import numpy as np
import pytest

from sinav_okur.modeller import (
    CevapAnahtari,
    RubrikKalemi,
    Soru,
    SoruTipi,
    TanimaSonucu,
)
from sinav_okur.puanlama import PuanlamaAyar, puanla
from sinav_okur.puanlama.bosluk import bosluk_puanla
from sinav_okur.puanlama.rubrik import rubrik_puanla


# --- Boşluk doldurma ---

def _bosluk_soru():
    return Soru(no=1, tip=SoruTipi.BOSLUK_DOLDURMA, metin="...", puan=10,
               anahtar=CevapAnahtari(dogru_cevaplar=["mitokondri"]))


def test_bosluk_tam_dogru():
    s = bosluk_puanla("mitokondri", _bosluk_soru())
    assert s.puan == 10 and not s.incele


def test_bosluk_htr_hatasi_tolere():
    # tek harf hatası, aksan farkı → yine tam puana yakın
    s = bosluk_puanla("mitokondiri", _bosluk_soru())
    assert s.puan == 10


def test_bosluk_aksansiz_kabul():
    s = bosluk_puanla("hucre", Soru(no=1, tip=SoruTipi.BOSLUK_DOLDURMA, metin="x", puan=5,
                                    anahtar=CevapAnahtari(dogru_cevaplar=["hücre"])))
    assert s.puan == 5


def test_bosluk_yanlis():
    s = bosluk_puanla("kloroplast", _bosluk_soru())
    assert s.puan == 0


def test_bosluk_bos():
    s = bosluk_puanla("", _bosluk_soru())
    assert s.puan == 0 and not s.incele


def test_bosluk_sinirda_incele():
    ayar = PuanlamaAyar()
    # kasıtlı sınır: eşiğin hemen altına düşen benzerlik
    s = bosluk_puanla("mitokon", _bosluk_soru(), ayar)
    assert s.incele  # süpheli banda düşmeli


# --- Rubrik (sözcüksel, gömlemci yok) ---

def _kisa_soru():
    return Soru(no=2, tip=SoruTipi.KISA_CEVAP, metin="...", puan=20,
                anahtar=CevapAnahtari(rubrik=[
                    RubrikKalemi("madde giriş çıkışını kontrol eder", 10,
                                 ["seçici geçirgenlik"]),
                    RubrikKalemi("hücreyi dış ortamdan ayırır", 10, ["hücreyi korur"]),
                ]))


def test_rubrik_ikisi_de_var():
    metin = "Hücre zarı madde giriş çıkışını kontrol eder ve hücreyi dış ortamdan ayırır."
    s = rubrik_puanla(metin, _kisa_soru())
    assert s.puan == 20


def test_rubrik_esanlamli_ile():
    metin = "Seçici geçirgenlik sağlar, ayrıca hücreyi korur."
    s = rubrik_puanla(metin, _kisa_soru())
    assert s.puan == 20


def test_rubrik_kisa_esdegerde_turkce_cekim_ekini_tolere_eder():
    soru = Soru(
        no=9,
        tip=SoruTipi.KISA_CEVAP,
        metin="Kavanozda ne oldu?",
        puan=5,
        anahtar=CevapAnahtari(
            rubrik=[
                RubrikKalemi(
                    "Açık kavanoza sinekler girmiştir.",
                    5,
                    ["sinekler girdi"],
                )
            ]
        ),
    )

    sonuc = rubrik_puanla(
        "Birinci kavanozun içine sinekler girmiştir.",
        soru,
    )

    assert sonuc.puan == 5


def test_rubrik_yarim():
    s = rubrik_puanla("Sadece hücreyi korur.", _kisa_soru())
    assert s.puan == 10


def test_rubrik_hic():
    s = rubrik_puanla("Bilmiyorum.", _kisa_soru())
    assert s.puan == 0


