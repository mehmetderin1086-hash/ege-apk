// Alan bilgisi, çözümleme, atölye ve saha uygulamaları.
import 'common.dart';

typedef _Pair = (String, String);
typedef _Maker = AdvancedItem Function(int, int, int);
const _hs = StudyLevel.lise, _un = StudyLevel.universite;
const _apply = BloomLevel.uygulama, _analyze = BloomLevel.analiz;
const _chart = VisualKind.barChart,
    _tableKind = VisualKind.table,
    _diag = VisualKind.diagram;

AdvancedFamily _domain(
  String key,
  String title,
  Topic topic,
  StudyLevel level,
  BloomLevel bloom,
  VisualKind? kind,
  _Maker make, {
  bool typed = true,
  CreationTask Function(AdvancedItem, int)? creation,
  Difficulty difficulty = Difficulty.medium,
}) => AdvancedFamily(
  key: 'arts_$key',
  title: title,
  topic: topic,
  level: level,
  count: 3000,
  difficulty: difficulty,
  lesson: title,
  visualKind: kind,
  bloom: bloom,
  shortAnswer: typed && creation == null,
  creation: creation,
  build: (i) => make(i % 20, i ~/ 20 % 15, i ~/ 300),
);

String _frac(int n, int d) {
  if (d < 0) return _frac(-n, -d);
  final g = n.gcd(d);
  return g == d ? '${n ~/ g}' : '${n ~/ g}/${d ~/ g}';
}

AdvancedItem _item(
  String p,
  String ans,
  List<String> choices,
  String e, [
  QuestionVisual? visual,
]) {
  final wrong = choices.where((s) => s != ans).toSet().take(3).toList();
  if (wrong.length != 3) throw StateError('Eksik seçenek: $p');
  return AdvancedItem(p, ans, wrong, e, visual: visual);
}

AdvancedItem _n(
  String p,
  int a,
  List<int> wrong,
  String e, [
  QuestionVisual? visual,
]) => _item(
  p,
  '$a',
  [...wrong, a + 1, a - 1, a + 2].map((x) => '$x').toList(),
  e,
  visual,
);
AdvancedItem _r(
  String p,
  int n,
  int d,
  List<(int, int)> wrong,
  String e, [
  QuestionVisual? visual,
]) => _item(
  p,
  _frac(n, d),
  [
    ...wrong,
    (n + 1, d),
    (n + 2, d),
    (n + 3, d),
  ].where((t) => t.$2 != 0).map((t) => _frac(t.$1, t.$2)).toList(),
  e,
  visual,
);

QuestionVisual _table(
  String title,
  List<String> columns,
  List<List<Object>> data,
) => QuestionVisual(
  kind: _tableKind,
  title: title,
  summary: '',
  columns: columns,
  rows: [
    for (final row in data) [for (final v in row) '$v'],
  ],
);
QuestionVisual _bars(
  String title,
  List<String> labels,
  List<int> values,
  String unit,
) => QuestionVisual(
  kind: _chart,
  title: title,
  summary: '',
  labels: labels,
  values: [for (final v in values) v.toDouble()],
  unit: unit,
);
DiagramElement _line(
  double x,
  double y,
  double u,
  double v, {
  String color = 'mint',
}) => DiagramElement(shape: 'line', x: x, y: y, endX: u, endY: v, color: color);
DiagramElement _lab(double x, double y, String s) =>
    DiagramElement(shape: 'text', x: x, y: y, label: s);
QuestionVisual _drawing(String title, List<DiagramElement> el) =>
    QuestionVisual(
      kind: _diag,
      title: title,
      summary: 'Şema ölçekli değildir; belirtilen ölçüleri kullanınız.',
      elements: el,
    );

int _choose(int n, int k) {
  var out = 1;
  for (var j = 1; j <= k; j++) {
    out = out * (n - j + 1) ~/ j;
  }
  return out;
}

// Combinatorial unranking selects a different set of four source concepts
// for each case. Reordering the same question never increases the count.
List<int> _subset(int index, int n) {
  final set = <int>[];
  var start = 0;
  for (var left = 4; left > 0; left--) {
    for (var j = start; j <= n - left; j++) {
      final block = _choose(n - j - 1, left - 1);
      if (index < block) {
        set.add(j);
        start = j + 1;
        break;
      }
      index -= block;
    }
  }
  return set;
}

const _arrangements = [
  [2, 0, 3, 1],
  [1, 3, 0, 2],
  [3, 2, 0, 1],
  [1, 0, 3, 2],
  [2, 3, 1, 0],
  [3, 0, 1, 2],
];
AdvancedFamily _activity(
  String key,
  String title,
  Topic topic,
  StudyLevel level,
  ActivityKind kind,
  BloomLevel bloom,
  List<_Pair> sources,
  String instruction,
) => AdvancedFamily(
  key: 'arts_$key',
  title: title,
  topic: topic,
  level: level,
  difficulty: Difficulty.medium,
  lesson: title,
  count: 3000,
  bloom: bloom,
  activityKind: kind,
  shortAnswer: false,
  build: (i) {
    final subset = _subset(i, sources.length);
    final order = _arrangements[(i + i ~/ 9) % _arrangements.length];
    final source = [for (final j in subset) sources[j]];
    final labels = [for (final j in order) source[j].$1];
    late QuestionActivity act;
    if (kind == ActivityKind.ordering) {
      act = QuestionActivity(
        kind: kind,
        title: title,
        items: labels,
        solution: [for (var j = 0; j < 4; j++) order.indexOf(j)],
      );
    } else {
      final rightOrder = [
        for (final j in _arrangements[(i ~/ 7) % 6]) order[j],
      ];
      act = QuestionActivity(
        kind: kind,
        title: title,
        left: labels,
        right: [for (final k in rightOrder) source[k].$2],
        solution: [for (final k in order) rightOrder.indexOf(k)],
      );
    }
    final sol = act.solution;
    String spell(List<int> pick) => act.describeSequence(pick);
    return AdvancedItem(
      '$instruction Seçki: ${labels.join(', ')}.',
      spell(sol),
      [
        spell([sol[1], sol[0], sol[2], sol[3]]),
        spell([sol[0], sol[2], sol[1], sol[3]]),
        spell([sol[3], sol[1], sol[2], sol[0]]),
      ],
      source.map((t) => '${t.$1} — ${t.$2}').join(' · '),
      activity: act,
    );
  },
);

