import 'dart:math' as math;

import 'common.dart';

// A reversible mixed-radix enumeration gives every case its own data set.
// All three coordinates are represented in the problem or its figure.
typedef _Builder = AdvancedItem Function(int a, int b, int c);

AdvancedFamily _family(
  String key,
  String title,
  Topic topic,
  StudyLevel level,
  VisualKind kind,
  _Builder builder, {
  Difficulty difficulty = Difficulty.hard,
  int count = 6247,
  bool shortAnswer = true,
  BloomLevel bloom = BloomLevel.uygulama,
  CreationTask Function(AdvancedItem, int)? creation,
}) {
  return AdvancedFamily(
    key: 'applied_$key',
    title: title,
    topic: topic,
    level: level,
    difficulty: difficulty,
    count: count,
    shortAnswer: shortAnswer,
    bloom: bloom,
    creation: creation,
    visualKind: kind,
    build: (index) {
      final n = (index * 3793) % 6400;
      return builder(n % 20, n ~/ 20 % 20, n ~/ 400);
    },
  );
}

String _fmt(num value, [int places = 2]) {
  final scale = math.pow(10, places).toDouble();
  final rounded = (value.abs() * scale + 0.5 + 1e-9).floor() / scale;
  final s = (value < 0 ? -rounded : rounded).toStringAsFixed(places);
  final trimmed = s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  return (trimmed == '-0' ? '0' : trimmed).replaceAll('.', ',');
}

QuestionVisual _table(
  String title,
  List<String> headings,
  List<List<Object>> data,
) => QuestionVisual(
  kind: VisualKind.table,
  title: title,
  summary: '',
  columns: headings,
  rows: [
    for (final row in data) [for (final v in row) '$v'],
  ],
);

QuestionVisual _chart(
  VisualKind kind,
  String title,
  List<String> labels,
  List<num> values,
  String unit,
) => QuestionVisual(
  kind: kind,
  title: title,
  summary: '',
  labels: labels,
  values: [for (final v in values) v.toDouble()],
  unit: unit,
);

QuestionVisual _bars(
  String title,
  List<String> labels,
  List<num> values,
  String unit,
) => _chart(VisualKind.barChart, title, labels, values, unit);
QuestionVisual _line(
  String title,
  List<String> labels,
  List<num> values,
  String unit,
) => _chart(VisualKind.lineChart, title, labels, values, unit);

QuestionVisual _chain(String title, List<String> labels) {
  final centers = [16.0, 50.0, 84.0];
  return QuestionVisual(
    kind: VisualKind.diagram,
    title: title,
    summary: '',
    elements: [
      for (int i = 0; i < 2; i++)
        DiagramElement(
          shape: 'arrow',
          x: centers[i] + 13,
          y: 50,
          endX: centers[i + 1] - 13,
          endY: 50,
        ),
      for (int i = 0; i < 3; i++)
        DiagramElement(
          shape: 'rectangle',
          x: centers[i],
          y: 50,
          width: 25,
          height: 35,
          label: labels[i],
          color: ['blue', 'gold', 'mint'][i],
        ),
    ],
  );
}

AdvancedItem _num(
  String prompt,
  num answer,
  List<num> candidates,
  String explanation,
  QuestionVisual visual, {
  String unit = '',
  int places = 2,
  num step = 1,
  num? low = 0,
  num? high,
}) {
  String render(num v) => unit == '%'
      ? '%${_fmt(v, places)}'
      : '${_fmt(v, places)}${unit.isEmpty ? '' : ' $unit'}';
  final correct = render(answer);
  final wrong = <String>{};
  for (final value in [
    ...candidates,
    for (int k = 1; k <= 8; k++) ...[answer - step * k, answer + step * k],
  ]) {
    if (!value.isFinite ||
        (low != null && value < low) ||
        (high != null && value > high))
      continue;
    final label = render(value);
    if (label != correct) wrong.add(label);
    if (wrong.length == 3) break;
  }
  if (wrong.length != 3) throw StateError('Yetersiz seçenek: $prompt, $answer');
  return AdvancedItem(
    prompt,
    correct,
    wrong.toList(),
    explanation,
    visual: visual,
  );
}

String _fraction(int x, int y) {
  final g = x.gcd(y);
  final divisor = y ~/ g;
  return divisor == 1 ? '${x ~/ g}' : '${x ~/ g}/$divisor';
}

AdvancedItem _ratio(
  String p,
  int n,
  int d,
  List<(int, int)> errors,
  String e,
  QuestionVisual v,
) {
  final correct = _fraction(n, d);
  final wrong = <String>{};
  for (final (x, y) in [
    ...errors,
    (n + 1, d),
    (n - 1, d),
    (n, d + 1),
    (n, d + 2),
    (n, d + 3),
    (n + 2, d + 3),
  ]) {
    if (x < 0 || y <= 0 || x > y) continue;
    final text = _fraction(x, y);
    if (text != correct) wrong.add(text);
    if (wrong.length == 3) break;
  }
  if (wrong.length != 3) throw StateError('Eksik kesir: $p');
  return AdvancedItem(p, correct, wrong.toList(), e, visual: v);
}

AdvancedItem _prefix(int a, int b, int c) {
  final t = 12 + a, u = 15 + b, v = 8 + c;
  final sums = [t, t + u, t + u + v];
  final figure = _line(
    'Biriken kayıt sayısı',
    ['08.00', '10.00', '12.00'],
    sums,
    'kayıt',
  );
  final last = (a + c).isEven;
  final count = last ? v : u + v;
  final hours = last ? 2 : 4;
  return _num(
    last
        ? 'Saat 10.00 ile 12.00 arasındaki ortalama kayıt hızı kaç kayıt/saattir?'
        : 'Saat 08.00 ile 12.00 arasındaki ortalama kayıt hızı kaç kayıt/saattir? Sonucu iki ondalığa yuvarlayın.',
    count / hours,
    [sums.last / hours, count, last ? u : v, count / (hours + 1)],
    'Kümülatif sayacın iki okuması arasındaki fark $count kayıttır. Bunu geçen $hours saate bölünce ${_fmt(count / hours)} kayıt/saat bulunur.',
    figure,
    unit: 'kayıt/saat',
    step: 0.5,
  );
}

AdvancedItem _critical(int a, int b, int c) {
  final left = 8 + a, right = 6 + b, join = 2 + c;
  final v = QuestionVisual(
    kind: VisualKind.diagram,
    title: 'Paralel iş akışı',
    summary: '',
    elements: [
      for (final y in [25.0, 75.0]) ...[
        DiagramElement(shape: 'arrow', x: 24, y: 50, endX: 40, endY: y),
        DiagramElement(shape: 'arrow', x: 60, y: y, endX: 76, endY: 50),
      ],
      const DiagramElement(
        shape: 'rectangle',
        x: 12,
        y: 50,
        width: 22,
        height: 25,
        label: 'Başlat',
      ),
      DiagramElement(
        shape: 'rectangle',
        x: 50,
        y: 25,
        width: 23,
        height: 24,
        label: 'A · $left sn',
        color: 'blue',
      ),
      DiagramElement(
        shape: 'rectangle',
        x: 50,
        y: 75,
        width: 23,
        height: 24,
        label: 'B · $right sn',
        color: 'mint',
      ),
      DiagramElement(
        shape: 'rectangle',
        x: 87,
        y: 50,
        width: 23,
        height: 27,
        label: 'C · $join sn',
        color: 'gold',
      ),
    ],
  );
  final longest = math.max(left, right);
  return _num(
    'A ve B farklı işlemcilerde aynı anda başlar. C, ikisi de bitince çalışır. Başlatma süresi önemsizse en erken bitiş kaç saniye sonradır?',
    longest + join,
    [left + right + join, math.min(left, right) + join, longest, left + right],
    'Birleşme noktasında daha uzun dal beklenir. max($left, $right) + $join = ${longest + join} saniye.',
    v,
    unit: 'sn',
  );
}

AdvancedItem _runLength(int a, int b, int c) {
  final runs = [3 + a, 4 + b, 3 + c];
  final total = runs.reduce((x, y) => x + y);
  final v = _bars(
    'Ardışık tek renkli pikseller',
    ['Gri', 'Mavi', 'Beyaz'],
    runs,
    'piksel',
  );
  return _num(
    'Ham görüntüde her piksel bir bayttır. Sıkıştırmada her kesintisiz renk bloğu için bir renk baytı ve bir uzunluk baytı kullanılıyor. Başlık yoksa kaç bayt tasarruf edilir?',
    total - 6,
    [total - 3, total, 6, total + 6],
    'Üç renk bloğu sıkıştırılmış biçimde 3 × 2 = 6 bayt tutar. Ham uzunluk $total bayt olduğundan kazanç ${total - 6} bayttır.',
    v,
    unit: 'bayt',
  );
}

