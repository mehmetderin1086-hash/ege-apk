#!/bin/sh
# Uses installed package managers; the standalone FFprobe fallback is SHA256-verified.
set -eu
SERVER_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export PATH="$HOME/.local/bin:$HOME/.local/node-v24/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v python3 >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        brew install python
    else
        echo 'Python 3.9+ gerekiyor. Python veya Homebrew kurup bu komutu tekrar çalıştırın.' >&2
        exit 1
    fi
fi
if ! command -v yt-dlp >/dev/null 2>&1; then
    if command -v uv >/dev/null 2>&1; then
        uv tool install --python 3.13 'yt-dlp[default]'
    elif command -v brew >/dev/null 2>&1; then
        brew install yt-dlp
    else
        echo 'yt-dlp gerekiyor. Önce uv veya Homebrew kurun.' >&2
        exit 1
    fi
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        brew install ffmpeg
    else
        echo 'FFmpeg gerekiyor. Homebrew kurup tekrar çalıştırın veya RITIM_FFMPEG yolunu yapılandırın.' >&2
        exit 1
    fi
fi
if ! command -v ffprobe >/dev/null 2>&1 && [ ! -x "$SERVER_DIR/.runtime/tools/ffprobe" ] && [ ! -x "${RITIM_FFPROBE:-}" ]; then
    if [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ]; then
        python3 "$SERVER_DIR/install-ffprobe.py"
    elif command -v brew >/dev/null 2>&1; then
        brew install ffmpeg
    else
        echo 'En yüksek kalite için FFprobe gerekiyor. FFmpeg paketini kurun veya RITIM_FFPROBE yolunu ayarlayın.' >&2
        exit 1
    fi
fi
if ! command -v node >/dev/null 2>&1 && ! command -v deno >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        brew install node
    else
        echo 'YouTube JavaScript desteği için Node.js 22+ veya Deno 2.3+ gerekiyor.' >&2
        exit 1
    fi
fi
python3 -c 'import sys; assert sys.version_info >= (3,9), "Python 3.9+ gerekiyor"'
python3 - <<'PY'
import re, shutil, subprocess
supported = False
for executable, minimum in [('node', (22, 0)), ('deno', (2, 3))]:
    path = shutil.which(executable)
    if path:
        result = subprocess.run([path, '--version'], capture_output=True, text=True, timeout=10)
        match = re.search(r'(\d+)\.(\d+)', result.stdout)
        supported |= bool(match and tuple(map(int, match.groups())) >= minimum)
if not supported:
    raise SystemExit('YouTube için Node.js 22+ veya Deno 2.3+ sürümüne güncelleyin.')
PY
yt-dlp --version
ffmpeg -version | head -n 1
cd "$SERVER_DIR"
python3 -m unittest discover -s tests -v
printf '%s\n' 'Kurulum doğrulandı. Başlatma: ./server/start.sh --host 0.0.0.0'
