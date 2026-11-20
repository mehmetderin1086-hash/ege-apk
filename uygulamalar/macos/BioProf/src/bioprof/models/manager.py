from __future__ import annotations

import asyncio
import builtins
import importlib
import importlib.util
import json
import os
import shutil
import socket
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Literal

import httpx

EngineName = Literal["mlx-lm", "mlx-vlm", "llama.cpp", "external"]


@dataclass(frozen=True, slots=True)
class ModelProfile:
    id: str
    title: str
    repo_id: str
    engine: EngineName
    approximate_disk_gib: float
    minimum_memory_gib: int
    license: str
    purpose: str
    remote_code_allowed: bool = False
    # Ağırlıkları BioProf cache'i dışında hazır duran modeller (pull gerekmez).
    local_dir: str | None = None
    # Hugging Face önbelleğinde hazır olan modeller: motor komutuna dizin
    # yerine depo kimliği geçilir, indirme yapılmaz (HF_HUB_OFFLINE).
    hf_cached: bool = False

    def model_dump(self) -> dict[str, Any]:
        return asdict(self)


def model_catalog() -> list[ModelProfile]:
    return [
        ModelProfile(
            id="sohbet",
            title="Qwen3.5 4B (Türkçe sohbet ve yazım)",
            repo_id="mlx-community/Qwen3.5-4B-MLX-4bit",
            engine="mlx-lm",
            approximate_disk_gib=2.9,
            minimum_memory_gib=8,
            license="Apache-2.0",
            purpose="Kaynaklardan akıcı Türkçe yanıt, Stüdyo metni ve podcast senaryosu",
            hf_cached=True,
        ),
        ModelProfile(
            id="biyo",
            title="Biyo-MLX v1 (biyoloji sorusu fine-tune)",
            repo_id="local/biyo-mlx-v1",
            engine="mlx-lm",
            approximate_disk_gib=2.2,
            minimum_memory_gib=8,
            license="Apache-2.0",
            # Ölçüldü: çoktan seçmeli soru çözmeye göre ayarlandığı için
            # kaynak özetlerken kanıt metnini olduğu gibi kopyalıyor.
            purpose="Biyoloji sorusu çözme; serbest yazımda kaynağı kopyalama eğilimi var",
            local_dir="~/.biyo-cozucu/modeller/biyo-mlx-v1",
        ),
        ModelProfile(
            id="derin",
            title="Qwen3.5 9B 4-bit (derin akıl yürütme)",
            repo_id="local/Qwen3.5-9B-4bit",
            engine="mlx-lm",
            approximate_disk_gib=5.6,
            minimum_memory_gib=16,
            license="Apache-2.0",
            purpose="Daha derin akıl yürütme; XTTS ile eşzamanlı kullanmayın",
            local_dir="~/.biyo-cozucu/modeller/Qwen3.5-9B-4bit",
        ),
        ModelProfile(
            id="biomedical",
            title="MedGemma 4B IT MLX",
            repo_id="local/medgemma-4b-it-mlx",
            engine="mlx-lm",
            approximate_disk_gib=2.8,
            minimum_memory_gib=12,
            license="Health AI Developer Foundations",
            purpose="Yalnız eğitim/araştırma amaçlı biyomedikal karşılaştırma",
            local_dir="~/Developer/medical-finetune/models/medgemma-4b-it-mlx",
        ),
    ]


def _hf_cache_dir() -> Path:
    override = os.environ.get("HF_HUB_CACHE") or os.environ.get("HF_HOME")
    if override:
        base = Path(override).expanduser()
        return base if base.name == "hub" else base / "hub"
    return Path.home() / ".cache" / "huggingface" / "hub"


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as value:
        value.bind(("127.0.0.1", 0))
        return int(value.getsockname()[1])


