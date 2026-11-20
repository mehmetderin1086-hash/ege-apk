"""Ölçüm kaydı, dondurulmuş dilim ve fark raporu testleri.

Hepsi çevrimdışı: gerçek model gerekmiyor. Ölçüm ALTYAPISININ doğruluğu,
ölçümün kendisinden bağımsız olarak sınanabilmeli — aksi halde kapının
kendisi bozukken yeşil yanabilir.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from biyo_cozucu.degerlendirme import OrnekSonucu, ozetle
from biyo_cozucu.metin import imza as metin_imzasi
from biyo_cozucu.modeller import Ornek
from biyo_cozucu.olcum import (
    ASGARI_DEGISEN,
    Dilim,
    OlcumKaydi,
    farkla,
    kayitlari_listele,
    son_kayit,
)


def _sonuc(soru: str, dogru: bool, *, tur="mekanizma_aciklama", guven=0.8, yontem="model"):
    return OrnekSonucu(
        ornek_id=None,
        soru=soru,
        beklenen_cevap="C",
        uretilen_cevap="C" if dogru else "A",
        cevap_dogru=dogru,
        adim_ortusmesi=0.5,
        guven=guven,
        incele=guven < 0.7,
        cozum_turu=tur,
        uretim_yontemi=yontem,
    )


def _kayit(etiket: str, sonuclar, dilim: Dilim, *, zaman: str | None = None) -> OlcumKaydi:
    kayit = OlcumKaydi.ozetten(
        ozetle(sonuclar), etiket=etiket, model="sahte", dilim=dilim
    )
    if zaman:
        kayit.zaman = zaman
    return kayit


@pytest.fixture
def dilim() -> Dilim:
    ornekler = [Ornek(soru=f"Soru {i}", cozum="c", cevap="C") for i in range(5)]
    return Dilim.ornekelerden(ornekler, "test-dilimi")


# --- Dilim ---


def test_dilim_imzasi_sirali_bagimsiz():
    a = Dilim(ad="x", imzalar=("b", "a", "c"))
    b = Dilim(ad="x", imzalar=("c", "b", "a"))
    assert a.imza() == b.imza()


def test_dilim_imzasi_icerik_degisince_degisir(dilim):
    baska = Dilim(ad=dilim.ad, imzalar=(*dilim.imzalar, "yeni"))
    assert baska.imza() != dilim.imza()


def test_dilim_yaz_yukle(tmp_path, dilim):
    yol = dilim.yaz(tmp_path)
    geri = Dilim.yukle(yol)
    assert geri.imzalar == dilim.imzalar
    assert geri.imza() == dilim.imza()


def test_dilim_cozumle_eksigi_bildirir(dilim):
    havuz = [Ornek(soru="Soru 0", cozum="c"), Ornek(soru="Soru 2", cozum="c")]
    bulunan, eksik = dilim.cozumle(havuz)
    assert [o.soru for o in bulunan] == sorted(["Soru 0", "Soru 2"], key=lambda s: dilim.imzalar.index(metin_imzasi(s)))
    assert len(eksik) == 3


def test_dilim_cozumle_manifest_sirasini_korur(dilim):
    """Koşu sırası dilimden gelmeli: sıra değişirse önbellek/takas davranışı değişir."""
    havuz = [Ornek(soru=f"Soru {i}", cozum="c") for i in reversed(range(5))]
    bulunan, eksik = dilim.cozumle(havuz)
    assert not eksik
    assert [metin_imzasi(o.soru) for o in bulunan] == list(dilim.imzalar)


# --- OlcumKaydi ---


def test_kayit_gidis_donus(tmp_path, dilim):
    kayit = _kayit("taban", [_sonuc("Soru 0", True), _sonuc("Soru 1", False)], dilim)
    yol = kayit.yaz(tmp_path)
    geri = OlcumKaydi.oku(yol)
    assert geri.etiket == "taban"
    assert geri.dilim_imzasi == dilim.imza()
    assert len(geri.sorular) == 2
    assert geri.ozet["dogruluk"] == 0.5


def test_ayni_gun_ikinci_kosu_uzerine_yazmaz(tmp_path, dilim):
    a = _kayit("taban", [_sonuc("Soru 0", True)], dilim)
    b = _kayit("taban", [_sonuc("Soru 0", False)], dilim)
    yol_a = a.yaz(tmp_path)
    yol_b = b.yaz(tmp_path)
    assert yol_a != yol_b
    assert yol_a.exists() and yol_b.exists()


def test_kayitlari_listele_dilim_manifestini_saymaz(tmp_path, dilim):
    dilim.yaz(tmp_path)
    _kayit("taban", [_sonuc("Soru 0", True)], dilim).yaz(tmp_path)
    assert len(kayitlari_listele(tmp_path)) == 1


def test_kayitlari_listele_bozuk_dosyayi_atlar(tmp_path, dilim):
    _kayit("taban", [_sonuc("Soru 0", True)], dilim).yaz(tmp_path)
    (tmp_path / "olcumler" / "bozuk.json").write_text("{ bu json değil", encoding="utf-8")
    assert len(kayitlari_listele(tmp_path)) == 1


def test_son_kayit_haric_tutar(tmp_path, dilim):
    eski = _kayit("eski", [_sonuc("Soru 0", True)], dilim, zaman="2026-01-01T00:00:00+00:00")
    yeni = _kayit("yeni", [_sonuc("Soru 0", False)], dilim, zaman="2026-06-01T00:00:00+00:00")
    eski.yaz(tmp_path)
    yeni_yol = yeni.yaz(tmp_path)
    assert son_kayit(tmp_path).etiket == "yeni"
    assert son_kayit(tmp_path, haric=yeni_yol).etiket == "eski"


def test_son_kayit_yoksa_none(tmp_path):
    assert son_kayit(tmp_path) is None


# --- Fark ---


def test_farkla_kazanilan_kaybedilen(dilim):
    onceki = _kayit(
        "a", [_sonuc("Soru 0", False), _sonuc("Soru 1", True), _sonuc("Soru 2", True)], dilim
    )
    yeni = _kayit(
        "b", [_sonuc("Soru 0", True), _sonuc("Soru 1", False), _sonuc("Soru 2", True)], dilim
    )
    fark = farkla(onceki, yeni)
    assert [s.soru for s in fark.kazanilan] == ["Soru 0"]
    assert [s.soru for s in fark.kaybedilen] == ["Soru 1"]
    assert fark.ortak == 3
    assert fark.dilim_uyusuyor


def test_farkla_dilim_degisimini_ayirir(dilim):
    onceki = _kayit("a", [_sonuc("Soru 0", True), _sonuc("Soru 1", True)], dilim)
    yeni = _kayit("b", [_sonuc("Soru 1", True), _sonuc("Soru 9", True)], dilim)
    fark = farkla(onceki, yeni)
    assert fark.ortak == 1
    assert len(fark.yeni_sorular) == 1
    assert len(fark.dusen_sorular) == 1


def test_farkla_tur_bazli(dilim):
    onceki = _kayit("a", [
        _sonuc("Soru 0", False, tur="kalitim_hesabi"),
        _sonuc("Soru 1", False, tur="kalitim_hesabi"),
    ], dilim)
    yeni = _kayit("b", [
        _sonuc("Soru 0", True, tur="kalitim_hesabi"),
        _sonuc("Soru 1", True, tur="kalitim_hesabi"),
    ], dilim)
    once, sonra, adet = farkla(onceki, yeni).tur_farki["kalitim_hesabi"]
    assert (once, sonra, adet) == (0.0, 1.0, 2)


def test_farkla_yontem_dagilimi(dilim):
    onceki = _kayit("a", [_sonuc("Soru 0", True, yontem="model")], dilim)
    yeni = _kayit("b", [_sonuc("Soru 0", True, yontem="kalitim_araci")], dilim)
    dagilim = farkla(onceki, yeni).yontem_dagilimi
    assert dagilim["model"] == (1, 0)
    assert dagilim["kalitim_araci"] == (0, 1)


def test_farkli_dilim_imzasi_yakalanir(dilim):
    baska = Dilim(ad="baska", imzalar=("x", "y"))
    onceki = _kayit("a", [_sonuc("Soru 0", True)], dilim)
    yeni = _kayit("b", [_sonuc("Soru 0", True)], baska)
    fark = farkla(onceki, yeni)
    assert not fark.dilim_uyusuyor
    assert any("farklı dilim" in s for s in fark.gerileme())


# --- McNemar ---


def test_mcnemar_az_degisimde_anlamsiz(dilim):
    onceki = _kayit("a", [_sonuc(f"S{i}", False) for i in range(20)], dilim)
    yeni = _kayit(
        "b",
        [_sonuc(f"S{i}", i < 3) for i in range(20)],  # 3 kazanç, 0 kayıp
        dilim,
    )
    b, c, ki_kare = farkla(onceki, yeni).mcnemar()
    assert (b, c) == (3, 0)
    assert ki_kare != ki_kare  # NaN
    assert not farkla(onceki, yeni).anlamli_mi()


def test_mcnemar_bilinen_deger(dilim):
    """b=10, c=2 → χ² = (|10-2|-1)² / 12 = 49/12 = 4,083 → anlamlı."""
    onceki = _kayit(
        "a", [_sonuc(f"S{i}", i >= 10) for i in range(30)], dilim
    )  # ilk 10 yanlış
    yeni = _kayit(
        "b",
        [_sonuc(f"S{i}", i < 10 or i >= 12) for i in range(30)],  # 10 kazanç, 2 kayıp
        dilim,
    )
    fark = farkla(onceki, yeni)
    b, c, ki_kare = fark.mcnemar()
    assert (b, c) == (10, 2)
    assert ki_kare == pytest.approx(49 / 12, abs=0.01)
    assert fark.anlamli_mi()


def test_mcnemar_esit_degisimde_anlamsiz(dilim):
    onceki = _kayit("a", [_sonuc(f"S{i}", i % 2 == 0) for i in range(40)], dilim)
    yeni = _kayit("b", [_sonuc(f"S{i}", i % 2 == 1) for i in range(40)], dilim)
    fark = farkla(onceki, yeni)
    b, c, _ki = fark.mcnemar()
    assert b == c == 20
    assert not fark.anlamli_mi()


def test_asgari_degisen_sabiti_makul():
    assert ASGARI_DEGISEN >= 10


# --- gerileme kapısı ---


def test_gerileme_genel_dusus(dilim):
    onceki = _kayit("a", [_sonuc(f"S{i}", True) for i in range(10)], dilim)
    yeni = _kayit("b", [_sonuc(f"S{i}", i < 5) for i in range(10)], dilim)
    sorunlar = farkla(onceki, yeni).gerileme(tolerans=0.03)
    assert any("Ortak sorularda doğruluk" in s for s in sorunlar)


def test_gerileme_temizse_bos(dilim):
    onceki = _kayit("a", [_sonuc(f"S{i}", i < 5) for i in range(10)], dilim)
    yeni = _kayit("b", [_sonuc(f"S{i}", i < 8) for i in range(10)], dilim)
    assert farkla(onceki, yeni).gerileme() == []


def test_gerileme_az_ornekli_turu_saymaz(dilim):
    """3 örnekli bir türde 1 sorunun düşmesi %33 oynar; kapı buna kapanmamalı."""
    onceki = _kayit("a", [
        *[_sonuc(f"S{i}", True) for i in range(20)],
        *[_sonuc(f"K{i}", True, tur="hesaplama") for i in range(3)],
    ], dilim)
    yeni = _kayit("b", [
        *[_sonuc(f"S{i}", True) for i in range(20)],
        *[_sonuc(f"K{i}", i > 0, tur="hesaplama") for i in range(3)],
    ], dilim)
    sorunlar = farkla(onceki, yeni).gerileme(asgari_tur_ornegi=8)
    assert not any("hesaplama" in s for s in sorunlar)


def test_gerileme_yeterli_ornekli_turu_sayar(dilim):
    onceki = _kayit("a", [_sonuc(f"K{i}", True, tur="kalitim_hesabi") for i in range(10)], dilim)
    yeni = _kayit("b", [_sonuc(f"K{i}", i < 5, tur="kalitim_hesabi") for i in range(10)], dilim)
    sorunlar = farkla(onceki, yeni).gerileme(asgari_tur_ornegi=8)
    assert any("kalitim_hesabi" in s for s in sorunlar)


def test_rapor_metni_okunabilir(dilim):
    onceki = _kayit("taban", [_sonuc(f"S{i}", i < 5) for i in range(20)], dilim)
    yeni = _kayit("yeni", [_sonuc(f"S{i}", i < 15) for i in range(20)], dilim)
    metin = farkla(onceki, yeni).rapor()
    assert "Doğruluk" in metin
    assert "McNemar" in metin
    assert "Kazanılan sorular" in metin


def test_kayit_json_serilestirilebilir(tmp_path, dilim):
    kayit = _kayit("x", [_sonuc("Soru 0", True)], dilim)
    yol = kayit.yaz(tmp_path)
    veri = json.loads(Path(yol).read_text(encoding="utf-8"))
    assert veri["sorular"][0]["dogru"] is True
    assert "risk_kapsama" in veri


# --- üretim yolu kırılımı ---
#
# Kurtarma tavanlarını ölçüye dayandırabilmek için gereken sinyal: bir yolun
# cevapları doğru olabilir ama güven tavanı yüzünden eşiği hiç geçemiyorsa,
# o tavan doğru cevapları boğuyor demektir. Bu ayrımı yalnız yol bazında
# doğruluk + eşiği geçen sayısı birlikte gösterir.


def test_yontem_bazli_dogruluk_ve_esik_ustu_ayrisir():
    ozet = ozetle(
        [
            # Model yolu: 2/4 doğru, güveni yüksek — eşiği geçiyor.
            *[_sonuc(f"M{i}", i < 2, guven=0.8) for i in range(4)],
            # Kurtarma: 3/4 doğru ama tavan 0,35 — hiçbiri eşiği geçemiyor.
            *[_sonuc(f"K{i}", i < 3, guven=0.35, yontem="kurtarma") for i in range(4)],
        ]
    )
    kirilim = ozet.yontem_bazli(0.70)

    assert kirilim["model"]["dogruluk"] == 0.5
    assert kirilim["model"]["esik_ustu"] == 4

    # Kurtarma daha DOĞRU ama kapsamaya hiç katkı vermiyor: tam da tavanın
    # sorgulanması gereken durum.
    assert kirilim["kurtarma"]["dogruluk"] == 0.75
    assert kirilim["kurtarma"]["esik_ustu"] == 0


def test_yontem_kirilimi_kayda_ve_rapora_giriyor(tmp_path, dilim):
    sonuclar = [
        _sonuc("A", True),
        _sonuc("B", True, guven=0.35, yontem="kurtarma"),
    ]
    kayit = _kayit("x", sonuclar, dilim)
    veri = json.loads(Path(kayit.yaz(tmp_path)).read_text(encoding="utf-8"))
    assert veri["yontem_bazli"]["kurtarma"]["dogruluk"] == 1.0

    metin = ozetle(sonuclar).rapor(esik=0.70)
    assert "Üretim yolu bazında" in metin
    assert "kurtarma" in metin


def test_eski_kayit_yontem_kirilimi_olmadan_okunabilir(tmp_path, dilim):
    """Kırılım eklenmeden önce yazılmış kayıtlar okunmayı sürdürmeli."""
    kayit = _kayit("eski", [_sonuc("A", True)], dilim)
    yol = kayit.yaz(tmp_path)
    veri = json.loads(Path(yol).read_text(encoding="utf-8"))
    del veri["yontem_bazli"]
    Path(yol).write_text(json.dumps(veri, ensure_ascii=False), encoding="utf-8")

    geri = OlcumKaydi.oku(yol)
    assert geri.yontem_bazli == {}


def test_limitli_kosu_farkli_paydayla_sahte_gerileme_uretmez(dilim):
    """`--limit` ile kısaltılmış koşu, tam koşuyla aynı sayıda ölçülmüş gibi
    kıyaslanınca kapı olmayan bir gerileme raporluyordu."""
    # Tam koşu: S0 dışında hepsi doğru → %90.
    onceki = _kayit(
        "tam", [_sonuc(f"S{i}", i >= 1) for i in range(10)], dilim)
    # Aynı dilimin ilk 5 sorusu, `--limit 5` ile: 4/5 → %80.
    yeni = _kayit("limitli", [_sonuc(f"S{i}", i < 4) for i in range(5)], dilim)

    fark = farkla(onceki, yeni)
    assert fark.ortak == 5
    assert fark.kosu_boyutu_onceki == 10
    assert fark.kosu_boyutu_yeni == 5
    # Başlık sayıları %90 → %80: eski mantık burada gerileme ilan ediyordu.
    assert fark.dogruluk_onceki == 0.9
    assert fark.dogruluk_yeni == 0.8
    # Ortak beş soruda ise ikisi de 4/5 — gerçekte hiçbir şey gerilemedi.
    assert fark.ortak_dogruluk_onceki == 0.8
    assert fark.ortak_dogruluk_yeni == 0.8
    assert fark.gerileme(tolerans=0.03) == []
    assert "koşu boyutları farklı" in fark.rapor()


def test_esik_alti_turdeki_gerileme_sessiz_gecmez(dilim):
    onceki = _kayit(
        "a",
        [_sonuc(f"S{i}", True, tur="grafik_yorumlama") for i in range(4)]
        + [_sonuc(f"T{i}", True, tur="mekanizma_aciklama") for i in range(10)],
        dilim,
    )
    yeni = _kayit(
        "b",
        [_sonuc(f"S{i}", False, tur="grafik_yorumlama") for i in range(4)]
        + [_sonuc(f"T{i}", True, tur="mekanizma_aciklama") for i in range(10)],
        dilim,
    )
    fark = farkla(onceki, yeni)
    sorunlar = fark.gerileme(tolerans=0.5, tur_toleransi=0.05)
    # 4 örnek asgari eşiğin (8) altında: kırmızı yakmaz…
    assert not any("grafik_yorumlama" in s for s in sorunlar)
    # …ama görünür kalır.
    assert any("grafik_yorumlama" in s for s in fark.az_ornekli_gerilemeler)
    assert "Eşik altı türlerde gerileme" in fark.rapor()
