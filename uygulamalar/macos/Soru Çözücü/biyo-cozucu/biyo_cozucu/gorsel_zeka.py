"""Görsel sorular için yönlendirme, ön işleme ve kanıt sözleşmesi.

Bir soru kırpımının bulunması, cevabın görüntüye bağlı olduğu anlamına gelmez.
Bu modül iki işi birbirinden ayırır:

* ``siniflandir`` görüntünün gerçekten gerekli olup olmadığına karar verir.
* ``gorseli_hazirla`` modele beyaz boşluk yerine soru içeriğini gösterir.

VLM çıktısı serbest açıklama olarak değil ``GorselKaniti`` biçiminde taşınır.
Çözücü bu kanıtı Campbell/Guyton ve referans çözüm bağlamıyla birleştirir.
"""

from __future__ import annotations

import io
import json
import re
from dataclasses import asdict, dataclass, field
from typing import Literal

import numpy as np

GorselModu = Literal["auto", "zorla", "yok"]
GorselTuru = Literal[
    "text_only",
    "chart",
    "table",
    "pedigree",
    "diagram",
    "micrograph",
    "uncertain",
]

GORSEL_PIPELINE_SURUMU = "gorsel-kanit-v2"

_IPUCLARI: tuple[tuple[GorselTuru, tuple[str, ...]], ...] = (
    ("pedigree", ("soyağac", "soyagac", "pedigri")),
    ("chart", ("grafik", "grafiğ", "grafig", "eğri", "egri", "koordinat", "eksen")),
    ("table", ("tablo", "çizelge", "cizelge")),
    (
        "micrograph",
        ("mikroskop", "mikrograf", "elektron mikroskob", "fotoğraf", "fotograf"),
    ),
    (
        "diagram",
        (
            "şekil",
            "sekil",
            "şekle",
            "sekle",
            "şema",
            "sema",
            "diyagram",
            "karyotip",
            "harita",
            "deney düzeneği",
            "deney duzenegi",
            "numaralandırılmış yapı",
            "numaralandirilmis yapi",
        ),
    ),
)


@dataclass(frozen=True)
class GorselKarari:
    tur: GorselTuru
    gerekli: bool
    guven: float
    neden: str


@dataclass
class GorselKaniti:
    """VLM'nin yalnız gördüğü olguları taşıyan, cevap içermeyen sözleşme."""

    tur: GorselTuru = "uncertain"
    ozet: str = ""
    veriler: list[str] = field(default_factory=list)
    iliskiler: list[str] = field(default_factory=list)
    okunamayanlar: list[str] = field(default_factory=list)
    guven: float = 0.0

    def sozluk(self) -> dict:
        return asdict(self)

    def istem_metni(self) -> str:
        veri = json.dumps(self.sozluk(), ensure_ascii=False, separators=(",", ":"))
        return (
            "[YAPILANDIRILMIŞ GÖRSEL KANIT]\n"
            f"{veri}\n"
            "Bu kayıt yalnız görüntüden çıkarılmış olgudur; cevabı içermez. "
            "Muhakemede yalnız açıkça görülen verileri kullan."
        )


# Varsayılan `auto` DEĞİL `zorla`. Ölçüldü (olcumler/2026-08-03-gorsel-50-
# kalite-kapisi.json, 50 gerçek soruluk görselli dilim, aynı model ve sıcaklık):
#
#   zorla → 39/50 (%78); seçici %84,8 @ kapsama %66
#   auto  → 35/50 (%70); seçici %95,0 @ kapsama %12
#
# `auto` yalnız doğrulukta değil, kullanılabilir kapsamada da çöküyor: yüksek
# seçici doğruluğu soruların yalnız %12'sinde veriyor. Sebebi basit — bu
# hafızadaki görseller Soru Kesici'nin kırpımları, yani sorunun ASLI; metin
# ise onun OCR'ı. Metin tam görünse bile aslı modele vermek daha iyi.
# `auto` hız için seçenek olarak duruyor, varsayılan değil.
VARSAYILAN_GORSEL_MODU = "zorla"


def gorsel_modunu_dogrula(mod: str | None) -> GorselModu:
    temiz = (mod or VARSAYILAN_GORSEL_MODU).strip().casefold()
    if temiz not in {"auto", "zorla", "yok"}:
        raise ValueError("gorsel_modu 'auto', 'zorla' veya 'yok' olmalıdır.")
    return temiz  # type: ignore[return-value]


def siniflandir(
    soru: str,
    secenekler: dict[str, str] | None,
    *,
    gorsel_var: bool,
    mod: str = "auto",
) -> GorselKarari:
    """Görüntünün cevap için gerekli olup olmadığını güvenli biçimde belirle."""
    mod = gorsel_modunu_dogrula(mod)
    if not gorsel_var:
        return GorselKarari("text_only", False, 1.0, "Görsel yok.")
    if mod == "yok":
        return GorselKarari("text_only", False, 1.0, "Görsel kullanımı kapatıldı.")
    if mod == "zorla":
        return GorselKarari("uncertain", True, 1.0, "Görsel kullanımı zorlandı.")

    metin = " ".join(soru.casefold().split())
    for tur, ipuclari in _IPUCLARI:
        bulunan = next((ipucu for ipucu in ipuclari if ipucu in metin), "")
        if bulunan:
            return GorselKarari(tur, True, 0.98, f"Soru '{bulunan}' ifadesini içeriyor.")

    # OCR kısa/eksikse sessizce metin motoruna düşmek tehlikelidir. Ama yalnız
    # soru kökünün kısa olması eksiklik değildir: "Hangisi yanlıştır?"
    # kökü beş tam şıkla birlikte eksiksiz olabilir. Kök + şıkları birlikte
    # ölç; şıkların ikiden az olması yine güçlü eksiklik işaretidir.
    secenek_metin = " ".join(str(v) for v in (secenekler or {}).values())
    butun_metin = f"{metin} {secenek_metin}".strip()
    if len(secenekler or {}) < 2 or (len(metin) < 45 and len(butun_metin) < 120):
        return GorselKarari(
            "uncertain",
            True,
            0.70,
            "Soru metni veya şıklar eksik; görüntüde ek bilgi olabilir.",
        )
    return GorselKarari(
        "text_only",
        False,
        0.96,
        "Soru ve şıklar tam; görsel bağımlılığı belirten ifade yok.",
    )


