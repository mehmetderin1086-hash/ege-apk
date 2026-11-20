"""Sentetik el yazısı satır görüntüsü üretimi (HTR eğitim verisi).

Türkçe-doğrulanmış el yazısı fontlarıyla korpus satırlarını render eder,
gerçekçi bozunma (rotasyon, dalgalanma, mürekkep değişimi, gürültü, bulanıklık)
uygular ve ``<görüntü>.png`` + ``labels.jsonl`` (satır -> metin) çıktısı verir.
Bu klasör doğrudan Colab'daki TrOCR/Qwen ince ayar defterlerine girdi olur.

Not: Sadece pillow + numpy kullanır (opsiyonel bağımlılıkları zorlamamak için).
Colab'da daha zengin bozunma isteyen kullanıcı augraphy/straug ekleyebilir.
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from ..metin import nfc
from .fontlar import turkce_uygun_mu
from .korpus import korpus_uret


def _fontlari_topla(font_dizini: str | Path) -> list[Path]:
    uygun = []
    for yol in sorted(Path(font_dizini).glob("**/*")):
        if yol.suffix.lower() in {".ttf", ".otf"}:
            try:
                if turkce_uygun_mu(yol):
                    uygun.append(yol)
            except Exception:
                continue
    return uygun


def _dalga_uygula(im: Image.Image, rng: random.Random) -> Image.Image:
    """Satıra hafif dikey dalgalanma verir (el yazısı taban çizgisi düzensizliği)."""
    dizi = np.asarray(im)
    h, w = dizi.shape[:2]
    genlik = rng.uniform(0.5, 2.0)
    periyot = rng.uniform(w / 3, w)
    faz = rng.uniform(0, 2 * math.pi)
    kaydirma = (genlik * np.sin(2 * np.pi * np.arange(w) / periyot + faz)).astype(int)
    cikti = np.full_like(dizi, 255)
    for x in range(w):
        dy = kaydirma[x]
        if dy >= 0:
            cikti[dy:, x] = dizi[: h - dy, x] if dy else dizi[:, x]
        else:
            cikti[:dy, x] = dizi[-dy:, x]
    return Image.fromarray(cikti)


def _bozundur(im: Image.Image, rng: random.Random) -> Image.Image:
    # hafif rotasyon
    im = im.rotate(rng.uniform(-2.5, 2.5), expand=True, fillcolor=255, resample=Image.BICUBIC)
    im = _dalga_uygula(im, rng)
    # bulanıklık
    if rng.random() < 0.6:
        im = im.filter(ImageFilter.GaussianBlur(rng.uniform(0.3, 1.1)))
    dizi = np.asarray(im).astype(np.float32)
    # mürekkep koyuluğu + kâğıt tonu
    dizi = 255 - (255 - dizi) * rng.uniform(0.6, 1.0)
    dizi = dizi * rng.uniform(0.9, 1.0)
    # gauss gürültüsü
    dizi += rng.uniform(2, 12) * np.random.randn(*dizi.shape)
    # seyrek leke
    if rng.random() < 0.3:
        maske = np.random.rand(*dizi.shape[:2]) < rng.uniform(0.0005, 0.003)
        dizi[maske] = rng.uniform(0, 80)
    return Image.fromarray(np.clip(dizi, 0, 255).astype(np.uint8))


def _satir_ciz(metin: str, font: ImageFont.FreeTypeFont, rng: random.Random) -> Image.Image:
    # Genişliği harf harf ilerleteceğimiz gerçek avans toplamından hesapla;
    # bbox genişliği kerning'siz avans toplamından küçük olabilir ve son harfleri
    # kırpar → etiket metniyle görüntü uyuşmaz (HTR verisini kirletir).
    olcum = ImageDraw.Draw(Image.new("L", (1, 1)))
    avans = sum(olcum.textlength(ch, font=font) for ch in metin)
    kutu = font.getbbox(metin)
    yuk = (kutu[3] - kutu[1]) + 30
    im = Image.new("L", (int(avans) + 40, yuk), 255)
    ciz = ImageDraw.Draw(im)
    x = 20.0
    # harf harf hafif dikey/renk oynaması → daha az "matbaa" görünümü
    taban = 15 - kutu[1]
    for ch in metin:
        dy = rng.randint(-2, 2)
        koyu = rng.randint(0, 70)
        ciz.text((x, taban + dy), ch, font=font, fill=koyu)
        x += ciz.textlength(ch, font=font)
    return im.crop((0, 0, int(x) + 20, yuk))


def veri_uret(
    cikti_dizini: str | Path,
    font_dizini: str | Path,
    adet: int = 2000,
    tohum: int = 0,
    ek_terimler: list[str] | None = None,
    punto_araligi: tuple[int, int] = (34, 52),
    benzersiz_metin: bool = True,
) -> dict:
    """Sentetik el yazısı satır veri seti üretir.

    ``benzersiz_metin`` açıkken aynı cümle yeniden üretilmez. Yinelenen
    metinler kodçözücünün cümleyi ezberleyip görüntüyü yok saymasına yol
    açar (eğitim kaybı sıfıra iner ama serbest üretimde CER düşmez).

    Döner: {"uretilen": n, "font_sayisi": k, "benzersiz_metin": m,
    "labels": <jsonl yolu>}
    """
    cikti = Path(cikti_dizini)
    (cikti / "img").mkdir(parents=True, exist_ok=True)
    fontlar = _fontlari_topla(font_dizini)
    if not fontlar:
        raise RuntimeError(
            f"{font_dizini} içinde Türkçe-uygun font bulunamadı. "
            "colab/01 defterindeki font indirme adımını çalıştırın."
        )

    rng = random.Random(tohum)
    np.random.seed(tohum)
    satirlar = korpus_uret(adet, tohum, ek_terimler, benzersiz=benzersiz_metin)
    label_yolu = cikti / "labels.jsonl"

    with open(label_yolu, "w", encoding="utf-8") as f:
        for i, metin in enumerate(satirlar):
            metin = nfc(metin)
            font_yolu = rng.choice(fontlar)
            punto = rng.randint(*punto_araligi)
            font = ImageFont.truetype(str(font_yolu), punto)
            im = _bozundur(_satir_ciz(metin, font, rng), rng)
            dosya = f"img/{i:06d}.png"
            im.save(cikti / dosya)
            f.write(json.dumps({"image": dosya, "text": metin}, ensure_ascii=False) + "\n")

    return {
        "uretilen": len(satirlar),
        "font_sayisi": len(fontlar),
        "benzersiz_metin": len(set(satirlar)),
        "labels": str(label_yolu),
    }
