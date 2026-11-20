"""Executable JSON-stdio bridge to a local ``llama-mtmd-cli`` runtime.

Run it without a packaging entry point:

``python -m kitapkatalog.ocr.sidecar_runtime``

The bridge performs no download and opens no outward socket.  It accepts one
request, starts one local llama.cpp-compatible process, and exits so the
operating system deterministically releases the large model.

A request names either a single ``image_path`` or an ``images`` group.  With a
group the server backend loads the model once and reads every image with it,
which is what makes a book's four surfaces cost one model load instead of four.
The response then carries a ``results`` list in request order; a single-image
request still answers with the bare payload.
"""

from __future__ import annotations

import base64
import html
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

ALLOWED_ENGINES = frozenset({"paddleocr_vl", "surya"})
PROMPT_PROTOCOL = "kitapkatalog-vision-json-v2"
ENGINE_PROFILES = {
    "paddleocr_vl": "layout-geometry-and-complex-cover",
    "surya": "long-text-reading-order",
}

# These are the models' published training-time prompts.  Asking either model
# for KitapKatalog's internal JSON schema degrades OCR and, for Surya, discards
# the normalized boxes it was trained to emit.
_ENGINE_PROMPTS = {
    "paddleocr_vl": "OCR:",
    "surya": (
        "OCR this image to HTML. Each block is a div with data-label and "
        "data-bbox (x0 y0 x1 y1, normalized 0-1000)."
    ),
}


class SidecarRuntimeError(RuntimeError):
    pass


def _read_request() -> dict[str, Any]:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError) as exc:
        raise SidecarRuntimeError(f"stdin üzerinde geçerli JSON istek yok: {exc}") from exc
    if payload.get("protocol") != 1:
        raise SidecarRuntimeError(f"desteklenmeyen protokol: {payload.get('protocol')!r}")
    engine_id = str(payload.get("engine_id", ""))
    if engine_id not in ALLOWED_ENGINES:
        raise SidecarRuntimeError(f"desteklenmeyen vision motoru: {engine_id!r}")
    expected_profile = ENGINE_PROFILES[engine_id]
    if payload.get("engine_profile") != expected_profile:
        raise SidecarRuntimeError(
            f"{engine_id} görev profili uyuşmuyor: {payload.get('engine_profile')!r}"
        )
    if payload.get("prompt_protocol") != PROMPT_PROTOCOL:
        raise SidecarRuntimeError(
            f"{engine_id} prompt protokolü uyuşmuyor: {payload.get('prompt_protocol')!r}"
        )
    for key in ("model_path", "mmproj_path", "image_path"):
        path = Path(str(payload.get(key, ""))).expanduser()
        if not path.is_file():
            raise SidecarRuntimeError(f"{key} bulunamadı: {path}")
        payload[key] = str(path.resolve())
    payload["images_requested_explicitly"] = payload.get("images") is not None
    payload["images"] = _read_image_paths(payload)
    return payload


def _read_image_paths(payload: dict[str, Any]) -> list[str]:
    """Resolve the image group, falling back to the single-image field.

    A request either names one ``image_path`` or a whole ``images`` group.  The
    group exists so one model load can serve a book's four surfaces; every entry
    is checked up front so a missing file fails before the model is loaded.
    """

    requested = payload.get("images")
    if requested is None:
        return [payload["image_path"]]
    if not isinstance(requested, list | tuple) or not requested:
        raise SidecarRuntimeError("images alanı boş olmayan bir liste olmalıdır")
    resolved: list[str] = []
    for index, entry in enumerate(requested):
        path = Path(str(entry)).expanduser()
        if not path.is_file():
            raise SidecarRuntimeError(f"images[{index}] bulunamadı: {path}")
        resolved.append(str(path.resolve()))
    return resolved


def _runtime_executable() -> str:
    configured = os.environ.get(
        "KITAPKATALOG_LLAMA_BACKEND",
        os.environ.get("KITAPKATALOG_LLAMA_MTMD_CLI", "llama-server"),
    )
    executable = shutil.which(configured)
    if executable is None:
        candidate = Path(configured).expanduser()
        executable = str(candidate.resolve()) if candidate.is_file() else None
    if executable is None:
        raise SidecarRuntimeError(
            "llama.cpp vision runtime bulunamadı. Paketlenmiş llama-server veya "
            "llama-mtmd-cli yolunu KITAPKATALOG_LLAMA_BACKEND değişkeninde belirtin"
        )
    return executable


def _common_values() -> tuple[str, str]:
    threads = os.environ.get("KITAPKATALOG_VISION_THREADS", "4")
    context = os.environ.get("KITAPKATALOG_VISION_CONTEXT", "16384")
    return threads, context


def _prompt_for(request: dict[str, Any]) -> str:
    return _ENGINE_PROMPTS[str(request["engine_id"])]


