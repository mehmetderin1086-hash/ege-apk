"""Psikometri: sınavın kendi kalitesini ölçen istatistikler.

Sözleşme: az örneklemde SAYI UYDURULMAZ. 8 kâğıtlık bir sınavda güvenilirlik
katsayısı yazmak bilgi değil yanlış güven üretir.
"""

from __future__ import annotations

import pytest

from sinav_okur.psikometri import (
    YETERLI_DUZELTME,
    YETERLI_KAGIT,
    cronbach_alfa,
    madde_toplam_korelasyonu,
    puan_dagilimi,
    puanlayici_uyumu,
)

AZAMILER = {1: 10.0, 2: 10.0, 3: 10.0, 4: 10.0, 5: 10.0}


def _matris(puanlar: list[list[float]]) -> dict:
    return {
        i: {no: p for no, p in zip(sorted(AZAMILER), satir)}
        for i, satir in enumerate(puanlar)
    }


def _tutarli_sinif(n: int = 12) -> dict:
    """Güçlü öğrenci her soruda güçlü: yüksek güvenilirlik beklenir."""
    return _matris(
        [[float(k) for _ in AZAMILER] for k in range(0, n)]
    )


def _rastgele_sinif() -> dict:
    """Sorular birbiriyle ilgisiz: düşük güvenilirlik beklenir."""
    desen = [
        [10, 0, 10, 0, 10],
        [0, 10, 0, 10, 0],
        [10, 10, 0, 0, 10],
        [0, 0, 10, 10, 0],
        [10, 0, 0, 10, 10],
        [0, 10, 10, 0, 0],
        [10, 10, 10, 0, 0],
        [0, 0, 0, 10, 10],
        [10, 0, 10, 10, 0],
        [0, 10, 0, 0, 10],
        [10, 10, 0, 10, 0],
        [0, 0, 10, 0, 10],
    ]
    return _matris([[float(x) for x in satir] for satir in desen])


def test_yetersiz_kagitta_sayi_uydurulmaz():
    sonuc = cronbach_alfa(_tutarli_sinif(n=6), AZAMILER)

    assert sonuc["deger"] is None
    assert sonuc["neden"] == "yetersiz_kagit"
    assert sonuc["gereken"] == YETERLI_KAGIT
    assert sonuc["mevcut"] == 6


def test_yetersiz_soruda_sayi_uydurulmaz():
    azamiler = {1: 10.0, 2: 10.0}
    matris = {i: {1: float(i), 2: float(i)} for i in range(12)}

    sonuc = cronbach_alfa(matris, azamiler)

    assert sonuc["deger"] is None
    assert sonuc["neden"] == "yetersiz_soru"


def test_tutarli_sinavda_guvenilirlik_yuksek():
    sonuc = cronbach_alfa(_tutarli_sinif(), AZAMILER)

    assert sonuc["deger"] > 0.9
    assert sonuc["band"] == "iyi"


def test_tutarsiz_sinavda_guvenilirlik_dusuk():
    sonuc = cronbach_alfa(_rastgele_sinif(), AZAMILER)

    assert sonuc["deger"] < 0.5


def test_herkes_ayni_puanda_katsayi_tanimsiz():
    matris = _matris([[5.0] * 5 for _ in range(12)])

    sonuc = cronbach_alfa(matris, AZAMILER)

    assert sonuc["deger"] is None
    assert sonuc["neden"] == "varyans_yok"


def test_ters_puanlanmis_madde_anahtar_supheli_isaretlenir():
    """Soruyu bilenler sınavın genelinde daha kötüyse anahtar hatalı olabilir."""
    matris = {}
    for i in range(12):
        taban = float(i)
        matris[i] = {1: taban, 2: taban, 3: taban, 4: taban, 5: 10.0 - taban}

    sonuc = madde_toplam_korelasyonu(matris, AZAMILER)

    assert sonuc[1]["deger"] > 0
    assert sonuc[5]["deger"] < 0
    assert sonuc[5]["band"] == "anahtar_supheli"


def test_madde_korelasyonu_az_kagitta_none():
    sonuc = madde_toplam_korelasyonu(_tutarli_sinif(n=5), AZAMILER)

    assert all(v["deger"] is None for v in sonuc.values())


