from __future__ import annotations

import pytest

from kitapkatalog.extractor import (
    _TITLE_CEILING_AMBIGUOUS,
    _TITLE_CEILING_DOMINANT,
    EvidenceBoundExtractor,
    EvidenceToken,
    LlamaFieldClient,
    _evidence_form,
    _line_text,
    _title_layout_ceiling,
)


def token(
    token_id: str,
    text: str,
    *,
    cover: str,
    line: int,
    confidence: float = 0.99,
    height: float = 0.05,
    top: float = 0.1,
) -> EvidenceToken:
    return EvidenceToken(
        token_id=token_id,
        text=text,
        cover=cover,
        line_index=line,
        confidence=confidence,
        polygon=((0.1, top), (0.9, top), (0.9, top + height), (0.1, top + height)),
    )


def test_deterministic_fields_stay_grounded() -> None:
    tokens = [
        token("t1", "Tutunamayanlar", cover="front", line=0, height=0.2),
        token("t2", "İletişim Yayınları", cover="front", line=1),
        token("t3", "ISBN 978-975-05-0001-1", cover="back", line=2),
        token("t4", "Fiyat: 250 TL", cover="back", line=3),
    ]
    result = EvidenceBoundExtractor().extract(tokens)
    values = {(field.field_name, field.value) for field in result.fields}
    assert ("title", "Tutunamayanlar") in values
    assert ("publisher", "İletişim Yayınları") in values
    assert ("printed_price", "250 TL") in values
    assert all(field.evidence_token_ids for field in result.fields)


def test_model_hallucination_is_rejected() -> None:
    class FakeModel:
        def extract(self, _tokens):
            return [
                {
                    "field_name": "author",
                    "value": "Olmayan Yazar",
                    "evidence_token_ids": ["t1"],
                    "confidence": 0.999,
                }
            ]

    tokens = [token("t1", "Gerçek Başlık", cover="front", line=0)]
    result = EvidenceBoundExtractor(FakeModel()).extract(tokens)
    assert result.rejected_model_fields
    assert all(field.value != "Olmayan Yazar" for field in result.fields)


def test_turkish_characters_are_preserved() -> None:
    tokens = [token("t1", "İçimizdeki Şeytan", cover="front", line=0)]
    result = EvidenceBoundExtractor().extract(tokens)
    title = next(field for field in result.fields if field.field_name == "title")
    assert title.value == "İçimizdeki Şeytan"


def test_multiline_front_title_excludes_editor_metadata() -> None:
    tokens = [
        # The first token deliberately has a coarse Surya-like box spanning
        # the following title lines.
        token(
            "f1",
            "Türkiye'nin",
            cover="front",
            line=0,
            confidence=0.98,
            height=0.18,
            top=0.55,
        ),
        token(
            "f2",
            "Bütün",
            cover="front",
            line=1,
            confidence=0.98,
            height=0.08,
            top=0.64,
        ),
        token(
            "f3",
            "Ağaçları ve Çalıları",
            cover="front",
            line=2,
            confidence=0.86,
            height=0.11,
            top=0.70,
        ),
        token(
            "f4",
            "Editör: Prof. Dr. Ünal Akkemik",
            cover="front",
            line=3,
            confidence=0.98,
            height=0.06,
            top=0.80,
        ),
        token(
            "f5",
            "Kültür Yayınları",
            cover="front",
            line=4,
            confidence=0.98,
            height=0.05,
            top=0.94,
        ),
    ]

    result = EvidenceBoundExtractor().extract(tokens)
    title = next(field for field in result.fields if field.field_name == "title")

    assert title.value == "Türkiye'nin Bütün Ağaçları ve Çalıları"
    assert title.evidence_token_ids == ("f1", "f2", "f3")
    assert "Ünal Akkemik" not in title.value


def test_front_inside_heading_safely_extends_incomplete_front_title() -> None:
    tokens = [
        token(
            "front",
            "Kayıp Zaman",
            cover="front",
            line=0,
            confidence=0.89,
            height=0.20,
        ),
        token(
            "inside",
            "Kayıp Zamanın İzinde",
            cover="front_inside",
            line=0,
            confidence=0.87,
        ),
        token(
            "copyright",
            "© Örnek Yayınları, 2024",
            cover="front_inside",
            line=1,
            confidence=0.99,
        ),
    ]

    result = EvidenceBoundExtractor().extract(tokens)
    titles = [field for field in result.fields if field.field_name == "title"]

    assert [(field.value, field.evidence_token_ids) for field in titles] == [
        ("Kayıp Zamanın İzinde", ("inside",))
    ]


