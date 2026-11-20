"""Türkçe TTS öncesi metin normalizasyonu.

Sayıları, tarihleri, saatleri, para tutarlarını, kısaltmaları vb. yazıya döker;
TTS motoru rakam/sembol okumakta zayıf olduğundan bu boru hattı Türkçe çıktı
kalitesinin en büyük kaldıracıdır.

Kurallar SIRALI çalışır (koru → bileşik desenler → atomik desenler):
bir kuralın çıktısı tamamen harflerden oluştuğu için sonraki sayı kuralları
onu yeniden işleyemez.

Kullanım:
    text, applied = normalize_tr("Dr. Ahmet %25 indirimle ₺1.250,50 ödedi.")
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Callable

from num2words import num2words

from .abbreviations_tr import (
    ACRONYM_OVERRIDES,
    CHEM_FORMULAS,
    FOREIGN_LEXICON,
    LETTER_NAMES,
    TAIL_ABBREVS,
    TITLE_ABBREVS,
    TR_VOWELS,
    WORD_ACRONYMS,
)

# ---------------------------------------------------------------------------
# Sayı okuma yardımcıları
# ---------------------------------------------------------------------------

# num2words Türkçe çıktıyı bitişik verir ("yirmibeş"); TDK yazımı ve TTS
# telaffuzu için sayı sözcüklerine ayırıyoruz. En uzun eşleşme önce denenir;
# eşleşmeyen kuyruk (çekim eki: "inci", "te" vb.) son sözcüğe yapışık kalır.
_NUM_WORDS = sorted(
    [
        "katrilyon", "trilyon", "milyar", "milyon", "doksan", "yetmiş",
        "seksen", "altmış", "dokuz", "sekiz", "sıfır", "yirmi", "otuz",
        "kırk", "elli", "altı", "yedi", "dört", "dörd", "yüz", "bin",
        "bir", "iki", "üç", "beş", "on",
    ],
    key=len,
    reverse=True,
)


def _spaced(joined: str) -> str:
    """'binikiyüzelli' → 'bin iki yüz elli'; 'yirmibeşinci' → 'yirmi beşinci'."""
    s = joined.replace(" ", "")
    tokens: list[str] = []
    i = 0
    while i < len(s):
        for w in _NUM_WORDS:
            if s.startswith(w, i):
                tokens.append(w)
                i += len(w)
                break
        else:
            # Bilinmeyen kuyruk (ör. sıra/hâl eki) → son sözcüğe bitişik
            if tokens:
                tokens[-1] += s[i:]
            else:
                tokens.append(s[i:])
            break
    return " ".join(tokens)


def _int_words(n: int) -> str:
    return _spaced(num2words(n, lang="tr"))


def _ordinal_words(n: int) -> str:
    return _spaced(num2words(n, to="ordinal", lang="tr"))


def _digits_words(s: str) -> str:
    """Rakam rakam okuma: '05' → 'sıfır beş'."""
    return " ".join(_int_words(int(d)) for d in s)


def _decimal_part_words(s: str) -> str:
    """Ondalık kısım: '14' → 'on dört'; '05' → 'sıfır beş' (baştaki sıfırlar tek tek)."""
    stripped = s.lstrip("0")
    zeros = len(s) - len(stripped)
    parts = ["sıfır"] * zeros
    if stripped:
        parts.append(_int_words(int(stripped)))
    return " ".join(parts)


def _strip_thousands(s: str) -> int:
    return int(s.replace(".", ""))


_TR_VOWELS_LOWER = "aeıioöuü"
_FRONT_VOWELS = "eiöü"


def _dative_suffix(word: str) -> str:
    """Söz sözcüğün son ünlüsüne göre datif eki: 'yüz yirmi'→'ye', 'doksan'→'a'."""
    vowels = [c for c in word if c in _TR_VOWELS_LOWER]
    last = vowels[-1] if vowels else "e"
    buf = "y" if word and word[-1] in _TR_VOWELS_LOWER else ""
    return buf + ("e" if last in _FRONT_VOWELS else "a")


def _attach_word_suffix(expansion: str, suffix: str | None) -> str:
    """Genişletilmiş birime çekim ekini ünlü uyumuyla ekler (mmHg'ye → cıvaya).

    Kullanıcının yazdığı ek orijinal (okunamayan) kısaltmaya göreydi; artık
    Türkçe sözcüğe göre yeniden uyumlanır. Arka ünlüyle biten genişlemede ek
    kalınlaştırılır; apostrof düşürülür (sözcüğe ek doğrudan bitişir)."""
    if not suffix:
        return expansion
    vowels = [c for c in expansion if c in _TR_VOWELS_LOWER]
    last = vowels[-1] if vowels else "e"
    if last not in _FRONT_VOWELS:  # arka ünlü → eki kalınlaştır
        suffix = suffix.translate(str.maketrans("eiüö", "aıuo"))
    return expansion + suffix


# ---------------------------------------------------------------------------
# Kural altyapısı
# ---------------------------------------------------------------------------

@dataclass
class Rule:
    name: str
    apply: Callable[[str], str]


_PROTECT_RE = re.compile(
    r"(?:https?://\S+|www\.\S+|[\w.+-]+@[\w-]+\.[\w.]+)", re.IGNORECASE
)


def _make_rules() -> list[Rule]:
    rules: list[Rule] = []

    # -- 2. Unvan/adres kısaltmaları (nokta asla korunmaz) ------------------
    title_pattern = re.compile(
        r"(?<![\w.])("
        + "|".join(re.escape(k) for k in sorted(TITLE_ABBREVS, key=len, reverse=True))
        + r")(?!\w)"
    )

    _num_before_re = re.compile(r"\d\s*$")

    def expand_titles(text: str) -> str:
        def repl(m: re.Match) -> str:
            token = m.group(1)
            # "Hz." hem "Hazreti" hem hertz (Hz) birimi; sayı öncülüyse
            # ("50 Hz.") başlık değil birimdir → birim kuralına bırak.
            if token == "Hz." and _num_before_re.search(text[: m.start()]):
                return m.group(0)
            return TITLE_ABBREVS[token]

        return title_pattern.sub(repl, text)

    rules.append(Rule("kisaltma", expand_titles))

    # -- 2b. Liste sonu kısaltmaları (vb., vs.) — sonraki sözcük büyükse
    #        gerçek cümle sonudur, nokta korunur ------------------------------
    tail_pattern = re.compile(
        r"(?<![\w.])("
        + "|".join(re.escape(k) for k in TAIL_ABBREVS)
        + r")(\s+[\"'«“‘]*[A-ZÇĞİÖŞÜ0-9])?"
    )

    def expand_tails(text: str) -> str:
        def repl(m: re.Match) -> str:
            expansion = TAIL_ABBREVS[m.group(1)]
            if m.group(2):  # ardından büyük harf → cümle sonuydu
                return expansion + "." + m.group(2)
            return expansion

        return tail_pattern.sub(repl, text)

    rules.append(Rule("kisaltma_liste", expand_tails))

    # -- 2c. Romen rakamı + nokta → sıra sayısı: "II. Abdülhamit" → "ikinci",
    #        "XV. yüzyıl" → "on beşinci yüzyıl". Tek harfte yalnız I/V/X
    #        (C./D./L./M. kişi adı baş harfi olabilir).
    ROMAN_VALUES = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}
    roman_dot_pattern = re.compile(r"\b([IVXLCDM]{1,7})\.(?=\s)")

    def _roman_to_int(s: str) -> int | None:
        total, prev = 0, 0
        for ch in reversed(s):
            val = ROMAN_VALUES[ch]
            total = total - val if val < prev else total + val
            prev = max(prev, val)
        return total if 1 <= total <= 400 else None

    def expand_roman_ordinals(text: str) -> str:
        def repl(m: re.Match) -> str:
            token = m.group(1)
            if len(token) == 1 and token not in ("I", "V", "X"):
                return m.group(0)  # olası baş harf (D., C., L., M.)
            value = _roman_to_int(token)
            if value is None:
                return m.group(0)
            return _ordinal_words(value)

        return roman_dot_pattern.sub(repl, text)

    rules.append(Rule("romen", expand_roman_ordinals))

    # -- 2d. Yabancı/marka kelimeler → fonetik yazım (WhatsApp → Vatsap) -----
    foreign_pattern = re.compile(
        r"(?<![\wçğıöşüÇĞİÖŞÜ])("
        + "|".join(re.escape(k) for k in sorted(FOREIGN_LEXICON, key=len, reverse=True))
        + r")(?![\wçğıöşüÇĞİÖŞÜ])",
        re.IGNORECASE,
    )

    def _lex_key(surface: str) -> str:
        # Türkçe büyük İ için 'İ'.lower() = 'i̇' (i + U+0307 birleşik nokta) olur
        # ve sözlük anahtarıyla eşleşmeyip KeyError verirdi. Küçültmeden ÖNCE
        # İ'yi düz 'i'ye çeviririz (anahtarlar küçük 'i' ile yazılı).
        return surface.replace("İ", "i").lower()

    def expand_foreign(text: str) -> str:
        return foreign_pattern.sub(
            lambda m: FOREIGN_LEXICON[_lex_key(m.group(1))], text
        )

    rules.append(Rule("yabanci", expand_foreign))

    # -- 4. Para: ₺1.250,50 / 1.250,50 TL / 25 TL / TL'ye ekleri --------------
    # (Akronim kuralı SONRA çalışır; yoksa "TL" ve "GB" harf harf okunurdu.)
    money_pattern = re.compile(
        r"(?:₺\s?(?P<w1>\d{1,3}(?:\.\d{3})*|\d+)(?:,(?P<c1>\d{1,2}))?"
        r"|(?<![\d,.])(?P<w2>\d{1,3}(?:\.\d{3})*|\d+)(?:,(?P<c2>\d{1,2}))?"
        r"\s?(?:TL|₺))(?:'(?P<ek>[a-zçğıöşü]+))?(?!\w)"
    )

    def _back_harmony(suffix: str) -> str:
        """'lira' kalın ünlüyle bittiği için eki kalın sıraya çevir (ye→ya)."""
        return suffix.translate(str.maketrans("eiüö", "aıuo"))

    def expand_money(text: str) -> str:
        def repl(m: re.Match) -> str:
            whole = m.group("w1") or m.group("w2")
            cents = m.group("c1") or m.group("c2")
            out = _int_words(_strip_thousands(whole)) + " lira"
            if cents:
                c = int(cents)
                if len(cents) == 1:  # '32,5 TL' → 50 kuruş (5 değil!)
                    c *= 10
                if c > 0:
                    out += " " + _int_words(c) + " kuruş"
            if m.group("ek"):
                out += _back_harmony(m.group("ek"))
            return out

        return money_pattern.sub(repl, text)

    rules.append(Rule("para", expand_money))

    # -- 5. Yüzde: %25 / %12,5 / 25% / %25'lik (kesme eki bitişik okunur) -----
    percent_pattern = re.compile(
        r"%\s?(?P<a>\d+)(?:,(?P<ad>\d+))?(?:'(?P<aek>[a-zçğıöşü]+))?"
        r"|(?P<b>\d+)(?:,(?P<bd>\d+))?\s?%(?:'(?P<bek>[a-zçğıöşü]+))?"
    )

    def expand_percent(text: str) -> str:
        def repl(m: re.Match) -> str:
            whole = m.group("a") or m.group("b")
            dec = m.group("ad") or m.group("bd")
            suffix = m.group("aek") or m.group("bek") or ""
            out = "yüzde " + _int_words(int(whole))
            if dec:
                out += " virgül " + _decimal_part_words(dec)
            return out + suffix  # "%25'lik" → "yüzde yirmi beşlik"

        return percent_pattern.sub(repl, text)

    rules.append(Rule("yuzde", expand_percent))

    # -- 7. Tarih: 15.07.2026 / 15/07/2026 → "on beş Temmuz iki bin yirmi altı"
    #    (Saat kuralından ÖNCE çalışmalı: nokta ayraçlı saat desteği eklendiği
    #     için '15.07' parçası aksi hâlde saat sanılırdı.)
    MONTHS = [
        "Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
        "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık",
    ]
    date_pattern = re.compile(
        r"\b(\d{1,2})[./](\d{1,2})[./](\d{4})\b(?:'([a-zçğıöşü]+))?"
    )

    def expand_date(text: str) -> str:
        def repl(m: re.Match) -> str:
            day, month, year = int(m.group(1)), int(m.group(2)), int(m.group(3))
            if not (1 <= day <= 31 and 1 <= month <= 12):
                return m.group(0)  # tarih değil → dokunma
            out = f"{_int_words(day)} {MONTHS[month - 1]} {_int_words(year)}"
            if m.group(4):  # "2026'da" → "...iki bin yirmi altıda"
                out += m.group(4)
            return out

        return date_pattern.sub(repl, text)

    rules.append(Rule("tarih", expand_date))

    # -- 6. Saat: 14:30 / 14.30 (TDK) → "on dört otuz"; kesme eki desteklenir
    time_pattern = re.compile(
        r"\b([01]?\d|2[0-3])[:.]([0-5]\d)\b(?:'([a-zçğıöşü]+))?"
    )

    def expand_time(text: str) -> str:
        def repl(m: re.Match) -> str:
            hour, minute = int(m.group(1)), int(m.group(2))
            out = _int_words(hour)
            if minute != 0:
                if minute < 10:
                    out += " sıfır " + _int_words(minute)
                else:
                    out += " " + _int_words(minute)
            if m.group(3):  # "14.30'da" → "on dört otuzda"
                out += m.group(3)
            return out

        return time_pattern.sub(repl, text)

    rules.append(Rule("saat", expand_time))

    # -- 8. Telefon: 0532 123 45 67 → gruplu okuma ---------------------------
    phone_pattern = re.compile(
        r"\b0\s?\(?(\d{3})\)?[\s-]?(\d{3})[\s-]?(\d{2})[\s-]?(\d{2})\b"
    )

    def expand_phone(text: str) -> str:
        def group_words(g: str) -> str:
            if g.startswith("0"):
                return _digits_words(g)
            return _int_words(int(g))

        def repl(m: re.Match) -> str:
            groups = [group_words(m.group(i)) for i in range(1, 5)]
            return "sıfır " + ", ".join(groups)

        return phone_pattern.sub(repl, text)

    rules.append(Rule("telefon", expand_phone))

    # -- 8a. Tıbbi/bileşik birimler: 120/80 mmHg, 5 mg/dl, 400 IU, pH 7,4 -----
    #        'birim' kuralından ÖNCE: bileşik birimdeki bare "mg"/"IU" tek
    #        başına yakalanıp yarım genişlemesin diye. Case-sensitive.
    MED_UNITS = {
        "mmHg": "milimetre cıva",
        "mg/dl": "miligram desilitre", "mg/dL": "miligram desilitre",
        "g/dl": "gram desilitre", "g/dL": "gram desilitre",
        "mmol/l": "milimol litre", "mmol/L": "milimol litre",
        "mEq/l": "miliekivalan litre", "mEq/L": "miliekivalan litre",
        "ng/ml": "nanogram mililitre", "ng/mL": "nanogram mililitre",
        "µg": "mikrogram", "μg": "mikrogram", "mcg": "mikrogram",
        "IU": "ünite", "İÜ": "ünite",
        "U/l": "ünite litre", "U/L": "ünite litre",
        "kcal": "kilokalori",
    }
    # Tansiyon: "120/80 mmHg" → "yüz yirmiye seksen milimetre cıva"
    bp_pattern = re.compile(
        r"\b(\d{2,3})\s?/\s?(\d{2,3})\s?mmHg(?:'([a-zçğıöşü]+))?"
        r"(?![\wçğıöşüÇĞİÖŞÜ])"
    )
    # pH: case-sensitive, tek başına — "pH 7,4" → "pe haş yedi virgül dört"
    ph_pattern = re.compile(r"(?<![\wçğıöşüÇĞİÖŞÜ])pH(?![\wçğıöşüÇĞİÖŞÜ])")
    med_unit_pattern = re.compile(
        r"(\d(?:[\d.,]*\d)?)\s?("
        + "|".join(re.escape(u) for u in sorted(MED_UNITS, key=len, reverse=True))
        + r")(?:'([a-zçğıöşü]+))?(?![\wçğıöşüÇĞİÖŞÜ/])"
    )

    def expand_med_units(text: str) -> str:
        def bp_repl(m: re.Match) -> str:
            systolic, diastolic, suffix = m.group(1), m.group(2), m.group(3)
            # Sistolik: rakam + apostrof datif bırak, kesme_ekli kuralı yazıya
            # döker (dörd-yumuşaması bedava). Diastolik bare kalır, sayi işler.
            dative = _dative_suffix(_int_words(int(systolic)))
            reading = _attach_word_suffix("milimetre cıva", suffix)
            return f"{systolic}'{dative} {diastolic} {reading}"

        def unit_repl(m: re.Match) -> str:
            number, unit, suffix = m.group(1), m.group(2), m.group(3)
            return f"{number} {_attach_word_suffix(MED_UNITS[unit], suffix)}"

        text = bp_pattern.sub(bp_repl, text)
        text = ph_pattern.sub("pe haş", text)
        text = med_unit_pattern.sub(unit_repl, text)
        return text

    rules.append(Rule("tibbi_birim", expand_med_units))

    # -- 8a2. Bileşik birimler: 100 km/h, 9,8 m/s², 3000 rpm -----------------
    #         'birim'den ÖNCE: "m/s"nin bare "m"den önce bütün eşleşmesi için.
    COMPOUND_UNITS = {
        "m/s²": "metre bölü saniye kare", "m/s2": "metre bölü saniye kare",
        "km/h": "kilometre saat", "km/sa": "kilometre saat",
        "m/s": "metre bölü saniye", "m/dk": "metre dakika",
        "rpm": "devir dakika", "devir/dk": "devir dakika",
    }
    compound_pattern = re.compile(
        r"(\d(?:[\d.,]*\d)?)\s?("
        + "|".join(re.escape(u) for u in sorted(COMPOUND_UNITS, key=len, reverse=True))
        + r")(?:'([a-zçğıöşü]+))?(?![\wçğıöşüÇĞİÖŞÜ/])"
    )

    def expand_compound_units(text: str) -> str:
        return compound_pattern.sub(
            lambda m: f"{m.group(1)} "
            + _attach_word_suffix(COMPOUND_UNITS[m.group(2)], m.group(3)),
            text,
        )

    rules.append(Rule("bilesik_birim", expand_compound_units))

    # -- 8b. Birimler: 5 km → 5 kilometre (sayı sonraki kurallara kalır) ------
    UNITS = {
        "mm": "milimetre", "cm": "santimetre", "km": "kilometre", "m": "metre",
        "nm": "nanometre", "µm": "mikrometre", "μm": "mikrometre", "dm": "desimetre",
        "kg": "kilogram", "gr": "gram", "g": "gram", "mg": "miligram",
        "lt": "litre", "l": "litre", "ml": "mililitre",
        "GB": "cigabayt", "MB": "megabayt", "KB": "kilobayt", "TB": "terabayt",
        "°C": "derece", "°F": "fahrenhayt", "kWh": "kilovat saat",
        "kW": "kilovat", "W": "vat", "V": "volt", "mV": "milivolt",
        # Fizik birimleri (desen sayı öncülü zorunlu kıldığından tek harfliler
        # de güvenli: "5 A" → "beş amper", düz metinde tetiklenmez)
        "GHz": "gigahertz", "MHz": "megahertz", "kHz": "kilohertz", "Hz": "hertz",
        "kJ": "kilojul", "J": "jul", "kPa": "kilopaskal", "Pa": "paskal",
        "mA": "miliamper", "A": "amper", "N": "newton", "mol": "mol",
        "dB": "desibel", "eV": "elektronvolt", "K": "kelvin",
        "ms": "milisaniye", "µs": "mikrosaniye", "ns": "nanosaniye",
        # Ek fizik birimleri (desen sayı öncülü zorunlu → güvenli)
        "atm": "atmosfer", "cal": "kalori", "lm": "lümen", "lx": "lüks",
        "cd": "kandela", "Bq": "bekerel", "Gy": "grey", "Sv": "sivert",
        "Wb": "veber", "Ω": "om", "µF": "mikrofarad", "nF": "nanofarad",
        # Zaman/para kısaltmaları — desen sayı öncülü zorunlu kıldığından
        # "sn." burada güvenle "saniye"dir ("Sn." Sayın çakışmaz)
        "dk.": "dakika", "dk": "dakika", "sn.": "saniye", "sa.": "saat",
        "kr.": "kuruş",
        # Alan/hacim
        "km²": "kilometrekare", "m²": "metrekare", "cm²": "santimetrekare",
        "mm²": "milimetrekare", "m³": "metreküp", "cm³": "santimetreküp",
        "dm³": "desimetreküp", "km³": "kilometreküp",
    }
    unit_pattern = re.compile(
        r"(\d(?:[\d.,]*\d)?)\s?("
        + "|".join(re.escape(u) for u in sorted(UNITS, key=len, reverse=True))
        + r")(?![\wçğıöşüÇĞİÖŞÜ])"
    )

    def expand_units(text: str) -> str:
        return unit_pattern.sub(lambda m: f"{m.group(1)} {UNITS[m.group(2)]}", text)

    rules.append(Rule("birim", expand_units))

    # -- 8d. Üsler: x², 10^-9, m² birim kuralından SONRA (m² zaten çözüldü) ---
    SUP = "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻ⁿ"
    _SUP_TO_ASCII = str.maketrans("⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻", "0123456789+-")
    superscript_pattern = re.compile(rf"([A-Za-zçğıöşü0-9])([{SUP}]+)")
    caret_pattern = re.compile(r"(?<=[A-Za-z0-9\)])\^(-?\d+|[a-zA-Z])")

    def expand_powers(text: str) -> str:
        def sup_repl(m: re.Match) -> str:
            base, sup = m.group(1), m.group(2)
            if sup == "²":
                return f"{base} kare"
            if sup == "³":
                return f"{base} küp"
            if sup == "ⁿ":
                return f"{base} üzeri n"
            exp = sup.translate(_SUP_TO_ASCII).replace("-", "eksi ").replace("+", "")
            return f"{base} üzeri {exp}"  # rakamlar sonra 'sayi' ile okunur

        text = superscript_pattern.sub(sup_repl, text)
        text = caret_pattern.sub(
            lambda m: " üzeri " + (
                "eksi " + m.group(1)[1:] if m.group(1).startswith("-") else m.group(1)
            ),
            text,
        )
        return text

    rules.append(Rule("us", expand_powers))

    # -- 8e. Kimyasal formüller: H2O → su, CO2 → karbondioksit ---------------
    #        Akronimden ÖNCE: yoksa "CO2"/"NaCl" harf harf okunurdu.
    _SUB_TO_ASCII = str.maketrans("₀₁₂₃₄₅₆₇₈₉", "0123456789")
    formula_pattern = re.compile(
        r"(?<![\wçğıöşüÇĞİÖŞÜ])("
        + "|".join(re.escape(f) for f in sorted(CHEM_FORMULAS, key=len, reverse=True))
        + r")(?![\wçğıöşüÇĞİÖŞÜ])"
    )

    def expand_formulas(text: str) -> str:
        text = text.translate(_SUB_TO_ASCII)  # H₂O → H2O
        return formula_pattern.sub(lambda m: CHEM_FORMULAS[m.group(1)], text)

    rules.append(Rule("kimya_formul", expand_formulas))

    # -- 3. Akronimler: harf harf mi, kelime gibi mi? ------------------------
    #       Para (TL) ve birim (GB) kurallarından SONRA çalışmalı.
    #       Kurallar: (a) WORD_ACRONYMS beyaz listesi kelime okunur (NATO);
    #       (b) 2-3 harfliler DAİMA harf harf (ABD → "a be de", AB → "a be");
    #       (c) 4+ harfliler telaffuz edilebilirse kelime (sesli oranı ≥ 1/3
    #       ve ardışık 3 sessiz yok: ASELSAN gibi), değilse harf harf (TBMM).
    acronym_pattern = re.compile(r"\b([A-ZÇĞİÖŞÜQWX]{2,7})\b")
    _consonant_run = re.compile(r"[^AEIİOÖUÜ]{3}")

    # Vurgu/başlık amacıyla büyük yazılmış kısa Türkçe sözcükler akronim
    # değildir. Önceki "2-3 harf = daima kısaltma" sezgiseli örneğin
    # "HAYATIN İÇİNDE BİR YOLCULUK" başlığındaki BİR'i "be i re"ye
    # çeviriyordu. Bu yüksek frekanslı sözcükleri küçük harfe indirerek XTTS'e
    # normal kelime olduklarını açıkça bildiriyoruz; ABD/AB/MEB gibi gerçek
    # kısaltmalar mevcut harf-harf yolunda kalır.
    short_turkish_words = {
        "AD", "AH", "AK", "AL", "AN", "AR", "AS", "AT", "AV", "AY", "AZ",
        "AÇ", "BU", "DA", "DE", "EK", "EL", "EN", "EŞ", "EV", "EY", "HA",
        "İÇ", "İKİ", "İLK", "İP", "İŞ", "İYİ", "İZ", "Kİ", "Mİ", "MI", "MU", "MÜ",
        "NE", "OF", "OH", "OK", "OL", "ON", "OT", "OY", "ÖZ", "SU", "ŞU",
        "UN", "UÇ", "ÜÇ", "VE", "YA", "YE", "ADA", "ANA", "ARA", "ARI",
        "ATA", "BAĞ", "BAL", "BAŞ", "BEL", "BEN", "BEŞ", "BEY", "BİN", "BİR",
        "BİZ", "BOL", "BOŞ", "BOY", "BUL", "CAM", "CAN", "CEP", "ÇAY", "ÇEK",
        "ÇOK", "DAR", "DİL", "DİN", "DİŞ", "DUA", "DUR", "DÜZ", "FEN", "GEL",
        "GEN", "GİT", "GÖZ", "GÜN", "HAL", "HAM", "HAN", "HAT", "HEP", "HER",
        "HİÇ", "HOŞ", "İSE", "KAT", "KAZ", "KES", "KİM", "KOL", "KOY", "KUL",
        "KUM", "KUR", "KUŞ", "LAF", "MAL", "MOR", "MUZ", "NET", "ODA", "ONA",
        "ONU", "OVA", "PAY", "PEK", "PİS", "RET", "ROL", "RUH", "SAÇ", "SAĞ",
        "SAL", "SEN", "SES", "SIK", "SİZ", "SOL", "SON", "SOR", "SÖZ", "SUS",
        "SÜT", "TAŞ", "TEK", "TEL", "TEZ", "TIP", "TOK", "TON", "TOP", "TOZ",
        "TUZ", "TÜR", "VAR", "VUR", "YAT", "YAZ", "YER", "YIL", "YOK", "YOL",
        "YÜZ", "ZOR",
    }

    def _pronounceable(token: str) -> bool:
        vowels = sum(1 for ch in token if ch in TR_VOWELS)
        return vowels / len(token) >= 1 / 3 and not _consonant_run.search(token)

    all_caps_word = re.compile(r"\b[A-ZÇĞİÖŞÜQWX]{2,}\b")

    def soften_all_caps_headings(text: str) -> str:
        """Tamamı büyük doğal başlıkları XTTS için normal sözcüklere çevir.

        Büyük harf dizileri XTTS'te hem akronim sezgisini hem de prozodiyi
        bozabiliyor. En az dört büyük sözcüklü satırlarda telaffuz edilebilir
        doğal kelimeler küçültülür; TBMM/ABD gibi kısaltmalar ve NATO gibi
        yerleşik akronimler korunur.
        """
        out: list[str] = []
        for line in text.splitlines(keepends=True):
            tokens = all_caps_word.findall(line)
            if len(tokens) < 4:
                out.append(line)
                continue

            def lower_word(m: re.Match) -> str:
                token = m.group(0)
                if token in WORD_ACRONYMS or token in ACRONYM_OVERRIDES:
                    return token
                is_natural = token in short_turkish_words or (
                    len(token) >= 4 and _pronounceable(token)
                )
                if not is_natural:
                    return token
                return token.replace("İ", "i").replace("I", "ı").lower()

            out.append(all_caps_word.sub(lower_word, line))
        return "".join(out)

    rules.append(Rule("buyuk_harf_baslik", soften_all_caps_headings))

    def spell_acronyms(text: str) -> str:
        def repl(m: re.Match) -> str:
            token = m.group(1)
            if token in short_turkish_words:
                return token.replace("İ", "i").replace("I", "ı").lower()
            if token in ACRONYM_OVERRIDES:
                return ACRONYM_OVERRIDES[token]  # özel biçim: MR → "emar"
            if token in WORD_ACRONYMS:
                return token  # yerleşik telaffuz: kelime gibi (NATO, TÜBİTAK)
            if len(token) >= 4 and _pronounceable(token):
                return token  # KOSGEB deseni: kelime gibi okunabilir
            return " ".join(LETTER_NAMES.get(ch, ch) for ch in token)

        return acronym_pattern.sub(repl, text)

    rules.append(Rule("akronim", spell_acronyms))

    # -- 8c. Kesir: 1/2 → "bir bölü iki" (tarih kuralı gg/aa/yyyy'yi zaten
    #        tüketti; kalan sayı/sayı çiftleri kesir okunur) -------------------
    fraction_pattern = re.compile(r"\b(\d{1,3})/(\d{1,3})\b")

    def expand_fraction(text: str) -> str:
        return fraction_pattern.sub(
            lambda m: f"{_int_words(int(m.group(1)))} bölü {_int_words(int(m.group(2)))}",
            text,
        )

    rules.append(Rule("kesir", expand_fraction))

    # -- 9. Ekli sıra sayıları: 3'üncü / 5inci → "üçüncü" ---------------------
    ordinal_suffix_pattern = re.compile(
        r"\b(\d+)\s?'?\s?(?:[iıuü]nc[iıuü]|nc[iıuü])(?![\wçğıöşü])"
    )

    def expand_ordinal_suffix(text: str) -> str:
        return ordinal_suffix_pattern.sub(
            lambda m: _ordinal_words(int(m.group(1))), text
        )

    rules.append(Rule("sira_ekli", expand_ordinal_suffix))

    # -- 10. Noktalı sıra sayıları: "1. sırada" → "birinci sırada" ------------
    #        Yalnızca küçük harfle devam edenler; önünde rakam+nokta varsa
    #        (yılsız tarih "15.07." gibi) dokunma.
    ordinal_dot_pattern = re.compile(r"(?<![\d.])\b(\d+)\.(?=\s+[a-zçğıöşü])")

    def expand_ordinal_dot(text: str) -> str:
        return ordinal_dot_pattern.sub(
            lambda m: _ordinal_words(int(m.group(1))), text
        )

    rules.append(Rule("sira_nokta", expand_ordinal_dot))

    # -- 12a. Negatif sayılar: -5 → "eksi beş" ("5-10" aralığına dokunmaz) ----
    negative_pattern = re.compile(r"(?<![\d\w])-(?=\d)")

    def expand_negative(text: str) -> str:
        return negative_pattern.sub("eksi ", text)

    rules.append(Rule("negatif", expand_negative))

    # -- 12. Ondalık (TR virgül): 3,14 → "üç virgül on dört" ------------------
    #        Kesme ekinden ÖNCE çalışmalı: yoksa "3,5'lik"te kesme kuralı
    #        kesir hanesini yutar ("üç virgül beş'lik" doğru sonuçtur).
    decimal_pattern = re.compile(r"\b(\d{1,3}(?:\.\d{3})*|\d+),(\d+)\b")

    def expand_decimal(text: str) -> str:
        return decimal_pattern.sub(
            lambda m: _int_words(_strip_thousands(m.group(1)))
            + " virgül "
            + _decimal_part_words(m.group(2)),
            text,
        )

    rules.append(Rule("ondalik", expand_decimal))

    # -- 11. Kesme ekli sayılar: 1923'te → "bin dokuz yüz yirmi üçte" ---------
    #        Kullanıcının yazdığı ek zaten ünlü uyumuna uyar; sayı yazıya
    #        dökülüp ek bitişik eklenir. Ünlüyle başlayan ekte "dört" son
    #        ünsüzü yumuşar: 4'ü → "dördü" (dörtü değil).
    apostrophe_pattern = re.compile(r"\b(\d{1,3}(?:\.\d{3})*|\d+)'([a-zçğıöşü]+)\b")

    def expand_apostrophe(text: str) -> str:
        def repl(m: re.Match) -> str:
            words = _int_words(_strip_thousands(m.group(1)))
            suffix = m.group(2)
            if suffix[0] in "aeıioöuü" and words.endswith("dört"):
                words = words[:-1] + "d"
            return words + suffix

        return apostrophe_pattern.sub(repl, text)

    rules.append(Rule("kesme_ekli", expand_apostrophe))

    # -- 12c. Kesmesiz ekli sayılar: "1902de" → "bin dokuz yüz ikide" ---------
    #         Dil modeli ve OCR çıktıları kesme işaretini sık atlıyor; ek
    #         bitişik kalınca sayı hiç açılmıyor ve XTTS rakamı okumaya
    #         çalışıyordu. Ek listesi bilinçli olarak dar: yalnız iki harften
    #         uzun, sayıdan sonra gerçekten gelebilen çekim ekleri. Böylece
    #         "3d", "2x" gibi teknik yazımlar bozulmaz.
    bare_suffix_pattern = re.compile(
        r"\b(\d{2,}|\d)(de|da|te|ta|den|dan|ten|tan|deki|daki|teki|taki|"
        r"ye|ya|nin|nın|nun|nün|in|ın|un|ün|li|lı|lu|lü|ler|lar|lik|lık|luk|lük|"
        r"i|ı|u|ü)"
        r"(?![\wçğıöşü])"
    )

    def expand_bare_suffix(text: str) -> str:
        def repl(m: re.Match) -> str:
            return _int_words(int(m.group(1))) + m.group(2)

        return bare_suffix_pattern.sub(repl, text)

    rules.append(Rule("sayi_ekli", expand_bare_suffix))

    # -- 13. Binlik noktalı sayılar: 1.000.000 → "bir milyon" -----------------
    thousands_pattern = re.compile(r"\b\d{1,3}(?:\.\d{3})+\b")

    def expand_thousands(text: str) -> str:
        return thousands_pattern.sub(
            lambda m: _int_words(_strip_thousands(m.group(0))), text
        )

    rules.append(Rule("binlik", expand_thousands))

    # -- 13b. Yunan harfleri: α → alfa, π → pi, μ → mü ------------------------
    #         tibbi_birim'den SONRA (µg zaten tüketildi). μ tek başına "mü".
    GREEK = {
        "α": "alfa", "β": "beta", "γ": "gama", "δ": "delta", "ε": "epsilon",
        "ζ": "zeta", "η": "eta", "θ": "teta", "ι": "iyota", "κ": "kapa",
        "λ": "lambda", "μ": "mü", "µ": "mü", "ν": "nü", "ξ": "ksi",
        "ο": "omikron", "π": "pi", "ρ": "ro", "σ": "sigma", "ς": "sigma",
        "τ": "tau", "υ": "üpsilon", "φ": "fi", "χ": "ki", "ψ": "psi", "ω": "omega",
        "Α": "alfa", "Β": "beta", "Γ": "gama", "Δ": "delta", "Θ": "teta",
        "Λ": "lambda", "Ξ": "ksi", "Π": "pi", "Σ": "sigma", "Φ": "fi",
        "Ψ": "psi", "Ω": "omega",
    }
    greek_pattern = re.compile("|".join(re.escape(g) for g in GREEK))

    def expand_greek(text: str) -> str:
        return greek_pattern.sub(lambda m: f" {GREEK[m.group(0)]} ", text)

    rules.append(Rule("yunan", expand_greek))

    # -- 13c. Matematik sembolleri: 2 + 2 = 4 → "iki artı iki eşittir dört" ---
    #         'sayi'dan ÖNCE (rakamlar okunsun). '-' ve '/'ye DOKUNMAZ
    #         (negatif/kesir/tarih/bileşik-birim sahipleri bozulmasın).
    MATH_SYMBOLS = {
        "±": " artı eksi ", "∓": " eksi artı ", "×": " çarpı ", "÷": " bölü ",
        "·": " çarpı ", "√": " karekök ", "∛": " küpkök ", "∑": " toplam ",
        "∏": " çarpım ", "∫": " integral ", "∞": " sonsuz ", "≈": " yaklaşık eşittir ",
        "≠": " eşit değildir ", "≤": " küçük eşittir ", "≥": " büyük eşittir ",
        "∝": " orantılı ", "∈": " elemanıdır ", "∉": " elemanı değildir ",
        "⊂": " alt kümesidir ", "⊆": " alt kümesi ya da eşittir ",
        "⊃": " kapsar ", "⊇": " kapsar ya da eşittir ",
        "∪": " birleşim ", "∩": " kesişim ", "∖": " fark ", "△": " simetrik fark ",
        "→": " gider ", "∂": " kısmi türev ", "∇": " nabla ", "∅": " boş küme ",
        # Mantık / niceleyiciler
        "∀": " her ", "∃": " vardır ", "∄": " yoktur ", "¬": " değil ",
        "∧": " ve ", "∨": " veya ", "⇒": " ise ", "⇐": " ancak ", "⇔": " ancak ve ancak ",
        "↔": " ancak ve ancak ", "≡": " denktir ", "≪": " çok küçüktür ",
        "≫": " çok büyüktür ", "∴": " o hâlde ", "∵": " çünkü ",
        "∠": " açı ", "⊥": " diktir ", "∥": " paraleldir ", "≅": " eştir ",
        # Sayı kümeleri (matematiksel çift-çizgi harfler)
        "ℝ": " reel sayılar ", "ℕ": " doğal sayılar ", "ℤ": " tam sayılar ",
        "ℚ": " rasyonel sayılar ", "ℂ": " karmaşık sayılar ", "ℙ": " asal sayılar ",
        "+": " artı ", "=": " eşittir ", "<": " küçüktür ", ">": " büyüktür ",
        "°": " derece ", "′": " dakika ", "″": " saniye ",
        # Unicode kesirler
        "½": " yarım ", "⅓": " üçte bir ", "⅔": " üçte iki ", "¼": " çeyrek ",
        "¾": " dörtte üç ", "⅕": " beşte bir ", "⅛": " sekizde bir ",
    }
    math_pattern = re.compile("|".join(re.escape(s) for s in MATH_SYMBOLS))

    def expand_math(text: str) -> str:
        return math_pattern.sub(lambda m: MATH_SYMBOLS[m.group(0)], text)

    rules.append(Rule("matematik", expand_math))

    # -- 14. Kalan düz tam sayılar --------------------------------------------
    int_pattern = re.compile(r"\b\d+\b")

    def expand_ints(text: str) -> str:
        return int_pattern.sub(lambda m: _int_words(int(m.group(0))), text)

    rules.append(Rule("sayi", expand_ints))

    return rules


_RULES = _make_rules()
RULE_NAMES = [r.name for r in _RULES]


# ---------------------------------------------------------------------------
# Genel API
# ---------------------------------------------------------------------------

def normalize_tr(
    text: str, enabled_rules: set[str] | None = None
) -> tuple[str, list[str]]:
    """Metni normalleştirir; (yeni_metin, değişiklik_yapan_kurallar) döndürür.

    URL ve e-postalar tüm kurallardan korunur ve sonunda geri konur.
    """
    # 1. Koruma: URL/e-posta → geçici belirteç.
    # Belirteç rakam/büyük harf İÇERMEMELİ; yoksa sayı/akronim kuralları bozar.
    def _token(i: int) -> str:
        letters = ""
        i += 1
        while i > 0:
            i, r = divmod(i - 1, 26)
            letters = chr(97 + r) + letters
        return f"\x00{letters}\x00"

    protected: list[str] = []

    def stash(m: re.Match) -> str:
        protected.append(m.group(0))
        return _token(len(protected) - 1)

    text = _PROTECT_RE.sub(stash, text)

    applied: list[str] = []
    for rule in _RULES:
        if enabled_rules is not None and rule.name not in enabled_rules:
            continue
        new_text = rule.apply(text)
        if new_text != text:
            applied.append(rule.name)
            text = new_text

    # Geri koy
    for i, original in enumerate(protected):
        text = text.replace(_token(i), original)

    # Boşluk temizliği: sembol kuralları (matematik/yunan) çevrelerine boşluk
    # bırakır — noktalama öncesi boşluğu ve çoklu boşluğu topla, uçları kırp
    # (satır sonlarına dokunma; paragraf \n\n korunur).
    text = re.sub(r"[ \t]+([,.;:!?…])", r"\1", text)
    text = re.sub(r"[ \t]{2,}", " ", text)
    text = re.sub(r"(?m)^[ \t]+|[ \t]+$", "", text)
    return text, applied
