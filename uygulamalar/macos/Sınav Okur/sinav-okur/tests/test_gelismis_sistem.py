from pathlib import Path

import cv2
import numpy as np

from sinav_okur.analiz import altin_test_metrikleri
from sinav_okur.depo import Depo
from sinav_okur.htr import YapayTaniyici
from sinav_okur.htr.coklu import CokluTaniyici
from sinav_okur.kalite import (
    kutu_kalitesini_olc,
    ocr_varyantlari,
    ogretmen_murekkebini_ayir,
    sayfa_kalitesini_olc,
)
from sinav_okur.modeller import (
    CevapAnahtari,
    RubrikKalemi,
    Soru,
    SoruTipi,
    TanimaSonucu,
)
from sinav_okur.modeller import PuanSonucu, Sinav
from sinav_okur.ogrenci import ogrenci_esle, ogrenci_listesi_oku
from sinav_okur.puanlama import puanla
from sinav_okur.puanlama.yapisal import ifadeler_esdeger
from sinav_okur.guvenlik_kapisi import otomatik_karari_degerlendir
from sinav_okur.htr.kalibrasyon import GuvenKalibrasyonu
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu


def _soru(tip, anahtar, puan=10):
    return Soru(
        no=1,
        tip=tip,
        metin="Örnek soru",
        puan=puan,
        anahtar=anahtar,
    )


def test_siyah_kursun_modu_rengi_silmez_ama_anomaliyi_olcer():
    gorsel = np.full((300, 600, 3), 255, np.uint8)
    cv2.putText(gorsel, "ogrenci", (30, 130), cv2.FONT_HERSHEY_SIMPLEX, 1.4, (40, 40, 40), 3)
    cv2.line(gorsel, (20, 180), (580, 220), (0, 0, 220), 8)

    katman = ogretmen_murekkebini_ayir(gorsel)

    assert katman.ogretmen_orani > 0
    assert np.array_equal(katman.ogrenci, gorsel)
    assert np.mean(katman.ogrenci[105:135, 30:220, :]) < 250
    eski_mod = ogretmen_murekkebini_ayir(gorsel, renkleri_cikar=True)
    assert np.mean(eski_mod.ogrenci[185:215, :, :]) > np.mean(gorsel[185:215, :, :])


def test_kalite_raporu_beklenmedik_rengi_incelemeye_ayirir():
    gorsel = np.full((1400, 1000, 3), 245, np.uint8)
    cv2.putText(gorsel, "10/20", (650, 180), cv2.FONT_HERSHEY_SIMPLEX, 2, (0, 0, 220), 5)
    cv2.putText(gorsel, "cevap", (100, 600), cv2.FONT_HERSHEY_SIMPLEX, 2, (30, 30, 30), 4)

    rapor = sayfa_kalitesini_olc(gorsel)

    assert rapor.ogretmen_murekkep_orani > 0
    assert rapor.kritik is True
    assert any("otomatik karar kesinleştirilmeyecek" in x for x in rapor.uyarilar)


def test_coklu_ocr_uzlasmasi_ve_varyantlar():
    gorsel = np.full((180, 500, 3), 255, np.uint8)
    cv2.putText(gorsel, "mitokondri", (20, 100), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 0), 2)
    taniyici = CokluTaniyici([("sabit", YapayTaniyici("mitokondri", 0.88))])

    sonuc = taniyici.kutu_taniy(gorsel)

    assert sonuc.metin == "mitokondri"
    assert sonuc.guven >= 0.8
    assert len(sonuc.motor_sonuclari) == len(ocr_varyantlari(gorsel))
    assert sonuc.bagimsiz_motor_sayisi == 1
    assert "Yalnız bir bağımsız" in sonuc.belirsizlik_nedeni


def test_kursun_kalem_bolge_kalitesi_kanit_uretir():
    gorsel = np.full((220, 900, 3), 242, np.uint8)
    cv2.putText(
        gorsel, "mitokondri enerji uretir", (30, 125),
        cv2.FONT_HERSHEY_SIMPLEX, 1.2, (95, 95, 95), 2,
    )
    rapor = kutu_kalitesini_olc(gorsel)
    assert 0 < rapor.cizgi_kontrasti <= 1
    assert 0 < rapor.kalite <= 1


