import '../common.dart';

typedef _Pair = (String, String);

const _perm3 = [
  [1, 2, 0],
  [2, 0, 1],
  [1, 0, 2],
  [0, 2, 1],
  [2, 1, 0],
];

const _perm4 = [
  [1, 3, 0, 2],
  [2, 0, 3, 1],
  [3, 2, 1, 0],
  [1, 0, 3, 2],
  [2, 3, 0, 1],
  [3, 0, 2, 1],
];

List<T> _pickCombo4<T>(List<T> items, int index) {
  final n = items.length;
  final out = <T>[];
  var cursor = (index * 5) % n;
  final stride = 1 + (index ~/ n) % (n - 1);
  while (out.length < 4) {
    final cand = items[cursor];
    if (!out.contains(cand)) out.add(cand);
    cursor = (cursor + stride) % n;
    if (cursor == (index * 5) % n) cursor = (cursor + 1) % n;
  }
  return out;
}

AdvancedItem _makeMatchItem(List<_Pair> pairs, int i, String title, String prompt) {
  final p = pairs.length == 4 ? _perm4[i % _perm4.length] : _perm3[i % _perm3.length];
  final left = [for (final e in pairs) e.$1];
  final right = [for (final idx in p) pairs[idx].$2];
  final solution = [for (var j = 0; j < pairs.length; j++) p.indexOf(j)];
  String seq(List<int> v) => v.map((n) => '${n + 1}').join(' – ');
  final wrongPerms = (pairs.length == 4 ? _perm4 : _perm3)
      .where((z) => seq(z) != seq(solution))
      .take(3)
      .map(seq)
      .toList();
  return AdvancedItem(
    prompt,
    seq(solution),
    wrongPerms,
    [for (final e in pairs) '${e.$1} → ${e.$2}'].join(' · '),
    activity: QuestionActivity(
      kind: ActivityKind.matching,
      title: title,
      left: left,
      right: right,
      solution: solution,
    ),
  );
}

// ---------------------------------------------------------------------------
// 1. ÇİFT EŞLEŞTİRME ATÖLYESİ — DÜNYA, BİLİM, EDEBİYAT & TARİH (400 soru)
// ---------------------------------------------------------------------------
const _matchDomains = <(String, String, List<_Pair>)>[
  (
    'Ülke – Başkent Eşleştirme',
    'Sol sütundaki ülkeleri sağ sütundaki başkentleriyle eşleştirin.',
    [
      ('Japonya', 'Tokyo'), ('İspanya', 'Madrid'), ('Kanada', 'Ottawa'),
      ('Avustralya', 'Kanberra'), ('Brezilya', 'Brasília'), ('Mısır', 'Kahire'),
      ('Norveç', 'Oslo'), ('Portekiz', 'Lizbon'), ('İsviçre', 'Bern'),
      ('Güney Kore', 'Seul'), ('Arjantin', 'Buenos Aires'), ('Fas', 'Rabat'),
      ('Kazakistan', 'Astana'), ('Çekya', 'Prag'), ('Avusturya', 'Viyana'),
      ('İsveç', 'Stockholm'), ('Finlandiya', 'Helsinki'), ('Yunanistan', 'Atina'),
    ],
  ),
  (
    'Element – Sembol Eşleştirme',
    'Kimyasal elementleri doğru periyodik tablo sembolleriyle eşleştirin.',
    [
      ('Altın', 'Au'), ('Gümüş', 'Ag'), ('Demir', 'Fe'), ('Bakır', 'Cu'),
      ('Sodyum', 'Na'), ('Potasyum', 'K'), ('Cıva', 'Hg'), ('Kurşun', 'Pb'),
      ('Kalay', 'Sn'), ('Tungsten', 'W'), ('Fosfor', 'P'), ('Kükürt', 'S'),
      ('Kalsiyum', 'Ca'), ('Magnezyum', 'Mg'), ('Klor', 'Cl'), ('Azot', 'N'),
    ],
  ),
  (
    'Bilim İnsanı – Keşif Eşleştirme',
    'Bilim insanlarını tarihe geçen buluş veya kuramlarıyla eşleştirin.',
    [
      ('Isaac Newton', 'Evrensel Kütleçekim Yasası'),
      ('Marie Curie', 'Polonyum ve Radyum'),
      ('Alexander Fleming', 'Penisilin'),
      ('Charles Darwin', 'Doğal Seçilim Kuramı'),
      ('Nikola Tesla', 'Alternatif Akım Motoru'),
      ('Galileo Galilei', 'Jüpiter’in Dört Büyük Uydusu'),
      ('Louis Pasteur', 'Pastörizasyon ve Kuduz Aşısı'),
      ('Dmitri Mendeleyev', 'Periyodik Tablo Düzeni'),
      ('Johannes Kepler', 'Gezegen Hareket Yasaları'),
      ('Gregor Mendel', 'Kalıtım Yasaları'),
      ('Alan Turing', 'Evrensel Hesaplama Modeli'),
      ('Aziz Sancar', 'DNA Onarım Mekanizmaları'),
    ],
  ),
  (
    'Yazar – Başyapıt Eşleştirme',
    'Türk ve dünya edebiyatı yazarlarını eserleriyle eşleştirin.',
    [
      ('Yaşar Kemal', 'İnce Memed'),
      ('Sabahattin Ali', 'Kürk Mantolu Madonna'),
      ('Oğuz Atay', 'Tutunamayanlar'),
      ('Ahmet Hamdi Tanpınar', 'Saatleri Ayarlama Enstitüsü'),
      ('Reşat Nuri Güntekin', 'Çalıkuşu'),
      ('Halit Ziya Uşaklıgil', 'Aşk-ı Memnu'),
      ('Orhan Pamuk', 'Benim Adım Kırmızı'),
      ('Dostoyevski', 'Suç ve Ceza'),
      ('Victor Hugo', 'Sefiller'),
      ('Cervantes', 'Don Kişot'),
      ('George Orwell', '1984'),
      ('Gabriel García Márquez', 'Yüzyıllık Yalnızlık'),
    ],
  ),
  (
    'Hücre Organeli – Görev Eşleştirme',
    'Hücre organellerini temel biyolojik görevleriyle eşleştirin.',
    [
      ('Mitokondri', 'ATP enerji üretimi'),
      ('Ribozom', 'Protein sentezi'),
      ('Kloroplast', 'Fotosentez yapımı'),
      ('Golgi Aygıtı', 'Salgı paketleme ve taşıma'),
      ('Lizozom', 'Hücre içi sindirim'),
      ('Çekirdek', 'Genetik bilgiyi yönetme'),
      ('Koful', 'Su ve madde depolama'),
      ('Sentrozom', 'Hücre bölünmesinde iğ ipliği'),
      ('Peroksizom', 'Zehirli peroksiti parçalama'),
      ('Hücre Zarı', 'Seçici geçirgen madde alışverişi'),
    ],
  ),
];

AdvancedItem _buildMatchWorld(int i) {
  final domain = _matchDomains[i % _matchDomains.length];
  final k = i ~/ _matchDomains.length;
  final pairs = _pickCombo4(domain.$3, k);
  return _makeMatchItem(pairs, i, domain.$1, domain.$2);
}