def test_rubrik_dogru_yonteme_sonuc_hatasi_olsa_da_kismi_puan_verir():
    soru = Soru(
        no=7,
        tip=SoruTipi.ACIK_UCLU,
        metin="Problemi çözünüz ve işlemleri gösteriniz.",
        puan=10,
        anahtar=CevapAnahtari(
            rubrik=[
                RubrikKalemi(
                    "Verilenleri kullanarak doğru denklemi kurar",
                    6,
                    ["doğru denklem kurma"],
                ),
                RubrikKalemi("Doğru sayısal sonuca ulaşır", 4),
            ]
        ),
    )

    sonuc = rubrik_puanla(
        "Denklemi doğru kurmaya başladım fakat bir terimi eksik bırakıp "
        "aritmetik hatadan sonucu yanlış buldum.",
        soru,
    )

    assert 0 < sonuc.puan < soru.puan
    assert any("doğru mantık/yöntem izi" in d for d in sonuc.detaylar)


def test_rubrik_olumlu_olumsuz_celiskisine_kismi_puan_vermez():
    soru = Soru(
        no=8,
        tip=SoruTipi.ACIK_UCLU,
        metin="Kavanoz sonucunu yazınız.",
        puan=5,
        anahtar=CevapAnahtari(
            rubrik=[RubrikKalemi("Kavanozda kurtçuk oluşmamıştır", 5)]
        ),
    )

    sonuc = rubrik_puanla("Kavanozda kurtçuk oluşmuştur.", soru)

    assert sonuc.puan == 0


def test_rubrik_puan_tavani():
    # toplam rubrik puanı soru puanını aşamaz
    soru = Soru(no=3, tip=SoruTipi.KISA_CEVAP, metin="x", puan=10,
                anahtar=CevapAnahtari(rubrik=[
                    RubrikKalemi("a", 8), RubrikKalemi("b", 8)]))
    s = rubrik_puanla("a b", soru)
    assert s.puan == 10


# --- puanla() giriş noktası + HTR güveni ---

def test_htr_dusuk_guven_incele():
    soru = _bosluk_soru()
    s = puanla(TanimaSonucu(metin="mitokondri", guven=0.4), soru)
    assert s.puan == 10 and s.incele  # doğru ama güven düşük → onaya düşer


def test_htr_yuksek_guven_otomatik():
    s = puanla(TanimaSonucu(metin="mitokondri", guven=0.95), _bosluk_soru())
    assert s.puan == 10 and not s.incele


def test_dogrulanmamis_rag_anahtari_puan_vermez():
    soru = Soru(
        no=8,
        tip=SoruTipi.ACIK_UCLU,
        metin="Soru",
        puan=10,
        anahtar=CevapAnahtari(
            rubrik=[RubrikKalemi("mitokondri", 10)],
            otomatik_uretildi=True,
            otomatik_puanlama=False,
            uyari="Kanıt yetersiz.",
        ),
    )

    sonuc = puanla("mitokondri", soru)

    assert sonuc.puan == 0
    assert sonuc.incele is True
    assert "Kanıt yetersiz" in sonuc.detaylar[0]


# --- Anlamsal katman (sahte gömlemci) ---

class SahteGomlemci:
    """'santral' ↔ 'kontrol eder' kalemine yüksek benzerlik veren sahte gömlemci."""

    def gom(self, metinler):
        vek = []
        for m in metinler:
            if "santral" in m or "kontrol" in m or "giriş" in m:
                vek.append([1.0, 0.0])
            else:
                vek.append([0.0, 1.0])
        return np.array(vek, dtype=float)


def test_anlamsal_kurtarma_rolunde_kismi_puan_verir():
    """Varsayılan rol "kurtarma": anlamsal benzerlik TEK BAŞINA tam puan vermez.

    ÖLÇÜLDÜ: eşdeğer ve farklı cevapların benzerlik dağılımları örtüşüyor
    ("mayoz çeşitlilik sağlar" ↔ "mitoz kromozom korunur" = 0.692), yani
    yüksek benzerlik "aynı şeyi söylüyor" anlamına gelmiyor. Katman haksız
    sıfırı önler ama tam puanı sözcüksel kanıt olmadan açmaz.
    """
    soru = _kisa_soru()

    s = rubrik_puanla("hücrenin santralidir", soru, gomlemci=SahteGomlemci())

    assert 0 < s.puan < 10, "kısmi puan verilmeli, tam puan değil"


