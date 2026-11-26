import 'dart:math';
import '../common.dart';

// ---------------------------------------------------------------------------
// 1. DÜNYA BAYRAKLARI GÖRSEL ATLASI (64 Ülke × 10 soru = 640 soru)
// ---------------------------------------------------------------------------
typedef _CountryInfo = ({
  String code,
  String name,
  String capital,
  String continent,
  String currency,
  String lang,
  String landmark,
  String colors,
  String region,
});

const _countries = <_CountryInfo>[
  (code: 'TR', name: 'Türkiye', capital: 'Ankara', continent: 'Asya ve Avrupa', currency: 'Türk Lirası', lang: 'Türkçe', landmark: 'Ayasofya ve Kapadokya', colors: 'Kırmızı zemin üzerinde beyaz ay-yıldız', region: 'Anadolu ve Doğu Akdeniz'),
  (code: 'JP', name: 'Japonya', capital: 'Tokyo', continent: 'Asya', currency: 'Japon Yeni', lang: 'Japonca', landmark: 'Fuji Dağı', colors: 'Beyaz zemin üzerinde kırmızı güneş diski', region: 'Doğu Asya ada ülkesi'),
  (code: 'BD', name: 'Bangladeş', capital: 'Dakka', continent: 'Asya', currency: 'Taka', lang: 'Bengalce', landmark: 'Sundarbans Mangrov Ormanı', colors: 'Koyu yeşil zemin üzerinde kırmızı daire', region: 'Güney Asya Bengal Körfezi kıyısı'),
  (code: 'FR', name: 'Fransa', capital: 'Paris', continent: 'Avrupa', currency: 'Euro', lang: 'Fransızca', landmark: 'Eyfel Kulesi', colors: 'Mavi, beyaz ve kırmızı dikey üç şerit', region: 'Batı Avrupa'),
  (code: 'IT', name: 'İtalya', capital: 'Roma', continent: 'Avrupa', currency: 'Euro', lang: 'İtalyanca', landmark: 'Kolezyum', colors: 'Yeşil, beyaz ve kırmızı dikey üç şerit', region: 'Güney Avrupa Akdeniz yarımadası'),
  (code: 'IE', name: 'İrlanda', capital: 'Dublin', continent: 'Avrupa', currency: 'Euro', lang: 'İngilizce ve İrlandaca', landmark: 'Moher Kayalıkları', colors: 'Yeşil, beyaz ve turuncu dikey üç şerit', region: 'Kuzeybatı Avrupa ada ülkesi'),
  (code: 'BE', name: 'Belçika', capital: 'Brüksel', continent: 'Avrupa', currency: 'Euro', lang: 'Felemenkçe ve Fransızca', landmark: 'Atomium ve Grand-Place', colors: 'Siyah, sarı ve kırmızı dikey üç şerit', region: 'Batı Avrupa Benelüks bölgesi'),
  (code: 'RO', name: 'Romanya', capital: 'Bükreş', continent: 'Avrupa', currency: 'Rumen Leyi', lang: 'Rumence', landmark: 'Bran Şatosu ve Karpatlar', colors: 'Lacivert, sarı ve kırmızı dikey üç şerit', region: 'Güneydoğu Avrupa Karadeniz kıyısı'),
  (code: 'NG', name: 'Nijerya', capital: 'Abuja', continent: 'Afrika', currency: 'Naira', lang: 'İngilizce', landmark: 'Zuma Kayası ve Lagos lagünü', colors: 'Yeşil, beyaz ve yeşil dikey üç şerit', region: 'Batı Afrika Gine Körfezi kıyısı'),
  (code: 'PE', name: 'Peru', capital: 'Lima', continent: 'Güney Amerika', currency: 'Sol', lang: 'İspanyolca', landmark: 'Machu Picchu Antik Kenti', colors: 'Kırmızı, beyaz ve kırmızı dikey üç şerit', region: 'And Dağları Pasifik kıyısı'),
  (code: 'MX', name: 'Meksika', capital: 'Meksiko', continent: 'Kuzey Amerika', currency: 'Meksika Pesosu', lang: 'İspanyolca', landmark: 'Chichén Itzá Piramidi', colors: 'Yeşil, beyaz, kırmızı dikey şeritler ve orta arma', region: 'Kuzey Amerika güney kuşağı'),
  (code: 'CA', name: 'Kanada', capital: 'Ottawa', continent: 'Kuzey Amerika', currency: 'Kanada Doları', lang: 'İngilizce ve Fransızca', landmark: 'Niagara Şelalesi ve Banff', colors: 'Kırmızı-beyaz-kırmızı şeritler ve akçaağaç yaprağı', region: 'Kuzey Amerika kuzey kuşağı'),
  (code: 'DE', name: 'Almanya', capital: 'Berlin', continent: 'Avrupa', currency: 'Euro', lang: 'Almanca', landmark: 'Brandenburg Kapısı', colors: 'Siyah, kırmızı ve sarı yatay üç şerit', region: 'Orta Avrupa'),
  (code: 'NL', name: 'Hollanda', capital: 'Amsterdam', continent: 'Avrupa', currency: 'Euro', lang: 'Felemenkçe', landmark: 'Kinderdijk Yel Değirmenleri', colors: 'Kırmızı, beyaz ve mavi yatay üç şerit', region: 'Batı Avrupa Kuzey Denizi kıyısı'),
  (code: 'RU', name: 'Rusya', capital: 'Moskova', continent: 'Avrupa ve Asya', currency: 'Rus Rublesi', lang: 'Rusça', landmark: 'Kızıl Meydan ve Baykal Gölü', colors: 'Beyaz, mavi ve kırmızı yatay üç şerit', region: 'Doğu Avrupa ve Kuzey Asya'),
  (code: 'AT', name: 'Avusturya', capital: 'Viyana', continent: 'Avrupa', currency: 'Euro', lang: 'Almanca', landmark: 'Schönbrunn Sarayı ve Alpler', colors: 'Kırmızı, beyaz ve kırmızı yatay üç şerit', region: 'Orta Avrupa Alp ülkesi'),
  (code: 'HU', name: 'Macaristan', capital: 'Budapeşte', continent: 'Avrupa', currency: 'Forint', lang: 'Macarca', landmark: 'Tuna Nehri ve Parlamento Binası', colors: 'Kırmızı, beyaz ve yeşil yatay üç şerit', region: 'Orta Avrupa Karpat Havzası'),
  (code: 'BG', name: 'Bulgaristan', capital: 'Sofya', continent: 'Avrupa', currency: 'Bulgar Levası', lang: 'Bulgarca', landmark: 'Rila Manastırı ve Gül Vadisi', colors: 'Beyaz, yeşil ve kırmızı yatay üç şerit', region: 'Balkanlar ve Karadeniz kıyısı'),
  (code: 'PL', name: 'Polonya', capital: 'Varşova', continent: 'Avrupa', currency: 'Zloti', lang: 'Lehçe', landmark: 'Kraków Tarihi Merkezi', colors: 'Üstte beyaz, altta kırmızı iki yatay şerit', region: 'Orta Avrupa Baltık kıyısı'),
  (code: 'ID', name: 'Endonezya', capital: 'Cakarta', continent: 'Asya', currency: 'Endonezya Rupiahı', lang: 'Endonezce', landmark: 'Borobudur Tapınağı ve Bali', colors: 'Üstte kırmızı, altta beyaz iki yatay şerit', region: 'Güneydoğu Asya takımada ülkesi'),
  (code: 'UA', name: 'Ukrayna', capital: 'Kiev', continent: 'Avrupa', currency: 'Grivna', lang: 'Ukraynaca', landmark: 'Aziz Sofya Katedrali ve Dinyeper', colors: 'Üstte mavi, altta sarı iki yatay şerit', region: 'Doğu Avrupa Karadeniz kuzeyi'),
  (code: 'ES', name: 'İspanya', capital: 'Madrid', continent: 'Avrupa', currency: 'Euro', lang: 'İspanyolca', landmark: 'Sagrada Família ve El Hamra', colors: 'Kırmızı-sarı-kırmızı yatay şeritler ve kraliyet arması', region: 'İber Yarımadası Güneybatı Avrupa'),
  (code: 'AR', name: 'Arjantin', capital: 'Buenos Aires', continent: 'Güney Amerika', currency: 'Arjantin Pesosu', lang: 'İspanyolca', landmark: 'Patagonya ve Iguazú Şelalesi', colors: 'Açık mavi-beyaz-açık mavi şeritler ve Mayıs Güneşi', region: 'Güney Amerika güney konisi'),
  (code: 'CO', name: 'Kolombiya', capital: 'Bogotá', continent: 'Güney Amerika', currency: 'Kolombiya Pesosu', lang: 'İspanyolca', landmark: 'Cartagena Surları ve kahve vadileri', colors: 'Geniş sarı, ardından mavi ve kırmızı yatay şerit', region: 'Güney Amerika kuzeybatısı'),
  (code: 'TH', name: 'Tayland', capital: 'Bangkok', continent: 'Asya', currency: 'Baht', lang: 'Tayca', landmark: 'Büyük Saray ve Ayutthaya', colors: 'Kırmızı-beyaz-lacivert-beyaz-kırmızı beş yatay şerit', region: 'Güneydoğu Asya Çinhindi yarımadası'),
  (code: 'IN', name: 'Hindistan', capital: 'Yeni Delhi', continent: 'Asya', currency: 'Hint Rupisi', lang: 'Hintçe ve İngilizce', landmark: 'Tac Mahal', colors: 'Safran, beyaz, yeşil şeritler ve lacivert çark', region: 'Güney Asya Hint Yarımadası'),
  (code: 'EG', name: 'Mısır', capital: 'Kahire', continent: 'Afrika', currency: 'Mısır Lirası', lang: 'Arapça', landmark: 'Gize Piramitleri ve Nil Nehri', colors: 'Kırmızı, beyaz, siyah şeritler ve altın kartal', region: 'Kuzeydoğu Afrika Süveyş bölgesi'),
  (code: 'GH', name: 'Gana', capital: 'Akra', continent: 'Afrika', currency: 'Gana Sedisi', lang: 'İngilizce', landmark: 'Volta Gölü ve Cape Coast Kalesi', colors: 'Kırmızı, sarı, yeşil şeritler ve siyah yıldız', region: 'Batı Afrika Atlantik kıyısı'),
  (code: 'ET', name: 'Etiyopya', capital: 'Addis Ababa', continent: 'Afrika', currency: 'Birr', lang: 'Amharca', landmark: 'Lalibela Kaya Kiliseleri', colors: 'Yeşil, sarı, kırmızı şeritler ve mavi daire içinde yıldız', region: 'Doğu Afrika Boynuzu'),
  (code: 'AZ', name: 'Azerbaycan', capital: 'Bakü', continent: 'Asya ve Avrupa', currency: 'Azerbaycan Manatı', lang: 'Azerbaycanca', landmark: 'Alev Kuleleri ve Kız Kulesi', colors: 'Turkuaz, kırmızı, yeşil şeritler ve ay-yıldız', region: 'Güney Kafkasya Hazar kıyısı'),
  (code: 'UZ', name: 'Özbekistan', capital: 'Taşkent', continent: 'Asya', currency: 'Özbek Somu', lang: 'Özbekçe', landmark: 'Semerkant Registan Meydanı', colors: 'Mavi, beyaz, yeşil şeritler, kırmızı çizgi ve hilal', region: 'Orta Asya İpek Yolu merkezi'),
  (code: 'SE', name: 'İsveç', capital: 'Stockholm', continent: 'Avrupa', currency: 'İsveç Kronu', lang: 'İsveççe', landmark: 'Vasa Müzesi ve Nobel Salonu', colors: 'Mavi zemin üzerinde sarı İskandinav haçı', region: 'Kuzey Avrupa İskandinavya'),
  (code: 'FI', name: 'Finlandiya', capital: 'Helsinki', continent: 'Avrupa', currency: 'Euro', lang: 'Fince ve İsveççe', landmark: 'Laponya ve bin göller yöresi', colors: 'Beyaz zemin üzerinde lacivert İskandinav haçı', region: 'Kuzey Avrupa Baltık kıyısı'),
  (code: 'DK', name: 'Danimarka', capital: 'Kopenhag', continent: 'Avrupa', currency: 'Danimarka Kronu', lang: 'Danca', landmark: 'Nyhavn Limanı ve Kronborg Kalesi', colors: 'Kırmızı zemin üzerinde beyaz İskandinav haçı', region: 'Kuzey Avrupa Jutland yarımadası'),
  (code: 'NO', name: 'Norveç', capital: 'Oslo', continent: 'Avrupa', currency: 'Norveç Kronu', lang: 'Norveççe', landmark: 'Geiranger Fiyordu', colors: 'Kırmızı zemin üzerinde beyaz çerçeveli lacivert haç', region: 'Kuzey Avrupa Atlantik kıyısı'),
  (code: 'IS', name: 'İzlanda', capital: 'Reykjavik', continent: 'Avrupa', currency: 'İzlanda Kronası', lang: 'İzlandaca', landmark: 'Geysir ve Mavi Lagün', colors: 'Mavi zemin üzerinde beyaz çerçeveli kırmızı haç', region: 'Kuzey Atlantik volkanik ada ülkesi'),
  (code: 'CH', name: 'İsviçre', capital: 'Bern', continent: 'Avrupa', currency: 'İsviçre Frangı', lang: 'Almanca ve Fransızca', landmark: 'Matterhorn Zirvesi ve Cenevre Gölü', colors: 'Kırmızı zemin üzerinde ortalanmış beyaz artı haçı', region: 'Orta Avrupa Alp Konfederasyonu'),
  (code: 'GE', name: 'Gürcistan', capital: 'Tiflis', continent: 'Asya ve Avrupa', currency: 'Gürcü Larisi', lang: 'Gürcüce', landmark: 'Kazbek Dağı ve Eski Tiflis', colors: 'Beyaz zemin üzerinde büyük kırmızı haç ve dört küçük haç', region: 'Güney Kafkasya Karadeniz kıyısı'),
  (code: 'GB', name: 'Birleşik Krallık', capital: 'Londra', continent: 'Avrupa', currency: 'İngiliz Sterlini', lang: 'İngilizce', landmark: 'Big Ben ve Stonehenge', colors: 'Lacivert zemin üzerinde kırmızı-beyaz çapraz ve dik haçlar', region: 'Kuzeybatı Avrupa Britanya Adaları'),
  (code: 'US', name: 'Amerika Birleşik Devletleri', capital: 'Washington D.C.', continent: 'Kuzey Amerika', currency: 'Amerikan Doları', lang: 'İngilizce', landmark: 'Özgürlük Heykeli ve Büyük Kanyon', colors: 'Kırmızı-beyaz şeritler ve sol üstte yıldızlı lacivert kanton', region: 'Kuzey Amerika kıtalararası güç'),
  (code: 'GR', name: 'Yunanistan', capital: 'Atina', continent: 'Avrupa', currency: 'Euro', lang: 'Yunanca', landmark: 'Akropolis ve Parthenon', colors: 'Mavi-beyaz yatay şeritler ve sol üstte beyaz haç', region: 'Güneydoğu Avrupa Ege ve Akdeniz'),
  (code: 'CL', name: 'Şili', capital: 'Santiago', continent: 'Güney Amerika', currency: 'Şili Pesosu', lang: 'İspanyolca', landmark: 'Atacama Çölü ve Paskalya Adası', colors: 'Beyaz-kırmızı iki şerit ve sol üstte tek yıldızlı mavi kare', region: 'Güney Amerika uzun Pasifik şeridi'),
  (code: 'MY', name: 'Malezya', capital: 'Kuala Lumpur', continent: 'Asya', currency: 'Malezya Ringgiti', lang: 'Malayca', landmark: 'Petronas İkiz Kuleleri', colors: 'Kırmızı-beyaz şeritler ve lacivert kantonda sarı hilal-yıldız', region: 'Güneydoğu Asya Malakka Boğazı'),
  (code: 'SG', name: 'Singapur', capital: 'Singapur', continent: 'Asya', currency: 'Singapur Doları', lang: 'İngilizce ve Malayca', landmark: 'Marina Bay Sands ve Botanik Bahçesi', colors: 'Üstte kırmızı, altta beyaz zemin ve sol üstte beyaz hilal', region: 'Güneydoğu Asya şehir devleti'),
  (code: 'BR', name: 'Brezilya', capital: 'Brasília', continent: 'Güney Amerika', currency: 'Brezilya Reali', lang: 'Portekizce', landmark: 'Amazon Yağmur Ormanı ve Kurtarıcı İsa', colors: 'Yeşil zemin, sarı eşkenar dörtgen ve lacivert küre', region: 'Güney Amerika en büyük ülkesi'),
  (code: 'CN', name: 'Çin', capital: 'Pekin', continent: 'Asya', currency: 'Çin Yuanı', lang: 'Çince', landmark: 'Çin Seddi ve Yasak Şehir', colors: 'Kırmızı zemin üzerinde sol üstte beş sarı yıldız', region: 'Doğu Asya'),
  (code: 'VN', name: 'Vietnam', capital: 'Hanoi', continent: 'Asya', currency: 'Vietnam Dongu', lang: 'Vietnamca', landmark: 'Ha Long Körfezi', colors: 'Kırmızı zemin ortasında tek büyük sarı yıldız', region: 'Güneydoğu Asya Güney Çin Denizi'),
  (code: 'MA', name: 'Fas', capital: 'Rabat', continent: 'Afrika', currency: 'Fas Dirhemi', lang: 'Arapça ve Berberice', landmark: 'Marakeş ve Atlas Dağları', colors: 'Kırmızı zemin ortasında beş köşeli yeşil yıldız', region: 'Kuzeybatı Afrika Mağrip bölgesi'),
  (code: 'TN', name: 'Tunus', capital: 'Tunus', continent: 'Afrika', currency: 'Tunus Dinarı', lang: 'Arapça', landmark: 'Kartaca Antik Kenti', colors: 'Kırmızı zemin ortasında beyaz daire ve kırmızı ay-yıldız', region: 'Kuzey Afrika Akdeniz kıyısı'),
  (code: 'PK', name: 'Pakistan', capital: 'İslamabad', continent: 'Asya', currency: 'Pakistan Rupisi', lang: 'Urduca ve İngilizce', landmark: 'K2 Zirvesi ve Badşahi Camii', colors: 'Sol kenarda beyaz dikey şerit, koyu yeşil alanda hilal-yıldız', region: 'Güney Asya İndus Vadisi'),
  (code: 'SA', name: 'Suudi Arabistan', capital: 'Riyad', continent: 'Asya', currency: 'Suudi Riyali', lang: 'Arapça', landmark: 'El-Ula ve Hicaz bölgesi', colors: 'Koyu yeşil zemin üzerinde beyaz hat yazısı ve kılıç', region: 'Orta Doğu Arap Yarımadası'),
  (code: 'KR', name: 'Güney Kore', capital: 'Seul', continent: 'Asya', currency: 'Güney Kore Wonu', lang: 'Korece', landmark: 'Gyeongbokgung Sarayı ve Jeju Adası', colors: 'Beyaz zemin ortasında kırmızı-mavi daire ve dört köşe çizgisi', region: 'Doğu Asya Kore Yarımadası'),
  (code: 'CZ', name: 'Çekya', capital: 'Prag', continent: 'Avrupa', currency: 'Çek Korunası', lang: 'Çekçe', landmark: 'Karl Köprüsü ve Prag Kalesi', colors: 'Beyaz-kırmızı iki şerit ve soldan uzanan lacivert üçgen', region: 'Orta Avrupa Bohemya'),
  (code: 'PH', name: 'Filipinler', capital: 'Manila', continent: 'Asya', currency: 'Filipin Pesosu', lang: 'Filipince ve İngilizce', landmark: 'Palawan ve Pirinç Terasları', colors: 'Mavi-kırmızı iki şerit ve solda altın güneşli beyaz üçgen', region: 'Güneydoğu Asya Pasifik takımadaları'),
  (code: 'CU', name: 'Küba', capital: 'Havana', continent: 'Kuzey Amerika', currency: 'Küba Pesosu', lang: 'İspanyolca', landmark: 'Eski Havana ve Viñales Vadisi', colors: 'Mavi-beyaz şeritler ve solda tek yıldızlı kırmızı üçgen', region: 'Karayipler ada ülkesi'),
  (code: 'PT', name: 'Portekiz', capital: 'Lizbon', continent: 'Avrupa', currency: 'Euro', lang: 'Portekizce', landmark: 'Belém Kulesi ve Douro Vadisi', colors: 'Yeşil ve kırmızı dikey alanlar birleşiminde altın küre arması', region: 'Güneybatı Avrupa Atlantik kıyısı'),
  (code: 'JM', name: 'Jamaika', capital: 'Kingston', continent: 'Kuzey Amerika', currency: 'Jamaika Doları', lang: 'İngilizce', landmark: 'Blue Mountains kahve bölgesi', colors: 'Sarı çapraz şeritlerle ayrılmış yeşil ve siyah üçgenler', region: 'Karayipler Büyük Antiller'),
  (code: 'ZA', name: 'Güney Afrika', capital: 'Pretoria', continent: 'Afrika', currency: 'Güney Afrika Randı', lang: 'İngilizce ve Zuluca', landmark: 'Masa Dağı ve Ümit Burnu', colors: 'Yeşil Y şeridiyle birleşen kırmızı, mavi, siyah ve sarı', region: 'Afrika kıtasının en güneyi'),
  (code: 'KE', name: 'Kenya', capital: 'Nairobi', continent: 'Afrika', currency: 'Kenya Şilini', lang: 'Svahili ve İngilizce', landmark: 'Masai Mara ve Büyük Rift Vadisi', colors: 'Siyah, kırmızı, yeşil şeritler ve ortada Masai kalkanı', region: 'Doğu Afrika Ekvator kuşağı'),
  (code: 'AE', name: 'Birleşik Arap Emirlikleri', capital: 'Abu Dabi', continent: 'Asya', currency: 'BAE Dirhemi', lang: 'Arapça', landmark: 'Burc Halife ve Şeyh Zayid Camii', colors: 'Solda dikey kırmızı şerit ve yatay yeşil-beyaz-siyah', region: 'Orta Doğu Basra Körfezi'),
  (code: 'QA', name: 'Katar', capital: 'Doha', continent: 'Asya', currency: 'Katar Riyali', lang: 'Arapça', landmark: 'İslam Eserleri Müzesi', colors: 'Solda dokuz dişli beyaz şerit ve bordo alan', region: 'Orta Doğu Basra Körfezi yarımadası'),
  (code: 'KZ', name: 'Kazakistan', capital: 'Astana', continent: 'Asya', currency: 'Tenge', lang: 'Kazakça ve Rusça', landmark: 'Bayterek Kulesi ve Tanrı Dağları', colors: 'Gök mavisi zemin üzerinde altın güneş ve bozkır kartalı', region: 'Orta Asya en geniş bozkır ülkesi'),
  (code: 'AU', name: 'Avustralya', capital: 'Kanberra', continent: 'Okyanusya', currency: 'Avustralya Doları', lang: 'İngilizce', landmark: 'Sidney Opera Binası ve Büyük Set Resifi', colors: 'Lacivert zemin, sol üstte Birleşik Krallık bayrağı ve Güney Haçı', region: 'Okyanusya kıta ülkesi'),
  (code: 'NZ', name: 'Yeni Zelanda', capital: 'Wellington', continent: 'Okyanusya', currency: 'Yeni Zelanda Doları', lang: 'İngilizce ve Maorice', landmark: 'Milford Sound fiyortları', colors: 'Lacivert zemin, sol üstte Birleşik Krallık bayrağı ve kırmızı yıldızlar', region: 'Güneybatı Pasifik Okyanusya'),
];

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
  var cursor = (seed * 17 + 5) % n;
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

