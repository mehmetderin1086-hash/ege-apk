"""Öğretmenin hazırladığı cevap anahtarı dosyasını ``CevapAnahtari``'ya çevirir.

İki giriş biçimi vardır:

* **Basit tablo** (CSV/XLSX) — satır başına bir soru; ``soru_no`` zorunlu,
  ``cevap``/``rubrik`` sütunlarındaki satırlar ``formdan_anahtar_uret``'in
  bildiği gramerle ayrıştırılır ("A = 1" eşleştirmeleri dahil).
* **Tam şema** (JSON/YAML) — ``{"sorular": [{"no", "tip", "anahtar": {...}}]}``;
  ``anahtar`` alt nesnesi ``Soru`` modelinin kabul ettiği sözlükle birebirdir,
  yani eş anlamlılar, sayısal tolerans ve ``otomatik_puanlama`` da verilebilir.

Dosyada tek bir hata varsa **hiçbir soru uygulanmaz**: kısmen uygulanan bir
anahtar, öğretmenin gördüğü önizlemeyle depodaki durumu ayrıştırır ve sessiz
puan kaybı üretir.
"""

from __future__ import annotations

import csv
import io
import json
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from .anahtar_duzen import anahtar_satirlari, formdan_anahtar_uret
from .modeller import CevapAnahtari, RubrikKalemi, Sinav, SoruTipi, _TrLoader

DESTEKLENEN_UZANTILAR = {".csv", ".xlsx", ".json", ".yaml", ".yml"}

# Basit tablo başlıkları: öğretmen Excel'de Türkçe başlık yazar; eş adlar da
# kabul edilir ki şablonu birebir kopyalamak zorunda kalmasın.
_BASLIK_ESLERI = {
    "soru_no": "soru_no",
    "soru no": "soru_no",
    "soru": "soru_no",
    "no": "soru_no",
    "tip": "tip",
    "soru_tipi": "tip",
    "cevap": "cevap",
    "dogru_cevap": "cevap",
    "doğru_cevap": "cevap",
    "doğru cevap": "cevap",
    "anahtar": "cevap",
    "rubrik": "rubrik",
    "olcut": "rubrik",
    "ölçüt": "rubrik",
    "puan": "puan",
}


@dataclass
class AnahtarYuklemeSonucu:
    """Ayrıştırma çıktısı: uygulanacak anahtarlar + öğretmene gösterilecek notlar."""

    sorular: dict[int, tuple[SoruTipi, CevapAnahtari]] = field(
        default_factory=dict
    )
    hatalar: list[str] = field(default_factory=list)
    uyarilar: list[str] = field(default_factory=list)
    degismeyen: list[int] = field(default_factory=list)

    @property
    def uygulanabilir(self) -> bool:
        return not self.hatalar and bool(self.sorular)


def _basligi_coz(ham: str) -> str | None:
    return _BASLIK_ESLERI.get(str(ham or "").strip().casefold().replace("ı", "i"))


def _satirlari_oku(yol: Path) -> list[dict[str, str]]:
    """CSV/XLSX dosyasını başlıkları çözülmüş sözlük listesine çevirir."""
    if yol.suffix.casefold() == ".xlsx":
        from openpyxl import load_workbook

        calisma_kitabi = load_workbook(yol, read_only=True, data_only=True)
        try:
            sayfa = calisma_kitabi.active
            satirlar = list(sayfa.iter_rows(values_only=True))
        finally:
            calisma_kitabi.close()
        if not satirlar:
            return []
        basliklar = [_basligi_coz(x) for x in satirlar[0]]
        kayitlar = []
        for satir in satirlar[1:]:
            kayit = {
                baslik: ("" if hucre is None else str(hucre))
                for baslik, hucre in zip(basliklar, satir)
                if baslik
            }
            if any(v.strip() for v in kayit.values()):
                kayitlar.append(kayit)
        return kayitlar

    metin = yol.read_text(encoding="utf-8-sig")
    ornek = metin[:2048]
    try:
        ayrac = csv.Sniffer().sniff(ornek, delimiters=",;\t").delimiter
    except csv.Error:
        ayrac = ";" if ornek.count(";") > ornek.count(",") else ","
    # StringIO: Excel'in ürettiği tırnak içi satır sonlarını koruyan tek yol;
    # splitlines() çok satırlı rubrik hücresini fiziksel satırlara bölerdi.
    okuyucu = csv.reader(io.StringIO(metin), delimiter=ayrac)
    satirlar = [x for x in okuyucu if any(str(h).strip() for h in x)]
    if not satirlar:
        return []
    basliklar = [_basligi_coz(x) for x in satirlar[0]]
    return [
        {
            baslik: str(hucre)
            for baslik, hucre in zip(basliklar, satir)
            if baslik
        }
        for satir in satirlar[1:]
    ]


