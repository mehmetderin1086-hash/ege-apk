"""Tesseract 5 adapter using its TSV interface (no pytesseract dependency)."""

from __future__ import annotations

import csv
import io
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

from kitapkatalog.images import PreparedImage
from kitapkatalog.ocr.contracts import (
    EngineAvailability,
    EngineOcrResult,
    OcrEngineAdapter,
    OcrExecutionError,
    OcrToken,
    rectangular_polygon,
)
from kitapkatalog.ocr.variants import CLASSIC_VARIANT_LADDER, run_ladder


class TesseractAdapter(OcrEngineAdapter):
    engine_id = "tesseract"
    evidence_kind = "classic"
    adapter_revision = "tesseract-tsv-v2"
    _TSV_COLUMNS = frozenset(
        {
            "level",
            "page_num",
            "block_num",
            "par_num",
            "line_num",
            "word_num",
            "left",
            "top",
            "width",
            "height",
            "conf",
            "text",
        }
    )

    def __init__(
        self,
        *,
        executable: str | Path = "tesseract",
        tessdata_dir: Path | None = None,
        languages: str = "tur+eng",
        model_version: str = "5.5.2+tessdata_best",
        artifact_digest: str | None = None,
        psm: int = 11,
        timeout_seconds: int = 300,
        escalation_threshold: float = 0.80,
    ) -> None:
        if not 0.0 <= float(escalation_threshold) <= 1.0:
            raise ValueError("escalation_threshold 0 ile 1 arasında olmalıdır")
        self.executable = str(executable)
        self.tessdata_dir = Path(tessdata_dir) if tessdata_dir else None
        self.languages = languages
        self.model_version = model_version
        self.artifact_digest = artifact_digest
        self.psm = int(psm)
        self.timeout_seconds = int(timeout_seconds)
        self.escalation_threshold = float(escalation_threshold)

    def _resolved_executable(self) -> str | None:
        candidate = Path(self.executable)
        if candidate.parent != Path(".") or candidate.is_absolute():
            return str(candidate) if candidate.is_file() else None
        return shutil.which(self.executable)

    def availability(self) -> EngineAvailability:
        problems: list[str] = []
        executable = self._resolved_executable()
        if executable is None:
            problems.append(
                "Tesseract çalıştırılabilir dosyası bulunamadı; macOS için "
                "`brew install tesseract tesseract-lang` veya paketlenmiş runtime kullanın"
            )
        if self.tessdata_dir is not None:
            for language in self.languages.split("+"):
                trained = self.tessdata_dir / f"{language}.traineddata"
                if not trained.is_file():
                    problems.append(f"Tesseract dil modeli bulunamadı: {trained}")
        return EngineAvailability(self.engine_id, not problems, self.model_version, tuple(problems))

    def recognize(self, image: PreparedImage) -> EngineOcrResult:
        self.require_available()
        started = time.perf_counter()
        stderr_by_path: dict[str, str] = {}

        def recognize_at(image_path: Path) -> list[OcrToken]:
            tokens, stderr = self._run_tsv(image_path)
            stderr_by_path[str(image_path)] = stderr
            return tokens

        variant, tokens, attempts = run_ladder(
            recognize_at,
            image,
            threshold=self.escalation_threshold,
            ladder=CLASSIC_VARIANT_LADDER,
        )
        duration = round((time.perf_counter() - started) * 1000)
        winning_stderr = stderr_by_path[str(image.variant_paths[variant])]
        return EngineOcrResult(
            engine_id=self.engine_id,
            model_version=self.model_version,
            image_sha256=image.image_sha256,
            variant=variant,
            tokens=tuple(tokens),
            raw_text=" ".join(token.text for token in tokens),
            duration_ms=duration,
            evidence_kind=self.evidence_kind,
            metadata={"stderr": winning_stderr[-1000:], "variant_attempts": attempts},
        )

    def _run_tsv(self, image_path: Path) -> tuple[list[OcrToken], str]:
        command = [
            self._resolved_executable() or self.executable,
            str(image_path),
            "stdout",
            "-l",
            self.languages,
            "--psm",
            str(self.psm),
        ]
        if self.tessdata_dir:
            command.extend(["--tessdata-dir", str(self.tessdata_dir)])
        # The packaged tessdata directory intentionally contains only language
        # models.  Asking for the named ``tsv`` config makes Tesseract search
        # for ``tessdata/configs/tsv`` and, on some builds, return exit code 0
        # with plain text after failing to find it.  Set the underlying
        # parameter directly so the runtime has no external config dependency.
        command.extend(["-c", "tessedit_create_tsv=1"])
        try:
            completed = subprocess.run(
                command,
                check=False,
                capture_output=True,
                text=True,
                timeout=self.timeout_seconds,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise OcrExecutionError(f"Tesseract çalıştırılamadı: {exc}") from exc
        if completed.returncode:
            detail = completed.stderr.strip()[-1000:] or f"çıkış kodu {completed.returncode}"
            raise OcrExecutionError(f"Tesseract başarısız: {detail}")
        stderr = completed.stderr.strip()
        stderr_casefold = stderr.casefold()
        if "can't open tsv" in stderr_casefold or (
            "read_params_file" in stderr_casefold and "tsv" in stderr_casefold
        ):
            raise OcrExecutionError(
                f"Tesseract TSV yapılandırmasını açamadı: {stderr[-1000:] or 'ayrıntı yok'}"
            )

        tokens: list[OcrToken] = []
        stdout = completed.stdout.lstrip("\ufeff")
        reader = csv.DictReader(io.StringIO(stdout), delimiter="\t")
        fieldnames = {name.strip() for name in (reader.fieldnames or ()) if name}
        if not self._TSV_COLUMNS.issubset(fieldnames):
            preview = stdout.strip().splitlines()
            detail = preview[0][:200] if preview else "çıktı boş"
            raise OcrExecutionError(
                "Tesseract geçerli TSV başlığı döndürmedi; düz metin veya bozuk "
                f"çıktı alındı: {detail}"
            )
        text_rows = 0
        for index, row in enumerate(reader):
            text = (row.get("text") or "").strip()
            if text:
                text_rows += 1
            try:
                confidence_raw = float(row.get("conf", "-1"))
                left = float(row.get("left", "0"))
                top = float(row.get("top", "0"))
                width = float(row.get("width", "0"))
                height = float(row.get("height", "0"))
            except (TypeError, ValueError) as exc:
                raise OcrExecutionError("Tesseract TSV çıktısında sayısal alan bozuk") from exc
            if not text or confidence_raw < 0 or width <= 0 or height <= 0:
                continue
            line_id = ":".join(
                row.get(name, "0") for name in ("page_num", "block_num", "par_num", "line_num")
            )
            tokens.append(
                OcrToken(
                    token_id=f"{self.engine_id}:{index}",
                    text=text,
                    confidence=min(1.0, max(0.0, confidence_raw / 100.0)),
                    polygon=rectangular_polygon(left, top, left + width, top + height),
                    line_id=line_id,
                    paragraph_id=":".join(
                        row.get(name, "0") for name in ("page_num", "block_num", "par_num")
                    ),
                )
            )
        if not tokens and text_rows:
            raise OcrExecutionError(
                "Tesseract TSV çıktısı metin içerdiği halde geçerli konumlandırılmış token üretmedi"
            )
        return tokens, stderr

    def runtime_settings(self) -> dict[str, Any]:
        return {
            "adapter_revision": self.adapter_revision,
            "languages": self.languages,
            "psm": self.psm,
            "timeout_seconds": self.timeout_seconds,
            "output_format": "tsv-parameter",
            "variant_ladder": list(CLASSIC_VARIANT_LADDER),
            "variant_escalation_threshold": self.escalation_threshold,
        }
