import 'dart:math';
import '../common.dart';

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

List<String> _pickDistinct(List<String> pool, String correct, int seed) {
  final out = <String>[];
  final n = pool.length;
  var step = 1;
  for (final candStep in const [7, 5, 3, 2, 1]) {
    if (n > candStep && _gcd(n, candStep) == 1) {
      step = candStep;
      break;
    }
  }
  var cursor = (seed * 19 + 5) % n;
  var guard = 0;
  while (out.length < 3 && guard < n) {
    final cand = pool[cursor];
    if (cand != correct && !out.contains(cand)) {
      out.add(cand);
    }
    cursor = (cursor + step) % n;
    guard++;
  }
  return out;
}

List<String> _intWrong(
  int correct,
  int seed, {
  String suffix = '',
  int minVal = -999999,
  List<int> deltas = const [1, -1, 2, -2, 3, -3, 5, -5, 10, -10],
}) {
  final out = <String>[];
  final seen = <int>{correct};
  final offset = seed.abs() % deltas.length;
  for (var k = 0; k < deltas.length * 2 && out.length < 3; k++) {
    final v = correct + deltas[(offset + k) % deltas.length];
    if (v >= minVal && seen.add(v)) out.add('$v$suffix');
  }
  var bump = 1;
  while (out.length < 3) {
    final v = correct + bump;
    if (seen.add(v)) out.add('$v$suffix');
    bump++;
  }
  return out;
}

const _perm4 = [
  [1, 3, 0, 2],
  [2, 0, 3, 1],
  [3, 2, 1, 0],
  [1, 0, 3, 2],
  [2, 3, 0, 1],
  [3, 0, 2, 1],
];

List<String> _scrambleLetters(String word, int seed) {
  final chars = word.split('');
  final n = chars.length;
  if (n <= 1) return chars;
  // Deterministic Fisher-Yates shuffle
  var s = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
  final out = List<String>.from(chars);
  for (var j = n - 1; j > 0; j--) {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
    final k = s % (j + 1);
    final tmp = out[j];
    out[j] = out[k];
    out[k] = tmp;
  }
  if (out.join() == word) {
    // Rotate by 1 to ensure scrambled != original
    final first = out.removeAt(0);
    out.add(first);
  }
  return out;
}

// ===========================================================================
// 1. 3D TAHMİN SÜRGÜSÜ (ActivityKind.slider · 4.500 soru)
// ===========================================================================
typedef _SliderFact = ({
  String prompt,
  int min,
  int max,
  int step,
  int tol,
  String unit,
  int target,
  String explain,
});

const _sliderFacts = <_SliderFact>[
  (prompt: 'Malazgirt Meydan Muharebesi hangi yılda gerçekleşmiştir?', min: 1000, max: 1200, step: 1, tol: 10, unit: '', target: 1071, explain: 'Malazgirt Zaferi 26 Ağustos 1071 tarihinde kazanılmıştır.'),
  (prompt: 'İstanbul’un fethi hangi yılda gerçekleşmiştir?', min: 1400, max: 1550, step: 1, tol: 5, unit: '', target: 1453, explain: 'Fatih Sultan Mehmet 29 Mayıs 1453 tarihinde İstanbul’u fethetmiştir.'),
  (prompt: 'Türkiye Cumhuriyeti hangi yılda ilan edilmiştir?', min: 1900, max: 1950, step: 1, tol: 2, unit: '', target: 1923, explain: 'Türkiye Cumhuriyeti 29 Ekim 1923 tarihinde ilan edilmiştir.'),
  (prompt: 'Apollo 11 göreviyle insanlık Ay’a ilk kez hangi yılda ayak basmıştır?', min: 1950, max: 1990, step: 1, tol: 3, unit: '', target: 1969, explain: 'Neil Armstrong ve Buzz Aldrin 20 Temmuz 1969 tarihinde Ay’a inmiştir.'),
  (prompt: 'Fransız İhtilali hangi yılda başlamıştır?', min: 1750, max: 1850, step: 1, tol: 8, unit: '', target: 1789, explain: 'Fransız İhtilali 14 Temmuz 1789’da Bastille Baskını ile başlamıştır.'),
  (prompt: 'Berlin Duvarı hangi yılda yıkılmıştır?', min: 1970, max: 2010, step: 1, tol: 3, unit: '', target: 1989, explain: 'Berlin Duvarı 9 Kasım 1989 tarihinde yıkılmıştır.'),
  (prompt: 'Matbaayı Avrupa’da yaygınlaştıran Gutenberg İncili yaklaşık hangi yılda basılmıştır?', min: 1400, max: 1520, step: 1, tol: 12, unit: '', target: 1455, explain: 'Gutenberg hareketli harfli matbaayla yaklaşık 1455’te baskı yapmıştır.'),
  (prompt: 'Ağrı Dağı’nın zirve yüksekliği yaklaşık kaç metredir?', min: 3500, max: 6000, step: 50, tol: 200, unit: 'm', target: 5137, explain: 'Türkiye’nin en yüksek dağı olan Ağrı Dağı 5137 metre yüksekliğindedir.'),
  (prompt: 'Everest Dağı’nın deniz seviyesinden yüksekliği yaklaşık kaç metredir?', min: 7000, max: 9500, step: 50, tol: 200, unit: 'm', target: 8849, explain: 'Himalayalar’daki Everest zirvesi 8849 metredir.'),
  (prompt: 'Kızılırmak Nehri’nin uzunluğu yaklaşık kaç kilometredir?', min: 600, max: 2000, step: 25, tol: 125, unit: 'km', target: 1355, explain: 'Türkiye sınırları içindeki en uzun akarsu Kızılırmak yaklaşık 1355 km’dir.'),
  (prompt: 'Sesin 20 °C havadaki yayılma hızı yaklaşık kaç m/s’dir?', min: 100, max: 600, step: 5, tol: 25, unit: 'm/s', target: 343, explain: 'Ses 20 °C kuru havada yaklaşık 343 m/s hızla yayılır.'),
  (prompt: 'Deniz seviyesinde saf suyun kaynama noktası kaç °C’dir?', min: 50, max: 150, step: 1, tol: 2, unit: '°C', target: 100, explain: '1 atm basınçta saf su 100 °C’de kaynar.'),
  (prompt: 'İnsan vücudunda yetişkin bir bireyde kaç kemik bulunur?', min: 150, max: 300, step: 1, tol: 10, unit: 'kemik', target: 206, explain: 'Yetişkin insan iskeleti 206 kemikten oluşur.'),
  (prompt: 'Dünya’nın kendi ekseni etrafında 1 tam dönüşü için geçen süre kaç saattir?', min: 10, max: 40, step: 1, tol: 1, unit: 'saat', target: 24, explain: 'Bir güneş günü 24 saattir.'),
  (prompt: 'Dünya’nın ekvator çevresi yaklaşık kaç bin kilometredir?', min: 20, max: 60, step: 1, tol: 3, unit: 'bin km', target: 40, explain: 'Dünya’nın ekvator çevresi yaklaşık 40.075 km (40 bin km) uzunluğundadır.'),
  (prompt: 'Olimpiyat Oyunları’nda standart maraton koşusu yaklaşık kaç kilometredir?', min: 20, max: 60, step: 1, tol: 2, unit: 'km', target: 42, explain: 'Maraton mesafesi tam olarak 42,195 km (yaklaşık 42 km)’dir.'),
  (prompt: 'Bir satranç tahtasında toplam kaç kare vardır?', min: 32, max: 100, step: 2, tol: 2, unit: 'kare', target: 64, explain: 'Satranç tahtası 8×8 = 64 kareden oluşur.'),
  (prompt: 'Standart bir piyanoda (tam boy) toplam kaç tuş bulunur?', min: 60, max: 108, step: 1, tol: 4, unit: 'tuş', target: 88, explain: 'Standart konser piyanosu 52 beyaz ve 36 siyah olmak üzere 88 tuşludur.'),
  (prompt: 'Bir futbol maçının normal süresi toplam kaç dakikadır?', min: 45, max: 120, step: 5, tol: 5, unit: 'dk', target: 90, explain: 'Futbol maçı 45+45 = 90 dakika sürer.'),
  (prompt: 'Mars gezegeninin Güneş etrafındaki 1 yılı yaklaşık kaç Dünya günüdür?', min: 400, max: 900, step: 10, tol: 40, unit: 'gün', target: 687, explain: 'Mars yörüngesini yaklaşık 687 Dünya gününde tamamlar.'),
  (prompt: 'Merkür gezegeninin Güneş etrafındaki 1 yılı yaklaşık kaç Dünya günüdür?', min: 40, max: 200, step: 2, tol: 10, unit: 'gün', target: 88, explain: 'Güneş’e en yakın gezegen Merkür 1 turunu 88 Dünya gününde tamamlar.'),
  (prompt: 'Türkiye’nin toplam kaç ili vardır?', min: 50, max: 100, step: 1, tol: 2, unit: 'il', target: 81, explain: 'Türkiye idari olarak 81 ilden oluşur.'),
  (prompt: 'İlk modern Olimpiyat Oyunları Atina’da hangi yılda düzenlenmiştir?', min: 1870, max: 1930, step: 1, tol: 5, unit: '', target: 1896, explain: 'İlk modern Olimpiyat Oyunları 1896’da Atina’da yapıldı.'),
  (prompt: 'TBMM Ankara’da hangi yılda açılmıştır?', min: 1900, max: 1940, step: 1, tol: 2, unit: '', target: 1920, explain: 'Türkiye Büyük Millet Meclisi 23 Nisan 1920’de açılmıştır.'),
  (prompt: 'İnsan DNA’sı kaç kromozomdan oluşur (sağlıklı vücut hücresinde)?', min: 20, max: 70, step: 1, tol: 2, unit: 'kromozom', target: 46, explain: 'İnsan vücut hücrelerinde 23 çift yani 46 kromozom bulunur.'),
  (prompt: 'Altının atom numarası (periyodik tablodaki proton sayısı) kaçtır?', min: 50, max: 100, step: 1, tol: 4, unit: '', target: 79, explain: 'Altın (Au) elementinin atom numarası 79’dur.'),
  (prompt: 'Periyodik tabloda bugün onaylanmış toplam kaç element vardır?', min: 90, max: 140, step: 1, tol: 4, unit: 'element', target: 118, explain: 'Modern periyodik tablo Hidrojenden (1) Oganesson’a (118) kadar 118 element içerir.'),
  (prompt: 'Işığın boşluktaki hızı yaklaşık kaç bin km/s’dir?', min: 150, max: 450, step: 5, tol: 15, unit: 'bin km/s', target: 300, explain: 'Işık boşlukta saniyede yaklaşık 300.000 km yol alır.'),
  (prompt: 'Bir yılda (artık olmayan yılda) toplam kaç gün vardır?', min: 300, max: 400, step: 1, tol: 2, unit: 'gün', target: 365, explain: 'Normal bir takvim yılı 365 gündür.'),
  (prompt: 'Güneş ışığının Dünya’ya ulaşması yaklaşık kaç saniye sürer?', min: 200, max: 800, step: 10, tol: 30, unit: 'sn', target: 500, explain: 'Güneş ışığı Dünya’ya yaklaşık 8 dakika 20 saniye (500 sn) içinde ulaşır.'),
];

