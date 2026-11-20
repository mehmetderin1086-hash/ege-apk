from __future__ import annotations

import json
from dataclasses import replace

import pytest

from biyo_cozucu.cozucu import Cozucu
from biyo_cozucu.degerlendirme import cozum_puanla, kor_kosu, ozetle
from biyo_cozucu.hafiza.indeks import OrnekIndeksi
from biyo_cozucu.metin import esitle
from biyo_cozucu.modeller import Cozum, Ornek
from biyo_cozucu.motor.temel import SahteMotor
from biyo_cozucu.veri.acik_setler import (
    KAYITLI_SETLER,
    LisansHatasi,
    VeriSetiHatasi,
    _openbookqa_ornek,
    ornekleri_al,
)
from biyo_cozucu.veri.disa_aktar import bol, egitim_verisi_yaz, ornekten_ornek_kaydi

# --- eşleştirme katlaması (gerçek bir hatanın regresyon testi) ---


def test_esitle_buyuk_harfli_alinti_sozcugu_eslestirir():
    """"OPTIMUM" Türkçe kurala göre "optımum" olur; eşleştirme bunu ayırmamalı."""
    assert esitle("OPTIMUM") == esitle("optimum") == "optimum"
    assert esitle("MİTOKONDRİ") == esitle("mitokondri")
    assert esitle("IŞIK") == esitle("ışık")


# --- değerlendirme ---


def test_cozum_puanla_dogru_cevabi_tanir(ornekler):
    uretilen = Cozum(
        soru=ornekler[3].soru,
        adimlar=["Mayoz kromozom sayısını yarıya indirir.", "2n=8 ise n=4 olur."],
        cevap="B",
        guven=0.8,
    )
    sonuc = cozum_puanla(uretilen, ornekler[3])
    assert sonuc.cevap_dogru
    assert sonuc.adim_ortusmesi > 0.3
    assert sonuc.cozum_turu == "hesaplama"


def test_cozum_puanla_yanlis_cevabi_yakalar(ornekler):
    uretilen = Cozum(soru=ornekler[3].soru, adimlar=["yanlış"], cevap="D")
    assert not cozum_puanla(uretilen, ornekler[3]).cevap_dogru


def test_cozum_puanla_anlamsal_katmani_kullanir(ornekler, sahte_gomlemci):
    uretilen = Cozum(soru=ornekler[0].soru, adimlar=["DNA interfazda eşlenir."], cevap="x")
    gommesiz = cozum_puanla(uretilen, ornekler[0])
    gommeli = cozum_puanla(uretilen, ornekler[0], sahte_gomlemci)
    assert gommeli.adim_ortusmesi != gommesiz.adim_ortusmesi


def test_kor_kosu_test_ornegini_kanit_olarak_kullanmaz(dolu_depo, ornekler, sahte_gomlemci):
    """Sızıntı olsaydı doğruluk yapay biçimde yükselirdi; getirilen kanıt id'leri kontrol edilir."""
    motor = SahteMotor(json.dumps({"adimlar": ["a"], "cevap": "B", "guven": 0.9}))
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=motor,
        gomlemci=sahte_gomlemci,
    )
    test_kumesi = [ornekler[1], ornekler[3]]
    ozet = kor_kosu(cozucu, test_kumesi)

    assert ozet.toplam == 2
    for mesajlar in motor.cagrilar:
        referanslar = "\n".join(
            m["content"] for m in mesajlar if m["content"].startswith("[REFERANS")
        )
        assert ornekler[1].soru not in referanslar
        assert ornekler[3].soru not in referanslar


def test_kor_kosu_cozumleri_depoya_yazmaz(dolu_depo, ornekler, sahte_gomlemci):
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=SahteMotor(json.dumps({"adimlar": ["a"], "cevap": "B", "guven": 0.9})),
        gomlemci=sahte_gomlemci,
    )
    kor_kosu(cozucu, [ornekler[3]])
    assert dolu_depo.ozet()["cozum"] == 0


def test_ozetle_tur_bazli_dagilim_uretir(ornekler):
    sonuclar = [
        cozum_puanla(Cozum(soru=o.soru, adimlar=["a"], cevap=o.cevap), o)
        for o in ornekler
    ]
    ozet = ozetle(sonuclar)
    assert ozet.toplam == 5
    assert ozet.dogruluk == 1.0
    assert ozet.tur_bazli["mekanizma_aciklama"]["adet"] == 2
    assert "Doğruluk: 100.0%" in ozet.rapor()


