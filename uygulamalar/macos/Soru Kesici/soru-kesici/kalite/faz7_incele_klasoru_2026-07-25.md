# Faz 7 — `İncele/` klasörü: "sıfır hata"nın ürün karşılığı

**Tarih:** 2026-07-25

## Sorun

`strict` ve `balanced` kiplerinde `incele` durumundaki kesimler çıktıya
**hiç yazılmıyordu**. Yani motor bir soruyu buluyor, kutusunu doğru kuruyor,
ama emin olamadığı için **sessizce atıyordu**. Kullanıcı ne kaybettiğini
bilmiyordu.

Kullanıcının seçtiği "sıfır hata" tanımı bunun tam tersini istiyor:
*otomatik teslim edilen her kesim kusursuz olacak; emin olunamayanlar
silinmek yerine ayrı klasöre gerekçesiyle yazılacak.*

## Çözüm

`kirpma_plani_meta` / `kirpma_seti` yeni bir `kova` parametresi aldı:

| kova | içerik |
|---|---|
| `"cikti"` (varsayılan) | bugünkü davranış **birebir** — otomatik/onaylı alt küme |
| `"incele"` | **tam tümleyeni** — tespit edilmiş ama otomatik teslim edilemeyen |

`inceleme_seti(...)` bunun kısayolu. `zip_yaz(..., incele=, incele_sorular=)`
bu kesimleri `İncele/` alt klasörüne + `İncele/sorular.json`'a yazar.
**Ana çıktı birebir aynı kalır** — incele kovası ana klasöre karışmaz, bu
yüzden `final_cuts` ve altın F1 etkilenmez (doğrulandı: kalibrasyon
0,993 / 0,983 değişmedi).

### Kovalar tam tümleyen — ölçüldü

`cozumyazili` (6 sayfa, balanced):

```
ana çıktı : 29 kesim
İncele    :  5 kesim
legacy    : 34 kesim   →  29 + 5 = 34   ✓
```

Ne sessiz kayıp ne mükerrer üretim. Bir test bu değişmezi kilitliyor
(`test_kovalar_ayrik_ve_tamamlayici`).

## Her kesim gerekçesini taşır

Ölçüldü: `incele` kutularının **28/49'u hiçbir uyarı taşımıyordu** — güven
0,55-0,82 arasında kaldığı için düşüyorlardı ama nedeni hiçbir yere
yazılmıyordu. Gerekçesiz bir `İncele/` klasörü kullanıcıyı sayfayı baştan
incelemeye zorlardı.

`aday_inceleme_gerekcesi(m)` uyarı yoksa eksik kanıtı adlandırır. Gerçek
çıktıdan:

```
İncele/incele_01.png  s1 no=2  ['sutun_uzlasmazligi']
İncele/incele_02.png  s2 no=9  ['coklu_numara_icerik']
İncele/incele_03.png  s3 no=1  ['kanit_yetersiz: şık kümesi yok, soru kipi yok']
İncele/incele_04.png  s6 no=8  ['sutun_uzlasmazligi']
```

## CLI

```
$ .venv/bin/python soru_kes.py "…YAZILI COZUM.pdf" -o cikti.zip --kalite balanced
  UYARI: 4 riskli sayfa dışlandı; yalnız otomatik/onaylı sorular yazılacak.
  29 soru kesildi · 4 test
✓ 29 soru → cikti.zip
  5 kesim İncele/ klasörüne yazıldı (otomatik teslim edilemedi; gerekçeler
  İncele/sorular.json içinde)
```

`legacy` kipinde İncele kovası boştur (her şey zaten ana çıktıya gider) —
aksi halde aynı kesim iki kez üretilirdi; bu da testle kilitli.

## Kapı sertleştirme (aynı fazın ikinci yarısı, daha önce yapıldı)

* `--kapsam A|B|C` — 10 / 41 / 44 belge, katmanlar iç içe; `C`'de `--sert`
  otomatik açılır.
* `--rapor <yol>` koşumu JSON'a yazar, `--kiyas <yol>` belge bazlı delta
  tablosu basar.
* Her koşumun sonunda **aile bazlı toplam satırı** — aynı kuralın ailelere
  zıt etkisi 44 belgede ancak böyle görünür.
* Ölü ölçüm artıkları silindi (`once_1sinav.json`, 11 adet `sonra_*.json`,
  4 adet `*_zip_*.txt`).