const _musicTerms = <_Pair>[
  ('Legato', 'Sesleri birbirine bağlı çalma'),
  ('Staccato', 'Sesleri kısa ve ayrık çalma'),
  ('Crescendo', 'Ses şiddetini giderek artırma'),
  ('Diminuendo', 'Ses şiddetini giderek azaltma'),
  ('Accelerando', 'Tempoyu giderek hızlandırma'),
  ('Ritardando', 'Tempoyu giderek yavaşlatma'),
  ('Fermata', 'Nota veya sus süresini yorumla uzatma'),
  ('Pizzicato', 'Yaylı çalgının telini parmakla çekme'),
  ('Arco', 'Yaylı çalgıda yayı kullanma'),
  (
    'Tremolo',
    'Bir sesi çok hızlı yineleme veya iki ses arasında hızla gidip gelme',
  ),
  ('Glissando', 'Ses yüksekliğini kaydırarak başka bir sese geçme'),
  ('Ostinato', 'Kısa bir müzik kalıbını ısrarla yineleme'),
  ('Senkop', 'Beklenen güçlü vurguyu zayıf zamana kaydırma'),
  ('Pedal sesi', 'Armoniler değişirken bir sesi sürdürme'),
  ('Kanon', 'Aynı ezgiyi farklı zamanlarda giren seslerle taklit etme'),
  ('Arpej', 'Akor seslerini art arda duyurma'),
  ('Portato', 'Bağ içinde sesleri hafifçe ayırarak çalma'),
  ('Rubato', 'Müzikal ifade için tempoyu esnek kullanma'),
];
const _intervals = <_Pair>[
  ('Tam sesteş', '0 yarım ses'),
  ('Küçük ikili', '1 yarım ses'),
  ('Büyük ikili', '2 yarım ses'),
  ('Küçük üçlü', '3 yarım ses'),
  ('Büyük üçlü', '4 yarım ses'),
  ('Tam dörtlü', '5 yarım ses'),
  ('Artmış dörtlü', '6 yarım ses'),
  ('Tam beşli', '7 yarım ses'),
  ('Küçük altılı', '8 yarım ses'),
  ('Büyük altılı', '9 yarım ses'),
  ('Küçük yedili', '10 yarım ses'),
  ('Büyük yedili', '11 yarım ses'),
  ('Tam sekizli', '12 yarım ses'),
  ('Küçük dokuzlu', '13 yarım ses'),
  ('Büyük dokuzlu', '14 yarım ses'),
  ('Küçük onlu', '15 yarım ses'),
  ('Büyük onlu', '16 yarım ses'),
  ('Tam on birli', '17 yarım ses'),
];
const _printTerms = <_Pair>[
  ('Linol baskı', 'Oyulmamış linolyum yüzeylerinden baskı alma'),
  ('Ağaç baskı', 'Yüksek kalan ahşap yüzeylerden baskı alma'),
  ('Litografi', 'Yağ ve suyun ayrılmasına dayalı taş baskı'),
  ('Serigrafi', 'Mürekkebi açık gözeneklerden rakleyle geçirme'),
  ('Kuru kazı', 'Metal kalıba doğrudan iğneyle çizik açma'),
  ('Asit oymabaskı', 'Koruyucu tabakası açılmış metali asitle oyma'),
  ('Akuatinta', 'Reçine taneli kalıpla asitte ton alanları oluşturma'),
  ('Mezzotint', 'Pürüzlendirilmiş kalıpta açık tonları düzelterek elde etme'),
  ('Monotip', 'Boyanmış düz bir yüzeyden tekil bir baskı aktarma'),
  ('Kolagrafi', 'Yapıştırılmış dokulardan oluşan kalıpla baskı alma'),
  ('Kör kabartma', 'Mürekkep kullanmadan kâğıdı kabartma'),
  (
    'Çin kolajı (chine-collé)',
    'İnce kâğıdı baskı sırasında taşıyıcıya yapıştırma',
  ),
  ('Kayıt işareti', 'Renk kalıplarını üst üste hizalamaya yardım etme'),
  ('Prova baskısı', 'Baskı öncesi sonucu kontrol etme'),
  ('Tram', 'Sürekli tonları nokta örüntüsüyle temsil etme'),
  ('Degrade baskı', 'Tek baskıda iki renk arasında kademeli geçiş oluşturma'),
  ('Taşma payı', 'Kesim çizgisinin dışına taşan baskı alanı bırakma'),
  ('Edisyon', 'Bir kalıptan üretilen numaralandırılmış baskı dizisi'),
];
const _filmDates = <_Pair>[
  ('Aya Seyahat', '1902'),
  ('Hoşgörüsüzlük (Intolerance)', '1916'),
  ('Dr. Caligari’nin Muayenehanesi', '1920'),
  ('Metropolis', '1927'),
  ('Şehir Işıkları', '1931'),
  ('Oz Büyücüsü (Victor Fleming)', '1939'),
  ('Yurttaş Kane', '1941'),
  ('Bisiklet Hırsızları', '1948'),
  ('Yağmur Altında', '1952'),
  ('Yedi Samuray', '1954'),
  ('400 Darbe', '1959'),
  ('Sapık (Alfred Hitchcock)', '1960'),
  ('2001: Bir Uzay Destanı', '1968'),
  ('Baba (The Godfather)', '1972'),
  ('Jaws', '1975'),
  ('Blade Runner', '1982'),
  ('Geleceğe Dönüş', '1985'),
  ('Jurassic Park', '1993'),
];
const _sportTerms = <_Pair>[
  ('Fosbury flop', 'Yüksek atlamada çıtayı sırt üstü geçme'),
  ('Estafet', 'Bayrağı el değiştirerek takım hâlinde koşma'),
  ('Negatif split', 'Yarışın ikinci yarısını ilkinden hızlı tamamlama'),
  ('Drafting', 'Öndeki sporcunun oluşturduğu akış izinden yararlanma'),
  ('Kadans', 'Bisiklette dakikadaki pedal devri'),
  ('Catch', 'Kürekte palanın suya girdiği evre'),
  ('Tumble turn', 'Yüzmede duvar önünde taklayla yön değiştirme'),
  ('Sculling', 'Yüzmede elin küçük süpürme hareketleriyle suyu kavraması'),
  ('Pick and roll', 'Basketbolda perdeleme sonrası potaya devrilme'),
  ('Box out', 'Basketbolda ribaunt için rakibi çemberden uzakta tutma'),
  ('Libero', 'Voleybolda arka alan savunmasında uzman oyuncu'),
  ('Blok', 'Voleybolda rakip hücumunu file üzerinde karşılama'),
  ('Ruck', 'Ragbide yerdeki topun üzerinde ayakta oluşan mücadele'),
  ('Ippon', 'Judoda karşılaşmayı sona erdiren tam puan'),
  (
    'Let servisi',
    'Teniste fileye değerek doğru kutuya düşen ve tekrarlanan servis',
  ),
  ('Hatalı çıkış', 'Koşuda geçerli başlangıç işaretinden önce çıkma'),
  ('Hat-trick', 'Futbolda bir oyuncunun bir maçta üç gol atması'),
  ('Break point', 'Teniste karşılayanın oyunu kazanabileceği puan'),
];
const _hostDates = <_Pair>[
  ('Atina', '1896'),
  ('Paris', '1900'),
  ('St. Louis', '1904'),
  ('Londra', '1908'),
  ('Stockholm', '1912'),
  ('Anvers', '1920'),
  ('Amsterdam', '1928'),
  ('Los Angeles', '1932'),
  ('Berlin', '1936'),
  ('Helsinki', '1952'),
  ('Melbourne', '1956'),
  ('Roma', '1960'),
  ('Tokyo', '1964'),
  ('Meksiko', '1968'),
  ('Münih', '1972'),
  ('Montreal', '1976'),
  ('Moskova', '1980'),
  ('Seul', '1988'),
];