AdvancedItem _buildFlagCountry(int i) {
  final c = _countries[i % _countries.length];
  final angle = i ~/ _countries.length; // 0..4 => 64 * 5 = 320
  final vis = QuestionVisual(
    kind: VisualKind.flag,
    title: 'Bayrak Atlası #${i + 1}',
    summary: c.colors,
    imageID: c.code,
  );
  switch (angle) {
    case 0:
      return AdvancedItem(
        'Görselde gösterilen bayrak hangi ülkeye aittir?',
        c.name,
        _pickDistinct(_countries.map((e) => e.name).toList(), c.name, i + 11),
        '${c.colors} tasarımı ${c.name} bayrağına aittir (Başkent: ${c.capital}).',
        visual: vis,
      );
    case 1:
      return AdvancedItem(
        'Bayrağı gösterilen ülkenin başkenti neresidir?',
        c.capital,
        _pickDistinct(_countries.map((e) => e.capital).toList(), c.capital, i + 23),
        'Görseldeki bayrak ${c.name} ülkesine aittir ve başkenti ${c.capital} şehridir.',
        visual: vis,
      );
    case 2:
      const allContinents = ['Avrupa', 'Asya', 'Afrika', 'Kuzey Amerika', 'Güney Amerika', 'Okyanusya', 'Asya ve Avrupa', 'Avrupa ve Asya'];
      return AdvancedItem(
        'Görseldeki bayrağa sahip ülke hangi kıtada yer alır?',
        c.continent,
        _pickDistinct(allContinents, c.continent, i + 31),
        '${c.name}, ${c.continent} kıtasında (${c.region}) yer alır.',
        visual: vis,
      );
    case 3:
      return AdvancedItem(
        'Bayrağı gösterilen ülkenin resmi para birimi hangisidir?',
        c.currency,
        _pickDistinct(_countries.map((e) => e.currency).toSet().toList(), c.currency, i + 43),
        '${c.name} ülkesinin resmi para birimi ${c.currency} olarak kullanılır.',
        visual: vis,
      );
    default:
      return AdvancedItem(
        'Bayrağı verilen ülkede konuşulan başlıca resmi dil hangisidir?',
        c.lang,
        _pickDistinct(_countries.map((e) => e.lang).toSet().toList(), c.lang, i + 59),
        '${c.name} ülkesinin başlıca resmi dili ${c.lang} olarak kabul edilir.',
        visual: vis,
      );
  }
}

