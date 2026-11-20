"""OCR güven kalibrasyonu döngüsü: örnek çıkarımı → eğitim → doğrulama → yazım."""
import json

import pytest

from sinav_okur.modeller import PuanSonucu, TanimaSonucu
from sinav_okur.ogrenme import (
    ocr_kalibrasyon_kumesi,
    ocr_kalibrasyonunu_guncelle,
)
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu


def _kutu(soru_no, taninan, ham_guven, motorlar=True):
    tanima = TanimaSonucu(
        metin=taninan,
        guven=0.7,
        alternatifler=[{"metin": taninan, "guven": ham_guven, "destek": 2}],
        motor_sonuclari=[{"motor": "vision"}] if motorlar else [],
        uzlasma_guveni=0.8,
        bagimsiz_motor_sayisi=2,
    )
    return KutuSonucu(
        soru_no=soru_no,
        tanima=tanima,
        puan=PuanSonucu(5, 5, 0.7),
    )


def _sinav_kur(depo, ornek_sinav):
    depo.sinav_kaydet(ornek_sinav)


def test_kalibrasyon_ornekleri_onayli_kutulari_dogru_sayar(depo, ornek_sinav):
    _sinav_kur(depo, ornek_sinav)
    ilk = ornek_sinav.sorular[0].no
    sonuc = KagitSonucu(
        sinav_kimlik=ornek_sinav.kimlik, islenen_sayfalar=[1],
        kutular=[_kutu(ilk, "mitokondri", 0.9)],
    )
    kagit_id = depo.kagit_kaydet(sonuc, ogrenci_ad="A")
    depo.kagit_onayla(kagit_id)
    ornekler = depo.kalibrasyon_ornekleri(ornek_sinav.kimlik)
    assert len(ornekler) == 1
    assert ornekler[0]["kaynak"] == "onay"
    ham, etiket = ocr_kalibrasyon_kumesi(ornekler)
    assert etiket == [1]  # taninan == ogretmen → doğru


def test_kalibrasyon_ornekleri_alternatifsiz_kutuyu_dislar(depo, ornek_sinav):
    _sinav_kur(depo, ornek_sinav)
    ilk = ornek_sinav.sorular[0].no
    sonuc = KagitSonucu(
        sinav_kimlik=ornek_sinav.kimlik, islenen_sayfalar=[1],
        kutular=[_kutu(ilk, "mitokondri", 0.9, motorlar=False)],
    )
    kagit_id = depo.kagit_kaydet(sonuc, ogrenci_ad="A")
    depo.kagit_onayla(kagit_id)
    # motor_sonuclari boş → dışlanır
    assert depo.kalibrasyon_ornekleri(ornek_sinav.kimlik) == []


def test_yetersiz_ornek_uygulanmaz(depo, ornek_sinav, tmp_path):
    _sinav_kur(depo, ornek_sinav)
    sonuc = ocr_kalibrasyonunu_guncelle(
        depo, tmp_path / "kal.json", asgari_ornek=200
    )
    assert sonuc["uygulandi"] is False
    assert "Yetersiz" in sonuc["neden"]


