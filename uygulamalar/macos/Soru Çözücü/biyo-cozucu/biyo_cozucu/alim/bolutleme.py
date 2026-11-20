"""Ham metinden soru/çözüm adaylarını ayırma.

Kitap taramaları ve ders videosu dökümleri `bloklari_ayristir()`in beklediği
"SORU:/ÇÖZÜM:/CEVAP:" düzenine uymaz; numaralı sorular, ayrı satırlara
dağılmış şıklar ve "Yanıt: B" gibi çeşitli işaretler kullanırlar. Buradaki
sezgiseller o düzenleri yakalar.

Çıktı her zaman **aday**dır: `guven` alanı ayrıştırmanın ne kadar sağlam
olduğunu söyler, karar öğretmenindir. Otomatik yazma bilinçli olarak yok —
yanlış ayrıştırılmış bir çözüm kalıcı referans örneğe dönüşürse modeli
sürekli yanlış yönlendirir.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# "1.", "12)", "3 -" gibi soru başlangıçları. Satır başında olmalı; metin
# içindeki "1990." gibi sayılar yakalanmasın diye numara 1-3 hane ile sınırlı.
#
# İkinci biçim ayraçsızdır ("2 Mayoz bölünmede…"): OCR küçük noktalama
# işaretlerini sık düşürüyor ve ayracı zorunlu tutmak taranmış sayfalardaki
# soruların tamamının kaçırılmasına yol açıyordu. Ayraçsız biçimde yanlış
# eşleşmeyi sınırlamak için ardından BÜYÜK harf gelmesi şart koşuluyor:
# "8 kromozom bulunur" ve "2n = 8" böylece soru başlangıcı sayılmıyor.
_SORU_NUMARASI = re.compile(
    r"^\s*(\d{1,3})\s*(?:[.)\-–]\s+(?=\S)|\s+(?=[A-ZÇĞİÖŞÜ]))"
)
# "SORU 5", "Soru:" — numara isteğe bağlı.
_SORU_ETIKETI = re.compile(r"^\s*soru\s*(\d{1,3})?\s*[:.\-–]?\s*", re.IGNORECASE)

# Konuşma dili: ders videosu/ses kaydında "1." diye numara söylenmez,
# "Birinci soru", "İkinci soruya geçelim" denir.
_SIRA_SAYILARI = (
    "birinci|ikinci|üçüncü|ucuncu|dördüncü|dorduncu|beşinci|besinci|"
    "altıncı|altinci|yedinci|sekizinci|dokuzuncu|onuncu"
)
_KONUSMA_SORU = re.compile(
    rf"^\s*(?:{_SIRA_SAYILARI})\s+soru\w*\s*[:.\-–]?\s*", re.IGNORECASE
)
# Konuşmada işaretler satır başında değil cümle içinde geçer; metni cümle
# sınırlarından bölerken bu işaretlerden önce satır sonu ekleriz.
_KONUSMA_ISARETLERI = re.compile(
    rf"(?<=[.!?])\s+(?=(?:{_SIRA_SAYILARI})\s+soru|çözüm|cevap|yanıt|soru\s*\d)",
    re.IGNORECASE,
)

# Şık satırı: "A) metin", "A. metin", "A- metin". Türkçe şıklar A-E arası.
_SIK = re.compile(r"^\s*([A-Ea-e])\s*[).\-–]\s*(.+)$")

# Çözüm bölümünün başladığı yer.
_COZUM_ISARETI = re.compile(
    r"^\s*(çözüm|cozum|çözümü|açıklama|aciklama|yanıt\s+açıklaması|çözüm\s+yolu)"
    r"\s*[:.\-–]?\s*",
    re.IGNORECASE,
)

# "CEVAP: B", "Yanıt B", "Doğru cevap: C", "Cevap C şıkkıdır", "Yanıt E seçeneğidir".
# Ek listesi bilinçli olarak kapalı: serbest bırakmak "Cevap C kloroplasttır"
# gibi satırlarda cevabı harfe indirger ve açık uçlu cevabı kaybederdi.
_CEVAP_EKLERI = r"(?:şıkkıdır|şıkkı|şıktır|şık|seçeneğidir|seçeneği|dır|dir|tır|tir)"
_CEVAP_ISARETI = re.compile(
    r"^\s*(?:doğru\s+)?(?:cevap|cevabı|yanıt|yanıtı)\s*[:.\-–]?\s*"
    rf"([A-Ea-e])\b\s*{_CEVAP_EKLERI}?\s*[.]?\s*$",
    re.IGNORECASE,
)
# Açık uçlu sorularda cevap bir cümle olabilir.
_CEVAP_METNI = re.compile(
    r"^\s*(?:doğru\s+)?(?:cevap|cevabı|yanıt|yanıtı)\s*[:.\-–]\s*(.+)$",
    re.IGNORECASE,
)

# PDF üstbilgi/altbilgi gürültüsü: yalnız sayfa numarası ya da çok kısa satır.
_GURULTU = re.compile(r"^\s*(?:sayfa\s*)?\d{1,4}\s*$", re.IGNORECASE)

ASGARI_SORU_KARAKTERI = 15
ASGARI_COZUM_KARAKTERI = 20


@dataclass
class SoruAdayi:
    """Alım önizlemesinde gösterilen, henüz onaylanmamış soru/çözüm."""

    soru: str
    cozum: str = ""
    cevap: str = ""
    secenekler: dict[str, str] = field(default_factory=dict)
    konum: str = ""
    guven: float = 0.5
    uyarilar: list[str] = field(default_factory=list)
    # Ses/video kaynaklı adaylarda sorunun anlatılmaya başladığı saniye —
    # onay arayüzü videoya derin bağlantı (youtu.be/…?t=sn) kurabilsin diye.
    baslangic_sn: float | None = None
    # Aday metninin kaynak dökümle örtüşme oranı (0-1). Model tabanlı
    # çıkarımda halüsinasyon işareti; kural tabanlı yolda hep 1.0.
    dayanak: float = 1.0

    @property
    def cevap_turu(self) -> str:
        """Şık varlığına değil, soru metnine göre belirlenir.

        Eskiden yalnız "şık var mı" bakılıyordu; kitaptaki doğru/yanlış,
        boşluk doldurma, eşleştirme ve sıralama soruları açık uçlu diye
        alınıp modele yanlış biçim talimatıyla gidiyordu.
        """
        from ..soru_turu import cevap_turunu_cikar

        return cevap_turunu_cikar(self.soru, self.secenekler, self.cozum)

    def kullanilabilir_mi(self) -> bool:
        """Hafızaya alınabilecek asgari bütünlükte mi?"""
        return (
            len(self.soru.strip()) >= ASGARI_SORU_KARAKTERI
            and len(self.cozum.strip()) >= ASGARI_COZUM_KARAKTERI
        )

    def sozluk(self) -> dict:
        return {
            "soru": self.soru,
            "cozum": self.cozum,
            "cevap": self.cevap,
            "secenekler": dict(self.secenekler),
            "cevap_turu": self.cevap_turu,
            "konum": self.konum,
            "guven": self.guven,
            "uyarilar": list(self.uyarilar),
            "baslangic_sn": self.baslangic_sn,
            "dayanak": self.dayanak,
        }


def _satirlari_temizle(metin: str) -> list[str]:
    """Sayfa gürültüsünü atar, sözcük ortasındaki tire bölmelerini birleştirir.

    Konuşma dökümünde satır yapısı yoktur; işaretlerin ("Çözüm", "Cevap B",
    "İkinci soru") önüne satır sonu ekleyerek metni kitap düzenine benzetiriz.
    """
    metin = _KONUSMA_ISARETLERI.sub("\n", metin)
    satirlar: list[str] = []
    for ham in metin.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        satir = ham.strip()
        if not satir or _GURULTU.match(satir):
            continue
        # PDF satır sonu tirelemesi: "fotosen-" + "tez" → "fotosentez"
        if satirlar and satirlar[-1].endswith("-") and satir[:1].islower():
            satirlar[-1] = satirlar[-1][:-1] + satir
            continue
        satirlar.append(satir)
    return satirlar


def _soru_baslangici_mi(satir: str) -> bool:
    if _SORU_ETIKETI.match(satir) or _KONUSMA_SORU.match(satir):
        return True
    eslesme = _SORU_NUMARASI.match(satir)
    if not eslesme:
        return False
    # "A) 12) ..." gibi şık satırlarını soru sanmayalım.
    return not _SIK.match(satir)


def _soru_basligini_soy(satir: str) -> str:
    for desen in (_KONUSMA_SORU, _SORU_ETIKETI, _SORU_NUMARASI):
        eslesme = desen.match(satir)
        if eslesme:
            return satir[eslesme.end():].strip()
    return satir.strip()


def _bloklara_ayir(satirlar: list[str]) -> list[list[str]]:
    """Metni soru başlangıçlarından bölerek bloklara ayırır."""
    bloklar: list[list[str]] = []
    mevcut: list[str] = []
    for satir in satirlar:
        if _soru_baslangici_mi(satir) and mevcut:
            bloklar.append(mevcut)
            mevcut = [satir]
        else:
            mevcut.append(satir)
    if mevcut:
        bloklar.append(mevcut)
    # İlk blok soru başlangıcı değilse (kapak, önsöz) at.
    if bloklar and not _soru_baslangici_mi(bloklar[0][0]):
        bloklar = bloklar[1:]
    return bloklar


def _blogu_coz(blok: list[str]) -> SoruAdayi | None:
    """Tek bir soru bloğunu soru/şık/çözüm/cevap parçalarına ayırır."""
    if not blok:
        return None

    soru_satirlari: list[str] = [_soru_basligini_soy(blok[0])]
    secenekler: dict[str, str] = {}
    cozum_satirlari: list[str] = []
    cevap = ""
    uyarilar: list[str] = []
    kip = "soru"

    for satir in blok[1:]:
        harf_cevap = _CEVAP_ISARETI.match(satir)
        if harf_cevap:
            cevap = harf_cevap.group(1).upper()
            kip = "cevap"
            continue

        if _COZUM_ISARETI.match(satir):
            kalan = satir[_COZUM_ISARETI.match(satir).end():].strip()
            kip = "cozum"
            if kalan:
                cozum_satirlari.append(kalan)
            continue

        sik = _SIK.match(satir)
        # Şıklar yalnız soru gövdesinden hemen sonra gelir; çözüm metninde
        # geçen "A) ..." benzeri satırlar şık sayılmamalı.
        if sik and kip in {"soru", "sik"}:
            secenekler[sik.group(1).upper()] = sik.group(2).strip()
            kip = "sik"
            continue

        if kip == "cozum":
            cozum_satirlari.append(satir)
        elif kip == "cevap":
            # Cevaptan sonra gelen metin genelde bir sonraki sorunun
            # gövdesidir; çözüme eklemek iki soruyu birbirine karıştırırdı.
            continue
        elif kip == "sik":
            # Şıklar bitti, açık çözüm işareti yok: kalanı çözüm say.
            kip = "cozum"
            cozum_satirlari.append(satir)
        else:
            soru_satirlari.append(satir)

    soru = " ".join(s for s in soru_satirlari if s).strip()
    cozum = "\n".join(cozum_satirlari).strip()

    if not cevap and cozum_satirlari:
        metin_cevap = _CEVAP_METNI.match(cozum_satirlari[-1])
        if metin_cevap:
            cevap = metin_cevap.group(1).strip()
            cozum = "\n".join(cozum_satirlari[:-1]).strip()

    if not soru or len(soru) < ASGARI_SORU_KARAKTERI:
        return None

    guven = 0.5
    if secenekler and cevap:
        guven = 0.9
    elif cozum and cevap:
        guven = 0.8
    elif cozum:
        guven = 0.65

    if not cozum:
        uyarilar.append("Çözüm metni bulunamadı.")
        guven = min(guven, 0.3)
    if secenekler and cevap and cevap not in secenekler:
        uyarilar.append(f"'{cevap}' cevabı şıklarla eşleşmiyor.")
        guven = min(guven, 0.4)
    if secenekler and len(secenekler) < 2:
        uyarilar.append("Yalnız tek şık okunabildi; şıklar eksik olabilir.")
        guven = min(guven, 0.4)

    return SoruAdayi(
        soru=soru,
        cozum=cozum,
        cevap=cevap,
        secenekler=secenekler,
        guven=guven,
        uyarilar=uyarilar,
    )


def adaylari_cikar(metin: str, *, kaynak=None) -> list[SoruAdayi]:
    """Ham metinden soru/çözüm adayları çıkarır.

    Metin zaten "SORU:/ÇÖZÜM:" düzenindeyse mevcut ayrıştırıcı kullanılır —
    o yol daha kesin ve zaten test edilmiş durumda.
    """
    from ..hafiza.etiketleme import bloklari_ayristir

    duz = bloklari_ayristir(metin)
    if duz:
        adaylar = [
            SoruAdayi(
                soru=str(k.get("soru", "")),
                cozum=str(k.get("cozum", "")),
                cevap=str(k.get("cevap", "")),
                secenekler=dict(k.get("secenekler") or {}),
                guven=0.95,
            )
            for k in duz
        ]
    else:
        satirlar = _satirlari_temizle(metin)
        adaylar = [
            aday
            for aday in (_blogu_coz(blok) for blok in _bloklara_ayir(satirlar))
            if aday is not None
        ]

    if kaynak is not None:
        # Adayın metinde nerede geçtiğini bulup sayfa/zaman damgası ver.
        for aday in adaylar:
            iz = aday.soru[:40]
            konum_indeksi = metin.find(iz) if iz else -1
            if konum_indeksi < 0:
                continue
            parca = kaynak.parca_bul(konum_indeksi)
            if parca is None:
                continue
            aday.konum = parca.konum()
            # Ses/video kaynağında saniye de taşınır: onay arayüzü videoda
            # tam o ana bağlantı verebilsin diye.
            aday.baslangic_sn = parca.baslangic_sn
    return adaylar