// ---------------------------------------------------------------------------
// 2. İNGİLİZCE DEYİM & FİİL EŞLEŞTİRME (350 soru)
// ---------------------------------------------------------------------------
const _enMatchPairs = <_Pair>[
  ('give up', 'vazgeçmek'), ('put off', 'ertelemek'), ('find out', 'keşfetmek / öğrenmek'),
  ('look after', 'ilgilenmek / bakmak'), ('carry out', 'uygulamak / yürütmek'), ('turn down', 'geri çevirmek'),
  ('run out of', 'tüketip bitirmek'), ('come across', 'tesadüfen rastlamak'), ('get over', 'atlatmak / iyileşmek'),
  ('bring up', 'gündeme getirmek'), ('figure out', 'çözümünü bulmak'), ('call off', 'iptal etmek'),
  ('set off', 'yola çıkmak'), ('hand in', 'teslim etmek'), ('cut down on', 'miktarını azaltmak'),
  ('break the ice', 'ortamdaki çekingenliği kırmak'), ('once in a blue moon', 'çok nadir'),
  ('piece of cake', 'çok kolay iş'), ('hit the sack', 'yatıp uyumak'),
  ('under the weather', 'halsiz / keyifsiz'), ('spill the beans', 'sırrı ağzından kaçırmak'),
  ('call it a day', 'bugünlük çalışmayı bitirmek'), ('keep an eye on', 'göz kulak olmak'),
  ('back to square one', 'en başa dönmek'), ('on the same page', 'aynı fikirde olmak'),
  ('reliable', 'güvenilir'), ('abundant', 'bol / bereketli'), ('scarce', 'kıt / az bulunur'),
  ('inevitable', 'kaçınılmaz'), ('fragile', 'kırılgan'), ('feasible', 'uygulanabilir'),
  ('reluctant', 'isteksiz'), ('accurate', 'tam doğru / isabetli'), ('versatile', 'çok yönlü'),
  ('crucial', 'hayati önemde'), ('resilient', 'dayanıklı'), ('coherent', 'tutarlı'),
  ('substantial', 'önemli ölçüde'), ('ambiguous', 'belirsiz'), ('meticulous', 'titiz'),
];

AdvancedItem _buildMatchEnglish(int i) {
  final pairs = _pickCombo4(_enMatchPairs, i);
  return _makeMatchItem(
    pairs,
    i,
    'İngilizce – Türkçe Eşleştirme',
    'Sol sütundaki İngilizce ifadeleri sağ sütundaki Türkçe karşılıklarıyla eşleştirin.',
  );
}

// ---------------------------------------------------------------------------
// 3. KRONOLOJİK & BİLİMSEL SIRALAMA ATÖLYESİ (450 soru)
// ---------------------------------------------------------------------------

const _historyTimeline = <(String, int, String)>[
  ('Malazgirt Meydan Muharebesi', 1071, '1071'),
  ('İstanbul’un Fethi', 1453, '1453'),
  ('Matbaanın Avrupa’da icadı (Gutenberg)', 1450, '1450'),
  ('Amerika Kıtası’na Kolomb’un ulaşması', 1492, '1492'),
  ('Fransız İhtilali', 1789, '1789'),
  ('Tanzimat Fermanı’nın ilanı', 1839, '1839'),
  ('I. Meşrutiyet’in ilanı', 1876, '1876'),
  ('TBMM’nin açılışı', 1920, '1920'),
  ('Cumhuriyet’in ilanı', 1923, '1923'),
  ('Harf İnkılabı', 1928, '1928'),
  ('Kadınlara milletvekili seçme ve seçilme hakkı', 1934, '1934'),
  ('Birleşmiş Milletler’in kuruluşu', 1945, '1945'),
  ('İlk yapay uydu Sputnik 1’in fırlatılışı', 1957, '1957'),
  ('Ay’a ilk insanlı iniş (Apollo 11)', 1969, '1969'),
  ('World Wide Web’in kamuya açılması', 1991, '1991'),
];

const _planetsOrder = <(String, int, String)>[
  ('Merkür', 1, '1. gezegen'),
  ('Venüs', 2, '2. gezegen'),
  ('Dünya', 3, '3. gezegen'),
  ('Mars', 4, '4. gezegen'),
  ('Jüpiter', 5, '5. gezegen'),
  ('Satürn', 6, '6. gezegen'),
  ('Uranüs', 7, '7. gezegen'),
  ('Neptün', 8, '8. gezegen'),
];

const _geoSizes = <(String, int, String)>[
  ('Avustralya (Okyanusya)', 1, '8,5 milyon km²'),
  ('Avrupa', 2, '10,5 milyon km²'),
  ('Antarktika', 3, '14,2 milyon km²'),
  ('Güney Amerika', 4, '17,8 milyon km²'),
  ('Kuzey Amerika', 5, '24,7 milyon km²'),
  ('Afrika', 6, '30,3 milyon km²'),
  ('Asya', 7, '44,6 milyon km²'),
];

const _fixedSequences = <(String, String, List<String>, String)>[
  (
    'Mitoz Bölünme Evreleri',
    'Mitoz hücre bölünmesinin evrelerini baştan sona doğru sıraya dizin.',
    ['Profaz', 'Metafaz', 'Anafaz', 'Telofaz'],
    'Mitoz evreleri sırasıyla Profaz → Metafaz → Anafaz → Telofaz şeklinde gerçekleşir.',
  ),
  (
    'Canlı Sınıflandırma Basamakları',
    'Taksonomi basamaklarını en KAPSAYICIDAN en ÖZELE doğru sıralayın.',
    ['Âlem', 'Şube', 'Sınıf', 'Tür'],
    'Kapsayıcıdan özele: Âlem → Şube → Sınıf → Takım → Aile → Cins → Tür.',
  ),
  (
    'Su Döngüsü Aşamaları',
    'Doğadaki su döngüsünün temel aşamalarını mantıksal sıraya dizin.',
    ['Buharlaşma', 'Yoğuşma (Bulut)', 'Yağış', 'Yüzey Akışı'],
    'Su buharlaşır, yüksekte yoğuşup bulut oluşturur, yağışla yere iner ve akışla sulara döner.',
  ),
  (
    'Bilimsel Yöntem Adımları',
    'Bilimsel araştırma sürecinin adımlarını doğru sıraya yerleştirin.',
    ['Gözlem ve Soru', 'Hipotez Kurma', 'Kontrollü Deney', 'Sonuç ve Paylaşım'],
    'Bilimsel yöntem gözlemle başlar, hipotez kurulur, deneyle sınanır ve sonuçlar paylaşılır.',
  ),
  (
    'Elektromanyetik Spektrum',
    'Dalgaları en DÜŞÜK enerjiden (en uzun dalga boyu) en YÜKSEK enerjiye sıralayın.',
    ['Radyo Dalgaları', 'Kızılötesi', 'Görünür Işık', 'X-Işınları'],
    'Enerji arttıkça dalga boyu kısalır: Radyo → Kızılötesi → Görünür Işık → Morötesi → X-Işınları → Gama.',
  ),
  (
    'Veri Birimleri Büyüklüğü',
    'Dijital depolama birimlerini en KÜÇÜKTEN en BÜYÜĞE doğru sıralayın.',
    ['Kilobayt (KB)', 'Megabayt (MB)', 'Gigabayt (GB)', 'Terabayt (TB)'],
    'Her basamakta kapasite yaklaşık 1024 kat artar: KB → MB → GB → TB.',
  ),
  (
    'Atmosfer Katmanları',
    'Atmosfer katmanlarını YERYÜZÜNDEN UZAYA doğru sıraya dizin.',
    ['Troposfer', 'Stratosfer', 'Mezosfer', 'Termosfer'],
    'Yerden yukarıya doğru katmanlar: Troposfer → Stratosfer → Mezosfer → Termosfer → Ekzosfer.',
  ),
  (
    'Sindirim Kanalı Yolculuğu',
    'Besinin sindirim sisteminde izlediği yolu baştan sona sıralayın.',
    ['Ağız', 'Yemek Borusu', 'Mide', 'İnce Bağırsak'],
    'Besinler sırasıyla Ağız → Yutak → Yemek Borusu → Mide → İnce Bağırsak → Kalın Bağırsak yolunu izler.',
  ),
];

