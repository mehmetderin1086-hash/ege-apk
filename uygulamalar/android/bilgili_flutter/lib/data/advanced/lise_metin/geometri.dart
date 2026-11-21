// Lise geometri ve analitik geometri metin aileleri: üçgen, çokgen, çember,
// katı cisimler, analitik düzlem ve dönüşümler. Her aile 5.000 ayrı vaka
// üretir; şekiller tümüyle sözle betimlenir.
import 'ortak.dart';

const _mat = Topic.mathematics;
const _tm = 'Temel Matematik';
const _aytMat = 'Matematik';

/// İşaretli tam sayı (Unicode eksi ile).
String _m(int x) => x < 0 ? '−${-x}' : '$x';

/// İşlem içinde kullanılan sayı: negatifse parantez içinde.
String _pz(int x) => x < 0 ? '(−${-x})' : '$x';

/// Nokta ya da vektör yazımı: (3, −2).
String _n(int x, int y) => '(${_m(x)}, ${_m(y)})';

/// c·√n ifadesini sadeleştirerek yazar: _kok(1, 12) → 2√3, _kok(3, 4) → 6.
String _kok(int c, int n) {
  for (var d = 2; d * d <= n; d++) {
    while (n % (d * d) == 0) {
      n ~/= d * d;
      c *= d;
    }
  }
  if (n == 1) return '$c';
  return c == 1 ? '√$n' : '$c√$n';
}

/// Unicode eksi işaretli sade kesir.
String _kesir(int n, int d) => kesir(n, d).replaceFirst('-', '−');

/// Köklü (c·√n) yanıtlı soru; seçenekler (katsayı, kök içi) ikilileridir.
AdvancedItem _koklu(
  String prompt,
  (int, int) dogru,
  List<(int, int)> yanlis,
  String aciklama,
) {
  final (c, n) = dogru;
  final havuz = [
    ...yanlis,
    (2 * c, n),
    (c, 2 * n),
    (3 * c, n),
    (c, 3 * n),
    (c + 1, n),
    (4 * c, n),
  ].where((e) => e.$1 > 0 && e.$2 > 0);
  return secenekli(
    prompt,
    _kok(c, n),
    havuz.map((e) => _kok(e.$1, e.$2)),
    aciklama,
  );
}

/// Derece yanıtlı soru.
AdvancedItem _aci(
  String prompt,
  int dogru,
  List<int> yanlis,
  String aciklama, {
  int ust = 180,
}) {
  final havuz = [
    ...yanlis,
    dogru + 10,
    dogru - 10,
    dogru + 20,
    dogru - 20,
    dogru + 5,
    dogru - 5,
    dogru + 15,
  ].where((x) => x > 0 && x < ust);
  return secenekli(prompt, '$dogru°', havuz.map((x) => '$x°'), aciklama);
}

/// İşaretli tam sayı yanıtlı soru (negatif ve sıfır olabilir).
AdvancedItem _tam(
  String prompt,
  int dogru,
  List<int> yanlis,
  String aciklama,
) => secenekli(
  prompt,
  _m(dogru),
  [
    ...yanlis,
    dogru + 1,
    dogru - 1,
    dogru + 2,
    dogru - 2,
    dogru + 3,
  ].map(_m),
  aciklama,
);

/// Nokta ya da vektör yanıtlı soru.
AdvancedItem _noktali(
  String prompt,
  (int, int) dogru,
  List<(int, int)> yanlis,
  String aciklama,
) {
  final (x, y) = dogru;
  return secenekli(
    prompt,
    _n(x, y),
    [
      ...yanlis,
      (x + 1, y),
      (x, y + 1),
      (x - 1, y - 1),
      (x + 1, y - 1),
      (x - 2, y),
    ].map((e) => _n(e.$1, e.$2)),
    aciklama,
  );
}

/// "2x − 3y + 5" gibi doğrusal ifade; sıfır katsayılı terimler yazılmaz.
String _ifade(List<(int, String)> terimler) {
  final s = StringBuffer();
  for (final (k, v) in terimler) {
    if (k == 0) continue;
    final m = k.abs();
    final g = v.isEmpty ? '$m' : (m == 1 ? v : '$m$v');
    if (s.isEmpty) {
      s.write(k < 0 ? '−$g' : g);
    } else {
      s.write(k < 0 ? ' − $g' : ' + $g');
    }
  }
  return s.isEmpty ? '0' : s.toString();
}

/// px + qy + r = 0 biçiminde doğru denklemi.
String _dnk(int p, int q, int r) {
  final z = p < 0 || (p == 0 && q < 0) ? -1 : 1;
  return '${_ifade([(z * p, 'x'), (z * q, 'y'), (z * r, '')])} = 0';
}

/// (x − h)² yazımı; h sıfırsa x².
String _kare(String v, int h) =>
    h == 0 ? '$v²' : (h > 0 ? '($v − $h)²' : '($v + ${-h})²');

/// İlkel Pisagor üçlüleri.
const _ilkel = [
  (3, 4, 5), (5, 12, 13), (8, 15, 17), (7, 24, 25), (20, 21, 29),
  (12, 35, 37), (9, 40, 41), (28, 45, 53), (11, 60, 61), (16, 63, 65),
  (33, 56, 65), (48, 55, 73), (13, 84, 85),
];

/// Öklid bağıntılarında |BH| : |HC| oranları (aralarında asal).
const _oklid = [
  (1, 2), (2, 1), (1, 3), (3, 1), (2, 3), (3, 2), (1, 4), (4, 1), (3, 4),
  (4, 3), (2, 5), (5, 2), (4, 5), (5, 4), (1, 8), (8, 1), (4, 9), (9, 4),
  (3, 5), (5, 3),
];

const _gezgin = [
  ('Bir yürüyüşçü', 'm', 'yürüyor'),
  ('Bir gemi', 'km', 'ilerliyor'),
  ('Bir insansız hava aracı', 'm', 'uçuyor'),
  ('Bir bisikletli', 'm', 'gidiyor'),
];

/// Aralarında asal küçük oranlar (m < n).
const _oran = [
  (1, 2), (1, 3), (2, 3), (1, 4), (3, 4), (1, 5), (2, 5), (3, 5), (4, 5),
  (1, 6), (5, 6), (1, 7), (2, 7), (3, 7), (4, 7), (5, 7), (6, 7), (3, 8),
  (5, 8), (7, 8), (2, 9), (4, 9), (5, 9), (7, 9), (3, 10),
];

/// Açıortay teoremi için kenar oranları (m < n < 2m, aralarında asal).
const _aciortayOran = [
  (2, 3), (3, 4), (3, 5), (4, 5), (4, 7), (5, 6), (5, 7), (5, 8), (5, 9),
  (6, 7), (7, 8), (7, 9), (8, 9),
];

/// (merkez açı, yarıçap çarpanı): yay ve dilim sonuçları tam çıkar.
const _yay = [
  (120, 3), (240, 3), (30, 6), (60, 6), (90, 2), (150, 6), (210, 6),
  (270, 2), (300, 6), (40, 9), (80, 9), (160, 9), (45, 4), (135, 4),
  (225, 4), (315, 4), (72, 5), (144, 5), (216, 5), (288, 5),
];

/// Cisim köşegeni için aralarında asal ayrıt oranları.
const _ayrit = [
  (1, 2, 2), (2, 3, 6), (1, 4, 8), (2, 6, 9), (4, 4, 7), (1, 1, 2), (1, 2, 3),
  (1, 2, 4), (2, 2, 3), (1, 3, 4), (2, 3, 4), (1, 2, 5), (3, 4, 5), (1, 1, 4),
  (1, 3, 5), (2, 3, 5), (3, 4, 12), (1, 4, 5), (2, 4, 5), (3, 5, 6),
];

/// Normal uzunluğu tam sayı olan doğru katsayıları (A, B, √(A² + B²)).
const _normal = [(3, 4, 5), (4, -3, 5), (5, 12, 13), (12, -5, 13), (8, 15, 17)];

/// Standart çember denklemi: (x − h)² + (y − k)² = sağ taraf.
String _cember(int h, int k, int sag) =>
    '${_kare('x', h)} + ${_kare('y', k)} = $sag';

const _konum = [
  'Çemberin iç bölgesindedir',
  'Çemberin dış bölgesindedir',
  'Çemberin üzerindedir',
  'Çemberin merkezindedir',
];

const _yansima = ['x eksenine', 'y eksenine', 'orijine', 'y = x doğrusuna'];

/// [tur] numaralı yansımayı uygular.
(int, int) _yansit(int tur, (int, int) p) => switch (tur) {
  0 => (p.$1, -p.$2),
  1 => (-p.$1, p.$2),
  2 => (-p.$1, -p.$2),
  _ => (p.$2, p.$1),
};

