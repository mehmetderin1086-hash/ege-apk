from __future__ import annotations

import os
import platform
import plistlib
import sys
import zipfile
from pathlib import Path

import pytest

from deployment.entry import (
    FROZEN_SIDECAR_ENVIRONMENT_VARIABLE,
    RUNTIME_SMOKE_ARGUMENT,
    VISION_SIDECAR_ARGUMENT,
    configure_runtime,
    discover_model_directory,
)
from deployment.entry import (
    main as deployment_main,
)
from scripts.build_release import (
    BuildTarget,
    ReleaseBuildError,
    _pyinstaller_command_path,
    _stamp_macos_bundle_version,
    assert_native_target,
    build_source_archive,
    render_deploy_spec,
)


def _sample_project(root: Path) -> None:
    for name in ("README.md", "LICENSE", "pyproject.toml", "uv.lock"):
        (root / name).write_text(f"{name}\n", encoding="utf-8")
    (root / "src" / "kitapkatalog").mkdir(parents=True)
    (root / "src" / "kitapkatalog" / "__init__.py").write_text(
        "__version__ = '0.1.0'\n",
        encoding="utf-8",
    )
    (root / "scripts").mkdir()
    (root / "scripts" / "run.command").write_text("#!/bin/zsh\n", encoding="utf-8")
    (root / "work").mkdir()
    (root / "work" / "private.jpg").write_bytes(b"not-in-source")
    (root / "src" / "kitapkatalog" / "__pycache__").mkdir()
    (root / "src" / "kitapkatalog" / "__pycache__" / "x.pyc").write_bytes(b"cache")


def test_source_archive_is_deterministic_and_excludes_runtime_data(tmp_path: Path) -> None:
    project = tmp_path / "project"
    project.mkdir()
    _sample_project(project)
    first = build_source_archive(project, tmp_path / "first.zip")
    second = build_source_archive(project, tmp_path / "second.zip")

    assert first.read_bytes() == second.read_bytes()
    with zipfile.ZipFile(first) as archive:
        names = archive.namelist()
        assert names == sorted(names)
        assert "KitapKatalog/src/kitapkatalog/__init__.py" in names
        assert all("work/" not in name for name in names)
        assert all("__pycache__" not in name for name in names)
        assert all(info.date_time == (2020, 1, 1, 0, 0, 0) for info in archive.infolist())


def test_source_archive_refuses_to_overwrite(tmp_path: Path) -> None:
    project = tmp_path / "project"
    project.mkdir()
    _sample_project(project)
    target = tmp_path / "release.zip"
    target.write_bytes(b"user data")

    with pytest.raises(ReleaseBuildError, match="üzerine yazılmadı"):
        build_source_archive(project, target)
    assert target.read_bytes() == b"user data"


def test_native_target_refuses_cross_platform_build() -> None:
    target = BuildTarget(
        name="impossible",
        system="definitely-not-" + platform.system().casefold(),
        machines=frozenset({"none"}),
        artifact_suffix=".bin",
    )
    with pytest.raises(ReleaseBuildError, match="yalnız kendi platformunda"):
        assert_native_target(target)