def _cli_command(executable: str, request: dict[str, Any], image_path: str) -> list[str]:
    threads, context = _common_values()
    return [
        executable,
        "--model",
        request["model_path"],
        "--mmproj",
        request["mmproj_path"],
        "--image",
        image_path,
        "--prompt",
        _prompt_for(request),
        "--temp",
        "0",
        "--ctx-size",
        context,
        "--threads",
        threads,
        "--n-predict",
        "8192",
        "--offline",
        "--no-display-prompt",
        "--no-show-timings",
        "--reasoning",
        "off",
    ]


def _offline_environment() -> dict[str, str]:
    environment = os.environ.copy()
    environment.update(
        {
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_DATASETS_OFFLINE": "1",
            "LLAMA_ARG_OFFLINE": "1",
        }
    )
    return environment


def _run_cli(executable: str, request: dict[str, Any]) -> tuple[list[str], str]:
    """Run the one-shot CLI backend once per image.

    ``llama-mtmd-cli`` exits after a single image, so a group here costs one
    model load per image.  The server backend is the one that amortises it; this
    path only keeps the batch request shape working.
    """

    outputs: list[str] = []
    logs: list[str] = []
    for image_path in request["images"]:
        try:
            completed = subprocess.run(
                _cli_command(executable, request, image_path),
                capture_output=True,
                text=True,
                check=False,
                timeout=int(os.environ.get("KITAPKATALOG_VISION_TIMEOUT", "900")),
                env=_offline_environment(),
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise SidecarRuntimeError(f"llama.cpp vision CLI çalıştırılamadı: {exc}") from exc
        if completed.returncode:
            detail = completed.stderr.strip()[-3000:] or f"çıkış kodu {completed.returncode}"
            raise SidecarRuntimeError(f"llama.cpp vision CLI başarısız: {detail}")
        outputs.append(completed.stdout)
        logs.append(completed.stderr)
    return outputs, "\n".join(logs)


def _unused_loopback_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def _server_command(
    executable: str,
    request: dict[str, Any],
    port: int,
) -> list[str]:
    threads, context = _common_values()
    return [
        executable,
        "--model",
        request["model_path"],
        "--mmproj",
        request["mmproj_path"],
        "--alias",
        f"kitapkatalog-{request['engine_id']}",
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
        "--ctx-size",
        context,
        "--threads",
        threads,
        "--parallel",
        "1",
        "--offline",
        "--no-webui",
        "--jinja",
        "--reasoning",
        "off",
    ]


def _wait_for_server(
    process: subprocess.Popen[bytes],
    port: int,
    *,
    timeout: float,
) -> None:
    deadline = time.monotonic() + timeout
    url = f"http://127.0.0.1:{port}/health"
    while time.monotonic() < deadline:
        return_code = process.poll()
        if return_code is not None:
            raise SidecarRuntimeError(
                f"llama-server model yüklerken kapandı (çıkış kodu {return_code})"
            )
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                if response.status == 200:
                    return
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            pass
        time.sleep(0.1)
    raise SidecarRuntimeError("llama-server model yükleme zaman aşımına uğradı")


def _server_completion(port: int, request: dict[str, Any], image_path: str, *, timeout: int) -> str:
    image_bytes = Path(image_path).read_bytes()
    suffix = Path(image_path).suffix.lower()
    media_type = "image/png" if suffix == ".png" else "image/jpeg"
    image_url = f"data:{media_type};base64,{base64.b64encode(image_bytes).decode('ascii')}"
    body = json.dumps(
        {
            "model": f"kitapkatalog-{request['engine_id']}",
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "image_url", "image_url": {"url": image_url}},
                        {"type": "text", "text": _prompt_for(request)},
                    ],
                }
            ],
            "temperature": 0,
            "max_tokens": 8192,
            "stream": False,
        },
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    http_request = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(http_request, timeout=timeout) as response:
            payload = json.load(response)
    except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
        raise SidecarRuntimeError(f"llama-server OCR isteği başarısız: {exc}") from exc
    try:
        content = payload["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as exc:
        raise SidecarRuntimeError("llama-server OpenAI yanıt şeması bozuk") from exc
    if isinstance(content, list):
        content = "".join(
            str(item.get("text", "")) if isinstance(item, dict) else str(item) for item in content
        )
    return str(content)


def _run_server(executable: str, request: dict[str, Any]) -> tuple[list[str], str]:
    """Load the model once and read every requested image with it.

    This is where a book's four surfaces stop costing four model loads.  The
    server still dies with this process, so no large model outlives the
    invocation and the caller's mutual-exclusion contract is untouched.
    """

    port = _unused_loopback_port()
    timeout = int(os.environ.get("KITAPKATALOG_VISION_TIMEOUT", "900"))
    with tempfile.TemporaryFile() as log:
        try:
            process = subprocess.Popen(
                _server_command(executable, request, port),
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=subprocess.STDOUT,
                env=_offline_environment(),
            )
        except OSError as exc:
            raise SidecarRuntimeError(f"llama-server başlatılamadı: {exc}") from exc
        outputs: list[str] = []
        try:
            _wait_for_server(process, port, timeout=min(timeout, 600))
            for image_path in request["images"]:
                outputs.append(_server_completion(port, request, image_path, timeout=timeout))
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        log.seek(0)
        runtime_log = log.read().decode("utf-8", errors="replace")
    return outputs, runtime_log


def _json_objects(text: str) -> list[dict[str, Any]]:
    decoder = json.JSONDecoder()
    candidates: list[dict[str, Any]] = []
    for index, character in enumerate(text):
        if character != "{":
            continue
        try:
            value, _end = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            candidates.append(value)
    return candidates


class _SuryaHtmlParser(HTMLParser):
    """Extract top-level Surya blocks without trusting or rendering model HTML."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.blocks: list[dict[str, Any]] = []
        self._depth = 0
        self._current: dict[str, Any] | None = None
        self._parts: list[str] = []

    def handle_starttag(
        self,
        tag: str,
        attrs: list[tuple[str, str | None]],
    ) -> None:
        values = dict(attrs)
        if self._current is None and tag == "div" and values.get("data-bbox"):
            self._current = {
                "bbox": values["data-bbox"],
                "label": values.get("data-label"),
            }
            self._parts = []
            self._depth = 1
            return
        if self._current is not None:
            if tag == "br":
                self._parts.append("\n")
                return
            self._depth += 1
            if tag in {"p", "li", "tr", "h1", "h2", "h3", "h4", "h5"}:
                self._parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if self._current is None:
            return
        self._depth -= 1
        if self._depth == 0:
            text = re.sub(r"[ \t]+", " ", "".join(self._parts))
            text = re.sub(r"\s*\n\s*", "\n", text).strip()
            if text:
                self._current["text"] = text
                self.blocks.append(self._current)
            self._current = None
            self._parts = []
        elif tag in {"p", "li", "tr", "h1", "h2", "h3", "h4", "h5"}:
            self._parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self._current is not None:
            self._parts.append(data)


def _strip_model_fences(value: str) -> str:
    cleaned = value.strip()
    cleaned = re.sub(r"^```(?:html|markdown|text|json)?\s*", "", cleaned, flags=re.I)
    cleaned = re.sub(r"\s*```$", "", cleaned)
    return cleaned.strip()


def _surya_tokens(
    raw_output: str,
    *,
    image_size: tuple[int, int] | None,
) -> list[dict[str, Any]]:
    parser = _SuryaHtmlParser()
    parser.feed(_strip_model_fences(raw_output))
    width, height = image_size or (0, 0)
    tokens: list[dict[str, Any]] = []
    for index, block in enumerate(parser.blocks):
        polygon = None
        try:
            x0, y0, x1, y1 = (
                float(value) for value in str(block["bbox"]).replace(",", " ").split()
            )
            if width > 0 and height > 0:
                polygon = [
                    [x0 / 1000 * width, y0 / 1000 * height],
                    [x1 / 1000 * width, y0 / 1000 * height],
                    [x1 / 1000 * width, y1 / 1000 * height],
                    [x0 / 1000 * width, y1 / 1000 * height],
                ]
        except (TypeError, ValueError):
            polygon = None
        tokens.append(
            {
                "token_id": f"vision:{index}",
                "text": str(block["text"]),
                "confidence": 0.5,
                "polygon": polygon,
                "line_id": f"block:{index}",
                "paragraph_id": f"block:{index}",
                "language": None,
            }
        )
    return tokens


def _plain_text_tokens(raw_output: str) -> list[dict[str, Any]]:
    cleaned = _strip_model_fences(raw_output)
    cleaned = html.unescape(re.sub(r"<[^>]+>", "\n", cleaned))
    lines = [line.strip() for line in cleaned.splitlines() if line.strip()]
    return [
        {
            "token_id": f"vision:{index}",
            "text": line,
            "confidence": 0.5,
            "polygon": None,
            "line_id": f"line:{index}",
            "paragraph_id": f"paragraph:{index}",
            "language": None,
        }
        for index, line in enumerate(lines)
    ]


def _normalize_response(
    raw_output: str,
    *,
    expected_engine_id: str | None = None,
    image_size: tuple[int, int] | None = None,
) -> dict[str, Any]:
    candidates = _json_objects(raw_output)
    payload = next(
        (
            candidate
            for candidate in reversed(candidates)
            if isinstance(candidate.get("tokens"), list)
        ),
        None,
    )
    if payload is None:
        tokens = (
            _surya_tokens(raw_output, image_size=image_size)
            if expected_engine_id == "surya"
            else _plain_text_tokens(raw_output)
        )
        if not tokens:
            raise SidecarRuntimeError("yerel vision model boş OCR çıktısı döndürdü")
        positioned = any(token["polygon"] is not None for token in tokens)
        warning = (
            "Surya HTML kutuları normalize edilerek çözümlendi"
            if positioned
            else "vision model konumsuz düz metin döndürdü"
        )
        return {
            "protocol": 1,
            "engine_id": expected_engine_id or "",
            "raw_text": "\n".join(token["text"] for token in tokens),
            "tokens": tokens,
            "warnings": [warning],
            "metadata": {
                "native_output": ("surya_html" if expected_engine_id == "surya" else "plain_text")
            },
        }
    reported_engine_id = payload.get("engine_id")
    if (
        expected_engine_id is not None
        and reported_engine_id is not None
        and reported_engine_id != expected_engine_id
    ):
        raise SidecarRuntimeError(f"vision model motor kimliği uyuşmuyor: {reported_engine_id!r}")
    normalized_tokens: list[dict[str, Any]] = []
    for index, token in enumerate(payload["tokens"]):
        if not isinstance(token, dict) or not str(token.get("text", "")).strip():
            continue
        polygon = token.get("polygon")
        if polygon is not None:
            if (
                not isinstance(polygon, list)
                or len(polygon) < 4
                or any(not isinstance(point, list | tuple) or len(point) != 2 for point in polygon)
            ):
                polygon = None
            else:
                try:
                    polygon = [[float(point[0]), float(point[1])] for point in polygon]
                except (TypeError, ValueError):
                    polygon = None
        try:
            confidence = max(0.0, min(1.0, float(token.get("confidence", 0.5))))
        except (TypeError, ValueError):
            confidence = 0.5
        normalized_tokens.append(
            {
                "token_id": str(token.get("token_id", f"vision:{index}")),
                "text": str(token["text"]),
                "confidence": confidence,
                "polygon": polygon,
                "line_id": token.get("line_id"),
                "paragraph_id": token.get("paragraph_id"),
                "language": token.get("language"),
            }
        )
    warnings = payload.get("warnings", ())
    if not isinstance(warnings, list | tuple):
        warnings = (str(warnings),)
    metadata = payload.get("metadata", {})
    if not isinstance(metadata, dict):
        metadata = {}
    return {
        "protocol": 1,
        "engine_id": expected_engine_id or str(reported_engine_id or ""),
        "raw_text": str(
            payload.get("raw_text", "\n".join(token["text"] for token in normalized_tokens))
        ),
        "tokens": normalized_tokens,
        "warnings": [str(value) for value in warnings],
        "metadata": metadata,
    }


def run_once() -> dict[str, Any]:
    """Answer one request, which may name a single image or a whole group.

    A single-image request still answers with the bare payload so an older
    caller keeps working; a group answers with a ``results`` list in request
    order.
    """

    request = _read_request()
    executable = _runtime_executable()
    backend_kind = os.environ.get("KITAPKATALOG_VISION_BACKEND_KIND", "auto").casefold()
    use_server = backend_kind == "server" or (
        backend_kind == "auto" and "server" in Path(executable).name.casefold()
    )
    outputs, runtime_log = (
        _run_server(executable, request) if use_server else _run_cli(executable, request)
    )
    image_paths = request["images"]
    if len(outputs) != len(image_paths):
        raise SidecarRuntimeError(
            f"{len(image_paths)} görüntü istendi ama {len(outputs)} çıktı üretildi"
        )
    from PIL import Image

    payloads: list[dict[str, Any]] = []
    for output, image_path in zip(outputs, image_paths, strict=True):
        with Image.open(image_path) as source_image:
            image_size = source_image.size
        payload = _normalize_response(
            output,
            expected_engine_id=request["engine_id"],
            image_size=image_size,
        )
        metadata = dict(payload["metadata"])
        metadata.update(
            {
                "engine_id": request["engine_id"],
                "engine_profile": request["engine_profile"],
                "prompt_protocol": request["prompt_protocol"],
                "backend_kind": "server" if use_server else "cli",
                "backend_executable": Path(executable).name,
                "batch_size": len(image_paths),
            }
        )
        if runtime_log.strip():
            metadata["runtime_log"] = runtime_log.strip()[-2000:]
        payload["metadata"] = metadata
        payloads.append(payload)
    if request.get("images_requested_explicitly"):
        return {"protocol": 1, "engine_id": request["engine_id"], "results": payloads}
    return payloads[0]


def main() -> int:
    try:
        response = run_once()
    except SidecarRuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except Exception as exc:  # defensive process boundary: never emit a traceback as JSON
        print(f"vision sidecar beklenmeyen hata: {exc}", file=sys.stderr)
        return 3
    json.dump(response, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
