"""HTML'den PDF üretimi (PyMuPDF Story).

Neden Story: WeasyPrint/wkhtmltopdf gibi seçenekler cairo, pango ya da Qt
istiyor; bu Mac'te brew kurulu değil ve her biri yeni bir sistem bağımlılığı
demek. PyMuPDF zaten müfredat çıkarımı için kurulu ve Türkçe karakterleri
gömülü yazı tipiyle sorunsuz basıyor (doğrulandı).

Story, HTML/CSS'in bir alt kümesini destekler: blok öğeler, tablolar, temel
metin biçimlendirme. Karmaşık yerleşim (flex/grid) burada kullanılmaz; belge
şablonları bilinçli olarak tablo tabanlı yazıldı.
"""

from __future__ import annotations

import io
from pathlib import Path

import pymupdf

A4_DIKEY = "a4"
A4_YATAY = "a4-l"

# Belge şablonlarının ortak baskı biçimi. Story dar bir CSS alt kümesi
# tanıdığı için burada yalnız desteklenen özellikler var.
BASKI_CSS = """
body { font-family: sans-serif; font-size: 9.5px; color: #111; }
h1 { font-size: 15px; margin: 0 0 2px 0; text-align: center; }
h2 { font-size: 12px; margin: 8px 0 3px 0; }
h3 { font-size: 10.5px; margin: 6px 0 2px 0; }
p  { margin: 3px 0; }
table { width: 100%; }
th, td { border: 1px solid #888; padding: 3px 4px; vertical-align: top; }
th { background-color: #eeeeee; font-weight: bold; }
.kucuk { font-size: 8.5px; color: #444; }
.orta { text-align: center; }
.imza { margin-top: 18px; font-size: 9px; }
.kutu { border: 1px solid #888; padding: 5px; margin: 4px 0; }
.baslik-serit { background-color: #f3f3f3; font-weight: bold; }
"""


def html_pdfe(
    html: str,
    *,
    yatay: bool = False,
    css: str = BASKI_CSS,
    kenar: float = 30.0,
) -> bytes:
    """HTML gövdesini PDF bayt dizisine çevirir."""
    alan = pymupdf.paper_rect(A4_YATAY if yatay else A4_DIKEY)
    yazim_alani = pymupdf.Rect(
        alan.x0 + kenar, alan.y0 + kenar, alan.x1 - kenar, alan.y1 - kenar
    )

    tampon = io.BytesIO()
    yazici = pymupdf.DocumentWriter(tampon)
    story = pymupdf.Story(html=html, user_css=css)
    while True:
        aygit = yazici.begin_page(alan)
        kalan, _ = story.place(yazim_alani)
        story.draw(aygit)
        yazici.end_page()
        if kalan == 0:
            break
    yazici.close()
    return tampon.getvalue()


def html_sayfalari_pdfe(
    sayfalar: list[str],
    *,
    yatay: bool = False,
    css: str = BASKI_CSS,
    kenar: float = 30.0,
) -> bytes:
    """Her HTML parçasını tam bir fiziksel sayfaya yerleştirir.

    Bir parça sığmıyorsa sessizce devam sayfasına bölmek yerine hata verir;
    MEB tablosunda başlıksız/yetişmeyen sayfa üretilemez.
    """
    alan = pymupdf.paper_rect(A4_YATAY if yatay else A4_DIKEY)
    yazim_alani = pymupdf.Rect(
        alan.x0 + kenar, alan.y0 + kenar, alan.x1 - kenar, alan.y1 - kenar
    )
    tampon = io.BytesIO()
    yazici = pymupdf.DocumentWriter(tampon)
    for html in sayfalar:
        story = pymupdf.Story(html=html, user_css=css)
        aygit = yazici.begin_page(alan)
        kalan, _ = story.place(yazim_alani)
        if kalan:
            raise ValueError("MEB planı için ayrılan sayfa içeriğe yetmedi.")
        story.draw(aygit)
        yazici.end_page()
    yazici.close()
    return tampon.getvalue()


def pdf_yaz(html: str, yol: Path, *, yatay: bool = False) -> Path:
    yol.parent.mkdir(parents=True, exist_ok=True)
    yol.write_bytes(html_pdfe(html, yatay=yatay))
    return yol
