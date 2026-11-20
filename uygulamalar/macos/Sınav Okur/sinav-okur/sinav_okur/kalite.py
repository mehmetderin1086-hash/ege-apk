"""Siyah kurşun kalem odaklı tarama ve bölgesel görüntü kalite kapısı.

Varsayılan akış hiçbir rengi silmez. Kullanım sözleşmesi, kâğıtta yalnız basılı
metin ile öğrencinin siyah kurşun kalem cevabının bulunmasıdır. Beklenmedik
doygun renkler girdi anomalisi sayılır ve otomatik kararın kesinleştirilmesini
engeller. Eski, öğretmen tarafından işaretlenmiş arşivler için renk silme
yalnız açıkça ``renkleri_cikar=True`` ile etkinleştirilebilir.
"""

from __future__ import annotations

import os
from dataclasses import asdict, dataclass, field

import cv2
import numpy as np


@dataclass
class TaramaKaliteRaporu:
    sayfa: int
    genislik: int
    yukseklik: int
    netlik: float
    parlama_orani: float
    golge_sapmasi: float
    sayfa_kapsama_orani: float
    egiklik_derecesi: float
    ogretmen_murekkep_orani: float
    kritik: bool = False
    uyarilar: list[str] = field(default_factory=list)
    parmakizi: str = ""

    def sozluk(self) -> dict:
        return asdict(self)


@dataclass
class MurekkepKatmanlari:
    ogrenci: np.ndarray
    ogretmen_maskesi: np.ndarray
    ogretmen_orani: float


@dataclass
class KutuKaliteRaporu:
    netlik: float
    cizgi_kontrasti: float
    onplan_orani: float
    aydinlatma_tekduzeligi: float
    kalite: float
    kritik: bool = False
    uyarilar: list[str] = field(default_factory=list)

    def sozluk(self) -> dict:
        return asdict(self)


def _kucuk_parmakizi(goruntu: np.ndarray) -> str:
    gri = cv2.cvtColor(goruntu, cv2.COLOR_BGR2GRAY)
    kucuk = cv2.resize(gri, (16, 16), interpolation=cv2.INTER_AREA)
    bitler = (kucuk >= float(kucuk.mean())).astype(np.uint8).ravel().tolist()
    return "".join(f"{sum(bit << i for i, bit in enumerate(bitler[j:j + 4])):x}"
                   for j in range(0, len(bitler), 4))


def _parmakizi_uzakligi(a: str, b: str) -> int:
    if not a or not b or len(a) != len(b):
        return 999
    return sum((int(x, 16) ^ int(y, 16)).bit_count() for x, y in zip(a, b))


def ogretmen_murekkebini_ayir(
    goruntu: np.ndarray, *, renkleri_cikar: bool = False
) -> MurekkepKatmanlari:
    """Beklenmedik doygun renkleri ölç; varsayılan olarak görüntüyü koru.

    İşlev adı eski API uyumluluğu için korunmuştur. Yeni siyah-kurşun modunda
    ``ogrenci`` görüntüsü girdinin kopyasıdır. Böylece soluk kurşun çizgiler,
    renk uzayındaki agresif maskeleme nedeniyle yanlışlıkla kaybolmaz.
    """
    if goruntu is None or not goruntu.size:
        bos = np.zeros((1, 1), dtype=np.uint8)
        return MurekkepKatmanlari(np.full((1, 1, 3), 255, np.uint8), bos, 0.0)
    hsv = cv2.cvtColor(goruntu, cv2.COLOR_BGR2HSV)
    h, s, v = cv2.split(hsv)
    # Kırmızı iki uçta yer alır; diğer doygun renkler de girdi anomalisi sayılır.
    kirmizi = (((h <= 12) | (h >= 168)) & (s >= 70) & (v >= 65))
    mavi_yesil = ((h >= 32) & (h <= 145) & (s >= 115) & (v >= 55))
    maske = np.where(kirmizi | mavi_yesil, 255, 0).astype(np.uint8)
    maske = cv2.morphologyEx(
        maske, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8)
    )
    maske = cv2.dilate(maske, np.ones((3, 3), np.uint8), iterations=1)
    ogrenci = goruntu.copy()
    if renkleri_cikar:
        ogrenci[maske > 0] = (255, 255, 255)
    return MurekkepKatmanlari(
        ogrenci=ogrenci,
        ogretmen_maskesi=maske,
        ogretmen_orani=float(np.mean(maske > 0)),
    )