final renewedArtsFamilies = <AdvancedFamily>[
  _activity(
    'music_terms',
    'İcra ve besteleme terimleri',
    Topic.music,
    _hs,
    ActivityKind.matching,
    BloomLevel.hatirlama,
    _musicTerms,
    'Her müzik terimini doğru icra ya da besteleme açıklamasıyla eşleştirin.',
  ),
  _activity(
    'interval_order',
    'Aralıkları karşılaştırma',
    Topic.music,
    _hs,
    ActivityKind.ordering,
    BloomLevel.anlama,
    _intervals,
    'Eşit aralıklı on iki ses sisteminde aralıkları dardan genişe sıralayın.',
  ),
  _domain(
    'ensemble',
    'Topluluk provasında tempo ve ölçü',
    Topic.music,
    _hs,
    _apply,
    _tableKind,
    (a, b, c) {
      final beats = 2 + c % 4,
          bars = a + 4,
          tempo = (b + 9) * 4,
          repeat = c ~/ 4 + 1;
      final tab = _table(
        'Prova planı',
        ['Ölçü', 'Tempo', 'Tekrar'],
        [
          ['$beats/4', '♩ = $tempo', '$repeat geçiş'],
        ],
      );
      final n = 60 * beats * bars * repeat;
      return _r(
        'Tablodaki sabit tempoyla $bars ölçülük pasaj belirtilen geçiş sayısı kadar çalınıyor. Aralıksız prova kaç saniye sürer?',
        n,
        tempo,
        [
          (60 * bars * repeat, tempo),
          (60 * bars * beats, tempo),
          (n, tempo * 2),
        ],
        'Her ölçüde $beats dörtlük vuruş, her geçişte $bars ölçü vardır. Toplam ${beats * bars * repeat} vuruş × 60/$tempo = ${_frac(n, tempo)} saniye.',
        tab,
      );
    },
  ),
  _domain('pulses', 'Birleşen ritmik döngüler', Topic.music, _un, _analyze, null, (
    a,
    b,
    c,
  ) {
    final p = a + 3, q = p + b + 1, seconds = c + 1, cycle = p * q ~/ p.gcd(q);
    return _r(
      'Bir vurmalı çalgı her $p, diğeri her $q eşit alt bölümde vurgu yapıyor. Başlangıçta vurgular çakışıyor. $seconds saniyede 12 alt bölüm geçiyorsa iki vurgunun ilk kez yeniden çakışmasına kaç saniye vardır?',
      cycle * seconds,
      12,
      [(p * q * seconds, 12), ((p + q) * seconds, 12), (cycle, 1)],
      'Eş vurguların arası EKOK($p, $q) = $cycle alt bölümdür. Bir alt bölüm $seconds/12 saniye sürer. Sonuç ${_frac(cycle * seconds, 12)} saniyedir.',
    );
  }),
  _domain(
    'strings',
    'Tel üzerinde etkin boy ve perde',
    Topic.music,
    _un,
    _apply,
    _diag,
    (a, b, c) {
      final length = a + 40,
          stopped = b + 20,
          freq = (c + 10) * 15,
          n = length * freq;
      final v = _drawing('Telin titreşen bölümü', [
        _line(13, 49, 88, 49),
        _line(13, 37, 13, 62),
        _line(88, 37, 88, 62),
        _line(42, 38, 42, 63, color: 'gold'),
        _lab(50, 19, 'Açık tel: $length cm'),
        _lab(65, 76, 'Titreşen: $stopped cm'),
      ]);
      return _r(
        'Açık telin temel frekansı $freq Hz. Şekildeki gibi perdeye basıldığında gerilim ve doğrusal yoğunluk değişmiyor. Yeni temel frekans kaç Hz olur?',
        n,
        stopped,
        [(stopped * freq, length), (n, length - stopped), (freq, 2)],
        'Aynı telde temel frekans etkin uzunlukla ters orantılıdır. Yeni frekans $freq × $length/$stopped = ${_frac(n, stopped)} Hz.',
        v,
      );
    },
  ),
  _domain(
    'tape',
    'Analog bant hızında süre ve perde',
    Topic.music,
    _hs,
    _analyze,
    _tableKind,
    (a, b, c) {
      final length = a + 8, record = b + 4, play = (c + 1) * 3;
      final v = _table(
        'Bant kaydı',
        ['Özellik', 'Değer'],
        [
          ['Kaydın süresi', '$length sn'],
          ['Kayıt hızı', '$record cm/sn'],
          ['Oynatma hızı', '$play cm/sn'],
        ],
      );
      return _r(
        'Kesilmemiş bant tabloda belirtilen hızla tekrar oynatılıyor. Kaydın dinlenme süresi kaç saniye olur?',
        length * record,
        play,
        [(length * play, record), (length, 1), (record * play, length)],
        'Kayıt boyunca $length × $record = ${length * record} cm bant kullanılır. Aynı uzunluğu $play cm/sn hızla oynatmak ${_frac(length * record, play)} saniye sürer.',
        v,
      );
    },
  ),
  _domain(
    'pcm',
    'Sıkıştırılmamış PCM ses arşivi',
    Topic.music,
    _un,
    _apply,
    _tableKind,
    (a, b, c) {
      final rate = (a + 22) * 1000,
          sec = b + 12,
          bits = [8, 16, 24, 32, 40][c % 5],
          channels = c ~/ 5 + 1;
      final v = _table(
        'Ham PCM kayıt',
        ['Örnekleme', 'Örnek boyu', 'Kanal'],
        [
          ['$rate Hz', '$bits bit', channels],
        ],
      );
      final bytes = rate * sec * (bits ~/ 8) * channels;
      return _n(
        'Tablodaki sıkıştırılmamış PCM biçiminde $sec saniyelik bir kaydın yalnız ses verisi kaç bayt yer kaplar? Her örnek belirtilen bit sayısıyla paketlenir.',
        bytes,
        [bytes * 8, rate * sec, bytes ~/ 2],
        'Kanal başına ${rate * sec} örnek vardır. Her örnek ${bits ~/ 8} bayt, kanal sayısı $channels. Toplam $bytes bayttır.',
        v,
      );
    },
  ),
  _domain(
    'harmonic',
    'Kısmi sesler ve filtre seçimi',
    Topic.music,
    _un,
    BloomLevel.degerlendirme,
    _tableKind,
    (a, b, c) {
      final f = a + 55, first = b + 2, last = first + c + 2;
      final low = f * first, high = f * last;
      final v = _table(
        'Spektrumda korunacak bileşenler',
        ['Temel frekans', 'En düşük sıra', 'En yüksek sıra'],
        [
          ['$f Hz', first, last],
        ],
      );
      String band(int l, int h) => '$l–$h Hz';
      return _item(
        'Bir ideal bant geçiren filtre, tabloda belirtilen harmonikleri uçlar dâhil koruyacak. Kesim frekansları arasında sürekli bir bant seçilecekse hangi ayar gerekli tüm bileşenleri en dar bantla korur?',
        band(low, high),
        [band(low - f, high), band(low, high + f), band(low + f, high)],
        'n. harmonik n × $f Hz’dir. En düşük hedef $low, en yüksek hedef $high Hz olur. Uçlardan birini içeri almak bir hedefi kaybettirir; dışarı almak bandı gereksiz genişletir.',
        v,
      );
    },
    typed: false,
  ),
  _domain(
    'melodic_edit',
    'Bir ezgiyi hedef perdeye aktarma',
    Topic.music,
    _hs,
    _apply,
    _tableKind,
    (a, b, c) {
      final begin = a + 45, turn = b + 1, trans = c + 2;
      final v = _table(
        'İki nota, MIDI perde numarası',
        ['İlk nota', 'Son nota'],
        [
          [begin, begin + turn],
        ],
      );
      return _n(
        'Düzenlemeci ilk notayı ${begin + trans} numaralı MIDI perdesine taşırken ezginin aralığını koruyor. Aktarılan son notanın MIDI numarası kaç olur?',
        begin + turn + trans,
        [begin + turn - trans, begin + trans, begin + turn],
        'Başlangıç perdesi $trans yarım ses yükselmiştir. İkinci perdeye de $trans eklenir: ${begin + turn} + $trans = ${begin + turn + trans}.',
        v,
      );
    },
  ),
  _domain(
    'rhythm_design',
    'Ritmik yanıt cümlesi besteleme',
    Topic.music,
    _un,
    BloomLevel.yaratma,
    _tableKind,
    (a, b, c) {
      final pulses = 32 + a,
          first = b + 3,
          silence = c + 1,
          remain = pulses - first - silence;
      final tab = _table(
        'Tekrarlanan ritmik çevrim',
        ['Öge', 'Onaltılık birim'],
        [
          ['Tüm çevrim', pulses],
          ['Çağrı bölümü', first],
          ['Son sus', silence],
        ],
      );
      return _n(
        'Tablodaki çevrim çağrı, yanıt ve son sustan oluşuyor. Yanıt bölümüne kaç onaltılık birim kalır?',
        remain,
        [pulses - first, pulses - silence, first + silence],
        'Çevrimi tamamlayan yanıtın uzunluğu $pulses − $first − $silence = $remain onaltılık birimdir.',
        tab,
      );
    },
    creation: (item, i) => CreationTask(
      'Verilen çağrıdan sonra çalınmak üzere bir ritmik yanıt besteleyin. Yanıt dört ayrı ataktan oluşsun. En az iki farklı süre kullanın ve vurguyu birinci ataktan başka bir atağa koyun. Her atağın süresini onaltılık birimle gösterin.',
      [
        'Dört atağı ve her birinin pozitif tam sayı süresini açıkça yazar.',
        'Dört süre, tabloda yanıt için kalan zamanı tam doldurur; en az iki süre farklıdır.',
        'Birinci ataktan başka bir vurguyu işaretler ve bu vurgunun çağrıya nasıl karşılık verdiğini açıklar.',
      ],
    ),
  ),
  _activity(
    'print_terms',
    'Baskı atölyesinde terimler',
    Topic.art,
    _un,
    ActivityKind.matching,
    BloomLevel.hatirlama,
    _printTerms,
    'Her baskıresim veya baskı üretimi terimini ayırt edici açıklamasıyla eşleştirin.',
  ),
  _activity(
    'film_order',
    'Sinema tarihinde ilk gösterim',
    Topic.cinema,
    _hs,
    ActivityKind.ordering,
    BloomLevel.hatirlama,
    _filmDates,
    'Filmleri ilk gösterim yıllarına göre eskiden yeniye sıralayın.',
  ),
  _domain(
    'camera',
    'İğne deliği kamerada görüntü boyu',
    Topic.art,
    _un,
    _apply,
    _diag,
    (a, b, c) {
      final subject = a + 20,
          gap = b + 20,
          chamber = c + 4,
          n = subject * chamber;
      final v = _drawing('İğne deliğinden geçen ışın', [
        _line(12, 20, 12, 69),
        _line(12, 20, 84, 75, color: 'gold'),
        _line(12, 69, 84, 44, color: 'gold'),
        _line(84, 35, 84, 82),
        _line(56, 28, 56, 50, color: 'blue'),
        _line(56, 57, 56, 72, color: 'blue'),
        _lab(20, 11, 'Nesne $subject cm'),
        _lab(48, 85, 'Nesne–delik $gap cm'),
        _lab(73, 23, 'Hazne $chamber cm'),
      ]);
      return _r(
        'Nesne düzlemi ile görüntü düzlemi paraleldir. Şekildeki iğne deliği kamerada görüntü boyunun büyüklüğü kaç santimetredir?',
        n,
        gap,
        [(subject * gap, chamber), (subject + chamber, 1), (n, gap + chamber)],
        'İğne deliğinde oluşan benzer üçgenlerde görüntü/nesne = hazne derinliği/nesne uzaklığıdır. Görüntü boyu $subject × $chamber/$gap = ${_frac(n, gap)} cm olur.',
        v,
      );
    },
  ),
  _domain(
    'crop',
    'Fotoğrafta oran koruyarak kırpma',
    Topic.art,
    _hs,
    _analyze,
    _diag,
    (a, b, c) {
      final rx = c + 3,
          ry = c + 2,
          base = (a + 40) * 10,
          height = ry * base,
          width = rx * base + b + 7;
      final v = _drawing('Kaynak fotoğraf', [
        const DiagramElement(
          shape: 'rectangle',
          x: 50,
          y: 47,
          width: 74,
          height: 56,
          color: 'blue',
        ),
        _lab(50, 10, '$width piksel'),
        _lab(50, 48, 'Yükseklik $height piksel'),
      ]);
      return _n(
        'Tasarımcı fotoğrafın yüksekliğini koruyup genişliği iki yandan kırpacak. Hedef en:boy oranı $rx:$ry ise toplam kaç piksel sütunu çıkarılmalıdır?',
        b + 7,
        [rx * base, width - height, 2 * (b + 7)],
        'Hedef genişlik $height × $rx/$ry = ${rx * base} pikseldir. İki yandan toplam $width − ${rx * base} = ${b + 7} sütun çıkarılır.',
        v,
      );
    },
  ),
  _domain(
    'film_edit',
    'Kurguda kare ve süre',
    Topic.cinema,
    _hs,
    _apply,
    _tableKind,
    (a, b, c) {
      final s1 = a + 4, s2 = b + 5, overlap = c + 2, fps = 24;
      final tab = _table(
        'Kurgu çizelgesi',
        ['Plan A', 'Plan B', 'Bindirme'],
        [
          ['$s1 sn', '$s2 sn', '$overlap kare'],
        ],
      );
      final n = (s1 + s2) * fps - overlap;
      return _n(
        'Saniyede 24 karelik zaman çizelgesinde B planının ilk kareleri A planının sonuyla tabloda belirtilen süre kadar üst üste getirilir. Kurgunun toplam süresi kaç karedir?',
        n,
        [(s1 + s2) * fps, (s1 + s2) * fps + overlap, n - overlap],
        'İki klip tek başına ${(s1 + s2) * fps} kare sürer. Bindirilen $overlap kare zaman çizelgesinde iki kez sayılmaz. Toplam $n kare kalır.',
        tab,
      );
    },
  ),
  _domain(
    'poster',
    'Afişte asgari yazı kontrastı',
    Topic.art,
    _un,
    BloomLevel.degerlendirme,
    _tableKind,
    (a, b, c) {
      // Scaled relative luminance keeps WCAG contrast comparisons exact.
      final dark = a + 1, light = b + 66, limit = c + 2;
      final n = light + 5, d = dark + 5, pass = n >= d * limit;
      final v = _table(
        'Bağıl parlaklık (yüzde)',
        ['Yazı', 'Zemin', 'Hedef oran'],
        [
          ['%$dark', '%$light', '$limit:1'],
        ],
      );
      final decision = pass ? 'Karşılar' : 'Karşılamaz',
          inverse = pass ? 'Karşılamaz' : 'Karşılar';
      return _item(
        'Afiş için verilen tasarım hedefi kontrol ediliyor. 0–1 ölçeğinde kontrast oranı (açık ton + 0,05)/(koyu ton + 0,05) ile hesaplanıyor. Hedefi karşılama durumu ve gerekçe hangisidir?',
        '$decision · oran ${_frac(n, d)}:1',
        [
          '$inverse · oran ${_frac(n, d)}:1',
          '$decision · oran ${_frac(light, dark)}:1',
          '$inverse · oran ${_frac(light, dark)}:1',
        ],
        'Yüzde ölçeğinde her parlaklığa 5 eklenir. Oran $n/$d = ${_frac(n, d)}:1 olur. $limit:1 eşiğiyle karşılaştırıldığında sonuç: $decision.',
        v,
      );
    },
    typed: false,
  ),
  _domain(
    'press',
    'Dört renk baskıda mürekkep sınırı',
    Topic.art,
    _un,
    _apply,
    _tableKind,
    (a, b, c) {
      final cyan = a + 50,
          magenta = b + 54,
          yellow = c + 56,
          limit = 240,
          n = limit - cyan - magenta - yellow;
      final tab = _table(
        'Bir baskı noktasındaki tram yüzdeleri',
        ['C', 'M', 'Y'],
        [
          ['%$cyan', '%$magenta', '%$yellow'],
        ],
      );
      return _n(
        'Matbaanın toplam mürekkep sınırı %$limit. C, M ve Y değerleri tablodaki gibi korunurken K kanalı en çok yüzde kaç olabilir?',
        n,
        [100 - n, 100, n - 10],
        'Toplam yüzdelik alan kapsamı C + M + Y + K’dir. Siyah kanala kalan üst sınır $limit − $cyan − $magenta − $yellow = %$n.',
        tab,
      );
    },
  ),
  _domain(
    'storyboard',
    'Çekim ölçeği için dekor maketi',
    Topic.cinema,
    _hs,
    _apply,
    null,
    (a, b, c) {
      final real = a + 8,
          ratio = b + 15,
          pedestal = c + 2,
          n = real * 100 + pedestal * ratio;
      return _r(
        'Bir film dekorunda $real m yüksekliğindeki cephenin 1:$ratio ölçekli maketi hazırlanıyor. Maket ayrıca $pedestal cm yüksekliğinde bir çekim kaidesine konuyor. Kaide tabanından cephe tepesine toplam yükseklik kaç cm olur?',
        n,
        ratio,
        [
          (real * 100, ratio),
          (100 * (real + pedestal), ratio),
          (real + pedestal, ratio),
        ],
        'Cephe maketinin boyu ${real * 100}/$ratio cm’dir. Kaide gerçek çekim düzenine ait olduğundan $pedestal cm doğrudan eklenir. Sonuç ${_frac(n, ratio)} cm.',
      );
    },
  ),
  _domain(
    'print_margin',
    'Sergi baskısında paspartu tasarımı',
    Topic.art,
    _hs,
    BloomLevel.yaratma,
    _tableKind,
    (a, b, c) {
      final page = a + 40, work = b + 16, gap = c + 1;
      final tab = _table(
        'Yatay yerleşim',
        ['Dış en', 'Görsel eni', 'Sol pay'],
        [
          ['$page cm', '$work cm', '$gap cm'],
        ],
      );
      return _n(
        'Görsel verilen sol payla bir sergi panosuna yerleştirilirse sağda kaç cm boşluk kalır?',
        page - work - gap,
        [page - work, page - gap, work - gap],
        'Yatay kesitte sol pay + görsel eni + sağ pay = dış en. Sağ pay $page − $work − $gap = ${page - work - gap} cm olur.',
        tab,
      );
    },
    creation: (item, i) => CreationTask(
      'Aynı pano ve görselle iki farklı yatay sergileme düzeni tasarlayın. Birinde görseli ortalayın, diğerinde sağ boşluğu sol boşluktan büyük tutun. Her iki düzenin kenar ölçülerini yazın ve odak etkilerini karşılaştırın.',
      [
        'İki tasarımda da kenar payları pozitif ve toplam en dış ölçüyle uyumludur.',
        'Bir düzende paylar eşit, diğerinde sağ pay daha büyüktür.',
        'Boş alanın görsel ağırlığa ve izleyicinin dikkatine etkisini kendi iki düzeniyle ilişkilendirir.',
      ],
    ),
  ),
  _domain(
    'contact_sheet',
    'Fotoğraf provasında yerleşim',
    Topic.art,
    _hs,
    _apply,
    _diag,
    (a, b, c) {
      final cell = a + 20,
          space = b + 1,
          n = c + 3,
          total = n * cell + (n - 1) * space;
      final v = _drawing('Yan yana yerleştirilecek kareler', [
        for (final x in [23.0, 50.0, 77.0])
          DiagramElement(
            shape: 'rectangle',
            x: x,
            y: 43,
            width: 17,
            height: 37,
            color: 'gold',
          ),
        _lab(50, 77, 'Kare $cell mm · ara $space mm'),
      ]);
      return _n(
        'Bir kontak baskıda aynı boyutlu $n fotoğraf karesi, çizimdeki aralık korunarak tek sıraya dizilecek. Dış kenar boşlukları hariç sıra kaç mm genişlik kaplar?',
        total,
        [n * (cell + space), n * cell, (n - 1) * (cell + space)],
        '$n karenin genişlikleri ${n * cell} mm eder. Aralarında ${n - 1} boşluk bulunduğundan toplam ${n * cell} + ${(n - 1) * space} = $total mm olur.',
        v,
      );
    },
  ),
  _activity(
    'sport_terms',
    'Sahada teknik ve oyun terimleri',
    Topic.sport,
    _hs,
    ActivityKind.matching,
    BloomLevel.hatirlama,
    _sportTerms,
    'Her spor terimini onu diğerlerinden ayıran teknik veya oyun açıklamasıyla eşleştirin.',
  ),
  _activity(
    'host_order',
    'Yaz Olimpiyatları ev sahipleri',
    Topic.sport,
    _hs,
    ActivityKind.ordering,
    BloomLevel.hatirlama,
    _hostDates,
    'Şehirleri, modern Yaz Olimpiyat Oyunları’na ilk kez ana ev sahibi oldukları tarihe göre eskiden yeniye sıralayın.',
  ),
  _domain(
    'curling',
    'Curlingde end puanını değerlendirme',
    Topic.sport,
    _hs,
    BloomLevel.degerlendirme,
    _tableKind,
    (a, b, c) {
      final r = a + 2, s = r + b + 2, t = s + c + 2;
      final blue = [r - 1, r + 1, s + 1, t + 1][(a + b + c) % 4];
      final tally = [r, s, t].where((n) => n < blue).length;
      final tab = _table(
        'Evin içinde kalan taşların düğmeye uzaklığı',
        ['Takım', 'Uzaklıklar (cm)'],
        [
          ['Kırmızı', '$r, $s, $t'],
          ['Mavi', '$blue'],
        ],
      );
      final correct = tally == 0 ? 'Mavi 1 puan' : 'Kırmızı $tally puan';
      return _item(
        'Bir curling endi tamamlandı. Tabloda evdeki tüm taşlar yer alıyor. En yakın rakip taştan daha yakın taşlar puan sayıldığına göre hakem hangi sonucu yazmalıdır?',
        correct,
        ['Kırmızı 1 puan', 'Kırmızı 2 puan', 'Kırmızı 3 puan', 'Mavi 1 puan'],
        tally == 0
            ? 'En yakın mavi taş $blue cm, en yakın kırmızı taş $r cm uzaktadır. Mavinin tek taşı kırmızı taşlardan daha yakındır, dolayısıyla mavi 1 puan alır.'
            : 'Düğmeye en yakın taş kırmızıdır ($r cm). Mavi taşa ait $blue cm uzaklıktan daha yakında duran kırmızı taşlar puan kazandırır. Sonuç $correct.',
        tab,
      );
    },
    typed: false,
  ),
  _domain(
    'basket',
    'Basketbolda etkili saha içi yüzdesi',
    Topic.sport,
    _un,
    _analyze,
    _tableKind,
    (a, b, c) {
      final two = a + 2,
          three = b + 1,
          miss = c + 3,
          att = two + three + miss,
          n = 100 * (2 * two + 3 * three),
          d = 2 * att;
      final tab = _table(
        'Takımın saha içi şutları',
        ['İkilik isabet', 'Üçlük isabet', 'Kaçan şut'],
        [
          [two, three, miss],
        ],
      );
      return _r(
        'Serbest atışlar tabloya dâhil değildir. Üçlük isabete 1,5; ikilik isabete 1 isabet ağırlığı veren etkili saha içi yüzdesi kaçtır?',
        n,
        d,
        [
          (100 * (two + three), att),
          (100 * (2 * two + 3 * three), att),
          (100 * three, att),
        ],
        'Ağırlıklı isabet $two + 1,5 × $three olur. Deneme sayısı $att. Etkili yüzde 100 × (2 × $two + 3 × $three)/(2 × $att) = ${_frac(n, d)}.',
        tab,
      );
    },
  ),
  _domain(
    'swimming',
    'Yüzmede negatif split değerlendirmesi',
    Topic.sport,
    _hs,
    _analyze,
    _chart,
    (a, b, c) {
      final first = a + 52, second = b + 51, last = c + 50;
      final v = _bars(
        '200 m serbest: 50 m ara süreleri',
        ['1. boy', '2. boy', '3. boy', '4. boy'],
        [first, second, last, 54],
        'sn',
      );
      final margin = first + second - last - 54;
      final result = margin > 0
          ? 'Negatif split'
          : margin < 0
          ? 'Pozitif split'
          : 'Eşit split';
      final value = '$result · ${margin.abs()} sn';
      return _item(
        'İkinci 100 m ilkinden daha kısa sürerse negatif, daha uzun sürerse pozitif split denir. Grafiğe göre doğru sınıflandırma ve iki yarı arasındaki süre farkı hangisidir?',
        value,
        [
          for (final t in ['Negatif split', 'Pozitif split', 'Eşit split'])
            if (t != result) '$t · ${margin.abs()} sn',
          '$result · ${margin.abs() + 1} sn',
        ],
        'İlk 100 m ${first + second} sn, ikinci 100 m ${last + 54} sn sürer. Aradaki fark ${margin.abs()} saniyedir. Bu nedenle sınıflandırma $result olur.',
        v,
      );
    },
    typed: false,
  ),
  _domain(
    'rowing',
    'Kürekte çevrim başına ilerleme',
    Topic.sport,
    _un,
    _apply,
    _tableKind,
    (a, b, c) {
      final stroke = a + 20, time = 120 + b * 5, dist = 480 + c * 12;
      final tab = _table(
        'Sabit ritimli parkur bölümü',
        ['Kürek ritmi', 'Süre', 'Yol'],
        [
          ['$stroke/dk', '$time sn', '$dist m'],
        ],
      );
      return _r(
        'Ölçüm aralığında tablodaki ortalama kürek ritmi korunmuştur. Tam çevrim eşdeğeri başına ortalama ilerleme kaç metredir?',
        60 * dist,
        stroke * time,
        [(dist, stroke), (dist, time), (dist * stroke, time * 60)],
        'Çevrim sayısı ritim × süre = $stroke × $time/60. Alınan yol bu sayıya bölünür. İlerleme 60 × $dist/($stroke × $time) = ${_frac(60 * dist, stroke * time)} m/çevrimdir.',
        tab,
      );
    },
  ),
  _domain(
    'cycle',
    'Bisiklette dişli oranı ve ilerleme',
    Topic.sport,
    _un,
    _apply,
    _diag,
    (a, b, c) {
      final front = a + 32, rear = b + 13, circ = 190 + c * 3, n = front * circ;
      final fig = _drawing('Aktarma organları', [
        const DiagramElement(
          shape: 'circle',
          x: 27,
          y: 46,
          width: 25,
          height: 55,
          color: 'gold',
        ),
        const DiagramElement(
          shape: 'circle',
          x: 76,
          y: 46,
          width: 14,
          height: 31,
          color: 'blue',
        ),
        _line(27, 19, 76, 30),
        _line(27, 73, 76, 62),
        _lab(27, 46, '$front'),
        _lab(76, 46, '$rear'),
        _lab(50, 88, 'Ön ve arka diş sayıları'),
      ]);
      return _r(
        'Tekerlek çevresi $circ cm olan bisiklette zincir kaymıyor. Şekildeki dişlilerle krankın bir tam devri bisikleti kaç cm ilerletir?',
        n,
        rear,
        [(rear * circ, front), (front + rear, 1), (circ, 1)],
        'Krank bir turda $front diş zincir çeker. Arka tekerlek $front/$rear tur döner. İlerleme $circ × $front/$rear = ${_frac(n, rear)} cm’dir.',
        fig,
      );
    },
  ),
  _domain(
    'points',
    'Futbolda grup sıralamasını değerlendirme',
    Topic.sport,
    _hs,
    BloomLevel.degerlendirme,
    _tableKind,
    (a, b, c) {
      final win = 2 + a, draw = 1 + b, gap = c % 5 + 1;
      final rival = win + ((c ~/ 5 == 0) ? gap : -gap);
      // Limit the win difference when the baseline is small.
      final rw = rival < 0 ? 0 : rival, rd = (a + 2 * b + c) % 13;
      final aScore = 3 * win + draw,
          bScore = 3 * rw + rd,
          diff = aScore - bScore;
      final label = diff > 0
          ? 'Kuzey önde'
          : diff < 0
          ? 'Güney önde'
          : 'Puanlar eşit';
      final tab = _table(
        'Grup klasmanında iki takım',
        ['Takım', 'Galibiyet', 'Beraberlik'],
        [
          ['Kuzey', win, draw],
          ['Güney', rw, rd],
        ],
      );
      return _item(
        'Galibiyet 3, beraberlik 1, mağlubiyet 0 puandır. Yalnız puan karşılaştırılacak. Tablodan çıkarılabilecek sonuç ve puan farkı hangisidir?',
        '$label · ${diff.abs()}',
        [
          for (final t in ['Kuzey önde', 'Güney önde', 'Puanlar eşit'])
            if (t != label) '$t · ${diff.abs()}',
          '$label · ${diff.abs() + 1}',
        ],
        'Kuzey 3 × $win + $draw = $aScore, Güney 3 × $rw + $rd = $bScore puan alır. Mutlak fark ${diff.abs()} puandır.',
        tab,
      );
    },
    typed: false,
  ),
  _domain(
    'sport_design',
    'Bayrak takımı için tur planı',
    Topic.sport,
    _un,
    BloomLevel.yaratma,
    _tableKind,
    (a, b, c) {
      final total = 320 + a * 2,
          first = 69 + b,
          second = 74 + c,
          remain = total - first - second;
      final tab = _table(
        'Dört eşit etaplı bayrak koşusu',
        ['Hedef', '1. koşucu', '2. koşucu'],
        [
          ['$total sn', '$first sn', '$second sn'],
        ],
      );
      return _n(
        'İlk iki etabın süreleri tabloda verilmiştir. Takım hedef süresini tam tutturacaksa son iki etabın toplamı kaç saniye olmalıdır?',
        remain,
        [total - second, total - first, first + second],
        'Son iki etaba kalan süre $total − $first − $second = $remain saniyedir.',
        tab,
      );
    },
    creation: (item, i) => CreationTask(
      'Koç olarak son iki etap için iki farklı süre planı tasarlayın. İlk planda son koşucu takım arkadaşından hızlı olsun. İkinci planda aynı toplamı koruyup son koşucuya ilk plandan daha uzun süre tanıyın. Süreleri ve değiş tokuşun gerekçesini yazın.',
      [
        'İki planda da son iki süre pozitif olup hedefe kalan süreyi tam doldurur.',
        'İlk planda son etap üçüncü etaptan kısadır. İkinci planda son etap ilk plana göre uzundur.',
        'İki planın tempo paylaşımını somut sürelerle karşılaştırır ve seçiminin sportif gerekçesini açıklar.',
      ],
    ),
  ),
  _domain(
    'jump',
    'Sıçrama sırasında ortalama net kuvvet',
    Topic.sport,
    _un,
    _apply,
    _tableKind,
    (a, b, c) {
      final mass = a + 52,
          delta = b + 12,
          ms = (c + 9) * 10,
          n = mass * delta * 100,
          d = ms;
      final tab = _table(
        'Kuvvet platformu denemesi',
        ['Kütle', 'Hız artışı', 'Süre'],
        [
          ['$mass kg', '${_frac(delta, 10)} m/sn', '$ms ms'],
        ],
      );
      return _r(
        'Sıçrama itişinde sporcunun kütle merkezinin yukarı yönlü hızı tabloda verilen miktarda artmıştır. Bu evredeki ortalama net düşey kuvvetin büyüklüğü kaç N olur?',
        n,
        d,
        [(mass * delta, ms), (mass * delta * 1000, ms), (mass * delta, 10)],
        'Net itki kütle × hız değişimidir. Süreyi saniyeye çevirince ortalama net kuvvet [$mass × (${_frac(delta, 10)})]/($ms/1000) = ${_frac(n, d)} N olur.',
        tab,
      );
    },
  ),
];
