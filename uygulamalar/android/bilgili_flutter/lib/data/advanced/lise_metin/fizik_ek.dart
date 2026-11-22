// Lise fizik · ek kazanımlar: vektörler, sürtünme, çarpışmalar, dönme,
// modern fizik, elektromanyetizma, dalgalar ve renk. Her aile 5.000 ayrı
// metin sorusu üretir; kökteki veriler a, b ve c ile birebir belirlenir.
import 'dart:math' as math;

import 'ortak.dart';

const _fizik = 'Fizik';
const _g10 = '(g = 10 m/s² alınız.)';

// ───────────────────────────── Ortak yardımcılar ─────────────────────────────

/// Sayıyı virgüllü ve gerçek eksi işaretiyle yazar.
String _n(num x, [int d = 2]) => tr(x, d).replaceFirst('-', '−');

/// İki ondalığa yuvarlar.
double _iki(num x) => (x * 100).roundToDouble() / 100;

/// Sayısal yanıtlı soru. Anahtar iki ondalıkta kesin olmalıdır. [hatalar]
/// tipik hatalardan gelen sayılar ya da hazır yazılmış seçeneklerdir
/// (ör. `12√3 N`); yetmezse anahtarın komşu değerleriyle tamamlanır.
AdvancedItem _s(
  String kok,
  num dogru,
  Iterable<Object?> hatalar,
  String aciklama, {
  String unit = '',
  bool pozitif = true,
}) {
  final k = _iki(dogru);
  if ((dogru - k).abs() > 1e-7) {
    throw StateError('Kesin olmayan anahtar $dogru: $kok');
  }
  if (pozitif && k <= 0) throw StateError('Pozitif olmayan anahtar $k: $kok');
  final tam = k == k.roundToDouble();
  final num adim = tam
      ? (k.abs() >= 200 ? 10 : (k.abs() >= 40 ? 5 : 1))
      : (k.abs() >= 20 ? 1 : (k.abs() >= 2 ? 0.5 : 0.1));
  String yaz(num x) => birimli(_n(x), unit);
  final adaylar = <String>[
    for (final h in hatalar)
      if (h is String)
        h
      else if (h is num && h.isFinite && (!pozitif || _iki(h) > 0))
        yaz(_iki(h)),
    for (final m in const [1, -1, 2, -2, 3, 4, 5, 6])
      if (!pozitif || k + m * adim > 0) yaz(_iki(k + m * adim)),
  ];
  return secenekli(kok, yaz(k), adaylar, aciklama);
}

/// Tam kare ise karekökü, değilse null.
int? _tamKok(int x) {
  if (x < 0) return null;
  final r = math.sqrt(x).round();
  return r * r == x ? r : null;
}

/// [n] numaralı (1'den başlayan) ve [yasak] içinde olmayan pozitif tam sayı.
int _atla(int n, Set<int> yasak) {
  var x = 0;
  for (var say = 0; say < n;) {
    x++;
    if (!yasak.contains(x)) say++;
  }
  return x;
}

/// Listenin [n] numaralı ögesini, [adet] sıra numarasını listenin tamamına
/// eşit aralıkla yayarak seçer (liste en az [adet] uzunlukta olmalıdır).
T _yay<T>(List<T> liste, int n, int adet) {
  if (liste.length < adet) {
    throw StateError('Yetersiz tablo: ${liste.length} < $adet');
  }
  return liste[n * liste.length ~/ adet];
}

/// [x] değeri [sayilar] içinde mi (sayısal eşitlik).
bool _icinde(num x, Iterable<num> sayilar) =>
    sayilar.any((y) => (x - y).abs() < 1e-9);

/// Aynı anahtarı taşıyan ögelerden yalnız ilkini tutar. Anahtar, sonucu
/// belirleyen sadeleşmiş oranlardır: bütün kütleler (ya da uzaklıklar) aynı
/// katla büyütüldüğünde hesap değişmediğinden bu ikizler ayrı vaka sayılmaz.
List<T> _tekil<T>(Iterable<T> ogeler, Object Function(T) anahtar) {
  final gorulen = <Object>{};
  return [
    for (final x in ogeler)
      if (gorulen.add(anahtar(x))) x,
  ];
}

/// Sadeleşmiş p : q oranı.
(int, int) _oran(int p, int q) {
  final g = p.gcd(q);
  return (p ~/ g, q ~/ g);
}

/// k√3 yazımı; k = 1 için yalnız √3.
String _k3(num k) => k == 1 ? '√3' : '${_n(k)}√3';

/// Cümle başı için ilk harfi büyütür (adlar ASCII harfle başlar).
String _bas(String s) => '${s[0].toUpperCase()}${s.substring(1)}';

// ─────────────────────── 1 · İki kuvvetin bileşkesi ────────────────────────

/// R² = F₁² + F₂² + 2·F₁·F₂·cos θ bağıntısıyla bileşkesi tam sayı çıkan
/// (F₁, F₂, R) üçlüleri; F₁ < F₂, önce bileşkeye sonra F₁ değerine göre
/// sıralı. Bileşkesi kökte yazılan açı değerine eşit olan üçlüler alınmaz.
List<(int, int, int)> _tamBileske(int aci) {
  final liste = <(int, int, int)>[];
  for (var r = 2; liste.length < 400; r++) {
    if (r == aci) continue;
    for (var f1 = 1; f1 < r && liste.length < 400; f1++) {
      int? f2;
      if (aci == 90) {
        f2 = _tamKok(r * r - f1 * f1);
      } else {
        final k = _tamKok(4 * r * r - 3 * f1 * f1);
        final pay = k == null ? 0 : (aci == 60 ? k - f1 : k + f1);
        if (pay > 0 && pay.isEven) f2 = pay ~/ 2;
      }
      if (f2 != null && f2 > f1) liste.add((f1, f2, r));
    }
  }
  return liste;
}

final _bileske = {
  for (final aci in const [90, 60, 120]) aci: _tamBileske(aci),
};

String _cosNot(int aci) => switch (aci) {
  60 => ' (cos 60° = 1/2)',
  120 => ' (cos 120° = −1/2)',
  _ => '',
};

/// Aynı kuvvetlerle öteki açılarda tam sayı çıkan bileşkeler (yanlış açı
/// bağıntısını kullanan öğrencinin bulduğu değerler).
Iterable<int> _digerAci(int aci, int f1, int f2) sync* {
  for (final (d, kat) in const [(90, 0), (60, 1), (120, -1)]) {
    if (d == aci) continue;
    final r = _tamKok(f1 * f1 + f2 * f2 + kat * f1 * f2);
    if (r != null) yield r;
  }
}

String _bileskeCozum(int aci, int x, int y, int r) => aci == 90
    ? 'Kuvvetler birbirine dik olduğundan R = √(F₁² + F₂²) = '
          '√(${x * x} + ${y * y}) = √${r * r} = $r N olur.'
    : 'R² = F₁² + F₂² + 2·F₁·F₂·cos $aci° = ${x * x} + ${y * y} '
          '${aci == 60 ? '+' : '−'} ${x * y} = ${r * r} olduğundan R = $r N '
          'bulunur.';

final _f01 = lmAile(
  'fz_vektor',
  'İki kuvvetin bileşkesi ve bileşkenin değer aralığı',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 1) {
      // F₁ ve bileşke biliniyor; F₂ = R − F₁ farkının sınırları. F₁ tek, R
      // dördün katı olduğundan R = F₁, R = 2·F₁ ve F₁ = 2·R olamaz: sınır
      // değeri sıfır ya da kökteki bir sayı çıkmaz.
      final f1 = 2 * a + 3; // 3 … 51 N
      final r = 4 * (1 + b ~/ 2 + 10 * k); // 4 … 120 N
      final enAz = b.isEven;
      final mn = (r - f1).abs(), mx = r + f1;
      return _s(
        'Aynı noktaya etki eden F₁ ve F₂ kuvvetlerinden F₁ kuvvetinin '
            'büyüklüğü $f1 N, bileşke kuvvetin büyüklüğü $r N olarak ölçülüyor. '
            'Kuvvetler arasındaki açı bilinmediğine göre F₂ kuvvetinin büyüklüğü '
            'en ${enAz ? 'az' : 'çok'} kaç N olabilir?',
        enAz ? mn : mx,
        enAz ? [mx, r, f1] : [mn, r, f1],
        'F₂ = R − F₁ olduğundan F₂, bileşke ile F₁ aynı yönlüyken en küçük, '
            'zıt yönlüyken en büyük olur: |$r − $f1| ≤ F₂ ≤ $r + $f1, yani '
            '$mn N ≤ F₂ ≤ $mx N. F₂ en ${enAz ? 'az $mn' : 'çok $mx'} N olabilir.',
        unit: 'N',
      );
    }
    final q = b ~/ 5; // 0 … 3
    if (c % 3 == 0) {
      final t = b % 5;
      if (t < 2) {
        final s = 2 + q + 4 * k; // 2 … 17 N
        // Zıt yönde bileşke küçük kuvvete eşit olmasın.
        final g = s + 1 + a == 2 * s ? s + 26 : s + 1 + a;
        final (x, y) = (a + b).isEven ? (g, s) : (s, g);
        final ayni = t == 0;
        final r = ayni ? g + s : g - s;
        return _s(
          'Bir noktasal cisme aynı doğrultuda '
          '${ayni ? 've aynı yönde' : 'fakat zıt yönlerde'}, büyüklükleri '
          'F₁ = $x N ve F₂ = $y N olan iki kuvvet etki ediyor. Bu iki '
          'kuvvetin bileşkesinin büyüklüğü kaç N olur?',
          r,
          ayni ? [g - s, g, s] : [g + s, g, s],
          ayni
              ? 'Aynı yönlü kuvvetlerin bileşkesi büyüklüklerin toplamına '
                    'eşittir: R = $x + $y = $r N.'
              : 'Zıt yönlü kuvvetlerin bileşkesi büyük kuvvetin yönündedir ve '
                    'büyüklüğü farka eşittir: R = $g − $s = $r N.',
          unit: 'N',
        );
      }
      final aci = const [90, 60, 120][t - 2];
      final (f1, f2, r) = _bileske[aci]![a + 25 * q + 100 * k]; // 0 … 399
      final (x, y) = (a + b).isEven ? (f1, f2) : (f2, f1);
      return _s(
        'Bir noktasal cisme aynı düzlemde etki eden ve aralarındaki açı '
        '$aci° olan iki kuvvetin büyüklükleri F₁ = $x N ve F₂ = $y N olarak '
        'veriliyor. Bileşke kuvvetin büyüklüğü kaç N olur?${_cosNot(aci)}',
        r,
        [f1 + f2, f2 - f1, ..._digerAci(aci, f1, f2)],
        _bileskeCozum(aci, x, y, r),
        unit: 'N',
      );
    }
    // En büyük ve en küçük bileşkeden kuvvetler ve belirli açıdaki bileşke.
    final v = b % 5;
    if (v < 2) {
      final s = 2 + q + 4 * k; // 2 … 13 N
      // Küçük kuvvet en küçük bileşkeye eşit olmasın.
      final g = s + 1 + a == 2 * s ? s + 26 : s + 1 + a;
      final x = g + s, y = g - s;
      final buyuk = v == 0;
      return _s(
        'Aynı noktaya etki eden iki kuvvetin bileşkesinin alabileceği en büyük '
            'değer $x N, en küçük değer $y N olarak veriliyor. Bu kuvvetlerden '
            '${buyuk ? 'büyük' : 'küçük'} olanının büyüklüğü kaç N olur?',
        buyuk ? g : s,
        buyuk ? [s, x - y, x + y] : [g, x - y, y],
        'Bileşke, kuvvetler aynı yönlüyken en büyük, zıt yönlüyken en küçük '
            'olur: F₁ + F₂ = $x ve F₁ − F₂ = $y. Denklemler toplanırsa büyük kuvvet '
            '($x + $y) / 2 = $g N, çıkarılırsa küçük kuvvet ($x − $y) / 2 = $s N '
            'bulunur.',
        unit: 'N',
      );
    }
    final aci = const [90, 60, 120][v - 2];
    final (f1, f2, r) = _bileske[aci]![a + 25 * q + 100 * k]; // 0 … 299
    final x = f1 + f2, y = f2 - f1;
    return _s(
      'Aynı noktaya etki eden iki kuvvetin bileşkesinin alabileceği en büyük '
          'değer $x N, en küçük değer $y N olarak veriliyor. Bu iki kuvvet '
          'aralarındaki açı $aci° olacak biçimde uygulanırsa bileşke kuvvetin '
          'büyüklüğü kaç N olur?${_cosNot(aci)}',
      r,
      [f2, f1, if (aci == 90) '$r√2 N', ..._digerAci(aci, f1, f2)],
      'Aynı yönlüyken F₁ + F₂ = $x, zıt yönlüyken F₂ − F₁ = $y olduğundan '
          'F₂ = $f2 N ve F₁ = $f1 N bulunur. ${_bileskeCozum(aci, f1, f2, r)}',
      unit: 'N',
    );
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ──────────────────── 2 · Üç kuvvetin dengesi: ip gerilmeleri ────────────────

const _sc3753 = 'sin 37° = cos 53° = 0,6; sin 53° = cos 37° = 0,8';
const _sc3060 = 'sin 30° = cos 60° = 1/2; sin 60° = cos 30° = √3/2';
const _sc = {
  37: 'sin 37° = 0,6; cos 37° = 0,8',
  53: 'sin 53° = 0,8; cos 53° = 0,6',
  30: 'sin 30° = 1/2; cos 30° = √3/2',
  60: 'sin 60° = √3/2; cos 60° = 1/2',
};

/// Asılı cismin ağırlığıyla tutarlı bir ad.
String _asili(num w, int i) {
  final adlar = w <= 25
      ? const ['bir süs lambası', 'küçük bir saksı']
      : w <= 120
      ? const ['bir avize', 'bir saksı']
      : w <= 400
      ? const ['bir tabela', 'bir trafik lambası']
      : const ['bir yük kasası', 'bir beton blok'];
  return adlar[i % 2];
}

const _ikiIpler =
    'ağırlığı önemsiz iki iple tavana asılarak dengede tutuluyor.';
const _t3753 =
    'Tavanla 37° açı yapan ipteki gerilme T₁, 53° açı yapan ipteki gerilme T₂ '
    'olsun.';
const _t3060 =
    'Tavanla 30° açı yapan ipteki gerilme T₁, 60° açı yapan ipteki gerilme T₂ '
    'olsun.';

String _ipAcilari(int x, int y) => x == y
    ? 'İplerin her biri tavanla $x° açı yapmaktadır.'
    : 'İplerden biri tavanla $x°, diğeri $y° açı yapmaktadır.';

/// Tavana bağlı iki iple asılı cisim.
AdvancedItem _ikiIp(int a, int b, int k) {
  final v = b % 10;
  final n = 1 + a + 25 * (b ~/ 10) + 50 * k; // 1 … 200
  String ad(num w) => _asili(w, a + b);
  String agirlikli(num w, String yazi) =>
      'Ağırlığı $yazi N olan ${ad(w)}, $_ikiIpler';
  String yalniz(num w) => '${_bas(ad(w))}, $_ikiIpler';
  switch (v) {
    case 0 || 1:
      final w = 5 * n, t1 = 3 * n, t2 = 4 * n;
      final ilk = v == 0;
      return _s(
        '${agirlikli(w, '$w')} ${_ipAcilari(37, 53)} Tavanla ${ilk ? 37 : 53}° '
            'açı yapan ipteki gerilme kuvveti kaç N olur? ($_sc3753)',
        ilk ? t1 : t2,
        ilk ? [t2, 2.5 * n, w] : [t1, 2.5 * n, w],
        '$_t3753 Yatay denge T₁·0,8 = T₂·0,6, düşey denge T₁·0,6 + T₂·0,8 = '
            '$w verir. Bu denklemlerden T₁ = $w·0,6 = $t1 N ve T₂ = $w·0,8 = $t2 N '
            'bulunur.',
        unit: 'N',
      );
    case 2:
      // 30° ipteki gerilme her zaman G/2 çıktığından (ağırlığı iplere eşit
      // bölen öğrenci de doğruyu bulurdu) 30°–60° düzeninde 60° ipi sorulur.
      final m = _atla(n, const {15, 30});
      final w = 2 * m;
      return _s(
        '${yalniz(w)} ${_ipAcilari(30, 60)} Tavanla 60° açı yapan ipteki '
            'gerilme kuvveti ${_k3(m)} N olarak ölçüldüğüne göre cismin ağırlığı '
            'kaç N olur? ($_sc3060)',
        w,
        ['${_k3(w)} N', 1.5 * m, 3 * m],
        '$_t3060 Yatay denge T₁·cos 30° = T₂·cos 60°, düşey denge '
            'T₁·sin 30° + T₂·sin 60° = G verir. İpler birbirine dik olduğundan bu '
            'denklemlerden T₂ = G·sin 60° bulunur: G = ${_k3(m)} / (√3/2) = $w N.',
        unit: 'N',
      );
    case 3:
      final m = _atla(n, const {10, 20});
      return _s(
        '${agirlikli(2 * m * 1.732, _k3(2 * m))} ${_ipAcilari(30, 60)} Tavanla '
            '60° açı yapan ipteki gerilme kuvveti kaç N olur? ($_sc3060)',
        3 * m,
        ['${_k3(m)} N', 4 * m, '${_k3(2 * m)} N'],
        '$_t3060 Yatay denge T₁·cos 30° = T₂·cos 60°, düşey denge '
            'T₁·sin 30° + T₂·sin 60° = G verir. İpler birbirine dik olduğundan bu '
            'denklemlerden T₂ = G·sin 60° bulunur: T₂ = ${_k3(2 * m)}·√3/2 = '
            '${3 * m} N.',
        unit: 'N',
      );
    case 4 || 5:
      final aci = v == 4 ? 37 : 53;
      final w = v == 4 ? 6 * n : 8 * n, t = 5 * n;
      final sinus = v == 4 ? '0,6' : '0,8';
      return _s(
        '${agirlikli(w, '$w')} ${_ipAcilari(aci, aci)} İplerden birindeki '
            'gerilme kuvveti kaç N olur? (${_sc[aci]})',
        t,
        v == 4 ? [3 * n, 3.75 * n, 10 * n] : [4 * n, 10 * n, 3.2 * n],
        'Simetrik iplerdeki gerilmeler eşittir ve yatay bileşenler birbirini '
            'dengeler. Düşey denge 2·T·sin $aci° = G verir: T = $w / (2·$sinus) = '
            '$t N.',
        unit: 'N',
      );
    case 6 || 7:
      final w = 5 * n, t1 = 3 * n, t2 = 4 * n;
      final agirlik = v == 6;
      return _s(
        '${yalniz(w)} ${_ipAcilari(37, 53)} Tavanla 53° açı yapan ipteki '
        'gerilme kuvveti $t2 N olarak ölçüldüğüne göre '
        '${agirlik ? 'cismin ağırlığı' : 'tavanla 37° açı yapan ipteki gerilme kuvveti'} '
        'kaç N olur? ($_sc3753)',
        agirlik ? w : t1,
        agirlik ? [7 * n, 3.2 * n, 8 * n] : [t2, 2.4 * n, 3.2 * n],
        agirlik
            ? '$_t3753 Yatay denge T₁·0,8 = T₂·0,6 eşitliğinden T₁ = '
                  '$t2·0,6 / 0,8 = $t1 N olur. Düşey denge G = T₁·0,6 + '
                  'T₂·0,8 = ${_n(1.8 * n)} + ${_n(3.2 * n)} = $w N verir.'
            : '$_t3753 Yatay bileşenler birbirini dengelediğinden '
                  'T₁·cos 37° = T₂·cos 53° olur: T₁·0,8 = $t2·0,6, T₁ = $t1 N.',
        unit: 'N',
      );
    case 8:
      final w = 8 * n, t = 5 * n;
      return _s(
        '${yalniz(w)} ${_ipAcilari(53, 53)} İplerden birindeki gerilme kuvveti '
            '$t N olarak ölçüldüğüne göre cismin ağırlığı kaç N olur? '
            '(${_sc[53]})',
        w,
        [10 * n, 4 * n, 6 * n],
        'Simetrik iplerdeki gerilmeler eşittir ve yatay bileşenler birbirini '
            'dengeler. Düşey denge G = 2·T·sin 53° = 2·$t·0,8 = $w N verir.',
        unit: 'N',
      );
    default:
      final w = 6 * n, t = 5 * n;
      return _s(
        '${yalniz(w)} ${_ipAcilari(37, 37)} İplerden birindeki gerilme kuvveti '
            '$t N olarak ölçüldüğüne göre cismin ağırlığı kaç N olur? '
            '(${_sc[37]})',
        w,
        [10 * n, 3 * n, 8 * n],
        'Simetrik iplerdeki gerilmeler eşittir ve yatay bileşenler birbirini '
            'dengeler. Düşey denge G = 2·T·sin 37° = 2·$t·0,6 = $w N verir.',
        unit: 'N',
      );
  }
}

