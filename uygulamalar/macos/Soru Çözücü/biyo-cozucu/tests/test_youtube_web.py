"""YouTube alım + onay kuyruğu web testleri (çevrimdışı).

Sınanan değişmezler: arka plan işi hafızaya yazmaz, video hatası işi
düşürmez, düzenleme kanıt alanlarına dokunamaz, aktarma indeksi artımlı
günceller, yol kaçışı 404 verir.
"""

from __future__ import annotations

import re
import threading
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path

import pytest

pytest.importorskip("fastapi")

from fastapi import FastAPI
from fastapi.testclient import TestClient

from biyo_cozucu.alim import kuyruk as kuyruk_birimi
from biyo_cozucu.alim.cikarim import AlimHatasi, Kaynak, Parca
from biyo_cozucu.alim.youtube import YoutubeVideo
from biyo_cozucu.webapp import sablonlar_kur
from biyo_cozucu.webapp.durum import Uygulama
from biyo_cozucu.webapp.youtube import YoutubeServisi, yonlendirici

_VIDEO = YoutubeVideo(
    video_id="abc12345678",
    baslik="Kalıtım Soru Çözümü",
    kanal="Biyoloji Dersi",
    sure_sn=300,
    url="https://www.youtube.com/watch?v=abc12345678",
)

_DOKUM = (
    "Birinci soru: Mayoz bölünmede krossing over hangi evrede gerçekleşir? "
    "Çözüm: Krossing over homolog kromozomların tetrat oluşturduğu profaz bir "
    "evresinde gerçekleşir. Cevap A şıkkıdır."
)


def _kaynak(video: YoutubeVideo) -> Kaynak:
    return Kaynak(
        ad=video.kaynak_adi(),
        tur="youtube",
        imza=video.imza,
        parcalar=[Parca(metin=_DOKUM, baslangic_sn=12.0, bitis_sn=60.0)],
    )


@contextmanager
def _istemci(
    tmp_path: Path,
    monkeypatch,
    *,
    videolar: list[YoutubeVideo] | None = None,
    dok: Callable | None = None,
) -> Iterator[tuple[TestClient, YoutubeServisi, Uygulama]]:
    monkeypatch.setattr(
        "biyo_cozucu.alim.youtube.kunye_getir",
        lambda url, *, limit=0: list(videolar or [_VIDEO]),
    )
    monkeypatch.setattr(
        "biyo_cozucu.alim.youtube.videoyu_dok",
        dok or (lambda video, *, kok, yeniden=False, sesi_sakla=False, dokum_ilerlemesi=None: _kaynak(video)),
    )
    durum = Uygulama(kok=tmp_path, motor_turu="yok", gommesiz=True)
    servis = YoutubeServisi(tmp_path, None, baslangicta_kurtar=False)
    uygulama = FastAPI()
    uygulama.include_router(yonlendirici(durum, sablonlar_kur(), servis=servis))
    try:
        with TestClient(uygulama) as istemci:
            yield istemci, servis, durum
    finally:
        servis.kapat()


def _bitmesini_bekle(servis: YoutubeServisi, is_id: str, sure: float = 10.0) -> dict:
    son = time.time() + sure
    while time.time() < son:
        kayit = servis.durum(is_id)
        if kayit and kayit["durum"] in {"bitti", "hata", "durduruldu"}:
            return kayit
        time.sleep(0.05)
    raise AssertionError(f"İş {sure} saniyede bitmedi: {servis.durum(is_id)}")


def _is_baslat(istemci: TestClient, **alanlar) -> str:
    veri = {"url": "https://www.youtube.com/watch?v=abc12345678", "kural": "1"}
    veri.update(alanlar)
    yanit = istemci.post("/youtube/is", data=veri, follow_redirects=False)
    assert yanit.status_code == 303
    return yanit.headers["location"].split("is_id=")[1]


# --- sayfalar ---


def test_youtube_sayfasi_acilir(tmp_path, monkeypatch):
    with _istemci(tmp_path, monkeypatch) as (istemci, _servis, _durum):
        yanit = istemci.get("/youtube")
        assert yanit.status_code == 200
        assert "onay kuyruğuna" in yanit.text


