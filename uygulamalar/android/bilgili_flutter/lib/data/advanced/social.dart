// Social-science exercises. Figures in the teaching cases are simulated.
// Each coordinate changes evidence available to the student. The final
// block of an index selects a different question about the same case.
import 'common.dart';

String _sn(num n) {
  final rounded = (n * 100).round() / 100;
  if (rounded == rounded.truncateToDouble()) return rounded.toInt().toString();
  return rounded
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0$'), '')
      .replaceAll('.', ',');
}

QuestionVisual _table(
  String title,
  List<String> cols,
  List<List<Object>> data,
) => QuestionVisual(
  kind: VisualKind.table,
  title: title,
  summary: 'Öğretim amacıyla oluşturulmuş örnek veri.',
  columns: cols,
  rows: [
    for (final r in data) [for (final v in r) v is num ? _sn(v) : v.toString()],
  ],
);

AdvancedItem _number(
  String prompt,
  num value,
  List<num> choices,
  String unit,
  String why, {
  QuestionVisual? visual,
}) {
  String format(num n) => (unit == "%" || unit == "‰")
      ? "$unit${_sn(n)}"
      : '${_sn(n)}${unit.isEmpty ? "" : " $unit"}';
  final answer = format(value);
  final wrong = <String>{};
  // If two misconceptions coincide after rounding, take a nearby misreading.
  for (final c in [
    ...choices,
    value * 1.1 + 1,
    value * .9,
    value + 1,
    value + 2,
    value + 3,
    value + 4,
  ]) {
    if (format(c) != answer) wrong.add(format(c));
    if (wrong.length == 3) break;
  }
  final instruction = (value * 100 - (value * 100).round()).abs() > 0.0000001
      ? ' Sonucu virgülden sonra iki basamağa yuvarlayın.'
      : '';
  return AdvancedItem(
    prompt + instruction,
    answer,
    wrong.toList(),
    '$why Sonuç $answer.',
    visual: visual,
  );
}

typedef _Builder = AdvancedItem Function(int);
AdvancedFamily _family(
  String key,
  String title,
  Topic topic,
  bool university,
  _Builder build, {
  int count = 10000,
  bool table = true,
  VisualKind? kind,
  BloomLevel bloom = BloomLevel.uygulama,
  bool shortAnswer = true,
  CreationTask Function(AdvancedItem, int)? creation,
}) => AdvancedFamily(
  key: 'social_$key',
  title: title,
  topic: topic,
  level: university ? StudyLevel.universite : StudyLevel.lise,
  count: count,
  difficulty: university ? Difficulty.hard : Difficulty.medium,
  visualKind: kind ?? (table ? VisualKind.table : null),
  bloom: bloom,
  shortAnswer: shortAnswer,
  creation: creation,
  build: build,
);

class _Case {
  final int a, b, mode;
  _Case(int i) : a = i % 50, b = (i ~/ 50) % 50, mode = i ~/ 2500;
}

AdvancedItem _census(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final r0 = 800 + 12 * a, u0 = 1400 + 21 * b;
  final r1 = r0 + 6 * b - 3 * a, u1 = u0 + 13 * a + 2 * b + 15;
  final v = _table(
    'İki sayımda nüfus dağılımı',
    ['Sayım', 'Kırsal', 'Kentsel'],
    [
      ['İlk', r0, u0],
      ['Son', r1, u1],
    ],
  );
  switch (c.mode) {
    case 0:
      return _number(
        'Son sayımda nüfusun yüzde kaçı kentsel yerleşmelerde yaşıyor?',
        100 * u1 / (u1 + r1),
        [100 * r1 / (u1 + r1), 100 * u1 / r1, 100 * u0 / (r0 + u0)],
        '%',
        'Kentsel nüfus, aynı sayımın toplam nüfusuna bölünür: $u1 / ${u1 + r1} × 100.',
        visual: v,
      );
    case 1:
      return _number(
        'Kentsel nüfusun toplam içindeki payı ilk sayımdan son sayıma kaç yüzde puan değişmiştir? Azalmayı eksi işaretiyle gösterin.',
        100 * (u1 / (r1 + u1) - u0 / (r0 + u0)),
        [100 * (u1 / u0 - 1), 100 * (r1 / r0 - 1), 100 * (u1 - u0) / (r1 + u1)],
        'yüzde puan',
        'Son paydan ilk pay çıkarılır: 100 × ($u1 / ${u1 + r1} − $u0 / ${u0 + r0}).',
        visual: v,
      );
    case 2:
      return _number(
        'Sayım alanının sınırları aynı kaldı. İki sayım arasındaki toplam nüfus artışı ilk nüfusun yüzde kaçıdır?',
        100 * (r1 + u1 - r0 - u0) / (r0 + u0),
        [
          100 * (u1 / u0 - 1),
          100 * (r1 / r0 - 1),
          100 * (r1 + u1 - r0 - u0) / (r1 + u1),
        ],
        '%',
        'Kırsal ve kentsel nüfus her sayım için toplanır. Fark ilk toplam olan ${r0 + u0} kişiye bölünür.',
        visual: v,
      );
    default:
      return _number(
        'Kırsal nüfusun iki sayım arasındaki değişimi toplam nüfus artışına kaç kişilik katkı yapmıştır? Azalışı eksi değerle gösterin.',
        r1 - r0,
        [u1 - u0, r1 + u1 - r0 - u0, r0 - r1],
        'kişi',
        'Toplam nüfus değişiminin kırsal bileşeni son kırsal nüfus eksi ilk kırsal nüfustur: $r1 − $r0.',
        visual: v,
      );
  }
}

AdvancedItem _migration(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final birth = 210 + a, death = 120 + b, arr = 100 + 3 * b, dep = 95 + 2 * a;
  final start = 10200 + 10 * a + 14 * b;
  final v = _table(
    'Bir yıllık nüfus hesabı',
    ['Kayıt', 'Kişi'],
    [
      ['Yıl başı', start],
      ['Canlı doğum', birth],
      ['Ölüm', death],
      ['Gelen göç', arr],
      ['Giden göç', dep],
    ],
  );
  final nat = birth - death, net = arr - dep, total = nat + net;
  switch (c.mode) {
    case 0:
      return _number(
        'Kayıtların eksiksiz olduğu bu ilçede doğal artış ile net göç birlikte düşünüldüğünde yıl sonu nüfusu kaç kişidir?',
        start + total,
        [start + nat, start + net, start + nat - net],
        'kişi',
        'Doğal artış $nat, net göç $net kişidir. İkisi de yıl başı nüfusuna eklenir.',
        visual: v,
      );
    case 1:
      return _number(
        'Gelen ve giden kişi sayısı eşit olsaydı, yıl sonu nüfusu tabloda öngörülen nüfustan kaç kişi farklı olurdu? Varsayımsal değer eksi öngörülen değeri bulun.',
        -net,
        [net, nat, -total],
        'kişi',
        'Göç dengelendiğinde doğal artış aynı kalır ve net göç sıfır olur. Fark 0 − ($arr − $dep) olarak bulunur.',
        visual: v,
      );
    case 2:
      return _number(
        'Toplam net nüfus değişiminin yıl başı nüfusuna oranı binde kaçtır?',
        1000 * total / start,
        [1000 * nat / start, 1000 * net / start, 100 * total / start],
        '‰',
        'Doğal artış ile net göçün toplamı $total kişidir. $total / $start × 1000 hesaplanır.',
        visual: v,
      );
    default:
      return _number(
        'Bütün göç kayıtlarında kaç hareket vardır? Bir geliş ve bir gidiş iki ayrı hareket kabul ediliyor.',
        arr + dep,
        [net.abs(), total, birth + death],
        'hareket',
        'Brüt göç hareketi gelen ve giden kayıtların toplamıdır: $arr + $dep.',
        visual: v,
      );
  }
}

AdvancedItem _ages(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final child = 125 + 3 * a, work = 630 + 2 * b, old = 65 + b;
  final v = _table(
    'Yaş yapısı',
    ['Yaş grubu', 'Kişi'],
    [
      ['0–14', child],
      ['15–64', work],
      ['65+', old],
    ],
  );
  final all = child + work + old;
  switch (c.mode) {
    case 0:
      return _number(
        'Her 100 çalışma çağındaki kişiye kaç genç ve yaşlı düşüyor? Yaşa bağlı toplam bağımlılık oranını bulun.',
        100 * (child + old) / work,
        [100 * (child + old) / all, 100 * old / work, 100 * child / work],
        'kişi',
        'Genç ve yaşlı grupları toplanır, 15–64 yaş grubuna bölünür ve 100 ile çarpılır.',
        visual: v,
      );
    case 1:
      return _number(
        'Her 100 çocuğa düşen 65 yaş ve üstü kişi sayısı kaçtır?',
        100 * old / child,
        [100 * old / all, 100 * child / old, 100 * old / work],
        'kişi',
        'Yaşlanma endeksi, 65 yaş ve üstü nüfusun 0–14 yaş nüfusuna oranının 100 katıdır.',
        visual: v,
      );
    case 2:
      return _number(
        'Yaş bakımından bağımlı kabul edilen iki grubun içinde çocukların payı yüzde kaçtır?',
        100 * child / (child + old),
        [100 * child / all, 100 * child / work, 100 * old / (child + old)],
        '%',
        'Payda, yalnızca 0–14 ve 65+ yaş gruplarının toplamı olan ${child + old} kişidir.',
        visual: v,
      );
    default:
      return _number(
        'Çalışma çağındaki nüfusun toplam nüfusa oranı yüzde kaçtır?',
        100 * work / all,
        [
          100 * work / (old + child),
          100 * child / all,
          100 * (child + old) / work,
        ],
        '%',
        '15–64 yaş grubundaki $work kişi, toplam $all kişiye bölünür ve sonuç 100 ile çarpılır.',
        visual: v,
      );
  }
}

AdvancedItem _land(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final area = 125 + 2 * a,
      farm = 55 + b,
      n = 4000 + 13 * b + 9 * a,
      fam = 150 + b + a;
  final v = _table(
    'İlçenin arazi ve nüfus kaydı',
    ['Gösterge', 'Değer'],
    [
      ['Toplam alan (km²)', area],
      ['Ekili alan (km²)', farm],
      ['Toplam nüfus', n],
      ['Tarımla geçinen nüfus', fam],
    ],
  );
  switch (c.mode) {
    case 0:
      return _number(
        'İlçenin aritmetik nüfus yoğunluğu km² başına kaç kişidir?',
        n / area,
        [n / farm, fam / farm, fam / area],
        'kişi/km²',
        'Toplam nüfus toplam yüzölçümüne bölünür: $n / $area.',
        visual: v,
      );
    case 1:
      return _number(
        'Bu uygulamada fizyolojik yoğunluk toplam nüfusun ekili alana oranı olarak tanımlanıyor. Bu yoğunluk kaçtır?',
        n / farm,
        [n / area, fam / farm, farm / n],
        'kişi/km²',
        'Pay toplam nüfus, payda yalnızca ekili alandır: $n / $farm.',
        visual: v,
      );
    case 2:
      return _number(
        'Ekili alanın her kilometrekaresine tarımla geçinen kaç kişi düşüyor?',
        fam / farm,
        [n / farm, fam / area, n / area],
        'kişi/km²',
        'Tarımla geçinen $fam kişi, $farm km² ekili alana bölünür.',
        visual: v,
      );
    default:
      return _number(
        'Ekili alanın toplam yüzölçümündeki payı yüzde kaçtır?',
        100 * farm / area,
        [100 * (area - farm) / area, 100 * fam / n, 100 * area / farm],
        '%',
        'Arazi payı $farm / $area × 100 değeridir.',
        visual: v,
      );
  }
}

