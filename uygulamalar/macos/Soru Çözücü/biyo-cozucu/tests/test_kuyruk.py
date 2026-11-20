"""Onay kuyruğu testleri: JSONL gidiş-dönüşü, değişmez alanlar, arşivleme.

Kuyruğun sözleşmesi "hiçbir şeyi sessizce kaybetme": bozuk satır korunur,
kanıt alanları düzenlenemez, arşiv üzerine yazmaz.
"""

from __future__ import annotations

import json

import pytest

from biyo_cozucu.alim import kuyruk as k
from biyo_cozucu.alim.kuyruk import KuyrukKaydi


def _kayit(**alanlar) -> KuyrukKaydi:
    temel = {
        "soru": "Mayoz bölünmede krossing over hangi evrede gerçekleşir?",
        "cozum": "Homolog kromozomlar tetrat oluşturduğunda, profaz bir evresinde olur.",
        "cevap": "A",
        "secenekler": {"A": "profaz bir", "B": "metafaz bir", "C": "anafaz bir"},
        "video_id": "abc12345678",
        "video_basligi": "Kalıtım Soru Çözümü",
        "kanal": "Biyoloji Dersi",
        "kaynak_imzasi": "f" * 16,
        "kaynak": "YouTube: Kalıtım Soru Çözümü",
        "konum": "02:15",
        "baslangic_sn": 135.0,
        "guven": 0.85,
        "dayanak": 0.92,
    }
    temel.update(alanlar)
    return KuyrukKaydi(**temel)


def test_gidis_donus_alanlari_korur(tmp_path):
    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit(), _kayit(soru="Fotosentez nerede gerçekleşir?")])
    kayitlar, bozuk = k.oku(yol)
    assert bozuk == 0
    assert len(kayitlar) == 2
    assert kayitlar[0].secenekler["A"] == "profaz bir"
    assert kayitlar[0].baslangic_sn == 135.0
    assert kayitlar[0].dayanak == 0.92


def test_bozuk_satir_sayilir_ve_yeniden_yazimda_korunur(tmp_path):
    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit()])
    with yol.open("a", encoding="utf-8") as dosya:
        dosya.write("{yarım json\n")
    kayitlar, bozuk = k.oku(yol)
    assert len(kayitlar) == 1 and bozuk == 1

    k.durumlari_isaretle(yol, [1], "onay")
    metin = yol.read_text(encoding="utf-8")
    assert "{yarım json" in metin, "bozuk satır sessizce silinmemeli"
    assert json.loads(metin.splitlines()[0])["durum"] == "onay"


def test_yazim_atomik_tmp_dosyasi_birakmaz(tmp_path):
    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit()])
    assert not list(tmp_path.glob("*.tmp"))


def test_durum_isaretleme_ve_gecersiz_sira(tmp_path):
    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit(), _kayit(soru="İkinci soru metni burada."), _kayit(soru="Üçüncü.")])
    assert k.durumlari_isaretle(yol, [1, 3], "onay") == 2
    kayitlar, _ = k.oku(yol)
    assert [x.durum for x in kayitlar] == ["onay", "bekliyor", "onay"]
    with pytest.raises(ValueError, match="dosyada yok"):
        k.durumlari_isaretle(yol, [9], "ret")


def test_gecersiz_durum_reddedilir(tmp_path):
    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit()])
    with pytest.raises(ValueError, match="Geçersiz durum"):
        k.durumlari_isaretle(yol, [1], "belki")


def test_satiri_guncelle_kanit_alanlarini_korur(tmp_path):
    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit()])
    kayit = k.satiri_guncelle(
        yol,
        1,
        {
            "soru": "Düzeltilmiş soru metni.",
            "guven": 1.0,            # değişmez
            "dayanak": 0.1,          # değişmez
            "video_id": "saldiri",   # değişmez
        },
    )
    assert kayit.soru == "Düzeltilmiş soru metni."
    assert kayit.guven == 0.85
    assert kayit.dayanak == 0.92
    assert kayit.video_id == "abc12345678"
    assert "elle_duzenlendi" in kayit.uyarilar


def test_metin_disi_alan_duzenlemesi_uyari_eklemez(tmp_path):
    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit()])
    kayit = k.satiri_guncelle(yol, 1, {"konu": "hücre bölünmesi"})
    assert kayit.konu == "hücre bölünmesi"
    assert "elle_duzenlendi" not in kayit.uyarilar


def test_ornege_cevir_alanlari_esler(tmp_path):
    ornek = k.ornege_cevir(_kayit())
    assert ornek is not None
    assert ornek.cevap_turu == "coktan_secmeli"
    assert ornek.konu  # kural_ile_etiketle doldurdu
    assert ornek.etiket_kaynagi == "kural"
    assert "youtube" in ornek.etiketler
    assert "abc12345678" in ornek.etiketler
    assert "02:15" in ornek.kaynak


