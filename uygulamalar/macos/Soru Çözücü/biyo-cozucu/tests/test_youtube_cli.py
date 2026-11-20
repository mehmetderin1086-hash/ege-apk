"""YouTube alım + onay kuyruğu CLI testleri (uçtan uca, çevrimdışı).

En önemli iki değişmez burada sınanıyor: `youtube-al --uygula` HAFIZAYA
yazmaz (yalnız kuyruğa), ve kaynak imzası çıkarımda değil ONAY aktarımında
işaretlenir — yoksa kuyruğa yazılıp onaylanmadan silinen bir video sonsuza
dek "alınmış" görünürdü.
"""

from __future__ import annotations

import json

import pytest

from biyo_cozucu.alim import kuyruk as kuyruk_birimi
from biyo_cozucu.alim.cikarim import Kaynak, Parca
from biyo_cozucu.alim.youtube import YoutubeVideo
from biyo_cozucu.cli import _siralari_ayristir, main
from biyo_cozucu.depo import Depo

_VIDEO = YoutubeVideo(
    video_id="abc12345678",
    baslik="AYT Biyoloji Kalıtım Soru Çözümü",
    kanal="Biyoloji Dersi",
    sure_sn=754,
    url="https://www.youtube.com/watch?v=abc12345678",
)

_DOKUM = (
    "Birinci soru: Mayoz bölünmede krossing over hangi evrede gerçekleşir? "
    "Çözüm: Krossing over homolog kromozomların tetrat oluşturduğu profaz bir "
    "evresinde gerçekleşir. Cevap A şıkkıdır."
)


def _calistir(*argumanlar) -> int:
    return main(list(argumanlar))


@pytest.fixture
def sahte_youtube(monkeypatch):
    """kunye_getir/videoyu_dok'u sahteler; ağ ve whisper hiç çalışmaz."""
    cagrilar = {"kunye": 0, "dokum": 0}

    def _kunye(url, *, limit=0):
        cagrilar["kunye"] += 1
        return [_VIDEO]

    def _dok(video, *, kok, yeniden=False, sesi_sakla=False, dokum_ilerlemesi=None):
        cagrilar["dokum"] += 1
        if dokum_ilerlemesi is not None:
            dokum_ilerlemesi(1, 1)
        return Kaynak(
            ad=video.kaynak_adi(),
            tur="youtube",
            imza=video.imza,
            parcalar=[Parca(metin=_DOKUM, baslangic_sn=12.0, bitis_sn=60.0)],
        )

    monkeypatch.setattr("biyo_cozucu.alim.youtube.kunye_getir", _kunye)
    monkeypatch.setattr("biyo_cozucu.alim.youtube.videoyu_dok", _dok)
    return cagrilar


def _kuyruga_al(tmp_path, sahte_youtube) -> int:
    return _calistir(
        "--veri", str(tmp_path), "youtube-al",
        "https://www.youtube.com/watch?v=abc12345678",
        "--uygula", "--kural",
    )


# --- youtube-al ---


def test_onizleme_hicbir_sey_indirmez(tmp_path, sahte_youtube, capsys):
    kod = _calistir(
        "--veri", str(tmp_path), "youtube-al",
        "https://www.youtube.com/watch?v=abc12345678",
    )
    assert kod == 0
    cikti = capsys.readouterr().out
    assert "Önizleme" in cikti
    assert "[yeni" in cikti
    assert "12:34" in cikti or "12:3" in cikti  # 754 sn
    assert sahte_youtube["dokum"] == 0
    assert kuyruk_birimi.dosyalar(tmp_path) == []


