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
  var cursor = (seed * 19 + 7) % n;
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
  int maxVal = 999999,
  List<int> deltas = const [1, -1, 2, -2, 3, -3, 5, -5, 4, -4, 6, 10, -10, 8],
}) {
  final out = <String>[];
  final seen = <int>{correct};
  final offset = seed.abs() % deltas.length;
  for (var k = 0; k < deltas.length * 2 && out.length < 3; k++) {
    final d = deltas[(offset + k) % deltas.length];
    final v = correct + d;
    if (v >= minVal && v <= maxVal && seen.add(v)) {
      out.add('$v$suffix');
    }
  }
  var bump = 1;
  while (out.length < 3) {
    final v = correct + bump;
    if (v <= maxVal && seen.add(v)) {
      out.add('$v$suffix');
    } else {
      final v2 = correct - bump;
      if (v2 >= minVal && seen.add(v2)) {
        out.add('$v2$suffix');
      }
    }
    bump++;
  }
  return out;
}

// ===========================================================================
// 1. DERİN DÜNYA BAYRAKLARI ATLASI (64 Ülke × 50 varyasyon = 3.200 soru)
// ===========================================================================
typedef _FlagData = ({
  String code,
  String name,
  String enName,
  String capital,
  String continent,
  String currency,
  String lang,
  String landmark,
  String region,
  String hemisphere,
});

