# Asistan — Siri'den yetenekli kişisel iPhone asistanı (plan, 14 Ekim 2026)

## Araştırma sonucu (kaynaklar: ~/Developer/research_notes/siri-asistan-{platform,oss,ses}-2026-10-14.md)
- Siri'nin **yerine geçmek Türkiye'de mümkün değil** (yan düğme ataması yalnız Japonya). Yol: ayrı asistan uygulaması + sistem tetikleyicileri (Action Button, Kontrol Merkezi/Kilit ekranı kontrolü, "Hey Siri, Asistan'ı aç" App Shortcut, Back Tap→Kısayol).
- Telefon iPhone 15 (A16, iOS 27.2): **Apple Intelligence yok** → cihaz içi Apple LLM'i yok; beyin bulut Claude.
- Beyin: **ClaudeForFoundationModels 0.2.3** (resmî Anthropic, Apache 2.0) + Apple `LanguageModelSession`. Mac'te doğrulandı: Türkçe + 2 araç + akış, API anahtarıyla 7,7 sn, VPS vekiliyle 5,8 sn.
- Ses: **DictationTranscriber tr_TR** cihaz içi akışlı STT (ölçüldü; SpeechTranscriber'da Türkçe yok). TTS: AVSpeech "Yelda" (yedek/çevrimdışı); sonra VPS Chirp 3 HD.
- Hesap: ücretli geliştirici hesabı (profil 2027'ye kadar) → uzantı, App Groups, Siri/App Attest serbest.

## Mimari
```
Tetikleyici (düğme / Action Button / Kontrol / App Shortcut)
  → SesDinleyici (AVAudioEngine → SpeechAnalyzer+DictationTranscriber tr_TR; volatile+final)
  → Beyin (LanguageModelSession; ClaudeLanguageModel: VPS vekil → API anahtarı; model/effort ayarlanabilir)
      ↔ Araçlar (Tool): saat, takvim, hatırlatıcı, kişiler, ara/mesaj, harita, hava (Open-Meteo), kısayol, uygulama aç, hafıza; sunucu: web arama
  → akışlı metin → Konuşmacı (cümle cümle TTS, barge-in'de sustur)
  → SwiftData: sohbet geçmişi + kalıcı olgular (hafıza)
```
Katmanlar: `App/` (giriş, ayarlar), `Beyin/` (oturum, model zinciri, istemler), `Araclar/` (her yetenek bir Tool), `Ses/` (STT, TTS, ses oturumu), `Hafiza/` (SwiftData modelleri), `Tetik/` (AppIntents + kontrol widget'ı), `Arayuz/` (SwiftUI).

## Aday yaklaşımlar ve seçim (rubrik: Doğruluk/Basitlik/Risk/Verim, 0-10)
| Aday | D | B | R | V | Toplam |
|---|---|---|---|---|---|
| A. ClaudeForFoundationModels + Apple Tool protokolü | 8 | 9 | 7 | 9 | **33** |
| B. Kendi URLSession Messages API istemcisi + kendi araç döngüsü | 9 | 6 | 8 | 7 | 30 |
| C. Ders Video'daki JavaScriptCore motorunu taşıma | 7 | 4 | 6 | 6 | 23 |
Seçim: **A**. Gerekçe: resmî paket, araç/şema/akış/önbellek hazır, Mac'te uçtan uca doğrulandı; beta riski Beyin katmanının arkasına saklanır (B'ye geçiş yalnız o katmanı değiştirir).
Codex çaprazı: hesap sınırı (7 Kasım'a kadar kapalı) nedeniyle atlandı.

## Fazlar
- **F0 Çekirdek (bugün):** XcodeGen iskeleti, metin sohbeti, model zinciri (vekil→anahtar), 10 araç, hafıza, ayarlar, testler, simülatör + telefona kurulum.
- **F1 Ses:** bas-konuş + sürekli konuşma, Türkçe STT/TTS, barge-in, ses oturumu.
- **F2 Tetikleyiciler:** App Intent + App Shortcut cümleleri, Kontrol Merkezi/Action Button kontrolü (widget uzantısı), kilit ekranı.
- **F3 Hafıza+:** konuşma sonu olgu çıkarımı (Haiku 5.5), profil, anlamsal arama (NLContextualEmbedding).
- **F4 Görsel/HomeKit/MCP:** kamera/foto → Claude vision, HomeKit, uzak MCP araçları, Chirp TTS, AlarmKit.

## Bilinçli kısıtlar
- Uygulama kapalıyken "Hey Asistan" yok (iOS izin vermiyor); dinleme kullanıcı başlatır.
- Arama/mesaj gönderme sistem onayından geçer (tel:/sms: URL).
- Silme ve arama gibi geri alınamaz eylemler kullanıcı onayı ister.

## Durum (19 Ekim 2026)
F0–F4 tamam ve telefonda. Sonradan eklenenler: paralel model yarışı + Antigravity hesabı önceliği; Hermes/OpenClaw tarzı ajan katmanı (beceriler SKILL.md, çalışma alanı dosyaları, nabız, plan, alt ajanlar — `arac` türü dahil, MCP, projeler, tetikleyiciler, Kestirme görev köprüsü, Ajan merkezi: izinler/bütçe/görev günlüğü, eleştirmen); Live tam ekran + kamera ajanı + OpenAI Realtime; 5 fazlı arayüz (Claude teması varsayılan, Telegram/Sade/Gece seçilebilir, her renk ayarlanabilir); çoklu fotoğraf/belge tarama/düzenleme; paylaşım uzantısı; web kazıma (`veriKazi`: tablo/alanlar/bağlantılar/medya), indirme (`bul/toplu/bekle`, biten her indirme sohbete dosya kartıyla gelir), önizleme kartları (dosya/tablo/medya/kaynak), İETT sefer saatleri + renkli PDF, Apple Music arama/çalma. Uygulama adı "Asistan", yeni logo (`icon.swift`).
Açık işler: anlamsal hafıza (VPS bge-m3 gömleme, Caddy izni gerekir); `asistan://sor` dış erişim kısıtı; YouTube indirme Kepçe'ye bağlı. Ayrıntılı kurallar: `AGENTS.md`.