AdvancedItem _matrix(int a, int b, int c) {
  final m = 4 + a, k = 5 + b, n = 3 + c, p = 8 + (a + 2 * b + c) % 13;
  final l = m * k * n + m * n * p, r = k * n * p + m * k * p;
  final v = _table(
    'Çarpılacak matrisler',
    ['Matris', 'Satır', 'Sütun'],
    [
      ['A', m, k],
      ['B', k, n],
      ['C', n, p],
    ],
  );
  return _num(
    'A × B × C çarpımında klasik matris çarpımı kullanılıyor. Parantezler en ekonomik biçimde yerleştirilirse kaç skaler çarpma gerekir?',
    math.min(l, r),
    [math.max(l, r), m * k * n, k * n * p, m * k * n * p],
    '(AB)C için $m × $k × $n + $m × $n × $p = $l işlem gerekir. A(BC) için $k × $n × $p + $m × $k × $p = $r gerekir. Küçük maliyet seçilir.',
    v,
    unit: 'çarpma',
  );
}

AdvancedItem _sparse(int a, int b, int c) {
  final rows = 16 + a, cols = 18 + b, nz = 20 + c;
  final raw = rows * cols * 8, csr = nz * 12 + 4 * (rows + 1);
  final v = _table(
    'Seyrek matrisin yapısı',
    ['Özellik', 'Değer'],
    [
      ['Satır', rows],
      ['Sütun', cols],
      ['Sıfır olmayan öğe', nz],
    ],
  );
  return _num(
    'Yoğun gösterimde her hücre 8 bayttır. CSR biçiminde her dolu öğe için 8 bayt değer, 4 bayt sütun indisi ve bütün matris için (satır sayısı + 1) adet 4 baytlık satır işaretçisi tutulur. CSR kaç bayt kazandırır?',
    raw - csr,
    [raw - nz * 8, raw - nz * 12, raw - csr + 4, csr],
    'Yoğun matris $raw bayt, CSR ise $nz × 12 + ${rows + 1} × 4 = $csr bayt tutar. Fark ${raw - csr} bayttır.',
    v,
    unit: 'bayt',
  );
}

AdvancedItem _block(int a, int b, int c) {
  final size = [64, 128, 256, 512][c % 4];
  final offset = size * (1 + c ~/ 4) + a * 3;
  final length = 25 + b * 15 + c;
  final first = offset ~/ size, last = (offset + length - 1) ~/ size;
  final v = _table(
    'Bayt adresleme',
    ['Alan', 'Değer'],
    [
      ['Blok boyutu', size],
      ['Başlangıç adresi', offset],
      ['Okuma uzunluğu', length],
    ],
  );
  return _num(
    '0 numaralı bayt ilk bloğun başıdır. İstenen bayt aralığını okumak için en az kaç farklı bloğa erişilir?',
    last - first + 1,
    [
      last - first,
      last + 1,
      (length / size).ceil(),
      (length / size).ceil() + 1,
    ],
    'İlk blok ⌊$offset/$size⌋ = $first, son blok ⌊${offset + length - 1}/$size⌋ = $last. Uçlar dâhil ${last - first + 1} blok vardır.',
    v,
    unit: 'blok',
    low: 1,
  );
}

AdvancedItem _queue(int a, int b, int c) {
  final jobs = [4 + a, 5 + b, 6 + c], quota = [12, 9, 11];
  var q = 0, peak = 0;
  final remaining = <int>[];
  for (var i = 0; i < 3; i++) {
    q = math.max(0, q + jobs[i] - quota[i]);
    remaining.add(q);
    peak = math.max(q, peak);
  }
  final v = _table(
    'Üç dönemlik iş kuyruğu',
    ['Dönem', 'Gelen', 'Kapasite'],
    [
      for (var i = 0; i < 3; i++) [i + 1, jobs[i], quota[i]],
    ],
  );
  final end = (a + b).isEven, answer = end ? q : peak;
  return _num(
    'Boş başlayan kuyruğa işler dönem başında gelir. Kullanılmayan işleme kapasitesi devretmez. ${end ? 'Üçüncü dönem sonunda' : 'Dönem sonları karşılaştırıldığında en kalabalık anda'} kuyrukta kaç iş vardır?',
    answer,
    [
      q,
      peak,
      jobs.reduce((x, y) => x + y) - 32,
      remaining[1],
      answer + quota.last,
    ],
    'Her dönemde bekleyen + gelen − kapasite hesaplanır ve negatif sonuç sıfıra çekilir. Dönem sonları ${remaining.join(', ')} iştir.',
    v,
    unit: 'iş',
  );
}

AdvancedItem _inversions(int a, int b, int c) {
  var rank = (a + 20 * b + 400 * c) * 3;
  final pool = [1, 2, 3, 4, 5, 6, 7, 8], order = <int>[];
  for (final f in [5040, 720, 120, 24, 6, 2, 1, 1]) {
    order.add(pool.removeAt(rank ~/ f));
    rank %= f;
  }
  var inversions = 0;
  final counts = <int>[];
  for (var i = 0; i < order.length; i++) {
    final n = order.skip(i + 1).where((x) => x < order[i]).length;
    inversions += n;
    counts.add(n);
  }
  final v = _table(
    'Girdi dizisi',
    ['Konum', 'Değerler'],
    [
      ['1–4', order.take(4).join(' · ')],
      ['5–8', order.skip(4).join(' · ')],
    ],
  );
  return _num(
    'Komşu iki öğenin yerini değiştirme işlemine izin veriliyor. Diziyi küçükten büyüğe sıralamak için en az kaç değişim gerekir?',
    inversions,
    [
      order.length - 1,
      counts.where((n) => n > 0).length,
      28 - inversions,
      inversions + 2,
    ],
    'Her ters çift bir komşu değişimi gerektirir. Sağdaki küçük öğe sayıları ${counts.join(', ')} olup toplam $inversions eder.',
    v,
    unit: 'değişim',
    high: 28,
  );
}

AdvancedItem _interval(int a, int b, int c) {
  final x = 8 + a, y = 9 + b, z = 12 + c, w = 10 + (a + 2 * b + c) % 17;
  final v = _table(
    'Tek salon için atölye talepleri',
    ['Saat', 'Katılımcı'],
    [
      ['09–11', x],
      ['11–13', y],
      ['09–12', z],
      ['12–13', w],
    ],
  );
  final pairs = [x + y, x + w, z + w];
  final best = pairs.reduce(math.max);
  final choice = (a + 2 * b + c) % 5;
  const plans = [
    '09–11 ile 11–13',
    '09–11 ile 12–13',
    '09–12 ile 12–13',
    '09–11 ile 09–12',
    '11–13 ile 12–13',
  ];
  const verdicts = [
    'Önerilen iki atölye çakıştığı için program uygulanamaz.',
    'Program uygulanabilir, ancak başka bir seçim daha fazla katılımcıya ulaşır.',
    'Bu program en yüksek katılıma ulaşan tek seçimdir.',
    'Bu program en yüksek katılımı başka bir seçimle paylaşır.',
  ];
  final key = choice >= 3
      ? 0
      : pairs[choice] < best
      ? 1
      : pairs.where((v) => v == best).length == 1
      ? 2
      : 3;
  return AdvancedItem(
    'Yönetici ${plans[choice]} atölyelerini tek salona almayı öneriyor. Biten atölyenin hemen ardından diğeri başlayabiliyor. Çakışmadan en fazla katılımcıya ulaşma ölçütüne göre öneriyi nasıl değerlendirirsiniz?',
    verdicts[key],
    [
      for (var i = 0; i < 4; i++)
        if (i != key) verdicts[i],
    ],
    'Uygulanabilir ikililer 09–11 ile 11–13 (${pairs[0]} kişi), 09–11 ile 12–13 (${pairs[1]} kişi) ve 09–12 ile 12–13 (${pairs[2]} kişi). En yüksek katılım $best kişidir. ${verdicts[key]}',
    visual: v,
  );
}

AdvancedItem _backpack(int a, int b, int c) {
  final weights = [2, 3, 4, 5],
      benefits = [5 + a, 6 + b, 7 + c, 10 + (a + b + c) % 18],
      limit = 7 + (a + c) % 3;
  final totals = <int>{}, names = ['A', 'B', 'C', 'D'];
  var best = 0;
  String selected = '';
  for (var subset = 1; subset < 16; subset++) {
    var w = 0, u = 0;
    final picked = <String>[];
    for (var i = 0; i < 4; i++) {
      if ((subset & (1 << i)) != 0) {
        w += weights[i];
        u += benefits[i];
        picked.add(names[i]);
      }
    }
    if (w <= limit) {
      totals.add(u);
      if (u > best) {
        best = u;
        selected = picked.join(' + ');
      }
    }
  }
  final v = _table(
    'Çevrimdışı harita paketleri',
    ['Paket', 'Boyut (GB)', 'Kapsam puanı'],
    [
      for (var i = 0; i < 4; i++) [names[i], weights[i], benefits[i]],
    ],
  );
  return _num(
    'Bir cihazda haritalara $limit GB ayrılabilir. Paketler bölünemez, her biri en çok bir kez indirilebilir ve kapsam puanları toplanır. Ulaşılabilen en yüksek puan nedir?',
    best,
    (totals.toList()..sort((x, y) => y.compareTo(x))),
    'Kapasiteyi aşmayan alt kümelerde puanları toplayınca en yüksek toplam $best olur. Bu toplamı sağlayan seçimlerden biri $selected.',
    v,
    unit: 'puan',
  );
}