final lmGeometri = <AdvancedFamily>[
  // 1 · Üçgende iç ve dış açılar: dış açı, açıortayla oluşan açı, iki dış açı.
  lmAile(
    'geo_ucgen_aci',
    'Üçgende iç ve dış açılar',
    _mat,
    Difficulty.easy,
    BloomLevel.anlama,
    (a, b, c) {
      final j = c ~/ 3;
      if (c % 3 == 0) {
        final al = 25 + 2 * a, be = 15 + 4 * b + j, d = al + be;
        return _aci(
          'ABC üçgeninde A köşesindeki iç açının ölçüsü $al°, C köşesindeki '
          'dış açının ölçüsü $d° olarak veriliyor. Buna göre B köşesindeki iç '
          'açının ölçüsü kaç derecedir?',
          be,
          [180 - d, 180 - be, 180 - al],
          'Bir dış açının ölçüsü, kendisine komşu olmayan iki iç açının '
          'ölçüleri toplamına eşittir: $al° + B = $d°, B = $d° − $al° = $be°.',
        );
      }
      if (c % 3 == 1) {
        final al = 30 + 2 * a, be = 20 + b + 20 * j;
        final ga = 180 - al - be, y = al ~/ 2;
        return _aci(
          'ABC üçgeninde A açısının ölçüsü $al°, B açısının ölçüsü $be° olarak '
          'veriliyor. A köşesinden çizilen iç açıortay [BC] kenarını D '
          'noktasında kesiyor. Buna göre ADC açısının ölçüsü kaç derecedir?',
          be + y,
          [ga + y, al + be, ga, 180 - be],
          'Açıortay A açısını $y° ölçülü iki açıya ayırır. ADC açısı ABD '
          'üçgeninin D köşesindeki dış açısıdır: B + BAD = $be° + $y° = '
          '${be + y}°.',
        );
      }
      final p = 20 + 3 * a, q = 15 + b + 20 * j;
      final x = 180 - p, y = 180 - q, g = 180 - p - q;
      return _aci(
        'Bir ABC üçgeninde A köşesindeki dış açının ölçüsü $x°, B köşesindeki '
        'dış açının ölçüsü $y° olarak veriliyor. Buna göre C köşesindeki iç '
        'açının ölçüsü kaç derecedir?',
        g,
        [p + q, p, q],
        'A ve B köşelerindeki iç açılar 180° − $x° = $p° ve 180° − $y° = $q° '
        'olur. C = 180° − ($p° + $q°) = $g°.',
      );
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 2 · İkizkenar ve eşkenar üçgen: açı izleme ve cebirsel kenar.
  lmAile(
    'geo_ikizkenar',
    'İkizkenar ve eşkenar üçgende açı ve kenar',
    _mat,
    Difficulty.medium,
    BloomLevel.analiz,
    (a, b, c) {
      final j = c ~/ 2;
      if (c.isOdd) {
        final x = 6 + a, r = 1 + b % 5, p = 2 + b ~/ 5, s = 2 + j;
        final q = (p - 1) * x - r, kol = x + r, tab = 2 * x - s;
        return sayisal(
          'ABC üçgeninde |AB| = |AC| olmak üzere |AB| = (${p}x − $q) cm, '
          '|AC| = (x + $r) cm ve |BC| = (2x − $s) cm olarak veriliyor. Buna '
          'göre ABC üçgeninin çevresi kaç cm olur?',
          2 * kol + tab,
          [kol + 2 * tab, 2 * kol, kol + tab, 3 * x],
          'Eş kenarlar eşitlenir: ${p}x − $q = x + $r, buradan x = $x bulunur. '
          '|AB| = |AC| = $kol cm ve |BC| = $tab cm olduğundan çevre '
          '2·$kol + $tab = ${2 * kol + tab} cm olur.',
          unit: 'cm',
          positive: true,
        );
      }
      if (j == 4) {
        final x = 10 + 2 * a, y = 8 + 2 * b;
        return _aci(
          'ABC eşkenar üçgeninde D noktası [BC] kenarı, E noktası [AC] kenarı '
          'üzerindedir. BAD açısının ölçüsü $x°, CDE açısının ölçüsü $y° '
          'olduğuna göre ADE açısının ölçüsü kaç derecedir?',
          60 + x - y,
          [60 + x, 120 - x, 60 + x + y, 120 - y],
          'Eşkenar üçgende her açı 60° olduğundan ABD üçgeninde ADB = 180° − '
          '60° − $x° = ${120 - x}° olur. ADE = 180° − ${120 - x}° − $y° = '
          '${60 + x - y}°.',
        );
      }
      final al = 20 + 2 * a, be = 80 - a, t = 8 + 2 * b;
      final verilen = j == 3 ? 'ACD' : 'BCD';
      final (sorulan, yanit, yanlis, cozum) = switch (j) {
        0 => (
          'ADC',
          be + t,
          [be - t, 180 - be - t, al + t],
          'ADC açısı DBC üçgeninin D köşesindeki dış açısıdır: B + BCD = '
              '$be° + $t° = ${be + t}°.',
        ),
        1 => (
          'ACD',
          be - t,
          [be + t, 180 - be - t, be],
          'ACD = ACB − BCD = $be° − $t° = ${be - t}°.',
        ),
        2 => (
          'BDC',
          180 - be - t,
          [be + t, be - t, 180 - al - t],
          'DBC üçgeninde BDC = 180° − $be° − $t° = ${180 - be - t}°.',
        ),
        _ => (
          'BDC',
          al + t,
          [180 - al - t, be + t, be - t],
          'BDC açısı ADC üçgeninin D köşesindeki dış açısıdır: A + ACD = '
              '$al° + $t° = ${al + t}°.',
        ),
      };
      return _aci(
        'ABC üçgeninde |AB| = |AC| ve A açısının ölçüsü $al° olarak veriliyor. '
        '[AB] kenarı üzerinde alınan bir D noktası için $verilen açısının '
        'ölçüsü $t° olduğuna göre $sorulan açısının ölçüsü kaç derecedir?',
        yanit,
        yanlis,
        'Taban açıları eşittir: B = C = (180° − $al°) / 2 = $be°. $cozum',
      );
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 3 · Pisagor teoremi (üçlülerin katları) ve Öklid bağıntıları.
  lmAile(
    'geo_pisagor',
    'Pisagor teoremi ve Öklid bağıntıları',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final j = c ~/ 2;
      if (c.isEven) {
        final u = _ilkel[a ~/ 2], s = 7 + j;
        final dx = (a.isEven ? u.$1 : u.$2) * s;
        final dy = (a.isEven ? u.$2 : u.$1) * s, h = u.$3 * s;
        final x1 = 1 + b, x2 = dx - x1;
        final (kim, br, fiil) = sec(_gezgin, a + b);
        return sayisal(
          '$kim önce doğuya $x1 $br, sonra kuzeye $dy $br, ardından yine '
          'doğuya $x2 $br $fiil. Son durumda başlangıç noktasına olan kuş '
          'uçuşu uzaklığı kaç $br olur?',
          h,
          [dx + dy, (dx - dy).abs(), dx > dy ? dx : dy],
          'Doğu yönünde toplam $x1 + $x2 = $dx $br, kuzey yönünde $dy $br yol '
          'alınmıştır. Uzaklık √($dx² + $dy²) = √${dx * dx + dy * dy} = $h $br '
          'olur (${u.$1}-${u.$2}-${u.$3} üçgeninin $s katı).',
          unit: br,
          positive: true,
        );
      }
      final g = 1 + a;
      final (s, t) = _oklid[b];
      final p = g * s, q = g * t, hip = p + q;
      const giris =
          'ABC dik üçgeninde A açısının ölçüsü 90° olup A köşesinden [BC] '
          'hipotenüsüne inen yüksekliğin ayağı H noktasıdır.';
      final veri = j < 3
          ? '|BH| = $p cm ve |HC| = $q cm'
          : '|BH| = $p cm ve |BC| = $hip cm';
      if (j == 0 || j == 3) {
        return _koklu(
          '$giris $veri olduğuna göre |AH| kaç cm olur?',
          (g, s * t),
          [(g * g * s * t, 1), (g, s * s + t * t), (g, s * (s + t))],
          '${j == 3 ? '|HC| = $hip − $p = $q cm olur. ' : ''}Öklid bağıntısına '
          'göre |AH|² = |BH|·|HC| = $p·$q = ${p * q}, buradan |AH| = '
          '${_kok(g, s * t)} cm bulunur.',
        );
      }
      if (j == 2) {
        return _koklu(
          '$giris $veri olduğuna göre |AC| kaç cm olur?',
          (g, t * (s + t)),
          [(g, s * t), (g * g * t * (s + t), 1), (g, s * (s + t))],
          '|BC| = $p + $q = $hip cm olur. Öklid bağıntısına göre |AC|² = '
          '|HC|·|BC| = $q·$hip = ${q * hip}, buradan |AC| = '
          '${_kok(g, t * (s + t))} cm bulunur.',
        );
      }
      return _koklu(
        '$giris $veri olduğuna göre |AB| kaç cm olur?',
        (g, s * (s + t)),
        [(g, s * t), (g * g * s * (s + t), 1), (g, t * (s + t))],
        '${j == 1 ? '|BC| = $p + $q = $hip cm olur. ' : ''}Öklid bağıntısına '
        'göre |AB|² = |BH|·|BC| = $p·$hip = ${p * hip}, buradan |AB| = '
        '${_kok(g, s * (s + t))} cm bulunur.',
      );
    },
    exam: ExamKind.tyt,
    lesson: _tm,
    shortAnswer: false,
  ),
  // 4 · 30-60-90 ve 45-45-90 üçgenleri: yükseklikli üçgen ve dik yamuk.
  lmAile(
    'geo_ozel_ucgen',
    '30-60-90 ve 45-45-90 üçgenleri',
    _mat,
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) {
      final j = c ~/ 2, m = 2 + a;
      if (c.isEven) {
        final n = 1 + b;
        final (aci, ab) = switch (j) {
          1 || 4 => (45, _kok(m, 2)),
          2 => (30, '${2 * m}'),
          _ => (60, '${2 * m}'),
        };
        final hc = j == 4 ? '|BC| = ${m + n} cm' : '|HC| = ${j < 2 ? n : 2 * n} cm';
        final veri =
            'ABC üçgeninde A köşesinden [BC] kenarına inen yüksekliğin ayağı '
            'olan H noktası B ile C arasındadır. B açısının ölçüsü $aci°, '
            '|AB| = $ab cm ve $hc olduğuna göre';
        return switch (j) {
          0 => _koklu(
            '$veri |BC| kaç cm olur?',
            (m + n, 1),
            [(2 * m + n, 1), (m, 3), (m + 2 * n, 1)],
            'ABH bir 30-60-90 üçgenidir; 30° karşısındaki |BH| = ${2 * m} / 2 '
                '= $m cm olur. |BC| = |BH| + |HC| = $m + $n = ${m + n} cm.',
          ),
          1 => _koklu(
            '$veri |BC| kaç cm olur?',
            (m + n, 1),
            [(2 * m + n, 1), (m + n, 2), (m, 1)],
            'ABH bir 45-45-90 üçgenidir; hipotenüs $ab cm olduğundan |BH| = '
                '|AH| = $m cm olur. |BC| = $m + $n = ${m + n} cm.',
          ),
          2 => _koklu(
            '$veri AHC üçgeninin alanı kaç cm² olur?',
            (m * n, 1),
            [(m * n, 3), (2 * m * n, 1), (2 * m * n, 3)],
            'ABH üçgeninde 30° karşısındaki |AH| = ${2 * m} / 2 = $m cm olur. '
                'AHC dik üçgeninin alanı |AH|·|HC| / 2 = $m·${2 * n} / 2 = '
                '${m * n} cm².',
          ),
          3 => _koklu(
            '$veri AHC üçgeninin alanı kaç cm² olur?',
            (m * n, 3),
            [(m * n, 1), (2 * m * n, 3), (2 * m * n, 1)],
            'ABH üçgeninde 60° karşısındaki |AH| = ${_kok(m, 3)} cm olur. AHC '
                'dik üçgeninin alanı |AH|·|HC| / 2 = ${_kok(m, 3)}·${2 * n} / '
                '2 = ${_kok(m * n, 3)} cm².',
          ),
          _ => _koklu(
            '$veri |HC| kaç cm olur?',
            (n, 1),
            [(m, 1), (m + 2 * n, 1), (n, 2)],
            'ABH bir 45-45-90 üçgenidir; hipotenüs $ab cm olduğundan |BH| = '
                '$m cm olur. |HC| = |BC| − |BH| = ${m + n} − $m = $n cm.',
          ),
        };
      }
      final t = 3 + b, w = t + m;
      const giris = 'ABCD dik yamuğunda [AB] ∥ [DC] ve [AD] ⊥ [AB] olup';
      const dikme =
          'C köşesinden [AB] kenarına inen dikmenin ayağı E olsun; |AE| = '
          '|DC| olur.';
      return switch (j) {
        0 => _koklu(
          '$giris |DC| = $t cm, |BC| = ${2 * m} cm ve B açısının ölçüsü 60° '
              'olarak veriliyor. Buna göre |AB| kaç cm olur?',
          (w, 1),
          [(t + 2 * m, 1), (2 * t + m, 1), (m, 3)],
          '$dikme CEB bir 30-60-90 üçgenidir; 30° karşısındaki |EB| = '
              '${2 * m} / 2 = $m cm olur. |AB| = $t + $m = $w cm.',
        ),
        1 => _koklu(
          '$giris |DC| = $t cm, |BC| = ${_kok(m, 2)} cm ve B açısının ölçüsü '
              '45° olarak veriliyor. Buna göre |AB| kaç cm olur?',
          (w, 1),
          [(t + 2 * m, 1), (w, 2), (m, 1)],
          '$dikme CEB bir 45-45-90 üçgenidir; hipotenüs ${_kok(m, 2)} cm '
              'olduğundan |EB| = $m cm olur. |AB| = $t + $m = $w cm.',
        ),
        2 => _koklu(
          '$giris |AB| = $w cm, |DC| = $t cm ve B açısının ölçüsü 45° olarak '
              'veriliyor. Buna göre |BC| kaç cm olur?',
          (m, 2),
          [(m, 1), (2 * m, 1), (m, 3)],
          '$dikme |EB| = $w − $t = $m cm bulunur. CEB bir 45-45-90 üçgeni '
              'olduğundan |BC| = ${_kok(m, 2)} cm.',
        ),
        3 => _koklu(
          '$giris |AB| = $w cm, |DC| = $t cm ve B açısının ölçüsü 60° olarak '
              'veriliyor. Buna göre |BC| kaç cm olur?',
          (2 * m, 1),
          [(m, 1), (m, 2), (m, 3)],
          '$dikme |EB| = $w − $t = $m cm bulunur. CEB bir 30-60-90 üçgenidir; '
              '30° karşısındaki kenar $m cm olduğundan hipotenüs |BC| = '
              '${2 * m} cm.',
        ),
        _ => _koklu(
          '$giris |AB| = $w cm, |DC| = $t cm ve B açısının ölçüsü 60° olarak '
              'veriliyor. Buna göre yamuğun yüksekliği olan |AD| kaç cm olur?',
          (m, 3),
          [(m, 1), (2 * m, 1), (m, 2)],
          '$dikme |EB| = $w − $t = $m cm bulunur. CEB bir 30-60-90 üçgenidir; '
              '60° karşısındaki |CE| = ${_kok(m, 3)} cm olur ve |AD| = |CE| = '
              '${_kok(m, 3)} cm.',
        ),
      };
    },
    exam: ExamKind.tyt,
    lesson: _tm,
    shortAnswer: false,
  ),
  // 5 · Üçgenin alanı: iki ayrı taban-yükseklik ve sinüslü alan.
  lmAile(
    'geo_ucgen_alan',
    'Üçgenin alanı: yükseklik ve sinüs bağıntısı',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final j = c ~/ 2;
      if (c.isEven) {
        // sin C = sn/sd seçilir: |AC| = sd·m, h_a = sn·m, |BC| = sd·n ve
        // h_b = sn·n. m > n olduğundan kenar oranı 1 ile 8/3 arasında kalır
        // ve yanıt verilen sayılardan hiçbirine eşit olmaz. Yüksekliğin ayağı
        // kenarın uzantısına düşebildiği için "kenara ait yükseklik" denir.
        final (sn, sd) = const [(1, 2), (2, 3), (3, 4), (3, 5), (4, 5)][j];
        final n = 12 + a, m = n + 1 + b;
        final t = sd * n, u = sd * m, r = sn * m, q = sn * n;
        return sayisal(
          'ABC üçgeninde |BC| = $t cm ve [BC] kenarına ait yükseklik $r cm '
          'olarak veriliyor. |AC| = $u cm olduğuna göre [AC] kenarına ait '
          'yükseklik kaç cm olur?',
          q,
          // Tek tarafta ikiye bölmeyi unutma (iki yönde), çarpım yerine toplam
          // eşitliği kurma, yükseklikleri eşit sanma, alanı yanıt sanma.
          [
            2 * q,
            if (q.isEven) q ~/ 2,
            t + r - u,
            r,
            if ((t * r).isEven) t * r ~/ 2,
            u - r,
          ],
          'Üçgenin alanı iki ayrı kenar ve o kenara ait yükseklik ile '
          'yazılır: $t·$r / 2 = $u·h / 2. Buradan h = ${t * r} / $u = $q cm '
          'bulunur.',
          unit: 'cm',
          positive: true,
        );
      }
      final x = 2 + a, y = 1 + b, k = x * y;
      final th = const [30, 45, 60, 120, 150][j];
      final (kokIci, sinus) = switch (th) {
        30 => (1, 'sin 30° = 1/2'),
        45 => (2, 'sin 45° = √2/2'),
        60 => (3, 'sin 60° = √3/2'),
        120 => (3, 'sin 120° = sin 60° = √3/2'),
        _ => (1, 'sin 150° = sin 30° = 1/2'),
      };
      return _koklu(
        'ABC üçgeninde |AB| = ${2 * x} cm, |AC| = ${2 * y} cm ve bu iki '
        'kenarın oluşturduğu A açısının ölçüsü $th° olduğuna göre ABC '
        'üçgeninin alanı kaç cm² olur?',
        (k, kokIci),
        switch (kokIci) {
          1 => [(k, 3), (2 * k, 1), (k, 2)],
          2 => [(2 * k, 2), (k, 1), (k, 3)],
          _ => [(k, 1), (2 * k, 3), (k, 2)],
        },
        '$sinus olduğundan alan (1/2)·|AB|·|AC|·sin A = (1/2)·${2 * x}·'
        '${2 * y}·sin $th° = ${_kok(k, kokIci)} cm² olur.',
      );
    },
    exam: ExamKind.tyt,
    lesson: _tm,
    shortAnswer: false,
  ),
  // 6 · Benzerlik: temel benzerlik teoremi, çevre ve alan oranları.
  lmAile(
    'geo_benzerlik',
    'Üçgenlerde benzerlik: kenar, çevre ve alan oranı',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final j = c ~/ 2;
      final (m, n) = _oran[a];
      if (c.isEven) {
        final s = 2 + b, w = 2 + j;
        final ad = m * s, db = (n - m) * s, de = m * w, bc = n * w;
        return sayisal(
          'ABC üçgeninde D noktası [AB] kenarı, E noktası [AC] kenarı üzerinde '
          'olup [DE] ∥ [BC] olarak veriliyor. |AD| = $ad cm, |DB| = $db cm ve '
          '|DE| = $de cm olduğuna göre |BC| kaç cm olur?',
          bc,
          [(n - m) * w, de + db, n * s],
          'ADE ve ABC üçgenleri benzerdir: |AD| / |AB| = |DE| / |BC|. |AB| = '
          '$ad + $db = ${n * s} cm olduğundan $ad / ${n * s} = $de / |BC|, '
          '|BC| = $de·${n * s} / $ad = $bc cm.',
          unit: 'cm',
          positive: true,
        );
      }
      final k = 1 + b, s1 = m * m * k, s2 = n * n * k;
      switch (j) {
        case 0:
          return sayisal(
            'Benzerlik oranı $m/$n olan iki benzer üçgenden küçüğünün alanı '
            '$s1 cm² olduğuna göre büyüğünün alanı kaç cm² olur?',
            s2,
            [m * n * k, s1 * n, n * k],
            'Alanlar oranı benzerlik oranının karesidir: ($m/$n)² = '
            '${m * m}/${n * n}. Büyük alan $s1·${n * n} / ${m * m} = $s2 cm².',
            unit: 'cm²',
            positive: true,
          );
        case 1:
          return sayisal(
            'Benzerlik oranı $m/$n olan iki benzer üçgenden büyüğünün alanı '
            '$s2 cm² olduğuna göre küçüğünün alanı kaç cm² olur?',
            s1,
            [m * n * k, m * k, s2 - (n - m) * k],
            'Alanlar oranı benzerlik oranının karesidir: ($m/$n)² = '
            '${m * m}/${n * n}. Küçük alan $s2·${m * m} / ${n * n} = $s1 cm².',
            unit: 'cm²',
            positive: true,
          );
        case 2:
          final p1 = m * (k + 2), p2 = n * (k + 2);
          return sayisal(
            'Benzerlik oranı $m/$n olan iki benzer üçgenden küçüğünün çevresi '
            '$p1 cm olduğuna göre büyüğünün çevresi kaç cm olur?',
            p2,
            [n * n * (k + 2), p1 + n - m, m * m * (k + 2)],
            'Çevreler oranı benzerlik oranına eşittir: $p1 / Ç = $m/$n, '
            'Ç = $p1·$n / $m = $p2 cm.',
            unit: 'cm',
            positive: true,
          );
        case 3:
          final e1 = m * (k + 1), e2 = n * (k + 1);
          return sayisal(
            'Alanları $s1 cm² ve $s2 cm² olan benzer iki üçgenden küçüğünün '
            'bir kenarı $e1 cm olduğuna göre büyük üçgende bu kenara karşılık '
            'gelen kenar kaç cm olur?',
            e2,
            [n * n * (k + 1), e1 + (n * n - m * m) * k, e1 + n - m],
            'Alanlar oranı $s1/$s2 = ${m * m}/${n * n} olduğundan benzerlik '
            'oranı $m/$n olur. Karşılık gelen kenar $e1·$n / $m = $e2 cm.',
            unit: 'cm',
            positive: true,
          );
        default:
          final e1 = m * (k + 1), e2 = n * (k + 1);
          return sayisal(
            'Benzer iki üçgenin karşılıklı iki kenarının uzunlukları $e1 cm ve '
            '$e2 cm olarak veriliyor. Küçük üçgenin alanı $s1 cm² olduğuna '
            'göre büyük üçgenin alanı kaç cm² olur?',
            s2,
            [m * n * k, s1 * n, s1 + e2 - e1],
            'Benzerlik oranı $e1/$e2 = $m/$n, alanlar oranı bunun karesi olan '
            '${m * m}/${n * n} olur. Büyük alan $s1·${n * n} / ${m * m} = '
            '$s2 cm².',
            unit: 'cm²',
            positive: true,
          );
      }
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 7 · Açıortay teoremi, ağırlık merkezi ve hipotenüse ait kenarortay.
  lmAile(
    'geo_aciortay_kenarortay',
    'Açıortay teoremi, ağırlık merkezi ve kenarortay',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final j = c ~/ 3;
      if (c % 3 == 0) {
        final u = _aciortayOran[a ~/ 2];
        final m = a.isEven ? u.$1 : u.$2, n = a.isEven ? u.$2 : u.$1;
        final w = 2 + b ~/ 2, s = w + 1 + j;
        final ab = m * s, ac = n * s, bd = m * w, dc = n * w, bc = bd + dc;
        const giris =
            'ABC üçgeninde A açısının iç açıortayı [BC] kenarını D noktasında '
            'kesiyor.';
        if (b.isEven) {
          return sayisal(
            '$giris |AB| = $ab cm, |AC| = $ac cm ve |BD| = $bd cm olduğuna '
            'göre |DC| kaç cm olur?',
            dc,
            [bd + (n - m) * s, bc, ac - bd, bd],
            'Açıortay teoremine göre |BD| / |DC| = |AB| / |AC| = $ab/$ac = '
            '$m/$n olur. $bd / |DC| = $m/$n eşitliğinden |DC| = $dc cm.',
            unit: 'cm',
            positive: true,
          );
        }
        return sayisal(
          '$giris |AB| = $ab cm, |AC| = $ac cm ve |BC| = $bc cm olduğuna göre '
          '|BD| kaç cm olur?',
          bd,
          [dc, bc ~/ 2, ab ~/ 2],
          'Açıortay teoremine göre |BD| / |DC| = |AB| / |AC| = $ab/$ac = '
          '$m/$n olur. |BD| = $bc·$m / ${m + n} = $bd cm.',
          unit: 'cm',
          positive: true,
        );
      }
      if (c % 3 == 1) {
        final p = 2 + a, q = 3 + b;
        final (ad, yanit, yanlis) = switch (j) {
          0 => ('|AG| + |GE|', 2 * p + q, [p + 2 * q, p + q, 2 * p + 2 * q]),
          1 => ('|GD| + |BG|', p + 2 * q, [2 * p + q, p + q, 2 * p + 2 * q]),
          _ => ('|AG| + |BG|', 2 * p + 2 * q, [p + q, 2 * p + q, p + 2 * q]),
        };
        return sayisal(
          'ABC üçgeninde [AD] ve [BE] kenarortayları G noktasında kesişiyor. '
          '|AD| = ${3 * p} cm ve |BE| = ${3 * q} cm olduğuna göre $ad toplamı '
          'kaç cm olur?',
          yanit,
          [...yanlis, 3 * p + 3 * q],
          'Ağırlık merkezi her kenarortayı köşeden başlayarak 2:1 oranında '
          'böler: |AG| = ${2 * p}, |GD| = $p, |BG| = ${2 * q} ve |GE| = $q '
          'cm olur. $ad = $yanit cm.',
          unit: 'cm',
          positive: true,
        );
      }
      final x = 3 + a, r = 14 + b;
      const giris = 'ABC dik üçgeninde A açısının ölçüsü 90° olup D noktası '
          '[BC] hipotenüsünün orta noktasıdır.';
      const kural =
          'Dik üçgende hipotenüse ait kenarortay hipotenüsün yarısına eşittir';
      return switch (j) {
        0 => sayisal(
          '$giris |AB| = $x cm ve |BC| = ${2 * r} cm olduğuna göre ABD '
              'üçgeninin çevresi kaç cm olur?',
          x + 2 * r,
          [x + r, x + 4 * r, x + 3 * r],
          '$kural: |AD| = |BD| = ${2 * r} / 2 = $r cm. Çevre $x + $r + $r = '
              '${x + 2 * r} cm.',
          unit: 'cm',
          positive: true,
        ),
        1 => sayisal(
          '$giris |AB| = $x cm ve ABD üçgeninin çevresi ${x + 2 * r} cm '
              'olduğuna göre |BC| kaç cm olur?',
          2 * r,
          [r, 4 * r, x + 2 * r],
          '$kural: |AD| = |BD| = |BC| / 2. Çevre |AB| + |BC| = ${x + 2 * r} '
              'olduğundan |BC| = ${x + 2 * r} − $x = ${2 * r} cm.',
          unit: 'cm',
          positive: true,
        ),
        _ => sayisal(
          '$giris |AB| = $x cm ve |AD| = $r cm olduğuna göre ABD üçgeninin '
              'çevresi kaç cm olur?',
          x + 2 * r,
          [x + r, x + 3 * r, x + 4 * r],
          '$kural: |BD| = |DC| = |AD| = $r cm. Çevre $x + $r + $r = '
              '${x + 2 * r} cm.',
          unit: 'cm',
          positive: true,
        ),
      };
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 8 · Çokgenlerde iç ve dış açılar, köşegen sayısı.
  lmAile(
    'geo_cokgen',
    'Çokgenlerde iç açı, dış açı ve köşegen sayısı',
    _mat,
    Difficulty.medium,
    BloomLevel.analiz,
    (a, b, c) {
      final j = c ~/ 3;
      if (c % 3 == 0) {
        final n = 5 + a, x = 30 + 7 * b + j, ic = (n - 2) * 180, t = ic - x;
        return _aci(
          'Kenar sayısı $n olan konveks bir çokgenin iç açılarından biri '
          'dışındaki diğer iç açılarının ölçüleri toplamı $t° olarak '
          'veriliyor. Buna göre toplamın dışında bırakılan iç açının ölçüsü '
          'kaç derecedir?',
          x,
          [180 - x],
          '$n kenarlı çokgenin iç açıları toplamı ($n − 2)·180° = $ic° olur. '
          'Aranan açı $ic° − $t° = $x°.',
        );
      }
      if (c % 3 == 1) {
        final n = 5 + a, x = 25 + 7 * b + j, ic = (n - 2) * 180, t = ic - x;
        final d = n * (n - 3) ~/ 2;
        return sayisal(
          'Konveks bir çokgenin iç açılarından biri dışındaki diğer iç '
          'açılarının ölçüleri toplamı $t° olduğuna göre bu çokgenin köşegen '
          'sayısı kaçtır?',
          d,
          [n, (n - 1) * (n - 4) ~/ 2, (n + 1) * (n - 2) ~/ 2, n * (n - 1) ~/ 2],
          'Dışarıda bırakılan açı 0° ile 180° arasında olduğundan iç açılar '
          'toplamı, $t° değerinden büyük ilk 180° katı olan $ic° olur. '
          '(n − 2)·180° = $ic° eşitliğinden n = $n bulunur. Köşegen sayısı '
          'n·(n − 3) / 2 = $n·${n - 3} / 2 = $d.',
          positive: true,
        );
      }
      final y = 8 + a, m = 3 + b % 5, k = 2 + b ~/ 5, e = 360 - m * y;
      if (j == 2) {
        final n = k + m, ic = (n - 2) * 180, ver = 180 * k - e;
        return _aci(
          'Kenar sayısı $n olan konveks bir çokgenin iç açılarından $k '
          'tanesinin ölçüleri toplamı $ver° olup diğer $m iç açısının ölçüleri '
          'birbirine eşittir. Buna göre eşit olan iç açılardan her biri kaç '
          'derecedir?',
          180 - y,
          [y, 180 - y + 360 ~/ m, ic ~/ n],
          'İç açılar toplamı ($n − 2)·180° = $ic° olur. Kalan $m açının '
          'toplamı $ic° − $ver° = ${ic - ver}°, her biri ${ic - ver}° / $m = '
          '${180 - y}°.',
        );
      }
      const giris = 'Konveks bir çokgenin dış açılarından';
      final veri =
          '$giris $k tanesinin ölçüleri toplamı $e° olup diğer $m dış açısının '
          'ölçüleri birbirine eşittir.';
      final cozum =
          'Konveks çokgende dış açıların ölçüleri toplamı 360° olur. Kalan $m '
          'dış açının toplamı 360° − $e° = ${m * y}°, her biri ${m * y}° / $m '
          '= $y°.';
      if (j == 0) {
        return _aci(
          '$veri Buna göre eşit olan dış açılardan her biri kaç derecedir?',
          y,
          [180 - y, e ~/ k, 360 ~/ (k + m)],
          cozum,
        );
      }
      return _aci(
        '$veri Buna göre eşit olan dış açılara komşu iç açılardan her biri '
        'kaç derecedir?',
        180 - y,
        [y, 180 - e ~/ k, 180 - 360 ~/ (k + m)],
        '$cozum Komşu iç açı 180° − $y° = ${180 - y}°.',
      );
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 9 · Yamuk, paralelkenar, eşkenar dörtgen ve deltoidin alanı.
  lmAile(
    'geo_dortgen_alan',
    'Yamuk, paralelkenar, eşkenar dörtgen ve deltoid alanı',
    _mat,
    Difficulty.easy,
    BloomLevel.uygulama,
    (a, b, c) {
      final j = c ~/ 2;
      if (c.isEven) {
        final q = 4 + b, p = q + 2 * (1 + a), h = 3 + j + a % 4;
        final alan = (p + q) * h ~/ 2;
        return sayisal(
          'ABCD yamuğunda [AB] ∥ [DC] olup |AB| = $p cm, |DC| = $q cm ve '
          'yamuğun yüksekliği $h cm olarak veriliyor. Buna göre ABCD yamuğunun '
          'alanı kaç cm² olur?',
          alan,
          [(p + q) * h, p * h, (p - q) * h ~/ 2, q * h],
          'Yamuğun alanı, taban uzunlukları toplamı ile yüksekliğin '
          'çarpımının yarısıdır: ($p + $q)·$h / 2 = ${p + q}·$h / 2 = '
          '$alan cm².',
          unit: 'cm²',
          positive: true,
        );
      }
      final e = 2 * (3 + a), f = 5 + b;
      switch (j) {
        case 0:
          return sayisal(
            'Köşegen uzunlukları $e cm ve $f cm olan bir eşkenar dörtgenin '
            'alanı kaç cm² olur?',
            e * f ~/ 2,
            [e * f, 2 * (e + f), e * f ~/ 4, e + f],
            'Eşkenar dörtgenin alanı köşegen uzunlukları çarpımının yarısıdır: '
            '$e·$f / 2 = ${e * f ~/ 2} cm².',
            unit: 'cm²',
            positive: true,
          );
        case 1:
          final g = f + 20;
          return sayisal(
            'Köşegenleri birbirini dik kesen bir deltoidin köşegen uzunlukları '
            '$e cm ve $g cm olduğuna göre bu deltoidin alanı kaç cm² olur?',
            e * g ~/ 2,
            [e * g, 2 * (e + g), e * g ~/ 4, e + g],
            'Deltoidin alanı köşegen uzunlukları çarpımının yarısıdır: '
            '$e·$g / 2 = ${e * g ~/ 2} cm².',
            unit: 'cm²',
            positive: true,
          );
        case 2:
          final s = e * f ~/ 2;
          return sayisal(
            'Alanı $s cm² olan bir eşkenar dörtgenin köşegenlerinden biri '
            '$e cm olduğuna göre diğer köşegeni kaç cm olur?',
            f,
            [2 * f, s ~/ e, f + e],
            'Alan köşegenler çarpımının yarısıdır: $e·k / 2 = $s. Buradan '
            'k = ${2 * s} / $e = $f cm.',
            unit: 'cm',
            positive: true,
          );
        case 3:
          final p = 6 + a, h = 4 + b;
          return sayisal(
            'ABCD paralelkenarında |AB| = $p cm ve [AB] kenarına ait yükseklik '
            '$h cm olduğuna göre ABCD paralelkenarının alanı kaç cm² olur?',
            p * h,
            [p * h ~/ 2, 2 * (p + h), p + h],
            'Paralelkenarın alanı bir kenar ile o kenara ait yüksekliğin '
            'çarpımıdır: $p·$h = ${p * h} cm².',
            unit: 'cm²',
            positive: true,
          );
        default:
          final (u, v) = const [(3, 2), (4, 3), (5, 2), (5, 3), (5, 4)][b % 5];
          final t = 1 + b ~/ 5, m = 5 + a;
          final p = m * u, q = m * v, hp = v * t, hq = u * t;
          return sayisal(
            'ABCD paralelkenarında |AB| = $p cm, |AD| = $q cm ve [AB] kenarına '
            'ait yükseklik $hp cm olduğuna göre [AD] kenarına ait yükseklik '
            'kaç cm olur?',
            hq,
            [hp, p * hp, 2 * hq, q - hp],
            'Alan iki ayrı kenar ve yükseklikle yazılır: $p·$hp = $q·h. '
            'Buradan h = ${p * hp} / $q = $hq cm.',
            unit: 'cm',
            positive: true,
          );
      }
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 10 · Dikdörtgen ve karede çevre, alan ve köşegen.
  lmAile(
    'geo_dikdortgen',
    'Dikdörtgen ve karede çevre, alan ve köşegen',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final j = c ~/ 2;
      if (c.isEven) {
        final x = 3 + a, k = 2 + b % 5, m = 1 + j, uzun = k * x + m;
        final cevre = 2 * (x + uzun);
        final veri =
            'Çevresi $cevre cm olan bir dikdörtgenin uzun kenarı, kısa '
            'kenarının $k katından $m cm fazladır. Buna göre bu dikdörtgenin';
        final cozum =
            'Kısa kenar x olsun; uzun kenar ${k}x + $m olur. Yarı çevre '
            'x + ${k}x + $m = ${cevre ~/ 2} eşitliğinden x = $x cm, uzun kenar '
            '$uzun cm bulunur.';
        return switch (b ~/ 5) {
          0 => sayisal(
            '$veri alanı kaç cm² olur?',
            x * uzun,
            [k * x * x, 2 * x * uzun, x + uzun, x * uzun ~/ 2],
            '$cozum Alan $x·$uzun = ${x * uzun} cm².',
            unit: 'cm²',
            positive: true,
          ),
          1 => sayisal(
            '$veri uzun kenarı kaç cm olur?',
            uzun,
            [x, k * x, x + uzun, uzun + m],
            cozum,
            unit: 'cm',
            positive: true,
          ),
          2 => sayisal(
            '$veri kısa kenarı kaç cm olur?',
            x,
            [uzun, cevre ~/ 2 ~/ (k + 1), x + m, k * x],
            cozum,
            unit: 'cm',
            positive: true,
          ),
          _ => sayisal(
            '$veri uzun kenarı kısa kenarından kaç cm fazladır?',
            uzun - x,
            [uzun, x, uzun + x, m],
            '$cozum Fark $uzun − $x = ${uzun - x} cm.',
            unit: 'cm',
            positive: true,
          ),
        };
      }
      final g = 1 + a;
      final (s, t) = _oran[b];
      final p = g * s, q = g * t, kk = s * s + t * t;
      const pisagor = 'Köşegen, kenarlarla dik üçgen oluşturur';
      return switch (j) {
        0 => _koklu(
          'Kısa kenarı $p cm, uzun kenarı $q cm olan bir dikdörtgenin köşegen '
              'uzunluğu kaç cm olur?',
          (g, kk),
          [(p + q, 1), (g, 2 * s * t), (g, t * t - s * s)],
          '$pisagor: k² = $p² + $q² = ${p * p + q * q}, k = ${_kok(g, kk)} cm.',
        ),
        1 => _koklu(
          'Köşegen uzunluğu ${_kok(g, kk)} cm, kısa kenarı $p cm olan bir '
              'dikdörtgenin uzun kenarı kaç cm olur?',
          (q, 1),
          [(g, 2 * s * s + t * t), (q, 2), (g * (t - s), 1)],
          '$pisagor: uzun kenarın karesi ${p * p + q * q} − $p² = ${q * q} '
              'olur, uzun kenar $q cm.',
        ),
        2 => _koklu(
          'Alanı ${p * q} cm², kısa kenarı $p cm olan bir dikdörtgenin köşegen '
              'uzunluğu kaç cm olur?',
          (g, kk),
          [(p + q, 1), (g, 2 * s * t), (g, t * t - s * s)],
          'Uzun kenar ${p * q} / $p = $q cm olur. $pisagor: k² = $p² + $q² = '
              '${p * p + q * q}, k = ${_kok(g, kk)} cm.',
        ),
        3 => _koklu(
          'Çevresi ${2 * (p + q)} cm, kısa kenarı $p cm olan bir dikdörtgenin '
              'köşegen uzunluğu kaç cm olur?',
          (g, kk),
          [(p + q, 1), (g, 2 * s * t), (g, t * t - s * s)],
          'Uzun kenar ${p + q} − $p = $q cm olur. $pisagor: k² = $p² + $q² = '
              '${p * p + q * q}, k = ${_kok(g, kk)} cm.',
        ),
        _ => _koklu(
          'Bir karenin alanı, kenar uzunlukları $p cm ve $q cm olan '
              'dikdörtgenin alanına eşittir. Buna göre bu karenin köşegen '
              'uzunluğu kaç cm olur?',
          (g, 2 * s * t),
          [(g, s * t), (g, kk), (2 * g, s * t)],
          'Karenin alanı $p·$q = ${p * q} cm² olduğundan bir kenarı '
              '${_kok(g, s * t)} cm olur. Köşegen, kenarın √2 katıdır: '
              '${_kok(g, 2 * s * t)} cm.',
        ),
      };
    },
    exam: ExamKind.tyt,
    lesson: _tm,
    shortAnswer: false,
  ),
  // 11 · Çemberde yay uzunluğu, dairede dilim alanı (π'li ya da π = 3).
  lmAile(
    'geo_cember_uzunluk',
    'Çemberde yay uzunluğu ve daire diliminin alanı',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final j = c ~/ 2, uc = c.isOdd;
      final (al, carpan) = _yay[b];
      final r = carpan * (1 + a);
      final y = r * al ~/ 180, s = r * r * al ~/ 360;
      String sim(int k) => k == 1 ? 'π' : '$kπ';
      String yaz(int k) => uc ? '${3 * k}' : sim(k);
      final ek = uc ? ' (π = 3 alınız.)' : '';
      final pi = uc ? '' : 'π ';
      String son(int k) => uc ? ' π = 3 alınırsa ${3 * k} bulunur.' : '';
      int deger(int k) => uc ? 3 * k : k;
      switch (j) {
        case 0:
          return sayisal(
            'Yarıçapı $r cm olan bir çemberde, merkez açısının ölçüsü $al° '
            'olan yayın uzunluğu kaç ${pi}cm olur?$ek',
            deger(y),
            [2 * r, s, 2 * y, r].map(deger),
            'Yay uzunluğu 2πr·(α / 360) = 2π·$r·$al / 360 = ${sim(y)} cm olur.'
            '${son(y)}',
            positive: true,
          );
        case 1:
          return sayisal(
            'Yarıçapı $r cm olan bir dairede, merkez açısının ölçüsü $al° olan '
            'daire diliminin alanı kaç ${pi}cm² olur?$ek',
            deger(s),
            [r * r, y, 2 * s, s ~/ 2].map(deger),
            'Dilimin alanı πr²·(α / 360) = π·${r * r}·$al / 360 = ${sim(s)} cm² '
            'olur.${son(s)}',
            positive: true,
          );
        case 2:
          return sayisal(
            'Bir çemberde merkez açısının ölçüsü $al° olan yayın uzunluğu '
            '${yaz(y)} cm olduğuna göre bu çemberin yarıçapı kaç cm olur?$ek',
            r,
            [2 * r, y, r ~/ 2, 3 * r],
            'Yay uzunluğu 2πr·($al / 360) = ${yaz(y)} eşitliğinden '
            'r = $r cm bulunur.',
            unit: 'cm',
            positive: true,
          );
        case 3:
          return sayisal(
            'Bir dairede merkez açısının ölçüsü $al° olan daire diliminin '
            'alanı ${yaz(s)} cm² olduğuna göre bu dairenin yarıçapı kaç cm '
            'olur?$ek',
            r,
            [2 * r, r ~/ 2, 3 * r, r + carpan],
            'Dilimin alanı πr²·($al / 360) = ${yaz(s)} eşitliğinden '
            'r² = ${r * r}, r = $r cm bulunur.',
            unit: 'cm',
            positive: true,
          );
        default:
          return _aci(
            'Yarıçapı $r cm olan bir çemberde uzunluğu ${yaz(y)} cm olan yayı '
            'gören merkez açının ölçüsü kaç derecedir?$ek',
            al,
            [al ~/ 2, 2 * al, 360 - al, 180 - al],
            'Çemberin çevresi 2πr = ${yaz(2 * r)} cm olur. Yay çevrenin '
            '${kesir(y, 2 * r)} kadarı olduğundan merkez açı '
            '360°·${kesir(y, 2 * r)} = $al°.',
            ust: 360,
          );
      }
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 12 · Çemberde merkez, çevre, teğet-kiriş açıları ve kirişler dörtgeni.
  lmAile(
    'geo_cember_aci',
    'Çemberde açılar ve kirişler dörtgeni',
    _mat,
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) {
      final ikinci = c >= 5;
      switch (c % 5) {
        case 0:
          final x = 40 + 4 * a, y = 30 + 4 * b, kalan = 360 - x - y;
          const veri = 'Bir çember üzerinde A, B ve C noktaları alınıyor. C '
              'noktasını içermeyen AB yayının ölçüsü';
          final cozum =
              'B noktasını içermeyen AC yayının ölçüsü 360° − $x° − $y° = '
              '$kalan° olur.';
          if (ikinci) {
            final th = kalan ~/ 2;
            return _aci(
              '$veri $x°, ABC açısının ölçüsü $th° olduğuna göre A noktasını '
              'içermeyen BC yayının ölçüsü kaç derecedir?',
              y,
              [360 - th - x, y ~/ 2, 2 * th, 180 - th],
              'ABC çevre açısının gördüğü, B noktasını içermeyen AC yayı '
              '2·$th° = $kalan° olur. Üç yayın toplamı 360° olduğundan BC yayı '
              '360° − $kalan° − $x° = $y°.',
              ust: 360,
            );
          }
          return _aci(
            '$veri $x°, A noktasını içermeyen BC yayının ölçüsü $y° olduğuna '
            'göre ABC açısının ölçüsü kaç derecedir?',
            kalan ~/ 2,
            [kalan, (x + y) ~/ 2, x + y],
            '$cozum ABC çevre açısı bu yayı gördüğünden ölçüsü $kalan° / 2 = '
            '${kalan ~/ 2}°.',
            ust: 360,
          );
        case 1:
          final u = 25 + 2 * a, v = 30 + 3 * b, t = 180 - u - v;
          final veri =
              'Köşeleri bir çember üzerinde olan ABC üçgeninde, çembere A '
              'noktasında teğet olan doğru üzerinde A noktasının farklı '
              'yanlarında T ve K noktaları alınıyor. TAB açısının ölçüsü $u°, '
              'KAC açısının ölçüsü $v° olduğuna göre';
          if (ikinci) {
            return _aci(
              '$veri A noktasını içermeyen BC yayının ölçüsü kaç derecedir?',
              2 * t,
              [t, 2 * (u + v), 2 * u, 2 * v],
              'T, A ve K doğrusal olduğundan BAC = 180° − $u° − $v° = $t° '
              'olur. BAC çevre açısının gördüğü BC yayı 2·$t° = ${2 * t}°.',
              ust: 360,
            );
          }
          return _aci(
            '$veri BAC açısının ölçüsü kaç derecedir?',
            t,
            [u + v, 180 - u, 180 - v],
            'T, A ve K noktaları doğrusal olduğundan TAB + BAC + KAC = 180° '
            'olur. BAC = 180° − $u° − $v° = $t°.',
          );
        case 2:
          final al = 70 + 2 * a, u = 12 + 2 * b;
          if (ikinci) {
            return _aci(
              'ABCD kirişler dörtgeninde BAD açısının ölçüsü $al°, ABD '
              'açısının ölçüsü $u° olduğuna göre ACB açısının ölçüsü kaç '
              'derecedir?',
              180 - al - u,
              [al - u, 180 - al, 180 - u, u],
              'ABD üçgeninde ADB = 180° − $al° − $u° = ${180 - al - u}° olur. '
              'ACB ve ADB çevre açıları aynı AB yayını gördüğünden ACB = '
              '${180 - al - u}°.',
            );
          }
          return _aci(
            'ABCD kirişler dörtgeninde BAD açısının ölçüsü $al°, CBD açısının '
            'ölçüsü $u° olduğuna göre BDC açısının ölçüsü kaç derecedir?',
            al - u,
            [180 - al - u, 180 - al + u, al + u, 180 - al],
            'Kirişler dörtgeninde karşılıklı açılar bütünlerdir: BCD = 180° − '
            '$al° = ${180 - al}°. BCD üçgeninde BDC = 180° − ${180 - al}° − '
            '$u° = ${al - u}°.',
          );
        case 3:
          final u = 15 + a, v = 20 + b, t = u + v;
          final veri =
              'O merkezli bir çember üzerinde A, B ve C noktaları alınıyor; O '
              'noktası ABC açısının iç bölgesindedir. OAB açısının ölçüsü $u°, '
              'OCB açısının ölçüsü $v° olduğuna göre';
          final cozum =
              '|OA| = |OB| = |OC| olduğundan OBA = $u° ve OBC = $v° olur; '
              'ABC = $u° + $v° = $t°.';
          if (ikinci) {
            return _aci(
              '$veri ABC açısının ölçüsü kaç derecedir?',
              t,
              [2 * t, 180 - t, 180 - 2 * t, (u - v).abs()],
              cozum,
            );
          }
          return _aci(
            '$veri AOC açısının ölçüsü kaç derecedir?',
            2 * t,
            [t, 180 - t, 360 - 2 * t, 180 - 2 * t],
            '$cozum Merkez açı aynı yayı gören çevre açının iki katıdır: AOC = '
            '2·$t° = ${2 * t}°.',
            ust: 360,
          );
        default:
          final u = 20 + 2 * a, v = 15 + 3 * b;
          final veri =
              '[AB] çaplı bir çember üzerinde, AB doğrusunun farklı yanlarında '
              'C ve D noktaları alınıyor. CAB açısının ölçüsü $u°, DBA '
              'açısının ölçüsü $v° olduğuna göre';
          const cap = 'Çapı gören çevre açı 90° olduğundan ACB = ADB = 90° '
              'olur.';
          if (ikinci) {
            return _aci(
              '$veri CBD açısının ölçüsü kaç derecedir?',
              90 - u + v,
              [u + v, 90 + u - v, 180 - u - v, 90 - u],
              '$cap ABC üçgeninde CBA = 90° − $u° = ${90 - u}° bulunur. '
              'CBD = ${90 - u}° + $v° = ${90 - u + v}°.',
            );
          }
          return _aci(
            '$veri CAD açısının ölçüsü kaç derecedir?',
            90 + u - v,
            [u + v, 90 - u + v, 180 - u - v, 90 - v],
            '$cap ABD üçgeninde DAB = 90° − $v° = ${90 - v}° bulunur. '
            'CAD = $u° + ${90 - v}° = ${90 + u - v}°.',
          );
      }
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 13 · Kirişin merkeze uzaklığı, teğet parçası ve çemberde kuvvet.
  lmAile(
    'geo_kiris',
    'Kiriş, teğet parçası ve çemberde kuvvet',
    _mat,
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) {
      final ikinci = c >= 5, g = 1 + a;
      final (s, t) = _oran[b];
      switch (c % 5) {
        case 0:
          const kural = 'Merkezden kirişe inen dikme kirişi ortalar';
          if (ikinci) {
            final h = g * t, d = g * s, k = s * s + t * t;
            return _koklu(
              'Bir çemberde uzunluğu ${2 * h} cm olan kirişin merkeze uzaklığı '
              '$d cm olduğuna göre bu çemberin yarıçapı kaç cm olur?',
              (g, k),
              [(g, 4 * t * t + s * s), (h + d, 1), (g, t * t - s * s)],
              '$kural; yarım kiriş $h cm olur. r² = $h² + $d² = '
              '${h * h + d * d}, r = ${_kok(g, k)} cm.',
            );
          }
          final r = g * t, d = g * s, k = t * t - s * s;
          return _koklu(
            'Yarıçapı $r cm olan bir çemberde, merkeze uzaklığı $d cm olan '
            'kirişin uzunluğu kaç cm olur?',
            (2 * g, k),
            [(g, k), (2 * g, t * t + s * s), (2 * (r - d), 1)],
            '$kural. Yarım kirişin karesi $r² − $d² = ${r * r - d * d} '
            'olduğundan yarım kiriş ${_kok(g, k)} cm, kirişin tamamı '
            '${_kok(2 * g, k)} cm olur.',
          );
        case 1:
          const giris =
              'cm yarıçaplı bir çembere, dışındaki bir P noktasından çizilen '
              'teğet çembere T noktasında değiyor.';
          const kural = 'Teğet, değme noktasındaki yarıçapa diktir';
          final r = g * s;
          if (ikinci) {
            final pt = g * t, k = s * s + t * t;
            return _koklu(
              'O merkezli ve $r $giris |PT| = $pt cm olduğuna göre |PO| kaç cm '
              'olur?',
              (g, k),
              [(r + pt, 1), (g, t * t - s * s), (g, 4 * s * s + t * t)],
              '$kural; OTP dik üçgeninde |PO|² = $r² + $pt² = '
              '${r * r + pt * pt}, |PO| = ${_kok(g, k)} cm.',
            );
          }
          final po = g * t, k = t * t - s * s;
          return _koklu(
            'O merkezli ve $r $giris |PO| = $po cm olduğuna göre |PT| kaç cm '
            'olur?',
            (g, k),
            [(g, t * t + s * s), (po - r, 1), (po + r, 1)],
            '$kural; OTP dik üçgeninde |PT|² = $po² − $r² = '
            '${po * po - r * r}, |PT| = ${_kok(g, k)} cm.',
          );
        case 2:
          final x = 2 * (1 + a), k = 2 + b % 2, y = 3 + 2 * (b ~/ 2);
          final pb = y * k, pd = x * k;
          final veri =
              'Bir çemberde [AB] ve [CD] kirişleri çemberin iç bölgesindeki P '
              'noktasında kesişiyor. |PA| = $x cm, |PB| = $pb cm ve |PC| = '
              '$y cm olduğuna göre';
          final cozum =
              'Kesişen kirişlerde |PA|·|PB| = |PC|·|PD| olur: $x·$pb = '
              '$y·|PD|, |PD| = ${x * pb} / $y = $pd cm.';
          if (ikinci) {
            return sayisal(
              '$veri [CD] kirişinin uzunluğu kaç cm olur?',
              y + pd,
              [pd, x + pb, pb + y],
              '$cozum |CD| = $y + $pd = ${y + pd} cm.',
              unit: 'cm',
              positive: true,
            );
          }
          return sayisal(
            '$veri |PD| kaç cm olur?',
            pd,
            [x + pb - y, y + pd, x * y, pb],
            cozum,
            unit: 'cm',
            positive: true,
          );
        case 3:
          final pa = g * s, pb = g * t, ab = pb - pa;
          const giris =
              'Bir çemberin dışındaki P noktasından çizilen teğet çembere T '
              'noktasında değiyor; P noktasından geçen bir kesen ise çemberi '
              'sırasıyla A ve B noktalarında kesiyor.';
          final veri = ikinci
              ? '|PA| = $pa cm ve |PB| = $pb cm'
              : '|PA| = $pa cm ve |AB| = $ab cm';
          return _koklu(
            '$giris $veri olduğuna göre |PT| kaç cm olur?',
            (g, s * t),
            [(g, s * (t - s)), (g * g * s * t, 1), (g, s * (s + t)), (pb, 1)],
            '${ikinci ? '' : '|PB| = $pa + $ab = $pb cm olur. '}Teğet-kesen '
            'bağıntısına göre |PT|² = |PA|·|PB| = $pa·$pb = ${pa * pb}, '
            '|PT| = ${_kok(g, s * t)} cm.',
          );
        default:
          final x = 5 + a, y = x + 1 + b % 4, k = 2 + b ~/ 4;
          final pb = y * k, pd = x * k, ab = pb - x;
          final veri =
              'Bir çemberin dışındaki P noktasından çizilen iki kesenden biri '
              'çemberi sırasıyla A ve B, diğeri sırasıyla C ve D noktalarında '
              'kesiyor. |PA| = $x cm, |AB| = $ab cm ve |PC| = $y cm olduğuna '
              'göre';
          final cozum =
              '|PB| = $x + $ab = $pb cm olur. Kuvvet bağıntısına göre '
              '|PA|·|PB| = |PC|·|PD|: $x·$pb = $y·|PD|, |PD| = $pd cm.';
          if (ikinci) {
            return sayisal(
              '$veri |CD| kaç cm olur?',
              pd - y,
              [pd, ab, x * ab ~/ y, pb - y],
              '$cozum |CD| = $pd − $y = ${pd - y} cm.',
              unit: 'cm',
              positive: true,
            );
          }
          return sayisal(
            '$veri |PD| kaç cm olur?',
            pd,
            [pb, x * ab ~/ y, pd - y, y + ab],
            cozum,
            unit: 'cm',
            positive: true,
          );
      }
    },
    exam: ExamKind.tyt,
    lesson: _tm,
    shortAnswer: false,
  ),
  // 14 · Dikdörtgenler prizması ve küp: hacim, yüzey alanı, cisim köşegeni.
  lmAile(
    'geo_prizma',
    'Dikdörtgenler prizması ve küp',
    _mat,
    Difficulty.easy,
    BloomLevel.uygulama,
    (a, b, c) {
      final ikinci = c >= 5;
      if (c % 5 == 4) {
        final g = ikinci ? 3 : 2;
        final p = 2 + a, q = 2 + b, h = 2 + (a + b) % 5, n = p * q * h;
        return sayisal(
          'Ayrıt uzunlukları ${g * p} cm, ${g * q} cm ve ${g * h} cm olan '
          'dikdörtgenler prizması biçimindeki bir kutu, bir ayrıtı $g cm olan '
          'küplerle hiç boşluk kalmayacak biçimde dolduruluyor. Buna göre '
          'kutuya kaç küp yerleştirilir?',
          n,
          [n * g, n * g * g, n * g * g * g, p + q + h],
          'Ayrıtlar boyunca sırasıyla ${g * p} / $g = $p, ${g * q} / $g = $q '
          've ${g * h} / $g = $h küp sığar. Toplam $p·$q·$h = $n küp.',
          positive: true,
        );
      }
      if (c % 5 == 2) {
        final g = 1 + a;
        final (s, t, u) = _ayrit[b];
        final sig = s * s + t * t + u * u;
        final p = g * s, q = g * t, h = g * u;
        if (ikinci) {
          return _koklu(
            'Taban ayrıtları $p cm ve $q cm, cisim köşegeni ${_kok(g, sig)} cm '
            'olan dikdörtgenler prizmasının yüksekliği kaç cm olur?',
            (h, 1),
            [(g, sig + s * s + t * t), (g, sig - s * s), (g, sig - t * t)],
            'Cisim köşegeninin karesi üç ayrıtın kareleri toplamıdır: '
            '${g * g * sig} = $p² + $q² + h². Buradan h² = ${h * h}, '
            'h = $h cm.',
          );
        }
        return _koklu(
          'Taban ayrıtları $p cm ve $q cm, yüksekliği $h cm olan dikdörtgenler '
          'prizmasının cisim köşegeni kaç cm olur?',
          (g, sig),
          [(g, s * s + t * t), (p + q + h, 1), (g, s * s + u * u)],
          'Cisim köşegeninin karesi üç ayrıtın kareleri toplamıdır: $p² + $q² '
          '+ $h² = ${g * g * sig}. Köşegen ${_kok(g, sig)} cm olur.',
        );
      }
      final p = 3 + a, q = 2 + b, h = 2 + (a + 2 * b) % 7 + (ikinci ? 7 : 0);
      final v = p * q * h, alan = 2 * (p * q + p * h + q * h);
      const giris = 'Taban ayrıtları';
      return switch (c % 5) {
        0 => sayisal(
          '$giris $p cm ve $q cm, yüksekliği $h cm olan dikdörtgenler '
              'prizmasının hacmi kaç cm³ olur?',
          v,
          [alan, alan ~/ 2, v ~/ 2, 4 * (p + q + h)],
          'Hacim üç ayrıtın çarpımıdır: $p·$q·$h = $v cm³.',
          unit: 'cm³',
          positive: true,
        ),
        1 => sayisal(
          '$giris $p cm ve $q cm, yüksekliği $h cm olan dikdörtgenler '
              'prizmasının yüzey alanı kaç cm² olur?',
          alan,
          [alan ~/ 2, v, 2 * (p * h + q * h) + p * q, 2 * (p * h + q * h)],
          'Yüzey alanı 2·(${p * q} + ${p * h} + ${q * h}) = '
              '2·${alan ~/ 2} = $alan cm².',
          unit: 'cm²',
          positive: true,
        ),
        _ => sayisal(
          '$giris $p cm ve $q cm, hacmi $v cm³ olan dikdörtgenler prizmasının '
              'yüksekliği kaç cm olur?',
          h,
          [v ~/ (p + q), 2 * h, v ~/ (2 * p * q), h + q],
          'Hacim taban alanı ile yüksekliğin çarpımıdır: $p·$q·h = $v, '
              'h = $v / ${p * q} = $h cm.',
          unit: 'cm',
          positive: true,
        ),
      };
    },
    exam: ExamKind.tyt,
    lesson: _tm,
    shortAnswer: false,
  ),
  // 15 · Silindir, koni ve kürede hacim ve yüzey alanı (π cinsinden).
  lmAile(
    'geo_silindir_koni_kure',
    'Silindir, koni ve kürede hacim ve yüzey alanı',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final r = 2 + a, hh = b + 20 * (c ~/ 5), h = 3 + hh;
      const silindir = 'olan dik dairesel silindirin';
      switch (c % 5) {
        case 0:
          return sayisal(
            'Taban yarıçapı $r cm, yüksekliği $h cm $silindir hacmi kaç π cm³ '
            'olur?',
            r * r * h,
            [2 * r * h, r * h * h, 2 * r * r * h, r * r * h ~/ 3],
            'Silindirin hacmi πr²h = π·$r²·$h = π·${r * r}·$h = '
            '${r * r * h}π cm³.',
            positive: true,
          );
        case 1:
          return sayisal(
            'Taban yarıçapı $r cm, yüksekliği $h cm $silindir yanal yüzey '
            'alanı kaç π cm² olur?',
            2 * r * h,
            [r * h, r * r * h, 2 * r * (r + h), 4 * r * h],
            'Yanal yüzey, taban çevresi ile yüksekliğin çarpımıdır: 2πrh = '
            '2π·$r·$h = ${2 * r * h}π cm².',
            positive: true,
          );
        case 2:
          return sayisal(
            'Taban yarıçapı $r cm, yüksekliği $h cm $silindir tüm yüzey alanı '
            'kaç π cm² olur?',
            2 * r * (r + h),
            [2 * r * h, r * (r + h), 2 * r * h + r * r, r * r * h],
            'Tüm yüzey alanı iki taban ile yanal yüzeyin toplamıdır: 2πr² + '
            '2πrh = 2π·$r·($r + $h) = ${2 * r * (r + h)}π cm².',
            positive: true,
          );
        case 3:
          final n = 1 + hh ~/ 2;
          if (hh.isEven) {
            return sayisal(
              'Taban yarıçapı $r cm, yüksekliği ${3 * n} cm olan dik dairesel '
              'koninin hacmi kaç π cm³ olur?',
              r * r * n,
              [3 * r * r * n, 2 * r * n, r * n * n * 3, 2 * r * r * n],
              'Koninin hacmi πr²h / 3 = π·${r * r}·${3 * n} / 3 = '
              '${r * r * n}π cm³.',
              positive: true,
            );
          }
          final yuk = r + 3 * n, v = r * r * (r + n);
          return sayisal(
            'Taban yarıçapı $r cm, yüksekliği $yuk cm olan dik dairesel bir '
            'koninin tabanına, yarıçapı $r cm olan bir yarım küre düz '
            'yüzünden yapıştırılıyor. Oluşan cismin hacmi kaç π cm³ olur?',
            v,
            [
              r * r * yuk ~/ 3,
              r * r * (yuk + 4 * r) ~/ 3,
              r * r * (yuk + 2 * r),
              2 * r * r * r ~/ 3,
            ],
            'Koninin hacmi π·${r * r}·$yuk / 3, yarım kürenin hacmi '
            '(2/3)·π·$r³ olur. Toplam π·${r * r}·($yuk + ${2 * r}) / 3 = '
            '$vπ cm³.',
            positive: true,
          );
        default:
          final s = r * (3 * r + 2 * h);
          return sayisal(
            'Taban yarıçapı $r cm, yüksekliği $h cm $silindir üst tabanına, '
            'yarıçapı $r cm olan bir yarım küre düz yüzünden yapıştırılıyor. '
            'Oluşan cismin dış yüzey alanı kaç π cm² olur?',
            s,
            [r * (4 * r + 2 * h), r * (2 * r + 2 * h), r * (3 * r + h), r * r * h],
            'Dış yüzey; alt taban πr², yanal yüzey 2πrh ve yarım kürenin '
            'yüzeyi 2πr² toplamıdır: π·${r * r} + 2π·$r·$h + 2π·${r * r} = '
            '$sπ cm².',
            positive: true,
          );
      }
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 16 · Analitik düzlemde uzaklık, orta nokta ve ağırlık merkezi.
  lmAile(
    'geo_analitik_nokta',
    'İki nokta arası uzaklık, orta nokta, ağırlık merkezi',
    _mat,
    Difficulty.easy,
    BloomLevel.uygulama,
    (a, b, c) {
      final j = c ~/ 3, isaret = (a + b).isEven ? 1 : -1;
      if (c % 3 == 0) {
        final x1 = j - 2, y1 = 3 - 2 * j;
        final dx = a < 12 ? a - 12 : a - 11, dy = b < 10 ? b - 10 : b - 9;
        final x2 = x1 + dx, y2 = y1 + dy, k = dx * dx + dy * dy;
        final sx = x1 + x2, sy = y1 + y2;
        return _koklu(
          'Analitik düzlemde A${_n(x1, y1)} ve B${_n(x2, y2)} noktaları '
          'arasındaki uzaklık kaç birimdir?',
          (1, k),
          [
            (dx.abs() + dy.abs(), 1),
            (1, sx * sx + sy * sy),
            (1, (dx * dx - dy * dy).abs()),
            (k, 1),
          ],
          'Koordinat farkları ${_m(x2)} − ${_pz(x1)} = ${_m(dx)} ve ${_m(y2)} '
          '− ${_pz(y1)} = ${_m(dy)} olur. |AB| = √(${_pz(dx)}² + '
          '${_pz(dy)}²) = √$k${_kok(1, k) == '√$k' ? '' : ' = ${_kok(1, k)}'} '
          'birim.',
        );
      }
      if (c % 3 == 1) {
        final ax = a - 12, ay = b - 9;
        final (ox, oy) = const [(3, -2), (-4, 5), (2, 6)][j];
        final mx = ax + isaret * ox, my = ay + isaret * oy;
        final bx = 2 * mx - ax, by = 2 * my - ay;
        return _noktali(
          'Analitik düzlemde A${_n(ax, ay)} ve B noktalarının orta noktası '
          'M${_n(mx, my)} olduğuna göre B noktasının koordinatları '
          'aşağıdakilerden hangisidir?',
          (bx, by),
          [(2 * ax - mx, 2 * ay - my), (mx - ax, my - ay), (mx + ax, my + ay)],
          'Orta nokta koordinatların ortalamasıdır; B(x, y) için x = '
          '2·${_pz(mx)} − ${_pz(ax)} = ${_m(bx)} ve y = 2·${_pz(my)} − '
          '${_pz(ay)} = ${_m(by)} bulunur.',
        );
      }
      final gx = a - 12, gy = b - 10;
      final (o1, o2) = const [
        ((3, -1), (-2, 4)),
        ((-4, -2), (1, 5)),
        ((2, 6), (3, -4)),
      ][j];
      final ax = gx + isaret * o1.$1, ay = gy + isaret * o1.$2;
      final bx = gx + isaret * o2.$1, by = gy + isaret * o2.$2;
      final cx = 3 * gx - ax - bx, cy = 3 * gy - ay - by;
      return _noktali(
        'Analitik düzlemde köşeleri A${_n(ax, ay)}, B${_n(bx, by)} ve '
        'C${_n(cx, cy)} olan ABC üçgeninin ağırlık merkezinin koordinatları '
        'aşağıdakilerden hangisidir?',
        (gx, gy),
        [(3 * gx, 3 * gy), (gy, gx), (-gx, -gy)],
        'Ağırlık merkezi köşe koordinatlarının ortalamasıdır: x = '
        '(${_pz(ax)} + ${_pz(bx)} + ${_pz(cx)}) / 3 = ${_m(gx)}, y = '
        '(${_pz(ay)} + ${_pz(by)} + ${_pz(cy)}) / 3 = ${_m(gy)}.',
      );
    },
    exam: ExamKind.ayt,
    lesson: _aytMat,
    shortAnswer: false,
  ),
  // 17 · Doğrunun eğimi ve denklemi, paralel ve dik doğrular, eksen kesimleri.
  lmAile(
    'geo_dogru',
    'Doğrunun eğimi, denklemi ve eksenleri kestiği noktalar',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final ikinci = c >= 5;
      switch (c % 5) {
        case 0 || 3:
          final dik = c % 5 == 3;
          final dx = 1 + a, dy = b < 10 ? b - 10 : b - 9;
          final x1 = a % 7 - 3, y1 = b % 5 - 2 + (ikinci ? 6 : 0);
          final x2 = x1 + dx, y2 = y1 + dy;
          final egim = _kesir(dy, dx), ham = '${_m(dy)}/$dx';
          final cozum =
              'AB doğrusunun eğimi (${_m(y2)} − ${_pz(y1)}) / (${_m(x2)} − '
              '${_pz(x1)}) = $ham${ham == egim ? '' : ' = $egim'} olur.';
          final noktalar = 'A${_n(x1, y1)} ve B${_n(x2, y2)}';
          if (dik) {
            return secenekli(
              'Analitik düzlemde $noktalar noktalarından geçen doğruya dik '
              'olan bir doğrunun eğimi kaçtır?',
              _kesir(-dx, dy),
              [
                egim,
                _kesir(dx, dy),
                _kesir(-dy, dx),
                _kesir(-dx - 1, dy),
                _kesir(-2 * dx, dy),
                _kesir(-dx, 2 * dy),
              ],
              '$cozum Dik doğruların eğimleri çarpımı −1 olduğundan aranan '
              'eğim ${_kesir(-dx, dy)} bulunur.',
            );
          }
          return secenekli(
            'Analitik düzlemde $noktalar noktalarından geçen doğrunun eğimi '
            'kaçtır?',
            egim,
            [
              _kesir(dx, dy),
              _kesir(-dy, dx),
              _kesir(-dx, dy),
              _kesir(dy + 1, dx),
              _kesir(2 * dy, dx),
              _kesir(dy, 2 * dx),
            ],
            'Eğim, ordinatlar farkının apsisler farkına oranıdır. $cozum',
          );
        case 1:
          final x0 = a < 12 ? a - 12 : a - 11, y0 = b - 8;
          final m = ikinci ? -(1 + (a + b) % 3) : 2 + (a + b) % 3;
          final n = y0 - m * x0;
          return _tam(
            'Analitik düzlemde eğimi ${_m(m)} olan ve A${_n(x0, y0)} '
            'noktasından geçen doğrunun y eksenini kestiği noktanın ordinatı '
            'kaçtır?',
            n,
            [y0 + m * x0, m * x0 - y0, x0 - m * y0, y0 - x0],
            'Doğrunun denklemi y − ${_pz(y0)} = ${_m(m)}·(x − ${_pz(x0)}) '
            'olur. x = 0 yazılırsa y = ${_m(y0)} − ${_pz(m)}·${_pz(x0)} = '
            '${_m(n)} bulunur.',
          );
        case 2:
          final (p, q) = const [
            (1, 2), (2, 1), (1, -3), (3, -1), (2, 3),
            (3, 2), (2, -5), (5, -2), (3, 4), (4, -3),
          ][b % 10];
          final r = 1 + b ~/ 10 + (ikinci ? 2 : 0), x0 = a - 12;
          var y0 = (a + b) % 5 - 2;
          if (p * x0 + q * y0 + r == 0) y0++;
          final k = -(p * x0 + q * y0);
          return secenekli(
            'Analitik düzlemde A${_n(x0, y0)} noktasından geçen ve '
            '${_dnk(p, q, r)} doğrusuna paralel olan doğrunun denklemi '
            'aşağıdakilerden hangisidir?',
            _dnk(p, q, k),
            [
              _dnk(p, q, -k),
              _dnk(q, -p, -(q * x0 - p * y0)),
              _dnk(p, -q, -(p * x0 - q * y0)),
              _dnk(q, p, -(q * x0 + p * y0)),
              _dnk(p, q, k + r),
            ],
            'Paralel doğruların x ve y katsayıları orantılıdır; aranan doğru '
            '${_ifade([(p, 'x'), (q, 'y')])} + k = 0 biçimindedir. A '
            'noktasının koordinatları yerine yazılırsa $p·${_pz(x0)} + '
            '${_pz(q)}·${_pz(y0)} + k = 0, k = ${_m(k)} bulunur.',
          );
        default:
          final x = 2 * (1 + a), y = 1 + b, g = x.gcd(y);
          final ka = y ~/ g, kb = x ~/ g, kc = x * y ~/ g;
          final denklem =
              '${_ifade([(ka, 'x'), (ikinci ? -kb : kb, 'y')])} = $kc';
          return sayisal(
            'Analitik düzlemde $denklem doğrusu ile koordinat eksenleri '
            'arasında kalan üçgensel bölgenin alanı kaç birimkaredir?',
            x * y ~/ 2,
            [x * y, x + y, kc ~/ 2, x * y ~/ 4, kc],
            'y = 0 için x = $kc / $ka = $x, x = 0 için y = '
            '${ikinci ? '−' : ''}$y bulunur. Dik kenarları $x ve $y birim '
            'olan dik üçgenin alanı $x·$y / 2 = ${x * y ~/ 2} birimkaredir.',
            positive: true,
          );
      }
    },
    exam: ExamKind.ayt,
    lesson: _aytMat,
    shortAnswer: false,
  ),
  // 18 · Noktanın doğruya uzaklığı ve paralel iki doğru arasındaki uzaklık.
  lmAile(
    'geo_uzaklik',
    'Noktanın doğruya ve paralel doğruların uzaklığı',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final (ka, kb, h) = _normal[c ~/ 2];
      final payda = '√(${ka * ka} + ${kb * kb}) = $h';
      String sonuc(int n) =>
          '$n/$h${kesir(n, h) == '$n/$h' ? '' : ' = ${kesir(n, h)}'}';
      if (c.isEven) {
        final x0 = a - 12, y0 = b - 10, t = ka * x0 + kb * y0;
        var k = ((a + 2 * b) % 9 + 1) * ((a + b).isEven ? 1 : -1);
        if (t + k == 0) k++;
        final n = (t + k).abs();
        return kesirli(
          'Analitik düzlemde A${_n(x0, y0)} noktasının ${_dnk(ka, kb, k)} '
          'doğrusuna uzaklığı kaç birimdir?',
          n,
          h,
          [
            ((t - k).abs(), h),
            (n, h * h),
            (n, 1),
            (t.abs(), h),
            (n, ka.abs() + kb.abs()),
          ].where((e) => e.$1 > 0),
          'Pay |$ka·${_pz(x0)} + ${_pz(kb)}·${_pz(y0)} + ${_pz(k)}| = $n, '
          'payda $payda olur. Uzaklık ${sonuc(n)} birimdir.',
        );
      }
      final c1 = a - 12, d = 1 + b + a % 4, c2 = c1 + d;
      final kat = (a + b).isEven ? 1 : 2;
      return kesirli(
        'Analitik düzlemde ${_dnk(ka, kb, c1)} ve '
        '${_dnk(kat * ka, kat * kb, kat * c2)} paralel doğruları arasındaki '
        'uzaklık kaç birimdir?',
        d,
        h,
        [
          ((c1 - kat * c2).abs(), h),
          ((c1 + c2).abs(), h),
          (d, h * h),
          (d, 1),
          (d, ka.abs() + kb.abs()),
        ].where((e) => e.$1 > 0),
        '${kat == 2 ? 'İkinci denklem 2 ile sadeleştirilirse '
                  '${_dnk(ka, kb, c2)} olur. ' : ''}Katsayıları aynı olan '
        'paralel doğrularda pay |${_m(c1)} − ${_pz(c2)}| = $d, payda $payda '
        'olur. Uzaklık ${sonuc(d)} birimdir.',
      );
    },
    exam: ExamKind.ayt,
    lesson: _aytMat,
  ),
  // 19 · Çember denklemi: merkez, yarıçap ve bir noktanın çembere göre konumu.
  lmAile(
    'geo_cember_denklem',
    'Çember denklemi: merkez, yarıçap ve nokta konumu',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final ikinci = c >= 5;
      final h = a - 12, k = b - 10, r = 2 + (a + b) % 6 + (ikinci ? 6 : 0);
      final sx = a.isEven ? 1 : -1, sy = b.isEven ? 1 : -1;
      final std = _cember(h, k, r * r);
      final genel = '${_ifade([
        (1, 'x²'),
        (1, 'y²'),
        (-2 * h, 'x'),
        (-2 * k, 'y'),
        (h * h + k * k - r * r, ''),
      ])} = 0';
      final tamKare =
          'Denklem tam kareye tamamlanırsa $std biçimine gelir';
      switch (c % 5) {
        case 0:
          return _tam(
            'Analitik düzlemde denklemi $std olan çemberin merkezi M(a, b) ve '
            'yarıçapı r birim olduğuna göre a + b + r toplamı kaçtır?',
            h + k + r,
            [-h - k + r, h + k + r * r, -h - k + r * r, h + k - r],
            'Merkez M${_n(h, k)} ve r² = ${r * r} olduğundan r = $r bulunur. '
            'a + b + r = ${_m(h)} + ${_pz(k)} + $r = ${_m(h + k + r)}.',
          );
        case 1:
          return sayisal(
            'Analitik düzlemde denklemi $genel olan çemberin yarıçapı kaç '
            'birimdir?',
            r,
            [r * r, 2 * r, r + 2],
            '$tamKare; r² = ${r * r} olduğundan yarıçap $r birimdir.',
            positive: true,
          );
        case 2:
          return _noktali(
            'Analitik düzlemde denklemi $genel olan çemberin merkezinin '
            'koordinatları aşağıdakilerden hangisidir?',
            (h, k),
            [(-h, -k), (-2 * h, -2 * k), (2 * h, 2 * k), (k, h)],
            '$tamKare; merkez M${_n(h, k)} noktasıdır.',
          );
        case 3:
          final durum = (a + b) % 3;
          final (dx, dy) = switch (durum) {
            0 => (sx * (r - 2), sy),
            1 => (sx * r, sy),
            _ => switch (r) {
              5 => (3 * sx, 4 * sy),
              10 => (6 * sx, 8 * sy),
              13 => (5 * sx, 12 * sy),
              _ => (sx * r, 0),
            },
          };
          final px = h + dx, py = k + dy, d2 = dx * dx + dy * dy;
          final isaret = const ['<', '>', '='][durum];
          return secenekli(
            'Analitik düzlemde denklemi $std olan çembere göre P${_n(px, py)} '
            'noktasının konumu aşağıdakilerden hangisinde doğru verilmiştir?',
            _konum[durum],
            [
              for (var i = 0; i < 4; i++)
                if (i != durum) _konum[i],
            ],
            'Merkez M${_n(h, k)}, yarıçap $r birimdir. |PM|² = ${_pz(dx)}² + '
            '${_pz(dy)}² = $d2 ve r² = ${r * r} olur. $d2 $isaret ${r * r} '
            'olduğundan P noktası ${const [
              'çemberin iç bölgesindedir',
              'çemberin dış bölgesindedir',
              'çemberin üzerindedir',
            ][durum]}.',
          );
        default:
          final dx = sx * (1 + (a + b) % 4);
          final dy = sy * (1 + a % 3 + (ikinci ? 3 : 0));
          final ax = h + dx, ay = k + dy, r2 = dx * dx + dy * dy;
          final top = dx.abs() + dy.abs();
          return secenekli(
            'Analitik düzlemde merkezi M${_n(h, k)} olan ve A${_n(ax, ay)} '
            'noktasından geçen çemberin denklemi aşağıdakilerden hangisidir?',
            _cember(h, k, r2),
            [
              _cember(-h, -k, r2),
              _cember(ax, ay, r2),
              _cember(h, k, top * top),
              _cember(h, k, top),
              _cember(h, k, 2 * r2),
            ],
            'Yarıçap |MA| olduğundan r² = ${_pz(dx)}² + ${_pz(dy)}² = $r2 '
            'bulunur. Merkezi M${_n(h, k)} olan çemberin denklemi '
            '${_cember(h, k, r2)} olur.',
          );
      }
    },
    exam: ExamKind.ayt,
    lesson: _aytMat,
    shortAnswer: false,
  ),
  // 20 · Öteleme, yansıma ve vektörlerde toplam ile uzunluk.
  lmAile(
    'geo_donusum_vektor',
    'Öteleme, yansıma ve vektörlerde toplam ile uzunluk',
    _mat,
    Difficulty.medium,
    BloomLevel.anlama,
    (a, b, c) {
      final ikinci = c >= 5;
      final x = a < 12 ? a - 12 : a - 11, y = b < 10 ? b - 10 : b - 9;
      final v1 = (1 + (a + b) % 4) * (a.isEven ? 1 : -1);
      var v2 = (1 + (a + 2 * b) % 5) * (b.isEven ? -1 : 1);
      const vektorler = 'vektörleri veriliyor. Buna göre';
      switch (c % 5) {
        case 0:
          final p = 2 + (a + b) % 5, q = 1 + (a + 2 * b) % 6;
          final tx = ikinci ? -p : p, ty = ikinci ? q : -q;
          return _noktali(
            'Analitik düzlemde A${_n(x, y)} noktası x ekseni doğrultusunda $p '
            'birim ${ikinci ? 'sola' : 'sağa'}, y ekseni doğrultusunda $q '
            'birim ${ikinci ? 'yukarı' : 'aşağı'} öteleniyor. Elde edilen '
            'noktanın koordinatları aşağıdakilerden hangisidir?',
            (x + tx, y + ty),
            [(x - tx, y + ty), (x + tx, y - ty), (x - tx, y - ty)],
            '${ikinci ? 'Sola' : 'Sağa'} öteleme apsisi $p '
            '${ikinci ? 'azaltır' : 'artırır'}, ${ikinci ? 'yukarı' : 'aşağı'} '
            'öteleme ordinatı $q ${ikinci ? 'artırır' : 'azaltır'}: '
            '(${_m(x)} ${ikinci ? '−' : '+'} $p, ${_m(y)} '
            '${ikinci ? '+' : '−'} $q) = ${_n(x + tx, y + ty)}.',
          );
        case 1:
          final (i1, i2) = const [
            (0, 3), (1, 3), (3, 0), (2, 3), (3, 1), (0, 2),
          ][(a + b) % 3 + (ikinci ? 3 : 0)];
          final yy = y > 0 ? y + 13 : y - 13;
          final p0 = (x, yy), p1 = _yansit(i1, p0), p2 = _yansit(i2, p1);
          final ters = _yansit(i1, _yansit(i2, p0));
          return _noktali(
            'Analitik düzlemde A${_n(x, yy)} noktasının önce ${_yansima[i1]} '
            'göre, ardından elde edilen noktanın ${_yansima[i2]} göre '
            'yansıması alınıyor. Son durumda elde edilen noktanın '
            'koordinatları aşağıdakilerden hangisidir?',
            p2,
            [p1, _yansit(i2, p0), ters, (-x, -yy), (yy, x), (x, -yy), (-x, yy)],
            'A${_n(x, yy)} noktasının ${_yansima[i1]} göre yansıması '
            '${_n(p1.$1, p1.$2)}, bu noktanın ${_yansima[i2]} göre yansıması '
            '${_n(p2.$1, p2.$2)} olur.',
          );
        case 2:
          final veri =
              'Analitik düzlemde u = ${_n(x, y)} ve v = ${_n(v1, v2)} '
              '$vektorler';
          if (ikinci) {
            return _noktali(
              '$veri u − 2v vektörü aşağıdakilerden hangisidir?',
              (x - 2 * v1, y - 2 * v2),
              [(x + 2 * v1, y + 2 * v2), (x - v1, y - v2), (2 * x - v1, 2 * y - v2)],
              'u − 2v = (${_m(x)} − 2·${_pz(v1)}, ${_m(y)} − 2·${_pz(v2)}) = '
              '${_n(x - 2 * v1, y - 2 * v2)}.',
            );
          }
          return _noktali(
            '$veri 2u + v vektörü aşağıdakilerden hangisidir?',
            (2 * x + v1, 2 * y + v2),
            [(x + v1, y + v2), (2 * x - v1, 2 * y - v2), (x + 2 * v1, y + 2 * v2)],
            '2u + v = (2·${_pz(x)} + ${_pz(v1)}, 2·${_pz(y)} + ${_pz(v2)}) = '
            '${_n(2 * x + v1, 2 * y + v2)}.',
          );
        case 3:
          final z = ikinci ? -1 : 1;
          if (x + z * v1 == 0 && y + z * v2 == 0) v2 += v2 > 0 ? 1 : -1;
          final s1 = x + z * v1, s2 = y + z * v2, k = s1 * s1 + s2 * s2;
          final d1 = x - z * v1, d2 = y - z * v2;
          final ad = ikinci ? 'u − v' : 'u + v';
          return _koklu(
            'Analitik düzlemde u = ${_n(x, y)} ve v = ${_n(v1, v2)} '
            '$vektorler $ad vektörünün uzunluğu kaç birimdir?',
            (1, k),
            [
              (1, d1 * d1 + d2 * d2),
              (s1.abs() + s2.abs(), 1),
              (k, 1),
              (1, x * x + y * y + v1 * v1 + v2 * v2),
            ],
            '$ad = ${_n(s1, s2)} olur. Uzunluk √(${_pz(s1)}² + ${_pz(s2)}²) = '
            '√$k${_kok(1, k) == '√$k' ? '' : ' = ${_kok(1, k)}'} birimdir.',
          );
        default:
          final tx = (2 + (a + b) % 5) * (ikinci ? -1 : 1);
          final ty = (1 + (a + 2 * b) % 4) * (a.isEven ? 1 : -1);
          final bx = (3 * a + b) % 9 - 4, by = (a + 2 * b) % 7 - 3;
          return _noktali(
            'Analitik düzlemde bir öteleme A${_n(x, y)} noktasını '
            'A′${_n(x + tx, y + ty)} noktasına taşıyor. Aynı öteleme '
            'B${_n(bx, by)} noktasını hangi noktaya taşır?',
            (bx + tx, by + ty),
            [(bx - tx, by - ty), (bx + ty, by + tx), (bx + tx, by - ty)],
            'Öteleme vektörü A′ − A = ${_n(tx, ty)} olur. B noktasına '
            'uygulanırsa (${_m(bx)} + ${_pz(tx)}, ${_m(by)} + ${_pz(ty)}) = '
            '${_n(bx + tx, by + ty)} bulunur.',
          );
      }
    },
    exam: ExamKind.ayt,
    lesson: _aytMat,
    shortAnswer: false,
  ),
];
