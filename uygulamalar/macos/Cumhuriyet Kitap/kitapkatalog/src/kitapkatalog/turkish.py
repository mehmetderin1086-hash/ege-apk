"""Turkish diacritic-form arbitration, backed by an OCR-observed frequency lexicon.

This module never invents a spelling.  It only chooses between forms that OCR
engines have themselves already produced (for example "GUNES" against
"GÜNEŞ"), and only when asked to — the caller decides whether a choice is
close enough to be genuinely uncertain.  See ``kitapkatalog.consensus`` for
the grapheme-vote arbiter that calls into this module.
"""

from __future__ import annotations

import unicodedata
from collections.abc import Iterable
from dataclasses import dataclass
from functools import lru_cache
from importlib.resources import files

# Turkish casefolding is not plain ``str.casefold()``: uppercase dotless "I"
# lowercases to dotless "ı" (not "i"), and Unicode's own casefold of dotted
# "İ" expands to "i" + a combining dot above rather than plain "i".  Both are
# rewritten explicitly before casefolding the rest of the word.
_DIACRITIC_FOLD = str.maketrans({"ı": "i", "ş": "s", "ç": "c", "ğ": "g", "ö": "o", "ü": "u"})


def _turkish_casefold(word: str) -> str:
    normalized = unicodedata.normalize("NFC", word)
    return normalized.replace("I", "ı").replace("İ", "i").casefold()


def diacritic_key(word: str) -> str:
    """Fold a word to a diacritic-insensitive comparison key.

    "GÜNEŞ", "güneş" and "GUNES" all fold to the same key; distinct base
    words never do (e.g. "sut" and "süt" fold differently only when the
    diacritic itself is the sole difference between two spellings of the
    same word — this key alone cannot and does not decide word identity).
    """

    return _turkish_casefold(word).translate(_DIACRITIC_FOLD)


@dataclass(frozen=True, slots=True)
class TurkishLexicon:
    """A word -> corpus-frequency table used only to break close diacritic ties."""

    frequencies: dict[str, int]

    def prefer_diacritic_form(self, options: Iterable[str]) -> str | None:
        """Return the most frequent of ``options`` that share one diacritic key.

        Returns ``None`` — meaning "no opinion, keep the caller's own
        deterministic choice" — when fewer than two distinct forms are
        given, when they do not all fold to the same diacritic key, or when
        none of them is a known Turkish word.  The result, when not
        ``None``, is always one of the supplied ``options`` verbatim: this
        method never synthesises a form nobody observed.
        """

        candidates = list(dict.fromkeys(options))
        if len(candidates) < 2:
            return None
        if len({diacritic_key(candidate) for candidate in candidates}) != 1:
            return None
        ranked = sorted(
            (
                (self.frequencies[folded], candidate)
                for candidate in candidates
                if (folded := _turkish_casefold(candidate)) in self.frequencies
            ),
            reverse=True,
        )
        return ranked[0][1] if ranked else None


def _parse_frequency_table(text: str) -> dict[str, int]:
    frequencies: dict[str, int] = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        word, _, count = stripped.rpartition(" ")
        if not word:
            continue
        try:
            frequencies[word] = int(count)
        except ValueError:
            continue
    return frequencies


@lru_cache(maxsize=1)
def _load_bundled_frequencies() -> dict[str, int]:
    resource = files("kitapkatalog").joinpath("resources/tr_frequency_50k.txt")
    return _parse_frequency_table(resource.read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def default_turkish_lexicon() -> TurkishLexicon:
    """The bundled OpenSubtitles-derived Turkish frequency lexicon.

    Loading is lazy and cached: most OCR runs never reach a diacritic tie
    close enough to consult it, and callers such as consensus reconciliation
    must not pay disk I/O on every run.  A missing or unreadable resource
    degrades to an empty lexicon (``prefer_diacritic_form`` then always
    returns ``None``) rather than breaking OCR consensus, since this is an
    accuracy refinement, not a required dependency.
    """

    try:
        frequencies = _load_bundled_frequencies()
    except OSError:
        frequencies = {}
    return TurkishLexicon(frequencies=frequencies)


def prefer_diacritic_form(options: Iterable[str]) -> str | None:
    """Convenience wrapper around :func:`default_turkish_lexicon`."""

    return default_turkish_lexicon().prefer_diacritic_form(options)
