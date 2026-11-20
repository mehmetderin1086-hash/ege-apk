"""Geometry-aware, Turkish-preserving OCR consensus with full provenance.

This is a compact ROVER-style reconciler:

* tokens are aggregated into each engine's positioned lines,
* lines are clustered spatially (text similarity is used only for unpositioned
  VLM observations),
* the medoid line becomes an alignment backbone,
* every other engine is globally aligned by Unicode grapheme cluster,
* each engine contributes at most one vote per cover/line,
* chosen graphemes retain their source engine/token/index.

Raw confidence values are never averaged.  They only break count ties and feed
an independent-evidence probability with a disagreement penalty.
"""

from __future__ import annotations

import math
import unicodedata
from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass
from difflib import SequenceMatcher

from kitapkatalog.calibration import ConfidenceCalibrationProfile
from kitapkatalog.ocr.contracts import (
    CLASSIC_ENGINE_IDS,
    REQUIRED_ENGINE_IDS,
    EngineOcrResult,
    OcrToken,
    Polygon,
)
from kitapkatalog.turkish import TurkishLexicon, default_turkish_lexicon, diacritic_key

_ENGINE_RELIABILITY: dict[str, float] = {
    "rapidocr_ppocrv6": 0.94,
    "tesseract": 0.93,
    "easyocr": 0.89,
    "paddleocr_vl": 0.90,
    "surya": 0.88,
}
# How much each additional classic engine counts once one has already voted.
# They share the same preprocessed image, so their errors correlate; the vision
# engines read the original and stay at full weight. Deliberately mild: a
# four-of-five Turkish majority must stay automatically acceptable, since
# easyocr's latin model routinely drops Turkish diacritics and demanding
# unanimity would put every Turkish title into review. The empirical value
# belongs in a calibration profile, which reviewing books now produces.
_CORRELATED_EVIDENCE_WEIGHT = 0.75
# Share of the score lost when every recognizer dissents, scaled by the square
# of the dissenting share. Left as it was: it encodes the product decision that
# one dissenting recognizer must not collapse four high-quality agreements.
_DISSENT_PENALTY = 0.08
_ALIGNMENT_CONFUSABLES = str.maketrans(
    {
        "O": "0",
        "o": "0",
        "I": "1",
        "İ": "1",
        "ı": "1",
        "i": "1",
        "l": "1",
        "S": "5",
        "s": "5",
        "B": "8",
        "b": "8",
    }
)


class ConsensusError(RuntimeError):
    """The five-engine output set is incomplete or internally inconsistent."""


@dataclass(frozen=True, slots=True)
class GraphemeSource:
    engine_id: str
    token_ids: tuple[str, ...]
    source_index: int
    source_grapheme: str
    confidence: float
    has_visual_evidence: bool


@dataclass(frozen=True, slots=True)
class ConsensusGrapheme:
    index: int
    value: str
    confidence: float
    sources: tuple[GraphemeSource, ...]

    @property
    def supporting_engines(self) -> tuple[str, ...]:
        return tuple(dict.fromkeys(source.engine_id for source in self.sources))


@dataclass(frozen=True, slots=True)
class ConsensusSpan:
    span_id: str
    text: str
    polygon: Polygon | None
    confidence: float
    supporting_engines: tuple[str, ...]
    classic_visual_evidence: bool
    eligible_for_auto: bool
    graphemes: tuple[ConsensusGrapheme, ...]
    source_token_ids: tuple[str, ...]
    source_polygon: Polygon | None = None
    # True when a close, diacritic-only grapheme tie was resolved by the
    # Turkish frequency lexicon rather than by the usual vote/confidence
    # tie-break. GraphemeSource provenance is unaffected either way — this
    # only flags that the choice between two engine-observed forms leaned on
    # word frequency.
    diacritic_lexicon_applied: bool = False


@dataclass(frozen=True, slots=True)
class ConsensusDocument:
    image_sha256: str
    spans: tuple[ConsensusSpan, ...]
    raw_text: str
    engine_ids: tuple[str, ...]
    five_ocr_complete: bool


