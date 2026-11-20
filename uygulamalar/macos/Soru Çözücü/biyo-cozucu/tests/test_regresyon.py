"""Çapraz incelemede bulunan gerçek hataların regresyon testleri.

Her test, düzeltilmeden önce başarısız olan somut bir senaryoyu yeniden üretir.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
import types
from pathlib import Path

import numpy as np
import pytest

from biyo_cozucu.cozucu import Ayarlar, Cozucu
from biyo_cozucu.degerlendirme import kor_kosu
from biyo_cozucu.hafiza.indeks import ANLAMSAL_TABAN, OrnekIndeksi
from biyo_cozucu.modeller import Ornek
from biyo_cozucu.motor.temel import SahteMotor, dusunceyi_ayikla
from biyo_cozucu.veri.disa_aktar import bol, egitim_verisi_yaz


def _yanit(adimlar, cevap, guven=0.9, **ek) -> str:
    veri = {"adimlar": adimlar, "cevap": cevap, "guven": guven, "uyari": ""}
    veri.update(ek)
    return json.dumps(veri, ensure_ascii=False)


# --- 1. Paketleme: veri paketi git'te olmalı ---


def test_veri_paketi_surum_kontrolunde():
    """`.gitignore`'daki köksüz `veri/` kuralı `biyo_cozucu/veri/` paketini gizliyordu."""
    kok = Path(__file__).resolve().parent.parent
    if not (kok / ".git").is_dir():
        pytest.skip("git deposu değil")
    izlenen = subprocess.run(
        ["git", "ls-files", "biyo_cozucu/veri"],  # noqa: S607
        cwd=kok, capture_output=True, text=True, check=True,
    ).stdout.split()
    assert "biyo_cozucu/veri/disa_aktar.py" in izlenen
    assert "biyo_cozucu/veri/acik_setler.py" in izlenen


# --- 2. Eğitim verisi sızıntısı ---


def test_egitim_kayitlari_dogrulama_ve_test_cozumlerini_sizdirmaz(tmp_path, sahte_gomlemci):
    """Kanıt havuzu tüm örneklerden kurulunca test çözümü train.jsonl'e giriyordu."""
    ornekler = [
        Ornek(id=i, soru=f"Mitoz bölünme evresi {i} nasıl gerçekleşir?",
              cozum=f"Bu evrede {i} numaralı olay olur. Kromozomlar hareket eder.",
              cevap=f"cevap {i}", konu="hücre bölünmesi")
        for i in range(1, 41)
    ]
    _egitim, dogrulama, test = bol(ornekler)
    assert dogrulama and test, "bölme anlamlı kümeler üretmeli"

    egitim_verisi_yaz(ornekler, tmp_path / "v1", kanit_sayisi=3, gomlemci=sahte_gomlemci)
    train_metni = (tmp_path / "v1" / "train.jsonl").read_text(encoding="utf-8")
    valid_metni = (tmp_path / "v1" / "valid.jsonl").read_text(encoding="utf-8")

    for ornek in (*dogrulama, *test):
        assert ornek.soru not in train_metni, "eğitim dışı soru train'e sızdı"
        assert ornek.cozum not in train_metni, "eğitim dışı ÇÖZÜM train'e sızdı"
        # Doğrulama kaydının kendi hedefi elbette valid'te; sızıntı testi
        # yalnız kanıt bölümü için — test örneği hiçbir yerde görünmemeli.
    for ornek in test:
        assert ornek.cozum not in valid_metni


# --- 3. Kör değerlendirmede önbellek sızıntısı ---