/// Biri yatay (duvara), biri eğik (tavana) iki iple tutulan cisim.
AdvancedItem _yatayIp(int a, int b, int k) {
  final v = b % 10;
  final n = 1 + a + 25 * (b ~/ 10) + 50 * k; // 1 … 150
  String ad(num w) => _asili(w, a + b);
  String duzen(int aci) =>
      'ağırlığı önemsiz iki iple dengede tutuluyor. İplerden biri yatay olup '
      'düşey bir duvara, diğeri tavana bağlıdır ve tavanla $aci° açı '
      'yapmaktadır.';
  String agirlikli(num w, String yazi, int aci) =>
      'Ağırlığı $yazi N olan ${ad(w)}, ${duzen(aci)}';
  String yalniz(num w, int aci) => '${_bas(ad(w))}, ${duzen(aci)}';
  const tavan = 'Tavana bağlı ipteki gerilme kuvveti kaç N olur?';
  const yatay = 'Yatay ipteki gerilme kuvveti kaç N olur?';
  String esas(int aci) =>
      'Tavana bağlı ipteki gerilme T₁, yatay ipteki gerilme T₂ olsun. Düşey '
      'denge T₁·sin $aci° = G, yatay denge T₁·cos $aci° = T₂ verir.';
  switch (v) {
    case 0 || 1:
      final w = 3 * n;
      final ilk = v == 0;
      return _s(
        '${agirlikli(w, '$w', 37)} ${ilk ? tavan : yatay} (${_sc[37]})',
        ilk ? 5 * n : 4 * n,
        ilk ? [1.8 * n, 3.75 * n, 4 * n] : [2.25 * n, 5 * n, 2.4 * n],
        '${esas(37)} T₁ = $w / 0,6 = ${5 * n} N'
            '${ilk ? '' : ', T₂ = ${5 * n}·0,8 = ${4 * n} N'} bulunur.',
        unit: 'N',
      );
    case 2 || 3:
      final w = 4 * n;
      final ilk = v == 2;
      return _s(
        '${agirlikli(w, '$w', 53)} ${ilk ? tavan : yatay} (${_sc[53]})',
        ilk ? 5 * n : 3 * n,
        ilk ? [3.2 * n, 3 * n, w] : [5 * n, 2.4 * n, 3.2 * n],
        '${esas(53)} T₁ = $w / 0,8 = ${5 * n} N'
            '${ilk ? '' : ', T₂ = ${5 * n}·0,6 = ${3 * n} N'} bulunur.',
        unit: 'N',
      );
    case 4:
      final m = _atla(n, const {15});
      return _s(
        '${agirlikli(m, '$m', 30)} $tavan (${_sc[30]})',
        2 * m,
        [m / 2, '${_k3(m)} N', m],
        '${esas(30)} T₁ = $m / (1/2) = ${2 * m} N bulunur.',
        unit: 'N',
      );
    case 5:
      final m = _atla(n, const {1, 10}); // √3 yazımındaki 3 ile karışmasın
      return _s(
        '${agirlikli(m * 1.732, _k3(m), 30)} $yatay (${_sc[30]})',
        3 * m,
        ['${_k3(2 * m)} N', m, '${_k3(m)} N'],
        '${esas(30)} T₁ = ${_k3(m)} / (1/2) = ${_k3(2 * m)} N, T₂ = '
            '${_k3(2 * m)}·√3/2 = ${3 * m} N bulunur.',
        unit: 'N',
      );
    case 6:
      final m = _atla(n, const {30});
      return _s(
        '${agirlikli(m * 1.732, _k3(m), 60)} $tavan (${_sc[60]})',
        2 * m,
        [1.5 * m, m, '${_k3(2 * m)} N'],
        '${esas(60)} T₁ = ${_k3(m)} / (√3/2) = ${2 * m} N bulunur.',
        unit: 'N',
      );
    case 7:
      final w = 3 * n;
      return _s(
        '${yalniz(w, 37)} Yatay ipteki gerilme kuvveti ${4 * n} N olarak '
            'ölçüldüğüne göre cismin ağırlığı kaç N olur? (${_sc[37]})',
        w,
        [2.4 * n, 3.2 * n, 5 * n],
        '${esas(37)} T₁ = ${4 * n} / 0,8 = ${5 * n} N olur. Buradan '
            'G = ${5 * n}·0,6 = $w N bulunur.',
        unit: 'N',
      );
    case 8:
      return _s(
        '${yalniz(4 * n, 53)} Tavana bağlı ipteki gerilme kuvveti ${5 * n} N '
            'olarak ölçüldüğüne göre yatay ipteki gerilme kuvveti kaç N olur? '
            '(${_sc[53]})',
        3 * n,
        [4 * n, 5 * n, 2.4 * n],
        '${esas(53)} T₂ = ${5 * n}·0,6 = ${3 * n} N bulunur.',
        unit: 'N',
      );
    default:
      final w = 3 * n;
      return _s(
        '${yalniz(w, 37)} Tavana bağlı ipteki gerilme kuvveti ${5 * n} N '
            'olarak ölçüldüğüne göre cismin ağırlığı kaç N olur? (${_sc[37]})',
        w,
        [4 * n, 5 * n, 3.75 * n],
        '${esas(37)} G = ${5 * n}·0,6 = $w N bulunur.',
        unit: 'N',
      );
  }
}

/// İple asılı cisme yatay kuvvet uygulanması.
AdvancedItem _yatayKuvvet(int a, int b, int k) {
  final v = b % 10;
  final n = 1 + a + 25 * (b ~/ 10) + 50 * k; // 1 … 150
  String ad(num w) => _asili(w, a + b);
  const asili = 'tavana bağlı ağırlığı önemsiz bir ipin ucuna asılıdır.';
  String sapma(int aci) =>
      'ip düşeyle $aci° açı yapacak biçimde dengede kalıyor.';
  String agirlikli(num w, String yazi, int aci) =>
      'Ağırlığı $yazi N olan ${ad(w)}, $asili Cisme yatay doğrultuda bir F '
      'kuvveti uygulandığında cisim, ${sapma(aci)}';
  const fSoru = 'F kuvvetinin büyüklüğü kaç N olur?';
  const tSoru = 'İpteki gerilme kuvveti kaç N olur?';
  String esas(int aci) =>
      'İpteki gerilme T olsun. Düşey denge T·cos $aci° = G, yatay denge '
      'T·sin $aci° = F verir.';
  switch (v) {
    case 0 || 1:
      final w = 4 * n;
      final f = v == 0;
      return _s(
        '${agirlikli(w, '$w', 37)} ${f ? fSoru : tSoru} (${_sc[37]})',
        f ? 3 * n : 5 * n,
        f ? [2.4 * n, 3.2 * n, 5 * n] : [3.2 * n, 3 * n, 7 * n],
        '${esas(37)} T = $w / 0,8 = ${5 * n} N'
            '${f ? ' ve F = ${5 * n}·0,6 = ${3 * n} N' : ''} bulunur.',
        unit: 'N',
      );
    case 2 || 3:
      final w = 3 * n;
      final f = v == 2;
      return _s(
        '${agirlikli(w, '$w', 53)} ${f ? fSoru : tSoru} (${_sc[53]})',
        f ? 4 * n : 5 * n,
        f ? [2.4 * n, 2.25 * n, 5 * n] : [1.8 * n, 3.75 * n, 7 * n],
        '${esas(53)} T = $w / 0,6 = ${5 * n} N'
            '${f ? ' ve F = ${5 * n}·0,8 = ${4 * n} N' : ''} bulunur.',
        unit: 'N',
      );
    case 4:
      final m = _atla(n, const {30});
      return _s(
        '${agirlikli(m, '$m', 60)} $tSoru (${_sc[60]})',
        2 * m,
        [m / 2, m, '${_k3(m)} N'],
        '${esas(60)} T = $m / (1/2) = ${2 * m} N bulunur.',
        unit: 'N',
      );
    case 5:
      final m = _atla(n, const {1, 20}); // √3 yazımındaki 3 ile karışmasın
      return _s(
        '${agirlikli(m * 1.732, _k3(m), 60)} $fSoru (${_sc[60]})',
        3 * m,
        [m, '${_k3(2 * m)} N', 1.5 * m],
        '${esas(60)} T = ${_k3(m)} / (1/2) = ${_k3(2 * m)} N ve F = '
            '${_k3(2 * m)}·√3/2 = ${3 * m} N bulunur.',
        unit: 'N',
      );
    case 6:
      final m = _atla(n, const {15});
      return _s(
        '${agirlikli(m * 1.732, _k3(m), 30)} $tSoru (${_sc[30]})',
        2 * m,
        [1.5 * m, m, '${_k3(2 * m)} N'],
        '${esas(30)} T = ${_k3(m)} / (√3/2) = ${2 * m} N bulunur.',
        unit: 'N',
      );
    case 7:
      final (f1, f2, r) = _bileske[90]![n - 1];
      final (w, f) = n.isEven ? (f2, f1) : (f1, f2);
      return _s(
        'Ağırlığı $w N olan ${ad(w)}, $asili Cisme yatay doğrultuda $f N '
            'büyüklüğünde bir kuvvet uygulandığında cisim, ip düşey doğrultudan '
            'saparak dengede kalıyor. $tSoru',
        r,
        [w + f, (w - f).abs(), math.max(w, f)],
        'Cisim üç kuvvetin etkisinde dengede olduğundan ipteki gerilme, ağırlık '
            'ile yatay kuvvetin bileşkesine eşit büyüklüktedir. Bu iki kuvvet '
            'birbirine dik olduğundan T = √($w² + $f²) = √(${w * w} + ${f * f}) = '
            '$r N olur.',
        unit: 'N',
      );
    case 8:
      final w = 4 * n;
      return _s(
        '${_bas(ad(w))}, $asili Cisme yatay doğrultuda ${3 * n} N büyüklüğünde '
            'bir kuvvet uygulandığında cisim, ${sapma(37)} Cismin ağırlığı kaç N '
            'olur? (${_sc[37]})',
        w,
        [2.25 * n, 2.4 * n, 5 * n],
        '${esas(37)} T = ${3 * n} / 0,6 = ${5 * n} N olur. Buradan '
            'G = ${5 * n}·0,8 = $w N bulunur.',
        unit: 'N',
      );
    default:
      return _s(
        '${_bas(ad(3 * n))}, $asili Cisme yatay doğrultuda ${4 * n} N '
            'büyüklüğünde bir kuvvet uygulandığında cisim, ${sapma(53)} $tSoru '
            '(${_sc[53]})',
        5 * n,
        [3.2 * n, 7 * n, 3 * n],
        '${esas(53)} T = ${4 * n} / 0,8 = ${5 * n} N bulunur.',
        unit: 'N',
      );
  }
}

