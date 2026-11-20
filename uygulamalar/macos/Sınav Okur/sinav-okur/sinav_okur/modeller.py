"""Çekirdek veri modelleri: sınav tanımı, cevap anahtarı, şablon geometrisi, puan sonucu."""

from __future__ import annotations

import warnings
from dataclasses import asdict, dataclass, field
from enum import Enum
from pathlib import Path

import yaml


class _TrLoader(yaml.SafeLoader):
    """YAML 1.1'in no/yes/on/off'u boolean sayması, ``no:`` anahtarını bozar;
    bu loader'da bu örtük boolean çözümlemesi kapatılır (değerler string kalır)."""


# Paylaşılan resolver sözlüğünü kopyala (SafeLoader'ı global olarak değiştirme).
_bool_tag = "tag:yaml.org,2002:bool"
_TrLoader.yaml_implicit_resolvers = {
    ch: [(etiket, kalip) for (etiket, kalip) in cozumleyiciler if etiket != _bool_tag]
    for ch, cozumleyiciler in yaml.SafeLoader.yaml_implicit_resolvers.items()
}


def _mantiksal_deger(deger, varsayilan: bool) -> bool:
    """YAML'den string gelen true/false değerlerini güvenle bool'a çevir."""
    if deger is None:
        return varsayilan
    if isinstance(deger, str):
        norm = deger.strip().casefold()
        if norm in {"false", "hayır", "hayir", "no", "off", "0", ""}:
            return False
        if norm in {"true", "evet", "yes", "on", "1"}:
            return True
    return bool(deger)


class SoruTipi(str, Enum):
    ACIK_UCLU = "acik_uclu"
    KISA_CEVAP = "kisa_cevap"
    BOSLUK_DOLDURMA = "bosluk_doldurma"
    ESLESTIRME = "eslestirme"
    SIRALAMA = "siralama"
    COKTAN_SECMELI = "coktan_secmeli"
    SAYISAL = "sayisal"
    FORMUL_ISPAT = "formul_ispat"
    TABLO = "tablo"
    GRAFIK = "grafik"
    CIZIM = "cizim"
    DENEY_TASARLAMA = "deney_tasarlama"
    YORUMLAMA = "yorumlama"
    ETIK = "etik"


@dataclass
class RubrikKalemi:
    """Cevapta aranan tek bir puan kalemi (kavram, ifade veya olgu)."""

    metin: str
    puan: float
    esanlamlilar: list[str] = field(default_factory=list)
    kategori: str = "kavram"
    zorunlu: bool = False
    celiskiler: list[str] = field(default_factory=list)
    aciklama: str = ""

    def __post_init__(self) -> None:
        # YAML tırnaksız değerleri int/float/date yükleyebilir; metin katmanı
        # her zaman str bekler (aksi halde NFC normalizasyonu TypeError verir).
        self.metin = str(self.metin)
        self.puan = float(self.puan)
        self.esanlamlilar = [str(e) for e in self.esanlamlilar]
        self.kategori = str(self.kategori or "kavram")
        self.zorunlu = _mantiksal_deger(self.zorunlu, False)
        self.celiskiler = [str(e) for e in self.celiskiler]
        self.aciklama = str(self.aciklama)

    def tum_bicimler(self) -> list[str]:
        return [self.metin, *self.esanlamlilar]


