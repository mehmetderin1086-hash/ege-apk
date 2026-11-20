#!/usr/bin/env python3
"""İzinli Colab XTTS paketlerini SesLab'a güvenli biçimde kur.

Colab'ın ``MyDrive/SesLab/licensed-voices/packages`` klasörü indirildikten
sonra çalıştırılır. Paketler konuşmacı başına ayrı dizindir; bu yükleyici
hiçbir paketi birleştirmez ve mevcut Mazlum v1 dizinine dokunmaz.

Örnek:
    uv run python scripts/install_licensed_xtts_models.py \
      /path/to/licensed-voices/packages
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
import time
from pathlib import Path

from app.config import DATA_DIR, VOICES_DIR


# Yükleme kapsamı, kullanıcının 2026-08-06'da eğitim ve SesLab kullanımı için
# izin verdiğini beyan ettiği açık listedir. Başka klasör adları yok sayılır.
VOICE_SPECS = (
    ("mazlum_kiper_v3_licensed", "Mazlum Kiper"),
    ("nisan_kumru", "Nisan Kumru"),
    ("akin_altan", "Akın Altan"),
    ("hayri_kucukdeniz", "Hayri Küçükdeniz"),
    ("koksal_engur", "Köksal Engür"),
    ("mudrike_cosansu", "Müdrike Coşansu"),
    ("sezai_aydin", "Sezai Aydın"),
    ("kursat_annac", "Kürşat Annaç"),
    ("rustu_asyali", "Rüştü Asyalı"),
    ("mehmet_atay", "Mehmet Atay"),
    ("musfik_kenter", "Müşfik Kenter"),
    ("ozden_ayyildiz", "Özden Ayyıldız"),
    ("umut_tabak", "Umut Tabak"),
    ("istemi_betil", "İstemi Betil"),
    ("omer_karaaslan", "Ömer Karaaslan"),
    ("caner_ozyazar", "Caner Özyazar"),
)
REQUIRED_FILES = ("model.pth", "config.json", "vocab.json", "referans.wav", "training_report.json")


def voice_id_for(slug: str) -> str:
    """Kararlı, SesLab'ın 12 onaltılık karakter kuralına uygun ses kimliği."""
    return hashlib.sha256(f"SesLab licensed voice:{slug}".encode()).hexdigest()[:12]


def _read_report(package_dir: Path, slug: str, name: str) -> dict:
    missing = [filename for filename in REQUIRED_FILES if not (package_dir / filename).is_file()]
    if missing:
        raise ValueError(f"{slug}: eksik paket dosyası: {', '.join(missing)}")
    if (package_dir / "model.pth").stat().st_size < 1_000_000:
        raise ValueError(f"{slug}: model.pth geçersiz derecede küçük")
    if (package_dir / "referans.wav").stat().st_size < 4_000:
        raise ValueError(f"{slug}: referans WAV geçersiz derecede küçük")
    try:
        report = json.loads((package_dir / "training_report.json").read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError(f"{slug}: training_report.json okunamadı") from error
    if report.get("slug") != slug or report.get("voice") != name:
        raise ValueError(f"{slug}: paket kimliği beklenen izinli kişiyle eşleşmiyor")
    return report


def _replace_directory(staged: Path, target: Path) -> None:
    """Başarısızlıkta önceki dizini geri getiren atomik dizin değişimi."""
    backup = target.with_name(f".{target.name}.backup")
    if backup.exists():
        shutil.rmtree(backup)
    had_target = target.exists()
    if had_target:
        target.rename(backup)
    try:
        staged.rename(target)
    except Exception:
        if had_target and backup.exists() and not target.exists():
            backup.rename(target)
        raise
    else:
        if backup.exists():
            shutil.rmtree(backup)


def install_packages(source_root: Path, *, dry_run: bool = False) -> dict:
    """Mevcut, doğrulanmış paketleri ayrı SesLab sesleri olarak kurar."""
    source_root = source_root.expanduser().resolve()
    if not source_root.is_dir():
        raise ValueError(f"Paket klasörü bulunamadı: {source_root}")

    models_dir = DATA_DIR / "models"
    models_dir.mkdir(parents=True, exist_ok=True)
    VOICES_DIR.mkdir(parents=True, exist_ok=True)
    result = {"installed": [], "not_ready": [], "errors": []}

    for slug, name in VOICE_SPECS:
        package_dir = source_root / slug
        if not package_dir.is_dir():
            result["not_ready"].append({"slug": slug, "name": name})
            continue
        try:
            report = _read_report(package_dir, slug, name)
            if dry_run:
                result["installed"].append({"slug": slug, "name": name, "dry_run": True})
                continue

            model_name = f"xtts_{slug}"
            model_target = models_dir / model_name
            voice_id = voice_id_for(slug)
            voice_target = VOICES_DIR / voice_id
            with tempfile.TemporaryDirectory(prefix=f".{slug}.", dir=models_dir) as temp_name:
                stage_model = Path(temp_name) / model_name
                stage_model.mkdir()
                for filename in REQUIRED_FILES:
                    shutil.copy2(package_dir / filename, stage_model / filename)

                stage_voice = Path(tempfile.mkdtemp(prefix=f".{voice_id}.", dir=VOICES_DIR))
                try:
                    shutil.copy2(package_dir / "referans.wav", stage_voice / "ref.wav")
                    existing_created_at = time.time()
                    if (voice_target / "meta.json").is_file():
                        try:
                            existing_created_at = json.loads(
                                (voice_target / "meta.json").read_text(encoding="utf-8")
                            ).get("created_at", existing_created_at)
                        except json.JSONDecodeError:
                            pass
                    metadata = {
                        "id": voice_id,
                        "name": name,
                        "created_at": existing_created_at,
                        "checkpoint_dir": model_name,
                        "training": {
                            "clips": report.get("clips"),
                            "minutes": report.get("minutes"),
                            "epochs": report.get("epochs"),
                            "model_loss": report.get("model_loss"),
                        },
                        "permission_note": report.get("permission_note"),
                    }
                    (stage_voice / "meta.json").write_text(
                        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
                    )
                    _replace_directory(stage_model, model_target)
                    _replace_directory(stage_voice, voice_target)
                except Exception:
                    if stage_voice.exists():
                        shutil.rmtree(stage_voice)
                    raise
            result["installed"].append({
                "slug": slug,
                "name": name,
                "voice_id": voice_id,
                "checkpoint_dir": model_name,
            })
        except (OSError, ValueError) as error:
            result["errors"].append({"slug": slug, "name": name, "error": str(error)})
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("packages", type=Path, help="Colab packages klasörü")
    parser.add_argument("--dry-run", action="store_true", help="Doğrula, SesLab verisini değiştirme")
    args = parser.parse_args()
    result = install_packages(args.packages, dry_run=args.dry_run)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if result["errors"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
