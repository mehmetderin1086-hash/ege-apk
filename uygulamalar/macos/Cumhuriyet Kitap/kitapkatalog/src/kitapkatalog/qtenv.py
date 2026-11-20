"""Qt eklenti görünürlüğü savunması (macOS UF_HIDDEN).

Bu Mac'te bir arka plan süreci, nokta-dizinlerin (ör. ``.venv``) içeriğine
periyodik olarak macOS ``hidden`` bayrağı basıyor. Qt'nin QFactoryLoader'ı
gizli dosyaları listelemediği için QPA platform eklentileri "yok" görünüyor ve
QApplication SIGABRT ile çöküyor (dağıtım tarafında scripts/build_release.py
aynı nedenle .app üzerinde ``chflags -R nohidden`` çalıştırıyor). Bu modül,
QApplication kurulmadan hemen önce yalnız PySide6 eklenti ağacındaki bayrağı
temizler; bayrağı basan sürece dokunmaz.
"""

from __future__ import annotations

import os
import stat
import sys
from pathlib import Path


def clear_hidden_flags(root: Path) -> int:
    """Ağaçtaki UF_HIDDEN bayraklarını kaldır; temizlenen yol sayısını döndür."""

    if sys.platform != "darwin":
        return 0
    hidden_bit = getattr(stat, "UF_HIDDEN", 0x8000)
    cleared = 0
    for path in (root, *root.rglob("*")):
        try:
            status = os.stat(path, follow_symlinks=False)
            if status.st_flags & hidden_bit:
                os.chflags(path, status.st_flags & ~hidden_bit, follow_symlinks=False)
                cleared += 1
        except OSError:
            continue
    return cleared


def ensure_qt_plugins_visible() -> int:
    """PySide6 Qt eklenti ağacını görünür kıl; PySide6 yoksa sessizce geç."""

    if sys.platform != "darwin":
        return 0
    try:
        import PySide6
    except ImportError:
        return 0
    plugins = Path(PySide6.__file__).resolve().parent / "Qt" / "plugins"
    if not plugins.is_dir():
        return 0
    return clear_hidden_flags(plugins)
