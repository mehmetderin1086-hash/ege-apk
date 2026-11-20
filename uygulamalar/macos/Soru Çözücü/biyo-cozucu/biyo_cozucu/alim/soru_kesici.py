"""Soru Kesici arşivlerini okuma (`soru_NN.png` + `sorular.json`).

Soru Kesici, PDF sınav/soru bankalarından soruları kırpıp her biri için hem
görüntü hem yapılandırılmış metin üreten ayrı bir program. Çıktısı burada
birinci sınıf bir girdi biçimi olarak tanınıyor: iki program arasındaki bağ
bu modül.

**Bu arşivler referans örnek DEĞİL.** İncelenen üç arşivin (1201, 1116 ve 6
soru) hiçbirinde `cevap` ya da çözüm alanı dolu değil; hepsi saf soru kümesi.
`Ornek` bir çözüm metni gerektirdiği için bunları `al` yoluna bağlamak sıfır
kullanılabilir aday üretirdi. Doğru yer çözme yolu: sorular çözülür, üretilen
çözümler öğretmen onayına düşer ve onaylananlar var olan döngüyle referans
örneğe dönüşür.
"""

from __future__ import annotations

import json
import shutil
import tempfile
import zipfile
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path

from .cikarim import AlimHatasi

# Arşivin künye dosyası. Soru Kesici bunu her dışa aktarmada yazıyor.
KUNYE_ADI = "sorular.json"

# Kabul edilen görüntü uzantıları (Soru Kesici PNG yazıyor; diğerleri hoşgörü).
GORUNTU_UZANTILARI = {".png", ".jpg", ".jpeg", ".webp"}

# Zip bombalarına karşı üst sınır: 1200 soruluk gerçek arşivler ~220 MB.
AZAMI_ACILMIS_MB = 2048


@dataclass
class KesilmisSoru:
    """Arşivdeki tek soru: metni, şıkları ve kırpılmış görüntüsü."""

    soru: str
    gorsel_yolu: Path | None = None
    secenekler: dict[str, str] = field(default_factory=dict)
    konu: str = ""
    guven: float = 0.0
    kaynak: str = ""
    sayfa: int | None = None
    dosya: str = ""

    def kaynak_adi(self) -> str:
        parcalar = [p for p in (self.kaynak, f"s. {self.sayfa}" if self.sayfa else "") if p]
        return " · ".join(parcalar) or self.dosya


def _kunye_bul(dizin: Path) -> Path | None:
    dogrudan = dizin / KUNYE_ADI
    if dogrudan.is_file():
        return dogrudan
    # Bazı arşivler tek bir üst klasör içinde geliyor.
    for aday in sorted(dizin.glob(f"*/{KUNYE_ADI}")):
        return aday
    return None


def _kaydi_coz(kayit: dict, kok: Path) -> KesilmisSoru | None:
    """Künye kaydını `KesilmisSoru`'ya çevirir; kullanılamayanı atar."""
    metin = str(kayit.get("metin") or "").strip()
    if not metin:
        return None

    # `siklar` gerçek çoktan seçmeli şıkları taşıyabildiği gibi, açık uçlu
    # soruların "A) … B) …" alt maddelerini de taşıyor (gözlemlendi). İkisini
    # ayırt etmek için tek ölçüt yok; şıklar aynen aktarılıyor ve cevap türünü
    # çözücünün kendi çıkarımı belirliyor.
    ham_siklar = kayit.get("siklar") or {}
    secenekler = {
        str(h).strip().upper(): str(m).strip()
        for h, m in ham_siklar.items()
        if str(m).strip()
    } if isinstance(ham_siklar, dict) else {}

    gorsel_yolu = None
    dosya = str(kayit.get("dosya") or "").strip()
    if dosya:
        aday = kok / dosya
        if aday.is_file() and aday.suffix.casefold() in GORUNTU_UZANTILARI:
            gorsel_yolu = aday

    try:
        guven = float(kayit.get("kalibre_guven") or kayit.get("guven") or 0.0)
    except (TypeError, ValueError):
        guven = 0.0

    sayfa = kayit.get("sayfa")
    return KesilmisSoru(
        soru=metin,
        gorsel_yolu=gorsel_yolu,
        secenekler=secenekler,
        konu=str(kayit.get("konu") or "").strip(),
        guven=guven,
        kaynak=str(kayit.get("kaynak") or "").strip(),
        sayfa=int(sayfa) if isinstance(sayfa, int) else None,
        dosya=dosya,
    )


def sorulari_oku(yol: str | Path) -> list[KesilmisSoru]:
    """Soru Kesici arşivinden (zip ya da dizin) soruları okur.

    Zip geçici bir dizine açılır ve çağrı boyunca orada durur; görüntü yolları
    o dizini gösterir. Çağıranın görüntüleri kendi deposuna kopyalaması
    gerekir — bu yüzden `arsivi_ac` bağlam yöneticisi tercih edilmeli.
    """
    with arsivi_ac(yol) as (kok, sorular):
        # Geçici dizin kapanmadan önce kullanılabilmesi için kopyalanmış
        # görüntü yolu isteyen çağıranlar `arsivi_ac`'i doğrudan kullanmalı.
        _ = kok
        return sorular


