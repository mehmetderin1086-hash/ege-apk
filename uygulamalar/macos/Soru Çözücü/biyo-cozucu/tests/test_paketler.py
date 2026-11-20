"""Hazır soru-çözüm paketi çeviricisinin testleri.

Şemalar üç gerçek paketten alındı: Palme TYT Biyoloji Soru Bankası (1261
soru), AYT Biyoloji 2018-2025 çıkmış sorular (103) ve TYT Biyoloji 2024-2025
çıkmış sorular (47). Sentetik sözlükler o kayıtların alan alan kopyası —
gerçek arşiv açılmıyor.
"""

from __future__ import annotations

import pytest

from biyo_cozucu.hafiza.etiketleme import KONU_IPUCLARI
from biyo_cozucu.veri.paketler import (
    _AYT_KONU,
    _PALME_KONU_USTU,
    _PALME_UNITE_KONU,
    _TYT_KONU,
    PaketHatasi,
    kayitlari_cevir,
    ozet,
    paket_turunu_bul,
)


def _palme(**degisiklik) -> dict:
    kayit = {
        "unit_no": 9,
        "unit_name": "KALITIM",
        "test_no": 3,
        "test_topic": "Mendel Genetiği",
        "source_pages": [175, 176],
        "question_no": 4,
        "answer_key": "E",
        "question_text": "Aa genotipli iki birey çaprazlanıyor. Buna göre…",
        "options": {
            "A": "Yalnız I", "B": "Yalnız II", "C": "Yalnız III",
            "D": "I ve II", "E": "I, II ve III",
        },
        "correct_option_text": "I, II ve III",
        "solution": {
            "primary_topic": "Mendel kavramları",
            "tags": ["Kalitim"],
            "key_fact": "Alel genler aynı karaktere etki eder.",
            "steps": [
                {"title": "Soru kökü", "text": "Kök olumlu."},
                {"title": "Uygulama", "text": "Çaprazlama 1:2:1 verir."},
            ],
            "statement_analysis": [
                {
                    "statement": "I",
                    "text": "Genotip oranı 1:2:1'dir.",
                    "verdict": "Doğru",
                    "explanation": "Monohibrit çaprazlamanın sonucu.",
                },
            ],
            "option_analysis": {
                "A": "Elendi. Yalnız I yetmez.",
                "E": "Doğru. I, II ve III uyumludur.",
            },
            "common_mistake": "Fenotip oranını genotip sanmak.",
            "conclusion": "Doğru cevap E seçeneğidir.",
            "extraction_confidence": "Yüksek",
            "visual_reference": False,
        },
    }
    kayit.update(degisiklik)
    return kayit


def _palme_paketi(*kayitlar: dict) -> dict:
    return {
        "title": "Palme TYT Biyoloji",
        "unit_stats": [{"unit_no": 9, "unit_name": "KALITIM"}],
        "questions": list(kayitlar) or [_palme()],
    }


def _ayt(**degisiklik) -> dict:
    kayit = {
        "question_id": "AYT_BIYOLOJI_001",
        "soru_no": 1,
        "yil": 2018,
        "sinav": "AYT",
        "unite": "İnsan Fizyolojisi",
        "konu": "Denetleyici ve Düzenleyici Sistem, Duyu Organları",
        "kaynak_pdf_sayfa": 179,
        "kaynak_kitap_sayfa": 177,
        "soru_metni": "İmpuls oluşumuyla ilgili hangisi yanlıştır?",
        "soru_koku": "İmpuls oluşumuyla ilgili hangisi yanlıştır?",
        "secenekler": {"A": "Na+ ve K+ yer değiştirir", "D": "Akson çapı etkilemez"},
        "has_diagram": False,
        "diagram_description": None,
        "soru_pdf": "sorular_pdf/soru_001.pdf",
        "soru_gorseli": "sorular_png/soru_001.png",
        "cozum_cevabi": "D",
        "cevap_anahtari": "D",
        "cevap_anahtari_ile_uyumlu": True,
        "kontrol_sonucu": "UYUMLU",
        "confidence": 0.99,
        "ayrintili_cozum": {
            "cozum_adimlari": ["İmpuls iyon hareketidir.", "Eşik değer gerekir."],
            "secenek_analizi": {
                "A": {"dogru_secenek_mi": False, "aciklama": "İyon hareketi doğrudur."},
                "D": {"dogru_secenek_mi": True, "aciklama": "Akson çapı hızı etkiler."},
            },
            "sonuc": "Yanlış ifade D seçeneğidir.",
            "anahtar_bilgi": "Kalın aksonlarda iletim hızlıdır.",
            "sik_yapilan_hata": "Uyarı şiddetinin impuls büyüklüğünü artırdığını sanmak.",
            "gorsel_yorum": None,
        },
    }
    kayit.update(degisiklik)
    return kayit