AdvancedItem _buildSliderEst(int i) {
  final mode = i % 6; // 6 modes × 750 = 4.500
  final k = i ~/ 6;

  late final String prompt;
  late final int minV, maxV, step, tol, target;
  late final String unit, explain, title;

  if (mode == 0) {
    // Curated world/science/history milestones + offset variations
    final f = _sliderFacts[k % _sliderFacts.length];
    final shift = (k ~/ _sliderFacts.length) % 4;
    if (shift == 0 || f.unit.isNotEmpty) {
      title = 'Bilgi & Ölçüm Sürgüsü';
      prompt = f.prompt;
      minV = f.min;
      maxV = f.max;
      step = f.step;
      tol = f.tol;
      unit = f.unit;
      target = f.target;
      explain = f.explain;
    } else {
      final addY = shift * 10;
      title = 'Tarihsel Zaman Çizelgesi';
      prompt = '${f.prompt.replaceAll('?', '')} tarihinden tam $addY yıl SONRAKİ yıl hangisidir?';
      minV = f.min + addY;
      maxV = f.max + addY;
      step = f.step;
      tol = f.tol;
      unit = '';
      target = f.target + addY;
      explain = 'Olay yılı ${f.target}; +$addY yıl sonrası $target yılıdır.';
    }
  } else if (mode == 1) {
    // Speed × Time = Distance estimator
    final speed = 40 + (k % 15) * 10; // 40..180 km/sa
    final hours = 2 + ((k ~/ 15) % 6); // 2..7 saat
    target = speed * hours;
    minV = max(50, ((target - 250) ~/ 10) * 10);
    maxV = minV + 500;
    step = 10;
    tol = 20;
    unit = 'km';
    title = 'Hız & Mesafe Tahmini';
    prompt = 'Saatte $speed km sabit hızla giden bir tren $hours saatte kaç km yol alır? Sürgüyle kilitleyin.';
    explain = 'Yol = Hız × Zaman = $speed × $hours = $target km.';
  } else if (mode == 2) {
    // Percentage of a number estimator
    const pcts = [10, 15, 20, 25, 30, 35, 40, 45, 60, 75, 80];
    final p = pcts[k % pcts.length];
    final base = 100 + ((k ~/ pcts.length) % 18) * 100; // 100..1800
    target = (base * p) ~/ 100;
    minV = 0;
    maxV = base;
    step = max(5, base ~/ 40);
    tol = max(10, base ~/ 25);
    unit = '';
    title = 'Yüzde Oran Sürgüsü';
    prompt = '$base sayısının %$p değeri kaçtır? Sürgüyü doğru konuma getirip kilitleyin.';
    explain = '$base × $p / 100 = $target.';
  } else if (mode == 3) {
    // Celsius -> Fahrenheit exact conversion (multiples of 5°C => exact integer °F)
    final c = -10 + (k % 23) * 5; // -10°C .. 100°C
    target = (c * 9) ~/ 5 + 32;
    minV = 0;
    maxV = 240;
    step = 1;
    tol = 5;
    unit = '°F';
    title = 'Sıcaklık Dönüşüm Sürgüsü';
    prompt = '$c °C sıcaklık, Fahrenheit (°F) ölçeğinde kaç °F değerine eşittir? (F = 1,8·C + 32)';
    explain = 'F = (9/5) × $c + 32 = $target °F.';
  } else if (mode == 4) {
    // Triangle third angle or supplementary/complementary angle
    final a = 25 + (k % 70); // 25..94
    final b = 20 + ((k * 3) % 60); // 20..79
    target = 180 - a - b;
    minV = 0;
    maxV = 180;
    step = 1;
    tol = 3;
    unit = '°';
    title = 'Üçgen İç Açı Sürgüsü';
    prompt = 'İki iç açısı $a° ve $b° olan bir üçgenin üçüncü iç açısı kaç derecedir?';
    explain = 'Üçgenin iç açıları toplamı 180° olduğundan 180° − ($a° + $b°) = $target°.';
  } else {
    // Mental multiplication / area estimator
    final w = 12 + (k % 28); // 12..39
    final h = 6 + ((k ~/ 28) % 15); // 6..20
    target = w * h;
    minV = max(0, ((target - 150) ~/ 5) * 5);
    maxV = minV + 300;
    step = 5;
    tol = 15;
    unit = 'm²';
    title = 'Alan & Çarpım Tahmini';
    prompt = 'Kenarları $w m ve $h m olan dikdörtgen güneş tarlasının alanı kaç m²’dir?';
    explain = 'Alan = $w × $h = $target m².';
  }

  final suf = unit.isNotEmpty ? ' $unit' : '';
  final correctStr = '$target$suf';
  return AdvancedItem(
    prompt,
    correctStr,
    _intWrong(target, i, suffix: suf, minVal: minV, deltas: [step * 2, -step * 2, step * 4, -step * 4, step * 6]),
    explain,
    activity: QuestionActivity(
      kind: ActivityKind.slider,
      title: title,
      items: ['$minV', '$maxV', '$step', '$tol', unit],
      solution: [target],
    ),
  );
}

// ===========================================================================
// 2. 3D SESLİ İNGİLİZCE HARF DİZME / ANAGRAM (175 × 20 = 3.500 soru)
// ===========================================================================
const _anagramEn175 = <(String word, String tr, String clue)>[
  ('PLANET', 'gezegen', 'A large celestial body orbiting a star'),
  ('GALAXY', 'galaksi', 'A massive system of billions of stars'),
  ('COMPASS', 'pusula', 'A magnetic instrument pointing north'),
  ('BRIDGE', 'köprü', 'A structure built to cross a river or bay'),
  ('ISLAND', 'ada', 'Land completely surrounded by water'),
  ('HARBOR', 'liman', 'A sheltered port where ships anchor'),
  ('FOREST', 'orman', 'A wide area covered with dense trees'),
  ('DESERT', 'çöl', 'A dry region with very little rainfall'),
  ('GLACIER', 'buzul', 'A slow-moving river of dense ice'),
  ('VALLEY', 'vadi', 'Low land lying between hills or mountains'),
  ('CANYON', 'kanyon', 'A deep gorge carved by a river'),
  ('SUMMIT', 'zirve', 'The highest peak of a mountain'),
  ('OCEAN', 'okyanus', 'A vast body of salt water covering Earth'),
  ('BREEZE', 'esinti', 'A gentle and pleasant wind'),
  ('THUNDER', 'gök gürültüsü', 'The loud sound following lightning'),
  ('RAINBOW', 'gökkuşağı', 'A colorful arc appearing after rain'),
  ('ECLIPSE', 'tutulma', 'When one celestial body shadows another'),
  ('GRAVITY', 'yerçekimi', 'The force keeping planets in orbit'),
  ('ENERGY', 'enerji', 'The capacity to perform work or light a bulb'),
  ('OXYGEN', 'oksijen', 'The essential gas we breathe every second'),
  ('CARBON', 'karbon', 'The chemical element forming diamonds and life'),
  ('COPPER', 'bakır', 'A reddish metal widely used in electric wires'),
  ('SILVER', 'gümüş', 'A shiny precious metal with symbol Ag'),
  ('QUARTZ', 'kuvars', 'A common crystal mineral used in watches'),
  ('MAGNET', 'mıknatıs', 'An object attracting iron and steel'),
  ('PRISM', 'prizma', 'Glass that splits white light into a spectrum'),
  ('PHOTON', 'foton', 'A tiny packet of light energy'),
  ('PROTON', 'proton', 'A positively charged particle in an atom’s core'),
  ('NEUTRON', 'nötron', 'A neutral particle inside the atomic nucleus'),
  ('CIRCUIT', 'devre', 'A closed loop carrying electric current'),
  ('VOLTAGE', 'voltaj', 'Electrical potential difference measured in volts'),
  ('CURRENT', 'akım', 'The flow of electric charge through a wire'),
  ('BATTERY', 'batarya', 'A portable device storing chemical energy'),
  ('TURBINE', 'türbin', 'Spinning blades converting wind into power'),
  ('SOLAR', 'güneş enerjili', 'Relating to power captured from sunlight'),
  ('MATRIX', 'matris', 'A rectangular grid of numbers or symbols'),
  ('VECTOR', 'vektör', 'A quantity having both magnitude and direction'),
  ('RADIUS', 'yarıçap', 'Distance from the center of a circle to its edge'),
  ('ANGLE', 'açı', 'The space measured in degrees between two lines'),
  ('SQUARE', 'kare', 'A four-sided shape with equal sides and right angles'),
  ('VOLUME', 'hacim', 'The three-dimensional space an object occupies'),
  ('NUMBER', 'sayı', 'A mathematical value used for counting'),
  ('BINARY', 'ikili sistem', 'A number system using only zeros and ones'),
  ('CODING', 'kodlama', 'Writing step-by-step instructions for computers'),
  ('SERVER', 'sunucu', 'A computer providing data to other devices'),
  ('SCREEN', 'ekran', 'The flat display surface of a phone or monitor'),
  ('SIGNAL', 'sinyal', 'A wave or pulse transmitting information'),
  ('MEMORY', 'bellek', 'Storage where a computer or brain keeps facts'),
  ('PYTHON', 'Python dili', 'A popular high-level programming language'),
  ('ROBOT', 'robot', 'A programmable machine performing tasks'),
  ('DRONE', 'dron', 'An unmanned flying vehicle'),
  ('ROCKET', 'roket', 'A powerful vehicle launching satellites to space'),
  ('ORBIT', 'yörünge', 'The curved path of a planet around a star'),
  ('METEOR', 'meteor', 'A bright streak of light from space rock'),
  ('CRATER', 'krater', 'A bowl-shaped depression on the Moon'),
  ('MUSEUM', 'müze', 'A building exhibiting art and historical artifacts'),
  ('LIBRARY', 'kütüphane', 'A quiet place filled with books to borrow'),
  ('THEATER', 'tiyatro', 'A hall where live plays are performed'),
  ('CONCERT', 'konser', 'A live musical performance before an audience'),
  ('MELODY', 'melodi', 'A pleasing sequence of musical notes'),
  ('RHYTHM', 'ritim', 'A regular repeated pattern of sound or beats'),
  ('CHORD', 'akor', 'Three or more musical notes played together'),
  ('PIANO', 'piyano', 'A large keyboard instrument with black and white keys'),
  ('VIOLIN', 'keman', 'A four-stringed wooden instrument played with a bow'),
  ('GUITAR', 'gitar', 'A stringed instrument strummed with fingers'),
  ('OCTAVE', 'oktav', 'An interval of twelve semitones in music'),
  ('CANVAS', 'tuval', 'Heavy fabric on which artists paint'),
  ('PALETTE', 'palet', 'A thin board where painters mix colors'),
  ('STATUE', 'heykel', 'A carved or cast three-dimensional artwork'),
  ('DESIGN', 'tasarım', 'A creative plan for how something looks and works'),
  ('SKETCH', 'eskiz / taslak', 'A quick rough drawing made with a pencil'),
  ('NOVEL', 'roman', 'A long fictional story published as a book'),
  ('POETRY', 'şiir', 'Literary writing rich in rhythm and imagery'),
  ('AUTHOR', 'yazar', 'A person who writes books or articles'),
  ('CHAPTER', 'bölüm', 'One main numbered section of a book'),
  ('JOURNAL', 'günlük', 'A personal notebook of thoughts or travel notes'),
  ('LETTER', 'mektup / harf', 'A written message or a symbol of the alphabet'),
  ('PHRASE', 'ifade / söz öbeği', 'A small group of words expressing an idea'),
  ('ACCENT', 'aksan', 'A distinctive regional way of pronouncing words'),
  ('SPEECH', 'konuşma', 'A formal talk delivered to listeners'),
  ('LISTEN', 'dinlemek', 'To pay close attention to spoken sound'),
  ('ANSWER', 'cevap', 'A reply or solution to a question'),
  ('PUZZLE', 'bulmaca', 'A game testing logic and problem solving'),
  ('RIDDLE', 'bilmece', 'A clever question with a surprising answer'),
  ('WISDOM', 'bilgelik', 'Deep judgment gained from knowledge and experience'),
  ('TALENT', 'yetenek', 'A natural skill or gift for doing something well'),
  ('EFFORT', 'çaba', 'Determined work put into achieving a goal'),
  ('HABIT', 'alışkanlık', 'A routine action practiced regularly'),
  ('FOCUS', 'odak', 'Center of attention and clear concentration'),
  ('FUTURE', 'gelecek', 'The time that is yet to come'),
  ('HISTORY', 'tarih', 'The study of past human civilizations'),
  ('EMPIRE', 'imparatorluk', 'A vast historical realm of many territories'),
  ('CASTLE', 'kale', 'A fortified historic stone residence'),
  ('PALACE', 'saray', 'A grand official residence of rulers'),
  ('TEMPLE', 'tapınak', 'An ancient building devoted to worship'),
  ('FOSSIL', 'fosil', 'Preserved remains of prehistoric life in rock'),
  ('BRONZE', 'tunç / bronz', 'An ancient alloy of copper and tin'),
  ('MARBLE', 'mermer', 'A smooth metamorphic stone used in sculpture'),
  ('TICKET', 'bilet', 'A pass granting entry to a train or museum'),
  ('FLIGHT', 'uçuş', 'A journey made through the air by airplane'),
  ('PASSPORT', 'pasaport', 'An official booklet for international travel'),
  ('LUGGAGE', 'bagaj', 'Suitcases and bags carried by travelers'),
  ('AIRPORT', 'havalimanı', 'A complex of runways and terminals for planes'),
  ('STATION', 'istasyon', 'A regular stopping place for trains or buses'),
  ('SUBWAY', 'metro', 'An underground urban electric railway'),
  ('FERRY', 'vapur / feribot', 'A boat carrying passengers across a strait'),
  ('BICYCLE', 'bisiklet', 'A two-wheeled vehicle powered by pedals'),
  ('JOURNEY', 'yolculuk', 'Traveling from one place to another'),
  ('CAPITAL', 'başkent', 'The main administrative city of a country'),
  ('BORDER', 'sınır', 'The dividing line between two countries'),
  ('CLIMATE', 'iklim', 'Long-term weather pattern of a region'),
  ('AUTUMN', 'sonbahar', 'The season when leaves turn golden and fall'),
  ('WINTER', 'kış', 'The coldest season of the year'),
  ('SPRING', 'ilkbahar', 'The season when flowers bloom anew'),
  ('SUMMER', 'yaz', 'The warmest and sunniest season'),
  ('MORNING', 'sabah', 'The early part of the day after sunrise'),
  ('EVENING', 'akşam', 'The late part of the day around sunset'),
  ('MINUTE', 'dakika', 'A unit of time equal to sixty seconds'),
  ('SECOND', 'saniye', 'The basic SI unit of time'),
  ('CENTURY', 'yüzyıl', 'A period of one hundred consecutive years'),
  ('MARKET', 'pazar', 'A lively place where fresh goods are sold'),
  ('COFFEE', 'kahve', 'A popular roasted bean beverage'),
  ('BAKERY', 'fırın', 'A shop making fresh bread and pastries'),
  ('KITCHEN', 'mutfak', 'A room equipped for preparing meals'),
  ('RECIPE', 'tarif', 'Instructions and ingredients for cooking a dish'),
  ('ORANGE', 'portakal / turuncu', 'A citrus fruit and a warm bright color'),
  ('ALMOND', 'badem', 'A nutritious oval nut grown in sunny climates'),
  ('HONEY', 'bal', 'Sweet golden nectar produced by bees'),
  ('OLIVE', 'zeytin', 'A classic Mediterranean fruit pressed for oil'),
  ('PEPPER', 'biber', 'A colorful vegetable or spicy seasoning'),
  ('GARDEN', 'bahçe', 'A cultivated plot of flowers or vegetables'),
  ('FLOWER', 'çiçek', 'The colorful blooming part of a plant'),
  ('BRANCH', 'dal', 'A limb growing out from a tree trunk'),
  ('BAMBOO', 'bambu', 'A tall fast-growing hollow woody grass'),
  ('CACTUS', 'kaktüs', 'A spiny plant adapted to arid deserts'),
  ('ORCHID', 'orkide', 'An exotic flowering plant prized for beauty'),
  ('EAGLE', 'kartal', 'A powerful bird of prey with sharp vision'),
  ('FALCON', 'şahin', 'The fastest diving bird in the sky'),
  ('DOLPHIN', 'yunus', 'An intelligent and social marine mammal'),
  ('TURTLE', 'kaplumbağa', 'A reptile protected by a sturdy shell'),
  ('PENGUIN', 'penguen', 'A flightless swimming bird of cold seas'),
  ('JAGUAR', 'jaguar', 'A spotted big cat of South American forests'),
  ('PANDA', 'panda', 'A black-and-white bear that loves bamboo'),
  ('WHALE', 'balina', 'The largest mammal living in Earth’s oceans'),
  ('CORAL', 'mercan', 'Colorful marine organisms building ocean reefs'),
  ('DOCTOR', 'doktor', 'A medical professional who treats patients'),
  ('HEALTH', 'sağlık', 'Overall physical and mental well-being'),
  ('HEART', 'kalp', 'The muscular organ pumping blood continuously'),
  ('BRAIN', 'beyin', 'The command center of the nervous system'),
  ('MUSCLE', 'kas', 'Body tissue that contracts to produce movement'),
  ('VITAMIN', 'vitamin', 'An essential nutrient supporting immunity'),
  ('SOCCER', 'futbol', 'The world’s most widely played team sport'),
  ('TENNIS', 'tenis', 'A racket sport played across a central net'),
  ('TROPHY', 'kupa', 'An award presented to a championship winner'),
  ('MEDAL', 'madalya', 'A gold, silver, or bronze prize at the Olympics'),
  ('RUNNER', 'koşucu', 'An athlete competing in track or marathon races'),
  ('PLAYER', 'oyuncu', 'A participant competing in a match or quiz'),
  ('FRIEND', 'arkadaş', 'Someone you trust and enjoy spending time with'),
  ('FAMILY', 'aile', 'Parents, children, and close relatives'),
  ('SCHOOL', 'okul', 'An institution where students learn together'),
  ('TEACHER', 'öğretmen', 'A dedicated guide helping students grow'),
  ('STUDENT', 'öğrenci', 'A person actively studying a subject'),
  ('CAMPUS', 'kampüs', 'The grounds and buildings of a university'),
  ('SCIENCE', 'bilim', 'Systematic study of the natural universe'),
  ('PHYSICS', 'fizik', 'The science of matter, motion, and energy'),
  ('BIOLOGY', 'biyoloji', 'The scientific study of living organisms'),
  ('GEOLOGY', 'jeoloji', 'The science of rocks, plates, and Earth’s crust'),
  ('WEATHER', 'hava durumu', 'Daily atmospheric conditions like wind and rain'),
  ('CRYSTAL', 'kristal', 'A solid whose atoms form a neat geometric lattice'),
  ('SPECTRUM', 'spektrum', 'The continuous band of visible light colors'),
  ('HORIZON', 'ufuk', 'The line where Earth’s surface meets the sky'),
  ('DIAMOND', 'elmas', 'The hardest natural mineral made of pure carbon'),
  ('LANTERN', 'fener', 'A portable lamp shielding a glowing light'),
  ('ANCHOR', 'çapa', 'A heavy iron hook holding a ship in place'),
  ('MIRROR', 'ayna', 'A polished surface reflecting a clear image'),
];

