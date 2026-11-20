"""BioProf command-line client and local server launcher."""

from __future__ import annotations

import asyncio
import json
import os
import threading
import webbrowser
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx
import typer
from rich.console import Console
from rich.table import Table

from bioprof.config import get_settings
from bioprof.providers.doctor import SystemDoctor

app = typer.Typer(help="BioProf yerel biyoloji ve tıp araştırma asistanı.", no_args_is_help=True)
models_app = typer.Typer(help="Model keşfi, indirme ve ölçüm komutları.")
providers_app = typer.Typer(help="Sağlayıcı tanılama komutları.")
dataset_app = typer.Typer(help="İncelenebilir fine-tuning veri setleri.")
train_app = typer.Typer(help="Colab/yerel eğitim çalışmaları ve model kayıt defteri.")
eval_app = typer.Typer(help="RAG ve model değerlendirmeleri.")
app.add_typer(models_app, name="models")
app.add_typer(providers_app, name="providers")
app.add_typer(dataset_app, name="dataset")
app.add_typer(train_app, name="train")
app.add_typer(eval_app, name="eval")

console = Console()


class CLIError(RuntimeError):
    pass


def _loopback(url: str) -> bool:
    return (urlparse(url).hostname or "").casefold() in {"127.0.0.1", "localhost", "::1"}


class APIClient:
    def __init__(self, base_url: str, *, allow_remote: bool = False, timeout: float = 300) -> None:
        if not _loopback(base_url) and not allow_remote:
            raise CLIError("Uzak BioProf API için --allow-remote açıkça verilmelidir.")
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def _headers(self) -> dict[str, str]:
        key = os.getenv("BIOPROF_API_KEY")
        return {"Authorization": f"Bearer {key}"} if key else {}

    def request(self, method: str, path: str, **kwargs: Any) -> httpx.Response:
        headers = dict(kwargs.pop("headers", {}))
        headers.update(self._headers())
        try:
            with httpx.Client(
                timeout=self.timeout,
                follow_redirects=False,
                trust_env=False,
            ) as client:
                response = client.request(
                    method,
                    f"{self.base_url}{path}",
                    headers=headers,
                    **kwargs,
                )
        except httpx.HTTPError as exc:
            raise CLIError(f"BioProf API bağlantısı başarısız: {exc.__class__.__name__}.") from exc
        if response.is_error:
            message = f"BioProf API HTTP {response.status_code} döndürdü."
            try:
                body = response.json()
                if isinstance(body, dict):
                    error = body.get("error") or body.get("detail")
                    if isinstance(error, dict) and isinstance(error.get("message"), str):
                        message += f" {error['message']}"
                    elif isinstance(error, str):
                        message += f" {error}"
            except ValueError:
                pass
            raise CLIError(message)
        return response

    def json(self, method: str, path: str, **kwargs: Any) -> Any:
        response = self.request(method, path, **kwargs)
        try:
            return response.json()
        except ValueError as exc:
            raise CLIError("BioProf API geçerli JSON döndürmedi.") from exc


def _client(api_url: str | None, allow_remote: bool = False) -> APIClient:
    settings = get_settings()
    return APIClient(
        api_url or f"http://{settings.host}:{settings.port}", allow_remote=allow_remote
    )


def _print_json(value: Any) -> None:
    console.print_json(json.dumps(value, ensure_ascii=False, default=str))


def _fail(error: Exception) -> None:
    console.print(f"[red]Hata:[/red] {error}", soft_wrap=True)
    raise typer.Exit(1)


@app.command()
def serve(
    host: str = typer.Option(None, help="Dinleme adresi; varsayılan ayarı kullanır."),
    port: int = typer.Option(None, help="Dinleme portu; varsayılan 8766."),
    open_browser: bool = typer.Option(False, "--open", help="Arayüzü tarayıcıda aç."),
    reload: bool = typer.Option(False, help="Geliştirme için otomatik yeniden yükleme."),
) -> None:
    """Yerel FastAPI uygulamasını başlat."""

    settings = get_settings()
    bind_host = host or settings.host
    bind_port = port or settings.port
    if bind_host not in {"127.0.0.1", "localhost", "::1"}:
        _fail(
            CLIError(
                "BioProf kişisel yerel uygulamadır; --host yalnız 127.0.0.1, "
                "localhost veya ::1 olabilir."
            )
        )
    if open_browser:
        threading.Timer(1.0, lambda: webbrowser.open(f"http://127.0.0.1:{bind_port}")).start()
    try:
        import uvicorn

        # String import keeps reload support and avoids constructing app twice.
        uvicorn.run(
            "bioprof.app:create_app",
            factory=True,
            host=bind_host,
            port=bind_port,
            reload=reload,
        )
    except (ImportError, RuntimeError) as exc:
        _fail(exc)


