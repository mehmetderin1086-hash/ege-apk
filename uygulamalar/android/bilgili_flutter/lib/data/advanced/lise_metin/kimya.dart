// Lise kimya metin aileleri: atomun yapısından elektrokimyaya 20 kazanım.
// Her aile 25 × 20 × 10 koordinatla 5.000 ayrı soru kökü üretir; veriler
// gerçek maddelerden seçilir, anahtarlar koordinatlardan kesin hesaplanır.
import 'denge.dart';
import 'ortak.dart';

const _altRakam = '₀₁₂₃₄₅₆₇₈₉';
const _ustRakam = '⁰¹²³⁴⁵⁶⁷⁸⁹';

/// Bu dosyada kullanılan atom kütleleri (g/mol); her kökte ayrıca yazılır.
const _atomKutlesi = <String, num>{
  'H': 1,
  'He': 4,
  'Li': 7,
  'B': 11,
  'C': 12,
  'N': 14,
  'O': 16,
  'F': 19,
  'Ne': 20,
  'Na': 23,
  'Mg': 24,
  'Al': 27,
  'Si': 28,
  'P': 31,
  'S': 32,
  'Cl': 35.5,
  'Ar': 40,
  'K': 39,
  'Ca': 40,
  'Ti': 48,
  'Cr': 52,
  'Mn': 55,
  'Fe': 56,
  'Ni': 59,
  'Cu': 64,
  'Zn': 65,
  'Br': 80,
  'Kr': 84,
  'Sr': 88,
  'Ag': 108,
  'Sn': 119,
  'I': 127,
  'Xe': 131,
  'Ba': 137,
  'Au': 197,
  'Pb': 207,
};

final _atomOnbellek = <String, Map<String, int>>{};

/// Formüldeki atom sayıları. Alt simgeleri ve parantezleri çözer; yük ve hâl
/// simgelerini atlar.
Map<String, int> _atomlar(String f) => _atomOnbellek[f] ??= () {
  final yigin = <Map<String, int>>[{}];
  var i = 0;
  int carpan() {
    var n = 0, var_ = false;
    while (i < f.length && _altRakam.contains(f[i])) {
      n = n * 10 + _altRakam.indexOf(f[i]);
      var_ = true;
      i++;
    }
    return var_ ? n : 1;
  }

  bool kucuk(int u) => u >= 97 && u <= 122;
  while (i < f.length) {
    final u = f.codeUnitAt(i);
    if (f[i] == '(') {
      yigin.add({});
      i++;
    } else if (f[i] == ')') {
      i++;
      final ic = yigin.removeLast();
      final k = carpan();
      ic.forEach((e, n) => yigin.last[e] = (yigin.last[e] ?? 0) + n * k);
    } else if (u >= 65 && u <= 90) {
      var s = f[i];
      i++;
      while (i < f.length && kucuk(f.codeUnitAt(i))) {
        s += f[i];
        i++;
      }
      final k = carpan();
      yigin.last[s] = (yigin.last[s] ?? 0) + k;
    } else {
      i++;
    }
  }
  return yigin.first;
}();

/// Mol kütlesi (g/mol).
num _mk(String f) {
  num m = 0;
  _atomlar(f).forEach((e, n) {
    final k = _atomKutlesi[e];
    if (k == null) throw StateError('Atom kütlesi yok: $e ($f)');
    m += k * n;
  });
  return m;
}

/// Verilen formüllerde geçen elementlerin atom kütleleri: “H: 1, O: 16”.
String _kut(List<String> formuller, {String haric = ''}) {
  final gorulen = <String>[];
  for (final f in formuller) {
    for (final e in _atomlar(f).keys) {
      if (e != haric && !gorulen.contains(e)) gorulen.add(e);
    }
  }
  return gorulen.map((e) => '$e: ${tr(_atomKutlesi[e]!)}').join(', ');
}

num _on(int d) {
  num p = 1;
  for (var j = 0; j < d; j++) {
    p *= 10;
  }
  return p;
}

/// Yuvarlayarak yazar; eksi işaretini “−” yapar.
String _yz(num x, [int d = 2]) => tr(x, d).replaceFirst('-', '−');

/// Kökte ve anahtarda kullanılan veriyi yazar; [d] basamakta kesin değilse
/// hata verir. Böylece yuvarlanmış bir sayı fark edilmeden köke giremez.
String _t(num x, [int d = 2]) {
  final y = x * _on(d);
  if ((y - y.roundToDouble()).abs() > 1e-6 * (1 + y.abs())) {
    throw StateError('Kesin değil: $x ($d basamak)');
  }
  return _yz(x, d);
}

String _isaretli(num x, [int d = 2]) => x > 0 ? '+${_t(x, d)}' : _t(x, d);

String _ust(int n) =>
    '${n < 0 ? '⁻' : ''}${'${n.abs()}'.split('').map((r) => _ustRakam[int.parse(r)]).join()}';

String _alt(int n) => '$n'.split('').map((r) => _altRakam[int.parse(r)]).join();

/// İyon yükü üst simgesi: 2 → “²⁺”, −1 → “⁻”.
String _yuk(int q) =>
    q == 0 ? '' : '${q.abs() == 1 ? '' : _ust(q.abs())}${q > 0 ? '⁺' : '⁻'}';

/// İyon yükünün yazıyla gösterimi: 2 → “2+”, −1 → “1−”.
String _yukYazi(int q) => '${q.abs()}${q > 0 ? '+' : '−'}';

/// m·10ᵉ biçiminde bilimsel gösterim; m, [1, 10) aralığına getirilir.
String _bilimsel(num m, int e) {
  var x = m.toDouble(), us = e;
  while (x >= 10 - 1e-9) {
    x /= 10;
    us++;
  }
  while (x < 1 - 1e-9) {
    x *= 10;
    us--;
  }
  final govde = _t(x, 4);
  return govde == '1' ? '10${_ust(us)}' : '$govde·10${_ust(us)}';
}

/// Sayısal yanıtlı soru. Doğru yanıt kesin yazılır; çeldiriciler tipik
/// hatalardan gelir, yetmezse komşu değerlerle tamamlanır.
AdvancedItem _say(
  String kok,
  num dogru,
  Iterable<num> adaylar,
  String aciklama, {
  String birim = '',
  String on = '',
  int basamak = 2,
  bool arti = true,
  bool isaret = false,
}) {
  String yaz(num x, {bool kesin = false}) {
    var s = kesin ? _t(x, basamak) : _yz(x, basamak);
    if (isaret && x > 0 && s != '0') s = '+$s';
    return birimli('$on$s', birim);
  }

  final d = dogru.toDouble(), m = d.abs();
  final tam = (d - d.roundToDouble()).abs() < 1e-9;
  final enKucuk = 1 / _on(basamak);
  var adim = tam
      ? (m >= 200 ? 10.0 : (m >= 40 ? 5.0 : 1.0))
      : (m >= 20
            ? 1.0
            : (m >= 2 ? 0.5 : (m >= 0.3 ? 0.1 : (m >= 0.03 ? 0.01 : 0.001))));
  if (adim < enKucuk) adim = enKucuk;
  final esik = 0.5 / _on(basamak);
  final havuz = <num>[
    ...adaylar,
    d + adim,
    d - adim,
    d + 2 * adim,
    d - 2 * adim,
    d + 3 * adim,
    d + 4 * adim,
    d + 5 * adim,
  ];
  return secenekli(
    kok,
    yaz(dogru, kesin: true),
    havuz.where((x) => x.isFinite && (!arti || x >= esik)).map(yaz),
    aciklama,
  );
}

/// Oranı en çok iki ondalıkla yazılabiliyorsa ondalık, değilse kesir yazar.
String _oran(int n, int d) {
  if (d < 0) return _oran(-n, -d);
  final g = n.gcd(d);
  final p = n ~/ g, q = d ~/ g;
  return 100 % q == 0 ? _yz(p / q) : kesir(p, q);
}

/// Oran yanıtlı soru; adaylar (pay, payda) ikilileridir.
AdvancedItem _oranli(
  String kok,
  int n,
  int d,
  Iterable<(int, int)> adaylar,
  String aciklama,
) => secenekli(
  kok,
  _oran(n, d),
  [
    ...adaylar,
    (2 * n, d),
    (n, 2 * d),
    (3 * n, d),
    (n, 3 * d),
    (n + d, d),
    (5 * n, d),
    (n, 5 * d),
  ].where((x) => x.$1 > 0 && x.$2 > 0).map((x) => _oran(x.$1, x.$2)),
  aciklama,
);

/// (a, b, c) koordinatlı vakanın hedef değer sırası (denge.dart · hedefSira).
int _sira(int a, int b, int c, [int tuz = 0]) =>
    hedefSira(a + 25 * b + 500 * c, tuz);

/// [_say] gibi; ancak çeldiricileri, anahtardan küçük olanların sayısı [sira]
/// (0 … 3) olacak biçimde seçer. [adaylar] öncelik sırasıyla tipik hata
/// değerleridir (anahtarın iki yanında da); en sonda, yalnız gerekirse,
/// anahtarın iki yanındaki komşu değerler kullanılır. Bir yanda tipik hata
/// yetmediğinde en çok [komsu] komşu değer kullanılır; daha fazlası
/// gerekecekse hedef sıra, gereken en küçük adımla kaydırılır. Komşu değerler
/// yalnız ([komsuAlt], [komsuUst]) açık aralığından alınır; adımları
/// [komsuOlcek] (verilmezse anahtarın kendisi) büyüklüğüne göre seçilir.
AdvancedItem _saySirali(
  String kok,
  num dogru,
  Iterable<num> adaylar,
  String aciklama,
  int sira, {
  String birim = '',
  String on = '',
  int basamak = 2,
  bool arti = true,
  bool isaret = false,
  int komsu = 1,
  num komsuAlt = double.negativeInfinity,
  num komsuUst = double.infinity,
  num? komsuOlcek,
}) {
  String yaz(num x, {bool kesin = false}) {
    var s = kesin ? _t(x, basamak) : _yz(x, basamak);
    if (isaret && x > 0 && s != '0') s = '+$s';
    return birimli('$on$s', birim);
  }

  final d = dogru.toDouble();
  final adim = _komsuAdim((komsuOlcek ?? d).toDouble(), basamak);
  final esik = 0.5 / _on(basamak);
  bool gecerli(num x) => x.isFinite && (!arti || x >= esik);
  final anahtar = yaz(dogru, kesin: true);
  final tipik = <(num, String)>[];
  for (final x in adaylar.where(gecerli)) {
    final y = yaz(x);
    if (ayniSecenek(y, anahtar) || tipik.any((t) => ayniSecenek(t.$2, y))) {
      continue;
    }
    tipik.add((x, y));
  }
  final alt = tipik.where((t) => t.$1 < d).length, ust = tipik.length - alt;
  int asim(int s) {
    final gereken = (s > alt ? s - alt : 0) + (3 - s > ust ? 3 - s - ust : 0);
    return gereken > komsu ? gereken - komsu : 0;
  }

  var hedef = sira;
  for (var s = 0; s < 4; s++) {
    final fark = asim(s) - asim(hedef);
    if (fark < 0 || (fark == 0 && (s - sira).abs() < (hedef - sira).abs())) {
      hedef = s;
    }
  }
  return AdvancedItem(
    kok,
    anahtar,
    siraliCeldiriciler(d, anahtar, [
      ...tipik,
      for (var k = 1; k <= 6; k++)
        for (final x in [d + k * adim, d - k * adim])
          if (gecerli(x) && x > komsuAlt && x < komsuUst) (x, yaz(x)),
    ], hedef),
    aciklama,
  );
}

/// Komşu değer adımı: |d| değerinin dörtte birini aşmayan en büyük
/// 1·10ᵏ, 2·10ᵏ ya da 5·10ᵏ değeri; en az bir yazım basamağı (10⁻ᵇᵃˢᵃᵐᵃᵏ).
/// Böylece komşu değer anahtara yapışık bir eş (0,2 ile 0,19 gibi) olmaz.
double _komsuAdim(double d, int basamak) {
  final enKucuk = 1 / _on(basamak), hedef = d.abs() / 4;
  if (hedef <= enKucuk) return enKucuk.toDouble();
  var e = enKucuk.toDouble();
  while (e * 10 <= hedef + 1e-12) {
    e *= 10;
  }
  for (final k in const [5, 2]) {
    if (k * e <= hedef + 1e-12) return k * e;
  }
  return e;
}

/// Kesir yanıtlı soru; anahtarın değer sırası [sira] ile belirlenir. Adaylar
/// öncelik sırasıyla (pay, payda) ikilileridir; komşu kesirler en sona eklenir.
/// Yalnız ([alt], [ust]) açık aralığındaki değerler kullanılır (ör. mol kesri).
AdvancedItem _kesirSirali(
  String kok,
  int n,
  int d,
  Iterable<(int, int)> adaylar,
  String aciklama,
  int sira, {
  num alt = 0,
  num ust = 1,
}) {
  final anahtar = kesir(n, d);
  final havuz = [
    ...adaylar,
    (n + 1, d),
    (n - 1, d),
    (n, d + 1),
    (n, d - 1),
    (n + 2, d),
    (n - 2, d),
    (n + 1, d + 1),
    (n, d + 2),
  ].where((x) => x.$2 > 0 && x.$1 / x.$2 > alt && x.$1 / x.$2 < ust);
  return AdvancedItem(
    kok,
    anahtar,
    siraliCeldiriciler(n / d, anahtar, [
      for (final (p, q) in havuz) (p / q, kesir(p, q)),
    ], sira),
    aciklama,
  );
}

/// [x], [ref] değerinin 1/[kat] katı ile [kat] katı arasındaysa kendisi, değilse
/// NaN (aday listesinden düşer). Anahtardan çok uzak kalan ve bağlamda
/// gerçekçi olmayan büyüklükleri ayıklar.
num _olcekte(num x, num ref, [num kat = 4]) =>
    x >= ref / kat && x <= ref * kat ? x : double.nan;

/// Yalnız alt < x < üst aralığındaki adayları bırakır (ör. bir örnekteki
/// element kütlesi örneğin kütlesini aşamaz).
Iterable<num> _arada(Iterable<num> x, num alt, num ust) =>
    x.where((v) => v > alt && v < ust);

// ---------------------------------------------------------------------------
// 1. Atomun temel tanecikleri
// ---------------------------------------------------------------------------

// Yaygın tek atomlu iyonlar ve soy gazlar, doğada bulunan izotoplarının kütle
// numaralarıyla: (atom numarası, yük, kütle numaraları). Yükü 0 olanlar soy
// gaz atomlarıdır. Her grup aynı soy gaz düzenindeki izoelektronik türlerdir.
const _izoelektronikGruplar = [
  [
    (2, 0, [3, 4]),
    (3, 1, [6, 7]),
    (4, 2, [9]),
  ],
  [
    (7, -3, [14, 15]),
    (8, -2, [16, 17, 18]),
    (9, -1, [19]),
    (10, 0, [20, 21, 22]),
    (11, 1, [23]),
    (12, 2, [24, 25, 26]),
    (13, 3, [27]),
  ],
  [
    (15, -3, [31]),
    (16, -2, [32, 33, 34, 36]),
    (17, -1, [35, 37]),
    (18, 0, [36, 38, 40]),
    (19, 1, [39, 41]),
    (20, 2, [40, 42, 43, 44, 46, 48]),
    (21, 3, [45]),
    (22, 4, [46, 47, 48, 49, 50]),
  ],
  [
    (33, -3, [75]),
    (34, -2, [74, 76, 77, 78, 80, 82]),
    (35, -1, [79, 81]),
    (36, 0, [78, 80, 82, 83, 84, 86]),
    (37, 1, [85, 87]),
    (38, 2, [84, 86, 87, 88]),
    (39, 3, [89]),
    (40, 4, [90, 91, 92, 94, 96]),
  ],
  [
    (52, -2, [120, 122, 123, 124, 125, 126, 128, 130]),
    (53, -1, [127]),
    (54, 0, [124, 126, 128, 129, 130, 131, 132, 134, 136]),
    (55, 1, [133]),
    (56, 2, [130, 132, 134, 135, 136, 137, 138]),
    (57, 3, [139]),
    (58, 4, [136, 138, 140, 142]),
  ],
];

const _kalayIzotoplari = [112, 114, 115, 116, 117, 118, 119, 120, 122, 124];

// Soy gaz düzeninde olmayan yaygın iyonlar ve doğal izotopları.
const _digerIyonlar = [
  (24, 3, [50, 52, 53, 54]),
  (25, 2, [55]),
  (26, 2, [54, 56, 57, 58]),
  (26, 3, [54, 56, 57, 58]),
  (27, 2, [59]),
  (28, 2, [58, 60, 61, 62, 64]),
  (29, 1, [63, 65]),
  (29, 2, [63, 65]),
  (30, 2, [64, 66, 67, 68, 70]),
  (31, 3, [69, 71]),
  (47, 1, [107, 109]),
  (48, 2, [106, 108, 110, 111, 112, 113, 114, 116]),
  (49, 3, [113, 115]),
  (50, 2, _kalayIzotoplari),
  (50, 4, _kalayIzotoplari),
  (51, 3, [121, 123]),
  (80, 2, [196, 198, 199, 200, 201, 202, 204]),
  (82, 2, [204, 206, 207, 208]),
];

/// Tek iyon soruları: (atom numarası, yük, kütle numarası).
final _tekIyonlar = <(int, int, int)>[
  for (final g in _izoelektronikGruplar)
    for (final (z, q, kn) in g)
      if (q != 0)
        for (final a in kn) (z, q, a),
  for (final (z, q, kn) in _digerIyonlar)
    for (final a in kn) (z, q, a),
];

/// İzoelektronik çiftler: (1. tür atom no, yük, kütle no; 2. tür atom no,
/// yük). Kütle numarası verilen tür, sorunun kuruluşuna göre X ya da Y olur.
final _izoCiftleri = <(int, int, int, int, int)>[
  for (final g in _izoelektronikGruplar)
    for (final (z1, q1, kn) in g)
      for (final a in kn)
        for (final (z2, q2, _) in g)
          if (z2 != z1) (z1, q1, a, z2, q2),
];

/// “X²⁺ iyonu” ya da yüksüz soy gaz için “X atomu”.
String _tanecik(String harf, int q) =>
    q == 0 ? '$harf atomu' : '$harf${_yuk(q)} iyonu';

/// z − q işlemi: “20 − 2 = 18”, “17 + 1 = 18”; q = 0 ise yalnız sonuç.
String _cikar(int z, int q) =>
    q == 0 ? '$z' : (q > 0 ? '$z − $q = ${z - q}' : '$z + ${-q} = ${z - q}');

/// e + q işlemi: “18 + 2 = 20”, “18 − 1 = 17”; q = 0 ise yalnız sonuç.
String _ekle(int e, int q) =>
    q == 0 ? '$e' : (q > 0 ? '$e + $q = ${e + q}' : '$e − ${-q} = ${e + q}');

