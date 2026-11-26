import '../common.dart';

const _accents = ['en-US', 'en-US-female', 'en-GB', 'en-GB-female', 'en-AU'];
String _accent(int i) => _accents[i % _accents.length];

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

List<String> _distinctWrong(List<String> pool, String correct, int seed) {
  final out = <String>[];
  final n = pool.length;
  var step = 1;
  for (final candStep in const [5, 3, 7, 2, 1]) {
    if (n > candStep && _gcd(n, candStep) == 1) {
      step = candStep;
      break;
    }
  }
  var idx = (seed * 13 + 3) % n;
  var guard = 0;
  while (out.length < 3 && guard < n) {
    final c = pool[idx];
    if (c != correct && !out.contains(c)) out.add(c);
    idx = (idx + step) % n;
    guard++;
  }
  return out;
}

// ---------------------------------------------------------------------------
// 1. GÜNLÜK İNGİLİZCE DİYALOG & ANONS DİNLEME (800 soru)
// ---------------------------------------------------------------------------
const _cities = [
  ('London', 'Londra'),
  ('Berlin', 'Berlin'),
  ('Paris', 'Paris'),
  ('Rome', 'Roma'),
  ('Madrid', 'Madrid'),
  ('Vienna', 'Viyana'),
  ('Dublin', 'Dublin'),
  ('Lisbon', 'Lizbon'),
  ('Prague', 'Prag'),
  ('Amsterdam', 'Amsterdam'),
];

const _delays = [
  ('twenty minutes', '20 dakika'),
  ('thirty-five minutes', '35 dakika'),
  ('forty-five minutes', '45 dakika'),
  ('one hour', '1 saat'),
  ('fifty minutes', '50 dakika'),
];

const _reasons = [
  ('heavy rain', 'şiddetli yağmur'),
  ('dense fog', 'yoğun sis'),
  ('a technical inspection', 'teknik kontrol'),
  ('air traffic congestion', 'hava trafiği yoğunluğu'),
  ('strong crosswinds', 'şiddetli yan rüzgâr'),
];

const _cafeItems = [
  ('an iced oat latte and a blueberry muffin', 'buzlu yulaf sütlü latte ve yaban mersinli kek'),
  ('a green tea and a cheese croissant', 'yeşil çay ve peynirli kruvasan'),
  ('a double espresso and an apple tart', 'çift shot espresso ve elmalı turta'),
  ('a hot chocolate and a toasted sandwich', 'sıcak çikolata ve tost'),
  ('a cappuccino and a slice of lemon cake', 'cappuccino ve bir dilim limonlu kek'),
];

const _rooms = [
  ('a quiet double room overlooking the garden', 'bahçeye bakan sessiz çift kişilik oda'),
  ('a single room on the fourth floor with a balcony', 'dördüncü katta balkonlu tek kişilik oda'),
  ('a family suite near the elevator', 'asansöre yakın aile süiti'),
  ('a corner room with a sea view', 'deniz manzaralı köşe oda'),
  ('a standard twin room with breakfast included', 'kahvaltı dâhil iki yataklı standart oda'),
];

const _weathers = [
  ('sunny skies in the morning followed by light showers in the evening', 'sabah güneşli, akşam hafif sağanak yağışlı'),
  ('chilly winds and overcast clouds throughout the afternoon', 'öğleden sonra serin rüzgârlı ve kapalı'),
  ('clear skies with temperatures reaching twenty-six degrees', 'açık gökyüzü ve 26 dereceye ulaşan sıcaklık'),
  ('heavy snowfall in the northern hills overnight', 'gece kuzey tepelerde yoğun kar yağışı'),
  ('mild coastal breezes and scattered clouds all weekend', 'hafta sonu boyunca ılık kıyı rüzgârı ve parçalı bulutlu'),
];

const _officeRooms = [
  ('Conference Room B on the third floor', '3. kattaki B Toplantı Odası'),
  ('the main auditorium downstairs', 'alt kattaki ana konferans salonu'),
  ('Room 204 next to the design studio', 'tasarım stüdyosunun yanındaki 204 numaralı oda'),
  ('the rooftop lounge after lunch', 'öğle yemeğinden sonra çatı salonu'),
  ('the training lab on the second floor', '2. kattaki eğitim laboratuvarı'),
];

const _days = [
  ('Monday', 'Pazartesi'),
  ('Tuesday', 'Salı'),
  ('Wednesday', 'Çarşamba'),
  ('Thursday', 'Perşembe'),
  ('Friday', 'Cuma'),
];

const _healthAdvice = [
  ('take one tablet after dinner and drink plenty of water', 'akşam yemeğinden sonra bir tablet almak ve bol su içmek'),
  ('rest for two days and avoid cold drinks', 'iki gün dinlenmek ve soğuk içeceklerden kaçınmak'),
  ('apply this cream twice a day before sleeping', 'bu kremi uyumadan önce günde iki kez sürmek'),
  ('return next Wednesday for a quick blood test', 'hızlı kan testi için gelecek Çarşamba tekrar gelmek'),
  ('use the herbal spray whenever your throat feels dry', 'boğaz kuruduğunda bitkisel spreyi kullanmak'),
];

const _shopDiscounts = [
  ('thirty percent off all winter coats today', 'bugün tüm kışlık montlarda %30 indirim'),
  ('buy two books and get the third one completely free', 'iki kitap alana üçüncüsü tamamen ücretsiz'),
  ('twenty percent student discount on headphones', 'kulaklıklarda %20 öğrenci indirimi'),
  ('half price on fresh bakery items after six o’clock', 'saat altıdan sonra taze fırın ürünlerinde yarı fiyat'),
  ('fifteen percent off if you pay with a contactless card', 'temassız kartla ödemede %15 indirim'),
];

const _museumExhibits = [
  ('ancient Anatolian bronze sculptures', 'antik Anadolu tunç heykelleri'),
  ('nineteenth-century maritime maps and compasses', '19. yüzyıl denizcilik haritaları ve pusulaları'),
  ('modern kinetic light installations', 'modern kinetik ışık yerleştirmeleri'),
  ('rare Ottoman calligraphy manuscripts', 'nadir Osmanlı hat elyazmaları'),
  ('early space exploration photography', 'erken dönem uzay keşfi fotoğrafları'),
];

const _lectureTopics = [
  ('renewable battery storage systems', 'yenilenebilir batarya depolama sistemleri'),
  ('how urban trees cool city streets', 'kent ağaçlarının sokakları nasıl serinlettiği'),
  ('the economics of high-speed rail networks', 'yüksek hızlı tren ağlarının ekonomisi'),
  ('machine translation in low-resource languages', 'az kaynaklı dillerde makine çevirisi'),
  ('coral reef restoration techniques', 'mercan resifi onarım teknikleri'),
];