def test_youtube_disi_adres_reddedilir(tmp_path, monkeypatch):
    with _istemci(tmp_path, monkeypatch) as (istemci, _servis, _durum):
        yanit = istemci.post(
            "/youtube/is", data={"url": "https://vimeo.com/1"}, follow_redirects=False
        )
        assert yanit.status_code == 400
        assert "YouTube" in yanit.text


def test_bilinmeyen_is_404(tmp_path, monkeypatch):
    with _istemci(tmp_path, monkeypatch) as (istemci, _servis, _durum):
        assert istemci.get("/youtube/api/is/yok").status_code == 404
        assert istemci.post("/youtube/api/is/yok/durdur").status_code == 404


# --- iş yaşam döngüsü ---


def test_is_kuyruga_yazar_hafizaya_yazmaz(tmp_path, monkeypatch):
    with _istemci(tmp_path, monkeypatch) as (istemci, servis, durum):
        is_id = _is_baslat(istemci)
        kayit = _bitmesini_bekle(servis, is_id)
        assert kayit["durum"] == "bitti"
        assert kayit["aday_sayisi"] >= 1
        assert kuyruk_birimi.dosyalar(tmp_path)
        # Asıl değişmez: onaysız hiçbir şey hafızaya girmez.
        assert durum.depo.ornek_sayisi() == 0


def test_kuyrukta_bekleyen_video_yeniden_islenmez(tmp_path, monkeypatch):
    """CLI ile aynı koruma: aynı adresi iki kez göndermek ikinci bir kuyruk
    dosyası üretmemeli."""
    dokum_sayisi = {"adet": 0}

    def _dok(video, *, kok, yeniden=False, sesi_sakla=False, dokum_ilerlemesi=None):
        dokum_sayisi["adet"] += 1
        return _kaynak(video)

    with _istemci(tmp_path, monkeypatch, dok=_dok) as (istemci, servis, _durum):
        _bitmesini_bekle(servis, _is_baslat(istemci))
        assert dokum_sayisi["adet"] == 1
        dosya_sayisi = len(kuyruk_birimi.dosyalar(tmp_path))

        kayit = _bitmesini_bekle(servis, _is_baslat(istemci))
        assert dokum_sayisi["adet"] == 1, "aynı video ikinci kez dökülmemeli"
        assert len(kuyruk_birimi.dosyalar(tmp_path)) == dosya_sayisi
        assert "atlandı" in kayit["mesaj"]


def test_video_hatasi_isi_dusurmez(tmp_path, monkeypatch):
    kotu = YoutubeVideo(video_id="kotu0000000", baslik="Bölge kilidi")

    def _dok(video, *, kok, yeniden=False, sesi_sakla=False, dokum_ilerlemesi=None):
        if video.video_id == "kotu0000000":
            raise AlimHatasi("bölge kilidi")
        return _kaynak(video)

    with _istemci(
        tmp_path, monkeypatch, videolar=[kotu, _VIDEO], dok=_dok
    ) as (istemci, servis, _durum):
        kayit = _bitmesini_bekle(servis, _is_baslat(istemci))
        assert kayit["durum"] == "bitti"
        assert kayit["hata_sayisi"] == 1
        assert kayit["aday_sayisi"] >= 1
        durumlar = {v["video_id"]: v["durum"] for v in kayit["videolar"]}
        assert durumlar["kotu0000000"] == "hata"
        assert durumlar["abc12345678"] == "bitti"


def test_durdurma_video_sinirinda_etkili(tmp_path, monkeypatch):
    videolar = [
        YoutubeVideo(video_id=f"video{i:07d}", baslik=f"Video {i}") for i in range(4)
    ]
    servis_kutusu: dict = {}

    def _dok(video, *, kok, yeniden=False, sesi_sakla=False, dokum_ilerlemesi=None):
        # İlk video işlenirken durdurma iste; ikinciye geçilmemeli.
        servis_kutusu["servis"].durdur(servis_kutusu["is_id"])
        return _kaynak(video)

    with _istemci(tmp_path, monkeypatch, videolar=videolar, dok=_dok) as (
        _istemcisi, servis, _durum
    ):
        servis_kutusu["servis"] = servis
        # İş kaydı oluşturulup hemen durdurulabilsin diye önce ekle, sonra başlat.
        is_id = servis.is_ekle("https://youtu.be/abc12345678", {"kural": True})
        servis_kutusu["is_id"] = is_id
        servis.baslat(is_id)
        kayit = _bitmesini_bekle(servis, is_id)
        assert kayit["durum"] == "durduruldu"
        assert kayit["biten_video"] < len(videolar)


