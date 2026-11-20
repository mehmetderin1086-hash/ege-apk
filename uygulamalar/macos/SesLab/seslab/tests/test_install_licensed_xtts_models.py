"""Colab'dan gelen izinli XTTS paketlerinin SesLab kurulum testi."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path


def _installer_module():
    path = Path(__file__).resolve().parents[1] / "scripts" / "install_licensed_xtts_models.py"
    spec = importlib.util.spec_from_file_location("install_licensed_xtts_models_test", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _make_package(root: Path, slug: str, name: str) -> Path:
    package = root / slug
    package.mkdir(parents=True)
    (package / "model.pth").write_bytes(b"x" * 1_000_001)
    (package / "config.json").write_text("{}", encoding="utf-8")
    (package / "vocab.json").write_text("{}", encoding="utf-8")
    (package / "referans.wav").write_bytes(b"RIFF" + b"x" * 4_001)
    (package / "training_report.json").write_text(
        json.dumps({
            "slug": slug,
            "voice": name,
            "clips": 250,
            "minutes": 30.5,
            "epochs": 3,
            "model_loss": 0.42,
            "permission_note": "İzinli test paketi",
        }),
        encoding="utf-8",
    )
    return package


def test_installer_keeps_old_mazlum_and_routes_new_model(tmp_path, monkeypatch):
    installer = _installer_module()
    data_dir = tmp_path / "data"
    voices_dir = data_dir / "voices"
    monkeypatch.setattr(installer, "DATA_DIR", data_dir)
    monkeypatch.setattr(installer, "VOICES_DIR", voices_dir)

    # Kullanıcının daha önce dinlediği v1 dizini yeni v3 kurulumundan etkilenmez.
    old_model = data_dir / "models" / "xtts_mazlum_kiper_ft"
    old_model.mkdir(parents=True)
    (old_model / "model.pth").write_bytes(b"old-model")

    packages = tmp_path / "packages"
    _make_package(packages, "mazlum_kiper_v3_licensed", "Mazlum Kiper")
    result = installer.install_packages(packages)

    assert result["errors"] == []
    assert result["installed"] == [{
        "slug": "mazlum_kiper_v3_licensed",
        "name": "Mazlum Kiper",
        "voice_id": installer.voice_id_for("mazlum_kiper_v3_licensed"),
        "checkpoint_dir": "xtts_mazlum_kiper_v3_licensed",
    }]
    assert (old_model / "model.pth").read_bytes() == b"old-model"
    checkpoint = data_dir / "models" / "xtts_mazlum_kiper_v3_licensed"
    assert (checkpoint / "model.pth").stat().st_size == 1_000_001
    meta = json.loads((voices_dir / installer.voice_id_for("mazlum_kiper_v3_licensed") / "meta.json").read_text())
    assert meta["checkpoint_dir"] == "xtts_mazlum_kiper_v3_licensed"
    assert meta["training"]["minutes"] == 30.5
    assert len(result["not_ready"]) == 15
