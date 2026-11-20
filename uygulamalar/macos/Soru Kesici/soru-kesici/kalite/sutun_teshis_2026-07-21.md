# Sütun-Taşma Kök Neden Teşhisi — 2026-07-21

Kaynak: salt-okunur runtime izleme (`.venv/bin/python`, `dogrula.belge_isle` +
`soru_kes` iç fonksiyonlarını doğrudan çağırma). Motor koduna ve veri
dosyalarına yazılmadı. Örnek sayfalar: aydin s31/s55/s79, ygslys s16/s36/s121,
karşılaştırma 12meb s66. Ham iz: `scratchpad/sutun_iz_cikti.json`.

`sutun-tasma` tanımı (`dogrula.py:1969-1977`): bir kutu, bantların **≥2**'siyle
kutu genişliğinin >%20'si kadar örtüşürse (`degen >= 2`) işaretlenir. Yani sorun
her zaman "kutu birden çok banda yayılıyor" — ya bantlar yanlış konumda, ya kutu
yanlış genişlikte.

---

## (a) Sütun karar akışının haritası (fonksiyon:satır)

Akış `dogrula.belge_isle` -> `soru_kes` üzerinden:

1. `belge_isle` (`dogrula.py:1585`) her sayfa için `sk.sayfa_sutunlari(s)`
   (`soru_kes.py:2435`) -> `sayfa_sutun_kalibrasyonu(s).bantlar`, ve
   `sk.sorulari_tespit_meta(s, fmt)` (`soru_kes.py:3222`) çağırır. Kutular
   meta'dan gelir; anomali bu iki çıktının kesişiminden hesaplanır.
2. **Bant kararı** `sayfa_sutun_kalibrasyonu` (`soru_kes.py:2250`): çok-yöntemli
   oylama. Girdiler:
   - `_sayfa_sutunlari_v21` (`:1792`) -> raster'da önce
     `_raster_gorsel_kume_bantlari` (`:1724`, numara kümelerini görsel banda
     oturtur), o başarısızsa `_numara_bant` (`:1759`, **numara-x tabanlı**).
   - `_coklu_projeksiyon_ayraclari` (`:1965`) ve
     `_bolgesel_projeksiyon_ayraclari` (`:1993`) -> **görsel beyaz-vadi** seam'leri.
   - `_numara_bant` çapaları (`ocr_capalari`) — yine numara tabanlı.
   - (isteğe bağlı) DocLayout / soru-modeli ayraçları.
   - Ağırlıklar `:2288-2295`: v21_geometri 0.36, ocr_capalari 0.34,
     coklu_projeksiyon 0.22+, bolgesel_seam 0.18+. Kümeleme `:2296`, "güçlü"
     eşiği (>=2 yöntem & toplam>=0.48) `:2303`, **birbirine yakın ayraçlarda
     yüksek-destekliyi tut** filtresi `:2315-2321`.
3. **Kutu inşası** `sorulari_tespit_meta`: numara çapasından kutu kurulurken
   `_aday_bant_araligi` (`:3288`) kutunun kaplayacağı **bant aralığını** belirler
   (aynı yatay satırdaki yan yana OCR parçalarını zincirleyerek genişletir).
   Sonra `_kutu_insa` (`:3511`) hard-clamp ile kutuyu `bantlar[bant_bas][0] ..
   bantlar[bant_son][1]` aralığına sıkıştırır (`:3610-3612`). **Kritik:** clamp
   yalnız _aralığa_ sıkıştırır; aralık iki bandı kapsıyorsa kutu iki-sütun geniş kalır.

Yani "sutun-tasma" iki bağımsız arızadan doğabilir: **(A)** bant sınırı yanlış
konumda (numara-midpoint çok solda), **(B)** `_aday_bant_araligi` kutuyu gutter'ın
karşısına genişletiyor (birleşmiş OCR satırı). İki belge iki farklı arızayı
gösteriyor.

---

## (b) aydin kök nedeni — OCR satır-birleşmesi -> tam-genişlik kutu