@dataclass(frozen=True, slots=True)
class _Unit:
    value: str
    token_ids: tuple[str, ...]
    source_index: int
    confidence: float
    has_visual_evidence: bool


@dataclass(frozen=True, slots=True)
class _Observation:
    engine_id: str
    text: str
    units: tuple[_Unit, ...]
    confidence: float
    polygon: Polygon | None
    token_ids: tuple[str, ...]


type AlignedPair = tuple[int | None, int | None]


def grapheme_clusters(text: str) -> tuple[str, ...]:
    """Split text without separating Turkish combining marks or ZWJ sequences."""

    normalized = unicodedata.normalize("NFC", text)
    clusters: list[str] = []
    current = ""
    join_next = False
    for character in normalized:
        codepoint = ord(character)
        combining = bool(unicodedata.combining(character))
        variation_selector = 0xFE00 <= codepoint <= 0xFE0F
        emoji_modifier = 0x1F3FB <= codepoint <= 0x1F3FF
        if not current:
            current = character
        elif (
            combining or variation_selector or emoji_modifier or join_next or character == "\u200d"
        ):
            current += character
        else:
            clusters.append(current)
            current = character
        join_next = character == "\u200d"
    if current:
        clusters.append(current)
    return tuple(clusters)


def _alignment_key(grapheme: str) -> str:
    return unicodedata.normalize("NFC", grapheme).translate(_ALIGNMENT_CONFUSABLES).casefold()


def _vote_key(grapheme: str) -> str:
    # Intentionally no confusable translation here: O and 0, I and İ remain
    # distinct votes.  Case is also preserved: voting must never silently turn
    # Turkish I/İ/ı/i into one another.
    return unicodedata.normalize("NFC", grapheme)


def align_graphemes(reference: str, candidate: str) -> tuple[AlignedPair, ...]:
    """Needleman-Wunsch global alignment over Unicode grapheme clusters."""

    left = grapheme_clusters(reference)
    right = grapheme_clusters(candidate)
    rows, columns = len(left) + 1, len(right) + 1
    scores = [[0] * columns for _ in range(rows)]
    moves = [[""] * columns for _ in range(rows)]
    for index in range(1, rows):
        scores[index][0] = -index
        moves[index][0] = "up"
    for index in range(1, columns):
        scores[0][index] = -index
        moves[0][index] = "left"
    for i in range(1, rows):
        for j in range(1, columns):
            exact = _alignment_key(left[i - 1]) == _alignment_key(right[j - 1])
            diagonal = scores[i - 1][j - 1] + (3 if exact else -1)
            up = scores[i - 1][j] - 2
            previous = scores[i][j - 1] - 2
            best = max(diagonal, up, previous)
            scores[i][j] = best
            # Stable tie order prefers a character substitution over gaps.
            moves[i][j] = "diag" if diagonal == best else ("up" if up == best else "left")
    aligned: list[AlignedPair] = []
    i, j = len(left), len(right)
    while i or j:
        move = moves[i][j]
        if move == "diag":
            aligned.append((i - 1, j - 1))
            i -= 1
            j -= 1
        elif move == "up":
            aligned.append((i - 1, None))
            i -= 1
        else:
            aligned.append((None, j - 1))
            j -= 1
    aligned.reverse()
    return tuple(aligned)


def _bbox(polygon: Polygon | None) -> tuple[float, float, float, float] | None:
    if not polygon:
        return None
    xs = [point[0] for point in polygon]
    ys = [point[1] for point in polygon]
    return min(xs), min(ys), max(xs), max(ys)


def _union_polygon(polygons: Iterable[Polygon | None]) -> Polygon | None:
    boxes = [box for polygon in polygons if (box := _bbox(polygon)) is not None]
    if not boxes:
        return None
    left = min(box[0] for box in boxes)
    top = min(box[1] for box in boxes)
    right = max(box[2] for box in boxes)
    bottom = max(box[3] for box in boxes)
    return ((left, top), (right, top), (right, bottom), (left, bottom))


