"""Loopback adapter for the existing SesLab MLX-Whisper/Murat service."""

from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any

import httpx

from bioprof.domain.models import ProviderCapabilities
from bioprof.providers.base import AudioPayload, ProviderError, ProviderUnavailableError

_AUDIO_TYPES = {
    "wav": "audio/wav",
    "mp3": "audio/mpeg",
    "opus": "audio/opus",
    "aac": "audio/aac",
    "flac": "audio/flac",
    "pcm": "audio/L16",
}

# SesLab /api/audio/master en fazla 200 parça kabul eder (HTTP 413). Sınırın
# altında payla gruplayıp iki seviyede birleştiriyoruz: 30 dk'lık podcast
# ~240, 90 dk'lık ~720 parça demek — tek istek hem sınırı aşar hem yüzlerce
# MB'lık gövdeyle dakikalarca sürer.
PARTI_BOYU = 160


class SesLabAdapter:
    name = "seslab"
    requires_egress = False

    def __init__(
        self,
        *,
        base_url: str = "http://127.0.0.1:8000",
        client: httpx.AsyncClient | None = None,
        timeout: float = 900.0,
        master_timeout: float = 1800.0,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self._client = client
        self._owns_client = client is None
        self.timeout = timeout
        self.master_timeout = master_timeout

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=self.timeout,
                follow_redirects=False,
                trust_env=False,
            )
        return self._client

    async def aclose(self) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None

    async def _request(self, method: str, path: str, **kwargs: Any) -> httpx.Response:
        try:
            response = await self._http().request(method, f"{self.base_url}{path}", **kwargs)
        except httpx.HTTPError as exc:
            raise ProviderUnavailableError(
                f"SesLab servisine bağlanılamadı: {exc.__class__.__name__}."
            ) from exc
        if response.is_error:
            # SesLab errors can contain input text. Do not echo its response body.
            raise ProviderError(f"SesLab HTTP {response.status_code} döndürdü.", status_code=502)
        return response

    async def probe(self) -> ProviderCapabilities:
        details: dict[str, Any] = {"base_url": self.base_url}
        available = False
        for path in ("/api/system/status", "/healthz"):
            try:
                response = await self._http().get(f"{self.base_url}{path}", timeout=5)
                details["status_path"] = path
                details["status_code"] = response.status_code
                available = response.is_success
                if available:
                    try:
                        body = response.json()
                        if isinstance(body, Mapping):
                            # Keep only operational booleans/labels, never paths or secrets.
                            for key in ("status", "ready", "whisper", "xtts", "murat"):
                                if key in body and isinstance(body[key], (str, bool, int, float)):
                                    details[key] = body[key]
                    except ValueError:
                        pass
                    break
            except httpx.HTTPError as exc:
                details["error"] = exc.__class__.__name__
        return ProviderCapabilities(
            name=self.name,
            available=available,
            models=["mlx-whisper", "xtts-v2-murat"] if available else [],
            transcription=available,
            speech=available,
            details=details,
        )

    async def transcribe(
        self,
        data: bytes,
        *,
        filename: str,
        content_type: str | None = None,
        model: str | None = None,
        language: str | None = None,
        prompt: str | None = None,
        response_format: str = "json",
    ) -> dict[str, Any]:
        if not data:
            raise ProviderError("Ses dosyası boş.", status_code=400)
        fields: dict[str, str] = {
            "model": model or "mlx-whisper",
            "response_format": response_format,
        }
        if language:
            fields["language"] = language
        if prompt:
            fields["prompt"] = prompt
        response = await self._request(
            "POST",
            "/v1/audio/transcriptions",
            files={"file": (filename, data, content_type or "application/octet-stream")},
            data=fields,
        )
        if response_format in {"text", "srt", "vtt"}:
            return {"text": response.text, "format": response_format}
        try:
            body = response.json()
        except ValueError as exc:
            raise ProviderError("SesLab geçerli bir transkripsiyon yanıtı döndürmedi.") from exc
        if not isinstance(body, Mapping):
            raise ProviderError("SesLab geçerli bir transkripsiyon yanıtı döndürmedi.")
        return dict(body)

    async def synthesize(
        self,
        text: str,
        *,
        voice: str = "Murat",
        model: str | None = None,
        response_format: str = "wav",
        speed: float = 1.0,
        language: str = "tr",
        verify: bool = False,  # geriye uyumluluk; SesLab tarafında karşılığı yok
    ) -> AudioPayload:
        text = text.strip()
        if not text:
            raise ProviderError("Seslendirilecek metin boş.", status_code=400)
        # SesLab /v1/audio/speech ucu 0.5-2.0 dışını 422 ile reddeder.
        if not 0.5 <= speed <= 2.0:
            raise ProviderError("Ses hızı 0.5 ile 2.0 arasında olmalıdır.", status_code=400)
        response = await self._request(
            "POST",
            "/v1/audio/speech",
            json={
                "model": model or "xtts-v2",
                "input": text,
                "voice": voice,
                "response_format": response_format,
                "speed": speed,
                "language": language,
            },
        )
        media_type = response.headers.get("content-type", "").split(";", 1)[0]
        if not media_type or media_type == "application/octet-stream":
            media_type = _AUDIO_TYPES.get(response_format, "application/octet-stream")
        if not response.content:
            raise ProviderError("SesLab boş ses verisi döndürdü.")
        return AudioPayload(data=response.content, media_type=media_type)

    async def master(
        self,
        chunks: list[bytes],
        *,
        gap_ms: int = 320,
        response_format: str = "wav",
    ) -> AudioPayload | None:
        """Parçaları SesLab'ın mastering zincirinde birleştirir.

        Uç bulunmayan (eski) bir SesLab'da ``None`` döner; çağıran ham
        birleştirmeye düşer. DSP kodu bilinçli olarak burada değil SesLab'da:
        zincir tek yerde bakılıyor.

        SesLab'ın parça sınırını (MAX_PARCA=200) aşan işler iki seviyede
        birleştirilir: gruplar normalize'lı WAV olarak master edilir, sonra
        grup WAV'ları ``normalize=false`` ile tek parçaya dikilir. İkinci
        geçişte normalize KAPALI olmak zorunda: seviye eşitleme ve kenar
        kırpma grup içinde zaten yapıldı, ikinci kırpma grup sınırlarındaki
        bilinçli boşlukları yok edip altyazıyı kaydırır. Boşluk muhasebesi
        değişmez: grup içi n-1 + gruplar arası G-1 = toplam N-1.
        """
        if not chunks:
            raise ProviderError("Birleştirilecek ses parçası yok.", status_code=400)
        if len(chunks) <= PARTI_BOYU:
            return await self._master_istek(
                chunks, gap_ms=gap_ms, response_format=response_format, normalize=True
            )
        gruplar = [
            chunks[bas : bas + PARTI_BOYU] for bas in range(0, len(chunks), PARTI_BOYU)
        ]
        grup_wavlari: list[bytes] = []
        grup_sureleri: list[list[float]] = []
        for grup in gruplar:
            payload = await self._master_istek(
                grup, gap_ms=gap_ms, response_format="wav", normalize=True
            )
            if payload is None:
                return None
            grup_wavlari.append(payload.data)
            sureler = list(payload.metadata.get("segment_durations", []))
            grup_sureleri.append(sureler if len(sureler) == len(grup) else [])
        birlesik = await self._master_istek(
            grup_wavlari, gap_ms=gap_ms, response_format=response_format, normalize=False
        )
        if birlesik is None:
            return None
        # Süre listesi ancak HER gruptan eksiksiz geldiyse anlamlı; kısmi liste
        # altyazıyı sessizce kaydırır, hiç yokmuş gibi davranmak daha doğru.
        eksiksiz = all(grup_sureleri)
        duz = [sure for grup in grup_sureleri for sure in grup] if eksiksiz else []
        return AudioPayload(
            data=birlesik.data,
            media_type=birlesik.media_type,
            metadata={"segment_durations": duz} if duz else {},
        )

    async def _master_istek(
        self,
        chunks: list[bytes],
        *,
        gap_ms: int,
        response_format: str,
        normalize: bool,
    ) -> AudioPayload | None:
        files = [
            ("files", (f"segment-{index:03d}.wav", chunk, "audio/wav"))
            for index, chunk in enumerate(chunks)
        ]
        try:
            response = await self._http().post(
                f"{self.base_url}/api/audio/master",
                files=files,
                data={
                    "gap_ms": str(int(gap_ms)),
                    "format": response_format,
                    "normalize": "true" if normalize else "false",
                },
                # Uzun işlerde (yüzlerce parça) genel timeout yetmeyebilir;
                # geçen turda bir 30 dk denemesini SesLab zaman aşımı öldürdü.
                timeout=self.master_timeout,
            )
        except httpx.HTTPError as exc:
            raise ProviderUnavailableError(
                f"SesLab mastering servisine bağlanılamadı: {exc.__class__.__name__}."
            ) from exc
        if response.status_code == 404:
            return None
        if response.is_error:
            raise ProviderError(
                f"SesLab mastering HTTP {response.status_code} döndürdü.", status_code=502
            )
        if not response.content:
            raise ProviderError("SesLab mastering boş ses döndürdü.")
        media_type = response.headers.get("content-type", "").split(";", 1)[0]
        # Mastering kenar sessizliğini kırptığı için parça süreleri değişir;
        # altyazı zaman damgaları ham TTS sürelerinden hesaplanırsa kayar.
        durations: list[float] = []
        raw = response.headers.get("X-Segment-Durations")
        if raw:
            try:
                parsed = json.loads(raw)
                durations = [float(value) for value in parsed]
            except (ValueError, TypeError):
                durations = []
        return AudioPayload(
            data=response.content,
            media_type=media_type or _AUDIO_TYPES.get(response_format, "audio/wav"),
            metadata={"segment_durations": durations} if durations else {},
        )
