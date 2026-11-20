"""SVG grafik üretiminin testleri.

Grafik yanlış çizilirse kimse hata görmez, yalnız yanlış yorum yapılır; bu
yüzden değer→koordinat dönüşümü ve kenar durumları sayısal olarak sabitlenir.
"""

from __future__ import annotations

import re

from ogretmen_cantasi.cikti import grafik


def _sayilar(svg: str, oznitelik: str) -> list[float]:
    return [float(x) for x in re.findall(rf'{oznitelik}="([0-9.]+)"', svg)]


def test_bos_seri_bos_dize_doner() -> None:
    assert grafik.cizgi_grafigi([]) == ""
    assert grafik.sutun_grafigi([]) == ""
    assert grafik.kivilcim([]) == ""
    assert grafik.sutun_grafigi([("0–49", 0), ("50–59", 0)]) == ""


def test_tek_nokta_cizgi_degil_isaret_cizer() -> None:
    svg = grafik.cizgi_grafigi([("TYT-1", 12.5)])
    assert "<polyline" not in svg
    assert "<circle" in svg
    assert "TYT-1: 12.5" in svg  # araç ipucu


def test_cizgi_koordinatlari_deger_sirasini_izler() -> None:
    svg = grafik.cizgi_grafigi([("A", 0.0), ("B", 10.0), ("C", 5.0)])
    yol = re.search(r'<polyline points="([^"]+)"', svg)
    assert yol is not None
    noktalar = [tuple(map(float, p.split(","))) for p in yol.group(1).split()]
    xler = [n[0] for n in noktalar]
    yler = [n[1] for n in noktalar]
    assert xler == sorted(xler), "x koordinatları soldan sağa artmalı"
    # SVG'de y aşağı doğru büyür: en yüksek değer (10) en küçük y'yi almalı.
    assert yler[1] < yler[2] < yler[0]


def test_cizgi_turkce_etiket_ve_son_deger_etiketi() -> None:
    svg = grafik.cizgi_grafigi([("Şubat Denemesi", 8.0), ("Öğrenci Ort.", 11.25)])
    assert "Şubat Denemesi" in svg
    assert ">11.25</text>" in svg  # yalnız son değer doğrudan etiketli
    assert ">8</text>" not in svg


def test_sutun_yukseklikleri_adetle_oranli() -> None:
    svg = grafik.sutun_grafigi([("0–49", 1), ("50–59", 2), ("85–100", 4)])
    yollar = re.findall(r'<path d="M ([0-9.]+) ([0-9.]+) L [0-9.]+ ([0-9.]+)', svg)
    assert len(yollar) == 3
    taban = float(yollar[0][1])
    yukseklikler = [taban - float(y[2]) for y in yollar]
    # Yuvarlatma payı (r) çıkarıldığı için tam oran değil sıralama sabitlenir.
    assert yukseklikler[0] < yukseklikler[1] < yukseklikler[2]
    # En yüksek sütun doğrudan etiketlenir, diğerleri araç ipucunda kalır.
    assert ">4</text>" in svg
    assert ">2</text>" not in svg
    assert "50–59: 2" in svg


def test_svg_renkleri_css_degiskenlerinden_gelir() -> None:
    svg = grafik.cizgi_grafigi([("A", 1.0), ("B", 2.0)])
    assert "var(--vurgu)" in svg
    assert "#" not in re.sub(r"aria-label=\"[^\"]*\"", "", svg), "renkler sabitlenmemeli"


def test_kivilcim_tek_deger_ve_seri() -> None:
    tek = grafik.kivilcim([5.0])
    assert "<circle" in tek and "<polyline" not in tek
    seri = grafik.kivilcim([1.0, 2.0, 3.0])
    assert "<polyline" in seri
