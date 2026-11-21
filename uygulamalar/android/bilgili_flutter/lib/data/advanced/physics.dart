import 'dart:math' as math;
import 'common.dart';

typedef _Problem = AdvancedItem Function(int a, int b, int c, bool second);

AdvancedFamily _family(
  String key,
  String title,
  StudyLevel level,
  VisualKind kind,
  String lesson,
  _Problem build, {
  ExamKind? exam,
  Difficulty? difficulty,
  bool shortAnswer = true,
  BloomLevel bloom = BloomLevel.uygulama,
  int count = 4900,
  CreationTask Function(AdvancedItem, int)? creation,
  MultiSelectTask Function(AdvancedItem, int)? multiSelect,
}) {
  return AdvancedFamily(
    key: 'physics_$key',
    title: title,
    topic: switch (key) {
      'thermal_design' || 'instrument_review' => Topic.research,
      'uncertainty' => Topic.statistics,
      _ => switch (lesson) {
        'Mühendislik' => Topic.engineering,
        'Kimya' => Topic.chemistry,
        _ => Topic.physics,
      },
    },
    level: level,
    count: count,
    difficulty:
        difficulty ??
        (level == StudyLevel.lise ? Difficulty.medium : Difficulty.hard),
    shortAnswer: shortAnswer,
    bloom: bloom,
    creation: creation,
    multiSelect: multiSelect,
    visualKind: kind,
    exam: exam,
    lesson: lesson,
    build: (index) => build(
      2 + index % 25,
      3 + index ~/ 25 % 20,
      2 + index ~/ 500 % 5,
      index >= 2500,
    ),
  );
}

String _n(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}

AdvancedItem _item(
  QuestionVisual visual,
  String prompt,
  num answer,
  String unit,
  List<num> wrong,
  String explanation,
) {
  String show(num v) => unit == '%' ? '%${_n(v)}' : '${_n(v)} $unit'.trim();
  final correct = show(answer);
  final alternatives = <String>{};
  for (final x in [
    ...wrong,
    answer * 2,
    answer / 2,
    answer + 1,
    answer + 2,
    answer + 3,
  ]) {
    if (!x.isFinite || (unit == '%' && (x < 0 || x > 100))) continue;
    final s = show(x);
    if (s != correct) alternatives.add(s);
    if (alternatives.length == 3) break;
  }
  final approx = ((answer * 1000).round() - answer * 1000).abs() > 0.000001;
  return AdvancedItem(
    approx
        ? '$prompt Sonucu virgülden sonra üç basamağa yuvarlayınız.'
        : prompt,
    correct,
    alternatives.toList(),
    '$explanation Sonuç $correct.',
    visual: visual,
  );
}

QuestionVisual _table(
  String title,
  List<String> columns,
  List<List<Object>> rows,
) => QuestionVisual(
  kind: VisualKind.table,
  title: title,
  summary: '',
  columns: columns,
  rows: rows
      .map((r) => r.map((v) => v is num ? _n(v) : v.toString()).toList())
      .toList(),
);

QuestionVisual _chart(
  VisualKind kind,
  String title,
  List<String> labels,
  List<num> data,
  String unit,
) => QuestionVisual(
  kind: kind,
  title: title,
  summary: '',
  labels: labels,
  values: data.map((v) => v.toDouble()).toList(),
  unit: unit,
);

DiagramElement _line(
  double x,
  double y,
  double endX,
  double endY, {
  bool arrow = false,
  String color = 'mint',
}) => DiagramElement(
  shape: arrow ? 'arrow' : 'line',
  x: x,
  y: y,
  endX: endX,
  endY: endY,
  color: color,
);
DiagramElement _label(double x, double y, String label) =>
    DiagramElement(shape: 'text', x: x, y: y, label: label);
DiagramElement _box(
  double x,
  double y,
  double w,
  double h,
  String label, [
  String color = 'blue',
]) => DiagramElement(
  shape: 'rectangle',
  x: x,
  y: y,
  width: w,
  height: h,
  label: label,
  color: color,
);
QuestionVisual _diagram(String title, List<DiagramElement> elements) =>
    QuestionVisual(
      kind: VisualKind.diagram,
      title: title,
      summary: 'Şema ölçekli değildir.',
      elements: elements,
    );

const _hs = StudyLevel.lise, _uni = StudyLevel.universite;
const _lineChart = VisualKind.lineChart,
    _bar = VisualKind.barChart,
    _tab = VisualKind.table,
    _diag = VisualKind.diagram;
const _phys = 'Fizik', _chem = 'Kimya', _eng = 'Mühendislik';

final physicsFamilies = <AdvancedFamily>[
  _family(
    'rail',
    'Doğrusal hareketin grafiği',
    _hs,
    _lineChart,
    _phys,
    _rail,
    shortAnswer: false,
    multiSelect: _railClaims,
    bloom: BloomLevel.analiz,
    exam: ExamKind.ayt,
  ),
  _family(
    'impulse',
    'Kuvvet darbesi ve momentum',
    _hs,
    _lineChart,
    _phys,
    _impulse,
    bloom: BloomLevel.analiz,
    exam: ExamKind.ayt,
  ),
  _family(
    'spring',
    'Yayın kalibrasyon eğrisi',
    _hs,
    _lineChart,
    _phys,
    _spring,
    exam: ExamKind.ayt,
  ),
  _family(
    'collision',
    'Çarpışmada sistem sınırı',
    _hs,
    _diag,
    _phys,
    _collision,
    bloom: BloomLevel.analiz,
    exam: ExamKind.ayt,
  ),
  _family(
    'beam',
    'Denge ve destek tepkileri',
    _hs,
    _diag,
    _phys,
    _beam,
    bloom: BloomLevel.analiz,
    exam: ExamKind.ayt,
  ),
  _family(
    'incline',
    'Eğik düzlemde enerji bütçesi',
    _hs,
    _diag,
    _phys,
    _incline,
    exam: ExamKind.ayt,
  ),
  _family(
    'lift',
    'Asansörün serbest cisim diyagramı',
    _hs,
    _diag,
    _phys,
    _lift,
    exam: ExamKind.ayt,
  ),
  _family(
    'float',
    'Askıdaki cismin tartımı',
    _hs,
    _bar,
    _phys,
    _float,
    exam: ExamKind.tyt,
  ),
  _family(
    'calorimeter',
    'Kalorimetrede ısı alışverişi',
    _hs,
    _tab,
    _phys,
    _calorimeter,
    exam: ExamKind.tyt,
  ),
  _family(
    'wave',
    'Duran dalga deseni',
    _hs,
    _diag,
    _phys,
    _wave,
    exam: ExamKind.ayt,
  ),
  _family(
    'lens',
    'Optik tezgahta görüntü',
    _hs,
    _diag,
    _phys,
    _lens,
    exam: ExamKind.tyt,
  ),
  _family(
    'resistor',
    'Seri devrede düğüm gerilimi',
    _hs,
    _diag,
    _phys,
    _resistor,
    exam: ExamKind.tyt,
  ),
  _family(
    'cell',
    'Gerçek pilin uç gerilimi',
    _hs,
    _lineChart,
    _phys,
    _cell,
    bloom: BloomLevel.analiz,
    exam: ExamKind.ayt,
  ),
  _family(
    'faraday',
    'Akı değişimi ve indüksiyon',
    _hs,
    _lineChart,
    _phys,
    _faraday,
    exam: ExamKind.ayt,
  ),
  _family(
    'transformer',
    'Transformatörde güç aktarımı',
    _hs,
    _diag,
    _phys,
    _transformer,
    exam: ExamKind.ayt,
  ),
  _family(
    'photon',
    'Fotoelektrik enerji bütçesi',
    _hs,
    _bar,
    _phys,
    _photon,
    exam: ExamKind.ayt,
  ),
  _family(
    'hess',
    'Entalpi ve enerji profili',
    _hs,
    _lineChart,
    _chem,
    _hess,
    bloom: BloomLevel.analiz,
    exam: ExamKind.ayt,
  ),
  _family(
    'gas',
    'Hareketli piston ve gaz yasaları',
    _hs,
    _tab,
    _chem,
    _gas,
    exam: ExamKind.ayt,
  ),
  _family(
    'solubility',
    'Soğutarak kristallendirme',
    _hs,
    _lineChart,
    _chem,
    _solubility,
    exam: ExamKind.ayt,
  ),
  _family(
    'acid',
    'Asit ve baz eşdeğerliği',
    _hs,
    _tab,
    _chem,
    _acid,
    exam: ExamKind.ayt,
  ),
  _family(
    'dilute',
    'Çözeltilerde madde dengesi',
    _hs,
    _diag,
    _chem,
    _dilute,
    exam: ExamKind.ayt,
  ),
  _family(
    'isotope',
    'İzotop bolluğu ve kütle',
    _hs,
    _bar,
    _chem,
    _isotope,
    exam: ExamKind.tyt,
  ),
  _family(
    'stoich',
    'Sınırlayıcı reaktif ve artan madde',
    _hs,
    _bar,
    _chem,
    _stoich,
    bloom: BloomLevel.analiz,
    exam: ExamKind.tyt,
  ),
  _family(
    'rates',
    'Tepkime ilerleme verileri',
    _hs,
    _lineChart,
    _chem,
    _rates,
    bloom: BloomLevel.analiz,
    exam: ExamKind.ayt,
  ),
  _family(
    'effusion',
    'Gazlarda dışarı sızma deneyi',
    _hs,
    _tab,
    _chem,
    _effusion,
    exam: ExamKind.ayt,
  ),
  _family('rc', 'Birinci dereceden devre cevabı', _uni, _diag, _eng, _rc),
  _family(
    'bridge',
    'Yük hücresinin direnç köprüsü',
    _uni,
    _diag,
    _eng,
    _bridge,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'thevenin',
    'Doğrusal kaynağın eşdeğeri',
    _uni,
    _lineChart,
    _eng,
    _thevenin,
    bloom: BloomLevel.analiz,
  ),
  _family('opamp', 'Tersleyen yükselteç', _uni, _diag, _eng, _opamp),
  _family('capacitor', 'Katmanlı dielektrik', _uni, _diag, _phys, _capacitor),
  _family('inertia', 'Noktasal kütleli rotor', _uni, _diag, _phys, _inertia),
  _family(
    'pv',
    'Kapalı çevrimin işi',
    _uni,
    _tab,
    _phys,
    _pv,
    bloom: BloomLevel.analiz,
  ),
  _family('carnot', 'Tersinir ısı makinesi', _uni, _diag, _eng, _carnot),
  _family('wall', 'Katmanlı duvarda ısı iletimi', _uni, _diag, _eng, _wall),
  _family('pipe', 'Süreklilik ve Bernoulli denklemi', _uni, _diag, _eng, _pipe),
  _family('pump', 'Pompa ve hidrolik güç', _uni, _tab, _eng, _pump),
  _family(
    'stress',
    'Çekme deneyi ve eksenel esneme',
    _uni,
    _lineChart,
    _eng,
    _stress,
  ),
  _family('torsion', 'Dairesel milde burulma', _uni, _tab, _eng, _torsion),
  _family('gears', 'Bileşik dişli kutusu', _uni, _diag, _eng, _gears),
  _family(
    'signal',
    'Örnekleme ve spektrum katlanması',
    _uni,
    _bar,
    _eng,
    _signal,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'calibrate',
    'Doğrusal ölçme zinciri',
    _uni,
    _lineChart,
    _eng,
    _calibrate,
  ),
  _family(
    'batch',
    'Kapalı reaktörde birinci derece kinetik',
    _uni,
    _lineChart,
    _chem,
    _batch,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'equilibrium',
    'Gaz fazında kimyasal denge',
    _uni,
    _tab,
    _chem,
    _equilibrium,
  ),
  _family(
    'beer',
    'Spektrofotometrik standart ekleme',
    _uni,
    _lineChart,
    _chem,
    _beer,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'extract',
    'Sıvı fazlar arasında dağılım',
    _uni,
    _diag,
    _chem,
    _extract,
  ),
  _family(
    'chrom',
    'Kromatografik ayrım',
    _uni,
    _tab,
    _chem,
    _chrom,
    bloom: BloomLevel.analiz,
  ),
  _family('osmotic', 'Seyreltik çözeltide ozmoz', _uni, _tab, _chem, _osmotic),
  _family(
    'flowmix',
    'Kararlı hâlde tank bilançosu',
    _uni,
    _diag,
    _eng,
    _flowmix,
  ),
  _family(
    'uncertainty',
    'Ölçüm belirsizliği yayılımı',
    _uni,
    _tab,
    _eng,
    _uncertainty,
  ),
  _family(
    'instrument_review',
    'Ölçüm şartnamesi ve teklif değerlendirmesi',
    _uni,
    _tab,
    _eng,
    _instrumentReview,
    bloom: BloomLevel.degerlendirme,
    shortAnswer: false,
    count: 2500,
  ),
  _family(
    'thermal_design',
    'Özgün sensör kalibrasyon deneyi',
    _uni,
    _tab,
    _eng,
    _designLab,
    bloom: BloomLevel.yaratma,
    shortAnswer: false,
    count: 2500,
    creation: _thermalDesign,
  ),
  _family(
    'quantum',
    'Enerji seviyeleri ve geçişler',
    _uni,
    _diag,
    _phys,
    _quantum,
    bloom: BloomLevel.analiz,
  ),
];

