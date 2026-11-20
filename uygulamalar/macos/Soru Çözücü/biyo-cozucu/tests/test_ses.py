"""Ses/video yazıya dökme testleri: yol çözümleme, sunucu tekilliği, biçim dönüşümü.

Hepsi çevrimdışı ve deterministik: gerçek ffmpeg/whisper-server hiçbir zaman
çalıştırılmaz. `subprocess.Popen`/`subprocess.run` ve `urllib.request.urlopen`
çağrıları monkeypatch ile yakalanır; asıl sınanan şey çağrının NASIL
kurulduğu (hangi bayraklar, hangi argümanlar).
"""

from __future__ import annotations

import io
import json
import subprocess
import urllib.error
from pathlib import Path

import pytest

from biyo_cozucu.alim import ses
from biyo_cozucu.alim.cikarim import AlimHatasi


class _SahteBaglanti:
    """`socket.create_connection`'ın `with` bloğuyla kullanılan sahte yanıtı."""

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class _SahteSurec:
    """`subprocess.Popen` yerine geçen, hiçbir gerçek süreç başlatmayan taklit."""

    def __init__(self):
        self._sonlandi = False

    def poll(self):
        return 0 if self._sonlandi else None

    def terminate(self):
        self._sonlandi = True

    def wait(self, timeout=None):
        return 0

    def kill(self):
        self._sonlandi = True


class _SahteYanit:
    """`urllib.request.urlopen`'ın `with` bloğuyla kullanılan sahte HTTP yanıtı."""

    def __init__(self, govde: bytes):
        self._govde = govde

    def read(self):
        return self._govde

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def _hazir_whisper_ortami(tmp_path, monkeypatch):
    """Whisper yollarını geçerli sahte dosyalara bağlar (gerçek ikili aranmaz).

    Ev sahibi makinede zaten kurulu bir whisper-server/model olabilir; testler
    ona bağımlı olmasın diye BIYO_WHISPER_* hep açıkça ayarlanır.
    """
    sunucu = tmp_path / "whisper-server"
    model = tmp_path / "ggml-model.bin"
    sunucu.write_text("")
    model.write_text("")
    monkeypatch.setenv("BIYO_WHISPER_SERVER", str(sunucu))
    monkeypatch.setenv("BIYO_WHISPER_MODEL", str(model))
    return sunucu, model


@pytest.fixture(autouse=True)
def _sunucu_durumunu_sifirla(monkeypatch):
    """Modüldeki tembel sunucu global'lerini (`_sunucu`, `_sunucu_adresi`) temizler.

    Bu durum süreç boyunca yaşar; bir test onu doldurursa sonraki test
    kirlenmiş başlangıç durumuyla karşılaşır ve yanlış "zaten başladı"
    sonucuna varabilir.
    """
    monkeypatch.setattr(ses, "_sunucu", None)
    monkeypatch.setattr(ses, "_sunucu_adresi", "")
    yield
    ses.kapat()


# --- yol çözümleme: ffmpeg ---


def test_ffmpeg_yolu_ortam_degiskeninden_okunur(monkeypatch):
    monkeypatch.setenv("BIYO_FFMPEG", "/ozel/yol/ffmpeg")
    assert ses._ffmpeg_yolu() == Path("/ozel/yol/ffmpeg")


def test_ffmpeg_yolu_varsayilan_dosyaya_duser(monkeypatch, tmp_path):
    monkeypatch.delenv("BIYO_FFMPEG", raising=False)
    sahte = tmp_path / "ffmpeg"
    sahte.write_text("")
    monkeypatch.setattr(ses, "_VARSAYILAN_FFMPEG", sahte)
    assert ses._ffmpeg_yolu() == sahte


def test_ffmpeg_yolu_path_ortam_degiskeninden_bulunur(monkeypatch, tmp_path):
    monkeypatch.delenv("BIYO_FFMPEG", raising=False)
    monkeypatch.setattr(ses, "_VARSAYILAN_FFMPEG", tmp_path / "yok")
    monkeypatch.setattr(ses.shutil, "which", lambda ad: "/usr/bin/ffmpeg")
    assert ses._ffmpeg_yolu() == Path("/usr/bin/ffmpeg")