AdvancedItem _makeOrderItem(List<String> correctOrder, int i, String title, String prompt, String explain) {
  final p = _perm4[i % _perm4.length];
  // displayed[j] = correctOrder[p[j]]
  final displayed = [for (final origIdx in p) correctOrder[origIdx]];
  // solution[k] = index in displayed of correctOrder[k]
  final solution = [for (var k = 0; k < 4; k++) p.indexOf(k)];
  String seq(List<int> v) => v.map((n) => '${n + 1}').join(' → ');
  final wrong = _perm4.where((z) => seq(z) != seq(solution)).take(3).map(seq).toList();
  return AdvancedItem(
    prompt,
    seq(solution),
    wrong,
    explain,
    activity: QuestionActivity(
      kind: ActivityKind.ordering,
      title: title,
      items: displayed,
      solution: solution,
    ),
  );
}

AdvancedItem _buildOrderHistSci(int i) {
  final bucket = i % 4;
  final k = i ~/ 4;
  if (bucket == 0) {
    final picked = _pickCombo4(_historyTimeline, k)..sort((a, b) => a.$2.compareTo(b.$2));
    return _makeOrderItem(
      [for (final e in picked) e.$1],
      i,
      'Tarih Kronolojisi',
      'Tarihsel olayları EN ESKİDEN EN YENİYE doğru kronolojik sıraya dizin.',
      [for (final e in picked) '${e.$1} (${e.$3})'].join(' → '),
    );
  } else if (bucket == 1) {
    final picked = _pickCombo4(_planetsOrder, k)..sort((a, b) => a.$2.compareTo(b.$2));
    return _makeOrderItem(
      [for (final e in picked) e.$1],
      i,
      'Gezegen Sıralaması',
      'Gezegenleri Güneş’e EN YAKINDAN EN UZAĞA doğru sıralayın.',
      [for (final e in picked) '${e.$1} (${e.$3})'].join(' → '),
    );
  } else if (bucket == 2) {
    final picked = _pickCombo4(_geoSizes, k)..sort((a, b) => a.$2.compareTo(b.$2));
    return _makeOrderItem(
      [for (final e in picked) e.$1],
      i,
      'Kıta Yüzölçümü Sıralaması',
      'Kıtaları yüzölçümü EN KÜÇÜKTEN EN BÜYÜĞE doğru sıralayın.',
      [for (final e in picked) '${e.$1} (${e.$3})'].join(' → '),
    );
  } else {
    final seq = _fixedSequences[k % _fixedSequences.length];
    return _makeOrderItem(seq.$3, i + k, seq.$1, seq.$2, seq.$4);
  }
}

// ---------------------------------------------------------------------------
// 4. İNGİLİZCE CÜMLE KURMA / WORD ORDER SIRALAMA (300 soru)
// ---------------------------------------------------------------------------
const _enOrderSentences = <(List<String>, String)>[
  (['She has been', 'studying architecture', 'in Istanbul', 'for three years.'], 'Üç yıldır İstanbul’da mimarlık okuyor.'),
  (['If it rains', 'tomorrow morning,', 'we will visit', 'the science museum.'], 'Yarın sabah yağmur yağarsa bilim müzesini gezeceğiz.'),
  (['The express train', 'to Edinburgh', 'departs from', 'Platform Six.'], 'Edinburgh ekspres treni 6. perondan kalkar.'),
  (['Although the hike', 'was quite steep,', 'the mountain view', 'was unforgettable.'], 'Yürüyüş oldukça dik olmasına rağmen dağ manzarası unutulmazdı.'),
  (['Could you please', 'tell me where', 'the nearest subway', 'station is?'], 'En yakın metro istasyonunun nerede olduğunu söyleyebilir misiniz?'),
  (['Scientists recently', 'discovered a new', 'deep-sea coral', 'species near Chile.'], 'Bilim insanları yakın zamanda Şili yakınlarında yeni bir derin deniz mercanı keşfetti.'),
  (['Before boarding', 'the international flight,', 'passengers must show', 'their passports.'], 'Uluslararası uçuşa binmeden önce yolcular pasaportlarını göstermelidir.'),
  (['Neither of the', 'two proposals', 'was accepted', 'by the committee.'], 'İki tekliften hiçbiri komite tarafından kabul edilmedi.'),
  (['By the time', 'we arrived at', 'the concert hall,', 'the orchestra had begun.'], 'Konser salonuna vardığımızda orkestra başlamıştı.'),
  (['Learning a new', 'foreign language', 'requires patience', 'and daily listening.'], 'Yeni bir yabancı dil öğrenmek sabır ve günlük dinleme gerektirir.'),
  (['Not only did', 'she finish first,', 'but she also', 'broke the record.'], 'Yalnızca birinci bitirmekle kalmadı, rekoru da kırdı.'),
  (['The solar panels', 'installed last spring', 'now power', 'the entire school.'], 'Geçen baharda kurulan güneş panelleri artık tüm okula elektrik sağlıyor.'),
  (['Had we known', 'about the traffic,', 'we would have', 'taken the ferry.'], 'Trafiği bilseydik vapura binerdik.'),
  (['Most visitors', 'prefer exploring', 'the historic bazaar', 'early in the morning.'], 'Çoğu ziyaretçi tarihi çarşıyı sabah erken gezmeyi tercih eder.'),
  (['While the chef', 'was preparing soup,', 'the waiter set', 'the terrace tables.'], 'Şef çorbayı hazırlarken garson teras masalarını kurdu.'),
  (['Unless you save', 'the document now,', 'your recent edits', 'may be lost.'], 'Belgeyi şimdi kaydetmezsen son düzenlemelerin kaybolabilir.'),
  (['Regular exercise', 'combined with sleep', 'sharply improves', 'concentration at work.'], 'Uykuyla birleşen düzenli egzersiz işte odaklanmayı belirgin biçimde artırır.'),
  (['The documentary', 'that we watched', 'last Friday won', 'two international awards.'], 'Geçen Cuma izlediğimiz belgesel iki uluslararası ödül kazandı.'),
  (['Despite the heavy', 'winter snowstorm,', 'all flights arrived', 'safely on schedule.'], 'Şiddetli kış fırtınasına rağmen tüm uçuşlar güvenle zamanında indi.'),
  (['I have never', 'tasted such delicious', 'homemade lemonade', 'in my life.'], 'Hayatımda hiç bu kadar lezzetli ev yapımı limonata tatmadım.'),
  (['Please remember', 'to turn off', 'the studio lights', 'before leaving tonight.'], 'Bu akşam çıkmadan önce stüdyo ışıklarını kapatmayı lütfen unutma.'),
  (['The library will', 'remain open until', 'midnight during', 'final exam week.'], 'Final sınav haftasında kütüphane gece yarısına kadar açık kalacak.'),
  (['As soon as', 'the bridge opens,', 'commute times will', 'drop by half.'], 'Köprü açılır açılmaz yolculuk süreleri yarıya düşecek.'),
  (['My colleague suggested', 'comparing both charts', 'before writing', 'the final report.'], 'Meslektaşım nihai raporu yazmadan önce iki grafiği karşılaştırmayı önerdi.'),
  (['Every Saturday morning,', 'local farmers bring', 'fresh figs and olives', 'to the square.'], 'Her Cumartesi sabahı yerel çiftçiler meydana taze incir ve zeytin getirir.'),
];

