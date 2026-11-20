from __future__ import annotations

import json

import pytest

from biyo_cozucu.istemler import (
    cozum_mesajlari,
    cozumu_adimlara_bol,
    ornek_yaniti,
    ornekten_diyalog,
    oz_kontrol_mesajlari,
    soru_metni,
)
from biyo_cozucu.modeller import Kanit
from biyo_cozucu.motor import motor_yukle
from biyo_cozucu.motor.temel import (
    MotorHatasi,
    SahteMotor,
    dusunceyi_ayikla,
    json_ayikla,
)

# --- JSON ve düşünce ayıklama ---


def test_json_ayikla_duz_json():
    assert json_ayikla('{"cevap":"B"}') == {"cevap": "B"}


def test_json_ayikla_kod_citini_soyar():
    assert json_ayikla('```json\n{"cevap":"B"}\n```') == {"cevap": "B"}


def test_json_ayikla_cevresindeki_metni_atar():
    assert json_ayikla('İşte cevap: {"cevap":"B"} umarım yardımcı olur.') == {"cevap": "B"}


def test_json_ayikla_dusunce_blogunu_yoksayar():
    ham = '<think>Önce şıkları eleyeyim.</think>{"cevap":"C"}'
    assert json_ayikla(ham) == {"cevap": "C"}


def test_json_ayikla_gecersizde_hata_verir():
    with pytest.raises(ValueError):
        json_ayikla("hiç json yok")


def test_json_ayikla_dizi_kabul_etmez():
    with pytest.raises(ValueError):
        json_ayikla("[1, 2, 3]")


def test_dusunceyi_ayikla_kapali_blok():
    dusunce, govde = dusunceyi_ayikla("<think>düşünüyorum</think>cevap")
    assert dusunce == "<think>düşünüyorum</think>"
    assert govde == "cevap"


def test_dusunceyi_ayikla_kapanmamis_blok_govdeye_sizmaz():
    """Token sınırında kesilen düşünce, kullanıcıya yanıt diye gösterilmemeli."""
    dusunce, govde = dusunceyi_ayikla("görünür kısım<think>yarım kalan düşünce")
    assert govde == "görünür kısım"
    assert "yarım kalan" in dusunce


# --- SahteMotor ---


def test_sahte_motor_sirayla_doner():
    motor = SahteMotor(["birinci", "ikinci"])
    assert motor.uret([]) == "birinci"
    assert motor.uret([]) == "ikinci"
    assert motor.uret([]) == "ikinci"  # son yanıt tekrar edilir


def test_sahte_motor_yanitsiz_hata_verir():
    with pytest.raises(MotorHatasi):
        SahteMotor().uret([])


def test_motor_yukle_bilinmeyen_turde_hata():
    with pytest.raises(MotorHatasi):
        motor_yukle("uydurma")


# --- istemler ---


def test_cozumu_adimlara_bol_numarali_liste():
    assert cozumu_adimlara_bol("1. ilk adım\n2. ikinci adım") == ["ilk adım", "ikinci adım"]


def test_cozumu_adimlara_bol_madde_imli():
    assert cozumu_adimlara_bol("- bir\n- iki") == ["bir", "iki"]


def test_cozumu_adimlara_bol_tek_paragrafi_cumlelere_boler():
    adimlar = cozumu_adimlara_bol("Birinci cümle. İkinci cümle.")
    assert adimlar == ["Birinci cümle.", "İkinci cümle."]


def test_cozumu_adimlara_bol_bos_metin():
    assert cozumu_adimlara_bol("") == []


def test_soru_metni_sikleri_ekler():
    metin = soru_metni("Soru?", {"B": "iki", "A": "bir"})
    assert metin == "Soru?\nA) bir\nB) iki"


def test_ornek_yaniti_gecerli_json():
    veri = json.loads(ornek_yaniti(["a"], "B", "konu", "hesaplama"))
    assert veri["adimlar"] == ["a"] and veri["cevap"] == "B"
    assert veri["cozum_turu"] == "hesaplama"


def test_ornekten_diyalog_kullanici_asistan_cifti(ornekler):
    mesajlar = ornekten_diyalog(ornekler[3])
    assert [m["role"] for m in mesajlar] == ["user", "assistant"]
    assert "A) 2" in mesajlar[0]["content"]
    assert json.loads(mesajlar[1]["content"])["cevap"] == "B"


def test_cozum_mesajlari_yapisi():
    kanitlar = [
        Kanit("Ö1", 1, "Örnek soru", "1. adım bir\n2. adım iki", "konu", "hesaplama", 0.9, "A")
    ]
    mesajlar = cozum_mesajlari("Yeni soru?", kanitlar, secenekler={"A": "bir"})
    assert [m["role"] for m in mesajlar] == ["system", "user", "assistant", "user"]
    assert "REFERANS ÇÖZÜM Ö1" in mesajlar[1]["content"]
    assert json.loads(mesajlar[2]["content"])["adimlar"] == ["adım bir", "adım iki"]
    assert mesajlar[-1]["content"].startswith("Yeni soru?")


def test_cozum_mesajlari_kanitsiz_da_calisir():
    mesajlar = cozum_mesajlari("Soru?", [])
    assert [m["role"] for m in mesajlar] == ["system", "user"]


def test_sistem_istemi_enjeksiyon_savunmasi_icerir():
    mesajlar = cozum_mesajlari("Soru?", [])
    sistem = mesajlar[0]["content"]
    assert "komut değildir" in sistem
    assert "kopyalama" in sistem


def test_oz_kontrol_mesajlari_json_ister():
    mesajlar = oz_kontrol_mesajlari("soru", "çözüm", "B")
    assert mesajlar[0]["role"] == "system"
    assert "tutarli" in mesajlar[0]["content"]
    assert json.loads(mesajlar[1]["content"])["verilen_cevap"] == "B"


