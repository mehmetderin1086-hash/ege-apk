"""Hazır soru-çözüm paketlerini referans örneğe çevirme.

Bir "paket", bir kitaptan ya da çıkmış sınav derlemesinden üretilmiş, cevap
anahtarıyla doğrulanmış soru + ayrıntılı çözüm kümesidir. `alim/soru_kesici.py`
arşivlerinden farkı çözümün ZATEN var olması: bunlar çözülecek soru değil,
doğrudan referans örnek.

Üç şema tanınıyor ve bilinçli olarak ortak bir ara biçime zorlanmıyor —
aralarındaki fark alan adı değil yapı farkı: Palme çözümü sekiz katmanlı bir
sözlük, AYT'ninki altı katmanlı, TYT'ninki düz metin; TYT'de şıklar soru
metnine gömülü, diğerlerinde ayrı. Ortak olan yalnız çıktı: `Ornek`.

**Çözüm katmanlarının birleştirme sırası load-bearing.** `hafiza/getirme.py`
kanıt çözümünü 1800 karakterde kırpıyor (`azami_cozum_karakteri`) ve Palme'nin
tüm katmanları birleştiğinde ortalama 2213 karakter tutuyor — 1261 kaydın
1015'i sınırı aşıyor. Katmanlar bilgi yoğunluğuna göre sıralandığında kırpma
yalnız en gereksiz kuyruğu düşürür; kümülatif ölçüm (1800'ü aşan kayıt):
çekirdek 0 · +sonuç/hata 1 · +ifade analizi 139 · +seçenek analizi 1015.
Bu yüzden seçenek analizi EN SONA konuyor. Sıra "daha okunaklı" diye
değiştirilirse 1015 kaydın sonucu isteme hiç girmez.

**`visual_reference` / `has_diagram` çözüm türünü belirlemiyor.** Palme'de 344
kayıtta görsel işareti var ama bunların yalnız 25'i gerçekten grafik okuma
sorusu; geri kalanı hücre şeması, soyağacı, tablo. Hepsini `grafik_yorumlama`
saymak o kovayı %27'ye şişirir ve `getirme.py`'nin tür uyumu kademesini
anlamsızlaştırırdı. Aynı gerekçeyle `statement_analysis` varlığı da tür
belirlemiyor: "I, II, III'ten hangileri?" bir soru biçimi, muhakeme yapısı
değil — aynı biçim kalıtımda da ekolojide de çıkıyor.
"""

from __future__ import annotations

import re
from collections import Counter
from dataclasses import dataclass, replace
from typing import Any

from ..hafiza.etiketleme import KONU_IPUCLARI, kural_ile_etiketle
from ..metin import bosluk_topla, katla, nfc
from ..modeller import Ornek, cozum_turu_dogrula

PAKET_TURLERI = ("palme", "ayt", "tyt")

# Bir çözüm satırı korpusta bu kadar kez birebir tekrarlıyorsa şablondur.
# Palme'de 1876 ifade açıklamasının yalnız 258'i, 1261 `key_fact`'in 116'sı
# benzersiz (en sık kalıp 81 kez). Karşılaştırma: AYT'de 310 çözüm adımının
# 310'u benzersiz. Eşik ikisini ayırt edecek kadar yüksek.
SABLON_ESIGI = 10

# Kaydın çözüm satırlarının bu oranı şablonsa kayıt `sablon_cozum` alır.
SABLON_ORANI = 0.5


class PaketHatasi(RuntimeError):
    """Paket tanınmadı ya da beklenen alanları taşımıyor."""


@dataclass(frozen=True)
class PaketKaydi:
    """Çevrilmiş tek soru + çeviri sırasında fark edilen kalite işaretleri.

    `uyarilar` eleme yapmaz, yalnız işaretler: hangi bayrağın elendiği bir
    politika kararı ve çağıranın (CLI) işi.
    """

    ornek: Ornek
    gorsel_yolu: str = ""            # arşive göreli: "sorular_png/soru_001.png"
    guven: str = "Yüksek"            # Yüksek | Orta | Düşük
    uyarilar: tuple[str, ...] = ()


