# Kalite Snapshot Sapması — Kök Neden Analizi (2026-07-21)

Soru: `kalite/once_*.json` snapshot'ları (18 Temmuz 15:54–15:57'de tazelenmiş) ile güncel
koşum arasında 3 belgede sapma var (10sb 5→7, aydin 32→35, ygslys 80→67); motor koduna
bu turda dokunulmadı. Kaynak ne?

## Sonuç (TL;DR)

Sapmanın kaynağı **snapshot'lardan SONRA devreye giren iki kasıtlı özellik**tir; kod hatası
veya nondeterminizm değildir:

1. **Birincil: soru-özel modelin (question_layout_v3.pt) 19 Temmuz'da yayınlanması.**
   Tespit kablolaması dbfadc2'de (18 Tem 16:02) vardı ama ağırlık dosyası yoktu → model
   snapshot koşumunda pasifti. Ağırlık 19 Tem 12:05'te, manifest 12:54'te yayınlandı
   (Colab eğitimi, v3.0.0, holdout F1=0.5757). O andan itibaren model tespitte aktif.
2. **İkincil (küçük): OCR "dengeli" hakemlik modu.** `~/.soru_kesici.json` içinde
   `"ocr_modu": "dengeli"` seçili; 5-motor hakemlik (Faz B, 581d965, 18 Tem 16:37 commit)
   güncel koşumlarda çalışıyor. Etkisi yalnız aydin (+2 kutu) ve ygslys (+1 anomali,
   +2 kutu) üzerinde; 10sb'de sıfır.

**Kanıt (kesin):** `SORU_KESICI_SORU_MODELI=0 SORU_KESICI_OCR_MODU=hizli` ile güncel kod,
üç belgede de snapshot'ları **bit-özdeş** üretiyor (anomali listesi, sayfa_soru, kutu
sayısı dahil `tam_esit=True`). Yalnız modeli kapatmak 10sb'yi bit-özdeş döndürüyor;
aydin/ygslys'de anomali sayısını snapshot'a döndürüyor (32; 81≈80), kalan ±2 kutu farkı
OCR modundan geliyor.

## (a) Belge başına diff özeti

| Belge | Snapshot | Güncel | Kutu | Mekanizma |
|---|---|---|---|---|
| 10sb | 5 | 7 | 168→174 | Model 6 sayfada (71,76,101,116,146,176) +1'er soru kurtardı; s71 ve s101'deki iki kurtarılan kutu `minik` anomalisi doğurdu (+2). `sutun-tasma` 5'te sabit. |
| aydin | 32 | 35 | 182→190 | Model 6 sayfada (43,49×2,73,91,97×2,187) +8 kutu ekledi → +3 anomali (24'lük liste kırpması nedeniyle tür kırılımı listede görünmüyor; sayım farkı model kaynaklı, kapalı koşumda 32'ye dönüyor). İlk-24 listesindeki farklar yalnız 1–12 px koordinat kayması (s49/s73/s79). |
| ygslys | 80 | 67 | 337→390 | En büyük etki: model 29 sayfada toplam +53 kutu kurtardı; birleşik kutular ayrışınca 13 anomali kayboldu (İYİLEŞME). İlk-24 listesinde s11/s26'daki `sutun-tasma` kayıtları yer değiştirdi/kaydı. |

Diğer 7 belge: soru modeli ve OCR hakemliği bu belgelerde sonucu değiştirmiyor
(4'ü metin katmanlı; taranmış 9konu'da da model kararları heuristikle çakışmıyor) → sapma yok.

## (b) Kök neden — kanıt zinciri