AdvancedItem _buildOrderEnglish(int i) {
  final s = _enOrderSentences[i % _enOrderSentences.length];
  final permShift = i ~/ _enOrderSentences.length;
  return _makeOrderItem(
    s.$1,
    i + permShift,
    'İngilizce Cümle Kurma (Word Order)',
    'İngilizce parçaları doğru dilbilgisi sırasına dizin.\n(Türkçe anlamı: “${s.$2}”)',
    'Doğru İngilizce cümle: "${s.$1.join(" ")}" (${s.$2})',
  );
}

// ---------------------------------------------------------------------------
// 5. ÇOKLU DOĞRU SEÇİM — HEPSİNİ BUL (500 soru)
// ---------------------------------------------------------------------------
typedef _MultiGroup = ({
  String prompt,
  List<String> trues,
  List<String> falses,
  String explain,
});

const _multiGroups = <_MultiGroup>[
  (
    prompt: 'Aşağıdaki önermelerden hangileri MEMELİ canlılar için doğrudur?',
    trues: [
      'Yavrularını sütle beslerler.',
      'Sıcakkanlı (sabit vücut sıcaklıklı) omurgalılardır.',
      'Akciğer solunumu yaparlar.',
      'Yunus ve balina denizde yaşayan memelilerdir.',
      'Yarasa uçabilen tek memeli grubudur.',
    ],
    falses: [
      'Tamamı solungaç solunumu yapar.',
      'Vücut sıcaklıkları dış ortama göre sürekli değişir.',
      'Bütün türleri yalnızca yumurtlayarak ürer.',
      'Hepsi karada yaşar, suda yaşayan türü yoktur.',
    ],
    explain: 'Memeliler sıcakkanlıdır, akciğer solunumu yapar ve yavrularını sütle besler; yunus, balina ve yarasa da memelidir.',
  ),
  (
    prompt: 'Hangi İngilizce sözcükler “artmak / yükselmek” (increase) anlamını taşır?',
    trues: ['rise', 'grow', 'surge', 'expand', 'escalate'],
    falses: ['decline', 'shrink', 'plummet', 'diminish'],
    explain: 'Rise, grow, surge, expand ve escalate artış bildirir; decline, shrink, plummet ve diminish azalış bildirir.',
  ),
  (
    prompt: 'Aşağıdaki maddelerden hangileri kimyasal BİLEŞİK örneğidir?',
    trues: ['Su (H₂O)', 'Sofra tuzu (NaCl)', 'Karbondioksit (CO₂)', 'Amonyak (NH₃)', 'Glikoz (C₆H₁₂O₆)'],
    falses: ['Saf altın (Au)', 'Oksijen gazı (O₂)', 'Bakır tel (Cu)', 'Hava karışımı'],
    explain: 'Bileşikler farklı element atomlarının belirli oranlarda kimyasal bağla birleşmesiyle oluşur (H₂O, NaCl, CO₂, NH₃, glikoz).',
  ),
  (
    prompt: 'Aşağıdaki gezegenlerden hangileri GAZ / BUZ DEVİ (Dış Gezegen) grubundadır?',
    trues: ['Jüpiter', 'Satürn', 'Uranüs', 'Neptün'],
    falses: ['Merkür', 'Venüs', 'Dünya', 'Mars'],
    explain: 'Jüpiter, Satürn, Uranüs ve Neptün dış dev gezegenlerdir; Merkür, Venüs, Dünya ve Mars karasal iç gezegenlerdir.',
  ),
  (
    prompt: 'Aşağıdaki şehirlerden hangileri bir ülkenin BAŞKENTİDİR?',
    trues: ['Kanberra', 'Ottawa', 'Bern', 'Brasília', 'Rabat', 'Astana'],
    falses: ['Sidney', 'Toronto', 'Zürih', 'Rio de Janeiro', 'New York'],
    explain: 'Avustralya’nın başkenti Kanberra, Kanada’nın Ottawa, İsviçre’nin Bern, Brezilya’nın Brasília, Fas’ın Rabat ve Kazakistan’ın Astana’dır.',
  ),
  (
    prompt: 'Aşağıdakilerden hangileri YENİLENEBİLİR enerji kaynağıdır?',
    trues: ['Güneş enerjisi', 'Rüzgâr enerjisi', 'Jeotermal enerji', 'Hidroelektrik enerji', 'Dalga enerjisi'],
    falses: ['Taş kömürü', 'Ham petrol', 'Doğal gaz', 'Linyit'],
    explain: 'Güneş, rüzgâr, jeotermal, hidroelektrik ve dalga enerjisi yenilenebilirken kömür, petrol ve doğal gaz fosil yakıtlardır.',
  ),
  (
    prompt: 'Aşağıdaki sayılardan hangileri ASAL SAYIDIR?',
    trues: ['17', '29', '37', '53', '71', '83'],
    falses: ['21', '39', '51', '57', '91'],
    explain: 'Yalnızca 1’e ve kendisine bölünebilen sayılar asaldır (21=3×7, 39=3×13, 51=3×17, 57=3×19, 91=7×13).',
  ),
  (
    prompt: 'Hangi İngilizce ifadeler “kibar rica / izin isteme” amacıyla doğru kullanılır?',
    trues: [
      'Could you please open the window?',
      'Would you mind helping me with this?',
      'May I borrow your pen for a moment?',
      'Could I ask a quick question?',
    ],
    falses: [
      'Give me that pen right now!',
      'She don’t want to help.',
      'You must to open it immediately.',
      'He have went to the office.',
    ],
    explain: 'Could you please, Would you mind + V-ing ve May I kalıpları İngilizcede kibar rica ve izin ifadeleridir.',
  ),
  (
    prompt: 'Aşağıdakilerden hangileri TÜRKİYE’NİN KARADENİZ’E KIYISI OLAN illerindendir?',
    trues: ['Trabzon', 'Samsun', 'Sinop', 'Rize', 'Bartın', 'Ordu'],
    falses: ['Antalya', 'Muğla', 'İzmir', 'Konya', 'Mersin'],
    explain: 'Trabzon, Samsun, Sinop, Rize, Bartın ve Ordu Karadeniz kıyısında yer alır.',
  ),
  (
    prompt: 'Aşağıdaki veri yapılarından hangileri DOĞRUSAL (Linear) veri yapısıdır?',
    trues: ['Dizi (Array)', 'Bağlı Liste (Linked List)', 'Yığın (Stack)', 'Kuyruk (Queue)'],
    falses: ['İkili Ağaç (Binary Tree)', 'Çizge (Graph)', 'Yığın Ağacı (Binary Heap)'],
    explain: 'Dizi, Bağlı Liste, Yığın ve Kuyruk doğrusal; Ağaç ve Çizge doğrusal olmayan veri yapılarıdır.',
  ),
];

