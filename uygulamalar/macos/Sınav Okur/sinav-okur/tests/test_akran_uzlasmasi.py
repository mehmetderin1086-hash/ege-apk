"""Akran uzlaşması: benzer cevaba benzer puan; puan asla otomatik değişmez."""
from __future__ import annotations

from sinav_okur.modeller import PuanSonucu, Sinav, TanimaSonucu
from sinav_okur.puanlama.akran import (
    akran_kumeleri,
    akran_uzlasmasini_degerlendir,
)
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu

METIN = "mitokondri hücrenin enerji üreten organelidir"


def _kagit(depo, sinav, soru, metin, puan):
    return depo.kagit_kaydet(
        KagitSonucu(
            sinav_kimlik=sinav.kimlik,
            islenen_sayfalar=[1],
            kutular=[
                KutuSonucu(
                    soru_no=soru.no,
                    tanima=TanimaSonucu(metin=metin, guven=0.9),
                    puan=PuanSonucu(
                        puan=puan, max_puan=soru.puan, guven=0.9
                    ),
                )
            ],
        ),
        ogrenci_ad="Öğrenci",
    )


def _kurulum(depo, ornek_sinav: Sinav):
    depo.sinav_kaydet(ornek_sinav)
    return ornek_sinav.sorular[0]


def test_ayni_metinli_kutular_tek_kumede(depo, ornek_sinav):
    soru = _kurulum(depo, ornek_sinav)
    _kagit(depo, ornek_sinav, soru, METIN, soru.puan)
    _kagit(depo, ornek_sinav, soru, METIN, 0.0)
    cevaplar = [
        c for c in depo.sinav_cevaplari(ornek_sinav.kimlik)
        if int(c["soru_no"]) == soru.no
    ]
    kumeler = akran_kumeleri(cevaplar)
    assert len(kumeler) == 1
    assert len(kumeler[0]) == 2


def test_capa_yoksa_hicbir_kutu_isaretlenmez(depo, ornek_sinav):
    soru = _kurulum(depo, ornek_sinav)
    _kagit(depo, ornek_sinav, soru, METIN, soru.puan)
    _kagit(depo, ornek_sinav, soru, METIN, 0.0)
    sonuc = akran_uzlasmasini_degerlendir(depo, ornek_sinav)
    assert sonuc["isaretlenen"] == []


def test_capadan_sapan_kutu_isaretlenir(depo, ornek_sinav):
    soru = _kurulum(depo, ornek_sinav)
    # Çapa: öğretmen elle tam puan verdi (otomatik 0 idi).
    capa_kagit = _kagit(depo, ornek_sinav, soru, METIN, 0.0)
    capa_kutu = depo.kutular(capa_kagit)[0]
    depo.kutu_guncelle(kutu_id=capa_kutu["id"], son_puan=soru.puan)
    # Aynı cevabı yazan ikinci kâğıt programca 0 almış, öğretmen dokunmamış.
    _kagit(depo, ornek_sinav, soru, METIN, 0.0)
    sonuc = akran_uzlasmasini_degerlendir(depo, ornek_sinav)
    assert len(sonuc["isaretlenen"]) == 1
    assert sonuc["isaretlenen"][0]["onerilen_puan"] == soru.puan


def test_puan_hicbir_kosulda_degismez(depo, ornek_sinav):
    soru = _kurulum(depo, ornek_sinav)
    capa_kagit = _kagit(depo, ornek_sinav, soru, METIN, 0.0)
    ikinci_kagit = _kagit(depo, ornek_sinav, soru, METIN, 0.0)
    capa_kutu = depo.kutular(capa_kagit)[0]
    depo.kutu_guncelle(kutu_id=capa_kutu["id"], son_puan=soru.puan)
    hedef = depo.kutular(ikinci_kagit)[0]
    onceki_puan = hedef["son_puan"]
    akran_uzlasmasini_degerlendir(depo, ornek_sinav, uygula=True)
    guncel = depo.kutu(hedef["id"])
    assert guncel["son_puan"] == onceki_puan
    assert guncel["incele"] == 1


def test_capalar_tutarsizsa_oneri_uretilmez(depo, ornek_sinav):
    soru = _kurulum(depo, ornek_sinav)
    # İki çapa birbirine çok uzak puan almış → MAD yüksek. İkisinde de
    # öğretmen otomatik puandan saptığı için gerçekten çapa sayılırlar.
    for puan in (soru.puan * 0.2, soru.puan):
        kagit = _kagit(depo, ornek_sinav, soru, METIN, 0.0)
        kutu = depo.kutular(kagit)[0]
        depo.kutu_guncelle(kutu_id=kutu["id"], son_puan=puan)
    _kagit(depo, ornek_sinav, soru, METIN, 0.0)
    sonuc = akran_uzlasmasini_degerlendir(depo, ornek_sinav)
    assert sonuc["isaretlenen"] == []


def test_tek_cevapli_soruda_guvenli_geri_dusus(depo, ornek_sinav):
    soru = _kurulum(depo, ornek_sinav)
    _kagit(depo, ornek_sinav, soru, METIN, soru.puan)
    sonuc = akran_uzlasmasini_degerlendir(depo, ornek_sinav)
    assert sonuc["isaretlenen"] == []
    assert sonuc["kume_sayisi"] == 0


def test_sahte_gomlemciyle_calisir(depo, ornek_sinav, SahteGomlemci=None):
    from tests.conftest import SahteGomlemci as Gomlemci

    soru = _kurulum(depo, ornek_sinav)
    _kagit(depo, ornek_sinav, soru, METIN, soru.puan)
    _kagit(depo, ornek_sinav, soru, METIN, 0.0)
    sonuc = akran_uzlasmasini_degerlendir(
        depo, ornek_sinav, gomlemci=Gomlemci()
    )
    assert isinstance(sonuc["isaretlenen"], list)


def test_uygula_denetim_kaydi_yazar(depo, ornek_sinav):
    soru = _kurulum(depo, ornek_sinav)
    capa_kagit = _kagit(depo, ornek_sinav, soru, METIN, 0.0)
    ikinci_kagit = _kagit(depo, ornek_sinav, soru, METIN, 0.0)
    capa_kutu = depo.kutular(capa_kagit)[0]
    depo.kutu_guncelle(kutu_id=capa_kutu["id"], son_puan=soru.puan)
    akran_uzlasmasini_degerlendir(depo, ornek_sinav, uygula=True)
    hedef = depo.kutular(ikinci_kagit)[0]
    kayitlar = depo.denetim_kayitlari("kutu", hedef["id"])
    assert any("Akran uzlaşması" in (k["neden"] or "") for k in kayitlar)