final _f02 = lmAile(
  'fz_uc_kuvvet',
  'Üç kuvvetin dengesi: ipe asılı cisimde ip gerilmeleri',
  Topic.physics,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) => switch (c % 3) {
    0 => _ikiIp(a, b, c ~/ 3),
    1 => _yatayIp(a, b, c ~/ 3),
    _ => _yatayKuvvet(a, b, c ~/ 3),
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ─────────────────────────── 3 · Sürtünme kuvveti ───────────────────────────

/// (statik, kinetik) sürtünme katsayıları, yüzde biriminde.
const _muCift = [(30, 20), (40, 30), (50, 30), (50, 40), (60, 50)];

/// (statik, kinetik) çiftleri: fark 0,1 değil ve μs = 2·μk değil. Fark 0,1
/// iken (μs − μk)·m·g sayıca kütleye, μs = 2·μk iken kinetik sürtünme
/// kuvvetine eşit çıkardı.
const _muFark = [
  (35, 20),
  (45, 25),
  (45, 30),
  (50, 30),
  (55, 35),
  (60, 40),
  (60, 45),
  (65, 40),
  (65, 45),
  (70, 50),
  (70, 45),
  (75, 50),
  (80, 60),
  (80, 55),
  (85, 60),
];

String _mu(int yuzde) => _n(yuzde / 100);

/// Zıt yönlü iki itme: kasa duruyorsa statik, kayıyorsa kinetik sürtünme.
AdvancedItem _zitItme(int a, int b, int k) {
  final m = 6 + a; // 6 … 30 kg
  final kayar = b.isOdd;
  final (ms, mk) = _muCift[(b ~/ 2) % 5];
  final fs = ms * m / 10, fk = mk * m / 10; // N
  final oran = kayar
      ? const [1.1, 1.15, 1.25, 1.4][k]
      : const [0.4, 0.5, 0.7, 0.9][k];
  final p = _iki(fs * oran); // net itme
  final dogru = kayar ? fk : p;
  var f2 = 15 + 10 * (b ~/ 10 + 2 * k); // 15 … 85 N
  // Anahtar kökteki bir sayıya (kütle, kuvvetler, g) eşit çıkmasın.
  while ({m, f2, _iki(f2 + p), 10}.any((x) => (x - dogru).abs() < 1e-9)) {
    f2++;
  }
  final f1 = _iki(f2 + p);
  final itme =
      'Kasaya etki eden net itme ${_n(f1)} − $f2 = ${_n(p)} N olur. En büyük '
      'statik sürtünme kuvveti μs·m·g = ${_mu(ms)}·$m·10 = ${_n(fs)} N olduğundan';
  return _s(
    'Yatay zeminde duran $m kg kütleli bir kasayı iki kişi zıt yönlerde, '
    'zemine paralel kuvvetlerle itiyor. Kişilerden biri ${_n(f1)} N, diğeri '
    '$f2 N büyüklüğünde kuvvet uyguluyor. Kasa ile zemin arasındaki statik '
    'sürtünme katsayısı ${_mu(ms)}, kinetik sürtünme katsayısı ${_mu(mk)} '
    'olduğuna göre kasaya etki eden sürtünme kuvvetinin büyüklüğü kaç N olur? '
    '$_g10',
    dogru,
    kayar ? [fs, p, p - fk, f1] : [fs, fk, f1, f1 + f2],
    kayar
        ? '$itme ${_n(p)} > ${_n(fs)}; kasa harekete geçer. Kayan kasaya '
              'kinetik sürtünme kuvveti etki eder: μk·m·g = ${_mu(mk)}·$m·10 = '
              '${_n(fk)} N.'
        : '$itme ${_n(p)} < ${_n(fs)}; kasa hareket etmez. Statik sürtünme '
              'kuvveti net itmeyi dengeler ve büyüklüğü ${_n(p)} N olur.',
    unit: 'N',
  );
}

/// Harekete geçiren en küçük kuvvet, sabit hız ve sürtünme katsayısı.
AdvancedItem _surtunmeKatsayi(int a, int b, int k) {
  final v = b % 4, q = b ~/ 4; // q: 0 … 4
  final j = q + 5 * k; // 0 … 14
  final m = 6 + a; // 6 … 30 kg
  switch (v) {
    case 0:
      final ms = 20 + 5 * j; // 0,2 … 0,9
      final f = ms * m / 10;
      return _s(
        'Yatay zeminde duran $m kg kütleli bir dolap ile zemin arasındaki '
            'statik sürtünme katsayısı ${_mu(ms)} olarak veriliyor. Dolabı harekete '
            'geçirebilmek için zemine paralel olarak en az kaç N kuvvet '
            'uygulanmalıdır? $_g10',
        f,
        [ms * m / 100, 10 * m, 1000 * m / ms],
        'Dolap, uygulanan kuvvet en büyük statik sürtünme kuvvetini aştığı '
            'anda harekete geçer. En büyük statik sürtünme kuvveti μs·m·g = '
            '${_mu(ms)}·$m·10 = ${_n(f)} N olduğundan en az ${_n(f)} N kuvvet '
            'gerekir.',
        unit: 'N',
      );
    case 1:
      final (ms, mk) = _muFark[j];
      final fs = ms * m / 10, fk = mk * m / 10, fark = (ms - mk) * m / 10;
      return _s(
        'Yatay zeminde duran $m kg kütleli bir kasa ile zemin arasındaki '
            'statik sürtünme katsayısı ${_mu(ms)}, kinetik sürtünme katsayısı '
            '${_mu(mk)} olarak veriliyor. Kasa, gereken en küçük yatay kuvvetle '
            'harekete geçirildikten sonra sabit hızla çekilmek isteniyor. Bunun '
            'için uygulanan yatay kuvvet kaç N azaltılmalıdır? $_g10',
        fark,
        [fs, fk, (ms - mk) * m / 100],
        'Harekete geçirmek için gereken en küçük kuvvet μs·m·g = '
            '${_mu(ms)}·$m·10 = ${_n(fs)} N, sabit hız için gereken kuvvet ise '
            'kinetik sürtünmeye eşit olup μk·m·g = ${_mu(mk)}·$m·10 = ${_n(fk)} N '
            'olur. Kuvvet ${_n(fs)} − ${_n(fk)} = ${_n(fark)} N azaltılmalıdır.',
        unit: 'N',
      );
    case 2:
      final (ms, mk) = _muFark[j];
      final fs = ms * m / 10, fk = mk * m / 10;
      final kinetik = (a + j).isEven;
      final dogru = (kinetik ? mk : ms) / 100;
      return _s(
        'Yatay zeminde duran $m kg kütleli bir kasayı harekete geçirmek için '
        'zemine paralel en az ${_n(fs)} N kuvvet gerekiyor. Harekete geçen '
        'kasa, zemine paralel ${_n(fk)} N büyüklüğündeki kuvvetle sabit hızla '
        'çekilebiliyor. Kasa ile zemin arasındaki '
        '${kinetik ? 'kinetik' : 'statik'} sürtünme katsayısı kaçtır? $_g10',
        dogru,
        [
          (kinetik ? fk : fs) / m,
          (kinetik ? ms : mk) / 100,
          10 * m / (kinetik ? fk : fs),
        ],
        kinetik
            ? 'Sabit hızda uygulanan kuvvet kinetik sürtünme kuvvetine eşittir: '
                  'μk·m·g = ${_n(fk)}, μk = ${_n(fk)} / ($m·10) = ${_n(dogru)}.'
            : 'Harekete geçiren en küçük kuvvet en büyük statik sürtünme '
                  'kuvvetine eşittir: μs·m·g = ${_n(fs)}, μs = ${_n(fs)} / '
                  '($m·10) = ${_n(dogru)}.',
      );
    default:
      final ms = const [20, 25, 40, 50, 80][q];
      final m10 = 9 + a + 25 * k; // 0,9 … 8,3 kg
      final w = m10.toDouble(), f = 100 * m10 / ms;
      final (nesne, yalin) = m10 <= 25
          ? ('bir kitap', 'kitap')
          : m10 <= 50
          ? ('bir tuğla', 'tuğla')
          : ('bir tahta blok', 'tahta blok');
      return _s(
        'Kütlesi ${_n(m10 / 10)} kg olan $nesne, düşey bir duvara yatay bir '
            'kuvvetle bastırılarak kaymadan dengede tutuluyor. ${_bas(yalin)} ile '
            'duvar arasındaki statik sürtünme katsayısı ${_mu(ms)} olduğuna göre '
            'bastırma kuvveti en az kaç N olmalıdır? $_g10',
        f,
        [w * ms / 100, w, m10 * 10 / ms],
        'Bastırma kuvveti F, duvarın cisme uyguladığı tepki kuvvetine eşittir. '
            'Cismin kaymaması için en büyük statik sürtünme kuvveti ağırlığı '
            'karşılamalıdır: μs·F ≥ m·g, yani F ≥ ${_n(w)} / ${_mu(ms)} = '
            '${_n(f)} N.',
        unit: 'N',
      );
  }
}

/// (giriş, kısa ad, tamlayan, yüzey ikilisi, μ yüzdeleri, en küçük ve en
/// büyük hız (0,1 m/s), en büyük durma yolu (m)).
const _kayma = <(String, String, String, String, List<int>, int, int, int)>[
  (
    'Donmuş bir gölün yüzeyinde kaydırılan bir taş',
    'taş',
    'taşın',
    'Taş ile buz',
    [2, 4, 5],
    10,
    120,
    150,
  ),
  (
    'Buz pistinde vurulan bir hokey diski',
    'disk',
    'diskin',
    'Disk ile buz',
    [5, 8, 10, 12],
    20,
    160,
    80,
  ),
  (
    'Fabrika zemininde itilip bırakılan bir koli',
    'koli',
    'kolinin',
    'Koli ile zemin',
    [20, 25, 30, 40, 50, 60],
    4,
    80,
    12,
  ),
  (
    'Karla kaplı düz bir alanda kayan bir kızak',
    'kızak',
    'kızağın',
    'Kızak ile kar',
    [5, 8, 15, 20, 25],
    20,
    120,
    90,
  ),
  (
    'Frene basıldığında tekerlekleri kilitlenen bir otomobil',
    'otomobil',
    'otomobilin',
    'Lastikler ile yol',
    [40, 50, 75, 80],
    80,
    300,
    110,
  ),
];

/// Her bağlam için (μ yüzdesi, hız (0,1 m/s)) ikilileri: durma yolu
/// v²/(2μg) ve süresi v/(μg) iki ondalıkta kesin; yol, süre, hız, μ ve g
/// birbirine eşit değil (yanlış nicelik yazan öğrenci doğruyu bulamasın).
/// v₀ = 1 ve 2 m/s alınmaz: v ile v² ya da v²/2 ile v aynı sayı olurdu.
final _kaymaListesi = [
  for (final (_, _, _, _, mus, v0, v1, dmax) in _kayma)
    [
      for (final mu in mus)
        for (var v = v0; v <= v1; v++)
          if (v != 10 &&
              v != 20 &&
              5 * v * v % mu == 0 &&
              100 * v % mu == 0 &&
              v * v / (20 * mu) <= dmax &&
              {
                    _iki(v * v / (20 * mu)),
                    _iki(v / mu),
                    _iki(v / 10),
                    _iki(mu / 100),
                    10.0,
                  }.length ==
                  5)
            (mu, v),
    ],
];

/// Sürtünmeli yatay yüzeyde kayarak durma.
AdvancedItem _kayarakDurma(int a, int b, int k) {
  final v = b % 4, q = b ~/ 4; // q: bağlam 0 … 4
  final (giris, ad, tamlayan, yuzey, _, _, _, _) = _kayma[q];
  final (mu100, v10) = _yay(_kaymaListesi[q], a + 25 * k, 75);
  final mu = mu100 / 100, v0 = v10 / 10, ivme = mu100 / 10;
  final d = v10 * v10 / (20 * mu100), t = v10 / mu100;
  final ivmeYazi =
      'Yatay yüzeyde sürtünme kuvveti μ·m·g olduğundan yavaşlama ivmesi '
      'a = μ·g = ${_n(mu)}·10 = ${_n(ivme)} m/s² olur.';
  const yalniz = 'yalnız sürtünme kuvvetinin etkisiyle yavaşlayarak';
  switch (v) {
    case 0:
      return _s(
        '$giris, ${_n(v0)} m/s hızla kaymaya başladıktan sonra $yalniz '
            'duruyor. $yuzey arasındaki kinetik sürtünme katsayısı ${_n(mu)} '
            'olduğuna göre $ad duruncaya kadar kaç metre yol alır? $_g10',
        d,
        [2 * d, 10 * d, v0 / (2 * ivme)],
        '$ivmeYazi v₀² = 2·a·x bağıntısından x = ${_n(v0)}² / (2·${_n(ivme)}) '
            '= ${_n(d)} m bulunur.',
        unit: 'm',
      );
    case 1:
      return _s(
        '$giris, ${_n(v0)} m/s hızla kaymaya başladıktan sonra $yalniz '
            'duruyor. $yuzey arasındaki kinetik sürtünme katsayısı ${_n(mu)} '
            'olduğuna göre $ad kaymaya başladıktan kaç saniye sonra durur? $_g10',
        t,
        [v0 / mu, t / 2, 2 * t],
        '$ivmeYazi v = v₀ − a·t = 0 eşitliğinden t = ${_n(v0)} / ${_n(ivme)} '
            '= ${_n(t)} s bulunur.',
        unit: 's',
      );
    case 2:
      return _s(
        '$giris, ${_n(v0)} m/s hızla kaymaya başladıktan sonra $yalniz '
            '${_n(d)} m yol alıp duruyor. $yuzey arasındaki kinetik sürtünme '
            'katsayısı kaçtır? $_g10',
        mu,
        [2 * mu, ivme, mu / 2],
        'v₀² = 2·a·x bağıntısından yavaşlama ivmesi a = ${_n(v0)}² / '
            '(2·${_n(d)}) = ${_n(ivme)} m/s² olur. a = μ·g olduğundan '
            'μ = ${_n(ivme)} / 10 = ${_n(mu)} bulunur.',
      );
    default:
      return _s(
        '$giris, $yalniz ${_n(d)} m yol alıp duruyor. $yuzey arasındaki '
            'kinetik sürtünme katsayısı ${_n(mu)} olduğuna göre $tamlayan kaymaya '
            'başladığı andaki hızı kaç m/s idi? $_g10',
        v0,
        [v0 * v0, v0 * v0 / 2, 2 * v0],
        '$ivmeYazi v₀² = 2·a·x = 2·${_n(ivme)}·${_n(d)} = ${_n(v0 * v0)} '
            'olduğundan v₀ = ${_n(v0)} m/s bulunur.',
        unit: 'm/s',
      );
  }
}

final _f03 = lmAile(
  'fz_surtunme',
  'Statik ve kinetik sürtünme, durma yolu',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.analiz,
  (a, b, c) => switch (c % 3) {
    0 => _zitItme(a, b, c ~/ 3),
    1 => _surtunmeKatsayi(a, b, c ~/ 3),
    _ => _kayarakDurma(a, b, c ~/ 3),
  },
  exam: ExamKind.tyt,
  lesson: _fizik,
);

// ─────────────────────── 4 · Merkezî esnek çarpışma ─────────────────────────

/// Duran cisme merkezî esnek çarpışma: (m_K, m_L, v) üçlüleri; çarpışmadan
/// sonraki hızlar santimetre/saniye birimiyle tam sayıdır (iki ondalık).
final _esnek = [
  for (var m1 = 1; m1 <= 25; m1++)
    for (var m2 = 1; m2 <= 25; m2++)
      // m_L = 2·m_K iken K cisminin hızı kenetlenme hızına, m_L = 3·m_K
      // iken L cisminin hızına eşit çıkar; bu oranlar alınmaz.
      if (m1 != m2 && m2 != 2 * m1 && m2 != 3 * m1)
        for (var v = 1; v <= 30; v++)
          if (200 * m1 * v % (m1 + m2) == 0) (m1, m2, v),
];

int _vL(int m1, int m2, int v) => 200 * m1 * v ~/ (m1 + m2); // cm/s
int _vK(int m1, int m2, int v) => _vL(m1, m2, v) - 100 * v; // cm/s

bool _kokteYok(int santi, List<int> sayilar) =>
    !sayilar.any((x) => 100 * x == santi);

// Hız sorularında yalnız kütle oranı ve ilk hız sonucu belirler.
final _esnekL = _tekil([
  for (final (m1, m2, v) in _esnek)
    if (_kokteYok(_vL(m1, m2, v), [m1, m2, v])) (m1, m2, v),
], (t) => (_oran(t.$1, t.$2), t.$3));
final _esnekK = _tekil([
  for (final (m1, m2, v) in _esnek)
    if (_kokteYok(_vK(m1, m2, v).abs(), [m1, m2, v])) (m1, m2, v),
], (t) => (_oran(t.$1, t.$2), t.$3));

/// Kinetik enerjisi (J) iki ondalıkta kesin ve kökteki sayılardan farklı.
bool _enerjiUygun(int m, int santi, List<int> sayilar) =>
    m * santi * santi % 200 == 0 &&
    !sayilar.any((x) => 20000 * x == m * santi * santi);

final _esnekEL = [
  for (final (m1, m2, v) in _esnek)
    if (_enerjiUygun(m2, _vL(m1, m2, v), [m1, m2, v])) (m1, m2, v),
];
final _esnekEK = [
  for (final (m1, m2, v) in _esnek)
    if (_enerjiUygun(m1, _vK(m1, m2, v), [m1, m2, v])) (m1, m2, v),
];

final _f04 = lmAile(
  'fz_esnek_carpisma',
  'Merkezî esnek çarpışmada hızlar ve kinetik enerji',
  Topic.physics,
  Difficulty.hard,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3, f = c % 3;
    final n = a + 25 * b + 500 * k;
    final (m1, m2, v) = switch (f) {
      0 => _yay(_esnekL, n, 2000),
      1 => _yay(_esnekK, n, 1500),
      _ => n.isEven ? _yay(_esnekEL, n ~/ 2, 750) : _yay(_esnekEK, n ~/ 2, 750),
    };
    final s = m1 + m2;
    final vl = _vL(m1, m2, v) / 100, vk = _vK(m1, m2, v) / 100;
    final ortak = m1 * v / s; // kenetlenme sanan öğrencinin hızı
    final giris =
        'Sürtünmesiz yatay bir düzlemde $v m/s hızla ilerleyen $m1 kg kütleli '
        'K cismi, aynı doğrultu üzerinde durmakta olan $m2 kg kütleli L cismine '
        'merkezî ve esnek olarak çarpıyor.';
    const kutleler = 'K cisminin kütlesi m₁, L cisminin kütlesi m₂ olsun.';
    final lHiz =
        '$kutleler Momentum ve kinetik enerjinin korunumundan L cisminin '
        'hızı 2·m₁·v / (m₁ + m₂) = 2·$m1·$v / $s = ${_n(vl)} m/s bulunur.';
    final kHiz =
        '$kutleler Momentum ve kinetik enerjinin korunumundan K cisminin '
        'hızı (m₁ − m₂)·v / (m₁ + m₂) = ($m1 − $m2)·$v / $s = ${_n(vk)} m/s '
        'bulunur. ${vk < 0 ? 'Eksi işaret K cisminin geri döndüğünü gösterir; '
                  'hızının büyüklüğü ${_n(-vk)} m/s olur.' : 'K cismi aynı '
                  'yönde yavaşlayarak ilerler.'}';
    if (f == 0) {
      return _s(
        '$giris Çarpışmadan sonra L cisminin hızı kaç m/s olur?',
        vl,
        [ortak, m1 * v / m2, v, vk.abs()],
        lHiz,
        unit: 'm/s',
      );
    }
    if (f == 1) {
      return _s(
        '$giris Çarpışmadan sonra K cisminin hızının büyüklüğü kaç m/s olur?',
        vk.abs(),
        [vl, ortak, v],
        kHiz,
        unit: 'm/s',
      );
    }
    final ilk = m1 * v * v / 2; // çarpışmadan önceki kinetik enerji
    if (n.isEven) {
      final e = m2 * vl * vl / 2;
      return _s(
        '$giris Çarpışmadan sonra L cisminin kinetik enerjisi kaç J olur?',
        e,
        [ilk, m2 * v * v / 2, m2 * ortak * ortak / 2, ilk - e],
        '$lHiz Çarpışmadan sonra L cisminin kinetik enerjisi '
            '½·$m2·${_n(vl)}² = ${_n(e)} J olur.',
        unit: 'J',
      );
    }
    final e = m1 * vk * vk / 2;
    return _s(
      '$giris Çarpışmadan sonra K cisminin kinetik enerjisi kaç J olur?',
      e,
      [ilk, ilk - e, m1 * ortak * ortak / 2, m1 * vl * vl / 2],
      '$kHiz Çarpışmadan sonra K cisminin kinetik enerjisi '
          '½·$m1·${_n(vk.abs())}² = ${_n(e)} J olur.',
      unit: 'J',
    );
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ─────────────────────── 5 · Patlama ve geri tepme ──────────────────────────

/// Tüfek: (kütle 0,1 kg, mermi g, mermi hızı m/s); geri tepme hızı
/// 0,5 … 6 m/s ve iki ondalıkta kesin.
final _tufek = _tekil([
  for (final m10 in const [25, 30, 35, 40, 45, 50, 55, 60])
    for (final mg in const [4, 5, 6, 8, 10, 12, 15, 16, 20, 24, 25])
      for (var v = 300; v <= 1000; v += 25)
        if (mg * v % m10 == 0 &&
            mg * v >= 50 * m10 &&
            mg * v <= 600 * m10 &&
            !_icinde(mg * v / (100 * m10), [m10 / 10, mg, v]))
          (m10, mg, v),
], (t) => (_oran(t.$2, t.$1), t.$3));

/// Top: (kütle kg, mermi kg, mermi hızı m/s); geri tepme 0,5 … 15 m/s.
final _top = _tekil([
  for (var mt = 400; mt <= 3000; mt += 100)
    for (final mm in const [4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50])
      for (var v = 150; v <= 900; v += 25)
        if (100 * mm * v % mt == 0 &&
            2 * mm * v >= mt &&
            mm * v <= 15 * mt &&
            !_icinde(mm * v / mt, [mt, mm, v]))
          (mt, mm, v),
], (t) => (_oran(t.$2, t.$1), t.$3));

/// Kayıktan atlama: (insan kg, kayık kg, kayığın ilk hızı ×2, atlama hızı ×2);
/// ilk hız 0 ise kayık durgundur. Yanıtlar iki ondalıkta kesin.
List<(int, int, int, int)> _kayikListesi(int tur) => [
  for (var m = 40; m <= 90; m += 5)
    for (var kayik = 60; kayik <= 300; kayik += (tur == 0 ? 10 : 20))
      for (var v02 = (tur == 0 ? 0 : 1); v02 <= (tur == 0 ? 0 : 6); v02++)
        for (var u2 = 2; u2 <= 12; u2++)
          if (_kayikUygun(tur, m, kayik, v02, u2)) (m, kayik, v02, u2),
];

/// tur 0: durgun kayık; 1: geriye atlama; 2: ileri atlama.
double? _kayikHizi(int tur, int m, int kayik, int v02, int u2) {
  final pay = switch (tur) {
    0 => m * u2,
    1 => (kayik + m) * v02 + m * u2,
    _ => (kayik + m) * v02 - m * u2,
  }; // kayık hızı = pay / (2·kayık)
  if (tur == 2 && u2 <= v02) return null;
  if (pay == 0 || 50 * pay % kayik != 0) return null;
  return pay / (2 * kayik);
}

bool _kayikUygun(int tur, int m, int kayik, int v02, int u2) {
  final h = _kayikHizi(tur, m, kayik, v02, u2);
  if (h == null) return false;
  final b = h.abs();
  if (tur == 0 && (b < 0.2 || b > 5)) return false;
  if (b > 8) return false;
  if (_icinde(b, [m, kayik, u2 / 2, v02 / 2])) return false;
  if (tur == 0) return true;
  // Yanlış yollar (işaret hatası, ilk hareketi ya da atlamayı yok sayma)
  // doğru yanıtı vermesin.
  final p = (kayik + m) * v02, ters = tur == 1 ? p - m * u2 : p + m * u2;
  return !_icinde(b, [
    ters.abs() / (2 * kayik),
    p / (2 * kayik),
    m * u2 / (2 * kayik),
  ]);
}

final _kayikDurgun = _tekil(_kayikListesi(0), (t) => (_oran(t.$1, t.$2), t.$4));
final _kayikGeri = _tekil(
  _kayikListesi(1),
  (t) => (_oran(t.$1, t.$2), t.$3, t.$4),
);
final _kayikIleri = _tekil(
  _kayikListesi(2),
  (t) => (_oran(t.$1, t.$2), t.$3, t.$4),
);

/// İki parçaya ayrılma: (m₁, m₂, ilk hız, birinci parçanın hızı); tur 0
/// duran cisim, 1 hareketli cisim (birinci parça ileri), 2 hareketli cisim
/// (birinci parça durur), 3 duran cisimde açığa çıkan enerji.
List<(int, int, int, int)> _parcaListesi(int tur) => [
  for (var m1 = 1; m1 <= 12; m1++)
    for (var m2 = 1; m2 <= 12; m2++)
      if (m1 != m2)
        for (
          var v0 = (tur == 0 || tur == 3 ? 0 : 2);
          v0 <= (tur == 0 || tur == 3 ? 0 : 20);
          v0++
        )
          for (
            var v1 = (tur == 2 ? 0 : (tur == 1 ? v0 + 1 : 2));
            v1 <= (tur == 2 ? 0 : (tur == 1 ? 40 : 30));
            v1++
          )
            if (_parcaUygun(tur, m1, m2, v0, v1)) (m1, m2, v0, v1),
];

bool _parcaUygun(int tur, int m1, int m2, int v0, int v1) {
  final pay = (m1 + m2) * v0 - m1 * v1; // m₂·v₂ (duran cisimde eksi)
  if (pay == 0 || 100 * pay % m2 != 0) return false;
  final v2 = pay / m2;
  if (tur == 2 && v2 <= 0) return false;
  if (v2.abs() > 40) return false;
  final sayilar = [m1, m2, v0, v1, m1 + m2];
  if (_icinde(v2.abs(), sayilar)) return false;
  if (tur == 1) {
    // İşaret hatası, ilk momentumu ya da patlamayı yok sayma doğruyu vermesin.
    final yanlis = [
      ((m1 + m2) * v0 + m1 * v1) / m2,
      (m1 + m2) * v0 / m2,
      m1 * v1 / m2,
    ];
    if (_icinde(v2.abs(), yanlis)) return false;
  }
  if (tur == 3) {
    // Enerji m₁·v₁²·(m₁ + m₂) / (2·m₂) iki ondalıkta kesin olmalı.
    final pay2 = 100 * m1 * v1 * v1 * (m1 + m2);
    if (pay2 % (2 * m2) != 0) return false;
    if (_icinde(pay2 / (200 * m2), sayilar)) return false;
  }
  return true;
}

final _parcalar = [
  for (var t = 0; t < 4; t++)
    _tekil(
      _parcaListesi(t),
      (x) => switch (t) {
        0 => (_oran(x.$1, x.$2), x.$4),
        1 => (_oran(x.$1, x.$2), x.$3, x.$4),
        2 => (_oran(x.$1, x.$2), x.$3),
        _ => x, // enerji sorusunda kütlelerin kendisi hesabı değiştirir
      },
    ),
];

AdvancedItem _geriTepme(int a, int b, int k) {
  final v = b % 4;
  final n = a + 25 * (b ~/ 4) + 125 * k; // 0 … 499
  if (v < 2) {
    final (m10, mg, hiz) = _yay(_tufek, n, 500);
    final tm = m10 / 10, geri = mg * hiz / (100 * m10);
    final giris =
        'Kütlesi ${_n(tm)} kg olan bir tüfekten $mg g kütleli bir mermi '
        'yatay doğrultuda';
    final cozum =
        'Atıştan önce sistemin momentumu sıfırdır; atıştan sonra da toplam '
        'momentum sıfır kalır: m_mermi·v_mermi = m_tüfek·v_tüfek. Mermi kütlesi '
        '$mg g = ${_n(mg / 1000, 3)} kg olduğundan';
    if (v == 0) {
      return _s(
        '$giris $hiz m/s hızla atılıyor. Tüfeğin geri tepme hızı kaç m/s '
            'olur?',
        geri,
        [mg * hiz / tm, geri * 10],
        '$cozum ${_n(mg / 1000, 3)}·$hiz = ${_n(tm)}·V, V = ${_n(geri)} m/s '
            'bulunur.',
        unit: 'm/s',
      );
    }
    return _s(
      '$giris atıldığında tüfek ${_n(geri)} m/s hızla geri tepiyor. Merminin '
          'namludan çıkış hızı kaç m/s olur?',
      hiz,
      [tm * geri / mg, hiz / 10, hiz * 10],
      '$cozum ${_n(mg / 1000, 3)}·v = ${_n(tm)}·${_n(geri)}, v = $hiz m/s '
          'bulunur.',
      unit: 'm/s',
    );
  }
  final (mt, mm, hiz) = _yay(_top, n, 500);
  final geri = mm * hiz / mt;
  final giris =
      'Sürtünmesiz yatay raylar üzerinde duran $mt kg kütleli bir toptan '
      '$mm kg kütleli bir gülle yatay doğrultuda';
  const cozum =
      'Atıştan önce toplam momentum sıfır olduğundan atıştan sonra '
      'm_gülle·v_gülle = m_top·V olur:';
  if (v == 2) {
    return _s(
      '$giris $hiz m/s hızla atılıyor. Topun geri tepme hızı kaç m/s olur?',
      geri,
      [mm * hiz / (mt + mm), geri * 10],
      '$cozum $mm·$hiz = $mt·V, V = ${_n(geri)} m/s.',
      unit: 'm/s',
    );
  }
  return _s(
    '$giris atıldığında top ${_n(geri)} m/s hızla geri tepiyor. Güllenin '
        'namludan çıkış hızı kaç m/s olur?',
    hiz,
    [(mt + mm) * geri / mm, hiz / 10, hiz * 10],
    '$cozum $mm·v = $mt·${_n(geri)}, v = $hiz m/s.',
    unit: 'm/s',
  );
}

AdvancedItem _kayiktanAtlama(int a, int b, int k) {
  final v = b % 4;
  final n = a + 25 * (b ~/ 4) + 125 * k; // 0 … 374
  if (v < 2) {
    final (m, kayik, _, u2) = _yay(_kayikDurgun, n, 375);
    final u = u2 / 2, hiz = m * u / kayik;
    final giris =
        'Durgun bir gölde duran $kayik kg kütleli bir kayıktaki $m kg '
        'kütleli bir kişi, kayıktan yatay doğrultuda';
    const cozum =
        'Başlangıçta kişi ve kayık durgun olduğundan toplam momentum sıfırdır; '
        'atlamadan sonra da m_kişi·v_kişi = m_kayık·v_kayık olur:';
    if (v == 0) {
      return _s(
        '$giris kıyıya göre ${_n(u)} m/s hızla atlıyor. Suyun direnci '
            'önemsiz olduğuna göre kayığın geri tepme hızı kaç m/s olur?',
        hiz,
        [m * u / (kayik + m), kayik * u / m, u],
        '$cozum $m·${_n(u)} = $kayik·V, V = ${_n(hiz)} m/s bulunur.',
        unit: 'm/s',
      );
    }
    return _s(
      '$giris atladığında kayık ters yönde ${_n(hiz)} m/s hızla hareket '
          'etmeye başlıyor. Suyun direnci önemsiz olduğuna göre kişinin kıyıya '
          'göre atlama hızı kaç m/s olur?',
      u,
      [m * hiz / kayik, (kayik + m) * hiz / m, hiz],
      '$cozum $m·v = $kayik·${_n(hiz)}, v = ${_n(u)} m/s bulunur.',
      unit: 'm/s',
    );
  }
  final geri = v == 2;
  final (m, kayik, v02, u2) = _yay(geri ? _kayikGeri : _kayikIleri, n, 375);
  final v0 = v02 / 2, u = u2 / 2;
  final hiz = _kayikHizi(geri ? 1 : 2, m, kayik, v02, u2)!;
  final toplam = (kayik + m) * v0;
  final yon = geri ? 'hareket yönünün tersine' : 'hareket yönünde';
  final yanlis = geri ? (toplam - m * u) / kayik : (toplam + m * u) / kayik;
  return _s(
    'Durgun bir gölde, içinde $m kg kütleli bir kişi bulunan $kayik kg '
        'kütleli bir kayık ${_n(v0)} m/s hızla ilerliyor. Kişi kayıktan $yon, '
        'kıyıya göre ${_n(u)} m/s hızla yatay olarak atlıyor. Suyun direnci '
        'önemsiz olduğuna göre kişi atladıktan sonra kayığın hızının büyüklüğü '
        'kaç m/s olur?',
    hiz.abs(),
    [yanlis.abs(), v0, toplam / kayik, m * u / kayik],
    'Momentum korunur: ($kayik + $m)·${_n(v0)} = $kayik·V '
        '${geri ? '−' : '+'} $m·${_n(u)}. Buradan V = (${_n(toplam)} '
        '${geri ? '+' : '−'} ${_n(m * u)}) / $kayik = ${_n(hiz)} m/s olur.'
        '${hiz < 0 ? ' Eksi işaret kayığın ters yönde hareket ettiğini gösterir; '
                  'hızının büyüklüğü ${_n(-hiz)} m/s olur.' : ''}',
    unit: 'm/s',
  );
}

