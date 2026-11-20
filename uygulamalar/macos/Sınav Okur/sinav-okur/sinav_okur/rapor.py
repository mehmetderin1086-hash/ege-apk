"""Sınav sonuçlarını Excel'e (openpyxl) döken not dökümü üretici."""

from __future__ import annotations

from pathlib import Path

from .depo import Depo


def excel_dokum(depo: Depo, sinav_kimlik: str, yol: str | Path) -> Path:
    """Bir sınavın tüm kâğıtları için not dökümü Excel'i üretir."""
    from openpyxl import Workbook
    from openpyxl.chart import BarChart, Reference
    from openpyxl.formatting.rule import ColorScaleRule, DataBarRule
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.utils import get_column_letter

    sinav = depo.sinav_yukle(sinav_kimlik)
    kagitlar = depo.kagitlar(sinav_kimlik)
    sorular = sorted(sinav.sorular, key=lambda s: s.no)

    wb = Workbook()
    ws = wb.active
    ws.title = "Notlar"

    baslik_font = Font(bold=True, color="FFFFFF")
    baslik_dolgu = PatternFill("solid", fgColor="2F5496")
    orta = Alignment(horizontal="center")

    basliklar = ["Ad", "Soyad", "Numara", "Sınıf", "Şube"] + [f"S{s.no} ({s.puan:g})" for s in sorular] + [
        "Toplam", f"/{sinav.toplam_puan:g}", "%"
    ]
    ws.append(basliklar)
    for h in ws[1]:
        h.font = baslik_font
        h.fill = baslik_dolgu
        h.alignment = orta

    for kagit in kagitlar:
        kutu_puan = {k["soru_no"]: k["son_puan"] for k in depo.kutular(kagit["id"])}
        toplam, maxp = depo.kagit_toplam(kagit["id"])
        oran = (toplam / maxp * 100) if maxp else 0
        satir = [
            kagit["ogrenci_ad"] or "",
            kagit["ogrenci_soyad"] or "",
            kagit["ogrenci_no"] or "",
            kagit["sinif"] or "",
            kagit["sube"] or "",
        ]
        satir += [kutu_puan.get(s.no, "") for s in sorular]
        satir += [round(toplam, 2), round(maxp, 2), round(oran, 1)]
        ws.append(satir)

    ws.freeze_panes = "F2"
    son_satir = ws.max_row
    if son_satir > 1:
        # Otofiltre + koşullu biçimlendirme (kâğıt varsa).
        ws.auto_filter.ref = f"A1:{get_column_letter(len(basliklar))}{son_satir}"
        yuzde_sutun = get_column_letter(len(basliklar))
        ws.conditional_formatting.add(
            f"{yuzde_sutun}2:{yuzde_sutun}{son_satir}",
            ColorScaleRule(
                start_type="num", start_value=0, start_color="F8696B",
                mid_type="num", mid_value=50, mid_color="FFEB84",
                end_type="num", end_value=100, end_color="63BE7B",
            ),
        )
        ilk_soru = get_column_letter(6)
        son_soru = get_column_letter(5 + len(sorular))
        ws.conditional_formatting.add(
            f"{ilk_soru}2:{son_soru}{son_satir}",
            DataBarRule(start_type="min", end_type="max", color="5B9BD5"),
        )
        for r in range(2, son_satir + 1):
            ws[f"{yuzde_sutun}{r}"].number_format = "0.0"
    for sutun in ws.columns:
        en = max((len(str(h.value)) for h in sutun if h.value is not None), default=8)
        ws.column_dimensions[sutun[0].column_letter].width = min(en + 2, 28)

    from .analiz import kazanim_analizi, sinav_analizi

    analiz = sinav_analizi(depo, sinav)
    kazanim = kazanim_analizi(depo, sinav)
    turuncu = PatternFill("solid", fgColor="FCE4D6")
    wa = wb.create_sheet("Soru Analizi")
    wa.append(
        ["Soru", "Cevap", "Güçlük %", "Ayırt edicilik", "Madde korelasyonu",
         "Bekleyen", "Düzeltme", "Anahtar uyarısı"]
    )
    for hucre in wa[1]:
        hucre.font = baslik_font
        hucre.fill = baslik_dolgu
    for soru in analiz["sorular"]:
        wa.append(
            [
                soru["no"],
                soru["cevap"],
                soru["ortalama_yuzde"],
                soru.get("ayirt_edicilik"),
                soru.get("r_pbis"),
                soru["bekleyen"],
                soru["elle_duzeltme"],
                "Kontrol et" if soru["anahtar_supheli"] else "",
            ]
        )
        if soru["anahtar_supheli"]:
            for hucre in wa[wa.max_row]:
                hucre.fill = turuncu
    wi = wb.create_sheet("İnceleme Kuyruğu")
    wi.append(["Kâğıt", "Öğrenci", "Risk önceliği %", "Kimlik güveni %"])
    for hucre in wi[1]:
        hucre.font = baslik_font
        hucre.fill = baslik_dolgu
    for kayit in analiz["inceleme_kuyrugu"]:
        wi.append(
            [
                kayit["kagit_id"],
                kayit["ogrenci"],
                round(kayit["oncelik"] * 100, 1),
                round(kayit["kimlik_guveni"] * 100, 1),
            ]
        )
    wg = wb.create_sheet("Program Gerekçeleri")
    wg.append(
        [
            "Kâğıt",
            "Soru",
            "OCR güveni %",
            "OCR uzlaşması %",
            "Bağımsız motor",
            "Girdi kalitesi %",
            "Puan güveni %",
            "Risk %",
            "Otomatik kabul",
            "Program puanı",
            "Nihai puan",
            "Gerekçe",
        ]
    )
    for hucre in wg[1]:
        hucre.font = baslik_font
        hucre.fill = baslik_dolgu
    for kagit in kagitlar:
        for kutu in depo.kutular(kagit["id"]):
            wg.append(
                [
                    kagit["id"],
                    kutu["soru_no"],
                    round(float(kutu["tanima_guveni"] or 0) * 100, 1),
                    round(float(kutu["uzlasma_guveni"] or 0) * 100, 1),
                    int(kutu["bagimsiz_motor_sayisi"] or 0),
                    round(
                        float(
                            __import__("json").loads(
                                kutu["girdi_kalitesi_json"] or "{}"
                            ).get("kalite", 0)
                        )
                        * 100,
                        1,
                    ),
                    round(float(kutu["puanlama_guveni"] or 0) * 100, 1),
                    round(float(kutu["risk"] or 0) * 100, 1),
                    "Evet" if kutu["otomatik_kabul"] else "İnceleme",
                    kutu["otomatik_puan"],
                    kutu["son_puan"],
                    kutu["aciklama"] or "",
                ]
            )
    # İnceleme hücrelerini turuncu vurgula.
    for satir in wg.iter_rows(min_row=2, max_row=wg.max_row):
        if satir[8].value == "İnceleme":
            satir[8].fill = turuncu

    # Puan dağılımı sayfası + histogram grafiği.
    wd = wb.create_sheet("Dağılım")
    wd.append(["Puan aralığı", "Kâğıt"])
    for hucre in wd[1]:
        hucre.font = baslik_font
        hucre.fill = baslik_dolgu
    for i, adet in enumerate(analiz.get("dagilim", [])):
        wd.append([f"{i * 10}–{i * 10 + 10}", adet])
    if analiz.get("dagilim"):
        grafik = BarChart()
        grafik.title = "Puan dağılımı"
        grafik.y_axis.title = "Kâğıt sayısı"
        grafik.x_axis.title = "Puan %"
        veri = Reference(wd, min_col=2, min_row=1, max_row=wd.max_row)
        kategori = Reference(wd, min_col=1, min_row=2, max_row=wd.max_row)
        grafik.add_data(veri, titles_from_data=True)
        grafik.set_categories(kategori)
        grafik.legend = None
        wd.add_chart(grafik, "D2")

    # Kazanım (konu) başarısı — etiket yoksa sayfa yine üretilir, boş kalır.
    wk = wb.create_sheet("Kazanımlar")
    wk.append(["Kazanım", "Sorular", "Cevap", "Başarı %"])
    for hucre in wk[1]:
        hucre.font = baslik_font
        hucre.fill = baslik_dolgu
    for kayit in kazanim.get("kazanimlar", []):
        wk.append(
            [
                kayit["ad"],
                ", ".join(str(n) for n in kayit["soru_nolari"]),
                kayit["cevap_sayisi"],
                kayit["basari_yuzdesi"],
            ]
        )
        yuzde = kayit["basari_yuzdesi"]
        if yuzde is not None and yuzde < 60:
            for hucre in wk[wk.max_row]:
                hucre.fill = turuncu

    # Sınavın kendi kalitesi: öğrenciyi değil sınavı değerlendiren ölçüler.
    psi = analiz.get("psikometri") or {}
    if psi:
        wp = wb.create_sheet("Psikometri")
        wp.append(["Ölçü", "Değer", "Yorum"])
        for hucre in wp[1]:
            hucre.font = baslik_font
            hucre.fill = baslik_dolgu
        guvenilirlik = psi.get("guvenilirlik") or {}
        dagilim = psi.get("dagilim") or {}
        uyum = psi.get("puanlayici_uyumu") or {}
        # Yetersiz örneklemde sayı yazılmaz; nedeni yazılır.
        wp.append(
            [
                "Güvenilirlik (Cronbach α)",
                guvenilirlik.get("deger"),
                guvenilirlik.get("yorum")
                or f"Yetersiz örneklem ({guvenilirlik.get('mevcut', 0)}/"
                f"{guvenilirlik.get('gereken', '—')})",
            ]
        )
        wp.append(
            ["Ortalama toplam puan", dagilim.get("ortalama"), ""]
        )
        wp.append(
            ["Standart sapma", dagilim.get("standart_sapma"), ""]
        )
        wp.append(
            [
                "Program–öğretmen farkı (MAE)",
                uyum.get("mae"),
                "Program puanının öğretmen puanından ortalama sapması"
                if uyum.get("mae") is not None
                else f"Yetersiz düzeltme ({uyum.get('mevcut', 0)}/"
                f"{uyum.get('gereken', '—')})",
            ]
        )
        if uyum.get("sistematik_sapma") is not None:
            wp.append(
                [
                    "Sistematik sapma",
                    uyum.get("sistematik_sapma"),
                    "Artı: program cimri · Eksi: program cömert",
                ]
            )
        wp.column_dimensions["A"].width = 30
        wp.column_dimensions["C"].width = 55

    # İtiraz kayıtları — denetlenebilirlik için karar notlarıyla birlikte.
    wt = wb.create_sheet("İtirazlar")
    wt.append(
        ["Öğrenci", "Soru", "Durum", "Önceki puan", "Yeni puan", "Gerekçe", "Karar notu"]
    )
    for hucre in wt[1]:
        hucre.font = baslik_font
        hucre.fill = baslik_dolgu
    for itiraz in depo.itirazlar(sinav_kimlik):
        wt.append(
            [
                " ".join(
                    p
                    for p in (
                        itiraz["ogrenci_ad"] or "",
                        itiraz["ogrenci_soyad"] or "",
                    )
                    if p
                ),
                itiraz["soru_no"],
                itiraz["durum"],
                itiraz["onceki_puan"],
                itiraz["yeni_puan"],
                itiraz["gerekce"],
                itiraz["karar_notu"] or "",
            ]
        )
        if itiraz["durum"] == "acik":
            for hucre in wt[wt.max_row]:
                hucre.fill = turuncu

    for sayfa in (wa, wi, wg, wd, wk, wt):
        sayfa.freeze_panes = "A2"
        for sutun in sayfa.columns:
            en = max(
                (len(str(h.value)) for h in sutun if h.value is not None),
                default=8,
            )
            sayfa.column_dimensions[sutun[0].column_letter].width = min(en + 2, 55)

    yol = Path(yol)
    wb.save(yol)
    return yol
