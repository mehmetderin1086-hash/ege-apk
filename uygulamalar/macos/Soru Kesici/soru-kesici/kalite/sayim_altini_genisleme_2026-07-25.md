# Sayım-altını 5 → 11 belgeye çıktı (çift kör sayım)

**Tarih:** 2026-07-25 · **Faz:** 2 · **Yöntem:** her belge **iki bağımsız
sayıcı** tarafından, yalnız çıplak render'a bakılarak sayıldı; sayıcılar
birbirinin sonucunu görmedi. Kurallar: `kalite/kor_sayim_kurallari.md`.

## Mutabakat: 42/42 sayfa, sıfır çelişki

Altı belgenin 42 sayfasının tamamında iki sayıcı **hem soru sayısında hem
sayfa rolünde** aynı sonuca vardı. Bu, yazılı sayım kuralının işe yaradığının
kanıtı; tek geçişli sayımda taşınan "yanlış altın kalıcı kapı gürültüsü olur"
riski bu turda gerçekleşmedi.

| Belge | sayfa | soru | tür |
|---|---|---|---|
| 10sb | 8 | 52 | taranmış soru bankası |
| 10sinif | 2 | 12 | sınav kâğıdı |
| 11fen | 8 | 5 | ders kitabı (7 sayfa konu anlatımı) |
| 9konu | 8 | 14 | taranmış konu anlatımlı |
| 9pdf | 8 | 18 | MEB ders kitabı |
| campbell | 8 | **0** | **negatif kontrol** — ders kitabı, soru yok |

Toplam sayım-altını artık **11 belge / 60 sayfa / 243 soru**.

## İlk kez ölçülen 5 belge — sonuçlar

| Belge | count_recall | count_precision | **otomatik recall** | sıfır sayfa |
|---|---|---|---|---|
| 9konu | 0,929 | 1,000 | 0,857 | s103 |
| 11fen | 0,800 | 1,000 | 0,600 | — |
| 10sinif | 0,500 | 1,000 | 0,333 | — |
| **10sb** | **0,462** | 1,000 | 0,385 | s141 |
| **9pdf** | **0,444** | **0,533** | 0,278 | s89 |

Bu beş belge kampanyadan önce **hiç ölçülmüyordu**; kapı yalnız anomali
sayısına bakıyor ve hepsini "temiz" sayıyordu. Gerçekte ikisinin recall'ü
%50'nin altında.

**9pdf korpusun en kötü precision'ı (0,533):** motor, gerçek soru sayısının
yaklaşık iki katı kutu üretiyor. Şimdiye kadar bu tamamen görünmezdi.

## Negatif kontrol GEÇTİ

`biyoloji-campbell.pdf` (1101 sayfalık ders kitabı) 8 sayfasında motor
**hiç kutu üretmedi** — altınla birebir. Yani `_blok_segmentasyon`'un
"her boşluk bir sorudur" eğilimi saf konu anlatımı sayfalarında ateşlemiyor.
Bu değer artık kapıda kilitli: `campbell` için `count_precision_min: 1.0` ve
`count_recall_min: 1.0`. Düşerse motor soru uydurmaya başlamış demektir.

## Korpus geneli (11 sayım-altınlı belge)

| Aile | belge | sayR | sayP | oR |
|---|---|---|---|---|
| biyoloji-sb (10sb, 9pdf) | 2 | 0,453 | 0,767 | 0,331 |
| meb (12meb, 10sinif) | 2 | 0,318 | 1,000 | 0,189 |
| cozum (cozumler1, cozumyazili) | 2 | 0,736 | 1,000 | 0,344 |
| konu-anlatim (9konu) | 1 | 0,929 | 1,000 | 0,857 |
| aydin | 1 | 0,917 | 1,000 | 0,917 |
| ygs-lys | 1 | 1,000 | 0,906 | 0,897 |
| negatif (campbell) | 1 | 1,000 | 1,000 | 1,000 |

Sıfır sayfa (altında soru var, motor 0 kutu) toplam **5**: cozumler1 s41,
10sb s141, 9konu s103, 9pdf s89, ve 12meb'in düşük recall'ü. Her biri kapıda
koşulsuz kırmızı.

## Kapıya yazılanlar

`kalite/kapi_esikleri.json` artık **13 belge** için taban tutuyor (2 kutu-altını
+ 11 sayım-altını). Tabanlar bugünkü ölçümdür — amaç "daha da düşmesin";
kampanya hedefleri ayrı `hedef` alanında ve kapı onlara bakmaz.

## Kapıda yeni: `--kapsam`

Korpus 44 belgeye çıktığı için üç katman tanımlandı
(`kalite_kosusu.KAPSAM_KATMANLARI`), iç içe:

```
--kapsam A   10 belge   kapı katmanı, her motor değişikliğinde
--kapsam B   41 belge   tam korpus, faz sonunda
--kapsam C   44 belge   yayın (holdout dahil), --sert otomatik açılır
```

Ayrıca `--rapor <yol>` koşumu JSON'a yazar, `--kiyas <yol>` önceki raporla
belge bazlı delta tablosu basar ve her koşumun sonuna **aile bazlı toplam
satırı** eklenir. Aile satırı, projenin dokümante edilmiş dersinin
(aynı kural ygslys'de doğru, cozumler1'de yıkıcı) 44 belgede gözden
kaçmaması için var.
