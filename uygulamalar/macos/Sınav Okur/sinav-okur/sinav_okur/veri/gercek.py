"""Gerçek Türkçe el yazısı veri setlerini eğitim formatına (labels.jsonl) çevirme.

HuggingFace `datasets` üzerinden indirilen setler, sentetik veriyle AYNI formata
(`img/*.png` + `labels.jsonl`) dönüştürülür; böylece Colab eğitim defterleri
sentetik ve gerçek veriyi tek bir dizinden harmanlayabilir.

Kolon isimleri setten sete değiştiği için görüntü/metin kolonları otomatik
tespit edilir. Bilinen Türkçe setler ``ON_AYARLAR`` sözlüğünde tanımlıdır;
veri-avı araştırması yeni set doğruladıkça buraya eklenir.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from ..metin import nfc

# Görüntü/metin kolonu otomatik tespiti için aday isimler (öncelik sırası)
_GORUNTU_ANAHTARLARI = ["image", "img", "images", "picture", "pixel_values"]
_METIN_ANAHTARLARI = [
    "text", "label", "labels", "sentence", "transcription",
    "ground_truth", "caption", "word", "annotation",
]


@dataclass
class VeriSetiOnAyar:
    repo_id: str
    split: str = "train"
    goruntu_anahtari: str | None = None  # None → otomatik tespit
    metin_anahtari: str | None = None
    tip: str = "satir"  # karakter | kelime | satir | sayfa
    lisans: str = "?"
    gercek_el_yazisi: bool = False
    egitim_izni: bool = False
    not_: str = ""


# Veri-avı workflow'unda (17 ajan) ERİŞİLEBİLİRLİĞİ DOĞRULANMIŞ HuggingFace setleri.
# NOT: T-H-E (gerçek Türkçe el yazısı KARAKTER verisi) HuggingFace'te YOKTUR
# (bartosgaye/thedataset 401 verir); GitHub'dan git-lfs ile CSV olarak gelir ve
# karakter→satır köprüsüyle işlenir → bkz. the_karakter.py.
ON_AYARLAR: dict[str, VeriSetiOnAyar] = {
    # Yalnız EVAL/sağlama için — GERÇEK değil (render + ~%30 basılı). Eğitime KATMAYIN;
    # kendi sentetik hattınız (sentetik.veri_uret) bu amaca daha uygundur.
    "turkish-ocr": VeriSetiOnAyar(
        repo_id="emredeveloper/turkish-ocr", split="train", tip="kelime",
        lisans="MIT",
        gercek_el_yazisi=False,
        egitim_izni=False,
        not_="SENTETİK/render (gerçek el yazısı DEĞİL); yalnız bağımsız eval seti olarak.",
    ),
}


def _anahtar_bul(kolonlar, adaylar, elle):
    if elle:
        return elle
    for a in adaylar:
        if a in kolonlar:
            return a
    return None


def hf_labels_uret(
    onayar: VeriSetiOnAyar | str,
    cikti_dizini: str | Path,
    azami: int | None = None,
    onek: str = "",
    amac: str = "eval",
) -> dict:
    """Bir HF veri setini indirip `img/` + `labels.jsonl` olarak yazar.

    ``onayar`` bir VeriSetiOnAyar veya ON_AYARLAR anahtarı (ör. "the") olabilir.
    Döner: {"repo": ..., "yazilan": n, "atlanan": m, "labels": <yol>}.
    """
    try:
        from datasets import load_dataset
    except ImportError as e:
        raise ImportError(
            "Gerçek veri için 'datasets' gerekli: uv sync --extra hfveri"
        ) from e

    if isinstance(onayar, str):
        if onayar not in ON_AYARLAR:
            raise KeyError(f"Bilinmeyen ön-ayar: {onayar}. Seçenekler: {list(ON_AYARLAR)}")
        onayar = ON_AYARLAR[onayar]
    if amac not in {"eval", "egitim"}:
        raise ValueError("amac yalnız 'eval' veya 'egitim' olabilir")
    if amac == "egitim" and not (onayar.gercek_el_yazisi and onayar.egitim_izni):
        raise PermissionError(
            f"{onayar.repo_id}: gerçek el yazısı ve açık eğitim izni doğrulanmadı; "
            "eğitim indirmesi engellendi. Kaynağı yalnız eval amacıyla inceleyin."
        )

    cikti = Path(cikti_dizini)
    (cikti / "img").mkdir(parents=True, exist_ok=True)
    ds = load_dataset(onayar.repo_id, split=onayar.split)

    kolonlar = set(ds.column_names)
    g_key = _anahtar_bul(kolonlar, _GORUNTU_ANAHTARLARI, onayar.goruntu_anahtari)
    t_key = _anahtar_bul(kolonlar, _METIN_ANAHTARLARI, onayar.metin_anahtari)
    if g_key is None or t_key is None:
        raise ValueError(
            f"{onayar.repo_id}: görüntü/metin kolonu tespit edilemedi. "
            f"Mevcut kolonlar: {sorted(kolonlar)}. Ön-ayarda anahtarları elle verin."
        )

    label_yolu = cikti / "labels.jsonl"
    yazilan, atlanan = 0, 0
    kip = "a" if label_yolu.exists() and onek else "w"
    with open(label_yolu, kip, encoding="utf-8") as f:
        for i, ornek in enumerate(ds):
            if azami is not None and yazilan >= azami:
                break
            metin = ornek.get(t_key)
            gorsel = ornek.get(g_key)
            if not metin or gorsel is None:
                atlanan += 1
                continue
            try:
                gorsel = gorsel.convert("RGB") if hasattr(gorsel, "convert") else gorsel
                dosya = f"img/{onek}gercek_{i:06d}.png"
                gorsel.save(cikti / dosya)
            except Exception:
                atlanan += 1
                continue
            f.write(json.dumps(
                {"image": dosya, "text": nfc(str(metin).strip())}, ensure_ascii=False) + "\n")
            yazilan += 1

    return {
        "repo": onayar.repo_id,
        "yazilan": yazilan,
        "atlanan": atlanan,
        "labels": str(label_yolu),
        "tip": onayar.tip,
        "lisans": onayar.lisans,
        "amac": amac,
    }