def kursun_kalem_gri(goruntu: np.ndarray) -> np.ndarray:
    """Gölgeyi bastırıp soluk kurşun kalem çizgilerini yerel olarak güçlendir."""
    if goruntu is None or not goruntu.size:
        return np.full((1, 1), 255, np.uint8)
    gri = (
        cv2.cvtColor(goruntu, cv2.COLOR_BGR2GRAY)
        if goruntu.ndim == 3
        else goruntu.astype(np.uint8)
    )
    # Büyük ölçekli aydınlatmayı bölerek fotoğraf gölgesini düzleştir.
    sigma = max(7.0, min(gri.shape[:2]) / 35.0)
    zemin = cv2.GaussianBlur(gri, (0, 0), sigma)
    duz = cv2.divide(gri, np.maximum(zemin, 1), scale=245)
    return cv2.createCLAHE(clipLimit=2.4, tileGridSize=(8, 8)).apply(duz)


# Kâğıt yalıtımı: kırpıntının bu kadarı kâğıt değilse yalıtım uygulanır.
# Altındaki değerlerde kırpıntı zaten temiz demektir ve dokunmak riskli.
KAGIT_YALITIM_ESIGI = 0.85
# Yalıtım sonrası kâğıt bölgesi bu orandan küçük kalırsa güvenilmez sayılıp
# özgün görüntü döndürülür (yanlış tespit tüm cevabı silebilir).
KAGIT_ASGARI_ORAN = 0.25


def kagit_bolgesini_yalit(
    goruntu: np.ndarray, *, zorla: bool = False
) -> tuple[np.ndarray, float]:
    """Kâğıt dışındaki arka planı beyaza boyar; (görüntü, kâğıt oranı) döner.

    Gerçek fotoğraflarda kâğıdın çevresi (masa, örtü, komşu kâğıt) da kadraja
    giriyor ve OCR oradaki dokuları metin sanıyor.

    **Varsayılan KAPALI** (`SINAV_OKUR_KAGIT_YALITIMI=acik` ile açılır).
    Ölçüldü (5 gerçek kutu): CER bazı kutularda iyileşiyor (3.31 → 1.11)
    ama bir kutuda okuma bozulup PUAN 4.67'den 0'a düştü; puan MAE 1.27 →
    2.20. CER iyileşmesi tek başına yeterli kanıt değildir — öğrencinin
    notunu bozan bir "iyileştirme" iyileştirme değildir. Daha çok etiketli
    veri gelince yeniden ölçülmeli.
    """
    if goruntu is None or goruntu.size == 0:
        return goruntu, 1.0
    if not zorla and os.environ.get(
        "SINAV_OKUR_KAGIT_YALITIMI", "kapali"
    ).strip().casefold() != "acik":
        return goruntu, 1.0
    gri = (
        cv2.cvtColor(goruntu, cv2.COLOR_BGR2GRAY)
        if goruntu.ndim == 3
        else goruntu.astype(np.uint8)
    )
    # Kâğıt: parlak ve düşük doygunluklu geniş bölge. Otsu eşiği aydınlatma
    # farklarına bulanıklaştırma sonrası dayanıklı.
    yumusak = cv2.GaussianBlur(gri, (0, 0), max(3.0, min(gri.shape[:2]) / 120.0))
    _esik, maske = cv2.threshold(
        yumusak, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
    )
    if float(np.mean(maske > 0)) >= KAGIT_YALITIM_ESIGI:
        return goruntu, float(np.mean(maske > 0))
    cekirdek = np.ones((9, 9), np.uint8)
    maske = cv2.morphologyEx(maske, cv2.MORPH_CLOSE, cekirdek)
    sayi, etiketler, istatistikler, _ = cv2.connectedComponentsWithStats(maske, 8)
    if sayi <= 1:
        return goruntu, 1.0
    # En büyük parlak bileşen kâğıttır (arka plan dokusu parçalı kalır).
    en_buyuk = 1 + int(np.argmax(istatistikler[1:, cv2.CC_STAT_AREA]))
    kagit = (etiketler == en_buyuk).astype(np.uint8) * 255
    kagit = cv2.morphologyEx(kagit, cv2.MORPH_CLOSE, np.ones((25, 25), np.uint8))
    oran = float(np.mean(kagit > 0))
    if oran < KAGIT_ASGARI_ORAN:
        return goruntu, oran
    sonuc = goruntu.copy()
    disari = kagit == 0
    if sonuc.ndim == 3:
        sonuc[disari] = (255, 255, 255)
    else:
        sonuc[disari] = 255
    return sonuc, oran


