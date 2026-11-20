"""Not CRUD'u: repository davranışı + göç zinciri (0002/0003) doğrulaması."""

from __future__ import annotations

from pathlib import Path

from sqlalchemy import inspect

from bioprof.application import BioProfApplication
from bioprof.services.repositories import Repository


def _repo(app: BioProfApplication) -> tuple[Repository, str]:
    session = app.database.session()
    repo = Repository(session)
    notebook = repo.create_notebook("Not Defteri")
    return repo, notebook.id


def test_not_olustur_listele_guncelle_sil(app: BioProfApplication) -> None:
    repo, nb = _repo(app)
    kayit = repo.create_note(nb, title="Mitoz", content="Profaz ile başlar.")
    assert kayit.id and kayit.pinned is False

    liste = repo.list_notes(nb)
    assert [n.id for n in liste] == [kayit.id]

    guncel = repo.update_note(kayit.id, content="Profaz, metafaz...", pinned=True)
    assert guncel is not None and guncel.pinned is True
    assert "metafaz" in guncel.content

    assert repo.delete_note(kayit.id) is True
    assert repo.list_notes(nb) == []
    assert repo.delete_note(kayit.id) is False


def test_sabitlenen_not_listede_one_gelir(app: BioProfApplication) -> None:
    repo, nb = _repo(app)
    ilk = repo.create_note(nb, title="sıradan")
    ikinci = repo.create_note(nb, title="önemli", pinned=True)
    liste = repo.list_notes(nb)
    assert [n.id for n in liste] == [ikinci.id, ilk.id]


def test_serialize_note_alanlari(app: BioProfApplication) -> None:
    repo, nb = _repo(app)
    kayit = repo.create_note(nb, title="X", content="Y")
    veri = Repository.serialize_note(kayit)
    assert set(veri) == {
        "id",
        "notebook_id",
        "title",
        "content",
        "pinned",
        "created_at",
        "updated_at",
    }


def test_notebook_silinince_notlar_da_silinir(app: BioProfApplication) -> None:
    repo, nb = _repo(app)
    repo.create_note(nb, title="kalmasın")
    repo.delete_notebook(nb)
    assert repo.list_notes(nb) == []


def test_flashcard_tablolari_migrationla_kurulur(app: BioProfApplication, tmp_path: Path) -> None:
    denetci = inspect(app.database.engine)
    for tablo in ("notes", "flashcard_decks", "flashcards", "flashcard_reviews"):
        assert denetci.has_table(tablo), f"{tablo} yok"
    kolonlar = {k["name"] for k in denetci.get_columns("flashcards")}
    assert {"ease_factor", "interval_days", "repetitions", "lapses", "due_at"} <= kolonlar


def test_sohbet_listeleme_ve_silme(app) -> None:
    import asyncio

    repo, nb = _repo(app)
    konusma = repo.create_conversation(nb, title="Mitoz sorusu")
    repo.add_message(konusma.id, "user", "Mitoz nedir?")
    repo.add_message(konusma.id, "assistant", "Bölünmedir [S1].")

    liste = asyncio.run(app._list_conversations(nb))
    assert [item["title"] for item in liste] == ["Mitoz sorusu"]
    mesajlar = asyncio.run(app._list_conversation_messages(konusma.id))
    assert [m["role"] for m in mesajlar] == ["user", "assistant"]

    asyncio.run(app._delete_conversation(konusma.id))
    assert asyncio.run(app._list_conversations(nb)) == []
    assert asyncio.run(app._list_conversation_messages(konusma.id)) == []


def test_not_api_handlerlari(app) -> None:
    import asyncio

    repo, nb = _repo(app)
    olusan = asyncio.run(
        app._create_note({"notebook_id": nb, "title": "Deney", "content": "Osmoz"})
    )
    assert olusan["title"] == "Deney"
    guncel = asyncio.run(app._update_note(olusan["id"], {"pinned": True}))
    assert guncel["pinned"] is True
    liste = asyncio.run(app._list_notes(nb))
    assert len(liste) == 1
    asyncio.run(app._delete_note(olusan["id"]))
    assert asyncio.run(app._list_notes(nb)) == []
