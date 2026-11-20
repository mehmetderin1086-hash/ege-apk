# Zincir çapası kuralı — ölçüm ve gerekçe (2026-07-25)

## Bulgu: anomali 0 iken recall 0,69

`cozumyazili` belgesinde **kör sayım** (çıplak sayfa render'ı, motorun kutuları
görülmeden) sonucu:

| Sayfa | Gerçek soru | Motor (önce) | Motor (sonra) |
|---|---|---|---|
| 1 | 6 | 6 | 6 |
| 2 | 6 | 4 | 6 |
| 3 | 7 | 4 | 6 |
| 4 | 5 | 1 | 5 |
| 5 | 5 | 5 | 5 |
| 6 | 10 | 7 | 7 |
| **Toplam** | **39** | **27** | **35** |

`count_recall` **0,692 → 0,897**, `count_precision` 1,000 (hiç fazla üretim yok).
Anomali sayısı iki durumda da **0** — proxy bu kaybı hiç görmüyordu.

## Kök neden

`blok_gecerli_mi` üç pozitif yol tanıyordu: şık (A–E) VEYA soru kipi
(…mıdır/hangisi) VEYA yazma alanı. Cevap anahtarı ve yazılı çözüm kâğıtlarında
gövde **düz metindir** ve üçüne de uymaz → blok elenirdi. Eleme iki yerde
oluyordu:

1. **Ön-filtre** (`soru_kes.py`, zincir seçiminden önce) — adaylar zincire hiç
   ulaşamıyordu. Asıl kayıp burada: sayfa 4'te 5 numaralı adaydan 4'ü burada
   düşüyordu.
2. `_kutu_insa` içindeki geçerlilik kapısı.

Ayrıca `acik_uclu` sayfalarda minimum kutu yüksekliği `0.05·Y` (~42 pt); tek
satırlık cevap ("4. Plasenta") bu eşiğe takılıyordu.

## Kural

Sayfada **doğrulanmış artan numara zinciri** (`en_uzun_zincir` ≥ 3 üye) varsa,
o zincirin numaralı üyeleri için içerik-kalıbı kanıtı gevşetilir: yeterli
gerçek içerik (≥20 harf/rakam) taşıyan ve İÇİNDEKİLER lider satırı olmayan
blok geçerli sayılır; minimum yükseklik genel tabana (`0.022·Y`) düşer.

Korumalar yerinde kalır — hepsi zincir kanıtından **önce** çalışır:
- talimat/başlık desenleri (`numara_adaylari` elemesi),
- tanım maddesi ("1. Duyu Nöronu:" — kısa, iki nokta ile biten),
- `kati=True` (numara çapasız blok-segmentasyon) yolunda gevşetme YOK.

## Korpus etkisi — hepsi doğrulandı

| Belge | Kutu (önce → sonra) | Anomali |
|---|---|---|
| 9konu | 60 → 94 | 0 → 0 |
| cozumler1 | 256 → 334 | 3 → 3 |
| 9pdf | 77 → 116 | 3 → **2** |
| 12meb | 77 → 108 | 0 → 0 |
| ygslys | 380 → 414 | 0 → 0 |
| aydin | 188 → 205 | 0 → 0 |
| cozumyazili | 27 → 35 | 0 → 0 |
| 11fen | 47 → 55 | 1 → 1 |
| 10sb | 172 → 177 | 2 → 2 |

**Hiçbir belgede anomali artmadı.** En büyük artışlar kör sayımla doğrulandı:

- `9konu` s79: motor **0 → 16** kutu. Sayfa bir "Etkinlik" sayfası ve üzerinde
  gerçekten **16 boşluk-doldurma sorusu** var. Eskiden sayfanın tamamı
  kaçıyordu.
- `9konu` s55: motor **1 → 15**. Sayfada 16 boşluk-doldurma sorusu var.

Yani artış yanlış-pozitif değil, daha önce tümüyle kaçan gerçek soruların
kurtarılmasıdır. Bu sayfa sınıfı (boşluk doldurma etkinlikleri) hiçbir şık,
soru kipi ya da noktalı yazma alanı taşımadığı için eski üç yolun hiçbirine
uymuyordu.

## Daraltma: çoktan seçmeli sayfalarda uygulanmaz

İlk sürüm formattan bağımsızdı ve **altın verili** TYT kalibrasyonunda
gerileme üretti: kutu 765 → 813, `F1 0,975 → 0,966` (P 0,947 / R 0,985,
41 yanlış-pozitif), `F1@0,75 0,958 → 0,937`. 10 belgelik korpusta anomali
artışı YOKTU — düşüş yalnız altın veriyle görüldü.

Kural bu yüzden `fmt != "coktan_secmeli"` ile sınırlandı: çoktan seçmeli bir
sayfada gerçek soru zaten şık taşır, gevşetmenin kazancı yok, maliyeti var.
Daraltma sonrası TYT `F1 0,975` / `F1@0,75 0,958` (taban değerlere döndü) ve
`cozumyazili` kazancı korundu (`count_recall` 0,897).

Bu olay kapıya da yansıtıldı: `kalite/kapi_esikleri.json` + `_altin_kapisi`
artık altın verili belgelerde F1/precision/recall/F1@0,75 tabanının altına
düşüşü **kırmızı** sayıyor. Aksi halde bu gerileme yine yalnız elle fark
edilebilirdi. Ratchet kuralı: ölçüm tabanın belirgin üstündeyse kapı yeni
taban önerir, yükseltme insan onayıyla dosyaya yazılır.

## Daraltmanın korpustaki bedeli — bilinçli, ama doğrulanmamış

Daraltma yalnız TYT'yi değil, çoktan seçmeli sınıflanan diğer sayfaları da
etkiledi: `cozumler1` 334 → 289, `ygslys` 414 → 380, `aydin` 205 → 188,
`12meb` 108 → 102. `9konu` (93) ve `cozumyazili` (35) kazançları korundu —
oradaki kurtarma açık uçlu / etkinlik sayfalarından geliyordu.

**Bu düşüşlerin yanlış-pozitif temizliği mi yoksa gerçek kayıp mı olduğu
ÖLÇÜLMEDİ**: bu belgelerin hiçbirinde altın veri yok. Karar, altın verinin
bulunduğu tek yerdeki (TYT) ölçüme dayanarak verildi — orada gevşetmenin
41 yanlış-pozitif ürettiği kesin. Muhafazakâr taraf seçildi: kanıtlanmış
precision kaybını kabul etmektense, kanıtlanmamış recall kazancından vazgeçmek.

Bu belirsizliği kapatmanın tek yolu, `altin_sayim.py` ile bu dört belgeye de
sayım-altını üretmektir. Sıradaki iş budur.

## Kalan iş

`cozumyazili` s6'da hâlâ 10 sorudan 3'ü eksik (`count_recall` 0,897).
`9konu` s55'te 16'dan 1'i eksik. Kalan kaçırmalar tek tek incelenmeli;
sayım-altını kapsamı diğer belgelere yayılmalı.
