"""The closed loop: reviewing books produces the profile that enables auto-accept.

Before this loop existed, `fit-calibration` could only read a file somebody
assembled by hand.  Without that file no field is ever accepted automatically,
which makes a ten-thousand-book catalogue impossible to review.  These tests
pin the loop end to end: review decisions become labels, labels become a
trusted profile, and a trusted profile is what lets consensus accept a span.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from kitapkatalog.calibration import (
    CalibrationSample,
    ReviewLabel,
    fit_isotonic_profile,
    samples_from_reviews,
)
from kitapkatalog.catalog import Catalog
from kitapkatalog.cli import main
from kitapkatalog.database import Database
from kitapkatalog.domain import BookInput, FieldStatus


def _label(observed: str, confirmed: str, confidence: float = 0.9) -> ReviewLabel:
    return ReviewLabel(
        field_path="edition.title",
        raw_confidence=confidence,
        observed_value=observed,
        confirmed_value=confirmed,
    )


def test_a_matching_proposal_is_a_positive_sample() -> None:
    samples = samples_from_reviews([_label("Kürk Mantolu Madonna", "Kürk Mantolu Madonna")])
    assert [sample.correct for sample in samples] == [True]


def test_surrounding_whitespace_and_unicode_form_do_not_change_the_label() -> None:
    # NFD "İ" versus NFC "İ": the same letter, written differently.
    samples = samples_from_reviews([_label("  İstanbul  ", "İstanbul")])
    assert [sample.correct for sample in samples] == [True]


def test_turkish_dotted_and_dotless_i_are_not_folded_together() -> None:
    # Folding case here would label the exact error this catalogue refuses to
    # hide as a correct read.
    samples = samples_from_reviews([_label("ISTANBUL", "İSTANBUL")])
    assert [sample.correct for sample in samples] == [False]


def test_a_replaced_proposal_is_a_negative_sample() -> None:
    samples = samples_from_reviews([_label("Kurk Mantolu Madona", "Kürk Mantolu Madonna")])
    assert [sample.correct for sample in samples] == [False]


def test_confidence_outside_the_unit_interval_is_clamped() -> None:
    samples = samples_from_reviews(
        [_label("A", "A", confidence=1.4), _label("B", "B", confidence=-0.2)]
    )
    assert [sample.raw_confidence for sample in samples] == [1.0, 0.0]


def _reviewed_catalogue(tmp_path: Path, *, books: int) -> Path:
    """Build a catalogue whose fields have been proposed and then reviewed."""

    database_path = tmp_path / "catalog.sqlite3"
    database = Database(database_path)
    catalog = Catalog(database)
    now = "2026-01-01T00:00:00+00:00"
    for index in range(books):
        edition = catalog.save_book(
            BookInput(title=f"Kitap {index}", publisher="Yayınevi", language="tr")
        )
        with database.transaction() as connection:
            # A high-confidence proposal that the user will agree with, and a
            # low-confidence one they will replace.
            for field_path, value, confidence in (
                ("edition.title", f"Kitap {index}", 0.97),
                ("edition.publisher", "Yayinevi", 0.55),
            ):
                connection.execute(
                    """
                    INSERT INTO field_observation (
                        edition_id, field_path, raw_value, normalized_value,
                        confidence, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (edition.edition_id, field_path, value, value, confidence, now),
                )
        catalog.update_book(
            edition.edition_id,
            {"title": f"Kitap {index}", "publisher": "Yayınevi"},
            user_edit=True,
        )
    return database_path


def test_review_labels_only_use_fields_the_user_locked(tmp_path: Path) -> None:
    database_path = _reviewed_catalogue(tmp_path, books=1)
    database = Database(database_path)
    catalog = Catalog(database)
    edition = catalog.list_books(limit=1)[0]
    # An untouched proposal on a field nobody reviewed must not become a label:
    # judging model output with model output calibrates nothing.
    with database.transaction() as connection:
        connection.execute(
            """
            INSERT INTO field_observation (
                edition_id, field_path, raw_value, normalized_value,
                confidence, created_at
            ) VALUES (?, 'edition.subtitle', 'x', 'x', 0.9,
                      '2026-01-01T00:00:00+00:00')
            """,
            (edition.edition_id,),
        )
        connection.execute(
            """
            INSERT INTO resolved_field (
                edition_id, field_path, value, status, user_locked,
                resolver_version, updated_at
            ) VALUES (?, 'edition.subtitle', 'x', ?, 0, 'pipeline',
                      '2026-01-01T00:00:00+00:00')
            """,
            (edition.edition_id, FieldStatus.AUTO.value),
        )

    paths = {row["field_path"] for row in database.review_labels()}

    assert paths == {"edition.title", "edition.publisher"}


def test_review_labels_survive_the_cleared_observation_link(tmp_path: Path) -> None:
    database = Database(_reviewed_catalogue(tmp_path, books=1))
    # A user edit sets resolved_field.observation_id to NULL, so the labels must
    # be matched back by (edition_id, field_path) instead.
    assert (
        database.fetchone("SELECT COUNT(*) AS n FROM resolved_field WHERE observation_id")["n"] == 0
    )

    labels = database.review_labels()

    assert len(labels) == 2
    by_path = {row["field_path"]: row for row in labels}
    assert by_path["edition.title"]["observed_value"] == "Kitap 0"
    assert by_path["edition.publisher"]["observed_value"] == "Yayinevi"
    assert by_path["edition.publisher"]["confirmed_value"] == "Yayınevi"


