"""Şema-bağımsız JSONL soru paketi dönüştürücüsü.

`paketler.py` üç BELİRLİ paket şemasını (Palme/AYT/TYT sözlük paketleri)
elle yazılmış dönüştürücülerle ele alıyor. Elde bunlardan farklı, her biri
kendi alan adlarını kullanan on ayrı JSONL dosyası daha var (8.050 kayıt).
Her biri için ayrı dönüştürücü yazmak hem çok kod hem de bir sonraki dosyada
yine baştan yazmak demek.

Bunlar aslında aynı şeyin farklı adlandırmaları: soru metni, şıklar, cevap,
çözüm, konu, görsel. Bu modül alanları ADAY AD LİSTELERİYLE bulur; yeni bir
kaynak geldiğinde çoğu zaman tek bir ada eklemek yetiyor.

Çözüm metni tek alanda olmayabiliyor: bazı kaynaklarda adımlar, şık analizi,
yaygın hata ve anahtar bilgi ayrı alanlarda duruyor. Bunlar `paketler`in
AYT dönüştürücüsündeki düzenle birleştiriliyor ki hafızaya giren çözüm biçimi
kaynaktan kaynağa değişmesin — model few-shot örneklerinde biçim tutarlılığı
görmezse üslup öğrenmesi bozulur.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ..hafiza.etiketleme import KONU_IPUCLARI, kural_ile_etiketle
from ..metin import nfc
from ..modeller import Ornek
from .paketler import (
    PaketHatasi,
    PaketKaydi,
    _cevap_turu,
    _duzelt,
    _etiketler,
    _guven_adi,
    _secenekleri_ayir,
    _turu_bul,
)

# --- alan adayları ---------------------------------------------------------
#
# Sıra ÖNEMLİ: önce gelen kazanır. "temizlenmiş" alanlar ham alanlardan önce
# geliyor çünkü ham metin soru numarası ve sayfa artığı taşıyabiliyor.

SORU_ALANLARI = (
    "question_text_clean", "question_stem", "stem",
    "question_text_raw", "question_text",
)
SIK_ALANLARI = ("options", "secenekler", "siklar")
CEVAP_ALANLARI = (
    "answer_letter", "official_answer", "correct_answer", "answer_key",
    "solution_answer", "answer", "cevap",
)
CEVAP_METNI_ALANLARI = ("correct_option_text", "official_answer_text")
KONU_ALANLARI = (
    "topic", "section", "unit_name", "chapter_title", "subject",
    "book_section_title", "konu",
)
GORSEL_ALANLARI = (
    "question_image", "image_file", "image", "question_png", "image_path",
    "image_relpath",
)

# Çözümün parçaları — sırayla birleştirilir.
COZUM_PARCALARI: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("Temel bilgi", ("key_concept", "key_fact", "solution_basis", "relevant_facts")),
    ("", ("detailed_solution", "solution_detailed", "solution",
          "official_solution", "official_solution_text", "solution_explanation")),
    ("Adımlar", ("solution_steps",)),
    ("Şık analizi", ("option_analysis", "statement_analysis")),
    ("Görsel yorumu", ("visual_interpretation", "visual_summary")),
    ("Sonuç", ("final_result",)),
    ("Sık yapılan hata", ("common_mistake",)),
    ("Bilimsel not", ("scientific_note",)),
)

GUVEN_ALANLARI = ("confidence", "solution_confidence", "guven")

# Kaynak konu adı → kanonik konu. Anahtar sözcük eşlemesi; 344 farklı kaynak
# konu adı var ve hepsini elle listelemek sürdürülebilir değil. Sıra önemli:
# daha özgül kural önce gelmeli ("solunum sistemi" ile "solunum" ayrı konular).
_KONU_KURALLARI: tuple[tuple[tuple[str, ...], str], ...] = (
    (("solunum sistem", "soluk alıp", "akciğer", "solunum organ", "gaz iletim",
      "gaz alışveriş", "solunumun sinirsel"), "solunum sistemi"),
    (("hücresel solunum", "fermantasyon", "fermentasyon", "atp üretim",
      "oksidatif", "glikoliz", "krebs", "etil alkol", "laktik asit",
      "oksijenli solunum", "oksijensiz solunum", "elektron taşıma"), "solunum"),
    (("fotosentez", "kemosentez", "canlılık ve enerji", "kloroplast",
      "ışığa bağımlı", "calvin", "karbon tutul"), "fotosentez"),
    (("sinir sistem", "nöron", "impuls", "duyu organ", "refleks", "beyin",
      "göz", "görme", "kulak", "işitme", "denge", "koku", "tat", "deri ve dokunma",
      "omurilik", "sinaps", "merkezi sinir"), "sinir sistemi"),
    (("endokrin", "hormon", "hipofiz", "hipotalamus", "tiroit", "tiroksin",
      "böbrek üstü", "adrenal", "insülin", "pankreas bezi"), "hormonlar"),
    (("sindirim", "karaciğer", "safra", "mide", "bağırsak", "enzim salgı"),
     "sindirim"),
    (("dolaşım", "kanın yapı", "kan grubu", "kalp", "damar", "lenf",
      "alyuvar", "akyuvar", "trombosit", "nabız", "tansiyon"), "dolaşım"),
    (("boşaltım", "üriner", "böbre", "nefron", "idrar", "üre ", "azotlu atık",
      "glomerül", "diyaliz"), "boşaltım"),
    (("bağışıklık", "savunma", "antikor", "antijen", "aşı", "serum",
      "lenfosit"), "bağışıklık"),
    (("destek ve hareket", "iskelet", "kas", "kemik", "sarkomer",
      "kayan iplik", "eklem"), "destek ve hareket"),
    (("üreme sistem", "embriyo", "gelişim", "eşeyli üreme", "gebelik",
      "menstrüasyon", "sperm", "yumurta hücre", "döllenme", "plasenta"),
     "üreme ve gelişme"),
    (("mitoz", "mayoz", "hücre bölünme", "eşeysiz üreme", "krossing"),
     "hücre bölünmesi"),
    (("kalıtım", "mendel", "genetik hastalık", "soyağa", "çaprazla",
      "modern genetik", "biyoteknoloji", "klonlama", "varyasyon",
      "eşeye bağlı", "genetik danışma"), "kalıtım"),
    (("nükleik asit", "dna", "rna", "protein sentez", "genetik şifre",
      "genetik kod", "translasyon", "transkripsiyon", "replikasyon", "atp"),
     "nükleik asitler"),
    (("enzim", "vitamin"), "enzimler"),
    (("karbonhidrat", "lipit", "protein", "temel bileşen", "temel bileşik",
      "inorganik", "organik bileşik", "su ve mineral", "mineral", "asit",
      "baz", "hormon yapısı"), "canlıların temel bileşenleri"),
    (("hücre zar", "hücrenin yapı", "hücresel yapı", "organel", "madde geçiş",
      "osmoz", "difüzyon", "sitoplazma", "çekirdek", "ribozom", "mitokondri"),
     "hücre"),
    (("sınıflandır", "âlem", "alem", "virüs", "bakteri", "mantar", "arke",
      "protista", "canlı çeşitliliği", "canlıların çeşitliliği", "tür kavramı"),
     "canlıların sınıflandırılması"),
    (("ekoloji", "ekosistem", "popülasyon", "komünite", "besin zinciri",
      "madde döngü", "çevre", "biyom", "doğal kaynak", "biyolojik çeşitlilik",
      "süksesyon", "simbiyoz", "adaptasyon", "erozyon", "kirlilik"), "ekoloji"),
    (("bitki", "fotoperiyot", "tropizma", "çimlenme", "tohum", "örtü doku",
      "meristem", "ksilem", "floem", "terleme", "stoma", "kök", "gövde",
      "yaprak", "çiçek", "meyve"), "bitki biyolojisi"),
    (("canlıların ortak", "bilimsel yöntem", "biyoloji bilimi",
      "canlılığın temel"), "canlıların ortak özellikleri"),
    (("gen mühendis", "gdo", "genom projesi", "gen aktar", "pcr"),
     "genetik mühendisliği"),
)


def konuyu_kanonige_cevir(ham: str) -> str:
    """Kaynak konu adını 22'lik kanonik eksene çevirir; bulunamazsa boş."""
    alcak = nfc(ham or "").casefold()
    if not alcak:
        return ""
    if alcak in KONU_IPUCLARI:
        return alcak
    for anahtarlar, kanonik in _KONU_KURALLARI:
        if any(a in alcak for a in anahtarlar):
            return kanonik
    return ""