def _tyt(**degisiklik) -> dict:
    kayit = {
        "soru_no": 1,
        "yil": 2025,
        "sinav": "2025-TYT",
        "konu": "Canlıların Yapısında Bulunan Temel Bileşikler",
        "kaynak_pdf_sayfa": 4,
        "soru_metni": (
            "Aşağıdakilerden hangisi bir polisakkarittir?\n"
            "A) Glikojen B) Kitin C) Nükleik asit\nD) Trigliserit E) Protein\n\n2025-TYT"
        ),
        "soru_pdf": "sorular_pdf/soru_01.pdf",
        "soru_gorseli": "sorular_png/soru_01.png",
        "cozum_cevabi": "A",
        "cevap_anahtari": "A",
        "cevap_anahtari_ile_uyumlu": True,
        "kontrol_sonucu": "DOĞRU / UYUMLU",
        "cozum": "Glikojen hayvansal depo polisakkaritidir.",
    }
    kayit.update(degisiklik)
    return kayit


# --- Şema tanıma -----------------------------------------------------------


def test_paket_turu_uc_semayi_ayirt_eder():
    assert paket_turunu_bul(_palme_paketi()) == "palme"
    assert paket_turunu_bul({"sorular": [_ayt()]}) == "ayt"
    assert paket_turunu_bul({"sorular": [_tyt()]}) == "tyt"


def test_taninmayan_sema_hata_verir():
    with pytest.raises(PaketHatasi):
        paket_turunu_bul({"veriler": [{"soru": "x"}]})


def test_soru_listesi_yoksa_hata_verir():
    with pytest.raises(PaketHatasi):
        kayitlari_cevir({"sorular": [_tyt()]}, tur="palme")


# --- Palme -----------------------------------------------------------------


def test_palme_kaydi_kanonik_konuya_duser():
    (kayit,) = kayitlari_cevir(_palme_paketi(), kaynak="Palme")
    assert kayit.ornek.konu == "kalıtım"
    assert kayit.ornek.cevap == "E"
    assert kayit.ornek.cevap_turu == "coktan_secmeli"
    assert len(kayit.ornek.secenekler) == 5
    assert kayit.ornek.kaynak == "Palme (s. 175)"
    assert kayit.ornek.etiket_kaynagi == "kural"


def test_palme_cozumunde_secenek_analizi_en_sonda():
    """Kırpma sırası regresyonu — sıra değiştirilirse bu test kırılmalı.

    `hafiza/getirme.py` kanıt çözümünü 1800 karakterde kesiyor. Palme'nin tüm
    katmanları birleştiğinde ortalama 2213 karakter tutuyor ve 1261 kaydın
    1012'si sınırı aşıyor; kümülatif ölçümde sınırı aşan kayıt sayısı çekirdek
    0, +sonuç 1, +ifade analizi 139, +seçenek analizi 1012. Seçenek analizi en
    uzun ve en az bilgi taşıyan katman olduğu için EN SONDA duruyor — böylece
    kırpma sonucu değil yalnız kuyruğu düşürüyor.
    """
    (kayit,) = kayitlari_cevir(_palme_paketi())
    cozum = kayit.ornek.cozum
    assert cozum.index("Temel bilgi:") < cozum.index("Sonuç:")
    assert cozum.index("Sonuç:") < cozum.index("Sık yapılan hata:")
    assert cozum.index("Sık yapılan hata:") < cozum.index("I. Genotip oranı")
    assert cozum.index("I. Genotip oranı") < cozum.index("A) Elendi.")


def test_palme_primary_topic_uniteyi_ezer():
    kayit_verisi = _palme(unit_no=2, unit_name="CANLILARIN TEMEL BİLEŞİMİ")
    kayit_verisi["solution"]["primary_topic"] = "Enzimlerin yapısı ve işleyişi"
    (kayit,) = kayitlari_cevir(_palme_paketi(kayit_verisi))
    assert kayit.ornek.konu == "enzimler"


def test_palme_unite_yedegi_kullanilir():
    kayit_verisi = _palme(unit_no=4, unit_name="EKOLOJİ")
    kayit_verisi["solution"]["primary_topic"] = "Ekolojik organizasyon düzeyleri"
    (kayit,) = kayitlari_cevir(_palme_paketi(kayit_verisi))
    assert kayit.ornek.konu == "ekoloji"
    assert "konu_eslenmedi" not in kayit.uyarilar


def test_palme_bilinmeyen_unite_kural_katmanina_duser():
    kayit_verisi = _palme(unit_no=99, unit_name="BİLİNMEYEN")
    kayit_verisi["solution"]["primary_topic"] = "Tanınmayan konu"
    (kayit,) = kayitlari_cevir(_palme_paketi(kayit_verisi))
    assert "konu_eslenmedi" in kayit.uyarilar