def _vertical_overlap(left: tuple[float, ...], right: tuple[float, ...]) -> float:
    overlap = max(0.0, min(left[3], right[3]) - max(left[1], right[1]))
    return overlap / max(1.0, min(left[3] - left[1], right[3] - right[1]))


def _horizontal_overlap(left: tuple[float, ...], right: tuple[float, ...]) -> float:
    overlap = max(0.0, min(left[2], right[2]) - max(left[0], right[0]))
    return overlap / max(1.0, min(left[2] - left[0], right[2] - right[0]))


def _spatial_match(left: _Observation, right: _Observation) -> bool:
    first, second = _bbox(left.polygon), _bbox(right.polygon)
    if first is None or second is None:
        return False
    vertical = _vertical_overlap(first, second)
    horizontal = _horizontal_overlap(first, second)
    first_center = ((first[0] + first[2]) / 2, (first[1] + first[3]) / 2)
    second_center = ((second[0] + second[2]) / 2, (second[1] + second[3]) / 2)
    average_height = max(1.0, ((first[3] - first[1]) + (second[3] - second[1])) / 2)
    horizontal_gap = max(0.0, max(first[0], second[0]) - min(first[2], second[2]))
    center_y_close = abs(first_center[1] - second_center[1]) <= average_height * 0.65
    return (
        vertical >= 0.55
        and center_y_close
        and (horizontal >= 0.15 or horizontal_gap <= average_height * 1.5)
    )


def _text_similarity(left: str, right: str) -> float:
    a = "".join(_alignment_key(value) for value in grapheme_clusters(left) if not value.isspace())
    b = "".join(_alignment_key(value) for value in grapheme_clusters(right) if not value.isspace())
    return SequenceMatcher(None, a, b, autojunk=False).ratio() if a and b else 0.0


def _clusters_share_one_visual_line(
    left: list[_Observation],
    right: list[_Observation],
) -> bool:
    """Return whether two existing clusters can safely be joined as one line.

    A vision model may emit one coarse polygon around several physical lines.
    Such an observation can overlap multiple already-separated classic OCR
    lines.  It must not bridge those lines into one cluster and make the
    one-vote-per-engine deduplicator discard valid text.  Split tokens on the
    *same* line (for example ``Editör:`` and a person's name) still merge
    because their own boxes spatially match.
    """

    return any(_spatial_match(first, second) for first in left for second in right)


def _best_matching_cluster(
    observation: _Observation,
    positioned: list[list[_Observation]],
    matches: list[int],
) -> int:
    """Choose one cluster for a multi-line/coarse observation without bridging."""

    return max(
        matches,
        key=lambda index: (
            max(_text_similarity(observation.text, other.text) for other in positioned[index]),
            max(
                _vertical_overlap(_bbox(observation.polygon), _bbox(other.polygon))
                for other in positioned[index]
                if _bbox(observation.polygon) is not None and _bbox(other.polygon) is not None
            ),
            -index,
        ),
    )


def _line_observations(result: EngineOcrResult) -> tuple[_Observation, ...]:
    grouped: dict[str, list[OcrToken]] = defaultdict(list)
    for token in result.tokens:
        key = token.line_id or token.token_id
        grouped[key].append(token)
    observations: list[_Observation] = []
    for tokens in grouped.values():
        tokens.sort(
            key=lambda token: (
                (_bbox(token.polygon) or (math.inf, math.inf, math.inf, math.inf))[0],
                token.token_id,
            )
        )
        units: list[_Unit] = []
        text_parts: list[str] = []
        source_index = 0
        for token_index, token in enumerate(tokens):
            if token_index:
                text_parts.append(" ")
                units.append(
                    _Unit(
                        value=" ",
                        token_ids=(tokens[token_index - 1].token_id, token.token_id),
                        source_index=source_index,
                        confidence=min(tokens[token_index - 1].confidence, token.confidence),
                        has_visual_evidence=(
                            tokens[token_index - 1].has_visual_evidence
                            and token.has_visual_evidence
                        ),
                    )
                )
                source_index += 1
            text_parts.append(token.text)
            for value in grapheme_clusters(token.text):
                units.append(
                    _Unit(
                        value=value,
                        token_ids=(token.token_id,),
                        source_index=source_index,
                        confidence=token.confidence,
                        has_visual_evidence=token.has_visual_evidence,
                    )
                )
                source_index += 1
        text = "".join(text_parts)
        observations.append(
            _Observation(
                engine_id=result.engine_id,
                text=text,
                units=tuple(units),
                confidence=min((unit.confidence for unit in units), default=0.0),
                polygon=_union_polygon(token.polygon for token in tokens),
                token_ids=tuple(token.token_id for token in tokens),
            )
        )
    return tuple(observations)