MultiSelectTask _buildMultiSelectTask(AdvancedItem _, int i) {
  final g = _multiGroups[i % _multiGroups.length];
  final k = i ~/ _multiGroups.length;
  final trueCount = k.isEven ? 2 : 3;
  final pickedT = <String>[];
  for (var j = 0; j < trueCount; j++) {
    pickedT.add(g.trues[(k + j) % g.trues.length]);
  }
  final pickedF = <String>[];
  for (var j = 0; j < 4 - trueCount; j++) {
    pickedF.add(g.falses[(k + j) % g.falses.length]);
  }
  final combined = [...pickedT, ...pickedF];
  final perm = _perm4[(i + k) % _perm4.length];
  final opts = [for (final idx in perm) combined[idx]];
  final correctIdx = [
    for (var pos = 0; pos < 4; pos++)
      if (perm[pos] < trueCount) pos,
  ]..sort();
  return MultiSelectTask(g.prompt, opts, correctIdx, g.explain);
}

AdvancedItem _buildMultiBase(int i) {
  final g = _multiGroups[i % _multiGroups.length];
  return AdvancedItem(g.prompt, g.trues.first, g.falses.take(3).toList(), g.explain);
}

// ---------------------------------------------------------------------------
// 6. HIZLI DOĞRU / YANLIŞ YARGI ARENASI (500 soru)
// ---------------------------------------------------------------------------
typedef _TfFact = ({String statement, bool isTrue, String explain});

