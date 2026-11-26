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
  String prefix = '',
  String suffix = '',
  int minVal = 0,
  List<int> deltas = const [1, -1, 2, -2, 3, -3, 5, -5, 10, -10, 4, 6],
}) {
  final out = <String>[];
  final seen = <int>{correct};
  final offset = seed.abs() % deltas.length;
  for (var k = 0; k < deltas.length * 2 && out.length < 3; k++) {
    final d = deltas[(offset + k) % deltas.length];
    final v = correct + d;
    if (v >= minVal && seen.add(v)) {
      out.add('$prefix$v$suffix');
    }
  }
  var bump = 1;
  while (out.length < 3) {
    final v = correct + bump;
    if (seen.add(v)) out.add('$prefix$v$suffix');
    bump++;
  }
  return out;
}

const _accents = ['en-US', 'en-GB', 'en-AU'];
String _accentAt(int i) => _accents[i % _accents.length];

const _enCities = <(String en, String tr)>[
  ('London', 'Londra'), ('Edinburgh', 'Edinburg'), ('Dublin', 'Dublin'),
  ('Paris', 'Paris'), ('Rome', 'Roma'), ('Madrid', 'Madrid'),
  ('Vienna', 'Viyana'), ('Zurich', 'Zürih'), ('Stockholm', 'Stockholm'),
  ('Oslo', 'Oslo'), ('Prague', 'Prag'), ('Athens', 'Atina'),
  ('Lisbon', 'Lizbon'), ('Tokyo', 'Tokyo'), ('Seoul', 'Seul'),
  ('Toronto', 'Toronto'), ('Boston', 'Boston'), ('Seattle', 'Seattle'),
  ('Sydney', 'Sidney'), ('Melbourne', 'Melburn'), ('Auckland', 'Auckland'),
  ('Berlin', 'Berlin'), ('Munich', 'Münih'), ('Amsterdam', 'Amsterdam'),
];

const _enDays = <(String en, String tr)>[
  ('Monday', 'Pazartesi'), ('Tuesday', 'Salı'), ('Wednesday', 'Çarşamba'),
  ('Thursday', 'Perşembe'), ('Friday', 'Cuma'), ('Saturday', 'Cumartesi'),
  ('Sunday', 'Pazar'),
];

const _enMonths = <(String en, String tr)>[
  ('January', 'Ocak'), ('February', 'Şubat'), ('March', 'Mart'),
  ('April', 'Nisan'), ('May', 'Mayıs'), ('June', 'Haziran'),
  ('July', 'Temmuz'), ('August', 'Ağustos'), ('September', 'Eylül'),
  ('October', 'Ekim'), ('November', 'Kasım'), ('December', 'Aralık'),
];

const _enNames = [
  'Emma', 'Liam', 'Olivia', 'Noah', 'Clara', 'Lucas', 'Hannah', 'Daniel',
  'Sophie', 'Ethan', 'Maya', 'Jack', 'Grace', 'Oliver', 'Nora', 'Sam',
];

// ===========================================================================
// 1. SESLİ İNGİLİZCE DİYALOG & ANONS STÜDYOSU (14 Senaryo × 500 = 7.000 soru)
// ===========================================================================
const _hotelExtras = <(String en, String tr)>[
  ('breakfast buffet', 'açık büfe kahvaltı'),
  ('airport shuttle', 'havalimanı servisi'),
  ('late checkout', 'geç çıkış hakkı'),
  ('spa access', 'spa ve hamam girişi'),
  ('high-speed internet', 'yüksek hızlı internet'),
  ('underground parking', 'kapalı otopark'),
  ('gym membership', 'spor salonu kullanımı'),
  ('balcony sea view', 'deniz manzaralı balkon'),
];

const _cafeItems = <(String en, String tr)>[
  ('iced latte and a blueberry muffin', 'buzlu latte ve yaban mersinli kek'),
  ('green tea and a toasted sandwich', 'yeşil çay ve tost'),
  ('espresso and a warm croissant', 'espresso ve sıcak kruvasan'),
  ('fresh orange juice and pancakes', 'taze portakal suyu ve pankek'),
  ('cappuccino and a slice of cheesecake', 'kapuçino ve bir dilim cheesecake'),
  ('herbal tea and an avocado wrap', 'bitki çayı ve avokadolu dürüm'),
  ('hot chocolate and an apple pie', 'sıcak çikolata ve elmalı turta'),
  ('mineral water and a caesar salad', 'maden suyu ve sezar salata'),
];

const _medAdvice = <(String en, String tr)>[
  ('take one tablet after dinner for five days', 'beş gün boyunca akşam yemeğinden sonra bir tablet alması'),
  ('drink plenty of warm water and rest indoors', 'bol ılık su içip evde dinlenmesi'),
  ('avoid heavy lifting for two weeks', 'iki hafta boyunca ağır kaldırmaktan kaçınması'),
  ('return for a follow-up check on Friday morning', 'Cuma sabahı kontrol muayenesine gelmesi'),
  ('apply the cooling gel twice a day', 'serinletici jeli günde iki kez sürmesi'),
  ('keep the wrist wrapped until Monday', 'Pazartesi gününe kadar bileği sarılı tutması'),
  ('schedule a blood test before breakfast', 'kahvaltıdan önce kan tahlili yaptırması'),
  ('use the nasal spray only before bedtime', 'burun spreyini yalnızca yatmadan önce kullanması'),
];

const _delayReasons = <(String en, String tr)>[
  ('heavy fog near the runway', 'pist yakınındaki yoğun sis'),
  ('a routine technical inspection', 'rutin teknik kontrol'),
  ('strong crosswinds over the coast', 'kıyıdaki şiddetli yan rüzgârlar'),
  ('air traffic congestion', 'hava trafiği yoğunluğu'),
  ('late arrival of the incoming crew', 'uçuş ekibinin geç ulaşması'),
  ('sudden snow clearing on the tarmac', 'pistteki ani kar temizliği'),
];

const _departments = <(String en, String tr)>[
  ('Product Design', 'Ürün Tasarımı'),
  ('Data Science', 'Veri Bilimi'),
  ('Customer Success', 'Müşteri Başarısı'),
  ('Mobile Engineering', 'Mobil Mühendislik'),
  ('Cybersecurity', 'Siber Güvenlik'),
  ('Renewable Energy', 'Yenilenebilir Enerji'),
  ('Digital Marketing', 'Dijital Pazarlama'),
  ('Financial Planning', 'Finansal Planlama'),
];

const _techIssues = <(String en, String tr)>[
  ('reset the router and update the firmware', 'yönlendiriciyi sıfırlayıp yazılımı güncellemek'),
  ('clear the browser cache and sign in again', 'tarayıcı önbelleğini temizleyip tekrar giriş yapmak'),
  ('replace the charging cable with a certified one', 'şarj kablosunu onaylı bir kabloyla değiştirmek'),
  ('enable two-factor authentication in settings', 'ayarlardan iki adımlı doğrulamayı açmak'),
  ('back up the photos before reinstalling the app', 'uygulamayı yeniden kurmadan önce fotoğrafları yedeklemek'),
  ('switch from public Wi-Fi to a private hotspot', 'ortak Wi-Fi yerine kişisel erişim noktasına geçmek'),
];

const _museumWings = <(String en, String tr)>[
  ('Ancient Pottery Gallery on the second floor', 'İkinci kattaki Antik Seramik Galerisi'),
  ('Maritime Maps Hall near the east courtyard', 'Doğu avlusu yanındaki Deniz Haritaları Salonu'),
  ('Modern Sculpture Wing beside the glass atrium', 'Cam atriyum yanındaki Modern Heykel Kanadı'),
  ('Astronomy Instruments Room on the third floor', 'Üçüncü kattaki Astronomi Aletleri Odası'),
  ('Botanical Prints Archive in the west wing', 'Batı kanadındaki Botanik Baskılar Arşivi'),
  ('Classical Music Manuscripts Hall on the ground floor', 'Zemin kattaki Klasik Müzik El Yazmaları Salonu'),
];

const _weatherConditions = <(String en, String tr)>[
  ('bright sunshine in the morning and light showers after five', 'sabah güneşli, saat beşten sonra hafif sağanak'),
  ('gusty winds along the harbor with clear skies overnight', 'liman boyunca sert rüzgâr ve gece açık gökyüzü'),
  ('scattered clouds at noon followed by a sharp drop in temperature', 'öğlen parçalı bulutlu, ardından keskin sıcaklık düşüşü'),
  ('mild afternoon breezes ideal for outdoor cycling', 'açık havada bisiklet için uygun ılık öğleden sonra esintisi'),
  ('dense coastal mist clearing just before midday', 'öğleden hemen önce dağılan yoğun kıyı sisi'),
  ('warm dry air across the valley with high UV levels', 'vadi boyunca sıcak kuru hava ve yüksek UV düzeyi'),
];

const _libraryRules = <(String en, String tr)>[
  ('borrow up to six books for three weeks', 'üç haftalığına en fazla altı kitap ödünç almak'),
  ('reserve a quiet study cabin two days in advance', 'sessiz çalışma kabinini iki gün önceden ayırtmak'),
  ('return reference dictionaries before closing at nine', 'başvuru sözlüklerini saat dokuzdaki kapanıştan önce iade etmek'),
  ('use the digital scanner on the mezzanine free of charge', 'ara kattaki dijital tarayıcıyı ücretsiz kullanmak'),
  ('renew loans online unless another reader is waiting', 'başka bir okur beklemiyorsa süreyi çevrim içi uzatmak'),
  ('bring a student card to access the archival basement', 'arşiv katına girmek için öğrenci kartı getirmek'),
];

const _returnReasons = <(String en, String tr)>[
  ('the jacket sleeves were slightly too short', 'ceketin kollarının biraz kısa olması'),
  ('the backpack zipper jammed on the first trip', 'sırt çantasının fermuarının ilk yolculukta takılması'),
  ('the running shoes ran half a size small', 'koşu ayakkabısının yarım numara küçük gelmesi'),
  ('the wireless headphones arrived in the wrong color', 'kablosuz kulaklığın yanlış renkte gelmesi'),
  ('the desk lamp had a flickering power switch', 'masa lambasının güç anahtarının titremesi'),
  ('the ceramic kettle arrived with a chipped lid', 'seramik su ısıtıcısının kapağının çatlak gelmesi'),
];