AdvancedItem _buildListeningScene(int i) {
  final scene = i % 10; // 10 scenarios × 80 variants = 800
  final k = i ~/ 10;
  final lang = _accent(i);

  switch (scene) {
    case 0:
      final city = _cities[k % _cities.length];
      final delay = _delays[(k ~/ 2) % _delays.length];
      final reason = _reasons[(k ~/ 3) % _reasons.length];
      final gate = 12 + (k % 18);
      final transcript =
          'Attention passengers. Flight TK ${210 + k} to ${city.$1} from Gate $gate has been delayed by ${delay.$1} due to ${reason.$1}. Please remain near the boarding area.';
      final askReason = k.isOdd;
      return AdvancedItem(
        askReason
            ? 'Havaalanı anonsunu dinleyin. Uçuşun gecikme nedeni nedir?'
            : 'Havaalanı anonsunu dinleyin. ${city.$2} uçuşu ne kadar gecikmiştir?',
        askReason ? reason.$2 : delay.$2,
        askReason
            ? _distinctWrong(_reasons.map((e) => e.$2).toList(), reason.$2, i + 3)
            : _distinctWrong(_delays.map((e) => e.$2).toList(), delay.$2, i + 5),
        'Anons: "$transcript" → ${city.$2} uçuşu (Kapı $gate) ${reason.$2} nedeniyle ${delay.$2} gecikmiştir.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Havaalanı Anonsu',
          language: lang,
          transcript: transcript,
        ),
      );
    case 1:
      final item = _cafeItems[k % _cafeItems.length];
      final seat = k.isEven ? 'by the window' : 'on the sunny terrace';
      final seatTr = k.isEven ? 'pencere kenarında' : 'güneşli terasta';
      final transcript =
          'Good afternoon! Could I please order ${item.$1}? I will be sitting $seat, and I would like to pay by card.';
      return AdvancedItem(
        'Kafe siparişini dinleyin. Müşteri tam olarak ne sipariş ediyor?',
        item.$2,
        _distinctWrong(_cafeItems.map((e) => e.$2).toList(), item.$2, i + 7),
        'Müşteri "$seatTr" oturacağını belirterek ${item.$2} sipariş ediyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Kafe Siparişi',
          language: lang,
          transcript: transcript,
        ),
      );
    case 2:
      final room = _rooms[k % _rooms.length];
      final nights = 2 + (k % 5);
      final transcript =
          'Hello, I have a reservation under Demir for $nights nights. I specifically requested ${room.$1}. Could I also get an early check-in?';
      return AdvancedItem(
        'Otel resepsiyon konuşmasını dinleyin. Konuk nasıl bir oda talep etmiştir?',
        room.$2,
        _distinctWrong(_rooms.map((e) => e.$2).toList(), room.$2, i + 11),
        'Konuk $nights gece konaklamak üzere ${room.$2} ayırtmıştır.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Otel Resepsiyonu',
          language: lang,
          transcript: transcript,
        ),
      );
    case 3:
      final w = _weathers[k % _weathers.length];
      final city = _cities[(k + 2) % _cities.length];
      final transcript =
          'Here is the latest weather update for ${city.$1}. Residents can expect ${w.$1}. Do not forget to dress accordingly.';
      return AdvancedItem(
        'İngilizce hava durumu bültenini dinleyin. ${city.$2} için tahmin nedir?',
        w.$2,
        _distinctWrong(_weathers.map((e) => e.$2).toList(), w.$2, i + 13),
        '${city.$2} bülteninde "${w.$2}" hava koşulları öngörülmektedir.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Hava Durumu Bülteni',
          language: lang,
          transcript: transcript,
        ),
      );
    case 4:
      final room = _officeRooms[k % _officeRooms.length];
      final day = _days[(k ~/ 2) % _days.length];
      final transcript =
          'Quick reminder for the project team: our ${day.$1} briefing has been relocated to ${room.$1}. Please bring your printed quarterly charts.';
      final askDay = k % 3 == 0;
      return AdvancedItem(
        askDay
            ? 'Ofis duyurusunu dinleyin. Proje toplantısı hangi gün yapılacaktır?'
            : 'Ofis duyurusunu dinleyin. Toplantı hangi mekâna alınmıştır?',
        askDay ? day.$2 : room.$2,
        askDay
            ? _distinctWrong(_days.map((e) => e.$2).toList(), day.$2, i + 17)
            : _distinctWrong(_officeRooms.map((e) => e.$2).toList(), room.$2, i + 19),
        'Toplantı ${day.$2} günü ${room.$2} konumuna taşınmıştır.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Ofis Duyurusu',
          language: lang,
          transcript: transcript,
        ),
      );
    case 5:
      final adv = _healthAdvice[k % _healthAdvice.length];
      final transcript =
          'Your examination looks reassuring, and there is no sign of infection. However, I recommend that you ${adv.$1}. Call the clinic if the symptoms persist.';
      return AdvancedItem(
        'Doktorun önerisini dinleyin. Hastaya hangi talimat verilmektedir?',
        adv.$2,
        _distinctWrong(_healthAdvice.map((e) => e.$2).toList(), adv.$2, i + 23),
        'Doktor enfeksiyon olmadığını belirterek hastaya "${adv.$2}" tavsiyesinde bulunuyor.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Klinik Tavsiyesi',
          language: lang,
          transcript: transcript,
        ),
      );
    case 6:
      final disc = _shopDiscounts[k % _shopDiscounts.length];
      final transcript =
          'Welcome shoppers! As part of our seasonal promotion, we are offering ${disc.$1}. Visit the customer desk for membership points.';
      return AdvancedItem(
        'Mağaza kampanya anonsunu dinleyin. Müşterilere hangi fırsat sunuluyor?',
        disc.$2,
        _distinctWrong(_shopDiscounts.map((e) => e.$2).toList(), disc.$2, i + 29),
        'Kampanya duyurusu "${disc.$2}" fırsatını içermektedir.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Mağaza Kampanyası',
          language: lang,
          transcript: transcript,
        ),
      );
    case 7:
      final ex = _museumExhibits[k % _museumExhibits.length];
      final floor = (k % 3) + 1;
      final transcript =
          'Welcome to the City Museum. Our new temporary gallery on floor $floor features ${ex.$1}. Audio guides are complimentary at the entrance.';
      return AdvancedItem(
        'Müze rehber sesini dinleyin. $floor. kattaki yeni sergide ne yer almaktadır?',
        ex.$2,
        _distinctWrong(_museumExhibits.map((e) => e.$2).toList(), ex.$2, i + 31),
        'Müzenin $floor. katındaki yeni geçici sergide ${ex.$2} sergilenmektedir.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Müze Rehberi',
          language: lang,
          transcript: transcript,
        ),
      );
    case 8:
      final lec = _lectureTopics[k % _lectureTopics.length];
      final day = _days[(k + 1) % _days.length];
      final transcript =
          'Good morning everyone. This ${day.$1}, guest professor Clarke will deliver an open seminar on ${lec.$1}. Registration closes at noon.';
      return AdvancedItem(
        'Üniversite seminer anonsunu dinleyin. Konuk profesörün konuşma konusu nedir?',
        lec.$2,
        _distinctWrong(_lectureTopics.map((e) => e.$2).toList(), lec.$2, i + 37),
        '${day.$2} günkü açık seminerin konusu "${lec.$2}" olarak duyurulmuştur.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Üniversite Semineri',
          language: lang,
          transcript: transcript,
        ),
      );
    default:
      final city = _cities[(k + 4) % _cities.length];
      final plat = 2 + (k % 9);
      final mins = 5 + (k % 5) * 5;
      final transcript =
          'The express train to ${city.$1} will now depart from Platform $plat in $mins minutes instead of Platform ${plat + 1}. Have your digital tickets ready.';
      final askPlat = k.isEven;
      return AdvancedItem(
        askPlat
            ? 'Tren istasyonu anonsunu dinleyin. ${city.$2} ekspresi hangi perondan kalkacaktır?'
            : 'Tren istasyonu anonsunu dinleyin. Ekspres tren kaç dakika içinde hareket edecektir?',
        askPlat ? 'Peron $plat' : '$mins dakika',
        askPlat
            ? ['Peron ${plat + 1}', 'Peron ${plat + 2}', 'Peron ${plat > 1 ? plat - 1 : plat + 3}']
            : ['${mins + 5} dakika', '${mins + 10} dakika', '${mins > 5 ? mins - 5 : mins + 15} dakika'],
        '${city.$2} ekspres treni Peron ${plat + 1} yerine Peron $plat üzerinden $mins dakika içinde kalkacaktır.',
        activity: QuestionActivity(
          kind: ActivityKind.listening,
          title: 'Tren İstasyonu Anonsu',
          language: lang,
          transcript: transcript,
        ),
      );
  }
}

// ---------------------------------------------------------------------------
// 2. SESLİ İNGİLİZCE KELİME, DEYİM & PHRASAL VERB STÜDYOSU (600 soru)
// ---------------------------------------------------------------------------
typedef _VocabAudio = ({
  String term,
  String trMeaning,
  String enSyn,
  String sentence,
  String kind,
});