AdvancedItem _rail(int a, int b, int c, bool second) {
  final v0 = a, v1 = a + b, v2 = a + b + c;
  final t = c + 1;
  final v = _chart(
    _lineChart,
    'Hız (m/s) – zaman (s)',
    ['0', '$t', '${2 * t}'],
    [v0, v1, v2],
    'm/s',
  );
  if (second)
    return _item(
      v,
      'Araçta hız, ölçüm noktaları arasında doğrusal değişiyor. İkinci zaman aralığındaki ortalama ivme kaç m/s² olur?',
      c / t,
      'm/s²',
      [b / t, (b + c) / (2 * t), v2 / t],
      'İkinci parçada Δv = $c m/s ve Δt = $t s. İvme Δv/Δt ile bulunur.',
    );
  return _item(
    v,
    'Araçta hız, ölçüm noktaları arasında doğrusal değişiyor. Çizilen aralığın tamamında araç kaç metre ilerler?',
    (v0 + 2 * v1 + v2) * t / 2,
    'm',
    [(v0 + v2) * t, 2 * t * v1, (v1 + v2) * t / 2],
    'Hız–zaman grafiğinin altındaki iki yamuğun alanı toplanır. Toplam yol ($v0 + 2×$v1 + $v2) × $t / 2 olur.',
  );
}

// Display exact ratios so a rounded distractor cannot coincide with the key.
String _ratio(int numerator,int denominator) {
  final common=numerator.gcd(denominator);
  final top=numerator~/common, bottom=denominator~/common;
  return bottom==1 ? '$top' : '$top/$bottom';
}

MultiSelectTask _railClaims(AdvancedItem item,int index) {
  final chart=item.visual!;
  final v0=chart.values[0].toInt(), v1=chart.values[1].toInt(), v2=chart.values[2].toInt();
  final dt=int.parse(chart.labels[1])-int.parse(chart.labels[0]);
  final twiceFirst=(v0+v1)*dt, twiceLast=(v1+v2)*dt;
  final twiceTotal=twiceFirst+twiceLast;
  final late=index>=2500;
  // Each distractor substitutes an endpoint for an interval average or a change.
  // Velocities rise strictly in both segments, so these substitutions are unequal.
  final facts=late
    ? <(String,String,String,String)>[
        ('İlk aralığın ortalama ivmesi',_ratio(v1-v0,dt),_ratio(v1,dt),'m/s²'),
        ('İkinci aralığın ortalama ivmesi',_ratio(v2-v1,dt),_ratio(v2,dt),'m/s²'),
        ('İlk aralıkta alınan yol',_ratio(twiceFirst,2),'${v1*dt}','m'),
        ('Tüm sürenin ortalama sürati',_ratio(twiceTotal,4*dt),'$v2','m/s'),
      ]
    : <(String,String,String,String)>[
        ('İlk aralıktaki hız artışı','${v1-v0}','$v1','m/s'),
        ('İki aralıkta alınan toplam yol',_ratio(twiceTotal,2),'${(v0+v1)*dt}','m'),
        ('İkinci aralığın ortalama sürati',_ratio(v1+v2,2),'$v2','m/s'),
        ('Tüm sürenin ortalama ivmesi',_ratio(v2-v0,2*dt),_ratio(v2,2*dt),'m/s²'),
      ];
  const pairs=[(0,1),(0,2),(0,3),(1,2),(1,3),(2,3)];
  final pair=pairs[(v0+v1+dt)%pairs.length];
  final correct={pair.$1,pair.$2};
  if(v0>=15){
    final others=[for(var j=0;j<4;j++)if(!correct.contains(j))j];
    correct.add(others[v2%2]);
  }
  final choices=<String>[], exact=<String>[];
  for(var j=0;j<facts.length;j++){
    final f=facts[j];
    choices.add('${f.$1} ${correct.contains(j)?f.$2:f.$3} ${f.$4} olur.');
    exact.add('${f.$1} ${f.$2} ${f.$4}');
  }
  return MultiSelectTask(late
    ? 'Hız noktalar arasında doğrusal değişiyor. İki aralığın ivmeleri, ilk aralığın yolu ve genel ortalama sürat için doğru ifadeleri seçin.'
    : 'Hız noktalar arasında doğrusal değişiyor. Hız artışı, toplam yol, ikinci aralığın sürati ve genel ivme için doğru ifadeleri seçin.',
    choices,correct.toList()..sort(),
    'Her aralık $dt saniyedir. Hız değişimleri ${v1-v0} ve ${v2-v1} m/s olur. İvme Δv/Δt, yol hız–zaman grafiğinin altındaki yamuk alanı, ortalama sürat ise toplam yol/toplam süredir. ${exact.join('. ')}.');
}

AdvancedItem _impulse(int a, int b, int c, bool second) {
  final dt = c + 1;
  final v = _chart(
    _lineChart,
    'Net kuvvet (N) – zaman (s)',
    ['0', '$dt', '${2 * dt}'],
    [a, a + b, a],
    'N',
  );
  final j = (2 * a + b) * dt;
  if (second)
    return _item(
      v,
      'Kuvvetler aynı doğrultudadır. Başlangıçta duran $c kg kütle, grafiğin sonunda kaç m/s hıza ulaşır?',
      j / c,
      'm/s',
      [j, (a + b) * dt / c, 2 * (a + b) * dt / c],
      'Kuvvetin zamana göre alanı $j N·s itmedir. Başlangıç momentumu sıfır olduğundan son hız itmenin $c kg kütleye bölümüdür.',
    );
  return _item(
    v,
    'Kuvvet örnekler arasında doğrusal değişiyor. Gösterilen sürede toplam itme kaç N·s olur?',
    j,
    'N·s',
    [2 * (a + b) * dt, b * dt, a * dt * 2],
    'Sabit taban kuvveti $a N, ${2 * dt} s boyunca etkir. Üzerindeki üçgenin alanı ${2 * dt} × $b / 2 olduğundan iki alan toplanır.',
  );
}

AdvancedItem _spring(int a, int b, int c, bool second) {
  final x = c * 2, f = a * b;
  final v = _chart(
    _lineChart,
    'Çekme kuvveti (N) – uzama (cm)',
    ['0', '$x', '${2 * x}'],
    [a, a + f, a + 2 * f],
    'N',
  );
  if (second)
    return _item(
      v,
      'Yay düzeneği gösterilen başlangıç gerilimiyle çalışıyor. 0 cm ile son konum arasında uygulanan kuvvetin yaptığı iş kaç joule olur?',
      (a + f) * 2 * x / 100,
      'J',
      [f * x / 100, (a + 2 * f) * 2 * x / 100, 2 * f * x / 100],
      'Kuvvet–yol eğrisinin alanı, ortalama kuvvet ${a + f} N ile ${_n(2 * x / 100)} m yer değiştirmenin çarpımıdır.',
    );
  return _item(
    v,
    'Ön gerilimli yayın doğrusal bölgesinde etkili yay sabiti kaç N/m olur?',
    f * 100 / x,
    'N/m',
    [(a + f) * 100 / x, f / x, f * 100 / (2 * x)],
    'Ön gerilim eğimi değiştirmez. Ardışık noktalar arasında kuvvet $f N, uzunluk ${_n(x / 100)} m değişir. Yay sabiti ΔF/Δx olur.',
  );
}

AdvancedItem _collision(int a, int b, int c, bool second) {
  final u = c + 1;
  final v = _diagram('Hava rayı · çarpışmadan önce', [
    _box(22, 53, 31, 21, '$a kg'),
    _box(78, 53, 31, 21, '$b kg'),
    _line(10, 67, 93, 67),
    _line(24, 32, 50, 32, arrow: true),
    _label(34, 17, '$u m/s'),
    _label(78, 28, 'Durgun'),
  ]);
  final vf = a * u / (a + b);
  if (second)
    return _item(
      v,
      'Arabalar çarpışıp birlikte hareket ediyor. Dış yatay itme yoksa çarpışmada kaybolan kinetik enerji kaç joule olur?',
      a * b * u * u / (2 * (a + b)),
      'J',
      [a * u * u / 2, (a + b) * vf * vf / 2, a * b * u * u / (a + b)],
      'Momentum korunumu ortak hızı m₁u/(m₁+m₂) verir. İlk enerjiden son enerji çıkarılınca kayıp m₁m₂u²/[2(m₁+m₂)] olur.',
    );
  return _item(
    v,
    'Sürtünmesiz raydaki arabalar temas edince birbirine kenetleniyor. Ortak sürat kaç m/s olur?',
    vf,
    'm/s',
    [u, a * u / b, b * u / (a + b)],
    'Başlangıçta yalnız soldaki arabanın momentumu vardır. Çarpışmadan sonra ${a * u} kg·m/s momentum ${a + b} kg toplam kütle tarafından taşınır.',
  );
}

AdvancedItem _beam(int a, int b, int c, bool second) {
  final f = 10 * c;
  final v = _diagram('Basit mesnetli kiriş · yük konumu', [
    _line(10, 59, 90, 59),
    _label(12, 78, 'A'),
    _label(88, 78, 'B'),
    _line(52, 18, 52, 53, arrow: true, color: 'gold'),
    _label(66, 18, '$f kN'),
    _label(29, 43, '$a m'),
    _label(73, 43, '$b m'),
    const DiagramElement(shape: 'triangle', x: 12, y: 66, width: 8, height: 12),
    const DiagramElement(shape: 'triangle', x: 88, y: 66, width: 8, height: 12),
  ]);
  final arm = second ? b : a;
  return _item(
    v,
    'Kiriş ağırlığı ihmal ediliyor. Tekil yük ile mesnetler arasındaki uzaklıklara göre ${second ? 'A' : 'B'} mesnedinin düşey tepki kuvveti kaç kN olur?',
    f * arm / (a + b),
    'kN',
    [f, f / 2, f * arm / (second ? a : b)],
    'Diğer mesnede göre moment alınır. Aranan tepki × ${a + b} m = $f kN × $arm m. Tepki yukarı yönlüdür.',
  );
}