def test_kurtarma_yarim_isi_yeniden_calistirir(tmp_path, monkeypatch):
    monkeypatch.setattr(
        "biyo_cozucu.alim.youtube.kunye_getir", lambda url, *, limit=0: [_VIDEO]
    )
    monkeypatch.setattr(
        "biyo_cozucu.alim.youtube.videoyu_dok",
        lambda video, *, kok, yeniden=False, sesi_sakla=False, dokum_ilerlemesi=None: _kaynak(video),
    )
    ilk = YoutubeServisi(tmp_path, None, baslangicta_kurtar=False)
    is_id = ilk.is_ekle("https://youtu.be/abc12345678", {"kural": True})
    ilk.depo.guncelle(is_id, durum="calisiyor", asama="dokum")
    ilk.kapat()

    ikinci = YoutubeServisi(tmp_path, None, baslangicta_kurtar=True)
    try:
        kayit = _bitmesini_bekle(ikinci, is_id)
        assert kayit["durum"] == "bitti"
    finally:
        ikinci.kapat()


# --- kuyruk sayfaları ---


def test_kuyruk_sayfalari_ve_derin_baglanti(tmp_path, monkeypatch):
    with _istemci(tmp_path, monkeypatch) as (istemci, servis, _durum):
        _bitmesini_bekle(servis, _is_baslat(istemci))
        liste = istemci.get("/kuyruk")
        assert liste.status_code == 200
        ad = kuyruk_birimi.dosyalar(tmp_path)[0].name
        assert ad in liste.text

        sayfa = istemci.get(f"/kuyruk/{ad}")
        assert sayfa.status_code == 200
        assert "youtu.be/abc12345678?t=" in sayfa.text


def test_kuyruk_yol_kacisi_404(tmp_path, monkeypatch):
    with _istemci(tmp_path, monkeypatch) as (istemci, _servis, _durum):
        assert istemci.get("/kuyruk/..%2F..%2Fetc%2Fpasswd").status_code == 404
        assert istemci.get("/kuyruk/yok.jsonl").status_code == 404


def test_satir_duzenleme_guveni_degistirmez(tmp_path, monkeypatch):
    with _istemci(tmp_path, monkeypatch) as (istemci, servis, _durum):
        _bitmesini_bekle(servis, _is_baslat(istemci))
        yol = kuyruk_birimi.dosyalar(tmp_path)[0]
        onceki, _ = kuyruk_birimi.oku(yol)
        yanit = istemci.post(
            f"/kuyruk/{yol.name}/satir/{onceki[0].kimlik}",
            data={
                "soru": "Elle düzeltilmiş soru metni.",
                "cozum": onceki[0].cozum,
                "cevap": onceki[0].cevap,
                "konu": "kalıtım",
                "guven": "1.0",
            },
            follow_redirects=False,
        )
        assert yanit.status_code == 303
        sonraki, _ = kuyruk_birimi.oku(yol)
        assert sonraki[0].soru == "Elle düzeltilmiş soru metni."
        assert sonraki[0].konu == "kalıtım"
        assert sonraki[0].guven == onceki[0].guven
        assert "elle_duzenlendi" in sonraki[0].uyarilar


def test_toplu_onay_ve_aktarma_indeksi_gunceller(tmp_path, monkeypatch):
    with _istemci(tmp_path, monkeypatch) as (istemci, servis, durum):
        _bitmesini_bekle(servis, _is_baslat(istemci))
        yol = kuyruk_birimi.dosyalar(tmp_path)[0]
        kayitlar, _ = kuyruk_birimi.oku(yol)

        onay = istemci.post(
            f"/kuyruk/{yol.name}/toplu",
            data={"secilenler": [k.kimlik for k in kayitlar], "eylem": "onay"},
            follow_redirects=False,
        )
        assert onay.status_code == 303

        aktar = istemci.post(f"/kuyruk/{yol.name}/aktar", follow_redirects=False)
        assert aktar.status_code == 303
        assert durum.depo.ornek_sayisi() >= 1
        ornek = durum.depo.ornekler()[0]
        assert ornek.id is not None
        assert durum.indeks.icerir(ornek.id), "aktarılan örnek indekse girmeli"
        assert durum.depo.kaynak_alindi_mi(_VIDEO.imza)
        # Tümü alındı → dosya arşive taşındı.
        assert kuyruk_birimi.dosyalar(tmp_path) == []


