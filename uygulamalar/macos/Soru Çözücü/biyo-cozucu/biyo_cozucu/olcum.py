"""Yeniden üretilebilir ölçüm koşusu ve koşular arası fark raporu.

Bu modül olmadan "sistem iyileşti mi?" sorusu cevaplanamıyordu: doğruluk elle
`degerlendir` komutuyla ölçülüyor, sonuç ekrana basılıyor, `kosu` tablosu boş
kalıyordu. İki koşuyu karşılaştırmak için üç şey gerekiyor ve üçü de burada:

1. **Sabit dilim.** `veri.disa_aktar.bol()` test dilimini soru imzasından
   türetiyor, yani örnek eklendikçe dilim BÜYÜYOR. İki koşu farklı soru
   kümesi gördüğünde aradaki fark iyileşme değil bileşim değişimidir.
   `Dilim` manifesti bölmenin bir anını dondurur; `bol()` değişmez.

2. **Soru bazlı kayıt.** Toplam doğruluk hangi sorunun kazanıldığını
   söylemez. Her sorunun sonucu ayrı saklanıyor, anahtar `metin.imza(soru)`
   — `ornek_id` değil, çünkü jsonl'den yüklenen örneklerde kimlik `None`
   olabiliyor ve kimlikler makineler arası taşınmıyor.

3. **Eşli istatistik.** 124 soruluk bir koşuda doğruluğun binom standart
   sapması ≈ %4,5. Ham farka bakmak, gürültüyü iyileşme sanmaya davetiye.
   Eşleşmiş koşularda doğru sınama McNemar'dır (bkz. `Fark.mcnemar`).
"""

from __future__ import annotations

import json
import shutil
import subprocess
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path

from .degerlendirme import KosuOzeti
from .metin import imza as metin_imzasi
from .modeller import Ornek

OLCUM_DIZINI = "olcumler"
DILIM_DIZINI = "olcumler"

# McNemar için ki-kare eşiği: p < 0,05 (1 serbestlik derecesi).
KI_KARE_ESIGI = 3.841
# Sınamanın anlamlı sayılması için gereken asgari değişen soru sayısı.
ASGARI_DEGISEN = 10


