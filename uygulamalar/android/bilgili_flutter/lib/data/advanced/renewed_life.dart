// Veriler, sorular için oluşturulan öğretim senaryolarına aittir.
import 'dart:math' as math;
import 'common.dart';

typedef _Study = AdvancedItem Function(int a, int b, int c);
const _hs = StudyLevel.lise, _u = StudyLevel.universite;
const _tab = VisualKind.table,
    _bar = VisualKind.barChart,
    _line = VisualKind.lineChart;
const _use = BloomLevel.uygulama,
    _analyse = BloomLevel.analiz,
    _judge = BloomLevel.degerlendirme,
    _understand = BloomLevel.anlama;
AdvancedFamily _case(
  String key,
  String name,
  StudyLevel level,
  VisualKind visualKind,
  BloomLevel bloom,
  _Study build, {
  bool numeric = true,
  ActivityKind? activityKind,
  Topic topic = Topic.nature,
}) {
  return AdvancedFamily(
    key: 'renew_life_$key',
    title: name,
    level: level,
    topic: switch (key) {
      'segregation' ||
      'survival' ||
      'indicators' ||
      'interval' ||
      'stratify' => Topic.statistics,
      'block' || 'pseudo' || 'effects' => Topic.research,
      'hardy' ||
      'fitness' ||
      'drift' ||
      'stage' ||
      'variance' ||
      'enzyme' ||
      'growth' ||
      'diffusion' ||
      'lifetable' => Topic.biology,
      _ => topic == Topic.science ? Topic.biology : topic,
    },
    difficulty: level == _u ? Difficulty.hard : Difficulty.medium,
    exam: level == _hs && topic == Topic.science ? ExamKind.ayt : null,
    lesson: 'Biyoloji',
    count: 2500,
    visualKind: visualKind,
    bloom: bloom,
    shortAnswer: numeric,
    activityKind: activityKind,
    build: (i) => build(2 + i % 25, 3 + i ~/ 25 % 20, 2 + i ~/ 500 % 5),
  );
}

String _s(num x) => x
    .toStringAsFixed(3)
    .replaceFirst(RegExp(r'0+$'), '')
    .replaceFirst(RegExp(r'\.$'), '')
    .replaceAll('.', ',');
QuestionVisual _v(String title, List<String> header, List<List<Object>> data) =>
    QuestionVisual(
      kind: _tab,
      title: title,
      summary: 'Öğretim senaryosu',
      columns: header,
      rows: data
          .map(
            (row) => row.map((x) => x is num ? _s(x) : x.toString()).toList(),
          )
          .toList(),
    );
QuestionVisual _g(
  VisualKind kind,
  String title,
  List<String> labels,
  List<num> data,
) => QuestionVisual(
  kind: kind,
  title: title,
  summary: 'Öğretim senaryosu',
  labels: labels,
  values: data.map((x) => x.toDouble()).toList(),
);
AdvancedItem _quant(
  QuestionVisual v,
  String prompt,
  num answer,
  String unit,
  List<num> plausible,
  String why,
) {
  String label(num n) => unit == '%' ? '%${_s(n)}' : '${_s(n)} $unit'.trim();
  final right = label(answer), wrong = <String>{};
  for (final n in [
    ...plausible,
    answer * 2,
    answer / 2,
    answer + 1,
    answer + 2,
    answer + 3,
  ]) {
    if (!n.isFinite || (unit == '%' && (n > 100 || n < 0))) continue;
    final s = label(n);
    if (s != right) wrong.add(s);
    if (wrong.length == 3) break;
  }
  final round = (answer * 1000 - (answer * 1000).round()).abs() > 0.000001;
  return AdvancedItem(
    round ? '$prompt Sonucu virgülden sonra üç basamağa yuvarlayınız.' : prompt,
    right,
    wrong.toList(),
    '$why Sonuç $right.',
    visual: v,
  );
}

AdvancedItem _choice(
  QuestionVisual v,
  String p,
  String a,
  List<String> wrong,
  String why, {
  QuestionActivity? activity,
}) => AdvancedItem(p, a, wrong, why, visual: v, activity: activity);

final renewedLifeFamilies = <AdvancedFamily>[
  _case(
    'allele',
    'Diploit örnekte alel sayımı',
    _hs,
    _bar,
    _use,
    _allele,
    topic: Topic.science,
  ),
  _case('hardy', 'Hardy–Weinberg modelinden beklenti', _u, _tab, _use, _hardy),
  _case(
    'fitness',
    'Bitkilerde göreli üreme başarısı',
    _u,
    _tab,
    _analyse,
    _fitness,
    numeric: false,
  ),
  _case(
    'drift',
    'Örnekleme ve alel frekansı',
    _u,
    _tab,
    _understand,
    _drift,
    numeric: false,
  ),
  _case('segregation', 'Mendel oranına uyum', _u, _bar, _use, _segregation),
  _case(
    'linkage',
    'Klasik kalıtımda rekombinasyon',
    _hs,
    _bar,
    _analyse,
    _linkage,
    topic: Topic.science,
  ),
  _case(
    'mendel',
    'Bitki çaprazında baskın fenotip',
    _hs,
    _tab,
    _use,
    _mendel,
    topic: Topic.science,
  ),
  _case('stage', 'Yaş yapısında geçiş hesabı', _u, _tab, _analyse, _stage),
  _case('lambda', 'Ayrık zamanlı nüfus modeli', _hs, _line, _use, _lambda),
  _case('logistic', 'Yoğunluğa bağlı net büyüme', _u, _tab, _use, _logistic),
  _case('patch', 'Habitat yamalarında yerel yok oluş', _u, _tab, _use, _patch),
  _case('lifetable', 'Yaşa bağlı net üreme', _u, _tab, _analyse, _lifetable),
  _case('survival', 'Sansürlü sağkalım gözlemi', _u, _tab, _analyse, _survival),
  _case(
    'indicators',
    'Doğa gözleminde sınıflama başarısı',
    _u,
    _tab,
    _analyse,
    _indicators,
  ),
  _case(
    'detect',
    'Tekrarlı gözlem ve tespit olasılığı',
    _u,
    _tab,
    _use,
    _detect,
  ),
  _case('simpson', 'Topluluk yoğunlaşma indeksi', _u, _bar, _use, _simpson),
  _case(
    'jaccard',
    'Tür listelerinde beta çeşitlilik',
    _u,
    _tab,
    _use,
    _jaccard,
  ),
  _case(
    'evenness',
    'Eşitlik ve tür zenginliği',
    _hs,
    _tab,
    _understand,
    _evenness,
    numeric: false,
  ),
  _case(
    'accumulation',
    'Birikimli tür eğrisinin sınırları',
    _hs,
    _line,
    _analyse,
    _accumulation,
    numeric: false,
  ),
  _case('diffusion', 'Yaprakta gaz difüzyonu', _u, _tab, _use, _diffusion),
  _case(
    'waterpot',
    'Bitkide su potansiyeli dengesi',
    _hs,
    _tab,
    _analyse,
    _waterpot,
    numeric: false,
    topic: Topic.science,
  ),
  _case(
    'rq',
    'Çimlenen tohumda solunum katsayısı',
    _hs,
    _bar,
    _use,
    _rq,
    topic: Topic.science,
  ),
  _case(
    'light',
    'Fotosentezin ışık dengeleme noktası',
    _hs,
    _line,
    _analyse,
    _light,
    topic: Topic.science,
  ),
  _case(
    'oxygen',
    'Göl katmanlarında oksijen bütçesi',
    _u,
    _tab,
    _analyse,
    _oxygen,
  ),
  _case(
    'stratify',
    'Tabakalı örneklemede alan ağırlığı',
    _u,
    _tab,
    _analyse,
    _stratify,
  ),
  _case('isomix', 'Besin kaynaklarının izotop imzası', _u, _tab, _use, _isomix),
  _case(
    'enzyme',
    'Besin enziminde doygunluk modeli',
    _u,
    _tab,
    _analyse,
    _enzyme,
  ),
  _case('growth', 'Bitkide bağıl büyüme hızı', _u, _line, _use, _growth),
  _case(
    'variance',
    'Ortam ve kalıtsal varyans',
    _u,
    _tab,
    _understand,
    _variance,
    numeric: false,
  ),
  _case(
    'block',
    'Bloklu arazi denemesinin yorumu',
    _u,
    _tab,
    _judge,
    _block,
    numeric: false,
  ),
  _case(
    'interval',
    'Güven aralığından bilimsel çıkarım',
    _u,
    _tab,
    _judge,
    _interval,
    numeric: false,
  ),
  _case(
    'pseudo',
    'Deney birimi ve yalancı tekrar',
    _hs,
    _tab,
    _judge,
    _pseudo,
    numeric: false,
  ),
  _case(
    'rank',
    'Yaşam evrelerinde geçiş başarısı',
    _hs,
    _tab,
    _analyse,
    _rank,
    numeric: false,
    activityKind: ActivityKind.ordering,
  ),
  _case(
    'effects',
    'Kontrollü deneyde etkileri eşleştirme',
    _u,
    _tab,
    _analyse,
    _effects,
    numeric: false,
    activityKind: ActivityKind.matching,
  ),
  _case(
    'niches',
    'Mikrohabitat ile gösterge tür eşleştirme',
    _hs,
    _tab,
    _analyse,
    _niches,
    numeric: false,
    activityKind: ActivityKind.matching,
  ),
  _case(
    'sediment',
    'Paleoekolojik olay sırası',
    _hs,
    _tab,
    _understand,
    _sediment,
    numeric: false,
    activityKind: ActivityKind.ordering,
  ),
  ..._conceptFamilies(),
];