**Bantlar DOĞRU tespit ediliyor.** aydin s31: `kal.bantlar = [[0, 1064.3],
[1064.3, 2117]]` — 2 sütun, ayraç 1064.3'te; v21 (1061), coklu_proj (1061.8),
bolgesel (1071.7) hepsi hemfikir. Buna rağmen s31'de bir kutu tam-genişlik çıkıyor:

```
TASMA  [0.0, 2280.4, 2117.0, 2905.1]  no=3  bant=0  degen=2
```

Neden: numara "3."in ilk gövde satırını Apple Vision **soldaki 3. soru + sağdaki
6. soruyu tek OCR satırında birleştirmiş** (köprü izinden):

```
[167.9, 2290, 1896.0, 2366]  "ATP' deki yüksek ener|l fosfat bağlarının yıkıl, 6. Aşağıdak"
[48.6, 2316.9, 172.4, 2366]  "• 3."
```

Bu birleşik satır x in [167.9..1896], yani gutter'ı (1064) geçiyor.
`_aday_bant_araligi` (`:3299-3320`) bunu "aynı satır + yatay bağlı" sayıp kutunun
bant aralığını `{0}`'dan `{0,1}`'e genişletiyor -> hard-clamp `[ban_sol=0,
ban_sag=2117]` uyguluyor -> tam-genişlik kutu. Guard
`baska_numara = SORU_NO_DESENI.match(smetin)` (`:3313`) yalnız **satırın
başındaki** numarayı reddediyor; "6." satır ORTASINDA olduğu için
(`SORU_NO_DESENI` `^` çapalı, `:59`) yakalanmıyor. s55 numara=1 ("... sınıflandırma
yapılırken O 5."), s79 numara=1 ("... bazı evreler O 4.") aynı örüntü.

Raporun "22 sayfada x in [0..2117]" örüntüsü bu tek nedene iniyor: **gutter'ı geçen
birleşik OCR satırı kutuyu iki sütuna açıyor.**

**İkincil aydin arızası (s55/s79 — sahte 3. bant + bos-sutun):** Bu iki sayfada
`_raster_gorsel_kume_bantlari`, dekoratif sol şerit bandı (ör. s79 gorsel_bant
`[44,147]` genişlik 103 < G*0.055=116) yüzünden `None` dönüp `_numara_bant`'a
düşüyor; o da ayracı numara-midpoint'e (s79: 543.6 = numara 110 ve 976'nın ortası)
koyuyor. Ama görsel gutter (~1060) de ayrı ayraç olarak güçlü kalıyor ve ikisi
G*0.12 (254px) uzak olduğundan **ikisi de hayatta kalıyor** -> 3 bant
`[0-543.6, 543.6-1045.7, 1045.7-2117]`. Sonuç: tam-genişlik kutuların merkezi dış
bantlara düşüp ortadaki sahte bant boş kalınca **bos-sutun** (s79 [544..1046]) +
kutular çok-bantlı olunca **sutun-tasma** birlikte üretiliyor.

## (c) ygslys kök nedeni — numara-midpoint sınırı çok solda -> kısmi örtüşme

ygslys sayfaları 4-sütun ve YOĞUN; **görsel projeksiyon 3 gutter'ın hepsini
ayıramıyor** (s16 `gorsel_bantlar` yalnız [249,1486.5],[1486.5,2748] — tek gutter
buluyor). 4 numara kümesine karşılık <=2 görsel bant olunca
`_raster_gorsel_kume_bantlari` `None` dönüyor -> `_numara_bant` devrede.

Numara sütunları x ~ 205, 825, 1557, 2202. `_numara_bant` sınırları numara-x
**orta noktalarına** koyuyor: 514.9, 1190.9, 1879.5 (`kal.ayraclar` bunlar). Ama
`coklu_proj`/`bolgesel_proj` gerçek beyaz gutter'ları **daha sağda** buluyor:
~838, ~1485, ~2215. Numara sol-kenarı işaretler, metin sağa dolar; dolayısıyla
numara-midpoint (1191) gerçek gutter'dan (1485) **~290px sola** düşüyor.

Kanıt — kutu ve numara satırı bu yanlış sınırı geçiyor:

