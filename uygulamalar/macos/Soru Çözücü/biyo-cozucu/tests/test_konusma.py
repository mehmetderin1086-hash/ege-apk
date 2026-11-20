"""Döküm → soru çıkarımı testleri: pencereleme ve model çıktısı politikaları.

Sınanan şey modelin ne dediği değil, çıktısının NASIL süzüldüğü: uydurulmuş
şık, yarım şık listesi, ezberden tamamlanmış soru ve dökümde karşılığı olmayan
metin işaretleniyor mu.
"""

from __future__ import annotations

import json

import pytest

from biyo_cozucu.alim.cikarim import Kaynak, Parca
from biyo_cozucu.alim.konusma import (
    ASGARI_DAYANAK,
    pencerele,
    sorulari_cikar,
)
from biyo_cozucu.motor.temel import MotorHatasi, SahteMotor

_DOKUM = (
    "Birinci soru: Mayoz bölünmede krossing over hangi evrede gerçekleşir? "
    "Şıklara bakalım: A profaz bir, B metafaz bir, C anafaz bir, D telofaz bir, "
    "E interfaz. Krossing over homolog kromozomlar yan yana geldiğinde, yani "
    "profaz bir evresinin tetrat aşamasında olur. Cevap A şıkkıdır."
)


def _kaynak(metin: str = _DOKUM, *, parca_boyu: int = 60) -> Kaynak:
    parcalar = []
    for bas in range(0, len(metin), parca_boyu):
        parcalar.append(
            Parca(
                metin=metin[bas : bas + parca_boyu],
                baslangic_sn=float(bas // parca_boyu * 5),
                bitis_sn=float((bas // parca_boyu + 1) * 5),
            )
        )
    return Kaynak(ad="YouTube: Test", tur="youtube", imza="a" * 16, parcalar=parcalar)


def _yanit(**alanlar) -> str:
    temel = {
        "soru": "Mayoz bölünmede krossing over hangi evrede gerçekleşir?",
        "cozum": "Krossing over homolog kromozomların tetrat oluşturduğu profaz bir evresinde olur.",
        "cevap": "A",
        "secenekler": {
            "A": "profaz bir", "B": "metafaz bir", "C": "anafaz bir",
            "D": "telofaz bir", "E": "interfaz",
        },
        "guven": 0.85,
    }
    temel.update(alanlar)
    return json.dumps({"sorular": [temel]}, ensure_ascii=False)


# --- pencereleme ---


def test_pencereler_ortusur_ve_parca_sinirinda_kesilir():
    kaynak = _kaynak()
    pencereler = pencerele(kaynak.parcalar, boyut=120, ortusme=60)
    assert len(pencereler) > 1
    for pencere in pencereler:
        # Kesim parça sınırında: hiçbir pencere yarım parça içermez.
        assert all(
            satir in kaynak.metin.replace("\n", "") or satir in kaynak.metin
            for satir in pencere.metin.split("\n")
        )
    # Ardışık pencereler ortak parça paylaşır (sınırdaki soru bölünmesin).
    ilk_satirlar = set(pencereler[0].metin.split("\n"))
    ikinci_satirlar = set(pencereler[1].metin.split("\n"))
    assert ilk_satirlar & ikinci_satirlar


def test_pencereleme_ilerler_sonsuz_donguye_girmez():
    # Örtüşme pencereden büyük verildiğinde de ilerleme durmamalı.
    kaynak = _kaynak(parca_boyu=30)
    pencereler = pencerele(kaynak.parcalar, boyut=40, ortusme=500)
    assert 0 < len(pencereler) <= len(kaynak.parcalar)


def test_bos_dokum_pencere_uretmez():
    assert pencerele([Parca(metin="  ", baslangic_sn=0, bitis_sn=1)]) == []


def test_tek_dev_parca_bolunur():
    """whisper-server dökümü TEK bölüt döndürdüğünde de pencereleme çalışmalı.

    Gerçek koşuda görüldü: 9 dakikalık video tek parça olarak geldi ve tüm
    döküm tek dev pencereye düşüp modelden hiç aday çıkmadı.
    """
    metin = " ".join(f"Cümle {i} burada yer alıyor." for i in range(400))
    pencereler = pencerele(
        [Parca(metin=metin, baslangic_sn=0.0, bitis_sn=600.0)], boyut=1800, ortusme=250
    )
    assert len(pencereler) > 3
    # Hiçbir pencere hedefi belirgin biçimde aşmamalı (örtüşme payı dahil).
    assert all(len(p.metin) <= 1800 + 250 + 50 for p in pencereler)
    # Zaman damgaları parça içinde orantılı dağıtılır, hepsi 0'da yığılmaz.
    assert pencereler[0].baslangic_sn == 0.0
    assert pencereler[-1].baslangic_sn > 0.0
    assert pencereler[-1].bitis_sn <= 600.0


def test_dev_parca_bolunmesi_metni_kaybetmez():
    metin = "".join(f"parça{i} " for i in range(500))
    pencereler = pencerele(
        [Parca(metin=metin, baslangic_sn=0.0, bitis_sn=10.0)], boyut=900, ortusme=100
    )
    birlesik = " ".join(p.metin for p in pencereler)
    for iz in ("parça0 ", "parça250 ", "parça499"):
        assert iz.strip() in birlesik


def test_pencere_konumu_dakika_saniye():
    kaynak = _kaynak()
    pencere = pencerele(kaynak.parcalar, boyut=10_000, ortusme=0)[0]
    assert pencere.konum() == "00:00"


# --- model politikaları ---


def test_model_cikarimi_temel_alanlari_doldurur():
    adaylar, yontem = sorulari_cikar(_kaynak(), SahteMotor(_yanit()), boyut=10_000)
    assert yontem == "model"
    (aday,) = adaylar
    assert aday.cevap == "A"
    assert aday.cevap_turu == "coktan_secmeli"
    assert aday.dayanak >= ASGARI_DAYANAK
    assert aday.baslangic_sn == 0.0
    assert not aday.uyarilar


def test_dokumde_olmayan_soru_dayanaktan_kirilir():
    yanit = _yanit(
        soru="Kalvin döngüsünde RuBisCO enzimi hangi tepkimeyi katalizler?",
        secenekler={},
        cevap="",
    )
    (aday,), _ = sorulari_cikar(_kaynak(), SahteMotor(yanit), boyut=10_000)
    assert "dokumde_dayanagi_zayif" in aday.uyarilar
    assert aday.guven <= 0.35
    assert aday.dayanak < ASGARI_DAYANAK


def test_siksiz_harf_cevap_nota_dusurulur():
    (aday,), _ = sorulari_cikar(
        _kaynak(), SahteMotor(_yanit(secenekler={})), boyut=10_000
    )
    assert aday.cevap == ""
    assert "sik_okunmadi:A" in aday.uyarilar
    assert aday.cevap_turu == "acik_uclu"
    assert aday.guven <= 0.4


def test_yarim_sik_listesi_dusurulur():
    (aday,), _ = sorulari_cikar(
        _kaynak(),
        SahteMotor(_yanit(secenekler={"A": "profaz bir", "B": "metafaz bir"})),
        boyut=10_000,
    )
    assert aday.secenekler == {}
    assert "eksik_secenek" in aday.uyarilar


def test_duz_cumle_soru_sayilmaz():
    """Ölçüldü: model anlatının düz bir cümlesini soru diye kaydediyor ve
    diğer filtrelerin hepsinden geçiyordu."""
    dokum = (
        "Soğanın yumrusundan yeni soğan oluşması vejetatif üremedir. "
        "Yavrular kalıtsal olarak aynıdır."
    )
    yanit = json.dumps({"sorular": [{
        "soru": "Soğanın yumrusundan yeni soğan oluşması.",
        "cozum": "Bu bir vejetatif üremedir; yavrular kalıtsal olarak aynıdır.",
        "secenekler": {}, "cevap": "", "guven": 0.9,
    }]}, ensure_ascii=False)
    (aday,), _ = sorulari_cikar(_kaynak(dokum), SahteMotor(yanit), boyut=10_000)
    assert "soru_cumlesi_degil" in aday.uyarilar
    assert aday.guven <= 0.35


@pytest.mark.parametrize(
    "soru",
    [
        "Mayoz bölünmede krossing over hangi evrede gerçekleşir?",
        "2n = 48 kromozomlu hücrede anafazda sentromer sayısı kaçtır?",
        "Aşağıdakilerden hangisi dolaşımın görevlerinden değildir.",
        "Bu olay için ne söylenebilir.",
    ],
)
def test_gercek_soru_kokleri_gecer(soru):
    """Yanlış pozitif kilidi: noktayla biten gerçek kökler de geçmeli."""
    from biyo_cozucu.alim.konusma import _soru_cumlesi_mi

    assert _soru_cumlesi_mi(soru)


def test_yinelenen_siklar_dusurulur():
    """10 saatlik koşuda ölçüldü: model şıkları aynı cümleyle dolduruyor ve
    hepsi dökümde geçtiği için dayanak 1,00, uyarı yok, güven 0,90 çıkıyordu."""
    dokum = (
        "Aşağıdakilerin hangisi dolaşım sisteminin görevlerinden değildir? "
        "Mikroorganizmalara karşı vücudu savunmak. Vücudu savunmasıdır."
    )
    yanit = json.dumps({"sorular": [{
        "soru": "Aşağıdakilerin hangisi dolaşım sisteminin görevlerinden değildir?",
        "cozum": "Mikroorganizmalara karşı vücudu savunmak bir dolaşım görevidir.",
        "cevap": "D",
        "secenekler": {
            "A": "Mikroorganizmalara karşı vücudu savunmak.",
            "B": "Vücudu savunmasıdır.",
            "C": "Vücudu savunmasıdır.",
            "D": "Vücudu savunmasıdır.",
        },
        "guven": 0.9,
    }]}, ensure_ascii=False)
    (aday,), _ = sorulari_cikar(_kaynak(dokum), SahteMotor(yanit), boyut=10_000)
    assert aday.secenekler == {}
    assert "bozuk_sik_kumesi" in aday.uyarilar
    assert aday.guven <= 0.35


def test_sorunun_metni_sik_olarak_geri_yazilirsa_dusurulur():
    dokum = (
        "Refleks yayında reseptör, duyu nöronu, ara nöron ve efektör görev yapar. "
        "A nöronu zarar gördüğünde refleks kaybolur."
    )
    soru = "Refleks yayında reseptör, duyu nöronu, ara nöron ve efektör görev yapar."
    yanit = json.dumps({"sorular": [{
        "soru": soru,
        "cozum": "A nöronu zarar gördüğünde refleks kaybolur, çünkü duyu iletimi kesilir.",
        "cevap": "B",
        "secenekler": {
            "A": soru,
            "B": "A nöronu zarar gördüğünde refleks kaybolur.",
            "C": "Beyne gelen uyartılarla tepki organı hareket ettirilemez.",
        },
        "guven": 0.9,
    }]}, ensure_ascii=False)
    (aday,), _ = sorulari_cikar(_kaynak(dokum), SahteMotor(yanit), boyut=10_000)
    assert aday.secenekler == {}
    assert "bozuk_sik_kumesi" in aday.uyarilar


def test_gecerli_sik_kumesi_bozuk_sayilmaz():
    """Yanlış pozitif kilidi."""
    (aday,), _ = sorulari_cikar(_kaynak(), SahteMotor(_yanit()), boyut=10_000)
    assert len(aday.secenekler) == 5
    assert "bozuk_sik_kumesi" not in aday.uyarilar


def test_sohbet_artigi_siklar_dusurulur():
    """Gerçek koşu bulgusu: anlatıcı şıkları okumayınca model çevredeki
    sohbet cümlelerini şık yapıyor ve hepsi dökümde geçtiği için dayanak
    puanı bunu yakalayamıyor."""
    dokum = (
        "Anafaz 1 ile anafaz 2 zaten aynı değil midir? Evet hocam. Değil mi? "
        "Geçici olarak iki katına çıkıyordu çünkü. Mayoz 1 ve mayoz 2 ile "
        "ilgili verilenlerden hangisi yanlıştır diye soruyor."
    )
    yanit = json.dumps(
        {
            "sorular": [
                {
                    "soru": "Mayoz 1 ve mayoz 2 ile ilgili verilenlerden hangisi yanlıştır?",
                    "cozum": "Mayoz 1'de tetrat oluşur, mayoz 2'de oluşmaz.",
                    "cevap": "A",
                    "secenekler": {
                        "A": "Mayoz 1'de tetrat oluşumu var mayoz 2'de yok.",
                        "B": "Crossing over mayoz 1'de gerçekleşir.",
                        "C": "Evet hocam böyle bir şey olmayabilir.",
                        "D": "Mayoz 1 öncesi replikasyon gerçekleşir.",
                    },
                    "guven": 0.9,
                }
            ]
        },
        ensure_ascii=False,
    )
    (aday,), _ = sorulari_cikar(_kaynak(dokum), SahteMotor(yanit), boyut=10_000)
    assert aday.secenekler == {}, "kirli şık kümesi tümden düşmeli"
    assert "sohbet_sikki" in aday.uyarilar
    assert aday.guven <= 0.35
    assert aday.cevap_turu == "acik_uclu"


def test_soru_isaretiyle_biten_sik_kirli_sayilir():
    yanit = _yanit(
        secenekler={"A": "profaz bir", "B": "Değil mi?", "C": "anafaz bir",
                    "D": "telofaz bir", "E": "interfaz"}
    )
    (aday,), _ = sorulari_cikar(_kaynak(), SahteMotor(yanit), boyut=10_000)
    assert aday.secenekler == {}
    assert "sohbet_sikki" in aday.uyarilar


def test_sohbet_sorusu_isaretlenir():
    dokum = "Anafaz 1 ile Anafaz 2 zaten aynı değil midir? Evet hocam, aynı değil."
    yanit = json.dumps(
        {"sorular": [{
            "soru": "Anafaz 1 ile Anafaz 2 zaten aynı değil midir?",
            "cozum": "Anafaz 1 ile anafaz 2 aynı değildir, farklı olaylardır.",
            "secenekler": {}, "cevap": "", "guven": 0.9,
        }]},
        ensure_ascii=False,
    )
    (aday,), _ = sorulari_cikar(_kaynak(dokum), SahteMotor(yanit), boyut=10_000)
    assert "sohbet_sorusu" in aday.uyarilar
    assert aday.guven <= 0.3


def test_dokumde_olmayan_cozum_isaretlenir():
    """Model, videonun anlatımı yerine kendi ders kitabı bilgisini yazıyor."""
    yanit = _yanit(
        cozum=(
            "Temel bilgi: Fotosentezde Kalvin döngüsü stromada yürür ve "
            "RuBisCO enzimi karbondioksiti sabitler."
        )
    )
    (aday,), _ = sorulari_cikar(_kaynak(), SahteMotor(yanit), boyut=10_000)
    assert "cozum_dokumde_yok" in aday.uyarilar
    assert aday.guven <= 0.4


def test_temiz_siklar_korunur():
    """Yanlış pozitif kilidi: gerçek şıklar düşürülmemeli."""
    (aday,), _ = sorulari_cikar(_kaynak(), SahteMotor(_yanit()), boyut=10_000)
    assert len(aday.secenekler) == 5
    assert "sohbet_sikki" not in aday.uyarilar
    assert "sohbet_sorusu" not in aday.uyarilar


def test_eksik_isaretli_soru_guveni_duser():
    (aday,), _ = sorulari_cikar(
        _kaynak(), SahteMotor(_yanit(eksik=True)), boyut=10_000
    )
    assert "soru_metni_eksik" in aday.uyarilar
    assert aday.guven <= 0.3


def test_kesik_json_kural_yoluna_dusurmez_ama_pencereyi_atlar():
    """Bozuk yanıt tek pencereyi düşürür; motor yine de 'model' sayılmaz."""
    adaylar, yontem = sorulari_cikar(
        _kaynak(), SahteMotor('{"sorular": [{"soru": "yarım'), boyut=10_000
    )
    # Model hiç aday üretemedi → kural yedeğine düşüldü.
    assert yontem == "kural"
    assert isinstance(adaylar, list)


def test_motor_hatasi_pencereyi_atlar():
    class _PatlayanMotor:
        ad = "patlayan"

        def uret(self, mesajlar, **kwargs):
            raise MotorHatasi("model düştü")

    adaylar, yontem = sorulari_cikar(_kaynak(), _PatlayanMotor(), boyut=10_000)
    assert yontem == "kural"
    assert isinstance(adaylar, list)


def test_motorsuz_cagri_kural_yolunu_kullanir():
    adaylar, yontem = sorulari_cikar(_kaynak(), None)
    assert yontem == "kural"
    assert any("krossing over" in a.soru.casefold() for a in adaylar)


def test_pencereler_arasi_yinelenen_soru_elenir():
    """Örtüşen pencereler aynı soruyu çıkarırsa kuyruğa tek kayıt girer."""
    kaynak = _kaynak(parca_boyu=40)
    motor = SahteMotor([_yanit(guven=0.6), _yanit(guven=0.9), _yanit(guven=0.5)])
    adaylar, _ = sorulari_cikar(kaynak, motor, boyut=60, ortusme=40)
    assert len(adaylar) == 1


def test_yinelenen_kopyalardan_yuksek_guvenli_kalir():
    """Sorunun tam geçtiği pencereden gelen (yüksek güvenli) kopya tutulur.

    Dayanak puanı kırpılmış pencerede düştüğü için güven de düşer; iki
    kopyadan yükseği, soruyu bütün gören penceredir.
    """
    from biyo_cozucu.alim.bolutleme import SoruAdayi
    from biyo_cozucu.alim.konusma import _yinelenenleri_ele

    dusuk = SoruAdayi(soru="Mayoz nerede olur?", guven=0.35)
    yuksek = SoruAdayi(soru="mayoz nerede olur", guven=0.9)
    baska = SoruAdayi(soru="Fotosentez nerede olur?", guven=0.4)
    kalanlar = _yinelenenleri_ele([dusuk, yuksek, baska])
    assert [k.guven for k in kalanlar] == [0.9, 0.4]


def test_bos_soru_listesi_kural_yoluna_duser():
    adaylar, yontem = sorulari_cikar(
        _kaynak(), SahteMotor(json.dumps({"sorular": []})), boyut=10_000
    )
    assert yontem == "kural"
    assert isinstance(adaylar, list)


def test_gecersiz_guven_degeri_varsayilana_duser():
    (aday,), _ = sorulari_cikar(
        _kaynak(), SahteMotor(_yanit(guven="çok yüksek")), boyut=10_000
    )
    assert aday.guven == 0.5


def test_istem_dokumu_blok_icinde_verir():
    motor = SahteMotor(_yanit())
    sorulari_cikar(_kaynak(), motor, boyut=10_000)
    kullanici = motor.cagrilar[0][-1]["content"]
    assert kullanici.startswith("[DÖKÜM")
    assert "krossing over" in kullanici.casefold()