AdvancedItem _f1(int a, int b, int c) {
  final tp = 18 + a, fp = 4 + b, fn = 3 + c;
  final v = _table(
    'Görüntü sınıflandırıcı',
    ['Sonuç', 'Görüntü'],
    [
      ['Doğru pozitif', tp],
      ['Yanlış pozitif', fp],
      ['Yanlış negatif', fn],
    ],
  );
  final den = 2 * tp + fp + fn;
  return _ratio(
    'Pozitif sınıf için kesinlik ve duyarlılığın harmonik ortalaması olan F1 skorunun tam değeri nedir?',
    2 * tp,
    den,
    [(tp, tp + fp), (tp, tp + fn), (tp, tp + fp + fn), (fp + fn, den)],
    'F1 = 2DP/(2DP + YP + YN). Sayılar yerleştirilirse ${2 * tp}/$den = ${_fraction(2 * tp, den)} bulunur.',
    v,
  );
}

AdvancedItem _merging(int a, int b, int c) {
  final sizes = [3 + a, 4 + b, 5 + c, 8 + (2 * a + b + c) % 17];
  final q = [...sizes];
  var total = 0;
  final merges = <int>[];
  while (q.length > 1) {
    q.sort();
    final sum = q.removeAt(0) + q.removeAt(0);
    total += sum;
    q.add(sum);
    merges.add(sum);
  }
  final v = _bars(
    'Birleştirilecek sıralı dosyalar',
    ['A', 'B', 'C', 'D'],
    sizes,
    'MB',
  );
  return _num(
    'İki dosyayı birleştirmenin maliyeti boyutlarının toplamına eşit. Oluşan dosya sonraki birleştirmeye katılabilir. Dört dosyayı teke indirmek için en düşük toplam maliyet nedir?',
    total,
    [q.single, total - merges.first, 2 * q.single, total + merges.first],
    'Her adımda kalan en küçük iki dosyayı birleştirmek toplamı en aza indirir. Adım maliyetleri ${merges.join(' + ')} = $total MB.',
    v,
    unit: 'MB',
  );
}

AdvancedItem _weighted(int a, int b, int c) {
  final n = 10 + a, m = 13 + b, u = 40 + c, w = 65 + (a + b) % 16;
  final v = _table(
    'İki kurs grubunun sonuçları',
    ['Grup', 'Kişi', 'Ort. puan'],
    [
      ['Sabah', n, u],
      ['Akşam', m, w],
    ],
  );
  final mean = (n * u + m * w) / (n + m);
  return _num(
    'Bütün katılımcılar tek grup olarak ele alındığında ortalama puan nedir? Sonucu iki ondalığa yuvarlayın.',
    mean,
    [(u + w) / 2, (m * u + n * w) / (n + m), w, u],
    'Puan toplamları toplanıp toplam kişi sayısına bölünür. ($n × $u + $m × $w)/${n + m} = ${_fmt(mean)} puan.',
    v,
    unit: 'puan',
    step: 0.5,
  );
}

AdvancedItem _variance(int a, int b, int c) {
  final x = 30 + a, d = 2 + b, e = 2 + c;
  final data = [x - d, x, x + e];
  final v = _bars(
    'Üç tekrarda ölçülen uzunluk',
    ['I', 'II', 'III'],
    data,
    'mm',
  );
  final sum = d * d + d * e + e * e;
  return _num(
    'Bu üç bağımsız ölçüm için n − 1 paydalı örneklem varyansı kaç mm² olur? Sonucu iki ondalığa yuvarlayın.',
    sum / 3,
    [2 * sum / 9, math.sqrt(sum / 3), (d + e) * (d + e) / 2, sum],
    'Üç gözlemde kareli ikili farkların toplamı n(n − 1) = 6 ile bölünebilir. ($d² + $e² + ${d + e}²)/6 = ${_fmt(sum / 3)} mm².',
    v,
    unit: 'mm²',
    step: 0.5,
  );
}

AdvancedItem _difference(int a, int b, int c) {
  final x = 40 + a, y = 45 + b, change = 4 + c, control = 2 + (2 * a + b) % 15;
  final v = _table(
    'Ortalama yolculuk süresi (dk)',
    ['Hat', 'Önce', 'Sonra'],
    [
      ['Pilot', x, x - change],
      ['Karşılaştırma', y, y - control],
    ],
  );
  final result = control - change;
  return _num(
    'Önce her hattın sonrasından öncesini çıkarın. Pilot hattın değişiminden karşılaştırma hattının değişimi çıkarıldığında farkların farkı kaç dakikadır?',
    result,
    [-result, -change, -control, x - change - y + control],
    'Pilot hattın değişimi −$change dk, diğer hattın değişimi −$control dk. Fark (−$change) − (−$control) = $result dk.',
    v,
    unit: 'dk',
    low: null,
  );
}

AdvancedItem _regression(int a, int b, int c) {
  final x = 12 + a,
      y = 90 + 2 * b,
      slope = 2 + c,
      xx = 32 + (a + b) % 15,
      xy = xx * slope;
  final v = _table(
    'En küçük kareler özeti',
    ['Büyüklük', 'Değer'],
    [
      ['Ortalama x', x],
      ['Ortalama y', y],
      ['Merkezî çarpım toplamı Sxy', xy],
      ['Merkezî kare toplamı Sxx', xx],
    ],
  );
  final intercept = y - slope * x;
  return _num(
    'Sabit terimli basit doğrusal regresyonda tahmin doğrusu y = α + βx biçimindedir. Tablodan hesaplanan α kaçtır?',
    intercept,
    [slope, y + slope * x, y - x / slope, y],
    'Eğim Sxy/Sxx = $xy/$xx = $slope olur. Doğru ortalama noktasından geçtiği için α = $y − $slope × $x = $intercept.',
    v,
    low: null,
  );
}

AdvancedItem _confidence(int a, int b, int c) {
  final mean = 50 + a, sigma = 5 + b, root = 4 + c;
  final v = _table(
    'Rastgele örneklem',
    ['Özet', 'Değer'],
    [
      ['Ortalama (g)', mean],
      ['Bilinen anakütle σ (g)', sigma],
      ['Örneklem büyüklüğü', root * root],
    ],
  );
  final margin = 1.96 * sigma / root;
  final upper = (a + b + c).isEven;
  return _num(
    'Normal anakütlenin ortalaması için iki taraflı %95 güven aralığı kuruluyor (z = 1,96). ${upper ? 'Üst' : 'Alt'} sınır kaç gramdır? İki ondalığa yuvarlayın.',
    upper ? mean + margin : mean - margin,
    [
      upper ? mean - margin : mean + margin,
      upper ? mean + sigma : mean - sigma,
      upper
          ? mean + 1.96 * sigma / (root * root)
          : mean - 1.96 * sigma / (root * root),
    ],
    'Standart hata $sigma/√${root * root} olur. Sınır $mean ${upper ? '+' : '−'} 1,96 × $sigma/$root = ${_fmt(upper ? mean + margin : mean - margin)} g.',
    v,
    unit: 'g',
    step: 0.1,
  );
}

AdvancedItem _posterior(int a, int b, int c) {
  final nA = 22 + a, nB = 24 + b, badA = 2 + c, badB = 2 + (a + 2 * b) % 15;
  final v = _table(
    'İki atölyeden gelen parçalar',
    ['Atölye', 'Gelen', 'Kusurlu'],
    [
      ['A', nA, badA],
      ['B', nB, badB],
    ],
  );
  final bad = (a + c).isEven;
  final first = bad ? badA : nA - badA, second = bad ? badB : nB - badB;
  return _ratio(
    'İki atölyenin parçaları bir araya getiriliyor. Rastgele seçilen parçanın ${bad ? 'kusurlu' : 'kusursuz'} olduğu biliniyor. A atölyesinden gelmiş olma olasılığı nedir?',
    first,
    first + second,
    [(nA, nA + nB), (first, nA), (first, nA + nB), (second, first + second)],
    'Koşul nedeniyle yalnızca ${bad ? 'kusurlu' : 'kusursuz'} parçalar örnek uzayda kalır. Bunların $first tanesi A, $second tanesi B kaynaklıdır. Olasılık ${_fraction(first, first + second)}.',
    v,
  );
}