AdvancedItem _buildDialogue100k(int i) {
  final scene = i % 14;
  final k = i ~/ 14;
  final lang = _accentAt(i);
  final city = _enCities[k % _enCities.length];
  final day = _enDays[k % _enDays.length];
  final month = _enMonths[k % _enMonths.length];
  final name = _enNames[k % _enNames.length];

  switch (scene) {
    case 0:
      // Airport boarding gate & delay reason
      final gate = 10 + (k % 38);
      final reason = _delayReasons[(k ~/ 3) % _delayReasons.length];
      final askReason = k.isOdd;
      final transcript =
          'Attention please. Flight to ${city.$1} is now boarding at Gate $gate after a brief delay caused by ${reason.$1}. Please have your boarding pass ready.';
      if (askReason) {
        return AdvancedItem(
          'Havalimanı anonsunu dinleyin. ${city.$2} uçuşundaki kısa gecikmenin sebebi nedir?',
          reason.$2,
          _pickDistinct([for (final r in _delayReasons) r.$2], reason.$2, i + 3),
          'Anonsta gecikme nedeni "${reason.$1}" (${reason.$2}) olarak açıklanıyor.',
          activity: QuestionActivity(
            kind: ActivityKind.listening,
            title: 'Havalimanı Anonsu · Dinleme',
            language: lang,
            transcript: transcript,
          ),
        );
      }
      return AdvancedItem(
        'İngilizce havalimanı anonsunu dinleyin. ${city.$2} uçağı hangi kapıdan yolcu alıyor?',
        'Kapı $gate',
        _intWrong(gate, i, prefix: 'Kapı ', minVal: 1, deltas: const [2, -2, 4, -4, 6, 10]),
        'Anons "${city.$1} ... at Gate $gate" diyerek Kapı $gate bilgisini veriyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Havalimanı Biniş Kapısı',
          language: lang,
          transcript: transcript,
        ),
      );
    case 1:
      // Hotel check-in extra & floor
      final extra = _hotelExtras[k % _hotelExtras.length];
      final nights = 2 + (k % 6);
      final floor = 2 + ((k * 3) % 11);
      final transcript =
          'Welcome to the Harbor Hotel, $name. Your reservation for $nights nights on floor $floor is confirmed, and your booking includes complimentary ${extra.$1}.';
      return AdvancedItem(
        'Otel resepsiyonu konuşmasını dinleyin. $name için rezervasyona ücretsiz dahil edilen hizmet hangisidir?',
        extra.$2,
        _pickDistinct([for (final e in _hotelExtras) e.$2], extra.$2, i + 5),
        'Resepsiyon görevlisi "includes complimentary ${extra.$1}" (${extra.$2}) ifadesini kullanıyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Otel Resepsiyonu · Diyalog',
          language: lang,
          transcript: transcript,
        ),
      );
    case 2:
      // Restaurant / Cafe order
      final order = _cafeItems[k % _cafeItems.length];
      final price = 8 + (k % 17);
      final transcript =
          'Hi! Could I please order an ${order.$1}? Sure thing, $name. Your total comes to $price dollars, and we will bring it to table six in five minutes.';
      return AdvancedItem(
        'Kafe diyaloğunu dinleyin. Müşteri ne sipariş etmiştir?',
        order.$2,
        _pickDistinct([for (final c in _cafeItems) c.$2], order.$2, i + 7),
        'Müşteri "${order.$1}" (${order.$2}) sipariş etmiştir.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Kafe & Restoran Siparişi',
          language: lang,
          transcript: transcript,
        ),
      );
    case 3:
      // Doctor / Pharmacy advice
      final advice = _medAdvice[k % _medAdvice.length];
      final transcript =
          'Hello $name, your test results look encouraging. To recover fully, please ${advice.$1}. Call our clinic if you notice any discomfort.';
      return AdvancedItem(
        'Doktor görüşmesini dinleyin. Doktor, $name adlı hastaya ne yapmasını öneriyor?',
        advice.$2,
        _pickDistinct([for (final m in _medAdvice) m.$2], advice.$2, i + 11),
        'Doktor "please ${advice.$1}" (${advice.$2}) tavsiyesinde bulunuyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Klinik & Sağlık Diyaloğu',
          language: lang,
          transcript: transcript,
        ),
      );
    case 4:
      // Job interview department & day
      final dept = _departments[k % _departments.length];
      final hour = 9 + (k % 8);
      final transcript =
          'Thank you for applying to our ${dept.$1} team, $name. We would love to invite you for a final interview on ${day.$1} at $hour o’clock in our ${city.$1} office.';
      final askDept = k.isEven;
      if (askDept) {
        return AdvancedItem(
          'İş görüşmesi davetini dinleyin. $name hangi departman için son mülakata çağrılıyor?',
          dept.$2,
          _pickDistinct([for (final d in _departments) d.$2], dept.$2, i + 13),
          'Mesajda "${dept.$1} team" (${dept.$2}) ekibi belirtilmektedir.',
          activity: QuestionActivity(
            kind: ActivityKind.listening,
            title: 'İş Mülakatı Daveti',
            language: lang,
            transcript: transcript,
          ),
        );
      }
      return AdvancedItem(
        'İş görüşmesi davetini dinleyin. Son mülakat hangi gün yapılacaktır?',
        day.$2,
        _pickDistinct([for (final d in _enDays) d.$2], day.$2, i + 17),
        'Mülakat günü "${day.$1}" (${day.$2}) olarak bildirilmektedir.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Mülakat Günü Dinleme',
          language: lang,
          transcript: transcript,
        ),
      );
    case 5:
      // Tech support solution
      final fix = _techIssues[k % _techIssues.length];
      final ticket = 200 + (k % 750);
      final transcript =
          'Tech support speaking, ticket number $ticket. To solve this connection issue right away, please ${fix.$1}. Let me know once the green light stays steady.';
      return AdvancedItem(
        'Teknik destek görüşmesini dinleyin. Uzmanın sorunu çözmek için önerdiği adım nedir?',
        fix.$2,
        _pickDistinct([for (final t in _techIssues) t.$2], fix.$2, i + 19),
        'Uzman "please ${fix.$1}" (${fix.$2}) adımını öneriyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Teknik Destek Görüşmesi',
          language: lang,
          transcript: transcript,
        ),
      );
    case 6:
      // Train station platform & destination
      final platform = 1 + (k % 18);
      final mins = 5 + ((k * 3) % 40);
      final transcript =
          'The express train to ${city.$1} will depart from Platform $platform in $mins minutes. Passengers with bicycles should board the rear carriage.';
      final askCity = k.isEven;
      if (askCity) {
        return AdvancedItem(
          'Tren istasyonu anonsunu dinleyin. Ekspres tren hangi şehre hareket edecektir?',
          city.$2,
          _pickDistinct([for (final c in _enCities) c.$2], city.$2, i + 23),
          'Anonsta "express train to ${city.$1}" (${city.$2}) ifadesi yer alıyor.',
          activity: QuestionActivity(
            kind: ActivityKind.listening,
            title: 'Tren İstasyonu Anonsu',
            language: lang,
            transcript: transcript,
          ),
        );
      }
      return AdvancedItem(
        'Tren anonsunu dinleyin. ${city.$2} ekspres treni hangi perondan kalkacaktır?',
        'Peron $platform',
        _intWrong(platform, i, prefix: 'Peron ', minVal: 1, deltas: const [1, -1, 2, -2, 3, 4]),
        'Anons "depart from Platform $platform" diyerek Peron $platform bilgisini veriyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Tren Peron Bilgisi',
          language: lang,
          transcript: transcript,
        ),
      );
    case 7:
      // Museum guided tour location
      final wing = _museumWings[k % _museumWings.length];
      final startH = 10 + (k % 7);
      final transcript =
          'Welcome visitors! Our free English guided tour begins at $startH o’clock in the ${wing.$1}. Audio headsets are available near the entrance.';
      return AdvancedItem(
        'Müze anonsunu dinleyin. Ücretsiz rehberli tur nerede başlamaktadır?',
        wing.$2,
        _pickDistinct([for (final w in _museumWings) w.$2], wing.$2, i + 29),
        'Rehberli turun başlangıç yeri "${wing.$1}" (${wing.$2}) olarak anons ediliyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Müze Rehber Anonsu',
          language: lang,
          transcript: transcript,
        ),
      );
    case 8:
      // Weather forecast
      final cond = _weatherConditions[k % _weatherConditions.length];
      final temp = 10 + (k % 24);
      final transcript =
          'Here is your ${day.$1} forecast for ${city.$1}. Expect ${cond.$1}, with daytime highs reaching $temp degrees Celsius.';
      return AdvancedItem(
        'İngilizce hava durumu bültenini dinleyin. ${city.$2} için beklenen hava koşulu hangisidir?',
        cond.$2,
        _pickDistinct([for (final c in _weatherConditions) c.$2], cond.$2, i + 31),
        'Bülten "${cond.$1}" (${cond.$2}) beklendiğini bildiriyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Hava Durumu Bülteni',
          language: lang,
          transcript: transcript,
        ),
      );
    case 9:
      // University library rule
      final rule = _libraryRules[k % _libraryRules.length];
      final transcript =
          'Welcome to the Central Campus Library, $name. With your new membership card, you can ${rule.$1}. Please remember to keep phones silent.';
      return AdvancedItem(
        'Üniversite kütüphanesi bilgilendirmesini dinleyin. Yeni üyelik kartı hangi hakkı veya kuralı içeriyor?',
        rule.$2,
        _pickDistinct([for (final r in _libraryRules) r.$2], rule.$2, i + 37),
        'Kütüphane görevlisi "${rule.$1}" (${rule.$2}) bilgisini paylaşıyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Kampüs Kütüphanesi',
          language: lang,
          transcript: transcript,
        ),
      );
    case 10:
      // Shopping return reason
      final reason = _returnReasons[k % _returnReasons.length];
      final transcript =
          'Hi, I bought this item online last ${day.$1}, and I would like to exchange it because ${reason.$1}. Here is my digital receipt.';
      return AdvancedItem(
        'Mağaza iade diyaloğunu dinleyin. Müşteri ürünü neden değiştirmek istiyor?',
        reason.$2,
        _pickDistinct([for (final r in _returnReasons) r.$2], reason.$2, i + 41),
        'Müşteri iade gerekçesini "${reason.$1}" (${reason.$2}) şeklinde ifade ediyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Mağaza & İade Diyaloğu',
          language: lang,
          transcript: transcript,
        ),
      );
    case 11:
      // Office meeting rescheduled month/day
      final dayNum = 5 + (k % 23);
      final transcript =
          'Hi $name, just a quick voice note: we moved the quarterly architecture review to ${month.$1} $dayNum on ${day.$1} so our ${city.$1} engineers can join live.';
      return AdvancedItem(
        'Ofis sesli mesajını dinleyin. Toplantı hangi ay ve güne ertelenmiştir?',
        '$dayNum ${month.$2}',
        [
          '$dayNum ${_enMonths[(k + 1) % 12].$2}',
          '${dayNum + 2} ${month.$2}',
          '${dayNum > 3 ? dayNum - 2 : dayNum + 4} ${month.$2}',
        ],
        'Sesli mesaj toplantının "${month.$1} $dayNum" ($dayNum ${month.$2}) tarihine alındığını belirtiyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Ofis Sesli Notu',
          language: lang,
          transcript: transcript,
        ),
      );
    case 12:
      // Bank / payment fee & currency
      final amount = 120 + (k % 40) * 15;
      final daysWait = 1 + (k % 5);
      final transcript =
          'Good afternoon $name. Your international transfer of $amount euros to ${city.$1} has been approved and will arrive within $daysWait business days with zero commission.';
      return AdvancedItem(
        'Banka bilgilendirme kaydını dinleyin. ${city.$2} yönüne yapılan uluslararası transfer tutarı kaç eurodur?',
        '$amount euro',
        _intWrong(amount, i, suffix: ' euro', minVal: 20, deltas: const [15, -15, 30, -30, 50, -50]),
        'Kayıtta "transfer of $amount euros" ($amount euro) bilgisi net biçimde geçiyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Banka & Finans Kaydı',
          language: lang,
          transcript: transcript,
        ),
      );
    default:
      // Gym / sports schedule
      const classes = <(String en, String tr)>[
        ('morning swimming lap session', 'sabah yüzme antrenmanı'),
        ('indoor rock climbing workshop', 'kapalı salon kaya tırmanışı atölyesi'),
        ('evening pilates and stretching class', 'akşam pilates ve esneme dersi'),
        ('group cycling endurance ride', 'grup bisiklet dayanıklılık sürüşü'),
        ('beginner tennis footwork clinic', 'başlangıç tenis ayak çalışması'),
        ('outdoor park running club', 'açık hava park koşu kulübü'),
      ];
      final cls = classes[k % classes.length];
      final spots = 3 + (k % 12);
      final transcript =
          'Hello members! There are only $spots spots remaining for our ${day.$1} ${cls.$1} led by coach $name. Sign up at the front desk.';
      return AdvancedItem(
        'Spor merkezi duyurusunu dinleyin. Kontenjanı sınırlı olan etkinlik hangisidir?',
        cls.$2,
        _pickDistinct([for (final c in classes) c.$2], cls.$2, i + 43),
        'Duyuruda "${cls.$1}" (${cls.$2}) için yalnızca $spots yer kaldığı söyleniyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Spor Merkezi Duyurusu',
          language: lang,
          transcript: transcript,
        ),
      );
  }
}

