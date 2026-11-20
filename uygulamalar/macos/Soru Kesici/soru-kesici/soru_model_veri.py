#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru-özel model (question_layout_v3) için sözde-etiket veri hattı.

Kullanıcının PDF korpusunu belge_analiz_et ile işler; YALNIZ yüksek-güvenli
(saf) sayfaları YOLO etiketli eğitim örneğine çevirir. Etiket saflığı için
sıkı kural: bir sayfa ancak reddedilmemiş TÜM adayları 'otomatik' &
kalibre_guven ≥ min_guven ise, riski/anomalisi yoksa ve düzen güveni
yüksekse veri setine girer (kısmen emin sayfa BÜTÜNÜYLE atılır — çünkü
etiketlenmemiş gerçek soru eğitimde zehirli false-negative).

Sınıf eşlemesi:
  numara_kutu  → 0 question_anchor
  kutu (body)  → 1 question_body
  ortak uyaran → 2 shared_stimulus   (_ortak_uyaran_haritasi)
  çözüm bloğu  → 3 solution_or_answer (fmt=cozumlu, sayfa_rolu=çözüm)

Manifest soru_model_egitim.EGITIM_SEMA_SURUMU sözleşmesindedir; kaynak
adları manifestte YASAK (sha→yol eşlemesi ayrı korpus_haritasi.json'da).

Kullanım:
    .venv/bin/python soru_model_veri.py --korpus "Desktop/Yeni klasör (3)" \
        --cikti ~/Library/Application\ Support/soru-kesici/egitim/ql_v3 \
        --dpi 200 --min-guven 0.90
    .venv/bin/python soru_model_veri.py --cikti <dizin> --denetim 150
"""

import argparse
import glob
import hashlib
import json
import os
import random
import sys

import soru_kes as sk

SINIFLAR = ("question_anchor", "question_body", "shared_stimulus",
            "solution_or_answer")
GORUNTU_UZANTILARI = (".pdf", ".png", ".jpg", ".jpeg", ".tif", ".tiff",
                      ".bmp", ".webp", ".docx")
# Belge-bazlı split oranları (yayınevi izolasyonlu)
SPLIT_ORAN = [("train", 0.70), ("validation", 0.15),
              ("calibration", 0.07), ("holdout", 0.08)]


def _dosya_sha256(yol):
    h = hashlib.sha256()
    with open(yol, "rb") as f:
        for parca in iter(lambda: f.read(1 << 20), b""):
            h.update(parca)
    return h.hexdigest()


def _yayinevi_grubu(ad):
    """Dosya adından opak yayınevi grubu (split izolasyonu için kaba imza)."""
    kok = os.path.splitext(os.path.basename(ad))[0].lower()
    for anahtar in ("palme", "aydin", "aydın", "3d", "oky", "prf", "meb",
                    "sınav", "sinav", "esen", "bilgi", "limit", "endemik"):
        if anahtar in kok:
            return "pub-" + hashlib.sha1(anahtar.encode()).hexdigest()[:6]
    # bilinmeyen: dosya sha'sının önekiyle kendi grubu
    return "pub-" + hashlib.sha1(kok.encode()).hexdigest()[:6]


# Sayfa-BÜTÜNÜ dışlayan riskler: KAÇAN soru işareti (etiketlenmemiş gerçek
# soru eğitimde zehirli false-negative). Diğer riskler (düşük aday güveni,
# egik tarama) sayfayı dışlamaz; yalnız düşük-güvenli kutular etiketlenmez.
_KACAN_SORU_RISKLERI = frozenset({
    "adaysiz_soru_sayfasi", "soru_sinyali_var_aday_yok"})


def _sayfa_saf_mi(analiz, min_guven):
    """Sayfa eğitim setine girer mi? Kaçan-soru riski / pipeline hatası yoksa
    ve ≥1 yeterince güvenli (kalibre_guven ≥ taban) kutu varsa. Etiketlenecek
    kutular: reddedilmemiş VE kalibre_guven ≥ taban (0.55; incele dahil —
    bunlar eşiğin hemen altındaki gerçek sorular). Dönüş: (kabul, gorunen) |
    False."""
    if analiz.pipeline_hatalari:
        return False
    if any(r in _KACAN_SORU_RISKLERI for r in analiz.risk_nedenleri):
        return False
    if analiz.duzen_guveni < 0.60:
        return False
    taban = min(0.55, min_guven)
    gorunen = [m for m in analiz.adaylar if not m.devam_aday]
    kabul = []
    for m in gorunen:
        if m.inceleme_durumu == "reddedildi":
            continue
        kg = m.kalibre_guven if m.kalibre_guven is not None else m.guven
        if kg >= taban:
            kabul.append(m)
    if not kabul:
        return False
    # En az bir YÜKSEK güvenli (otomatik & ≥min_guven) kutu şart: saf-olmayan
    # sayfa da az da olsa güvenilir çapa taşımalı.
    if not any(m.inceleme_durumu == "otomatik"
               and (m.kalibre_guven if m.kalibre_guven is not None
                    else m.guven) >= min_guven for m in kabul):
        return False
    return kabul, gorunen


def _yolo_satiri(sinif, kutu, G, Y):
    """(x0,y0,x1,y1) layout → YOLO 'sinif cx cy w h' [0,1] normalize.
    Köşeler ÖNCE [0,G]×[0,Y]'ye kırpılır → kutu tümüyle görüntü içinde kalır
    (merkez+boyut sonradan clamp'lense taşma kalabilirdi)."""
    x0, y0, x1, y1 = kutu
    x0, x1 = sorted((max(0.0, min(G, x0)), max(0.0, min(G, x1))))
    y0, y1 = sorted((max(0.0, min(Y, y0)), max(0.0, min(Y, y1))))
    w = (x1 - x0) / G
    h = (y1 - y0) / Y
    if w <= 1e-4 or h <= 1e-4:
        return None
    cx = (x0 + x1) / 2 / G
    cy = (y0 + y1) / 2 / Y
    return f"{sinif} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}"


def _sayfa_etiketleri(sayfa, kabul, fmt):
    """Bir sayfanın YOLO etiket satırlarını üretir (layout koordinat)."""
    G, Y = float(sayfa.genislik), float(sayfa.yukseklik)
    satirlar = []
    for m in kabul:
        # Bir kutu tek bir semantik gövde sınıfı alır. Çözüm rolündeki kutuyu
        # önce question_body, sonra solution_or_answer olarak iki kez yazmak
        # çelişkili hedef üretir ve manifest doğrulamasını da haklı olarak
        # başarısız kılar.
        govde_sinifi = 3 if m.sayfa_rolu == "çözüm" else 1
        s = _yolo_satiri(govde_sinifi, tuple(m.kutu), G, Y)
        if s:
            satirlar.append(s)
        if m.numara_kutu is not None:
            s = _yolo_satiri(0, tuple(m.numara_kutu), G, Y)  # question_anchor
            if s:
                satirlar.append(s)
    # ortak uyaran (varsa)
    try:
        ocr_satirlari = sayfa.satirlar()
        _meta, bantlar, _f = sk.sorulari_tespit_meta(sayfa, fmt)
        harita = sk._ortak_uyaran_haritasi(sayfa, ocr_satirlari, bantlar)
        gorulen = set()
        for kutu in (harita or {}).values():
            anahtar = tuple(round(v, 1) for v in kutu)
            if anahtar in gorulen:
                continue
            gorulen.add(anahtar)
            s = _yolo_satiri(2, tuple(kutu), G, Y)     # shared_stimulus
            if s:
                satirlar.append(s)
    except Exception:  # noqa: BLE001 — ortak uyaran zorunlu değil
        pass
    return [s for s in satirlar if isinstance(s, str)]


def korpus_isle(korpus, cikti, dpi=200, min_guven=0.90, negatif_oran=0.12,
                tohum=42, ilerleme=None):
    """Korpusu YOLO veri setine çevirir. Dönüş: {ozet, manifest_yolu}."""
    dosyalar = []
    for kok in korpus:
        if os.path.isdir(kok):
            for uz in GORUNTU_UZANTILARI:
                dosyalar += glob.glob(os.path.join(kok, "**", "*" + uz),
                                      recursive=True)
        elif os.path.isfile(kok):
            dosyalar.append(kok)
    dosyalar = sorted(set(dosyalar))
    if not dosyalar:
        raise ValueError("korpusta işlenecek dosya yok")

    os.makedirs(cikti, exist_ok=True)
    for split, _ in SPLIT_ORAN:
        os.makedirs(os.path.join(cikti, "images", split), exist_ok=True)
        os.makedirs(os.path.join(cikti, "labels", split), exist_ok=True)

    # Belgeleri yayınevi grubuna göre split'e ata (yayınevi izolasyonu)
    rnd = random.Random(tohum)
    gruplar = {}
    for d in dosyalar:
        gruplar.setdefault(_yayinevi_grubu(d), []).append(d)
    grup_split = {}
    grup_listesi = sorted(gruplar)
    rnd.shuffle(grup_listesi)
    # oranları grup sayısına dağıt
    i = 0
    for split, oran in SPLIT_ORAN:
        n = max(1, round(len(grup_listesi) * oran)) if grup_listesi else 0
        for g in grup_listesi[i:i + n]:
            grup_split[g] = split
        i += n
    for g in grup_listesi[i:]:
        grup_split[g] = "train"

    manifest = {"schema_version":
                "soru-kesici.question-layout-training/v1",
                "dataset_id": "korpus-" + hashlib.sha1(
                    "".join(dosyalar).encode()).hexdigest()[:12],
                "classes": list(SINIFLAR), "root": ".",
                "splits": {s: [] for s, _ in SPLIT_ORAN}}
    korpus_haritasi = {}          # sha → gerçek yol (manifest DIŞINDA)
    ozet = {"belge": 0, "saf_sayfa": 0, "negatif": 0, "kutu": 0,
            "atlanan_belge": 0}

    for di, dosya in enumerate(dosyalar):
        if ilerleme:
            ilerleme(di + 1, len(dosyalar), os.path.basename(dosya))
        try:
            sha = _dosya_sha256(dosya)
            grup = _yayinevi_grubu(dosya)
            split = grup_split.get(grup, "train")
            sayfalar, acik, fmt, _sx = sk.belge_hazirla([dosya], dpi)
            korpus_haritasi[sha] = dosya
        except Exception as e:  # noqa: BLE001 — bozuk belge atlanır
            ozet["atlanan_belge"] += 1
            continue
        try:
            _profil, analizler = sk.belge_analiz_et(sayfalar, fmt=fmt,
                                                    girdiler=[dosya])
            ozet["belge"] += 1
            for si, (sayfa, analiz) in enumerate(zip(sayfalar, analizler)):
                saf = _sayfa_saf_mi(analiz, min_guven)
                negatif = False
                if saf is False:
                    # negatif örnek adayı: rol soru-dışı + sıfır kabul
                    rol_disi = analiz.sayfa_rolu in (
                        "kapak", "içindekiler", "konu", "cevap_anahtari")
                    kabul_var = any(m.inceleme_durumu != "reddedildi"
                                    for m in analiz.adaylar if not m.devam_aday)
                    if rol_disi and not kabul_var and rnd.random() < negatif_oran:
                        negatif, kabul = True, []
                    else:
                        continue
                else:
                    kabul, _gorunen = saf
                etiketler = ([] if negatif
                             else _sayfa_etiketleri(sayfa, kabul, fmt))
                if not negatif and not etiketler:
                    continue
                ad = f"{sha[:12]}-p{si:04d}"
                img_rel = f"images/{split}/{ad}.png"
                lbl_rel = f"labels/{split}/{ad}.txt"
                pil, _olcek = sayfa.gorsel()
                pil.convert("RGB").save(os.path.join(cikti, img_rel),
                                        "PNG", compress_level=3)
                with open(os.path.join(cikti, lbl_rel), "w") as f:
                    f.write("\n".join(etiketler))
                manifest["splits"][split].append({
                    "image": img_rel, "label": lbl_rel,
                    "document_sha256": sha, "page": si + 1,
                    "publisher_group": grup})
                if negatif:
                    ozet["negatif"] += 1
                else:
                    ozet["saf_sayfa"] += 1
                    ozet["kutu"] += len(etiketler)
        finally:
            sk.belge_kapat(acik)

    manifest_yolu = os.path.join(cikti, "manifest.json")
    with open(manifest_yolu, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    with open(os.path.join(cikti, "korpus_haritasi.json"), "w",
              encoding="utf-8") as f:
        json.dump(korpus_haritasi, f, ensure_ascii=False, indent=1)
    return {"ozet": ozet, "manifest_yolu": manifest_yolu, "cikti": cikti}


def denetim_uret(cikti, n=150, tohum=7):
    """Rastgele N etiketli sayfayı kutular çizilmiş kontak PNG'lerine dizer
    (insan örnekleme denetimi). Dönüş: kontak sayfası yolu."""
    from PIL import Image, ImageDraw
    manifest = json.load(open(os.path.join(cikti, "manifest.json")))
    ornekler = []
    for split in ("train", "validation"):
        ornekler += manifest["splits"].get(split, [])
    rnd = random.Random(tohum)
    sec = rnd.sample(ornekler, min(n, len(ornekler)))
    renk = {"0": (235, 145, 20), "1": (20, 155, 70),
            "2": (60, 90, 220), "3": (205, 35, 45)}
    denetim_dizin = os.path.join(cikti, "denetim")
    os.makedirs(denetim_dizin, exist_ok=True)
    yollar = []
    for i, o in enumerate(sec):
        img = Image.open(os.path.join(cikti, o["image"])).convert("RGB")
        d = ImageDraw.Draw(img)
        W, H = img.size
        lbl = os.path.join(cikti, o["label"])
        for satir in open(lbl).read().splitlines():
            p = satir.split()
            if len(p) != 5:
                continue
            s, cx, cy, w, h = p
            cx, cy, w, h = float(cx) * W, float(cy) * H, float(w) * W, float(h) * H
            d.rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2],
                        outline=renk.get(s, (0, 0, 0)), width=3)
        oran = 620 / max(img.width, 1)
        if oran < 1:
            img = img.resize((620, max(1, int(img.height * oran))))
        yol = os.path.join(denetim_dizin, f"denetim_{i:03d}.png")
        img.save(yol)
        yollar.append(yol)
    return {"dizin": denetim_dizin, "sayfa": len(yollar)}


def main(argv=None):
    p = argparse.ArgumentParser(description="Soru modeli sözde-etiket verisi")
    p.add_argument("--korpus", nargs="+", help="PDF/görüntü dizin(ler)i")
    p.add_argument("--cikti", required=True, help="veri seti kök dizini")
    p.add_argument("--dpi", type=int, default=200)
    p.add_argument("--min-guven", type=float, default=0.90)
    p.add_argument("--denetim", type=int, default=0,
                   help="N sayfa için kontak denetim sayfaları üret")
    args = p.parse_args(argv)

    if args.denetim:
        sonuc = denetim_uret(args.cikti, n=args.denetim)
        print(f"Denetim: {sonuc['sayfa']} sayfa → {sonuc['dizin']}")
        print("Kötü sayfaları not edip eşiği yükseltebilirsiniz.")
        return 0

    if not args.korpus:
        p.error("--korpus gerekli (ya da --denetim)")

    def _il(i, n, ad):
        print(f"  [{i}/{n}] {ad[:50]}")

    sonuc = korpus_isle(args.korpus, args.cikti, dpi=args.dpi,
                        min_guven=args.min_guven, ilerleme=_il)
    o = sonuc["ozet"]
    print(f"\n✓ Veri seti: {o['saf_sayfa']} saf sayfa + {o['negatif']} "
          f"negatif, {o['kutu']} kutu ({o['belge']} belge, "
          f"{o['atlanan_belge']} atlandı)")
    print(f"  manifest: {sonuc['manifest_yolu']}")
    # manifest doğrula
    try:
        import soru_model_egitim
        rapor = soru_model_egitim.manifest_dogrula(sonuc["manifest_yolu"])
        print(f"  manifest doğrulama: {'ok' if rapor['ok'] else 'HATA'}")
        if not rapor["ok"]:
            for h in rapor["hatalar"][:6]:
                print(f"    - {h}")
    except Exception as e:  # noqa: BLE001
        print(f"  doğrulama atlandı: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
