"""Görsel soru desteği testleri.

Hepsi çevrimdışı: gerçek VLM birkaç GB indirir ve saniyeler sürer, oysa
sınanan şey görüntünün DOĞRU YERE ULAŞMASI — modelin ne dediği değil.
Görüntüler pillow ile üretilen küçük sentetik PNG'ler.
"""

from __future__ import annotations

import io
import json

import pytest

pytest.importorskip("PIL")

from PIL import Image

from biyo_cozucu.cozucu import Cozucu
from biyo_cozucu.gorsel import GorselDeposu, GorselHatasi
from biyo_cozucu.hafiza.indeks import OrnekIndeksi
from biyo_cozucu.modeller import Ornek
from biyo_cozucu.motor.temel import GorselMotor, SahteGorselMotor, SahteMotor


def _png(renk: tuple[int, int, int] = (255, 0, 0), boyut=(24, 16)) -> bytes:
    tampon = io.BytesIO()
    Image.new("RGB", boyut, renk).save(tampon, format="PNG")
    return tampon.getvalue()


def _yanit(adimlar, cevap, guven=0.9) -> str:
    return json.dumps(
        {"adimlar": adimlar, "cevap": cevap, "guven": guven, "uyari": ""},
        ensure_ascii=False,
    )


# --- görsel deposu ---


def test_ayni_gorsel_tek_kopya_saklanir(tmp_path):
    depo = GorselDeposu(tmp_path)
    veri = _png()
    ilk = depo.yaz(veri)
    ikinci = depo.yaz(veri)
    assert ilk == ikinci
    assert len(list((tmp_path / "gorseller").iterdir())) == 1


def test_farkli_gorsel_farkli_imza_alir(tmp_path):
    depo = GorselDeposu(tmp_path)
    assert depo.yaz(_png((255, 0, 0))) != depo.yaz(_png((0, 0, 255)))


def test_ayni_goruntunun_jpeg_kopyasi_ayni_imzaya_duser(tmp_path):
    """İmza ham baytlardan değil normalize PNG'den alınıyor: aynı şeklin
    JPEG ve PNG kopyaları hafızada iki ayrı kayıt oluşturmamalı."""
    depo = GorselDeposu(tmp_path)
    goruntu = Image.new("RGB", (24, 16), (10, 200, 30))

    png = io.BytesIO()
    goruntu.save(png, format="PNG")
    bmp = io.BytesIO()
    goruntu.save(bmp, format="BMP")

    assert depo.yaz(png.getvalue()) == depo.yaz(bmp.getvalue())


def test_bozuk_veri_anlamli_hata_verir(tmp_path):
    depo = GorselDeposu(tmp_path)
    with pytest.raises(GorselHatasi, match="okunamadı"):
        depo.yaz(b"bu bir goruntu degil")
    with pytest.raises(GorselHatasi, match="Boş"):
        depo.yaz(b"")


def test_asiri_buyuk_goruntu_reddedilir(tmp_path, monkeypatch):
    from biyo_cozucu import gorsel as gorsel_modulu

    monkeypatch.setattr(gorsel_modulu, "AZAMI_BOYUT_MB", 0)
    with pytest.raises(GorselHatasi, match="sınırını aşıyor"):
        GorselDeposu(tmp_path).yaz(_png())


def test_yaz_oku_sil_dongusu(tmp_path):
    depo = GorselDeposu(tmp_path)
    imza = depo.yaz(_png())
    assert depo.var_mi(imza)
    assert depo.oku(imza).startswith(b"\x89PNG")
    assert depo.sil(imza) is True
    assert not depo.var_mi(imza)
    assert depo.sil(imza) is False
    with pytest.raises(GorselHatasi, match="bulunamadı"):
        depo.oku(imza)


# --- motor protokolü ---


def test_gorsel_motor_protokolu_ayirt_edilir():
    """Görsel desteği ayrı protokol: mevcut motorları kırmadan genişletme."""
    assert isinstance(SahteGorselMotor("x"), GorselMotor)
    assert not isinstance(SahteMotor("x"), GorselMotor)