def test_uygula_kuyruga_yazar_hafizaya_yazmaz(tmp_path, sahte_youtube):
    assert _kuyruga_al(tmp_path, sahte_youtube) == 0
    yollar = kuyruk_birimi.dosyalar(tmp_path)
    assert len(yollar) == 1
    kayitlar, bozuk = kuyruk_birimi.oku(yollar[0])
    assert bozuk == 0 and kayitlar
    assert kayitlar[0].video_id == "abc12345678"
    assert kayitlar[0].yontem == "kural"
    assert kayitlar[0].durum == "bekliyor"
    # Asıl değişmez: hafıza boş kalmalı.
    assert Depo(tmp_path / "biyo.db").ornek_sayisi() == 0


def test_kuyrukta_bekleyen_video_yeniden_dokulmez(tmp_path, sahte_youtube, capsys):
    _kuyruga_al(tmp_path, sahte_youtube)
    onceki_dokum = sahte_youtube["dokum"]
    _kuyruga_al(tmp_path, sahte_youtube)
    assert sahte_youtube["dokum"] == onceki_dokum
    assert "kuyrukta" in capsys.readouterr().out


def test_cikarim_ilerlemesi_basilir(tmp_path, monkeypatch, capsys):
    """Uzun videoda çıkarım saatler sürüyor; kullanıcı çıktısız kalmamalı."""
    from biyo_cozucu.motor.temel import SahteMotor

    uzun_dokum = " ".join(
        f"Soru {i}: Mayoz bölünmeyle ilgili bir durum anlatılıyor burada."
        for i in range(400)
    )
    monkeypatch.setattr(
        "biyo_cozucu.alim.youtube.kunye_getir", lambda url, *, limit=0: [_VIDEO]
    )
    monkeypatch.setattr(
        "biyo_cozucu.alim.youtube.videoyu_dok",
        lambda video, *, kok, yeniden=False, sesi_sakla=False, dokum_ilerlemesi=None: Kaynak(
            ad=video.kaynak_adi(), tur="youtube", imza=video.imza,
            parcalar=[Parca(metin=uzun_dokum, baslangic_sn=0.0, bitis_sn=600.0)],
        ),
    )
    monkeypatch.setattr(
        "biyo_cozucu.motor.motor_yukle",
        lambda *a, **k: SahteMotor(json.dumps({"sorular": []})),
    )
    _calistir(
        "--veri", str(tmp_path), "youtube-al", "https://youtu.be/abc12345678",
        "--uygula", "--motor", "sahte",
    )
    cikti = capsys.readouterr().out
    assert "çıkarım" in cikti and "pencere" in cikti


def test_uzun_videoda_colab_onerilir(tmp_path, monkeypatch, capsys):
    """Kullanıcı bunu bir saat bekledikten sonra değil, önizlemede öğrenmeli."""
    uzun = YoutubeVideo(
        video_id="uzun0000000", baslik="AYT full tekrar", sure_sn=35620.0
    )
    monkeypatch.setattr(
        "biyo_cozucu.alim.youtube.kunye_getir", lambda url, *, limit=0: [uzun]
    )
    kod = _calistir("--veri", str(tmp_path), "youtube-al", "https://youtu.be/uzun0000000")
    assert kod == 0
    hata = capsys.readouterr().err
    assert "60 dakikadan uzun" in hata
    assert "transkript-al" in hata


def test_kisa_videoda_colab_onerilmez(tmp_path, sahte_youtube, capsys):
    _calistir("--veri", str(tmp_path), "youtube-al", "https://youtu.be/abc12345678")
    assert "Colab" not in capsys.readouterr().err


def test_onbellekli_uzun_videoda_uyari_yok(tmp_path, monkeypatch, capsys):
    """Döküm zaten elde; uyarı gürültü olurdu."""
    from biyo_cozucu.alim.youtube import transkripti_ice_aktar

    kaynak = tmp_path / "uzun0000000.json"
    kaynak.write_text(
        json.dumps({
            "video_id": "uzun0000000", "sure_sn": 35620.0,
            "parcalar": [{"metin": "bir metin", "baslangic_sn": 0.0, "bitis_sn": 3.0}],
        }),
        encoding="utf-8",
    )
    transkripti_ice_aktar(kaynak, tmp_path)
    monkeypatch.setattr(
        "biyo_cozucu.alim.youtube.kunye_getir",
        lambda url, *, limit=0: [
            YoutubeVideo(video_id="uzun0000000", sure_sn=35620.0)
        ],
    )
    _calistir("--veri", str(tmp_path), "youtube-al", "https://youtu.be/uzun0000000")
    assert "60 dakikadan uzun" not in capsys.readouterr().err