@app.command()
def doctor(
    json_output: bool = typer.Option(False, "--json", help="Makine okunur JSON çıktı."),
    active: bool = typer.Option(
        False,
        "--active-provider-probe",
        help="CLI Proxy'ye en fazla bir tokenlık gerçek upstream istek de gönder.",
    ),
) -> None:
    """M4 kaynaklarını, bağımlılıkları, SesLab'ı ve CLI Proxy'yi denetle."""

    settings = get_settings()
    report = asyncio.run(
        SystemDoctor(
            data_dir=settings.data_dir,
            seslab_base_url=settings.seslab_base_url,
            cliproxy_base_url=settings.cliproxy_base_url,
        ).run(active_provider_probe=active)
    )
    value = report.model_dump()
    if json_output:
        _print_json(value)
        return
    hardware = value["hardware"]
    console.print(
        f"[bold]BioProf doctor[/bold] — {hardware['chip']} · "
        f"{hardware['memory_gib']} GiB RAM · {hardware['disk_free_gib']} GiB boş"
    )
    table = Table("Denetim", "Durum", "Ayrıntı")
    for check in value["checks"]:
        marker = "[green]hazır[/green]" if check["ok"] else "[yellow]eksik/kapalı[/yellow]"
        table.add_row(check["name"], marker, check["status"])
    console.print(table)


@app.command()
def ingest(
    path: Path = typer.Argument(..., exists=True, readable=True, dir_okay=False),
    notebook: str = typer.Option(..., "--notebook", "-n"),
    api_url: str | None = typer.Option(None),
) -> None:
    """Bir dosyayı notebook'a ekle; iş tamamlanmasını beklemez."""

    try:
        with path.open("rb") as handle:
            result = _client(api_url).json(
                "POST",
                f"/api/v1/notebooks/{notebook}/sources",
                files={"file": (path.name, handle, "application/octet-stream")},
            )
        _print_json(result)
    except (OSError, CLIError) as exc:
        _fail(exc)


@app.command()
def search(
    query: str = typer.Argument(...),
    notebook: str = typer.Option(..., "--notebook", "-n"),
    limit: int = typer.Option(20, min=1, max=100),
    api_url: str | None = typer.Option(None),
) -> None:
    """Kaynak parçalarında hibrit arama yap."""

    try:
        _print_json(
            _client(api_url).json(
                "POST",
                f"/api/v1/notebooks/{notebook}/search",
                json={"query": query, "limit": limit},
            )
        )
    except CLIError as exc:
        _fail(exc)


@app.command()
def ask(
    question: str = typer.Argument(...),
    notebook: str = typer.Option(..., "--notebook", "-n"),
    mode: str = typer.Option("strict", help="strict, hybrid, research veya raw."),
    provider: str | None = typer.Option(None),
    model: str | None = typer.Option(None),
    speak: bool = typer.Option(False, help="Yanıt için Murat ses işi oluştur."),
    api_url: str | None = typer.Option(None),
) -> None:
    """Notebook kaynaklarına dayalı bir soru sor."""

    payload = {
        "question": question,
        "mode": mode,
        "provider": provider,
        "model": model,
        "speak": speak,
    }
    try:
        result = _client(api_url).json(
            "POST", f"/api/v1/notebooks/{notebook}/ask", json=payload
        )
        if isinstance(result, dict) and result.get("answer_markdown"):
            console.print(result["answer_markdown"])
            console.print(f"[dim]trace: {result.get('trace_id', '-')}[/dim]")
        else:
            _print_json(result)
    except CLIError as exc:
        _fail(exc)


@app.command()
def chat(
    notebook: str = typer.Option(..., "--notebook", "-n"),
    mode: str = typer.Option("strict"),
    api_url: str | None = typer.Option(None),
) -> None:
    """Ctrl-D/boş satıra kadar etkileşimli kaynaklı sohbet."""

    console.print("BioProf sohbeti. Çıkmak için boş satır veya Ctrl-D.")
    while True:
        try:
            question = typer.prompt("Siz", prompt_suffix=": ").strip()
        except (EOFError, KeyboardInterrupt):
            console.print()
            return
        if not question:
            return
        try:
            result = _client(api_url).json(
                "POST",
                f"/api/v1/notebooks/{notebook}/ask",
                json={"question": question, "mode": mode},
            )
            console.print(f"[bold]BioProf:[/bold] {result.get('answer_markdown', result)}")
        except CLIError as exc:
            console.print(f"[red]Hata:[/red] {exc}")


