"""Colab'da eğitilen LoRA adaptörünü taban modele birleştirir (Mac, CPU, fp16).

Colab'ın birleştirilmiş çıktısı 8,7 GB; onu indirmek yerine 79 MB'lık adaptörü
indirip taban modeli Hugging Face'ten çekiyoruz.

MODEL SINIFI KRİTİK: adaptörün 256 anahtarının tamamı
`base_model.model.model.language_model.layers...` yolunu kullanıyor, çünkü
Colab'da model `Qwen3_5ForConditionalGeneration` olarak yüklendi.
`AutoModelForCausalLM` burada `Qwen3_5ForCausalLM` seçiyor — o sınıfta ara
`language_model` katmanı yok, hiçbir anahtar eşleşmiyor ve PEFT sessizce
(yalnız UserWarning ile) taban modeli olduğu gibi bırakıyor. İlk denemede
7,9 GB'lık çıktı taban modelin kopyasıydı.
"""

from __future__ import annotations

import sys
from pathlib import Path

import torch
from peft import PeftModel
from transformers import AutoTokenizer, Qwen3_5ForConditionalGeneration

ADAPTOR = Path.home() / ".biyo-cozucu/modeller/biyo-lora-v1-adapter/biyo-lora-v1-adapter"
TABAN = "unsloth/Qwen3.5-4B"
HEDEF = Path.home() / ".biyo-cozucu/modeller/biyo-lora-v1-fused"

# Birleşmenin gerçekten olduğunu kanıtlamak için izlenecek ağırlık: adaptörde
# LoRA'sı olan bir katman. Merge sonrası değişmemişse iş görmemiş demektir.
TANIK = "model.language_model.layers.0.mlp.down_proj.weight"


def main() -> int:
    if not ADAPTOR.is_dir():
        print(f"Adaptör bulunamadı: {ADAPTOR}", file=sys.stderr)
        return 1

    print(f"Taban model yükleniyor: {TABAN}", flush=True)
    model = Qwen3_5ForConditionalGeneration.from_pretrained(
        TABAN, dtype=torch.float16, low_cpu_mem_usage=True, device_map="cpu"
    )
    once = dict(model.named_parameters())[TANIK].detach().clone()
    print("Taban model yüklendi.", flush=True)

    print(f"Adaptör uygulanıyor: {ADAPTOR}", flush=True)
    model = PeftModel.from_pretrained(model, str(ADAPTOR), dtype=torch.float16)
    model = model.merge_and_unload()

    sonra = dict(model.named_parameters())[TANIK]
    fark = (sonra - once).abs().max().item()
    print(f"Tanık ağırlık azami farkı: {fark:.6f}", flush=True)
    if fark == 0.0:
        print(
            "BİRLEŞME OLMADI: LoRA ağırlıkları taban modele işlenmemiş. "
            "Model sınıfı ile adaptör anahtar yolu uyuşmuyor olabilir.",
            file=sys.stderr,
        )
        return 2

    HEDEF.mkdir(parents=True, exist_ok=True)
    model.save_pretrained(str(HEDEF), safe_serialization=True)
    AutoTokenizer.from_pretrained(str(ADAPTOR)).save_pretrained(str(HEDEF))
    print(f"Yazıldı → {HEDEF}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