def _clusters(results: Iterable[EngineOcrResult]) -> list[list[_Observation]]:
    positioned: list[list[_Observation]] = []
    unpositioned: list[_Observation] = []
    for result in results:
        for observation in _line_observations(result):
            if observation.polygon is None:
                unpositioned.append(observation)
                continue
            matches = [
                index
                for index, cluster in enumerate(positioned)
                if any(
                    other.engine_id != observation.engine_id and _spatial_match(other, observation)
                    for other in cluster
                )
            ]
            if not matches:
                positioned.append([observation])
                continue
            merge_matches = all(
                _clusters_share_one_visual_line(positioned[left], positioned[right])
                for offset, left in enumerate(matches)
                for right in matches[offset + 1 :]
            )
            target = (
                matches[0]
                if merge_matches
                else _best_matching_cluster(observation, positioned, matches)
            )
            positioned[target].append(observation)
            if merge_matches:
                for merge_index in reversed([index for index in matches if index != target]):
                    positioned[target].extend(positioned.pop(merge_index))

    for observation in unpositioned:
        candidates = [
            (
                max(_text_similarity(observation.text, other.text) for other in cluster),
                index,
            )
            for index, cluster in enumerate(positioned)
            if all(other.engine_id != observation.engine_id for other in cluster)
        ]
        score, index = max(candidates, default=(0.0, -1))
        if score >= 0.55:
            positioned[index].append(observation)
        else:
            positioned.append([observation])
    return positioned


def _deduplicate_engine_votes(cluster: list[_Observation]) -> tuple[_Observation, ...]:
    by_engine: dict[str, list[_Observation]] = defaultdict(list)
    for observation in cluster:
        by_engine[observation.engine_id].append(observation)
    chosen: list[_Observation] = []
    for engine_id, alternatives in by_engine.items():
        if len(alternatives) == 1:
            chosen.append(alternatives[0])
            continue
        others = [item for item in cluster if item.engine_id != engine_id]
        chosen.append(
            max(
                alternatives,
                key=lambda item: (
                    sum(_text_similarity(item.text, other.text) for other in others),
                    item.confidence,
                    len(item.text),
                ),
            )
        )
    order = {engine_id: index for index, engine_id in enumerate(REQUIRED_ENGINE_IDS)}
    chosen.sort(key=lambda item: order[item.engine_id])
    return tuple(chosen)


def _choose_anchor(observations: tuple[_Observation, ...]) -> _Observation:
    classics = [item for item in observations if item.engine_id in CLASSIC_ENGINE_IDS]
    pool = classics or list(observations)
    return max(
        pool,
        key=lambda item: (
            sum(_text_similarity(item.text, other.text) for other in observations),
            item.confidence,
            -REQUIRED_ENGINE_IDS.index(item.engine_id),
        ),
    )


def _source(observation: _Observation, index: int) -> GraphemeSource:
    unit = observation.units[index]
    return GraphemeSource(
        engine_id=observation.engine_id,
        token_ids=unit.token_ids,
        source_index=unit.source_index,
        source_grapheme=unit.value,
        confidence=unit.confidence,
        has_visual_evidence=unit.has_visual_evidence,
    )