const _vocabAudioPool = <_VocabAudio>[
  (term: 'postpone', trMeaning: 'ertelemek', enSyn: 'delay', sentence: 'They decided to postpone the outdoor concert until Sunday.', kind: 'Fiil'),
  (term: 'call off', trMeaning: 'iptal etmek', enSyn: 'cancel', sentence: 'The coach had to call off practice because of lightning.', kind: 'Phrasal Verb'),
  (term: 'break a leg', trMeaning: 'iyi şanslar dilemek', enSyn: 'good luck', sentence: 'Before the actress stepped on stage, her friends whispered break a leg.', kind: 'Deyim'),
  (term: 'figure out', trMeaning: 'çözümünü bulmak / anlamak', enSyn: 'solve', sentence: 'It took us an hour to figure out how the new scanner works.', kind: 'Phrasal Verb'),
  (term: 'once in a blue moon', trMeaning: 'kırk yılda bir / çok nadir', enSyn: 'very rarely', sentence: 'My uncle visits the city once in a blue moon.', kind: 'Deyim'),
  (term: 'reluctant', trMeaning: 'isteksiz / gönülsüz', enSyn: 'hesitant', sentence: 'She was reluctant to sign the contract before reading every clause.', kind: 'Sıfat'),
  (term: 'run out of', trMeaning: 'tüketmek / kalmamak', enSyn: 'exhaust supply', sentence: 'We are about to run out of printer paper before the deadline.', kind: 'Phrasal Verb'),
  (term: 'piece of cake', trMeaning: 'çok kolay iş / çocuk oyuncağı', enSyn: 'very easy', sentence: 'After weeks of practice, the driving exam felt like a piece of cake.', kind: 'Deyim'),
  (term: 'reliable', trMeaning: 'güvenilir', enSyn: 'dependable', sentence: 'Public trains here are remarkably reliable even in winter.', kind: 'Sıfat'),
  (term: 'look forward to', trMeaning: 'dört gözle beklemek', enSyn: 'eagerly anticipate', sentence: 'The students look forward to visiting the planetarium next week.', kind: 'Phrasal Verb'),
  (term: 'hit the sack', trMeaning: 'yatmaya gitmek / uyumak', enSyn: 'go to bed', sentence: 'After a twelve-hour flight, I just want to hit the sack.', kind: 'Deyim'),
  (term: 'abundant', trMeaning: 'bol / bereketli', enSyn: 'plentiful', sentence: 'Solar energy is abundant across the southern coastline.', kind: 'Sıfat'),
  (term: 'turn down', trMeaning: 'geri çevirmek / reddetmek', enSyn: 'reject', sentence: 'He had to turn down the job offer because of the long commute.', kind: 'Phrasal Verb'),
  (term: 'under the weather', trMeaning: 'keyifsiz / hafif hasta hissetmek', enSyn: 'feeling slightly ill', sentence: 'Maya stayed home today because she was feeling under the weather.', kind: 'Deyim'),
  (term: 'inevitable', trMeaning: 'kaçınılmaz', enSyn: 'unavoidable', sentence: 'With rapid urbanization, higher demand for transit is inevitable.', kind: 'Sıfat'),
  (term: 'come across', trMeaning: 'tesadüfen rastlamak', enSyn: 'find by chance', sentence: 'While organizing the attic, I came across my grandfather’s diary.', kind: 'Phrasal Verb'),
  (term: 'bite the bullet', trMeaning: 'dişini sıkıp zor işi kabullenmek', enSyn: 'face a hard task bravely', sentence: 'We decided to bite the bullet and renovate the old kitchen now.', kind: 'Deyim'),
  (term: 'versatile', trMeaning: 'çok yönlü', enSyn: 'adaptable', sentence: 'Olive oil is one of the most versatile ingredients in Mediterranean cuisine.', kind: 'Sıfat'),
  (term: 'put off', trMeaning: 'sonraya bırakmak / ertelemek', enSyn: 'defer', sentence: 'Never put off repairing a small roof leak until winter.', kind: 'Phrasal Verb'),
  (term: 'spill the beans', trMeaning: 'sırrı ağzından kaçırmak', enSyn: 'reveal a secret', sentence: 'Please do not spill the beans about the surprise anniversary dinner.', kind: 'Deyim'),
  (term: 'scarce', trMeaning: 'kıt / az bulunan', enSyn: 'rare', sentence: 'Fresh drinking water becomes scarce during prolonged droughts.', kind: 'Sıfat'),
  (term: 'carry out', trMeaning: 'yürütmek / uygulamak', enSyn: 'conduct', sentence: 'Marine biologists will carry out a three-month survey near the reef.', kind: 'Phrasal Verb'),
  (term: 'cut corners', trMeaning: 'kaliteden ödün verip ucuza kaçmak', enSyn: 'do poorly to save cost', sentence: 'Bridges fail when contractors cut corners on steel quality.', kind: 'Deyim'),
  (term: 'accurate', trMeaning: 'isabetli / tam doğru', enSyn: 'precise', sentence: 'Atomic clocks provide extraordinarily accurate time measurements.', kind: 'Sıfat'),
  (term: 'get over', trMeaning: 'atlatmak / iyileşmek', enSyn: 'recover from', sentence: 'It took him two full weeks to get over the seasonal flu.', kind: 'Phrasal Verb'),
  (term: 'cost an arm and a leg', trMeaning: 'çok pahalıya mal olmak', enSyn: 'be extremely expensive', sentence: 'Renting an apartment right beside the harbor costs an arm and a leg.', kind: 'Deyim'),
  (term: 'crucial', trMeaning: 'hayati önemde / kritik', enSyn: 'essential', sentence: 'Regular sleep plays a crucial role in long-term memory consolidation.', kind: 'Sıfat'),
  (term: 'bring up', trMeaning: 'bir konuyu gündeme getirmek', enSyn: 'mention', sentence: 'During the meeting, Deniz brought up the issue of battery recycling.', kind: 'Phrasal Verb'),
  (term: 'burn the midnight oil', trMeaning: 'gece geç saatlere kadar çalışmak', enSyn: 'work late into the night', sentence: 'The architects burned the midnight oil to finish the stadium model.', kind: 'Deyim'),
  (term: 'fragile', trMeaning: 'kırılgan / hassas', enSyn: 'delicate', sentence: 'Handle the ceramic vase carefully because its glaze is extremely fragile.', kind: 'Sıfat'),
  (term: 'make up for', trMeaning: 'telafi etmek', enSyn: 'compensate for', sentence: 'She worked extra hours on Friday to make up for the missed afternoon.', kind: 'Phrasal Verb'),
  (term: 'on the same page', trMeaning: 'aynı fikirde / uyum içinde olmak', enSyn: 'in agreement', sentence: 'Let us review the timeline so everyone is on the same page.', kind: 'Deyim'),
  (term: 'feasible', trMeaning: 'uygulanabilir / mümkün', enSyn: 'practical', sentence: 'Engineers confirmed that building a solar ferry is economically feasible.', kind: 'Sıfat'),
  (term: 'cut down on', trMeaning: 'tüketimini azaltmak', enSyn: 'reduce', sentence: 'The nutritionist advised him to cut down on sugary sodas.', kind: 'Phrasal Verb'),
  (term: 'a blessing in disguise', trMeaning: 'ilk başta kötü görünüp hayra çıkan durum', enSyn: 'hidden benefit', sentence: 'Missing that crowded bus turned out to be a blessing in disguise.', kind: 'Deyim'),
  (term: 'persistent', trMeaning: 'ısrarlı / kararlı', enSyn: 'determined', sentence: 'Persistent curiosity often leads to unexpected scientific discoveries.', kind: 'Sıfat'),
  (term: 'look into', trMeaning: 'ayrıntılı incelemek / araştırmak', enSyn: 'investigate', sentence: 'The support team promised to look into the billing error immediately.', kind: 'Phrasal Verb'),
  (term: 'back to the drawing board', trMeaning: 'başa dönüp yeniden planlamak', enSyn: 'start over again', sentence: 'When the prototype failed the wind test, it was back to the drawing board.', kind: 'Deyim'),
  (term: 'vivid', trMeaning: 'canlı / parlak', enSyn: 'bright and clear', sentence: 'The traveler gave a vivid description of the northern lights.', kind: 'Sıfat'),
  (term: 'hand in', trMeaning: 'teslim etmek', enSyn: 'submit', sentence: 'Remember to hand in your lab reports before five o’clock.', kind: 'Phrasal Verb'),
  (term: 'the ball is in your court', trMeaning: 'sıra ve karar artık sende', enSyn: 'it is your turn to act', sentence: 'We sent our revised proposal, so now the ball is in your court.', kind: 'Deyim'),
  (term: 'ambiguous', trMeaning: 'belirsiz / çift anlamlı', enSyn: 'unclear', sentence: 'Legal contracts should avoid ambiguous phrasing that invites disputes.', kind: 'Sıfat'),
  (term: 'set off', trMeaning: 'yolculuğa çıkmak', enSyn: 'begin a journey', sentence: 'The hikers set off at dawn to reach the summit before noon.', kind: 'Phrasal Verb'),
  (term: 'hit the nail on the head', trMeaning: 'tam isabet / can alıcı noktayı söylemek', enSyn: 'be exactly right', sentence: 'Your diagnosis of the network bottleneck hit the nail on the head.', kind: 'Deyim'),
  (term: 'resilient', trMeaning: 'dayanıklı / çabuk toparlanan', enSyn: 'tough and adaptable', sentence: 'Coastal mangroves are remarkably resilient against tropical storms.', kind: 'Sıfat'),
  (term: 'sort out', trMeaning: 'düzene koyup çözmek', enSyn: 'resolve', sentence: 'The coordinator quickly sorted out the seating confusion at the hall.', kind: 'Phrasal Verb'),
  (term: 'beat around the bush', trMeaning: 'lafı dolandırmak', enSyn: 'avoid the main point', sentence: 'Stop beating around the bush and tell us the actual budget.', kind: 'Deyim'),
  (term: 'substantial', trMeaning: 'kayda değer / önemli ölçüde', enSyn: 'considerable', sentence: 'Insulating the attic led to a substantial drop in heating bills.', kind: 'Sıfat'),
  (term: 'give up', trMeaning: 'vazgeçmek / bırakmak', enSyn: 'quit', sentence: 'Even after three failed trials, the young inventor refused to give up.', kind: 'Phrasal Verb'),
  (term: 'speak of the devil', trMeaning: 'iyi insan lafının üstüne gelir', enSyn: 'appear right when mentioned', sentence: 'Speak of the devil, we were just talking about your new bicycle.', kind: 'Deyim'),
  (term: 'meticulous', trMeaning: 'titiz / ince eleyip sık dokuyan', enSyn: 'very careful', sentence: 'Restoring medieval frescoes requires meticulous brushwork.', kind: 'Sıfat'),
  (term: 'catch up with', trMeaning: 'yetişmek / arayı kapatmak', enSyn: 'reach the same level', sentence: 'After missing two classes, he studied all weekend to catch up with the group.', kind: 'Phrasal Verb'),
  (term: 'pull someone’s leg', trMeaning: 'birine takılmak / şaka yapmak', enSyn: 'tease playfully', sentence: 'Relax, I did not really lose the tickets; I was just pulling your leg.', kind: 'Deyim'),
  (term: 'pragmatic', trMeaning: 'gerçekçi / uygulamaya dönük', enSyn: 'realistic', sentence: 'The committee adopted a pragmatic plan that fits the current budget.', kind: 'Sıfat'),
  (term: 'point out', trMeaning: 'dikkat çekmek / işaret etmek', enSyn: 'highlight', sentence: 'The editor politely pointed out a calculation mistake in Table Two.', kind: 'Phrasal Verb'),
  (term: 'call it a day', trMeaning: 'bugünlük işi bitirmek', enSyn: 'stop working for the day', sentence: 'We have painted three walls already; let us call it a day.', kind: 'Deyim'),
  (term: 'lucrative', trMeaning: 'kârlı / kazançlı', enSyn: 'profitable', sentence: 'Exporting specialty olive oil became a lucrative business for the village.', kind: 'Sıfat'),
  (term: 'keep an eye on', trMeaning: 'göz kulak olmak', enSyn: 'watch carefully', sentence: 'Could you keep an eye on my suitcase while I buy a bottle of water?', kind: 'Deyim'),
  (term: 'coherent', trMeaning: 'tutarlı / bütünlüklü', enSyn: 'logical and clear', sentence: 'A coherent essay connects every paragraph to a central thesis.', kind: 'Sıfat'),
  (term: 'take for granted', trMeaning: 'kıymetini bilmeden doğal kabul etmek', enSyn: 'undervalue', sentence: 'Many people take clean tap water for granted until there is an outage.', kind: 'Deyim'),
];

