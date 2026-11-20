from __future__ import annotations

import os
import stat
import sys
from pathlib import Path

import pytest

from kitapkatalog.qtenv import clear_hidden_flags, ensure_qt_plugins_visible


@pytest.mark.skipif(sys.platform != "darwin", reason="UF_HIDDEN yalnız macOS")
def test_clear_hidden_flags_removes_flag_recursively(tmp_path: Path) -> None:
    nested = tmp_path / "plugins" / "platforms"
    nested.mkdir(parents=True)
    target = nested / "libqoffscreen.dylib"
    target.write_bytes(b"sahte")
    os.chflags(target, stat.UF_HIDDEN)
    os.chflags(nested, stat.UF_HIDDEN)
    assert os.stat(target).st_flags & stat.UF_HIDDEN

    cleared = clear_hidden_flags(tmp_path)

    assert cleared == 2
    assert not os.stat(target).st_flags & stat.UF_HIDDEN
    assert not os.stat(nested).st_flags & stat.UF_HIDDEN
    assert clear_hidden_flags(tmp_path) == 0


def test_ensure_qt_plugins_visible_is_safe_to_call() -> None:
    # PySide6 kuruluysa gerçek eklenti ağacını temizler, değilse 0 döner;
    # her iki durumda da istisna fırlatmamalı.
    assert ensure_qt_plugins_visible() >= 0