def test_kor_kosuda_onbellek_atlanir(dolu_depo, ornekler, sahte_gomlemci):
    """Test sorusu daha önce çözülmüşse önbellek cevabı doğrudan döndürüyordu."""
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    hedef = ornekler[3]

    # Önce aynı soruyu normal akışta çöz → önbelleğe girer.
    hazirlik = Cozucu(
        depo=dolu_depo, indeks=indeks,
        motor=SahteMotor(_yanit(["önbellekten"], "B")),
        gomlemci=sahte_gomlemci,
        # Bu test birebir yerel arşivi değil, model önbelleğinin kör koşuda
        # atlanmasını ölçüyor; hazırlık çözümünü özellikle model yolundan geçir.
        ayarlar=Ayarlar(tam_referans_aktif=False),
    )
    hazirlik.coz(hedef.soru, secenekler=hedef.secenekler, cevap_turu=hedef.cevap_turu)
    assert dolu_depo.ozet()["onbellek"] >= 1

    # Kör koşu motoru gerçekten çağırmalı, önbelleği kullanmamalı.
    motor = SahteMotor(_yanit(["kör koşu"], "A"))
    kor = Cozucu(depo=dolu_depo, indeks=indeks, motor=motor, gomlemci=sahte_gomlemci)
    ozet = kor_kosu(kor, [hedef])

    assert motor.cagrilar, "kör koşuda model çağrılmalı"
    assert ozet.sonuclar[0].uretim_yontemi == "model"
    assert ozet.sonuclar[0].uretilen_cevap == "A"


# --- 4. Önbellek kimliği şıkları içermeli ---


def test_onbellek_farkli_siklarda_eski_cevabi_dondurmez(depo, sahte_gomlemci):
    """Anahtar yalnız soru gövdesiyken şıklar değişince eski harf dönüyordu."""
    indeks = OrnekIndeksi.kur([], sahte_gomlemci)
    motor = SahteMotor([_yanit(["ilk"], "B"), _yanit(["ikinci"], "A")])
    cozucu = Cozucu(depo=depo, indeks=indeks, motor=motor, gomlemci=sahte_gomlemci)

    soru = "Aşağıdakilerden hangisi doğrudur?"
    ilk = cozucu.coz(soru, secenekler={"A": "yanlış", "B": "doğru"})
    assert ilk.cevap == "B"

    ikinci = cozucu.coz(soru, secenekler={"A": "doğru", "B": "yanlış"})
    assert ikinci.uretim_yontemi == "model", "şıklar değişti, önbellek kullanılmamalı"
    assert ikinci.cevap == "A"


def test_onbellek_ayni_soru_ayni_siklarda_calisir(depo, sahte_gomlemci):
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci),
        motor=SahteMotor(_yanit(["a"], "B")), gomlemci=sahte_gomlemci,
    )
    siklar = {"A": "bir", "B": "iki"}
    cozucu.coz("Soru?", secenekler=siklar)
    cagri = len(cozucu.motor.cagrilar)
    ikinci = cozucu.coz("Soru?", secenekler=dict(siklar))
    assert ikinci.uretim_yontemi == "onbellek"
    assert len(cozucu.motor.cagrilar) == cagri


def test_onbellekten_donen_cozum_guncel_soruya_baglanir(depo, sahte_gomlemci):
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci),
        motor=SahteMotor(_yanit(["a"], "B")), gomlemci=sahte_gomlemci,
    )
    cozucu.coz("Soru?", secenekler={"A": "bir", "B": "iki"})
    ikinci = cozucu.coz("  soru?  ", secenekler={"A": "bir", "B": "iki"})
    assert ikinci.uretim_yontemi == "onbellek"
    assert ikinci.soru == "soru?"
    assert ikinci.secenekler == {"A": "bir", "B": "iki"}


def test_yakin_eslesme_onbellegi_incelemeye_duser(depo, sahte_gomlemci):
    """Yakın eşleşmede yeni soru + eski çözüm birleşiyor; onaya hazır sayılmamalı.

    Aksi halde öğretmen panelinde "Onayla" denince bu karma kayıt kalıcı
    referans örneğe dönüşüp hafızayı kirletiyordu.
    """
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci),
        motor=SahteMotor([_yanit(["ilk"], "A")]), gomlemci=sahte_gomlemci,
        ayarlar=Ayarlar(onbellek_esigi=0.5),  # sahte gömlemciyle yakın eşleşmeyi zorla
    )
    siklar = {"A": "mitoz", "B": "mayoz"}
    ilk = cozucu.coz("Aşağıdakilerden hangisi doğrudur?", secenekler=siklar)
    assert not ilk.incele

    ikinci = cozucu.coz("Aşağıdakilerden hangisi doğrudur ve neden?", secenekler=dict(siklar))
    if ikinci.uretim_yontemi == "onbellek":
        assert ikinci.incele, "farklı soruya ait çözüm incelemeye düşmeli"
        assert any("doğrulayın" in u for u in ikinci.uyarilar)