- Zaman çizelgesi: snapshot tazeleme 18 Tem 15:54–15:57 (dosya mtime'ları). Ağırlık
  `~/Library/Application Support/soru-kesici/modeller/question_layout_v3.pt` mtime
  **19 Tem 12:05:41**, manifest `created_at: 2026-07-19T09:54:49+00:00` (=12:54 yerel).
  Eğitim verisi dizini `egitim/ql_v3` 19 Tem 07:02–08:29 (Colab paketleme akışı,
  `soru_model_colab*.py` çalışma kopyası dosyalarıyla uyumlu).
- Model tahmin önbelleği `~/Library/Caches/soru-kesici/duzen/soru-v3/` içindeki **516
  girdinin tamamı 19 Tem 13:04 ve sonrası; 19 Tem öncesi tek girdi yok** → snapshot
  koşumunda soru modeli hiç çıkarım yapmadı. (Ağırlık yokken `soru_modeli_kullanilabilir()`
  güvenle False döner — `duzen_model.py:365-366`; cache anahtarı model SHA'sını içerir —
  `duzen_model.py:468-478`.)
- Etki mekanizması `soru_kes.py`'de: sütun ayracı adayı (2285–2295), kutu kanıt/uyarıları
  (2902–3023) ve özellikle `_soru_modeli_yedegi_uygula` soru-kurtarma yolu (4171–4257,
  `soru_modeli_kurtardi`) — kutu sayısı artışlarının kaynağı bu.
- Snapshot'lardaki `"duzen_model": true` alanı GENEL düzen modelini gösterir
  (doclayout_yolo, 14 Tem'den beri değişmedi; `dogrula.py:2053`) — soru-özel modeli değil;
  yanıltmasın.
- İkincil etken: `ocr_ensemble.mod_al()` önceliği MOD_ZORLA > env > ayar > hizli;
  ayar dosyasında bugün `dengeli` seçili. Snapshot davranışı `hizli` ile bit-özdeş
  olduğundan snapshot anında ya Faz B kodu çalışma kopyasında yoktu ya da mod henüz
  seçilmemişti. (OCR_CACHE_SURUM 3→4 yalnız cache anahtarını değiştirir; Vision
  sonuçları aynı — 10sb'nin bit-özdeş dönmesi bunu doğrular.)

## (c) Determinizm

Güncel konfigürasyonla art arda iki tam koşum (3 belge) **bit-özdeş** (JSON diff boş).
Ayrıca iki bayrakla snapshot durumu da bit-özdeş yeniden üretilebiliyor. Sapma
**tamamen deterministik**tir; nondeterministik bileşen gözlenmedi.

## (d) Öneri: snapshot'ları TAZELE (`--guncelle`)

Gerekçe:
1. Sapma bir hata değil, iki bilinçli özelliğin (yayın kapısından geçmiş model + kullanıcı
   ayarıyla seçilmiş OCR modu) üretim konfigürasyonuna girmesi. `once_*.json` artık üretim
   davranışını temsil etmiyor.
2. Eski snapshot regresyon kapısını köreltiyor: ygslys'de güncel 67 < snapshot 80
   olduğundan, 67→79 arası bir GERÇEK regresyon kapıdan sessizce geçer. Baseline
   2026-07-21 çalışmasının hedefi ("güncel değerlerde artış olmadan birlesme→0") için
   referans güncel değerler (7/35/67) olmalı.
3. 10sb'deki +2 `minik` ve aydin'daki +3, modelin kurtardığı kutuların yan etkisi —
   model toplamda +67 kutu (kaçan soruları) kazandırdı; bu takas yayın kapısında kabul
   edildi. İzlenmek isteniyorsa tazeleme sonrası ayrı bir iş kalemi olarak ele alınmalı.

Tazeleme, üretim konfigürasyonuyla (model açık + `ocr_modu` ayar dosyasından) tüm
koleksiyon için yapılmalı: `.venv/bin/python kalite_kosusu.py --guncelle`. Not: bu analiz
raporu salt-okunur turda yazıldı; `--guncelle` çalıştırılmadı, karar ekibe bırakıldı.

## Yöntem / artefaktlar

Koşumlar `dogrula.metrikler(yol, dpi=300, max_sayfa=40)` ile `_guncelle` yoluna özdeş
yapıldı; çıktılar scratchpad'de (`acik1_*/acik2_*/kapali_*/kapali_hizli_*.json`).
Not: `anomaliler` listesi 24 kayıtla kırpıldığından (dogrula.py:2049) aydin/ygslys satır
diff'i ilk 24 kayıtla sınırlıdır; sayımlar ve `sayfa_soru` tam listedir.
