from __future__ import annotations

import contextlib
import hashlib
import json
import os
import re
import tempfile
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from bioprof.training.dataset import DatasetManifest


class QLoRAConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    base_model: str = "Qwen/Qwen3.5-4B"
    base_revision: str
    trainer: Literal["unsloth", "llamafactory"] = "unsloth"
    max_sequence_length: int = Field(default=2048, ge=256, le=32768)
    lora_rank: int = Field(default=32, ge=1, le=256)
    lora_alpha: int = Field(default=64, ge=1, le=512)
    lora_dropout: float = Field(default=0.05, ge=0, lt=1)
    learning_rate: float = Field(default=2e-4, gt=0, le=0.1)
    epochs: float = Field(default=2.0, gt=0, le=20)
    per_device_batch_size: int = Field(default=2, ge=1, le=64)
    gradient_accumulation_steps: int = Field(default=8, ge=1, le=256)
    seed: int = 42
    output_dir: str = "/content/bioprof-output"
    use_4bit: bool = True
    double_quantization: bool = True
    quantization_type: Literal["nf4"] = "nf4"
    target_modules: Literal["all-linear"] = "all-linear"

    @model_validator(mode="after")
    def supported_recipe(self) -> QLoRAConfig:
        if not re.fullmatch(r"[0-9a-fA-F]{40,64}", self.base_revision):
            raise ValueError("base_revision must be an immutable 40-64 character commit SHA")
        if self.trainer == "llamafactory" and self.lora_dropout != 0.05:
            # This is allowed, but makes explicit that the manifest remains the authority.
            pass
        return self


class ColabTrainingManifest(BaseModel):
    run_id: str
    generated_at: datetime
    dataset_hash: str
    dataset_schema: str
    source_ids: list[str]
    licenses: list[str]
    base_model: str
    base_revision: str
    method: str = "qlora_sft"
    configuration: dict[str, object]
    expected_outputs: list[str]
    reproducibility_hash: str
    educational_noncommercial: bool = True


def _atomic_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except Exception:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)
        raise


def _code(source: str) -> dict[str, object]:
    return {
        "cell_type": "code",
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": [line + "\n" for line in source.strip().splitlines()],
    }


def _markdown(source: str) -> dict[str, object]:
    return {
        "cell_type": "markdown",
        "metadata": {},
        "source": [line + "\n" for line in source.strip().splitlines()],
    }