# --- 5. Onaylanan çoktan seçmeli çözüm şıkları korumalı ---


def test_cozum_secenekleri_saklar_ve_gidis_donusunde_korur(depo, sahte_gomlemci):
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci),
        motor=SahteMotor(_yanit(["a"], "B")), gomlemci=sahte_gomlemci,
    )
    cozum = cozucu.coz("Soru?", secenekler={"A": "bir", "B": "iki"})
    assert cozum.secenekler == {"A": "bir", "B": "iki"}
    geri, _satir = depo.cozum(cozum.id)
    assert geri.secenekler == {"A": "bir", "B": "iki"}
    assert "A) bir" in geri.soru_metni()


# --- 6. Anlamsal taban: alakasız aday kanıt sayılmamalı ---


class _KarsitGomlemci:
    """Her sorguya tüm belgelerden uzak (negatif kosinüs) bir vektör döndürür."""

    model_adi = "karsit"

    def gom(self, metinler: list[str], *, sorgu: bool = False) -> np.ndarray:
        taban = np.zeros((len(metinler), 4), dtype=np.float32)
        taban[:, 0] = -1.0 if sorgu else 1.0
        return taban


def test_alakasiz_anlamsal_adaylar_kanit_sayilmaz(ornekler):
    """RRF sıra tabanlı olduğu için süzülmeyen adaylar eşiği hep geçiyordu."""
    gomlemci = _KarsitGomlemci()
    indeks = OrnekIndeksi.kur(ornekler, gomlemci)
    assert indeks.anlamsal_hazir

    sonuc = indeks.ara("zzz qqq www", gomlemci, k=5)
    assert sonuc == [], "ne sözcüksel ne anlamsal eşleşme varken aday dönmemeli"


def test_anlamsal_taban_gercek_eslesmeyi_elemez(ornekler, sahte_gomlemci):
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    sonuc = indeks.ara("Aa genotipli bireylerin çaprazlanması", sahte_gomlemci, k=3)
    assert sonuc, f"gerçek eşleşme ANLAMSAL_TABAN={ANLAMSAL_TABAN} ile elenmemeli"


def test_kanitsiz_soruda_ceza_uygulanir(depo, ornekler):
    gomlemci = _KarsitGomlemci()
    cozucu = Cozucu(
        depo=depo,
        indeks=OrnekIndeksi.kur(ornekler, gomlemci),
        motor=SahteMotor(_yanit(["a"], "B", guven=0.9)),
        gomlemci=gomlemci,
        ayarlar=Ayarlar(kanitsiz_ceza=0.25),
    )
    cozum = cozucu.coz("zzz qqq www")
    assert cozum.kanitlar == []
    assert cozum.guven == pytest.approx(0.65)


# --- 11. adimlar dize gelirse harf harf bölünmemeli ---


def test_adimlar_dize_gelirse_satirlara_bolunur(depo, sahte_gomlemci):
    ham = json.dumps(
        {"adimlar": "İlk adım budur.\nİkinci adım budur.", "cevap": "B", "guven": 0.9},
        ensure_ascii=False,
    )
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci),
        motor=SahteMotor(ham), gomlemci=sahte_gomlemci,
    )
    cozum = cozucu.coz("Soru?")
    assert cozum.adimlar == ["İlk adım budur.", "İkinci adım budur."]


def test_adimlar_beklenmeyen_tipte_bos_kalir(depo, sahte_gomlemci):
    ham = json.dumps({"adimlar": {"a": 1}, "cevap": "B", "guven": 0.9})
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci),
        motor=SahteMotor(ham), gomlemci=sahte_gomlemci,
    )
    cozum = cozucu.coz("Soru?")
    assert cozum.adimlar == []
    assert cozum.incele


# --- Düşünce ayıklama: yalnız kapanış etiketi ---


def test_yalniz_kapanis_etiketi_ayiklanir():
    """Qwen3.5 şablonu istemi `<think>` ile bitirir; çıktıda yalnız `</think>` olur."""
    ham = 'Uzun uzun düşünüyorum...\n</think>\n\n{"cevap":"C"}'
    dusunce, govde = dusunceyi_ayikla(ham)
    assert "Uzun uzun düşünüyorum" in dusunce
    assert govde == '{"cevap":"C"}'