const _tfBank = <_TfFact>[
  // Bilim & Doğa
  (statement: 'Venüs, Güneş Sistemi’nde diğer gezegenlerin çoğunun aksine doğudan batıya doğru döner.', isTrue: true, explain: 'Venüs ters yönlü (retrograd) dönüşe sahiptir; bu yüzden Venüs’te Güneş batıdan doğar.'),
  (statement: 'Ses dalgaları uzay boşluğunda ışıktan daha hızlı yayılır.', isTrue: false, explain: 'Ses mekanik bir dalgadır; maddesel ortam olmadan uzay boşluğunda hiç yayılmaz.'),
  (statement: 'İnsan vücudundaki en büyük iç organ karaciğerdir.', isTrue: true, explain: 'Deri en büyük organ, karaciğer ise en büyük iç organdır.'),
  (statement: 'Saf su deniz seviyesinde 100 °C sıcaklıkta kaynar.', isTrue: true, explain: '1 atmosfer (deniz seviyesi) basıncında saf su 100 °C’de kaynar.'),
  (statement: 'Altının kimyasal sembolü Ag’dir.', isTrue: false, explain: 'Ag gümüşün (Argentum) sembolüdür; altının (Aurum) sembolü Au’dur.'),
  (statement: 'Bitkiler fotosentez sırasında karbondioksit kullanıp oksijen üretir.', isTrue: true, explain: 'Klorofil ışık enerjisiyle CO₂ ve H₂O’yu glikoz ve O₂’ye dönüştürür.'),
  (statement: 'Yarasalar kör canlılardır ve hiç göremezler.', isTrue: false, explain: 'Yarasalar ekolokasyon kullansa da gözleri işlevseldir ve görerek yön bulabilirler.'),
  (statement: 'Ahtapotların üç kalbi ve mavi renkli kanı vardır.', isTrue: true, explain: 'Ahtapotlarda iki solungaç kalbi, bir sistemik kalp ve bakır temelli hemosiyanin nedeniyle mavi kan bulunur.'),
  (statement: 'Elmas ve grafit aynı element olan karbondan oluşur.', isTrue: true, explain: 'Elmas ve grafit karbonun farklı kristal dizilimli allotroplarıdır.'),
  (statement: 'Işık yılı bir zaman ölçü birimidir.', isTrue: false, explain: 'Işık yılı ışığın boşlukta bir yılda katettiği uzaklığı belirten bir uzunluk birimidir (~9,46 trilyon km).'),
  (statement: 'Jüpiter, Güneş Sistemi’ndeki en büyük gezegendir.', isTrue: true, explain: 'Jüpiter diğer tüm gezegenlerin toplam kütlesinin iki katından daha büyüktür.'),
  (statement: 'Oksijen atmosferdeki en bol gazdır.', isTrue: false, explain: 'Atmosferin yaklaşık %78’i azot, %21’i oksijendir.'),
  (statement: 'DNA molekülü çift sarmal (double helix) yapıdadır.', isTrue: true, explain: 'DNA iki nükleotid zincirinin hidrojen bağlarıyla oluşturduğu çift sarmal yapıdadır.'),
  (statement: 'Kutup ayıları doğal olarak Antarktika’da yaşar.', isTrue: false, explain: 'Kutup ayıları Kuzey Kutbu’nda (Arktik), penguenler ise ağırlıklı olarak Güney Yarımküre’de yaşar.'),
  (statement: 'Cıva oda sıcaklığında sıvı hâlde bulunan bir metaldir.', isTrue: true, explain: 'Cıva (Hg) −38,8 °C’de eridiği için oda sıcaklığında sıvıdır.'),
  // Coğrafya & Tarih
  (statement: 'Türkiye hem Asya hem Avrupa kıtasında toprağı bulunan bir ülkedir.', isTrue: true, explain: 'Anadolu Asya’da, Trakya Avrupa’da yer alır.'),
  (statement: 'Avustralya’nın başkenti Sidney şehridir.', isTrue: false, explain: 'Avustralya’nın başkenti Sidney değil Kanberra’dır.'),
  (statement: 'Everest Dağı, Himalaya Sıradağları üzerinde bulunur.', isTrue: true, explain: '8.848 m yüksekliğindeki Everest, Nepal-Tibet sınırında Himalayalar’dadır.'),
  (statement: 'Cumhuriyet, 29 Ekim 1923 tarihinde ilan edilmiştir.', isTrue: true, explain: 'TBMM 29 Ekim 1923’te anayasa değişikliğiyle Cumhuriyet’i ilan etti.'),
  (statement: 'Nil Nehri yalnızca Mısır sınırları içinden akar.', isTrue: false, explain: 'Nil havzası Uganda, Sudan, Etiyopya ve Mısır dâhil 11 ülkeyi kapsar.'),
  (statement: 'Pasifik (Büyük) Okyanus dünyanın en geniş okyanusudur.', isTrue: true, explain: 'Pasifik Okyanusu dünya yüzeyinin yaklaşık üçte birini kaplar.'),
  (statement: 'Kanada’nın başkenti Toronto’dur.', isTrue: false, explain: 'Toronto en kalabalık şehir olsa da Kanada’nın başkenti Ottawa’dır.'),
  (statement: 'Matbaayı Osmanlı’da ilk kez İbrahim Müteferrika kurmuştur.', isTrue: true, explain: 'İlk Türk matbaası 1727’de İbrahim Müteferrika ve Sait Efendi tarafından kuruldu.'),
  (statement: 'Brezilya’nın resmi dili İspanyolcadır.', isTrue: false, explain: 'Brezilya Güney Amerika’da resmi dili Portekizce olan tek ülkedir.'),
  (statement: 'Van Gölü Türkiye’nin yüzölçümü en büyük gölüdür.', isTrue: true, explain: 'Van Gölü ~3.713 km² yüzölçümüyle Türkiye’nin en büyük gölüdür.'),
  // İngilizce Dilbilgisi Doğru/Yanlış Kontrolü
  (statement: 'İngilizce dilbilgisi: “She doesn’t like spicy food.” cümlesi doğrudur.', isTrue: true, explain: 'Üçüncü tekil şahıs (she) için geniş zaman olumsuzunda "doesn’t + yalın fiil" kullanılır.'),
  (statement: 'İngilizce dilbilgisi: “He don’t know the answer.” cümlesi doğrudur.', isTrue: false, explain: 'Doğrusu “He doesn’t know the answer.” olmalıdır.'),
  (statement: 'İngilizce dilbilgisi: “I have lived in Izmir since 2019.” cümlesi doğrudur.', isTrue: true, explain: 'Belirli başlangıç yılı için "since" ve Present Perfect kullanımı doğrudur.'),
  (statement: 'İngilizce dilbilgisi: “She has worked here since five years.” cümlesi doğrudur.', isTrue: false, explain: 'Süre uzunluğu (five years) için "since" değil "for" kullanılır: “for five years”.'),
  (statement: 'İngilizce dilbilgisi: “If I were you, I would accept the offer.” cümlesi doğrudur.', isTrue: true, explain: 'Type 2 Conditional (hayali durum) yapısında “If I were you, I would...” kullanımı doğrudur.'),
  (statement: 'İngilizce dilbilgisi: “Despite it was raining, we walked home.” cümlesi doğrudur.', isTrue: false, explain: '“Despite” ardından tam cümle değil isim/gerund gelir; tam cümle için “Although it was raining” kullanılır.'),
  (statement: 'İngilizce dilbilgisi: “There is much information in this book.” cümlesi doğrudur.', isTrue: true, explain: '“Information” sayılamayan (uncountable) bir isim olduğu için “is” ve “much” ile kullanılır.'),
  (statement: 'İngilizce dilbilgisi: “He gave me many good advices.” cümlesi doğrudur.', isTrue: false, explain: '“Advice” sayılamaz ve çoğul -s almaz; doğrusu “much good advice” veya “pieces of advice” olur.'),
  (statement: 'İngilizce dilbilgisi: “The museum was built in 1895.” edilgen (passive) cümlesi doğrudur.', isTrue: true, explain: 'Past Simple Passive yapısı “was/were + V3 (built)” şeklinde kurulur.'),
  (statement: 'İngilizce dilbilgisi: “She is more taller than her brother.” cümlesi doğrudur.', isTrue: false, explain: 'Kısa sıfatlarda çift karşılaştırma yapılmaz; doğrusu “taller than” şeklindedir.'),
  (statement: 'İngilizce dilbilgisi: “I look forward to hearing from you.” cümlesi doğrudur.', isTrue: true, explain: '“look forward to” kalıbındaki “to” edat olduğu için ardından fiil -ing (hearing) alır.'),
  (statement: 'İngilizce dilbilgisi: “We discussed about the new budget.” cümlesi doğrudur.', isTrue: false, explain: '“Discuss” fiili doğrudan nesne alır, “about” edatı kullanılmaz: “We discussed the new budget.”'),
  (statement: 'İngilizce dilbilgisi: “Neither Ali nor Zeynep was late.” cümlesi doğrudur.', isTrue: true, explain: '“Neither... nor...” yapısında iki özne de tekilse fiil tekil (was) çekimlenir.'),
  (statement: 'İngilizce dilbilgisi: “Did you went to the cinema yesterday?” cümlesi doğrudur.', isTrue: false, explain: '“Did” yardımcı fiilinden sonra ana fiil yalın (V1) gelir: “Did you go...?”'),
  (statement: 'İngilizce dilbilgisi: “She speaks English fluently.” cümlesi doğrudur.', isTrue: true, explain: 'Fiili niteleyen durum belirteci olarak sıfat (fluent) değil zarf (fluently) kullanılır.'),
  (statement: 'İngilizce dilbilgisi: “Every students in the class passed.” cümlesi doğrudur.', isTrue: false, explain: '“Every” her zaman tekil isim alır: “Every student in the class passed.”'),
  (statement: 'İngilizce dilbilgisi: “I used to play the violin as a child.” cümlesi doğrudur.', isTrue: true, explain: 'Geçmişte sürmüş ama artık bırakılmış alışkanlıklar için “used to + V1” doğrudur.'),
  (statement: 'İngilizce dilbilgisi: “By next year, they will have finished the bridge.” cümlesi doğrudur.', isTrue: true, explain: 'Future Perfect (will have + V3), gelecekte belirli bir noktadan önce tamamlanacak eylemi anlatır.'),
  (statement: 'İngilizce dilbilgisi: “She suggested me to take the train.” cümlesi doğrudur.', isTrue: false, explain: '“Suggest” + nesne + to V1 almaz; doğrusu “She suggested taking the train” veya “suggested that I take...” olur.'),
  (statement: 'İngilizce dilbilgisi: “How long have you known each other?” cümlesi doğrudur.', isTrue: true, explain: '“Know” durum fiili olduğundan Present Perfect Simple ile “have you known” doğru kullanılır.'),
  // Matematik & Teknoloji
  (statement: 'Bir üçgenin iç açılarının toplamı Öklid düzleminde 180 derecedir.', isTrue: true, explain: 'Düzlemsel (Öklid) geometride her üçgenin iç açıları toplamı 180°’dir.'),
  (statement: 'Sıfır sayısı pozitif bir tam sayıdır.', isTrue: false, explain: 'Sıfır ne pozitif ne negatiftir; işaretsiz bir çift tam sayıdır.'),
  (statement: '2 sayısı bilinen tek çift asal sayıdır.', isTrue: true, explain: '2’den büyük tüm çift sayılar 2’ye bölünebildiğinden başka çift asal yoktur.'),
  (statement: 'İkili (binary) sayı sisteminde 1010 sayısı onluk sistemde 10’a eşittir.', isTrue: true, explain: '1×8 + 0×4 + 1×2 + 0×1 = 10.'),
  (statement: 'HTTP protokolü verileri varsayılan olarak uçtan uca şifreler.', isTrue: false, explain: 'Düz HTTP şifresizdir; TLS/SSL ile şifrelenen sürüm HTTPS’tir.'),
];