AdvancedItem _stratum(int a, int b, int c) {
  final sizes = [8 + a, 10 + b, 12 + c], n = sizes.reduce((x, y) => x + y);
  final same = sizes.fold(0, (s, v) => s + v * (v - 1)), den = n * (n - 1);
  final v = _bars(
    'Ankete katılan öğrenciler',
    ['Hazırlık', '1. sınıf', '2. sınıf'],
    sizes,
    'kişi',
  );
  final different = (a + b).isOdd;
  return _ratio(
    'Bu öğrenciler arasından geri koymadan iki kişi seçiliyor. İkisinin ${different ? 'farklı sınıflardan' : 'aynı sınıftan'} olma olasılığı nedir?',
    different ? den - same : same,
    den,
    [
      (different ? same : den - same, den),
      (same, n * n),
      (sizes[0] * (sizes[0] - 1), den),
    ],
    'Sıralı kişi çiftlerinin sayısı $n × ${n - 1} = $den. Aynı sınıftan çiftler için her grupta m(m − 1) sayılır ve toplam $same bulunur. ${different ? 'Farklı sınıftaki çiftler için bu sayı toplamdan çıkarılır.' : 'Aynı sınıfa ait sayı toplam çift sayısına bölünür.'}',
    v,
  );
}

AdvancedItem _quantile(int a, int b, int c) {
  final scores = [20, 40, 60, 80, 100];
  final f = [4 + a, 5 + b, 6 + c, 8 + (a + b) % 17, 6 + (2 * b + c) % 11];
  final total = f.reduce((x, y) => x + y),
      q = [25, 40, 50, 60, 75][(a + b + c) % 5];
  final rank = (total * q + 99) ~/ 100;
  int acc = 0, index = 0;
  for (var i = 0; i < scores.length; i++) {
    acc += f[i];
    if (acc >= rank) {
      index = i;
      break;
    }
  }
  final v = _bars(
    'Puanların frekans dağılımı',
    [for (final s in scores) '$s'],
    f,
    'kişi',
  );
  return _num(
    'En yakın üst sıra yönteminde yüzde $q kantili, küçükten büyüğe dizilmiş gözlemlerin ⌈$q × n/100⌉ sırasındaki değeridir. Bu dağılımın yüzde $q kantili kaç puandır?',
    scores[index],
    scores,
    'Toplam $total kişi vardır. Aranan sıra $rank. Bu sırayı içeren puan grubu ${scores[index]} olup bu gruba kadar biriken kişi sayısı $acc olur.',
    v,
    unit: 'puan',
  );
}

AdvancedItem _missingMean(int a, int b, int c) {
  final n = 10 + a, m = 14 + b, x = 48 + c;
  final y = 61 + (a + 2 * b + c) % 20;
  final total = n * x + m * y;
  final v = _table(
    'İki şubenin sınavı',
    ['', 'Kişi', 'Puan toplamı'],
    [
      ['I', n, n * x],
      ['II', m, '?'],
      ['Birlikte', n + m, total],
    ],
  );
  return _num(
    'İkinci şubenin ortalama sınav puanı nedir?',
    y,
    [total / (n + m), x, (total - n * x) / (m + n), total / m],
    'İkinci şubenin toplamı $total − ${n * x} = ${m * y}. Bu değer $m öğrenciye bölündüğünde $y puan düşer.',
    v,
    unit: 'puan',
    high: 100,
  );
}

AdvancedItem _error(int a, int b, int c) {
  final residual = [2 + a, -(3 + b), 1 + c], base = [50, 70, 60];
  final v = _table(
    'Üç günde elektrik talebi (MWh)',
    ['Gün', 'Gerçek', 'Tahmin'],
    [
      for (var i = 0; i < 3; i++) [i + 1, base[i], base[i] - residual[i]],
    ],
  );
  final squares = residual.fold(0, (s, x) => s + x * x),
      abs = residual.fold(0, (s, x) => s + x.abs()),
      rmse = (a + b + c).isEven;
  final target = rmse ? math.sqrt(squares / 3) : abs / 3;
  return _num(
    'Tahminler için ${rmse ? 'kök ortalama kare hata (RMSE)' : 'ortalama mutlak hata (MAE)'} kaç MWh olur? İki ondalığa yuvarlayın.',
    target,
    [
      squares / 3,
      abs / 3,
      math.sqrt(squares / 3),
      residual.reduce((x, y) => x + y).abs() / 3,
      abs,
    ],
    'Gerçekten tahmini çıkarınca hatalar ${residual.join(', ')} olur. ${rmse ? 'RMSE = √($squares/3)' : 'MAE = $abs/3'} = ${_fmt(target)} MWh.',
    v,
    unit: 'MWh',
    step: 0.1,
  );
}

AdvancedItem _priceIndex(int a, int b, int c) {
  final p = 9 + a, r = 7 + b, q = 2 + c, s = 3 + (a + b) % 12;
  final h = p + 2 + (c % 4), k = r + 3 + (a % 6);
  final old = p * q + r * s, now = h * q + k * s;
  final v = _table(
    'Sabit tüketim sepeti',
    ['Ürün', 'Adet', 'Eski ₺', 'Yeni ₺'],
    [
      ['A', q, p, h],
      ['B', s, r, k],
    ],
  );
  return _num(
    'Baz dönemi 100 alınan Laspeyres fiyat endeksinde baz dönem miktarları sabit tutulur. Bu sepetin yeni dönem endeksi nedir? İki ondalığa yuvarlayın.',
    100 * now / old,
    [
      100 * old / now,
      100 * (now - old) / old,
      50 * (h / p + k / r),
      100 * (h + k) / (p + r),
    ],
    'Sabit sepetin maliyeti $old TL iken $now TL olmuştur. Endeks 100 × $now / $old = ${_fmt(100 * now / old)}.',
    v,
    step: 1,
  );
}

AdvancedItem _standardized(int a, int b, int c) {
  final young = 45 + a, old = 62 + b, w = 20 + 3 * c;
  final rate = (w * young + (100 - w) * old) / 100;
  final v = _table(
    'Standart nüfus ve ulaşım alışkanlığı',
    ['Grup', 'Standart pay (%)', 'Bisiklet kullanan (%)'],
    [
      ['18–39', w, young],
      ['40+', 100 - w, old],
    ],
  );
  return _num(
    'Yaşa göre doğrudan standardizasyon yapılırsa bisiklet kullananların yüzdesi ne olur?',
    rate,
    [(old + young) / 2, ((100 - w) * young + w * old) / 100, old, young],
    'Yaş gruplarının kullanım oranları standart nüfus paylarıyla ağırlıklandırılır. ($w × $young + ${100 - w} × $old)/100 = ${_fmt(rate)}.',
    v,
    unit: '%',
    step: 0.1,
    high: 100,
  );
}

AdvancedItem _reservoir(int a, int b, int c) {
  final rain = 28 + a, inflow = 14 + b, evap = 18 + c, out = 9 + (a + b) % 17;
  final v = _table(
    'Gölün haftalık su bütçesi',
    ['Bileşen', 'Göl yüzeyine eşdeğer mm'],
    [
      ['Yağış', rain],
      ['Akarsu girişi', inflow],
      ['Buharlaşma', evap],
      ['Akarsu çıkışı', out],
    ],
  );
  final net = rain + inflow - evap - out;
  return _num(
    'Göl yüzey alanı sabit ve yeraltı suyu alışverişi ihmal edilebilir. Hafta sonunda su seviyesi başlangıca göre kaç mm değişir? Yükselmeyi pozitif alın.',
    net,
    [rain - evap, net + out, net - inflow, -net],
    'Seviye değişimi, girişlerin toplamından çıkışların çıkarılmasıdır. $rain + $inflow − $evap − $out = $net mm.',
    v,
    unit: 'mm',
    low: null,
  );
}

AdvancedItem _recapture(int a, int b, int c) {
  final marked = 25 + a, caught = 26 + b, again = 3 + c;
  final v = _table(
    'Bir gölde işaretli balık sayımı',
    ['Gözlem', 'Birey'],
    [
      ['İlk örnekte işaretlenen', marked],
      ['İkinci örnekte sayılan', caught],
      ['İkinci örnekte işaretli', again],
    ],
  );
  final estimate = marked * caught / again;
  return _num(
    'Kapalı popülasyonda işaret kaybı yoktur ve işaretli balıklar diğerleriyle aynı yakalanma olasılığına sahiptir. Lincoln–Petersen oran tahmini, en yakın tam sayıya göre kaç balıktır?',
    estimate.round(),
    [
      (marked * caught / (caught - again)).round(),
      marked + caught - again,
      (marked * (caught - again) / again).round(),
      marked + caught,
    ],
    'İkinci örnekteki işaretli oranı $again/$caught, popülasyonda $marked/N oranına karşılık gelir. N ≈ $marked × $caught/$again ≈ ${estimate.round()}.',
    v,
    unit: 'balık',
    low: 1,
  );
}

