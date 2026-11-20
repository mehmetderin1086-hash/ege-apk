# Third-party notices

DownloadHub is licensed under GNU GPL version 3 only. It depends on and may be
distributed alongside third-party software whose copyright remains with its
respective authors. The entries below are informational; the license files shipped
with the exact dependency versions and runtime binaries are authoritative.

## Python application dependencies

| Component | Project | License |
|---|---|---|
| FastAPI | <https://github.com/fastapi/fastapi> | MIT |
| Starlette | <https://github.com/Kludex/starlette> | BSD-3-Clause |
| Uvicorn | <https://github.com/encode/uvicorn> | BSD-3-Clause |
| SQLAlchemy | <https://github.com/sqlalchemy/sqlalchemy> | MIT |
| Alembic | <https://github.com/sqlalchemy/alembic> | MIT |
| aiosqlite | <https://github.com/omnilib/aiosqlite> | MIT |
| Pydantic and pydantic-settings | <https://github.com/pydantic/pydantic> | MIT |
| Jinja | <https://github.com/pallets/jinja> | BSD-3-Clause |
| HTTPX | <https://github.com/encode/httpx> | BSD-3-Clause |
| imageio-ffmpeg 0.6.0 | <https://github.com/imageio/imageio-ffmpeg> | BSD-2-Clause; its wheel includes a separately licensed FFmpeg 7.1 binary |
| python-multipart | <https://github.com/Kludex/python-multipart> | Apache-2.0 |
| platformdirs | <https://github.com/tox-dev/platformdirs> | MIT |
| yt-dlp 2026.07.04 | <https://github.com/yt-dlp/yt-dlp> | Unlicense |

Transitive dependencies are included in the packaged Python environment. A release
builder must preserve the license metadata from every installed distribution and
review it before publishing a DMG.

## Web assets

| Component | Project | License |
|---|---|---|
| htmx | <https://github.com/bigskysoftware/htmx> | BSD-2-Clause |

Only locally vendored web assets are allowed in the application. If more assets are
added, their notices and source links must be added here before release.

## Bundled and optional runtimes

| Component | Project | License considerations |
|---|---|---|
| aria2 | <https://github.com/aria2/aria2> | GPL-2.0-or-later; include its license and corresponding source offer when distributed. |
| FFmpeg | <https://ffmpeg.org/> | LGPL-2.1-or-later by default; a particular build may become GPL. Preserve its build configuration and source offer. |
| Deno | <https://github.com/denoland/deno> | MIT |
| yt-dlp standalone | <https://github.com/yt-dlp/yt-dlp> | Unlicense |

`runtime-manifest.json` ships with the official Deno 2.9.3 macOS arm64 asset and aria2
1.37.0 release-source archive enabled and pinned to verified SHA-256 values. aria2 is
built locally as an HTTP/HTTPS-only arm64 executable using AppleTLS and system
libraries; the exact configure arguments are recorded in the manifest. The bootstrap
process invokes the runtime manager explicitly: it downloads and verifies the pinned
Deno binary, then downloads, verifies and attempts to build the pinned aria2 source.
It does not execute a remote shell installer or an unpinned native binary. Standalone
FFmpeg and yt-dlp downloads remain disabled until a maintainer records a trusted HTTPS
asset, exact version and verified SHA-256. Enabling a runtime is also a
release-compliance decision: the binary's complete license text, copyright notices,
build configuration and any corresponding-source obligations must be placed in the
release materials.

The imageio-ffmpeg 0.6.0 macOS arm64 wheel currently contains an FFmpeg 7.1 build made
with `--enable-gpl`. A binary release must therefore treat that embedded executable as
GPL software, preserve its exact build configuration and provide the applicable FFmpeg
license, notices and corresponding source. The imageio-ffmpeg BSD-2-Clause license
applies to the Python wrapper and does not replace FFmpeg's own license.

## Build tools

Build-only tools are not part of a normal source installation, but their notices must
be retained if they are redistributed: uv (Apache-2.0 OR MIT), Hatchling (MIT) and
PyInstaller (GPL-2.0-or-later with its bootloader exception).

This notice is not legal advice and does not replace any third-party license text.