AdvancedItem _allele(int a, int b, int c) {
  final z = 4 * c, tot = a + b + z;
  final v = _g(
    _bar,
    'Ada bitkilerinin genotip sayımı (birey)',
    ['AA', 'Aa', 'aa'],
    [a, b, z],
  );
  return _quant(
    v,
    'Her bitki diploittir. Örneklenen gen kopyaları içinde A alelinin yüzdesi kaçtır?',
    100 * (2 * a + b) / (2 * tot),
    '%',
    [100 * a / tot, 100 * (a + b) / tot, 100 * (2 * z + b) / (2 * tot)],
    'AA bitkilerinin her biri iki, Aa bitkilerinin her biri bir A kopyası taşır. Toplam ${2 * tot} alel kopyası içinde ${2 * a + b} A vardır.',
  );
}

AdvancedItem _hardy(int a, int b, int c) {
  final percent = a + 5, n = 100 * (b + c * 20);
  final v = _v(
    'İki alelli lokus · model girdileri',
    ['Büyüklük', 'Değer'],
    [
      ['A aleli (%)', percent],
      ['Diploit bitki sayısı', n],
    ],
  );
  final p = percent / 100;
  return _quant(
    v,
    'Hardy–Weinberg varsayımları altında heterozigot oranı için beklenen değer kullanılıyor. Bu grupta beklenen heterozigot sayısı kaçtır?',
    n * 2 * p * (1 - p),
    'birey',
    [n * p * p, n * (1 - p) * (1 - p), n * p * (1 - p)],
    'Rastgele eşleşen iki alelli bir lokusta heterozigot olasılığı 2pq olur. q = 1−p ve beklenti N × 2pq ile hesaplanır. Beklenen değer kesirli olabilir.',
  );
}

AdvancedItem _fitness(int a, int b, int c) {
  final names = ['K', 'L', 'M', 'N'], rot = (a + b + c) % 4;
  final initial = [a + 12, b + 16, a + b, 6 * c];
  final rates = [c + 4, c + 2, c + 1, c + 3];
  final rows = [
    for (var i = 0; i < 4; i++)
      <Object>[names[(i + rot) % 4], initial[i], initial[i] * rates[i]],
  ]..sort((x, y) => x[0].toString().compareTo(y[0].toString()));
  final v = _v('Ortak bahçe · aynı kuşak izleniyor', [
    'Soy',
    'Üreyen bitki',
    'Üreme çağına ulaşan yavru',
  ], rows);
  return _choice(
    v,
    'Başlangıçtaki üreyen bitki başına üreme çağına ulaşan yavru sayısı ölçüt alınırsa bu koşullarda hangi soy en yüksek başarıyı göstermiştir?',
    names[rot],
    [for (var i = 1; i < 4; i++) names[(i + rot) % 4]],
    'Toplam yavru sayısı tek başına başarı ölçüsü değildir. Her soy kendi başlangıç sayısına bölünür. En yüksek oran ${rates.first} yavru/bitki ile ${names[rot]} soyundadır.',
  );
}

AdvancedItem _drift(int a, int b, int c) {
  final x = 30 + a, y = 20 + b, shift = c * (a.isEven ? 1 : -1);
  final v = _v(
    'Rastgele çekilen kurucu örnek · alel kopyaları',
    ['Örnek', 'A', 'a'],
    [
      ['Kaynak', x * 10, y * 10],
      ['Kurucular', x + shift, y - shift],
    ],
  );
  final up = shift > 0 ? 'artmıştır' : 'azalmıştır';
  return _choice(
    v,
    'Kurucular kaynaktan rastgele seçilmiştir. Tablonun tek başına desteklediği ifade hangisidir?',
    'Kurucu örnekte A frekansı $up; rastgele örnekleme bu farkı oluşturabilir.',
    [
      'A alelinin üstün uyum sağladığı kanıtlanmıştır.',
      'Alel sayısındaki her değişim yeni bir mutasyon gerektirir.',
      'Kuruculardaki A frekansının kaynakla eşit olması zorunludur.',
    ],
    'Kaynak frekansı $x/${x + y}, kuruculardaki frekans ${x + shift}/${x + y} olur. Fark, kaynak popülasyondan sınırlı sayıda birey seçilmesiyle ortaya çıkabilir.',
  );
}

AdvancedItem _segregation(int a, int b, int c) {
  final k = 20 + a + 25 * (c - 2), d = b;
  final v = _g(
    _bar,
    'Aa × Aa · gözlenen bitki fenotipleri',
    ['Baskın', 'Çekinik'],
    [3 * k + d, k - d],
  );
  return _quant(
    v,
    'Tam baskınlık ve 3:1 beklenen oran için Pearson χ² = Σ[(G−B)²/B] istatistiği kaçtır? Süreklilik düzeltmesi kullanmayınız.',
    d * d / (3 * k) + d * d / k,
    '',
    [d * d / (4 * k), d * d / k, 2 * d * d / (4 * k)],
    'Toplam ${4 * k} bitki için beklenen sayılar ${3 * k} ve $k olur. Her sınıfta farkın mutlak değeri $d olduğundan χ² = $d²/${3 * k} + $d²/$k hesaplanır.',
  );
}

AdvancedItem _linkage(int a, int b, int c) {
  final p1 = 70 + a, p2 = 60 + b, r1 = c + 2, r2 = b + 3;
  final v = _g(
    _bar,
    'Klasik bitki test çaprazı · yavru sayıları',
    ['AB', 'ab', 'Ab', 'aB'],
    [p1, p2, r1, r2],
  );
  return _quant(
    v,
    'Çift heterozigot bitkide ebeveyn haplotipleri AB ve ab olarak bilinmektedir. Gözlenen rekombinant yavruların yüzdesi kaçtır?',
    100 * (r1 + r2) / (p1 + p2 + r1 + r2),
    '%',
    [
      100 * (p1 + p2) / (p1 + p2 + r1 + r2),
      100 * r1 / (r1 + r2),
      100 * (r1 + r2) / (p1 + p2),
    ],
    'Ab ve aB, ebeveyndeki iki haplotipten farklı birleşimlerdir. Bu iki sınıfın toplamı ${r1 + r2}, tüm yavru sayısı ${p1 + p2 + r1 + r2} olur.',
  );
}

AdvancedItem _mendel(int a, int b, int c) {
  final n1 = 4 * a, n2 = 4 * b, n3 = 4 * c;
  final v = _v(
    'Tohum rengi · yavru grupları',
    ['Ebeveynler', 'İzlenen yavru'],
    [
      ['Aa × Aa', n1],
      ['Aa × aa', n2],
      ['AA × aa', n3],
    ],
  );
  return _quant(
    v,
    'A aleli tam baskındır. Üç grubun toplamında baskın fenotipli yavru sayısının beklenen değeri kaçtır?',
    3 * a + 2 * b + 4 * c,
    'yavru',
    [a + 2 * b, 3 * a + 2 * b, 3 * (a + b + c)],
    'Baskın fenotip olasılıkları sırasıyla 3/4, 1/2 ve 1 olur. Her grubun yavru sayısı kendi olasılığıyla çarpılıp toplanır.',
  );
}