def test_transkript_al_komutu(tmp_path, capsys):
    kaynak = tmp_path / "indirilen"
    kaynak.mkdir()
    (kaynak / "video000000a.json").write_text(
        json.dumps({
            "video_id": "video000000a", "baslik": "Ders", "sure_sn": 600.0,
            "parcalar": [{"metin": "Mayoz bölünme", "baslangic_sn": 1.0, "bitis_sn": 4.0}],
        }),
        encoding="utf-8",
    )
    (kaynak / "bozuk.json").write_text("{yarım", encoding="utf-8")

    kod = _calistir("--veri", str(tmp_path), "transkript-al", str(kaynak))
    assert kod == 0
    cikti = capsys.readouterr()
    assert "video000000a: 1 parça" in cikti.out
    assert "İçe aktarılan transkript: 1" in cikti.out
    assert "Alınamayan dosya: 1" in cikti.out

    from biyo_cozucu.alim.youtube import transkript_yolu

    assert transkript_yolu(tmp_path, "video000000a").is_file()


def test_transkript_al_hepsi_bozuksa_bir_doner(tmp_path):
    bozuk = tmp_path / "bozuk.json"
    bozuk.write_text("{yarım", encoding="utf-8")
    assert _calistir("--veri", str(tmp_path), "transkript-al", str(bozuk)) == 1


def test_onbellekten_okunurken_dogru_mesaj(tmp_path, sahte_youtube, capsys):
    _kuyruga_al(tmp_path, sahte_youtube)
    # `sahte_youtube` videoyu_dok'u sahteliyor; önbellek dosyasını elle koy.
    from biyo_cozucu.alim.youtube import transkript_yolu

    yol = transkript_yolu(tmp_path, "abc12345678")
    yol.parent.mkdir(parents=True, exist_ok=True)
    yol.write_text(
        json.dumps({"parcalar": [{"metin": _DOKUM, "baslangic_sn": 0.0, "bitis_sn": 9.0}]}),
        encoding="utf-8",
    )
    kuyruk_birimi.dosyalar(tmp_path)[0].unlink()
    _calistir(
        "--veri", str(tmp_path), "youtube-al", "https://youtu.be/abc12345678",
        "--uygula", "--kural",
    )
    assert "önbellekteki döküm" in capsys.readouterr().out


def test_kunye_hatasi_cikis_kodu_bir(tmp_path, monkeypatch, capsys):
    def _patlat(url, *, limit=0):
        from biyo_cozucu.alim.cikarim import AlimHatasi

        raise AlimHatasi("Video unavailable")

    monkeypatch.setattr("biyo_cozucu.alim.youtube.kunye_getir", _patlat)
    kod = _calistir(
        "--veri", str(tmp_path), "youtube-al", "https://youtu.be/abc12345678"
    )
    assert kod == 1
    assert "Video unavailable" in capsys.readouterr().err


def test_json_kipi_kuyruk_kayitlarini_basar(tmp_path, sahte_youtube, capsys):
    kod = _calistir(
        "--veri", str(tmp_path), "youtube-al",
        "https://youtu.be/abc12345678", "--uygula", "--kural", "--json",
    )
    assert kod == 0
    veri = json.loads(capsys.readouterr().out)
    assert veri and veri[0]["video_id"] == "abc12345678"


def test_asgari_guven_adaylari_eler(tmp_path, sahte_youtube, capsys):
    kod = _calistir(
        "--veri", str(tmp_path), "youtube-al",
        "https://youtu.be/abc12345678", "--uygula", "--kural",
        "--asgari-guven", "0.99",
    )
    assert kod == 0
    assert kuyruk_birimi.dosyalar(tmp_path) == []
    assert "elenen:" in capsys.readouterr().out


