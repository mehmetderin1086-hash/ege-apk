"""Güvenlik kapısının serbest akışa gölge/aktif bağlanması ve telemetri."""
from pathlib import Path

import pytest

pytest.importorskip("cv2")
import cv2

from sinav_okur.htr import YapayTaniyici
from sinav_okur.serbest import serbest_kagit_isle


def _dolu_kagit(ana_yolu, tmp_path, kutu_gecmisi):
    ana = cv2.imread(str(ana_yolu), cv2.IMREAD_COLOR)
    for _no, y in kutu_gecmisi.items():
        cv2.putText(
            ana, "mitokondri", (120, y + 100),
            cv2.FONT_HERSHEY_SCRIPT_SIMPLEX, 1.1, (80, 20, 10), 2,
        )
    yol = tmp_path / "ogrenci.png"
    cv2.imwrite(str(yol), ana)
    return yol


def _isle(serbest_ortam, tmp_path, mod, guven=0.95):
    from tests.conftest import basili_sayfa

    db, sinav, sablon, ana_yolu = serbest_ortam
    _, kutu_gecmisi = basili_sayfa(sinav.sorular)
    ogrenci = _dolu_kagit(ana_yolu, tmp_path, kutu_gecmisi)
    sonuc = serbest_kagit_isle(
        ogrenci, sinav, sablon,
        YapayTaniyici("mitokondri", guven),
        kirp_dizini=tmp_path / "kirp",
        guvenlik_kapisi_modu=mod,
    )
    return db, sinav, sonuc


def test_golge_modda_her_kutu_incelemeye_duser(serbest_ortam, tmp_path):
    """Gölge modun temel güvencesi: davranış değişmez."""
    _, _, sonuc = _isle(serbest_ortam, tmp_path, "golge")
    assert sonuc.kutular
    for kutu in sonuc.kutular:
        assert kutu.puan.incele is True
        assert kutu.puan.otomatik_kabul is False
        # Kapı kararı yine de telemetriye yazılır
        kapi = [k for k in kutu.puan.kararlar if k.get("tur") == "guvenlik_kapisi"]
        assert kapi and kapi[0]["mod"] == "golge"


def test_kapali_modda_kapi_devrede_degil(serbest_ortam, tmp_path):
    _, _, sonuc = _isle(serbest_ortam, tmp_path, "kapali")
    for kutu in sonuc.kutular:
        assert kutu.puan.incele is True
        assert kutu.puan.otomatik_kabul is False
        # Kapalı modda kapı hiç çağrılmaz → telemetri kaydı da olmaz
        assert not any(
            k.get("tur") == "guvenlik_kapisi" for k in kutu.puan.kararlar
        )


def test_golge_mod_kapali_modla_ayni_risk_ve_incele(serbest_ortam, tmp_path):
    """Gölge mod davranış-nötr olmalı: risk ve incele kapalı modla birebir aynı."""
    _, _, golge = _isle(serbest_ortam, tmp_path, "golge")
    _, _, kapali = _isle(serbest_ortam, tmp_path, "kapali")
    golge_kutu = {k.soru_no: k for k in golge.kutular}
    for kk in kapali.kutular:
        gk = golge_kutu[kk.soru_no]
        assert gk.puan.incele == kk.puan.incele
        assert abs(gk.puan.risk - kk.puan.risk) < 1e-9
        assert gk.puan.otomatik_kabul == kk.puan.otomatik_kabul is False


def test_aktif_modda_tam_kanit_otomatik_kabul(serbest_ortam, tmp_path):
    """YapayTaniyici tam kanıt üretmez (tek motor); tam kanıtlı kutu kurgulanır."""
    from sinav_okur.modeller import PuanSonucu, Soru, SoruTipi, TanimaSonucu
    from sinav_okur.guvenlik_kapisi import (
        kapi_karari_sozlugu,
        otomatik_karari_degerlendir,
    )

    soru = Soru(no=1, tip=SoruTipi.BOSLUK_DOLDURMA, metin="x", puan=10,
                anahtar=__import__("sinav_okur.modeller", fromlist=["CevapAnahtari"])
                .CevapAnahtari(dogru_cevaplar=["mitokondri"]))
    tanima = TanimaSonucu(
        metin="mitokondri", guven=0.95, uzlasma_guveni=0.95,
        bagimsiz_motor_sayisi=2, karar_marji=0.5, girdi_kalitesi=0.9,
    )
    puan = PuanSonucu(10, 10, 0.95, puanlama_guveni=0.95)
    sonuc = otomatik_karari_degerlendir(
        tanima, puan, soru, hizalama_guveni=1.0
    )
    assert sonuc.otomatik_kabul is True
    assert sonuc.incele is False
    # Kritik sayfa vetosu
    puan2 = PuanSonucu(10, 10, 0.95, puanlama_guveni=0.95)
    sonuc2 = otomatik_karari_degerlendir(
        tanima, puan2, soru, sayfa_kritik=True
    )
    assert sonuc2.incele is True


def test_hizalama_dusukse_veto(serbest_ortam, tmp_path):
    from sinav_okur.modeller import PuanSonucu, Soru, SoruTipi, TanimaSonucu
    from sinav_okur.modeller import CevapAnahtari
    from sinav_okur.guvenlik_kapisi import otomatik_karari_degerlendir

    soru = Soru(no=1, tip=SoruTipi.BOSLUK_DOLDURMA, metin="x", puan=10,
                anahtar=CevapAnahtari(dogru_cevaplar=["mitokondri"]))
    tanima = TanimaSonucu(
        metin="mitokondri", guven=0.95, uzlasma_guveni=0.95,
        bagimsiz_motor_sayisi=2, karar_marji=0.5, girdi_kalitesi=0.9,
    )
    puan = PuanSonucu(10, 10, 0.95, puanlama_guveni=0.95)
    sonuc = otomatik_karari_degerlendir(
        tanima, puan, soru, hizalama_guveni=0.5
    )
    assert sonuc.otomatik_kabul is False
    assert any("hizalama" in n.lower() for n in sonuc.kabul_nedenleri)


def test_telemetri_denetim_kaydina_yazilir(serbest_ortam, tmp_path):
    db, sinav, sonuc = _isle(serbest_ortam, tmp_path, "golge")
    kagit_id = db.kagit_kaydet(sonuc, ogrenci_ad="Ayşe")
    kayitlar = db.denetim_kayitlari(varlik_turu="kagit")
    kapi = [k for k in kayitlar if k["islem"] == "guvenlik_kapisi"]
    assert kapi
    ozet = db.guvenlik_kapisi_ozeti(sinav.kimlik)
    assert ozet["kapili_kutu"] >= 1
    assert ozet["golge_yanlis_kabul"] == 0