AdvancedItem _stage(int a, int b, int c) {
  final juvenile = 20 * a, adult = 20 * b, survival = (c + 2) / 10;
  final v = _v(
    'İki evreli bitki modeli · bir sonraki sayım',
    ['Bugünkü evre', 'Birey', 'Bir yıl sonra erişkin olma olasılığı'],
    [
      ['Genç', juvenile, survival],
      ['Erişkin', adult, 0.8],
    ],
  );
  return _quant(
    v,
    'Yeni tohumlar bir yılda erişkinliğe ulaşamıyor. Bir yıl sonraki sayımda beklenen erişkin sayısı kaçtır?',
    juvenile * survival + adult * 0.8,
    'birey',
    [adult * 0.8, juvenile * survival, juvenile + adult],
    'Erişkin sınıfına geçen gençler ile hayatta kalan erişkinler toplanır. Beklenti Ngenç × pgeçiş + Nerişkin × psağkalım olur.',
  );
}

AdvancedItem _lambda(int a, int b, int c) {
  final init = 100 * a, r = 100 + b, t = c;
  final v = _g(
    _line,
    'Ardışık sayımlarda koloni büyüklüğü (birey)',
    ['Başlangıç', '1. yıl'],
    [init, a * r],
  );
  return _quant(
    v,
    'Son iki sayım arasındaki sonlu çoğalma katsayısı λ bundan sonra da aynı kalırsa son sayımdan $t yıl sonraki beklenen büyüklük kaç bireydir?',
    a * r * math.pow(r / 100, t),
    'birey',
    [a * r * r / 100, a * r + 2 * (a * r - init), a * r * 2],
    'Bir yıllık çarpan λ = Nson/Nilk = ${_s(r / 100)} olur. Son sayım $t yıl ileri götürülürken λ üzeri $t ile çarpılır.',
  );
}

AdvancedItem _logistic(int a, int b, int c) {
  final n = 20 * a, k = 20 * (a + b), r = c / 10;
  final v = _v(
    'Kapalı popülasyon · lojistik model',
    ['N (birey)', 'K (birey)', 'r (yıl⁻¹)'],
    [
      [n, k, r],
    ],
  );
  return _quant(
    v,
    'Tablodaki anda dN/dt = rN(1−N/K) modeli hangi net artış hızını öngörür?',
    r * n * (1 - n / k),
    'birey/yıl',
    [r * n, r * (k - n), r * n * n / k],
    'Taşıma kapasitesinin dolu kesri N/K, kalan kesri 1−N/K olur. Yoğunluktan bağımsız artış rN bu kalan kesirle çarpılır.',
  );
}

AdvancedItem _patch(int a, int b, int c) {
  final full = 10 * a, empty = 10 * b, colon = c / 10, loss = 0.1;
  final v = _v(
    'Habitat adacıkları · bir mevsimlik geçiş',
    ['Başlangıç', 'Yama sayısı', 'Geçiş olasılığı'],
    [
      ['Dolu → boş', full, loss],
      ['Boş → dolu', empty, colon],
    ],
  );
  return _quant(
    v,
    'Her yama başlangıç durumuna göre yalnızca bir geçiş yapabiliyor. Mevsim sonunda dolu olması beklenen yama sayısı kaçtır?',
    full * (1 - loss) + empty * colon,
    'yama',
    [full + empty * colon, empty * colon, full * loss + empty * colon],
    'Başlangıçta dolu yamaların 1−p(yok oluş) kesri dolu kalır. Buna başlangıçta boş yamalardan kolonileşenlerin beklentisi eklenir.',
  );
}

AdvancedItem _lifetable(int a, int b, int c) {
  final l1 = (50 + a) / 100, l2 = (10 + b) / 100, m1 = c, m2 = c + 2;
  final v = _v(
    'Dişi bireyler için yaşam çizelgesi',
    ['Yaş', 'Doğumdan sağkalım lₓ', 'Dişi yavru/birey mₓ'],
    [
      ['0', 1, 0],
      ['1', l1, m1],
      ['2', l2, m2],
    ],
  );
  return _quant(
    v,
    'Üreme yalnızca çizelgedeki yaşlarda gerçekleşiyor. Net üreme katsayısı R₀, doğan her dişi başına kaç dişi yavrudur?',
    l1 * m1 + l2 * m2,
    '',
    [m1 + m2, (l1 + l2) * (m1 + m2), l1 * m1],
    'Bir yaşta üretilen yavrular doğumdan o yaşa erişme olasılığıyla ağırlıklandırılır. R₀ = Σlₓmₓ olur.',
  );
}

AdvancedItem _survival(int a, int b, int c) {
  final initial = 70 + a + b, first = a, censored = b, next = c;
  final risk = initial - first - censored;
  final v = _v(
    'Fidan kohortu · kayıp kayıtları',
    ['Zaman', 'Olay', 'Sayı'],
    [
      ['Başlangıç', 'Canlı fidan', initial],
      ['1. ay', 'Ölüm', first],
      ['2. ay', 'İzlem dışı, son gözlemde canlı', censored],
      ['3. ay', 'Ölüm', next],
    ],
  );
  return _quant(
    v,
    'Sansürlemenin bağımsız olduğu varsayımıyla Kaplan–Meier yöntemi üçüncü ayın sonuna kadar sağkalımı yüzde kaç tahmin eder?',
    100 * (1 - first / initial) * (1 - next / risk),
    '%',
    [
      100 * (initial - first - next) / initial,
      100 * (initial - first - next - censored) / initial,
      100 * (1 - next / risk),
    ],
    'Ölüm zamanlarındaki koşullu sağkalımlar çarpılır. İkinci ay izlemden çıkanlar ölüm sayılmaz, sonraki risk kümesinden çıkar. Risk kümesi son ölümden önce $risk fidan içerir.',
  );
}

AdvancedItem _indicators(int a, int b, int c) {
  final tp = 3 * a + c, fp = b, fn = 2 * c, tn = 30 + b;
  final v = _v(
    'Kuş sesi sınıflandırması · uzman doğrulaması',
    ['Otomatik karar', 'Uzman: tür var', 'Uzman: tür yok'],
    [
      ['Tür var', tp, fp],
      ['Tür yok', fn, tn],
    ],
  );
  final scores = [
    100 * tp / (tp + fp),
    100 * tp / (tp + fn),
    100 * tn / (tn + fp),
    100 * tn / (tn + fn),
  ];
  final xs = [
    'Algılayıcının “tür var” dediği kayıtların gerçekte bu türe ait yüzdesi (pozitif kestirim değeri) kaçtır?',
    'Uzmanın türü doğruladığı kayıtların algılayıcı tarafından yakalanan yüzdesi (duyarlılık) kaçtır?',
    'Uzmanda türün bulunmadığı kayıtların otomatik sistemde doğru olarak negatif sınıflanma yüzdesi (özgüllük) kaçtır?',
    'Otomatik sistemin negatif sınıfladığı kayıtlarda gerçekten tür bulunmayanların yüzdesi (negatif kestirim değeri) kaçtır?',
  ];
  final whys = [
    'Otomatik pozitifler arasındaki doğru pozitif oranı $tp/($tp+$fp) olur.',
    'Uzman pozitifler arasındaki doğru pozitif oranı $tp/($tp+$fn) olur.',
    'Uzman negatifler arasındaki doğru negatif oranı $tn/($tn+$fp) olur.',
    'Otomatik negatifler arasındaki doğru negatif oranı $tn/($tn+$fn) olur.',
  ];
  final mode = (a + b + c) % 4;
  return _quant(v, xs[mode], scores[mode], '%', [
    for (var i = 0; i < 4; i++)
      if (i != mode) scores[i],
    100 - scores[mode],
    scores[mode] / 2,
  ], whys[mode]);
}