def test_ozetle_bos_listede_cokmez():
    assert ozetle([]).toplam == 0


# --- eğitim verisi ---


def test_ornekten_ornek_kaydi_chat_bicimi(ornekler):
    kayit = ornekten_ornek_kaydi(ornekler[3])
    roller = [m["role"] for m in kayit["messages"]]
    assert roller == ["system", "user", "assistant"]
    son = json.loads(kayit["messages"][-1]["content"])
    assert son["cevap"] == "B"
    assert son["adimlar"][0].startswith("Mayoz")


def test_ornekten_ornek_kaydi_sistemsiz(ornekler):
    """Sistem mesajını kapatmak için AÇIK boş dize gerekir.

    `None` "etkin şemanın istemini kullan" demek: eğitim verisi sabit bir
    istem sürümüne bağlanırsa, şema değiştiğinde hedef yanıt ile sistem
    mesajı ayrışır ve model eğitimde gördüğünden farklı biçimle çalıştırılır.
    """
    kayit = ornekten_ornek_kaydi(ornekler[0], sistem="")
    assert [m["role"] for m in kayit["messages"]] == ["user", "assistant"]


def test_egitim_kaydi_etkin_semayi_izler(ornekler, monkeypatch):
    monkeypatch.setenv("BIYO_SEMA", "v2")
    kayit = ornekten_ornek_kaydi(ornekler[3])
    sistem = kayit["messages"][0]["content"]
    hedef = json.loads(kayit["messages"][-1]["content"])
    # İkisi de v2 olmalı; biri v1 biri v2 ise eğitim verisi kendi içinde tutarsız.
    assert "on_cevap" in sistem
    assert "on_cevap" in hedef


def test_bol_kararlidir(ornekler):
    """Aynı örnek kümesi her çalıştırmada aynı bölmeyi vermeli."""
    ilk = bol(ornekler)
    ikinci = bol(list(reversed(ornekler)))
    assert {o.id for o in ilk[2]} == {o.id for o in ikinci[2]}
    assert {o.id for o in ilk[1]} == {o.id for o in ikinci[1]}


def test_bol_yeni_ornek_eskilerin_kumesini_degistirmez(ornekler):
    onceki = bol(ornekler)
    yeni_liste = [*ornekler, Ornek(id=99, soru="Yeni bir soru?", cozum="Yeni çözüm.")]
    sonraki = bol(yeni_liste)
    for eski_kume, yeni_kume in zip(onceki, sonraki, strict=True):
        eski_idler = {o.id for o in eski_kume}
        yeni_idler = {o.id for o in yeni_kume}
        assert eski_idler <= yeni_idler


def test_bol_gecersiz_oranlari_reddeder(ornekler):
    with pytest.raises(ValueError):
        bol(ornekler, dogrulama_orani=0.6, test_orani=0.5)


def test_egitim_verisi_yaz_dosyalari_uretir(ornekler, sahte_gomlemci, tmp_path):
    ozet = egitim_verisi_yaz(
        ornekler, tmp_path / "v1", etiket="v1", gomlemci=sahte_gomlemci
    )
    assert (tmp_path / "v1" / "train.jsonl").exists()
    assert (tmp_path / "v1" / "valid.jsonl").exists()
    assert (tmp_path / "v1" / "test.jsonl").exists()
    assert json.loads((tmp_path / "v1" / "ozet.json").read_text())["etiket"] == "v1"
    assert ozet.egitim + ozet.dogrulama + ozet.test == 5


def test_egitim_kayitlari_kendi_cevabini_ornek_gostermez(ornekler, sahte_gomlemci, tmp_path):
    """Kanıtlı eğitimde örneğin kendisi kanıt olursa model kopyalamayı öğrenir."""
    egitim_verisi_yaz(ornekler, tmp_path / "v1", kanit_sayisi=2, gomlemci=sahte_gomlemci)
    satirlar = (tmp_path / "v1" / "train.jsonl").read_text(encoding="utf-8").splitlines()
    for satir in satirlar:
        mesajlar = json.loads(satir)["messages"]
        hedef_soru = mesajlar[-2]["content"]
        referanslar = [m["content"] for m in mesajlar if m["content"].startswith("[REFERANS")]
        assert all(hedef_soru not in r for r in referanslar)