AdvancedItem _buildListeningVocab(int i) {
  // 60 rich items × 10 variants/angles = 600
  final v = _vocabAudioPool[i % _vocabAudioPool.length];
  final angle = (i ~/ _vocabAudioPool.length) % 3;
  final lang = _accent(i);
  final leadIn = switch ((i ~/ (_vocabAudioPool.length * 3)) % 4) {
    0 => '',
    1 => 'Listen carefully. ',
    2 => 'In everyday English: ',
    _ => 'Repeat after me: ',
  };
  final spoken = '$leadIn${v.sentence}';

  if (angle == 0) {
    return AdvancedItem(
      'İngilizce cümleyi dinleyin. Cümlede geçen "${v.term}" (${v.kind}) ifadesinin Türkçe anlamı nedir?',
      v.trMeaning,
      _distinctWrong(_vocabAudioPool.map((e) => e.trMeaning).toList(), v.trMeaning, i + 9),
      'Cümle: "${v.sentence}" → "${v.term}" ifadesi "${v.trMeaning}" (İng. ${v.enSyn}) anlamına gelir.',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'Bağlamda İngilizce (${v.kind})',
        language: lang,
        transcript: spoken,
      ),
    );
  } else if (angle == 1) {
    return AdvancedItem(
      'Cümleyi dinleyin. Duyduğunuz "${v.term}" ifadesine anlamca en yakın İngilizce karşılık hangisidir?',
      v.enSyn,
      _distinctWrong(_vocabAudioPool.map((e) => e.enSyn).toList(), v.enSyn, i + 17),
      '"${v.term}" (${v.trMeaning}) ifadesi İngilizcede "${v.enSyn}" anlamında kullanılır.',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'İngilizce Eş Anlam Dinleme',
        language: lang,
        transcript: spoken,
      ),
    );
  } else {
    return AdvancedItem(
      'Sesli İngilizce cümleyi dinleyin. Konuşmacının kullandığı anahtar "${v.kind}" ifadesi hangisidir?',
      v.term,
      _distinctWrong(_vocabAudioPool.map((e) => e.term).toList(), v.term, i + 25),
      'Seslendirilen cümlede "${v.term}" (${v.trMeaning}) ifadesi geçmektedir: "${v.sentence}"',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'Anahtar İfade Yakalama',
        language: lang,
        transcript: spoken,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. IELTS TARZI SAYI, FİYAT, SAAT & TARİH DİNLEME (400 soru)
// ---------------------------------------------------------------------------
const _teenTyPairs = [
  (13, 'thirteen', 30, 'thirty'),
  (14, 'fourteen', 40, 'forty'),
  (15, 'fifteen', 50, 'fifty'),
  (16, 'sixteen', 60, 'sixty'),
  (17, 'seventeen', 70, 'seventy'),
  (18, 'eighteen', 80, 'eighty'),
  (19, 'nineteen', 90, 'ninety'),
];

const _monthsEn = [
  ('January', 'Ocak'), ('February', 'Şubat'), ('March', 'Mart'),
  ('April', 'Nisan'), ('May', 'Mayıs'), ('June', 'Haziran'),
  ('July', 'Temmuz'), ('August', 'Ağustos'), ('September', 'Eylül'),
  ('October', 'Ekim'), ('November', 'Kasım'), ('December', 'Aralık'),
];

AdvancedItem _buildListeningNumbers(int i) {
  final kind = i % 4; // 0: Price, 1: Gate/Teen-Ty trap, 2: Date & Day, 3: Time & Duration
  final k = i ~/ 4; // 0..99
  final lang = _accent(i);

  if (kind == 0) {
    final pair = _teenTyPairs[k % _teenTyPairs.length];
    final useTeen = k.isEven;
    final dollars = useTeen ? pair.$1 : pair.$3;
    final dollarWord = useTeen ? pair.$2 : pair.$4;
    final trapDollars = useTeen ? pair.$3 : pair.$1;
    final cents = (k % 2 == 0) ? 50 : 25;
    final centWord = cents == 50 ? 'fifty' : 'twenty-five';
    final transcript =
        'Your total at the bookshop comes to $dollarWord dollars and $centWord cents, including tax.';
    final correct = '\$$dollars.$cents';
    return AdvancedItem(
      'Kasiyerin sesli anonsunu dinleyin. Toplam tutar ne kadardır?',
      correct,
      ['\$$trapDollars.$cents', '\$$dollars.${cents == 50 ? 15 : 75}', '\$${dollars + 10}.$cents'],
      'Anons "$dollarWord dollars and $centWord cents" yani $correct tutarını söylüyor ($dollars ile $trapDollars ses ayrımına dikkat!).',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'Fiyat & Sayı Dinleme (IELTS)',
        language: lang,
        transcript: transcript,
      ),
    );
  } else if (kind == 1) {
    final pair = _teenTyPairs[k % _teenTyPairs.length];
    final useTeen = (k ~/ 7).isEven;
    final numVal = useTeen ? pair.$1 : pair.$3;
    final numWord = useTeen ? pair.$2 : pair.$4;
    final trapVal = useTeen ? pair.$3 : pair.$1;
    final city = _cities[k % _cities.length];
    final transcript =
        'Final call for passengers traveling to ${city.$1}. Please proceed immediately to Gate $numWord for boarding.';
    return AdvancedItem(
      'Anonsu dikkatle dinleyin. ${city.$2} uçağı hangi kapıdan yolcu almaktadır?',
      'Kapı $numVal',
      ['Kapı $trapVal', 'Kapı ${numVal + 2}', 'Kapı ${numVal > 3 ? numVal - 2 : numVal + 4}'],
      '"Gate $numWord" ifadesi Kapı $numVal anlamına gelir (-teen ve -ty vurguları ayırt edicidir).',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'Sayı Ayrımı (-teen / -ty)',
        language: lang,
        transcript: transcript,
      ),
    );
  } else if (kind == 2) {
    final m = _monthsEn[k % _monthsEn.length];
    final nextM = _monthsEn[(k + 1) % _monthsEn.length];
    final dayNum = 10 + (k % 18);
    final dayOfWeek = _days[k % _days.length];
    final transcript =
        'Please note that the photography exhibition opens on ${dayOfWeek.$1}, ${m.$1} $dayNum, and remains open for three weeks.';
    final correct = '$dayNum ${m.$2} ${dayOfWeek.$2}';
    final altDay = _days[(k + 2) % _days.length];
    return AdvancedItem(
      'İngilizce tarih anonsunu dinleyin. Sergi hangi tarih ve günde açılıyor?',
      correct,
      ['$dayNum ${nextM.$2} ${dayOfWeek.$2}', '${dayNum + 2} ${m.$2} ${dayOfWeek.$2}', '$dayNum ${m.$2} ${altDay.$2}'],
      'Anons "${dayOfWeek.$1}, ${m.$1} $dayNum" yani "$correct" tarihini belirtmektedir.',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'Tarih & Gün Dinleme',
        language: lang,
        transcript: transcript,
      ),
    );
  } else {
    final h = 8 + (k % 10);
    const mOpts = [(15, 'quarter past'), (30, 'half past'), (45, 'quarter to')];
    final mSpec = mOpts[k % 3];
    final actualH = mSpec.$1 == 45 ? h : h;
    final spokenH = mSpec.$1 == 45 ? h + 1 : h;
    final hh = actualH.toString().padLeft(2, '0');
    final mm = mSpec.$1.toString().padLeft(2, '0');
    final transcript =
        'The guided ferry tour departs at ${mSpec.$2} ${_enNumWord(spokenH)} sharp from Pier Three.';
    final correct = '$hh:$mm';
    return AdvancedItem(
      'Feribot turu anonsunu dinleyin. Tur saat kaçta hareket edecektir?',
      correct,
      [
        '${spokenH.toString().padLeft(2, '0')}:${mSpec.$1 == 45 ? '15' : '45'}',
        '${(actualH + 1).toString().padLeft(2, '0')}:$mm',
        '${actualH.toString().padLeft(2, '0')}:${mSpec.$1 == 30 ? '15' : '30'}',
      ],
      '"${mSpec.$2} ${_enNumWord(spokenH)}" ifadesi $correct saatine karşılık gelir.',
      activity: QuestionActivity(
        kind: ActivityKind.listening,
        title: 'İngilizce Saat Dinleme',
        language: lang,
        transcript: transcript,
      ),
    );
  }
}