AdvancedItem _quadrat(int a, int b, int c) {
  final area = [2, 4, 6], plants = [10 + a, 11 + b, 9 + c];
  final total = plants.reduce((x, y) => x + y), density = total / 12;
  final v = _table(
    'Çayırdaki üç örnek alan',
    ['Alan', 'Yüzölçümü (m²)', 'Papatya'],
    [
      for (var i = 0; i < 3; i++) ['${i + 1}', area[i], plants[i]],
    ],
  );
  return _num(
    'Örnek alanlar örtüşmüyor. Üç alan tek parsel olarak ele alınırsa metrekare başına papatya yoğunluğu nedir? İki ondalığa yuvarlayın.',
    density,
    [
      (plants[0] / 2 + plants[1] / 4 + plants[2] / 6) / 3,
      total / 3,
      12 / total,
      plants[1] / 4,
    ],
    'Alanlar farklı genişliktedir. Toplam $total bireyi toplam 12 m² alana bölmek gerekir. Yoğunluk ${_fmt(density)} birey/m² olur.',
    v,
    unit: 'birey/m²',
    step: 0.1,
  );
}

AdvancedItem _detection(int a, int b, int c) {
  final p = 20 + a, q = 35 + b, s = 45 + c;
  final fail = (100 - p) * (100 - q) * (100 - s);
  final v = _bars(
    'Bağımsız ziyaretlerde görme olasılığı (%)',
    ['I', 'II', 'III'],
    [p, q, s],
    '%',
  );
  final none = (a + b + c).isOdd;
  return _ratio(
    'Kuş türü alanda kesin olarak bulunuyor. Türün görülmesi ziyaretler arasında bağımsızsa üç ziyarette ${none ? 'hiç görülmeme' : 'en az bir kez görülme'} olasılığı nedir?',
    none ? fail : 1000000 - fail,
    1000000,
    [
      (none ? 1000000 - fail : fail, 1000000),
      (p * q * s, 1000000),
      (p + q + s, 300),
    ],
    'Üç ziyarette de kaçırma olasılığı ${100 - p}/100 × ${100 - q}/100 × ${100 - s}/100 = ${_fraction(fail, 1000000)}. ${none ? 'Aranan doğrudan bu ortak olasılıktır.' : 'En az bir kez görülme olasılığı bunun birden farkıdır.'}',
    v,
  );
}

AdvancedItem _diversity(int a, int b, int c) {
  final abundance = [5 + a, 7 + b, 6 + c],
      n = abundance.reduce((x, y) => x + y);
  final same = abundance.fold(0, (s, v) => s + v * v), den = n * n;
  final v = _bars(
    'Örnek parselde birey sayıları',
    ['Meşe', 'Çam', 'Ardıç'],
    abundance,
    'birey',
  );
  return _ratio(
    'Her türün bağıl bolluğu pᵢ olsun. Bu parselde Gini–Simpson çeşitlilik indisi 1 − Σpᵢ² kaçtır?',
    den - same,
    den,
    [(same, den), (n * n - same, n * (n - 1)), (n, den)],
    'Her tür sayısının karesi toplanarak $same bulunur. Toplam birey sayısı $n olduğundan 1 − $same/$den = ${_fraction(den - same, den)}.',
    v,
  );
}

AdvancedItem _similarity(int a, int b, int c) {
  final onlyA = 3 + a, onlyB = 5 + b, both = 4 + c;
  final v = _table(
    'İki sulak alanın kuş envanteri',
    ['Dağılım', 'Tür sayısı'],
    [
      ['Yalnızca I', onlyA],
      ['İkisinde de', both],
      ['Yalnızca II', onlyB],
    ],
  );
  final union = onlyA + onlyB + both, sorensen = (a + c).isOdd;
  final top = sorensen ? 2 * both : both,
      bottom = sorensen ? union + both : union;
  return _ratio(
    sorensen
        ? 'Sørensen benzerliği, ortak tür sayısının iki katının iki listenin uzunlukları toplamına oranıdır. İki alan için bu oran kaçtır?'
        : 'Jaccard benzerliği, ortak tür sayısının iki alanda görülen farklı tür sayısına oranıdır. İki alan için bu oran kaçtır?',
    top,
    bottom,
    [
      (both, union),
      (2 * both, union + both),
      (both, onlyA + both),
      (both, onlyB + both),
      (onlyA + onlyB, union),
    ],
    'Ortak $both tür, birleşimde $union farklı tür vardır. ${sorensen ? 'Liste uzunluklarının toplamı ${union + both} olur.' : ''} Benzerlik ${_fraction(top, bottom)} bulunur.',
    v,
  );
}

AdvancedItem _nutrient(int a, int b, int c) {
  final river = 130 + 3 * a, runoff = 42 + 2 * b, loss = 65 + 2 * c;
  final v = _chain('Yıllık fosfor bütçesi (kg)', [
    'Akarsu\n$river',
    'Yanal giriş\n+$runoff',
    'Çıkış\n$loss',
  ]);
  final net = river + runoff - loss, percent = 100 * net / (river + runoff);
  return _num(
    'Bir sulak alanın giriş ve çıkışları şekilde gösteriliyor. Başka akı yoksa toplam yıllık fosfor girişinin yüzde kaçı alan içinde kalmıştır? İki ondalığa yuvarlayın.',
    percent,
    [
      100 * loss / (river + runoff),
      100 * net / river,
      100 * runoff / (river + runoff),
      100 * (river - loss) / river,
    ],
    'Yıllık giriş ${river + runoff} kg, çıkış $loss kg. İçeride kalan $net kg, toplam girişin %${_fmt(percent)} kadarını oluşturur.',
    v,
    unit: '%',
    step: 0.1,
    high: 100,
  );
}

AdvancedItem _degreeDays(int a, int b, int c) {
  // Tenths of a degree retain realistic temperatures without loss of precision.
  final low = [45 + 3 * a, 65 + 3 * b, 55 + 3 * c],
      high = [135 + 3 * a, 145 + 3 * b, 175 + 3 * c];
  final threshold = 10 + (a + b) % 3;
  final daily = [
    for (var i = 0; i < 3; i++)
      math.max(0.0, (low[i] + high[i]) / 20 - threshold),
  ];
  final sum = daily.reduce((x, y) => x + y);
  final v = _table(
    'Üç günlük sıcaklıklar (°C)',
    ['Gün', 'En düşük', 'En yüksek'],
    [
      for (var i = 0; i < 3; i++)
        [i + 1, _fmt(low[i] / 10), _fmt(high[i] / 10)],
    ],
  );
  return _num(
    'Bitki gelişimi için taban sıcaklığı $threshold °C alınsın. Her gün için en düşük ve en yükseğin ortalamasından tabanı çıkarın, negatif sonucu sıfır sayın. Üç günde kaç derece-gün birikir?',
    sum,
    [sum / 3, daily[0] + daily[1], daily[1] + daily[2], sum + threshold],
    'Günlük katkılar sırasıyla ${daily.map((e) => _fmt(e)).join(' + ')} derece-gündür. Toplam ${_fmt(sum)} derece-gün eder.',
    v,
    unit: 'derece-gün',
    step: 0.1,
  );
}

AdvancedItem _patch(int a, int b, int c) {
  final occupied = 30 + a,
      empty = 24 + b,
      colonize = 10 + c,
      loss = 6 + (a + b) % 12;
  final v = _table(
    'Bir mevsimlik yama geçişleri',
    ['Başlangıç', 'Yama', 'Geçiş olasılığı'],
    [
      ['Dolu', occupied, 'Boşalma %$loss'],
      ['Boş', empty, 'Yerleşim %$colonize'],
    ],
  );
  final expected = occupied * (1 - loss / 100) + empty * colonize / 100;
  return _num(
    'Her yama bir mevsimde en çok bir kez durum değiştiriyor. Mevsim sonundaki dolu habitat yaması sayısının beklenen değeri kaçtır?',
    expected,
    [
      occupied + empty * colonize / 100,
      occupied * (1 - loss / 100),
      occupied * loss / 100 + empty * colonize / 100,
      occupied + (colonize - loss) / 100,
    ],
    'Dolu kalması beklenen yamalar $occupied × (1 − $loss/100), yeni dolması beklenenler $empty × $colonize/100 kadardır. İki beklentinin toplamı ${_fmt(expected)} yamadır.',
    v,
    unit: 'yama',
    step: 0.1,
  );
}

AdvancedItem _thermal(int a, int b, int c) {
  final r = [2 + a, 4 + b, 3 + c],
      sum = r.reduce((x, y) => x + y),
      delta = 15 + (a + b + c) % 18;
  final v = _chain('Seri katman dirençleri (K/W)', [
    'I · ${_fmt(r[0] / 10)}',
    'II · ${_fmt(r[1] / 10)}',
    'III · ${_fmt(r[2] / 10)}',
  ]);
  return _num(
    'Düz bir duvarın dış yüzleri arasındaki sıcaklık farkı $delta K. Isı kararlı durumda üç katmandan sırayla geçiyor. Temas dirençleri ihmal edilirse ısı geçiş hızı kaç watt olur? İki ondalığa yuvarlayın.',
    10 * delta / sum,
    [delta * sum / 10, delta * 30 / sum, delta * 10 / r[1], sum / (10 * delta)],
    'Seri dirençler toplanır. Toplam ${_fmt(sum / 10)} K/W olduğundan ısı geçiş hızı ΔT/R = $delta/${_fmt(sum / 10)} = ${_fmt(10 * delta / sum)} W.',
    v,
    unit: 'W',
    step: 0.1,
  );
}

