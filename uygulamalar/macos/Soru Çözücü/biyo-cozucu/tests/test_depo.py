from __future__ import annotations

import sqlite3

import numpy as np
import pytest

from biyo_cozucu.depo import SEMA_SURUMU, Depo
from biyo_cozucu.metin import imza as metin_imzasi
from biyo_cozucu.modeller import Cozum, Ornek


def test_ornek_ekle_ve_oku(depo, ornekler):
    kimlik = depo.ornek_ekle(ornekler[0])
    okunan = depo.ornek(kimlik)
    assert okunan is not None
    assert okunan.konu == "hücre bölünmesi"
    assert okunan.cozum_turu == "mekanizma_aciklama"
    assert depo.ornek_sayisi() == 1


def test_ayni_soru_iki_kez_eklenemez(depo, ornekler):
    depo.ornek_ekle(ornekler[0])
    with pytest.raises(ValueError, match="zaten kayıtlı"):
        depo.ornek_ekle(ornekler[0])


def test_uzerine_yaz_gunceller_yeni_kayit_acmaz(depo, ornekler):
    kimlik = depo.ornek_ekle(ornekler[0])
    guncel = Ornek(
        soru=ornekler[0].soru, cozum="Yeni çözüm", cevap="X", konu="yeni konu"
    )
    ikinci = depo.ornek_ekle(guncel, uzerine_yaz=True)
    assert ikinci == kimlik
    assert depo.ornek_sayisi() == 1
    assert depo.ornek(kimlik).cozum == "Yeni çözüm"


def test_bicimsel_farkli_ayni_soru_yineleme_sayilir(depo):
    depo.ornek_ekle(Ornek(soru="Mitoz nedir?", cozum="c"))
    with pytest.raises(ValueError):
        depo.ornek_ekle(Ornek(soru="  mitoz   NEDİR ", cozum="başka"))


def test_ornek_sil_pasife_alir_gecmisi_korur(dolu_depo):
    dolu_depo.ornek_sil(1)
    assert dolu_depo.ornek_sayisi() == 4
    assert dolu_depo.ornek_sayisi(yalniz_aktif=False) == 5
    assert len(dolu_depo.ornekler()) == 4


def test_cozum_kaydet_ve_onayla(depo):
    cozum = Cozum(soru="Mitoz nedir?", adimlar=["a"], cevap="B", guven=0.8)
    kimlik = depo.cozum_kaydet(cozum)
    okunan, satir = depo.cozum(kimlik)
    assert okunan.cevap == "B"
    assert satir["onay_durumu"] == "bekliyor"

    depo.cozum_onayla(kimlik, durum="duzeltildi", duzeltme="doğrusu C")
    _okunan, satir = depo.cozum(kimlik)
    assert satir["onay_durumu"] == "duzeltildi"
    assert satir["duzeltme"] == "doğrusu C"


def test_cozum_kaydet_kaynak_kimligiyle_idempotenttir(depo):
    ilk = Cozum(soru="Mitoz nedir?", cevap="A", guven=0.4)
    ikinci = Cozum(soru="Mitoz nedir?", cevap="B", guven=0.8)

    ilk_id = depo.cozum_kaydet(ilk, kaynak_kimligi="kes-ve-coz:is-1:7")
    ikinci_id = depo.cozum_kaydet(ikinci, kaynak_kimligi="kes-ve-coz:is-1:7")

    assert ikinci_id == ilk_id
    assert len(depo.cozumler()) == 1
    okunan, _satir = depo.cozum(ilk_id)
    assert okunan.cevap == "B"
    assert okunan.dogrulama["kaynak_kimligi"] == "kes-ve-coz:is-1:7"


def test_bilinmeyen_onay_durumu_reddedilir(depo):
    kimlik = depo.cozum_kaydet(Cozum(soru="s"))
    with pytest.raises(ValueError):
        depo.cozum_onayla(kimlik, durum="belki")


