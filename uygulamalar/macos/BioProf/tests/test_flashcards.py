"""Flashcard servisi: SM-2 zamanlaması, deste aktarımı, inceleme günlüğü, export."""

from __future__ import annotations

import pytest
from sqlalchemy import select

from bioprof.application import BioProfApplication
from bioprof.db.models import FlashcardReviewRecord
from bioprof.services.flashcards import FlashcardService, sm2_guncelle
from bioprof.services.repositories import Repository


class TestSm2:
    def test_klasik_dizi_1_6_ve_ef_carpani(self) -> None:
        adim1 = sm2_guncelle(2.5, 0.0, 0, 5)
        assert (adim1.interval_days, adim1.repetitions) == (1.0, 1)
        adim2 = sm2_guncelle(adim1.ease_factor, adim1.interval_days, adim1.repetitions, 5)
        assert (adim2.interval_days, adim2.repetitions) == (6.0, 2)
        adim3 = sm2_guncelle(adim2.ease_factor, adim2.interval_days, adim2.repetitions, 5)
        assert adim3.interval_days == pytest.approx(6.0 * adim3.ease_factor)
        assert adim3.repetitions == 3

    def test_basarisizlik_sifirlar_ve_lapse_sayar(self) -> None:
        sonuc = sm2_guncelle(2.5, 15.0, 4, 2)
        assert sonuc.lapse is True
        assert sonuc.repetitions == 0
        assert sonuc.interval_days == 1.0
        assert sonuc.ease_factor < 2.5

    def test_ef_taban_1_3_altina_inmez(self) -> None:
        ef = 1.35
        for _ in range(10):
            ef = sm2_guncelle(ef, 1.0, 0, 3).ease_factor
        assert ef >= 1.3

    def test_zor_hatirlama_ef_dusurur_ama_ilerletir(self) -> None:
        sonuc = sm2_guncelle(2.5, 6.0, 2, 3)
        assert sonuc.lapse is False
        assert sonuc.repetitions == 3
        assert sonuc.ease_factor < 2.5


def _deste(app: BioProfApplication):
    session = app.database.session()
    notebook = Repository(session).create_notebook("Kartlar")
    service = FlashcardService(session)
    deck = service.create_deck_from_artifact(
        notebook.id,
        None,
        "Hücre",
        [
            {
                "front": "Mitokondri nedir?", "back": "Enerji santrali.",
                "citation": "[S1]", "citation_id": "c1", "source_title": "Campbell",
            },
            {
                "front": "Ribozom nedir?", "back": "Protein sentez yeri.",
                "citation": "[S2]", "citation_id": "c2",
            },
            {"front": "", "back": "boş ön yüz atlanır"},
        ],
    )
    return session, service, deck


def test_artifact_karti_desteye_atif_koruyarak_gecer(app: BioProfApplication) -> None:
    session, service, deck = _deste(app)
    kartlar = service.due_cards(deck.id)
    assert len(kartlar) == 2  # boş ön yüz atlandı
    assert kartlar[0]["citation_id"] == "c1"
    assert kartlar[0]["citation_label"] == "[S1]"


def test_inceleme_karti_gunceller_ve_log_yazar(app: BioProfApplication) -> None:
    session, service, deck = _deste(app)
    kart = service.due_cards(deck.id)[0]
    sonra = service.record_review(kart["id"], 5)
    assert sonra["repetitions"] == 1
    assert sonra["interval_days"] == 1.0
    loglar = session.scalars(select(FlashcardReviewRecord)).all()
    assert len(loglar) == 1
    assert loglar[0].grade == 5 and loglar[0].interval_after == 1.0
    # Vadesi yarına atıldı: due listesinde artık görünmez.
    kalan = service.due_cards(deck.id)
    assert all(item["id"] != kart["id"] for item in kalan)


def test_bilemedim_ayni_gun_vadede_kalir_lapse_artar(app: BioProfApplication) -> None:
    session, service, deck = _deste(app)
    kart = service.due_cards(deck.id)[0]
    service.record_review(kart["id"], 5)
    sonra = service.record_review(service.due_cards(deck.id)[0]["id"], 2)
    assert sonra["lapses"] == 1 and sonra["repetitions"] == 0


def test_csv_export_uc_kolon(app: BioProfApplication) -> None:
    session, service, deck = _deste(app)
    icerik = service.export_csv(deck.id).decode("utf-8")
    satirlar = [satir for satir in icerik.splitlines() if satir]
    assert len(satirlar) == 2
    assert satirlar[0].split(";")[0] == "Mitokondri nedir?"
    assert "Campbell" in satirlar[0]


def test_apkg_export_zip_imzali(app: BioProfApplication) -> None:
    pytest.importorskip("genanki")
    session, service, deck = _deste(app)
    veri = service.export_apkg(deck.id)
    assert veri[:2] == b"PK"  # apkg bir zip arşividir


def test_deste_silme(app: BioProfApplication) -> None:
    session, service, deck = _deste(app)
    assert service.delete_deck(deck.id) is True
    assert service.get_deck(deck.id) is None
    assert service.delete_deck(deck.id) is False


def test_bos_kart_listesi_reddedilir(app: BioProfApplication) -> None:
    session = app.database.session()
    notebook = Repository(session).create_notebook("Boş")
    with pytest.raises(ValueError):
        FlashcardService(session).create_deck_from_artifact(notebook.id, None, "Boş", [])


def test_baska_notebookun_artifacti_desteye_cevrilemez(app: BioProfApplication) -> None:
    """Codex çapraz review bulgusu: aidiyet kapısı olmadan A'nın kartları B'ye
    deste olarak kopyalanabiliyordu."""
    import asyncio

    from bioprof.api.native import NativeAPIError

    with app.database.session() as session:
        repo = Repository(session)
        sahip = repo.create_notebook("Sahip").id
        yabanci = repo.create_notebook("Yabancı").id
        artifact = repo.create_artifact(
            sahip, "flashcards", "Kartlar", "/tmp/yok.md", "text/markdown",
            metadata={"structured_data": {"cards": [{"front": "a", "back": "b"}]}},
        )
    with pytest.raises(NativeAPIError):
        asyncio.run(
            app._create_flashcard_deck(
                {"notebook_id": yabanci, "artifact_id": artifact.id}
            )
        )
