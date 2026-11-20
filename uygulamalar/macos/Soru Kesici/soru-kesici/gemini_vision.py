#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Düşük güvenli sayfalarda isteğe bağlı Gemini Vision ikinci görüşü.

Varsayılan kapalıdır. Belgenin tamamı değil, yalnız yerel motorun emin
olamadığı sayfanın küçültülmüş görüntüsü gönderilir. Bu modül karar vermez;
normalize koordinat/rol önerisi döndürür. Çekirdek, öneriyi yerel numara veya
aday kanıtıyla doğrulamadan kullanmaz.
"""

import base64
import io
import json
import os

import gemini_konu

AYAR_YOLU = os.path.expanduser("~/.soru_kesici.json")

_SEMA = {
    "type": "object",
    "properties": {
        "sayfa_rolu": {"type": "string", "enum": [
            "kapak", "içindekiler", "konu", "soru", "çözüm",
            "cevap_anahtarı", "karma"]},
        "sorular": {"type": "array", "items": {
            "type": "object", "properties": {
                "x0": {"type": "integer"}, "y0": {"type": "integer"},
                "x1": {"type": "integer"}, "y1": {"type": "integer"},
                "soru_turu": {"type": "string"},
                "guven": {"type": "number"}},
            "required": ["x0", "y0", "x1", "y1", "soru_turu", "guven"]}},
    },
    "required": ["sayfa_rolu", "sorular"],
}


def _ayar():
    try:
        with open(AYAR_YOLU, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def aktif_mi():
    ortam = os.environ.get("SORU_KESICI_GEMINI_VISION")
    if ortam in ("0", "1"):
        return ortam == "1"
    return bool(_ayar().get("gemini_vision_aktif"))


def _png(img, maks=1600):
    kopya = img.convert("RGB")
    kopya.thumbnail((maks, maks))
    bio = io.BytesIO()
    kopya.save(bio, "JPEG", quality=82, optimize=True)
    return base64.b64encode(bio.getvalue()).decode("ascii")


def sayfa_analiz_et(img, yerel_adaylar=(), layout_boyut=None,
                    anahtar=None, model=None):
    """Sayfa rolü ve 0..1000 normalize soru kutuları döndürür; hata → None."""
    if not aktif_mi():
        return None
    anahtar = anahtar or gemini_konu.gemini_anahtar_al()
    if not anahtar:
        return None
    aday_ozeti = []
    layout_en, layout_boy = layout_boyut or img.size
    for a in yerel_adaylar:
        try:
            k = a.kutu if hasattr(a, "kutu") else a["kutu"]
            aday_ozeti.append([round(k[0] / layout_en * 1000),
                               round(k[1] / layout_boy * 1000),
                               round(k[2] / layout_en * 1000),
                               round(k[3] / layout_boy * 1000)])
        except Exception:  # noqa: BLE001
            continue
    istem = (
        "Bu sayfa bir Türkçe test/kitap sayfasıdır. Sayfanın rolünü belirle ve "
        "yalnız gerçek SORU bloklarını kutula. Konu anlatımı, çözüm, cevap "
        "anahtarı, üst/alt bilgi, örnek numaraları ve komşu soruyu kutuya alma. "
        "Açık uçlu, kısa cevap, çoktan seçmeli, doğru-yanlış ve eşleştirme "
        "sorularını tanı. Koordinatlar görüntü genişlik/yüksekliğine göre "
        "0..1000 aralığında olmalı. Yerel motorun önerileri yalnız ipucudur: "
        f"{json.dumps(aday_ozeti)}")
    istek = {"contents": [{"parts": [
        {"text": istem},
        {"inlineData": {"mimeType": "image/jpeg", "data": _png(img)}}]}],
        "generationConfig": {"responseMimeType": "application/json",
                              "responseSchema": _SEMA,
                              "maxOutputTokens": 1800}}
    for m in gemini_konu._modeller(model or gemini_konu.gemini_model_al()):
        try:
            sonuc = json.loads(gemini_konu._cagir(m, istek, anahtar, timeout=60))
            if isinstance(sonuc, dict):
                return sonuc
        except Exception:  # noqa: BLE001 — yerel yol her zaman çalışır
            continue
    return None