def _soru_numarasi(ham) -> int | None:
    """Tam sayı olan soru numarasını döndürür; kesirliyi kabul ETMEZ.

    ``int(float("1.9"))`` sessizce 1 verirdi; yanlış soruya anahtar yazmak
    yerine dosyayı reddetmek gerekir.
    """
    if isinstance(ham, bool):
        return None
    if isinstance(ham, int):
        return ham
    if isinstance(ham, float):
        return int(ham) if ham.is_integer() else None
    try:
        sayi = float(str(ham).strip().replace(",", "."))
    except ValueError:
        return None
    return int(sayi) if sayi.is_integer() else None


def _tip_coz(ham: str, varsayilan: SoruTipi) -> tuple[SoruTipi, str | None]:
    ham = str(ham or "").strip()
    if not ham:
        return varsayilan, None
    try:
        return SoruTipi(ham.casefold()), None
    except ValueError:
        return varsayilan, f"bilinmeyen soru tipi '{ham}', sınavdaki tip korundu"


def _tablodan_coz(yol: Path, sinav: Sinav) -> AnahtarYuklemeSonucu:
    sonuc = AnahtarYuklemeSonucu()
    try:
        kayitlar = _satirlari_oku(yol)
    except (OSError, ValueError, KeyError) as exc:
        sonuc.hatalar.append(f"Dosya okunamadı: {exc}")
        return sonuc
    if not kayitlar:
        sonuc.hatalar.append("Dosyada veri satırı bulunamadı.")
        return sonuc
    if not any("soru_no" in k for k in kayitlar):
        sonuc.hatalar.append(
            "'soru_no' sütunu bulunamadı. Başlık satırında soru_no, cevap ve "
            "rubrik sütunları beklenir."
        )
        return sonuc

    for sira, kayit in enumerate(kayitlar, start=2):
        ham_no = str(kayit.get("soru_no", "")).strip()
        if not ham_no:
            sonuc.hatalar.append(f"{sira}. satır: soru numarası boş.")
            continue
        no = _soru_numarasi(ham_no)
        if no is None:
            sonuc.hatalar.append(
                f"{sira}. satır: '{ham_no}' geçerli soru numarası değil."
            )
            continue
        if no in sonuc.sorular:
            sonuc.hatalar.append(f"{sira}. satır: {no}. soru dosyada birden fazla kez var.")
            continue
        try:
            soru = sinav.soru(no)
        except KeyError:
            sonuc.hatalar.append(f"{sira}. satır: sınavda {no}. soru yok.")
            continue

        tip, tip_uyarisi = _tip_coz(kayit.get("tip", ""), soru.tip)
        if tip_uyarisi:
            sonuc.uyarilar.append(f"{no}. soru: {tip_uyarisi}.")
        ham_metin = "\n".join(
            x for x in (kayit.get("cevap", ""), kayit.get("rubrik", "")) if x.strip()
        )
        satirlar = [
            parca.strip()
            for satir in anahtar_satirlari(ham_metin)
            for parca in satir.split("|")
            if parca.strip()
        ]
        if not satirlar:
            sonuc.hatalar.append(f"{sira}. satır: {no}. soru için cevap/rubrik boş.")
            continue
        ham_puan = str(kayit.get("puan", "")).strip()
        if ham_puan:
            try:
                if abs(float(ham_puan.replace(",", ".")) - soru.puan) > 1e-6:
                    sonuc.uyarilar.append(
                        f"{no}. soru: dosyadaki puan ({ham_puan}) sınavdaki "
                        f"puandan ({soru.puan:g}) farklı; sınav puanı geçerli."
                    )
            except ValueError:
                sonuc.uyarilar.append(f"{no}. soru: puan '{ham_puan}' sayı değil, yok sayıldı.")
        sonuc.sorular[no] = formdan_anahtar_uret(tip, soru.puan, satirlar)

    return sonuc


