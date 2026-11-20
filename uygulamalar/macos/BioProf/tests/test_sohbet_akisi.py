"""Akışlı sohbet: taslak akar, DB'ye yalnız doğrulanmış yanıt yazılır."""

from __future__ import annotations

import asyncio
from typing import Any

from bioprof.providers.base import ChatResult, ProviderUnavailableError
from bioprof.rag.answering import StrictEvidenceAnswerBuilder
from bioprof.services.repositories import Repository
from tests.conftest import FakeRetriever, fake_evidence

_SUPPORTED = "Mitokondri, hücrenin enerji santrali olarak görev yapar [S1]."


class _StreamProvider:
    """Metni parça parça akıtan sahte sağlayıcı."""

    name = "sahte_akis"
    requires_egress = False

    def __init__(self, text: str = _SUPPORTED, *, fail: bool = False) -> None:
        self.text = text
        self.fail = fail
        self.chat_calls = 0

    async def chat(self, payload):
        self.chat_calls += 1
        return ChatResult(text=self.text, model="sahte", provider=self.name)

    async def stream_chat(self, payload):
        if self.fail:
            raise ProviderUnavailableError("akış koptu")
        for parça in self.text.split(" "):
            yield {"choices": [{"delta": {"content": parça + " "}}]}


def _collect(app, notebook_id: str, payload: dict[str, Any]) -> list[dict[str, Any]]:
    async def run() -> list[dict[str, Any]]:
        return [event async for event in app.ask_stream(notebook_id, payload)]

    return asyncio.run(run())


def _notebook(app) -> str:
    with app.database.session() as session:
        return Repository(session).create_notebook("Akış").id


def _messages(app, conversation_id: str) -> list[tuple[str, str]]:
    with app.database.session() as session:
        return [
            (record.role, record.content)
            for record in Repository(session).list_messages(conversation_id)
        ]


def test_akis_taslak_sonra_dogrulanmis_final(app) -> None:
    app.providers.register(_StreamProvider())
    app._retriever = lambda session: FakeRetriever([fake_evidence()])
    notebook_id = _notebook(app)

    events = _collect(app, notebook_id, {"question": "Mitokondri?", "provider": "sahte_akis"})
    names = [event["event"] for event in events]
    assert names[0] == "draft_delta"
    assert "validating" in names
    assert names[-1] == "final"
    # Sıra numarası monoton artar: yeniden bağlanan istemci sırayı bilebilir.
    assert [event["seq"] for event in events] == sorted(event["seq"] for event in events)
    assert len({event["message_id"] for event in events}) == 1

    final = events[-1]["answer"]
    assert final["degraded"] is False
    assert "[S1]" in final["answer_markdown"]

    # DB'ye yalnız doğrulanmış final yazılır (taslak parçaları değil).
    kayitlar = _messages(app, final["conversation_id"])
    assert [role for role, _ in kayitlar] == ["user", "assistant"]
    assert kayitlar[1][1] == final["answer_markdown"]


def test_akis_desteksiz_metin_kapidan_gecemez(app) -> None:
    app.providers.register(_StreamProvider("Aspirin günde 3 kez alınmalıdır [S1]."))
    app._retriever = lambda session: FakeRetriever([fake_evidence()])
    notebook_id = _notebook(app)

    events = _collect(app, notebook_id, {"question": "Doz?", "provider": "sahte_akis"})
    final = events[-1]["answer"]
    # Taslak aktı ama kanıt kapısı reddetti; final deterministik özete indi.
    assert "günde 3 kez" not in final["answer_markdown"]


def test_akis_saglayici_coktugunde_degraded_final(app) -> None:
    app.providers.register(_StreamProvider(fail=True))
    app._retriever = lambda session: FakeRetriever([fake_evidence()])
    notebook_id = _notebook(app)

    events = _collect(app, notebook_id, {"question": "Mitokondri?", "provider": "sahte_akis"})
    final = events[-1]["answer"]
    assert final["degraded"] is True
    assert final["answer_markdown"].strip()
    assert [event["event"] for event in events][-1] == "final"


def test_klinik_ret_akista_da_uygulanir(app) -> None:
    app.providers.register(_StreamProvider())
    app._retriever = lambda session: FakeRetriever([fake_evidence()])
    notebook_id = _notebook(app)

    events = _collect(
        app,
        notebook_id,
        {"question": "Benim için hangi ilaç dozunu önerirsin?", "provider": "sahte_akis"},
    )
    assert [event["event"] for event in events] == ["final"]
    assert events[0]["answer"]["provider"] == "bioprof_policy"


def test_gecmis_isteme_baglam_olarak_giriyor(app) -> None:
    provider = _StreamProvider()
    app.providers.register(provider)
    app._retriever = lambda session: FakeRetriever([fake_evidence()])
    notebook_id = _notebook(app)

    first = asyncio.run(
        app._ask(notebook_id, {"question": "Mitokondri?", "provider": "sahte_akis"})
    )
    conversation_id = first["conversation_id"]
    plan = asyncio.run(
        app._prepare_ask(
            notebook_id,
            {
                "question": "Peki krista nedir?",
                "conversation_id": conversation_id,
                "provider": "sahte_akis",
            },
        )
    )
    user_message = plan.messages[-1]["content"]
    assert "ÖNCEKİ KONUŞMA" in user_message
    assert "Mitokondri?" in user_message


def test_gecmissiz_istem_degismedi(app) -> None:
    evidence = [fake_evidence()]
    builder = StrictEvidenceAnswerBuilder()
    with_history = builder.build_prompt("Soru?", evidence, history=[])
    without = builder.build_prompt("Soru?", evidence)
    assert with_history == without