String _enNumWord(int n) {
  const words = {
    1: 'one', 2: 'two', 3: 'three', 4: 'four', 5: 'five', 6: 'six',
    7: 'seven', 8: 'eight', 9: 'nine', 10: 'ten', 11: 'eleven', 12: 'twelve',
    13: 'one', 14: 'two', 15: 'three', 16: 'four', 17: 'five', 18: 'six', 19: 'seven',
  };
  return words[n] ?? '$n';
}

// ---------------------------------------------------------------------------
// 4. SESLİ İNGİLİZCE DİKTE & EKSİK KELİME YAZMA (600 soru)
// ---------------------------------------------------------------------------
typedef _DictationEntry = ({
  String word,
  String trClue,
  String before,
  String after,
});

const _dictationBank = <_DictationEntry>[
  (word: 'seatbelt', trClue: 'emniyet kemeri', before: 'Please fasten your', after: 'before takeoff.'),
  (word: 'luggage', trClue: 'bagaj / valiz', before: 'Do not leave your', after: 'unattended in the terminal.'),
  (word: 'passport', trClue: 'pasaport', before: 'Keep your', after: 'ready at border control.'),
  (word: 'boarding', trClue: 'uçağa biniş', before: 'Show your', after: 'pass at Gate Nine.'),
  (word: 'departure', trClue: 'kalkış / ayrılış', before: 'Check the', after: 'screen for any updates.'),
  (word: 'reservation', trClue: 'rezervasyon', before: 'I would like to confirm my', after: 'for tonight.'),
  (word: 'receipt', trClue: 'fiş / makbuz', before: 'Could you please print a', after: 'for this purchase?'),
  (word: 'umbrella', trClue: 'şemsiye', before: 'Take an', after: 'because rain is expected.'),
  (word: 'schedule', trClue: 'program / takvim', before: 'The train is running right on', after: 'this morning.'),
  (word: 'tomorrow', trClue: 'yarın', before: 'The science fair starts', after: 'at ten o’clock.'),
  (word: 'library', trClue: 'kütüphane', before: 'She returned three novels to the', after: 'yesterday.'),
  (word: 'breakfast', trClue: 'kahvaltı', before: 'Fresh fruit and coffee are served for', after: 'every day.'),
  (word: 'mountain', trClue: 'dağ', before: 'They reached the', after: 'hut just before sunset.'),
  (word: 'bridge', trClue: 'köprü', before: 'The historic stone', after: 'crosses the narrow river.'),
  (word: 'calendar', trClue: 'takvim', before: 'Mark the exam date on your', after: 'right away.'),
  (word: 'knowledge', trClue: 'bilgi', before: 'Reading widely expands your', after: 'of history.'),
  (word: 'environment', trClue: 'çevre', before: 'Planting trees helps protect the', after: 'for future generations.'),
  (word: 'temperature', trClue: 'sıcaklık', before: 'The evening', after: 'dropped to eight degrees.'),
  (word: 'scientist', trClue: 'bilim insanı', before: 'The young', after: 'published her findings in June.'),
  (word: 'experiment', trClue: 'deney', before: 'Our chemistry', after: 'confirmed the hypothesis.'),
  (word: 'electricity', trClue: 'elektrik', before: 'Wind turbines generate clean', after: 'for the island.'),
  (word: 'telescope', trClue: 'teleskop', before: 'We observed Saturn’s rings through a', after: 'last night.'),
  (word: 'gravity', trClue: 'yerçekimi', before: 'Earth’s', after: 'keeps the Moon in orbit.'),
  (word: 'oxygen', trClue: 'oksijen', before: 'Forests release', after: 'during photosynthesis.'),
  (word: 'compass', trClue: 'pusula', before: 'Sailors relied on a magnetic', after: 'to find north.'),
  (word: 'century', trClue: 'yüzyıl', before: 'That observatory was built in the nineteenth', after: '.'),
  (word: 'museum', trClue: 'müze', before: 'The archaeology', after: 'opens at nine every Tuesday.'),
  (word: 'concert', trClue: 'konser', before: 'Tickets for the symphony', after: 'sold out quickly.'),
  (word: 'language', trClue: 'dil / lisan', before: 'Listening daily improves your foreign', after: 'skills.'),
  (word: 'dictionary', trClue: 'sözlük', before: 'Look up unfamiliar idioms in a reliable', after: '.'),
  (word: 'pronunciation', trClue: 'telaffuz', before: 'Slow audio clips help you master English', after: '.'),
  (word: 'conversation', trClue: 'sohbet / konuşma', before: 'We had an inspiring', after: 'about urban architecture.'),
  (word: 'interview', trClue: 'mülakat / röportaj', before: 'He prepared thoroughly for his job', after: 'on Monday.'),
  (word: 'colleague', trClue: 'iş arkadaşı', before: 'My', after: 'shared the presentation slides before noon.'),
  (word: 'deadline', trClue: 'son teslim tarihi', before: 'We finished the design well ahead of the', after: '.'),
  (word: 'solution', trClue: 'çözüm', before: 'The team proposed a practical', after: 'to reduce waste.'),
  (word: 'strategy', trClue: 'strateji', before: 'Chess rewards patience and long-term', after: '.'),
  (word: 'challenge', trClue: 'meydan okuma / zorluk', before: 'Learning a new instrument is a rewarding', after: '.'),
  (word: 'progress', trClue: 'ilerleme', before: 'Daily review ensures steady', after: 'every month.'),
  (word: 'decision', trClue: 'karar', before: 'After careful thought, she made a wise', after: '.'),
  (word: 'patience', trClue: 'sabır', before: 'Growing an orchard requires time and', after: '.'),
  (word: 'curiosity', trClue: 'merak', before: 'Genuine', after: 'drives every great discovery.'),
  (word: 'confidence', trClue: 'özgüven', before: 'Speaking aloud builds', after: 'in English.'),
  (word: 'journey', trClue: 'yolculuk', before: 'The scenic train', after: 'took four relaxing hours.'),
  (word: 'harbor', trClue: 'liman', before: 'Ferries cross the busy', after: 'every fifteen minutes.'),
  (word: 'weather', trClue: 'hava durumu', before: 'Check the coastal', after: 'before sailing out.'),
  (word: 'kitchen', trClue: 'mutfak', before: 'Warm bread smelled wonderful in the', after: '.'),
  (word: 'medicine', trClue: 'ilaç / tıp', before: 'Store the', after: 'in a cool, dry cabinet.'),
  (word: 'hospital', trClue: 'hastane', before: 'The new regional', after: 'has a modern solar roof.'),
  (word: 'pharmacy', trClue: 'eczane', before: 'The corner', after: 'stays open until midnight.'),
  (word: 'bicycle', trClue: 'bisiklet', before: 'He commutes to the studio by', after: 'every spring.'),
  (word: 'station', trClue: 'istasyon', before: 'Meet me outside the central subway', after: 'at six.'),
  (word: 'ticket', trClue: 'bilet', before: 'Keep your digital', after: 'accessible on your phone.'),
  (word: 'discount', trClue: 'indirim', before: 'Students receive a twenty percent', after: 'at the theater.'),
  (word: 'payment', trClue: 'ödeme', before: 'Contactless', after: 'makes checkout much faster.'),
  (word: 'account', trClue: 'hesap', before: 'She opened a savings', after: 'at the local bank.'),
  (word: 'balance', trClue: 'denge / bakiye', before: 'Regular exercise helps maintain', after: 'and focus.'),
  (word: 'battery', trClue: 'pil / batarya', before: 'Charge the camera', after: 'before the morning hike.'),
  (word: 'network', trClue: 'ağ', before: 'The fiber', after: 'connects all university campuses.'),
  (word: 'algorithm', trClue: 'algoritma', before: 'A faster', after: 'sorted the records in milliseconds.'),
  (word: 'software', trClue: 'yazılım', before: 'Install the latest', after: 'update for better security.'),
  (word: 'keyboard', trClue: 'klavye', before: 'He typed the English dictation quickly on the', after: '.'),
  (word: 'satellite', trClue: 'uydu', before: 'The weather', after: 'tracks storms across the ocean.'),
  (word: 'volcano', trClue: 'yanardağ', before: 'Geologists monitored the dormant', after: 'all summer.'),
  (word: 'glacier', trClue: 'buzul', before: 'Meltwater from the', after: 'feeds the valley river.'),
  (word: 'island', trClue: 'ada', before: 'Small boats sail to the quiet', after: 'every hour.'),
  (word: 'desert', trClue: 'çöl', before: 'Nighttime temperatures in the', after: 'can be surprisingly cold.'),
  (word: 'forest', trClue: 'orman', before: 'Pine trees cover the northern', after: 'slopes.'),
  (word: 'harvest', trClue: 'hasat', before: 'Autumn is the olive', after: 'season along the Aegean.'),
  (word: 'orchestra', trClue: 'orkestra', before: 'The youth', after: 'rehearsed Mozart all afternoon.'),
  (word: 'melody', trClue: 'melodi / ezgi', before: 'Everyone recognized the cheerful', after: 'immediately.'),
  (word: 'painting', trClue: 'tablo / resim', before: 'The oil', after: 'hung beside the sunlit window.'),
  (word: 'sculpture', trClue: 'heykel', before: 'The marble', after: 'stood at the center of the courtyard.'),
  (word: 'novel', trClue: 'roman', before: 'She finished reading the historical', after: 'in three days.'),
  (word: 'chapter', trClue: 'bölüm', before: 'The opening', after: 'introduces the coastal town.'),
];