# --- kuyruk ---


def test_kuyruk_ozeti_ve_listesi(tmp_path, sahte_youtube, capsys):
    _kuyruga_al(tmp_path, sahte_youtube)
    assert _calistir("--veri", str(tmp_path), "kuyruk") == 0
    ozet = capsys.readouterr().out
    assert "bekleyen" in ozet

    assert _calistir("--veri", str(tmp_path), "kuyruk", "1") == 0
    liste = capsys.readouterr().out
    assert "krossing over" in liste.casefold()


def test_kuyruk_bos_iken_yol_gosterir(tmp_path, capsys):
    assert _calistir("--veri", str(tmp_path), "kuyruk") == 0
    assert "youtube-al" in capsys.readouterr().out


def test_onayla_ve_reddet_isaretler(tmp_path, sahte_youtube, capsys):
    _kuyruga_al(tmp_path, sahte_youtube)
    assert _calistir("--veri", str(tmp_path), "kuyruk", "1", "--onayla", "1") == 0
    kayitlar, _ = kuyruk_birimi.oku(kuyruk_birimi.dosyalar(tmp_path)[0])
    assert kayitlar[0].durum == "onay"

    assert _calistir("--veri", str(tmp_path), "kuyruk", "1", "--reddet", "1") == 0
    kayitlar, _ = kuyruk_birimi.oku(kuyruk_birimi.dosyalar(tmp_path)[0])
    assert kayitlar[0].durum == "ret"


def test_gecersiz_sira_hata_kodu(tmp_path, sahte_youtube, capsys):
    _kuyruga_al(tmp_path, sahte_youtube)
    kod = _calistir("--veri", str(tmp_path), "kuyruk", "1", "--onayla", "99")
    assert kod == 2
    assert "dosyada yok" in capsys.readouterr().err


def test_bilinmeyen_dosya_hata(tmp_path, capsys):
    assert _calistir("--veri", str(tmp_path), "kuyruk", "yok.jsonl") == 1


# --- kuyruk-onayla ---


def test_onay_akisi_hafizaya_yazar_ve_kaynagi_isaretler(tmp_path, sahte_youtube, capsys):
    _kuyruga_al(tmp_path, sahte_youtube)
    depo = Depo(tmp_path / "biyo.db")
    assert not depo.kaynak_alindi_mi(_VIDEO.imza), "çıkarımda işaretlenmemeli"

    _calistir("--veri", str(tmp_path), "kuyruk", "1", "--tumu")
    kod = _calistir(
        "--veri", str(tmp_path), "--gommesiz", "kuyruk-onayla", "--hepsi", "--indekssiz"
    )
    assert kod == 0
    assert depo.ornek_sayisi() == 1
    ornek = depo.ornekler()[0]
    assert "krossing over" in ornek.soru.casefold()
    assert "youtube" in ornek.etiketler
    assert depo.kaynak_alindi_mi(_VIDEO.imza), "onayda işaretlenmeli"
    # Biten dosya arşive taşındı.
    assert kuyruk_birimi.dosyalar(tmp_path) == []


def test_onaysiz_kayit_aktarilmaz(tmp_path, sahte_youtube, capsys):
    _kuyruga_al(tmp_path, sahte_youtube)
    kod = _calistir(
        "--veri", str(tmp_path), "--gommesiz", "kuyruk-onayla", "--hepsi", "--indekssiz"
    )
    assert kod == 0
    assert Depo(tmp_path / "biyo.db").ornek_sayisi() == 0
    assert "Aktarılacak onaylı kayıt yok" in capsys.readouterr().out


