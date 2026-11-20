"""Açık veri setlerinden referans örnek üretimi (isteğe bağlı takviye).

Lisans burada veri gibi değil, kural gibi ele alınıyor: türev üretimini yasaklayan
(ND) veya ticari olmayan (NC) setler `egitime_uygun=False` işaretli ve
`ornekleri_al(..., amac="egitim")` çağrısında hata veriyor. Sessizce eğitime
karışan bir NC-ND seti geri alınamaz bir lisans sorunudur.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..modeller import Ornek


@dataclass(frozen=True)
class VeriSeti:
    ad: str
    hf_yolu: str
    alt_kume: str | None
    lisans: str
    egitime_uygun: bool
    dil: str
    aciklama: str
    # Aşağıdaki iki alan "neden alınamıyor"u taşır. Bunlar olmadan kullanıcı
    # yalnız `NotImplementedError` görüyordu ve engelin lisans mı, kimlik
    # doğrulama mı, biçim mi olduğunu anlayamıyordu.
    kapili: bool = False           # HF'de şart kabulü + token gerektiriyor
    gorsel_gerektirir: bool = False  # soru metni yok, yalnız görüntü var

    def durum_ozeti(self) -> str:
        """Listede tek sözcüklük durum; ayrıntı `engel()`'de."""
        if self.kapili:
            return "kapılı"
        if self.gorsel_gerektirir:
            return "görsel"
        return "hazır"

    def engel(self) -> str:
        """Bu set şu an alınamıyorsa nedeni; alınabiliyorsa boş dizge."""
        if self.kapili:
            return (
                f"{self.ad} HuggingFace'te kapılı (gated): indirmeden önce veri "
                f"kartında şartları kabul edip HF_TOKEN tanımlamanız gerekiyor. "
                f"Kart: https://huggingface.co/datasets/{self.hf_yolu}"
            )
        if self.gorsel_gerektirir:
            return (
                f"{self.ad} sorularının metni yok, yalnız görüntü var; metin "
                f"tabanlı referans örneğe çevrilemez. Görsel soru desteği "
                f"geldiğinde değerlendirme kümesi olarak kullanılabilir."
            )
        return ""


KAYITLI_SETLER: dict[str, VeriSeti] = {
    "scienceqa": VeriSeti(
        ad="scienceqa",
        hf_yolu="derek-thomas/ScienceQA",
        alt_kume=None,
        lisans="CC-BY-SA-4.0",
        egitime_uygun=True,
        dil="en",
        aciklama="Görselli fen soruları; `lecture`+`solution` alanları çözüm üretimi öğretmek için uygun.",
    ),
    "medmcqa": VeriSeti(
        ad="medmcqa",
        hf_yolu="openlifescienceai/medmcqa",
        alt_kume=None,
        lisans="Apache-2.0",
        egitime_uygun=True,
        dil="en",
        aciklama="194K tıp çoktan seçmeli; açıklama alanı var.",
    ),
    "openbookqa": VeriSeti(
        ad="openbookqa",
        hf_yolu="allenai/openbookqa",
        # `main` yapılandırmasında çözüm alanı YOK (yalnız soru/şık/cevap).
        # `additional`'daki `fact1`, cevabı doğrulayan bilimsel olguyu veriyor
        # ve asgari bir çözüm metni olarak kullanılabiliyor.
        alt_kume="additional",
        lisans="Apache-2.0",
        egitime_uygun=True,
        dil="en",
        aciklama="Çok adımlı temel bilim muhakemesi; `fact1` destekleyici olguyu verir.",
    ),
    "turkish_mmlu": VeriSeti(
        ad="turkish_mmlu",
        hf_yolu="alibayram/turkish_mmlu",
        alt_kume=None,
        lisans="CC-BY-NC-ND-4.0",
        egitime_uygun=False,
        dil="tr",
        aciklama="Türkçe çok alanlı sınav soruları — ND kısıtı nedeniyle YALNIZ değerlendirme.",
        kapili=True,
    ),
    "yksbench": VeriSeti(
        ad="yksbench",
        hf_yolu="metu-yks/yksbench",
        alt_kume=None,
        lisans="MIT (kartta 'akademik kullanım' notu da var — çelişkili)",
        egitime_uygun=False,
        dil="tr",
        aciklama=(
            "Görselli gerçek YKS soruları (2.047 soru). Alanlar: image, answer, "
            "topic, subject — soru METNİ yok. Görsel destek geldiğinde biyoloji "
            "altkümesi değerlendirme için birincil kaynak."
        ),
        gorsel_gerektirir=True,
    ),
}


class LisansHatasi(RuntimeError):
    """Veri seti istenen amaç için kullanılamadığında oluşur."""


class VeriSetiHatasi(RuntimeError):
    """Set teknik olarak alınamadığında (kapılı, görsel, biçimsiz) oluşur.

    Lisanstan ayrı tutuluyor: lisans engeli bir KURAL, bu bir DURUM — biri
    aşılmamalı, diğeri kullanıcı bir şey yaparsa (token tanımlar, görsel
    desteği gelir) ortadan kalkar.
    """


def _hf_yukle(veri_seti: VeriSeti, bolum: str):
    try:
        from datasets import load_dataset
    except ImportError as exc:  # pragma: no cover - opsiyonel bağımlılık
        raise RuntimeError(
            "Açık veri setleri için `datasets` gerekli: uv pip install datasets"
        ) from exc
    if veri_seti.alt_kume:
        return load_dataset(veri_seti.hf_yolu, veri_seti.alt_kume, split=bolum)
    return load_dataset(veri_seti.hf_yolu, split=bolum)