AdvancedItem _contour(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final base = 450 + 5 * a, climb = 110 + 3 * b, run = 1200 + 40 * a;
  final next = base + climb, step = 10 + (a % 5) * 5, dist = 800 + 20 * b;
  final v = _table(
    'Yamaç boyunca örnek yükselti kesiti',
    ['Nokta', 'Yatay uzaklık (m)', 'Yükselti (m)'],
    [
      ['P', 0, base],
      ['R', run, next],
      ['S', run + dist, next + step * 4],
    ],
  );
  switch (c.mode) {
    case 0:
      return _number(
        'P–R arasında ortalama eğim yüzde kaçtır?',
        100 * climb / run,
        [100 * next / run, 100 * climb / (run + dist), 100 * 4 * step / dist],
        '%',
        'Yükselti farkı $climb m, yatay uzaklık $run m. Yüzde eğim bu iki büyüklüğün oranının 100 katıdır.',
        visual: v,
      );
    case 1:
      return _number(
        'P ve S arasındaki bütün kesitin ortalama eğimi yüzde kaçtır?',
        100 * (climb + 4 * step) / (run + dist),
        [
          100 * climb / run,
          100 * 4 * step / dist,
          100 * (climb + 4 * step) / run,
        ],
        '%',
        'İki uç arasındaki yükselti farkı ${climb + 4 * step} m, yatay uzaklık ${run + dist} m’dir.',
        visual: v,
      );
    case 2:
      return _number(
        'R–S arasındaki ortalama eğim, P–R arasındakinden kaç yüzde puan farklıdır? R–S değerinden P–R değerini çıkarın.',
        100 * (4 * step / dist - climb / run),
        [
          100 * 4 * step / dist,
          100 * climb / run,
          100 * (climb / run - 4 * step / dist),
        ],
        'yüzde puan',
        'Her kesim için yükselti farkını kendi yatay uzunluğuna bölüp 100 ile çarpın. Sonra ikinci kesimin eğiminden ilkini çıkarın.',
        visual: v,
      );
    default:
      return _number(
        'P–R boyunca eğimin sabit olduğu kabul edilirse P’den R’ye yatay mesafenin dörtte üçü geçildiğinde yükselti kaç metredir?',
        base + .75 * climb,
        [.75 * next, base + .25 * climb, next + step],
        'm',
        'Başlangıç yükseltisine yükselti farkının dörtte üçü eklenir: $base + 0,75 × $climb.',
        visual: v,
      );
  }
}

AdvancedItem _map(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final denominator = 20000 + 1000 * a, cm = (25 + b) / 10;
  final detour = 10 + (a + b) % 26;
  final km = denominator * cm / 100000;
  final stem =
      '1:$denominator ölçekli bir topoğrafya haritasında iki köy merkezi arasındaki düz çizgi ${_sn(cm)} cm. ';
  final road = km * (1 + detour / 100);
  switch (c.mode) {
    case 0:
      return _number(
        '${stem}Köyler arasındaki yatay kuş uçuşu uzaklığı kaç kilometredir?',
        km,
        [km * 10, km / 10, km * 2],
        'km',
        'Harita uzunluğu ölçeğin paydasıyla çarpılıp santimetreden kilometreye çevrilir.',
      );
    case 1:
      return _number(
        '${stem}Vadiden geçen yol kuş uçuşu uzaklıktan %$detour uzunsa yolun uzunluğu kaç kilometredir?',
        road,
        [km, km * (1 - detour / 100), km + detour / 100],
        'km',
        'Önce kuş uçuşu uzaklık ${_sn(km)} km bulunur. Bu değer 1 + $detour/100 ile çarpılır.',
      );
    case 2:
      return _number(
        '${stem}Köyler arasındaki aynı yatay uzaklık 1:25000 ölçekli ikinci bir haritada kaç santimetre olur?',
        cm * denominator / 25000,
        [cm * 25000 / denominator, cm, km / 25],
        'cm',
        'Gerçek uzunluk ${_sn(cm)} × $denominator santimetredir. İkinci haritada bu uzunluk 25000’e bölünür.',
      );
    default:
      return _number(
        '${stem}Köy merkezlerini birleştiren doğru, kare bir etüt alanının bir kenarıdır. Alan gerçekte kaç kilometrekaredir?',
        km * km,
        [km, 4 * km, km * km / 2],
        'km²',
        'Gerçek kenar ${_sn(km)} km’dir. Kare alan için kenar uzunluğunun karesi alınır.',
      );
  }
}

AdvancedItem _climate(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final valley = 120 + 5 * a,
      summit = 1600 + 10 * b,
      t = 20 + a % 9,
      rate = (45 + (a + b) % 26) / 100;
  final lapse = rate * (summit - valley) / 100;
  final stem =
      'Bir saha modelinde yükseklik her 100 m arttığında sıcaklık ${_sn(rate)} °C düşüyor. Vadide ($valley m) sıcaklık $t °C, zirve $summit m. ';
  switch (c.mode) {
    case 0:
      return _number(
        '${stem}Modelin zirve için öngördüğü sıcaklık kaç derecedir?',
        t - lapse,
        [t + lapse, lapse, t - rate * summit / 100],
        '°C',
        'İki noktanın yükseklik farkı ${summit - valley} m’dir. Bu yükselmenin soğutucu etkisi vadi sıcaklığından çıkarılır.',
      );
    case 1:
      return _number(
        '${stem}Zirvedeki termometre model tahmininden 1,5 °C daha yüksek gösterirse ölçülen sıcaklık kaç derecedir?',
        t - lapse + 1.5,
        [t - lapse - 1.5, t + lapse + 1.5, t - lapse],
        '°C',
        'Vadi sıcaklığından yükselmenin etkisi çıkarılır ve ölçüm sapması olan 1,5 °C eklenir.',
      );
    case 2:
      return _number(
        '${stem}Vadi ve zirve yükseltilerinin tam ortasında modelin tahmini kaç derecedir?',
        t - lapse / 2,
        [t - lapse, t + lapse / 2, (t - lapse) / 2],
        '°C',
        'Sabit sıcaklık gradyanında yükselti farkının yarısı, tam farkın yarısı kadar soğuma üretir.',
      );
    default:
      return _number(
        '${stem}Modelde zirveden vadiye inişte toplam sıcaklık artışı kaç derecedir?',
        lapse,
        [t - lapse, rate * summit / 100, rate * valley / 100],
        '°C',
        'Yükselti farkı ${summit - valley} m, her 100 m için sıcaklık değişimi ${_sn(rate)} °C’dir.',
      );
  }
}

String _clockTime(int minutes) {
  final m = minutes % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}.${(m % 60).toString().padLeft(2, '0')}';
}

AdvancedItem _solar(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final west = 5 + a,
      east = 6 + b,
      t = 480 + (a + b) % 120,
      delta = 4 * (west + east);
  final v = QuestionVisual(
    kind: VisualKind.diagram,
    title: 'Örnek meridyen şeması',
    summary: 'Batı solda, doğu sağdadır. Çizim ölçekli değildir.',
    elements: [
      for (final x in [15.0, 50.0, 85.0])
        DiagramElement(shape: 'line', x: x, y: 23, endX: x, endY: 83),
      DiagramElement(shape: 'text', x: 15, y: 13, label: 'A · $west° B'),
      const DiagramElement(shape: 'text', x: 50, y: 13, label: '0°'),
      DiagramElement(shape: 'text', x: 85, y: 13, label: 'B · $east° D'),
    ],
  );
  if (c.mode < 2) {
    final first = c.mode == 0, offset = first ? delta : -delta;
    final from = first ? 'A' : 'B', to = first ? 'B' : 'A';
    final answer = _clockTime(t + offset);
    final candidates = [
      t - offset,
      t + offset ~/ 4,
      t - offset ~/ 4,
      t,
      t + offset + 4,
    ];
    return AdvancedItem(
      '$from noktasında yerel ortalama güneş saati ${_clockTime(t)} iken aynı anda $to noktasında kaçtır?',
      answer,
      candidates
          .map(_clockTime)
          .where((e) => e != answer)
          .toSet()
          .take(3)
          .toList(),
      'Boylam farkı ${east + west}° olduğundan saat farkı ${east + west} × 4 = $delta dakikadır. Doğudaki noktanın yerel saati ileridir.',
      visual: v,
    );
  }
  if (c.mode == 2)
    return _number(
      'İki istasyonda yerel ortalama güneş öğleleri arasında kaç dakika vardır?',
      delta,
      [(east - west).abs() * 4, east + west, delta / 2],
      'dakika',
      'Başlangıç meridyeninin iki yanındaki boylamlar toplanır. Her derece 4 dakika fark oluşturur.',
      visual: v,
    );
  return _number(
    'A ile B arasındaki boylam yayının orta meridyeninde ortalama güneş öğlesi, A noktasından kaç dakika önce yaşanır?',
    delta / 2,
    [delta, (east - west).abs() * 2, (east + west) / 2],
    'dakika',
    'Orta meridyen, A noktasının ${_sn((east + west) / 2)}° doğusundadır. Bu fark derece başına 4 dakika ile çarpılır.',
    visual: v,
  );
}

AdvancedItem _agriculture(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final h1 = 60 + a, h2 = 80 + b, y1 = 2100 + 10 * b, y2 = 2400 + 12 * a;
  final p1 = h1 * y1, p2 = h2 * y2;
  final v = _table(
    'Buğday üretimi',
    ['Ova', 'Ekili alan (ha)', 'Hasat (kg)'],
    [
      ['Kuzey', h1, p1],
      ['Güney', h2, p2],
    ],
  );
  switch (c.mode) {
    case 0:
      return _number(
        'İki ova tek bir üretim alanı olarak ele alınırsa hektar başına ortalama verim nedir?',
        (p1 + p2) / (h1 + h2),
        [(y1 + y2) / 2, y1, y2],
        'kg/ha',
        'Toplam hasat ${p1 + p2} kg, toplam alan ${h1 + h2} hektardır. Ağırlıklar hektar sayılarıdır.',
        visual: v,
      );
    case 1:
      return _number(
        'Kuzey Ovası’nda verim Güney Ovası’nın verimine ulaşsaydı, aynı ekili alanda kuzeydeki hasat kaç kilogram değişirdi? Artışı pozitif alın.',
        h1 * (y2 - y1),
        [h2 * (y2 - y1), (p2 - p1), h1 * (y1 - y2)],
        'kg',
        'Hektar başına fark $y2 − $y1 kg’dır. Yalnızca kuzeyin $h1 hektarlık alanı hesaba katılır.',
        visual: v,
      );
    case 2:
      return _number(
        'Güney Ovası iki ovanın toplam hasadının yüzde kaçını karşılamıştır?',
        100 * p2 / (p1 + p2),
        [100 * h2 / (h1 + h2), 100 * p1 / (p1 + p2), 100 * p2 / p1],
        '%',
        'Güneydeki hasat toplam hasada bölünür: $p2 / ${p1 + p2} × 100.',
        visual: v,
      );
    default:
      return _number(
        'Kuzey Ovası’nın 5 hektarı üretimden çıkıp Güney Ovası’na aynı miktarda ekili alan eklenirse ve her ovanın verimi korunursa toplam üretim nasıl değişir? Azalışı eksi gösterin.',
        5 * (y2 - y1),
        [5 * (y1 - y2), 5 * y1, 5 * y2],
        'kg',
        'Kuzeyde kaybedilen 5 × $y1 kg ile güneydeki 5 × $y2 kg üretim artışı birlikte değerlendirilir.',
        visual: v,
      );
  }
}

