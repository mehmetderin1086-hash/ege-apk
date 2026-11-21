// AYT Matematik metin aileleri: fonksiyon, polinom, ikinci derece, logaritma,
// dizi, trigonometri, limit, türev, integral ve toplam sembolü.
// Her aile (a, b, c) koordinatlarından 5.000 ayrı soru kökü üretir.
import 'ortak.dart';

// ---------------------------------------------------------------------------
// Yazım yardımcıları
// ---------------------------------------------------------------------------

const _ustRakam = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];
const _altRakam = ['₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉'];

/// Üst simge: `_ust(12)` → `¹²`.
String _ust(int n) => [for (final r in '$n'.codeUnits) _ustRakam[r - 48]].join();

/// Alt simge: `_alt(12)` → `₁₂`.
String _alt(int n) => [for (final r in '$n'.codeUnits) _altRakam[r - 48]].join();

/// İşaretli tam sayı: `_n(-3)` → `−3`.
String _n(int x) => x < 0 ? '−${-x}' : '$x';

/// İşlem içinde negatif sayı paranteze alınır: `_p(-3)` → `(−3)`.
String _p(int x) => x < 0 ? '(−${-x})' : '$x';

/// Sade kesir, eksi işareti tipografik: `_q(-6, 4)` → `−3/2`.
String _q(int n, int d) => kesir(n, d).replaceAll('-', '−');

/// Kesir ya da negatif değer işlem içinde paranteze alınır.
String _sar(String s) => s.contains('/') || s.startsWith('−') ? '($s)' : s;

/// İşlem içinde kesir: `_qp(-3, 2)` → `(−3/2)`, `_qp(4, 2)` → `2`.
String _qp(int n, int d) => _sar(_q(n, d));

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
    final govde = d == 0 ? '$m' : (m == 1 ? us : '$m·$us');
    if (sb.isEmpty) {
      sb.write(c < 0 ? '−$govde' : govde);
    } else {
      sb.write(c < 0 ? ' − $govde' : ' + $govde');
    }
  }
  return sb.isEmpty ? '0' : sb.toString();
}

/// Sıfırı atlayan simetrik aralık: i = 0 … → −alt, …, −1, 1, 2, …
int _sifirsiz(int i, int alt) {
  final x = i - alt;
  return x >= 0 ? x + 1 : x;
}

int _us(int taban, int kuvvet) {
  var r = 1;
  for (var i = 0; i < kuvvet; i++) {
    r *= taban;
  }
  return r;
}

