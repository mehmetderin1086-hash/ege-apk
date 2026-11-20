"""Bağımlılıksız Code 128 (set B+C) barkod üreteci.

Çevrimdışı ilke gereği harici kütüphane yok. Yalnız yazdırılabilir ASCII
(32-126) kodlanır — barkoda demirbaş numarası / okul numarası / ISBN girer,
ad-soyad girmez. Set C'ye geçiş ISO/IEC 15417 optimizasyon kurallarının
güvenli alt kümesiyle yapılır: başta ≥4 rakam ya da içeride ≥6 rakam
(sonda ≥4) çift çift C'de kodlanır, tek kalan rakam B'de kalır.
"""

from __future__ import annotations

_START_B = 104
_START_C = 105
_CODE_B = 100  # C içindeyken B'ye geçiş
_CODE_C = 99  # B içindeyken C'ye geçiş
_STOP = 106

# Her sembol 6 aralıktan (bar/boşluk genişliği) oluşur ve toplamı 11 modüldür;
# STOP 7 aralık, 13 modüldür. Tablo bütünlüğü test_barcode128'de bu değişmezle
# doğrulanır (satır toplamı 11/13 değilse yazım hatası vardır).
_PATTERNS = (
    "212222", "222122", "222221", "121223", "121322", "131222", "122213",
    "122312", "132212", "221213", "221312", "231212", "112232", "122132",
    "122231", "113222", "123122", "123221", "223211", "221132", "221231",
    "213212", "223112", "312131", "311222", "321122", "321221", "312212",
    "322112", "322211", "212123", "212321", "232121", "111323", "131123",
    "131321", "112313", "132113", "132311", "211313", "231113", "231311",
    "112133", "112331", "132131", "113123", "113321", "133121", "313121",
    "211331", "231131", "213113", "213311", "213131", "311123", "311321",
    "331121", "312113", "312311", "332111", "314111", "221411", "431111",
    "111224", "111422", "121124", "121421", "141122", "141221", "112214",
    "112412", "122114", "122411", "142112", "142211", "241211", "221114",
    "413111", "241112", "134111", "111242", "121142", "121241", "114212",
    "124112", "124211", "411212", "421112", "421211", "212141", "214121",
    "412121", "111143", "111341", "131141", "114113", "114311", "411113",
    "411311", "113141", "114131", "311141", "411131", "211412", "211214",
    "211232", "2331112",
)


def _validate(value: str) -> str:
    if not value:
        raise ValueError("Barkod değeri boş olamaz")
    for char in value:
        if not (32 <= ord(char) <= 126):
            raise ValueError(f"Code 128 set B dışı karakter: {char!r}")
    return value


def _digit_run(value: str, start: int) -> int:
    end = start
    while end < len(value) and value[end].isdigit():
        end += 1
    return end - start


def encode(value: str) -> list[int]:
    """Checksum dahil, STOP hariç codepoint dizisi."""

    value = _validate(value)
    codes: list[int] = []
    position = 0
    length = len(value)
    run = _digit_run(value, 0)
    if run >= 4 or run == length == 2:
        # Tek uzunluklu rakam dizisinde çiftler C'de kodlanır; kalan tek
        # rakam döngü içinde B'ye geçilerek kodlanır.
        current = "C"
        codes.append(_START_C)
    else:
        current = "B"
        codes.append(_START_B)
    while position < length:
        if current == "C":
            if _digit_run(value, position) >= 2:
                codes.append(int(value[position : position + 2]))
                position += 2
            else:
                codes.append(_CODE_B)
                current = "B"
        else:
            run = _digit_run(value, position)
            if run >= 6 or (run >= 4 and position + run == length):
                if run % 2 == 1:
                    # Çift kalması için ilk rakam B'de kodlanır.
                    codes.append(ord(value[position]) - 32)
                    position += 1
                codes.append(_CODE_C)
                current = "C"
            else:
                codes.append(ord(value[position]) - 32)
                position += 1
    checksum = codes[0]
    for index, code in enumerate(codes[1:], start=1):
        checksum += index * code
    codes.append(checksum % 103)
    return codes


def modules(value: str) -> list[tuple[int, bool]]:
    """(genişlik, bar mı?) dizisi; bar=True siyah çubuk demektir."""

    result: list[tuple[int, bool]] = []
    for code in [*encode(value), _STOP]:
        for index, width in enumerate(_PATTERNS[code]):
            result.append((int(width), index % 2 == 0))
    return result


def svg(
    value: str,
    *,
    module: float = 2.0,
    height: int = 60,
    quiet: int = 10,
    text: bool = True,
) -> str:
    """Kendine yeten SVG (harici kaynak yok); yazdırma sayfalarına gömülür."""

    bars = modules(value)
    total_modules = sum(width for width, _ in bars) + 2 * quiet
    width_px = total_modules * module
    text_height = 16 if text else 0
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width_px:g}" '
        f'height="{height + text_height}" '
        f'viewBox="0 0 {width_px:g} {height + text_height}" '
        'role="img" aria-label="barkod">'
    ]
    x = quiet * module
    for width, is_bar in bars:
        bar_width = width * module
        if is_bar:
            parts.append(
                f'<rect x="{x:g}" y="0" width="{bar_width:g}" height="{height}" fill="#000"/>'
            )
        x += bar_width
    if text:
        escaped = (
            value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        )
        parts.append(
            f'<text x="{width_px / 2:g}" y="{height + 13}" text-anchor="middle" '
            f'font-family="monospace" font-size="12" fill="#000">{escaped}</text>'
        )
    parts.append("</svg>")
    return "".join(parts)
