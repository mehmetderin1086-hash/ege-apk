# Kur’an Öğreniyorum · Elif Bâ

Entry points: Kur’an library card, Kur’an section selector, and Keşfet → Kur’an Öğreniyorum.

Implemented:
- 28 letters with Arabic names, distinguishing hints, positional forms, joining exceptions, vowel comparison, search and favorites.
- 12 original introductory lessons and 36 corrective checkpoints: letters, joining, three vowels, sukun, shadda, lengthening, tanwin, lam-alif/hamza, sun/moon letters, and introductory stopping signs.
- Letter recognition and listening quizzes: 10 non-repeating targets per session, 4 distinct choices, exactly one correct answer. One recorded answer per question.
- Persistent completion, favorites, daily answer count, and letter review intervals (1, 3, 7, 14, 30 days; mistakes reset to 10 minutes). Existing app preferences are untouched.
- Freehand tracing with undo/clear. No automatic handwriting or pronunciation grading is claimed.
- 28 locally bundled Azure Hamed Neural letter-name recordings with generation manifest. Other narration uses the existing studio gateway and its disk cache. AI examples are explicitly labeled; they are not a reciter's recording or a certification of pronunciation.
- Large regular Amiri lettering; RTL alphabet layout; scrollable cards and adaptable grid.

References:
- https://kuran.diyanet.gov.tr/elifba/
- https://egitimhizmetleri.diyanet.gov.tr/Documents/ElifBa%20Kuran%20%C3%96%C4%9Freniyorum.pdf

Content and audio should receive a qualified Quran teacher's review before being presented as a complete tajwid course. The current module is an introductory learning and practice feature.

Source: `Sekine/Features/LearnQuran/ElifBaView.swift`.
Audio generation: `deployment/studio/generate_elifba.py`; provenance: `Sekine/Resources/ElifBaAudio/sources.json`.
The folder resource is registered both in the current pbxproj and project.yml.

## Benzer harfler ve yanlışları tekrar çalışma

Elif Bâ → Alıştırma → Benzer harfleri ayırt et. Dokuz görsel aile vardır: Be/Te/Se, Cim/Hâ/Hı, Dal/Zel, Ra/Ze, Sin/Şın, Sad/Dad, Tı/Zı, Ayn/Gayn, Fe/Kaf. Büyük yan yana harfler, mevcut nokta/şekil açıklamaları ve paketli harf adı sesleri kullanılır. Grup testi yalnız grubun harflerini seçenek yapar; iki veya üç soruluk çalışmadır. Dinleme modu da aynı gruptan sorar.

Tüm harf testlerinin sonunda yanlış cevaplanan hedefler gösterilir; “Yanlış yaptıklarımı çalış” yalnız bu hedefleri yeni turda sorar. İlk turun seçenekleri korunur; tekrar sorusunun cevap seçenekleri daraltılıp cevap ele verilmez. Her cevap mevcut ilerleme/tekrar kaydına işlenir. Otomatik telaffuz değerlendirmesi yapılmaz.

## Hareke atölyesi

Elif Bâ → Alıştırma → Harekeleri ayırt et. Harf seçiciyle 28 harf üzerinde üstün/esre/ötre karşılaştırılır; elif örneğinde hemzeli elif kullanılır. Mevcut stüdyo ses servisiyle kısa örnekler dinlenebilir; sesler yapay zekâ örneğidir.

Dokuz soruluk test her harekeden üç soru üretir. Cevaptan sonra işaretin yeri/şekli açıklanır. Sonuçta yanlış sorular yeni turda çalışılır. İstatistikler `elifba.vowels.v1` içinde hareke bazında doğru/toplam olarak saklanır; harf ustalığı ve mevcut ders ilerlemesi değiştirilmez. Yeni soruda görünüm başa döner. Test telaffuz puanlaması yapmaz.

## Harekeli biçim seçimi ve birleşik şekiller

Hareke atölyesindeki “İstenen harekeli harfi bul” modu harf adı ve istenen harekeyi gösterir; kullanıcı aynı harfin üstün/esre/ötreli biçimleri arasından seçer. Aynı dengeli soru ve yanlışları tekrar mekanizmasını kullanır.

Alıştırma → Birleşik şekilleri tanı: 28 harfin tek/baş/orta/son görünümleri, sonraki harfe bağlanmayan altı harfin açıklaması ve 10 soruluk şekil tanıma testi. Sorudaki şekil konumu soru modelinde saklanır; yanlış soruyu tekrar çalışırken konumu değişmez. Çizgiler bağlantı öğretimi içindir; kelime örneği olarak sunulmaz.

## Okumaya geçiş, genel değerlendirme ve Gelişim

Atölye mevcut ders içeriğindeki cezim, şedde, med ve tenvin açıklamalarını karşılaştırmalı kartlarda gösterir. Her konu 3 soru; karma çalışma 12 soru; genel değerlendirme 12 dersteki 36 kontrol sorusunun tamamıdır. Her cevap bir kez kaydedilir, açıklama verilir, sonuçta yanlış sorularla yeni tur yapılabilir.

Gelişim sekmesi ders/harf çalışması, konu bazında doğru/toplam, hareke istatistikleri ve son beş tamamlanmış değerlendirmeyi gösterir. Son 20 değerlendirme ve konu skorları `elifba.assessment.v1` içinde kalıcıdır. Doğruluk oranı %80'in altındaki çalışılmış konular, düşük orandan başlayarak tekrar önerilir; hiç çalışılmamış konu başarısız sayılmaz. Öneri ilgili derse açılır. Bunlar mahreç/tecvid yeterliliği puanı değildir. Eski ders/harf kayıtları değiştirilmez.

Testler: dengeli 9 hareke sorusu, ayrı kalıcı hareke ilerlemesi, birleşik şekil hedefleri, 36 benzersiz değerlendirme sorusu ve cevap sınırları, öneri eşiği/kalıcılık/20 oturum sınırı. Arayüz testleri: hareke testi 8/9 → yalnız yanlışla tekrar; istenen harekeli harfi seç; birleşik şekli tanı; cezim 2/3 → Gelişim ekranı.