# --- Konu eşlemesi ---------------------------------------------------------
#
# Kaynak konu adları kanonik eksene çevrilmek ZORUNDA: `kapsam.py` konu
# eksenini doğrudan `KONU_IPUCLARI` anahtarlarından türetiyor, listede olmayan
# bir konu dizgesi taşıyan örnek kapsam matrisinde hiç sayılmıyor. Eşleme
# anahtar sözcükle yapılamaz — "Bakteri hücre yapısı" ya da "Ekolojik
# organizasyon düzeyleri" hiçbir ipucuyla eşleşmez.

_PALME_UNITE_KONU: dict[int, str] = {
    1: "canlıların ortak özellikleri",
    2: "canlıların temel bileşenleri",
    3: "hücre",
    4: "ekoloji",
    5: "canlıların sınıflandırılması",   # mikroorganizmalar
    6: "canlıların sınıflandırılması",
    7: "hücre bölünmesi",                # mitoz
    8: "hücre bölünmesi",                # mayoz
    9: "kalıtım",
    10: "sinir sistemi",
    11: "hormonlar",
}

# Ünite kararının fazla kaba kaldığı konular. Yalnız ünite adı ile kanonik
# konunun GERÇEKTEN ayrıştığı yerler; "Ribozom ve protein sentezi" (ünite 3)
# gibi ünitesinde de doğru duran konular bilinçli olarak burada değil.
_PALME_KONU_USTU: dict[str, str] = {
    "Enzimlerin yapısı ve işleyişi": "enzimler",
    "Bileşik enzim - koenzim/kofaktör": "enzimler",
    "Enzim hızını etkileyen faktörler": "enzimler",
    "Denatürasyon": "enzimler",
    "Nükleik asitler": "nükleik asitler",
    "ATP ve fosforilasyon": "solunum",
    "Hücresel solunum ve ATP": "solunum",
    "Üreme, büyüme ve gelişme": "üreme ve gelişme",
    "Eşeyli üreme ve yaşam döngüleri": "üreme ve gelişme",
    "Boşaltım ve atıkların uzaklaştırılması": "boşaltım",
    "Bitkiler alemi": "bitki biyolojisi",
    "Konjugasyon ve gen aktarımı": "genetik mühendisliği",
}

_AYT_KONU: dict[str, str] = {
    "Denetleyici ve Düzenleyici Sistem, Duyu Organları": "sinir sistemi",
    "Destek ve Hareket Sistemi": "destek ve hareket",
    "Dolaşım Sistemleri": "dolaşım",
    "Sindirim Sistemi": "sindirim",
    "Solunum Sistemi": "solunum sistemi",
    "Üriner Sistem": "boşaltım",
    "Üreme Sistemi ve Embriyonik Gelişim": "üreme ve gelişme",
    "Genetik Şifre ve Protein Sentezi": "nükleik asitler",
    "Nükleik Asitlerin Keşfi ve Önemi": "nükleik asitler",
    "Fotosentez": "fotosentez",
    "Kemosentez": "fotosentez",
    "Hücresel Solunum": "solunum",
    "Canlılık ve Enerji": "solunum",
    "Bitkilerin Yapısı": "bitki biyolojisi",
    "Bitkilerde Madde Taşınması": "bitki biyolojisi",
    "Bitkilerde Eşeyli Üreme": "bitki biyolojisi",
    "Komünite Ekolojisi": "ekoloji",
    "Popülasyon Ekolojisi": "ekoloji",
    "Canlılar ve Çevre": "ekoloji",
}