AdvancedItem _buildFlagMeta(int i) {
  final c = _countries[i % _countries.length];
  final angle = i ~/ _countries.length; // 0..4 => 64 * 5 = 320
  final vis = QuestionVisual(
    kind: VisualKind.flag,
    title: 'Bayrak & Kültür Analizi #${i + 1}',
    summary: c.colors,
    imageID: c.code,
  );
  switch (angle) {
    case 0:
      return AdvancedItem(
        'Bayrağı gösterilen ülke hangi ünlü yapı veya doğal simgeyle özdeşleşmiştir?',
        c.landmark,
        _pickDistinct(_countries.map((e) => e.landmark).toList(), c.landmark, i + 17),
        '${c.landmark}, bayrağı gösterilen ${c.name} ülkesinin en tanınan simgelerindendir.',
        visual: vis,
      );
    case 1:
      return AdvancedItem(
        'Görseldeki bayrağa sahip ülkenin uluslararası 2 harfli ISO ülke kodu hangisidir?',
        c.code,
        _pickDistinct(_countries.map((e) => e.code).toList(), c.code, i + 29),
        '${c.name} ülkesinin ISO 3166-1 alpha-2 kodu "${c.code}" şeklindedir.',
        visual: vis,
      );
    case 2:
      final correctPair = '${c.name} – ${c.capital}';
      final c1 = _countries[(i + 9) % _countries.length];
      final c2 = _countries[(i + 19) % _countries.length];
      final c3 = _countries[(i + 31) % _countries.length];
      return AdvancedItem(
        'Görseldeki bayrağın ülke–başkent eşleştirmesi hangi seçenekte doğrudur?',
        correctPair,
        ['${c.name} – ${c1.capital}', '${c2.name} – ${c.capital}', '${c3.name} – ${c3.capital}'],
        'Gösterilen bayrak ${c.name} ülkesine aittir ve başkenti ${c.capital} şehridir.',
        visual: vis,
      );
    case 3:
      return AdvancedItem(
        'Görseldeki bayrağın coğrafi konum tanımı hangi seçenekte doğru verilmiştir?',
        c.region,
        _pickDistinct(_countries.map((e) => e.region).toSet().toList(), c.region, i + 37),
        '${c.name} (${c.capital}), ${c.region} konumunda bulunur.',
        visual: vis,
      );
    default:
      final wrongCountries = _pickDistinct(_countries.map((e) => e.name).toList(), c.name, i + 47);
      return AdvancedItem(
        'Bayrağın görsel tasarımını inceleyin: "${c.colors}" betimlemesiyle uyuşan bu bayrak hangi ülkenindir?',
        c.name,
        wrongCountries,
        '${c.name} bayrağı, ${c.colors.toLowerCase()} düzeniyle ayırt edilir.',
        visual: vis,
      );
  }
}

// ---------------------------------------------------------------------------
// 2. ANALOG SAAT, AÇI VE İNGİLİZCE SAAT KADRANI (640 soru)
// ---------------------------------------------------------------------------
String _fmtDeg(double d) {
  if ((d - d.roundToDouble()).abs() < 0.01) return '${d.round()}°';
  return '${d.toStringAsFixed(1).replaceAll('.', ',')}°';
}

AdvancedItem _buildClockAngle(int i) {
  // 12 hours × 20 distinct minute/task slots = 240
  const mins = [0, 5, 10, 12, 15, 20, 24, 25, 30, 35, 36, 40, 45, 48, 50, 55, 10, 20, 30, 40];
  final hour = (i % 12) + 1;
  final slot = i ~/ 12; // 0..19
  final minute = mins[slot];
  final askReflex = slot >= 16;

  final hDeg = ((hour % 12) * 30.0 + minute * 0.5) % 360.0;
  final mDeg = (minute * 6.0) % 360.0;
  var diff = (hDeg - mDeg).abs();
  if (diff > 180) diff = 360.0 - diff;
  final answerVal = askReflex ? (360.0 - diff == 360.0 ? 360.0 : 360.0 - diff) : diff;
  final hh = hour.toString().padLeft(2, '0');
  final mm = minute.toString().padLeft(2, '0');

  final correct = _fmtDeg(answerVal);
  final wrongSet = <String>{};
  for (final delta in [15.0, -15.0, 30.0, 22.5, -22.5, 45.0, 10.0]) {
    var cand = answerVal + delta;
    if (cand < 0) cand += 90;
    if (cand > 360) cand -= 60;
    final s = _fmtDeg(cand);
    if (s != correct) wrongSet.add(s);
    if (wrongSet.length == 3) break;
  }

  return AdvancedItem(
    askReflex
        ? 'Analog saat $hh:$mm gösterirken akrep ile yelkovan arasındaki BÜYÜK açı kaç derecedir?'
        : 'Analog saat $hh:$mm gösterirken akrep ile yelkovan arasındaki küçük açı kaç derecedir?',
    correct,
    wrongSet.toList(),
    'Akrep saatte 30°, dakikada 0,5° döner (${_fmtDeg(hDeg)}); yelkovan dakikada 6° döner (${_fmtDeg(mDeg)}). '
    'Küçük açı ${_fmtDeg(diff)}${askReflex ? ', büyük açı 360° − ${_fmtDeg(diff)} = $correct' : ''} olur.',
    visual: QuestionVisual(
      kind: VisualKind.clock,
      title: 'Saat Açısı · $hh:$mm',
      summary: 'Analog saat $hh:$mm konumunda akrep ve yelkovan arasındaki açı gösteriliyor.',
      values: [hour.toDouble(), minute.toDouble(), 1.0],
      unit: 'Saat $hh:$mm',
    ),
  );
}

const _enHours = [
  'twelve', 'one', 'two', 'three', 'four', 'five',
  'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
];
const _enMinsWord = {
  5: 'five',
  10: 'ten',
  15: 'a quarter',
  20: 'twenty',
  25: 'twenty-five',
  30: 'half',
  35: 'twenty-five',
  40: 'twenty',
  45: 'a quarter',
  50: 'ten',
  55: 'five',
};

String _englishTimePhrase(int h, int m) {
  final hWord = _enHours[h % 12];
  final nextWord = _enHours[(h % 12) + 1];
  if (m == 0) return "It is $hWord o'clock.";
  if (m == 15) return 'It is a quarter past $hWord.';
  if (m == 30) return 'It is half past $hWord.';
  if (m == 45) return 'It is a quarter to $nextWord.';
  if (m < 30) return 'It is ${_enMinsWord[m]} past $hWord.';
  return 'It is ${_enMinsWord[m]} to $nextWord.';
}

