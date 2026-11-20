"""Düzenlenebilir Word (.docx) çıktıları.

İdare "Word olarak gönder" dediğinde ya da plan üzerinde elle oynamak
gerektiğinde kullanılır. İçerik PDF ile aynı kaynaktan gelir; yalnız
biçimlendirme yolu farklıdır.
"""

from __future__ import annotations

import io

from docx import Document
from docx.enum.section import WD_ORIENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Cm, Pt

from ..plan.gunluk import GunlukPlan
from ..plan.yillik import TUR_TATIL, PlanSatiri

MEB_BASLIKLARI = (
    "Ay",
    "Hafta",
    "Saat",
    "Tema / Öğrenme Çıktısı",
    "Süreç Bileşenleri",
    "Yöntem ve Teknikler",
    "Araç-Gereç",
    "Ölçme ve Değerlendirme",
    "Diğer Derslerle İlişkilendirme",
    "Belirli Gün ve Haftalar",
    "Açıklama",
)
MEB_GENISLIKLERI = (1.4, 2.2, 0.9, 5.8, 4.8, 2.6, 2.2, 2.4, 2.2, 2.2, 1.4)


def _yatay_yap(belge: Document) -> None:
    bolum = belge.sections[0]
    genislik, yukseklik = bolum.page_width, bolum.page_height
    bolum.orientation = WD_ORIENT.LANDSCAPE
    bolum.page_width, bolum.page_height = max(genislik, yukseklik), min(genislik, yukseklik)
    for kenar in ("left_margin", "right_margin", "top_margin", "bottom_margin"):
        setattr(bolum, kenar, Cm(1.2))


def _yazi_boyutu(belge: Document, punto: float) -> None:
    stil = belge.styles["Normal"]
    stil.font.name = "Calibri"
    stil.font.size = Pt(punto)


def _baslik(belge: Document, metin: str, alt: str = "") -> None:
    paragraf = belge.add_paragraph(metin)
    paragraf.alignment = WD_ALIGN_PARAGRAPH.CENTER
    paragraf.runs[0].bold = True
    paragraf.runs[0].font.size = Pt(13)
    if alt:
        alt_paragraf = belge.add_paragraph(alt)
        alt_paragraf.alignment = WD_ALIGN_PARAGRAPH.CENTER
        alt_paragraf.runs[0].font.size = Pt(9)


def _imza(belge: Document, ogretmen: str) -> None:
    belge.add_paragraph()
    tablo = belge.add_table(rows=1, cols=2)
    tablo.rows[0].cells[0].text = f"{ogretmen}\nBiyoloji Öğretmeni"
    tablo.rows[0].cells[1].text = "…………………\nOkul Müdürü"
    for hucre in tablo.rows[0].cells:
        hucre.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER


