// Özgün matematik aileleri. Her ailenin üç bağımsız koordinatı 25 × 20 × 10
// farklı problem verisi üretir; herhangi bir varyanta doğrudan erişilebilir.
import 'common.dart';

typedef _Builder = AdvancedItem Function(int a, int b, int c);

AdvancedFamily _family(
  String key,
  String title,
  StudyLevel level,
  Difficulty difficulty,
  VisualKind? kind,
  _Builder build, {
  ExamKind? exam,
  BloomLevel bloom = BloomLevel.uygulama,
  CreationTask Function(AdvancedItem, int)? creation,
}) => AdvancedFamily(
  key: 'math_$key',
  title: title,
  topic:
      const {
        'weighted',
        'two_draws',
        'flower_beds',
        'regression',
        'bayes',
        'expectation',
        'covariance',
        'hypergeom',
        'poisson_condition',
        'markov',
      }.contains(key)
      ? Topic.statistics
      : Topic.mathematics,
  level: level,
  count: 5000,
  difficulty: difficulty,
  visualKind: kind,
  exam: exam,
  bloom: bloom,
  creation: creation,
  shortAnswer:
      creation == null &&
      !const {'centroid', 'basis', 'ode', 'simpson'}.contains(key),
  lesson: exam == ExamKind.tyt ? 'Temel Matematik' : 'Matematik',
  build: (i) => build(i % 25, i ~/ 25 % 20, i ~/ 500),
);

String _fraction(int n, int d) {
  if (d < 0) return _fraction(-n, -d);
  final g = n.gcd(d);
  return d == g ? '${n ~/ g}' : '${n ~/ g}/${d ~/ g}';
}

AdvancedItem _choose(
  String p,
  String a,
  Iterable<String> alternatives,
  String explanation,
  QuestionVisual? visual,
) {
  final choices = alternatives.where((s) => s != a).toSet().take(3).toList();
  if (choices.length != 3) throw StateError('Eksik seçenek: $p ($a)');
  return AdvancedItem(p, a, choices, explanation, visual: visual);
}

AdvancedItem _num(
  String p,
  int a,
  List<int> alternatives,
  String e, [
  QuestionVisual? v,
]) => _choose(
  p,
  '$a',
  [...alternatives, a + 1, a - 1, a + 2, a - 2].map((x) => '$x'),
  e,
  v,
);

AdvancedItem _ratio(
  String p,
  int n,
  int d,
  List<(int, int)> alternatives,
  String e, [
  QuestionVisual? v,
]) {
  final values = [
    ...alternatives,
    (n + 1, d),
    (n - 1, d),
    (n + 2, d),
    (n + 3, d),
  ];
  return _choose(
    p,
    _fraction(n, d),
    values.where((x) => x.$2 != 0).map((x) => _fraction(x.$1, x.$2)),
    e,
    v,
  );
}

String _pair(int a, int b) => '($a, $b)';

QuestionVisual _table(
  String name,
  List<String> heads,
  List<List<Object>> data,
) => QuestionVisual(
  kind: VisualKind.table,
  title: name,
  summary: '',
  columns: heads,
  rows: [
    for (final row in data) [for (final x in row) '$x'],
  ],
);

QuestionVisual _plot(
  VisualKind kind,
  String name,
  List<String> labels,
  List<int> vals,
  String unit,
) => QuestionVisual(
  kind: kind,
  title: name,
  summary: '',
  labels: labels,
  values: vals.map((v) => v.toDouble()).toList(),
  unit: unit,
);

DiagramElement _line(
  double x,
  double y,
  double u,
  double v, {
  String color = 'mint',
}) => DiagramElement(shape: 'line', x: x, y: y, endX: u, endY: v, color: color);
DiagramElement _label(double x, double y, Object text) =>
    DiagramElement(shape: 'text', x: x, y: y, label: '$text');
QuestionVisual _diagram(String name, List<DiagramElement> elements) =>
    QuestionVisual(
      kind: VisualKind.diagram,
      title: name,
      summary: 'Şema ölçekli değildir. Hesaplamada etiketlerde verilen ölçüleri kullanınız.',
      elements: elements,
    );

int _comb(int n, int k) {
  if (k < 0 || k > n) return 0;
  if (k > n - k) k = n - k;
  var result = 1;
  for (var i = 1; i <= k; i++) {
    result = result * (n - i + 1) ~/ i;
  }
  return result;
}

const _high = StudyLevel.lise, _uni = StudyLevel.universite;
const _m = Difficulty.medium, _h = Difficulty.hard;
const _d = VisualKind.diagram,
    _t = VisualKind.table,
    _b = VisualKind.barChart,
    _l = VisualKind.lineChart;

