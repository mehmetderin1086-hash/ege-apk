# 🎙️ SesLab

**Türkçe odaklı, tamamen yerel ses stüdyosu** — ElevenLabs'e açık kaynak alternatif.
Apple Silicon (M serisi) Mac'ler için tasarlandı; internet olmadan çalışır, verileriniz makinenizden çıkmaz.

## Özellikler

| Özellik | Teknoloji |
|---|---|
| 🗣️ **Konuşturucu (TTS)** — Türkçe + 22 dil | Chatterbox Multilingual (MIT, Resemble AI) |
| 👤 **Anında ses klonlama** — ~10 sn örnekten | Chatterbox zero-shot cloning |
| 🌍 **Diller arası klon** — Türkçe sesinizle İngilizce konuşun | `language_id` parametresi |
| 📝 **Deşifre (STT)** — kelime zaman damgalı | mlx-whisper large-v3-turbo (MLX) |
| 🔄 **Ses değiştirici** — kayıt içeriğini koruyup sesi dönüştür | ChatterboxVC |
| 📚 **Projeler** — kitap boyu metin (5M karakter) seslendirme | bölüm bazlı sentez + birleştirme |
| 📄 **Dosya yükleme** — PDF / Word / TXT'den metin çıkarma | pypdf + python-docx (satır onarımlı) |
| ⚡ **Hız kontrolü** — üret∥denetle boru hattı; isteğe bağlı denetim (kapalı ≈ 2× hız) | insan temposu varsayılanı 0.85× |
| 🔤 **Türkçe normalizasyon** — sayı/tarih/saat/kısaltma/akronim/Romen rakamı/kesir okunuşu, yabancı marka fonetiği | 20+ kurallı özel motor + num2words |
| 📤 **Exportlar** — WAV, MP3, TXT, SRT, VTT, JSON | PyAV / soundfile |
| 🔌 **OpenAI uyumlu API** | `/v1/audio/speech`, `/v1/audio/transcriptions` |

## Kurulum

Gereksinimler: Apple Silicon Mac (M1–M4), ~16 GB RAM, ~12 GB boş disk, [uv](https://docs.astral.sh/uv/).

```bash
uv sync                              # bağımlılıklar (Python 3.11 otomatik)
uv run python -m app.setup_models    # modelleri indir (~7 GB, tek seferlik)
uv run uvicorn app.main:app --port 8000
```

Tarayıcıda **http://localhost:8000** açın. (Modelleri arayüzdeki kurulum sihirbazından da indirebilirsiniz.)

## Hızlı API örnekleri

```bash
# TTS
curl localhost:8000/api/tts -H 'Content-Type: application/json' \
  -d '{"text": "Merhaba dünya! Saat 14:30, hava 25°C."}'

# OpenAI uyumlu TTS
curl localhost:8000/v1/audio/speech -H 'Content-Type: application/json' \
  -d '{"model":"seslab","input":"Merhaba!","voice":"default","response_format":"wav"}' \
  -o merhaba.wav

# Deşifre (OpenAI uyumlu)
curl localhost:8000/v1/audio/transcriptions -F file=@kayit.mp3 -F language=tr
```

## Mimari

```
app/
├── engines/        # Chatterbox TTS/VC + mlx-whisper sarmalayıcıları
│   └── manager.py  # 16 GB politikası: en fazla 1 ağır motor, MPS watchdog
├── core/text/      # Türkçe normalizasyon + kısaltma-vetolu cümle bölme
├── audio/          # PyAV çözme (ffmpeg CLI gerekmez), mp3 kodlama
├── api/            # FastAPI uçları + OpenAI uyumluluk katmanı
└── jobs.py         # tek worker iş kuyruğu + SSE ilerleme
web/                # build'siz vanilla JS arayüz (koyu stüdyo teması)
```

## Opsiyonel: XTTS-v2 ikinci motoru (A/B karşılaştırma)

> ⚠️ **Lisans:** XTTS-v2 ağırlıkları CPML kapsamındadır — **yalnızca ticari olmayan**
> kullanım. Bu yüzden ayrı bir sanal ortamda, arayüzde rozetle işaretli çalışır.

```bash
uv venv .venv-xtts --python 3.11
uv pip install --python .venv-xtts/bin/python \
  "coqui-tts[codec]==0.27.5" "transformers>=4.57,<5" \
  "torch==2.8.0" "torchaudio==2.8.0"
# torch 2.8 pini önemli: 2.9+ torchcodec/sistem-FFmpeg ister (bu kurulumda yok)
```

Kurulum sonrası Konuşturucu sayfasındaki **Motor** menüsünden `XTTS-v2` seçilebilir;
ilk kullanımda model (~2 GB) otomatik iner. Chatterbox'a özgü Abartı/CFG ayarları
bu motorda geçerli değildir. Ana ortam ile bağımlılık çakışması yoktur
(transformers 4.57 ↔ 5.2 izolasyonu alt süreçle sağlanır).

## Testler

```bash
uv run pytest        # 67 test: normalizasyon, parçalama, ses G/Ç, API
```

## Bilinen notlar

- **Filigran:** Tüm TTS/VC çıktıları, kötüye kullanımı caydırmak için Chatterbox'ın
  duyulmayan **Perth nöral filigranını** içerir.
- **Bellek:** 16 GB Mac'te TTS ve Ses Değiştirici motorları aynı anda bellekte tutulmaz;
  geçişlerde kısa bir yeniden yükleme beklenir. RSS 12 GB'ı aşarsa motor otomatik boşaltılır.
- **Türkçe kalitesi:** Chatterbox'ta Türkçe, öncelikli 6 dilin bir kademe altındadır;
  normalizasyon motoru (sayı/tarih/kısaltma okunuşu) bu farkın çoğunu kapatır.
  Parametrelerle oynayın: `Abartı` duyguyu, `CFG` klon sadakatini kontrol eder.
- **Etik:** Yalnızca kendi sesinizi veya izin aldığınız sesleri klonlayın.

## Lisanslar

SesLab kodu MIT. Modeller: Chatterbox (MIT), Whisper large-v3-turbo (MIT).