AdvancedItem _buildClockEnglish(int i) {
  // 12 hours × 20 minute/format variants = 240
  const mList = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 0, 15, 30, 45, 10, 20, 40, 50];
  final hour = (i % 12) + 1;
  final slot = i ~/ 12; // 0..19
  final minute = mList[slot];
  final isPm = slot >= 12;
  final hh = hour.toString().padLeft(2, '0');
  final mm = minute.toString().padLeft(2, '0');
  final correct = _englishTimePhrase(hour, minute);

  final wrong = <String>{};
  final nextH = (hour % 12) + 1;
  final prevH = hour == 1 ? 12 : hour - 1;
  for (final cand in [
    _englishTimePhrase(nextH, minute),
    _englishTimePhrase(hour, (60 - minute) % 60),
    _englishTimePhrase(prevH, minute),
    _englishTimePhrase(hour, (minute + 15) % 60),
    _englishTimePhrase(nextH, (minute + 30) % 60),
  ]) {
    if (cand != correct) wrong.add(cand);
    if (wrong.length == 3) break;
  }

  return AdvancedItem(
    'Görseldeki analog saatin İngilizce doğru söylenişi hangisidir?',
    correct,
    wrong.toList(),
    '$hh:$mm saati İngilizcede "$correct" şeklinde ifade edilir (past = geçiyor, to = var, quarter = çeyrek, half = buçuk).',
    visual: QuestionVisual(
      kind: VisualKind.clock,
      title: 'İngilizce Saat Okuma',
      summary: 'Analog saat $hh:$mm gösteriyor.',
      values: [hour.toDouble(), minute.toDouble(), 0.0],
      unit: isPm ? 'Afternoon / Evening (PM)' : 'Morning (AM)',
    ),
  );
}

typedef _TzCity = ({String name, int offset});
const _tzCities = <_TzCity>[
  (name: 'Londra', offset: 0),
  (name: 'Paris', offset: 1),
  (name: 'Kahire', offset: 2),
  (name: 'İstanbul', offset: 3),
  (name: 'Dubai', offset: 4),
  (name: 'Bangkok', offset: 7),
  (name: 'Tokyo', offset: 9),
  (name: 'Sidney', offset: 10),
  (name: 'New York', offset: -5),
  (name: 'Rio de Janeiro', offset: -3),
];

AdvancedItem _buildClockTimeZone(int i) {
  // 160 questions: world time zone offset & flight arrival time
  final baseCity = _tzCities[i % _tzCities.length];
  final targetCity = _tzCities[(i + 3 + (i ~/ 10) % 6) % _tzCities.length];
  final startHour = 6 + (i * 5) % 12;
  final startMin = (i % 4) * 15;
  final diff = targetCity.offset - baseCity.offset;
  final targetTotal = (startHour * 60 + startMin + diff * 60 + 1440) % 1440;
  final th = targetTotal ~/ 60;
  final tm = targetTotal % 60;

  String fmt(int h, int m) => '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  final correct = fmt(th, tm);
  final wrong = <String>{};
  for (final dh in [1, -1, 2, -2, 3]) {
    final wh = (th + dh + 24) % 24;
    final cand = fmt(wh, tm);
    if (cand != correct) wrong.add(cand);
    if (wrong.length == 3) break;
  }

  final signBase = baseCity.offset >= 0 ? '+${baseCity.offset}' : '${baseCity.offset}';
  final signTarget = targetCity.offset >= 0 ? '+${targetCity.offset}' : '${targetCity.offset}';

  return AdvancedItem(
    'Saat kadranı ${baseCity.name} (UTC$signBase) için ${fmt(startHour, startMin)} gösteriyorsa, aynı anda ${targetCity.name} (UTC$signTarget) şehrinde saat kaçtır?',
    correct,
    wrong.toList(),
    '${targetCity.name} (UTC$signTarget) ile ${baseCity.name} (UTC$signBase) arasındaki saat farkı ${diff >= 0 ? '+$diff' : '$diff'} saattir. ${fmt(startHour, startMin)} üzerine eklenince $correct bulunur.',
    visual: QuestionVisual(
      kind: VisualKind.clock,
      title: 'Saat Dilimi · ${baseCity.name}',
      summary: '${baseCity.name} yerel saati ${fmt(startHour, startMin)}.',
      values: [(startHour % 12 == 0 ? 12 : startHour % 12).toDouble(), startMin.toDouble(), 0.0],
      unit: '${baseCity.name} (UTC$signBase) · ${fmt(startHour, startMin)}',
    ),
  );
}

// ---------------------------------------------------------------------------
// 3. 3D PASTA / HALKA GRAFİĞİ ANALİZİ (520 soru)
// ---------------------------------------------------------------------------
typedef _PieTheme = ({String title, List<String> labels, String unit});

const _econPieThemes = <_PieTheme>[
  (title: 'Aylık Ev Bütçesi Dağılımı', labels: ['Barınma', 'Gıda', 'Ulaşım', 'Tasarruf'], unit: '%'),
  (title: 'Şirket Ar-Ge Harcama Payları', labels: ['Yazılım', 'Donanım', 'Eğitim', 'Test'], unit: '%'),
  (title: 'Ülke İhracat Sektörleri', labels: ['Otomotiv', 'Tekstil', 'Elektronik', 'Tarım'], unit: '%'),
  (title: 'Kent İçi Ulaşım Tercihi', labels: ['Metro', 'Otobüs', 'Yaya', 'Bisiklet'], unit: '%'),
  (title: 'Haftalık Ders Çalışma Planı', labels: ['Matematik', 'Fen', 'Türkçe', 'İngilizce'], unit: '%'),
];

const _sciPieThemes = <_PieTheme>[
  (title: 'Elektrik Üretim Kaynakları', labels: ['Güneş', 'Rüzgâr', 'Hidro', 'Jeotermal'], unit: '%'),
  (title: 'Atık Geri Dönüşüm Oranları', labels: ['Kâğıt', 'Cam', 'Metal', 'Plastik'], unit: '%'),
  (title: 'Bölgesel Su Kullanım Payı', labels: ['Tarım', 'Sanayi', 'Evsel', 'Park'], unit: '%'),
  (title: 'Besin Enerji Dağılımı', labels: ['Karbonhidrat', 'Protein', 'Yağ', 'Lif'], unit: '%'),
  (title: 'Ekosistem Biyokütle Payı', labels: ['Üretici', 'Otçul', 'Etçil', 'Ayrıştırıcı'], unit: '%'),
];

AdvancedItem _buildPieQuestion(int i, List<_PieTheme> themes, bool isEcon) {
  final theme = themes[i % themes.length];
  final a = 15 + (i * 5) % 35; // 15..45 (step 5)
  final b = 10 + ((i ~/ 5) * 5) % 25; // 10..30
  final c = 10 + ((i ~/ 25) * 5) % 20; // 10..25
  final d = 100 - a - b - c;
  final vals = [a.toDouble(), b.toDouble(), c.toDouble(), d.toDouble()];
  final task = i % 4;

  final vis = QuestionVisual(
    kind: VisualKind.pieChart,
    title: theme.title,
    summary: '${theme.labels[0]} %$a, ${theme.labels[1]} %$b, ${theme.labels[2]} %$c, ${theme.labels[3]} %$d.',
    labels: theme.labels,
    values: vals,
    unit: '%',
  );

  if (task == 0) {
    final targetIdx = (i ~/ 4) % 4;
    final deg = (vals[targetIdx] * 3.6).round();
    final correct = '$deg°';
    final wrong = <String>{};
    for (final delta in [18, -18, 36, 54, -36, 72]) {
      final cand = deg + delta;
      if (cand > 0 && cand < 360 && '$cand°' != correct) wrong.add('$cand°');
      if (wrong.length == 3) break;
    }
    return AdvancedItem(
      '${theme.title} grafiğinde "${theme.labels[targetIdx]}" diliminin merkez açısı kaç derecedir?',
      correct,
      wrong.toList(),
      'Daire grafiğinde %100 = 360° olduğundan %${vals[targetIdx].toInt()} payın merkez açısı ${vals[targetIdx].toInt()} × 3,6 = $deg° olur.',
      visual: vis,
    );
  } else if (task == 1) {
    final totalBudget = isEcon ? (2000 + (i % 8) * 1000) : (400 + (i % 6) * 200);
    final unitWord = isEcon ? 'TL' : 'ton';
    final targetIdx = (i ~/ 4) % 4;
    final amount = (totalBudget * vals[targetIdx] / 100).round();
    final step = max(10, totalBudget * 5 ~/ 100);
    final correct = '$amount $unitWord';
    final wrong = <String>{};
    for (final delta in [step, -step, step * 2, step * 3]) {
      final cand = amount + delta;
      if (cand > 0 && '$cand $unitWord' != correct) wrong.add('$cand $unitWord');
      if (wrong.length == 3) break;
    }
    return AdvancedItem(
      'Grafikteki toplam değer $totalBudget $unitWord ise "${theme.labels[targetIdx]}" dilimine düşen miktar nedir?',
      correct,
      wrong.toList(),
      '$totalBudget $unitWord toplamının %${vals[targetIdx].toInt()} kadarı $totalBudget × ${vals[targetIdx].toInt()} / 100 = $amount $unitWord eder.',
      visual: vis,
    );
  } else if (task == 2) {
    final sumTop2 = vals[0].toInt() + vals[1].toInt();
    final correct = '%$sumTop2';
    final wrong = <String>{};
    for (final cand in [sumTop2 + 5, sumTop2 - 5, 100 - sumTop2, sumTop2 + 10, sumTop2 - 10]) {
      if (cand > 0 && cand < 100 && '%$cand' != correct) wrong.add('%$cand');
      if (wrong.length == 3) break;
    }
    return AdvancedItem(
      'Grafikte "${theme.labels[0]}" ve "${theme.labels[1]}" dilimlerinin toplam oranı yüzde kaçtır?',
      correct,
      wrong.toList(),
      '${theme.labels[0]} (%${vals[0].toInt()}) + ${theme.labels[1]} (%${vals[1].toInt()}) = %$sumTop2 olur.',
      visual: vis,
    );
  } else {
    final maxV = vals.reduce(max).toInt();
    final minV = vals.reduce(min).toInt();
    final diff = maxV - minV;
    final correct = '%$diff puan';
    final wrong = <String>{};
    for (final delta in [5, 10, -5, 15, 20]) {
      final cand = diff + delta;
      if (cand >= 0 && cand <= 95 && '%$cand puan' != correct) wrong.add('%$cand puan');
      if (wrong.length == 3) break;
    }
    return AdvancedItem(
      'Grafikteki en büyük dilim ile en küçük dilim arasındaki yüzde puan farkı kaçtır?',
      correct,
      wrong.toList(),
      'En büyük dilim %$maxV, en küçük dilim %$minV olduğundan aradaki fark $maxV − $minV = %$diff puandır.',
      visual: vis,
    );
  }
}