@contextmanager
def gecici_acilmis(yol: str | Path) -> Iterator[Path]:
    """Zip'i geçici bir dizine güvenle açar; dizin verilirse onu aynen döndürür.

    `arsivi_ac`'ten farkı künye aramaması: Soru Kesici dışındaki arşivlerde
    (ör. hazır soru-çözüm paketleri) `sorular.json` yok, ama zip-slip ve
    açılmış boyut koruması aynı şekilde gerekli.
    """
    hedef = Path(yol).expanduser()
    if hedef.is_dir():
        yield hedef
        return
    if not zipfile.is_zipfile(hedef):
        raise AlimHatasi(
            f"{hedef.name}: bir .zip dosyası ya da açılmış bir klasör olmalı."
        )
    with tempfile.TemporaryDirectory(prefix="biyo-arsiv-") as gecici:
        kok = Path(gecici)
        _guvenli_ac(hedef, kok)
        yield kok


class _AcikArsiv:
    def __init__(self, yol: Path):
        self.yol = yol
        self._gecici: tempfile.TemporaryDirectory | None = None

    def __enter__(self) -> tuple[Path, list[KesilmisSoru]]:
        if self.yol.is_dir():
            kok = self.yol
        elif zipfile.is_zipfile(self.yol):
            self._gecici = tempfile.TemporaryDirectory(prefix="biyo-soru-kesici-")
            kok = Path(self._gecici.name)
            _guvenli_ac(self.yol, kok)
        else:
            raise AlimHatasi(
                f"{self.yol.name}: Soru Kesici arşivi bir .zip dosyası ya da "
                "açılmış bir klasör olmalı."
            )

        kunye = _kunye_bul(kok)
        if kunye is None:
            raise AlimHatasi(
                f"{self.yol.name}: arşivde {KUNYE_ADI} bulunamadı. Bu bir Soru "
                "Kesici arşivi mi?"
            )
        try:
            kayitlar = json.loads(kunye.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise AlimHatasi(f"{KUNYE_ADI} okunamadı: {exc}") from exc
        if not isinstance(kayitlar, list):
            raise AlimHatasi(f"{KUNYE_ADI} bir liste değil.")

        veri_kok = kunye.parent
        sorular = [s for s in (_kaydi_coz(k, veri_kok) for k in kayitlar if isinstance(k, dict)) if s]
        return veri_kok, sorular

    def __exit__(self, *_a) -> None:
        if self._gecici is not None:
            self._gecici.cleanup()


def arsivi_ac(yol: str | Path) -> _AcikArsiv:
    """Arşivi açıp `(kök, sorular)` veren bağlam yöneticisi."""
    return _AcikArsiv(Path(yol).expanduser())


def _guvenli_ac(arsiv: Path, hedef: Path) -> None:
    """Zip'i hedefin DIŞINA yazmadan açar.

    `..` içeren üye adları hedef dizinin dışına yazabilir (zip-slip); aynı
    koruma `model-kur` komutunda da var.
    """
    cozulmus_hedef = hedef.resolve()
    toplam = 0
    with zipfile.ZipFile(arsiv) as z:
        for uye in z.infolist():
            if uye.is_dir():
                continue
            toplam += uye.file_size
            if toplam > AZAMI_ACILMIS_MB * 1024 * 1024:
                raise AlimHatasi(
                    f"Arşiv açılmış hâlde {AZAMI_ACILMIS_MB} MB sınırını aşıyor."
                )
            varis = (cozulmus_hedef / uye.filename).resolve()
            if not str(varis).startswith(str(cozulmus_hedef) + "/"):
                raise AlimHatasi(f"Arşivde güvensiz yol: {uye.filename}")
            varis.parent.mkdir(parents=True, exist_ok=True)
            with z.open(uye) as kaynak, varis.open("wb") as cikti:
                shutil.copyfileobj(kaynak, cikti)


def ozet(sorular: list[KesilmisSoru]) -> dict[str, object]:
    """Arşivin insan okunur künyesi — çözmeden önce ne olduğunu görmek için."""
    konular: dict[str, int] = {}
    for soru in sorular:
        konular[soru.konu or "(konusuz)"] = konular.get(soru.konu or "(konusuz)", 0) + 1
    return {
        "soru": len(sorular),
        "gorselli": sum(1 for s in sorular if s.gorsel_yolu is not None),
        "sikli": sum(1 for s in sorular if s.secenekler),
        "kaynaklar": sorted({s.kaynak for s in sorular if s.kaynak}),
        "konu_dagilimi": dict(
            sorted(konular.items(), key=lambda x: -x[1])
        ),
    }
