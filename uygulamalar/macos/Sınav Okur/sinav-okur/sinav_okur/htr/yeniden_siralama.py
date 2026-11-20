"""Aday okuma yeniden sıralama: kanıt marjı düşükken bağlama en tutarlı okuma.

``CokluTaniyici`` birden çok aday üretir ve en yüksek OCR kanıtlı olanı
seçer. Kanıt marjı dar olduğunda (iki aday neredeyse eşit) sözlük, cevap
anahtarı ve ders kitabı bağlamı hangi okumanın gerçek olduğuna dair ek
bilgi taşır.

**Anahtar sızıntısı koruması:** anahtar bileşeni bilinçli olarak düşük
ağırlıklıdır ve kazanan değişirse kutu HER ZAMAN incelemeye düşer; puan
arttıysa puanlama güveni tavanlanır. Yani bu modül tek başına hiçbir
öğrenciye puan kazandıramaz — yalnız öğretmene daha doğru bir metin sunar.
"""

from __future__ import annotations

from rapidfuzz import fuzz

from ..guvenlik_kapisi import ASGARI_KARAR_MARJI
from ..metin import eslesme_bicimi
from ..modeller import Soru, TanimaSonucu
from ..terim_sozlugu import TerimSozlugu

AGIRLIK_OCR = 0.55
AGIRLIK_SOZLUK = 0.25
AGIRLIK_ANAHTAR = 0.12
AGIRLIK_KITAP = 0.08

# Kazanan değiştiğinde puanlama güvenine konan tavan.
DEGISIM_GUVEN_TAVANI = 0.6


def _sozluk_uyumu(metin: str, sozluk: TerimSozlugu) -> float:
    """Metindeki sözcüklerin sözlükte karşılığı olma oranı (0-1)."""
    if sozluk.bos_mu():
        return 0.0
    kelimeler = [
        eslesme_bicimi(k) for k in metin.split() if len(eslesme_bicimi(k)) >= 4
    ]
    if not kelimeler:
        return 0.0
    bulunan = sum(1 for k in kelimeler if k in sozluk.terimler)
    return bulunan / len(kelimeler)


def _anahtar_yakinligi(metin: str, soru: Soru) -> float:
    """Cevabın anahtarın herhangi bir biçimine en yüksek benzerliği (0-1)."""
    anahtar = soru.anahtar
    bicimler: list[str] = [
        *anahtar.dogru_cevaplar,
        *anahtar.kabul_edilen_alternatifler,
        *anahtar.siralama,
    ]
    for kalem in anahtar.rubrik:
        bicimler.extend(kalem.tum_bicimler())
    if anahtar.ornek_cevap:
        bicimler.append(anahtar.ornek_cevap)
    if not bicimler:
        return 0.0
    norm = eslesme_bicimi(metin)
    return max(
        (fuzz.token_set_ratio(norm, eslesme_bicimi(b)) / 100.0 for b in bicimler),
        default=0.0,
    )


def _kitap_ortusmesi(metin: str, referans_pasajlari: list[str] | None) -> float:
    if not referans_pasajlari:
        return 0.0
    norm = eslesme_bicimi(metin)
    return max(
        (
            fuzz.partial_token_set_ratio(norm, eslesme_bicimi(p)) / 100.0
            for p in referans_pasajlari
        ),
        default=0.0,
    )