_TYT_KONU: dict[str, str] = {
    "Biyoloji ve Canlıların Ortak Özellikleri": "canlıların ortak özellikleri",
    "Canlıların Yapısında Bulunan Temel Bileşikler": "canlıların temel bileşenleri",
    "Hücre": "hücre",
    "Canlı Âlemleri ve Özellikleri": "canlıların sınıflandırılması",
    "Canlıların Çeşitliliği ve Sınıflandırılması": "canlıların sınıflandırılması",
    "Mitoz ve Eşeysiz Üreme": "hücre bölünmesi",
    "Mayoz ve Eşeyli Üreme": "hücre bölünmesi",
    "Kalıtım ve Biyolojik Çeşitlilik": "kalıtım",
    "Ekosistem Ekolojisi": "ekoloji",
    "Doğal Kaynaklar ve Biyolojik Çeşitliliğin Korunması": "ekoloji",
}

# --- Çözüm türü eşlemesi ---------------------------------------------------
#
# `primary_topic` muhakeme yapısını doğrudan söylediği için kural
# etiketleyicisinden daha isabetli. Kural katmanı soru metnine bakıyor ve
# Palme metinlerinde grafiğin ham sayı dökümü (eksen değerleri) gürültü
# yaratıyor; bu tablo yalnız yapının kesin olduğu konuları kapsıyor, geri
# kalanı `kural_ile_etiketle`'ye düşüyor.
_PALME_TUR: dict[str, str] = {
    "Mendel kavramları": "kalitim_hesabi",
    "Monohibrit ve test çaprazı": "kalitim_hesabi",
    "Soyağacı analizi": "kalitim_hesabi",
    "X’e bağlı kalıtım": "kalitim_hesabi",
    "Y’ye bağlı kalıtım": "kalitim_hesabi",
    "Çok alellilik ve ABO kan grubu": "kalitim_hesabi",
    "Rh faktörü ve kan uyuşmazlığı": "kalitim_hesabi",
    "Eksik baskınlık ve eş baskınlık": "kalitim_hesabi",
    "Bağlı genler ve crossing-over": "kalitim_hesabi",
    "Mayozda kromozom/DNA hesabı": "hesaplama",
    "Sitokinez ve kromozom-DNA hesabı": "hesaplama",
    "Grafik ve tablo yorumlama": "grafik_yorumlama",
    "Bilimsel yöntem ve deney": "deney_kurgusu",
    "Taksonomi ve ikili adlandırma": "siniflandirma",
    "Tür kavramı ve akrabalık": "siniflandirma",
    "Üç domain ve alemler": "siniflandirma",
    "Filogeni ve homolog yapılar": "siniflandirma",
    "Omurgalılar": "siniflandirma",
    "Hayvanlar alemi - omurgasızlar": "siniflandirma",
    "Bitkiler alemi": "siniflandirma",
    "Mantarlar": "siniflandirma",
    "Arkeler": "siniflandirma",
    "Protista - protozoalar": "siniflandirma",
    "Hücre teorisi ve prokaryot-ökaryot": "siniflandirma",
}


# --- Ortak yardımcılar -----------------------------------------------------

# Şık sınırı: satır başı şart DEĞİL. TYT paketinde şıklar sık sık tek satırda
# yan yana ("A) Glikojen B) Kitin C) Nükleik asit"); `etiketleme._SECENEK`
# satır-çapalı olduğu için 47 sorunun yalnız 27'sinde çalışıyordu, bu desen
# 46'sında çalışıyor. Öndeki negatif bakış "(A)" gibi metin içi parantezleri
# ve "12) " gibi madde numaralarını dışarıda tutuyor.
_SIK_SINIRI = re.compile(r"(?<![A-Za-zÇĞİÖŞÜçğıöşü0-9])([A-E])\)\s*")

# Soru metninin kuyruğundaki sınav künyesi ("\n\n2024-TYT"): BM25'e giren
# ama hiçbir soruyu diğerinden ayırmayan gürültü.
_SINAV_KUYRUGU = re.compile(r"\s*\n\s*20\d\d\s*-\s*[A-ZÇĞİÖŞÜ]{2,}\s*$")

_SIK_HARFLERI = ("A", "B", "C", "D", "E")


