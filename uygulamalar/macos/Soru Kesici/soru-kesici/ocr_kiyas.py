#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici — öz-denetimli OCR doğruluk kıyası (etiket gerektirmez).

Metin katmanlı PDF sayfası GERÇEK (ground truth) kabul edilir; aynı sayfa
OCR_RENDER_DPI'da raster'a çevrilip OCR motoruna verilir ve çıktı metin
katmanıyla karşılaştırılır. Böylece Apple Vision'ın (ve ileride eklenecek
motorların) Türkçe doğruluğu kendi belgelerinizle, elle etiketlemeden
ölçülür. _ocr_tr_duzelt katmanının kazancı da aynı OCR geçişinden ham ve
düzeltilmiş çift skorlamayla nicelenir.

Hizalama bbox-örtüşme tabanlıdır (okuma sırasından bağımsız → çok sütun
güvenli). Bilinen sapma: Vision iki GT satırını tek satırda birleştirirse
bir GT satırı tam silme sayılır (CER hafif yukarı yanlıdır); A/B-göreli
kıyasta iki taraf da aynı yanlılığı taşır.

Kullanım:
    python ocr_kiyas.py <belge.pdf> [max_sayfa] [--bas N | --aralik BAS SON]
                        [--motor vision] [--dpi 200] [--duzeltme-kapat]