def _ilk_dolu(kayit: dict[str, Any], adaylar: tuple[str, ...]) -> Any:
    for ad in adaylar:
        deger = kayit.get(ad)
        if isinstance(deger, str) and deger.strip():
            return deger
        if isinstance(deger, (dict, list)) and deger:
            return deger
    return None


def _metne_cevir(deger: Any) -> str:
    """Dize, liste ya da sözlük olabilen çözüm parçasını düz metne indirger."""
    if deger is None:
        return ""
    if isinstance(deger, str):
        return _duzelt(deger)
    if isinstance(deger, list):
        satirlar = [_metne_cevir(o) for o in deger]
        return "\n".join(s for s in satirlar if s)
    if isinstance(deger, dict):
        satirlar = [f"{k}: {_metne_cevir(v)}" for k, v in deger.items() if v]
        return "\n".join(satirlar)
    return _duzelt(deger)


def _cozumu_birlestir(kayit: dict[str, Any]) -> str:
    parcalar: list[str] = []
    for baslik, adaylar in COZUM_PARCALARI:
        ham = _ilk_dolu(kayit, adaylar)
        metin = _metne_cevir(ham)
        if not metin:
            continue
        parcalar.append(f"{baslik}: {metin}" if baslik else metin)
    return "\n".join(parcalar).strip()