def test_asgari_guvenle_bekleyenler_aktarilir(tmp_path, sahte_youtube):
    _kuyruga_al(tmp_path, sahte_youtube)
    kod = _calistir(
        "--veri", str(tmp_path), "--gommesiz", "kuyruk-onayla", "--hepsi",
        "--asgari-guven", "0.0", "--indekssiz",
    )
    assert kod == 0
    assert Depo(tmp_path / "biyo.db").ornek_sayisi() >= 1


def test_uyarisiz_bayragi_yalniz_temiz_kayitlari_aktarir(tmp_path, sahte_youtube):
    """Güven eşiği bunun yerine geçmiyor: temiz bir kaydın güveni de düşük
    olabilir, uyarılı bir kaydınki de eşiğin üstünde kalabilir."""
    _kuyruga_al(tmp_path, sahte_youtube)
    yol = kuyruk_birimi.dosyalar(tmp_path)[0]
    kayitlar, _ = kuyruk_birimi.oku(yol)
    # Biri temiz ama düşük güvenli, biri uyarılı ama yüksek güvenli.
    kayitlar[0].uyarilar = []
    kayitlar[0].guven = 0.2
    kayitlar[0].soru = "Temiz ama düşük güvenli soru metni burada."
    kirli = kuyruk_birimi.KuyrukKaydi(
        soru="Uyarılı ama yüksek güvenli soru metni burada.",
        cozum="Bu kaydın çözümü yeterince uzun bir metindir.",
        guven=0.95,
        uyarilar=["dokumde_dayanagi_zayif"],
    )
    kuyruk_birimi.yaz(yol, [kayitlar[0], kirli])

    kod = _calistir(
        "--veri", str(tmp_path), "--gommesiz", "kuyruk-onayla", "--hepsi",
        "--uyarisiz", "--indekssiz", "--arsivleme",
    )
    assert kod == 0
    depo = Depo(tmp_path / "biyo.db")
    sorular = [o.soru for o in depo.ornekler()]
    assert any("Temiz ama düşük" in s for s in sorular)
    assert not any("Uyarılı ama" in s for s in sorular)


def test_yinelenen_soru_atlanir(tmp_path, sahte_youtube, capsys):
    _kuyruga_al(tmp_path, sahte_youtube)
    _calistir("--veri", str(tmp_path), "kuyruk", "1", "--tumu")
    _calistir("--veri", str(tmp_path), "--gommesiz", "kuyruk-onayla", "--hepsi",
              "--indekssiz")
    onceki = Depo(tmp_path / "biyo.db").ornek_sayisi()

    # Aynı video yeniden kuyruğa alınıp onaylanırsa hafıza büyümemeli.
    _calistir(
        "--veri", str(tmp_path), "youtube-al", "https://youtu.be/abc12345678",
        "--uygula", "--kural", "--yeniden",
    )
    _calistir("--veri", str(tmp_path), "kuyruk", "1", "--tumu")
    _calistir("--veri", str(tmp_path), "--gommesiz", "kuyruk-onayla", "--hepsi",
              "--indekssiz")
    assert Depo(tmp_path / "biyo.db").ornek_sayisi() == onceki


def test_onay_indeksi_artimli_gunceller(tmp_path, sahte_youtube, capsys):
    """Onay, indeksi tam yeniden kurmadan büyütmeli."""
    _calistir(
        "--veri", str(tmp_path), "--gommesiz", "ornek-ekle",
        "--soru", "Fotosentez hangi organelde gerçekleşir?",
        "--cozum", "Kloroplastta gerçekleşir; ışık ve karbon tepkimeleri orada yürür.",
    )
    from biyo_cozucu.hafiza.indeks import OrnekIndeksi

    onceki = len(OrnekIndeksi.yukle(tmp_path / "indeks"))

    _kuyruga_al(tmp_path, sahte_youtube)
    _calistir("--veri", str(tmp_path), "kuyruk", "1", "--tumu")
    kod = _calistir("--veri", str(tmp_path), "--gommesiz", "kuyruk-onayla", "--hepsi")
    assert kod == 0
    assert "İndeks güncellendi" in capsys.readouterr().out
    assert len(OrnekIndeksi.yukle(tmp_path / "indeks")) == onceki + 1


