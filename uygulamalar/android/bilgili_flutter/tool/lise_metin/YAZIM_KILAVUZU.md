# Lise metin aileleri · Yazım kılavuzu

Bu klasördeki araçlar, `lib/data/advanced/lise_metin/` altındaki ailelerin yazımını ve denetimini düzenler. Her aile lise düzeyinde, yalnız metinden oluşan 5.000 ayrı soru üretir. Aileler sorunun kökünü, doğru yanıtını, üç çeldiricisini ve açıklamasını sıra numarasından hesaplar; uygulama soruyu açıldığı anda üretir.

## Dosyalar

- `lib/data/advanced/lise_metin/ortak.dart`: aile kurucuları (`lmAile`, `lmSirali`) ve yardımcılar (`sayisal`, `ondalikli`, `kesirli`, `secenekli`, `tr`, `kesir`, `kombinasyon`, `sec`).
- `tool/lise_metin/ornek_aile.dart`: bir sayısal ve bir sözel başvuru ailesi.
- `tool/lise_metin/denetim.dart`: her vakayı açan denetim.
- `tool/lise_metin/<alan>_test.dart`: alanın denetimini çalıştırır.

Denetimi çalıştırma:

```sh
flutter test --no-pub tool/lise_metin/<alan>_test.dart
```

## Bir ailenin taşıması gerekenler

1. **Tek kazanım.** Aile, lise müfredatındaki tek bir kazanımı sınar. Başlık bu kazanımı adlandırır (8–60 karakter).
2. **5.000 farklı kök.** `lmAile` üreteci `(a, b, c)` alır: a ∈ [0, 25), b ∈ [0, 20), c ∈ [0, 10). Her üçlü farklı bir soru kökü vermelidir; bunun için a, b ve c kökte görünen verileri birebir belirlemelidir. Sözel ailelerde `lmSirali` ve `kombinasyon` kullanılır; öge listesi C(n, k) ≥ 5.000 olacak kadar uzun tutulur.
3. **Hesap değişmeli.** Varyantlar arasında yalnız kişi ya da nesne adı değişmemeli; veri değiştiği için çözüm de değişmelidir. Adlar kökü zenginleştirebilir ama tekliğin tek kaynağı olamaz.
4. **Kesin anahtar.** Doğru yanıt parametrelerden kesin olarak hesaplanır. Parametreleri, sonuç tam sayı, sade kesir ya da en çok iki ondalık basamaklı sayı çıkacak biçimde seçin. Yuvarlama gerekiyorsa kök bunu açıkça ister.
5. **Gerçekçi veri.** Hız, kütle, fiyat, yaş, sıcaklık gibi büyüklükler gerçek hayattaki aralıklarda kalır. Uzunluk, kütle, süre ve sayım sonuçları negatif ya da sıfır olmaz. Bölen sıfır olmaz, kök içi negatif olmaz.
6. **Tipik hatalardan çeldirici.** Üç çeldirici, öğrencilerin sık yaptığı hatalardan (işaret hatası, bölmeyi unutma, yanlış formül, birimi çevirmeme, ara sonucu yanıt sanma) hesaplanır. Dört seçenek değerce birbirinden farklı olmalıdır; `1/2` ile `0,5` aynı sayılır. Yardımcılar yinelenen adayları atar ve gerekirse komşu değerlerle tamamlar.
7. **Açıklama.** Açıklama, o vakanın sayılarıyla çözüm yolunu bir iki cümlede gösterir.
8. **Yanıt türü.** Yanıt düz bir sayı, kesir ya da kısa bir terimse `shortAnswer: true` olur; uygulama bu ailelerdeki soruların bir bölümünü boşluk doldurma olarak sorar. Yanıt bir cümle ya da dizi ise `shortAnswer: false` yazılır. Birimli yanıtlarda birim `Question.acceptsWritten` içindeki isteğe bağlı birimlerden biri olmalıdır (ör. `m`, `cm`, `km`, `m/s`, `km/sa`, `N`, `J`, `W`, `kg`, `g`, `L`, `mL`, `mol`, `°C`, `K`, `V`, `A`, `Ω`, `Pa`, `Hz`, `TL`, `%`, `s`, `dk`, `saat`, `gün`, `yıl`, `kişi`, `adet`); listede olmayan birimlerde ya birimi köke taşıyıp yanıtı birimsiz bırakın ya da `shortAnswer: false` yazın.
9. **Sınav ve ders etiketi.** `lesson` her ailede verilir. `exam` verilirse `lesson` o sınavın ders listesinden olmalıdır: TYT için `Türkçe`, `Temel Matematik`, `Fizik`, `Kimya`, `Biyoloji`, `Tarih`, `Coğrafya`, `Felsefe`; AYT için `Matematik`, `Fizik`, `Kimya`, `Biyoloji`, `Edebiyat`, `Tarih-1`, `Coğrafya-1`.
10. **Bloom ve güçlük.** Tek adımlı tanıma hatırlama ya da anlama, doğrudan formül uygulaması uygulama, çok adımlı ya da koşullu çözüm analiz, bir yorumu ya da yöntemi ölçütle tartma değerlendirme basamağıdır. Yaratma basamağı kullanılmaz. Güçlük `Difficulty.easy`, `medium` ya da `hard` olur.

## Dil ve biçim

- Kök tam cümlelerle, soru ekiyle biten açık bir soruyla yazılır. Markdown, LaTeX ve HTML kullanılmaz. `x²`, `10³`, `√`, `π`, `·`, `−`, `≤`, `°` gibi Unicode simgeleri kullanılabilir.
- Ondalık ayırıcı virgüldür (`2,5`). Sayıları yazarken `tr(...)` kullanın; Dart'ın `3.0` ya da `2.5` yazımı denetimden geçmez. Binlik ayırıcı kullanılmaz.
- Değişen bir sayıya ya da değişen bir sözcüğe ek getirmeyin: “`$n`'in”, “`$x`'e” gibi yazımlar ünlü uyumunu bozar ve denetimden geçmez. Cümleyi “değeri $n olan sayının …”, “$x sayısına …” biçiminde kurun.
- Sayı ile birim arasında boşluk bırakılır (`12 m/s`). Yüzde işareti sayıdan önce yazılır (`%25`).
- Fizikte gerekiyorsa kök `g = 10 m/s²` alınacağını söyler. π sembol olarak bırakılır ya da kök “π = 3 alınız” der.
- Negatif sayılar ifadede parantez içinde gösterilir: `3 − (−2)`.
- Aynı kök iki kez üretilmez; denetim bunu alan genelinde sınar.

## Yasaklar

- `Random`, saat ya da dış kaynak kullanılmaz; üretim yalnız sıra numarasına bağlıdır.
- Görsel, etkinlik, çoklu seçim ya da açık uçlu görev eklenmez.
- Gerçek kişi adları yerine yaygın ön adlar ya da roller kullanılır. Olgusal içerikte yalnız kesin bilinen, ders kitaplarında yer alan bilgiler kullanılır; emin olunmayan bilgi listeye alınmaz.
- Hiçbir sıra numarası hata fırlatmamalıdır.