def _independent_confidence(sources: Iterable[GraphemeSource], dissent: int) -> float:
    sources_tuple = tuple(sources)
    probability_wrong = 1.0
    classic_seen = 0
    for source in sources_tuple:
        reliability = _ENGINE_RELIABILITY.get(source.engine_id, 0.85)
        calibrated = max(0.05, min(0.995, source.confidence * reliability))
        if source.engine_id in CLASSIC_ENGINE_IDS:
            # The three classic engines read the same canonical/CLAHE image, so
            # they fail together on glare, blur and stylised type. Treating each
            # extra one as fully independent multiplies away a shared error and
            # produces confidences near certainty on covers all three misread.
            classic_seen += 1
            if classic_seen > 1:
                calibrated *= _CORRELATED_EVIDENCE_WEIGHT ** (classic_seen - 1)
        probability_wrong *= 1.0 - calibrated
    probability = 1.0 - probability_wrong
    total = len(sources_tuple) + dissent
    if total:
        # A single dissenting recognizer must not collapse four independent,
        # high-quality agreements below the auto threshold; sustained
        # disagreement still compounds quickly.
        probability *= 1.0 - _DISSENT_PENALTY * (dissent / total) ** 2
    return max(0.0, min(0.9999, probability))


@dataclass(frozen=True, slots=True)
class _VoteOutcome:
    value: str
    sources: tuple[GraphemeSource, ...]
    confidence: float
    support: int
    # The second-ranked group, if any — kept only so a later, word-level pass
    # can consider deferring to it; it is never used unless that pass finds a
    # close, diacritic-only tie with lexicon support for the swap.
    runner_up_value: str | None
    runner_up_sources: tuple[GraphemeSource, ...]
    runner_up_confidence: float
    runner_up_support: int


def _winning_sources(
    sources: list[GraphemeSource],
    *,
    deletion_count: int = 0,
) -> _VoteOutcome | None:
    groups: dict[str, list[GraphemeSource]] = defaultdict(list)
    for source in sources:
        groups[_vote_key(source.source_grapheme)].append(source)
    if not groups:
        return None
    ranked = sorted(
        groups.values(),
        key=lambda group: (
            len({source.engine_id for source in group}),
            sum(
                source.confidence * _ENGINE_RELIABILITY.get(source.engine_id, 0.85)
                for source in group
            ),
            any(source.engine_id in CLASSIC_ENGINE_IDS for source in group),
        ),
        reverse=True,
    )
    winner = ranked[0]
    supporting = len({source.engine_id for source in winner})
    if deletion_count > supporting:
        return None

    def representative_of(group: list[GraphemeSource]) -> GraphemeSource:
        return max(
            group,
            key=lambda source: (
                source.confidence * _ENGINE_RELIABILITY.get(source.engine_id, 0.85),
                source.engine_id in CLASSIC_ENGINE_IDS,
                -REQUIRED_ENGINE_IDS.index(source.engine_id),
            ),
        )

    dissent = sum(len(group) for group in ranked[1:]) + deletion_count
    runner_up_value: str | None = None
    runner_up_sources: tuple[GraphemeSource, ...] = ()
    runner_up_confidence = 0.0
    runner_up_support = 0
    if len(ranked) > 1:
        runner_up_group = ranked[1]
        runner_up_support = len({source.engine_id for source in runner_up_group})
        runner_up_value = representative_of(runner_up_group).source_grapheme
        runner_up_sources = tuple(runner_up_group)
        runner_up_dissent = (len(sources) - len(runner_up_group)) + deletion_count
        runner_up_confidence = _independent_confidence(runner_up_group, runner_up_dissent)
    return _VoteOutcome(
        value=representative_of(winner).source_grapheme,
        sources=tuple(winner),
        confidence=_independent_confidence(winner, dissent),
        support=supporting,
        runner_up_value=runner_up_value,
        runner_up_sources=runner_up_sources,
        runner_up_confidence=runner_up_confidence,
        runner_up_support=runner_up_support,
    )