AdvancedItem _detect(int a, int b, int c) {
  final p = (20 + a) / 100, occupied = b + 10, visits = c;
  final v = _v(
    'Türün varlığı bilinen alanlar · tarama modeli',
    ['Alan sayısı', 'Ziyaret/alan', 'Ziyaret başına tespit olasılığı'],
    [
      [occupied, visits, p],
    ],
  );
  return _quant(
    v,
    'Ziyaretler bağımsızdır ve alanlar kapanım varsayımını sağlar. En az bir kez tür kaydı beklenen alan sayısı kaçtır?',
    occupied * (1 - math.pow(1 - p, visits)),
    'alan',
    [
      occupied * p,
      occupied * math.pow(1 - p, visits),
      occupied * math.pow(p, visits),
    ],
    'Bir alanda bütün ziyaretlerin kaçırma olasılığı (1−p)ᵏ olur. Bunun tümleyeni, alan sayısıyla çarpılarak en az bir kez tespit edilen alanların beklenen sayısı elde edilir.',
  );
}

AdvancedItem _simpson(int a, int b, int c) {
  final vals = [a, b, 3 * c], n = a + b + 3 * c;
  final v = _g(_bar, 'Üç bitki türünün birey sayıları', ['K', 'L', 'M'], vals);
  final same = vals.fold<int>(0, (sum, x) => sum + x * (x - 1)) / (n * (n - 1));
  return _quant(
    v,
    'Bu örnekten geri koymadan rastgele seçilen iki bireyin farklı türlere ait olma olasılığı yüzde kaçtır?',
    100 * (1 - same),
    '%',
    [
      100 * same,
      100 * (1 - vals.fold<num>(0, (s, x) => s + math.pow(x / n, 2))),
      100 * (1 - 1 / n),
    ],
    'Aynı tür olasılığı Σnᵢ(nᵢ−1)/[N(N−1)] ile bulunur. Farklı tür seçilmesi bunun tümleyenidir.',
  );
}

AdvancedItem _jaccard(int a, int b, int c) {
  final v = _v(
    'Bitişik iki çayırdaki tam tür listeleri',
    ['Görüldüğü yer', 'Tür sayısı'],
    [
      ['Yalnız kuzey', a],
      ['Yalnız güney', b],
      ['Her iki çayır', c],
    ],
  );
  return _quant(
    v,
    'İki listenin Jaccard benzerliği hangi yüzdedir? J = ortak tür sayısı / birleşimdeki tür sayısı.',
    100 * c / (a + b + c),
    '%',
    [100 * c / (a + b + 2 * c), 100 * c / (a + c), 100 * (a + b) / (a + b + c)],
    'Birleşim kuzeye özgü, güneye özgü ve ortak türleri birer kez içerir. Böylece pay $c ve payda ${a + b + c} olur.',
  );
}

AdvancedItem _evenness(int a, int b, int c) {
  final k = a + b + c, d = a;
  final evenFirst = (a + b + c).isEven;
  final row1 = [k, k, k, k], row2 = [k + 2 * d + c, k - d, k - d, k - c];
  final v = _v(
    'Eşit büyüklükte topluluk örnekleri',
    ['Örnek', 'Tür A', 'Tür B', 'Tür C', 'Tür D'],
    [
      ['K', ...(evenFirst ? row1 : row2)],
      ['L', ...(evenFirst ? row2 : row1)],
    ],
  );
  final name = evenFirst ? 'K' : 'L';
  return _choice(
    v,
    'Her türün en az bir bireyi var. Tür zenginliği ve bireylerin türlere eşit dağılımı için hangi sonuç doğrudur?',
    'Zenginlik eşittir; $name örneğinde dağılım daha eşittir.',
    [
      'Baskın türü olan örnek daha fazla tür içerir.',
      'Toplam birey sayıları eşit olduğundan türler iki örnekte de eşit dağılmıştır.',
      'Düşük bolluklu türler zenginlik hesabına alınmaz.',
    ],
    'Her iki örnekte de dört tür sayılır. $name örneğinde tür başına $k birey vardır. Diğerinde toplam aynı olsa da bolluklar farklıdır.',
  );
}

AdvancedItem _accumulation(int a, int b, int c) {
  final mode = (a + b + c) % 4;
  final increments = [
    [0, b, c],
    [b, 0, c],
    [b, c, 0],
    [b, c, 1],
  ][mode];
  final vals = [a];
  for (final addition in increments) {
    vals.add(vals.last + addition);
  }
  final v = _g(_line, 'Birikimli gözlenen tür sayısı – örnekleme günü', [
    '1',
    '2',
    '3',
    '4',
  ], vals);
  final claims = [
    'İkinci gün liste genişlememiştir.',
    'Üçüncü gün liste genişlememiştir.',
    'Dördüncü gün liste genişlememiştir.',
    'İkinci, üçüncü ve dördüncü günlerin her birinde listeye en az bir tür eklenmiştir.',
  ];
  return _choice(
    v,
    'Eşit örnekleme çabasıyla izlenen alanda hangi ifade birikimli kayıtlarla uyumludur?',
    claims[mode],
    [
      for (var i = 0; i < 4; i++)
        if (i != mode) claims[i],
    ],
    'Birikimli sayıdaki günlük artışlar sırasıyla ${increments.join(', ')} türdür. Sıfır artış yalnızca o gün yeni kayıt gelmediğini gösterir. Eğri, görülmemiş türlerin varlığını dışlamaz.',
  );
}

AdvancedItem _diffusion(int a, int b, int c) {
  final area = 5 * a, thick = b, diff = c, d = 2;
  final v = _v(
    'Yaprak modeli · sabit koşullar',
    ['Alan A (cm²)', 'Yol L (mm)', 'Derişim farkı (µmol/cm³)'],
    [
      [area, thick, diff],
    ],
  );
  return _quant(
    v,
    'Modelde etkin difüzyon katsayısı 2 cm²/dk değerindedir. Fick yasasına göre yüksek derişimden düşük derişime toplam aktarım hızı kaç µmol/dk olur?',
    d * area * diff / (thick / 10),
    'µmol/dk',
    [
      d * area * diff / thick,
      d * diff / (thick / 10),
      area * diff / (thick / 10),
    ],
    'Toplam aktarım hızı D A ΔC/L ile verilir. Derişim ve alan santimetre tabanlı olduğundan yol $thick mm = ${_s(thick / 10)} cm alınır.',
  );
}

AdvancedItem _waterpot(int a, int b, int c) {
  final base = -0.6 - a / 100, p = c / 10, diff = (b + 1) / 100;
  final higher = (a + b).isEven;
  final psiA = base + p, psiB = psiA + (higher ? diff : -diff);
  final otherP = p / 2;
  final v = _v(
    'Bitişik iki bitki hücresi · MPa',
    ['Hücre', 'Çözünen potansiyeli', 'Basınç potansiyeli'],
    [
      ['A', base, p],
      ['B', psiB - otherP, otherP],
    ],
  );
  final direction = higher ? 'B → A' : 'A → B';
  return _choice(
    v,
    'Zar suya geçirgendir. Yer çekimi ve matrik bileşenler önemsizse başlangıçtaki net su hareketi hangi yöndedir?',
    direction,
    [
      higher ? 'A → B' : 'B → A',
      'Başlangıçta net akış yoktur.',
      'Su potansiyeli iki bileşenden hesaplanamaz.',
    ],
    'Toplam su potansiyeli çözünen ve basınç bileşenlerinin toplamıdır. A için ${_s(psiA)}, B için ${_s(psiB)} MPa bulunur. Su yüksek toplam potansiyelden düşüğe gider.',
  );
}

AdvancedItem _rq(int a, int b, int c) {
  final base = 100 + a, oxygen = b * 4, carbon = oxygen + c - 4;
  final v = _g(
    _bar,
    'Kapalı respirometre · miktarlar (µmol)',
    ['O₂ ilk', 'O₂ son', 'CO₂ ilk', 'CO₂ son'],
    [base, base - oxygen, 2 * a, 2 * a + carbon],
  );
  return _quant(
    v,
    'Başka gaz kaynağı veya gideri bulunmuyor. Tohum örneğinin molar solunum katsayısı RQ = üretilen CO₂ / tüketilen O₂ için hangi değer bulunur?',
    carbon / oxygen,
    '',
    [oxygen / carbon, (2 * a + carbon) / (base - oxygen), carbon / base],
    'Mutlak gaz miktarları yerine gözlem süresindeki değişimler hesaplanır. CO₂ $carbon µmol artmış, O₂ $oxygen µmol azalmıştır.',
  );
}

