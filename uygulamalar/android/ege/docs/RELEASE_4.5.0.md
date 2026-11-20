# Ege 4.5.0+63 — Tek tasarım dili: Araçlar, Stüdyo ve PC Kod yenilendi

4.4.9'daki canlı mod / dikte düzeltmelerini içerir (bkz. `RELEASE_4.4.9.md`).

## Sorun

Sohbet, Canlı Ses ve Ayarlar sıcak, sade temaya geçmişti; Araçlar, Stüdyo ve
PC Kod ise eski siyan/lacivert "HUD" renklerinde kalmıştı. Açık temada beyaz
zemin üstünde lacivert kartlar, okunmayan açık mavi düğme yazıları ve
lacivert sekme şeridi oluşuyordu.

## Değişiklikler

- 12 ekran ve bileşendeki ~110 sabit renk tema belirteçlerine
  (`ChatPalette.accent/surface/soft/border/muted/ink`) taşındı. Artık açık/koyu
  tema ve Ayarlar'daki vurgu rengi tüm sekmelere uygulanır.
- Araçlar/Stüdyo/PC Kod üst çubuğu: sekme adı ve simgesi, oturum adı, sade
  model rozeti; buzlu cam ve parlama çizgisi kaldırıldı. Tekrarlayan "Yeni
  Sohbet" düğmesi bu sekmelerden çıkarıldı (Sohbet ve çekmecede duruyor).
- Araçlar sekme şeridi temaya uyar, alt çizgiyle ayrılır.
- Alt gezinme çubuğu: düz yüzey, ince üst çizgi, sade seçim göstergesi.
- Stüdyo'daki "Ege Merkezi" afişi: eski siyan görsel yerine kodla çizilen,
  temaya ve vurgu rengine uyan ses dalgası deseni (`EgeBannerArt`).
- Sohbetteki ek menüsü koyu temada beyaz açılmıyor.
- Açılış ekranında "J.A.R.V.I.S." yerine "Ege".

## Görseller hakkında

Higgsfield MCP kullanılamadı: Claude Code'da tanımlı değil (yalnız Codex'te)
ve bu ağdan `mcp.higgsfield.ai` adresine TLS bağlantısı kurulamıyor.
Gemini görsel modeli de anahtarın kotası dolduğu için (HTTP 429) denendi ama
kullanılamadı. Afiş bu nedenle vektörel çizildi.

## Doğrulama

- Yeni `test/ui_preview_test.dart`: 6 sekme × açık/koyu ekran çizimi, taşma
  yok (`--dart-define=UI_PREVIEW=<klasör>` ile PNG yazar).
- `test/ege_449_test.dart`: eski renklerin ana ekranlara geri dönmediğini
  denetleyen test eklendi.
- Tüm paket: 341 başarılı, 5 başarısız (4.4.8'den kalan aynı 5 test).

## 3D arayüz

- **Canlı Ses küresi** (`lib/widgets/ege_3d.dart`, `Ege3DOrb`): ışıklandırılmış
  çekirdek, eğik ekvator halkası ve 420 noktalık Fibonacci küre kabuğu gerçek
  perspektif izdüşümüyle iki eksende döner; noktalar derinliğe göre boyut ve
  saydamlık alır. Konuşma enerjisi yüzeyi dalgalandırır, renk faza göre değişir
  (hazır: vurgu rengi, düşünüyor: amber, konuşuyor: mavi). 45 fps, ayrı
  `RepaintBoundary`; sistemde hareket azaltma, "Arayüz efektleri" kapalıysa
  veya ağır iş sürerken durur.
- **3D eğilen kartlar** (`Tilt3D`): dokunulabilir kartlar ve Ege Merkezi
  kutucukları parmağın olduğu yöne perspektifle eğilir, bırakınca yumuşakça
  düzleşir. Kutucuk simgelerine üst ışık / alt gölge kabartması eklendi.
- Higgsfield MCP bu makinede eklenemedi: kurumsal MCP yapılandırması MCP
  sunucularını tek başına yönetiyor (`claude mcp add` reddedildi) ve ağ
  `higgsfield.ai` TLS bağlantısını kesiyor. 3D öğeler bu yüzden kodla çizildi.
- Tüm paket: 343 başarılı, 5 başarısız (4.4.8'den kalan aynı 5 test).