def test_palme_turu_konu_tablosundan_gelir():
    (kayit,) = kayitlari_cevir(_palme_paketi())
    assert kayit.ornek.cozum_turu == "kalitim_hesabi"


def test_palme_unite_adi_turkce_katlanir():
    """`str.capitalize()` "KALITIM"ı "Kalitim" yapıp "ı"yı yok ediyordu."""
    (kayit,) = kayitlari_cevir(_palme_paketi())
    assert "kalıtım" in kayit.ornek.etiketler


def test_palme_dusuk_guven_isaretlenir():
    kayit_verisi = _palme()
    kayit_verisi["solution"]["extraction_confidence"] = "Düşük"
    (kayit,) = kayitlari_cevir(_palme_paketi(kayit_verisi))
    assert kayit.guven == "Düşük"
    assert "dusuk_guven" in kayit.uyarilar


def test_palme_eksik_secenek_isaretlenir():
    (kayit,) = kayitlari_cevir(
        _palme_paketi(_palme(options={"A": "Yalnız I", "B": "Yalnız II"}))
    )
    assert "eksik_secenek" in kayit.uyarilar


def test_palme_cevap_seceneklerdeyse_eksiklik_isaretlenmez():
    """Şıkların bir kısmı ayrıştırılamamış olsa da cevap okunabiliyorsa kayıt sağlam."""
    (kayit,) = kayitlari_cevir(
        _palme_paketi(_palme(options={"E": "I, II ve III"}))
    )
    assert "eksik_secenek" not in kayit.uyarilar


def test_palme_gorsel_referansi_isaretlenir():
    """Palme paketinde soru görseli yok; grafik sorusu metinden okunmak zorunda."""
    kayit_verisi = _palme()
    kayit_verisi["solution"]["visual_reference"] = True
    (kayit,) = kayitlari_cevir(_palme_paketi(kayit_verisi))
    assert "gorselsiz_grafik" in kayit.uyarilar


def test_cozumsuz_kayit_atlanir():
    kayit_verisi = _palme()
    kayit_verisi["solution"] = {}
    assert kayitlari_cevir(_palme_paketi(kayit_verisi)) == []


# --- AYT -------------------------------------------------------------------


def test_ayt_kaydi_gorsel_yolunu_tasir():
    (kayit,) = kayitlari_cevir({"sorular": [_ayt()]}, kaynak="AYT")
    assert kayit.gorsel_yolu == "sorular_png/soru_001.png"
    assert kayit.ornek.konu == "sinir sistemi"
    assert kayit.ornek.cevap == "D"
    assert kayit.ornek.kaynak == "AYT (s. 177)"


def test_ayt_cozumu_katmanlari_birlestirir():
    (kayit,) = kayitlari_cevir({"sorular": [_ayt()]})
    cozum = kayit.ornek.cozum
    assert cozum.startswith("İmpuls iyon hareketidir.")
    assert "Sonuç: Yanlış ifade D" in cozum
    assert cozum.index("Anahtar bilgi:") < cozum.index("A) İyon hareketi")


def test_ayt_cevap_uyusmazligi_isaretlenir():
    (kayit,) = kayitlari_cevir(
        {"sorular": [_ayt(cevap_anahtari_ile_uyumlu=False, cozum_cevabi="B")]}
    )
    assert "cevap_uyusmazligi" in kayit.uyarilar


def test_ayt_dusuk_confidence_kademeye_cevrilir():
    (kayit,) = kayitlari_cevir({"sorular": [_ayt(confidence=0.5)]})
    assert kayit.guven == "Düşük"


# --- TYT -------------------------------------------------------------------


def test_tyt_secenekleri_ayni_satirdan_ayrilir():
    """Şıklar sık sık tek satırda yan yana.

    `etiketleme._SECENEK` satır-çapalı olduğu için 47 gerçek sorunun yalnız
    27'sinde beş şıkkı da yakalıyordu; sınır tabanlı desen 46'sında yakalıyor.
    """
    (kayit,) = kayitlari_cevir({"sorular": [_tyt()]}, kaynak="TYT")
    assert set(kayit.ornek.secenekler) == {"A", "B", "C", "D", "E"}
    assert kayit.ornek.secenekler["A"] == "Glikojen"
    assert kayit.ornek.secenekler["E"] == "Protein"
    assert kayit.ornek.soru == "Aşağıdakilerden hangisi bir polisakkarittir?"
    assert kayit.ornek.konu == "canlıların temel bileşenleri"


def test_tyt_sinav_kunyesi_soru_metninden_dusulur():
    (kayit,) = kayitlari_cevir({"sorular": [_tyt()]})
    assert "2025-TYT" not in kayit.ornek.soru
    assert "2025-TYT" not in "".join(kayit.ornek.secenekler.values())


