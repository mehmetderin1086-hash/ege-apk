# Eğitim runbook'u

Referans örneklerden LoRA adaptörü çıkarıp Mac'te yerel modele bağlama akışı.

## Ne zaman eğitmeye değer

RAG katmanı örnek eklendiği anda etkili olur; ince ayar için yeniden eğitim
gerekir. Bu yüzden sıra şu:

1. **Önce hafızayı doldur.** ~50 örneğe kadar RAG tek başına en iyi yatırımdır.
2. **~200 örnekten sonra eğit.** Bu eşiğin altında LoRA çoğunlukla üslup
   öğrenir, muhakeme değil; kör değerlendirmede fark görünmez.
3. **Her eğitimden sonra kör koşu yap.** Ölçmediğin bir iyileşme yoktur.

## 1. Veriyi üret

```bash
biyo-cozucu disa-aktar --etiket v1
# ~/.biyo-cozucu/egitim/v1/{train,valid,test}.jsonl
```

Kayıt biçimi çıkarım istemiyle birebir aynıdır: aynı sistem mesajı, aynı JSON
şeması, `--kanit-sayisi` kadar referans örnek diyaloğu. Bu bilinçli — eğitim ve
çıkarım istemleri ayrışırsa model öğrendiği biçimi çıkarımda göremez.

`test.jsonl` eğitim biçimine sokulmaz; ham `Ornek` kayıtları olarak yazılır ve
yalnız kör değerlendirmede kullanılır. Bölme sorunun imzasına bağlı olduğundan
yeni örnek eklemek eski örneklerin kümesini değiştirmez.

## 2. Colab'da eğit

`colab/01_qwen35_lora.ipynb` → Çalışma zamanı **A100**.

- Denemede `unsloth/Qwen3.5-4B`, gerçek koşuda `unsloth/Qwen3.5-9B`.
- Qwen3.5 **Transformers v5** ister; eski sürüm sessizce değil, açıkça patlar.
- `AZAMI_UZUNLUK=4096` — kanıtlı kayıtlar uzun. Defterdeki uzunluk kontrolü
  aşım varsa durur; sessiz kırpma çözümün sonunu keser ve model yarım çözüm
  üretmeyi öğrenir.
- 4B/9B dense olduğu için 4-bit QLoRA sorunsuz. MoE modellerde 4-bit önerilmez,
  bf16 LoRA kullan.

## 3. Duman testi (atlanmaz)

Defterin 7. hücresi, eğitim sonrası model ile diskten yeniden yüklenen
birleştirilmiş modeli aynı üç soruda karşılaştırır.

- **Sapma yok** → MLX dönüşümüne geç.
- **Sapma var** → sorun birleştirmede, MLX'te değil. Adaptörü ayrı tutup
  `mlx_lm.fuse` dene; olmazsa GGUF + Ollama yoluna geç.

Bu adım bilinen iki açık hata yüzünden var:

| Sorun | Etki | Önlem |
|---|---|---|
| mlx-lm #1058 | Qwen3.5 LoRA birleştirme sonrası ilk 20-30 token doğru, sonra sapma | Duman testi; yedek GGUF |
| mlx-vlm #824 | Qwen3.5/Gemma VLM LoRA eğitimi görüntüsüz koşuyor (loss takılı) | Görsel LoRA kapsam dışı |

İkinci sorun `medical-finetune` projesindeki MedGemma adaptör-çıkarım bozukluğuyla
aynı kökten; bu yüzden görsel yol bilinçli olarak ertelendi.

## 4. Mac'e kur

```bash
biyo-cozucu model-kur ~/Downloads/biyo-lora-v1-merged.zip

uv run python -m mlx_lm.convert \
  --hf-path ~/.biyo-cozucu/modeller/biyo-lora-v1-merged/biyo-lora-v1-merged \
  --mlx-path ~/.biyo-cozucu/modeller/biyo-mlx-v1 -q --q-bits 4 --q-group-size 64

export BIYO_MLX_MODEL=~/.biyo-cozucu/modeller/biyo-mlx-v1
```

Adaptörü ayrı tutmayı tercih edersen `BIYO_MLX_ADAPTOR` ile taban modele takılır
(model dosyası çoğaltılmaz, disk tasarrufu).

## 5. Ölç

```bash
# taban model
BIYO_MLX_MODEL=mlx-community/Qwen3.5-4B-MLX-4bit \
  biyo-cozucu degerlendir --cikti /tmp/taban.json

# ince ayarlı model
BIYO_MLX_MODEL=~/.biyo-cozucu/modeller/biyo-mlx-v1 \
  biyo-cozucu degerlendir --cikti /tmp/v1.json
```

Kör koşu test örneklerini hafızadan **dışlar** — dışlamasaydı sistem kendi
cevabını örnek olarak getirir ve doğruluk yapay şekilde %100 çıkardı.

Bakılacak sayılar: genel doğruluk, **çözüm türü bazlı** doğruluk (zayıf tür =
o türden daha çok örnek gerekiyor), adım örtüşmesi ve incelemeye düşme oranı.

## Hiperparametre başlangıcı

Colab (A100, 4-bit QLoRA): r=16, alpha=32, lr=2e-4, 3 epoch, batch 2 × accum 4.

Mac'te yerel küçük ayar (mlx-lm): `medical-finetune`'da 16 GB M4'te doğrulanmış
konfigürasyon — `num_layers=8, rank=8, lr=1e-5, iters=300, batch=2,
max_seq_length=2048`. Yerel eğitim Colab'ın yerini tutmaz; küçük düzeltme
turları için uygundur.

## Lisans sınırı

Eğitim verisine yalnız **kendi örneklerin** ve Apache/MIT lisanslı açık setler
(MedMCQA, OpenBookQA, ScienceQA) girer. `turkish_mmlu` (CC BY-NC-ND) ve
`yksbench` yalnız **değerlendirmede** kullanılır; `veri/acik_setler.py` bunu
kural olarak uygular ve eğitim amacıyla istendiğinde hata verir.