AdvancedItem _incline(int a, int b, int c, bool second) {
  final rise = a, run = a + b, mass = c;
  final v = _diagram('Sabit hızla çekilen kızak', [
    _line(12, 75, 87, 75),
    _line(87, 75, 87, 20),
    _line(12, 75, 87, 20),
    _label(37, 36, '$run m yol'),
    _label(78, 88, 'h = $rise m'),
    _box(55, 52, 21, 15, '$mass kg'),
  ]);
  if (second)
    return _item(
      v,
      'Sürtünme yoktur. Kızak alttan en üste sabit hızla çıkarılırken eğime paralel çekme kuvveti kaç N olur? g = 10 m/s².',
      mass * 10 * rise / run,
      'N',
      [mass * 10, mass * 10 * run / rise, mass * rise / run],
      'Hız değişmediği için çekme işi potansiyel enerji artışına eşittir. F × $run = $mass × 10 × $rise.',
    );
  return _item(
    v,
    'Kızak alt düzeyden üst düzeye çıkarıldığında yer çekimi potansiyel enerjisi kaç joule artar? g = 10 m/s².',
    mass * 10 * rise,
    'J',
    [mass * 10 * run, mass * rise, mass * 10 * (run - rise)],
    'Potansiyel enerji değişimi ΔU = mgh ile bulunur. Düşey yükselme $rise m, kütle $mass kg olur.',
  );
}

AdvancedItem _lift(int a, int b, int c, bool second) {
  final m = 10 * a, net = b + 20 * (c - 2), tension = m * 10 + net;
  final v = _diagram('Yük hücreli platform · düşey kuvvetler', [
    _box(50, 52, 30, 17, '$m kg'),
    _line(50, 42, 50, 15, arrow: true),
    _label(72, 24, '$tension N'),
    _line(50, 61, 50, 88, arrow: true, color: 'gold'),
    _label(70, 81, 'Ağırlık'),
  ]);
  if (second)
    return _item(
      v,
      'Kuvvetler $c saniye sabit kalıyor. Yukarıyı pozitif alırsak hız değişimi kaç m/s olur? g = 10 m/s².',
      net * c / m,
      'm/s',
      [tension * c / m, net / m, 10 * c],
      'Net kuvvet $tension − ${10 * m} = $net N olur. İvme Fnet/m ile, hız değişimi bu ivme ile $c s sürenin çarpımıyla bulunur.',
    );
  return _item(
    v,
    'Kuvvetler şekildeki gibidir. g = 10 m/s² iken platformun yukarı yönlü ivmesi kaç m/s² olur?',
    net / m,
    'm/s²',
    [tension / m, net / (m * 10), 10 + net / m],
    'Aşağı yönlü ağırlık ${m * 10} N olur. Net kuvvet $net N yukarı yönlüdür. Newton yasasıyla bu kuvvet $m kg kütleye bölünür.',
  );
}

AdvancedItem _float(int a, int b, int c, bool second) {
  final wet = 2 * a, buoy = 2 * b;
  final v = _chart(
    _bar,
    'Dinamometre okuması (N)',
    ['Hava', 'Sıvı'],
    [wet + buoy, wet],
    'N',
  );
  final rho = 800 + 100 * c;
  if (second)
    return _item(
      v,
      'Cisim yoğunluğu $rho kg/m³ olan sıvıya bütünüyle batırılıyor. Havanın kaldırması ihmal edilirse cismin ortalama yoğunluğu kaç kg/m³ olur?',
      rho * (wet + buoy) / buoy,
      'kg/m³',
      [rho * wet / buoy, rho * buoy / (wet + buoy), rho * (wet + buoy) / wet],
      'Havadaki ağırlığın kaldırma kuvvetine oranı cisim yoğunluğunun sıvı yoğunluğuna oranıdır. Kaldırma kuvveti iki okumanın farkı $buoy N olur.',
    );
  return _item(
    v,
    'Cisim yoğunluğu $rho kg/m³ olan sıvıya bütünüyle batırılıyor. Hava kaldırması önemsiz ve g = 10 m/s² ise cismin hacmi kaç litredir?',
    buoy * 100 / rho,
    'L',
    [(wet + buoy) * 100 / rho, wet * 100 / rho, buoy * 1000 / rho],
    'Okuma farkı $buoy N, yer değiştiren sıvının ağırlığıdır. Hacim ΔF/(ρg) ile m³ olarak bulunup litreye çevrilir.',
  );
}

AdvancedItem _calorimeter(int a, int b, int c, bool second) {
  final cold = a, hot = a + 30 + c, m1 = 10 * b, m2 = 10 * c;
  final v = _table(
    'Yalıtılmış kap · iki su örneği',
    ['Örnek', 'Kütle (g)', 'Sıcaklık (°C)'],
    [
      ['K', m1, cold],
      ['L', m2, hot],
    ],
  );
  final tf = (m1 * cold + m2 * hot) / (m1 + m2);
  if (second)
    return _item(
      v,
      'Kap ısı almıyor. Isı dengesi kurulana kadar soğuk suyun aldığı ısı kaç joule olur? Suyun öz ısısı 4,2 J/(g·°C).',
      m1 * 4.2 * (tf - cold),
      'J',
      [m1 * 4.2 * (hot - cold), m2 * 4.2 * (hot - cold), m1 * (tf - cold)],
      'Önce ortak sıcaklık (m₁T₁+m₂T₂)/(m₁+m₂) ile bulunur. Soğuk suyun aldığı ısı m₁ × 4,2 × (Tdenge−T₁) olur.',
    );
  return _item(
    v,
    'Kap ısı almıyorsa su örnekleri karıştırıldığında denge sıcaklığı kaç °C olur?',
    tf,
    '°C',
    [(hot + cold) / 2, (m2 * cold + m1 * hot) / (m1 + m2), tf - cold],
    'İki örneğin öz ısıları eşittir. Denge sıcaklığı kütle ağırlıklı ortalama ($m1 × $cold + $m2 × $hot) / ${m1 + m2} olur.',
  );
}

AdvancedItem _wave(int a, int b, int c, bool second) {
  final length = 5 * a, f = 10 * b, loops = c;
  final elements = <DiagramElement>[
    _line(8, 54, 92, 54),
    _label(27, 87, 'L = $length cm'),
    _label(74, 87, 'f = $f Hz'),
  ];
  for (var i = 0; i < loops; i++) {
    final x = 8 + 84 * i / loops, next = 8 + 84 * (i + 1) / loops;
    final peak = i.isEven ? 29.0 : 70.0;
    for (var j = 0; j < 8; j++) {
      final u = j / 8, w = (j + 1) / 8;
      elements.add(
        _line(
          x + (next - x) * u,
          54 + (peak - 54) * math.sin(math.pi * u),
          x + (next - x) * w,
          54 + (peak - 54) * math.sin(math.pi * w),
          color: 'gold',
        ),
      );
    }
  }
  final v = _diagram('İki ucu sabit tel · anlık duran dalga', elements);
  final wl = 2 * length / loops;
  if (second)
    return _item(
      v,
      'Şekildeki karınları sayarak teldeki dalganın yayılma hızını m/s cinsinden bulunuz.',
      wl * f / 100,
      'm/s',
      [length * f / 100, wl * f, wl * f / 200],
      'Tel üzerinde $loops yarım dalga boyu yer alır. Dalga boyu 2L/$loops, hız ise frekans ile metreye çevrilmiş dalga boyunun çarpımıdır.',
    );
  return _item(
    v,
    'Telin çizimdeki titreşim frekansı veriliyor. Gerilim ve tel aynı kalırsa temel titreşim frekansı kaç Hz olur?',
    f / loops,
    'Hz',
    [f * loops, f / (2 * loops), f],
    'İki ucu sabit telde karın sayısı harmonik sırasıdır. Şekilde $loops karın bulunduğundan temel frekans $f/$loops olur.',
  );
}

AdvancedItem _lens(int a, int b, int c, bool second) {
  final obj = 10 + a, img = 10 + b, h = c;
  final v = _diagram('İnce mercek · gerçek görüntünün yeri', [
    _line(6, 60, 94, 60),
    _line(49, 22, 49, 84),
    _line(14, 60, 14, 31, arrow: true),
    _line(85, 60, 85, 79, arrow: true),
    _label(28, 75, '$obj cm'),
    _label(67, 43, '$img cm'),
    _label(20, 17, 'h = $h cm'),
  ]);
  if (second)
    return _item(
      v,
      'Cisim ve ters gerçek görüntüsü şemada gösteriliyor. Görüntünün boyunun mutlak değeri kaç cm olur?',
      h * img / obj,
      'cm',
      [h * obj / img, h * (obj + img) / obj, h * img / (obj + img)],
      'Benzer üçgenlerden mutlak büyütme görüntü uzaklığı/cisim uzaklığıdır. Görüntü boyu $h × $img/$obj olur.',
    );
  return _item(
    v,
    'İnce yakınsak mercek havadadır. Şekildeki cisim ve gerçek görüntü uzaklıklarına göre odak uzaklığı kaç cm olur?',
    obj * img / (obj + img),
    'cm',
    [obj + img, (obj + img) / 2, obj * img / (obj + 2 * img)],
    'İnce mercek bağıntısı 1/f = 1/dc + 1/dg şeklindedir. Gerçek cisim ve gerçek görüntü için her iki uzaklık pozitiftir.',
  );
}

AdvancedItem _resistor(int a, int b, int c, bool second) {
  final e = 6 * c;
  final v = _diagram('İdeal kaynakla seri dirençler', [
    _line(8, 48, 92, 48),
    _box(33, 48, 25, 18, '$a Ω'),
    _box(67, 48, 25, 18, '$b Ω'),
    _label(10, 25, '+$e V'),
    _label(88, 25, '0 V'),
    _label(50, 68, 'K'),
  ]);
  final current = e / (a + b);
  if (second)
    return _item(
      v,
      'K, iki direncin birleştiği noktadır. Sağ uç referans alındığında K noktasının gerilimi kaç volt olur?',
      current * b,
      'V',
      [current * a, e, current * (a + b) / 2],
      'Seri akım E/(Rsol+Rsağ) olur. Sağ uçtan K noktasına gerilim artışı sağ dirençteki I × Rsağ düşümüne eşittir.',
    );
  return _item(
    v,
    'İdeal iletkenler ve ohmik dirençler kullanılıyor. Soldaki dirençte harcanan güç kaç watt olur?',
    current * current * a,
    'W',
    [current * current * b, current * e, e * e / a],
    'İki dirençten aynı I = $e/($a+$b) akımı geçer. Sol dirençteki güç I² × $a ile hesaplanır.',
  );
}

AdvancedItem _cell(int a, int b, int c, bool second) {
  final r = (a + 1) / 10, i = c, emf = 2 * b + 50;
  final v = _chart(
    _lineChart,
    'Uç gerilimi (V) – çıkış akımı (A)',
    ['0', '$i', '${2 * i}'],
    [emf, emf - i * r, emf - 2 * i * r],
    'V',
  );
  if (second)
    return _item(
      v,
      'Pili sabit elektromotor kuvvet ve seri iç dirençle modelleyiniz. $i A akım akarken pil içinde ısıya dönüşen güç kaç watt olur?',
      i * i * r,
      'W',
      [i * (emf - i * r), i * emf, i * r],
      'Açık devreden yük akımına geçerken gerilim I r kadar düşer. İç kayıp I²r = I × (E−U) olur.',
    );
  return _item(
    v,
    'Uç gerilimindeki azalmayı modelleyen seri iç direnç kaç ohm olur?',
    r,
    'Ω',
    [emf / i, (emf - i * r) / i, 2 * r],
    'U = E−Ir olduğundan gerilim-akım eğiminin mutlak değeri iç dirençtir. İlk aralıkta gerilim ${_n(i * r)} V azalırken akım $i A artar.',
  );
}