def _siklari_bul(kayit: dict[str, Any], soru: str) -> tuple[str, dict[str, str]]:
    """Şıkları alandan ya da soru metninin içinden çıkarır."""
    ham = _ilk_dolu(kayit, SIK_ALANLARI)
    if isinstance(ham, dict):
        secenekler = {
            str(h).strip().upper()[:1]: _duzelt(m)
            for h, m in ham.items()
            if str(h).strip() and _duzelt(m)
        }
        if len(secenekler) >= 2:
            return soru, secenekler
    if isinstance(ham, list) and len(ham) >= 2:
        harfler = "ABCDE"
        secenekler = {
            harfler[i]: _duzelt(m) for i, m in enumerate(ham[:5]) if _duzelt(m)
        }
        if len(secenekler) >= 2:
            return soru, secenekler
    # Alan yoksa soru metnine gömülü olabilir.
    return _secenekleri_ayir(soru)


def _cevabi_bul(kayit: dict[str, Any], secenekler: dict[str, str]) -> str:
    ham = _duzelt(_ilk_dolu(kayit, CEVAP_ALANLARI))
    if not ham:
        return _duzelt(_ilk_dolu(kayit, CEVAP_METNI_ALANLARI))
    # Tek harfli cevap ve şıklar varsa harfi kanonikleştir.
    sade = ham.strip(" .)").upper()
    if secenekler and len(sade) == 1 and sade in secenekler:
        return sade
    return ham


def kaydi_cevir(kayit: dict[str, Any], *, kaynak: str = "") -> PaketKaydi | None:
    """Tek bir JSONL kaydını `PaketKaydi`'ye çevirir; çevrilemezse None."""
    if not isinstance(kayit, dict):
        return None
    ham_soru = _duzelt(_ilk_dolu(kayit, SORU_ALANLARI))
    if not ham_soru:
        return None
    cozum = _cozumu_birlestir(kayit)
    if not cozum:
        return None

    soru, secenekler = _siklari_bul(kayit, ham_soru)
    cevap = _cevabi_bul(kayit, secenekler)
    ham_konu = _duzelt(_ilk_dolu(kayit, KONU_ALANLARI))
    konu = konuyu_kanonige_cevir(ham_konu)
    if not konu:
        # Kaynak konu adı eşleşmedi ya da hiç yok ("Karma", "Genel konu
        # değerlendirmesi", konusuz kaynaklar). Soru metninden kural
        # etiketleyicisiyle kestir — kanonik eksene oturmayan örnek kapsam
        # matrisinde hiç sayılmıyor ve raporda görünmez oluyor.
        konu, _tur = kural_ile_etiketle(soru, "")
    gorsel_yolu = _duzelt(_ilk_dolu(kayit, GORSEL_ALANLARI))

    uyarilar: list[str] = []
    if not cevap:
        uyarilar.append("cevap_yok")
    if not konu and ham_konu:
        uyarilar.append("konu_eslesmedi")
    if secenekler and len(secenekler) < 4:
        uyarilar.append("eksik_secenek")
    if cevap and secenekler and len(cevap) == 1 and cevap.upper() not in secenekler:
        uyarilar.append("cevap_uyusmazligi")

    ornek = Ornek(
        soru=soru,
        cozum=cozum,
        cevap=cevap,
        cevap_turu=_cevap_turu(secenekler),
        secenekler=secenekler,
        konu=konu,
        cozum_turu=_turu_bul(ham_konu, soru, cozum),
        etiketler=_etiketler(ham_konu, _duzelt(kayit.get("question_type"))),
        kaynak=kaynak,
        etiket_kaynagi="kural",
    )
    return PaketKaydi(
        ornek=ornek,
        gorsel_yolu=gorsel_yolu,
        guven=_guven_adi(_ilk_dolu(kayit, GUVEN_ALANLARI)),
        uyarilar=tuple(uyarilar),
    )


def jsonl_cevir(yol: Path | str, *, kaynak: str = "") -> list[PaketKaydi]:
    """JSONL dosyasındaki kayıtları çevirir.

    Ayrıştırılamayan satır ATLANIR, dosyayı düşürmez: sekiz bin satırlık bir
    kaynakta tek bozuk satır yüzünden tümünü kaybetmek yanlış takas.
    """
    dosya = Path(yol)
    if not dosya.is_file():
        raise PaketHatasi(f"Dosya bulunamadı: {dosya}")
    kaynak = kaynak or dosya.stem
    kayitlar: list[PaketKaydi] = []
    with dosya.open(encoding="utf-8") as fh:
        for satir in fh:
            satir = satir.strip()
            if not satir:
                continue
            try:
                ham = json.loads(satir)
            except ValueError:
                continue
            cevrilen = kaydi_cevir(ham, kaynak=kaynak)
            if cevrilen is not None:
                kayitlar.append(cevrilen)
    return kayitlar