def test_pyinstaller_command_defaults_beside_active_virtualenv_python(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    executable = tmp_path / "bin" / "python"
    executable.parent.mkdir()
    executable.touch()
    pyinstaller = executable.with_name("pyinstaller")
    pyinstaller.touch()
    monkeypatch.setattr(sys, "executable", str(executable))

    assert _pyinstaller_command_path(None) == pyinstaller


def test_macos_bundle_plist_uses_pyproject_version(tmp_path: Path) -> None:
    project = tmp_path / "project"
    project.mkdir()
    (project / "pyproject.toml").write_text(
        '[project]\nname = "kitapkatalog"\nversion = "0.2.2"\n',
        encoding="utf-8",
    )
    application = tmp_path / "KitapKatalog.app"
    plist_path = application / "Contents" / "Info.plist"
    plist_path.parent.mkdir(parents=True)
    with plist_path.open("wb") as stream:
        plistlib.dump(
            {
                "CFBundleIdentifier": "local.kitapkatalog.app",
                "CFBundleShortVersionString": "0.0.0",
                "CFBundleVersion": "0",
            },
            stream,
        )

    _stamp_macos_bundle_version(application, project_root=project)

    with plist_path.open("rb") as stream:
        payload = plistlib.load(stream)
    assert payload["CFBundleShortVersionString"] == "0.2.2"
    assert payload["CFBundleVersion"] == "0.2.2"
    assert payload["CFBundleIdentifier"] == "local.kitapkatalog.app"


def test_deploy_spec_is_fully_rendered(tmp_path: Path) -> None:
    project = tmp_path / "project"
    deployment = project / "deployment"
    deployment.mkdir(parents=True)
    source_template = (
        Path(__file__).resolve().parents[1] / "deployment" / "pysidedeploy.spec.template"
    )
    (deployment / "pysidedeploy.spec.template").write_bytes(source_template.read_bytes())
    (deployment / "entry.py").write_text("pass\n", encoding="utf-8")

    rendered = render_deploy_spec(
        project_root=project,
        executable_directory=tmp_path / "release",
        python_path=tmp_path / "python3.12",
        build_packages="nuitka==4.0,ordered_set==4.1.0,zstandard==0.23.0",
    )

    assert "@" not in rendered
    assert "mode = standalone" in rendered
    assert "--include-package=kitapkatalog" in rendered
    assert "--include-package=rapidocr" in rendered
    assert "--include-package=easyocr" in rendered
    assert "--include-package=torch" not in rendered
    assert "--include-package=torchvision" not in rendered
    assert "--enable-plugins=anti-bloat" in rendered
    assert "--nofollow-import-to=torch." not in rendered
    assert "--include-module=zxingcpp" in rendered
    assert "--include-package=pillow_heif" in rendered
    assert "--include-package=pypdfium2" in rendered
    assert "--include-package-data=rapidocr" in rendered
    assert "--include-package-data=easyocr" in rendered
    assert "--include-distribution-metadata=easyocr" in rendered
    assert "--include-distribution-metadata=pillow_heif" in rendered
    assert "--include-distribution-metadata=pypdfium2" in rendered
    assert str((deployment / "entry.py").resolve()) in rendered


def test_entry_discovers_adjacent_locked_model_bundle(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    executable = tmp_path / "KitapKatalog.app" / "Contents" / "MacOS" / "KitapKatalog"
    executable.parent.mkdir(parents=True)
    executable.touch()
    models = tmp_path / "KitapKatalog-models"
    models.mkdir()
    (models / "model_manifest.lock.json").write_text("{}\n", encoding="utf-8")
    monkeypatch.delenv("KITAPKATALOG_MODEL_DIR", raising=False)

    assert discover_model_directory(executable=executable) == models


def test_entry_discovers_models_embedded_in_macos_application(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    executable = tmp_path / "KitapKatalog.app" / "Contents" / "MacOS" / "KitapKatalog"
    executable.parent.mkdir(parents=True)
    executable.touch()
    models = tmp_path / "KitapKatalog.app" / "Contents" / "Resources" / "KitapKatalog-models"
    models.mkdir(parents=True)
    (models / "model_manifest.lock.json").write_text("{}\n", encoding="utf-8")
    monkeypatch.delenv("KITAPKATALOG_MODEL_DIR", raising=False)

    assert discover_model_directory(executable=executable) == models


def test_entry_without_bundle_can_reach_readiness_ui(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from kitapkatalog.offline import _uninstall_for_tests

    models = tmp_path / "missing-models"
    monkeypatch.setenv("KITAPKATALOG_MODEL_DIR", str(models))
    _uninstall_for_tests()
    try:
        assert configure_runtime() == models
    finally:
        _uninstall_for_tests()


def test_frozen_entry_dispatches_vision_sidecar_without_starting_gui(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[str] = []
    monkeypatch.setattr(sys, "argv", ["KitapKatalog", VISION_SIDECAR_ARGUMENT])
    monkeypatch.setattr(
        "deployment.entry._run_vision_sidecar",
        lambda: calls.append("sidecar") or 23,
    )

    assert deployment_main() == 23
    assert calls == ["sidecar"]


def test_frozen_entry_dispatches_runtime_smoke_without_starting_gui(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[str] = []
    monkeypatch.setattr(sys, "argv", ["KitapKatalog", RUNTIME_SMOKE_ARGUMENT])
    monkeypatch.setattr(
        "deployment.entry._run_runtime_smoke",
        lambda: calls.append("smoke") or 29,
    )

    assert deployment_main() == 29
    assert calls == ["smoke"]


def test_frozen_runtime_registers_executable_for_child_sidecar(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from kitapkatalog.offline import _uninstall_for_tests

    models = tmp_path / "missing-models"
    executable = tmp_path / "KitapKatalog"
    executable.touch()
    monkeypatch.setenv("KITAPKATALOG_MODEL_DIR", str(models))
    monkeypatch.delenv(FROZEN_SIDECAR_ENVIRONMENT_VARIABLE, raising=False)
    monkeypatch.setattr(sys, "executable", str(executable))
    monkeypatch.setattr("deployment.entry._running_as_frozen_application", lambda: True)
    _uninstall_for_tests()
    try:
        configure_runtime()
        assert os.environ[FROZEN_SIDECAR_ENVIRONMENT_VARIABLE] == str(executable.resolve())
    finally:
        _uninstall_for_tests()