AdvancedItem _faraday(int a, int b, int c, bool second) {
  final n = 10 * c, dt = b, flux = a;
  final v = _chart(
    _lineChart,
    'Tek sarımın akısı (mWb) – zaman (ms)',
    ['0', '$dt', '${2 * dt}'],
    [a, 2 * a, 3 * a],
    'mWb',
  );
  final emf = n * flux / dt;
  if (second)
    return _item(
      v,
      '$n sarımlı bobinin uçları ideal bir $c Ω yüke bağlıdır. Özindüksiyon ve bobin direnci ihmal edilirse indüklenen akımın büyüklüğü kaç A olur?',
      emf / c,
      'A',
      [emf, flux / dt / c, emf * c],
      'Akı her $dt ms içinde $flux mWb değişir. Faraday yasasıyla |ε| = N|ΔΦ/Δt| olur. Yükteki akım |ε|/R ile bulunur.',
    );
  return _item(
    v,
    'Birbirine eş $n sarımın her birinden grafikteki akı geçiyor. Bobinin uçları arasında oluşan elektromotor kuvvetin büyüklüğü kaç volt olur?',
    emf,
    'V',
    [flux / dt, emf * 2, emf / 1000],
    'Faraday yasasında tek sarımın akı eğimi sarım sayısıyla çarpılır. mWb/ms ile Wb/s aynı sayısal değere sahiptir.',
  );
}

AdvancedItem _transformer(int a, int b, int c, bool second) {
  final n1 = 50 * a, n2 = 50 * b, u = 10 * c;
  final v = _diagram('İdeal transformatör · etkin değerler', [
    _box(24, 48, 30, 33, '$n1 sarım'),
    _box(76, 48, 30, 33, '$n2 sarım'),
    _line(43, 27, 43, 69),
    _line(56, 27, 56, 69),
    _label(24, 80, 'Giriş $u V'),
    _label(76, 80, 'Çıkış'),
  ]);
  if (second)
    return _item(
      v,
      'İkincil sargıya $c Ω saf direnç takılıyor. İdeal transformatörün çıkışındaki etkin akım kaç amper olur?',
      u * b / (a * c),
      'A',
      [u / c, u * a / (b * c), u * b / a],
      'Gerilim sarım sayıları oranında değişir. Çıkış gerilimi U₁N₂/N₁, dirençteki etkin akım bu gerilimin yük direncine bölümüdür.',
    );
  return _item(
    v,
    'İdeal transformatörün ikincil sargısındaki etkin gerilim kaç volt olur?',
    u * b / a,
    'V',
    [u * a / b, u * (a + b) / a, u * b / (a + b)],
    'İki sargı aynı değişken manyetik akıyı bağlar. U₂/U₁ = N₂/N₁ olduğundan çıkış $u × $n2 / $n1 volt olur.',
  );
}

AdvancedItem _photon(int a, int b, int c, bool second) {
  final threshold = 1 + a / 10, extra = 0.2 + b / 10, extra2 = extra + c / 10;
  final v = _chart(
    _bar,
    'Metale gelen foton enerjileri (eV)',
    ['Eşik', 'K ışını', 'L ışını'],
    [threshold, threshold + extra, threshold + extra2],
    'eV',
  );
  if (second)
    return _item(
      v,
      'Aynı metalde K yerine L ışını kullanılıyor. Durdurma potansiyeli kaç volt artar?',
      extra2 - extra,
      'V',
      [extra2, extra, (extra + extra2) / 2],
      'İş fonksiyonu iki ölçümde aynıdır. Maksimum kinetik enerjideki artış foton enerjilerinin farkına eşittir. eV cinsinden bu fark durdurma gerilimi artışını volt olarak verir.',
    );
  return _item(
    v,
    'Grafikteki eşik enerjisi metalin iş fonksiyonudur. L ışınının kopardığı elektronların en büyük kinetik enerjisi kaç eV olur?',
    extra2,
    'eV',
    [threshold + extra2, extra, threshold + extra + extra2],
    'Fotoelektrik bağıntısı Kmax = Efoton − W biçimindedir. L sütunundan eşik sütunu çıkarılır.',
  );
}

AdvancedItem _hess(int a, int b, int c, bool second) {
  final product = 2 * a, react = product + 2 * b, top = react + 5 * c;
  final v = _chart(
    _lineChart,
    'Tepkime koordinatında enerji (kJ/mol)',
    ['Giren', 'Geçiş', 'Ürün'],
    [react, top, product],
    'kJ/mol',
  );
  if (second)
    return _item(
      v,
      'Grafik bir basamaklı tepkimeye aittir. Üründen girenlere doğru ters yönde gereken aktivasyon enerjisi kaç kJ/mol olur?',
      top - product,
      'kJ/mol',
      [top - react, react - product, top],
      'Ters yönde başlangıç enerji düzeyi üründür. Geçiş durumuna erişmek için $top − $product kJ/mol gerekir.',
    );
  return _item(
    v,
    'İleri yöndeki tepkimenin molar entalpi değişimi ΔH kaç kJ/mol olur?',
    product - react,
    'kJ/mol',
    [react - product, top - react, product - top],
    'Entalpi değişimi ürün enerjisi eksi giren enerjisidir. Ürün daha düşük enerjide olduğundan ΔH negatiftir.',
  );
}

AdvancedItem _gas(int a, int b, int c, bool second) {
  final p = 50 + 5 * a, vol = b, temp = 250 + 10 * c;
  final v = _table(
    'Kapalı silindir · ideal gaz',
    ['Durum', 'P (kPa)', 'V (L)', 'T (K)'],
    [
      ['I', p, vol, temp],
      ['II', 2 * p, '?', temp + 50],
    ],
  );
  final v2 = vol * (temp + 50) / (2 * temp);
  if (second)
    return _item(
      v,
      'Gaz miktarı sabit tutuluyor. I ve II durumları arasında hacim ilk değere göre yüzde kaç azalır?',
      100 * (vol - v2) / vol,
      '%',
      [(100 * v2 / vol), 50, 100 * (vol - v2) / v2],
      'Birleşik gaz yasasıyla V₂/V₁ = (T₂/T₁)(P₁/P₂). Başlangıca göre yüzde azalma 100 × (1−V₂/V₁) olur.',
    );
  return _item(
    v,
    'Gaz miktarı değişmiyorsa ikinci durumda pistonun sınırladığı hacim kaç litre olur?',
    v2,
    'L',
    [vol / 2, 2 * vol * (temp + 50) / temp, vol * temp / (2 * (temp + 50))],
    'Aynı ideal gaz örneği için PV/T sabittir. V₂ = V₁(P₁/P₂)(T₂/T₁) olur ve sıcaklıklar kelvin cinsinden kullanılır.',
  );
}

AdvancedItem _solubility(int a, int b, int c, bool second) {
  final lower = a + 8, upper = lower + b;
  final v = _chart(
    _lineChart,
    'Çözünürlük (g tuz / 100 g su) – sıcaklık (°C)',
    ['20', '40', '60'],
    [lower, lower + b / 2, upper],
    'g/100 g',
  );
  final water = c * 50;
  if (second)
    return _item(
      v,
      '60 °C’de $water g su ile doygun çözelti hazırlanıp 20 °C’ye soğutuluyor. Su kaybı yoksa kristaller süzüldükten sonra kalan çözeltinin kütlesi kaç gramdır?',
      water * (1 + lower / 100),
      'g',
      [water * lower / 100, water * (1 + upper / 100), water * b / 100],
      '20 °C’de her 100 g su $lower g tuz taşır. Filtrattan kristaller ayrılmıştır. Suyun kütlesine çözünmüş tuz kütlesi eklenir.',
    );
  return _item(
    v,
    '60 °C’de $water g su ile hazırlanan doygun çözelti 20 °C’ye soğutuluyor. Su buharlaşmıyor ve denge kuruluyorsa kaç gram susuz kristal ayrılır?',
    water * b / 100,
    'g',
    [water * upper / 100, water * lower / 100, water * b / 200],
    'Çözünürlük 100 g su başına $upper − $lower = $b g azalır. Bu fark $water/100 ile çarpılır.',
  );
}

AdvancedItem _acid(int a, int b, int c, bool second) {
  final va = 10 + a, ca = 10 * b, cb = 10 * c;
  final v = _table(
    'Kuvvetli asit – kuvvetli baz titrasyonu',
    ['Çözelti', 'Derişim (mmol/L)', 'Hacim (mL)'],
    [
      ['HCl', ca, va],
      ['NaOH', cb, 'Büret'],
    ],
  );
  final vb = va * ca / cb;
  if (second)
    return _item(
      v,
      'Eşdeğerlik noktasına kadar NaOH eklenmiştir. Hacimler toplanabiliyorsa bu noktada Na⁺ derişimi kaç mmol/L olur?',
      ca * va / (va + vb),
      'mmol/L',
      [ca, cb, ca * va / vb],
      'Eşdeğerlikte eklenen NaOH miktarı ilk HCl miktarına eşittir. Na⁺ derişimi CₐVₐ/(Vₐ+Vᵦ) olup Vᵦ = CₐVₐ/Cᵦ kullanılır.',
    );
  return _item(
    v,
    'HCl çözeltisinin tamamını nötrlemek için büretten kaç mL NaOH çözeltisi verilmelidir?',
    vb,
    'mL',
    [va * cb / ca, va, va + vb],
    'HCl ve NaOH 1:1 tepkime verir. Eşdeğerlikte CₐVₐ = CᵦVᵦ olduğundan gereken hacim $ca × $va / $cb mL olur.',
  );
}

AdvancedItem _dilute(int a, int b, int c, bool second) {
  final va = 5 * a, vb = 5 * b, ca = 50 * c;
  final v = _diagram('Çözelti hazırlama · hacimler toplanır', [
    _box(24, 40, 33, 30, '$va mL'),
    _box(77, 40, 33, 30, '$vb mL'),
    _label(24, 70, '$ca mmol/L'),
    _label(76, 70, 'Saf su'),
    _line(43, 40, 58, 40, arrow: true),
  ]);
  final cf = va * ca / (va + vb);
  if (second)
    return _item(
      v,
      'İki sıvı karıştırıldıktan sonra homojen karışımdan $c mL örnek çekiliyor. Bu örnekte kaç mikromol çözünen bulunur?',
      cf * c,
      'µmol',
      [ca * c, cf, va * ca],
      'Seyreltilmiş derişim C₁V₁/(V₁+Vsu) olur. mmol/L ile µmol/mL eşdeğerdir. Derişim alınan $c mL ile çarpılır.',
    );
  return _item(
    v,
    'Şekilde soldaki stok çözelti sağdaki saf suyla karıştırılıyor. Çözünen kaybı yoksa son derişim kaç mmol/L olur?',
    cf,
    'mmol/L',
    [ca, ca * vb / (va + vb), ca * va / vb],
    'Çözünen miktarı stok çözeltiden gelir. Aynı miktar ${va + vb} mL toplam hacme dağılır. Cson = Cstok × Vstok / Vson olur.',
  );
}

AdvancedItem _isotope(int a, int b, int c, bool second) {
  final light = 40 + a, heavy = light + c, p = 20 + 2 * b;
  final v = _chart(
    _bar,
    'İzotopların atom sayısına göre bolluğu (%)',
    ['$light u', '$heavy u'],
    [100 - p, p],
    '%',
  );
  if (second)
    return _item(
      v,
      'Örnek tam ${100 * c} atom içeriyor ve izotop kütleleri grafikteki değerler kabul ediliyor. Ağır izotopların toplam kütlesi kaç u olur?',
      p * c * heavy,
      'u',
      [(100 - p) * c * light, p * c * light, p * heavy],
      'Ağır izotop sayısı toplam atom sayısının yüzde $p kadarıdır. Bu atom sayısı $heavy u ile çarpılır.',
    );
  return _item(
    v,
    'Kurgusal element yalnızca bu iki izotoptan oluşuyor. Verilen kütlelerle ortalama atom kütlesi kaç u olur?',
    (light * (100 - p) + heavy * p) / 100,
    'u',
    [(light + heavy) / 2, (light * p + heavy * (100 - p)) / 100, heavy],
    'Her izotopun kütlesi atom sayısındaki payıyla çarpılır. Ortalama [$light × ${100 - p} + $heavy × $p]/100 olur.',
  );
}

