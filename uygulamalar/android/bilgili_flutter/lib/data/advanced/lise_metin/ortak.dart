// Lise düzeyi metin soru aileleri için ortak yardımcılar.
//
// Bu klasördeki her aile yalnız metinden oluşur: görsel, etkinlik, açık uçlu
// görev veya çoklu seçim taşımaz. Her aile 5.000 ayrı vaka üretir ve her
// vakanın soru kökü aile içinde tektir.
import '../common.dart';

export '../common.dart';

/// Üç bağımsız koordinatla çalışan üreteç: a ∈ [0, 25), b ∈ [0, 20),
/// c ∈ [0, 10). Her (a, b, c) üçlüsü farklı bir soru kökü vermelidir.
typedef LmUretec = AdvancedItem Function(int a, int b, int c);

const lmAileBoyu = 5000;

/// Bu ailelerden üretilen soruların kaynak etiketi.
const lmKaynak = 'Bilgili · Lise Metin Bankası';

/// 25 × 20 × 10 koordinatlı sayısal aile.
AdvancedFamily lmAile(
  String key,
  String title,
  Topic topic,
  Difficulty difficulty,
  BloomLevel bloom,
  LmUretec build, {
  ExamKind? exam,
  String? lesson,
  bool shortAnswer = true,
}) => lmSirali(
  key,
  title,
  topic,
  difficulty,
  bloom,
  (i) => build(i % 25, i ~/ 25 % 20, i ~/ 500),
  exam: exam,
  lesson: lesson,
  shortAnswer: shortAnswer,
);

/// Doğrudan sıra numarasıyla (0 … 4999) çalışan aile. Seçki ve birleşim
/// tabanlı sözel aileler için kullanılır.
AdvancedFamily lmSirali(
  String key,
  String title,
  Topic topic,
  Difficulty difficulty,
  BloomLevel bloom,
  AdvancedItem Function(int i) build, {
  ExamKind? exam,
  String? lesson,
  bool shortAnswer = false,
}) {
  assert(bloom != BloomLevel.yaratma, 'Metin ailelerinde yaratma görevi yok');
  return AdvancedFamily(
    key: 'lm_$key',
    title: title,
    topic: topic,
    level: StudyLevel.lise,
    count: lmAileBoyu,
    difficulty: difficulty,
    bloom: bloom,
    build: build,
    exam: exam,
    lesson: lesson,
    shortAnswer: shortAnswer,
    sourceLabel: lmKaynak,
  );
}

/// Sayıyı Türkçe ondalık virgülüyle yazar; sondaki sıfırları atar.
/// `tr(2.50)` → `2,5`, `tr(3.0)` → `3`, `tr(1 / 3, 3)` → `0,333`.
String tr(num x, [int digits = 2]) {
  if (x is int) return '$x';
  if (!x.isFinite) throw StateError('Sonlu olmayan sayı: $x');
  var s = x.toStringAsFixed(digits);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  if (s == '-0') s = '0';
  return s.replaceFirst('.', ',');
}

/// Sadeleşmiş kesir: `kesir(6, 4)` → `3/2`, `kesir(8, 4)` → `2`.
String kesir(int n, int d) {
  if (d == 0) throw StateError('Payda sıfır');
  if (d < 0) return kesir(-n, -d);
  final g = n.gcd(d);
  if (g == 0) return '0';
  return d == g ? '${n ~/ g}' : '${n ~/ g}/${d ~/ g}';
}

/// Birimi varsa araya boşluk koyarak ekler.
String birimli(String value, String unit) =>
    unit.isEmpty ? value : '$value $unit';

final _sayi = RegExp(r'^([+-]?\d+(?:[,.]\d+)?)(?:/(\d+))?\s*(.*)$');
final _bosluk = RegExp(r'\s+');

String _duz(String s) =>
    s.trim().replaceAll('−', '-').replaceAll(_bosluk, ' ').toLowerCase();

/// İki seçenek aynı yazıma ya da aynı sayısal değere (aynı birimle) sahipse
/// öğrenci açısından aynıdır.
bool ayniSecenek(String x, String y) {
  final a = _duz(x), b = _duz(y);
  if (a == b) return true;
  final m = _sayi.firstMatch(a), n = _sayi.firstMatch(b);
  if (m == null || n == null) return false;
  if (m.group(3) != n.group(3)) return false;
  double value(RegExpMatch r) {
    final top = double.parse(r.group(1)!.replaceFirst(',', '.'));
    final bottom = r.group(2) == null ? 1.0 : double.parse(r.group(2)!);
    return bottom == 0 ? double.nan : top / bottom;
  }

  final u = value(m), v = value(n);
  return (u - v).abs() <= 1e-9 * (1 + u.abs() + v.abs());
}

