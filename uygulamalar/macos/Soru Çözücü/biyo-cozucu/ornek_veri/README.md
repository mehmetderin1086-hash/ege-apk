# ornek_veri/

Hafızaya alınabilir referans örnekler. `baslangic.txt` elle yazılmış küçük bir
başlangıç seti; `.jsonl` dosyaları hazır soru-çözüm paketlerinden `paket-al`
komutuyla türetildi.

## Telif

`.jsonl` dosyaları üçüncü taraf yayınların soru ve çözüm metinlerini birebir
içerir. **Bu depo özel kalmalı**; dosyalar dağıtılamaz, yeniden yayımlanamaz.
`make yedekle` hedefi bugün yerel bir çıplak depoya
(`~/Developer/.yedek/biyo-cozucu.git`) yazıyor; uzak bir sunucuya taşınırsa
deponun özel olduğu önce doğrulanmalı.

## Türetilmiş setler

| Dosya | Örnek | Kaynak |
|---|---|---|
| `palme_tyt_1261.jsonl` | 1225 | Palme Yayınları TYT Biyoloji Soru Bankası (1261 sorudan) |
| `ayt_2018_2025_103.jsonl` | 103 | AYT Biyoloji çıkmış sorular 2018-2025 |
| `tyt_2024_2025_47.jsonl` | 47 | TYT Biyoloji çıkmış sorular 2024-2025 |

Palme setinde 36 kayıt elendi: 18'i düşük ayrıştırma güveni, geri kalanı beş
şıkkı da cevap harfi de okunamayan sorular. Bu pakette soru görseli yok —
344 kayıt `gorselsiz_grafik` işaretli, yani grafiği yalnız metinden okunabilir.
AYT ve TYT setlerinin 150 soru görseli `<veri kökü>/gorseller/` altına yazıldı
ve örneklere imzayla bağlandı.

## Yeniden üretim

```bash
U=~/.claude/uploads/<oturum>          # paket zip'lerinin bulunduğu dizin

uv run biyo-cozucu paket-al "$U/Palme_....zip" \
    --jsonl ornek_veri/palme_tyt_1261.jsonl \
    --kaynak "Palme Yayınları TYT Biyoloji Soru Bankası"
uv run biyo-cozucu paket-al "$U/AYT_....zip" \
    --jsonl ornek_veri/ayt_2018_2025_103.jsonl \
    --kaynak "AYT Biyoloji Çıkmış Sorular 2018-2025"
uv run biyo-cozucu paket-al "$U/TYT_....zip" \
    --jsonl ornek_veri/tyt_2024_2025_47.jsonl \
    --kaynak "TYT Biyoloji Çıkmış Sorular 2024-2025"
```

Bayraksız çağrı yalnız künye önizlemesi basar; `--jsonl` olmadan hiçbir şey
yazılmaz. Hafızaya almak için:

```bash
# --indekssiz şart: ornek-ekle her çağrıda TAM indeks kurulumu yapıyor,
# üç dosya ardarda verilirse 1384 metin üç kez gömülür.
uv run biyo-cozucu ornek-ekle ornek_veri/tyt_2024_2025_47.jsonl   --indekssiz
uv run biyo-cozucu ornek-ekle ornek_veri/ayt_2018_2025_103.jsonl  --indekssiz
uv run biyo-cozucu ornek-ekle ornek_veri/palme_tyt_1261.jsonl     --indekssiz
uv run biyo-cozucu indeksle
```

## Bilinmesi gerekenler

**Konu eşlemesi `biyo_cozucu/veri/paketler.py`'de yaşıyor.** Kaynak konu adları
(Palme'de 100'den fazla ince taneli başlık) `hafiza/etiketleme.py:KONU_IPUCLARI`
anahtarlarına çevriliyor; `kapsam.py` konu eksenini doğrudan o sözlükten
türettiği için kanonik olmayan bir konu dizgesi kapsam matrisinde sayılmaz.
Yeni bir paket eklerken eşleme tablosunu genişletin — `test_paketler.py`
tabloların tümüyle kanonik kaldığını doğruluyor.

**Palme çözümleri kısmen şablon.** 1876 ifade açıklamasının yalnız 258'i
benzersiz; 356 kayıt `sablon_cozum` işaretli. Üretilen çözümlere üslup
bulaşırsa set `paket-al --sablonu-ayikla` ile yeniden türetilebilir; bu,
korpusta tekrarlayan satırları düşürür.

**Çözüm uzunluğu.** Palme çözümleri ortalama 2213 karakter ve 1012'si
`getirme.py`'nin 1800 karakterlik kanıt sınırını aşıyor. Katmanlar bilgi
yoğunluğuna göre sıralandığı için kırpma yalnız seçenek analizinin kuyruğunu
düşürür — sonuç ve temel bilgi her zaman içeride kalır.

**Kanıt adım sınırı.** Bu setler hafızaya girdikten sonra kanıt çözümlerinin
ortalama adım sayısı 4'ten 14'e çıktı (Palme'de azami 57) ve model few-shot
örneğinin uzunluğunu taklit edip yanıtı yarıda bırakmaya başladı.
`Ayarlar.kanit_azami_adim` (varsayılan 6) kanıtları istemde adım sayısıyla
sınırlar; istem 6777 karakterden 4548'e iniyor. Sınırı kaldırmak için `0`.
