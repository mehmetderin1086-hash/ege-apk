"""Webapp router modüllerinin paylaştığı durum sözleşmesi.

`uygulama_kur` fabrikası tek bir `WebBaglam` kurar; her router modülü
`rota_kur(baglam) -> APIRouter` imzasıyla yalnız bu nesneye bağımlıdır.
Modül düzeyi global tutulmaz (test yalıtımı bozulur); tüm paylaşılan durum
bu dataclass'ın alanlarıdır. Fabrika içindeki ortak yardımcılar, tüketicileri
router modüllerine taşındıkça buraya BİREBİR (davranış değiştirmeden) metod
olarak alınır.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable
from uuid import uuid4

from fastapi import HTTPException, UploadFile
from fastapi.templating import Jinja2Templates

from ..depo import Depo
from ..yeniden_puanlama import kutuyu_yeniden_puanla


def _yedekli_uretici(birincil: Callable, yedek: Callable) -> Callable:
    """Birincil üretici hata verirse yedeğe düşen sarmalayıcı.

    ``rag_anahtar`` üretici hatasını yakalayıp puanlanamayan taslak yazıyor;
    bu sarmalayıcı olmadan bozuk bir yerel motor, çalışan bulut sağlayıcısını
    sessizce gölgeler ve öğretmen hiçbir soruda rubrik alamazdı.
    """

    def uret(sorular, **ayarlar):
        from ..yapay_zeka import YapayZekaHatasi

        try:
            return birincil(sorular, **ayarlar)
        except YapayZekaHatasi:
            return yedek(sorular, **ayarlar)

    return uret


def _anahtar_ozeti(soru) -> str:
    """Öğrenciye gösterilecek sade doğru cevap özeti (soru tipine göre)."""
    from ..modeller import SoruTipi

    a = soru.anahtar
    if soru.tip in {SoruTipi.BOSLUK_DOLDURMA, SoruTipi.COKTAN_SECMELI,
                    SoruTipi.SAYISAL, SoruTipi.FORMUL_ISPAT}:
        return a.dogru_cevaplar[0] if a.dogru_cevaplar else (a.ornek_cevap or "")
    if soru.tip == SoruTipi.SIRALAMA and a.siralama:
        return " → ".join(a.siralama)
    if soru.tip == SoruTipi.ESLESTIRME and a.eslestirmeler:
        return " · ".join(f"{k} → {v}" for k, v in a.eslestirmeler.items())
    if a.ornek_cevap:
        return a.ornek_cevap
    if a.rubrik:
        return " · ".join(k.metin for k in a.rubrik)
    return a.dogru_cevaplar[0] if a.dogru_cevaplar else ""


@dataclass
class WebBaglam:
    depo: Depo
    sablonlar: Jinja2Templates
    kirp_kok: Path
    veri_kok: Path
    sinav_dizini: Path
    yukleme_dizini: Path
    serbest_taslak_dizini: Path
    referans_kok: Path
    referans_kaynak_dizini: Path
    referans_indeks_dizini: Path
    toplu_sonuc_dizini: Path
    entegrasyon_dizini: Path
    proje_kok: Path
    model_yollari: dict[str, Path]
    taniyici_onbellegi: dict[str, object] = field(default_factory=dict)
    taniyici_fabrikasi: Callable | None = None
    serbest_cozumleyici: Callable | None = None
    # Testlerin gerçek biyo-cozucu sunucusuna dokunmadan üretici/motor
    # davranışını enjekte edebilmesi için (taniyici_fabrikasi deseni).
    yerel_uretici: Callable | None = None
    yerel_uret: Callable | None = None
    # Anlamsal puanlama gömlemcisi tembel yüklenir; None sonucu da
    # önbelleklenir ki sentence-transformers yoksa her istek yeniden denemesin.
    _gomlemci_onbellegi: list = field(default_factory=list)

    def gomlemci(self):
        """Anlamsal rubrik puanlaması için gömlemci (kapalıysa None).

        **Varsayılan kapalıdır.** Gömlemci açık uçlu cevaplarda kısmi puanı
        iyileştirir, ama arayüz bugüne dek hep sözcüksel puanladı: açık
        gelseydi öğretmen başka bir sorunun anahtarına dokunduğunda, elle
        değiştirilmemiş eski kutular yeni algoritmayla sessizce kayardı.
        ``SINAV_OKUR_GOMLEMCI=acik`` ile bilinçli olarak açılır; etkisi
        anahtar önizlemesinde görülebilir.
        """
        if self._gomlemci_onbellegi:
            return self._gomlemci_onbellegi[0]
        if (
            os.environ.get("SINAV_OKUR_GOMLEMCI", "kapali").strip().casefold()
            != "acik"
        ):
            self._gomlemci_onbellegi.append(None)
            return None
        try:
            from ..puanlama.gomme import gomlemci_yukle

            gomlemci = gomlemci_yukle()
        except (ImportError, OSError, ValueError):
            gomlemci = None
        self._gomlemci_onbellegi.append(gomlemci)
        return gomlemci

    def _kirp_url(self, yol: str | None) -> str | None:
        if not yol:
            return None
        try:
            return "/kirpinti/" + str(
                Path(yol).resolve().relative_to(self.kirp_kok.resolve())
            )
        except ValueError:
            return None

    def _kutu_metnini_otomatik_puanla(self, kutu, sinav, metin: str) -> None:
        kutuyu_yeniden_puanla(
            self.depo,
            sinav,
            kutu,
            metin,
            referans_indeks_dizini=self.referans_indeks_dizini,
            gomlemci=self.gomlemci(),
        )

    def _geri_bildirim_kagidi(
        self, kagit_id: int, gorsel: bool, *, sinav=None, kazanim=None
    ) -> dict:
        """Tek kâğıdın geri bildirim verisi.

        ``sinav`` ve ``kazanim`` dışarıdan verilebilir: sınıf listesi ekranı
        bunları döngü dışında BİR KEZ hesaplayıp geçirir. Aksi hâlde her
        kâğıt için tüm sınavın cevapları yeniden okunuyordu (N kâğıt =
        N tam tarama).
        """
        kagit = self.depo.kagit(kagit_id)
        if kagit is None:
            raise HTTPException(404, "Kâğıt bulunamadı")
        if sinav is None:
            sinav = self.depo.sinav_yukle(kagit["sinav_kimlik"])
        sorular = []
        for b in self.depo.kutular(kagit_id):
            soru = sinav.soru(b["soru_no"])
            sorular.append({
                "soru": soru,
                "cevap": (
                    b["duzeltilmis_metin"]
                    if b["duzeltilmis_metin"] is not None else b["taninan_metin"]
                ) or "",
                "puan": b["son_puan"] if b["son_puan"] is not None else b["otomatik_puan"],
                "max_puan": b["max_puan"],
                "dogru_cevap": _anahtar_ozeti(soru),
                "aciklama": b["aciklama"] or "",
                "kirp_url": self._kirp_url(b["kirp_yolu"]) if gorsel else None,
            })
        sorular.sort(key=lambda s: s["soru"].no)
        toplam, maxp = self.depo.kagit_toplam(kagit_id)
        # Bu öğrencinin %60 altında kaldığı kazanımlar: "neyi tekrar etmeli".
        if kazanim is None:
            from ..analiz import kazanim_analizi

            kazanim = kazanim_analizi(self.depo, sinav)
        zayif_kazanimlar = next(
            (
                o["zayif"]
                for o in kazanim["ogrenciler"]
                if o["kagit_id"] == kagit_id
            ),
            [],
        )
        return {
            "kagit": kagit, "sinav": sinav, "sorular": sorular,
            "toplam": toplam, "max": maxp,
            "yuzde": (toplam / maxp * 100) if maxp else 0,
            "taslak": not kagit["onaylandi"],
            "zayif_kazanimlar": zayif_kazanimlar,
        }

    def _kalibrasyon_durumu(self) -> dict:
        yol = self.proje_kok / "modeller/ocr_kalibrasyon.json"
        durum: dict = {
            "var": yol.is_file(),
            "bekleyen": len(self.depo.kalibrasyon_ornekleri()),
        }
        if yol.is_file():
            try:
                durum.update(json.loads(yol.read_text(encoding="utf-8")))
            except (ValueError, OSError):
                pass
            metrik = yol.with_suffix(".metrikler.json")
            if metrik.is_file():
                try:
                    m = json.loads(metrik.read_text(encoding="utf-8"))
                    durum["ece"] = m.get("ece")
                    durum["brier"] = m.get("brier")
                except (ValueError, OSError):
                    pass
        return durum

    def _serbest_mi(self, sablon_yolu: str | Path | None) -> bool:
        if not sablon_yolu:
            return False
        try:
            veri = json.loads(Path(sablon_yolu).read_text(encoding="utf-8"))
            return veri.get("tur") == "serbest_v1"
        except (OSError, json.JSONDecodeError, AttributeError):
            return False

    def _uretici_sec(self) -> tuple[Callable, bool, str]:
        """SINAV_OKUR_ANAHTAR_URETICI sırasına göre (uretici, hazir, ad) seç.

        Öncelik: yerel motor (biyo-cozucu) → Claude API → çıkarımsal taslak.
        Hiçbiri hazır değilse rag_anahtar zaten puanlanamayan taslağa düşer.
        """
        from .. import yerel_motor
        from ..yapay_zeka import cevap_anahtarlari_uret, claude_api_durumu

        yerel = self.yerel_uretici or yerel_motor.yerel_cevap_anahtarlari_uret
        tercih = (
            os.environ.get("SINAV_OKUR_ANAHTAR_URETICI", "otomatik")
            .strip()
            .casefold()
        )
        yerel_ad = "yerel model (biyo-cozucu)"
        bulut_ad = "kaynakla sınırlandırılmış model"
        if tercih == "yerel":
            if self.yerel_uretici is not None:
                return yerel, True, yerel_ad
            durum = yerel_motor.yerel_motor_durumu()
            return yerel, bool(durum["kullanilabilir"]), yerel_ad
        if tercih == "bulut":
            return cevap_anahtarlari_uret, claude_api_durumu()["hazir"], bulut_ad
        if self.yerel_uretici is not None:
            return yerel, True, yerel_ad
        durum = yerel_motor.yerel_motor_durumu()
        if durum["kullanilabilir"]:
            if claude_api_durumu()["hazir"]:
                # Yerel motor kurulu görünüp de üretemiyorsa (model eksik,
                # sunucu çökmüş) çalışan bulut sağlayıcısı varken her soruyu
                # puanlanamaz taslağa düşürmek yerine ona düşülür.
                return (
                    _yedekli_uretici(yerel, cevap_anahtarlari_uret),
                    True,
                    f"{yerel_ad} · gerekirse {bulut_ad}",
                )
            return yerel, True, yerel_ad
        return cevap_anahtarlari_uret, claude_api_durumu()["hazir"], bulut_ad

    def _rag_anahtarlari_uret(
        self, sorular: list[tuple[int, str, float]], *, ders: str = ""
    ):
        """Düzeltilmiş soru metinlerinden kaynaklı, güvenlik kapılı anahtar üret."""
        from ..rag_anahtar import rag_anahtarlari_uret

        uretici, hazir, uretici_adi = self._uretici_sec()
        return rag_anahtarlari_uret(
            self.referans_indeks_dizini,
            sorular,
            ders=ders,
            uretici=uretici,
            uretici_hazir=hazir,
            uretim_yontemi=f"Yerel kitap RAG + {uretici_adi}",
        )

    def _kayitli_dosya(self, kimlik: str, alan: str) -> Path:
        kayit = self.depo.sinav_dosyasi(kimlik)
        if not kayit or not kayit[alan]:
            raise HTTPException(404, "Dosya bulunamadı")
        yol = Path(kayit[alan]).resolve()
        try:
            yol.relative_to(self.veri_kok.resolve())
        except ValueError as exc:
            raise HTTPException(403, "Dosya güvenli uygulama dizininin dışında") from exc
        if not yol.is_file():
            raise HTTPException(404, "Dosya bulunamadı")
        return yol

    def _anahtari_uygula(self, kimlik: str, yeni) -> tuple[int, int]:
        """Yeni anahtarı sürümleyip kâğıtları yeniden puanlar.

        Öğretmenin elle verdiği istisna puanlar korunur: anahtarın bambaşka
        bir sorusunu düzeltmek, gözle verilmiş bir puanı sessizce silmemeli.
        ``(guncellenen, korunan)`` döndürür.
        """
        # sinav_kaydet sürümlemeyi ve denetim kaydını kendisi yapıyor.
        self.depo.sinav_kaydet(yeni)
        dosya_kaydi = self.depo.sinav_dosyasi(kimlik)
        if dosya_kaydi and dosya_kaydi["yaml_yolu"]:
            try:
                yeni.yaml_kaydet(dosya_kaydi["yaml_yolu"])
            except OSError:
                pass  # YAML yazılamazsa depo yine de kaynak doğrudur
        guncellenen = korunan = 0
        for kagit in self.depo.kagitlar(kimlik):
            for kutu in self.depo.kutular(kagit["id"]):
                otomatik = kutu["otomatik_puan"]
                son = kutu["son_puan"]
                if (
                    otomatik is not None
                    and son is not None
                    and abs(float(son) - float(otomatik)) > 1e-6
                ):
                    korunan += 1
                    continue
                metin = (
                    kutu["duzeltilmis_metin"]
                    if kutu["duzeltilmis_metin"] is not None
                    else kutu["taninan_metin"] or ""
                )
                self._kutu_metnini_otomatik_puanla(kutu, yeni, metin)
                guncellenen += 1
            self.depo.kagit_onayini_kaldir(kagit["id"])
        return guncellenen, korunan

    def _yerel_motor_durumu(self) -> dict:
        from ..yerel_motor import yerel_motor_durumu

        return yerel_motor_durumu()

    def _yerel_rag_durumu(self) -> dict:
        from ..bioprof import bioprof_durumu
        from ..referans import YerelRAGDeposu

        bioprof = bioprof_durumu()
        yerel_motor = self._yerel_motor_durumu()
        if not YerelRAGDeposu.hazir_mi(self.referans_indeks_dizini):
            return {
                "hazir": False,
                "kitap": 0,
                "pasaj": 0,
                "mesaj": "Kaynaklı otomatik puanlama için önce biyoloji kitabı yükleyin.",
                "bioprof": bioprof,
                "yerel_motor": yerel_motor,
            }
        depo_rag = YerelRAGDeposu.yukle(self.referans_indeks_dizini)
        durum = depo_rag.durum()
        durum["mesaj"] = (
            f"{durum['kitap']} kitap · {durum['pasaj']} yerel pasaj · API/token yok"
        )
        durum["bioprof"] = bioprof
        durum["yerel_motor"] = yerel_motor
        return durum

    async def _yuklemeyi_kaydet(
        self,
        dosya: UploadFile,
        hedef_dizin: Path,
        izinli_uzantilar: set[str],
        *,
        azami_bayt: int = 80 * 1024 * 1024,
    ) -> Path:
        uzanti = Path(dosya.filename or "").suffix.lower()
        if uzanti not in izinli_uzantilar:
            raise ValueError(
                f"Desteklenmeyen dosya türü: {uzanti or 'uzantısız'}. "
                f"İzin verilenler: {', '.join(sorted(izinli_uzantilar))}"
            )
        hedef_dizin.mkdir(parents=True, exist_ok=True)
        hedef = hedef_dizin / f"{uuid4().hex}{uzanti}"
        toplam = 0
        try:
            with hedef.open("wb") as f:
                while parca := await dosya.read(1024 * 1024):
                    toplam += len(parca)
                    if toplam > azami_bayt:
                        raise ValueError("Dosya 80 MB sınırını aşıyor.")
                    f.write(parca)
        except Exception:
            hedef.unlink(missing_ok=True)
            raise
        finally:
            await dosya.close()
        if toplam == 0:
            hedef.unlink(missing_ok=True)
            raise ValueError("Yüklenen dosya boş.")
        return hedef