def test_guvenlik_kapisi_iki_bagimsiz_motor_olmadan_kabul_etmez():
    soru = _soru(
        SoruTipi.KISA_CEVAP,
        CevapAnahtari(rubrik=[RubrikKalemi("mitokondri", 10)]),
    )
    tanima = TanimaSonucu(
        "mitokondri",
        0.98,
        alternatifler=[{"metin": "mitokondri", "guven": 0.98}],
        uzlasma_guveni=0.99,
        bagimsiz_motor_sayisi=1,
        karar_marji=0.5,
        girdi_kalitesi=0.9,
    )
    sonuc = otomatik_karari_degerlendir(
        tanima, puanla(tanima, soru), soru
    )
    assert sonuc.incele is True
    assert sonuc.otomatik_kabul is False


def test_guvenlik_kapisi_tum_kanitlarla_otomatik_kabul_eder():
    soru = _soru(
        SoruTipi.KISA_CEVAP,
        CevapAnahtari(rubrik=[RubrikKalemi("mitokondri", 10)]),
    )
    tanima = TanimaSonucu(
        "mitokondri",
        0.98,
        alternatifler=[{"metin": "mitokondri", "guven": 0.98}],
        uzlasma_guveni=0.99,
        bagimsiz_motor_sayisi=2,
        karar_marji=0.5,
        girdi_kalitesi=0.9,
    )
    puan = puanla(tanima, soru)
    sonuc = otomatik_karari_degerlendir(tanima, puan, soru)
    assert sonuc.incele is False
    assert sonuc.otomatik_kabul is True
    assert len(sonuc.kabul_nedenleri) == 3


def test_guven_kalibrasyonu_kaydedilip_yuklenir(tmp_path: Path):
    ham = [0.1, 0.2, 0.3, 0.4, 0.45] * 2 + [0.65, 0.72, 0.8, 0.9, 0.97] * 2
    etiket = [0] * 10 + [1] * 10
    kalibrasyon = GuvenKalibrasyonu().egit(ham, etiket)
    yol = tmp_path / "ocr-kalibrasyon.json"
    kalibrasyon.kaydet(yol)
    yuklu = GuvenKalibrasyonu.yukle(yol)
    assert yuklu.olasilik(0.9) > yuklu.olasilik(0.2)
    assert yuklu.metrikler(ham, etiket)["brier"] < 0.25


def test_siralama_kismi_puan_verir():
    soru = _soru(
        SoruTipi.SIRALAMA,
        CevapAnahtari(siralama=["gözlem", "hipotez", "deney", "sonuç"]),
    )
    sonuc = puanla(TanimaSonucu("gözlem, deney, hipotez, sonuç"), soru)
    assert 0 < sonuc.puan < soru.puan
    assert sonuc.kararlar[0]["tur"] == "siralama"


def test_eslestirme_madde_madde_puanlanir():
    soru = _soru(
        SoruTipi.ESLESTIRME,
        CevapAnahtari(eslestirmeler={"A": "1", "B": "2", "C": "3"}),
        puan=12,
    )
    sonuc = puanla(TanimaSonucu("A-1, B-3, C-3"), soru)
    assert sonuc.puan == 8
    assert sum(1 for k in sonuc.kararlar if k["dogru"]) == 2


def test_yanlis_sonuc_dogru_yontemden_puan_alir():
    soru = _soru(
        SoruTipi.SAYISAL,
        CevapAnahtari(
            dogru_cevaplar=["12 cm"],
            birimler=["cm"],
            yontem_adimlari=["alan formülü uygulanır"],
            rubrik=[RubrikKalemi("alan formülü uygulanır", 3, kategori="yontem")],
        ),
        puan=10,
    )
    sonuc = puanla(TanimaSonucu("Alan formülü uygulanır, sonuç 14 cm.", 1.0), soru)
    assert sonuc.puan == 3
    assert "yalnız" in sonuc.aciklama.casefold()