// ===========================================================================
// 2. SESLİ İNGİLİZCE KELİME, PHRASAL VERB & DEYİM (125 × 40 = 5.000 soru)
// ===========================================================================
typedef _VocabItem = ({
  String term,
  String tr,
  String syn,
  String sent,
  String lvl,
});

const _vocab125 = <_VocabItem>[
  (term: 'accomplish', tr: 'başarmak / tamamlamak', syn: 'achieve', sent: 'With steady effort, you can accomplish ambitious goals.', lvl: 'B1'),
  (term: 'accurate', tr: 'doğru / hatasız', syn: 'precise', sent: 'The new sensor gives accurate temperature readings.', lvl: 'B1'),
  (term: 'adapt', tr: 'uyum sağlamak', syn: 'adjust', sent: 'Mountain plants adapt quickly to cold winds.', lvl: 'B1'),
  (term: 'adequate', tr: 'yeterli', syn: 'sufficient', sent: 'Make sure you get adequate sleep before the exam.', lvl: 'B2'),
  (term: 'adjacent', tr: 'bitişik / komşu', syn: 'neighboring', sent: 'The bakery is adjacent to the subway exit.', lvl: 'B2'),
  (term: 'ambiguous', tr: 'belirsiz / çift anlamlı', syn: 'unclear', sent: 'The contract contained an ambiguous sentence.', lvl: 'C1'),
  (term: 'ancient', tr: 'antik / çok eski', syn: 'historic', sent: 'Archeologists uncovered an ancient harbor wall.', lvl: 'A2'),
  (term: 'anticipate', tr: 'öngörmek / beklemek', syn: 'expect', sent: 'Engineers anticipate heavy traffic over the holiday.', lvl: 'B2'),
  (term: 'apparent', tr: 'açık / belirgin', syn: 'obvious', sent: 'Her improvement in speaking became apparent immediately.', lvl: 'B2'),
  (term: 'appreciate', tr: 'takdir etmek / minnet duymak', syn: 'value', sent: 'We truly appreciate your patient feedback.', lvl: 'B1'),
  (term: 'approach', tr: 'yaklaşmak / yöntem', syn: 'method', sent: 'Let us try a more visual approach to this puzzle.', lvl: 'B1'),
  (term: 'arbitrary', tr: 'keyfi / rastgele', syn: 'random', sent: 'The scoring rule must be fair, not arbitrary.', lvl: 'C1'),
  (term: 'assess', tr: 'değerlendirmek / ölçmek', syn: 'evaluate', sent: 'Short quizzes help assess weekly progress.', lvl: 'B2'),
  (term: 'astonishing', tr: 'şaşırtıcı / hayret verici', syn: 'amazing', sent: 'The telescope captured an astonishing view of Jupiter.', lvl: 'B2'),
  (term: 'authentic', tr: 'özgün / gerçek', syn: 'genuine', sent: 'The museum displayed authentic Ottoman maps.', lvl: 'B2'),
  (term: 'beneficial', tr: 'faydalı / yararlı', syn: 'helpful', sent: 'Daily walking is beneficial for focus and health.', lvl: 'B2'),
  (term: 'brief', tr: 'kısa / öz', syn: 'short', sent: 'The pilot gave a brief update before landing.', lvl: 'B1'),
  (term: 'brilliant', tr: 'parlak / zeki', syn: 'clever', sent: 'That was a brilliant way to solve the circuit.', lvl: 'B1'),
  (term: 'cautious', tr: 'tedbirli / dikkatli', syn: 'careful', sent: 'Drivers should be cautious on icy mountain roads.', lvl: 'B2'),
  (term: 'cease', tr: 'durmak / sona ermek', syn: 'stop', sent: 'Ferry services will cease during the storm.', lvl: 'C1'),
  (term: 'coherent', tr: 'tutarlı / anlaşılır', syn: 'logical', sent: 'She presented a coherent plan for the project.', lvl: 'C1'),
  (term: 'collaborate', tr: 'iş birliği yapmak', syn: 'cooperate', sent: 'Musicians and designers collaborate in this studio.', lvl: 'B2'),
  (term: 'commence', tr: 'başlamak', syn: 'begin', sent: 'The opening ceremony will commence at noon.', lvl: 'C1'),
  (term: 'compelling', tr: 'ikna edici / sürükleyici', syn: 'persuasive', sent: 'The documentary offered a compelling argument.', lvl: 'C1'),
  (term: 'comprehend', tr: 'kavramak / anlamak', syn: 'understand', sent: 'Listening twice helps you comprehend fast speech.', lvl: 'B2'),
  (term: 'concise', tr: 'özlü / kısa ve net', syn: 'succinct', sent: 'Please write a concise summary of the chapter.', lvl: 'C1'),
  (term: 'confirm', tr: 'onaylamak / doğrulamak', syn: 'verify', sent: 'Please confirm your departure time by email.', lvl: 'B1'),
  (term: 'consequence', tr: 'sonuç / etki', syn: 'outcome', sent: 'Skipping warm-ups can have an unpleasant consequence.', lvl: 'B2'),
  (term: 'considerable', tr: 'önemli ölçüde / kayda değer', syn: 'substantial', sent: 'Solar panels saved a considerable amount of energy.', lvl: 'B2'),
  (term: 'consistent', tr: 'tutarlı / istikrarlı', syn: 'steady', sent: 'Consistent practice beats last-minute cramming.', lvl: 'B2'),
  (term: 'crucial', tr: 'çok önemli / kritik', syn: 'vital', sent: 'Clean water is crucial for every ecosystem.', lvl: 'B2'),
  (term: 'curious', tr: 'meraklı', syn: 'inquisitive', sent: 'Curious learners ask thoughtful questions.', lvl: 'A2'),
  (term: 'decline', tr: 'reddetmek / azalmak', syn: 'decrease', sent: 'Plastic waste began to decline after the policy.', lvl: 'B2'),
  (term: 'dedicate', tr: 'adamak / ayırmak', syn: 'devote', sent: 'Dedicate fifteen minutes daily to English audio.', lvl: 'B2'),
  (term: 'deliberate', tr: 'kasıtlı / bilinçli', syn: 'intentional', sent: 'Every brushstroke in the painting was deliberate.', lvl: 'C1'),
  (term: 'demonstrate', tr: 'göstermek / kanıtlamak', syn: 'illustrate', sent: 'The lab experiment will demonstrate Ohm’s law.', lvl: 'B2'),
  (term: 'depart', tr: 'ayrılmak / yola çıkmak', syn: 'leave', sent: 'Our evening train will depart from Platform Four.', lvl: 'B1'),
  (term: 'deprive', tr: 'mahrum bırakmak', syn: 'strip', sent: 'Long screen hours can deprive you of deep rest.', lvl: 'C1'),
  (term: 'derive', tr: 'türetmek / elde etmek', syn: 'obtain', sent: 'Many scientific words derive from ancient Greek.', lvl: 'C1'),
  (term: 'deteriorate', tr: 'kötüleşmek / bozulmak', syn: 'worsen', sent: 'Weather conditions may deteriorate after sunset.', lvl: 'C1'),
  (term: 'diligent', tr: 'çalışkan / özenli', syn: 'hardworking', sent: 'A diligent student checks every calculation twice.', lvl: 'C1'),
  (term: 'diminish', tr: 'azalmak / küçülmek', syn: 'lessen', sent: 'Fog will gradually diminish as the sun rises.', lvl: 'C1'),
  (term: 'distinct', tr: 'belirgin / farklı', syn: 'separate', sent: 'Each accent has its own distinct rhythm.', lvl: 'B2'),
  (term: 'diverse', tr: 'çeşitli / farklı türden', syn: 'varied', sent: 'Istanbul is famous for its diverse culinary traditions.', lvl: 'B2'),
  (term: 'durable', tr: 'dayanıklı / uzun ömürlü', syn: 'sturdy', sent: 'Choose a durable backpack for mountain hikes.', lvl: 'B2'),
  (term: 'eager', tr: 'istekli / hevesli', syn: 'keen', sent: 'The team is eager to test the new prototype.', lvl: 'B1'),
  (term: 'efficient', tr: 'verimli / etkin', syn: 'productive', sent: 'Electric trains are fast and energy efficient.', lvl: 'B2'),
  (term: 'elaborate', tr: 'ayrıntılandırmak / detaylı', syn: 'detailed', sent: 'Could you elaborate on your final design choice?', lvl: 'C1'),
  (term: 'eliminate', tr: 'ortadan kaldırmak / elemek', syn: 'remove', sent: 'Automated checks help eliminate simple mistakes.', lvl: 'B2'),
  (term: 'eloquent', tr: 'akıcı ve etkileyici konuşan', syn: 'articulate', sent: 'She delivered an eloquent speech on climate science.', lvl: 'C1'),
  (term: 'emerge', tr: 'ortaya çıkmak', syn: 'appear', sent: 'New patterns emerge when you plot the data.', lvl: 'B2'),
  (term: 'emphasize', tr: 'vurgulamak', syn: 'highlight', sent: 'Teachers emphasize clear pronunciation from day one.', lvl: 'B2'),
  (term: 'enable', tr: 'olanak sağlamak', syn: 'allow', sent: 'Offline packs enable studying on an airplane.', lvl: 'B2'),
  (term: 'encounter', tr: 'karşılaşmak / rastlamak', syn: 'face', sent: 'Travelers often encounter unexpected kindness.', lvl: 'B2'),
  (term: 'endure', tr: 'dayanmak / katlanmak', syn: 'withstand', sent: 'Stone bridges can endure centuries of floods.', lvl: 'B2'),
  (term: 'enhance', tr: 'geliştirmek / artırmak', syn: 'improve', sent: 'Vector graphics enhance visual clarity on every screen.', lvl: 'B2'),
  (term: 'enormous', tr: 'devasa / muazzam', syn: 'huge', sent: 'The observatory dome has an enormous mirror.', lvl: 'B1'),
  (term: 'ensure', tr: 'garantiye almak / sağlamak', syn: 'guarantee', sent: 'Double-check your ticket to ensure smooth boarding.', lvl: 'B2'),
  (term: 'enthusiastic', tr: 'coşkulu / heyecanlı', syn: 'passionate', sent: 'The audience gave an enthusiastic applause.', lvl: 'B2'),
  (term: 'essential', tr: 'temel / vazgeçilmez', syn: 'necessary', sent: 'A compass is essential when hiking off-trail.', lvl: 'B1'),
  (term: 'estimate', tr: 'tahmin etmek', syn: 'approximate', sent: 'Can you estimate the height of Mount Ararat?', lvl: 'B2'),
  (term: 'evident', tr: 'açıkça ortada', syn: 'clear', sent: 'From the Venn diagram, the overlap is evident.', lvl: 'B2'),
  (term: 'exceed', tr: 'aşmak / geçmek', syn: 'surpass', sent: 'Wind output may exceed last winter’s record.', lvl: 'B2'),
  (term: 'exhibit', tr: 'sergilemek', syn: 'display', sent: 'The gallery will exhibit rare Anatolian textiles.', lvl: 'B2'),
  (term: 'expand', tr: 'genişletmek / büyümek', syn: 'enlarge', sent: 'Reading novels helps expand your vocabulary.', lvl: 'B1'),
  (term: 'explicit', tr: 'açık seçik / net', syn: 'direct', sent: 'The manual provides explicit safety steps.', lvl: 'C1'),
  (term: 'feasible', tr: 'uygulanabilir / mümkün', syn: 'achievable', sent: 'Building a bike lane along the coast is feasible.', lvl: 'C1'),
  (term: 'flexible', tr: 'esnek', syn: 'adaptable', sent: 'Remote learning allows a flexible daily schedule.', lvl: 'B1'),
  (term: 'flourish', tr: 'gelişmek / serpilmek', syn: 'thrive', sent: 'Olive trees flourish in the sunny Aegean climate.', lvl: 'C1'),
  (term: 'fluctuate', tr: 'dalgalanmak / inip çıkmak', syn: 'vary', sent: 'Mountain temperatures fluctuate wildly after dark.', lvl: 'C1'),
  (term: 'fragile', tr: 'kırılgan / hassas', syn: 'delicate', sent: 'Pack the glass telescope lens carefully; it is fragile.', lvl: 'B2'),
  (term: 'frequent', tr: 'sık / tekrarlanan', syn: 'regular', sent: 'Frequent short reviews strengthen long-term memory.', lvl: 'B1'),
  (term: 'fundamental', tr: 'temel / esas', syn: 'basic', sent: 'Logic gates are fundamental to digital computers.', lvl: 'B2'),
  (term: 'generous', tr: 'cömert', syn: 'giving', sent: 'Our hosts offered a generous Anatolian breakfast.', lvl: 'B1'),
  (term: 'gradual', tr: 'kademeli / yavaş yavaş', syn: 'progressive', sent: 'Notice the gradual shift in color across the spectrum.', lvl: 'B2'),
  (term: 'hesitate', tr: 'tereddüt etmek', syn: 'pause', sent: 'Never hesitate to replay the slow audio clip.', lvl: 'B2'),
  (term: 'hostile', tr: 'düşmanca / elverişsiz', syn: 'unfriendly', sent: 'Mars has a thin and hostile atmosphere.', lvl: 'C1'),
  (term: 'identify', tr: 'tanımlamak / belirlemek', syn: 'recognize', sent: 'Can you identify the chord played on the piano?', lvl: 'B1'),
  (term: 'immense', tr: 'engin / çok büyük', syn: 'vast', sent: 'The Pacific Ocean covers an immense area.', lvl: 'B2'),
  (term: 'implement', tr: 'uygulamaya koymak', syn: 'execute', sent: 'The city will implement new recycling stations.', lvl: 'B2'),
  (term: 'imply', tr: 'ima etmek', syn: 'suggest', sent: 'What does the speaker’s tone imply?', lvl: 'B2'),
  (term: 'inevitable', tr: 'kaçınılmaz', syn: 'unavoidable', sent: 'Small mistakes are inevitable when learning a skill.', lvl: 'C1'),
  (term: 'ingenious', tr: 'dahice / ustaca', syn: 'inventive', sent: 'Archimedes designed an ingenious water screw.', lvl: 'C1'),
  (term: 'initial', tr: 'ilk / başlangıçtaki', syn: 'first', sent: 'Our initial estimate was remarkably close.', lvl: 'B2'),
  (term: 'innovative', tr: 'yenilikçi', syn: 'creative', sent: 'Students built an innovative solar glider.', lvl: 'B2'),
  (term: 'inspect', tr: 'incelemek / denetlemek', syn: 'examine', sent: 'Technicians inspect the turbine blades every spring.', lvl: 'B2'),
  (term: 'integrate', tr: 'birleştirmek / bütünleştirmek', syn: 'combine', sent: 'Modern apps integrate audio and vector diagrams.', lvl: 'B2'),
  (term: 'intricate', tr: 'karmaşık / ince işlenmiş', syn: 'complex', sent: 'Watchmakers assemble intricate mechanical gears.', lvl: 'C1'),
  (term: 'justify', tr: 'gerekçelendirmek / haklı göstermek', syn: 'defend', sent: 'Use data from the chart to justify your answer.', lvl: 'B2'),
  (term: 'keen', tr: 'keskin / çok istekli', syn: 'enthusiastic', sent: 'She has a keen ear for musical intervals.', lvl: 'B2'),
  (term: 'lucid', tr: 'berrak / açık anlaşılır', syn: 'clear', sent: 'The professor gave a lucid explanation of orbits.', lvl: 'C1'),
  (term: 'magnificent', tr: 'görkemli / muhteşem', syn: 'splendid', sent: 'The Bosphorus sunset looked magnificent from the ferry.', lvl: 'B2'),
  (term: 'maintain', tr: 'sürdürmek / bakım yapmak', syn: 'preserve', sent: 'Regular exercise helps maintain high energy.', lvl: 'B2'),
  (term: 'mandatory', tr: 'zorunlu', syn: 'compulsory', sent: 'Safety goggles are mandatory in the chemistry lab.', lvl: 'C1'),
  (term: 'meticulous', tr: 'titiz / çok özenli', syn: 'thorough', sent: 'A meticulous scientist logs every measurement.', lvl: 'C1'),
  (term: 'modify', tr: 'değiştirmek / uyarlamak', syn: 'alter', sent: 'We can modify the resistor value to adjust current.', lvl: 'B2'),
  (term: 'neglect', tr: 'ihmal etmek', syn: 'ignore', sent: 'Do not neglect listening practice while studying grammar.', lvl: 'B2'),
  (term: 'notable', tr: 'dikkate değer / kayda değer', syn: 'remarkable', sent: 'There was a notable increase in solar output.', lvl: 'B2'),
  (term: 'obstacle', tr: 'engel', syn: 'barrier', sent: 'Turn every difficult question into a stepping stone, not an obstacle.', lvl: 'B2'),
  (term: 'obtain', tr: 'elde etmek / sağlamak', syn: 'acquire', sent: 'You can obtain free maps at the tourist desk.', lvl: 'B2'),
  (term: 'break the ice', tr: 'soğukluğu kırmak / ortamı ısıtmak', syn: 'start friendly conversation', sent: 'A fun trivia round always helps break the ice.', lvl: 'B2'),
  (term: 'call off', tr: 'iptal etmek', syn: 'cancel', sent: 'They had to call off the match due to heavy rain.', lvl: 'B1'),
  (term: 'carry out', tr: 'yürütmek / gerçekleştirmek', syn: 'conduct', sent: 'The researchers will carry out a coastal survey.', lvl: 'B2'),
  (term: 'come across', tr: 'tesadüfen rastlamak', syn: 'find by chance', sent: 'I came across a rare map in the old bookstore.', lvl: 'B1'),
  (term: 'cut down on', tr: 'azaltmak / kısmak', syn: 'reduce', sent: 'Many households cut down on single-use plastics.', lvl: 'B2'),
  (term: 'figure out', tr: 'çözmek / anlamak', syn: 'solve', sent: 'Take a moment to figure out the matrix pattern.', lvl: 'B1'),
  (term: 'get over', tr: 'atlatmak / üstesinden gelmek', syn: 'recover from', sent: 'It took him a week to get over the winter flu.', lvl: 'B2'),
  (term: 'give up', tr: 'vazgeçmek / pes etmek', syn: 'quit', sent: 'Never give up when a puzzle looks tricky at first.', lvl: 'A2'),
  (term: 'look forward to', tr: 'dört gözle beklemek', syn: 'eagerly await', sent: 'We look forward to visiting Cappadocia in April.', lvl: 'B1'),
  (term: 'look into', tr: 'araştırmak / incelemek', syn: 'investigate', sent: 'The support team will look into the login issue.', lvl: 'B2'),
  (term: 'make up your mind', tr: 'karar vermek', syn: 'decide', sent: 'Take your time and make up your mind carefully.', lvl: 'B1'),
  (term: 'once in a blue moon', tr: 'kırk yılda bir / çok nadir', syn: 'very rarely', sent: 'Heavy snow falls on this island once in a blue moon.', lvl: 'B2'),
  (term: 'piece of cake', tr: 'çocuk oyuncağı / çok kolay', syn: 'very easy', sent: 'After practicing intervals, this chord is a piece of cake.', lvl: 'B1'),
  (term: 'put off', tr: 'ertelemek', syn: 'postpone', sent: 'Let us not put off the rehearsal until tomorrow.', lvl: 'B2'),
  (term: 'run out of', tr: 'tüketmek / bitmek', syn: 'exhaust supply of', sent: 'Check the battery so we do not run out of power.', lvl: 'B1'),
  (term: 'set up', tr: 'kurmak / hazırlamak', syn: 'establish', sent: 'We set up the telescope on the quiet hill.', lvl: 'B1'),
  (term: 'take off', tr: 'havalanmak / çıkarmak', syn: 'depart by air', sent: 'The flight to Rome is scheduled to take off at eight.', lvl: 'A2'),
  (term: 'turn down', tr: 'reddetmek / sesini kısmak', syn: 'reject', sent: 'She politely turned down the inconvenient offer.', lvl: 'B2'),
  (term: 'under the weather', tr: 'keyifsiz / hafif hasta hissetmek', syn: 'feeling unwell', sent: 'Liam stayed home today because he felt under the weather.', lvl: 'B2'),
  (term: 'work out', tr: 'egzersiz yapmak / çözüme kavuşmak', syn: 'exercise or resolve', sent: 'Everything will work out smoothly with good planning.', lvl: 'B1'),
  (term: 'resilient', tr: 'dirençli / çabuk toparlanan', syn: 'tough', sent: 'Coastal pines are remarkably resilient against salt winds.', lvl: 'C1'),
  (term: 'scarce', tr: 'kıt / nadir bulunan', syn: 'rare', sent: 'Freshwater springs are scarce in arid deserts.', lvl: 'B2'),
  (term: 'subtle', tr: 'ince / zor fark edilen', syn: 'delicate', sent: 'Listen closely for the subtle vowel difference.', lvl: 'C1'),
  (term: 'transparent', tr: 'şeffaf / saydam', syn: 'see-through', sent: 'Clear quartz crystals are almost completely transparent.', lvl: 'B2'),
  (term: 'versatile', tr: 'çok yönlü', syn: 'adaptable', sent: 'A smartphone is a remarkably versatile learning tool.', lvl: 'C1'),
];