const _flags64 = <_FlagData>[
  (code: 'TR', name: 'Türkiye', enName: 'Turkey', capital: 'Ankara', continent: 'Asya ve Avrupa', currency: 'Türk Lirası', lang: 'Türkçe', landmark: 'Ayasofya ve Kapadokya', region: 'Anadolu ve Doğu Akdeniz', hemisphere: 'Kuzey Yarımküre'),
  (code: 'JP', name: 'Japonya', enName: 'Japan', capital: 'Tokyo', continent: 'Asya', currency: 'Japon Yeni', lang: 'Japonca', landmark: 'Fuji Dağı', region: 'Doğu Asya ada ülkesi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'BD', name: 'Bangladeş', enName: 'Bangladesh', capital: 'Dakka', continent: 'Asya', currency: 'Taka', lang: 'Bengalce', landmark: 'Sundarbans Mangrov Ormanı', region: 'Güney Asya Bengal Körfezi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'FR', name: 'Fransa', enName: 'France', capital: 'Paris', continent: 'Avrupa', currency: 'Euro', lang: 'Fransızca', landmark: 'Eyfel Kulesi', region: 'Batı Avrupa', hemisphere: 'Kuzey Yarımküre'),
  (code: 'IT', name: 'İtalya', enName: 'Italy', capital: 'Roma', continent: 'Avrupa', currency: 'Euro', lang: 'İtalyanca', landmark: 'Kolezyum', region: 'Güney Avrupa Akdeniz yarımadası', hemisphere: 'Kuzey Yarımküre'),
  (code: 'IE', name: 'İrlanda', enName: 'Ireland', capital: 'Dublin', continent: 'Avrupa', currency: 'Euro', lang: 'İngilizce ve İrlandaca', landmark: 'Moher Kayalıkları', region: 'Kuzeybatı Avrupa ada ülkesi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'BE', name: 'Belçika', enName: 'Belgium', capital: 'Brüksel', continent: 'Avrupa', currency: 'Euro', lang: 'Felemenkçe ve Fransızca', landmark: 'Atomium ve Grand-Place', region: 'Batı Avrupa Benelüks', hemisphere: 'Kuzey Yarımküre'),
  (code: 'RO', name: 'Romanya', enName: 'Romania', capital: 'Bükreş', continent: 'Avrupa', currency: 'Rumen Leyi', lang: 'Rumence', landmark: 'Bran Şatosu ve Karpatlar', region: 'Güneydoğu Avrupa Karadeniz kıyısı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'NG', name: 'Nijerya', enName: 'Nigeria', capital: 'Abuja', continent: 'Afrika', currency: 'Naira', lang: 'İngilizce', landmark: 'Zuma Kayası', region: 'Batı Afrika Gine Körfezi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'PE', name: 'Peru', enName: 'Peru', capital: 'Lima', continent: 'Güney Amerika', currency: 'Sol', lang: 'İspanyolca', landmark: 'Machu Picchu Antik Kenti', region: 'And Dağları Pasifik kıyısı', hemisphere: 'Güney Yarımküre'),
  (code: 'MX', name: 'Meksika', enName: 'Mexico', capital: 'Meksiko', continent: 'Kuzey Amerika', currency: 'Meksika Pesosu', lang: 'İspanyolca', landmark: 'Chichén Itzá Piramidi', region: 'Kuzey Amerika güney kuşağı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'CA', name: 'Kanada', enName: 'Canada', capital: 'Ottawa', continent: 'Kuzey Amerika', currency: 'Kanada Doları', lang: 'İngilizce ve Fransızca', landmark: 'Niagara Şelalesi ve Banff', region: 'Kuzey Amerika kuzey kuşağı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'DE', name: 'Almanya', enName: 'Germany', capital: 'Berlin', continent: 'Avrupa', currency: 'Euro', lang: 'Almanca', landmark: 'Brandenburg Kapısı', region: 'Orta Avrupa', hemisphere: 'Kuzey Yarımküre'),
  (code: 'NL', name: 'Hollanda', enName: 'Netherlands', capital: 'Amsterdam', continent: 'Avrupa', currency: 'Euro', lang: 'Felemenkçe', landmark: 'Kinderdijk Yel Değirmenleri', region: 'Batı Avrupa Kuzey Denizi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'RU', name: 'Rusya', enName: 'Russia', capital: 'Moskova', continent: 'Asya ve Avrupa', currency: 'Rus Rublesi', lang: 'Rusça', landmark: 'Kızıl Meydan ve Baykal Gölü', region: 'Doğu Avrupa ve Kuzey Asya', hemisphere: 'Kuzey Yarımküre'),
  (code: 'AT', name: 'Avusturya', enName: 'Austria', capital: 'Viyana', continent: 'Avrupa', currency: 'Euro', lang: 'Almanca', landmark: 'Schönbrunn Sarayı ve Alpler', region: 'Orta Avrupa Alp ülkesi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'HU', name: 'Macaristan', enName: 'Hungary', capital: 'Budapeşte', continent: 'Avrupa', currency: 'Forint', lang: 'Macarca', landmark: 'Tuna Nehri ve Parlamento Binası', region: 'Orta Avrupa Karpat Havzası', hemisphere: 'Kuzey Yarımküre'),
  (code: 'BG', name: 'Bulgaristan', enName: 'Bulgaria', capital: 'Sofya', continent: 'Avrupa', currency: 'Bulgar Levası', lang: 'Bulgarca', landmark: 'Rila Manastırı ve Gül Vadisi', region: 'Balkanlar ve Karadeniz kıyısı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'PL', name: 'Polonya', enName: 'Poland', capital: 'Varşova', continent: 'Avrupa', currency: 'Zloti', lang: 'Lehçe', landmark: 'Kraków Tarihi Merkezi', region: 'Orta Avrupa Baltık kıyısı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'ID', name: 'Endonezya', enName: 'Indonesia', capital: 'Cakarta', continent: 'Asya', currency: 'Endonezya Rupiahı', lang: 'Endonezce', landmark: 'Borobudur Tapınağı ve Bali', region: 'Güneydoğu Asya takımada ülkesi', hemisphere: 'Her İki Yarımküre'),
  (code: 'UA', name: 'Ukrayna', enName: 'Ukraine', capital: 'Kiev', continent: 'Avrupa', currency: 'Grivna', lang: 'Ukraynaca', landmark: 'Aziz Sofya Katedrali ve Dinyeper', region: 'Doğu Avrupa Karadeniz kuzeyi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'ES', name: 'İspanya', enName: 'Spain', capital: 'Madrid', continent: 'Avrupa', currency: 'Euro', lang: 'İspanyolca', landmark: 'Sagrada Família ve El Hamra', region: 'İber Yarımadası Güneybatı Avrupa', hemisphere: 'Kuzey Yarımküre'),
  (code: 'AR', name: 'Arjantin', enName: 'Argentina', capital: 'Buenos Aires', continent: 'Güney Amerika', currency: 'Arjantin Pesosu', lang: 'İspanyolca', landmark: 'Patagonya ve Iguazú Şelalesi', region: 'Güney Amerika güney konisi', hemisphere: 'Güney Yarımküre'),
  (code: 'CO', name: 'Kolombiya', enName: 'Colombia', capital: 'Bogotá', continent: 'Güney Amerika', currency: 'Kolombiya Pesosu', lang: 'İspanyolca', landmark: 'Cartagena Surları', region: 'Güney Amerika kuzeybatısı', hemisphere: 'Her İki Yarımküre'),
  (code: 'TH', name: 'Tayland', enName: 'Thailand', capital: 'Bangkok', continent: 'Asya', currency: 'Baht', lang: 'Tayca', landmark: 'Büyük Saray ve Ayutthaya', region: 'Güneydoğu Asya Çinhindi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'IN', name: 'Hindistan', enName: 'India', capital: 'Yeni Delhi', continent: 'Asya', currency: 'Hint Rupisi', lang: 'Hintçe ve İngilizce', landmark: 'Tac Mahal', region: 'Güney Asya Hint Yarımadası', hemisphere: 'Kuzey Yarımküre'),
  (code: 'EG', name: 'Mısır', enName: 'Egypt', capital: 'Kahire', continent: 'Afrika', currency: 'Mısır Lirası', lang: 'Arapça', landmark: 'Gize Piramitleri ve Nil Nehri', region: 'Kuzeydoğu Afrika Süveyş bölgesi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'GH', name: 'Gana', enName: 'Ghana', capital: 'Akra', continent: 'Afrika', currency: 'Gana Sedisi', lang: 'İngilizce', landmark: 'Volta Gölü ve Cape Coast Kalesi', region: 'Batı Afrika Atlantik kıyısı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'ET', name: 'Etiyopya', enName: 'Ethiopia', capital: 'Addis Ababa', continent: 'Afrika', currency: 'Birr', lang: 'Amharca', landmark: 'Lalibela Kaya Kiliseleri', region: 'Doğu Afrika Boynuzu', hemisphere: 'Kuzey Yarımküre'),
  (code: 'AZ', name: 'Azerbaycan', enName: 'Azerbaijan', capital: 'Bakü', continent: 'Asya ve Avrupa', currency: 'Azerbaycan Manatı', lang: 'Azerbaycanca', landmark: 'Alev Kuleleri ve Kız Kulesi', region: 'Güney Kafkasya Hazar kıyısı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'UZ', name: 'Özbekistan', enName: 'Uzbekistan', capital: 'Taşkent', continent: 'Asya', currency: 'Özbek Somu', lang: 'Özbekçe', landmark: 'Semerkant Registan Meydanı', region: 'Orta Asya İpek Yolu merkezi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'SE', name: 'İsveç', enName: 'Sweden', capital: 'Stockholm', continent: 'Avrupa', currency: 'İsveç Kronu', lang: 'İsveççe', landmark: 'Vasa Müzesi ve Nobel Salonu', region: 'Kuzey Avrupa İskandinavya', hemisphere: 'Kuzey Yarımküre'),
  (code: 'FI', name: 'Finlandiya', enName: 'Finland', capital: 'Helsinki', continent: 'Avrupa', currency: 'Euro', lang: 'Fince ve İsveççe', landmark: 'Laponya ve bin göller yöresi', region: 'Kuzey Avrupa Baltık kıyısı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'DK', name: 'Danimarka', enName: 'Denmark', capital: 'Kopenhag', continent: 'Avrupa', currency: 'Danimarka Kronu', lang: 'Danca', landmark: 'Nyhavn Limanı ve Kronborg Kalesi', region: 'Kuzey Avrupa Jutland yarımadası', hemisphere: 'Kuzey Yarımküre'),
  (code: 'NO', name: 'Norveç', enName: 'Norway', capital: 'Oslo', continent: 'Avrupa', currency: 'Norveç Kronu', lang: 'Norveççe', landmark: 'Geiranger Fiyordu', region: 'Kuzey Avrupa Atlantik kıyısı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'IS', name: 'İzlanda', enName: 'Iceland', capital: 'Reykjavik', continent: 'Avrupa', currency: 'İzlanda Kronası', lang: 'İzlandaca', landmark: 'Geysir ve Mavi Lagün', region: 'Kuzey Atlantik volkanik ada', hemisphere: 'Kuzey Yarımküre'),
  (code: 'CH', name: 'İsviçre', enName: 'Switzerland', capital: 'Bern', continent: 'Avrupa', currency: 'İsviçre Frangı', lang: 'Almanca ve Fransızca', landmark: 'Matterhorn Zirvesi ve Cenevre Gölü', region: 'Orta Avrupa Alp Konfederasyonu', hemisphere: 'Kuzey Yarımküre'),
  (code: 'GE', name: 'Gürcistan', enName: 'Georgia', capital: 'Tiflis', continent: 'Asya ve Avrupa', currency: 'Gürcü Larisi', lang: 'Gürcüce', landmark: 'Kazbek Dağı ve Eski Tiflis', region: 'Güney Kafkasya Karadeniz kıyısı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'GB', name: 'Birleşik Krallık', enName: 'United Kingdom', capital: 'Londra', continent: 'Avrupa', currency: 'İngiliz Sterlini', lang: 'İngilizce', landmark: 'Big Ben ve Stonehenge', region: 'Kuzeybatı Avrupa Britanya Adaları', hemisphere: 'Kuzey Yarımküre'),
  (code: 'US', name: 'Amerika Birleşik Devletleri', enName: 'United States', capital: 'Washington D.C.', continent: 'Kuzey Amerika', currency: 'Amerikan Doları', lang: 'İngilizce', landmark: 'Özgürlük Heykeli ve Büyük Kanyon', region: 'Kuzey Amerika kıtalararası güç', hemisphere: 'Kuzey Yarımküre'),
  (code: 'GR', name: 'Yunanistan', enName: 'Greece', capital: 'Atina', continent: 'Avrupa', currency: 'Euro', lang: 'Yunanca', landmark: 'Akropolis ve Parthenon', region: 'Güneydoğu Avrupa Ege ve Akdeniz', hemisphere: 'Kuzey Yarımküre'),
  (code: 'CL', name: 'Şili', enName: 'Chile', capital: 'Santiago', continent: 'Güney Amerika', currency: 'Şili Pesosu', lang: 'İspanyolca', landmark: 'Atacama Çölü ve Paskalya Adası', region: 'Güney Amerika Pasifik şeridi', hemisphere: 'Güney Yarımküre'),
  (code: 'MY', name: 'Malezya', enName: 'Malaysia', capital: 'Kuala Lumpur', continent: 'Asya', currency: 'Malezya Ringgiti', lang: 'Malayca', landmark: 'Petronas İkiz Kuleleri', region: 'Güneydoğu Asya Malakka Boğazı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'SG', name: 'Singapur', enName: 'Singapore', capital: 'Singapur', continent: 'Asya', currency: 'Singapur Doları', lang: 'İngilizce ve Malayca', landmark: 'Marina Bay Sands', region: 'Güneydoğu Asya şehir devleti', hemisphere: 'Kuzey Yarımküre'),
  (code: 'BR', name: 'Brezilya', enName: 'Brazil', capital: 'Brasília', continent: 'Güney Amerika', currency: 'Brezilya Reali', lang: 'Portekizce', landmark: 'Amazon Yağmur Ormanı', region: 'Güney Amerika en büyük ülkesi', hemisphere: 'Her İki Yarımküre'),
  (code: 'CN', name: 'Çin', enName: 'China', capital: 'Pekin', continent: 'Asya', currency: 'Çin Yuanı', lang: 'Çince', landmark: 'Çin Seddi ve Yasak Şehir', region: 'Doğu Asya ana karası', hemisphere: 'Kuzey Yarımküre'),
  (code: 'VN', name: 'Vietnam', enName: 'Vietnam', capital: 'Hanoi', continent: 'Asya', currency: 'Vietnam Dongu', lang: 'Vietnamca', landmark: 'Ha Long Körfezi', region: 'Güneydoğu Asya Güney Çin Denizi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'MA', name: 'Fas', enName: 'Morocco', capital: 'Rabat', continent: 'Afrika', currency: 'Fas Dirhemi', lang: 'Arapça ve Berberice', landmark: 'Marakeş ve Atlas Dağları', region: 'Kuzeybatı Afrika Mağrip bölgesi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'TN', name: 'Tunus', enName: 'Tunisia', capital: 'Tunus', continent: 'Afrika', currency: 'Tunus Dinarı', lang: 'Arapça', landmark: 'Kartaca Antik Kenti', region: 'Kuzey Afrika Akdeniz kıyısı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'PK', name: 'Pakistan', enName: 'Pakistan', capital: 'İslamabad', continent: 'Asya', currency: 'Pakistan Rupisi', lang: 'Urduca ve İngilizce', landmark: 'K2 Zirvesi ve Badşahi Camii', region: 'Güney Asya İndus Vadisi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'SA', name: 'Suudi Arabistan', enName: 'Saudi Arabia', capital: 'Riyad', continent: 'Asya', currency: 'Suudi Riyali', lang: 'Arapça', landmark: 'El-Ula ve Hicaz bölgesi', region: 'Orta Doğu Arap Yarımadası', hemisphere: 'Kuzey Yarımküre'),
  (code: 'KR', name: 'Güney Kore', enName: 'South Korea', capital: 'Seul', continent: 'Asya', currency: 'Güney Kore Wonu', lang: 'Korece', landmark: 'Gyeongbokgung Sarayı ve Jeju', region: 'Doğu Asya Kore Yarımadası', hemisphere: 'Kuzey Yarımküre'),
  (code: 'CZ', name: 'Çekya', enName: 'Czechia', capital: 'Prag', continent: 'Avrupa', currency: 'Çek Korunası', lang: 'Çekçe', landmark: 'Karl Köprüsü ve Prag Kalesi', region: 'Orta Avrupa Bohemya', hemisphere: 'Kuzey Yarımküre'),
  (code: 'PH', name: 'Filipinler', enName: 'Philippines', capital: 'Manila', continent: 'Asya', currency: 'Filipin Pesosu', lang: 'Filipince ve İngilizce', landmark: 'Palawan ve Pirinç Terasları', region: 'Güneydoğu Asya Pasifik takımadası', hemisphere: 'Kuzey Yarımküre'),
  (code: 'CU', name: 'Küba', enName: 'Cuba', capital: 'Havana', continent: 'Kuzey Amerika', currency: 'Küba Pesosu', lang: 'İspanyolca', landmark: 'Eski Havana ve Viñales Vadisi', region: 'Karayipler ada ülkesi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'PT', name: 'Portekiz', enName: 'Portugal', capital: 'Lizbon', continent: 'Avrupa', currency: 'Euro', lang: 'Portekizce', landmark: 'Belém Kulesi ve Douro Vadisi', region: 'Güneybatı Avrupa Atlantik kıyısı', hemisphere: 'Kuzey Yarımküre'),
  (code: 'JM', name: 'Jamaika', enName: 'Jamaica', capital: 'Kingston', continent: 'Kuzey Amerika', currency: 'Jamaika Doları', lang: 'İngilizce', landmark: 'Blue Mountains kahve bölgesi', region: 'Karayipler Büyük Antiller', hemisphere: 'Kuzey Yarımküre'),
  (code: 'ZA', name: 'Güney Afrika', enName: 'South Africa', capital: 'Pretoria', continent: 'Afrika', currency: 'Güney Afrika Randı', lang: 'İngilizce ve Zuluca', landmark: 'Masa Dağı ve Ümit Burnu', region: 'Afrika kıtasının en güneyi', hemisphere: 'Güney Yarımküre'),
  (code: 'KE', name: 'Kenya', enName: 'Kenya', capital: 'Nairobi', continent: 'Afrika', currency: 'Kenya Şilini', lang: 'Svahili ve İngilizce', landmark: 'Masai Mara ve Büyük Rift Vadisi', region: 'Doğu Afrika Ekvator kuşağı', hemisphere: 'Her İki Yarımküre'),
  (code: 'AE', name: 'Birleşik Arap Emirlikleri', enName: 'United Arab Emirates', capital: 'Abu Dabi', continent: 'Asya', currency: 'BAE Dirhemi', lang: 'Arapça', landmark: 'Burc Halife ve Şeyh Zayid Camii', region: 'Orta Doğu Basra Körfezi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'QA', name: 'Katar', enName: 'Qatar', capital: 'Doha', continent: 'Asya', currency: 'Katar Riyali', lang: 'Arapça', landmark: 'İslam Eserleri Müzesi', region: 'Orta Doğu Basra Körfezi yarımadası', hemisphere: 'Kuzey Yarımküre'),
  (code: 'KZ', name: 'Kazakistan', enName: 'Kazakhstan', capital: 'Astana', continent: 'Asya', currency: 'Tenge', lang: 'Kazakça ve Rusça', landmark: 'Bayterek Kulesi ve Tanrı Dağları', region: 'Orta Asya bozkır ülkesi', hemisphere: 'Kuzey Yarımküre'),
  (code: 'AU', name: 'Avustralya', enName: 'Australia', capital: 'Kanberra', continent: 'Okyanusya', currency: 'Avustralya Doları', lang: 'İngilizce', landmark: 'Sidney Opera Binası ve Büyük Set Resifi', region: 'Okyanusya kıta ülkesi', hemisphere: 'Güney Yarımküre'),
  (code: 'NZ', name: 'Yeni Zelanda', enName: 'New Zealand', capital: 'Wellington', continent: 'Okyanusya', currency: 'Yeni Zelanda Doları', lang: 'İngilizce ve Maorice', landmark: 'Milford Sound fiyortları', region: 'Güneybatı Pasifik Okyanusya', hemisphere: 'Güney Yarımküre'),
];

final _flagNames = [for (final f in _flags64) f.name];
final _flagEnNames = [for (final f in _flags64) f.enName];
final _flagCapitals = [for (final f in _flags64) f.capital];
final _flagCurrencies = _flags64.map((f) => f.currency).toSet().toList();
final _flagLangs = _flags64.map((f) => f.lang).toSet().toList();
final _flagLandmarks = [for (final f in _flags64) f.landmark];
final _flagRegions = [for (final f in _flags64) f.region];
final _flagCodes = [for (final f in _flags64) f.code];
const _flagContinents = ['Avrupa', 'Asya', 'Afrika', 'Kuzey Amerika', 'Güney Amerika', 'Okyanusya', 'Asya ve Avrupa'];

const _flagContexts = [
  'Uluslararası havalimanı tabelasında',
  'Olimpiyat geçit töreninde',
  'Birleşmiş Milletler oturumunda',
  'Dünya coğrafya atlasında',
  'Denizcilik ve liman kayıtlarında',
  'Küresel ekonomi zirvesinde',
];

AdvancedItem _buildFlagDeep(int i) {
  final c = _flags64[i % _flags64.length];
  final variant = i ~/ _flags64.length; // 0..49
  final partner = _flags64[(i + 11 + variant * 3) % _flags64.length];
  final ctx = _flagContexts[(variant + i) % _flagContexts.length];
  final vis = QuestionVisual(
    kind: VisualKind.flag,
    title: 'Bayrak Atlası · #${i + 1}',
    summary: 'Bayrağın ait olduğu ülkenin coğrafi ve kültürel profilini belirleyin.',
    imageID: c.code,
  );
  final aspect = variant % 10;
  final style = variant ~/ 10; // 0..4
  switch (aspect) {
    case 0:
      final prompts = [
        '$ctx görülen bu bayrak hangi ülkeye aittir?',
        'Vektörel bayrağı sunulan ve başkenti ${c.capital} olan ülke hangisidir?',
        'Görseldeki ulusal bayrak, ${partner.name} ile aynı zirvede yer alan hangi ülkeyi temsil eder?',
        '${c.landmark} simgesine ev sahipliği yapan ve bayrağı gösterilen ülke hangisidir?',
        'Bu bayrağı dalgalandıran, ${c.region} coğrafyasındaki ülke aşağıdakilerden hangisidir?',
      ];
      return AdvancedItem(
        prompts[style],
        c.name,
        _pickDistinct(_flagNames, c.name, i + 3),
        'Gösterilen bayrak ${c.name} (${c.enName}) ülkesine aittir; başkenti ${c.capital} şehridir.',
        visual: vis,
      );
    case 1:
      final prompts = [
        'Bayrağı gösterilen ülkenin başkenti aşağıdakilerden hangisidir?',
        '$ctx bu bayrağı taşıyan delegasyon hangi başkentten gelmektedir?',
        '${partner.capital} şehrinden bu bayrağın ülkesine uçan diplomat hangi başkente iner?',
        'Görseldeki bayrağın ülkesinde yönetim merkezi olan başkent hangisidir?',
        'Bayrağı sunulan ülkenin (${c.continent}) resmi başkenti neresidir?',
      ];
      return AdvancedItem(
        prompts[style],
        c.capital,
        _pickDistinct(_flagCapitals, c.capital, i + 5),
        '${c.name} bayrağı gösterilmektedir; ülkenin başkenti ${c.capital} şehridir.',
        visual: vis,
      );
    case 2:
      final prompts = [
        'Bayrağı gösterilen ülkenin resmi para birimi hangisidir?',
        'Görseldeki bayrağın temsil ettiği ülkede yerel alışverişlerde hangi para birimi geçerlidir?',
        '${partner.currency} bozdurup bu bayrağın ülkesine giden yolcu hangi para birimini alır?',
        '$ctx yer alan bu ülkenin merkez bankası hangi para birimini basar?',
        'Bayrağı verilen ülkenin (${c.capital} merkezli) resmi para birimi nedir?',
      ];
      return AdvancedItem(
        prompts[style],
        c.currency,
        _pickDistinct(_flagCurrencies, c.currency, i + 7),
        '${c.name} ülkesinin resmi para birimi ${c.currency} olarak kullanılır.',
        visual: vis,
      );
    case 3:
      final prompts = [
        'Bayrağı gösterilen ülkede en yaygın resmi dil hangisidir?',
        'Bu bayrağın temsil ettiği ülkedeki müze ve tabelalarda öncelikle hangi dil kullanılır?',
        '$ctx bu bayrakla temsil edilen ülkenin resmi dili aşağıdakilerden hangisidir?',
        'Başkenti ${c.capital} olan ve bayrağı gösterilen ülkede hangi resmi dil konuşulur?',
        'Görseldeki bayrağın ait olduğu ülkede eğitim ve yönetimde öne çıkan dil nedir?',
      ];
      return AdvancedItem(
        prompts[style],
        c.lang,
        _pickDistinct(_flagLangs, c.lang, i + 11),
        '${c.name} ülkesinde resmi dil ${c.lang} olarak kullanılmaktadır.',
        visual: vis,
      );
    case 4:
      final prompts = [
        'Bayrağı gösterilen ülkenin İngilizce adı aşağıdakilerden hangisidir?',
        'Uluslararası spor formalarında bu bayrakla birlikte hangi İngilizce ülke adı yazar?',
        'İngilizce haritada bu bayrağı arayan bir öğrenci hangi ülke adına bakmalıdır?',
        'İngilizce pasaport ve vize belgelerinde bu bayrağın ülkesi nasıl yazılır?',
        '${c.capital} başkentli bu bayrağın uluslararası İngilizce karşılığı hangisidir?',
      ];
      return AdvancedItem(
        prompts[style],
        c.enName,
        _pickDistinct(_flagEnNames, c.enName, i + 13),
        '${c.name} ülkesinin uluslararası İngilizce adı "${c.enName}" biçimindedir.',
        visual: vis,
      );
    case 5:
      final prompts = [
        'Bayrağı gösterilen ülkenin dünyaca ünlü simgesi veya doğal mirası hangisidir?',
        'Bu bayrağın ülkesini ziyaret eden bir gezgin aşağıdaki hangi ünlü yapıyı veya bölgeyi görür?',
        'Görseldeki bayrak ile doğrudan eşleşen kültürel/doğal miras hangisidir?',
        'Başkenti ${c.capital} olan bu bayrağın ülkesindeki öne çıkan simge yer hangisidir?',
        'Uluslararası turizm afişinde bu bayrakla birlikte hangi simge yer tanıtılır?',
      ];
      return AdvancedItem(
        prompts[style],
        c.landmark,
        _pickDistinct(_flagLandmarks, c.landmark, i + 17),
        '${c.landmark}, bayrağı gösterilen ${c.name} ülkesinin ünlü simgelerindendir.',
        visual: vis,
      );
    case 6:
      final prompts = [
        'Bayrağı gösterilen ülke hangi kıta veya kıta kuşağında yer alır?',
        'Görseldeki bayrağın ülkesi dünya fiziki haritasında hangi kıtada bulunur?',
        '${c.capital} başkenti ve bu bayrak hangi kıtaya aittir?',
        '$ctx temsil edilen bu ülke hangi kıta grubundadır?',
        'Bayrağı sunulan ülkenin coğrafi olarak bağlı olduğu kıta hangisidir?',
      ];
      return AdvancedItem(
        prompts[style],
        c.continent,
        _pickDistinct(_flagContinents, c.continent, i + 19),
        '${c.name} (${c.region}) ${c.continent} kıtasında konumlanır.',
        visual: vis,
      );
    case 7:
      final prompts = [
        'Bayrağı gösterilen ülkenin iki harfli uluslararası ISO-3166 alan kodu hangisidir?',
        'İnternet alan adlarında ve uçuş listelerinde bu bayrağın ülkesi hangi 2 harfli kodla gösterilir?',
        'Görseldeki bayrağa karşılık gelen standart 2 harfli ülke kodu nedir?',
        '${c.enName} adıyla anılan bu bayrağın resmi ISO-2 kodu hangisidir?',
        'Kargo ve havacılık etiketlerinde bu bayrak için kullanılan 2 harfli ülke kodu hangisidir?',
      ];
      return AdvancedItem(
        prompts[style],
        c.code,
        _pickDistinct(_flagCodes, c.code, i + 23),
        '${c.name} (${c.enName}) için uluslararası ISO-2 ülke kodu "${c.code}" şeklindedir.',
        visual: vis,
      );
    case 8:
      final prompts = [
        'Bayrağı gösterilen ülke aşağıdaki hangi coğrafi alt bölgede yer alır?',
        'Fiziki coğrafya atlasında bu bayrağın ülkesi hangi bölge tanımıyla eşleşir?',
        'Görseldeki bayrağın temsil ettiği ülkenin bulunduğu bölge hangisidir?',
        '${c.capital} başkentli bu ülke hangi coğrafi bölgede konumlanmıştır?',
        'Bayrağı sunulan ülkenin haritadaki bölgesel konumu aşağıdakilerden hangisidir?',
      ];
      return AdvancedItem(
        prompts[style],
        c.region,
        _pickDistinct(_flagRegions, c.region, i + 29),
        '${c.name} ülkesi "${c.region}" coğrafi bölgesinde yer alır.',
        visual: vis,
      );
    default:
      final correctPair = '${c.name} · ${c.capital}';
      final otherPairs = [
        for (final o in _flags64) '${o.name} · ${o.capital}',
      ];
      final prompts = [
        'Bayrağı gösterilen ülke ve başkenti ikilisi aşağıdakilerden hangisidir?',
        'Görseldeki bayrak ile doğru “Ülke · Başkent” eşleştirmesi hangisidir?',
        '$ctx görülen bu bayrağın ait olduğu ülke ve başkent çifti nedir?',
        'Harita eşleştirme oyununda bu bayrak hangi “Ülke · Başkent” kartıyla örtüşür?',
        'Bayrağı inceleyin: doğru ülke ve başkent ikilisi aşağıdakilerden hangisidir?',
      ];
      return AdvancedItem(
        prompts[style],
        correctPair,
        _pickDistinct(otherPairs, correctPair, i + 31),
        'Gösterilen bayrak ${c.name} ülkesine aittir ve başkenti ${c.capital} şehridir (${c.hemisphere}).',
        visual: vis,
      );
  }
}

// ===========================================================================
// 2. ANALOG SAAT, AÇI, AYNA & İNGİLİZCE ZAMAN USTASI (4.000 soru)
// ===========================================================================
const _enHourWords = [
  'twelve', 'one', 'two', 'three', 'four', 'five',
  'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
];

String _fmtClock12(int h, int m) {
  final hh = ((h - 1) % 12 + 12) % 12 + 1;
  return '${hh.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

String _englishTimePhrase(int h, int m) {
  final nextH = h % 12 + 1;
  final hw = _enHourWords[h % 12 == 0 ? 12 : h % 12];
  final nhw = _enHourWords[nextH % 12 == 0 ? 12 : nextH % 12];
  return switch (m) {
    0 => "$hw o'clock",
    5 => 'five past $hw',
    10 => 'ten past $hw',
    15 => 'quarter past $hw',
    20 => 'twenty past $hw',
    25 => 'twenty-five past $hw',
    30 => 'half past $hw',
    35 => 'twenty-five to $nhw',
    40 => 'twenty to $nhw',
    45 => 'quarter to $nhw',
    50 => 'ten to $nhw',
    55 => 'five to $nhw',
    _ => '$hw ${m.toString().padLeft(2, '0')}',
  };
}

AdvancedItem _buildClockMaster(int i) {
  final mode = i % 5; // 5 modes × 800 = 4.000
  final k = i ~/ 5;
  if (mode == 0) {
    // Exact integer angle between hour and minute hands (even minutes => always exact integer)
    var h = (k % 12) + 1;
    var m = ((k ~/ 12) % 30) * 2; // 0, 2, ..., 58
    final askReflex = k >= 360 && k < 720;
    final askLater = k >= 720;
    if (askLater) {
      h = ((k - 720) % 12) + 1;
      m = (((k - 720) ~/ 12) % 6) * 10;
    }
    double calcAcute(int hh, int mm) {
      final raw = (30.0 * (hh % 12) - 5.5 * mm).abs();
      return min(raw, 360.0 - raw);
    }
    var acute = calcAcute(h, m).round();
    if (askReflex && (acute == 0 || acute == 180)) {
      m = (m + 10) % 60;
      acute = calcAcute(h, m).round();
    }
    final vis = QuestionVisual(
      kind: VisualKind.clock,
      title: 'Analog Saat Açı Laboratuvarı',
      summary: 'Akrep ve yelkovan arasındaki açıyı hesaplayın.',
      values: [h.toDouble(), m.toDouble()],
    );
    if (askLater) {
      final total = (h % 12) * 60 + m + 30;
      final nh = (total ~/ 60) % 12 == 0 ? 12 : (total ~/ 60) % 12;
      final nm = total % 60;
      final target = calcAcute(nh, nm).round();
      return AdvancedItem(
        'Görseldeki analog saatten tam 30 dakika sonra akrep ile yelkovan arasındaki küçük açı kaç derece olur?',
        '$target°',
        _intWrong(target, i, suffix: '°', minVal: 0, maxVal: 180, deltas: const [15, -15, 30, -30, 10, -10, 5, -5, 20]),
        'Başlangıç saati ${_fmtClock12(h, m)}, 30 dk sonra ${_fmtClock12(nh, nm)} olur. |30·$nh − 5,5·$nm| formülünden küçük açı $target° bulunur.',
        visual: vis,
      );
    }
    if (askReflex) {
      final reflex = 360 - acute;
      return AdvancedItem(
        'Analog saatte akrep ile yelkovan arasındaki BÜYÜK (geniş) açı kaç derecedir?',
        '$reflex°',
        _intWrong(reflex, i, suffix: '°', minVal: 181, maxVal: 359, deltas: const [12, -12, 18, -18, 6, -6, 15, -15, 24]),
        'Saat ${_fmtClock12(h, m)} iken küçük açı $acute°, dolayısıyla büyük açı 360° − $acute° = $reflex° olur.',
        visual: vis,
      );
    }
    return AdvancedItem(
      'Görseldeki analog saatte akrep ile yelkovan arasındaki küçük açı kaç derecedir?',
      '$acute°',
      _intWrong(acute, i, suffix: '°', minVal: 0, maxVal: 180, deltas: const [11, -11, 15, -15, 6, -6, 22, -22, 30]),
      'Saat ${_fmtClock12(h, m)} için |30·${h % 12} − 5,5·$m| hesabından dar/küçük açı $acute° bulunur.',
      visual: vis,
    );
  } else if (mode == 1) {
    // Elapsed time arithmetic forward/backward
    final h = (k % 12) + 1;
    final m = ((k * 7) % 12) * 5;
    const offsets = [25, 35, 40, 45, 50, 55, 65, 75, 85, 95, 105, 115, 125, 135, 145];
    final delta = offsets[(k ~/ 12) % offsets.length];
    final forward = (k ~/ 5).isEven;
    final baseMin = (h % 12) * 60 + m;
    final resMin = (baseMin + (forward ? delta : -delta) + 7200) % 720;
    final rh = resMin ~/ 60 == 0 ? 12 : resMin ~/ 60;
    final rm = resMin % 60;
    final correct = _fmtClock12(rh, rm);
    final wrongSet = <String>{};
    for (final shift in const [5, -5, 15, -15, 60, -60, 10, -10]) {
      final wMin = (resMin + shift + 7200) % 720;
      final wh = wMin ~/ 60 == 0 ? 12 : wMin ~/ 60;
      final wm = wMin % 60;
      final cand = _fmtClock12(wh, wm);
      if (cand != correct) wrongSet.add(cand);
      if (wrongSet.length == 3) break;
    }
    final durLabel = delta >= 60 ? '${delta ~/ 60} saat ${delta % 60} dakika' : '$delta dakika';
    return AdvancedItem(
      forward
          ? 'Analog saate göre tam $durLabel SONRA saat kaçı gösterir?'
          : 'Analog saate göre tam $durLabel ÖNCE saat kaçı gösteriyordu?',
      correct,
      wrongSet.toList(),
      'Görseldeki saat ${_fmtClock12(h, m)}. $durLabel ${forward ? 'eklendiğinde' : 'çıkarıldığında'} $correct elde edilir.',
      visual: QuestionVisual(
        kind: VisualKind.clock,
        title: 'Zaman Hesabı Stüdyosu',
        summary: 'Analog saati okuyup zaman farkını hesaplayın.',
        values: [h.toDouble(), m.toDouble()],
      ),
    );
  } else if (mode == 2) {
    // English analog time reading
    final h = (k % 12) + 1;
    final m = ((k ~/ 12) % 12) * 5;
    final correct = _englishTimePhrase(h, m);
    final pool = <String>[
      for (var hh = 1; hh <= 12; hh++)
        for (var mm = 0; mm < 60; mm += 5)
          _englishTimePhrase(hh, mm),
    ];
    final contextIdx = (k ~/ 144) % 6;
    const prompts = [
      'Analog saatteki zaman İngilizce olarak nasıl söylenir? ("What time is it?")',
      'İngilizce konuşan bir kişi görseldeki bu saati sorduğunuzda hangi yanıtı verir?',
      'Görseldeki saat İngilizce dersinde hangi ifadeyle okunur?',
      'Bir uçuş tabelasında bu saat görülüyor; İngilizce sesli okunuşu hangisidir?',
      'Analog saatteki zamanın doğru İngilizce karşılığı hangisidir?',
      'İngilizce günlük konuşmada bu analog saat nasıl ifade edilir?',
    ];
    return AdvancedItem(
      prompts[contextIdx],
      correct,
      _pickDistinct(pool, correct, i + 17),
      'Saat ${_fmtClock12(h, m)} İngilizce olarak "$correct" şeklinde okunur.',
      visual: QuestionVisual(
        kind: VisualKind.clock,
        title: 'English Clock Studio',
        summary: 'Read the analog clock and pick the matching English expression.',
        values: [h.toDouble(), m.toDouble()],
      ),
    );
  } else if (mode == 3) {
    // Mirror clock reflection: real = 12:00 - shown
    final h = (k % 12) + 1;
    final m = ((k * 11 + 3) % 60);
    final shownMin = (h % 12) * 60 + m;
    final realMin = (720 - shownMin) % 720;
    final rh = realMin ~/ 60 == 0 ? 12 : realMin ~/ 60;
    final rm = realMin % 60;
    final correct = _fmtClock12(rh, rm);
    final wrong = <String>[];
    for (final delta in const [60, -60, 10, -10, 5, -5, 30, -30]) {
      final wmTotal = (realMin + delta + 7200) % 720;
      final wh = wmTotal ~/ 60 == 0 ? 12 : wmTotal ~/ 60;
      final wm = wmTotal % 60;
      final cand = _fmtClock12(wh, wm);
      if (cand != correct && !wrong.contains(cand)) wrong.add(cand);
      if (wrong.length == 3) break;
    }
    return AdvancedItem(
      'Rakamları olmayan bir analog saatin DÜZ AYNADAKİ görüntüsü şekildeki gibidir. Gerçek saat kaçtır?',
      correct,
      wrong,
      'Düz ayna simetrisinde gerçek saat 12:00 − ${_fmtClock12(h, m)} = $correct olarak bulunur.',
      visual: QuestionVisual(
        kind: VisualKind.clock,
        title: 'Ayna Saati Simetrisi',
        summary: 'Düz aynadaki yansımadan gerçek saati bulun.',
        values: [h.toDouble(), m.toDouble()],
      ),
    );
  } else {
    // 24-hour digital & evening/night schedule conversion
    final h12 = (k % 12) + 1; // 1..12
    final m = ((k * 5) % 12) * 5;
    final isAfternoon = (k ~/ 12).isEven;
    final addMins = const [0, 15, 20, 30, 40, 45][k % 6];
    final base24H = isAfternoon
        ? (h12 == 12 ? 12 : h12 + 12)
        : (h12 == 12 ? 0 : h12);
    final total24 = (base24H * 60 + m + addMins) % 1440;
    final outH = total24 ~/ 60;
    final outM = total24 % 60;
    final correct = '${outH.toString().padLeft(2, '0')}:${outM.toString().padLeft(2, '0')}';
    final wrong = <String>[];
    for (final shift in const [60, -60, 720, 15, -15, 30]) {
      final t = (total24 + shift + 1440) % 1440;
      final cand = '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
      if (cand != correct && !wrong.contains(cand)) wrong.add(cand);
      if (wrong.length == 3) break;
    }
    final periodLabel = isAfternoon ? 'öğleden sonra / akşam (PM)' : 'sabah / gece yarısı sonrası (AM)';
    return AdvancedItem(
      addMins == 0
          ? 'Bu analog saat $periodLabel zamanını göstermektedir. 24 saatlik dijital gösterimi hangisidir?'
          : 'Bu analog saat $periodLabel zamanını göstermektedir. $addMins dakika sonraki tren kalkış saati 24 saatlik düzende kaçtır?',
      correct,
      wrong,
      'Analog saat ${_fmtClock12(h12, m)} ($periodLabel) → 24 saatlik düzende ${base24H.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}${addMins > 0 ? ', +$addMins dk sonrası $correct' : ''}.',
      visual: QuestionVisual(
        kind: VisualKind.clock,
        title: '24 Saat Dijital Dönüşüm',
        summary: 'Analog saati 24 saatlik takvim/sefer saatine çevirin.',
        values: [h12.toDouble(), m.toDouble()],
      ),
    );
  }
}

// ===========================================================================
// 3. PASTA GRAFİĞİ & DAİRE VERİ ANALİTİĞİ (3.600 soru)
// ===========================================================================
const _pieThemes = <(String, String, List<String>)>[
  ('Elektrik Üretim Dağılımı', 'MW', ['Güneş', 'Rüzgâr', 'Hidroelektrik', 'Jeotermal']),
  ('Aylık Hane Bütçesi', 'TL', ['Konut', 'Gıda', 'Ulaşım', 'Eğitim']),
  ('Kütüphane Kitap Türleri', 'kitap', ['Roman', 'Bilim', 'Tarih', 'Şiir']),
  ('Şehir İçi Ulaşım Payı', 'yolcu', ['Metro', 'Otobüs', 'Vapur', 'Bisiklet']),
  ('Tarım Üretim Alanı', 'dönüm', ['Buğday', 'Zeytin', 'Mısır', 'Pamuk']),
  ('Okul Kulüpleri Katılımı', 'öğrenci', ['Robotik', 'Müzik', 'Spor', 'Tiyatro']),
  ('Dijital Trafik Kaynakları', 'ziyaret', ['Arama', 'Doğrudan', 'Sosyal', 'E-posta']),
  ('Geri Dönüşüm Tonajı', 'ton', ['Kâğıt', 'Cam', 'Plastik', 'Metal']),
  ('Su Tüketim Dağılımı', 'litre', ['Tarım', 'Sanayi', 'Evsel', 'Park']),
  ('Sınav Çalışma Süresi', 'dk', ['Matematik', 'Fen', 'Türkçe', 'İngilizce']),
  ('Müze Ziyaretçi Profili', 'kişi', ['Öğrenci', 'Yetişkin', 'Turist', 'Grup']),
  ('Yazılım Ekibi Zamanı', 'saat', ['Geliştirme', 'Test', 'Tasarım', 'Bakım']),
];

const _piePartitions = <List<int>>[
  [40, 30, 20, 10],
  [45, 25, 20, 10],
  [40, 25, 20, 15],
  [35, 30, 20, 15],
  [50, 25, 15, 10],
  [45, 30, 15, 10],
  [55, 20, 15, 10],
  [50, 25, 20, 5],
  [45, 30, 20, 5],
  [40, 35, 20, 5],
  [40, 35, 15, 10],
  [55, 25, 15, 5],
];

const _pieTotals = [
  200, 300, 360, 400, 500, 600, 720, 800, 900, 1000,
  1200, 1400, 1500, 1600, 1800, 2000, 2400, 2500, 3000, 3600,
  4000, 4500, 5000, 6000, 7200,
];

AdvancedItem _buildPieAnalytics(int i) {
  final theme = _pieThemes[i % _pieThemes.length];
  final part = _piePartitions[(i ~/ _pieThemes.length) % _piePartitions.length];
  final rot = (i ~/ 144) % 4;
  final pcts = [for (var k = 0; k < 4; k++) part[(k + rot) % 4]];
  final total = _pieTotals[(i ~/ 6) % _pieTotals.length];
  final qType = i % 6;
  final labels = theme.$3;
  final unit = theme.$2;
  final vis = QuestionVisual(
    kind: VisualKind.pieChart,
    title: theme.$1,
    summary: 'Toplam: $total $unit · Dilimler yüzde (%) olarak verilmiştir.',
    labels: labels,
    values: [for (final p in pcts) p.toDouble()],
    unit: '%',
  );

  final targetIdx = (i ~/ 12) % 4;
  if (qType == 0) {
    final val = (total * pcts[targetIdx]) ~/ 100;
    return AdvancedItem(
      'Toplamın $total $unit olduğu bu daire grafiğinde "${labels[targetIdx]}" dilimi kaç $unit değerindedir?',
      '$val $unit',
      _intWrong(val, i, suffix: ' $unit', minVal: 1, deltas: [total ~/ 20, -total ~/ 20, total ~/ 10, -total ~/ 10, 20, -20, 50]),
      '%${pcts[targetIdx]} × $total = $val $unit.',
      visual: vis,
    );
  } else if (qType == 1) {
    final deg = (pcts[targetIdx] * 18) ~/ 5;
    return AdvancedItem(
      'Grafikte "${labels[targetIdx]}" dilimine ait merkez açı kaç derecedir?',
      '$deg°',
      _intWrong(deg, i, suffix: '°', minVal: 9, maxVal: 350, deltas: const [18, -18, 36, -36, 9, -9, 27, -27]),
      'Tam daire 360° olduğundan %${pcts[targetIdx]} diliminin merkez açısı 360° × ${pcts[targetIdx]} / 100 = $deg° olur.',
      visual: vis,
    );
  } else if (qType == 2) {
    final maxP = pcts.reduce(max);
    final minP = pcts.reduce(min);
    final diff = (total * (maxP - minP)) ~/ 100;
    return AdvancedItem(
      'Toplam $total $unit üzerinden, en büyük dilim ile en küçük dilim arasındaki fark kaç $unit olur?',
      '$diff $unit',
      _intWrong(diff, i, suffix: ' $unit', minVal: 1, deltas: [total ~/ 20, -total ~/ 20, total ~/ 10, -total ~/ 10, 30, -30]),
      'En büyük %$maxP, en küçük %$minP; fark %${maxP - minP} × $total = $diff $unit.',
      visual: vis,
    );
  } else if (qType == 3) {
    final a = targetIdx;
    final b = (targetIdx + 1) % 4;
    final sumVal = (total * (pcts[a] + pcts[b])) ~/ 100;
    return AdvancedItem(
      'Toplam $total $unit için "${labels[a]}" ve "${labels[b]}" dilimlerinin toplam değeri kaç $unit eder?',
      '$sumVal $unit',
      _intWrong(sumVal, i, suffix: ' $unit', minVal: 1, deltas: [total ~/ 20, -total ~/ 20, total ~/ 10, -total ~/ 10, 40, -40]),
      '%${pcts[a]} + %${pcts[b]} = %${pcts[a] + pcts[b]}; bu oran $total $unit içinde $sumVal $unit yapar.',
      visual: vis,
    );
  } else if (qType == 4) {
    final a = targetIdx;
    final b = (targetIdx + 2) % 4;
    final sumDeg = ((pcts[a] + pcts[b]) * 18) ~/ 5;
    return AdvancedItem(
      '"${labels[a]}" ve "${labels[b]}" dilimlerinin merkez açıları toplamı kaç derecedir?',
      '$sumDeg°',
      _intWrong(sumDeg, i, suffix: '°', minVal: 18, maxVal: 350, deltas: const [18, -18, 36, -36, 9, -9, 54]),
      'İki dilimin yüzdeleri toplamı %${pcts[a] + pcts[b]}; 360° ile çarpımı $sumDeg° eder.',
      visual: vis,
    );
  } else {
    final remVal = (total * (100 - pcts[targetIdx])) ~/ 100;
    return AdvancedItem(
      'Toplam $total $unit içinden "${labels[targetIdx]}" dışındaki diğer üç dilimin toplamı kaç $unit olur?',
      '$remVal $unit',
      _intWrong(remVal, i, suffix: ' $unit', minVal: 1, deltas: [total ~/ 20, -total ~/ 20, total ~/ 10, -total ~/ 10, 50, -50]),
      'Diğer üç dilimin toplamı %${100 - pcts[targetIdx]}; $total × ${100 - pcts[targetIdx]} / 100 = $remVal $unit.',
      visual: vis,
    );
  }
}

// ===========================================================================
// 4. KOORDİNAT DÜZLEMİ, GEOMETRİ & VEKTÖR STÜDYOSU (4.400 soru)
// ===========================================================================
String _pt(int x, int y) => '($x, $y)';

List<String> _pickDistinctPoints(String correct, List<(int, int)> candidates, int seed) {
  final seen = <String>{correct};
  final out = <String>[];
  final start = seed.abs() % candidates.length;
  for (var k = 0; k < candidates.length && out.length < 3; k++) {
    final p = candidates[(start + k) % candidates.length];
    final s = _pt(p.$1, p.$2);
    if (seen.add(s)) out.add(s);
  }
  var dx = 1;
  while (out.length < 3) {
    final s = _pt(dx, -dx);
    if (seen.add(s)) out.add(s);
    dx++;
  }
  return out;
}

AdvancedItem _buildCoordMaster(int i) {
  final mode = i % 8; // 8 modes × 550 = 4.400
  final k = i ~/ 8;
  if (mode == 0) {
    // Point quadrant & coordinate reading
    const coords = [-5, -4, -3, -2, -1, 1, 2, 3, 4, 5];
    final x = coords[k % coords.length];
    final y = coords[(k ~/ coords.length + k * 3) % coords.length];
    final askQuad = (k ~/ 100).isOdd;
    final vis = QuestionVisual(
      kind: VisualKind.coordPlane,
      title: 'Koordinat Düzlemi · Nokta Okuma',
      summary: 'P noktasının konumunu eksenlere göre okuyun.',
      values: const [-6, 6, -6, 6],
      elements: [DiagramElement(shape: 'point', x: x.toDouble(), y: y.toDouble(), label: 'P', color: 'gold')],
    );
    if (askQuad) {
      final qName = (x > 0 && y > 0)
          ? '1. Bölge (+, +)'
          : (x < 0 && y > 0)
              ? '2. Bölge (−, +)'
              : (x < 0 && y < 0)
                  ? '3. Bölge (−, −)'
                  : '4. Bölge (+, −)';
      return AdvancedItem(
        'Koordinat düzleminde işaretlenen P($x, $y) noktası hangi bölgededir?',
        qName,
        _pickDistinct(const ['1. Bölge (+, +)', '2. Bölge (−, +)', '3. Bölge (−, −)', '4. Bölge (+, −)'], qName, i),
        'Apsis x = $x ve ordinat y = $y olduğundan P noktası $qName içindedir.',
        visual: vis,
      );
    }
    return AdvancedItem(
      'Koordinat düzleminde işaretlenen P noktasının koordinatları (x, y) hangisidir?',
      _pt(x, y),
      _pickDistinctPoints(_pt(x, y), [(-x, y), (x, -y), (y, x), (-x, -y), (x + 1, y), (x, y - 1), (y, -x)], i),
      'P noktası x ekseninde $x, y ekseninde $y hizasında olduğundan ($x, $y) konumundadır.',
      visual: vis,
    );
  } else if (mode == 1) {
    // Exact Euclidean distance using Pythagorean displacements inside [-6, 6]
    const triples = [
      (3, 4, 5), (4, 3, 5), (-3, 4, 5), (4, -3, 5), (-4, -3, 5),
      (6, 8, 10), (8, 6, 10), (-6, 8, 10), (8, -6, 10),
      (0, 5, 5), (0, 7, 7), (6, 0, 6), (9, 0, 9),
    ];
    final t = triples[k % triples.length];
    final dx = t.$1, dy = t.$2, dist = t.$3;
    final minX1 = max(-6, -6 - dx);
    final maxX1 = min(6, 6 - dx);
    final minY1 = max(-6, -6 - dy);
    final maxY1 = min(6, 6 - dy);
    final x1 = minX1 + (k % (maxX1 - minX1 + 1));
    final y1 = minY1 + ((k ~/ 7) % (maxY1 - minY1 + 1));
    final x2 = x1 + dx;
    final y2 = y1 + dy;
    return AdvancedItem(
      'Koordinat düzleminde A($x1, $y1) ile B($x2, $y2) noktaları arasındaki uzaklık kaç birimdir?',
      '$dist birim',
      _intWrong(dist, i, suffix: ' birim', minVal: 1, deltas: const [1, -1, 2, -2, 3, -3, 4]),
      'd = √(($x2 − $x1)² + ($y2 − $y1)²) = √(${dx * dx} + ${dy * dy}) = $dist birim.',
      visual: QuestionVisual(
        kind: VisualKind.coordPlane,
        title: 'İki Nokta Arası Uzaklık',
        summary: 'AB doğru parçasının uzunluğunu hesaplayın.',
        values: const [-6, 6, -6, 6],
        elements: [
          DiagramElement(shape: 'line', x: x1.toDouble(), y: y1.toDouble(), endX: x2.toDouble(), endY: y2.toDouble(), color: 'mint'),
          DiagramElement(shape: 'point', x: x1.toDouble(), y: y1.toDouble(), label: 'A', color: 'gold'),
          DiagramElement(shape: 'point', x: x2.toDouble(), y: y2.toDouble(), label: 'B', color: 'pink'),
        ],
      ),
    );
  } else if (mode == 2) {
    // Integer midpoint of segment AB
    final mx = (k % 9) - 4; // -4..4
    final my = ((k ~/ 9) % 9) - 4;
    final hx = ((k % 3) + 1) * ((k ~/ 3).isEven ? 1 : -1);
    final hy = (((k + 1) % 3) + 1) * ((k ~/ 5).isEven ? 1 : -1);
    final x1 = (mx - hx).clamp(-6, 6);
    final x2 = 2 * mx - x1;
    final y1 = (my - hy).clamp(-6, 6);
    final y2 = 2 * my - y1;
    final realMx = (x1 + x2) ~/ 2;
    final realMy = (y1 + y2) ~/ 2;
    return AdvancedItem(
      'Düzlemde verilen A($x1, $y1) ve B($x2, $y2) noktalarının orta noktası M hangisidir?',
      _pt(realMx, realMy),
      _pickDistinctPoints(_pt(realMx, realMy), [
        (realMx + 1, realMy), (realMx - 1, realMy), (realMx, realMy + 1),
        (realMx, realMy - 1), (realMy, realMx), (-realMx, realMy), (realMx + 2, realMy - 1),
      ], i),
      'Orta nokta M = ((x₁+x₂)/2, (y₁+y₂)/2) = (($x1+$x2)/2, ($y1+$y2)/2) = ($realMx, $realMy).',
      visual: QuestionVisual(
        kind: VisualKind.coordPlane,
        title: 'Doğru Parçası Orta Noktası',
        summary: 'AB doğru parçasının tam orta noktasını bulun.',
        values: const [-6, 6, -6, 6],
        elements: [
          DiagramElement(shape: 'line', x: x1.toDouble(), y: y1.toDouble(), endX: x2.toDouble(), endY: y2.toDouble(), color: 'blue'),
          DiagramElement(shape: 'point', x: x1.toDouble(), y: y1.toDouble(), label: 'A', color: 'gold'),
          DiagramElement(shape: 'point', x: x2.toDouble(), y: y2.toDouble(), label: 'B', color: 'mint'),
        ],
      ),
    );
  } else if (mode == 3) {
    // Exact integer slope m = dy / dx
    const slopes = [-3, -2, -1, 0, 1, 2, 3];
    final m = slopes[k % slopes.length];
    final dx = (m.abs() == 3) ? 2 : (m.abs() == 2 ? 2 + (k % 2) : 2 + (k % 4));
    final dy = m * dx;
    final x1 = -((dx ~/ 2) + (k % 2)).clamp(1, 5);
    final x2 = x1 + dx;
    final y1 = (-(dy ~/ 2)).clamp(-5, 5);
    final y2 = y1 + dy;
    return AdvancedItem(
      'Koordinat düzleminde A($x1, $y1) ve B($x2, $y2) noktalarından geçen doğrunun eğimi (m) kaçtır?',
      '$m',
      _intWrong(m, i, minVal: -6, maxVal: 6, deltas: const [1, -1, 2, -2, 3, -3]),
      'Eğim m = (y₂ − y₁) / (x₂ − x₁) = ($y2 − $y1) / ($x2 − $x1) = $dy / $dx = $m.',
      visual: QuestionVisual(
        kind: VisualKind.coordPlane,
        title: 'Doğrunun Eğimi',
        summary: 'A ve B noktalarından geçen doğrunun eğimini hesaplayın.',
        values: const [-6, 6, -6, 6],
        elements: [
          DiagramElement(shape: 'line', x: x1.toDouble(), y: y1.toDouble(), endX: x2.toDouble(), endY: y2.toDouble(), color: 'gold'),
          DiagramElement(shape: 'point', x: x1.toDouble(), y: y1.toDouble(), label: 'A', color: 'mint'),
          DiagramElement(shape: 'point', x: x2.toDouble(), y: y2.toDouble(), label: 'B', color: 'pink'),
        ],
      ),
    );
  } else if (mode == 4) {
    // Triangle area on grid (even base or height => exact integer area)
    final base = 2 + (k % 5) * 2; // 2,4,6,8,10 (even => area always integer!)
    final height = 2 + ((k ~/ 5) % 5); // 2..6
    final x1 = -(base ~/ 2);
    final x2 = x1 + base;
    final yBase = -3 + ((k ~/ 25) % 3); // -3, -2, -1
    final xTop = x1 + ((k * 3) % (base + 1));
    final yTop = (yBase + height).clamp(-5, 6);
    final realH = (yTop - yBase).abs();
    final area = (base * realH) ~/ 2;
    return AdvancedItem(
      'Köşeleri A($x1, $yBase), B($x2, $yBase) ve C($xTop, $yTop) olan taralı üçgenin alanı kaç birimkaredir?',
      '$area br²',
      _intWrong(area, i, suffix: ' br²', minVal: 1, deltas: const [2, -2, 4, -4, 3, -3, 6]),
      'Taban = $base birim, yükseklik = $realH birim. Alan = ($base × $realH) / 2 = $area br².',
      visual: QuestionVisual(
        kind: VisualKind.coordPlane,
        title: 'Koordinat Düzleminde Üçgen Alanı',
        summary: 'Taralı üçgenin alanını taban × yükseklik / 2 ile bulun.',
        values: const [-6, 6, -6, 6],
        elements: [
          DiagramElement(shape: 'polygon', x: 0, y: 0, label: '$x1,$yBase;$x2,$yBase;$xTop,$yTop', color: 'mint'),
          DiagramElement(shape: 'point', x: x1.toDouble(), y: yBase.toDouble(), label: 'A', color: 'gold'),
          DiagramElement(shape: 'point', x: x2.toDouble(), y: yBase.toDouble(), label: 'B', color: 'gold'),
          DiagramElement(shape: 'point', x: xTop.toDouble(), y: yTop.toDouble(), label: 'C', color: 'pink'),
        ],
      ),
    );
  } else if (mode == 5) {
    // Rectangle area or perimeter on grid
    final w = 2 + (k % 7); // 2..8
    final h = 2 + ((k ~/ 7) % 6); // 2..7
    final x1 = -(w ~/ 2);
    final x2 = x1 + w;
    final y1 = -(h ~/ 2);
    final y2 = y1 + h;
    final askPerimeter = (k ~/ 42).isOdd;
    final ans = askPerimeter ? 2 * (w + h) : w * h;
    final suf = askPerimeter ? ' birim' : ' br²';
    return AdvancedItem(
      askPerimeter
          ? 'Köşeleri ($x1, $y1) ve ($x2, $y2) hizasında çizilen dikdörtgenin ÇEVRESİ kaç birimdir?'
          : 'Köşeleri ($x1, $y1) ve ($x2, $y2) hizasında çizilen dikdörtgenin ALANI kaç birimkaredir?',
      '$ans$suf',
      _intWrong(ans, i, suffix: suf, minVal: 4, deltas: const [2, -2, 4, -4, 6, -6, 3]),
      'Kenar uzunlukları $w ve $h birimdir. ${askPerimeter ? 'Çevre = 2·($w+$h) = $ans birim' : 'Alan = $w·$h = $ans br²'}.',
      visual: QuestionVisual(
        kind: VisualKind.coordPlane,
        title: 'Dikdörtgen Analizi',
        summary: 'Dikdörtgenin kenar uzunluklarını ızgaradan okuyun.',
        values: const [-6, 6, -6, 6],
        elements: [
          DiagramElement(shape: 'polygon', x: 0, y: 0, label: '$x1,$y1;$x2,$y1;$x2,$y2;$x1,$y2', color: 'blue'),
        ],
      ),
    );
  } else if (mode == 6) {
    // Reflection across x-axis, y-axis, origin, or y=x
    const coords = [-5, -4, -3, -2, -1, 1, 2, 3, 4, 5];
    final x = coords[k % coords.length];
    final y = coords[(k ~/ coords.length + k * 2 + 1) % coords.length];
    final refType = k % 4;
    final (rx, ry, refName) = switch (refType) {
      0 => (x, -y, 'x eksenine göre'),
      1 => (-x, y, 'y eksenine göre'),
      2 => (-x, -y, 'orijine göre'),
      _ => (y, x, 'y = x doğrusuna göre'),
    };
    return AdvancedItem(
      'Koordinat düzleminde gösterilen P($x, $y) noktasının $refName simetriği (yansıması) hangi noktadır?',
      _pt(rx, ry),
      _pickDistinctPoints(_pt(rx, ry), [
        (x, -y), (-x, y), (-x, -y), (y, x), (-y, -x), (x + 1, -y), (-x, y - 1),
      ], i),
      'P($x, $y) noktasının $refName simetriği ($rx, $ry) olur.',
      visual: QuestionVisual(
        kind: VisualKind.coordPlane,
        title: 'Simetri & Yansıma',
        summary: 'P noktasının belirtilen eksene göre simetriğini bulun.',
        values: const [-6, 6, -6, 6],
        elements: [
          DiagramElement(shape: 'point', x: x.toDouble(), y: y.toDouble(), label: 'P($x,$y)', color: 'gold'),
        ],
      ),
    );
  } else {
    // Vectors u and v from origin: sum, diff, or dot product
    const vals = [-4, -3, -2, -1, 1, 2, 3, 4];
    final ux = vals[k % vals.length];
    final uy = vals[(k ~/ 8 + 2) % vals.length];
    final vx = vals[(k * 3 + 1) % vals.length];
    final vy = vals[(k * 5 + 3) % vals.length];
    final op = k % 3;
    final vis = QuestionVisual(
      kind: VisualKind.coordPlane,
      title: 'Vektör İşlemleri Stüdyosu',
      summary: 'u($ux, $uy) ve v($vx, $vy) vektörleri gösterilmiştir.',
      values: const [-6, 6, -6, 6],
      elements: [
        DiagramElement(shape: 'arrow', x: 0, y: 0, endX: ux.toDouble(), endY: uy.toDouble(), label: 'u', color: 'gold'),
        DiagramElement(shape: 'arrow', x: 0, y: 0, endX: vx.toDouble(), endY: vy.toDouble(), label: 'v', color: 'mint'),
      ],
    );
    if (op == 0) {
      final sx = ux + vx, sy = uy + vy;
      return AdvancedItem(
        'Şekildeki u($ux, $uy) ve v($vx, $vy) vektörlerinin toplamı (u + v) hangisidir?',
        _pt(sx, sy),
        _pickDistinctPoints(_pt(sx, sy), [
          (ux - vx, uy - vy), (sx + 1, sy), (sx, sy - 1), (sy, sx), (-sx, -sy), (sx - 2, sy + 1),
        ], i),
        'u + v = ($ux + $vx, $uy + $vy) = ($sx, $sy).',
        visual: vis,
      );
    } else if (op == 1) {
      final dx = ux - vx, dy = uy - vy;
      return AdvancedItem(
        'Şekildeki u($ux, $uy) ve v($vx, $vy) vektörlerinin farkı (u − v) hangisidir?',
        _pt(dx, dy),
        _pickDistinctPoints(_pt(dx, dy), [
          (ux + vx, uy + vy), (-dx, -dy), (dx + 1, dy), (dx, dy + 1), (dy, dx), (dx - 1, dy - 1),
        ], i),
        'u − v = ($ux − $vx, $uy − $vy) = ($dx, $dy).',
        visual: vis,
      );
    } else {
      final dot = ux * vx + uy * vy;
      return AdvancedItem(
        'Şekildeki u($ux, $uy) ve v($vx, $vy) vektörlerinin skaler (iç) çarpımı u · v kaçtır?',
        '$dot',
        _intWrong(dot, i, deltas: const [2, -2, 4, -4, 1, -1, 6, -6]),
        'u · v = ($ux)·($vx) + ($uy)·($vy) = ${ux * vx} + ${uy * vy} = $dot.',
        visual: vis,
      );
    }
  }
}

// ===========================================================================
// 5. BOHR ATOM & İZOTOP / İYON LABORATUVARI (36 Element → 3.000 soru)
// ===========================================================================
typedef _AtomInfo = ({
  int z,
  String sym,
  String trName,
  String enName,
  int mass,
  List<int> shells,
  int period,
  String group,
  String cls,
  int valence,
  String stableIon,
});

const _atoms36 = <_AtomInfo>[
  (z: 1, sym: 'H', trName: 'Hidrojen', enName: 'Hydrogen', mass: 1, shells: [1], period: 1, group: '1A', cls: 'Ametal', valence: 1, stableIon: 'H⁺'),
  (z: 2, sym: 'He', trName: 'Helyum', enName: 'Helium', mass: 4, shells: [2], period: 1, group: '8A', cls: 'Soygaz', valence: 2, stableIon: 'Kararlı (0)'),
  (z: 3, sym: 'Li', trName: 'Lityum', enName: 'Lithium', mass: 7, shells: [2, 1], period: 2, group: '1A', cls: 'Alkali Metal', valence: 1, stableIon: 'Li⁺'),
  (z: 4, sym: 'Be', trName: 'Berilyum', enName: 'Beryllium', mass: 9, shells: [2, 2], period: 2, group: '2A', cls: 'Toprak Alkali Metal', valence: 2, stableIon: 'Be²⁺'),
  (z: 5, sym: 'B', trName: 'Bor', enName: 'Boron', mass: 11, shells: [2, 3], period: 2, group: '3A', cls: 'Yarı Metal', valence: 3, stableIon: 'B³⁺'),
  (z: 6, sym: 'C', trName: 'Karbon', enName: 'Carbon', mass: 12, shells: [2, 4], period: 2, group: '4A', cls: 'Ametal', valence: 4, stableIon: 'Kovalent (4 bağ)'),
  (z: 7, sym: 'N', trName: 'Azot', enName: 'Nitrogen', mass: 14, shells: [2, 5], period: 2, group: '5A', cls: 'Ametal', valence: 5, stableIon: 'N³⁻'),
  (z: 8, sym: 'O', trName: 'Oksijen', enName: 'Oxygen', mass: 16, shells: [2, 6], period: 2, group: '6A', cls: 'Ametal', valence: 6, stableIon: 'O²⁻'),
  (z: 9, sym: 'F', trName: 'Flor', enName: 'Fluorine', mass: 19, shells: [2, 7], period: 2, group: '7A', cls: 'Halojen (Ametal)', valence: 7, stableIon: 'F⁻'),
  (z: 10, sym: 'Ne', trName: 'Neon', enName: 'Neon', mass: 20, shells: [2, 8], period: 2, group: '8A', cls: 'Soygaz', valence: 8, stableIon: 'Kararlı (0)'),
  (z: 11, sym: 'Na', trName: 'Sodyum', enName: 'Sodium', mass: 23, shells: [2, 8, 1], period: 3, group: '1A', cls: 'Alkali Metal', valence: 1, stableIon: 'Na⁺'),
  (z: 12, sym: 'Mg', trName: 'Magnezyum', enName: 'Magnesium', mass: 24, shells: [2, 8, 2], period: 3, group: '2A', cls: 'Toprak Alkali Metal', valence: 2, stableIon: 'Mg²⁺'),
  (z: 13, sym: 'Al', trName: 'Alüminyum', enName: 'Aluminium', mass: 27, shells: [2, 8, 3], period: 3, group: '3A', cls: 'Metal', valence: 3, stableIon: 'Al³⁺'),
  (z: 14, sym: 'Si', trName: 'Silisyum', enName: 'Silicon', mass: 28, shells: [2, 8, 4], period: 3, group: '4A', cls: 'Yarı Metal', valence: 4, stableIon: 'Kovalent (4 bağ)'),
  (z: 15, sym: 'P', trName: 'Fosfor', enName: 'Phosphorus', mass: 31, shells: [2, 8, 5], period: 3, group: '5A', cls: 'Ametal', valence: 5, stableIon: 'P³⁻'),
  (z: 16, sym: 'S', trName: 'Kükürt', enName: 'Sulfur', mass: 32, shells: [2, 8, 6], period: 3, group: '6A', cls: 'Ametal', valence: 6, stableIon: 'S²⁻'),
  (z: 17, sym: 'Cl', trName: 'Klor', enName: 'Chlorine', mass: 35, shells: [2, 8, 7], period: 3, group: '7A', cls: 'Halojen (Ametal)', valence: 7, stableIon: 'Cl⁻'),
  (z: 18, sym: 'Ar', trName: 'Argon', enName: 'Argon', mass: 40, shells: [2, 8, 8], period: 3, group: '8A', cls: 'Soygaz', valence: 8, stableIon: 'Kararlı (0)'),
  (z: 19, sym: 'K', trName: 'Potasyum', enName: 'Potassium', mass: 39, shells: [2, 8, 8, 1], period: 4, group: '1A', cls: 'Alkali Metal', valence: 1, stableIon: 'K⁺'),
  (z: 20, sym: 'Ca', trName: 'Kalsiyum', enName: 'Calcium', mass: 40, shells: [2, 8, 8, 2], period: 4, group: '2A', cls: 'Toprak Alkali Metal', valence: 2, stableIon: 'Ca²⁺'),
  (z: 21, sym: 'Sc', trName: 'Skandiyum', enName: 'Scandium', mass: 45, shells: [2, 8, 9, 2], period: 4, group: '3B', cls: 'Geçiş Metali', valence: 2, stableIon: 'Sc³⁺'),
  (z: 22, sym: 'Ti', trName: 'Titanyum', enName: 'Titanium', mass: 48, shells: [2, 8, 10, 2], period: 4, group: '4B', cls: 'Geçiş Metali', valence: 2, stableIon: 'Ti⁴⁺'),
  (z: 23, sym: 'V', trName: 'Vanadyum', enName: 'Vanadium', mass: 51, shells: [2, 8, 11, 2], period: 4, group: '5B', cls: 'Geçiş Metali', valence: 2, stableIon: 'V³⁺'),
  (z: 24, sym: 'Cr', trName: 'Krom', enName: 'Chromium', mass: 52, shells: [2, 8, 13, 1], period: 4, group: '6B', cls: 'Geçiş Metali', valence: 1, stableIon: 'Cr³⁺'),
  (z: 25, sym: 'Mn', trName: 'Mangan', enName: 'Manganese', mass: 55, shells: [2, 8, 13, 2], period: 4, group: '7B', cls: 'Geçiş Metali', valence: 2, stableIon: 'Mn²⁺'),
  (z: 26, sym: 'Fe', trName: 'Demir', enName: 'Iron', mass: 56, shells: [2, 8, 14, 2], period: 4, group: '8B', cls: 'Geçiş Metali', valence: 2, stableIon: 'Fe²⁺ / Fe³⁺'),
  (z: 27, sym: 'Co', trName: 'Kobalt', enName: 'Cobalt', mass: 59, shells: [2, 8, 15, 2], period: 4, group: '8B', cls: 'Geçiş Metali', valence: 2, stableIon: 'Co²⁺'),
  (z: 28, sym: 'Ni', trName: 'Nikel', enName: 'Nickel', mass: 59, shells: [2, 8, 16, 2], period: 4, group: '8B', cls: 'Geçiş Metali', valence: 2, stableIon: 'Ni²⁺'),
  (z: 29, sym: 'Cu', trName: 'Bakır', enName: 'Copper', mass: 64, shells: [2, 8, 18, 1], period: 4, group: '1B', cls: 'Geçiş Metali', valence: 1, stableIon: 'Cu²⁺'),
  (z: 30, sym: 'Zn', trName: 'Çinko', enName: 'Zinc', mass: 65, shells: [2, 8, 18, 2], period: 4, group: '2B', cls: 'Geçiş Metali', valence: 2, stableIon: 'Zn²⁺'),
  (z: 31, sym: 'Ga', trName: 'Galyum', enName: 'Gallium', mass: 70, shells: [2, 8, 18, 3], period: 4, group: '3A', cls: 'Metal', valence: 3, stableIon: 'Ga³⁺'),
  (z: 32, sym: 'Ge', trName: 'Germanyum', enName: 'Germanium', mass: 73, shells: [2, 8, 18, 4], period: 4, group: '4A', cls: 'Yarı Metal', valence: 4, stableIon: 'Ge⁴⁺'),
  (z: 33, sym: 'As', trName: 'Arsenik', enName: 'Arsenic', mass: 75, shells: [2, 8, 18, 5], period: 4, group: '5A', cls: 'Yarı Metal', valence: 5, stableIon: 'As³⁻'),
  (z: 34, sym: 'Se', trName: 'Selenyum', enName: 'Selenium', mass: 79, shells: [2, 8, 18, 6], period: 4, group: '6A', cls: 'Ametal', valence: 6, stableIon: 'Se²⁻'),
  (z: 35, sym: 'Br', trName: 'Brom', enName: 'Bromine', mass: 80, shells: [2, 8, 18, 7], period: 4, group: '7A', cls: 'Halojen (Ametal)', valence: 7, stableIon: 'Br⁻'),
  (z: 36, sym: 'Kr', trName: 'Kripton', enName: 'Krypton', mass: 84, shells: [2, 8, 18, 8], period: 4, group: '8A', cls: 'Soygaz', valence: 8, stableIon: 'Kararlı (0)'),
];

final _atomTrNames = [for (final a in _atoms36) '${a.trName} (${a.sym})'];
final _atomEnNames = [for (final a in _atoms36) a.enName];
final _atomGroups = _atoms36.map((a) => a.group).toSet().toList();
const _atomClasses = ['Ametal', 'Soygaz', 'Alkali Metal', 'Toprak Alkali Metal', 'Yarı Metal', 'Halojen (Ametal)', 'Metal', 'Geçiş Metali'];

AdvancedItem _buildAtomMaster(int i) {
  final a = _atoms36[i % _atoms36.length];
  final variant = i ~/ _atoms36.length;
  final aspect = variant % 10;
  final isotopeShift = (aspect == 3 || aspect == 6) ? (variant ~/ 10) % 3 : 0; // 0, +1, +2 neutrons
  final baseNeutrons = a.mass - a.z;
  final neutrons = baseNeutrons + isotopeShift;
  final massNum = a.z + neutrons;

  final hideSymbol = aspect == 0 || aspect == 1;
  final vis = QuestionVisual(
    kind: VisualKind.atom,
    title: 'Bohr Atom Modeli · #${i + 1}',
    summary: 'Katman elektron dizilimini ve çekirdek verilerini inceleyin.',
    labels: [hideSymbol ? '?' : a.sym],
    values: [a.z.toDouble(), neutrons.toDouble(), ...a.shells.map((e) => e.toDouble())],
    unit: 'Z=${a.z} · N=$neutrons',
  );

  switch (aspect) {
    case 0:
      final ans = '${a.trName} (${a.sym})';
      return AdvancedItem(
        'Elektron katman dizilimi ${a.shells.join(' – ')} ve atom numarası ${a.z} olan nötr atom hangi elemente aittir?',
        ans,
        _pickDistinct(_atomTrNames, ans, i + 3),
        'Z = ${a.z} protona sahip nötr atom ${a.trName} (${a.sym}) elementidir.',
        visual: vis,
      );
    case 1:
      return AdvancedItem(
        'Bohr modeli gösterilen Z = ${a.z} elementinin uluslararası İngilizce adı nedir?',
        a.enName,
        _pickDistinct(_atomEnNames, a.enName, i + 5),
        '${a.trName} (${a.sym}) elementinin İngilizce adı "${a.enName}" olarak yazılır.',
        visual: vis,
      );
    case 2:
      final v = a.shells.last;
      return AdvancedItem(
        '${a.trName} (${a.sym}) atomunun en dış katmanındaki (değerlik) elektron sayısı kaçtır?',
        '$v elektron',
        _intWrong(v, i, suffix: ' elektron', minVal: 1, maxVal: 8, deltas: const [1, -1, 2, -2, 3, -3]),
        'Katman dizilimi ${a.shells.join(' – ')} olduğundan en dış kabukta $v elektron bulunur.',
        visual: vis,
      );
    case 3:
      return AdvancedItem(
        'Çekirdeğinde ${a.z} proton ve $neutrons nötron bulunan bu ${a.trName} izotopunun kütle numarası (A) kaçtır?',
        '$massNum',
        _intWrong(massNum, i, minVal: 1, deltas: const [1, -1, 2, -2, 3, -3, 4]),
        'Kütle numarası A = Proton (Z) + Nötron (N) = ${a.z} + $neutrons = $massNum.',
        visual: vis,
      );
    case 4:
      return AdvancedItem(
        '${a.trName} (${a.sym}) elementi periyodik tabloda kaçıncı periyotta yer alır?',
        '${a.period}. Periyot',
        _pickDistinct(const ['1. Periyot', '2. Periyot', '3. Periyot', '4. Periyot', '5. Periyot'], '${a.period}. Periyot', i + 7),
        'Atomun ${a.shells.length} elektron katmanı bulunduğundan ${a.period}. Periyotta yer alır.',
        visual: vis,
      );
    case 5:
      return AdvancedItem(
        'Bohr modeli gösterilen ${a.trName} (${a.sym}) elementi hangi periyodik grup içindedir?',
        '${a.group} Grubu',
        _pickDistinct([for (final g in _atomGroups) '$g Grubu'], '${a.group} Grubu', i + 11),
        '${a.trName} (${a.sym}), ${a.period}. periyot ${a.group} grubu elementidir.',
        visual: vis,
      );
    case 6:
      return AdvancedItem(
        'Kütle numarası $massNum ve atom numarası ${a.z} olan bu ${a.trName} atomunun çekirdeğindeki nötron sayısı kaçtır?',
        '$neutrons nötron',
        _intWrong(neutrons, i, suffix: ' nötron', minVal: 0, deltas: const [1, 2, 3, -1, -2, 4, 5]),
        'Nötron sayısı N = A − Z = $massNum − ${a.z} = $neutrons bulunur.',
        visual: vis,
      );
    case 7:
      return AdvancedItem(
        '${a.trName} (${a.sym}) elementi periyodik sınıflandırmada hangi aileye dahildir?',
        a.cls,
        _pickDistinct(_atomClasses, a.cls, i + 13),
        '${a.trName} (${a.sym}) bir ${a.cls} elementidir.',
        visual: vis,
      );
    case 8:
      final charge = (a.z >= 3) ? ((variant ~/ 10) % 3) + 1 : 1; // +1, +2, +3
      final isCation = a.z >= 4 && (variant % 2 == 0);
      final elec = isCation ? a.z - charge : a.z + charge;
      final ionStr = isCation ? '${a.sym}^+$charge' : '${a.sym}^-$charge';
      return AdvancedItem(
        'Nötr ${a.trName} (Z=${a.z}) atomu ${isCation ? '$charge elektron vererek' : '$charge elektron alarak'} $ionStr iyonuna dönüşürse toplam elektron sayısı kaç olur?',
        '$elec elektron',
        _intWrong(elec, i, suffix: ' elektron', minVal: 0, deltas: const [1, -1, 2, -2, 3, -3]),
        '${isCation ? 'Katyon oluşurken elektron verilir: ${a.z} − $charge = $elec' : 'Anyon oluşurken elektron alınır: ${a.z} + $charge = $elec'} elektron.',
        visual: vis,
      );
    default:
      final totalE = a.shells.fold<int>(0, (s, x) => s + x);
      final innerE = totalE - a.shells.last;
      return AdvancedItem(
        '${a.trName} (${a.sym}) atomunun en dış katmanı HARİÇ iç katmanlarındaki toplam elektron sayısı kaçtır?',
        '$innerE elektron',
        _intWrong(innerE, i, suffix: ' elektron', minVal: 0, deltas: const [1, 2, 3, -1, -2, 4, 8]),
        'Toplam $totalE elektrondan en dış katmandaki ${a.shells.last} elektron çıkarılınca iç katmanlarda $innerE elektron kalır.',
        visual: vis,
      );
  }
}

// ===========================================================================
// 6. MÜZİK PORTESİ, NOTA, ARALIK & AKOR STÜDYOSU (2.800 soru)
// ===========================================================================
typedef _StaffNote = (String code, String trName, String enName, int semi);

const _trebleNotes = <_StaffNote>[
  ('C4', 'Do (C4)', 'C4', 0),
  ('C#4', 'Do diyez (C#4)', 'C#4', 1),
  ('D4', 'Re (D4)', 'D4', 2),
  ('Eb4', 'Mi bemol (Eb4)', 'Eb4', 3),
  ('E4', 'Mi (E4)', 'E4', 4),
  ('F4', 'Fa (F4)', 'F4', 5),
  ('F#4', 'Fa diyez (F#4)', 'F#4', 6),
  ('G4', 'Sol (G4)', 'G4', 7),
  ('Ab4', 'La bemol (Ab4)', 'Ab4', 8),
  ('A4', 'La (A4)', 'A4', 9),
  ('Bb4', 'Si bemol (Bb4)', 'Bb4', 10),
  ('B4', 'Si (B4)', 'B4', 11),
  ('C5', 'İnce Do (C5)', 'C5', 12),
  ('D5', 'İnce Re (D5)', 'D5', 14),
  ('E5', 'İnce Mi (E5)', 'E5', 16),
  ('F5', 'İnce Fa (F5)', 'F5', 17),
  ('G5', 'İnce Sol (G5)', 'G5', 19),
];

const _bassNotes = <_StaffNote>[
  ('G2', 'Kalın Sol (G2)', 'G2', -17),
  ('A2', 'Kalın La (A2)', 'A2', -15),
  ('B2', 'Kalın Si (B2)', 'B2', -13),
  ('C3', 'Kalın Do (C3)', 'C3', -12),
  ('D3', 'Kalın Re (D3)', 'D3', -10),
  ('E3', 'Kalın Mi (E3)', 'E3', -8),
  ('F3', 'Kalın Fa (F3)', 'F3', -7),
  ('G3', 'Orta Sol (G3)', 'G3', -5),
  ('A3', 'Orta La (A3)', 'A3', -3),
  ('B3', 'Orta Si (B3)', 'B3', -1),
  ('C4', 'Orta Do (C4)', 'C4', 0),
];

const _staffChords = <(String name, List<String> notes, String kind)>[
  ('Do Majör (C)', ['C4', 'E4', 'G4'], 'Majör Üçlü'),
  ('Do Minör (Cm)', ['C4', 'Eb4', 'G4'], 'Minör Üçlü'),
  ('Re Majör (D)', ['D4', 'F#4', 'A4'], 'Majör Üçlü'),
  ('Re Minör (Dm)', ['D4', 'F4', 'A4'], 'Minör Üçlü'),
  ('Mi Majör (E)', ['E4', 'G#4', 'B4'], 'Majör Üçlü'),
  ('Mi Minör (Em)', ['E4', 'G4', 'B4'], 'Minör Üçlü'),
  ('Fa Majör (F)', ['F4', 'A4', 'C5'], 'Majör Üçlü'),
  ('Fa Minör (Fm)', ['F4', 'Ab4', 'C5'], 'Minör Üçlü'),
  ('Sol Majör (G)', ['G4', 'B4', 'D5'], 'Majör Üçlü'),
  ('Sol Minör (Gm)', ['G4', 'Bb4', 'D5'], 'Minör Üçlü'),
  ('La Majör (A)', ['A4', 'C#5', 'E5'], 'Majör Üçlü'),
  ('La Minör (Am)', ['A4', 'C5', 'E5'], 'Minör Üçlü'),
  ('Si Eksilmiş (Bdim)', ['B4', 'D5', 'F5'], 'Eksilmiş Üçlü'),
  ('Do Artmış (Caug)', ['C4', 'E4', 'G#4'], 'Artmış Üçlü'),
  ('Sol Artmış (Gaug)', ['G4', 'B4', 'D#5'], 'Artmış Üçlü'),
  ('Re Eksilmiş (Ddim)', ['D4', 'F4', 'Ab4'], 'Eksilmiş Üçlü'),
];

const _intervalSpecs = <(int semi, String name)>[
  (1, 'Küçük İkili (1 yarım ses)'),
  (2, 'Büyük İkili (2 yarım ses)'),
  (3, 'Küçük Üçlü (3 yarım ses)'),
  (4, 'Büyük Üçlü (4 yarım ses)'),
  (5, 'Tam Dörtlü (5 yarım ses)'),
  (7, 'Tam Beşli (7 yarım ses)'),
  (8, 'Küçük Altılı (8 yarım ses)'),
  (9, 'Büyük Altılı (9 yarım ses)'),
  (12, 'Tam Oktav (12 yarım ses)'),
];

const _chromaticNames = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];

String _semiToNote(int semiFromC4) {
  final oct = 4 + (semiFromC4 >= 0 ? semiFromC4 ~/ 12 : -((-semiFromC4 + 11) ~/ 12));
  final idx = ((semiFromC4 % 12) + 12) % 12;
  return '${_chromaticNames[idx]}$oct';
}

AdvancedItem _buildMusicMaster(int i) {
  final mode = i % 4; // 4 modes × 700 = 2.800
  final k = i ~/ 4;
  if (mode == 0) {
    // Treble clef note reading
    final n = _trebleNotes[k % _trebleNotes.length];
    final askEn = (k ~/ _trebleNotes.length).isOdd;
    final pool = askEn
        ? [for (final x in _trebleNotes) x.$3]
        : [for (final x in _trebleNotes) x.$2];
    final ans = askEn ? n.$3 : n.$2;
    return AdvancedItem(
      askEn
          ? 'Sol anahtarı (𝄞) portesinde gösterilen bu notanın harf gösterimi (bilimsel nota adı) hangisidir?'
          : 'Sol anahtarı (𝄞) portesinde gösterilen nota aşağıdakilerden hangisidir?',
      ans,
      _pickDistinct(pool, ans, i + 5),
      'Sol anahtarında alttan 2. çizgi Sol (G4) notasıdır; gösterilen konum ${n.$2} notasına karşılık gelir.',
      visual: QuestionVisual(
        kind: VisualKind.musicStaff,
        title: 'Sol Anahtarı (Treble) Nota Okuma',
        summary: 'Porte üzerindeki notayı çizgi ve aralık konumuna göre okuyun.',
        labels: [n.$1],
        unit: 'treble',
      ),
    );
  } else if (mode == 1) {
    // Bass clef note reading
    final n = _bassNotes[k % _bassNotes.length];
    final pool = [for (final x in _bassNotes) x.$2];
    return AdvancedItem(
      'Fa anahtarı (𝄢) portesinde gösterilen nota aşağıdakilerden hangisidir?',
      n.$2,
      _pickDistinct(pool, n.$2, i + 7),
      'Fa anahtarında üstten 2. çizgi Fa (F3) notasıdır; bu konum ${n.$2} notasını gösterir.',
      visual: QuestionVisual(
        kind: VisualKind.musicStaff,
        title: 'Fa Anahtarı (Bass) Nota Okuma',
        summary: 'Fa anahtarındaki pes nota konumunu belirleyin.',
        labels: [n.$1],
        unit: 'bass',
      ),
    );
  } else if (mode == 2) {
    // Musical interval between 2 notes on treble staff
    final rootSemi = k % 7; // C4..F#4 so +12 stays <= F#5
    final spec = _intervalSpecs[(k ~/ 7) % _intervalSpecs.length];
    final n1 = _semiToNote(rootSemi);
    final n2 = _semiToNote(rootSemi + spec.$1);
    final pool = [for (final s in _intervalSpecs) s.$2];
    return AdvancedItem(
      'Sol anahtarında peş peşe gösterilen $n1 ve $n2 notaları arasındaki müzik aralığı hangisidir?',
      spec.$2,
      _pickDistinct(pool, spec.$2, i + 11),
      '$n1 ile $n2 arasında tam ${spec.$1} yarım ses bulunur; bu aralık "${spec.$2}" olarak adlandırılır.',
      visual: QuestionVisual(
        kind: VisualKind.musicStaff,
        title: 'Müzik Aralığı (Interval) Analizi',
        summary: 'İki nota arasındaki yarım ses mesafesini bulun.',
        labels: [n1, n2],
        unit: 'treble',
      ),
    );
  } else {
    // Chord identification on staff
    final ch = _staffChords[k % _staffChords.length];
    final askKind = (k ~/ _staffChords.length) % 3 == 2;
    if (askKind) {
      return AdvancedItem(
        'Sol anahtarında aynı anda basılan bu üçlü akor (${ch.$2.join(' – ')}) hangi akor türündedir?',
        ch.$3,
        _pickDistinct(const ['Majör Üçlü', 'Minör Üçlü', 'Eksilmiş Üçlü', 'Artmış Üçlü'], ch.$3, i + 13),
        '${ch.$1} akoru (${ch.$2.join(', ')}) bir ${ch.$3} akorudur.',
        visual: QuestionVisual(
          kind: VisualKind.musicStaff,
          title: 'Akor Türü Stüdyosu',
          summary: 'Portede üst üste dizilen seslerin akor yapısını belirleyin.',
          columns: const ['chord'],
          labels: ch.$2,
          unit: 'treble',
        ),
      );
    }
    final pool = [for (final c in _staffChords) c.$1];
    return AdvancedItem(
      'Sol anahtarında üst üste gösterilen bu akor (${ch.$2.join(' – ')}) hangisidir?',
      ch.$1,
      _pickDistinct(pool, ch.$1, i + 17),
      '${ch.$2.join(', ')} sesleri birleşerek ${ch.$1} akorunu oluşturur.',
      visual: QuestionVisual(
        kind: VisualKind.musicStaff,
        title: 'Akor Okuma Laboratuvarı',
        summary: 'Portedeki üçlü akorun adını bulun.',
        columns: const ['chord'],
        labels: ch.$2,
        unit: 'treble',
      ),
    );
  }
}

// ===========================================================================
// 7. 3×3 MATRİS, ÖRÜNTÜ & ZEKA KÜPÜ STÜDYOSU (4.000 soru)
// ===========================================================================
AdvancedItem _buildMatrixMaster(int i) {
  final rule = i % 8; // 8 rules × 500 = 4.000
  final k = i ~/ 8;
  late final List<List<int>> grid;
  late final String explain;
  late final String title;

  if (rule == 0) {
    // Row arithmetic progression
    final a = 2 + (k % 15);
    final dr = 2 + ((k ~/ 15) % 9);
    final dc = 2 + ((k ~/ 135) % 7);
    grid = [
      [a, a + dc, a + 2 * dc],
      [a + dr, a + dr + dc, a + dr + 2 * dc],
      [a + 2 * dr, a + 2 * dr + dc, a + 2 * dr + 2 * dc],
    ];
    title = '3×3 Aritmetik Matris';
    explain = 'Her satırda sayılar +$dc artmakta, her sütunda +$dr artmaktadır. Son hücre = ${grid[2][2]}.';
  } else if (rule == 1) {
    // Row sum: c3 = c1 + c2
    final r0a = 3 + (k % 18);
    final r0b = 4 + ((k * 3) % 19);
    final r1a = 5 + ((k * 5) % 21);
    final r1b = 2 + ((k * 7) % 17);
    final r2a = 6 + ((k * 11) % 23);
    final r2b = 3 + ((k * 13) % 20);
    grid = [
      [r0a, r0b, r0a + r0b],
      [r1a, r1b, r1a + r1b],
      [r2a, r2b, r2a + r2b],
    ];
    title = 'Satır Toplam Matrisi';
    explain = 'Her satırda 3. sütun = 1. sütun + 2. sütun kuralı geçerlidir: $r2a + $r2b = ${grid[2][2]}.';
  } else if (rule == 2) {
    // Linear combo: c3 = 2*c1 + c2
    final r0a = 2 + (k % 10);
    final r0b = 1 + ((k * 3) % 12);
    final r1a = 3 + ((k * 5) % 11);
    final r1b = 2 + ((k * 7) % 13);
    final r2a = 4 + ((k * 2) % 12);
    final r2b = 3 + ((k * 4) % 14);
    grid = [
      [r0a, r0b, 2 * r0a + r0b],
      [r1a, r1b, 2 * r1a + r1b],
      [r2a, r2b, 2 * r2a + r2b],
    ];
    title = 'Ağırlıklı Örüntü Matrisi';
    explain = 'Her satırda 3. sayı = 2 × (1. sayı) + (2. sayı): 2 × $r2a + $r2b = ${grid[2][2]}.';
  } else if (rule == 3) {
    // Row product: c3 = c1 * c2
    final r0a = 2 + (k % 8);
    final r0b = 3 + ((k * 3) % 9);
    final r1a = 3 + ((k * 5) % 8);
    final r1b = 2 + ((k * 7) % 9);
    final r2a = 4 + ((k * 2) % 8);
    final r2b = 2 + ((k * 4) % 9);
    grid = [
      [r0a, r0b, r0a * r0b],
      [r1a, r1b, r1a * r1b],
      [r2a, r2b, r2a * r2b],
    ];
    title = 'Çarpım Matrisi';
    explain = 'Her satırda ilk iki sayının çarpımı üçüncü hücreyi verir: $r2a × $r2b = ${grid[2][2]}.';
  } else if (rule == 4) {
    // Column sum: r3 = r1 + r2
    final c0a = 4 + (k % 15);
    final c0b = 5 + ((k * 3) % 16);
    final c1a = 3 + ((k * 5) % 17);
    final c1b = 6 + ((k * 7) % 14);
    final c2a = 7 + ((k * 11) % 18);
    final c2b = 4 + ((k * 13) % 19);
    grid = [
      [c0a, c1a, c2a],
      [c0b, c1b, c2b],
      [c0a + c0b, c1a + c1b, c2a + c2b],
    ];
    title = 'Sütun Toplam Matrisi';
    explain = 'Her sütunda ilk iki satırın toplamı alt satırı verir: $c2a + $c2b = ${grid[2][2]}.';
  } else if (rule == 5) {
    // Magic square: Lo Shu transformed m + s*[-3,4,-1; 2,0,-2; 1,-4,3]
    final s = 1 + (k % 6);
    final m = 4 * s + 3 + (k ~/ 6);
    grid = [
      [m - 3 * s, m + 4 * s, m - s],
      [m + 2 * s, m, m - 2 * s],
      [m + s, m - 4 * s, m + 3 * s],
    ];
    title = 'Sihirli Kare Matrisi';
    explain = 'Tüm satır, sütun ve köşegen toplamları ${3 * m} eşittir. Son hücre = ${3 * m} − (${grid[2][0]} + ${grid[2][1]}) = ${grid[2][2]}.';
  } else if (rule == 6) {
    // Row product minus first: c3 = c1 * c2 + k0
    final shift = 1 + (k % 7);
    final r0a = 2 + (k % 6);
    final r0b = 3 + ((k * 3) % 6);
    final r1a = 3 + ((k * 5) % 6);
    final r1b = 4 + ((k * 2) % 6);
    final r2a = 4 + ((k * 7) % 6);
    final r2b = 3 + ((k * 4) % 6);
    grid = [
      [r0a, r0b, r0a * r0b + shift],
      [r1a, r1b, r1a * r1b + shift],
      [r2a, r2b, r2a * r2b + shift],
    ];
    title = 'Kural Keşif Matrisi';
    explain = 'Her satırda 3. hücre = (1. × 2.) + $shift kuralına uyar: $r2a × $r2b + $shift = ${grid[2][2]}.';
  } else {
    // Square + offset pattern: c2 = c1 + d, c3 = c2 + 2d (step doubles)
    final d = 2 + (k % 9);
    final a0 = 3 + ((k * 2) % 12);
    final a1 = 5 + ((k * 3) % 14);
    final a2 = 4 + ((k * 5) % 15);
    grid = [
      [a0, a0 + d, a0 + 3 * d],
      [a1, a1 + d, a1 + 3 * d],
      [a2, a2 + d, a2 + 3 * d],
    ];
    title = 'Katlanan Artış Matrisi';
    explain = 'Her satırda önce +$d, ardından +${2 * d} eklenmektedir: ${grid[2][1]} + ${2 * d} = ${grid[2][2]}.';
  }

  final ans = grid[2][2];
  final rows = [
    ['${grid[0][0]}', '${grid[0][1]}', '${grid[0][2]}'],
    ['${grid[1][0]}', '${grid[1][1]}', '${grid[1][2]}'],
    ['${grid[2][0]}', '${grid[2][1]}', '?'],
  ];
  return AdvancedItem(
    '3×3 sayı matrisindeki mantıksal kuralı keşfedin. "?" yerine hangi sayı gelmelidir?',
    '$ans',
    _intWrong(ans, i, minVal: 1, deltas: const [1, -1, 2, -2, 3, -3, 4, -4, 5, -5]),
    explain,
    visual: QuestionVisual(
      kind: VisualKind.matrix,
      title: title,
      summary: 'Satır ve sütunlar arasındaki sayısal ilişkiyi bulun.',
      rows: rows,
    ),
  );
}

final List<AdvancedFamily> visualExpand25kFamilies = [
  AdvancedFamily(
    key: 's100_flag_deep',
    title: 'Derin Dünya Bayrakları Görsel Atlası',
    topic: Topic.geography,
    level: StudyLevel.lise,
    count: 3200,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.flag,
    bloom: BloomLevel.anlama,
    sourceLabel: 'Bilgili 3.21 · Görsel Stüdyo 100K',
    build: _buildFlagDeep,
  ),
  AdvancedFamily(
    key: 's100_clock_master',
    title: 'Analog Saat, Açı, Ayna & İngilizce Zaman',
    topic: Topic.mathematics,
    level: StudyLevel.lise,
    count: 4000,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.clock,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.21 · Görsel Stüdyo 100K',
    build: _buildClockMaster,
  ),
  AdvancedFamily(
    key: 's100_pie_analytics',
    title: 'Pasta Grafiği & Daire Veri Analitiği',
    topic: Topic.statistics,
    level: StudyLevel.lise,
    count: 3600,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.pieChart,
    bloom: BloomLevel.analiz,
    sourceLabel: 'Bilgili 3.21 · Görsel Stüdyo 100K',
    build: _buildPieAnalytics,
  ),
  AdvancedFamily(
    key: 's100_coord_master',
    title: 'Koordinat Düzlemi, Geometri & Vektör Laboratuvarı',
    topic: Topic.mathematics,
    level: StudyLevel.lise,
    count: 4400,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.coordPlane,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.21 · Görsel Stüdyo 100K',
    build: _buildCoordMaster,
  ),
  AdvancedFamily(
    key: 's100_atom_master',
    title: 'Bohr Atom, İzotop & İyon Laboratuvarı',
    topic: Topic.chemistry,
    level: StudyLevel.lise,
    count: 3000,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.atom,
    bloom: BloomLevel.analiz,
    sourceLabel: 'Bilgili 3.21 · Görsel Stüdyo 100K',
    build: _buildAtomMaster,
  ),
  AdvancedFamily(
    key: 's100_music_master',
    title: 'Müzik Portesi, Sol-Fa Anahtarı, Aralık & Akor',
    topic: Topic.music,
    level: StudyLevel.lise,
    count: 2800,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.musicStaff,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.21 · Görsel Stüdyo 100K',
    build: _buildMusicMaster,
  ),
  AdvancedFamily(
    key: 's100_matrix_master',
    title: '3×3 Mantık Matrisi & Sihirli Kare Stüdyosu',
    topic: Topic.computing,
    level: StudyLevel.lise,
    count: 4000,
    difficulty: Difficulty.hard,
    visualKind: VisualKind.matrix,
    bloom: BloomLevel.analiz,
    sourceLabel: 'Bilgili 3.21 · Görsel Stüdyo 100K',
    build: _buildMatrixMaster,
  ),
];