def ocr_varyantlari(goruntu: np.ndarray) -> list[tuple[str, np.ndarray]]:
    """Kurşun kalemi birbirini tamamlayan, kayıpsız OCR görünümlerine dönüştür."""
    if goruntu is None or not goruntu.size:
        goruntu = np.full((1, 1, 3), 255, np.uint8)
    gri = cv2.cvtColor(goruntu, cv2.COLOR_BGR2GRAY)
    duz = kursun_kalem_gri(goruntu)
    yumusak = cv2.bilateralFilter(duz, 7, 28, 28)
    esik = cv2.adaptiveThreshold(
        yumusak,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        41,
        11,
    )
    keskin = cv2.addWeighted(
        duz, 1.65, cv2.GaussianBlur(duz, (0, 0), 1.0), -0.65, 0
    )
    return [
        ("orijinal", goruntu.copy()),
        ("golge_duzeltilmis", cv2.cvtColor(duz, cv2.COLOR_GRAY2BGR)),
        ("yumusaltilmis_kontrast", cv2.cvtColor(yumusak, cv2.COLOR_GRAY2BGR)),
        ("uyarlanir_esik", cv2.cvtColor(esik, cv2.COLOR_GRAY2BGR)),
        ("keskin", cv2.cvtColor(keskin, cv2.COLOR_GRAY2BGR)),
    ]


def ocr_varyantlari_genis(goruntu: np.ndarray) -> list[tuple[str, np.ndarray]]:
    """İkinci geçiş için pahalı ek görünümler: büyütme, eğiklik, ters kontrast.

    Aşama-1'de üretilen varyantları TEKRARLAMAZ; yalnız kanıt zayıf kaldığında
    denenecek ek görünümleri döndürür.
    """
    if goruntu is None or not goruntu.size:
        return []
    duz = kursun_kalem_gri(goruntu)
    varyantlar: list[tuple[str, np.ndarray]] = []

    # 2× büyütme: küçük el yazısında motorun karakter çözünürlüğünü artırır.
    buyuk = cv2.resize(
        goruntu, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC
    )
    varyantlar.append(("buyutulmus", buyuk))

    # Ters kontrast: koyu zeminli/soluk kalem izlerinde bazı motorlar düzelir.
    varyantlar.append(("ters_kontrast", cv2.cvtColor(255 - duz, cv2.COLOR_GRAY2BGR)))

    # Eğiklik düzeltme: satır eğimini metin piksellerinin ana eksenine göre çöz.
    try:
        koyu = np.column_stack(np.where(duz < 200))
        if len(koyu) >= 50:
            aci = cv2.minAreaRect(koyu.astype(np.float32))[-1]
            if aci < -45:
                aci = 90 + aci
            if abs(aci) > 0.75:
                yukseklik, genislik = duz.shape[:2]
                donus = cv2.getRotationMatrix2D(
                    (genislik / 2, yukseklik / 2), aci, 1.0
                )
                dogrultulmus = cv2.warpAffine(
                    goruntu, donus, (genislik, yukseklik),
                    flags=cv2.INTER_CUBIC,
                    borderMode=cv2.BORDER_REPLICATE,
                )
                varyantlar.append(("egiklik_duzeltilmis", dogrultulmus))
    except cv2.error:
        pass
    return varyantlar