final _vocabTrPool = _vocab125.map((v) => v.tr).toSet().toList();
final _vocabSynPool = _vocab125.map((v) => v.syn).toSet().toList();

AdvancedItem _buildVocab100k(int i) {
  final v = _vocab125[i % _vocab125.length];
  final round = i ~/ _vocab125.length; // 0..39
  final lang = _accentAt(i + round);
  final askSyn = round.isOdd;
  final intro = switch (round % 4) {
    0 => 'Listen carefully: ${v.sent}',
    1 => 'Target expression: ${v.term}. Example: ${v.sent}',
    2 => 'In context: ${v.sent} Focus on the word "${v.term}".',
    _ => '${v.sent} Repeat after me: ${v.term}.',
  };
  if (askSyn) {
    return AdvancedItem(
      'İngilizce kaydı dinleyin (${v.lvl}). Cümlede geçen "${v.term}" ifadesinin en yakın İNGİLİZCE eş anlamlısı hangisidir?',
      v.syn,
      _pickDistinct(_vocabSynPool, v.syn, i + 7),
      '"${v.term}" (${v.tr}) ifadesinin en yakın eş anlamlısı "${v.syn}" şeklindedir.',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'İngilizce Eş Anlam (${v.lvl})',
        language: lang,
        transcript: intro,
      ),
    );
  }
  return AdvancedItem(
    'İngilizce ses kaydını dinleyin (${v.lvl}). Cümlede vurgulanan "${v.term}" ifadesinin Türkçe karşılığı hangisidir?',
    v.tr,
    _pickDistinct(_vocabTrPool, v.tr, i + 5),
    '"${v.term}" → "${v.tr}" (eş anlamlısı: ${v.syn}). Örnek: ${v.sent}',
    activity: QuestionActivity(
      kind: ActivityKind.listening,
      title: 'Sesli Kelime & Deyim (${v.lvl})',
      language: lang,
      transcript: intro,
    ),
  );
}

