from __future__ import annotations

import json

import pytest

from kitapkatalog.calibration import (
    CalibrationError,
    CalibrationSample,
    ConfidenceCalibrationProfile,
    fit_isotonic_profile,
)


def test_isotonic_fit_is_monotonic_and_round_trips(tmp_path) -> None:
    samples = tuple(CalibrationSample(index / 299, index % 5 != 0) for index in range(300))
    profile = fit_isotonic_profile(
        samples,
        version="calibration-set-v1",
        minimum_samples=200,
    )

    probabilities = [item.calibrated_probability for item in profile.bins]
    assert probabilities == sorted(probabilities)
    assert profile.trusted
    assert profile.calibrate(0.0) <= profile.calibrate(0.8)
    path = tmp_path / "ensemble.json"
    path.write_text(
        json.dumps(profile.to_dict(), ensure_ascii=False),
        encoding="utf-8",
    )
    loaded = ConfidenceCalibrationProfile.load(path)
    assert loaded == profile
    assert loaded.digest() == profile.digest()


def test_small_profile_is_not_trusted() -> None:
    profile = fit_isotonic_profile(
        (CalibrationSample(0.9, True), CalibrationSample(0.8, False)),
        version="tiny",
    )
    assert not profile.trusted


def test_profile_save_is_atomic_and_reloadable(tmp_path) -> None:
    profile = fit_isotonic_profile(
        [
            CalibrationSample(0.70, False),
            CalibrationSample(0.99, True),
        ],
        version="atomic-v1",
        minimum_samples=2,
    )
    destination = profile.save(tmp_path / "calibration" / "ensemble.json")
    assert destination.is_file()
    assert ConfidenceCalibrationProfile.load(destination) == profile
    assert not list(destination.parent.glob("*.part"))


def test_repeated_raw_scores_form_one_valid_bin() -> None:
    profile = fit_isotonic_profile(
        [
            CalibrationSample(0.90, True),
            CalibrationSample(0.90, False),
            CalibrationSample(0.99, True),
        ],
        version="duplicates-v1",
        minimum_samples=3,
    )
    assert profile.total_samples == 3
    assert sum(item.sample_count for item in profile.bins) == 3
    assert len({item.upper_bound for item in profile.bins}) == len(profile.bins)


def test_malformed_non_monotonic_profile_is_rejected() -> None:
    with pytest.raises(CalibrationError, match="monoton"):
        ConfidenceCalibrationProfile.from_dict(
            {
                "schema_version": 1,
                "version": "bad",
                "total_samples": 2,
                "bins": [
                    {
                        "upper_bound": 0.5,
                        "calibrated_probability": 0.9,
                        "sample_count": 1,
                    },
                    {
                        "upper_bound": 1.0,
                        "calibrated_probability": 0.1,
                        "sample_count": 1,
                    },
                ],
            }
        )
