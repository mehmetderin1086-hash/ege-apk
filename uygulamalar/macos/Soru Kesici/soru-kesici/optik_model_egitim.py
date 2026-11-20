#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Optik balon sınıflandırıcı eğitimi — YALNIZ .venv-ml (torch) altında koşar.

Karalanmış/iptal işaretleri salt doluluk oranıyla ayrılamaz (X çekilmiş
balon çoğu kez silik doludan daha mürekkeplidir). Bu betik TAMAMEN
SENTETİK 64×64 balon kırpmaları üretir (halka + harf + dolgu stilleri +
bozulmalar), ~70k parametreli küçük bir CNN eğitir (sınıflar:
bos/dolu/iptal/kismi) ve ağırlığı manifest kilidiyle kaydeder
(duzen_model'in soru-modeli manifest deseni). İşçi (optik_isci.py)
ağırlık varsa balon başına sınıf + güven ekler; istemci (optik_oku)
bunu klasik skorla ÇAPRAZ KONTROL olarak kullanır (iptal arıtması).

Kullanım (.venv-ml altında):
  .venv-ml/bin/python optik_model_egitim.py uret --adet 48000 -o balon_veri.npz
  .venv-ml/bin/python optik_model_egitim.py egit --veri balon_veri.npz
  .venv-ml/bin/python optik_model_egitim.py hepsi          # ikisi bir arada
"""
import argparse
import datetime
import hashlib
import json
import os
import random
import sys

BOYUT = 64
SINIFLAR = ("bos", "dolu", "iptal", "kismi")
SEMA_SURUMU = "soru-kesici.optik-balon-model/v1"
MODEL_DIZIN = os.path.expanduser(
    "~/Library/Application Support/soru-kesici/modeller")
MODEL_YOLU = os.path.join(MODEL_DIZIN, "optik_balon_v1.pt")


# ------------------------------------------------------------- sentetik veri

def _kirpma_uret(rnd, sinif):
    """Tek 64×64 gri kırpma: halka + harf + sınıfa göre dolgu + bozulma."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    img = Image.new("L", (BOYUT, BOYUT), rnd.randint(235, 255))
    ciz = ImageDraw.Draw(img)
    cx = BOYUT / 2 + rnd.uniform(-4, 4)
    cy = BOYUT / 2 + rnd.uniform(-4, 4)
    yari = rnd.uniform(15, 23)
    halka_g = rnd.randint(0, 80)
    ciz.ellipse([cx - yari, cy - yari, cx + yari, cy + yari],
                outline=halka_g, width=rnd.randint(1, 3))
    # balon içi harf (boş/kısmi/iptalde görünür kalır)
    if rnd.random() < 0.9:
        harf = rnd.choice("ABCDE0123456789")
        hg = rnd.randint(120, 185)
        ciz.text((cx - 4, cy - 6), harf, fill=hg)

    def dolgu(oran, renk):
        r = yari * oran
        dx, dy = rnd.uniform(-3, 3), rnd.uniform(-3, 3)
        ciz.ellipse([cx + dx - r, cy + dy - r * rnd.uniform(.85, 1.1),
                     cx + dx + r, cy + dy + r * rnd.uniform(.85, 1.1)],
                    fill=renk)

    def cizik(adet):
        for _ in range(adet):
            a1 = rnd.uniform(0, 6.283)
            a2 = a1 + rnd.uniform(2.4, 3.9)
            import math
            u = rnd.uniform(1.0, 1.35)
            ciz.line([cx + math.cos(a1) * yari * u,
                      cy + math.sin(a1) * yari * u,
                      cx + math.cos(a2) * yari * u,
                      cy + math.sin(a2) * yari * u],
                     fill=rnd.randint(20, 90),
                     width=rnd.randint(2, 5))

    if sinif == "dolu":
        dolgu(rnd.uniform(0.7, 1.1), rnd.randint(15, 95))
        if rnd.random() < 0.2:          # bastırılmış koyu kalem + taşma
            dolgu(rnd.uniform(0.4, 0.7), rnd.randint(5, 40))
    elif sinif == "kismi":
        if rnd.random() < 0.5:
            dolgu(rnd.uniform(0.3, 0.55), rnd.randint(30, 110))   # ufak leke
        else:
            dolgu(rnd.uniform(0.7, 1.0), rnd.randint(140, 195))   # silik
    elif sinif == "iptal":
        if rnd.random() < 0.45:         # silinmiş izi + üstüne X
            dolgu(rnd.uniform(0.6, 0.95), rnd.randint(190, 220))
        cizik(rnd.randint(1, 3))

    arr = np.asarray(img, dtype=np.float32)
    # aydınlatma eğimi + gürültü + bulanıklık
    gx = np.linspace(rnd.uniform(.85, 1.0), rnd.uniform(.95, 1.12), BOYUT)
    gy = np.linspace(rnd.uniform(.9, 1.0), rnd.uniform(.95, 1.08), BOYUT)
    arr = arr * gx[None, :] * gy[:, None]
    arr += np.random.default_rng(rnd.randrange(1 << 30)).normal(
        0, rnd.uniform(1, 9), arr.shape)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    if rnd.random() < 0.6:
        img = img.filter(ImageFilter.GaussianBlur(rnd.uniform(0.2, 1.1)))
    if rnd.random() < 0.5:
        img = img.rotate(rnd.uniform(-6, 6), fillcolor=245)
    return np.asarray(img, dtype=np.uint8)


def veri_uret(adet, yol, tohum=42):
    import numpy as np
    rnd = random.Random(tohum)
    X = np.empty((adet, BOYUT, BOYUT), dtype=np.uint8)
    y = np.empty(adet, dtype=np.int64)
    for i in range(adet):
        sinif = i % len(SINIFLAR)
        X[i] = _kirpma_uret(rnd, SINIFLAR[sinif])
        y[i] = sinif
        if (i + 1) % 8000 == 0:
            print(f"  {i + 1}/{adet}")
    np.savez_compressed(yol, X=X, y=y,
                        siniflar=np.array(SINIFLAR, dtype=object))
    print(f"veri yazıldı: {yol} ({adet} örnek)")
    return yol


# --------------------------------------------------------------------- model

def _model_kur():
    import torch.nn as nn

    class BalonAgi(nn.Module):
        def __init__(self):
            super().__init__()
            def blok(gi, go):
                return nn.Sequential(
                    nn.Conv2d(gi, go, 3, padding=1, bias=False),
                    nn.BatchNorm2d(go), nn.ReLU(inplace=True),
                    nn.MaxPool2d(2))
            self.govde = nn.Sequential(
                blok(1, 16), blok(16, 32), blok(32, 64),
                nn.Conv2d(64, 64, 3, padding=1, bias=False),
                nn.BatchNorm2d(64), nn.ReLU(inplace=True),
                nn.AdaptiveAvgPool2d(1))
            self.kafa = nn.Linear(64, len(SINIFLAR))

        def forward(self, x):
            return self.kafa(self.govde(x).flatten(1))
    return BalonAgi()


def egit(veri_yolu, model_yolu=MODEL_YOLU, donem=4, parti=256):
    import numpy as np
    import torch
    from torch.utils.data import DataLoader, TensorDataset

    veri = np.load(veri_yolu, allow_pickle=True)
    X = torch.from_numpy(veri["X"]).float().unsqueeze(1) / 255.0
    y = torch.from_numpy(veri["y"])
    n_dogrulama = max(1000, len(X) // 10)
    Xe, ye = X[:-n_dogrulama], y[:-n_dogrulama]
    Xd, yd = X[-n_dogrulama:], y[-n_dogrulama:]
    cihaz = "mps" if torch.backends.mps.is_available() else "cpu"
    model = _model_kur().to(cihaz)
    p_sayi = sum(p.numel() for p in model.parameters())
    print(f"cihaz: {cihaz}, parametre: {p_sayi:,}")
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    kayip_f = torch.nn.CrossEntropyLoss()
    yukleyici = DataLoader(TensorDataset(Xe, ye), batch_size=parti,
                           shuffle=True)
    for d in range(donem):
        model.train()
        toplam = 0.0
        for xb, yb in yukleyici:
            xb, yb = xb.to(cihaz), yb.to(cihaz)
            opt.zero_grad()
            kayip = kayip_f(model(xb), yb)
            kayip.backward()
            opt.step()
            toplam += float(kayip) * len(xb)
        model.eval()
        with torch.no_grad():
            dogru = saymak = 0
            for i in range(0, len(Xd), 1024):
                xb = Xd[i:i + 1024].to(cihaz)
                tahmin = model(xb).argmax(1).cpu()
                dogru += int((tahmin == yd[i:i + 1024]).sum())
                saymak += len(xb)
        dogruluk = dogru / saymak
        print(f"dönem {d + 1}/{donem}: kayıp {toplam / len(Xe):.4f}  "
              f"doğrulama {dogruluk:.4f}")
    os.makedirs(os.path.dirname(model_yolu), exist_ok=True)
    model.cpu().eval()
    torch.save(model.state_dict(), model_yolu)
    ozet = hashlib.sha256(open(model_yolu, "rb").read()).hexdigest()
    manifest = {
        "schema_version": SEMA_SURUMU,
        "model_version": "v1",
        "classes": list(SINIFLAR),
        "input_size": BOYUT,
        "weights_sha256": ozet,
        "weights_size": os.path.getsize(model_yolu),
        "val_accuracy": round(dogruluk, 4),
        "created": datetime.datetime.now().isoformat(timespec="seconds"),
    }
    with open(model_yolu + ".manifest.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f"model yazıldı: {model_yolu} (doğrulama {dogruluk:.2%})")
    return model_yolu


def model_yukle(model_yolu=MODEL_YOLU):
    """İşçi tarafı: manifest doğrulanmış model | None (torch yoksa da None)."""
    try:
        import torch
    except ImportError:
        return None
    try:
        with open(model_yolu + ".manifest.json", encoding="utf-8") as f:
            manifest = json.load(f)
        if manifest.get("schema_version") != SEMA_SURUMU or \
                tuple(manifest.get("classes") or ()) != SINIFLAR:
            return None
        ozet = hashlib.sha256(open(model_yolu, "rb").read()).hexdigest()
        if ozet != manifest.get("weights_sha256"):
            return None
        model = _model_kur()
        model.load_state_dict(torch.load(model_yolu, map_location="cpu"))
        model.eval()
        return model
    except (OSError, ValueError, RuntimeError):
        return None


def main():
    p = argparse.ArgumentParser(description=__doc__)
    alt = p.add_subparsers(dest="komut", required=True)
    u = alt.add_parser("uret")
    u.add_argument("--adet", type=int, default=48000)
    u.add_argument("-o", "--cikti", default="balon_veri.npz")
    u.add_argument("--tohum", type=int, default=42)
    e = alt.add_parser("egit")
    e.add_argument("--veri", default="balon_veri.npz")
    e.add_argument("-o", "--cikti", default=MODEL_YOLU)
    e.add_argument("--donem", type=int, default=4)
    h = alt.add_parser("hepsi")
    h.add_argument("--adet", type=int, default=48000)
    h.add_argument("--donem", type=int, default=4)
    args = p.parse_args()
    if args.komut == "uret":
        veri_uret(args.adet, args.cikti, args.tohum)
    elif args.komut == "egit":
        egit(args.veri, args.cikti, donem=args.donem)
    else:
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            veri = os.path.join(d, "veri.npz")
            veri_uret(args.adet, veri)
            egit(veri, donem=args.donem)
    return 0


if __name__ == "__main__":
    sys.exit(main())