def gorseli_hazirla(veri: bytes, *, azami_piksel: int = 1_800_000) -> bytes:
    """Beyaz kenarları kırp, yön bilgisini düzelt ve piksel bütçesini sınırla."""
    if not veri:
        return b""
    try:
        from PIL import Image, ImageOps

        goruntu = ImageOps.exif_transpose(Image.open(io.BytesIO(veri))).convert("RGB")
    except (OSError, ValueError):
        return veri

    dizi = np.asarray(goruntu, dtype=np.uint8)
    # Beyaz veya beyaza çok yakın arka plan. Her kanalda eşik kullanmak QR ve
    # ince grafik çizgilerini korurken dev boş alt kenarları atar.
    maske = np.any(dizi < 245, axis=2)
    if np.any(maske):
        ys, xs = np.nonzero(maske)
        pay = max(12, int(min(goruntu.size) * 0.025))
        sol = max(0, int(xs.min()) - pay)
        ust = max(0, int(ys.min()) - pay)
        sag = min(goruntu.width, int(xs.max()) + pay + 1)
        alt = min(goruntu.height, int(ys.max()) + pay + 1)
        goruntu = goruntu.crop((sol, ust, sag, alt))

    piksel = goruntu.width * goruntu.height
    if piksel > azami_piksel:
        oran = (azami_piksel / piksel) ** 0.5
        boyut = (max(1, round(goruntu.width * oran)), max(1, round(goruntu.height * oran)))
        goruntu = goruntu.resize(boyut, Image.Resampling.LANCZOS)

    tampon = io.BytesIO()
    goruntu.save(tampon, format="PNG", optimize=True)
    return tampon.getvalue()


def kanit_mesajlari(tur: GorselTuru) -> list[dict[str, str]]:
    """Şıkları veya beklenen cevabı sızdırmadan algılama istemi kur."""
    ayrinti = {
        "pedigree": (
            "Bireylere kuşak-sıra kimliği ver; cinsiyet, hasta/sağlıklı durumu, "
            "eş ve ebeveyn-çocuk bağlarını ayrı maddelerle yaz."
        ),
        "chart": "Eksenleri, birimleri, serileri, işaretli değerleri ve artış/azalışları yaz.",
        "table": "Satır/sütun başlıklarını ve hücre değerlerini ilişkileri bozmadan yaz.",
        "micrograph": "Görülebilen yapı, konum, renk ve işaretleri yaz; tür adı tahmin etme.",
        "diagram": "Etiketleri, ok yönlerini, numaraları ve parçalar arasındaki bağları yaz.",
        "uncertain": "Metin dışındaki bütün şekil, grafik, tablo ve sembol verisini yaz.",
        "text_only": "Yalnız okunabilen metni özetle.",
    }[tur]
    istem = (
        "Yalnız görsel algılama yap; soruyu çözme, doğru şıkkı seçme ve biyoloji "
        "bilgisiyle boşluk doldurma. "
        f"{ayrinti} Göremediğin alanları okunamayanlar listesine koy. "
        "Yalnız geçerli JSON döndür: "
        '{"tur":"chart|table|pedigree|diagram|micrograph|uncertain",'
        '"ozet":"kısa nesnel özet","veriler":["..."],'
        '"iliskiler":["..."],"okunamayanlar":["..."],"guven":0.0}'
    )
    return [{"role": "user", "content": istem}]


_KOD_CITI = re.compile(r"^```(?:json)?\s*|\s*```$", re.I | re.M)


def kaniti_ayikla(ham: str, varsayilan_tur: GorselTuru) -> GorselKaniti:
    govde = _KOD_CITI.sub("", (ham or "").strip()).strip()
    bas, son = govde.find("{"), govde.rfind("}")
    if bas >= 0 and son > bas:
        govde = govde[bas : son + 1]
    try:
        veri = json.loads(govde)
    except (json.JSONDecodeError, TypeError):
        return GorselKaniti(
            tur=varsayilan_tur,
            okunamayanlar=["Görsel model yapılandırılmış kanıt üretemedi."],
            guven=0.0,
        )
    izinli = {"text_only", "chart", "table", "pedigree", "diagram", "micrograph", "uncertain"}
    tur = str(veri.get("tur") or varsayilan_tur)
    if tur not in izinli:
        tur = varsayilan_tur

    def liste(ad: str) -> list[str]:
        ham_liste = veri.get(ad) or []
        if not isinstance(ham_liste, list):
            return []
        return [str(x).strip()[:300] for x in ham_liste if str(x).strip()][:40]

    try:
        guven = max(0.0, min(1.0, float(veri.get("guven", 0.0))))
    except (TypeError, ValueError):
        guven = 0.0
    return GorselKaniti(
        tur=tur,  # type: ignore[arg-type]
        ozet=str(veri.get("ozet") or "").strip()[:1000],
        veriler=liste("veriler"),
        iliskiler=liste("iliskiler"),
        okunamayanlar=liste("okunamayanlar"),
        guven=guven,
    )