const _accents = ['en-US', 'en-GB', 'en-AU'];

AdvancedItem _buildAnagramEn(int i) {
  final entry = _anagramEn175[i % _anagramEn175.length];
  final round = i ~/ _anagramEn175.length; // 0..19
  final word = entry.$1;
  final lang = _accents[(i + round) % 3];
  final tiles = _scrambleLetters(word, i + 17);
  final style = round % 4;
  final prompt = switch (style) {
    0 => 'Sesli İngilizce kelimeyi dinleyin ve karışık harflere dokunarak doğru yazımı kurun!\nTürkçe anlamı: "${entry.$2}"',
    1 => 'İngilizce açıklamaya göre doğru kelimeyi harf taşlarıyla dizin (sesi dinleyebilirsiniz):\n"${entry.$3}"',
    2 => 'Sesli İngilizce Harf Dizme (${word.length} harf): "${entry.$2}" anlamına gelen kelimeyi kurun.',
    _ => 'Dinle ve Harfleri Diz: "${entry.$3}" (${entry.$2}).',
  };
  final transcript = switch (style) {
    0 => '$word. ${entry.$3}.',
    1 => 'Spell the word: $word.',
    2 => '$word. Repeat: $word.',
    _ => '${entry.$3}. The word is $word.',
  };
  return AdvancedItem(
    prompt,
    word,
    _pickDistinct([for (final e in _anagramEn175) e.$1], word, i + 5),
    'Doğru yazım: "$word" (${entry.$2}) — ${entry.$3}.',
    activity: QuestionActivity(
      kind: ActivityKind.anagram,
      title: 'Sesli İngilizce Harf Dizme',
      language: lang,
      transcript: transcript,
      items: tiles,
      left: [word],
      solution: const [0],
    ),
  );
}