def _duzelt(deger: object) -> str:
    """Ham JSON değerini kullanılabilir metne indirger."""
    if deger is None:
        return ""
    return nfc(str(deger)).strip()


def _secenekleri_ayir(metin: str) -> tuple[str, dict[str, str]]:
    """Soru metnine gömülü A-E şıklarını ayırır → (kalan kök, şıklar).

    Beş şıkkın tamamı sırayla bulunamazsa metin BÖLÜNMEDEN geri verilir:
    yarım ayrıştırılmış bir soru, ayrıştırılmamış olandan kötüdür — kök
    eksik kalır ve indeks metni bozulur.
    """
    eslesmeler = list(_SIK_SINIRI.finditer(metin))
    harfler = [e.group(1) for e in eslesmeler]
    if harfler[: len(_SIK_HARFLERI)] != list(_SIK_HARFLERI):
        return metin, {}

    secenekler: dict[str, str] = {}
    for sira, eslesme in enumerate(eslesmeler[: len(_SIK_HARFLERI)]):
        bitis = (
            eslesmeler[sira + 1].start()
            if sira + 1 < len(_SIK_HARFLERI)
            else len(metin)
        )
        secenekler[eslesme.group(1)] = bosluk_topla(metin[eslesme.end() : bitis])
    return metin[: eslesmeler[0].start()].strip(), secenekler


def _konuyu_bul(
    ham: str, tablo: dict[str, str], *, yedek: str = ""
) -> tuple[str, bool]:
    """Kaynak konu adını kanonik eksene çevirir → (konu, eşleşti mi)."""
    kanonik = tablo.get(ham) or (yedek if yedek in KONU_IPUCLARI else "")
    return (kanonik, True) if kanonik else ("", False)


def _turu_bul(ham_konu: str, soru: str, cozum: str) -> str:
    """Çözüm türü: önce açık tablo, sonra kural katmanı."""
    dogrudan = _PALME_TUR.get(ham_konu)
    if dogrudan:
        return cozum_turu_dogrula(dogrudan)
    _, tur = kural_ile_etiketle(soru, cozum)
    return tur


def _etiketler(*adaylar: str) -> list[str]:
    """En fazla dört benzersiz, boş olmayan etiket (model katmanıyla aynı sınır)."""
    secilen: list[str] = []
    for aday in adaylar:
        temiz = _duzelt(aday)
        if temiz and temiz not in secilen:
            secilen.append(temiz)
    return secilen[:4]


def _cevap_turu(secenekler: dict[str, str]) -> str:
    return "coktan_secmeli" if secenekler else "acik_uclu"


# --- Palme -----------------------------------------------------------------

# Palme'nin çözümü kural etiketleyicisine VERİLMİYOR ve bu boş dizge onun
# yerini tutuyor. Neden: her kaydın "Soru kökü" adımı aynı şablon cümleyle
# başlıyor — "…doğru biyoloji ilkesini verilen bilgi, grafik, tablo veya
# çaprazlamaya uygulamayı gerektirir." İçindeki "çaprazlama" ve "grafik, tablo"
# 1261 kaydın hepsine `kalitim_hesabi` ve `grafik_yorumlama` puanı yazdırıyordu;
# ilk ölçümde soruların %59'u `kalitim_hesabi` çıktı (gerçek kalıtım ünitesi
# 207 soru). Soru metni gürültüsüz, tür kararı yalnız ona ve `_PALME_TUR`'e
# dayanıyor. AYT ve TYT çözümleri özgün olduğu için onlarda böyle bir kısıt yok.
_PALME_KURAL_COZUMU = ""


