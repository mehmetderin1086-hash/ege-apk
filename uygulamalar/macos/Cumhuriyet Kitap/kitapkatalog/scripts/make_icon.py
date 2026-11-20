"""KitapKatalog uygulama simgesini (PNG ve macOS ICNS) üretir.

    uv run python scripts/make_icon.py

Simge, açık bir kitap ile üzerindeki büyüteci birleştirir: dört yüzü okuyup
bibliyografik künyeyi çıkaran uygulamanın işini tek bakışta anlatır. 32 px'e
indiğinde de okunur kalması için ayrıntı az, karşıtlık yüksek tutuldu.

ICNS, `build_release.py`'nin PyInstaller'a verdiği simgedir; üretilmezse
paket PyInstaller'ın jenerik `icon-windowed.icns` dosyasıyla çıkar.
"""

from __future__ import annotations

import struct
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw

BOYUT = 1024
KENAR = 224  # macOS'un kare simgelerdeki alışılmış köşe yuvarlaması
ARKA_UST = (34, 47, 92)
ARKA_ALT = (14, 116, 122)
KAGIT = (250, 250, 247)
KAGIT_GOLGE = (200, 209, 219)
CIZGI = (139, 154, 174)
CILT = (226, 84, 58)
CERCEVE = (255, 190, 74)
CAM = (18, 32, 66, 96)


def _arka_plan() -> Image.Image:
    """Dikey degradeyi yuvarlatılmış kareye kırpar."""
    katman = Image.new("RGB", (1, BOYUT))
    for y in range(BOYUT):
        oran = y / (BOYUT - 1)
        katman.putpixel(
            (0, y),
            tuple(
                round(ust + (alt - ust) * oran) for ust, alt in zip(ARKA_UST, ARKA_ALT, strict=True)
            ),
        )
    zemin = katman.resize((BOYUT, BOYUT)).convert("RGBA")
    maske = Image.new("L", (BOYUT, BOYUT), 0)
    ImageDraw.Draw(maske).rounded_rectangle((0, 0, BOYUT - 1, BOYUT - 1), KENAR, fill=255)
    zemin.putalpha(maske)
    return zemin


def _kitap(cizim: ImageDraw.ImageDraw) -> None:
    sol, sag = 138, 886
    ust, alt = 430, 806
    orta = BOYUT // 2
    kubbe = 54  # sayfa destesinin dış kenardaki düşüşü

    for isaret in (-1, 1):
        dis = sol if isaret < 0 else sag
        cizim.polygon(
            [(orta, ust), (dis, ust + kubbe), (dis, alt - 62), (orta, alt)],
            fill=KAGIT,
        )
        # Sayfa destesinin kalınlığı: alt kenarda koyu bir şerit.
        cizim.polygon(
            [(orta, alt), (dis, alt - 62), (dis, alt + 4), (orta, alt + 66)],
            fill=KAGIT_GOLGE,
        )

    # Satır izleri: sol sayfada tam, sağ sayfada büyütecin dışında kalan kısım.
    for sira in range(4):
        y = ust + 92 + sira * 56
        cizim.line([(228, y + 26), (orta - 54, y)], fill=CIZGI, width=18)
        cizim.line([(orta + 54, y), (orta + 168, y + 10)], fill=CIZGI, width=18)

    cizim.polygon(
        [
            (orta - 24, ust - 16),
            (orta + 24, ust - 16),
            (orta + 24, alt + 72),
            (orta - 24, alt + 72),
        ],
        fill=CILT,
    )


def _buyutec(cizim: ImageDraw.ImageDraw) -> None:
    merkez = (664, 388)
    yaricap = 186
    kutu = (
        merkez[0] - yaricap,
        merkez[1] - yaricap,
        merkez[0] + yaricap,
        merkez[1] + yaricap,
    )
    # Sap önce çizilir ki halka onun ucunu örtsün.
    cizim.line([(786, 510), (906, 630)], fill=CERCEVE, width=64)
    cizim.ellipse(kutu, fill=CAM)
    cizim.ellipse(kutu, outline=CERCEVE, width=40)


def _icns_yaz(gorsel: Image.Image, hedef: Path) -> None:
    """PNG temsillerini doğrudan ICNS kapsayıcısına koyar.

    macOS 26'daki `iconutil`, geçerli bir iconset'i de "Invalid Iconset" diye
    reddedebiliyor; bu yüzden standart PNG tabanlı ICNS blokları elle yazılır.
    """
    temsiller = (
        (b"icp4", 16),
        (b"icp5", 32),
        (b"icp6", 64),
        (b"ic07", 128),
        (b"ic08", 256),
        (b"ic09", 512),
        (b"ic10", 1024),
    )
    bloklar: list[bytes] = []
    for tur, boyut in temsiller:
        tampon = BytesIO()
        gorsel.resize((boyut, boyut), Image.LANCZOS).save(tampon, format="PNG")
        veri = tampon.getvalue()
        bloklar.append(tur + struct.pack(">I", len(veri) + 8) + veri)
    govde = b"".join(bloklar)
    hedef.write_bytes(b"icns" + struct.pack(">I", len(govde) + 8) + govde)


def uret(png_hedefi: Path, icns_hedefi: Path | None = None) -> None:
    gorsel = _arka_plan()
    cizim = ImageDraw.Draw(gorsel, "RGBA")
    _kitap(cizim)
    _buyutec(cizim)
    png_hedefi.parent.mkdir(parents=True, exist_ok=True)
    gorsel.save(png_hedefi)
    print(f"Simge yazıldı: {png_hedefi}")
    if icns_hedefi is not None:
        icns_hedefi.parent.mkdir(parents=True, exist_ok=True)
        _icns_yaz(gorsel, icns_hedefi)
        print(f"Simge yazıldı: {icns_hedefi}")


if __name__ == "__main__":
    varliklar = Path(__file__).resolve().parents[1] / "assets"
    uret(varliklar / "kitapkatalog-icon.png", varliklar / "kitapkatalog-icon.icns")