// ===========================================================================
// 3. 3D TÜRKÇE KÜLTÜR, BİLİM & COĞRAFYA HARF DİZME (125 × 20 = 2.500 soru)
// ===========================================================================
const _anagramTr125 = <(String word, String cat, String clue)>[
  ('ANKARA', 'Başkent', 'Türkiye Cumhuriyeti’nin başkenti'),
  ('İSTANBUL', 'Şehir', 'Asya ve Avrupa kıtalarını birleştiren metropol'),
  ('İZMİR', 'Şehir', 'Ege’nin incisi, saat kulesiyle ünlü liman kenti'),
  ('ANTALYA', 'Şehir', 'Akdeniz’in turizm başkenti'),
  ('TRABZON', 'Şehir', 'Sümela Manastırı’na ev sahipliği yapan Karadeniz ili'),
  ('KONYA', 'Şehir', 'Mevlânâ Türbesi ile tanınan İç Anadolu ili'),
  ('BURSA', 'Şehir', 'Uludağ eteklerindeki tarihi Osmanlı başkenti'),
  ('MARDİN', 'Şehir', 'Taş mimarisiyle ünlü Güneydoğu Anadolu kenti'),
  ('EDİRNE', 'Şehir', 'Selimiye Camii’nin bulunduğu Trakya kenti'),
  ('SAMSUN', 'Şehir', '19 Mayıs 1919’da Kurtuluş Savaşı’nın başladığı liman'),
  ('PARİS', 'Başkent', 'Eyfel Kulesi ve Louvre Müzesi’nin bulunduğu başkent'),
  ('LONDRA', 'Başkent', 'Thames Nehri kıyısındaki Birleşik Krallık başkenti'),
  ('TOKYO', 'Başkent', 'Japonya’nın teknoloji ve kültür başkenti'),
  ('ROMA', 'Başkent', 'Kolezyum’un bulunduğu İtalya başkenti'),
  ('BERLİN', 'Başkent', 'Brandenburg Kapısı ile ünlü Almanya başkenti'),
  ('MADRİD', 'Başkent', 'İspanya’nın başkenti'),
  ('VİYANA', 'Başkent', 'Klasik müziğin merkezi, Avusturya’nın başkenti'),
  ('ATİNA', 'Başkent', 'Akropolis’in bulunduğu Yunanistan başkenti'),
  ('KAHİRE', 'Başkent', 'Nil Nehri ve piramitlere komşu Mısır başkenti'),
  ('LİZBON', 'Başkent', 'Atlas Okyanusu kıyısındaki Portekiz başkenti'),
  ('MERKÜR', 'Astronomi', 'Güneş’e en yakın gezegen'),
  ('VENÜS', 'Astronomi', 'Yoğun atmosferiyle Güneş sisteminin en sıcak gezegeni'),
  ('MARS', 'Astronomi', 'Demir oksit yüzeyiyle “Kızıl Gezegen”'),
  ('JÜPİTER', 'Astronomi', 'Güneş sisteminin en büyük gaz devi gezegeni'),
  ('SATÜRN', 'Astronomi', 'Buz ve kaya halkalarıyla ünlü gezegen'),
  ('URANÜS', 'Astronomi', 'Yana yatık ekseniyle dönen buz devi gezegen'),
  ('NEPTÜN', 'Astronomi', 'Güneş’e en uzak sekizinci gezegen'),
  ('GALAKSİ', 'Astronomi', 'Milyarlarca yıldızdan oluşan gök adası'),
  ('YÖRÜNGE', 'Astronomi', 'Bir gök cisminin çekim altında izlediği yol'),
  ('TUTULMA', 'Astronomi', 'Ay veya Dünya’nın gölgesinin diğerine düşmesi'),
  ('OKSİJEN', 'Kimya', 'Atom numarası 8 olan, solunum için yaşamsal element'),
  ('KARBON', 'Kimya', 'Organik bileşiklerin temel taşı, atom numarası 6'),
  ('HİDROJEN', 'Kimya', 'Periyodik tablonun 1 numaralı en hafif elementi'),
  ('HELYUM', 'Kimya', 'Uçan balonları dolduran 2 numaralı soygaz'),
  ('SODYUM', 'Kimya', 'Sembolü Na olan yumuşak alkali metal'),
  ('DEMİR', 'Kimya', 'Sembolü Fe olan, çelik üretiminde temel metal'),
  ('BAKIR', 'Kimya', 'Sembolü Cu olan yüksek iletkenlikli metal'),
  ('ALTIN', 'Kimya', 'Sembolü Au olan değerli soy metal'),
  ('GÜMÜŞ', 'Kimya', 'Sembolü Ag olan en iyi elektrik iletkeni metal'),
  ('KALSİYUM', 'Kimya', 'Kemik ve diş yapısında bulunan Ca sembollü element'),
  ('MOLEKÜL', 'Kimya', 'Kovalent bağla birleşmiş atom grubu'),
  ('İZOTOP', 'Kimya', 'Proton sayısı aynı, nötron sayısı farklı atomlar'),
  ('KATALİZ', 'Kimya', 'Tepkimeyi hızlandıran kimyasal etki'),
  ('KUVVET', 'Fizik', 'Birimi Newton (N) olan vektörel büyüklük'),
  ('ENERJİ', 'Fizik', 'İş yapabilme yeteneği, birimi Joule'),
  ('BASINÇ', 'Fizik', 'Birim yüzeye dik etkiyen kuvvet, birimi Pascal'),
  ('DİRENÇ', 'Fizik', 'Elektrik akımına karşı koyma özelliği, birimi Ohm'),
  ('GERİLİM', 'Fizik', 'İki nokta arasındaki potansiyel fark, birimi Volt'),
  ('FREKANS', 'Fizik', 'Saniyedeki titreşim sayısı, birimi Hertz'),
  ('OPTİK', 'Fizik', 'Işığın davranışını ve mercekleri inceleyen fizik dalı'),
  ('PRİZMA', 'Fizik', 'Beyaz ışığı renk spektrumuna ayıran cam cisim'),
  ('MIKNATIS', 'Fizik', 'Kuzey ve güney kutbu bulunan manyetik cisim'),
  ('SÜRTÜNME', 'Fizik', 'Temas eden yüzeylerde harekete zıt direnç'),
  ('HÜCRE', 'Biyoloji', 'Tüm canlıların en küçük yapısal ve işlevsel birimi'),
  ('ENZİM', 'Biyoloji', 'Canlılarda tepkimeleri hızlandıran biyolojik protein'),
  ('GENETİK', 'Biyoloji', 'Kalıtım ve gen aktarımını inceleyen bilim dalı'),
  ('MİTOZ', 'Biyoloji', 'Vücut hücrelerinde iki özdeş hücre oluşturan bölünme'),
  ('MAYOZ', 'Biyoloji', 'Üreme hücrelerinde kromozom sayısını yarıya indiren bölünme'),
  ('NÖRON', 'Biyoloji', 'Sinir sisteminde uyartı ileten sinir hücresi'),
  ('PLAZMA', 'Biyoloji', 'Kanın sıvı kısmını oluşturan sarımsı ortam'),
  ('VİTAMİN', 'Biyoloji', 'Metabolizmada düzenleyici rol oynayan organik bileşik'),
  ('BAKTERİ', 'Biyoloji', 'Çekirdek zarı bulunmayan tek hücreli prokaryot'),
  ('MANTAR', 'Biyoloji', 'Fotosentez yapmayan, sporla üreyen canlı âlemi'),
  ('ÜÇGEN', 'Matematik', 'İç açıları toplamı 180 derece olan çokgen'),
  ('ÇEMBER', 'Matematik', 'Bir merkeze eşit uzaklıktaki noktalar kümesi'),
  ('PİRAMİT', 'Matematik', 'Tabanı çokgen, yan yüzleri üçgen katı cisim'),
  ('SİLİNDİR', 'Matematik', 'Alt ve üst tabanı eş dairelerden oluşan cisim'),
  ('VEKTÖR', 'Matematik', 'Büyüklüğü ve yönü olan yönlü doğru parçası'),
  ('MATRİS', 'Matematik', 'Satır ve sütunlardan oluşan sayı tablosu'),
  ('FAKTÖR', 'Matematik', 'Bir sayıyı kalansız bölen çarpan'),
  ('ORANTI', 'Matematik', 'İki veya daha fazla oranın eşitliği'),
  ('OLASILIK', 'Matematik', 'Bir olayın gerçekleşme ihtimalinin sayısal ölçüsü'),
  ('TEOREM', 'Matematik', 'Mantıksal kanıtla doğruluğu gösterilen önerme'),
  ('YAZILIM', 'Teknoloji', 'Bilgisayar donanımını yöneten programlar bütünü'),
  ('DONANIM', 'Teknoloji', 'Bilgisayarın elle tutulabilen fiziksel parçaları'),
  ('İŞLEMCİ', 'Teknoloji', 'Komutları yürüten merkezi hesaplama birimi (CPU)'),
  ('BELLEK', 'Teknoloji', 'Verilerin geçici veya kalıcı saklandığı alan'),
  ('SUNUCU', 'Teknoloji', 'Ağ üzerinden istemcilere hizmet veren sistem'),
  ('BULUT', 'Teknoloji', 'İnternet üzerinden erişilen uzak veri depolama ağı'),
  ('SENSÖR', 'Teknoloji', 'Isı, ışık veya hareketi algılayan elektronik parça'),
  ('DEVRE', 'Teknoloji', 'Elektrik akımının izlediği kapalı iletken yol'),
  ('ROBOTİK', 'Teknoloji', 'Otonom makinelerin tasarım ve kontrol mühendisliği'),
  ('PİKSEL', 'Teknoloji', 'Dijital bir görüntüyü oluşturan en küçük nokta'),
  ('PİYANO', 'Müzik', 'Tuşlu ve telli, 88 tuşlu klasik çalgı'),
  ('KEMAN', 'Müzik', 'Yayla çalınan dört telli orkestra çalgısı'),
  ('BAĞLAMA', 'Müzik', 'Türk halk müziğinin köklü tezene çalgısı'),
  ('SENFONİ', 'Müzik', 'Büyük orkestra için yazılmış çok bölümlü eser'),
  ('MELODİ', 'Müzik', 'Anlamlı bir bütün oluşturan ardışık nota dizisi'),
  ('ARMONİ', 'Müzik', 'Aynı anda duyulan seslerin ve akorların uyumu'),
  ('OKTAV', 'Müzik', 'Aynı adlı iki nota arasındaki sekizli ses aralığı'),
  ('SOLFEJ', 'Müzik', 'Notaları adlarıyla ve ritmiyle sesli okuma çalışması'),
  ('ROMAN', 'Edebiyat', 'Geniş zaman ve karakter kadrosuna sahip uzun anlatı'),
  ('HİKÂYE', 'Edebiyat', 'Kısa ve yoğun olay örgüsüne dayalı edebi tür'),
  ('DESTAN', 'Edebiyat', 'Toplumları etkileyen büyük olayları anlatan manzum eser'),
  ('TİYATRO', 'Edebiyat', 'Sahnede canlı oynanmak üzere yazılan sanat türü'),
  ('DENEME', 'Edebiyat', 'Yazarın kişisel düşüncelerini samimi dille aktardığı tür'),
  ('BİYOGRAFİ', 'Edebiyat', 'Ünlü bir kişinin yaşam öyküsünü anlatan eser'),
  ('FABL', 'Edebiyat', 'Kahramanları çoğunlukla hayvanlar olan ders verici masal'),
  ('KAFİYE', 'Edebiyat', 'Dize sonlarındaki anlamca farklı ses benzerliği'),
  ('DEVRİM', 'Tarih', 'Toplumsal ve siyasal düzende köklü dönüşüm'),
  ('ANAYASA', 'Tarih', 'Devletin temel yapısını ve hakları belirleyen üst yasa'),
  ('FERMAN', 'Tarih', 'Osmanlı padişahının mührünü taşıyan yazılı buyruk'),
  ('ANTLAŞMA', 'Tarih', 'Devletler arasında imzalanan resmi uluslararası metin'),
  ('UYGARLIK', 'Tarih', 'Bir toplumun bilim, sanat ve kültür birikimi'),
  ('ARKEOLOJİ', 'Tarih', 'Kazılarla geçmiş kültürlerin kalıntılarını inceleyen bilim'),
  ('BOĞAZ', 'Coğrafya', 'İki denizi birbirine bağlayan dar su geçidi'),
  ('YARIMADA', 'Coğrafya', 'Üç tarafı sularla çevrili kara parçası'),
  ('PLATOLAR', 'Coğrafya', 'Akarsularca yarılmış yüksek düzlüklere verilen ad'),
  ('BUZUL', 'Coğrafya', 'Yüksek dağ ve kutuplarda biriken dev buz kütlesi'),
  ('VOLKAN', 'Coğrafya', 'Magmanın yeryüzüne püskürdüğü yanardağ'),
  ('DEPREM', 'Coğrafya', 'Yer kabuğundaki fay kırılmasıyla oluşan sarsıntı'),
  ('MUSON', 'Coğrafya', 'Güney Asya’da mevsimlik yön değiştiren rüzgâr'),
  ('EKVATOR', 'Coğrafya', 'Dünya’yı kuzey ve güney yarımküreye bölen hayali çember'),
  ('MERİDYEN', 'Coğrafya', 'Kutupları birleştiren hayali boylam yayı'),
  ('PARALEL', 'Coğrafya', 'Ekvator’a paralel uzanan enlem çemberi'),
  ('PUSULA', 'Coğrafya', 'Manyetik kuzeyi göstererek yön bulduran alet'),
  ('HARİTA', 'Coğrafya', 'Yeryüzünün ölçekli küçültülerek düzleme aktarımı'),
  ('MARATON', 'Spor', '42,195 kilometrelik uzun mesafe koşusu'),
  ('SATRANÇ', 'Spor', '64 kare üzerinde oynanan köklü strateji oyunu'),
  ('VOLEYBOL', 'Spor', 'Altışar kişilik iki takımın file üzerinden oynadığı spor'),
  ('ESKRİM', 'Spor', 'Kılıçla puan mücadelesine dayanan olimpik spor'),
  ('KÜREK', 'Spor', 'Su üzerinde teknede senkronize çekişle yapılan spor'),
  ('OKÇULUK', 'Spor', 'Yay ve okla hedefi vurmaya dayanan tarihi spor'),
  ('MİMARLIK', 'Sanat', 'Yapı ve mekân tasarlama sanatı ve bilimi'),
  ('MOZAİK', 'Sanat', 'Renkli küçük taş parçalarıyla oluşturulan duvar resmi'),
];