AdvancedItem _basin(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final rain = 180 + 2 * a,
      inflow = 65 + b,
      evap = 75 + (a + 2 * b) % 40,
      out = 75 + (2 * a + b) % 45;
  final balance = rain + inflow - evap - out;
  final v = QuestionVisual(
    kind: VisualKind.barChart,
    title: 'Bir gölün aylık su bütçesi',
    summary: 'Varsayımsal kayıtta tüm akımlar aynı göl yüzeyine göre mm su yüksekliği olarak verilmiştir.',
    labels: const ['Yağış', 'Giren akım', 'Buharlaşma', 'Çıkan akım'],
    values: [
      for (final x in [rain, inflow, evap, out]) x.toDouble(),
    ],
    unit: 'mm',
  );
  switch (c.mode) {
    case 0:
      return _number(
        'Başka giriş veya kayıp yoksa ay sonunda depolanan su yüksekliğindeki net değişim kaç mm olur?',
        balance,
        [rain - evap, inflow - out, rain + inflow],
        'mm',
        'Yağış ve giren akım toplanır, buharlaşma ile çıkan akım çıkarılır: $rain + $inflow − $evap − $out.',
        visual: v,
      );
    case 1:
      return _number(
        'Toplam su girdisinin yüzde kaçı doğrudan göle düşen yağıştan gelmiştir?',
        100 * rain / (rain + inflow),
        [
          100 * inflow / (rain + inflow),
          100 * rain / (evap + out),
          100 * rain / inflow,
        ],
        '%',
        'Doğrudan yağış $rain mm, toplam girdi ${rain + inflow} mm’dir.',
        visual: v,
      );
    case 2:
      return _number(
        'Diğer üç akım sabit kalırken depolamanın hiç değişmemesi için çıkan akım kaç mm olmalıydı?',
        rain + inflow - evap,
        [out, balance, rain - evap],
        'mm',
        'Sıfır depolama değişimi için çıkışlar girdilere eşit olmalıdır. Gerekli çıkan akım $rain + $inflow − $evap değeridir.',
        visual: v,
      );
    default:
      return _number(
        'Buharlaşma kaybı dörtte bir azalırken diğer akımlar aynı kalırsa depolama değişimi kaç mm olur?',
        balance + evap / 4,
        [balance - evap / 4, balance * 1.25, balance + out / 4],
        'mm',
        'Buharlaşma kaybındaki azalma ${_sn(evap / 4)} mm’dir. Bu miktar ilk net değişime eklenir.',
        visual: v,
      );
  }
}

AdvancedItem _wages(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final w0 = 80 + a, w1 = 110 + b, p0 = 4 + (a % 8), p1 = 5 + (b % 8);
  final v = _table(
    'Örnek tarihî ücret defteri',
    ['Dönem', 'Gündelik (akçe)', 'Tahıl (akçe/kg)'],
    [
      ['I', w0, p0],
      ['II', w1, p1],
    ],
  );
  final r0 = w0 / p0, r1 = w1 / p1;
  switch (c.mode) {
    case 0:
      return _number(
        'Bir gündelikle alınabilen tahıl miktarı ikinci dönemde birinci döneme göre kaç kg değişmiştir? Azalışı eksi gösterin.',
        r1 - r0,
        [r0 - r1, (w1 - w0) / p1, w1 / p0 - w0 / p1],
        'kg',
        'Her dönemin ücreti kendi tahıl fiyatına bölünür. İkinci dönemin miktarından birincininki çıkarılır.',
        visual: v,
      );
    case 1:
      return _number(
        'Tahıl cinsinden reel gündelik endeksi birinci dönemde 100 alınırsa ikinci dönemde kaç olur?',
        100 * r1 / r0,
        [100 * w1 / w0, 100 * p1 / p0, 100 * r0 / r1],
        '',
        'Reel gündelikler $w0/$p0 ve $w1/$p1 kg’dır. Son değerin ilk değere oranı 100 ile çarpılır.',
        visual: v,
      );
    case 2:
      return _number(
        'İlk dönemdeki gündeliğin tahıl alım gücünü ikinci dönemde tam olarak koruyacak gündelik kaç akçedir?',
        r0 * p1,
        [w1, w0 * p0 / p1, r1 * p0],
        'akçe',
        'İlk gündeliğin alabildiği ${_sn(r0)} kg tahıl ikinci dönemin kg fiyatıyla değerlendirilir. Hesapta ara değer yuvarlanmaz.',
        visual: v,
      );
    default:
      return _number(
        'İki dönemde de birer gün çalışan biri kazancının tamamını o dönemin fiyatıyla tahıla harcarsa toplam kaç kg alır?',
        r0 + r1,
        [(w0 + w1) / (p0 + p1), 2 * r0, 2 * r1],
        'kg',
        'İki satın alma ayrı ayrı hesaplanır: $w0/$p0 + $w1/$p1.',
        visual: v,
      );
  }
}

AdvancedItem _archive(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final lo = 1450 + 2 * a, hi = lo + 4 + b;
  final v = _table(
    'Tarihsiz bir yazma için örnek kanıt dosyası',
    ['Kanıt', 'Tarihleme bilgisi'],
    [
      [
        'Metindeki olay',
        'Olay $lo yılında gerçekleşti. Metin olaydan sonraki bir takvim yılında yazıldı.',
      ],
      [
        'Katalog kaydı',
        'Metnin tamamı $hi yılı başlamadan önce kayda geçirilmişti.',
      ],
    ],
  );
  final earliest = lo + 1, last = hi - 1;
  switch (c.mode) {
    case 0:
      return AdvancedItem(
        'Her iki kayda göre yazımın mümkün olduğu en dar takvim yılı aralığı hangisidir?',
        '$earliest–$last',
        ['$lo–$hi', '$earliest–$hi', '$lo–$last'],
        'Yazım olayla aynı yılda olamaz. Katalog kaydı $hi yılını da dışarıda bırakır. İki koşulun kesişimi $earliest–$last aralığıdır.',
        visual: v,
      );
    case 1:
      return _number(
        'Her iki kanıt da doğruysa kaç farklı takvim yılı yazım yılı olabilir?',
        hi - lo - 1,
        [hi - lo, hi - lo + 1, hi - lo - 2],
        'yıl',
        'Alt ve üst sınırların ikisi de dışlanır. Uygun tam yılların sayısı $hi − $lo − 1 olur.',
        visual: v,
      );
    case 2:
      final middle = (lo + hi) ~/ 2;
      return AdvancedItem(
        'Ayrı bir tanık, metnin $middle yılı sona ermeden tamamlandığını söylüyor. Bu tanık da güvenilir sayılırsa aralık nasıl daralır?',
        '$earliest–$middle',
        ['$lo–$middle', '${middle + 1}–$last', '$earliest–${middle - 1}'],
        'Yeni kayıt en geç $middle yılında yazılmış olmayı gerektirir. En erken yıl $earliest olarak kalır.',
        visual: v,
      );
    default:
      final after = lo + (hi - lo) ~/ 2;
      return AdvancedItem(
        'Metindeki başka bir olayın $after yılında gerçekleştiği ve yazımın bu olaydan sonraki bir takvim yılında tamamlandığı doğrulandı. Hangi aralık savunulabilir?',
        '${after + 1}–$last',
        ['$after–$hi', '$earliest–$after', '$after–$last'],
        'En yeni olay alt sınırı ${after + 1} yılına taşır. Katalog kaydı nedeniyle üst sınır $last olarak kalır.',
        visual: v,
      );
  }
}

AdvancedItem _standard(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final ny = 1000 + 100 * (a % 7),
      no = 800 + 100 * (b % 5),
      ry = 4 + a,
      ro = 35 + b;
  final py = 35 + (a + 2 * b) % 31;
  final v = _table(
    'Yaşa göre olay sıklığı',
    ['Yaş', 'Gözlenen nüfus', '1000 kişide olay', 'Standart pay (%)'],
    [
      ['18–49', ny, ry, py],
      ['50+', no, ro, 100 - py],
    ],
  );
  final adjusted = (ry * py + ro * (100 - py)) / 100,
      crude = (ry * ny + ro * no) / (ny + no);
  switch (c.mode) {
    case 0:
      return _number(
        'Doğrudan yaş standardizasyonuna göre örnek grubun olay hızı binde kaçtır?',
        adjusted,
        [crude, (ry + ro) / 2, (ry * (100 - py) + ro * py) / 100],
        '‰',
        'Her grubun olaya özgü hızı standart nüfustaki payıyla çarpılır: ($ry × $py + $ro × ${100 - py}) / 100.',
        visual: v,
      );
    case 1:
      return _number(
        'Verilen yaşa özgü hızları gözlenen nüfusun yaş dağılımıyla ağırlıklandırınca kaba hız binde kaç olur?',
        crude,
        [adjusted, (ry + ro) / 2, ry + ro],
        '‰',
        'Gözlenen gruplar $ny ve $no kişidir. Kaba hız ($ny × $ry + $no × $ro) / ${ny + no} olarak hesaplanır.',
        visual: v,
      );
    case 2:
      return _number(
        'Standart nüfus 100000 kişiden oluşsaydı, iki yaş grubunda toplam kaç olay beklenirdi?',
        100 * adjusted,
        [100 * crude, 10 * adjusted, 100 * (ry + ro)],
        'olay',
        'Ağırlıklı binde hız ${_sn(adjusted)} olur. 100000 kişi, biner kişilik 100 birim içerir.',
        visual: v,
      );
    default:
      return _number(
        'Standart nüfusta 50+ yaş grubunun payı 10 yüzde puan artıp genç grubun payı aynı ölçüde azalırsa standartlaştırılmış hız binde kaç puan değişir?',
        (ro - ry) / 10,
        [(ry - ro) / 10, (ro + ry) / 10, (ro - ry)],
        'bindelik puan',
        'Nüfus ağırlığının 0,10’u gençlerden ileri yaşa aktarılır. Hız değişimi 0,10 × ($ro − $ry) olur.',
        visual: v,
      );
  }
}

AdvancedItem _did(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final t0 = 175 + a,
      k0 = 130 + b,
      dk = (2 * b + a) % 30 - 8,
      dt = (a + 2 * b) % 40 - 9;
  final t1 = t0 + dt, k1 = k0 + dk;
  final v = _table(
    'Ulaşım yatırımı ve iş erişimi',
    ['Bölge', 'Önce', 'Sonra'],
    [
      ['Yatırım alan', t0, t1],
      ['Karşılaştırma', k0, k1],
    ],
  );
  final stem =
      'Değerler, bir mahalleden 30 dakikada erişilebilen ortalama işyeri sayısıdır. ';
  switch (c.mode) {
    case 0:
      return _number(
        '${stem}İki dönemli farkların farkı tahmini kaç işyeridir?',
        dt - dk,
        [dt, t1 - k1, dk - dt],
        'işyeri',
        'Yatırım alan bölgenin değişiminden karşılaştırma bölgesinin değişimi çıkarılır: ($t1 − $t0) − ($k1 − $k0).',
        visual: v,
      );
    case 1:
      return _number(
        '${stem}Paralel eğilim varsayımında, yatırım yapılmasaydı yatırım alan bölgede son dönemde kaç işyerine erişim beklenirdi?',
        t0 + dk,
        [t1, k1, t0 - dk],
        'işyeri',
        'Karşılaştırma bölgesindeki $dk birimlik değişim, yatırım bölgesinin başlangıç düzeyine eklenir.',
        visual: v,
      );
    case 2:
      return _number(
        '${stem}Yalnızca son dönem düzey farkını kullanmak, farkların farkı tahminini sayısal olarak kaç birim aşar? Son dönem farkından farkların farkını çıkarın.',
        t0 - k0,
        [t1 - k1, dt - dk, k0 - t0],
        'işyeri',
        'Son dönem grup farkı, başlangıç grup farkı ile farkların farkının toplamıdır. Aranan değer $t0 − $k0 olur.',
        visual: v,
      );
    default:
      return _number(
        '${stem}Aynı aylarda yalnızca yatırım alan bölgede başka bir programın erişimi ayrıca 6 işyeri artırdığı biliniyor. Etkiler toplamsalsa yatırımla ilişkilendirilen düzeltilmiş farkların farkı kaçtır?',
        dt - dk - 6,
        [dt - dk + 6, dt - dk, dt - 6],
        'işyeri',
        'Ortak dönem değişimi karşılaştırma bölgesinden alınır. Yatırım bölgesine özgü diğer katkı ayrıca çıkarılır: $dt − ($dk) − 6.',
        visual: v,
      );
  }
}