def test_bare_kitap_word_does_not_create_publisher() -> None:
    tokens = [
        token(
            "sentence",
            "Niteliğinde olan bu kitap, doğaseverlerin hizmetine sunuluyor.",
            cover="back",
            line=0,
        )
    ]

    result = EvidenceBoundExtractor().extract(tokens)

    assert all(field.field_name != "publisher" for field in result.fields)


def test_inner_surfaces_extract_colophon_and_physical_fields() -> None:
    tokens = [
        token("fi1", "Basım yeri: İstanbul", cover="front_inside", line=0),
        token("fi2", "3. Baskı, 2024", cover="front_inside", line=1),
        token("fi3", "Matbaa: Örnek Basım A.Ş.", cover="front_inside", line=2),
        token("bi1", "Toplam 384 sayfa", cover="back_inside", line=0),
        token("bi2", "13,5 x 21 cm", cover="back_inside", line=1),
    ]

    result = EvidenceBoundExtractor().extract(tokens)
    values = {(field.field_name, field.value) for field in result.fields}

    assert ("publication_place", "İstanbul") in values
    assert ("publication_date", "2024") in values
    assert ("printing_number", "3") in values
    assert ("printer", "Örnek Basım A.Ş.") in values
    assert ("page_count", "384") in values
    assert ("dimensions", "13,5 x 21 cm") in values


def test_kunye_labels_extract_publisher_translator_and_editor() -> None:
    tokens = [
        token("fi1", "Yayınevi: Yapı Kredi Yayınları", cover="front_inside", line=0),
        token("fi2", "Çeviren: Ahmet Yılmaz", cover="front_inside", line=1),
        token("bi1", "Editör: Ayşe Demir", cover="back_inside", line=0),
    ]
    result = EvidenceBoundExtractor().extract(tokens)
    values = {(field.field_name, field.value) for field in result.fields}
    assert ("publisher", "Yapı Kredi Yayınları") in values
    assert ("contributor.translator", "Ahmet Yılmaz") in values
    assert ("contributor.editor", "Ayşe Demir") in values


def test_kunye_labels_extract_cover_designer_and_editorial_director_as_other() -> None:
    tokens = [
        token("fi1", "Kapak Tasarımı: Zeynep Kaya", cover="front_inside", line=0),
        token("bi1", "Yayın Yönetmeni: Mehmet Öz", cover="back_inside", line=0),
    ]
    result = EvidenceBoundExtractor().extract(tokens)
    values = {(field.field_name, field.value) for field in result.fields}
    assert ("contributor.other", "Zeynep Kaya") in values
    assert ("contributor.other", "Mehmet Öz") in values


def test_kunye_label_extracts_edition_statement_without_a_leading_digit() -> None:
    # "3. Baskı" style is already covered by _EDITION_RE; this label-first
    # form ("Baskı: <değer>") is the gap _kunye_fields closes.
    tokens = [token("fi1", "Baskı: Üçüncü Basım", cover="front_inside", line=0)]
    result = EvidenceBoundExtractor().extract(tokens)
    values = {(field.field_name, field.value) for field in result.fields}
    assert ("edition_statement", "Üçüncü Basım") in values


def test_kunye_certificate_number_is_recognised_but_not_extracted() -> None:
    tokens = [token("bi1", "Sertifika No: 45678", cover="back_inside", line=0)]
    result = EvidenceBoundExtractor().extract(tokens)
    assert all(field.value != "45678" for field in result.fields)


def test_kunye_value_without_a_label_is_not_extracted() -> None:
    tokens = [token("fi1", "Zeynep Kaya", cover="front_inside", line=0)]
    result = EvidenceBoundExtractor().extract(tokens)
    assert all(field.field_name != "contributor.other" for field in result.fields)


def test_kunye_translator_line_does_not_override_the_existing_role_rule() -> None:
    tokens = [token("fi1", "Çeviren: Ahmet Yılmaz", cover="front_inside", line=0)]
    result = EvidenceBoundExtractor().extract(tokens)
    translator_fields = [f for f in result.fields if f.field_name == "contributor.translator"]
    assert len(translator_fields) == 1
    assert translator_fields[0].value == "Ahmet Yılmaz"
    # The pre-existing role-label rule ran first and wins the tie, so the new
    # colophon helper must not have introduced a second, competing entry.
    assert translator_fields[0].source == "rule:translator"