def test_kanitsiz_disa_aktarma_referans_eklemez(ornekler, tmp_path):
    egitim_verisi_yaz(ornekler, tmp_path / "v2", kanitli=False)
    satirlar = (tmp_path / "v2" / "train.jsonl").read_text(encoding="utf-8").splitlines()
    for satir in satirlar:
        roller = [m["role"] for m in json.loads(satir)["messages"]]
        assert roller == ["system", "user", "assistant"]


def test_test_kumesi_ham_ornek_olarak_yazilir(ornekler, tmp_path):
    egitim_verisi_yaz(ornekler, tmp_path / "v3", kanitli=False)
    satirlar = (tmp_path / "v3" / "test.jsonl").read_text(encoding="utf-8").splitlines()
    for satir in satirlar:
        veri = json.loads(satir)
        assert "soru" in veri and "messages" not in veri
        Ornek(**veri)  # doğrudan Ornek olarak yüklenebilmeli


# --- açık veri setleri ---


def test_nd_lisansli_set_egitime_alinmaz():
    with pytest.raises(LisansHatasi, match="lisansı"):
        ornekleri_al("turkish_mmlu", amac="egitim")


def test_bilinmeyen_veri_seti_hata_verir():
    with pytest.raises(KeyError):
        ornekleri_al("uydurma_set")


def test_gorsel_gerektiren_set_nedeniyle_birlikte_reddedilir():
    """YKSBench'te soru METNİ yok, yalnız görüntü var (HF şemasından doğrulandı).

    Eskiden yalnız "dönüştürücü yazılmadı" deniyordu; kullanıcı engelin
    unutulmuş bir iş mi yoksa biçimsel bir imkânsızlık mı olduğunu bilemiyordu.
    """
    with pytest.raises(VeriSetiHatasi, match="görüntü"):
        ornekleri_al("yksbench", amac="degerlendirme")


def test_kapili_set_token_gerektigini_soyler():
    with pytest.raises(VeriSetiHatasi, match="HF_TOKEN"):
        ornekleri_al("turkish_mmlu", amac="degerlendirme")


def test_lisans_kapisi_kapili_engelden_once_calisir():
    """Lisans bir KURAL, kapılılık bir DURUM; kural önce uygulanmalı.

    Aksi halde kullanıcı token alıp şartları kabul ettikten sonra "aslında
    zaten eğitime giremezdi" duvarına çarpardı.
    """
    with pytest.raises(LisansHatasi):
        ornekleri_al("turkish_mmlu", amac="egitim")


# --- openbookqa dönüştürücüsü ---


def _openbookqa_satiri(**degisiklik) -> dict:
    satir = {
        "id": "7-980",
        "question_stem": "The sun is responsible for",
        "choices": {
            "text": ["puppies learning tricks", "children growing up",
                     "flowers wilting", "plants sprouting and blooming"],
            "label": ["A", "B", "C", "D"],
        },
        "answerKey": "D",
        "fact1": "the sun is the source of energy for physical cycles on Earth",
    }
    satir.update(degisiklik)
    return satir


def test_openbookqa_ornegi_siklari_ve_olguyu_tasir():
    ornek = _openbookqa_ornek(_openbookqa_satiri())
    assert ornek is not None
    assert ornek.soru == "The sun is responsible for"
    assert ornek.secenekler["D"] == "plants sprouting and blooming"
    assert ornek.cevap == "D"
    assert ornek.cevap_turu == "coktan_secmeli"
    assert "source of energy" in ornek.cozum
    assert ornek.kaynak == "openbookqa"


def test_openbookqa_olgusuz_kayit_atlanir():
    """Gerekçesiz cevap ezberletmek referans örneğin amacına aykırı.

    `main` yapılandırmasında `fact1` hiç yok; oradan gelen kayıtlar sessizce
    hafızaya girmemeli.
    """
    assert _openbookqa_ornek(_openbookqa_satiri(fact1="")) is None
    satir = _openbookqa_satiri()
    del satir["fact1"]
    assert _openbookqa_ornek(satir) is None


def test_openbookqa_cevap_siklarla_uyusmazsa_atlanir():
    assert _openbookqa_ornek(_openbookqa_satiri(answerKey="Z")) is None