@app.command()
def transcribe(
    path: Path = typer.Argument(..., exists=True, readable=True, dir_okay=False),
    language: str | None = typer.Option("tr"),
    response_format: str = typer.Option("json"),
    api_url: str | None = typer.Option(None),
) -> None:
    """SesLab/MLX-Whisper üzerinden ses yazıya çevir."""

    try:
        with path.open("rb") as handle:
            response = _client(api_url).request(
                "POST",
                "/v1/audio/transcriptions",
                files={"file": (path.name, handle, "application/octet-stream")},
                data={
                    "model": "mlx-whisper",
                    "language": language,
                    "response_format": response_format,
                },
            )
        if response_format in {"text", "srt", "vtt"}:
            console.print(response.text)
        else:
            _print_json(response.json())
    except (OSError, ValueError, CLIError) as exc:
        _fail(exc)


@app.command()
def speak(
    text: str = typer.Argument(...),
    output: Path = typer.Option(Path("murat.wav"), "--output", "-o"),
    voice: str = typer.Option("Murat"),
    strict: bool = typer.Option(False, help="Whisper eksik-kelime doğrulaması iste."),
    force: bool = typer.Option(False, help="Var olan çıktı dosyasının üstüne yaz."),
    api_url: str | None = typer.Option(None),
) -> None:
    """Murat XTTS ile ses üret."""

    if output.exists() and not force:
        _fail(CLIError(f"Çıktı zaten var: {output}. Üzerine yazmak için --force kullanın."))
    audio_format = output.suffix.lstrip(".").lower() or "wav"
    if audio_format not in {"wav", "mp3", "opus", "aac", "flac", "pcm"}:
        _fail(CLIError("Çıktı uzantısı wav, mp3, opus, aac, flac veya pcm olmalıdır."))
    try:
        response = _client(api_url).request(
            "POST",
            "/v1/audio/speech",
            json={
                "model": "xtts-v2",
                "input": text,
                "voice": voice,
                "response_format": audio_format,
                "verify": strict,
            },
        )
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(response.content)
        console.print(f"[green]Oluşturuldu:[/green] {output.resolve()}")
    except (OSError, CLIError) as exc:
        _fail(exc)


@models_app.command("list")
def models_list(api_url: str | None = typer.Option(None)) -> None:
    try:
        _print_json(_client(api_url).json("GET", "/v1/models"))
    except CLIError as exc:
        _fail(exc)


@models_app.command("pull")
def models_pull(model: str, api_url: str | None = typer.Option(None)) -> None:
    """Sunucunun doğrulanmış model indirme işini başlat."""

    try:
        _print_json(_client(api_url).json("POST", "/api/v1/models/pull", json={"model": model}))
    except CLIError as exc:
        _fail(exc)


@models_app.command("benchmark")
def models_benchmark(model: str, api_url: str | None = typer.Option(None)) -> None:
    try:
        _print_json(
            _client(api_url).json("POST", "/api/v1/models/benchmark", json={"model": model})
        )
    except CLIError as exc:
        _fail(exc)


@providers_app.command("test")
def providers_test(
    name: str | None = typer.Argument(None),
    active: bool = typer.Option(False, help="Gerçek, küçük upstream isteklerine izin ver."),
    api_url: str | None = typer.Option(None),
) -> None:
    try:
        _print_json(
            _client(api_url).json(
                "POST", "/api/v1/providers/test", json={"provider": name, "active": active}
            )
        )
    except CLIError as exc:
        _fail(exc)


def _job_command(path: str, payload: dict[str, Any], api_url: str | None) -> None:
    try:
        _print_json(_client(api_url).json("POST", path, json=payload))
    except CLIError as exc:
        _fail(exc)


@dataset_app.command("build")
def dataset_build(notebook: str, name: str, api_url: str | None = typer.Option(None)) -> None:
    _job_command("/api/v1/datasets", {"notebook_id": notebook, "name": name}, api_url)


@dataset_app.command("validate")
def dataset_validate(dataset_id: str, api_url: str | None = typer.Option(None)) -> None:
    _job_command(f"/api/v1/datasets/{dataset_id}/validate", {}, api_url)


@train_app.command("export-colab")
def train_export_colab(run_id: str, api_url: str | None = typer.Option(None)) -> None:
    _job_command(f"/api/v1/training-runs/{run_id}/export-colab", {}, api_url)