def test_ornege_cevir_bos_cozumde_none():
    assert k.ornege_cevir(_kayit(cozum="   ")) is None


def test_ornege_cevir_kullanicinin_konusuna_saygi_duyar():
    ornek = k.ornege_cevir(_kayit(konu="kalıtım", cozum_turu="hesaplama"))
    assert ornek.konu == "kalıtım"
    assert ornek.cozum_turu == "hesaplama"


def test_alindi_isaretle_ornek_id_yazar(tmp_path):
    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit(), _kayit(soru="İkinci soru metni burada.")])
    kayitlar, _ = k.oku(yol)
    k.alindi_isaretle(yol, {kayitlar[1].kimlik: 41})
    kayitlar, _ = k.oku(yol)
    assert kayitlar[1].durum == "alindi"
    assert kayitlar[1].ornek_id == 41
    assert kayitlar[0].durum == "bekliyor"


def test_alindi_isaretle_kayit_dususunde_kaymaz(tmp_path):
    """Kalıcı kimlik kilidi: aktarım sırasında dosya değişse bile damga
    doğru kayda gider.

    Sıra numarasıyla eşlenseydi, aradan bir kayıt düştüğünde hiç hafızaya
    yazılmamış bir kayıt "alindi" damgası yiyip sessizce kaybolurdu.
    """
    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit(soru=f"Soru {i} metni burada yer alıyor.") for i in range(1, 6)])
    kayitlar, _ = k.oku(yol)
    hedef = kayitlar[3]              # 4. kayıt
    # Aktarım sürerken 1. kayıt dosyadan düşüyor (bozuluyor).
    satirlar = yol.read_text(encoding="utf-8").splitlines()
    yol.write_text("{bozuldu\n" + "\n".join(satirlar[1:]) + "\n", encoding="utf-8")

    k.alindi_isaretle(yol, {hedef.kimlik: 99})
    kalanlar, _ = k.oku(yol)
    damgalanan = [x for x in kalanlar if x.durum == "alindi"]
    assert len(damgalanan) == 1
    assert damgalanan[0].kimlik == hedef.kimlik
    assert damgalanan[0].soru == hedef.soru
    assert damgalanan[0].ornek_id == 99


def test_kimlik_yeniden_yazimda_degismez(tmp_path):
    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit()])
    ilk, _ = k.oku(yol)
    k.durumlari_isaretle(yol, [1], "onay")
    ikinci, _ = k.oku(yol)
    assert ilk[0].kimlik == ikinci[0].kimlik


def test_kimliksiz_eski_dosya_kararli_kimlik_alir(tmp_path):
    """Kimlik alanı olmayan eski kuyruk dosyaları da eşlenebilmeli."""
    yol = tmp_path / "kuyruk.jsonl"
    ham = _kayit().sozluk()
    ham.pop("kimlik")
    yol.write_text(json.dumps(ham, ensure_ascii=False) + "\n", encoding="utf-8")
    ilk, _ = k.oku(yol)
    ikinci, _ = k.oku(yol)
    assert ilk[0].kimlik and ilk[0].kimlik == ikinci[0].kimlik


def test_kimlikle_isaretleme(tmp_path):
    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit(), _kayit(soru="İkinci soru metni burada.")])
    kayitlar, _ = k.oku(yol)
    assert k.durumlari_isaretle(yol, [kayitlar[1].kimlik], "ret") == 1
    sonra, _ = k.oku(yol)
    assert [x.durum for x in sonra] == ["bekliyor", "ret"]
    with pytest.raises(ValueError, match="bulunamadı"):
        k.durumlari_isaretle(yol, ["yokboyle0000"], "onay")


def test_bos_soru_reddedilir(tmp_path):
    """Boş soru kaydı okunamaz hâle getirir ve alttaki sıraları kaydırırdı."""
    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit()])
    with pytest.raises(ValueError, match="boş bırakılamaz"):
        k.satiri_guncelle(yol, 1, {"soru": "   "})
    kayitlar, bozuk = k.oku(yol)
    assert len(kayitlar) == 1 and bozuk == 0


def test_bilinmeyen_alanlar_korunur(tmp_path):
    """Modül dosyanın elle düzenlenebilir olduğunu vaat ediyor."""
    yol = tmp_path / "kuyruk.jsonl"
    ham = _kayit().sozluk()
    ham["ogretmen_notu"] = "sınavda sordum"
    yol.write_text(json.dumps(ham, ensure_ascii=False) + "\n", encoding="utf-8")
    k.durumlari_isaretle(yol, [1], "onay")
    yeniden = json.loads(yol.read_text(encoding="utf-8").splitlines()[0])
    assert yeniden["ogretmen_notu"] == "sınavda sordum"
    assert yeniden["durum"] == "onay"