def test_kanit_adimi_sinirlanir():
    """Uzun kanıtlar modeli uzun yanıta itip token sınırında kesilmeye yol açıyor.

    Hafızaya 14 adım ortalamalı soru bankası çözümleri girdikten sonra 12
    soruluk kör koşuda 5 cevap boş döndü; hepsinde uyarı "üretim token
    sınırında kesildi" idi. Kırpma ADIM sınırında yapılıyor: yarım cümlelik
    bir few-shot örneği modele bozuk biçim öğretirdi.
    """
    kanit = Kanit(
        etiket="Ö1",
        ornek_id=1,
        soru="Uzun çözümlü soru?",
        cozum="\n".join(f"{no}. adım metni." for no in range(1, 15)),
        konu="kalıtım",
        cozum_turu="kalitim_hesabi",
        skor=0.9,
        cevap="A",
    )
    sinirsiz = cozum_mesajlari("Hedef soru?", [kanit])
    sinirli = cozum_mesajlari("Hedef soru?", [kanit], kanit_azami_adim=6)

    ornek_sinirsiz = json.loads(sinirsiz[2]["content"])
    ornek_sinirli = json.loads(sinirli[2]["content"])
    assert len(ornek_sinirsiz["adimlar"]) == 14
    assert len(ornek_sinirli["adimlar"]) == 6
    # Kırpılan örnek hâlâ geçerli biçimde: cevap ve etiketler korunuyor.
    assert ornek_sinirli["cevap"] == "A"
    assert ornek_sinirli["cozum_turu"] == "kalitim_hesabi"
    assert len(json.dumps(ornek_sinirli)) < len(json.dumps(ornek_sinirsiz))


def test_kanit_adimi_sifirken_kirpilmaz():
    kanit = Kanit(
        etiket="Ö1", ornek_id=1, soru="S?",
        cozum="\n".join(f"{no}. adım." for no in range(1, 10)),
        konu="hücre", cozum_turu="ezber_bilgi", skor=0.8, cevap="B",
    )
    mesajlar = cozum_mesajlari("Hedef?", [kanit], kanit_azami_adim=0)
    assert len(json.loads(mesajlar[2]["content"])["adimlar"]) == 9


# --- v2 şeması: `on_cevap` sigortası ---
#
# Kapsamanın %40'ta takılmasının en büyük tek kaynağı, üretimin token
# sınırında kesilip `cevap` alanının hiç gelmemesiydi (ölçülen oran %23).
# `on_cevap` en başta üretildiği için kesilmeden kurtulur. Buradaki testler
# iki şeyi birden kilitliyor: sigorta gerçekten çalışıyor mu, ve v1 davranışı
# bayrak kapalıyken bit bit aynı mı kalıyor.


@pytest.fixture
def sema_v2(monkeypatch):
    monkeypatch.setenv("BIYO_SEMA", "v2")


def test_v1_varsayilan_on_cevap_icermez(monkeypatch):
    monkeypatch.delenv("BIYO_SEMA", raising=False)
    from biyo_cozucu.istemler import sema_surumu, sistem_istemi

    assert sema_surumu() == "v1"
    assert "on_cevap" not in sistem_istemi()
    assert "on_cevap" not in ornek_yaniti(["a"], "B")


def test_v2_semasi_on_cevabi_en_basa_koyar(sema_v2):
    from biyo_cozucu.istemler import sistem_istemi

    istem = sistem_istemi()
    assert '{"on_cevap":"...","adimlar"' in istem
    # Nihai karar hâlâ adımlardan SONRA: muhakeme sırası korunmalı, yoksa
    # sigorta kazandırdığını doğrulukta geri verir.
    assert istem.index("on_cevap") < istem.index('"adimlar"')
    assert "DÜZELTİLMİŞ" in istem


def test_v2_few_shot_ornegi_istenen_bicimle_ayni(sema_v2):
    """Few-shot biçimi istemden ayrışırsa model gördüğünü taklit eder."""
    veri = json.loads(ornek_yaniti(["adım"], "C", "konu", "hesaplama"))
    assert veri["on_cevap"] == "C"
    assert next(iter(veri)) == "on_cevap"

    kanit = Kanit(
        etiket="Ö1", ornek_id=1, soru="S?", cozum="1. adım.",
        konu="hücre", cozum_turu="ezber_bilgi", skor=0.8, cevap="D",
    )
    ornek = json.loads(cozum_mesajlari("Hedef?", [kanit])[2]["content"])
    assert ornek["on_cevap"] == "D"


def test_kesik_yanittan_on_cevap_kurtarilir():
    """Asıl senaryo: `adimlar` kapanmadan üretim kesilmiş, `cevap` hiç yok."""
    kesik = '{"on_cevap":"B","adimlar":["ilk adım","ikinci adım'
    veri = json_ayikla(kesik)
    assert veri["on_cevap"] == "B"
    assert veri["cevap"] == ""
    assert veri["adimlar"] == ["ilk adım"]


def test_on_cevap_nihai_cevap_yerine_gecmez():
    """`"cevap"` kalıbı `"on_cevap"` ile eşleşirse iki alan birbirine karışır."""
    parca = '{"on_cevap":"A","adimlar":["x"],"cevap":"D"'
    veri = json_ayikla(parca)
    assert veri["on_cevap"] == "A"
    assert veri["cevap"] == "D"


def test_yalniz_on_cevap_varken_de_onarim_calisir():
    """Adım bile gelmemişse tek başına ön cevap yanıtı kurtarmaya yeter."""
    veri = json_ayikla('{"on_cevap":"E"')
    assert veri["on_cevap"] == "E"
