// AYT Matematik metin aileleri (ikinci tur): toplam-fark ve iki kat açı,
// trigonometrik denklem, sinüs ve kosinüs teoremi, ters trigonometri,
// logaritma uygulamaları, fonksiyonlar, süreklilik, türev ve integral.
import 'denge.dart';
import 'ortak.dart';

// ---------------------------------------------------------------------------
// Yazım yardımcıları
// ---------------------------------------------------------------------------

const _ustRakam = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];
const _altRakam = ['₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉'];

/// Üst simge: `_ust(12)` → `¹²`.
String _ust(int n) =>
    [for (final r in '$n'.codeUnits) r == 45 ? '⁻' : _ustRakam[r - 48]].join();

/// Alt simge: `_alt(-2)` → `₋₂`.
String _alt(int n) =>
    [for (final r in '$n'.codeUnits) r == 45 ? '₋' : _altRakam[r - 48]].join();

/// İşaretli tam sayı: `_n(-3)` → `−3`.
String _n(int x) => x < 0 ? '−${-x}' : '$x';

/// İşlem içinde negatif sayı paranteze alınır: `_p(-3)` → `(−3)`.
String _p(int x) => x < 0 ? '(−${-x})' : '$x';

/// Sade kesir, eksi işareti tipografik: `_q(-6, 4)` → `−3/2`.
String _q(int n, int d) => kesir(n, d).replaceAll('-', '−');

/// Kesir ya da negatif değer işlem içinde paranteze alınır.
String _sar(String s) => s.contains('/') || s.startsWith('−') ? '($s)' : s;

/// Polinom yazımı; katsayılar büyük dereceden küçüğe verilir.
/// `_pol([1, -3, 0, 2])` → `x³ − 3x² + 2`.
String _pol(List<int> k, [String v = 'x']) {
  final sb = StringBuffer();
  final n = k.length - 1;
  for (var i = 0; i <= n; i++) {
    final c = k[i];
    if (c == 0) continue;
    final d = n - i, m = c.abs();
    final govde = d == 0
        ? '$m'
        : '${m == 1 ? '' : m}$v${d == 1 ? '' : _ust(d)}';
    if (sb.isEmpty) {
      sb.write(c < 0 ? '−$govde' : govde);
    } else {
      sb.write(c < 0 ? ' − $govde' : ' + $govde');
    }
  }
  return sb.isEmpty ? '0' : sb.toString();
}

/// Polinomun [x] noktasındaki değeri (Horner).
int _deg(List<int> k, int x) => k.fold(0, (t, c) => t * x + c);

/// Değer yerine koyma yazımı: `_yerine([1, 2, -1], -2)` →
/// `(−2)² + 2·(−2) − 1`.
String _yerine(List<int> k, int x) {
  final sb = StringBuffer();
  final n = k.length - 1;
  for (var i = 0; i <= n; i++) {
    final c = k[i];
    if (c == 0) continue;
    final d = n - i, m = c.abs();
    final us = '${_p(x)}${d == 1 ? '' : _ust(d)}';
    // x = 0 iken “−0” yazılmasın diye katsayı açık yazılır.
    final govde = d == 0
        ? '$m'
        : (m == 1 && !(x == 0 && c < 0) ? us : '$m·$us');
    if (sb.isEmpty) {
      sb.write(c < 0 ? '−$govde' : govde);
    } else {
      sb.write(c < 0 ? ' − $govde' : ' + $govde');
    }
  }
  return sb.isEmpty ? '0' : sb.toString();
}

/// Polinomun türevinin katsayıları.
List<int> _turevK(List<int> f) => [
  for (var j = 0; j < f.length - 1; j++) f[j] * (f.length - 1 - j),
];

/// [adaylar] içinden [uygun] koşulunu sağlayanların [i] numaralısı. Tipik bir
/// yanlış yolun da doğru yanıtı verdiği yozlaşmış değerleri ayıklamak için
/// kullanılır; sıra korunduğundan farklı [i] farklı değer verir.
T _uygun<T>(Iterable<T> adaylar, int i, bool Function(T) uygun) =>
    adaylar.where(uygun).elementAt(i);

/// Sıfırı atlayan tam sayı aralığı: `_sifirsizAralik(-2, 3)` → −2, −1, 1, 2, 3.
List<int> _sifirsizAralik(int bas, int son) => [
  for (var x = bas; x <= son; x++)
    if (x != 0) x,
];

/// Kare çarpanı ayırma: n = s²·f, f kare çarpansız → (s, f).
(int, int) _kokAyir(int n) {
  var s = 1, f = n;
  for (var d = 2; d * d <= f; d++) {
    while (f % (d * d) == 0) {
      f ~/= d * d;
      s *= d;
    }
  }
  return (s, f);
}

bool _kareCarpansiz(int k) => _kokAyir(k).$1 == 1;

/// n·√k/d biçiminde sade kök yazımı (k kare çarpansız): `_kok(2, 5, 5)` →
/// `2√5/5`, `_kok(-1, 2, 3)` → `−√3/2`, `_kok(3, 4, 1)` → `3/4`.
String _kok(int n, int d, int k) {
  if (k == 1) return _q(n, d);
  if (d < 0) {
    n = -n;
    d = -d;
  }
  final g = n.abs().gcd(d);
  final a = n ~/ g, b = d ~/ g, m = a.abs();
  return '${a < 0 ? '−' : ''}${m == 1 ? '' : m}√$k${b == 1 ? '' : '/$b'}';
}

/// Yarım derece biriminde verilen açının yazımı: `_yarim(15)` → `7,5`,
/// `_yarim(-60)` → `−30`.
String _yarim(int x2) => tr(x2 / 2).replaceFirst('-', '−');

/// Sade kesir: pay ve payda tam sayıdır, payda pozitiftir.
class _R {
  final int p, q;
  const _R._(this.p, this.q);

  factory _R(int p, [int q = 1]) {
    if (q == 0) throw StateError('Payda sıfır');
    if (q < 0) {
      p = -p;
      q = -q;
    }
    final g = p.gcd(q);
    return _R._(p ~/ g, q ~/ g);
  }

  _R operator +(_R o) => _R(p * o.q + o.p * q, q * o.q);
  _R operator -(_R o) => _R(p * o.q - o.p * q, q * o.q);
  _R operator *(_R o) => _R(p * o.p, q * o.q);
  _R operator /(_R o) => _R(p * o.q, q * o.p);
  _R operator -() => _R._(-p, q);

  bool get sifir => p == 0;
  bool get tam => q == 1;

  @override
  bool operator ==(Object o) => o is _R && o.p == p && o.q == q;

  @override
  int get hashCode => Object.hash(p, q);

  @override
  String toString() => _q(p, q);
}

/// Kesir, işlem içinde paranteze alınmış biçimde.
String _rs(_R x) => _sar('$x');

/// Pay ve paydayı genişletme cümlesi; çarpan 1 iken atlanır.
String _carpilirsa(int m) =>
    m == 1 ? 'Buradan ' : 'Pay ve payda $m ile çarpılırsa ';

/// Tam sayı yanıtlı soru; eksi işareti tipografik yazılır. Adaylar yetmezse
/// komşu değerlerle tamamlanır.
AdvancedItem _tam(
  String kok,
  int yanit,
  Iterable<int?> adaylar,
  String aciklama, {
  String birim = '',
  bool pozitif = false,
}) {
  if (adaylar.contains(yanit) || _yazili(kok).contains(_R(yanit))) {
    _kirli = true;
  }
  final adim = yanit.abs() >= 200 ? 10 : (yanit.abs() >= 40 ? 5 : 1);
  final havuz = [
    for (final x in adaylar) ?x,
    yanit + adim,
    yanit - adim,
    yanit + 2 * adim,
    yanit - 2 * adim,
    yanit + 3 * adim,
    yanit + 4 * adim,
    yanit + 5 * adim,
  ].where((x) => !pozitif || x > 0);
  return secenekli(
    kok,
    birimli(_n(yanit), birim),
    havuz.map((x) => birimli(_n(x), birim)),
    aciklama,
  );
}

/// Kesir yanıtlı soru. Adaylar yetmezse pay komşuları, işaret ve ters kesirle
/// tamamlanır. [aralik] verilirse yanıtın alabileceği değerlerin dışındaki
/// adaylar (ör. 1'den büyük sinüs) atılır ve aralık içinden komşu kesirler
/// eklenir. [yedek] adayları rastlantı denetimine girmez; yalnız atılan
/// adayların yerini doldurur.
AdvancedItem _ras(
  String kok,
  _R yanit,
  Iterable<_R?> adaylar,
  String aciklama, {
  bool pozitif = false,
  bool Function(_R)? aralik,
  Iterable<_R?> yedek = const [],
}) {
  if (adaylar.contains(yanit) || _yazili(kok).contains(yanit)) _kirli = true;
  final havuz = <_R>[
    for (final x in adaylar) ?x,
    for (final x in yedek) ?x,
    -yanit,
    if (!yanit.sifir && !yanit.tam) _R(yanit.q, yanit.p),
    if (yanit.tam) ...[
      yanit + _R(1),
      yanit - _R(1),
      yanit + _R(2),
      yanit - _R(2),
    ] else ...[
      _R(yanit.p + 1, yanit.q),
      _R(yanit.p - 1, yanit.q),
      _R(yanit.p + 2, yanit.q),
      _R(yanit.p, yanit.q + 1),
    ],
    yanit + _R(3),
    yanit + _R(4),
    yanit + _R(5),
    if (aralik != null) ...[
      _R(yanit.p - 2, yanit.q),
      _R(yanit.p, yanit.q + 2),
      _R(yanit.p + 1, yanit.q + 1),
      _R(yanit.p - 1, yanit.q + 1),
      for (final (u, v) in const [
        (1, 2),
        (-1, 2),
        (1, 3),
        (-1, 3),
        (2, 3),
        (-2, 3),
        (1, 4),
        (-1, 4),
        (3, 4),
        (-3, 4),
        (2, 5),
        (3, 5),
        (4, 5),
      ])
        _R(u, v),
    ],
  ].where((x) => (!pozitif || x.p > 0) && (aralik == null || aralik(x)));
  return secenekli(kok, '$yanit', havuz.map((x) => '$x'), aciklama);
}

/// −1 ≤ x ≤ 1: sinüs ve kosinüs değerleri.
bool _birlik(_R x) => x.p.abs() <= x.q;

/// −1 < x < 1: üçgen iç açısının kosinüsü.
bool _acikBirlik(_R x) => x.p.abs() < x.q;

/// 0 < x ≤ 1: üçgen iç açısının sinüsü.
bool _sinusAraligi(_R x) => x.p > 0 && x.p <= x.q;

/// Ara adım ile sonuç aynı yazılıyorsa adım tekrarlanmaz:
/// `_esit('3/4', '3/4')` → `3/4`, `_esit('6/8', '3/4')` → `6/8 = 3/4`.
String _esit(String ara, String son) => ara == son ? son : '$ara = $son';

// ---------------------------------------------------------------------------
// Rastlantı denetimi
// ---------------------------------------------------------------------------

/// Son kurulan sorunun yanıtı kökte yazılı bir sayıya ya da hatalı bir yolun
/// verdiği değere (çeldirici adaylarından birine) eşitse true olur. [_yeniden]
/// ve [_temizSec] bu bayrağa bakarak temiz seçeneği arar.
var _kirli = false;

final _sayiDeseni = RegExp(r'(?<![\d,])(−?)(\d+)(?:,(\d+))?(?:/(\d+))?');
final _sinirDeseni = RegExp('∫([₋₀₁₂₃₄₅₆₇₈₉]+)([⁻⁰¹²³⁴⁵⁶⁷⁸⁹]+)');

/// Alt ya da üst simgeyle yazılmış tam sayı: `₋₂` → −2.
int _simgeSayi(String s) {
  var n = 0, eksi = false;
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    if (ch == '₋' || ch == '⁻') {
      eksi = true;
      continue;
    }
    final i = _altRakam.indexOf(ch);
    n = n * 10 + (i >= 0 ? i : _ustRakam.indexOf(ch));
  }
  return eksi ? -n : n;
}

/// Kökte yazılı sayılar: tam ve ondalıklı sayılar, kesirler ve payları,
/// integral sınırları. "x − 3" gibi ayrık eksiyle yazılan sayı iki işaretiyle
/// de alınır.
Set<_R> _yazili(String kok) {
  final s = <_R>{};
  for (final m in _sayiDeseni.allMatches(kok)) {
    var d = _R(int.parse(m[2]!));
    final ond = m[3];
    if (ond != null) {
      var payda = 1;
      for (var i = 0; i < ond.length; i++) {
        payda *= 10;
      }
      d = d + _R(int.parse(ond), payda);
    }
    final bitisik = m[1]!.isNotEmpty;
    final ayrik =
        !bitisik && m.start >= 2 && kok.substring(m.start - 2, m.start) == '− ';
    for (final x in [d, if (m[4] != null) d / _R(int.parse(m[4]!))]) {
      s.add(bitisik ? -x : x);
      if (ayrik) s.add(-x);
    }
  }
  for (final m in _sinirDeseni.allMatches(kok)) {
    s
      ..add(_R(_simgeSayi(m[1]!)))
      ..add(_R(_simgeSayi(m[2]!)));
  }
  return s;
}

/// Seçenekli soru; çeldirici adaylarından biri yanıta eşitse soru kirli
/// sayılır.
AdvancedItem _secenek(
  String kok,
  String dogru,
  List<String> adaylar,
  String aciklama,
) {
  if (adaylar.any((x) => ayniSecenek(x, dogru))) _kirli = true;
  return secenekli(kok, dogru, adaylar, aciklama);
}

/// [kur] ile kurulan soru: 0 temiz, 1 kirli, 2 kurulamıyor.
int _durum(AdvancedItem Function() kur) {
  final once = _kirli;
  _kirli = false;
  var sonuc = 2;
  try {
    kur();
    sonuc = _kirli ? 1 : 0;
  } on StateError {
    sonuc = 2;
  }
  _kirli = once;
  return sonuc;
}

class _TemizDurum {
  var konum = 0;
  final temiz = <int>[], kirli = <int>[];
}

final _temizOnbellek = <String, _TemizDurum>{};

/// 0 … adet − 1 adaylarından temiz soru kuranlar sırayla, ardından (yetmezse)
/// kirli olanlar dizilir; bu dizinin i'inci öğesini verir. Adaylar gerektikçe
/// ve anahtar başına bir kez denenir.
int _temizSec(
  String anahtar,
  int adet,
  AdvancedItem Function(int t) kur,
  int i,
) {
  final d = _temizOnbellek.putIfAbsent(anahtar, _TemizDurum.new);
  while (d.temiz.length <= i && d.konum < adet) {
    final t = d.konum++;
    switch (_durum(() => kur(t))) {
      case 0:
        d.temiz.add(t);
      case 1:
        d.kirli.add(t);
    }
  }
  return i < d.temiz.length ? d.temiz[i] : d.kirli[i - d.temiz.length];
}

/// Listeden [kur] ile temiz soru veren i'inci öğe (temizler yetmezse kirli
/// öğelerle devam edilir).
T _temizOge<T>(
  String anahtar,
  List<T> liste,
  int i,
  AdvancedItem Function(T) kur,
) => liste[_temizSec(anahtar, liste.length, (t) => kur(liste[t]), i)];

/// deneme = 0, 1, … seçeneklerinden yanıtı rastlantıya düşmeyen ilkini kurar;
/// hiçbiri temiz değilse kurulabilen ilk seçenek kullanılır.
LmUretec _yeniden(
  AdvancedItem Function(int a, int b, int c, int deneme) kur, [
  int sayi = 8,
]) => (a, b, c) {
  AdvancedItem? ilk;
  for (var d = 0; d < sayi; d++) {
    _kirli = false;
    try {
      final soru = kur(a, b, c, d);
      if (!_kirli) return soru;
      ilk ??= soru;
    } on StateError {
      continue;
    }
  }
  _kirli = false;
  return ilk ?? kur(a, b, c, 0);
};

AdvancedFamily _aile(
  String key,
  String title,
  Difficulty difficulty,
  BloomLevel bloom,
  LmUretec build, {
  bool shortAnswer = true,
}) => lmAile(
  'an_$key',
  title,
  Topic.mathematics,
  difficulty,
  bloom,
  build,
  exam: ExamKind.ayt,
  lesson: 'Matematik',
  shortAnswer: shortAnswer,
);

// ---------------------------------------------------------------------------
// Seçenek dengesi
// ---------------------------------------------------------------------------
//
// Bilgisiz bir öğrenci anahtarı seçeneklerin düzeninden bulamamalıdır
// (tool/lise_metin/ipucu.dart). Dengelenen ailelerde soru önce eski yoluyla
// kurulur; böylece kök, anahtar, açıklama ve rastlantı denetiminin kararı
// aynen kalır. Yalnız çeldiriciler, tipik hata adaylarından yeniden seçilir.

/// lmAile koordinatlarından vakanın sıra numarası.
int _vaka(int a, int b, int c) => a + 25 * b + 500 * c;

final _sozAyrac = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Seçeneğin sözcük kümesi (ipucu taramasındaki ölçütle aynı).
Set<String> _sozKumesi(String s) =>
    s.toLowerCase().split(_sozAyrac).where((w) => w.isNotEmpty).toSet();

/// [x] içinde [j] numaralı değer tek başına en büyük (ya da [enKucuk]
/// doğruysa tek başına en küçük) mü?
bool _tekBasina(List<num> x, int j, {bool enKucuk = false}) {
  for (var k = 0; k < x.length; k++) {
    if (k != j && (enKucuk ? x[k] - x[j] : x[j] - x[k]) <= 1e-9) return false;
  }
  return true;
}

/// İlk değerin (anahtarın) en büyük değeri kaç seçenekle paylaştığı (kendisi
/// dahil); anahtar en büyük değilse 0.
int _tepe(List<num> x) {
  var enb = x[0];
  for (final v in x) {
    if (v > enb) enb = v;
  }
  if (x[0] < enb - 1e-9) return 0;
  return x.where((v) => (v - enb).abs() <= 1e-9).length;
}

/// Ceza listelerinin sözlük sırasıyla karşılaştırılması.
bool _dahaIyi(List<int> a, List<int> b) {
  for (var k = 0; k < a.length; k++) {
    if (a[k] != b[k]) return a[k] < b[k];
  }
  return false;
}

/// Üç çeldiriciyi [adaylar] (öncelik sırasıyla değer ve yazım) içinden seçer.
/// Üçlüler sırasıyla şu ölçütlerle karşılaştırılır: anahtardan küçük
/// çeldirici sayısının [sira] hedefine uzaklığı; anahtarın sözcük
/// benzerliğinde öne çıkması ya da tek başına geride kalması, uzunlukta tek
/// başına en uzun olması; adayların öncelik sırası. Yazımı anahtarla ya da önceki bir
/// adayla aynı olan adaylar atlanır; ilk [enFazla] farklı aday denenir.
List<String> _dengeli(
  num anahtar,
  String yazim,
  Iterable<(num, String)> adaylar,
  int sira, {
  int enFazla = 10,
}) {
  final d = <num>[], y = <String>[];
  for (final (deger, metin) in adaylar) {
    if (y.length == enFazla) break;
    if (metin.trim().isEmpty ||
        ayniSecenek(metin, yazim) ||
        y.any((w) => ayniSecenek(w, metin))) {
      continue;
    }
    d.add(deger);
    y.add(metin);
  }
  final n = y.length;
  if (n < 3) throw StateError('Eksik çeldirici: $yazim → $y');
  final soz = [_sozKumesi(yazim), for (final x in y) _sozKumesi(x)];
  final boy = [yazim.length, for (final x in y) x.length];
  double benzer(int p, int q) {
    if (p == q) return 0;
    final u = soz[p].union(soz[q]).length;
    return u == 0 ? 0 : soz[p].intersection(soz[q]).length / u;
  }

  final jac = [
    for (var p = 0; p <= n; p++) [for (var q = 0; q <= n; q++) benzer(p, q)],
  ];
  var enIyi = const <int>[];
  List<int>? enIyiCeza;
  for (var p = 0; p < n; p++) {
    for (var q = p + 1; q < n; q++) {
      for (var r = q + 1; r < n; r++) {
        final s = [0, p + 1, q + 1, r + 1];
        final alt = [p, q, r].where((x) => d[x] < anahtar).length;
        final puan = [
          for (final u in s) s.fold<double>(0, (t, v) => t + jac[u][v]),
        ];
        final uz = [for (final u in s) boy[u]];
        // Anahtarın en benzer seçenekler arasındaki payı 1/4'e yakın olmalı:
        // tek başına en benzer (pay 1) ya da yalnız bir seçenekle en benzer
        // (pay 1/2) olması da, en benzerler arasında hiç bulunmaması da
        // cezalandırılır.
        final tepe = _tepe(puan);
        final ceza = [
          (alt - sira).abs(),
          (tepe == 1 ? 3 : (tepe == 2 || tepe == 0 ? 1 : 0)) +
              (_tekBasina(puan, 0, enKucuk: true) ? 1 : 0) +
              (_tekBasina(uz, 0) ? 1 : 0),
          p + q + r,
        ];
        if (enIyiCeza == null || _dahaIyi(ceza, enIyiCeza)) {
          enIyi = [p, q, r];
          enIyiCeza = ceza;
        }
      }
    }
  }
  return [for (final x in enIyi) y[x]];
}

/// [eski] sorunun kökü, anahtarı ve açıklaması korunur; çeldiricileri
/// [_dengeli] ile [adaylar] içinden yeniden seçilir. Seçim kurulamazsa eski
/// çeldiriciler kalır (rastlantı denetiminin kararı değişmesin diye).
AdvancedItem _dengele(
  AdvancedItem eski,
  num anahtar,
  Iterable<(num, String)> adaylar,
  int sira,
) {
  try {
    return AdvancedItem(
      eski.prompt,
      eski.correct,
      _dengeli(anahtar, eski.correct, adaylar, sira),
      eski.explanation,
    );
  } on StateError {
    return eski;
  }
}

/// [hedef] verilmemişse (rastlantı denetiminin ön denemeleri) [eski] soru
/// olduğu gibi döner; verilmişse çeldiriciler [adaylar] ile dengelenir.
AdvancedItem _belkiDengele(
  AdvancedItem eski,
  num anahtar,
  List<(num, String)> Function() adaylar,
  int? hedef,
) => hedef == null ? eski : _dengele(eski, anahtar, adaylar(), hedef);

/// Tam sayı adayları; [pozitif] doğruysa sıfır ve negatifler atılır.
List<(num, String)> _tamAday(
  Iterable<int?> xs, {
  String birim = '',
  bool pozitif = false,
}) => [
  for (final x in xs)
    if (x != null && (!pozitif || x > 0)) (x, birimli(_n(x), birim)),
];

/// Kesir adayları; [aralik] verilirse aralık dışındakiler atılır.
List<(num, String)> _rAday(
  Iterable<_R?> xs, {
  bool pozitif = false,
  bool Function(_R)? aralik,
}) => [
  for (final x in xs)
    if (x != null && (!pozitif || x.p > 0) && (aralik == null || aralik(x)))
      (x.p / x.q, '$x'),
];

/// Tam sayı yanıtın yakın komşuları (son çare): x ∓ s ve x ∓ 2s; s, x/8'i
/// geçmeyen en büyük yuvarlak adımdır (1, 2, 5, 10, 20, …).
List<int> _komsuTam(int x) {
  var s = 1;
  for (final u in const [2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000]) {
    if (u * 8 <= x.abs()) s = u;
  }
  return [x - s, x + s, x - 2 * s, x + 2 * s];
}

// ---------------------------------------------------------------------------
// 1 · Toplam-fark formülleri
// ---------------------------------------------------------------------------

/// Küçük Pisagor üçlüleri (dik kenarlar ve hipotenüs).
const _uclu = [(3, 4, 5), (5, 12, 13), (8, 15, 17), (7, 24, 25), (20, 21, 29)];

/// Pisagor üçlüsünden dar açı: karşı dik kenar, komşu dik kenar, hipotenüs.
typedef _Dar = ({int uclu, int kar, int kom, int hip});

/// j = 2·(üçlü) + (yön); yön 1 iken dik kenarların rolü değişir.
_Dar _dar(int j) {
  final (p, q, h) = _uclu[j ~/ 2];
  return j.isEven
      ? (uclu: j ~/ 2, kar: p, kom: q, hip: h)
      : (uclu: j ~/ 2, kar: q, kom: p, hip: h);
}

const _oranAd = ['sin', 'cos', 'tan', 'cot'];

_R _oran(_Dar x, int f) => switch (f) {
  0 => _R(x.kar, x.hip),
  1 => _R(x.kom, x.hip),
  2 => _R(x.kar, x.kom),
  _ => _R(x.kom, x.kar),
};

/// Verilen orandan dar açının sin ve cos (istenirse tan) değerlerine geçiş.
String _darTuret(_Dar x, int f, String ad, {bool tanjant = false}) {
  final s = _q(x.kar, x.hip), c = _q(x.kom, x.hip), t = _q(x.kar, x.kom);
  if (tanjant) {
    return switch (f) {
      0 =>
        '$ad dar açı ve sin $ad = $s olduğundan cos $ad = $c ve tan $ad = $t',
      1 =>
        '$ad dar açı ve cos $ad = $c olduğundan sin $ad = $s ve tan $ad = $t',
      2 => 'tan $ad = $t verilmiştir',
      _ => 'cot $ad = ${_q(x.kom, x.kar)} olduğundan tan $ad = $t',
    };
  }
  return switch (f) {
    0 => '$ad dar açı ve sin $ad = $s olduğundan cos $ad = $c',
    1 => '$ad dar açı ve cos $ad = $c olduğundan sin $ad = $s',
    _ =>
      '${_oranAd[f]} $ad = ${_oran(x, f)} olduğundan dik kenarları ${x.kar} ve '
          '${x.kom} olan dik üçgende hipotenüs ${x.hip} olur; sin $ad = $s, '
          'cos $ad = $c',
  };
}

AdvancedItem _toplamFarkUclu(int a, int b, int e) {
  // x: a < 10 iken sinüsü, a < 20 iken kosinüsü, sonra tanjantı verilir.
  final fx = a < 10 ? 0 : (a < 20 ? 1 : 2);
  final x = _dar(a % 10);
  // y, x ile aynı üçlüden seçilmez: tümler açılar tan(x + y) değerini
  // tanımsız, eş açılar sin(x − y) değerini sıfır yapardı. (3, 4, 5) ile
  // (7, 24, 25) üçlüleri de eşleştirilmez: 7-24-25 açısı 3-4-5 açısının
  // iki katının tümleyenidir ve x ± y yeniden 3-4-5 açısı çıkar; yanıt kökte
  // yazılı bir orana eşit olurdu.
  final aday = [
    for (final f in const [1, 0, 3, 2])
      for (var j = 0; j < 10; j++)
        if (j ~/ 2 != x.uclu && {x.uclu, j ~/ 2}.difference({0, 3}).isNotEmpty)
          (f, j),
  ];
  final (fy, jy) = aday[b];
  final y = _dar(jy);
  final sx = _R(x.kar, x.hip), cx = _R(x.kom, x.hip);
  final sy = _R(y.kar, y.hip), cy = _R(y.kom, y.hip);
  final tx = _R(x.kar, x.kom), ty = _R(y.kar, y.kom);
  final bir = _R(1);
  final sArti = sx * cy + cx * sy, sEksi = sx * cy - cx * sy;
  final cArti = cx * cy - sx * sy, cEksi = cx * cy + sx * sy;
  final tArti = (tx + ty) / (bir - tx * ty);
  final tEksi = (tx - ty) / (bir + tx * ty);
  const adlar = [
    'sin(x + y)',
    'sin(x − y)',
    'cos(x + y)',
    'cos(x − y)',
    'tan(x + y)',
    'tan(x − y)',
  ];
  final kok =
      'x ve y dar açılar olmak üzere ${_oranAd[fx]} x = ${_oran(x, fx)} ve '
      '${_oranAd[fy]} y = ${_oran(y, fy)} olduğuna göre ${adlar[e]} değeri '
      'kaçtır?';
  final turet =
      '${_darTuret(x, fx, 'x', tanjant: e >= 4)}; '
      '${_darTuret(y, fy, 'y', tanjant: e >= 4)}.';
  final hh = x.hip * y.hip;
  final sc = x.kar * y.kom, cs = x.kom * y.kar;
  final cc = x.kom * y.kom, ss = x.kar * y.kar;
  String ikili(_R u, _R v) => '${_rs(u)}·${_rs(v)}';
  switch (e) {
    case 0:
      return _ras(
        kok,
        sArti,
        [sEksi, cEksi, cArti, sx + sy],
        '$turet sin(x + y) = sin x·cos y + cos x·sin y = ${ikili(sx, cy)} + '
        '${ikili(cx, sy)} = ($sc + $cs)/$hh = $sArti.',
        aralik: _birlik,
      );
    case 1:
      return _ras(
        kok,
        sEksi,
        [sArti, -sEksi, cArti, sx - sy],
        '$turet sin(x − y) = sin x·cos y − cos x·sin y = ${ikili(sx, cy)} − '
        '${ikili(cx, sy)} = ($sc − $cs)/$hh = $sEksi.',
        aralik: _birlik,
      );
    case 2:
      return _ras(
        kok,
        cArti,
        [cEksi, -cArti, sArti, cx * cy],
        '$turet cos(x + y) = cos x·cos y − sin x·sin y = ${ikili(cx, cy)} − '
        '${ikili(sx, sy)} = ($cc − $ss)/$hh = $cArti.',
        aralik: _birlik,
      );
    case 3:
      return _ras(
        kok,
        cEksi,
        [cArti, sArti, sEksi, cx * cy],
        '$turet cos(x − y) = cos x·cos y + sin x·sin y = ${ikili(cx, cy)} + '
        '${ikili(sx, sy)} = ($cc + $ss)/$hh = $cEksi.',
        aralik: _birlik,
      );
    case 4:
      return _ras(
        kok,
        tArti,
        [(tx + ty) / (bir + tx * ty), tx + ty, tEksi, -tArti],
        '$turet tan(x + y) = (tan x + tan y)/(1 − tan x·tan y) olur. Pay ve '
        'payda $cc ile çarpılırsa (${x.kar * y.kom} + ${y.kar * x.kom})/'
        '($cc − $ss) = $tArti bulunur.',
      );
    default:
      return _ras(
        kok,
        tEksi,
        [(tx - ty) / (bir - tx * ty), tx - ty, tArti, -tEksi],
        '$turet tan(x − y) = (tan x − tan y)/(1 + tan x·tan y) olur. Pay ve '
        'payda $cc ile çarpılırsa (${x.kar * y.kom} − ${y.kar * x.kom})/'
        '($cc + $ss) = $tEksi bulunur.',
      );
  }
}

/// Dar açıların tanjantları için pozitif değerler (pay, payda).
const _tanDeg = [
  (1, 2),
  (1, 3),
  (2, 1),
  (3, 1),
  (2, 3),
  (3, 2),
  (1, 4),
  (3, 4),
  (4, 3),
  (4, 1),
  (1, 5),
  (2, 5),
  (3, 5),
  (4, 5),
  (5, 4),
  (5, 3),
  (5, 2),
  (5, 1),
  (1, 6),
  (5, 6),
  (6, 5),
  (6, 1),
  (1, 7),
  (2, 7),
  (3, 7),
  (7, 3),
  (7, 2),
  (7, 1),
  (1, 8),
  (3, 8),
];

/// İşaretli tanjant değerleri (pay, payda).
const _tanIsaretli = [
  (1, 1),
  (-1, 1),
  (2, 1),
  (-2, 1),
  (3, 1),
  (-3, 1),
  (1, 2),
  (-1, 2),
  (3, 2),
  (-3, 2),
  (1, 3),
  (-1, 3),
  (2, 3),
  (-2, 3),
  (4, 3),
  (-4, 3),
  (4, 1),
  (-4, 1),
  (5, 2),
  (-5, 2),
  (3, 4),
  (-3, 4),
  (5, 1),
  (-5, 1),
  (7, 2),
  (-7, 2),
  (6, 1),
  (-6, 1),
  (1, 4),
  (-1, 4),
];

AdvancedItem _toplamFarkTan(int a, int b, int c) {
  final bir = _R(1);
  if (c == 4 || c == 5) {
    final arti = c == 4;
    final (p1, q1) = _tanDeg[a];
    final t1 = _R(p1, q1);
    _R hesap(_R t2) =>
        arti ? (t1 + t2) / (bir - t1 * t2) : (t1 - t2) / (bir + t1 * t2);
    // Eş açı, tümler açı ve yanıtın kökte yazılı bir sayıya eşit çıktığı
    // ikinci tanjantlar atlanır.
    final (p2, q2) = _uygun(_tanDeg.reversed, b, (t) {
      final t2 = _R(t.$1, t.$2);
      if (t2 == t1 || t1 * t2 == bir) return false;
      final y = hesap(t2);
      return y != t1 && y != t2 && y != -t1 && y != -t2;
    });
    final t2 = _R(p2, q2);
    final yanit = hesap(t2);
    final isaret = arti ? '+' : '−', ters = arti ? '−' : '+';
    final pay = arti ? p1 * q2 + p2 * q1 : p1 * q2 - p2 * q1;
    final payda = arti ? q1 * q2 - p1 * p2 : q1 * q2 + p1 * p2;
    return _ras(
      'x ve y dar açılar olmak üzere tan x = $t1 ve tan y = $t2 olduğuna göre '
          'tan(x $isaret y) değeri kaçtır?',
      yanit,
      [
        arti ? (t1 + t2) / (bir + t1 * t2) : (t1 - t2) / (bir - t1 * t2),
        arti ? t1 + t2 : t1 - t2,
        arti ? (t1 - t2) / (bir + t1 * t2) : (t1 + t2) / (bir - t1 * t2),
        -yanit,
      ],
      'tan(x $isaret y) = (tan x $isaret tan y)/(1 $ters tan x·tan y) = '
          '($t1 $isaret $t2)/(1 $ters ${_rs(t1)}·${_rs(t2)}) olur. '
          '${_carpilirsa(q1 * q2)}(${p1 * q2} $isaret ${p2 * q1})/'
          '(${q1 * q2} $ters ${p1 * p2}) = ${_q(pay, payda)} bulunur.',
    );
  }
  if (c == 6) {
    // tan y = tan((x + y) − x)
    final (p1, q1) = _tanDeg[a];
    final t1 = _R(p1, q1);
    final (sn, sd) = _uygun(_tanIsaretli, b, (t) {
      final s = _R(t.$1, t.$2);
      if (s == t1 || (bir + s * t1).sifir) return false;
      final y = (s - t1) / (bir + s * t1);
      return y != t1 && y != -t1 && y != s && y != -s;
    });
    final s = _R(sn, sd);
    final yanit = (s - t1) / (bir + s * t1);
    final pay = sn * q1 - p1 * sd, payda = sd * q1 + sn * p1;
    return _ras(
      'tan x = $t1 ve tan(x + y) = $s olduğuna göre tan y değeri kaçtır?',
      yanit,
      [
        if (!(bir - s * t1).sifir) (s + t1) / (bir - s * t1),
        s - t1,
        if (!(bir - s * t1).sifir) (s - t1) / (bir - s * t1),
        -yanit,
      ],
      'y = (x + y) − x olduğundan tan y = [tan(x + y) − tan x]/'
          '[1 + tan(x + y)·tan x] = ($s − $t1)/(1 + ${_rs(s)}·${_rs(t1)}) olur. '
          '${_carpilirsa(sd * q1)}(${_n(sn * q1)} − ${p1 * sd})/'
          '(${sd * q1} + ${_p(sn * p1)}) = ${_q(pay, payda)} bulunur.',
    );
  }
  // c == 7: tan x = tan((x − y) + y)
  final (p2, q2) = _tanDeg[a];
  final t2 = _R(p2, q2);
  final (dn, dd) = _uygun(_tanIsaretli, b, (t) {
    final d = _R(t.$1, t.$2);
    if (d == -t2 || (bir - d * t2).sifir) return false;
    final y = (d + t2) / (bir - d * t2);
    return y != t2 && y != -t2 && y != d && y != -d;
  });
  final d = _R(dn, dd);
  final yanit = (d + t2) / (bir - d * t2);
  final pay = dn * q2 + p2 * dd, payda = dd * q2 - dn * p2;
  return _ras(
    'tan y = $t2 ve tan(x − y) = $d olduğuna göre tan x değeri kaçtır?',
    yanit,
    [
      if (!(bir + d * t2).sifir) (d - t2) / (bir + d * t2),
      d + t2,
      if (!(bir + d * t2).sifir) (d + t2) / (bir + d * t2),
      -yanit,
    ],
    'x = (x − y) + y olduğundan tan x = [tan(x − y) + tan y]/'
        '[1 − tan(x − y)·tan y] = ($d + $t2)/(1 − ${_rs(d)}·${_rs(t2)}) olur. '
        '${_carpilirsa(dd * q2)}(${_n(dn * q2)} + ${p2 * dd})/'
        '(${dd * q2} − ${_p(dn * p2)}) = ${_q(pay, payda)} bulunur.',
  );
}

// ---------------------------------------------------------------------------
// 2 · İki kat açı formülleri
// ---------------------------------------------------------------------------

/// İki kat açı sorusunun verisi: (aranan, biçim, s, t).
/// aranan: 0 sin 2x, 1 cos 2x, 2 tan 2x, 3 cot 2x.
/// biçim: 0 tan, 1 cot, 2 sin ve aralık, 3 cos ve aralık, 4 bitim kenarı
/// noktası; bu biçimlerde (s, t) = (u, v) noktasıdır (cos ve sin işaretli).
/// Yalnız cos 2x için: 5 sin = p/q, 6 cos = p/q, 7 sin = √k/q, 8 cos = √k/q,
/// 9 tan = √k/q; (s, t) = (p, q) ya da (k, q).
typedef _IkiKat = (int, int, int, int);

final List<_IkiKat> _ikiKatHavuz = _ikiKatKur();

List<_IkiKat> _ikiKatKur() {
  final gruplar = <(int, int, List<_IkiKat>)>[];
  final ciftler = <(int, int)>[
    for (var m = 1; m <= 20; m++)
      for (var n = 1; n <= 20; n++)
        if (m != n && m.gcd(n) == 1 && m * m + n * n <= 330) (m, n),
    (7, 24),
    (24, 7),
    (20, 21),
    (21, 20),
  ];
  for (final (m, n) in ciftler) {
    final nn = m * m + n * n;
    final dost = nn <= 50 || _kokAyir(nn).$2 == 1;
    final g = <_IkiKat>[];
    const ceyrekler = [(1, 1), (-1, 1), (-1, -1), (1, -1)];
    for (final ar in const [0, 2, 3]) {
      g
        ..add((ar, 0, n, m))
        ..add((ar, 0, n, -m))
        ..add((ar, 1, n, m))
        ..add((ar, 1, n, -m));
      for (final (i, j) in ceyrekler) {
        g.add((ar, 4, i * n, j * m));
        if (dost) {
          g
            ..add((ar, 2, i * n, j * m))
            ..add((ar, 3, i * n, j * m));
        }
      }
    }
    final (ci, cj) = ceyrekler[(m + n) % 4];
    g
      ..add((1, 0, n, m))
      ..add((1, 1, n, m))
      ..add((1, 4, ci * n, cj * m));
    gruplar.add((nn, gruplar.length, g));
  }
  // cos 2x: sinüs ya da kosinüsü kesirli ya da köklü verilen açılar.
  for (var q = 2; q <= 20; q++) {
    for (var p = 1; p < q; p++) {
      if (p.gcd(q) != 1) continue;
      // sin x = 1/2 iken cos 2x de 1/2 olur; yanıt kökte yazılı sayı olurdu.
      final g = <_IkiKat>[if (!(p == 1 && q == 2)) (1, 5, p, q), (1, 6, p, q)];
      gruplar.add((q * q, gruplar.length, g));
    }
  }
  for (var q = 2; q <= 8; q++) {
    for (var k = 2; k < q * q; k++) {
      if (!_kareCarpansiz(k)) continue;
      gruplar.add((q * q, gruplar.length, [(1, 7, k, q), (1, 8, k, q)]));
    }
  }
  for (var q = 1; q <= 5; q++) {
    for (var k = 2; k <= 30; k++) {
      if (!_kareCarpansiz(k)) continue;
      gruplar.add((q * q + k, gruplar.length, [(1, 9, k, q)]));
    }
  }
  gruplar.sort(
    (x, y) => x.$1 != y.$1 ? x.$1.compareTo(y.$1) : x.$2.compareTo(y.$2),
  );
  final hepsi = [for (final g in gruplar) ...g.$3];
  if (hepsi.length < lmAileBoyu) {
    throw StateError('İki kat açı havuzu yetersiz: ${hepsi.length}');
  }
  return hepsi.sublist(0, lmAileBoyu);
}

String _aralik(int u, int v) => u > 0
    ? (v > 0 ? '0° < x < 90°' : '270° < x < 360°')
    : (v > 0 ? '90° < x < 180°' : '180° < x < 270°');

String _bolge(int u, int v) =>
    u > 0 ? (v > 0 ? 'birinci' : 'dördüncü') : (v > 0 ? 'ikinci' : 'üçüncü');

/// Bitim kenarı noktası (u, v) olan açının sinüsü ya da kosinüsü: pay/√N.
String _kokluOran(int pay, int nn) {
  final (s, f) = _kokAyir(nn);
  return _kok(pay, s * f, f);
}

AdvancedItem _ikiKat(_IkiKat veri, [int? hedef]) {
  final (ar, bicim, s, t) = veri;
  const adlar = ['sin 2x', 'cos 2x', 'tan 2x', 'cot 2x'];
  final bir = _R(1);
  if (bicim >= 5) {
    // Yalnız cos 2x; s ve t: (p, q) ya da (k, q).
    final kesirli = bicim <= 6;
    final kare = kesirli ? _R(s * s, t * t) : _R(s, t * t);
    final deger = kesirli ? _q(s, t) : _kok(1, t, s);
    final ad = bicim == 5 || bicim == 7 ? 'sin' : (bicim == 9 ? 'tan' : 'cos');
    final kok = '$ad x = $deger olduğuna göre cos 2x değeri kaçtır?';
    if (bicim == 9) {
      final yanit = (bir - kare) / (bir + kare);
      final eski = _ras(
        kok,
        yanit,
        [
          if (kare != bir) (bir + kare) / (bir - kare),
          (kare - bir) / (bir + kare),
          bir - kare,
        ],
        'tan² x = $kare olur. cos 2x = (1 − tan² x)/(1 + tan² x) = '
        '${_esit('${_rs(bir - kare)}/${_rs(bir + kare)}', '$yanit')}.',
        aralik: _birlik,
        // cos 2x yerine cos² x ya da sin² x bulma.
        yedek: [bir / (bir + kare), kare / (bir + kare)],
      );
      // İşaret hatası, ters kesir, paydayı unutma, cos² x ya da sin² x bulma
      // ve bunların işaretlisi.
      return _belkiDengele(
        eski,
        yanit.p / yanit.q,
        () => _rAday([
          ...[-yanit, bir - kare, kare - bir, bir / (bir + kare)],
          ...[
            kare / (bir + kare),
            -(bir / (bir + kare)),
            -(kare / (bir + kare)),
          ],
          if (kare != bir) (bir + kare) / (bir - kare),
        ], aralik: _birlik),
        hedef,
      );
    }
    final kareYaz = kesirli ? '' : '$ad² x = $kare olduğundan ';
    if (ad == 'sin') {
      final yanit = bir - _R(2) * kare;
      final eski = _ras(
        kok,
        yanit,
        [
          _R(2) * kare - bir,
          bir - kare,
          if (kesirli) bir - _R(2 * s, t) else _R(2) * kare,
        ],
        '${kareYaz}cos 2x = 1 − 2·sin² x = 1 − 2·${_rs(kare)} = $yanit.',
        aralik: _birlik,
        yedek: [kare, bir - _R(4) * kare],
      );
      // İşaret hatası, 2 katsayısını unutma, kare almayı unutma, formülü
      // karıştırma ve bunların işaretlisi.
      return _belkiDengele(
        eski,
        yanit.p / yanit.q,
        () => _rAday([
          ...[-yanit, bir - kare, kare - bir],
          if (kesirli) ...[bir - _R(2 * s, t), _R(2 * s, t) - bir],
          ...[kare, -kare, bir - _R(4) * kare, _R(4) * kare - bir],
        ], aralik: _birlik),
        hedef,
      );
    }
    final yanit = _R(2) * kare - bir;
    final eski = _ras(
      kok,
      yanit,
      [
        bir - _R(2) * kare,
        kare - bir,
        if (kesirli) _R(2 * s, t) - bir else _R(2) * kare,
      ],
      '${kareYaz}cos 2x = 2·cos² x − 1 = 2·${_rs(kare)} − 1 = $yanit.',
      aralik: _birlik,
      yedek: [kare, bir - kare],
    );
    // İşaret hatası, 2 katsayısını unutma, kare almayı unutma, sin² x bulma
    // ve bunların işaretlisi.
    return _belkiDengele(
      eski,
      yanit.p / yanit.q,
      () => _rAday([
        ...[-yanit, kare - bir, bir - kare],
        if (kesirli) ...[_R(2 * s, t) - bir, bir - _R(2 * s, t)],
        ...[kare, -kare, _R(4) * kare - bir, bir - _R(4) * kare],
      ], aralik: _birlik),
      hedef,
    );
  }
  final u = s, v = t, nn = u * u + v * v;
  final sin2 = _R(2 * u * v, nn), cos2 = _R(u * u - v * v, nn);
  final tan2 = _R(2 * u * v, u * u - v * v),
      cot2 = _R(u * u - v * v, 2 * u * v);
  final tanx = _R(v, u), cotx = _R(u, v);
  final nokta = bicim == 4;
  final x = nokta ? 'α' : 'x';
  final aranan = nokta ? adlar[ar].replaceFirst('x', 'α') : adlar[ar];
  final kok = switch (bicim) {
    0 => 'tan x = $tanx olduğuna göre $aranan değeri kaçtır?',
    1 => 'cot x = $cotx olduğuna göre $aranan değeri kaçtır?',
    2 =>
      '${_aralik(u, v)} ve sin x = ${_kokluOran(v, nn)} olduğuna göre '
          '$aranan değeri kaçtır?',
    3 =>
      '${_aralik(u, v)} ve cos x = ${_kokluOran(u, nn)} olduğuna göre '
          '$aranan değeri kaçtır?',
    _ =>
      'Analitik düzlemde köşesi orijinde, başlangıç kenarı x ekseninin pozitif '
          'yönü olan bir α açısının bitim kenarı P(${_n(u)}, ${_n(v)}) '
          'noktasından geçmektedir. Buna göre $aranan değeri kaçtır?',
  };
  // Açının sin ve cos değerlerine (ya da tan değerine) geçiş.
  final (hs, hf) = _kokAyir(nn);
  final r = hf == 1 ? '$hs' : (hs == 1 ? '√$nn' : '√$nn = $hs√$hf');
  final giris = switch (bicim) {
    0 => '',
    1 => 'cot x = $cotx olduğundan tan x = $tanx olur. ',
    2 =>
      'sin² x + cos² x = 1 eşitliğinden cos² x = ${_R(u * u, nn)} olur; x '
          '${_bolge(u, v)} bölgede olduğundan cos x = ${_kokluOran(u, nn)}. ',
    3 =>
      'sin² x + cos² x = 1 eşitliğinden sin² x = ${_R(v * v, nn)} olur; x '
          '${_bolge(u, v)} bölgede olduğundan sin x = ${_kokluOran(v, nn)}. ',
    _ =>
      'Orijine uzaklık r = √(${_p(u)}² + ${_p(v)}²) = $r olur; sin α = '
          '${_kokluOran(v, nn)}, cos α = ${_kokluOran(u, nn)}. ',
  };
  final tanSatir = bicim <= 1 ? '' : 'tan $x = sin $x/cos $x = $tanx olur. ';
  final t2 = _R(2) * tanx, t1 = bir - tanx * tanx, tp = bir + tanx * tanx;
  switch (ar) {
    case 0:
      final hesap = bicim <= 1
          ? 'sin 2x = 2·tan x/(1 + tan² x) = '
                '${_esit('${_rs(t2)}/${_rs(tp)}', '$sin2')}.'
          : 'sin 2$x = 2·sin $x·cos $x = 2·${_sar(_kokluOran(v, nn))}·'
                '${_sar(_kokluOran(u, nn))} = $sin2.';
      final eski = _ras(
        kok,
        sin2,
        [-sin2, _R(u * v, nn), cos2, tan2],
        '$giris$hesap',
        aralik: _birlik,
        yedek: [-cos2, _R(-u * v, nn)],
      );
      // Bölge işareti, 2 katsayısını unutma, cos 2x ya da tan 2x bulma,
      // sin² x ya da cos² x bulma ve bunların işaretlisi.
      return _belkiDengele(
        eski,
        sin2.p / sin2.q,
        () => _rAday([
          ...[-sin2, _R(u * v, nn), cos2, tan2, -cos2, _R(-u * v, nn)],
          ...[_R(v * v, nn), _R(u * u, nn), -tan2],
        ], aralik: _birlik),
        hedef,
      );
    case 1:
      final hesap = bicim <= 1
          ? 'cos 2x = (1 − tan² x)/(1 + tan² x) = '
                '${_esit('${_rs(t1)}/${_rs(tp)}', '$cos2')}.'
          : 'cos 2α = cos² α − sin² α = ${_R(u * u, nn)} − ${_R(v * v, nn)} '
                '= $cos2.';
      final eski = _ras(
        kok,
        cos2,
        [-cos2, sin2, _R(u * u - v * v, u * u), _R(nn, u * u - v * v)],
        '$giris$hesap',
        aralik: _birlik,
        // cos 2x yerine cos² x ya da sin² x bulma.
        yedek: [_R(u * u, nn), _R(v * v, nn)],
      );
      // İşaret hatası, sin 2x bulma, paydayı yanlış alma, cos² x ya da sin² x
      // bulma ve bunların işaretlisi.
      return _belkiDengele(
        eski,
        cos2.p / cos2.q,
        () => _rAday([
          ...[-cos2, sin2, _R(u * u - v * v, u * u), _R(u * u, nn)],
          ...[_R(v * v, nn), -sin2, _R(v * v - u * u, u * u)],
          ...[_R(-u * u, nn), _R(-v * v, nn)],
        ], aralik: _birlik),
        hedef,
      );
    case 2:
      final eski = _ras(
        kok,
        tan2,
        [-tan2, sin2, _R(2 * v, u), cot2],
        '$giris${tanSatir}tan 2$x = 2·tan $x/(1 − tan² $x) = '
        '${_esit('${_rs(t2)}/${_rs(t1)}', '$tan2')}.',
      );
      // İşaret hatası, tan ile cot'u karıştırma (ikisi birlikte de), sin 2x
      // bulma, 2·tan x bulma.
      return _belkiDengele(
        eski,
        tan2.p / tan2.q,
        () => _rAday([
          ...[-tan2, cot2, -cot2, sin2, _R(2 * v, u), -sin2],
          ...[_R(-2 * v, u), cos2],
        ]),
        hedef,
      );
    default:
      final k2 = cotx * cotx - bir, k1 = _R(2) * cotx;
      final cotSatir = bicim == 1
          ? ''
          : 'cot $x = cos $x/sin $x = $cotx olur. ';
      final cotGiris = bicim == 1 ? '' : giris;
      final eski = _ras(
        kok,
        cot2,
        [-cot2, tan2, _R(u * u - v * v, u * v), cos2],
        '$cotGiris${bicim == 0 ? 'tan x = $tanx olduğundan cot x = $cotx olur. ' : cotSatir}'
        'cot 2$x = (cot² $x − 1)/(2·cot $x) = '
        '${_esit('${_rs(k2)}/${_rs(k1)}', '$cot2')}.',
      );
      // İşaret hatası, tan ile cot'u karıştırma (ikisi birlikte de), 2
      // katsayısını unutma, cos 2x bulma.
      return _belkiDengele(
        eski,
        cot2.p / cot2.q,
        () => _rAday([
          ...[-cot2, tan2, -tan2, _R(u * u - v * v, u * v), cos2],
          ...[_R(v * v - u * u, u * v), -cos2],
        ]),
        hedef,
      );
  }
}

// ---------------------------------------------------------------------------
// 3 · Trigonometrik denklemler
// ---------------------------------------------------------------------------

/// sin ve cos için özel değerler: (yazım, sin kökleri, cos kökleri) [0°, 360°).
const _ozelSC = [
  ('1/2', [30, 150], [60, 300]),
  ('−1/2', [210, 330], [120, 240]),
  ('√2/2', [45, 135], [45, 315]),
  ('−√2/2', [225, 315], [135, 225]),
  ('√3/2', [60, 120], [30, 330]),
  ('−√3/2', [240, 300], [150, 210]),
  ('1', [90], [0]),
  ('−1', [270], [180]),
  ('0', [0, 180], [90, 270]),
];

/// tan için özel değerler: (yazım, [0°, 180°) aralığındaki kök).
const _ozelT = [
  ('1', 45),
  ('−1', 135),
  ('√3', 60),
  ('−√3', 120),
  ('√3/3', 30),
  ('−√3/3', 150),
  ('0', 0),
];

/// sin ve cos denklemleri için (k, değer sırası) seçenekleri.
const _kvSC = [
  (1, 0),
  (1, 1),
  (1, 2),
  (1, 3),
  (1, 4),
  (1, 5),
  (1, 6),
  (1, 7),
  (1, 8),
  (2, 0),
  (2, 1),
  (2, 2),
  (2, 3),
  (2, 4),
  (2, 5),
  (2, 6),
  (2, 7),
  (2, 8),
  (3, 0),
  (3, 4),
];

/// tan denklemleri için (k, değer sırası) seçenekleri.
const _kvT = [
  (1, 0),
  (1, 1),
  (1, 2),
  (1, 3),
  (1, 4),
  (1, 5),
  (1, 6),
  (2, 0),
  (2, 1),
  (2, 2),
  (2, 3),
  (2, 4),
  (2, 5),
  (2, 6),
  (3, 0),
  (3, 1),
  (3, 2),
  (3, 3),
  (3, 4),
  (3, 5),
];

/// θ = kx + α için [α, α + 360k) aralığındaki çözümler: (θ, x·2) çiftleri.
List<(int, int)> _trigKokler(List<int> taban, int per, int k, int alfa) {
  final kok = <(int, int)>[];
  for (final t0 in taban) {
    var th = t0;
    while (th < alfa) {
      th += per;
    }
    while (th - per >= alfa) {
      th -= per;
    }
    for (; th < alfa + 360 * k; th += per) {
      final x2 = 2 * (th - alfa);
      if (x2 % k != 0) throw StateError('Tam olmayan kök');
      kok.add((th, x2 ~/ k));
    }
  }
  kok.sort((p, q) => p.$2.compareTo(q.$2));
  return kok;
}

String _trigArg(int k, int alfa) {
  final kx = k == 1 ? 'x' : '${k}x';
  if (alfa == 0) return ' $kx';
  return alfa > 0 ? '($kx + $alfa°)' : '($kx − ${-alfa}°)';
}

AdvancedItem _trigDenklemOzel(int a, int b, int c) {
  final f = c % 3; // 0 sin, 1 cos, 2 tan
  final soru = c < 3 ? 0 : (c == 4 ? 2 : 1); // 0 toplam, 1 en küçük, 2 en büyük
  final (k, vi) = f == 2 ? _kvT[b] : _kvSC[b];
  final String deger;
  final List<int> taban;
  final int per;
  if (f == 2) {
    deger = _ozelT[vi].$1;
    taban = [_ozelT[vi].$2];
    per = 180;
  } else {
    deger = _ozelSC[vi].$1;
    taban = f == 0 ? _ozelSC[vi].$2 : _ozelSC[vi].$3;
    per = 360;
  }
  int yanitOf(List<(int, int)> kok) => switch (soru) {
    0 => kok.fold(0, (t, e) => t + e.$2),
    1 => kok.first.$2,
    _ => kok.last.$2,
  };
  // α adayları: k = 3 iken kökler tam derece çıksın diye 15'in katları.
  final adaylar = k == 3
      ? [
          for (var j = 0; j <= 18; j++) ...[15 * j, if (j > 0) -15 * j],
        ]
      : [
          for (var j = 0; j <= 36; j++) ...[5 * j, if (j > 0) -5 * j],
        ];
  // Yanıtın kökte yazılı bir sayıya (0, 360, α, k) eşit çıktığı α değerleri
  // atlanır.
  final alfa = _uygun(adaylar, a, (al) {
    final y2 = yanitOf(_trigKokler(taban, per, k, al));
    return y2 != 0 && y2 != 720 && y2 != 2 * al.abs() && y2 != 2 * k;
  });
  final kok = _trigKokler(taban, per, k, alfa);
  final yanit2 = yanitOf(kok);
  const fAd = ['sin', 'cos', 'tan'];
  const soruYaz = [
    'köklerinin toplamı kaç derecedir?',
    'en küçük kökü kaç derecedir?',
    'en büyük kökü kaç derecedir?',
  ];
  final denklem = '${fAd[f]}${_trigArg(k, alfa)} = $deger';
  final kokMetin =
      '$denklem denkleminin [0°, 360°) aralığındaki ${soruYaz[soru]}';
  final thetalar = kok.map((e) => '${_n(e.$1)}°').join(', ');
  final xler = kok.map((e) => '${_yarim(e.$2)}°').join(', ');
  final sonuc = switch (soru) {
    0 => 'toplamları ${_yarim(yanit2)}° olur',
    1 => 'en küçüğü ${_yarim(yanit2)}° olur',
    _ => 'en büyüğü ${_yarim(yanit2)}° olur',
  };
  final String aciklama;
  if (k == 1 && alfa == 0) {
    aciklama =
        '${fAd[f]} x = $deger eşitliğini [0°, 360°) aralığında sağlayan kökler '
        '$xler; $sonuc.';
  } else {
    final kx = k == 1 ? 'x' : '${k}x';
    final ic = alfa == 0 ? kx : (alfa > 0 ? '$kx + $alfa°' : '$kx − ${-alfa}°');
    final geri = alfa == 0
        ? 'θ/$k'
        : (k == 1
              ? (alfa > 0 ? 'θ − $alfa°' : 'θ + ${-alfa}°')
              : (alfa > 0 ? '(θ − $alfa°)/$k' : '(θ + ${-alfa}°)/$k'));
    aciklama =
        'θ = $ic dersek x ∈ [0°, 360°) için θ ∈ [${_n(alfa)}°, '
        '${_n(alfa + 360 * k)}°) olur. ${fAd[f]} θ = $deger eşitliğini bu '
        'aralıkta sağlayan θ değerleri $thetalar bulunur. x = $geri ile '
        'kökler $xler; $sonuc.';
  }
  // Çeldiriciler: θ değerlerini kök sanma, α işaretini çevirme, yalnız ilk
  // periyodu alma, temel çözümü alma.
  final ters = alfa == 0 ? null : _trigKokler(taban, per, k, -alfa);
  final ilk = [
    for (final e in kok)
      if (e.$1 < alfa + 360) e,
  ];
  final List<int> adaylar2;
  switch (soru) {
    case 0:
      adaylar2 = [
        2 * kok.fold(0, (t, e) => t + e.$1),
        if (ters != null) yanitOf(ters),
        if (ilk.length < kok.length) ilk.fold(0, (t, e) => t + e.$2),
        yanit2 + 360,
        yanit2 - 360,
      ];
    case 1:
      adaylar2 = [
        2 * kok.first.$1,
        if (ters != null) ters.first.$2,
        2 * taban.first,
        if (kok.length > 1) kok[1].$2,
        kok.last.$2,
      ];
    default:
      adaylar2 = [
        2 * kok.last.$1,
        if (ters != null) ters.last.$2,
        if (kok.length > 1) kok[kok.length - 2].$2,
        kok.first.$2,
        2 * (taban.last + 360 * (k - 1)),
      ];
  }
  // Tek kök soruluyorsa seçenekler [0°, 360°) aralığında, toplam soruluyorsa
  // pozitif kalır: aralık dışındaki değerler çözmeden elenirdi.
  bool olasi(int x2) => soru == 0 ? x2 > 0 : x2 >= 0 && x2 < 720;
  final eski = secenekli(kokMetin, _yarim(yanit2), [
    for (final x in [
      ...adaylar2,
      yanit2 + 60,
      yanit2 + 120,
      yanit2 + 180,
      yanit2 - 60,
      yanit2 - 120,
      yanit2 - 180,
      yanit2 + 240,
      yanit2 - 240,
      yanit2 + 300,
      yanit2 - 300,
    ])
      if (olasi(x)) _yarim(x),
  ], aciklama);
  // θ − α değerlerini k ile bölmeden kök sanma da tipik bir hatadır; komşu
  // değerler iki yana da eklenir.
  final bolmeden = k == 1
      ? null
      : switch (soru) {
          0 => k * yanit2,
          1 => k * kok.first.$2,
          _ => k * kok.last.$2,
        };
  return _dengele(eski, yanit2 / 2, [
    for (final x in [
      ...adaylar2,
      ?bolmeden,
      ...[yanit2 + 60, yanit2 - 60, yanit2 + 120, yanit2 - 120],
      ...[yanit2 + 180, yanit2 - 180, yanit2 + 240, yanit2 - 240],
    ])
      if (olasi(x)) (x / 2, _yarim(x)),
  ], hedefSira(_vaka(a, b, c)));
}

/// İkinci dereceden trigonometrik denklemlerin kök çiftleri ((p1, q1),
/// (p2, q2)): birinci kök [−1, 1] içindedir; ikinci kök ya listede sonra
/// gelen bir geçerli kök ya da [−1, 1] dışında kalan, çözüm vermeyen bir
/// köktür. Çiftler katsayıların (dönüştürülmüş biçimin sabit terimi de)
/// büyüklüğüne göre sıralanır.
final List<((int, int), (int, int))> _trigKokCiftleri = () {
  final gecerli = <(int, int)>[(0, 1)];
  for (var q = 1; q <= 6; q++) {
    for (var p = 1; p <= q; p++) {
      if (p.gcd(q) == 1) {
        gecerli
          ..add((p, q))
          ..add((-p, q));
      }
    }
  }
  final gecersiz = <(int, int)>[];
  for (var q = 1; q <= 4; q++) {
    for (var p = q + 1; p <= 4 * q; p++) {
      if (p.gcd(q) == 1) {
        gecersiz
          ..add((p, q))
          ..add((-p, q));
      }
    }
  }
  final l = <(int, int, int, (int, int), (int, int))>[];
  for (var i = 0; i < gecerli.length; i++) {
    final (p1, q1) = gecerli[i];
    for (final (p2, q2) in [...gecerli.sublist(i + 1), ...gecersiz]) {
      final ka = q1 * q2, kb = -(q1 * p2 + q2 * p1), kc = p1 * p2;
      final m = [
        ka,
        kb.abs(),
        kc.abs(),
        (ka + kc).abs(),
      ].reduce((x, y) => x > y ? x : y);
      l.add((m, ka, l.length, (p1, q1), (p2, q2)));
    }
  }
  l.sort((x, y) {
    if (x.$1 != y.$1) return x.$1.compareTo(y.$1);
    if (x.$2 != y.$2) return x.$2.compareTo(y.$2);
    return x.$3.compareTo(y.$3);
  });
  return [for (final e in l) (e.$4, e.$5)];
}();

/// Kökün [0°, 360°) aralığındaki çözüm sayısı ve çözümlerin toplamı.
(int, int) _trigKokSayi(int p, int q, bool sinus) {
  if (p.abs() > q) return (0, 0);
  if (sinus) {
    if (p == q) return (1, 90);
    if (p == -q) return (1, 270);
    return p >= 0 ? (2, 180) : (2, 540);
  }
  if (p == q) return (1, 0);
  if (p == -q) return (1, 180);
  return (2, 360);
}

/// c = 6, 7 kök sayısı (sin, cos), c = 8 dönüştürülmüş, c = 9 doğrudan
/// sinüs denkleminde kökler toplamı. Kök sayısı kökte yazılı bir katsayıya,
/// toplam 0 ya da 360 sayısına eşit çıkan çiftler atlanır; kosinüs
/// denkleminde her geçerli kök 360° toplam verdiğinden toplam sorulmaz.
/// c = 8 ve c = 9 süzülmüş listenin çift ve tek sıralarını kullanır.
final Map<int, List<((int, int), (int, int))>> _trigKokSlot = {
  for (final c in const [6, 7, 8, 9])
    c: () {
      final sinus = c != 7;
      final l = <((int, int), (int, int))>[];
      for (final e in _trigKokCiftleri) {
        final ((p1, q1), (p2, q2)) = e;
        final ka = q1 * q2, kb = -(q1 * p2 + q2 * p1), kc = p1 * p2;
        final (n1, t1) = _trigKokSayi(p1, q1, sinus);
        final (n2, t2) = _trigKokSayi(p2, q2, sinus);
        if (c <= 7) {
          final yazili = {ka.abs(), kb.abs(), kc.abs(), 0, 360};
          if (!yazili.contains(n1 + n2)) l.add(e);
        } else if (t1 + t2 != 0 && t1 + t2 != 360) {
          l.add(e);
        }
      }
      final secilen = c <= 7
          ? l
          : [for (var i = c == 8 ? 0 : 1; i < l.length; i += 2) l[i]];
      if (secilen.length < 500) throw StateError('Kök çifti az: $c');
      return secilen.sublist(0, 500);
    }(),
};

String _ikinciDerece(int a, int b, int c, String u2, String u1) {
  final parca = <String>[];
  void ekle(int k, String t) {
    if (k == 0) return;
    final m = k.abs();
    final govde = t.isEmpty ? '$m' : (m == 1 ? t : '$m $t');
    if (parca.isEmpty) {
      parca.add(k < 0 ? '−$govde' : govde);
    } else {
      parca.add(k < 0 ? '− $govde' : '+ $govde');
    }
  }

  ekle(a, u2);
  ekle(b, u1);
  ekle(c, '');
  return parca.join(' ');
}

/// (q·g − p) çarpanı: `_carpan(2, 1, 'sin x')` → `(2 sin x − 1)`.
String _carpan(int q, int p, String g) {
  final bas = q == 1 ? g : '$q $g';
  if (p == 0) return bas;
  return '($bas ${p > 0 ? '−' : '+'} ${p.abs()})';
}

AdvancedItem _trigDenklemKare(int a, int b, int c) {
  final sinus = c != 7; // c = 7 kosinüs, diğerleri sinüs
  final sayi = c <= 7; // 6, 7: kök sayısı; 8, 9: kökler toplamı
  final karma = c == 8; // cos² x ile yazılmış biçim
  final ((p1, q1), (p2, q2)) = _trigKokSlot[c]![a + 25 * b];
  final ka = q1 * q2, kb = -(q1 * p2 + q2 * p1), kc = p1 * p2;
  final g = sinus ? 'sin x' : 'cos x', g2 = sinus ? 'sin² x' : 'cos² x';
  final h2 = sinus ? 'cos² x' : 'sin² x';
  final denklem = karma
      ? '${_ikinciDerece(ka, -kb, -(ka + kc), h2, g)} = 0'
      : '${_ikinciDerece(ka, kb, kc, g2, g)} = 0';
  // Kökün [0°, 360°) aralığındaki çözümleri: (sayı, toplam, açıklama).
  // Kök sayısı sorulurken açıklama köklerin toplamına değinmez.
  String topla(String t) => sayi ? '' : t;
  (int, int, String) coz(int p, int q) {
    final r = _R(p, q);
    final yaz = '$g = $r';
    if (p.abs() > q) {
      return (0, 0, '$yaz olamaz (−1 ≤ $g ≤ 1)');
    }
    if (sinus) {
      if (p == q) return (1, 90, '$yaz için x = 90°');
      if (p == -q) return (1, 270, '$yaz için x = 270°');
      if (p == 0) return (2, 180, '$yaz için x = 0° ve x = 180°');
      if (r == _R(1, 2)) return (2, 180, '$yaz için x = 30° ve x = 150°');
      if (r == _R(-1, 2)) return (2, 540, '$yaz için x = 210° ve x = 330°');
      return p > 0
          ? (
              2,
              180,
              '$yaz için biri birinci, biri ikinci bölgede iki kök vardır'
                  '${topla('; bunlar a ve 180° − a biçiminde olduğundan '
                  'toplamları 180°')}',
            )
          : (
              2,
              540,
              '$yaz için biri üçüncü, biri dördüncü bölgede iki kök vardır'
                  '${topla('; bunlar 180° + a ve 360° − a biçiminde olduğundan '
                  'toplamları 540°')}',
            );
    }
    if (p == q) return (1, 0, '$yaz için x = 0°');
    if (p == -q) return (1, 180, '$yaz için x = 180°');
    if (p == 0) return (2, 360, '$yaz için x = 90° ve x = 270°');
    if (r == _R(1, 2)) return (2, 360, '$yaz için x = 60° ve x = 300°');
    if (r == _R(-1, 2)) return (2, 360, '$yaz için x = 120° ve x = 240°');
    return (
      2,
      360,
      '$yaz için ${p > 0 ? 'biri birinci, biri dördüncü' : 'biri ikinci, biri üçüncü'} '
          'bölgede iki kök vardır'
          '${topla('; bunlar a ve 360° − a biçiminde olduğundan toplamları '
          '360°')}',
    );
  }

  final (n1, t1, a1) = coz(p1, q1);
  final (n2, t2, a2) = coz(p2, q2);
  final donusum = !karma
      ? ''
      : '$h2 = 1 − $g2 yazılırsa denklem '
            '${_ikinciDerece(ka, kb, kc, g2, g)} = 0 biçimine gelir. ';
  final carpanli =
      '${_carpan(q1, p1, g)}·${_carpan(q2, p2, g)} = 0 olduğundan $g = '
      '${_R(p1, q1)} ya da $g = ${_R(p2, q2)} bulunur.';
  final kokMetin = sayi
      ? '$denklem denkleminin [0°, 360°) aralığında kaç farklı kökü vardır?'
      : '$denklem denkleminin [0°, 360°) aralığındaki köklerinin toplamı kaç '
            'derecedir?';
  final aciklama = '$donusum$carpanli $a1; $a2. ';
  // Hatalı sayımlar: her kökü iki çözüm sayma, geçersiz kökü de sayma.
  int ham(int p, int q) => p.abs() == q ? 1 : 2;
  bool gecerli(int p, int q) => p.abs() <= q;
  final sira = hedefSira(_vaka(a, b, c));
  if (sayi) {
    final yanit = n1 + n2;
    final eski = _tam(
      kokMetin,
      yanit,
      [
        ham(p1, q1) + ham(p2, q2),
        (gecerli(p1, q1) ? 1 : 0) + (gecerli(p2, q2) ? 1 : 0),
        2 * ((gecerli(p1, q1) ? 1 : 0) + (gecerli(p2, q2) ? 1 : 0)),
        yanit + 1,
        if (yanit > 0) yanit - 1,
        yanit + 2,
      ],
      '${aciklama}Kök sayısı $n1 + $n2 = $yanit.',
      pozitif: false,
    );
    // Her kökü iki çözüm sayma, geçersiz kökü de sayma, çözüm yerine kök
    // sayma, yalnız bir çarpanın çözümlerini sayma; komşu sayılar.
    return _dengele(
      eski,
      yanit,
      _tamAday(
        [
          ham(p1, q1) + ham(p2, q2),
          (gecerli(p1, q1) ? 1 : 0) + (gecerli(p2, q2) ? 1 : 0),
          2 * ((gecerli(p1, q1) ? 1 : 0) + (gecerli(p2, q2) ? 1 : 0)),
          ...[n1, n2, yanit + 1, yanit - 1, yanit + 2, yanit - 2, 0],
          yanit + 3,
        ].where((x) => x >= 0),
      ),
      sira,
    );
  }
  final yanit = t1 + t2;
  // Hatalı toplamlar: sinüste her köke 180°, kosinüste 180° verme; geçersiz
  // kökü de toplama katma.
  int yanlis(int p, int q, int dogru) => !gecerli(p, q)
      ? (sinus ? 180 : 360)
      : (p.abs() == q ? dogru : (sinus ? 180 : 180));
  final eski = _tam(kokMetin, yanit, [
    yanlis(p1, q1, t1) + yanlis(p2, q2, t2),
    t1 + t2 + (gecerli(p2, q2) ? 0 : (sinus ? 180 : 360)),
    yanit + 180,
    if (yanit >= 180) yanit - 180,
    yanit + 360,
  ], '${aciklama}Köklerin toplamı $t1° + $t2° = $yanit°.');
  // Yanlış toplam kuralları, geçersiz kökü katma, yalnız bir çarpanın
  // köklerini toplama; komşu değerler (90° adımlı).
  return _dengele(
    eski,
    yanit,
    _tamAday(
      [
        yanlis(p1, q1, t1) + yanlis(p2, q2, t2),
        t1 + t2 + (gecerli(p2, q2) ? 0 : (sinus ? 180 : 360)),
        ...[yanit + 180, yanit - 180, yanit + 360, t1, t2],
        ...[yanit - 360, yanit + 90, yanit - 90],
      ].where((x) => x >= 0),
    ),
    sira,
  );
}

// ---------------------------------------------------------------------------
// 4 · Sinüs teoremi
// ---------------------------------------------------------------------------

/// Özel açıların sinüsü: (pay, payda, kök içi); değer pay·√kök/payda.
const _sinOzel = {
  30: (1, 2, 1),
  45: (1, 2, 2),
  60: (1, 2, 3),
  90: (1, 1, 1),
  120: (1, 2, 3),
  135: (1, 2, 2),
  150: (1, 2, 1),
};

String _sinOzelYaz(int aci) {
  final (n, d, k) = _sinOzel[aci]!;
  return _kok(n, d, k);
}

/// (A, B) özel açı çiftleri. sin A/sin B oranının rasyonel kısmı 1 olan
/// çiftler yoktur: verilen kenarın katsayısı yanıta eşit çıkardı.
final List<(int, int)> _sinusCiftleri = [
  for (final x in const [30, 45, 60, 90, 120, 135])
    for (final y in const [30, 45, 60, 90, 120, 135])
      if (x != y && x + y < 180 && _sinusOran(x, y).$1 != _R(1)) (x, y),
];

/// a = b·sin A/sin B = b·κ·√f; (κ, f).
(_R, int) _sinusOran(int x, int y) {
  final (nx, dx, rx) = _sinOzel[x]!;
  final (ny, dy, ry) = _sinOzel[y]!;
  final (s, f) = _kokAyir(rx * ry);
  return (_R(nx * dy * s, dx * ny * ry), f);
}

/// Sinüs teoreminde kesirli sinüs değerleri (pay, payda).
const _sinKesir = [
  (1, 2),
  (1, 3),
  (2, 3),
  (1, 4),
  (3, 4),
  (1, 5),
  (2, 5),
  (3, 5),
  (4, 5),
  (1, 6),
  (5, 6),
  (2, 7),
  (3, 7),
  (4, 7),
  (5, 7),
  (6, 7),
  (3, 8),
  (5, 8),
  (7, 8),
  (2, 9),
  (4, 9),
  (5, 9),
  (7, 9),
  (8, 9),
  (3, 10),
  (7, 10),
  (9, 10),
  (1, 7),
  (1, 8),
  (1, 9),
];

/// Kenar çiftleri (p, q): aralarında asal, toplamlarına göre sıralı.
final List<(int, int)> _kenarCiftleri = [
  for (var s = 5; s <= 50; s++)
    for (var p = 2; p <= s - 2; p++)
      if (p.gcd(s - p) == 1) (p, s - p),
];

/// Sinüsleri orantılı verilen üçgenler (x, y, z, k): x < y < z oranları,
/// kenarlar kx, ky, kz. Kenarlardan biri oranlardan birine eşit olmaz.
final List<(int, int, int, int)> _sinusOranUcgen = () {
  final l = <(int, int, int, int)>[];
  for (var z = 3; z <= 13; z++) {
    for (var y = 2; y < z; y++) {
      for (var x = 1; x < y; x++) {
        if (x + y <= z || x.gcd(y).gcd(z) != 1) continue;
        for (var k = 2; k <= 7; k++) {
          final oranlar = {x, y, z};
          if ([k * x, k * y, k * z].any(oranlar.contains)) continue;
          l.add((x, y, z, k));
        }
      }
    }
  }
  l.sort((p, q) {
    final d = (p.$4 * (p.$1 + p.$2 + p.$3)).compareTo(
      q.$4 * (q.$1 + q.$2 + q.$3),
    );
    return d != 0 ? d : p.$3.compareTo(q.$3);
  });
  return l.sublist(0, 500);
}();

/// Çevrel çember verileri (biçim, s, t, r). Biçim 0: sin A = s/t ve |BC|
/// verilir, R sorulur; 1: R = r ve sin A verilir, |BC| sorulur; 2: m(A) = s°
/// ve |BC| = r·√… verilir, çap sorulur.
final List<(int, int, int, int)> _cevrelVeri = () {
  final l = <(int, int, int, int)>[];
  for (final (p, q) in _sinKesir) {
    final birim = q ~/ q.gcd(2 * p);
    for (var r = birim; r <= 90; r += birim) {
      // R yanıtı kökte yazılı sayılara (sinüsün payı, paydası, kenar) eşit
      // olmasın; sin A = 1/2 iken R = |BC| çıkar.
      final kenar = 2 * r * p ~/ q;
      if (!{p, q, kenar}.contains(r)) l.add((0, p, q, r));
      // |BC| = 2R·sin A yanıtı da kökteki sayılara eşit olmasın.
      if (!{p, q, r}.contains(kenar)) l.add((1, p, q, r));
    }
  }
  for (final aci in const [30, 45, 60, 120, 135, 150]) {
    final kokIci = _sinOzel[aci]!.$3;
    for (var m = 1; m <= 20; m++) {
      // Çap 2m; açıya ya da kök içine eşit olmasın.
      if (2 * m == aci || 2 * m == kokIci) continue;
      l.add((2, aci, 0, m));
    }
  }
  int boy((int, int, int, int) e) => e.$1 == 2 ? 2 * e.$4 : e.$4;
  final sirali = [
    for (var i = 0; i < l.length; i++) (boy(l[i]), i),
  ]..sort((p, q) => p.$1 != q.$1 ? p.$1.compareTo(q.$1) : p.$2.compareTo(q.$2));
  return [for (final e in sirali.take(1000)) l[e.$2]];
}();

/// Özel açılı sinüs teoremi verileri (A, B, sunuş, ölçek). Yanıtın kökte
/// yazılı bir sayıya (verilen açılar, kenarın katsayısı ya da kök içi) eşit
/// olduğu veriler atlanır.
final List<(int, int, int, int)> _sinusOzelVeri = () {
  final l = <(int, int, int, int)>[];
  for (var t = 1; l.length < 1000; t++) {
    for (final (ax, by) in _sinusCiftleri) {
      final (kap, f) = _sinusOran(ax, by);
      final cevap = t * kap.q, katsayi = t * kap.p;
      for (var sunus = 0; sunus < 3; sunus++) {
        final acilar = switch (sunus) {
          0 => {ax, by},
          1 => {ax, 180 - ax - by},
          _ => {by, 180 - ax - by},
        };
        final yazili = {...acilar, katsayi, if (f > 1) f};
        if (!yazili.contains(cevap)) l.add((ax, by, sunus, t));
      }
    }
  }
  return l.sublist(0, 1000);
}();

AdvancedItem _sinusTeoremi(int a, int b, int c) {
  final sira = hedefSira(_vaka(a, b, c));
  // Kenar yanıtlı sorularda ek çeldiriciler: komşu değerler.
  AdvancedItem kenar(AdvancedItem eski, int yanit, List<int?> aday) => _dengele(
    eski,
    yanit,
    _tamAday([...aday, ..._komsuTam(yanit)], birim: 'cm', pozitif: true),
    sira,
  );
  if (c <= 1) {
    // Özel açılar: j → (çift, sunuş, ölçek).
    final (ax, by, sunus, t) = _sinusOzelVeri[a + 25 * b + 500 * c];
    final cz = 180 - ax - by;
    final (kap, f) = _sinusOran(ax, by);
    final bKenar = t * kap.q, katsayi = t * kap.p;
    final aYaz = f == 1 ? '$katsayi' : (katsayi == 1 ? '√$f' : '$katsayi√$f');
    final acilar = switch (sunus) {
      0 => 'm(A) = $ax°, m(B) = $by°',
      1 => 'm(A) = $ax°, m(C) = $cz°',
      _ => 'm(B) = $by°, m(C) = $cz°',
    };
    final bul = switch (sunus) {
      0 => '',
      1 => 'm(B) = 180° − $ax° − $cz° = $by° olur. ',
      _ => 'm(A) = 180° − $by° − $cz° = $ax° olur. ',
    };
    // Oranı ters kurma (a·sin A/sin B) rasyonel çıktığında çeldiricidir.
    final tersOran = _R(katsayi * katsayi * f, bKenar);
    final eski = _tam(
      'ABC üçgeninde $acilar ve |BC| = $aYaz cm olduğuna göre |AC| kaç cm '
          'olur?',
      bKenar,
      [
        if (tersOran.tam) tersOran.p,
        katsayi,
        2 * bKenar,
        if (bKenar.isEven) bKenar ~/ 2,
      ],
      '${bul}Sinüs teoremine göre |BC|/sin A = |AC|/sin B olur. sin $ax° = '
          '${_sinOzelYaz(ax)}, sin $by° = ${_sinOzelYaz(by)} olduğundan |AC| = '
          '$aYaz·${_sar(_sinOzelYaz(by))}/${_sar(_sinOzelYaz(ax))} = $bKenar cm '
          'bulunur.',
      birim: 'cm',
      pozitif: true,
    );
    // Oranı ters kurma, kökü atma, iki katını ya da yarısını alma.
    return kenar(eski, bKenar, [
      if (tersOran.tam) tersOran.p,
      katsayi,
      2 * bKenar,
      if (bKenar.isEven) bKenar ~/ 2,
    ]);
  }
  if (c <= 5) {
    // Kenarlar p = |BC|, q = |AC|; sin B = sin A·q/p. c = 5 iken sin B
    // listeden seçilir ve sin A sorulur.
    final (ps, qs) = _sinKesir[a];
    final verilen = _R(ps, qs);
    final (p, q) = _uygun(_kenarCiftleri, b, (e) {
      final diger = c == 5
          ? verilen * _R(e.$1, e.$2)
          : verilen * _R(e.$2, e.$1);
      if (diger.p >= diger.q || diger.q > 36) return false;
      // Kenar yanıtı kökte yazılı bir sayıya eşit olmasın.
      final yazili = {verilen.p, verilen.q, diger.p, diger.q};
      return switch (c) {
        2 => !{...yazili, e.$1}.contains(e.$2),
        3 => !{...yazili, e.$2}.contains(e.$1),
        _ => true,
      };
    });
    final sa = c == 5 ? verilen * _R(p, q) : verilen;
    final sb = c == 5 ? verilen : verilen * _R(q, p);
    final oran = '|BC|/sin A = |AC|/sin B';
    switch (c) {
      case 2:
        final eski = _tam(
          'ABC üçgeninde sin A = $sa, sin B = $sb ve |BC| = $p cm olduğuna '
              'göre |AC| kaç cm olur?',
          q,
          [
            if ((p * p) % q == 0) p * p ~/ q,
            if ((p * sb.p) % sb.q == 0) p * sb.p ~/ sb.q,
            p + q,
            2 * q,
          ],
          'Sinüs teoremine göre $oran olur. $p/${_rs(sa)} = |AC|/${_rs(sb)} '
              'eşitliğinden |AC| = $p·${_rs(sb)}/${_rs(sa)} = $q cm bulunur.',
          birim: 'cm',
          pozitif: true,
        );
        // Oranı ters kurma, yalnız bir sinüsle çarpma, toplama, iki katı,
        // verilen kenarı yanıt sanma, yarısını alma.
        return kenar(eski, q, [
          if ((p * p) % q == 0) p * p ~/ q,
          if ((p * sb.p) % sb.q == 0) p * sb.p ~/ sb.q,
          ...[p + q, 2 * q, p, if (q.isEven) q ~/ 2],
          if ((p * sa.p) % sa.q == 0) p * sa.p ~/ sa.q,
        ]);
      case 3:
        final eski = _tam(
          'ABC üçgeninde sin A = $sa, sin B = $sb ve |AC| = $q cm olduğuna '
              'göre |BC| kaç cm olur?',
          p,
          [
            if ((q * q) % p == 0) q * q ~/ p,
            if ((q * sa.p) % sa.q == 0) q * sa.p ~/ sa.q,
            p + q,
            2 * p,
          ],
          'Sinüs teoremine göre $oran olur. |BC|/${_rs(sa)} = $q/${_rs(sb)} '
              'eşitliğinden |BC| = $q·${_rs(sa)}/${_rs(sb)} = $p cm bulunur.',
          birim: 'cm',
          pozitif: true,
        );
        return kenar(eski, p, [
          if ((q * q) % p == 0) q * q ~/ p,
          if ((q * sa.p) % sa.q == 0) q * sa.p ~/ sa.q,
          ...[p + q, 2 * p, q, if (p.isEven) p ~/ 2],
          if ((q * sb.p) % sb.q == 0) q * sb.p ~/ sb.q,
        ]);
      case 4:
        final eski = _ras(
          'ABC üçgeninde |BC| = $p cm, |AC| = $q cm ve sin A = $sa olduğuna '
              'göre sin B değeri kaçtır?',
          sb,
          [sa * _R(p, q), _R(q, p), sa * _R(q), _R(1) - sb],
          'Sinüs teoremine göre $oran olur. $p/${_rs(sa)} = $q/sin B '
              'eşitliğinden sin B = $q·${_rs(sa)}/$p = $sb bulunur.',
          pozitif: true,
          aralik: _sinusAraligi,
          // Kenar oranını sinüs sanma, sin B = sin A alma.
          yedek: [_R(p, q), sa],
        );
        // Ek olarak yarısını ya da iki katını alma, tümleyeni 1 − sin A sanma.
        return _dengele(
          eski,
          sb.p / sb.q,
          _rAday(
            [
              ...[sa * _R(p, q), _R(q, p), sa * _R(q), _R(1) - sb, _R(p, q)],
              ...[sa, sb / _R(2), sb * _R(2), _R(1) - sa],
            ],
            pozitif: true,
            aralik: _sinusAraligi,
          ),
          sira,
        );
      default:
        final eski = _ras(
          'ABC üçgeninde |BC| = $p cm, |AC| = $q cm ve sin B = $sb olduğuna '
              'göre sin A değeri kaçtır?',
          sa,
          [sb * _R(q, p), _R(p, q), sb * _R(p), _R(1) - sa],
          'Sinüs teoremine göre $oran olur. $p/sin A = $q/${_rs(sb)} '
              'eşitliğinden sin A = $p·${_rs(sb)}/$q = $sa bulunur.',
          pozitif: true,
          aralik: _sinusAraligi,
          yedek: [_R(q, p), sb],
        );
        return _dengele(
          eski,
          sa.p / sa.q,
          _rAday(
            [
              ...[sb * _R(q, p), _R(p, q), sb * _R(p), _R(1) - sa, _R(q, p)],
              ...[sb, sa / _R(2), sa * _R(2), _R(1) - sb],
            ],
            pozitif: true,
            aralik: _sinusAraligi,
          ),
          sira,
        );
    }
  }
  if (c <= 7) {
    // Sinüslerin oranı ve çevre: kenarlar sinüslerle orantılıdır.
    final j = a + 25 * b;
    final (x, y, z, k) = _sinusOranUcgen[j];
    final d = ucluDizilimler[j % 6];
    final r = [x, y, z];
    final ra = r[d[0]], rb = r[d[1]], rc = r[d[2]];
    final cevre = k * (x + y + z);
    // Kenar adları: A karşısı |BC|, B karşısı |AC|, C karşısı |AB|.
    const kenarAd = ['|BC|', '|AC|', '|AB|'];
    final String soru;
    final int yanit;
    if (c == 6) {
      final yer = [ra, rb, rc].indexOf(y);
      soru = '${kenarAd[yer]} kaç cm olur?';
      yanit = k * y;
    } else if (j.isEven) {
      soru = 'en uzun kenarı kaç cm olur?';
      yanit = k * z;
    } else {
      soru = 'en kısa kenarı kaç cm olur?';
      yanit = k * x;
    }
    final oranYaz = '$ra : $rb : $rc';
    final aranan = c == 6
        ? kenarAd[[ra, rb, rc].indexOf(y)]
        : (j.isEven ? 'en uzun kenar' : 'en kısa kenar');
    final carpan = yanit ~/ k;
    final eski = _tam(
      'ABC üçgeninde sin A : sin B : sin C = $oranYaz ve üçgenin çevresi '
          '$cevre cm olduğuna göre $soru',
      yanit,
      [
        for (final o in [x, y, z])
          if (o != carpan) k * o,
        if (cevre % 3 == 0) cevre ~/ 3,
        cevre - yanit,
      ],
      'Sinüs teoremine göre kenarlar karşılarındaki açıların sinüsleriyle '
          'orantılıdır: |BC| : |AC| : |AB| = $oranYaz. Kenarlar ${ra}k, ${rb}k '
          've ${rc}k alınırsa ${x + y + z}k = $cevre, k = $k olur; $aranan '
          '${carpan}k = $yanit cm bulunur.',
      birim: 'cm',
      pozitif: true,
    );
    // Başka bir kenar, çevrenin üçte biri, kalan iki kenarın toplamı ya da
    // orantı sabitini yanıt sanma.
    return kenar(eski, yanit, [
      for (final o in [x, y, z])
        if (o != carpan) k * o,
      if (cevre % 3 == 0) cevre ~/ 3,
      ...[cevre - yanit, k],
    ]);
  }
  // Çevrel çember.
  final (bicim, s, t, r) = _cevrelVeri[a + 25 * b + 500 * (c - 8)];
  if (bicim == 2) {
    final (n, d, kk) = _sinOzel[s]!;
    final aYaz = kk == 1 ? '$r' : (r == 1 ? '√$kk' : '$r√$kk');
    final cap = 2 * r * d ~/ (2 * n); // a/sin A = r·√k/(√k/2) = 2r
    final eski = _tam(
      'ABC üçgeninde m(A) = $s° ve |BC| = $aYaz cm olduğuna göre ABC '
          'üçgeninin çevrel çemberinin çapı kaç cm olur?',
      cap,
      [r, 4 * r, if (kk == 1) 3 * r, if (kk != 1) r * kk],
      'Sinüs teoremine göre |BC|/sin A = 2R olur. sin $s° = '
          '${_sinOzelYaz(s)} olduğundan çap 2R = $aYaz/${_sar(_sinOzelYaz(s))} = '
          '$cap cm bulunur.',
      birim: 'cm',
      pozitif: true,
    );
    return kenar(eski, cap, [
      ...[r, 4 * r, if (kk == 1) 3 * r, if (kk != 1) r * kk],
      if (cap.isEven) cap ~/ 2,
    ]);
  }
  final sa = _R(s, t);
  final aKenar = 2 * r * s ~/ t;
  if (bicim == 0) {
    final eski = _tam(
      'ABC üçgeninde sin A = $sa ve |BC| = $aKenar cm olduğuna göre ABC '
          'üçgeninin çevrel çemberinin yarıçapı kaç cm olur?',
      r,
      [
        2 * r,
        if (r.isEven) r ~/ 2,
        if ((aKenar * s) % t == 0) aKenar * s ~/ t,
        aKenar,
      ],
      'Sinüs teoremine göre |BC|/sin A = 2R olur. $aKenar/${_rs(sa)} = 2R '
          'eşitliğinden 2R = ${2 * r} ve R = $r cm bulunur.',
      birim: 'cm',
      pozitif: true,
    );
    // Çapı yarıçap sanma, iki kez yarıya bölme, sinüsle çarpma, kenarı verme.
    return kenar(eski, r, [
      2 * r,
      if (r.isEven) r ~/ 2,
      if ((aKenar * s) % t == 0) aKenar * s ~/ t,
      aKenar,
      if ((aKenar * s) % (2 * t) == 0) aKenar * s ~/ (2 * t),
    ]);
  }
  final eski = _tam(
    'Çevrel çemberinin yarıçapı $r cm olan ABC üçgeninde sin A = $sa '
        'olduğuna göre |BC| kaç cm olur?',
    aKenar,
    [
      if ((r * s) % t == 0) r * s ~/ t, // 2R yerine R
      if ((4 * r * s) % t == 0) 4 * r * s ~/ t, // çapı iki kez alma
      if ((2 * r * t) % s == 0) 2 * r * t ~/ s, // sinüse bölme
      2 * r,
    ],
    'Sinüs teoremine göre |BC|/sin A = 2R olur. Buradan |BC| = 2R·sin A = '
        '${2 * r}·${_rs(sa)} = $aKenar cm bulunur.',
    birim: 'cm',
    pozitif: true,
  );
  return kenar(eski, aKenar, [
    if ((r * s) % t == 0) r * s ~/ t,
    if ((4 * r * s) % t == 0) 4 * r * s ~/ t,
    if ((2 * r * t) % s == 0) 2 * r * t ~/ s,
    ...[2 * r, r],
  ]);
}

// ---------------------------------------------------------------------------
// 5 · Kosinüs teoremi
// ---------------------------------------------------------------------------

/// Kenarları aralarında asal, çeşitkenar tam sayı üçgenleri (x < y < z).
final List<(int, int, int)> _kosUcgenler = () {
  final l = <(int, int, int)>[];
  for (var z = 4; z <= 40; z++) {
    for (var y = 3; y < z; y++) {
      for (var x = 2; x < y; x++) {
        if (x + y > z && x.gcd(y).gcd(z) == 1) l.add((x, y, z));
      }
    }
  }
  l.sort((p, q) {
    final d = (p.$1 + p.$2 + p.$3).compareTo(q.$1 + q.$2 + q.$3);
    if (d != 0) return d;
    final e = p.$3.compareTo(q.$3);
    return e != 0 ? e : p.$2.compareTo(q.$2);
  });
  return l;
}();

/// İki kenar ve aradaki açıdan tam sayı üçüncü kenar: (b, c, cos A, a).
final List<(int, int, _R, int)> _kosIkiKenar = () {
  final coslar = <_R>[
    _R(1, 2),
    _R(-1, 2),
    for (var q = 3; q <= 9; q++)
      for (var p = 1; p < q; p++)
        if (p.gcd(q) == 1) ...[_R(p, q), _R(-p, q)],
  ];
  final l = <(int, int, _R, int)>[];
  for (var b = 2; b <= 40; b++) {
    for (var c = b + 1; c <= 40; c++) {
      for (final cs in coslar) {
        final a2 = _R(b * b + c * c) - _R(2 * b * c) * cs;
        if (!a2.tam) continue;
        final a = _kokAyir(a2.p);
        if (a.$2 != 1) continue;
        final kenar = a.$1;
        if (kenar == b || kenar == c) continue;
        l.add((b, c, cs, kenar));
      }
    }
  }
  l.sort((p, q) {
    final d = (p.$1 + p.$2).compareTo(q.$1 + q.$2);
    return d != 0 ? d : p.$1.compareTo(q.$1);
  });
  return l;
}();

AdvancedItem _kosinusTeoremi(int a, int b, int c) {
  if (c <= 8) {
    final j = a + 25 * b + 500 * c;
    final (x, y, z) = _kosUcgenler[j ~/ 3];
    final hangi = j % 3; // 0 en büyük, 1 en küçük, 2 orta (adlandırılmış)
    _R kos(int karsi, int k1, int k2) =>
        _R(k1 * k1 + k2 * k2 - karsi * karsi, 2 * k1 * k2);
    final kz = kos(z, x, y), kx = kos(x, y, z), ky = kos(y, x, z);
    if (hangi < 2) {
      final buyuk = hangi == 0;
      final o = buyuk ? z : x, s1 = buyuk ? x : y, s2 = buyuk ? y : z;
      final yanit = buyuk ? kz : kx;
      final diger = buyuk ? [kx, ky] : [kz, ky];
      return _ras(
        'Kenar uzunlukları $x cm, $y cm ve $z cm olan bir üçgenin en '
            '${buyuk ? 'büyük' : 'küçük'} açısının kosinüsü kaçtır?',
        yanit,
        [-yanit, yanit * _R(2), ...diger, yanit / _R(2)],
        'En ${buyuk ? 'büyük' : 'küçük'} açı en ${buyuk ? 'uzun' : 'kısa'} '
            'kenarın ($o cm) karşısındadır. Kosinüs teoremine göre bu açının '
            'kosinüsü ($s1² + $s2² − $o²)/(2·$s1·$s2) = '
            '(${s1 * s1} + ${s2 * s2} − ${o * o})/${2 * s1 * s2} = $yanit olur.',
        aralik: _acikBirlik,
        // Paydada karşı kenarı kullanma.
        yedek: [_R(s1 * s1 + s2 * s2 - o * o, 2 * o * s1)],
      );
    }
    // Orta kenar y'nin karşısındaki açı, adlandırılmış köşeyle sorulur.
    final d = ucluDizilimler[(j ~/ 3) % 6];
    final kenarlar = [x, y, z];
    final ab = kenarlar[d[0]], bc = kenarlar[d[1]], ac = kenarlar[d[2]];
    // |AB| karşısı C, |BC| karşısı A, |AC| karşısı B.
    final kose = ab == y ? 'C' : (bc == y ? 'A' : 'B');
    final (k1, k2) = switch (kose) {
      'C' => (bc, ac),
      'A' => (ab, ac),
      _ => (ab, bc),
    };
    final (a1, a2) = switch (kose) {
      'C' => ('|BC|', '|AC|'),
      'A' => ('|AB|', '|AC|'),
      _ => ('|AB|', '|BC|'),
    };
    final karsiAd = switch (kose) {
      'C' => '|AB|',
      'A' => '|BC|',
      _ => '|AC|',
    };
    final yanit = ky;
    return _ras(
      'ABC üçgeninde |AB| = $ab cm, |BC| = $bc cm ve |AC| = $ac cm olduğuna '
          'göre cos $kose değeri kaçtır?',
      yanit,
      [-yanit, yanit * _R(2), kz, kx],
      'Kosinüs teoremine göre $karsiAd² = $a1² + $a2² − 2·$a1·$a2·cos $kose '
          'olur. ${y * y} = ${k1 * k1} + ${k2 * k2} − ${2 * k1 * k2}·cos $kose '
          'eşitliğinden cos $kose = '
          '${_esit('${k1 * k1 + k2 * k2 - y * y}/${2 * k1 * k2}', '$yanit')} '
          'bulunur.',
      aralik: _acikBirlik,
      yedek: [yanit / _R(2), _R(k1 * k1 + k2 * k2 - y * y, 2 * y * k1)],
    );
  }
  final (bk, ck, cs, ak) = _kosIkiKenar[a + 25 * b];
  final aci = cs == _R(1, 2)
      ? 'm(A) = 60°'
      : (cs == _R(-1, 2) ? 'm(A) = 120°' : 'cos A = $cs');
  final a2 = ak * ak;
  final arti = bk * bk + ck * ck + (_R(2 * bk * ck) * cs).p;
  final artiKok = arti > 0 ? _kokAyir(arti) : (0, 0);
  final pis = _kokAyir(bk * bk + ck * ck);
  final cosYaz = cs == _R(1, 2) || cs == _R(-1, 2)
      ? 'cos A = $cs olduğundan '
      : '';
  return _tam(
    'ABC üçgeninde |AB| = $bk cm, |AC| = $ck cm ve $aci olduğuna göre |BC| '
        'kaç cm olur?',
    ak,
    [a2, if (artiKok.$2 == 1) artiKok.$1, if (pis.$2 == 1) pis.$1, ck - bk],
    '${cosYaz}Kosinüs teoremine göre |BC|² = |AB|² + |AC|² − '
        '2·|AB|·|AC|·cos A = ${bk * bk} + ${ck * ck} − ${2 * bk * ck}·${_rs(cs)} '
        '= $a2 olur; |BC| = $ak cm.',
    birim: 'cm',
    pozitif: true,
  );
}

// ---------------------------------------------------------------------------
// 6 · Trigonometrik oranların işaretleri ve sıralama
// ---------------------------------------------------------------------------

/// Birinci terimin açıları: her biri farklı bölge ya da farklı indirgeme.
const _isaretAci1 = [
  130,
  215,
  305,
  40,
  470,
  590,
  680,
  395,
  -45,
  -135,
  -220,
  -320,
  160,
  250,
  340,
  70,
  820,
  945,
  1030,
  755,
  -100,
  -190,
  -290,
  -370,
  1150,
  115,
  235,
  325,
  55,
  -65,
];

/// İkinci terimin açıları.
const _isaretAci2 = [
  100,
  200,
  290,
  10,
  460,
  560,
  650,
  380,
  -20,
  -110,
  -200,
  -300,
  170,
  260,
  350,
  80,
  800,
  910,
  1000,
  730,
  145,
  205,
  275,
  25,
  -155,
  -245,
  515,
  605,
  695,
  425,
];

/// İşaret sorularında fonksiyon üçlüleri ve üçüncü terimin açısı.
const _isaretUclu = [
  ('sin', 'cos', 'tan', 160),
  ('cos', 'tan', 'sin', 200),
  ('tan', 'sin', 'cos', 310),
  ('sin', 'cot', 'cos', -50),
  ('cot', 'cos', 'sin', 500),
];

/// Sıralama sorularında fonksiyon üçlüleri ve üçüncü terimin açısı.
const _siraUclu = [
  ('sin', 'cos', 'sin', 250),
  ('cos', 'sin', 'cos', 140),
  ('sin', 'sin', 'cos', 320),
  ('tan', 'cot', 'tan', 110),
  ('cot', 'tan', 'cot', 230),
];

const _bolgeAd = ['birinci', 'ikinci', 'üçüncü', 'dördüncü'];

const _fonkAd = {
  'sin': 'sinüs',
  'cos': 'kosinüs',
  'tan': 'tanjant',
  'cot': 'kotanjant',
};

/// Açının [0°, 360°) aralığındaki eşi ve bölgesi (1–4).
(int, int) _esasBolge(int aci) {
  final e = aci % 360;
  return (e, e ~/ 90 + 1);
}

String _aciYaz(String f, int aci) => aci < 0 ? '$f(−${-aci}°)' : '$f $aci°';

/// Açının bölgesini indirgemeyle açıklar.
String _bolgeAcikla(int aci) {
  final (e, r) = _esasBolge(aci);
  final ad = _bolgeAd[r - 1];
  if (aci == e) return '$aci° $ad bölgededir';
  if (aci > e) {
    final t = (aci - e) ~/ 360;
    return '$aci° = ${t == 1 ? '' : '$t·'}360° + $e° olduğundan $ad '
        'bölgededir';
  }
  final t = (e - aci) ~/ 360;
  return '−${-aci}° + ${t == 1 ? '' : '$t·'}360° = $e° olduğundan $ad '
      'bölgededir';
}

bool _pozitif(String f, int bolge) => switch (f) {
  'sin' => bolge <= 2,
  'cos' => bolge == 1 || bolge == 4,
  _ => bolge == 1 || bolge == 3,
};

/// Değeri ±sin φ (sin, cos) ya da ±tan φ (tan, cot) biçimine indirger,
/// 0° < φ < 90°. Dönüş: (işaret·φ, açıklama).
(int, String) _indirgeSira(String f, int aci) {
  final (e, r) = _esasBolge(aci);
  final bas = _aciYaz(f, aci);
  final ara = aci == e ? '' : ' = $f $e°';
  switch (f) {
    case 'sin':
      final (s, fi) = switch (r) {
        1 => (1, e),
        2 => (1, 180 - e),
        3 => (-1, e - 180),
        _ => (-1, 360 - e),
      };
      return (
        s * fi,
        r == 1 ? '$bas$ara' : '$bas$ara = ${s < 0 ? '−' : ''}sin $fi°',
      );
    case 'cos':
      final (s, fi, adim) = switch (r) {
        1 => (1, 90 - e, ' = sin ${90 - e}°'),
        2 => (-1, e - 90, ' = −cos ${180 - e}° = −sin ${e - 90}°'),
        3 => (-1, 270 - e, ' = −cos ${e - 180}° = −sin ${270 - e}°'),
        _ => (1, e - 270, ' = cos ${360 - e}° = sin ${e - 270}°'),
      };
      return (s * fi, '$bas$ara$adim');
    case 'tan':
      final (s, fi) = switch (r) {
        1 => (1, e),
        2 => (-1, 180 - e),
        3 => (1, e - 180),
        _ => (-1, 360 - e),
      };
      return (
        s * fi,
        r == 1 ? '$bas$ara' : '$bas$ara = ${s < 0 ? '−' : ''}tan $fi°',
      );
    default:
      final (s, fi, adim) = switch (r) {
        1 => (1, 90 - e, ' = tan ${90 - e}°'),
        2 => (-1, e - 90, ' = −cot ${180 - e}° = −tan ${e - 90}°'),
        3 => (1, 270 - e, ' = cot ${e - 180}° = tan ${270 - e}°'),
        _ => (-1, e - 270, ' = −cot ${360 - e}° = −tan ${e - 270}°'),
      };
      return (s * fi, '$bas$ara$adim');
  }
}

AdvancedItem _trigIsaret(int a, int b, int c) {
  const adlar = ['x', 'y', 'z'];
  if (c < 5) {
    final (f1, f2, f3, aci3) = _isaretUclu[c];
    final fs = [f1, f2, f3];
    final acilar = [_isaretAci1[a], _isaretAci2[b], aci3];
    final poz = [
      for (var i = 0; i < 3; i++) _pozitif(fs[i], _esasBolge(acilar[i]).$2),
    ];
    String yaz(List<bool> p) =>
        [for (var i = 0; i < 3; i++) '${adlar[i]} ${p[i] ? '>' : '<'} 0']
            .join(', ');
    final aciklama = [
      for (var i = 0; i < 3; i++)
        '${_bolgeAcikla(acilar[i])}; bu bölgede ${_fonkAd[fs[i]]} '
            '${poz[i] ? 'pozitif' : 'negatif'}tir, ${adlar[i]} '
            '${poz[i] ? '>' : '<'} 0',
    ].join('. ');
    return secenekli(
      'x = ${_aciYaz(f1, acilar[0])}, y = ${_aciYaz(f2, acilar[1])} ve '
          'z = ${_aciYaz(f3, acilar[2])} olduğuna göre x, y ve z sayılarının '
          'işaretleri hangi seçenekte doğru verilmiştir?',
      yaz(poz),
      // Her çeldiricide iki işaret yanlıştır: her terimin doğru işareti iki
      // seçenekte görülür, terim terim çoğunluk anahtarı göstermez.
      [
        for (var i = 0; i < 3; i++)
          yaz([for (var j = 0; j < 3; j++) j == i ? poz[j] : !poz[j]]),
      ],
      '$aciklama.',
    );
  }
  final (f1, f2, f3, aci3) = _siraUclu[c - 5];
  final (v3, a3) = _indirgeSira(f3, aci3);
  // Eşit değer çıkmaması için birinci ve ikinci açılar ayıklanır.
  final aci1 = _uygun(_isaretAci1, a, (x) => _indirgeSira(f1, x).$1 != v3);
  final (v1, a1) = _indirgeSira(f1, aci1);
  final aci2 = _uygun(_isaretAci2, b, (x) {
    final v = _indirgeSira(f2, x).$1;
    return v != v1 && v != v3;
  });
  final (v2, a2) = _indirgeSira(f2, aci2);
  final deger = [v1, v2, v3];
  String sira(List<int> anahtar) {
    final ix = [0, 1, 2]..sort((p, q) => anahtar[p].compareTo(anahtar[q]));
    return ix.map((i) => adlar[i]).join(' < ');
  }

  final dogru = sira(deger);
  final tanjant = f1 == 'tan' || f1 == 'cot';
  final artan = tanjant ? 'tanjant' : 'sinüs';
  final kisa = tanjant ? 'tan' : 'sin';
  final zincir = ([0, 1, 2]..sort((p, q) => deger[p].compareTo(deger[q])))
      .map((i) => '${deger[i] < 0 ? '−' : ''}$kisa ${deger[i].abs()}°')
      .join(' < ');
  return secenekli(
    'x = ${_aciYaz(f1, aci1)}, y = ${_aciYaz(f2, aci2)} ve '
        'z = ${_aciYaz(f3, aci3)} olduğuna göre x, y ve z sayılarının '
        'sıralaması hangi seçenekte doğru verilmiştir?',
    dogru,
    [
      // İşareti yok sayma, açı ölçüsüne göre sıralama, ters sıralama.
      sira([for (final v in deger) v.abs()]),
      sira([aci1 % 360, aci2 % 360, aci3 % 360]),
      sira([for (final v in deger) -v]),
      sira([aci1, aci2, aci3]),
      'x < y < z',
      'z < y < x',
      'y < x < z',
      'x < z < y',
    ],
    '$a1, $a2, $a3 olur. 0° ile 90° arasında $artan artan olduğundan '
        '$zincir; sıralama $dogru bulunur.',
  );
}

// ---------------------------------------------------------------------------
// 7 · Esas periyot, en büyük ve en küçük değer
// ---------------------------------------------------------------------------

/// x'in katsayısı b = pay/payda (b > 0).
const _frekans = [
  (2, 1),
  (3, 1),
  (4, 1),
  (1, 2),
  (2, 3),
  (3, 2),
  (5, 1),
  (6, 1),
  (1, 3),
  (4, 3),
  (3, 4),
  (5, 2),
  (8, 1),
  (2, 5),
  (1, 4),
  (1, 1),
];

/// π li kesir: `_pi(5, 6)` → `5π/6`, `_pi(-2, 1)` → `−2π`, `_pi(0, 3)` → `0`.
String _pi(int n, int d) {
  final r = _R(n, d);
  if (r.sifir) return '0';
  final m = r.p.abs();
  return '${r.p < 0 ? '−' : ''}${m == 1 ? '' : m}π${r.q == 1 ? '' : '/${r.q}'}';
}

/// bx yazımı: `_bx(2, 3)` → `2x/3`, `_bx(1, 2)` → `x/2`.
String _bx(int p, int q, [String v = 'x']) {
  final govde = p == 1 ? v : '$p$v';
  return q == 1 ? govde : '$govde/$q';
}

/// Esas periyot 2π/b yazımı.
String _periyot(int p, int q) => _pi(2 * q, p);

/// Ters çözüm verileri: (genlik, kayma, frekans sırası).
final List<(int, int, int)> _tersPeriyot = () {
  final l = <(int, int, int)>[];
  for (var g = 1; g <= 9; g++) {
    for (var k = -9; k <= 9; k++) {
      if (k == 0) continue;
      for (var f = 0; f < _frekans.length; f++) {
        l.add((g, k, f));
      }
    }
  }
  // Ardışık sıra numaraları farklı genlik, kayma ve frekans alsın diye
  // 1097 adımla dolaşılır (1097 ile 2592 aralarında asaldır).
  return [for (var i = 0; i < l.length; i++) l[i * 1097 % l.length]];
}();

/// a·sin x + b·cos x için (a, b) ikilileri; √(a² + b²) tam sayıdır.
const _genlikCifti = [
  (3, 4),
  (6, 8),
  (5, 12),
  (9, 12),
  (8, 15),
  (12, 16),
  (15, 20),
  (7, 24),
  (10, 24),
  (20, 21),
  (18, 24),
  (16, 30),
  (21, 28),
  (12, 35),
  (15, 36),
  (24, 32),
  (9, 40),
  (27, 36),
  (14, 48),
  (30, 40),
];

/// a·sin x + b·cos x + d sorularında sabit terim adayları.
final _genlikKayma = [
  for (var x = -12; x <= 12; x++) x,
  -13,
  13,
  -14,
  14,
  -15,
  15,
];

/// Faz kayması süsleri: (pay, payda) → pay·π/payda.
const _faz = [
  (1, 6),
  (-1, 4),
  (1, 3),
  (-1, 6),
  (1, 4),
  (-1, 3),
  (2, 3),
  (1, 2),
];

String _fazliArg(int p, int q, (int, int) faz) {
  final bx = _bx(p, q);
  final (fn, fd) = faz;
  return fn > 0 ? '$bx + ${_pi(fn, fd)}' : '$bx − ${_pi(-fn, fd)}';
}

/// Açık biçim soruları için uç değeri sıfır olmayan veriler: en büyük değer
/// (true) ya da en küçük değer (false).
final Map<bool, List<(int, int, int)>> _acikPeriyot = {
  for (final maks in const [true, false])
    maks: [
      for (var i = 0; i < _tersPeriyot.length; i++)
        if ((maks
                ? _tersPeriyot[i * 7 % _tersPeriyot.length].$2 +
                      _tersPeriyot[i * 7 % _tersPeriyot.length].$1
                : _tersPeriyot[i * 7 % _tersPeriyot.length].$2 -
                      _tersPeriyot[i * 7 % _tersPeriyot.length].$1) !=
            0)
          _tersPeriyot[i * 7 % _tersPeriyot.length],
    ],
};

AdvancedItem _periyotSoru(int a, int b, int c) {
  final j = a + 25 * b;
  if (c <= 4) {
    // Yanıtı kökte yazılı bir sayıya ya da hatalı bir yolun sonucuna eşit
    // olmayan veriler; her c için listede başka bir yerden başlanır.
    final n = _tersPeriyot.length;
    final t = _temizSec(
      'periyot$c',
      n,
      (t) => _periyotTers(c, (t + 500 * c) % n),
      j,
    );
    return _periyotTers(c, (t + 500 * c) % n, hedefSira(_vaka(a, b, c)));
  }
  if (c <= 6) {
    final t = _temizSec(
      'periyot$c',
      _acikPeriyot[c == 5]!.length,
      (t) => _periyotAcik(c, t),
      j,
    );
    return _periyotAcik(c, t, hedefSira(_vaka(a, b, c)));
  }
  final t = _temizSec(
    'periyot$c-$b',
    _genlikKayma.length,
    (t) => _genlikSoru(b, t, c),
    a,
  );
  return _genlikSoru(b, t, c, hedefSira(_vaka(a, b, c)));
}

/// Uç değerleri ve periyodu verilen a·sin(bx) + c biçimleri (c ≤ 4).
AdvancedItem _periyotTers(int c, int sira, [int? hedef]) {
  final (g, k, fi) = _tersPeriyot[sira];
  final (fp, fq) = _frekans[fi];
  final frek = _R(fp, fq), ters = _R(fq, fp);
  final maks = k + g, min = k - g;
  final t = _periyot(fp, fq);
  final buyuk = 'en büyük değeri ${_n(maks)}, en küçük değeri ${_n(min)}';
  final pozitif = 'a, b pozitif gerçek sayılardır.';
  final perAc = 'Esas periyot 2π/b = $t olduğundan b = $frek olur.';
  final kYaz = '${k < 0 ? '−' : '+'} ${k.abs()}';
  // Ek çeldiriciler: periyodu π/b ya da 4π/b sanma (b'nin yarısı ya da iki
  // katı), kaymayı en küçük değer sanma, genliği en büyük değer sanma.
  final yari = frek / _R(2), cift = frek * _R(2);
  switch (c) {
    case 0:
      final yanit = _R(g) + frek + _R(k);
      final eski = _ras(
        'f(x) = a·sin(bx) + c fonksiyonunun $buyuk ve esas periyodu $t '
            'olduğuna göre a + b + c toplamı kaçtır? ($pozitif)',
        yanit,
        [
          _R(maks - min) + frek + _R(k),
          _R(g) + ters + _R(k),
          _R(g) + frek - _R(k),
          _R(g) + frek + _R(maks),
        ],
        'En büyük ve en küçük değerin farkının yarısı genliktir: a = '
            '(${_n(maks)} − ${_p(min)})/2 = $g. Ortalamaları kaymadır: c = '
            '(${_n(maks)} + ${_p(min)})/2 = ${_n(k)}. $perAc a + b + c = $g + '
            '${_rs(frek)} + ${_p(k)} = $yanit.',
      );
      return _belkiDengele(
        eski,
        yanit.p / yanit.q,
        () => _rAday([
          ...[_R(maks - min) + frek + _R(k), _R(g) + ters + _R(k)],
          ...[_R(g) + frek - _R(k), _R(g) + frek + _R(maks)],
          ...[_R(g) + frek + _R(min), _R(g) + yari + _R(k)],
          ...[_R(g) + cift + _R(k), _R(maks) + frek + _R(k)],
        ]),
        hedef,
      );
    case 1:
      final yanit = _R(k) + _R(g) + frek;
      final eski = _ras(
        'f(x) = a + b·cos(cx) fonksiyonunun görüntü kümesi [${_n(min)}, '
            '${_n(maks)}] ve esas periyodu $t olduğuna göre a + b + c toplamı '
            'kaçtır? (b ve c pozitif gerçek sayılardır.)',
        yanit,
        [
          _R(k) + _R(maks - min) + frek,
          _R(k) + _R(g) + ters,
          _R(-k) + _R(g) + frek,
          _R(maks) + _R(g) + frek,
        ],
        'Kosinüsün görüntü kümesi [−1, 1] olduğundan b = (${_n(maks)} − '
            '${_p(min)})/2 = $g ve a = (${_n(maks)} + ${_p(min)})/2 = ${_n(k)} olur. '
            'Esas periyot 2π/c = $t olduğundan c = $frek bulunur. a + b + c = '
            '${_n(k)} + $g + ${_rs(frek)} = $yanit.',
      );
      return _belkiDengele(
        eski,
        yanit.p / yanit.q,
        () => _rAday([
          ...[_R(k) + _R(maks - min) + frek, _R(k) + _R(g) + ters],
          ...[_R(-k) + _R(g) + frek, _R(maks) + _R(g) + frek],
          ...[_R(min) + _R(g) + frek, _R(k) + _R(g) + yari],
          ...[_R(k) + _R(g) + cift, _R(k) + _R(maks) + frek],
        ]),
        hedef,
      );
    case 2:
      final yanit = _R(g) * frek;
      final eski = _ras(
        'f(x) = a·sin(bx) $kYaz fonksiyonunun en büyük değeri ${_n(maks)} ve esas '
            'periyodu $t olduğuna göre a·b çarpımı kaçtır? ($pozitif)',
        yanit,
        [
          _R(maks) * frek,
          _R(g) * ters,
          _R((g + 2 * k).abs()) * frek,
          _R(g) + frek,
        ],
        'En büyük değer a $kYaz = ${_n(maks)} olduğundan a = $g olur. $perAc '
            'a·b = $g·${_rs(frek)} = $yanit.',
        pozitif: true,
      );
      return _belkiDengele(
        eski,
        yanit.p / yanit.q,
        () => _rAday([
          ...[_R(maks) * frek, _R(g) * ters, _R((g + 2 * k).abs()) * frek],
          ...[_R(g) + frek, _R(g) * yari, _R(g) * cift, _R(k.abs()) * frek],
        ], pozitif: true),
        hedef,
      );
    case 3:
      final yanit = _R(g) * frek;
      final eski = _ras(
        'f(x) = a·cos(bx) $kYaz fonksiyonunun en küçük değeri ${_n(min)} ve '
            'esas periyodu $t olduğuna göre a·b çarpımı kaçtır? ($pozitif)',
        yanit,
        [
          _R(min.abs()) * frek,
          _R(g) * ters,
          _R(maks.abs()) * frek,
          _R(g) + frek,
        ],
        'En küçük değer −a $kYaz = ${_n(min)} olduğundan a = $g olur. '
            '$perAc a·b = $g·${_rs(frek)} = $yanit.',
        pozitif: true,
      );
      return _belkiDengele(
        eski,
        yanit.p / yanit.q,
        () => _rAday([
          ...[_R(min.abs()) * frek, _R(g) * ters, _R(maks.abs()) * frek],
          ...[_R(g) + frek, _R(g) * yari, _R(g) * cift, _R(k.abs()) * frek],
        ], pozitif: true),
        hedef,
      );
    default:
      final yanit = _R(g) * frek * _R(k);
      final eski = _ras(
        'f(x) = a·sin(bx) + c fonksiyonunun $buyuk ve esas periyodu $t '
            'olduğuna göre a·b·c çarpımı kaçtır? ($pozitif)',
        yanit,
        [
          _R(maks - min) * frek * _R(k),
          _R(g) * ters * _R(k),
          _R(g) * frek * _R(maks),
          _R(g) * frek * _R(min),
        ],
        'a = (${_n(maks)} − ${_p(min)})/2 = $g ve c = (${_n(maks)} + ${_p(min)})/2 = '
            '${_n(k)} olur. $perAc a·b·c = $g·${_rs(frek)}·${_p(k)} = $yanit.',
      );
      return _belkiDengele(
        eski,
        yanit.p / yanit.q,
        () => _rAday([
          ...[_R(maks - min) * frek * _R(k), _R(g) * ters * _R(k)],
          ...[_R(g) * frek * _R(maks), _R(g) * frek * _R(min)],
          ...[_R(g) * yari * _R(k), _R(g) * cift * _R(k), -yanit],
        ]),
        hedef,
      );
  }
}

/// Açık biçim: en büyük (c = 5) ya da en küçük (c = 6) değer ile esas
/// periyodun çarpımı.
AdvancedItem _periyotAcik(int c, int j, [int? hedef]) {
  // Açık biçim: en büyük (c = 5) ya da en küçük (c = 6) değer ile esas
  // periyodun çarpımı. Genlik g, kayma k ve frekans hesaba girer; katsayının
  // işareti, fonksiyonun adı ve faz kayması yalnız süstür.
  final maks = c == 5;
  final (g, k, fi) = _acikPeriyot[maks]![j];
  final (fp, fq) = _frekans[fi];
  final uc = maks ? k + g : k - g;
  final isaret = j.isEven ? 1 : -1;
  final fonk = (j ~/ 2).isEven ? 'sin' : 'cos';
  final faz = _faz[j % _faz.length];
  final katsayi = g == 1 ? '' : '$g';
  final terim = '$fonk(${_fazliArg(fp, fq, faz)})';
  final ifade = j % 3 == 0
      ? '${_n(k)} ${isaret < 0 ? '−' : '+'} $katsayi$terim'
      : '${isaret < 0 ? '−' : ''}$katsayi$terim ${k < 0 ? '−' : '+'} '
            '${k.abs()}';
  final yanit = _pi(uc * 2 * fq, fp);
  final ad = maks ? 'büyük' : 'küçük';
  final eski = _secenek(
    'f(x) = $ifade fonksiyonunun en $ad değeri a ve esas periyodu T '
        'olduğuna göre a·T çarpımı kaçtır?',
    yanit,
    [
      _pi(uc * fq, fp),
      _pi((maks ? g : -g) * 2 * fq, fp),
      _pi((maks ? k - g : k + g) * 2 * fq, fp),
      _pi(uc * 4 * fq, fp),
      _pi(-uc * 2 * fq, fp),
      _pi((uc + 1) * 2 * fq, fp),
      _pi((uc - 1) * 2 * fq, fp),
    ],
    '$fonk fonksiyonu −1 ile 1 arasında değer aldığından en $ad değer '
        'a = ${_n(k)} ${maks ? '+' : '−'} $g = ${_n(uc)} olur. Esas periyot '
        'T = ${_esit('2π/${_rs(_R(fp, fq))}', _periyot(fp, fq))} bulunur. a·T = '
        '${_p(uc)}·${_sar(_periyot(fp, fq))} = $yanit.',
  );
  // Periyodu π/b ya da 4π/b sanma, kaymayı unutma, öteki uç değeri alma,
  // işaret hatası; en sonda komşu değerler. Değerler π'nin katsayısıdır.
  (num, String) piAday(int n) => (n / fp, _pi(n, fp));
  return _belkiDengele(
    eski,
    uc * 2 * fq / fp,
    () => [
      ...[uc * fq, (maks ? g : -g) * 2 * fq, (maks ? k - g : k + g) * 2 * fq],
      ...[uc * 4 * fq, -uc * 2 * fq, (uc + 1) * 2 * fq, (uc - 1) * 2 * fq],
      ...[(uc + 2) * 2 * fq, (uc - 2) * 2 * fq],
    ].map(piAday).toList(),
    hedef,
  );
}

/// a·sin x + b·cos x + d: genlik √(a² + b²). t sabit terimi ve işaretleri
/// seçer.
AdvancedItem _genlikSoru(int b, int t, int c, [int? hedef]) {
  final (u0, v0) = _genlikCifti[b];
  final (p0, q0) = (t ~/ 4).isEven ? (u0, v0) : (v0, u0);
  final d = _genlikKayma[t];
  final sa = (t + b).isEven ? 1 : -1, sb = (t ~/ 2 + b).isEven ? 1 : -1;
  final pa = sa * p0, qb = sb * q0;
  final r = _kokAyir(p0 * p0 + q0 * q0).$1;
  final ifade =
      '${_n(pa)} sin x ${qb < 0 ? '−' : '+'} ${qb.abs()} cos x'
      '${d == 0 ? '' : (d < 0 ? ' − ${-d}' : ' + $d')}';
  final giris =
      '${_n(pa)} sin x ${qb < 0 ? '−' : '+'} ${qb.abs()} cos x ifadesinin '
      'alabileceği değerler −√(a² + b²) ile √(a² + b²) arasındadır; '
      '√(${p0 * p0} + ${q0 * q0}) = $r olur.';
  switch (c) {
    case 7:
      final eski = _tam(
        'f(x) = $ifade fonksiyonunun en büyük değeri kaçtır?',
        r + d,
        [pa + qb + d, p0 + q0 + d, p0 * p0 + q0 * q0 + d, r - d],
        '$giris En büyük değer '
            '${d == 0 ? '$r' : '$r ${d < 0 ? '−' : '+'} ${d.abs()} = ${_n(r + d)}'}'
            ' olur.',
      );
      // Katsayıları toplama ya da kareleri toplayıp kök almayı unutma, sabiti
      // unutma ya da çıkarma, en küçük değeri verme, katsayıları çıkarma.
      return _belkiDengele(
        eski,
        r + d,
        () => _tamAday([
          ...[pa + qb + d, p0 + q0 + d, p0 * p0 + q0 * q0 + d, r - d],
          ...[d - r, if (d != 0) r, (p0 - q0).abs() + d, ..._komsuTam(r + d)],
        ]),
        hedef,
      );
    case 8:
      final eski = _tam(
        'f(x) = $ifade fonksiyonunun en küçük değeri kaçtır?',
        d - r,
        [d - p0 - q0, d - (pa + qb).abs(), -r - d.abs(), d - p0 * p0 - q0 * q0],
        '$giris En küçük değer '
            '${d == 0 ? '−$r' : '−$r ${d < 0 ? '−' : '+'} ${d.abs()} = ${_n(d - r)}'}'
            ' olur.',
      );
      // Katsayıları toplama ya da kareleri toplayıp kök almayı unutma, sabiti
      // unutma, en büyük değeri verme, katsayıları çıkarma.
      return _belkiDengele(
        eski,
        d - r,
        () => _tamAday([
          ...[d - p0 - q0, d - (pa + qb).abs(), -r - d.abs()],
          ...[d - p0 * p0 - q0 * q0, r + d, if (d != 0) -r],
          ...[d - (p0 - q0).abs(), ..._komsuTam(d - r)],
        ]),
        hedef,
      );
    default:
      final yanit = (r + d) * (d - r);
      final eski = _tam(
        'f(x) = $ifade fonksiyonunun en büyük değeri M, en küçük değeri m '
            'olduğuna göre M·m çarpımı kaçtır?',
        yanit,
        [
          (p0 + q0 + d) * (d - p0 - q0),
          -yanit,
          (r + d) + (d - r),
          d * d + r * r,
        ],
        '$giris M = ${_n(r + d)} ve m = ${_n(d - r)} olduğundan M·m = '
            '${_p(r + d)}·${_p(d - r)} = ${_n(yanit)}.',
      );
      // Genlik yerine katsayı toplamını alma, çarpım yerine toplam ya da fark,
      // işaret hatası, uç değerlerden birinin karesi.
      return _belkiDengele(
        eski,
        yanit,
        () => _tamAday([
          ...[(p0 + q0 + d) * (d - p0 - q0), -yanit, 2 * d, d * d + r * r],
          ...[2 * r, (r + d) * (r + d), (d - r) * (d - r)],
          ..._komsuTam(yanit),
        ]),
        hedef,
      );
  }
}

// ---------------------------------------------------------------------------
// 8 · Ters trigonometrik fonksiyonlar
// ---------------------------------------------------------------------------

/// x − m·⌊x/m⌋ (m > 0 tam sayı).
_R _modR(_R x, int m) {
  final b = x.p, d = x.q * m;
  final kat = (b - b % d) ~/ d;
  return x - _R(kat * m);
}

String _piR(_R x) => _pi(x.p, x.q);

/// θ = nπ/q açıları (|θ| ≤ 5π); küçük ölçüler önce gelir.
List<_R> _tersAcilar(bool Function(_R) uygun) {
  final l = <_R>[
    for (final q in const [3, 4, 5, 6, 8, 9, 10, 12])
      for (var n = -5 * q; n <= 5 * q; n++)
        if (n.gcd(q) == 1 && uygun(_R(n, q))) _R(n, q),
  ];
  l.sort((x, y) {
    final d = (x.p.abs() * y.q).compareTo(y.p.abs() * x.q);
    if (d != 0) return d;
    return x.p.compareTo(y.p);
  });
  return l;
}

final _yarimR = _R(1, 2);

final List<_R> _asinAcilar = _tersAcilar(
  (t) => t.p * 2 > t.q || t.p * 2 < -t.q,
);
final List<_R> _acosAcilar = _tersAcilar((t) => t.p < 0 || t.p > t.q);
final List<_R> _atanAcilar = _tersAcilar(
  (t) => t.p * 2 >= t.q || t.p * 2 <= -t.q,
);

/// arcsin(sin θ), arccos(cos θ), arctan(tan θ) (π biriminde) ve adımlar.
(_R, String) _esasDeger(String f, _R teta) {
  final icinde = switch (f) {
    'sin' => teta.p * 2 <= teta.q && teta.p * 2 >= -teta.q,
    'cos' => teta.p >= 0 && teta.p <= teta.q,
    _ => teta.p * 2 < teta.q && teta.p * 2 > -teta.q,
  };
  if (icinde) return (teta, '');
  final bas = '$f(${_piR(teta)})';
  final ara = <String>[bas];
  switch (f) {
    case 'sin':
      final t = _modR(teta, 2);
      if (t != teta) ara.add('sin(${_piR(t)})');
      final _R son;
      if (t.p * 2 <= t.q) {
        son = t;
      } else if (t.p * 2 <= 3 * t.q) {
        son = _R(1) - t;
        ara.add('sin(π − ${_piR(t)})');
      } else {
        son = t - _R(2);
        ara.add('sin(${_piR(t)} − 2π)');
      }
      if (ara.last != 'sin(${_piR(son)})') ara.add('sin(${_piR(son)})');
      return (son, ara.join(' = '));
    case 'cos':
      final t = _modR(teta, 2);
      if (t != teta) ara.add('cos(${_piR(t)})');
      final _R son;
      if (t.p <= t.q) {
        son = t;
      } else {
        son = _R(2) - t;
        ara.add('cos(2π − ${_piR(t)})');
      }
      if (ara.last != 'cos(${_piR(son)})') ara.add('cos(${_piR(son)})');
      return (son, ara.join(' = '));
    default:
      final t = _modR(teta, 1);
      if (t != teta) ara.add('tan(${_piR(t)})');
      final _R son;
      if (t.p * 2 < t.q) {
        son = t;
      } else {
        son = t - _R(1);
        ara.add('tan(${_piR(t)} − π)');
      }
      if (ara.last != 'tan(${_piR(son)})') ara.add('tan(${_piR(son)})');
      return (son, ara.join(' = '));
  }
}

/// Ters trigonometride Pisagor üçlüleri.
const _pisagorTers = [
  (3, 4, 5),
  (5, 12, 13),
  (8, 15, 17),
  (7, 24, 25),
  (20, 21, 29),
  (12, 35, 37),
  (9, 40, 41),
  (28, 45, 53),
  (11, 60, 61),
  (16, 63, 65),
  (33, 56, 65),
  (48, 55, 73),
  (13, 84, 85),
  (36, 77, 85),
  (39, 80, 89),
  (65, 72, 97),
];

/// Bileşke türleri: (dış fonksiyon, iç fonksiyon).
const _bileske = [
  ('cos', 'arcsin'),
  ('tan', 'arcsin'),
  ('cot', 'arcsin'),
  ('sin', 'arccos'),
  ('tan', 'arccos'),
  ('cot', 'arccos'),
  ('sin', 'arctan'),
  ('cos', 'arctan'),
];

/// Özel değerler: (yazım, arcsin π/12 biriminde, arccos π/12 biriminde).
const _ozelSinDeg = [
  ('−1', -6, 12),
  ('−√3/2', -4, 10),
  ('−√2/2', -3, 9),
  ('−1/2', -2, 8),
  ('0', 0, 6),
  ('1/2', 2, 4),
  ('√2/2', 3, 3),
  ('√3/2', 4, 2),
  ('1', 6, 0),
];

/// tan özel değerleri: (yazım, arctan π/12 biriminde).
const _ozelTanDeg = [
  ('−√3', -4),
  ('−1', -3),
  ('−√3/3', -2),
  ('0', 0),
  ('√3/3', 2),
  ('1', 3),
  ('√3', 4),
];

/// Toplam ifadeleri: (şablon, u, v, t).
final List<(int, int, int, int)> _tersToplam = () {
  final l = <(int, int, int, int)>[];
  for (var u = 0; u < 9; u++) {
    for (var v = 0; v < 9; v++) {
      if (u != v) l.add((0, u, v, 0));
      l
        ..add((1, u, v, 0))
        ..add((2, u, v, 0))
        ..add((6, u, v, 0))
        ..add((8, u, v, 0));
      for (var t = 0; t < 7; t++) {
        l.add((7, u, v, t));
      }
    }
    for (var t = 0; t < 7; t++) {
      l
        ..add((3, u, 0, t))
        ..add((4, u, 0, t))
        ..add((5, u, 0, t))
        ..add((9, u, 0, t));
    }
  }
  return [for (var i = 0; i < l.length; i++) l[i * 389 % l.length]];
}();

/// Denklem iç ifadeleri (p, q, r): (px + q)/r.
List<(int, int, int)> _icIfadeler(int qSinir, List<int> rler) => [
  for (var q = 0; q <= qSinir; q++)
    for (final qq in q == 0 ? [0] : [q, -q])
      for (final r in rler)
        for (var p = 1; p <= 5; p++)
          if (p.gcd(qq).gcd(r) == 1) (p, qq, r),
];

/// Ters trigonometrik denklemlerde c'ye göre iç ifadeler.
final Map<int, List<(int, int, int)>> _tersIcListe = {
  6: _icIfadeler(20, [1, 2]),
  7: _icIfadeler(20, [1, 2]),
  8: _icIfadeler(20, [1, 2, 3]),
  9: _icIfadeler(20, [3, 4]),
};

String _icYaz((int, int, int) ic) {
  final (p, q, r) = ic;
  final lin = _pol([p, q]);
  return r == 1 ? lin : (q == 0 ? '$lin/$r' : '($lin)/$r');
}

AdvancedItem _tersTrig(int a, int b, int c) {
  final j = a + 25 * b;
  if (c <= 2) {
    final liste = c == 0 ? _asinAcilar : (c == 1 ? _acosAcilar : _atanAcilar);
    final t = _temizSec('ters$c', 2 * liste.length, (t) => _tersOzel(c, t), j);
    return _tersOzel(c, t);
  }
  if (c == 3) {
    final t = _temizSec('ters3', 32 * _pisagorTers.length, _tersBileske, j);
    return _tersBileske(t);
  }
  if (c <= 5) {
    // c = 4 ve c = 5 aynı kalıbı kullanır: temiz listenin ayrı yarıları.
    final t = _temizSec(
      'ters45',
      _tersToplam.length,
      _tersToplamSoru,
      j + 500 * (c - 4),
    );
    return _tersToplamSoru(t);
  }
  final n = const {6: 4, 7: 5, 8: 2, 9: 4}[c]!;
  final ai = j % n;
  final t = _temizSec(
    'ters$c-$ai',
    _tersIcListe[c]!.length,
    (t) => _tersDenklem(c, ai, t),
    j ~/ n,
  );
  return _tersDenklem(c, ai, t);
}

/// arcsin(sin θ), arccos(cos θ), arctan(tan θ) ve çapraz biçimleri; j tek
/// ise çapraz biçim.
AdvancedItem _tersOzel(int c, int j) {
  // c = 0: arcsin(sin θ) ya da arcsin(cos θ); c = 1: arccos; c = 2: arctan.
  final ters = c == 0 ? 'arcsin' : (c == 1 ? 'arccos' : 'arctan');
  final dogal = c == 0 ? 'sin' : (c == 1 ? 'cos' : 'tan');
  final capraz = c == 0 ? 'cos' : (c == 1 ? 'sin' : 'cot');
  final liste = c == 0 ? _asinAcilar : (c == 1 ? _acosAcilar : _atanAcilar);
  final teta = liste[j ~/ 2];
  final caprazMi = j.isOdd;
  final ic = caprazMi ? '$capraz(${_piR(teta)})' : '$dogal(${_piR(teta)})';
  // Çapraz biçim tümler açıya çevrilir: cos θ = sin(π/2 − θ) vb.
  final aci = caprazMi ? _yarimR - teta : teta;
  final (son, adim) = _esasDeger(dogal, aci);
  final aralik = switch (c) {
    0 => '[−π/2, π/2]',
    1 => '[0, π]',
    _ => '(−π/2, π/2)',
  };
  final cevir = caprazMi
      ? '$capraz(${_piR(teta)}) = $dogal(π/2 − '
            '${teta.p < 0 ? '(${_piR(teta)})' : _piR(teta)}) = '
            '$dogal(${_piR(aci)}) olur. '
      : '';
  return _secenek(
    '$ters($ic) ifadesinin değeri kaçtır?',
    _piR(son),
    [
      _piR(teta),
      _piR(aci),
      _piR(-son),
      _piR(_modR(aci, c == 2 ? 1 : 2)),
      _piR(son + _R(1, 2)),
      _piR(son - _R(1, 3)),
      _piR(son + _R(1, 6)),
    ],
    '$ters fonksiyonunun değeri $aralik aralığındadır. $cevir'
        '${adim.isEmpty ? '' : '$adim olur. '}${_piR(son)} bu aralıkta '
        'bulunduğundan sonuç '
        '${_piR(son)} olur.',
  );
}

/// sin, cos, tan, cot ile ters fonksiyon bileşkesi (Pisagor üçlüleri).
AdvancedItem _tersBileske(int j) {
  final tur = j % 8;
  final kalan = j ~/ 8;
  final (p0, q0, h) = _pisagorTers[kalan ~/ 4];
  final (kar, kom) = kalan.isEven ? (p0, q0) : (q0, p0);
  final s = (kalan ~/ 2).isEven ? 1 : -1;
  final (dis, icF) = _bileske[tur];
  final _R v, sinT, cosT;
  final String aralik;
  switch (icF) {
    case 'arcsin':
      v = _R(s * kar, h);
      sinT = v;
      cosT = _R(kom, h);
      aralik = '[−π/2, π/2]';
    case 'arccos':
      v = _R(s * kom, h);
      cosT = v;
      sinT = _R(kar, h);
      aralik = '[0, π]';
    default:
      v = _R(s * kar, kom);
      sinT = _R(s * kar, h);
      cosT = _R(kom, h);
      aralik = '(−π/2, π/2)';
  }
  final tanT = sinT / cosT;
  final yanit = switch (dis) {
    'sin' => sinT,
    'cos' => cosT,
    'tan' => tanT,
    _ => _R(1) / tanT,
  };
  final bilinen = switch (icF) {
    'arcsin' => 'sin θ = $v',
    'arccos' => 'cos θ = $v',
    _ => 'tan θ = $v',
  };
  final isaretNot = switch (icF) {
    'arcsin' => 'bu aralıkta kosinüs negatif değildir: cos θ = $cosT',
    'arccos' => 'bu aralıkta sinüs negatif değildir: sin θ = $sinT',
    _ => 'bu aralıkta kosinüs pozitiftir: cos θ = $cosT, sin θ = $sinT',
  };
  final hesap = switch (dis) {
    'tan' => ' tan θ = sin θ/cos θ = ${_rs(sinT)}/${_rs(cosT)} = $tanT.',
    'cot' =>
      ' cot θ = cos θ/sin θ = ${_rs(cosT)}/${_rs(sinT)} = ${_R(1) / tanT}.',
    _ => '',
  };
  final sinKos = dis == 'sin' || dis == 'cos';
  final takas = dis == 'sin' ? cosT : (dis == 'cos' ? sinT : _R(1) / yanit);
  return _ras(
    '$dis($icF($v)) ifadesinin değeri kaçtır?',
    yanit,
    [
      -yanit,
      takas,
      dis == 'tan' || dis == 'cot' ? -_R(1) / yanit : _R(1) / yanit,
      _R(kar, kom),
      _R(kom, kar),
    ],
    'θ = $icF($v) dersek $bilinen ve θ ∈ $aralik olur; $isaretNot.$hesap',
    // Sinüs ve kosinüs değeri [−1, 1] dışına çıkamaz.
    aralik: sinKos ? _birlik : null,
    yedek: [if (sinKos) -takas],
  );
}

/// Esas değerlerin toplamı.
AdvancedItem _tersToplamSoru(int sira) {
  final (sablon, u, v, t) = _tersToplam[sira];
  final (uy, us, uc) = _ozelSinDeg[u];
  final (vy, vs, vc) = _ozelSinDeg[v];
  final (ty, tt) = _ozelTanDeg[t];
  // Terimler: (yazım, değer, sık hata değeri).
  (String, int, int) asin(String y, int d) =>
      ('arcsin($y)', d, d.abs()); // işareti yok sayma
  (String, int, int) acos(String y, int d) =>
      ('arccos($y)', d, d > 6 ? d - 12 : d); // arccos(−a) = −arccos(a)
  (String, int, int) atan(String y, int d) => ('arctan($y)', d, d.abs());
  final terimler = <(int, (String, int, int))>[
    ...switch (sablon) {
      0 => [(1, asin(uy, us)), (1, acos(vy, vc))],
      1 => [(1, asin(uy, us)), (-1, acos(vy, vc))],
      2 => [(1, acos(uy, uc)), (-1, asin(vy, vs))],
      3 => [(1, acos(uy, uc)), (1, atan(ty, tt))],
      4 => [(1, asin(uy, us)), (1, atan(ty, tt))],
      5 => [(1, acos(uy, uc)), (-1, atan(ty, tt))],
      6 => [(2, asin(uy, us)), (1, acos(vy, vc))],
      8 => [(2, acos(uy, uc)), (-1, asin(vy, vs))],
      9 => [(1, asin(uy, us)), (-2, atan(ty, tt))],
      _ => [(1, asin(uy, us)), (1, acos(vy, vc)), (1, atan(ty, tt))],
    },
  ];
  var ifade = '';
  for (final (k, (y, _, _)) in terimler) {
    final kat = k.abs() == 1 ? y : '${k.abs()}·$y';
    ifade = ifade.isEmpty
        ? (k < 0 ? '−$kat' : kat)
        : '$ifade ${k < 0 ? '−' : '+'} $kat';
  }
  final toplam = terimler.fold(0, (s, e) => s + e.$1 * e.$2.$2);
  // Sıfır çıkan toplamlar önemsizdir.
  if (toplam == 0) _kirli = true;
  final hatali = terimler.fold(0, (s, e) => s + e.$1 * e.$2.$3);
  var isaretli = 0;
  for (var i = 0; i < terimler.length; i++) {
    final e = terimler[i];
    isaretli += (i == terimler.length - 1 ? -e.$1 : e.$1) * e.$2.$2;
  }
  var islem = '';
  for (final (k, (_, d, _)) in terimler) {
    final deg = _pi(d, 12);
    final kat = k.abs() == 1 ? _sar(deg) : '${k.abs()}·${_sar(deg)}';
    islem = islem.isEmpty
        ? (k < 0 ? '−$kat' : kat)
        : '$islem ${k < 0 ? '−' : '+'} $kat';
  }
  final degerler = [for (final (_, (y, d, _)) in terimler) '$y = ${_pi(d, 12)}']
      .join(', ');
  return _secenek(
    '$ifade ifadesinin değeri kaçtır?',
    _pi(toplam, 12),
    [
      _pi(hatali, 12),
      _pi(isaretli, 12),
      _pi(toplam + 2, 12),
      _pi(toplam - 2, 12),
      _pi(toplam + 3, 12),
      _pi(-toplam, 12),
    ],
    'Esas değerler $degerler olduğundan ifadenin değeri $islem = '
        '${_pi(toplam, 12)} bulunur.',
  );
}

/// Ters trigonometrik denklem: ai açı, t iç ifade sırası.
AdvancedItem _tersDenklem(int c, int ai, int t) {
  // c = 6..9: ters trigonometrik denklem.
  final String f, ters;
  final List<(String, _R)> acilar; // (açı yazımı, fonksiyon değeri)
  switch (c) {
    case 6:
      f = 'sin';
      ters = 'arcsin';
      acilar = [
        ('−π/2', _R(-1)),
        ('−π/6', _R(-1, 2)),
        ('π/6', _R(1, 2)),
        ('π/2', _R(1)),
      ];
    case 7:
      f = 'cos';
      ters = 'arccos';
      acilar = [
        ('0', _R(1)),
        ('π/3', _R(1, 2)),
        ('π/2', _R(0)),
        ('2π/3', _R(-1, 2)),
        ('π', _R(-1)),
      ];
    case 8:
      f = 'tan';
      ters = 'arctan';
      acilar = [('−π/4', _R(-1)), ('π/4', _R(1))];
    default:
      f = 'sin';
      ters = 'arcsin';
      acilar = [
        ('arccos(√3/2)', _R(1, 2)),
        ('arctan(−√3/3)', _R(-1, 2)),
        ('arccos(0)', _R(1)),
        ('arctan(√3/3)', _R(1, 2)),
      ];
  }
  final (aciYaz, deger) = acilar[ai];
  final ic = _tersIcListe[c]![t];
  final (p, q, r) = ic;
  final yanit = (deger * _R(r) - _R(q)) / _R(p);
  final ozel = c == 9
      ? '$aciYaz = ${switch (aciYaz) {
          'arccos(√3/2)' => 'π/6',
          'arctan(−√3/3)' => '−π/6',
          'arccos(0)' => 'π/2',
          _ => 'π/6',
        }} olduğundan '
      : '';
  // İç ifade yalnız x ise ya da paydası yoksa denklem yeniden yazılmaz.
  final String son;
  if (p == 1 && q == 0) {
    son = r == 1 ? '' : ' Buradan x = $yanit bulunur.';
  } else {
    son =
        ' Buradan ${r == 1 ? '' : '${_pol([p, q])} = ${deger * _R(r)} ve '}'
        'x = $yanit bulunur.';
  }
  return _ras(
    '$ters(${_icYaz(ic)}) = $aciYaz olduğuna göre x kaçtır?',
    yanit,
    [
      (deger * _R(r) + _R(q)) / _R(p),
      (deger - _R(q)) / _R(p),
      (-deger * _R(r) - _R(q)) / _R(p),
      (deger * _R(r) - _R(q)) * _R(p),
    ],
    '$ozel${_icYaz(ic)} = $f(${c == 9 ? switch (aciYaz) {
            'arccos(√3/2)' => 'π/6',
            'arctan(−√3/3)' => '−π/6',
            'arccos(0)' => 'π/2',
            _ => 'π/6',
          } : aciYaz}) = $deger ${son.isEmpty ? 'bulunur' : 'olmalıdır'}.$son',
  );
}

// ---------------------------------------------------------------------------
// 9 · Logaritma ile basamak sayısı
// ---------------------------------------------------------------------------

const _logNot = '(log 2 = 0,301 ve log 3 = 0,477 alınız.)';

/// Tabanlar: (taban, 2'nin, 3'ün, 5'in kuvveti).
const _basTaban = [
  (2, 1, 0, 0),
  (3, 0, 1, 0),
  (4, 2, 0, 0),
  (5, 0, 0, 1),
  (6, 1, 1, 0),
  (8, 3, 0, 0),
  (9, 0, 2, 0),
  (12, 2, 1, 0),
  (15, 0, 1, 1),
  (16, 4, 0, 0),
  (18, 1, 2, 0),
  (20, 2, 0, 1),
  (24, 3, 1, 0),
  (25, 0, 0, 2),
  (27, 0, 3, 0),
  (30, 1, 1, 1),
  (32, 5, 0, 0),
  (36, 2, 2, 0),
  (45, 0, 2, 1),
  (48, 4, 1, 0),
  (50, 1, 0, 2),
  (54, 1, 3, 0),
  (60, 2, 1, 1),
  (72, 3, 2, 0),
  (75, 0, 1, 2),
];

/// Yuvarlanmış logaritma (binde birlik birimde).
int _logBin((int, int, int, int) t) => 301 * t.$2 + 477 * t.$3 + 699 * t.$4;

/// log tabanının açılımı: `log 45 = 2·log 3 + log 5 = 2·0,477 + 0,699`.
String _logAcilim((int, int, int, int) t) {
  final (b, i, j, k) = t;
  if (b == 5) return 'log 5 = 1 − log 2 = 0,699';
  final parca = <String>[], sayi = <String>[];
  void ekle(int us, String ad, String deger) {
    if (us == 0) return;
    parca.add(us == 1 ? 'log $ad' : '$us·log $ad');
    sayi.add(us == 1 ? deger : '$us·$deger');
  }

  ekle(i, '2', '0,301');
  ekle(j, '3', '0,477');
  ekle(k, '5', '0,699');
  final bes = k > 0 ? ' (log 5 = 1 − log 2 = 0,699)' : '';
  if (parca.length == 1 && i + j + k == 1) {
    return 'log $b = ${sayi.first}';
  }
  return 'log $b = ${parca.join(' + ')} = ${sayi.join(' + ')} = '
      '${tr(_logBin(t) / 1000, 3)}$bes';
}

/// n·log x değerinin yuvarlanmış logaritmayla basamak sayısı kesin mi?
/// Kesir kısmı tam sayıya 0,01'den yakın olmamalı ve gerçek değerle aynı
/// basamak sayısını vermelidir.
bool _basamakKesin(int binlik, BigInt gercek) {
  final kesir = binlik % 1000;
  if (kesir < 10 || kesir > 990) return false;
  return gercek.toString().length == binlik ~/ 1000 + 1;
}

BigInt _bigUs((int, int, int, int) t, int n) => BigInt.from(t.$1).pow(n);

/// 2^p2·5^p5 sayısında 10'un kuvveti ayrılınca kalan 2 ya da 5 kuvvetinin
/// basamak sayısı kesin bulunuyor mu? Küçük kalanlar doğrudan hesaplanır;
/// büyükler yuvarlanmış logaritmayla (log 2 = 0,301, log 5 = 0,699) gerçek
/// değerle aynı sonucu ve yeterli payı vermelidir.
bool _kalanKesin(int p2, int p5) {
  final fark = (p2 - p5).abs();
  final taban = p2 > p5 ? 2 : 5;
  final deger = BigInt.from(taban).pow(fark);
  if (deger < BigInt.from(100000)) return true;
  return _basamakKesin(fark * (taban == 2 ? 301 : 699), deger);
}

/// Tek kuvvetin basamak sayısı; yuvarlanmış logaritma kesin değilse kurulmaz.
/// k basamak koşulu yuvarlanmış logaritmayla kesin çözülüyor mu?
bool _basamakSinirUygun((int, int, int, int) t, bool enAz, int x) {
  final lg = _logBin(t);
  final sinir = enAz ? x - 1 : x;
  final oran = sinir * 1000 % lg;
  if (oran * 100 < lg || (lg - oran) * 100 < lg) return false;
  final n = enAz ? (sinir * 1000 + lg - 1) ~/ lg : sinir * 1000 ~/ lg;
  int basamak(BigInt v) => v.toString().length;
  if (enAz) {
    return basamak(_bigUs(t, n)) >= x && basamak(_bigUs(t, n - 1)) < x;
  }
  return basamak(_bigUs(t, n)) == x && basamak(_bigUs(t, n + 1)) > x;
}

/// c = 6: en az k basamaklı olması için en küçük n; c = 7: k basamaklı ise
/// n en çok kaç.
AdvancedItem _basamakSinir(int c, (int, int, int, int) t, int k, [int? sira]) {
  final lg = _logBin(t);
  final enAz = c == 6;
  if (!_basamakSinirUygun(t, enAz, k)) {
    throw StateError('Basamak sınırı kesin çözülmüyor');
  }
  if (enAz) {
    final sinir = k - 1;
    final n = (sinir * 1000 + lg - 1) ~/ lg;
    final eski = _tam(
      '${t.$1}ⁿ sayısının en az $k basamaklı olması için n doğal sayısı en '
          'az kaç olmalıdır? $_logNot',
      n,
      [n - 1, n + 1, (k * 1000 + lg - 1) ~/ lg, k],
      '${_logAcilim(t)} olur. ${t.$1}ⁿ sayısının en az $k basamaklı olması '
          'için ${t.$1}ⁿ ≥ 10${_ust(sinir)}, yani n·${tr(lg / 1000, 3)} ≥ '
          '$sinir olmalıdır. $sinir/${tr(lg / 1000, 3)} ≈ '
          '${tr(sinir * 1000 / lg, 2)} olduğundan n en az $n olur.',
      pozitif: true,
    );
    if (sira == null) return eski;
    // Sınırı k − 1 yerine k alma, yuvarlamayı ters yapma, basamak sayısını
    // üs sanma; en sonda komşu değerler.
    return _dengele(
      eski,
      n,
      _tamAday([
        ...[n - 1, n + 1, (k * 1000 + lg - 1) ~/ lg, k],
        ...[sinir * 1000 ~/ lg, k - 1, n - 2, n + 2],
      ], pozitif: true),
      sira,
    );
  }
  final n = k * 1000 ~/ lg;
  final eski = _tam(
    '${t.$1}ⁿ sayısı $k basamaklı olduğuna göre n doğal sayısı en çok kaç '
        'olabilir? $_logNot',
    n,
    [n + 1, n - 1, ((k - 1) * 1000 + lg - 1) ~/ lg, k],
    '${_logAcilim(t)} olur. ${t.$1}ⁿ sayısının $k basamaklı olması için '
        '10${_ust(k - 1)} ≤ ${t.$1}ⁿ < 10${_ust(k)}, yani n·${tr(lg / 1000, 3)} '
        '< $k olmalıdır. $k/${tr(lg / 1000, 3)} ≈ ${tr(k * 1000 / lg, 2)} '
        'olduğundan n en çok $n olur.',
    pozitif: true,
  );
  if (sira == null) return eski;
  // "En az" yanıtını verme, yuvarlamayı ters yapma, basamak sayısını üs
  // sanma; en sonda komşu değerler.
  return _dengele(
    eski,
    n,
    _tamAday([
      ...[n + 1, n - 1, ((k - 1) * 1000 + lg - 1) ~/ lg, k],
      ...[(k * 1000 + lg - 1) ~/ lg, k - 1, n - 2, n + 2],
    ], pozitif: true),
    sira,
  );
}

AdvancedItem _basamakTek((int, int, int, int) t, int n, [int? sira]) {
  final lg = _logBin(t);
  if (!_basamakKesin(n * lg, _bigUs(t, n))) {
    throw StateError('Yuvarlanmış logaritma kesin değil');
  }
  final bin = n * lg;
  final yanit = bin ~/ 1000 + 1;
  final eski = _tam(
    '${t.$1}${_ust(n)} sayısı kaç basamaklıdır? $_logNot',
    yanit,
    [yanit - 1, yanit + 1, (n * lg / 100).round(), n],
    '${_logAcilim(t)} olur. log(${t.$1}${_ust(n)}) = $n·log ${t.$1} = '
        '${tr(bin / 1000, 3)} bulunur. Bu sayı ${bin ~/ 1000} ile '
        '${bin ~/ 1000 + 1} arasında olduğundan ${t.$1}${_ust(n)} sayısı '
        '$yanit basamaklıdır.',
    pozitif: true,
  );
  if (sira == null) return eski;
  // 1 eklemeyi unutma, virgülü kaydırma, üssü ya da tabanın basamak sayısı
  // ile üssün çarpımını yanıt sanma; en sonda komşu değerler.
  return _dengele(
    eski,
    yanit,
    _tamAday([
      ...[yanit - 1, yanit + 1, n, (n * lg / 100).round()],
      ...['${t.$1}'.length * n, yanit - 2, yanit + 2, n + 1, n - 1],
    ], pozitif: true),
    sira,
  );
}

AdvancedItem _logBasamak(int a, int b, int c, int deneme) {
  final sira = hedefSira(_vaka(a, b, c));
  if (c <= 3) {
    final t = _basTaban[a];
    final n = _temizSec(
      'basamak$a',
      390,
      (x) => _basamakTek(t, 11 + x),
      b + 20 * c,
    );
    return _basamakTek(t, 11 + n, sira);
  }
  if (c == 4) {
    // 2 ve 5 kuvvetleri: 10'un kuvveti ayrılır.
    const ikiler = [(2, 1), (4, 2), (8, 3), (16, 4), (32, 5)];
    const besler = [(5, 1), (25, 2), (125, 3)];
    final (t2, i2) = ikiler[a % 5];
    final (t5, i5) = besler[a ~/ 5 % 3];
    final m = 3 + a ~/ 15 * 20 + b; // 3 … 42
    // Kalan kuvvetin basamak sayısı verilen yuvarlanmış logaritmayla kesin
    // bulunabilmelidir (log 2 = 0,301 ile 2¹⁹⁶ yanlış sayılırdı).
    final k = _uygun(
      [for (var x = 2; x <= 60; x++) x],
      (a % 5 + b + deneme) % 7,
      (x) => i2 * m != i5 * x && _kalanKesin(i2 * m, i5 * x),
    );
    final p2 = i2 * m, p5 = i5 * k;
    final ortak = p2 < p5 ? p2 : p5;
    final fark = (p2 - p5).abs();
    final kalanTaban = p2 > p5 ? 2 : 5;
    final kalan = BigInt.from(kalanTaban).pow(fark);
    final kalanBasamak = kalan.toString().length;
    final yanit = ortak + kalanBasamak;
    final kalanYaz = fark == 1 ? '$kalanTaban' : '$kalanTaban${_ust(fark)}';
    final kalanLg = kalanTaban == 2 ? 301 : 699;
    final String kalanAcik;
    if (fark == 1) {
      kalanAcik = '$kalanYaz sayısı 1 basamaklı';
    } else if (kalan < BigInt.from(100000)) {
      kalanAcik = '$kalanYaz = $kalan sayısı $kalanBasamak basamaklı';
    } else {
      kalanAcik =
          'log($kalanYaz) = $fark·${tr(kalanLg / 1000, 3)} = '
          '${tr(fark * kalanLg / 1000, 3)}'
          '${kalanTaban == 5 ? ' (log 5 = 1 − log 2)' : ''} ve $kalanYaz sayısı '
          '$kalanBasamak basamaklı';
    }
    final ayir = t2 == 2 && t5 == 5 ? '' : ' = 2${_ust(p2)}·5${_ust(p5)}';
    final eski = _tam(
      '$t2${_ust(m)}·$t5${_ust(k)} sayısı kaç basamaklıdır? $_logNot',
      yanit,
      [ortak, p2 + p5, ortak + 1 == yanit ? ortak + 2 : ortak + 1, yanit + 1],
      '$t2${_ust(m)}·$t5${_ust(k)}$ayir = 10${_ust(ortak)}·$kalanYaz olur. '
          '$kalanAcik olduğundan çarpım $ortak + $kalanBasamak = $yanit '
          'basamaklıdır.',
      pozitif: true,
    );
    // Kalan kuvveti unutma, üsleri toplama, kalan çarpanların her birini bir
    // basamak sayma; en sonda komşu değerler.
    return _dengele(
      eski,
      yanit,
      _tamAday([
        ...[ortak, p2 + p5, yanit + 1, yanit - 1, ortak + fark, m + k],
        ...[ortak + 1, yanit + 2, yanit - 2],
      ], pozitif: true),
      sira,
    );
  }
  if (c == 5) {
    // İki tabanın kuvvetlerinin çarpımı.
    final t1 = _basTaban[a];
    final i2 = (a + 3 + b + 5 * deneme) % 25;
    final t2 = _basTaban[i2 == a ? (a + 4) % 25 : i2];
    final n1 = 10 + b;
    final n2 = _uygun(
      [for (var x = 8; x <= 90; x++) x],
      a % 10 + b,
      (x) => _basamakKesin(
        n1 * _logBin(t1) + x * _logBin(t2),
        _bigUs(t1, n1) * _bigUs(t2, x),
      ),
    );
    final bin = n1 * _logBin(t1) + n2 * _logBin(t2);
    final yanit = bin ~/ 1000 + 1;
    final eski = _tam(
      '${t1.$1}${_ust(n1)}·${t2.$1}${_ust(n2)} sayısı kaç basamaklıdır? '
          '$_logNot',
      yanit,
      [
        yanit - 1,
        yanit + 1,
        (n1 * _logBin(t1)) ~/ 1000 + (n2 * _logBin(t2)) ~/ 1000 + 2,
        (n1 * _logBin(t1)) ~/ 1000 + 1,
      ],
      '${_logAcilim(t1)} ve ${_logAcilim(t2)} olur. Çarpımın logaritması '
          '$n1·log ${t1.$1} + $n2·log ${t2.$1} = ${tr(bin / 1000, 3)} '
          'olduğundan sayı $yanit basamaklıdır.',
      pozitif: true,
    );
    final b1 = (n1 * _logBin(t1)) ~/ 1000, b2 = (n2 * _logBin(t2)) ~/ 1000;
    // Çarpanların basamak sayılarını toplama, tek çarpanı sayma, 1 eklemeyi
    // unutma, üsleri toplama; en sonda komşu değerler.
    return _dengele(
      eski,
      yanit,
      _tamAday([
        ...[yanit - 1, yanit + 1, b1 + b2 + 2, b1 + 1, b2 + 1, n1 + n2],
        ...[yanit - 2, yanit + 2],
      ], pozitif: true),
      sira,
    );
  }
  if (c <= 7) {
    // Taban 10'dan küçüktür (2, 3, 4, 5, 6, 8, 9): daha büyük tabanlarda k
    // basamaklı kuvvet çoğu kez tektir ya da yoktur; "en az" ile "en çok"
    // yanıtları ve komşu basamak sayılarının yanıtları çakışır.
    // c = 7'de yalnız 2, 3 ve 4 tabanları: her basamak sayısında birden çok
    // kuvvet bulunur, "en az" yanıtı "en çok" yanıtından ayrılır.
    final tur = c == 6 ? 7 : 3;
    final t = _basTaban[a % tur];
    final k = _temizSec(
      'basamak$c-${a % tur}',
      389,
      (x) => _basamakSinir(c, t, 12 + x),
      b + 20 * (a ~/ tur),
    );
    return _basamakSinir(c, t, 12 + k, sira);
  }
  // c = 8, 9: üç sayının karşılaştırılması.
  final p = 40 + 2 * a;
  // z = 5^r, x = 2^p ile en az 0,2 farklı logaritma alsın.
  final r = _uygun(
    [for (var x = 18; x <= 75; x++) x],
    (a * 7 + b * 3 + deneme) % 20,
    (x) => (699 * x - 301 * p).abs() >= 200,
  );
  final q = _uygun([for (var x = 20; x <= 120; x++) x], b, (x) {
    final l = [301 * p, 477 * x, 699 * r]..sort();
    if (l[1] - l[0] < 30 || l[2] - l[1] < 30) return false;
    final hedef = c == 8 ? l[2] : l[0];
    final gercek = hedef == 301 * p
        ? BigInt.two.pow(p)
        : (hedef == 477 * x ? BigInt.from(3).pow(x) : BigInt.from(5).pow(r));
    return _basamakKesin(hedef, gercek);
  });
  final degerler = [(301 * p, 'x'), (477 * q, 'y'), (699 * r, 'z')]
    ..sort((u, v) => u.$1.compareTo(v.$1));
  final secilen = c == 8 ? degerler.last : degerler.first;
  final diger = c == 8 ? degerler.first : degerler.last;
  final yanit = secilen.$1 ~/ 1000 + 1;
  final eski = _tam(
    'x = 2${_ust(p)}, y = 3${_ust(q)} ve z = 5${_ust(r)} sayılarından en '
        '${c == 8 ? 'büyüğü' : 'küçüğü'} kaç basamaklıdır? $_logNot',
    yanit,
    [diger.$1 ~/ 1000 + 1, degerler[1].$1 ~/ 1000 + 1, yanit + 1, yanit - 1],
    'log x = $p·0,301 = ${tr(301 * p / 1000, 3)}, log y = $q·0,477 = '
        '${tr(477 * q / 1000, 3)}, log z = $r·0,699 = ${tr(699 * r / 1000, 3)} '
        'olur (log 5 = 1 − log 2). En ${c == 8 ? 'büyüğü' : 'küçüğü'} '
        '${secilen.$2} sayısıdır; ${secilen.$2} sayısı $yanit basamaklıdır.',
    pozitif: true,
  );
  final us = switch (secilen.$2) {
    'x' => p,
    'y' => q,
    _ => r,
  };
  // Öteki uçtaki ya da ortadaki sayının basamak sayısı, 1 eklemeyi unutma,
  // üssü basamak sayısı sanma; en sonda komşu değerler.
  return _dengele(
    eski,
    yanit,
    _tamAday([
      ...[diger.$1 ~/ 1000 + 1, degerler[1].$1 ~/ 1000 + 1, yanit + 1],
      ...[yanit - 1, us, yanit + 2, yanit - 2],
    ], pozitif: true),
    sira,
  );
}

// ---------------------------------------------------------------------------
// 10 · Üstel büyüme ve azalma modelleri
// ---------------------------------------------------------------------------

/// Artış ve azalış oranları: (yüzde, çarpanın logaritması binde birlik,
/// çarpan yazımı, bağlam, süre birimi, logaritmanın bulunuşu).
const _oranlar = [
  (
    20,
    79,
    '1,2',
    'Bir bakteri kültüründeki bakteri sayısı her saat %20 artıyor.',
    'saat',
    'log 1,2 = log 12 − 1 = 2·0,301 + 0,477 − 1 = 0,079',
  ),
  (
    50,
    176,
    '1,5',
    'Bir göldeki nilüfer yapraklarının kapladığı alan her hafta %50 genişliyor.',
    'hafta',
    'log 1,5 = log 3 − log 2 = 0,477 − 0,301 = 0,176',
  ),
  (
    25,
    97,
    '1,25',
    'Bir mağazanın internet satışları her ay %25 artıyor.',
    'ay',
    'log 1,25 = log 5 − log 4 = 0,699 − 0,602 = 0,097 (log 5 = 1 − log 2)',
  ),
  (
    60,
    204,
    '1,6',
    'Bir maya kültürünün kütlesi her gün %60 artıyor.',
    'gün',
    'log 1,6 = log 16 − 1 = 4·0,301 − 1 = 0,204',
  ),
  (
    8,
    33,
    '1,08',
    'Bir hesaptaki para her yıl %8 bileşik faizle artıyor.',
    'yıl',
    'log 1,08 = log 108 − 2 = 2·0,301 + 3·0,477 − 2 = 0,033',
  ),
  (
    80,
    255,
    '1,8',
    'Bir göldeki alg miktarı her gün %80 artıyor.',
    'gün',
    'log 1,8 = log 18 − 1 = 0,301 + 2·0,477 − 1 = 0,255',
  ),
  (
    -20,
    -97,
    '0,8',
    'Kana karışan bir ilacın miktarı her saat %20 azalıyor.',
    'saat',
    'log 0,8 = log 8 − 1 = 3·0,301 − 1 = −0,097',
  ),
  (
    -10,
    -46,
    '0,9',
    'Işık, her bir cam levhadan geçerken şiddetinin %10 kadarını yitiriyor.',
    'levha',
    'log 0,9 = log 9 − 1 = 2·0,477 − 1 = −0,046',
  ),
  (
    -25,
    -125,
    '0,75',
    'Bir arabanın değeri her yıl %25 azalıyor.',
    'yıl',
    'log 0,75 = log 3 − log 4 = 0,477 − 0,602 = −0,125',
  ),
  (
    -40,
    -222,
    '0,6',
    'Bir göletteki kirletici madde miktarı her ay %40 azalıyor.',
    'ay',
    'log 0,6 = log 6 − 1 = 0,778 − 1 = −0,222',
  ),
];

/// Hedef katlar: (kat, logaritma binde birlik).
const _katlar = [
  (2, 301),
  (3, 477),
  (4, 602),
  (5, 699),
  (6, 778),
  (8, 903),
  (9, 954),
  (10, 1000),
  (12, 1079),
  (15, 1176),
  (16, 1204),
  (18, 1255),
  (20, 1301),
  (25, 1398),
  (27, 1431),
  (30, 1477),
  (32, 1505),
  (36, 1556),
  (40, 1602),
  (45, 1653),
  (48, 1681),
  (50, 1699),
  (60, 1778),
  (64, 1806),
  (72, 1857),
  (75, 1875),
  (80, 1903),
  (81, 1908),
  (90, 1954),
  (100, 2000),
];

/// Oranın gerçek çarpanı (pay, payda): 1,2 → (6, 5), 0,75 → (3, 4) gibi.
(int, int) _oranCarpan(int yuzde) => switch (yuzde) {
  20 => (6, 5),
  50 => (3, 2),
  25 => (5, 4),
  60 => (8, 5),
  8 => (27, 25),
  80 => (9, 5),
  -20 => (4, 5),
  -10 => (9, 10),
  -25 => (3, 4),
  _ => (3, 5),
};

/// Logaritmalı en az süre verileri: (tür, x, y, kat sırası, yanıt).
/// Tür 0: yüzdelik oran (x = oran sırası); tür 1: her y saatte x katına
/// çıkan model. Oran tam sayıya %2'den yakın çıkmaz; yanıt gerçek değerlerle
/// doğrulanır ve kökte yazılı bir sayıya eşit olmaz.
final List<(int, int, int, int, int)> _logSureVeri = () {
  final l0 = <(int, int, int, int, int)>[];
  for (var k = 0; k < _katlar.length; k++) {
    for (var o = 0; o < _oranlar.length; o++) {
      final (yuzde, lg, _, _, _, _) = _oranlar[o];
      final (kat, klg) = _katlar[k];
      final mutlak = lg.abs();
      final n = (klg + mutlak - 1) ~/ mutlak;
      final kalan = klg % mutlak;
      if (kalan * 50 < mutlak || (mutlak - kalan) * 50 < mutlak) continue;
      if (n > 80 || n <= 3 || n == kat || n == yuzde.abs()) continue;
      final (cp, cq) = _oranCarpan(yuzde);
      final (bp, bq) = yuzde > 0 ? (cp, cq) : (cq, cp);
      bool yeter(int m) =>
          BigInt.from(bp).pow(m) >= BigInt.from(kat) * BigInt.from(bq).pow(m);
      if (!yeter(n) || yeter(n - 1)) continue;
      l0.add((0, o, 0, k, n));
    }
  }
  final l1 = <(int, int, int, int, int)>[];
  for (var t = 2; t <= 12; t++) {
    for (final (ca, lg) in const [(2, 301), (3, 477)]) {
      for (var k = 0; k < _katlar.length; k++) {
        final (kat, klg) = _katlar[k];
        // Katın çarpanın kuvveti olduğu (logsuz çözülen) hedefler atlanır.
        var x = kat;
        while (x % ca == 0) {
          x ~/= ca;
        }
        if (x == 1) continue;
        final pay = t * klg;
        final n = (pay + lg - 1) ~/ lg;
        final kalan = pay % lg;
        if (kalan * 50 < lg || (lg - kalan) * 50 < lg) continue;
        if (n == kat || n == t || n > 120 || n <= 3) continue;
        // ca^(n/t) ≥ kat ⇔ ca^n ≥ kat^t
        bool yeter(int m) => BigInt.from(ca).pow(m) >= BigInt.from(kat).pow(t);
        if (!yeter(n) || yeter(n - 1)) continue;
        l1.add((1, ca, t, k, n));
      }
    }
  }
  // İki tür sırayla karıştırılır.
  final l = <(int, int, int, int, int)>[];
  for (var i = 0; i < l0.length || i < l1.length; i++) {
    if (i < l0.length) l.add(l0[i]);
    if (i < l1.length) l.add(l1[i]);
  }
  if (l.length < 500) {
    throw StateError('Logaritmalı süre verisi az: ${l.length}');
  }
  return l;
}();

const _baslangic = [
  100,
  150,
  200,
  250,
  300,
  400,
  500,
  600,
  750,
  800,
  1000,
  1200,
];
const _kalanKutle = [5, 6, 8, 10, 12, 15, 20, 24, 25, 30, 40, 50, 60, 75, 80];

/// [liste] içinden [i] numaralıdan başlayarak [yasak] kümesinde olmayan ilk
/// değer (süs değerlerinin yanıta eşit çıkmaması için).
int _susSec(List<int> liste, int i, Set<int> yasak) {
  for (var d = 0; d < liste.length; d++) {
    final x = liste[(i + d) % liste.length];
    if (!yasak.contains(x)) return x;
  }
  throw StateError('Uygun süs değeri yok');
}

/// İki ya da üç katına çıkma verileri: (çarpan, periyot, kat sayısı).
final List<(int, int, int)> _katlanma = [
  for (var t = 12; t <= 65; t++)
    for (final (a, ks) in const [(2, 7), (3, 5)])
      for (var k = 2; k <= ks; k++) (a, t, k),
];

/// Yarılanma verileri: (birim, yarılanma süresi, yarılanma sayısı).
final List<(String, int, int)> _yarilanma = [
  for (var t = 2; t <= 45; t++)
    for (var k = 2; k <= 6; k++) ('gün', t, k),
  for (var t = 5; t <= 60; t++)
    for (var k = 2; k <= 6; k++) ('yıl', t, k),
];

/// Açık model N(t) = N₀·a^(t/T) verileri: (a, T, k); a^k en çok 1024.
final List<(int, int, int)> _acikModel = [
  for (var t = 2; t <= 26; t++)
    for (final (a, ks) in const [(2, 10), (3, 6), (4, 5), (5, 4), (10, 3)])
      for (var k = 2; k <= ks; k++)
        // Süre yanıtı tabana eşit olmasın.
        if (k * t != a) (a, t, k),
];

int _us(int taban, int kuvvet) {
  var r = 1;
  for (var i = 0; i < kuvvet; i++) {
    r *= taban;
  }
  return r;
}

AdvancedItem _logModel(int a, int b, int c) {
  final eski = _logModelEski(a, b, c);
  final sira = hedefSira(_vaka(a, b, c));
  final j = a + 25 * b;
  // Çeldiriciler: kat ya da yarılanma sayısını süre sanma, çarpanı periyotla
  // çarpma, bir dönem eksik ya da fazla sayma, üs yerine çarpma, toplam süreyi
  // periyot sanma; en sonda komşu değerler.
  final List<int?> aday;
  String birim = '';
  switch (c) {
    case 0 || 1 || 8:
      final (ca, tt, k) = _katlanma[(j * 7 + 11 * c) % _katlanma.length];
      final t = k * tt;
      final n0 = _susSec(_baslangic, j + c, {
        t,
        tt,
        if (t % _us(ca, k) == 0) t ~/ _us(ca, k),
      });
      final n = n0 * _us(ca, k);
      if (c == 0) {
        birim = 'dk';
        aday = [
          ...[_us(ca, k) * tt, (k - 1) * tt, (k + 1) * tt, k, k * ca * tt],
          ...[tt, (k - 2) * tt, (k + 2) * tt, ..._komsuTam(t)],
        ];
      } else if (c == 1) {
        aday = [
          ...[n0 * _us(ca, k + 1), n0 * ca * k, n0 * _us(ca, k - 1)],
          if (k <= 4) n0 * _us(ca + 1, k),
          ...[n0 * (1 + ca * k), n0 * _us(k, ca)],
          if (k >= 3) n0 * _us(ca, k - 2),
          ...[n0 * _us(ca, k + 2), n - n0, ..._komsuTam(n)],
        ];
      } else {
        birim = 'dk';
        aday = [
          ...[t ~/ _us(ca, k), t ~/ (k - 1), t ~/ (k + 1), t ~/ 2, t],
          if (t % ca == 0) t ~/ ca,
          ...[k * t, ..._komsuTam(tt)],
        ];
      }
    case 2 || 3 || 9:
      final (bir, tt, k) = _yarilanma[(j * 7 + 13 * c) % _yarilanma.length];
      final t = k * tt;
      final m = _susSec(_kalanKutle, j + c, {
        t,
        tt,
        if (t % _us(2, k) == 0) t ~/ _us(2, k),
      });
      final m0 = m * _us(2, k);
      if (c == 2) {
        birim = bir;
        aday = [
          ...[_us(2, k) * tt, (k - 1) * tt, (k + 1) * tt, k],
          ...[_us(2, k) * tt ~/ 2, tt, (k - 2) * tt, (k + 2) * tt],
          ..._komsuTam(t),
        ];
      } else if (c == 3) {
        birim = 'g';
        aday = [
          // Tam bölünmeyen hatalı sonuçlar (aşağı yuvarlanır) sona alınır.
          if (m0 % (2 * k) == 0) m0 ~/ (2 * k),
          if (m.isEven) m ~/ 2,
          ...[2 * m, m0 - m, m0 ~/ 2],
          if (m % 4 == 0) m ~/ 4,
          if (m0 % (2 * k) != 0) m0 ~/ (2 * k),
          ..._komsuTam(m),
        ];
      } else {
        birim = bir;
        aday = [
          ...[t ~/ (k + 1), t ~/ (k - 1), t * m ~/ m0, t ~/ 2, t],
          if (k >= 3 && t % (k - 2) == 0) t ~/ (k - 2),
          ...[k * t, ..._komsuTam(tt)],
        ];
      }
    case 4:
      final (tur, x, y, ki, n) = _logSureVeri[j];
      final (kat, _) = _katlar[ki];
      if (tur == 1) {
        birim = 'saat';
        var katlanma = 0;
        for (var u = 1; u < kat; u *= x) {
          katlanma++;
        }
        aday = [
          ...[n - 1, y * katlanma, n + 1, y * ((kat + x - 1) ~/ x)],
          ...[y * kat ~/ x, n - 2, n + 2, n - 3, n + 3],
        ];
      } else {
        final (yuzde, _, _, _, _, _) = _oranlar[x];
        final yp = yuzde.abs();
        final dogrusal = yuzde > 0
            ? ((kat - 1) * 100 + yp - 1) ~/ yp
            : ((kat - 1) * 100 + kat * yp - 1) ~/ (kat * yp);
        aday = [n - 1, n + 1, dogrusal, n + 2, n - 2, n - 3, n + 3, n + 4];
      }
    case 5:
      final (bir, tt, k) = _yarilanma[(j * 11 + 5) % _yarilanma.length];
      birim = bir;
      final t = k * tt;
      aday = [
        ...[k, _us(2, k) * tt, (k - 1) * tt, (k + 1) * tt, tt],
        ...[(k - 2) * tt, (k + 2) * tt, ..._komsuTam(t)],
      ];
    default:
      final (ta, tt, k) = _acikModel[(j * 7 + 19 * c) % _acikModel.length];
      final t = k * tt;
      final n0 = _susSec(_baslangic, j + 2 * c, {
        t,
        if (t % _us(ta, k) == 0) t ~/ _us(ta, k),
      });
      final n = n0 * _us(ta, k);
      if (c == 6) {
        birim = 'saat';
        aday = [
          ...[k, _us(ta, k) * tt, (k - 1) * tt, (k + 1) * tt, tt],
          ...[(k - 2) * tt, (k + 2) * tt, ..._komsuTam(t)],
        ];
      } else {
        aday = [
          ...[n0 * _us(ta, k + 1), n0 * ta * k, n0 * _us(ta, k - 1), n0 * t],
          if (ta <= 3) n0 * _us(k, ta),
          if (k >= 3) n0 * _us(ta, k - 2),
          ...[n0 * _us(ta, k + 2), n - n0, ..._komsuTam(n)],
        ];
      }
  }
  final deger = num.parse(eski.correct.split(' ').first);
  return _dengele(
    eski,
    deger,
    _tamAday(aday, birim: birim, pozitif: true),
    sira,
  );
}

AdvancedItem _logModelEski(int a, int b, int c) {
  final j = a + 25 * b;
  switch (c) {
    case 0 || 1 || 8:
      final (ca, tt, k) = _katlanma[(j * 7 + 11 * c) % _katlanma.length];
      final t = k * tt;
      final n0 = _susSec(_baslangic, j + c, {
        t,
        tt,
        if (t % _us(ca, k) == 0) t ~/ _us(ca, k),
      });
      final n = n0 * _us(ca, k);
      final kat = ca == 2 ? 'iki' : 'üç';
      if (c == 0) {
        return _tam(
          'Bir bakteri kültüründeki bakteri sayısı her $tt dakikada bir $kat '
              'katına çıkmaktadır. Başlangıçta $n0 bakteri bulunan kültürde '
              'bakteri sayısı kaç dakika sonra $n olur?',
          t,
          [_us(ca, k) * tt, (k + 1) * tt, (k - 1) * tt, k * ca * tt],
          '$n/$n0 = ${_us(ca, k)} = $ca${_ust(k)} olduğundan sayı $k kez $kat '
              'katına çıkmalıdır. Geçen süre $k·$tt = $t dakikadır.',
          birim: 'dk',
          pozitif: true,
        );
      }
      if (c == 1) {
        return _tam(
          'Bir bakteri kültüründeki bakteri sayısı her $tt dakikada bir $kat '
              'katına çıkmaktadır. Başlangıçta $n0 bakteri bulunan kültürde $t '
              'dakika sonra kaç bakteri bulunur?',
          n,
          [
            n0 * ca * k,
            n0 * _us(ca, k + 1),
            n0 * _us(ca, k - 1),
            n0 * (1 + ca * k),
          ],
          '$t dakikada $t/$tt = $k kez $kat katına çıkılır. Bakteri sayısı '
              '$n0·$ca${_ust(k)} = $n olur.',
          pozitif: true,
        );
      }
      return _tam(
        'Bir bakteri kültüründe bakteri sayısı eşit zaman aralıklarında $kat '
            'katına çıkmaktadır. Başlangıçta $n0 olan bakteri sayısı $t dakika '
            'sonra $n olduğuna göre bu zaman aralığı kaç dakikadır?',
        tt,
        [t ~/ _us(ca, k), t ~/ (k + 1), t ~/ (k - 1), t ~/ 2],
        '$n/$n0 = $ca${_ust(k)} olduğundan $t dakikada $k kez $kat katına '
            'çıkılmıştır. Aralık $t/$k = $tt dakikadır.',
        birim: 'dk',
        pozitif: true,
      );
    case 2 || 3 || 9:
      final (birim, tt, k) = _yarilanma[(j * 7 + 13 * c) % _yarilanma.length];
      final t = k * tt;
      final m = _susSec(_kalanKutle, j + c, {
        t,
        tt,
        if (t % _us(2, k) == 0) t ~/ _us(2, k),
      });
      final m0 = m * _us(2, k);
      if (c == 2) {
        return _tam(
          'Yarılanma süresi $tt $birim olan radyoaktif bir maddenin $m0 gramı '
              'kaç $birim sonra $m grama iner?',
          t,
          [(m0 ~/ m) * tt, (k + 1) * tt, (k - 1) * tt, (m0 ~/ m) * tt ~/ 2],
          '$m0/$m = ${_us(2, k)} = 2${_ust(k)} olduğundan madde $k kez '
              'yarılanmalıdır. Geçen süre $k·$tt = $t $birim olur.',
          birim: birim,
          pozitif: true,
        );
      }
      if (c == 3) {
        return _tam(
          'Yarılanma süresi $tt $birim olan radyoaktif bir maddenin $m0 '
              'gramından $t $birim sonra kaç gram kalır?',
          m,
          [m0 ~/ (2 * k), m0 ~/ _us(2, k - 1), m0 - m, m0 ~/ _us(2, k + 1)],
          '$t $birim içinde $t/$tt = $k kez yarılanma olur. Kalan miktar '
              '$m0/2${_ust(k)} = $m0/${_us(2, k)} = $m gramdır.',
          birim: 'g',
          pozitif: true,
        );
      }
      return _tam(
        'Radyoaktif bir maddenin $m0 gramı $t $birim sonra $m grama inmiştir. '
            'Bu maddenin yarılanma süresi kaç $birim olur?',
        tt,
        [t ~/ (k + 1), t ~/ (k - 1), t * m ~/ m0, t ~/ 2],
        '$m0/$m = 2${_ust(k)} olduğundan $t $birim içinde $k kez yarılanma '
            'olmuştur. Yarılanma süresi $t/$k = $tt $birim olur.',
        birim: birim,
        pozitif: true,
      );
    case 4:
      final (tur, x, y, ki, n) = _logSureVeri[j];
      final (kat, klg) = _katlar[ki];
      if (tur == 1) {
        final lg = x == 2 ? 301 : 477;
        final oran = y * klg / lg;
        // Model sürekli verilir: "her y saatte bir katlanma" basamaklı
        // okunursa yanıt y'nin katına yuvarlanırdı; bu yol çeldiricidir.
        var katlanma = 0;
        for (var u = 1; u < kat; u *= x) {
          katlanma++;
        }
        return _tam(
          'Bir bakteri kültüründeki bakteri sayısı, başlangıçtaki sayı N₀ olmak '
              'üzere t saat sonra N(t) = N₀·$x^(t/$y) bağıntısıyla veriliyor. '
              'Bakteri sayısının başlangıçtakinin en az $kat katı olması için '
              'en az kaç tam saat geçmelidir? $_logNot',
          n,
          [n - 1, y * katlanma, n + 1, y * ((kat + x - 1) ~/ x), y * kat ~/ x],
          'N(t)/N₀ = $x^(t/$y) ≥ $kat için (t/$y)·log $x ≥ log $kat, yani '
              't ≥ $y·${tr(klg / 1000, 3)}/${tr(lg / 1000, 3)} ≈ ${tr(oran, 2)} '
              'olmalıdır; en az $n tam saat geçmelidir.',
          birim: 'saat',
          pozitif: true,
        );
      }
      final (yuzde, lg, carpan, baglam, birim, turetim) = _oranlar[x];
      final artis = yuzde > 0;
      final levha = birim == 'levha';
      final soru = levha
          ? 'Işık şiddetinin başlangıçtaki değerin 1/$kat katına ya da daha '
                'azına inmesi için ışık en az kaç levhadan geçmelidir?'
          : (artis
                ? 'Bu miktarın başlangıçtakinin en az $kat katı olması için en '
                      'az kaç $birim geçmesi gerekir?'
                : 'Bu miktarın başlangıçtaki değerin 1/$kat katına ya da '
                      'daha azına inmesi için en az kaç $birim geçmesi '
                      'gerekir?');
      final esitsizlik = artis
          ? '($carpan)ⁿ ≥ $kat, yani n·log $carpan ≥ log $kat'
          : '($carpan)ⁿ ≤ 1/$kat, yani n·log $carpan ≤ −log $kat';
      final oran = klg / lg.abs();
      // Doğrusal düşünme hatası: her adımda başlangıcın yüzdesi kadar değişim.
      final yp = yuzde.abs();
      final dogrusal = artis
          ? ((kat - 1) * 100 + yp - 1) ~/ yp
          : ((kat - 1) * 100 + kat * yp - 1) ~/ (kat * yp);
      final adim = levha ? 'levha' : birim;
      return _tam(
        '$baglam $soru $_logNot',
        n,
        [n - 1, n + 1, dogrusal, n + 2],
        'n $adim sonra miktar başlangıcın ($carpan)ⁿ katı olur. $esitsizlik '
            'olmalıdır. $turetim ve log $kat = ${tr(klg / 1000, 3)} olduğundan '
            'n ≥ ${tr(oran, 2)} bulunur; en az $n $adim.',
        pozitif: true,
      );
    case 5:
      // Azalma modeli m(t) = m₀·(1/2)^(t/T): kütlenin verilen değere inme süresi.
      final (birim, tt, k) = _yarilanma[(j * 11 + 5) % _yarilanma.length];
      final t = k * tt;
      final m = _susSec(_kalanKutle, j + 3, {
        t,
        tt,
        if (t % _us(2, k) == 0) t ~/ _us(2, k),
      });
      final m0 = m * _us(2, k);
      return _tam(
        'Bir maddenin kütlesi t $birim sonunda m(t) = $m0·(1/2)^(t/$tt) gram '
            'olarak modelleniyor. Kütle kaç $birim sonra $m grama iner?',
        t,
        [k, (m0 ~/ m) * tt, (k + 1) * tt, (k - 1) * tt],
        '$m0·(1/2)^(t/$tt) = $m eşitliğinden (1/2)^(t/$tt) = 1/${_us(2, k)} '
            '= (1/2)${_ust(k)} olur. t/$tt = $k ve t = $t $birim bulunur.',
        birim: birim,
        pozitif: true,
      );
    default:
      // c = 6, 7: N(t) = N₀·a^(t/T) açık modeli.
      final (ta, tt, k) = _acikModel[(j * 7 + 19 * c) % _acikModel.length];
      final t = k * tt;
      final n0 = _susSec(_baslangic, j + 2 * c, {
        t,
        if (t % _us(ta, k) == 0) t ~/ _us(ta, k),
      });
      final n = n0 * _us(ta, k);
      final ifade = 'N(t) = $n0·$ta^(t/$tt)';
      if (c == 6) {
        return _tam(
          'Bir bakteri kolonisindeki bakteri sayısı t saat sonra $ifade '
              'bağıntısıyla veriliyor. Bakteri sayısı kaç saat sonra $n olur?',
          t,
          [k, (n ~/ n0) * tt, (k + 1) * tt, (k - 1) * tt],
          '$ifade = $n eşitliğinden $ta^(t/$tt) = ${_us(ta, k)} = '
              '$ta${_ust(k)} olur. t/$tt = $k ve t = $t saat bulunur.',
          birim: 'saat',
          pozitif: true,
        );
      }
      return _tam(
        'Bir bakteri kolonisindeki bakteri sayısı t saat sonra $ifade '
            'bağıntısıyla veriliyor. $t saat sonra bakteri sayısı kaç olur?',
        n,
        [n0 * ta * k, n0 * _us(ta, k + 1), n0 * t, n0 * _us(ta, k - 1)],
        't = $t için t/$tt = $k olur. N($t) = $n0·$ta${_ust(k)} = $n bulunur.',
        pozitif: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 11 · Parçalı tanımlı fonksiyonlar
// ---------------------------------------------------------------------------

/// Sıfırı atlayan simetrik aralık: i = 0 … → −alt, …, −1, 1, 2, …
int _sifirsiz(int i, int alt) {
  final x = i - alt;
  return x >= 0 ? x + 1 : x;
}

/// Birinci parça: αx + β.
const _parcaDog = [
  (2, 1),
  (3, -2),
  (-1, 4),
  (-2, 3),
  (1, 5),
  (2, -3),
  (3, 1),
  (-1, -2),
  (-3, 2),
  (1, -4),
  (2, 5),
  (4, -1),
  (-2, -1),
  (-1, 6),
  (3, -5),
  (1, 2),
  (-4, 3),
  (2, -5),
  (5, -2),
  (-3, -1),
  (4, 3),
  (-2, 5),
  (1, -6),
  (3, 4),
  (-1, 1),
];

/// İkinci parça: μx² + νx + ρ.
const _parcaKare = [
  (1, 0, -3),
  (1, -2, 1),
  (-1, 0, 4),
  (1, 1, -2),
  (2, 0, -5),
  (1, -3, 2),
  (-1, 2, 3),
  (1, 0, 2),
  (1, 2, -4),
  (-1, -1, 6),
  (2, -1, -3),
  (1, -4, 5),
  (-1, 0, 1),
  (1, 3, 0),
  (1, -1, -6),
  (-2, 0, 7),
  (1, 0, -8),
  (1, 2, 3),
  (-1, 3, -2),
  (2, 1, -1),
];

/// İki parçalı fonksiyon: x < k (tür 0) ya da x ≤ k (tür 1) için birinci,
/// diğer x değerleri için ikinci parça.
class _Parcali {
  final List<int> p1, p2;
  final int k, tur;
  const _Parcali(this.p1, this.p2, this.k, this.tur);

  bool birinci(int x) => tur == 0 ? x < k : x <= k;
  int deger(int x) => birinci(x) ? _deg(p1, x) : _deg(p2, x);
  int ters(int x) => birinci(x) ? _deg(p2, x) : _deg(p1, x);

  String get tanim {
    final s1 = tur == 0 ? '<' : '≤', s2 = tur == 0 ? '≥' : '>';
    return 'Gerçek sayılarda tanımlı f fonksiyonu x $s1 ${_n(k)} için '
        'f(x) = ${_pol(p1)}, x $s2 ${_n(k)} için f(x) = ${_pol(p2)} biçiminde '
        'tanımlanıyor.';
  }

  /// f(x) hesabının açıklaması: hangi parça, yerine koyma.
  String hesap(int x) {
    final p = birinci(x) ? p1 : p2;
    return 'f(${_n(x)}) = ${_yerine(p, x)} = ${_n(_deg(p, x))}';
  }
}

/// Tek ve çift tam sayılara göre tanımlı kuralda tekler için (α, β): αn + β.
const _tekKural = [
  (3, 1),
  (1, 3),
  (3, -1),
  (5, 1),
  (1, 5),
  (3, 3),
  (5, -1),
  (1, -3),
  (7, 1),
  (5, 3),
  (3, 5),
  (1, 1),
  (7, -1),
  (3, -3),
  (5, 5),
  (7, 3),
  (1, -1),
  (5, -3),
  (7, 5),
  (3, 7),
];

/// f(f(p)) soruları için birinci parça adayları: αx + β.
final List<(int, int)> _parcaAday = [
  for (final be in const [1, -3, 4, -2, 5, 3, -5, 2, -1, 6])
    for (final al in const [-1, 2, -2, 3, -3]) (al, be),
];

/// İç değeri öteki parçaya düşen bir p arar; kırılma noktası c'ye özgü
/// listeden alınır. Yanıtın p, f(p) ya da k sayısına eşit olmadığı seçim
/// öncelik taşır.
(_Parcali, int)? _ffBul(List<int> e1, List<int> e2, int tur, int c) {
  const kListe = [
    [0, 2, -2, 4, -4, 6],
    [1, -1, 3, -3, 5, -5],
    [7, -6, 8, -7, 9, -8],
  ];
  (_Parcali, int)? yedek;
  for (final k in kListe[c - 3]) {
    final f = _Parcali(e1, e2, k, tur);
    final adaylar = [
      for (final d in const [-2, 2, -1, 1, -3, 3, 0, -4, 4, -5, 5, -6, 6])
        k + d,
    ];
    bool gecis(int x) {
      final ic = f.deger(x);
      return f.birinci(x) != f.birinci(ic) && ic.abs() <= 12;
    }

    bool temiz(int x) {
      final ic = f.deger(x), y = f.deger(ic);
      // Yanıt kökte yazılı sayılara ve hatalı yolların sonuçlarına eşit
      // olmasın.
      final yazili = {
        for (final v in [...e1, ...e2, k, x]) ...[v, -v],
      };
      final hata = {f.ters(ic), ic, 2 * ic, f.ters(f.ters(x))};
      return gecis(x) &&
          !yazili.contains(y) &&
          !hata.contains(y) &&
          y.abs() <= 150;
    }

    for (final x in adaylar) {
      if (temiz(x)) return (f, x);
    }
    if (yedek == null) {
      for (final x in adaylar) {
        if (gecis(x)) {
          yedek = (f, x);
          break;
        }
      }
    }
  }
  return yedek;
}

AdvancedItem _parcaliSoru(int a, int b, int c, int deneme) {
  if (c <= 5) {
    final (al, be) = _parcaDog[a];
    final (mu, nu, ro) = _parcaKare[b];
    final tur = (a + b) % 2;
    if (c <= 2) {
      final k = const [
        [-1, -4, 4],
        [1, -3, 5],
        [2, 3, -2],
      ][c][deneme % 3];
      final f = _Parcali([al, be], [mu, nu, ro], k, tur);
      // Her parçadan bir nokta; sınır noktası hangi parçadaysa ona yazılır.
      final ofs = const [2, 3, 1][deneme ~/ 3 % 3];
      final p = tur == 0 ? k - ofs : k, q = tur == 0 ? k : k + ofs;
      final yanit = f.deger(p) + f.deger(q);
      return _tam(
        '${f.tanim} Buna göre f(${_n(p)}) + f(${_n(q)}) toplamı kaçtır?',
        yanit,
        [
          f.ters(p) + f.deger(q),
          f.deger(p) + f.ters(q),
          f.ters(p) + f.ters(q),
          f.deger(p) - f.deger(q),
        ],
        '${_n(p)} birinci, ${_n(q)} ikinci parçanın tanım aralığındadır. '
            '${f.hesap(p)} ve ${f.hesap(q)} olduğundan toplam ${_n(yanit)} olur.',
      );
    }
    // f(f(p)): birinci parça, iki parçanın da kullanıldığı bir f(f(p))
    // sorusu kurulabilen adaylar arasından seçilir.
    final e2 = [mu, nu, ro];
    final e1 = _uygun(
      _parcaAday,
      a,
      (e) => _ffBul([e.$1, e.$2], e2, tur, c) != null,
    );
    final (f, p) = _ffBul([e1.$1, e1.$2], e2, tur, c)!;
    final ic = f.deger(p);
    final yanit = f.deger(ic);
    return _tam(
      '${f.tanim} Buna göre f(f(${_n(p)})) değeri kaçtır?',
      yanit,
      [f.ters(ic), ic, f.deger(p) * 2, f.ters(f.ters(p))],
      'Önce ${f.hesap(p)} bulunur. ${_n(ic)} öteki parçanın tanım aralığında '
          'olduğundan ${f.hesap(ic)} olur. f(f(${_n(p)})) = ${_n(yanit)}.',
    );
  }
  if (c <= 7) {
    final (al, be) = _tekKural[b];
    int f(int n) => n.isEven ? n ~/ 2 : al * n + be;
    final derin = c == 6 ? 3 : 2;
    // Zincirde tek kural en az bir kez kullanılsın; yanıt başlangıç değerine
    // ya da kuraldaki sayılara eşit olmasın.
    int karisik(int n) => n.isOdd ? n ~/ 2 : al * n + be;
    final n0 = _uygun([for (var x = 3; x <= 120; x++) x], a, (x) {
      var y = x, yk = x, tek = false;
      final ara = <int>[];
      for (var i = 0; i < derin; i++) {
        if (y.isOdd) tek = true;
        ara.add(y);
        y = f(y);
        yk = karisik(yk);
      }
      // Yanıt başlangıca, ara değerlere, kuraldaki sayılara ve hatalı
      // yolların sonuçlarına eşit olmasın.
      final hata = {...ara, yk, f(y), 2 * y, 2, al, be, -be};
      return tek && !hata.contains(y) && y.abs() <= 999;
    });
    final adim = <String>[];
    var y = n0;
    for (var i = 0; i < derin; i++) {
      final z = f(y);
      adim.add(
        y.isEven
            ? 'f(${_n(y)}) = ${_n(y)}/2 = ${_n(z)}'
            : 'f(${_n(y)}) = ${al == 1 ? '' : '$al·'}${_p(y)} '
                  '${be < 0 ? '−' : '+'} ${be.abs()} = ${_n(z)}',
      );
      y = z;
    }
    final ifade = derin == 3 ? 'f(f(f(${_n(n0)})))' : 'f(f(${_n(n0)}))';
    // Hatalı yollar: tek/çift kuralını karıştırma, bir adım eksik ya da fazla.
    var yk = n0, ye = n0;
    for (var i = 0; i < derin; i++) {
      yk = karisik(yk);
    }
    for (var i = 0; i < derin - 1; i++) {
      ye = f(ye);
    }
    return _tam(
      'Tam sayılar kümesinde tanımlı f fonksiyonu n çift ise f(n) = n/2, n tek '
          'ise f(n) = ${_pol([al, be], 'n')} biçiminde tanımlanıyor. Buna göre '
          '$ifade değeri kaçtır?',
      y,
      [yk, ye, f(y), y * 2],
      '${adim.join(', ')} olduğundan $ifade = ${_n(y)} bulunur.',
    );
  }
  // c = 8, 9: f(t) = v eşitliğini sağlayan t değerlerinin toplamı.
  final (al, be) = _parcaDog[a];
  // s doğrusal parçanın katsayılarına eşit olmasın (yanıt çoğu kez s'dir);
  // c = 8 ile c = 9 ayrık s kümeleri kullanır.
  final s = _uygun(
    c == 8 ? const [5, 6, 7, 8, 9] : const [3, 4, 2, 10, 11],
    b ~/ 10,
    (x) => x != al.abs() && x != be.abs(),
  );
  // γ = ±s iken yanıt s kökte yazılı kalırdı.
  final gamma = _uygun(
    const [-4, -3, -2, -1, 1, 2, 3, 4, 7, -7, 8, -8],
    b % 10,
    (x) => x != s && x != -s,
  );
  final k = c == 8
      ? const [0, 1, -1, 2, 3, -2, 4, -3, 5][deneme % 9]
      : const [-3, -4, -2, -5, -1, 2, 3, 1, 0][deneme % 9];
  final tur = (a + b) % 2;
  final v = s * s + gamma;
  bool birinci(_R x) => tur == 0 ? x.p < k * x.q : x.p <= k * x.q;
  final dogrusal = _R(v - be, al);
  final adaylar = <(_R, bool, String)>[
    (dogrusal, birinci(dogrusal), 'birinci parça'),
    (_R(s), !birinci(_R(s)), 'ikinci parça'),
    (_R(-s), !birinci(_R(-s)), 'ikinci parça'),
  ];
  final gecerli = [
    for (final e in adaylar)
      if (e.$2) e.$1,
  ];
  if (gecerli.isEmpty) _kirli = true;
  final yanit = gecerli.fold(_R(0), (t, e) => t + e);
  final s1 = tur == 0 ? '<' : '≤', s2 = tur == 0 ? '≥' : '>';
  String kokYaz(int r, bool g) =>
      '${_n(r)} ikinci parçanın aralığında${g ? 'dır' : ' değildir'}';
  final kareGecerlik = adaylar[1].$2 == adaylar[2].$2
      ? '$s ve −$s ikinci parçanın aralığında'
            '${adaylar[1].$2 ? 'dır' : ' değildir'}'
      : '${kokYaz(s, adaylar[1].$2)}, ${kokYaz(-s, adaylar[2].$2)}';
  final aciklama =
      '${_pol([al, be], 't')} = ${_n(v)} için t = $dogrusal; bu değer birinci '
      'parçanın aralığında${adaylar[0].$2 ? 'dır' : ' değildir'}. '
      't² ${gamma < 0 ? '−' : '+'} ${gamma.abs()} = ${_n(v)} için t = $s ya da '
      't = −$s; $kareGecerlik';
  return _ras(
    'Gerçek sayılarda tanımlı f fonksiyonu x $s1 ${_n(k)} için '
        'f(x) = ${_pol([al, be])}, x $s2 ${_n(k)} için f(x) = '
        '${_pol([1, 0, gamma])} biçiminde tanımlanıyor. f(t) = ${_n(v)} '
        'eşitliğini sağlayan t değerlerinin toplamı kaçtır?',
    yanit,
    // Tanım aralıklarını yok sayan bütün köklerin toplamını (doğrusal kök
    // + s − s) bulur; ±s'den birini yanlış alan yanıtı s kadar kaydırır.
    [dogrusal, yanit + _R(s), yanit - _R(s)],
    '$aciklama. Geçerli değerlerin toplamı $yanit olur.',
  );
}

// ---------------------------------------------------------------------------
// 12 · Fonksiyon grafiklerinde öteleme ve yansıma
// ---------------------------------------------------------------------------

String _nokta(int x, int y) => '(${_n(x)}, ${_n(y)})';

/// f(x − h) yazımı: `_kayik(4)` → `x − 4`, `_kayik(-3)` → `x + 3`.
String _kayik(int h) => h > 0 ? 'x − $h' : 'x + ${-h}';

String _sabitEk(int k) => k == 0 ? '' : (k > 0 ? ' + $k' : ' − ${-k}');

AdvancedItem _grafikDonusum(int a, int b, int c, int deneme) {
  final p = _sifirsiz(a, 12);
  final q = _sifirsiz(b, 10);
  final h = (1 + (a + 2 * b + deneme) % 6) * ((a + b).isEven ? 1 : -1);
  final k = (1 + (2 * a + b + 3 * deneme) % 7) * ((a ~/ 3 + b).isEven ? 1 : -1);
  if (c <= 3) {
    final (ifade, x, y, adim) = switch (c) {
      0 => (
        'f(${_kayik(h)})${_sabitEk(k)}',
        p + h,
        q + k,
        'y = f(${_kayik(h)})${_sabitEk(k)} grafiği, f grafiğinin '
            '${h > 0 ? 'sağa' : 'sola'} ${h.abs()} birim ve '
            '${k > 0 ? 'yukarı' : 'aşağı'} ${k.abs()} birim ötelenmiş '
            'hâlidir: (${_n(p)} ${h > 0 ? '+' : '−'} ${h.abs()}, ${_n(q)} '
            '${k > 0 ? '+' : '−'} ${k.abs()})',
      ),
      1 => (
        '−f(x)${_sabitEk(k)}',
        p,
        k - q,
        '−f(x) grafiği f grafiğinin x eksenine göre yansımasıdır; nokta '
            '(${_n(p)}, ${_n(-q)}) olur. Sonra ${k > 0 ? 'yukarı' : 'aşağı'} '
            '${k.abs()} birim ötelenir: (${_n(p)}, ${_n(-q)} '
            '${k > 0 ? '+' : '−'} ${k.abs()})',
      ),
      2 => (
        'f(−x)${_sabitEk(k)}',
        -p,
        q + k,
        'f(−x) grafiği f grafiğinin y eksenine göre yansımasıdır; nokta '
            '(${_n(-p)}, ${_n(q)}) olur. Sonra ${k > 0 ? 'yukarı' : 'aşağı'} '
            '${k.abs()} birim ötelenir: (${_n(-p)}, ${_n(q)} '
            '${k > 0 ? '+' : '−'} ${k.abs()})',
      ),
      _ => (
        '−f(${_kayik(h)})',
        p + h,
        -q,
        'f(${_kayik(h)}) grafiği ${h > 0 ? 'sağa' : 'sola'} ${h.abs()} birim '
            'ötelemedir; nokta (${_n(p + h)}, ${_n(q)}) olur. Başa gelen eksi '
            'x eksenine göre yansıma yapar ve ordinatın işaretini değiştirir',
      ),
    };
    final hatalar = switch (c) {
      0 => [_nokta(p - h, q + k), _nokta(p + h, q - k), _nokta(p - h, q - k)],
      1 => [_nokta(p, q + k), _nokta(-p, k - q), _nokta(p, -q - k)],
      2 => [_nokta(p, q + k), _nokta(-p, k - q), _nokta(-p, q - k)],
      _ => [_nokta(p - h, -q), _nokta(p + h, q), _nokta(-p - h, -q)],
    };
    // Yanıt verilen noktaya eşit olmasın.
    if (x == p && y == q) _kirli = true;
    final eski = _secenek(
      'f fonksiyonunun grafiği A${_nokta(p, q)} noktasından geçmektedir. '
          'Buna göre y = $ifade fonksiyonunun grafiği hangi noktadan kesinlikle '
          'geçer?',
      _nokta(x, y),
      [...hatalar, _nokta(y, x), _nokta(x + 1, y), _nokta(x, y + 1)],
      '$adim${c == 3 ? ': ' : ' = '}${_nokta(x, y)}.',
    );
    if (c == 0) return eski;
    // Çeldiriciler apsiste ve ordinatta birer tipik hatanın üç birleşimidir:
    // yansımayı yanlış eksene uygulama ya da unutma, ötelemeyi ters yöne
    // yapma. Her koordinatın doğru değeri iki seçenekte görülür.
    final (x2, y2) = switch (c) {
      1 => (-p, q + k),
      2 => (p, k - q),
      _ => (p - h, q),
    };
    return AdvancedItem(eski.prompt, eski.correct, [
      _nokta(x2, y),
      _nokta(x, y2),
      _nokta(x2, y2),
    ], eski.explanation);
  }
  if (c <= 6) {
    // Ters yön: dönüştürülmüş grafiğin noktasından f grafiğinin noktasına.
    final (ifade, bx, by, adim) = switch (c) {
      4 => (
        'f(${_kayik(h)})${_sabitEk(k)}',
        p + h,
        q + k,
        'x = ${_n(p + h)} için f(${_n(p + h)} ${h > 0 ? '−' : '+'} '
            '${h.abs()})${_sabitEk(k)} = ${_n(q + k)}, yani f(${_n(p)}) = '
            '${_n(q + k)} ${k > 0 ? '−' : '+'} ${k.abs()} = ${_n(q)} olur',
      ),
      5 => (
        '−f(x)${_sabitEk(k)}',
        p,
        k - q,
        'x = ${_n(p)} için −f(${_n(p)})${_sabitEk(k)} = ${_n(k - q)}, yani '
            'f(${_n(p)}) = ${_n(k)} − ${_p(k - q)} = ${_n(q)} olur',
      ),
      _ => (
        'f(−x)${_sabitEk(k)}',
        -p,
        q + k,
        'x = ${_n(-p)} için f(${_n(p)})${_sabitEk(k)} = ${_n(q + k)}, yani '
            'f(${_n(p)}) = ${_n(q)} olur',
      ),
    };
    final hatalar = switch (c) {
      4 => [
        _nokta(bx + h, by + k),
        _nokta(bx - h, by + k),
        _nokta(bx + h, by - k),
      ],
      5 => [_nokta(bx, by - k), _nokta(bx, -by - k), _nokta(-bx, k - by)],
      _ => [_nokta(bx, by - k), _nokta(-bx, by + k), _nokta(bx, k - by)],
    };
    if (bx == p && by == q) _kirli = true;
    final eski = _secenek(
      'y = $ifade fonksiyonunun grafiği B${_nokta(bx, by)} noktasından '
          'geçtiğine göre y = f(x) fonksiyonunun grafiği hangi noktadan '
          'kesinlikle geçer?',
      _nokta(p, q),
      [...hatalar, _nokta(q, p), _nokta(p + 1, q), _nokta(p, q + 1)],
      '$adim. f fonksiyonunun grafiği ${_nokta(p, q)} noktasından geçer.',
    );
    if (c == 4) return eski;
    // Apsiste yansımayı geri almayı unutma ya da yanlış eksende yapma,
    // ordinatta eksiyi unutma ya da ötelemeyi ters yönde geri alma: üç
    // birleşim. Her koordinatın doğru değeri iki seçenekte görülür.
    final (x2, y2) = c == 5 ? (-p, -q) : (-p, q + 2 * k);
    return AdvancedItem(eski.prompt, eski.correct, [
      _nokta(x2, q),
      _nokta(p, y2),
      _nokta(x2, y2),
    ], eski.explanation);
  }
  // c = 7, 8, 9: kuralı verilen f ile dönüşüm.
  final f = [
    const [1, -1, 2, -2, 3][a ~/ 5],
    const [-4, -2, 1, 3, 5][a % 5],
    _sifirsiz(b, 9),
  ];
  final hh = h.abs() == 1 ? 2 * h : h; // öteleme en az 2 birim
  switch (c) {
    case 7:
      final yanit = _deg(f, -hh) + k;
      return _tam(
        'f(x) = ${_pol(f)} olmak üzere y = f(${_kayik(hh)})${_sabitEk(k)} '
            'fonksiyonunun grafiğinin y eksenini kestiği noktanın ordinatı '
            'kaçtır?',
        yanit,
        [_deg(f, hh) + k, _deg(f, -hh) - k, _deg(f, 0) + k, _deg(f, -hh)],
        'Grafik y eksenini x = 0 iken keser: y = f(${_n(-hh)})${_sabitEk(k)} '
            'olur. f(${_n(-hh)}) = ${_yerine(f, -hh)} = ${_n(_deg(f, -hh))} '
            'olduğundan ordinat ${_n(yanit)} bulunur.',
      );
    case 8:
      final yanit = -_deg(f, hh);
      return _tam(
        'f(x) = ${_pol(f)} olmak üzere y = −f(${_kayik(-hh)}) fonksiyonunun '
            'grafiğinin y eksenini kestiği noktanın ordinatı kaçtır?',
        yanit,
        [_deg(f, hh), -_deg(f, -hh), -_deg(f, 0), _deg(f, -hh)],
        'Grafik y eksenini x = 0 iken keser: y = −f(${_n(hh)}) olur. '
            'f(${_n(hh)}) = ${_yerine(f, hh)} = ${_n(_deg(f, hh))} olduğundan '
            'ordinat ${_n(yanit)} bulunur.',
      );
    default:
      final m = p.abs() > 6 ? p ~/ 2 : p;
      final yanit = _deg(f, -m) + k;
      return _tam(
        'f(x) = ${_pol(f)} ve g(x) = f(−x)${_sabitEk(k)} olduğuna göre '
            'g(${_n(m)}) değeri kaçtır?',
        yanit,
        [_deg(f, m) + k, _deg(f, -m) - k, -_deg(f, m) + k, _deg(f, -m)],
        'g(${_n(m)}) = f(${_n(-m)})${_sabitEk(k)} olur. f(${_n(-m)}) = '
            '${_yerine(f, -m)} = ${_n(_deg(f, -m))} olduğundan g(${_n(m)}) = '
            '${_n(yanit)} bulunur.',
      );
  }
}

// ---------------------------------------------------------------------------
// 13 · Parçalı fonksiyonda limit ve süreklilik
// ---------------------------------------------------------------------------

String _sagSol(int k, bool sag) => 'lim (x → ${_n(k)}${sag ? '⁺' : '⁻'}) f(x)';

AdvancedItem _sureklilik(int a, int b, int c, int deneme) {
  final sira = hedefSira(_vaka(a, b, c));
  if (c <= 2) {
    final (al, be) = _parcaDog[a];
    final (mu, nu, ro) = _parcaKare[b];
    final k = const [
      [1, -2, 3, 0],
      [2, -1, -3, 1],
      [-1, 2, -2, 3],
    ][c][deneme % 4];
    final f = _Parcali([al, be], [mu, nu, ro], k, (a + b) % 2);
    final sol = _deg(f.p1, k), sag = _deg(f.p2, k), fk = f.deger(k);
    // x yerine −k koyma (işaret hatası) ile bulunan tek yanlı limitler.
    final solE = _deg(f.p1, -k), sagE = _deg(f.p2, -k);
    // Sürekli noktada sağ ve sol limitler eşittir; soru önemsizleşir.
    if (sol == sag) _kirli = true;
    final limitler =
        'x değeri ${_n(k)} sayısına soldan yaklaşırken birinci, sağdan '
        'yaklaşırken ikinci kural kullanılır: ${_sagSol(k, false)} = '
        '${_yerine(f.p1, k)} = ${_n(sol)}, ${_sagSol(k, true)} = '
        '${_yerine(f.p2, k)} = ${_n(sag)}.';
    switch (c) {
      case 0:
        final eski = _tam(
          '${f.tanim} Buna göre ${_sagSol(k, false)} + ${_sagSol(k, true)} '
              'toplamı kaçtır?',
          sol + sag,
          [2 * sol, 2 * sag, sol - sag, sag - sol],
          '$limitler Toplam ${_n(sol + sag)} olur.',
        );
        // İki limiti tek kuraldan alma, toplamak yerine çıkarma, işaret
        // hatası.
        return _dengele(
          eski,
          sol + sag,
          _tamAday([
            ...[2 * sol, 2 * sag, sol - sag, sag - sol, solE + sagE],
            ...[sol + sagE, solE + sag, -(sol + sag)],
            ..._komsuTam(sol + sag),
          ]),
          sira,
        );
      case 1:
        final hangi = f.birinci(k) ? 'birinci' : 'ikinci';
        final eski = _tam(
          '${f.tanim} Buna göre ${_sagSol(k, false)} + f(${_n(k)}) toplamı '
              'kaçtır?',
          sol + fk,
          [
            f.birinci(k) ? sol + sag : 2 * sol,
            2 * sag,
            sol - fk,
            sag + fk == sol + fk ? sol + sag + 1 : sag + fk,
          ],
          '$limitler f(${_n(k)}) değeri $hangi kuraldan hesaplanır: '
              'f(${_n(k)}) = ${_n(fk)}. Toplam ${_n(sol)} + ${_p(fk)} = '
              '${_n(sol + fk)} olur.',
        );
        // f(k) için yanlış kuralı seçme, limit yerine öteki kuralı kullanma,
        // toplamak yerine çıkarma, işaret hatası.
        return _dengele(
          eski,
          sol + fk,
          _tamAday([
            ...[f.birinci(k) ? sol + sag : 2 * sol, 2 * sag, sol - fk],
            ...[sag + fk, solE + (f.birinci(k) ? solE : sagE), fk - sol],
            ...[-(sol + fk), ..._komsuTam(sol + fk)],
          ]),
          sira,
        );
      default:
        final eski = _tam(
          '${f.tanim} Buna göre ${_sagSol(k, true)} − ${_sagSol(k, false)} '
              'farkı kaçtır?',
          sag - sol,
          [sol - sag, sol + sag, sag, -sol],
          '$limitler Fark ${_n(sag)} − ${_p(sol)} = ${_n(sag - sol)} olur.',
        );
        // Farkı ters alma, toplama, limitlerden birini unutma, işaret hatası.
        return _dengele(
          eski,
          sag - sol,
          _tamAday([
            ...[sol - sag, sol + sag, sag, -sol, sagE - solE],
            ...[-(sol + sag), -sag, sol, solE - sagE],
            ..._komsuTam(sag - sol),
          ]),
          sira,
        );
    }
  }
  if (c <= 5) {
    // x = k noktasında süreklilik: m·k + β = k² + γk + δ.
    final gamma = const [-3, -2, -1, 1, 2][a % 5];
    final delta = const [-4, -1, 2, 5, 3][a ~/ 5];
    // m kökteki katsayılara eşit olmasın.
    final m = _uygun(
      [
        for (var x = -10; x <= 10; x++)
          if (x != 0) x,
        -11,
        11,
        -12,
        12,
        -13,
        13,
      ],
      b,
      (x) => !{gamma, -gamma, delta, -delta}.contains(x),
    );
    // c'ye göre ayrık kırılma noktaları: kalıp aynı, kökler farklı kalsın.
    final k = const [
      [2, -2, 4],
      [-1, 1, -4],
      [3, -3, 5],
    ][c - 3][deneme % 3];
    final sag = [1, gamma, delta];
    final hedef = _deg(sag, k);
    final be = hedef - m * k;
    final tur = (a + b) % 2;
    final s1 = tur == 0 ? '<' : '≤', s2 = tur == 0 ? '≥' : '>';
    final sol = be == 0 ? 'mx' : 'mx ${be < 0 ? '−' : '+'} ${be.abs()}';
    final eski = _ras(
      'Gerçek sayılarda tanımlı f fonksiyonu x $s1 ${_n(k)} için f(x) = $sol, '
          'x $s2 ${_n(k)} için f(x) = ${_pol(sag)} biçiminde tanımlanıyor. f '
          'fonksiyonu x = ${_n(k)} noktasında sürekli olduğuna göre m kaçtır?',
      _R(m),
      [
        _R(hedef - be),
        _R(be - hedef, k),
        _R(delta - be, k),
        _R(_deg(sag, -k) - be, k),
      ],
      'Süreklilik için soldan ve sağdan limitler eşit olmalıdır: '
          'm·${_p(k)}${be == 0 ? '' : (be < 0 ? ' − ${-be}' : ' + $be')} = '
          '${_yerine(sag, k)} = ${_n(hedef)}. Buradan '
          '${_pol([k, 0], 'm')} = ${_n(hedef - be)} ve m = ${_n(m)} bulunur.',
    );
    // k ile bölmeyi unutma, işaret hatası, yalnız sabit terimi alma, x
    // yerine −k koyma, sabit terimi yanlış yana geçirme ya da unutma, bölmeyi
    // ters yapma; en sonda komşu değerler.
    return _dengele(
      eski,
      m,
      _rAday([
        ...[_R(hedef - be), _R(be - hedef, k), _R(delta - be, k)],
        ...[_R(_deg(sag, -k) - be, k), _R(hedef + be, k), _R(hedef, k)],
        ...[_R(k, hedef - be), _R(m + 1), _R(m - 1), _R(m + 2), _R(m - 2)],
      ]),
      sira,
    );
  }
  if (c == 6) {
    // Kaldırılabilir süreksizlik: (x − r)(x − s)/(x − r).
    final r = _sifirsiz(a, 12);
    AdvancedItem kur(int s) {
      final pay = [1, -(r + s), r * s];
      final yanit = r - s;
      final eski = _tam(
        'Gerçek sayılarda tanımlı f fonksiyonu x ≠ ${_n(r)} için f(x) = '
            '(${_pol(pay)})/(${_pol([1, -r])}), x = ${_n(r)} için f(x) = m '
            'biçiminde tanımlanıyor. f fonksiyonu x = ${_n(r)} noktasında sürekli '
            'olduğuna göre m kaçtır?',
        yanit,
        [r + s, s - r, r * s, 0],
        'Pay (${_pol([1, -r])})·(${_pol([1, -s])}) biçiminde çarpanlarına '
            'ayrılır; x ≠ ${_n(r)} için f(x) = ${_pol([1, -s])} olur. Süreklilik '
            'için m = ${_n(r)} − ${_p(s)} = ${_n(yanit)} olmalıdır.',
      );
      // Çarpanın işaretini yanlış alma, farkı ters alma, sabit terimi ya da
      // 0'ı yanıt sanma, sadeleşen çarpanı unutma.
      return _dengele(
        eski,
        yanit,
        _tamAday([
          ...[r + s, s - r, r * s, 0, -(r + s), -s, r, 2 * r - s],
          ..._komsuTam(yanit),
        ]),
        sira,
      );
    }

    return kur(
      _temizOge(
        'sureklilik6-$a',
        [
          for (final x in _sifirsizAralik(-15, 15))
            if (x != r) x,
        ],
        b,
        kur,
      ),
    );
  }
  if (c == 7) {
    const kokler = [1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6];
    final r = kokler[a % 12];
    final al = 1 + a ~/ 12;
    AdvancedItem kur(int d) {
      final kup = r * r * r;
      final pay = [al, 0, 0, -al * kup];
      final yanit = 3 * al * r * r + d;
      final eski = _tam(
        'Gerçek sayılarda tanımlı f fonksiyonu x ≠ ${_n(r)} için f(x) = '
            '(${_pol(pay)})/(${_pol([1, -r])})${_sabitEk(d)}, x = ${_n(r)} için '
            'f(x) = m biçiminde tanımlanıyor. f fonksiyonu x = ${_n(r)} noktasında '
            'sürekli olduğuna göre m kaçtır?',
        yanit,
        [al * r * r + d, 3 * al * r * r, 2 * al * r * r + d, d],
        '${_pol([1, 0, 0, -kup])} = (${_pol([1, -r])})·(${_pol([1, r, r * r])}) '
            'olduğundan x ≠ ${_n(r)} için f(x) = ${al == 1 ? '' : '$al·'}'
            '(${_pol([1, r, r * r])})${_sabitEk(d)} olur. Süreklilik için m, bu '
            'ifadenin x = ${_n(r)} için değeridir: ${al == 1 ? '' : '$al·'}'
            '${3 * r * r}${_sabitEk(d)} = ${_n(yanit)}.',
      );
      // Bölümde 3 katsayısını, sabiti ya da baş katsayıyı unutma, sabitin
      // işaretini çevirme, r² yerine r alma.
      return _dengele(
        eski,
        yanit,
        _tamAday([
          ...[al * r * r + d, 3 * al * r * r, 2 * al * r * r + d, d],
          ...[3 * al * r * r - d, if (al != 1) 3 * r * r + d, 3 * al * r + d],
          ..._komsuTam(yanit),
        ]),
        sira,
      );
    }

    return kur(_temizOge('sureklilik7-$a', _sifirsizAralik(-15, 15), b, kur));
  }
  // c = 8, 9: iki kırılma noktası, iki parametre.
  final aa = _sifirsiz(a, 12), bb = _sifirsiz(b, 10);
  final (k1, k2, gamma) = const [
    [(-1, 2, 1), (-2, 1, 1), (-1, 3, 2), (1, 3, -1)],
    [(1, 3, -2), (-1, 2, -2), (2, 4, -1), (-2, 1, 3)],
  ][c - 8][deneme % 4];
  final orta = [1, 0, gamma];
  final c1 = _deg(orta, k1) - aa * k1, c3 = _deg(orta, k2) - bb * k2;
  final yanit = c == 8 ? aa + bb : aa * bb;
  // Hatalı çözüm: süreklilik eşitliğinde işaret hatası (a·k1 = c1 − …).
  final aHata = _R(c1 - _deg(orta, k1), k1),
      bHata = _R(c3 - _deg(orta, k2), k2);
  final eski = _ras(
    'Gerçek sayılarda tanımlı f fonksiyonu x < ${_n(k1)} için f(x) = '
        'ax${_sabitEk(c1)}, ${_n(k1)} ≤ x < ${_n(k2)} '
        'için f(x) = ${_pol(orta)}, x ≥ ${_n(k2)} için f(x) = '
        'bx${_sabitEk(c3)} biçiminde tanımlanıyor. f '
        'fonksiyonu her x gerçek sayısı için sürekli olduğuna göre '
        '${c == 8 ? 'a + b toplamı' : 'a·b çarpımı'} kaçtır?',
    _R(yanit),
    c == 8
        ? [aHata + _R(bb), _R(aa) + bHata, _R(aa - bb), _R(aa * bb)]
        : [aHata * _R(bb), _R(aa) * bHata, _R(aa + bb), -_R(aa * bb)],
    'x = ${_n(k1)} noktasında süreklilik: a·${_p(k1)}${_sabitEk(c1)} = '
        '${_n(_deg(orta, k1))}, buradan a = ${_n(aa)}. x = ${_n(k2)} noktasında: '
        '${_n(_deg(orta, k2))} = b·${_p(k2)}${_sabitEk(c3)}, buradan b = '
        '${_n(bb)}. ${c == 8 ? 'a + b' : 'a·b'} = ${_n(yanit)}.',
  );
  // Süreklilik eşitliklerinde işaret hatası (birinde ya da ikisinde), işlemi
  // karıştırma, parametrelerden yalnız birini yanıt sanma.
  return _dengele(
    eski,
    yanit,
    _rAday(
      c == 8
          ? [
              ...[aHata + _R(bb), _R(aa) + bHata, _R(aa - bb), _R(aa * bb)],
              ...[aHata + bHata, _R(bb - aa), -_R(aa + bb), _R(aa), _R(bb)],
            ]
          : [
              ...[aHata * _R(bb), _R(aa) * bHata, _R(aa + bb), -_R(aa * bb)],
              ...[aHata * bHata, _R(aa - bb), _R(aa), _R(bb)],
            ],
    ),
    sira,
  );
}

// ---------------------------------------------------------------------------
// 14 · Zincir kuralı
// ---------------------------------------------------------------------------

/// (p, x₀) çiftleri: 2x₀ + p ve 3x₀² + p ne 0 ne 1 olur (türev sıfır çıkmaz;
/// iç türevi unutan doğru yanıtı bulmaz).
final List<(int, int)> _zincirCift = [
  for (final x0 in const [1, 2, -1, 3, -2])
    for (final p in const [-3, -2, -1, 1, 2, 3, -4, 4])
      if (2 * x0 + p != 0 &&
          3 * x0 * x0 + p != 0 &&
          2 * x0 + p != 1 &&
          3 * x0 * x0 + p != 1)
        (p, x0),
].take(25).toList();

AdvancedItem _zincirKurali(int a, int b, int c, int deneme) {
  switch (c) {
    case 0 || 1:
      // (αx + β)^n ya da (αx² + β)^n; iç ifadenin değeri u.
      final al = const [2, 3, -1, -2, 4][a % 5];
      final x0 = const [1, 2, -1, 3, -2][a ~/ 5];
      final n = 2 + b ~/ 4;
      final kare = c == 1;
      final icDeg = kare ? al * x0 * x0 : al * x0;
      // İç ifadenin sabit terimi sıfır olmasın: (αx)ⁿ zincir kuralı gerektirmez.
      AdvancedItem kur(int u) {
        final be = u - icDeg;
        final ic = kare ? _pol([al, 0, be]) : _pol([al, be]);
        final icTurev = kare ? 2 * al * x0 : al;
        final yanit = n * _us(u, n - 1) * icTurev;
        return _tam(
          'f(x) = ($ic)${_ust(n)} olduğuna göre f′(${_n(x0)}) değeri kaçtır?',
          yanit,
          [
            n * _us(u, n - 1),
            _us(u, n - 1) * icTurev,
            n * _us(u, n) * icTurev,
            (n - 1) * _us(u, n - 1) * icTurev,
          ],
          'Zincir kuralına göre f′(x) = $n·($ic)${n - 1 == 1 ? '' : _ust(n - 1)}'
              '·(${kare ? _pol([2 * al, 0]) : _n(al)}) olur. x = ${_n(x0)} için iç '
              'ifade ${_n(u)}, iç türev ${_n(icTurev)} olduğundan f′(${_n(x0)}) = '
              '$n·${_p(u)}${n - 1 == 1 ? '' : _ust(n - 1)}·${_p(icTurev)} = '
              '${_n(yanit)}.',
        );
      }

      return kur(
        _temizOge(
          'zincir$c-$a-${b ~/ 4}',
          [
            for (final x in const [-2, -1, 1, 2, 3, -3, 4, -4])
              if (x != icDeg) x,
          ],
          b % 4,
          kur,
        ),
      );
    case 2 || 3:
      // (x² + px + q)^n ya da (x³ + px + q)^n.
      final (p, x0) = _zincirCift[a];
      final n = 2 + b ~/ 4;
      AdvancedItem kur(int u) {
        final kup = c == 3;
        final ic0 = kup ? x0 * x0 * x0 + p * x0 : x0 * x0 + p * x0;
        final q = u - ic0;
        final ic = kup ? _pol([1, 0, p, q]) : _pol([1, p, q]);
        final icTurev = kup ? 3 * x0 * x0 + p : 2 * x0 + p;
        final icTurevYaz = kup ? _pol([3, 0, p]) : _pol([2, p]);
        final yanit = n * _us(u, n - 1) * icTurev;
        return _tam(
          'f(x) = ($ic)${_ust(n)} olduğuna göre f′(${_n(x0)}) değeri kaçtır?',
          yanit,
          [
            n * _us(u, n - 1),
            _us(u, n - 1) * icTurev,
            n * _us(u, n - 1) * (kup ? 3 * x0 * x0 : 2 * x0),
            n * _us(icTurev, n - 1),
          ],
          'Zincir kuralına göre f′(x) = $n·($ic)${n - 1 == 1 ? '' : _ust(n - 1)}'
              '·($icTurevYaz) olur. x = ${_n(x0)} için iç ifade ${_n(u)}, iç türev '
              '${_n(icTurev)} olduğundan f′(${_n(x0)}) = $n·${_p(u)}'
              '${n - 1 == 1 ? '' : _ust(n - 1)}·${_p(icTurev)} = ${_n(yanit)}.',
        );
      }

      return kur(
        _temizOge(
          'zincir$c-$a-${b ~/ 4}',
          const [-2, -1, 1, 2, 3, -3, 4, -4],
          b % 4,
          kur,
        ),
      );
    case 4 || 5:
      // h = f∘g; c = 4: f ikinci, g birinci derece; c = 5: f üçüncü, g ikinci
      // derece.
      final x0 = const [1, 2, 3, -1, -2][(a + b + deneme) % 5];
      if (c == 4) {
        final f = [
          1,
          const [-4, -2, 1, 3, 5][a % 5],
          const [2, -3, 1, 4, -1][a ~/ 5],
        ];
        final g = [
          const [2, 3, -1, -2][b % 4],
          const [-3, -1, 1, 2, 4][b ~/ 4],
        ];
        final gx = _deg(g, x0), gt = g[0];
        final ft = _deg(_turevK(f), gx);
        final yanit = ft * gt;
        return _tam(
          'f(x) = ${_pol(f)} ve g(x) = ${_pol(g)} olmak üzere h(x) = f(g(x)) '
              'olduğuna göre h′(${_n(x0)}) değeri kaçtır?',
          yanit,
          [ft, _deg(_turevK(f), x0) * gt, _deg(f, gx) * gt, ft + gt],
          'h′(x) = f′(g(x))·g′(x) olur. g(${_n(x0)}) = ${_n(gx)} ve g′(x) = '
              '${_n(gt)}; f′(x) = ${_pol(_turevK(f))} olduğundan f′(${_n(gx)}) = '
              '${_n(ft)}. h′(${_n(x0)}) = ${_p(ft)}·${_p(gt)} = ${_n(yanit)}.',
        );
      }
      final ep = const [1, 2, -1, 3, -2][a % 5];
      final be = const [-4, -1, 2, 5, -3][a ~/ 5];
      final ze = const [3, 2, -1, -2][b % 4];
      final u = const [-2, -1, 1, 2, 3][b ~/ 4];
      final f = [ep, 0, be, 0];
      final g = [ze, u - ze * x0];
      final ft = _deg(_turevK(f), u);
      final yanit = ft * ze;
      return _tam(
        'f(x) = ${_pol(f)} ve g(x) = ${_pol(g)} olmak üzere h(x) = f(g(x)) '
            'olduğuna göre h′(${_n(x0)}) değeri kaçtır?',
        yanit,
        [ft, _deg(_turevK(f), x0) * ze, _deg(f, u) * ze, ft + ze],
        'h′(x) = f′(g(x))·g′(x) olur. g(${_n(x0)}) = ${_n(u)} ve g′(x) = '
            '${_n(ze)}; f′(x) = ${_pol(_turevK(f))} olduğundan f′(${_n(u)}) = '
            '${_n(ft)}. h′(${_n(x0)}) = ${_p(ft)}·${_p(ze)} = ${_n(yanit)}.',
      );
    case 6 || 7:
      // Değerlerle bileşke türevi: (f∘g)′(k) = f′(g(k))·g′(k).
      final k = 1 + a % 4;
      final m = _uygun(
        _sifirsizAralik(-8, 10),
        a ~/ 4 + (c == 7 ? 7 : 0),
        (x) => x != k,
      );
      // g′(k) = ±1 olmasın: iç türevi unutan da doğru yanıtı bulurdu.
      final s = b < 10 ? b - 11 : b - 8;
      final t = _sifirsiz((a + 3 * b + 5 * deneme) % 12, 6);
      // Kökte süs olarak verilen dış fonksiyon türevi; yanlış noktada türev
      // alan öğrencinin kullanacağı değer.
      final yaniltici = s == -1 ? t + 2 : t + s + 1;
      final (dis, ici) = c == 6 ? ('f', 'g') : ('g', 'f');
      final yanit = t * s;
      return _tam(
        'Türevlenebilir f ve g fonksiyonları için $ici(${_n(k)}) = ${_n(m)}, '
            '$ici′(${_n(k)}) = ${_n(s)}, $dis′(${_n(k)}) = ${_n(yaniltici)} ve '
            '$dis′(${_n(m)}) = ${_n(t)} veriliyor. Buna göre '
            '($dis∘$ici)′(${_n(k)}) değeri kaçtır?',
        yanit,
        [yaniltici * s, t, t + s, yaniltici * t],
        'Zincir kuralına göre ($dis∘$ici)′(${_n(k)}) = '
            '$dis′($ici(${_n(k)}))·$ici′(${_n(k)}) = $dis′(${_n(m)})·'
            '$ici′(${_n(k)}) = ${_p(t)}·${_p(s)} = ${_n(yanit)}.',
      );
    case 8:
      // √(αx + β); αx₀ + β = s².
      // İç fonksiyonun katsayısı 1 olmaz: iç türevi unutan da doğru yanıtı
      // bulurdu (√x biçiminde bileşke de kalmazdı).
      final al = const [2, 4, 6, -2, 3, 7, -4, 8, 5, -6][a % 10];
      final x0 = const [1, 2, -1][a ~/ 10];
      AdvancedItem kur(int s) {
        final be = s * s - al * x0;
        final yanit = _R(al, 2 * s);
        return _ras(
          'f(x) = √(${_pol([al, be])}) olduğuna göre f′(${_n(x0)}) değeri '
              'kaçtır?',
          yanit,
          [_R(1, 2 * s), _R(al, s), _R(al * s, 2), _R(al, 2 * s * s)],
          'f(x) = (${_pol([al, be])})^(1/2) olduğundan f′(x) = '
              '${_n(al)}/(2√(${_pol([al, be])})) olur. x = ${_n(x0)} için kök '
              'içi ${s * s} ve kökü $s olduğundan f′(${_n(x0)}) = '
              '${_n(al)}/(2·$s) = $yanit.',
        );
      }

      return kur(
        _temizOge('zincir8-$a', [for (var x = 1; x <= 30; x++) x], b, kur),
      );
    default:
      // √(x² + q); x₀² + q = s².
      final x0 = _sifirsiz(a, 12);
      final s = x0.abs() + 1 + b;
      final q = s * s - x0 * x0;
      final yanit = _R(x0, s);
      return _ras(
        'f(x) = √(${_pol([1, 0, q])}) olduğuna göre f′(${_n(x0)}) değeri '
            'kaçtır?',
        yanit,
        [_R(2 * x0, s), _R(x0, 2 * s), _R(1, 2 * s), _R(x0, s * s)],
        'f′(x) = 2x/(2√(${_pol([1, 0, q])})) = x/√(${_pol([1, 0, q])}) olur. '
            'x = ${_n(x0)} için kök içi ${s * s} ve kökü $s olduğundan '
            'f′(${_n(x0)}) = ${_esit('${_n(x0)}/$s', '$yanit')}.',
      );
  }
}

// ---------------------------------------------------------------------------
// 15 · Konum fonksiyonundan hız ve ivme
// ---------------------------------------------------------------------------

const _konumGiris =
    'Doğrusal bir yolda hareket eden bir cismin t saniyedeki konumu metre '
    'cinsinden';

/// Hızın sıfır olduğu anlar t₁, t₁ + fark ve |a₃|. fark = 2t₁ iken x(t₂)
/// sabit terime, a(t₁) t² katsayısına eşit çıkardı; bu üçlüler atlanır.
final List<(int, int, int)> _konumUclu = [
  for (final m in const [1, 2])
    for (final fark in const [2, 4, 6, 8])
      for (var t1 = 1; t1 <= 5; t1++)
        if (fark != 2 * t1) (t1, fark, m),
].take(25).toList();

AdvancedItem _konumHiz(int a, int b, int c, int deneme) {
  final sira = hedefSira(_vaka(a, b, c));
  if (c <= 1) {
    final a3 = 1 + a % 2;
    final a2 = const [-6, -4, -3, -1, 2, 3][a ~/ 2 % 6];
    final a1 = _sifirsiz(b, 10);
    final a0 = 2 + (a + b) % 9;
    final x = [a3, a2, a1, a0];
    final t0 = 1 + (a ~/ 12 + b + deneme) % 5;
    final v = _turevK(x), ivme = _turevK(v);
    if (c == 0) {
      final yanit = _deg(v, t0);
      final eski = _tam(
        '$_konumGiris x(t) = ${_pol(x, 't')} bağıntısıyla veriliyor. Cismin '
            't = $t0 s anındaki hızı kaç m/s olur?',
        yanit,
        [
          _deg(x, t0),
          _deg(ivme, t0),
          _deg([a3, a2, a1], t0),
          _deg(v, t0 + 1),
        ],
        'Hız konumun türevidir: v(t) = x′(t) = ${_pol(v, 't')}. v($t0) = '
            '${_yerine(v, t0)} = ${_n(yanit)} m/s.',
        birim: 'm/s',
      );
      // Konumu, ivmeyi ya da türevi hatalı (2 katsayısını ya da sabiti
      // unutarak) alma, bir saniye kaydırma; komşu değerler.
      return _dengele(
        eski,
        yanit,
        _tamAday([
          ...[
            _deg(x, t0),
            _deg(ivme, t0),
            _deg([a3, a2, a1], t0),
          ],
          ...[
            _deg(v, t0 + 1),
            _deg(v, t0 - 1),
            _deg([3 * a3, a2, a1], t0),
          ],
          ...[
            _deg([3 * a3, 2 * a2, 0], t0),
            ..._komsuTam(yanit),
          ],
        ], birim: 'm/s'),
        sira,
      );
    }
    final yanit = _deg(ivme, t0);
    final eski = _tam(
      '$_konumGiris x(t) = ${_pol(x, 't')} bağıntısıyla veriliyor. Cismin '
          't = $t0 s anındaki ivmesi kaç m/s² olur?',
      yanit,
      [_deg(v, t0), 6 * a3 * t0, 3 * a3 * t0 + 2 * a2, _deg(ivme, t0) + a1],
      'v(t) = ${_pol(v, 't')} ve ivme a(t) = v′(t) = ${_pol(ivme, 't')} olur. '
          'a($t0) = ${_yerine(ivme, t0)} = ${_n(yanit)} m/s².',
      birim: 'm/s²',
    );
    // Hızı verme, türevde 2 katsayısını ya da sabit terimi unutma, bir saniye
    // kaydırma; komşu değerler.
    return _dengele(
      eski,
      yanit,
      _tamAday([
        ...[_deg(v, t0), 6 * a3 * t0, 3 * a3 * t0 + 2 * a2, yanit + a1],
        ...[6 * a3 * t0 + a2, _deg(ivme, t0 + 1), _deg(ivme, t0 - 1)],
        ..._komsuTam(yanit),
      ], birim: 'm/s²'),
      sira,
    );
  }
  if (c == 8) {
    // x(t) = −p·t² + q·t + r: en uzak konum (hızın sıfır olduğu an).
    final p = 1 + a % 5;
    final ts = 1 + a ~/ 5 + (b % 4);
    final r = 2 + b + 20 * (deneme % 4);
    final q = 2 * p * ts;
    final x = [-p, q, r];
    final yanit = _deg(x, ts);
    final eski = _tam(
      '$_konumGiris x(t) = ${_pol(x, 't')} bağıntısıyla veriliyor. Cismin '
          'hızının sıfır olduğu anda konumu kaç metredir?',
      yanit,
      [ts, _deg(x, ts + 1), q * ts + r, _deg(x, 2 * ts)],
      'v(t) = ${_pol([-2 * p, q], 't')} = 0 eşitliğinden t = $ts s bulunur. '
          'x($ts) = ${_yerine(x, ts)} = $yanit m.',
      birim: 'm',
      pozitif: true,
    );
    // Anı konum sanma, bir saniye kaydırma, kare terimi unutma ya da işaretini
    // çevirme, başlangıç konumunu verme, hızı sıfır yapan anı t = ts/2 bulma.
    return _dengele(
      eski,
      yanit,
      _tamAday(
        [
          ...[ts, _deg(x, ts + 1), q * ts + r, r, 3 * p * ts * ts + r],
          if (_bol(3 * p * ts * ts, 4) != null) 3 * p * ts * ts ~/ 4 + r,
          ..._komsuTam(yanit),
        ],
        birim: 'm',
        pozitif: true,
      ),
      sira,
    );
  }
  // Hızı t₁ ve t₂ anlarında sıfır olan hareket:
  // x(t) = a₃t³ − (3a₃/2)(t₁ + t₂)t² + 3a₃t₁t₂t + x₀, t₁ + t₂ çift.
  // a → (t₁, t₂ − t₁, |a₃|), b → (a₃ işareti, x₀); hepsi farklıdır.
  final (t1, fark, buyukluk) = _konumUclu[a];
  final t2 = t1 + fark;
  final a3 = buyukluk * (b < 10 ? 1 : -1);
  final x0 = 3 + b % 10 + 10 * (deneme % 3);
  final x = [a3, -3 * a3 * (t1 + t2) ~/ 2, 3 * a3 * t1 * t2, x0];
  final v = _turevK(x), ivme = _turevK(v);
  final pol = _pol(x, 't');
  final vYaz = 'v(t) = ${_pol(v, 't')} = ${_n(3 * a3)}·(t − $t1)·(t − $t2)';
  switch (c) {
    case 2 || 3:
      final ilk = c == 2;
      final yanit = ilk ? t1 : t2;
      final eski = _tam(
        '$_konumGiris x(t) = $pol bağıntısıyla veriliyor. Cismin hızı '
            'kaçıncı saniyede ${ilk ? 'ilk' : 'ikinci'} kez sıfır olur?',
        yanit,
        [ilk ? t2 : t1, t1 + t2, (t1 + t2) ~/ 2, t1 * t2],
        '$vYaz olur. Hız t = $t1 s ve t = $t2 s anlarında sıfırdır; '
            'hız ${ilk ? 'ilk' : 'ikinci'} kez $yanit. saniyede sıfır olur.',
        pozitif: true,
      );
      // Öteki kökü, köklerin toplamını, ortalamasını, çarpımını ya da farkını
      // verme; komşu değerler.
      return _dengele(
        eski,
        yanit,
        _tamAday([
          ...[ilk ? t2 : t1, t1 + t2, (t1 + t2) ~/ 2, t1 * t2, t2 - t1],
          ..._komsuTam(yanit),
        ], pozitif: true),
        sira,
      );
    case 4 || 5:
      final ti = c == 4 ? t1 : t2;
      final yanit = _deg(x, ti);
      final eski = _tam(
        '$_konumGiris x(t) = $pol bağıntısıyla veriliyor. Cismin hızının '
            '${c == 4 ? 'ilk' : 'ikinci'} kez sıfır olduğu anda konumu kaç '
            'metredir?',
        yanit,
        [_deg(x, c == 4 ? t2 : t1), x0, _deg(v, ti) + x0, _deg(x, ti + 1)],
        '$vYaz olur; hız t = $t1 s ve t = $t2 s anlarında sıfırdır. '
            'x($ti) = ${_yerine(x, ti)} = ${_n(yanit)} m.',
        birim: 'm',
      );
      // Öteki anı, başlangıç konumunu ya da yer değiştirmeyi verme, bir saniye
      // kaydırma; komşu değerler.
      return _dengele(
        eski,
        yanit,
        _tamAday([
          ...[_deg(x, c == 4 ? t2 : t1), x0, _deg(x, ti + 1)],
          ...[_deg(x, ti - 1), yanit - x0, ..._komsuTam(yanit)],
        ], birim: 'm'),
        sira,
      );
    case 6:
      final ts = (t1 + t2) ~/ 2;
      final yanit = _deg(v, ts);
      final eski = _tam(
        '$_konumGiris x(t) = $pol bağıntısıyla veriliyor. Cismin ivmesinin '
            'sıfır olduğu andaki hızı kaç m/s olur?',
        yanit,
        [-yanit, _deg(x, ts), _deg(v, ts + 1), ts],
        'a(t) = ${_pol(ivme, 't')} = 0 eşitliğinden t = $ts s olur. '
            'v(t) = ${_pol(v, 't')} olduğundan v($ts) = ${_yerine(v, ts)} = '
            '${_n(yanit)} m/s.',
        birim: 'm/s',
      );
      // İşaret hatası, konumu verme, bir saniye kaydırma, anı hız sanma,
      // başlangıç hızı, ivmenin sıfır olduğu anı hızın sıfır olduğu an sanma.
      return _dengele(
        eski,
        yanit,
        _tamAday([
          ...[-yanit, _deg(x, ts), _deg(v, ts + 1), ts, _deg(v, ts - 1)],
          ...[_deg(v, 0), 0, ..._komsuTam(yanit)],
        ], birim: 'm/s'),
        sira,
      );
    case 7:
      // t = 0 ile t = T arasında alınan yol; yön t₁ anında değişir.
      final tSon = t1 + fark ~/ 2;
      final x0d = _deg(x, 0), x1 = _deg(x, t1), xs = _deg(x, tSon);
      final yol = (x1 - x0d).abs() + (xs - x1).abs();
      final eski = _tam(
        '$_konumGiris x(t) = $pol bağıntısıyla veriliyor. Cismin t = 0 ile '
            't = $tSon s arasında aldığı toplam yol kaç metredir?',
        yol,
        [(xs - x0d).abs(), (x1 - x0d).abs(), (xs - x1).abs(), x1 + xs],
        '$vYaz olduğundan cisim t = $t1 s anında yön değiştirir. x(0) = '
            '${_n(x0d)}, x($t1) = ${_n(x1)}, x($tSon) = ${_n(xs)} olur. Yol '
            '|${_n(x1)} − ${_p(x0d)}| + |${_n(xs)} − ${_p(x1)}| = $yol m.',
        birim: 'm',
        pozitif: true,
      );
      // Yer değiştirmeyi ya da tek parçayı yol sanma, konumları toplama, iki
      // parçayı da başlangıçtan ölçme; komşu değerler.
      return _dengele(
        eski,
        yol,
        _tamAday(
          [
            ...[(xs - x0d).abs(), (x1 - x0d).abs(), (xs - x1).abs(), x1 + xs],
            ...[(x1 - x0d).abs() + (xs - x0d).abs(), 2 * (x1 - x0d).abs()],
            ..._komsuTam(yol),
          ],
          birim: 'm',
          pozitif: true,
        ),
        sira,
      );
    default:
      final yanit = _deg(ivme, t1);
      final eski = _tam(
        '$_konumGiris x(t) = $pol bağıntısıyla veriliyor. Cismin hızının '
            'ilk kez sıfır olduğu andaki ivmesi kaç m/s² olur?',
        yanit,
        [-yanit, _deg(ivme, t2), _deg(ivme, 0), 0],
        '$vYaz olduğundan hız ilk kez t = $t1 s anında sıfırdır. a(t) = '
            '${_pol(ivme, 't')} olduğundan a($t1) = ${_yerine(ivme, t1)} = '
            '${_n(yanit)} m/s².',
        birim: 'm/s²',
      );
      // İşaret hatası, başlangıçtaki ivme, ivme yerine hız (0), bir saniye
      // kaydırma, türevde sabit terimi unutma; komşu değerler.
      return _dengele(
        eski,
        yanit,
        _tamAday([
          ...[-yanit, _deg(ivme, 0), 0, _deg(ivme, t1 + 1)],
          ...[_deg(ivme, t1 - 1), 6 * a3 * t1, ..._komsuTam(yanit)],
        ], birim: 'm/s²'),
        sira,
      );
  }
}

// ---------------------------------------------------------------------------
// 16 · Türevle en büyük ve en küçük değer problemleri
// ---------------------------------------------------------------------------

/// Çit problemleri: (tel uzunluğu L, bölme sayısı k, duvar var mı).
final List<(int, int, bool)> _citVeri = () {
  final l = <(int, int, bool)>[];
  for (var uzun = 40; uzun <= 1000; uzun += 2) {
    for (var k = 1; k <= 4; k++) {
      for (final duvar in const [true, false]) {
        // Duvarlı: 2(k + 1) | L; duvarsız: 4 | L ve 2(k + 1) | L.
        final ok = duvar
            ? uzun % (2 * (k + 1)) == 0
            : uzun % 4 == 0 && uzun % (2 * (k + 1)) == 0;
        if (ok) l.add((uzun, k, duvar));
      }
    }
  }
  // Ardışık sıralar farklı k ve duvar durumlarına dağılsın.
  return [for (var i = 0; i < l.length; i++) l[i * 233 % l.length]];
}();

/// Bütçeli çit: (a, b, duvar, B); a ve b telin metre fiyatıdır (TL).
final List<(int, int, bool, int)> _butceCit = () {
  const fiyat = [10, 15, 20, 25, 30, 40, 50, 60];
  final l = <(int, int, bool, int)>[];
  for (final a in fiyat) {
    for (final b in fiyat) {
      if (a == b) continue;
      for (final duvar in const [false, true]) {
        final x = 4 * a, y = duvar ? 2 * b : 4 * b;
        final ek = x * y ~/ x.gcd(y);
        for (var t = 1; t <= 5; t++) {
          if (ek * t > 40000) break;
          l.add((a, b, duvar, ek * t));
        }
      }
    }
  }
  return [for (var i = 0; i < l.length; i++) l[i * 101 % l.length]];
}();

/// Kenarlardan biri eksenlerde, karşı köşesi x/p + y/q = 1 doğrusunda olan
/// dikdörtgenler için (p, q) çiftleri (p, q çift).
final List<(int, int)> _dogruAlti = [
  for (var p = 2; p <= 70; p += 2)
    for (var q = 2; q <= 70; q += 2)
      if (p != q) (p, q),
];

/// Sabit toplam ax + by = S ile en büyük çarpım: (a, b, S); a ile b
/// aralarında asaldır.
final List<(int, int, int)> _toplamSabit = () {
  final l = <(int, int, int)>[];
  for (var a = 1; a <= 10; a++) {
    for (var b = a; b <= 10; b++) {
      if (a.gcd(b) != 1) continue;
      for (var s = 2 * a * b; s <= 480; s += 2 * a * b) {
        if (a == 1 && b == 1 && s > 120) continue;
        l.add((a, b, s));
      }
    }
  }
  return [for (var i = 0; i < l.length; i++) l[i * 211 % l.length]];
}();

/// Dikdörtgen karton kutular: (a, b, x, hacim); x tam sayıdır.
const _kutuDikdortgen = [
  (9, 24, 2, 200),
  (10, 16, 2, 144),
  (13, 48, 3, 882),
  (14, 30, 3, 576),
  (15, 24, 3, 486),
  (16, 21, 3, 450),
  (18, 48, 4, 1600),
  (20, 32, 4, 1152),
  (24, 45, 5, 2450),
  (25, 40, 5, 2250),
  (28, 60, 6, 4608),
  (30, 48, 6, 3888),
  (32, 42, 6, 3600),
  (33, 40, 6, 3528),
  (35, 56, 7, 6174),
];

/// Karışık liste: (tür, u, v, w). Tür 0–6 kutu ve parabol altı dikdörtgen,
/// 7 sabit çarpım (u·x + v·y en küçük, xy = w), 8 sabit toplamla x²y ya da
/// xy² en büyük (u = 1 ise x²y).
final List<(int, int, int, int)> _karmaOpt = () {
  final l = <(int, int, int, int)>[];
  for (var m = 1; m <= 12; m++) {
    l
      ..add((0, m, 0, 0))
      ..add((1, m, 0, 0));
  }
  for (var i = 0; i < _kutuDikdortgen.length; i++) {
    l
      ..add((2, i, 0, 0))
      ..add((3, i, 0, 0));
  }
  for (var m = 1; m <= 15; m++) {
    l.add((4, m, 0, 0));
  }
  for (var m = 2; m <= 21; m++) {
    l.add((5, m, 0, 0));
  }
  for (var m = 1; m <= 10; m++) {
    l.add((6, m, 0, 0));
  }
  for (var a = 1; a <= 6; a++) {
    for (var b = a; b <= 9; b++) {
      if (a.gcd(b) != 1) continue;
      for (var p = 2; p <= 2000; p++) {
        if (_kokAyir(a * b * p).$2 == 1) l.add((7, a, b, p));
      }
    }
  }
  for (var s = 6; s <= 60; s += 3) {
    l
      ..add((8, 1, s, 0))
      ..add((8, 2, s, 0));
  }
  // 678 öğe; 7 ile 678 aralarında asaldır.
  return [for (var i = 0; i < l.length; i++) l[i * 7 % l.length]];
}();

/// Kapalı aralıkta mutlak uç değer: (a, r1, r2, d, p, q);
/// f′(x) = 3a(x − r1)(x − r2).
final List<(int, int, int, int, int, int)> _aralikUc = () {
  final l = <(int, int, int, int, int, int)>[];
  for (final a in const [1, -1, 2, -2]) {
    for (var r1 = -3; r1 <= 3; r1++) {
      for (var fark = 2; fark <= 4; fark += 2) {
        final r2 = r1 + fark;
        for (final d in const [-5, 1, 6, -2, 3]) {
          for (final (dp, dq) in const [
            (1, 1),
            (2, 1),
            (1, 2),
            (0, 2),
            (2, 0),
            (3, 1),
          ]) {
            l.add((a, r1, r2, d, r1 - dp, r2 + dq));
          }
        }
      }
    }
  }
  return [for (var i = 0; i < l.length; i++) l[i * 151 % l.length]];
}();

AdvancedItem _optimizasyon(int a, int b, int c) {
  final adet = switch (c) {
    0 || 1 => _citVeri.length,
    2 || 3 => _butceCit.length,
    4 => _dogruAlti.length,
    5 => _toplamSabit.length,
    6 => _karmaOpt.length,
    _ => _aralikUc.length,
  };
  final t = _temizSec('opt$c', adet, (t) => _optimizasyonHam(t, c), a + 25 * b);
  final eski = _optimizasyonHam(t, c);
  final (yanit, aday) = _optimizasyonAday(t, c);
  final birim = eski.correct.contains(' ')
      ? eski.correct.substring(eski.correct.indexOf(' ') + 1)
      : '';
  // Yanıt eski soruyla aynı hesaplanmadıysa eski çeldiriciler kalır.
  if (birimli(_n(yanit), birim) != eski.correct) return eski;
  return _dengele(
    eski,
    yanit,
    _tamAday(aday, birim: birim, pozitif: c <= 6),
    hedefSira(_vaka(a, b, c)),
  );
}

/// Tam bölünüyorsa bölüm, değilse null (çeldirici adayı atılır).
int? _bol(int a, int b) => b != 0 && a % b == 0 ? a ~/ b : null;

/// [_optimizasyonHam] sorusunun yanıtı ve çeldirici adayları (öncelik
/// sırasıyla, anahtarın iki yanından): eski adaylar, ardından en uygun
/// noktayı yanlış bulma, bir kenarı ya da bölmeyi fazla veya eksik sayma,
/// yarıya bölme, işlemi karıştırma gibi hatalar; en sonda komşu değerler.
(int, List<int?>) _optimizasyonAday(int j, int c) {
  if (c <= 1) {
    final (uzun, k, duvar) = _citVeri[j];
    final x = uzun ~/ (2 * (k + 1));
    final y = duvar ? uzun ~/ 2 : uzun ~/ 4;
    final alan = x * y, l2 = uzun * uzun;
    if (c == 0) {
      // Bir bölme fazla sayılırsa x = L/(2(k + 2)) olur.
      final fazla = duvar ? _bol(l2, 4 * (k + 2)) : _bol(l2, 8 * (k + 2));
      return (
        alan,
        [
          2 * alan,
          _bol(alan, 2),
          ...(k == 1
              ? (duvar ? [l2 ~/ 16, x * (uzun - x)] : [l2 ~/ 8, l2 ~/ 4])
              : [
                  duvar ? l2 ~/ 8 : l2 ~/ 16,
                  duvar ? x * (uzun - k * x) : x * (uzun - (k + 1) * x),
                  (uzun ~/ 4) * (uzun ~/ 4),
                ]),
          fazla,
          if (duvar && k == 1) _bol(l2, 9),
          ..._komsuTam(alan),
        ],
      );
    }
    return (
      x,
      [
        uzun ~/ 4,
        _bol(uzun, 2 * (k + 2)),
        y,
        _bol(x, 2),
        2 * x,
        x + k,
        if (!duvar) _bol(uzun, 8),
        ..._komsuTam(x),
      ],
    );
  }
  if (c <= 3) {
    final (fa, fb, duvar, butce) = _butceCit[j];
    final x = butce ~/ (4 * fa);
    final y = duvar ? butce ~/ (2 * fb) : butce ~/ (4 * fb);
    final alan = x * y;
    if (c == 2) {
      final esit = butce ~/ (2 * (fa + fb));
      return (
        alan,
        [
          duvar
              ? butce * butce ~/ (16 * fa * fb)
              : butce * butce ~/ (8 * fa * fb),
          _bol(alan, 2),
          2 * alan,
          esit * esit,
          x * x,
          y * y,
          ..._komsuTam(alan),
        ],
      );
    }
    final tel = duvar ? 2 * x + y : 2 * x + 2 * y;
    return (
      tel,
      [
        x + y,
        2 * tel,
        duvar ? 2 * x + 2 * y : 2 * x + y,
        _bol(tel, 2),
        4 * x,
        2 * y,
        x + 2 * y,
        ..._komsuTam(tel),
      ],
    );
  }
  if (c == 4) {
    final (p, q) = _dogruAlti[j * 11 % _dogruAlti.length];
    final pq = p * q;
    return (
      pq ~/ 4,
      [
        pq ~/ 2,
        pq ~/ 8,
        pq,
        _bol(3 * pq, 16),
        (p + q) * (p + q) ~/ 16,
        _bol(2 * pq, 9),
        _bol(pq, 6),
        ..._komsuTam(pq ~/ 4),
      ],
    );
  }
  if (c == 5) {
    final (ka, kb, s) = _toplamSabit[j];
    final x = s ~/ (2 * ka), y = s ~/ (2 * kb);
    final yanit = x * y;
    return (
      yanit,
      [
        s * s ~/ 4,
        yanit ~/ 2,
        (s ~/ (ka + kb)) * (s ~/ (ka + kb)),
        _bol(yanit, 4),
        2 * yanit,
        x + y,
        ..._komsuTam(yanit),
      ],
    );
  }
  if (c == 6) {
    final (tur, u, v, w) = _karmaOpt[j];
    switch (tur) {
      case 0:
        return (u, [3 * u, _bol(u, 2), _bol(3 * u, 2), 2 * u, ..._komsuTam(u)]);
      case 1:
        final s = 6 * u, hacim = 16 * u * u * u;
        return (
          hacim,
          [
            u * (s - 4 * u) * (s - 4 * u),
            2 * hacim,
            hacim ~/ 2,
            u * s * s,
            _bol(s * s * s, 16),
            25 * u * u * u,
            ..._komsuTam(hacim),
          ],
        );
      case 2:
        final (ka, kb, x, _) = _kutuDikdortgen[u];
        return (
          x,
          [x + 1, ka ~/ 6, kb ~/ 6, 2 * x, x - 1, _bol(ka, 4), ..._komsuTam(x)],
        );
      case 3:
        final (ka, kb, x, hacim) = _kutuDikdortgen[u];
        return (
          hacim,
          [
            (x + 1) * (ka - 2 * x - 2) * (kb - 2 * x - 2),
            x * ka * kb,
            (x - 1) * (ka - 2 * x + 2) * (kb - 2 * x + 2),
            2 * hacim,
            hacim ~/ 2,
            ..._komsuTam(hacim),
          ],
        );
      case 4:
        final yuzey = 12 * u * u;
        return (
          yuzey,
          [
            ...[6 * u * u, 16 * u * u, 10 * u * u, 2 * yuzey, 8 * u * u],
            ...[17 * u * u, ..._komsuTam(yuzey)],
          ],
        );
      case 5:
        final yuzey = 6 * u * u;
        return (
          yuzey,
          [
            ...[5 * u * u, 8 * u * u, 4 * u * u, 2 * yuzey, 3 * u * u],
            ...[7 * u * u, ..._komsuTam(yuzey)],
          ],
        );
      case 6:
        final h = 3 * u * u, alan = 4 * u * u * u;
        return (
          alan,
          [
            ...[2 * alan, u * h, alan + h, 2 * u * u * u, 2 * u * h],
            ..._komsuTam(alan),
          ],
        );
      case 7:
        final (ka, kb, p) = (u, v, w);
        final yanit = 2 * _kokAyir(ka * kb * p).$1;
        return (
          yanit,
          [
            ka * p + kb,
            yanit ~/ 2,
            if (_kokAyir(p).$2 == 1) (ka + kb) * _kokAyir(p).$1,
            2 * yanit,
            ..._komsuTam(yanit),
          ],
        );
      default:
        final s = v, buyukX = u == 1;
        final x = buyukX ? 2 * s ~/ 3 : s ~/ 3, y = s - x;
        final yanit = buyukX ? x * x * y : x * y * y;
        return (
          yanit,
          [
            (s ~/ 2) * (s ~/ 2) * (s - s ~/ 2),
            2 * yanit,
            buyukX ? x * y * y : x * x * y,
            yanit ~/ 2,
            buyukX ? x * x * x : y * y * y,
            ..._komsuTam(yanit),
          ],
        );
    }
  }
  // c = 7, 8, 9: kapalı aralıkta en büyük ve en küçük değer. Kritik noktayı
  // işaret hatasıyla −r bulma, M ile m'yi karıştırma da çeldiricidir.
  final (ka, r1, r2, d, p, q) =
      _aralikUc[(j + 500 * (c - 7)) % _aralikUc.length];
  final f = [ka, -3 * ka * (r1 + r2) ~/ 2, 3 * ka * r1 * r2, d];
  final degerler = [
    for (final x in {p, q, r1, r2}) _deg(f, x),
  ];
  final maks = degerler.reduce((x, y) => x > y ? x : y);
  final min = degerler.reduce((x, y) => x < y ? x : y);
  final yerelMaks = _deg(f, ka > 0 ? r1 : r2);
  final yerelMin = _deg(f, ka > 0 ? r2 : r1);
  final fp = _deg(f, p), fq = _deg(f, q);
  // −r aralıkta kalıyorsa öğrenci onu da kritik nokta sanıp değerlendirir.
  int? hatali(int r) => -r >= p && -r <= q && -r != r ? _deg(f, -r) : null;
  final e1 = hatali(r1), e2 = hatali(r2);
  return switch (c) {
    7 => (
      maks,
      [
        ...[yerelMaks, fp, fq, min, e1, e2, maks - min, maks + min],
        ..._komsuTam(maks),
      ],
    ),
    8 => (
      min,
      [
        ...[yerelMin, fp, fq, maks, e1, e2, min - maks, maks + min],
        ..._komsuTam(min),
      ],
    ),
    _ => (
      maks + min,
      [
        ...[yerelMaks + yerelMin, fp + fq, maks - min, maks, min],
        ...[if (e1 != null && e2 != null) e1 + e2, yerelMaks + min],
        maks + yerelMin,
        ..._komsuTam(maks + min),
      ],
    ),
  };
}

/// (n/d)·x yazımı: `_xKat(2, 1)` → `2x`, `_xKat(1, 1)` → `x`,
/// `_xKat(23, 2)` → `(23/2)x`.
String _xKat(int n, int d) {
  final r = _R(n, d);
  if (!r.tam) return '($r)x';
  return r.p == 1 ? 'x' : '${r.p}x';
}

/// j: c'ye göre veri listesindeki sıra.
AdvancedItem _optimizasyonHam(int j, int c) {
  if (c <= 1) {
    final (uzun, k, duvar) = _citVeri[j];
    final x = uzun ~/ (2 * (k + 1));
    final y = duvar ? uzun ~/ 2 : uzun ~/ 4;
    final alan = x * y;
    final bolme = k == 1
        ? ''
        : ' ve alanı ${duvar ? 'duvara dik' : 'bir kenarına paralel'} '
              '${k == 2 ? 'bir' : k - 1} tel çitle $k eş bölmeye ayıracaktır';
    final giris =
        'Bir çiftçi $uzun m uzunluğundaki tel ile '
        '${duvar ? 'bir kenarı düz bir duvar olan ' : ''}dikdörtgen biçimli bir '
        'alanı ${k == 1 ? 'çevirecektir' : 'çevirecek$bolme'}. '
        '${duvar ? 'Duvar tarafına tel çekilmeyecektir. ' : ''}';
    final adlar = duvar
        ? 'Duvara dik kenarların her biri x m, duvara paralel kenar y m olsun'
        : (k == 1
              ? 'Karşılıklı iki kenarın her biri x m, öteki iki kenarın her '
                    'biri y m olsun'
              : 'Bölme çitlerine paralel kenarların her biri x m, öteki '
                    'kenarlar y m olsun');
    final kur = duvar
        ? '${k + 1}x + y = $uzun ve A = x·y = x·($uzun − ${k + 1}x)'
        : '${k + 1}x + 2y = $uzun ve A = x·y = x·($uzun − ${k + 1}x)/2';
    final turev = duvar
        ? 'A′(x) = $uzun − ${2 * (k + 1)}x = 0'
        : 'A′(x) = ($uzun − ${2 * (k + 1)}x)/2 = 0';
    final cozum =
        '$adlar: $kur olur. $turev eşitliğinden x = $x m, y = $y m bulunur.';
    if (c == 0) {
      return _tam(
        '$girisÇevrilebilecek alan en çok kaç m² olur?',
        alan,
        k == 1
            // Bölmesiz: duvarı unutma ya da duvar varsayma.
            ? (duvar
                  ? [uzun * uzun ~/ 16, x * (uzun - x), 2 * alan]
                  : [uzun * uzun ~/ 8, uzun * uzun ~/ 4])
            : [
                duvar ? uzun * uzun ~/ 8 : uzun * uzun ~/ 16,
                (uzun ~/ 4) * (uzun ~/ 4),
                duvar ? x * (uzun - k * x) : x * (uzun - (k + 1) * x),
                2 * alan,
              ],
        '$cozum En büyük alan $x·$y = $alan m² olur.',
        birim: 'm²',
        pozitif: true,
      );
    }
    return _tam(
      '$girisÇevrilen alanın en büyük olması için '
      '${duvar ? 'duvara dik her bir kenar' : (k == 1 ? 'dikdörtgenin bir kenarı' : 'bölme çitlerine paralel her bir kenar')} '
      'kaç metre olmalıdır?',
      x,
      [uzun ~/ 4, y, 2 * x, x + k],
      cozum,
      birim: 'm',
      pozitif: true,
    );
  }
  if (c <= 3) {
    // Bütçeli çit: 2a·x + 2b·y = B (duvarsız) ya da 2a·x + b·y = B (duvarlı).
    final (fa, fb, duvar, butce) = _butceCit[j];
    final x = butce ~/ (4 * fa);
    final y = duvar ? butce ~/ (2 * fb) : butce ~/ (4 * fb);
    final alan = x * y;
    final giris = duvar
        ? 'Bir kenarı duvar olan dikdörtgen biçimli bir bahçenin öteki üç '
              'kenarına tel çekilecektir. Duvara dik kenarlar için telin '
              'metresi $fa TL, duvara paralel kenar için $fb TL\'dir.'
        : 'Dikdörtgen biçimli bir bahçenin dört kenarına tel çekilecektir. '
              'Karşılıklı iki kenar için telin metresi $fa TL, diğer iki kenar '
              'için $fb TL\'dir.';
    final kur = duvar
        ? '${2 * fa}x + ${fb}y = $butce'
        : '${2 * fa}x + ${2 * fb}y = $butce';
    final cozum =
        'Fiyatı $fa TL olan kenarlar x m, öteki ${duvar ? 'kenar' : 'kenarlar'} '
        'y m olsun: $kur olur. A = x·y ifadesinde y yerine yazılıp türev '
        'sıfıra eşitlenirse x = $x m ve y = $y m bulunur.';
    if (c == 2) {
      return _tam(
        '$giris Bu iş için $butce TL harcanacağına göre bahçenin alanı en çok '
            'kaç m² olur?',
        alan,
        [
          duvar
              ? butce * butce ~/ (16 * fa * fb)
              : butce * butce ~/ (8 * fa * fb),
          2 * alan,
          (butce ~/ (2 * (fa + fb))) * (butce ~/ (2 * (fa + fb))),
          x * x,
        ],
        '$cozum En büyük alan $x·$y = $alan m² olur.',
        birim: 'm²',
        pozitif: true,
      );
    }
    final tel = duvar ? 2 * x + y : 2 * x + 2 * y;
    return _tam(
      '$giris Bu iş için $butce TL harcanacaktır. Bahçenin alanı en büyük '
          'olduğunda kullanılan telin toplam uzunluğu kaç metre olur?',
      tel,
      [x + y, 2 * tel, duvar ? 2 * x + 2 * y : 2 * x + y, 4 * x],
      '$cozum Kullanılan tel ${duvar ? '2·$x + $y' : '2·$x + 2·$y'} = $tel m '
          'olur.',
      birim: 'm',
      pozitif: true,
    );
  }
  if (c == 4) {
    final (p, q) = _dogruAlti[j * 11 % _dogruAlti.length];
    final g = p.gcd(q);
    final dogru =
        '${_pol([q ~/ g, 0])} + ${_pol([p ~/ g, 0], 'y')} = ${p * q ~/ g}';
    final alan = p * q ~/ 4;
    return _tam(
      'Analitik düzlemin birinci bölgesinde bir köşesi orijinde, iki kenarı '
          'koordinat eksenleri üzerinde ve orijinin karşısındaki köşesi $dogru '
          'doğrusu üzerinde olan dikdörtgenlerin alanı en çok kaç birimkaredir?',
      alan,
      [p * q ~/ 2, p * q, p * q ~/ 8, (p + q) * (p + q) ~/ 16],
      'Doğru x eksenini x = $p, y eksenini y = $q noktasında keser. Köşe '
          '(x, y) için y = $q − ${_xKat(q, p)} olur; A(x) = '
          'x·($q − ${_xKat(q, p)}). A′(x) = $q − ${_xKat(2 * q, p)} = 0 '
          'eşitliğinden x = ${p ~/ 2}, y = '
          '${q ~/ 2} ve en büyük alan ${p ~/ 2}·${q ~/ 2} = $alan bulunur.',
      pozitif: true,
    );
  }
  if (c == 5) {
    final (ka, kb, s) = _toplamSabit[j];
    final x = s ~/ (2 * ka), y = s ~/ (2 * kb);
    final yanit = x * y;
    final kisit = '${_pol([ka, 0])} + ${_pol([kb, 0], 'y')} = $s';
    return _tam(
      'Pozitif x ve y gerçek sayıları için $kisit olduğuna göre x·y '
          'çarpımının en büyük değeri kaçtır?',
      yanit,
      [s * s ~/ 4, (s ~/ (ka + kb)) * (s ~/ (ka + kb)), 2 * yanit, yanit ~/ 2],
      'y = ($s − ${_pol([ka, 0])})/$kb yazılırsa x·y = x·($s − '
          '${_pol([ka, 0])})/$kb olur. Türev ($s − ${_pol([2 * ka, 0])})/$kb = 0 '
          'eşitliğinden x = $x, y = $y bulunur. En büyük çarpım $x·$y = $yanit.',
      pozitif: true,
    );
  }
  if (c == 6) {
    final (tur, u, v, w) = _karmaOpt[j];
    switch (tur) {
      case 0 || 1:
        final s = 6 * u, hacim = 16 * u * u * u;
        final giris =
            'Bir kenarı $s cm olan kare biçimindeki bir kartonun dört '
            'köşesinden eş kareler kesilip kenarlar katlanarak üstü açık bir '
            'kutu yapılacaktır.';
        final cozum =
            'Kesilen karenin kenarı x ise V(x) = x·($s − 2x)² olur. V′(x) = '
            '($s − 2x)·($s − 6x) = 0 ve 0 < x < ${s ~/ 2} koşulundan x = $u '
            'cm bulunur.';
        if (tur == 0) {
          return _tam(
            '$giris Kutunun hacminin en büyük olması için kesilen karelerin '
            'bir kenarı kaç cm olmalıdır?',
            u,
            [s ~/ 4, s ~/ 2, 2 * u, s ~/ 3],
            cozum,
            birim: 'cm',
            pozitif: true,
          );
        }
        return _tam(
          '$giris Kutunun hacmi en çok kaç cm³ olur?',
          hacim,
          [
            u * (s - 4 * u) * (s - 4 * u),
            2 * hacim,
            (s ~/ 3) * (s ~/ 3) * (s ~/ 6),
            u * s * s,
          ],
          '$cozum En büyük hacim $u·${s - 2 * u}² = $hacim cm³ olur.',
          birim: 'cm³',
          pozitif: true,
        );
      case 2 || 3:
        final (ka, kb, x, hacim) = _kutuDikdortgen[u];
        final giris =
            'Kenarları $ka cm ve $kb cm olan dikdörtgen biçimindeki bir '
            'kartonun dört köşesinden eş kareler kesilip kenarlar katlanarak '
            'üstü açık bir kutu yapılacaktır.';
        final cozum =
            'Kesilen karenin kenarı x ise V(x) = x·($ka − 2x)·($kb − 2x) olur. '
            'V′(x) = 12x² − ${4 * (ka + kb)}x + ${ka * kb} = 0 eşitliğinin '
            '0 < x < ${_R(ka, 2)} aralığındaki kökü x = $x cm olur.';
        if (tur == 2) {
          return _tam(
            '$giris Kutunun hacminin en büyük olması için kesilen karelerin '
            'bir kenarı kaç cm olmalıdır?',
            x,
            [x + 1, ka ~/ 6, kb ~/ 6, 2 * x],
            cozum,
            birim: 'cm',
            pozitif: true,
          );
        }
        return _tam(
          '$giris Kutunun hacmi en çok kaç cm³ olur?',
          hacim,
          [
            (x + 1) * (ka - 2 * x - 2) * (kb - 2 * x - 2),
            (x - 1) * (ka - 2 * x + 2) * (kb - 2 * x + 2),
            x * ka * kb,
            2 * hacim,
          ],
          '$cozum En büyük hacim $x·${ka - 2 * x}·${kb - 2 * x} = $hacim cm³ '
              'olur.',
          birim: 'cm³',
          pozitif: true,
        );
      case 4:
        final hacim = 4 * u * u * u, yuzey = 12 * u * u;
        return _tam(
          'Tabanı kare biçiminde, üstü açık ve hacmi $hacim cm³ olan bir kutu '
              'yapılacaktır. Bu kutunun yapımında en az kaç cm² malzeme '
              'kullanılır?',
          yuzey,
          [6 * u * u, 10 * u * u, 16 * u * u, 2 * yuzey],
          'Taban kenarı x, yükseklik h ise x²·h = $hacim ve S = x² + 4xh = '
              'x² + ${4 * hacim}/x olur. S′(x) = 2x − ${4 * hacim}/x² = 0 '
              'eşitliğinden x³ = ${2 * hacim}, x = ${2 * u} cm ve h = $u cm '
              'bulunur. En az yüzey ${4 * u * u} + 4·${2 * u}·$u = $yuzey cm².',
          birim: 'cm²',
          pozitif: true,
        );
      case 5:
        final hacim = u * u * u, yuzey = 6 * u * u;
        return _tam(
          'Tabanı kare biçiminde, kapalı ve hacmi $hacim cm³ olan bir kutu '
              'yapılacaktır. Bu kutunun yapımında en az kaç cm² malzeme '
              'kullanılır?',
          yuzey,
          [5 * u * u, 4 * u * u, 8 * u * u, 2 * yuzey],
          'Taban kenarı x, yükseklik h ise x²·h = $hacim ve S = 2x² + 4xh = '
              '2x² + ${4 * hacim}/x olur. S′(x) = 4x − ${4 * hacim}/x² = 0 '
              'eşitliğinden x³ = $hacim, x = $u cm ve h = $u cm bulunur; kutu '
              'küptür. En az yüzey 6·$u² = $yuzey cm².',
          birim: 'cm²',
          pozitif: true,
        );
      case 6:
        final h = 3 * u * u, alan = 4 * u * u * u;
        return _tam(
          'Bir kenarı x ekseni üzerinde, diğer iki köşesi y = $h − x² '
              'parabolü üzerinde olan ve x ekseninin üst tarafında kalan '
              'dikdörtgenlerin alanı en çok kaç birimkaredir?',
          alan,
          [2 * alan, u * h, 2 * u * u * u, alan + h],
          'Köşeler (−x, $h − x²) ve (x, $h − x²) olsun: A(x) = 2x·($h − x²) = '
              '${2 * h}x − 2x³. A′(x) = ${2 * h} − 6x² = 0 eşitliğinden x = $u '
              'bulunur. En büyük alan 2·$u·${h - u * u} = $alan.',
          pozitif: true,
        );
      case 7:
        final (ka, kb, p) = (u, v, w);
        final yanit = 2 * _kokAyir(ka * kb * p).$1;
        final ifade = '${_pol([ka, 0])} + ${_pol([kb, 0], 'y')}';
        return _tam(
          'Pozitif x ve y gerçek sayıları için x·y = $p olduğuna göre $ifade '
              'toplamının en küçük değeri kaçtır?',
          yanit,
          [
            ka * p + kb,
            if (_kokAyir(p).$2 == 1) (ka + kb) * _kokAyir(p).$1,
            yanit ~/ 2,
            2 * yanit,
          ],
          'y = $p/x yazılırsa toplam ${_pol([ka, 0])} + ${kb * p}/x olur. '
              'Türev $ka − ${kb * p}/x² = 0 eşitliğinden x² = ${_R(kb * p, ka)} '
              'bulunur; en küçük değer 2·√(${ka * kb * p}) = $yanit olur.',
          pozitif: true,
        );
      default:
        // x + y = S, x²·y (u = 1) ya da x·y² (u = 2) en büyük.
        final s = v, buyukX = u == 1;
        final x = buyukX ? 2 * s ~/ 3 : s ~/ 3, y = s - x;
        final yanit =
            x * x * y * (buyukX ? 1 : 0) + x * y * y * (buyukX ? 0 : 1);
        final ifade = buyukX ? 'x²·y' : 'x·y²';
        return _tam(
          'Pozitif x ve y gerçek sayıları için x + y = $s olduğuna göre '
              '$ifade ifadesinin en büyük değeri kaçtır?',
          yanit,
          [
            (s ~/ 2) * (s ~/ 2) * (s - s ~/ 2),
            buyukX ? x * y * y : x * x * y,
            2 * yanit,
            yanit ~/ 2,
          ],
          'y = $s − x yazılırsa ${buyukX ? 'x²·($s − x)' : 'x·($s − x)²'} '
              'ifadesinin türevi ${buyukX ? 'x·(${2 * s} − 3x)' : '($s − x)·($s − 3x)'} '
              'olur. Türevin sıfır olduğu uygun nokta x = $x, y = $y bulunur. En '
              'büyük değer ${buyukX ? '$x²·$y' : '$x·$y²'} = $yanit.',
          pozitif: true,
        );
    }
  }
  // c = 7, 8, 9: kapalı aralıkta en büyük ve en küçük değer.
  final (ka, r1, r2, d, p, q) =
      _aralikUc[(j + 500 * (c - 7)) % _aralikUc.length];
  final f = [ka, -3 * ka * (r1 + r2) ~/ 2, 3 * ka * r1 * r2, d];
  final noktalar = <int>{p, q, r1, r2};
  final degerler = {for (final x in noktalar) x: _deg(f, x)};
  final sirali = noktalar.toList()..sort();
  final maks = degerler.values.reduce((x, y) => x > y ? x : y);
  final min = degerler.values.reduce((x, y) => x < y ? x : y);
  final yerelMaks = _deg(f, ka > 0 ? r1 : r2);
  final yerelMin = _deg(f, ka > 0 ? r2 : r1);
  final liste = [for (final x in sirali) 'f(${_n(x)}) = ${_n(degerler[x]!)}']
      .join(', ');
  final c1 = r1 == 0 ? 'x' : '(${_pol([1, -r1])})';
  final c2 = r2 == 0 ? 'x' : '(${_pol([1, -r2])})';
  final giris =
      'f′(x) = ${_pol(_turevK(f))} = ${_n(3 * ka)}·$c1·$c2 olduğundan kritik '
      'noktalar x = ${_n(r1)} ve x = ${_n(r2)} olur. Aralığın uçlarıyla '
      'birlikte $liste bulunur.';
  final aralik = '[${_n(p)}, ${_n(q)}]';
  switch (c) {
    case 7:
      return _tam(
        'f(x) = ${_pol(f)} fonksiyonunun $aralik aralığındaki en büyük değeri '
            'kaçtır?',
        maks,
        // Uç değer ya bir kritik noktada ya bir uçtadır; ikisinden yanıta
        // eşit olanı çeldirici olamaz.
        [
          for (final v in [yerelMaks, degerler[p]!, degerler[q]!])
            if (v != maks) v,
          min,
        ],
        '$giris En büyük değer ${_n(maks)} olur.',
      );
    case 8:
      return _tam(
        'f(x) = ${_pol(f)} fonksiyonunun $aralik aralığındaki en küçük değeri '
            'kaçtır?',
        min,
        [
          for (final v in [yerelMin, degerler[p]!, degerler[q]!])
            if (v != min) v,
          maks,
        ],
        '$giris En küçük değer ${_n(min)} olur.',
      );
    default:
      return _tam(
        'f(x) = ${_pol(f)} fonksiyonunun $aralik aralığındaki en büyük değeri '
            'M, en küçük değeri m olduğuna göre M + m toplamı kaçtır?',
        maks + min,
        [yerelMaks + yerelMin, degerler[p]! + degerler[q]!, maks - min, maks],
        '$giris M = ${_n(maks)}, m = ${_n(min)}; M + m = ${_n(maks + min)}.',
      );
  }
}

// ---------------------------------------------------------------------------
// 17 · Belirsiz integral ve başlangıç koşulu
// ---------------------------------------------------------------------------

/// Kesirli katsayılı polinom yazımı: `[4/3, −2, 1, 0]` → `(4/3)x³ − 2x² + x`.
String _polR(List<_R> k) {
  final sb = StringBuffer();
  final n = k.length - 1;
  for (var i = 0; i <= n; i++) {
    final c = k[i];
    if (c.sifir) continue;
    final d = n - i;
    final m = _R(c.p.abs(), c.q);
    final kat = m.tam ? (m.p == 1 && d > 0 ? '' : '${m.p}') : '($m)';
    final govde = d == 0 ? '$m' : '$kat${d == 1 ? 'x' : 'x${_ust(d)}'}';
    if (sb.isEmpty) {
      sb.write(c.p < 0 ? '−$govde' : govde);
    } else {
      sb.write(c.p < 0 ? ' − $govde' : ' + $govde');
    }
  }
  return sb.isEmpty ? '0' : sb.toString();
}

_R _degR(List<_R> k, int x) => k.fold(_R(0), (t, c) => t * _R(x) + c);

AdvancedItem _belirsizIntegral(int a, int b, int c, int deneme) {
  // c = 4, 5 (teğet biçimi) c = 0, 1 ile aynı veriyi kullanmasın.
  final teget = c == 4 || c == 5;
  final x0 = (teget ? const [1, -1, 2, 0] : const [0, 1, -1, 2])[b % 4];
  // c = 0 ve 4'te F(x₀) = px₀² + qx₀ iken integral sabiti sıfırdır; sabiti
  // unutan da doğru yanıtı bulurdu. Bu v değerleri atlanır.
  final g0 =
      const [1, 2, 3, -1, -2][a % 5] * x0 * x0 +
      const [-4, -1, 2, 5, 3][a ~/ 5] * x0;
  final v = _uygun(
    teget ? const [4, -1, 6, -3, 2, 5, -2] : const [3, -2, 5, 7, -4, 6, -5],
    b ~/ 4,
    (y) => !(c == 0 || c == 4) || y != g0,
  );
  final fark = const [2, 3, -2, 4, -3, 1, -1][(a + b + deneme) % 7];
  final x1 = x0 + fark;
  if (c <= 2 || c == 4 || c == 5) {
    // F′ polinomu, ilkeli tam katsayılı olacak biçimde ilkelden kurulur.
    final p = const [1, 2, 3, -1, -2][a % 5];
    final q = const [-4, -1, 2, 5, 3][a ~/ 5];
    final r = const [2, -3, 1, 4, -5][(a + 2 * b + deneme) % 5];
    final ilkel = switch (c) {
      0 || 4 => [p, q, 0],
      1 || 5 => [p, q, r, 0],
      _ => [p, 0, q, r, 0],
    };
    final turev = _turevK(ilkel);
    final sabit = v - _deg(ilkel, x0);
    final tam = [...ilkel.sublist(0, ilkel.length - 1), sabit];
    final yanit = _deg(tam, x1);
    final kok = teget
        ? 'y = f(x) eğrisinin her (x, y) noktasındaki teğetinin eğimi '
              '${_pol(turev)} olup eğri (${_n(x0)}, ${_n(v)}) noktasından '
              'geçmektedir. Buna göre f(${_n(x1)}) değeri kaçtır?'
        : 'F′(x) = ${_pol(turev)} ve F(${_n(x0)}) = ${_n(v)} olduğuna göre '
              'F(${_n(x1)}) değeri kaçtır?';
    final ad = teget ? 'f' : 'F';
    return _tam(
      kok,
      yanit,
      [
        _deg(ilkel, x1), // sabiti unutma
        _deg(turev, x1), // türevin değerini yanıt sanma
        // İlkel x₀'da sıfırsa sabit verilen değerin kendisidir; o zaman işaret
        // hataları kullanılır.
        if (_deg(ilkel, x0) == 0) ...[
          v - _deg(ilkel, x1),
          _deg(ilkel, x1) - v,
        ] else ...[
          _deg(ilkel, x1) + v, // sabiti doğrudan verilen değer sanma
          yanit + 2 * _deg(ilkel, x0), // sabitte işaret hatası
        ],
      ],
      '${teget ? 'Teğetin eğimi türevdir: f′(x) = ${_pol(turev)}. ' : ''}'
      '$ad(x) = ∫(${_pol(turev)}) dx = ${_pol(ilkel)} + C olur. '
      '$ad(${_n(x0)}) = ${_n(v)} koşulundan ${_n(_deg(ilkel, x0))} + C = '
      '${_n(v)}, C = ${_n(sabit)} bulunur. $ad(${_n(x1)}) = '
      '${_yerine(tam, x1)} = ${_n(yanit)}.',
    );
  }
  if (c == 3) {
    // F′(x) = (αx + β)²: önce açılır; ilkelin katsayıları kesirli olabilir.
    final al = const [1, 2, 3, -1, -2][a % 5];
    final be = const [1, -2, 3, 2, -1][a ~/ 5];
    final turev = [al * al, 2 * al * be, be * be];
    final ilkel = [_R(al * al, 3), _R(al * be), _R(be * be), _R(0)];
    final sabit = _R(v) - _degR(ilkel, x0);
    final yanit = _degR(ilkel, x1) + sabit;
    return _ras(
      'F′(x) = (${_pol([al, be])})² ve F(${_n(x0)}) = ${_n(v)} olduğuna göre '
          'F(${_n(x1)}) değeri kaçtır?',
      yanit,
      [
        _degR(ilkel, x1),
        _R(_deg(turev, x1)),
        _degR(ilkel, x0).sifir
            ? _R(v) - _degR(ilkel, x1)
            : _degR(ilkel, x1) + _R(v),
        // İç türevi unutma (α = 1 iken bu yol doğrudur; 3'e bölmeyi unutma).
        al == 1
            ? _R(_us(x1 + be, 3) - _us(x0 + be, 3)) + _R(v)
            : _R(_us(al * x1 + be, 3) - _us(al * x0 + be, 3), 3) + _R(v),
      ],
      'Kare açılırsa F′(x) = ${_pol(turev)} olur. F(x) = ${_polR(ilkel)} + C '
          've F(${_n(x0)}) = ${_n(v)} koşulundan C = $sabit bulunur. '
          'F(${_n(x1)}) = $yanit.',
    );
  }
  if (c <= 7) {
    // İkinci türevden fonksiyona: f″(x) = 6px + 2q.
    final p = const [1, 2, -1, 3, -2][a % 5];
    final q = const [-3, 1, 2, -1, 4][a ~/ 5];
    final r = _sifirsiz(b, 10);
    final s = const [2, -3, 5, 1, -4][(a + b + deneme) % 5];
    final t0 = c == 6 ? 0 : 1;
    final ikinci = [6 * p, 2 * q];
    final aa = r - (3 * p * t0 * t0 + 2 * q * t0);
    final bb = s - (p * t0 * t0 * t0 + q * t0 * t0 + aa * t0);
    final f = [p, q, aa, bb];
    final xs = t0 + const [2, 3, -1, -2][(a ~/ 5 + b + deneme) % 4];
    final yanit = _deg(f, xs);
    return _tam(
      'f″(x) = ${_pol(ikinci)}, f′(${_n(t0)}) = ${_n(r)} ve f(${_n(t0)}) = '
          '${_n(s)} olduğuna göre f(${_n(xs)}) değeri kaçtır?',
      yanit,
      [
        _deg([3 * p, 2 * q, aa], xs), // f′ değeri
        _deg(ikinci, xs), // f″ değeri
        _deg([p, q, 0, s], xs), // birinci sabiti unutma
        // t₀ = 0 iken verilen değerler sabitlerin kendisidir.
        t0 == 0
            ? _deg([p, q, aa, 0], xs) // ikinci sabiti unutma
            : _deg([p, q, r, s], xs), // verilen değerleri sabit sanma
      ],
      'f′(x) = ${_pol([3 * p, 2 * q, 0])} + C₁ ve f′(${_n(t0)}) = ${_n(r)} '
          'koşulundan C₁ = ${_n(aa)} olur. f(x) = ${_pol([p, q, aa, 0])} + C₂ ve '
          'f(${_n(t0)}) = ${_n(s)} koşulundan C₂ = ${_n(bb)} bulunur. '
          'f(${_n(xs)}) = ${_yerine(f, xs)} = ${_n(yanit)}.',
    );
  }
  // c = 8, 9: belirsiz integralden integrali alınan fonksiyona ya da
  // katsayılara.
  final p = const [1, 2, -1, 3, -2][a % 5];
  // p + q ve 2p + q sıfır olmaz: a + b + c ile katsayılar toplamı ya da c
  // aynı çıkmasın.
  final q = const [3, -5, 5, 6, -7][a ~/ 5];
  if (c == 8) {
    final r = _sifirsiz(b, 10);
    final ilkel = [p, q, r, 0];
    final f = _turevK(ilkel);
    final xs = const [2, -1, 3, 1, -2][(a + b + deneme) % 5];
    final yanit = _deg(f, xs);
    return _tam(
      '∫ f(x) dx = ${_pol(ilkel)} + C olduğuna göre f(${_n(xs)}) değeri '
          'kaçtır?',
      yanit,
      [
        _deg(ilkel, xs),
        _deg(_turevK(f), xs),
        _deg([p, q, r], xs),
        yanit + r,
      ],
      'Belirsiz integralin türevi integrali alınan fonksiyonu verir: '
          'f(x) = ${_pol(f)}. f(${_n(xs)}) = ${_yerine(f, xs)} = ${_n(yanit)}.',
    );
  }
  AdvancedItem kur(int r) {
    final f = [3 * p, 2 * q, r];
    final yanit = p + q + r;
    return _tam(
      '∫ (${_pol(f)}) dx = ax³ + bx² + cx + C olduğuna göre a + b + c toplamı '
          'kaçtır?',
      yanit,
      [3 * p + 2 * q + r, p + q, 3 * p + q + r, yanit + 1],
      'Kuvvet kuralıyla ∫ (${_pol(f)}) dx = ${_pol([p, q, r, 0])} + C olur. '
          'a = ${_n(p)}, b = ${_n(q)}, c = ${_n(r)} olduğundan a + b + c = '
          '${_n(yanit)}.',
    );
  }

  return kur(_temizOge('belirsiz9-$a', _sifirsizAralik(-15, 15), b, kur));
}

// ---------------------------------------------------------------------------
// 18 · İki eğri arasındaki alan
// ---------------------------------------------------------------------------

/// (k, e): üçüncü dereceden eğri ile doğru arasındaki alan için.
final List<(int, int)> _kupAlan = [
  for (var e = 1; e <= 4; e++)
    for (final k in const [1, -1, 2, -2, 3, -3]) (k, e),
  (4, 1),
];

AdvancedItem _ikiEgriAlan(int a, int b, int c, int deneme) {
  final sira = hedefSira(_vaka(a, b, c));
  if (c <= 5) {
    // a → (α, d); b → (r₁, doğru ya da ikinci parabol).
    final al = const [1, -1, 2, -2, 3][a % 5];
    final d = 1 + a ~/ 5; // 1 … 5
    // t: (r₁, doğrunun eğimi ya da ikinci parabolün baş katsayısı) çifti; b,
    // yanıtı kökte yazılı bir sayıya eşit olmayan çiftlerin b'incisini seçer.
    AdvancedItem kur(int t) {
      final r1 = const [-3, -2, -1, 0, 1][(t + c) % 5];
      final r2 = r1 + d;
      final m = const [2, -1, 3, -2, 4, -3, 5, -4][(t ~/ 5 + c) % 8];
      final n = const [1, -3, 4, 2, -2][(a + t) % 5];
      // İkinci parabolün baş katsayısı ±4 … ±7: farkla sıfırlanmaz.
      final egri2 = c <= 2
          ? [0, m, n]
          : [
              const [4, -4, 5, -5, 6, -6, 7, -7][t ~/ 5],
              const [-1, 2, -3, 1][(a + t) % 4],
              n,
            ];
      final carpim = [al, -al * (r1 + r2), al * r1 * r2];
      final egri1 = [for (var i = 0; i < 3; i++) egri2[i] + carpim[i]];
      final alan = _R(al.abs() * d * d * d, 6);
      final String ikinci;
      if (c <= 2) {
        ikinci = switch (c) {
          0 => 'y = ${_pol([m, n])} doğrusu',
          1 =>
            '${_pol([m, 0])} − y ${n < 0 ? '−' : '+'} ${n.abs()} = 0 doğrusu',
          _ =>
            'A(${_n(r1 - 1)}, ${_n(m * (r1 - 1) + n)}) ve '
                'B(${_n(r2 + 1)}, ${_n(m * (r2 + 1) + n)}) noktalarından geçen '
                'doğru',
        };
      } else {
        ikinci = switch (c) {
          3 => 'y = ${_pol(egri2)} parabolü',
          4 => 'y = ${_pol(egri2)} eğrisi',
          _ => 'y = ${_pol(egri2)} fonksiyonunun grafiği',
        };
      }
      final kup = al.abs() * d * d * d;
      final carpanlar =
          '${_n(al)}·${r1 == 0 ? 'x' : '(${_pol([1, -r1])})'}·(${_pol([1, -r2])})';
      final eski = _ras(
        'y = ${_pol(egri1)} parabolü ile $ikinci arasında kalan kapalı '
            'bölgenin alanı kaç birimkaredir?',
        alan,
        [
          _R(kup, 3),
          _R(kup, 2),
          _R(d * d * d, 6),
          alan * _R(2),
          _R(al.abs() * d * d, 2),
        ],
        '${c == 2 ? 'Doğrunun denklemi y = ${_pol([m, n])} olur. ' : ''}'
            '${c == 1 ? 'Doğru y = ${_pol([m, n])} biçiminde yazılır. ' : ''}'
            'İki eğrinin farkı ${_pol(carpim)} = $carpanlar olduğundan eğriler '
            'x = ${_n(r1)} ve x = ${_n(r2)} noktalarında kesişir. Alan '
            '∫${_alt(r1)}${_ust(r2)} |${_pol(carpim)}| dx = ${al.abs()}·$d³/6 = '
            '$alan birimkaredir.',
        pozitif: true,
      );
      // 1/6 yerine 1/3, 1/2 ya da 1/12 alma; baş katsayıyı unutma; d³ yerine
      // d² yazma; 6'ya bölmeyi unutma. Son dört aday komşu değerlerdir.
      return _dengele(
        eski,
        alan.p / alan.q,
        _rAday([
          alan * _R(2),
          _R(d * d * d, 6),
          alan * _R(3),
          _R(al.abs() * d * d, 6),
          _R(al.abs() * d * d, 2),
          alan * _R(6),
          alan / _R(2),
          _R(d * d * d, 3),
          alan + _R(1),
          alan - _R(1),
          alan * _R(5, 4),
          alan * _R(3, 4),
        ], pozitif: true),
        sira,
      );
    }

    return kur(
      _temizOge('alan$c-$a', [for (var t = 0; t < 40; t++) t], b, kur),
    );
  }
  // c = 6 … 9: üçüncü dereceden eğri ile doğru; kesişimler r − e, r, r + e.
  final (ka, e) = _kupAlan[a];
  final r = const [0, 1, -1, 2][c - 6];
  // Doğru adayları: (eğim, sabit).
  final dogrular = [
    for (final n0 in const [2, -1, 4, -3, 5, -2])
      for (final m0 in const [3, -2, 1, -1, 2, 4, -3]) [m0, n0],
  ];
  AdvancedItem kur(List<int> dogru) {
    final kup = [
      ka,
      -3 * ka * r,
      3 * ka * r * r - ka * e * e + dogru[0],
      -ka * r * r * r + ka * e * e * r + dogru[1],
    ];
    final alan = _R(ka.abs() * e * e * e * e, 2);
    final fark = r == 0
        ? '${_n(ka)}·x·(x² − ${e * e})'
        : '${_n(ka)}·(${_pol([1, -r])})·((${_pol([1, -r])})² − ${e * e})';
    final eski = _ras(
      'y = ${_pol(kup)} eğrisi ile y = ${_pol(dogru)} doğrusu arasında kalan '
          'bölgelerin alanları toplamı kaç birimkaredir?',
      alan,
      [_R(0), alan / _R(2), alan * _R(2), _R(ka.abs() * e * e * e * e, 4)],
      'Eğri ile doğrunun farkı $fark olduğundan kesişim noktaları '
          'x = ${_n(r - e)}, x = ${_n(r)} ve x = ${_n(r + e)} olur. İki bölge '
          'simetriktir; her birinin alanı ${ka.abs()}·$e⁴/4 = ${alan / _R(2)} '
          'olduğundan toplam alan $alan birimkaredir.',
      pozitif: true,
    );
    // Tek bölgeyi alma; ilkelde u⁴/4 ya da e²u²/2 paydasını unutma; baş
    // katsayıyı unutma; parabol formülünü d = 2e ile uygulama; tek bölgede
    // çıkarma yerine toplama. Son dört aday komşu değerlerdir.
    final e4 = e * e * e * e;
    return _dengele(
      eski,
      alan.p / alan.q,
      _rAday([
        alan / _R(2),
        alan * _R(2),
        _R(e4, 2),
        alan * _R(3),
        _R(4 * ka.abs() * e * e * e, 3),
        _R(e4, 4),
        alan * _R(3, 2),
        alan + _R(1),
        alan - _R(1),
        alan * _R(5, 4),
        alan * _R(3, 4),
      ], pozitif: true),
      sira,
    );
  }

  return kur(_temizOge('alan$c-$a', dogrular, b, kur));
}

// ---------------------------------------------------------------------------
// 19 · Belirli integralin özellikleri
// ---------------------------------------------------------------------------

String _intYaz(int alt, int ust, String f) => '∫${_alt(alt)}${_ust(ust)} $f dx';

AdvancedItem _integralOzellik(int a, int b, int c, int deneme) {
  final p = _sifirsiz(a, 12); // −12 … 13
  // c = 0'da p + q = 0 ya da p + q = pq, c = 1'de q = p ya da q = 2p iken bir
  // hatalı yol doğru yanıtı verirdi; bu q değerleri atlanır.
  final q = _uygun(
    [
      for (var x = -10; x <= 10; x++)
        if (x != 0) x,
      -11,
      11,
      -12,
      12,
    ],
    b,
    (x) => switch (c) {
      0 => x != -p && p + x != p * x,
      1 => x != p && x != 2 * p,
      _ => true,
    },
  );
  switch (c) {
    case 0 || 1:
      final x0 = const [-2, 0, 1, -1, 2][(a + b + deneme) % 5];
      final x1 = x0 + 2 + (b + deneme) % 3, x2 = x1 + 1 + (a + deneme) % 4;
      if (c == 0) {
        return _tam(
          '${_intYaz(x0, x1, 'f(x)')} = ${_n(p)} ve ${_intYaz(x1, x2, 'f(x)')} '
              '= ${_n(q)} olduğuna göre ${_intYaz(x0, x2, 'f(x)')} değeri kaçtır?',
          p + q,
          [p - q, q - p, p * q, -(p + q)],
          'Belirli integralde ardışık aralıklar birleştirilebilir: '
              '${_intYaz(x0, x2, 'f(x)')} = ${_intYaz(x0, x1, 'f(x)')} + '
              '${_intYaz(x1, x2, 'f(x)')} = ${_n(p)} + ${_p(q)} = ${_n(p + q)}.',
        );
      }
      return _tam(
        '${_intYaz(x0, x2, 'f(x)')} = ${_n(p)} ve ${_intYaz(x1, x2, 'f(x)')} '
            '= ${_n(q)} olduğuna göre ${_intYaz(x1, x0, 'f(x)')} değeri kaçtır?',
        q - p,
        [p - q, p + q, -(p + q), p],
        '${_intYaz(x0, x1, 'f(x)')} = ${_n(p)} − ${_p(q)} = ${_n(p - q)} olur. '
            'Sınırlar yer değiştirince işaret değişir: '
            '${_intYaz(x1, x0, 'f(x)')} = ${_n(q - p)}.',
      );
    case 2 || 3:
      // Aralık uzunluğu en az 2: sabit terimi uzunlukla çarpmayı unutan
      // doğru yanıtı bulmasın.
      final x0 = const [0, 1, -1, 2, -2][(a + deneme) % 5];
      final x1 = x0 + 2 + (b + deneme) % 4;
      final al = const [2, 3, -1, -2, 4][a ~/ 5];
      final be = c == 2 ? const [1, -3, 2, -2, 3][b ~/ 4] : 0;
      // c = 3'te sabit terim q'dur; b'yi kökte o taşır.
      final ga = c == 2 ? const [5, -2, 3, 1, -4][(a + b + deneme) % 5] : q;
      final fYaz = _pol([al, 0], 'f(x)');
      final gYaz = be.abs() == 1 ? 'g(x)' : '${be.abs()}g(x)';
      final ifade = c == 2
          ? '($fYaz ${be < 0 ? '−' : '+'} $gYaz${_sabitEk(ga)})'
          : '($fYaz${_sabitEk(ga)})';
      final yanit = al * p + be * q + ga * (x1 - x0);
      final veri = c == 2
          ? '${_intYaz(x0, x1, 'f(x)')} = ${_n(p)} ve '
                '${_intYaz(x0, x1, 'g(x)')} = ${_n(q)}'
          : '${_intYaz(x0, x1, 'f(x)')} = ${_n(p)}';
      final gTerim = c == 2
          ? ' ${be < 0 ? '−' : '+'} ${be.abs()}·${_p(q)}'
          : '';
      return _tam(
        '$veri olduğuna göre ${_intYaz(x0, x1, ifade)} değeri kaçtır?',
        yanit,
        c == 2
            ? [
                al * p + be * q + ga,
                al * p + be * q,
                p + q + ga * (x1 - x0),
                al * p - be * q + ga * (x1 - x0),
              ]
            : [
                al * p + ga, // uzunlukla çarpmayı unutma
                al * p, // sabiti unutma
                p + ga * (x1 - x0), // katsayıyı unutma
                al * p - ga * (x1 - x0), // işaret hatası
              ],
        'İntegral terimlere ayrılır ve sabit çarpanlar dışarı alınır: '
            '${_n(al)}·${_p(p)}$gTerim ${ga < 0 ? '−' : '+'} '
            '${ga.abs()}·(${_n(x1)} − ${_p(x0)}) = ${_n(yanit)}.',
      );
    case 4 || 5:
      final ust = 2 + (b + deneme) % 5;
      final k = q;
      if (c == 4) {
        // f tek: ∫₋ᵤ⁰ f = −∫₀ᵘ f.
        final yanit = -p + k * ust;
        return _tam(
          'f tek fonksiyon ve ${_intYaz(0, ust, 'f(x)')} = ${_n(p)} olduğuna '
              'göre ${_intYaz(-ust, 0, '(f(x)${_sabitEk(k)})')} değeri kaçtır?',
          yanit,
          [p + k * ust, -p, -p - k * ust, k * ust],
          'f tek olduğundan ${_intYaz(-ust, 0, 'f(x)')} = '
              '−${_intYaz(0, ust, 'f(x)')} = ${_n(-p)} olur. Sabitin integrali '
              '${_n(k)}·$ust = ${_n(k * ust)} olduğundan sonuç ${_n(yanit)} '
              'bulunur.',
        );
      }
      // f çift: ∫₋ᵤᵘ f = 2∫₀ᵘ f.
      final yanit = 2 * p + 2 * k * ust;
      return _tam(
        'f çift fonksiyon ve ${_intYaz(0, ust, 'f(x)')} = ${_n(p)} olduğuna '
            'göre ${_intYaz(-ust, ust, '(f(x)${_sabitEk(k)})')} değeri kaçtır?',
        yanit,
        [p + 2 * k * ust, 2 * p + k * ust, 2 * k * ust, 2 * p],
        'f çift olduğundan ${_intYaz(-ust, ust, 'f(x)')} = 2·${_p(p)} = '
            '${_n(2 * p)} olur. Sabitin integrali ${_n(k)}·(${_n(ust)} − '
            '(−$ust)) = ${_n(2 * k * ust)} olduğundan sonuç ${_n(yanit)} '
            'bulunur.',
      );
    case 6 || 7:
      // Simetrik aralıkta polinom: tek dereceli terimler sıfırlanır.
      final ust = 1 + a ~/ 5;
      final k2 =
          3 *
          (c == 6
              ? const [1, -1, 2, -2, 3][a % 5]
              : const [4, -4, 5, -5, -3][a % 5]);
      final k0 = _sifirsiz(b, 10);
      final k3 = const [1, -2, 3, -1, 2][(a + b + deneme) % 5];
      final k1 = const [-4, 5, -3, 2, 1][(a + 2 * b + deneme) % 5];
      final f = [k3, k2, k1, k0];
      final cift = k2 * ust * ust * ust ~/ 3 + k0 * ust;
      final yanit = 2 * cift;
      final tumu =
          _R(k3 * _us(ust, 4), 4) +
          _R(k2 * _us(ust, 3), 3) +
          _R(k1 * ust * ust, 2) +
          _R(k0 * ust);
      return _ras(
        '${_intYaz(-ust, ust, '(${_pol(f)})')} değeri kaçtır?',
        _R(yanit),
        [tumu, _R(cift), tumu * _R(2), _R(2 * k0 * ust)],
        '${_pol([k3, 0, k1, 0])} tek fonksiyon olduğundan [−$ust, $ust] '
            'aralığındaki integrali sıfırdır. Geriye 2·∫₀${_ust(ust)} '
            '(${_pol([k2, 0, k0])}) dx = 2·(${_n(k2 * _us(ust, 3) ~/ 3)} + '
            '${_p(k0 * ust)}) = ${_n(yanit)} kalır.',
      );
    default:
      // Aralık farkı ve doğrusallık birlikte.
      final x0 = const [0, 1, -1, 2, -2][(a + deneme) % 5];
      final x1 = x0 + 2 + (a ~/ 5 + deneme) % 3;
      final x2 = x1 + 1 + (b + deneme) % 3;
      final al = c == 8 ? 2 : 3;
      final ga = const [1, -2, 3, -1, 4][(b ~/ 4 + deneme) % 5];
      final toplam = p + q;
      final yanit = al * p + ga * (x1 - x0);
      return _tam(
        '${_intYaz(x0, x2, 'f(x)')} = ${_n(toplam)} ve '
            '${_intYaz(x1, x2, 'f(x)')} = ${_n(q)} olduğuna göre '
            '${_intYaz(x0, x1, '(${al}f(x)${_sabitEk(ga)})')} değeri kaçtır?',
        yanit,
        [
          al * toplam + ga * (x1 - x0),
          al * p + ga,
          p + ga * (x1 - x0),
          al * (toplam + q) + ga * (x1 - x0),
        ],
        '${_intYaz(x0, x1, 'f(x)')} = ${_n(toplam)} − ${_p(q)} = ${_n(p)} '
            'olur. İstenen integral $al·${_p(p)} ${ga < 0 ? '−' : '+'} '
            '${ga.abs()}·(${_n(x1)} − ${_p(x0)}) = ${_n(yanit)} bulunur.',
      );
  }
}

// ---------------------------------------------------------------------------
// 20 · İkinci türev: büküm noktası ve çukurluk yönü
// ---------------------------------------------------------------------------

/// Çukurluk yönü soruları: (tür, a₄ ya da k, r₁ ya da h, r₂ ya da yön).
/// Tür 0: dördüncü derece, n − m; tür 1: dördüncü derece, m + n; tür 2:
/// üçüncü derece, eşik değeri.
final List<(int, int, int, int)> _cukurluk = () {
  final l = <(int, int, int, int)>[];
  for (final a4 in const [1, 2, 3, 4]) {
    for (var r1 = -5; r1 <= 4; r1++) {
      for (var r2 = r1 + 1; r2 <= 5; r2++) {
        l
          ..add((0, a4, r1, r2))
          ..add((1, a4, r1, r2));
      }
    }
  }
  for (final k in const [1, -1, 2, -2, 3, -3, 4, -4]) {
    for (var h = -8; h <= 8; h++) {
      if (h == 0) continue;
      l
        ..add((2, k, h, 1))
        ..add((2, k, h, -1));
    }
  }
  return [for (var i = 0; i < l.length; i++) l[i * 101 % l.length]];
}();

/// Çukurluk yönü soruları: t, [_cukurluk] listesindeki sıradır.
AdvancedItem _bukumCukur(int t) {
  final (tur, ka, x1, x2) = _cukurluk[t];
  if (tur < 2) {
    final e = const [3, -5, 2, -1, 4][t % 5];
    final g = const [1, -2, 6, -4, 3][(t ~/ 5) % 5];
    final f = [ka, -2 * ka * (x1 + x2), 6 * ka * x1 * x2, e, g];
    final f2 = _turevK(_turevK(f));
    final yanit = tur == 0 ? x2 - x1 : x1 + x2;
    return _tam(
      'f(x) = ${_pol(f)} fonksiyonunun grafiğinin çukurluk yönünün aşağı '
          'doğru olduğu en geniş aralık (m, n) olduğuna göre '
          '${tur == 0 ? 'n − m farkı' : 'm + n toplamı'} kaçtır?',
      yanit,
      tur == 0
          ? [x1 + x2, x1 * x2, 2 * (x2 - x1), x2 - x1 + 1]
          : [x2 - x1, -(x1 + x2), x1 * x2, x1 + x2 + 1],
      'f″(x) = ${_pol(f2)} = ${12 * ka}·${x1 == 0 ? 'x' : '(${_pol([1, -x1])})'}·'
          '${x2 == 0 ? 'x' : '(${_pol([1, -x2])})'} olur. f″(x) < 0 olan aralık '
          '(${_n(x1)}, ${_n(x2)}) olduğundan m = ${_n(x1)}, n = ${_n(x2)}; '
          '${tur == 0 ? 'n − m = ${x2 - x1}' : 'm + n = ${_n(x1 + x2)}'}.',
      pozitif: tur == 0,
    );
  }
  // Üçüncü derece: f″ işaret değiştirdiği x = h noktası eşiktir.
  final k = ka, h = x1, yukari = x2 == 1;
  final m = const [2, -3, 5, -1, 4][t % 5];
  final n0 = const [1, -4, 3, -2, 6][(t ~/ 5) % 5];
  final f = [k, -3 * k * h, 3 * k * h * h + m, -k * h * h * h - m * h + n0];
  final buyuk = (k > 0) == yukari;
  // "x > t olan her yerde" demek her t ≥ h için doğru olurdu; en geniş
  // aralık sorulduğunda yalnız t = h doğrudur.
  final aralik = buyuk ? '(t, ∞)' : '(−∞, t)';
  final bulunan = buyuk ? '(${_n(h)}, ∞)' : '(−∞, ${_n(h)})';
  return _tam(
    'f(x) = ${_pol(f)} fonksiyonunun grafiğinin çukurluk yönünün '
        '${yukari ? 'yukarı' : 'aşağı'} doğru olduğu en geniş aralık $aralik '
        'olduğuna göre t kaçtır?',
    h,
    [-h, 3 * h, h + 1, -3 * k * h],
    'f″(x) = ${_pol(_turevK(_turevK(f)))} = 0 eşitliğinden x = ${_n(h)} '
        'bulunur. ${k > 0 ? 'Baş katsayı pozitif olduğundan' : 'Baş katsayı negatif olduğundan'} '
        'f″(x), x > ${_n(h)} için ${k > 0 ? 'pozitif' : 'negatif'}, '
        'x < ${_n(h)} için ${k > 0 ? 'negatif' : 'pozitif'}tir. Çukurluk yönü '
        'f″ > 0 iken yukarı, f″ < 0 iken aşağı doğru olduğundan aralık '
        '$bulunan ve t = ${_n(h)} olur.',
  );
}

AdvancedItem _bukum(int a, int b, int c, int deneme) {
  if (c == 5) {
    final t = _temizSec('bukum5', _cukurluk.length, _bukumCukur, a + 25 * b);
    return _bukumCukur(t);
  }
  if (c <= 3 || c == 9) {
    // Üçüncü derece: f(x) = k(x − h)³ + m(x − h) + n; büküm noktası (h, n),
    // oradaki teğetin eğimi m.
    // c = 9'da öncül katsayı 1'dir; a yalnız büküm noktasını seçer. Büküm
    // apsisi 1 olamaz: f(1) = 1 + a + b + c olduğundan a + b + c doğrudan
    // ordinattan okunur, büküm koşulu ve eğim gereksiz kalırdı.
    final k = const [1, -1, 2, -2, 3][a % 5];
    final h = c == 9
        ? const [-2, -1, -3, 2, 3][a % 5]
        : const [-2, -1, 1, 2, 3][a ~/ 5];
    // Büküm noktasındaki eğim m kökteki katsayılara, sabit terim ise
    // ordinata eşit çıkmasın (m = −kh² iken sabit terim n olur).
    final yasak = {
      k,
      -k,
      3 * k * h,
      -3 * k * h,
      -k * h * h,
      if ((3 * k * h * h).isEven) -3 * k * h * h ~/ 2,
    };
    final m = _uygun(
      [
        for (var x = -10; x <= 10; x++)
          if (x != 0) x,
        -11,
        11,
        -12,
        12,
        -13,
        13,
        -14,
        14,
      ],
      b,
      (x) {
        if (c != 9) return !yasak.contains(x);
        // c = 9: a + b + c = x(1 − h) + n − h³ + 3h² − 3h, kökteki h, n ve
        // eğime eşit olmasın. b = x + 3h² ya da c = n − h³ − xh sıfır
        // çıkarsa bir katsayıyı unutan yol, yanıt 0 iken işaret hatası,
        // yanıt n − 1 iken büküm ordinatını f(1) sanan yol
        // (1 + a + b + c = n) yanıtı verirdi; bu eğimler atlanır.
        final nn = const [3, -4, 5, -1, 6][a ~/ 5];
        final y = x * (1 - h) + nn - h * h * h + 3 * h * h - 3 * h;
        final b9 = x + 3 * h * h, c9 = nn - h * h * h - x * h;
        return y != 0 &&
            y != nn - 1 &&
            b9 != 0 &&
            c9 != 0 &&
            !{x, -x, h, -h, nn, -nn}.contains(y);
      },
    );
    final n = c == 9
        ? const [3, -4, 5, -1, 6][a ~/ 5]
        : const [3, -4, 5, -1, 2][(a + b + deneme) % 5];
    final f = [k, -3 * k * h, 3 * k * h * h + m, -k * h * h * h - m * h + n];
    final f1 = _turevK(f), f2 = _turevK(f1);
    final bas =
        'f″(x) = ${_pol(f2)} = 0 eşitliğinden x = ${_n(h)} bulunur; ikinci '
        'türev bu noktada işaret değiştirir.';
    switch (c) {
      case 0:
        return _tam(
          'f(x) = ${_pol(f)} fonksiyonunun büküm noktasının ordinatı kaçtır?',
          n,
          [_deg(f, -h), f[3], _deg(f, h + 1), n + m],
          '$bas Büküm noktasının ordinatı f(${_n(h)}) = ${_yerine(f, h)} = '
              '${_n(n)} olur.',
        );
      case 1:
        return _tam(
          'f(x) = ${_pol(f)} fonksiyonunun grafiğine büküm noktasında çizilen '
              'teğetin eğimi kaçtır?',
          m,
          [f[2], _deg(f1, -h), _deg(f2, h + 1), m + 3 * k],
          '$bas Teğetin eğimi f′(${_n(h)}) = ${_yerine(f1, h)} = ${_n(m)} '
              'olur.',
        );
      case 2:
        return _tam(
          'f(x) = ${_pol(f)} fonksiyonunun büküm noktası (a, b) olduğuna göre '
              'a + b toplamı kaçtır?',
          h + n,
          [n - h, h + f[3], _deg(f, -h) - h, h * n],
          '$bas f(${_n(h)}) = ${_yerine(f, h)} = ${_n(n)} olduğundan büküm '
              'noktası (${_n(h)}, ${_n(n)}) ve a + b = ${_n(h + n)} olur.',
        );
      case 3:
        // f(x) = x³ + px² + qx + r: büküm noktası (h₂, n₂) verilir. h₂ = 1
        // olamaz: f(1) = 1 + p + q + r eşitliği p + q'yu büküm koşulu
        // kullanılmadan verirdi.
        final h2 = const [-2, -1, -3, 2, 3][a % 5];
        final r = const [4, -3, 2, -5, 1][a ~/ 5];
        AdvancedItem kur(int q) {
          final p = -3 * h2;
          final n2 = _deg([1, p, q, r], h2);
          return _tam(
            'f(x) = x³ + px² + qx${_sabitEk(r)} fonksiyonunun büküm noktası '
                '(${_n(h2)}, ${_n(n2)}) olduğuna göre p + q toplamı kaçtır?',
            p + q,
            [
              q - p,
              p,
              3 * h2 + q,
              p * q,
              // Büküm ordinatını f(1) sanan yol (1 + p + q + r = n₂) ve büküm
              // noktasını f′(h₂) = 0 ile arayan yol (tam sayı çıkarsa).
              n2 - 1 - r,
              if (q % h2 == 0) -q ~/ h2 - 3 * h2 * h2 + 2 * q,
            ],
            'f″(x) = 6x + 2p olur. f″(${_n(h2)}) = 0 eşitliğinden p = ${_n(p)} '
                'bulunur. f(${_n(h2)}) = ${_n(n2)} eşitliğinden '
                '${_n(h2 * h2 * h2 + p * h2 * h2 + r)} + ${_p(h2)}·q = ${_n(n2)} ve '
                'q = ${_n(q)} olur. p + q = ${_n(p + q)}.',
          );
        }

        return kur(_temizOge('bukum3-$a', _sifirsizAralik(-15, 15), b, kur));
      default:
        // f(x) = x³ + px² + qx + r; büküm noktası (h, n), eğim m.
        final p = -3 * h;
        final q = m - 3 * h * h - 2 * p * h;
        final r = n - h * h * h - p * h * h - q * h;
        final yanit = p + q + r;
        return _tam(
          'f(x) = x³ + ax² + bx + c fonksiyonunun büküm noktası '
              '(${_n(h)}, ${_n(n)}) ve bu noktadaki teğetinin eğimi ${_n(m)} '
              'olduğuna göre a + b + c toplamı kaçtır?',
          yanit,
          [p + q, yanit + 1, -yanit, p + r],
          'f″(x) = 6x + 2a = 0 eşitliği x = ${_n(h)} için a = ${_n(p)} verir. '
              'f′(${_n(h)}) = 3·${_p(h)}² + 2·${_p(p)}·${_p(h)} + b = ${_n(m)} '
              'eşitliğinden b = ${_n(q)}; f(${_n(h)}) = ${_n(n)} eşitliğinden '
              'c = ${_n(r)} bulunur. a + b + c = ${_n(yanit)}.',
        );
    }
  }
  // c = 4, 6, 7, 8: dördüncü derece; f″(x) = 12(x − r₁)(x − r₂).
  // c = 6'da büyük, c = 8'de küçük büküm apsisi 0 olmasın: yanıt kökteki
  // katsayıya eşit çıkardı. c = 6'da r₂ = 3r₁, c = 7'de f(r₁) = f(r₂) olan
  // çiftler de (yanıt x'in katsayısına eşit çıkardı) atlanır.
  final r1 = switch (c) {
    6 => const [-6, -7, 4, 5, 3][a % 5],
    7 => const [-3, -4, 0, 1, 2][a % 5],
    8 => const [-3, -2, -1, 1, 2][a % 5],
    _ => const [-3, -2, -1, 0, 1][a % 5],
  };
  final r2 = r1 + 1 + a ~/ 5;
  final e = _sifirsiz(b, 10);
  final g = const [2, -5, 1, 4, -3][(a + b + deneme) % 5];
  final f = [1, -2 * (r1 + r2), 6 * r1 * r2, e, g];
  final f1 = _turevK(f), f2 = _turevK(f1);
  final bas =
      'f″(x) = ${_pol(f2)} = 12·${r1 == 0 ? 'x' : '(${_pol([1, -r1])})'}·'
      '${r2 == 0 ? 'x' : '(${_pol([1, -r2])})'} olur; ikinci türev x = '
      '${_n(r1)} ve x = ${_n(r2)} noktalarında işaret değiştirir.';
  switch (c) {
    case 4:
      final yanit = _deg(f, r1) + _deg(f, r2);
      return _tam(
        'f(x) = ${_pol(f)} fonksiyonunun büküm noktalarının ordinatları '
            'toplamı kaçtır?',
        yanit,
        [_deg(f, r1), _deg(f, r2), r1 + r2, yanit - 2 * g],
        '$bas f(${_n(r1)}) = ${_n(_deg(f, r1))} ve f(${_n(r2)}) = '
            '${_n(_deg(f, r2))} olduğundan toplam ${_n(yanit)} olur.',
      );
    case 6:
      final yanit = _deg(f1, r2);
      return _tam(
        'f(x) = ${_pol(f)} fonksiyonunun apsisi büyük olan büküm noktasında '
            'çizilen teğetin eğimi kaçtır?',
        yanit,
        [_deg(f1, r1), _deg(f, r2), _deg(f2, r2 + 1), e],
        '$bas Büyük apsisli büküm noktası x = ${_n(r2)} olur. f′(x) = '
            '${_pol(f1)} olduğundan f′(${_n(r2)}) = ${_yerine(f1, r2)} = '
            '${_n(yanit)}.',
      );
    case 7:
      // İki büküm noktasından geçen doğrunun eğimi.
      final dy = _deg(f, r2) - _deg(f, r1);
      final yanit = dy ~/ (r2 - r1);
      return _tam(
        'f(x) = ${_pol(f)} fonksiyonunun grafiğinin iki büküm noktasından '
            'geçen doğrunun eğimi kaçtır?',
        yanit,
        [dy, _deg(f1, r1), _deg(f1, r2), -yanit],
        '$bas f(${_n(r1)}) = ${_n(_deg(f, r1))} ve f(${_n(r2)}) = '
            '${_n(_deg(f, r2))} olduğundan eğim (${_n(_deg(f, r2))} − '
            '${_p(_deg(f, r1))})/(${_n(r2)} − ${_p(r1)}) = ${_n(yanit)} bulunur.',
      );
    default:
      final yanit = _deg(f, r1);
      return _tam(
        'f(x) = ${_pol(f)} fonksiyonunun apsisi küçük olan büküm noktasının '
            'ordinatı kaçtır?',
        yanit,
        [_deg(f, r2), _deg(f, -r1), _deg(f1, r1), yanit + g],
        '$bas Küçük apsisli büküm noktası x = ${_n(r1)} olur. f(${_n(r1)}) = '
            '${_yerine(f, r1)} = ${_n(yanit)}.',
      );
  }
}

// ---------------------------------------------------------------------------
// Aileler
// ---------------------------------------------------------------------------

final lmAnaliz = <AdvancedFamily>[
  // 1 · Toplam-fark: c ∈ {0, 1, 2, 3, 8, 9} → Pisagor üçlüleriyle sin, cos,
  // tan; c ∈ {4, 5, 6, 7} → tanjant değerleriyle toplam, fark ve ters yön.
  _aile(
    'toplam_fark',
    'Toplam-fark formülleriyle trigonometrik değer',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) => c >= 4 && c <= 7
        ? _toplamFarkTan(a, b, c)
        : _toplamFarkUclu(a, b, c <= 3 ? c : c - 4),
  ),

  // 2 · İki kat açı: tan, cot, sin/cos ve aralık, bitim kenarı noktası ya da
  // kesirli/köklü oran verilir; sin 2x, cos 2x, tan 2x ya da cot 2x sorulur.
  _aile(
    'iki_kat',
    'İki kat açı formülleriyle sin 2x, cos 2x, tan 2x, cot 2x',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) => _ikiKat(
      _ikiKatHavuz[(a + 25 * b + 500 * c) * 1013 % lmAileBoyu],
      hedefSira(_vaka(a, b, c)),
    ),
  ),

  // 3 · Trigonometrik denklem: c < 6 → özel değerli sin, cos, tan denklemi
  // (toplam, en küçük ya da en büyük kök); c ≥ 6 → çarpanlarına ayrılan
  // ikinci dereceden denklem (kök sayısı ya da toplamı).
  _aile(
    'trig_denklem',
    'Trigonometrik denklemlerin kökleri, kök sayısı ve toplamı',
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) => c < 6 ? _trigDenklemOzel(a, b, c) : _trigDenklemKare(a, b, c),
  ),

  // 4 · Sinüs teoremi: c ≤ 1 özel açılar, c ≤ 5 kesirli sinüsler, c ≥ 6
  // çevrel çemberin yarıçapı.
  _aile(
    'sinus_teoremi',
    'Sinüs teoremiyle kenar, sinüs ve çevrel çember',
    Difficulty.medium,
    BloomLevel.uygulama,
    _sinusTeoremi,
  ),

  // 5 · Kosinüs teoremi: c ≤ 8 üç kenardan kosinüs, c = 9 iki kenar ve aradaki
  // açıdan üçüncü kenar.
  _aile(
    'kosinus_teoremi',
    'Kosinüs teoremiyle kenar ve açının kosinüsü',
    Difficulty.medium,
    BloomLevel.uygulama,
    _kosinusTeoremi,
  ),
  // 6 · İşaretler: c < 5 üç terimin işareti, c ≥ 5 üç değerin sıralaması.
  _aile(
    'trig_isaret',
    'Trigonometrik oranların işareti ve sıralanması',
    Difficulty.medium,
    BloomLevel.anlama,
    _trigIsaret,
    shortAnswer: false,
  ),

  // 7 · Periyot ve uç değerler: c ≤ 4 değerlerden katsayı bulma, c = 5, 6
  // uç değer ile periyodun çarpımı, c ≥ 7 a·sin x + b·cos x + d.
  _aile(
    'periyot',
    'Esas periyot ile en büyük ve en küçük değer',
    Difficulty.medium,
    BloomLevel.uygulama,
    _periyotSoru,
    shortAnswer: false,
  ),

  // 8 · Ters trigonometri: c ≤ 2 esas değer, c = 3 bileşke, c = 4, 5 özel
  // değerlerle işlem, c ≥ 6 denklem.
  _aile(
    'ters_trig',
    'Ters trigonometrik fonksiyonların değerleri',
    Difficulty.medium,
    BloomLevel.uygulama,
    _tersTrig,
    shortAnswer: false,
  ),

  // 9 · Basamak sayısı: c ≤ 3 kuvvet, c = 4 2 ve 5 kuvvetleri, c = 5 çarpım,
  // c = 6, 7 üs sınırı, c = 8, 9 karşılaştırma.
  _aile(
    'log_basamak',
    'Logaritmayla basamak sayısı ve büyüklük karşılaştırma',
    Difficulty.hard,
    BloomLevel.analiz,
    _yeniden(_logBasamak),
  ),

  // 10 · Üstel modeller: katlanma ve yarılanma süreleri, logaritmalı süre,
  // açık model ve ters yönde periyot bulma.
  _aile(
    'log_model',
    'Üstel büyüme ve azalma modellerinde süre ve miktar',
    Difficulty.medium,
    BloomLevel.uygulama,
    _logModel,
  ),
  // 11 · Parçalı fonksiyon: c ≤ 2 iki değerin toplamı, c ≤ 5 f(f(p)), c = 6, 7
  // tek-çift kurallı bileşke, c = 8, 9 f(t) = v denkleminin çözümleri.
  _aile(
    'parcali',
    'Parçalı tanımlı fonksiyonun değeri ve f(f(a))',
    Difficulty.medium,
    BloomLevel.uygulama,
    _yeniden(_parcaliSoru, 9),
  ),

  // 12 · Grafik dönüşümleri: c ≤ 3 dönüşen grafiğin noktası, c ≤ 6 ters yön,
  // c ≥ 7 kuralı verilen fonksiyonla dönüşüm.
  _aile(
    'grafik_donusum',
    'Fonksiyon grafiklerinde öteleme ve yansıma',
    Difficulty.medium,
    BloomLevel.anlama,
    _yeniden(_grafikDonusum),
    shortAnswer: false,
  ),

  // 13 · Süreklilik: c ≤ 2 sağdan ve soldan limit, c ≤ 5 parametre, c = 6, 7
  // kaldırılabilir süreksizlik, c = 8, 9 iki parametre.
  _aile(
    'sureklilik',
    'Parçalı fonksiyonda limit ve süreklilik',
    Difficulty.medium,
    BloomLevel.uygulama,
    _yeniden(_sureklilik),
  ),

  // 14 · Zincir kuralı: (ax + b)ⁿ biçimleri, f(g(x)), değerlerle bileşke
  // türevi ve köklü ifadeler.
  _aile(
    'zincir_kurali',
    'Zincir kuralıyla bileşke fonksiyonun türevi',
    Difficulty.medium,
    BloomLevel.uygulama,
    _yeniden(_zincirKurali),
  ),

  // 15 · Konum, hız ve ivme: anlık hız ve ivme, hızın sıfır olduğu anlar,
  // o andaki konum ve ivme, alınan yol.
  _aile(
    'konum_hiz',
    'Konum fonksiyonundan hız ve ivme',
    Difficulty.medium,
    BloomLevel.uygulama,
    _yeniden(_konumHiz),
  ),
  // 16 · En büyük ve en küçük değer problemleri: çit, bütçeli çit, doğru
  // altında dikdörtgen, sabit toplam, kutu ve sabit çarpım, kapalı aralık.
  _aile(
    'optimizasyon',
    'Türevle en büyük ve en küçük değer problemleri',
    Difficulty.hard,
    BloomLevel.analiz,
    _optimizasyon,
  ),

  // 17 · Belirsiz integral: F′ ve F(a) verilir; teğet eğimi, ikinci türev ve
  // ters yönde katsayı soruları.
  _aile(
    'belirsiz_integral',
    'Belirsiz integral ve başlangıç koşulu',
    Difficulty.medium,
    BloomLevel.uygulama,
    _yeniden(_belirsizIntegral, 20),
  ),

  // 18 · İki eğri arasındaki alan: parabol ve doğru, iki parabol, üçüncü
  // dereceden eğri ve doğru.
  _aile(
    'iki_egri_alan',
    'İki eğri arasında kalan bölgenin alanı',
    Difficulty.hard,
    BloomLevel.analiz,
    _yeniden(_ikiEgriAlan, 20),
  ),

  // 19 · Belirli integralin özellikleri: aralık birleştirme, doğrusallık, tek
  // ve çift fonksiyon simetrisi.
  _aile(
    'integral_ozellik',
    'Belirli integralin özellikleri ve simetri',
    Difficulty.medium,
    BloomLevel.anlama,
    _yeniden(_integralOzellik, 20),
  ),

  // 20 · İkinci türev: büküm noktası, teğet eğimi, çukurluk yönü aralıkları.
  _aile(
    'bukum',
    'İkinci türevle büküm noktası ve çukurluk yönü',
    Difficulty.hard,
    BloomLevel.analiz,
    _yeniden(_bukum, 10),
  ),
];
