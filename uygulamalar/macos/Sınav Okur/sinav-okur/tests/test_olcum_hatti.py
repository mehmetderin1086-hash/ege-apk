"""Ölçüm hattı: altın set üretimi, zincir hizalaması, hata bütçesi, kapı.

Bu katman kod olarak vardı ama hiç veriyle çalışmamıştı: altın set 0 örnek,
`olcumler/` dizini hiç oluşmamış, yanlış otomatik kabul oranını üreten kod
ölüydü. Buradaki testler hattın gerçekten aktığını sabitler.
"""

from __future__ import annotations

import numpy as np
import pytest

from sinav_okur.analiz import altin_test_metrikleri
from sinav_okur.depo import Depo
from sinav_okur.htr import YapayTaniyici
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
from sinav_okur.tanima_zinciri import kutuyu_oku
from sinav_okur.tezgah import (
    _veri_sagligi_uyarilari,
    altin_ornekleri_uret,
    tezgah_calistir,
)

KIMLIK = "OLCUM"


def _sinav() -> Sinav:
    return Sinav(
        kimlik=KIMLIK,
        baslik="Biyoloji",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.KISA_CEVAP,
                metin="Mitokondrinin görevi nedir?",
                puan=10.0,
                anahtar=CevapAnahtari(
                    rubrik=[RubrikKalemi("Mitokondri ATP üretir", 10.0)]
                ),
            )
        ],
    )


def _kirpinti(tmp_path, ad: str = "kutu.png") -> str:
    cv2 = pytest.importorskip("cv2")
    yol = tmp_path / ad
    cv2.imwrite(str(yol), np.full((60, 200, 3), 255, dtype=np.uint8))
    return str(yol)


def _kagit_kur(depo: Depo, tmp_path, *, onayli: bool, duzeltilmis: str | None):
    kutu = KutuSonucu(
        soru_no=1,
        tanima=TanimaSonucu(metin="mitokondri atp", guven=0.8),
        puan=PuanSonucu(6.0, 10.0, 0.8),
        kirp_yolu=_kirpinti(tmp_path),
    )
    kagit_id = depo.kagit_kaydet(
        KagitSonucu(sinav_kimlik=KIMLIK, islenen_sayfalar=[1], kutular=[kutu]),
        ogrenci_ad="Ayşe",
        yazar_grubu="A",
    )
    if duzeltilmis is not None:
        hedef = depo.kutular(kagit_id)[0]
        depo.kutu_guncelle(
            hedef["id"],
            duzeltilmis_metin=duzeltilmis,
            son_puan=10.0,
            neden="öğretmen düzeltti",
        )
    if onayli:
        depo.kagit_onayla(kagit_id)
    return kagit_id


def test_onaysiz_kagittaki_duzeltme_altin_sete_girer(tmp_path):
    """Ölçüldü: onaylandi=1 şartı yüzünden altın set üretilemiyordu.

    Gerçek etiket öğretmenin yazdığı metindir; onay ayrı bir iş akışı adımı.
    """
    depo = Depo(tmp_path / "t.db")
    depo.sinav_kaydet(_sinav())
    _kagit_kur(depo, tmp_path, onayli=False, duzeltilmis="Mitokondri ATP üretir")

    yalniz_onay = altin_ornekleri_uret(depo, kaynak="onay")
    assert yalniz_onay["eklenen"] == 0

    duzeltmeyle = altin_ornekleri_uret(depo, kaynak="duzeltme")
    assert duzeltmeyle["eklenen"] == 1
    assert duzeltmeyle["kaynak_sayimi"]["duzeltme"] == 1
    assert depo.altin_ornekler()[0]["beklenen_metin"] == "Mitokondri ATP üretir"


def test_ayni_kirpinti_iki_kez_eklenmez(tmp_path):
    depo = Depo(tmp_path / "t.db")
    depo.sinav_kaydet(_sinav())
    _kagit_kur(depo, tmp_path, onayli=True, duzeltilmis="Mitokondri ATP üretir")

    ilk = altin_ornekleri_uret(depo, kaynak="hepsi")
    ikinci = altin_ornekleri_uret(depo, kaynak="hepsi")

    assert ilk["eklenen"] == 1
    assert ikinci["eklenen"] == 0
    assert len(depo.altin_ornekler()) == 1


