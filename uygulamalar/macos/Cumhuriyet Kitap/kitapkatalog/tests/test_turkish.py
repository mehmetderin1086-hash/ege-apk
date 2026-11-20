from __future__ import annotations

from kitapkatalog.turkish import (
    TurkishLexicon,
    default_turkish_lexicon,
    diacritic_key,
    prefer_diacritic_form,
)


def test_diacritic_key_folds_turkish_i_and_dotted_i_correctly() -> None:
    # Python's generic str.casefold() gets Turkish I/İ backwards: "I".casefold()
    # returns "i" (should be dotless "ı") and "İ".casefold() returns "i̇" (an
    # "i" plus a combining dot, not plain "i"). diacritic_key must rewrite
    # both before folding so Turkish words compare correctly regardless of
    # which of the two dotted/dotless letters an OCR engine produced.
    assert diacritic_key("IŞIK") == diacritic_key("ışık")  # "light": dotless I/ı
    assert diacritic_key("İNCE") == diacritic_key("ince")  # "thin": dotted İ/i
    assert diacritic_key("I") == diacritic_key("ı") == diacritic_key("İ") == diacritic_key("i")


def test_diacritic_key_folds_all_turkish_diacritics() -> None:
    assert diacritic_key("GÜNEŞ") == diacritic_key("güneş") == diacritic_key("GUNES")
    assert diacritic_key("ÇALIŞMA") == diacritic_key("calisma")
    assert diacritic_key("ÖĞRENCİ") == diacritic_key("ogrenci")


def test_diacritic_key_does_not_collapse_different_words() -> None:
    assert diacritic_key("GÜNEŞ") != diacritic_key("BULUT")


def test_default_lexicon_prefers_the_correctly_spelled_dictionary_word() -> None:
    lexicon = default_turkish_lexicon()
    assert lexicon.prefer_diacritic_form(["GUNES", "GÜNEŞ"]) == "GÜNEŞ"
    assert lexicon.prefer_diacritic_form(["GÜNEŞ", "GUNES"]) == "GÜNEŞ"


def test_lexicon_returns_none_when_no_option_is_a_known_word() -> None:
    lexicon = TurkishLexicon(frequencies={"güneş": 100})
    assert lexicon.prefer_diacritic_form(["Zzznotaword", "ZZZNOTAWORDX"]) is None


def test_lexicon_returns_none_for_a_single_option() -> None:
    lexicon = TurkishLexicon(frequencies={"güneş": 100})
    assert lexicon.prefer_diacritic_form(["GÜNEŞ"]) is None
    assert lexicon.prefer_diacritic_form([]) is None


def test_lexicon_returns_none_when_options_are_not_diacritic_variants() -> None:
    lexicon = TurkishLexicon(frequencies={"güneş": 100, "bulut": 50})
    assert lexicon.prefer_diacritic_form(["GÜNEŞ", "BULUT"]) is None


def test_lexicon_never_returns_a_form_that_was_not_one_of_the_options() -> None:
    lexicon = TurkishLexicon(frequencies={"süt": 10, "sut": 5})
    for options in (["SUT", "SÜT"], ["SÜT", "SUT"]):
        result = lexicon.prefer_diacritic_form(options)
        assert result is None or result in options


def test_lexicon_picks_the_higher_frequency_form_when_both_are_known_words() -> None:
    lexicon = TurkishLexicon(frequencies={"süt": 10, "sut": 5})
    assert lexicon.prefer_diacritic_form(["SUT", "SÜT"]) == "SÜT"


def test_empty_lexicon_never_overrides_anything() -> None:
    empty = TurkishLexicon(frequencies={})
    assert empty.prefer_diacritic_form(["GUNES", "GÜNEŞ"]) is None


def test_module_level_convenience_function_matches_the_default_lexicon() -> None:
    assert prefer_diacritic_form(["GUNES", "GÜNEŞ"]) == "GÜNEŞ"