AdvancedItem _light(int a, int b, int c) {
  final lo = a, width = 10 * b, gain = c;
  final v = _g(
    _line,
    'Net O₂ akısı – ışık şiddeti (µmol foton/m²·s)',
    ['$lo', '${lo + width}', '${lo + 2 * width}'],
    [-gain, gain, 3 * gain],
  );
  return _quant(
    v,
    'Gösterilen aralıkta net akı ışık şiddetiyle doğrusal değişiyor. Net fotosentezin sıfır olduğu ışık dengeleme noktası kaç µmol foton/(m²·s) olur?',
    lo + width / 2,
    'µmol/(m²·s)',
    [lo + width, lo, 2 * lo + width],
    'İlk iki ölçümde net oksijen akıları eşit büyüklükte ve zıt işaretlidir. Doğrusal ara değerlemede sıfır bu iki ışık şiddetinin tam ortasına düşer.',
  );
}

AdvancedItem _oxygen(int a, int b, int c) {
  final volume1 = a * 100, volume2 = b * 100, o1 = c + 4, o2 = c - 1;
  final v = _v(
    'Göl modeli · karışmadan önce',
    ['Katman', 'Hacim (m³)', 'O₂ (mg/L)'],
    [
      ['Üst', volume1, o1],
      ['Alt', volume2, o2],
    ],
  );
  return _quant(
    v,
    'İki katman tamamen karışırken atmosferle alışveriş, üretim ve tüketim yoktur. Son çözünmüş O₂ derişimi kaç mg/L olur?',
    (volume1 * o1 + volume2 * o2) / (volume1 + volume2),
    'mg/L',
    [
      (o1 + o2) / 2,
      (volume1 * o2 + volume2 * o1) / (volume1 + volume2),
      o1 + o2,
    ],
    'Oksijen kütlesi korunur. Katmanların derişimleri kendi hacimleriyle ağırlıklandırılır. Hacim birimleri pay ve paydada aynı çarpanla dönüştüğü için sadeleşir.',
  );
}

AdvancedItem _stratify(int a, int b, int c) {
  final area1 = 10 * c, area2 = 100 - area1, n1 = a, n2 = b + 30;
  final v = _v(
    'Tabakalı çayır sayımı · birim alan başına yoğunluk',
    ['Tabaka', 'Alan (ha)', 'Tahmin (yuva/ha)'],
    [
      ['Kumlu', area1, n1],
      ['Killi', area2, n2],
    ],
  );
  return _quant(
    v,
    'Her tabakanın yoğunluk tahmini kendi alanını temsil ediyor. Tüm çayırın tahmini ortalama yuva yoğunluğu kaç yuva/ha olur?',
    (area1 * n1 + area2 * n2) / 100,
    'yuva/ha',
    [(n1 + n2) / 2, (area1 * n2 + area2 * n1) / 100, area1 * n1 + area2 * n2],
    'Tabaka tahminlerinden önce toplam yuva sayısı alan × yoğunluk ile bulunur. İki toplam 100 hektara bölünür.',
  );
}

AdvancedItem _isomix(int a, int b, int c) {
  final x = -40 + a / 5, y = x + b / 2, p = c / 10, mix = x * p + y * (1 - p);
  final v = _v(
    'İki kaynaklı beslenme modeli',
    ['Örnek', 'İzotop imzası (‰)'],
    [
      ['Kaynak K', x],
      ['Kaynak L', y],
      ['Tüketici', mix],
    ],
  );
  return _quant(
    v,
    'Bu öğretim modelinde fraksiyonlaşma sıfır, derişimler eşit ve imzalar kaynak paylarıyla doğrusal karışıyor. Tüketicide K kaynağının besinsel payı yüzde kaçtır?',
    100 * p,
    '%',
    [100 * (1 - p), 100 * (mix - x) / (y - x), 100 * p / 2, 100 - p],
    'İki kaynaklı modelde δtüketici = fK δK + (1−fK) δL olur. Buradan fK = (δL−δtüketici)/(δL−δK) bulunur.',
  );
}

AdvancedItem _enzyme(int a, int b, int c) {
  final vmax = 10 * a, km = b, substrate = c * b;
  final v = _v(
    'Gıda nişastasını parçalayan enzim · model değerleri',
    ['Vmax (µmol/dk)', 'Km (mmol/L)', '[S] (mmol/L)'],
    [
      [vmax, km, substrate],
    ],
  );
  return _quant(
    v,
    'İlk hız Michaelis–Menten modeline uyuyor. Verilen substrat derişiminde hız kaç µmol/dk olur?',
    vmax * substrate / (km + substrate),
    'µmol/dk',
    [vmax * substrate / km, vmax * km / (km + substrate), vmax / 2],
    'Michaelis–Menten bağıntısı v = Vmax[S]/(Km+[S]) şeklindedir. Doygunluk kesri $c/(1+$c) olduğundan hız sınırlayıcı Vmax değerinin altında kalır.',
  );
}

AdvancedItem _growth(int a, int b, int c) {
  final init = a + 3, step = b + 3, days = c + 2;
  final v = _g(
    _line,
    'Aynı bitki grubunun ortalama kuru kütlesi (g)',
    ['0. gün', '$days. gün'],
    [init, init + step],
  );
  return _quant(
    v,
    'Bu aralık için bağıl büyüme hızı [ln(W₂)−ln(W₁)]/Δt olarak tanımlanmıştır. Hız kaç gün⁻¹ olur?',
    math.log((init + step) / init) / days,
    'gün⁻¹',
    [step / days, step / (init * days), math.log((init + step) / init) * days],
    'Başlangıç ve son kütlelerin oranının doğal logaritması $days güne bölünür. Bu ölçüt başlangıç büyüklüğüne göre göreli değişimi ifade eder.',
  );
}

AdvancedItem _variance(int a, int b, int c) {
  final g = 10 + a, e = 10 + b, mode = (a + b + c) % 4;
  final g2 = mode == 2
      ? g * (1 + c)
      : mode == 3
      ? g + c
      : g;
  final e2 = mode == 0
      ? e + c
      : mode == 1
      ? e - c
      : mode == 2
      ? e * (1 + c)
      : e;
  final v = _v(
    'Aynı karakter için iki popülasyondaki varyans bileşenleri',
    ['Popülasyon', 'Genetik varyans VG', 'Çevresel varyans VE'],
    [
      ['I', g, e],
      ['II', g2, e2],
    ],
  );
  final claims = [
    'II’de genetik varyans korunmuş, daha yüksek çevresel varyans H² oranını düşürmüştür.',
    'II’de genetik varyans korunmuş, daha düşük çevresel varyans H² oranını yükseltmiştir.',
    'İki bileşen aynı oranda büyüdüğünden H² iki popülasyonda aynıdır.',
    'II’de çevresel varyans korunmuş, daha yüksek genetik varyans H² oranını yükseltmiştir.',
  ];
  return _choice(
    v,
    'Kovaryans ve etkileşim sıfır kabul ediliyor. H² = VG/(VG+VE) için hangi karşılaştırma verilerden çıkar?',
    claims[mode],
    [
      for (var i = 0; i < 4; i++)
        if (i != mode) claims[i],
    ],
    'I için oran $g/${g + e}, II için $g2/${g2 + e2} olur. Bu oran bir popülasyonun belirli bir ortamda gösterdiği varyansı açıklar; bir bireyin özelliğini genetik ve çevresel yüzdelere ayırmaz.',
  );
}