AdvancedItem _mixing(int a, int b, int c) {
  final cold = 10 + a,
      hot = 51 + b,
      m1 = 100 + 10 * c,
      m2 = 150 + 10 * ((a + b) % 15);
  final v = _table(
    'Yalıtılmış kapta iki su örneği',
    ['Su', 'Kütle (g)', 'Sıcaklık (°C)'],
    [
      ['Soğuk', m1, cold],
      ['Sıcak', m2, hot],
    ],
  );
  final temp = (m1 * cold + m2 * hot) / (m1 + m2);
  return _num(
    'Kabın ısı kapasitesi ve çevreyle ısı alışverişi ihmal ediliyor. Suyun özgül ısısı sabitse karışımın denge sıcaklığı kaç °C olur? İki ondalığa yuvarlayın.',
    temp,
    [(hot + cold) / 2, (m1 * hot + m2 * cold) / (m1 + m2), hot - cold, cold],
    'Sıcak suyun verdiği ısı, soğuk suyun aldığı ısıya eşittir. Denge sıcaklığı ($m1 × $cold + $m2 × $hot)/${m1 + m2} = ${_fmt(temp)} °C.',
    v,
    unit: '°C',
    step: 0.5,
  );
}

AdvancedItem _flow(int a, int b, int c) {
  final q = [4 + a, 6 + b, 5 + c], dt = 2 + (a + c) % 5;
  final v = _line(
    'Su akış hızı (L/dk)',
    ['0 dk', '$dt dk', '${2 * dt} dk'],
    q,
    'L/dk',
  );
  final volume = dt * (q[0] + 2 * q[1] + q[2]) / 2;
  return _num(
    'Pompanın debisi ardışık ölçümler arasında doğrusal değişiyor. Grafiğin kapsadığı sürede toplam kaç litre su aktarılır?',
    volume,
    [
      dt * q.reduce((x, y) => x + y),
      dt * (q[0] + q[2]),
      2 * dt * q[1],
      volume / 2,
    ],
    'Her aralıkta ortalama debi iki ucun ortalamasıdır. İki yamuğun alanı $dt × (${q[0]} + 2 × ${q[1]} + ${q[2]})/2 = ${_fmt(volume)} L.',
    v,
    unit: 'L',
    step: 0.5,
  );
}

AdvancedItem _calibration(int a, int b, int c) {
  final x = 100 + 4 * a,
      y = 240 + 3 * b,
      probe = x + 4 * (c + 1),
      base = 15 + (a + c) % 10,
      upper = 55 + (a + b) % 11;
  final v = _table(
    'Basınç sensörü kalibrasyonu',
    ['Okuma (birim)', 'Basınç (kPa)'],
    [
      [x, base],
      [y, upper],
      [probe, '?'],
    ],
  );
  final actual = base + (probe - x) * (upper - base) / (y - x);
  return _num(
    'İki referans noktasını birleştiren doğrusal kalibrasyona göre eksik basınç kaç kPa olmalıdır? İki ondalığa yuvarlayın.',
    actual,
    [
      base + (probe - x) * (y - x) / (upper - base),
      probe * upper / y,
      (base + upper) / 2,
      upper - (actual - base),
    ],
    'Ölçüm, okuma aralığının ($probe − $x)/($y − $x) kadarlık bölümündedir. Aynı oran basınç farkına uygulanıp $base kPa eklenince ${_fmt(actual)} kPa bulunur.',
    v,
    unit: 'kPa',
    step: 0.5,
  );
}

AdvancedItem _uncertainty(int a, int b, int c) {
  final m1 = 650 + 3 * a, m2 = 410 + 4 * b, u = 2 + c, vv = 3 + (a + b) % 9;
  final v = _table(
    'Kütle ölçümleri',
    ['Tartım', 'Ölçüm (g)', 'Azami hata (g)'],
    [
      ['Dolu', m1, _fmt(u / 10)],
      ['Boş', m2, _fmt(vv / 10)],
    ],
  );
  final diff = m1 - m2, bound = (u + vv) / 10, upper = (a + c).isOdd;
  final limit = upper ? diff + bound : diff - bound;
  return _num(
    'Net kütle, dolu kaptan boş kabın çıkarılmasıyla bulunuyor. Hataların işaretlerine dair bilgi yok. Verilen kesin hata sınırlarına göre net kütle en ${upper ? 'çok' : 'az'} kaç gram olabilir?',
    limit,
    [
      upper ? diff - bound : diff + bound,
      diff,
      diff + (u - vv) / 10,
      diff - (u - vv) / 10,
    ],
    'Nominal fark $diff g. En kötü durumda iki mutlak hata toplanır ve ${_fmt(bound)} g eder. ${upper ? 'Üst' : 'Alt'} sınır $diff ${upper ? '+' : '−'} ${_fmt(bound)} = ${_fmt(limit)} g.',
    v,
    unit: 'g',
    step: 0.1,
  );
}

AdvancedItem _solar(int a, int b, int c) {
  final rad = 425 + 10 * a, area = 15 + b, eff = 12 + c;
  final v = _table(
    'Panelin çalışma koşulları',
    ['Büyüklük', 'Değer'],
    [
      ['Işınım', '$rad W/m²'],
      ['Etkin alan', '${_fmt(area / 10)} m²'],
      ['Elektriksel verim', '%$eff'],
    ],
  );
  final power = rad * area * eff / 1000;
  return _num(
    'Işınım panel yüzeyine dik geliyor ve verilen koşullar sabit. Panelin ürettiği elektrik gücü kaç watt olur? İki ondalığa yuvarlayın.',
    power,
    [rad * area / 10, rad * eff / 100, rad * area / 10 - power, power * 10],
    'Gelen güç, ışınım ile etkin alanın çarpımıdır. Elektrik gücü $rad × ${_fmt(area / 10)} × $eff/100 = ${_fmt(power)} W.',
    v,
    unit: 'W',
    step: 0.5,
  );
}

AdvancedItem _gear(int a, int b, int c) {
  final drive = 18 + a,
      idler = 20 + b,
      driven = 24 + c,
      rpm = 120 + 5 * ((a + b + c) % 20);
  final v = _chain('Birbirine dıştan geçen dişliler', [
    'A\n$drive diş',
    'B\n$idler diş',
    'C\n$driven diş',
  ]);
  final mid = (a + b).isEven, speed = rpm * drive / (mid ? idler : driven);
  final target = mid ? 'B' : 'C', targetTeeth = mid ? idler : driven;
  return _num(
    'A dişlisi $rpm dev/dk hızla dönüyor. Kayma yokken $target dişlisinin dönme hızının büyüklüğü kaç dev/dk olur? İki ondalığa yuvarlayın.',
    speed,
    [
      rpm * targetTeeth / drive,
      rpm * drive / (mid ? driven : idler),
      rpm,
      rpm * (drive + idler) / targetTeeth,
    ],
    'Temas eden dişlilerde devir sayısı ile diş sayısının çarpımı eşittir. ${mid ? 'A ve B için' : 'Ara dişlinin oranları sadeleştiğinden A ve C için'} n = $rpm × $drive/$targetTeeth = ${_fmt(speed)} dev/dk.',
    v,
    unit: 'dev/dk',
    step: 0.5,
  );
}

AdvancedItem _interpret(int a, int b, int c) {
  final start = 18 + a;
  final first = 8 + b, second = 10 + c;
  final visual = _line(
    'Arşivlenen belge sayacı',
    ['08.00', '10.00', '12.00'],
    [start, start + first, start + first + second],
    'belge',
  );
  const growing = 'İkinci dönemde ortalama arşivleme hızı daha yüksektir.';
  const falling = 'İlk dönemde ortalama arşivleme hızı daha yüksektir.';
  const equal = 'İki dönemin ortalama arşivleme hızı aynıdır.';
  const invalid = 'İki dönem içinde hızın her an sabit kaldığı kesindir.';
  final key = first < second
      ? growing
      : first > second
      ? falling
      : equal;
  return AdvancedItem(
    'Grafik birikimli sayacı gösteriyor. İki saatlik dönemlerin ortalama arşivleme hızları hakkında hangi yorum verilerle desteklenir?',
    key,
    [growing, falling, equal, invalid].where((x) => x != key).toList(),
    'Eşit sürede ilk dönem $first, ikinci dönem $second belge eklenmiştir. İki uç nokta arasındaki artış, dönem içindeki anlık hızı göstermez.',
    visual: visual,
  );
}

CreationTask _designPacks(AdvancedItem item, int index) {
  final data = item.visual!.rows;
  return CreationTask(
    'Harita indirmelerini planlayacak bir seçim algoritması tasarlayın. Tablodaki dört paketi örnek veri olarak kullanın. Algoritmanın kapasiteyi aşmadan en yüksek puanı bulduğunu gösterin ve eşit puanlı çözümler için bir seçim kuralı yazın.',
    [
      'Her paketin en çok bir kez seçilmesini ve izin verilen GB sınırını algoritmada ifade ettim.',
      'Tablodaki A (${data[0][1]} GB, ${data[0][2]} puan) dâhil dört paketi algoritmaya uyguladım ve seçtiğim alt kümenin boyutu ile puanını gösterdim.',
      'Elediğim seçeneklerin neden daha iyi olamayacağını açıkladım ve eşit puan durumu için uygulanabilir bir kural ürettim.',
    ],
  );
}

