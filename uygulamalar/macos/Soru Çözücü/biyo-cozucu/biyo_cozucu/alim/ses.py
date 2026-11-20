"""Ses ve videodan yazıya dökme (ffmpeg + whisper.cpp).

Python paketi yok, harici binary kullanılır. Gerekçe: `mlx-whisper` denendi
ve elendi — en güncel sürümü bile numpy 2.x ile bağdaşmayan eski bir
`numba`ya bağlanıp Python 3.12'de derlenmiyor. Bu makinede whisper.cpp
zaten derli ve Türkçe diktede doğrulanmış durumda, onu yeniden kullanıyoruz.

Yollar ortam değişkenleriyle değiştirilebilir:
  BIYO_FFMPEG          ffmpeg ikilisi
  BIYO_WHISPER_SERVER  whisper.cpp `whisper-server` ikilisi
  BIYO_WHISPER_MODEL   ggml model dosyası
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from pathlib import Path

from .cikarim import AlimHatasi, Parca

# whisper.cpp 16 kHz mono PCM bekler; başka bir biçim sessizce bozuk
# yazıya dönüşür, bu yüzden dönüştürme atlanabilir değil.
ORNEKLEME_HIZI = 16000

# Uzun kayıtlar bu süreli dilimler hâlinde dökülür. 15 dakika, dilim başına
# ~27 MB WAV demek: bellek sabit kalıyor ve ilerleme dilim dilim görülüyor.
DILIM_SANIYE = 900

_VARSAYILAN_FFMPEG = Path.home() / ".local/bin/ffmpeg"
_VARSAYILAN_WHISPER = (
    Path.home()
    / "Library/Application Support/KitapKatalog/models/whisper/bin/whisper-server"
)
_VARSAYILAN_MODEL = (
    Path.home()
    / "Library/Application Support/KitapKatalog/models/whisper/ggml-large-v3-turbo-q5_0.bin"
)

_sunucu_kilidi = threading.Lock()
_sunucu: subprocess.Popen | None = None
_sunucu_adresi = ""


def _ffmpeg_yolu() -> Path:
    ham = os.environ.get("BIYO_FFMPEG", "")
    if ham:
        return Path(ham)
    if _VARSAYILAN_FFMPEG.is_file():
        return _VARSAYILAN_FFMPEG
    bulunan = shutil.which("ffmpeg")
    if bulunan:
        return Path(bulunan)
    raise AlimHatasi(
        "ffmpeg bulunamadı. Ses/video alımı için gerekli; "
        "yolu BIYO_FFMPEG ile verebilirsiniz."
    )


def _whisper_yollari() -> tuple[Path, Path]:
    sunucu = Path(os.environ.get("BIYO_WHISPER_SERVER", "") or _VARSAYILAN_WHISPER)
    model = Path(os.environ.get("BIYO_WHISPER_MODEL", "") or _VARSAYILAN_MODEL)
    if not sunucu.is_file():
        raise AlimHatasi(
            f"whisper-server bulunamadı ({sunucu}). "
            "Yolu BIYO_WHISPER_SERVER ile verin."
        )
    if not model.is_file():
        raise AlimHatasi(
            f"Whisper modeli bulunamadı ({model}). "
            "Yolu BIYO_WHISPER_MODEL ile verin."
        )
    return sunucu, model


def _bos_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def _sunucuyu_baslat() -> str:
    """whisper-server'ı tembel başlatır ve adresini döndürür.

    Süreç boyunca tek örnek yaşar: model 574 MB, her dosya için yeniden
    yüklemek dakikalar götürürdü. `atexit` yerine daemon süreç + açık
    kapatma: uvicorn yeniden yüklendiğinde artık süreç kalmasın diye
    `kapat()` da sunulur.
    """
    global _sunucu, _sunucu_adresi
    with _sunucu_kilidi:
        if _sunucu is not None and _sunucu.poll() is None:
            return _sunucu_adresi

        ikili, model = _whisper_yollari()
        port = _bos_port()
        _sunucu = subprocess.Popen(  # noqa: S603 - yollar bizim denetimimizde
            [
                str(ikili),
                "--model", str(model),
                "--host", "127.0.0.1",
                "--port", str(port),
                "--language", "tr",
                "--threads", str(max(2, (os.cpu_count() or 4) - 2)),
                # Bölütleri token yerine SÖZCÜK sınırında kes. Varsayılan
                # (token) davranışta uzun cümleler kelime ortasından
                # bölünüyor ("gerçek\nleşir") ve ayrıştırıcı bozuk sözcük
                # görüyordu.
                "--split-on-word",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        _sunucu_adresi = f"http://127.0.0.1:{port}"

        # Model yüklenene kadar bekle; erken POST bağlantı hatası verir.
        son = time.time() + 120
        while time.time() < son:
            if _sunucu.poll() is not None:
                raise AlimHatasi("whisper-server beklenmedik biçimde kapandı.")
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=1):
                    return _sunucu_adresi
            except OSError:
                time.sleep(0.4)
        kapat()
        raise AlimHatasi("whisper-server 120 saniyede hazır olmadı.")


def kapat() -> None:
    """Yazıya dökme sunucusunu durdurur (test ve kapanış için)."""
    global _sunucu, _sunucu_adresi
    with _sunucu_kilidi:
        if _sunucu is not None and _sunucu.poll() is None:
            _sunucu.terminate()
            try:
                _sunucu.wait(timeout=10)
            except subprocess.TimeoutExpired:
                _sunucu.kill()
        _sunucu = None
        _sunucu_adresi = ""


def _wave_donustur(kaynak: Path, hedef: Path) -> None:
    """Herhangi bir ses/video dosyasını 16 kHz mono WAV'a çevirir."""
    komut = [
        str(_ffmpeg_yolu()),
        "-nostdin", "-y", "-loglevel", "error",
        "-i", str(kaynak),
        "-vn",                       # video akışını at
        "-ac", "1",                  # mono
        "-ar", str(ORNEKLEME_HIZI),
        "-c:a", "pcm_s16le",
        str(hedef),
    ]
    sonuc = subprocess.run(  # noqa: S603
        komut, capture_output=True, text=True, timeout=3600
    )
    if sonuc.returncode != 0 or not hedef.is_file():
        ayrinti = (sonuc.stderr or "").strip()[-400:]
        raise AlimHatasi(f"ffmpeg dönüştürmesi başarısız: {ayrinti}")