AdvancedItem _stoich(int a, int b, int c, bool second) {
  final n = a, h = 3 * a + b, yieldP = 50 + 5 * c;
  final v = _chart(
    _bar,
    'Başlangıçtaki madde miktarı (mol)',
    ['N₂', 'H₂'],
    [n, h],
    'mol',
  );
  if (second)
    return _item(
      v,
      'N₂ + 3H₂ → 2NH₃ tepkimesinde gerçekleşen dönüşüm kuramsal verimin %$yieldP kadarıdır. Başka tepkime yoksa kaç mol H₂ artar?',
      h - 3 * n * yieldP / 100,
      'mol',
      [b, h - n * yieldP / 100, h - 3 * n * yieldP / 200],
      'Azot sınırlayıcıdır. Verilen gerçekleşme oranında harcanan hidrojen 3 × n(N₂) × $yieldP/100 moldür. Bu değer başlangıçtaki hidrojenden çıkarılır.',
    );
  return _item(
    v,
    'N₂ + 3H₂ → 2NH₃ denklemine göre tepkime verimi %$yieldP ise elde edilen amonyak kaç moldür?',
    2 * n * yieldP / 100,
    'mol',
    [2 * n, 2 * h * yieldP / 300, n * yieldP / 100],
    'H₂ miktarı $n mol N₂ için gereken ${3 * n} molden fazladır. Kuramsal amonyak 2 × $n moldür. Gerçek ürün için verimle çarpılır.',
  );
}

AdvancedItem _rates(int a, int b, int c, bool second) {
  final end = a, step = b, dt = c;
  final v = _chart(
    _lineChart,
    'A miktarı (mmol) – zaman (s)',
    ['0', '$dt', '${2 * dt}'],
    [end + 3 * step, end + step, end],
    'mmol',
  );
  final delta = second ? step : 2 * step;
  return _item(
    v,
    '2A → 3B tepkimesinde hacim sabittir. ${second ? 'İkinci' : 'İlk'} zaman aralığında B maddesinin ortalama oluşum hızı kaç mmol/s olur?',
    1.5 * delta / dt,
    'mmol/s',
    [delta / dt, 2 * delta / (3 * dt), 3 * delta / dt],
    'İlgili aralıkta $delta mmol A tüketilir. Denklem gereği oluşan B bunun 3/2 katıdır. Ürün miktarı $dt saniyeye bölünür.',
  );
}

AdvancedItem _effusion(int a, int b, int c, bool second) {
  final m = a + 10, k = c, t = b + 10;
  final v = _table(
    'Küçük delikten efüzyon · eşit T ve P',
    ['Gaz', 'M (g/mol)', 'Eşit miktar için süre (s)'],
    [
      ['X', m, t],
      ['Y', m * k * k, '?'],
    ],
  );
  if (second)
    return _item(
      v,
      'Gazların hızları Graham yasasına uyuyor. Aynı sürede kaç mol X çıkarsa 1 mol Y çıkmış olur?',
      k,
      'mol',
      [k * k, 1 / k, 1 / (k * k)],
      'Efüzyon hızı molar kütlenin kareköküyle ters orantılıdır. Aynı sürede çıkan mol oranı √(Mᵧ/Mₓ) = √${k * k} olur.',
    );
  return _item(
    v,
    'Aynı küçük delikten eşit mol gazın çıkması için Y gazında kaç saniye gerekir?',
    t * k,
    's',
    [t / k, t * k * k, t],
    'Eşit madde miktarı için süre hızla ters orantılıdır. Dolayısıyla tᵧ/tₓ = √(Mᵧ/Mₓ) = $k olur.',
  );
}

AdvancedItem _rc(int a, int b, int c, bool second) {
  final e = 2 * c, res = a, cap = b;
  final v = _diagram('RC şarj devresi · anahtar t = 0 anında kapanır', [
    _line(8, 46, 91, 46),
    _box(36, 46, 25, 16, '$res kΩ'),
    _box(70, 46, 25, 16, '$cap µF'),
    _label(12, 23, '+$e V'),
    _label(90, 68, '0 V'),
  ]);
  final tau = res * cap;
  if (second)
    return _item(
      v,
      'Başlangıçta yüksüz kondansatör ideal bir gerilim basamağı ile şarj ediliyor. Bir zaman sabiti sonra kondansatörde kaç µC yük bulunur?',
      cap * e * (1 - math.exp(-1)),
      'µC',
      [cap * e, cap * e * math.exp(-1), cap * e / 2],
      'q(t) = CE[1−exp(−t/RC)] bağıntısında t = RC için zaman çarpanı 1−1/e olur. µF ile volt çarpımı µC verir.',
    );
  return _item(
    v,
    'Kondansatör başlangıçta yüksüzdür. Şarj akımının ilk değerinin yarısına inmesi için kaç ms geçer?',
    tau * math.ln2,
    'ms',
    [tau, tau / math.ln2, tau * 2],
    'i/i₀ = exp(−t/RC) = 1/2 eşitliğinden t = RC ln2 bulunur. kΩ ile µF çarpımı milisaniye verir.',
  );
}

AdvancedItem _bridge(int a, int b, int c, bool second) {
  final r1 = 100 + a, r2 = 100 + b, e = 2 * c;
  final v = _diagram('Köprü · gerilim bölücü kolları', [
    _line(24, 20, 77, 20),
    _line(24, 80, 77, 80),
    _line(27, 20, 27, 80),
    _line(73, 20, 73, 80),
    _box(27, 35, 26, 14, '100 Ω'),
    _box(27, 65, 26, 14, '$r1 Ω'),
    _box(73, 35, 26, 14, '100 Ω'),
    _box(73, 65, 26, 14, '$r2 Ω'),
    _label(50, 10, '+$e V'),
    _label(50, 91, '0 V'),
    _label(14, 50, 'L'),
    _label(87, 50, 'R'),
  ]);
  final vl = e * r1 / (100 + r1), vr = e * r2 / (100 + r2);
  if (second)
    return _item(
      v,
      'Ölçü aleti akım çekmiyor. R düğümü eksi L düğümü olarak tanımlanan çıkış kaç mV olur?',
      1000 * (vr - vl),
      'mV',
      [1000 * (vl - vr), 1000 * (vl + vr) / 2, 1000 * vr],
      'Her orta düğüm alt direncin üzerindeki gerilime eşittir. Vç = E[Ralt,sağ/(100+Ralt,sağ) − Ralt,sol/(100+Ralt,sol)]. Volt değeri 1000 ile çarpılır.',
    );
  return _item(
    v,
    'L ve R arasına ideal voltmetre bağlanıyor. Kaynaktan çekilen toplam akım kaç mA olur?',
    1000 * e * (1 / (100 + r1) + 1 / (100 + r2)),
    'mA',
    [1000 * e / (200 + r1 + r2), 1000 * e / (100 + r1), 1000 * e / (100 + r2)],
    'Voltmetrenin akımı sıfırdır. Her kol kendi seri direnç toplamına sahiptir. Kollardaki E/R akımları toplanıp mA birimine çevrilir.',
  );
}

AdvancedItem _thevenin(int a, int b, int c, bool second) {
  final e = 30 + a, r = b, step = c * 100;
  final v = _chart(
    _lineChart,
    'Port gerilimi (V) – yük akımı (mA)',
    ['0', '$step', '${2 * step}'],
    [e, e - r * step / 1000, e - r * 2 * step / 1000],
    'V',
  );
  if (second)
    return _item(
      v,
      'Porta maksimum güç çeken bir direnç bağlanıyor. Bu dirence aktarılan güç kaç watt olur?',
      e * e / (4 * r),
      'W',
      [e * e / r, e * e / (2 * r), e * e / (8 * r)],
      'Açık devre gerilimi $e V, I–V eğiminin büyüklüğünden Thévenin direnci $r Ω olur. Eşleşmede yük gerilimi E/2 ve güç E²/(4Rth) olur.',
    );
  return _item(
    v,
    'Doğrusal portun Norton eşdeğerindeki kısa devre akımı kaç amperdir?',
    e / r,
    'A',
    [r / e, e / (2 * r), 2 * e / r],
    'Akım amper cinsine çevrilir. Rth = |ΔV/ΔI| = $r Ω ve açık devre gerilimi $e V olduğundan kısa devre akımı E/Rth olur.',
  );
}

AdvancedItem _opamp(int a, int b, int c, bool second) {
  final rin = a, rf = b, mv = 10 * c;
  final v = _diagram('İdeal tersleyen yükselteç · bağlantı özeti', [
    _box(20, 45, 27, 18, '$rin kΩ'),
    _box(57, 45, 23, 24, '− giriş'),
    _line(34, 45, 44, 45),
    _line(69, 45, 93, 45, arrow: true),
    _line(86, 45, 86, 18),
    _line(86, 18, 43, 18),
    _line(43, 18, 43, 45),
    _box(64, 18, 25, 13, '$rf kΩ', 'gold'),
    _label(19, 69, 'Vi = $mv mV'),
    _label(61, 78, '+ giriş: 0 V'),
  ]);
  if (second)
    return _item(
      v,
      'Negatif geri besleme etkindir ve yükselteç doymamıştır. Geri besleme direncinden geçen akımın büyüklüğü kaç µA olur?',
      mv / rin,
      'µA',
      [mv / rf, mv / (rin + rf), mv * rf / rin],
      'Eksi giriş sanal topraktır. İdeal giriş akımı sıfır olduğundan giriş direncindeki Vi/Rin akımı geri besleme direncine geçer. mV/kΩ = µA.',
    );
  return _item(
    v,
    'Yükselteç doğrusal bölgede çalışıyorsa çıkış gerilimi kaç mV olur?',
    -mv * rf / rin,
    'mV',
    [mv * rf / rin, -mv * rin / rf, -mv * (1 + rf / rin)],
    'Eksi giriş 0 V düzeyindedir. Düğüm akım dengesi Vç = −(Rf/Rin)Vi bağıntısını verir.',
  );
}

AdvancedItem _capacitor(int a, int b, int c, bool second) {
  final area = 10 * a, d = b, k = c;
  final v = _diagram('Paralel levhalar · eş kalınlıklı iki katman', [
    _line(10, 28, 90, 28),
    _line(10, 72, 90, 72),
    _box(50, 42, 67, 19, 'Hava · $d mm'),
    _box(50, 60, 67, 17, 'Dielektrik · $d mm', 'gold'),
    _label(49, 86, 'A = $area cm² · εr = $k'),
  ]);
  final capacitance = 8.85 * area * 0.1 / (d * (1 + 1 / k));
  if (second)
    return _item(
      v,
      'Kenar etkileri ihmal ediliyor. Levhalar arasında ${10 * c} V varsa hava katmanındaki gerilim düşümü kaç volt olur?',
      10 * c * k / (k + 1),
      'V',
      [10 * c / (k + 1), 5 * c, 10 * c],
      'Katmanlar seri olduğundan normal elektrik akı yoğunluğu aynıdır. Havadaki alan dielektriktekinden εr kat büyük olur. Kalınlıklar eşit olduğundan gerilimler de εr:1 oranındadır.',
    );
  return _item(
    v,
    'Ortada serbest yük yoktur. ε₀ = 8,85 pF/m alınırsa iki katmanın eşdeğer kapasitesi kaç pF olur?',
    capacitance,
    'pF',
    [2 * capacitance, capacitance / (k + 1), capacitance * k],
    'Alan ve kalınlık SI birimlerine çevrilir. Seri katmanlarda 1/C = d/(ε₀A) + d/(ε₀εrA) olur.',
  );
}

