"""Yerel LLM katmanı: profil çözümleme, tel eşlemesi ve degraded düşüşü."""

from __future__ import annotations

import asyncio
import importlib.util
import json
from pathlib import Path

import httpx

from bioprof.config import Settings
from bioprof.models.manager import LocalModelManager
from bioprof.providers.base import ProviderError, ProviderUnavailableError
from bioprof.providers.local_model import LocalModelProvider
from bioprof.services.repositories import Repository
from tests.conftest import FakeRetriever, fake_evidence

_MLX_IN_VENV = importlib.util.find_spec("mlx_lm") is not None


def test_ayarlar_varsayilanlari() -> None:
    settings = Settings(_env_file=None)
    assert settings.local_llm_default_profile == "sohbet"
    assert settings.local_llm_idle_timeout == 600.0
    assert settings.local_llm_python.name == "python"


def test_profil_yolu_yerel_dizin(tmp_path: Path) -> None:
    manager = LocalModelManager(tmp_path)
    profile = manager.resolve_profile("biyo")
    assert manager.profile_path(profile) == (
        Path("~/.biyo-cozucu/modeller/biyo-mlx-v1").expanduser()
    )
    assert manager.model_argument(profile).endswith("biyo-mlx-v1")


def test_hf_onbellekli_profil_depo_kimligi_gecer(tmp_path: Path) -> None:
    manager = LocalModelManager(tmp_path)
    profile = manager.resolve_profile("sohbet")
    # Varlık kontrolü HF önbellek dizinine, motor argümanı depo kimliğine bakar.
    assert manager.profile_path(profile).name == (
        "models--mlx-community--Qwen3.5-4B-MLX-4bit"
    )
    assert manager.model_argument(profile) == "mlx-community/Qwen3.5-4B-MLX-4bit"


def test_engine_available_dis_python(tmp_path: Path) -> None:
    fake_python = tmp_path / "python"
    fake_python.write_text("#!/bin/sh\n")
    assert LocalModelManager(tmp_path, mlx_python=fake_python).engine_available("mlx-lm")
    yok = LocalModelManager(tmp_path, mlx_python=tmp_path / "yok")
    assert yok.engine_available("mlx-lm") is _MLX_IN_VENV


def test_komut_dis_python_kullanir(tmp_path: Path) -> None:
    if _MLX_IN_VENV:
        return  # süreç içi mlx varken dış python'a gerek yok
    fake_python = tmp_path / "python"
    fake_python.write_text("#!/bin/sh\n")
    manager = LocalModelManager(tmp_path, mlx_python=fake_python)
    command = manager._command("mlx-lm", tmp_path / "model", 1234, context_size=8192)
    assert command[0] == str(fake_python)
    assert command[1:3] == ["-m", "mlx_lm.server"]


def _wire_provider(handler) -> LocalModelProvider:
    provider = LocalModelProvider(
        base_url="http://127.0.0.1:9", profile="biyo", available_profiles=["biyo", "derin"]
    )
    provider._client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    provider._owns_client = True
    return provider


def _chat_handler(captured: dict, content: str, finish: str = "stop"):
    def handler(request: httpx.Request) -> httpx.Response:
        captured.update(json.loads(request.content))
        return httpx.Response(
            200,
            json={
                "model": "/tmp/bir/model/yolu",
                "choices": [{"message": {"content": content}, "finish_reason": finish}],
                "usage": {"completion_tokens": 3},
            },
        )

    return handler


def test_local_model_provider_tel_eslemesi() -> None:
    captured: dict = {}
    provider = _wire_provider(_chat_handler(captured, "yanıt<|im_end|>\n"))
    result = asyncio.run(
        provider.chat(
            {
                "model": "biyo",
                "messages": [{"role": "user", "content": "soru"}],
                "evidence": [{"gizli": "kanit"}],
                "temperature": 0.1,
            }
        )
    )
    # mlx_lm.server yalnız "default_model" anahtarını tanır; kanıt dışarı sızmaz.
    assert captured["model"] == "default_model"
    assert "evidence" not in captured
    # Düşünme kapatılmazsa token bütçesi düşünceye gider ve content boş döner.
    assert captured["chat_template_kwargs"]["enable_thinking"] is False
    assert result.model == "biyo"
    assert result.text == "yanıt"


def test_dusunce_blogu_ayiklanir() -> None:
    captured: dict = {}
    provider = _wire_provider(
        _chat_handler(captured, "<think>uzun uzun düşünüyorum</think>Görünen yanıt.")
    )
    result = asyncio.run(
        provider.chat({"model": "biyo", "messages": [{"role": "user", "content": "s"}]})
    )
    assert result.text == "Görünen yanıt."


def test_kapanmis_dusunce_etiketi_ayiklanir() -> None:
    captured: dict = {}
    provider = _wire_provider(_chat_handler(captured, "düşünce metni</think>Asıl yanıt."))
    result = asyncio.run(
        provider.chat({"model": "biyo", "messages": [{"role": "user", "content": "s"}]})
    )
    assert result.text == "Asıl yanıt."


def test_bos_icerik_hata_uretir() -> None:
    captured: dict = {}
    provider = _wire_provider(_chat_handler(captured, "<think>bitmedi", finish="length"))
    try:
        asyncio.run(
            provider.chat({"model": "biyo", "messages": [{"role": "user", "content": "s"}]})
        )
    except ProviderError as exc:
        assert "boş yanıt" in str(exc)
    else:  # pragma: no cover - başarısızlık yolu
        raise AssertionError("Boş içerik sessizce kabul edildi")


def _notebook_id(app) -> str:
    with app.database.session() as session:
        return Repository(session).create_notebook("Deneme").id


class _BoomProvider:
    name = "boom"
    requires_egress = False

    async def chat(self, payload):
        raise ProviderUnavailableError("boom kapalı")


def test_ask_saglayici_hatasi_kanit_ozetine_duser(app) -> None:
    app.providers.register(_BoomProvider())
    app._retriever = lambda session: FakeRetriever([fake_evidence()])
    notebook_id = _notebook_id(app)
    value = asyncio.run(
        app._ask(notebook_id, {"question": "Mitokondri nedir?", "provider": "boom"})
    )
    assert value["degraded"] is True
    assert value["provider"] == "boom"
    assert value["answer_markdown"].strip()
    assert value["conversation_id"]


def test_ask_local_model_baslamazsa_degraded(app) -> None:
    async def fail_start(*args, **kwargs):
        raise RuntimeError("model dizini yok")

    app.model_manager.start = fail_start
    app._retriever = lambda session: FakeRetriever([fake_evidence()])
    notebook_id = _notebook_id(app)
    value = asyncio.run(
        app._ask(notebook_id, {"question": "Mitokondri nedir?", "provider": "local_model"})
    )
    assert value["degraded"] is True
    assert value["provider"] == "local_model"
    assert value["answer_markdown"].strip()


def test_ask_llm_calisirken_degraded_degil(app) -> None:
    app._retriever = lambda session: FakeRetriever([fake_evidence()])
    notebook_id = _notebook_id(app)
    value = asyncio.run(app._ask(notebook_id, {"question": "Mitokondri nedir?"}))
    assert value["degraded"] is False


def test_provider_raporu_local_model_stub(app) -> None:
    report = asyncio.run(app._provider_report(active=False))
    stub = next(item for item in report if item["name"] == "local_model")
    assert stub["details"]["lazy_start"] is True
    assert isinstance(stub["models"], list)
