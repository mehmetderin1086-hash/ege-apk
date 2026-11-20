"""Motor karşılaştırma: hangi OCR motoru KENDİ kâğıtlarınızda daha iyi?

Sıralama genel bir gerçek değil, yazıya ve kâğıda bağlı. Bu yüzden araç
kıyaslama tablosu yerine kullanıcının kendi altın setini ölçer.
"""

from __future__ import annotations

import numpy as np
import pytest

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
from sinav_okur.motor_karsilastirma import motorlari_karsilastir
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu
from sinav_okur.tezgah import altin_ornekleri_uret

KIMLIK = "KARSILASTIR"


def _kur(tmp_path) -> Depo:
    cv2 = pytest.importorskip("cv2")
    depo = Depo(tmp_path / "t.db")
    depo.sinav_kaydet(
        Sinav(
            kimlik=KIMLIK,
            baslik="Biyoloji",
            sorular=[
                Soru(
                    no=1,
                    tip=SoruTipi.KISA_CEVAP,
                    metin="Mitokondrinin görevi nedir?",
                    puan=10.0,
                    anahtar=CevapAnahtari(
                        rubrik=[RubrikKalemi("ATP üretir", 10.0)]
                    ),
                )
            ],
        )
    )
    kirp = tmp_path / "kutu.png"
    cv2.imwrite(str(kirp), np.full((60, 200, 3), 255, dtype=np.uint8))
    kagit_id = depo.kagit_kaydet(
        KagitSonucu(
            sinav_kimlik=KIMLIK,
            islenen_sayfalar=[1],
            kutular=[
                KutuSonucu(
                    soru_no=1,
                    tanima=TanimaSonucu(metin="atp", guven=0.8),
                    puan=PuanSonucu(5.0, 10.0, 0.8),
                    kirp_yolu=str(kirp),
                )
            ],
        ),
        ogrenci_ad="Ayşe",
    )
    kutu = depo.kutular(kagit_id)[0]
    depo.kutu_guncelle(
        kutu["id"], duzeltilmis_metin="ATP üretir", son_puan=10.0, neden="öğretmen"
    )
    altin_ornekleri_uret(depo, kaynak="hepsi")
    return depo


def test_altin_set_yoksa_bos_rapor(tmp_path):
    sonuc = motorlari_karsilastir(Depo(tmp_path / "bos.db"))

    assert sonuc["ornek"] == 0
    assert sonuc["motorlar"] == []


def test_kurulu_olmayan_motor_olcumu_durdurmaz(tmp_path):
    """Bir motor yoksa 'hata' ile raporlanır, diğerleri ölçülmeye devam eder."""
    depo = _kur(tmp_path)

    sonuc = motorlari_karsilastir(depo, motorlar=["yapay", "hic-olmayan-motor"])

    adlar = {s["motor"] for s in sonuc["motorlar"]}
    assert adlar == {"yapay", "hic-olmayan-motor"}
    hatali = next(s for s in sonuc["motorlar"] if s["motor"] == "hic-olmayan-motor")
    assert "hata" in hatali


def test_motorlar_cer_sirasina_gore_gelir(tmp_path):
    depo = _kur(tmp_path)

    sonuc = motorlari_karsilastir(depo, motorlar=["yapay"])

    olculen = [s for s in sonuc["motorlar"] if "cer" in s]
    assert olculen, "en az bir motor ölçülmeli"
    assert olculen == sorted(olculen, key=lambda s: s["cer"])
    assert sonuc["en_iyi"] == olculen[0]["motor"]


def test_kucuk_sette_istatistik_uyarisi_verilir(tmp_path):
    """Tek örnekle motor seçmek yanlış güven üretir."""
    depo = _kur(tmp_path)

    sonuc = motorlari_karsilastir(depo, motorlar=["yapay"])

    assert any("istatistik değildir" in u for u in sonuc["uyarilar"])


def test_azami_ornek_siniri_uygulanir(tmp_path):
    depo = _kur(tmp_path)

    sonuc = motorlari_karsilastir(depo, motorlar=["yapay"], azami_ornek=1)

    assert sonuc["ornek"] == 1