AdvancedItem _parcalanma(int a, int b, int k) {
  final v = b % 4;
  final n = a + 25 * (b ~/ 4) + 125 * k; // 0 … 374
  final (m1, m2, v0, v1) = _yay(_parcalar[v], n, 375);
  final mt = m1 + m2;
  final v2 = (mt * v0 - m1 * v1) / m2; // duran cisimde ikinci parça ters yönde
  final h2 = v2.abs();
  const duz = 'Sürtünmesiz yatay bir düzlemde';
  switch (v) {
    case 0:
      return _s(
        '$duz duran $mt kg kütleli bir cisim, içindeki küçük bir patlamayla '
            'iki parçaya ayrılıyor. $m1 kg kütleli parça $v1 m/s hızla hareket '
            'ettiğine göre $m2 kg kütleli parçanın hızı kaç m/s olur?',
        h2,
        [v1, m2 * v1 / m1, m1 * v1 / mt],
        'Patlamadan önce momentum sıfırdır; parçaların momentumları eşit '
            'büyüklükte ve zıt yönlü olur: $m1·$v1 = $m2·v₂, v₂ = ${_n(h2)} m/s.',
        unit: 'm/s',
      );
    case 1:
      final yanlis = (mt * v0 + m1 * v1) / m2;
      return _s(
        '$duz $v0 m/s hızla ilerleyen $mt kg kütleli bir cisim, içindeki '
            'küçük bir patlamayla iki parçaya ayrılıyor. $m1 kg kütleli parça '
            'aynı yönde $v1 m/s hızla ilerlediğine göre $m2 kg kütleli parçanın '
            'hızının büyüklüğü kaç m/s olur?',
        h2,
        [yanlis, v0, mt * v0 / m2, m1 * v1 / m2],
        'Momentum korunur: $mt·$v0 = $m1·$v1 + $m2·v₂. Buradan v₂ = '
            '(${mt * v0} − ${m1 * v1}) / $m2 = ${_n(v2)} m/s olur.'
            '${v2 < 0 ? ' Eksi işaret bu parçanın ters yönde hareket ettiğini '
                      'gösterir; hızının büyüklüğü ${_n(-v2)} m/s olur.' : ''}',
        unit: 'm/s',
      );
    case 2:
      return _s(
        '$duz $v0 m/s hızla ilerleyen $mt kg kütleli bir cisim, içindeki '
            'küçük bir patlamayla iki parçaya ayrılıyor. $m1 kg kütleli parça '
            'patlama anında durduğuna göre $m2 kg kütleli parçanın hızı kaç m/s '
            'olur?',
        v2,
        [v0, m2 * v0 / mt, m1 * v0 / m2],
        'Momentum korunur: $mt·$v0 = $m1·0 + $m2·v₂. Buradan v₂ = '
            '${mt * v0} / $m2 = ${_n(v2)} m/s olur.',
        unit: 'm/s',
      );
    default:
      final e = (m1 * v1 * v1 + m2 * h2 * h2) / 2;
      return _s(
        '$duz duran $mt kg kütleli bir cisim, içindeki küçük bir patlamayla '
            'iki parçaya ayrılıyor. $m1 kg kütleli parça $v1 m/s hızla hareket '
            'ettiğine göre patlamada parçalara aktarılan toplam kinetik enerji '
            'kaç J olur?',
        e,
        [m1 * v1 * v1 / 2, m1 * v1 * v1, mt * v1 * v1 / 2],
        'Momentum korunumundan $m1·$v1 = $m2·v₂, v₂ = ${_n(h2)} m/s olur. '
            'Toplam kinetik enerji ½·$m1·$v1² + ½·$m2·${_n(h2)}² = '
            '${_n(m1 * v1 * v1 / 2)} + ${_n(m2 * h2 * h2 / 2)} = ${_n(e)} J '
            'bulunur.',
        unit: 'J',
      );
  }
}

final _f05 = lmAile(
  'fz_patlama',
  'Patlama ve geri tepmede momentumun korunumu',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) => switch (c % 3) {
    0 => _geriTepme(a, b, c ~/ 3),
    1 => _kayiktanAtlama(a, b, c ~/ 3),
    _ => _parcalanma(a, b, c ~/ 3),
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ──────────────── 6 · Eylemsizlik momenti ve açısal momentum ────────────────

/// Santimetreyi metre olarak yazar.
String _m(int cm) => _n(cm / 100);

/// Noktasal cisimlerin eylemsizlik momenti ve açısal momentumu.
AdvancedItem _eylemsizlik(int a, int b, int k) {
  final v = b % 4, q = b ~/ 4; // q: 0 … 4
  final m1 = 1 + a % 5, m2 = 1 + a ~/ 5; // 1 … 5 kg
  double terim(int m, int cm) => m * cm * cm / 10000;
  String toplam(List<(int, int)> ler) =>
      'I = ${ler.map((e) => '${e.$1}·${_m(e.$2)}²').join(' + ')} = '
      '${ler.map((e) => _n(terim(e.$1, e.$2))).join(' + ')}';
  const giris = 'Ağırlığı önemsiz bir çubuk üzerine';
  String ikiKutle() => m1 == m2
      ? 'her birinin kütlesi $m1 kg olan iki noktasal cisim'
      : 'kütleleri $m1 kg ve $m2 kg olan iki noktasal cisim';
  // Anahtar kökteki bir sayıya ya da yaygın bir yanlış yolun sonucuna eşit
  // çıkarsa bir uzaklık, olağan aralığın dışındaki bir değere taşınır; bu
  // değerler başka vakada kullanılmadığından kök yine tek kalır.
  bool cakisir(num x, List<num> ler) => _icinde(x, ler);
  switch (v) {
    case 0:
      final r1 = 10 * (1 + q); // 10 … 50 cm
      var r2 = 10 * (6 + k); // 60 … 90 cm (yedek: 100 … 130 cm)
      double i0() => terim(m1, r1) + terim(m2, r2);
      List<double> yanlis() => [
        (m1 * r1 + m2 * r2) / 100,
        i0() * 10000,
        (m1 + m2) * (r1 + r2) * (r1 + r2) / 40000,
      ];
      for (
        var d = 0;
        d < 2 && cakisir(i0(), [m1, m2, r1, r2, ...yanlis()]);
        d++
      ) {
        r2 += 40; // 100 … 130, sonra 140 … 170 cm
      }
      final i = i0();
      return _s(
        '$giris ${ikiKutle()}, çubuğa dik olan dönme ekseninden sırasıyla '
            '$r1 cm ve $r2 cm uzaklığa yerleştirilmiştir. Sistemin bu eksene göre '
            'eylemsizlik momenti kaç kg·m² olur?',
        i,
        yanlis(),
        'Noktasal cisimlerden oluşan sistemin eylemsizlik momenti I = Σ m·r² '
            'olur. Uzaklıklar metreye çevrilirse ${toplam([(m1, r1), (m2, r2)])} = '
            '${_n(i)} kg·m² bulunur.',
      );
    case 1:
      var x = 10 * (1 + q); // eksenin K cismine uzaklığı (yedek: 60 … 100 cm)
      final y = 10 * (6 + k); // eksenin L cismine uzaklığı
      double i0() => terim(m1, x) + terim(m2, y);
      List<double> yanlis() => [
        terim(m1, x) + terim(m2, x + y),
        (m1 + m2) * (x + y) * (x + y) / 40000,
        i0() * 10000,
      ];
      for (
        var d = 0;
        d < 2 && cakisir(i0(), [x + y, m1, m2, x, ...yanlis()]);
        d++
      ) {
        x += 50; // 60 … 100, sonra 110 … 150 cm
      }
      final boy = x + y, i = i0();
      return _s(
        'Uzunluğu $boy cm olan ağırlığı önemsiz bir çubuğun uçlarına kütlesi '
            '$m1 kg olan K ve kütlesi $m2 kg olan L noktasal cisimleri takılmıştır. '
            'Çubuk, K cisminden $x cm uzaktaki bir noktadan geçen ve çubuğa dik '
            'olan bir eksen etrafında döndürülüyor. Sistemin bu eksene göre '
            'eylemsizlik momenti kaç kg·m² olur?',
        i,
        yanlis(),
        'L cismi eksenden $boy − $x = $y cm uzaktadır. Uzaklıklar metreye '
            'çevrilirse ${toplam([(m1, x), (m2, y)])} = ${_n(i)} kg·m² bulunur.',
      );
    case 2:
      final m3 = 1 + k; // 1 … 4 kg
      var r1 = 10 * (1 + q); // 10 … 50 cm (yedek: 60 … 100 cm)
      double i0() => terim(m1, r1) + terim(m2, r1 + 20) + terim(m3, r1 + 40);
      List<double> yanlis() => [
        (m1 * r1 + m2 * (r1 + 20) + m3 * (r1 + 40)) / 100,
        i0() * 10000,
        (m1 + m2 + m3) * (r1 + 20) * (r1 + 20) / 10000,
      ];
      for (
        var d = 0;
        d < 2 && cakisir(i0(), [m1, m2, m3, r1, r1 + 20, r1 + 40, ...yanlis()]);
        d++
      ) {
        r1 += 50; // 60 … 100, sonra 110 … 150 cm
      }
      final r2 = r1 + 20, r3 = r1 + 40, i = i0();
      final kutleler = m1 == m2 && m2 == m3
          ? 'her birinin kütlesi $m1 kg olan'
          : 'kütleleri $m1 kg, $m2 kg ve $m3 kg olan';
      return _s(
        '$giris $kutleler üç noktasal cisim, çubuğa dik olan dönme ekseninden '
            'sırasıyla $r1 cm, $r2 cm ve $r3 cm uzaklığa yerleştirilmiştir. '
            'Sistemin bu eksene göre eylemsizlik momenti kaç kg·m² olur?',
        i,
        yanlis(),
        'I = Σ m·r² bağıntısında uzaklıklar metreye çevrilirse '
            '${toplam([(m1, r1), (m2, r2), (m3, r3)])} = ${_n(i)} kg·m² bulunur.',
      );
    default:
      var r1 = 10 * (1 + q); // 10 … 50 cm (yedek: 110 … 150 cm)
      final r2 = 10 * (6 + q); // 60 … 100 cm
      final w = const [2, 4, 5, 10][k]; // rad/s
      double l0() => (terim(m1, r1) + terim(m2, r2)) * w;
      List<double> yanlis() => [
        l0() / w,
        l0() * w,
        (m1 * r1 + m2 * r2) * w / 100,
      ];
      for (
        var d = 0;
        d < 2 && cakisir(l0(), [m1, m2, r1, r2, w, ...yanlis()]);
        d++
      ) {
        r1 += 100; // 110 … 150, sonra 210 … 250 cm
      }
      final i = terim(m1, r1) + terim(m2, r2), l = l0();
      return _s(
        '$giris ${ikiKutle()}, çubuğa dik olan dönme ekseninden sırasıyla '
            '$r1 cm ve $r2 cm uzaklığa yerleştirilmiştir. Sistem bu eksen '
            'etrafında $w rad/s büyüklüğünde açısal hızla dönmektedir. Sistemin '
            'açısal momentumunun büyüklüğü kaç kg·m²/s olur?',
        l,
        yanlis(),
        'Eylemsizlik momenti ${toplam([(m1, r1), (m2, r2)])} = ${_n(i)} kg·m² '
            'olur. Açısal momentum L = I·ω = ${_n(i)}·$w = ${_n(l)} kg·m²/s bulunur.',
      );
  }
}

/// Patenci: (kollar açıkken I, kollar kapalıyken I, frekans ya da periyot),
/// hepsi onda bir birimle. Yeni değer iki ondalıkta kesin.
List<(int, int, int)> _patenci(bool periyot) => [
  for (var i1 = 20; i1 <= 72; i1++)
    for (var i2 = 8; i2 <= 24; i2++)
      if (2 * i2 <= i1 && 2 * i1 <= 9 * i2)
        for (var x = periyot ? 5 : 4; x <= (periyot ? 25 : 20); x++)
          if (_patenciUygun(periyot, i1, i2, x)) (i1, i2, x),
];

bool _patenciUygun(bool periyot, int i1, int i2, int x) {
  // Frekans f₂ = f₁·I₁/I₂, periyot T₂ = T₁·I₂/I₁; yüzde birimiyle tam sayı.
  final pay = periyot ? 10 * x * i2 : 10 * x * i1;
  final payda = periyot ? i1 : i2;
  if (pay % payda != 0) return false;
  final y = pay / payda / 100;
  if (periyot ? y < 0.15 : y > 6) return false;
  return !_icinde(y, [i1 / 10, i2 / 10, x / 10]);
}

final _patenciF = _tekil(_patenci(false), (t) => (_oran(t.$1, t.$2), t.$3));
final _patenciT = _tekil(_patenci(true), (t) => (_oran(t.$1, t.$2), t.$3));

/// Dönen platforma kum torbası: (I₀ onda bir kg·m², m kg, r dm, ω₁ rad/s).
final _platform = _tekil([
  for (var i0 = 10; i0 <= 100; i0++)
    for (var m = 1; m <= 10; m++)
      for (var r = 5; r <= 20; r += 5)
        for (var w = 1; w <= 12; w++)
          if (_platformUygun(i0, m, r, w)) (i0, m, r, w),
], (t) => (_oran(10 * t.$1, t.$2 * t.$3 * t.$3), t.$4));

bool _platformUygun(int i0, int m, int r, int w) {
  final payda = 10 * i0 + m * r * r; // 100·(I₀ + m·r²)
  if (1000 * w * i0 % payda != 0) return false;
  final w2 = 10 * w * i0 / payda;
  if (w2 < 0.2) return false;
  final ib = i0 / 10, rm = r / 10;
  return !_icinde(w2, [
    ib,
    m,
    rm,
    w,
    w * (ib + m * rm * rm) / ib,
    w * ib / (ib + m * rm),
    w * ib / (m * rm * rm),
  ]);
}

/// Çubuktaki boncuklar: (r₁ cm, r₂ cm, ω₁ rad/s).
final _boncuk = _tekil([
  for (var r1 = 10; r1 <= 60; r1 += 5)
    for (var r2 = 10; r2 <= 60; r2 += 5)
      if (r1 != r2)
        for (var w = 1; w <= 20; w++)
          if (100 * w * r1 * r1 % (r2 * r2) == 0 &&
              5 * w * r1 * r1 >= r2 * r2 &&
              w * r1 * r1 <= 60 * r2 * r2 &&
              !_icinde(w * r1 * r1 / (r2 * r2), [
                r1,
                r2,
                w,
                w * r1 / r2,
                w * r2 * r2 / (r1 * r1),
              ]))
            (r1, r2, w),
], (t) => (_oran(t.$1, t.$2), t.$3));

/// Açısal momentumun korunumu: patenci, platform ve boncuklar.
AdvancedItem _acisalKorunum(int a, int b, int k) {
  final v = b % 4;
  final n = a + 25 * (b ~/ 4) + 125 * k; // 0 … 374
  const korunur =
      'Dış tork olmadığından açısal momentum korunur: I₁·ω₁ = I₂·ω₂.';
  switch (v) {
    case 0:
      final (i1, i2, f10) = _yay(_patenciF, n, 375);
      final f2 = f10 * i1 / (10 * i2);
      return _s(
        'Buz üzerinde kendi ekseni etrafında dönen bir patencinin kolları '
            'açıkken eylemsizlik momenti ${_n(i1 / 10)} kg·m², dönme frekansı '
            '${_n(f10 / 10)} Hz olarak ölçülüyor. Patenci kollarını kapatınca '
            'eylemsizlik momenti ${_n(i2 / 10)} kg·m² oluyor. Sürtünmeler '
            'önemsiz olduğuna göre patencinin yeni dönme frekansı kaç Hz olur?',
        f2,
        [f10 * i2 / (10 * i1), f10 / 10, f10 * i1 * i1 / (10 * i2 * i2)],
        '$korunur ω = 2·π·f olduğundan I₁·f₁ = I₂·f₂ yazılır: '
            'f₂ = ${_n(i1 / 10)}·${_n(f10 / 10)} / ${_n(i2 / 10)} = ${_n(f2)} Hz.',
        unit: 'Hz',
      );
    case 1:
      final (i1, i2, t10) = _yay(_patenciT, n, 375);
      final t2 = t10 * i2 / (10 * i1);
      return _s(
        'Buz üzerinde kendi ekseni etrafında dönen bir patencinin kolları '
            'açıkken eylemsizlik momenti ${_n(i1 / 10)} kg·m², bir tam dönüş süresi '
            '${_n(t10 / 10)} s olarak ölçülüyor. Patenci kollarını kapatınca '
            'eylemsizlik momenti ${_n(i2 / 10)} kg·m² oluyor. Sürtünmeler '
            'önemsiz olduğuna göre patencinin yeni dönme periyodu kaç s olur?',
        t2,
        [t10 * i1 / (10 * i2), t10 / 10, t10 * i2 * i2 / (10 * i1 * i1)],
        '$korunur ω = 2·π / T olduğundan I₁ / T₁ = I₂ / T₂ yazılır: '
            'T₂ = ${_n(t10 / 10)}·${_n(i2 / 10)} / ${_n(i1 / 10)} = ${_n(t2)} s.',
        unit: 's',
      );
    case 2:
      final (i0, m, r, w) = _yay(_platform, n, 375);
      final ib = i0 / 10, rm = r / 10, ek = m * rm * rm;
      final w2 = w * ib / (ib + ek);
      return _s(
        'Sürtünmesiz düşey bir eksen etrafında $w rad/s açısal hızla dönen ve '
            'bu eksene göre eylemsizlik momenti ${_n(ib)} kg·m² olan yatay bir '
            'platformun üzerine, eksenden ${_n(rm)} m uzaktaki bir noktaya $m kg '
            'kütleli bir kum torbası yavaşça bırakılıyor ve torba platformla '
            'birlikte dönmeye başlıyor. Torba noktasal kabul edildiğine göre '
            'platformun yeni açısal hızı kaç rad/s olur?',
        w2,
        [w * (ib + ek) / ib, w * ib / (ib + m * rm), w * ib / ek],
        '$korunur Torba eklenince eylemsizlik momenti ${_n(ib)} + '
            '$m·${_n(rm)}² = ${_n(ib + ek)} kg·m² olur. ω₂ = ${_n(ib)}·$w / '
            '${_n(ib + ek)} = ${_n(w2)} rad/s bulunur.',
      );
    default:
      final (r1, r2, w) = _yay(_boncuk, n, 375);
      final w2 = w * r1 * r1 / (r2 * r2);
      return _s(
        'Sürtünmesiz düşey bir eksen etrafında dönebilen, ağırlığı önemsiz '
            'yatay bir çubuk üzerinde, eksenin iki yanında ve eksenden $r1 cm '
            'uzakta eşit kütleli iki boncuk bulunuyor. Çubuk $w rad/s açısal hızla '
            'dönerken boncuklar çubuk üzerinde kayarak eksenden $r2 cm uzağa '
            'geliyor. Boncuklar noktasal kabul edildiğine göre çubuğun yeni açısal '
            'hızı kaç rad/s olur?',
        w2,
        [w * r1 / r2, w * r2 * r2 / (r1 * r1), w],
        '$korunur Boncukların kütlesi m ise I = 2·m·r² olduğundan '
            'r₁²·ω₁ = r₂²·ω₂ olur: ω₂ = $w·$r1² / $r2² = ${_n(w2)} rad/s.',
      );
  }
}

/// İpi delikten çekilen cisim: (r₁ cm, r₂ cm, v₁ onda bir m/s).
final _delikHiz = _tekil([
  for (var r1 = 40; r1 <= 150; r1 += 10)
    for (var r2 = 20; r2 < r1; r2 += 10)
      for (var v = 5; v <= 40; v++)
        if (10 * v * r1 % r2 == 0 &&
            v * r1 <= 150 * r2 &&
            !_icinde(v * r1 / (10 * r2), [
              r1,
              r2,
              v / 10,
              v * r2 / (10 * r1),
              v * r1 * r1 / (10 * r2 * r2),
            ]))
          (r1, r2, v),
], (t) => (_oran(t.$1, t.$2), t.$3));

/// (r₁ cm, r₂ cm, ω₁ rad/s); yeni açısal hız iki ondalıkta kesin.
final _delikAcisal = _tekil([
  for (var r1 = 20; r1 <= 200; r1 += 5)
    for (var r2 = 10; r2 < r1; r2 += 5)
      for (var w = 1; w <= 15; w++)
        if (100 * w * r1 * r1 % (r2 * r2) == 0 &&
            w * r1 * r1 <= 80 * r2 * r2 &&
            !_icinde(w * r1 * r1 / (r2 * r2), [r1, r2, w, w * r1 / r2]))
          (r1, r2, w),
], (t) => (_oran(t.$1, t.$2), t.$3));

/// (r₁ cm, v₁ m/s, v₂ m/s); yeni yarıçap iki ondalıkta kesin.
final _delikYaricap = _tekil([
  for (var r1 = 20; r1 <= 150; r1 += 5)
    for (var v1 = 1; v1 <= 10; v1++)
      for (var v2 = v1 + 1; v2 <= 15; v2++)
        if (100 * r1 * v1 % v2 == 0 &&
            r1 * v1 >= 10 * v2 &&
            !_icinde(r1 * v1 / v2, [r1, v1, v2, r1 * v2 / v1]))
          (r1, v1, v2),
], (t) => (t.$1, _oran(t.$2, t.$3)));

/// Yatay masadaki delikten geçen ipe bağlı cisim.
AdvancedItem _ipDelik(int a, int b, int k) {
  final v = b % 4;
  final n = a + 25 * (b ~/ 4) + 125 * k; // 0 … 374
  const masa =
      'Sürtünmesiz yatay bir masanın ortasındaki küçük bir delikten geçen ipe '
      'bağlı küçük bir cisim, deliğin çevresinde';
  const cekilir = 'İp delikten aşağı doğru yavaşça çekilerek yörünge yarıçapı';
  const korunur =
      'İpin cisme uyguladığı kuvvet deliğe doğru olduğundan tork oluşturmaz; '
      'açısal momentum korunur.';
  switch (v) {
    case 0:
      final (r1, r2, v10) = _yay(_delikHiz, n, 375);
      final v2 = v10 * r1 / (10 * r2);
      return _s(
        '$masa $r1 cm yarıçaplı çembersel yörüngede ${_n(v10 / 10)} m/s hızla '
            'dolanıyor. $cekilir $r2 cm yapılırsa cismin hızı kaç m/s olur?',
        v2,
        [v10 * r2 / (10 * r1), v10 * r1 * r1 / (10 * r2 * r2), v10 / 10],
        '$korunur m·v₁·r₁ = m·v₂·r₂ eşitliğinden v₂ = ${_n(v10 / 10)}·$r1 / '
            '$r2 = ${_n(v2)} m/s bulunur.',
        unit: 'm/s',
      );
    case 1:
      final (r1, r2, w) = _yay(_delikAcisal, n, 375);
      final w2 = w * r1 * r1 / (r2 * r2);
      return _s(
        '$masa $r1 cm yarıçaplı çembersel yörüngede $w rad/s açısal hızla '
            'dolanıyor. $cekilir $r2 cm yapılırsa cismin açısal hızı kaç rad/s '
            'olur?',
        w2,
        [w * r1 / r2, w * r2 * r2 / (r1 * r1), w],
        '$korunur L = m·r²·ω olduğundan r₁²·ω₁ = r₂²·ω₂ olur: ω₂ = $w·$r1² / '
            '$r2² = ${_n(w2)} rad/s.',
      );
    case 2:
      final m10 = 1 + a % 10; // 0,1 … 1 kg
      final hiz = 1 + a ~/ 10 + 3 * k; // 1 … 9 m/s
      // r = 1 m alınmaz: m·v·r ile m·v aynı sayı olurdu.
      final r0 = 2 + b ~/ 4 * 2 + (a % 2);
      // v·r = 1 iken açısal momentum sayıca kütleye eşit olurdu.
      final r10 = r0 == 10 ? 12 : (hiz * r0 == 10 ? 13 : r0); // 20 … 130 cm
      final l = m10 * hiz * r10 / 100;
      return _s(
        '$masa ${r10 * 10} cm yarıçaplı çembersel yörüngede $hiz m/s hızla '
            'dolanıyor. Cismin kütlesi ${_n(m10 / 10)} kg olduğuna göre deliğe '
            'göre açısal momentumunun büyüklüğü kaç kg·m²/s olur?',
        l,
        [l * 100, m10 * hiz / 10, m10 * hiz * r10 * r10 / 1000],
        'Çembersel yörüngedeki noktasal cismin açısal momentumu L = m·v·r '
            'olur. Yarıçap ${_n(r10 / 10)} m olduğundan L = ${_n(m10 / 10)}·$hiz·'
            '${_n(r10 / 10)} = ${_n(l)} kg·m²/s bulunur.',
      );
    default:
      final (r1, v1, v2) = _yay(_delikYaricap, n, 375);
      final r2 = r1 * v1 / v2;
      return _s(
        '$masa $r1 cm yarıçaplı çembersel yörüngede $v1 m/s hızla dolanıyor. '
            'İp delikten aşağı doğru yavaşça çekiliyor ve cismin hızı $v2 m/s '
            'oluyor. Cismin yeni yörünge yarıçapı kaç cm olur?',
        r2,
        [r1 * v2 / v1, r1 * v1 * v1 / (v2 * v2), r1 - v2 + v1],
        '$korunur m·v₁·r₁ = m·v₂·r₂ eşitliğinden r₂ = $r1·$v1 / $v2 = '
            '${_n(r2)} cm bulunur.',
        unit: 'cm',
      );
  }
}

final _f06 = lmAile(
  'fz_acisal_momentum',
  'Eylemsizlik momenti ve açısal momentumun korunumu',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) => switch (c % 3) {
    0 => _eylemsizlik(a, b, c ~/ 3),
    1 => _acisalKorunum(a, b, c ~/ 3),
    _ => _ipDelik(a, b, c ~/ 3),
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ───────────────────────────── 7 · Kepler yasaları ────────────────────────────

/// Yarıçap oranı tam kare olan (p, q) ikilileri: r₂/r₁ = (q/p)², T₂/T₁ = (q/p)³.
const _keplerOran = <(int, int)>[
  (1, 2),
  (2, 1),
  (1, 3),
  (3, 1),
  (2, 3),
  (3, 2),
  (1, 4),
  (4, 1),
  (3, 4),
  (4, 3),
  (2, 5),
  (5, 2),
  (1, 5),
  (5, 1),
  (3, 5),
  (5, 3),
  (4, 5),
  (5, 4),
  (1, 6),
  (6, 1),
];

/// Taranan alan kesirleri (1/2 yok: tümleyeni kendisine eşit olurdu).
const _alanKesri = <(int, int)>[
  (1, 8),
  (3, 8),
  (5, 8),
  (1, 5),
  (2, 5),
  (3, 5),
  (4, 5),
  (1, 4),
  (3, 4),
  (1, 6),
  (5, 6),
  (1, 10),
  (3, 10),
  (7, 10),
  (9, 10),
  (1, 12),
  (5, 12),
  (7, 12),
  (1, 3),
  (2, 3),
  (1, 9),
  (2, 9),
  (4, 9),
  (1, 15),
  (2, 15),
  (4, 15),
  (1, 20),
  (3, 20),
  (7, 20),
  (9, 20),
];

/// Yıldıza en yakın ve en uzak konum uzaklıklarının oranı (p < q).
const _yakinUzak = <(int, int)>[
  (2, 3),
  (3, 4),
  (4, 5),
  (3, 5),
  (5, 6),
  (5, 7),
  (6, 7),
  (7, 8),
  (5, 8),
  (7, 9),
];

String _ikiGezegen(String bilinen) =>
    'Bir yıldızın çevresinde çembersel yörüngelerde dolanan X ve Y '
    'gezegenlerinden $bilinen';

AdvancedItem _keplerUcuncu(int a, int b, int k, bool periyotSor) {
  final (p, q) = _keplerOran[b];
  // Oran sabitken yalnız bilinen değer (periyot sorusunda T₁, yarıçap
  // sorusunda r₁) hesabı değiştirir; onu a ve k birebir belirler. Öbür
  // gezegen çiftinin ortak ölçeği yalnız bağlamdır.
  final j = 1 + a + 25 * k; // 1 … 100
  final ince = math.max(p, q) >= 4; // büyük oranlarda küçük birim
  final birim = ince ? 100 : 10;
  // Ortak ölçek anahtar kökteki bir sayıya eşit çıkmayacak biçimde 1 … 5
  // arasından seçilir.
  var olcek = 1 + (a + k) % 5;
  var r1 = 0.0, r2 = 0.0, t1 = 0.0, t2 = 0.0;
  for (var deneme = 0; deneme < 5; deneme++) {
    final t = periyotSor ? j : olcek, s = periyotSor ? olcek : j;
    r1 = p * p * s / (periyotSor ? 10 : birim);
    r2 = q * q * s / (periyotSor ? 10 : birim);
    t1 = p * p * p * t / (periyotSor ? birim : 10);
    t2 = q * q * q * t / (periyotSor ? birim : 10);
    final kokte = periyotSor ? [r1, r2, t1] : [t1, t2, r1];
    if (!_icinde(periyotSor ? t2 : r2, kokte)) break;
    olcek = olcek % 5 + 1;
  }
  const not = '(AB: astronomik birim)';
  const tanim =
      'X gezegeni için periyot ve yarıçap T₁ ve r₁, Y gezegeni için T₂ ve r₂ '
      'olsun. Kepler yasasına göre aynı yıldızın gezegenleri için T² / r³ '
      'sabit olduğundan (T₂ / T₁)² = (r₂ / r₁)³ olur.';
  final kare = kesir(q * q, p * p), kup = kesir(q * q * q, p * p * p);
  final altinci = kesir(q * q * q * q * q * q, p * p * p * p * p * p);
  if (periyotSor) {
    return _s(
      '${_ikiGezegen('X gezegeninin yörünge yarıçapı ${_n(r1)} AB, Y '
          'gezegenininki ${_n(r2)} AB olarak veriliyor.')} X gezegeninin dolanım '
          'periyodu ${_n(t1)} yıl olduğuna göre Y gezegeninin dolanım periyodu '
          'kaç yıl olur? $not',
      t2,
      [t1 * q * q / (p * p), t1 * q / p, t1 * q * q * q * q / (p * p * p * p)],
      '$tanim r₂ / r₁ = $kare olduğundan (T₂ / T₁)² = $altinci ve '
          'T₂ / T₁ = $kup bulunur: T₂ = ${_n(t1)}·$kup = ${_n(t2)} yıl.',
      unit: 'yıl',
    );
  }
  return _s(
    '${_ikiGezegen('X gezegeninin dolanım periyodu ${_n(t1)} yıl, Y '
        'gezegenininki ${_n(t2)} yıl olarak ölçülüyor.')} X gezegeninin '
        'yörünge yarıçapı ${_n(r1)} AB olduğuna göre Y gezegeninin yörünge '
        'yarıçapı kaç AB olur? $not',
    r2,
    [r1 * q * q * q / (p * p * p), r1 * q / p],
    '$tanim T₂ / T₁ = $kup olduğundan (r₂ / r₁)³ = $altinci ve r₂ / r₁ = '
        '$kare bulunur: r₂ = ${_n(r1)}·$kare = ${_n(r2)} AB.',
  );
}