def _simdi() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def kod_surumu(kok: Path) -> str:
    """Çalışan kodun git kısa kimliği; depo yoksa boş.

    Ölçüm kaydına giriyor: aylar sonra bir koşuya bakıldığında hangi kodun
    ölçüldüğü bilinmezse kayıt yalnız bir sayı yığınıdır.
    """
    git = shutil.which("git")
    if not git:
        return ""
    try:
        sonuc = subprocess.run(  # noqa: S603  (sabit argüman, kullanıcı girdisi yok)
            [git, "rev-parse", "--short", "HEAD"],
            cwd=kok, capture_output=True, text=True, timeout=5, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return sonuc.stdout.strip() if sonuc.returncode == 0 else ""


# --- dondurulmuş dilim ---


@dataclass(frozen=True)
class Dilim:
    """Ölçümün üzerinde koşacağı sabit soru kümesi."""

    ad: str
    imzalar: tuple[str, ...]
    olusturma: str = ""
    aciklama: str = ""

    def imza(self) -> str:
        """Manifestin kendi özeti — iki koşunun aynı dilimi gördüğünü kanıtlar."""
        import hashlib

        govde = "\n".join(sorted(self.imzalar))
        return hashlib.sha256(govde.encode("utf-8")).hexdigest()[:16]

    @classmethod
    def ornekelerden(
        cls, ornekler: list[Ornek], ad: str, *, aciklama: str = ""
    ) -> Dilim:
        return cls(
            ad=ad,
            imzalar=tuple(sorted(metin_imzasi(o.soru) for o in ornekler)),
            olusturma=_simdi(),
            aciklama=aciklama,
        )

    @classmethod
    def yukle(cls, yol: Path) -> Dilim:
        veri = json.loads(Path(yol).read_text(encoding="utf-8"))
        return cls(
            ad=str(veri.get("ad") or Path(yol).stem),
            imzalar=tuple(veri.get("imzalar") or ()),
            olusturma=str(veri.get("olusturma") or ""),
            aciklama=str(veri.get("aciklama") or ""),
        )

    def yaz(self, kok: Path) -> Path:
        dizin = Path(kok) / DILIM_DIZINI
        dizin.mkdir(parents=True, exist_ok=True)
        yol = dizin / f"{self.ad}.json"
        yol.write_text(
            json.dumps(
                {
                    "ad": self.ad,
                    "olusturma": self.olusturma,
                    "aciklama": self.aciklama,
                    "imza": self.imza(),
                    "imzalar": list(self.imzalar),
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        return yol

    def cozumle(self, ornekler: list[Ornek]) -> tuple[list[Ornek], list[str]]:
        """Manifest imzalarını gerçek örneklere çevirir; (bulunan, eksik) döner.

        Sıra manifestteki sıradır, örnek havuzundaki değil: koşu sırası
        değişirse önbellek ve model takas davranışı değişir ve iki koşu
        birebir kıyaslanamaz.
        """
        havuz = {metin_imzasi(o.soru): o for o in ornekler}
        bulunan: list[Ornek] = []
        eksik: list[str] = []
        for imza in self.imzalar:
            ornek = havuz.get(imza)
            if ornek is None:
                eksik.append(imza)
            else:
                bulunan.append(ornek)
        return bulunan, eksik


# --- ölçüm kaydı ---


@dataclass
class SoruSonucu:
    imza: str
    soru: str
    tur: str
    beklenen: str
    uretilen: str
    dogru: bool
    guven: float
    yontem: str


@dataclass
class OlcumKaydi:
    etiket: str
    zaman: str
    model: str
    dilim: str
    dilim_imzasi: str
    kod_surumu: str
    ayarlar: dict
    ozet: dict
    tur_bazli: dict
    risk_kapsama: list
    hedef_esigi: list | None
    sorular: list[SoruSonucu] = field(default_factory=list)
    # Üretim yolu başına doğruluk/güven. Eski kayıtlarda yok — `oku` bilinmeyen
    # alanı zaten eliyor, varsayılan boş sözlük geriye dönük uyumu koruyor.
    yontem_bazli: dict = field(default_factory=dict)

    @classmethod
    def ozetten(
        cls,
        ozet: KosuOzeti,
        *,
        etiket: str,
        model: str,
        dilim: Dilim,
        kod: str = "",
        ayarlar: dict | None = None,
    ) -> OlcumKaydi:
        hedef = ozet.hedef_esigi()
        return cls(
            etiket=etiket,
            zaman=_simdi(),
            model=model,
            dilim=dilim.ad,
            dilim_imzasi=dilim.imza(),
            kod_surumu=kod,
            ayarlar=dict(ayarlar or {}),
            ozet={
                "toplam": ozet.toplam,
                "dogru": ozet.dogru,
                "dogruluk": round(ozet.dogruluk, 4),
                "ortalama_ortusme": ozet.ortalama_ortusme,
                "ortalama_guven": ozet.ortalama_guven,
                "inceleme_orani": round(ozet.inceleme_orani, 4),
            },
            tur_bazli=ozet.tur_bazli,
            risk_kapsama=ozet.risk_kapsama(),
            hedef_esigi=list(hedef) if hedef else None,
            yontem_bazli=ozet.yontem_bazli(),
            sorular=[
                SoruSonucu(
                    imza=metin_imzasi(s.soru),
                    soru=" ".join(s.soru.split())[:80],
                    tur=s.cozum_turu,
                    beklenen=s.beklenen_cevap,
                    uretilen=s.uretilen_cevap,
                    dogru=bool(s.cevap_dogru),
                    guven=round(float(s.guven), 4),
                    yontem=s.uretim_yontemi,
                )
                for s in ozet.sonuclar
            ],
        )

    def dosya_adi(self) -> str:
        gun = (self.zaman or _simdi())[:10]
        return f"{gun}-{self.etiket}.json"

    def yaz(self, kok: Path) -> Path:
        dizin = Path(kok) / OLCUM_DIZINI
        dizin.mkdir(parents=True, exist_ok=True)
        yol = dizin / self.dosya_adi()
        # Aynı gün aynı etiketle ikinci koşu önceki kaydın ÜZERİNE YAZMAMALI:
        # ölçümün değeri geçmişte, tek bir anlık görüntüde değil.
        sayac = 2
        while yol.exists():
            yol = dizin / f"{yol.stem.split('#')[0]}#{sayac}.json"
            sayac += 1
        yol.write_text(
            json.dumps(asdict(self), ensure_ascii=False, indent=2), encoding="utf-8"
        )
        return yol

    @classmethod
    def oku(cls, yol: Path) -> OlcumKaydi:
        veri = json.loads(Path(yol).read_text(encoding="utf-8"))
        sorular = [SoruSonucu(**s) for s in veri.get("sorular") or []]
        veri["sorular"] = sorular
        bilinen = set(cls.__dataclass_fields__)
        return cls(**{a: d for a, d in veri.items() if a in bilinen})

    def sonuc_haritasi(self) -> dict[str, SoruSonucu]:
        return {s.imza: s for s in self.sorular}


def kayitlari_listele(kok: Path) -> list[Path]:
    dizin = Path(kok) / OLCUM_DIZINI
    if not dizin.is_dir():
        return []
    # Dilim manifestleri aynı dizinde duruyor ama ölçüm kaydı değil; ayırt
    # edici alan `sorular`. Ada göre ayırmak kırılgan olurdu.
    yollar = []
    for yol in sorted(dizin.glob("*.json")):
        try:
            veri = json.loads(yol.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(veri, dict) and "sorular" in veri:
            yollar.append(yol)
    return yollar


def son_kayit(kok: Path, *, haric: Path | None = None) -> OlcumKaydi | None:
    """En son yazılmış ölçüm kaydı (zaman damgasına göre)."""
    adaylar = [y for y in kayitlari_listele(kok) if haric is None or y != haric]
    if not adaylar:
        return None
    kayitlar = []
    for yol in adaylar:
        try:
            kayitlar.append(OlcumKaydi.oku(yol))
        except (OSError, ValueError, TypeError):
            continue
    if not kayitlar:
        return None
    return max(kayitlar, key=lambda k: k.zaman)


# --- fark ---


@dataclass
class Fark:
    onceki: str
    yeni: str
    dogruluk_onceki: float
    dogruluk_yeni: float
    kazanilan: list[SoruSonucu]
    kaybedilen: list[SoruSonucu]
    tur_farki: dict[str, tuple[float, float, int]]
    yontem_dagilimi: dict[str, tuple[int, int]]
    ortak: int
    yeni_sorular: list[str]
    dusen_sorular: list[str]
    dilim_uyusuyor: bool
    # Kapı kararı BU ikisine bakar: iki koşunun ORTAK sorularındaki doğruluk.
    # Başlıktaki `dogruluk_*` koşuların kendi paydalarından gelir; `--limit 50`
    # ile koşulan bir ölçüm 125 soruluk bir kayıtla kıyaslandığında bu iki
    # sayı farklı kümeleri ölçer ve sahte gerileme (ya da sahte iyileşme) verir.
    ortak_dogruluk_onceki: float = 0.0
    ortak_dogruluk_yeni: float = 0.0
    kosu_boyutu_onceki: int = 0
    kosu_boyutu_yeni: int = 0
    # `sorunlar()` doldurur: eşiğin altında kaldığı için kırmızı yakmayan,
    # ama yine de gerileyen türler. Sessizce kaybolmasınlar diye raporlanır.
    az_ornekli_gerilemeler: list[str] = field(default_factory=list)

    def mcnemar(self) -> tuple[int, int, float]:
        """(kazanılan, kaybedilen, ki-kare). Değişen soru azsa ki-kare `nan`.

        Neden gerekli: 124 soruda doğruluğun binom standart sapması ≈ %4,5.
        "Doğruluk %51'den %55'e çıktı" tek başına gürültüden ayırt edilemez.
        Eşleşmiş tasarımda bilgi, TOPLAM doğrulukta değil hangi soruların yön
        değiştirdiğindedir: yalnız b (kazanılan) ve c (kaybedilen) sayılır,
        ikisinde de aynı kalan sorular sınamaya girmez.

        Süreklilik düzeltmeli biçim: χ² = (|b−c| − 1)² / (b + c).
        """
        b, c = len(self.kazanilan), len(self.kaybedilen)
        if b + c < ASGARI_DEGISEN:
            return b, c, float("nan")
        ki_kare = (abs(b - c) - 1) ** 2 / (b + c)
        return b, c, round(ki_kare, 3)

    def anlamli_mi(self) -> bool:
        _b, _c, ki_kare = self.mcnemar()
        return ki_kare == ki_kare and ki_kare > KI_KARE_ESIGI  # NaN != NaN

    def gerileme(
        self,
        *,
        tolerans: float = 0.03,
        tur_toleransi: float = 0.10,
        asgari_tur_ornegi: int = 8,
    ) -> list[str]:
        """Kapıdan geçemeyecek düşüşler; boş liste = temiz."""
        sorunlar: list[str] = []
        if not self.dilim_uyusuyor:
            sorunlar.append(
                "Koşular farklı dilimlerde yapılmış — fark karşılaştırılabilir değil."
            )
        dusus = self.ortak_dogruluk_onceki - self.ortak_dogruluk_yeni
        if dusus > tolerans:
            sorunlar.append(
                f"Ortak sorularda doğruluk {self.ortak_dogruluk_onceki:.1%} → "
                f"{self.ortak_dogruluk_yeni:.1%} "
                f"({dusus:.1%} düşüş, tolerans {tolerans:.1%})."
            )
        atlanan = []
        for tur, (once, sonra, adet) in sorted(self.tur_farki.items()):
            # Az örnekli türde birkaç sorunun yön değiştirmesi büyük yüzde
            # oynaması yaratır; bunu gerileme saymak kapıyı gürültüye açar.
            if adet < asgari_tur_ornegi:
                # Ama SESSİZ atlamak daha kötü: ölçümdeki en zayıf tür
                # (grafik_yorumlama, 7 örnek) tam da bu eşiğin altında kalıp
                # kapının hiç bakmadığı yer oldu. Gerileme kırmızı olmasa da
                # görünür: mutlak soru sayısıyla, yön değiştirenler sayılarak.
                if once - sonra > tur_toleransi:
                    dusen = round((once - sonra) * adet)
                    atlanan.append(f"{tur} ({adet} örnek, ~{dusen} soru geriledi)")
                continue
            if once - sonra > tur_toleransi:
                sorunlar.append(
                    f"{tur}: {once:.0%} → {sonra:.0%} ({adet} örnek)."
                )
        if atlanan:
            self.az_ornekli_gerilemeler = atlanan
        return sorunlar

    def rapor(self) -> str:
        b, c, ki_kare = self.mcnemar()
        satirlar = [
            f"Fark: {self.onceki} → {self.yeni}",
            f"Doğruluk: {self.dogruluk_onceki:.1%} → {self.dogruluk_yeni:.1%} "
            f"({self.dogruluk_yeni - self.dogruluk_onceki:+.1%})",
            f"Ortak soru: {self.ortak} · kazanılan {b} · kaybedilen {c}",
        ]
        if ki_kare != ki_kare:  # NaN
            satirlar.append(
                f"McNemar: değişen soru {b + c} < {ASGARI_DEGISEN} — "
                "sınama anlamlı değil, fark gürültü olabilir."
            )
        else:
            karar = "ANLAMLI (p<0,05)" if ki_kare > KI_KARE_ESIGI else "anlamsız"
            satirlar.append(f"McNemar χ² = {ki_kare} → {karar}")
        if self.kosu_boyutu_onceki != self.kosu_boyutu_yeni:
            satirlar.append(
                f"UYARI: koşu boyutları farklı ({self.kosu_boyutu_onceki} → "
                f"{self.kosu_boyutu_yeni}); başlıktaki doğruluklar farklı "
                f"paydalardan. Kapı kararı ortak {self.ortak} soruya bakıyor: "
                f"{self.ortak_dogruluk_onceki:.1%} → {self.ortak_dogruluk_yeni:.1%}."
            )
        if self.az_ornekli_gerilemeler:
            satirlar.append(
                "Eşik altı türlerde gerileme (kırmızı yakmaz, izlenmeli): "
                + "; ".join(self.az_ornekli_gerilemeler)
            )
        if not self.dilim_uyusuyor:
            satirlar.append("UYARI: koşular farklı dilimlerde — kıyas geçersiz.")
        if self.tur_farki:
            satirlar.append("Çözüm türü bazında:")
            for tur, (once, sonra, adet) in sorted(
                self.tur_farki.items(), key=lambda x: -x[1][2]
            ):
                ok = "→" if abs(sonra - once) < 1e-9 else ("↑" if sonra > once else "↓")
                satirlar.append(
                    f"  {tur:22s} {once:>4.0%} {ok} {sonra:>4.0%}  ({adet} örnek)"
                )
        if self.yontem_dagilimi:
            satirlar.append("Üretim yöntemi (önce → sonra):")
            for yontem, (once, sonra) in sorted(self.yontem_dagilimi.items()):
                satirlar.append(f"  {yontem:22s} {once:>4d} → {sonra:>4d}")
        if self.kazanilan:
            satirlar.append(f"Kazanılan sorular ({len(self.kazanilan)}):")
            satirlar.extend(
                f"  + [{s.tur}] {s.soru}  (→ {s.uretilen})" for s in self.kazanilan[:15]
            )
        if self.kaybedilen:
            satirlar.append(f"Kaybedilen sorular ({len(self.kaybedilen)}):")
            satirlar.extend(
                f"  - [{s.tur}] {s.soru}  ({s.beklenen} yerine {s.uretilen})"
                for s in self.kaybedilen[:15]
            )
        if self.yeni_sorular or self.dusen_sorular:
            satirlar.append(
                f"Dilim değişimi: {len(self.yeni_sorular)} yeni, "
                f"{len(self.dusen_sorular)} düşen soru (kıyasa girmedi)."
            )
        return "\n".join(satirlar)


def farkla(onceki: OlcumKaydi, yeni: OlcumKaydi) -> Fark:
    """İki ölçüm kaydını soru bazında karşılaştırır."""
    a, b = onceki.sonuc_haritasi(), yeni.sonuc_haritasi()
    ortak = sorted(set(a) & set(b))

    ortak_dogru_a = sum(1 for i in ortak if a[i].dogru) / len(ortak) if ortak else 0.0
    ortak_dogru_b = sum(1 for i in ortak if b[i].dogru) / len(ortak) if ortak else 0.0

    kazanilan = [b[i] for i in ortak if b[i].dogru and not a[i].dogru]
    kaybedilen = [b[i] for i in ortak if a[i].dogru and not b[i].dogru]

    turler = {a[i].tur for i in ortak} | {b[i].tur for i in ortak}
    tur_farki: dict[str, tuple[float, float, int]] = {}
    for tur in turler:
        kume = [i for i in ortak if b[i].tur == tur or a[i].tur == tur]
        if not kume:
            continue
        once = sum(1 for i in kume if a[i].dogru) / len(kume)
        sonra = sum(1 for i in kume if b[i].dogru) / len(kume)
        tur_farki[tur] = (round(once, 4), round(sonra, 4), len(kume))

    yontemler = {s.yontem for s in onceki.sorular} | {s.yontem for s in yeni.sorular}
    yontem_dagilimi = {
        y: (
            sum(1 for s in onceki.sorular if s.yontem == y),
            sum(1 for s in yeni.sorular if s.yontem == y),
        )
        for y in sorted(yontemler)
    }

    return Fark(
        onceki=onceki.etiket,
        yeni=yeni.etiket,
        dogruluk_onceki=float(onceki.ozet.get("dogruluk") or 0.0),
        dogruluk_yeni=float(yeni.ozet.get("dogruluk") or 0.0),
        kazanilan=kazanilan,
        kaybedilen=kaybedilen,
        tur_farki=tur_farki,
        yontem_dagilimi=yontem_dagilimi,
        ortak=len(ortak),
        yeni_sorular=sorted(set(b) - set(a)),
        dusen_sorular=sorted(set(a) - set(b)),
        dilim_uyusuyor=bool(
            onceki.dilim_imzasi
            and yeni.dilim_imzasi
            and onceki.dilim_imzasi == yeni.dilim_imzasi
        ),
        ortak_dogruluk_onceki=round(ortak_dogru_a, 4),
        ortak_dogruluk_yeni=round(ortak_dogru_b, 4),
        kosu_boyutu_onceki=len(a),
        kosu_boyutu_yeni=len(b),
    )