def test_onaysiz_aktarma_hafizayi_degistirmez(tmp_path, monkeypatch):
    with _istemci(tmp_path, monkeypatch) as (istemci, servis, durum):
        _bitmesini_bekle(servis, _is_baslat(istemci))
        yol = kuyruk_birimi.dosyalar(tmp_path)[0]
        yanit = istemci.post(f"/kuyruk/{yol.name}/aktar", follow_redirects=False)
        assert yanit.status_code == 303
        assert durum.depo.ornek_sayisi() == 0
        assert not durum.depo.kaynak_alindi_mi(_VIDEO.imza)


def test_kuyruk_dosyasi_silme_onay_ister(tmp_path, monkeypatch):
    """Tek tıkla bir videonun tüm adayları ve düzeltmeleri gitmemeli."""
    with _istemci(tmp_path, monkeypatch) as (istemci, servis, _durum):
        _bitmesini_bekle(servis, _is_baslat(istemci))
        yol = kuyruk_birimi.dosyalar(tmp_path)[0]

        onaysiz = istemci.post(f"/kuyruk/{yol.name}/sil", follow_redirects=False)
        assert onaysiz.status_code == 400
        assert kuyruk_birimi.dosyalar(tmp_path), "onaysız silme dosyayı silmemeli"

        onayli = istemci.post(
            f"/kuyruk/{yol.name}/sil", data={"onaylandi": "1"}, follow_redirects=False
        )
        assert onayli.status_code == 303
        assert kuyruk_birimi.dosyalar(tmp_path) == []


def test_toplu_isaretlemede_bilinmeyen_kimlik_500_vermez(tmp_path, monkeypatch):
    """Bayat sekme ya da geri tuşuyla yeniden gönderim."""
    with _istemci(tmp_path, monkeypatch) as (istemci, servis, _durum):
        _bitmesini_bekle(servis, _is_baslat(istemci))
        yol = kuyruk_birimi.dosyalar(tmp_path)[0]
        yanit = istemci.post(
            f"/kuyruk/{yol.name}/toplu",
            data={"secilenler": ["yokboyle0000"], "eylem": "onay"},
            follow_redirects=False,
        )
        assert yanit.status_code == 400
        assert "yenile" in yanit.text.casefold()


def test_yinelenen_kayit_aktarimda_bildirilir(tmp_path, monkeypatch):
    """Sessiz atlama: kullanıcı neden hâlâ 'onay' kaldığını göremiyordu."""
    with _istemci(tmp_path, monkeypatch) as (istemci, servis, durum):
        _bitmesini_bekle(servis, _is_baslat(istemci))
        yol = kuyruk_birimi.dosyalar(tmp_path)[0]
        kayitlar, _ = kuyruk_birimi.oku(yol)
        # Aynı soruyu önceden hafızaya koy: aktarımda çakışacak.
        ornek = kuyruk_birimi.ornege_cevir(kayitlar[0])
        durum.depo.ornek_ekle(ornek)

        istemci.post(
            f"/kuyruk/{yol.name}/toplu",
            data={"secilenler": [kayitlar[0].kimlik], "eylem": "onay"},
            follow_redirects=False,
        )
        yanit = istemci.post(f"/kuyruk/{yol.name}/aktar", follow_redirects=False)
        assert yanit.status_code == 200
        assert "atlanan" in yanit.text.casefold()
        assert "zaten kayıtlı" in yanit.text