```
TASMA  numara=13  kutu=[514.9, 163.7, 1400.2, 681.8]  bant=1  degen=2
       numara_kutu=[824.7, 188, 1377.2, 222]  "13. Aşağıdaki grafikte, biyokimyasal reaksiyon-"
```

13. sorunun KENDİ ilk satırı x in [824.7..1377.2]; sağ kenarı 1377, sınırı 1190.9'u
geçiyor ama gerçek gutter 1485'i geçmiyor. Yani satır tek sütuna ait, sınır onu
ortadan kesiyor. `_aday_bant_araligi` numara satırı zaten bant 2'ye taştığı için
aralığı {1,2} yapıyor -> kutu iki-sütun geniş -> sutun-tasma. Sınır 1485'te olsaydı
satır tek banda sığardı. (aydin'in aksine burada OCR **birleşme yok**; 11/3/13
aynı y'de ayrı bbox'lar. Arıza saf **sınır konumu**.)

**Konsensüs neden yanlışı seçiyor:** `sayfa_sutun_kalibrasyonu`'nda numara-midpoint
(514.9) hem `v21_geometri` (0.36) hem `ocr_capalari` (0.34) tarafından oylanıyor =
0.70 birleşik destek, "güçlü". Görsel gutter (838) coklu+bolgesel = ~0.56, o da
"güçlü". İkisi G*0.12 içinde yakın (838-515=323 < 346) -> **yüksek-destekliyi tut**
filtresi (`:2315-2321`) numara-midpoint'i (0.70) tutup görsel gutter'ı (0.56)
düşürüyor. Ama `v21_geometri` ile `ocr_capalari` **ikisi de numara türevi**
(bağımsız değil) — birlikte sayılınca numara-artıfaktı sahte "güçlü" görünüyor.

## (d) bos-sutun bağlantısı

Evet, aynı sütun-tespit zayıflığının diğer yüzü. aydin s79 bos-sutun [544..1046]
doğrudan (c)/(b)'deki sahte 3. banttan doğuyor: numara-midpoint (543.6) + görsel
gutter (1060) ikisi de yaşayınca ortada boş bir hayalet bant oluşuyor ve
tam-genişlik kutu merkezleri onu doldurmayınca "boş sütun" işaretleniyor. aydin
s91 [1063..2117] ve ygslys s16 [1191..1880] aynı mekanizma. **Bantları
doğrulayan bir düzeltme bos-sutun'u da azaltır.** (9konu s43/s73 sağ sütun bu
koşumda incelenmedi; muhtemelen ayrı bir "sağ sütun OCR'da kaçtı" alt-durumu —
sütun-konum değil, sütun-boşluğu doldurma sorunu; ayrı doğrulama ister.)

## Karşılaştırma — 12meb (0 anomali) neden doğru

12meb s66 **metin PDF** (raster=False). Temiz bbox projeksiyonu gutter'ı net
buluyor: `coklu_proj=[267.7 destek 1.0]`, `bolgesel=[260.4 destek 1.0]`, sonuç
`kal.ayraclar=[265.4]`. Numara-midpoint 158.7 hesaplansa da metin sayfasında
`_gorsel_numara_rafine` görsel bandı KORUYOR -> sınır gerçek gutter'da (265.4),
8 kutunun hepsi `degen=1`, tasma=0. Fark: aydin/ygslys **taranmış + yoğun**,
görsel projeksiyon yetersiz kalıp numara-midpoint yedeğine düşüyor; 12meb'de
görsel yeterli olduğu için doğru gutter kazanıyor.

---

## (e) Düzeltme adayları

### Aday 1 — Yakın ayraç çakışmasında GÖRSEL gutter'ı tercih et (ygslys)
- **Yer:** `soru_kes.py:2315-2321` (`sayfa_sutun_kalibrasyonu`, "too-close" filtresi).
- **Fikir:** İki ayraç G*0.12 içinde yakınsa yalnız yüksek-destekliyi tutmak yerine,
  biri görsel (`coklu_projeksiyon`/`bolgesel_seam`/`doclayout_yolo`) diğeri saf
  numara (`v21_geometri`+`ocr_capalari`) ise **görsel ayracın konumunu** kullan
  (numara sütunun sol-kenarını, görsel seam gerçek boşluğu işaretler). Ek olarak
  `v21_geometri` ve `ocr_capalari` aynı x'te çakıştığında tek kaynak say
  (`:2298-2304` "güçlü" hesabında) — böylece numara-only ayraç bağımsız görsel
  destek olmadan "güçlü" sayılmaz.