@train_app.command("import")
def train_import(
    manifest: Path = typer.Argument(..., exists=True, readable=True, dir_okay=False),
    artifact: Path | None = typer.Option(
        None,
        "--artifact",
        exists=True,
        readable=True,
        help="PEFT adapter dosyası veya dizini; candidate kaydı için gereklidir.",
    ),
    api_url: str | None = typer.Option(None),
) -> None:
    try:
        content = json.loads(manifest.read_text(encoding="utf-8"))
        if not isinstance(content, dict):
            raise CLIError("Eğitim manifesti bir JSON nesnesi olmalıdır.")
        if artifact is not None:
            content["artifact_path"] = str(artifact.resolve())
        _print_json(
            _client(api_url).json(
                "POST",
                "/api/v1/training-runs/import",
                files={
                    "file": (
                        manifest.name,
                        json.dumps(content, ensure_ascii=False).encode(),
                        "application/json",
                    )
                },
            )
        )
    except (OSError, json.JSONDecodeError, CLIError) as exc:
        _fail(exc)


@train_app.command("promote")
def train_promote(run_id: str, api_url: str | None = typer.Option(None)) -> None:
    _job_command(f"/api/v1/training-runs/{run_id}/promote", {}, api_url)


@train_app.command("rollback")
def train_rollback(model_id: str, api_url: str | None = typer.Option(None)) -> None:
    _job_command(f"/api/v1/models/{model_id}/rollback", {}, api_url)


@eval_app.command("run")
def eval_run(model_id: str, suite: str = "gold", api_url: str | None = typer.Option(None)) -> None:
    _job_command("/api/v1/eval-runs", {"model_id": model_id, "suite": suite}, api_url)


@eval_app.command("report")
def eval_report(run_id: str, api_url: str | None = typer.Option(None)) -> None:
    try:
        _print_json(_client(api_url).json("GET", f"/api/v1/eval-runs/{run_id}"))
    except CLIError as exc:
        _fail(exc)


@app.command("nli-esik")
def nli_esik(
    altin_set: Path = typer.Option(
        Path("tests/data/nli_altin_set.jsonl"),
        help="Etiketli iddia-kanıt çiftleri (jsonl).",
    ),
) -> None:
    """NLI hakemi eşiğini altın set üzerinde tarar ve önerilen eşiği basar.

    `nli_enabled` bu ölçüm koşulup temiz bir eşik görülmeden açılmamalı.
    """
    from bioprof.evaluation.nli_esik import altin_seti_yukle, esik_taramasi, rapor_metni

    settings = get_settings()
    if not altin_set.exists():
        typer.echo(f"Altın set bulunamadı: {altin_set}", err=True)
        raise typer.Exit(code=1)
    kayitlar = altin_seti_yukle(altin_set)
    typer.echo(f"{len(kayitlar)} çift yükleniyor; model: {settings.nli_model}")
    rapor = esik_taramasi(
        kayitlar, model=settings.nli_model, karsi_esik=settings.nli_karsi_esik
    )
    typer.echo(rapor_metni(rapor))
    raise typer.Exit(code=0 if rapor.secilen is not None else 2)


@app.command()
def backup(
    output: Path = typer.Argument(...),
    force: bool = typer.Option(False),
    api_url: str | None = typer.Option(None),
) -> None:
    """Sunucunun tutarlı notebook yedeğini indir."""

    if output.exists() and not force:
        _fail(CLIError("Yedek hedefi zaten var; --force olmadan üzerine yazılmaz."))
    try:
        response = _client(api_url).request("POST", "/api/v1/backup")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(response.content)
        output.chmod(0o600)
        console.print(f"[green]Yedek oluşturuldu:[/green] {output.resolve()}")
    except (OSError, CLIError) as exc:
        _fail(exc)


@app.command()
def restore(
    archive: Path = typer.Argument(..., exists=True, readable=True, dir_okay=False),
    yes: bool = typer.Option(False, "--yes", help="Geri yüklemeyi açıkça onayla."),
    api_url: str | None = typer.Option(None),
) -> None:
    """Doğrulanmış BioProf yedeğini geri yükle; --yes zorunludur."""

    if not yes:
        _fail(CLIError("Geri yükleme veri durumunu değiştirir; --yes zorunludur."))
    try:
        with archive.open("rb") as handle:
            _print_json(
                _client(api_url).json(
                    "POST",
                    "/api/v1/restore",
                    files={"file": (archive.name, handle, "application/zip")},
                )
            )
    except (OSError, CLIError) as exc:
        _fail(exc)


if __name__ == "__main__":
    app()