def _palme_cozumu(cozum: dict[str, Any], *, sablonu_ayikla: bool = False) -> str:
    """Sekiz katmanı tek metne indirir; sıra için modül docstring'ine bakın."""
    satirlar: list[str] = []
    temel = _duzelt(cozum.get("key_fact"))
    if temel:
        satirlar.append(f"Temel bilgi: {temel}")

    for adim in cozum.get("steps") or []:
        if not isinstance(adim, dict):
            continue
        baslik, govde = _duzelt(adim.get("title")), _duzelt(adim.get("text"))
        if govde:
            satirlar.append(f"{baslik}: {govde}" if baslik else govde)

    sonuc = _duzelt(cozum.get("conclusion"))
    if sonuc:
        satirlar.append(f"Sonuç: {sonuc}")
    hata = _duzelt(cozum.get("common_mistake"))
    if hata:
        satirlar.append(f"Sık yapılan hata: {hata}")

    for ifade in cozum.get("statement_analysis") or []:
        if not isinstance(ifade, dict):
            continue
        etiket = _duzelt(ifade.get("statement"))
        govde = _duzelt(ifade.get("text"))
        hukum = _duzelt(ifade.get("verdict"))
        parca = f"{etiket}. {govde} → {hukum}" if etiket else f"{govde} → {hukum}"
        # Açıklama katmanı hükmün yeniden ifadesinden ibaret olabiliyor
        # (1876 açıklamanın 258'i benzersiz); sadeleştirmede ilk düşen o.
        aciklama = _duzelt(ifade.get("explanation"))
        if aciklama and not sablonu_ayikla:
            parca = f"{parca}: {aciklama}"
        satirlar.append(parca)

    for harf in sorted((cozum.get("option_analysis") or {}).keys()):
        govde = _duzelt((cozum.get("option_analysis") or {})[harf])
        if govde:
            satirlar.append(f"{harf}) {govde}")

    return "\n".join(satirlar)


def _palme_kaydi(
    kayit: dict[str, Any], *, kaynak: str, sablonu_ayikla: bool
) -> PaketKaydi | None:
    cozum_verisi = kayit.get("solution")
    if not isinstance(cozum_verisi, dict):
        return None

    soru = _duzelt(kayit.get("question_text"))
    cozum = _palme_cozumu(cozum_verisi, sablonu_ayikla=sablonu_ayikla)
    if not soru or not cozum:
        return None

    secenekler = {
        _duzelt(h): _duzelt(m)
        for h, m in (kayit.get("options") or {}).items()
        if _duzelt(m)
    }
    cevap = _duzelt(kayit.get("answer_key")).upper()
    ham_konu = _duzelt(cozum_verisi.get("primary_topic"))
    unite_no = kayit.get("unit_no")

    konu, eslesti = _konuyu_bul(
        ham_konu,
        _PALME_KONU_USTU,
        yedek=_PALME_UNITE_KONU.get(unite_no if isinstance(unite_no, int) else 0, ""),
    )

    uyarilar: list[str] = []
    if not eslesti:
        konu, _ = kural_ile_etiketle(soru, _PALME_KURAL_COZUMU)
        uyarilar.append("konu_eslenmedi")
    if len(secenekler) < len(_SIK_HARFLERI) and cevap not in secenekler:
        uyarilar.append("eksik_secenek")
    if cozum_verisi.get("visual_reference"):
        uyarilar.append("gorselsiz_grafik")

    guven = _duzelt(cozum_verisi.get("extraction_confidence")) or "Yüksek"
    if guven == "Düşük":
        uyarilar.append("dusuk_guven")

    sayfalar = [s for s in (kayit.get("source_pages") or []) if isinstance(s, int)]
    atif = f"{kaynak} (s. {sayfalar[0]})" if kaynak and sayfalar else kaynak

    return PaketKaydi(
        ornek=Ornek(
            soru=soru,
            cozum=cozum,
            cevap=cevap,
            cevap_turu=_cevap_turu(secenekler),
            secenekler=secenekler,
            konu=konu,
            cozum_turu=_turu_bul(ham_konu, soru, _PALME_KURAL_COZUMU),
            etiketler=_etiketler(
                # Ünite adları kaynakta tümü büyük harf. `str.capitalize()`
                # ASCII kuralıyla katlayıp "KALITIM" → "Kalitim" yapıyor ve
                # "ı"yı yok ediyor; `katla` Türkçe I→ı eşlemesini koruyor.
                katla(_duzelt(kayit.get("unit_name"))),
                ham_konu,
                _duzelt(kayit.get("test_topic")),
            ),
            kaynak=atif,
            etiket_kaynagi="kural",
        ),
        guven=guven,
        uyarilar=tuple(uyarilar),
    )