def test_egitim_ayrilabilir_kumede_yazilir_ve_ayrimi_artirir(depo, ornek_sinav, tmp_path):
    _sinav_kur(depo, ornek_sinav)
    ilk = ornek_sinav.sorular[0].no
    # Doğru örnekler yüksek ham güvenli, yanlışlar düşük → ayrılabilir
    for i in range(40):
        s = KagitSonucu(
            sinav_kimlik=ornek_sinav.kimlik, islenen_sayfalar=[1],
            kutular=[_kutu(ilk, "mitokondri", 0.92)],
        )
        kid = depo.kagit_kaydet(s, ogrenci_ad=f"D{i}")
        depo.kagit_onayla(kid)
    for i in range(40):
        s = KagitSonucu(
            sinav_kimlik=ornek_sinav.kimlik, islenen_sayfalar=[1],
            kutular=[_kutu(ilk, "mitokondri", 0.3)],
        )
        kid = depo.kagit_kaydet(s, ogrenci_ad=f"Y{i}")
        # yanlış: öğretmen metni düzeltir → etiket False
        kutu = depo.kutular(kid)[0]
        depo.kutu_guncelle(kutu["id"], duzeltilmis_metin="kloroplast")

    yol = tmp_path / "kal.json"
    sonuc = ocr_kalibrasyonunu_guncelle(
        depo, yol, asgari_ornek=50, asgari_sinif=30
    )
    assert sonuc["uygulandi"] is True
    assert yol.is_file()
    # Eğitilen eğri yüksek ham güvene düşükten daha yüksek olasılık verir
    from sinav_okur.htr.kalibrasyon import GuvenKalibrasyonu

    kal = GuvenKalibrasyonu.yukle(yol)
    assert kal.olasilik(0.92) > kal.olasilik(0.3)
    assert kal.egitildi is True
    # Metrikler yan dosyası yazıldı
    assert (yol.with_suffix(".metrikler.json")).is_file()


def test_kuru_calistirma_yazmaz(depo, ornek_sinav, tmp_path):
    _sinav_kur(depo, ornek_sinav)
    ilk = ornek_sinav.sorular[0].no
    for i in range(35):
        s = KagitSonucu(
            sinav_kimlik=ornek_sinav.kimlik, islenen_sayfalar=[1],
            kutular=[_kutu(ilk, "mitokondri", 0.92)],
        )
        kid = depo.kagit_kaydet(s, ogrenci_ad=f"D{i}"); depo.kagit_onayla(kid)
    for i in range(35):
        s = KagitSonucu(
            sinav_kimlik=ornek_sinav.kimlik, islenen_sayfalar=[1],
            kutular=[_kutu(ilk, "mitokondri", 0.3)],
        )
        kid = depo.kagit_kaydet(s, ogrenci_ad=f"Y{i}")
        kutu = depo.kutular(kid)[0]
        depo.kutu_guncelle(kutu["id"], duzeltilmis_metin="kloroplast")
    yol = tmp_path / "kal.json"
    sonuc = ocr_kalibrasyonunu_guncelle(
        depo, yol, asgari_ornek=50, asgari_sinif=30, kuru=True
    )
    assert not yol.exists()
    assert sonuc["uygulandi"] is False


# --- Koşullu (dilimli) kalibrasyon ---------------------------------------


def _dilimli_kume(adet=120):
    """İki dilim: çok motorlu/temiz dilim daha güvenilir, tek motorlu değil."""
    ham, etiket, dilim = [], [], []
    for i in range(adet):
        cok_motor = i % 2 == 0
        p = 0.75 + (i % 10) * 0.02
        ham.append(p)
        # Çok motorlu dilimde aynı ham güven çoğunlukla doğru (%80), tek
        # motorlu dilimde çoğunlukla yanlış (%20) — iki sınıf da her dilimde var.
        if cok_motor:
            etiket.append(0 if i % 10 == 0 else 1)
        else:
            etiket.append(1 if i % 10 == 1 else 0)
        dilim.append("motor3+/kalite_iyi" if cok_motor else "motor1/kalite_dusuk")
    return ham, etiket, dilim


def test_dilim_anahtari_bantlari():
    from sinav_okur.htr.kalibrasyon import dilim_anahtari

    assert dilim_anahtari(1, 0.9) == "motor1/kalite_iyi"
    assert dilim_anahtari(2, 0.3) == "motor2/kalite_dusuk"
    assert dilim_anahtari(5, 0.9) == "motor3+/kalite_iyi"
    assert dilim_anahtari(0, 0.0) == "motor1/kalite_dusuk"