def test_openbookqa_bozuk_sik_yapisi_atlanir():
    bozuk = _openbookqa_satiri(choices={"text": ["bir", "iki"], "label": ["A"]})
    assert _openbookqa_ornek(bozuk) is None
    assert _openbookqa_ornek(_openbookqa_satiri(choices={})) is None


def test_kayitli_setlerin_durum_ozeti_tutarli():
    for veri_seti in KAYITLI_SETLER.values():
        ozet = veri_seti.durum_ozeti()
        assert ozet in {"hazır", "kapılı", "görsel"}
        assert bool(veri_seti.engel()) == (ozet != "hazır")


def test_kor_kosu_ornegin_gorselini_gecirir(dolu_depo, ornekler, sahte_gomlemci, tmp_path):
    """Ölçüm, gerçek çözüm yoluyla aynı girdiyi kullanmalı.

    Görsel geçilmediğinde 150 şekilli soru burada şekilsiz çözülüyordu; koşu
    sistemin gerçek performansını değil daha kötüsünü ölçüyordu. Metin
    motorunda görüntü modele gitmediği için istem "şekli oku" DEMEZ (bkz.
    `Cozucu._gorsel_modele_gidiyor`), ama motorun şekli okuyamadığı uyarıya
    çevrilir ve çözüm incelemeye düşer.
    """
    pytest.importorskip("PIL")
    from biyo_cozucu.gorsel import GorselDeposu
    from biyo_cozucu.istemler import GORSEL_KURALI
    from tests.test_soru_kesici import _png

    deposu = GorselDeposu(tmp_path)
    sekilli = replace(
        ornekler[3],
        soru="Aşağıdaki şekildeki bilgiye göre " + ornekler[3].soru,
        gorsel=deposu.yaz(_png()),
    )
    motor = SahteMotor(json.dumps({"adimlar": ["a"], "cevap": "B", "guven": 0.9}))
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=motor,
        gomlemci=sahte_gomlemci,
        gorsel_deposu=deposu,
    )
    ozet = kor_kosu(cozucu, [sekilli])

    # Görsel çözücüye ulaştı: metin motoru okuyamadığı için uyarı üretildi.
    assert ozet.inceleme_orani == 1.0
    # Ama isteme "şekli oku" talimatı EKLENMEDİ: şekil modele verilmiyor.
    assert GORSEL_KURALI not in motor.cagrilar[0][0]["content"]


def test_kor_kosu_gorsel_modunu_zorlayabilir(dolu_depo, ornekler, sahte_gomlemci, tmp_path):
    pytest.importorskip("PIL")
    from biyo_cozucu.gorsel import GorselDeposu
    from tests.test_soru_kesici import _png

    deposu = GorselDeposu(tmp_path)
    sekilli = replace(ornekler[3], gorsel=deposu.yaz(_png()))
    motor = SahteMotor(json.dumps({"adimlar": ["a"], "cevap": "B", "guven": 0.9}))
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=motor,
        gomlemci=sahte_gomlemci,
        gorsel_deposu=deposu,
    )

    ozet = kor_kosu(cozucu, [sekilli], gorsel_modu="zorla")

    assert ozet.inceleme_orani == 1.0


def test_kor_kosu_gorselsiz_orneke_gorsel_kurali_eklemez(
    dolu_depo, ornekler, sahte_gomlemci
):
    from biyo_cozucu.istemler import GORSEL_KURALI

    motor = SahteMotor(json.dumps({"adimlar": ["a"], "cevap": "B", "guven": 0.9}))
    cozucu = Cozucu(
        depo=dolu_depo,
        indeks=OrnekIndeksi.kur(ornekler, sahte_gomlemci),
        motor=motor,
        gomlemci=sahte_gomlemci,
    )
    kor_kosu(cozucu, [ornekler[3]])

    assert GORSEL_KURALI not in motor.cagrilar[0][0]["content"]