@dataclass
class CevapAnahtari:
    # bosluk_doldurma: kabul edilen cevap yazımları (ilk eleman kanonik)
    dogru_cevaplar: list[str] = field(default_factory=list)
    # kisa_cevap / acik_uclu: kısmi puanlı rubrik kalemleri
    rubrik: list[RubrikKalemi] = field(default_factory=list)
    # açık uçlu için tam puanlık örnek cevap (gömme benzerliği desteği)
    ornek_cevap: str = ""
    # RAG ile oluşturulan anahtarın denetlenebilir kökeni
    kaynaklar: list[str] = field(default_factory=list)
    uretim_yontemi: str = ""
    otomatik_uretildi: bool = False
    # Eksik/kanıtsız sorularda anahtar gösterilebilir, fakat otomatik not verilmez.
    otomatik_puanlama: bool = True
    uyari: str = ""
    # Yapısal anahtar: tek bir örnek cevaba mahkûm olmadan alternatifleri,
    # yöntemi, çelişkileri ve sayısal/şematik cevapları ayrı ayrı tanımlar.
    kabul_edilen_alternatifler: list[str] = field(default_factory=list)
    yaygin_hatalar: list[str] = field(default_factory=list)
    yasak_celiskiler: list[str] = field(default_factory=list)
    yontem_adimlari: list[str] = field(default_factory=list)
    birimler: list[str] = field(default_factory=list)
    siralama: list[str] = field(default_factory=list)
    eslestirmeler: dict[str, str] = field(default_factory=dict)
    sayisal_tolerans: float = 0.0
    onay_durumu: str = "taslak"
    surum: int = 1
    esneklik: str = "dengeli"
    kaynak_kanitlari: list[dict] = field(default_factory=list)

    def __post_init__(self) -> None:
        self.dogru_cevaplar = [str(c) for c in self.dogru_cevaplar]
        self.ornek_cevap = str(self.ornek_cevap)
        self.kaynaklar = [str(k) for k in self.kaynaklar]
        self.uretim_yontemi = str(self.uretim_yontemi)
        self.otomatik_uretildi = _mantiksal_deger(
            self.otomatik_uretildi, False
        )
        self.otomatik_puanlama = _mantiksal_deger(
            self.otomatik_puanlama, True
        )
        self.uyari = str(self.uyari)
        self.kabul_edilen_alternatifler = [
            str(x) for x in self.kabul_edilen_alternatifler
        ]
        self.yaygin_hatalar = [str(x) for x in self.yaygin_hatalar]
        self.yasak_celiskiler = [str(x) for x in self.yasak_celiskiler]
        self.yontem_adimlari = [str(x) for x in self.yontem_adimlari]
        self.birimler = [str(x) for x in self.birimler]
        self.siralama = [str(x) for x in self.siralama]
        self.eslestirmeler = {
            str(k): str(v) for k, v in self.eslestirmeler.items()
        }
        self.sayisal_tolerans = max(0.0, float(self.sayisal_tolerans or 0.0))
        self.onay_durumu = str(self.onay_durumu or "taslak")
        self.surum = max(1, int(self.surum or 1))
        self.esneklik = str(self.esneklik or "dengeli")
        self.kaynak_kanitlari = [
            dict(x) for x in self.kaynak_kanitlari if isinstance(x, dict)
        ]


@dataclass
class Soru:
    no: int
    tip: SoruTipi
    metin: str
    puan: float
    anahtar: CevapAnahtari
    kutu_yuksekligi_mm: float = 30.0
    kazanımlar: list[str] = field(default_factory=list)
    esneklik: str = "dengeli"

    def __post_init__(self) -> None:
        self.tip = SoruTipi(self.tip)
        self.metin = str(self.metin)
        self.puan = float(self.puan)
        if isinstance(self.anahtar, dict):
            rubrik = [
                RubrikKalemi(**k) if isinstance(k, dict) else k
                for k in self.anahtar.get("rubrik", [])
            ]
            self.anahtar = CevapAnahtari(
                dogru_cevaplar=list(self.anahtar.get("dogru_cevaplar", [])),
                rubrik=rubrik,
                ornek_cevap=self.anahtar.get("ornek_cevap", ""),
                kaynaklar=list(self.anahtar.get("kaynaklar", [])),
                uretim_yontemi=self.anahtar.get("uretim_yontemi", ""),
                otomatik_uretildi=self.anahtar.get("otomatik_uretildi", False),
                otomatik_puanlama=self.anahtar.get("otomatik_puanlama", True),
                uyari=self.anahtar.get("uyari", ""),
                kabul_edilen_alternatifler=list(
                    self.anahtar.get("kabul_edilen_alternatifler", [])
                ),
                yaygin_hatalar=list(self.anahtar.get("yaygin_hatalar", [])),
                yasak_celiskiler=list(
                    self.anahtar.get("yasak_celiskiler", [])
                ),
                yontem_adimlari=list(self.anahtar.get("yontem_adimlari", [])),
                birimler=list(self.anahtar.get("birimler", [])),
                siralama=list(self.anahtar.get("siralama", [])),
                eslestirmeler=dict(self.anahtar.get("eslestirmeler", {})),
                sayisal_tolerans=self.anahtar.get("sayisal_tolerans", 0.0),
                onay_durumu=self.anahtar.get("onay_durumu", "taslak"),
                surum=self.anahtar.get("surum", 1),
                esneklik=self.anahtar.get("esneklik", "dengeli"),
                kaynak_kanitlari=list(
                    self.anahtar.get("kaynak_kanitlari", [])
                ),
            )
        self.kazanımlar = [str(x) for x in self.kazanımlar]
        self.esneklik = str(self.esneklik or self.anahtar.esneklik or "dengeli")
        dogrudan_tipler = {
            SoruTipi.BOSLUK_DOLDURMA,
            SoruTipi.COKTAN_SECMELI,
        }
        if self.tip in dogrudan_tipler and not self.anahtar.dogru_cevaplar:
            raise ValueError(
                f"Soru {self.no}: {self.tip.value} için dogru_cevaplar gerekli"
            )
        yapisal_hazir = (
            (self.tip == SoruTipi.SIRALAMA and bool(self.anahtar.siralama))
            or (
                self.tip == SoruTipi.ESLESTIRME
                and bool(self.anahtar.eslestirmeler)
            )
            or (
                self.tip in {SoruTipi.SAYISAL, SoruTipi.FORMUL_ISPAT}
                and bool(self.anahtar.dogru_cevaplar)
            )
        )
        if self.tip not in dogrudan_tipler and not yapisal_hazir:
            if not self.anahtar.rubrik:
                raise ValueError(f"Soru {self.no}: {self.tip.value} için rubrik gerekli")
            rubrik_toplam = sum(k.puan for k in self.anahtar.rubrik)
            if rubrik_toplam < self.puan - 1e-6:
                warnings.warn(
                    f"Soru {self.no}: rubrik kalemleri toplamı ({rubrik_toplam:g}) "
                    f"soru puanından ({self.puan:g}) düşük — tam puan alınamaz.",
                    stacklevel=2,
                )