def test_bilinmeyen_kaynak_reddedilir(tmp_path):
    depo = Depo(tmp_path / "t.db")

    with pytest.raises(ValueError, match="Bilinmeyen kaynak"):
        altin_ornekleri_uret(depo, kaynak="uydurma")


def test_tezgah_uretim_zincirini_olcer(tmp_path):
    """Tezgâh çıplak kutu_taniy yerine üretimdeki zinciri ölçmeli."""
    depo = Depo(tmp_path / "t.db")
    depo.sinav_kaydet(_sinav())
    _kagit_kur(depo, tmp_path, onayli=True, duzeltilmis="Mitokondri ATP üretir")
    altin_ornekleri_uret(depo, kaynak="hepsi")

    sonuc = tezgah_calistir(
        depo,
        YapayTaniyici("Mitokondri ATP üretir"),
        zincir="ikisi",
        gorsel_yukleyici=lambda _y: np.full((60, 200, 3), 255, dtype=np.uint8),
    )

    satir = sonuc["satirlar"][0]
    assert satir["cer"] == pytest.approx(0.0)
    assert "cer_ham" in satir, "ikisi modunda ham kol da ölçülmeli"
    assert sonuc["metrikler"]["katman_kazanci"]["ornek"] == 1
    assert sonuc["zincir"] == "ikisi"


def test_tezgah_hata_butcesini_ikiye_boler(tmp_path):
    """Puan sapmasının ne kadarı anahtardan, ne kadarı okumadan?"""
    depo = Depo(tmp_path / "t.db")
    depo.sinav_kaydet(_sinav())
    _kagit_kur(depo, tmp_path, onayli=True, duzeltilmis="Mitokondri ATP üretir")
    altin_ornekleri_uret(depo, kaynak="hepsi")

    sonuc = tezgah_calistir(
        depo,
        YapayTaniyici("tamamen alakasız metin"),
        gorsel_yukleyici=lambda _y: np.full((60, 200, 3), 255, dtype=np.uint8),
    )

    satir = sonuc["satirlar"][0]
    # Anahtar doğru: beklenen metin tam puan alır → rubrik hatası yok.
    assert satir["rubrik_hatasi"] == pytest.approx(0.0)
    # Tüm sapma okumadan geliyor.
    assert satir["ocr_puan_hatasi"] > 0
    puan = sonuc["metrikler"]["puan"]
    assert puan["rubrik_mae"] == pytest.approx(0.0)
    assert puan["ocr_puan_mae"] > 0


def test_tezgah_yanlis_otomatik_kabulu_olcer(tmp_path):
    """analiz.py:419 ölü kodu canlanmalı: kapı altın sette simüle edilir."""
    depo = Depo(tmp_path / "t.db")
    depo.sinav_kaydet(_sinav())
    _kagit_kur(depo, tmp_path, onayli=True, duzeltilmis="Mitokondri ATP üretir")
    altin_ornekleri_uret(depo, kaynak="hepsi")

    sonuc = tezgah_calistir(
        depo,
        YapayTaniyici("Mitokondri ATP üretir"),
        gorsel_yukleyici=lambda _y: np.full((60, 200, 3), 255, dtype=np.uint8),
    )

    satir = sonuc["satirlar"][0]
    assert "otomatik_kabul" in satir
    assert "dogru" in satir
    metrikler = altin_test_metrikleri(sonuc["satirlar"])
    assert "otomatik_kapsama" in metrikler
    assert "yanlis_otomatik_kabul" in metrikler


def test_veri_sagligi_sisen_cer_uyarir():
    """Kırpıntı cevaptan fazlasını içeriyorsa CER şişer; sessizce geçmemeli.

    Ölçüldü: gerçek depoda 5/5 örnekte CER 8-12 çıktı çünkü kırpıntılar
    basılı soru metnini de kapsıyordu.
    """
    uyarilar = _veri_sagligi_uyarilari(
        [{"cer": 8.9}, {"cer": 0.2}, {"cer": 12.4}]
    )

    assert len(uyarilar) == 1
    assert "2/3" in uyarilar[0]


def test_veri_sagligi_normal_cerde_susar():
    assert _veri_sagligi_uyarilari([{"cer": 0.2}, {"cer": 0.4}]) == []


