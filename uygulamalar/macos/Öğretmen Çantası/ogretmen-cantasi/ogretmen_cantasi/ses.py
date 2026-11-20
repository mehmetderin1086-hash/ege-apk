"""Ses kaydını yazıya döker (whisper.cpp).

Bu Mac'te whisper.cpp zaten kurulu (KitapKatalog için derlenmiş statik
`whisper-server` + `ggml-large-v3-turbo` modeli); yeniden kurmak yerine aynı
kurulum kullanılıyor. Yollar ortam değişkenleriyle değiştirilebilir.

Ses katmanı ZORUNLU DEĞİL: whisper bulunamazsa sesli yoklama kapanır, tek tık
listesi çalışmaya devam eder. Bu yüzden burada içe aktarma hatası değil,
anlaşılır bir istisna üretilir.
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path

VARSAYILAN_FFMPEG = Path.home() / ".local/bin/ffmpeg"
VARSAYILAN_WHISPER = (
    Path.home() / "Library/Application Support/KitapKatalog/models/whisper/bin/whisper-server"
)
VARSAYILAN_MODEL = (
    Path.home()
    / "Library/Application Support/KitapKatalog/models/whisper/ggml-large-v3-turbo-q5_0.bin"
)

_sunucu: subprocess.Popen | None = None
_adres: str = ""


class SesKullanilamiyor(RuntimeError):
    """whisper.cpp ya da ffmpeg bulunamadı."""


@dataclass(frozen=True)
class Durum:
    kullanilabilir: bool
    aciklama: str


def _yol(cevre_degiskeni: str, varsayilan: Path) -> Path:
    ozel = os.environ.get(cevre_degiskeni, "").strip()
    return Path(ozel).expanduser() if ozel else varsayilan


def durum() -> Durum:
    """Sesli yoklamanın kullanılabilir olup olmadığını söyler."""
    ffmpeg = _yol("OGRETMEN_FFMPEG", VARSAYILAN_FFMPEG)
    sunucu = _yol("OGRETMEN_WHISPER_SERVER", VARSAYILAN_WHISPER)
    model = _yol("OGRETMEN_WHISPER_MODEL", VARSAYILAN_MODEL)
    eksikler = [
        ad
        for ad, y in (("ffmpeg", ffmpeg), ("whisper-server", sunucu), ("model", model))
        if not y.exists()
    ]
    if eksikler:
        return Durum(False, "Bulunamadı: " + ", ".join(eksikler))
    return Durum(True, "Hazır")


def _bos_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _sunucuyu_baslat() -> str:
    global _sunucu, _adres
    if _sunucu is not None and _sunucu.poll() is None:
        return _adres

    bilgi = durum()
    if not bilgi.kullanilabilir:
        raise SesKullanilamiyor(
            f"Sesli yoklama kullanılamıyor. {bilgi.aciklama}. "
            "Yolları OGRETMEN_WHISPER_SERVER / OGRETMEN_WHISPER_MODEL ile verebilirsiniz."
        )

    port = _bos_port()
    sunucu_yolu = _yol("OGRETMEN_WHISPER_SERVER", VARSAYILAN_WHISPER)
    model_yolu = _yol("OGRETMEN_WHISPER_MODEL", VARSAYILAN_MODEL)
    _sunucu = subprocess.Popen(  # noqa: S603 - yollar bu modülün denetiminde
        [
            str(sunucu_yolu),
            "--model", str(model_yolu),
            "--host", "127.0.0.1",
            "--port", str(port),
            "--language", "tr",
            # Varsayılan bölütleme kelimeyi ortadan kırıyor; ad eşleştirmesi
            # bozuk sözcükle çalışamaz (kardeş projede aynı tuzağa düşülmüştü).
            "--split-on-word",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    _adres = f"http://127.0.0.1:{port}"

    for _ in range(120):
        if _sunucu.poll() is not None:
            raise SesKullanilamiyor("whisper-server başlatılamadı.")
        try:
            with urllib.request.urlopen(_adres, timeout=1):  # noqa: S310 - yerel adres
                return _adres
        except (urllib.error.URLError, OSError):
            time.sleep(0.5)
    raise SesKullanilamiyor("whisper-server 60 saniyede hazır olmadı.")


def kapat() -> None:
    global _sunucu
    if _sunucu is not None and _sunucu.poll() is None:
        _sunucu.terminate()
        try:
            _sunucu.wait(timeout=5)
        except subprocess.TimeoutExpired:
            _sunucu.kill()
    _sunucu = None


def _wave_donustur(kaynak: Path, hedef: Path) -> None:
    ffmpeg = _yol("OGRETMEN_FFMPEG", VARSAYILAN_FFMPEG)
    subprocess.run(  # noqa: S603 - komut sabit, yollar bizim
        [str(ffmpeg), "-y", "-i", str(kaynak), "-ar", "16000", "-ac", "1", "-f", "wav", str(hedef)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def yaziya_dok(ses_verisi: bytes, *, uzanti: str = ".webm") -> str:
    """Tarayıcıdan gelen ses kaydını Türkçe metne çevirir."""
    adres = _sunucuyu_baslat()
    with tempfile.TemporaryDirectory(prefix="ogretmen-ses-") as gecici_ham:
        gecici = Path(gecici_ham)
        ham = gecici / f"kayit{uzanti}"
        ham.write_bytes(ses_verisi)
        wav = gecici / "kayit.wav"
        _wave_donustur(ham, wav)

        sinir = uuid.uuid4().hex
        govde = bytearray()
        for ad, deger in (("temperature", "0.0"), ("response_format", "json"), ("language", "tr")):
            govde += (
                f"--{sinir}\r\nContent-Disposition: form-data; name=\"{ad}\"\r\n\r\n{deger}\r\n"
            ).encode()
        govde += (
            f'--{sinir}\r\nContent-Disposition: form-data; name="file"; filename="kayit.wav"\r\n'
            "Content-Type: audio/wav\r\n\r\n"
        ).encode()
        govde += wav.read_bytes() + b"\r\n" + f"--{sinir}--\r\n".encode()

        istek = urllib.request.Request(  # noqa: S310 - adres yerel whisper sunucusu
            f"{adres}/inference",
            data=bytes(govde),
            headers={"Content-Type": f"multipart/form-data; boundary={sinir}"},
        )
        with urllib.request.urlopen(istek, timeout=300) as yanit:  # noqa: S310 - yerel adres
            veri = json.loads(yanit.read().decode("utf-8"))
    return (veri.get("text") or "").strip()
