"""Dar biyobirikim aracinin pozitifleri ve geri cekilme kapilari."""

from __future__ import annotations

import json

import pytest

from biyo_cozucu.biyobirikim import coz
from biyo_cozucu.cozucu import Ayarlar, Cozucu
from biyo_cozucu.depo import Depo
from biyo_cozucu.hafiza.indeks import OrnekIndeksi

SIKLAR = {
    "A": "Yalnız I",
    "B": "Yalnız II",
    "C": "Yalnız III",
    "D": "I ve II",
    "E": "II ve III",
}

TEMIZ_SORU = """
Bir göl ekosisteminde canlıların dokularında biriken toksik maddenin trofik
düzeylere göre dağılımı araştırılıyor. Bu araştırmaya göre
I. Omnivorların toksik madde birikiminin herbivorlardakinden daha fazla olması beklenir.
II. Ototrofların toksik madde birikiminin omurgasızlardakinden daha fazla olması beklenir.
III. Herbivorların toksik madde birikiminin karnivorlardakinden daha fazla olması beklenir.
yorumlarından hangileri yapılamaz?
"""

GERCEK_OCR_SORUSU = (
    "Bir göl ekosisteminde suda tespit edilen ve canlıların vücutlarında biriken "
    "toksik bir maddenin farklı trofik düzeylerdeki birikimini belirlemeye çalışan "
    "araştırmacıların elde ettiği sonuçlar aşağıda verilmiş Karnivor balıkların "
    "dokularında tespit edilen toks madde birikimi omurgasızlardakinden daha fazki "
    "Herbivor balıkların dokularında tespit edilen toks madde birikimi alglerdekinden "
    "daha fazladır. Bu araştırmanın sonuçlarına göre 1. Omnivor türlerin "
    "dokularındaki toksik madde birikiminin herbivorlardakinden daha fazla olması "
    "beklenir. II. Ototrof organizmaların dokularındaki toksik madde birikiminin "
    "omurgasızlardakinden daha olması beklenir. III. Herbivor balıkların "
    "dokularındaki toksik madde birikiminin karnivor balıklardakinden daha fazla "
    "olması beklenir. yorumlarından hangileri yapılamaz?"
)


class SayacliMotor:
    ad = "sayacli"

    def __init__(self) -> None:
        self.cagrilar: list[list[dict[str, str]]] = []

    def uret(self, mesajlar, *, sicaklik=0.0, azami_token=0) -> str:
        self.cagrilar.append(mesajlar)
        return json.dumps({"adimlar": ["model"], "cevap": "B", "guven": 0.9})


def _cozucu(tmp_path, motor: SayacliMotor | None = None, **ayarlar) -> Cozucu:
    return Cozucu(
        depo=Depo(tmp_path / "biyo.db"),
        indeks=OrnekIndeksi.kur([], None),
        motor=motor,
        ayarlar=Ayarlar(onbellek_aktif=False, deneme_sayisi=1, **ayarlar),
    )


def test_temiz_yapilamaz_sorusu_e_sikkini_bulur():
    sonuc = coz(TEMIZ_SORU, SIKLAR)
    assert sonuc is not None
    assert sonuc.cevap == "E"
    assert sonuc.guven == pytest.approx(0.95)
    assert not sonuc.incele
    assert not sonuc.uyarilar


def test_yapilabilir_koku_dogru_ifadeleri_secer():
    sonuc = coz(TEMIZ_SORU.replace("yapılamaz", "yapılabilir"), SIKLAR)
    assert sonuc is not None
    assert sonuc.cevap == "A"


def test_daha_az_yonu_ters_karsilastirilir():
    soru = """
    Toksik madde birikimi trofik düzeye göre inceleniyor.
    I. Üreticilerin toksik madde birikiminin herbivorlardan daha az olması beklenir.
    II. Karnivorların toksik madde birikiminin omnivorlardan daha az olması beklenir.
    III. Herbivorların toksik madde birikiminin alglerden daha fazla olması beklenir.
    yorumlarından hangileri yapılamaz?
    """
    sonuc = coz(soru, SIKLAR)
    assert sonuc is not None
    assert sonuc.cevap == "B"


def test_es_anlamli_kategoriler_desteklenir():
    soru = TEMIZ_SORU.replace("Omnivorların", "Hepçillerin").replace(
        "karnivorlardakinden", "etçillerdekinden"
    )
    sonuc = coz(soru, SIKLAR)
    assert sonuc is not None
    assert sonuc.cevap == "E"


def test_uc_ifadeli_kume_tek_sikka_eslenir():
    soru = """
    Toksik madde birikimi trofik düzeye göre inceleniyor.
    I. Alglerin toksik madde birikiminin herbivorlardan daha fazla olması beklenir.
    II. Omurgasızların toksik madde birikiminin omnivorlardan daha fazla olması beklenir.
    III. Omnivorların toksik madde birikiminin karnivorlardan daha fazla olması beklenir.
    yorumlarından hangileri yapılamaz?
    """
    secenekler = {
        "A": "Yalnız I",
        "B": "I ve II",
        "C": "I ve III",
        "D": "II ve III",
        "E": "I, II ve III",
    }
    sonuc = coz(soru, secenekler)
    assert sonuc is not None
    assert sonuc.cevap == "E"