def test_zincir_ham_okumayi_ve_katmanlari_dondurur():
    """kutuyu_oku üretim zincirini tek imzada toplar."""
    soru = _sinav().soru(1)
    kirp = np.full((60, 200, 3), 255, dtype=np.uint8)

    sonuc = kutuyu_oku(YapayTaniyici("Mitokondri ATP üretir"), kirp, soru)

    assert sonuc.tanima.metin
    assert sonuc.ham_tanima.metin == "Mitokondri ATP üretir"
    assert isinstance(sonuc.sozluk_degisimleri, list)


def test_gerileme_kapisi_puan_mae_kotulesmesini_yakalar():
    """Metni aynı okuyup puanı bozan değişiklik sessizce geçmemeli."""
    from sinav_okur.tezgah import gerileme_karsilastir

    onceki = {
        "metrikler": {
            "ornek": 50,
            "ort_cer": 0.1,
            "tam_eslesme_orani": 0.8,
            "puan": {"puan_mae": 0.5},
        }
    }
    yeni = {
        "metrikler": {
            "ornek": 50,
            "ort_cer": 0.1,
            "tam_eslesme_orani": 0.8,
            "puan": {"puan_mae": 1.4},
        }
    }

    sonuc = gerileme_karsilastir(onceki, yeni)

    assert any("Puan MAE" in g for g in sonuc["gerilemeler"])
    assert sonuc["sert"] is True


def test_gerileme_kapisi_yanlis_kabul_artisini_yakalar():
    from sinav_okur.tezgah import gerileme_karsilastir

    taban = {
        "ornek": 40,
        "ort_cer": 0.1,
        "tam_eslesme_orani": 0.8,
        "puan": {"yanlis_otomatik_kabul_orani": 0.0},
    }
    yeni_metrik = dict(taban)
    yeni_metrik["puan"] = {"yanlis_otomatik_kabul_orani": 0.05}

    sonuc = gerileme_karsilastir(
        {"metrikler": taban}, {"metrikler": yeni_metrik}
    )

    assert any("Yanlış otomatik kabul" in g for g in sonuc["gerilemeler"])


def test_kucuk_altin_sette_gerileme_uyaridir():
    """5 örnekle CER istatistik değil; kapı kırmızı yanmamalı."""
    from sinav_okur.tezgah import gerileme_karsilastir

    sonuc = gerileme_karsilastir(
        {"metrikler": {"ornek": 5, "ort_cer": 0.1, "tam_eslesme_orani": 0.8}},
        {"metrikler": {"ornek": 5, "ort_cer": 0.5, "tam_eslesme_orani": 0.8}},
    )

    assert sonuc["gerilemeler"], "gerileme yine de raporlanmalı"
    assert sonuc["sert"] is False
    assert "istatistik değil" in sonuc["gerilemeler"][0]


def test_baglam_sizmasi_uydurulan_terimi_yakalar():
    """Bağlamlı motor, görüntüde olmayan bir ipucunu yazarsa ölçülmeli.

    Bağlam okumayı kolaylaştırır ama aynı zamanda cevabı fısıldayabilir;
    bağlamlı motoru açmadan önce bakılacak kapı budur.
    """
    from sinav_okur.tanima_zinciri import baglam_sizmasi

    ipuclari = ["mitokondri", "ribozom", "kloroplast"]

    temiz = baglam_sizmasi("mitokondri atp üretir", "mitokondri atp üretir", ipuclari)
    sizan = baglam_sizmasi(
        "mitokondri ribozom kloroplast", "mitokondri atp üretir", ipuclari
    )

    assert temiz == 0.0
    assert sizan > 0.0


def test_baglam_sizmasi_ipucusuz_sifir():
    from sinav_okur.tanima_zinciri import baglam_sizmasi

    assert baglam_sizmasi("herhangi bir metin", "beklenen", []) == 0.0


def test_baglam_sizmasi_beklenende_gecen_terimi_saymaz():
    """Cevapta gerçekten yazan bir terim sızma değildir."""
    from sinav_okur.tanima_zinciri import baglam_sizmasi

    assert (
        baglam_sizmasi("ribozom protein yapar", "ribozom protein yapar", ["ribozom"])
        == 0.0
    )