# A grapheme-position tie this close is a genuine coin flip between two forms
# engines actually produced; anything wider already has a clear winner and
# the lexicon should not second-guess it.
_DIACRITIC_TIE_MARGIN = 1


def _word_ranges(
    emitted: list[tuple[str, tuple[GraphemeSource, ...], float]],
) -> list[tuple[int, int]]:
    """Contiguous non-whitespace index ranges in an emitted grapheme list."""

    ranges: list[tuple[int, int]] = []
    start: int | None = None
    for index, (value, _sources, _confidence) in enumerate(emitted):
        if value.isspace():
            if start is not None:
                ranges.append((start, index))
                start = None
        elif start is None:
            start = index
    if start is not None:
        ranges.append((start, len(emitted)))
    return ranges


def _apply_diacritic_lexicon(
    emitted: list[tuple[str, tuple[GraphemeSource, ...], float]],
    position_outcomes: dict[int, _VoteOutcome],
    lexicon: TurkishLexicon,
) -> tuple[list[tuple[str, tuple[GraphemeSource, ...], float]], bool]:
    """Let a close, diacritic-only grapheme tie defer to Turkish word frequency.

    Only positions whose top two vote groups differ solely by a Turkish
    diacritic and are separated by at most ``_DIACRITIC_TIE_MARGIN``
    supporting engines are reconsidered. The replacement value, sources and
    confidence always come from that position's own runner-up group — an
    alternative every engine involved already produced — so provenance is
    exactly as trustworthy as the original winner's would have been.
    """

    result = list(emitted)
    applied = False
    for start, end in _word_ranges(result):
        swaps: dict[int, _VoteOutcome] = {}
        for index in range(start, end):
            outcome = position_outcomes.get(index)
            if outcome is None or outcome.runner_up_value is None:
                continue
            current_value = result[index][0]
            if current_value == outcome.runner_up_value:
                continue
            if abs(outcome.support - outcome.runner_up_support) > _DIACRITIC_TIE_MARGIN:
                continue
            if diacritic_key(current_value) != diacritic_key(outcome.runner_up_value):
                continue
            swaps[index] = outcome
        if not swaps:
            continue
        current_word = "".join(result[index][0] for index in range(start, end))
        alternate_word = "".join(
            swaps[index].runner_up_value if index in swaps else result[index][0]
            for index in range(start, end)
        )
        preferred = lexicon.prefer_diacritic_form([current_word, alternate_word])
        if preferred != alternate_word:
            continue
        for index, outcome in swaps.items():
            result[index] = (
                outcome.runner_up_value,
                outcome.runner_up_sources,
                outcome.runner_up_confidence,
            )
        applied = True
    return result, applied