AdvancedItem _buildAnagramTr(int i) {
  final e = _anagramTr125[i % _anagramTr125.length];
  final round = i ~/ _anagramTr125.length; // 0..19
  final word = e.$1;
  final tiles = _scrambleLetters(word, i + 31);
  final style = round % 4;
  final prompt = switch (style) {
    0 => '${e.$2} Harf Dizme: Karışık 3D taşlara dokunarak doğru kavramı oluşturun.\nİpucu: ${e.$3}.',
    1 => 'Harfleri doğru sıraya dizin (${word.length} harf · ${e.$2}): ${e.$3}.',
    2 => '3D Anagram Atölyesi [${e.$2}]: "${e.$3}" tanımına uyan sözcüğü kurun.',
    _ => 'İpucundan Kelime Kur (${e.$2}): ${e.$3}.',
  };
  return AdvancedItem(
    prompt,
    word,
    _pickDistinct([for (final x in _anagramTr125) x.$1], word, i + 7),
    'Doğru sözcük: $word (${e.$2}) — ${e.$3}.',
    activity: QuestionActivity(
      kind: ActivityKind.anagram,
      title: '3D Harf Dizme · ${e.$2}',
      language: 'tr-TR',
      items: tiles,
      left: [word],
      solution: const [0],
    ),
  );
}

// ===========================================================================
// 4. MEGA ÇİFT EŞLEŞTİRME ATÖLYESİ (10 Alan → 4.000 soru)
// ===========================================================================
typedef _Pair = (String, String);

const _megaMatchDomains = <(String, String, List<_Pair>)>[
  (
    'Ülke ↔ Başkent',
    'Sol sütundaki ülkeleri sağ sütundaki başkentleriyle eşleştirin.',
    [
      ('Türkiye', 'Ankara'), ('Japonya', 'Tokyo'), ('İspanya', 'Madrid'), ('Kanada', 'Ottawa'),
      ('Avustralya', 'Kanberra'), ('Brezilya', 'Brasília'), ('Mısır', 'Kahire'), ('Norveç', 'Oslo'),
      ('Portekiz', 'Lizbon'), ('İsviçre', 'Bern'), ('Güney Kore', 'Seul'), ('Arjantin', 'Buenos Aires'),
      ('Fas', 'Rabat'), ('Kazakistan', 'Astana'), ('Çekya', 'Prag'), ('Avusturya', 'Viyana'),
      ('İsveç', 'Stockholm'), ('Finlandiya', 'Helsinki'), ('Yunanistan', 'Atina'), ('İrlanda', 'Dublin'),
    ],
  ),
  (
    'Element ↔ Sembol',
    'Kimyasal elementleri doğru periyodik tablo sembolleriyle eşleştirin.',
    [
      ('Altın', 'Au'), ('Gümüş', 'Ag'), ('Demir', 'Fe'), ('Bakır', 'Cu'),
      ('Sodyum', 'Na'), ('Potasyum', 'K'), ('Cıva', 'Hg'), ('Kurşun', 'Pb'),
      ('Kalay', 'Sn'), ('Tungsten', 'W'), ('Fosfor', 'P'), ('Kükürt', 'S'),
      ('Kalsiyum', 'Ca'), ('Magnezyum', 'Mg'), ('Klor', 'Cl'), ('Azot', 'N'),
      ('Karbon', 'C'), ('Oksijen', 'O'), ('Helyum', 'He'), ('Argon', 'Ar'),
    ],
  ),
  (
    'İngilizce Phrasal Verb ↔ Anlam',
    'İngilizce deyimsel fiilleri Türkçe karşılıklarıyla eşleştirin.',
    [
      ('give up', 'vazgeçmek'), ('put off', 'ertelemek'), ('call off', 'iptal etmek'), ('figure out', 'çözmek'),
      ('run out of', 'tüketmek'), ('turn down', 'reddetmek'), ('carry out', 'yürütmek'), ('look into', 'araştırmak'),
      ('set up', 'kurmak'), ('take off', 'havalanmak'), ('get over', 'atlatmak'), ('come across', 'rastlamak'),
      ('cut down on', 'azaltmak'), ('bring up', 'gündeme getirmek'), ('find out', 'öğrenmek'), ('pick up', 'almak / toplamak'),
    ],
  ),
  (
    'Fizik Büyüklüğü ↔ SI Birimi',
    'Fiziksel büyüklükleri uluslararası SI birimleriyle eşleştirin.',
    [
      ('Kuvvet', 'Newton (N)'), ('Enerji', 'Joule (J)'), ('Güç', 'Watt (W)'), ('Basınç', 'Pascal (Pa)'),
      ('Frekans', 'Hertz (Hz)'), ('Elektrik Akımı', 'Amper (A)'), ('Gerilim', 'Volt (V)'), ('Direnç', 'Ohm (Ω)'),
      ('Elektrik Yükü', 'Coulomb (C)'), ('Sığa', 'Farad (F)'), ('Manyetik Akı', 'Weber (Wb)'), ('Sıcaklık', 'Kelvin (K)'),
      ('Işık Şiddeti', 'Kandela (cd)'), ('Madde Miktarı', 'Mol (mol)'), ('Hız', 'm/s'), ('İvme', 'm/s²'),
    ],
  ),
  (
    'Bilim İnsanı ↔ Buluş / Kuram',
    'Bilim insanlarını tarihe geçen katkılarıyla eşleştirin.',
    [
      ('Isaac Newton', 'Kütleçekim Yasası'), ('Marie Curie', 'Radyum ve Polonyum'), ('Alexander Fleming', 'Penisilin'),
      ('Charles Darwin', 'Doğal Seçilim'), ('Nikola Tesla', 'Alternatif Akım'), ('Galileo Galilei', 'Jüpiter’in Uyduları'),
      ('Louis Pasteur', 'Pastörizasyon'), ('Dmitri Mendeleyev', 'Periyodik Tablo'), ('Johannes Kepler', 'Gezegen Yasaları'),
      ('Gregor Mendel', 'Kalıtım Yasaları'), ('Alan Turing', 'Hesaplama Kuramı'), ('Aziz Sancar', 'DNA Onarımı'),
      ('Albert Einstein', 'Görelilik Kuramı'), ('James Watt', 'Buhar Makinesi'), ('Michael Faraday', 'Elektromanyetik İndüksiyon'),
      ('Ada Lovelace', 'İlk Bilgisayar Algoritması'),
    ],
  ),
  (
    'İngilizce Eş Anlamlılar',
    'Soldaki İngilizce kelimeleri sağdaki yakın eş anlamlılarıyla eşleştirin.',
    [
      ('accurate', 'precise'), ('adequate', 'sufficient'), ('ancient', 'historic'), ('brief', 'short'),
      ('cautious', 'careful'), ('commence', 'begin'), ('crucial', 'vital'), ('durable', 'sturdy'),
      ('enormous', 'huge'), ('essential', 'necessary'), ('fragile', 'delicate'), ('frequent', 'regular'),
      ('initial', 'first'), ('modify', 'alter'), ('obtain', 'acquire'), ('scarce', 'rare'),
    ],
  ),
  (
    'Türk & Dünya Edebiyatı',
    'Yazarları ünlü eserleriyle doğru biçimde eşleştirin.',
    [
      ('Yaşar Kemal', 'İnce Memed'), ('Sabahattin Ali', 'Kürk Mantolu Madonna'), ('Oğuz Atay', 'Tutunamayanlar'),
      ('Ahmet H. Tanpınar', 'Saatleri Ayarlama Enstitüsü'), ('Reşat N. Güntekin', 'Çalıkuşu'), ('Orhan Pamuk', 'Benim Adım Kırmızı'),
      ('Dostoyevski', 'Suç ve Ceza'), ('Victor Hugo', 'Sefiller'), ('Cervantes', 'Don Kişot'),
      ('George Orwell', '1984'), ('Tolstoy', 'Savaş ve Barış'), ('Franz Kafka', 'Dönüşüm'),
      ('Peyami Safa', 'Dokuzuncu Hariciye Koğuşu'), ('Sait Faik', 'Semaver'), ('Nazım Hikmet', 'Memleketimden İnsan Manzaraları'),
      ('Antoine de Saint-Exupéry', 'Küçük Prens'),
    ],
  ),
  (
    'Coğrafya ↔ Kıta / Bölge',
    'Dünyaca ünlü doğal oluşumları bulundukları bölgeyle eşleştirin.',
    [
      ('Amazon Nehri', 'Brezilya · Güney Amerika'), ('Nil Nehri', 'Kuzeydoğu Afrika · Mısır'), ('Himalayalar', 'Güney Asya · Nepal/Tibet'), ('Alpler', 'Orta Avrupa · İsviçre'),
      ('Büyük Set Resifi', 'Avustralya · Okyanusya'), ('Büyük Kanyon', 'ABD · Arizona'), ('Sahra Çölü', 'Kuzey Afrika'), ('Baykal Gölü', 'Sibirya · Rusya'),
      ('And Dağları', 'Güney Amerika Batısı'), ('Tuna Nehri', 'Orta ve Doğu Avrupa'), ('Fuji Dağı', 'Japonya · Honşu'), ('Kapadokya', 'İç Anadolu · Nevşehir'),
      ('Ağrı Dağı', 'Doğu Anadolu · Türkiye'), ('Kilimanjaro', 'Tanzanya · Doğu Afrika'), ('Niagara Şelalesi', 'ABD – Kanada Sınırı'), ('Gobi Çölü', 'Moğolistan · Orta Asya'),
    ],
  ),
  (
    'Bilişim Terimi ↔ Görev',
    'Teknoloji kavramlarını temel işlevleriyle eşleştirin.',
    [
      ('CPU', 'Komut işleme merkezi'), ('RAM', 'Geçici hızlı bellek'), ('SSD', 'Kalıcı flaş depolama'), ('GPU', 'Grafik ve paralel işlem'),
      ('HTTP', 'Web aktarım protokolü'), ('DNS', 'Alan adını IP’ye çevirme'), ('SQL', 'Veri tabanı sorgulama'), ('JSON', 'Hafif veri değişim biçimi'),
      ('Git', 'Sürüm kontrol sistemi'), ('API', 'Uygulama programlama arayüzü'), ('TLS / SSL', 'Şifreli iletişim katmanı'), ('HTML', 'Web sayfası işaretleme'),
      ('CSS', 'Görsel stil ve düzen'), ('APK', 'Android uygulama paketi'), ('UTF-8', 'Evrensel karakter kodlama'), ('VPN', 'Şifreli sanal özel ağ'),
    ],
  ),
  (
    'İnsan Vücudu ↔ İşlev',
    'Organ veya yapıları temel biyolojik görevleriyle eşleştirin.',
    [
      ('Kalp', 'Kanı damarlara pompalar'), ('Akciğer', 'Oksijen ve CO₂ gaz alışverişi'), ('Karaciğer', 'Zehirli maddeleri süzer, safra üretir'),
      ('Böbrek', 'Kanı süzerek idrar oluşturur'), ('Mide', 'Asit ve enzimle protein sindirimi'), ('Beyincik', 'Denge ve kas koordinasyonu'),
      ('Alyuvar', 'Hemoglobin ile oksijen taşır'), ('Akyuvar', 'Bağışıklık ve savunma sağlar'), ('Trombosit', 'Kanın pıhtılaşmasını sağlar'),
      ('Pankreas', 'İnsülin ve glukagon salgılar'), ('Retina', 'Gözde ışığı algılayan ağ tabaka'), ('Salyangoz (Koklea)', 'İç kulakta ses titreşimini algılar'),
      ('İnce Bağırsak', 'Besin emiliminin büyük kısmı'), ('Deri', 'Koruyucu örtü ve ısı dengesi'), ('Tiroit', 'Metabolizma hızını düzenler'),
      ('Omurilik', 'Refleks merkezi ve iletim yolu'),
    ],
  ),
];

