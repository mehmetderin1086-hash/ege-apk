#!/bin/sh
set -eu
SERVER_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export PATH="$HOME/.local/bin:$HOME/.local/node-v24/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
exec python3 "$SERVER_DIR/app.py" "$@"