// ===========================================================================
// 3. IELTS SAYI, İNDİRİM, SAAT, TARİH & ÖLÇÜM DİNLEME (4.000 soru)
// ===========================================================================
const _teenTy = [
  (13, 'thirteen', 30, 'thirty'),
  (14, 'fourteen', 40, 'forty'),
  (15, 'fifteen', 50, 'fifty'),
  (16, 'sixteen', 60, 'sixty'),
  (17, 'seventeen', 70, 'seventy'),
  (18, 'eighteen', 80, 'eighty'),
  (19, 'nineteen', 90, 'ninety'),
];

AdvancedItem _buildIeltsNum100k(int i) {
  final kind = i % 5; // 5 × 800 = 4.000
  final k = i ~/ 5;
  final lang = _accentAt(i);
  final city = _enCities[k % _enCities.length];

  if (kind == 0) {
    // Price + exact percentage discount
    const basePrices = [40, 60, 80, 100, 120, 140, 160, 180, 200, 240];
    const discounts = [10, 20, 25, 50];
    final price = basePrices[k % basePrices.length];
    final disc = discounts[(k ~/ basePrices.length) % discounts.length];
    final finalPrice = price - (price * disc) ~/ 100;
    final transcript =
        'Standard museum admission in ${city.$1} is $price dollars, while students receive a $disc percent discount at the counter.';
    return AdvancedItem(
      'IELTS fiyat anonsunu dinleyin. %$disc öğrenci indirimi uygulandığında bilet fiyatı kaç dolar olur?',
      '\$$finalPrice',
      _intWrong(finalPrice, i, prefix: '\$', minVal: 5, deltas: const [5, -5, 10, -10, 15, 20]),
      'Normal fiyat \$$price; %$disc indirimle \$$price − \$${(price * disc) ~/ 100} = \$$finalPrice olur.',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'IELTS Fiyat & İndirim',
        language: lang,
        transcript: transcript,
      ),
    );
  } else if (kind == 1) {
    // -teen vs -ty audio discrimination
    final p = _teenTy[k % _teenTy.length];
    final useTeen = (k ~/ 7).isEven;
    final val = useTeen ? p.$1 : p.$3;
    final word = useTeen ? p.$2 : p.$4;
    final trap = useTeen ? p.$3 : p.$1;
    final busNo = 100 + (k % 89);
    final transcript =
        'Shuttle bus number $busNo for ${city.$1} station leaves every $word minutes from Bay Four.';
    return AdvancedItem(
      'Anonsu dikkatle dinleyin (-teen / -ty ayrımı). Servis otobüsü kaç dakikada bir kalkmaktadır?',
      '$val dakika',
      ['$trap dakika', '${val + 5} dakika', '${val > 5 ? val - 5 : val + 10} dakika'],
      '"every $word minutes" ifadesi $val dakika anlamına gelir.',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'IELTS Sayı Ayrımı (-teen / -ty)',
        language: lang,
        transcript: transcript,
      ),
    );
  } else if (kind == 2) {
    // Start time + duration => end time
    final sh = 8 + (k % 10);
    final sm = (k % 4) * 15;
    const durs = [30, 45, 60, 75, 90, 105, 120];
    final dur = durs[(k ~/ 4) % durs.length];
    final endTotal = sh * 60 + sm + dur;
    final eh = endTotal ~/ 60;
    final em = endTotal % 60;
    final startStr = '${sh.toString().padLeft(2, '0')}:${sm.toString().padLeft(2, '0')}';
    final endStr = '${eh.toString().padLeft(2, '0')}:${em.toString().padLeft(2, '0')}';
    final transcript =
        'The science workshop in ${city.$1} starts promptly at $startStr and runs for $dur minutes without a break.';
    final wrong = <String>[];
    for (final shift in const [15, -15, 30, -30, 45, 60]) {
      final t = endTotal + shift;
      final cand = '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
      if (cand != endStr && !wrong.contains(cand)) wrong.add(cand);
      if (wrong.length == 3) break;
    }
    return AdvancedItem(
      'Etkinlik anonsunu dinleyin. $startStr saatinde başlayıp $dur dakika süren atölye kaçta biter?',
      endStr,
      wrong,
      'Başlangıç $startStr + $dur dakika = $endStr bitiş saati.',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'IELTS Saat & Süre Hesabı',
        language: lang,
        transcript: transcript,
      ),
    );
  } else if (kind == 3) {
    // Booking reference & date
    final m = _enMonths[k % 12];
    final d = _enDays[k % 7];
    final dayNum = 3 + (k % 25);
    final transcript =
        'Your guided boat cruise in ${city.$1} is confirmed for ${d.$1}, ${m.$1} $dayNum. Please arrive twenty minutes early.';
    final correct = '$dayNum ${m.$2} ${d.$2}';
    return AdvancedItem(
      'Rezervasyon kaydını dinleyin. Tekne turu hangi tarih ve günde onaylanmıştır?',
      correct,
      [
        '$dayNum ${_enMonths[(k + 2) % 12].$2} ${d.$2}',
        '${dayNum + 2} ${m.$2} ${d.$2}',
        '$dayNum ${m.$2} ${_enDays[(k + 2) % 7].$2}',
      ],
      'Kayıtta "${d.$1}, ${m.$1} $dayNum" ($correct) tarihi verilmektedir.',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'IELTS Tarih & Gün Kaydı',
        language: lang,
        transcript: transcript,
      ),
    );
  } else {
    // Temperature / distance / speed measurement
    final temp = 6 + (k % 28);
    final wind = 10 + ((k * 3) % 35);
    final askWind = k.isOdd;
    final transcript =
        'Maritime report for ${city.$1}: afternoon air temperature is $temp degrees Celsius with a steady breeze of $wind kilometers per hour.';
    if (askWind) {
      return AdvancedItem(
        'Denizcilik hava raporunu dinleyin. Bildirilen rüzgâr hızı saatte kaç kilometredir?',
        '$wind km/sa',
        _intWrong(wind, i, suffix: ' km/sa', minVal: 2, deltas: const [3, -3, 5, -5, 10, -10]),
        'Raporda "breeze of $wind kilometers per hour" ($wind km/sa) bilgisi geçmektedir.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'IELTS Ölçüm & Rüzgâr Raporu',
          language: lang,
          transcript: transcript,
        ),
      );
    }
    return AdvancedItem(
      'Hava raporunu dinleyin. Öğleden sonra hava sıcaklığı kaç santigrat derecedir?',
      '$temp °C',
      _intWrong(temp, i, suffix: ' °C', minVal: 0, deltas: const [2, -2, 4, -4, 6, -6]),
      'Rapor "$temp degrees Celsius" ($temp °C) değerini vermektedir.',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'IELTS Sıcaklık Raporu',
        language: lang,
        transcript: transcript,
      ),
    );
  }
}

