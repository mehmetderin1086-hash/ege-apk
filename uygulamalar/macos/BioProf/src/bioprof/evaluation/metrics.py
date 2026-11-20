from __future__ import annotations

import math
from dataclasses import dataclass
from statistics import fmean
from typing import Any


@dataclass(frozen=True, slots=True)
class AcceptanceThresholds:
    recall_at_20: float = 0.90
    citation_precision: float = 0.95
    unsupported_claim_rate: float = 0.02
    abstention_f1: float = 0.90

    def check(self, metrics: dict[str, float]) -> tuple[bool, list[str]]:
        failures = []
        for key, expected, comparison in (
            ("recall_at_20", self.recall_at_20, "min"),
            ("citation_precision", self.citation_precision, "min"),
            ("unsupported_claim_rate", self.unsupported_claim_rate, "max"),
            ("abstention_f1", self.abstention_f1, "min"),
        ):
            actual = metrics.get(key)
            if actual is None:
                failures.append(f"Eksik metrik: {key}")
            elif comparison == "min" and actual < expected:
                failures.append(f"{key}={actual:.4f}, gereken >= {expected:.4f}")
            elif comparison == "max" and actual > expected:
                failures.append(f"{key}={actual:.4f}, gereken <= {expected:.4f}")
        return not failures, failures


def _dcg(relevances: list[float]) -> float:
    return sum(value / math.log2(index + 2) for index, value in enumerate(relevances))


def evaluate_retrieval(cases: list[dict[str, Any]], *, k: int = 20) -> dict[str, float]:
    """Evaluate ranked chunk/source IDs against one or more relevant IDs per case."""
    recalls: list[float] = []
    reciprocal_ranks: list[float] = []
    ndcgs: list[float] = []
    for case in cases:
        relevant = {str(value) for value in case.get("relevant_ids", [])}
        retrieved = [str(value) for value in case.get("retrieved_ids", [])][:k]
        if not relevant:
            continue
        matched = [value for value in retrieved if value in relevant]
        recalls.append(len(set(matched)) / len(relevant))
        first_rank = next(
            (index for index, value in enumerate(retrieved, start=1) if value in relevant), None
        )
        reciprocal_ranks.append(1.0 / first_rank if first_rank else 0.0)
        gains = [1.0 if value in relevant else 0.0 for value in retrieved]
        ideal = [1.0] * min(len(relevant), k)
        ndcgs.append(_dcg(gains) / _dcg(ideal) if ideal else 0.0)
    return {
        f"recall_at_{k}": fmean(recalls) if recalls else 0.0,
        f"mrr_at_{k}": fmean(reciprocal_ranks) if reciprocal_ranks else 0.0,
        f"ndcg_at_{k}": fmean(ndcgs) if ndcgs else 0.0,
        "case_count": float(len(recalls)),
    }


def evaluate_answers(cases: list[dict[str, Any]]) -> dict[str, float]:
    citation_total = 0
    citation_supported = 0
    claims_total = 0
    unsupported = 0
    true_positive = false_positive = false_negative = 0

    for case in cases:
        citations = list(case.get("citations", []))
        citation_total += len(citations)
        citation_supported += sum(bool(item.get("supports_claim")) for item in citations)
        claims = list(case.get("claims", []))
        claims_total += len(claims)
        unsupported += sum(not bool(item.get("supported")) for item in claims)

        should_abstain = bool(case.get("should_abstain"))
        abstained = bool(case.get("abstained"))
        if should_abstain and abstained:
            true_positive += 1
        elif not should_abstain and abstained:
            false_positive += 1
        elif should_abstain and not abstained:
            false_negative += 1

    precision = citation_supported / citation_total if citation_total else 0.0
    unsupported_rate = unsupported / claims_total if claims_total else 0.0
    abstention_precision = (
        true_positive / (true_positive + false_positive)
        if true_positive + false_positive
        else 0.0
    )
    abstention_recall = (
        true_positive / (true_positive + false_negative)
        if true_positive + false_negative
        else 0.0
    )
    abstention_f1 = (
        2 * abstention_precision * abstention_recall / (abstention_precision + abstention_recall)
        if abstention_precision + abstention_recall
        else 0.0
    )
    return {
        "citation_precision": precision,
        "unsupported_claim_rate": unsupported_rate,
        "abstention_precision": abstention_precision,
        "abstention_recall": abstention_recall,
        "abstention_f1": abstention_f1,
        "case_count": float(len(cases)),
    }