// ---------------------------------------------------------------------------
// 4. KOORDİNAT DÜZLEMİ & VEKTÖR SAHNESİ (640 soru)
// ---------------------------------------------------------------------------
AdvancedItem _buildCoordGeometry(int i) {
  // 360 questions cycling through 5 geometric tasks
  final mode = i % 5;
  final k = i ~/ 5; // 0..71

  if (mode == 0) {
    // Distance using exact Pythagorean triples
    const triples = [(3, 4, 5), (4, 3, 5), (6, 8, 10), (8, 6, 10), (5, 0, 5), (0, 6, 6), (3, 0, 3), (0, 7, 7)];
    final t = triples[k % triples.length];
    final x1 = -4 + (k % 3);
    final y1 = -4 + ((k ~/ 3) % 3);
    final x2 = x1 + t.$1;
    final y2 = y1 + t.$2;
    final dist = t.$3;
    return AdvancedItem(
      'Koordinat düzleminde gösterilen A($x1, $y1) ve B($x2, $y2) noktaları arasındaki |AB| uzaklığı kaç birimdir?',
      '$dist birim',
      ['${dist + 1} birim', '${dist + 2} birim', '${dist > 1 ? dist - 1 : dist + 3} birim'],
      'Δx = ${t.$1}, Δy = ${t.$2} olduğundan |AB| = √(${t.$1}² + ${t.$2}²) = $dist birim bulunur.',
      visual: QuestionVisual(
        kind: VisualKind.coordPlane,
        title: 'İki Nokta Arası Uzaklık',
        summary: 'A($x1, $y1) ve B($x2, $y2) noktalarını birleştiren doğru parçası.',
        values: const [-6, 6, -6, 6],
        elements: [
          DiagramElement(shape: 'line', x: x1.toDouble(), y: y1.toDouble(), endX: x2.toDouble(), endY: y2.toDouble(), color: 'mint'),
          DiagramElement(shape: 'point', x: x1.toDouble(), y: y1.toDouble(), label: 'A($x1,$y1)', color: 'gold'),
          DiagramElement(shape: 'point', x: x2.toDouble(), y: y2.toDouble(), label: 'B($x2,$y2)', color: 'gold'),
        ],
      ),
    );
  } else if (mode == 1) {
    // Midpoint (guaranteed integer coordinates)
    final x1 = -4 + (k % 5);
    final y1 = -4 + ((k ~/ 5) % 5);
    final dx = 2 * (1 + (k % 3));
    final dy = 2 * (1 + ((k ~/ 3) % 3));
    final x2 = x1 + dx;
    final y2 = y1 + dy;
    final mx = (x1 + x2) ~/ 2;
    final my = (y1 + y2) ~/ 2;
    final correct = '($mx, $my)';
    final wrong = <String>{
      '(${mx + 1}, $my)',
      '($mx, ${my + 1})',
      '($my, $mx)',
      '(${mx - 1}, ${my + 1})',
      '(${mx + 1}, ${my - 1})',
    }..remove(correct);
    return AdvancedItem(
      'Koordinat düzlemindeki A($x1, $y1) ve B($x2, $y2) noktalarının orta noktası M hangisidir?',
      correct,
      wrong.take(3).toList(),
      'Orta nokta M = ((x₁+x₂)/2, (y₁+y₂)/2) = (($x1+$x2)/2, ($y1+$y2)/2) = ($mx, $my) olur.',
      visual: QuestionVisual(
        kind: VisualKind.coordPlane,
        title: 'Doğru Parçasının Orta Noktası',
        summary: 'A($x1, $y1) ile B($x2, $y2) noktaları.',
        values: const [-6, 6, -6, 6],
        elements: [
          DiagramElement(shape: 'line', x: x1.toDouble(), y: y1.toDouble(), endX: x2.toDouble(), endY: y2.toDouble(), color: 'blue'),
          DiagramElement(shape: 'point', x: x1.toDouble(), y: y1.toDouble(), label: 'A($x1,$y1)', color: 'gold'),
          DiagramElement(shape: 'point', x: x2.toDouble(), y: y2.toDouble(), label: 'B($x2,$y2)', color: 'gold'),
        ],
      ),
    );
  } else if (mode == 2) {
    // Integer slope
    const slopes = [-3, -2, -1, 1, 2, 3];
    final m = slopes[k % slopes.length];
    final x1 = -2 + (k % 3);
    final y1 = -1 + ((k ~/ 6) % 3);
    final dx = m.abs() == 3 ? 1 : 2;
    final x2 = x1 + dx;
    final y2 = y1 + m * dx;
    final wrong = <String>{'${-m}', '${m + 1}', '${m - 1}', '${m + 2}'}..remove('$m');
    return AdvancedItem(
      'Grafikte A($x1, $y1) ve B($x2, $y2) noktalarından geçen doğrunun eğimi kaçtır?',
      '$m',
      wrong.take(3).toList(),
      'Eğim m = (y₂ − y₁) / (x₂ − x₁) = ($y2 − $y1) / ($x2 − $x1) = $m bulunur.',
      visual: QuestionVisual(
        kind: VisualKind.coordPlane,
        title: 'Doğru Eğimi Analizi',
        summary: 'A($x1, $y1) ve B($x2, $y2) noktalarından geçen doğru.',
        values: const [-6, 6, -6, 6],
        elements: [
          DiagramElement(shape: 'line', x: x1.toDouble(), y: y1.toDouble(), endX: x2.toDouble(), endY: y2.toDouble(), color: 'pink'),
          DiagramElement(shape: 'point', x: x1.toDouble(), y: y1.toDouble(), label: 'A($x1,$y1)', color: 'gold'),
          DiagramElement(shape: 'point', x: x2.toDouble(), y: y2.toDouble(), label: 'B($x2,$y2)', color: 'gold'),
        ],
      ),
    );
  } else if (mode == 3) {
    // Shaded right-triangle area on grid
    final bVal = 2 + (k % 4) * 2; // 2,4,6,8
    final hVal = 2 + ((k ~/ 4) % 4) * 2; // 2,4,6,8
    final x0 = -4 + (k % 2);
    final y0 = -4 + ((k ~/ 16) % 2);
    final area = (bVal * hVal) ~/ 2;
    final wrong = <String>{};
    for (final cand in [area * 2, area + bVal, area + 4, area - 2, area + 6]) {
      if (cand > 0 && cand != area) wrong.add('$cand br²');
      if (wrong.length == 3) break;
    }
    return AdvancedItem(
      'Koordinat düzleminde taralı dik üçgenin alanı kaç birimkaredir?',
      '$area br²',
      wrong.toList(),
      'Taban uzunluğu $bVal birim, yükseklik $hVal birim olduğundan Alan = ($bVal × $hVal) / 2 = $area br² olur.',
      visual: QuestionVisual(
        kind: VisualKind.coordPlane,
        title: 'Koordinat Düzleminde Üçgen Alanı',
        summary: 'Köşeleri ($x0,$y0), (${x0 + bVal},$y0) ve ($x0,${y0 + hVal}) olan dik üçgen.',
        values: const [-5, 6, -5, 6],
        elements: [
          DiagramElement(shape: 'polygon', x: 0, y: 0, label: '$x0,$y0;${x0 + bVal},$y0;$x0,${y0 + hVal}', color: 'mint'),
          DiagramElement(shape: 'point', x: x0.toDouble(), y: y0.toDouble(), label: '($x0,$y0)', color: 'gold'),
          DiagramElement(shape: 'point', x: (x0 + bVal).toDouble(), y: y0.toDouble(), label: '(${x0 + bVal},$y0)', color: 'gold'),
          DiagramElement(shape: 'point', x: x0.toDouble(), y: (y0 + hVal).toDouble(), label: '($x0,${y0 + hVal})', color: 'gold'),
        ],
      ),
    );
  } else {
    // Reflection across X-axis, Y-axis, or Origin
    final px = 1 + (k % 4);
    final py = 1 + ((k ~/ 4) % 4);
    final sx = k.isEven ? px : -px;
    final sy = (k ~/ 2).isEven ? py : -py;
    final axis = k % 3; // 0: X, 1: Y, 2: Origin
    final rx = axis == 0 ? sx : -sx;
    final ry = axis == 1 ? sy : -sy;
    final axisName = axis == 0 ? 'x-eksenine' : (axis == 1 ? 'y-eksenine' : 'orijine');
    final correct = '($rx, $ry)';
    final wrong = <String>{
      '($sx, ${-sy})',
      '(${-sx}, $sy)',
      '(${-sx}, ${-sy})',
      '($sy, $sx)',
      '(${rx + 1}, $ry)',
      '($rx, ${ry + 1})',
      '(${rx - 1}, ${ry - 1})',
    }..remove(correct);
    return AdvancedItem(
      'Koordinat düzlemindeki P($sx, $sy) noktasının $axisName göre simetriği hangisidir?',
      correct,
      wrong.take(3).toList(),
      'P($sx, $sy) noktasının $axisName göre simetriği ($rx, $ry) koordinatlarına karşılık gelir.',
      visual: QuestionVisual(
        kind: VisualKind.coordPlane,
        title: 'Noktanın Simetriği · P($sx, $sy)',
        summary: 'P($sx, $sy) noktası koordinat düzleminde işaretlendi.',
        values: const [-5, 5, -5, 5],
        elements: [
          DiagramElement(shape: 'point', x: sx.toDouble(), y: sy.toDouble(), label: 'P($sx,$sy)', color: 'gold'),
        ],
      ),
    );
  }
}

AdvancedItem _buildCoordVector(int i) {
  // 280 physics vector resultant questions on coordinate plane
  const vecPairs = [
    (3, 0, 0, 4, 5),
    (4, 0, 0, 3, 5),
    (5, 2, -2, 2, 5),
    (2, 4, 1, 0, 5),
    (-3, 0, 0, 4, 5),
    (3, 4, 3, 4, 10),
    (4, 2, 2, 6, 10),
    (5, 0, -2, 4, 5),
    (0, 5, 3, -1, 5),
    (4, -2, 0, 5, 5),
    (2, 3, 2, 0, 5),
    (-4, 1, 1, 3, 5),
    (5, -4, 0, 4, 5),
    (3, 5, 0, -1, 5),
  ];
  final p = vecPairs[i % vecPairs.length];
  final scale = (i ~/ vecPairs.length) % 2 == 0 ? 1 : 1;
  final askCoords = (i ~/ vecPairs.length).isOdd;
  final rx = (p.$1 + p.$3) * scale;
  final ry = (p.$2 + p.$4) * scale;
  final mag = p.$5 * scale;

  final vis = QuestionVisual(
    kind: VisualKind.coordPlane,
    title: 'Kuvvet Vektörleri (1 br = 1 N)',
    summary: 'F₁(${p.$1}, ${p.$2}) N ve F₂(${p.$3}, ${p.$4}) N vektörleri.',
    values: const [-6, 6, -6, 6],
    elements: [
      DiagramElement(shape: 'arrow', x: 0, y: 0, endX: p.$1.toDouble(), endY: p.$2.toDouble(), label: 'F₁', color: 'gold'),
      DiagramElement(shape: 'arrow', x: 0, y: 0, endX: p.$3.toDouble(), endY: p.$4.toDouble(), label: 'F₂', color: 'mint'),
    ],
  );

  if (askCoords) {
    final correct = '($rx, $ry) N';
    return AdvancedItem(
      'Koordinat düzlemindeki F₁(${p.$1}, ${p.$2}) N ve F₂(${p.$3}, ${p.$4}) N vektörlerinin bileşkesi R hangi koordinat çiftidir?',
      correct,
      ['(${rx + 1}, $ry) N', '($rx, ${ry - 1}) N', '(${p.$1 - p.$3}, ${p.$2 - p.$4}) N' == correct ? '(${rx - 1}, ${ry + 1}) N' : '(${p.$1 - p.$3}, ${p.$2 - p.$4}) N'],
      'Bileşke vektör bileşenleri toplanarak bulunur: Rx = ${p.$1} + (${p.$3}) = $rx, Ry = ${p.$2} + (${p.$4}) = $ry → ($rx, $ry) N.',
      visual: vis,
    );
  }
  return AdvancedItem(
    'Şekildeki F₁(${p.$1}, ${p.$2}) N ve F₂(${p.$3}, ${p.$4}) N kuvvetlerinin bileşkesinin büyüklüğü kaç Newton’dur?',
    '$mag N',
    ['${mag + 2} N', '${max(1, mag - 2)} N', '${mag + 4} N'],
    'Bileşke bileşenleri Rx = $rx N, Ry = $ry N olduğundan |R| = √($rx² + $ry²) = $mag N bulunur.',
    visual: vis,
  );
}