List<T> _pickCombo4<T>(List<T> items, int index) {
  final n = items.length;
  final out = <T>[];
  var cursor = (index * 5 + 1) % n;
  var stride = 1 + ((index ~/ n) % (n - 1));
  while (_gcd(n, stride) != 1) {
    stride = (stride % (n - 1)) + 1;
  }
  while (out.length < 4) {
    final cand = items[cursor];
    if (!out.contains(cand)) out.add(cand);
    cursor = (cursor + stride) % n;
  }
  return out;
}

AdvancedItem _buildMatchingMega(int i) {
  final d = _megaMatchDomains[i % _megaMatchDomains.length];
  final k = i ~/ _megaMatchDomains.length;
  final pairs = _pickCombo4(d.$3, k);
  final p = _perm4[i % _perm4.length];
  final left = [for (final e in pairs) e.$1];
  final right = [for (final idx in p) pairs[idx].$2];
  final solution = [for (var j = 0; j < 4; j++) p.indexOf(j)];
  String seq(List<int> v) => v.map((n) => '${n + 1}').join(' – ');
  final wrongPerms = _perm4.where((z) => seq(z) != seq(solution)).take(3).map(seq).toList();
  return AdvancedItem(
    d.$2,
    seq(solution),
    wrongPerms,
    [for (final e in pairs) '${e.$1} → ${e.$2}'].join(' · '),
    activity: QuestionActivity(
      kind: ActivityKind.matching,
      title: 'Eşleştirme · ${d.$1}',
      left: left,
      right: right,
      solution: solution,
    ),
  );
}

// ===========================================================================
// 5. KRONOLOJİ, BİLİM & SAYI SIRALAMA (2.000 soru)
// ===========================================================================
const _historyEvents = <(int year, String label)>[
  (1071, 'Malazgirt Zaferi (1071)'),
  (1299, 'Osmanlı Beyliği’nin Kuruluşu (1299)'),
  (1453, 'İstanbul’un Fethi (1453)'),
  (1492, 'Amerika Kıtasına Ulaşılması (1492)'),
  (1517, 'Ridaniye Seferi (1517)'),
  (1687, 'Newton’un Principia Eseri (1687)'),
  (1789, 'Fransız İhtilali (1789)'),
  (1839, 'Tanzimat Fermanı (1839)'),
  (1876, 'Telefonun Patenti (1876)'),
  (1896, 'İlk Modern Olimpiyatlar (1896)'),
  (1903, 'Wright Kardeşlerin İlk Uçuşu (1903)'),
  (1915, 'Çanakkale Zaferi (1915)'),
  (1920, 'TBMM’nin Açılışı (1920)'),
  (1923, 'Cumhuriyetin İlanı (1923)'),
  (1928, 'Harf İnkılabı (1928)'),
  (1953, 'DNA Çift Sarmalının Keşfi (1953)'),
  (1957, 'Sputnik 1’in Fırlatılması (1957)'),
  (1969, 'Apollo 11 Ay’a İniş (1969)'),
  (1989, 'World Wide Web Tasarımı (1989)'),
  (2015, 'Aziz Sancar’ın Nobel Ödülü (2015)'),
];

const _orderedChains = <(String title, String prompt, List<String> asc)>[
  ('Güneş’e Yakınlık Sırası', 'Gezegenleri Güneş’e EN YAKINDAN EN UZAĞA doğru sıralayın.', ['Merkür', 'Venüs', 'Dünya', 'Mars', 'Jüpiter', 'Satürn', 'Uranüs', 'Neptün']),
  ('Metrik Uzunluk Birimleri', 'Uzunluk birimlerini EN KÜÇÜKTEN EN BÜYÜĞE doğru sıralayın.', ['Nanometre', 'Mikrometre', 'Milimetre', 'Santimetre', 'Desimetre', 'Metre', 'Kilometre']),
  ('Biyolojik Organizasyon', 'Canlılık basamaklarını EN BASİTTEN EN KARMAŞIĞA doğru sıralayın.', ['Atom', 'Molekül', 'Organel', 'Hücre', 'Doku', 'Organ', 'Sistem', 'Organizma']),
  ('Atmosfer Katmanları', 'Atmosfer katmanlarını YERYÜZÜNDEN UZAYA doğru sıralayın.', ['Troposfer', 'Stratosfer', 'Mezosfer', 'Termosfer', 'Ekzosfer']),
  ('Elektromanyetik Spektrum', 'Dalga türlerini EN UZUN DALGA BOYUNDAN EN KISAYA sıralayın.', ['Radyo Dalgaları', 'Mikrodalga', 'Kızılötesi', 'Görünür Işık', 'Morötesi', 'X-Işınları', 'Gama Işınları']),
  ('Dijital Veri Birimleri', 'Veri depolama birimlerini EN KÜÇÜKTEN EN BÜYÜĞE doğru sıralayın.', ['Bit', 'Bayt', 'Kilobayt', 'Megabayt', 'Gigabayt', 'Terabayt', 'Petabayt']),
  ('Element Atom Numaraları', 'Elementleri atom numarasına (Z) göre KÜÇÜKTEN BÜYÜĞE sıralayın.', ['Hidrojen (1)', 'Helyum (2)', 'Lityum (3)', 'Karbon (6)', 'Azot (7)', 'Oksijen (8)', 'Neon (10)', 'Sodyum (11)', 'Demir (26)', 'Altın (79)']),
  ('Görünür Işık Renkleri', 'Gökkuşağı renklerini KIRMIZIDAN MORA (uzun dalgadan kısaya) sıralayın.', ['Kırmızı', 'Turuncu', 'Sarı', 'Yeşil', 'Mavi', 'Lacivert', 'Mor']),
];

AdvancedItem _buildOrderingFact(int i) {
  final mode = i % 3;
  final k = i ~/ 3;
  late final String title, prompt;
  late final List<String> ordered;

  if (mode == 0) {
    // Chronological 4 historical events (years stripped from labels so user relies on history!)
    final picked = _pickCombo4(_historyEvents, k)..sort((a, b) => a.$1.compareTo(b.$1));
    title = 'Kronoloji Sıralama';
    prompt = 'Tarihsel olayları ESKİDEN YENİYE (kronolojik) doğru sıralayın.';
    ordered = [for (final e in picked) e.$2.split(' (').first];
  } else if (mode == 1) {
    final chain = _orderedChains[k % _orderedChains.length];
    final n = chain.$3.length;
    final indices = _pickCombo4(List.generate(n, (x) => x), k ~/ _orderedChains.length)..sort();
    title = chain.$1;
    prompt = chain.$2;
    ordered = [for (final idx in indices) chain.$3[idx]];
  } else {
    // Parametric math expressions ordered smallest to largest
    final a = 2 + (k % 9);
    final b = 3 + ((k ~/ 9) % 8);
    final exprs = <(int val, String text)>[
      (a + b, '$a + $b'),
      (a * b, '$a × $b'),
      (a * a + b, '$a² + $b'),
      (b * b + a * 2, '$b² + ${2 * a}'),
      ((a + b) * 3, '3 × ($a + $b)'),
      (a * b + 12, '$a × $b + 12'),
    ];
    // Pick 4 with strictly distinct values
    final unique = <(int, String)>[];
    final seenV = <int>{};
    for (final e in exprs) {
      if (seenV.add(e.$1)) unique.add(e);
    }
    final chosen = unique.take(4).toList()..sort((x, y) => x.$1.compareTo(y.$1));
    title = 'Sayısal Değer Sıralama';
    prompt = 'Matematiksel ifadeleri değerine göre KÜÇÜKTEN BÜYÜĞE doğru sıralayın.';
    ordered = [for (final c in chosen) c.$2];
  }

  final p = _perm4[i % _perm4.length];
  final scrambled = [for (final idx in p) ordered[idx]];
  final solution = [for (var j = 0; j < 4; j++) p.indexOf(j)];
  String seq(List<int> v) => v.map((n) => '${n + 1}').join(' → ');
  final wrongPerms = _perm4.where((z) => seq(z) != seq(solution)).take(3).map(seq).toList();
  return AdvancedItem(
    prompt,
    seq(solution),
    wrongPerms,
    'Doğru sıra: ${ordered.join(' → ')}.',
    activity: QuestionActivity(
      kind: ActivityKind.ordering,
      title: title,
      items: scrambled,
      solution: solution,
    ),
  );
}

// ===========================================================================
// 6. İNGİLİZCE CÜMLE KURMA / WORD ORDER (1.500 soru · Topic.language)
// ===========================================================================
const _woSubjects = [
  'The scientist', 'My sister', 'Our team', 'The musician', 'An architect',
  'The traveler', 'Our teacher', 'The engineer', 'A photographer', 'The student',
];
const _woVerbs = [
  'reviewed the chart', 'played a melody', 'built a circuit', 'read an article',
  'solved the puzzle', 'painted a sunset', 'checked the compass', 'recorded the audio',
  'visited the gallery', 'studied the stars',
];
const _woPlaces = [
  'in the quiet library', 'near the harbor', 'at the science lab',
  'inside the studio', 'beside the river',
];
const _woTimes = [
  'yesterday afternoon.', 'before sunset.', 'every weekend.',
];

AdvancedItem _buildOrderingEn(int i) {
  final s = _woSubjects[i % _woSubjects.length];
  final v = _woVerbs[(i ~/ _woSubjects.length) % _woVerbs.length];
  final pl = _woPlaces[(i ~/ 100) % _woPlaces.length];
  final tm = _woTimes[(i ~/ 500) % _woTimes.length];
  final ordered = [s, v, pl, tm];
  final p = _perm4[i % _perm4.length];
  final scrambled = [for (final idx in p) ordered[idx]];
  final solution = [for (var j = 0; j < 4; j++) p.indexOf(j)];
  final fullSentence = ordered.join(' ');
  String seq(List<int> v) => v.map((n) => '${n + 1}').join(' → ');
  final wrongPerms = _perm4.where((z) => seq(z) != seq(solution)).take(3).map(seq).toList();
  return AdvancedItem(
    'Karışık İngilizce parçaları doğru dil bilgisi sırasına (Özne → Fiil → Yer → Zaman) dizerek anlamlı cümleyi kurun.',
    seq(solution),
    wrongPerms,
    'Doğru İngilizce cümle: "$fullSentence"',
    activity: QuestionActivity(
      kind: ActivityKind.ordering,
      title: 'English Word Order Studio',
      language: _accents[i % 3],
      transcript: fullSentence,
      items: scrambled,
      solution: solution,
    ),
  );
}