AdvancedItem _block(int a, int b, int c) {
  final valley = 10 + a, hill = 30 + b, mode = (a + b + c) % 4;
  final dv = mode == 3 ? -c : c,
      dh = mode == 0
          ? c
          : mode == 2
          ? 0
          : -c;
  final v = _v(
    'İki arazi bloğu · rastgele atanmış parseller',
    ['Blok', 'Kontrol verimi (kg)', 'Uygulama verimi (kg)'],
    [
      ['Vadi', valley, valley + dv],
      ['Yamaç', hill, hill + dh],
    ],
  );
  final claims = [
    'İki blokta gözlenen fark da olumludur; sonucu başka arazilere genellemek için bağımsız bloklar gerekir.',
    'İşlem farkı iki blokta ters yönlüdür; ortalama fark tek başına bu deseni gizler.',
    'Yalnız vadide artış görülür; yamaçta gözlenen eşitlik tüm yamaçlarda etkisizlik kanıtı sayılmaz.',
    'Her iki blokta verim düşmüştür; azalışın başka konumlarda da aynı olacağı bu örnekten kesinleşmez.',
  ];
  return _choice(
    v,
    'Her hücre bir parsel ölçümüdür. Ölçülen blok içi farkları ve bu verinin sınırını hangi değerlendirme doğru belirtiyor?',
    claims[mode],
    [
      for (var i = 0; i < 4; i++)
        if (i != mode) claims[i],
    ],
    'Uygulama eksi kontrol farkı vadide $dv kg, yamaçta $dh kg olur. Konumlar arası düzey farklarıyla işlem etkisini karıştırmamak için aynı bloktaki parseller karşılaştırılır.',
  );
}

AdvancedItem _interval(int a, int b, int c) {
  final center = (a - b) / 10,
      width = c / 10,
      lo = center - width,
      hi = center + width;
  final v = _v(
    'İki bakım yönteminin farkı · tahmin',
    ['Farkın yönü', 'Tahmin (cm)', '%95 güven aralığı (cm)'],
    [
      ['K eksi L', center, '[${_s(lo)}, ${_s(hi)}]'],
    ],
  );
  final plus = a > b + c, minus = a < b - c;
  final options = [
    'Aralık sıfırın üstündedir; bu analiz K lehine bir ortalama farkı destekler.',
    'Aralık sıfırın altındadır; bu analiz L lehine bir ortalama farkı destekler.',
    'Aralık sıfırı içerir; bu analizle sıfır fark dışlanamaz.',
    'Aralık bireysel bitkilerin %95’inin boyunu gösterir.',
  ];
  final ans = plus
      ? 0
      : minus
      ? 1
      : 2;
  // The allocation n varies across independent model trials and determines the available precision.
  final sample = 10 * a + 50;
  return _choice(
    v,
    'Her grupta $sample bağımsız bitkiyle iki taraflı ortalama farkı incelenmiştir. Verilen %95 güven aralığı için hangi yorum geçerlidir?',
    options[ans],
    [
      for (var i = 0; i < 4; i++)
        if (i != ans) options[i],
    ],
    'Aralık ortalama farkı içindir. Alt sınır ${_s(lo)} cm ve üst sınır ${_s(hi)} cm olduğundan sıfırın konumu farkın yönüne dair destek düzeyini belirler.',
  );
}

AdvancedItem _pseudo(int a, int b, int c) {
  final ponds = 2 * c, per = a + 5, days = b;
  final v = _v(
    'Gölgelik etkisi · deney planı',
    ['Bir karar / gözlem', 'Sayı'],
    [
      ['Rastgele atanan bağımsız gölet', ponds],
      ['Her gölette işaretlenen yaprak', per],
      ['Her yaprakta ölçüm günü', days],
    ],
  );
  return _choice(
    v,
    'Gölgeleme göletin tamamına uygulanıyor. İşlem için bağımsız deney birimi sayısını doğru değerlendiren seçenek hangisidir?',
    '$ponds gölet bağımsız işlem birimidir; yaprak ve gün ölçümleri gölet içinde kümelenir.',
    [
      '${ponds * per} yaprak bağımsız işlem birimidir; gölet etkisi önemsizdir.',
      '${ponds * per * days} ölçümün tamamı ayrı işlem tekrarıdır.',
      '$days gün bağımsız gölet sayısının yerini alır.',
    ],
    'İşlemin rastgele atandığı birim gölettir. Aynı göletteki yapraklar ve aynı yapraktaki tekrarlar ortak çevreyi ve ölçüm geçmişini paylaşır.',
  );
}

AdvancedItem _rank(int a, int b, int c) {
  final first = [10 * a, 10 * b, 10 * c, 10 * (a + c)], shift = (a + b + c) % 4;
  final rates = [2, 4, 6, 8], labels = ['K', 'L', 'M', 'N'];
  final rows = [
    for (var i = 0; i < 4; i++)
      <Object>[labels[(i + shift) % 4], first[i], first[i] * rates[i] ~/ 10],
  ]..sort((x, y) => x[0].toString().compareTo(y[0].toString()));
  final v = _v('Fidan grupları · aynı büyüme dönemi', [
    'Grup',
    'Başlangıç fidanı',
    'Evreyi tamamlayan',
  ], rows);
  final seq = [for (var i = 0; i < 4; i++) (i + shift) % 4];
  final act = QuestionActivity(
    kind: ActivityKind.ordering,
    title: 'Orana göre küçükten büyüğe',
    items: labels,
    solution: seq,
  );
  final order = seq.map((i) => labels[i]).toList();
  String code(List<String> values) => values.join(' → ');
  return _choice(
    v,
    'Fidan gruplarını, bir sonraki evreye ulaşanların başlangıca oranına göre düşükten yükseğe sıralayın.',
    code(order),
    [
      code(order.reversed.toList()),
      code([order[1], order[0], order[2], order[3]]),
      code([order[0], order[2], order[1], order[3]]),
    ],
    'Her grupta evreyi tamamlayan sayı başlangıç sayısına bölünür. Artan oranlar sırasıyla %20, %40, %60 ve %80 olur.',
    activity: act,
  );
}

String _mapping(
  List<String> names,
  List<String> results,
  List<int> seq,
  int shift,
) => [
  for (var j = 0; j < names.length; j++)
    '${names[j]}: ${results[(seq[j] + shift) % results.length]}',
].join(' · ');

AdvancedItem _effects(int a, int b, int c) {
  final base = a, water = b, light = c;
  final types = [
    'Yalnız su etkisi',
    'Yalnız ışık etkisi',
    'Toplamsal iki etki',
    'Birlikte ek artış',
  ];
  final series = [
    [base, base + water, base, base + water],
    [base, base, base + light, base + light],
    [base, base + water, base + light, base + water + light],
    [base, base + water, base + light, base + water + light + c],
  ];
  final rot = (a + b + c) % 4, ids = ['K', 'L', 'M', 'N'];
  final rows = [
    for (var i = 0; i < 4; i++) <Object>[ids[i], ...series[(i + rot) % 4]],
  ];
  final v = _v('Fidan büyümesi (mm) · ideal ölçüm sonuçları', [
    'Grup',
    'Temel',
    'Su',
    'Işık',
    'İkisi',
  ], rows);
  final seq = [for (var i = 0; i < 4; i++) (i + rot) % 4];
  final act = QuestionActivity(
    kind: ActivityKind.matching,
    title: 'Her desen için uygun etkiyi seç',
    left: ids,
    right: types,
    solution: seq,
  );
  return _choice(
    v,
    'Su ve ışık takviyelerine verilen yanıtları temel koşulla karşılaştırarak her grubu uygun etki deseniyle eşleştirin.',
    _mapping(ids, types, seq, 0),
    [for (var shift = 1; shift <= 3; shift++) _mapping(ids, types, seq, shift)],
    'Tekli etkiler temel değerden fark alınarak hesaplanır. İkili yanıt bu farkların toplamını aşıyorsa birlikte ek artış vardır. K, L, M ve N için sırasıyla ${seq.map((i) => types[i]).join(', ')} bulunur.',
    activity: act,
  );
}