/// Doğru yanıtı ve aday çeldiricileri alır; doğru yanıttan ve birbirinden
/// farklı ilk üç adayı çeldirici yapar. Yeterli aday yoksa hata verir.
AdvancedItem secenekli(
  String prompt,
  String correct,
  Iterable<String> alternatives,
  String explanation,
) {
  final wrong = <String>[];
  for (final s in alternatives) {
    if (s.trim().isEmpty || ayniSecenek(s, correct)) continue;
    if (wrong.any((w) => ayniSecenek(w, s))) continue;
    wrong.add(s);
    if (wrong.length == 3) break;
  }
  if (wrong.length != 3) {
    throw StateError('Eksik çeldirici: $prompt ($correct) → $wrong');
  }
  return AdvancedItem(prompt, correct, wrong, explanation);
}

/// Tam sayı yanıtlı soru. Verilen çeldiriciler yetmezse komşu değerlerle
/// tamamlar. [positive] doğruysa sıfır ve negatif çeldiriciler elenir.
AdvancedItem sayisal(
  String prompt,
  int answer,
  Iterable<int> alternatives,
  String explanation, {
  String unit = '',
  bool positive = false,
}) {
  final step = answer.abs() >= 200 ? 10 : (answer.abs() >= 40 ? 5 : 1);
  final pool = [
    ...alternatives,
    answer + step,
    answer - step,
    answer + 2 * step,
    answer - 2 * step,
    answer + 3 * step,
    answer + 4 * step,
    answer + 5 * step,
  ].where((x) => !positive || x > 0);
  return secenekli(
    prompt,
    birimli('$answer', unit),
    pool.map((x) => birimli('$x', unit)),
    explanation,
  );
}

/// Ondalıklı yanıtlı soru. Değerler [digits] basamağa göre yazılır.
AdvancedItem ondalikli(
  String prompt,
  double answer,
  Iterable<double> alternatives,
  String explanation, {
  String unit = '',
  int digits = 2,
  bool positive = false,
}) {
  final step = answer.abs() >= 20 ? 1.0 : (answer.abs() >= 2 ? 0.5 : 0.1);
  final pool = [
    ...alternatives,
    answer + step,
    answer - step,
    answer + 2 * step,
    answer + 3 * step,
    answer + 4 * step,
    answer + 5 * step,
  ].where((x) => !positive || x > 0);
  return secenekli(
    prompt,
    birimli(tr(answer, digits), unit),
    pool.map((x) => birimli(tr(x, digits), unit)),
    explanation,
  );
}

/// Kesir yanıtlı soru. Çeldiriciler (pay, payda) ikilileridir.
AdvancedItem kesirli(
  String prompt,
  int n,
  int d,
  Iterable<(int, int)> alternatives,
  String explanation, {
  String unit = '',
}) {
  final pool = [
    ...alternatives,
    (n + 1, d),
    (n - 1, d),
    (n, d + 1),
    (n + 2, d),
    (n + 3, d),
    (n + 1, d + 1),
    (n + 4, d),
  ].where((x) => x.$2 != 0);
  return secenekli(
    prompt,
    birimli(kesir(n, d), unit),
    pool.map((x) => birimli(kesir(x.$1, x.$2), unit)),
    explanation,
  );
}

/// Listeyi döngüsel okur.
T sec<T>(List<T> items, int i) => items[i % items.length];

/// C(n, k).
int kombinasyonSayisi(int n, int k) {
  if (k < 0 || n < k) return 0;
  var r = 1;
  for (var j = 1; j <= k; j++) {
    r = r * (n - j + 1) ~/ j;
  }
  return r;
}

/// [items] içinden [k] elemanlı birleşimlerin [index] numaralı olanını
/// sözlük sırasıyla verir. C(n, k) ≥ 5000 ise her index farklı bir seçkidir;
/// [spread] doğruysa 5.000 sıra numarası tüm birleşimlere eşit aralıkla
/// yayılır, böylece listenin sonundaki ögeler de kullanılır.
List<T> kombinasyon<T>(
  List<T> items,
  int k,
  int index, {
  bool spread = true,
}) {
  final total = kombinasyonSayisi(items.length, k);
  if (total == 0) throw StateError('Yetersiz öge: ${items.length} < $k');
  var offset = spread && total >= lmAileBoyu
      ? index * total ~/ lmAileBoyu
      : index % total;
  final result = <T>[];
  var lo = 0;
  for (var slots = k; slots > 0; slots--) {
    for (var j = lo; j < items.length; j++) {
      final after = kombinasyonSayisi(items.length - j - 1, slots - 1);
      if (offset >= after) {
        offset -= after;
        continue;
      }
      result.add(items[j]);
      lo = j + 1;
      break;
    }
  }
  return result;
}

/// Üç ögenin altı diziliminden [i] numaralı olanı.
const ucluDizilimler = [
  [0, 1, 2],
  [1, 2, 0],
  [2, 0, 1],
  [0, 2, 1],
  [2, 1, 0],
  [1, 0, 2],
];