def test_gorselli_soru_goruntuyu_motora_ulastirir(depo, sahte_gomlemci, tmp_path):
    gorsel_deposu = GorselDeposu(tmp_path)
    imza = gorsel_deposu.yaz(_png())
    motor = SahteGorselMotor(_yanit(["Grafikte hız artıyor"], "B"))
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci), motor=motor,
        gomlemci=sahte_gomlemci, gorsel_deposu=gorsel_deposu,
    )

    cozum = cozucu.coz("Grafikte ne görülüyor?", gorsel=imza)

    assert motor.gorseller, "görüntü modele ulaşmalı"
    assert motor.gorseller[0].startswith(b"\x89PNG")
    assert cozum.gorsel == imza
    assert not cozum.incele


def test_gorsel_desteklemeyen_motor_uyarir_ve_incelemeye_duser(
    depo, sahte_gomlemci, tmp_path
):
    """Sessizce metinle çözmek, kullanıcının şekle bakıldığını sanmasına yol açar."""
    gorsel_deposu = GorselDeposu(tmp_path)
    imza = gorsel_deposu.yaz(_png())
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci),
        motor=SahteMotor(_yanit(["metinden tahmin"], "A")),
        gomlemci=sahte_gomlemci, gorsel_deposu=gorsel_deposu,
    )

    cozum = cozucu.coz("Grafikte ne görülüyor?", gorsel=imza)

    assert cozum.incele
    assert any("görsel okuyamıyor" in u for u in cozum.uyarilar)


def test_okunamayan_gorsel_cozumu_durdurmaz_ama_uyarir(depo, sahte_gomlemci, tmp_path):
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci),
        motor=SahteGorselMotor(_yanit(["yine de çözdüm"], "C")),
        gomlemci=sahte_gomlemci, gorsel_deposu=GorselDeposu(tmp_path),
    )

    cozum = cozucu.coz("Şekilde ne var?", gorsel="olmayanimza")

    assert cozum.cevap == "C", "metin yolu yine de cevap üretmeli"
    assert cozum.incele
    assert any("okunamadı" in u for u in cozum.uyarilar)


# --- önbellek ayrışması (en kritik) ---


def test_ayni_metin_farkli_gorsel_onbellegi_paylasmaz(depo, sahte_gomlemci, tmp_path):
    """Sessiz ve ciddi hata sınıfı: "Grafikteki eğri neyi gösterir?" metni iki
    farklı şekille sorulduğunda ikincisi birincinin cevabını almamalı."""
    gorsel_deposu = GorselDeposu(tmp_path)
    kirmizi = gorsel_deposu.yaz(_png((255, 0, 0)))
    mavi = gorsel_deposu.yaz(_png((0, 0, 255)))
    motor = SahteGorselMotor([_yanit(["ilk şekil"], "A"), _yanit(["ikinci şekil"], "B")])
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci), motor=motor,
        gomlemci=sahte_gomlemci, gorsel_deposu=gorsel_deposu,
    )

    soru = "Grafikteki eğri neyi gösterir?"
    ilk = cozucu.coz(soru, gorsel=kirmizi)
    ikinci = cozucu.coz(soru, gorsel=mavi)

    assert ilk.cevap == "A"
    assert ikinci.uretim_yontemi == "model", "farklı görsel önbelleği kullanmamalı"
    assert ikinci.cevap == "B"
    assert len(motor.gorseller) == 2


def test_ayni_metin_ayni_gorsel_onbellekten_doner(depo, sahte_gomlemci, tmp_path):
    gorsel_deposu = GorselDeposu(tmp_path)
    imza = gorsel_deposu.yaz(_png())
    motor = SahteGorselMotor(_yanit(["tek çözüm"], "D"))
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci), motor=motor,
        gomlemci=sahte_gomlemci, gorsel_deposu=gorsel_deposu,
    )

    soru = "Grafikteki eğri neyi gösterir?"
    cozucu.coz(soru, gorsel=imza)
    ikinci = cozucu.coz(soru, gorsel=imza)

    assert ikinci.uretim_yontemi == "onbellek"
    assert len(motor.gorseller) == 1, "ikinci kez model çalıştırılmamalı"