// ===========================================================================
// 7. ÇOKLU SEÇİM (MultiSelectTask · 2.500 soru)
// ===========================================================================
const _multiCurated = <(String prompt, List<String> opts, List<int> corr, String exp)>[
  ('Aşağıdakilerden hangileri SOYGAZ (8A grubu) elementleridir?', ['Helyum (He)', 'Neon (Ne)', 'Azot (N)', 'Argon (Ar)'], [0, 1, 3], 'Helyum, Neon ve Argon 8A soygazlarıdır; Azot 5A ametalidir.'),
  ('Aşağıdakilerden hangileri YENİLENEBİLİR enerji kaynaklarıdır?', ['Güneş enerjisi', 'Kömür', 'Rüzgâr enerjisi', 'Jeotermal enerji'], [0, 2, 3], 'Güneş, rüzgâr ve jeotermal yenilenebilir; kömür fosil yakıttır.'),
  ('Aşağıdakilerden hangileri VEKTÖREL büyüklüklerdir (yön taşır)?', ['Hız', 'Kütle', 'Kuvvet', 'İvme'], [0, 2, 3], 'Hız, kuvvet ve ivme vektörel; kütle skaler büyüklüktür.'),
  ('Aşağıdakilerden hangileri İÇ GEZEGEN (karasal gezegen) grubundadır?', ['Merkür', 'Venüs', 'Jüpiter', 'Mars'], [0, 1, 3], 'Merkür, Venüs, Dünya ve Mars karasal; Jüpiter gaz devidir.'),
  ('Aşağıdakilerden hangileri DÜZENSİZ (irregular) İngilizce fiillerdir?', ['go (went)', 'walk (walked)', 'write (wrote)', 'speak (spoke)'], [0, 2, 3], 'go, write ve speak düzensiz; walk düzenli (-ed) fiildir.'),
  ('Aşağıdakilerden hangileri AVRUPA kıtasında bulunan başkentlerdir?', ['Viyana', 'Lizbon', 'Ottawa', 'Prag'], [0, 1, 3], 'Viyana, Lizbon ve Prag Avrupa; Ottawa Kuzey Amerika (Kanada) başkentidir.'),
  ('Aşağıdakilerden hangileri ASAL sayılardır?', ['17', '21', '29', '37'], [0, 2, 3], '17, 29 ve 37 yalnızca 1’e ve kendisine bölünür; 21 = 3 × 7 asal değildir.'),
  ('Aşağıdakilerden hangileri MEMELİ hayvanlardır?', ['Yunus', 'Yarasa', 'Penguen', 'Balina'], [0, 1, 3], 'Yunus, yarasa ve balina memelidir; penguen bir kuştur.'),
  ('Aşağıdakilerden hangileri TÜRKİYE’NİN UNESCO Dünya Mirası alanlarındandır?', ['Göbeklitepe', 'Efes', 'Pamukkale', 'Kolezyum'], [0, 1, 2], 'Göbeklitepe, Efes ve Pamukkale Türkiye’dedir; Kolezyum İtalya’dadır.'),
  ('Aşağıdakilerden hangileri IŞIĞIN ANA RENKLERİ (RGB) arasındadır?', ['Kırmızı', 'Yeşil', 'Sarı', 'Mavi'], [0, 1, 3], 'RGB toplamsal ışık sisteminin üç ana rengi Kırmızı, Yeşil ve Mavi’dir.'),
  ('Aşağıdakilerden hangileri OKTAV içinde SİYAH TUŞ olarak yer alır?', ['Do♯ (C♯)', 'Mi (E)', 'Fa♯ (F♯)', 'Si♭ (B♭)'], [0, 2, 3], 'Do♯, Fa♯ ve Si♭ siyah tuş; Mi doğal beyaz tuştur.'),
  ('Aşağıdakilerden hangileri PROGRAMLAMA dilleridir?', ['Dart', 'Python', 'HTML', 'Rust'], [0, 1, 3], 'Dart, Python ve Rust programlama dilidir; HTML işaretleme dilidir.'),
];

bool _isPrime(int n) {
  if (n < 2) return false;
  for (var d = 2; d * d <= n; d++) {
    if (n % d == 0) return false;
  }
  return true;
}

MultiSelectTask _buildMultiTask(AdvancedItem _, int i) {
  final mode = i % 5;
  final k = i ~/ 5;
  if (mode == 0) {
    final c = _multiCurated[k % _multiCurated.length];
    final rot = (k ~/ _multiCurated.length) % 4;
    final opts = [for (var j = 0; j < 4; j++) c.$2[(j + rot) % 4]];
    final corr = [
      for (var j = 0; j < 4; j++)
        if (c.$3.contains((j + rot) % 4)) j,
    ];
    return MultiSelectTask(c.$1, opts, corr, c.$4);
  } else if (mode == 1) {
    // Multiples of divisor d (2 or 3 correct)
    final d = 3 + (k % 7); // 3..9
    final base = 2 + (k % 12);
    final good1 = d * base;
    final good2 = d * (base + 2);
    final bad1 = d * (base + 1) + 1;
    final bad2 = d * (base + 3) + 2;
    final raw = [(good1, true), (bad1, false), (good2, true), (bad2, false)];
    final rot = k % 4;
    final opts = [for (var j = 0; j < 4; j++) '${raw[(j + rot) % 4].$1}'];
    final corr = [for (var j = 0; j < 4; j++) if (raw[(j + rot) % 4].$2) j];
    return MultiSelectTask(
      'Aşağıdaki sayılardan $d ile KALANSIZ bölünebilen TÜM seçenekleri işaretleyin.',
      opts,
      corr,
      '$good1 ve $good2 sayıları $d ile tam bölünür; $bad1 ve $bad2 tam bölünmez.',
    );
  } else if (mode == 2) {
    // Prime numbers selection
    final primes = [for (var n = 11; n < 150; n++) if (_isPrime(n)) n];
    final composites = [for (var n = 12; n < 150; n++) if (!_isPrime(n) && n.isOdd) n];
    final p1 = primes[k % primes.length];
    final p2 = primes[(k + 5) % primes.length];
    final c1 = composites[k % composites.length];
    final c2 = composites[(k + 7) % composites.length];
    final raw = [(p1, true), (c1, false), (p2, true), (c2, false)];
    final rot = k % 4;
    final opts = [for (var j = 0; j < 4; j++) '${raw[(j + rot) % 4].$1}'];
    final corr = [for (var j = 0; j < 4; j++) if (raw[(j + rot) % 4].$2) j];
    return MultiSelectTask(
      'Aşağıdaki sayılardan ASAL SAYI olanların tamamını işaretleyin.',
      opts,
      corr,
      '$p1 ve $p2 asal sayılardır; $c1 ve $c2 bileşik sayılardır.',
    );
  } else if (mode == 3) {
    // Perfect squares selection
    final a = 3 + (k % 15);
    final b = a + 2;
    final sq1 = a * a;
    final sq2 = b * b;
    final non1 = sq1 + 3;
    final non2 = sq2 - 2;
    final raw = [(sq1, true), (non1, false), (sq2, true), (non2, false)];
    final rot = k % 4;
    final opts = [for (var j = 0; j < 4; j++) '${raw[(j + rot) % 4].$1}'];
    final corr = [for (var j = 0; j < 4; j++) if (raw[(j + rot) % 4].$2) j];
    return MultiSelectTask(
      'Aşağıdaki sayılardan TAM KARE (bir tam sayının karesi) olanların tamamını seçin.',
      opts,
      corr,
      '$sq1 = $a² ve $sq2 = $b² tam kare sayılardır.',
    );
  } else {
    // Angles that are obtuse (90° < x < 180°)
    final o1 = 95 + (k % 40);
    final o2 = 136 + ((k * 3) % 40);
    final ac1 = 15 + (k % 35);
    final ac2 = 52 + ((k * 5) % 34);
    final raw = [('$o1°', true), ('$ac1°', false), ('$o2°', true), ('$ac2°', false)];
    final rot = k % 4;
    final opts = [for (var j = 0; j < 4; j++) raw[(j + rot) % 4].$1];
    final corr = [for (var j = 0; j < 4; j++) if (raw[(j + rot) % 4].$2) j];
    return MultiSelectTask(
      'Aşağıdaki açılardan GENİŞ AÇI (90° ile 180° arası) olanların tamamını işaretleyin.',
      opts,
      corr,
      '$o1° ve $o2° geniş açılardır (90° < açı < 180°); diğerleri dar açıdır.',
    );
  }
}

AdvancedItem _buildMultiBase(int i) => const AdvancedItem(
      'Çoklu seçim',
      'A',
      ['B', 'C', 'D'],
      'Doğru seçeneklerin tamamını işaretleyin.',
    );

// ===========================================================================
// 8. HIZLI DOĞRU / YANLIŞ STÜDYOSU (2.500 soru)
// ===========================================================================
const _tfCurated = <(String stmt, bool isTrue, String exp)>[
  ('“She has lived in Izmir since 2021.” cümlesi İngilizce dil bilgisine göre doğrudur.', true, 'Belirli bir başlangıç yılı ile Present Perfect + since kullanımı doğrudur.'),
  ('“He don’t like drinking cold tea.” cümlesi İngilizce dil bilgisine göre doğrudur.', false, '3. tekil şahısta “doesn’t” kullanılmalıdır: “He doesn’t like...”.'),
  ('“If it rains tomorrow, we will stay inside.” cümlesi Type 1 koşul cümlesi olarak doğrudur.', true, 'If + Present Simple, will + V1 yapısı doğru Type 1 koşuldur.'),
  ('“I look forward to meet you next week.” cümlesi İngilizce dil bilgisine göre doğrudur.', false, '“look forward to” edatından sonra fiil -ing alır: “meeting”.'),
  ('“There are fewer cars on the bridge tonight.” cümlesi doğrudur.', true, 'Sayılabilen çoğul isimlerle (cars) “fewer” kullanımı doğrudur.'),
  ('“She is interested on modern astronomy.” cümlesi edat kullanımı açısından doğrudur.', false, 'Doğru edat “in”dir: “interested in”.'),
  ('Ses dalgaları uzay boşluğunda ışıktan daha hızlı yayılır.', false, 'Ses mekanik dalgadır ve boşlukta hiç yayılmaz.'),
  ('Saf su 1 atmosfer basınç altında 0 °C’de donar ve 100 °C’de kaynar.', true, 'Standart basınçta suyun donma noktası 0 °C, kaynama noktası 100 °C’dir.'),
  ('Fotosentez yapan yeşil bitkiler gündüz atmosferden karbondioksit alıp oksijen üretir.', true, 'Fotosentez CO₂ + H₂O → glikoz + O₂ dönüşümüdür.'),
  ('Periyodik tabloda aynı grupta yer alan elementlerin atom numaraları aynıdır.', false, 'Her elementin atom numarası benzersizdir; aynı gruptakiler benzer değerlik elektronuna sahiptir.'),
  ('Seri bağlı dirençlerde eşdeğer direnç, devredeki en büyük tekil dirençten büyüktür.', true, 'R_eş = R₁ + R₂ + ... olduğundan her zaman tekil dirençlerden büyüktür.'),
  ('Paralel bağlı iki pozitif direncin eşdeğer direnci, küçük olan dirençten bile küçüktür.', true, '1/R_eş = 1/R₁ + 1/R₂ olduğu için R_eş < min(R₁, R₂).'),
  ('İki çift sayının toplamı her zaman tek sayıdır.', false, 'İki çift sayının toplamı her zaman çift sayıdır.'),
  ('Bir üçgenin dış açıları toplamı her zaman 360 derecedir.', true, 'Tüm dışbükey çokgenlerde dış açılar toplamı 360°’dir.'),
  ('2 sayısı tek çift asal sayıdır.', true, '2’den büyük tüm çift sayılar 2’ye bölündüğü için asal değildir.'),
  ('Ekvator üzerinde gece ve gündüz süresi yıl boyunca neredeyse eşittir.', true, 'Ekvator’da yıl boyu yaklaşık 12 saat gündüz ve 12 saat gece yaşanır.'),
  ('Avustralya hem bir ülke hem de bir kıta adıdır.', true, 'Avustralya kıta ölçeğinde tek bir ülkedir.'),
  ('Müzikte bir tam oktav 10 yarım sesten oluşur.', false, 'Bir tam oktav tam olarak 12 yarım sesten (semitone) oluşur.'),
  ('İkili (binary) sistemde 1010₂ sayısı onluk sistemde 10 değerine eşittir.', true, '8 + 0 + 2 + 0 = 10.'),
  ('XOR mantık kapısı yalnızca iki giriş birbirinden FARKLI olduğunda 1 çıkışı verir.', true, 'XOR(1,0)=1, XOR(0,1)=1; XOR(0,0)=0, XOR(1,1)=0.'),
];