def test_onbellek_tam_eslesme_ve_isabet_sayaci(depo):
    cozum = Cozum(soru="Mitoz nedir?", adimlar=["a"], cevap="B")
    depo.onbellek_yaz("Mitoz nedir?", cozum, None)

    assert depo.onbellek_tam_eslesme("  mitoz NEDİR ") is not None
    assert depo.onbellek_tam_eslesme("Mayoz nedir?") is None
    assert depo.ozet()["onbellek_isabeti"] == 1


def test_onbellek_gomme_gidis_donusu_korunur(depo):
    vektor = np.array([0.1, 0.2, 0.3], dtype=np.float32)
    depo.onbellek_yaz("soru", Cozum(soru="soru"), vektor)
    girdiler = depo.onbellek_girdileri()
    assert len(girdiler) == 1
    np.testing.assert_allclose(girdiler[0][1], vektor)


def test_onbellek_girdileri_baglam_imzasina_gore_suzulur(depo):
    """Yakın eşleşme havuzu yalnız aynı şık eşlemesine sahip girdileri görmeli."""
    vektor = np.array([0.1, 0.2, 0.3], dtype=np.float32)
    depo.onbellek_yaz("soru A", Cozum(soru="soru A", cevap="A"), vektor, "imza-1")
    depo.onbellek_yaz("soru B", Cozum(soru="soru B", cevap="B"), vektor, "imza-2")

    assert len(depo.onbellek_girdileri()) == 2
    assert len(depo.onbellek_girdileri("imza-1")) == 1
    assert depo.onbellek_girdileri("bilinmeyen") == []


def test_eski_semadan_goc_sutunu_ekler_ve_onbellegi_bosaltir(tmp_path):
    """v1 satırları yeni anahtar biçimiyle erişilemez; sayacı şişirmesinler diye silinir."""
    yol = tmp_path / "eski.db"
    ham = sqlite3.connect(str(yol))
    ham.executescript(
        """
        CREATE TABLE sema_bilgi(anahtar TEXT PRIMARY KEY, deger TEXT NOT NULL);
        CREATE TABLE cozum_onbellek(
            soru_imza TEXT PRIMARY KEY, soru TEXT NOT NULL, gomme BLOB,
            cozum_json TEXT NOT NULL, isabet INTEGER NOT NULL DEFAULT 0,
            olusturma TEXT NOT NULL
        );
        """
    )
    ham.execute(
        "INSERT INTO cozum_onbellek VALUES(?,?,?,?,?,?)",
        (
            metin_imzasi("eski soru"),
            "eski soru",
            np.ones(4, dtype=np.float32).tobytes(),
            Cozum(soru="eski soru", cevap="B").json(),
            3,
            "2026-01-01T00:00:00+00:00",
        ),
    )
    ham.commit()
    ham.close()

    eski = Depo(yol)
    try:
        sutunlar = {s["name"] for s in eski._sorgu("PRAGMA table_info(cozum_onbellek)")}
        assert "baglam_imza" in sutunlar
        assert eski.ozet()["onbellek"] == 0
        assert eski.onbellek_girdileri() == []
        # Göç iki kez açılışta da güvenli olmalı.
        eski.kapat()
        yeniden = Depo(yol)
        try:
            assert yeniden.ozet()["onbellek"] == 0
        finally:
            yeniden.kapat()
    finally:
        eski.kapat()


def test_onbellek_ayni_soruda_uzerine_yazar(depo):
    depo.onbellek_yaz("soru", Cozum(soru="soru", cevap="A"), None)
    depo.onbellek_yaz("soru", Cozum(soru="soru", cevap="B"), None)
    assert depo.ozet()["onbellek"] == 1
    assert depo.onbellek_tam_eslesme("soru").cevap == "B"


def test_ozet_dagilimlari_verir(dolu_depo):
    ozet = dolu_depo.ozet()
    assert ozet["ornek"] == 5
    assert ozet["konu_dagilimi"]["hücre bölünmesi"] == 2
    assert ozet["cozum_turu_dagilimi"]["mekanizma_aciklama"] == 2


def test_egitim_surumu_kaydi(depo, tmp_path):
    depo.egitim_surumu_ekle("v1", str(tmp_path), 100, 10, notlar="deneme")
    surumler = depo.egitim_surumleri()
    assert len(surumler) == 1
    assert surumler[0]["etiket"] == "v1"
    assert surumler[0]["ornek_sayisi"] == 100


