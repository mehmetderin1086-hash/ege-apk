"""Alan sözlüğü ile OCR sonrası terim düzeltme."""
from __future__ import annotations

from sinav_okur.modeller import CevapAnahtari, Sinav, Soru, SoruTipi, TanimaSonucu
from sinav_okur.terim_sozlugu import (
    TerimSozlugu,
    baglam_terimleri,
    karisikliklari_ogren,
    sozluk_kur,
    sozlukle_duzelt,
)


def _sinav(dogru=("mitokondri",)) -> Sinav:
    return Sinav(
        kimlik="T-1",
        baslik="Test",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.BOSLUK_DOLDURMA,
                metin="Hücrenin enerji merkezi?",
                puan=10,
                anahtar=CevapAnahtari(dogru_cevaplar=list(dogru)),
            )
        ],
    )


def _sozluk(*terimler) -> TerimSozlugu:
    s = TerimSozlugu()
    for t in terimler:
        s.ekle(t, 1.0)
    return s


def test_sozluk_kaynaklari_birlesir():
    sozluk = sozluk_kur(
        _sinav(),
        soru_no=1,
        referans_pasajlari=["Kloroplast fotosentez organelidir."],
        duzeltme_ornekleri=[{"duzeltilmis_metin": "ribozom protein sentezler"}],
        taban_dahil=False,
    )
    assert "mitokondri" in sozluk.terimler
    assert "kloroplast" in sozluk.terimler
    assert "ribozom" in sozluk.terimler
    # Anahtar en güçlü kaynak
    assert sozluk.terimler["mitokondri"] > sozluk.terimler["kloroplast"]


def test_eki_koruyarak_govdeyi_duzeltir():
    sozluk = _sozluk("mitokondri")
    yeni, degisimler = sozlukle_duzelt(
        TanimaSonucu(metin="mitokondriye enerji", guven=0.8), sozluk
    )
    # Zaten doğru yazım: dokunulmaz
    assert not degisimler
    yeni, degisimler = sozlukle_duzelt(
        TanimaSonucu(metin="mitokondiye enerji", guven=0.8), sozluk
    )
    assert degisimler
    assert yeni.metin.startswith("mitokondriye")


def test_esik_altinda_duzeltilmez():
    sozluk = _sozluk("mitokondri")
    _, degisimler = sozlukle_duzelt(
        TanimaSonucu(metin="fotosentez", guven=0.8), sozluk
    )
    assert not degisimler


def test_iki_terim_arasinda_kalirsa_karar_verilmez():
    # "sitoz" iki terime de neredeyse eşit uzaklıkta → marj yetersiz
    sozluk = _sozluk("mitoz", "mayoz")
    _, degisimler = sozlukle_duzelt(
        TanimaSonucu(metin="miyoz bölünme", guven=0.8), sozluk
    )
    assert not degisimler


def test_asiri_degisim_orani_tum_duzeltmeyi_iptal_eder():
    sozluk = _sozluk("mitokondri", "kloroplast", "ribozom")
    ham = "mitokondi kloroplas ribozomm"
    yeni, degisimler = sozlukle_duzelt(
        TanimaSonucu(metin=ham, guven=0.8), sozluk
    )
    # 3/3 sözcük değişecekti → %35 sınırını aşar, hiç dokunulmaz
    assert not degisimler
    assert yeni.metin == ham


def test_rakam_iceren_ve_kisa_sozcuk_korunur():
    sozluk = _sozluk("mitokondri")
    ham = "mit 12mitokondi"
    _, degisimler = sozlukle_duzelt(TanimaSonucu(metin=ham, guven=0.8), sozluk)
    assert not degisimler


def test_ham_metin_alternatiflerde_kalir():
    sozluk = _sozluk("mitokondri")
    yeni, _ = sozlukle_duzelt(
        TanimaSonucu(metin="mitokondi hücre organelidir", guven=0.8), sozluk
    )
    assert any(a.get("kaynak") == "ham_ocr" for a in yeni.alternatifler)
    assert any("mitokondi" in a.get("metin", "") for a in yeni.alternatifler)


