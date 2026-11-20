#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DocLayout-YOLO işçi süreci — YALNIZ .venv-ml (Python 3.10+) altında koşar.

duzen_model.py bu betiği alt süreç olarak başlatır ve satır-JSON
protokolüyle konuşur:
  başlangıç → {"ok": true, "cihaz": "mps"} | {"ok": false, "hata": "..."}
  stdin     ← {"id": N, "png": "/mutlak/yol.png"}
  stdout    → {"id": N, "bolgeler": [{"sinif","kutu","guven"}, ...]}
              (kutu = [x0,y0,x1,y1], girdi PNG'sinin piksel uzayında)
  stdin     ← {"cikis": true}  → süreç biter (stdin EOF de aynı etki)

stdout protokole ayrılmıştır: torch/ultralytics'in olası print'leri
başlangıçta stderr'e yönlendirilir (duzen_model.py stderr'i isci.log'a
bağlar). MPS'te ilk çıkarım hatasında kalıcı olarak CPU'ya düşülür.

Kullanım: .venv-ml/bin/python duzen_isci.py --model <pt>
          --model-sha256 <sha256> [--imgsz 1024]
          [--conf 0.2] [--cihaz mps|cpu] [--probe]
"""
import argparse
import hashlib
import json
import os
import sys
import tempfile


def _bolgeler(sonuc, ox=0.0, oy=0.0, olcek_adi="global"):
    """Ultralytics sonucunu ortak sayfa koordinatına taşır."""
    adlar = sonuc.names
    bolgeler = []
    for kutu in sonuc.boxes:
        x0, y0, x1, y1 = (float(v) for v in kutu.xyxy[0])
        bolgeler.append({"sinif": adlar[int(kutu.cls)],
                         "kutu": [x0 + ox, y0 + oy, x1 + ox, y1 + oy],
                         "guven": round(float(kutu.conf), 3),
                         "olcek": olcek_adi})
    return bolgeler


def _iou(a, b):
    ax0, ay0, ax1, ay1 = a["kutu"]
    bx0, by0, bx1, by1 = b["kutu"]
    w = max(0.0, min(ax1, bx1) - max(ax0, bx0))
    h = max(0.0, min(ay1, by1) - max(ay0, by0))
    kesisim = w * h
    if not kesisim:
        return 0.0
    alan_a = max(0.0, ax1 - ax0) * max(0.0, ay1 - ay0)
    alan_b = max(0.0, bx1 - bx0) * max(0.0, by1 - by0)
    return kesisim / max(alan_a + alan_b - kesisim, 1e-9)


def _tekillestir(bolgeler):
    """Global/yerel örtüşen aynı sınıf bölgeleri sınıf-içi NMS ile birleştir."""
    sonuc = []
    for b in sorted(bolgeler, key=lambda x: x["guven"], reverse=True):
        if any(b["sinif"] == k["sinif"] and _iou(b, k) >= 0.55
               for k in sonuc):
            continue
        sonuc.append(b)
    return sorted(sonuc, key=lambda x: (x["kutu"][1], x["kutu"][0]))


def _modeli_ozel_kopyaya_al(kaynak, beklenen_sha, hedef):
    """Paylaşılan model yolunu tek okumada özel kopyaya alıp SHA'yı doğrula."""
    ozet = hashlib.sha256()
    with open(kaynak, "rb") as giris, open(hedef, "wb") as cikis:
        while True:
            parca = giris.read(1 << 20)
            if not parca:
                break
            ozet.update(parca)
            cikis.write(parca)
    gercek = ozet.hexdigest()
    if gercek != beklenen_sha.lower():
        raise RuntimeError(
            f"model SHA-256 uyuşmuyor: {gercek} != {beklenen_sha.lower()}"
        )
    return gercek