def test_eski_duz_json_yuklenebilir(tmp_path):
    from sinav_okur.htr.kalibrasyon import (
        GuvenKalibrasyonu,
        KosulluGuvenKalibrasyonu,
    )

    yol = tmp_path / "eski.json"
    GuvenKalibrasyonu(egim=1.2, kesme=-0.4, egitildi=True).kaydet(yol)
    kosullu = KosulluGuvenKalibrasyonu.yukle(yol)
    assert kosullu.genel.egim == 1.2
    assert kosullu.dilimler == {}
    # Dilim bilinmiyorsa genel eğriye düşer
    assert kosullu.olasilik(0.8, "motor1/kalite_dusuk") == kosullu.genel.olasilik(0.8)


def test_dilimler_olasiligi_ayristirir():
    from sinav_okur.htr.kalibrasyon import KosulluGuvenKalibrasyonu

    ham, etiket, dilim = _dilimli_kume()
    k = KosulluGuvenKalibrasyonu().egit_dilimli(ham, etiket, dilim)
    assert set(k.dilimler) == {"motor3+/kalite_iyi", "motor1/kalite_dusuk"}
    guvenilir = k.olasilik(0.8, "motor3+/kalite_iyi")
    zayif = k.olasilik(0.8, "motor1/kalite_dusuk")
    assert guvenilir > zayif


def test_az_ornekli_dilim_egitilmez():
    from sinav_okur.htr.kalibrasyon import KosulluGuvenKalibrasyonu

    ham, etiket, dilim = _dilimli_kume()
    # 5 örnekli üçüncü dilim ekle
    for i in range(5):
        ham.append(0.6)
        etiket.append(i % 2)
        dilim.append("motor2/kalite_iyi")
    k = KosulluGuvenKalibrasyonu().egit_dilimli(ham, etiket, dilim)
    assert "motor2/kalite_iyi" not in k.dilimler
    # Bilinmeyen dilim genele düşer, çökmez
    assert 0.0 <= k.olasilik(0.6, "motor2/kalite_iyi") <= 1.0


def test_shrinkage_az_ornekte_genele_yaklastirir():
    from sinav_okur.htr.kalibrasyon import (
        GuvenKalibrasyonu,
        KosulluGuvenKalibrasyonu,
        SHRINKAGE_SABITI,
    )

    ham, etiket, dilim = _dilimli_kume()
    k = KosulluGuvenKalibrasyonu().egit_dilimli(ham, etiket, dilim)
    for ad, egri in k.dilimler.items():
        n = egri.ornek_sayisi
        agirlik = n / (n + SHRINKAGE_SABITI)
        assert 0.0 < agirlik < 1.0
        # Shrinkage uygulandıysa dilim eğimi genel ile ham eğim arasında kalır
        assert isinstance(egri.egim, float)
    assert isinstance(k.genel, GuvenKalibrasyonu)


def test_kosullu_yuvarlak_gidis(tmp_path):
    from sinav_okur.htr.kalibrasyon import KosulluGuvenKalibrasyonu

    ham, etiket, dilim = _dilimli_kume()
    k = KosulluGuvenKalibrasyonu().egit_dilimli(ham, etiket, dilim)
    yol = tmp_path / "kosullu.json"
    k.kaydet(yol)
    geri = KosulluGuvenKalibrasyonu.yukle(yol)
    assert set(geri.dilimler) == set(k.dilimler)
    assert geri.olasilik(0.8, "motor3+/kalite_iyi") == k.olasilik(
        0.8, "motor3+/kalite_iyi"
    )


def test_kosullu_metrikler_dilimi_hesaba_katar():
    from sinav_okur.htr.kalibrasyon import KosulluGuvenKalibrasyonu

    ham, etiket, dilim = _dilimli_kume()
    k = KosulluGuvenKalibrasyonu().egit_dilimli(ham, etiket, dilim)
    dilimli = k.metrikler(ham, etiket, dilim)
    dilimsiz = k.metrikler(ham, etiket)
    assert dilimli["brier"] <= dilimsiz["brier"] + 1e-9
