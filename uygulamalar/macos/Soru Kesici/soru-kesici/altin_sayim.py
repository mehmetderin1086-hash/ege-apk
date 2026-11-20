#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sayım-altını (Tier-1 golden) üretici — KÖR SAYIM protokolü.

Neden ayrı bir katman: recall gerilemesini yakalamak için kutu KOORDİNATI
gerekmiyor; sayfa başına doğru soru SAYISI ve numara kümesi yeter. Kutu-altını
(`altin_pdf_katmani.py`) yalnız IoU/kırpma kalitesi için gerekir ve pahalıdır
(~25 sn/soru). Sayım-altını ~45 sn/sayfa ile aynı kapsamı 3-4 kat ucuza verir.

KÖR SAYIM: `--hazirla` yalnız ÇIPLAK sayfa görüntüsü üretir ve `question_count`
alanlarını `null` bırakır. Motorun kutuları sayan kişiye ASLA gösterilmez —
aksi halde ölçüm motorun kendi hatasına kör kalır (döngüsellik). Sayan kişi
`null` alanları doldurur, `--kilitle` boş alan kalmadığını doğrulayıp kaynak
SHA-256 ile mühürler.

Şema `soru-kesici.golden-count/v1`; golden-v2'den KASITLI olarak ayrıdır:
v2'ye `questions: []` olan sayfa eklemek tüm tahminleri false-positive sayıp
metrikleri bozar.

Kullanım:
    .venv/bin/python altin_sayim.py --belge 9pdf --hazirla
    #   → kalite/altin_onizleme/9pdf_sayim/ciplak_s*.png + iskelet JSON
    #   (insan çıplak görselden sayar, question_count/numbers doldurur)
    .venv/bin/python altin_sayim.py --belge 9pdf --kilitle
    #   → kalite/altin_sayim/9pdf.json (mühürlü)
    .venv/bin/python altin_sayim.py --belge 9pdf --olc
    #   → motoru koşup sayım metriklerini raporlar