CreationTask _designPatches(AdvancedItem item, int index) {
  final before = item.visual!.rows;
  return CreationTask(
    'Bu yama ağı için bir mevsimlik gözlem araştırması tasarlayın. Başlangıçta dolu olan ${before[0][1]} yama ile boş olan ${before[1][1]} yamayı izleyerek boşalma ve yerleşim olasılıklarını nasıl ayrı tahmin edeceğinizi açıklayın.',
    [
      'Örnekleme birimini, başlangıç ve son ziyaretlerinin zamanlamasını ve iki başlangıç grubunun nasıl izleneceğini belirttim.',
      'Gözden kaçan canlıların yanlış boşalma kaydı üretmesini azaltacak tekrar gözlem veya başka bir doğrulama yolu tasarladım.',
      'Her geçişin sayısını doğru başlangıç grubuna bölerek iki ayrı tahmin elde ettim ve gözlem kayıplarının nasıl ele alınacağını belirttim.',
    ],
  );
}

typedef _Fact = (String, String, String, String, String, String);
const _computingFacts = <_Fact>[
  (
    'İlk giren öğenin ilk çıktığı soyut veri yapısının adı nedir?',
    'Kuyruk',
    'Yığın',
    'Öncelik yığını',
    'İkili arama ağacı',
    'Bir kuyrukta ekleme arkadan, çıkarma önden yapılır.',
  ),
  (
    'Bir veri kümesi için karmaşıklık gösteriminde Θ (teta) hangi tür asimptotik sınırı belirtir?',
    'Sıkı alt ve üst sınır',
    'Yalnız üst sınır',
    'Yalnız alt sınır',
    'Tam çalışma süresi',
    'Θ gösterimi büyüme hızını sabit çarpanlar içinde üstten ve alttan sınırlar.',
  ),
  (
    'İlişkisel veritabanında her satırı benzersiz tanımlamak için seçilen ve boş bırakılamayan anahtarın adı nedir?',
    'Birincil anahtar',
    'Yabancı anahtar',
    'İkincil dizin',
    'Görünüm',
    'Birincil anahtar satır kimliğidir ve birden çok sütundan oluşabilir.',
  ),
  (
    'Sıralama algoritmalarında kararlılık hangi özelliği ifade eder?',
    'Eşit anahtarlı öğelerin göreli sırasını koruma',
    'Her girdide aynı süreyi kullanma',
    'Ek bellek ayırmama',
    'Sıralamayı tek geçişte bitirme',
    'Kararlı sıralama önceden eşit görülen anahtarların sırasını bozmaz.',
  ),
  (
    'İkili arama algoritmasının standart dizi sürümünde temel önkoşul nedir?',
    'Dizinin karşılaştırma anahtarına göre sıralı olması',
    'Eleman sayısının çift olması',
    'Girdinin yalnızca tam sayı içermesi',
    'Tüm anahtarların farklı olması',
    'Sıralama, ortadaki değere bakarak arama alanının yarısını elemek için gereklidir.',
  ),
  (
    'Sınıflandırmada doğru pozitiflerin tüm gerçek pozitiflere oranına hangi ad verilir?',
    'Duyarlılık',
    'Kesinlik',
    'Özgüllük',
    'Genel doğruluk',
    'Duyarlılık, doğru pozitif sayısının doğru pozitif ve yanlış negatif sayıları toplamına oranıdır.',
  ),
  (
    'Ağaç veri yapısında çocuğu olmayan düğüm hangi adla anılır?',
    'Yaprak',
    'Kök bağlantısı',
    'Alt ağaç',
    'Kardeş kümesi',
    'Yaprak, altına yeni bir dalın inmediği düğümdür.',
  ),
  (
    'Bir fonksiyonun aynı alt problem için hesapladığı sonucu saklayıp yeniden kullanma tekniğinin adı nedir?',
    'Memoizasyon',
    'Serileştirme',
    'Normalleştirme',
    'Parçalama',
    'Memoizasyon alt problem ile sonucunu birlikte saklar ve yinelenen hesaplamayı önler.',
  ),
];
const _statsFacts = <_Fact>[
  (
    'Ölçü birimi gözlenen değişkenle aynı olan yayılım ölçüsü hangisidir?',
    'Standart sapma',
    'Varyans',
    'Değişim katsayısı',
    'Standartlaştırılmış z puanı',
    'Standart sapma, varyansın karekökü olduğu için özgün ölçü birimini taşır.',
  ),
  (
    'Bir olayın tümleyeninin olasılığı, olayın olasılığı p cinsinden nedir?',
    '1 − p',
    '1/p',
    'p²',
    '1 + p',
    'Olay ve tümleyeni örnek uzayı ayırır. Olasılıkları toplamı birdir.',
  ),
  (
    'Sonlu bir listede en sık görülen değerin istatistikteki adı nedir?',
    'Mod',
    'Medyan',
    'Açıklık',
    'Varyans',
    'Mod, frekansı en yüksek olan değerdir. Aynı en yüksek frekansa birden fazla değer ulaşabilir.',
  ),
  (
    'Eşit aralıklı ölçekten farklı olarak oran ölçeğini tanımlayan özellik nedir?',
    'Miktarın yokluğunu ifade eden sıfır noktası',
    'Kategorilerin yalnız adlarla gösterilmesi',
    'Gözlemlerin yalnız sıralanabilmesi',
    'Sıfır noktasının keyfî seçilmesi',
    'Anlamlı mutlak sıfır, ölçümlerin oranlarının yorumlanabilmesini sağlar.',
  ),
  (
    'Modelin tahmin hatasını değerlendirmek için eğitimde ve model seçiminde kullanılmayıp en sona ayrılan veri bölümüne ne denir?',
    'Test kümesi',
    'Eğitim kümesi',
    'Parametre kümesi',
    'Özellik kümesi',
    'Bağımsız test kümesi son modelin görülmemiş verilerdeki başarımını değerlendirmek için saklanır.',
  ),
  (
    'Birinci ve üçüncü çeyreklerin farkı Q₃ − Q₁ hangi yayılım ölçüsüdür?',
    'Çeyrekler açıklığı',
    'Tam açıklık',
    'Standart hata',
    'Ortalama mutlak sapma',
    'Çeyrekler açıklığı ortadaki yüzde 50’lik kesimin kapladığı aralığın genişliğidir.',
  ),
  (
    'Bir tahmin edicinin beklenen değeri ile tahmin ettiği gerçek parametre arasındaki farka ne ad verilir?',
    'Yanlılık',
    'Güven düzeyi',
    'Serbestlik derecesi',
    'Örnek hacmi',
    'Yanlılık, tahmin edicinin tekrarlı örneklemedeki ortalamasının gerçek parametreden sistematik sapmasıdır.',
  ),
  (
    'Sıfır hipotezi gerçekte doğruyken onu reddetmek hangi hatadır?',
    'Tip I hata',
    'Tip II hata',
    'Yuvarlama hatası',
    'Ölçekleme hatası',
    'Tip I hata doğru sıfır hipotezini reddetmektir. Tip II hata ise yanlış sıfır hipotezini reddedememektir.',
  ),
];
const _ecologyFacts = <_Fact>[
  (
    'Bir bölgede bulunan farklı türlerin sayısı hangi terimle ifade edilir?',
    'Tür zenginliği',
    'Göreli bolluk',
    'Popülasyon yoğunluğu',
    'Taşıma kapasitesi',
    'Tür zenginliği listedeki farklı türleri birer kez sayar.',
  ),
  (
    'Canlıların dağılışı ve mevsimsel olayların zamanlaması bağlamında, ilk çiçeklenme tarihi hangi alanın konusudur?',
    'Fenoloji',
    'Taksonomi',
    'Mineraloji',
    'Petroloji',
    'Fenoloji, çiçeklenme ve göç gibi dönemsel biyolojik olayların zamanlamasını inceler.',
  ),
  (
    'Ekolojide bir popülasyonun birim alan veya hacim başına düşen birey sayısına ne denir?',
    'Popülasyon yoğunluğu',
    'Tür zenginliği',
    'Brüt üretim',
    'Habitat genişliği',
    'Yoğunlukta pay birey sayısı, payda ölçülen alan ya da hacimdir.',
  ),
  (
    'Bir ortama dışarıdan bireylerin gelerek yerel popülasyona katılmasının adı nedir?',
    'İçe göç',
    'Dışa göç',
    'Ölüm',
    'Ayrışma',
    'İçe göç yerel popülasyona birey ekler. Dışa göçte bireyler popülasyondan ayrılır.',
  ),
  (
    'Birincil üreticilerin kendi solunumlarından sonra biyokütlede kalan üretime ne denir?',
    'Net birincil üretim',
    'Brüt birincil üretim',
    'İkincil tüketim',
    'Topluluk solunumu',
    'Net birincil üretim, brüt birincil üretimden üreticilerin solunumu çıkarılarak bulunur.',
  ),
  (
    'Aynı türün ayrı habitat yamalarında yaşayan ve aralarında göç olabilen yerel popülasyonları birlikte ne oluşturur?',
    'Metapopülasyon',
    'Besin ağı',
    'Trofik basamak',
    'Niş genişliği',
    'Metapopülasyon, birbirine birey hareketiyle bağlanabilen yerel popülasyonların bütünüdür.',
  ),
  (
    'Bir akarsuya yüzey akışıyla su sağlayan kara alanının genel adı nedir?',
    'Drenaj havzası',
    'Talveg çizgisi',
    'Kıyı oku',
    'Menderes boynu',
    'Drenaj havzası yağışın aynı akarsu sistemine yöneldiği alanı kapsar.',
  ),
  (
    'Tür bolluklarının birbirine ne kadar yakın olduğunu betimleyen çeşitlilik bileşeni hangisidir?',
    'Tür eşitliği',
    'Tür zenginliği',
    'Trofi düzeyi',
    'Göç hızı',
    'Tür eşitliği bireylerin türler arasında ne kadar dengeli dağıldığını gösterir.',
  ),
];