def test_ffmpeg_hicbir_yerde_yoksa_env_adini_anan_hata_verir(monkeypatch, tmp_path):
    monkeypatch.delenv("BIYO_FFMPEG", raising=False)
    monkeypatch.setattr(ses, "_VARSAYILAN_FFMPEG", tmp_path / "yok")
    monkeypatch.setattr(ses.shutil, "which", lambda ad: None)
    with pytest.raises(AlimHatasi, match="BIYO_FFMPEG"):
        ses._ffmpeg_yolu()


# --- yol çözümleme: whisper sunucusu ve modeli ---


def test_whisper_yollari_ortam_degiskenlerinden_okunur(tmp_path, monkeypatch):
    sunucu, model = _hazir_whisper_ortami(tmp_path, monkeypatch)
    bulunan_sunucu, bulunan_model = ses._whisper_yollari()
    assert bulunan_sunucu == sunucu
    assert bulunan_model == model


def test_whisper_sunucu_bulunamayinca_env_adini_anan_hata_verir(tmp_path, monkeypatch):
    _hazir_whisper_ortami(tmp_path, monkeypatch)
    monkeypatch.setenv("BIYO_WHISPER_SERVER", str(tmp_path / "yok"))
    with pytest.raises(AlimHatasi, match="BIYO_WHISPER_SERVER"):
        ses._whisper_yollari()


def test_whisper_modeli_bulunamayinca_env_adini_anan_hata_verir(tmp_path, monkeypatch):
    _hazir_whisper_ortami(tmp_path, monkeypatch)
    monkeypatch.setenv("BIYO_WHISPER_MODEL", str(tmp_path / "yok.bin"))
    with pytest.raises(AlimHatasi, match="BIYO_WHISPER_MODEL"):
        ses._whisper_yollari()


# --- sunucu başlatma: --split-on-word bayrağı ---


def test_sunucu_baslatma_komutu_split_on_word_bayragini_icerir(tmp_path, monkeypatch):
    """Regresyon kilidi: bu bayrak olmadan whisper.cpp cümleyi kelime
    ortasından kesiyor ("gerçek\\nleşir") ve soru ayrıştırıcısı bozuk sözcük
    görüyordu. Sunucu her başlatıldığında komutta gerçekten geçmeli.
    """
    _hazir_whisper_ortami(tmp_path, monkeypatch)
    monkeypatch.setattr(ses, "_bos_port", lambda: 45123)
    monkeypatch.setattr(
        ses.socket, "create_connection", lambda *a, **k: _SahteBaglanti()
    )
    kaydedilen = {}

    def sahte_popen(komut, **kwargs):
        kaydedilen["komut"] = komut
        return _SahteSurec()

    monkeypatch.setattr(ses.subprocess, "Popen", sahte_popen)

    ses._sunucuyu_baslat()

    assert "--split-on-word" in kaydedilen["komut"]


def test_sunucu_erken_kapanirsa_anlamli_hata_verir(tmp_path, monkeypatch):
    _hazir_whisper_ortami(tmp_path, monkeypatch)
    monkeypatch.setattr(ses, "_bos_port", lambda: 45124)

    class _HemenBiten(_SahteSurec):
        def poll(self):
            return 1  # süreç Popen'dan hemen sonra sonlanmış gibi davran

    monkeypatch.setattr(ses.subprocess, "Popen", lambda *a, **k: _HemenBiten())

    with pytest.raises(AlimHatasi, match="beklenmedik biçimde kapandı"):
        ses._sunucuyu_baslat()


# --- ffmpeg dönüştürme: 16 kHz mono ---


