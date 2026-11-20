#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
EXTENSION_DIR="${PROJECT_ROOT}/extension"
MANIFEST="${EXTENSION_DIR}/manifest.json"

if [[ ! -f "${MANIFEST}" ]]; then
  print -u2 "HATA: Chromium eklenti manifesti bulunamadı: ${MANIFEST}"
  exit 2
fi

PYTHON_BIN="${PROJECT_ROOT}/.venv/bin/python"
if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="$(command -v python3 || true)"
fi
if [[ -z "${PYTHON_BIN}" ]]; then
  print -u2 "HATA: manifest doğrulaması için Python bulunamadı."
  exit 2
fi

VERSION="$("${PYTHON_BIN}" - "${MANIFEST}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding="utf-8"))
if manifest.get("manifest_version") != 3:
    raise SystemExit("HATA: Yalnız Manifest V3 paketlenebilir.")
allowed = {"activeTab", "scripting", "contextMenus", "storage"}
permissions = set(manifest.get("permissions", []))
unexpected = sorted(permissions - allowed)
if unexpected:
    raise SystemExit(f"HATA: Beklenmeyen eklenti izni: {', '.join(unexpected)}")
hosts = set(manifest.get("host_permissions", []))
expected_hosts = {"http://127.0.0.1:8765/*"}
if hosts != expected_hosts:
    raise SystemExit("HATA: host_permissions yalnız http://127.0.0.1:8765/* olmalı.")
serialized = json.dumps(manifest)
if "<all_urls>" in serialized or "webRequest" in serialized:
    raise SystemExit("HATA: geniş trafik izleme izinleri ilk sürümde yasak.")
version = manifest.get("version")
if not isinstance(version, str) or not version:
    raise SystemExit("HATA: Eklenti sürümü eksik.")
print(version)
PY
)"

if find "${EXTENSION_DIR}" -type f \( \
  -name '.env' -o -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name '*.crx' \
\) | grep -q .; then
  print -u2 "HATA: Eklenti klasöründe paketlenmemesi gereken anahtar/gizli dosya bulundu."
  exit 2
fi

mkdir -p "${PROJECT_ROOT}/dist"
OUTPUT="${PROJECT_ROOT}/dist/downloadhub-extension-${VERSION}.zip"
if [[ -e "${OUTPUT}" ]]; then
  print -u2 "HATA: Mevcut eklenti paketi üzerine yazılmayacak: ${OUTPUT}"
  exit 2
fi

cd "${EXTENSION_DIR}"
/usr/bin/zip -X -r "${OUTPUT}" . \
  -x '*.DS_Store' '*.map' '.git/*' 'node_modules/*'
/usr/bin/unzip -t "${OUTPUT}" >/dev/null
print "Hazır: ${OUTPUT}"
