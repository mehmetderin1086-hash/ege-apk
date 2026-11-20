#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici — golden-v1 TASLAK + denetim overlay üretici.

Motorun mevcut tespitlerinden (dogrula.belge_isle + dogrula._tahmin_raporu_
verilerden) kalite/altin/<ad>.json şemasına (soru-kesici.golden/v1) uygun bir
TASLAK üretir. Taslak kalite/altin_taslak/'a yazılır — kalite/altin/'a ASLA
doğrudan yazılmaz; insan onayından sonra elle taşınır.

kalite/koleksiyon.json'daki her belge için (dogrula.belge_isle'ın örneklediği
sayfalarla birebir):
  - kalite/altin_taslak/<ad>.json            → golden-v1 taslak
    (dogrula.altin_veriyi_yukle ile yüklenebilir olması garanti edilir; yazım
    öncesi ve sonrası ayrıca doğrulanır)
  - kalite/altin_onizleme/<ad>/s<no>.png      → kutu+numara+güven renkli
    overlay (yeşil=otomatik, turuncu=incele, kırmızı=reddedildi, gri=bilinmiyor)
  - kalite/altin_onizleme/<ad>/ciplak_s<no>.png → kutusuz ÇIPLAK sayfa
    (kör-sayım protokolü: kutuları görmeden sayfadaki soru sayısı sayılabilir)

Kullanım:
    .venv/bin/python altin_hazirla.py                  # koleksiyondaki tüm belgeler
    .venv/bin/python altin_hazirla.py --belge aydin     # yalnız bu belge
    .venv/bin/python altin_hazirla.py --sadece-liste    # yalnız belge adlarını bas

