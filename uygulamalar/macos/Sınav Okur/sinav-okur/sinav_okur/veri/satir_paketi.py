"""İzinli gerçek el yazısı satır paketlerini güvenli eğitim biçimine aktarır."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
from collections import Counter, defaultdict
from pathlib import Path

from ..metin import nfc

_BOLMELER = {"train", "validation", "test"}
_YAZAR_KODU = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")
_GORUNTU_UZANTILARI = {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".webp"}
_TURKCE_OZEL = "ÇĞİÖŞÜçğıöşü"


def _sha256(yol: Path) -> str:
    ozet = hashlib.sha256()
    with yol.open("rb") as f:
        for parca in iter(lambda: f.read(1024 * 1024), b""):
            ozet.update(parca)
    return ozet.hexdigest()


def _kaynak_gorsel(base: Path, deger: object) -> Path:
    if not isinstance(deger, str) or not deger.strip():
        raise ValueError("image boş veya metin değil")
    aday = Path(deger)
    yol = aday.resolve() if aday.is_absolute() else (base / aday).resolve()
    try:
        yol.relative_to(base.resolve())
    except ValueError as e:
        raise ValueError(f"Görüntü paket dizini dışında: {deger}") from e
    if not yol.is_file():
        raise ValueError(f"Görüntü bulunamadı: {deger}")
    if yol.suffix.lower() not in _GORUNTU_UZANTILARI:
        raise ValueError(f"Desteklenmeyen görüntü uzantısı: {yol.suffix}")
    return yol


def _kayitlari_oku(labels: Path) -> list[dict]:
    kayitlar: list[dict] = []
    for no, ham in enumerate(labels.read_text(encoding="utf-8").splitlines(), 1):
        if not ham.strip():
            continue
        try:
            kayit = json.loads(ham)
        except json.JSONDecodeError as e:
            raise ValueError(f"labels.jsonl satır {no}: geçersiz JSON") from e
        eksik = {"image", "text", "writer_id"} - set(kayit)
        if eksik:
            raise ValueError(f"labels.jsonl satır {no}: eksik alanlar {sorted(eksik)}")
        metin = nfc(str(kayit["text"]).strip())
        yazar = str(kayit["writer_id"]).strip()
        if not metin:
            raise ValueError(f"labels.jsonl satır {no}: boş transkripsiyon")
        if not _YAZAR_KODU.fullmatch(yazar) or "@" in yazar:
            raise ValueError(
                f"labels.jsonl satır {no}: writer_id anonim sabit kod olmalı; "
                "ad, e-posta veya öğrenci numarası kullanmayın"
            )
        bolme = str(kayit.get("split", "")).strip().lower()
        if bolme and bolme not in _BOLMELER:
            raise ValueError(f"labels.jsonl satır {no}: geçersiz split={bolme!r}")
        kayitlar.append({
            "image": kayit["image"],
            "text": metin,
            "writer_id": yazar,
            **({"split": bolme} if bolme else {}),
        })
    if not kayitlar:
        raise ValueError("Paket hiç kayıt içermiyor")
    return kayitlar


def _bolmeleri_dogrula(kayitlar: list[dict]) -> dict[str, list[str]]:
    bolmeli = ["split" in k for k in kayitlar]
    if any(bolmeli) and not all(bolmeli):
        raise ValueError("split alanı ya bütün kayıtlarda bulunmalı ya da hiç bulunmamalı")
    if not any(bolmeli):
        return {}
    yazar_bolmeleri: dict[str, set[str]] = defaultdict(set)
    for k in kayitlar:
        yazar_bolmeleri[k["writer_id"]].add(k["split"])
    sizan = {y: sorted(b) for y, b in yazar_bolmeleri.items() if len(b) > 1}
    if sizan:
        raise ValueError(f"Yazar sızıntısı: aynı writer_id birden çok split'te: {sizan}")
    return {
        bolme: sorted({k["writer_id"] for k in kayitlar if k["split"] == bolme})
        for bolme in sorted({k["split"] for k in kayitlar})
    }


def satir_paketi_aktar(
    labels: str | Path,
    cikti_dizini: str | Path,
    *,
    lisans: str,
    izin_belgesi: str | Path,
    kaynak_url: str,
) -> dict:
    """Gerçek satır paketini doğrular, kopyalar ve denetlenebilir manifest üretir.

    Girdi JSONL alanları: ``image``, ``text``, ``writer_id`` ve isteğe bağlı
    ``split``. Split verilmişse aynı yazarın iki bölmede bulunması kesin hatadır.
    İzin belgesi pakete kopyalanmaz; yalnız yolu ve SHA-256 özeti manifestte tutulur.
    """
    labels = Path(labels).resolve()
    izin = Path(izin_belgesi).resolve()
    if not labels.is_file():
        raise FileNotFoundError(labels)
    if not izin.is_file():
        raise FileNotFoundError(izin)
    if not lisans.strip() or not kaynak_url.strip():
        raise ValueError("lisans ve kaynak_url zorunludur")

    kayitlar = _kayitlari_oku(labels)
    bolmeler = _bolmeleri_dogrula(kayitlar)
    yazarlar = sorted({k["writer_id"] for k in kayitlar})
    if len(yazarlar) < 5:
        raise ValueError("Yazar-ayrık değerlendirme için en az 5 anonim yazar gerekli")

    cikti = Path(cikti_dizini)
    img_cikti = cikti / "img"
    img_cikti.mkdir(parents=True, exist_ok=True)
    yeni_kayitlar: list[dict] = []
    goruntu_hashleri: dict[str, str] = {}
    for i, kayit in enumerate(kayitlar):
        kaynak = _kaynak_gorsel(labels.parent, kayit["image"])
        ad = f"satir_{i:06d}{kaynak.suffix.lower()}"
        hedef = img_cikti / ad
        shutil.copy2(kaynak, hedef)
        goreli = f"img/{ad}"
        goruntu_hashleri[goreli] = _sha256(hedef)
        yeni_kayitlar.append({
            "image": goreli,
            "text": kayit["text"],
            "writer_id": kayit["writer_id"],
            **({"split": kayit["split"]} if "split" in kayit else {}),
        })

    labels_cikti = cikti / "labels.jsonl"
    labels_cikti.write_text(
        "".join(json.dumps(k, ensure_ascii=False) + "\n" for k in yeni_kayitlar),
        encoding="utf-8",
    )
    karakterler = Counter("".join(k["text"] for k in yeni_kayitlar))
    manifest = {
        "schema_version": 1,
        "kind": "real_handwritten_line_dataset",
        "source_url": kaynak_url,
        "license": lisans,
        "permission_evidence": {
            "path": str(izin),
            "sha256": _sha256(izin),
        },
        "labels_sha256": _sha256(labels_cikti),
        "line_count": len(yeni_kayitlar),
        "writer_count": len(yazarlar),
        "writer_disjoint_splits_verified": bool(bolmeler),
        "splits": {
            b: {
                "lines": sum(k.get("split") == b for k in yeni_kayitlar),
                "writers": len(ws),
            }
            for b, ws in bolmeler.items()
        },
        "turkish_special_character_counts": {
            c: karakterler[c] for c in _TURKCE_OZEL
        },
        "image_sha256": goruntu_hashleri,
    }
    manifest_yolu = cikti / "manifest.json"
    manifest_yolu.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return {
        "labels": str(labels_cikti),
        "manifest": str(manifest_yolu),
        "satir": len(yeni_kayitlar),
        "yazar": len(yazarlar),
        "bolmeler_dogrulandi": bool(bolmeler),
    }