def test_yalniz_dusunce_ureten_yanit_sahte_adim_yaratmaz(depo, sahte_gomlemci):
    """Token sınırında kesilen düşünce, adım diye kullanıcıya sunulmamalı."""
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci),
        motor=SahteMotor("Thinking Process:\n1. Analyze the request\n2. Recall"),
        gomlemci=sahte_gomlemci,
    )
    cozum = cozucu.coz("Soru?")
    assert cozum.incele
    assert cozum.guven <= 0.2


def test_yarim_jsonda_kesik_adim_gosterilmez(depo, sahte_gomlemci):
    """Yarım JSON'dan yalnız TAMAMLANMIŞ adımlar kurtarılır.

    Eskiden yanıtın tamamı atılıyordu; 125 soruluk ölçümde bu, soruların
    %23'ünde hem muhakemenin hem cevabın çöpe gitmesi demekti. Artık kapanmış
    dizeler alınıyor — ama kesik olan ("ikinci ad") hâlâ alınmıyor, çünkü
    yarım cümleyi adım diye göstermek kullanıcıya çöp sunmaktır.
    """
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci),
        motor=SahteMotor('{"adimlar": ["ilk adım", "ikinci ad'),
        gomlemci=sahte_gomlemci,
    )
    cozum = cozucu.coz("Soru?")
    assert cozum.adimlar == ["ilk adım"]
    assert not any("ikinci ad" in a for a in cozum.adimlar)
    assert any("şemasını bozdu" in u for u in cozum.uyarilar)
    assert cozum.guven <= 0.5


# --- Sahte gömlemci gerçekten devreye girmeli ---


def test_webapp_sahte_gomlemciyi_gercekten_kullanir(tmp_path, sahte_gomlemci, monkeypatch):
    """`durum.py` adı import anında bağlarsa monkeypatch etkisiz kalıyordu.

    Sonuç sessizdi: testler sahte gömlemci sandıkları hâlde 2 GB'lık gerçek
    modeli yükleyip test başına ~11 sn harcıyordu ve modelsiz bir makinede
    kırılacaktı.
    """
    pytest.importorskip("fastapi")
    from biyo_cozucu import gomme as gomme_modulu
    from biyo_cozucu.webapp.durum import Uygulama

    cagrildi: list[str] = []

    def sahte_yukleyici(*a, **k):
        cagrildi.append("sahte")
        return sahte_gomlemci

    monkeypatch.setattr(gomme_modulu, "gomlemci_yukle", sahte_yukleyici)
    uygulama = Uygulama(kok=tmp_path, motor_turu="yok")
    assert uygulama.gomlemci is sahte_gomlemci
    assert cagrildi == ["sahte"], "yerine konan yükleyici çağrılmalı"


def test_cozucu_kur_sahte_gomlemciyi_gercekten_kullanir(tmp_path, sahte_gomlemci, monkeypatch):
    from biyo_cozucu import gomme as gomme_modulu

    monkeypatch.setattr(gomme_modulu, "gomlemci_yukle", lambda *a, **k: sahte_gomlemci)
    cozucu = Cozucu.kur(tmp_path, motor=None)
    assert cozucu.gomlemci is sahte_gomlemci


# --- Faz 1 çapraz incelemesinde bulunan hatalar ---


def test_arama_joker_karakterlerini_kacisliyor(depo):
    """Kullanıcının yazdığı % ve _ SQL joker'i olmamalı; süzgeç boşa düşüyordu."""
    depo.ornek_ekle(Ornek(soru="Mitoz nedir?", cozum="ç"))
    depo.ornek_ekle(Ornek(soru="Fotosentez nedir?", cozum="ç"))
    depo.ornek_ekle(Ornek(soru="Solunum %50 verimle olur mu?", cozum="ç"))

    assert depo.ornek_say(ara="%") == 1, "% her kaydı getirmemeli"
    assert depo.ornek_say(ara="_") == 0
    assert depo.ornek_say(ara="m_toz") == 0, "_ tek karakter joker'i olmamalı"
    assert depo.ornek_say(ara="mitoz") == 1