@dataclass
class Sinav:
    kimlik: str
    baslik: str
    sorular: list[Soru]
    ders: str = ""

    def __post_init__(self) -> None:
        self.kimlik = str(self.kimlik)
        self.baslik = str(self.baslik)
        self.ders = str(self.ders)
        self.sorular = [Soru(**s) if isinstance(s, dict) else s for s in self.sorular]
        for s in self.sorular:
            s.no = int(s.no)
        nolar = [s.no for s in self.sorular]
        if len(nolar) != len(set(nolar)):
            raise ValueError("Soru numaraları tekrarlı")

    @property
    def toplam_puan(self) -> float:
        return sum(s.puan for s in self.sorular)

    def soru(self, no: int) -> Soru:
        for s in self.sorular:
            if s.no == no:
                return s
        raise KeyError(f"Soru {no} bulunamadı")

    @classmethod
    def yaml_yukle(cls, yol: str | Path) -> "Sinav":
        veri = yaml.load(Path(yol).read_text(encoding="utf-8"), Loader=_TrLoader)
        return cls(**veri)

    def yaml_kaydet(self, yol: str | Path) -> None:
        veri = asdict(self)
        for s in veri["sorular"]:
            s["tip"] = s["tip"].value if isinstance(s["tip"], SoruTipi) else s["tip"]
        Path(yol).write_text(
            yaml.safe_dump(veri, allow_unicode=True, sort_keys=False), encoding="utf-8"
        )


# --- Tanıma ve puanlama sonuçları ---


@dataclass
class TanimaSonucu:
    metin: str
    guven: float = 1.0  # 0-1 arası; düşükse insan onayına düşer
    alternatifler: list[dict] = field(default_factory=list)
    motor_sonuclari: list[dict] = field(default_factory=list)
    ogretmen_murekkebi_ayrildi: bool = False
    # Çoklu OCR kanıtları. Aynı motorun farklı görüntü varyantları bağımsız
    # motor sayılmaz; bu alanlar güven kapısının yanlış otomatik kabulü
    # engellemesine yarar.
    uzlasma_guveni: float = 0.0
    bagimsiz_motor_sayisi: int = 0
    karar_marji: float = 0.0
    belirsizlik_nedeni: str = ""
    girdi_kalitesi: float = 0.0
    model_surumu: dict = field(default_factory=dict)
    otomatik_kabul: bool = False
    # Kanıt formülünün sürümü. `karar_marji` iki kümenin kanıt farkıdır;
    # formül değişince bu alanın anlamı da değişir. Gölge telemetride farklı
    # sürümler karışırsa eşik süpürmesi sessizce yanlış sonuç verir.
    kanit_surumu: str = ""


@dataclass
class PuanSonucu:
    puan: float
    max_puan: float
    guven: float
    detaylar: list[str] = field(default_factory=list)
    incele: bool = False
    risk: float = 0.0
    kararlar: list[dict] = field(default_factory=list)
    aciklama: str = ""
    tanima_guveni: float = 1.0
    puanlama_guveni: float = 1.0
    otomatik_kabul: bool = False
    kabul_nedenleri: list[str] = field(default_factory=list)

    @property
    def oran(self) -> float:
        return self.puan / self.max_puan if self.max_puan else 0.0