# --- AYT -------------------------------------------------------------------


def _ayt_cozumu(cozum: dict[str, Any]) -> str:
    satirlar: list[str] = []
    for adim in cozum.get("cozum_adimlari") or []:
        govde = _duzelt(adim)
        if govde:
            satirlar.append(govde)

    for anahtar, onek in (
        ("sonuc", "Sonuç"),
        ("anahtar_bilgi", "Anahtar bilgi"),
        ("sik_yapilan_hata", "Sık yapılan hata"),
        ("gorsel_yorum", "Görsel yorumu"),
    ):
        govde = _duzelt(cozum.get(anahtar))
        if govde:
            satirlar.append(f"{onek}: {govde}")

    analiz = cozum.get("secenek_analizi") or {}
    for harf in sorted(analiz.keys()):
        deger = analiz[harf]
        govde = _duzelt(deger.get("aciklama") if isinstance(deger, dict) else deger)
        if govde:
            satirlar.append(f"{harf}) {govde}")

    return "\n".join(satirlar)


def _ayt_kaydi(kayit: dict[str, Any], *, kaynak: str) -> PaketKaydi | None:
    cozum_verisi = kayit.get("ayrintili_cozum")
    if not isinstance(cozum_verisi, dict):
        return None

    soru = _duzelt(kayit.get("soru_metni")) or _duzelt(kayit.get("soru_koku"))
    cozum = _ayt_cozumu(cozum_verisi)
    if not soru or not cozum:
        return None

    secenekler = {
        _duzelt(h): _duzelt(m)
        for h, m in (kayit.get("secenekler") or {}).items()
        if _duzelt(m)
    }
    if not secenekler:
        soru, secenekler = _secenekleri_ayir(soru)

    ham_konu = _duzelt(kayit.get("konu"))
    konu, eslesti = _konuyu_bul(ham_konu, _AYT_KONU)
    uyarilar: list[str] = []
    if not eslesti:
        konu, _ = kural_ile_etiketle(soru, cozum)
        uyarilar.append("konu_eslenmedi")
    if kayit.get("cevap_anahtari_ile_uyumlu") is False:
        uyarilar.append("cevap_uyusmazligi")

    yil = _duzelt(kayit.get("yil"))
    sayfa = kayit.get("kaynak_kitap_sayfa") or kayit.get("kaynak_pdf_sayfa")
    atif = f"{kaynak} (s. {sayfa})" if kaynak and isinstance(sayfa, int) else kaynak

    return PaketKaydi(
        ornek=Ornek(
            soru=soru,
            cozum=cozum,
            cevap=_duzelt(kayit.get("cevap_anahtari")).upper(),
            cevap_turu=_cevap_turu(secenekler),
            secenekler=secenekler,
            konu=konu,
            cozum_turu=_turu_bul(ham_konu, soru, cozum),
            etiketler=_etiketler(_duzelt(kayit.get("unite")), ham_konu, yil),
            kaynak=atif,
            etiket_kaynagi="kural",
        ),
        gorsel_yolu=_duzelt(kayit.get("soru_gorseli")),
        guven=_guven_adi(kayit.get("confidence")),
        uyarilar=tuple(uyarilar),
    )


def _guven_adi(deger: object) -> str:
    """Sayısal güveni paketler arası ortak üç kademeye indirir."""
    if not isinstance(deger, int | float):
        return "Yüksek"
    if deger >= 0.9:
        return "Yüksek"
    return "Orta" if deger >= 0.7 else "Düşük"


# --- TYT -------------------------------------------------------------------