// ===========================================================================
// 4. SESLİ İNGİLİZCE DİKTE STÜDYOSU (125 Kelime × 40 = 5.000 soru)
// ===========================================================================
typedef _DictSpec = (String word, String tr, String before, String after);

const _dict125 = <_DictSpec>[
  ('adventure', 'macera', 'Every trip to the mountains feels like an', 'for our team.'),
  ('afternoon', 'öğleden sonra', 'The photography workshop begins this', 'at three.'),
  ('agreement', 'anlaşma', 'Both partners signed the final', 'yesterday morning.'),
  ('algorithm', 'algoritma', 'The sorting', 'processes thousands of items in milliseconds.'),
  ('altitude', 'rakım / yükseklik', 'The aircraft cruised smoothly at high', 'above the clouds.'),
  ('architect', 'mimar', 'The young', 'designed a sunlit timber library.'),
  ('astronomy', 'astronomi / gök bilimi', 'She joined the campus', 'club to observe Saturn.'),
  ('atmosphere', 'atmosfer', 'Earth’s', 'protects life from harmful radiation.'),
  ('attention', 'dikkat', 'Please pay close', 'to the pronunciation of each vowel.'),
  ('audience', 'seyirci / dinleyici', 'The', 'clapped warmly after the violin solo.'),
  ('available', 'müsait / mevcut', 'Quiet study rooms are', 'on the second floor.'),
  ('backpack', 'sırt çantası', 'He packed a compass and water bottle in his', 'before hiking.'),
  ('balanced', 'dengeli', 'A', 'diet supports energy throughout the day.'),
  ('balcony', 'balkon', 'We watched the ferry lights from the', 'at dusk.'),
  ('battery', 'pil / batarya', 'Remember to charge the', 'before the long flight.'),
  ('behavior', 'davranış', 'Biologists studied dolphin', 'along the bay.'),
  ('boundary', 'sınır', 'The river marks the natural', 'between the two valleys.'),
  ('building', 'bina / yapı', 'That historic stone', 'now houses a maritime museum.'),
  ('business', 'iş / ticaret', 'She started a small eco-friendly', 'last spring.'),
  ('capacity', 'kapasite', 'The concert hall reached full', 'within ten minutes.'),
  ('category', 'kategori', 'Choose your favorite', 'before starting the round.'),
  ('celebrate', 'kutlamak', 'Friends gathered to', 'the graduation ceremony.'),
  ('challenge', 'meydan okuma', 'Solving logic circuits is an exciting', 'for learners.'),
  ('character', 'karakter', 'The novel’s main', 'travels across three continents.'),
  ('chemistry', 'kimya', 'We built Bohr models in', 'class today.'),
  ('chocolate', 'çikolata', 'Warm', 'tastes wonderful after a winter walk.'),
  ('classroom', 'sınıf', 'Every', 'now has an interactive vector screen.'),
  ('climate', 'iklim', 'Mediterranean', 'summers are warm and sunny.'),
  ('coastline', 'kıyı şeridi', 'The Aegean', 'is famous for turquoise bays.'),
  ('collection', 'koleksiyon', 'The gallery opened a new', 'of modern ceramics.'),
  ('comfortable', 'rahat / konforlu', 'Wear', 'shoes for the walking tour.'),
  ('community', 'topluluk', 'Our local', 'planted two hundred saplings.'),
  ('companion', 'yol arkadaşı', 'A good book is a loyal', 'on train journeys.'),
  ('compare', 'karşılaştırmak', 'Use the pie chart to', 'energy sources.'),
  ('complete', 'tamamlamak', 'Please', 'all four matches before submitting.'),
  ('computer', 'bilgisayar', 'Every modern', 'relies on binary logic gates.'),
  ('condition', 'koşul / durum', 'The vintage violin remained in excellent', 'for a century.'),
  ('confident', 'özgüvenli', 'Daily audio drills make you a more', 'speaker.'),
  ('connect', 'bağlamak', 'Two bridges', 'the eastern and western shores.'),
  ('consider', 'düşünmek / göz önüne almak', 'Always', 'both speed and accuracy during tests.'),
  ('continent', 'kıta', 'Antarctica is the coldest', 'on Earth.'),
  ('contrast', 'karşıtlık / kontrast', 'High', 'colors make charts much easier to read.'),
  ('creative', 'yaratıcı', 'The students proposed a', 'way to save rainwater.'),
  ('crossing', 'geçit / geçiş', 'Wait for the green light at the pedestrian', 'ahead.'),
  ('cultural', 'kültürel', 'Istanbul hosts dozens of international', 'festivals.'),
  ('customer', 'müşteri', 'Every', 'receives a digital receipt by email.'),
  ('database', 'veri tabanı', 'The research', 'stores climate readings since 1950.'),
  ('decision', 'karar', 'Taking notes helped him make a wise', 'quickly.'),
  ('delivery', 'teslimat', 'Your book', 'will arrive tomorrow afternoon.'),
  ('describe', 'betimlemek / tanımlamak', 'Can you', 'the pattern in the third row?'),
  ('destination', 'varış noktası', 'Our final', 'is the ancient theater of Ephesus.'),
  ('developer', 'geliştirici', 'The mobile', 'optimized the app for offline speed.'),
  ('diagram', 'diyagram / şema', 'Examine the Venn', 'to find the intersection.'),
  ('dialogue', 'diyalog', 'Replay the English', 'at slower speed if needed.'),
  ('different', 'farklı', 'British and American speakers use slightly', 'accents.'),
  ('direction', 'yön', 'Check the compass needle to verify your', 'eastward.'),
  ('discover', 'keşfetmek', 'Curiosity helps scientists', 'hidden laws of nature.'),
  ('distance', 'mesafe / uzaklık', 'Calculate the', 'between points A and B.'),
  ('document', 'belge', 'Keep your travel', 'safe inside your front pocket.'),
  ('economy', 'ekonomi', 'Tourism plays a major role in the coastal', 'every summer.'),
  ('education', 'eğitim', 'Interactive games transform modern', 'for all ages.'),
  ('electric', 'elektrikli', 'Silent', 'ferries now cross the narrow bay.'),
  ('element', 'element', 'Carbon is the key', 'in organic chemistry.'),
  ('elevator', 'asansör', 'Take the', 'to the rooftop observatory.'),
  ('emergency', 'acil durum', 'Know the nearest', 'exit in every public hall.'),
  ('emission', 'emisyon / salım', 'Solar roofs help cut carbon', 'across cities.'),
  ('emphasis', 'vurgu', 'Notice the clear', 'on the second syllable.'),
  ('engineer', 'mühendis', 'The electrical', 'tested the parallel resistor circuit.'),
  ('enormous', 'devasa', 'Whales migrate across', 'stretches of open ocean.'),
  ('entrance', 'giriş', 'Meet your guide near the main museum', 'at ten.'),
  ('envelope', 'zarf', 'Place the signed letter inside the white', 'carefully.'),
  ('equation', 'denklem', 'Balance the chemical', 'before counting moles.'),
  ('equipment', 'ekipman / donanım', 'Check all diving', 'prior to leaving the pier.'),
  ('estimate', 'tahmin', 'Slide the marker to lock in your best', 'today.'),
  ('evening', 'akşam', 'A gentle breeze cooled the', 'air along the pier.'),
  ('evidence', 'kanıt', 'Fossils provide strong', 'of ancient marine life.'),
  ('exchange', 'değişim / takas', 'Currency', 'rates are displayed above the desk.'),
  ('exercise', 'egzersiz / alıştırma', 'Each listening', 'includes three spoken accents.'),
  ('exhibition', 'sergi', 'The space photography', 'runs until late October.'),
  ('explorer', 'kâşif', 'The Arctic', 'mapped the frozen archipelago.'),
  ('festival', 'festival', 'Jazz musicians performed at the summer', 'by the lake.'),
  ('forecast', 'hava tahmini', 'According to the', 'skies will clear by noon.'),
  ('fraction', 'kesir', 'Simplify the probability', 'to its lowest terms.'),
  ('frequency', 'frekans', 'Blue light has a higher', 'than red light.'),
  ('friendly', 'arkadaş canlısı', 'The barista gave us a', 'welcome in Dublin.'),
  ('function', 'fonksiyon / işlev', 'Plot the linear', 'on the coordinate grid.'),
  ('gallery', 'galeri', 'Watercolor landscapes filled the bright', 'hall.'),
  ('garden', 'bahçe', 'Fragrant rosemary grows along the stone', 'path.'),
  ('geography', 'coğrafya', 'Flag quizzes sharpen your world', 'skills quickly.'),
  ('glacier', 'buzul', 'Warming oceans affect every polar', 'worldwide.'),
  ('grammar', 'dil bilgisi', 'Word order puzzles build natural English', 'habits.'),
  ('gratitude', 'minnettarlık', 'She expressed heartfelt', 'to her mentors.'),
  ('harmony', 'uyum / armoni', 'Three notes played together create rich', 'on piano.'),
  ('headline', 'manşet / başlık', 'The morning', 'announced a breakthrough in battery tech.'),
  ('healthy', 'sağlıklı', 'Fresh fruit and oats make a', 'breakfast.'),
  ('heritage', 'miras', 'Stone aqueducts are part of our shared', 'history.'),
  ('horizon', 'ufuk', 'Golden light shimmered along the eastern', 'at dawn.'),
  ('identity', 'kimlik', 'Match each flag to its country’s', 'and capital.'),
  ('imagine', 'hayal etmek', 'Close your eyes and', 'sailing across the Aegean.'),
  ('improve', 'iyileştirmek / geliştirmek', 'Short daily drills steadily', 'listening fluency.'),
  ('include', 'içermek', 'Does the hotel rate', 'early breakfast?'),
  ('increase', 'artmak / artırmak', 'Adding resistors in series will', 'total resistance.'),
  ('industry', 'sanayi / sektör', 'Clean energy is a rapidly growing', 'worldwide.'),
  ('insight', 'içgörü / anlayış', 'Charts give instant', 'into complex numbers.'),
  ('inspire', 'ilham vermek', 'Great teachers', 'lifelong curiosity in students.'),
  ('instrument', 'enstrüman / alet', 'The piano is a versatile musical', 'for theory.'),
  ('interest', 'ilgi', 'Her', 'in astronomy began with a lunar eclipse.'),
  ('interval', 'aralık', 'Count the semitones to name the musical', 'accurately.'),
  ('island', 'ada', 'Ferries reach the quiet', 'in forty minutes.'),
  ('journal', 'günlük / dergi', 'He keeps a travel', 'full of hand-drawn maps.'),
  ('journey', 'yolculuk', 'The overnight rail', 'crossed three alpine valleys.'),
  ('keyboard', 'klavye', 'Highlight the major chord on the piano', 'above.'),
  ('landmark', 'simge yapı', 'The Maiden’s Tower is an iconic', 'of Istanbul.'),
  ('landscape', 'manzara', 'Volcanic valleys shape the surreal', 'of Cappadocia.'),
  ('lecture', 'ders / konferans', 'The physics', 'explored light wavelengths and optics.'),
  ('location', 'konum', 'Use bearing and angle to plot the exact', 'now.'),
  ('machine', 'makine', 'Every digital', 'turns voltage pulses into bits.'),
  ('magnet', 'mıknatıs', 'A compass needle behaves like a tiny', 'aligned north.'),
  ('measure', 'ölçmek', 'Use the slider to', 'your numerical intuition.'),
  ('melody', 'melodi / ezgi', 'Can you read this short', 'in treble clef?'),
  ('memory', 'hafıza / bellek', 'Spaced repetition boosts active', 'retention.'),
  ('message', 'mesaj', 'Listen to the voice', 'and note the meeting day.'),
  ('mineral', 'mineral', 'Quartz is one of the most abundant', 'crystals on Earth.'),
  ('mission', 'görev', 'The lunar', 'collected priceless rock samples.'),
  ('monitor', 'izlemek / ekran', 'Sensors continuously', 'air quality in the park.'),
];