const _dictationPrefixes = [
  ('', ''),
  ('Today, ', 'Bugün — '),
  ('Remember: ', 'Hatırlatma — '),
  ('Listen: ', 'Dinle — '),
  ('Note: ', 'Not — '),
  ('Example: ', 'Örnek — '),
  ('Practice: ', 'Pratik — '),
  ('Studio: ', 'Stüdyo — '),
];

AdvancedItem _buildDictation(int i) {
  // 75 core English dictation entries × 8 varied studio frames = 600
  final d = _dictationBank[i % _dictationBank.length];
  final frame = _dictationPrefixes[(i ~/ _dictationBank.length) % _dictationPrefixes.length];
  final fullSentence = '${frame.$1}${d.before} ${d.word} ${d.after}'.replaceAll(' .', '.').replaceAll(' ?', '?');
  final gapped = '${d.before} ___ ${d.after}'.replaceAll(' .', '.').replaceAll(' ?', '?');
  final lang = _accent(i);

  return AdvancedItem(
    '${frame.$2}İngilizce cümleyi dinleyin ve boşluğa gelen İngilizce kelimeyi yazın:\n“$gapped”\n(Anlam ipucu: ${d.trClue})',
    d.word,
    _distinctWrong(_dictationBank.map((e) => e.word).toList(), d.word, i + 7),
    'Tam cümle: "$fullSentence" — Eksik kelime "${d.word}" (${d.trClue}).',
    activity: QuestionActivity(
      kind: ActivityKind.dictation,
      title: 'İngilizce Sesli Dikte',
      language: lang,
      transcript: fullSentence,
    ),
  );
}