Tek JSON metrik satırı basar (dogrula.py sözleşmesi).
"""

import json
import sys
import unicodedata
from collections import Counter

import fitz  # PyMuPDF

import soru_kes as sk
from dogrula import _ornek_indeksleri

TR_KARAKTERLER = "çğıöşüÇĞİÖŞÜ"
# GT metin katmanında kalmış başıboş diakritik → bozuk metin katmanı işareti
_SUPHELI_ISARETLER = "˘¸˙¨̧̆̇̈"
_LIGATURLER = str.maketrans({"ﬁ": "fi", "ﬂ": "fl"})

# Motor sözleşmesi: f(pil_img) -> [(metin, (x0,y0,x1,y1))] PİKSEL uzayında,
# metin HAM (düzeltmesiz) motor çıktısı. Yeni motor = bir fonksiyon + bir
# sözlük girdisi; başka hiçbir yer değişmez.
def _ensemble_motor(ad):
    """ocr_ensemble üzerinden tek motor okur (motor yoksa [])."""
    def _oku(img):
        try:
            import ocr_ensemble
            return ocr_ensemble.motor_satirlar(img, ad, duzelt=False)
        except Exception:  # noqa: BLE001
            return []
    return _oku


MOTORLAR = {
    "vision": lambda img: sk.vision_satirlar(img, duzelt=False),
    "easyocr": _ensemble_motor("easyocr"),
    "rapidocr": _ensemble_motor("rapidocr"),
    "tesseract": _ensemble_motor("tesseract"),
    "surya": _ensemble_motor("surya"),
}


def _kiyas_normalize(metin):
    """Her iki tarafa uygulanan asgari eşitleme: NFC + ﬁ/ﬂ ligatür açma +
    boşluk katlama. Tire/tırnak varyantları bilerek korunur (gerçek fark)."""
    metin = unicodedata.normalize("NFC", metin).translate(_LIGATURLER)
    return " ".join(metin.split())


def duzenle_mesafesi(a, b):
    """Levenshtein + geri-iz. Dönüş: (mesafe, islemler); islemler
    [('esit'|'degistir'|'sil'|'ekle', a_kar|None, b_kar|None)] sırasıyla.
    Satır düzeyinde çağrılır (≤ yüzlerce karakter) → tam matris ucuz."""
    n, m = len(a), len(b)
    D = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        D[i][0] = i
    for j in range(m + 1):
        D[0][j] = j
    for i in range(1, n + 1):
        ai, Di, Do = a[i - 1], D[i], D[i - 1]
        for j in range(1, m + 1):
            mal = 0 if ai == b[j - 1] else 1
            Di[j] = min(Do[j - 1] + mal, Do[j] + 1, Di[j - 1] + 1)
    islemler = []
    i, j = n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and D[i][j] == D[i - 1][j - 1] \
                + (0 if a[i - 1] == b[j - 1] else 1):
            islemler.append(("esit" if a[i - 1] == b[j - 1] else "degistir",
                             a[i - 1], b[j - 1]))
            i, j = i - 1, j - 1
        elif i > 0 and D[i][j] == D[i - 1][j] + 1:
            islemler.append(("sil", a[i - 1], None))
            i -= 1
        else:
            islemler.append(("ekle", None, b[j - 1]))
            j -= 1
    islemler.reverse()
    return D[n][m], islemler


def _hizala(gt, ocr):
    """Her OCR satırını en çok örtüşen GT satırına atar (dikey örtüşme ≥
    küçük yüksekliğin %50'si + yatay örtüşme > 0). Dönüş:
    (atama: {gt_idx: [(metin, kutu)]}, eslesmeyen: [(metin, kutu)])."""
    atama, eslesmeyen = {}, []
    for om, ok in ocr:
        en_iyi, en_alan = None, 0.0
        for gi, (_, gk) in enumerate(gt):
            dikey = min(ok[3], gk[3]) - max(ok[1], gk[1])
            if dikey <= 0:
                continue
            kucuk = min(ok[3] - ok[1], gk[3] - gk[1])
            if kucuk <= 0 or dikey < 0.5 * kucuk:
                continue
            yatay = min(ok[2], gk[2]) - max(ok[0], gk[0])
            if yatay <= 0:
                continue
            alan = dikey * yatay
            if alan > en_alan:
                en_alan, en_iyi = alan, gi
        if en_iyi is None:
            eslesmeyen.append((om, ok))
        else:
            atama.setdefault(en_iyi, []).append((om, ok))
    return atama, eslesmeyen


def sayfa_kiyasla(page, dpi, motor, duzeltme=True):
    """Tek sayfanın kıyas sayaçları. GT satırları PdfSayfa.satirlar()'dan
    (punto), OCR kutuları dpi/72 ile puntoya indirilir."""
    gt_ham = sk.PdfSayfa(page, dpi=300).satirlar()   # dpi satirlar'ı etkilemez
    gt, supheli = [], 0
    for metin, kutu, _ in gt_ham:
        norm = _kiyas_normalize(metin)
        if not norm:
            continue
        if any(c in _SUPHELI_ISARETLER for c in norm):
            supheli += 1
        gt.append((norm, kutu))
    if not gt:
        return None

    # RasterSayfa._img ile birebir aynı render tarifi: üretimin gördüğü piksel
    olcek = dpi / 72
    pix = page.get_pixmap(matrix=fitz.Matrix(olcek, olcek), alpha=False)
    from PIL import Image
    img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)

    ocr = []
    for metin, (x0, y0, x1, y1) in motor(img):
        norm = _kiyas_normalize(metin)
        if norm:
            ocr.append((norm, (x0 / olcek, y0 / olcek,
                               x1 / olcek, y1 / olcek)))

    atama, eslesmeyen = _hizala(gt, ocr)

    say = {"gt_satir": len(gt), "gt_karakter": 0, "eslesen_satir": 0,
           "eksik_satir": 0, "fazla_satir": len(eslesmeyen),
           "fazla_karakter": sum(len(m) for m, _ in eslesmeyen),
           "gt_supheli_satir": supheli, "hata_ham": 0, "hata_duz": 0,
           "tr": {}, "karisiklik": Counter()}
    for c in TR_KARAKTERLER:
        say["tr"][c] = {"toplam": 0, "dogru_ham": 0, "dogru_duzeltilmis": 0}

    for gi, (gt_metin, _) in enumerate(gt):
        say["gt_karakter"] += len(gt_metin)
        for c in gt_metin:
            if c in TR_KARAKTERLER:
                say["tr"][c]["toplam"] += 1
        parcalar = atama.get(gi)
        if not parcalar:
            say["eksik_satir"] += 1
            say["hata_ham"] += len(gt_metin)
            say["hata_duz"] += len(gt_metin)
            continue
        say["eslesen_satir"] += 1
        parcalar.sort(key=lambda p: p[1][0])
        ham = _kiyas_normalize(" ".join(m for m, _ in parcalar))
        mesafe, islemler = duzenle_mesafesi(gt_metin, ham)
        say["hata_ham"] += mesafe
        for op, gk, ok in islemler:
            if op == "esit" and gk in TR_KARAKTERLER:
                say["tr"][gk]["dogru_ham"] += 1
            if op == "degistir":
                say["karisiklik"][(gk, ok)] += 1
            elif op == "sil":
                say["karisiklik"][(gk, "∅")] += 1
            elif op == "ekle":
                say["karisiklik"][("∅", ok)] += 1
        if duzeltme:
            duz = _kiyas_normalize(" ".join(
                sk._ocr_tr_duzelt(m) for m, _ in parcalar))
            mesafe_d, islemler_d = duzenle_mesafesi(gt_metin, duz)
            say["hata_duz"] += mesafe_d
            for op, gk, _ in islemler_d:
                if op == "esit" and gk in TR_KARAKTERLER:
                    say["tr"][gk]["dogru_duzeltilmis"] += 1
    return say


def main(argv):
    args = [a for a in argv[1:]]
    if not args:
        print(__doc__.strip())
        return 2
    yol, max_sayfa, bas, son, motor_adi = args[0], 20, None, None, "vision"
    dpi, duzeltme = sk.OCR_RENDER_DPI, True
    kalan = args[1:]
    i = 0
    while i < len(kalan):
        a = kalan[i]
        if a == "--bas":
            bas = int(kalan[i + 1]); i += 2
        elif a == "--aralik":
            bas, son = int(kalan[i + 1]), int(kalan[i + 2]); i += 3
        elif a == "--motor":
            motor_adi = kalan[i + 1]; i += 2
        elif a == "--dpi":
            dpi = int(kalan[i + 1]); i += 2
        elif a == "--duzeltme-kapat":
            duzeltme = False; i += 1
        else:
            max_sayfa = int(a); i += 1
    if motor_adi not in MOTORLAR:
        print(f"bilinmeyen motor: {motor_adi} — mevcut: "
              f"{', '.join(sorted(MOTORLAR))}")
        return 2
    motor = MOTORLAR[motor_adi]

    doc = fitz.open(yol)
    try:
        idx = _ornek_indeksleri(len(doc), max_sayfa, bas, son)
        toplam = {"gt_satir": 0, "gt_karakter": 0, "eslesen_satir": 0,
                  "eksik_satir": 0, "fazla_satir": 0, "fazla_karakter": 0,
                  "gt_supheli_satir": 0, "hata_ham": 0, "hata_duz": 0}
        tr = {c: {"toplam": 0, "dogru_ham": 0, "dogru_duzeltilmis": 0}
              for c in TR_KARAKTERLER}
        karisiklik = Counter()
        sayfa_detay, atlanan, ornek_no = [], 0, []
        for i in idx:
            page = doc[i]
            try:
                if not sk.pdf_metin_yeterli(page):
                    atlanan += 1
                    continue
                say = sayfa_kiyasla(page, dpi, motor, duzeltme)
            except Exception as e:  # noqa: BLE001 — sayfa başına izole
                sayfa_detay.append({"sayfa": i + 1, "hata": str(e)})
                continue
            if say is None:
                atlanan += 1
                continue
            ornek_no.append(i + 1)
            for k in toplam:
                toplam[k] += say[k]
            for c in TR_KARAKTERLER:
                for k in tr[c]:
                    tr[c][k] += say["tr"][c][k]
            karisiklik.update(say["karisiklik"])
            detay = {"sayfa": i + 1, "gt_karakter": say["gt_karakter"],
                     "cer_ham": round(say["hata_ham"]
                                      / max(1, say["gt_karakter"]), 4)}
            if duzeltme:
                detay["cer_duzeltilmis"] = round(
                    say["hata_duz"] / max(1, say["gt_karakter"]), 4)
            sayfa_detay.append(detay)

        if not ornek_no:
            print(json.dumps({"dosya": yol.rsplit("/", 1)[-1],
                              "hata": "kullanılabilir metin katmanlı sayfa yok",
                              "atlanan_sayfa": atlanan}, ensure_ascii=False))
            return 2

        gt_k = max(1, toplam["gt_karakter"])
        sonuc = {
            "dosya": yol.rsplit("/", 1)[-1], "motor": motor_adi, "dpi": dpi,
            "sayfa": len(doc), "ornek_no": ornek_no,
            "atlanan_sayfa": atlanan,
            "gt_satir": toplam["gt_satir"],
            "gt_karakter": toplam["gt_karakter"],
            "eslesen_satir": toplam["eslesen_satir"],
            "eksik_satir": toplam["eksik_satir"],
            "fazla_satir": toplam["fazla_satir"],
            "fazla_karakter": toplam["fazla_karakter"],
            "gt_supheli_satir": toplam["gt_supheli_satir"],
            "cer_ham": round(toplam["hata_ham"] / gt_k, 4),
            "cer_duzeltilmis": (round(toplam["hata_duz"] / gt_k, 4)
                                if duzeltme else None),
            "tr_karakter": {c: v for c, v in tr.items() if v["toplam"]},
            "karisiklik": [[g, o, n] for (g, o), n
                           in karisiklik.most_common(15)],
            "sayfa_detay": sayfa_detay[:24],
        }
        print(json.dumps(sonuc, ensure_ascii=False))
        return 0
    finally:
        doc.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