def test_es_zamanli_yazim_kayit_kaybetmez(tmp_path):
    """Ortak `.tmp` adı iki yazıcıda dosyayı bozabiliyordu."""
    import threading

    yol = tmp_path / "kuyruk.jsonl"
    k.yaz(yol, [_kayit(soru=f"Soru {i} metni burada yer alıyor.") for i in range(1, 21)])

    hatalar: list[Exception] = []

    def isaretle(bas: int) -> None:
        try:
            for sira in range(bas, 21, 2):
                k.durumlari_isaretle(yol, [sira], "onay")
        except Exception as exc:  # noqa: BLE001 - teste rapor edilecek
            hatalar.append(exc)

    iplikler = [threading.Thread(target=isaretle, args=(b,)) for b in (1, 2)]
    for iplik in iplikler:
        iplik.start()
    for iplik in iplikler:
        iplik.join()

    assert not hatalar, f"eşzamanlı yazımda hata: {hatalar}"
    kayitlar, bozuk = k.oku(yol)
    assert len(kayitlar) == 20 and bozuk == 0
    assert all(x.durum == "onay" for x in kayitlar)
    assert not list(tmp_path.glob("*.tmp"))


def test_guvenli_izleme_adresi_semasi_denetler():
    kayit = _kayit(video_id="", url="javascript:alert(1)")
    assert kayit.guvenli_izleme_adresi() == ""
    assert _kayit().guvenli_izleme_adresi().startswith("https://")


def test_ozet_durumlari_sayar(tmp_path):
    yol = k.kuyruk_dizini(tmp_path) / "20260803-120000-abc12345678.jsonl"
    k.yaz(yol, [
        _kayit(),
        _kayit(soru="İkinci soru.", durum="onay"),
        _kayit(soru="Üçüncü soru.", durum="ret"),
        _kayit(soru="Dördüncü soru.", durum="alindi"),
    ])
    ozet = k.ozet(tmp_path)
    assert (ozet.bekleyen, ozet.onayli, ozet.reddedilen, ozet.alinan) == (1, 1, 1, 1)
    assert ozet.dosya_sayisi == 1 and ozet.toplam == 4


def test_arsivle_uzerine_yazmaz(tmp_path):
    dizin = k.kuyruk_dizini(tmp_path)
    ilk = dizin / "20260803-120000-abc.jsonl"
    k.yaz(ilk, [_kayit()])
    hedef1 = k.arsivle(ilk, tmp_path)
    k.yaz(ilk, [_kayit(soru="Farklı bir soru metni.")])
    hedef2 = k.arsivle(ilk, tmp_path)
    assert hedef1 != hedef2
    assert hedef1.exists() and hedef2.exists()
    assert json.loads(hedef1.read_text(encoding="utf-8").splitlines()[0])["soru"] != (
        json.loads(hedef2.read_text(encoding="utf-8").splitlines()[0])["soru"]
    )


def test_arsivlenen_dosya_kuyrukta_gorunmez(tmp_path):
    yol = k.kuyruk_dizini(tmp_path) / "20260803-120000-abc.jsonl"
    k.yaz(yol, [_kayit()])
    k.arsivle(yol, tmp_path)
    assert k.dosyalar(tmp_path) == []


def test_bul_yol_kacisini_engeller(tmp_path):
    yol = k.kuyruk_dizini(tmp_path) / "20260803-120000-abc.jsonl"
    k.yaz(yol, [_kayit()])
    assert k.bul(tmp_path, "20260803-120000-abc.jsonl") == yol
    assert k.bul(tmp_path, "../../etc/passwd") is None
    assert k.bul(tmp_path, "/etc/passwd") is None


def test_kuyrukta_mi_video_kimliginden_bulur(tmp_path):
    assert not k.kuyrukta_mi(tmp_path, "abc12345678")
    k.yaz(k.kuyruk_dizini(tmp_path) / k.dosya_adi("abc12345678"), [_kayit()])
    assert k.kuyrukta_mi(tmp_path, "abc12345678")
    assert not k.kuyrukta_mi(tmp_path, "xyz98765432")


def test_izleme_adresi_zaman_damgali():
    assert _kayit().izleme_adresi() == "https://youtu.be/abc12345678?t=135"
    assert _kayit(baslangic_sn=None).izleme_adresi() == "https://youtu.be/abc12345678"


def test_sozlukten_kayit_bos_soruyu_reddeder():
    assert k.sozlukten_kayit({"soru": "   ", "cozum": "x"}) is None
    assert k.sozlukten_kayit({"soru": "geçerli", "durum": "uydurma"}).durum == "bekliyor"