// ---------------------------------------------------------------------------
// 5. BOHR ATOM MODELİ & PERİYODİK YÖRÜNGE (480 soru)
// ---------------------------------------------------------------------------
typedef _AtomSpec = ({
  int z,
  int n,
  String sym,
  String name,
  List<int> shells,
  String periodGroup,
  String kind,
  int ionCharge,
  List<int> ionShells,
});

const _atoms = <_AtomSpec>[
  (z: 1, n: 0, sym: 'H', name: 'Hidrojen', shells: [1], periodGroup: '1. Periyot 1A', kind: 'Ametal', ionCharge: 1, ionShells: [0]),
  (z: 2, n: 2, sym: 'He', name: 'Helyum', shells: [2], periodGroup: '1. Periyot 8A', kind: 'Soygaz', ionCharge: 0, ionShells: [2]),
  (z: 3, n: 4, sym: 'Li', name: 'Lityum', shells: [2, 1], periodGroup: '2. Periyot 1A', kind: 'Alkali Metal', ionCharge: 1, ionShells: [2]),
  (z: 4, n: 5, sym: 'Be', name: 'Berilyum', shells: [2, 2], periodGroup: '2. Periyot 2A', kind: 'Toprak Alkali Metal', ionCharge: 2, ionShells: [2]),
  (z: 5, n: 6, sym: 'B', name: 'Bor', shells: [2, 3], periodGroup: '2. Periyot 3A', kind: 'Yarı Metal', ionCharge: 3, ionShells: [2]),
  (z: 6, n: 6, sym: 'C', name: 'Karbon', shells: [2, 4], periodGroup: '2. Periyot 4A', kind: 'Ametal', ionCharge: -4, ionShells: [2, 8]),
  (z: 7, n: 7, sym: 'N', name: 'Azot', shells: [2, 5], periodGroup: '2. Periyot 5A', kind: 'Ametal', ionCharge: -3, ionShells: [2, 8]),
  (z: 8, n: 8, sym: 'O', name: 'Oksijen', shells: [2, 6], periodGroup: '2. Periyot 6A', kind: 'Ametal', ionCharge: -2, ionShells: [2, 8]),
  (z: 9, n: 10, sym: 'F', name: 'Flor', shells: [2, 7], periodGroup: '2. Periyot 7A', kind: 'Halojen (Ametal)', ionCharge: -1, ionShells: [2, 8]),
  (z: 10, n: 10, sym: 'Ne', name: 'Neon', shells: [2, 8], periodGroup: '2. Periyot 8A', kind: 'Soygaz', ionCharge: 0, ionShells: [2, 8]),
  (z: 11, n: 12, sym: 'Na', name: 'Sodyum', shells: [2, 8, 1], periodGroup: '3. Periyot 1A', kind: 'Alkali Metal', ionCharge: 1, ionShells: [2, 8]),
  (z: 12, n: 12, sym: 'Mg', name: 'Magnezyum', shells: [2, 8, 2], periodGroup: '3. Periyot 2A', kind: 'Toprak Alkali Metal', ionCharge: 2, ionShells: [2, 8]),
  (z: 13, n: 14, sym: 'Al', name: 'Alüminyum', shells: [2, 8, 3], periodGroup: '3. Periyot 3A', kind: 'Metal', ionCharge: 3, ionShells: [2, 8]),
  (z: 14, n: 14, sym: 'Si', name: 'Silisyum', shells: [2, 8, 4], periodGroup: '3. Periyot 4A', kind: 'Yarı Metal', ionCharge: 4, ionShells: [2, 8]),
  (z: 15, n: 16, sym: 'P', name: 'Fosfor', shells: [2, 8, 5], periodGroup: '3. Periyot 5A', kind: 'Ametal', ionCharge: -3, ionShells: [2, 8, 8]),
  (z: 16, n: 16, sym: 'S', name: 'Kükürt', shells: [2, 8, 6], periodGroup: '3. Periyot 6A', kind: 'Ametal', ionCharge: -2, ionShells: [2, 8, 8]),
  (z: 17, n: 18, sym: 'Cl', name: 'Klor', shells: [2, 8, 7], periodGroup: '3. Periyot 7A', kind: 'Halojen (Ametal)', ionCharge: -1, ionShells: [2, 8, 8]),
  (z: 18, n: 22, sym: 'Ar', name: 'Argon', shells: [2, 8, 8], periodGroup: '3. Periyot 8A', kind: 'Soygaz', ionCharge: 0, ionShells: [2, 8, 8]),
  (z: 19, n: 20, sym: 'K', name: 'Potasyum', shells: [2, 8, 8, 1], periodGroup: '4. Periyot 1A', kind: 'Alkali Metal', ionCharge: 1, ionShells: [2, 8, 8]),
  (z: 20, n: 20, sym: 'Ca', name: 'Kalsiyum', shells: [2, 8, 8, 2], periodGroup: '4. Periyot 2A', kind: 'Toprak Alkali Metal', ionCharge: 2, ionShells: [2, 8, 8]),
];

AdvancedItem _buildAtomQuestion(int i) {
  // 20 elements × 24 question angles/variants = 480
  final a = _atoms[i % _atoms.length];
  final task = (i ~/ _atoms.length) % 6; // 0..5 (repeats across 4 isotope/angle shifts)
  final isotopeShift = (i ~/ (_atoms.length * 6)) % 4; // 0..3 => distinct neutron count for mass Qs
  final n = task == 3 ? a.n + isotopeShift : a.n;
  final mass = a.z + n;

  final baseVisual = QuestionVisual(
    kind: VisualKind.atom,
    title: 'Bohr Atom Modeli #${i + 1}',
    summary: '${a.z} proton, $n nötron, katmanlar ${a.shells.join("-")}.',
    values: [a.z.toDouble(), n.toDouble(), ...a.shells.map((e) => e.toDouble())],
    labels: [task == 0 ? '?' : a.sym],
    unit: 'Nötr Atom',
  );

  switch (task) {
    case 0:
      return AdvancedItem(
        'Elektron katman dizilimi ve çekirdeği verilen bu nötr atom hangi elementtir?',
        '${a.name} (${a.sym})',
        _pickDistinct(_atoms.map((e) => '${e.name} (${e.sym})').toList(), '${a.name} (${a.sym})', i + 5),
        'Çekirdekte ${a.z} proton bulunduğu için atom numarası Z = ${a.z} olan element ${a.name} (${a.sym}) elementidir.',
        visual: baseVisual,
      );
    case 1:
      final val = a.shells.last;
      return AdvancedItem(
        'Bohr modeli verilen ${a.name} (${a.sym}) atomunun değerlik elektron sayısı kaçtır?',
        '$val',
        _pickDistinct(['1', '2', '3', '4', '5', '6', '7', '8'], '$val', i + 11),
        'En dış katmanda $val elektron bulunduğundan ${a.name} atomunun değerlik elektron sayısı $val olur.',
        visual: baseVisual,
      );
    case 2:
      return AdvancedItem(
        'Katman dizilimi gösterilen ${a.name} (${a.sym}) elementinin periyodik tablodaki yeri neresidir?',
        a.periodGroup,
        _pickDistinct(_atoms.map((e) => e.periodGroup).toSet().toList(), a.periodGroup, i + 17),
        '${a.shells.length} elektron katmanı periyodu, son katmandaki elektron sayısı (Helyum hariç) grubu verir: ${a.periodGroup}.',
        visual: baseVisual,
      );
    case 3:
      return AdvancedItem(
        'Görseldeki ${a.name} (${a.sym}) izotopunun kütle numarası (A) kaçtır?',
        '$mass',
        ['${mass + 1}', '${mass + 2}', '${mass > 1 ? mass - 1 : mass + 3}'],
        'Kütle numarası proton ve nötron toplamıdır: A = ${a.z} + $n = $mass.',
        visual: baseVisual,
      );
    case 4:
      final ionShells = a.ionShells.first == 0 ? a.shells : a.ionShells;
      final eTotal = ionShells.fold<int>(0, (s, v) => s + v);
      final charge = a.z - eTotal;
      final chargeStr = charge == 0 ? '0 (Nötr)' : (charge > 0 ? '+$charge' : '$charge');
      final ionVis = QuestionVisual(
        kind: VisualKind.atom,
        title: 'İyon Yükü Analizi · ${a.sym}',
        summary: '${a.z} proton, toplam $eTotal elektron.',
        values: [a.z.toDouble(), a.n.toDouble(), ...ionShells.map((e) => e.toDouble())],
        labels: [a.sym],
        unit: 'Yük = ?',
      );
      return AdvancedItem(
        'Çekirdeğinde ${a.z} proton, yörüngelerinde toplam $eTotal elektron bulunan bu ${a.name} taneciğinin elektrik yükü nedir?',
        chargeStr,
        _pickDistinct(['0 (Nötr)', '+1', '+2', '+3', '-1', '-2', '-3', '-4'], chargeStr, i + 23),
        'İyon yükü = Proton − Elektron = ${a.z} − $eTotal = $chargeStr olarak hesaplanır.',
        visual: ionVis,
      );
    default:
      return AdvancedItem(
        'Katman yapısı gösterilen ${a.name} (${a.sym}) elementi hangi sınıfa girer?',
        a.kind,
        _pickDistinct(['Alkali Metal', 'Toprak Alkali Metal', 'Metal', 'Yarı Metal', 'Ametal', 'Halojen (Ametal)', 'Soygaz'], a.kind, i + 31),
        '${a.name} (${a.periodGroup}) periyodik tabloda ${a.kind} sınıfında yer alır.',
        visual: baseVisual,
      );
  }
}

// ---------------------------------------------------------------------------
// 6. MÜZİK PORTESİ, NOTA, ARALIK VE AKOR GÖRSELİ (480 soru)
// ---------------------------------------------------------------------------
typedef _NoteInfo = ({String token, String trName, String clef});