def yillik_plan_docx(
    satirlar: list[PlanSatiri],
    *,
    okul: str,
    sube_adi: str,
    ogretim_yili: str,
    ogretmen: str,
) -> bytes:
    belge = Document()
    _yatay_yap(belge)
    _yazi_boyutu(belge, 8)
    _baslik(
        belge,
        f"{ogretim_yili} EĞİTİM ÖĞRETİM YILI ÜNİTELENDİRİLMİŞ YILLIK DERS PLANI",
        f"{okul} — {sube_adi} sınıfı Biyoloji dersi",
    )

    tablo = belge.add_table(rows=1, cols=len(MEB_BASLIKLARI))
    tablo.style = "Table Grid"
    for hucre, baslik in zip(tablo.rows[0].cells, MEB_BASLIKLARI, strict=True):
        hucre.text = baslik
        hucre.paragraphs[0].runs[0].bold = True

    onceki_ay = ""
    for satir in satirlar:
        hucreler = tablo.add_row().cells
        hucreler[0].text = "" if satir.ay == onceki_ay else satir.ay
        onceki_ay = satir.ay
        hucreler[1].text = f"{satir.baslangic[8:]}.{satir.baslangic[5:7]}–{satir.bitis[8:]}.{satir.bitis[5:7]}"
        hucreler[2].text = str(satir.ders_saati) if satir.ders_saati else "—"
        if satir.tur == TUR_TATIL:
            hucreler[3].text = satir.aciklama
            continue
        kazanimlar = "\n".join(
            f"{kod} {ifade}"
            for kod, ifade in zip(satir.kazanim_kodlari, satir.kazanim_ifadeleri, strict=False)
        )
        hucreler[3].text = f"{satir.tema_adi}\n{kazanimlar}".strip()
        hucreler[4].text = "\n".join(satir.surec_bilesenleri)
        hucreler[5].text = ", ".join(satir.yontem_teknik)
        hucreler[6].text = ", ".join(satir.arac_gerec)
        hucreler[7].text = ", ".join(satir.olcme_degerlendirme)
        hucreler[8].text = ", ".join(satir.disiplinler_arasi)
        hucreler[9].text = ", ".join(satir.belirli_gunler)
        hucreler[10].text = satir.aciklama

    for sutun, genislik in enumerate(MEB_GENISLIKLERI):
        for satir_nesnesi in tablo.rows:
            satir_nesnesi.cells[sutun].width = Cm(genislik)

    belge.add_paragraph(f"Toplam ders saati: {sum(s.ders_saati for s in satirlar)}")
    _imza(belge, ogretmen)

    tampon = io.BytesIO()
    belge.save(tampon)
    return tampon.getvalue()


def gunluk_plan_docx(plan: GunlukPlan, *, okul: str, ogretmen: str) -> bytes:
    belge = Document()
    _yazi_boyutu(belge, 10)
    _baslik(belge, "GÜNLÜK DERS PLANI", okul)

    kunye = belge.add_table(rows=0, cols=2)
    kunye.style = "Table Grid"
    for ad, deger in (
        ("Ders", "Biyoloji"),
        ("Sınıf / Şube", f"{plan.sinif}. sınıf — {plan.sube_adi}"),
        ("Tarih", plan.tarih.strftime("%d.%m.%Y")),
        ("Ders saati", ", ".join(str(s) for s in plan.ders_saatleri) + ". ders"),
        ("Süre", f"{plan.toplam_dakika} dakika"),
        ("Tema", f"{plan.tema_no}. TEMA: {plan.tema_adi}"),
    ):
        hucreler = kunye.add_row().cells
        hucreler[0].text = ad
        hucreler[1].text = deger

    belge.add_paragraph()
    belge.add_paragraph("Öğrenme Çıktıları").runs[0].bold = True
    for kod, ifade in zip(plan.kazanim_kodlari, plan.kazanim_ifadeleri, strict=False):
        belge.add_paragraph(f"{kod} {ifade}", style="List Bullet")

    belge.add_paragraph("Süreç Bileşenleri").runs[0].bold = True
    for bilesen in plan.surec_bilesenleri:
        belge.add_paragraph(bilesen, style="List Bullet")

    belge.add_paragraph("Ders Akışı").runs[0].bold = True
    akis = belge.add_table(rows=0, cols=3)
    akis.style = "Table Grid"
    for bolum in plan.bolumler:
        hucreler = akis.add_row().cells
        hucreler[0].text = f"{bolum.dakika} dk"
        hucreler[1].text = bolum.ad
        hucreler[2].text = bolum.metin or "(Programda bu bölüm için metin yok.)"
        hucreler[0].width = Cm(1.5)
        hucreler[1].width = Cm(4.0)
        hucreler[2].width = Cm(11.0)

    belge.add_paragraph()
    belge.add_paragraph(f"Yöntem-teknik: {', '.join(plan.yontem_teknik)}")
    belge.add_paragraph(f"Araç-gereç: {', '.join(plan.arac_gerec)}")
    if plan.zenginlestirme:
        belge.add_paragraph(f"Zenginleştirme: {plan.zenginlestirme}")
    if plan.destekleme:
        belge.add_paragraph(f"Destekleme: {plan.destekleme}")
    _imza(belge, ogretmen)

    tampon = io.BytesIO()
    belge.save(tampon)
    return tampon.getvalue()
