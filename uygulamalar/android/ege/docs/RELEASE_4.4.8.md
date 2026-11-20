# Ege 4.4.8+61 — CLIProxyAPI tam model kataloğu ve 4.4.7 Android STT uyandırma birleşimi

## CLIProxyAPI tam model kataloğu (En yeni modeller dahil)

- **Gemini 4 ve 3.8 serisi**: `gemini-4-carbon` (`-high`, `-medium`, `-low`), `gemini-4-argon` (`-high`, `-medium`, `-low`), `gemini-4-hydrogen` (`-xhigh`, `-high`, `-medium`, `-low`), `gemini-3.8-flash` (`-high`, `-medium`, `-low`), `gemini-3.8-live`, `gemini-omni-1.2-flash`, `gemini-3.7-flash`, `gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.5-flash-lite`, `gemini-3.5-transcribe`, `gemma-4-31b-it`, `gemma-4-26b-a4b-it`, `gemini-embedding-2`.
- **OpenAI / GPT-6.2 / Codex serisi**: `gpt-6.2-sol`, `gpt-6.2-astra`, `gpt-6.1-terra`, `gpt-6.1-sol`, `gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna`, `gpt-reserve`, `codex-auto-review`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-5.5`, `gpt-5.4`, `gpt-5.3-codex`, `gpt-oss-120b-medium`, `o3`, `o4-mini`, `gpt-4.1`, `gpt-4o`, `gpt-4o-mini`.
- **Claude 5.5 / 5 / 4.x ve Antigravity**: `claude-opus-5-5` (`-high`, `-medium`, `-low`), `claude-sonnet-5-5` (`-high`, `-medium`, `-low`), `claude-fable-5-1`, `claude-opus-5`, `claude-sonnet-5`, `claude-fable-5`, `claude-opus-4-8`, `claude-opus-4-7`, `claude-opus-4-6`, `claude-sonnet-4-6`, `claude-opus-4-5`, `claude-sonnet-4-5`, `claude-haiku-4-5`, `antigravity-claude-opus-5-5`, `antigravity-claude-sonnet-5-5`.
- **Görsel ve Ses (TTS) modelleri**: `gemini-nano-banana-2.1`, `gemini-3-pro-image`, `gemini-3.1-flash-lite-image`, `gemini-3.1-flash-image`, `antigravity-gemini-image`, `gpt-image-2.6`, `gpt-image-2.5-flare`, `gpt-image-2.5-sunburst`, `gemini-3.8-flash-tts`, `gemini-3.8-flash-lite-tts`, `gpt-4o-mini-tts`.
- **Katalog birleştirme ve koruma**:
  - `StorageService.loadCachedModels()` ve `JarvisController.refreshProxyModels()` artık canlı `/v1/models` listesini tam `ProxyModelInfo.fallbackCatalog` ile birleştirir; eski sürüm önbellekleri veya eski telefondaki CLIProxy derlemesi yeni modelleri gizlemez.
  - `EmbeddedKeys.applyTo()` artık kullanıcının telefonda gerçek anahtarla yapılandırdığı `http://127.0.0.1:8317` (yerel `com.mehmetderin.cliproxy`) CLI Proxy API ayarını ezmez.
  - Eski proxy sürümlerinde `-high`/`-medium`/`-low`/`-xhigh` alias tanımlı değilse 400/404 durumunda otomatik temel modele düşülür; Gemini Direct yolunda `thinkingLevel` gönderilir ve `thought: true` parçaları yanıt metninden süzülür.
- **PC CLIProxyAPI (`~/cli-proxy-api`)**: `codex`, `gemini`, `gemini-script`, `openai` sağlayıcı listeleri ve `config.yaml` alias/yönlendirme kuralları da aynı güncel modellerle eşitlendi.

## Android yerel STT ile Hey Ege uyandırma kontrolü (4.4.7'den devralınan)

- Arka plan servisi mevcut mikrofon PCM akışından kısa konuşma parçalarını Android yerel STT motoruna verir; Whisper kapalı kalır, mevcut ses profili ve eşikler korunur.

## Doğrulama ve Kurulum

- `dart analyze` (değişen ve eklenen 8 dosya): 0 hata, 0 uyarı.
- `test/cliproxy_models_test.dart` (6/6), `test/agent-memory-compress_test.dart`, `test/chat-stream-ai_test.dart`: tamamı başarılı.
- APK: `C:/Users/mehmet/Desktop/JARVIS/dist/Ege-4.4.8.apk` (84.628.526 bayt, `versionName=4.4.8`, `versionCode=61`).
- SHA-256: `7da5b87434c31a6814628d6f68a6fc47109199e52db9ad2631e3841b9ba01d4d`.
- Bağlı telefona (`QOAI8D5XE6VK4HQ8`) `adb install -r` ile veriler korunarak kuruldu (`2026-11-17 22:20:55`).
- Cihaz kaydı doğrulaması: `WAKE_ENGINE keyword_spotter=true android_local=true whisper=false` aktif; çökme yok. Android Türkçe cihaz içi STT modeli hâlen `status=SCHEDULED` durumunda (telefon Wi-Fi kapalı olduğu için Google model indirme işi ölçümsüz ağ bekliyor).
