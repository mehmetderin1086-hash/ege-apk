# Sıfır sayfa teşhisi — üç sayfa, üç ayrı kök neden

**Tarih:** 2026-07-25 · "Sıfır sayfa" = sayım-altınında soru var ama motor
o sayfada **hiç kutu teslim etmiyor**. Kalite kapısında koşulsuz kırmızıdır
(`sayim-sifir-sayfa`): eşikten bağımsız, yapısal bir kayıp.

Kampanya başında 5 sıfır sayfa vardı. cozumler1'in üçü (s41, s57, s157)
Faz 5 düzeltme 1 ile kapandı. Kalan üçünün her birinin nedeni **farklı**.

## 1. `10sb` s141 — harfli alt sorular (mekanizma yok)

Sayfa bir "Mini Sınav": **tek** numaralı gövde ("1. Aşağıdaki soyağaçlarında
koyu renkli bireyler…") ve altında **a) … h) ile işaretlenmiş 8 soyağacı**,
her birinin yanında ayrı ayrı doldurulacak I/II/III boşlukları. Kör sayıcılar
(ikisi de) 8 saydı — kural gereği doğru: "ayrı ayrı cevaplanacak alt sorular
kadar sayılır".

Motorun bulduğu: **1 aday** (yalnız "1." çapası). `numara_adaylari` yalnız
SAYI çapası arıyor; a)–h) harfli alt sorular için hiçbir mekanizma yok.

**Sınıf:** özellik eksiği (bug değil). Gerekli: paylaşılan gövde + harfli alt
soru düzenini tanıyan bir kesim modu. `duzen_model.py`'nin commit edilmiş
`layout_view`/`instance_view` hiyerarşisi (parent/leaf) tam bu ilişki için
yazılmış ve `soru_kes.py` onu hâlâ tüketmiyor — doğal bağlanma noktası.

## 2. `9konu` s103 — sütun kalibrasyonu çöküyor

```
bantlar = [(0, 172), (172, 2657)]     ← sayfa 2657 px geniş
ham_aday = 8   (numaralar 1..8)
meta = 1        no=None  g=0.03
uyarilar = ('sutun_uzlasmazligi', 'tam_sayfaya_yakin', 'konu_sayfasinda_aday')
```

2657 px'lik bir sayfada 172 px'lik bir birinci bant fiziksel olarak anlamsız.
Sekiz numara adayı bulunuyor ama bant çöktüğü için tek bir numarasız,
"tam sayfaya yakın" kutuya iniyor ve 0,03 güvenle reddediliyor.

**Sınıf:** sütun kalibrasyonu hatası. `sayfa_sutun_kalibrasyonu`'nun bu
sayfada neden 172 px'lik bir ayraç ürettiği ayrıca incelenmeli; asgari bant
genişliği koruması (`G`'nin belirli bir oranı) makul bir savunma olurdu.

## 3. `9pdf` s89 — bulmaca ipuçları + `konu` rolü tavanı

Sayfanın üst yarısı önceki sayfadan devam eden etkinlik adımları (4-7,
**soru değil**), alt yarısı "Kontrol Noktası" bulmacası: "Soldan Sağa"
2,4,6,7,8 ve "Yukarıdan Aşağıya" 1,2,3,4,5 → **10 soru** (altınla birebir).

Motor 14 ham aday buluyor (4 etkinlik adımı + 10 ipucu — tam isabet) ve
9 kutu kuruyor, ama sayfa rolü `konu` (güven 0,94) olduğu için hepsi
**0,35 tavanına** çarpıp reddediliyor.

### Denenen ve GERİ ALINAN düzeltme

`konu` tavanına üçüncü bir kurtarma yolu (doğrulanmış zincir üyeliği) eklendi.
**İşe yaramadı:** iki soru grubunun sol hizaları 61,2 ve 76,4 px, aradaki fark
15,2 px, hizalama toleransı `G × 0,025 = 14,25` px — kıl payı elenip zincir
boş kalıyor. Buna karşılık değişiklik 12meb'e +12, 9pdf'e +8 **altınsız sayfa
kutusu** ekledi; yani ölçülebilir faydası olmayan, ölçülemeyen üretim.

Projenin kendi kuralı gereği geri alındı (`--kiyas` sonucu: `fark yok`).
Bu kayıt, aynı fikrin ileride yeniden denenmesini önlemek için duruyor.

**Sınıf:** rol tespiti + puanlama. Doğru çözüm muhtemelen sayfa rolünü
bölgesel yapmaktır: sayfanın üst yarısı `konu`/etkinlik, alt yarısı
("Kontrol Noktası") `soru`. Bugünkü rol tek ve sayfa geneli.

## Özet

| Sayfa | altın | ham aday | kutu | kök neden | sınıf |
|---|---|---|---|---|---|
| 10sb s141 | 8 | 1 | 0 | a)–h) harfli alt sorular tanınmıyor | özellik eksiği |
| 9konu s103 | 1 | 8 | 0 | 172 px'lik sahte bant | sütun kalibrasyonu |
| 9pdf s89 | 10 | 14 | 0 | sayfa geneli `konu` rolü tavanı 0,35 | rol + puanlama |

Üçü de birbirinden bağımsız ve her biri ayrı bir iş. Hiçbiri "eşik oynatarak"
kapanmaz — kapıda koşulsuz kırmızı olarak duruyorlar ve öyle kalmalılar.