# --- SQL seviyesinde süzme ve sayfalama ---


def _ornek(soru, konu="", tur="mekanizma_aciklama"):
    return Ornek(soru=soru, cozum="çözüm metni", konu=konu, cozum_turu=tur)


def test_ornek_aramasi_turkce_katlamaya_uyar(depo):
    """SQLite'ın LIKE'ı 'İ/ı' bilmez; `esitle` SQL fonksiyonu olarak bağlanmalı."""
    depo.ornek_ekle(_ornek("MİTOZ bölünme nasıl olur?"))
    depo.ornek_ekle(_ornek("Fotosentez nerede gerçekleşir?"))

    assert len(depo.ornekler(ara="mitoz")) == 1
    assert len(depo.ornekler(ara="MITOZ")) == 1
    assert len(depo.ornekler(ara="mİtoz")) == 1
    assert depo.ornekler(ara="mayoz") == []


def test_ornek_aramasi_konuda_da_arar(depo):
    depo.ornek_ekle(_ornek("Bir soru?", konu="kalıtım"))
    assert len(depo.ornekler(ara="kalıtım")) == 1


def test_ornek_turune_gore_suzulur(depo):
    depo.ornek_ekle(_ornek("Birinci?", tur="hesaplama"))
    depo.ornek_ekle(_ornek("İkinci?", tur="ezber_bilgi"))
    assert len(depo.ornekler(cozum_turu="hesaplama")) == 1
    assert len(depo.ornekler(cozum_turu="ezber_bilgi")) == 1


def test_ornek_sayfalamasi_ayni_suzgeci_kullanir(depo):
    for i in range(1, 8):
        depo.ornek_ekle(_ornek(f"Mitoz sorusu {i}?"))
    depo.ornek_ekle(_ornek("Alakasız fotosentez sorusu?"))

    assert depo.ornek_say(ara="mitoz") == 7
    ilk = depo.ornekler(ara="mitoz", limit=3, offset=0)
    ikinci = depo.ornekler(ara="mitoz", limit=3, offset=3)
    son = depo.ornekler(ara="mitoz", limit=3, offset=6)
    assert [len(ilk), len(ikinci), len(son)] == [3, 3, 1]
    kimlikler = [o.id for o in (*ilk, *ikinci, *son)]
    assert len(set(kimlikler)) == 7, "sayfalar örtüşmemeli"


def test_pasif_ornek_aramada_cikmaz(depo):
    kimlik = depo.ornek_ekle(_ornek("Silinecek mitoz sorusu?"))
    depo.ornek_sil(kimlik)
    assert depo.ornek_say(ara="mitoz") == 0
    assert depo.ornek_say(ara="mitoz", yalniz_aktif=False) == 1


def test_cozum_aramasi_ve_sayfalamasi(depo):
    for i in range(5):
        depo.cozum_kaydet(Cozum(soru=f"Mitoz çözüm {i}", cevap="A"))
    depo.cozum_kaydet(Cozum(soru="Fotosentez çözümü", cevap="B"))

    assert depo.cozum_say(ara="mitoz") == 5
    assert len(depo.cozumler(ara="mitoz", limit=2)) == 2
    assert len(depo.cozumler(ara="mitoz", limit=2, offset=4)) == 1


def test_cozum_yalniz_incele_suzgeci(depo):
    depo.cozum_kaydet(Cozum(soru="Temiz çözüm", cevap="A", incele=False))
    depo.cozum_kaydet(Cozum(soru="Şüpheli çözüm", cevap="B", incele=True))
    assert depo.cozum_say(yalniz_incele=True) == 1
    assert depo.cozumler(yalniz_incele=True)[0]["soru"] == "Şüpheli çözüm"