soru_kes.py ve dogrula.py'ye dokunmaz; yalnız içe aktarır.
"""

import argparse
import datetime
import json
import os
import sys

import dogrula
import soru_kes as sk

KOK = os.path.dirname(os.path.abspath(__file__))
KOLEKSIYON = os.path.join(KOK, "kalite", "koleksiyon.json")
TASLAK_DIZIN = os.path.join(KOK, "kalite", "altin_taslak")
ONIZLEME_DIZIN = os.path.join(KOK, "kalite", "altin_onizleme")

# _inceleme_bindirmesi (soru_kes.py) ile aynı renk sözleşmesi.
_RENKLER = {
    "otomatik": (20, 155, 70),     # yeşil
    "incele": (235, 145, 20),      # turuncu
    "reddedildi": (205, 35, 45),   # kırmızı
    "bilinmiyor": (110, 110, 110),  # gri — güven yok
}

# Tahmin şeması sayfa rolü olarak "bilinmiyor"a izin verir (TAHMIN_SAYFA_
# ROLLERI); golden şeması vermez (SAYFA_ROLLERI). Motor rolü belirleyemediyse
# taslakta şema-geçerli bir yer tutucuya düşürülür ve insan incelemesi için
# raporlanır — geometri/kutu verisi ETKİLENMEZ, yalnız etiket.
_GOLDEN_ROL_YER_TUTUCU = "karma"


def _koleksiyon_oku():
    with open(KOLEKSIYON, encoding="utf-8") as f:
        return json.load(f)


def _golden_rolu(rol, uyarilar, sayfa_no):
    if rol in dogrula.SAYFA_ROLLERI:
        return rol
    uyarilar.append(
        f"sayfa {sayfa_no}: motor rolü belirleyemedi ('bilinmiyor') → "
        f"taslakta '{_GOLDEN_ROL_YER_TUTUCU}' ile dolduruldu, elle düzelt")
    return _GOLDEN_ROL_YER_TUTUCU


def _kutu_onar(kutu, genislik, yukseklik):
    """Motor kutusunu golden şemasının geçerli sınırlarına indirger.
    Dönüş: (yeni_kutu, degisti_mi). Kırpma sonrası dejenere (sıfır/negatif
    alan) kalırsa None döner — böyle bir soru taslağa eklenmez."""
    x0, y0, x1, y1 = (float(v) for v in kutu)
    x0c = min(max(x0, 0.0), genislik)
    y0c = min(max(y0, 0.0), yukseklik)
    x1c = min(max(x1, 0.0), genislik)
    y1c = min(max(y1, 0.0), yukseklik)
    if x1c <= x0c or y1c <= y0c:
        return None, True
    yeni = [round(x0c, 3), round(y0c, 3), round(x1c, 3), round(y1c, 3)]
    degisti = yeni != [round(v, 3) for v in kutu]
    return yeni, degisti


def _tahmin_sorusunu_altina_indirge(soru, genislik, yukseklik, uyarilar,
                                    sayfa_no):
    """Tahmin sorusundan (confidence/status içerir) golden-v1 soru alanı
    üretir. Motorun ürettiği kutu sayfa sınırını aşıyorsa (bilinen birleşme/
    anomali sınıfı) kırpılır ve insan incelemesi için uyarı biriktirilir;
    dejenere kalırsa soru taslağa hiç eklenmez."""
    yeni_kutu, degisti = _kutu_onar(soru["box"], genislik, yukseklik)
    kimlik = f"id={soru['id']} (no={soru.get('number')})"
    if yeni_kutu is None:
        uyarilar.append(
            f"sayfa {sayfa_no} soru {kimlik}: kutu dejenere/geçersiz — "
            f"taslağa eklenmedi, ELLE EKLE "
            f"(orijinal kutu: {[round(v, 1) for v in soru['box']]})")
        return None
    if degisti:
        uyarilar.append(
            f"sayfa {sayfa_no} soru {kimlik}: kutu sayfa sınırını aşıyor "
            f"(olası birleşme/anomali) → sayfaya kırpıldı, ELLE KONTROL ET "
            f"(orijinal: {[round(v, 1) for v in soru['box']]})")
    altin = {"id": soru["id"], "box": yeni_kutu, "type": soru["type"]}
    if soru.get("number") is not None:
        altin["number"] = soru["number"]
    return altin


def _sayfa_taslagi(tahmin_sayfa, uyarilar):
    genislik, yukseklik = tahmin_sayfa["width"], tahmin_sayfa["height"]
    sayfa_no = tahmin_sayfa["page"]
    sorular = []
    for q in tahmin_sayfa["questions"]:
        altin = _tahmin_sorusunu_altina_indirge(
            q, genislik, yukseklik, uyarilar, sayfa_no)
        if altin is not None:
            sorular.append(altin)
    return {
        "page": sayfa_no,
        "width": genislik,
        "height": yukseklik,
        "role": _golden_rolu(tahmin_sayfa["role"], uyarilar, sayfa_no),
        "questions": sorular,
    }


def _overlay_ciz(sayfa, tahmin_sayfa):
    """Sayfa görseli üstüne kutu indeksi + soru no + güven etiketli, güven
    durumuna göre renklendirilmiş kutuları çizer."""
    from PIL import ImageDraw
    gorsel, olcek = sayfa.gorsel()
    ciz = ImageDraw.Draw(gorsel)
    for j, soru in enumerate(tahmin_sayfa["questions"], 1):
        x0, y0, x1, y1 = (float(v) * olcek for v in soru["box"])
        durum = soru.get("status") or "bilinmiyor"
        renk = _RENKLER.get(durum, _RENKLER["bilinmiyor"])
        ciz.rectangle((x0, y0, x1, y1), outline=renk, width=4)
        guven = soru.get("confidence")
        guven_metni = f"{guven:.2f}" if isinstance(guven, (int, float)) else "?"
        numara = soru.get("number")
        etiket = f"#{j} no:{numara if numara is not None else '?'} g:{guven_metni}"
        etiket_genisligi = max(90, len(etiket) * 7)
        ciz.rectangle((x0, y0, x0 + etiket_genisligi, y0 + 20), fill=renk)
        ciz.text((x0 + 4, y0 + 3), etiket, fill="white")
    return gorsel


def _belge_uret(oge):
    """Tek koleksiyon ögesini işler; taslak + overlay + çıplak PNG üretir.
    Dönüş: (taslak_yolu, onizleme_dizini, sayfa_sayisi, uyarilar)."""
    yol = oge["yol"] if os.path.isabs(oge["yol"]) \
        else os.path.join(KOK, oge["yol"])
    ad = oge["ad"]
    dpi = oge.get("dpi", 300)
    max_sayfa = oge.get("max_sayfa", 40)

    fmt, veriler, ornek_no, acik = dogrula.belge_isle(
        yol, dpi=dpi, max_sayfa=max_sayfa)
    try:
        # NOT: dogrula._tahmin_raporu_verilerden kullanmıyoruz — o TÜM rapor
        # şemasını tek seferde doğrular ve sayfa sınırını aşan TEK bir kutu
        # (bilinen "birleşme" anomalisi sınıfı, ör. 9pdf sayfa 29) yüzünden
        # belgenin TAMAMINI düşürür. Golden taslağı üretirken amaç böyle
        # motor kusurlarını ATLAMAK değil, işaretleyip insan incelemesine
        # sunmaktır; bu yüzden aynı dönüşümü (_sayfa_tahmini, dogrula.py'nin
        # kendi yardımcısı — YENİDEN YAZILMADI) sayfa sayfa çağırıp doğrulama/
        # kırpmayı _sayfa_taslagi içinde soru düzeyinde ele alıyoruz.
        tahmin_sayfalar = [
            dogrula._sayfa_tahmini(s, meta, no, fmt)
            for (s, _b, _k, meta), no in zip(veriler, ornek_no)
        ]

        uyarilar = []
        bugun = datetime.date.today().isoformat()
        golden = {
            "schema_version": dogrula.ALTIN_SEMA_SURUMU,
            "dataset": {
                "id": f"soru-kesici-taslak-{ad}",
                "kind": "annotated",
                "description": f"motor taslağından, altin_hazirla.py, {bugun}",
            },
            "documents": [{
                "id": f"soru-kesici:{ad}",
                "source": os.path.basename(yol),
                "source_sha256": dogrula._dosya_sha256(yol),
                "pages": [_sayfa_taslagi(s, uyarilar)
                         for s in tahmin_sayfalar],
            }],
        }
        # Taslak MUTLAKA bu doğrulamadan geçmeli (dogrula.altin_veriyi_yukle
        # ile yüklenebilir olmalı) — dosyaya yazmadan önce bellekte doğrula.
        dogrula._veri_setini_dogrula(golden, tahmin=False)

        os.makedirs(TASLAK_DIZIN, exist_ok=True)
        taslak_yolu = os.path.join(TASLAK_DIZIN, f"{ad}.json")
        with open(taslak_yolu, "w", encoding="utf-8") as f:
            json.dump(golden, f, ensure_ascii=False, indent=1)
        # Dosyadan gerçek round-trip yükleme ile de doğrula (serileştirme
        # sorunlarını yakalar; dogrula.altin_veriyi_yukle tam olarak budur).
        dogrula.altin_veriyi_yukle(taslak_yolu)

        onizleme_alt = os.path.join(ONIZLEME_DIZIN, ad)
        os.makedirs(onizleme_alt, exist_ok=True)
        sayfa_haritasi = {no: s for (s, _b, _k, _m), no
                          in zip(veriler, ornek_no)}
        tahmin_sayfa_haritasi = {s["page"]: s for s in tahmin_sayfalar}
        for no, sayfa in sayfa_haritasi.items():
            tahmin_sayfa = tahmin_sayfa_haritasi[no]
            ciplak, _ = sayfa.gorsel()
            ciplak.save(os.path.join(onizleme_alt, f"ciplak_s{no}.png"))
            overlay = _overlay_ciz(sayfa, tahmin_sayfa)
            overlay.save(os.path.join(onizleme_alt, f"s{no}.png"))

        return taslak_yolu, onizleme_alt, len(sayfa_haritasi), uyarilar
    finally:
        sk.belge_kapat(acik)


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Golden-v1 taslak + denetim overlay üretici")
    p.add_argument("--belge", metavar="AD", help="yalnız bu belgeyi işle")
    p.add_argument("--sadece-liste", action="store_true",
                   help="yalnız koleksiyondaki belge adlarını bas, işleme")
    args = p.parse_args(argv)

    koleksiyon = _koleksiyon_oku()
    if args.sadece_liste:
        for oge in koleksiyon:
            print(oge["ad"])
        return 0

    if args.belge:
        koleksiyon = [o for o in koleksiyon if o["ad"] == args.belge]
        if not koleksiyon:
            print(f"bilinmeyen belge: {args.belge}", file=sys.stderr)
            return 1

    hata_var = False
    for oge in koleksiyon:
        print(f"[{oge['ad']}] işleniyor...")
        try:
            taslak_yolu, onizleme_dizin, sayfa_sayisi, uyarilar = \
                _belge_uret(oge)
        except Exception as e:  # noqa: BLE001 — bir belgenin hatası diğerini durdurmasın
            print(f"[{oge['ad']}] HATA: {type(e).__name__}: {e}",
                  file=sys.stderr)
            hata_var = True
            continue
        print(f"[{oge['ad']}] taslak: {taslak_yolu}")
        print(f"[{oge['ad']}] overlay: {onizleme_dizin} ({sayfa_sayisi} sayfa)")
        for uyari in uyarilar:
            print(f"[{oge['ad']}] uyarı: {uyari}")

    return 1 if hata_var else 0


if __name__ == "__main__":
    sys.exit(main())