AdvancedItem _niches(int a, int b, int c) {
  final dry = 5 + a,
      wet = dry + 20 + c,
      shade = 30 + b,
      bright = shade + 30 + c;
  final ids = ['K', 'L', 'M', 'N'],
      words = [
        'Kuru ve gölgeli',
        'Kuru ve aydınlık',
        'Nemli ve gölgeli',
        'Nemli ve aydınlık',
      ];
  final rot = (a + 2 * b + c) % 4,
      seq = [for (var i = 0; i < 4; i++) (i + rot) % 4];
  final v = _v(
    'Gösterge bitkilerinin en sık bulunduğu mikrohabitatlar',
    ['Tür kodu', 'Toprak nemi (%)', 'Açık alan ışığı (%)'],
    [
      for (var i = 0; i < 4; i++)
        [ids[i], seq[i] < 2 ? dry : wet, seq[i].isEven ? shade : bright],
    ],
  );
  final thresholds =
      'Nem %${dry + 10}, ışık %${shade + 15} üzerindeyse sırasıyla “nemli” ve “aydınlık” sınıfları kullanılıyor.';
  final act = QuestionActivity(
    kind: ActivityKind.matching,
    title: 'Tür kodunu mikrohabitat sınıfıyla eşleştir',
    left: ids,
    right: words,
    solution: seq,
  );
  return _choice(
    v,
    '$thresholds Verilen eşiklerle her tür kodunu gözlenen mikrohabitat sınıfıyla eşleştirin.',
    _mapping(ids, words, seq, 0),
    [for (var shift = 1; shift <= 3; shift++) _mapping(ids, words, seq, shift)],
    'Her türün iki ölçümü kendi eşiğiyle ayrı karşılaştırılır. Sırasıyla ${seq.map((i) => words[i]).join(', ')} sınıfları bulunur. En sık karşılaşılan sınıf, türün yalnızca orada yaşayabildiğini göstermez.',
    activity: act,
  );
}

AdvancedItem _sediment(int a, int b, int c) {
  final names = [
    'Saz poleni artışı',
    'İnce kül tabakası',
    'Turba başlangıcı',
    'Kumlu taşkın katmanı',
  ];
  final rot = (a + b + c) % 4;
  final depths = [a, a + b, a + b + c, 2 * a + b + c];
  final seq = [for (var i = 3; i >= 0; i--) (i + rot) % 4];
  final rows = [
    for (var i = 0; i < 4; i++) <Object>[names[(i + rot) % 4], depths[i]],
  ]..sort((x, y) => x[0].toString().compareTo(y[0].toString()));
  final v = _v('Bozulmamış göl karotu · yüzeyden derinlik', [
    'Gösterge',
    'Derinlik (cm)',
  ], rows);
  final act = QuestionActivity(
    kind: ActivityKind.ordering,
    title: 'Eskiden yeniye diz',
    items: names,
    solution: seq,
  );
  final order = seq.map((i) => names[i]).toList();
  return _choice(
    v,
    'Katmanlar devrilmemiş ve yeniden işlenmemiştir. Dört çevresel kaydı en eski olaydan en yeniye sıralayın.',
    order.join(' → '),
    [
      order.reversed.join(' → '),
      [order[1], order[0], order[2], order[3]].join(' → '),
      [order[0], order[2], order[1], order[3]].join(' → '),
    ],
    'Normal çökelimde daha derin düzey daha eskidir. Derinlikler büyükten küçüğe ${depths.reversed.join(', ')} cm olarak sıralanır.',
    activity: act,
  );
}

