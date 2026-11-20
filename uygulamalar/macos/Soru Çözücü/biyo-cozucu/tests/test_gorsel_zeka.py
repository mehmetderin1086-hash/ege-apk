from __future__ import annotations

import io
import json

from PIL import Image, ImageDraw

from biyo_cozucu.gorsel_zeka import (
    GorselKaniti,
    gorseli_hazirla,
    kaniti_ayikla,
    siniflandir,
)
from biyo_cozucu.kalitim.soyagaci import (
    grafi_ayikla,
    x_cekinik_olasilik_coz,
)


def test_tam_metinli_soru_kirpimi_gereksiz_vlmye_gitmez():
    karar = siniflandir(
        "Mantarlarla ilgili aşağıdaki ifadelerden hangisi yanlıştır? Bu canlıların "
        "hücre duvarı, beslenmesi ve ekolojik rolleri birlikte değerlendirilecektir.",
        {"A": "bir", "B": "iki", "C": "üç"},
        gorsel_var=True,
    )
    assert karar.tur == "text_only"
    assert karar.gerekli is False


def test_kisa_kok_bes_tam_sikla_eksik_sayilmaz():
    karar = siniflandir(
        "Hangisi tüm canlıların ortak özelliği değildir?",
        {
            "A": "Hücresel bir organizasyona sahip olma",
            "B": "Enerjiyi metabolik tepkimelerde kullanma",
            "C": "Uyarılara uygun bir yanıt oluşturma",
            "D": "Kloroplast organeliyle fotosentez yapma",
            "E": "Kendine benzer yeni bireyler oluşturabilme",
        },
        gorsel_var=True,
    )
    assert karar.tur == "text_only"
    assert karar.gerekli is False


def test_soyagaci_ve_grafik_gorsel_yoluna_gider():
    soyagaci = siniflandir(
        "Aşağıdaki soyağacında ? bireyin hasta olma olasılığı kaçtır?",
        {"A": "1/2", "B": "1/4"},
        gorsel_var=True,
    )
    grafik = siniflandir(
        "Grafikte verilen büyüme eğrisine göre hangisi yanlıştır?",
        {"A": "bir", "B": "iki"},
        gorsel_var=True,
    )
    sekil = siniflandir(
        "Aşağıdaki şekle göre hangisi doğrudur?",
        {"A": "bir", "B": "iki"},
        gorsel_var=True,
    )
    assert (soyagaci.tur, soyagaci.gerekli) == ("pedigree", True)
    assert (grafik.tur, grafik.gerekli) == ("chart", True)
    assert (sekil.tur, sekil.gerekli) == ("diagram", True)

    ekli_grafik = siniflandir(
        "Trofik düzey grafiğine göre hangileri yapılamaz?",
        {"A": "Yalnız I", "E": "II ve III"},
        gorsel_var=True,
    )
    assert (ekli_grafik.tur, ekli_grafik.gerekli) == ("chart", True)


def test_gorsel_modu_zorla_ve_yok_kesin_karar_verir():
    zorla = siniflandir("Uzun ve eksiksiz bir soru metni " * 8, {"A": "x", "B": "y"}, gorsel_var=True, mod="zorla")
    yok = siniflandir("Grafikte hangisi doğrudur?", {"A": "x", "B": "y"}, gorsel_var=True, mod="yok")
    assert zorla.gerekli
    assert not yok.gerekli


def test_beyaz_bosluk_kirpilarak_icerik_korunur():
    goruntu = Image.new("RGB", (300, 1200), "white")
    ciz = ImageDraw.Draw(goruntu)
    ciz.rectangle((20, 20, 280, 220), outline="black", width=4)
    tampon = io.BytesIO()
    goruntu.save(tampon, format="PNG")

    hazir = Image.open(io.BytesIO(gorseli_hazirla(tampon.getvalue())))

    assert hazir.height < 350
    assert hazir.width >= 260


def test_gorsel_kaniti_kati_jsondan_okunur():
    ham = "```json\n" + json.dumps(
        {
            "tur": "chart",
            "ozet": "S tipi büyüme eğrisi",
            "veriler": ["K taşıma kapasitesi"],
            "iliskiler": ["III bölgesinde eğim azalıyor"],
            "okunamayanlar": [],
            "guven": 0.91,
        },
        ensure_ascii=False,
    ) + "\n```"
    kanit = kaniti_ayikla(ham, "uncertain")
    assert kanit == GorselKaniti(
        tur="chart",
        ozet="S tipi büyüme eğrisi",
        veriler=["K taşıma kapasitesi"],
        iliskiler=["III bölgesinde eğim azalıyor"],
        okunamayanlar=[],
        guven=0.91,
    )


def test_tam_soyagaci_grafi_xe_bagli_olasiligi_pythonla_cozer():
    ham = json.dumps(
        {
            "bireyler": [
                {"kimlik": "L1", "cinsiyet": "erkek", "durum": "hasta", "ebeveynler": []},
                {"kimlik": "L2", "cinsiyet": "disi", "durum": "saglikli", "ebeveynler": []},
                {"kimlik": "BABA", "cinsiyet": "erkek", "durum": "hasta", "ebeveynler": ["L1", "L2"]},
                {"kimlik": "R1", "cinsiyet": "erkek", "durum": "saglikli", "ebeveynler": []},
                {"kimlik": "R2", "cinsiyet": "disi", "durum": "saglikli", "ebeveynler": []},
                {"kimlik": "ANNE", "cinsiyet": "disi", "durum": "saglikli", "ebeveynler": ["R1", "R2"]},
                {"kimlik": "DAYI", "cinsiyet": "erkek", "durum": "hasta", "ebeveynler": ["R1", "R2"]},
                {"kimlik": "HEDEF", "cinsiyet": "bilinmiyor", "durum": "bilinmiyor", "ebeveynler": ["BABA", "ANNE"], "hedef": True},
            ]
        }
    )
    graf = grafi_ayikla(ham)
    sonuc = x_cekinik_olasilik_coz(
        "Soyağacında renk körlüğü X kromozomunda çekiniktir. Hedef bireyin renk körü olma olasılığı kaçtır?",
        {"A": "1", "B": "3/4", "C": "1/2", "D": "1/4", "E": "1/8"},
        graf,
    )
    assert sonuc is not None
    assert sonuc.cevap == "D"
    assert any("1/4" in adim for adim in sonuc.adimlar)


def test_soyagaci_grafi_modelin_kok_nesnesiz_listesini_de_kabul_eder():
    ham = json.dumps(
        [
            {
                "id": "HEDEF",
                "gender": "unknown",
                "status": "unknown",
                "parents": ["BABA", "ANNE"],
                "target": True,
            }
        ]
    )
    graf = grafi_ayikla(ham)
    assert len(graf) == 1
    assert graf[0].hedef is True