def test_guvenli_geri_ters_egik_cizgiyi_reddeder():
    """`/\\kotu.example.com` tarayıcıda `//` gibi çözülüp site dışına çıkarıyordu."""
    pytest.importorskip("fastapi")
    from biyo_cozucu.webapp.yardimcilar import guvenli_geri

    assert guvenli_geri("/ornekler") == "/ornekler"
    for kotu in ("//kotu.example.com", "/\\kotu.example.com",
                 "https://kotu.example.com", "", "   ",
                 "/iyi\r\nSet-Cookie: x=1", "javascript:alert(1)"):
        assert guvenli_geri(kotu, "/pano") == "/pano", f"{kotu!r} kabul edildi"


def test_kanit_skoru_benzerligi_asmaz(sahte_gomlemci):
    """`skor` arayüzde 'benzerlik' diye sunuluyor; konu bonusu 1'i aştırıyordu."""
    from biyo_cozucu.hafiza.getirme import benzer_ornekler

    ornekler = [
        Ornek(id=1, soru="Mitoz bölünme nasıl olur?", cozum="ç",
              konu="hücre bölünmesi", cozum_turu="mekanizma_aciklama"),
        Ornek(id=2, soru="Mitoz evreleri nelerdir?", cozum="ç",
              konu="hücre bölünmesi", cozum_turu="mekanizma_aciklama"),
    ]
    indeks = OrnekIndeksi.kur(ornekler, sahte_gomlemci)
    kanitlar = benzer_ornekler(
        indeks, "Mitoz bölünme sonucu ne olur?", gomlemci=sahte_gomlemci, k=2,
        konu="hücre bölünmesi", cozum_turu="mekanizma_aciklama",
    )
    assert kanitlar
    for kanit in kanitlar:
        assert 0.0 <= kanit.skor <= 1.0, f"benzerlik aralık dışı: {kanit.skor}"


def test_mlx_akisi_kilidi_tuketici_gitse_de_birakir(monkeypatch):
    """İstemci akışı yarıda keserse üretim kilidi sızıyor ve sonraki istek asılıyordu."""
    from biyo_cozucu.motor import mlx_motor

    sahte_model, sahte_tokenizer = object(), object()
    monkeypatch.setattr(mlx_motor, "_yukle", lambda *a, **k: (sahte_model, sahte_tokenizer))

    class _Adim:
        def __init__(self, text):
            self.text = text

    sahte_mlx = types.ModuleType("mlx_lm")
    sahte_mlx.stream_generate = lambda *a, **k: (_Adim(f"p{i}") for i in range(50))
    sahte_ornekleyici = types.ModuleType("mlx_lm.sample_utils")
    sahte_ornekleyici.make_sampler = lambda **k: object()
    monkeypatch.setitem(sys.modules, "mlx_lm", sahte_mlx)
    monkeypatch.setitem(sys.modules, "mlx_lm.sample_utils", sahte_ornekleyici)

    motor = mlx_motor.MlxMotor(model_yolu="sahte")
    monkeypatch.setattr(motor, "_istem_kur", lambda t, m: "istem")

    akis = motor.uret_akis([{"role": "user", "content": "x"}])
    assert next(akis) == "p0"

    # Tüketici akışı terk ediyor AMA generator hâlâ referanslı: Starlette
    # istemci kopunca üreticiyi close() etmiyor ve nesne bir başvuru
    # döngüsünde kaldığından sayaçla da toplanmıyor. Bu yüzden bilinçli
    # olarak ne `del` ne `gc.collect()` çağırıyoruz — kilidi doğrudan
    # `yield` sınırları boyunca tutan eski tasarım burada asılı kalırdı.
    assert akis is not None

    # İşçi iş parçacığı kendi başına bitip kilidi bırakmalı.
    son = time.time() + 5
    while mlx_motor._uretim_kilidi.locked() and time.time() < son:
        time.sleep(0.02)
    assert not mlx_motor._uretim_kilidi.locked(), "üretim kilidi sızdı"

    # Kilit gerçekten yeniden alınabiliyor olmalı.
    assert mlx_motor._uretim_kilidi.acquire(timeout=2)
    mlx_motor._uretim_kilidi.release()