// ---------------------------------------------------------------------------
// 5. İNGİLİZCE TELAFFUZ, VURGU & FONETİK KONUŞMA STÜDYOSU (600 soru)
// ---------------------------------------------------------------------------
typedef _SilentSpec = ({String word, String silent, String ipa, String tr});
const _silentWords = <_SilentSpec>[
  (word: 'knight', silent: 'k harfi', ipa: '/naɪt/', tr: 'şövalye'),
  (word: 'island', silent: 's harfi', ipa: '/ˈaɪ.lənd/', tr: 'ada'),
  (word: 'honest', silent: 'h harfi', ipa: '/ˈɒn.ɪst/', tr: 'dürüst'),
  (word: 'receipt', silent: 'p harfi', ipa: '/rɪˈsiːt/', tr: 'makbuz'),
  (word: 'castle', silent: 't harfi', ipa: '/ˈkɑː.səl/', tr: 'kale'),
  (word: 'debt', silent: 'b harfi', ipa: '/det/', tr: 'borç'),
  (word: 'subtle', silent: 'b harfi', ipa: '/ˈsʌt.əl/', tr: 'ince / sezilmesi güç'),
  (word: 'plumber', silent: 'b harfi', ipa: '/ˈplʌm.ər/', tr: 'tesisatçı'),
  (word: 'psychology', silent: 'p harfi', ipa: '/saɪˈkɒl.ə.dʒi/', tr: 'psikoloji'),
  (word: 'Wednesday', silent: 'ilk d harfi', ipa: '/ˈwenz.deɪ/', tr: 'Çarşamba'),
  (word: 'autumn', silent: 'n harfi', ipa: '/ˈɔː.təm/', tr: 'sonbahar'),
  (word: 'column', silent: 'n harfi', ipa: '/ˈkɒl.əm/', tr: 'sütun'),
  (word: 'listen', silent: 't harfi', ipa: '/ˈlɪs.ən/', tr: 'dinlemek'),
  (word: 'wrist', silent: 'w harfi', ipa: '/rɪst/', tr: 'bilek'),
  (word: 'answer', silent: 'w harfi', ipa: '/ˈɑːn.sər/', tr: 'yanıt'),
  (word: 'knife', silent: 'k harfi', ipa: '/naɪf/', tr: 'bıçak'),
  (word: 'climb', silent: 'b harfi', ipa: '/klaɪm/', tr: 'tırmanmak'),
  (word: 'hour', silent: 'h harfi', ipa: '/aʊər/', tr: 'saat'),
  (word: 'salmon', silent: 'l harfi', ipa: '/ˈsæm.ən/', tr: 'somon'),
  (word: 'aisle', silent: 's harfi', ipa: '/aɪl/', tr: 'koridor'),
];

typedef _MinimalPair = ({String phrase, String ipa, String meaning, List<String> wrong});
const _minimalPairs = <_MinimalPair>[
  (phrase: 'a big ship', ipa: '/ʃɪp/ (kısa i)', meaning: 'büyük bir gemi', wrong: ['büyük bir koyun (sheep)', 'büyük bir dükkan (shop)', 'büyük bir şekil (shape)']),
  (phrase: 'a white sheep', ipa: '/ʃiːp/ (uzun i:)', meaning: 'beyaz bir koyun', wrong: ['beyaz bir gemi (ship)', 'beyaz bir çarşaf (sheet)', 'beyaz bir raf (shelf)']),
  (phrase: 'leave early', ipa: '/liːv/ (uzun i:)', meaning: 'erken ayrılmak', wrong: ['erken yaşamak (live)', 'erken sevmek (love)', 'erken kaldırmak (lift)']),
  (phrase: 'live nearby', ipa: '/lɪv/ (kısa i)', meaning: 'yakında yaşamak', wrong: ['yakında ayrılmak (leave)', 'yakında gülmek (laugh)', 'yakında öğrenmek (learn)']),
  (phrase: 'walk to work', ipa: '/wɔːk/ – /wɜːrk/', meaning: 'işe yürümek', wrong: ['uyanıp beklemek', 'duvarı boyamak', 'saate bakmak']),
  (phrase: 'hot soup', ipa: '/suːp/ (u:)', meaning: 'sıcak çorba', wrong: ['sıcak sabun (soap)', 'sıcak mağaza (shop)', 'sıcak ip (rope)']),
  (phrase: 'fresh soap', ipa: '/səʊp/ (oʊ)', meaning: 'taze sabun', wrong: ['taze çorba (soup)', 'taze çorap (sock)', 'taze salata (salad)']),
  (phrase: 'bad weather', ipa: '/bæd/ (açık e-a)', meaning: 'kötü hava', wrong: ['yatak odası (bed)', 'kuş sesi (bird)', 'ekmek kokusu (bread)']),
  (phrase: 'soft bed', ipa: '/bed/ (kısa e)', meaning: 'yumuşak yatak', wrong: ['yumuşak yarasa (bat)', 'yumuşak çanta (bag)', 'yumuşak kötü (bad)']),
  (phrase: 'full glass', ipa: '/fʊl/ (kısa u)', meaning: 'dolu bardak', wrong: ['düşmüş bardak (fall)', 'aptal bardak (fool)', 'soğuk bardak (cool)']),
  (phrase: 'desert sand', ipa: '/ˈdez.ət/ (ilk hece vurgulu)', meaning: 'çöl kumu', wrong: ['tatlı tabağı (dessert)', 'akşam yemeği (dinner)', 'derin deniz (deep)']),
  (phrase: 'sweet dessert', ipa: '/dɪˈzɜːt/ (ikinci hece vurgulu)', meaning: 'tatlı (yemek sonrası)', wrong: ['kuru çöl (desert)', 'sert rüzgar (breeze)', 'tuzlu çerez (snack)']),
  (phrase: 'quiet library', ipa: '/ˈkwaɪ.ət/ (iki hece)', meaning: 'sessiz kütüphane', wrong: ['oldukça kütüphane (quite)', 'hızlı kütüphane (quick)', 'kare kütüphane (square)']),
  (phrase: 'three trees', ipa: '/θriː triːz/ (th + t)', meaning: 'üç ağaç', wrong: ['üç tren (trains)', 'üç tepsi (trays)', 'özgür yapraklar (free)']),
  (phrase: 'think carefully', ipa: '/θɪŋk/ (peltek th)', meaning: 'dikkatle düşünmek', wrong: ['dikkatle batmak (sink)', 'dikkatle içmek (drink)', 'dikkatle teşekkür etmek (thank)']),
];

typedef _StressWord = ({String word, String stressed, String ipa, String tr});
const _stressWords = <_StressWord>[
  (word: 'photography', stressed: '2. hece (pho-TO-gra-phy)', ipa: '/fəˈtɒɡ.rə.fi/', tr: 'fotoğrafçılık'),
  (word: 'economy', stressed: '2. hece (e-CO-no-my)', ipa: '/ɪˈkɒn.ə.mi/', tr: 'ekonomi'),
  (word: 'information', stressed: '3. hece (in-for-MA-tion)', ipa: '/ˌɪn.fəˈmeɪ.ʃən/', tr: 'bilgi'),
  (word: 'development', stressed: '2. hece (de-VE-lop-ment)', ipa: '/dɪˈvel.əp.mənt/', tr: 'gelişim'),
  (word: 'university', stressed: '3. hece (u-ni-VER-si-ty)', ipa: '/ˌjuː.nɪˈvɜː.sə.ti/', tr: 'üniversite'),
  (word: 'technology', stressed: '2. hece (tech-NO-lo-gy)', ipa: '/tekˈnɒl.ə.dʒi/', tr: 'teknoloji'),
  (word: 'engineer', stressed: '3. hece (en-gi-NEER)', ipa: '/ˌen.dʒɪˈnɪər/', tr: 'mühendis'),
  (word: 'comfortable', stressed: '1. hece (COM-for-ta-ble)', ipa: '/ˈkʌm.fə.tə.bəl/', tr: 'rahat'),
  (word: 'interesting', stressed: '1. hece (IN-ter-es-ting)', ipa: '/ˈɪn.trəs.tɪŋ/', tr: 'ilginç'),
  (word: 'hotel', stressed: '2. hece (ho-TEL)', ipa: '/həʊˈtel/', tr: 'otel'),
  (word: 'banana', stressed: '2. hece (ba-NA-na)', ipa: '/bəˈnɑː.nə/', tr: 'muz'),
  (word: 'calendar', stressed: '1. hece (CA-len-dar)', ipa: '/ˈkæl.ən.dər/', tr: 'takvim'),
  (word: 'important', stressed: '2. hece (im-POR-tant)', ipa: '/ɪmˈpɔː.tənt/', tr: 'önemli'),
  (word: 'dictionary', stressed: '1. hece (DIC-tion-a-ry)', ipa: '/ˈdɪk.ʃən.ər.i/', tr: 'sözlük'),
  (word: 'geography', stressed: '2. hece (ge-OG-ra-phy)', ipa: '/dʒiˈɒɡ.rə.fi/', tr: 'coğrafya'),
];