const _dictLeadIns = [
  'Listen carefully:',
  'Sentence audio:',
  'Dictation check:',
  'Fill in the missing word:',
];

AdvancedItem _buildDictation100k(int i) {
  final d = _dict125[i % _dict125.length];
  final round = i ~/ _dict125.length; // 0..39
  final lang = _accentAt(i + round);
  final fullSentence = '${d.$3} ${d.$1} ${d.$4}';
  final lead = _dictLeadIns[round % _dictLeadIns.length];
  final hint = '${d.$1[0].toUpperCase()}${'_' * (d.$1.length - 1)} (${d.$1.length} harf · ${d.$2})';
  return AdvancedItem(
    '$lead Ses kaydını dinleyip boşluğa gelen İngilizce kelimeyi yazın:\n"${d.$3} _____ ${d.$4}"\nİpucu: $hint',
    d.$1,
    _pickDistinct([for (final x in _dict125) x.$1], d.$1, i + 11),
    'Tam cümle: "$fullSentence" — Eksik kelime "${d.$1}" (${d.$2}).',
    activity: QuestionActivity(
      kind: ActivityKind.dictation,
      title: 'Sesli İngilizce Dikte',
      language: lang,
      transcript: fullSentence,
    ),
  );
}

// ===========================================================================
// 5. SESLİ İNGİLİZCE TELAFFUZ, VURGU & FONETİK (4.000 soru)
// ===========================================================================
const _silentLetters = <(String word, String silent, String ipa, String tr)>[
  ('knight', 'k', '/naɪt/', 'şövalye'),
  ('island', 's', '/ˈaɪ.lənd/', 'ada'),
  ('receipt', 'p', '/rɪˈsiːt/', 'fiş / makbuz'),
  ('debt', 'b', '/det/', 'borç'),
  ('subtle', 'b', '/ˈsʌt.əl/', 'ince / zarif'),
  ('psychology', 'p', '/saɪˈkɒl.ə.dʒi/', 'psikoloji'),
  ('castle', 't', '/ˈkɑː.səl/', 'kale / şato'),
  ('plumber', 'b', '/ˈplʌm.ər/', 'tesisatçı'),
  ('listen', 't', '/ˈlɪs.ən/', 'dinlemek'),
  ('autumn', 'n', '/ˈɔː.təm/', 'sonbahar'),
  ('column', 'n', '/ˈkɒl.əm/', 'sütun'),
  ('sword', 'w', '/sɔːrd/', 'kılıç'),
  ('whistle', 't', '/ˈwɪs.əl/', 'düdük / ıslık'),
  ('honest', 'h', '/ˈɒn.ɪst/', 'dürüst'),
  ('doubt', 'b', '/daʊt/', 'şüphe'),
  ('thumb', 'b', '/θʌm/', 'başparmak'),
  ('knee', 'k', '/niː/', 'diz'),
  ('wrist', 'w', '/rɪst/', 'bilek'),
  ('answer', 'w', '/ˈɑːn.sər/', 'cevap'),
  ('Wednesday', 'd', '/ˈwenz.deɪ/', 'Çarşamba'),
  ('salmon', 'l', '/ˈsæm.ən/', 'somon'),
  ('almond', 'l', '/ˈɑː.mənd/', 'badem'),
  ('ballet', 't', '/ˈbæl.eɪ/', 'bale'),
  ('debris', 's', '/dəˈbriː/', 'enkaz / kalıntı'),
  ('mortgage', 't', '/ˈmɔːr.ɡɪdʒ/', 'konut kredisi'),
  ('raspberry', 'p', '/ˈræz.bər.i/', 'ahududu'),
  ('cupboard', 'p', '/ˈkʌb.ərd/', 'dolap'),
  ('hour', 'h', '/aʊər/', 'saat'),
  ('design', 'g', '/dɪˈzaɪn/', 'tasarım'),
  ('foreign', 'g', '/ˈfɒr.ən/', 'yabancı'),
  ('knife', 'k', '/naɪf/', 'bıçak'),
  ('chalk', 'l', '/tʃɔːk/', 'tebeşir'),
];

const _homophones = <(String w1, String w2, String ipa, String trPair)>[
  ('flower', 'flour', '/ˈflaʊ.ər/', 'çiçek / un'),
  ('knight', 'night', '/naɪt/', 'şövalye / gece'),
  ('peace', 'piece', '/piːs/', 'barış / parça'),
  ('right', 'write', '/raɪt/', 'doğru / yazmak'),
  ('sea', 'see', '/siː/', 'deniz / görmek'),
  ('pair', 'pear', '/peər/', 'çift / armut'),
  ('bare', 'bear', '/beər/', 'çıplak / ayı'),
  ('break', 'brake', '/breɪk/', 'kırmak / fren'),
  ('mail', 'male', '/meɪl/', 'posta / erkek'),
  ('plain', 'plane', '/pleɪn/', 'ova / uçak'),
  ('tail', 'tale', '/teɪl/', 'kuyruk / masal'),
  ('wait', 'weight', '/weɪt/', 'beklemek / ağırlık'),
  ('weak', 'week', '/wiːk/', 'zayıf / hafta'),
  ('wood', 'would', '/wʊd/', 'odun / -ecekti'),
  ('dear', 'deer', '/dɪər/', 'sevgili / geyik'),
  ('heal', 'heel', '/hiːl/', 'iyileşmek / topuk'),
  ('meat', 'meet', '/miːt/', 'et / buluşmak'),
  ('one', 'won', '/wʌn/', 'bir / kazandı'),
  ('sail', 'sale', '/seɪl/', 'yelken / indirim'),
  ('stair', 'stare', '/steər/', 'basamak / dik dik bakmak'),
  ('steal', 'steel', '/stiːl/', 'çalmak / çelik'),
  ('sun', 'son', '/sʌn/', 'güneş / oğul'),
  ('waste', 'waist', '/weɪst/', 'israf / bel'),
  ('whole', 'hole', '/həʊl/', 'bütün / delik'),
  ('aloud', 'allowed', '/əˈlaʊd/', 'sesli / izinli'),
  ('blue', 'blew', '/bluː/', 'mavi / esti'),
  ('ate', 'eight', '/eɪt/', 'yedi (fiil) / sekiz'),
  ('road', 'rode', '/rəʊd/', 'yol / sürdü'),
];

const _stress30 = <(String word, String stressed, String ipa, String tr)>[
  ('photography', '2. hece', '/fəˈtɒɡ.rə.fi/', 'fotoğrafçılık'),
  ('technology', '2. hece', '/tekˈnɒl.ə.dʒi/', 'teknoloji'),
  ('geography', '2. hece', '/dʒiˈɒɡ.rə.fi/', 'coğrafya'),
  ('economy', '2. hece', '/ɪˈkɒn.ə.mi/', 'ekonomi'),
  ('develop', '2. hece', '/dɪˈvel.əp/', 'geliştirmek'),
  ('hotel', '2. hece', '/həʊˈtel/', 'otel'),
  ('balloon', '2. hece', '/bəˈluːn/', 'balon'),
  ('guitar', '2. hece', '/ɡɪˈtɑːr/', 'gitar'),
  ('tomorrow', '2. hece', '/təˈmɒr.əʊ/', 'yarın'),
  ('umbrella', '2. hece', '/ʌmˈbrel.ə/', 'şemsiye'),
  ('calendar', '1. hece', '/ˈkæl.ən.dər/', 'takvim'),
  ('mountain', '1. hece', '/ˈmaʊn.tɪn/', 'dağ'),
  ('library', '1. hece', '/ˈlaɪ.brər.i/', 'kütüphane'),
  ('hospital', '1. hece', '/ˈhɒs.pɪ.təl/', 'hastane'),
  ('bicycle', '1. hece', '/ˈbaɪ.sɪ.kəl/', 'bisiklet'),
  ('atmosphere', '1. hece', '/ˈæt.mə.sfɪər/', 'atmosfer'),
  ('architecture', '1. hece', '/ˈɑː.kɪ.tek.tʃər/', 'mimarlık'),
  ('chocolate', '1. hece', '/ˈtʃɒk.lət/', 'çikolata'),
  ('orchestra', '1. hece', '/ˈɔː.kɪ.strə/', 'orkestra'),
  ('symphony', '1. hece', '/ˈsɪm.fə.ni/', 'senfoni'),
  ('engineer', '3. hece', '/ˌen.dʒɪˈnɪər/', 'mühendis'),
  ('afternoon', '3. hece', '/ˌɑːf.təˈnuːn/', 'öğleden sonra'),
  ('understand', '3. hece', '/ˌʌn.dəˈstænd/', 'anlamak'),
  ('volunteer', '3. hece', '/ˌvɒl.ənˈtɪər/', 'gönüllü'),
  ('magazine', '3. hece', '/ˌmæɡ.əˈziːn/', 'dergi'),
  ('recommend', '3. hece', '/ˌrek.əˈmend/', 'tavsiye etmek'),
  ('guarantee', '3. hece', '/ˌɡær.ənˈtiː/', 'garanti'),
  ('pioneer', '3. hece', '/ˌpaɪ.əˈnɪər/', 'öncü'),
  ('information', '3. hece', '/ˌɪn.fəˈmeɪ.ʃən/', 'bilgi'),
  ('university', '3. hece', '/ˌjuː.nɪˈvɜː.sə.ti/', 'üniversite'),
];