def test_v2_veritabani_kosu_tablosuyla_gocer(tmp_path):
    """Şema 2 → 3: `kosu` tablosu eklenirken var olan veri korunmalı.

    Kullanıcının gerçek veritabanı tek kopya ve yedeksiz; bu göçün veri
    kaybetmediği testle sabitlenmeli.
    """
    yol = tmp_path / "v2.db"
    ham = sqlite3.connect(str(yol))
    ham.executescript(
        """
        CREATE TABLE sema_bilgi(anahtar TEXT PRIMARY KEY, deger TEXT NOT NULL);
        CREATE TABLE ornek(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            soru TEXT NOT NULL, soru_imza TEXT NOT NULL UNIQUE,
            cozum TEXT NOT NULL, cevap TEXT NOT NULL DEFAULT '',
            cevap_turu TEXT NOT NULL DEFAULT 'acik_uclu',
            secenekler TEXT NOT NULL DEFAULT '{}',
            konu TEXT NOT NULL DEFAULT '', cozum_turu TEXT NOT NULL DEFAULT '',
            etiketler TEXT NOT NULL DEFAULT '[]', kaynak TEXT NOT NULL DEFAULT '',
            etiket_kaynagi TEXT NOT NULL DEFAULT 'elle',
            aktif INTEGER NOT NULL DEFAULT 1, olusturma TEXT NOT NULL
        );
        INSERT INTO sema_bilgi VALUES('surum', '2');
        """
    )
    ham.execute(
        "INSERT INTO ornek(soru, soru_imza, cozum, olusturma)"
        " VALUES('Eski soru?', ?, 'Eski çözüm.', '2026-01-01T00:00:00+00:00')",
        (metin_imzasi("Eski soru?"),),
    )
    ham.commit()
    ham.close()

    depo = Depo(yol)
    try:
        assert depo.ornek_sayisi() == 1, "göç var olan örneği kaybetmemeli"
        assert depo.ornekler()[0].soru == "Eski soru?"
        assert depo.kosular() == [], "yeni tablo boş ama okunabilir olmalı"
        surum = depo._sorgu("SELECT deger FROM sema_bilgi WHERE anahtar='surum'")
        assert surum[0]["deger"] == str(SEMA_SURUMU)
        # v3 → v4 göçü de aynı açılışta uygulanmalı: görsel sütunu eklenmeli.
        sutunlar = {s["name"] for s in depo._sorgu("PRAGMA table_info(ornek)")}
        assert "gorsel" in sutunlar
        assert depo.ornekler()[0].gorsel == "", "eski örnekler görselsiz kalmalı"
    finally:
        depo.kapat()


def test_kosu_kaydedilir_ve_geri_okunur(depo, ornekler):
    from biyo_cozucu.degerlendirme import OrnekSonucu, ozetle

    ozet = ozetle([
        OrnekSonucu(
            ornek_id=1, soru="Soru?", beklenen_cevap="B", uretilen_cevap="B",
            cevap_dogru=True, adim_ortusmesi=0.8, guven=0.9, incele=False,
            cozum_turu="kalitim_hesabi",
        ),
        OrnekSonucu(
            ornek_id=2, soru="Soru2?", beklenen_cevap="A", uretilen_cevap="C",
            cevap_dogru=False, adim_ortusmesi=0.2, guven=0.4, incele=True,
            cozum_turu="kalitim_hesabi",
        ),
    ])
    kimlik = depo.kosu_kaydet(ozet, etiket="taban", model="sahte")
    assert kimlik > 0

    (kayit,) = depo.kosular()
    assert kayit["etiket"] == "taban"
    assert kayit["ornek_sayisi"] == 2
    assert kayit["dogru"] == 1
    assert kayit["dogruluk"] == pytest.approx(0.5)
    # Tür bazlı kırılım JSON olarak saklanıp geri çözülmeli: karşılaştırmanın
    # asıl değerli kısmı bu (hangi tür zayıf).
    assert kayit["tur_bazli"]["kalitim_hesabi"]["adet"] == 2
    assert depo.kosu(kimlik)["etiket"] == "taban"
    assert depo.kosu(9999) is None


def test_kosular_en_yeniden_eskiye_siralanir(depo):
    from biyo_cozucu.degerlendirme import ozetle

    for etiket in ("ilk", "ikinci", "ucuncu"):
        depo.kosu_kaydet(ozetle([]), etiket=etiket)
    assert [k["etiket"] for k in depo.kosular()] == ["ucuncu", "ikinci", "ilk"]
