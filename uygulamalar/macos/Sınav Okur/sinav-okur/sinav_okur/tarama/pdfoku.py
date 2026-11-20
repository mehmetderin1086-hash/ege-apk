"""Taranmış PDF/görüntü dosyalarını sayfa görüntülerine (BGR numpy) çevirme."""

from __future__ import annotations

from collections.abc import Sequence
from pathlib import Path
import subprocess
import sys
import tempfile

import cv2
import numpy as np

GORUNTU_UZANTILARI = {
    ".png", ".jpg", ".jpeg", ".tif", ".tiff",
    ".bmp", ".webp", ".heic", ".heif",
}


def pdf_sayfalari(
    yol: str | Path, dpi: int = 300, *, azami_sayfa: int | None = None
) -> list[np.ndarray]:
    import pypdfium2 as pdfium

    try:
        belge = pdfium.PdfDocument(str(yol))
    except Exception as exc:
        raise ValueError(
            "PDF açılamadı; dosya bozuk, şifreli veya desteklenmeyen biçimde olabilir."
        ) from exc
    sayfalar = []
    try:
        sayfa_sayisi = len(belge)
        if sayfa_sayisi == 0:
            raise ValueError("PDF içinde okunabilir sayfa bulunamadı.")
        if azami_sayfa is not None and sayfa_sayisi > azami_sayfa:
            raise ValueError(
                f"Bir yüklemede en fazla {azami_sayfa} sayfa olabilir; "
                f"PDF {sayfa_sayisi} sayfa içeriyor."
            )
        for sayfa in belge:
            bitmap = sayfa.render(scale=dpi / 72.0)
            pil = bitmap.to_pil().convert("RGB")
            sayfalar.append(cv2.cvtColor(np.asarray(pil), cv2.COLOR_RGB2BGR))
    except ValueError:
        raise
    except Exception as exc:
        raise ValueError("PDF sayfaları görüntüye dönüştürülemedi.") from exc
    finally:
        belge.close()
    return sayfalar


def dosya_sayfalari(
    yol: str | Path, dpi: int = 300, *, azami_sayfa: int | None = None
) -> list[np.ndarray]:
    """PDF veya görüntü dosyasını sayfa listesine çevirir."""
    yol = Path(yol)
    if yol.suffix.lower() == ".pdf":
        return pdf_sayfalari(yol, dpi, azami_sayfa=azami_sayfa)
    if yol.suffix.lower() in {".tif", ".tiff"}:
        from PIL import Image

        try:
            with Image.open(yol) as belge:
                kare_sayisi = int(getattr(belge, "n_frames", 1))
                if (
                    azami_sayfa is not None
                    and kare_sayisi > azami_sayfa
                ):
                    raise ValueError(
                        f"Bir yüklemede en fazla {azami_sayfa} sayfa olabilir; "
                        f"TIFF {kare_sayisi} sayfa içeriyor."
                    )
                sayfalar = []
                for kare_no in range(kare_sayisi):
                    belge.seek(kare_no)
                    rgb = np.asarray(belge.convert("RGB"))
                    sayfalar.append(cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))
                return sayfalar
        except ValueError:
            raise
        except (OSError, EOFError) as exc:
            raise ValueError("TIFF görüntüsü okunamadı veya bozuk.") from exc
    if yol.suffix.lower() in GORUNTU_UZANTILARI:
        if yol.suffix.lower() in {".heic", ".heif"}:
            if sys.platform == "darwin":
                sips = Path("/usr/bin/sips")
                if not sips.is_file():
                    raise ValueError(
                        "HEIC/HEIF fotoğrafı bu sistemde dönüştürülemiyor; "
                        "JPG, PNG veya PDF olarak dışa aktarın."
                    )
                with tempfile.TemporaryDirectory(prefix="sinav-okur-heic-") as gecici:
                    png = Path(gecici) / "sayfa.png"
                    try:
                        subprocess.run(
                            [
                                str(sips),
                                "-s",
                                "format",
                                "png",
                                str(yol),
                                "--out",
                                str(png),
                            ],
                            check=True,
                            capture_output=True,
                            timeout=60,
                        )
                    except (subprocess.SubprocessError, OSError) as exc:
                        raise ValueError(
                            "HEIC/HEIF fotoğrafı okunamadı; dosya bozuk olabilir."
                        ) from exc
                    goruntu = cv2.imread(str(png), cv2.IMREAD_COLOR)
            else:
                # macOS dışında sips yok; pillow-heif kuruluysa onunla çöz.
                try:
                    import pillow_heif
                except ImportError as exc:
                    raise ValueError(
                        "HEIC/HEIF fotoğrafı bu sistemde dönüştürülemiyor; "
                        "JPG, PNG veya PDF olarak dışa aktarın."
                    ) from exc
                pillow_heif.register_heif_opener()
                from PIL import Image

                try:
                    with Image.open(yol) as pil_goruntu:
                        rgb = np.asarray(pil_goruntu.convert("RGB"))
                except (OSError, ValueError) as exc:
                    raise ValueError(
                        "HEIC/HEIF fotoğrafı okunamadı; dosya bozuk olabilir."
                    ) from exc
                goruntu = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        else:
            goruntu = cv2.imread(str(yol), cv2.IMREAD_COLOR)
        if goruntu is None:
            raise ValueError(f"Görüntü okunamadı: {yol}")
        return [goruntu]
    raise ValueError(f"Desteklenmeyen dosya türü: {yol.suffix}")


def dosyalar_sayfalari(
    yollar: Sequence[str | Path],
    dpi: int = 300,
    *,
    azami_sayfa: int | None = None,
) -> list[np.ndarray]:
    """Aynı öğrenciye ait ayrı PDF/görüntüleri yükleme sırasıyla birleştir."""
    sayfalar: list[np.ndarray] = []
    for yol in yollar:
        kalan = (
            None if azami_sayfa is None
            else azami_sayfa - len(sayfalar)
        )
        if kalan is not None and kalan <= 0:
            raise ValueError(
                f"Bir yüklemede en fazla {azami_sayfa} sayfa olabilir."
            )
        sayfalar.extend(dosya_sayfalari(yol, dpi, azami_sayfa=kalan))
    return sayfalar