def test_gercek_q2_ocr_metni_e_ama_zorunlu_inceleme():
    sonuc = coz(GERCEK_OCR_SORUSU, {**SIKLAR, "A": "Yalnız l"})
    assert sonuc is not None
    assert sonuc.cevap == "E"
    assert sonuc.guven == pytest.approx(0.72)
    assert sonuc.incele
    assert any("OCR" in uyari for uyari in sonuc.uyarilar)


@pytest.mark.parametrize(
    ("eski", "yeni"),
    [
        ("toksik", "yararlı"),
        ("birikiminin", "miktarının"),
        ("hangileri yapılamaz", "hangisi doğrudur"),
        ("daha fazla", "çok"),
        ("daha fazla", "daha hızlı"),
        ("herbivorlardakinden", "canlılardakinden"),
        ("daha fazla olması beklenir", "daha fazla ve daha az olması beklenir"),
        ("daha fazla olması beklenir", "daha fazla olması beklenmez"),
    ],
)
def test_guvenlik_kapilari_belirsiz_soruda_susar(eski, yeni):
    assert coz(TEMIZ_SORU.replace(eski, yeni), SIKLAR) is None


def test_iki_ifadeli_soruda_susar():
    soru = TEMIZ_SORU.replace(
        "III. Herbivorların toksik madde birikiminin karnivorlardakinden "
        "daha fazla olması beklenir.",
        "",
    )
    assert coz(soru, SIKLAR) is None


def test_bir_ifadede_uc_kategori_gecerse_susar():
    soru = TEMIZ_SORU.replace(
        "Omnivorların toksik",
        "Omnivor ve karnivorların toksik",
    )
    assert coz(soru, SIKLAR) is None


@pytest.mark.parametrize(
    "secenekler",
    [
        {"A": "Yalnız I", "B": "Yalnız II"},
        {**SIKLAR, "E": "II veya III"},
        {**SIKLAR, "D": "II ve III"},
        {**SIKLAR, "E": "II ve II"},
        {**SIKLAR, "F": "I, II ve III"},
    ],
)
def test_sik_kumesi_tek_harfe_guvenle_baglanamazsa_susar(secenekler):
    assert coz(TEMIZ_SORU, secenekler) is None


def test_cozucu_modelden_once_araci_kullanir(tmp_path):
    motor = SayacliMotor()
    sonuc = _cozucu(tmp_path, motor).coz(TEMIZ_SORU, secenekler=SIKLAR, kaydet=False)
    assert sonuc.cevap == "E"
    assert sonuc.uretim_yontemi == "biyobirikim_araci"
    assert sonuc.konu == "ekoloji"
    assert sonuc.cozum_turu == "siniflandirma"
    assert motor.cagrilar == []


def test_arac_model_guven_cezalarindan_muaftir(tmp_path):
    motor = SayacliMotor()
    sonuc = _cozucu(
        tmp_path,
        motor,
        kanitsiz_ceza=0.9,
        tur_guvenilirligi={"siniflandirma": 0.1},
        inceleme_esigi=0.7,
    ).coz(TEMIZ_SORU, secenekler=SIKLAR, kaydet=False)
    assert sonuc.guven == pytest.approx(0.95)
    assert not sonuc.incele


def test_akis_yolu_da_modelden_once_araci_kullanir(tmp_path):
    motor = SayacliMotor()
    olaylar = list(
        _cozucu(tmp_path, motor).coz_akis(
            TEMIZ_SORU, secenekler=SIKLAR, kaydet=False
        )
    )
    assert olaylar[-1][0] == "bitti"
    assert olaylar[-1][1].uretim_yontemi == "biyobirikim_araci"
    assert any("toksik birikim" in str(deger) for tur, deger in olaylar if tur == "durum")
    assert motor.cagrilar == []


def test_desteklenmeyen_soru_mevcut_model_yoluna_duser(tmp_path):
    motor = SayacliMotor()
    sonuc = _cozucu(tmp_path, motor).coz(
        "Fotosentezde oksijenin kaynağı nedir?",
        secenekler={"A": "Su", "B": "Karbondioksit", "C": "Glikoz"},
        kaydet=False,
    )
    assert sonuc.uretim_yontemi == "model"
    assert len(motor.cagrilar) == 1


def test_motorsuz_da_deterministik_arac_calisir(tmp_path):
    sonuc = _cozucu(tmp_path, None).coz(TEMIZ_SORU, secenekler=SIKLAR, kaydet=False)
    assert sonuc.cevap == "E"
    assert sonuc.uretim_yontemi == "biyobirikim_araci"