/// Tam sayı yanıtlı soru; eksi işareti tipografik yazılır. Adaylar yetmezse
/// komşu değerlerle tamamlanır.
AdvancedItem _tam(
  String kok,
  int yanit,
  Iterable<int> adaylar,
  String aciklama, {
  String birim = '',
  bool pozitif = false,
}) {
  final adim = yanit.abs() >= 200 ? 10 : (yanit.abs() >= 40 ? 5 : 1);
  final havuz = [
    ...adaylar,
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

/// Kesir yanıtlı soru; adaylar (pay, payda) ikilileridir. Paydası sıfır olan
/// adaylar atılır, eksikler işaret ve komşu değerlerle tamamlanır.
AdvancedItem _kes(
  String kok,
  int n,
  int d,
  Iterable<(int, int)> adaylar,
  String aciklama, {
  bool pozitif = false,
}) {
  final havuz = [
    ...adaylar,
    (-n, d),
    if (n != 0) (d, n),
    (n + d, d),
    (n - d, d),
    (n + 2 * d, d),
    (n + 3 * d, d),
    (n + 4 * d, d),
    (n + 5 * d, d),
  ].where((x) => x.$2 != 0 && (!pozitif || x.$1 * x.$2 > 0));
  return secenekli(
    kok,
    _q(n, d),
    havuz.map((x) => _q(x.$1, x.$2)),
    aciklama,
  );
}

AdvancedFamily _aile(
  String key,
  String title,
  Difficulty difficulty,
  BloomLevel bloom,
  LmUretec build, {
  bool shortAnswer = true,
}) => lmAile(
  'mi_$key',
  title,
  Topic.mathematics,
  difficulty,
  bloom,
  build,
  exam: ExamKind.ayt,
  lesson: 'Matematik',
  shortAnswer: shortAnswer,
);

AdvancedFamily _gecici(int n) => _aile(
  'gecici_$n',
  'Geçici yer tutucu aile $n',
  Difficulty.easy,
  BloomLevel.uygulama,
  (a, b, c) => _tam(
    'Geçici soru $n: ${a + 1} + ${b + 30} + ${c + 60} · 100 işleminin sonucu kaçtır?',
    a + 1 + b + 30 + (c + 60) * 100,
    const [],
    'Geçici açıklama metni.',
  ),
);

// ---------------------------------------------------------------------------
// Aileler
// ---------------------------------------------------------------------------

final lmMatIleri = <AdvancedFamily>[
  // 1 · Bileşke fonksiyon: a → f, b → g, c → nokta ve bileşke sırası.
  _aile(
    'fonksiyon_bileske',
    'Bileşke fonksiyonun bir noktadaki değeri',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final f = [const [2, 3, -2, 4, -3][a % 5], const [-3, -1, 1, 2, 4][a ~/ 5]];
      final g = [1, const [-2, -1, 1, 2, 3][b % 5], const [-1, 1, 2, 3][b ~/ 5]];
      final k = const [-2, -1, 1, 2, 3][c ~/ 2];
      final fog = c.isEven;
      final fk = _deg(f, k), gk = _deg(g, k);
      final fgk = _deg(f, gk), gfk = _deg(g, fk);
      final kok =
          'Gerçek sayılarda tanımlı f(x) = ${_pol(f)} ve g(x) = ${_pol(g)} '
          'fonksiyonları veriliyor. Buna göre '
          '${fog ? '(f∘g)' : '(g∘f)'}(${_n(k)}) değeri kaçtır?';
      if (fog) {
        return _tam(
          kok,
          fgk,
          [gfk, fk * gk, fk + gk, gk],
          '(f∘g)(${_n(k)}) = f(g(${_n(k)})) olur. Önce g(${_n(k)}) = '
          '${_yerine(g, k)} = ${_n(gk)}, sonra f(${_n(gk)}) = '
          '${_yerine(f, gk)} = ${_n(fgk)} bulunur.',
        );
      }
      return _tam(
        kok,
        gfk,
        [fgk, fk * gk, fk + gk, fk],
        '(g∘f)(${_n(k)}) = g(f(${_n(k)})) olur. Önce f(${_n(k)}) = '
        '${_yerine(f, k)} = ${_n(fk)}, sonra g(${_n(fk)}) = '
        '${_yerine(g, fk)} = ${_n(gfk)} bulunur.',
      );
    },
  ),

  // 2 · Ters fonksiyon: c çift → doğrusal, c tek → (px + q)/(x − d).
  _aile(
    'ters_fonksiyon',
    'Ters fonksiyonun bir noktadaki değeri',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final v = c ~/ 2;
      if (c.isEven) {
        final p = const [2, 3, 4, 5, 7][a % 5];
        final q = _sifirsiz(5 * (a ~/ 5) + v, 12);
        final t = _sifirsiz(b, 9);
        final k = p * t + q;
        return _kes(
          'Gerçek sayılarda tanımlı f(x) = ${_pol([p, q])} fonksiyonunun tersi '
          'f⁻¹ olduğuna göre f⁻¹(${_n(k)}) değeri kaçtır?',
          t,
          1,
          [(k + q, p), (k - q, 1), (p * k + q, 1)],
          'f⁻¹(${_n(k)}) = t ise f(t) = ${_n(k)} olur. ${_pol([p, q], 't')} = '
          '${_n(k)} eşitliğinden ${p}t = ${_n(k - q)} ve t = ${_n(t)} bulunur.',
        );
      }
      final p = const [2, 3, 4, 5, -2][a % 5];
      final d = const [1, 2, 3, -1, -2][a ~/ 5];
      final j = const [-2, -1, 1, 2, 3][v];
      final u = _sifirsiz(b, 10);
      final q = j * u - p * d, k = p + j, t = d + u;
      String pay(String h) => q == 0 ? _pol([p, 0], h) : '(${_pol([p, q], h)})';
      return _kes(
        'x ≠ ${_n(d)} için tanımlı f(x) = ${pay('x')}/(${_pol([1, -d])}) '
        'fonksiyonunun tersi f⁻¹ olduğuna göre f⁻¹(${_n(k)}) değeri kaçtır?',
        t,
        1,
        [
          if (k != d) (p * k + q, k - d),
          (k * d - q, k - p),
          (-t, 1),
        ],
        'f⁻¹(${_n(k)}) = t ise f(t) = ${_n(k)} olur. '
        '${pay('t')}/(${_pol([1, -d], 't')}) = ${_n(k)} eşitliğinden '
        '${_pol([p, q], 't')} = ${_pol([k, -k * d], 't')} ve t = ${_n(t)} '
        'bulunur.',
      );
    },
  ),

  // 3 · Polinom: c % 3 → katsayılar toplamı, sabit terim ya da derece.
  _aile(
    'polinom_deger',
    'Polinomda katsayılar toplamı, sabit terim ve derece',
    Difficulty.medium,
    BloomLevel.anlama,
    (a, b, c) {
      final v = c ~/ 3;
      if (c % 3 == 2) {
        final p = 2 + a % 5, q = 2 + a ~/ 5, r = 1 + b % 5, s = 2 + b ~/ 5;
        final f1 = List.filled(p + 1, 0)
          ..[0] = 1
          ..[p - 1] = 2;
        final f2 = List.filled(r + 1, 0)
          ..[0] = 3
          ..[r] = -1;
        final ifade = '(${_pol(f1)})${_ust(q)}·(${_pol(f2)})${_ust(s)}';
        final t = p + q + r + s, d = p * q + r * s;
        final buyuk = p * q > r * s ? p * q : r * s;
        final temel =
            'Bir çarpımın derecesi, çarpanların dereceleri toplamıdır: '
            '$p·$q + $r·$s = $d.';
        return switch (v) {
          0 => _tam(
            'P(x) = $ifade polinomunun derecesi kaçtır?',
            d,
            [buyuk, t, p + r],
            temel,
            pozitif: true,
          ),
          1 => _tam(
            'P(x) = $ifade olduğuna göre P(x²) polinomunun derecesi kaçtır?',
            2 * d,
            [d, d + 2, 2 * t],
            '$temel x yerine x² yazılınca derece iki katına çıkar: 2·$d = '
            '${2 * d}.',
            pozitif: true,
          ),
          _ => _tam(
            'P(x) = $ifade olduğuna göre x³·P(x) polinomunun derecesi kaçtır?',
            d + 3,
            [3 * d, d, t + 3],
            '$temel x³ ile çarpılınca derece 3 artar: $d + 3 = ${d + 3}.',
            pozitif: true,
          ),
        };
      }
      final u = _sifirsiz(a, 12), w = _sifirsiz(b, 9);
      final sag = [1, u, w];
      if (c % 3 == 0) {
        final m = const [1, 2, 3, -2][v];
        final x0 = 1 + m;
        return _tam(
          'P(${_pol([1, -m])}) = ${_pol(sag)} olduğuna göre P(x) polinomunun '
          'katsayılar toplamı kaçtır?',
          _deg(sag, x0),
          [_deg(sag, 1), _deg(sag, m), _deg(sag, 1 - m)],
          'Katsayılar toplamı P(1) değeridir. ${_pol([1, -m])} = 1 için '
          'x = ${_n(x0)} alınır: P(1) = ${_yerine(sag, x0)} = '
          '${_n(_deg(sag, x0))}.',
        );
      }
      final (kat, kay) = const [(2, -4), (3, 3), (2, 6)][v];
      final x0 = -kay ~/ kat;
      return _tam(
        'P(${_pol([kat, kay])}) = ${_pol(sag)} olduğuna göre P(x) polinomunun '
        'sabit terimi kaçtır?',
        _deg(sag, x0),
        [w, _deg(sag, -x0), _deg(sag, 1)],
        'Sabit terim P(0) değeridir. ${_pol([kat, kay])} = 0 için '
        'x = ${_n(x0)} alınır: P(0) = ${_yerine(sag, x0)} = '
        '${_n(_deg(sag, x0))}.',
      );
    },
  ),

  // 4 · Kalan teoremi: c çift → P(k), c tek → kaydırılmış P(x + m).
  _aile(
    'kalan',
    'Kalan teoremi ile bölümden kalanı bulma',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final w = _sifirsiz(b, 9);
      if (c.isEven) {
        final k = const [2, -1, 3, -2, 1][c ~/ 2];
        final pol = [
          1,
          const [-3, -2, 1, 2, 4][a % 5],
          const [-4, -1, 2, 3, 5][a ~/ 5],
          w,
        ];
        final kalan = _deg(pol, k);
        return _tam(
          'P(x) = ${_pol(pol)} polinomunun ${_pol([1, -k])} ile bölümünden '
          'kalan kaçtır?',
          kalan,
          [_deg(pol, -k), w, kalan - w],
          'Kalan teoremine göre kalan P(${_n(k)}) değeridir: '
          'P(${_n(k)}) = ${_yerine(pol, k)} = ${_n(kalan)}.',
        );
      }
      final (m, k) = const [(2, 1), (3, -1), (-1, 3), (-2, -2), (1, 2)][c ~/ 2];
      final pol = [1, _sifirsiz(a, 12), w];
      final x0 = k + m, kalan = _deg(pol, x0);
      return _tam(
        'P(x) = ${_pol(pol)} polinomu veriliyor. P(${_pol([1, m])}) '
        'polinomunun ${_pol([1, -k])} ile bölümünden kalan kaçtır?',
        kalan,
        [_deg(pol, k), _deg(pol, k - m), _deg(pol, m)],
        'Q(x) = P(${_pol([1, m])}) polinomunun ${_pol([1, -k])} ile '
        'bölümünden kalan Q(${_n(k)}) = P(${_n(x0)}) değeridir: '
        'P(${_n(x0)}) = ${_yerine(pol, x0)} = ${_n(kalan)}.',
      );
    },
  ),

  // 5 · Vieta: a → b katsayısı, b → sabit terim, c → ifade ve baş katsayı.
  _aile(
    'vieta',
    'Kökler toplamı ve çarpımıyla simetrik ifadeler',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final e = c % 5, bas = 1 + c ~/ 5;
      final kb = _sifirsiz(a, 12);
      var kc = _sifirsiz(b, 14);
      // Kökler gerçek kalsın: diskriminant pozitif değilse sabit terim
      // negatif bir değere taşınır.
      if (kc > 0 && kb * kb <= 4 * bas * kc) kc = -(14 + kc);
      final top = _q(-kb, bas), carp = _q(kc, bas);
      final giris =
          'Kökler toplamı x₁ + x₂ = $top, kökler çarpımı x₁·x₂ = $carp olur.';
      final denklem = '${_pol([bas, kb, kc])} = 0';
      String kok(String ifade) =>
          '$denklem denkleminin kökleri x₁ ve x₂ olduğuna göre $ifade '
          'ifadesinin değeri kaçtır?';
      final b2 = kb * kb, a2 = bas * bas, ac = bas * kc;
      switch (e) {
        case 0:
          return _kes(
            kok('x₁² + x₂²'),
            b2 - 2 * ac,
            a2,
            [(b2 + 2 * ac, a2), (b2, a2), (b2 - 2 * kc, 1), (b2 - ac, a2)],
            '$giris x₁² + x₂² = (x₁ + x₂)² − 2·x₁·x₂ = ${_sar(top)}² − '
            '2·${_sar(carp)} = ${_q(b2 - 2 * ac, a2)}.',
          );
        case 1:
          return _kes(
            kok('1/x₁ + 1/x₂'),
            -kb,
            kc,
            [(kb, kc), (-kc, kb), (kc, kb)],
            '$giris 1/x₁ + 1/x₂ = (x₁ + x₂)/(x₁·x₂) = ${_sar(top)}/'
            '${_sar(carp)} = ${_q(-kb, kc)}.',
          );
        case 2:
          return _kes(
            kok('(x₁ − x₂)²'),
            b2 - 4 * ac,
            a2,
            [(b2 - 2 * ac, a2), (b2 + 4 * ac, a2), (b2, a2)],
            '$giris (x₁ − x₂)² = (x₁ + x₂)² − 4·x₁·x₂ = ${_sar(top)}² − '
            '4·${_sar(carp)} = ${_q(b2 - 4 * ac, a2)}.',
          );
        case 3:
          return _kes(
            kok('x₁²·x₂ + x₁·x₂²'),
            -kb * kc,
            a2,
            [(kb * kc, a2), (kc - kb, bas), (-kb * kc, bas), (kb + kc, bas)],
            '$giris x₁²·x₂ + x₁·x₂² = x₁·x₂·(x₁ + x₂) = ${_sar(carp)}·'
            '${_sar(top)} = ${_q(-kb * kc, a2)}.',
          );
        default:
          return _kes(
            kok('x₁/x₂ + x₂/x₁'),
            b2 - 2 * ac,
            ac,
            [(b2, ac), (b2 + 2 * ac, ac), (-kb, kc)],
            '$giris x₁/x₂ + x₂/x₁ = (x₁² + x₂²)/(x₁·x₂) = '
            '[${_sar(top)}² − 2·${_sar(carp)}]/${_sar(carp)} = '
            '${_q(b2 - 2 * ac, ac)}.',
          );
      }
    },
  ),

  for (var n = 6; n <= 20; n++) _gecici(n),
];