AdvancedItem _location(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final local = 2200 + 20 * a,
      total = 60000 + 100 * b,
      sector = 280 + 5 * b,
      ref = 10000 + 50 * a;
  final v = _table(
    'Turizm istihdamı',
    ['Alan', 'Tüm çalışanlar', 'Turizmde çalışanlar'],
    [
      ['İlçe', local, sector],
      ['Referans bölge', total, ref],
    ],
  );
  final refShare = ref / total, share = sector / local, lq = share / refShare;
  switch (c.mode) {
    case 0:
      return _number(
        'İlçenin turizm için yerelleşme katsayısı (LQ) kaçtır?',
        lq,
        [1 / lq, sector / ref, share * 100],
        '',
        'İlçe sektör payı ($sector/$local), referans sektör payına ($ref/$total) bölünür.',
        visual: v,
      );
    case 1:
      return _number(
        'Referans bölgedeki sektör payı ilçede aynen geçerli olsaydı ilçede turizm istihdamı kaç kişi olurdu? En yakın tam sayıya yuvarlayın.',
        (local * refShare).round(),
        [
          sector,
          (local * share).round(),
          (total * share).round(),
          (local * refShare * 2).round(),
        ],
        'kişi',
        'İlçe istihdamı $local, referans payı $ref/$total ile çarpılır ve sonuç yuvarlanır.',
        visual: v,
      );
    case 2:
      return _number(
        'İlçedeki sektör payı ile referans bölgedeki sektör payı arasındaki fark kaç yüzde puandır? İlçe eksi referans sırasını kullanın.',
        100 * (share - refShare),
        [100 * (refShare - share), 100 * share, 100 * refShare],
        'yüzde puan',
        'İki pay ayrı ayrı hesaplanır. İlçe payından referans payı çıkarılıp 100 ile çarpılır.',
        visual: v,
      );
    default:
      return _number(
        'İlçede turizm istihdamı aynı kalırken diğer sektörlere 200 çalışan eklenirse, tablodaki sabit referans oranıyla yeni LQ kaç olur?',
        sector / (local + 200) / refShare,
        [
          lq,
          (sector + 200) / (local + 200) / refShare,
          sector / (local - 200) / refShare,
        ],
        '',
        'Referans payı sabit tutulur. Yeni ilçe sektör payı $sector/${local + 200} olur ve referans payına bölünür.',
        visual: v,
      );
  }
}

AdvancedItem _strata(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final n1 = 1500 + 20 * a,
      n2 = 2400 + 25 * b,
      r1 = 18 + (a + 2 * b) % 32,
      r2 = 38 + (2 * a + b) % 32;
  final v = _table(
    'Tabakalı erişim araştırması',
    ['Tabaka', 'Evren (hane)', 'Örneklem (hane)', 'Erişimi olan (%)'],
    [
      ['Merkez', n1, 100, r1],
      ['Çevre', n2, 100, r2],
    ],
  );
  final weighted = (n1 * r1 + n2 * r2) / (n1 + n2), simple = (r1 + r2) / 2;
  switch (c.mode) {
    case 0:
      return _number(
        'Her tabakada basit rastgele seçim yapıldı. Erişimi olan hanelerin evrendeki yüzdesi tasarım ağırlıklarıyla kaç olarak tahmin edilir?',
        weighted,
        [simple, r1, r2],
        '%',
        'Tabaka yüzdeleri kendi evren ağırlıklarıyla birleştirilir: ($n1 × $r1 + $n2 × $r2) / ${n1 + n2}.',
        visual: v,
      );
    case 1:
      return _number(
        'Evren büyüklükleri göz ardı edilerek iki tabaka ortalaması eşit ağırlıklandırılırsa sonuç, tasarıma uygun tahminden kaç yüzde puan farklı çıkar? Eşit ağırlıklı eksi tasarım ağırlıklı değeri bulun.',
        simple - weighted,
        [weighted - simple, weighted, simple],
        'yüzde puan',
        'İki tabakanın eşit ağırlıklı ortalaması ${_sn(simple)}, evren paylarıyla ağırlıklı tahmin ${_sn(weighted)} değerindedir. Yuvarlama en son yapılır.',
        visual: v,
      );
    case 2:
      return _number(
        'Araştırmaya göre evren genelinde erişimi olan toplam hane sayısı yaklaşık kaçtır? En yakın tam sayıyı bulun.',
        ((n1 * r1 + n2 * r2) / 100).round(),
        [
          ((n1 + n2) * simple / 100).round(),
          (n1 * r1 / 100).round(),
          (n2 * r2 / 100).round(),
        ],
        'hane',
        'Her tabaka evreni kendi erişim oranıyla çarpılır. İki tahmin toplanır ve en yakın haneye yuvarlanır.',
        visual: v,
      );
    default:
      return _number(
        'Yeni turda 400 hane evren büyüklükleriyle orantılı dağıtılacak. Merkez tabakasına en yakın tam sayıyla kaç hane ayrılır?',
        (400 * n1 / (n1 + n2)).round(),
        [(400 * n2 / (n1 + n2)).round(), 200, (400 * r1 / (r1 + r2)).round()],
        'hane',
        'Orantılı tahsis erişim oranına göre değil, evren ağırlığına göre yapılır: 400 × $n1 / ${n1 + n2}.',
        visual: v,
      );
  }
}

AdvancedItem _missing(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final n = 350 + a, miss = 40 + b, yes = 105 + a + (b ~/ 2);
  final known = n - miss, no = known - yes;
  final v = _table(
    'Bir panelde ikinci tur görüşmeleri',
    ['Sonuç', 'Katılımcı'],
    [
      ['Destekliyor', yes],
      ['Desteklemiyor', no],
      ['Yanıt yok', miss],
    ],
  );
  final lower = 100 * yes / n, upper = 100 * (yes + miss) / n;
  switch (c.mode) {
    case 0:
      return _number(
        'Yanıtsızlar hakkında varsayım yapılmadan, tüm paneldeki destek yüzdesi için mümkün olan en küçük değer kaçtır?',
        lower,
        [upper, 100 * yes / known, 100 * miss / n],
        '%',
        'Alt sınırda yanıtsızların hiçbiri desteklemez. Pay $yes, payda tüm panel olan $n kişidir.',
        visual: v,
      );
    case 1:
      return _number(
        'Yanıt vermeyenlerin tamamının desteğe katılması mümkünse, ilk panelin tümü için destek oranının keskin üst sınırı yüzde kaçtır?',
        upper,
        [lower, 100 * yes / known, 100 * (yes + miss) / known],
        '%',
        'Üst sınırda $miss yanıtsız kişinin hepsi $yes destekçiye eklenir. Payda $n olarak değişmeden kalır.',
        visual: v,
      );
    case 2:
      return _number(
        'Yanıtsızlara ilişkin hiçbir varsayım yapılmadığında destek oranının üst ve alt sınırları arasındaki aralık kaç yüzde puandır?',
        upper - lower,
        [100 * miss / known, 100 * yes / n, 100 * no / n],
        'yüzde puan',
        'Üst ve alt sınırı birbirinden ayıran tek grup yanıtsızlardır. Genişlik $miss/$n × 100 değeridir.',
        visual: v,
      );
    default:
      return _number(
        'Yalnızca yanıt verenlerin destek oranı, bütün panel için varsayımsız alt sınırdan kaç yüzde puan yüksektir?',
        100 * yes / known - lower,
        [upper - lower, 100 * yes / known, lower],
        'yüzde puan',
        'Yanıt verenlere göre payda $known, alt sınırda ise $n kişidir. Pay her iki hesapta $yes olarak kalır.',
        visual: v,
      );
  }
}

AdvancedItem _cohort(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final first = 450 + 2 * a,
      second = first - 40 - b,
      third = second - 25 - (2 * a + b) % 48;
  final v = QuestionVisual(
    kind: VisualKind.lineChart,
    title: 'Aynı öğrencilerin üç dalgada izlenmesi',
    summary: 'Örnek panel kapalıdır. Ayrılanlar geri dönmemiş, yeni kişi alınmamıştır.',
    labels: const ['1. dalga', '2. dalga', '3. dalga'],
    values: [first.toDouble(), second.toDouble(), third.toDouble()],
    unit: 'kişi',
  );
  switch (c.mode) {
    case 0:
      return _number(
        'Başlangıç grubunun yüzde kaçı üçüncü dalgada hâlâ gözlenmektedir?',
        100 * third / first,
        [
          100 * third / second,
          100 * second / first,
          100 * (first - third) / first,
        ],
        '%',
        'Üçüncü dalgada kalan $third öğrenci başlangıçtaki $first öğrenciye bölünür.',
        visual: v,
      );
    case 1:
      return _number(
        'İkinci dalgada hâlâ gözlenen bir öğrencinin üçüncü dalgadan önce panelden ayrılma oranı yüzde kaçtır?',
        100 * (second - third) / second,
        [
          100 * (second - third) / first,
          100 * (first - third) / first,
          100 * third / second,
        ],
        '%',
        'İkinci aralıkta ${second - third} öğrenci ayrılmıştır. Bu aralığın başlangıç risk kümesi $second kişidir.',
        visual: v,
      );
    case 2:
      return _number(
        'Üçüncü dalgaya kadar gözlemden çıkanların yüzde kaçı ilk iki dalga arasında ayrılmıştır?',
        100 * (first - second) / (first - third),
        [
          100 * (first - second) / first,
          100 * (second - third) / (first - third),
          100 * second / first,
        ],
        '%',
        'Pay ilk aralıktaki ${first - second} kayıp, payda iki aralıktaki toplam ${first - third} kayıptır.',
        visual: v,
      );
    default:
      return _number(
        'İkinci aralıktaki koşullu kalma oranı aynen sürseydi dördüncü dalgada beklenen öğrenci sayısı yaklaşık kaç olurdu? En yakın tam sayıya yuvarlayın.',
        (third * third / second).round(),
        [
          (third * third / first).round(),
          third - (first - second),
          third - (second - third),
        ],
        'öğrenci',
        'Son koşullu kalma oranı $third/$second olarak hesaplanır ve üçüncü dalganın $third öğrencisine uygulanır.',
        visual: v,
      );
  }
}

AdvancedItem _mobility(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final ll = 75 + a,
      lh = 36 + b,
      hl = 27 + (a + 2 * b) % 30,
      hh = 88 + (2 * a + b) % 48,
      all = ll + lh + hl + hh;
  final v = _table(
    'İki kuşakta yükseköğrenimi tamamlama',
    ['Ebeveyn', 'Çocuk tamamlamadı', 'Çocuk tamamladı'],
    [
      ['Tamamlamadı', ll, lh],
      ['Tamamladı', hl, hh],
    ],
  );
  switch (c.mode) {
    case 0:
      return _number(
        'Ebeveyni yükseköğrenimi tamamlamayan grubun içinde çocukların tamamlama oranı yüzde kaçtır?',
        100 * lh / (ll + lh),
        [100 * lh / (lh + hh), 100 * lh / all, 100 * hh / (hl + hh)],
        '%',
        'Koşul ebeveynin eğitimine ilişkindir. İlk satırdaki $lh çocuk, ilk satır toplamı ${ll + lh} sayısına bölünür.',
        visual: v,
      );
    case 1:
      return _number(
        'Yükseköğrenimi tamamlayan çocukların içinde ebeveyni de tamamlamış olanların oranı yüzde kaçtır?',
        100 * hh / (lh + hh),
        [100 * hh / (hl + hh), 100 * hh / all, 100 * lh / (lh + hh)],
        '%',
        'Koşul çocukların tamamlama durumudur. Tamamlayanlar sütununda ebeveyni de tamamlamış $hh kişi vardır.',
        visual: v,
      );
    case 2:
      return _number(
        'İkili eğitim sınıflamasında ebeveyninden farklı düzeyde olan çocukların toplam içindeki payı yüzde kaçtır?',
        100 * (lh + hl) / all,
        [100 * (ll + hh) / all, 100 * lh / all, 100 * hl / all],
        '%',
        'İki kuşağın farklı olduğu hücreler köşegenin dışındadır. Bu hücrelerde $lh + $hl kişi yer alır.',
        visual: v,
      );
    default:
      return _number(
        'Çocuğun yükseköğrenimi tamamlama odds’u, ebeveyni tamamlamış olanlarda ebeveyni tamamlamamış olanların kaç katıdır?',
        hh * ll / (hl * lh),
        [(hh / (hh + hl)) / (lh / (lh + ll)), hl * lh / (hh * ll), hh / lh],
        'kat',
        'Odds, tamamlayan sayısının tamamlamayan sayısına oranıdır. Odds oranı ($hh/$hl) / ($lh/$ll) olur.',
        visual: v,
      );
  }
}

