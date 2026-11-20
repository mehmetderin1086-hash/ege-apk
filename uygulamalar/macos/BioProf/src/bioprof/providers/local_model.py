"""mlx_lm.server / llama-server üzerinde koşan yerel model sağlayıcısı.

``LocalModelManager`` sunucuyu başlattıktan sonra bu adaptör kaydedilir.
Üç davranış burada tek noktada toplanır:

* mlx_lm.server istek gövdesindeki ``model`` alanını yalnız ``default_model``
  anahtarıyla CLI'da verilen modele eşler; başka her değer bir HF deposu gibi
  yorumlanıp indirme denemesine dönüşür.
* Qwen3.5 sohbet şablonu varsayılan olarak düşünür; düşünme token bütçesini
  tüketirse ``content`` boş, ``reasoning`` dolu döner ve yanıt sessizce
  kaybolur. RAG kanıtından yazarken düşünmeye gerek yok — kapatılır.
* Sohbet şablonunun bitiş işareti (``<|im_end|>``) metinde kalabiliyor.
"""

from __future__ import annotations

import re
from collections.abc import AsyncIterator, Mapping
from typing import Any

from bioprof.domain.models import ProviderCapabilities
from bioprof.providers.base import ChatResult, ProviderError
from bioprof.providers.openai_compatible import OpenAICompatibleProvider

_WIRE_MODEL = "default_model"
# RAG kanıtı yalnız local_evidence sağlayıcısının anladığı bir alan; genel
# OpenAI uyumlu sunuculara sızdırılmaz.
_PRIVATE_KEYS = {"evidence", "metadata"}
_SPECIAL_TOKENS = re.compile(r"<\|(?:im_end|im_start|endoftext|eot_id)\|>")
_THINK_BLOCK = re.compile(r"<think>.*?</think>", re.DOTALL | re.IGNORECASE)


def _wire_payload(payload: Mapping[str, Any]) -> dict[str, Any]:
    body = {key: value for key, value in payload.items() if key not in _PRIVATE_KEYS}
    body["model"] = _WIRE_MODEL
    template_args = dict(body.get("chat_template_kwargs") or {})
    template_args.setdefault("enable_thinking", False)
    body["chat_template_kwargs"] = template_args
    body.setdefault("max_tokens", 1400)
    return body


def clean_model_text(value: str) -> str:
    """Şablon artıklarını ve düşünce bloklarını ayıklar.

    Üç biçim de karşılanır: tam ``<think>…</think>`` bloğu, yalnız kapanış
    etiketi (Qwen3.5 şablonu açılışı isteme koyar) ve token sınırında kesilen
    kapanmamış açılış. Sonuncusu tamamen düşünce sayılır — aksi halde ham
    düşünce yanıt diye sunulurdu.
    """
    text = _THINK_BLOCK.sub("", value)
    lowered = text.casefold()
    if "</think>" in lowered and "<think>" not in lowered:
        text = text[lowered.rindex("</think>") + len("</think>") :]
        lowered = text.casefold()
    if "<think>" in lowered:
        text = text[: lowered.index("<think>")]
    return _SPECIAL_TOKENS.sub("", text).strip()


class LocalModelProvider(OpenAICompatibleProvider):
    def __init__(
        self,
        *,
        base_url: str,
        profile: str,
        available_profiles: list[str] | None = None,
        timeout: float = 600.0,
    ) -> None:
        super().__init__(
            name="local_model",
            base_url=base_url,
            requires_egress=False,
            timeout=timeout,
        )
        self.profile = profile
        self.available_profiles = available_profiles or [profile]

    async def probe(self, *, active: bool = False) -> ProviderCapabilities:
        capabilities = await super().probe(active=active)
        details = dict(capabilities.details)
        details["active_profile"] = self.profile
        return capabilities.model_copy(
            update={"models": list(self.available_profiles), "details": details}
        )

    async def chat(self, payload: Mapping[str, Any]) -> ChatResult:
        result = await super().chat(_wire_payload(payload))
        result.model = self.profile
        result.text = clean_model_text(result.text)
        if not result.text:
            # Boş içerik "model yanıt vermedi" demektir; sessizce boş metni
            # yanıt diye geçirmek yerine çağıranın kanıt özetine düşmesi gerekir.
            raise ProviderError(
                "Yerel model boş yanıt döndürdü "
                f"(bitiş nedeni: {result.finish_reason}).",
                status_code=502,
            )
        return result

    def stream_chat(self, payload: Mapping[str, Any]) -> AsyncIterator[dict[str, Any]]:
        return super().stream_chat(_wire_payload(payload))