const _trebleNotes = <_NoteInfo>[
  (token: 'C4', trName: 'Do (C4)', clef: 'treble'),
  (token: 'D4', trName: 'Re (D4)', clef: 'treble'),
  (token: 'E4', trName: 'Mi (E4)', clef: 'treble'),
  (token: 'F4', trName: 'Fa (F4)', clef: 'treble'),
  (token: 'F#4', trName: 'Fa Diyez (F♯4)', clef: 'treble'),
  (token: 'G4', trName: 'Sol (G4)', clef: 'treble'),
  (token: 'A4', trName: 'La (A4)', clef: 'treble'),
  (token: 'Bb4', trName: 'Si Bemol (B♭4)', clef: 'treble'),
  (token: 'B4', trName: 'Si (B4)', clef: 'treble'),
  (token: 'C5', trName: 'İnce Do (C5)', clef: 'treble'),
  (token: 'D5', trName: 'İnce Re (D5)', clef: 'treble'),
  (token: 'E5', trName: 'İnce Mi (E5)', clef: 'treble'),
  (token: 'F5', trName: 'İnce Fa (F5)', clef: 'treble'),
  (token: 'G5', trName: 'İnce Sol (G5)', clef: 'treble'),
];

const _bassNotes = <_NoteInfo>[
  (token: 'G2', trName: 'Kalın Sol (G2)', clef: 'bass'),
  (token: 'A2', trName: 'Kalın La (A2)', clef: 'bass'),
  (token: 'B2', trName: 'Kalın Si (B2)', clef: 'bass'),
  (token: 'C3', trName: 'Do (C3)', clef: 'bass'),
  (token: 'D3', trName: 'Re (D3)', clef: 'bass'),
  (token: 'E3', trName: 'Mi (E3)', clef: 'bass'),
  (token: 'F3', trName: 'Fa (F3)', clef: 'bass'),
  (token: 'G3', trName: 'Sol (G3)', clef: 'bass'),
  (token: 'A3', trName: 'La (A3)', clef: 'bass'),
  (token: 'C4', trName: 'Orta Do (C4)', clef: 'bass'),
];

typedef _ChordInfo = ({String name, List<String> notes, String explain});
const _chords = <_ChordInfo>[
  (name: 'Do Majör (C)', notes: ['C4', 'E4', 'G4'], explain: 'Do – Mi – Sol sesleri Do Majör üçlü akorunu oluşturur.'),
  (name: 'La Minör (Am)', notes: ['A4', 'C5', 'E5'], explain: 'La – Do – Mi sesleri La Minör üçlü akorunu oluşturur.'),
  (name: 'Sol Majör (G)', notes: ['G4', 'B4', 'D5'], explain: 'Sol – Si – Re sesleri Sol Majör akorudur.'),
  (name: 'Fa Majör (F)', notes: ['F4', 'A4', 'C5'], explain: 'Fa – La – Do sesleri Fa Majör akorudur.'),
  (name: 'Re Minör (Dm)', notes: ['D4', 'F4', 'A4'], explain: 'Re – Fa – La sesleri Re Minör akorudur.'),
  (name: 'Mi Minör (Em)', notes: ['E4', 'G4', 'B4'], explain: 'Mi – Sol – Si sesleri Mi Minör akorudur.'),
  (name: 'Re Majör (D)', notes: ['D4', 'F#4', 'A4'], explain: 'Re – Fa♯ – La sesleri Re Majör akorudur.'),
  (name: 'Mi Majör (E)', notes: ['E4', 'G#4', 'B4'], explain: 'Mi – Sol♯ – Si sesleri Mi Majör akorudur.'),
  (name: 'Si Bemol Majör (B♭)', notes: ['Bb4', 'D5', 'F5'], explain: 'Si♭ – Re – Fa sesleri Si Bemol Majör akorudur.'),
  (name: 'La Majör (A)', notes: ['A4', 'C#5', 'E5'], explain: 'La – Do♯ – Mi sesleri La Majör akorudur.'),
];

typedef _IntervalInfo = ({String name, List<String> notes, int semitones});
const _intervals = <_IntervalInfo>[
  (name: 'Büyük İkili (M2)', notes: ['C4', 'D4'], semitones: 2),
  (name: 'Küçük Üçlü (m3)', notes: ['A4', 'C5'], semitones: 3),
  (name: 'Büyük Üçlü (M3)', notes: ['C4', 'E4'], semitones: 4),
  (name: 'Tam Dörtlü (P4)', notes: ['C4', 'F4'], semitones: 5),
  (name: 'Tam Beşli (P5)', notes: ['C4', 'G4'], semitones: 7),
  (name: 'Büyük Altılı (M6)', notes: ['C4', 'A4'], semitones: 9),
  (name: 'Büyük Yedili (M7)', notes: ['C4', 'B4'], semitones: 11),
  (name: 'Tam Oktav (P8)', notes: ['C4', 'C5'], semitones: 12),
  (name: 'Tam Beşli (P5)', notes: ['G4', 'D5'], semitones: 7),
  (name: 'Tam Dörtlü (P4)', notes: ['G4', 'C5'], semitones: 5),
  (name: 'Büyük Üçlü (M3)', notes: ['F4', 'A4'], semitones: 4),
  (name: 'Küçük Üçlü (m3)', notes: ['E4', 'G4'], semitones: 3),
];

AdvancedItem _buildMusicStaff(int i) {
  final kind = i % 4; // 0: Treble note, 1: Bass note, 2: Chord, 3: Interval
  final k = i ~/ 4;
  if (kind == 0) {
    final n = _trebleNotes[k % _trebleNotes.length];
    return AdvancedItem(
      'Sol anahtarlı (𝄞) portede gösterilen nota hangisidir?',
      n.trName,
      _pickDistinct(_trebleNotes.map((e) => e.trName).toList(), n.trName, i + 7),
      'Sol anahtarında 2. çizgi Sol (G4) referans alınarak sayıldığında bu nota ${n.trName} olarak okunur.',
      visual: QuestionVisual(
        kind: VisualKind.musicStaff,
        title: 'Sol Anahtarı Nota Okuma',
        summary: 'Sol anahtarında ${n.token} notası.',
        unit: 'treble',
        labels: [n.token],
      ),
    );
  } else if (kind == 1) {
    final n = _bassNotes[k % _bassNotes.length];
    return AdvancedItem(
      'Fa anahtarlı (𝄢) portede gösterilen nota hangisidir?',
      n.trName,
      _pickDistinct(_bassNotes.map((e) => e.trName).toList(), n.trName, i + 13),
      'Fa anahtarında 4. çizgi Fa (F3) kabul edilir; buna göre porte üzerindeki nota ${n.trName} sesidir.',
      visual: QuestionVisual(
        kind: VisualKind.musicStaff,
        title: 'Fa Anahtarı Nota Okuma',
        summary: 'Fa anahtarında ${n.token} notası.',
        unit: 'bass',
        labels: [n.token],
      ),
    );
  } else if (kind == 2) {
    final ch = _chords[k % _chords.length];
    return AdvancedItem(
      'Portede üst üste dizilmiş üç sesten oluşan bu akor hangisidir?',
      ch.name,
      _pickDistinct(_chords.map((e) => e.name).toList(), ch.name, i + 19),
      ch.explain,
      visual: QuestionVisual(
        kind: VisualKind.musicStaff,
        title: 'Akor Tanıma Stüdyosu',
        summary: 'Üçlü akor: ${ch.notes.join(" + ")}.',
        unit: 'treble',
        columns: const ['chord'],
        labels: ch.notes,
      ),
    );
  } else {
    final iv = _intervals[k % _intervals.length];
    final askSemitone = (k ~/ _intervals.length).isOdd;
    final vis = QuestionVisual(
      kind: VisualKind.musicStaff,
      title: 'Müzik Aralığı Analizi',
      summary: '${iv.notes[0]} ile ${iv.notes[1]} arasındaki aralık.',
      unit: 'treble',
      labels: iv.notes,
    );
    if (askSemitone) {
      return AdvancedItem(
        'Portede sırayla gösterilen iki nota arasındaki uzaklık kaç yarım sesten oluşur?',
        '${iv.semitones} yarım ses',
        _pickDistinct(['2 yarım ses', '3 yarım ses', '4 yarım ses', '5 yarım ses', '7 yarım ses', '9 yarım ses', '11 yarım ses', '12 yarım ses'], '${iv.semitones} yarım ses', i + 23),
        '${iv.notes[0]} – ${iv.notes[1]} aralığı ${iv.name} olup tam ${iv.semitones} yarım sesten oluşur.',
        visual: vis,
      );
    }
    return AdvancedItem(
      'Portede sırayla verilen iki nota hangi müzik aralığını oluşturur?',
      iv.name,
      _pickDistinct(_intervals.map((e) => e.name).toSet().toList(), iv.name, i + 29),
      '${iv.notes[0]} ile ${iv.notes[1]} arasında ${iv.semitones} yarım ses vardır; bu aralık ${iv.name} olarak adlandırılır.',
      visual: vis,
    );
  }
}

// ---------------------------------------------------------------------------
// 7. 3×3 GÖRSEL ZEKA & ŞEKİL ÖRÜNTÜSÜ MATRİSİ (600 soru)
// ---------------------------------------------------------------------------
const _mShapes = [
  ('circle', 'Daire'),
  ('square', 'Kare'),
  ('triangle', 'Üçgen'),
  ('diamond', 'Eşkenar Dörtgen'),
  ('hexagon', 'Altıgen'),
  ('star', 'Yıldız'),
];
const _mColors = [
  ('gold', 'Altın'),
  ('cyan', 'Turkuaz'),
  ('coral', 'Mercan'),
  ('mint', 'Zümrüt'),
  ('violet', 'Mor'),
];
const _mFills = [
  ('solid', 'Dolu'),
  ('outline', 'Çerçeve'),
  ('dot', 'Noktalı'),
];

