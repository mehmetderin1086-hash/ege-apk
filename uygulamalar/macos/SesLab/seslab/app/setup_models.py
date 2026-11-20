"""Model ağırlıklarını HuggingFace'ten indirir / varlığını doğrular.

Kullanım:
    uv run python -m app.setup_models            # indir (kaldığı yerden devam eder)
    uv run python -m app.setup_models --check    # yalnızca varlık + boyut raporu
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

from huggingface_hub import snapshot_download
from huggingface_hub.errors import LocalEntryNotFoundError

from app.config import STT_REPO, TTS_REPO

REPOS = [TTS_REPO, STT_REPO]
MIN_FREE_GB = 12.0


def _dir_size_gb(path: Path) -> float:
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file()) / 1e9


def check() -> dict[str, float | None]:
    """Her repo için yerel boyut (GB) veya None (eksik) döndürür."""
    result: dict[str, float | None] = {}
    for repo in REPOS:
        try:
            path = Path(
                snapshot_download(repo, local_files_only=True)
            )
            result[repo] = round(_dir_size_gb(path), 2)
        except LocalEntryNotFoundError:
            result[repo] = None
    return result


def download(progress_cb=None) -> None:
    """Her iki repoyu indirir. progress_cb(repo, done_idx, total) çağrılır."""
    free_gb = shutil.disk_usage("/").free / 1e9
    if free_gb < MIN_FREE_GB:
        raise RuntimeError(
            f"Yetersiz disk alanı: {free_gb:.1f} GB boş, en az {MIN_FREE_GB} GB gerekli."
        )
    for i, repo in enumerate(REPOS):
        if progress_cb:
            progress_cb(repo, i, len(REPOS))
        snapshot_download(repo)
        if progress_cb:
            progress_cb(repo, i + 1, len(REPOS))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="yalnızca durum raporu")
    args = parser.parse_args()

    if args.check:
        status = check()
        ok = True
        for repo, size in status.items():
            if size is None:
                print(f"  EKSİK  {repo}")
                ok = False
            else:
                print(f"  HAZIR  {repo}  ({size} GB)")
        return 0 if ok else 1

    def cb(repo: str, done: int, total: int) -> None:
        if done < total:
            print(f"[{done + 1}/{total}] indiriliyor: {repo} ...", flush=True)
        else:
            print(f"[{done}/{total}] tamam: {repo}", flush=True)

    download(cb)
    print("Tüm modeller hazır.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