const _minPairs = <(String phrase, String diff, String ipa)>[
  ('ship and sheep', 'Kısa /ɪ/ ile uzun /iː/ ünlü farkı', '/ʃɪp/ – /ʃiːp/'),
  ('live and leave', 'Kısa /ɪ/ ile uzun /iː/ ünlü farkı', '/lɪv/ – /liːv/'),
  ('full and fool', 'Kısa /ʊ/ ile uzun /uː/ ünlü farkı', '/fʊl/ – /fuːl/'),
  ('pull and pool', 'Kısa /ʊ/ ile uzun /uː/ ünlü farkı', '/pʊl/ – /puːl/'),
  ('cheap and sheep', 'Başlangıç ünsüzü /tʃ/ ile /ʃ/ farkı', '/tʃiːp/ – /ʃiːp/'),
  ('fan and van', 'Ötümsüz /f/ ile ötümlü /v/ farkı', '/fæn/ – /væn/'),
  ('vest and west', 'Diş-dudak /v/ ile dudak /w/ farkı', '/vest/ – /west/'),
  ('think and sink', 'Peltek /θ/ ile /s/ ünsüz farkı', '/θɪŋk/ – /sɪŋk/'),
  ('three and tree', 'Peltek /θ/ ile patlamalı /t/ farkı', '/θriː/ – /triː/'),
  ('bed and bad', 'Orta /e/ ile açık /æ/ ünlü farkı', '/bed/ – /bæd/'),
  ('walk and work', 'Yuvarlak /ɔː/ ile merkez /ɜː/ farkı', '/wɔːk/ – /wɜːk/'),
  ('pat and bat', 'Ötümsüz /p/ ile ötümlü /b/ farkı', '/pæt/ – /bæt/'),
  ('coat and goat', 'Ötümsüz /k/ ile ötümlü /ɡ/ farkı', '/kəʊt/ – /ɡəʊt/'),
  ('tie and die', 'Ötümsüz /t/ ile ötümlü /d/ farkı', '/taɪ/ – /daɪ/'),
  ('price and prize', 'Son /s/ ile son /z/ ünsüz farkı', '/praɪs/ – /praɪz/'),
  ('loose and lose', 'Son /s/ ile son /z/ ünsüz farkı', '/luːs/ – /luːz/'),
];

const _edGroups = <(String words, String sound, String rule)>[
  ('worked, watched, laughed, stopped', '/t/ sesi', 'Ötümsüz ünsüzlerle biten fiillerde -ed eki /t/ okunur.'),
  ('helped, looked, washed, danced', '/t/ sesi', 'p, k, sh, s gibi ötümsüz seslerden sonra -ed eki /t/ okunur.'),
  ('played, called, cleaned, opened', '/d/ sesi', 'Ötümlü seslerle biten fiillerde -ed eki /d/ okunur.'),
  ('lived, moved, rained, traveled', '/d/ sesi', 'v, n, l gibi ötümlü seslerden sonra -ed eki /d/ okunur.'),
  ('wanted, needed, decided, visited', '/ɪd/ hecesi', 't veya d sesiyle biten fiillerde -ed eki /ɪd/ hecesi ekler.'),
  ('started, waited, painted, landed', '/ɪd/ hecesi', 't ve d ile biten köklere gelen -ed ayrı bir /ɪd/ hecesi oluşturur.'),
  ('books, cats, maps, cups', '/s/ sesi', 'Ötümsüz ünsüzlerden sonra -s çoğul eki /s/ okunur.'),
  ('dogs, bags, trees, pens', '/z/ sesi', 'Ötümlü seslerden sonra -s çoğul eki /z/ okunur.'),
  ('watches, boxes, buses, dishes', '/ɪz/ hecesi', 'ch, x, s, sh ile biten isimlerde -es eki /ɪz/ hecesi oluşturur.'),
];

AdvancedItem _buildPronunciation100k(int i) {
  final kind = i % 5; // 5 × 800 = 4.000
  final k = i ~/ 5;
  final lang = _accentAt(i);
  if (kind == 0) {
    final s = _silentLetters[k % _silentLetters.length];
    final lettersInWord = s.$1.toLowerCase().split('').toSet().toList();
    final pool = <String>{...lettersInWord, 't', 'k', 'b', 'p', 'h', 'w', 'l', 'n', 'g', 's'}.toList();
    return AdvancedItem(
      'İngilizce "${s.$1}" (${s.$4}) sözcüğünü dinleyip söyleyin. Bu sözcükte okunmayan (sessiz / silent) harf hangisidir?',
      '"${s.$2}" harfi',
      [for (final l in _pickDistinct(pool, s.$2, i + 3)) '"$l" harfi'],
      '"${s.$1}" (${s.$3}) telaffuz edilirken "${s.$2}" harfi sessiz kalır.',
      activity: QuestionActivity(
        kind: ActivityKind.pronunciation,
        title: 'Sessiz Harf (Silent Letter)',
        language: lang,
        transcript: s.$1,
        items: ['Fonetik: ${s.$3} · ${s.$4}'],
      ),
    );
  } else if (kind == 1) {
    final h = _homophones[k % _homophones.length];
    final pool = [for (final x in _homophones) x.$2];
    return AdvancedItem(
      'İngilizce "${h.$1}" sözcüğünü dinleyin (${h.$3}). Aynı telaffuza sahip eşsesli (homophone) sözcük hangisidir?',
      h.$2,
      _pickDistinct(pool, h.$2, i + 5),
      '"${h.$1}" ve "${h.$2}" (${h.$4}) tam olarak aynı ${h.$3} telaffuzuna sahiptir.',
      activity: QuestionActivity(
        kind: ActivityKind.pronunciation,
        title: 'Eşsesli Sözcükler (Homophones)',
        language: lang,
        transcript: '${h.$1}. ${h.$2}.',
        items: ['Fonetik: ${h.$3} · ${h.$4}'],
      ),
    );
  } else if (kind == 2) {
    final st = _stress30[k % _stress30.length];
    return AdvancedItem(
      'İngilizce "${st.$1}" (${st.$4}) sözcüğünü dinleyip tekrarlayın. Ana hece vurgusu (primary stress) kaçıncı hecededir?',
      st.$2,
      _pickDistinct(const ['1. hece', '2. hece', '3. hece', '4. hece'], st.$2, i + 7),
      '"${st.$1}" (${st.$3}) sözcüğünde ana vurgu ${st.$2} üzerindedir.',
      activity: QuestionActivity(
        kind: ActivityKind.pronunciation,
        title: 'Hece Vurgusu (Word Stress)',
        language: lang,
        transcript: st.$1,
        items: ['Fonetik: ${st.$3} · ${st.$4}'],
      ),
    );
  } else if (kind == 3) {
    final m = _minPairs[k % _minPairs.length];
    final pool = _minPairs.map((x) => x.$2).toSet().toList();
    return AdvancedItem(
      '"${m.$1}" minimal çiftini dinleyip söyleyin. Bu iki sözcüğü birbirinden ayıran temel ses farkı hangisidir?',
      m.$2,
      _pickDistinct(pool, m.$2, i + 11),
      '"${m.$1}" (${m.$3}) çiftini ayıran temel özellik: ${m.$2}.',
      activity: QuestionActivity(
        kind: ActivityKind.pronunciation,
        title: 'Minimal Çift Telaffuzu',
        language: lang,
        transcript: m.$1,
        items: ['Fonetik: ${m.$3}'],
      ),
    );
  } else {
    final g = _edGroups[k % _edGroups.length];
    return AdvancedItem(
      'Örnek sözcükleri dinleyip sırayla telaffuz edin. Bu gruptaki ekler hangi sesle biter?',
      g.$2,
      _pickDistinct(const ['/t/ sesi', '/d/ sesi', '/ɪd/ hecesi', '/s/ sesi', '/z/ sesi', '/ɪz/ hecesi'], g.$2, i + 13),
      g.$3,
      activity: QuestionActivity(
        kind: ActivityKind.pronunciation,
        title: '-ed / -s Ek Sesletimi',
        language: lang,
        transcript: g.$1,
        items: ['Hedef ses: ${g.$2}'],
      ),
    );
  }
}

final List<AdvancedFamily> audioEnglish25kFamilies = [
  AdvancedFamily(
    key: 's100_en_dialogues',
    title: 'Sesli İngilizce · 14 Senaryolu Gerçek Diyalog & Anons',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 7000,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.listening,
    bloom: BloomLevel.anlama,
    sourceLabel: 'Bilgili 3.21 · Sesli İngilizce 25K',
    build: _buildDialogue100k,
  ),
  AdvancedFamily(
    key: 's100_en_vocab_idioms',
    title: 'Sesli İngilizce · A2–C1 Kelime, Deyim & Phrasal Verb',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 5000,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.listening,
    bloom: BloomLevel.anlama,
    sourceLabel: 'Bilgili 3.21 · Sesli İngilizce 25K',
    build: _buildVocab100k,
  ),
  AdvancedFamily(
    key: 's100_en_ielts_num',
    title: 'Sesli İngilizce · IELTS Sayı, İndirim, Saat & Tarih',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 4000,
    difficulty: Difficulty.hard,
    activityKind: ActivityKind.listening,
    bloom: BloomLevel.analiz,
    sourceLabel: 'Bilgili 3.21 · Sesli İngilizce 25K',
    build: _buildIeltsNum100k,
  ),
  AdvancedFamily(
    key: 's100_en_dictation',
    title: 'Sesli İngilizce · 125 Kelimelik Dinle-Yaz Dikte',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 5000,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.dictation,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.21 · Sesli İngilizce 25K',
    build: _buildDictation100k,
  ),
  AdvancedFamily(
    key: 's100_en_pronunciation',
    title: 'Sesli İngilizce · Telaffuz, Sessiz Harf, Vurgu & Eşsesli',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 4000,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.pronunciation,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.21 · Sesli İngilizce 25K',
    build: _buildPronunciation100k,
  ),
];