AdvancedFamily _factBank(
  String key,
  String title,
  Topic topic,
  StudyLevel level,
  List<_Fact> facts,
) => AdvancedFamily(
  key: 'applied_$key',
  title: title,
  topic: topic,
  level: level,
  count: facts.length,
  difficulty: Difficulty.medium,
  bloom: BloomLevel.hatirlama,
  build: (index) {
    final (prompt, correct, w1, w2, w3, reason) = facts[index];
    return AdvancedItem(prompt, correct, [w1, w2, w3], reason);
  },
);

const _h = StudyLevel.lise, _u = StudyLevel.universite;
const _ta = VisualKind.table,
    _ba = VisualKind.barChart,
    _li = VisualKind.lineChart,
    _di = VisualKind.diagram;

final appliedFamilies = <AdvancedFamily>[
  _factBank(
    'core_cs',
    'Bilgisayar biliminde temel kavramlar',
    Topic.computing,
    _u,
    _computingFacts,
  ),
  _factBank(
    'core_stats',
    'İstatistikte temel kavramlar',
    Topic.statistics,
    _u,
    _statsFacts,
  ),
  _factBank(
    'core_ecology',
    'Ekolojide temel kavramlar',
    Topic.biology,
    _h,
    _ecologyFacts,
  ),
  _family(
    'interpret',
    'Kümülatif grafiği yorumlama',
    Topic.statistics,
    _h,
    _li,
    _interpret,
    count: 3123,
    bloom: BloomLevel.anlama,
    shortAnswer: false,
    difficulty: Difficulty.medium,
  ),
  _family(
    'prefix',
    'Kümülatif sayaç ve kayıt hızı',
    Topic.technology,
    _h,
    _li,
    _prefix,
    count: 3100,
    difficulty: Difficulty.medium,
  ),
  _family(
    'critical',
    'Paralel yürütme ve kritik yol',
    Topic.computing,
    _u,
    _di,
    _critical,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'rle',
    'Görüntü sıkıştırma',
    Topic.technology,
    _h,
    _ba,
    _runLength,
    difficulty: Difficulty.medium,
  ),
  _family(
    'matrix',
    'Matris zinciri maliyeti',
    Topic.computing,
    _u,
    _ta,
    _matrix,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'sparse',
    'Seyrek matris gösterimi',
    Topic.computing,
    _u,
    _ta,
    _sparse,
  ),
  _family('blocks', 'Blok tabanlı erişim', Topic.technology, _u, _ta, _block),
  _family(
    'queue',
    'İş kuyruğu ve kapasite',
    Topic.computing,
    _h,
    _ta,
    _queue,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'inversions',
    'Sıralamada ters çiftler',
    Topic.computing,
    _u,
    _ta,
    _inversions,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'interval',
    'Ağırlıklı aralık seçimi',
    Topic.computing,
    _u,
    _ta,
    _interval,
    bloom: BloomLevel.degerlendirme,
    shortAnswer: false,
  ),
  _family(
    'knapsack',
    'Kapasite kısıtlı seçim',
    Topic.computing,
    _u,
    _ta,
    _backpack,
    bloom: BloomLevel.yaratma,
    shortAnswer: false,
    creation: _designPacks,
  ),
  _family('f1', 'Sınıflandırmada F1 ölçüsü', Topic.computing, _u, _ta, _f1),
  _family(
    'merge',
    'En düşük birleştirme maliyeti',
    Topic.computing,
    _u,
    _ba,
    _merging,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'weighted',
    'Grup ortalamalarını birleştirme',
    Topic.statistics,
    _h,
    _ta,
    _weighted,
    difficulty: Difficulty.medium,
  ),
  _family(
    'variance',
    'Örneklem varyansı',
    Topic.statistics,
    _u,
    _ba,
    _variance,
  ),
  _family(
    'did',
    'Farkların farkı',
    Topic.research,
    _u,
    _ta,
    _difference,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'regression',
    'Regresyonda sabit terim',
    Topic.statistics,
    _u,
    _ta,
    _regression,
  ),
  _family(
    'confidence',
    'Ortalama için güven aralığı',
    Topic.statistics,
    _u,
    _ta,
    _confidence,
  ),
  _family(
    'posterior',
    'Koşullu örnek uzay',
    Topic.statistics,
    _h,
    _ta,
    _posterior,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'stratum',
    'Geri koymadan örnekleme',
    Topic.statistics,
    _h,
    _ba,
    _stratum,
  ),
  _family(
    'quantile',
    'Frekans tablosunda kantil',
    Topic.statistics,
    _u,
    _ba,
    _quantile,
  ),
  _family(
    'missingmean',
    'Bir gruba ait eksik ortalama',
    Topic.statistics,
    _h,
    _ta,
    _missingMean,
    difficulty: Difficulty.medium,
  ),
  _family(
    'forecast',
    'Tahmin hatası ölçüleri',
    Topic.statistics,
    _u,
    _ta,
    _error,
  ),
  _family(
    'index',
    'Sabit sepet fiyat endeksi',
    Topic.economics,
    _u,
    _ta,
    _priceIndex,
  ),
  _family(
    'standardize',
    'Doğrudan standardizasyon',
    Topic.statistics,
    _u,
    _ta,
    _standardized,
  ),
  _family(
    'reservoir',
    'Göl su bütçesi',
    Topic.nature,
    _h,
    _ta,
    _reservoir,
    difficulty: Difficulty.medium,
  ),
  _family(
    'recapture',
    'Popülasyon büyüklüğü tahmini',
    Topic.research,
    _u,
    _ta,
    _recapture,
  ),
  _family(
    'quadrat',
    'Örnek alanlardan yoğunluk',
    Topic.nature,
    _h,
    _ta,
    _quadrat,
  ),
  _family(
    'detection',
    'Bağımsız gözlemlerde saptama',
    Topic.research,
    _u,
    _ba,
    _detection,
  ),
  _family(
    'diversity',
    'Tür çeşitliliği indisi',
    Topic.biology,
    _u,
    _ba,
    _diversity,
  ),
  _family(
    'similarity',
    'Habitatların tür benzerliği',
    Topic.nature,
    _u,
    _ta,
    _similarity,
  ),
  _family(
    'nutrient',
    'Sulak alanda madde bütçesi',
    Topic.nature,
    _u,
    _di,
    _nutrient,
  ),
  _family(
    'degreedays',
    'Fenolojide derece-gün',
    Topic.biology,
    _h,
    _ta,
    _degreeDays,
  ),
  _family(
    'patch',
    'Habitat yamalarında geçiş',
    Topic.research,
    _u,
    _ta,
    _patch,
    bloom: BloomLevel.yaratma,
    shortAnswer: false,
    creation: _designPatches,
  ),
  _family('thermal', 'Seri ısıl direnç', Topic.engineering, _u, _di, _thermal),
  _family('mixing', 'Kalorimetri ve denge', Topic.science, _h, _ta, _mixing),
  _family('flow', 'Debi grafiğinden hacim', Topic.engineering, _h, _li, _flow),
  _family(
    'calibration',
    'Doğrusal sensör kalibrasyonu',
    Topic.engineering,
    _h,
    _ta,
    _calibration,
  ),
  _family(
    'uncertainty',
    'Ölçümde en kötü durum sınırı',
    Topic.research,
    _u,
    _ta,
    _uncertainty,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'solar',
    'Fotovoltaik güç dönüşümü',
    Topic.engineering,
    _h,
    _ta,
    _solar,
  ),
  _family('gear', 'Dişli oranları', Topic.engineering, _h, _di, _gear),
];