AdvancedItem _inertia(int a, int b, int c, bool second) {
  final m1 = a, m2 = b, radius = 5 * c;
  final v = _diagram('Kütlesiz kol · gösterilen noktadan geçen dik eksen', [
    _line(10, 51, 91, 51),
    _box(16, 51, 17, 16, '$m1 kg'),
    _box(83, 51, 17, 16, '$m2 kg'),
    const DiagramElement(
      shape: 'circle',
      x: 49,
      y: 51,
      width: 7,
      height: 7,
      color: 'pink',
    ),
    _label(48, 75, 'Eksen'),
    _label(31, 33, '$radius cm'),
    _label(68, 33, '${2 * radius} cm'),
  ]);
  final inertia = (a + 4 * b) * radius * radius / 10000;
  if (second)
    return _item(
      v,
      'Rotor $c rad/s açısal hızla dönüyorsa gösterilen eksene göre toplam dönme kinetik enerjisi kaç joule olur?',
      inertia * c * c / 2,
      'J',
      [
        inertia * c * c,
        inertia * c / 2,
        (a + b) * radius * radius * c * c / 20000,
      ],
      'Noktasal kütleler için I = m₁r₁² + m₂r₂² hesaplanır. Yarıçap metre cinsinden kullanılarak K = Iω²/2 bulunur.',
    );
  return _item(
    v,
    'Şemadaki kütleler noktasal kabul ediliyor. Gösterilen eksene göre toplam eylemsizlik momenti kaç kg·m² olur?',
    inertia,
    'kg·m²',
    [
      (a + 2 * b) * radius * radius / 10000,
      (a + b) * radius * radius / 10000,
      inertia / 2,
    ],
    'Her kütle eksene uzaklığının karesiyle çarpılır. Sağ kütle iki kat uzakta olduğundan karesel çarpanı dört kat olur.',
  );
}

AdvancedItem _pv(int a, int b, int c, bool second) {
  final low = 40 + 2 * a, hi = low + 5 * b, v1 = c, v2 = 3 * c;
  final v = _table(
    'İdeal gaz · doğrusal kenarlı çevrim',
    ['Köşe', 'V (L)', 'P (kPa)'],
    [
      ['A', v1, low],
      ['B', v1, hi],
      ['C', v2, hi],
      ['D', v2, low],
    ],
  );
  if (second)
    return _item(
      v,
      'Gaz A→D→C→B→A yoluyla ilk durumuna dönüyor. Gazın aldığı ısı pozitif tanımlanırsa tam çevrimdeki net ısı kaç joule olur?',
      -(hi - low) * (v2 - v1),
      'J',
      [(hi - low) * (v2 - v1), 0, -hi * (v2 - v1)],
      'Ters yönlü çevrimde gazın net işi negatiftir. İç enerji ilk değerine döner. Dolayısıyla net ısı, çevrimin işaretli alanına eşittir. 1 kPa·L = 1 J.',
    );
  return _item(
    v,
    'A→B→C→D→A sırasıyla yürütülen çevrimde gazın yaptığı net iş kaç joule olur?',
    (hi - low) * (v2 - v1),
    'J',
    [hi * (v2 - v1), low * (v2 - v1), -(hi - low) * (v2 - v1)],
    'Düşey hacim sabit adımlarında iş sıfırdır. Yüksek basınçtaki genleşme işi ile düşük basınçtaki sıkıştırma işi toplanınca (Püst−Palt)(Vson−Vilk) kalır.',
  );
}

AdvancedItem _carnot(int a, int b, int c, bool second) {
  final cold = 250 + a, hot = cold + 10 * b, heat = 10 * c;
  final v = _diagram('Tersinir makine · bir çevrim', [
    _box(17, 48, 27, 26, '$hot K', 'gold'),
    _box(51, 48, 23, 26, 'Makine'),
    _box(85, 48, 26, 26, '$cold K'),
    _line(32, 48, 39, 48, arrow: true),
    _line(63, 48, 71, 48, arrow: true),
    _label(26, 21, 'Qₕ = $heat kJ'),
  ]);
  if (second)
    return _item(
      v,
      'Carnot makinesinin bir çevrimde soğuk depoya verdiği ısının büyüklüğü kaç kJ olur?',
      heat * cold / hot,
      'kJ',
      [heat * (1 - cold / hot), heat * hot / cold, heat * (hot - cold) / cold],
      'Tersinir bir çevrimde |Qc|/Qh = Tc/Th ilişkisi mutlak sıcaklıklarla uygulanır.',
    );
  return _item(
    v,
    'Makine iki depo arasında Carnot çevrimi gerçekleştiriyor. Bir çevrimde dışarı verilen net iş kaç kJ olur?',
    heat * (1 - cold / hot),
    'kJ',
    [heat * cold / hot, heat * (hot - cold) / cold, heat],
    'Carnot verimi 1−Tc/Th olur. Sıcak depodan alınan $heat kJ enerji bu verimle çarpılır.',
  );
}

AdvancedItem _wall(int a, int b, int c, bool second) {
  final d1 = a, d2 = b, hot = 30 + 5 * c, cold = 10;
  final v = _diagram('Düz duvar · iki katman seri', [
    _box(32, 49, 33, 43, 'k₁ = 0,5'),
    _box(66, 49, 33, 43, 'k₂ = 1,0', 'gold'),
    _label(31, 80, '$d1 cm'),
    _label(69, 80, '$d2 cm'),
    _label(22, 16, '$hot °C'),
    _label(80, 16, '$cold °C'),
  ]);
  final resistance = d1 / 50 + d2 / 100, flux = (hot - cold) / resistance;
  if (second)
    return _item(
      v,
      'Isıl iletkenlikler W/(m·K) cinsindendir. Kararlı tek boyutlu iletimde temas direnci yoksa katmanlar arasındaki sıcaklık kaç °C olur?',
      hot - flux * d1 / 50,
      '°C',
      [hot - flux * d2 / 100, (hot + cold) / 2, hot],
      'Birim alan başına ısıl dirençler d₁/k₁ ve d₂/k₂ olarak toplanır. Akı ΔT/Rtoplam olur. Arayüz sıcaklığı sıcak yüzeyden ilk katmandaki q″d₁/k₁ düşümü çıkarılarak bulunur.',
    );
  return _item(
    v,
    'İletkenlikler W/(m·K) cinsindendir. Kararlı tek boyutlu iletimde birim alandan geçen ısı akısı kaç W/m² olur?',
    flux,
    'W/m²',
    [
      (hot - cold) / (d1 / 50),
      (hot - cold) / (d2 / 100),
      (hot - cold) * resistance,
    ],
    'Katmanların seri dirençleri kalınlık/iletkenlik ile hesaplanır. q″ = (Tsol−Tsağ)/(d₁/k₁+d₂/k₂) olur ve kalınlıklar metreye çevrilir.',
  );
}

AdvancedItem _pipe(int a, int b, int c, bool second) {
  final area = a + 5, speed = b / 10, ratio = c;
  final v = _diagram('Yatay akış · giriş ve dar kesit', [
    _line(8, 26, 47, 26),
    _line(47, 26, 64, 39),
    _line(64, 39, 91, 39),
    _line(8, 72, 47, 72),
    _line(47, 72, 64, 58),
    _line(64, 58, 91, 58),
    _line(20, 48, 39, 48, arrow: true),
    _label(28, 88, '${area * ratio} cm²'),
    _label(79, 81, '$area cm²'),
    _label(28, 14, '${_n(speed)} m/s'),
  ]);
  final fast = speed * ratio;
  if (second)
    return _item(
      v,
      'Akış kararlı, sıkıştırılamaz ve kayıpsızdır. Suyun yoğunluğu 1000 kg/m³ ise giriş ile dar kesit arasındaki statik basınç düşümü kaç Pa olur?',
      500 * (fast * fast - speed * speed),
      'Pa',
      [
        500 * fast * fast,
        1000 * (fast - speed),
        1000 * (fast * fast - speed * speed),
      ],
      'Süreklilik dar kesitteki hızı $ratio katına çıkarır. Aynı yükseklikte Bernoulli denklemi P₁−P₂ = ρ(v₂²−v₁²)/2 verir.',
    );
  return _item(
    v,
    'Boru suyla doludur ve akış kararlıdır. Girişteki hızın kesit ortalaması olduğu kabul edilirse hacimsel debi kaç L/s olur?',
    area * ratio * speed / 10,
    'L/s',
    [area * speed / 10, area * ratio * speed, area * speed / (10 * ratio)],
    'Q = A₁v₁ hesaplanır. cm² alanı m² birimine dönüştürmek için 10⁻⁴, m³/s değerini L/s yapmak için 1000 çarpanı kullanılır.',
  );
}

AdvancedItem _pump(int a, int b, int c, bool second) {
  final q = a, h = b, eta = 50 + 5 * c;
  final v = _table(
    'Su pompası · kararlı çalışma',
    ['İşletme büyüklüğü', 'Değer'],
    [
      ['Debi (L/s)', q],
      ['Toplam basma yüksekliği (m)', h],
      ['Pompa verimi (%)', eta],
    ],
  );
  final hyd = q * h * 10 / 1000;
  if (second)
    return _item(
      v,
      'ρ = 1000 kg/m³ ve g = 10 m/s² alınız. Şaft giriş gücünün akışkana aktarılmayan kısmı kaç kW olur?',
      hyd * (100 / eta - 1),
      'kW',
      [hyd * 100 / eta, hyd, hyd * (1 - eta / 100)],
      'Hidrolik güç ρgQH, şaft giriş gücü Ph/(η/100) olur. Kayıp ikisinin farkıdır.',
    );
  return _item(
    v,
    'Bu çalışma noktasında gereken şaft gücü kaç kW olur? ρ = 1000 kg/m³ ve g = 10 m/s² alınız.',
    hyd * 100 / eta,
    'kW',
    [hyd, hyd * eta / 100, hyd * (100 / eta - 1)],
    'Önce debi m³/s birimine çevrilir ve hidrolik güç ρgQH hesaplanır. Şaft gücü, hidrolik gücün kesir biçimindeki verime bölümüdür.',
  );
}

AdvancedItem _stress(int a, int b, int c, bool second) {
  final strain = c, sig = 5 * a, area = 10 * b;
  final v = _chart(
    _lineChart,
    'Elastik bölgede gerilme (MPa) – birim uzama (‰)',
    ['0', '$strain', '${2 * strain}'],
    [0, sig, 2 * sig],
    'MPa',
  );
  if (second)
    return _item(
      v,
      'Başlangıç kesiti $area mm² olan numunede grafiğin son noktasındaki çekme kuvveti kaç kN olur?',
      2 * sig * area / 1000,
      'kN',
      [sig * area / 1000, 2 * sig / area, sig * area / 100],
      'Mühendislik gerilmesi başlangıç kesitine göre tanımlanır. MPa = N/mm² olduğundan son gerilme alanla çarpılıp 1000’e bölünür.',
    );
  return _item(
    v,
    'Başlangıç kesiti $area mm² olan numunenin Young modülü kaç GPa olur?',
    sig / strain,
    'GPa',
    [sig * strain, sig / (2 * strain), 1000 * sig / strain],
    'Elastik eğim E = Δσ/Δε olur. Yatay eksen binde birimindedir. MPa değerini gerçek şekil değiştirmeye bölüp GPa’ya çevirince sayısal olarak $sig/$strain elde edilir.',
  );
}