def _tyt_kaydi(kayit: dict[str, Any], *, kaynak: str) -> PaketKaydi | None:
    cozum = _duzelt(kayit.get("cozum"))
    ham_soru = _SINAV_KUYRUGU.sub("", _duzelt(kayit.get("soru_metni")))
    if not ham_soru or not cozum:
        return None

    soru, secenekler = _secenekleri_ayir(ham_soru)
    uyarilar: list[str] = []
    if not secenekler:
        uyarilar.append("secenek_ayrilamadi")

    ham_konu = _duzelt(kayit.get("konu"))
    konu, eslesti = _konuyu_bul(ham_konu, _TYT_KONU)
    if not eslesti:
        konu, _ = kural_ile_etiketle(soru, cozum)
        uyarilar.append("konu_eslenmedi")
    if kayit.get("cevap_anahtari_ile_uyumlu") is False:
        uyarilar.append("cevap_uyusmazligi")

    sayfa = kayit.get("kaynak_pdf_sayfa")
    atif = f"{kaynak} (s. {sayfa})" if kaynak and isinstance(sayfa, int) else kaynak

    return PaketKaydi(
        ornek=Ornek(
            soru=soru,
            cozum=cozum,
            cevap=_duzelt(kayit.get("cevap_anahtari")).upper(),
            cevap_turu=_cevap_turu(secenekler),
            secenekler=secenekler,
            konu=konu,
            cozum_turu=_turu_bul(ham_konu, soru, cozum),
            etiketler=_etiketler(ham_konu, _duzelt(kayit.get("sinav"))),
            kaynak=atif,
            etiket_kaynagi="kural",
        ),
        gorsel_yolu=_duzelt(kayit.get("soru_gorseli")),
        uyarilar=tuple(uyarilar),
    )


# --- Genel API -------------------------------------------------------------


def paket_turunu_bul(veri: dict[str, Any]) -> str:
    """Paketin şemasını tanır. Tanınmazsa `PaketHatasi`."""
    if isinstance(veri.get("questions"), list) and "unit_stats" in veri:
        return "palme"
    sorular = veri.get("sorular")
    if isinstance(sorular, list) and sorular:
        ilk = sorular[0]
        if isinstance(ilk, dict):
            if "ayrintili_cozum" in ilk:
                return "ayt"
            if "cozum" in ilk:
                return "tyt"
    raise PaketHatasi(
        "Paket şeması tanınmadı: beklenen alanlar 'questions'+'unit_stats' "
        "(Palme), 'sorular[].ayrintili_cozum' (AYT) ya da 'sorular[].cozum' (TYT)."
    )


def _sablonlari_gec(
    kayitlar: list[PaketKaydi], *, ayikla: bool
) -> list[PaketKaydi]:
    """Korpus genelinde tekrarlayan çözüm satırlarını işaretler ya da ayıklar.

    Tek satırın tekrarlaması yetmez: bir kayıt, satırlarının yarısından fazlası
    şablonsa `sablon_cozum` alır. Amaç, üretilen çözüme üslup bulaştırma
    riskini görünür kılmak — kaydı elemek değil.

    `ayikla` açıkken şablon satırlar çözümden düşürülür ve kayıt bunun yerine
    `sablon_ayiklandi` alır. Ayıklama korpus bilgisi gerektirdiği için tek
    kaydı çeviren fonksiyonlarda değil burada yapılabiliyor.
    """
    sayac: Counter[str] = Counter()
    for kayit in kayitlar:
        sayac.update(set(kayit.ornek.cozum.splitlines()))

    sonuc: list[PaketKaydi] = []
    for kayit in kayitlar:
        satirlar = [s for s in kayit.ornek.cozum.splitlines() if s.strip()]
        sablonlar = [s for s in satirlar if sayac[s] >= SABLON_ESIGI]
        if not satirlar or len(sablonlar) / len(satirlar) <= SABLON_ORANI:
            sonuc.append(kayit)
            continue
        if not ayikla:
            sonuc.append(replace(kayit, uyarilar=(*kayit.uyarilar, "sablon_cozum")))
            continue
        kalan = [s for s in satirlar if sayac[s] < SABLON_ESIGI]
        # Tümü şablonsa çözüm boşalırdı; o durumda kaydı olduğu gibi bırakıp
        # yalnız işaretlemek, çözümsüz bir örnek üretmekten iyidir.
        if not kalan:
            sonuc.append(replace(kayit, uyarilar=(*kayit.uyarilar, "sablon_cozum")))
            continue
        sonuc.append(
            replace(
                kayit,
                ornek=replace(kayit.ornek, cozum="\n".join(kalan)),
                uyarilar=(*kayit.uyarilar, "sablon_ayiklandi"),
            )
        )
    return sonuc


