"""Serbest akış uçtan uca entegrasyon testi.

Örnek sınav tanımından basılı ana sayfa + "el yazısı" öğrenci kâğıdı üretilir,
serbest_kagit_isle ile hizalama → kutu eşleştirme → puanlama → depo → Excel
zinciri işletilir. OCR'ı deterministik kılmak için YapayTaniyici kullanılır;
böylece test motor kurulumundan bağımsız çalışır ve gerçek çalışan katman
görüntü zinciri (hizalama, el yazısı farkı, kırpma, boş/dolu) + puanlama +
depo + rapor olur.
"""
from pathlib import Path

import pytest

pytest.importorskip("cv2")
pytest.importorskip("openpyxl")
import cv2

from sinav_okur.htr import YapayTaniyici
from sinav_okur.rapor import excel_dokum
from sinav_okur.serbest import serbest_kagit_isle


def _ogrenci_kagidi(ana_yolu, tmp_path, kutu_gecmisi=None, doldurulacak=None,
                    ad="ogrenci"):
    """Ana sayfayı kopyalayıp seçili kutulara 'el yazısı' cevap çizerek kâğıt üretir.

    ``doldurulacak`` None ise tüm kutular doldurulur; bir soru no kümesi
    verilirse yalnız o kutular doldurulur (diğerleri boş bırakılır).
    """
    ana = cv2.imread(str(ana_yolu), cv2.IMREAD_COLOR)
    for no, y in (kutu_gecmisi or {}).items():
        if doldurulacak is None or no in doldurulacak:
            cv2.putText(
                ana, "mitokondri", (120, y + 100),
                cv2.FONT_HERSHEY_SCRIPT_SIMPLEX, 1.1, (80, 20, 10), 2,
            )
    yol = tmp_path / f"{ad}.png"
    cv2.imwrite(str(yol), ana)
    return yol


def test_tam_zincir_puanla_ve_excel(serbest_ortam, tmp_path):
    from tests.conftest import basili_sayfa

    db, sinav, sablon, ana_yolu = serbest_ortam
    _, kutu_gecmisi = basili_sayfa(sinav.sorular)
    ogrenci = _ogrenci_kagidi(ana_yolu, tmp_path, kutu_gecmisi)

    sonuc = serbest_kagit_isle(
        ogrenci, sinav, sablon,
        YapayTaniyici("mitokondri", 0.95),
        kirp_dizini=tmp_path / "kirp",
    )
    # Her soru için bir kutu, doğru soruya eşleşmiş
    assert len(sonuc.kutular) == len(sinav.sorular)
    assert {k.soru_no for k in sonuc.kutular} == {s.no for s in sinav.sorular}

    kagit_id = db.kagit_kaydet(sonuc, ogrenci_ad="Ayşe")
    toplam, maxp = db.kagit_toplam(kagit_id)
    assert maxp == sinav.toplam_puan

    yol = excel_dokum(db, sinav.kimlik, tmp_path / "rapor.xlsx")
    assert Path(yol).is_file()
    from openpyxl import load_workbook

    ws = load_workbook(yol)["Notlar"]
    assert [h.value for h in ws[2]][0] == "Ayşe"


def test_bos_kutu_taniyiciya_gitmez_sifir_puan(serbest_ortam, tmp_path):
    from tests.conftest import basili_sayfa

    db, sinav, sablon, ana_yolu = serbest_ortam
    _, kutu_gecmisi = basili_sayfa(sinav.sorular)
    ilk = sinav.sorular[0].no
    # Yalnız ilk kutuyu doldur → kâğıt gerçek öğrenci kâğıdı sayılır
    # (cevaplı-şablon modu değil); diğer kutular boş kalır.
    ogrenci = _ogrenci_kagidi(
        ana_yolu, tmp_path, kutu_gecmisi, doldurulacak={ilk}
    )
    sonuc = serbest_kagit_isle(
        ogrenci, sinav, sablon,
        YapayTaniyici("mitokondri", 0.95),
        kirp_dizini=tmp_path / "kirp",
    )
    bos_kutular = [k for k in sonuc.kutular if k.soru_no != ilk]
    # Boş kutular tanıyıcıya girmez → metin boş, puan 0, inceleme gerektirmez
    assert bos_kutular
    assert all(not k.tanima.metin.strip() for k in bos_kutular)
    assert all(k.puan.puan == 0 for k in bos_kutular)


def test_dusuk_guven_incelemeye_duser(serbest_ortam, tmp_path):
    from tests.conftest import basili_sayfa

    db, sinav, sablon, ana_yolu = serbest_ortam
    _, kutu_gecmisi = basili_sayfa(sinav.sorular)
    ogrenci = _ogrenci_kagidi(ana_yolu, tmp_path, kutu_gecmisi)

    sonuc = serbest_kagit_isle(
        ogrenci, sinav, sablon,
        YapayTaniyici("mitokondri", 0.3),  # düşük güven
        kirp_dizini=tmp_path / "kirp",
    )
    dolu = [k for k in sonuc.kutular if k.tanima.metin.strip()]
    assert dolu and all(k.puan.incele for k in dolu)


def test_sayfa_uyusmazligi_uyari_verir(serbest_ortam, tmp_path):
    from tests.conftest import basili_sayfa

    db, sinav, sablon, ana_yolu = serbest_ortam
    _, kutu_gecmisi = basili_sayfa(sinav.sorular)
    # İki sayfalık kâğıt yükle ama şablon tek sayfa → uyuşmazlık
    ogrenci = _ogrenci_kagidi(ana_yolu, tmp_path, kutu_gecmisi)
    ikinci = tmp_path / "ogrenci2.png"
    cv2.imwrite(str(ikinci), cv2.imread(str(ogrenci)))

    sonuc = serbest_kagit_isle(
        [ogrenci, ikinci], sinav, sablon,
        YapayTaniyici("mitokondri", 0.95),
        kirp_dizini=tmp_path / "kirp",
    )
    assert any("Sayfa sayısı farklı" in u for u in sonuc.uyarilar)