AdvancedItem _keplerIkinci(int a, int b, int k) {
  if (b.isEven) {
    final (p, q) = _alanKesri[b ~/ 2 + 10 * k];
    final t = 72 * (a + 4); // 288 … 2016 gün
    final cevap = t * p / q;
    return _s(
      'Bir yıldızın çevresinde eliptik yörüngede dolanan bir gezegenin dolanım '
          'periyodu $t gündür. Gezegeni yıldıza birleştiren doğru parçası, '
          'yörüngenin sınırladığı alanın $p/$q kadarını kaç günde tarar?',
      cevap,
      [t * (q - p) / q, t * p / (2 * q)],
      'Kepler yasasına göre gezegeni yıldıza birleştiren doğru parçası eşit '
          'sürelerde eşit alanlar tarar; taranan alan geçen süreyle doğru '
          'orantılıdır. Alanın tamamı $t günde tarandığından $p/$q kadarı '
          '$t·$p/$q = ${_n(cevap)} günde taranır.',
      unit: 'gün',
    );
  }
  final (p, q) = _yakinUzak[b ~/ 2];
  final ry = p * (k + 1) / 10, ru = q * (k + 1) / 10; // AB
  final w = (a + 5) / 5; // 1 … 5,8 km/s
  final vy = q * w, vu = p * w;
  return _s(
    'Bir yıldızın çevresinde eliptik yörüngede dolanan bir gezegenin yıldıza '
        'en yakın olduğu konumdaki uzaklığı ${_n(ry)} AB, en uzak olduğu '
        'konumdaki uzaklığı ${_n(ru)} AB olarak veriliyor. Gezegen en yakın '
        'konumdan ${_n(vy)} km/s hızla geçtiğine göre en uzak konumdan kaç km/s '
        'hızla geçer? (AB: astronomik birim)',
    vu,
    [vy * ru / ry, vy * ry * ry / (ru * ru), vy],
    'Kepler yasasına göre alan hızı sabittir. En yakın ve en uzak konumlarda '
        'hız yıldıza uzaklığa dik olduğundan v₁·r₁ = v₂·r₂ yazılır: v₂ = '
        '${_n(vy)}·${_n(ry)} / ${_n(ru)} = ${_n(vu)} km/s.',
  );
}

