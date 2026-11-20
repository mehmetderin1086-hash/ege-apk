"""The lightweight macOS launcher is staged and rollback-safe."""

from __future__ import annotations

import plistlib
import stat
import subprocess
from pathlib import Path

import pytest

from scripts import build_launcher_app

APP_NAME = build_launcher_app.APP_NAME


def _existing_launcher(path: Path, marker: str) -> None:
    binary = path / "Contents" / "MacOS" / APP_NAME
    binary.parent.mkdir(parents=True)
    binary.write_text(f"#!/bin/zsh\n# {marker}\n")
    plist = path / "Contents" / "Info.plist"
    with plist.open("wb") as handle:
        plistlib.dump({"CFBundleShortVersionString": marker}, handle)


def _redirect(monkeypatch: pytest.MonkeyPatch, root: Path) -> Path:
    application = root / f"{APP_NAME}.app"
    monkeypatch.setattr(build_launcher_app, "APPLICATIONS", root)
    monkeypatch.setattr(build_launcher_app, "APP_PATH", application)
    monkeypatch.setattr(build_launcher_app, "OLD_QT_APP", root / f"{APP_NAME}-qt-eski.app")
    return application


def test_launcher_is_built_off_to_the_side_then_swapped(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    application = _redirect(monkeypatch, tmp_path / "Applications")
    _existing_launcher(application, "old")
    monkeypatch.setattr(build_launcher_app.subprocess, "run", lambda *_args, **_kwargs: None)

    assert build_launcher_app.build() == 0

    binary = application / "Contents" / "MacOS" / APP_NAME
    assert binary.stat().st_mode & stat.S_IXUSR
    with (application / "Contents" / "Info.plist").open("rb") as handle:
        assert plistlib.load(handle)["CFBundleShortVersionString"] == build_launcher_app._version()
    assert not list(application.parent.glob(f".{APP_NAME}-build-*"))
    assert not list(application.parent.glob(f".{APP_NAME}.rollback-*"))


def test_failed_post_swap_verification_restores_previous_launcher(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    application = _redirect(monkeypatch, tmp_path / "Applications")
    _existing_launcher(application, "old-marker")
    calls = 0

    def codesign(*_args, **_kwargs) -> None:
        nonlocal calls
        calls += 1
        if calls == 3:
            raise subprocess.CalledProcessError(1, "codesign")

    monkeypatch.setattr(build_launcher_app.subprocess, "run", codesign)

    with pytest.raises(subprocess.CalledProcessError):
        build_launcher_app.build()

    assert "old-marker" in (
        application / "Contents" / "MacOS" / APP_NAME
    ).read_text()
    assert not list(application.parent.glob(f".{APP_NAME}-build-*"))
    assert not list(application.parent.glob(f".{APP_NAME}.rollback-*"))


def test_failed_first_install_does_not_leave_invalid_live_bundle(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    application = _redirect(monkeypatch, tmp_path / "Applications")
    calls = 0

    def codesign(*_args, **_kwargs) -> None:
        nonlocal calls
        calls += 1
        if calls == 3:
            raise subprocess.CalledProcessError(1, "codesign")

    monkeypatch.setattr(build_launcher_app.subprocess, "run", codesign)

    with pytest.raises(subprocess.CalledProcessError):
        build_launcher_app.build()

    assert not application.exists()
    assert not list(application.parent.glob(f".{APP_NAME}-build-*"))
    assert not list(application.parent.glob(f".{APP_NAME}.rollback-*"))