def _tahmin(model, png, args, cihaz):
    """Belirsizlik tetiklemeli coarse-to-fine düzen çıkarımı.

    Önce tüm sayfa 1024 ölçeğinde görülür. Gövde bölgesi az ya da güveni düşük
    ise yüksek çözünürlüklü kaynak iki örtüşen yerel parçaya ayrılır. Böylece
    küçük seçenek/formül/şekiller ikinci geçişte daha fazla piksel görür;
    kesin sayfalar ise ek model maliyeti ödemez.
    """
    global_sonuc = model.predict(png, imgsz=args.imgsz, conf=args.conf,
                                 device=cihaz, verbose=False)[0]
    bolgeler = _bolgeler(global_sonuc)
    # Genel DocStructBench sınıfları VE soru-özel model sınıfları — soru
    # modelinde 'plain text' hiç üretilmediğinden govde hep boş kalıp her
    # sayfada gereksiz ikinci geçiş tetiklenmesin.
    govde = [b for b in bolgeler if b["sinif"] in {
        "plain text", "title", "figure", "table", "isolate_formula",
        "question_body", "shared_stimulus", "solution_or_answer"}]
    ort_guven = (sum(b["guven"] for b in govde) / len(govde)) if govde else 0
    belirsiz = len(govde) < 6 or ort_guven < 0.48
    if not belirsiz:
        return bolgeler

    try:
        from PIL import Image
        with Image.open(png) as kaynak:
            kaynak = kaynak.convert("RGB")
            w, h = kaynak.size
            if max(w, h) < args.imgsz * 1.25:
                return bolgeler
            if h >= w:
                parcalar = [(0, 0, w, int(h * 0.58)),
                             (0, int(h * 0.42), w, h)]
            else:
                parcalar = [(0, 0, int(w * 0.58), h),
                             (int(w * 0.42), 0, w, h)]
            for i, (x0, y0, x1, y1) in enumerate(parcalar):
                parca = kaynak.crop((x0, y0, x1, y1))
                sonuc = model.predict(parca, imgsz=args.imgsz,
                                      conf=args.conf, device=cihaz,
                                      verbose=False)[0]
                bolgeler.extend(_bolgeler(
                    sonuc, x0, y0, f"yerel_{i + 1}"))
    except Exception:
        # Yerel ikinci geçiş başarısızsa geçerli global sonuç korunur.
        return bolgeler
    return _tekillestir(bolgeler)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", required=True)
    p.add_argument("--model-sha256", required=True)
    p.add_argument("--imgsz", type=int, default=1024)
    p.add_argument("--conf", type=float, default=0.2)
    p.add_argument("--cihaz", default=None)
    p.add_argument("--probe", action="store_true")
    args = p.parse_args()

    # Protokol kanalını kütüphane gürültüsünden ayır: gerçek stdout'u
    # kopyala, fd 1'i stderr'e yönlendir → sonraki tüm print'ler log'a.
    proto = os.fdopen(os.dup(1), "w", buffering=1)
    os.dup2(2, 1)

    def yaz(obj):
        proto.write(json.dumps(obj, ensure_ascii=False) + "\n")

    try:
        import torch
        from doclayout_yolo import YOLOv10
        cihaz = args.cihaz or (
            "mps" if torch.backends.mps.is_available() else "cpu")
        if (
                len(args.model_sha256) != 64
                or any(c not in "0123456789abcdef"
                       for c in args.model_sha256.lower())):
            raise ValueError("--model-sha256 geçersiz")
        with tempfile.TemporaryDirectory(prefix="soru-model-isci-") as gecici:
            ozel_model = os.path.join(gecici, "dogrulanmis-model.pt")
            model_sha = _modeli_ozel_kopyaya_al(
                args.model,
                args.model_sha256,
                ozel_model,
            )
            asil_load = torch.load

            def sinirli_load(*load_args, **load_kwargs):
                if not load_args:
                    raise RuntimeError("torch.load model yolu eksik")
                gelen = os.path.realpath(os.fspath(load_args[0]))
                if gelen != os.path.realpath(ozel_model):
                    raise RuntimeError(
                        f"doğrulanmamış checkpoint reddedildi: {gelen}")
                load_kwargs["weights_only"] = False
                return asil_load(*load_args, **load_kwargs)

            torch.load = sinirli_load
            try:
                model = YOLOv10(ozel_model)
            finally:
                torch.load = asil_load
    except Exception as e:  # noqa: BLE001 — kurulum/model her türlü hata
        yaz({"ok": False, "hata": f"{type(e).__name__}: {e}"})
        return 1
    yaz({"ok": True, "cihaz": cihaz, "model_sha256": model_sha})
    if args.probe:
        return 0

    for satir in sys.stdin:
        satir = satir.strip()
        if not satir:
            continue
        try:
            istek = json.loads(satir)
        except ValueError:
            continue
        if istek.get("cikis"):
            break
        no = istek.get("id")
        try:
            yaz({"id": no, "model_sha256": model_sha,
                 "bolgeler": _tahmin(model, istek["png"], args, cihaz)})
        except Exception as e:  # noqa: BLE001
            if cihaz != "cpu":
                # MPS operatör boşluğu: bir kez CPU ile dene, kalıcı kal
                try:
                    cihaz = "cpu"
                    yaz({"id": no, "model_sha256": model_sha,
                         "bolgeler": _tahmin(
                             model, istek["png"], args, cihaz)})
                    continue
                except Exception as e2:  # noqa: BLE001
                    e = e2
            yaz({"id": no, "hata": f"{type(e).__name__}: {e}"})
    return 0


if __name__ == "__main__":
    sys.exit(main())