def _sozlukten_coz(veri: dict, sinav: Sinav) -> AnahtarYuklemeSonucu:
    sonuc = AnahtarYuklemeSonucu()
    if not isinstance(veri, dict) or not isinstance(veri.get("sorular"), list):
        sonuc.hatalar.append(
            "Beklenen şema: {\"sorular\": [{\"no\": 1, \"anahtar\": {...}}]}"
        )
        return sonuc

    for sira, ham in enumerate(veri["sorular"], start=1):
        if not isinstance(ham, dict):
            sonuc.hatalar.append(f"{sira}. kayıt nesne değil.")
            continue
        no = _soru_numarasi(ham.get("no"))
        if no is None:
            sonuc.hatalar.append(f"{sira}. kayıt: 'no' alanı geçerli bir sayı değil.")
            continue
        if no in sonuc.sorular:
            sonuc.hatalar.append(f"{no}. soru dosyada birden fazla kez var.")
            continue
        try:
            soru = sinav.soru(no)
        except KeyError:
            sonuc.hatalar.append(f"Sınavda {no}. soru yok.")
            continue

        tip, tip_uyarisi = _tip_coz(ham.get("tip", ""), soru.tip)
        if tip_uyarisi:
            sonuc.uyarilar.append(f"{no}. soru: {tip_uyarisi}.")
        ham_anahtar = ham.get("anahtar")
        if not isinstance(ham_anahtar, dict):
            sonuc.hatalar.append(f"{no}. soru: 'anahtar' nesnesi eksik.")
            continue
        try:
            anahtar = _anahtari_kur(ham_anahtar, soru.puan)
        except (TypeError, ValueError) as exc:
            sonuc.hatalar.append(f"{no}. soru: anahtar okunamadı ({exc}).")
            continue
        if not (
            anahtar.dogru_cevaplar
            or anahtar.rubrik
            or anahtar.siralama
            or anahtar.eslestirmeler
        ):
            sonuc.hatalar.append(f"{no}. soru: anahtar boş.")
            continue
        eksik = _tipe_uygunluk_hatasi(tip, anahtar)
        if eksik:
            sonuc.hatalar.append(f"{no}. soru: {eksik}")
            continue
        if not anahtar.otomatik_puanlama:
            sonuc.uyarilar.append(
                f"{no}. soru: dosyada otomatik puanlama kapatılmış; "
                "bu soru öğretmen incelemesine düşer."
            )
        sonuc.sorular[no] = (tip, anahtar)

    return sonuc


# CevapAnahtari'nin koleksiyon alanları. Metin gelirse dataclass bunu
# karakter karakter listeye çevirir ("ATP" → ['A','T','P']); böyle bir anahtar
# hata vermeden uygulanır ve sessizce yanlış puanlar. Tip burada doğrulanır.
_LISTE_ALANLARI = {
    "rubrik",
    "dogru_cevaplar",
    "kaynaklar",
    "kabul_edilen_alternatifler",
    "yaygin_hatalar",
    "yasak_celiskiler",
    "yontem_adimlari",
    "birimler",
    "siralama",
    "kaynak_kanitlari",
}


def _tipleri_denetle(ham: dict) -> None:
    for alan in _LISTE_ALANLARI:
        if alan in ham and not isinstance(ham[alan], list):
            raise ValueError(f"'{alan}' alanı liste olmalı")
    if "eslestirmeler" in ham and not isinstance(ham["eslestirmeler"], dict):
        raise ValueError("'eslestirmeler' alanı nesne olmalı")
    for kalem in ham.get("rubrik", []):
        if not isinstance(kalem, (str, dict, RubrikKalemi)):
            raise ValueError("rubrik kalemleri metin veya nesne olmalı")


def _tipe_uygunluk_hatasi(tip: SoruTipi, anahtar: CevapAnahtari) -> str | None:
    """Anahtarın soru tipinin gerektirdiği alanı taşıdığını doğrular.

    ``Soru.__post_init__`` bu kuralı zaten uyguluyor ama ValueError fırlatarak;
    ayrıştırma aşamasında yakalanmazsa öğretmen açıklayıcı bir hata yerine
    500 sayfası görür.
    """
    if tip in {SoruTipi.BOSLUK_DOLDURMA, SoruTipi.COKTAN_SECMELI}:
        if not anahtar.dogru_cevaplar:
            return (
                f"{tip.value} soruda kabul edilen cevap ('cevap' sütunu / "
                "'dogru_cevaplar') gerekli."
            )
        return None
    yapisal_hazir = (
        (tip == SoruTipi.SIRALAMA and bool(anahtar.siralama))
        or (tip == SoruTipi.ESLESTIRME and bool(anahtar.eslestirmeler))
        or (
            tip in {SoruTipi.SAYISAL, SoruTipi.FORMUL_ISPAT}
            and bool(anahtar.dogru_cevaplar)
        )
    )
    if not yapisal_hazir and not anahtar.rubrik:
        return f"{tip.value} soruda rubrik ölçütleri gerekli."
    return None