"""

import argparse
import json
import os
import sys

import dogrula
import soru_kes as sk

KOK = os.path.dirname(os.path.abspath(__file__))
KOLEKSIYON = os.path.join(KOK, "kalite", "koleksiyon.json")
SAYIM_DIZIN = os.path.join(KOK, "kalite", "altin_sayim")
ONIZLEME_DIZIN = os.path.join(KOK, "kalite", "altin_onizleme")
TASLAK_DIZIN = os.path.join(KOK, "kalite", "altin_sayim_taslak")

SEMA_SURUMU = "soru-kesici.golden-count/v1"


def _koleksiyon_oku():
    with open(KOLEKSIYON, encoding="utf-8") as f:
        return json.load(f)


def _oge_bul(ad):
    for oge in _koleksiyon_oku():
        if oge["ad"] == ad:
            return oge
    raise SystemExit(f"koleksiyonda yok: {ad}")


def _yol_coz(oge):
    return (oge["yol"] if os.path.isabs(oge["yol"])
            else os.path.join(KOK, oge["yol"]))


def _taslak_yolu(ad):
    return os.path.join(TASLAK_DIZIN, f"{ad}.json")


def _kilitli_yol(ad):
    return os.path.join(SAYIM_DIZIN, f"{ad}.json")


def hazirla(ad, dpi=150, sayfalar_secili=None):
    """Çıplak sayfa görüntülerini ve doldurulacak iskeleti üretir.

    Motorun tespit çıktısı ÇAĞRILMAZ; bu fonksiyon bilerek yalnız sayfa
    görüntüsü ve boş iskelet üretir.

    sayfalar_secili: 1-tabanlı sayfa numaraları. Verilirse yalnız o sayfalar
    için iskelet üretilir (TABAKALI ÖRNEKLEM). Tam kapsam her zaman daha
    iyidir; kısmi sayım yalnız belirli bir soruyu yanıtlamak için kullanılır
    ve `sampling.kapsam` alanına "kismi" yazılır — `sayim_degerlendir` zaten
    yalnız ortak sayfaları ölçer, dolayısıyla metrik doğru kalır ama BELGE
    GENELİNİ TEMSİL ETMEZ."""
    oge = _oge_bul(ad)
    yol = _yol_coz(oge)
    sayfalar, acik = sk.belge_sayfalari([yol], dpi)
    try:
        idx = dogrula._ornek_indeksleri(
            len(sayfalar), oge.get("max_sayfa", 40),
            oge.get("bas"), oge.get("son"))
        if sayfalar_secili:
            istenen = set(sayfalar_secili)
            eksik = istenen - {i + 1 for i in idx}
            if eksik:
                raise SystemExit(
                    f"bu sayfalar koşum örnekleminde yok: {sorted(eksik)}")
            idx = [i for i in idx if i + 1 in istenen]
        onizleme = os.path.join(ONIZLEME_DIZIN, f"{ad}_sayim")
        os.makedirs(onizleme, exist_ok=True)
        os.makedirs(TASLAK_DIZIN, exist_ok=True)
        kayitlar = []
        for i in idx:
            no = i + 1
            gorsel, _olcek = sayfalar[i].gorsel()
            gorsel.convert("RGB").save(
                os.path.join(onizleme, f"ciplak_s{no}.png"))
            kayitlar.append({
                "page": no,
                "question_count": None,     # DOLDURULACAK
                "question_numbers": None,   # DOLDURULACAK (varsa)
                "role": None,               # soru | konu | cevap_anahtari | kapak
                "notes": "",
            })
        veri = {
            "schema_version": SEMA_SURUMU,
            "document": {
                "id": f"soru-kesici:{ad}",
                "source": os.path.basename(yol),
                "source_sha256": dogrula._dosya_sha256(yol),
                "page_count": len(sayfalar),
            },
            "sampling": {"dpi": oge.get("dpi", 300),
                         "max_sayfa": oge.get("max_sayfa", 40),
                         "bas": oge.get("bas"), "son": oge.get("son"),
                         "kapsam": "kismi" if sayfalar_secili else "tam",
                         "ornek_no": [i + 1 for i in idx]},
            "verifier": None,               # DOLDURULACAK
            "method": "kor-sayim",
            "pages": kayitlar,
        }
        hedef = _taslak_yolu(ad)
        with open(hedef, "w", encoding="utf-8") as f:
            json.dump(veri, f, ensure_ascii=False, indent=1)
        print(f"çıplak görseller: {onizleme} ({len(idx)} sayfa)")
        print(f"iskelet: {hedef}")
        print("Sayarken motorun kutularına BAKMAYIN (kör sayım).")
        return hedef
    finally:
        sk.belge_kapat(acik)


def kilitle(ad):
    """Taslağı doğrulayıp mühürlü sayım-altınına taşır."""
    taslak = _taslak_yolu(ad)
    if not os.path.exists(taslak):
        raise SystemExit(f"taslak yok: {taslak} (önce --hazirla)")
    with open(taslak, encoding="utf-8") as f:
        veri = json.load(f)
    eksik = [s["page"] for s in veri["pages"]
             if s.get("question_count") is None or s.get("role") is None]
    if eksik:
        raise SystemExit(
            f"{len(eksik)} sayfa doldurulmamış: {eksik[:12]} …")
    if not veri.get("verifier"):
        raise SystemExit("'verifier' alanı boş — sayımı kimin yaptığı yazılmalı")
    for s in veri["pages"]:
        nums = s.get("question_numbers")
        if nums is not None and len(nums) != s["question_count"]:
            raise SystemExit(
                f"s{s['page']}: numara adedi ({len(nums)}) sayımla "
                f"({s['question_count']}) uyuşmuyor")
    oge = _oge_bul(ad)
    guncel_sha = dogrula._dosya_sha256(_yol_coz(oge))
    if guncel_sha != veri["document"]["source_sha256"]:
        raise SystemExit("kaynak PDF değişmiş — sayım geçersiz")
    os.makedirs(SAYIM_DIZIN, exist_ok=True)
    hedef = _kilitli_yol(ad)
    with open(hedef, "w", encoding="utf-8") as f:
        json.dump(veri, f, ensure_ascii=False, indent=1)
    toplam = sum(s["question_count"] for s in veri["pages"])
    print(f"kilitlendi: {hedef} ({len(veri['pages'])} sayfa, {toplam} soru)")
    return hedef


def sayim_yukle(yol):
    with open(yol, encoding="utf-8") as f:
        veri = json.load(f)
    if veri.get("schema_version") != SEMA_SURUMU:
        raise ValueError(f"beklenmeyen şema: {veri.get('schema_version')}")
    for alan in ("document", "pages"):
        if alan not in veri:
            raise ValueError(f"eksik alan: {alan}")
    return veri


def sayim_degerlendir(sayim, veriler, ornek_no):
    """Motorun sayfa başına kutu sayısını sayım-altınıyla karşılaştırır.

    Kutu koordinatı KULLANILMAZ — bu katman yalnız kaçırma/fazla üretme
    ölçer. Dönüş: sayım raporu sözlüğü.

    İki kova ayrı ayrı ölçülür:
      * TESLİM  — `otomatik` + `incele` (kullanıcının gördüğü her kesim);
                  recall'ün asıl ölçüsü, çünkü `incele` kutusu da bulunmuştur.
      * OTOMATİK — insan bakmadan teslim edilen alt küme; "sıfır hata"
                  hedefi (SH-1/SH-2) bu kovaya tanımlıdır.
    """
    import soru_kes as sk
    altin = {s["page"]: s for s in sayim["pages"]}
    tahmin = {}
    tahmin_oto = {}
    for (_s, _b, kutular, meta), no in zip(veriler, ornek_no):
        tahmin[no] = len(kutular)
        tahmin_oto[no] = sum(1 for m in meta if sk.aday_otomatik_teslim(m))
    ortak = sorted(set(altin) & set(tahmin))
    if not ortak:
        raise ValueError("sayım-altını ile koşum sayfaları örtüşmüyor")
    # Kısmi örtüşme SESSİZ bir tuzaktır: koşumun örneklemi altınınkinden
    # kaydığında ölçüm birkaç sayfaya (hatta yalnız boş kapağa) düşer ve
    # 1,000 gibi kusursuz ama anlamsız değerler üretir. Gerçek vaka: bir ikiz
    # belgede max_sayfa farkı yüzünden 8 altın sayfasından yalnız 1'i
    # örtüştü ve recall/precision/otomatik hepsi 1,000 çıktı.
    ortusme = len(ortak) / len(altin)
    eksik = fazla = tam = 0
    eksik_oto = fazla_oto = 0
    sapmalar = []
    for no in ortak:
        g = altin[no]["question_count"]
        p = tahmin[no]
        eksik += max(0, g - p)
        fazla += max(0, p - g)
        tam += int(g == p)
        po = tahmin_oto[no]
        eksik_oto += max(0, g - po)
        fazla_oto += max(0, po - g)
        if g != p:
            sapmalar.append({"page": no, "gold": g, "pred": p,
                             "pred_auto": po})
    altin_toplam = sum(altin[no]["question_count"] for no in ortak)
    tahmin_toplam = sum(tahmin[no] for no in ortak)
    oto_toplam = sum(tahmin_oto[no] for no in ortak)
    bos = [s["page"] for s in sapmalar
           if altin[s["page"]]["question_count"] > 0 and s["pred"] == 0]
    return {
        "schema_version": "soru-kesici.count-report/v1",
        "pages": len(ortak),
        "gold_pages": len(altin),
        "pages_overlap_ratio": round(ortusme, 4),
        "pages_exact": tam,
        "page_exact_rate": tam / len(ortak),
        "gold_total": altin_toplam,
        "pred_total": tahmin_toplam,
        "pred_total_auto": oto_toplam,
        "under_count": eksik,
        "over_count": fazla,
        "count_recall": (1 - eksik / altin_toplam) if altin_toplam else 1.0,
        "count_precision": (1 - fazla / tahmin_toplam) if tahmin_toplam else 1.0,
        "count_recall_auto": (
            (1 - eksik_oto / altin_toplam) if altin_toplam else 1.0),
        "count_precision_auto": (
            (1 - fazla_oto / oto_toplam) if oto_toplam else 1.0),
        "zero_pages": bos,
        "worst_pages": sorted(sapmalar,
                              key=lambda s: -abs(s["gold"] - s["pred"]))[:10],
    }


def olc(ad):
    """Motoru koşup sayım metriklerini raporlar."""
    yol_json = _kilitli_yol(ad)
    if not os.path.exists(yol_json):
        raise SystemExit(f"sayım-altını yok: {yol_json}")
    sayim = sayim_yukle(yol_json)
    oge = _oge_bul(ad)
    fmt, veriler, ornek_no, acik = dogrula.belge_isle(
        _yol_coz(oge), dpi=oge.get("dpi", 300),
        max_sayfa=oge.get("max_sayfa", 40),
        bas=oge.get("bas"), son=oge.get("son"))
    try:
        rapor = sayim_degerlendir(sayim, veriler, ornek_no)
    finally:
        sk.belge_kapat(acik)
    print(json.dumps(rapor, ensure_ascii=False, indent=1))
    return rapor


def main(argv=None):
    p = argparse.ArgumentParser(description="Sayım-altını (kör sayım) aracı")
    p.add_argument("--belge", required=True, metavar="AD")
    p.add_argument("--hazirla", action="store_true",
                   help="çıplak görselleri ve boş iskeleti üret")
    p.add_argument("--kilitle", action="store_true",
                   help="doldurulmuş taslağı doğrulayıp mühürle")
    p.add_argument("--olc", action="store_true",
                   help="motoru koşup sayım metriklerini raporla")
    p.add_argument("--dpi", type=int, default=150,
                   help="önizleme çözünürlüğü (yalnız --hazirla)")
    p.add_argument("--sayfalar", type=int, nargs="+", metavar="NO",
                   help="yalnız bu sayfalar için iskelet üret (tabakalı örneklem)")
    args = p.parse_args(argv)

    if args.hazirla:
        hazirla(args.belge, dpi=args.dpi, sayfalar_secili=args.sayfalar)
    elif args.kilitle:
        kilitle(args.belge)
    elif args.olc:
        olc(args.belge)
    else:
        p.error("--hazirla, --kilitle ya da --olc verin")
    return 0


if __name__ == "__main__":
    sys.exit(main())
