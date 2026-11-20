"""JSON-stdio adapters for isolated llama.cpp-compatible vision sidecars.

PaddleOCR-VL and Surya have heavy, mutually exclusive runtimes on a 16 GB
machine.  The scheduler starts this adapter as a short-lived sidecar, receives
one schema-validated result, then releases all model memory before the next
large model is admitted.

Sidecar request (JSON on stdin)::

    {"protocol": 1, "engine_id": "...", "image_path": "...", ...}

Sidecar response (JSON on stdout)::

    {"protocol": 1, "engine_id": "...", "raw_text": "...",
     "tokens": [{"text": "...", "confidence": .9,
                 "polygon": [[x,y], ...], "line_id": "..."}]}
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess

from kitapkatalog import portable
import time
from collections.abc import Sequence
from contextlib import suppress
from pathlib import Path
from types import SimpleNamespace
from typing import Any, ClassVar

from kitapkatalog.images import PreparedImage
from kitapkatalog.ocr.contracts import (
    EngineAvailability,
    EngineOcrResult,
    InvalidEngineResultError,
    OcrEngineAdapter,
    OcrExecutionError,
    OcrToken,
)


def _terminate_process_group(process: subprocess.Popen[Any]) -> None:
    """Signal the sidecar and everything it started, then reap it.

    A plain ``kill()`` leaves the llama-server grandchild running; the sidecar
    is started in its own session so the group id is the sidecar's own pid.
    """

    portable.surec_grubunu_sonlandir(process)
    try:
        process.wait(timeout=10)
        return
    except subprocess.TimeoutExpired:
        pass
    portable.surec_grubunu_sonlandir(process, zorla=True)
    with suppress(subprocess.TimeoutExpired):
        process.wait(timeout=5)


class LlamaVisionSidecarAdapter(OcrEngineAdapter):
    evidence_kind = "vision"
    engine_id: ClassVar[str]
    engine_profile: ClassVar[str]
    prompt_protocol: ClassVar[str] = "kitapkatalog-vision-json-v2"
    # The GGUF pair is reloaded on every invocation, so grouping images is the
    # single largest saving available to these two engines.
    batches_model_load: ClassVar[bool] = True

    def __init__(
        self,
        *,
        executable: str | Path,
        model_path: Path,
        mmproj_path: Path,
        model_version: str,
        artifact_digest: str | None = None,
        timeout_seconds: int = 900,
        startup_timeout_seconds: int = 600,
        extra_args: tuple[str, ...] = (),
        environment: dict[str, str] | None = None,
        backend_executable: str | Path | None = None,
    ) -> None:
        self.executable = str(executable)
        self.model_path = Path(model_path)
        self.mmproj_path = Path(mmproj_path)
        self.model_version = model_version
        self.artifact_digest = artifact_digest
        self.timeout_seconds = int(timeout_seconds)
        self.startup_timeout_seconds = int(startup_timeout_seconds)
        self.extra_args = tuple(extra_args)
        self.environment = dict(environment or {})
        self.backend_executable = str(backend_executable) if backend_executable else None

    def _resolved_executable(self) -> str | None:
        candidate = Path(self.executable)
        if candidate.parent != Path(".") or candidate.is_absolute():
            return str(candidate) if candidate.is_file() else None
        return shutil.which(self.executable)

    def availability(self) -> EngineAvailability:
        problems: list[str] = []
        if self._resolved_executable() is None:
            problems.append(
                f"JSON vision sidecar bulunamadı: {self.executable}. Paketlenmiş "
                "`kitapkatalog-vision-sidecar` yolunu yapılandırın"
            )
        if not self.model_path.is_file():
            problems.append(f"GGUF model bulunamadı: {self.model_path}")
        if not self.mmproj_path.is_file():
            problems.append(f"GGUF mmproj bulunamadı: {self.mmproj_path}")
        if self.backend_executable:
            backend_path = Path(self.backend_executable)
            backend_found = (
                backend_path.is_file()
                if backend_path.parent != Path(".") or backend_path.is_absolute()
                else shutil.which(self.backend_executable) is not None
            )
            if not backend_found:
                problems.append(
                    f"Yerel llama.cpp vision runtime bulunamadı: {self.backend_executable}"
                )
        return EngineAvailability(self.engine_id, not problems, self.model_version, tuple(problems))

    def recognize(self, image: PreparedImage) -> EngineOcrResult:
        return self.recognize_many((image,))[0]

    def recognize_many(self, images: Sequence[PreparedImage]) -> tuple[EngineOcrResult, ...]:
        """Read every image with a single sidecar invocation.

        The GGUF pair behind these engines is 1-2 GB, and the sidecar loads it
        per invocation.  Sending a book's four surfaces together turns four
        model loads into one without keeping any model resident between books,
        so the mutual-exclusion contract in ``resources`` is unchanged.
        """

        if not images:
            return ()
        self.require_available()
        request = {
            "protocol": 1,
            "engine_id": self.engine_id,
            "model_path": str(self.model_path),
            "mmproj_path": str(self.mmproj_path),
            # ``image_path`` stays for single-image requests so an older sidecar
            # build keeps working; ``images`` is what a batch-aware one reads.
            "image_path": str(images[0].canonical_path),
            "images": [str(image.canonical_path) for image in images],
            "language_hints": ["tr", "en"],
            "require_positions": True,
            "preserve_unicode": True,
            "engine_profile": self.engine_profile,
            "prompt_protocol": self.prompt_protocol,
        }
        command = [self._resolved_executable() or self.executable, *self.extra_args]
        environment = os.environ.copy()
        environment.update(self.environment)
        started = time.perf_counter()
        try:
            completed = self._run_sidecar(command, request, environment, count=len(images))
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise OcrExecutionError(f"{self.engine_id} sidecar çalıştırılamadı: {exc}") from exc
        if completed.returncode:
            detail = completed.stderr.strip()[-2000:] or f"çıkış kodu {completed.returncode}"
            raise OcrExecutionError(f"{self.engine_id} sidecar başarısız: {detail}")
        try:
            envelope: dict[str, Any] = json.loads(completed.stdout)
        except (json.JSONDecodeError, TypeError) as exc:
            raise InvalidEngineResultError(
                f"{self.engine_id} sidecar geçerli JSON döndürmedi"
            ) from exc
        payloads = self._response_payloads(envelope, expected=len(images))
        elapsed_ms = round((time.perf_counter() - started) * 1000)
        stderr_tail = completed.stderr.strip()[-2000:]
        return tuple(
            self._result_from_payload(
                payload,
                image=image,
                # One process produced them all; splitting the wall clock evenly
                # keeps per-engine totals honest without inventing precision.
                duration_ms=elapsed_ms // len(images),
                stderr_tail=stderr_tail,
            )
            for payload, image in zip(payloads, images, strict=True)
        )

    def _run_sidecar(
        self,
        command: list[str],
        request: dict[str, Any],
        environment: dict[str, str],
        *,
        count: int,
    ) -> Any:
        """Run the sidecar so a timeout takes its ``llama-server`` down too.

        The sidecar spawns a llama-server holding one to two gigabytes.  Killing
        only the sidecar on timeout reparents that grandchild, which then keeps
        its memory and its loopback port while no longer being visible to the
        memory admission controller — the accounting silently loses the largest
        allocation in the process tree.  Its own start is a new session, so the
        whole group can be signalled at once.

        The budget must also exceed the sidecar's internal one, or the outer
        timeout fires first and the sidecar never reaches its own cleanup.
        """

        budget = self.startup_timeout_seconds + self.timeout_seconds * count
        process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
            start_new_session=True,
        )
        try:
            stdout, stderr = process.communicate(
                input=json.dumps(request, ensure_ascii=False),
                timeout=budget,
            )
        except subprocess.TimeoutExpired:
            _terminate_process_group(process)
            raise
        except BaseException:
            _terminate_process_group(process)
            raise
        return SimpleNamespace(returncode=process.returncode, stdout=stdout, stderr=stderr)

    def _response_payloads(
        self,
        envelope: dict[str, Any],
        *,
        expected: int,
    ) -> tuple[dict[str, Any], ...]:
        """Accept both the batch envelope and the single-result response."""

        results = envelope.get("results")
        payloads: tuple[dict[str, Any], ...]
        if isinstance(results, list):
            if any(not isinstance(item, dict) for item in results):
                raise InvalidEngineResultError(f"{self.engine_id} sidecar sonuç listesi bozuk")
            payloads = tuple(results)
        else:
            payloads = (envelope,)
        if len(payloads) != expected:
            raise InvalidEngineResultError(
                f"{self.engine_id} sidecar {expected} görüntü için {len(payloads)} sonuç döndürdü"
            )
        for payload in payloads:
            if payload.get("protocol") != 1:
                raise InvalidEngineResultError(
                    f"{self.engine_id} sidecar protokolü uyumsuz: {payload.get('protocol')!r}"
                )
            if payload.get("engine_id") != self.engine_id:
                raise InvalidEngineResultError(
                    f"{self.engine_id} sidecar motor kimliği uyuşmuyor: "
                    f"{payload.get('engine_id')!r}"
                )
        return payloads

    def _result_from_payload(
        self,
        payload: dict[str, Any],
        *,
        image: PreparedImage,
        duration_ms: int,
        stderr_tail: str,
    ) -> EngineOcrResult:
        tokens: list[OcrToken] = []
        for index, item in enumerate(payload.get("tokens", ())):
            try:
                text = str(item["text"])
                confidence = float(item.get("confidence", 0.5))
                polygon_payload = item.get("polygon")
                polygon = (
                    tuple((float(point[0]), float(point[1])) for point in polygon_payload)
                    if polygon_payload is not None
                    else None
                )
                tokens.append(
                    OcrToken(
                        token_id=str(item.get("token_id", f"{self.engine_id}:{index}")),
                        text=text,
                        confidence=max(0.0, min(1.0, confidence)),
                        polygon=polygon,
                        line_id=item.get("line_id"),
                        paragraph_id=item.get("paragraph_id"),
                        language=item.get("language"),
                    )
                )
            except (KeyError, TypeError, ValueError, IndexError) as exc:
                raise InvalidEngineResultError(
                    f"{self.engine_id} sidecar token #{index} bozuk"
                ) from exc
        raw_text = str(payload.get("raw_text", "\n".join(token.text for token in tokens)))
        warnings_payload = payload.get("warnings", ())
        metadata_payload = payload.get("metadata", {})
        if not isinstance(warnings_payload, list | tuple) or not isinstance(metadata_payload, dict):
            raise InvalidEngineResultError(
                f"{self.engine_id} sidecar warnings/metadata şeması bozuk"
            )
        return EngineOcrResult(
            engine_id=self.engine_id,
            model_version=self.model_version,
            image_sha256=image.image_sha256,
            variant="canonical",
            tokens=tuple(tokens),
            raw_text=raw_text,
            duration_ms=duration_ms,
            evidence_kind=self.evidence_kind,
            warnings=tuple(str(value) for value in warnings_payload),
            metadata={
                "sidecar_stderr": stderr_tail,
                "sidecar_metadata": metadata_payload,
                "engine_profile": self.engine_profile,
                "prompt_protocol": self.prompt_protocol,
            },
        )

    def runtime_settings(self) -> dict[str, Any]:
        return {
            "sidecar_protocol": 1,
            "prompt_protocol": self.prompt_protocol,
            "engine_profile": self.engine_profile,
            "timeout_seconds": self.timeout_seconds,
            "extra_args": list(self.extra_args),
            # The verified runtime bytes already participate in
            # ``artifact_digest``.  An installation path must not invalidate
            # thousands of cached covers when the same app bundle is moved or
            # upgraded in place.
            "backend_required": self.backend_executable is not None,
            "backend_kind": self.environment.get("KITAPKATALOG_VISION_BACKEND_KIND", "auto"),
        }


class PaddleOcrVlAdapter(LlamaVisionSidecarAdapter):
    engine_id = "paddleocr_vl"
    engine_profile = "layout-geometry-and-complex-cover"


class SuryaOcrAdapter(LlamaVisionSidecarAdapter):
    engine_id = "surya"
    engine_profile = "long-text-reading-order"