AdvancedItem _torsion(int a, int b, int c, bool second) {
  final torque = 10 * a,
      radius = b + 9,
      j = math.pi * math.pow(radius, 4) / 2,
      length = 100 * c;
  final v = _table(
    'Dolu dairesel mil · saf burulma',
    ['Geometri / yük', 'Değer'],
    [
      ['Yarıçap (mm)', radius],
      ['Etkin uzunluk (mm)', length],
      ['Burulma momenti (N·m)', torque],
    ],
  );
  if (second)
    return _item(
      v,
      'Kesit dairesel ve malzeme elastiktir. Kayma modülü 80 GPa ise iki uç arasındaki burulma açısı kaç mrad olur?',
      torque * 1000 * length * 1000 / (80000 * j),
      'mrad',
      [
        torque * 1000 * length / (80000 * j),
        2 * torque * 1000 * length * 1000 / (80000 * j),
        torque * 1000 * length * 1000 / (160000 * j),
      ],
      'φ = TL/(GJ) ve J = πr⁴/2 kullanılır. T değeri N·mm, G değeri N/mm² alınır. Radyan sonucu mrad için 1000 ile çarpılır.',
    );
  return _item(
    v,
    'Elastik burulmada milin dış yüzeyindeki en büyük kayma gerilmesi kaç MPa olur?',
    torque * 1000 * radius / j,
    'MPa',
    [
      torque * radius / j,
      2 * torque * 1000 * radius / j,
      torque * 1000 * radius / (2 * j),
    ],
    'Dairesel kesitte τ(r) = Tr/J artarak dış yüzeyde en büyük değerini alır. J = πr⁴/2 ve 1 N·m = 1000 N·mm kullanılır.',
  );
}

AdvancedItem _gears(int a, int b, int c, bool second) {
  final A = 10 + a, B = 20 + b, C = 10 + c, D = 2 * C + 3, speed = 120;
  final v = _diagram('Bileşik dişli treni · diş sayıları', [
    _box(14, 45, 21, 22, 'A: $A'),
    _box(38, 45, 21, 22, 'B: $B'),
    _box(62, 45, 21, 22, 'C: $C', 'gold'),
    _box(86, 45, 21, 22, 'D: $D', 'gold'),
    _label(50, 72, 'B ve C aynı milde'),
    _label(25, 20, 'A → B'),
    _label(75, 20, 'C → D'),
  ]);
  final ratio = A * C / (B * D);
  if (second)
    return _item(
      v,
      'Kayıpsız dişli treninde A miline $c N·m tork uygulanıyor. D milindeki çıkış torkunun büyüklüğü kaç N·m olur?',
      c / ratio,
      'N·m',
      [c * ratio, c * B / A, c * D / C],
      'B ve C aynı açısal hızla döner. İki kademenin hız oranı (A/B)(C/D) olur. Kayıpsız güç aktarımında tork bunun tersiyle ölçeklenir.',
    );
  return _item(
    v,
    'A dişlisi $speed dev/dak ile sürülüyor. D dişlisinin dönme hızının büyüklüğü kaç dev/dak olur?',
    speed * ratio,
    'dev/dak',
    [speed / ratio, speed * A / B, speed * C / D],
    'Kavrama noktasındaki çevresel hızlar eşit olduğundan ilk hız oranı A/B, ikinci oran C/D olur. Giriş hızı bu oranların çarpımıyla çarpılır.',
  );
}

AdvancedItem _signal(int a, int b, int c, bool second) {
  final fs = 200 + 10 * a, lo = b, hi = fs ~/ 2 + 5 * c;
  final v = _chart(
    _bar,
    'İki sinüzoidal bileşenin frekansları (Hz)',
    ['K', 'L'],
    [lo, hi],
    'Hz',
  );
  if (second)
    return _item(
      v,
      'Bu sinyali $fs Hz ile örnekleyen sistemde ön süzgeç yoktur. L bileşeni tek taraflı taban bantta kaç Hz olarak görünür?',
      fs - hi,
      'Hz',
      [hi, hi - fs / 2, fs - lo],
      'L, Nyquist frekansının üzerinde ve örnekleme frekansının altındadır. Bu aralıkta katlanan frekans fs−fL olur.',
    );
  return _item(
    v,
    'Mevcut örnekleme hızı $fs Hz. Sinyalin grafikteki en yüksek frekansına karşılık gelen Nyquist örnekleme hızı 2fmax kaç Hz olur?',
    2 * hi,
    'Hz',
    [hi, 2 * lo, fs / 2],
    'Spektrumdaki yüksek frekans L bileşenindedir. Nyquist örnekleme hızı en yüksek bileşenin iki katıdır.',
  );
}

AdvancedItem _calibrate(int a, int b, int c, bool second) {
  final offset = a, step = b, span = 10 * c;
  final v = _chart(
    _lineChart,
    'Sensör çıkışı (mV) – standart basınç (kPa)',
    ['0', '$span', '${2 * span}'],
    [offset, offset + step, offset + 2 * step],
    'mV',
  );
  if (second)
    return _item(
      v,
      'Doğrusal sensörün çıkışında ${_n(offset + 1.5 * step)} mV okunuyor. Kalibrasyon doğrusuna göre basınç kaç kPa olur?',
      1.5 * span,
      'kPa',
      [(offset + 1.5 * step) * span / step, span / 1.5, span * 2],
      'Sıfır basınçta $offset mV ofset vardır. Okumadan bu ofset çıkarılıp $step/$span mV/kPa duyarlılığa bölünür.',
    );
  return _item(
    v,
    'Sensörün basınçtan gerilime statik duyarlılığı kaç mV/kPa olur?',
    step / span,
    'mV/kPa',
    [(offset + step) / span, span / step, 2 * step / span],
    'Statik duyarlılık, çıkış değişiminin giriş değişimine oranıdır. Bir ölçüm aralığında çıkış $step mV, basınç $span kPa artar.',
  );
}

AdvancedItem _batch(int a, int b, int c, bool second) {
  final last = a, half = b, t0 = c;
  final v = _chart(
    _lineChart,
    'Reaktörde A derişimi (mmol/L) – zaman (dk)',
    ['$t0', '${t0 + half}', '${t0 + 2 * half}'],
    [4 * last, 2 * last, last],
    'mmol/L',
  );
  if (second)
    return _item(
      v,
      'Birinci dereceden izotermal tüketim sürüyor. Ölçülen son noktadan hemen sonraki anlık tüketim hızının büyüklüğü kaç mmol/(L·dk) olur?',
      last * math.ln2 / half,
      'mmol/(L·dk)',
      [last / half, 2 * last * math.ln2 / half, last * math.ln2],
      'Bir yarı ömür, derişimin ardışık iki noktada yarıya indiği $half dakikadır. k = ln2/t½ ve son noktadaki hız k[A]son olur.',
    );
  return _item(
    v,
    'Çizgi ölçüm noktalarını birleştiriyor. Birinci derece hız yasasına göre hız sabiti kaç dk⁻¹ olur?',
    math.ln2 / half,
    'dk⁻¹',
    [1 / half, 2 * math.ln2 / half, half / math.ln2],
    'Ardışık ölçümlerde derişimin yarıya inmesi $half dakika sürüyor. Birinci derece tüketimin tümleşik yasası k = ln(Cilk/Cson)/Δt verir.',
  );
}

AdvancedItem _equilibrium(int a, int b, int c, bool second) {
  final vol = c, na = a, nb = b, np = a + b;
  final v = _table(
    'A(g) + B(g) ⇌ AB(g) · denge örneği',
    ['Tür', 'Dengedeki miktar (mmol)'],
    [
      ['A', na],
      ['B', nb],
      ['AB', np],
    ],
  );
  final k = 1000 * np * vol / (na * nb);
  if (second)
    return _item(
      v,
      'Dengedeki $vol L kap aynı sıcaklıkta bir anda ${2 * vol} L hacme genişliyor. Tepkime ilerlemeden hemen sonraki Qc kaç L/mol olur? Derişimleri mol/L alın.',
      2 * k,
      'L/mol',
      [k, k / 2, 4 * k],
      'Hacim iki katına çıkınca tüm derişimler yarıya iner. Qc = [AB]/([A][B]) bu nedenle eski değerinin iki katıdır. Eski değer nAB V/(nA nB) ile mol biriminde hesaplanır.',
    );
  return _item(
    v,
    'Kabın hacmi $vol L ve derişimler mol/L cinsindendir. [AB]/([A][B]) olarak tanımlanan derişim oranı kaç L/mol olur?',
    k,
    'L/mol',
    [k / vol, k / 1000, 1 / k],
    'Her denge miktarı mol birimine dönüştürülüp kap hacmine bölünür. Oran nAB V/(nA nB) biçimine sadeleşir.',
  );
}

AdvancedItem _beer(int a, int b, int c, bool second) {
  final step = b, initial = a, slope = c;
  final v = _chart(
    _lineChart,
    'Absorbans (mAU) – son çözeltide eklenen standart (µmol/L)',
    ['0', '$step', '${2 * step}'],
    [slope * initial, slope * (initial + step), slope * (initial + 2 * step)],
    'mAU',
  );
  if (second)
    return _item(
      v,
      'Her balonda aynı $c mL numune toplam ${5 * c} mL’ye tamamlanmıştır. Kör sinyali çıkarılmıştır. Seyreltilmemiş numunede analit derişimi kaç µmol/L olur?',
      5 * initial,
      'µmol/L',
      [initial, initial / 5, initial * slope],
      'Standart ekleme doğrusunun y kesişimi/eğim oranı, hazırlanmış balondaki numune katkısını verir. İlk derişim için toplam hacmin numune hacmine oranı 5 ile çarpılır.',
    );
  return _item(
    v,
    'Her balonda aynı miktarda numune vardır ve son hacimler eşittir. Kör düzeltmesi yapılmış kalibrasyon doğrusunun x eksenini kestiği nokta kaç µmol/L olur?',
    -initial,
    'µmol/L',
    [initial, -initial * slope, -step],
    'Sinyal sıfıra götürülürse x = −kesişim/eğim olur. Kesişim ${initial * slope} mAU, eğim $slope mAU/(µmol/L) olduğundan değer negatiftir.',
  );
}

AdvancedItem _extract(int a, int b, int c, bool second) {
  final water = 10 * a, org = 10 * b, k = c;
  final v = _diagram('Karışmayan iki çözücü · dengede fazlar', [
    _box(50, 37, 54, 24, 'Organik $org mL', 'gold'),
    _box(50, 62, 54, 24, 'Su $water mL'),
    _label(50, 15, 'K = Corg / Csu = $k'),
  ]);
  final f = water / (water + k * org);
  if (second)
    return _item(
      v,
      'Analit başlangıçta sulu fazdadır. Şekildeki organik hacim her seferinde taze olarak iki kez art arda kullanılıp ayrılıyor. Sulu fazda kalan analit başlangıcın yüzde kaçıdır?',
      100 * f * f,
      '%',
      [100 * f, 100 * (1 - f * f), 100 * f / 2],
      'Tek ekstraksiyondan sonra suda kalan kesir Vsu/(Vsu+K Vorg) olur. İki bağımsız denge adımında aynı kesir iki kez çarpılır.',
    );
  return _item(
    v,
    'Analit başlangıçta yalnız sulu fazdadır. Bir dengeleme ve faz ayırma sonunda organik faza geçen analit yüzdesi kaçtır?',
    100 * (1 - f),
    '%',
    [100 * f, 100 * org / (org + water), 100 * (1 - f * f)],
    'Denge derişimleri K ile ilişkilidir. Organik fazdaki miktarın toplama oranı K Vorg/(Vsu+K Vorg) olur.',
  );
}

