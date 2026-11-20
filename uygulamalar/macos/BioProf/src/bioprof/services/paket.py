"""Öğrenci paketi: seçilen artifact'ları MANIFEST'li tek zip'te toplar.

Her dosya yolu artifacts_dir köküne `resolve().is_relative_to` kapısından
geçer: bozuk ya da kötü niyetli metadata, kökün dışındaki bir dosyayı pakete
sızdıramaz.
"""

from __future__ import annotations

import re
import zipfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

_GUVENLI_AD = re.compile(r"[^\w\sçğıöşüÇĞİÖŞÜ.-]", re.UNICODE)


def _dosya_adi(value: str, varsayilan: str) -> str:
    temiz = _GUVENLI_AD.sub("", value).strip().replace(" ", "-")[:60]
    return temiz or varsayilan


def paket_olustur(
    artifacts: list[dict[str, Any]],
    *,
    artifacts_dir: Path,
    hedef_dizin: Path,
    baslik: str = "ogrenci-paketi",
) -> Path:
    """Zip'i exports dizinine yazar ve yolunu döndürür."""
    kok = artifacts_dir.resolve()
    hedef_dizin.mkdir(parents=True, exist_ok=True)
    zaman = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    zip_yolu = hedef_dizin / f"{_dosya_adi(baslik, 'paket')}-{zaman}.zip"
    manifest: list[str] = [
        "# Öğrenci Paketi",
        "",
        f"Oluşturulma: {datetime.now(UTC).isoformat(timespec='seconds')}",
        "",
    ]
    with zipfile.ZipFile(zip_yolu, "w", compression=zipfile.ZIP_DEFLATED) as arsiv:
        for artifact in artifacts:
            meta = artifact.get("metadata") or {}
            adaylar = [
                *(str(dosya) for dosya in (meta.get("files") or [])),
            ]
            # Liste boşsa birincil dosya (path) tek adaydır; export tabanlı
            # artifact'larda "files" hiç olmaz.
            if not adaylar and artifact.get("path"):
                adaylar = [str(artifact["path"])]
            klasor = _dosya_adi(
                str(artifact.get("title") or artifact.get("kind") or "cikti"), "cikti"
            )
            eklenen = 0
            for aday in adaylar:
                yol = Path(aday).expanduser()
                try:
                    cozulmus = yol.resolve()
                except OSError:
                    continue
                if not cozulmus.is_file():
                    continue
                if cozulmus == kok or kok not in cozulmus.parents:
                    continue
                arsiv.write(cozulmus, arcname=f"{klasor}/{cozulmus.name}")
                eklenen += 1
            manifest.append(
                f"- **{artifact.get('title') or artifact.get('kind')}** "
                f"({artifact.get('kind')}, {artifact.get('created_at', '')[:10]}) — "
                f"{eklenen} dosya"
            )
        arsiv.writestr("MANIFEST.md", "\n".join(manifest))
    zip_yolu.chmod(0o600)
    return zip_yolu