def adaylari_yeniden_sirala(
    tanima: TanimaSonucu,
    soru: Soru,
    sozluk: TerimSozlugu | None = None,
    referans_pasajlari: list[str] | None = None,
) -> tuple[TanimaSonucu, dict | None]:
    """Adayları bağlamla yeniden sıralar; kazanan değişirse incele işaretler.

    Dönüş: (tanıma, karar) — karar ``None`` ise hiçbir şey değişmemiştir.
    """
    # `ham_ocr` kaydı sözlük düzeltmesinin sakladığı DÜZELTİLMEMİŞ metindir ve
    # güveni Platt kalibre ölçekte tutulur; motor adaylarının güveni ise ham
    # kanıt skorudur. İkisini aynı torbaya atmak hem ölçek karıştırır hem de
    # düzeltmeyi geri alır — bu yüzden aday havuzu dışında bırakılır.
    adaylar = [
        a
        for a in (tanima.alternatifler or [])
        if str(a.get("metin", "")).strip() and a.get("kaynak") != "ham_ocr"
    ]
    if len(adaylar) < 2:
        return tanima, None
    if float(tanima.karar_marji or 0.0) >= ASGARI_KARAR_MARJI:
        return tanima, None  # kanıt zaten net; dokunma

    # Yürürlükteki metin (sözlük düzeltmesi uygulanmış olabilir) havuzda
    # yoksa eklenir: aksi halde yeniden sıralama onu asla seçemez ve her
    # seferinde düzeltmeyi geri alır.
    mevcut_norm = eslesme_bicimi(tanima.metin or "")
    if mevcut_norm and not any(
        eslesme_bicimi(str(a.get("metin", ""))) == mevcut_norm for a in adaylar
    ):
        adaylar.insert(
            0,
            {
                "metin": tanima.metin,
                # Kazanan adayın ham kanıtını devralır; ölçek korunur.
                "guven": max(
                    float(a.get("guven", 0.0) or 0.0) for a in adaylar
                ),
            },
        )

    sozluk = sozluk or TerimSozlugu()
    skorlar: list[dict] = []
    for aday in adaylar:
        metin = str(aday.get("metin", ""))
        ocr = float(aday.get("guven", 0.0) or 0.0)
        skor = (
            AGIRLIK_OCR * ocr
            + AGIRLIK_SOZLUK * _sozluk_uyumu(metin, sozluk)
            + AGIRLIK_ANAHTAR * _anahtar_yakinligi(metin, soru)
            + AGIRLIK_KITAP * _kitap_ortusmesi(metin, referans_pasajlari)
        )
        skorlar.append({"metin": metin, "ocr": round(ocr, 4), "skor": round(skor, 4)})
    skorlar.sort(key=lambda s: -s["skor"])
    secilen = skorlar[0]["metin"]
    if eslesme_bicimi(secilen) == eslesme_bicimi(tanima.metin or ""):
        return tanima, None

    yeni = TanimaSonucu(
        metin=secilen,
        guven=tanima.guven,
        alternatifler=list(tanima.alternatifler),
        motor_sonuclari=list(tanima.motor_sonuclari),
        ogretmen_murekkebi_ayrildi=tanima.ogretmen_murekkebi_ayrildi,
        uzlasma_guveni=tanima.uzlasma_guveni,
        bagimsiz_motor_sayisi=tanima.bagimsiz_motor_sayisi,
        karar_marji=tanima.karar_marji,
        belirsizlik_nedeni=(
            f"{tanima.belirsizlik_nedeni} · Aday yeniden sıralama devrede"
        ).strip(" ·"),
        girdi_kalitesi=tanima.girdi_kalitesi,
        model_surumu=dict(tanima.model_surumu),
        otomatik_kabul=False,
    )
    karar = {
        "tur": "aday_yeniden_siralama",
        "onceki": tanima.metin,
        "secilen": secilen,
        "skorlar": skorlar[:4],
    }
    return yeni, karar


def puan_sonucunu_kisitla(puan_sonucu, onceki_puan: float | None = None):
    """Yeniden sıralama sonrası kapı vetosu ve güven tavanını uygular."""
    puan_sonucu.incele = True
    puan_sonucu.otomatik_kabul = False
    puan_sonucu.kabul_nedenleri = list(puan_sonucu.kabul_nedenleri) + [
        "Aday yeniden sıralama devrede: okuma bağlamla seçildi, öğretmen doğrulamalı."
    ]
    if onceki_puan is not None and puan_sonucu.puan > onceki_puan:
        puan_sonucu.puanlama_guveni = min(
            float(puan_sonucu.puanlama_guveni or puan_sonucu.guven),
            DEGISIM_GUVEN_TAVANI,
        )
        puan_sonucu.guven = min(float(puan_sonucu.guven), DEGISIM_GUVEN_TAVANI)
    return puan_sonucu