AdvancedItem _prices(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final p01 = 10 + a, p02 = 8 + b, p11 = p01 + 2 + b % 7, p12 = p02 + 1 + a % 5;
  final q01 = 14 + (2 * a + b) % 10,
      q02 = 6 + (a + b) % 6,
      q11 = q01 - 4,
      q12 = q02 + 5;
  final v = _table(
    'İki mallı tarihsel pazar sepeti',
    ['Kayıt', 'Buğday', 'Arpa'],
    [
      ['Baz fiyat (akçe/kg)', p01, p02],
      ['Son fiyat (akçe/kg)', p11, p12],
      ['Baz miktar (kg)', q01, q02],
      ['Son miktar (kg)', q11, q12],
    ],
  );
  final old = p01 * q01 + p02 * q02,
      current = p11 * q11 + p12 * q12,
      newOnOld = p11 * q01 + p12 * q02,
      oldOnNew = p01 * q11 + p02 * q12;
  final las = 100 * newOnOld / old, paas = 100 * current / oldOnNew;
  switch (c.mode) {
    case 0:
      return _number(
        'Baz yıl 100 iken baz dönemin miktarları sabit tutularak hesaplanan Laspeyres fiyat endeksi kaçtır?',
        las,
        [paas, 100 * current / old, 100 * old / newOnOld],
        '',
        'Baz sepetin son fiyatlarla maliyeti $newOnOld, baz fiyatlarla maliyeti $old akçedir. Oran 100 ile çarpılır.',
        visual: v,
      );
    case 1:
      return _number(
        'Son dönem sepetini ağırlık olarak kullanan Paasche fiyat endeksi baz yıl 100 iken kaçtır?',
        paas,
        [las, 100 * current / old, 100 * oldOnNew / current],
        '',
        'Son miktarlar iki fiyat vektörüyle değerlendirilir. Endeks 100 × $current / $oldOnNew olur.',
        visual: v,
      );
    case 2:
      return _number(
        'Miktarlar baz sepetindeki gibi kalsaydı yalnızca fiyat değişimi toplam harcamayı kaç akçe artırırdı?',
        newOnOld - old,
        [current - old, current - oldOnNew, oldOnNew - old],
        'akçe',
        'Sabit sepetin yeni ve eski maliyetleri çıkarılır: $newOnOld − $old.',
        visual: v,
      );
    default:
      return _number(
        'Her iki mal baz dönemin fiyatlarıyla değerlendirilirse miktar değişiminden kaynaklanan toplam harcama farkı kaç akçedir? Son eksi baz sırasını kullanın.',
        oldOnNew - old,
        [current - old, newOnOld - old, current - oldOnNew],
        'akçe',
        'Baz fiyatlarıyla son sepet $oldOnNew, baz sepet $old akçe eder. Yalnız miktarlar değişmiştir.',
        visual: v,
      );
  }
}

AdvancedItem _inequality(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final low = 15 + a,
      mid = 75 + b,
      high = 190 + (2 * a + b) % 75,
      total = low + mid + high;
  final v = _table(
    'Eşit büyüklükte üç gelir grubu',
    ['Üçte birlik dilim', 'Kişi başı aylık gelir (birim)'],
    [
      ['Alt', low],
      ['Orta', mid],
      ['Üst', high],
    ],
  );
  final g = 2 * (high - low) / (3 * total);
  switch (c.mode) {
    case 0:
      return _number(
        'Her grup içinde herkes aynı geliri alıyor. Lorenz eğrisinin nüfusun ilk üçte ikisine karşılık gelen noktasında birikimli gelir payı yüzde kaçtır?',
        100 * (low + mid) / total,
        [100 * high / total, 100 * low / total, 100 * mid / total],
        '%',
        'Grupların nüfusları eşit olduğundan ilk iki ortalamanın toplamı üç ortalamanın toplamına bölünür.',
        visual: v,
      );
    case 1:
      return _number(
        'Grup içi gelirler eşit kabul edilirse bu dağılımın 0–1 ölçeğindeki nüfus Gini katsayısı kaçtır?',
        g,
        [1 - g, g / 2, 1.5 * g],
        '',
        'Eşit ağırlıklı üç gelir için Gini, üç ikili mutlak farkın toplamının üç gelirin toplamının üç katına oranıdır. Farkların toplamı 2 × ($high − $low) olur.',
        visual: v,
      );
    case 2:
      return _number(
        'Üst dilimdeki herkesten 5 birim alınıp alt dilimdeki herkese 5 birim verilirse, gruplar eşit büyüklükteyken alt dilimin gelir payı kaç yüzde puan artar?',
        500 / total,
        [500 / low, 500 / (low + 5), 1000 / total],
        'yüzde puan',
        'Aktarım toplam geliri değiştirmez. Eşit büyüklükteki gruplarda alt dilimin payı 5 / $total kadar artar.',
        visual: v,
      );
    default:
      return _number(
        'Her bireye aynı miktarda 10 gelir birimi eklendiğinde, üst üçte birin toplam gelirdeki yeni payı yüzde kaçtır?',
        100 * (high + 10) / (total + 30),
        [
          100 * high / total,
          100 * (high + 10) / (total + 10),
          100 * high / (total + 30),
        ],
        '%',
        'Üç grubun kişi başı geliri de 10 artar. Üst dilimin yeni geliri ${high + 10}, üç ortalamanın yeni toplamı ${total + 30} olur.',
        visual: v,
      );
  }
}

AdvancedItem _texts(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final n1 = 12000 + 100 * a,
      n2 = 18000 + 150 * b,
      t1 = 32 + 2 * b,
      t2 = 41 + 2 * a;
  final v = _table(
    'İki döneme ait örnek gazete derlemi',
    ['Dönem', 'Toplam sözcük', 'Hedef sözcük'],
    [
      ['Erken', n1, t1],
      ['Geç', n2, t2],
    ],
  );
  final r1 = 10000 * t1 / n1, r2 = 10000 * t2 / n2;
  switch (c.mode) {
    case 0:
      return _number(
        'Hedef sözcüğün 10000 sözcük başına sıklığı geç dönemde erken döneme göre kaç birim değişmiştir? Azalışı eksi gösterin.',
        r2 - r1,
        [r1 - r2, t2 - t1, (r2 + r1) / 2],
        'kullanım',
        'Her sayı kendi derleminin büyüklüğüne bölünüp 10000 ile çarpılır. Geç dönem sıklığından erken dönem sıklığı çıkarılır.',
        visual: v,
      );
    case 1:
      return _number(
        'Derlemler tek bir metin havuzunda birleştirilirse 10000 sözcükte kaç hedef sözcük görülür?',
        10000 * (t1 + t2) / (n1 + n2),
        [(r1 + r2) / 2, r1 + r2, 10000 * t2 / (n1 + n2)],
        'kullanım',
        'Toplam hedef sözcük sayısı ${t1 + t2}, toplam havuz uzunluğu ${n1 + n2} sözcüktür. Önce toplamlar alınır.',
        visual: v,
      );
    case 2:
      return _number(
        'Geç derlemdeki hedef sözcük oranı erken derlemdekiyle aynı olsaydı geç derlemde beklenen hedef sözcük sayısı kaç olurdu? En yakın tam sayıyı bulun.',
        (n2 * t1 / n1).round(),
        [t1, t2, (n1 * t2 / n2).round()],
        'kullanım',
        'Erken dönem oranı $t1/$n1, geç derlemin $n2 sözcüklük uzunluğuna uygulanır.',
        visual: v,
      );
    default:
      return _number(
        'Derlem uzunlukları hesaba katıldığında geç dönemin hedef sözcük sıklığı erken dönemin kaç katıdır?',
        r2 / r1,
        [t2 / t1, r1 / r2, n2 / n1],
        'kat',
        'Normalize edilmiş sıklık oranı ($t2/$n2) / ($t1/$n1) biçiminde hesaplanır.',
        visual: v,
      );
  }
}

AdvancedItem _overlap(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final first = 130 + a, second = 165 + b, common = 45 + (a + b) % 29;
  final union = first + second - common, estimated = first * second / common;
  final v = _table(
    'İki yazımın eşleştirilmesi',
    ['Arşiv bilgisi', 'Kayıtlı kişi'],
    [
      ['A listesindeki farklı kişi', first],
      ['B listesindeki farklı kişi', second],
      ['İki listede de görünen', common],
    ],
  );
  switch (c.mode) {
    case 0:
      return _number(
        'Her liste kendi içinde tekilleştirilmişse en az bir listede görülen kaç farklı kişi vardır?',
        union,
        [first + second, first + second - 2 * common, common],
        'kişi',
        'İki listede bulunan $common kişi toplamada iki kez sayıldığı için bir kez çıkarılır.',
        visual: v,
      );
    case 1:
      return _number(
        'Kapalı bir evren, kişi başına eşit kayıt olasılığı ve iki kayıt işleminin bağımsızlığı varsayılıyor. Lincoln–Petersen yöntemiyle nüfus tahmini kaç kişidir? En yakın tam sayıya yuvarlayın.',
        estimated.round(),
        [union, first + second, (first * second / union).round()],
        'kişi',
        'İkinci listedeki tekrar oranı $common/$second, ilk listenin evrendeki payını tahmin eder. Evren tahmini $first × $second / $common olur.',
        visual: v,
      );
    case 2:
      return _number(
        'Bu iki liste için Jaccard benzerliği, ortak kişilerin birleşimdeki tüm kişilere oranıdır. Yüzde olarak kaçtır?',
        100 * common / union,
        [
          100 * common / first,
          100 * common / second,
          100 * common / (first + second),
        ],
        '%',
        'Kesişim $common, birleşim $union kişidir. Çakışma oranı $common/$union × 100 olur.',
        visual: v,
      );
    default:
      return _number(
        'Bağımsız, eşit yakalama olasılıklı iki kayıt varsayımıyla Lincoln–Petersen tahmini kullanıldığında, iki listede de görünmeyen kaç kişi öngörülür? En yakın tam sayıyı bulun.',
        (estimated - union).round(),
        [estimated.round(), union, first + second - 2 * common],
        'kişi',
        'Tahmini evren $first × $second / $common kişidir. Bu tahminden gözlenen birleşim olan $union kişi çıkarılır.',
        visual: v,
      );
  }
}