final _f01 = lmAile(
  'kim_atom',
  'Atom ve iyonlarda proton, nötron, elektron sayısı',
  Topic.chemistry,
  Difficulty.easy,
  BloomLevel.anlama,
  (a, b, c) {
    final sira = a + 25 * b + 500 * c;
    final tekSayi = 10 * _tekIyonlar.length;
    AdvancedItem soru(String kok, int yanit, List<int> yanlis, String cozum) =>
        sayisal(kok, yanit, yanlis, cozum, positive: true);
    if (sira >= tekSayi) {
      // İzoelektronik türlerle kurulan sorular.
      final j = sira - tekSayi;
      final tur = j % 6, adet = (lmAileBoyu - tekSayi + 5) ~/ 6;
      if (_izoCiftleri.length < adet) {
        throw StateError('İzoelektronik çift sayısı yetersiz');
      }
      final (z1, q1, a1, z2, q2) =
          _izoCiftleri[j ~/ 6 * _izoCiftleri.length ~/ adet];
      if (tur < 4) {
        // X türünün kütle numarası ya da nötron sayısı, Y türünün atom
        // numarası verilir.
        final zx = z1, q = q1, kn = a1, zy = z2, r = q2;
        final e = zy - r, n = kn - zx, hepsi = zx + n + e;
        final x = _tanecik('X', q), y = _tanecik('Y', r);
        final yol =
            '${y}nun elektron sayısı ${_cikar(zy, r)} olur. ${x}nda da $e '
            'elektron bulunduğundan X elementinin atom numarası '
            '${_ekle(e, q)} bulunur.';
        final iliski = 'atom numarası $zy olan $y ile izoelektroniktir';
        switch (tur) {
          case 0:
            return soru(
              'Kütle numarası $kn olan $x, $iliski. Buna göre X atomunun '
                  'çekirdeğindeki nötron sayısı kaçtır?',
              n,
              [kn - zy, kn - e, kn - (e - q), kn - zy - r, n + 1, n - 1],
              '$yol Nötron sayısı $kn − $zx = $n olur.',
            );
          case 1:
            return soru(
              'Çekirdeğinde $n nötron bulunan $x, $iliski. Buna göre X '
                  'atomunun kütle numarası kaçtır?',
              kn,
              [zy + n, e + n, e - q + n, zy + r + n, kn + 1, kn - 1],
              '$yol Kütle numarası $zx + $n = $kn olur.',
            );
          case 2:
            return soru(
              'Kütle numarası $kn olan $x, $iliski. Buna göre ${x}ndaki '
                  'proton, nötron ve elektron sayılarının toplamı kaçtır?',
              hepsi,
              [kn + zx, kn + zy, kn, kn + e + q.abs() + 1, n + e],
              '$yol Nötron sayısı $kn − $zx = $n olduğundan toplam $zx + $n + '
                  '$e = $hepsi bulunur.',
            );
          default:
            return soru(
              'Çekirdeğinde $n nötron bulunan $x, $iliski. Buna göre '
                  '${x}ndaki proton, nötron ve elektron sayılarının toplamı '
                  'kaçtır?',
              hepsi,
              [2 * zx + n, zy + n + e, 2 * e + n, e + n, zx + n],
              '$yol Toplam $zx + $n + $e = $hepsi bulunur.',
            );
        }
      }
      // Y türünün kütle numarası ve nötron sayısı verilir.
      final zy = z1, r = q1, ky = a1, zx = z2, q = q2;
      final ny = ky - zy, e = zy - r;
      final x = _tanecik('X', q), y = _tanecik('Y', r);
      final giris =
          'Kütle numarası $ky olan ${y}nun çekirdeğinde $ny nötron '
          'bulunmaktadır.';
      final yol =
          'Y elementinin atom numarası $ky − $ny = $zy, ${y}nun elektron '
          'sayısı ${_cikar(zy, r)} olur. ${x}nda da $e elektron bulunduğundan '
          'X elementinin atom numarası ${_ekle(e, q)} bulunur.';
      if (tur == 4) {
        return soru(
          '$giris $x, bu ${r == 0 ? 'atom' : 'iyon'} ile izoelektronik '
          'olduğuna göre X elementinin atom numarası kaçtır?',
          zx,
          [zy, e, e - q, zy + q, ky - zx, zx + 1],
          yol,
        );
      }
      return soru(
        '$giris Bu ${r == 0 ? 'atom' : 'iyon'} ile izoelektronik olan '
            '${x}ndaki proton sayısı ile elektron sayısının toplamı kaçtır?',
        zx + e,
        [2 * e, 2 * zx, zy + e, zx + zy, 2 * zy],
        '$yol Proton ve elektron sayılarının toplamı $zx + $e = ${zx + e} '
            'olur.',
      );
    }
    final (z, q, kn) = _tekIyonlar[sira ~/ 10];
    final n = kn - z;
    final e = z - q, hepsi = kn + e;
    final x = 'X${_yuk(q)}';
    final yuk = _yukYazi(q);
    final eIslem = q > 0 ? '$z − $q = $e' : '$z + ${-q} = $e';
    final zIslem = q > 0 ? '$e + $q = $z' : '$e − ${-q} = $z';
    final eYazi =
        'İyonun yükü $yuk olduğundan elektron sayısı $eIslem bulunur.';
    final zYazi = 'İyonun yükü $yuk olduğundan proton sayısı $zIslem olur.';
    switch (sira % 10) {
      case 0:
        return soru(
          'Kütle numarası $kn olan $x iyonunun çekirdeğinde $n nötron '
              'bulunmaktadır. Bu iyonun elektron sayısı kaçtır?',
          e,
          [z, z + q, kn - q, n],
          'Proton sayısı $kn − $n = $z olur. $eYazi',
        );
      case 1:
        return soru(
          '$x iyonunda $e elektron ve $n nötron bulunmaktadır. X atomunun '
              'kütle numarası kaçtır?',
          kn,
          [e + n, e - q + n, z, kn + q + q],
          '$zYazi Kütle numarası $z + $n = $kn bulunur.',
        );
      case 2:
        return soru(
          'Kütle numarası $kn olan $x iyonunda $e elektron bulunmaktadır. X '
              'atomunun çekirdeğindeki nötron sayısı kaçtır?',
          n,
          [kn - e, kn - e + q, z, e],
          '$zYazi Nötron sayısı $kn − $z = $n bulunur.',
        );
      case 3:
        return soru(
          'Atom numarası $z, kütle numarası $kn olan X atomundan oluşan $x '
              'iyonunda proton, nötron ve elektron sayılarının toplamı kaçtır?',
          hepsi,
          [kn + z, kn + z + q, kn + n, z + e],
          'Proton sayısı $z, nötron sayısı $kn − $z = $n, elektron sayısı '
              '$eIslem olur. Toplam $z + $n + $e = $hepsi bulunur.',
        );
      case 4:
        return _say(
          'Kütle numarası $kn olan bir X iyonunda $n nötron ve $e elektron '
              'bulunmaktadır. Bu iyonun yükü kaçtır?',
          q,
          [-q, q + 1, q - 1, q + 2, q - 2],
          'Proton sayısı $kn − $n = $z olur. Yük, proton sayısı ile elektron '
              'sayısının farkıdır: $z − $e = ${_isaretli(q)}.',
          arti: false,
          isaret: true,
        );
      case 5:
        return soru(
          '$x iyonunda proton, nötron ve elektron sayılarının toplamı $hepsi, '
              'nötron sayısı ise $n olarak verilmiştir. X elementinin atom '
              'numarası kaçtır?',
          z,
          [e, (hepsi - n) ~/ 2, z + q.abs() + 1, hepsi - n, z - q.abs() - 1],
          'Proton sayısı p ise elektron sayısı ${q > 0 ? 'p − $q' : 'p + ${-q}'} '
              'olur. p + $n + ${q > 0 ? 'p − $q' : 'p + ${-q}'} = $hepsi '
              'eşitliğinden p = $z bulunur.',
        );
      case 6:
        return soru(
          'Kütle numarası $kn olan $x iyonunda proton, nötron ve elektron '
              'sayılarının toplamı $hepsi olarak verilmiştir. X elementinin atom '
              'numarası kaçtır?',
          z,
          [e, e - q, n, z + 1, z - 1],
          'Proton ve nötron sayılarının toplamı $kn olduğundan elektron sayısı '
              '$hepsi − $kn = $e olur. $zYazi',
        );
      case 7:
        final f = n - z;
        return soru(
          'Kütle numarası $kn olan $x iyonunun çekirdeğindeki nötron sayısı '
              'proton sayısı${f == 0 ? 'na eşittir' : 'ndan $f fazladır'}. Bu '
              'iyonun elektron sayısı kaçtır?',
          e,
          [z, z + q, n, n - q, kn - q],
          'Proton sayısı p ise ${f == 0 ? 'p + p' : 'p + (p + $f)'} = $kn '
              'eşitliğinden p = $z olur. $eYazi',
        );
      case 8:
        return soru(
          '$x iyonunda $e elektron ve $n nötron bulunmaktadır. Bu iyondaki '
              'proton, nötron ve elektron sayılarının toplamı kaçtır?',
          hepsi,
          [2 * e + n, hepsi - 2 * q, e + n, kn],
          '$zYazi Toplam $z + $n + $e = $hepsi bulunur.',
        );
      default:
        return soru(
          'Kütle numarası $kn olan $x iyonunun çekirdeğinde $n nötron '
              'bulunmaktadır. Bu iyondaki proton sayısı ile elektron sayısının '
              'toplamı kaçtır?',
          z + e,
          [2 * z, z + z + q, kn + e, e, z],
          'Proton sayısı $kn − $n = $z olur. $eYazi Toplam $z + $e = '
              '${z + e} olur.',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 2. İzotoplar ve ortalama atom kütlesi
// ---------------------------------------------------------------------------

final _f02 = lmAile(
  'kim_izotop',
  'İzotop bolluğu ve ortalama atom kütlesi',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final m1 = 10 + 3 * a; // hafif izotopun kütle numarası
    // Doğada iki izotopu bulunan elementlerde kütle numarası farkı 1 ya da 2.
    final fark = 1 + c ~/ 5;
    final m2 = m1 + fark;
    final p = 8 + 4 * b, r = 100 - p; // hafif ve ağır izotop yüzdeleri
    final ort = m1 + fark * r / 100;
    const giris =
        'Doğada yalnızca iki izotopu bulunan X elementinin izotoplarının '
        'kütle numaraları';
    const giris2 =
        'Doğada yalnızca iki izotopu bulunan X elementinin ortalama atom '
        'kütlesi';
    switch (c % 5) {
      case 0:
        return _say(
          '$giris $m1 ve $m2 olarak verilmiştir. Kütle numarası $m1 olan '
              'izotopun doğadaki bolluğu %$p olduğuna göre X elementinin ortalama '
              'atom kütlesi kaçtır?',
          ort,
          [
            (m1 + m2) / 2,
            m1 + fark * p / 100,
            m1 + fark * r / 200,
            m2 - fark * p / 200,
          ],
          'Ortalama atom kütlesi ($m1·$p + $m2·$r) / 100 = ${_t(ort)} olur.',
        );
      case 1:
        return _say(
          '$giris $m1 ve $m2 olarak verilmiştir. Elementin ortalama atom kütlesi '
              '${_t(ort)} olduğuna göre kütle numarası $m2 olan izotopun doğadaki '
              'bolluk yüzdesi kaçtır?',
          r,
          [p, 50, r / 2, 100 - r / 2],
          on: '%',
          'Ağır izotopun kesri x olsun: $m1·(1 − x) + $m2·x = ${_t(ort)} '
              'eşitliğinden x = ${_t(ort - m1)} / $fark = ${_t(r / 100)} bulunur; '
              'bolluk %$r olur.',
        );
      case 2:
        return sayisal(
          '$giris2 ${_t(ort)} olarak hesaplanmıştır. Kütle numarası $m1 olan '
              'izotopun doğadaki bolluğu %$p olduğuna göre diğer izotopun kütle '
              'numarası kaçtır?',
          m2,
          [m2 + 1, m1 - 1, m2 + 2, m2 + 3],
          'Diğer izotopun bolluğu %$r olur. $m1·$p + m·$r = ${_t(ort)}·100 '
              'eşitliğinden m = ${_t(ort * 100 - m1 * p)} / $r = $m2 bulunur.',
          positive: true,
        );
      case 3:
        return _say(
          '$giris $m1 ve $m2 olarak verilmiştir. Elementin ortalama atom kütlesi '
              '${_t(ort)} olduğuna göre kütle numarası $m1 olan izotopun doğadaki '
              'bolluk yüzdesi kaçtır?',
          p,
          [r, 50, p / 2, 100 - p / 2],
          on: '%',
          'Hafif izotopun kesri y olsun: $m1·y + $m2·(1 − y) = ${_t(ort)} '
              'eşitliğinden y = ${_t(m2 - ort)} / $fark = ${_t(p / 100)} bulunur; '
              'bolluk %$p olur.',
        );
      default:
        return sayisal(
          '$giris2 ${_t(ort)} olarak hesaplanmıştır. Kütle numarası $m2 olan '
              'izotopun doğadaki bolluğu %$r olduğuna göre diğer izotopun kütle '
              'numarası kaçtır?',
          m1,
          [m1 - 1, m2 + 1, m1 - 2, m1 - 3],
          'Diğer izotopun bolluğu %$p olur. m·$p + $m2·$r = ${_t(ort)}·100 '
              'eşitliğinden m = ${_t(ort * 100 - m2 * r)} / $p = $m1 bulunur.',
          positive: true,
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 3. Elektron dizilimi, değerlik elektronu, periyot ve grup
// ---------------------------------------------------------------------------

// (baş kuantum sayısı, tür, orbital sayısı) — Z ≤ 38 için dolma sırası.
const _altKabuk = [
  (1, 's', 1),
  (2, 's', 1),
  (2, 'p', 3),
  (3, 's', 1),
  (3, 'p', 3),
  (4, 's', 1),
  (3, 'd', 5),
  (4, 'p', 3),
  (5, 's', 1),
];

// Dizilimi sorulan elementler: (atom numarası, doğada bulunan izotoplarının
// kütle numaraları, yaygın tek atomlu iyonunun yükü; iyonu yoksa 0). Temel hâl
// dizilimleri Aufbau sırasına uyar; Cr ve Cu gibi kural dışı elementler yoktur.
const _dizilimElementleri = [
  (5, [10, 11], 0),
  (6, [12, 13], 0),
  (7, [14, 15], -3),
  (8, [16, 17, 18], -2),
  (9, [19], -1),
  (10, [20, 21, 22], 0),
  (11, [23], 1),
  (12, [24, 25, 26], 2),
  (13, [27], 3),
  (14, [28, 29, 30], 0),
  (15, [31], -3),
  (16, [32, 33, 34, 36], -2),
  (17, [35, 37], -1),
  (18, [36, 38, 40], 0),
  (19, [39, 41], 1),
  (20, [40, 42, 43, 44, 46, 48], 2),
  (21, [45], 3),
  (22, [46, 47, 48, 49, 50], 4),
  (23, [51], 0),
  (25, [55], 2),
  (31, [69, 71], 3),
  (32, [70, 72, 73, 74, 76], 0),
  (33, [75], -3),
  (34, [74, 76, 77, 78, 80, 82], -2),
  (35, [79, 81], -1),
  (36, [78, 80, 82, 83, 84, 86], 0),
  (37, [85, 87], 1),
  (38, [84, 86, 87, 88], 2),
];

/// Atom numarasını buldurmanın yolları: (atom no, kütle no, iyon yükü, biçim).
/// Biçim 0–4 nötr atom, 5–8 iyon verisi kullanır.
final _dizilimVerileri = <(int, int, int, int)>[
  for (final (z, kn, q) in _dizilimElementleri)
    for (final a in kn)
      for (var f = 0; f < (q == 0 ? 5 : 9); f++) (z, a, q, f),
];

class _Dizilim {
  _Dizilim(this.z) {
    var kalan = z;
    final parca = <String>[];
    for (final (n, tur, orb) in _altKabuk) {
      if (kalan == 0) break;
      final e = kalan < 2 * orb ? kalan : 2 * orb;
      kalan -= e;
      parca.add('$n$tur${_ust(e)}');
      son = '$n$tur';
      katman[n - 1] += e;
      if (tur == 's') s += e;
      if (tur == 'p') p += e;
      tamDolu += e <= orb ? 0 : e - orb;
      dolu += e <= orb ? e : orb;
      if (n > periyot) periyot = n;
    }
    yazim = parca.join(' ');
    final dis = katman[periyot - 1];
    degerlik = z >= 21 && z <= 30 ? z - 18 : dis;
    grup = z >= 21 && z <= 30 ? z - 18 : (dis <= 2 ? dis : dis + 10);
    onceki = katman[periyot - 2];
    alt = z + (z <= 12 ? 8 : 18);
  }
  final int z;
  final katman = [0, 0, 0, 0, 0];
  var periyot = 0, s = 0, p = 0, tamDolu = 0, dolu = 0;
  late final int degerlik, grup, onceki, alt;
  late final String yazim;
  var son = '';
  String get katmanYazim => katman.where((e) => e > 0).join(', ');
}

final _f03 = lmAile(
  'kim_dizilim',
  'Elektron dizilimi, değerlik elektronu, periyot ve grup',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.anlama,
  (a, b, c) {
    final k = a + 25 * b;
    final (z, kn, q, bicim) =
        _dizilimVerileri[k * _dizilimVerileri.length ~/ 500];
    final d = _Dizilim(z);
    final n = kn - z, f = n - z, hepsi = 2 * z + n;
    final e = z - q, iyonHepsi = kn + e;
    final x = 'X${_yuk(q)}';
    final fazla = f == 0 ? 'na eşittir' : 'ndan $f fazladır';
    final iyonYolu =
        'İyonun yükü ${_yukYazi(q)} olduğundan atom numarası ${_ekle(e, q)} '
        'olur.';
    final String veri, bulus;
    switch (bicim) {
      case 0:
        veri =
            'Kütle numarası $kn olan nötr X atomunun çekirdeğinde $n nötron '
            'bulunmaktadır.';
        bulus = 'Atom numarası $kn − $n = $z olur.';
      case 1:
        veri =
            'Nötr X atomunun kütle numarası $kn olup nötron sayısı proton '
            'sayısı$fazla.';
        bulus =
            'Proton sayısı p ise ${f == 0 ? 'p + p' : 'p + (p + $f)'} = $kn '
            'eşitliğinden atom numarası $z olur.';
      case 2:
        veri =
            'Nötr X atomunda proton, nötron ve elektron sayılarının toplamı '
            '$hepsi, nötron sayısı ise $n olarak verilmiştir.';
        bulus =
            'Proton ve elektron sayıları eşit olduğundan atom numarası '
            '($hepsi − $n) / 2 = $z olur.';
      case 3:
        veri =
            'Kütle numarası $kn olan nötr X atomunda proton, nötron ve elektron '
            'sayılarının toplamı $hepsi olarak verilmiştir.';
        bulus =
            'Proton ve nötron sayılarının toplamı $kn olduğundan elektron '
            'sayısı $hepsi − $kn = $z olur; nötr atomda bu, atom numarasına '
            'eşittir.';
      case 4:
        veri =
            'Nötr X atomunun çekirdeğinde $n nötron bulunmaktadır ve nötron '
            'sayısı proton sayısı$fazla.';
        bulus = f == 0
            ? 'Proton sayısı nötron sayısına eşit olduğundan atom numarası $z '
                  'olur.'
            : 'Atom numarası $n − $f = $z olur.';
      case 5:
        veri = '$x iyonunda $e elektron ve $n nötron bulunmaktadır.';
        bulus = iyonYolu;
      case 6:
        veri = 'Kütle numarası $kn olan $x iyonunda $e elektron bulunmaktadır.';
        bulus = iyonYolu;
      case 7:
        veri =
            'Kütle numarası $kn olan $x iyonunda proton, nötron ve elektron '
            'sayılarının toplamı $iyonHepsi olarak verilmiştir.';
        bulus = 'Elektron sayısı $iyonHepsi − $kn = $e olur. $iyonYolu';
      default:
        final pe = q > 0 ? 'p − $q' : 'p + ${-q}';
        veri =
            '$x iyonunda proton, nötron ve elektron sayılarının toplamı '
            '$iyonHepsi, nötron sayısı ise $n olarak verilmiştir.';
        bulus =
            'Proton sayısı p ise elektron sayısı $pe olur. p + $n + ($pe) = '
            '$iyonHepsi eşitliğinden atom numarası $z bulunur.';
    }
    final dizi = '$bulus Temel hâl dizilimi: ${d.yazim}.';
    AdvancedItem tamSayi(
      String soru,
      int yanit,
      List<int> yanlis,
      String son,
    ) => sayisal('$veri $soru', yanit, yanlis, '$dizi $son', positive: true);
    switch (c) {
      case 0:
        return tamSayi(
          'Buna göre X elementi periyodik sistemin kaçıncı periyodunda yer alır?',
          d.periyot,
          [d.degerlik, d.periyot + 1, d.periyot - 1, d.grup],
          'Elektron bulunduran en yüksek katman ${d.periyot} olduğundan element '
              '${d.periyot}. periyottadır.',
        );
      case 1:
        return tamSayi(
          'Buna göre X elementinin periyodik sistemdeki grup numarası '
              '(IUPAC, 1–18 arası) kaçtır?',
          d.grup,
          [d.degerlik, d.grup + 1, d.grup - 1, d.periyot, d.degerlik + 8],
          'Değerlik elektron sayısı ${d.degerlik} olduğundan element '
              '${d.grup}. grupta yer alır.',
        );
      case 2:
        return tamSayi(
          'Buna göre X atomunun değerlik elektron sayısı kaçtır?',
          d.degerlik,
          [d.periyot, d.grup, d.degerlik + 1, d.onceki, d.degerlik - 1],
          'Değerlik elektron sayısı ${d.degerlik} bulunur.',
        );
      case 3:
        return tamSayi(
          'Buna göre temel hâldeki X atomunun tam dolu orbital sayısı kaçtır?',
          d.tamDolu,
          [d.dolu, d.tamDolu + 1, d.tamDolu - 1, d.yazim.split(' ').length],
          'İki elektron taşıyan orbital sayısı ${d.tamDolu} olur.',
        );
      case 4:
        return tamSayi(
          'Buna göre temel hâldeki X atomunda elektron bulunduran orbital '
              'sayısı kaçtır?',
          d.dolu,
          [d.tamDolu, d.yazim.split(' ').length, d.dolu + 1, d.dolu - 1],
          'En az bir elektron taşıyan orbital sayısı ${d.dolu} olur.',
        );
      case 5:
        return tamSayi(
          'Buna göre temel hâldeki X atomunun s orbitallerinde toplam kaç '
              'elektron bulunur?',
          d.s,
          [d.p, d.s + 2, d.s - 2, d.s + 1, d.periyot],
          's orbitallerindeki elektronların toplamı ${d.s} olur.',
        );
      case 6:
        return tamSayi(
          'Buna göre temel hâldeki X atomunun p orbitallerinde toplam kaç '
              'elektron bulunur?',
          d.p,
          [d.s, d.p + 6, d.p - 6, d.degerlik, d.p + 1],
          'p orbitallerindeki elektronların toplamı ${d.p} olur.',
        );
      case 7:
        return tamSayi(
          'Buna göre X ile aynı grupta ve bir sonraki periyotta yer alan '
              'elementin atom numarası kaçtır?',
          d.alt,
          [z + 8, z + 18, z + 10, z + 2, z + 32],
          'Element ${d.periyot}. periyot ${d.grup}. gruptadır. Bir alt periyotta '
              'aynı gruba ${d.alt - z} element sonra gelinir: $z + '
              '${d.alt - z} = ${d.alt}.',
        );
      case 8:
        return tamSayi(
          'Buna göre temel hâldeki X atomunun katman elektron diziliminde, en '
              'dış katmandan bir önceki katmanda kaç elektron bulunur?',
          d.onceki,
          [d.degerlik, 8, 18, 2, d.katman[d.periyot - 1]],
          'Katman dizilimi ${d.katmanYazim} olduğundan aranan sayı '
              '${d.onceki} olur.',
        );
      default:
        final sira = [
          for (final (n, tur, _) in _altKabuk) '$n$tur',
          '4d',
          '5p',
        ];
        final yer = sira.indexOf(d.son);
        return secenekli(
          '$veri Buna göre X atomunun temel hâl elektron dizilimi Aufbau '
              'ilkesine göre yazıldığında son elektron hangi orbitale '
              'yerleşir?',
          d.son,
          [sira[yer - 1], sira[yer + 1], sira[yer - 2], sira[yer + 2]],
          '$dizi Dizilim Aufbau sırasıyla yazıldığında son elektron ${d.son} '
              'orbitaline yerleşir.',
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 4. Mol, kütle ve tanecik sayısı
// ---------------------------------------------------------------------------

const _molekuller = [
  ('H₂O', 'su'),
  ('CO₂', 'karbon dioksit'),
  ('NH₃', 'amonyak'),
  ('CH₄', 'metan'),
  ('O₂', 'oksijen gazı'),
  ('N₂', 'azot gazı'),
  ('SO₂', 'kükürt dioksit'),
  ('SO₃', 'kükürt trioksit'),
  ('C₂H₆', 'etan'),
  ('C₃H₈', 'propan'),
  ('C₂H₄', 'eten'),
  ('C₂H₂', 'asetilen'),
  ('C₆H₁₂O₆', 'glikoz'),
  ('C₂H₅OH', 'etanol'),
  ('HCl', 'hidrojen klorür'),
  ('NO₂', 'azot dioksit'),
  ('CO', 'karbon monoksit'),
  ('H₂S', 'hidrojen sülfür'),
  ('H₂SO₄', 'sülfürik asit'),
  ('HNO₃', 'nitrik asit'),
  ('CH₃OH', 'metanol'),
  ('C₄H₁₀', 'bütan'),
  ('N₂O₅', 'diazot pentaoksit'),
  ('C₆H₆', 'benzen'),
  ('CH₃COOH', 'asetik asit'),
];

final _f04 = lmAile(
  'kim_mol',
  'Mol, kütle ve tanecik sayısı dönüşümleri',
  Topic.chemistry,
  Difficulty.easy,
  BloomLevel.uygulama,
  (a, b, c) {
    final (f, ad) = _molekuller[a];
    final mk = _mk(f);
    final atomlar = _atomlar(f);
    final atom = atomlar.values.fold(0, (x, y) => x + y);
    num yalin = 0; // alt simgeleri yok sayan hatalı mol kütlesi
    for (final e in atomlar.keys) {
      yalin += _atomKutlesi[e]!;
    }
    final t = b + 1 + 20 * (c ~/ 5);
    final n = t / 10, m = mk * t / 10;
    final madde = '$ad ($f)';
    final kut = _kut([f]);
    final mkYazi = 'Mol kütlesi ${_t(mk)} g/mol olur.';
    switch (c % 5) {
      case 0:
        return _say(
          'Kütlesi ${_t(m)} gram olan $madde örneği kaç moldür? ($kut)',
          n,
          [n * atom, mk / m, m / yalin, n / atom, n * 10],
          '$mkYazi n = ${_t(m)} / ${_t(mk)} = ${_t(n)} mol bulunur.',
          birim: 'mol',
        );
      case 1:
        return _say(
          '${_t(n)} mol $madde kaç gramdır? ($kut)',
          m,
          [n * yalin, mk / n, m / atom, m * atom, mk + n],
          '$mkYazi m = ${_t(n)}·${_t(mk)} = ${_t(m)} gram bulunur.',
          birim: 'g',
        );
      case 2:
        return _say(
          'Kütlesi ${_t(m)} gram olan $madde örneğinde toplam kaç mol atom '
              'bulunur? ($kut)',
          n * atom,
          [n, n * atomlar.length, m / yalin, n * atom * 2, n * (atom + 1)],
          '$mkYazi Örnek ${_t(m)} / ${_t(mk)} = ${_t(n)} moldür. Bir molekülde '
              '$atom atom bulunduğundan toplam ${_t(n)}·$atom = ${_t(n * atom)} '
              'mol atom vardır.',
          birim: 'mol',
        );
      case 3:
        return _say(
          '${_bilimsel(6.02 * t, 22)} tane molekül içeren $madde örneği kaç '
              'gramdır? ($kut; Avogadro sayısı N_A = 6,02·10²³)',
          m,
          [n * yalin, m * atom, m / atom, n * 10 + mk, mk],
          'Mol sayısı ${_bilimsel(6.02 * t, 22)} / 6,02·10²³ = ${_t(n)} olur. '
              '$mkYazi m = ${_t(n)}·${_t(mk)} = ${_t(m)} gram bulunur.',
          birim: 'g',
        );
      default:
        return _say(
          'Toplam ${_t(n * atom)} mol atom içeren $madde örneği kaç gramdır? '
              '($kut)',
          m,
          [n * atom * mk, n * atom * yalin, m / atom, n * yalin],
          'Bir molekülde $atom atom bulunduğundan örnek ${_t(n * atom)} / $atom '
              '= ${_t(n)} moldür. $mkYazi m = ${_t(n)}·${_t(mk)} = ${_t(m)} gram '
              'bulunur.',
          birim: 'g',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 5. Mol kütlesi ve kütlece yüzde bileşim
// ---------------------------------------------------------------------------

// (bileşik, ad, sorulan element): kütlece yüzdesi en çok iki ondalıklıdır.
const _yuzdeCiftleri = [
  ('CaCO₃', 'kalsiyum karbonat', 'Ca'),
  ('CaCO₃', 'kalsiyum karbonat', 'O'),
  ('SO₃', 'kükürt trioksit', 'S'),
  ('CH₄', 'metan', 'C'),
  ('NaOH', 'sodyum hidroksit', 'Na'),
  ('MgO', 'magnezyum oksit', 'Mg'),
  ('Fe₂O₃', 'demir(III) oksit', 'Fe'),
  ('CuO', 'bakır(II) oksit', 'Cu'),
  ('C₂H₆', 'etan', 'C'),
  ('NH₄NO₃', 'amonyum nitrat', 'N'),
  ('CuSO₄', 'bakır(II) sülfat', 'Cu'),
  ('CuSO₄', 'bakır(II) sülfat', 'S'),
  ('C₃H₄', 'propin', 'C'),
  ('CaBr₂', 'kalsiyum bromür', 'Br'),
  ('KHCO₃', 'potasyum bikarbonat', 'K'),
  ('C₆H₁₂O₆', 'glikoz', 'C'),
  ('HF', 'hidrojen florür', 'F'),
  ('Fe₂(SO₄)₃', 'demir(III) sülfat', 'Fe'),
  ('Fe₂(SO₄)₃', 'demir(III) sülfat', 'S'),
  ('C₇H₁₆', 'heptan', 'C'),
  ('TiO₂', 'titanyum dioksit', 'Ti'),
  ('Cu₂S', 'bakır(I) sülfür', 'Cu'),
  ('CaC₂', 'kalsiyum karbür', 'Ca'),
  ('CH₃OH', 'metanol', 'O'),
  ('Mg₃N₂', 'magnezyum nitrür', 'Mg'),
];

final _f05 = lmAile(
  'kim_yuzde_bilesim',
  'Mol kütlesi ve kütlece yüzde bileşim',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (f, ad, el) = _yuzdeCiftleri[a];
    final mk = _mk(f);
    final atomlar = _atomlar(f);
    final adet = atomlar[el]!;
    final atomSay = atomlar.values.fold(0, (x, y) => x + y);
    final ak = _atomKutlesi[el]!;
    final pay = adet * ak, kalan = mk - pay; // 1 moldeki element ve diğerleri
    final yuzde = 100 * pay / mk;
    final t = b + 1 + 20 * (c ~/ 5);
    final m = mk * t / 10, g = pay * t / 10, n = t / 10;
    final madde = '$ad ($f)';
    final kut = _kut([f]);
    final payYazi = adet == 1 ? _t(ak) : '$adet·${_t(ak)} = ${_t(pay)}';
    final molYazi =
        'Bir mol bileşik ${_t(mk)} gramdır ve $payYazi gram $el içerir.';
    // Alt simgeleri yok sayan öğrencinin kullandığı "mol kütlesi".
    final tekli = atomlar.keys.fold<num>(0, (x, e) => x + _atomKutlesi[e]!);
    final sira = _sira(a, b, c);
    switch (c % 5) {
      case 0:
        return _saySirali(
          '${_t(m)} gram $madde bileşiğinde kaç gram $el elementi bulunur? '
              '($kut)',
          g,
          _arada(
            [
              m * ak / tekli,
              m - g,
              m * ak / mk,
              m * adet / atomSay,
              m * pay / kalan,
              g / 2,
              g * 2,
              (m - g) / 2,
            ],
            0,
            m,
          ),
          '$molYazi ${_t(m)} gram bileşikte ${_t(m)}·${_t(pay)} / ${_t(mk)} = '
              '${_t(g)} gram $el bulunur.',
          sira,
          birim: 'g',
          komsuUst: m,
        );
      case 1:
        return _saySirali(
          '${_t(g)} gram $el elementi içeren $madde örneğinin kütlesi kaç '
              'gramdır? ($kut)',
          m,
          [
            g * kalan / pay,
            g * tekli / ak,
            g * mk / ak,
            g * atomSay / adet,
            g * pay / mk,
            m + g,
            m / 2,
            m * 2,
            g + kalan,
          ],
          '$molYazi Örneğin kütlesi ${_t(g)}·${_t(mk)} / ${_t(pay)} = ${_t(m)} '
              'gram olur.',
          sira,
          birim: 'g',
          komsuAlt: g,
        );
      case 2:
        return _saySirali(
          'Bir $madde örneğinin ${_t(m)} gramında ${_t(g)} gram $el elementi '
              'bulunduğu belirlenmiştir. Buna göre bileşikteki $el elementinin '
              'kütlece yüzdesi kaçtır?',
          yuzde,
          _arada(
            [
              100 * ak / tekli,
              100 - yuzde,
              100 * ak / mk,
              100 * adet / atomSay,
              100 * pay / kalan,
              yuzde / 2,
              yuzde * 2,
            ],
            0,
            100,
          ),
          on: '%',
          'Kütlece yüzde ${_t(g)} / ${_t(m)}·100 = %${_t(yuzde)} olur.',
          sira,
          komsuUst: 100,
        );
      case 3:
        return _saySirali(
          '${_t(n)} mol $madde bileşiğinde kaç gram $el elementi bulunur? '
              '($kut)',
          g,
          [
            n * ak,
            n * mk,
            n * kalan,
            n * ak * adet * adet,
            g / 2,
            g * 2,
            n * adet,
            g / (adet + 1),
          ],
          '$molYazi ${_t(n)} mol bileşikte ${_t(n)}·${_t(pay)} = ${_t(g)} gram '
              '$el bulunur.',
          sira,
          birim: 'g',
          komsuUst: n * mk,
        );
      default:
        // Bileşik adı verilmez; aksi hâlde yanıt bilinen bir sabit olurdu.
        final elMol = adet * t / 10;
        return _saySirali(
          'Formülünde ${adet == 1 ? 'bir' : '$adet'} tane $el atomu bulunan bir '
              'bileşiğin ${_t(m)} gramlık örneğinde ${_t(g)} gram $el elementi '
              'bulunmaktadır. Buna göre bileşiğin mol kütlesi kaç g/mol olur? '
              '($el: ${_t(ak)})',
          mk,
          [
            mk / adet,
            mk * adet,
            pay,
            kalan,
            ak * mk / kalan,
            mk / (adet * adet),
            mk * 2,
            mk / 2,
          ],
          '${_t(g)} gram $el ${_t(g)} / ${_t(ak)} = ${_t(elMol)} mol $el '
              'atomudur. ${adet == 1 ? 'Formülde bir $el atomu bulunduğundan örnek de' : 'Bir molekülde (formül biriminde) $adet $el atomu bulunduğundan örnek ${_t(elMol)} / $adet ='} '
              '${_t(n)} mol bileşiktir. Mol kütlesi ${_t(m)} / ${_t(n)} = '
              '${_t(mk)} g/mol olur.',
          sira,
          birim: 'g/mol',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 6. Kaba formül ve molekül formülü
// ---------------------------------------------------------------------------

// İki elementli bileşiklerin kaba formülleri; aynı element çiftinde oranlar
// birbirinden farklıdır.
const _kabaFormuller = [
  'Fe₂O₃',
  'Fe₃O₄',
  'FeO',
  'Al₂O₃',
  'SO₂',
  'SO₃',
  'CO₂',
  'CO',
  'CH₄',
  'CH₃',
  'CH₂',
  'C₃H₈',
  'N₂O',
  'NO',
  'N₂O₃',
  'NO₂',
  'N₂O₅',
  'Cu₂O',
  'CuO',
  'MgO',
  'Na₂O',
  'P₂O₅',
  'Mg₃N₂',
  'Al₄C₃',
  'FeS₂',
];

// Molekül formülü kaba formülünün en az iki katı olan bileşikler.
const _molekulFormulleri = [
  'C₂H₆',
  'C₂H₄',
  'C₃H₆',
  'C₄H₈',
  'C₂H₂',
  'C₆H₆',
  'C₄H₁₀',
  'C₆H₁₂O₆',
  'C₂H₄O₂',
  'C₃H₆O₃',
  'H₂O₂',
  'N₂O₄',
  'N₂H₄',
  'P₄O₁₀',
  'C₆H₁₄',
  'C₈H₁₈',
  'C₂H₆O₂',
  'C₄H₈O₂',
  'C₆H₁₂',
  'C₅H₁₀',
  'C₄H₆',
  'C₂H₂O₄',
  'C₁₀H₂₂',
  'C₅H₁₀O₅',
  'C₈H₈',
];

String _formul(List<String> el, List<int> adet) => [
  for (var j = 0; j < el.length; j++)
    '${el[j]}${adet[j] == 1 ? '' : _alt(adet[j])}',
].join();

String _sirala(List<String> x) => x.length == 1
    ? x.first
    : '${x.sublist(0, x.length - 1).join(', ')} ve ${x.last}';

final _f06 = lmAile(
  'kim_formul',
  'Kaba formül ve molekül formülü bulma',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.analiz,
  (a, b, c) {
    if (c < 5) {
      final atomlar = _atomlar(_kabaFormuller[a]);
      final el = atomlar.keys.toList(), adet = atomlar.values.toList();
      final k1 = _atomKutlesi[el[0]]!, k2 = _atomKutlesi[el[1]]!;
      final t = b + 1 + (c == 2 || c == 3 ? 20 : 0);
      final n1 = adet[0] * t / 50, n2 = adet[1] * t / 50;
      final m1 = n1 * k1, m2 = n2 * k2;
      final kut = _kut([_kabaFormuller[a]]);
      const soru = 'Bu bileşiğin kaba (basit) formülü nedir?';
      final giris =
          'Yalnızca ${el[0]} ve ${el[1]} elementlerinden oluşan bir '
          'bileşiğin';
      final kok = switch (c) {
        0 =>
          '$giris bir örneğinde ${_t(m1)} gram ${el[0]} ve ${_t(m2)} gram '
              '${el[1]} bulunmaktadır. $soru ($kut)',
        1 =>
          '$giris ${_t(m1 + m2)} gramlık örneğinde ${_t(m1)} gram ${el[0]} '
              'bulunmaktadır. $soru ($kut)',
        2 =>
          '${_t(m1)} gram ${el[0]} elementi ile ${_t(m2)} gram ${el[1]} '
              'elementi artansız birleşerek tek bir bileşik oluşturuyor. $soru '
              '($kut)',
        3 =>
          '$giris ${_t(m1 + m2)} gramlık örneğinde ${_t(m2)} gram ${el[1]} '
              'bulunmaktadır. $soru ($kut)',
        _ =>
          '$giris bir örneğinde ${_t(n1)} mol ${el[0]} atomu ve ${_t(m2)} '
              'gram ${el[1]} bulunmaktadır. $soru ($kut)',
      };
      // Kütle oranını mol oranı sanma hatası.
      final p1 = (adet[0] * k1).round(), p2 = (adet[1] * k2).round();
      final g = p1.gcd(p2);
      final on = switch (c) {
        1 =>
          '${el[1]} kütlesi ${_t(m1 + m2)} − ${_t(m1)} = ${_t(m2)} gramdır. ',
        3 =>
          '${el[0]} kütlesi ${_t(m1 + m2)} − ${_t(m2)} = ${_t(m1)} gramdır. ',
        _ => '',
      };
      final ilk = c == 4
          ? '${el[0]}: ${_t(n1)} mol'
          : '${el[0]}: ${_t(m1)} / ${_t(k1)} = ${_t(n1)} mol';
      return secenekli(
        kok,
        _formul(el, adet),
        [
          _formul(el, [adet[1], adet[0]]),
          if (p1 ~/ g <= 12 && p2 ~/ g <= 12) _formul(el, [p1 ~/ g, p2 ~/ g]),
          _formul(el, [2 * adet[0], 2 * adet[1]]),
          _formul(el, [adet[0], adet[1] + 1]),
          _formul(el, [adet[0] + 1, adet[1]]),
          _formul(el, [adet[0] + 1, adet[1] + 2]),
        ],
        '$on$ilk, ${el[1]}: ${_t(m2)} / ${_t(k2)} = ${_t(n2)} mol. Mol oranı '
        '${_t(n1)} : ${_t(n2)} = ${adet[0]} : ${adet[1]} olduğundan kaba formül '
        '${_formul(el, adet)} olur.',
      );
    }
    final f = _molekulFormulleri[a];
    final atomlar = _atomlar(f);
    final el = atomlar.keys.toList(), adet = atomlar.values.toList();
    final kat = adet.reduce((x, y) => x.gcd(y));
    final kabaAdet = [for (final x in adet) x ~/ kat];
    final kaba = _formul(el, kabaAdet);
    final mk = _mk(f), kabaMk = mk / kat;
    final kut = _kut([f]);
    final t = b + 1;
    final yanlis = [
      kaba,
      _formul(el, [for (final x in kabaAdet) x * (kat + 1)]),
      _formul(el, [
        for (final x in kabaAdet) x * (kat > 2 ? kat - 1 : kat + 2),
      ]),
      _formul(el, [adet[1], adet[0], ...adet.sublist(2)]),
      _formul(el, [adet[0], adet[1] + 2, ...adet.sublist(2)]),
    ];
    final elYazi = 'Yalnızca ${_sirala(el)} elementlerinden oluşan';
    const soru = 'Bu bileşiğin molekül formülü nedir?';
    final katYazi =
        'Kaba formül kütlesi ${_t(kabaMk)} olduğundan ${_t(mk)} / '
        '${_t(kabaMk)} = $kat; molekül formülü $f olur.';
    switch (c) {
      case 5:
      case 8:
        final n = t / 20, m = mk * t / 20;
        final giris =
            'Kaba formülü $kaba olan bir bileşiğin ${_t(n)} molü '
            '${_t(m)} gramdır.';
        final mkYazi =
            'Mol kütlesi ${_t(m)} / ${_t(n)} = ${_t(mk)} g/mol olur.';
        if (c == 5) {
          return secenekli(
            '$giris $soru ($kut)',
            f,
            yanlis,
            '$mkYazi $katYazi',
          );
        }
        final toplam = adet.fold(0, (x, y) => x + y);
        return sayisal(
          '$giris Bu bileşiğin bir molekülünde toplam kaç atom bulunur? ($kut)',
          toplam,
          [toplam ~/ kat, toplam ~/ kat * (kat + 1), kat, toplam + kat],
          '$mkYazi $katYazi Bir molekülde toplam $toplam atom bulunur.',
          positive: true,
        );
      case 6:
        final n = t / 20;
        final veri = _sirala([
          for (var j = 0; j < el.length; j++)
            '${_t(n * adet[j] * _atomKutlesi[el[j]]!)} gram ${el[j]}',
        ]);
        return secenekli(
          '$elYazi bir bileşiğin ${_t(n)} molünde $veri bulunmaktadır. $soru '
              '($kut)',
          f,
          yanlis,
          'Bir moldeki atom sayıları: ${[for (var j = 0; j < el.length; j++) '${el[j]} için ${_t(n * adet[j] * _atomKutlesi[el[j]]!)} / (${_t(n)}·${_t(_atomKutlesi[el[j]]!)}) = ${adet[j]}'].join(', ')}. Molekül formülü $f olur.',
        );
      case 7:
        final n = t / 20;
        final veri = _sirala([
          for (var j = 0; j < el.length; j++)
            '${_t(n * adet[j])} mol ${el[j]} atomu',
        ]);
        return secenekli(
          '$elYazi bir bileşiğin ${_t(n)} molünde $veri bulunmaktadır. $soru',
          f,
          yanlis,
          'Bir moldeki atom sayıları: ${[for (var j = 0; j < el.length; j++) '${el[j]} için ${_t(n * adet[j])} / ${_t(n)} = ${adet[j]}'].join(', ')}. Molekül formülü $f olur.',
        );
      default:
        final s = t / 50;
        final veri = _sirala([
          for (var j = 0; j < el.length; j++)
            '${_t(s * adet[j] * _atomKutlesi[el[j]]!)} gram ${el[j]}',
        ]);
        return secenekli(
          '$elYazi ve mol kütlesi ${_t(mk)} g/mol olan bir bileşiğin bir '
              'örneğinde $veri bulunmaktadır. $soru ($kut)',
          f,
          yanlis,
          'Mol sayıları: ${[for (var j = 0; j < el.length; j++) '${el[j]} ${_t(s * adet[j])}'].join(', ')}. En küçük tam sayı oranı kaba formülü $kaba verir. '
              '$katYazi',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
  shortAnswer: false,
);

// ---------------------------------------------------------------------------
// 7. Tepkime denkleştirme ve mol oranları
// ---------------------------------------------------------------------------

// (girenler, ürünler, en küçük tam sayılı katsayılar). Her tepkimede dört tür
// vardır ve katsayıları farklı en az on sıralı tür çifti bulunur.
const _denklemler = [
  ('C₂H₆ + O₂', 'CO₂ + H₂O', [2, 7, 4, 6]),
  ('C₃H₈ + O₂', 'CO₂ + H₂O', [1, 5, 3, 4]),
  ('C₄H₁₀ + O₂', 'CO₂ + H₂O', [2, 13, 8, 10]),
  ('C₂H₄ + O₂', 'CO₂ + H₂O', [1, 3, 2, 2]),
  ('C₂H₂ + O₂', 'CO₂ + H₂O', [2, 5, 4, 2]),
  ('C₂H₅OH + O₂', 'CO₂ + H₂O', [1, 3, 2, 3]),
  ('CH₃OH + O₂', 'CO₂ + H₂O', [2, 3, 2, 4]),
  ('NH₃ + O₂', 'NO + H₂O', [4, 5, 4, 6]),
  ('NH₃ + O₂', 'N₂ + H₂O', [4, 3, 2, 6]),
  ('Fe₂O₃ + CO', 'Fe + CO₂', [1, 3, 2, 3]),
  ('Fe₂O₃ + H₂', 'Fe + H₂O', [1, 3, 2, 3]),
  ('Al + HCl', 'AlCl₃ + H₂', [2, 6, 2, 3]),
  ('Al + H₂SO₄', 'Al₂(SO₄)₃ + H₂', [2, 3, 1, 3]),
  ('Al(OH)₃ + H₂SO₄', 'Al₂(SO₄)₃ + H₂O', [2, 3, 1, 6]),
  ('FeS₂ + O₂', 'Fe₂O₃ + SO₂', [4, 11, 2, 8]),
  ('C₆H₆ + O₂', 'CO₂ + H₂O', [2, 15, 12, 6]),
  ('Fe₃O₄ + H₂', 'Fe + H₂O', [1, 4, 3, 4]),
  ('NO₂ + H₂O', 'HNO₃ + NO', [3, 1, 2, 1]),
  ('Al₂O₃ + HCl', 'AlCl₃ + H₂O', [1, 6, 2, 3]),
  ('SiO₂ + HF', 'SiF₄ + H₂O', [1, 4, 1, 2]),
  ('CS₂ + O₂', 'CO₂ + SO₂', [1, 3, 1, 2]),
  ('C₅H₁₂ + O₂', 'CO₂ + H₂O', [1, 8, 5, 6]),
  ('Ca(OH)₂ + H₃PO₄', 'Ca₃(PO₄)₂ + H₂O', [3, 2, 1, 6]),
  ('Mg₃N₂ + H₂O', 'Mg(OH)₂ + NH₃', [1, 6, 3, 2]),
  ('Al₄C₃ + H₂O', 'Al(OH)₃ + CH₄', [1, 12, 4, 3]),
];

String _katsayili(int k, String f) => k == 1 ? f : '$k$f';

final _f07 = lmAile(
  'kim_denklestirme',
  'Tepkime denkleştirme ve mol oranları',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (sol, sag, k) = _denklemler[a];
    final tur = [...sol.split(' + '), ...sag.split(' + ')];
    final ciftler = [
      for (var i = 0; i < 4; i++)
        for (var j = 0; j < 4; j++)
          if (i != j && k[i] != k[j]) (i, j),
    ];
    final (i, j) = ciftler[c];
    final n = k[i] * (b + 1) / 20, yanit = k[j] * (b + 1) / 20;
    final denk =
        '${_katsayili(k[0], tur[0])} + ${_katsayili(k[1], tur[1])} → '
        '${_katsayili(k[2], tur[2])} + ${_katsayili(k[3], tur[3])}';
    final veri = '${_t(n)} mol ${tur[i]}';
    final soru = i < 2
        ? (j < 2
              ? '$veri ile artansız tepkimeye girmek için kaç mol ${tur[j]} '
                    'gerekir?'
              : '$veri tamamen harcandığında en çok kaç mol ${tur[j]} oluşur?')
        : (j < 2
              ? '$veri elde etmek için en az kaç mol ${tur[j]} harcanmalıdır?'
              : '$veri oluştuğunda aynı anda kaç mol ${tur[j]} oluşur?');
    return _say(
      '$sol → $sag tepkimesi en küçük tam sayılarla denkleştiriliyor. Buna '
          'göre $soru',
      yanit,
      [n, n * k[i] / k[j], n * k[j], n / k[i], yanit / 2, yanit * 2],
      'Denk tepkime: $denk. Mol oranı ${tur[i]} : ${tur[j]} = ${k[i]} : ${k[j]} '
          'olduğundan ${_t(n)}·${k[j]} / ${k[i]} = ${_t(yanit)} mol bulunur.',
      birim: 'mol',
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 8. Kütle–kütle ve hacim hesapları
// ---------------------------------------------------------------------------

// (denk tepkime, tepken, katsayısı, gaz ürün, katsayısı)
const _gazTepkimeleri = [
  ('CaCO₃ → CaO + CO₂', 'CaCO₃', 1, 'CO₂', 1),
  ('2KClO₃ → 2KCl + 3O₂', 'KClO₃', 2, 'O₂', 3),
  ('Zn + 2HCl → ZnCl₂ + H₂', 'Zn', 1, 'H₂', 1),
  ('Mg + 2HCl → MgCl₂ + H₂', 'Mg', 1, 'H₂', 1),
  ('2Al + 6HCl → 2AlCl₃ + 3H₂', 'Al', 2, 'H₂', 3),
  ('2Na + 2H₂O → 2NaOH + H₂', 'Na', 2, 'H₂', 1),
  ('CH₄ + 2O₂ → CO₂ + 2H₂O', 'CH₄', 1, 'CO₂', 1),
  ('C₃H₈ + 5O₂ → 3CO₂ + 4H₂O', 'C₃H₈', 1, 'CO₂', 3),
  ('2H₂O₂ → 2H₂O + O₂', 'H₂O₂', 2, 'O₂', 1),
  ('2NaHCO₃ → Na₂CO₃ + H₂O + CO₂', 'NaHCO₃', 2, 'CO₂', 1),
  ('Fe + 2HCl → FeCl₂ + H₂', 'Fe', 1, 'H₂', 1),
  ('CaC₂ + 2H₂O → Ca(OH)₂ + C₂H₂', 'CaC₂', 1, 'C₂H₂', 1),
  ('2H₂O → 2H₂ + O₂', 'H₂O', 2, 'O₂', 1),
  ('N₂ + 3H₂ → 2NH₃', 'N₂', 1, 'NH₃', 2),
  ('S + O₂ → SO₂', 'S', 1, 'SO₂', 1),
  ('C + O₂ → CO₂', 'C', 1, 'CO₂', 1),
  ('MgCO₃ → MgO + CO₂', 'MgCO₃', 1, 'CO₂', 1),
  ('NH₄NO₂ → N₂ + 2H₂O', 'NH₄NO₂', 1, 'N₂', 1),
  ('2KNO₃ → 2KNO₂ + O₂', 'KNO₃', 2, 'O₂', 1),
  ('CaCO₃ + 2HCl → CaCl₂ + H₂O + CO₂', 'CaCO₃', 1, 'CO₂', 1),
  ('C₂H₅OH + 3O₂ → 2CO₂ + 3H₂O', 'C₂H₅OH', 1, 'CO₂', 2),
  ('Na₂CO₃ + 2HCl → 2NaCl + H₂O + CO₂', 'Na₂CO₃', 1, 'CO₂', 1),
  ('2C₂H₂ + 5O₂ → 4CO₂ + 2H₂O', 'C₂H₂', 2, 'CO₂', 4),
  ('C₆H₁₂O₆ → 2C₂H₅OH + 2CO₂', 'C₆H₁₂O₆', 1, 'CO₂', 2),
  ('CaH₂ + 2H₂O → Ca(OH)₂ + 2H₂', 'CaH₂', 1, 'H₂', 2),
];

final _f08 = lmAile(
  'kim_stokiyometri',
  'Tepkimelerde kütle ve gaz hacmi hesapları',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (denk, fa, ka, fb, kb) = _gazTepkimeleri[a];
    final ma = _mk(fa), mb = _mk(fb);
    final t = b + 1 + 20 * (c ~/ 5);
    final na = ka * t / 20, nb = kb * t / 20;
    final ga = na * ma, gb = nb * mb, v = nb * 22.4;
    final giris = '$denk tepkimesine göre';
    const nk = 'normal koşullarda 1 mol gaz 22,4 L hacim kaplar';
    final oran = '$fa : $fb mol oranı $ka : $kb olduğundan';
    final ters = ka / kb; // katsayı oranını ters kullanma
    final sira = _sira(a, b, c);
    switch (c % 5) {
      case 0:
        return _saySirali(
          '$giris ${_t(ga)} gram $fa tamamen tepkimeye girdiğinde kaç gram $fb '
              'oluşur? (${_kut([fa, fb])})',
          gb,
          [
            ga * kb / ka,
            nb * ma,
            na * mb,
            na * ters * mb,
            _olcekte(kb * mb, gb),
            nb,
            gb * 2,
            gb / 2,
          ],
          '${_t(ga)} / ${_t(ma)} = ${_t(na)} mol $fa harcanır. $oran '
              '${_t(nb)} mol $fb oluşur; kütlesi ${_t(nb)}·${_t(mb)} = ${_t(gb)} '
              'gramdır.',
          sira,
          birim: 'g',
        );
      case 1:
        return _saySirali(
          '$giris ${_t(ga)} gram $fa tamamen tepkimeye girdiğinde normal '
              'koşullarda kaç litre $fb gazı oluşur? (${_kut([fa])}; $nk)',
          v,
          [
            na * 22.4,
            na * ters * 22.4,
            na * kb * 22.4,
            ga / mb * 22.4,
            _olcekte(kb * 22.4, v),
            nb,
            gb,
            v * 2,
            v / 2,
          ],
          '${_t(ga)} / ${_t(ma)} = ${_t(na)} mol $fa harcanır. $oran '
              '${_t(nb)} mol $fb oluşur; hacmi ${_t(nb)}·22,4 = ${_t(v)} L olur.',
          sira,
          birim: 'L',
        );
      case 2:
        return _saySirali(
          '$giris normal koşullarda ${_t(v)} litre $fb gazı elde etmek için kaç '
              'gram $fa harcanmalıdır? (${_kut([fa])}; $nk)',
          ga,
          [
            nb * ma,
            nb * kb / ka * ma,
            na * mb,
            _olcekte(ka * ma, ga),
            gb,
            na,
            ga * 2,
            ga / 2,
          ],
          '${_t(v)} / 22,4 = ${_t(nb)} mol $fb oluşur. $oran ${_t(na)} mol $fa '
              'harcanır; kütlesi ${_t(na)}·${_t(ma)} = ${_t(ga)} gramdır.',
          sira,
          birim: 'g',
        );
      case 3:
        return _saySirali(
          '$giris ${_t(gb)} gram $fb oluşması için kaç gram $fa tepkimeye '
              'girmelidir? (${_kut([fa, fb])})',
          ga,
          [
            gb * ka / kb,
            nb * ma,
            nb * kb / ka * ma,
            na * mb,
            _olcekte(ka * ma, ga),
            na,
            gb,
            ga * 2,
            ga / 2,
          ],
          '${_t(gb)} / ${_t(mb)} = ${_t(nb)} mol $fb oluşur. $oran ${_t(na)} '
              'mol $fa harcanır; kütlesi ${_t(na)}·${_t(ma)} = ${_t(ga)} gramdır.',
          sira,
          birim: 'g',
        );
      default:
        return _saySirali(
          '$giris normal koşullarda ${_t(v)} litre $fb gazı oluştuğunda kaç mol '
              '$fa harcanmış olur? ($nk)',
          na,
          [
            nb,
            nb * kb / ka,
            v * ka / kb,
            v * ka / kb / 2,
            na * 2,
            na / 2,
            nb * 2,
            nb / 2,
          ],
          '${_t(v)} / 22,4 = ${_t(nb)} mol $fb oluşur. $oran ${_t(nb)}·$ka / $kb '
              '= ${_t(na)} mol $fa harcanır.',
          sira,
          birim: 'mol',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 9. Sınırlayıcı bileşen ve artan madde
// ---------------------------------------------------------------------------

// (denk tepkime, 1. tepken, katsayı, 2. tepken, katsayı, ürün, katsayı)
const _ikiTepkenli = [
  ('2H₂ + O₂ → 2H₂O', 'H₂', 2, 'O₂', 1, 'H₂O', 2),
  ('N₂ + 3H₂ → 2NH₃', 'N₂', 1, 'H₂', 3, 'NH₃', 2),
  ('2Mg + O₂ → 2MgO', 'Mg', 2, 'O₂', 1, 'MgO', 2),
  ('4Al + 3O₂ → 2Al₂O₃', 'Al', 4, 'O₂', 3, 'Al₂O₃', 2),
  ('2Na + Cl₂ → 2NaCl', 'Na', 2, 'Cl₂', 1, 'NaCl', 2),
  ('H₂ + Cl₂ → 2HCl', 'H₂', 1, 'Cl₂', 1, 'HCl', 2),
  ('2SO₂ + O₂ → 2SO₃', 'SO₂', 2, 'O₂', 1, 'SO₃', 2),
  ('2CO + O₂ → 2CO₂', 'CO', 2, 'O₂', 1, 'CO₂', 2),
  ('C + O₂ → CO₂', 'C', 1, 'O₂', 1, 'CO₂', 1),
  ('S + O₂ → SO₂', 'S', 1, 'O₂', 1, 'SO₂', 1),
  ('2Fe + 3Cl₂ → 2FeCl₃', 'Fe', 2, 'Cl₂', 3, 'FeCl₃', 2),
  ('2Al + 3Cl₂ → 2AlCl₃', 'Al', 2, 'Cl₂', 3, 'AlCl₃', 2),
  ('Ca + 2H₂O → Ca(OH)₂ + H₂', 'Ca', 1, 'H₂O', 2, 'Ca(OH)₂', 1),
  ('CaO + H₂O → Ca(OH)₂', 'CaO', 1, 'H₂O', 1, 'Ca(OH)₂', 1),
  ('2NO + O₂ → 2NO₂', 'NO', 2, 'O₂', 1, 'NO₂', 2),
  ('CH₄ + 2O₂ → CO₂ + 2H₂O', 'CH₄', 1, 'O₂', 2, 'CO₂', 1),
  ('Zn + 2HCl → ZnCl₂ + H₂', 'Zn', 1, 'HCl', 2, 'H₂', 1),
  ('Mg + 2HCl → MgCl₂ + H₂', 'Mg', 1, 'HCl', 2, 'MgCl₂', 1),
  ('NaOH + HCl → NaCl + H₂O', 'NaOH', 1, 'HCl', 1, 'NaCl', 1),
  ('3Mg + N₂ → Mg₃N₂', 'Mg', 3, 'N₂', 1, 'Mg₃N₂', 1),
  ('2Cu + O₂ → 2CuO', 'Cu', 2, 'O₂', 1, 'CuO', 2),
  ('Fe + S → FeS', 'Fe', 1, 'S', 1, 'FeS', 1),
  ('2Al + 3S → Al₂S₃', 'Al', 2, 'S', 3, 'Al₂S₃', 1),
  ('P₄ + 5O₂ → P₄O₁₀', 'P₄', 1, 'O₂', 5, 'P₄O₁₀', 1),
  ('N₂ + O₂ → 2NO', 'N₂', 1, 'O₂', 1, 'NO', 2),
];

final _f09 = lmAile(
  'kim_sinirlayici',
  'Sınırlayıcı bileşen ve artan madde',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final (denk, fa, ka, fb, kb, fc, kc) = _ikiTepkenli[a];
    final x = (1 + b % 10) / 10; // tepkime ilerlemesi (mol)
    final artan = (1 + (b + 3 * (c ~/ 5)) % 8) / 10; // artan madde (mol)
    final aSinir = b < 10;
    final na = ka * x + (aSinir ? 0 : artan),
        nb = kb * x + (aSinir ? artan : 0);
    final ma = _mk(fa), mb = _mk(fb), mc = _mk(fc);
    final fs = aSinir ? fa : fb, fe = aSinir ? fb : fa; // sınırlayıcı, artan
    final ks = aSinir ? ka : kb, ke = aSinir ? kb : ka;
    final ns = aSinir ? na : nb, ne = aSinir ? nb : na;
    final me = aSinir ? mb : ma;
    final nc = kc * x;
    final yanlisUrun = kc * ne / ke; // artan maddeden hesaplama hatası
    final giris = '$denk tepkimesine göre';
    final karar =
        '${_t(ns)} mol $fs için ${_t(ns)}·$ke / $ks = ${_t(ke * x)} mol $fe '
        'gerekir; eldeki ${_t(ne)} mol bundan fazla olduğundan sınırlayıcı '
        'bileşen $fs olur.';
    final molVeri = '${_t(na)} mol $fa ile ${_t(nb)} mol $fb';
    final kutleVeri = '${_t(na * ma)} gram $fa ile ${_t(nb * mb)} gram $fb';
    final cevir =
        '$fa: ${_t(na * ma)} / ${_t(ma)} = ${_t(na)} mol, $fb: ${_t(nb * mb)} / '
        '${_t(mb)} = ${_t(nb)} mol.';
    final ms = aSinir ? ma : mb; // sınırlayıcının mol kütlesi
    final sira = _sira(a, b, c);
    switch (c % 5) {
      case 0:
        return _saySirali(
          '$giris $molVeri tam verimle tepkimeye sokuluyor. En çok kaç mol $fc '
              'oluşur?',
          nc,
          [yanlisUrun, ns, ne, na + nb, ns * ks / kc, x, nc / 2, nc * 2, artan],
          '$karar Oluşan $fc miktarı ${_t(ns)}·$kc / $ks = ${_t(nc)} mol olur.',
          sira,
          birim: 'mol',
        );
      case 1:
        return _saySirali(
          '$giris $molVeri tam verimle tepkimeye sokuluyor. Tepkime sonunda '
              'artan maddeden kaç mol kalır?',
          artan,
          [
            (na - nb).abs(),
            ne - x,
            ke * x,
            ne,
            ns,
            ne - ns,
            artan / ke,
            ks * artan / ke,
            artan / 2,
            artan * 2,
            artan + x,
          ],
          '$karar Artan $fe miktarı ${_t(ne)} − ${_t(ke * x)} = ${_t(artan)} '
              'mol olur.',
          sira,
          birim: 'mol',
        );
      case 2:
        return _saySirali(
          '$giris $kutleVeri tam verimle tepkimeye sokuluyor. En çok kaç gram '
              '$fc oluşur? (${_kut([fa, fb, fc])})',
          nc * mc,
          [
            na * ma + nb * mb,
            yanlisUrun * mc,
            ns * mc,
            x * mc,
            nc,
            ns * ms,
            nc * mc / 2,
            nc * mc * 2,
          ],
          '$cevir $karar Oluşan $fc miktarı ${_t(nc)} mol, kütlesi '
              '${_t(nc)}·${_t(mc)} = ${_t(nc * mc)} gram olur.',
          sira,
          birim: 'g',
        );
      case 3:
        return _saySirali(
          '$giris $kutleVeri tam verimle tepkimeye sokuluyor. Tepkime sonunda '
              'artan maddenin kütlesi kaç gramdır? (${_kut([fa, fb])})',
          artan * me,
          [
            (na * ma - nb * mb).abs(),
            artan * ms,
            ne * me,
            (ne - x) * me,
            ke * x * me,
            artan,
            (ne - ns) * me,
            artan * me / 2,
            artan * me * 2,
          ],
          '$cevir $karar Artan $fe miktarı ${_t(ne)} − ${_t(ke * x)} = '
              '${_t(artan)} mol, kütlesi ${_t(artan)}·${_t(me)} = '
              '${_t(artan * me)} gram olur.',
          sira,
          birim: 'g',
        );
      default:
        return _saySirali(
          '$giris $molVeri tam verimle tepkimeye sokuluyor. En çok kaç gram $fc '
              'oluşur? (${_kut([fc])})',
          nc * mc,
          [
            yanlisUrun * mc,
            ns * mc,
            (na + nb) * mc,
            x * mc,
            nc,
            ne * mc,
            nc * mc / 2,
            nc * mc * 2,
          ],
          '$karar Oluşan $fc miktarı ${_t(nc)} mol, kütlesi ${_t(nc)}·${_t(mc)} '
              '= ${_t(nc * mc)} gram olur.',
          sira,
          birim: 'g',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 10. Yüzde verim ve saflık
// ---------------------------------------------------------------------------

// (denk tepkime, tepken, katsayısı, ürün, katsayısı)
const _verimTepkimeleri = [
  ('CaCO₃ → CaO + CO₂', 'CaCO₃', 1, 'CaO', 1),
  ('Fe₂O₃ + 3CO → 2Fe + 3CO₂', 'Fe₂O₃', 1, 'Fe', 2),
  ('C₆H₁₂O₆ → 2C₂H₅OH + 2CO₂', 'C₆H₁₂O₆', 1, 'C₂H₅OH', 2),
  ('CaO + H₂O → Ca(OH)₂', 'CaO', 1, 'Ca(OH)₂', 1),
  ('2Al₂O₃ → 4Al + 3O₂', 'Al₂O₃', 2, 'Al', 4),
  ('CuO + H₂ → Cu + H₂O', 'CuO', 1, 'Cu', 1),
  ('2KClO₃ → 2KCl + 3O₂', 'KClO₃', 2, 'O₂', 3),
  ('CaC₂ + 2H₂O → Ca(OH)₂ + C₂H₂', 'CaC₂', 1, 'C₂H₂', 1),
  ('2NaHCO₃ → Na₂CO₃ + H₂O + CO₂', 'NaHCO₃', 2, 'Na₂CO₃', 1),
  ('MgCO₃ → MgO + CO₂', 'MgCO₃', 1, 'MgO', 1),
  ('2Mg + O₂ → 2MgO', 'Mg', 2, 'MgO', 2),
  ('S + O₂ → SO₂', 'S', 1, 'SO₂', 1),
  ('Zn + H₂SO₄ → ZnSO₄ + H₂', 'Zn', 1, 'ZnSO₄', 1),
  ('2H₂O₂ → 2H₂O + O₂', 'H₂O₂', 2, 'O₂', 1),
  ('C + O₂ → CO₂', 'C', 1, 'CO₂', 1),
  ('Fe + S → FeS', 'Fe', 1, 'FeS', 1),
  ('4FeS₂ + 11O₂ → 2Fe₂O₃ + 8SO₂', 'FeS₂', 4, 'SO₂', 8),
  ('SiO₂ + 2C → Si + 2CO', 'SiO₂', 1, 'Si', 1),
  ('2Cu + O₂ → 2CuO', 'Cu', 2, 'CuO', 2),
  ('CaCO₃ + 2HCl → CaCl₂ + H₂O + CO₂', 'CaCO₃', 1, 'CO₂', 1),
  ('3Fe + 4H₂O → Fe₃O₄ + 4H₂', 'Fe', 3, 'Fe₃O₄', 1),
  ('2Al + 3H₂SO₄ → Al₂(SO₄)₃ + 3H₂', 'Al', 2, 'H₂', 3),
  ('Mg + 2HCl → MgCl₂ + H₂', 'Mg', 1, 'H₂', 1),
  ('2NaCl → 2Na + Cl₂', 'NaCl', 2, 'Cl₂', 1),
  ('Fe₃O₄ + 4H₂ → 3Fe + 4H₂O', 'Fe₃O₄', 1, 'Fe', 3),
];

final _f10 = lmAile(
  'kim_verim',
  'Tepkimelerde yüzde verim ve saflık',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final (denk, fa, ka, fb, kb) = _verimTepkimeleri[a];
    final ma = _mk(fa), mb = _mk(fb);
    final t = b + 1;
    final p = const [
      80,
      60,
      50,
      90,
      70,
      40,
      30,
      20,
    ][(a + b + 4 * (c ~/ 5)) % 8];
    final na = ka * t / 10, nb = kb * t / 10;
    final ga = na * ma, teorik = nb * mb, gercek = teorik * p / 100;
    final kut = _kut([fa, fb]);
    final teorikYazi =
        '${_t(ga)} gram $fa ${_t(na)} moldür; tam verimle ${_t(nb)} mol, yani '
        '${_t(teorik)} gram $fb oluşur.';
    switch (c % 5) {
      case 0:
        return _say(
          '$denk tepkimesine göre ${_t(ga)} gram $fa tepkimeye sokulduğunda '
              '${_t(gercek)} gram $fb elde ediliyor. Tepkimenin yüzde verimi '
              'kaçtır? ($kut)',
          p,
          [100 - p, if (gercek < ga) 100 * gercek / ga, p / 2, p + 10, p - 10],
          on: '%',
          '$teorikYazi Verim ${_t(gercek)} / ${_t(teorik)}·100 = %$p olur.',
        );
      case 1:
        return _say(
          '$denk tepkimesine göre ${_t(ga)} gram $fa %$p verimle tepkimeye '
              'girdiğinde kaç gram $fb elde edilir? ($kut)',
          gercek,
          [teorik, teorik * (100 - p) / 100, ga * p / 100, na * mb * p / 100],
          '$teorikYazi Verim %$p olduğundan ${_t(teorik)}·$p / 100 = '
              '${_t(gercek)} gram $fb elde edilir.',
          birim: 'g',
        );
      case 2:
        return _say(
          'Kütlece %$p saflıktaki ${_t(ga)} gram $fa örneği $denk tepkimesine '
              'göre tamamen tepkimeye giriyor; safsızlıklar tepkimeye katılmıyor. '
              'Kaç gram $fb oluşur? ($kut)',
          gercek,
          [teorik, teorik * (100 - p) / 100, ga * p / 100, na * mb * p / 100],
          'Örnekteki saf $fa kütlesi ${_t(ga)}·$p / 100 = ${_t(ga * p / 100)} '
              'gram, yani ${_t(na * p / 100, 3)} moldür. Oluşan $fb '
              '${_t(nb * p / 100, 3)} mol olup kütlesi ${_t(gercek)} gramdır.',
          birim: 'g',
        );
      case 3:
        return _say(
          'Saf olmayan ${_t(ga)} gramlık bir $fa örneği $denk tepkimesine göre '
              'tepkimeye sokulduğunda ${_t(gercek)} gram $fb oluşuyor; safsızlıklar '
              'tepkimeye katılmıyor. Örnekteki $fa kütlece yüzde kaçtır? ($kut)',
          p,
          [100 - p, if (gercek < ga) 100 * gercek / ga, p / 2, p + 10, p - 10],
          on: '%',
          '${_t(gercek)} gram $fb ${_t(nb * p / 100, 3)} moldür; bunun için '
              '${_t(na * p / 100, 3)} mol, yani ${_t(ga * p / 100)} gram saf $fa '
              'gerekir. Saflık ${_t(ga * p / 100)} / ${_t(ga)}·100 = %$p olur.',
        );
      default:
        return _say(
          '$denk tepkimesi %$p verimle gerçekleşmektedir. ${_t(gercek)} gram '
              '$fb elde etmek için kaç gram $fa kullanılmalıdır? ($kut)',
          ga,
          [ga * p / 100, ga * p / 100 * p / 100, teorik, gercek, ga * 2],
          'Tam verimle oluşması gereken $fb kütlesi ${_t(gercek)}·100 / $p = '
              '${_t(teorik)} gram, yani ${_t(nb)} moldür. Gereken $fa ${_t(na)} mol '
              'olup kütlesi ${_t(na)}·${_t(ma)} = ${_t(ga)} gramdır.',
          birim: 'g',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 11. Gaz yasaları
// ---------------------------------------------------------------------------

const _oranCiftleri = [
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
  (1, 5),
  (5, 1),
  (2, 5),
  (5, 2),
  (3, 5),
  (5, 3),
  (4, 5),
  (5, 4),
  (1, 6),
  (6, 1),
];

// Kelvin karşılıkları basit oran veren Celsius sıcaklık çiftleri.
const _sicaklikCiftleri = [
  (27, 127),
  (27, 327),
  (127, 27),
  (127, 327),
  (327, 27),
  (327, 127),
  (0, 273),
  (273, 0),
  (-73, 27),
  (27, -73),
  (-73, 127),
  (127, -73),
  (227, 27),
  (27, 227),
  (227, 127),
  (127, 227),
  (-23, 227),
  (227, -23),
  (-23, 27),
  (27, 477),
];

const _besOran = [(1, 2), (2, 1), (1, 3), (3, 2), (2, 3)];

final _f11 = lmAile(
  'kim_gaz_yasalari',
  'Boyle, Charles, Gay-Lussac ve birleşik gaz yasası',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (n1, n2) = _oranCiftleri[b];
    final (c1, c2) = _sicaklikCiftleri[b];
    final k1 = c1 + 273, k2 = c2 + 273;
    final g = k1.gcd(k2);
    final r1 = k1 ~/ g, r2 = k2 ~/ g;
    final kelvin =
        'T₁ = ${_t(c1)} + 273 = $k1 K, T₂ = ${_t(c2)} + 273 = $k2 K.';
    switch (c) {
      case 0:
        final p1 = n1 / 2, p2 = n2 / 2;
        final v1 = n2 * (a + 1) / 2, v2 = n1 * (a + 1) / 2;
        return _say(
          'Sabit sıcaklıkta, sürtünmesiz pistonlu bir kapta bulunan ideal gazın '
              'basıncı ${_t(p1)} atm iken hacmi ${_t(v1)} L olarak ölçülüyor. Piston '
              'hareket ettirilerek gazın basıncı ${_t(p2)} atm yapıldığında hacmi '
              'kaç litre olur?',
          v2,
          [v1 * p2 / p1, v1, v2 / 2, v2 * 2, v1 + v2],
          'Boyle yasasına göre P₁V₁ = P₂V₂ olur: ${_t(p1)}·${_t(v1)} = '
              '${_t(p2)}·V₂ eşitliğinden V₂ = ${_t(v2)} L bulunur.',
          birim: 'L',
        );
      case 4:
        final p1 = n1 / 5, p2 = n2 / 5;
        final v1 = n2 * (a + 1) / 2, v2 = n1 * (a + 1) / 2;
        return _say(
          'Sabit sıcaklıkta ${_t(p1)} atm basınç altında ${_t(v1)} L hacim '
              'kaplayan ideal gazın hacmi ${_t(v2)} L yapılıyor. Gazın son basıncı '
              'kaç atm olur?',
          p2,
          [p1 * v2 / v1, p1, p2 * 2, p2 / 2, p1 + p2],
          'Boyle yasasına göre P₁V₁ = P₂V₂ olur: ${_t(p1)}·${_t(v1)} = '
              'P₂·${_t(v2)} eşitliğinden P₂ = ${_t(p2)} atm bulunur.',
        );
      case 8:
        final p1 = n1 * 190, p2 = n2 * 190;
        final v1 = n2 * (a + 1) * 20, v2 = n1 * (a + 1) * 20;
        return sayisal(
          'Sabit sıcaklıkta $p1 mmHg basınç altında $v1 mL hacim kaplayan bir '
              'miktar ideal gazın basıncı $p2 mmHg değerine getiriliyor. Gazın son '
              'hacmi kaç mL olur?',
          v2,
          [v1 * n2 ~/ n1, v1, v2 * 2, v2 ~/ 2, v1 + v2],
          'Boyle yasasına göre P₁V₁ = P₂V₂ olur: $p1·$v1 = $p2·V₂ eşitliğinden '
              'V₂ = $v2 mL bulunur.',
          unit: 'mL',
          positive: true,
        );
      case 1:
        final v1 = r1 * (a + 1) / 2, v2 = r2 * (a + 1) / 2;
        return _say(
          'Sabit basınçta, sürtünmesiz pistonlu bir kapta bulunan ideal gazın '
              'sıcaklığı ${_t(c1)} °C iken hacmi ${_t(v1)} L olarak ölçülüyor. Gazın '
              'sıcaklığı ${_t(c2)} °C yapıldığında hacmi kaç litre olur?',
          v2,
          [if (c1 != 0) v1 * c2 / c1, v1 * r1 / r2, v1, v2 * 2, v2 / 2],
          '$kelvin Charles yasasına göre V₁ / T₁ = V₂ / T₂ olur: V₂ = '
              '${_t(v1)}·$k2 / $k1 = ${_t(v2)} L bulunur.',
          birim: 'L',
        );
      case 5:
        final v1 = r1 * (a + 1) / 2, v2 = r2 * (a + 1) / 2;
        return _say(
          'Sabit basınçta ${_t(c1)} °C sıcaklıkta ${_t(v1)} L hacim kaplayan '
              'ideal gazın sıcaklığı, hacmi ${_t(v2)} L oluncaya kadar '
              'değiştiriliyor. Gazın son sıcaklığı kaç °C olur?',
          c2,
          [k2, c1 * r2 / r1, k2 + 273, c2 + 100, c2 - 100, c1 + 273],
          'T₁ = ${_t(c1)} + 273 = $k1 K olur. V₁ / T₁ = V₂ / T₂ eşitliğinden '
              'T₂ = $k1·${_t(v2)} / ${_t(v1)} = $k2 K, yani $k2 − 273 = ${_t(c2)} '
              '°C bulunur.',
          birim: '°C',
          arti: false,
        );
      case 9:
        final v1 = r1 * (a + 1) * 10, v2 = r2 * (a + 1) * 10;
        return sayisal(
          'Sabit basınçta $k1 K sıcaklıkta $v1 mL hacim kaplayan ideal gazın '
              'sıcaklığı $k2 K değerine getiriliyor. Gazın son hacmi kaç mL olur?',
          v2,
          [v1 * r1 ~/ r2, v1, v2 * 2, v2 ~/ 2, v1 + v2],
          'Charles yasasına göre V₁ / T₁ = V₂ / T₂ olur: V₂ = $v1·$k2 / $k1 = '
              '$v2 mL bulunur.',
          unit: 'mL',
          positive: true,
        );
      case 2:
        final p1 = r1 * (a + 1) / 10, p2 = r2 * (a + 1) / 10;
        return _say(
          'Sabit hacimli kapalı bir çelik kapta bulunan ideal gazın sıcaklığı '
              '${_t(c1)} °C iken basıncı ${_t(p1)} atm olarak ölçülüyor. Gazın '
              'sıcaklığı ${_t(c2)} °C yapıldığında basıncı kaç atm olur?',
          p2,
          [if (c1 != 0) p1 * c2 / c1, p1 * r1 / r2, p1, p2 * 2, p2 / 2],
          '$kelvin Gay-Lussac yasasına göre P₁ / T₁ = P₂ / T₂ olur: P₂ = '
              '${_t(p1)}·$k2 / $k1 = ${_t(p2)} atm bulunur.',
        );
      case 6:
        final p1 = r1 * (a + 1) * 20, p2 = r2 * (a + 1) * 20;
        return _say(
          'Sabit hacimli kapalı bir kapta ${_t(c1)} °C sıcaklıkta $p1 mmHg '
              'basınç yapan ideal gazın sıcaklığı, basıncı $p2 mmHg oluncaya kadar '
              'değiştiriliyor. Gazın son sıcaklığı kaç °C olur?',
          c2,
          [k2, c1 * r2 / r1, k2 + 273, c2 + 100, c2 - 100, c1 + 273],
          'T₁ = ${_t(c1)} + 273 = $k1 K olur. P₁ / T₁ = P₂ / T₂ eşitliğinden '
              'T₂ = $k1·$p2 / $p1 = $k2 K, yani $k2 − 273 = ${_t(c2)} °C bulunur.',
          birim: '°C',
          arti: false,
        );
      default:
        // Birleşik gaz yasası. Oranlar birbirini götürüp sonucu verilen
        // değere eşitlemesin diye gerekirse ilk oran kaydırılır.
        var (x, y) = _besOran[a % 5];
        if (x * r2 == y * r1) x += 3;
        final s = 1 + a ~/ 5;
        if (c == 3) {
          final p1 = x / 2, p2 = y / 2;
          final v1 = y * r1 * s / 2, v2 = x * r2 * s / 2;
          return _say(
            '${_t(c1)} °C sıcaklıkta ve ${_t(p1)} atm basınçta ${_t(v1)} L hacim '
                'kaplayan bir miktar ideal gaz, ${_t(c2)} °C sıcaklığa ve ${_t(p2)} '
                'atm basınca getiriliyor. Gazın son hacmi kaç litre olur?',
            v2,
            [
              v1 * p2 / p1 * k2 / k1,
              v1 * p1 / p2 * k1 / k2,
              v1 * k2 / k1,
              v1 * p1 / p2,
            ],
            '$kelvin P₁V₁ / T₁ = P₂V₂ / T₂ eşitliğinden V₂ = '
                '${_t(p1)}·${_t(v1)}·$k2 / ($k1·${_t(p2)}) = ${_t(v2)} L bulunur.',
            birim: 'L',
          );
        }
        final v1 = 2 * x, v2 = 2 * y;
        final p1 = y * r1 * s / 10, p2 = x * r2 * s / 10;
        return _say(
          '${_t(c1)} °C sıcaklıkta ${_t(v1)} L hacim kaplayan ideal gazın '
              'basıncı ${_t(p1)} atm olarak ölçülüyor. Gaz ${_t(c2)} °C sıcaklığa '
              'getirilip hacmi ${_t(v2)} L yapıldığında basıncı kaç atm olur?',
          p2,
          [
            p1 * v2 / v1 * k2 / k1,
            p1 * v1 / v2 * k1 / k2,
            p1 * k2 / k1,
            p1 * v1 / v2,
          ],
          '$kelvin P₁V₁ / T₁ = P₂V₂ / T₂ eşitliğinden P₂ = '
              '${_t(p1)}·${_t(v1)}·$k2 / ($k1·${_t(v2)}) = ${_t(p2)} atm bulunur.',
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 12. İdeal gaz denklemi ve gaz yoğunluğu
// ---------------------------------------------------------------------------

// Mol kütleleri birbirinden farklı, sorulardaki koşullarda (27–527 °C, en çok
// 16,4 atm) açıkça gaz kalan ve bu sıcaklıklarda bozunmayan maddeler. SO₂,
// Cl₂ gibi 27 °C'de birkaç atmosferde sıvılaşabilen gazlar ile ısıda bozunan
// O₃ ve C₂H₂ alınmamıştır.
const _gazlar = [
  ('H₂', 'hidrojen'),
  ('He', 'helyum'),
  ('CH₄', 'metan'),
  ('NH₃', 'amonyak'),
  ('Ne', 'neon'),
  ('N₂', 'azot'),
  ('C₂H₆', 'etan'),
  ('O₂', 'oksijen'),
  ('H₂S', 'hidrojen sülfür'),
  ('F₂', 'flor'),
  ('Ar', 'argon'),
  ('CO₂', 'karbon dioksit'),
  ('BF₃', 'bor triflorür'),
  ('NF₃', 'azot triflorür'),
  ('HBr', 'hidrojen bromür'),
  ('Kr', 'kripton'),
  ('CF₄', 'karbon tetraflorür'),
  ('SiF₄', 'silisyum tetraflorür'),
  ('Xe', 'ksenon'),
  ('SF₆', 'kükürt hekzaflorür'),
];

const _rYazi = 'R = 0,082 L·atm/(mol·K)';

final _f12 = lmAile(
  'kim_ideal_gaz',
  'İdeal gaz denklemi ve gaz yoğunluğu',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final tc = const [27, 127, 227, 327, 527][a % 5];
    final tk = tc + 273;
    final rt = 0.082 * tk;
    final kelvin = 'T = $tc + 273 = $tk K.';
    final sira = _sira(a, b, c);
    if (c % 5 == 4) {
      final (f, ad) = _gazlar[b];
      final mk = _mk(f);
      final j = 1 + a ~/ 5;
      final p = j * rt / 20, d = j * mk / 20;
      if (c == 4) {
        return _saySirali(
          '$tc °C sıcaklıkta ve ${_t(p)} atm basınçta $ad ($f) gazının '
              'yoğunluğu kaç g/L olur? (${_kut([f])}; $_rYazi)',
          d,
          [
            p * mk / (0.082 * tc),
            mk / 22.4,
            mk / rt,
            p / rt,
            d * 2,
            d / 2,
            p * mk,
          ],
          '$kelvin d = P·M / (R·T) = ${_t(p)}·${_t(mk)} / (0,082·$tk) = '
              '${_t(d)} g/L bulunur.',
          sira,
          birim: 'g/L',
        );
      }
      return _saySirali(
        '$tc °C sıcaklıkta ve ${_t(p)} atm basınçta yoğunluğu ${_t(d)} g/L olan '
            'ideal gazın mol kütlesi kaç g/mol olur? ($_rYazi)',
        mk,
        [d * 0.082 * tc / p, d * 22.4, d * rt, mk * 2, mk / 2, d * tk / p],
        '$kelvin M = d·R·T / P = ${_t(d)}·0,082·$tk / ${_t(p)} = ${_t(mk)} '
            'g/mol bulunur.',
        sira,
        birim: 'g/mol',
      );
    }
    final p = (c < 5
        ? const [0.5, 1, 2, 3, 4]
        : const [0.2, 0.4, 0.8, 1.5, 2.5])[a ~/ 5];
    final k = b + 1;
    final v = k * rt / 10, n = k * p / 10;
    switch (c % 5) {
      case 0:
        return _saySirali(
          '${_t(n)} mol ideal gaz $tc °C sıcaklıkta ${_t(p)} atm basınç '
              'yapmaktadır. Gazın hacmi kaç litredir? ($_rYazi)',
          v,
          [n * 0.082 * tc / p, n * 22.4, n * rt, n * rt * p, v / 2, v * 2],
          '$kelvin V = n·R·T / P = ${_t(n)}·0,082·$tk / ${_t(p)} = ${_t(v)} L '
              'bulunur.',
          sira,
          birim: 'L',
        );
      case 1:
        return _saySirali(
          '${_t(v)} L hacimli kapalı bir kapta $tc °C sıcaklıkta ${_t(n)} mol '
              'ideal gaz bulunmaktadır. Gazın basıncı kaç atm olur? ($_rYazi)',
          p,
          [
            n * 0.082 * tc / v,
            n * 22.4 / v,
            v / (n * rt),
            n * rt,
            p * 2,
            p / 2,
          ],
          '$kelvin P = n·R·T / V = ${_t(n)}·0,082·$tk / ${_t(v)} = ${_t(p)} '
              'atm bulunur.',
          sira,
        );
      case 2:
        return _saySirali(
          '$tc °C sıcaklıkta ${_t(v)} L hacimli kapalı bir kapta ${_t(p)} atm '
              'basınç yapan ideal gaz kaç moldür? ($_rYazi)',
          n,
          [p * v / (0.082 * tc), v / 22.4, v / rt, p / rt, n * 2, n / 2, p * v],
          '$kelvin n = P·V / (R·T) = ${_t(p)}·${_t(v)} / (0,082·$tk) = '
              '${_t(n)} mol bulunur.',
          sira,
          birim: 'mol',
        );
      default:
        final (f, ad) = _gazlar[(a + b) % 20];
        final mk = _mk(f);
        return _saySirali(
          '$tc °C sıcaklıkta ${_t(v)} L hacimli kapalı bir kapta ${_t(p)} atm '
              'basınç yapan $ad ($f) gazı kaç gramdır? (${_kut([f])}; $_rYazi)',
          n * mk,
          [
            p * v / (0.082 * tc) * mk,
            v / 22.4 * mk,
            v / rt * mk,
            n,
            n * mk / 2,
            n * mk * 2,
          ],
          '$kelvin n = P·V / (R·T) = ${_t(p)}·${_t(v)} / (0,082·$tk) = '
              '${_t(n)} mol olur. Kütle ${_t(n)}·${_t(mk)} = ${_t(n * mk)} gramdır.',
          sira,
          birim: 'g',
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 13. Kısmi basınç, mol kesri ve Graham difüzyon yasası
// ---------------------------------------------------------------------------

// (hafif gaz, ağır gaz, hız oranı = √(M_ağır / M_hafif))
const _grahamCiftleri = [
  ('He', 'CH₄', 2),
  ('H₂', 'O₂', 4),
  ('CH₄', 'SO₂', 2),
  ('He', 'SO₂', 4),
  ('O₂', 'HI', 2),
];

final _f13 = lmAile(
  'kim_kismi_basinc',
  'Kısmi basınç, mol kesri ve Graham difüzyon yasası',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final ikinci = c >= 5;
    final sira = _sira(a, b, c);
    switch (c % 5) {
      case 0:
        final n = [1 + a % 5, 1 + a ~/ 5, 1 + b % 4];
        final top = n[0] + n[1] + n[2];
        final u = 20 * (1 + b ~/ 4);
        final j = ikinci ? 1 : 0;
        final gaz = const ['He', 'Ne', 'Ar'][j];
        return _saySirali(
          'Kapalı bir kapta ${n[0]} mol He, ${n[1]} mol Ne ve ${n[2]} mol Ar '
              'gazlarından oluşan karışımın toplam basıncı ${top * u} mmHg olarak '
              'ölçülüyor. Buna göre $gaz gazının kısmi basıncı kaç mmHg olur?',
          n[j] * u,
          [
            top * u ~/ 3,
            n[1 - j] * u,
            top * u - n[j] * u,
            n[2] * u,
            u,
            top * u ~/ n[j],
            2 * n[j] * u,
            n[j] * u ~/ 2,
          ],
          'Toplam mol sayısı $top olduğundan $gaz gazının mol kesri '
              '${kesir(n[j], top)} olur. Kısmi basınç ${top * u}·${n[j]} / $top = '
              '${n[j] * u} mmHg bulunur.',
          sira,
          basamak: 0,
          komsuUst: top * u,
        );
      case 1:
        final n1 = 1 + a % 5, n2 = 1 + a ~/ 5, top = n1 + n2;
        if (!ikinci) {
          final pt = top * (b + 1) / 20, p2 = n2 * (b + 1) / 20;
          final m1 = 4 * n1, m2 = 16 * n2;
          return _saySirali(
            'Kapalı bir kapta $m1 gram He ve $m2 gram CH₄ gazları '
                'bulunmaktadır. Karışımın toplam basıncı ${_t(pt)} atm olduğuna '
                'göre CH₄ gazının kısmi basıncı kaç atm olur? '
                '(${_kut(['He', 'CH₄'])})',
            p2,
            _arada(
              [
                pt * m2 / (m1 + m2),
                pt - p2,
                pt * m1 / (m1 + m2),
                pt / 2,
                pt * n2 / (n1 + 2 * n2),
                pt * n2 / n1,
                p2 * 2,
                p2 / 2,
              ],
              0,
              pt,
            ),
            'He: $m1 / 4 = $n1 mol, CH₄: $m2 / 16 = $n2 mol. CH₄ gazının mol '
                'kesri $n2/$top olduğundan kısmi basıncı ${_t(pt)}·$n2 / $top = '
                '${_t(p2)} atm bulunur.',
            sira,
            komsuUst: pt,
          );
        }
        // Mol sayıları onda bir adımlarla; her (a, b) ayrı bir çift verir.
        final h1 = 1 + a % 5 + 5 * (b % 4), h2 = 1 + a ~/ 5 + 5 * (b ~/ 4);
        final g1 = 2 * h1 / 10, g2 = 32 * h2 / 10;
        return _kesirSirali(
          'Kapalı bir kapta ${_t(g1)} gram H₂ ve ${_t(g2)} gram O₂ gazları '
              'bulunmaktadır. Buna göre karışımdaki O₂ gazının mol kesri kaçtır? '
              '(${_kut(['H₂', 'O₂'])})',
          h2,
          h1 + h2,
          [
            (h1, h1 + h2),
            (16 * h2, h1 + 16 * h2),
            (h1, h1 + 16 * h2),
            (h2, h1 + 2 * h2),
            (h2, 2 * h1 + h2),
            (h2, h1),
            (h1, h2),
            (2 * h2, h1 + h2),
            (h2, 2 * (h1 + h2)),
          ],
          'H₂: ${_t(g1)} / 2 = ${_t(h1 / 10)} mol, O₂: ${_t(g2)} / 32 = '
              '${_t(h2 / 10)} mol. O₂ gazının mol kesri ${_t(h2 / 10)} / '
              '${_t((h1 + h2) / 10)} = ${kesir(h2, h1 + h2)} olur.',
          sira,
        );
      case 2:
        final v1 = 1 + a % 5, v2 = 1 + a ~/ 5, top = v1 + v2;
        final p = (1 + b % 4) / 10, q = (1 + b ~/ 4) / 10 + 0.05;
        final p1 = top * p, p2 = top * q;
        final son = v1 * p + v2 * q;
        final giris =
            'Sabit sıcaklıkta, $v1 L hacimli kapta ${_t(p1)} atm basınçta He '
            'gazı, $v2 L hacimli kapta ${_t(p2)} atm basınçta Ne gazı '
            'bulunmaktadır. Kaplar arasındaki musluk açılarak gazların '
            'karışması sağlanıyor.';
        if (!ikinci) {
          return _saySirali(
            '$giris Son durumda toplam basınç kaç atm olur?',
            son,
            [
              (p1 + p2) / 2,
              p1 + p2,
              (p1 * v2 + p2 * v1) / top,
              v1 * p,
              v2 * q,
              p1 * v1 + p2 * v2,
              son * 2,
              son / 2,
            ],
            'Toplam hacim $top L olur. P = (${_t(p1)}·$v1 + ${_t(p2)}·$v2) / '
                '$top = ${_t(son)} atm bulunur.',
            sira,
          );
        }
        return _saySirali(
          '$giris Son durumda Ne gazının kısmi basıncı kaç atm olur?',
          v2 * q,
          [
            son,
            p2,
            p2 * v1 / top,
            v1 * p,
            p2 / 2,
            p2 * v2,
            p2 * top / v2,
            v2 * q * 2,
            v2 * q / 2,
          ],
          'Ne gazı $v2 L hacimden $top L hacme yayılır. Kısmi basıncı '
              '${_t(p2)}·$v2 / $top = ${_t(v2 * q)} atm bulunur.',
          sira,
        );
      default:
        final (hafif, agir, oran) = _grahamCiftleri[a % 5];
        final k = 5 + b + 20 * (a ~/ 5);
        final mh = _mk(hafif), ma = _mk(agir);
        final kut = _kut([hafif, agir]);
        final hiz =
            'Graham yasasına göre hız oranı √(${_t(ma)} / ${_t(mh)}) = $oran '
            'olur; $hafif gazı $oran kat hızlı yayılır.';
        if (c % 5 == 3) {
          final giris = 'Aynı sıcaklık ve basınçta, özdeş cam borularda';
          if (!ikinci) {
            return _saySirali(
              '$giris $hafif gazı borunun diğer ucuna $k saniyede ulaşıyor. '
                  'Aynı koşullarda $agir gazı aynı yolu kaç saniyede alır? ($kut)',
              oran * k,
              [
                k * ma ~/ mh,
                k,
                k / oran,
                k + oran,
                k * (oran + 1),
                _olcekte(k / (oran * oran), oran * k, 8),
              ],
              '$hiz Süre hızla ters orantılı olduğundan $agir gazı yolu '
                  '$k·$oran = ${oran * k} saniyede alır.',
              sira,
              birim: 's',
            );
          }
          return _saySirali(
            '$giris $agir gazı borunun diğer ucuna ${oran * k} saniyede '
                'ulaşıyor. Aynı koşullarda $hafif gazı aynı yolu kaç saniyede alır? '
                '($kut)',
            k,
            [oran * oran * k, k / oran, oran * k, oran * k - oran, 2 * k],
            '$hiz Süre hızla ters orantılı olduğundan $hafif gazı yolu '
                '${oran * k} / $oran = $k saniyede alır.',
            sira,
            birim: 's',
          );
        }
        // Boru boyu 30–200 cm arasında kalır; bir ondalık basamak kullanılır.
        final l = 100 + 3 * (b + 20 * (a ~/ 5));
        final boy = (oran + 1) * l / 10;
        final uc = ikinci ? agir : hafif;
        final yanit = (ikinci ? 1 : oran) * l / 10;
        return _saySirali(
          'Aynı sıcaklıktaki $hafif ve $agir gazları, ${_t(boy)} cm '
              'uzunluğundaki cam borunun iki ucundan aynı anda gönderiliyor. '
              'Gazlar, $uc gazının gönderildiği uçtan kaç cm uzakta karşılaşır? '
              '($kut)',
          yanit,
          _arada(
            [
              boy / 2,
              boy - yanit,
              boy * ma / (mh + ma),
              boy * mh / (mh + ma),
              boy / oran,
              yanit + oran,
              yanit - oran,
            ],
            0,
            boy,
          ),
          '$hiz Aynı sürede alınan yollar $oran : 1 oranındadır. $uc gazı '
              '${_t(boy)}·${ikinci ? 1 : oran} / ${oran + 1} = ${_t(yanit)} cm '
              'yol alır.',
          sira,
          birim: 'cm',
          komsuUst: boy,
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 14. Molarite, kütlece yüzde derişim ve ppm
// ---------------------------------------------------------------------------

// Suda çok çözünen maddeler.
const _cozunenler = [
  ('NaOH', 'sodyum hidroksit'),
  ('KOH', 'potasyum hidroksit'),
  ('NaCl', 'sodyum klorür'),
  ('KNO₃', 'potasyum nitrat'),
  ('C₆H₁₂O₆', 'glikoz'),
  ('CaCl₂', 'kalsiyum klorür'),
  ('NaNO₃', 'sodyum nitrat'),
  ('MgSO₄', 'magnezyum sülfat'),
  ('NH₄Cl', 'amonyum klorür'),
  ('KBr', 'potasyum bromür'),
  ('AgNO₃', 'gümüş nitrat'),
  ('CaBr₂', 'kalsiyum bromür'),
  ('C₁₂H₂₂O₁₁', 'sakkaroz'),
  ('NH₄NO₃', 'amonyum nitrat'),
  ('KI', 'potasyum iyodür'),
  ('MgCl₂', 'magnezyum klorür'),
  ('NaBr', 'sodyum bromür'),
  ('Ca(NO₃)₂', 'kalsiyum nitrat'),
  ('Al(NO₃)₃', 'alüminyum nitrat'),
  ('NaI', 'sodyum iyodür'),
  ('HNO₃', 'nitrik asit'),
  ('H₂SO₄', 'sülfürik asit'),
  ('KCl', 'potasyum klorür'),
  ('ZnSO₄', 'çinko sülfat'),
  ('Mg(NO₃)₂', 'magnezyum nitrat'),
];

final _f14 = lmAile(
  'kim_derisim',
  'Molarite, kütlece yüzde derişim ve ppm',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (f, ad) = _cozunenler[a];
    final mk = _mk(f);
    final madde = '$ad ($f)';
    final w = c ~/ 5;
    switch (c % 5) {
      case 0:
      case 1:
        final hacim = const [200, 250, 400, 500, 1000, 2000][(a + 3 * w) % 6];
        final n = (b + 1) / 50, m = n * mk;
        final der = n * 1000 / hacim;
        final kut = _kut([f]);
        if (c % 5 == 0) {
          return _say(
            'Kütlesi ${_t(m)} gram olan $madde saf suda çözülerek $hacim mL '
                'çözelti hazırlanıyor. Çözeltinin molar derişimi kaç mol/L olur? '
                '($kut)',
            der,
            [n, m * 1000 / hacim / 100, n * hacim / 1000, der * 2, der / 2],
            'n = ${_t(m)} / ${_t(mk)} = ${_t(n)} mol ve V = ${_t(hacim / 1000)} '
                'L olur. Derişim ${_t(n)} / ${_t(hacim / 1000)} = ${_t(der)} mol/L '
                'bulunur.',
            birim: 'mol/L',
          );
        }
        return _say(
          'Derişimi ${_t(der)} mol/L olan $hacim mL $madde çözeltisi hazırlamak '
              'için kaç gram $f gerekir? ($kut)',
          m,
          [der * mk, m * 2, m / 2, n, m * 10],
          'n = ${_t(der)}·${_t(hacim / 1000)} = ${_t(n)} mol olur. Kütle '
              '${_t(n)}·${_t(mk)} = ${_t(m)} gram bulunur.',
          birim: 'g',
        );
      case 3:
        final iyon = const ['Ca²⁺', 'Mg²⁺', 'Na⁺', 'Cl⁻', 'NO₃⁻'][a % 5];
        final kg = const [0.5, 2, 2.5, 4, 5][a ~/ 5];
        final ppm = 2 * (b + 1), mg = ppm * kg;
        const tanim =
            'ppm, 1 kg çözeltideki çözünenin miligram cinsinden kütlesidir.';
        if (w == 0) {
          return _say(
            'Kütlesi ${_t(kg)} kg olan bir içme suyu örneğinde ${_t(mg)} mg '
                '$iyon iyonu bulunmaktadır. Bu iyonun sudaki derişimi kaç ppm '
                'olur?',
            ppm,
            [mg * kg, mg, ppm * 10, ppm / 10, mg / (kg * 10)],
            '$tanim Derişim ${_t(mg)} / ${_t(kg)} = $ppm ppm bulunur.',
          );
        }
        return _say(
          'Bir içme suyu örneğinde $iyon iyonu derişimi $ppm ppm olarak '
              'ölçülmüştür. Bu suyun ${_t(kg)} kg kütleli örneğinde kaç mg $iyon '
              'iyonu bulunur?',
          mg,
          [ppm / kg, ppm, mg * 10, mg / 10, ppm * kg * kg],
          '$tanim Örnekte $ppm·${_t(kg)} = ${_t(mg)} mg iyon bulunur.',
          birim: 'mg',
        );
      default:
        final top = 40 * (a + 2), p = 2 + b;
        final ms = top * p / 100, su = top - ms;
        if (c % 5 == 2) {
          if (w == 0) {
            return _say(
              '${_t(ms)} gram $madde, ${_t(su)} gram saf suda tamamen '
                  'çözünüyor. Oluşan çözelti kütlece yüzde kaçlıktır?',
              p,
              [100 * ms / su, 100 - p, p / 2, p * 2],
              on: '%',
              'Çözelti kütlesi ${_t(ms)} + ${_t(su)} = $top gramdır. Kütlece '
                  'yüzde ${_t(ms)} / $top·100 = %$p olur.',
            );
          }
          return _say(
            'Kütlesi $top gram olan bir $madde çözeltisinde ${_t(ms)} gram '
                'çözünen madde bulunmaktadır. Çözeltinin kütlece yüzde derişimi '
                'kaçtır?',
            p,
            [100 * ms / su, 100 * ms / (top + ms), 100 - p, p / 2],
            on: '%',
            'Kütlece yüzde ${_t(ms)} / $top·100 = %$p olur.',
          );
        }
        if (w == 0) {
          return _say(
            'Kütlece %$p oranında $madde içeren $top gram çözeltide kaç gram '
                'su bulunur?',
            su,
            [ms, top * 100 / (100 + p), top - p, su / 2],
            'Çözünen kütlesi $top·$p / 100 = ${_t(ms)} gramdır. Su kütlesi '
                '$top − ${_t(ms)} = ${_t(su)} gram olur.',
            birim: 'g',
          );
        }
        return _say(
          'Kütlece %$p oranında $madde içeren $top gram çözelti hazırlamak '
              'için kaç gram çözünen madde tartılmalıdır?',
          ms,
          [su, top * p / (100 + p), top / p, ms * 2],
          'Çözünen kütlesi $top·$p / 100 = ${_t(ms)} gram olur.',
          birim: 'g',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 15. Seyreltme, çözeltileri karıştırma ve iyon derişimi
// ---------------------------------------------------------------------------

// (ilk hacim payı, son hacim payı): aralarında asal, ikincisi en çok 8.
const _hacimOranlari = [
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
  (1, 7),
  (2, 7),
  (3, 7),
  (4, 7),
  (5, 7),
  (6, 7),
  (1, 8),
  (3, 8),
  (5, 8),
];

// (tuz, sorulan iyon, formül başına iyon sayısı)
const _tuzIyonlari = [
  ('CaCl₂', 'Cl⁻', 2),
  ('Al₂(SO₄)₃', 'SO₄²⁻', 3),
  ('Na₃PO₄', 'Na⁺', 3),
  ('Mg(NO₃)₂', 'NO₃⁻', 2),
  ('K₂SO₄', 'K⁺', 2),
  ('AlCl₃', 'Cl⁻', 3),
  ('Fe₂(SO₄)₃', 'Fe³⁺', 2),
  ('Na₂CO₃', 'Na⁺', 2),
  ('Al(NO₃)₃', 'NO₃⁻', 3),
  ('(NH₄)₂SO₄', 'NH₄⁺', 2),
];

// (1. tuz, iyon sayısı, 2. tuz, iyon sayısı, ortak iyon)
const _ortakIyonlular = [
  ('NaCl', 1, 'CaCl₂', 2, 'Cl⁻'),
  ('KNO₃', 1, 'Ca(NO₃)₂', 2, 'NO₃⁻'),
  ('Na₂SO₄', 1, 'Al₂(SO₄)₃', 3, 'SO₄²⁻'),
  ('NaCl', 1, 'AlCl₃', 3, 'Cl⁻'),
  ('KCl', 1, 'MgCl₂', 2, 'Cl⁻'),
  ('NaNO₃', 1, 'Al(NO₃)₃', 3, 'NO₃⁻'),
  ('Na₂SO₄', 2, 'NaCl', 1, 'Na⁺'),
  ('K₂SO₄', 2, 'KNO₃', 1, 'K⁺'),
  ('Na₃PO₄', 3, 'NaCl', 1, 'Na⁺'),
  ('MgCl₂', 2, 'AlCl₃', 3, 'Cl⁻'),
];

final _f15 = lmAile(
  'kim_seyreltme',
  'Seyreltme, çözelti karıştırma ve iyon derişimi',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (r1, r2) = _hacimOranlari[b];
    final v = const [20, 25, 40, 50, 100][a % 5];
    final w = c ~/ 5, s = 1 + a ~/ 5, s2 = 1 + (a ~/ 5 + 2) % 5;
    final v1 = r1 * v, v2 = (r2 - r1) * v, vt = r2 * v;
    // Derişim 4 mol/L değerine çıkabildiğinden yalnız suda çok çözünen
    // maddeler kullanılır.
    final x = const ['NaCl', 'NaNO₃', 'HCl', 'NaOH', 'KOH'][(a + b) % 5];
    switch (c % 5) {
      case 0:
      case 1:
        final c0 = (w == 0 ? 10 : 3) * s / 100;
        final d1 = r2 * c0, d2 = r1 * c0;
        if (c % 5 == 0) {
          return _say(
            '${_t(d1)} mol/L derişimli $v1 mL $x çözeltisine $v2 mL saf su '
                'ekleniyor. Yeni çözeltinin derişimi kaç mol/L olur?',
            d2,
            [d1 * v1 / v2, d1 * v2 / vt, d1 / 2, d1 * vt / v1, d2 / 2],
            'Son hacim $v1 + $v2 = $vt mL olur. M₁V₁ = M₂V₂ eşitliğinden M₂ = '
                '${_t(d1)}·$v1 / $vt = ${_t(d2)} mol/L bulunur.',
            birim: 'mol/L',
          );
        }
        return sayisal(
          '${_t(d1)} mol/L derişimli $v1 mL $x çözeltisinin derişimini '
              '${_t(d2)} mol/L değerine düşürmek için kaç mL saf su eklenmelidir?',
          v2,
          [vt, v1, vt + v1, v2 * 2, v2 ~/ 2],
          'M₁V₁ = M₂V₂ eşitliğinden son hacim ${_t(d1)}·$v1 / ${_t(d2)} = $vt '
              'mL olmalıdır. Eklenecek su $vt − $v1 = $v2 mL bulunur.',
          unit: 'mL',
          positive: true,
        );
      case 2:
        final p = (w == 0 ? 10 : 3) * s / 100, q = (w == 0 ? 10 : 3) * s2 / 100;
        final d1 = r2 * p, d2 = r2 * q, son = r1 * p + (r2 - r1) * q;
        return _say(
          '${_t(d1)} mol/L derişimli $v1 mL $x çözeltisi ile ${_t(d2)} mol/L '
              'derişimli $v2 mL $x çözeltisi karıştırılıyor. Karışımın derişimi '
              'kaç mol/L olur?',
          son,
          [(d1 + d2) / 2, d1 + d2, (d1 * v2 + d2 * v1) / vt, (d1 - d2).abs()],
          'Son derişim (${_t(d1)}·$v1 + ${_t(d2)}·$v2) / $vt = ${_t(son)} '
              'mol/L bulunur.',
          birim: 'mol/L',
        );
      case 3:
        final (tuz, iyon, k) = _tuzIyonlari[a % 5 + 5 * w];
        final c0 = s / 100;
        final d1 = r2 * c0, d2 = r1 * c0;
        return _say(
          '${_t(d1)} mol/L derişimli $v1 mL $tuz çözeltisi saf su ile $vt mL '
              'hacme tamamlanıyor. Son çözeltideki $iyon iyonu derişimi kaç mol/L '
              'olur? (Tuzun suda tamamen iyonlaştığı kabul edilecektir.)',
          k * d2,
          [d2, k * d1, d2 / k, d1, k * d2 * 2],
          'Seyreltilen çözeltinin derişimi ${_t(d1)}·$v1 / $vt = ${_t(d2)} '
              'mol/L olur. Bir formül birimi $k tane $iyon iyonu verdiğinden iyon '
              'derişimi $k·${_t(d2)} = ${_t(k * d2)} mol/L bulunur.',
          birim: 'mol/L',
        );
      default:
        final (t1, k1, t2, k2, iyon) = _ortakIyonlular[a % 5 + 5 * w];
        final p = s / 100, q = s2 / 100;
        final d1 = r2 * p, d2 = r2 * q;
        final son = k1 * r1 * p + k2 * (r2 - r1) * q;
        return _say(
          '${_t(d1)} mol/L derişimli $v1 mL $t1 çözeltisi ile ${_t(d2)} mol/L '
              'derişimli $v2 mL $t2 çözeltisi karıştırılıyor. Karışımdaki $iyon '
              'iyonu derişimi kaç mol/L olur? (Tuzların suda tamamen iyonlaştığı '
              'kabul edilecektir.)',
          son,
          [
            r1 * p + (r2 - r1) * q,
            k1 * d1 + k2 * d2,
            (k1 * d1 + k2 * d2) / 2,
            k2 * r1 * p + k1 * (r2 - r1) * q,
            son / 2,
          ],
          '$iyon derişimi ($k1·${_t(d1)}·$v1 + $k2·${_t(d2)}·$v2) / $vt = '
              '${_t(son)} mol/L bulunur.',
          birim: 'mol/L',
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 16. Donma noktası alçalması ve kaynama noktası yükselmesi
// ---------------------------------------------------------------------------

// (formül, ad, suda bir formül biriminin verdiği tanecik sayısı). Tanecik
// molalitesi 5 m değerine çıkabildiğinden iyonlaşmayan maddeler suda çok
// çözünen ya da suyla karışan maddelerden seçilmiştir.
const _koligatifler = [
  ('C₆H₁₂O₆', 'fruktoz', 1),
  ('C₃H₈O₂', 'propilen glikol', 1),
  ('CO(NH₂)₂', 'üre', 1),
  ('C₂H₆O₂', 'etilen glikol', 1),
  ('C₃H₈O₃', 'gliserin', 1),
  ('NaOH', 'sodyum hidroksit', 2),
  ('KOH', 'potasyum hidroksit', 2),
  ('KNO₃', 'potasyum nitrat', 2),
  ('NaNO₃', 'sodyum nitrat', 2),
  ('KBr', 'potasyum bromür', 2),
  ('NaBr', 'sodyum bromür', 2),
  ('KI', 'potasyum iyodür', 2),
  ('MgSO₄', 'magnezyum sülfat', 2),
  ('NH₄NO₃', 'amonyum nitrat', 2),
  ('LiOH', 'lityum hidroksit', 2),
  ('AgNO₃', 'gümüş nitrat', 2),
  ('CaCl₂', 'kalsiyum klorür', 3),
  ('MgCl₂', 'magnezyum klorür', 3),
  ('K₂CO₃', 'potasyum karbonat', 3),
  ('Ca(NO₃)₂', 'kalsiyum nitrat', 3),
  ('Mg(NO₃)₂', 'magnezyum nitrat', 3),
  ('CaBr₂', 'kalsiyum bromür', 3),
  ('Na₂CO₃', 'sodyum karbonat', 3),
  ('Al(NO₃)₃', 'alüminyum nitrat', 4),
  ('K₃PO₄', 'potasyum fosfat', 4),
];

final _f16 = lmAile(
  'kim_koligatif',
  'Donma noktası alçalması ve kaynama noktası yükselmesi',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final (f, ad, i) = _koligatifler[a];
    final mk = _mk(f);
    final k = 1 + b % 10; // tanecik molalitesi 0,5·k
    final donma = b < 10;
    final s = c < 5 ? 2 : 4;
    final su = 100 * i * s, kg = su / 1000;
    final n = k * s / 20, ms = n * mk;
    final sabit = donma ? 1.86 : 0.52;
    final dt = sabit * k / 2;
    final nokta = donma ? -dt : 100 + dt;
    final olay = donma ? 'donmaya' : 'kaynamaya';
    final sabitYazi = donma
        ? 'su için Kd = 1,86 °C/m'
        : 'su için Kk = 0,52 °C/m; saf su 100 °C sıcaklıkta kaynar';
    final iyonYazi = i == 1
        ? 'madde suda iyonlaşmadan çözünür'
        : 'madde suda tamamen iyonlaşır';
    final madde = '$ad ($f)';
    final kut = _kut([f]);
    final tanecik = i == 1
        ? 'Tanecik molalitesi ${_t(n)} / ${_t(kg)} = ${_t(k / 2)} m olur.'
        : 'Bir formül birimi $i tanecik verdiğinden tanecik molalitesi '
              '$i·${_t(n)} / ${_t(kg)} = ${_t(k / 2)} m olur.';
    final dtYazi = 'ΔT = ${_t(sabit)}·${_t(k / 2)} = ${_t(dt)} °C';
    final noktaYazi = donma
        ? '$olay başlama sıcaklığı 0 − ${_t(dt)} = ${_t(nokta)} °C'
        : '$olay başlama sıcaklığı 100 + ${_t(dt)} = ${_t(nokta)} °C';
    final geri =
        'ΔT = ${_t(dt)} °C olduğundan tanecik molalitesi ${_t(dt)} / '
        '${_t(sabit)} = ${_t(k / 2)} m olur.';
    final diger = donma ? 0.52 : 1.86; // öteki sabit (Kk ↔ Kd karışıklığı)
    final sira = _sira(a, b, c);
    switch (c % 5) {
      case 0:
        return _saySirali(
          '${_t(ms)} gram $madde, $su gram saf suda çözülüyor. Çözeltinin 1 atm '
              'basınçtaki $olay başlama sıcaklığı kaç °C olur? ($kut; $sabitYazi; '
              '$iyonYazi)',
          nokta,
          donma
              ? [
                  dt,
                  -sabit * n * i,
                  -diger * k / 2,
                  -k / 2,
                  -sabit / (k / 2),
                  -dt / i,
                  -dt * i,
                  -dt * 2,
                  -dt / 2,
                ]
              : [
                  100 - dt,
                  100 + sabit * n * i,
                  100 + diger * k / 2,
                  dt,
                  100 + dt / i,
                  100 + dt * i,
                  100 + dt * 2,
                  100 + dt / 2,
                ],
          'n = ${_t(ms)} / ${_t(mk)} = ${_t(n)} mol. $tanecik $dtYazi; '
              '$noktaYazi bulunur.',
          sira,
          birim: '°C',
          arti: false,
          komsuOlcek: dt,
        );
      case 1:
        return _saySirali(
          'Bir miktar $madde, $su gram saf suda çözüldüğünde çözeltinin 1 atm '
              'basınçtaki $olay başlama sıcaklığı ${_t(nokta)} °C oluyor. Çözünen '
              'madde kaç gramdır? ($kut; $sabitYazi; $iyonYazi)',
          ms,
          [k / 2 * mk, n, k / 2 * mk / i, ms * i, ms / i, ms * 2, ms / 2],
          '$geri $su gram suda ${_t(k / 2)}·${_t(kg)} = ${_t(n * i)} mol '
              'tanecik, yani ${_t(n)} mol madde bulunur. Kütle ${_t(n)}·${_t(mk)} '
              '= ${_t(ms)} gramdır.',
          sira,
          birim: 'g',
        );
      case 2:
        return _saySirali(
          '${_t(ms)} gram $madde kaç gram saf suda çözülürse çözeltinin 1 atm '
              'basınçtaki $olay başlama sıcaklığı ${_t(nokta)} °C olur? ($kut; '
              '$sabitYazi; $iyonYazi)',
          su,
          [
            su / sabit,
            su * diger / sabit,
            su + 100,
            su / i,
            su * i,
            su * 2,
            su / 2,
          ],
          '$geri n = ${_t(ms)} / ${_t(mk)} = ${_t(n)} mol madde ${_t(n * i)} '
              'mol tanecik verir. Su kütlesi ${_t(n * i)} / ${_t(k / 2)} = '
              '${_t(kg)} kg, yani $su gramdır.',
          sira,
          birim: 'g',
        );
      case 3:
        return _saySirali(
          '$su gram saf su ile hazırlanan $madde çözeltisinin 1 atm basınçtaki '
              '$olay başlama sıcaklığı ${_t(nokta)} °C olarak ölçülüyor. Çözeltide '
              'kaç mol $f çözünmüştür? ($sabitYazi; $iyonYazi)',
          n,
          [
            k / 2,
            k / 2 / i,
            n * sabit,
            n * sabit / diger,
            n * i,
            n / i,
            n * 2,
            n / 2,
          ],
          '$geri $su gram suda ${_t(k / 2)}·${_t(kg)} = ${_t(n * i)} mol '
              'tanecik bulunur; çözünen madde ${_t(n * i)} / $i = ${_t(n)} moldür.',
          sira,
          birim: 'mol',
        );
      default:
        return _saySirali(
          '${_t(n)} mol $madde, $su gram saf suda çözülüyor. Çözeltinin '
              '${donma ? 'donma noktası saf suya göre kaç °C alçalır' : 'kaynama noktası saf suya göre kaç °C yükselir'}? '
              '($sabitYazi; $iyonYazi)',
          dt,
          [
            sabit * n * i,
            diger * k / 2,
            k / 2,
            sabit / (k / 2),
            dt / i,
            dt * i,
            dt * 2,
            dt / 2,
          ],
          '$tanecik $dtYazi bulunur.',
          sira,
          birim: '°C',
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 17. Tepkime entalpisi: oluşum entalpileri, Hess yasası, kalorimetri
// ---------------------------------------------------------------------------

// Standart oluşum entalpileri (kJ/mol); (k) katı, (s) sıvı, (g) gaz.
const _olusum = <String, int>{
  'CO₂(g)': -394,
  'H₂O(s)': -286,
  'H₂O(g)': -242,
  'CH₄(g)': -75,
  'C₂H₆(g)': -85,
  'C₃H₈(g)': -104,
  'C₄H₁₀(g)': -126,
  'C₂H₄(g)': 52,
  'C₂H₂(g)': 227,
  'CH₃OH(s)': -239,
  'C₂H₅OH(s)': -278,
  'CO(g)': -110,
  'NH₃(g)': -46,
  'NO(g)': 90,
  'NO₂(g)': 34,
  'SO₂(g)': -297,
  'SO₃(g)': -396,
  'H₂S(g)': -21,
  'HCl(g)': -92,
  'CaO(k)': -635,
  'CaCO₃(k)': -1207,
  'Fe₂O₃(k)': -824,
  'Al₂O₃(k)': -1676,
  'MgO(k)': -602,
  'C₆H₁₂O₆(k)': -1273,
  'C₆H₆(s)': 49,
};

// (girenler, ürünler, miktarı verilen bileşik). Tümü ekzotermiktir.
const _termoTepkimeler = [
  ('CH₄(g) + 2O₂(g)', 'CO₂(g) + 2H₂O(s)', 'CH₄(g)'),
  ('2C₂H₆(g) + 7O₂(g)', '4CO₂(g) + 6H₂O(s)', 'C₂H₆(g)'),
  ('C₃H₈(g) + 5O₂(g)', '3CO₂(g) + 4H₂O(s)', 'C₃H₈(g)'),
  ('C₂H₄(g) + 3O₂(g)', '2CO₂(g) + 2H₂O(s)', 'C₂H₄(g)'),
  ('2C₂H₂(g) + 5O₂(g)', '4CO₂(g) + 2H₂O(s)', 'C₂H₂(g)'),
  ('C₂H₅OH(s) + 3O₂(g)', '2CO₂(g) + 3H₂O(s)', 'C₂H₅OH(s)'),
  ('2CH₃OH(s) + 3O₂(g)', '2CO₂(g) + 4H₂O(s)', 'CH₃OH(s)'),
  ('2CO(g) + O₂(g)', '2CO₂(g)', 'CO(g)'),
  ('2SO₂(g) + O₂(g)', '2SO₃(g)', 'SO₂(g)'),
  ('2H₂S(g) + 3O₂(g)', '2SO₂(g) + 2H₂O(s)', 'H₂S(g)'),
  ('4NH₃(g) + 5O₂(g)', '4NO(g) + 6H₂O(g)', 'NH₃(g)'),
  ('2NO(g) + O₂(g)', '2NO₂(g)', 'NO(g)'),
  ('Fe₂O₃(k) + 3CO(g)', '2Fe(k) + 3CO₂(g)', 'Fe₂O₃(k)'),
  ('2Al(k) + Fe₂O₃(k)', 'Al₂O₃(k) + 2Fe(k)', 'Fe₂O₃(k)'),
  ('C₆H₁₂O₆(k) + 6O₂(g)', '6CO₂(g) + 6H₂O(s)', 'C₆H₁₂O₆(k)'),
  ('CO(g) + H₂O(g)', 'CO₂(g) + H₂(g)', 'CO(g)'),
  ('C₂H₄(g) + H₂(g)', 'C₂H₆(g)', 'C₂H₄(g)'),
  ('C₂H₂(g) + 2H₂(g)', 'C₂H₆(g)', 'C₂H₂(g)'),
  ('N₂(g) + 3H₂(g)', '2NH₃(g)', 'NH₃(g)'),
  ('2C₄H₁₀(g) + 13O₂(g)', '8CO₂(g) + 10H₂O(s)', 'C₄H₁₀(g)'),
  ('2C₆H₆(s) + 15O₂(g)', '12CO₂(g) + 6H₂O(s)', 'C₆H₆(s)'),
  ('CaO(k) + CO₂(g)', 'CaCO₃(k)', 'CaO(k)'),
  ('H₂(g) + Cl₂(g)', '2HCl(g)', 'HCl(g)'),
  ('2Mg(k) + CO₂(g)', '2MgO(k) + C(k)', 'CO₂(g)'),
  ('CO(g) + 2H₂(g)', 'CH₃OH(s)', 'CO(g)'),
];

// (bilinen tepkimeler, hedef tepkime, ürün, hedefin entalpisi, tipik yanlış
// sonuçlar, çözüm yolu)
const _hessTakimlari = [
  (
    [
      'C(k) + O₂(g) → CO₂(g), ΔH = −394 kJ',
      'CO(g) + ½O₂(g) → CO₂(g), ΔH = −283 kJ',
    ],
    'C(k) + ½O₂(g) → CO(g)',
    'CO(g)',
    -111,
    [677, 394],
    'I. tepkime aynen alınır, II. tepkime ters çevrilir: ΔH = −394 + 283 = −111 kJ.',
  ),
  (
    [
      'S(k) + O₂(g) → SO₂(g), ΔH = −297 kJ',
      '2SO₂(g) + O₂(g) → 2SO₃(g), ΔH = −198 kJ',
    ],
    'S(k) + 3/2 O₂(g) → SO₃(g)',
    'SO₃(g)',
    -396,
    [495, 99],
    'I. tepkime aynen alınır, II. tepkime ikiye bölünür: ΔH = −297 − 99 = −396 kJ.',
  ),
  (
    ['H₂(g) + ½O₂(g) → H₂O(g), ΔH = −242 kJ', 'H₂O(s) → H₂O(g), ΔH = +44 kJ'],
    'H₂(g) + ½O₂(g) → H₂O(s)',
    'H₂O(s)',
    -286,
    [198, 242],
    'I. tepkime aynen alınır, II. tepkime ters çevrilir: ΔH = −242 − 44 = −286 kJ.',
  ),
  (
    [
      'C₂H₄(g) + 3O₂(g) → 2CO₂(g) + 2H₂O(s), ΔH = −1411 kJ',
      'C₂H₆(g) + 7/2 O₂(g) → 2CO₂(g) + 3H₂O(s), ΔH = −1560 kJ',
      'H₂(g) + ½O₂(g) → H₂O(s), ΔH = −286 kJ',
    ],
    'C₂H₄(g) + H₂(g) → C₂H₆(g)',
    'C₂H₆(g)',
    -137,
    [149, 435],
    'I. ve III. tepkimeler aynen alınır, II. tepkime ters çevrilir: ΔH = −1411 − 286 + 1560 = −137 kJ.',
  ),
  (
    [
      'C(k) + O₂(g) → CO₂(g), ΔH = −394 kJ',
      'H₂(g) + ½O₂(g) → H₂O(s), ΔH = −286 kJ',
      'CH₄(g) + 2O₂(g) → CO₂(g) + 2H₂O(s), ΔH = −891 kJ',
    ],
    'C(k) + 2H₂(g) → CH₄(g)',
    'CH₄(g)',
    -75,
    [211, 713],
    'I. tepkime aynen, II. tepkime 2 ile çarpılarak alınır, III. tepkime ters çevrilir: ΔH = −394 − 572 + 891 = −75 kJ.',
  ),
];

final _katsayiDeseni = RegExp(r'^(\d*)(.+)$');

/// “2CO(g) + O₂(g)” → [(2, 'CO(g)'), (1, 'O₂(g)')]
List<(int, String)> _terimler(String s) => [
  for (final t in s.split(' + '))
    if (_katsayiDeseni.firstMatch(t) case final m?)
      (m.group(1)!.isEmpty ? 1 : int.parse(m.group(1)!), m.group(2)!),
];

final _f17 = lmAile(
  'kim_termokimya',
  'Tepkime entalpisi, Hess yasası ve kalorimetri',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final w = c ~/ 5;
    if (c % 5 == 1) {
      final (bilinen, hedef, urun, dh, yanlis, yol) = _hessTakimlari[a % 5];
      final n = (1 + b + 20 * (a ~/ 5)) / 10;
      final q = -dh * n;
      const rakam = ['I', 'II', 'III'];
      final liste = [
        for (var j = 0; j < bilinen.length; j++) '${rakam[j]}. ${bilinen[j]}',
      ].join('\n');
      final giris =
          'Aşağıdaki tepkimelerin entalpileri bilinmektedir:\n$liste\n'
          'Buna göre $hedef tepkimesi';
      if (w == 0) {
        return _say(
          '$giris ile ${_t(n)} mol $urun oluşurken açığa çıkan ısı kaç kJ olur?',
          q,
          [yanlis[0] * n, yanlis[1] * n, q / 2, q * 2, -dh],
          '$yol ${_t(n)} mol $urun için ${_t(n)}·${-dh} = ${_t(q)} kJ ısı '
              'açığa çıkar.',
          birim: 'kJ',
        );
      }
      return _say(
        '$giris gerçekleşirken ${_t(q)} kJ ısı açığa çıktığına göre kaç mol '
            '$urun oluşmuştur?',
        n,
        [q / yanlis[0], q / yanlis[1], n * 2, n / 2, n + 1],
        '$yol Oluşan $urun miktarı ${_t(q)} / ${-dh} = ${_t(n)} mol olur.',
        birim: 'mol',
      );
    }
    if (c % 5 == 2) {
      final m = 50 * (a + 2), dt = 3 + b;
      final t1 = 18 + b % 4, t2 = t1 + dt;
      final q = m * 4.2 * dt / 1000;
      const sabit = 'Su için c = 4,2 J/(g·°C)';
      if (w == 0) {
        return _say(
          'Kalorimetre kabındaki $m gram suyun sıcaklığı $t1 °C değerinden '
              '$t2 °C değerine çıkıyor. Suyun aldığı ısı kaç kJ olur? ($sabit)',
          q,
          [
            m * 4.2 * t2 / 1000,
            m * 4.2 * t1 / 1000,
            m * dt / 1000,
            q * 2,
            q / 2,
          ],
          'ΔT = $t2 − $t1 = $dt °C olur. Q = m·c·ΔT = $m·4,2·$dt = '
              '${_t(q * 1000)} J = ${_t(q)} kJ bulunur.',
          birim: 'kJ',
        );
      }
      return sayisal(
        'Kalorimetre kabındaki $t1 °C sıcaklıktaki $m gram suya ${_t(q)} kJ '
            'ısı veriliyor. Isı kaybı olmadığına göre suyun son sıcaklığı kaç °C '
            'olur? ($sabit)',
        t2,
        [dt, t2 + t1, t1 + 2 * dt, t2 - 5, t2 + 5],
        'ΔT = Q / (m·c) = ${_t(q * 1000)} / ($m·4,2) = $dt °C olur. Son '
            'sıcaklık $t1 + $dt = $t2 °C bulunur.',
        unit: '°C',
        positive: true,
      );
    }
    final (girenYazi, urunYazi, x) = _termoTepkimeler[a];
    final giren = _terimler(girenYazi), urun = _terimler(urunYazi);
    var dh = 0, yalin = 0, kx = 0, digerleri = 0;
    var xUrun = false;
    for (final (k, f) in urun) {
      dh += k * (_olusum[f] ?? 0);
      yalin += _olusum[f] ?? 0;
      if (f == x) {
        kx = k;
        xUrun = true;
      } else {
        digerleri += k * (_olusum[f] ?? 0);
      }
    }
    for (final (k, f) in giren) {
      dh -= k * (_olusum[f] ?? 0);
      yalin -= _olusum[f] ?? 0;
      if (f == x) {
        kx = k;
      } else {
        digerleri -= k * (_olusum[f] ?? 0);
      }
    }
    final denk = '$girenYazi → $urunYazi';
    final n = (b + 1) / 10, q = -dh * n / kx;
    final mk = _mk(x), m = n * mk;
    final hx = _olusum[x]!;
    String liste(bool xDahil) => [
      for (final (_, f) in [...giren, ...urun])
        if (_olusum.containsKey(f) && (xDahil || f != x))
          '$f: ${_isaretli(_olusum[f]!)}',
    ].join(', ');
    final fiil = xUrun ? 'oluştuğunda' : 'harcandığında';
    final gramli = w == 1;
    final miktar = gramli ? '${_t(m)} gram $x' : '${_t(n)} mol $x';
    final kut = gramli ? ' (${_kut([x])})' : '';
    final molYazi = gramli
        ? '${_t(m)} / ${_t(mk)} = ${_t(n)} mol $x tepkimede yer alır. '
        : '';
    final dhYazi = 'ΔH = ΣΔH°f(ürünler) − ΣΔH°f(girenler) = $dh kJ olur.'
        .replaceFirst('-', '−');
    switch (c % 5) {
      case 0:
        return _say(
          '$denk tepkimesindeki bileşiklerin standart oluşum entalpileri '
              '(kJ/mol): ${liste(true)}. Buna göre $miktar $fiil açığa çıkan ısı '
              'kaç kJ olur?$kut',
          q,
          [-dh * n, yalin.abs() * n / kx, yalin.abs() * n, q / 2, q * 2, -dh],
          '$dhYazi $molYazi${kx == 1 ? '' : 'Bu değer $kx mol $x içindir. '}'
              'Açığa çıkan ısı ${-dh}·${_t(n)}${kx == 1 ? '' : ' / $kx'} = '
              '${_t(q)} kJ bulunur.',
          birim: 'kJ',
        );
      case 3:
        return _say(
          '$denk tepkimesindeki bileşiklerin standart oluşum entalpileri '
              '(kJ/mol): ${liste(true)}. Tepkimede ${_t(q)} kJ ısı açığa çıktığına '
              'göre kaç ${gramli ? 'gram' : 'mol'} $x '
              '${xUrun ? 'oluşmuştur' : 'harcanmıştır'}?$kut',
          gramli ? m : n,
          gramli
              ? [m / kx, m * 2, m / 2, n, q / yalin.abs() * mk, m * kx]
              : [n / kx, n * 2, n / 2, q / yalin.abs(), n * kx, n + 1],
          '$dhYazi ${-dh} kJ ısı $kx mol $x için açığa çıkar; ${_t(q)} kJ için '
              '${_t(q)}·$kx / ${-dh} = ${_t(n)} mol $x gerekir.'
              '${gramli ? ' Kütlesi ${_t(n)}·${_t(mk)} = ${_t(m)} gramdır.' : ''}',
          birim: gramli ? 'g' : 'mol',
        );
      default:
        final diger = liste(false);
        return _say(
          '$denk tepkimesinde $miktar $fiil ${_t(q)} kJ ısı açığa çıkıyor. '
              '${diger.isEmpty ? 'Elementlerin standart oluşum entalpisi sıfır kabul edildiğine' : 'Diğer bileşiklerin standart oluşum entalpileri (kJ/mol): $diger. Buna'} '
              'göre $x bileşiğinin standart oluşum entalpisi kaç kJ/mol olur?$kut',
          hx,
          [-hx, dh / kx, hx * kx, hx + dh, (digerleri - dh).abs(), hx - 100],
          '$molYazi${_t(n)} mol için ${_t(q)} kJ açığa çıktığından tepkime '
              'entalpisi (denklemdeki $kx mol $x için) ΔH = ${_t(dh)} kJ olur. ΔH = ΣΔH°f(ürünler) − '
              'ΣΔH°f(girenler) eşitliğinde $x için x yazılırsa x = ${_t(hx)} '
              'kJ/mol bulunur.',
          arti: false,
          isaret: true,
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 18. Hız ifadesi ve tepkime derecesi; derişimlerden denge sabiti
// ---------------------------------------------------------------------------

int _kuvvet(int x, int n) {
  var r = 1;
  for (var j = 0; j < n; j++) {
    r *= x;
  }
  return r;
}

/// Hız bağıntısı: derecesi sıfır olan tür yazılmaz.
String _hizBagintisi(int m, int n) =>
    'hız = k'
    '${m == 0 ? '' : '·[X]${m == 1 ? '' : _ust(m)}'}'
    '${n == 0 ? '' : '·[Y]${n == 1 ? '' : _ust(n)}'}';

// (denge denklemi, girenler, ürünler): türler (formül, katsayı) ikilileridir.
const _dengeler = [
  ('N₂(g) + 3H₂(g) ⇌ 2NH₃(g)', [('N₂', 1), ('H₂', 3)], [('NH₃', 2)]),
  ('H₂(g) + I₂(g) ⇌ 2HI(g)', [('H₂', 1), ('I₂', 1)], [('HI', 2)]),
  ('2SO₂(g) + O₂(g) ⇌ 2SO₃(g)', [('SO₂', 2), ('O₂', 1)], [('SO₃', 2)]),
  ('N₂O₄(g) ⇌ 2NO₂(g)', [('N₂O₄', 1)], [('NO₂', 2)]),
  ('PCl₅(g) ⇌ PCl₃(g) + Cl₂(g)', [('PCl₅', 1)], [('PCl₃', 1), ('Cl₂', 1)]),
];

// Hızı belirleyen (yavaş) basamağı verilen iki basamaklı tepkimeler: (net
// tepkime, yavaş basamak, hızlı basamak, X derecesi, Y derecesi, net
// tepkimedeki X ve Y katsayıları).
const _mekanizmalar = [
  (
    'X(g) + 2Y(g) → XY₂(g)',
    'X(g) + Y(g) → XY(g)',
    'XY(g) + Y(g) → XY₂(g)',
    1,
    1,
    1,
    2,
  ),
  (
    '2X(g) + 2Y(g) → X₂Y₂(g)',
    '2X(g) + Y(g) → X₂Y(g)',
    'X₂Y(g) + Y(g) → X₂Y₂(g)',
    2,
    1,
    2,
    2,
  ),
  (
    '2X(g) + 2Y(g) → X₂Y₂(g)',
    'X(g) + 2Y(g) → XY₂(g)',
    'XY₂(g) + X(g) → X₂Y₂(g)',
    1,
    2,
    2,
    2,
  ),
  (
    '2X(g) + Y(g) → X₂Y(g)',
    '2X(g) → X₂(g)',
    'X₂(g) + Y(g) → X₂Y(g)',
    2,
    0,
    2,
    1,
  ),
  (
    'X(g) + 2Y(g) → XY₂(g)',
    '2Y(g) → Y₂(g)',
    'Y₂(g) + X(g) → XY₂(g)',
    0,
    2,
    1,
    2,
  ),
];

const _tersDengeler = [
  '2NH₃(g) ⇌ N₂(g) + 3H₂(g)',
  '2HI(g) ⇌ H₂(g) + I₂(g)',
  '2SO₃(g) ⇌ 2SO₂(g) + O₂(g)',
  '2NO₂(g) ⇌ N₂O₄(g)',
  'PCl₃(g) + Cl₂(g) ⇌ PCl₅(g)',
];

final _f18 = lmAile(
  'kim_hiz_denge',
  'Hız bağıntısı, tepkime derecesi ve denge sabiti',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final w = c ~/ 5;
    switch (c % 5) {
      case 0:
        // w = 0: hız bağıntısı verilir; w = 1: iki basamaklı mekanizmanın
        // yavaş basamağı verilir (en çok üç tanecikli basamaklar).
        final (net, yavas, hizli, m, n, mo, no) = w == 0
            ? const [
                ('', '', '', 1, 1, 0, 0),
                ('', '', '', 2, 1, 0, 0),
                ('', '', '', 1, 2, 0, 0),
                ('', '', '', 2, 2, 0, 0),
                ('', '', '', 0, 1, 0, 0),
              ][a % 5]
            : _mekanizmalar[a % 5];
        final (pn, pd) = const [(2, 1), (3, 1), (4, 1), (5, 1), (1, 2)][a ~/ 5];
        final (qn, qd) = const [
          (2, 1),
          (3, 1),
          (4, 1),
          (5, 1),
          (1, 2),
          (1, 3),
          (1, 4),
          (1, 5),
          (3, 2),
          (5, 2),
          (2, 3),
          (3, 4),
          (4, 3),
          (5, 3),
          (5, 4),
          (2, 5),
          (3, 5),
          (4, 5),
          (6, 1),
          (1, 6),
        ][b];
        final pay = _kuvvet(pn, m) * _kuvvet(qn, n);
        final payda = _kuvvet(pd, m) * _kuvvet(qd, n);
        final giris = w == 0
            ? 'X(g) + Y(g) → Z(g) tepkimesinin hız bağıntısı '
                  '${_hizBagintisi(m, n)} biçimindedir.'
            : '$net tepkimesi iki basamakta gerçekleşmektedir. 1. basamak '
                  '(yavaş): $yavas; 2. basamak (hızlı): $hizli.';
        final bag = w == 0
            ? ''
            : 'Hızı yavaş basamak belirler; dereceler yavaş basamaktaki '
                  'katsayılara eşittir: ${_hizBagintisi(m, n)}. ';
        return kesirli(
          '$giris Sabit sıcaklıkta X derişimi ${kesir(pn, pd)} katına, Y '
              'derişimi ${kesir(qn, qd)} katına getirilirse tepkime hızı ilk hızın '
              'kaç katı olur?',
          pay,
          payda,
          [
            // Mekanizmada dereceleri net tepkimeden alma hatası.
            if (w == 1)
              (
                _kuvvet(pn, mo) * _kuvvet(qn, no),
                _kuvvet(pd, mo) * _kuvvet(qd, no),
              ),
            (pn * qn, pd * qd),
            (_kuvvet(pn, n) * _kuvvet(qn, m), _kuvvet(pd, n) * _kuvvet(qd, m)),
            (pn * m * qd + qn * n * pd, pd * qd),
            (_kuvvet(pn, m) * _kuvvet(qd, n), _kuvvet(pd, m) * _kuvvet(qn, n)),
            (_kuvvet(qn, n), _kuvvet(qd, n)),
          ],
          '${bag}Hız, X için $m. ve Y için $n. derecedendir: '
              '(${kesir(pn, pd)})${_ust(m)}·(${kesir(qn, qd)})${_ust(n)} = '
              '${kesir(pay, payda)} olur.',
        );
      case 1:
        final (m, n) = const [(1, 1), (2, 1), (1, 2), (2, 2), (2, 0)][a % 5];
        final xi = 1 + a ~/ 5, yi = 1 + b % 5, ki = 1 + b ~/ 5;
        final k = ki * _on(m + n) / 1000;
        final hiz = ki * _kuvvet(xi, m) * _kuvvet(yi, n) / 1000;
        final x = xi / 10, y = yi / 10;
        final bagi = _hizBagintisi(m, n);
        final islem =
            '[X]${m == 1 ? '' : _ust(m)} = '
            '${_t(_kuvvet(xi, m) / _on(m), 4)}'
            '${n == 0 ? '' : ', [Y]${n == 1 ? '' : _ust(n)} = ${_t(_kuvvet(yi, n) / _on(n), 4)}'}';
        if (w == 0) {
          return _say(
            'X(g) + Y(g) → Z(g) tepkimesinin hız bağıntısı $bagi biçimindedir '
                've belirli bir sıcaklıkta k = ${_t(k)} olarak verilmiştir. [X] = '
                '${_t(x)} mol/L ve [Y] = ${_t(y)} mol/L olduğu anda tepkime hızı '
                'kaç mol/(L·s) olur?',
            hiz,
            [k * x * y, k * x, hiz * 10, hiz / 10, k * (x + y), hiz * 2],
            '$islem olur. Hız ${_t(k)} ile bu değerlerin çarpımıdır: '
                '${_t(hiz, 3)} mol/(L·s).',
            basamak: 3,
          );
        }
        return _say(
          'X(g) + Y(g) → Z(g) tepkimesinin hız bağıntısı $bagi biçimindedir. '
              'Belirli bir sıcaklıkta [X] = ${_t(x)} mol/L ve [Y] = ${_t(y)} mol/L '
              'olduğu anda tepkime hızı ${_t(hiz, 3)} mol/(L·s) olarak ölçülüyor. '
              'Buna göre hız sabiti k sayısal olarak kaçtır?',
          k,
          [hiz / (x * y), hiz / x, k * 10, k / 10, hiz * x * y, k * 2],
          '$islem olur. k, hızın bu değerlerin çarpımına bölümüdür: k = '
              '${_t(k)}.',
        );
      case 2:
        final (m, n) = const [(1, 1), (2, 1), (1, 2), (2, 2), (0, 1)][a % 5];
        final (p, q) = const [(2, 2), (2, 3), (3, 2), (3, 3), (2, 4)][a ~/ 5];
        final ki = b + 1;
        final h1 = ki / 1000;
        final h2 = h1 * _kuvvet(p, m), h3 = h2 * _kuvvet(q, n);
        final k = ki * _on(m + n) / 1000;
        final deneyler =
            'X(g) + Y(g) → Z(g) tepkimesi için aynı sıcaklıkta üç deney '
            'yapılıyor.\n'
            '1. deney: [X] = 0,1 mol/L, [Y] = 0,1 mol/L, hız = ${_t(h1, 3)} '
            'mol/(L·s)\n'
            '2. deney: [X] = ${_t(p / 10)} mol/L, [Y] = 0,1 mol/L, hız = '
            '${_t(h2, 3)} mol/(L·s)\n'
            '3. deney: [X] = ${_t(p / 10)} mol/L, [Y] = ${_t(q / 10)} mol/L, '
            'hız = ${_t(h3, 3)} mol/(L·s)\n';
        final derece =
            '[X] $p katına çıkınca hız '
            '${m == 0 ? 'değişmediğinden' : '${_kuvvet(p, m)} katı olduğundan'} '
            'X için derece $m; [Y] $q katına çıkınca hız ${_kuvvet(q, n)} katı '
            'olduğundan Y için derece $n olur: ${_hizBagintisi(m, n)}.';
        if (w == 0) {
          return _say(
            '${deneyler}Buna göre hız sabiti k sayısal olarak kaçtır?',
            k,
            [h1 / 0.01, h1 / 0.1, h1 / 0.001, h1 / 0.0001, h1, k * 2],
            '$derece 1. deneyden k = ${_t(h1, 3)} / '
                '${_t(1 / _on(m + n), 4)} = ${_t(k)} bulunur.',
          );
        }
        final h4 = h1 * _kuvvet(5, m + n);
        return _say(
          '${deneyler}Buna göre [X] = 0,5 mol/L ve [Y] = 0,5 mol/L olduğunda '
              'tepkime hızı kaç mol/(L·s) olur?',
          h4,
          [h1 * 5, h1 * 25, h1 * 125, h1 * 625, h1 * 10],
          '$derece 1. deneye göre her iki derişim 5 katına çıktığından hız '
              '5${_ust(m + n)} = ${_kuvvet(5, m + n)} katına çıkar: '
              '${_t(h1, 3)}·${_kuvvet(5, m + n)} = ${_t(h4, 3)} mol/(L·s).',
          basamak: 3,
        );
      case 3:
        final (denk, giren, urun) = _dengeler[a % 5];
        final x = 1 + a ~/ 5, y = 1 + b % 5, z = 1 + b ~/ 5;
        // Derişimler onda bir mol/L birimiyle.
        final deger = switch (a % 5) {
          3 => [x, y + 5 * (z - 1)],
          _ => [x, y, z],
        };
        final tur = [...giren, ...urun];
        var pay = 1, payda = 1, yalinPay = 1, yalinPayda = 1, us = 0;
        for (var j = 0; j < tur.length; j++) {
          final g = _kuvvet(deger[j], tur[j].$2);
          if (j < giren.length) {
            payda *= g;
            yalinPayda *= deger[j];
            us += tur[j].$2;
          } else {
            pay *= g;
            yalinPay *= deger[j];
            us -= tur[j].$2;
          }
        }
        if (us > 0) pay *= _kuvvet(10, us);
        if (us < 0) payda *= _kuvvet(10, -us);
        final veri = _sirala([
          for (var j = 0; j < tur.length; j++)
            '[${tur[j].$1}] = ${_t(deger[j] / 10)} mol/L',
        ]);
        String terim((String, int) t) =>
            '[${t.$1}]${t.$2 == 1 ? '' : _ust(t.$2)}';
        final bagi =
            'Kc = ${urun.map(terim).join('·')} / '
            '${giren.length == 1 ? terim(giren.first) : '(${giren.map(terim).join('·')})'}';
        final giris =
            '$denk tepkimesi belirli bir sıcaklıkta dengeye '
            'ulaştığında derişimler $veri olarak ölçülüyor.';
        if (w == 0) {
          return _oranli(
            '$giris Bu sıcaklıkta tepkimenin derişimler cinsinden denge sabiti '
                '(Kc) kaçtır?',
            pay,
            payda,
            [(payda, pay), (yalinPay, yalinPayda), (yalinPay * 10, yalinPayda)],
            '$bagi bağıntısında değerler yerine yazılırsa Kc = '
                '${_oran(pay, payda)} bulunur.',
          );
        }
        return _oranli(
          '$giris Aynı sıcaklıkta ${_tersDengeler[a % 5]} tepkimesinin '
              'derişimler cinsinden denge sabiti kaçtır?',
          payda,
          pay,
          [(pay, payda), (yalinPayda, yalinPay), (yalinPayda, yalinPay * 10)],
          'Verilen tepkime için $bagi = ${_oran(pay, payda)} olur. Ters '
              'tepkimenin denge sabiti bunun tersidir: ${_oran(payda, pay)}.',
        );
      default:
        final v = w + 1; // kap hacmi (L)
        final yi = 1 + a ~/ 5 + 5 * (b ~/ 5); // dengede oluşan (onda bir mol)
        final ri = const [1, 2, 4, 5, 10][b % 5]; // dengede kalan giren
        final yv = yi / 10, kalan = ri / 10;
        final kap = '$v litrelik kapalı bir kaba';
        switch (a % 5) {
          case 0:
            return _oranli(
              '$kap ${_t(kalan + yv)} mol PCl₅ gazı konuluyor. Sabit sıcaklıkta '
                  'PCl₅(g) ⇌ PCl₃(g) + Cl₂(g) dengesi kurulduğunda kapta ${_t(yv)} '
                  'mol PCl₃ bulunuyor. Buna göre denge sabiti (Kc) kaçtır?',
              yi * yi,
              10 * v * ri,
              [
                (yi * yi, 10 * ri * (3 - v)),
                (yi, ri),
                (yi * yi, 10 * v * (ri + yi)),
              ],
              'Dengede ${_t(yv)} mol PCl₃, ${_t(yv)} mol Cl₂ ve ${_t(kalan)} '
                  'mol PCl₅ bulunur. Derişimler mol sayılarının $v litreye '
                  'bölümüdür; Kc = [PCl₃]·[Cl₂] / [PCl₅] = '
                  '${_oran(yi * yi, 10 * v * ri)} olur.',
            );
          case 1:
            return _oranli(
              '$kap ${_t(kalan + yv)} mol N₂O₄ gazı konuluyor. Sabit '
                  'sıcaklıkta N₂O₄(g) ⇌ 2NO₂(g) dengesi kurulduğunda kapta '
                  '${_t(2 * yv)} mol NO₂ bulunuyor. Buna göre denge sabiti (Kc) '
                  'kaçtır?',
              4 * yi * yi,
              10 * v * ri,
              [
                (4 * yi * yi, 10 * ri * (3 - v)),
                (2 * yi, ri),
                (yi * yi, 10 * v * ri),
              ],
              '${_t(2 * yv)} mol NO₂ oluşurken ${_t(yv)} mol N₂O₄ harcanır; '
                  'dengede ${_t(kalan)} mol N₂O₄ kalır. Derişimler mol sayılarının '
                  '$v litreye bölümüdür; Kc = [NO₂]² / [N₂O₄] = '
                  '${_oran(4 * yi * yi, 10 * v * ri)} olur.',
            );
          case 2:
            // Hacim sadeleşir; w = 1 iken I₂ fazla alınır, böylece hesap da
            // değişir.
            final ri2 = v * ri, kalan2 = ri2 / 10;
            return _oranli(
              '$kap ${_t(kalan + yv)} mol H₂ ve ${_t(kalan2 + yv)} mol I₂ '
                  'gazları konuluyor. Sabit sıcaklıkta H₂(g) + I₂(g) ⇌ 2HI(g) '
                  'dengesi kurulduğunda kapta ${_t(2 * yv)} mol HI bulunuyor. Buna '
                  'göre denge sabiti (Kc) kaçtır?',
              4 * yi * yi,
              ri * ri2,
              [
                (yi * yi, ri * ri2),
                (4 * yi * yi, (ri + yi) * (ri2 + yi)),
                (ri * ri2, 4 * yi * yi),
              ],
              '${_t(2 * yv)} mol HI oluşurken ${_t(yv)} mol H₂ ve ${_t(yv)} mol '
                  'I₂ harcanır; dengede ${v == 1 ? 'her birinden ${_t(kalan)} mol' : '${_t(kalan)} mol H₂ ve ${_t(kalan2)} mol I₂'} '
                  'kalır. Hacim sadeleşir; Kc = [HI]² / ([H₂]·[I₂]) = '
                  '${_t(2 * yv)}² / (${_t(kalan)}·${_t(kalan2)}) = '
                  '${_oran(4 * yi * yi, ri * ri2)} olur.',
            );
          case 3:
            return _oranli(
              '$kap ${_t(kalan + 2 * yv)} mol SO₃ gazı konuluyor. Sabit '
                  'sıcaklıkta 2SO₃(g) ⇌ 2SO₂(g) + O₂(g) dengesi kurulduğunda kapta '
                  '${_t(yv)} mol O₂ bulunuyor. Buna göre denge sabiti (Kc) kaçtır?',
              4 * yi * yi * yi,
              10 * v * ri * ri,
              [
                (4 * yi * yi * yi, 10 * (3 - v) * ri * ri),
                (yi * yi * yi, 10 * v * ri * ri),
                (2 * yi * yi, 10 * v * ri),
              ],
              '${_t(yv)} mol O₂ oluşurken ${_t(2 * yv)} mol SO₂ oluşur ve '
                  '${_t(2 * yv)} mol SO₃ harcanır; dengede ${_t(kalan)} mol SO₃ '
                  'kalır. Derişimler mol sayılarının $v litreye bölümüdür; Kc = '
                  '[SO₂]²·[O₂] / [SO₃]² = ${_oran(4 * yi * yi * yi, 10 * v * ri * ri)} '
                  'olur.',
            );
          default:
            final ri2 = v * ri, kalan2 = ri2 / 10;
            return _oranli(
              '$kap ${_t(kalan + yv)} mol CO ve ${_t(kalan2 + yv)} mol H₂O '
                  'gazları konuluyor. Sabit sıcaklıkta CO(g) + H₂O(g) ⇌ CO₂(g) + '
                  'H₂(g) dengesi kurulduğunda kapta ${_t(yv)} mol CO₂ bulunuyor. '
                  'Buna göre denge sabiti (Kc) kaçtır?',
              yi * yi,
              ri * ri2,
              [
                (yi, ri),
                (yi * yi, (ri + yi) * (ri2 + yi)),
                (ri * ri2, yi * yi),
              ],
              'Dengede ${_t(yv)} mol CO₂ ve ${_t(yv)} mol H₂ oluşur; '
                  '${v == 1 ? 'CO ve H₂O gazlarından ${_t(kalan)} mol' : '${_t(kalan)} mol CO ve ${_t(kalan2)} mol H₂O'} '
                  'kalır. Hacim sadeleşir; Kc = [CO₂]·[H₂] / ([CO]·[H₂O]) = '
                  '${_t(yv)}² / (${_t(kalan)}·${_t(kalan2)}) = '
                  '${_oran(yi * yi, ri * ri2)} olur.',
            );
        }
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 19. pH, pOH ve nötralleşme (kuvvetli asit ve bazlar)
// ---------------------------------------------------------------------------

// (formül, asit mi, formül başına H⁺ ya da OH⁻ sayısı); iki ayrı takım.
const _kuvvetliler = [
  ('HCl', true, 1),
  ('NaOH', false, 1),
  ('H₂SO₄', true, 2),
  ('Ba(OH)₂', false, 2),
  ('HNO₃', true, 1),
  ('HBr', true, 1),
  ('KOH', false, 1),
  ('HI', true, 1),
  ('Sr(OH)₂', false, 2),
  ('LiOH', false, 1),
];

// (asit, H⁺ sayısı, baz, OH⁻ sayısı)
const _notrCiftleri = [
  ('HCl', 1, 'NaOH', 1),
  ('H₂SO₄', 2, 'NaOH', 1),
  ('HNO₃', 1, 'Ba(OH)₂', 2),
  ('H₂SO₄', 2, 'KOH', 1),
  ('HCl', 1, 'Ba(OH)₂', 2),
  ('HNO₃', 1, 'KOH', 1),
  ('H₂SO₄', 2, 'LiOH', 1),
  ('HBr', 1, 'Ba(OH)₂', 2),
  ('HCl', 1, 'KOH', 1),
  ('HBr', 1, 'NaOH', 1),
];

const _litreler = [
  0.02,
  0.04,
  0.05,
  0.1,
  0.2,
  0.25,
  0.4,
  0.5,
  0.8,
  1,
  2,
  2.5,
  4,
  5,
  8,
  10,
  20,
  25,
  40,
  50,
];

final _f19 = lmAile(
  'kim_asit_baz',
  'Kuvvetli asit ve bazlarda pH, pOH ve nötralleşme',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final w = c ~/ 5;
    switch (c % 5) {
      case 0:
        final (f, asit, nu) = _kuvvetliler[a % 5 + 5 * w];
        final k = 1 + a ~/ 5;
        final v = _litreler[b];
        final hacim = v < 1 ? '${_t(v * 1000)} mL' : '${_t(v)} L';
        final n = _bilimsel(v / nu, -k);
        final ph = asit ? k : 14 - k;
        final iyon = asit ? 'H⁺' : 'OH⁻';
        return sayisal(
          'Hacmi $hacim olan sulu çözeltide $n mol $f çözünmüştür. $f suda '
              'tamamen iyonlaştığına göre 25 °C sıcaklıkta çözeltinin pH değeri '
              'kaçtır?',
          ph,
          [14 - ph, ph + 1, ph - 1, 7],
          '${nu == 1 ? '' : 'Bir formül birimi $nu tane $iyon verir. '}[$iyon] '
              '= ${nu == 1 ? '' : '$nu·'}$n / ${_t(v)} = 10${_ust(-k)} mol/L olur. '
              '${asit ? 'pH = $k bulunur.' : 'pOH = $k olduğundan pH = 14 − $k = $ph bulunur.'}',
          positive: true,
        );
      case 1:
        final (f, asit, _) = _kuvvetliler[a % 5 + 5 * w];
        final (k, j) = const [
          (1, 1),
          (1, 2),
          (2, 1),
          (2, 2),
          (3, 1),
          (3, 2),
          (4, 1),
          (4, 2),
          (1, 3),
          (2, 3),
        ][a ~/ 5 * 2 + b % 2];
        final v = const [10, 20, 25, 40, 50, 100, 200, 250, 400, 500][b ~/ 2];
        final kat = _kuvvet(10, j);
        final ilk = asit ? k : 14 - k, son = asit ? k + j : 14 - k - j;
        return sayisal(
          '25 °C sıcaklıkta pH değeri $ilk olan $v mL $f çözeltisine saf su '
          'eklenerek hacmi $kat katına çıkarılıyor. Son çözeltinin pH değeri '
          'kaçtır?',
          son,
          [
            asit ? ilk - j : (ilk + j <= 14 ? ilk + j : 14 - son),
            ilk,
            asit ? son + 1 : son - 1,
            7,
            14 - son,
          ],
          asit
              ? 'Hacim $kat katına çıkınca [H⁺] 10${_ust(-k)} değerinden '
                    '10${_ust(-k - j)} mol/L değerine düşer; pH = $son olur.'
              : 'pOH = 14 − $ilk = $k olur. Hacim $kat katına çıkınca [OH⁻] '
                    '10${_ust(-k)} değerinden 10${_ust(-k - j)} mol/L değerine '
                    'düşer; pOH = ${k + j}, pH = 14 − ${k + j} = $son olur.',
          positive: true,
        );
      case 2:
        final (asit, na, baz, nb) = _notrCiftleri[a % 5 + 5 * w];
        final i = 1 + a ~/ 5, jj = 1 + b % 4, carpan = 1 + b ~/ 4;
        final d1 = i / 20, d2 = jj / 25;
        final v1 = nb * 4 * jj * carpan, v2 = na * 5 * i * carpan;
        return sayisal(
          '${_t(d1)} mol/L derişimli $v1 mL $asit çözeltisini tamamen '
              'nötrleştirmek için ${_t(d2)} mol/L derişimli $baz çözeltisinden kaç '
              'mL gerekir?',
          v2,
          [v2 * nb ~/ na, v2 * nb, v1, v2 * 2, v2 ~/ 2, v2 + v1],
          'n(H⁺) = $na·${_t(d1)}·$v1 = ${_t(na * d1 * v1)} mmol olur. Nötralleşmede '
              'n(H⁺) = n(OH⁻) olduğundan $nb·${_t(d2)}·V = ${_t(na * d1 * v1)} '
              'eşitliğinden V = $v2 mL bulunur.',
          unit: 'mL',
          positive: true,
        );
      case 3:
        final (asit, baz) = const [
          ('HCl', 'NaOH'),
          ('HNO₃', 'KOH'),
          ('HBr', 'NaOH'),
          ('HCl', 'KOH'),
          ('HNO₃', 'NaOH'),
        ][a % 5];
        final k = w + 1;
        final az = (1 + a ~/ 5) / 10, cok = az + 2 / _on(k);
        final asitFazla = b.isEven;
        final v = const [
          50,
          100,
          150,
          200,
          250,
          300,
          400,
          500,
          750,
          1000,
        ][b ~/ 2];
        final ca = asitFazla ? cok : az, cb = asitFazla ? az : cok;
        final ph = asitFazla ? k : 14 - k;
        final fazla = asitFazla ? 'H⁺' : 'OH⁻';
        final artan = 2 / _on(k) * v / 1000;
        return sayisal(
          '${_t(ca)} mol/L derişimli $v mL $asit çözeltisi ile ${_t(cb)} mol/L '
              'derişimli $v mL $baz çözeltisi karıştırılıyor. 25 °C sıcaklıkta '
              'karışımın pH değeri kaçtır?',
          ph,
          [14 - ph, 7, ph + 1, ph - 1],
          'n(H⁺) = ${_t(ca * v / 1000, 4)} mol, n(OH⁻) = '
              '${_t(cb * v / 1000, 4)} mol olur; ${_t(artan, 4)} mol $fazla artar. '
              'Toplam hacim ${_t(2 * v / 1000)} L olduğundan [$fazla] = '
              '10${_ust(-k)} mol/L, ${asitFazla ? 'pH = $k' : 'pOH = $k ve pH = 14 − $k = $ph'} '
              'bulunur.',
          positive: true,
        );
      default:
        final (baz, nb) = const [
          ('NaOH', 1),
          ('KOH', 1),
          ('Ca(OH)₂', 2),
          ('LiOH', 1),
          ('Sr(OH)₂', 2),
        ][a % 5];
        final (asit, na) = w == 0 ? ('HCl', 1) : ('H₂SO₄', 2);
        final i = 1 + a ~/ 5;
        final d = i / 10, v = 100 * (b + 1);
        final hMol = na * i * (b + 1) / 100, bMol = hMol / nb;
        final mk = _mk(baz), m = bMol * mk;
        return sayisal(
          '${_t(m)} gram $baz bazını tamamen nötrleştirmek için ${_t(d)} mol/L '
              'derişimli $asit çözeltisinden kaç mL gerekir? (${_kut([baz])})',
          v,
          [v * na, v * nb ~/ na, v ~/ 2, v * 2, v + 100, v * nb],
          '${_t(m)} / ${_t(mk)} = ${_t(bMol, 3)} mol $baz ${_t(hMol)} mol OH⁻ '
              'verir. Gereken asit ${_t(hMol)} / $na = ${_t(hMol / na, 3)} moldür; '
              'hacmi ${_t(hMol / na, 3)} / ${_t(d)} = ${_t(v / 1000)} L = $v mL '
              'olur.',
          unit: 'mL',
          positive: true,
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 20. Yükseltgenme basamağı, pil gerilimi ve Faraday yasası
// ---------------------------------------------------------------------------

// (tanecik, sorulan atom, yükseltgenme basamağı): −4 … +4 arası.
const _basamakA = [
  ('NH₃', 'N', -3),
  ('CH₄', 'C', -4),
  ('H₂S', 'S', -2),
  ('H₂O₂', 'O', -1),
  ('CaH₂', 'H', -1),
  ('N₂H₄', 'N', -2),
  ('OF₂', 'O', 2),
  ('CO', 'C', 2),
  ('CO₂', 'C', 4),
  ('SO₂', 'S', 4),
  ('NO', 'N', 2),
  ('N₂O', 'N', 1),
  ('NO₂', 'N', 4),
  ('N₂O₃', 'N', 3),
  ('HNO₂', 'N', 3),
  ('HClO', 'Cl', 1),
  ('HClO₂', 'Cl', 3),
  ('MnO₂', 'Mn', 4),
  ('Fe₂O₃', 'Fe', 3),
  ('Cu₂O', 'Cu', 1),
  ('SO₃²⁻', 'S', 4),
  ('NO₂⁻', 'N', 3),
  ('CO₃²⁻', 'C', 4),
  ('C₂O₄²⁻', 'C', 3),
  ('NH₄⁺', 'N', -3),
];

// (tanecik, sorulan atom, yükseltgenme basamağı): +5 … +7 arası.
const _basamakB = [
  ('KMnO₄', 'Mn', 7),
  ('K₂Cr₂O₇', 'Cr', 6),
  ('H₂SO₄', 'S', 6),
  ('HNO₃', 'N', 5),
  ('HClO₄', 'Cl', 7),
  ('H₃PO₄', 'P', 5),
  ('KClO₃', 'Cl', 5),
  ('Na₂SO₄', 'S', 6),
  ('SO₃', 'S', 6),
  ('N₂O₅', 'N', 5),
  ('CrO₄²⁻', 'Cr', 6),
  ('MnO₄⁻', 'Mn', 7),
  ('NO₃⁻', 'N', 5),
  ('SO₄²⁻', 'S', 6),
  ('PO₄³⁻', 'P', 5),
  ('Cr₂O₇²⁻', 'Cr', 6),
  ('ClO₄⁻', 'Cl', 7),
  ('ClO₃⁻', 'Cl', 5),
  ('K₂MnO₄', 'Mn', 6),
  ('P₄O₁₀', 'P', 5),
];

// (metal, iyonu, standart indirgenme potansiyeli × 100 V); artan sırada.
const _yariHucreler = [
  ('Li', 'Li⁺', -304),
  ('K', 'K⁺', -293),
  ('Ca', 'Ca²⁺', -287),
  ('Na', 'Na⁺', -271),
  ('Mg', 'Mg²⁺', -237),
  ('Al', 'Al³⁺', -166),
  ('Mn', 'Mn²⁺', -118),
  ('Zn', 'Zn²⁺', -76),
  ('Cr', 'Cr³⁺', -74),
  ('Fe', 'Fe²⁺', -44),
  ('Cd', 'Cd²⁺', -40),
  ('Co', 'Co²⁺', -28),
  ('Ni', 'Ni²⁺', -25),
  ('Sn', 'Sn²⁺', -14),
  ('Pb', 'Pb²⁺', -13),
  ('Cu', 'Cu²⁺', 34),
  ('Ag', 'Ag⁺', 80),
  ('Hg', 'Hg²⁺', 85),
  ('Au', 'Au³⁺', 150),
];

// (ilk tanecik, son tanecik, atom, ilk basamak, son basamak, tanecikteki
// atom sayısı)
const _donusumler = [
  ('MnO₄⁻', 'Mn²⁺', 'Mn', 7, 2, 1),
  ('MnO₄⁻', 'MnO₂', 'Mn', 7, 4, 1),
  ('Cr₂O₇²⁻', 'Cr³⁺', 'Cr', 6, 3, 2),
  ('NO₃⁻', 'NO', 'N', 5, 2, 1),
  ('IO₃⁻', 'I₂', 'I', 5, 0, 1),
  ('NO₃⁻', 'NH₄⁺', 'N', 5, -3, 1),
  ('SO₄²⁻', 'SO₂', 'S', 6, 4, 1),
  ('ClO₃⁻', 'Cl⁻', 'Cl', 5, -1, 1),
  ('Al', 'Al³⁺', 'Al', 0, 3, 1),
  ('N₂', 'NH₃', 'N', 0, -3, 2),
  ('Sn²⁺', 'Sn⁴⁺', 'Sn', 2, 4, 1),
  ('H₂O₂', 'O₂', 'O', -1, 0, 2),
  ('H₂O₂', 'H₂O', 'O', -1, -2, 2),
  ('C₂O₄²⁻', 'CO₂', 'C', 3, 4, 2),
  ('SO₃²⁻', 'SO₄²⁻', 'S', 4, 6, 1),
  ('H₂S', 'S', 'S', -2, 0, 1),
  ('H₂S', 'SO₂', 'S', -2, 4, 1),
  ('NH₃', 'NO', 'N', -3, 2, 1),
  ('MnO₂', 'Mn²⁺', 'Mn', 4, 2, 1),
  ('ClO⁻', 'Cl⁻', 'Cl', 1, -1, 1),
  ('NO₂⁻', 'NO₃⁻', 'N', 3, 5, 1),
  ('Cr³⁺', 'CrO₄²⁻', 'Cr', 3, 6, 1),
  ('PbO₂', 'Pb²⁺', 'Pb', 4, 2, 1),
  ('SO₂', 'SO₄²⁻', 'S', 4, 6, 1),
  ('CH₄', 'CO₂', 'C', -4, 4, 1),
];

// (metal, iyonu, iyon yükü); iki ayrı takım.
const _kaplananlar = [
  ('Ag', 'Ag⁺', 1),
  ('Cu', 'Cu²⁺', 2),
  ('Al', 'Al³⁺', 3),
  ('Zn', 'Zn²⁺', 2),
  ('Fe', 'Fe²⁺', 2),
  ('Ni', 'Ni²⁺', 2),
  ('Mg', 'Mg²⁺', 2),
  ('Na', 'Na⁺', 1),
  ('Ca', 'Ca²⁺', 2),
  ('Cr', 'Cr³⁺', 3),
];

// (olay, gaz, 1 mol gaz için gereken elektron molü)
const _gazElektrolizleri = [
  ('Erimiş NaCl tuzunun elektrolizinde anotta', 'Cl₂', 2),
  ('Suyun elektrolizinde katotta', 'H₂', 2),
  ('Suyun elektrolizinde anotta', 'O₂', 4),
  ('Erimiş MgCl₂ tuzunun elektrolizinde anotta', 'Cl₂', 2),
  ('Derişik HCl çözeltisinin elektrolizinde katotta', 'H₂', 2),
];

const _akimlar = [9.65, 19.3, 38.6, 48.25, 96.5];
const _faraday = '1 mol elektronun yükü 96500 C';

String _turEki(String f) =>
    f.endsWith('⁺') || f.endsWith('⁻') ? 'iyonundaki' : 'bileşiğindeki';

/// Negatif sayıyı ifade içinde parantezle yazar.
String _par(num x) => x < 0 ? '(${_t(x)})' : _t(x);

final _f20 = lmAile(
  'kim_elektrokimya',
  'Yükseltgenme basamağı, pil gerilimi ve elektroliz',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.uygulama,
  (a, b, c) {
    switch (c) {
      case 0:
      case 5:
        final (f1, e1, s1) = _basamakA[a];
        final (f2, e2, s2) = _basamakB[b];
        final t1 = '$f1 ${_turEki(f1)} $e1 atomunun yükseltgenme basamağı';
        final t2 = '$f2 ${_turEki(f2)} $e2 atomunun yükseltgenme basamağı';
        final bilgi =
            'Yükseltgenme basamakları toplamı bileşikte sıfıra, iyonda iyon '
            'yüküne eşittir: $f1 içinde $e1 ${_isaretli(s1)}, $f2 içinde $e2 '
            '${_isaretli(s2)} değerini alır.';
        if (c == 0) {
          return _say('$t1 ile ${t2}nın toplamı kaçtır?', s1 + s2, [
            s2 - s1,
            s2,
            s1.abs() + s2,
            s1 + s2 + 1,
            s1 + s2 - 1,
            s1 + s2 + 2,
          ], '$bilgi Toplam ${_par(s1)} + $s2 = ${s1 + s2} olur.');
        }
        return _say('$t2, ${t1}ndan kaç fazladır?', s2 - s1, [
          s1 + s2,
          s2,
          (s2 - s1.abs()).abs(),
          s2 - s1 + 1,
          s2 - s1 - 1,
        ], '$bilgi Fark $s2 − ${_par(s1)} = ${s2 - s1} olur.');
      case 1:
        final sira = a * 20 + b;
        final cift = kombinasyon(_yariHucreler, 2, sira % 171, spread: false);
        final (ma, ia, pa) = cift[0]; // küçük potansiyel: anot
        final (mc, ic, pc) = cift[1];
        final ea = pa / 100, ec = pc / 100, pil = (pc - pa) / 100;
        final once = sira.isEven;
        final karar =
            'İndirgenme potansiyeli büyük olan $mc katot, küçük olan $ma anot '
            'olur.';
        final hesap =
            'E°pil = E°katot − E°anot = ${_t(ec)} − ${_par(ea)} = ${_t(pil)} V';
        switch (sira ~/ 171) {
          case 0:
            final ilk = '$ia/$ma için ${_isaretli(ea)} V';
            final son = '$ic/$mc için ${_isaretli(ec)} V';
            return _say(
              'Standart indirgenme potansiyelleri '
                  '${once ? '$ilk, $son' : '$son, $ilk'} olarak verilmiştir. Bu iki '
                  'yarı hücreden oluşturulan galvanik pilin standart potansiyeli '
                  'kaç V olur?',
              pil,
              [(ec + ea).abs(), ec.abs(), ea.abs(), pil / 2, pil * 2],
              '$karar $hesap bulunur.',
              birim: 'V',
            );
          case 1:
            final ilk = '$ma/$ia için ${_isaretli(-ea)} V';
            final son = '$mc/$ic için ${_isaretli(-ec)} V';
            return _say(
              'Standart yükseltgenme potansiyelleri '
                  '${once ? '$ilk, $son' : '$son, $ilk'} olarak verilmiştir. Bu iki '
                  'yarı hücreden oluşturulan galvanik pilin standart potansiyeli '
                  'kaç V olur?',
              pil,
              [(ec + ea).abs(), ec.abs(), ea.abs(), pil / 2, pil * 2],
              'Yükseltgenme potansiyeli büyük olan $ma anot, küçük olan $mc '
                  'katot olur. E°pil = E°yük(anot) − E°yük(katot) = ${_t(-ea)} − '
                  '${_par(-ec)} = ${_t(pil)} V bulunur.',
              birim: 'V',
            );
          default:
            return _say(
              'Anodu $ma, katodu $mc olan galvanik pilin standart potansiyeli '
                  '${_t(pil)} V olarak ölçülüyor. $ic/$mc yarı hücresinin standart '
                  'indirgenme potansiyeli ${_isaretli(ec)} V olduğuna göre $ia/$ma '
                  'yarı hücresinin standart indirgenme potansiyeli kaç V olur?',
              ea,
              [-ea, ec + pil, -(ec + pil), pil, -pil, ea - 1],
              'E°pil = E°katot − E°anot eşitliğinden E°anot = ${_t(ec)} − '
                  '${_t(pil)} = ${_t(ea)} V bulunur.',
              birim: 'V',
              arti: false,
              isaret: true,
            );
        }
      case 6:
        final (ilk, son, el, s1, s2, adet) = _donusumler[a];
        final fark = (s1 - s2).abs(), e = fark * adet;
        final n = (b + 1) / 10;
        final alir = s1 > s2;
        return _say(
          'Bir tepkimede ${_t(n)} mol $ilk taneciğinin tamamı $son taneciğine '
              'dönüşüyor. Bu dönüşümde $ilk tarafından '
              '${alir ? 'alınan' : 'verilen'} elektron kaç moldür?',
          e * n,
          [
            n * (e + 1),
            if (e > 1) n * (e - 1),
            n * e * 2,
            n * e / 2,
            n,
            n * (e + 2),
          ],
          '$el atomunun yükseltgenme basamağı ${_isaretli(s1)} değerinden '
              '${_isaretli(s2)} değerine ${alir ? 'iner' : 'çıkar'}; atom başına '
              '$fark elektron ${alir ? 'alınır' : 'verilir'}. '
              '${adet == 1 ? '' : 'Bir $ilk taneciğinde $adet tane $el atomu bulunduğundan tanecik başına $e elektron aktarılır. '}'
              '${_t(n)} mol için ${_t(n)}·$e = ${_t(e * n)} mol elektron bulunur.',
          birim: 'mol',
        );
      case 3:
        final (olay, gaz, ze) = _gazElektrolizleri[a % 5];
        final akim = _akimlar[a ~/ 5];
        final k = b + 1;
        final sure = const [500, 250, 125, 100, 50][a ~/ 5] * k;
        final ne = k / 20, v = 22.4 * ne / ze;
        return _say(
          '$olay $gaz gazı açığa çıkmaktadır. Hücreden ${_t(akim)} amperlik '
              'akım $sure saniye boyunca geçirildiğinde normal koşullarda kaç '
              'litre $gaz gazı elde edilir? ($_faraday; normal koşullarda 1 mol '
              'gaz 22,4 L hacim kaplar)',
          v,
          [22.4 * ne, v * 2, v / 2, ne / ze, 22.4 * ne * ze],
          'Q = ${_t(akim)}·$sure = ${4825 * k} C, n(e⁻) = ${4825 * k} / 96500 '
              '= ${_t(ne)} mol olur. 1 mol $gaz için $ze mol elektron gerektiğinden '
              '${_t(ne)} / $ze = ${_t(ne / ze, 4)} mol gaz oluşur; hacmi '
              '${_t(v)} L bulunur.',
          birim: 'L',
        );
      case 8:
        final ciftler = [
          for (var i = 0; i < 6; i++)
            for (var j = 0; j < 6; j++)
              if (i != j)
                (const [0, 1, 2, 3, 5, 9][i], const [0, 1, 2, 3, 5, 9][j]),
        ];
        final (i1, i2) = ciftler[a];
        final (m1, y1, z1) = _kaplananlar[i1];
        final (m2, y2, z2) = _kaplananlar[i2];
        final k1 = _atomKutlesi[m1]!, k2 = _atomKutlesi[m2]!;
        final ne = 6 * (b + 1) / 100;
        final g1 = ne / z1 * k1, g2 = ne / z2 * k2;
        return _say(
          'Seri bağlı iki elektroliz hücresinden birincisinde $y1 iyonları $m1 '
              'metaline, ikincisinde $y2 iyonları $m2 metaline indirgenmektedir. '
              'Devreden bir süre akım geçirildiğinde birinci hücrenin katodunda '
              '${_t(g1)} gram $m1 toplandığına göre ikinci hücrenin katodunda kaç '
              'gram $m2 toplanır? ($m1: ${_t(k1)}, $m2: ${_t(k2)})',
          g2,
          [g1 * k2 / k1, g1, g2 * z2 / z1, g1 * z1 / z2, g2 * 2, g2 / 2],
          'Birinci hücrede ${_t(g1)} / ${_t(k1)} = ${_t(ne / z1)} mol $m1 için '
              '${_t(ne / z1)}·$z1 = ${_t(ne)} mol elektron geçer. Seri bağlı '
              'hücrelerden aynı yük geçtiğinden ikinci hücrede ${_t(ne)} / $z2 = '
              '${_t(ne / z2)} mol $m2, yani ${_t(g2)} gram metal toplanır.',
          birim: 'g',
        );
      default:
        // Katotta metal toplanması: c = 2, 7 (akım ve süre), c = 4, 9 (yük).
        final (metal, iyon, z) =
            _kaplananlar[a % 5 + (c == 7 || c == 9 ? 5 : 0)];
        final ak = _atomKutlesi[metal]!;
        final giris =
            '$iyon iyonlarının katotta $metal metaline indirgendiği '
            'bir elektroliz hücresinden';
        if (c == 2 || c == 7) {
          final akim = _akimlar[a ~/ 5];
          final k = b + 1;
          final sure = const [100, 50, 25, 20, 10][a ~/ 5] * k * z;
          final yuk = 965 * k * z;
          final mol = k / 100, m = mol * ak;
          final yol =
              '${_t(m)} gram $metal ${_t(mol)} moldür ve ${_t(mol)}·$z = '
              '${_t(mol * z)} mol elektron gerektirir.';
          if (c == 2) {
            return _say(
              '$giris ${_t(akim)} amperlik akım $sure saniye boyunca '
                  'geçiriliyor. Katotta kaç gram $metal toplanır? ($metal: '
                  '${_t(ak)}; $_faraday)',
              m,
              [m * z, mol * z, m * 2, m / 2, m / z, m + ak / 100],
              'Q = ${_t(akim)}·$sure = $yuk C, n(e⁻) = $yuk / 96500 = '
                  '${_t(mol * z)} mol olur. 1 mol $metal için $z mol elektron '
                  'gerektiğinden ${_t(mol)} mol, yani ${_t(m)} gram $metal '
                  'toplanır.',
              birim: 'g',
            );
          }
          return sayisal(
            '$giris ${_t(akim)} amperlik akım geçiriliyor. Katotta ${_t(m)} '
                'gram $metal toplanması için akım kaç saniye geçirilmelidir? '
                '($metal: ${_t(ak)}; $_faraday)',
            sure,
            [sure ~/ z, sure * z, sure * 2, sure ~/ 2, sure + 100],
            '$yol Q = ${_t(mol * z)}·96500 = $yuk C olur. t = Q / I = $yuk / '
                '${_t(akim)} = $sure saniye bulunur.',
            unit: 's',
            positive: true,
          );
        }
        final k = b + 1 + 20 * (a ~/ 5);
        final mol = k / 100, m = mol * ak;
        final yuk = 965 * k * z;
        if (c == 4) {
          return sayisal(
            '$giris akım geçiriliyor. Katotta ${_t(m)} gram $metal toplanması '
                'için devreden kaç coulomb yük geçmelidir? ($metal: ${_t(ak)}; '
                '$_faraday)',
            yuk,
            [965 * k, 965 * k * (z + 1), yuk * 2, yuk ~/ 2, 96500 * z],
            '${_t(m)} gram $metal ${_t(mol)} moldür ve ${_t(mol)}·$z = '
                '${_t(mol * z)} mol elektron gerektirir. Q = ${_t(mol * z)}·96500 '
                '= $yuk C bulunur.',
            unit: 'C',
            positive: true,
          );
        }
        return _say(
          'Bir X metalinin erimiş tuzunun elektrolizinde devreden $yuk coulomb '
              'yük geçtiğinde katotta ${_t(m)} gram X metali toplanıyor. X '
              'metalinin atom kütlesi ${_t(ak)} olduğuna göre tuzdaki X iyonunun '
              'yükü kaçtır? ($_faraday)',
          z,
          [z + 1, z - 1, z + 2, z + 3],
          'n(e⁻) = $yuk / 96500 = ${_t(mol * z)} mol, n(X) = ${_t(m)} / '
              '${_t(ak)} = ${_t(mol)} mol olur. Atom başına ${_t(mol * z)} / '
              '${_t(mol)} = $z elektron alındığından iyonun yükü +$z bulunur.',
          isaret: true,
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

final lmKimya = <AdvancedFamily>[
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
  _f16,
  _f17,
  _f18,
  _f19,
  _f20,
];