def test_bottom_folio_on_back_inside_is_review_only_page_count() -> None:
    tokens = [
        token(
            "index-number",
            "1309",
            cover="back_inside",
            line=0,
            confidence=0.99,
            top=0.55,
        ),
        token(
            "last-page",
            "1362",
            cover="back_inside",
            line=1,
            confidence=0.99,
            top=0.94,
        ),
        token(
            "back-number",
            "9999",
            cover="back",
            line=0,
            confidence=0.99,
            top=0.99,
        ),
    ]

    result = EvidenceBoundExtractor().extract(tokens)
    page_counts = [field for field in result.fields if field.field_name == "page_count"]

    assert len(page_counts) == 1
    assert page_counts[0].value == "1362"
    assert page_counts[0].evidence_token_ids == ("last-page",)
    assert page_counts[0].source == "layout:back-inside-final-page-number"
    assert page_counts[0].status == "review"
    assert page_counts[0].confidence < 0.98


def test_model_physical_fields_require_back_inside_role_and_matching_syntax() -> None:
    class PhysicalFieldModel:
        def extract(self, _tokens):
            return [
                {
                    "field_name": "page_count",
                    "value": "4996",
                    "evidence_token_ids": ["publication-number"],
                    "confidence": 0.99,
                },
                {
                    "field_name": "page_count",
                    "value": "384",
                    "evidence_token_ids": ["wrong-page-role"],
                    "confidence": 0.99,
                },
                {
                    "field_name": "dimensions",
                    "value": '9"786254"051722',
                    "evidence_token_ids": ["barcode"],
                    "confidence": 0.99,
                },
                {
                    "field_name": "dimensions",
                    "value": "13,5 x 21 cm",
                    "evidence_token_ids": ["wrong-dimension-role"],
                    "confidence": 0.99,
                },
                {
                    "field_name": "page_count",
                    "value": "384",
                    "evidence_token_ids": ["valid-page"],
                    "confidence": 0.99,
                },
                {
                    "field_name": "dimensions",
                    "value": "13,5 x 21 cm",
                    "evidence_token_ids": ["valid-dimensions"],
                    "confidence": 0.99,
                },
            ]

    result = EvidenceBoundExtractor(PhysicalFieldModel()).extract(
        [
            token(
                "publication-number",
                "Genel Yayın: 4996",
                cover="back_inside",
                line=0,
            ),
            token(
                "wrong-page-role",
                "384 sayfa",
                cover="front_inside",
                line=1,
            ),
            token(
                "barcode",
                '9"786254"051722',
                cover="back_inside",
                line=2,
            ),
            token(
                "wrong-dimension-role",
                "13,5 x 21 cm",
                cover="front_inside",
                line=3,
            ),
            token(
                "valid-page",
                "Toplam 384 sayfa",
                cover="back_inside",
                line=4,
            ),
            token(
                "valid-dimensions",
                "13,5 x 21 cm",
                cover="back_inside",
                line=5,
            ),
        ]
    )

    rejected_ids = {
        tuple(candidate["evidence_token_ids"]) for candidate in result.rejected_model_fields
    }
    assert rejected_ids == {
        ("publication-number",),
        ("wrong-page-role",),
        ("barcode",),
        ("wrong-dimension-role",),
    }
    values = {(field.field_name, field.value) for field in result.fields}
    assert ("page_count", "384") in values
    assert ("dimensions", "13,5 x 21 cm") in values


def test_model_cannot_ground_a_value_as_a_sparse_subsequence() -> None:
    class SparseModel:
        def extract(self, _tokens):
            return [
                {
                    "field_name": "title",
                    "value": "Kt",
                    "evidence_token_ids": ["t1"],
                    "confidence": 0.999,
                }
            ]

    result = EvidenceBoundExtractor(SparseModel()).extract(
        [token("t1", "Kitap", cover="front", line=0)]
    )
    assert result.rejected_model_fields
    assert all(field.value != "Kt" for field in result.fields)


def test_model_evidence_must_stay_on_one_cover() -> None:
    class CrossCoverModel:
        def extract(self, _tokens):
            return [
                {
                    "field_name": "title",
                    "value": "ÖnArka",
                    "evidence_token_ids": ["front", "back"],
                    "confidence": 0.999,
                }
            ]

    result = EvidenceBoundExtractor(CrossCoverModel()).extract(
        [
            token("front", "Ön", cover="front", line=0),
            token("back", "Arka", cover="back", line=0),
        ]
    )
    assert result.rejected_model_fields
    assert all(field.value != "ÖnArka" for field in result.fields)


