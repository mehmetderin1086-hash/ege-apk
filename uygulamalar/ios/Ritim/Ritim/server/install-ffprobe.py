#!/usr/bin/env python3
"""Install a pinned Apple Silicon FFprobe binary, verified before execution.

Publisher/source and published binary checksum: https://www.osxexperts.net/
FFmpeg itself distributes source; OSXExperts builds this standalone macOS tool.
Other platforms should install their package manager's ffmpeg package instead.
"""
import hashlib
import io
import os
from pathlib import Path
import platform
import subprocess
from urllib.request import urlopen
import zipfile

URL = "https://www.osxexperts.net/ffprobe9arm.zip"
SHA256 = "e11c17e8200b3ee4c4c186d245e2b4053f01d56957336c1817fca0b997469106"


def main():
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("Bu yardımcı Apple Silicon içindir. FFmpeg/FFprobe paketini paket yöneticinizle kurun.")
    destination = Path(__file__).resolve().parent / ".runtime" / "tools" / "ffprobe"
    if destination.is_file() and hashlib.sha256(destination.read_bytes()).hexdigest() == SHA256:
        print("FFprobe doğrulandı; zaten kurulu.")
        return
    with urlopen(URL, timeout=45) as response:
        data = response.read(100 * 1024 * 1024 + 1)
    if len(data) > 100 * 1024 * 1024:
        raise SystemExit("FFprobe arşivi boyut sınırını aştı.")
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        entries = [item for item in archive.infolist() if Path(item.filename).name == "ffprobe"
                   and not item.filename.startswith("__MACOSX/") and item.file_size <= 150 * 1024 * 1024]
        if len(entries) != 1:
            raise SystemExit("FFprobe arşivinin içeriği doğrulanamadı.")
        binary = archive.read(entries[0])
    if hashlib.sha256(binary).hexdigest() != SHA256:
        raise SystemExit("FFprobe SHA256 doğrulaması başarısız; hiçbir dosya çalıştırılmadı.")
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = destination.with_suffix(".tmp")
    temporary.write_bytes(binary)
    os.chmod(temporary, 0o700)
    temporary.replace(destination)
    result = subprocess.run([str(destination), "-version"], check=True, capture_output=True, text=True, timeout=15)
    print(result.stdout.splitlines()[0])
    print("FFprobe SHA256 doğrulandı ve Ritim'in özel araç dizinine kuruldu.")


if __name__ == "__main__":
    main()