typedef _EndingSpec = ({String words, String sound, String rule});
const _edEndings = <_EndingSpec>[
  (words: 'worked, watched, laughed', sound: '/t/ sesi', rule: 'Ötümsüz ünsüzlerden (k, ch, f, p, s, sh) sonra -ed eki /t/ okunur.'),
  (words: 'played, cleaned, opened', sound: '/d/ sesi', rule: 'Ünlüler ve ötümlü ünsüzlerden (l, n, r, v, g) sonra -ed eki /d/ okunur.'),
  (words: 'wanted, needed, decided', sound: '/ɪd/ hecesi', rule: 't veya d sesiyle biten fiillerde -ed eki ayrı bir /ɪd/ hecesi olarak okunur.'),
  (words: 'stopped, asked, washed', sound: '/t/ sesi', rule: 'p, k, sh gibi ötümsüz seslerden sonra -ed eki /t/ olarak telaffuz edilir.'),
  (words: 'called, lived, traveled', sound: '/d/ sesi', rule: 'l ve v ötümlü sesler olduğundan -ed eki /d/ sesiyle biter.'),
  (words: 'started, visited, waited', sound: '/ɪd/ hecesi', rule: 'Fiil /t/ ile bittiği için -ed eki /ɪd/ biçiminde ekstra hece oluşturur.'),
  (words: 'books, maps, cups', sound: '/s/ sesi', rule: 'Ötümsüz k, p, t, f ünsüzlerinden sonra çoğul -s eki /s/ okunur.'),
  (words: 'dogs, bags, pens', sound: '/z/ sesi', rule: 'Ötümlü g, n, d, b seslerinden sonra çoğul -s eki /z/ olarak okunur.'),
  (words: 'boxes, watches, buses', sound: '/ɪz/ hecesi', rule: 's, x, ch, sh, z ile biten sözcüklerde -es eki /ɪz/ hecesiyle söylenir.'),
  (words: 'helped, cooked, danced', sound: '/t/ sesi', rule: 'Ötümsüz ünsüzlerden sonra gelen -ed eki /t/ sesi verir.'),
];

AdvancedItem _buildPronunciation(int i) {
  final kind = i % 4; // 4 × 150 = 600
  final k = i ~/ 4;
  final lang = _accent(i);

  if (kind == 0) {
    final s = _silentWords[k % _silentWords.length];
    final wrong = _distinctWrong(
      ['k harfi', 's harfi', 'h harfi', 'p harfi', 't harfi', 'b harfi', 'n harfi', 'w harfi', 'l harfi', 'ilk d harfi'],
      s.silent,
      i + 5,
    );
    return AdvancedItem(
      'İngilizce "${s.word}" (${s.tr}) sözcüğünü dinleyip telaffuz edin. Bu sözcükte OKUNMAYAN (sessiz) harf hangisidir?',
      s.silent,
      wrong,
      '"${s.word}" sözcüğü ${s.ipa} şeklinde okunur; ${s.silent} telaffuz edilmez.',
      activity: QuestionActivity(
        kind: ActivityKind.pronunciation,
        title: 'Sessiz Harf & Telaffuz',
        language: lang,
        transcript: s.word,
        items: ['Fonetik: ${s.ipa} · Anlam: ${s.tr}'],
      ),
    );
  } else if (kind == 1) {
    final m = _minimalPairs[k % _minimalPairs.length];
    return AdvancedItem(
      'İngilizce ifadeyi dinleyip yüksek sesle tekrar edin. Duyduğunuz ifadenin doğru Türkçe anlamı hangisidir?',
      m.meaning,
      m.wrong,
      '"${m.phrase}" (${m.ipa}) ifadesi "${m.meaning}" anlamına gelir.',
      activity: QuestionActivity(
        kind: ActivityKind.pronunciation,
        title: 'Minimal Çift Telaffuzu',
        language: lang,
        transcript: m.phrase,
        items: ['Fonetik ipucu: ${m.ipa}'],
      ),
    );
  } else if (kind == 2) {
    final w = _stressWords[k % _stressWords.length];
    final correctOpt = w.stressed.substring(0, 7);
    final wrong = _distinctWrong(
      ['1. hece', '2. hece', '3. hece', '4. hece'],
      correctOpt,
      i + 13,
    );
    return AdvancedItem(
      'İngilizce "${w.word}" (${w.tr}) sözcüğünü dinleyip söyleyin. Ana vurgu (stress) hangi hecededir?',
      correctOpt,
      wrong,
      '"${w.word}" (${w.ipa}) sözcüğünde ana vurgu ${w.stressed} konumundadır.',
      activity: QuestionActivity(
        kind: ActivityKind.pronunciation,
        title: 'İngilizce Hece Vurgusu',
        language: lang,
        transcript: w.word,
        items: ['Fonetik: ${w.ipa} · ${w.tr}'],
      ),
    );
  } else {
    final e = _edEndings[k % _edEndings.length];
    final wrong = _distinctWrong(
      ['/t/ sesi', '/d/ sesi', '/ɪd/ hecesi', '/s/ sesi', '/z/ sesi', '/ɪz/ hecesi'],
      e.sound,
      i + 19,
    );
    return AdvancedItem(
      'Örnek sözcükleri dinleyip sırayla telaffuz edin. Bu gruptaki son ekler hangi sesle biter?',
      e.sound,
      wrong,
      e.rule,
      activity: QuestionActivity(
        kind: ActivityKind.pronunciation,
        title: 'İngilizce Ek Sesletimi',
        language: lang,
        transcript: e.words,
        items: ['Hedef ek sesi: ${e.sound}'],
      ),
    );
  }
}

final List<AdvancedFamily> audioEnglish3kFamilies = [
  AdvancedFamily(
    key: 'st10k_en_listen_scene',
    title: 'Sesli İngilizce · Günlük Diyalog & Anons',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 800,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.listening,
    bloom: BloomLevel.anlama,
    sourceLabel: 'Bilgili 3.20 · Sesli İngilizce Stüdyosu',
    build: _buildListeningScene,
  ),
  AdvancedFamily(
    key: 'st10k_en_listen_vocab',
    title: 'Sesli İngilizce · Kelime, Deyim & Phrasal Verb',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 600,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.listening,
    bloom: BloomLevel.anlama,
    sourceLabel: 'Bilgili 3.20 · Sesli İngilizce Stüdyosu',
    build: _buildListeningVocab,
  ),
  AdvancedFamily(
    key: 'st10k_en_listen_numbers',
    title: 'Sesli İngilizce · Sayı, Fiyat, Saat & Tarih (IELTS)',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 400,
    difficulty: Difficulty.hard,
    activityKind: ActivityKind.listening,
    bloom: BloomLevel.analiz,
    sourceLabel: 'Bilgili 3.20 · Sesli İngilizce Stüdyosu',
    build: _buildListeningNumbers,
  ),
  AdvancedFamily(
    key: 'st10k_en_dictation',
    title: 'Sesli İngilizce · Dikte & Eksik Kelime Yazma',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 600,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.dictation,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.20 · Sesli İngilizce Stüdyosu',
    build: _buildDictation,
  ),
  AdvancedFamily(
    key: 'st10k_en_pronunciation',
    title: 'Sesli İngilizce · Telaffuz, Vurgu & Fonetik',
    topic: Topic.language,
    level: StudyLevel.lise,
    count: 600,
    difficulty: Difficulty.medium,
    activityKind: ActivityKind.pronunciation,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.20 · Sesli İngilizce Stüdyosu',
    build: _buildPronunciation,
  ),
];