AdvancedItem _boundsReview(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final yesA = 28 + a,
      yesB = 28 + b,
      mA = 3 + (2 * b + a) % 10,
      mB = 4 + (2 * a + b) % 9;
  final v = _table(
    'İki yerde aynı soruya verilen yanıtlar',
    ['Yer', 'Evet', 'Hayır', 'Bilinmiyor'],
    [
      ['A', yesA, 100 - yesA - mA, mA],
      ['B', yesB, 100 - yesB - mB, mB],
    ],
  );
  if (c.mode == 0) {
    const opts = [
      'A’nın oranı kesinlikle daha yüksektir.',
      'B’nin oranı kesinlikle daha yüksektir.',
      'Oranların eşit olması zorunludur.',
      'Tek bir kesin sıralama yapılamaz.',
    ];
    final pick = yesA > yesB + mB
        ? 0
        : yesB > yesA + mA
        ? 1
        : 3;
    return AdvancedItem(
      'Her yerde 100 kişinin tamamı tabloda. Bilinmeyen yanıtların tüm mümkün dağılımlarını hesaba kattığınızda evet oranlarının sıralaması için hangi değerlendirme savunulabilir?',
      opts[pick],
      [
        for (var j = 0; j < 4; j++)
          if (j != pick) opts[j],
      ],
      'A için mümkün oranlar %$yesA ile %${yesA + mA}, B için %$yesB ile %${yesB + mB} arasındadır. Kesin üstünlük ancak aralıklar birbiriyle kesişmediğinde kurulabilir.',
      visual: v,
    );
  }
  const opts = [
    'İddia zorunlu olarak doğrudur.',
    'İddia mümkün, fakat zorunlu değildir.',
    'İddia hiçbir dağılımda sağlanamaz.',
    'İki yerin büyüklükleri verilmeden değerlendirilemez.',
  ];
  final lo = yesA - yesB - mB, hi = yesA + mA - yesB;
  final pick = lo >= 10
      ? 0
      : hi < 10
      ? 2
      : 1;
  return AdvancedItem(
    'Bir rapor “A’nın evet oranı B’ninkinden en az 10 yüzde puan yüksektir” diyor. Her yerde 100 kişi olduğuna göre eksik yanıtların etkisini de içeren değerlendirme hangisidir?',
    opts[pick],
    [
      for (var j = 0; j < 4; j++)
        if (j != pick) opts[j],
    ],
    'A eksi B farkı en az $lo, en çok $hi yüzde puan olabilir. İddia tüm olasılıklarda geçerliyse alt sınır en az 10 olmalıdır. En iyi durumda bile 10’a ulaşılmıyorsa iddia olanaksızdır.',
    visual: v,
  );
}

AdvancedItem _fieldDesign(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final n1 = 250 + 5 * a, n2 = 400 + 7 * b, budget = 90 + (a + b) % 36;
  final v = _table(
    'Saha araştırması için örnek çerçeve',
    ['Tabaka', 'Hane', 'Beklenen yanıt (%)'],
    [
      ['Kıyı', n1, 75],
      ['İç kesim', n2, 50],
    ],
  );
  final target = (budget * n1 / (n1 + n2)).round(), other = budget - target;
  if (c.mode == 0) {
    return AdvancedItem(
      'Kıyı ve iç kesimde toplu taşımaya erişimi ölçeceksiniz. Her tabakada güncel hane listesi var. $budget tamamlanmış görüşme nüfus büyüklüklerine orantılı paylaştırılacak. Kıyı hedefini en yakın tam sayıya yuvarlayıp kalanını iç kesime ayırırsanız plan nasıl başlamalı?',
      'Kıyı $target, iç kesim $other tamamlanmış görüşme',
      [
        'Kıyı ${target + 1}, iç kesim ${other - 1} tamamlanmış görüşme',
        'Kıyı ${target - 1}, iç kesim ${other + 1} tamamlanmış görüşme',
        'Kıyı ${target + 2}, iç kesim ${other - 2} tamamlanmış görüşme',
      ],
      'Kıyı hedefi $budget × $n1 / ${n1 + n2} değerinin en yakın tam sayısıdır. Tamamlanmış görüşmeler ile davetler ayrı planlanır.',
      visual: v,
    );
  }
  // Ask for the invitation plan, not a promise about realised contacts.
  final inv1 = (target / .75).ceil(), inv2 = (other / .50).ceil();
  return AdvancedItem(
    'Toplu taşımaya erişim araştırması $budget tamamlanmış görüşme hedefliyor. Hane sayılarına orantılı tahsiste kıyı hedefini en yakın tam sayıya yuvarlayın, kalanını iç kesime verin. Beklenen yanıt oranlarına göre davetleri her tabakada yukarı yuvarlayınca hangi davet planı çıkar?',
    'Kıyı $inv1, iç kesim $inv2 davet',
    [
      'Kıyı $target, iç kesim $other davet',
      'Kıyı $inv1, iç kesim $other davet',
      'Kıyı $target, iç kesim $inv2 davet',
    ],
    'Tamamlanmış görüşme hedefleri $target ve $other olur. Tabakaya özgü davetler sırasıyla $target / 0,75 ve $other / 0,50 değerlerinin yukarı yuvarlanmasıyla bulunur.',
    visual: v,
  );
}

CreationTask _fieldTask(AdvancedItem item, int i) {
  final c = _Case(i),
      a = c.a,
      b = c.b,
      n1 = 250 + 5 * a,
      n2 = 400 + 7 * b,
      budget = 90 + (a + b) % 36;
  final deliverable = c.mode == 0
      ? 'Her tabaka için hedef görüşme sayısını gösteren bir tahsis çizelgesi hazırlayın.'
      : 'Her tabaka için davet sayısı ve ulaşılamayan haneler için yeniden temas takvimi hazırlayın.';
  return CreationTask(
    'Kıyıda $n1, iç kesimde $n2 haneli bir evrende toplu taşımaya erişimi karşılaştırmak için yöntem tasarlayın. $budget tamamlanmış görüşme hedefleniyor. Kıyıda beklenen yanıt %75, iç kesimde %50. Gösterge, seçim, sayı ve veri toplama kararlarınızı gerekçelendirin. $deliverable',
    [
      'Erişimi, örneğin konuttan durağa yürüme süresi gibi iki bölgede aynı şekilde ölçülebilen bir göstergeyle tanımlamak.',
      'Her tabakada güncel listeden olasılıklı hane seçimi tarif etmek. Tamamlanma hedeflerini hane sayılarına orantılı, davet sayılarını beklenen yanıta göre planlamak.',
      'Yanıtsızları kaydetmek, farklı saatlerde geri arama yapmak ve kalan yanıt farklılığının karşılaştırmaya olası etkisini tartışmak.',
    ],
  );
}

const _sources = [
  [
    'belediye su dağıtım defteri',
    'su bağlantısı',
    'su ücreti makbuzu',
    'mahalle',
  ],
  ['lonca üyelik defteri', 'lonca üyeliği', 'aidat makbuzu', 'esnaf grubu'],
  ['liman yük defteri', 'yükleme işlemi', 'navlun makbuzu', 'emtia türü'],
  ['vakıf kira defteri', 'kiralama işlemi', 'kira makbuzu', 'mülk türü'],
  ['okul kayıt defteri', 'öğrenci kaydı', 'sınav yoklama listesi', 'sınıf'],
  ['belediye ruhsat defteri', 'ruhsat işlemi', 'harç makbuzu', 'iş kolu'],
  ['kütüphane ödünç defteri', 'ödünç işlemi', 'iade fişi', 'eser türü'],
  ['matbaa sipariş defteri', 'baskı siparişi', 'teslim tutanağı', 'yayın türü'],
  ['kooperatif teslim defteri', 'ürün teslimi', 'tartım fişi', 'ürün türü'],
  [
    'ambar giriş defteri',
    'ambarda giriş işlemi',
    'tesellüm belgesi',
    'mal türü',
  ],
];
AdvancedItem _archiveDesign(int i) {
  final c = _Case(i), a = c.a, b = c.b;
  final src = _sources[(a + b) % _sources.length];
  final early = 75 + a,
      late = 82 + b,
      me = 4 + (a + 2 * b) % 14,
      ml = 6 + (a + b) % 15;
  final v = _table(
    'Arşiv denetimi için örnek dosya',
    ['Dönem', 'Okunan sayfa', 'Eksik sayfa', 'Gözlenen işlem'],
    [
      ['Erken', early, me, early * 2 + b],
      ['Geç', late, ml, late * 2 + a],
    ],
  );
  if (c.mode == 0) {
    final e = 100 * me / (early + me), l = 100 * ml / (late + ml);
    final choice = e > l
        ? 'Erken dönemde'
        : e < l
        ? 'Geç dönemde'
        : 'İki dönemde aynı oranda';
    final opts = [
      'Erken dönemde',
      'Geç dönemde',
      'İki dönemde aynı oranda',
      'Okunan sayfa sayısı bilinmediği için belirlenemez',
    ];
    return AdvancedItem(
      'Bir ${src[0]} inceleniyor. Kaynak karşılaştırması tasarımında korunma yanlılığını denetlemek için önce eksik sayfa oranına bakılıyor. Hangi dönemde bu oran daha yüksektir? Eşitse eşitliği işaretleyin.',
      choice,
      opts.where((e) => e != choice).toList(),
      'Eksiklik oranı eksik sayfaların beklenen tüm sayfalara oranıdır. Erken dönem %${_sn(e)}, geç dönem %${_sn(l)}. Bu oran tek başına kayıp işlemlerin sayısını vermez.',
      visual: v,
    );
  }
  final earlyCount = early * 2 + b, lateCount = late * 2 + a;
  return _number(
    'Bir ${src[0]} için korunmuş sayfa başına işlem sıklığı karşılaştırılacak. Geç dönemin sıklığı erken dönemin kaç katıdır? Bu göstergeyi kayıp sayfaların içeriği için tahmin saymayın.',
    (lateCount / late) / (earlyCount / early),
    [
      lateCount / earlyCount,
      late / early,
      (earlyCount / early) / (lateCount / late),
    ],
    'kat',
    'Okunabilen kayıtlardaki yoğunluklar $lateCount/$late ve $earlyCount/$early değerleridir. Bunların oranı yalnızca korunmuş sayfaları betimler.',
    visual: v,
  );
}

CreationTask _archiveTask(AdvancedItem item, int i) {
  final c = _Case(i),
      a = c.a,
      b = c.b,
      src = _sources[(a + b) % _sources.length];
  final early = 75 + a,
      late = 82 + b,
      me = 4 + (a + 2 * b) % 14,
      ml = 6 + (a + b) % 15;
  final deliverable = c.mode == 0
      ? 'Kayıp sayfa oranlarını ve bunları denetleyecek karşılaştırmayı içeren bir kaynak denetim tablosu oluşturun.'
      : 'Korunmuş sayfa başına işlem sıklığını raporlayacak bir kodlama formu ve ikinci diziyle bir eşleştirme şeması oluşturun.';
  return CreationTask(
    'İki dönemde ${src[1]} sıklığının değiştiği iddiasını sınamak için bir arşiv araştırma protokolü yazın. Bir ${src[0]} için erken dönemde $early okunabilir, $me eksik sayfa var. Geç dönemde $late okunabilir, $ml eksik sayfa var. Ayrı bir ${src[2]} dizisine erişiminiz bulunuyor. ${src[3]} değişkenini tasarımınıza katın. $deliverable',
    [
      'Kayıt birimini, zaman aralığını, mükerrer kayıt kuralını ve iki dönem için ortak karşılaştırma paydasını belirlemek.',
      'Birincil defter ile ikinci diziyi eşleştirmek için tarih, ayırt edici kimlik ve denetlenebilir bir eşleşme kuralı önermek. İkinci dizinin bağımsızlığını sınamak.',
      'Eksik sayfaların ve ${src[3]} bileşiminin dönem farkını nasıl etkileyebileceğini belirtmek. Sonucun hangi koşullarda açık kalacağını açıklamak.',
    ],
  );
}