AdvancedItem _buildTrueFalse(int i) {
  // 50 verified core facts + 450 parametric verifiable math/binary/year/English-grammar statements = 500
  if (i < _tfBank.length) {
    final f = _tfBank[i];
    return AdvancedItem(
      'Doğru mu Yanlış mı?\n${f.statement}',
      f.isTrue ? 'Doğru' : 'Yanlış',
      [f.isTrue ? 'Yanlış' : 'Doğru'],
      f.explain,
    );
  }
  final k = i - _tfBank.length; // 0..449
  final kind = k % 3;
  final n = k ~/ 3; // 0..149
  if (kind == 0) {
    // Parametric arithmetic & percentage truth verification
    final base = 20 + (n % 25) * 4;
    final pct = 10 + (n % 5) * 15; // 10, 25, 40, 55, 70
    final exact = (base * pct) ~/ 100;
    final makeTrue = n.isEven;
    final shown = makeTrue ? exact : exact + (n % 3 + 1) * 2;
    return AdvancedItem(
      'Doğru mu Yanlış mı?\n$base sayısının %$pct kadarı $shown sayısına eşittir.',
      makeTrue ? 'Doğru' : 'Yanlış',
      [makeTrue ? 'Yanlış' : 'Doğru'],
      '$base × $pct / 100 = $exact olduğundan önerme ${makeTrue ? 'doğrudur' : 'yanlıştır'}.',
    );
  } else if (kind == 1) {
    // Parametric binary conversion truth check
    final val = 5 + (n % 58);
    final bin = val.toRadixString(2);
    final makeTrue = n.isOdd;
    final shown = makeTrue ? val : val + (n % 2 == 0 ? 2 : -1);
    return AdvancedItem(
      'Doğru mu Yanlış mı?\nİkili (binary) sistemdeki $bin sayısı onluk sistemde $shown değerine eşittir.',
      makeTrue ? 'Doğru' : 'Yanlış',
      [makeTrue ? 'Yanlış' : 'Doğru'],
      '($bin)₂ = $val olduğundan bu ifade ${makeTrue ? 'doğrudur' : 'yanlıştır'}.',
    );
  } else {
    // Parametric English regular/irregular verb & tense check
    const verbChecks = [
      ('go', 'went', 'goed'),
      ('write', 'wrote', 'writed'),
      ('speak', 'spoke', 'speaked'),
      ('choose', 'chose', 'choosed'),
      ('break', 'broke', 'breaked'),
      ('begin', 'began', 'begined'),
      ('drink', 'drank', 'drinked'),
      ('drive', 'drove', 'drived'),
      ('forget', 'forgot', 'forgetted'),
      ('know', 'knew', 'knowed'),
      ('teach', 'taught', 'teached'),
      ('bring', 'brought', 'bringed'),
      ('buy', 'bought', 'buyed'),
      ('catch', 'caught', 'catched'),
      ('think', 'thought', 'thinked'),
      ('swim', 'swam', 'swimmed'),
      ('fly', 'flew', 'flied'),
      ('grow', 'grew', 'growed'),
      ('wear', 'wore', 'weared'),
      ('build', 'built', 'builded'),
    ];
    final v = verbChecks[n % verbChecks.length];
    final makeTrue = (n ~/ verbChecks.length).isEven;
    final used = makeTrue ? v.$2 : v.$3;
    return AdvancedItem(
      'Doğru mu Yanlış mı?\nİngilizce “${v.$1}” fiilinin geçmiş zaman (Past Simple / V2) hâli “$used” biçimindedir.',
      makeTrue ? 'Doğru' : 'Yanlış',
      [makeTrue ? 'Yanlış' : 'Doğru'],
      '“${v.$1}” düzensiz bir fiildir ve V2 geçmiş zaman hâli “${v.$2}” şeklindedir.',
    );
  }
}

// ---------------------------------------------------------------------------
// 7. AKILLI BOŞLUK DOLDURMA (500 soru)
// ---------------------------------------------------------------------------
const _irregularVerbsFill = <(String, String, String, String)>[
  ('go', 'went', 'gone', 'gitmek'),
  ('see', 'saw', 'seen', 'görmek'),
  ('take', 'took', 'taken', 'almak'),
  ('write', 'wrote', 'written', 'yazmak'),
  ('speak', 'spoke', 'spoken', 'konuşmak'),
  ('eat', 'ate', 'eaten', 'yemek'),
  ('give', 'gave', 'given', 'vermek'),
  ('know', 'knew', 'known', 'bilmek'),
  ('begin', 'began', 'begun', 'başlamak'),
  ('drink', 'drank', 'drunk', 'içmek'),
  ('break', 'broke', 'broken', 'kırmak'),
  ('choose', 'chose', 'chosen', 'seçmek'),
  ('drive', 'drove', 'driven', 'sürmek'),
  ('forget', 'forgot', 'forgotten', 'unutmak'),
  ('freeze', 'froze', 'frozen', 'donmak'),
  ('fly', 'flew', 'flown', 'uçmak'),
  ('grow', 'grew', 'grown', 'büyümek'),
  ('ride', 'rode', 'ridden', 'binmek'),
  ('rise', 'rose', 'risen', 'yükselmek'),
  ('shake', 'shook', 'shaken', 'sallamak'),
  ('steal', 'stole', 'stolen', 'çalmak'),
  ('swim', 'swam', 'swum', 'yüzmek'),
  ('throw', 'threw', 'thrown', 'fırlatmak'),
  ('wear', 'wore', 'worn', 'giymek'),
  ('teach', 'taught', 'taught', 'öğretmek'),
  ('catch', 'caught', 'caught', 'yakalamak'),
  ('bring', 'brought', 'brought', 'getirmek'),
  ('buy', 'bought', 'bought', 'satın almak'),
  ('think', 'thought', 'thought', 'düşünmek'),
  ('build', 'built', 'built', 'inşa etmek'),
  ('feel', 'felt', 'felt', 'hissetmek'),
  ('keep', 'kept', 'kept', 'saklamak / tutmak'),
  ('leave', 'left', 'left', 'ayrılmak'),
  ('meet', 'met', 'met', 'buluşmak'),
  ('send', 'sent', 'sent', 'göndermek'),
  ('sleep', 'slept', 'slept', 'uyumak'),
  ('spend', 'spent', 'spent', 'harcamak'),
  ('understand', 'understood', 'understood', 'anlamak'),
  ('win', 'won', 'won', 'kazanmak'),
  ('find', 'found', 'found', 'bulmak'),
];