def test_egitim_kaydi_kaniti_sinirlar_hedefi_sinirlamaz():
    """Eğitim ve çıkarım aynı bağlam biçimini görmeli.

    Kanıt bloğu eğitim kaydının ~%50'siydi ve sınırsızdı; çıkarım tarafı
    `Ayarlar.kanit_azami_adim` ile 6 adıma inince ikisi ayrıştı. Hedef
    (öğrenilecek çözüm) kısaltılmaz: model tam çözüm üretmeyi öğrenmeli.
    """
    from biyo_cozucu.modeller import Kanit

    uzun = "\n".join(f"{no}. adım." for no in range(1, 15))
    kanit = Kanit(
        etiket="Ö1", ornek_id=1, soru="Kanıt sorusu?", cozum=uzun,
        konu="kalıtım", cozum_turu="kalitim_hesabi", skor=0.9, cevap="A",
    )
    hedef = Ornek(soru="Hedef soru?", cozum=uzun, cevap="C", konu="kalıtım")

    kayit = ornekten_ornek_kaydi(hedef, kanitlar=[kanit], kanit_azami_adim=6)
    mesajlar = kayit["messages"]
    assert len(json.loads(mesajlar[2]["content"])["adimlar"]) == 6
    assert len(json.loads(mesajlar[-1]["content"])["adimlar"]) == 14


def test_egitim_verisi_varsayilani_cikarimla_ayni(tmp_path, ornekler, sahte_gomlemci):
    """Tek kaynak: `istemler.VARSAYILAN_KANIT_ADIMI`. Ayrışırsa eğitim boşa gider."""
    from biyo_cozucu.cozucu import Ayarlar
    from biyo_cozucu.istemler import VARSAYILAN_KANIT_ADIMI

    assert Ayarlar().kanit_azami_adim == VARSAYILAN_KANIT_ADIMI

    uzun = [
        replace(o, cozum="\n".join(f"{n}. adım {o.konu}." for n in range(1, 15)))
        for o in ornekler
    ]
    egitim_verisi_yaz(uzun, tmp_path, gomlemci=sahte_gomlemci, kanit_sayisi=1)
    satirlar = (tmp_path / "train.jsonl").read_text(encoding="utf-8").splitlines()
    kanitli = [
        json.loads(s)["messages"]
        for s in satirlar
        if "[REFERANS" in s
    ]
    assert kanitli, "kanıtlı eğitim kaydı üretilmedi"
    for mesajlar in kanitli:
        for mesaj in mesajlar[2:-2:2]:
            assert len(json.loads(mesaj["content"])["adimlar"]) <= VARSAYILAN_KANIT_ADIMI


def _sonuc(dogru: bool, guven: float):
    from biyo_cozucu.degerlendirme import OrnekSonucu

    return OrnekSonucu(
        ornek_id=None, soru="s", beklenen_cevap="A",
        uretilen_cevap="A" if dogru else "B", cevap_dogru=dogru,
        adim_ortusmesi=0.5, guven=guven, incele=False, cozum_turu="ezber_bilgi",
    )


def test_secici_dogruluk_kapsamayla_birlikte_okunur():
    """Kapsamayı düşürerek seçici doğruluğu şişirmek kolay; ikisi birlikte raporlanmalı."""
    ozet = ozetle([_sonuc(True, 0.9), _sonuc(True, 0.8), _sonuc(False, 0.4), _sonuc(False, 0.2)])
    assert ozet.dogruluk == 0.5
    kapsama, secici = ozet.secici(0.75)
    assert kapsama == 0.5           # 4 sorunun 2'si cevaplandı
    assert secici == 1.0            # cevaplananların hepsi doğru
    kapsama_hepsi, secici_hepsi = ozet.secici(0.0)
    assert kapsama_hepsi == 1.0
    assert secici_hepsi == 0.5


def test_hedef_esigi_en_yuksek_kapsamayi_secer():
    """Hedefi sağlayan birden çok eşik varsa en çok soruyu cevaplayan seçilmeli."""
    ozet = ozetle([_sonuc(True, 0.9), _sonuc(True, 0.7), _sonuc(False, 0.3)])
    hedef = ozet.hedef_esigi(0.95)
    assert hedef is not None
    esik, kapsama, dogruluk = hedef
    assert dogruluk == 1.0
    assert kapsama == pytest.approx(2 / 3, abs=0.01)
    assert esik <= 0.7


def test_hedef_saglanamazsa_none_doner():
    ozet = ozetle([_sonuc(False, 0.95), _sonuc(True, 0.9)])
    assert ozet.hedef_esigi(0.95) is None
    assert "sağlanmıyor" in ozet.rapor()
