"""Kalıtım çözücüsünün `Cozucu` akışına bağlanması — uçtan uca, sahte motorla.

Buradaki testlerin çoğu bir REGRESYON AĞI: zincirin herhangi bir halkası
koptuğunda çözücünün sessizce çekilip mevcut model yolunun çalışması ve
kalibrasyonun deterministik cevabı boğmaması gerekiyor.
"""

from __future__ import annotations

import json

import pytest

from biyo_cozucu.cozucu import Ayarlar, Cozucu
from biyo_cozucu.depo import Depo
from biyo_cozucu.hafiza.indeks import OrnekIndeksi
from biyo_cozucu.motor.temel import MotorHatasi

# Gerçek soru: AaBbMmDD → aBmD gameti = (1/2)³ × 1 = 1/8
SORU = (
    "AaBbMmDD genotipindeki bir bireyin, aBmD genotipindeki bir gamet "
    "oluşturma olasılığı kaçtır? (Genler bağımsız.)"
)
SIKLAR = {"A": "16\n1", "B": "0", "C": "4\n1", "D": "2\n1", "E": "8\n1"}

GECERLI_TANIM = {
    "lokuslar": [
        {"ad": "a", "aleller": ["A", "a"], "baskinlik": "tam", "konum": "otozom"},
        {"ad": "b", "aleller": ["B", "b"], "baskinlik": "tam", "konum": "otozom"},
        {"ad": "m", "aleller": ["M", "m"], "baskinlik": "tam", "konum": "otozom"},
        {"ad": "d", "aleller": ["D", "d"], "baskinlik": "tam", "konum": "otozom"},
    ],
    "ebeveynler": [
        {"etiket": "birey", "genotip": {"a": "Aa", "b": "Bb", "m": "Mm", "d": "DD"},
         "cinsiyet": ""}
    ],
    "bagli_gruplar": [],
    "krossing_orani": None,
    "istek": {
        "tur": "gamet_olasiligi",
        "hedef": {"a": "a", "b": "B", "m": "m", "d": "D"},
        "cocuk_sirasi": [], "sinir": "", "kosul": {},
    },
}


class BetiklıMotor:
    """Sırayla verilen yanıtları döndürür; çağrıları sayar."""

    ad = "betikli"

    def __init__(self, yanitlar: list[str | Exception]):
        self.yanitlar = list(yanitlar)
        self.cagrilar: list[list[dict]] = []

    def uret(self, mesajlar, *, sicaklik=0.0, azami_token=0) -> str:
        self.cagrilar.append(mesajlar)
        if not self.yanitlar:
            return json.dumps({"adimlar": ["yedek"], "cevap": "A", "guven": 0.9})
        yanit = self.yanitlar.pop(0)
        if isinstance(yanit, Exception):
            raise yanit
        return yanit


@pytest.fixture
def kok(tmp_path):
    return tmp_path


def _cozucu(kok, motor, **ayar) -> Cozucu:
    return Cozucu(
        depo=Depo(kok / "biyo.db"),
        indeks=OrnekIndeksi.kur([], None),
        motor=motor,
        ayarlar=Ayarlar(deneme_sayisi=1, onbellek_aktif=False, **ayar),
    )


def test_kalitim_yolu_dogru_cevabi_bulur(kok):
    motor = BetiklıMotor([json.dumps(GECERLI_TANIM, ensure_ascii=False)])
    cozum = _cozucu(kok, motor).coz(SORU, secenekler=SIKLAR, kaydet=False)
    assert cozum.cevap == "E"                      # "8\n1" = 1/8
    assert cozum.uretim_yontemi == "kalitim_araci"
    assert len(motor.cagrilar) == 1                # yalnız çıkarım çağrısı


def test_kalibrasyon_deterministik_cevabi_bogmaz(kok):
    """Tür çarpanı 0,442 uygulanırsa 0,95 güven 0,42'ye iner ve incelemeye düşer.

    Bu testin varlık sebebi: muafiyet yazılmazsa kazanılan HER doğru cevap
    inceleme eşiğinin (0,70) altında kalır — doğruluk artar, kapsama çöker,
    kullanıcı hiçbir fark görmez.
    """
    motor = BetiklıMotor([json.dumps(GECERLI_TANIM, ensure_ascii=False)])
    cozucu = _cozucu(
        kok, motor,
        inceleme_esigi=0.70,
        tur_guvenilirligi={"kalitim_hesabi": 0.442},
    )
    cozum = cozucu.coz(SORU, secenekler=SIKLAR, kaydet=False)
    assert cozum.guven > 0.70
    assert not cozum.incele


def test_kanitsiz_ceza_arac_yolunda_uygulanmaz(kok):
    motor = BetiklıMotor([json.dumps(GECERLI_TANIM, ensure_ascii=False)])
    cozum = _cozucu(kok, motor, kanitsiz_ceza=0.9).coz(
        SORU, secenekler=SIKLAR, kaydet=False
    )
    assert cozum.guven > 0.70
    assert not any("referans örnek yoktu" in u for u in cozum.uyarilar)


# --- geri çekilme zinciri ---


@pytest.mark.parametrize(
    "yanit",
    [
        "bu json değil",                                   # ayrıştırılamaz
        json.dumps({"lokuslar": []}),                      # boş şema
        json.dumps({**GECERLI_TANIM, "istek": {"tur": "uydurma"}}),  # geçersiz tür
        json.dumps({**GECERLI_TANIM,                       # tanımsız alel
                    "ebeveynler": [{"genotip": {"a": "Zz"}}]}),
    ],
)
def test_cikarim_basarisizsa_model_yoluna_duser(kok, yanit):
    model_cozumu = json.dumps(
        {"adimlar": ["model çözdü"], "cevap": "C", "guven": 0.9}, ensure_ascii=False
    )
    motor = BetiklıMotor([yanit, model_cozumu])
    cozum = _cozucu(kok, motor).coz(SORU, secenekler=SIKLAR, kaydet=False)
    assert cozum.uretim_yontemi != "kalitim_araci"
    assert len(motor.cagrilar) == 2                 # çıkarım + model çözümü