AdvancedItem _buildTrueFalseMega(int i) {
  final mode = i % 4;
  final k = i ~/ 4;
  late final String stmt, exp;
  late final bool isTrue;

  if (mode == 0) {
    final c = _tfCurated[k % _tfCurated.length];
    stmt = c.$1;
    isTrue = c.$2;
    exp = c.$3;
  } else if (mode == 1) {
    // Divisibility truth check
    final d = 3 + (k % 9);
    final q = 4 + (k % 25);
    isTrue = k.isEven;
    final num = isTrue ? d * q : d * q + (1 + (k % (d - 1)));
    stmt = '$num sayısı $d ile kalansız (tam) bölünebilir.';
    exp = isTrue
        ? 'Doğru: $num = $d × $q olduğundan kalan 0’dır.'
        : 'Yanlış: $num sayısı $d ile bölündüğünde kalan ${num % d} olur.';
  } else if (mode == 2) {
    // Multiplication / square check
    final a = 6 + (k % 19);
    final b = 4 + ((k ~/ 19) % 14);
    final real = a * b;
    isTrue = k.isOdd;
    final shown = isTrue ? real : real + ((k % 2 == 0) ? 4 : -3);
    stmt = '$a × $b işleminin sonucu $shown eşittir.';
    exp = isTrue ? 'Doğru: $a × $b = $real.' : 'Yanlış: $a × $b = $real ($shown değil).';
  } else {
    // Binary to decimal truth check (4..63)
    final val = 5 + (k % 58);
    final bin = val.toRadixString(2);
    isTrue = (k % 3) != 0;
    final shown = isTrue ? val : val + ((k.isEven) ? 2 : -1);
    stmt = 'İkili (binary) sayı sistemindeki $bin₂ sayısı onluk sistemde $shown değerine karşılık gelir.';
    exp = isTrue ? 'Doğru: $bin₂ = $val.' : 'Yanlış: $bin₂ = $val ($shown değil).';
  }

  return AdvancedItem(
    'Aşağıdaki önerme Doğru mu, Yanlış mı?\n\n“$stmt”',
    isTrue ? 'Doğru' : 'Yanlış',
    [isTrue ? 'Yanlış' : 'Doğru'],
    exp,
  );
}

// ===========================================================================
// 9. KISA YANIT & BOŞLUK DOLDURMA STÜDYOSU (2.000 soru)
// ===========================================================================
const _irregVerbs = <(String v1, String v2, String v3, String tr)>[
  ('go', 'went', 'gone', 'gitmek'),
  ('write', 'wrote', 'written', 'yazmak'),
  ('speak', 'spoke', 'spoken', 'konuşmak'),
  ('take', 'took', 'taken', 'almak'),
  ('give', 'gave', 'given', 'vermek'),
  ('break', 'broke', 'broken', 'kırmak'),
  ('choose', 'chose', 'chosen', 'seçmek'),
  ('drive', 'drove', 'driven', 'sürmek'),
  ('eat', 'ate', 'eaten', 'yemek'),
  ('fall', 'fell', 'fallen', 'düşmek'),
  ('fly', 'flew', 'flown', 'uçmak'),
  ('forget', 'forgot', 'forgotten', 'unutmak'),
  ('know', 'knew', 'known', 'bilmek'),
  ('see', 'saw', 'seen', 'görmek'),
  ('begin', 'began', 'begun', 'başlamak'),
  ('drink', 'drank', 'drunk', 'içmek'),
  ('sing', 'sang', 'sung', 'şarkı söylemek'),
  ('swim', 'swam', 'swum', 'yüzmek'),
  ('throw', 'threw', 'thrown', 'fırlatmak'),
  ('grow', 'grew', 'grown', 'büyümek'),
  ('draw', 'drew', 'drawn', 'çizmek'),
  ('wear', 'wore', 'worn', 'giymek'),
  ('bring', 'brought', 'brought', 'getirmek'),
  ('buy', 'bought', 'bought', 'satın almak'),
  ('catch', 'caught', 'caught', 'yakalamak'),
  ('teach', 'taught', 'taught', 'öğretmek'),
  ('think', 'thought', 'thought', 'düşünmek'),
  ('build', 'built', 'built', 'inşa etmek'),
  ('send', 'sent', 'sent', 'göndermek'),
  ('spend', 'spent', 'spent', 'harcamak'),
];

const _enPreps = <(String sent, String prep, String exp)>[
  ('She is very interested ___ astronomy.', 'in', '“interested in” kalıbı kullanılır.'),
  ('He is really good ___ playing chess.', 'at', 'Yetenek bildirirken “good at” kullanılır.'),
  ('We are proud ___ our school robotics team.', 'of', '“proud of” (gurur duymak) kalıbı kullanılır.'),
  ('This museum is famous ___ its ancient mosaics.', 'for', '“famous for” (ile ünlü) kalıbı kullanılır.'),
  ('Please listen ___ the English recording carefully.', 'to', '“listen to” edatı ile kullanılır.'),
  ('The final exam depends ___ consistent daily practice.', 'on', '“depend on” (bağlı olmak) kalıbı kullanılır.'),
  ('My schedule is quite different ___ yours.', 'from', '“different from” (farklı) kalıbı kullanılır.'),
  ('Don’t worry ___ making small mistakes.', 'about', '“worry about” (endişelenmek) kalıbı kullanılır.'),
  ('The harbor train arrives ___ noon.', 'at', 'Belirli saat/öğle vakti için “at noon” kullanılır.'),
  ('Our science festival starts ___ Monday.', 'on', 'Haftanın günleri önünde “on” kullanılır.'),
  ('Tulips bloom across Istanbul ___ April.', 'in', 'Aylar ve mevsimler önünde “in” kullanılır.'),
  ('Thank you ___ sharing your detailed notes.', 'for', '“thank someone for” kalıbı kullanılır.'),
  ('He apologized ___ arriving five minutes late.', 'for', '“apologize for” kalıbı kullanılır.'),
  ('This melody reminds me ___ summer evenings.', 'of', '“remind someone of” kalıbı kullanılır.'),
  ('She succeeded ___ solving the logic circuit.', 'in', '“succeed in” kalıbı kullanılır.'),
];

AdvancedItem _buildFillMega(int i) {
  final mode = i % 4; // 4 × 500 = 2.000
  final k = i ~/ 4;
  if (mode == 0) {
    // English irregular verb V2 / V3
    final v = _irregVerbs[k % _irregVerbs.length];
    final askV3 = (k ~/ _irregVerbs.length).isOdd;
    final ans = askV3 ? v.$3 : v.$2;
    return AdvancedItem(
      askV3
          ? 'İngilizce "${v.$1}" (${v.$4}) fiilinin 3. hâlini (Past Participle / V3) yazın: "She has ____ ..."'
          : 'İngilizce "${v.$1}" (${v.$4}) fiilinin geçmiş zaman (Past Simple / V2) hâlini yazın: "Yesterday he ____ ..."',
      ans,
      _pickDistinct([for (final x in _irregVerbs) askV3 ? x.$3 : x.$2], ans, i + 3),
      '"${v.$1}" fiilinin çekimi: ${v.$1} – ${v.$2} – ${v.$3}.',
    );
  } else if (mode == 1) {
    // English preposition fill
    final p = _enPreps[k % _enPreps.length];
    return AdvancedItem(
      'İngilizce cümledeki boşluğa uygun tek kelimelik edatı (preposition) yazın:\n"${p.$1}"',
      p.$2,
      _pickDistinct(const ['in', 'on', 'at', 'of', 'for', 'to', 'from', 'about', 'with', 'by'], p.$2, i + 5),
      p.$3,
    );
  } else if (mode == 2) {
    // Linear equation ax + b = c => x = ?
    final a = 2 + (k % 8);
    final x = 2 + ((k ~/ 8) % 24);
    final b = 3 + ((k * 5) % 25);
    final c = a * x + b;
    return AdvancedItem(
      '${a}x + $b = $c denkleminde x sayısının tam sayı değeri kaçtır?',
      '$x',
      _intWrong(x, i, minVal: 1),
      '${a}x = $c − $b = ${c - b} ⇒ x = ${c - b} / $a = $x.',
    );
  } else {
    // Binary -> decimal exact integer conversion
    final val = 6 + (k % 120);
    final bin = val.toRadixString(2);
    return AdvancedItem(
      'İkili (binary) sayı sisteminde $bin₂ olarak yazılan sayının onluk (decimal) değerini yazın.',
      '$val',
      _intWrong(val, i, minVal: 1),
      '$bin₂ ikili sayısının basamak değerleri toplamı $val eder.',
    );
  }
}

final List<AdvancedFamily> interactiveStudio25kFamilies = [
  AdvancedFamily(
    key: 's100_slider_est',
    title: '3D Tahmin Sürgüsü · Tarih, Bilim, Açı & Ölçüm',
    topic: Topic.science,
    level: StudyLevel.lise,
    count: 4500,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.slider,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.21 · Etkileşimli Stüdyo 25K',
    build: _buildSliderEst,
  ),
  AdvancedFamily(
    key: 's100_anagram_en',
    title: '3D Sesli İngilizce Harf Dizme (Anagram)',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 3500,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.anagram,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.21 · Etkileşimli Stüdyo 25K',
    build: _buildAnagramEn,
  ),
  AdvancedFamily(
    key: 's100_anagram_tr',
    title: '3D Türkçe Kültür & Bilim Harf Dizme',
    topic: Topic.culture,
    level: StudyLevel.lise,
    count: 2500,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.anagram,
    bloom: BloomLevel.hatirlama,
    sourceLabel: 'Bilgili 3.21 · Etkileşimli Stüdyo 25K',
    build: _buildAnagramTr,
  ),
  AdvancedFamily(
    key: 's100_matching_mega',
    title: '10 Alanlı Mega Çift Eşleştirme Atölyesi',
    topic: Topic.culture,
    level: StudyLevel.lise,
    count: 4000,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.matching,
    bloom: BloomLevel.anlama,
    sourceLabel: 'Bilgili 3.21 · Etkileşimli Stüdyo 25K',
    build: _buildMatchingMega,
  ),
  AdvancedFamily(
    key: 's100_ordering_fact',
    title: 'Kronoloji, Gezegen & Bilim Sıralama Atölyesi',
    topic: Topic.history,
    level: StudyLevel.lise,
    count: 2000,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.ordering,
    bloom: BloomLevel.analiz,
    sourceLabel: 'Bilgili 3.21 · Etkileşimli Stüdyo 25K',
    build: _buildOrderingFact,
  ),
  AdvancedFamily(
    key: 's100_ordering_en',
    title: 'İngilizce Cümle Kurma (Word Order · Sesli)',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 1500,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.ordering,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.21 · Etkileşimli Stüdyo 25K',
    build: _buildOrderingEn,
  ),
  AdvancedFamily(
    key: 's100_multiselect_mega',
    title: 'Çoklu Seçim & Eleme Laboratuvarı',
    topic: Topic.science,
    level: StudyLevel.lise,
    count: 2500,
    difficulty: Difficulty.hard,
    bloom: BloomLevel.analiz,
    multiSelect: _buildMultiTask,
    sourceLabel: 'Bilgili 3.21 · Etkileşimli Stüdyo 25K',
    build: _buildMultiBase,
  ),
  AdvancedFamily(
    key: 's100_truefalse_mega',
    title: 'Hızlı Doğru / Yanlış · Bilim, Matematik & İngilizce',
    topic: Topic.culture,
    level: StudyLevel.lise,
    count: 2500,
    difficulty: Difficulty.easy,
    fixedResponseType: ResponseType.trueFalse,
    bloom: BloomLevel.degerlendirme,
    sourceLabel: 'Bilgili 3.21 · Etkileşimli Stüdyo 25K',
    build: _buildTrueFalseMega,
  ),
  AdvancedFamily(
    key: 's100_fill_mega',
    title: 'Kısa Yanıt · İngilizce Fiiller, Edatlar, İkili & Denklem',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 2000,
    difficulty: Difficulty.medium,
    fixedResponseType: ResponseType.fill,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.21 · Etkileşimli Stüdyo 25K',
    build: _buildFillMega,
  ),
];