def test_model_supports_illustrator_and_visible_other_contributor_roles() -> None:
    class RoleModel:
        def extract(self, _tokens):
            return [
                {
                    "field_name": "contributor.illustrator",
                    "value": "Sadi Güran",
                    "evidence_token_ids": ["t1"],
                    "confidence": 0.99,
                },
                {
                    "field_name": "contributor.foreword",
                    "value": "Önsöz Yazarı",
                    "evidence_token_ids": ["t2"],
                    "confidence": 0.99,
                },
            ]

    result = EvidenceBoundExtractor(RoleModel()).extract(
        [
            token("t1", "Çizer: Sadi Güran", cover="back", line=0),
            token("t2", "Önsöz Yazarı", cover="back", line=1),
        ]
    )
    values = {(field.field_name, field.value) for field in result.fields}
    assert ("contributor.illustrator", "Sadi Güran") in values
    assert ("contributor.foreword", "Önsöz Yazarı") in values


def test_model_rejects_grounded_but_semantically_wrong_publisher_and_role() -> None:
    class MislabelledModel:
        def extract(self, _tokens):
            return [
                {
                    "field_name": "publisher",
                    "value": "Türkiye'nin Bütün Ağaçları ve Çalıları",
                    "evidence_token_ids": ["title", "publisher"],
                    "confidence": 0.99,
                },
                {
                    "field_name": "contributor.translator",
                    "value": "Prof. Dr. Ünal Akkemik",
                    "evidence_token_ids": ["editor"],
                    "confidence": 0.99,
                },
            ]

    result = EvidenceBoundExtractor(MislabelledModel()).extract(
        [
            token(
                "title",
                "Türkiye'nin Bütün Ağaçları ve Çalıları",
                cover="front",
                line=0,
            ),
            token(
                "editor",
                "Editör: Prof. Dr. Ünal Akkemik",
                cover="front",
                line=1,
            ),
            token(
                "publisher",
                "Türkiye İş Bankası Kültür Yayınları",
                cover="front",
                line=2,
            ),
        ]
    )

    values = {(field.field_name, field.value) for field in result.fields}
    assert (
        "publisher",
        "Türkiye'nin Bütün Ağaçları ve Çalıları",
    ) not in values
    assert (
        "contributor.translator",
        "Prof. Dr. Ünal Akkemik",
    ) not in values
    assert (
        "publisher",
        "Türkiye İş Bankası Kültür Yayınları",
    ) in values
    assert (
        "contributor.editor",
        "Prof. Dr. Ünal Akkemik",
    ) in values
    assert len(result.rejected_model_fields) == 2


def test_model_accepts_conservative_unlabelled_front_author() -> None:
    class AuthorModel:
        def extract(self, _tokens):
            return [
                {
                    "field_name": "author",
                    "value": "Sabahattin Ali",
                    "evidence_token_ids": ["author"],
                    "confidence": 0.99,
                }
            ]

    result = EvidenceBoundExtractor(AuthorModel()).extract(
        [token("author", "Sabahattin Ali", cover="front", line=1)]
    )

    assert ("author", "Sabahattin Ali") in {
        (field.field_name, field.value) for field in result.fields
    }
    assert not result.rejected_model_fields


def test_model_accepts_publisher_marker_and_split_contributor_label() -> None:
    class LabelledModel:
        def extract(self, _tokens):
            return [
                {
                    "field_name": "publisher",
                    "value": "Türkiye İş Bankası Kültür Yayınları",
                    "evidence_token_ids": ["publisher"],
                    "confidence": 0.99,
                },
                {
                    "field_name": "publisher",
                    "value": "Örnek Kitapçılık A.Ş.",
                    "evidence_token_ids": ["corporate-publisher"],
                    "confidence": 0.99,
                },
                {
                    "field_name": "contributor.editor",
                    "value": "ÜNAL AKKEMİK",
                    "evidence_token_ids": ["editor-label", "editor-name"],
                    "confidence": 0.99,
                },
            ]

    result = EvidenceBoundExtractor(LabelledModel()).extract(
        [
            token(
                "publisher",
                "Türkiye İş Bankası Kültür Yayınları",
                cover="front",
                line=0,
            ),
            token(
                "corporate-publisher",
                "Örnek Kitapçılık A.Ş.",
                cover="front",
                line=1,
            ),
            token(
                "editor-label",
                "Editör",
                cover="front_inside",
                line=2,
            ),
            token(
                "editor-name",
                "ÜNAL AKKEMİK",
                cover="front_inside",
                line=3,
            ),
        ]
    )

    values = {(field.field_name, field.value) for field in result.fields}
    assert (
        "publisher",
        "Türkiye İş Bankası Kültür Yayınları",
    ) in values
    assert ("publisher", "Örnek Kitapçılık A.Ş.") in values
    assert ("contributor.editor", "ÜNAL AKKEMİK") in values
    assert not result.rejected_model_fields