def _reconcile_cluster(
    cluster: list[_Observation],
    span_index: int,
    *,
    auto_confidence: float,
    calibration_profile: ConfidenceCalibrationProfile | None,
    lexicon: TurkishLexicon | None = None,
) -> ConsensusSpan:
    observations = _deduplicate_engine_votes(cluster)
    anchor = _choose_anchor(observations)
    anchor_length = len(anchor.units)
    position_votes: dict[int, list[GraphemeSource]] = defaultdict(list)
    deletion_votes: dict[int, int] = defaultdict(int)
    insertion_votes: dict[int, dict[str, list[GraphemeSource]]] = defaultdict(
        lambda: defaultdict(list)
    )
    position_votes.update({index: [_source(anchor, index)] for index in range(anchor_length)})

    for observation in observations:
        if observation is anchor:
            continue
        aligned = align_graphemes(anchor.text, observation.text)
        current_gap = 0
        insertion_ordinals: dict[int, int] = defaultdict(int)
        mapped_anchor: set[int] = set()
        for anchor_index, candidate_index in aligned:
            if anchor_index is not None:
                current_gap = anchor_index
                mapped_anchor.add(anchor_index)
                if candidate_index is None:
                    deletion_votes[anchor_index] += 1
                else:
                    position_votes[anchor_index].append(_source(observation, candidate_index))
                current_gap = anchor_index + 1
            elif candidate_index is not None:
                ordinal = insertion_ordinals[current_gap]
                insertion_ordinals[current_gap] += 1
                insertion_votes[current_gap][str(ordinal)].append(
                    _source(observation, candidate_index)
                )
        for index in range(anchor_length):
            if index not in mapped_anchor:
                deletion_votes[index] += 1

    emitted: list[tuple[str, tuple[GraphemeSource, ...], float]] = []
    # Only position votes (not insertions) are eligible for the diacritic
    # lexicon pass below: an inserted grapheme has no anchor-backed runner-up
    # to defer to.
    position_outcomes: dict[int, _VoteOutcome] = {}
    for gap in range(anchor_length + 1):
        for ordinal in sorted(insertion_votes.get(gap, {}), key=int):
            sources = insertion_votes[gap][ordinal]
            absent = len(observations) - len({source.engine_id for source in sources})
            winning = _winning_sources(sources, deletion_count=absent)
            if winning is not None and len({source.engine_id for source in winning.sources}) >= 2:
                emitted.append((winning.value, winning.sources, winning.confidence))
        if gap < anchor_length:
            winning = _winning_sources(
                position_votes[gap],
                deletion_count=deletion_votes.get(gap, 0),
            )
            if winning is not None:
                emitted.append((winning.value, winning.sources, winning.confidence))
                if lexicon is not None and winning.runner_up_value is not None:
                    position_outcomes[len(emitted) - 1] = winning

    diacritic_lexicon_applied = False
    if lexicon is not None and position_outcomes:
        emitted, diacritic_lexicon_applied = _apply_diacritic_lexicon(
            emitted, position_outcomes, lexicon
        )

    graphemes = tuple(
        ConsensusGrapheme(index=index, value=value, confidence=confidence, sources=sources)
        for index, (value, sources, confidence) in enumerate(emitted)
    )
    text = "".join(item.value for item in graphemes)
    engine_sets = [
        {source.engine_id for source in item.sources}
        for item in graphemes
        if not item.value.isspace()
    ]
    all_support = set().union(*engine_sets) if engine_sets else set()
    classic_visual = all(
        any(
            source.engine_id in CLASSIC_ENGINE_IDS and source.has_visual_evidence
            for source in item.sources
        )
        for item in graphemes
        if not item.value.isspace()
    )
    minimum_support = min((len(values) for values in engine_sets), default=0)
    raw_confidence = min(
        (item.confidence for item in graphemes if not item.value.isspace()),
        default=0.0,
    )
    calibration_trusted = bool(calibration_profile is not None and calibration_profile.trusted)
    confidence = (
        calibration_profile.calibrate(raw_confidence)
        if calibration_trusted and calibration_profile is not None
        else min(raw_confidence, math.nextafter(auto_confidence, 0.0))
    )
    source_token_ids = tuple(
        dict.fromkeys(
            token_id
            for item in graphemes
            for source in item.sources
            for token_id in source.token_ids
        )
    )
    return ConsensusSpan(
        span_id=f"span:{span_index}",
        text=text,
        polygon=_union_polygon(observation.polygon for observation in observations),
        confidence=confidence,
        supporting_engines=tuple(
            engine_id for engine_id in REQUIRED_ENGINE_IDS if engine_id in all_support
        ),
        classic_visual_evidence=classic_visual,
        eligible_for_auto=(
            bool(text.strip())
            and calibration_trusted
            and classic_visual
            and minimum_support >= 2
            and confidence >= auto_confidence
        ),
        graphemes=graphemes,
        source_token_ids=source_token_ids,
        diacritic_lexicon_applied=diacritic_lexicon_applied,
    )


class _UseDefaultLexicon:
    """Sentinel: resolve to :func:`default_turkish_lexicon` lazily, on first use.

    ``None`` is a distinct, valid value for ``lexicon`` (diacritic
    arbitration explicitly off); this sentinel lets the parameter default to
    "load the bundled lexicon" without paying for that load at import time or
    on every call that does pass an explicit lexicon.
    """