def _unsloth_notebook(config: QLoRAConfig) -> dict[str, object]:
    config_json = json.dumps(config.model_dump(), ensure_ascii=False)
    cells = [
        _markdown(
            "# BioProf QLoRA / SFT\n\n"
            "Bu defter yalnız incelenmiş ve hakları onaylanmış BioProf veri paketini kullanır. "
            "Çalıştırmadan önce `dataset_manifest.json` lisanslarını ve split ailelerini inceleyin."
        ),
        _code(
            '!pip -q install "unsloth[colab-new]==2026.7.3" '
            '"transformers==5.14.1" "datasets==5.0.0" "trl==1.8.0" '
            '"peft==0.19.1" "accelerate==1.14.0"'
        ),
        _code(
            "import json, os, random\n"
            "from pathlib import Path\n"
            f"CONFIG = json.loads({config_json!r})\n"
            "DATA_DIR = Path('/content/bioprof-dataset')\n"
            "manifest_path = DATA_DIR / 'dataset_manifest.json'\n"
            "assert manifest_path.exists(), 'Upload the dataset bundle first'\n"
            "manifest = json.loads((DATA_DIR / 'dataset_manifest.json').read_text())\n"
            "print('Dataset:', manifest['dataset_hash'], manifest['split_counts'])"
        ),
        _code(
            "from datasets import load_dataset\n"
            "files = {name: str(DATA_DIR / filename)\n"
            "         for name, filename in manifest['files'].items()}\n"
            "dataset = load_dataset('json', data_files=files)\n"
            "train_families = set(manifest['split_families']['train'])\n"
            "validation_families = set(manifest['split_families']['validation'])\n"
            "test_families = set(manifest['split_families']['test'])\n"
            "assert not (train_families & validation_families)\n"
            "assert not (train_families & test_families)\n"
            "dataset"
        ),
        _code(
            "from unsloth import FastLanguageModel\n"
            "model, tokenizer = FastLanguageModel.from_pretrained(\n"
            "    model_name=CONFIG['base_model'],\n"
            "    revision=CONFIG['base_revision'],\n"
            "    max_seq_length=CONFIG['max_sequence_length'],\n"
            "    load_in_4bit=CONFIG['use_4bit'],\n"
            ")\n"
            "model = FastLanguageModel.get_peft_model(\n"
            "    model, r=CONFIG['lora_rank'], lora_alpha=CONFIG['lora_alpha'],\n"
            "    lora_dropout=CONFIG['lora_dropout'], target_modules=CONFIG['target_modules'],\n"
            "    use_gradient_checkpointing='unsloth', random_state=CONFIG['seed'],\n"
            ")"
        ),
        _code(
            "def format_chat(batch):\n"
            "    texts = []\n"
            "    for messages in batch['messages']:\n"
            "        text = tokenizer.apply_chat_template(\n"
            "            messages, tokenize=False, add_generation_prompt=False)\n"
            "        texts.append(text)\n"
            "    return {'text': texts}\n"
            "formatted = dataset.map(format_chat, batched=True)\n"
            "from trl import SFTConfig, SFTTrainer\n"
            "args = SFTConfig(\n"
            "    output_dir=CONFIG['output_dir'], num_train_epochs=CONFIG['epochs'],\n"
            "    per_device_train_batch_size=CONFIG['per_device_batch_size'],\n"
            "    gradient_accumulation_steps=CONFIG['gradient_accumulation_steps'],\n"
            "    learning_rate=CONFIG['learning_rate'], seed=CONFIG['seed'],\n"
            "    max_length=CONFIG['max_sequence_length'], eval_strategy='steps',\n"
            "    save_strategy='steps', save_steps=50, eval_steps=50, logging_steps=5,\n"
            "    report_to='none',\n"
            ")\n"
            "trainer = SFTTrainer(\n"
            "    model=model, processing_class=tokenizer, args=args,\n"
            "    train_dataset=formatted['train'],\n"
            "    eval_dataset=formatted['validation'], dataset_text_field='text')\n"
            "trainer.train(resume_from_checkpoint=bool(os.environ.get('BIOPROF_RESUME')))"
        ),
        _code(
            "output = Path(CONFIG['output_dir'])\n"
            "import subprocess\n"
            "environment = subprocess.check_output(['python', '-m', 'pip', 'freeze'], text=True)\n"
            "(output / 'environment.lock.txt').write_text(environment)\n"
            "model.save_pretrained(output / 'adapter')\n"
            "tokenizer.save_pretrained(output / 'adapter')\n"
            "metrics = trainer.evaluate(formatted['test'])\n"
            "(output / 'test_metrics.json').write_text(json.dumps(metrics, indent=2))\n"
            "print(metrics)"
        ),
        _markdown(
            "## Promotion gate\n\n"
            "Adapterı BioProf'a içe aktarmak onu otomatik olarak `champion` yapmaz. "
            "Kaynak alıntısı, abstention ve görülmemiş belge ailesi değerlendirmeleri "
            "ayrıca geçmelidir."
        ),
    ]
    return {
        "cells": cells,
        "metadata": {
            "accelerator": "GPU",
            "colab": {"name": "BioProf QLoRA", "provenance": []},
            "kernelspec": {"display_name": "Python 3", "name": "python3"},
            "language_info": {"name": "python"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }


def export_colab_bundle(
    destination: Path,
    *,
    dataset: DatasetManifest,
    config: QLoRAConfig | None = None,
) -> ColabTrainingManifest:
    if config is None:
        raise ValueError("A commit-pinned QLoRAConfig is required")
    destination.mkdir(parents=True, exist_ok=True)
    if config.trainer != "unsloth":
        raise ValueError("The notebook exporter currently supports the reviewed Unsloth recipe")
    stable = json.dumps(
        {"dataset_hash": dataset.dataset_hash, "config": config.model_dump()},
        sort_keys=True,
        separators=(",", ":"),
    )
    digest = hashlib.sha256(stable.encode()).hexdigest()
    manifest = ColabTrainingManifest(
        run_id=uuid.uuid4().hex,
        generated_at=datetime.now(UTC),
        dataset_hash=dataset.dataset_hash,
        dataset_schema=dataset.schema_version,
        source_ids=dataset.source_ids,
        licenses=dataset.licenses,
        base_model=config.base_model,
        base_revision=config.base_revision,
        configuration=config.model_dump(),
        expected_outputs=[
            "adapter/",
            "test_metrics.json",
            "trainer_state.json",
            "environment.lock.txt",
        ],
        reproducibility_hash=digest,
    )
    _atomic_json(destination / "training_manifest.json", manifest.model_dump(mode="json"))
    _atomic_json(destination / "bioprof_qlora_colab.ipynb", _unsloth_notebook(config))
    return manifest