AdvancedItem _chrom(int a, int b, int c, bool second) {
  final dead = c, t1 = dead + a, t2 = t1 + b, w1 = c, w2 = c + 1;
  final v = _table(
    'Kromatogram · zamanlar saniye',
    ['Ölçüm', 'Zaman', 'Taban genişliği'],
    [
      ['Tutulmayan izleyici', dead, '—'],
      ['Pik 1', t1, w1],
      ['Pik 2', t2, w2],
    ],
  );
  if (second)
    return _item(
      v,
      'Alıkonma zamanları ölü zamana göre düzeltiliyor. İkinci bileşenin birinciye göre seçicilik katsayısı α kaçtır?',
      (t2 - dead) / (t1 - dead),
      '',
      [t2 / t1, (t1 - dead) / (t2 - dead), (t2 - t1) / dead],
      'Kapasite faktörü k′ = (tR−t₀)/t₀ olur. α = k′₂/k′₁ oranında ortak t₀ paydaları sadeleşir.',
    );
  return _item(
    v,
    'Taban genişliklerine dayalı çözünürlük Rs = 2(t₂−t₁)/(w₁+w₂) olarak tanımlanıyor. İki pikin çözünürlüğü kaçtır?',
    2 * (t2 - t1) / (w1 + w2),
    '',
    [(t2 - t1) / (w1 + w2), 2 * (t2 + t1) / (w1 + w2), (w1 + w2) / (t2 - t1)],
    'Pik merkezleri arasındaki fark $b s, iki taban genişliğinin toplamı ${w1 + w2} s olur. Tanımdaki iki çarpanı uygulanır.',
  );
}

AdvancedItem _osmotic(int a, int b, int c, bool second) {
  final concentration = a, t = 270 + b, reference = c;
  final v = _table(
    'İdeal seyreltik çözelti · geçirimsiz çözünen',
    ['Özellik', 'Değer'],
    [
      ['Derişim (mmol/L)', concentration],
      ['Sıcaklık (K)', t],
      ['van’t Hoff faktörü', reference],
    ],
  );
  final pressure = reference * concentration * 8.314 * t / 1000;
  if (second)
    return _item(
      v,
      'Sıcaklık korunurken saf su eklenerek hacim iki katına çıkarılıyor. Faktör değişmiyorsa son ozmotik basınç kaç kPa olur? R = 8,314 J/(mol·K).',
      pressure / 2,
      'kPa',
      [pressure, 2 * pressure, pressure / (2 * reference)],
      'Yeni derişim ilk derişimin yarısıdır. π = iCRT bağıntısında 1 mmol/L = 1 mol/m³ ve 1000 Pa = 1 kPa kullanılır.',
    );
  return _item(
    v,
    'Çözelti saf çözücüden yarı geçirgen zarla ayrılıyor. Ozmotik basınç kaç kPa olur? R = 8,314 J/(mol·K).',
    pressure,
    'kPa',
    [pressure / reference, pressure * 1000, pressure / t],
    'İdeal seyreltik çözeltide π = iCRT olur. Sayısal olarak mmol/L ile mol/m³ aynıdır. SI sonucu paskaldan kilopaskala çevrilir.',
  );
}

AdvancedItem _flowmix(int a, int b, int c, bool second) {
  final qa = a, qb = b, ca = 2 * c, cb = c;
  final v = _diagram('Tam karışımlı tank · kararlı sürekli akış', [
    _box(62, 51, 35, 38, 'Tank'),
    _line(10, 34, 43, 43, arrow: true),
    _line(10, 70, 43, 59, arrow: true),
    _line(80, 51, 95, 51, arrow: true),
    _label(22, 17, '$qa L/dk · $ca g/L'),
    _label(22, 87, '$qb L/dk · $cb g/L'),
  ]);
  final mass = qa * ca + qb * cb;
  if (second)
    return _item(
      v,
      'Tankta tepkime yoktur ve çıkışlar aynı homojen karışımdandır. Çıkış debisinin %20’si yan kola ayrılırsa yan koldan dakikada kaç gram çözünen geçer?',
      mass / 5,
      'g/dk',
      [mass, mass / 5 / (qa + qb), mass * 0.8],
      'Kararlı hâlde giriş ve çıkış çözünen debileri eşittir. Giriş debisi Q₁C₁+Q₂C₂ olur. Aynı derişimdeki yan kol bunun %20 kadarını taşır.',
    );
  return _item(
    v,
    'Hacimler toplanabilir, çözünen tepkimeye girmiyor ve tankta birikme yoktur. Çıkıştaki çözünen derişimi kaç g/L olur?',
    mass / (qa + qb),
    'g/L',
    [(ca + cb) / 2, (qa * cb + qb * ca) / (qa + qb), mass / qa],
    'Çözünen bilançosunda QçCç = Q₁C₁+Q₂C₂ olur. Çıkış debisi Q₁+Q₂ olduğundan sonuç debi ağırlıklı ortalamadır.',
  );
}

AdvancedItem _uncertainty(int a, int b, int c, bool second) {
  final x = 50 + a, y = 30 + b, ux = c / 10, uy = (c + 1) / 10;
  final v = _table(
    'Bağımsız uzunluk ölçümleri',
    ['Ölçü', 'Tahmin (mm)', 'Standart u (mm)'],
    [
      ['x', x, ux],
      ['y', y, uy],
    ],
  );
  if (second)
    return _item(
      v,
      'İki uzunluk uç uca ekleniyor. Kovaryans sıfırsa toplam uzunluğun birleşik standart belirsizliği kaç mm olur?',
      math.sqrt(ux * ux + uy * uy),
      'mm',
      [ux + uy, (ux + uy) / 2, (uy - ux).abs()],
      'Toplamın her duyarlılık katsayısı 1’dir. Bağımsız standart belirsizliklerin kareleri toplanıp karekök alınır.',
    );
  final u = math.sqrt(y * y * ux * ux + x * x * uy * uy);
  return _item(
    v,
    'Bu ölçülerle hesaplanan dikdörtgen alanının birinci dereceden yayılım yaklaşımıyla standart belirsizliği kaç mm² olur?',
    u,
    'mm²',
    [y * ux + x * uy, ux * uy, u / 2],
    'Alan A = xy için duyarlılıklar ∂A/∂x = y ve ∂A/∂y = x olur. Bağımsız girdilerde uA = √[(y ux)² + (x uy)²] kullanılır.',
  );
}

AdvancedItem _quantum(int a, int b, int c, bool second) {
  final e1 = a / 10, e2 = e1 + b / 10, e3 = e2 + c / 10;
  final es = <DiagramElement>[];
  for (final entry in [(74.0, e1, 'K'), (50.0, e2, 'L'), (24.0, e3, 'M')]) {
    es.add(_line(12, entry.$1, 68, entry.$1));
    es.add(_label(81, entry.$1, '${entry.$3}: ${_n(entry.$2)} eV'));
  }
  final v = _diagram('Yalıtılmış sistem · üç enerji özdurumu', es);
  if (second)
    return _item(
      v,
      'M→L→K ardışık geçişlerinde iki foton yayılıyor. İlk fotonun dalga boyunun ikinci fotonun dalga boyuna oranı kaçtır?',
      b / c,
      '',
      [c / b, (b + c) / c, (b + c) / b],
      'Her fotonun enerjisi ilgili düzey farkıdır. λ = hc/ΔE olduğundan λML/λLK = (EL−EK)/(EM−EL) olur.',
    );
  return _item(
    v,
    'M düzeyinden doğrudan K düzeyine inişte yayılan fotonun dalga boyu kaç nm olur? hc = 1240 eV·nm alınız.',
    12400 / (b + c),
    'nm',
    [12400 / b, 12400 / c, 1240 / e3],
    'Geçiş enerjisi EM−EK = ${_n((b + c) / 10)} eV olur. Dalga boyu hc değerinin bu enerjiye bölümüdür.',
  );
}

AdvancedItem _instrumentReview(int a, int b, int c, bool _) {
  final target = 5 * a, tolerance = b / 10, base = 75 + 5 * c;
  final names = ['K', 'L', 'M', 'N'];
  final shift = (a + 2 * b + c) % 4;
  final role = [for (var i = 0; i < 4; i++) names[(i + shift) % 4]];
  final rows = <List<Object>>[
    [role[0], target + 2 * c, tolerance / 2, base],
    [role[1], target + c, tolerance / 3, base + 5 * b],
    [role[2], target - c, tolerance / 4, base - 7],
    [role[3], target + 3 * c, tolerance + 0.2, base - 10],
  ]..sort((p, q) => p[0].toString().compareTo(q[0].toString()));
  final v = _table('Ölçü aleti teklifleri · garantili sınırlar', [
    'Model',
    'Üst sınır (V)',
    'Hata ±(V)',
    'Bedel (₺)',
  ], rows);
  final prompt =
      'Sıfırdan $target V değerine kadar ölçüm yapılacak. İzin verilen mutlak hata en çok ${_n(tolerance)} V. Bu iki şartı sağlayan en ucuz model hangisidir?';
  return AdvancedItem(
    prompt,
    role[0],
    [role[1], role[2], role[3]],
    '${role[2]} gerekli üst gerilime erişemez. ${role[3]} hata sınırını aşar. Kalan iki modelden ${role[0]} $base ₺ bedelle daha ucuzdur.',
    visual: v,
  );
}

AdvancedItem _designLab(int a, int b, int c, bool _) {
  final low = a, high = a + 20 + b, limit = c / 10, time = 10 * (c + 3);
  final v = _table(
    'Termistör kalibrasyonu · kullanılabilir düzenek',
    ['Laboratuvar bilgisi', 'Sınır / kaynak'],
    [
      ['Ayarlanabilen banyo', '$low–$high °C'],
      ['İzin verilen sapma', '±${_n(limit)} °C'],
      ['Oturma süresi', '$c dk / yeni sıcaklık'],
      ['Toplam banyo süresi', '$time dk'],
      ['Başvuru cihazı', 'Kalibreli referans termometre'],
    ],
  );
  final t = low + 10;
  final mode = (a + 2 * b + c) % 4;
  final magnitude = mode.isEven ? limit / 2 : limit + (1 + b % 3) / 10;
  final error = mode < 2 ? magnitude : -magnitude;
  final read = t + error;
  final decisions = [
    'Sensör yüksek okumuştur; mutlak hata izin verilen sınırdadır.',
    'Sensör yüksek okumuştur; mutlak hata izin verilen sınırı aşmıştır.',
    'Sensör düşük okumuştur; mutlak hata izin verilen sınırdadır.',
    'Sensör düşük okumuştur; mutlak hata izin verilen sınırı aşmıştır.',
  ];
  return AdvancedItem(
    'Kalibrasyon sonrasında referans $t °C gösterirken sensör ${_n(read)} °C göstermiştir. Bu tek doğrulama noktası için sapmanın yönünü ve ölçümün kabul sınırına uygunluğunu belirleyin.',
    decisions[mode],
    [
      for (var i = 0; i < 4; i++)
        if (i != mode) decisions[i],
    ],
    'Okuma eksi referans ${_n(error)} °C olur. Kabul kararı için bunun mutlak değeri ${_n(magnitude)} °C, tabloda verilen ${_n(limit)} °C sınırıyla karşılaştırılır.',
    visual: v,
  );
}

CreationTask _thermalDesign(AdvancedItem item, int _) {
  final rows = item.visual!.rows;
  return CreationTask(
    '${rows[0][1]} aralığında çalışacak termistör için kendi kalibrasyon ve bağımsız doğrulama deneyinizi tasarlayın. Referans noktalarınızı, tekrar sayılarınızı, ölçüm sırasını ve süre hesabınızı yazın. Belirtilen sapma sınırına göre bir kabul kuralı ve sıcaklık artışı ile azalışı farklı sonuç verirse izleyeceğiniz yolu gerekçelendirin.',
    [
      'Aralığı temsil eden kalibrasyon sıcaklıkları ile uyuma dahil edilmeyen bir doğrulama noktası belirler.',
      '${rows[2][1]} bekleme gereğini, referansla eşzamanlı ölçümleri ve tekrarları ${rows[3][1]} zaman bütçesi içinde planlar.',
      'Sapmayı referansa göre tanımlar, ${rows[1][1]} sınırını uygular ve ısınma/soğuma yönünde gözlenen farkı değerlendiren bir kontrol önerir.',
    ],
  );
}