final mathFamilies = <AdvancedFamily>[
  _family('trapezoid', 'Yamukta alan', _high, _m, _d, (a, b, c) {
    final top = a + 6, bottom = top + b + 2, height = c + 4;
    final n = (top + bottom) * height;
    final v = _diagram('Yamuğun ölçüleri (cm)', [
      _line(12, 80, 87, 80),
      _line(87, 80, 66, 22),
      _line(66, 22, 33, 22),
      _line(33, 22, 12, 80),
      _line(33, 22, 33, 80, color: 'gold'),
      _line(33, 72, 38, 72, color: 'gold'),
      _line(38, 72, 38, 80, color: 'gold'),
      _label(50, 11, top),
      _label(50, 91, bottom),
      _label(39, 51, height),
    ]);
    return _ratio(
      'Şekildeki yamuğun alanı kaç santimetrekaredir?',
      n,
      2,
      [(n, 1), (bottom * height, 2), (top * height, 1)],
      'Paralel kenarların ortalaması yükseklikle çarpılır. Alan ($top + $bottom) × $height / 2 = ${_fraction(n, 2)} cm² olur.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family('parallel', 'Paralellik ve benzerlik', _high, _m, _d, (a, b, c) {
    final ad = a + 3, db = b + 2, de = c + 4, n = de * (ad + db);
    final v = _diagram('ABC üçgeninde DE ∥ BC', [
      _line(48, 13, 12, 85),
      _line(48, 13, 87, 85),
      _line(12, 85, 87, 85),
      _line(30, 49, 67.5, 49, color: 'gold'),
      _label(48, 5, 'A'),
      _label(8, 89, 'B'),
      _label(91, 89, 'C'),
      _label(24, 48, 'D'),
      _label(73, 48, 'E'),
      _label(32, 28, ad),
      _label(15, 65, db),
      _label(49, 42, de),
    ]);
    return _ratio(
      'D ve E, ABC üçgeninin kenarları üzerindedir. Şekilde verilen uzunluklara göre BC kaç birimdir?',
      n,
      ad,
      [(de * db, ad), (de * ad, ad + db), (de + db, 1)],
      'ADE ve ABC benzerdir. BC/DE = AB/AD = ($ad + $db)/$ad. Dolayısıyla BC = ${_fraction(n, ad)} birimdir.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family('angle_bisector', 'İç açıortay ve kenar oranı', _high, _m, _d, (
    a,
    b,
    c,
  ) {
    // With AB and AC near one another the base satisfies both triangle inequalities.
    final ab = a + 35, ac = b + 35, bc = c + 26, n = ab * bc;
    final v = _diagram('AD, A açısının açıortayıdır', [
      _line(44, 14, 11, 81),
      _line(44, 14, 89, 81),
      _line(11, 81, 89, 81),
      _line(44, 14, 52, 81, color: 'gold'),
      _label(44, 5, 'A'),
      _label(8, 89, 'B'),
      _label(52, 88, 'D'),
      _label(91, 89, 'C'),
      _label(21, 44, ab),
      _label(71, 43, ac),
      _label(46, 96, 'BC = $bc'),
    ]);
    return _ratio(
      'Şekildeki ABC üçgeninde BD uzunluğu kaç birimdir?',
      n,
      ab + ac,
      [(ac * bc, ab + ac), (ab * bc, ac), (bc, 2)],
      'Açıortay teoremi BD/DC = $ab/$ac verir. Tüm tabanın $ab/(${ab + ac}) kadarı BD olduğundan BD = ${_fraction(n, ab + ac)}.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family('frame', 'Dikdörtgen çerçevede alan', _high, _m, _d, (a, b, c) {
    final width = a + 31,
        height = b + 28,
        edge = c + 1,
        inner = (width - 2 * edge) * (height - 2 * edge),
        area = width * height - inner;
    final v = _diagram('Dış çerçeve ve iç açıklık', [
      const DiagramElement(
        shape: 'rectangle',
        x: 50,
        y: 48,
        width: 74,
        height: 64,
        color: 'gold',
      ),
      const DiagramElement(
        shape: 'rectangle',
        x: 50,
        y: 48,
        width: 56,
        height: 40,
        color: 'blue',
      ),
      _label(50, 8, '$width cm'),
      _label(8, 47, '$height'),
      _label(50, 48, 'İç açıklık'),
    ]);
    return _num(
      'Çizimde dış kenar uzunlukları cm cinsindendir. Dört kenarı da $edge cm genişliğinde olan çerçevenin malzeme alanı kaç santimetrekaredir?',
      area,
      [
        inner,
        2 * (width + height) * edge,
        width * height - (width - edge) * (height - edge),
      ],
      'İç açıklığın ölçüleri ${width - 2 * edge} × ${height - 2 * edge} cm’dir. Malzeme alanı $width × $height − $inner = $area cm² olur.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family('quad_angle', 'Dörtgende iç açı', _high, _m, _d, (a, b, c) {
    final left = a + 55,
        top = b + 91,
        right = c + 98,
        ans = 360 - left - top - right;
    final v = _diagram('Dışbükey dörtgenin iç açıları', [
      _line(12, 75, 34, 19),
      _line(34, 19, 76, 25),
      _line(76, 25, 87, 83),
      _line(87, 83, 12, 75),
      _label(22, 65, '$left°'),
      _label(40, 31, '$top°'),
      _label(70, 37, '$right°'),
      _label(79, 70, 'x'),
    ]);
    return _num(
      'Dörtgende x ile gösterilen iç açının derece cinsinden ölçüsü kaçtır?',
      ans,
      [180 - ans, 360 - top - right, ans + 10],
      'Dört iç açı toplamı 360°’dir. Bu nedenle x = 360 − $left − $top − $right = $ans derecedir.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family('centroid', 'Üçgenin ağırlık merkezi', _high, _m, _t, (a, b, c) {
    final x = a + 1, y = b + 2, h = c + 3;
    final v = _table(
      'ABC üçgeninin köşeleri',
      ['Köşe', 'x', 'y'],
      [
        ['A', 0, 0],
        ['B', 3 * x, 0],
        ['C', 3 * h, 3 * y],
      ],
    );
    return _choose(
      'Koordinatları verilen üçgenin ağırlık merkezi hangi noktadır?',
      _pair(x + h, y),
      [
        _pair(3 * x + 3 * h, 3 * y),
        _pair(x, y + h),
        _pair(x + h, 3 * y),
        _pair(h, y),
      ],
      'Ağırlık merkezi koordinatların ayrı ayrı ortalamasıdır. x = (0 + ${3 * x} + ${3 * h})/3 = ${x + h}, y = ${3 * y}/3 = $y.',
      v,
    );
  }, exam: ExamKind.ayt),
  _family('weighted', 'Frekans dağılımında ortalama', _high, _m, _b, (a, b, c) {
    final x = a + 2,
        y = b + 2,
        z = c + 2,
        n = 2 * x + 5 * y + 9 * z,
        d = x + y + z;
    final v = _plot(
      _b,
      'Öğrencilerin çözdüğü soru sayısı',
      ['2 soru', '5 soru', '9 soru'],
      [x, y, z],
      'kişi',
    );
    return _ratio(
      'Grafik, her soru sayısı için kaç öğrenci bulunduğunu gösteriyor. Öğrenci başına düşen ortalama soru sayısı kaçtır?',
      n,
      d,
      [(16, 3), (n, 3), (n - x, d)],
      'Toplam çözülen soru sayısı 2 × $x + 5 × $y + 9 × $z = $n. Bunu $d öğrenciye bölersek ${_fraction(n, d)} buluruz.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family('two_draws', 'Geri koymadan çekim', _high, _h, _b, (a, b, c) {
    final x = a + 2,
        y = b + 2,
        z = c + 1,
        t = x + y + z,
        n = 2 * x * y,
        d = t * (t - 1);
    final v = _plot(
      _b,
      'Torbadaki bilyeler',
      ['Kırmızı', 'Mavi', 'Beyaz'],
      [x, y, z],
      'adet',
    );
    return _ratio(
      'Grafikteki torbadan geri koymadan rastgele iki bilye çekiliyor. Birinin kırmızı, diğerinin mavi olma olasılığı kaçtır?',
      n,
      d,
      [(x * y, d), (n, t * t), (x + y, t)],
      'Kırmızı-mavi ve mavi-kırmızı sıraları ayrıdır. İki sıranın toplam olasılığı 2 × $x × $y / ($t × ${t - 1}) = ${_fraction(n, d)}.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family(
    'paths',
    'Kafes yollarında geçiş koşulu',
    _high,
    _h,
    _t,
    (a, b, c) {
      final x = a % 5 + 1,
          y = a ~/ 5 + 1,
          u = b % 5 + 1,
          v = b ~/ 5 + 1,
          k = c + 1;
      final endX = x + u + k, endY = y + v;
      // Two mandatory stops split the path into three monotone segments.
      final ans = _comb(x + y, x) * _comb(u + v, u);
      final tab = _table(
        'Izgara kavşakları',
        ['Kavşak', 'x', 'y'],
        [
          ['Başlangıç', 0, 0],
          ['P', x, y],
          ['Q', x + u, y + v],
          ['Bitiş', endX, endY],
        ],
      );
      final total = ans * k;
      return _num(
        'Yalnız sağa ve yukarı birim adımlarla ilerleyen bir kurye P ve Q noktalarından geçecektir. Q’dan bitişe kadar yaptığı yatay adımlardan tam birinde fotoğraf çekmesi gerekiyor. Yol ve fotoğraf adımı birlikte kaç farklı şekilde seçilebilir?',
        total,
        [ans, _comb(endX + endY, endY), ans * (k + 1)],
        'P’ye kadar ${_comb(x + y, x)}, P’den Q’ya kadar ${_comb(u + v, u)} yol vardır. Son $k adımın tümü sağa gider; fotoğraf için $k seçim vardır. Çarpım $total olur.',
        tab,
      );
    },
    exam: ExamKind.ayt,
    bloom: BloomLevel.analiz,
  ),
  _family('arith_sum', 'Aritmetik dizide kısmi toplam', _high, _m, _t, (
    a,
    b,
    c,
  ) {
    final first = a + 2,
        step = b + 1,
        k = c + 5,
        last = first + (k - 1) * step,
        total = k * (first + last) ~/ 2;
    final v = _table(
      'Bir dizinin ilk terimleri',
      ['Sıra', 'Terim'],
      [
        [1, first],
        [2, first + step],
        [3, first + 2 * step],
      ],
    );
    return _num(
      'Tablodaki aritmetik dizinin ilk $k teriminin toplamı kaçtır?',
      total,
      [k * last, k * first, last],
      'Ortak fark $step, $k. terim $last olur. Toplam $k × ($first + $last)/2 = $total.',
      v,
    );
  }, exam: ExamKind.ayt),
  _family(
    'piecewise_transport',
    'Kademeli tarife',
    _high,
    _m,
    _t,
    (a, b, c) {
      final fixed = a + 20, rate = b + 4, km = c + 7;
      final v = _table(
        'Taşıma tarifesi',
        ['Kalem', 'Ücret'],
        [
          ['Çıkış', '$fixed TL'],
          ['İlk 5 km', '$rate TL/km'],
          ['5 km sonrası', '${rate + 3} TL/km'],
        ],
      );
      final total = fixed + 5 * rate + (km - 5) * (rate + 3);
      return _num(
        'Tarifeye göre $km km uzunluğundaki tek bir yolculuk kaç TL tutar?',
        total,
        [fixed + rate * km, fixed + (rate + 3) * km, total - fixed],
        'Çıkış ücretine ilk bölümün ${5 * rate} TL ve kalan ${km - 5} km’nin ${(km - 5) * (rate + 3)} TL bedeli eklenir. Toplam $total TL’dir.',
        v,
      );
    },
    exam: ExamKind.tyt,
    bloom: BloomLevel.yaratma,
    creation: (item, index) {
      final km = 7 + index ~/ 500;
      return CreationTask(
        'Tablodaki tarifeye alternatif bir taşıma tarifesi tasarlayın. Çıkış ücretini ve ilk 5 km için kilometre ücretini değiştirin. Ücretler negatif olmasın. Dört kilometrede yeni tarife daha ucuz, $km kilometrede iki tarife eşit olsun. Kendi tarifenizi ve iki yolculuk için hesaplarınızı yazın.',
        [
          'Negatif olmayan çıkış, ilk kademe ve sonraki kademe ücretlerini tanımlar. İlk iki ücret eski tarifeden farklıdır.',
          'Dört kilometrede iki toplamı doğru hesaplar ve yeni tarifenin daha ucuz olduğunu gösterir.',
          '$km kilometrede iki tarifenin aynı toplamı verdiğini ücret kalemleriyle doğrular.',
        ],
      );
    },
  ),
  _family('moving_graph', 'Hız-zaman grafiğinde yol', _high, _m, _l, (a, b, c) {
    final x = a + 4, y = b + 7, z = c + 5, total = x + 2 * y + z;
    final v = _plot(
      _l,
      'Hız (m/s)',
      ['0 sn', '2 sn', '4 sn'],
      [x, y, z],
      'm/s',
    );
    return _num(
      'Hızı grafikteki noktalar arasında doğrusal değişen araç dört saniyede kaç metre yol alır?',
      total,
      [x + y + z, 2 * (x + y + z), 2 * y + z],
      'Her iki saniyelik bölümde ortalama hız uç değerlerin ortalamasıdır. Toplam yol ($x + $y) × 2/2 + ($y + $z) × 2/2 = $total m.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family('radical_distance', 'Uzayda köşegen', _high, _m, _d, (a, b, c) {
    final x = a + 3, y = b + 4, z = c + 2, s = x * x + y * y + z * z;
    final v = _diagram('Dikdörtgenler prizmasının ayrıtları', [
      _line(14, 35, 62, 35),
      _line(62, 35, 62, 80),
      _line(62, 80, 14, 80),
      _line(14, 80, 14, 35),
      _line(14, 35, 32, 16),
      _line(32, 16, 81, 16),
      _line(81, 16, 62, 35),
      _line(81, 16, 81, 62),
      _line(81, 62, 62, 80),
      _label(36, 90, x),
      _label(8, 59, z),
      _label(78, 80, y),
    ]);
    return _num(
      'Ayrıt ölçüleri şekilde verilen prizmanın cisim köşegeninin uzunluğunun karesi kaçtır?',
      s,
      [x * x + y * y, (x + y + z) * (x + y + z), x * y * z],
      'Önce taban köşegeni için Pisagor bağıntısı uygulanır, sonra üçüncü ayrıtın karesi eklenir. Sonuç $x² + $y² + $z² = $s.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family('similar_shadows', 'Gölgeyle yükseklik ölçme', _high, _m, _t, (
    a,
    b,
    c,
  ) {
    final pole = a + 50, shadow = b + 30, tower = c + 11, n = pole * tower;
    final v = _table(
      'Aynı anda alınan ölçüler',
      ['Nesne', 'Boy', 'Gölge'],
      [
        ['Çubuk', '$pole cm', '$shadow cm'],
        ['Kule', '?', '$tower m'],
      ],
    );
    return _ratio(
      'Düz zeminde dik duran çubuk ve kulenin gölgeleri tabloda verilmiştir. Kulenin boyu kaç metredir?',
      n,
      shadow,
      [(tower * shadow, pole), (n, 100 * shadow), (tower + pole, shadow)],
      'Aynı güneş açısında boy/gölge oranı sabittir. Çubukta bu oran $pole/$shadow olduğundan kulenin boyu $tower × $pole/$shadow = ${_fraction(n, shadow)} m’dir.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family('progressive_sale', 'Ardışık yüzde değişimi', _high, _m, _t, (
    a,
    b,
    c,
  ) {
    final price = (a + 10) * 100,
        up = (b + 1) * 2,
        down = (c + 1) * 5,
        n = price * (100 + up) * (100 - down);
    final v = _table(
      'Bir ürünün fiyat geçmişi',
      ['Aşama', 'Değişim'],
      [
        ['İlk fiyat', '$price TL'],
        ['İlk işlem', '%$up artış'],
        ['İkinci işlem', '%$down indirim'],
      ],
    );
    return _ratio(
      'Tablodaki iki işlem sırayla uygulanınca ürünün son fiyatı kaç TL olur?',
      n,
      10000,
      [
        (price * (100 + up - down), 100),
        (price * (100 - down), 100),
        (price * (100 + up), 100),
      ],
      'İndirim, artıştan sonraki fiyat üzerinden yapılır. Son fiyat $price × (100 + $up)/100 × (100 − $down)/100 = ${_fraction(n, 10000)} TL olur.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family('roof', 'Eğim oranı ve yükseklik', _high, _m, _d, (a, b, c) {
    final span = a + 6,
        rise = b + 2,
        base = c + 3,
        n = 100 * base + span * rise;
    final v = _diagram('Tek eğimli çatının kesiti', [
      _line(19, 80, 80, 80),
      _line(19, 80, 19, 51),
      _line(19, 51, 80, 17, color: 'gold'),
      _line(80, 17, 80, 80),
      _label(49, 90, '$span m'),
      _label(11, 64, '$base m'),
      _label(48, 20, 'Eğim %$rise'),
    ]);
    return _ratio(
      'Şekilde eğim, düşey yükselmenin yatay uzaklığa oranıdır. Sağ duvarın yüksekliği kaç metredir?',
      n,
      100,
      [(span * rise, 100), (base + span + rise, 1), (100 * base + rise, 100)],
      'Çatıda yükselme $span × $rise/100 m’dir. Sol duvarın boyu eklenince sağ duvar ${_fraction(n, 100)} m olur.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family(
    'piecewise_profit',
    'Parabolle kârın en büyük değeri',
    _high,
    _h,
    null,
    (a, b, c) {
      final slope = c + 1,
          mid = a + 8,
          cost = b + 4,
          price = 2 * mid * slope + cost;
      final ans = slope * mid * mid;
      return _num(
        'Bir satıcının x adet satış için belirlediği birim fiyat ${price} − ${slope}x TL, birim maliyeti $cost TL’dir. Sabit gider yoksa elde edebileceği en büyük toplam kâr kaç TL’dir?',
        ans,
        [mid, 2 * ans, ans + cost * mid],
        'Kâr x($price − ${slope}x − $cost) = $ans − $slope(x − $mid)² biçimindedir. x = $mid adet satıldığında en büyük değer $ans TL olur.',
      );
    },
    exam: ExamKind.ayt,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'remainders',
    'Bir aralıkta iki kalanı sağlayan sayılar',
    _high,
    _h,
    null,
    (a, b, c) {
      final lower = a + 11,
          upper = (b + 7) * 13 + lower,
          rem = c % 5,
          parity = c ~/ 5;
      final start = [
        for (var k = 0; k < 10; k++)
          if (k % 5 == rem && k % 2 == parity) k,
      ].single;
      final first = lower + (start - lower % 10 + 10) % 10,
          ans = (upper - first) ~/ 10 + 1;
      return _num(
        '$lower ile $upper arasında (uçlar dâhil), 5 ile bölümünden $rem kalan ve 2 ile bölümünden $parity kalan kaç tam sayı vardır?',
        ans,
        [ans - 1, ans + 1, (upper - lower) ~/ 5],
        'İki koşulu birlikte sağlayan sayıların birler basamağı $start olur. Aralıktaki ilk uygun sayı $first. Bundan başlayıp onar sayıldığında $ans sayı elde edilir.',
      );
    },
    exam: ExamKind.tyt,
    bloom: BloomLevel.analiz,
  ),
  _family('secant_line', 'İki ölçümden doğrusal kestirim', _high, _m, _l, (
    a,
    b,
    c,
  ) {
    final y = a + 10, change = b + 2, t = c + 3, ans = y + change * t;
    final v = _plot(
      _l,
      'Sabit debiyle dolan tank',
      ['0 dk', '2 dk', '4 dk'],
      [y, y + 2 * change, y + 4 * change],
      'L',
    );
    return _num(
      'Grafikte ilk dört dakikanın su hacimleri verilmiştir. Aynı sabit debi korunursa ${t + 4}. dakikadaki hacim kaç litre olur?',
      ans + 4 * change,
      [ans, y + (t + 4) * 2 * change, (t + 4) * change],
      'Dakikadaki hacim artışı (${y + 2 * change} − $y)/2 = $change litredir. ${t + 4}. dakikada hacim $y + ${t + 4} × $change = ${ans + 4 * change} L olur.',
      v,
    );
  }, exam: ExamKind.tyt),
  _family('polynomial_div', 'Polinom kalanıyla eksik katsayı', _high, _m, null, (
    a,
    b,
    c,
  ) {
    final root = c + 2, m = a + 2, k = b + 1, rem = root * root + m * root + k;
    return _num(
      'P(x) = x² + mx + $k polinomunun x − $root ile bölümünden kalan $rem ise m kaçtır?',
      m,
      [k, m + root, m + 1],
      'Kalan teoreminden P($root) = $rem. Buradan m = ($rem − ${root * root} − $k)/$root = $m.',
    );
  }, exam: ExamKind.ayt),
  _family(
    'log_law',
    'Logaritma denkleminde tanım kümesi',
    _high,
    _h,
    null,
    (a, b, c) {
      final shift = a + 1,
          gap = b + 1,
          root = c + 2,
          product = root * (root + gap);
      return _num(
        'log₂(x − $shift) + log₂(x − $shift + $gap) = log₂($product) denkleminin gerçek çözümü kaçtır?',
        shift + root,
        [shift - root - gap, root, shift + root + gap],
        'u = x − $shift için tanım koşulu u > 0’dır. u(u + $gap) = $product denkleminin pozitif kökü $root olduğundan x = ${shift + root}.',
      );
    },
    exam: ExamKind.ayt,
    bloom: BloomLevel.analiz,
  ),
  _family('affine_comp', 'Fonksiyon bileşimi ve parametre', _high, _m, null, (
    a,
    b,
    c,
  ) {
    final v = a + 2, s = b + 2, q = c + 2, target = s * (v + q) + 1;
    return _num(
      'f(x) = ${s}x + 1 ve g(x) = x + k olsun. f(g($v)) = $target olduğuna göre k kaçtır?',
      q,
      [v + q, q + 1, target - v],
      'Önce g($v) = ($target − 1)/$s = ${v + q}. Ardından $v + k = ${v + q} eşitliğinden k = $q.',
    );
  }, exam: ExamKind.ayt),
  _family(
    'perpendicular',
    'Eş uzaklık doğrusu',
    _high,
    _m,
    _t,
    (a, b, c) {
      final left = a + 1,
          right = left + 2 * (b + 1),
          h = c + 3,
          mid = (left + right) ~/ 2;
      final v = _table(
        'İstasyonların koordinatları',
        ['İstasyon', 'x', 'y'],
        [
          ['A', left, h],
          ['B', right, h],
        ],
      );
      return _num(
        'A ve B istasyonlarına eşit uzaklıktaki noktanın y koordinatı, x koordinatından $h fazladır. Bu noktanın y koordinatı kaçtır?',
        mid + h,
        [mid, mid - h, right + h],
        'AB yatay olduğundan orta dikmesi x = ($left + $right)/2 = $mid doğrusudur. Aranan noktanın ordinatı $mid + $h = ${mid + h}.',
        v,
      );
    },
    exam: ExamKind.ayt,
    bloom: BloomLevel.analiz,
  ),
  _family('angular_rate', 'Dönme hareketinde taranan açı', _high, _m, null, (
    a,
    b,
    c,
  ) {
    final full = a + 12, time = b + 3, offset = (c + 1) * 12;
    final n = offset * full + 360 * time;
    return _ratio(
      'Sabit hızla saatin tersi yönde dönen bir kolun başlangıç açısı $offset° ve tur süresi $full saniyedir. $time saniye sonraki açının [0°, 360°) aralığındaki eş ölçüsü kaç derecedir?',
      n % (360 * full),
      full,
      [
        (360 * time, full),
        (n + 360 * full, full),
        ((offset * full - 360 * time) % (360 * full), full),
      ],
      'Saniyede 360/$full derece dönülür. $offset + 360 × $time/$full ifadesinden tam turlar çıkarılınca açı ${_fraction(n % (360 * full), full)}° olur.',
    );
  }, exam: ExamKind.ayt),
  _family(
    'flower_beds',
    'Kesişen kümeler ve tümleyen',
    _high,
    _m,
    _b,
    (a, b, c) {
      final onlyA = a + 3,
          onlyB = b + 2,
          both = c + 1,
          total = onlyA + onlyB + both;
      final v = _plot(
        _b,
        'En az birini seçen öğrenciler',
        ['Müzik', 'Resim', 'İkisi de'],
        [onlyA + both, onlyB + both, both],
        'kişi',
      );
      return _ratio(
        'Müzik ve resimden en az birini seçenler arasından rastgele bir öğrenci seçiliyor. Tam bir etkinlik seçmiş olma olasılığı kaçtır?',
        onlyA + onlyB,
        total,
        [(both, total), (onlyA + onlyB, total + both), (onlyA, total)],
        'Birleşim ${onlyA + both} + ${onlyB + both} − $both = $total kişidir. İki etkinliği de seçen $both kişi çıkarılırsa tam birini seçen ${onlyA + onlyB} kişi kalır. Olasılık ${_fraction(onlyA + onlyB, total)}.',
        v,
      );
    },
    exam: ExamKind.tyt,
    bloom: BloomLevel.analiz,
  ),
  _family('determinant', 'Determinantın dönüşüm alanına etkisi', _uni, _m, _t, (
    a,
    b,
    c,
  ) {
    final x = a + 2, y = b + 1, z = c + 3, det = x * z + y;
    final v = _table(
      'Dönüşüm matrisi A',
      ['', '1. sütun', '2. sütun'],
      [
        ['1. satır', x, y],
        ['2. satır', -1, z],
      ],
    );
    return _num(
      'Tablodaki A matrisi birim karenin köşelerine uygulanıyor. Görüntüdeki paralelkenarın alanı kaç birimkaredir?',
      det,
      [x * z - y, x * z, x + z],
      'Doğrusal dönüşüm alanı |det A| ile çarpar. |$x × $z − $y × (−1)| = $det olduğundan birim karenin görüntüsünün alanı $det olur.',
      v,
    );
  }),
  _family('basis', 'Bir vektörün yeni bazdaki koordinatları', _uni, _m, _t, (
    a,
    b,
    c,
  ) {
    final shear = a + 1, x = b + 2, y = c + 1, u = x + shear * y;
    final v = _table(
      'Standart koordinatlarda vektörler',
      ['Vektör', '1. bileşen', '2. bileşen'],
      [
        ['b₁', 1, 0],
        ['b₂', shear, 1],
        ['v', u, y],
      ],
    );
    return _choose(
      'v vektörünün sıralı B = (b₁, b₂) bazına göre koordinatları hangisidir?',
      _pair(x, y),
      [_pair(u, y), _pair(x, -y), _pair(u + shear * y, y), _pair(-x, y)],
      'v = r b₁ + s b₂ yazılır. İkinci bileşenden s = $y; ilk bileşenden r = $u − $shear × $y = $x. Koordinat çifti ${_pair(x, y)}.',
      v,
    );
  }),
  _family('eigenvalues', 'Özdeğerler ve matris kuvvetinin izi', _uni, _h, _t, (
    a,
    b,
    c,
  ) {
    final x = a + 2, y = b + 1, k = c + 2;
    // The off-diagonal parameter enters through the trace of a product.
    final n = x * x + y * y + 2 * k * k;
    final v = _table(
      'Simetrik matris A',
      ['', '1. sütun', '2. sütun'],
      [
        ['1. satır', x, k],
        ['2. satır', k, y],
      ],
    );
    return _num(
      'A matrisinin özdeğerleri λ₁ ve λ₂ ise λ₁² + λ₂² kaçtır?',
      n,
      [(x + y) * (x + y), x * x + y * y, x * y - k * k],
      'Özdeğer karelerinin toplamı tr(A²) değeridir. A² köşegeninde $x² + $k² ve $y² + $k² vardır. Toplam $n olur.',
      v,
    );
  }, bloom: BloomLevel.analiz),
  _family('projection', 'Ortogonal izdüşüm katsayısı', _uni, _m, _t, (a, b, c) {
    final x = a + 1, y = b + 1, k = c + 2, n = x + k * y, d = 1 + k * k;
    final v = _table(
      'Öklid düzleminde iki vektör',
      ['Vektör', 'x', 'y'],
      [
        ['u', x, y],
        ['v', 1, k],
      ],
    );
    return _ratio(
      'u’nun v doğrultusundaki ortogonal izdüşümü t·v biçiminde yazıldığında t kaçtır?',
      n,
      d,
      [(n, 1), (d, n), (k * x + y, d)],
      'İzdüşüm katsayısı (u·v)/(v·v) olur. İç çarpımlar $x + $y × $k = $n ve 1 + $k² = $d olduğundan t = ${_fraction(n, d)}.',
      v,
    );
  }),
  _family('gram', 'Gram matrisiyle alan', _uni, _h, _t, (a, b, c) {
    final u = a + 1, v = b + 1, w = c + 1;
    final det = u * u * (v * v + w * w);
    final tab = _table(
      'Uzaydaki iki kenar vektörü',
      ['Vektör', 'x', 'y', 'z'],
      [
        ['p', u, 0, 0],
        ['q', 1, v, w],
      ],
    );
    return _num(
      'p ve q vektörlerinin gerdiği paralelkenarın alanının karesi kaçtır?',
      det,
      [u * u * (1 + v * v + w * w), u * (v + w), u * u * v * v],
      'Alan karesi Gram determinantı (p·p)(q·q) − (p·q)² olur. Burada ${u * u} × ${1 + v * v + w * w} − $u² = $det.',
      tab,
    );
  }),
  _family(
    'regression',
    'Doğrusal regresyonda eğim',
    _uni,
    _h,
    _t,
    (a, b, c) {
      final y0 = a + 1, y1 = b + 2, y3 = c + 3;
      // x = 0, 1, 3 gives unnormalized centered weights -4, -1, 5.
      final n = -4 * y0 - y1 + 5 * y3;
      final tab = _table(
        'Üç gözlem',
        ['x', 'y'],
        [
          [0, y0],
          [1, y1],
          [3, y3],
        ],
      );
      return _ratio(
        'Tablodaki verilere sabit terimli y = α + βx doğrusu en küçük karelerle uyduruluyor. Eğim β kaçtır?',
        n,
        14,
        [(y3 - y0, 3), (n, 7), (y1 - y0, 1)],
        'β = [3Σxy − (Σx)(Σy)]/[3Σx² − (Σx)²]. Σx = 4 ve Σx² = 10. Pay −4 × $y0 − $y1 + 5 × $y3 = $n, payda 14, dolayısıyla β = ${_fraction(n, 14)}.',
        tab,
      );
    },
    bloom: BloomLevel.yaratma,
    creation: (item, index) => CreationTask(
      'Tablodaki üç x değerini koruyarak üç yeni y değeri tasarlayın. Yeni veri kümesinin en küçük kareler eğimi başlangıçtakiyle aynı kalsın, sabit terimi en az 2 birim artsın. Yeni tabloyu verin ve seçiminizin her iki koşulu nasıl karşıladığını açıklayın.',
      [
        'x = 0, 1 ve 3 için özgün üç gözlem çifti verir.',
        'Yeni ve ilk eğimin eşitliğini sayısal hesapla veya geçerli bir cebirsel gerekçeyle gösterir.',
        'İki sabit terim arasındaki artışın en az 2 olduğunu veri üzerinden doğrular.',
      ],
    ),
  ),
  _family('direction', 'Birim yönde türev', _uni, _m, _d, (a, b, c) {
    final gx = a + 1, gy = b + 1, k = c + 1;
    final n = gx * (k * k - 1) + gy * 2 * k, d = k * k + 1;
    final v = _diagram('Yön ve bileşenleri', [
      _line(18, 75, 86, 75, color: 'blue'),
      _line(18, 75, 18, 16, color: 'blue'),
      DiagramElement(
        shape: 'arrow',
        x: 18,
        y: 75,
        endX: 18 + 53 * (k * k - 1) / d,
        endY: 75 - 49 * (2 * k) / d,
        color: 'gold',
      ),
      _label(54, 12, 'v = (${k * k - 1}, ${2 * k})'),
      _label(87, 84, 'x'),
      _label(12, 15, 'y'),
    ]);
    return _ratio(
      'P noktasında ∇f(P) = ($gx, $gy). Şekilde bileşenleri verilen v yönündeki birim yönlü türev kaçtır?',
      n,
      d,
      [(n, 1), (gx * (k * k - 1) - gy * 2 * k, d), (gx + gy, d)],
      'v’nin normu √(${k * k - 1}² + ${2 * k}²) = $d. Birim yönlü türev ∇f·v/‖v‖ = ($gx × ${k * k - 1} + $gy × ${2 * k})/$d = ${_fraction(n, d)}.',
      v,
    );
  }),
  _family('hessian', 'İkinci türev testi', _uni, _h, _t, (a, b, c) {
    final p = a + 2, q = b + 2, r = c + 1, ans = p * q - r * r;
    final v = _table(
      'Kritik noktada türevler',
      ['Türev', 'Değer'],
      [
        ['fₓₓ', p],
        ['fₓᵧ = fᵧₓ', r],
        ['fᵧᵧ', q],
      ],
    );
    return _num(
      'İki değişkenli fonksiyon için ikinci türev testinde kullanılan Hessian determinantı D kaçtır?',
      ans,
      [p * q + r * r, p * q - r, p + q],
      'D = fₓₓ fᵧᵧ − (fₓᵧ)² = $p × $q − $r² = $ans. ${ans > 0
          ? 'İlk köşegen terimi pozitif olduğundan kritik nokta yerel minimumdur.'
          : ans < 0
          ? 'Negatif determinant kritik noktanın eyer noktası olduğunu gösterir.'
          : 'Sıfır determinant nedeniyle ikinci türev testi tek başına sonuç vermez.'}',
      v,
    );
  }),
  _family('chain', 'Bir eğri boyunca değişim', _uni, _m, _t, (a, b, c) {
    final gx = a + 2, gy = b + 1, s = c + 1, n = gx * s - 2 * gy;
    final v = _table(
      'Aynı andaki yerel ölçümler',
      ['Büyüklük', 'Değer'],
      [
        ['∂T/∂x', gx],
        ['∂T/∂y', gy],
        ['dx/dt', s],
        ['dy/dt', -2],
      ],
    );
    return _num(
      'T(x, y) sıcaklığı içinde hareket eden bir sensör için tabloda anlık türevler verilmiştir. Sensörün ölçtüğü dT/dt kaçtır?',
      n,
      [gx * s + 2 * gy, gx + gy, s - 2],
      'Çok değişkenli zincir kuralına göre dT/dt = Tₓ x′ + Tᵧ y′. Verilerle $gx × $s + $gy × (−2) = $n.',
      v,
    );
  }),
  _family(
    'simpson',
    'İntegral raporunun hata ölçütüyle değerlendirilmesi',
    _uni,
    _m,
    _l,
    (a, b, c) {
      final x = a + 2, y = b + 1, z = c + 3, n = x + 4 * y + z;
      final v = _plot(
        _l,
        'Düğüm noktalarındaki f değerleri',
        ['x = 0', 'x = 1', 'x = 2'],
        [x, y, z],
        '',
      );
      final difference = (x - 2 * y + z).abs();
      final verdict = difference <= 3 ? 'Kabul' : 'Ret';
      final opposite = difference <= 3 ? 'Ret' : 'Kabul';
      final error = _fraction(difference, 6);
      final other = _fraction(difference + 2, 6);
      return _choose(
        'Derecesi en fazla iki olan f için bir rapor, [0, 2] integralini grafikteki düğümler arasında iki yamukla hesaplıyor. Mutlak hata en çok 1/2 ise rapor kabul edilecek. Kesin integral ile karşılaştırıldığında doğru karar ve hata hangisidir?',
        '$verdict · hata $error',
        [
          '$opposite · hata $error',
          '$verdict · hata $other',
          '$opposite · hata $other',
        ],
        'İkinci dereceye kadar Simpson kuralı kesindir: I = ($x + 4 × $y + $z)/3 = ${_fraction(n, 3)}. İki yamuğun toplamı ($x + 2 × $y + $z)/2 = ${_fraction(x + 2 * y + z, 2)}. Mutlak fark $error olduğu için karar: $verdict.',
        v,
      );
    },
    bloom: BloomLevel.degerlendirme,
  ),
  _family('double_integral', 'Üçgensel bölgede çift integral', _uni, _h, _d, (
    a,
    b,
    c,
  ) {
    final x = a + 2, y = b + 2, k = c + 1, n = k * x * x * y;
    final v = _diagram('D bölgesinin eksen kesişimleri', [
      _line(20, 78, 83, 78),
      _line(20, 78, 20, 18),
      _line(20, 18, 83, 78, color: 'gold'),
      _label(16, 87, 'O'),
      _label(77, 89, '($x, 0)'),
      _label(28, 11, '(0, $y)'),
      _label(39, 60, 'D'),
    ]);
    return _ratio(
      'Şekildeki üçgensel D bölgesinde yoğunluk ρ(x, y) = ${k}x olsun. ∬ᴅ ρ(x, y) dA kaçtır?',
      n,
      6,
      [(n, 2), (k * x * y, 2), (n, 3)],
      'Üst sınır y = $y(1 − x/$x) olur. x = 0 ile $x arasında ${k}x × $y(1 − x/$x) integre edilince $k × $x² × $y/6 = ${_fraction(n, 6)} bulunur.',
      v,
    );
  }, bloom: BloomLevel.analiz),
  _family('midpoint_rule', 'Orta nokta karelemesi', _uni, _m, _b, (a, b, c) {
    final x = a + 1, y = b + 2, z = c + 1, n = 2 * (x + y + z);
    final v = _plot(
      _b,
      'Orta noktalardaki f değerleri',
      ['x = 1', 'x = 3', 'x = 5'],
      [x, y, z],
      '',
    );
    return _num(
      'Grafikte orta nokta değerleri verilen fonksiyonun [0, 6] aralığındaki integralini üç eşit alt aralıkla orta nokta kuralından hesaplayınız. Yaklaşık değer kaçtır?',
      n,
      [x + y + z, 3 * (x + y + z), 2 * (x + z)],
      'Her alt aralığın genişliği 2’dir. Orta nokta toplamı 2 × ($x + $y + $z) = $n olur.',
      v,
    );
  }),
  _family('improper', 'Sonsuz aralıkta yakınsak integral', _uni, _h, null, (
    a,
    b,
    c,
  ) {
    final factor = a + 1, lower = b + 2, shift = c + 1;
    final d = (lower + shift) * (lower + shift);
    return _ratio(
      'x = $lower sınırından +∞’a kadar $factor/(x + $shift)³ fonksiyonunun genelleştirilmiş integrali kaçtır?',
      factor,
      2 * d,
      [(factor, d), (factor, 2 * (lower + shift)), (2 * factor, d)],
      'İlkel fonksiyon −$factor/[2(x + $shift)²] olur. Sonsuzdaki limit sıfır olduğu için integral $factor/[2 × ${lower + shift}²] = ${_fraction(factor, 2 * d)}.',
    );
  }),
  _family('ode', 'Ayırılabilir diferansiyel denklem', _uni, _m, null, (
    a,
    b,
    c,
  ) {
    final init = a + 2, rate = b + 1, time = c + 1;
    final result = '$init·e^${rate * time}';
    return _choose(
      'y′ = ${rate}y, y(0) = $init başlangıç değer probleminin çözümü için y($time) nedir?',
      result,
      [
        '$init·e^${rate + time}',
        'e^${init + rate * time}',
        '${init + rate * time}',
        '${init + 1}·e^${rate * time}',
      ],
      'dy/y = $rate dt eşitliği integre edilirse y(t) = Ce^(${rate}t) olur. Başlangıç değeri C = $init verdiğinden y($time) = $result.',
      null,
    );
  }),
  _family('markov', 'İki durumlu Markov zinciri', _uni, _h, _t, (a, b, c) {
    final l = a + 10, r = b + 55, initial = (c + 1) * 5;
    final n = initial * l + (100 - initial) * r;
    final v = _table(
      'Bir adımlık geçişler (%)',
      ['Bugün', 'Yarın A', 'Yarın B'],
      [
        ['A', l, 100 - l],
        ['B', r, 100 - r],
      ],
    );
    return _ratio(
      'Bugün A durumunda bulunma olasılığı %$initial. Tablodaki geçişlere göre yarın A durumunda bulunma olasılığı yüzde kaçtır?',
      n,
      100,
      [
        (l + r, 2),
        (initial * l, 100),
        (initial * r + (100 - initial) * l, 100),
      ],
      'Bugünkü durumlar üzerinden toplam olasılık uygulanır. Yüzde olarak sonuç ($initial × $l + ${100 - initial} × $r)/100 = ${_fraction(n, 100)}.',
      v,
    );
  }),
  _family('bayes', 'Kusur gözleminden kaynağa Bayes çıkarımı', _uni, _h, _t, (
    a,
    b,
    c,
  ) {
    final share = a + 25,
        x = b + 2,
        y = c + 1,
        n = share * x,
        d = n + (100 - share) * y;
    final v = _table(
      'Üretim payları ve kusur oranları',
      ['Hat', 'Üretim payı', 'Kusurlu'],
      [
        ['A', '%$share', '%$x'],
        ['B', '%${100 - share}', '%$y'],
      ],
    );
    return _ratio(
      'Tüm üretimden rastgele seçilen parçanın kusurlu olduğu biliniyor. Parçanın A hattından çıkmış olma olasılığı kaçtır?',
      n,
      d,
      [(share, 100), (x, x + y), (n, 10000)],
      'A hattından gelip kusurlu olma ağırlığı $share × $x = $n. Her iki hattın toplam kusur ağırlığı $d. Bayes kuralıyla istenen olasılık $n/$d = ${_fraction(n, d)}.',
      v,
    );
  }),
  _family('expectation', 'Kesikli dağılımda beklenen maliyet', _uni, _m, _t, (
    a,
    b,
    c,
  ) {
    final x = a + 1,
        y = b + 3,
        loss = c + 2,
        n = -loss * x + 2 * loss * y,
        d = x + y + 5;
    final v = _table(
      'Eş olasılıklı durumların dağılımı',
      ['Net kazanç (TL)', 'Durum sayısı'],
      [
        [-loss, x],
        [0, 5],
        [2 * loss, y],
      ],
    );
    return _ratio(
      'Tablodaki temel durumların her biri eş olasılıklıdır. Bir denemedeki net kazancın beklenen değeri kaç TL’dir?',
      n,
      d,
      [(loss * x + 2 * loss * y, d), (n, 3), (n, x + y)],
      'Eş olasılıklı $d durumun kazanç toplamı (−$loss) × $x + 0 × 5 + ${2 * loss} × $y = $n. Beklenen değer ${_fraction(n, d)} TL’dir.',
      v,
    );
  }),
  _family('covariance', 'Anakütle kovaryansı', _uni, _h, _t, (a, b, c) {
    final x = a + 1, y = b + 2, z = c + 1;
    // E[XY] − E[X]E[Y], where X is sampled at 0,1,3.
    final n = -4 * x - y + 5 * z;
    final v = _table(
      'Üç eş olasılıklı gözlem',
      ['X', 'Y'],
      [
        [0, x],
        [1, y],
        [3, z],
      ],
    );
    return _ratio(
      'Tablodaki üç çift tüm anakütleyi oluşturuyor. X ile Y arasındaki anakütle kovaryansı kaçtır?',
      n,
      9,
      [(n, 6), (y + 3 * z, 3), (n, 3)],
      'Cov(X,Y) = E[XY] − E[X]E[Y]. E[XY] = (${y + 3 * z})/3, E[X] = 4/3, E[Y] = ${x + y + z}/3. Fark ${_fraction(n, 9)} olur.',
      v,
    );
  }),
  _family('hypergeom', 'Sonlu anakütleden örneklem', _uni, _h, _b, (a, b, c) {
    final good = a + 6, bad = b + 6, k = c + 2, t = good + bad;
    final n = good * _comb(bad, k - 1), d = _comb(t, k);
    final favourable = n;
    final v = _plot(
      _b,
      'Partideki bileşenler',
      ['A tipi', 'B tipi'],
      [good, bad],
      'adet',
    );
    return _ratio(
      'Grafikteki partiden geri koymadan $k bileşen rastgele seçiliyor. Seçilenler arasında tam bir A tipi bileşen bulunma olasılığı kaçtır?',
      favourable,
      d,
      [(good, t), (favourable, d + good), (favourable + 1, d), (bad, t)],
      k - 1 > bad
          ? 'Tam bir A seçilirse ${k - 1} B gerekir. Partide sadece $bad B bulunduğu için bu olayın olasılığı sıfırdır.'
          : 'Bir A için $good seçim, ${k - 1} B için ${_comb(bad, k - 1)} seçim vardır. $d eş olasılıklı alt kümeden $favourable tanesi uygundur. Sonuç ${_fraction(favourable, d)}.',
      v,
    );
  }),
  _family('poisson_condition', 'Koşullu Poisson süreci', _uni, _h, null, (
    a,
    b,
    c,
  ) {
    final duration = a + 26, window = b + 2, k = c + 2;
    final n = k * window, d = duration;
    return _ratio(
      'Sabit hızlı bir Poisson sürecinde $duration dakikada tam $k çağrı geldiği biliniyor. Bu aralığın ilk $window dakikasında gelen çağrı sayısının koşullu beklenen değeri kaçtır?',
      n,
      d,
      [
        (k * (duration - window), duration),
        (window, duration),
        (k * duration, window),
      ],
      'Toplam sayı verilince her çağrının zamanının ilk $window dakikaya düşme olasılığı $window/$duration olur. Koşullu sayı Binom($k, $window/$duration) dağılımlıdır. Ortalama ${_fraction(n, d)}.',
    );
  }),
  _family('jacobian', 'Değişken dönüşümünde Jacobian', _uni, _h, _t, (a, b, c) {
    final x = a + 2, y = b + 2, k = c + 1, det = 4 * x * y + k * k;
    final v = _table(
      'Parametre noktasında dönüşüm',
      ['Bileşen', 'Kural'],
      [
        ['x', 'u² + ${k}v'],
        ['y', 'v² − ${k}u'],
      ],
    );
    return _num(
      'Tablodaki dönüşümde (u, v) = ($x, $y) noktasında |∂(x,y)/∂(u,v)| kaçtır?',
      det,
      [4 * x * y - k * k, 2 * x + 2 * y, 4 * x * y],
      'Jacobian matrisinin satırları (2u, $k) ve (−$k, 2v) olur. Mutlak determinant |4uv + $k²| = 4 × $x × $y + ${k * k} = $det.',
      v,
    );
  }),
  _family('newton', 'Newton yönteminde bir yineleme', _uni, _h, _t, (a, b, c) {
    final current = a + 2,
        fx = b + 1,
        derivative = c + 2,
        n = current * derivative - fx;
    final v = _table(
      'Yerel fonksiyon bilgisi',
      ['x₀', 'f(x₀)', 'f′(x₀)'],
      [
        [current, fx, derivative],
      ],
    );
    return _ratio(
      'f(x) = 0 denklemini çözerken tablodaki noktadan bir Newton adımı atılıyor. Yeni yaklaşım x₁ kaçtır?',
      n,
      derivative,
      [
        (current * derivative + fx, derivative),
        (current * fx - derivative, fx),
        (fx, derivative),
      ],
      'Newton adımı x₁ = x₀ − f(x₀)/f′(x₀) biçimindedir. Buna göre x₁ = $current − $fx/$derivative = ${_fraction(n, derivative)}.',
      v,
    );
  }),
  _family('euler', 'İleri Euler integrasyonu', _uni, _m, _t, (a, b, c) {
    final initial = a + 2,
        increment = b + 1,
        denom = c + 2,
        n = initial * denom + increment + initial;
    final v = _table(
      'Başlangıç ve adım verileri',
      ['t₀', 'y₀', 'h'],
      [
        [increment, initial, '1/$denom'],
      ],
    );
    return _ratio(
      'y′ = t + y diferansiyel denklemi için tablodan başlayarak bir ileri Euler adımı uygulanıyor. Elde edilen y₁ kaçtır?',
      n,
      denom,
      [
        (initial + increment, denom),
        (initial * denom + increment, denom),
        (initial * denom - increment - initial, denom),
      ],
      'Başlangıç eğimi $increment + $initial = ${increment + initial}. Euler kuralı y₁ = y₀ + h f(t₀,y₀) verdiğinden y₁ = $initial + ${increment + initial}/$denom = ${_fraction(n, denom)}.',
      v,
    );
  }),
  _family('lagrange', 'Kısıt altında iki kare toplamı', _uni, _h, null, (
    a,
    b,
    c,
  ) {
    final p = a + 1, q = b + 2, t = c + 3, n = t * t, d = p * p + q * q;
    return _ratio(
      'Gerçek x, y değerleri ${p}x + ${q}y = $t koşulunu sağlıyor. x² + y² ifadesinin minimum değeri kaçtır?',
      n,
      d,
      [(t, d), (n, p + q), (n, (p + q) * (p + q))],
      'Cauchy-Schwarz eşitsizliği $t² ≤ ($p² + $q²)(x² + y²) verir. (x,y), ($p,$q) ile aynı doğrultuda seçilince eşitlik sağlanır. Minimum ${_fraction(n, d)}.',
    );
  }, bloom: BloomLevel.analiz),
  _family('geom_tail', 'Yakınsak geometrik serinin kuyruğu', _uni, _m, null, (
    a,
    b,
    c,
  ) {
    final first = a + 1, den = b + 2, k = c + 2;
    var power = 1;
    // Keep denominators exact in both native Dart and web integer arithmetic.
    for (var j = 0; j < k - 1; j++) {
      power *= den;
    }
    final d = power * (den - 1);
    return _ratio(
      'İlk terimi $first ve ortak oranı 1/$den olan sonsuz geometrik seride ilk $k terim çıkarılıyor. Geri kalan terimlerin toplamı kaçtır?',
      first,
      d,
      [(first, den * d), (first * den, d), (first, power)],
      'İlk kalan terim $first/$den^$k olur. Bunu 1 − 1/$den değerine bölünce kuyruk toplamı $first/[$den^${k - 1} × (${den - 1})] = ${_fraction(first, d)} elde edilir.',
    );
  }),
];