_USE_DEFAULT_LEXICON = _UseDefaultLexicon()


def reconcile_results(
    results: Iterable[EngineOcrResult],
    *,
    require_all_five: bool = True,
    auto_confidence: float = 0.98,
    calibration_profile: ConfidenceCalibrationProfile | None = None,
    lexicon: TurkishLexicon | _UseDefaultLexicon | None = _USE_DEFAULT_LEXICON,
) -> ConsensusDocument:
    if not 0.0 <= auto_confidence <= 1.0:
        raise ValueError("Otomatik kabul eşiği 0 ile 1 arasında olmalıdır")
    resolved_lexicon = (
        default_turkish_lexicon() if lexicon is _USE_DEFAULT_LEXICON else lexicon
    )
    supplied_results = tuple(results)
    engine_ids = [result.engine_id for result in supplied_results]
    duplicate_ids = sorted(
        {engine_id for engine_id in engine_ids if engine_ids.count(engine_id) > 1}
    )
    if duplicate_ids:
        raise ConsensusError(
            f"Motor başına yalnız bir oy kabul edilir; yinelenen: {', '.join(duplicate_ids)}"
        )
    missing = sorted(set(REQUIRED_ENGINE_IDS) - set(engine_ids))
    extra = sorted(set(engine_ids) - set(REQUIRED_ENGINE_IDS))
    if require_all_five and (missing or extra or len(supplied_results) != 5):
        detail: list[str] = []
        if missing:
            detail.append(f"eksik: {', '.join(missing)}")
        if extra:
            detail.append(f"bilinmeyen: {', '.join(extra)}")
        raise ConsensusError(
            "Beş zorunlu motor tamamlanmadan uzlaştırma yapılamaz"
            + (f" ({'; '.join(detail)})" if detail else "")
        )
    # Clustering is incremental, so caller/worker completion order must never
    # change the catalog text.  Normalize every complete ensemble to the
    # contract's canonical engine order before any spatial observations are
    # joined.  Unknown engines are kept stable at the end for the optional
    # partial/debug path; the production five-engine path rejects them above.
    engine_order = {engine_id: index for index, engine_id in enumerate(REQUIRED_ENGINE_IDS)}
    result_tuple = tuple(
        item[1]
        for item in sorted(
            enumerate(supplied_results),
            key=lambda item: (
                engine_order.get(item[1].engine_id, len(engine_order)),
                item[0],
            ),
        )
    )
    image_hashes = {result.image_sha256 for result in result_tuple}
    if len(image_hashes) != 1:
        raise ConsensusError("OCR sonuçları aynı kanonik görüntüye ait değil")
    for result in result_tuple:
        if result.engine_id in CLASSIC_ENGINE_IDS and any(
            token.polygon is None for token in result.tokens
        ):
            raise ConsensusError(
                f"{result.engine_id} konumlandırılmamış klasik OCR tokenı döndürdü"
            )

    clusters = _clusters(result_tuple)
    spans = [
        _reconcile_cluster(
            cluster,
            index,
            auto_confidence=auto_confidence,
            calibration_profile=calibration_profile,
            lexicon=resolved_lexicon,
        )
        for index, cluster in enumerate(clusters)
    ]
    spans.sort(
        key=lambda span: (
            (_bbox(span.polygon) or (math.inf, math.inf, math.inf, math.inf))[1],
            (_bbox(span.polygon) or (math.inf, math.inf, math.inf, math.inf))[0],
            span.span_id,
        )
    )
    return ConsensusDocument(
        image_sha256=next(iter(image_hashes), ""),
        spans=tuple(spans),
        raw_text="\n".join(span.text for span in spans if span.text.strip()),
        engine_ids=tuple(
            engine_id for engine_id in REQUIRED_ENGINE_IDS if engine_id in set(engine_ids)
        ),
        five_ocr_complete=set(engine_ids) == set(REQUIRED_ENGINE_IDS) and len(result_tuple) == 5,
    )
