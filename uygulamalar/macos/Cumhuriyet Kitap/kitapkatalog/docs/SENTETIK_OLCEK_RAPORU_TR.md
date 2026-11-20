# Sentetik ölçek doğrulama raporu

Tarih: 2026-07-26  
Makine: Apple M4, 16 GiB RAM  
Çalışma zamanı: Python 3.12.13, SQLite 3.53.1, openpyxl 3.1.5

Bu rapor gerçek KitapKatalog SQLite, FTS5 ve dışa aktarım kodunu kullanır.
Katalog verisi sentetiktir. Beş ağır model paketi bu çalışma alanında
bulunmadığı için sonuçlar OCR hızı veya doğruluğu olarak yorumlanamaz.
İki kitap işçisinin motor semaforları ve Qwen bariyeri otomatik test
kapsamındadır; bu rapor ağır modellerle eşzamanlı tepe RSS ölçümü değildir.

## Kalıcı dört-yüzlü kuyruk

Sürüm 0.2.0 dört-yüz geçişinden sonra 10.000 kitap/40.000 belge yolu tek işe
gerçek `Database.create_import_job()` koduyla eklendi:

- 10.000 iş öğesi 0,1679 saniyede yazıldı.
- 10.000 `front_inside_path` ve 10.000 `back_inside_path` satırı doğrulandı.
- Veritabanını yeni nesneyle açıp işi yeniden okuma 0,000433 saniye sürdü.
- SQLite ana dosyası 4.231.168 bayttı.
- `PRAGMA integrity_check=ok`; yeniden okunan işte 10.000 öğe vardı.

Bu test görüntü dosyalarını açmaz ve OCR modellerini çalıştırmaz; yalnız
40.000 yüz yolunun dayanıklı kuyruk sözleşmesini sınar. Dört yüzün her birinde
beş motor olmak üzere yirmi checkpoint zorunluluğu ve önbellekten yeniden
çalışma davranışı otomatik uçtan uca scheduler testlerinde doğrulanmıştır.

## 100.000 kayıt arama, filtre ve sayfalama

| Vaka | Sonuç | Medyan | p95 |
|---|---:|---:|---:|
| Tekil FTS | 1 | 0,474 ms | 0,574 ms |
| 100.000 eşleşmeli FTS | 100.000 | 46,950 ms | 50,563 ms |
| Türkçe `İstanbul` FTS | 100.000 | 46,367 ms | 48,254 ms |
| Yayınevi filtresi | 5.000 | 59,669 ms | 64,351 ms |
| FTS + yayınevi/dil/durum | 5.000 | 82,595 ms | 84,776 ms |
| İlk 50 kayıt | 100.000 toplam | 10,921 ms | 11,349 ms |
| Son 50 (`offset=99.950`) | 100.000 toplam | 68,688 ms | 74,235 ms |

Veritabanı boyutu 149.782.528 bayt, dış süreç tepe RSS değeri
117.473.280 bayt ve bütünlük sonucu `ok` idi.

## 10.000 kayıt dışa aktarımı

| Biçim | Saf dışa aktarım | Dosya boyutu | Ek tepe bellek |
|---|---:|---:|---:|
| CSV | 0,236 sn | 3.664.168 bayt | 10.993.664 bayt |
| JSON | 0,344 sn | 11.730.550 bayt | 11.239.424 bayt |
| XLSX | 1,169 sn | 1.344.505 bayt | 11.616.256 bayt |

CSV UTF-8 BOM taşıdı; JSON 10.000 kitap içerdi; XLSX’in istenen yedi sayfası
ve 10.000 kitap satırı doğrulandı. Hiçbir `.part` artığı kalmadı. Bu ölçümler
60/180 saniye ve 750 MB dışa aktarım kabul sınırlarının altındadır.