// Dates denote point events, including a specified start, signature or publication.
typedef _Event = (int, String);
const _periods = <List<_Event>>[
  [
    (1302, "Koyunhisar Savaşı"),
    (1326, "Bursa'nın Osmanlılarca alınması"),
    (1331, "İznik'in Osmanlılarca alınması"),
    (1337, "İzmit'in Osmanlılarca alınması"),
    (1389, "Birinci Kosova Savaşı"),
    (1396, "Niğbolu Savaşı"),
    (1402, "Ankara Savaşı"),
    (1413, "Çelebi Mehmed'in Fetret Devri'ne son vermesi"),
    (1444, "Varna Savaşı"),
    (1448, "İkinci Kosova Savaşı"),
    (1453, "İstanbul'un II. Mehmed tarafından fethedilmesi"),
    (1461, "Trabzon'un Fatih Sultan Mehmed tarafından alınması"),
    (1473, "Otlukbeli Savaşı"),
    (1481, "II. Bayezid'in tahta çıkması"),
    (1512, "Yavuz Sultan Selim'in tahta çıkması"),
    (1514, "Çaldıran Savaşı"),
    (1516, "Mercidabık Savaşı"),
    (1517, "Ridaniye Savaşı"),
    (1521, "Belgrad'ın Kanuni Sultan Süleyman tarafından alınması"),
    (1522, "Rodos'un Kanuni Sultan Süleyman tarafından alınması"),
    (1526, "Mohaç Savaşı"),
    (1529, "Kanuni Sultan Süleyman'ın Viyana'yı kuşatması"),
    (1538, "Preveze Deniz Savaşı"),
    (1555, "Amasya Antlaşması"),
    (1566, "Zigetvar Seferi"),
    (1571, "İnebahtı Deniz Savaşı"),
    (1596, "Haçova Savaşı"),
    (1606, "Zitvatorok Antlaşması"),
    (1638, "Bağdat'ın IV. Murad tarafından geri alınması"),
    (1639, "Kasr-ı Şirin Antlaşması"),
    (1664, "Vasvar Antlaşması"),
    (1669, "Kandiye'nin Osmanlılara teslimi"),
    (1672, "Bucaş Antlaşması"),
    (1683, "İkinci Viyana Kuşatması"),
    (1699, "Karlofça Antlaşması"),
    (1711, "Prut Antlaşması"),
    (1718, "Pasarofça Antlaşması"),
    (1730, "Patrona Halil İsyanı"),
    (1739, "Belgrad Antlaşması"),
    (1774, "Küçük Kaynarca Antlaşması"),
    (1792, "Yaş Antlaşması"),
    (1808, "Sened-i İttifak'ın imzalanması"),
    (1826, "Yeniçeri Ocağı'nın kaldırılması"),
    (1829, "Edirne Antlaşması"),
    (1839, "Tanzimat Fermanı'nın ilanı"),
    (1856, "Islahat Fermanı'nın ilanı"),
    (1876, "Birinci Meşrutiyet'in ilanı"),
    (1878, "Berlin Antlaşması"),
    (1881, "Düyûn-ı Umûmiye İdaresinin kuruluşu"),
    (1908, "İkinci Meşrutiyet'in ilanı"),
    (1912, "Uşi Antlaşması"),
    (1918, "Mondros Mütarekesi"),
  ],
  [
    (1911, "Trablusgarp Savaşı'nın başlaması"),
    (1912, "Birinci Balkan Savaşı'nın başlaması"),
    (1913, "Bâbıâli Baskını"),
    (1914, "Osmanlı Devleti'nin Birinci Dünya Savaşı'na girmesi"),
    (1915, "Çanakkale'de 18 Mart Deniz Zaferi"),
    (1918, "Mondros Mütarekesi'nin imzalanması"),
    (1919, "Sivas Kongresi'nin toplanması"),
    (1920, "Türkiye Büyük Millet Meclisinin açılması"),
    (1921, "Sakarya Meydan Muharebesi"),
    (1922, "Mudanya Mütarekesi"),
    (1923, "Türkiye Cumhuriyeti'nin ilanı"),
    (1924, "Halifeliğin kaldırılması"),
    (1925, "Aşar vergisinin kaldırılması"),
    (1926, "Türk Medeni Kanunu'nun kabul edilmesi"),
    (1927, "Mustafa Kemal Atatürk'ün Nutuk'u okuması"),
    (1928, "Yeni Türk harflerinin kabul edilmesi"),
    (1930, "Kadınlara belediye seçimlerine katılma hakkı verilmesi"),
    (1931, "Türk Tarihi Tetkik Cemiyetinin kurulması"),
    (1932, "Türkiye'nin Milletler Cemiyetine katılması"),
    (1933, "İstanbul Üniversitesinin Darülfünun'un yerine kurulması"),
    (1934, "Soyadı Kanunu'nun kabul edilmesi"),
    (1936, "Montrö Boğazlar Sözleşmesi"),
    (1937, "Sadabat Paktı'nın imzalanması"),
    (1938, "İsmet İnönü'nün cumhurbaşkanı seçilmesi"),
    (1939, "Hatay'ın Türkiye'ye katılması"),
    (1940, "Köy Enstitüleri Kanunu'nun kabul edilmesi"),
    (1946, "Demokrat Partinin kurulması"),
    (1950, "Demokrat Partinin genel seçimleri kazanarak iktidara gelmesi"),
    (1952, "Türkiye'nin NATO'ya katılması"),
    (1963, "Türkiye ile AET arasında Ankara Anlaşması'nın imzalanması"),
    (1973, "İstanbul'da Boğaziçi Köprüsü'nün açılması"),
    (1999, "Türkiye'nin Helsinki Zirvesi'nde AB'ye aday ülke ilan edilmesi"),
  ],
  [
    (800, "Şarlman'ın Roma'da imparatorluk tacı giymesi"),
    (843, "Verdun Antlaşması"),
    (1066, "Hastings Savaşı"),
    (
      1095,
      "Papa II. Urbanus'un Clermont Konsili'nde Haçlı Seferi çağrısı yapması",
    ),
    (1099, "Birinci Haçlı Seferi'nde Kudüs'ün ele geçirilmesi"),
    (1204, "Dördüncü Haçlı Seferi'nde Konstantinopolis'in ele geçirilmesi"),
    (1215, "Magna Carta'nın kabul edilmesi"),
    (1337, "Yüz Yıl Savaşları'nın başlaması"),
    (1453, "Yüz Yıl Savaşları'nın sona ermesi"),
    (1492, "Gırnata Emirliği'nin sona ermesi"),
    (1517, "Martin Luther'in Doksan Beş Tez ile anılan çıkışı"),
    (1555, "Augsburg Din Barışı"),
    (1588, "İspanyol Armadası'nın İngiltere seferi"),
    (1618, "Otuz Yıl Savaşları'nın başlaması"),
    (1648, "Vestfalya Barışı"),
    (1688, "İngiltere'de Şanlı Devrim'in başlaması"),
    (1689, "İngiltere'de Haklar Bildirgesi'nin kabulü"),
    (
      1707,
      "İngiltere ile İskoçya'nın Büyük Britanya Krallığı çatısı altında birleşmesi",
    ),
    (1713, "Utrecht Barışı'nın ilk antlaşmalarının imzalanması"),
    (1756, "Yedi Yıl Savaşı'nın başlaması"),
    (1789, "Bastille Baskını"),
    (1799, "Napolyon Bonapart'ın 18 Brumaire Darbesi"),
    (1804, "Napolyon Bonapart'ın imparatorluk tacı giymesi"),
    (1815, "Waterloo Savaşı"),
    (1830, "Fransa'da Temmuz Devrimi"),
    (1848, "Fransa'da İkinci Cumhuriyet'in ilanı"),
    (1853, "Kırım Savaşı'nın başlaması"),
    (1861, "İtalya Krallığı'nın ilanı"),
    (1871, "Alman İmparatorluğu'nun Versailles'da ilanı"),
    (1884, "Afrika'nın paylaşımını görüşen Berlin Konferansı'nın başlaması"),
    (1914, "Birinci Dünya Savaşı'nın başlaması"),
    (1917, "Rusya'da Ekim Devrimi"),
    (1919, "Versailles Antlaşması'nın imzalanması"),
    (1922, "Sovyetler Birliği'nin kurulması"),
    (1936, "İspanya İç Savaşı'nın başlaması"),
    (1939, "Almanya'nın Polonya'yı işgal etmesi"),
    (1945, "Almanya'nın İkinci Dünya Savaşı'nda teslim olması"),
    (1949, "NATO'nun kurulması"),
    (1955, "Varşova Paktı'nın kurulması"),
    (
      1957,
      "Avrupa Ekonomik Topluluğu'nu kuran Roma Antlaşması'nın imzalanması",
    ),
    (1961, "Berlin Duvarı'nın inşasına başlanması"),
    (1968, "Prag Baharı"),
    (1989, "Berlin Duvarı'ndaki geçişlerin açılması"),
    (1990, "Doğu ve Batı Almanya'nın birleşmesi"),
    (1991, "Sovyetler Birliği'nin dağılması"),
    (1993, "Maastricht Antlaşması'nın yürürlüğe girmesi"),
  ],
  [
    (1492, "Kristof Kolomb'un ilk Atlantik seferinde Karayipler'e ulaşması"),
    (1498, "Vasco da Gama'nın deniz yoluyla Hindistan'a ulaşması"),
    (1519, "Macellan'ın dünya çevresindeki seferinin başlaması"),
    (1522, "Elcano'nun dünya çevresindeki seferi tamamlaması"),
    (1607, "İngiltere'nin Virginia'da Jamestown yerleşimini kurması"),
    (1620, "Mayflower gemisinin Kuzey Amerika'ya varması"),
    (1773, "Boston Çay Partisi"),
    (1776, "Amerikan Bağımsızlık Bildirgesi'nin kabul edilmesi"),
    (1787, "ABD Anayasası'nın Philadelphia'da imzalanması"),
    (1791, "Saint-Domingue'de Haiti Devrimi'ni başlatan ayaklanma"),
    (1804, "Haiti'nin bağımsızlığını ilan etmesi"),
    (1821, "Meksika'nın bağımsızlığını kazanması"),
    (1822, "Brezilya'nın Portekiz'den bağımsızlığını ilan etmesi"),
    (1842, "Birinci Afyon Savaşı'nı bitiren Nanking Antlaşması"),
    (1861, "Amerikan İç Savaşı'nın başlaması"),
    (1865, "Abraham Lincoln'e suikast düzenlenmesi"),
    (1868, "Japonya'da Meiji Restorasyonu"),
    (1869, "Süveyş Kanalı'nın açılması"),
    (1888, "Brezilya'da köleliği kaldıran Altın Yasa'nın kabulü"),
    (1898, "İspanya-Amerika Savaşı"),
    (1903, "Panama'nın Kolombiya'dan ayrılması"),
    (1910, "Meksika Devrimi'nin başlaması"),
    (1911, "Çin'de Xinhai Devrimi'nin başlaması"),
    (1914, "Panama Kanalı'nın açılması"),
    (1929, "New York Borsası'nda Büyük Buhran'la anılan çöküş"),
    (1930, "Gandi'nin Tuz Yürüyüşü"),
    (1941, "Pearl Harbor Baskını"),
    (1945, "Birleşmiş Milletler Antlaşması'nın yürürlüğe girmesi"),
    (1947, "Hindistan ile Pakistan'ın Britanya yönetiminden bağımsızlaşması"),
    (1948, "İnsan Hakları Evrensel Bildirgesi'nin kabul edilmesi"),
    (1949, "Çin Halk Cumhuriyeti'nin ilanı"),
    (1950, "Kore Savaşı'nın başlaması"),
    (1953, "Kore Ateşkes Anlaşması"),
    (1959, "Fidel Castro'nun öncülük ettiği Küba Devrimi'nin zafere ulaşması"),
    (1962, "Küba Füze Krizi"),
    (
      1963,
      "Martin Luther King'in Washington'da “Bir Hayalim Var” konuşmasını yapması",
    ),
    (1969, "Apollo 11 astronotlarının Ay'a inmesi"),
    (1975, "Saygon'un düşmesi"),
    (1979, "İran İslam Devrimi'nin gerçekleşmesi"),
    (1994, "Nelson Mandela'nın Güney Afrika cumhurbaşkanı seçilmesi"),
    (1997, "Hong Kong'un Çin'e devredilmesi"),
  ],
  [
    (
      1543,
      "Kopernik'in gök kürelerinin devinimleri üzerine kitabının yayımlanması",
    ),
    (1609, "Kepler'in Astronomia Nova adlı eserinin yayımlanması"),
    (1610, "Galileo'nun Sidereus Nuncius adlı eserinin yayımlanması"),
    (
      1628,
      "William Harvey'nin kan dolaşımını açıkladığı eserinin yayımlanması",
    ),
    (1665, "Robert Hooke'un Micrographia adlı eserinin yayımlanması"),
    (1687, "Newton'ın Principia adlı eserinin yayımlanması"),
    (1781, "William Herschel'in Uranüs'ü keşfetmesi"),
    (1796, "Edward Jenner'ın James Phipps üzerinde çiçek aşısı deneyi yapması"),
    (1800, "Alessandro Volta'nın elektrik pilini tanıtması"),
    (
      1820,
      "Ørsted'in elektrik akımının pusula iğnesini saptırdığını gözlemlemesi",
    ),
    (1831, "Faraday'ın elektromanyetik indüksiyonu keşfetmesi"),
    (1846, "Neptün'ün ilk kez hesaplamalara dayalı olarak gözlenmesi"),
    (1859, "Darwin'in Türlerin Kökeni adlı eserinin yayımlanması"),
    (1869, "Mendeleyev'in periyodik tablosunu yayımlaması"),
    (1876, "Alexander Graham Bell'in ABD'de telefon patentini alması"),
    (1895, "Röntgen'in X ışınlarını keşfetmesi"),
    (
      1896,
      "Henri Becquerel'in uranyum tuzlarında doğal radyoaktiviteyi keşfetmesi",
    ),
    (1897, "J. J. Thomson'ın elektronu keşfetmesi"),
    (1898, "Marie ve Pierre Curie'nin radyumun keşfini duyurması"),
    (1903, "Wright kardeşlerin Kitty Hawk yakınındaki motorlu uçuşu"),
    (1905, "Einstein'ın özel görelilik makalesinin yayımlanması"),
    (1911, "Rutherford'un atomun çekirdek modelini önermesi"),
    (1913, "Niels Bohr'un hidrojen atomu modelini yayımlaması"),
    (1915, "Einstein'ın genel göreliliğin son alan denklemlerini sunması"),
    (1928, "Alexander Fleming'in penisilini keşfetmesi"),
    (1930, "Clyde Tombaugh'nun Plüton'u keşfetmesi"),
    (1932, "James Chadwick'in nötronu keşfetmesi"),
    (1953, "Watson ve Crick'in DNA'nın çift sarmal modelini yayımlaması"),
    (1957, "Sputnik 1'in yörüngeye yerleştirilmesi"),
    (1961, "Yuri Gagarin'in uzaya çıkması"),
    (1963, "Valentina Tereşkova'nın uzaya çıkması"),
    (1969, "Apollo 11'in Ay'a inişi"),
    (1971, "Mariner 9'un Mars yörüngesine girmesi"),
    (1977, "Voyager 1'in fırlatılması"),
    (1981, "Columbia'nın ilk uzay mekiği yörünge uçuşuna çıkması"),
    (1986, "Mir uzay istasyonunun çekirdek modülünün fırlatılması"),
    (1990, "Hubble Uzay Teleskobu'nun fırlatılması"),
    (1997, "Mars Pathfinder'ın Mars'a inmesi"),
    (2004, "Cassini'nin Satürn yörüngesine girmesi"),
    (2012, "Curiosity keşif aracının Mars'a inmesi"),
    (2015, "New Horizons'ın Plüton yakınından geçmesi"),
    (2021, "James Webb Uzay Teleskobu'nun fırlatılması"),
  ],
];