def test_gorselsiz_soru_gorselli_kaydi_almaz(depo, sahte_gomlemci, tmp_path):
    gorsel_deposu = GorselDeposu(tmp_path)
    imza = gorsel_deposu.yaz(_png())
    motor = SahteGorselMotor([_yanit(["şekille"], "A"), _yanit(["şekilsiz"], "B")])
    cozucu = Cozucu(
        depo=depo, indeks=OrnekIndeksi.kur([], sahte_gomlemci), motor=motor,
        gomlemci=sahte_gomlemci, gorsel_deposu=gorsel_deposu,
    )

    soru = "Bu soruda ne oluyor?"
    cozucu.coz(soru, gorsel=imza)
    gorselsiz = cozucu.coz(soru)

    assert gorselsiz.uretim_yontemi == "model"
    assert gorselsiz.cevap == "B"


# --- istem katmanı ---


def test_gorselli_istem_sekli_okuma_kuralini_ekler():
    from biyo_cozucu.istemler import GORSEL_KURALI, cozum_mesajlari

    gorselsiz = cozum_mesajlari("Soru?", [])
    gorselli = cozum_mesajlari("Soru?", [], gorselli=True)
    assert GORSEL_KURALI not in gorselsiz[0]["content"]
    assert GORSEL_KURALI in gorselli[0]["content"]
    # Uydurmaya karşı açık talimat: yanlış ama kendinden emin cevap, incelemeye
    # düşmediği için en zararlı çıktıdır.
    assert "uydurma" in gorselli[0]["content"]


# --- kalıcılık ---


def test_ornek_gorseli_veritabaninda_korunur(depo, tmp_path):
    imza = GorselDeposu(tmp_path).yaz(_png())
    kimlik = depo.ornek_ekle(
        Ornek(soru="Şekilde ne var?", cozum="Bir grafik.", gorsel=imza)
    )
    geri = depo.ornek(kimlik)
    assert geri.gorsel == imza

    geri.gorsel = ""
    depo.ornek_guncelle(geri)
    assert depo.ornek(kimlik).gorsel == "", "görsel kaldırılabilmeli"


# --- VLM motoru (gerçek model yüklemeden sınanabilen kısımlar) ---


def test_vlm_motoru_model_adini_ortamdan_alir(monkeypatch):
    from biyo_cozucu.motor.vlm_motor import VARSAYILAN_MODEL, VlmMotor

    assert VlmMotor().model_yolu == VARSAYILAN_MODEL
    monkeypatch.setenv("BIYO_VLM_MODEL", "yerel/baska-model")
    assert VlmMotor().model_yolu == "yerel/baska-model"
    assert VlmMotor("acik/yol").model_yolu == "acik/yol", "parametre ortamı ezmeli"


def test_vlm_motoru_gorsel_protokolunu_karsilar():
    from biyo_cozucu.motor.vlm_motor import VlmMotor

    assert isinstance(VlmMotor(), GorselMotor)


def test_vlm_istemi_cok_turlu_mesajlari_tek_metne_indirger():
    """mlx-vlm sohbet listesi değil tek istem alıyor; kanıt diyalogları
    metne düzleştiriliyor (görselli few-shot bilinçli olarak yok)."""
    from biyo_cozucu.motor.vlm_motor import VlmMotor

    istem = VlmMotor()._metin_istemi([
        {"role": "system", "content": "Sen bir biyoloji öğretmenisin."},
        {"role": "user", "content": "Örnek soru?"},
        {"role": "assistant", "content": '{"cevap":"B"}'},
        {"role": "user", "content": "Asıl soru?"},
    ])
    assert "Sen bir biyoloji öğretmenisin." in istem
    assert "Örnek çözüm:" in istem
    assert istem.strip().endswith("Asıl soru?")


def test_mlx_vlm_yoksa_kurulum_komutunu_soyleyen_hata(monkeypatch):
    """Hata "model bulunamadı" gibi görünmemeli; eksik olan pakettir."""
    import builtins

    from biyo_cozucu.motor.temel import MotorHatasi
    from biyo_cozucu.motor.vlm_motor import ASGARI_MLX_VLM, VlmMotor, onbellegi_bosalt

    onbellegi_bosalt()
    gercek = builtins.__import__

    def engelli(ad, *args, **kwargs):
        if ad.startswith("mlx_vlm"):
            raise ImportError("mlx_vlm yok")
        return gercek(ad, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", engelli)
    with pytest.raises(MotorHatasi) as bilgi:
        VlmMotor("sahte/model").gorselle_uret([{"role": "user", "content": "x"}], _png())
    mesaj = str(bilgi.value)
    assert "uv sync --extra vizyon" in mesaj
    assert ASGARI_MLX_VLM in mesaj