# --- kuyruk-sil ve yardımcılar ---


def test_kuyruk_sil_bekleyen_varken_zorla_ister(tmp_path, sahte_youtube, capsys):
    _kuyruga_al(tmp_path, sahte_youtube)
    kod = _calistir("--veri", str(tmp_path), "kuyruk-sil", "1")
    assert kod == 1
    assert "--zorla" in capsys.readouterr().err
    assert kuyruk_birimi.dosyalar(tmp_path)

    assert _calistir("--veri", str(tmp_path), "kuyruk-sil", "1", "--zorla") == 0
    assert kuyruk_birimi.dosyalar(tmp_path) == []


def test_kuyruk_sil_reddedilenleri_temizler(tmp_path, sahte_youtube):
    _kuyruga_al(tmp_path, sahte_youtube)
    yol = kuyruk_birimi.dosyalar(tmp_path)[0]
    kayitlar, _ = kuyruk_birimi.oku(yol)
    kuyruk_birimi.durumlari_isaretle(yol, list(range(1, len(kayitlar) + 1)), "ret")
    assert _calistir("--veri", str(tmp_path), "kuyruk-sil", "--reddedilenler") == 0
    assert kuyruk_birimi.dosyalar(tmp_path) == []


def test_durum_komutu_kuyrugu_gosterir(tmp_path, sahte_youtube, capsys):
    _kuyruga_al(tmp_path, sahte_youtube)
    assert _calistir("--veri", str(tmp_path), "durum") == 0
    assert "Kuyruk" in capsys.readouterr().out


@pytest.mark.parametrize(
    ("metin", "beklenen"),
    [
        ("1", [1]),
        ("1,3", [1, 3]),
        ("5-9", [5, 6, 7, 8, 9]),
        ("1,3,5-7", [1, 3, 5, 6, 7]),
        (" 2 , 4 ", [2, 4]),
    ],
)
def test_sira_araligi_ayristirma(metin, beklenen):
    assert _siralari_ayristir(metin) == beklenen


def test_devasa_aralik_reddedilir():
    """Yazım hatası, doğrulamaya varmadan belleği şişirirdi."""
    with pytest.raises(ValueError, match="çok geniş"):
        _siralari_ayristir("1-99999999")


def test_negatif_pencere_kilitlenmez(tmp_path, sahte_youtube):
    """`--pencere -1` dökümden SONRA sonsuz döngüye giriyordu."""
    kod = _calistir(
        "--veri", str(tmp_path), "youtube-al", "https://youtu.be/abc12345678",
        "--uygula", "--kural", "--pencere", "-1",
    )
    assert kod == 0


def test_onay_kayit_dususunde_dogru_kaydi_damgalar(tmp_path, sahte_youtube):
    """Kalıcı kimlik kilidi (CLI yolu)."""
    _kuyruga_al(tmp_path, sahte_youtube)
    yol = kuyruk_birimi.dosyalar(tmp_path)[0]
    kayitlar, _ = kuyruk_birimi.oku(yol)
    _calistir("--veri", str(tmp_path), "kuyruk", "1", "--tumu")
    _calistir("--veri", str(tmp_path), "--gommesiz", "kuyruk-onayla", "--hepsi",
              "--indekssiz", "--arsivleme")
    sonra, _ = kuyruk_birimi.oku(yol)
    depo = Depo(tmp_path / "biyo.db")
    for kayit in sonra:
        if kayit.durum == "alindi":
            assert kayit.ornek_id is not None
            yazilan = depo.ornek(kayit.ornek_id)
            assert yazilan is not None, "alindi damgası hafızada karşılığı olmayan kayda"
            assert yazilan.soru == kayit.soru, "damga başka kaydın kimliğine gitmiş"
    assert len(sonra) == len(kayitlar)