def test_wave_donusturme_komutu_16khz_mono_tasir(tmp_path, monkeypatch):
    """whisper.cpp 16 kHz mono PCM bekler; başka bir biçim sessizce bozuk
    yazıya dönüşür (bkz. ORNEKLEME_HIZI yorumu) — komutta bu argümanlar
    gerçekten olmalı.
    """
    monkeypatch.setenv("BIYO_FFMPEG", "/sahte/ffmpeg")
    kaynak = tmp_path / "kayit.mp3"
    kaynak.write_bytes(b"sahte ses verisi")
    hedef = tmp_path / "ses.wav"
    kaydedilen = {}

    def sahte_run(komut, **kwargs):
        kaydedilen["komut"] = komut
        hedef.write_bytes(b"RIFF....WAVEfmt ")
        return subprocess.CompletedProcess(komut, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(ses.subprocess, "run", sahte_run)

    ses._wave_donustur(kaynak, hedef)

    komut = kaydedilen["komut"]
    assert komut[0] == "/sahte/ffmpeg"
    assert komut[komut.index("-ar") + 1] == str(ses.ORNEKLEME_HIZI)
    assert komut[komut.index("-ac") + 1] == "1"


def test_wave_donusturme_basarisiz_olunca_stderr_ile_hata_verir(tmp_path, monkeypatch):
    monkeypatch.setenv("BIYO_FFMPEG", "/sahte/ffmpeg")
    kaynak = tmp_path / "kayit.mp3"
    kaynak.write_bytes(b"x")
    hedef = tmp_path / "ses.wav"

    def sahte_run(komut, **kwargs):
        return subprocess.CompletedProcess(
            komut, returncode=1, stdout="", stderr="kodek bulunamadı"
        )

    monkeypatch.setattr(ses.subprocess, "run", sahte_run)

    with pytest.raises(AlimHatasi, match="ffmpeg dönüştürmesi başarısız"):
        ses._wave_donustur(kaynak, hedef)


# --- sunucu tekilliği ---


def test_sunucu_ikinci_cagrida_yeniden_baslatilmaz(tmp_path, monkeypatch):
    """Model 574 MB; her çağrıda yeniden yüklemek dakikalar sürerdi. Süreç
    boyunca tek örnek yaşamalı.
    """
    _hazir_whisper_ortami(tmp_path, monkeypatch)
    monkeypatch.setattr(ses, "_bos_port", lambda: 45125)
    monkeypatch.setattr(
        ses.socket, "create_connection", lambda *a, **k: _SahteBaglanti()
    )
    baslatma_sayisi = 0

    def sahte_popen(komut, **kwargs):
        nonlocal baslatma_sayisi
        baslatma_sayisi += 1
        return _SahteSurec()

    monkeypatch.setattr(ses.subprocess, "Popen", sahte_popen)

    ilk_adres = ses._sunucuyu_baslat()
    ikinci_adres = ses._sunucuyu_baslat()

    assert baslatma_sayisi == 1
    assert ilk_adres == ikinci_adres


def test_kapat_sonrasi_durum_sifirlanir_ve_yeniden_baslatilabilir(tmp_path, monkeypatch):
    _hazir_whisper_ortami(tmp_path, monkeypatch)
    monkeypatch.setattr(ses, "_bos_port", lambda: 45126)
    monkeypatch.setattr(
        ses.socket, "create_connection", lambda *a, **k: _SahteBaglanti()
    )
    baslatma_sayisi = 0

    def sahte_popen(komut, **kwargs):
        nonlocal baslatma_sayisi
        baslatma_sayisi += 1
        return _SahteSurec()

    monkeypatch.setattr(ses.subprocess, "Popen", sahte_popen)

    ses._sunucuyu_baslat()
    ses.kapat()

    assert ses._sunucu is None
    assert ses._sunucu_adresi == ""

    ses._sunucuyu_baslat()
    assert baslatma_sayisi == 2, "kapat() sonrası yeni çağrı süreci yeniden başlatmalı"


# --- zaman damgası çevirme ---


@pytest.mark.parametrize(
    "deger,beklenen",
    [
        (12.5, 12.5),
        (7, 7.0),
        ("5,5", 5.5),  # whisper.cpp bazı yapılarda virgülü ondalık ayırıcı kullanır
        ("00:01:23,450", 83.45),  # saat:dakika:saniye,ms
        ("01:00:00,000", 3600.0),  # saat taşması
        ("", 0.0),
        ("bozuk:veri", 0.0),  # sayıya çevrilemeyen parça sessizce 0'a düşer
    ],
)
def test_saniyeye_cevir_bicimleri_dogru_hesaplar(deger, beklenen):
    assert ses._saniyeye_cevir(deger) == pytest.approx(beklenen)


# --- uçtan uca: yazıya dökümden Parça üretimi ---


def test_sesi_yaziya_dok_parcalari_zaman_damgasiyla_uretir(tmp_path, monkeypatch):
    """Parça.baslangic_sn dolu olmalı ve konum() atıf zincirinin beklediği
    "DD:DD" biçimini vermeli.
    """
    monkeypatch.setenv("BIYO_FFMPEG", "/sahte/ffmpeg")
    monkeypatch.setattr(ses, "_sunucuyu_baslat", lambda: "http://127.0.0.1:9999")

    def sahte_run(komut, **kwargs):
        Path(komut[-1]).write_bytes(b"RIFF....WAVEfmt ")
        return subprocess.CompletedProcess(komut, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(ses.subprocess, "run", sahte_run)

    govde = json.dumps(
        {
            "segments": [
                {"text": "Birinci parça.", "start": 0.0, "end": 5.0},
                {"text": "İkinci parça.", "start": 65.0, "end": 70.0},
            ]
        }
    ).encode("utf-8")
    monkeypatch.setattr(
        ses.urllib.request, "urlopen", lambda *a, **k: _SahteYanit(govde)
    )

    kaynak = tmp_path / "ders.mp4"
    kaynak.write_bytes(b"sahte video")
    parcalar = ses.sesi_yaziya_dok(kaynak)

    assert len(parcalar) == 2
    assert parcalar[0].metin == "Birinci parça."
    assert parcalar[0].baslangic_sn == 0.0
    assert parcalar[1].baslangic_sn == 65.0
    assert parcalar[1].konum() == "01:05"


def test_bos_metinli_bolutler_atlanir(tmp_path, monkeypatch):
    """Whisper'ın sessizlik için ürettiği boş metinli bölütler sonuca girmemeli."""
    monkeypatch.setenv("BIYO_FFMPEG", "/sahte/ffmpeg")
    monkeypatch.setattr(ses, "_sunucuyu_baslat", lambda: "http://127.0.0.1:9999")

    def sahte_run(komut, **kwargs):
        Path(komut[-1]).write_bytes(b"x")
        return subprocess.CompletedProcess(komut, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(ses.subprocess, "run", sahte_run)

    govde = json.dumps(
        {
            "segments": [
                {"text": "   ", "start": 0.0, "end": 1.0},
                {"text": "Gerçek metin.", "start": 1.0, "end": 2.0},
            ]
        }
    ).encode("utf-8")
    monkeypatch.setattr(
        ses.urllib.request, "urlopen", lambda *a, **k: _SahteYanit(govde)
    )

    kaynak = tmp_path / "ders.mp3"
    kaynak.write_bytes(b"x")
    parcalar = ses.sesi_yaziya_dok(kaynak)

    assert len(parcalar) == 1
    assert parcalar[0].metin == "Gerçek metin."


def test_segments_yoksa_tum_metin_tek_parca_olur(tmp_path, monkeypatch):
    """whisper-server bazı yapılandırmalarda `segments` yerine düz `text` döner."""
    monkeypatch.setenv("BIYO_FFMPEG", "/sahte/ffmpeg")
    monkeypatch.setattr(ses, "_sunucuyu_baslat", lambda: "http://127.0.0.1:9999")

    def sahte_run(komut, **kwargs):
        Path(komut[-1]).write_bytes(b"x")
        return subprocess.CompletedProcess(komut, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(ses.subprocess, "run", sahte_run)

    govde = json.dumps({"text": "Bölütsüz tam metin."}).encode("utf-8")
    monkeypatch.setattr(
        ses.urllib.request, "urlopen", lambda *a, **k: _SahteYanit(govde)
    )

    kaynak = tmp_path / "ders.mp3"
    kaynak.write_bytes(b"x")
    parcalar = ses.sesi_yaziya_dok(kaynak)

    assert len(parcalar) == 1
    assert parcalar[0].metin == "Bölütsüz tam metin."
    assert parcalar[0].baslangic_sn == 0.0


def test_verbose_json_istenir(tmp_path, monkeypatch):
    """Sade `json` yalnız tek `text` alanı döndürüp tüm zaman damgalarını
    kaybettiriyordu; `segments` için `verbose_json` gerekiyor."""
    monkeypatch.setattr(ses, "_sunucuyu_baslat", lambda: "http://127.0.0.1:9999")
    wav = tmp_path / "ses.wav"
    wav.write_bytes(b"RIFF" * 100)
    yakalanan = {}

    def sahte_urlopen(istek, **kwargs):
        yakalanan["govde"] = istek.data
        return _SahteYanit(json.dumps({"segments": [
            {"text": "bir", "start": 0.0, "end": 1.0}
        ]}).encode("utf-8"))

    monkeypatch.setattr(ses.urllib.request, "urlopen", sahte_urlopen)
    ses._yaziya_dok(wav)
    assert b"verbose_json" in yakalanan["govde"]


def test_uzun_ses_dilimlenir_ve_damgalar_kaydirilir(tmp_path, monkeypatch):
    """Tek parça göndermek 10 saatlik videoda 1 GB'ı belleğe alıyordu.

    Dilim içindeki damgalar sıfırdan başlar; kaydırılmazsa tüm derin
    bağlantılar yanlış ana gider.
    """
    monkeypatch.setenv("BIYO_FFMPEG", "/sahte/ffmpeg")
    monkeypatch.setattr(ses, "_sunucuyu_baslat", lambda: "http://127.0.0.1:9999")

    def sahte_run(komut, **kwargs):
        cikti = Path(komut[-1])
        if "segment" in komut:
            # 3 dilim üret (kalıp: dilim%04d.wav)
            for sira in range(3):
                (cikti.parent / f"dilim{sira:04d}.wav").write_bytes(b"d")
        else:
            # Dönüştürme: 40 dakikalık ses → dilimleme eşiğini aşar.
            cikti.write_bytes(b"x" * (ses.ORNEKLEME_HIZI * 2 * 40 * 60))
        return subprocess.CompletedProcess(komut, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(ses.subprocess, "run", sahte_run)

    cagri = {"adet": 0}

    def sahte_urlopen(istek, **kwargs):
        cagri["adet"] += 1
        govde = json.dumps({"segments": [
            {"text": f"dilim {cagri['adet']}", "start": 5.0, "end": 9.0}
        ]}).encode("utf-8")
        return _SahteYanit(govde)

    monkeypatch.setattr(ses.urllib.request, "urlopen", sahte_urlopen)

    ilerlemeler: list[tuple[int, int]] = []
    kaynak = tmp_path / "uzun.mp3"
    kaynak.write_bytes(b"x")
    parcalar = ses.sesi_yaziya_dok(kaynak, ilerleme=lambda d, t: ilerlemeler.append((d, t)))

    assert cagri["adet"] == 3, "her dilim ayrı istekle gönderilmeli"
    assert ilerlemeler == [(1, 3), (2, 3), (3, 3)]
    # Damgalar dilim numarasına göre 900 saniye kaydırılmış olmalı.
    assert [p.baslangic_sn for p in parcalar] == [5.0, 905.0, 1805.0]
    assert [p.bitis_sn for p in parcalar] == [9.0, 909.0, 1809.0]


def test_kisa_ses_dilimlenmez(tmp_path, monkeypatch):
    monkeypatch.setenv("BIYO_FFMPEG", "/sahte/ffmpeg")
    monkeypatch.setattr(ses, "_sunucuyu_baslat", lambda: "http://127.0.0.1:9999")
    komutlar: list[list[str]] = []

    def sahte_run(komut, **kwargs):
        komutlar.append(komut)
        Path(komut[-1]).write_bytes(b"x" * (ses.ORNEKLEME_HIZI * 2 * 60))  # 1 dk
        return subprocess.CompletedProcess(komut, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(ses.subprocess, "run", sahte_run)
    monkeypatch.setattr(
        ses.urllib.request, "urlopen",
        lambda *a, **k: _SahteYanit(json.dumps({"segments": [
            {"text": "kısa", "start": 1.0, "end": 2.0}
        ]}).encode("utf-8")),
    )

    kaynak = tmp_path / "kisa.mp3"
    kaynak.write_bytes(b"x")
    parcalar = ses.sesi_yaziya_dok(kaynak)
    assert [p.baslangic_sn for p in parcalar] == [1.0]
    assert not any("segment" in k for k in komutlar), "kısa seste dilimleme yapılmamalı"


def test_cli_bitisinde_dokum_sunucusu_kapatilir(monkeypatch):
    """Kapatılmayan sunucu, 574 MB'lık modeli tutan artık süreç bırakıyordu."""
    from biyo_cozucu import cli

    kapatildi = {"adet": 0}
    monkeypatch.setattr(ses, "kapat", lambda: kapatildi.__setitem__("adet", 1))
    # `ses` modülü zaten yüklü; `main` onu sys.modules üzerinden bulmalı.
    monkeypatch.setattr(cli, "ayristirici", lambda: _SahteAyristirici())
    cli.main([])
    assert kapatildi["adet"] == 1


def test_cli_hata_atsa_da_sunucu_kapatilir(monkeypatch):
    from biyo_cozucu import cli

    kapatildi = {"adet": 0}
    monkeypatch.setattr(ses, "kapat", lambda: kapatildi.__setitem__("adet", 1))
    monkeypatch.setattr(cli, "ayristirici", lambda: _SahteAyristirici(patlat=True))
    with pytest.raises(RuntimeError):
        cli.main([])
    assert kapatildi["adet"] == 1


class _SahteAyristirici:
    """`main`in çağırdığı en küçük ayrıştırıcı taklidi."""

    def __init__(self, *, patlat: bool = False):
        self._patlat = patlat

    def parse_args(self, argv):
        def islev(_argumanlar):
            if self._patlat:
                raise RuntimeError("komut çöktü")
            return 0

        return type("Argumanlar", (), {"islev": staticmethod(islev)})()


def test_dokum_zaman_asimi_ses_suresiyle_olceklenir(tmp_path):
    """Sabit 1 saat, 10 saatlik bir ders videosunun ortasında düşüyordu."""
    kisa = tmp_path / "kisa.wav"
    kisa.write_bytes(b"x" * (ses.ORNEKLEME_HIZI * 2 * 60))          # 1 dk
    uzun = tmp_path / "uzun.wav"
    uzun.write_bytes(b"x" * (ses.ORNEKLEME_HIZI * 2 * 6 * 3600))    # 6 saat

    assert ses._dokum_zaman_asimi(kisa) == 3600.0, "kısa seste taban korunmalı"
    assert ses._dokum_zaman_asimi(uzun) == pytest.approx(6 * 3600, rel=0.01)


def test_yaziya_dokme_http_hatasi_anlamli_mesaja_donusur(tmp_path, monkeypatch):
    monkeypatch.setattr(ses, "_sunucuyu_baslat", lambda: "http://127.0.0.1:9999")
    wav = tmp_path / "ses.wav"
    wav.write_bytes(b"RIFF")

    def patlayan_urlopen(*args, **kwargs):
        raise urllib.error.HTTPError(
            "http://127.0.0.1:9999/inference",
            500,
            "Internal Error",
            None,
            io.BytesIO(b"model yuklenemedi"),
        )

    monkeypatch.setattr(ses.urllib.request, "urlopen", patlayan_urlopen)

    with pytest.raises(AlimHatasi, match="Yazıya dökme başarısız"):
        ses._yaziya_dok(wav)