AdvancedItem _buildMatrixIq(int i) {
  final rule = i % 4; // 0: Latin square shape+color, 1: Count +1 per col, 2: Rotation +90 deg, 3: Fill + shape cycle
  final k = i ~/ 4; // 0..149

  if (rule == 0) {
    // Latin square: 3 shapes & 3 colors each appear once per row & column
    final sOff = k % _mShapes.length;
    final cOff = (k ~/ 6) % _mColors.length;
    final shapes = [_mShapes[sOff % 6], _mShapes[(sOff + 1) % 6], _mShapes[(sOff + 2) % 6]];
    final colors = [_mColors[cOff % 5], _mColors[(cOff + 1) % 5], _mColors[(cOff + 2) % 5]];
    final fill = _mFills[k % 3];
    final grid = List.generate(3, (r) {
      return List.generate(3, (c) {
        if (r == 2 && c == 2) return '?';
        final sh = shapes[(r + c) % 3].$1;
        final co = colors[(r + 2 * c) % 3].$1;
        return '$sh:1:$co:0:${fill.$1}';
      });
    });
    final ansSh = shapes[(2 + 2) % 3];
    final ansCo = colors[(2 + 4) % 3];
    final correct = '${ansCo.$2} ${ansSh.$2} (${fill.$2})';
    final wrong = [
      '${colors[0].$2 == ansCo.$2 ? colors[1].$2 : colors[0].$2} ${ansSh.$2} (${fill.$2})',
      '${ansCo.$2} ${shapes[0].$2 == ansSh.$2 ? shapes[1].$2 : shapes[0].$2} (${fill.$2})',
      '${colors[1].$2 == ansCo.$2 ? colors[2].$2 : colors[1].$2} ${shapes[2].$2 == ansSh.$2 ? shapes[0].$2 : shapes[2].$2} (${fill.$2})',
    ];
    return AdvancedItem(
      '3×3 görsel örüntü matrisinde her satır ve sütunda şekil ile renk birer kez yer alıyor. "?" hücresine ne gelmelidir?',
      correct,
      wrong,
      '3. satır ve 3. sütunda eksik kalan şekil ${ansSh.$2}, eksik kalan renk ise ${ansCo.$2} olduğundan doğru parça "$correct" olur.',
      visual: QuestionVisual(
        kind: VisualKind.matrix,
        title: 'Görsel Mantık Matrisi #${i + 1}',
        summary: 'Her satır ve sütunda şekil ve renk benzersizdir.',
        rows: grid,
      ),
    );
  } else if (rule == 1) {
    // Count progression across columns: 1 -> 2 -> 3 or 2 -> 3 -> 4
    final baseCount = k.isEven ? 1 : 2;
    final rowsShapes = [_mShapes[k % 6], _mShapes[(k + 2) % 6], _mShapes[(k + 4) % 6]];
    final rowsColors = [_mColors[k % 5], _mColors[(k + 1) % 5], _mColors[(k + 2) % 5]];
    final grid = List.generate(3, (r) {
      return List.generate(3, (c) {
        if (r == 2 && c == 2) return '?';
        return '${rowsShapes[r].$1}:${baseCount + c}:${rowsColors[r].$1}:0:solid';
      });
    });
    final targetCount = baseCount + 2;
    final sh = rowsShapes[2];
    final co = rowsColors[2];
    final correct = '$targetCount adet ${co.$2} ${sh.$2}';
    return AdvancedItem(
      'Matriste her satır soldan sağa düzenli bir sayı artış kuralı izliyor. "?" kutusuna hangisi gelmelidir?',
      correct,
      [
        '${targetCount - 1} adet ${co.$2} ${sh.$2}',
        '$targetCount adet ${rowsColors[1].$2} ${sh.$2}',
        '$targetCount adet ${co.$2} ${rowsShapes[1].$2}',
      ],
      'Her satırda şekil sayısı soldan sağa +1 artıyor ($baseCount → ${baseCount + 1} → $targetCount); son satırın rengi ${co.$2}, şekli ${sh.$2}.',
      visual: QuestionVisual(
        kind: VisualKind.matrix,
        title: 'Sayı & Şekil Örüntüsü #${i + 1}',
        summary: 'Soldan sağa artan şekil adedi kuralı.',
        rows: grid,
      ),
    );
  } else if (rule == 2) {
    // Clockwise 90-degree arrow rotation
    const dirs = [(0, 'Yukarı (0°)'), (90, 'Sağa (90°)'), (180, 'Aşağı (180°)'), (270, 'Sola (270°)')];
    final startIdx = k % 4;
    final col = _mColors[k % 5];
    final grid = List.generate(3, (r) {
      return List.generate(3, (c) {
        if (r == 2 && c == 2) return '?';
        final deg = dirs[(startIdx + r + c) % 4].$1;
        return 'arrow:1:${col.$1}:$deg:solid';
      });
    });
    final ansDir = dirs[(startIdx + 4) % 4];
    final correct = '${ansDir.$2} bakan ${col.$2} Ok';
    final wrong = [
      for (final d in dirs)
        if (d.$1 != ansDir.$1) '${d.$2} bakan ${col.$2} Ok',
    ];
    return AdvancedItem(
      'Her adımda saat yönünde 90° dönen ok matrisinde "?" yerine hangi yöndeki ok gelmelidir?',
      correct,
      wrong,
      'Her satırda ve sütunda ok saat yönünde 90° döndüğünden 3. satır 3. sütunda yön ${ansDir.$2} olur.',
      visual: QuestionVisual(
        kind: VisualKind.matrix,
        title: 'Dönüşüm & Açı Matrisi #${i + 1}',
        summary: 'Saat yönünde 90° dönen ok örüntüsü.',
        rows: grid,
      ),
    );
  } else {
    // Fill pattern cycle: solid -> outline -> dot across each row
    final col = _mColors[k % 5];
    final shapes = [_mShapes[k % 6], _mShapes[(k + 1) % 6], _mShapes[(k + 2) % 6]];
    final shift = k % 3;
    final grid = List.generate(3, (r) {
      return List.generate(3, (c) {
        if (r == 2 && c == 2) return '?';
        final f = _mFills[(c + r + shift) % 3].$1;
        return '${shapes[r].$1}:1:${col.$1}:0:$f';
      });
    });
    final ansFill = _mFills[(4 + shift) % 3];
    final sh = shapes[2];
    final correct = '${ansFill.$2} ${col.$2} ${sh.$2}';
    final wrong = [
      for (final f in _mFills)
        if (f.$1 != ansFill.$1) '${f.$2} ${col.$2} ${sh.$2}',
      '${ansFill.$2} ${col.$2} ${shapes[0].$2}',
    ];
    return AdvancedItem(
      'Her satırda dolgu stili (Dolu, Çerçeve, Noktalı) birer kez kullanılıyor. "?" hücresini hangisi tamamlar?',
      correct,
      wrong,
      'Son satırda ${sh.$2} şekli kullanılıyor ve eksik kalan dolgu stili "${ansFill.$2}" olduğu için yanıt "$correct" olur.',
      visual: QuestionVisual(
        kind: VisualKind.matrix,
        title: 'Dolgu Döngüsü Matrisi #${i + 1}',
        summary: 'Dolu, Çerçeve ve Noktalı dolgu örüntüsü.',
        rows: grid,
      ),
    );
  }
}

final List<AdvancedFamily> visualStudio4kFamilies = [
  AdvancedFamily(
    key: 'st10k_flag_country',
    title: 'Dünya Bayrakları Görsel Atlası',
    topic: Topic.geography,
    level: StudyLevel.lise,
    count: 320,
    difficulty: Difficulty.easy,
    visualKind: VisualKind.flag,
    bloom: BloomLevel.hatirlama,
    sourceLabel: 'Bilgili 3.20 · Görsel Stüdyo',
    build: _buildFlagCountry,
  ),
  AdvancedFamily(
    key: 'st10k_flag_meta',
    title: 'Bayrak, Simgeler ve ISO Kodları',
    topic: Topic.culture,
    level: StudyLevel.lise,
    count: 320,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.flag,
    bloom: BloomLevel.anlama,
    sourceLabel: 'Bilgili 3.20 · Görsel Stüdyo',
    build: _buildFlagMeta,
  ),
  AdvancedFamily(
    key: 'st10k_clock_angle',
    title: 'Analog Saat & Akrep-Yelkovan Açısı',
    topic: Topic.mathematics,
    level: StudyLevel.lise,
    count: 240,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.clock,
    bloom: BloomLevel.uygulama,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
    sourceLabel: 'Bilgili 3.20 · Görsel Stüdyo',
    build: _buildClockAngle,
  ),
  AdvancedFamily(
    key: 'st10k_clock_english',
    title: 'Görsel İngilizce Saat Okuma',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 240,
    difficulty: Difficulty.easy,
    visualKind: VisualKind.clock,
    bloom: BloomLevel.uygulama,
    exam: ExamKind.lgs,
    lesson: 'İngilizce',
    sourceLabel: 'Bilgili 3.20 · Görsel Stüdyo',
    build: _buildClockEnglish,
  ),
  AdvancedFamily(
    key: 'st10k_clock_tz',
    title: 'Dünya Saat Dilimleri Kadranı',
    topic: Topic.geography,
    level: StudyLevel.lise,
    count: 160,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.clock,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.20 · Görsel Stüdyo',
    build: _buildClockTimeZone,
  ),
  AdvancedFamily(
    key: 'st10k_pie_econ',
    title: '3D Pasta Grafiği · Ekonomi & Veri',
    topic: Topic.economics,
    level: StudyLevel.lise,
    count: 260,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.pieChart,
    bloom: BloomLevel.analiz,
    sourceLabel: 'Bilgili 3.20 · Görsel Stüdyo',
    build: (i) => _buildPieQuestion(i, _econPieThemes, true),
  ),
  AdvancedFamily(
    key: 'st10k_pie_sci',
    title: '3D Pasta Grafiği · Doğa & Enerji',
    topic: Topic.nature,
    level: StudyLevel.lise,
    count: 260,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.pieChart,
    bloom: BloomLevel.analiz,
    sourceLabel: 'Bilgili 3.20 · Görsel Stüdyo',
    build: (i) => _buildPieQuestion(i, _sciPieThemes, false),
  ),
  AdvancedFamily(
    key: 'st10k_coord_geo',
    title: 'Koordinat Düzlemi & Analitik Geometri',
    topic: Topic.mathematics,
    level: StudyLevel.lise,
    count: 360,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.coordPlane,
    bloom: BloomLevel.uygulama,
    exam: ExamKind.ayt,
    lesson: 'Matematik',
    sourceLabel: 'Bilgili 3.20 · Görsel Stüdyo',
    build: _buildCoordGeometry,
  ),
  AdvancedFamily(
    key: 'st10k_coord_vec',
    title: 'Vektör Bileşkesi & Fizik Düzlemi',
    topic: Topic.physics,
    level: StudyLevel.lise,
    count: 280,
    difficulty: Difficulty.hard,
    visualKind: VisualKind.coordPlane,
    bloom: BloomLevel.uygulama,
    exam: ExamKind.ayt,
    lesson: 'Fizik',
    sourceLabel: 'Bilgili 3.20 · Görsel Stüdyo',
    build: _buildCoordVector,
  ),
  AdvancedFamily(
    key: 'st10k_atom_bohr',
    title: 'Bohr Atom Modeli & Elektron Katmanları',
    topic: Topic.chemistry,
    level: StudyLevel.lise,
    count: 480,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.atom,
    bloom: BloomLevel.analiz,
    exam: ExamKind.tyt,
    lesson: 'Kimya',
    sourceLabel: 'Bilgili 3.20 · Görsel Stüdyo',
    build: _buildAtomQuestion,
  ),
  AdvancedFamily(
    key: 'st10k_music_staff',
    title: 'Müzik Portesi, Nota, Aralık & Akor',
    topic: Topic.music,
    level: StudyLevel.lise,
    count: 480,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.musicStaff,
    bloom: BloomLevel.anlama,
    sourceLabel: 'Bilgili 3.20 · Görsel Stüdyo',
    build: _buildMusicStaff,
  ),
  AdvancedFamily(
    key: 'st10k_matrix_iq',
    title: '3×3 Görsel Mantık & Örüntü Matrisi',
    topic: Topic.computing,
    level: StudyLevel.lise,
    count: 600,
    difficulty: Difficulty.hard,
    visualKind: VisualKind.matrix,
    bloom: BloomLevel.analiz,
    sourceLabel: 'Bilgili 3.20 · Görsel Stüdyo',
    build: _buildMatrixIq,
  ),
];