def kutu_kalitesini_olc(goruntu: np.ndarray) -> KutuKaliteRaporu:
    """Tek cevap bölgesinin okunabilirliğini 0-1 arası ölç.

    Ölçüm bir model güveni değildir; OCR'ın güvenli karar verebilmesi için
    gerekli görüntü kanıtıdır. Soluk, bulanık veya aşırı boş bölgeler incelemeye
    düşürülür.
    """
    if goruntu is None or not goruntu.size:
        return KutuKaliteRaporu(
            0.0, 0.0, 0.0, 0.0, 0.0, True, ["Cevap bölgesi okunamadı."]
        )
    gri = cv2.cvtColor(goruntu, cv2.COLOR_BGR2GRAY)
    duz = kursun_kalem_gri(goruntu)
    netlik = float(cv2.Laplacian(duz, cv2.CV_64F).var())
    zemin = float(np.percentile(duz, 82))
    onplan = duz < max(80.0, zemin - 20.0)
    onplan_orani = float(np.mean(onplan))
    koyu = duz[onplan]
    cizgi_kontrasti = (
        float(np.clip((zemin - float(np.mean(koyu))) / 95.0, 0.0, 1.0))
        if koyu.size
        else 0.0
    )
    aydinlik = cv2.GaussianBlur(gri, (0, 0), max(5.0, min(gri.shape) / 18.0))
    tekduzelik = float(np.clip(1.0 - np.std(aydinlik) / 55.0, 0.0, 1.0))
    netlik_puani = float(np.clip((netlik - 12.0) / 100.0, 0.0, 1.0))
    yogunluk_puani = float(
        np.clip(onplan_orani / 0.012, 0.0, 1.0)
        * np.clip((0.34 - onplan_orani) / 0.20, 0.0, 1.0)
    )
    kalite = float(
        np.clip(
            0.34 * netlik_puani
            + 0.34 * cizgi_kontrasti
            + 0.20 * tekduzelik
            + 0.12 * yogunluk_puani,
            0.0,
            1.0,
        )
    )
    uyarilar: list[str] = []
    if netlik < 28:
        uyarilar.append("Cevap bölgesi bulanık.")
    if cizgi_kontrasti < 0.22 and onplan_orani > 0.001:
        uyarilar.append("Kurşun kalem çizgileri çok soluk.")
    if onplan_orani < 0.001:
        uyarilar.append("Cevap bölgesinde yeterli yazı izi bulunamadı.")
    if tekduzelik < 0.45:
        uyarilar.append("Cevap bölgesinde kuvvetli gölge/ışık farkı var.")
    return KutuKaliteRaporu(
        netlik=netlik,
        cizgi_kontrasti=cizgi_kontrasti,
        onplan_orani=onplan_orani,
        aydinlatma_tekduzeligi=tekduzelik,
        kalite=kalite,
        kritik=bool(kalite < 0.48 or (onplan_orani > 0.001 and cizgi_kontrasti < 0.16)),
        uyarilar=uyarilar,
    )