def kayitlari_cevir(
    veri: dict[str, Any],
    *,
    kaynak: str = "",
    tur: str = "",
    sablonu_ayikla: bool = False,
) -> list[PaketKaydi]:
    """Paket sözlüğünü `PaketKaydi` listesine çevirir.

    `sablonu_ayikla` iki katmanda çalışır: Palme'de ifade analizinin açıklama
    kuyruğunu (hükmün yeniden ifadesi) düşürür, sonra korpusta tekrarlayan
    çözüm satırlarını ayıklar. Varsayılan kapalı — çözümün tam hâli hafızaya
    girsin diye; açılması bir kalite kararı ve çağıranın işi.
    """
    tur = tur or paket_turunu_bul(veri)
    if tur not in PAKET_TURLERI:
        raise PaketHatasi(f"Bilinmeyen paket türü: {tur!r}")

    ham = veri.get("questions") if tur == "palme" else veri.get("sorular")
    if not isinstance(ham, list):
        raise PaketHatasi("Pakette soru listesi bulunamadı.")

    kayitlar: list[PaketKaydi] = []
    for girdi in ham:
        if not isinstance(girdi, dict):
            continue
        if tur == "palme":
            kayit = _palme_kaydi(girdi, kaynak=kaynak, sablonu_ayikla=sablonu_ayikla)
        elif tur == "ayt":
            kayit = _ayt_kaydi(girdi, kaynak=kaynak)
        else:
            kayit = _tyt_kaydi(girdi, kaynak=kaynak)
        if kayit is not None:
            kayitlar.append(kayit)

    return _sablonlari_gec(kayitlar, ayikla=sablonu_ayikla)


def ozet(kayitlar: list[PaketKaydi]) -> dict[str, object]:
    """Paketin insan okunur künyesi — hafızaya yazmadan önce ne olduğunu görmek için."""
    konular: Counter[str] = Counter()
    turler: Counter[str] = Counter()
    bayraklar: Counter[str] = Counter()
    for kayit in kayitlar:
        konular[kayit.ornek.konu or "(konusuz)"] += 1
        turler[kayit.ornek.cozum_turu] += 1
        bayraklar.update(kayit.uyarilar)

    uzunluklar = [len(k.ornek.cozum) for k in kayitlar]
    return {
        "soru": len(kayitlar),
        "gorselli": sum(1 for k in kayitlar if k.gorsel_yolu),
        "sikli": sum(1 for k in kayitlar if k.ornek.secenekler),
        "cevapli": sum(1 for k in kayitlar if k.ornek.cevap),
        "konu_dagilimi": dict(konular.most_common()),
        "tur_dagilimi": dict(turler.most_common()),
        "guven_dagilimi": dict(Counter(k.guven for k in kayitlar).most_common()),
        "uyarilar": dict(bayraklar.most_common()),
        "cozum_uzunlugu": {
            "ortalama": round(sum(uzunluklar) / len(uzunluklar)) if uzunluklar else 0,
            "azami": max(uzunluklar, default=0),
            # `getirme.azami_cozum_karakteri` sınırı: bunu aşan kayıtların
            # çözümü kanıt olarak kullanılırken kuyruğundan kırpılacak.
            "kirpilacak": sum(1 for u in uzunluklar if u > 1800),
        },
    }
