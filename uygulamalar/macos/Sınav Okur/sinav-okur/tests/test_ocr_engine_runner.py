"""scripts/ocr_engine_runner.py'nin RapidOCR köprüsü: satır-JSON sözleşmesi.

``rapidocr`` paketi geliştirme makinesinde kurulu olmayabilir (Windows'ta
paketlenecek yeni bir motor); testler paketi ``sys.modules`` üzerinden
sahteleyip yalnız köprünün girdi/çıktı sözleşmesini (satır başına
text/confidence/x/y/width/height, diğer okuyucularla — ör. ``easyocr_oku`` —
aynı biçim) doğrular.
"""
from __future__ import annotations

import importlib.util
import json
import sys
import types
from pathlib import Path

import numpy as np
import pytest

pytest.importorskip("PIL")
pytest.importorskip("cv2")
import cv2

_RUNNER_YOLU = Path(__file__).parent.parent / "scripts" / "ocr_engine_runner.py"


def _runner_modulunu_yukle():
    spec = importlib.util.spec_from_file_location("ocr_engine_runner", _RUNNER_YOLU)
    modul = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modul)
    return modul


@pytest.fixture
def runner():
    return _runner_modulunu_yukle()


@pytest.fixture
def ornek_gorsel(tmp_path):
    yol = tmp_path / "sayfa.png"
    goruntu = np.full((100, 200, 3), 255, np.uint8)
    cv2.imwrite(str(yol), goruntu)
    return yol


def _sahte_rapidocr_modulu(boxes, txts, scores):
    sonuc = types.SimpleNamespace(boxes=boxes, txts=txts, scores=scores)

    class SahteRapidOCR:
        def __call__(self, yol):
            return sonuc

    return types.SimpleNamespace(RapidOCR=SahteRapidOCR)


def test_rapidocr_oku_satir_json_sozlesmesine_uyar(monkeypatch, runner, ornek_gorsel):
    kutu = np.array([[10, 10], [60, 10], [60, 30], [10, 30]], dtype=float)
    sahte = _sahte_rapidocr_modulu(
        boxes=np.array([kutu]), txts=("mitokondri",), scores=(0.93,)
    )
    monkeypatch.setitem(sys.modules, "rapidocr", sahte)

    sonuc = runner.rapidocr_oku(ornek_gorsel)

    assert len(sonuc) == 1
    blok = sonuc[0]
    assert blok["text"] == "mitokondri"
    assert blok["confidence"] == pytest.approx(0.93)
    for anahtar in ("x", "y", "width", "height"):
        assert anahtar in blok
        assert 0.0 <= blok[anahtar] <= 1.0


def test_rapidocr_oku_bos_sonucta_bos_liste_doner(monkeypatch, runner, ornek_gorsel):
    sahte = _sahte_rapidocr_modulu(boxes=None, txts=(), scores=())
    monkeypatch.setitem(sys.modules, "rapidocr", sahte)

    assert runner.rapidocr_oku(ornek_gorsel) == []


def test_rapidocr_motoru_onbellege_bir_kez_yuklenir(monkeypatch, runner, ornek_gorsel):
    kutu = np.array([[10, 10], [60, 10], [60, 30], [10, 30]], dtype=float)
    sahte = _sahte_rapidocr_modulu(
        boxes=np.array([kutu]), txts=("x",), scores=(0.5,)
    )
    yaratma_sayisi = 0
    gercek_rapidocr = sahte.RapidOCR

    class SayanRapidOCR(gercek_rapidocr):
        def __init__(self):
            nonlocal yaratma_sayisi
            yaratma_sayisi += 1

    monkeypatch.setitem(
        sys.modules, "rapidocr", types.SimpleNamespace(RapidOCR=SayanRapidOCR)
    )
    runner.rapidocr_oku(ornek_gorsel)
    runner.rapidocr_oku(ornek_gorsel)
    assert yaratma_sayisi == 1


def test_main_argv_rapidocr_dispatch(monkeypatch, capsys, runner, ornek_gorsel):
    kutu = np.array([[10, 10], [60, 10], [60, 30], [10, 30]], dtype=float)
    sahte = _sahte_rapidocr_modulu(
        boxes=np.array([kutu]), txts=("hücre",), scores=(0.8,)
    )
    monkeypatch.setitem(sys.modules, "rapidocr", sahte)
    monkeypatch.setattr(
        sys, "argv", ["ocr_engine_runner.py", "rapidocr", str(ornek_gorsel)]
    )

    runner.main()

    veri = json.loads(capsys.readouterr().out.strip())
    assert veri["blocks"][0]["text"] == "hücre"
