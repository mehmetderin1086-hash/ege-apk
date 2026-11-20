# CLI Proxy (iPhone / iPad)

Sunucudaki CLI Proxy API'nin (82.29.179.131, `/srv/apps/cliproxy`) telefona taşınmış hâli.

- `ProxyKit/` — çekirdek Swift paketi: OAuth (Claude, ChatGPT/Codex), API anahtarlı sağlayıcılar, OpenAI ↔ Anthropic ↔ Responses
  çevirisi, Network.framework HTTP sunucusu, Keychain kasası. `cd ProxyKit && swift test` (canlı süit: `CLIPROXY_CANLI_PAKET=<paket.json>`).
- `CLIProxy/` — SwiftUI uygulaması (Durum, Hesaplar, Sohbet, Kayıtlar, Ayarlar). Kurulum: `./telefona-kur.sh [--paket]`.
- `sunucu/` — sunucuya eklenenlerin kaynağı: `telefon-paketi.py` (taşıma paketi), `telefon_esitleme.py` (`GET /v1/x/oauth-access`).
- İkra entegrasyonu: ortak Keychain grubu `838FF89FZ8.com.mehmetderin.ortak`; İkra'daki kopya `./ikraya-esitle.sh` ile güncellenir.

OAuth hesapları varsayılan olarak **sunucu yeniler** kipindedir: telefon erişim belirtecini sunucudan çeker, yenileme belirteci
rotasyonu iki tarafı birbirine düşürmez. Telefonda yürütülemeyen modeller (Antigravity, Gemini Pro köprüsü, Qwen, görsel üretim)
ve telefonda hata veren istekler sunucuya yönlenir.