typedef _Trio = (_Event, _Event, _Event);
final List<_Trio> _historyCases = _historyWindows();
List<_Trio> _historyWindows() {
  final perTheme = <List<_Trio>>[];
  for (final theme in _periods) {
    final windows = <_Trio>[];
    for (var left = 0; left < theme.length - 2; left++) {
      for (
        var mid = left + 1;
        mid < theme.length - 1 && mid <= left + 5;
        mid++
      ) {
        for (
          var right = mid + 1;
          right < theme.length && right <= left + 9;
          right++
        ) {
          if (theme[right].$1 - theme[left].$1 <= 160)
            windows.add((theme[left], theme[mid], theme[right]));
        }
      }
    }
    perTheme.add(windows);
  }
  final cases = <_Trio>[];
  // Keep all historical themes represented throughout the bank and take
  // windows spread over each theme's whole time span.
  for (var n = 0; n < 500; n++) {
    for (final pool in perTheme) {
      if (pool.length < 500) throw StateError('Yetersiz kronoloji penceresi');
      cases.add(pool[(n * pool.length) ~/ 500]);
    }
  }
  return cases;
}

AdvancedItem _dateRecall(int index) {
  final (a, b, c) = _historyCases[index];
  final order = index % 2 == 0 ? [c, a, b] : [b, c, a];
  final x = order[0], y = order[1], z = order[2];
  String years(_Event p, _Event q, _Event r) => '${p.$1} / ${q.$1} / ${r.$1}';
  return AdvancedItem(
    'I. ${x.$2}\nII. ${y.$2}\nIII. ${z.$2}\nBu üç gelişmenin takvim yılları numara sırasına göre hangileridir?',
    years(x, y, z),
    [years(y, x, z), years(x, z, y), years(z, y, x)],
    'Tarih sırasıyla ${a.$1} yılında “${a.$2}”, ${b.$1} yılında “${b.$2}”, ${c.$1} yılında “${c.$2}” gerçekleşti.',
  );
}

AdvancedItem _periodReading(int index) {
  final (a, b, c) = _historyCases[index];
  final first = b.$1 - a.$1, second = c.$1 - b.$1;
  final visual = QuestionVisual(
    kind: VisualKind.table,
    title: 'Kronoloji çizelgesi',
    summary: 'Aralıkları takvim yılları arasındaki fark olarak değerlendirin.',
    columns: const ['Gelişme', 'Yıl'],
    rows: [
      [a.$2, '${a.$1}'],
      [b.$2, '${b.$1}'],
      [c.$2, '${c.$1}'],
    ],
  );
  const options = [
    'İlk iki gelişme arasındaki süre daha uzundur.',
    'Son iki gelişme arasındaki süre daha uzundur.',
    'İki ardışık aralık eşit uzunluktadır.',
    'Verilen yıllar süreleri karşılaştırmaya yetmez.',
  ];
  final k = first > second
      ? 0
      : first < second
      ? 1
      : 2;
  return AdvancedItem(
    'Bir öğrenci çizelgedeki üç işareti eşit aralıklarla yerleştirmiştir. Sabit ölçekli bir zaman şeridi çizmek için hangi yorum doğrudur?',
    options[k],
    [
      for (var j = 0; j < 4; j++)
        if (j != k) options[j],
    ],
    'İlk aralık ${b.$1} − ${a.$1} = $first yıl, ikinci aralık ${c.$1} − ${b.$1} = $second yıldır. Sabit ölçekte çizgi uzunlukları bu sürelerle orantılıdır.',
    visual: visual,
  );
}

final socialFamilies = <AdvancedFamily>[
  _family(
    'census',
    'Sayım verilerinde kentleşme',
    Topic.geography,
    false,
    _census,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'migration',
    'Doğal artış ve göç bilançosu',
    Topic.geography,
    false,
    _migration,
  ),
  _family('ages', 'Nüfusun yaş yapısı', Topic.geography, false, _ages),
  _family('land', 'Arazi ve nüfus yoğunluğu', Topic.geography, false, _land),
  _family(
    'contour',
    'Yükselti kesitinin okunması',
    Topic.geography,
    false,
    _contour,
  ),
  _family(
    'map',
    'Ölçek ve arazi ölçümü',
    Topic.geography,
    false,
    _map,
    table: false,
  ),
  _family(
    'climate',
    'Yükselti ve sıcaklık modeli',
    Topic.geography,
    false,
    _climate,
    table: false,
  ),
  _family(
    'solar',
    'Meridyenler ve yerel güneş saati',
    Topic.geography,
    false,
    _solar,
    kind: VisualKind.diagram,
  ),
  _family(
    'agriculture',
    'Tarımda alan, verim ve üretim',
    Topic.geography,
    false,
    _agriculture,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'basin',
    'Havza su bilançosu',
    Topic.geography,
    false,
    _basin,
    kind: VisualKind.barChart,
  ),
  _family(
    'wages',
    'İktisat tarihinde alım gücü',
    Topic.history,
    false,
    _wages,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'archive',
    'Tarihsel kanıtla tarihleme',
    Topic.history,
    false,
    _archive,
    shortAnswer: false,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'date_recall',
    'Tarihsel olay ve yıl bilgisi',
    Topic.history,
    false,
    _dateRecall,
    shortAnswer: false,
    count: 2500,
    table: false,
    bloom: BloomLevel.hatirlama,
  ),
  _family(
    'time_scale',
    'Zaman şeridini yorumlama',
    Topic.history,
    false,
    _periodReading,
    shortAnswer: false,
    count: 2500,
    bloom: BloomLevel.anlama,
  ),
  _family(
    'standard',
    'Doğrudan yaş standardizasyonu',
    Topic.geography,
    true,
    _standard,
  ),
  _family(
    'did',
    'Yatırımın etkisini karşılaştırma',
    Topic.economics,
    true,
    _did,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'location',
    'Bölgesel ekonomik uzmanlaşma',
    Topic.geography,
    true,
    _location,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'strata',
    'Tabakalı örneklem ve ağırlıklar',
    Topic.research,
    true,
    _strata,
  ),
  _family(
    'missing',
    'Eksik yanıtta keskin sınırlar',
    Topic.research,
    true,
    _missing,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'cohort',
    'Panel izlemi ve kayıp',
    Topic.socialScience,
    true,
    _cohort,
    kind: VisualKind.lineChart,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'mobility',
    'Kuşaklar arası eğitim hareketliliği',
    Topic.socialScience,
    true,
    _mobility,
    bloom: BloomLevel.analiz,
  ),
  _family('prices', 'Tarihsel fiyat endeksleri', Topic.history, true, _prices),
  _family(
    'inequality',
    'Gelir dağılımı ve Lorenz eğrisi',
    Topic.economics,
    true,
    _inequality,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'texts',
    'Derlem büyüklüğü ve sözcük sıklığı',
    Topic.literature,
    true,
    _texts,
    bloom: BloomLevel.analiz,
  ),
  _family(
    'overlap',
    'Arşiv yazımlarında kaynak örtüşmesi',
    Topic.history,
    true,
    _overlap,
  ),
  _family(
    'bounds_review',
    'Eksik veride iddia değerlendirmesi',
    Topic.research,
    true,
    _boundsReview,
    shortAnswer: false,
    count: 5000,
    bloom: BloomLevel.degerlendirme,
  ),
  _family(
    'field_design',
    'Coğrafi saha araştırması tasarımı',
    Topic.geography,
    true,
    _fieldDesign,
    shortAnswer: false,
    count: 5000,
    bloom: BloomLevel.yaratma,
    creation: _fieldTask,
  ),
  _family(
    'archive_design',
    'Arşiv doğrulama protokolü',
    Topic.history,
    true,
    _archiveDesign,
    shortAnswer: false,
    count: 5000,
    bloom: BloomLevel.yaratma,
    creation: _archiveTask,
  ),
];