def test_anlamsal_tam_rolu_yuksek_esik_ve_sozcuksel_destek_ister():
    """"tam" rolü açılsa bile iki koruma kalır: yüksek eşik + sözcüksel destek.

    Ölçülen risk: 0.60 eşiğinde farklı kavramlar da eşleşiyordu
    ("mayoz çeşitlilik" ↔ "mitoz kromozom korunur" = 0.692).
    """
    from sinav_okur.puanlama.ayarlar import PuanlamaAyar
    from sinav_okur.puanlama.rubrik import _anlamsal_tam_puan_verilir

    kurtarma = PuanlamaAyar()
    tam = PuanlamaAyar(anlamsal_rol="tam")

    # Kurtarma rolünde anlamsal katman tek başına tam puan AÇMAZ.
    assert _anlamsal_tam_puan_verilir(80.0, 0.95, kurtarma) is False
    # "tam" rolünde yüksek benzerlik + sözcüksel destek varsa açar.
    assert _anlamsal_tam_puan_verilir(80.0, 0.95, tam) is True
    # Eşiğin altındaki benzerlik "tam" rolünde de açmaz.
    assert _anlamsal_tam_puan_verilir(80.0, 0.69, tam) is False
    # Sözcüksel destek yoksa yüksek benzerlik yanıltıcıdır.
    assert _anlamsal_tam_puan_verilir(20.0, 0.95, tam) is False


# --- Çoktan seçmeli dalı (puanla → bosluk_puanla) ---

def _coktan_secmeli(dogru="B"):
    return Soru(no=5, tip=SoruTipi.COKTAN_SECMELI, metin="...", puan=4,
                anahtar=CevapAnahtari(dogru_cevaplar=[dogru]))


def test_coktan_secmeli_dogru_sik_tam_puan():
    s = puanla(TanimaSonucu(metin="B", guven=0.95), _coktan_secmeli("B"))
    assert s.puan == 4 and not s.incele


def test_coktan_secmeli_yanlis_sik_sifir():
    s = puanla(TanimaSonucu(metin="C", guven=0.95), _coktan_secmeli("B"))
    assert s.puan == 0


def test_coktan_secmeli_bos_incele_gerektirmez():
    s = puanla(TanimaSonucu(metin="", guven=1.0), _coktan_secmeli("B"))
    assert s.puan == 0 and not s.incele


def test_coktan_secmeli_anahtarsiz_hata():
    with pytest.raises(ValueError):
        Soru(no=5, tip=SoruTipi.COKTAN_SECMELI, metin="x", puan=4,
             anahtar=CevapAnahtari(dogru_cevaplar=[]))


# --- Formül/ispat dalı (puanla → formul_puanla) ---

def _formul_soru(dogru="2*x+3", puan=10, **ek):
    return Soru(no=6, tip=SoruTipi.FORMUL_ISPAT, metin="İfadeyi yazınız.", puan=puan,
                anahtar=CevapAnahtari(dogru_cevaplar=[dogru], **ek))


def test_formul_esdeger_tam_puan():
    s = puanla(TanimaSonucu(metin="3 + 2*x", guven=0.95), _formul_soru())
    assert s.puan == 10 and not s.incele
    assert s.kararlar[-1]["tur"] == "formul" and s.kararlar[-1]["esdeger"]


def test_formul_esdeger_degil_sifir_ve_incele():
    s = puanla(TanimaSonucu(metin="5*x - 1", guven=0.95), _formul_soru())
    assert s.puan == 0 and s.incele


def test_formul_yontem_adimli_kismi_puan():
    soru = Soru(
        no=6, tip=SoruTipi.FORMUL_ISPAT, metin="İspatlayınız.", puan=10,
        anahtar=CevapAnahtari(
            dogru_cevaplar=["2*x+3"],
            yontem_adimlari=["dağıtma", "sadeleştirme"],
            rubrik=[RubrikKalemi("dağıtma özelliğini uygular", 3)],
        ),
    )
    # Eşdeğer sonuç: yöntem payı (rubrik) + sonuç payı (0.7*puan)
    s = puanla(TanimaSonucu(metin="2*x + 3", guven=0.95), soru)
    assert 0 < s.puan <= soru.puan


def test_formul_sayisala_delege():
    # Formül işareti yok ama sayı var → sayisal_puanla'ya düşer
    soru = _formul_soru(dogru="42")
    s = puanla(TanimaSonucu(metin="42", guven=0.95), soru)
    assert s.puan == soru.puan
    assert s.kararlar[-1]["tur"] == "sayisal_sonuc"