def test_cebirsel_esdegerlik():
    assert ifadeler_esdeger("2*(x+1)", "2*x+2")
    assert not ifadeler_esdeger("2*x+1", "2*x+2")


def test_grafik_metni_otomatik_kesinlestirilmez():
    soru = _soru(
        SoruTipi.GRAFIK,
        CevapAnahtari(rubrik=[RubrikKalemi("eksenler doğru adlandırılır", 10)]),
    )
    sonuc = puanla(TanimaSonucu("Eksenler doğru adlandırılır.", 0.95), soru)
    assert sonuc.puan == 10
    assert sonuc.incele is True
    assert sonuc.puanlama_guveni <= 0.55


def test_ogrenci_listesi_ve_bulanik_eslesme(tmp_path: Path):
    yol = tmp_path / "liste.csv"
    yol.write_text(
        "Öğrenci No;Ad;Soyad;Sınıf;Şube\n122;Ece;Kara;9;A\n125;Ali;Yılmaz;9;A\n",
        encoding="utf-8",
    )
    kayitlar = ogrenci_listesi_oku(yol)
    eslesme = ogrenci_esle(
        {"numara": "122", "ad": "Eçe", "soyad": "Kara", "sinif": "9"},
        kayitlar,
    )
    assert eslesme is not None
    assert eslesme["ad"] == "Ece"
    assert eslesme["ogrenci_no"] == "122"


def test_altin_test_metrikleri():
    sonuc = altin_test_metrikleri(
        [
            {"tahmin_puan": 8, "beklenen_puan": 10},
            {"tahmin_puan": 6, "beklenen_puan": 5},
        ]
    )
    assert sonuc == {"ornek": 2, "puan_mae": 1.5, "iki_puan_icinde": 1.0}


def test_depo_denetim_ogrenme_roster_ve_gizlilik(tmp_path: Path):
    soru = _soru(
        SoruTipi.KISA_CEVAP,
        CevapAnahtari(rubrik=[RubrikKalemi("mitokondri", 10)]),
    )
    sinav = Sinav("T1", "Test", [soru])
    depo = Depo(tmp_path / "test.db")
    depo.sinav_kaydet(sinav)
    kagit = KagitSonucu(
        "T1",
        [1],
        kutular=[
            KutuSonucu(
                1,
                TanimaSonucu("mitokondri", 0.9, alternatifler=[{"metin": "mitokondri"}]),
                PuanSonucu(
                    10, 10, 0.9, ["doğru"], False,
                    risk=0.1, aciklama="Kavram doğru.", puanlama_guveni=0.9,
                ),
            )
        ],
        kalite_raporu=[{"sayfa": 1, "kritik": False}],
    )
    kagit_id = depo.kagit_kaydet(
        kagit,
        ogrenci_ad="Ece",
        ogrenci_no="122",
        saklama_gunu=1,
    )
    depo.kagit_kalitesini_guncelle(
        kagit_id,
        [{"sayfa": 1, "kritik": False, "parlama_orani": 0.01, "golge_sapmasi": 0.02}],
    )
    assert '"parlama_orani": 0.01' in depo.kagit(kagit_id)["kalite_json"]
    assert any(
        x["islem"] == "kalite_yenileme"
        for x in depo.denetim_kayitlari("kagit", str(kagit_id))
    )
    kutu = depo.kutular(kagit_id)[0]
    depo.kutu_guncelle(
        kutu["id"],
        son_puan=9,
        duzeltilmis_metin="mitokondri organeli",
        neden="Örnek istisna",
    )
    assert depo.duzeltme_ornekleri("T1")
    assert depo.denetim_kayitlari("kutu", str(kutu["id"]))

    assert depo.ogrenci_listesi_kaydet(
        "T1", [{"ogrenci_no": "122", "ad": "Ece", "soyad": "Kara"}]
    ) == 1
    assert depo.ogrenci_listesi("T1")[0]["soyad"] == "Kara"