def _scienceqa_ornek(satir: dict) -> Ornek | None:
    secenek_listesi = satir.get("choices") or []
    dogru = satir.get("answer")
    if not secenek_listesi or dogru is None:
        return None
    harfler = "ABCDE"
    secenekler = {
        harfler[i]: str(s) for i, s in enumerate(secenek_listesi) if i < len(harfler)
    }
    cozum_parcalari = [
        str(satir.get("lecture") or "").strip(),
        str(satir.get("solution") or "").strip(),
    ]
    cozum = "\n".join(p for p in cozum_parcalari if p)
    if not cozum:
        return None
    return Ornek(
        soru=str(satir.get("question", "")).strip(),
        secenekler=secenekler,
        cozum=cozum,
        cevap=harfler[int(dogru)] if int(dogru) < len(harfler) else "",
        cevap_turu="coktan_secmeli",
        konu=str(satir.get("topic") or satir.get("subject") or "").strip(),
        kaynak="scienceqa",
    )


def _medmcqa_ornek(satir: dict) -> Ornek | None:
    secenekler = {
        harf: str(satir.get(alan) or "").strip()
        for harf, alan in zip("ABCD", ("opa", "opb", "opc", "opd"), strict=True)
    }
    secenekler = {h: m for h, m in secenekler.items() if m}
    cozum = str(satir.get("exp") or "").strip()
    if not secenekler or not cozum:
        return None
    dogru = satir.get("cop")
    harf = "ABCD"[int(dogru)] if isinstance(dogru, int) and 0 <= int(dogru) < 4 else ""
    return Ornek(
        soru=str(satir.get("question", "")).strip(),
        secenekler=secenekler,
        cozum=cozum,
        cevap=harf,
        cevap_turu="coktan_secmeli",
        konu=str(satir.get("subject_name") or "").strip(),
        kaynak="medmcqa",
    )


def _openbookqa_ornek(satir: dict) -> Ornek | None:
    """`additional` yapılandırması: şıklar `choices{text,label}` içinde gelir."""
    secimler = satir.get("choices") or {}
    metinler = list(secimler.get("text") or [])
    etiketler = [str(e).strip().upper() for e in (secimler.get("label") or [])]
    if not metinler or len(metinler) != len(etiketler):
        return None
    secenekler = {
        harf: metin.strip()
        for harf, metin in zip(etiketler, metinler, strict=True)
        if str(metin).strip()
    }
    # `fact1` tek cümlelik destekleyici olgu; çözüm sayılabilecek yegâne alan.
    # Yoksa kayıt atlanır — cevabı gerekçesiz ezberletmek bu projenin amacına
    # aykırı (referans örneğin işi ÜSLUP ve YÖNTEM öğretmek).
    olgu = str(satir.get("fact1") or "").strip()
    cevap = str(satir.get("answerKey") or "").strip().upper()
    if not secenekler or not olgu or cevap not in secenekler:
        return None
    return Ornek(
        soru=str(satir.get("question_stem", "")).strip(),
        secenekler=secenekler,
        cozum=olgu,
        cevap=cevap,
        cevap_turu="coktan_secmeli",
        konu="",
        kaynak="openbookqa",
    )


_DONUSTURUCULER = {
    "scienceqa": _scienceqa_ornek,
    "medmcqa": _medmcqa_ornek,
    "openbookqa": _openbookqa_ornek,
}

# ScienceQA/MedMCQA'nın hangi kayıtları biyoloji sayılacağı.
_BIYOLOJI_IPUCLARI = (
    "biology", "life science", "anatomy", "physiology", "genetics",
    "microbiology", "biochemistry", "cell", "botany", "zoology", "ecology",
)


def biyoloji_mi(ornek: Ornek) -> bool:
    havuz = f"{ornek.konu} {ornek.kaynak} {ornek.soru[:200]}".casefold()
    return any(ipucu in havuz for ipucu in _BIYOLOJI_IPUCLARI)


def ornekleri_al(
    ad: str,
    *,
    bolum: str = "train",
    amac: str = "egitim",
    limit: int | None = 500,
    yalniz_biyoloji: bool = True,
) -> list[Ornek]:
    """Kayıtlı bir veri setinden `Ornek` listesi üretir.

    ``amac="egitim"`` iken lisansı türev üretimine izin vermeyen setler
    reddedilir; değerlendirme (``amac="degerlendirme"``) için engel yoktur.
    """
    if ad not in KAYITLI_SETLER:
        raise KeyError(f"Bilinmeyen veri seti: {ad}. Seçenekler: {', '.join(KAYITLI_SETLER)}")
    veri_seti = KAYITLI_SETLER[ad]
    if amac == "egitim" and not veri_seti.egitime_uygun:
        raise LisansHatasi(
            f"{veri_seti.ad} lisansı ({veri_seti.lisans}) eğitim verisine katılmaya "
            "uygun değil; yalnız değerlendirmede kullanılabilir."
        )
    engel = veri_seti.engel()
    if engel:
        raise VeriSetiHatasi(engel)
    donusturucu = _DONUSTURUCULER.get(ad)
    if donusturucu is None:
        raise NotImplementedError(
            f"{ad} için dönüştürücü yazılmadı; değerlendirme koşusunda elle kullanın."
        )

    ornekler: list[Ornek] = []
    for satir in _hf_yukle(veri_seti, bolum):
        ornek = donusturucu(dict(satir))
        if ornek is None or not ornek.soru:
            continue
        if yalniz_biyoloji and not biyoloji_mi(ornek):
            continue
        ornekler.append(ornek)
        if limit and len(ornekler) >= limit:
            break
    return ornekler