const _chemSymbolsFill = <(String, String)>[
  ('Altın', 'Au'), ('Gümüş', 'Ag'), ('Demir', 'Fe'), ('Bakır', 'Cu'),
  ('Sodyum', 'Na'), ('Potasyum', 'K'), ('Kalsiyum', 'Ca'), ('Magnezyum', 'Mg'),
  ('Karbon', 'C'), ('Oksijen', 'O'), ('Azot', 'N'), ('Hidrojen', 'H'),
  ('Helyum', 'He'), ('Neon', 'Ne'), ('Argon', 'Ar'), ('Klor', 'Cl'),
  ('Flor', 'F'), ('Fosfor', 'P'), ('Kükürt', 'S'), ('Silisyum', 'Si'),
  ('Alüminyum', 'Al'), ('Çinko', 'Zn'), ('Cıva', 'Hg'), ('Kurşun', 'Pb'),
  ('Kalay', 'Sn'), ('Nikel', 'Ni'), ('Platin', 'Pt'), ('Lityum', 'Li'),
  ('Bor', 'B'), ('İyot', 'I'),
];

AdvancedItem _buildSmartFill(int i) {
  final kind = i % 4; // 0: English V2/V3 (125), 1: Mental math (125), 2: Binary/Hex (125), 3: Chem/Geo short answer (125)
  final k = i ~/ 4; // 0..124

  if (kind == 0) {
    final v = _irregularVerbsFill[k % _irregularVerbsFill.length];
    final askV3 = (k ~/ _irregularVerbsFill.length).isOdd;
    final ans = askV3 ? v.$3 : v.$2;
    return AdvancedItem(
      askV3
          ? 'Boşluğu İngilizce fiilin 3. hâli (Past Participle / V3) ile doldurun:\n“She has already ___ (${v.$1} — ${v.$4}) it.”'
          : 'Boşluğu İngilizce fiilin 2. hâli (Past Simple / V2) ile doldurun:\n“Yesterday he ___ (${v.$1} — ${v.$4}) early.”',
      ans,
      [v.$1, askV3 ? v.$2 : v.$3, '${v.$1}ed'],
      '“${v.$1}” (${v.$4}) fiilinin çekimi: V1 ${v.$1} – V2 ${v.$2} – V3 ${v.$3}.',
    );
  } else if (kind == 1) {
    // Clean exact mental math equation
    final a = 3 + (k % 12);
    final b = 4 + ((k ~/ 12) % 9);
    final c = 5 + (k % 15);
    final res = a * b + c;
    return AdvancedItem(
      'İşlem önceliğine dikkat ederek sonucu yazın:\n$a × $b + $c = ___',
      '$res',
      ['${res + a}', '${res - c}', '${a * (b + c)}'],
      'Önce çarpma yapılır: $a × $b = ${a * b}; ardından $c eklenince $res bulunur.',
    );
  } else if (kind == 2) {
    // Binary to decimal conversion
    final val = 6 + k; // 6..130
    final bin = val.toRadixString(2);
    return AdvancedItem(
      'İkili (binary) sayı sistemindeki “$bin” sayısının onluk (decimal) karşılığını yazın:',
      '$val',
      ['${val + 1}', '${val + 2}', '${val - 1}'],
      '($bin)₂ sayısının basamak değerleri toplandığında onluk karşılığı $val olur.',
    );
  } else {
    final el = _chemSymbolsFill[k % _chemSymbolsFill.length];
    final mode = (k ~/ _chemSymbolsFill.length) % 2;
    if (mode == 0) {
      return AdvancedItem(
        '${el.$1} elementinin periyodik tablodaki kimyasal sembolünü yazın:',
        el.$2,
        ['X', 'Q', 'Z'],
        '${el.$1} elementinin uluslararası kimyasal sembolü "${el.$2}" şeklindedir.',
      );
    }
    final pctBase = 100 + (k % 15) * 20;
    final pct = 15 + (k % 4) * 10; // 15,25,35,45
    final ans = (pctBase * pct) ~/ 100;
    return AdvancedItem(
      '$pctBase sayısının %$pct kadarı kaçtır? (Yalnızca sayıyı yazın)',
      '$ans',
      ['${ans + 5}', '${ans + 10}', '${ans - 5}'],
      '$pctBase × $pct / 100 = $ans.',
    );
  }
}

final List<AdvancedFamily> interactiveStudio3kFamilies = [
  AdvancedFamily(
    key: 'st10k_match_world',
    title: 'Eşleştirme Atölyesi · Dünya, Bilim & Edebiyat',
    topic: Topic.culture,
    level: StudyLevel.lise,
    count: 400,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.matching,
    bloom: BloomLevel.hatirlama,
    sourceLabel: 'Bilgili 3.20 · Etkileşimli Stüdyo',
    build: _buildMatchWorld,
  ),
  AdvancedFamily(
    key: 'st10k_match_en',
    title: 'İngilizce Deyim & Phrasal Verb Eşleştirme',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 350,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.matching,
    bloom: BloomLevel.anlama,
    sourceLabel: 'Bilgili 3.20 · Etkileşimli Stüdyo',
    build: _buildMatchEnglish,
  ),
  AdvancedFamily(
    key: 'st10k_order_hist_sci',
    title: 'Kronoloji, Gezegen & Süreç Sıralama',
    topic: Topic.history,
    level: StudyLevel.lise,
    count: 450,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.ordering,
    bloom: BloomLevel.analiz,
    sourceLabel: 'Bilgili 3.20 · Etkileşimli Stüdyo',
    build: _buildOrderHistSci,
  ),
  AdvancedFamily(
    key: 'st10k_order_en',
    title: 'İngilizce Cümle Kurma (Word Order)',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 300,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.ordering,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.20 · Etkileşimli Stüdyo',
    build: _buildOrderEnglish,
  ),
  AdvancedFamily(
    key: 'st10k_multi_select',
    title: 'Çoklu Doğru Seçim (Hepsini Bul)',
    topic: Topic.science,
    level: StudyLevel.lise,
    count: 500,
    difficulty: Difficulty.hard,
    bloom: BloomLevel.degerlendirme,
    multiSelect: _buildMultiSelectTask,
    sourceLabel: 'Bilgili 3.20 · Etkileşimli Stüdyo',
    build: _buildMultiBase,
  ),
  AdvancedFamily(
    key: 'st10k_true_false',
    title: 'Hızlı Doğru / Yanlış Yargı Arenası',
    topic: Topic.culture,
    level: StudyLevel.lise,
    count: 500,
    difficulty: Difficulty.easy,
    bloom: BloomLevel.anlama,
    fixedResponseType: ResponseType.trueFalse,
    sourceLabel: 'Bilgili 3.20 · Etkileşimli Stüdyo',
    build: _buildTrueFalse,
  ),
  AdvancedFamily(
    key: 'st10k_fill_smart',
    title: 'Akıllı Boşluk Doldurma · Dil, Matematik & Fen',
    topic: Topic.exam,
    level: StudyLevel.lise,
    count: 500,
    difficulty: Difficulty.medium,
    bloom: BloomLevel.uygulama,
    fixedResponseType: ResponseType.fill,
    sourceLabel: 'Bilgili 3.20 · Etkileşimli Stüdyo',
    build: _buildSmartFill,
  ),
];