class LocalModelManager:
    """Starts one explicit loopback model server; never downloads or falls back silently."""

    def __init__(self, cache_dir: Path, *, mlx_python: Path | None = None) -> None:
        self.cache_dir = cache_dir
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        # BioProf venv'inde mlx yoksa mlx sunucuları bu dış yorumlayıcıyla
        # başlar (komşu projenin venv'i); BioProf'a mlx kurulumu gerekmez.
        self.mlx_python = mlx_python
        self._process: asyncio.subprocess.Process | None = None
        self._active: dict[str, Any] | None = None
        self._lock = asyncio.Lock()
        self._log_path: Path | None = None

    def profile_path(self, profile: ModelProfile) -> Path:
        if profile.local_dir:
            return Path(profile.local_dir).expanduser()
        if profile.hf_cached:
            return _hf_cache_dir() / f"models--{profile.repo_id.replace('/', '--')}"
        return self.cache_dir / profile.repo_id.replace("/", "--")

    def model_argument(self, profile: ModelProfile) -> str:
        """Motora geçilecek değer: HF önbelleğinde depo kimliği, aksi hâlde yol."""
        return profile.repo_id if profile.hf_cached else str(self.profile_path(profile))

    def list(self) -> list[dict[str, Any]]:
        values = []
        for profile in model_catalog():
            local_path = self.profile_path(profile)
            data = profile.model_dump()
            revision_path = local_path / ".bioprof-model.json"
            revision = None
            if revision_path.is_file():
                try:
                    revision = json.loads(revision_path.read_text(encoding="utf-8")).get(
                        "revision"
                    )
                except (OSError, ValueError):
                    revision = None
            data.update(
                {
                    "downloaded": local_path.exists(),
                    "local_path": str(local_path),
                    "engine_available": self.engine_available(profile.engine),
                    "active": bool(self._active and self._active["profile"] == profile.id),
                    "revision": revision,
                }
            )
            values.append(data)
        return values

    def engine_available(self, engine: EngineName) -> bool:
        if engine == "llama.cpp":
            return shutil.which("llama-server") is not None
        if engine in {"mlx-lm", "mlx-vlm"}:
            module = "mlx_lm" if engine == "mlx-lm" else "mlx_vlm"
            if importlib.util.find_spec(module) is not None:
                return True
            return self.mlx_python is not None and self.mlx_python.is_file()
        return True

    def resolve_profile(self, profile_id: str) -> ModelProfile:
        for profile in model_catalog():
            if profile.id == profile_id:
                return profile
        raise ValueError(f"Bilinmeyen model profili: {profile_id}")

    def pull(self, profile_id: str) -> Path:
        """Explicit user-triggered download, pinned to the configured repository revision."""
        profile = self.resolve_profile(profile_id)
        try:
            hub = importlib.import_module("huggingface_hub")
            snapshot_download = hub.snapshot_download
            api_class = hub.HfApi
        except (ImportError, AttributeError) as exc:
            raise RuntimeError(
                "Model indirmek için `uv sync --extra models` çalıştırın."
            ) from exc
        target = self.cache_dir / profile.repo_id.replace("/", "--")
        revision = str(api_class().model_info(profile.repo_id).sha or "")
        if len(revision) < 40:
            raise RuntimeError("Hugging Face değişmez model commit SHA döndürmedi")
        snapshot_download(
            repo_id=profile.repo_id,
            revision=revision,
            local_dir=target,
            local_dir_use_symlinks=False,
        )
        metadata_path = target / ".bioprof-model.json"
        metadata_path.write_text(
            json.dumps(
                {"repo_id": profile.repo_id, "revision": revision},
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        metadata_path.chmod(0o600)
        return target

    async def start(
        self,
        profile_id: str,
        *,
        model_path: Path | None = None,
        engine: EngineName | None = None,
        port: int | None = None,
        context_size: int = 8192,
    ) -> dict[str, Any]:
        profile = self.resolve_profile(profile_id)
        selected_engine = engine or profile.engine
        selected_path = model_path or self.profile_path(profile)
        if not selected_path.exists():
            raise RuntimeError(
                f"Model yerelde yok: {selected_path}. "
                f"Önce açıkça `models pull {profile_id}` çalıştırın."
            )
        if not self.engine_available(selected_engine):
            raise RuntimeError(f"Yerel model motoru kurulu değil: {selected_engine}")
        model_argument = (
            str(model_path) if model_path is not None else self.model_argument(profile)
        )

        async with self._lock:
            await self.stop()
            selected_port = port or _free_port()
            command = self._command(
                selected_engine, model_argument, selected_port, context_size=context_size
            )
            logs_dir = self.cache_dir / "logs"
            logs_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
            self._log_path = logs_dir / f"{profile.id}-{int(time.time())}.log"
            descriptor = os.open(
                self._log_path,
                os.O_WRONLY | os.O_CREAT | os.O_APPEND,
                0o600,
            )
            try:
                with os.fdopen(descriptor, "ab", closefd=True) as model_log:
                    self._process = await asyncio.create_subprocess_exec(
                        *command,
                        stdout=model_log,
                        stderr=model_log,
                        env={
                            **os.environ,
                            "TOKENIZERS_PARALLELISM": "false",
                            # Motor komutu depo kimliği alsa bile ağa çıkmaz:
                            # ağırlıklar yalnız yerel önbellekten okunur.
                            "HF_HUB_OFFLINE": "1",
                            "TRANSFORMERS_OFFLINE": "1",
                        },
                    )
            except BaseException:
                self._log_path = None
                raise
            endpoint = f"http://127.0.0.1:{selected_port}"
            try:
                await self._wait_ready(endpoint, timeout=180)
            except BaseException:
                # CancelledError BaseException altındadır: yalnız Exception
                # yakalamak, iptal edilen bir başlatmada model sürecini
                # arkada çalışır hâlde bırakırdı.
                await self.stop()
                raise
            self._active = {
                "profile": profile.id,
                "engine": selected_engine,
                "model_path": str(selected_path),
                "endpoint": endpoint,
                "pid": self._process.pid,
                "log_path": str(self._log_path),
            }
            return dict(self._active)

    async def stop(self) -> None:
        process = self._process
        self._active = None
        if process is None or process.returncode is not None:
            self._process = None
            return
        process.terminate()
        try:
            await asyncio.wait_for(process.wait(), timeout=10)
        except TimeoutError:
            process.kill()
            await process.wait()
        except BaseException:
            # Bekleme iptal edilirse referans korunur; aksi hâlde sonraki
            # stop() çağrısı süreci bulamaz ve zombi bırakırdı.
            process.kill()
            raise
        finally:
            if process.returncode is not None:
                self._process = None

    def _command(
        self, engine: EngineName, model_path: str, port: int, *, context_size: int
    ) -> builtins.list[str]:
        if engine == "llama.cpp":
            executable = shutil.which("llama-server")
            if not executable:
                raise RuntimeError("llama-server bulunamadı")
            return [
                executable,
                "--host",
                "127.0.0.1",
                "--port",
                str(port),
                "--model",
                model_path,
                "--ctx-size",
                str(context_size),
                "--jinja",
            ]
        module = "mlx_lm.server" if engine == "mlx-lm" else "mlx_vlm.server"
        in_process = importlib.util.find_spec(module.split(".", 1)[0]) is not None
        python = sys.executable if in_process else str(self.mlx_python or sys.executable)
        return [
            python,
            "-m",
            module,
            "--model",
            model_path,
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
        ]

    @staticmethod
    async def _wait_ready(endpoint: str, timeout: float) -> None:
        deadline = time.monotonic() + timeout
        async with httpx.AsyncClient(timeout=3, trust_env=False) as client:
            while time.monotonic() < deadline:
                try:
                    response = await client.get(f"{endpoint}/v1/models")
                    if response.is_success:
                        return
                except httpx.HTTPError:
                    pass
                await asyncio.sleep(0.5)
        raise TimeoutError("Yerel model sunucusu zamanında hazır olmadı.")

    async def benchmark(self, endpoint: str, model: str) -> dict[str, Any]:
        payload = {
            "model": model,
            "messages": [{"role": "user", "content": "Yalnızca 'hazır' yaz."}],
            "max_tokens": 16,
            "stream": False,
        }
        started = time.perf_counter()
        async with httpx.AsyncClient(timeout=120, trust_env=False) as client:
            response = await client.post(
                f"{endpoint.rstrip('/')}/v1/chat/completions", json=payload
            )
            response.raise_for_status()
        elapsed = time.perf_counter() - started
        body = response.json()
        usage = body.get("usage", {})
        completion_tokens = int(usage.get("completion_tokens", 0) or 0)
        return {
            "elapsed_seconds": round(elapsed, 3),
            "completion_tokens": completion_tokens,
            "tokens_per_second": (
                round(completion_tokens / elapsed, 3) if completion_tokens else None
            ),
            "response_model": body.get("model"),
        }
