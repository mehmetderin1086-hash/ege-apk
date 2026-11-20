"""Yıllık planın yöntem-teknik, araç-gereç ve ölçme sütunlarını doldurur.

Öneriler uydurulmuyor: resmî programın "öğrenme-öğretme uygulamaları" ve
"öğrenme kanıtları" metinlerinde geçen ifadelerden çıkarılıyor. Böylece plana
yazılan her yöntem, o kazanım için belgede gerçekten önerilmiş oluyor.

Anahtar kelime eşlemesi bilinçli olarak küçük tutuldu; amaç metni etiketlemek,
anlamak değil. Eşleşme çıkmazsa sütun, dersin genel yöntemleriyle doldurulur.
"""

from __future__ import annotations

import re

# (metinde aranan kalıp, plana yazılacak ad)
#
# Kalıpların hepsi `\b` ile kelime başına çapalanır: çapasız kısa kökler kelime
# ORTASINDA eşleşiyordu — "lam" (preparat lamı) "uygulama" içinde tutunca her
# kazanıma mikroskop önerilmişti. Son ek serbest bırakılır ("kart" → "kartlar").
YONTEM_TEKNIK: tuple[tuple[str, str], ...] = (
    (r"\btartış", "Tartışma"),
    (r"\bbeyin fırtınası", "Beyin fırtınası"),
    (r"\bmünazara", "Münazara"),
    (r"\bdeney(?!im)", "Deney"),
    (r"\bgözlem", "Gözlem"),
    (r"\baraştır", "Araştırma"),
    (r"\bdrama\b|\brol oyna|\bcanlandır", "Drama"),
    (r"\bgruplara ayrılır|\bgrup çalışması|\bgruplar\b|\bgruplardan\b", "Grup çalışması"),
    (r"\bsunum|\bsunar\b|\bsunu yap", "Sunum"),
    (r"\bsoru sor|\bsorular sor|\bsoru-cevap|\bsorulabilir|\bsorulur\b", "Soru-cevap"),
    (r"\börnek olay|\bsenaryo", "Örnek olay incelemesi"),
    (r"\bistasyon", "İstasyon"),
    (r"\bkavram haritası|\bzihin haritası", "Kavram haritası"),
    (r"\bproje ödevi|\bproje çalışması|\baraştırma projesi", "Proje tabanlı öğrenme"),
    (r"\boyun(?!ak)", "Eğitsel oyun"),
    (r"\bbenzetim|\bsimülasyon", "Benzetim"),
)

ARAC_GEREC: tuple[tuple[str, str], ...] = (
    (r"\banimasyon", "Animasyon"),
    (r"\bvideo|\bbelgesel|\bkısa film", "Video / belgesel"),
    (r"\bgörsel|\bfotoğraf|\binfografik", "Görsel"),
    (r"\bçalışma yaprağı|\bçalışma kâğıdı|\bçalışma kağıdı", "Çalışma yaprağı"),
    (r"\btablo", "Tablo"),
    (r"\bmikroskop|\bpreparat|\blam\b|\blamel", "Mikroskop ve preparat"),
    (r"\bmodel|\bmaket", "Model"),
    (r"\blaboratuvar|\bdeney düzeneği|\bdeney malzeme", "Laboratuvar malzemeleri"),
    (r"\bsanal laboratuvar|\bsimülasyon", "Sanal laboratuvar"),
    (r"\bkart\b|\bkartlar", "Kart"),
    (r"\bgrafik|\bçizelge", "Grafik"),
    (r"\bharita", "Harita"),
    (r"\bders kitabı", "Ders kitabı"),
    (r"\bafiş|\bposter|\bpano\b", "Afiş / pano"),
    (r"\bweb\b|\bdijital|\bkarekod", "Dijital araçlar"),
    (r"\bslayt|\bprojeksiyon", "Projeksiyon"),
)

OLCME: tuple[tuple[str, str], ...] = (
    (r"\bperformans görevi", "Performans görevi"),
    (r"\bdereceli puanlama anahtarı|\bpuanlama anahtar|\brubrik", "Dereceli puanlama anahtarı"),
    (r"\baçık uçlu", "Açık uçlu sorular"),
    (r"\bkontrol noktası", "Kontrol noktası"),
    (r"\böğrenme günlüğü", "Öğrenme günlüğü"),
    (r"\bzihin haritası", "Zihin haritası"),
    (r"\bkavram haritası", "Kavram haritası"),
    (r"\byapılandırılmış grid", "Yapılandırılmış grid"),
    (r"\btanılayıcı dallanmış ağaç", "Tanılayıcı dallanmış ağaç"),
    (r"\baraştırma raporu|\baraştırma yazısı", "Araştırma raporu"),
    (r"\bbilgi görseli", "Bilgi görseli"),
    (r"\bgözlem formu", "Gözlem formu"),
    (r"\böz değerlendirme|\bkendilerini değerlendir", "Öz değerlendirme"),
    (r"\bakran", "Akran değerlendirme"),
    (r"\bproje ödevi|\bproje çalışması", "Proje"),
    (r"\bçalışma yaprağı", "Çalışma yaprağı"),
    (r"\bmünazara", "Münazara"),
    (r"\bkontrol listesi", "Kontrol listesi"),
)

VARSAYILAN_YONTEM = ("Anlatım", "Soru-cevap")
VARSAYILAN_ARAC = ("Ders kitabı", "Projeksiyon")
VARSAYILAN_OLCME = ("Açık uçlu sorular",)


def _esle(metin: str, tablo: tuple[tuple[str, str], ...], en_fazla: int) -> list[str]:
    if not metin:
        return []
    kucuk = metin.casefold()
    bulunanlar: list[str] = []
    for kalip, ad in tablo:
        if ad in bulunanlar:
            continue
        if re.search(kalip, kucuk):
            bulunanlar.append(ad)
        if len(bulunanlar) >= en_fazla:
            break
    return bulunanlar


def yontemler(metin: str, en_fazla: int = 4) -> list[str]:
    return _esle(metin, YONTEM_TEKNIK, en_fazla) or list(VARSAYILAN_YONTEM)


def araclar(metin: str, en_fazla: int = 4) -> list[str]:
    return _esle(metin, ARAC_GEREC, en_fazla) or list(VARSAYILAN_ARAC)


def olcme_araclari(metin: str, en_fazla: int = 4) -> list[str]:
    return _esle(metin, OLCME, en_fazla) or list(VARSAYILAN_OLCME)