def test_kuyruk_sayfasinda_ic_ice_form_yok(tmp_path, monkeypatch):
    """İç içe form, tarayıcıda toplu onay düğmelerini sessizce etkisizleştirir.

    HTML ayrıştırıcısı iç `<form>`u yok sayar ve onun `</form>`u dış formu
    erken kapatır; kutular işaretlenip onayla'ya basılınca hiçbir şey olmaz.
    """
    with _istemci(tmp_path, monkeypatch) as (istemci, servis, _durum):
        _bitmesini_bekle(servis, _is_baslat(istemci))
        ad = kuyruk_birimi.dosyalar(tmp_path)[0].name
        govde = istemci.get(f"/kuyruk/{ad}").text

        derinlik = 0
        for parca in re.finditer(r"<form\b|</form>", govde):
            if parca.group().startswith("</"):
                derinlik -= 1
            else:
                derinlik += 1
                assert derinlik == 1, "form içinde form açılmış"
            assert derinlik >= 0, "fazladan </form>"
        assert derinlik == 0, "kapanmamış form"
        # Onay kutuları tabloda ama forma öznitelikle bağlı olmalı.
        assert 'form="toplu-form"' in govde


def test_beklenmedik_hata_isi_hata_durumuna_yazar(tmp_path, monkeypatch):
    """Yakalanmayan istisna işi sonsuza dek 'calisiyor' bırakıyordu."""

    def _patlat(video, *, kok, yeniden=False, sesi_sakla=False, dokum_ilerlemesi=None):
        raise RuntimeError("beklenmedik çökme")

    with _istemci(tmp_path, monkeypatch, dok=_patlat) as (istemci, servis, _durum):
        kayit = _bitmesini_bekle(servis, _is_baslat(istemci))
        # Video düzeyinde yalıtıldı: iş biter, hata sayılır.
        assert kayit["durum"] == "bitti"
        assert kayit["hata_sayisi"] == 1
        assert "beklenmedik çökme" in kayit["videolar"][0]["hata"]


def test_kunye_beklenmedik_hatasi_isi_hataya_alir(tmp_path, monkeypatch):
    monkeypatch.setattr(
        "biyo_cozucu.alim.youtube.kunye_getir",
        lambda url, *, limit=0: (_ for _ in ()).throw(RuntimeError("çöktü")),
    )
    monkeypatch.setattr(
        "biyo_cozucu.alim.youtube.videoyu_dok",
        lambda video, *, kok, yeniden=False, sesi_sakla=False, dokum_ilerlemesi=None: _kaynak(video),
    )
    servis = YoutubeServisi(tmp_path, None, baslangicta_kurtar=False)
    try:
        is_id = servis.is_ekle("https://youtu.be/abc12345678", {"kural": True})
        servis.baslat(is_id)
        kayit = _bitmesini_bekle(servis, is_id)
        assert kayit["durum"] == "hata"
        assert "çöktü" in kayit["hata"]
    finally:
        servis.kapat()


def test_kapanis_calisan_isin_veritabanini_cekmez(tmp_path, monkeypatch):
    """Kapanışta bağlantı erken kapanırsa işçi ProgrammingError alıyordu."""
    basladi = threading.Event()
    devam = threading.Event()

    def _yavas_dok(video, *, kok, yeniden=False, sesi_sakla=False, dokum_ilerlemesi=None):
        basladi.set()
        devam.wait(5)
        return _kaynak(video)

    monkeypatch.setattr(
        "biyo_cozucu.alim.youtube.kunye_getir", lambda url, *, limit=0: [_VIDEO]
    )
    monkeypatch.setattr("biyo_cozucu.alim.youtube.videoyu_dok", _yavas_dok)
    servis = YoutubeServisi(tmp_path, None, baslangicta_kurtar=False)
    is_id = servis.is_ekle("https://youtu.be/abc12345678", {"kural": True})
    servis.baslat(is_id)
    assert basladi.wait(5), "iş başlamadı"
    devam.set()
    servis.kapat(bekleme_sn=5.0)

    # Kapanış işçiyi bekledi: satır "calisiyor" takılı kalmamalı.
    yeni = YoutubeServisi(tmp_path, None, baslangicta_kurtar=False)
    try:
        assert yeni.durum(is_id)["durum"] in {"bitti", "durduruldu", "hata"}
    finally:
        yeni.kapat()


def test_bozuk_adres_500_vermez(tmp_path, monkeypatch):
    with _istemci(tmp_path, monkeypatch) as (istemci, _servis, _durum):
        yanit = istemci.post(
            "/youtube/is", data={"url": "http://["}, follow_redirects=False
        )
        assert yanit.status_code == 400