def sayfa_kalitesini_olc(
    goruntu: np.ndarray, sayfa: int = 1
) -> TaramaKaliteRaporu:
    if goruntu is None or not goruntu.size:
        return TaramaKaliteRaporu(
            sayfa=sayfa,
            genislik=0,
            yukseklik=0,
            netlik=0.0,
            parlama_orani=1.0,
            golge_sapmasi=1.0,
            sayfa_kapsama_orani=0.0,
            egiklik_derecesi=0.0,
            ogretmen_murekkep_orani=0.0,
            kritik=True,
            uyarilar=["Sayfa görüntüsü okunamadı."],
        )
    yukseklik, genislik = goruntu.shape[:2]
    gri = cv2.cvtColor(goruntu, cv2.COLOR_BGR2GRAY)
    hsv = cv2.cvtColor(goruntu, cv2.COLOR_BGR2HSV)
    netlik = float(cv2.Laplacian(gri, cv2.CV_64F).var())
    parlak = (hsv[:, :, 2] >= 250) & (hsv[:, :, 1] <= 28)
    koyu_komsulugu = cv2.dilate(
        (gri < 185).astype(np.uint8), np.ones((41, 41), np.uint8)
    ) > 0
    parlama = float(np.mean(parlak & koyu_komsulugu))
    aydinlik = cv2.GaussianBlur(gri, (0, 0), max(15.0, min(gri.shape) / 45))
    golge_sapmasi = float(np.std(aydinlik) / 255.0)

    # Fotoğraftaki en büyük açık renkli dörtgeni yaklaşık kâğıt kabul et.
    esik = cv2.threshold(gri, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)[1]
    konturlar, _ = cv2.findContours(esik, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    kapsam = 0.0
    egiklik = 0.0
    kagit_maskesi: np.ndarray | None = None
    if konturlar:
        en_buyuk = max(konturlar, key=cv2.contourArea)
        kapsam = float(cv2.contourArea(en_buyuk) / max(1, genislik * yukseklik))
        rect = cv2.minAreaRect(en_buyuk)
        aci = float(rect[2])
        egiklik = min(abs(aci), abs(aci - 90), abs(aci + 90))
        if kapsam >= 0.35:
            kagit_maskesi = np.zeros_like(gri, dtype=np.uint8)
            cv2.drawContours(kagit_maskesi, [en_buyuk], -1, 255, thickness=-1)
    if float(np.mean(gri >= 205)) >= 0.62:
        # Tarayıcı/PDF rasterinde kâğıt çerçevenin tamamıdır; dış kontur
        # bulunmaması sayfanın kesildiği anlamına gelmez.
        kapsam = max(kapsam, 0.92)
    if (
        kapsam >= 0.90
        and float(np.mean(gri >= 245)) >= 0.70
        and golge_sapmasi < 0.10
    ):
        # Doğrudan PDF/tarayıcı çıktısındaki saf beyaz arka plan parlama değildir.
        parlama = 0.0

    katman = ogretmen_murekkebini_ayir(goruntu)
    ogretmen_orani = katman.ogretmen_orani
    if kagit_maskesi is not None:
        kagit_pikseli = kagit_maskesi > 0
        ogretmen_orani = float(
            np.sum((katman.ogretmen_maskesi > 0) & kagit_pikseli)
            / max(1, np.sum(kagit_pikseli))
        )
    uyarilar: list[str] = []
    kritik = False
    if min(genislik, yukseklik) < 900:
        uyarilar.append("Çözünürlük düşük; sayfayı daha yakından yeniden çekin.")
        kritik = True
    if netlik < 45:
        uyarilar.append("Görüntü bulanık; kamera sabitlenerek yeniden çekilmeli.")
        kritik = True
    elif netlik < 85:
        uyarilar.append("Netlik sınırda; ince yazılar öğretmen kontrolüne düşebilir.")
    if parlama > 0.18:
        uyarilar.append("Yoğun ışık parlaması cevapları örtebilir.")
        kritik = True
    elif parlama > 0.08:
        uyarilar.append("Sayfada bölgesel parlama algılandı.")
    if golge_sapmasi > 0.22:
        uyarilar.append("Sayfada kuvvetli gölge/aydınlık farkı var.")
    if kapsam < 0.45:
        uyarilar.append("Kâğıdın tamamı görünmüyor veya başka bir nesne örtüyor olabilir.")
        kritik = True
    if egiklik > 8:
        uyarilar.append(f"Sayfa yaklaşık {egiklik:.0f}° eğik görünüyor.")
    if ogretmen_orani > 0.0002:
        uyarilar.append(
            "Beklenmedik renkli işaret algılandı. Siyah kurşun kalem varsayımı "
            "sağlanmadığı için otomatik karar kesinleştirilmeyecek."
        )
        kritik = True
    return TaramaKaliteRaporu(
        sayfa=sayfa,
        genislik=genislik,
        yukseklik=yukseklik,
        netlik=netlik,
        parlama_orani=parlama,
        golge_sapmasi=golge_sapmasi,
        sayfa_kapsama_orani=kapsam,
        egiklik_derecesi=egiklik,
        ogretmen_murekkep_orani=ogretmen_orani,
        kritik=kritik,
        uyarilar=uyarilar,
        parmakizi=_kucuk_parmakizi(goruntu),
    )


def sayfalari_degerlendir(sayfalar: list[np.ndarray]) -> list[TaramaKaliteRaporu]:
    raporlar = [
        sayfa_kalitesini_olc(goruntu, i)
        for i, goruntu in enumerate(sayfalar, start=1)
    ]
    for i, rapor in enumerate(raporlar):
        for onceki in raporlar[:i]:
            if _parmakizi_uzakligi(rapor.parmakizi, onceki.parmakizi) <= 2:
                rapor.kritik = True
                rapor.uyarilar.append(
                    f"Bu sayfa, yüklenen {onceki.sayfa}. sayfanın tekrarı olabilir."
                )
    return raporlar