def test_kapi_kanit_alanlari_degismez():
    sozluk = _sozluk("mitokondri")
    ham = TanimaSonucu(
        metin="mitokondi hücre organelidir",
        guven=0.8,
        uzlasma_guveni=0.55,
        bagimsiz_motor_sayisi=2,
        karar_marji=0.07,
    )
    yeni, degisimler = sozlukle_duzelt(ham, sozluk)
    assert degisimler
    assert yeni.uzlasma_guveni == ham.uzlasma_guveni
    assert yeni.bagimsiz_motor_sayisi == ham.bagimsiz_motor_sayisi
    assert yeni.karar_marji == ham.karar_marji
    assert yeni.guven == ham.guven


def test_karisikliklar_duzeltmelerden_ogrenilir():
    ornekler = [
        {"ocr_metni": "rnitokondri", "duzeltilmis_metin": "mitokondri"},
        {"ocr_metni": "rnayoz", "duzeltilmis_metin": "mayoz"},
        {"ocr_metni": "rnitoz", "duzeltilmis_metin": "mitoz"},
    ]
    karisikliklar = karisikliklari_ogren(ornekler, asgari_destek=3)
    assert karisikliklar.get("rn") == "m"


def test_bos_sozlukle_metin_degismez():
    ham = TanimaSonucu(metin="mitokondi", guven=0.8)
    yeni, degisimler = sozlukle_duzelt(ham, TerimSozlugu())
    assert yeni is ham
    assert not degisimler


def test_baglam_terimleri_agirliga_gore_siralanir():
    sozluk = sozluk_kur(
        _sinav(),
        soru_no=1,
        referans_pasajlari=["kloroplast fotosentez organelidir"],
        taban_dahil=False,
    )
    terimler = baglam_terimleri(sozluk, azami=1)
    assert terimler == ["mitokondri"]


def test_sozluk_diske_yuvarlak_gidis(tmp_path):
    sozluk = _sozluk("mitokondri", "kloroplast")
    sozluk.karisikliklar = {"rn": "m"}
    yol = sozluk.kaydet(tmp_path / "sozluk.json")
    geri = TerimSozlugu.yukle(yol)
    assert geri.terimler == sozluk.terimler
    assert geri.karisikliklar == {"rn": "m"}


# --- Code-review regresyonları -------------------------------------------


import pytest  # noqa: E402


@pytest.mark.parametrize(
    "ek", ["larda", "lerde", "lardan", "lerden", "ların", "lerin", "larla", "lerle"]
)
@pytest.mark.parametrize(
    "terim", ["kloroplast", "ribozom", "enzim", "organel", "mitokondri"]
)
def test_cekim_ekli_dogru_sozcuk_bozulmaz(terim, ek):
    """Türkçe çekim zinciri 6 karaktere çıkar; gövde ekin ortasından kesilmemeli."""
    sozluk = _sozluk("kloroplast", "ribozom", "enzim", "organel", "mitokondri")
    # "mitokondri" + "lerde" gibi birleşimlerde araya kaynaştırma girmez;
    # doğrudan birleştirmek gerçek kâğıtlardaki yazımı temsil eder.
    kelime = terim + ek
    _yeni, degisimler = sozlukle_duzelt(
        TanimaSonucu(metin=kelime, guven=0.8), sozluk
    )
    assert degisimler == [], f"{kelime} bozuldu"


def test_zit_anlamli_turev_terim_anahtara_cekilmez():
    """'deplazmoliz' sözlükteki 'plazmoliz'e çekilirse öğrenci haksız puan alır."""
    sozluk = _sozluk("plazmoliz")
    _yeni, degisimler = sozlukle_duzelt(
        TanimaSonucu(metin="deplazmoliz", guven=0.8), sozluk
    )
    assert degisimler == []


def test_duzeltme_ornekleri_soru_bazinda_suzulur():
    ornekler = [
        {"soru_no": 2, "duzeltilmis_metin": "translasyon ribozomda olur"},
    ]
    sozluk = sozluk_kur(
        _sinav(),
        soru_no=1,
        duzeltme_ornekleri=ornekler,
        taban_dahil=False,
    )
    assert "translasyon" not in sozluk.terimler


def test_ogrenilen_karisiklik_duzeltmede_kullanilir():
    sozluk = _sozluk("mitokondri")
    sozluk.karisikliklar = {"rn": "m"}
    yeni, degisimler = sozlukle_duzelt(
        TanimaSonucu(metin="rnitokondri", guven=0.8), sozluk
    )
    assert degisimler
    assert yeni.metin == "mitokondri"
