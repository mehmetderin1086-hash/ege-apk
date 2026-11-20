"""Yanlış otomatik puanı azaltan seçici kabul/inceleme kapısı."""

from __future__ import annotations

from .modeller import PuanSonucu, Soru, SoruTipi, TanimaSonucu

# Otomatik kabul için tüm eşikler tek yerde adlandırılır; docs/ml_dl_guvenilirlik.md
# ve testler bu sabitlere referans verir. Değerleri değiştirmek kapının yanlış
# otomatik kabul oranını doğrudan etkiler.
ASGARI_OCR_GUVENI = 0.90
ASGARI_UZLASMA_GUVENI = 0.90
ASGARI_KARAR_MARJI = 0.12
ASGARI_BAGIMSIZ_MOTOR = 2
ASGARI_PUANLAMA_GUVENI = 0.82
ASGARI_GIRDI_KALITESI = 0.62
ASGARI_HIZALAMA_GUVENI = 0.80

# Kapının çalışma modları (SINAV_OKUR_GUVENLIK_KAPISI ortam değişkeni).
MOD_KAPALI = "kapali"
MOD_GOLGE = "golge"
MOD_AKTIF = "aktif"
GECERLI_MODLAR = {MOD_KAPALI, MOD_GOLGE, MOD_AKTIF}
VARSAYILAN_MOD = MOD_GOLGE


def otomatik_karari_degerlendir(
    tanima: TanimaSonucu,
    puan: PuanSonucu,
    soru: Soru,
    *,
    bos_dogrulandi: bool = False,
    sayfa_kritik: bool = False,
    hizalama_guveni: float = 1.0,
    ek_nedenler: list[str] | None = None,
) -> PuanSonucu:
    """Kararı yalnız bütün kanıtlar yeterliyse otomatik kesinleştir.

    Bu kapı puanı yeniden hesaplamaz. OCR, görüntü, anahtar ve puanlama
    güvenlerini birlikte değerlendirir; bir koşul eksikse puan öneri olarak
    kalır ve insan incelemesine gider.

    ``hizalama_guveni`` sayfa hizalama güveni; eşiğin altındaysa otomatik kabul
    vetolanır. ``ek_nedenler`` hattan gelen serbest veto nedenleridir
    (ör. çok sayfalı birleşik cevap, cevaplı şablon modu).
    """
    nedenler: list[str] = list(ek_nedenler or [])
    kabul_kanitlari: list[str] = []

    if sayfa_kritik:
        nedenler.append("Sayfa kalite kapısını geçmedi.")
    if hizalama_guveni < ASGARI_HIZALAMA_GUVENI:
        nedenler.append(f"Sayfa hizalama güveni düşük ({hizalama_guveni:.2f}).")
    if soru.tip in {SoruTipi.GRAFIK, SoruTipi.CIZIM, SoruTipi.TABLO}:
        nedenler.append("Görsel cevap türü otomatik kesinleştirilemez.")
    if soru.anahtar.otomatik_uretildi and soru.anahtar.onay_durumu != "onayli":
        nedenler.append("Otomatik cevap anahtarı henüz onaylı değil.")
    if not soru.anahtar.otomatik_puanlama:
        nedenler.append("Bu soru için otomatik puanlama kapalı.")

    if bos_dogrulandi:
        # Yazı bulunmayan bir kutunun bölgesel "çizgi kalitesi" doğal olarak
        # düşüktür. Boş kararı iki ayrı görüntü hazırlığında doğrulanır; veto
        # yalnız sayfa düzeyindeki bulanıklık/parlama kapısından gelir.
        if not nedenler and puan.puan == 0:
            kabul_kanitlari.append("İki aşamalı görüntü denetimi cevap bölgesini boş buldu.")
    else:
        if not tanima.metin.strip():
            nedenler.append("Cevap izi var fakat metin tanınamadı.")
        if tanima.girdi_kalitesi < ASGARI_GIRDI_KALITESI:
            nedenler.append(
                f"Cevap bölgesi kalitesi düşük ({tanima.girdi_kalitesi:.2f})."
            )
        if tanima.guven < ASGARI_OCR_GUVENI:
            nedenler.append(f"Kalibre OCR güveni düşük ({tanima.guven:.2f}).")
        if tanima.uzlasma_guveni < ASGARI_UZLASMA_GUVENI:
            nedenler.append(
                f"OCR metin uzlaşması yetersiz ({tanima.uzlasma_guveni:.2f})."
            )
        if tanima.karar_marji < ASGARI_KARAR_MARJI and len(tanima.alternatifler) > 1:
            nedenler.append(
                f"OCR adayları arasındaki karar marjı düşük ({tanima.karar_marji:.2f})."
            )
        if tanima.bagimsiz_motor_sayisi < ASGARI_BAGIMSIZ_MOTOR:
            # Aynı motorun varyantları kararlıysa puan yine gösterilir; fakat
            # yanlış kabul hedefi için insan incelemesi atlanmaz.
            nedenler.append("İkinci bağımsız OCR motoru doğrulaması yok.")
        if puan.puanlama_guveni < ASGARI_PUANLAMA_GUVENI:
            nedenler.append(
                f"Puanlama güveni düşük ({puan.puanlama_guveni:.2f})."
            )
        if tanima.belirsizlik_nedeni:
            nedenler.append(tanima.belirsizlik_nedeni)
        if not nedenler:
            kabul_kanitlari.extend(
                [
                    "Cevap bölgesi görüntü kalite kapısını geçti.",
                    f"{tanima.bagimsiz_motor_sayisi} bağımsız OCR motoru uzlaştı.",
                    "Kalibre OCR ve puanlama güvenleri eşikleri geçti.",
                ]
            )

    # Puanlayıcının önceden koyduğu bir inceleme bayrağı da veto hakkına sahip.
    # Başka nedenler olsa da kaydedilir: eşik süpürme simülasyonu kayıtlı
    # nedenlerden çalışır, gizli kalan bir veto simülasyonu iyimser saptırır.
    if puan.incele:
        nedenler.append("Puanlama motoru ek insan incelemesi istedi.")

    otomatik_kabul = bool(kabul_kanitlari and not nedenler)
    tanima.otomatik_kabul = otomatik_kabul
    puan.otomatik_kabul = otomatik_kabul
    puan.kabul_nedenleri = kabul_kanitlari if otomatik_kabul else nedenler
    puan.incele = not otomatik_kabul
    if nedenler:
        puan.risk = max(puan.risk, 0.35)
        for neden in dict.fromkeys(nedenler):
            metin = f"⚠ Güvenli karar kapısı: {neden}"
            if metin not in puan.detaylar:
                puan.detaylar.append(metin)
    return puan


def kapi_karari_sozlugu(
    tanima: TanimaSonucu, puan: PuanSonucu, mod: str
) -> dict:
    """Kapı kararını telemetri/denetim için serileştirir."""
    return {
        "tur": "guvenlik_kapisi",
        "mod": mod,
        "otomatik_kabul": bool(puan.otomatik_kabul),
        "nedenler": list(puan.kabul_nedenleri),
        "kalibre_guven": float(tanima.guven),
        "uzlasma_guveni": float(tanima.uzlasma_guveni),
        "bagimsiz_motor": int(tanima.bagimsiz_motor_sayisi),
        "karar_marji": float(tanima.karar_marji),
        "puanlama_guveni": float(puan.puanlama_guveni),
    }