def test_llama_client_rejects_json_without_fields_key(monkeypatch) -> None:
    class Response:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        @staticmethod
        def read() -> bytes:
            return b'{"choices":[{"message":{"content":"{}"}}]}'

    monkeypatch.setattr(
        "kitapkatalog.extractor.urllib.request.urlopen",
        lambda *_args, **_kwargs: Response(),
    )
    client = LlamaFieldClient("http://127.0.0.1:43210")

    with pytest.raises(ValueError, match="fields alanı eksik"):
        client.extract([])


def test_model_schema_failure_preserves_deterministic_fields_for_review() -> None:
    class BrokenModel:
        def extract(self, _tokens):
            raise ValueError("fields alanı eksik")

    result = EvidenceBoundExtractor(BrokenModel()).extract(
        [
            token(
                "title",
                "Türkiye'nin Bütün Ağaçları ve Çalıları",
                cover="front",
                line=0,
                confidence=0.99,
            )
        ]
    )

    assert any(
        field.field_name == "title" and field.value == "Türkiye'nin Bütün Ağaçları ve Çalıları"
        for field in result.fields
    )
    assert result.rejected_model_fields == [
        {
            "field_name": "__model_error__",
            "error": "ValueError: fields alanı eksik",
        }
    ]


def _title_line(text: str, *, top: float, height: float) -> list[EvidenceToken]:
    return [
        EvidenceToken(
            token_id=f"t:{text}",
            text=text,
            cover="front",
            polygon=((10.0, top), (400.0, top), (400.0, top + height), (10.0, top + height)),
            confidence=0.995,
        )
    ]


def test_a_dominant_title_may_be_accepted_automatically() -> None:
    lines = [
        _title_line("Kürk Mantolu Madonna", top=100.0, height=90.0),
        _title_line("Bir Roman", top=260.0, height=20.0),
    ]
    group = [lines[0]]

    ceiling = _title_layout_ceiling(lines, group)

    # The layout decision is unambiguous, so the ceiling must clear the auto
    # threshold instead of pinning the most basic field to manual review.
    assert ceiling > 0.98


def test_two_similarly_sized_blocks_keep_the_title_in_review() -> None:
    lines = [
        _title_line("Kürk Mantolu Madonna", top=100.0, height=80.0),
        _title_line("Sabahattin Ali", top=260.0, height=75.0),
    ]

    ceiling = _title_layout_ceiling(lines, [lines[0]])

    # Either block could have been the title, and that uncertainty belongs in
    # the score rather than in the reviewer's lap after the fact.
    assert ceiling < 0.98


def test_a_cover_with_only_one_candidate_is_unambiguous() -> None:
    lines = [_title_line("İnce Memed", top=100.0, height=90.0)]

    assert _title_layout_ceiling(lines, [lines[0]]) > 0.98


def test_a_fuzzy_colophon_match_does_not_reach_automatic_acceptance() -> None:
    front = [_title_line("KÜÇÜK PRENS", top=100.0, height=90.0)]
    # "PRENSES" contains "PRENS" and scores well above the fuzzy threshold, so
    # the fallback wins — but it is a different book, not confirmation.
    fallback = _title_line("KÜÇÜK PRENSES", top=100.0, height=30.0)

    similar = min(
        _TITLE_CEILING_DOMINANT
        if _evidence_form(_line_text(fallback)) == _evidence_form(_line_text(front[0]))
        else _TITLE_CEILING_AMBIGUOUS,
        0.99,
    )

    assert similar < 0.98


def test_an_identical_colophon_heading_is_real_confirmation() -> None:
    front = [_title_line("KÜÇÜK PRENS", top=100.0, height=90.0)]
    fallback = _title_line("Küçük Prens", top=100.0, height=30.0)

    ceiling = (
        _TITLE_CEILING_DOMINANT
        if _evidence_form(_line_text(fallback)) == _evidence_form(_line_text(front[0]))
        else _TITLE_CEILING_AMBIGUOUS
    )

    assert ceiling > 0.98
