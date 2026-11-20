"""SesLab yapılandırması — yollar, limitler, ortam değişkeni geçersiz kılmaları."""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = Path(os.environ.get("SESLAB_DATA", BASE_DIR / "data"))
VOICES_DIR = DATA_DIR / "voices"
OUTPUTS_DIR = DATA_DIR / "outputs"
PROJECTS_DIR = DATA_DIR / "projects"
DB_PATH = DATA_DIR / "seslab.db"
WEB_DIR = BASE_DIR / "web"

# HuggingFace model depoları
TTS_REPO = "ResembleAI/chatterbox"
# Chatterbox Multilingual sürümü: "v3" (Haziran 2026: daha iyi ses benzerliği, daha az uydurma) ya da eski "v2".
CHATTERBOX_T3 = os.environ.get("SESLAB_CHATTERBOX_T3", "v3")
STT_REPO = "mlx-community/whisper-large-v3-turbo"

# Örnekleme hızları
TTS_SR = 24000   # Chatterbox çıkışı
STT_SR = 16000   # Whisper girişi
REF_SR = 24000   # klon referans kayıtları

# Türkçe metin parçalama (Chatterbox uzun girdide bozulur)
CHUNK_TARGET = 250   # hedef karakter/üretim
CHUNK_HARD = 300     # sert tavan

# XTTS tek-geçiş sınırları: model tokenizer'ının Türkçe tavanı 226 karakter.
# Parçalar çok cümleli gruplardır ve split_sentences=False ile TEK GPT
# geçişinde üretilir → cümleler arası doğal tonlama akışı (prozodi) korunur.
XTTS_CHUNK_TARGET = 200
XTTS_CHUNK_HARD = 226

# Bellek yönetimi (16 GB RAM bütçesi)
IDLE_UNLOAD_S = int(os.environ.get("SESLAB_IDLE_UNLOAD_S", "600"))
RSS_LIMIT_GB = float(os.environ.get("SESLAB_RSS_LIMIT_GB", "12"))
RELOAD_EVERY_N = int(os.environ.get("SESLAB_RELOAD_EVERY_N", "150"))

# Klon referans örneği süre sınırları (saniye)
VOICE_MIN_S = 3.0
VOICE_MAX_S = 30.0

# STT geri beslemeli üretim doğrulaması (kuyruk halüsinasyonu kesimi +
# kötü örneklemede 1 kez yeniden üretim). Türkçe üretimlerde etkindir.
TTS_VERIFY = os.environ.get("SESLAB_TTS_VERIFY", "1") == "1"

# Varsayılan konuşma temposu. Murat dinleme geri bildiriminde 0.85 hız
# bayık/ağır bulundu; modelin doğal ham temposu olan 1.0'a dönüldü.
# XTTS hızı latent uzayında uygular, bu nedenle perdeyi yapay biçimde
# yükseltmeden konuşmayı canlandırır. Kaydırıcıyla yine değiştirilebilir.
DEFAULT_SPEECH_SPEED = float(os.environ.get("SESLAB_SPEECH_SPEED", "1.0"))

# Chatterbox Multilingual dil kodları (cross-lingual üretim için)
LANGUAGES = {
    "tr": "Türkçe", "en": "İngilizce", "de": "Almanca", "fr": "Fransızca",
    "es": "İspanyolca", "it": "İtalyanca", "pt": "Portekizce", "pl": "Lehçe",
    "nl": "Felemenkçe", "ru": "Rusça", "ar": "Arapça", "zh": "Çince",
    "ja": "Japonca", "ko": "Korece", "hi": "Hintçe", "el": "Yunanca",
    "he": "İbranice", "sv": "İsveççe", "no": "Norveççe", "da": "Danca",
    "fi": "Fince", "ms": "Malayca", "sw": "Svahili",
}
DEFAULT_LANGUAGE = "tr"


def ensure_dirs() -> None:
    for d in (DATA_DIR, VOICES_DIR, OUTPUTS_DIR, PROJECTS_DIR):
        d.mkdir(parents=True, exist_ok=True)