def test_dagilim_standart_sapma_hesaplar():
    sonuc = puan_dagilimi(_tutarli_sinif(), AZAMILER)

    assert sonuc["ornek"] == 12
    assert sonuc["standart_sapma"] > 0
    assert sonuc["azami"] == pytest.approx(50.0)


def test_tek_kagitta_standart_sapma_none():
    sonuc = puan_dagilimi(_matris([[5.0] * 5]), AZAMILER)

    assert sonuc["ornek"] == 1
    assert sonuc["standart_sapma"] is None


def test_puanlayici_uyumu_sistematik_sapmayi_gorur():
    """Program tutarlı biçimde cimriyse bu görünmeli."""
    duzeltmeler = [
        {"otomatik_puan": 6.0, "son_puan": 8.0} for _ in range(YETERLI_DUZELTME)
    ]

    sonuc = puanlayici_uyumu(duzeltmeler, AZAMILER)

    assert sonuc["mae"] == pytest.approx(2.0)
    assert sonuc["sistematik_sapma"] == pytest.approx(2.0)
    assert sonuc["tam_uyum_orani"] == pytest.approx(0.0)


def test_puanlayici_uyumu_az_veride_none():
    sonuc = puanlayici_uyumu([{"otomatik_puan": 5, "son_puan": 5}], AZAMILER)

    assert sonuc["deger"] is None
    assert sonuc["neden"] == "yetersiz_duzeltme"


def test_puanlayici_uyumu_tam_ortusmeyi_gorur():
    duzeltmeler = [
        {"otomatik_puan": 7.0, "son_puan": 7.0} for _ in range(YETERLI_DUZELTME)
    ]

    sonuc = puanlayici_uyumu(duzeltmeler, AZAMILER)

    assert sonuc["mae"] == pytest.approx(0.0)
    assert sonuc["tam_uyum_orani"] == pytest.approx(1.0)


def test_analiz_r_pbis_soru_satirlarina_islenir(tmp_path):
    """Ölçüldü: alan adı uyuşmazlığı yüzünden r_pbis satırlara hiç geçmiyordu.

    Ters puanlanan bir soru negatif korelasyon verir ve mevcut
    'anahtar şüpheli' bayrağına OR'lanmalıdır.
    """
    from sinav_okur.analiz import sinav_analizi
    from sinav_okur.depo import Depo
    from sinav_okur.modeller import (
        CevapAnahtari,
        PuanSonucu,
        RubrikKalemi,
        Sinav,
        Soru,
        SoruTipi,
        TanimaSonucu,
    )
    from sinav_okur.sonuclar import KagitSonucu, KutuSonucu

    sorular = [
        Soru(
            no=n,
            tip=SoruTipi.KISA_CEVAP,
            metin=f"{n}. soru",
            puan=10.0,
            anahtar=CevapAnahtari(rubrik=[RubrikKalemi(f"ölçüt {n}", 10.0)]),
        )
        for n in range(1, 6)
    ]
    sinav = Sinav(kimlik="RPB", baslik="Test", sorular=sorular)
    depo = Depo(tmp_path / "t.db")
    depo.sinav_kaydet(sinav)
    for i in range(12):
        guclu = i >= 6
        kutular = []
        for n in range(1, 6):
            # 5. soru ters: zayıf öğrenciler doğru yapıyor.
            dogru = (not guclu) if n == 5 else guclu
            kutular.append(
                KutuSonucu(
                    soru_no=n,
                    tanima=TanimaSonucu(metin="x", guven=0.9),
                    puan=PuanSonucu(10.0 if dogru else 0.0, 10.0, 0.9),
                )
            )
        depo.kagit_kaydet(
            KagitSonucu(sinav_kimlik="RPB", islenen_sayfalar=[1], kutular=kutular),
            ogrenci_ad=f"Ö{i}",
        )

    analiz = sinav_analizi(depo, sinav)

    satirlar = {s["no"]: s for s in analiz["sorular"]}
    assert satirlar[1]["r_pbis"] is not None, "r_pbis satırlara işlenmeli"
    assert satirlar[5]["r_pbis"] < 0
    assert satirlar[5]["r_pbis_band"] == "anahtar_supheli"
    assert satirlar[5]["anahtar_supheli"] is True
