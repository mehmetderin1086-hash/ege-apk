// AYT Matematik metin aileleri (ikinci tur): toplam-fark ve iki kat açı,
// trigonometrik denklem, sinüs ve kosinüs teoremi, ters trigonometri,
// logaritma uygulamaları, fonksiyonlar, süreklilik, türev ve integral.
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

/// Yarım derece biriminde verilen açının yazımı: `_yarim(15)` → `7,5`.
String _yarim(int x2) => tr(x2 / 2);

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
  final adim = yanit.abs() >= 200 ? 10 : (yanit.abs() >= 40 ? 5 : 1);
  final havuz = [
    for (final x in adaylar)
      if (x != null) x,
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
/// tamamlanır.
AdvancedItem _ras(
  String kok,
  _R yanit,
  Iterable<_R?> adaylar,
  String aciklama, {
  bool pozitif = false,
}) {
  final havuz = <_R>[
    for (final x in adaylar)
      if (x != null) x,
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
  ].where((x) => !pozitif || x.p > 0);
  return secenekli(kok, '$yanit', havuz.map((x) => '$x'), aciklama);
}

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
  // tanımsız, eş açılar sin(x − y) değerini sıfır yapardı.
  final aday = [
    for (final f in const [1, 0, 3, 2])
      for (var j = 0; j < 10; j++)
        if (j ~/ 2 != x.uclu) (f, j),
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
      );
    case 1:
      return _ras(
        kok,
        sEksi,
        [sArti, -sEksi, cArti, sx - sy],
        '$turet sin(x − y) = sin x·cos y − cos x·sin y = ${ikili(sx, cy)} − '
        '${ikili(cx, sy)} = ($sc − $cs)/$hh = $sEksi.',
      );
    case 2:
      return _ras(
        kok,
        cArti,
        [cEksi, -cArti, sArti, cx * cy],
        '$turet cos(x + y) = cos x·cos y − sin x·sin y = ${ikili(cx, cy)} − '
        '${ikili(sx, sy)} = ($cc − $ss)/$hh = $cArti.',
      );
    case 3:
      return _ras(
        kok,
        cEksi,
        [cArti, sArti, sEksi, cx * cy],
        '$turet cos(x − y) = cos x·cos y + sin x·sin y = ${ikili(cx, cy)} + '
        '${ikili(sx, sy)} = ($cc + $ss)/$hh = $cEksi.',
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

AdvancedItem _ikiKat(_IkiKat veri) {
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
      return _ras(
        kok,
        yanit,
        [
          if (kare != bir) (bir + kare) / (bir - kare),
          (kare - bir) / (bir + kare),
          bir - kare,
        ],
        'tan² x = $kare olur. cos 2x = (1 − tan² x)/(1 + tan² x) = '
        '${_rs(bir - kare)}/${_rs(bir + kare)} = $yanit.',
      );
    }
    final kareYaz = kesirli ? '' : '$ad² x = $kare olduğundan ';
    if (ad == 'sin') {
      final yanit = bir - _R(2) * kare;
      return _ras(kok, yanit, [
        _R(2) * kare - bir,
        bir - kare,
        if (kesirli) bir - _R(2 * s, t) else _R(2) * kare,
      ], '${kareYaz}cos 2x = 1 − 2·sin² x = 1 − 2·${_rs(kare)} = $yanit.');
    }
    final yanit = _R(2) * kare - bir;
    return _ras(kok, yanit, [
      bir - _R(2) * kare,
      kare - bir,
      if (kesirli) _R(2 * s, t) - bir else _R(2) * kare,
    ], '${kareYaz}cos 2x = 2·cos² x − 1 = 2·${_rs(kare)} − 1 = $yanit.');
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
          ? 'sin 2x = 2·tan x/(1 + tan² x) = ${_rs(t2)}/${_rs(tp)} = $sin2.'
          : 'sin 2$x = 2·sin $x·cos $x = 2·${_sar(_kokluOran(v, nn))}·'
                '${_sar(_kokluOran(u, nn))} = $sin2.';
      return _ras(kok, sin2, [
        -sin2,
        _R(u * v, nn),
        cos2,
        tan2,
      ], '$giris$hesap');
    case 1:
      final hesap = bicim <= 1
          ? 'cos 2x = (1 − tan² x)/(1 + tan² x) = ${_rs(t1)}/${_rs(tp)} = '
                '$cos2.'
          : 'cos 2α = cos² α − sin² α = ${_R(u * u, nn)} − ${_R(v * v, nn)} '
                '= $cos2.';
      return _ras(kok, cos2, [
        -cos2,
        sin2,
        _R(u * u - v * v, u * u),
        _R(nn, u * u - v * v),
      ], '$giris$hesap');
    case 2:
      return _ras(
        kok,
        tan2,
        [-tan2, sin2, _R(2 * v, u), cot2],
        '$giris${tanSatir}tan 2$x = 2·tan $x/(1 − tan² $x) = '
        '${_rs(t2)}/${_rs(t1)} = $tan2.',
      );
    default:
      final k2 = cotx * cotx - bir, k1 = _R(2) * cotx;
      final cotSatir = bicim == 1
          ? ''
          : 'cot $x = cos $x/sin $x = $cotx olur. ';
      final cotGiris = bicim == 1 ? '' : giris;
      return _ras(
        kok,
        cot2,
        [-cot2, tan2, _R(u * u - v * v, u * v), cos2],
        '$cotGiris${bicim == 0 ? 'tan x = $tanx olduğundan cot x = $cotx olur. ' : cotSatir}'
        'cot 2$x = (cot² $x − 1)/(2·cot $x) = ${_rs(k2)}/${_rs(k1)} = $cot2.',
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
  return secenekli(kokMetin, _yarim(yanit2), [
    for (final x in adaylar2) _yarim(x),
    _yarim(yanit2 + 60),
    _yarim(yanit2 + 120),
    _yarim(yanit2 + 180),
  ], aciklama);
}

/// İkinci dereceden trigonometrik denklemlerin kök çiftleri ((p1, q1),
/// (p2, q2)): birinci kök [−1, 1] içindedir; ikinci kök ya listede sonra
/// gelen bir geçerli kök ya da [−1, 1] dışında kalan, çözüm vermeyen bir
/// köktür. Katsayıları (dönüştürülmüş biçimin sabit terimi de) en küçük olan
/// 500 çift alınır; en büyük katsayı 18'dir.
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
  return [for (final e in l.take(500)) (e.$4, e.$5)];
}();

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
  final sinus = c.isEven; // c = 6, 8: sinüs; 7, 9: kosinüs
  final sayi = c <= 7; // 6, 7: kök sayısı; 8, 9: kökler toplamı
  final ((p1, q1), (p2, q2)) = _trigKokCiftleri[a + 25 * b];
  final ka = q1 * q2, kb = -(q1 * p2 + q2 * p1), kc = p1 * p2;
  final g = sinus ? 'sin x' : 'cos x', g2 = sinus ? 'sin² x' : 'cos² x';
  final h2 = sinus ? 'cos² x' : 'sin² x';
  final denklem = sayi
      ? '${_ikinciDerece(ka, kb, kc, g2, g)} = 0'
      : '${_ikinciDerece(ka, -kb, -(ka + kc), h2, g)} = 0';
  // Kökün [0°, 360°) aralığındaki çözümleri: (sayı, toplam, açıklama).
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
              '$yaz için biri birinci, biri ikinci bölgede iki kök vardır; '
                  'bunlar a ve 180° − a biçiminde olduğundan toplamları 180°',
            )
          : (
              2,
              540,
              '$yaz için biri üçüncü, biri dördüncü bölgede iki kök vardır; '
                  'bunlar 180° + a ve 360° − a biçiminde olduğundan '
                  'toplamları 540°',
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
          'bölgede iki kök vardır; bunlar a ve 360° − a biçiminde olduğundan '
          'toplamları 360°',
    );
  }

  final (n1, t1, a1) = coz(p1, q1);
  final (n2, t2, a2) = coz(p2, q2);
  final donusum = sayi
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
  if (sayi) {
    final yanit = n1 + n2;
    return _tam(
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
  }
  final yanit = t1 + t2;
  // Hatalı toplamlar: sinüste her köke 180°, kosinüste 180° verme; geçersiz
  // kökü de toplama katma.
  int yanlis(int p, int q, int dogru) => !gecerli(p, q)
      ? (sinus ? 180 : 360)
      : (p.abs() == q ? dogru : (sinus ? 180 : 180));
  return _tam(kokMetin, yanit, [
    yanlis(p1, q1, t1) + yanlis(p2, q2, t2),
    t1 + t2 + (gecerli(p2, q2) ? 0 : (sinus ? 180 : 360)),
    yanit + 180,
    if (yanit >= 180) yanit - 180,
    yanit + 360,
  ], '${aciklama}Köklerin toplamı $t1° + $t2° = $yanit°.');
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
  for (var s = 5; s <= 40; s++)
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
/// verilir, R sorulur; 1: R = r ve |BC| verilir, sin A sorulur; 2: m(A) = s°
/// ve |BC| = r·√… verilir, çap sorulur.
final List<(int, int, int, int)> _cevrelVeri = () {
  final l = <(int, int, int, int)>[];
  for (final (p, q) in _sinKesir) {
    final birim = q ~/ q.gcd(2 * p);
    for (var r = birim; r <= 66; r += birim) {
      l
        ..add((0, p, q, r))
        ..add((1, p, q, r));
    }
  }
  for (final aci in const [30, 45, 60, 120, 135, 150]) {
    for (var m = 1; m <= 20; m++) {
      l.add((2, aci, 0, m));
    }
  }
  int boy((int, int, int, int) e) => e.$1 == 2 ? 2 * e.$4 : e.$4;
  final sirali = [
    for (var i = 0; i < l.length; i++) (boy(l[i]), i),
  ]..sort((p, q) => p.$1 != q.$1 ? p.$1.compareTo(q.$1) : p.$2.compareTo(q.$2));
  return [for (final e in sirali.take(1000)) l[e.$2]];
}();

AdvancedItem _sinusTeoremi(int a, int b, int c) {
  if (c <= 1) {
    // Özel açılar: j → (çift, sunuş, ölçek).
    final j = a + 25 * b + 500 * c;
    final varyant = j % (_sinusCiftleri.length * 3);
    final t = j ~/ (_sinusCiftleri.length * 3) + 1;
    final (ax, by) = _sinusCiftleri[varyant ~/ 3];
    final sunus = varyant % 3;
    final cz = 180 - ax - by;
    final (kap, f) = _sinusOran(ax, by);
    final bKenar = t * kap.q, katsayi = t * kap.p;
    final aYaz = f == 1 ? '$katsayi' : (katsayi == 1 ? '√$f' : '$katsayi√$f');
    final acilar = switch (sunus) {
      0 => 'm(A) = $ax° ve m(B) = $by°',
      1 => 'm(A) = $ax° ve m(C) = $cz°',
      _ => 'm(B) = $by° ve m(C) = $cz°',
    };
    final bul = switch (sunus) {
      0 => '',
      1 => 'm(B) = 180° − $ax° − $cz° = $by° olur. ',
      _ => 'm(A) = 180° − $by° − $cz° = $ax° olur. ',
    };
    // Oranı ters kurma (a·sin A/sin B) rasyonel çıktığında çeldiricidir.
    final tersOran = _R(katsayi * katsayi * f, bKenar);
    return _tam(
      'ABC üçgeninde $acilar, |BC| = $aYaz cm olduğuna göre |AC| kaç cm '
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
      return diger.p < diger.q && diger.q <= 36;
    });
    final sa = c == 5 ? verilen * _R(p, q) : verilen;
    final sb = c == 5 ? verilen : verilen * _R(q, p);
    final oran = '|BC|/sin A = |AC|/sin B';
    switch (c) {
      case 2:
        return _tam(
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
      case 3:
        return _tam(
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
      case 4:
        return _ras(
          'ABC üçgeninde |BC| = $p cm, |AC| = $q cm ve sin A = $sa olduğuna '
              'göre sin B değeri kaçtır?',
          sb,
          [sa * _R(p, q), _R(q, p), sa * _R(q), _R(1) - sb],
          'Sinüs teoremine göre $oran olur. $p/${_rs(sa)} = $q/sin B '
              'eşitliğinden sin B = $q·${_rs(sa)}/$p = $sb bulunur.',
          pozitif: true,
        );
      default:
        return _ras(
          'ABC üçgeninde |BC| = $p cm, |AC| = $q cm ve sin B = $sb olduğuna '
              'göre sin A değeri kaçtır?',
          sa,
          [sb * _R(q, p), _R(p, q), sb * _R(p), _R(1) - sa],
          'Sinüs teoremine göre $oran olur. $p/sin A = $q/${_rs(sb)} '
              'eşitliğinden sin A = $p·${_rs(sb)}/$q = $sa bulunur.',
          pozitif: true,
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
    return _tam(
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
  }
  // Çevrel çember.
  final (bicim, s, t, r) = _cevrelVeri[a + 25 * b + 500 * (c - 8)];
  if (bicim == 2) {
    final (n, d, kk) = _sinOzel[s]!;
    final aYaz = kk == 1 ? '$r' : (r == 1 ? '√$kk' : '$r√$kk');
    final cap = 2 * r * d ~/ (2 * n); // a/sin A = r·√k/(√k/2) = 2r
    return _tam(
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
  }
  final sa = _R(s, t);
  final aKenar = 2 * r * s ~/ t;
  if (bicim == 0) {
    return _tam(
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
  }
  return _ras(
    'Çevrel çemberinin yarıçapı $r cm olan ABC üçgeninde |BC| = $aKenar cm '
        'olduğuna göre sin A değeri kaçtır?',
    sa,
    [_R(aKenar, r), _R(2 * r, aKenar), _R(r, 2 * aKenar), _R(aKenar, 4 * r)],
    'Sinüs teoremine göre |BC|/sin A = 2R olur. $aKenar/sin A = ${2 * r} '
        'eşitliğinden sin A = $aKenar/${2 * r} = $sa bulunur.',
    pozitif: true,
  );
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
          'eşitliğinden cos $kose = ${k1 * k1 + k2 * k2 - y * y}/${2 * k1 * k2} '
          '= $yanit bulunur.',
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
      [
        for (var i = 0; i < 3; i++)
          yaz([for (var j = 0; j < 3; j++) j == i ? !poz[j] : poz[j]]),
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
  (4, 3),
  (6, 8),
  (8, 6),
  (5, 12),
  (12, 5),
  (9, 12),
  (12, 9),
  (8, 15),
  (15, 8),
  (12, 16),
  (16, 12),
  (7, 24),
  (24, 7),
  (15, 20),
  (20, 15),
  (10, 24),
  (24, 10),
  (20, 21),
  (21, 20),
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
  if (c <= 4) {
    final (g, k, fi) = _tersPeriyot[500 * c + a + 25 * b];
    final (fp, fq) = _frekans[fi];
    final frek = _R(fp, fq), ters = _R(fq, fp);
    final maks = k + g, min = k - g;
    final t = _periyot(fp, fq);
    final buyuk = 'en büyük değeri ${_n(maks)}, en küçük değeri ${_n(min)}';
    final pozitif = 'a, b pozitif gerçek sayılardır.';
    final perAc = 'Esas periyot 2π/b = $t olduğundan b = $frek olur.';
    final kYaz = '${k < 0 ? '−' : '+'} ${k.abs()}';
    switch (c) {
      case 0:
        final yanit = _R(g) + frek + _R(k);
        return _ras(
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
      case 1:
        final yanit = _R(k) + _R(g) + frek;
        return _ras(
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
          'Kosinüsün görüntü kümesi [−1, 1] olduğundan b = ($maks − '
              '${_p(min)})/2 = $g ve a = (${_n(maks)} + ${_p(min)})/2 = ${_n(k)} olur. '
              'Esas periyot 2π/c = $t olduğundan c = $frek bulunur. a + b + c = '
              '${_n(k)} + $g + ${_rs(frek)} = $yanit.',
        );
      case 2:
        final yanit = _R(g) * frek;
        return _ras(
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
      case 3:
        final yanit = _R(g) * frek;
        return _ras(
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
      default:
        final yanit = _R(g) * frek * _R(k);
        return _ras(
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
    }
  }
  if (c <= 6) {
    // Açık biçim: en büyük (c = 5) ya da en küçük (c = 6) değer ile esas
    // periyodun çarpımı. Genlik g, kayma k ve frekans hesaba girer; katsayının
    // işareti, fonksiyonun adı ve faz kayması yalnız süstür.
    final maks = c == 5;
    final j = a + 25 * b;
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
    return secenekli(
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
          'T = 2π/${_rs(_R(fp, fq))} = ${_periyot(fp, fq)} bulunur. a·T = '
          '${_p(uc)}·${_sar(_periyot(fp, fq))} = $yanit.',
    );
  }
  // a·sin x + b·cos x + d: genlik √(a² + b²).
  final (p0, q0) = _genlikCifti[b];
  final d = a - 12;
  final sa = (a + b).isEven ? 1 : -1, sb = (a ~/ 2 + b).isEven ? 1 : -1;
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
      return _tam(
        'f(x) = $ifade fonksiyonunun en büyük değeri kaçtır?',
        r + d,
        [pa + qb + d, p0 + q0 + d, p0 * p0 + q0 * q0 + d, r - d],
        '$giris En büyük değer $r ${d < 0 ? '−' : '+'} ${d.abs()} = '
            '${_n(r + d)}.',
      );
    case 8:
      return _tam(
        'f(x) = $ifade fonksiyonunun en küçük değeri kaçtır?',
        d - r,
        [d - p0 - q0, d - (pa + qb).abs(), -r - d.abs(), d - p0 * p0 - q0 * q0],
        '$giris En küçük değer −$r ${d < 0 ? '−' : '+'} ${d.abs()} = '
            '${_n(d - r)}.',
      );
    default:
      final yanit = (r + d) * (d - r);
      return _tam(
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
        ..add((6, u, v, 0));
      for (var t = 0; t < 7; t++) {
        l.add((7, u, v, t));
      }
    }
    for (var t = 0; t < 7; t++) {
      l
        ..add((3, u, 0, t))
        ..add((4, u, 0, t))
        ..add((5, u, 0, t));
    }
  }
  return [for (var i = 0; i < l.length; i++) l[i * 389 % l.length]];
}();

/// Denklem iç ifadeleri (p, q, r): (px + q)/r.
List<(int, int, int)> _icIfadeler(int qSinir, List<int> rler) => [
  for (final r in rler)
    for (var q = 0; q <= qSinir; q++)
      for (final qq in q == 0 ? [0] : [q, -q])
        for (var p = 1; p <= 5; p++)
          if (p.gcd(qq).gcd(r) == 1) (p, qq, r),
];

String _icYaz((int, int, int) ic) {
  final (p, q, r) = ic;
  final lin = _pol([p, q]);
  return r == 1 ? lin : '($lin)/$r';
}

AdvancedItem _tersTrig(int a, int b, int c) {
  final j = a + 25 * b;
  if (c <= 2) {
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
    return secenekli(
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
  if (c == 3) {
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
    return _ras('$dis($icF($v)) ifadesinin değeri kaçtır?', yanit, [
      -yanit,
      dis == 'sin' ? cosT : (dis == 'cos' ? sinT : _R(1) / yanit),
      dis == 'tan' || dis == 'cot' ? -_R(1) / yanit : _R(1) / yanit,
      _R(kar, kom),
      _R(kom, kar),
    ], 'θ = $icF($v) dersek $bilinen ve θ ∈ $aralik olur; $isaretNot.$hesap');
  }
  if (c <= 5) {
    final (sablon, u, v, t) = _tersToplam[j + 500 * (c - 4)];
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
    final degerler = [
      for (final (_, (y, d, _)) in terimler) '$y = ${_pi(d, 12)}',
    ].join(', ');
    return secenekli(
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
  // c = 6..9: ters trigonometrik denklem.
  final String f, ters;
  final List<(String, _R)> acilar; // (açı yazımı, fonksiyon değeri)
  final List<(int, int, int)> icler;
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
      icler = _icIfadeler(7, [1, 2]);
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
      icler = _icIfadeler(9, [1, 2]);
    case 8:
      f = 'tan';
      ters = 'arctan';
      acilar = [('−π/4', _R(-1)), ('π/4', _R(1))];
      icler = _icIfadeler(12, [1, 2, 3]);
    default:
      f = 'sin';
      ters = 'arcsin';
      acilar = [
        ('arccos(√3/2)', _R(1, 2)),
        ('arctan(−√3/3)', _R(-1, 2)),
        ('arccos(0)', _R(1)),
        ('arctan(√3/3)', _R(1, 2)),
      ];
      icler = _icIfadeler(7, [3, 4]);
  }
  final (aciYaz, deger) = acilar[j % acilar.length];
  final ic = icler[j ~/ acilar.length];
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
              } : aciYaz}) = $deger olmalıdır. Buradan '
        '${_pol([p, q])} = ${deger * _R(r)} ve x = $yanit bulunur.',
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

AdvancedItem _logBasamak(int a, int b, int c) {
  if (c <= 3) {
    final t = _basTaban[a];
    final lg = _logBin(t);
    final n = _uygun(
      [for (var x = 11; x <= 160; x++) x],
      b + 20 * c,
      (x) => _basamakKesin(x * lg, _bigUs(t, x)),
    );
    final bin = n * lg;
    final yanit = bin ~/ 1000 + 1;
    return _tam(
      '${t.$1}${_ust(n)} sayısı kaç basamaklıdır? $_logNot',
      yanit,
      [yanit - 1, yanit + 1, (n * lg / 100).round(), n],
      '${_logAcilim(t)} olur. log(${t.$1}${_ust(n)}) = $n·log ${t.$1} = '
          '${tr(bin / 1000, 3)} bulunur. Bu sayı ${bin ~/ 1000} ile '
          '${bin ~/ 1000 + 1} arasında olduğundan ${t.$1}${_ust(n)} sayısı '
          '$yanit basamaklıdır.',
      pozitif: true,
    );
  }
  if (c == 4) {
    // 2 ve 5 kuvvetleri: 10'un kuvveti ayrılır.
    const ikiler = [(2, 1), (4, 2), (8, 3), (16, 4), (32, 5)];
    const besler = [(5, 1), (25, 2), (125, 3)];
    final (t2, i2) = ikiler[a % 5];
    final (t5, i5) = besler[a ~/ 5 % 3];
    final m = 3 + a ~/ 15 * 20 + b; // 3 … 42
    final k = _uygun(
      [for (var x = 2; x <= 60; x++) x],
      c - 4 + (a % 5 + b) % 7,
      (x) => i2 * m != i5 * x,
    );
    final p2 = i2 * m, p5 = i5 * k;
    final ortak = p2 < p5 ? p2 : p5;
    final fark = (p2 - p5).abs();
    final kalanTaban = p2 > p5 ? 2 : 5;
    final kalanBasamak = BigInt.from(kalanTaban).pow(fark).toString().length;
    final yanit = ortak + kalanBasamak;
    final kalanYaz = '$kalanTaban${_ust(fark)}';
    return _tam(
      '$t2${_ust(m)}·$t5${_ust(k)} sayısı kaç basamaklıdır? $_logNot',
      yanit,
      [ortak, p2 + p5, ortak + 1 == yanit ? ortak + 2 : ortak + 1, yanit + 1],
      '$t2${_ust(m)}·$t5${_ust(k)} = 2${_ust(p2)}·5${_ust(p5)} = '
          '10${_ust(ortak)}·$kalanYaz olur. $kalanYaz sayısı $kalanBasamak '
          'basamaklı olduğundan çarpım $ortak + $kalanBasamak = $yanit '
          'basamaklıdır.',
      pozitif: true,
    );
  }
  if (c == 5) {
    // İki tabanın kuvvetlerinin çarpımı.
    final t1 = _basTaban[a];
    final t2 =
        _basTaban[(a + 3 + b) % 25 == a ? (a + 4) % 25 : (a + 3 + b) % 25];
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
    return _tam(
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
  }
  if (c <= 7) {
    // c = 6: en az k basamaklı olması için en küçük n;
    // c = 7: k basamaklı ise n en çok kaç.
    final t = _basTaban[a];
    final lg = _logBin(t);
    final enAz = c == 6;
    final k = _uygun([for (var x = 12; x <= 200; x++) x], b * 3 + a % 3, (x) {
      final sinir = enAz ? x - 1 : x;
      final oran = sinir * 1000 % lg;
      if (oran * 100 < lg || (lg - oran) * 100 < lg) return false;
      final n = enAz ? (sinir * 1000 + lg - 1) ~/ lg : sinir * 1000 ~/ lg;
      final basamak = (BigInt v) => v.toString().length;
      if (enAz) {
        return basamak(_bigUs(t, n)) >= x && basamak(_bigUs(t, n - 1)) < x;
      }
      return basamak(_bigUs(t, n)) == x && basamak(_bigUs(t, n + 1)) > x;
    });
    if (enAz) {
      final sinir = k - 1;
      final n = (sinir * 1000 + lg - 1) ~/ lg;
      return _tam(
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
    }
    final n = k * 1000 ~/ lg;
    return _tam(
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
  }
  // c = 8, 9: üç sayının karşılaştırılması.
  final p = 40 + 2 * a;
  // z = 5^r, x = 2^p ile en az 0,2 farklı logaritma alsın.
  final r = _uygun(
    [for (var x = 18; x <= 75; x++) x],
    (a * 7 + b * 3) % 20,
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
  return _tam(
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
      if (n > 80 || n == kat || n == yuzde.abs()) continue;
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
        if (n == kat || n == t || n > 120) continue;
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
  if (l.length < 500)
    throw StateError('Logaritmalı süre verisi az: ${l.length}');
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
      for (var k = 2; k <= ks; k++) (a, t, k),
];

int _us(int taban, int kuvvet) {
  var r = 1;
  for (var i = 0; i < kuvvet; i++) {
    r *= taban;
  }
  return r;
}

AdvancedItem _logModel(int a, int b, int c) {
  final j = a + 25 * b;
  switch (c) {
    case 0 || 1 || 8:
      final (ca, tt, k) = _katlanma[(j * 7 + 11 * c) % _katlanma.length];
      final t = k * tt;
      final n0 = _susSec(_baslangic, j + c, {t, tt});
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
      final m = _susSec(_kalanKutle, j + c, {t, tt});
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
        final katYaz = x == 2 ? 'iki' : 'üç';
        final oran = y * klg / lg;
        return _tam(
          'Bir bakteri kültüründeki bakteri sayısı her $y saatte bir $katYaz '
              'katına çıkmaktadır. Bakteri sayısının başlangıçtakinin en az $kat '
              'katı olması için en az kaç saat geçmelidir? $_logNot',
          n,
          [n - 1, n + 1, y * ((kat + x - 1) ~/ x), y * kat ~/ x],
          't saat sonra sayı başlangıcın $x^(t/$y) katı olur. $x^(t/$y) ≥ '
              '$kat için (t/$y)·log $x ≥ log $kat, yani t ≥ $y·'
              '${tr(klg / 1000, 3)}/${tr(lg / 1000, 3)} ≈ ${tr(oran, 2)} '
              'olmalıdır; en az $n saat geçmelidir.',
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
      final m = _susSec(_kalanKutle, j + 3, {t, tt});
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
      final n0 = _susSec(_baslangic, j + 2 * c, {t});
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
      return gecis(x) && y != x && y != ic && y != k && y.abs() <= 150;
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

AdvancedItem _parcaliSoru(int a, int b, int c) {
  if (c <= 5) {
    final (al, be) = _parcaDog[a];
    final (mu, nu, ro) = _parcaKare[b];
    final tur = (a + b) % 2;
    if (c <= 2) {
      final k = const [-1, 1, 2][c];
      final f = _Parcali([al, be], [mu, nu, ro], k, tur);
      // Her parçadan bir nokta; sınır noktası hangi parçadaysa ona yazılır.
      final p = tur == 0 ? k - 2 : k, q = tur == 0 ? k : k + 2;
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
    final n0 = _uygun([for (var x = 3; x <= 80; x++) x], a, (x) {
      var y = x, tek = false;
      for (var i = 0; i < derin; i++) {
        if (y.isOdd) tek = true;
        y = f(y);
      }
      return tek && y != x && y != al && y != be && y.abs() <= 999;
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
    int karisik(int n) => n.isOdd ? n ~/ 2 : al * n + be;
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
  final gamma = b % 10 - 5; // −5 … 4
  final s = c == 8 ? 3 + b ~/ 10 : 1 + b ~/ 10; // 3, 4 ya da 1, 2
  final k = c == 8 ? 0 : -2;
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
  final yanit = gecerli.fold(_R(0), (t, e) => t + e);
  final s1 = tur == 0 ? '<' : '≤', s2 = tur == 0 ? '≥' : '>';
  String kokYaz(int r, bool g) =>
      '${_n(r)} ikinci parçanın aralığında${g ? 'dır' : ' değildir'}';
  final kareGecerlik = adaylar[1].$2 == adaylar[2].$2
      ? '$s ve −$s ikinci parçanın aralığında'
            '${adaylar[1].$2 ? 'dır' : ' değildir'}'
      : '${kokYaz(s, adaylar[1].$2)}, ${kokYaz(-s, adaylar[2].$2)}';
  final aciklama =
      '${_pol([al, be], 't')} = $v için t = $dogrusal; bu değer birinci '
      'parçanın aralığında${adaylar[0].$2 ? 'dır' : ' değildir'}. '
      't² ${gamma < 0 ? '−' : '+'} ${gamma.abs()} = $v için t = $s ya da '
      't = −$s; $kareGecerlik';
  return _ras(
    'Gerçek sayılarda tanımlı f fonksiyonu x $s1 ${_n(k)} için '
        'f(x) = ${_pol([al, be])}, x $s2 ${_n(k)} için f(x) = '
        '${_pol([1, 0, gamma])} biçiminde tanımlanıyor. f(t) = ${_n(v)} '
        'eşitliğini sağlayan t değerlerinin toplamı kaçtır?',
    yanit,
    [dogrusal, dogrusal + _R(s), _R(s), yanit + _R(s), yanit - _R(s)],
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

AdvancedItem _grafikDonusum(int a, int b, int c) {
  final p = _sifirsiz(a, 12);
  final q = _sifirsiz(b, 10);
  final h = (1 + (a + 2 * b) % 6) * ((a + b).isEven ? 1 : -1);
  final k = (1 + (2 * a + b) % 7) * ((a ~/ 3 + b).isEven ? 1 : -1);
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
            'x eksenine göre yansıma yapar: (${_n(p + h)}, ${_n(-q)})',
      ),
    };
    final hatalar = switch (c) {
      0 => [_nokta(p - h, q + k), _nokta(p + h, q - k), _nokta(p - h, q - k)],
      1 => [_nokta(p, q + k), _nokta(-p, k - q), _nokta(p, -q - k)],
      2 => [_nokta(p, q + k), _nokta(-p, k - q), _nokta(-p, q - k)],
      _ => [_nokta(p - h, -q), _nokta(p + h, q), _nokta(-p - h, -q)],
    };
    return secenekli(
      'f fonksiyonunun grafiği A${_nokta(p, q)} noktasından geçmektedir. '
          'Buna göre y = $ifade fonksiyonunun grafiği hangi noktadan kesinlikle '
          'geçer?',
      _nokta(x, y),
      [...hatalar, _nokta(y, x), _nokta(x + 1, y), _nokta(x, y + 1)],
      '$adim = ${_nokta(x, y)}.',
    );
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
    return secenekli(
      'y = $ifade fonksiyonunun grafiği B${_nokta(bx, by)} noktasından '
          'geçtiğine göre y = f(x) fonksiyonunun grafiği hangi noktadan '
          'kesinlikle geçer?',
      _nokta(p, q),
      [...hatalar, _nokta(q, p), _nokta(p + 1, q), _nokta(p, q + 1)],
      '$adim. f fonksiyonunun grafiği ${_nokta(p, q)} noktasından geçer.',
    );
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

AdvancedItem _sureklilik(int a, int b, int c) {
  if (c <= 2) {
    final (al, be) = _parcaDog[a];
    final (mu, nu, ro) = _parcaKare[b];
    final k = const [1, 2, -1][c];
    final f = _Parcali([al, be], [mu, nu, ro], k, (a + b) % 2);
    final sol = _deg(f.p1, k), sag = _deg(f.p2, k), fk = f.deger(k);
    final limitler =
        'x değeri ${_n(k)} sayısına soldan yaklaşırken birinci, sağdan '
        'yaklaşırken ikinci kural kullanılır: ${_sagSol(k, false)} = '
        '${_yerine(f.p1, k)} = ${_n(sol)}, ${_sagSol(k, true)} = '
        '${_yerine(f.p2, k)} = ${_n(sag)}.';
    switch (c) {
      case 0:
        return _tam(
          '${f.tanim} Buna göre ${_sagSol(k, false)} + ${_sagSol(k, true)} '
              'toplamı kaçtır?',
          sol + sag,
          [2 * sol, 2 * sag, sol - sag, sag - sol],
          '$limitler Toplam ${_n(sol + sag)} olur.',
        );
      case 1:
        final hangi = f.birinci(k) ? 'birinci' : 'ikinci';
        return _tam(
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
      default:
        return _tam(
          '${f.tanim} Buna göre ${_sagSol(k, true)} − ${_sagSol(k, false)} '
              'farkı kaçtır?',
          sag - sol,
          [sol - sag, sol + sag, sag, -sol],
          '$limitler Fark ${_n(sag)} − ${_p(sol)} = ${_n(sag - sol)} olur.',
        );
    }
  }
  if (c <= 5) {
    // x = k noktasında süreklilik: m·k + β = k² + γk + δ.
    final gamma = const [-3, -2, -1, 1, 2][a % 5];
    final delta = const [-4, -1, 2, 5, 3][a ~/ 5];
    final m = _sifirsiz(b, 10);
    final k = const [2, -1, 3][c - 3];
    final sag = [1, gamma, delta];
    final hedef = _deg(sag, k);
    final be = hedef - m * k;
    final tur = (a + b) % 2;
    final s1 = tur == 0 ? '<' : '≤', s2 = tur == 0 ? '≥' : '>';
    final sol = be == 0 ? 'mx' : 'mx ${be < 0 ? '−' : '+'} ${be.abs()}';
    return _ras(
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
          '${_yerine(sag, k)} = ${_n(hedef)}. Buradan ${_n(k)}m = '
          '${_n(hedef - be)} ve m = ${_n(m)} bulunur.',
    );
  }
  if (c == 6) {
    // Kaldırılabilir süreksizlik: (x − r)(x − s)/(x − r).
    final r = _sifirsiz(a, 12);
    final s = _uygun(_sifirsizAralik(-11, 11), b, (x) => x != r);
    final pay = [1, -(r + s), r * s];
    final yanit = r - s;
    return _tam(
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
  }
  if (c == 7) {
    const kokler = [1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6];
    final r = kokler[a % 12];
    final al = 1 + a ~/ 12;
    final d = _sifirsiz(b, 10);
    final kup = r * r * r;
    final pay = [al, 0, 0, -al * kup];
    final yanit = 3 * al * r * r + d;
    return _tam(
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
  }
  // c = 8, 9: iki kırılma noktası, iki parametre.
  final aa = _sifirsiz(a, 12), bb = _sifirsiz(b, 10);
  final (k1, k2, gamma) = c == 8 ? (-1, 2, 1) : (1, 3, -2);
  final orta = [1, 0, gamma];
  final c1 = _deg(orta, k1) - aa * k1, c3 = _deg(orta, k2) - bb * k2;
  final yanit = c == 8 ? aa + bb : aa * bb;
  // Hatalı çözüm: süreklilik eşitliğinde işaret hatası (a·k1 = c1 − …).
  final aHata = _R(c1 - _deg(orta, k1), k1),
      bHata = _R(c3 - _deg(orta, k2), k2);
  return _ras(
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
}

// ---------------------------------------------------------------------------
// 14 · Zincir kuralı
// ---------------------------------------------------------------------------

/// (p, x₀) çiftleri: 2x₀ + p ve 3x₀² + p sıfır olmaz (türev sıfır çıkmaz).
final List<(int, int)> _zincirCift = [
  for (final x0 in const [1, 2, -1, 3, -2])
    for (final p in const [-3, -2, -1, 1, 2, 3, -4, 4])
      if (2 * x0 + p != 0 && 3 * x0 * x0 + p != 0) (p, x0),
].take(25).toList();

AdvancedItem _zincirKurali(int a, int b, int c) {
  switch (c) {
    case 0 || 1:
      // (αx + β)^n ya da (αx² + β)^n; iç ifadenin değeri u.
      final al = const [2, 3, -1, -2, 4][a % 5];
      final x0 = const [1, 2, -1, 3, -2][a ~/ 5];
      final n = 2 + b ~/ 4;
      final kare = c == 1;
      final icDeg = kare ? al * x0 * x0 : al * x0;
      // İç ifadenin sabit terimi sıfır olmasın: (αx)ⁿ zincir kuralı gerektirmez.
      final u = _uygun(const [-2, -1, 1, 2, 3], b % 4, (x) => x != icDeg);
      final be = u - icDeg;
      final ic = kare ? _pol([al, 0, be]) : _pol([al, be]);
      final icTurev = kare ? 2 * al * x0 : al;
      final yanit = n * _us(u, n - 1) * icTurev;
      return _tam(
        'f(x) = (${ic})${_ust(n)} olduğuna göre f′(${_n(x0)}) değeri kaçtır?',
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
    case 2 || 3:
      // (x² + px + q)^n ya da (x³ + px + q)^n.
      final (p, x0) = _zincirCift[a];
      final n = 2 + b ~/ 4;
      final u = const [-2, -1, 1, 2][b % 4];
      final kup = c == 3;
      final ic0 = kup ? x0 * x0 * x0 + p * x0 : x0 * x0 + p * x0;
      final q = u - ic0;
      final ic = kup ? _pol([1, 0, p, q]) : _pol([1, p, q]);
      final icTurev = kup ? 3 * x0 * x0 + p : 2 * x0 + p;
      final icTurevYaz = kup ? _pol([3, 0, p]) : _pol([2, p]);
      final yanit = n * _us(u, n - 1) * icTurev;
      return _tam(
        'f(x) = (${ic})${_ust(n)} olduğuna göre f′(${_n(x0)}) değeri kaçtır?',
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
    case 4 || 5:
      // h = f∘g; c = 4: f ikinci, g birinci derece; c = 5: f üçüncü, g ikinci
      // derece.
      final x0 = 1 + (a + b) % 3;
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
      final ze = const [1, 2, -1, -2][b % 4];
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
      final s = _sifirsiz(b, 10);
      final t = _sifirsiz((a + 3 * b) % 12, 6);
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
      final al = const [2, 4, 6, -2, 3, 1, -4, 8, 5, -6][a % 10];
      final x0 = const [1, 2, -1][a ~/ 10];
      final s = 1 + b;
      final be = s * s - al * x0;
      final yanit = _R(al, 2 * s);
      return _ras(
        'f(x) = √(${_pol([al, be])}) olduğuna göre f′(${_n(x0)}) değeri '
            'kaçtır?',
        yanit,
        [_R(1, 2 * s), _R(al, s), _R(al * s, 2), _R(al, 2 * s * s)],
        'f(x) = (${_pol([al, be])})^(1/2) olduğundan f′(x) = '
            '$al/(2√(${_pol([al, be])})) olur. x = ${_n(x0)} için kök içi '
            '${s * s} ve kökü $s olduğundan f′(${_n(x0)}) = $al/(2·$s) = '
            '$yanit.',
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
            'f′(${_n(x0)}) = ${_n(x0)}/$s = $yanit.',
      );
  }
}

// ---------------------------------------------------------------------------
// 15 · Konum fonksiyonundan hız ve ivme
// ---------------------------------------------------------------------------

const _konumGiris =
    'Doğrusal bir yolda hareket eden bir cismin t saniyedeki konumu metre '
    'cinsinden';

AdvancedItem _konumHiz(int a, int b, int c) {
  if (c <= 1) {
    final a3 = 1 + a % 2;
    final a2 = const [-6, -4, -3, -1, 2, 3][a ~/ 2 % 6];
    final a1 = _sifirsiz(b, 10);
    final a0 = 2 + (a + b) % 9;
    final x = [a3, a2, a1, a0];
    final t0 = 1 + (a ~/ 12 + b) % 5;
    final v = _turevK(x), ivme = _turevK(v);
    if (c == 0) {
      final yanit = _deg(v, t0);
      return _tam(
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
    }
    final yanit = _deg(ivme, t0);
    return _tam(
      '$_konumGiris x(t) = ${_pol(x, 't')} bağıntısıyla veriliyor. Cismin '
          't = $t0 s anındaki ivmesi kaç m/s² olur?',
      yanit,
      [_deg(v, t0), 6 * a3 * t0, 3 * a3 * t0 + 2 * a2, _deg(ivme, t0) + a1],
      'v(t) = ${_pol(v, 't')} ve ivme a(t) = v′(t) = ${_pol(ivme, 't')} olur. '
          'a($t0) = ${_yerine(ivme, t0)} = ${_n(yanit)} m/s².',
      birim: 'm/s²',
    );
  }
  if (c == 8) {
    // x(t) = −p·t² + q·t + r: en uzak konum (hızın sıfır olduğu an).
    final p = 1 + a % 5;
    final ts = 1 + a ~/ 5 + (b % 4);
    final r = 2 + b;
    final q = 2 * p * ts;
    final x = [-p, q, r];
    final yanit = _deg(x, ts);
    return _tam(
      '$_konumGiris x(t) = ${_pol(x, 't')} bağıntısıyla veriliyor. Cismin '
          'hızının sıfır olduğu anda konumu kaç metredir?',
      yanit,
      [ts, _deg(x, ts + 1), q * ts + r, _deg(x, 2 * ts)],
      'v(t) = ${_pol([-2 * p, q], 't')} = 0 eşitliğinden t = $ts s bulunur. '
          'x($ts) = ${_yerine(x, ts)} = $yanit m.',
      birim: 'm',
      pozitif: true,
    );
  }
  // Hızı t₁ ve t₂ anlarında sıfır olan hareket:
  // x(t) = a₃t³ − (3a₃/2)(t₁ + t₂)t² + 3a₃t₁t₂t + x₀, t₁ + t₂ çift.
  // a → (t₁, t₂ − t₁, |a₃|), b → (a₃ işareti, x₀); hepsi farklıdır.
  final t1 = 1 + a % 5;
  final fark = 2 + 2 * ((a ~/ 5) % 3); // 2, 4, 6
  final t2 = t1 + fark;
  final a3 = (a < 15 ? 1 : 2) * (b < 10 ? 1 : -1);
  final x0 = 3 + b % 10;
  final x = [a3, -3 * a3 * (t1 + t2) ~/ 2, 3 * a3 * t1 * t2, x0];
  final v = _turevK(x), ivme = _turevK(v);
  final pol = _pol(x, 't');
  final vYaz = 'v(t) = ${_pol(v, 't')} = ${_n(3 * a3)}·(t − $t1)·(t − $t2)';
  switch (c) {
    case 2 || 3:
      final ilk = c == 2;
      final yanit = ilk ? t1 : t2;
      return _tam(
        '$_konumGiris x(t) = $pol bağıntısıyla veriliyor. Cismin hızı '
            'kaçıncı saniyede ${ilk ? 'ilk' : 'ikinci'} kez sıfır olur?',
        yanit,
        [ilk ? t2 : t1, t1 + t2, (t1 + t2) ~/ 2, t1 * t2],
        '$vYaz olur. Hız t = $t1 s ve t = $t2 s anlarında sıfırdır; '
            'hız ${ilk ? 'ilk' : 'ikinci'} kez $yanit. saniyede sıfır olur.',
        pozitif: true,
      );
    case 4 || 5:
      final ti = c == 4 ? t1 : t2;
      final yanit = _deg(x, ti);
      return _tam(
        '$_konumGiris x(t) = $pol bağıntısıyla veriliyor. Cismin hızının '
            '${c == 4 ? 'ilk' : 'ikinci'} kez sıfır olduğu anda konumu kaç '
            'metredir?',
        yanit,
        [_deg(x, c == 4 ? t2 : t1), x0, _deg(v, ti) + x0, _deg(x, ti + 1)],
        '$vYaz olur; hız t = $t1 s ve t = $t2 s anlarında sıfırdır. '
            'x($ti) = ${_yerine(x, ti)} = ${_n(yanit)} m.',
        birim: 'm',
      );
    case 6:
      final ts = (t1 + t2) ~/ 2;
      final yanit = _deg(v, ts);
      return _tam(
        '$_konumGiris x(t) = $pol bağıntısıyla veriliyor. Cismin ivmesinin '
            'sıfır olduğu andaki hızı kaç m/s olur?',
        yanit,
        [-yanit, _deg(x, ts), _deg(v, ts + 1), ts],
        'a(t) = ${_pol(ivme, 't')} = 0 eşitliğinden t = $ts s olur. '
            'v(t) = ${_pol(v, 't')} olduğundan v($ts) = ${_yerine(v, ts)} = '
            '${_n(yanit)} m/s.',
        birim: 'm/s',
      );
    case 7:
      // t = 0 ile t = T arasında alınan yol; yön t₁ anında değişir.
      final tSon = t1 + fark ~/ 2;
      final x0d = _deg(x, 0), x1 = _deg(x, t1), xs = _deg(x, tSon);
      final yol = (x1 - x0d).abs() + (xs - x1).abs();
      return _tam(
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
    default:
      final yanit = _deg(ivme, t1);
      return _tam(
        '$_konumGiris x(t) = $pol bağıntısıyla veriliyor. Cismin hızının '
            'ilk kez sıfır olduğu andaki ivmesi kaç m/s² olur?',
        yanit,
        [-yanit, _deg(ivme, t2), _deg(ivme, 0), 0],
        '$vYaz olduğundan hız ilk kez t = $t1 s anında sıfırdır. a(t) = '
            '${_pol(ivme, 't')} olduğundan a($t1) = ${_yerine(ivme, t1)} = '
            '${_n(yanit)} m/s².',
        birim: 'm/s²',
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
    'İki kat açı formülleriyle sin 2x, cos 2x, tan 2x',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) =>
        _ikiKat(_ikiKatHavuz[(a + 25 * b + 500 * c) * 1013 % lmAileBoyu]),
  ),

  // 3 · Trigonometrik denklem: c < 6 → özel değerli sin, cos, tan denklemi
  // (toplam, en küçük ya da en büyük kök); c ≥ 6 → çarpanlarına ayrılan
  // ikinci dereceden denklem (kök sayısı ya da toplamı).
  _aile(
    'trig_denklem',
    'Trigonometrik denklemlerde kök sayısı ve toplamı',
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) => c < 6 ? _trigDenklemOzel(a, b, c) : _trigDenklemKare(a, b, c),
  ),

  // 4 · Sinüs teoremi: c ≤ 1 özel açılar, c ≤ 5 kesirli sinüsler, c ≥ 6
  // çevrel çemberin yarıçapı.
  _aile(
    'sinus_teoremi',
    'Sinüs teoremiyle kenar ve çevrel çember yarıçapı',
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
    _logBasamak,
  ),

  // 10 · Üstel modeller: katlanma ve yarılanma süreleri, logaritmalı süre,
  // açık model ve ters yönde periyot bulma.
  _aile(
    'log_model',
    'Üstel büyüme ve azalma modellerinde süre',
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
    _parcaliSoru,
  ),

  // 12 · Grafik dönüşümleri: c ≤ 3 dönüşen grafiğin noktası, c ≤ 6 ters yön,
  // c ≥ 7 kuralı verilen fonksiyonla dönüşüm.
  _aile(
    'grafik_donusum',
    'Fonksiyon grafiklerinde öteleme ve yansıma',
    Difficulty.medium,
    BloomLevel.anlama,
    _grafikDonusum,
    shortAnswer: false,
  ),

  // 13 · Süreklilik: c ≤ 2 sağdan ve soldan limit, c ≤ 5 parametre, c = 6, 7
  // kaldırılabilir süreksizlik, c = 8, 9 iki parametre.
  _aile(
    'sureklilik',
    'Parçalı fonksiyonda limit ve süreklilik',
    Difficulty.medium,
    BloomLevel.uygulama,
    _sureklilik,
  ),

  // 14 · Zincir kuralı: (ax + b)ⁿ biçimleri, f(g(x)), değerlerle bileşke
  // türevi ve köklü ifadeler.
  _aile(
    'zincir_kurali',
    'Zincir kuralıyla bileşke fonksiyonun türevi',
    Difficulty.medium,
    BloomLevel.uygulama,
    _zincirKurali,
  ),

  // 15 · Konum, hız ve ivme: anlık hız ve ivme, hızın sıfır olduğu anlar,
  // o andaki konum ve ivme, alınan yol.
  _aile(
    'konum_hiz',
    'Konum fonksiyonundan hız ve ivme',
    Difficulty.medium,
    BloomLevel.uygulama,
    _konumHiz,
  ),
  // GEÇİCİ: ara denetimler için yer tutucular; son sürümde yoktur.
  for (var k = 16; k <= 20; k++)
    _aile(
      'gecici_$k',
      'Geçici yer tutucu aile $k',
      Difficulty.easy,
      BloomLevel.uygulama,
      (a, b, c) => _tam(
        'Geçici soru $k: $a + ${10 * b} + ${200 * c} toplamı kaçtır?',
        a + 10 * b + 200 * c,
        [a + 10 * b + 200 * c + 1],
        'Toplama işlemi yapılır.',
      ),
    ),
];
