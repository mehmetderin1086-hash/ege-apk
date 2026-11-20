"""Ses katmanının testleri — sahte whisper-server ve sahte ffmpeg ile.

Gerçek model 574 MB ve testte koşturulamaz; ama sunucu başlatma, bekleme,
multipart gönderim ve JSON çözme yolu (ses.py'nin asıl gövdesi) sahte bir
HTTP sunucusuyla uçtan uca test edilebilir. Ses hattının test edilmeyen tek
kısmı gerçek modelin çıktısı kalır.
"""

from __future__ import annotations

import os
import stat
from pathlib import Path

import pytest

from ogretmen_cantasi import ses as ses_modulu

SAHTE_SUNUCU = """#!/usr/bin/env python3
import argparse, json
from http.server import BaseHTTPRequestHandler, HTTPServer

p = argparse.ArgumentParser()
p.add_argument("--model"); p.add_argument("--host"); p.add_argument("--port", type=int)
p.add_argument("--language"); p.add_argument("--split-on-word", action="store_true")
a = p.parse_args()


class Istekci(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")

    def do_POST(self):
        boy = int(self.headers.get("Content-Length", 0))
        govde = self.rfile.read(boy)
        # multipart gövdesi gerçekten ulaşmış mı? (dosya alanı + wav imzası)
        metin = " Ayşe Yılmaz yok. " if b"kayit.wav" in govde and b"RIFF" in govde else ""
        veri = json.dumps({"text": metin}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(veri)

    def log_message(self, *args):
        pass


HTTPServer((a.host, a.port), Istekci).serve_forever()
"""

SAHTE_FFMPEG = """#!/bin/sh
# Son argüman hedef dosyadır; wav imzasıyla sahte çıktı üret.
for son in "$@"; do :; done
printf 'RIFFsahte-wav' > "$son"
"""


def _calistirilebilir(yol: Path, icerik: str) -> Path:
    yol.write_text(icerik, encoding="utf-8")
    yol.chmod(yol.stat().st_mode | stat.S_IXUSR)
    return yol


@pytest.fixture
def sahte_ses(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv(
        "OGRETMEN_WHISPER_SERVER", str(_calistirilebilir(tmp_path / "whisper-server", SAHTE_SUNUCU))
    )
    monkeypatch.setenv("OGRETMEN_FFMPEG", str(_calistirilebilir(tmp_path / "ffmpeg", SAHTE_FFMPEG)))
    model = tmp_path / "model.bin"
    model.write_bytes(b"sahte model")
    monkeypatch.setenv("OGRETMEN_WHISPER_MODEL", str(model))
    yield
    ses_modulu.kapat()


def test_durum_eksikleri_adlariyla_soyler(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OGRETMEN_WHISPER_SERVER", "/olmayan/whisper")
    monkeypatch.setenv("OGRETMEN_WHISPER_MODEL", "/olmayan/model.bin")
    monkeypatch.setenv("OGRETMEN_FFMPEG", "/olmayan/ffmpeg")
    bilgi = ses_modulu.durum()
    assert not bilgi.kullanilabilir
    for parca in ("ffmpeg", "whisper-server", "model"):
        assert parca in bilgi.aciklama


def test_yaziya_dok_sahte_sunucuyla_ucdan_uca(sahte_ses) -> None:
    metin = ses_modulu.yaziya_dok(b"tarayici-ses-verisi")
    assert metin == "Ayşe Yılmaz yok."
    # İkinci çağrı aynı sunucuyu kullanmalı (yeniden başlatma yok).
    assert ses_modulu.yaziya_dok(b"ikinci") == "Ayşe Yılmaz yok."


def test_sunucu_hemen_olurse_anlasilir_hata(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    bozuk = _calistirilebilir(tmp_path / "whisper-server", "#!/bin/sh\nexit 1\n")
    monkeypatch.setenv("OGRETMEN_WHISPER_SERVER", str(bozuk))
    monkeypatch.setenv("OGRETMEN_FFMPEG", str(_calistirilebilir(tmp_path / "ffmpeg", SAHTE_FFMPEG)))
    model = tmp_path / "model.bin"
    model.write_bytes(b"m")
    monkeypatch.setenv("OGRETMEN_WHISPER_MODEL", str(model))
    with pytest.raises(ses_modulu.SesKullanilamiyor, match="başlatılamadı"):
        ses_modulu.yaziya_dok(b"veri")
    ses_modulu.kapat()


def test_whisper_yoksa_seskullanilamiyor(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OGRETMEN_WHISPER_SERVER", "/olmayan/whisper")
    monkeypatch.setenv("OGRETMEN_WHISPER_MODEL", "/olmayan/model.bin")
    monkeypatch.setenv("OGRETMEN_FFMPEG", "/olmayan/ffmpeg")
    with pytest.raises(ses_modulu.SesKullanilamiyor, match="Bulunamadı"):
        ses_modulu.yaziya_dok(b"veri")


def test_ortam_degiskeni_bosluklu_yolu_kirpar(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OGRETMEN_FFMPEG", "  ")
    # Boş/boşluk değer varsayılana düşmeli, Path('') olmamalı.
    assert ses_modulu._yol("OGRETMEN_FFMPEG", ses_modulu.VARSAYILAN_FFMPEG) == (
        ses_modulu.VARSAYILAN_FFMPEG
    )


def _pid_yasiyor(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def test_kapat_sunucuyu_gercekten_oldurur(sahte_ses) -> None:
    ses_modulu.yaziya_dok(b"veri")
    surec = ses_modulu._sunucu
    assert surec is not None and surec.poll() is None
    ses_modulu.kapat()
    surec.wait(timeout=5)
    assert not _pid_yasiyor(surec.pid) or surec.poll() is not None
