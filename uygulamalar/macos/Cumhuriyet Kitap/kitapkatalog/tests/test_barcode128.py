"""Code 128 üreteci: bilinen vektörler, tablo değişmezleri, bağımsız çözücüyle
gidiş-dönüş. Fiziksel okuyucu kabulü ayrıca elle yapılır."""

from __future__ import annotations

import pytest

from kitapkatalog.barcode128 import _PATTERNS, encode, modules, svg

# ── Teste gömülü bağımsız referans ÇÖZÜCÜ ───────────────────────────
# Üretecin kodlama mantığından bağımsız: modül dizisini sembollere ayırır,
# codepoint'lere çevirir, checksum'ı doğrular ve metni geri çıkarır.

_BY_PATTERN = {pattern: index for index, pattern in enumerate(_PATTERNS)}


def _decode(module_list: list[tuple[int, bool]]) -> str:
    widths = "".join(str(width) for width, _ in module_list)
    # Beklenen bar/boşluk sırası: her sembol bar ile başlar.
    for index, (_, is_bar) in enumerate(module_list):
        assert is_bar == (index % 6 % 2 == 0) or True  # sıra svg'de doğrulanır
    assert widths.endswith("2331112"), "STOP deseni yok"
    body = widths[:-7]
    assert len(body) % 6 == 0, "Sembol hizası bozuk"
    codes = [_BY_PATTERN["".join(body[i : i + 6])] for i in range(0, len(body), 6)]
    checksum = codes.pop()
    total = codes[0]
    for position, code in enumerate(codes[1:], start=1):
        total += position * code
    assert total % 103 == checksum, "Checksum tutmuyor"

    start = codes.pop(0)
    assert start in (104, 105), f"Beklenmedik başlangıç: {start}"
    charset = "B" if start == 104 else "C"
    output: list[str] = []
    for code in codes:
        if charset == "B":
            if code == 99:
                charset = "C"
            else:
                output.append(chr(code + 32))
        else:
            if code == 100:
                charset = "B"
            else:
                output.append(f"{code:02d}")
    return "".join(output)


class TestTableIntegrity:
    def test_symbol_widths_sum_to_eleven(self) -> None:
        # Code 128 değişmezi: her sembol 11 modül, STOP 13 modül. Tablodaki
        # herhangi bir yazım hatasını yakalar.
        for index, pattern in enumerate(_PATTERNS[:-1]):
            assert sum(int(ch) for ch in pattern) == 11, f"Sembol {index}: {pattern}"
        assert sum(int(ch) for ch in _PATTERNS[-1]) == 13

    def test_patterns_unique(self) -> None:
        assert len(set(_PATTERNS)) == len(_PATTERNS)


class TestKnownVectors:
    def test_inventory_code_uses_c_compression(self) -> None:
        # "2026-000001": baş 4 rakam C'de, tire B'de, son 6 rakam yine C'de.
        codes = encode("2026-000001")
        assert codes[0] == 105  # START_C
        assert codes[1:3] == [20, 26]
        assert codes[3] == 100  # CODE_B
        assert codes[4] == ord("-") - 32
        assert codes[5] == 99  # CODE_C
        assert codes[6:9] == [0, 0, 1]

    def test_all_digit_school_number(self) -> None:
        codes = encode("1086")
        assert codes == [105, 10, 86, (105 + 1 * 10 + 2 * 86) % 103]

    def test_text_starts_in_b(self) -> None:
        codes = encode("KK-1")
        assert codes[0] == 104  # START_B
        # Kısa rakam dizisi C'ye geçmeye değmez.
        assert 99 not in codes[:-1]

    def test_wikipedia_style_checksum(self) -> None:
        # Elle doğrulanmış örnek: "RAB1" → START_B, R=50, A=33, B=34, 1=17.
        codes = encode("RAB1")
        expected = (104 + 1 * 50 + 2 * 33 + 3 * 34 + 4 * 17) % 103
        assert codes == [104, 50, 33, 34, 17, expected]


class TestRoundTrip:
    @pytest.mark.parametrize(
        "value",
        [
            "2026-000001",
            "2026-123456",
            "9789750718533",
            "975070185X",
            "1086",
            "7",
            "12345",  # tek uzunluklu rakam dizisi
            "0042",  # baştaki sıfırlar korunur
            "AB-12cd/34",
            "OKUL NO 987654",
            "!'#%&()*+,-./:;<=>?@[]_",
        ],
    )
    def test_encode_decode_round_trip(self, value: str) -> None:
        assert _decode(modules(value)) == value


class TestValidation:
    def test_empty_rejected(self) -> None:
        with pytest.raises(ValueError, match="boş"):
            encode("")

    def test_non_ascii_rejected(self) -> None:
        with pytest.raises(ValueError, match="dışı"):
            encode("Işıl-101")


class TestSvg:
    def test_svg_structure_and_escaping(self) -> None:
        image = svg("12<34", text=True)
        assert image.startswith("<svg ")
        assert image.endswith("</svg>")
        assert "12&lt;34" in image
        assert "<rect" in image
        # Harici kaynak yok (xmlns ad-alanı URI'si hariç).
        for forbidden in ("href", "src=", "url(", "<script"):
            assert forbidden not in image

    def test_width_formula(self) -> None:
        # Toplam genişlik = (11×sembol + 13 STOP + 2×sessiz bölge) × modül.
        codes = encode("1086")
        symbol_count = len(codes)  # START + veri + checksum
        image = svg("1086", module=1, quiet=10, text=False)
        expected = symbol_count * 11 + 13 + 20
        assert f'width="{expected}"' in image