- **Çözmesi beklenen:** ygslys 66 sutun-tasma'nın büyük kısmı (sınır 1191->1485
  gibi sağa kayınca kutular tek banda oturur) + ygslys s16 bos-sutun.
- **Regresyon riski:** Görsel seam'in gürültülü olduğu, numara-midpoint'in daha
  doğru olduğu sayfalar. Ama coklu (>=3 görüş) ve bolgesel (>=2 şerit) zaten
  oylanmış seam'ler; düşük. İzlenecek: cozumler1 (x in [0..740]) ve 10sb (2-sütun).

### Aday 2 — Kutu genişletmesini doğrulanmış gutter'da durdur (aydin tam-genişlik)
- **Yer:** `soru_kes.py:3299-3320` (`_aday_bant_araligi` yatay genişletme döngüsü).
- **Fikir:** Bir aday satırı, yüksek-güvenli bir görsel ayracı (`kal.ayraclar`,
  guven>=~0.8) geçiyorsa VE `_bolgesel_gecis_dogrula` gerçek tam-genişlik geçişini
  doğrulamıyorsa, bant aralığını gutter'ın ötesine **genişletme** (birleşik OCR
  satırını kır). Yani `_aday_bant_araligi` yalnız `bolgesel_gecis=True` sayfalarda
  gutter aşabilsin. Alternatif/ek: guard'ı `SORU_NO_DESENI.match` yerine
  "satır içinde farklı banda düşen bir soru-no jetonu var mı" testine çevir
  (satır-ortası "6." yakalansın).
- **Çözmesi beklenen:** aydin'in x in [0..2117] tam-genişlik kutuları (22 sayfa,
  ~sutun-tasma 21+).
- **Regresyon riski:** Gerçek tam-genişlik/gutter-üstü sorular (aile
  `*_tam_genislik_gecisli`). Bunlar zaten `duzen_bolgeleri_uret`/`bolgesel_gecis`
  yolundan yönetildiği için, genişletmeyi yalnız `bolgesel_gecis` sayfalarına
  bağlamak güvenli. İzlenecek: 11fen s103, 9pdf s133 (tek-bant kutular etkilenmemeli).

### Aday 3 — Numara-midpoint yedeğini gerçek metin kenarına yasla (her ikisi)
- **Yer:** `soru_kes.py:1784-1787` (`_numara_bant` fallback dalı).
- **Fikir:** Metin yüzdelikleri örtüştüğünde (gutter-aşan satırlar yüzünden)
  `(merkez[i-1]+merkez[i])/2` yerine sınırı **sonraki sütunun numara sol-kenarına
  yakın** koy: ör. `min(sol_sonraki, merkez[i] - G*0.02)` gibi sağa yaslı bir değer.
  Numara sol-kenarı işaretlediğinden, gerçek gutter numara[i]'nin hemen soluna daha
  yakındır, ikisinin ortasına değil.
- **Çözmesi beklenen:** ygslys tipi kısmi taşmalar + aydin s55/s79 sahte 3. bant
  (numara-midpoint sağa kayınca görsel gutter'la çakışıp tek sınıra iner).
- **Regresyon riski:** Sütunların gerçekten simetrik/dar olduğu düzenler; sınırın
  fazla sağa gidip bir sonraki sütunun numarasını kesmesi. `merkez[i]-G*0.02`
  tavanı bunu sınırlar. Aday 1 ile birlikte uygulanırsa Aday 3 ikincil kalabilir.

**Öneri:** Aday 2 (aydin) + Aday 1 (ygslys) birlikte 95/106 sutun-tasma'yı hedefler;
ikisi ayrı arıza olduğu için ayrı ayrı ölçülmeli. Aday 3 numara-yedeğini genel
olarak sağlamlaştıran düşük-riskli destek.