typedef _Term = ({String term, String clue});
_Term _t(String term, String clue) => (term: term, clue: clue);
Iterable<AdvancedFamily> _conceptFamilies() sync* {
  final sets = <({String key, String topic, int count, StudyLevel level, List<_Term> terms})>[
    (
      key: 'cell',
      topic: 'Hücre biyolojisi',
      count: 100,
      level: _hs,
      terms: [
        _t(
          'Ribozom',
          'mRNA üzerindeki kodonlara göre amino asitleri birbirine bağlayan, zarsız kompleks',
        ),
        _t(
          'Golgi aygıtı',
          'Salgı yolundaki proteinlerin işlendiği ve hedeflerine göre ayrıştırıldığı yassı kesecik sistemi',
        ),
        _t(
          'Mitokondri',
          'Ökaryot hücrede elektron taşıma zincirinin iç zarına yerleştiği organel',
        ),
        _t(
          'Kloroplast',
          'Yeşil bitkilerde ışığa bağlı tepkimelerin tilakoit zarlarında yürütüldüğü organel',
        ),
        _t(
          'Çekirdekçik',
          'Ökaryot çekirdeğinde ribozomal alt birimlerin öncüllerinin bir araya getirildiği bölge',
        ),
        _t(
          'Düz endoplazmik retikulum',
          'Ribozom taşımayan, yağ sentezinde görev alan zar ağı',
        ),
        _t(
          'Granüllü endoplazmik retikulum',
          'Sitozole bakan yüzüne salgı proteinlerini sentezleyen ribozomların bağlandığı zar ağı',
        ),
        _t(
          'Lizozom',
          'Hayvan hücresinde asidik lümeninde hidrolitik enzimlerle maddeleri parçalayan organel',
        ),
        _t(
          'Peroksizom',
          'Oksidazlar ve katalaz yardımıyla hidrojen peroksit dönüşümünü yürüten tek zarlı organel',
        ),
        _t(
          'Sentromer',
          'Bir kromozomda kinetokorun kurulduğu özgül DNA bölgesi',
        ),
        _t(
          'Telomer',
          'Doğrusal kromozomların uçlarını koruyan tekrarlı DNA ve protein yapısı',
        ),
        _t(
          'Plazmodezma',
          'Komşu bitki hücrelerinin sitoplazmasını çeper boyunca birbirine bağlayan kanal',
        ),
        _t(
          'Merkezi koful',
          'Olgun bitki hücresinde tonoplastla çevrili, turgora katkı sağlayan büyük bölme',
        ),
        _t(
          'Mikrotübül',
          'Tübülin alt birimlerinden oluşan, iğ ipliklerinde de bulunan içi boş sitoskeletal yapı',
        ),
        _t(
          'Aktin filamenti',
          'Kas kasılmasında miyozinle etkileşen ince sitoskeletal lif',
        ),
      ],
    ),
    (
      key: 'eco',
      topic: 'Ekolojik ilişkiler',
      count: 100,
      level: _hs,
      terms: [
        _t(
          'Mutualizm',
          'Türler arası etkileşimde her iki türün ölçülen uyum başarısının artması',
        ),
        _t(
          'Kommensalizm',
          'Türlerden birinin yarar gördüğü, diğeri üzerinde ölçülebilir etki saptanmayan etkileşim',
        ),
        _t(
          'Türler arası rekabet',
          'İki farklı türün ortak sınırlayıcı kaynak nedeniyle birbirinin başarısını düşürmesi',
        ),
        _t(
          'Avcılık',
          'Bir canlının başka bir canlıyı yakalayıp öldürerek besin olarak tüketmesi',
        ),
        _t(
          'Birincil süksesyon',
          'Toprak ve önceki karasal topluluk bulunmayan yeni yüzeyde topluluğun zamanla kurulması',
        ),
        _t(
          'İkincil süksesyon',
          'Bozulma sonrasında toprağı kalan bir alanda topluluğun yeniden gelişmesi',
        ),
        _t('Ekoton', 'Komşu iki ekosistem tipi arasındaki geçiş alanı'),
        _t(
          'Ekolojik niş',
          'Bir türün kaynak kullanımı, çevresel gereksinimleri ve diğer türlerle ilişkilerinin bütünü',
        ),
        _t('Habitat', 'Bir organizmanın doğal olarak yaşadığı fiziksel yer'),
        _t(
          'Taşıma kapasitesi',
          'Verilen koşullarda bir ortamın uzun dönemde destekleyebildiği popülasyon büyüklüğü',
        ),
        _t(
          'Biyobirikim',
          'Bir kimyasalın zaman içinde tek bir organizmanın dokularında birikmesi',
        ),
        _t(
          'Biyobüyütme',
          'Kalıcı bir maddenin ortalama derişiminin besin zincirinde üst basamaklara doğru artması',
        ),
        _t(
          'Net birincil üretim',
          'Üreticilerin bağladığı toplam organik maddeden kendi solunum gideri çıkarılınca kalan üretim',
        ),
        _t(
          'Ayrıştırıcı',
          'Ölü organik maddeleri dışarı salgıladığı enzimlerle parçalayıp emen canlı',
        ),
        _t(
          'Gösterge tür',
          'Varlığı veya bolluğu belirli çevre koşulları hakkında bilgi sağlayan tür',
        ),
      ],
    ),
    (
      key: 'method',
      topic: 'Araştırma yöntemleri',
      count: 100,
      level: _u,
      terms: [
        _t(
          'Rastgele atama',
          'Deney birimlerinin işlem gruplarına şansa dayalı bir düzenle dağıtılması',
        ),
        _t(
          'Rastgele örnekleme',
          'Popülasyondan inceleme birimlerinin tanımlı bir olasılık mekanizmasıyla seçilmesi',
        ),
        _t(
          'Kör değerlendirme',
          'Sonuçları puanlayan kişinin hangi birime hangi işlemin uygulandığını bilmemesi',
        ),
        _t(
          'Negatif kontrol',
          'İncelenen özgül yanıtın oluşmaması beklenen karşılaştırma koşulu',
        ),
        _t(
          'Pozitif kontrol',
          'Ölçümün çalıştığını sınamak için beklenen yanıtı verdiği bilinen koşul',
        ),
        _t(
          'Bağımsız değişken',
          'Deneyde etkisi araştırılmak üzere araştırmacının değiştirdiği etken',
        ),
        _t(
          'Bağımlı değişken',
          'İşleme yanıt olarak ölçülen veya kaydedilen sonuç değişkeni',
        ),
        _t(
          'Karıştırıcı değişken',
          'Maruziyetle ilişkili olup sonucu da etkileyerek görünen ilişkiyi çarpıtan etken',
        ),
        _t(
          'Yalancı tekrar',
          'Aynı deney birimindeki bağımlı alt ölçümlerin ayrı işlem tekrarları sayılması',
        ),
        _t(
          'Bloklama',
          'Benzer birimleri gruplara ayırıp işlemleri her grubun içinde karşılaştırma düzeni',
        ),
        _t(
          'Sistematik ölçüm hatası',
          'Ölçümlerin referanstan tutarlı biçimde bir yöne sapması',
        ),
        _t(
          'Sansürlenmiş gözlem',
          'İzlem biterken olay zamanının tam değeri bilinmeyen ancak kısmi zaman bilgisi olan kayıt',
        ),
        _t(
          'Ön kayıt',
          'Hipotezlerin ve temel analiz kararlarının veriler incelenmeden önce kayda geçirilmesi',
        ),
        _t(
          'Teknik tekrar',
          'Aynı biyolojik örnek üzerinde ölçüm işleminin birden fazla kez uygulanması',
        ),
        _t(
          'Etki büyüklüğü',
          'Karşılaştırılan koşullar arasındaki farkın veya ilişkinin büyüklüğünü nicelendiren ölçü',
        ),
      ],
    ),
    (
      key: 'evolution',
      topic: 'Kalıtım ve evrim',
      count: 80,
      level: _hs,
      terms: [
        _t('Homozigot', 'Diploit bir lokusta aynı iki aleli taşıyan genotip'),
        _t(
          'Heterozigot',
          'Diploit bir lokusta birbirinden farklı iki aleli taşıyan genotip',
        ),
        _t(
          'Eş baskınlık',
          'Heterozigotta iki alelin ürünlerinin fenotipte birlikte ayırt edilebilmesi',
        ),
        _t(
          'Eksik baskınlık',
          'Heterozigotun ölçülen fenotipinin iki homozigot fenotip arasında kalması',
        ),
        _t(
          'Pleiotropi',
          'Tek bir genin birden çok fenotipik karakteri etkilemesi',
        ),
        _t(
          'Poligenik kalıtım',
          'Bir karakterin varyasyonuna birden fazla lokusun katkı vermesi',
        ),
        _t(
          'Gen akışı',
          'Göç eden bireyler veya gametler yoluyla popülasyonlar arasında alel aktarılması',
        ),
        _t(
          'Genetik sürüklenme',
          'Sonlu popülasyonda rastlantısal örnekleme nedeniyle alel sıklıklarının değişmesi',
        ),
        _t(
          'Kurucu etkisi',
          'Yeni bir popülasyon az sayıda bireyle kurulduğunda kaynak popülasyondan farklı alel frekansları oluşması',
        ),
        _t(
          'Darboğaz etkisi',
          'Popülasyonun kısa sürede çok küçülmesinin rastlantısal genetik çeşitlilik kaybına yol açması',
        ),
        _t(
          'Homoloji',
          'İki özelliğin ortak atadan kalıtılmış kökeni paylaşması',
        ),
        _t(
          'Yakınsak evrim',
          'Ayrı soylarda benzer işlevsel özelliklerin birbirinden bağımsız ortaya çıkması',
        ),
        _t(
          'Fenotipik plastisite',
          'Aynı genotipin farklı çevrelerde farklı fenotipler sergileyebilmesi',
        ),
        _t(
          'Bağlantı',
          'Aynı kromozom üzerinde yakın lokusların bağımsız dağılımdan daha sık birlikte aktarılması',
        ),
      ],
    ),
    (
      key: 'physiology',
      topic: 'Bitki fizyolojisi',
      count: 59,
      level: _hs,
      terms: [
        _t(
          'Ksilem',
          'Damarlı bitkilerde kökten üst organlara su ve mineral taşımada temel iletim dokusu',
        ),
        _t(
          'Floem',
          'Fotosentez ürünlerini kaynak dokulardan tüketen ya da depolayan dokulara taşıyan iletim dokusu',
        ),
        _t(
          'Stoma',
          'Bekçi hücrelerinin açıklığını ayarladığı, yaprakta gaz alışverişine aracılık eden gözenek',
        ),
        _t(
          'Kütikula',
          'Karasal bitki epidermisinin dış yüzeyinde su kaybını sınırlayan mumsu örtü',
        ),
        _t(
          'Transpirasyon',
          'Bitkinin toprak üstü kısımlarından özellikle stomalar yoluyla su buharı kaybı',
        ),
        _t(
          'Gutasyon',
          'Kök basıncıyla yaprak uçlarındaki hidatotlardan sıvı su çıkışı',
        ),
        _t(
          'Turgor basıncı',
          'Hücre içeriğinin su alımı sonucunda çepere uyguladığı hidrostatik basınç',
        ),
        _t(
          'Plazmoliz',
          'Hipertonik ortamda su kaybeden bitki hücresinde protoplastın çeperden ayrılması',
        ),
        _t(
          'Fototropizma',
          'Bir organın yönlü ışık uyaranına karşı yönelimli büyüme göstermesi',
        ),
        _t(
          'Gravitropizma',
          'Bir organın yer çekimine göre yönelimli büyüme göstermesi',
        ),
        _t(
          'Vernalizasyon',
          'Uygun süre soğuğa maruz kalmanın bazı bitkilerde çiçeklenme yetkinliğini sağlaması',
        ),
        _t(
          'Dormansi',
          'Canlı tohumun başka bakımlardan elverişli koşullara karşın içsel nedenlerle hemen çimlenmemesi',
        ),
      ],
    ),
  ];
  for (final set in sets) {
    final pairs = <({int x, int y})>[];
    for (var gap = 1; gap < set.terms.length; gap++) {
      for (var x = 0; x + gap < set.terms.length; x++)
        pairs.add((x: x, y: x + gap));
    }
    yield AdvancedFamily(
      key: 'renew_life_concept_${set.key}',
      title: set.topic,
      level: set.level,
      topic: set.key == 'method'
          ? Topic.research
          : set.key == 'eco'
          ? Topic.nature
          : Topic.biology,
      lesson: 'Biyoloji',
      difficulty: Difficulty.medium,
      count: set.count,
      visualKind: _tab,
      bloom: BloomLevel.hatirlama,
      build: (i) {
        final p = pairs[i], one = set.terms[p.x], two = set.terms[p.y];
        final other = set.terms.firstWhere(
          (t) => t.term != one.term && t.term != two.term,
        );
        final v = _v(
          set.topic,
          ['Kod', 'Tanımlayıcı özellik'],
          [
            ['K', one.clue],
            ['L', two.clue],
          ],
        );
        return _choice(
          v,
          'K ve L tanımlarının karşılığı sırasıyla hangi iki kavramdır?',
          '${one.term} / ${two.term}',
          [
            '${two.term} / ${one.term}',
            '${other.term} / ${two.term}',
            '${one.term} / ${other.term}',
          ],
          'K tanımı ${one.term}, L tanımı ${two.term} kavramına karşılık gelir. K için ayırt edici özellik “${one.clue}”, L için “${two.clue}” olarak verilmiştir.',
        );
      },
    );
  }
}