def test_export_reports_how_far_the_catalogue_is_from_enabling_auto_accept(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    database_path = _reviewed_catalogue(tmp_path, books=3)

    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "export-calibration-samples",
                "--minimum-samples",
                "200",
            ]
        )
        == 0
    )
    payload = json.loads(capsys.readouterr().out)

    assert payload["samples"] == 6
    assert payload["correct"] == 3  # the titles the user agreed with
    assert payload["incorrect"] == 3  # the publisher spelling they replaced
    assert payload["sufficient"] is False
    assert payload["remaining"] == 194
    assert payload["fields"] == {"edition.publisher": 3, "edition.title": 3}


def test_exported_file_is_exactly_what_fit_calibration_consumes(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    database_path = _reviewed_catalogue(tmp_path, books=120)
    destination = tmp_path / "ornekler.jsonl"
    profile_path = tmp_path / "ensemble.json"

    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "export-calibration-samples",
                str(destination),
            ]
        )
        == 0
    )
    export = json.loads(capsys.readouterr().out)
    assert export["samples"] == 240
    assert export["sufficient"] is True

    # The export feeds the existing command unchanged.
    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "fit-calibration",
                str(destination),
                str(profile_path),
                "--version",
                "inceleme-v1",
            ]
        )
        == 0
    )
    fitted = json.loads(capsys.readouterr().out)

    assert fitted["samples"] == 240
    assert fitted["trusted"] is True
    # This is the switch: without a trusted profile no field is ever accepted.
    assert fitted["automatic_acceptance"] is True


def test_a_profile_fitted_from_reviews_separates_the_two_confidence_levels(
    tmp_path: Path,
) -> None:
    database = Database(_reviewed_catalogue(tmp_path, books=120))
    samples = samples_from_reviews([ReviewLabel(**row) for row in database.review_labels()])

    profile = fit_isotonic_profile(samples, version="inceleme-v1", minimum_samples=200)

    assert profile.trusted
    # The 0.55 proposals were always wrong and the 0.97 ones always right, so a
    # monotone fit has to place them at opposite ends.
    assert profile.calibrate(0.55) < profile.calibrate(0.97)
    assert profile.calibrate(0.97) > 0.9


def test_fitting_refuses_a_sample_set_that_is_too_small() -> None:
    samples = [CalibrationSample(raw_confidence=0.9, correct=True) for _ in range(10)]

    profile = fit_isotonic_profile(samples, version="az-ornek", minimum_samples=200)

    # Fitting still succeeds so the operator can inspect it, but the profile is
    # not trusted, which keeps automatic acceptance off.
    assert profile.total_samples == 10
    assert profile.trusted is False


def test_one_review_decision_produces_exactly_one_sample(tmp_path: Path) -> None:
    """The extractor writes an observation for every candidate it weighed.

    A front-cover title and its colophon fallback are two observations for one
    field, but the pipeline only ever proposed the winner. Counting both would
    inflate the trust threshold and feed the curve a losing candidate the user
    was never shown.
    """

    database_path = tmp_path / "catalog.sqlite3"
    database = Database(database_path)
    catalog = Catalog(database)
    edition = catalog.save_book(BookInput(title="Küçük Prens"))
    now = "2026-01-01T00:00:00+00:00"
    with database.transaction() as connection:
        for value, confidence in (("Küçük Prens", 0.97), ("Küçük Prenses", 0.55)):
            connection.execute(
                """
                INSERT INTO field_observation (
                    edition_id, field_path, raw_value, normalized_value,
                    confidence, created_at
                ) VALUES (?, 'edition.title', ?, ?, ?, ?)
                """,
                (edition.edition_id, value, value, confidence, now),
            )
    catalog.update_book(edition.edition_id, {"title": "Küçük Prens"}, user_edit=True)

    labels = database.review_labels()

    assert len(labels) == 1
    # The winner is the observation the resolver would have picked.
    assert labels[0]["observed_value"] == "Küçük Prens"
    assert labels[0]["raw_confidence"] == pytest.approx(0.97)


def test_the_counted_total_matches_the_exported_samples(tmp_path: Path) -> None:
    database = Database(_reviewed_catalogue(tmp_path, books=7))

    # The review screen counts without materialising; the two must not diverge.
    assert database.review_label_count() == len(database.review_labels())


def test_provenance_is_read_from_the_observation_not_assumed(tmp_path: Path) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    database = Database(database_path)
    catalog = Catalog(database)
    edition = catalog.save_book(BookInput(title="Kitap", publisher="Yayınevi"))
    now = "2026-01-01T00:00:00+00:00"
    with database.transaction() as connection:
        connection.execute(
            """
            INSERT INTO field_observation (
                edition_id, field_path, raw_value, normalized_value,
                confidence, source_polygon_json, engine_evidence_json, created_at
            ) VALUES (?, 'edition.title', 'Kitap', 'Kitap', 0.99,
                      '[[1,2],[3,2],[3,4],[1,4]]', '["rapidocr_ppocrv6"]', ?)
            """,
            (edition.edition_id, now),
        )
        connection.execute(
            """
            INSERT INTO field_observation (
                edition_id, field_path, raw_value, normalized_value,
                confidence, source_polygon_json, engine_evidence_json, created_at
            ) VALUES (?, 'edition.publisher', 'Yayınevi', 'Yayınevi', 0.99,
                      NULL, '[]', ?)
            """,
            (edition.edition_id, now),
        )
    catalog.update_book(
        edition.edition_id, {"title": "Kitap", "publisher": "Yayınevi"}, user_edit=True
    )

    by_path = {row["field_path"]: row for row in database.review_labels()}

    assert by_path["edition.title"]["has_visual_provenance"] is True
    assert by_path["edition.title"]["engine_ids"] == ("rapidocr_ppocrv6",)
    # A field with no box on the source photograph must not be reported as
    # covered; the acceptance gate demands full coverage.
    assert by_path["edition.publisher"]["has_visual_provenance"] is False
