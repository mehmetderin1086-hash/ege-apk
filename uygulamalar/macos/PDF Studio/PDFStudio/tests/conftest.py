"""Test sabitleri: örnek PDF ve görsel üretimi."""
from __future__ import annotations

import io
from pathlib import Path

import fitz
import pytest


@pytest.fixture()
def sample_pdf(tmp_path: Path) -> Path:
    doc = fitz.open()
    for i in range(4):
        page = doc.new_page()
        page.insert_text((72, 90), f"PDF Studio Test — Sayfa {i + 1}", fontsize=18)
        page.insert_text((72, 130), "Bağışıklık sistemi çğüşöıİ", fontsize=11)
        page.draw_rect(fitz.Rect(72, 150, 320, 210), color=(0.3, 0.3, 0.9))
    p = tmp_path / "ornek.pdf"
    doc.save(p)
    doc.close()
    return p


@pytest.fixture()
def sample_image(tmp_path: Path) -> Path:
    from PIL import Image
    img = Image.new("RGB", (400, 300), (120, 90, 200))
    p = tmp_path / "gorsel.png"
    img.save(p)
    return p