final _f07 = lmAile(
  'fz_kepler',
  'Kepler yasaları: periyot, yarıçap ve alan hızı',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.anlama,
  (a, b, c) => switch (c % 3) {
    0 => _keplerUcuncu(a, b, c ~/ 3, true),
    1 => _keplerUcuncu(a, b, c ~/ 3, false),
    _ => _keplerIkinci(a, b, c ~/ 3),
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ───────────────────────────── 8 · Özel görelilik ────────────────────────────

/// (hız, β yüzde, √(1 − β²) yüzde): γ değeri kesin çıkan hızlar.
const _gorelilik = <(String, int, int)>[
  ('0,6c', 60, 80),
  ('0,8c', 80, 60),
  ('0,28c', 28, 96),
  ('0,96c', 96, 28),
];

String _kokNot(int beta, int kok) =>
    '(√(1 − ${_n(beta / 100)}²) = ${_n(kok / 100)} alınız.)';

AdvancedItem _zamanGenislemesi(int a, int b, int k) {
  final (hiz, beta, kok) = _gorelilik[b % 4];
  // n = 2 alınmaz: verilen süre 1 olunca anahtar kökteki kök değerine eşit
  // çıkardı.
  final n = _atla(1 + a + 25 * (b ~/ 4), const {2}); // 1 … 126
  final ileri = k.isEven, parcacik = k >= 2;
  final uzun = n / 2; // gözlemcinin ölçtüğü süre
  final oz = uzun * kok / 100; // öz süre
  final not = _kokNot(beta, kok);
  final birim = parcacik ? 'µs' : 'yıl';
  final kokYazi = _n(kok / 100);
  if (ileri) {
    return _s(
      parcacik
          ? 'Kendi durgun çerçevesinde ölçülen ortalama ömrü ${_n(oz)} µs olan '
                'kararsız bir parçacık, laboratuvara göre $hiz hızıyla hareket '
                'ediyor. Laboratuvardaki gözlemciye göre parçacığın ortalama '
                'ömrü kaç µs olur? $not'
          : "Dünya'ya göre $hiz hızıyla hareket eden bir uzay aracındaki saat, "
                'bir yolculuğun ${_n(oz)} yıl sürdüğünü gösteriyor. Bu yolculuk '
                "Dünya'daki bir gözlemciye göre kaç yıl sürer? $not",
      uzun,
      [oz * kok / 100, oz * 100 / beta, oz * 100 / (100 - beta)],
      'Hareketli saat yavaş işler: Δt = Δt₀ / √(1 − v²/c²) = ${_n(oz)} / '
      '$kokYazi = ${_n(uzun)} $birim.',
      unit: parcacik ? '' : 'yıl',
    );
  }
  return _s(
    parcacik
        ? 'Laboratuvara göre $hiz hızıyla hareket eden kararsız bir parçacığın '
              'ortalama ömrü laboratuvarda ${_n(uzun)} µs olarak ölçülüyor. '
              'Parçacığın kendi durgun çerçevesinde ölçülen ortalama ömrü kaç '
              'µs olur? $not'
        : "Dünya'ya göre $hiz hızıyla hareket eden bir uzay aracının yolculuğu "
              "Dünya'daki bir gözlemciye göre ${_n(uzun)} yıl sürüyor. Bu "
              'yolculuk uzay aracındaki saate göre kaç yıl sürer? $not',
    oz,
    [uzun * 100 / kok, uzun * beta / 100, uzun * (100 - beta) / 100],
    'Öz süre en kısa süredir: Δt₀ = Δt·√(1 − v²/c²) = ${_n(uzun)}·$kokYazi = '
    '${_n(oz)} $birim.',
    unit: parcacik ? '' : 'yıl',
  );
}

AdvancedItem _boyKisalmasi(int a, int b, int k) {
  final s = b % 4;
  final (hiz, beta, kok) = _gorelilik[s];
  final n = 1 + a + 25 * (b ~/ 4); // 1 … 125
  final not = _kokNot(beta, kok);
  final kokYazi = _n(kok / 100);
  // 0,6c ve 0,8c için çift n değerlerinde ters soru (ölçülen boydan öz boy).
  final ters = s < 2 && n.isEven;
  final birim = k == 2 ? 'km' : 'm';
  // Ters soruda ölçülen uzunluk, öz uzunluk kesin çıkacak biçimde seçilir.
  final olcu = s == 0
      ? const [16, 60, 12][k] + 2 * n
      : 3 * (const [6, 20, 4][k] + n);
  final oz = ters
      ? olcu * 100 / kok
      : (const [20, 100, 10][k] + const [2, 4, 2][k] * n).toDouble();
  final kisa = ters ? olcu.toDouble() : oz * kok / 100;
  final (ileriKok, tersKok) = switch (k) {
    0 => (
      'Durgun hâldeki boyu ${_n(oz)} m olan bir uzay aracı, Dünya\'ya göre '
          '$hiz hızıyla hareket ediyor. Dünya\'daki bir gözlemci aracın '
          'hareket doğrultusundaki boyunu kaç m ölçer? $not',
      'Dünya\'ya göre $hiz hızıyla hareket eden bir uzay aracının hareket '
          'doğrultusundaki boyu, Dünya\'daki bir gözlemci tarafından '
          '${_n(kisa)} m ölçülüyor. Aracın durgun hâldeki boyu kaç m olur? $not',
    ),
    1 => (
      'Kendi çerçevesinde ölçülen uzunluğu ${_n(oz)} m olan bir uzay '
          'istasyonunun yanından, istasyona göre $hiz hızıyla bir uzay gemisi '
          'geçiyor. Gemideki gözlemciye göre istasyonun hareket doğrultusundaki '
          'uzunluğu kaç m olur? $not',
      'Bir uzay istasyonuna göre $hiz hızıyla hareket eden bir uzay '
          'gemisindeki gözlemci, istasyonun hareket doğrultusundaki uzunluğunu '
          '${_n(kisa)} m ölçüyor. İstasyonun kendi çerçevesinde ölçülen '
          'uzunluğu kaç m olur? $not',
    ),
    _ => (
      'Birbirine göre durgun iki uzay işaret istasyonu arasındaki uzaklık, '
          'istasyonların çerçevesinde ${_n(oz)} km olarak ölçülüyor. '
          'İstasyonları birleştiren doğru boyunca istasyonlara göre $hiz '
          'hızıyla giden bir uzay aracındaki gözlemciye göre bu uzaklık kaç km '
          'olur? $not',
      'Birbirine göre durgun iki uzay işaret istasyonunu birleştiren doğru '
          'boyunca istasyonlara göre $hiz hızıyla giden bir uzay aracındaki '
          'gözlemci, istasyonlar arasındaki uzaklığı ${_n(kisa)} km ölçüyor. '
          'Bu uzaklık istasyonların çerçevesinde kaç km olur? $not',
    ),
  };
  if (!ters) {
    return _s(
      ileriKok,
      kisa,
      [oz * 100 / kok, oz * beta / 100, oz * (100 - beta) / 100],
      'Hareket doğrultusundaki uzunluk kısalır: L = L₀·√(1 − v²/c²) = '
      '${_n(oz)}·$kokYazi = ${_n(kisa)} $birim.',
      unit: birim,
    );
  }
  return _s(
    tersKok,
    oz,
    [kisa * kok / 100, kisa * 100 / beta, kisa * 100 / (100 - beta)],
    'L = L₀·√(1 − v²/c²) bağıntısından L₀ = ${_n(kisa)} / $kokYazi = '
    '${_n(oz)} $birim bulunur.',
    unit: birim,
  );
}

AdvancedItem _yildizYolculugu(int a, int b, int k) {
  final (hiz, beta, kok) = _gorelilik[b % 4];
  final n = 1 + a + 25 * (b ~/ 4); // 1 … 125
  final not = _kokNot(beta, kok);
  final kokYazi = _n(kok / 100);
  if (k < 2) {
    final t = 14 + n; // Dünya'ya göre süre (yıl)
    final d = t * beta / 100; // ışık yılı
    final oz = t * kok / 100;
    final giris =
        "Dünya'dan ${_n(d)} ışık yılı uzaklıktaki bir yıldıza, Dünya'ya göre "
        '$hiz hızıyla giden bir uzay aracı gönderiliyor.';
    final dunya =
        "Dünya'daki gözlemciye göre yolculuk süresi uzaklık / hız = ${_n(d)} / "
        '${_n(beta / 100)} = $t yıl olur.';
    if (k == 0) {
      return _s(
        "$giris Dünya'daki gözlemciye göre yolculuk kaç yıl sürer?",
        t,
        [oz, d * beta / 100, t * 100 / kok],
        '$dunya (Işık yılı, ışığın bir yılda aldığı yoldur.)',
        unit: 'yıl',
      );
    }
    return _s(
      '$giris Uzay aracındaki saate göre yolculuk kaç yıl sürer? $not',
      oz,
      [t, t * 100 / kok, d * kok / 100],
      '$dunya Araçtaki saat öz süreyi ölçer: Δt₀ = Δt·√(1 − v²/c²) = '
          '$t·$kokYazi = ${_n(oz)} yıl.',
      unit: 'yıl',
    );
  }
  final d = 4 + n; // ışık yılı
  final kisa = d * kok / 100;
  return _s(
    "Dünya'dan $d ışık yılı uzaklıktaki bir yıldıza, Dünya'ya göre $hiz "
        'hızıyla giden bir uzay aracındaki gözlemciye göre Dünya ile yıldız '
        'arasındaki uzaklık kaç ışık yılı olur? $not',
    kisa,
    [d * 100 / kok, d * beta / 100, d * (100 - beta) / 100],
    'Araçtaki gözlemciye göre Dünya–yıldız uzaklığı hareket doğrultusunda '
        'kısalır: L = L₀·√(1 − v²/c²) = $d·$kokYazi = ${_n(kisa)} ışık yılı.',
  );
}

final _f08 = lmAile(
  'fz_gorelilik',
  'Özel görelilik: zaman genişlemesi ve boy kısalması',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) => switch (c % 3) {
    0 => _zamanGenislemesi(a, b, c ~/ 3),
    1 => _boyKisalmasi(a, b, c ~/ 3),
    _ => _yildizYolculugu(a, b, c ~/ 3),
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ─────────────────────── 9 · Kütle-enerji eşdeğerliği ───────────────────────

const _u931 = '(1 u kütleye karşılık gelen enerji 931 MeV alınız.)';

/// On binde bir u biriminden kütle yazımı.
String _u(int onBinde) => _n(onBinde / 10000, 4);

AdvancedItem _tepkimeEnerjisi(int a, int b, int k) {
  final fisyon = k >= 2;
  final x = fisyon
      ? 2300417 + 3517 * a + 123 * b + 40000 * (k - 2)
      : 40263 + 1931 * a + 47 * b + 23000 * k;
  final j = fisyon ? 12 + (a + 2 * b + 5 * k) % 14 : 1 + (a + b + k) % 3;
  final y = x - 100 * j; // kütle farkı j/100 u
  final dm = j / 100, e = 931 * j / 100;
  return _s(
    'Bir ${fisyon ? 'fisyon (çekirdek bölünmesi)' : 'füzyon (çekirdek kaynaşması)'} '
        'tepkimesinde tepkimeye giren taneciklerin toplam kütlesi ${_u(x)} u, '
        'tepkime sonunda oluşan taneciklerin toplam kütlesi ${_u(y)} u olarak '
        'veriliyor. Bu tepkimede açığa çıkan enerji kaç MeV olur? $_u931',
    e,
    [dm, e / 10, e * 10],
    'Kütle farkı Δm = ${_u(x)} − ${_u(y)} = ${_n(dm)} u olur. Bu kütle '
        'enerjiye dönüştüğünden açığa çıkan enerji E = ${_n(dm)}·931 = ${_n(e)} '
        'MeV bulunur.',
  );
}

AdvancedItem _kutleEnerji(int a, int b, int k) {
  final v = b % 3, q = b ~/ 3; // q: 0 … 6
  const sabit = '(c = 3·10⁸ m/s; 1 kWh = 3,6·10⁶ J)';
  switch (v) {
    case 0:
      final n = 1 + a + 25 * q + 175 * k; // 1 … 525
      final mg = n / 5, e = 5000 * n; // kWh
      return _s(
        'Kütlesi ${_n(mg)} mg olan bir maddenin tamamı enerjiye dönüşebilseydi '
            'açığa çıkacak enerji kaç kWh olurdu? $sabit',
        e,
        [e * 1000, e / 1000],
        'E = m·c² = ${_n(mg)}·10⁻⁶ kg·(3·10⁸ m/s)² = ${_n(9 * mg)}·10¹⁰ J '
            'olur. 1 kWh = 3,6·10⁶ J olduğundan E = ${_n(9 * mg)}·10¹⁰ / '
            '(3,6·10⁶) = $e kWh bulunur.',
        unit: 'kWh',
      );
    case 1:
      final guc = const [100, 125, 200, 250, 400, 500, 1000][q]; // MW
      var i = 1 + a + 25 * k; // kütle: 0,1 g biriminde
      // Süre kökteki bir sayıya eşit çıkarsa kütle 7,5 g artırılır.
      if (_icinde(2500 * i / guc, [guc, i / 10, 3, 10])) i += 75;
      final saniye = 9000000 * i / guc, saat = 2500 * i / guc;
      return _s(
        'Elektrik gücü $guc MW olan bir santral, ${_n(i / 10)} g kütlenin '
            'tamamının enerjiye dönüşmesiyle elde edilecek enerjiyi kayıpsız olarak '
            'elektrik enerjisine çevirebilseydi kaç saat çalışabilirdi? '
            '(c = 3·10⁸ m/s)',
        saat,
        [saniye, saat * 60, saat / 60],
        'E = m·c² = ${_n(i / 10)}·10⁻³ kg·(3·10⁸ m/s)² = ${9 * i}·10¹² J '
            'olur. Santralin gücü $guc·10⁶ W olduğundan çalışma süresi t = E / P '
            '= ${_n(saniye)} s bulunur; bu süre ${_n(saat)} saate eşittir.',
        unit: 'saat',
      );
    default:
      // Kütle 1, 3, 3,6 ve 10 mg olmasın (kökteki sabitlerle karışmasın).
      final n = _atla(1 + a + 25 * q + 150 * k, const {10, 30, 36, 100});
      final e = 2500 * n, mg = n / 10;
      return _s(
        'Bir maddenin tamamının enerjiye dönüşmesiyle $e kWh enerji elde '
            'edilebilmesi için bu maddenin kütlesi kaç mg olmalıdır? $sabit',
        mg,
        [mg * 1000, mg / 1000],
        '$e kWh = $e·3,6·10⁶ J = ${9 * n}·10⁹ J olur. E = m·c² bağıntısından '
            'm = ${9 * n}·10⁹ / (9·10¹⁶) = $n·10⁻⁷ kg = ${_n(mg)} mg bulunur.',
        unit: 'mg',
      );
  }
}

AdvancedItem _baglanmaEnerjisi(int a, int b, int k) {
  final j = a + 25 * (b ~/ 2) + 250 * k; // 0 … 749
  if (b.isEven) {
    final kutle = 4 + j * 235 ~/ 749; // kütle numarası 4 … 239
    final toplam =
        10080 * kutle + j; // nükleonların toplam kütlesi (on binde bir u)
    // Kütle eksikliği (yüzde bir u); 1 u olmasın: anahtar kökteki 931 MeV
    // değerine eşit çıkardı.
    final d0 = (86 * kutle + 50) ~/ 100 + j % 3;
    final d100 = d0 == 100 ? 103 : d0;
    final cekirdek = toplam - 100 * d100;
    final dm = d100 / 100, e = 931 * d100 / 100;
    return _s(
      'Kütle numarası $kutle olan bir çekirdeği oluşturan proton ve '
          'nötronların serbest hâldeki toplam kütlesi ${_u(toplam)} u, çekirdeğin '
          'kütlesi ise ${_u(cekirdek)} u olarak veriliyor. Bu çekirdeğin '
          'bağlanma enerjisi kaç MeV olur? $_u931',
      e,
      [dm, e / kutle, e / 10],
      'Kütle eksikliği Δm = ${_u(toplam)} − ${_u(cekirdek)} = ${_n(dm)} u '
          'olur. Bağlanma enerjisi E = Δm·931 = ${_n(dm)}·931 = ${_n(e)} MeV '
          'bulunur.',
    );
  }
  final x = 30151 + 1931 * a + 59 * (b ~/ 2) + 9000 * k; // on binde bir u
  final d100 = 1 + (a + b + k) % 3;
  final y = x - 100 * d100;
  final kin = (1 + (7 * a + b + 3 * k) % 40) / 10; // MeV
  final e = 931 * d100 / 100, son = kin + e;
  return _s(
    'Bir füzyon tepkimesinde tepkimeye giren çekirdeklerin toplam kütlesi '
        '${_u(x)} u, oluşan taneciklerin toplam kütlesi ${_u(y)} u olarak '
        'veriliyor. Tepkimeye giren çekirdeklerin toplam kinetik enerjisi '
        '${_n(kin)} MeV olduğuna göre tepkimeden sonra oluşan taneciklerin toplam '
        'kinetik enerjisi kaç MeV olur? $_u931',
    son,
    [e, (e - kin).abs(), kin + d100 / 100],
    'Kütle farkı Δm = ${_u(x)} − ${_u(y)} = ${_n(d100 / 100)} u olup '
        '${_n(e)} MeV enerjiye karşılık gelir. Enerji korunumundan oluşan '
        'taneciklerin toplam kinetik enerjisi ${_n(kin)} + ${_n(e)} = ${_n(son)} '
        'MeV olur.',
  );
}

final _f09 = lmAile(
  'fz_kutle_enerji',
  'Kütle-enerji eşdeğerliği ve çekirdek tepkimeleri',
  Topic.physics,
  Difficulty.easy,
  BloomLevel.uygulama,
  (a, b, c) => switch (c % 3) {
    0 => _tepkimeEnerjisi(a, b, c ~/ 3),
    1 => _kutleEnerji(a, b, c ~/ 3),
    _ => _baglanmaEnerjisi(a, b, c ~/ 3),
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ─────────────────────────── 10 · Bohr atom modeli ───────────────────────────

const _eForm = '(Hidrojen atomunda Eₙ = −13,6 / n² eV)';

const _alt = {1: '₁', 2: '₂', 4: '₄'};

/// Kesin yazılan düzey enerjilerinin büyüklüğü (eV).
const _eDuzey = {1: 13.6, 2: 3.4, 4: 0.85};

String _duzeydeki(int m) =>
    m == 1 ? 'Temel hâldeki (n = 1)' : 'n = $m düzeyinde bulunan uyarılmış';

/// [n] numaralı (1'den) yüzde bir eV değeri; [yasak] değerler atlanır.
double _yuzde(int n, Iterable<num> yasak) =>
    _atla(n, {for (final y in yasak) (y * 100).round()}) / 100;

AdvancedItem _carpismaUyarma(int a, int b, int k) {
  final t = b % 4, q = b ~/ 4; // q: 0 … 4
  final n = 1 + a + 25 * q + 125 * k; // 1 … 500
  final (ilk, son) = const [(1, 2), (1, 4), (2, 4), (1, 4)][t];
  final de = _eDuzey[ilk]! - _eDuzey[son]!;
  final yasak = <num>[1, 2, 4, 13.6, 3.4, 0.85, de, 10.2, 12.75, 2.55];
  if (t == 3) {
    // 1 → 4 uyarma, ardından 4 → 2 geçişiyle foton; toplam K − 10,2 eV.
    final d = _yuzde(n + 9, [for (final y in yasak) y - 2.55]);
    final kin = _iki(12.75 + d), cevap = _iki(d + 2.55);
    return _s(
      'Temel hâldeki (n = 1) bir hidrojen atomuna kinetik enerjisi ${_n(kin)} '
          'eV olan bir elektron çarpıyor ve atomu n = 4 düzeyine uyarıyor. Atom '
          'daha sonra n = 4 düzeyinden n = 2 düzeyine geçerek bir foton '
          'yayımlıyor. Çarpışmadan sonraki elektronun kinetik enerjisi ile '
          'yayımlanan fotonun enerjisinin toplamı kaç eV olur? $_eForm',
      cevap,
      [d, _iki(kin - 2.55), _iki(d + 10.2)],
      'Uyarma için E₄ − E₁ = −0,85 − (−13,6) = 12,75 eV harcanır; elektronun '
          'kinetik enerjisi ${_n(kin)} − 12,75 = ${_n(d)} eV olur. Fotonun enerjisi '
          'E₄ − E₂ = −0,85 − (−3,4) = 2,55 eV olduğundan toplam ${_n(d)} + 2,55 = '
          '${_n(cevap)} eV bulunur.',
    );
  }
  final d = _yuzde(n + 9, yasak); // 0,1 eV ve üstü
  final kin = _iki(de + d);
  final eIlk = _eDuzey[ilk]!, eSon = _eDuzey[son]!;
  return _s(
    '${_duzeydeki(ilk)} bir hidrojen atomuna kinetik enerjisi ${_n(kin)} eV '
        'olan bir elektron çarpıyor. Çarpışmada atom n = $son enerji düzeyine '
        'uyarılıyor. Çarpışmadan sonra elektronun kinetik enerjisi kaç eV olur? '
        '$_eForm',
    d,
    [_iki(kin - eSon), if (kin > 13.6) _iki(kin - 13.6), de, _iki(kin + de)],
    'Atomun soğurduğu enerji iki düzeyin enerji farkına eşittir: '
        'E${_alt[son]} − E${_alt[ilk]} = −${_n(eSon)} − (−${_n(eIlk)}) = '
        '${_n(de)} eV. Elektronun kinetik '
        'enerjisi ${_n(kin)} − ${_n(de)} = ${_n(d)} eV olur.',
  );
}

AdvancedItem _fotonIyonlasma(int a, int b, int k) {
  final m = const [1, 2, 4][b % 3], q = b ~/ 3; // q: 0 … 6
  final n = 1 + a + 25 * q + 175 * k; // 1 … 525
  final ei = _eDuzey[m]!;
  final ileri = n.isOdd;
  final yasak = <num>[1, 2, 4, 13.6, ei, 10.2, 12.75, 2.55, 3.4, 0.85];
  final d = _yuzde(n + 9, ileri ? yasak : [for (final y in yasak) y - ei]);
  final foton = _iki(ei + d);
  final aciklama =
      'n = $m düzeyindeki elektronun enerjisi −13,6 / $m² = −${_n(ei)} eV '
      'olduğundan iyonlaşma enerjisi ${_n(ei)} eV olur.';
  if (ileri) {
    return _s(
      '${_duzeydeki(m)} bir hidrojen atomu, enerjisi ${_n(foton)} eV olan bir '
          'fotonu soğurarak iyonlaşıyor. Atomdan kopan elektronun kinetik enerjisi '
          'kaç eV olur? $_eForm',
      d,
      [
        if (m != 1 && foton > 13.6) _iki(foton - 13.6),
        if (m == 4) _iki(foton - 3.4),
        if (m == 2) _iki(foton - 6.8),
        _iki(foton + ei),
        ei,
      ],
      '$aciklama Kopan elektronun kinetik enerjisi ${_n(foton)} − ${_n(ei)} = '
          '${_n(d)} eV bulunur.',
    );
  }
  return _s(
    '${_duzeydeki(m)} bir hidrojen atomu bir fotonu soğurarak iyonlaşıyor ve '
        'atomdan kopan elektronun kinetik enerjisi ${_n(d)} eV oluyor. Soğurulan '
        'fotonun enerjisi kaç eV olur? $_eForm',
    foton,
    [
      if (m != 1) _iki(d + 13.6),
      if (d > ei) _iki(d - ei),
      ei,
      if (m == 2) _iki(d + 6.8),
    ],
    '$aciklama Fotonun enerjisi iyonlaşma enerjisi ile elektronun kinetik '
        'enerjisinin toplamıdır: ${_n(ei)} + ${_n(d)} = ${_n(foton)} eV.',
  );
}

AdvancedItem _carpismaIyonlasma(int a, int b, int k) {
  final m = const [1, 2, 4][b % 3], q = b ~/ 3; // q: 0 … 6
  final ei = _eDuzey[m]!;
  final kopan = (1 + a) / 10; // 0,1 … 2,5 eV
  final kalan = (1 + q + 7 * k) / 10 + 0.05; // 0,15 … 2,15 eV
  final kin = _iki(ei + kopan + kalan);
  return _s(
    '${_duzeydeki(m)} bir hidrojen atomuna kinetik enerjisi ${_n(kin)} eV olan '
        'bir elektron çarpıyor ve atomu iyonlaştırıyor. Atomdan kopan elektronun '
        'kinetik enerjisi ${_n(kopan)} eV olduğuna göre çarpan elektronun '
        'çarpışmadan sonraki kinetik enerjisi kaç eV olur? $_eForm',
    _iki(kalan),
    [
      _iki(kin - kopan),
      _iki(kin - ei),
      if (m != 1 && kin - 13.6 - kopan > 0) _iki(kin - 13.6 - kopan),
      _iki(kopan + kalan),
    ],
    'n = $m düzeyindeki elektronu atomdan koparmak için ${_n(ei)} eV gerekir. '
        'Enerji korunumundan ${_n(kin)} = ${_n(ei)} + ${_n(kopan)} + K olur; '
        'çarpan elektronun kinetik enerjisi K = ${_n(_iki(kalan))} eV bulunur.',
  );
}

final _f10 = lmAile(
  'fz_bohr',
  'Bohr modeli: enerji düzeyleri, uyarma ve iyonlaşma',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.analiz,
  (a, b, c) => switch (c % 3) {
    0 => _carpismaUyarma(a, b, c ~/ 3),
    1 => _fotonIyonlasma(a, b, c ~/ 3),
    _ => _carpismaIyonlasma(a, b, c ~/ 3),
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ───────────────────────── 11 · de Broglie dalga boyu ─────────────────────────

const _parcacikAdi = [
  'elektronun',
  'protonun',
  'nötronun',
  'alfa parçacığının',
];
const _goreliDegil = '(Göreli etkiler önemsizdir.)';

/// Tek parçacıkta hız, momentum ya da kinetik enerji değişince dalga boyu.
AdvancedItem _dalgaBoyuDegisimi(int a, int b, int k) {
  final v = b % 4, q = b ~/ 4; // q: 0 … 4
  final kat = const [2, 3, 4, 5][k];
  final u0 = 1 + a + 25 * q; // 1 … 125
  // Yavaşlatma sorusunda u = 100 alınmaz: yanıt kökteki 1/kat ile karışırdı.
  final u = v == 1 && u0 == 100 ? 126 : u0;
  final ad = _parcacikAdi[(a + b) % 4];
  final buyur = v == 1; // dalga boyu büyür
  final ilk = buyur ? u / 100 : kat * u / 100,
      son = buyur ? kat * u / 100 : u / 100;
  final (degisim, neden) = switch (v) {
    0 => ('hızı $kat katına çıkarılırsa', 'hızla ters orantılıdır'),
    1 => (
      'hızı ilk değerinin 1/$kat katına düşürülürse',
      'hızla ters orantılıdır',
    ),
    2 => ('momentumu $kat katına çıkarılırsa', 'momentumla ters orantılıdır'),
    _ => (
      'kinetik enerjisi ${kat * kat} katına çıkarılırsa',
      'kinetik enerjinin kareköküyle ters orantılıdır',
    ),
  };
  final bagint = v == 3
      ? 'λ = h / √(2·m·E)'
      : (v == 2 ? 'λ = h / p' : 'λ = h / (m·v)');
  return _s(
    'Bir $ad de Broglie dalga boyu ${_n(ilk)} nm olarak hesaplanıyor. Bu '
        'parçacığın $degisim de Broglie dalga boyu kaç nm olur? $_goreliDegil',
    son,
    buyur
        ? [ilk / kat, ilk * kat * kat, ilk]
        : [ilk * kat, ilk / (kat * kat), ilk],
    '$bagint olduğundan dalga boyu $neden. '
        '${v == 3 ? 'Enerji ${kat * kat} katına çıkınca karekökü $kat katına çıkar. ' : ''}'
        'Yeni dalga boyu ${_n(ilk)} ${buyur ? '·' : '/'} $kat = ${_n(son)} nm olur.',
    unit: 'nm',
  );
}

/// İki parçacığın kütle ve hızları: (m₁, m₂, v₁, v₂) — kütle u, hız 10⁵ m/s.
final _ikiParcacik = _tekil([
  for (var m1 = 1; m1 <= 12; m1++)
    for (var m2 = 1; m2 <= 12; m2++)
      if (m1 != m2)
        for (var v1 = 1; v1 <= 9; v1++)
          for (var v2 = 1; v2 <= 9; v2++)
            if (v1 != v2 && m1 * v1 != m2 * v2) (m1, m2, v1, v2),
], (t) => (_oran(t.$1, t.$2), _oran(t.$3, t.$4)));

const _iyonKutle = [
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  12,
  14,
  16,
  18,
  20,
  24,
  25,
  27,
  28,
  32,
  36,
];

/// (m₁, m₂, E₁, E₂): m₂·E₂ / (m₁·E₁) rasyonel bir sayının karesi (1 değil).
final _enerjiParcacik = _tekil([
  for (final m1 in _iyonKutle)
    for (final m2 in _iyonKutle)
      for (var e1 = 2; e1 <= 100; e1 += 2)
        for (var e2 = 2; e2 <= 100; e2 += 2)
          if (_kareOran(m2 * e2, m1 * e1) != null &&
              m2 * e2 != m1 * e1 &&
              m1 != m2 &&
              e1 != e2)
            (m1, m2, e1, e2),
], (t) => (_oran(t.$1, t.$2), _oran(t.$3, t.$4)));

/// x / y rasyonel bir sayının karesiyse (√x, √y) sadeleşmiş ikilisi.
(int, int)? _kareOran(int x, int y) {
  final (p, q) = _oran(x, y);
  final rp = _tamKok(p), rq = _tamKok(q);
  return rp == null || rq == null ? null : (rp, rq);
}

/// Aynı parçacığın kinetik enerji oranı (p/q)² olacak biçimde (p, q).
const _enerjiKati = <(int, int)>[
  (1, 2),
  (2, 1),
  (1, 3),
  (3, 1),
  (2, 3),
  (3, 2),
  (3, 4),
  (4, 3),
  (2, 5),
  (5, 2),
];

AdvancedItem _dalgaBoyuOrani(int a, int b, int k) {
  final n = a + 25 * b + 500 * k; // 0 … 1499
  final (m1, m2, v1, v2) = _yay(_ikiParcacik, n, 1500);
  return kesirli(
    'Kütlesi $m1 u olan X parçacığı $v1·10⁵ m/s, kütlesi $m2 u olan Y '
        'parçacığı $v2·10⁵ m/s hızla hareket ediyor. X parçacığının de Broglie '
        'dalga boyunun Y parçacığının de Broglie dalga boyuna oranı kaçtır? '
        '$_goreliDegil',
    m2 * v2,
    m1 * v1,
    [(m1 * v1, m2 * v2), (m2, m1), (v2, v1)],
    'λ = h / (m·v) olduğundan dalga boyları oranı momentumların ters oranına '
        'eşittir: ($m2·$v2) / ($m1·$v1) = ${kesir(m2 * v2, m1 * v1)}.',
  );
}

AdvancedItem _dalgaBoyuEnerji(int a, int b, int k) {
  if (b.isEven) {
    final n = a + 25 * (b ~/ 2) + 250 * k; // 0 … 749
    final (m1, m2, e1, e2) = _yay(_enerjiParcacik, n, 750);
    final (p, q) = _kareOran(m2 * e2, m1 * e1)!;
    return kesirli(
      'Kütlesi $m1 u olan X parçacığının kinetik enerjisi $e1 eV, kütlesi '
          '$m2 u olan Y parçacığının kinetik enerjisi $e2 eV olarak veriliyor. X '
          'parçacığının de Broglie dalga boyunun Y parçacığının de Broglie dalga '
          'boyuna oranı kaçtır? $_goreliDegil',
      p,
      q,
      [(m2 * e2, m1 * e1), (q, p), (m2, m1)],
      'p = √(2·m·E) ve λ = h / p olduğundan λ ∝ 1 / √(m·E) olur: '
          'λX / λY = √(($m2·$e2) / ($m1·$e1)) = √(${kesir(m2 * e2, m1 * e1)}) = '
          '${kesir(p, q)}.',
    );
  }
  final (p, q) = _enerjiKati[b ~/ 2];
  final s = 1 + a % 5 + 5 * k; // enerji birimi (eV)
  final w = 1 + a + 25 * k; // dalga boyu birimi (0,01 nm)
  final e1 = p * p * s, e2 = q * q * s;
  final l1 = q * w / 100, l2 = p * w / 100;
  return _s(
    'Kinetik enerjisi $e1 eV olan bir parçacığın de Broglie dalga boyu '
        '${_n(l1)} nm olarak hesaplanıyor. Aynı parçacığın kinetik enerjisi $e2 eV '
        'olursa de Broglie dalga boyu kaç nm olur? $_goreliDegil',
    l2,
    [l1 * p * p / (q * q), l1 * q / p, l1],
    'λ = h / √(2·m·E) olduğundan dalga boyu kinetik enerjinin kareköküyle ters '
        'orantılıdır: λ₂ = λ₁·√(E₁ / E₂) = ${_n(l1)}·√($e1 / $e2) = '
        '${_n(l1)}·${kesir(p, q)} = ${_n(l2)} nm.',
    unit: 'nm',
  );
}

final _f11 = lmAile(
  'fz_de_broglie',
  'Madde dalgaları: de Broglie dalga boyunun değişimi',
  Topic.physics,
  Difficulty.easy,
  BloomLevel.anlama,
  (a, b, c) => switch (c % 3) {
    0 => _dalgaBoyuDegisimi(a, b, c ~/ 3),
    1 => _dalgaBoyuOrani(a, b, c ~/ 3),
    _ => _dalgaBoyuEnerji(a, b, c ~/ 3),
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ─────────────────── 12 · Manyetik alanda hareket eden çubuk ──────────────────

/// (B onda bir T, L dm, v m/s): emk = B·L·v iki ondalıkta kesindir. B = 1 T
/// ve L = 1 m alınmaz (emk sayıca L·v ya da B·v olurdu).
final _cubuk = [
  for (final b10 in const [1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 15, 20])
    for (var l10 = 1; l10 <= 9; l10++)
      for (var v = 1; v <= 20; v++)
        if (!_icinde(b10 * l10 * v / 100, [
          b10 / 10,
          10 * l10,
          v,
          b10 * v / 10,
          l10 * v / 10,
        ]))
          (b10, l10, v),
];

const _direncler = [2, 3, 4, 5, 6, 8, 10, 12, 15, 16, 20, 25, 40, 50];

/// (B onda bir T, L dm, v m/s, R Ω): akım, kuvvet ve güç iki ondalıkta kesin.
final _cubukDevre = [
  for (final b10 in const [1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 15, 16, 18, 20])
    for (var l10 = 1; l10 <= 9; l10++)
      for (var v = 1; v <= 24; v++)
        for (final r in _direncler)
          if (_cubukUygun(b10, l10, v, r)) (b10, l10, v, r),
];

bool _cubukUygun(int b10, int l10, int v, int r) {
  final e100 = b10 * l10 * v; // emk·100
  // Akım·100 = e100 / r, kuvvet·100 = b10·e100·l10 / (100·r),
  // güç·100 = e100² / (100·r): üçü de tam sayı olmalı.
  if (e100 % r != 0 || b10 * e100 * l10 % (100 * r) != 0) return false;
  if (e100 * e100 % (100 * r) != 0) return false;
  final e = e100 / 100, akim = e / r;
  if (_icinde(e, [b10 / 10, 10 * l10, v, b10 * v / 10, l10 * v / 10])) {
    return false;
  }
  final f = b10 * akim * l10 / 100, p = e * e / r;
  if (akim > 20 || f < 0.01 || p < 0.01) return false;
  // Anahtar kökteki sayılara ya da yanlış yolların sonucuna eşit olmasın.
  final sayilar = [b10 / 10, 10 * l10, v, r, e, e * r, e * e];
  return !_icinde(akim, sayilar) &&
      !_icinde(f, sayilar) &&
      !_icinde(p, sayilar);
}

String _rayDuzeni(int b10, int l10, int v, int? r) =>
    'Büyüklüğü ${_n(b10 / 10)} T olan düzgün bir manyetik alana dik yatay '
    'düzlemde bulunan, birbirine paralel iki iletken ray'
    '${r == null ? '' : ' bir uçta $r Ω değerinde bir dirençle birleştirilmiştir'}'
    '${r == null ? ' üzerine' : '. Raylar üzerine'} dik olarak konan ve raylar '
    'arasında kalan uzunluğu ${10 * l10} cm olan iletken bir çubuk, raylar '
    'boyunca $v m/s sabit hızla çekiliyor.';

AdvancedItem _cubukEmk(int a, int b, int k) {
  final (b10, l10, v) = _yay(_cubuk, a + 25 * b + 500 * k, 2000);
  final e = b10 * l10 * v / 100;
  return _s(
    '${_rayDuzeni(b10, l10, v, null)} Çubuğun uçları arasında oluşan '
        'indüksiyon emk değeri kaç V olur?',
    e,
    [e * 100, b10 * v / 10, l10 * v / 10],
    'Hareketli çubukta oluşan emk ε = B·L·v bağıntısıyla bulunur. Uzunluk '
        '${_n(l10 / 10)} m olduğundan ε = ${_n(b10 / 10)}·${_n(l10 / 10)}·$v = '
        '${_n(e)} V olur.',
    unit: 'V',
  );
}

AdvancedItem _cubukAkim(int a, int b, int k) {
  final (b10, l10, v, r) = _yay(_cubukDevre, a + 25 * b + 500 * k, 1500);
  final e = b10 * l10 * v / 100, akim = e / r;
  return _s(
    '${_rayDuzeni(b10, l10, v, r)} Rayların ve çubuğun direnci önemsiz '
        'olduğuna göre devreden geçen indüksiyon akımı kaç A olur?',
    akim,
    [e * r, e, akim * 100],
    'Çubukta oluşan emk ε = B·L·v = ${_n(b10 / 10)}·${_n(l10 / 10)}·$v = '
        '${_n(e)} V olur. Devreden geçen akım I = ε / R = ${_n(e)} / $r = '
        '${_n(akim)} A bulunur.',
    unit: 'A',
  );
}

AdvancedItem _cubukKuvvet(int a, int b, int k) {
  final (b10, l10, v, r) = _yay(_cubukDevre, a + 25 * b + 500 * k, 1500);
  final e = b10 * l10 * v / 100, akim = e / r;
  final f = b10 * akim * l10 / 100, p = e * e / r;
  final ortak =
      'Çubukta oluşan emk ε = B·L·v = ${_n(b10 / 10)}·${_n(l10 / 10)}·$v = '
      '${_n(e)} V, devreden geçen akım I = ε / R = ${_n(e)} / $r = ${_n(akim)} A '
      'olur.';
  if (b.isEven) {
    return _s(
      '${_rayDuzeni(b10, l10, v, r)} Sürtünmeler ile rayların ve çubuğun '
          'direnci önemsiz olduğuna göre çubuğun sabit hızla hareket etmesi için '
          'çubuğa uygulanması gereken kuvvet kaç N olur?',
      f,
      [e, b10 * e * l10 / 100, b10 * akim / 10],
      '$ortak Çubuğa etki eden manyetik kuvvet F = B·I·L = '
          '${_n(b10 / 10)}·${_n(akim)}·${_n(l10 / 10)} = ${_n(f)} N olup çubuğun '
          'sabit hızla gitmesi için aynı büyüklükte kuvvet uygulanmalıdır.',
      unit: 'N',
    );
  }
  return _s(
    '${_rayDuzeni(b10, l10, v, r)} Rayların ve çubuğun direnci önemsiz '
        'olduğuna göre dirençte harcanan elektriksel güç kaç W olur?',
    p,
    [e * e, e * r, e * akim * 2],
    '$ortak Dirençte harcanan güç P = ε·I = ${_n(e)}·${_n(akim)} = ${_n(p)} W '
        'bulunur.',
    unit: 'W',
  );
}

final _f12 = lmAile(
  'fz_hareketli_cubuk',
  'Manyetik alanda hareket eden çubukta indüksiyon',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) => switch (c % 3) {
    0 => _cubukEmk(a, b, c ~/ 3),
    1 => _cubukAkim(a, b, c ~/ 3),
    _ => _cubukKuvvet(a, b, c ~/ 3),
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ───────────────────────────── 13 · Alternatif akım ────────────────────────────

/// ω / π değerleri (rad/s): frekans ω / (2π) tam sayı hertz çıkar.
const _omega = [
  20,
  24,
  30,
  36,
  40,
  44,
  50,
  56,
  60,
  64,
  70,
  80,
  90,
  100,
  110,
  120,
  130,
  140,
  150,
  160,
  180,
  200,
  240,
  300,
  400,
];

const _kok2 = '(√2 = 1,4 alınız.)';

/// k√2 yazımı.
String _k2(num k) => k == 1 ? '√2' : '${_n(k)}√2';

AdvancedItem _acFrekans(int a, int b, int k) {
  final w = _omega[a], f = w ~/ 2;
  final t = 3 + b ~/ 2 + 10 * k; // 3 … 42 s (1 ve 2 s yanıtı köke eşitlerdi)
  final yon = b.isEven;
  final n = yon ? w * t : f * t;
  final giris =
      'Bir alternatif akım kaynağının uçları arasındaki gerilim V = Vmaks·sin(ω·t) '
      'bağıntısıyla değişmektedir ve ω = $wπ rad/s olarak veriliyor.';
  final frekans =
      'ω = 2·π·f olduğundan f = $wπ / (2π) = $f Hz, yani saniyede $f periyot '
      'olur.';
  if (yon) {
    return _s(
      '$giris Kaynağa bağlı bir dirençten geçen akımın yönü $t s içinde kaç kez '
          'değişir?',
      n,
      [f * t, 4 * f * t, f],
      '$frekans Akımın yönü her periyotta iki kez değiştiğinden $t s içinde '
          '2·$f·$t = $n kez değişir.',
    );
  }
  return _s(
    '$giris Kaynağın gerilimi $t s içinde kaç kez pozitif en büyük değerine '
        'ulaşır?',
    n,
    [2 * f * t, n / 2, f],
    '$frekans Gerilim her periyotta bir kez pozitif en büyük değerine ulaştığından '
        '$t s içinde $f·$t = $n kez ulaşır.',
  );
}

const _acDirenc = [2, 4, 5, 7, 8, 10, 14, 20, 25, 28, 35, 40, 50, 70, 100];

/// (taban değer onda bir, direnç): taban değer / direnç iki ondalıkta kesin.
List<(int, int)> _acTablo(int tur) => _tekil([
  // Gerilimler tam volt (1 … 400 V), akımlar onda bir amper (0,1 … 20 A).
  for (
    var x = tur < 2 ? 10 : 1;
    x <= (tur < 2 ? 4000 : 200);
    x += tur < 2 ? 10 : 1
  )
    for (final r in _acDirenc)
      if (_acUygun(tur, x, r)) (x, r),
], (t) => tur < 2 ? _oran(t.$1, t.$2) : (t.$1, t.$2));

bool _acUygun(int tur, int x10, int r) {
  // tur 0: Vmaks = x√2 → Ietkin = x/R; tur 1: Vetkin = x → Imaks = 1,4·x/R;
  // tur 2: Ietkin = x → Vmaks = 1,4·x·R; tur 3: Imaks = x√2 → Vetkin = x·R.
  final x = x10 / 10;
  switch (tur) {
    case 0 || 1:
      final pay = tur == 0 ? 10 * x10 : 14 * x10; // yanıt·100·R
      if (pay % r != 0) return false;
      final y = pay / (100 * r);
      if (y < 0.1 || y > 20) return false;
      return !_icinde(
        y,
        tur == 0
            ? [x, r, x / (2 * r), x * r]
            : [x, r, x / r, x / (1.4 * r), 2 * x / r],
      );
    default:
      final y100 = tur == 2 ? 14 * x10 * r : 10 * x10 * r; // yanıt·100
      final y = y100 / 100;
      if (y > 2000) return false;
      return !_icinde(
        y,
        tur == 2
            ? [x, r, x * r, x * r / 1.4, 2 * x * r]
            : [x, r, x * r / 2, x / r],
      );
  }
}

final _acTablolar = [for (var t = 0; t < 4; t++) _acTablo(t)];

AdvancedItem _acEtkin(int a, int b, int k) {
  final v = b % 4;
  final n = a + 25 * (b ~/ 4) + 125 * k; // 0 … 374
  final (x10, r) = _yay(_acTablolar[v], n, 375);
  final x = x10 / 10;
  switch (v) {
    case 0:
      final ie = x / r;
      return _s(
        'Maksimum değeri ${_k2(x)} V olan alternatif gerilim, direnci $r Ω '
            'olan bir dirence uygulanıyor. Dirençten geçen akımın etkin değeri kaç '
            'A olur?',
        ie,
        ['${_k2(_iki(ie))} A', x / (2 * r), x * r],
        'Gerilimin etkin değeri maksimum değerin √2 ile bölünmesiyle bulunur: '
            '${_k2(x)} / √2 = ${_n(x)} V. Etkin akım ${_n(x)} / $r = ${_n(ie)} A '
            'olur.',
        unit: 'A',
      );
    case 1:
      final ie = x / r, im = 1.4 * x / r;
      return _s(
        'Bir dirence bağlı alternatif akım kaynağının etkin gerilimi bir '
            'voltmetreyle ${_n(x)} V olarak ölçülüyor. Direncin değeri $r Ω '
            'olduğuna göre dirençten geçen akımın maksimum değeri kaç A olur? '
            '$_kok2',
        im,
        [ie, x / (1.4 * r), 2 * x / r],
        'Etkin akım ${_n(x)} / $r = ${_n(ie)} A olur. Akımın maksimum değeri '
            'etkin değerin √2 katıdır: ${_n(ie)}·1,4 = ${_n(im)} A.',
        unit: 'A',
      );
    case 2:
      final ve = x * r, vm = 1.4 * x * r;
      return _s(
        'Direnci $r Ω olan bir dirençten geçen alternatif akımın etkin değeri '
            'bir ampermetreyle ${_n(x)} A olarak ölçülüyor. Direncin uçları '
            'arasındaki gerilimin maksimum değeri kaç V olur? $_kok2',
        vm,
        [ve, ve / 1.4, 2 * ve],
        'Etkin gerilim ${_n(x)}·$r = ${_n(ve)} V olur. Gerilimin maksimum '
            'değeri etkin değerin √2 katıdır: ${_n(ve)}·1,4 = ${_n(vm)} V.',
        unit: 'V',
      );
    default:
      final ve = x * r;
      return _s(
        'Direnci $r Ω olan bir dirençten geçen alternatif akımın maksimum '
            'değeri ${_k2(x)} A olarak veriliyor. Direncin uçları arasındaki '
            'gerilimin etkin değeri kaç V olur?',
        ve,
        ['${_k2(_iki(ve))} V', ve / 2, x / r],
        'Akımın etkin değeri ${_k2(x)} / √2 = ${_n(x)} A olur. Etkin gerilim '
            '${_n(x)}·$r = ${_n(ve)} V bulunur.',
        unit: 'V',
      );
  }
}

/// Ortalama güç tabloları: (değer, direnç) — güç iki ondalıkta kesin.
List<(int, int)> _gucTablo(int tur) => [
  for (var x = 1; x <= (tur == 1 ? 60 : 400); x++)
    for (final r in _acDirenc)
      if (_gucUygun(tur, x, r)) (x, r),
];

bool _gucUygun(int tur, int x, int r) {
  // tur 0: Vm = x volt; 1: Im = x/2 amper; 2: Vm = x√2 volt; 3: Ve = x volt.
  final double p = switch (tur) {
    0 => x * x / (2 * r),
    1 => (x / 2) * (x / 2) * r / 2,
    2 => x * x / r,
    _ => x * x / r,
  };
  if ((p * 100 - (p * 100).round()).abs() > 1e-6 || p < 1 || p > 5000) {
    return false;
  }
  return !_icinde(p, [x, r, x / 2, x / r]);
}

final _gucTablolar = [for (var t = 0; t < 4; t++) _gucTablo(t)];

AdvancedItem _acGuc(int a, int b, int k) {
  final v = b % 4;
  final n = a + 25 * (b ~/ 4) + 125 * k; // 0 … 374
  final (x, r) = _yay(_gucTablolar[v], n, 375);
  switch (v) {
    case 0:
      final p = x * x / (2 * r);
      return _s(
        'Maksimum değeri $x V olan alternatif gerilim, direnci $r Ω olan bir '
            'dirence uygulanıyor. Dirençte harcanan ortalama güç kaç W olur?',
        p,
        [2 * p, p / 2, x / r],
        'Ortalama güç etkin değerlerle hesaplanır: P = (Vmaks / √2)² / R = '
            'Vmaks² / (2·R) = $x² / (2·$r) = ${_n(p)} W.',
        unit: 'W',
      );
    case 1:
      final im = x / 2, p = im * im * r / 2;
      return _s(
        'Direnci $r Ω olan bir dirençten geçen alternatif akımın maksimum '
            'değeri ${_n(im)} A olarak veriliyor. Dirençte harcanan ortalama güç '
            'kaç W olur?',
        p,
        [2 * p, p / 2, im * r],
        'Ortalama güç etkin akımla hesaplanır: P = (Imaks / √2)²·R = '
            'Imaks²·R / 2 = ${_n(im)}²·$r / 2 = ${_n(p)} W.',
        unit: 'W',
      );
    case 2:
      final p = x * x / r;
      return _s(
        'Maksimum değeri ${_k2(x)} V olan alternatif gerilim, direnci $r Ω olan '
            'bir dirence uygulanıyor. Dirençte harcanan ortalama güç kaç W olur?',
        p,
        [2 * p, p / 2, x / r],
        'Etkin gerilim ${_k2(x)} / √2 = $x V olur. Ortalama güç P = Vetkin² / R '
            '= $x² / $r = ${_n(p)} W.',
        unit: 'W',
      );
    default:
      final dk = 1 + a % 5 + 5 * k; // 1 … 15 dakika
      final p = x * x / r, e = p * 60 * dk; // J
      return _s(
        'Etkin değeri $x V olan alternatif gerilim, direnci $r Ω olan bir '
            'ısıtıcı telin uçlarına uygulanıyor. Tel $dk dakika çalıştırıldığında '
            'harcanan elektrik enerjisi kaç J olur?',
        e,
        [e * 2, p * dk, e / 2],
        'Ortalama güç P = Vetkin² / R = $x² / $r = ${_n(p)} W olur. $dk dakika '
            '${60 * dk} s olduğundan enerji W = P·t = ${_n(p)}·${60 * dk} = '
            '${_n(e)} J bulunur.',
        unit: 'J',
      );
  }
}

final _f13 = lmAile(
  'fz_alternatif_akim',
  'Alternatif akımda etkin değer, frekans ve güç',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) => switch (c % 3) {
    0 => _acFrekans(a, b, c ~/ 3),
    1 => _acEtkin(a, b, c ~/ 3),
    _ => _acGuc(a, b, c ~/ 3),
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ───────────────────────────── 14 · Çift yarıkta girişim ───────────────────────

/// (λ nm, L cm, d yüzde bir mm): saçak genişliği Δx = λ·L / d iki ondalıkta
/// kesin ve 0,3 … 15 mm. L / d oranı aynı olan ikizler alınmaz.
final _girisim = _tekil([
  for (var l = 400; l <= 700; l += 10)
    for (var boy = 50; boy <= 300; boy += 10)
      for (final d in const [
        8,
        10,
        12,
        15,
        16,
        20,
        24,
        25,
        30,
        32,
        40,
        45,
        48,
        50,
        60,
        64,
        75,
        80,
        90,
        100,
        120,
        125,
        150,
      ])
        if (l * boy % (10 * d) == 0 &&
            l * boy >= 300 * d &&
            l * boy <= 15000 * d)
          (l, boy, d),
], (t) => (t.$1, _oran(t.$2, t.$3)));

/// Δx yüzde bir mm biriminde.
int _sacak(int l, int boy, int d) => l * boy ~/ (10 * d);

/// Karanlık saçak soruları için Δx / 2 de iki ondalıkta kesin olanlar.
final _girisimYarim = [
  for (final t in _girisim)
    if (_sacak(t.$1, t.$2, t.$3).isEven) t,
];

String _deney(int l, int boy, int d) =>
    'Çift yarık deneyinde yarıklar arasındaki uzaklık ${_n(d / 100)} mm, '
    'yarıklarla perde arasındaki uzaklık ${_n(boy / 100)} m ve kullanılan tek '
    'renkli ışığın dalga boyu $l nm olarak veriliyor.';

String _sacakCozum(int l, int boy, int d) {
  final dx = _sacak(l, boy, d) / 100;
  return 'Saçak genişliği Δx = λ·L / d = $l·10⁻⁹·${_n(boy / 100)} / '
      '(${_n(d / 100)}·10⁻³) m = ${_n(dx)} mm olur.';
}

AdvancedItem _sacakGenisligi(int a, int b, int k) {
  final (l, boy, d) = _yay(_girisim, a + 25 * b + 500 * k, 2000);
  final dx = _sacak(l, boy, d) / 100;
  return _s(
    '${_deney(l, boy, d)} Perdede oluşan ardışık iki aydınlık saçak '
    'arasındaki uzaklık (saçak genişliği) kaç mm olur?',
    dx,
    [dx * 1000, dx / 2, 2 * dx],
    _sacakCozum(l, boy, d),
    unit: 'mm',
  );
}

AdvancedItem _sacakKonumu(int a, int b, int k) {
  final v = b % 4;
  final n = a + 25 * (b ~/ 4) + 125 * k; // 0 … 374
  final (l, boy, d) = _yay(v == 0 ? _girisim : _girisimYarim, n, 375);
  final dx = _sacak(l, boy, d) / 100;
  final cozum = _sacakCozum(l, boy, d);
  const merkez = 'merkezî aydınlık saçağın';
  switch (v) {
    case 0:
      final s = 2 + n % 5; // 2 … 6
      return _s(
        '${_deney(l, boy, d)} Perdede oluşan $s. aydınlık saçağın $merkez '
            'ortasına uzaklığı kaç mm olur?',
        s * dx,
        [(s - 0.5) * dx, (s + 1) * dx, dx],
        '$cozum n. aydınlık saçak merkezden n·Δx uzaktadır: $s·${_n(dx)} = '
            '${_n(s * dx)} mm.',
        unit: 'mm',
      );
    case 1:
      final s = 1 + n % 5; // 1 … 5
      return _s(
        '${_deney(l, boy, d)} Perdede oluşan $s. karanlık saçağın $merkez '
            'ortasına uzaklığı kaç mm olur?',
        (s - 0.5) * dx,
        [s * dx, (s + 0.5) * dx, (s - 1) * dx],
        '$cozum n. karanlık saçak merkezden (n − ½)·Δx uzaktadır: '
            '${_n(s - 0.5)}·${_n(dx)} = ${_n((s - 0.5) * dx)} mm.',
        unit: 'mm',
      );
    case 2:
      final s = 1 + n % 3, m = s + 1 + (n ~/ 3) % 3; // aynı tarafta
      final x = (m - 0.5 - s) * dx;
      return _s(
        '${_deney(l, boy, d)} Merkezî aydınlık saçağın aynı tarafında bulunan '
            '$s. aydınlık saçak ile $m. karanlık saçak arasındaki uzaklık kaç mm '
            'olur?',
        x,
        [(m - s) * dx, (m + 0.5 - s) * dx, (m - 0.5 + s) * dx],
        '$cozum $s. aydınlık saçak ${_n(s * dx)} mm, $m. karanlık saçak '
            '${_n((m - 0.5) * dx)} mm uzaktadır; aradaki uzaklık ${_n(x)} mm olur.',
        unit: 'mm',
      );
    default:
      final s = 1 + n % 3, m = 1 + (n ~/ 3) % 4; // zıt taraflarda
      final x = (s + m - 0.5) * dx;
      return _s(
        '${_deney(l, boy, d)} Merkezî aydınlık saçağın bir tarafındaki $s. '
            'aydınlık saçak ile öbür tarafındaki $m. karanlık saçak arasındaki '
            'uzaklık kaç mm olur?',
        x,
        [(s + m) * dx, ((m - 0.5 - s).abs()) * dx, (s + m + 0.5) * dx],
        '$cozum Saçaklar merkezin iki yanında olduğundan uzaklıklar toplanır: '
            '$s·${_n(dx)} + ${_n(m - 0.5)}·${_n(dx)} = ${_n(x)} mm.',
        unit: 'mm',
      );
  }
}

AdvancedItem _girisimTers(int a, int b, int k) {
  final v = b % 3;
  final n = a + 25 * (b ~/ 3) + 175 * k; // 0 … 524
  final (l, boy, d) = _yay(_girisim, n, 525);
  final dx = _sacak(l, boy, d) / 100;
  final yarik = 'Çift yarık deneyinde';
  switch (v) {
    case 0:
      return _s(
        '$yarik yarıklar arasındaki uzaklık ${_n(d / 100)} mm, yarıklarla perde '
            'arasındaki uzaklık ${_n(boy / 100)} m olarak veriliyor. Perdede ardışık '
            'iki aydınlık saçak arasındaki uzaklık ${_n(dx)} mm ölçüldüğüne göre '
            'kullanılan ışığın dalga boyu kaç nm olur?',
        l,
        [l * 1000, l / 2, 2 * l],
        'Δx = λ·L / d bağıntısından λ = Δx·d / L = ${_n(dx)}·10⁻³·'
            '${_n(d / 100)}·10⁻³ / ${_n(boy / 100)} m = $l·10⁻⁹ m = $l nm bulunur.',
        unit: 'nm',
      );
    case 1:
      return _s(
        '$yarik dalga boyu $l nm olan tek renkli ışık kullanılıyor ve '
            'yarıklarla perde arasındaki uzaklık ${_n(boy / 100)} m olarak '
            'veriliyor. Perdede ardışık iki aydınlık saçak arasındaki uzaklık '
            '${_n(dx)} mm ölçüldüğüne göre yarıklar arasındaki uzaklık kaç mm olur?',
        d / 100,
        [d / 10, d / 200, d / 50],
        'Δx = λ·L / d bağıntısından d = λ·L / Δx = $l·10⁻⁹·${_n(boy / 100)} / '
            '(${_n(dx)}·10⁻³) m = ${_n(d / 100)} mm bulunur.',
        unit: 'mm',
      );
    default:
      final s = 2 + n % 4; // 2 … 5
      return _s(
        '$yarik yarıklar arasındaki uzaklık ${_n(d / 100)} mm, yarıklarla perde '
            'arasındaki uzaklık ${_n(boy / 100)} m olarak veriliyor. Perdede $s. '
            'aydınlık saçağın merkezî aydınlık saçağın ortasına uzaklığı '
            '${_n(s * dx)} mm ölçüldüğüne göre kullanılan ışığın dalga boyu kaç nm '
            'olur?',
        l,
        [s * l, l * s / (s - 0.5), 2 * l],
        '$s. aydınlık saçak merkezden $s·Δx uzakta olduğundan Δx = '
            '${_n(s * dx)} / $s = ${_n(dx)} mm olur. λ = Δx·d / L = $l nm bulunur.',
        unit: 'nm',
      );
  }
}

final _f14 = lmAile(
  'fz_girisim',
  'Çift yarıkta girişim: saçak genişliği ve konumu',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) => switch (c % 3) {
    0 => _sacakGenisligi(a, b, c ~/ 3),
    1 => _sacakKonumu(a, b, c ~/ 3),
    _ => _girisimTers(a, b, c ~/ 3),
  },
  exam: ExamKind.ayt,
  lesson: _fizik,
);

// ───────────────────────────── 15 · Su dalgaları ───────────────────────────────

/// (f onda bir Hz, λ₁ mm, λ₂ mm): derin ve sığ bölgede dalga boyları; hızlar
/// v = f·λ iki ondalıkta kesin. Derin bölge hızı 15 … 40 cm/s.
/// Dalga leğeni kaynak frekansları (onda bir Hz): 2 … 25 Hz.
const _suFrekans = [
  20,
  25,
  30,
  40,
  50,
  60,
  75,
  80,
  100,
  120,
  125,
  150,
  160,
  200,
  250,
];

final _suDalgasi = _tekil([
  for (final f10 in _suFrekans)
    for (var l1 = 10; l1 <= 100; l1 += 5)
      for (var l2 = 5; l2 < l1; l2 += 5)
        if (f10 * l1 >= 1200 &&
            f10 * l1 <= 4000 &&
            f10 * l2 >= 500 &&
            !_icinde(f10 * l2 / 100, [
              f10 / 10,
              l1 / 10,
              l2 / 10,
              f10 * l1 / 100,
            ]))
          (f10, l1, l2),
], (t) => (_oran(t.$2, t.$3), t.$1 * t.$2));

AdvancedItem _derinlikDegisimi(int a, int b, int k) {
  final v = b % 4;
  final n = a + 25 * (b ~/ 4) + 125 * k; // 0 … 499
  final (f10, l1, l2) = _yay(_suDalgasi, n, 500);
  final v1 = f10 * l1 / 100, v2 = f10 * l2 / 100; // cm/s
  final la1 = l1 / 10, la2 = l2 / 10; // cm
  const giris = 'Bir dalga leğeninde periyodik su dalgaları';
  const sabit =
      'Dalgaların frekansı kaynağa bağlı olduğundan iki bölgede de aynıdır';
  switch (v) {
    case 0:
      return _s(
        '$giris derin bölgede ${_n(v1)} cm/s hızla ilerlemekte ve dalga boyları '
            '${_n(la1)} cm olarak ölçülmektedir. Dalgalar sığ bölgeye geçtiğinde '
            'dalga boyu ${_n(la2)} cm oluyor. Dalgaların sığ bölgedeki hızı kaç '
            'cm/s olur?',
        v2,
        [v1 * la1 / la2, v1, v1 - v2],
        '$sabit: f = ${_n(v1)} / ${_n(la1)} = ${_n(f10 / 10)} Hz. Sığ bölgedeki '
            'hız v = f·λ = ${_n(f10 / 10)}·${_n(la2)} = ${_n(v2)} cm/s olur.',
      );
    case 1:
      return _s(
        '$giris derin bölgede ${_n(v1)} cm/s hızla ilerlemekte ve dalga boyları '
            '${_n(la1)} cm olarak ölçülmektedir. Dalgalar sığ bölgeye geçtiğinde '
            'hızları ${_n(v2)} cm/s oluyor. Dalgaların sığ bölgedeki dalga boyu kaç '
            'cm olur?',
        la2,
        [la1 * v1 / v2, la1],
        '$sabit: f = ${_n(v1)} / ${_n(la1)} = ${_n(f10 / 10)} Hz. Sığ bölgedeki '
            'dalga boyu λ = v / f = ${_n(v2)} / ${_n(f10 / 10)} = ${_n(la2)} cm olur.',
        unit: 'cm',
      );
    case 2:
      return _s(
        '$giris sığ bölgede ${_n(v2)} cm/s hızla ilerlemekte ve dalga boyları '
            '${_n(la2)} cm olarak ölçülmektedir. Dalgalar derin bölgeye geçtiğinde '
            'dalga boyu ${_n(la1)} cm oluyor. Dalgaların derin bölgedeki hızı kaç '
            'cm/s olur?',
        v1,
        [v2 * la2 / la1, v2, 2 * v2],
        '$sabit: f = ${_n(v2)} / ${_n(la2)} = ${_n(f10 / 10)} Hz. Derin bölgedeki '
            'hız v = f·λ = ${_n(f10 / 10)}·${_n(la1)} = ${_n(v1)} cm/s olur.',
      );
    default:
      final fark = v1 - v2;
      return _s(
        'Frekansı ${_n(f10 / 10)} Hz olan bir kaynağın dalga leğeninde '
            'oluşturduğu periyodik dalgaların derin bölgedeki dalga boyu ${_n(la1)} '
            'cm, sığ bölgedeki dalga boyu ${_n(la2)} cm olarak ölçülüyor. '
            'Dalgaların derin bölgedeki hızı sığ bölgedekinden kaç cm/s fazladır?',
        fark,
        [la1 - la2, fark / (f10 / 10) * 2, v1],
        '$sabit. Derin bölgede v = ${_n(f10 / 10)}·${_n(la1)} = ${_n(v1)} cm/s, '
            'sığ bölgede v = ${_n(f10 / 10)}·${_n(la2)} = ${_n(v2)} cm/s olur; fark '
            '${_n(fark)} cm/s bulunur.',
      );
  }
}

/// (v₁ cm/s, v₂ cm/s, d₁ cm, d₂ cm): atmanın iki bölgedeki süreleri iki
/// ondalıkta kesin.
final _atma = [
  for (var v1 = 15; v1 <= 40; v1++)
    for (var v2 = 8; v2 < v1; v2++)
      for (var d1 = 10; d1 <= 60; d1 += 2)
        for (final d2 in const [10, 12, 15, 18, 20, 24, 25, 30, 36, 40])
          if (100 * d1 % v1 == 0 &&
              100 * d2 % v2 == 0 &&
              !_icinde(d1 / v1 + d2 / v2, [
                v1,
                v2,
                d1,
                d2,
                (d1 + d2) / v1,
                (d1 + d2) / v2,
                2 * (d1 + d2) / (v1 + v2),
              ]))
            (v1, v2, d1, d2),
];

AdvancedItem _atmaSuresi(int a, int b, int k) {
  final n = a + 25 * b + 500 * k; // 0 … 1499
  final (v1, v2, d1, d2) = _yay(_atma, n, 1500);
  final t1 = d1 / v1, t2 = d2 / v2, t = t1 + t2;
  return _s(
    'Bir dalga leğeninin derin bölgesinde $v1 cm/s hızla ilerleyen bir atma, '
        'derin bölgede $d1 cm yol aldıktan sonra sığ bölgeye geçiyor ve sığ '
        'bölgede $v2 cm/s hızla ilerliyor. Atma sığ bölgede $d2 cm daha '
        'ilerlediğinde, harekete başladığı andan itibaren kaç saniye geçmiş olur?',
    t,
    [(d1 + d2) / v1, (d1 + d2) / v2, (d1 + d2) / ((v1 + v2) / 2)],
    'Atma derin bölgede $d1 / $v1 = ${_n(t1)} s, sığ bölgede $d2 / $v2 = '
        '${_n(t2)} s ilerler. Toplam süre ${_n(t1)} + ${_n(t2)} = ${_n(t)} s olur.',
    unit: 's',
  );
}

/// (f onda bir Hz, ardışık tepe sayısı, aradaki uzaklık mm): hız kesin.
final _tepeler = [
  for (final f10 in _suFrekans)
    for (var t = 3; t <= 10; t++)
      for (var d = 20; d <= 400; d += 5)
        if (d % (t - 1) == 0 &&
            f10 * d ~/ (t - 1) >= 500 &&
            f10 * d ~/ (t - 1) <= 3000 &&
            !_icinde(f10 * d / (100 * (t - 1)), [f10 / 10, t, d / 10]))
          (f10, t, d),
];

/// (f onda bir Hz, λ₁ mm, λ₂ mm, yol cm): sığ bölgedeki süre iki ondalıkta
/// kesin.
final _suYol = [
  for (final (f10, l1, l2) in _suDalgasi)
    for (var yol = 10; yol <= 60; yol += 5)
      if (10000 * yol % (f10 * l2) == 0 &&
          !_icinde(10000 * yol / (f10 * l2) / 100, [
            f10 / 10,
            l1 / 10,
            l2 / 10,
            yol,
            f10 * l1 / 100,
            100 * yol / (f10 * l1),
          ]))
        (f10, l1, l2, yol),
];

AdvancedItem _periyodikDalga(int a, int b, int k) {
  final n = a + 25 * (b ~/ 2) + 250 * k; // 0 … 749
  if (b.isEven) {
    final (f10, t, d) = _yay(_tepeler, n, 750);
    final f = f10 / 10, la = d / (10 * (t - 1)), v = f * la;
    return _s(
      'Frekansı ${_n(f)} Hz olan bir kaynağın dalga leğeninde oluşturduğu '
          'periyodik dalgalar sığ bölgeye geçiyor. Sığ bölgede art arda gelen $t '
          'dalga tepesinden ilki ile sonuncusu arasındaki uzaklık ${_n(d / 10)} cm '
          'olarak ölçülüyor. Dalgaların sığ bölgedeki hızı kaç cm/s olur?',
      v,
      [f * d / (10 * t), f * d / 10, v / 2],
      '$t tepe arasında ${t - 1} dalga boyu bulunduğundan λ = ${_n(d / 10)} / '
          '${t - 1} = ${_n(la)} cm olur. Frekans kaynağa bağlı olduğundan sığ '
          'bölgede de ${_n(f)} Hz kalır: v = f·λ = ${_n(f)}·${_n(la)} = ${_n(v)} '
          'cm/s.',
    );
  }
  final (f10, l1, l2, yol) = _yay(_suYol, n, 750);
  final v1 = f10 * l1 / 100, v2 = f10 * l2 / 100;
  final sure = yol / v2;
  return _s(
    'Bir dalga leğeninin derin bölgesinde ${_n(v1)} cm/s hızla ilerleyen '
        'periyodik dalgaların dalga boyu ${_n(l1 / 10)} cm, sığ bölgedeki dalga '
        'boyu ${_n(l2 / 10)} cm olarak ölçülüyor. Bir dalga tepesi sığ bölgede '
        '$yol cm yolu kaç saniyede alır?',
    sure,
    [yol / v1, yol * l2 / (v1 * l1), sure * 2],
    'Frekans iki bölgede aynıdır: f = ${_n(v1)} / ${_n(l1 / 10)} = '
        '${_n(f10 / 10)} Hz. Sığ bölgedeki hız ${_n(f10 / 10)}·${_n(l2 / 10)} = '
        '${_n(v2)} cm/s olduğundan süre $yol / ${_n(v2)} = ${_n(sure)} s bulunur.',
    unit: 's',
  );
}

final _f15 = lmAile(
  'fz_su_dalgasi',
  'Su dalgalarında derinlik, hız ve dalga boyu',
  Topic.physics,
  Difficulty.easy,
  BloomLevel.anlama,
  (a, b, c) => switch (c % 3) {
    0 => _derinlikDegisimi(a, b, c ~/ 3),
    1 => _atmaSuresi(a, b, c ~/ 3),
    _ => _periyodikDalga(a, b, c ~/ 3),
  },
  exam: ExamKind.tyt,
  lesson: _fizik,
);

final lmFizikEk = <AdvancedFamily>[
  _f01,
  _f02,
  _f03,
  _f04,
  _f05,
  _f06,
  _f07,
  _f08,
  _f09,
  _f10,
  _f11,
  _f12,
  _f13,
  _f14,
  _f15,
];
