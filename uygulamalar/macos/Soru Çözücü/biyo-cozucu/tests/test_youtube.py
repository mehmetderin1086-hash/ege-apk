"""YouTube alım testleri: künye çekme, indirme bayrakları, transkript önbelleği.

`test_ses.py` deseni: gerçek yt-dlp/whisper hiçbir zaman çalıştırılmaz,
`subprocess.run` monkeypatch'lenir ve sınanan şey çağrının NASIL kurulduğudur
(hangi bayraklar geçti, hangi bayrak GEÇMEDİ).
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from biyo_cozucu.alim import youtube
from biyo_cozucu.alim.cikarim import AlimHatasi, Parca

_TEK_VIDEO = {
    "id": "abc12345678",
    "title": "AYT Biyoloji Kalıtım Soru Çözümü",
    "channel": "Biyoloji Dersi",
    "duration": 754,
    "webpage_url": "https://www.youtube.com/watch?v=abc12345678",
}


class _SahteSonuc:
    def __init__(self, stdout: str = "", returncode: int = 0, stderr: str = ""):
        self.stdout = stdout
        self.returncode = returncode
        self.stderr = stderr


@pytest.fixture(autouse=True)
def _ytdlp_yolu(monkeypatch, tmp_path):
    """yt-dlp aramasını sahte bir yola bağlar; makinede kurulu olması gerekmez."""
    ikili = tmp_path / "yt-dlp"
    ikili.write_text("")
    monkeypatch.setenv("BIYO_YTDLP", str(ikili))
    return ikili


def _komutlari_yakala(monkeypatch, cikti: str = "", returncode: int = 0, stderr: str = ""):
    cagrilar: list[list[str]] = []

    def _sahte_run(komut, **kwargs):
        cagrilar.append(list(komut))
        return _SahteSonuc(cikti, returncode, stderr)

    monkeypatch.setattr(subprocess, "run", _sahte_run)
    return cagrilar


# --- künye ---


def test_kunye_tek_video(monkeypatch):
    _komutlari_yakala(monkeypatch, json.dumps(_TEK_VIDEO))
    videolar = youtube.kunye_getir("https://www.youtube.com/watch?v=abc12345678")
    assert len(videolar) == 1
    video = videolar[0]
    assert video.video_id == "abc12345678"
    assert video.sure_sn == 754
    assert "Kalıtım" in video.kaynak_adi()
    assert video.kaynak_adi().startswith("YouTube: ")


def test_kunye_playlist_ve_limit(monkeypatch):
    girdiler = [dict(_TEK_VIDEO, id=f"video{i:07d}") for i in range(5)]
    _komutlari_yakala(monkeypatch, json.dumps({"entries": girdiler}))
    videolar = youtube.kunye_getir("https://www.youtube.com/playlist?list=PL1", limit=2)
    assert [v.video_id for v in videolar] == ["video0000000", "video0000001"]


def test_kunye_silinmis_girdiyi_atlar(monkeypatch):
    _komutlari_yakala(
        monkeypatch, json.dumps({"entries": [None, _TEK_VIDEO, "bozuk"]})
    )
    videolar = youtube.kunye_getir("https://www.youtube.com/playlist?list=PL1")
    assert [v.video_id for v in videolar] == ["abc12345678"]


def test_kunye_null_sure_sifira_duser(monkeypatch):
    _komutlari_yakala(monkeypatch, json.dumps(dict(_TEK_VIDEO, duration=None)))
    (video,) = youtube.kunye_getir("https://youtu.be/abc12345678")
    assert video.sure_sn == 0.0


def test_kunye_flat_playlist_bayragi_gecer(monkeypatch):
    cagrilar = _komutlari_yakala(monkeypatch, json.dumps(_TEK_VIDEO))
    youtube.kunye_getir("https://youtu.be/abc12345678")
    assert "--flat-playlist" in cagrilar[0]
    assert "--dump-single-json" in cagrilar[0]


def test_kunye_bos_liste_hata(monkeypatch):
    _komutlari_yakala(monkeypatch, json.dumps({"entries": []}))
    with pytest.raises(AlimHatasi, match="video bulunamadı"):
        youtube.kunye_getir("https://www.youtube.com/playlist?list=PL1")


def test_ytdlp_hatasi_stderr_tasir(monkeypatch):
    _komutlari_yakala(monkeypatch, returncode=1, stderr="ERROR: Video unavailable")
    with pytest.raises(AlimHatasi, match="Video unavailable"):
        youtube.kunye_getir("https://youtu.be/abc12345678")


def test_ytdlp_bulunamazsa_anlamli_hata(monkeypatch):
    monkeypatch.delenv("BIYO_YTDLP", raising=False)
    monkeypatch.setattr(youtube.shutil, "which", lambda ad: None)
    monkeypatch.setitem(__import__("sys").modules, "yt_dlp", None)
    with pytest.raises(AlimHatasi, match="BIYO_YTDLP"):
        youtube._ytdlp_komutu()


# --- URL kapısı ---


@pytest.mark.parametrize(
    "url",
    [
        "https://vimeo.com/12345",
        "https://youtube.com.saldirgan.example/watch?v=1",
        "file:///etc/passwd",
        "ftp://youtube.com/x",
    ],
)
def test_youtube_disi_adres_reddedilir(url):
    with pytest.raises(AlimHatasi):
        youtube._url_dogrula(url)


@pytest.mark.parametrize(
    "url",
    [
        "https://www.youtube.com/watch?v=abc",
        "https://youtu.be/abc",
        "https://m.youtube.com/watch?v=abc",
    ],
)
def test_youtube_adresleri_gecer(url):
    assert youtube._url_dogrula(url) == url


# --- indirme ---


def test_indirme_extract_audio_kullanmaz(monkeypatch, tmp_path):
    """Çift transcode kilidi: ses ham inmeli, dönüşümü whisper yolu yapmalı."""
    hedef = tmp_path / "ses"

    def _sahte_run(komut, **kwargs):
        (hedef).mkdir(parents=True, exist_ok=True)
        (hedef / "abc12345678.m4a").write_bytes(b"ses")
        return _SahteSonuc()

    monkeypatch.setattr(subprocess, "run", _sahte_run)
    video = youtube.YoutubeVideo(video_id="abc12345678")
    dosya = youtube.sesi_indir(video, hedef)
    assert dosya.name == "abc12345678.m4a"


def test_indirme_bayraklari(monkeypatch, tmp_path):
    cagrilar: list[list[str]] = []

    def _sahte_run(komut, **kwargs):
        cagrilar.append(list(komut))
        (tmp_path / "abc12345678.webm").write_bytes(b"ses")
        return _SahteSonuc()

    monkeypatch.setattr(subprocess, "run", _sahte_run)
    youtube.sesi_indir(youtube.YoutubeVideo(video_id="abc12345678"), tmp_path)
    komut = cagrilar[0]
    assert "bestaudio/best" in komut
    assert "--no-playlist" in komut
    assert "--extract-audio" not in komut
    assert "-x" not in komut
    assert "--max-filesize" in komut


def test_indirme_dosya_yoksa_boyut_hatasi(monkeypatch, tmp_path):
    monkeypatch.setattr(subprocess, "run", lambda komut, **k: _SahteSonuc())
    with pytest.raises(AlimHatasi, match="MB sınırını"):
        youtube.sesi_indir(youtube.YoutubeVideo(video_id="abc12345678"), tmp_path)


def test_yarim_inen_part_dosyasi_secilmez(monkeypatch, tmp_path):
    def _sahte_run(komut, **kwargs):
        (tmp_path / "abc12345678.m4a.part").write_bytes(b"yarim")
        return _SahteSonuc()

    monkeypatch.setattr(subprocess, "run", _sahte_run)
    with pytest.raises(AlimHatasi):
        youtube.sesi_indir(youtube.YoutubeVideo(video_id="abc12345678"), tmp_path)


# --- döküm ve transkript önbelleği ---


def _parcalar() -> list[Parca]:
    return [
        Parca(metin="Birinci soru mayoz bölünmeyle ilgili.", baslangic_sn=0.0, bitis_sn=4.0),
        Parca(metin="Cevap C şıkkıdır.", baslangic_sn=4.0, bitis_sn=7.0),
    ]


def test_dokum_transkripti_onbellege_yazar(monkeypatch, tmp_path):
    monkeypatch.setattr(
        subprocess, "run",
        lambda komut, **k: (
            (tmp_path / "youtube" / "ses").mkdir(parents=True, exist_ok=True),
            (tmp_path / "youtube" / "ses" / "abc12345678.m4a").write_bytes(b"ses"),
            _SahteSonuc(),
        )[2],
    )
    monkeypatch.setattr(
        "biyo_cozucu.alim.ses.sesi_yaziya_dok", lambda yol, **k: _parcalar()
    )
    video = youtube.YoutubeVideo(video_id="abc12345678", baslik="Test")
    kaynak = youtube.videoyu_dok(video, kok=tmp_path, sesi_sakla=True)
    assert kaynak.tur == "youtube"
    assert kaynak.imza == youtube.video_imzasi("abc12345678")
    assert "mayoz" in kaynak.metin
    assert youtube.transkript_yolu(tmp_path, "abc12345678").is_file()


def test_onbellek_varsa_indirme_hic_cagrilmaz(monkeypatch, tmp_path):
    yol = youtube.transkript_yolu(tmp_path, "abc12345678")
    yol.parent.mkdir(parents=True, exist_ok=True)
    yol.write_text(
        json.dumps({"parcalar": [{"metin": "önbellekten", "baslangic_sn": 0, "bitis_sn": 1}]}),
        encoding="utf-8",
    )

    def _patlat(*a, **k):
        raise AssertionError("Önbellek varken alt süreç çağrılmamalı.")

    monkeypatch.setattr(subprocess, "run", _patlat)
    kaynak = youtube.videoyu_dok(
        youtube.YoutubeVideo(video_id="abc12345678"), kok=tmp_path
    )
    assert kaynak.metin == "önbellekten"


def test_yeniden_bayragi_onbellegi_yok_sayar(monkeypatch, tmp_path):
    yol = youtube.transkript_yolu(tmp_path, "abc12345678")
    yol.parent.mkdir(parents=True, exist_ok=True)
    yol.write_text(json.dumps({"parcalar": [{"metin": "eski"}]}), encoding="utf-8")

    monkeypatch.setattr(
        subprocess, "run",
        lambda komut, **k: (
            (tmp_path / "youtube" / "ses").mkdir(parents=True, exist_ok=True),
            (tmp_path / "youtube" / "ses" / "abc12345678.m4a").write_bytes(b"s"),
            _SahteSonuc(),
        )[2],
    )
    monkeypatch.setattr(
        "biyo_cozucu.alim.ses.sesi_yaziya_dok", lambda yol, **k: _parcalar()
    )
    kaynak = youtube.videoyu_dok(
        youtube.YoutubeVideo(video_id="abc12345678"),
        kok=tmp_path, yeniden=True, sesi_sakla=True,
    )
    assert "mayoz" in kaynak.metin


def test_playlistte_tek_video_hatasi_akisi_durdurmaz(monkeypatch, tmp_path):
    iyi = youtube.YoutubeVideo(video_id="iyi00000000")
    kotu = youtube.YoutubeVideo(video_id="kotu0000000")

    def _sahte_dok(video, **kwargs):
        if video.video_id == "kotu0000000":
            raise AlimHatasi("bölge kilidi")
        from biyo_cozucu.alim.cikarim import Kaynak

        return Kaynak(ad="iyi", tur="youtube", imza=video.imza, parcalar=_parcalar())

    monkeypatch.setattr(youtube, "videoyu_dok", _sahte_dok)
    sonuclar, hatalar = youtube.dok_hepsi([kotu, iyi], kok=tmp_path)
    assert [v.video_id for v, _ in sonuclar] == ["iyi00000000"]
    assert len(hatalar) == 1 and "bölge kilidi" in hatalar[0]


def test_bozuk_onbellek_dosyasi_yeniden_dokume_duser(monkeypatch, tmp_path):
    yol = youtube.transkript_yolu(tmp_path, "abc12345678")
    yol.parent.mkdir(parents=True, exist_ok=True)
    yol.write_text("{bozuk json", encoding="utf-8")

    monkeypatch.setattr(
        subprocess, "run",
        lambda komut, **k: (
            (tmp_path / "youtube" / "ses").mkdir(parents=True, exist_ok=True),
            (tmp_path / "youtube" / "ses" / "abc12345678.m4a").write_bytes(b"s"),
            _SahteSonuc(),
        )[2],
    )
    monkeypatch.setattr(
        "biyo_cozucu.alim.ses.sesi_yaziya_dok", lambda yol, **k: _parcalar()
    )
    kaynak = youtube.videoyu_dok(
        youtube.YoutubeVideo(video_id="abc12345678"), kok=tmp_path, sesi_sakla=True
    )
    assert "mayoz" in kaynak.metin


def test_imza_video_kimliginden_kararli():
    ilk = youtube.video_imzasi("abc12345678")
    assert ilk == youtube.video_imzasi("abc12345678")
    assert ilk != youtube.video_imzasi("xyz98765432")
    assert len(ilk) == 16


def test_izleme_adresi_urlsiz_videoda_kurulur():
    video = youtube.YoutubeVideo(video_id="abc12345678")
    assert video.izleme_adresi().endswith("watch?v=abc12345678")


def test_transkript_yolu_kok_altinda(tmp_path: Path):
    yol = youtube.transkript_yolu(tmp_path, "abc")
    assert yol.parent == tmp_path / "youtube" / "transkript"


# --- Colab'den transkript içe aktarma ---


def _colab_ciktisi(tmp_path: Path, ad: str = "abc12345678.json", **degisiklik) -> Path:
    veri = {
        "video_id": "abc12345678",
        "baslik": "AYT Biyoloji full tekrar",
        "kanal": "Test Kanalı",
        "sure_sn": 35620.0,
        "parcalar": [
            {"metin": "Birinci soru mayozla ilgili.", "baslangic_sn": 12.5, "bitis_sn": 18.0},
            {"metin": "Cevap A şıkkıdır.", "baslangic_sn": 18.0, "bitis_sn": 21.5},
        ],
    }
    veri.update(degisiklik)
    yol = tmp_path / ad
    yol.write_text(json.dumps(veri, ensure_ascii=False), encoding="utf-8")
    return yol


def test_colab_transkripti_onbellege_kurulur(tmp_path):
    kaynak = _colab_ciktisi(tmp_path)
    kok = tmp_path / "veri"
    video_id, parca, sure = youtube.transkripti_ice_aktar(kaynak, kok)
    assert (video_id, parca) == ("abc12345678", 2)
    assert sure == 35620.0
    assert youtube.transkript_yolu(kok, "abc12345678").is_file()


def test_ice_aktarilan_transkript_indirmeyi_atlar(tmp_path, monkeypatch):
    """Asıl kazanç: `videoyu_dok` artık ne indiriyor ne döküyor."""
    kok = tmp_path / "veri"
    youtube.transkripti_ice_aktar(_colab_ciktisi(tmp_path), kok)

    def _patlat(*a, **k):
        raise AssertionError("içe aktarılmış transkript varken indirme yapılmamalı")

    monkeypatch.setattr(subprocess, "run", _patlat)
    kaynak = youtube.videoyu_dok(
        youtube.YoutubeVideo(video_id="abc12345678"), kok=kok
    )
    assert "mayozla" in kaynak.metin
    assert kaynak.parcalar[0].baslangic_sn == 12.5


def test_ingilizce_alan_adlari_da_okunur(tmp_path):
    """faster-whisper çıktısı `text`/`start`/`end` ile de gelebilir."""
    yol = tmp_path / "xyz98765432.json"
    yol.write_text(
        json.dumps({
            "video_id": "xyz98765432",
            "duration": 600,
            "parcalar": [{"text": "Mayoz bölünme", "start": 3.0, "end": 6.0}],
        }),
        encoding="utf-8",
    )
    video_id, parca, sure = youtube.transkripti_ice_aktar(yol, tmp_path / "veri")
    assert (video_id, parca, sure) == ("xyz98765432", 1, 600.0)


def test_video_id_yoksa_dosya_adindan_alinir(tmp_path):
    kaynak = _colab_ciktisi(tmp_path, ad="dosyaadi123.json")
    kaynak.write_text(
        json.dumps({"parcalar": [{"metin": "bir metin", "baslangic_sn": 0}]}),
        encoding="utf-8",
    )
    video_id, _, _ = youtube.transkripti_ice_aktar(kaynak, tmp_path / "veri")
    assert video_id == "dosyaadi123"


@pytest.mark.parametrize(
    ("govde", "desen"),
    [
        ("{bozuk", "okunamadı"),
        ('["liste"]', "JSON nesnesi"),
        ('{"video_id": "a", "parcalar": []}', "boş ya da yok"),
        ('{"video_id": "a", "parcalar": [{"metin": "   "}]}', "metni olan parça yok"),
    ],
)
def test_bozuk_transkript_anlamli_hata(tmp_path, govde, desen):
    yol = tmp_path / "bozuk.json"
    yol.write_text(govde, encoding="utf-8")
    with pytest.raises(AlimHatasi, match=desen):
        youtube.transkripti_ice_aktar(yol, tmp_path / "veri")