def test_motor_hatasinda_model_yoluna_duser(kok):
    model_cozumu = json.dumps({"adimlar": ["m"], "cevap": "C", "guven": 0.9})
    motor = BetiklıMotor([MotorHatasi("çöktü"), model_cozumu])
    cozum = _cozucu(kok, motor).coz(SORU, secenekler=SIKLAR, kaydet=False)
    assert cozum.uretim_yontemi != "kalitim_araci"


def test_sonuc_sikla_eslesmezse_model_yoluna_duser(kok):
    """Hesap doğru ama şıklarda karşılığı yok → çözücü konuşmamalı."""
    baska_siklar = {"A": "3\n1", "B": "5\n1", "C": "7\n1"}
    model_cozumu = json.dumps({"adimlar": ["m"], "cevap": "A", "guven": 0.9})
    motor = BetiklıMotor([json.dumps(GECERLI_TANIM), model_cozumu])
    cozum = _cozucu(kok, motor).coz(SORU, secenekler=baska_siklar, kaydet=False)
    assert cozum.uretim_yontemi != "kalitim_araci"


def test_siksiz_soruda_arac_denenmez(kok):
    """Çözücü serbest cevap üretmiyor; şık yoksa hiç çağrılmamalı."""
    model_cozumu = json.dumps({"adimlar": ["m"], "cevap": "1/8", "guven": 0.9})
    motor = BetiklıMotor([model_cozumu])
    cozum = _cozucu(kok, motor).coz(SORU, kaydet=False)
    assert cozum.uretim_yontemi != "kalitim_araci"
    assert len(motor.cagrilar) == 1                 # çıkarım çağrısı YOK


def test_kalitim_disi_soruda_arac_denenmez(kok):
    model_cozumu = json.dumps({"adimlar": ["m"], "cevap": "B", "guven": 0.9})
    motor = BetiklıMotor([model_cozumu])
    cozucu = _cozucu(kok, motor)
    cozum = cozucu.coz(
        "Fotosentezde ışığa bağımlı tepkimeler nerede gerçekleşir?",
        secenekler={"A": "Stroma", "B": "Tilakoit"}, kaydet=False,
    )
    assert cozum.uretim_yontemi != "kalitim_araci"
    assert len(motor.cagrilar) == 1


def test_ayar_kapaliyken_arac_denenmez(kok):
    model_cozumu = json.dumps({"adimlar": ["m"], "cevap": "A", "guven": 0.9})
    motor = BetiklıMotor([model_cozumu])
    cozum = _cozucu(kok, motor, kalitim_araci=False).coz(
        SORU, secenekler=SIKLAR, kaydet=False
    )
    assert cozum.uretim_yontemi != "kalitim_araci"
    assert len(motor.cagrilar) == 1


def test_motorsuz_cozucude_arac_denenmez(kok):
    cozum = Cozucu(
        depo=Depo(kok / "biyo.db"),
        indeks=OrnekIndeksi.kur([], None),
        motor=None,
        ayarlar=Ayarlar(onbellek_aktif=False),
    ).coz(SORU, secenekler=SIKLAR, kaydet=False)
    assert cozum.uretim_yontemi != "kalitim_araci"


# --- akış yolu ---


def test_akis_yolu_ayni_cevabi_verir(kok):
    """Akış yalnız gösterim katmanı; aynı soru arayüzden farklı cevaplanamaz."""
    motor = BetiklıMotor([json.dumps(GECERLI_TANIM, ensure_ascii=False)])
    olaylar = list(
        _cozucu(kok, motor).coz_akis(SORU, secenekler=SIKLAR, kaydet=False)
    )
    tur, cozum = olaylar[-1]
    assert tur == "bitti"
    assert cozum.cevap == "E"
    assert cozum.uretim_yontemi == "kalitim_araci"
    assert any(o[1] == "çaprazlama hesaplanıyor" for o in olaylar if o[0] == "durum")


def test_akis_yolunda_cikarim_basarisizsa_model_calisir(kok):
    """Regresyon: fazladan bir `return` burada soruyu hiç çözmeden bitiriyordu."""
    model_cozumu = json.dumps({"adimlar": ["m"], "cevap": "C", "guven": 0.9})
    motor = BetiklıMotor(["bozuk json", model_cozumu])
    olaylar = list(
        _cozucu(kok, motor).coz_akis(SORU, secenekler=SIKLAR, kaydet=False)
    )
    tur, cozum = olaylar[-1]
    assert tur == "bitti"
    assert cozum.cevap == "C"


# --- çözüm içeriği ---


def test_adimlar_uretilir(kok):
    """Adımsız çözüm `cozum_puanla`da adım örtüşmesini sıfır sayardı."""
    motor = BetiklıMotor([json.dumps(GECERLI_TANIM, ensure_ascii=False)])
    cozum = _cozucu(kok, motor).coz(SORU, secenekler=SIKLAR, kaydet=False)
    assert len(cozum.adimlar) >= 2
    assert len(cozum.adimlar) <= 6          # istemdeki sınırla aynı
    assert any("gamet" in a.casefold() for a in cozum.adimlar)