def _anahtari_kur(ham: dict, puan: float) -> CevapAnahtari:
    """Sözlükten CevapAnahtari kurar; rubrik puanı verilmemişse eşit böler."""
    _tipleri_denetle(ham)
    ham_rubrik = list(ham.get("rubrik", []))
    kalemler: list[RubrikKalemi] = []
    if ham_rubrik:
        varsayilan_puan = puan / len(ham_rubrik)
        for kalem in ham_rubrik:
            if isinstance(kalem, RubrikKalemi):
                kalemler.append(kalem)
            elif isinstance(kalem, dict):
                veri = dict(kalem)
                veri.setdefault("metin", veri.pop("olcut", ""))
                veri.setdefault("puan", varsayilan_puan)
                kalemler.append(RubrikKalemi(**veri))
            else:
                kalemler.append(RubrikKalemi(metin=str(kalem), puan=varsayilan_puan))
    veri = {k: v for k, v in ham.items() if k != "rubrik"}
    # Öğretmenin hazırladığı dosya kendi verisidir: üretim yöntemi ve onay
    # durumu burada sabitlenir, dosyadaki değerler bunu ezemez (otomatik
    # üretilmiş bir anahtarın kendini "öğretmen onaylı" ilan etmesini önler).
    veri.pop("otomatik_uretildi", None)
    veri.pop("onay_durumu", None)
    veri.setdefault("uretim_yontemi", "Öğretmen · dosyadan yüklendi")
    return CevapAnahtari(
        rubrik=kalemler,
        otomatik_uretildi=False,
        onay_durumu="onayli",
        **veri,
    )


def dosyadan_anahtar_uret(yol: str | Path, sinav: Sinav) -> AnahtarYuklemeSonucu:
    """Anahtar dosyasını okur; hata varsa hiçbir soruyu uygulanabilir bırakmaz."""
    yol = Path(yol)
    uzanti = yol.suffix.casefold()
    if uzanti not in DESTEKLENEN_UZANTILAR:
        return AnahtarYuklemeSonucu(
            hatalar=[
                f"Desteklenmeyen dosya türü '{uzanti or yol.name}'. "
                "CSV, XLSX, JSON veya YAML yükleyin."
            ]
        )

    if uzanti in {".csv", ".xlsx"}:
        sonuc = _tablodan_coz(yol, sinav)
    else:
        try:
            ham_metin = yol.read_text(encoding="utf-8")
            if uzanti == ".json":
                veri = json.loads(ham_metin)
            else:
                # _TrLoader: "no:" anahtarının YAML 1.1'de boolean'a düşmesini
                # engeller; soru numaraları bu alanda taşınıyor.
                veri = yaml.load(ham_metin, Loader=_TrLoader)
        except (OSError, ValueError, yaml.YAMLError) as exc:
            return AnahtarYuklemeSonucu(hatalar=[f"Dosya okunamadı: {exc}"])
        sonuc = _sozlukten_coz(veri, sinav)

    if sonuc.hatalar:
        # Ya hep ya hiç: kısmi uygulama önizlemeyle depoyu ayrıştırır.
        sonuc.sorular = {}
        sonuc.degismeyen = []
        return sonuc
    if not sonuc.sorular:
        sonuc.hatalar.append("Dosyadan uygulanabilir anahtar çıkarılamadı.")
        return sonuc
    sonuc.degismeyen = sorted(
        s.no for s in sinav.sorular if s.no not in sonuc.sorular
    )
    if sonuc.degismeyen:
        sonuc.uyarilar.append(
            f"{len(sonuc.degismeyen)} soru dosyada yok; mevcut anahtarları korunacak: "
            + ", ".join(str(x) for x in sonuc.degismeyen)
        )
    return sonuc