def test_tyt_bozuk_secenek_satirinda_metin_korunur():
    """Kaynakta bir soruda ")" eksik ("E II ve III"); yarım ayrıştırma yapılmamalı."""
    bozuk = _tyt(soru_metni="Hangisi doğrudur?\nA) I B) II C) III D) I ve II\nE II ve III")
    (kayit,) = kayitlari_cevir({"sorular": [bozuk]})
    assert kayit.ornek.secenekler == {}
    assert "E II ve III" in kayit.ornek.soru
    assert "secenek_ayrilamadi" in kayit.uyarilar


def test_tyt_metin_ici_parantez_sik_sanilmaz():
    duz = _tyt(soru_metni="ATP (A) yapısını açıklayınız.", cozum="Adenin, riboz, fosfat.")
    (kayit,) = kayitlari_cevir({"sorular": [duz]})
    assert kayit.ornek.secenekler == {}
    assert kayit.ornek.cevap_turu == "acik_uclu"


# --- Konu ekseni ve şablon -------------------------------------------------


def test_konu_eslemesi_tamamen_kanonik():
    """Eşleme değerleri `KONU_IPUCLARI` anahtarı olmalı.

    `kapsam.py` konu eksenini doğrudan o sözlükten türetiyor; tek harf yazım
    farkı, örneği kapsam matrisinde sessizce görünmez yapar.
    """
    kanonik = set(KONU_IPUCLARI)
    for tablo in (_PALME_UNITE_KONU, _PALME_KONU_USTU, _AYT_KONU, _TYT_KONU):
        assert set(tablo.values()) <= kanonik


def test_sablon_cozum_tekrar_esiginde_isaretlenir():
    kayitlar = [_palme(question_text=f"Soru {no}?") for no in range(12)]
    ozgun = _palme(question_text="Özgün soru?")
    ozgun["solution"] = dict(
        ozgun["solution"],
        key_fact="Bu açıklama başka hiçbir kayıtta geçmiyor.",
        steps=[{"title": "Uygulama", "text": "Kendine özgü akıl yürütme."}],
        statement_analysis=[],
        option_analysis={},
        conclusion="Kendine özgü sonuç.",
        common_mistake="Kendine özgü hata.",
    )
    cevrilen = kayitlari_cevir(_palme_paketi(*kayitlar, ozgun))
    assert all("sablon_cozum" in k.uyarilar for k in cevrilen[:12])
    assert "sablon_cozum" not in cevrilen[-1].uyarilar


def test_sablonu_ayikla_tekrarlayan_satirlari_dusurur():
    kayitlar = []
    for no in range(12):
        kayit = _palme(question_text=f"Soru {no}?")
        kayit["solution"] = dict(kayit["solution"], conclusion=f"{no}. sorunun sonucu.")
        kayitlar.append(kayit)
    cevrilen = kayitlari_cevir(_palme_paketi(*kayitlar), sablonu_ayikla=True)
    ilk = cevrilen[0]
    assert "sablon_ayiklandi" in ilk.uyarilar
    # Her kayıtta birebir aynı olan satırlar düştü, kayda özgü olan kaldı.
    assert "Alel genler aynı karaktere etki eder." not in ilk.ornek.cozum
    assert "Sonuç: 0. sorunun sonucu." in ilk.ornek.cozum


def test_tumu_sablonsa_cozum_bosaltilmaz():
    """Ayıklama çözümü tüketecekse kayıt olduğu gibi bırakılır."""
    kayitlar = [_palme(question_text=f"Soru {no}?") for no in range(12)]
    cevrilen = kayitlari_cevir(_palme_paketi(*kayitlar), sablonu_ayikla=True)
    assert cevrilen[0].ornek.cozum
    assert "sablon_cozum" in cevrilen[0].uyarilar


def test_ozet_kirpilacak_cozumleri_sayar():
    uzun = _palme()
    uzun["solution"] = dict(uzun["solution"], key_fact="x" * 2000)
    kunye = ozet(kayitlari_cevir(_palme_paketi(uzun, _palme(question_text="Kısa?"))))
    assert kunye["soru"] == 2
    assert kunye["cozum_uzunlugu"]["kirpilacak"] == 1
    assert kunye["konu_dagilimi"]["kalıtım"] == 2


def test_ornek_indeks_metnine_konu_ve_etiket_girer():
    (kayit,) = kayitlari_cevir(_palme_paketi())
    indeks_metni = kayit.ornek.indeks_metni()
    assert "kalıtım" in indeks_metni
    assert "Mendel kavramları" in indeks_metni
    # Çözüm indekse girmemeli: sorgu ile belge aynı uzayda olmalı.
    assert "Alel genler aynı karaktere" not in indeks_metni