def _ses_suresi(wav: Path) -> float:
    """WAV dosyasının saniye cinsinden süresi (16 kHz mono, 16 bit)."""
    try:
        return wav.stat().st_size / (ORNEKLEME_HIZI * 2)
    except OSError:
        return 0.0


def _dokum_zaman_asimi(wav: Path) -> float:
    """Ses süresine göre ölçeklenen HTTP zaman aşımı.

    Sabit 1 saat, bir saati aşan videolarda yetmiyordu: 10 saatlik bir ders
    videosunun dökümü bu makinede ~100 dakika sürüyor ve istek tam ortasında
    düşüyordu. Döküm kabaca gerçek zamanın altıda biri hızında; sesin
    süresinin kendisini üst sınır yapmak yaklaşık 6 kat pay bırakıyor.
    """
    return max(3600.0, _ses_suresi(wav))


def _yaziya_dok(wav: Path) -> list[dict]:
    """whisper-server'a WAV gönderir, zaman damgalı bölütleri döndürür."""
    adres = _sunucuyu_baslat()
    sinir = "----biyo-cozucu-sinir"
    govde = bytearray()
    govde += f"--{sinir}\r\n".encode()
    govde += (
        b'Content-Disposition: form-data; name="file"; filename="ses.wav"\r\n'
        b"Content-Type: audio/wav\r\n\r\n"
    )
    govde += wav.read_bytes()
    govde += b"\r\n"
    # `verbose_json` zaman damgalı `segments` döndürür; sade `json` yalnız tek
    # bir `text` alanı veriyor ve tüm konum bilgisi kayboluyordu (9 dakikalık
    # bir video tek parça olarak geliyor, "bu soru 03:12'de" denemiyordu).
    # Sunucu bu biçimi tanımazsa aşağıdaki `segments` yokluğu yolu yine
    # devrede: davranış kötüleşmez.
    for ad, deger in (("response_format", "verbose_json"), ("language", "tr")):
        govde += f"--{sinir}\r\n".encode()
        govde += f'Content-Disposition: form-data; name="{ad}"\r\n\r\n{deger}\r\n'.encode()
    govde += f"--{sinir}--\r\n".encode()

    istek = urllib.request.Request(
        f"{adres}/inference",
        data=bytes(govde),
        headers={"Content-Type": f"multipart/form-data; boundary={sinir}"},
    )
    try:
        with urllib.request.urlopen(istek, timeout=_dokum_zaman_asimi(wav)) as yanit:
            veri = json.loads(yanit.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as exc:
        try:
            ayrinti = exc.read().decode("utf-8", errors="replace")[-300:]
        finally:
            exc.close()
        raise AlimHatasi(f"Yazıya dökme başarısız (HTTP {exc.code}): {ayrinti}") from exc
    except (OSError, json.JSONDecodeError) as exc:
        raise AlimHatasi(f"Yazıya dökme başarısız: {exc}") from exc

    bolutler = veri.get("segments")
    if isinstance(bolutler, list) and bolutler:
        return bolutler
    return [{"text": str(veri.get("text", "")), "start": 0.0, "end": 0.0}]


def _saniyeye_cevir(deger) -> float:
    """whisper.cpp bazı yapılarda "00:01:23,450" biçimi döndürür."""
    if isinstance(deger, (int, float)):
        return float(deger)
    metin = str(deger).strip().replace(",", ".")
    if not metin:
        return 0.0
    try:
        parcalar = [float(p) for p in metin.split(":")]
    except ValueError:
        return 0.0
    saniye = 0.0
    for parca in parcalar:
        saniye = saniye * 60 + parca
    return saniye


def _wavi_dilimle(wav: Path, dizin: Path) -> list[Path]:
    """WAV'ı sabit süreli parçalara böler (yeniden kodlama yok)."""
    kalip = dizin / "dilim%04d.wav"
    komut = [
        str(_ffmpeg_yolu()),
        "-nostdin", "-y", "-loglevel", "error",
        "-i", str(wav),
        "-f", "segment",
        "-segment_time", str(DILIM_SANIYE),
        "-c", "copy",
        str(kalip),
    ]
    sonuc = subprocess.run(komut, capture_output=True, text=True, timeout=3600)  # noqa: S603
    if sonuc.returncode != 0:
        ayrinti = (sonuc.stderr or "").strip()[-400:]
        raise AlimHatasi(f"Ses dilimlenemedi: {ayrinti}")
    dilimler = sorted(dizin.glob("dilim*.wav"))
    if not dilimler:
        raise AlimHatasi("Ses dilimlenemedi: dilim üretilmedi.")
    return dilimler


def sesi_yaziya_dok(
    yol: Path,
    *,
    video: bool = False,
    ilerleme: Callable[[int, int], None] | None = None,
) -> list[Parca]:
    """Ses/video dosyasını zaman damgalı metin parçalarına çevirir.

    Uzun kayıtlar DİLİMLENEREK dökülür. Tek parça göndermek üç şeyi birden
    bozuyordu: 10 saatlik bir ders videosunun 1 GB'lık WAV'ı olduğu gibi
    belleğe okunuyor (üstüne multipart gövdesi için bir kopya daha), tek HTTP
    isteği saatlerce açık kalıyor ve iş yarıda koparsa baştan başlanıyordu.
    Dilim başına bellek ~27 MB ve her dilim bittiğinde ilerleme bildirilebiliyor.
    """
    bolutler: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="biyo-alim-") as gecici:
        gecici_dizin = Path(gecici)
        wav = gecici_dizin / "ses.wav"
        _wave_donustur(yol, wav)

        # Kısa kayıtta dilimleme gereksiz maliyet; sınır 1,5 dilim.
        if _ses_suresi(wav) <= DILIM_SANIYE * 1.5:
            if ilerleme is not None:
                ilerleme(1, 1)
            bolutler = _yaziya_dok(wav)
        else:
            dilim_dizini = gecici_dizin / "dilimler"
            dilim_dizini.mkdir()
            dilimler = _wavi_dilimle(wav, dilim_dizini)
            # WAV başlığı gerekmediğinden asıl dosya erken silinebilir:
            # 40 dilim + 1 GB'lık asıl dosyayı aynı anda tutmak diski zorlar.
            wav.unlink(missing_ok=True)
            for sira, dilim in enumerate(dilimler):
                if ilerleme is not None:
                    ilerleme(sira + 1, len(dilimler))
                kayma = sira * DILIM_SANIYE
                for bolut in _yaziya_dok(dilim):
                    # Zaman damgaları dilim içinde sıfırdan başlıyor; kayıttaki
                    # gerçek ana taşınmazsa tüm derin bağlantılar yanlış olur.
                    bolut = dict(bolut)
                    bolut["start"] = _saniyeye_cevir(bolut.get("start", 0.0)) + kayma
                    bolut["end"] = _saniyeye_cevir(bolut.get("end", 0.0)) + kayma
                    bolutler.append(bolut)
                dilim.unlink(missing_ok=True)

    parcalar: list[Parca] = []
    for bolut in bolutler:
        metin = str(bolut.get("text", "")).strip()
        if not metin:
            continue
        parcalar.append(
            Parca(
                metin=metin,
                baslangic_sn=_saniyeye_cevir(bolut.get("start", 0.0)),
                bitis_sn=_saniyeye_cevir(bolut.get("end", 0.0)),
            )
        )
    if not parcalar:
        parcalar = [Parca(metin="", baslangic_sn=0.0, bitis_sn=0.0)]
    return parcalar
