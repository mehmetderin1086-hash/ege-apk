// Lise kimya metin aileleri (2. tur): temel kanunlardan organik kimyaya 20
// kazanım. Her aile 5.000 ayrı soru kökü üretir; veriler gerçek maddelerden ve
// ders kitabı değerlerinden seçilir, anahtarlar koordinatlardan hesaplanır.
import 'ortak.dart';

// ───────────────────────────── Ortak yardımcılar ─────────────────────────────

const _altRakam = '₀₁₂₃₄₅₆₇₈₉';
const _ustRakam = '⁰¹²³⁴⁵⁶⁷⁸⁹';

String _alt(int n) => '$n'.split('').map((r) => _altRakam[int.parse(r)]).join();

String _ust(int n) =>
    '${n < 0 ? '⁻' : ''}${'${n.abs()}'.split('').map((r) => _ustRakam[int.parse(r)]).join()}';

/// İyon yükü üst simgesi: 2 → “²⁺”, −1 → “⁻”.
String _yuk(int q) =>
    q == 0 ? '' : '${q.abs() == 1 ? '' : _ust(q.abs())}${q > 0 ? '⁺' : '⁻'}';

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
/// hata verir.
String _t(num x, [int d = 2]) {
  final y = x * _on(d);
  if ((y - y.roundToDouble()).abs() > 1e-6 * (1 + y.abs())) {
    throw StateError('Kesin değil: $x ($d basamak)');
  }
  return _yz(x, d);
}

/// Cümle başı için ilk harfi büyütür (Türkçe i → İ).
String _bas(String s) => s.isEmpty
    ? s
    : '${s[0] == 'i' ? 'İ' : s[0].toUpperCase()}${s.substring(1)}';

String _uc(List<String> x) => 'I. ${x[0]}\nII. ${x[1]}\nIII. ${x[2]}';

const _romaRakam = ['I', 'II', 'III'];

/// [n] elemanlı listeden [k] elemanlı bütün seçkiler (sözlük sırasıyla).
List<List<T>> _secimler<T>(List<T> items, int k) {
  final out = <List<T>>[];
  void kur(int bas, List<T> secili) {
    if (secili.length == k) {
      out.add([...secili]);
      return;
    }
    for (var j = bas; j < items.length; j++) {
      secili.add(items[j]);
      kur(j + 1, secili);
      secili.removeLast();
    }
  }

  kur(0, <T>[]);
  return out;
}

/// [n] elemanın bütün dizilimleri (sözlük sırasıyla).
List<List<int>> _dizilimler(int n) {
  final out = <List<int>>[];
  void kur(List<int> d) {
    if (d.length == n) {
      out.add([...d]);
      return;
    }
    for (var j = 0; j < n; j++) {
      if (d.contains(j)) continue;
      d.add(j);
      kur(d);
      d.removeLast();
    }
  }

  kur(<int>[]);
  return out;
}

final _dizilim3 = _dizilimler(3);
final _dizilim4 = _dizilimler(4);

/// Sayısal yanıtlı soru. Doğru yanıt kesin yazılır; çeldiriciler tipik
/// hatalardan gelir, yetmezse komşu değerlerle tamamlanır.
AdvancedItem _say(
  String kok,
  num dogru,
  Iterable<num> adaylar,
  String aciklama, {
  String birim = '',
  int basamak = 2,
  bool arti = true,
}) {
  String yaz(num x, {bool kesin = false}) =>
      birimli(kesin ? _t(x, basamak) : _yz(x, basamak), birim);
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

/// Üç konumlu sıralı yanıt. Her çeldirici bir konumu doğru bırakır, öteki iki
/// konuma o konumun yanlış adayını yazar; böylece her seçenek ötekilerle tam
/// bir konumda ortaklaşır ve seçeneklerin yapısı doğru yanıtı ele vermez.
AdvancedItem _uclu(
  String kok,
  List<String> dogru,
  List<String> yanlis,
  String aciklama, {
  String ayrac = ' – ',
}) {
  for (var p = 0; p < 3; p++) {
    if (yanlis[p] == dogru[p]) {
      throw StateError('Yanlış aday doğruya eşit: $kok');
    }
  }
  String yaz(List<String> v) => v.join(ayrac);
  return secenekli(kok, yaz(dogru), [
    for (var p = 0; p < 3; p++)
      yaz([for (var q = 0; q < 3; q++) q == p ? dogru[q] : yanlis[q]]),
  ], aciklama);
}

/// Adaylardan [kay] sırasından başlayarak, üçlüdeki öteki doğru yanıtlarla
/// çakışmayan ilk yanlışı seçer.
String _secYanlis(List<String> adaylar, int kay, List<String> dogrular) {
  for (var r = 0; r < adaylar.length; r++) {
    final s = adaylar[(kay + r) % adaylar.length];
    if (!dogrular.contains(s)) return s;
  }
  return adaylar[kay % adaylar.length];
}

const _kumeAdi = {
  1: 'Yalnız I',
  2: 'Yalnız II',
  4: 'Yalnız III',
  3: 'I ve II',
  5: 'I ve III',
  6: 'II ve III',
  7: 'I, II ve III',
};

/// “Hangileri?” sorusu. [maske] doğru numaraları bit olarak taşır (bit 0 = I).
/// Seçenekler dengeli iki takımdan biridir: {I, II, III, hepsi} ya da
/// {I-II, I-III, II-III, hepsi}; her numara takım içinde eşit sıklıkta geçer.
AdvancedItem _hangileri(String kok, int maske, String aciklama, int i) {
  if (maske < 1 || maske > 7) throw StateError('Boş maske: $kok');
  final tekli =
      maske == 1 || maske == 2 || maske == 4 || (maske == 7 && i.isEven);
  final takim = tekli ? const [1, 2, 4, 7] : const [3, 5, 6, 7];
  return secenekli(kok, _kumeAdi[maske]!, [
    for (final m in takim)
      if (m != maske) _kumeAdi[m]!,
  ], aciklama);
}

// ───────────────────── 1 · Kütlenin korunumu, sabit ve katlı oranlar ─────────

// (formül, ad, X simgesi, X adı, Y simgesi, Y adı, p, q, u): p/q kütlece
// birleşme oranıdır (atom kütleleri H 1, C 12, N 14, O 16, Na 23, Mg 24, Al 27,
// Si 28, P 31, S 32, Cl 35,5, K 39, Ca 40, Fe 56, Cu 64, Zn 65, Br 80). u, birim
// kütlenin onda biri olarak adımıdır; kütleler 1 ile 300 gram arasında kalır.
const _sabitOranlar = [
  ('H₂O', 'su', 'H', 'hidrojen', 'O', 'oksijen', 1, 8, 10),
  ('CO₂', 'karbon dioksit', 'C', 'karbon', 'O', 'oksijen', 3, 8, 10),
  ('CO', 'karbon monoksit', 'C', 'karbon', 'O', 'oksijen', 3, 4, 10),
  ('MgO', 'magnezyum oksit', 'Mg', 'magnezyum', 'O', 'oksijen', 3, 2, 20),
  ('CaO', 'kalsiyum oksit', 'Ca', 'kalsiyum', 'O', 'oksijen', 5, 2, 10),
  ('FeS', 'demir(II) sülfür', 'Fe', 'demir', 'S', 'kükürt', 7, 4, 10),
  ('CuO', 'bakır(II) oksit', 'Cu', 'bakır', 'O', 'oksijen', 4, 1, 20),
  ('Fe₂O₃', 'demir(III) oksit', 'Fe', 'demir', 'O', 'oksijen', 7, 3, 10),
  ('CaS', 'kalsiyum sülfür', 'Ca', 'kalsiyum', 'S', 'kükürt', 5, 4, 10),
  ('Al₂O₃', 'alüminyum oksit', 'Al', 'alüminyum', 'O', 'oksijen', 9, 8, 5),
  ('ZnS', 'çinko sülfür', 'Zn', 'çinko', 'S', 'kükürt', 65, 32, 1),
  ('Al₂S₃', 'alüminyum sülfür', 'Al', 'alüminyum', 'S', 'kükürt', 9, 16, 4),
  ('Mg₃N₂', 'magnezyum nitrür', 'Mg', 'magnezyum', 'N', 'azot', 18, 7, 4),
  ('Ca₃N₂', 'kalsiyum nitrür', 'Ca', 'kalsiyum', 'N', 'azot', 30, 7, 3),
  ('KBr', 'potasyum bromür', 'K', 'potasyum', 'Br', 'brom', 39, 80, 1),
  ('NaCl', 'sodyum klorür', 'Na', 'sodyum', 'Cl', 'klor', 46, 71, 1),
  ('MgCl₂', 'magnezyum klorür', 'Mg', 'magnezyum', 'Cl', 'klor', 24, 71, 1),
  ('CaCl₂', 'kalsiyum klorür', 'Ca', 'kalsiyum', 'Cl', 'klor', 40, 71, 1),
  ('HCl', 'hidrojen klorür', 'H', 'hidrojen', 'Cl', 'klor', 2, 71, 1),
  ('CuCl₂', 'bakır(II) klorür', 'Cu', 'bakır', 'Cl', 'klor', 64, 71, 1),
  ('KCl', 'potasyum klorür', 'K', 'potasyum', 'Cl', 'klor', 78, 71, 1),
  ('Na₂S', 'sodyum sülfür', 'Na', 'sodyum', 'S', 'kükürt', 23, 16, 3),
  ('SiO₂', 'silisyum dioksit', 'Si', 'silisyum', 'O', 'oksijen', 7, 8, 6),
  ('P₂O₅', 'difosfor pentaoksit', 'P', 'fosfor', 'O', 'oksijen', 31, 40, 1),
  ('AlN', 'alüminyum nitrür', 'Al', 'alüminyum', 'N', 'azot', 27, 14, 3),
];

// Katlı oranlar: (X simgesi, X adı, Y simgesi, Y adı, I. bileşik, II. bileşik,
// x1, y1, x2, y2, 2·A(X), 2·A(Y)); atom kütleleri iki katıyla tutulur.
const _katliOranlar = [
  ('C', 'karbon', 'O', 'oksijen', 'CO', 'CO₂', 1, 1, 1, 2, 24, 32),
  ('C', 'karbon', 'O', 'oksijen', 'CO₂', 'CO', 1, 2, 1, 1, 24, 32),
  ('N', 'azot', 'O', 'oksijen', 'N₂O', 'NO', 2, 1, 1, 1, 28, 32),
  ('N', 'azot', 'O', 'oksijen', 'NO', 'NO₂', 1, 1, 1, 2, 28, 32),
  ('N', 'azot', 'O', 'oksijen', 'N₂O', 'NO₂', 2, 1, 1, 2, 28, 32),
  ('N', 'azot', 'O', 'oksijen', 'N₂O₃', 'N₂O₅', 2, 3, 2, 5, 28, 32),
  ('N', 'azot', 'O', 'oksijen', 'NO', 'N₂O₃', 1, 1, 2, 3, 28, 32),
  ('N', 'azot', 'O', 'oksijen', 'NO₂', 'N₂O₅', 1, 2, 2, 5, 28, 32),
  ('N', 'azot', 'O', 'oksijen', 'N₂O₅', 'N₂O', 2, 5, 2, 1, 28, 32),
  ('Cu', 'bakır', 'Cl', 'klor', 'CuCl', 'CuCl₂', 1, 1, 1, 2, 128, 71),
  ('Fe', 'demir', 'Cl', 'klor', 'FeCl₃', 'FeCl₂', 1, 3, 1, 2, 112, 71),
  ('Fe', 'demir', 'O', 'oksijen', 'FeO', 'Fe₂O₃', 1, 1, 2, 3, 112, 32),
  ('Fe', 'demir', 'O', 'oksijen', 'Fe₂O₃', 'FeO', 2, 3, 1, 1, 112, 32),
  ('Cu', 'bakır', 'O', 'oksijen', 'Cu₂O', 'CuO', 2, 1, 1, 1, 128, 32),
  ('Cu', 'bakır', 'O', 'oksijen', 'CuO', 'Cu₂O', 1, 1, 2, 1, 128, 32),
  ('H', 'hidrojen', 'O', 'oksijen', 'H₂O', 'H₂O₂', 2, 1, 2, 2, 2, 32),
  ('H', 'hidrojen', 'O', 'oksijen', 'H₂O₂', 'H₂O', 2, 2, 2, 1, 2, 32),
  ('P', 'fosfor', 'Cl', 'klor', 'PCl₃', 'PCl₅', 1, 3, 1, 5, 62, 71),
  ('Fe', 'demir', 'Cl', 'klor', 'FeCl₂', 'FeCl₃', 1, 2, 1, 3, 112, 71),
  ('C', 'karbon', 'H', 'hidrojen', 'CH₄', 'C₂H₆', 1, 4, 2, 6, 24, 2),
  ('C', 'karbon', 'H', 'hidrojen', 'C₂H₆', 'C₂H₄', 2, 6, 2, 4, 24, 2),
  ('C', 'karbon', 'H', 'hidrojen', 'C₂H₄', 'C₂H₂', 2, 4, 2, 2, 24, 2),
  ('C', 'karbon', 'H', 'hidrojen', 'C₂H₂', 'CH₄', 2, 2, 1, 4, 24, 2),
  ('Sn', 'kalay', 'Cl', 'klor', 'SnCl₂', 'SnCl₄', 1, 2, 1, 4, 238, 71),
  ('Pb', 'kurşun', 'O', 'oksijen', 'PbO', 'PbO₂', 1, 1, 1, 2, 414, 32),
];

/// Sabit oran sorularında artan kütle (onda bir gram). İki düzeyin aday
/// takımları ayrıktır; yanıtın kökteki bir sayıyla ya da tipik bir yanlış
/// yöntemin sonucuyla çakışmadığı ilk aday seçilir.
int _artanKutle(int p, int q, int u, int b, int duzey, bool yFazla) {
  final k = (b + 2) * u;
  final adaylar = duzey == 0
      ? const [2, 3, 4, 5, 6]
      : const [7, 9, 11, 13, 15, 8, 10, 12, 14];
  for (var r = 0; r < adaylar.length; r++) {
    final e = adaylar[(b % 5 + r) % adaylar.length] * u;
    if (_sabitOranTemiz(p, q, k, e, yFazla)) return e;
  }
  throw StateError('Uygun artan kütle yok: $p/$q, $b');
}

bool _sabitOranTemiz(int p, int q, int k, int e, bool yFazla) {
  final xTep = p * k, yTep = q * k;
  final mx = xTep + (yFazla ? 0 : e), my = yTep + (yFazla ? e : 0);
  final top = xTep + yTep;
  final tersX = my * q / p, tersY = mx * p / q;
  final tersArtan = tersX <= mx ? mx - tersX : my - tersY;
  final tersToplam = tersX <= mx ? my + tersX : mx + tersY;
  final yanlisToplam = yFazla ? my * (p + q) / q : mx * (p + q) / p;
  bool ayni(num x, num y) => (x - y).abs() < 1e-9;
  final artanHata = <num>[
    (mx - my).abs(),
    yFazla ? yTep : xTep,
    yFazla ? xTep : yTep,
    top,
    mx,
    my,
    tersArtan,
  ];
  final topHata = <num>[
    mx,
    my,
    2 * (mx < my ? mx : my),
    tersToplam,
    yanlisToplam,
  ];
  return !artanHata.any((h) => ayni(h, e)) && !topHata.any((h) => ayni(h, top));
}

AdvancedItem _katliOran(int a, int b, int w) {
  final (xs, xa, ys, ya, f1, f2, x1, y1, x2, y2, ax2, ay2) = _katliOranlar[a];
  // Miktarlar onda bir mol birimiyle; kütleler (yarım atom kütlesiyle) yüzde
  // bir gram birimine çevrilir.
  // t2, yanıt kökteki kütlelerden biriyle çakışmayacak biçimde seçilir;
  // ikinci bileşikteki X kütlesi 300 gramı aşmaz.
  final t1 = 1 + b % 5;
  final uygun = [
    for (var t = 1; x2 * ax2 * t <= 6000; t++)
      if (y2 * ay2 * t != x1 * ax2 * t1 &&
          y2 * ay2 * t != y1 * ay2 * t1 &&
          y2 * ay2 * t != x2 * ax2 * t)
        t,
  ];
  final t2 = uygun[b ~/ 5 + 4 * w];
  final m1x = x1 * ax2 * t1 / 20, m1y = y1 * ay2 * t1 / 20;
  final m2x = x2 * ax2 * t2 / 20, cevap = y2 * ay2 * t2 / 20;
  final r = m1y / m1x, kat = y2 * x1 / (x2 * y1);
  final oranYazi = kesir(y1 * ay2, x1 * ax2);
  final katYazi = kesir(y2 * x1, x2 * y1);
  return _say(
    '${_bas(xa)} ve $ya elementlerinden oluşan $f1 bileşiğinde ${_t(m1x)} g '
        '$xa ile ${_t(m1y)} g $ya birleşmektedir. Aynı iki elementten oluşan '
        '$f2 bileşiğinde ${_t(m2x)} g $xa ile kaç gram $ya birleşir?',
    cevap,
    [m2x * r, m2x * r / kat, m2x * r * y2 / y1, m2x * r * x1 / x2, cevap * 2],
    '$f1 bileşiğinde m($ys)/m($xs) = ${_t(m1y)}/${_t(m1x)} = $oranYazi olur. '
        'Bir $xs atomuna düşen $ys atomu sayısı $f1 bileşiğinde '
        '${kesir(y1, x1)}, $f2 bileşiğinde ${kesir(y2, x2)} olduğundan $f2 '
        'bileşiğinde aynı kütlede $xa ile $katYazi katı $ya birleşir: '
        '${_t(m2x)}·$oranYazi·$katYazi = ${_t(cevap)} g.',
    birim: 'g',
  );
}

final _f01 = lmAile(
  'km_temel_kanunlar',
  'Kütlenin korunumu, sabit ve katlı oranlar yasası',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    if (c >= 7) return _katliOran(a, b, c - 7);
    final (f, ad, xs, xa, ys, ya, p, q, u) = _sabitOranlar[a];
    final artanSorusu = c < 4;
    final j = artanSorusu ? c : c - 4;
    final yFazla = j.isOdd;
    final duzey = j ~/ 2;
    // Kütleler onda bir gram birimiyle tamsayı tutulur.
    final k = (b + 2) * u;
    final e = _artanKutle(p, q, u, b, duzey, yFazla);
    final xTep = p * k, yTep = q * k;
    final mx = xTep + (yFazla ? 0 : e), my = yTep + (yFazla ? e : 0);
    final top = xTep + yTep;
    String g(int onda) => _t(onda / 10);
    // Ters oranla çözme hatası: m(X)/m(Y) = q/p alınır.
    final tersX = my * q / p, tersY = mx * p / q;
    final tersArtan = tersX <= mx ? mx - tersX : my - tersY;
    final tersToplam = tersX <= mx ? my + tersX : mx + tersY;
    // Fazla olan elementi sınırlayıcı sanma hatası.
    final yanlisToplam = yFazla ? my * (p + q) / q : mx * (p + q) / p;
    final giris =
        '${_bas(xa)} ve $ya elementlerinden $ad ($f) oluşurken elementlerin '
        'kütlece birleşme oranı m($xs)/m($ys) = ${kesir(p, q)} olarak '
        'bilinmektedir. ${g(mx)} g $xa ile ${g(my)} g $ya tam verimle '
        'tepkimeye girdiğinde';
    final birlesme = yFazla
        ? '${g(mx)} g $xa ile ${g(mx)}·$q/$p = ${g(yTep)} g $ya birleşir.'
        : '${g(my)} g $ya ile ${g(my)}·$p/$q = ${g(xTep)} g $xa birleşir.';
    if (artanSorusu) {
      return _say(
        '$giris artan maddenin kütlesi kaç gram olur?',
        e / 10,
        [
          (mx - my).abs() / 10,
          tersArtan / 10,
          (yFazla ? yTep : xTep) / 10,
          top / 10,
          (yFazla ? my : mx) / 10,
        ],
        '$birlesme ${_bas(yFazla ? ya : xa)} elementinden '
            '${g(yFazla ? my : mx)} − ${g(yFazla ? yTep : xTep)} = ${g(e)} g '
            'artar.',
        birim: 'g',
      );
    }
    return _say(
      '$giris en çok kaç gram $f oluşur?',
      top / 10,
      [
        (mx + my) / 10,
        tersToplam / 10,
        yanlisToplam / 10,
        2 * (yFazla ? mx : my) / 10,
      ],
      '$birlesme Kütlenin korunumuna göre ${g(xTep)} + ${g(yTep)} = ${g(top)} g '
          '$f oluşur; ${yFazla ? ya : xa} elementinden ${g(e)} g artar.',
      birim: 'g',
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ───────────────────────────── 2 · Periyodik özellikler ──────────────────────

// Z → (periyot, A grubu, birinci iyonlaşma enerjisi kJ/mol).
const _elementBilgi = <int, (int, int, int)>{
  2: (1, 8, 2372),
  3: (2, 1, 520),
  4: (2, 2, 899),
  5: (2, 3, 801),
  6: (2, 4, 1086),
  7: (2, 5, 1402),
  8: (2, 6, 1314),
  9: (2, 7, 1681),
  10: (2, 8, 2081),
  11: (3, 1, 496),
  12: (3, 2, 738),
  13: (3, 3, 578),
  14: (3, 4, 786),
  15: (3, 5, 1012),
  16: (3, 6, 1000),
  17: (3, 7, 1251),
  18: (3, 8, 1521),
  19: (4, 1, 419),
  20: (4, 2, 590),
  33: (4, 5, 947),
  34: (4, 6, 941),
  35: (4, 7, 1140),
  36: (4, 8, 1351),
  37: (5, 1, 403),
  38: (5, 2, 549),
  51: (5, 5, 834),
  52: (5, 6, 869),
  53: (5, 7, 1008),
  54: (5, 8, 1170),
  55: (6, 1, 376),
  56: (6, 2, 503),
};

const _periyotKumeleri = [
  [3, 4, 5, 6, 7, 8, 9, 10],
  [11, 12, 13, 14, 15, 16, 17, 18],
];

const _grupKumeleri = [
  [3, 11, 19, 37, 55],
  [4, 12, 20, 38, 56],
  [7, 15, 33, 51],
  [8, 16, 34, 52],
  [9, 17, 35, 53],
  [2, 10, 18, 36, 54],
];

// Elektronegatiflikleri çok yakın olduğu için birlikte sorulmayan çiftler
// (Pauling: K 0,82 – Rb 0,82; S 2,58 – Se 2,55; P 2,19 – As 2,18).
const _yakinEn = [
  [19, 37],
  [16, 34],
  [15, 33],
];

const _ozellikAdi = [
  'Atom yarıçapı',
  'Birinci iyonlaşma enerjisi',
  'Elektronegatiflik',
  'Metalik özellik',
];

const _ozellikTamlama = [
  'atom yarıçaplarının',
  'birinci iyonlaşma enerjilerinin',
  'elektronegatifliklerinin',
  'metalik özelliklerinin',
];

const _harfler = ['X', 'Y', 'Z', 'T'];

bool _ayniPeriyot(List<int> z) =>
    z.every((e) => _elementBilgi[e]!.$1 == _elementBilgi[z.first]!.$1);

/// Özelliğin karşılaştırma değeri: büyük olan özelliği büyük olandır.
num _ozellikDegeri(int z, int ozellik, bool periyot) => switch (ozellik) {
  0 || 3 => periyot ? -z : z,
  1 => _elementBilgi[z]!.$3,
  _ => periyot ? z : -z,
};

bool _ozellikGecerli(List<int> z, int ozellik) {
  if (z.any((e) => _elementBilgi[e]!.$2 == 8)) return ozellik == 1;
  if (ozellik == 2 && !_ayniPeriyot(z)) {
    for (final c in _yakinEn) {
      if (z.contains(c[0]) && z.contains(c[1])) return false;
    }
  }
  return true;
}

/// Sıralama soruları: (harf sırasıyla atom numaraları, özellik).
final _periyodikSiralar = () {
  final hepsi = <(List<int>, int)>[];
  for (final n in const [3, 4]) {
    final kumeler = [
      for (final p in _periyotKumeleri) ..._secimler(p, n),
      for (final g in _grupKumeleri)
        if (g.length >= n) ..._secimler(g, n),
    ];
    final dizilim = n == 3 ? _dizilim3 : _dizilim4;
    var sayac = 0;
    for (final k in kumeler) {
      for (var o = 0; o < 4; o++) {
        if (!_ozellikGecerli(k, o)) continue;
        final kac = n == 3 ? 2 : 3;
        for (var r = 0; r < kac; r++) {
          final d =
              dizilim[(sayac * 7 + r * dizilim.length ~/ kac) % dizilim.length];
          hepsi.add(([for (final j in d) k[j]], o));
        }
        sayac++;
      }
    }
  }
  return hepsi;
}();

String _grupYazi(int z) {
  final (p, g, _) = _elementBilgi[z]!;
  return '$p. periyot ${g}A grubu';
}

/// Periyotta iyonlaşma enerjisindeki 2A–3A ve 5A–6A istisnalarından kümede
/// bulunanlar.
String _istisna(List<int> gruplar) {
  final a = gruplar.contains(2) && gruplar.contains(3);
  final b = gruplar.contains(5) && gruplar.contains(6);
  if (!a && !b) return '';
  final parca = [
    if (a) '2A grubundaki element 3A grubundakinden',
    if (b) '5A grubundaki element 6A grubundakinden',
  ];
  return '; ancak ${parca.join(', ')} daha büyük iyonlaşma enerjisine sahiptir';
}

String _egilim(int ozellik, bool periyot, List<int> z) {
  final gruplar = [for (final e in z) _elementBilgi[e]!.$2];
  return switch ((ozellik, periyot)) {
    (0, true) => 'Aynı periyotta soldan sağa atom yarıçapı azalır',
    (0, false) => 'Aynı grupta yukarıdan aşağıya atom yarıçapı artar',
    (1, true) =>
      'Aynı periyotta soldan sağa iyonlaşma enerjisi genel olarak artar'
          '${_istisna(gruplar)}',
    (1, false) => 'Aynı grupta yukarıdan aşağıya iyonlaşma enerjisi azalır',
    (2, true) => 'Aynı periyotta soldan sağa elektronegatiflik artar',
    (2, false) => 'Aynı grupta yukarıdan aşağıya elektronegatiflik azalır',
    (_, true) => 'Aynı periyotta soldan sağa metalik özellik azalır',
    (_, false) => 'Aynı grupta yukarıdan aşağıya metalik özellik artar',
  };
}

String _virgulVe(List<String> x) => x.length == 1
    ? x.first
    : '${x.sublist(0, x.length - 1).join(', ')} ve ${x.last}';

AdvancedItem _periyodikSira(int i) {
  final (z, o) = _periyodikSiralar[i * _periyodikSiralar.length ~/ 2000];
  final n = z.length;
  final periyot = _ayniPeriyot(z);
  final harf = _harfler.sublist(0, n);
  final sira = [for (var j = 0; j < n; j++) j]
    ..sort(
      (x, y) => _ozellikDegeri(
        z[y],
        o,
        periyot,
      ).compareTo(_ozellikDegeri(z[x], o, periyot)),
    );
  String yaz(List<int> s) => [for (final j in s) harf[j]].join(' > ');
  final zArtan = [for (var j = 0; j < n; j++) j]
    ..sort((x, y) => z[x].compareTo(z[y]));
  final adaylar = <String>[
    yaz(sira.reversed.toList()),
    yaz(zArtan),
    yaz(zArtan.reversed.toList()),
    for (var r = 0; r + 1 < n; r++)
      yaz([...sira]..setAll(r, [sira[r + 1], sira[r]])),
  ];
  final yer = [
    for (var j = 0; j < n; j++) '${harf[j]} (${z[j]}): ${_grupYazi(z[j])}',
  ];
  return secenekli(
    'Aynı ${periyot ? 'periyotta' : 'grupta'} bulunan ${_virgulVe(harf)} '
        'elementlerinin atom numaraları sırasıyla ${_virgulVe([for (final e in z) '$e'])} '
        'olarak verilmiştir. Buna göre bu elementlerin ${_ozellikTamlama[o]} '
        'büyükten küçüğe doğru sıralanışı hangi seçenekte doğru verilmiştir?',
    yaz(sira),
    adaylar,
    '${yer.join('; ')}. ${_egilim(o, periyot, z)}: ${yaz(sira)}.',
  );
}

// Yargı soruları için üçlü kümeler (soy gazlar dışında).
final _yargiKumeleri = [
  for (final p in _periyotKumeleri) ..._secimler(p.sublist(0, 7), 3),
  for (final g in _grupKumeleri.sublist(0, 5)) ..._secimler(g, 3),
];

// (özellik, harf i, harf j) karşılaştırmaları; geçerli olanlar kümeye göre.
List<(int, int, int)> _karsilastirmalar(List<int> z) => [
  for (var o = 0; o < 4; o++)
    for (var x = 0; x < 3; x++)
      for (var y = x + 1; y < 3; y++)
        if (_ozellikGecerli([z[x], z[y]], o)) (o, x, y),
];

final _yargiOnbellek = <int, List<(int, int, int, int, int, int, int)>>{};

/// Kümenin bütün yargı üçlüleri: (k1, k2, k3, yön bitleri, maske, …).
List<(int, int, int, int, int, int, int)> _yargiUcluleri(int s) =>
    _yargiOnbellek[s] ??= () {
      final z = _yargiKumeleri[s];
      final periyot = _ayniPeriyot(z);
      final k = _karsilastirmalar(z);
      final out = <(int, int, int, int, int, int, int)>[];
      for (var p = 0; p < k.length; p++) {
        for (var q = p + 1; q < k.length; q++) {
          for (var r = q + 1; r < k.length; r++) {
            for (var yon = 0; yon < 8; yon++) {
              var maske = 0;
              for (final (t, idx) in [(0, p), (1, q), (2, r)]) {
                final (o, x, y) = k[idx];
                final ters = (yon >> t) & 1 == 1;
                final sol = ters ? y : x, sag = ters ? x : y;
                if (_ozellikDegeri(z[sol], o, periyot) >
                    _ozellikDegeri(z[sag], o, periyot)) {
                  maske |= 1 << t;
                }
              }
              if (maske != 0) out.add((p, q, r, yon, maske, 0, 0));
            }
          }
        }
      }
      return out;
    }();

AdvancedItem _periyodikYargi(int j) {
  final s = j % _yargiKumeleri.length, k = j ~/ _yargiKumeleri.length;
  final taban = _yargiKumeleri[s];
  final d = _dizilim3[(s + k) % 6];
  final z = [for (final x in d) taban[x]];
  final periyot = _ayniPeriyot(z);
  final liste = _yargiUcluleri(s);
  // Kümenin üçlüleri k sırasına göre farklı aralıklarla taranır; asal adım
  // aynı küme içinde yinelemeyi önler.
  final (p, q, r, yon, maske, _, _) = liste[(k * 157 + s * 31) % liste.length];
  final kars = _karsilastirmalar(taban);
  // Karşılaştırmalar taban kümenin harf sırasına göre kurulmuştur; dizilimle
  // yeni harflere taşınır.
  final yeniHarf = List<int>.filled(3, 0);
  for (var t = 0; t < 3; t++) {
    yeniHarf[d[t]] = t;
  }
  final yargilar = <String>[], cozum = <String>[];
  for (final (t, idx) in [(0, p), (1, q), (2, r)]) {
    final (o, x, y) = kars[idx];
    final ters = (yon >> t) & 1 == 1;
    final sol = yeniHarf[ters ? y : x], sag = yeniHarf[ters ? x : y];
    yargilar.add('${_ozellikAdi[o]}: ${_harfler[sol]} > ${_harfler[sag]}');
    final dogru = (maske >> t) & 1 == 1;
    cozum.add(
      '${_romaRakam[t]} ${dogru ? 'doğru' : 'yanlış'}: '
      '${_ozellikAdi[o].toLowerCase()} için '
      '${dogru ? '${_harfler[sol]} > ${_harfler[sag]}' : '${_harfler[sag]} > ${_harfler[sol]}'}',
    );
  }
  final yer = [
    for (var t = 0; t < 3; t++) '${_harfler[t]} (${z[t]}): ${_grupYazi(z[t])}',
  ];
  return _hangileri(
    'Atom numaraları sırasıyla ${z[0]}, ${z[1]} ve ${z[2]} olan X, Y ve Z '
        'elementleri aynı ${periyot ? 'periyotta' : 'grupta'} bulunmaktadır. Bu '
        'elementlerle ilgili\n${_uc(yargilar)}\nyargılarından hangileri '
        'doğrudur?',
    maske,
    '${yer.join('; ')}. ${cozum.join('; ')}.',
    j,
  );
}

final _f02 = lmSirali(
  'km_periyodik',
  'Periyodik özelliklerin karşılaştırılması',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.analiz,
  (i) => i < 2000 ? _periyodikSira(i) : _periyodikYargi(i - 2000),
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ─────────────────────── 3 · İyonik bileşiklerin formülü ve adı ───────────────

// Katyonlar: (simge, yük, ad, çok atomlu mu, öteki yaygın yük; 0 ise sabit
// değerlikli metal).
const _katyonlar = <String, (String, int, String, bool, int)>{
  'Li': ('Li', 1, 'lityum', false, 0),
  'Na': ('Na', 1, 'sodyum', false, 0),
  'K': ('K', 1, 'potasyum', false, 0),
  'NH4': ('NH₄', 1, 'amonyum', true, 0),
  'Ag': ('Ag', 1, 'gümüş', false, 0),
  'Mg': ('Mg', 2, 'magnezyum', false, 0),
  'Ca': ('Ca', 2, 'kalsiyum', false, 0),
  'Sr': ('Sr', 2, 'stronsiyum', false, 0),
  'Ba': ('Ba', 2, 'baryum', false, 0),
  'Zn': ('Zn', 2, 'çinko', false, 0),
  'Al': ('Al', 3, 'alüminyum', false, 0),
  'Fe2': ('Fe', 2, 'demir', false, 3),
  'Fe3': ('Fe', 3, 'demir', false, 2),
  'Cu1': ('Cu', 1, 'bakır', false, 2),
  'Cu2': ('Cu', 2, 'bakır', false, 1),
  'Pb2': ('Pb', 2, 'kurşun', false, 4),
  'Pb4': ('Pb', 4, 'kurşun', false, 2),
  'Sn2': ('Sn', 2, 'kalay', false, 4),
  'Sn4': ('Sn', 4, 'kalay', false, 2),
  'Cr3': ('Cr', 3, 'krom', false, 2),
  'Co2': ('Co', 2, 'kobalt', false, 3),
  'Ni2': ('Ni', 2, 'nikel', false, 3),
  'Hg2': ('Hg', 2, 'cıva', false, 1),
  'Mn2': ('Mn', 2, 'mangan', false, 4),
  'Mn4': ('Mn', 4, 'mangan', false, 2),
};

// Anyonlar: (formül, yük büyüklüğü, ad, çok atomlu mu, karıştırılan anyonlar).
const _anyonlar = <String, (String, int, String, bool, List<String>)>{
  'F': ('F', 1, 'florür', false, []),
  'Cl': ('Cl', 1, 'klorür', false, ['ClO']),
  'Br': ('Br', 1, 'bromür', false, []),
  'I': ('I', 1, 'iyodür', false, []),
  'O': ('O', 2, 'oksit', false, ['O2', 'OH']),
  'S': ('S', 2, 'sülfür', false, ['SO4', 'SO3']),
  'N3': ('N', 3, 'nitrür', false, ['NO3']),
  'H': ('H', 1, 'hidrür', false, ['OH']),
  'OH': ('OH', 1, 'hidroksit', true, ['O']),
  'NO3': ('NO₃', 1, 'nitrat', true, ['NO2']),
  'NO2': ('NO₂', 1, 'nitrit', true, ['NO3']),
  'SO4': ('SO₄', 2, 'sülfat', true, ['SO3', 'S']),
  'SO3': ('SO₃', 2, 'sülfit', true, ['SO4', 'S']),
  'CO3': ('CO₃', 2, 'karbonat', true, ['HCO3']),
  'HCO3': ('HCO₃', 1, 'hidrojen karbonat', true, ['CO3']),
  'PO4': ('PO₄', 3, 'fosfat', true, []),
  'MnO4': ('MnO₄', 1, 'permanganat', true, []),
  'ClO': ('ClO', 1, 'hipoklorit', true, ['Cl']),
  'O2': ('O₂', 2, 'peroksit', true, ['O']),
  'HSO4': ('HSO₄', 1, 'hidrojen sülfat', true, ['SO4']),
};

// Ders kitaplarında geçen gerçek iyonik bileşikler: (katyon, anyonlar).
const _iyonikCiftler = [
  ('Li', ['F', 'Cl', 'Br', 'O', 'OH', 'CO3', 'N3', 'NO3', 'H']),
  (
    'Na',
    [
      'F', 'Cl', 'Br', 'I', 'O', 'S', 'OH', 'NO3', 'NO2', 'SO4', 'SO3', //
      'CO3', 'HCO3', 'PO4', 'ClO', 'O2', 'HSO4', 'H',
    ],
  ),
  (
    'K',
    [
      'F', 'Cl', 'Br', 'I', 'O', 'S', 'OH', 'NO3', 'NO2', 'SO4', 'CO3', //
      'HCO3', 'PO4', 'MnO4', 'HSO4',
    ],
  ),
  ('NH4', ['Cl', 'Br', 'I', 'F', 'SO4', 'PO4', 'CO3', 'HCO3']),
  ('Ag', ['F', 'Cl', 'Br', 'I', 'NO3', 'O', 'S', 'SO4', 'CO3', 'PO4']),
  (
    'Mg',
    ['F', 'Cl', 'Br', 'I', 'O', 'S', 'OH', 'NO3', 'SO4', 'CO3', 'PO4', 'N3'],
  ),
  (
    'Ca',
    [
      'F', 'Cl', 'Br', 'I', 'O', 'S', 'OH', 'NO3', 'SO4', 'CO3', 'PO4', //
      'N3', 'H', 'ClO',
    ],
  ),
  ('Sr', ['Cl', 'OH', 'NO3', 'SO4', 'CO3']),
  ('Ba', ['F', 'Cl', 'O', 'OH', 'NO3', 'SO4', 'CO3', 'O2']),
  ('Zn', ['Cl', 'Br', 'O', 'S', 'OH', 'NO3', 'SO4', 'CO3']),
  ('Al', ['F', 'Cl', 'Br', 'I', 'O', 'S', 'OH', 'NO3', 'SO4', 'PO4', 'N3']),
  ('Fe2', ['Cl', 'Br', 'I', 'O', 'S', 'OH', 'SO4', 'CO3']),
  ('Fe3', ['F', 'Cl', 'Br', 'O', 'OH', 'NO3', 'SO4', 'PO4']),
  ('Cu1', ['Cl', 'Br', 'I', 'O', 'S']),
  ('Cu2', ['F', 'Cl', 'Br', 'O', 'S', 'OH', 'NO3', 'SO4']),
  ('Pb2', ['Cl', 'Br', 'I', 'O', 'S', 'NO3', 'SO4', 'CO3']),
  ('Pb4', ['O']),
  ('Sn2', ['F', 'Cl', 'O', 'S']),
  ('Sn4', ['Cl', 'O', 'S']),
  ('Cr3', ['Cl', 'O', 'OH', 'NO3', 'SO4']),
  ('Co2', ['Cl', 'O', 'NO3', 'SO4']),
  ('Ni2', ['Cl', 'O', 'OH', 'NO3', 'SO4']),
  ('Hg2', ['Cl', 'I', 'O', 'S', 'NO3']),
  ('Mn2', ['Cl', 'SO4']),
  ('Mn4', ['O']),
];

final _iyonikler = [
  for (final (k, liste) in _iyonikCiftler)
    for (final a in liste) (k, a),
];

const _onekler = [
  '', 'mono', 'di', 'tri', 'tetra', 'penta', 'hekza', 'hepta', 'okta', //
  'nona', 'deka',
];

/// Ön ek + ad; “mono + oksit” birleşince “monoksit” olur.
String _onekli(int n, String ad) =>
    n == 1 && ad.startsWith('o') ? 'mon$ad' : '${_onekler[n]}$ad';

String _parca(String s, bool cok, int n) =>
    n == 1 ? s : (cok ? '($s)${_alt(n)}' : '$s${_alt(n)}');

/// Yükler dengelenerek iyonik formül.
String _iyonFormulu(
  String cs,
  bool ccok,
  int cq,
  String as_,
  bool acok,
  int aq,
) {
  final g = cq.gcd(aq);
  return _parca(cs, ccok, aq ~/ g) + _parca(as_, acok, cq ~/ g);
}

String _katyonAdi(String k, [int? yuk]) {
  final (_, q, ad, _, diger) = _katyonlar[k]!;
  return diger == 0
      ? ad
      : '$ad(${const ['', 'I', 'II', 'III', 'IV'][yuk ?? q]})';
}

String _iyonikFormul((String, String) x) {
  final (cs, cq, _, ccok, _) = _katyonlar[x.$1]!;
  final (as_, aq, _, acok, _) = _anyonlar[x.$2]!;
  return _iyonFormulu(cs, ccok, cq, as_, acok, aq);
}

String _iyonikAd((String, String) x) =>
    '${_katyonAdi(x.$1)} ${_anyonlar[x.$2]!.$3}';

/// Bileşiğe özgü kesin yanlış adlar (tipik hatalar).
List<String> _yanlisIyonikAdlar((String, String) x) {
  final (_, cq, cad, _, diger) = _katyonlar[x.$1]!;
  final (_, aq, aad, _, karisan) = _anyonlar[x.$2]!;
  final g = cq.gcd(aq), nc = aq ~/ g, na = cq ~/ g;
  final kat = _katyonAdi(x.$1);
  return [
    if (diger != 0) ...['${_katyonAdi(x.$1, diger)} $aad', '$cad $aad'],
    for (final w in karisan) '$kat ${_anyonlar[w]!.$3}',
    '${nc > 1 ? _onekler[nc] : ''}$kat ${_onekli(na, aad)}',
  ];
}

/// Bileşiğe özgü kesin yanlış formüller (tipik hatalar).
List<String> _yanlisIyonikFormuller((String, String) x) {
  final (cs, cq, _, ccok, diger) = _katyonlar[x.$1]!;
  final (as_, aq, _, acok, karisan) = _anyonlar[x.$2]!;
  final g = cq.gcd(aq), nc = aq ~/ g, na = cq ~/ g;
  final dogru = _iyonikFormul(x);
  final out = <String>[
    if (nc != na) _parca(cs, ccok, na) + _parca(as_, acok, nc),
    if (nc != 1 || na != 1) _parca(cs, ccok, 1) + _parca(as_, acok, 1),
    if (diger != 0) _iyonFormulu(cs, ccok, diger, as_, acok, aq),
    for (final w in karisan)
      _iyonFormulu(
        cs,
        ccok,
        cq,
        _anyonlar[w]!.$1,
        _anyonlar[w]!.$4,
        _anyonlar[w]!.$2,
      ),
    _parca(cs, ccok, nc + 1) + _parca(as_, acok, na),
    _parca(cs, ccok, nc) + _parca(as_, acok, na + 1),
  ];
  return [
    for (final f in out)
      if (f != dogru) f,
  ];
}

String _iyonYazi(String x) {
  final (cs, cq, _, _, _) = _katyonlar[x]!;
  return '$cs${_yuk(cq)}';
}

String _anyonYazi(String x) {
  final (as_, aq, _, _, _) = _anyonlar[x]!;
  return '$as_${_yuk(-aq)}';
}

final _f03 = lmSirali(
  'km_iyonik_ad',
  'İyonik bileşiklerin formülü ve adlandırılması',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final u = kombinasyon(_iyonikler, 3, i);
    final d = ucluDizilimler[i % 6];
    final x = [for (final j in d) u[j]];
    final adlar = [for (final e in x) _iyonikAd(e)];
    final formuller = [for (final e in x) _iyonikFormul(e)];
    final aciklama =
        '${[for (var p = 0; p < 3; p++) '${formuller[p]} (${_iyonYazi(x[p].$1)} ve ${_anyonYazi(x[p].$2)}): ${adlar[p]}'].join('; ')}.';
    if (i.isEven) {
      return _uclu(
        '${_uc(formuller)}\nBu iyonik bileşiklerin adları numara sırasıyla hangi '
        'seçenekte doğru verilmiştir?',
        adlar,
        [
          for (var p = 0; p < 3; p++)
            () {
              final y = _yanlisIyonikAdlar(x[p]);
              return _secYanlis(y, i ~/ 2 + p, adlar);
            }(),
        ],
        aciklama,
      );
    }
    return _uclu(
      '${_uc(adlar)}\nAdları verilen bu iyonik bileşiklerin formülleri numara '
      'sırasıyla hangi seçenekte doğru verilmiştir?',
      formuller,
      [
        for (var p = 0; p < 3; p++)
          () {
            final y = _yanlisIyonikFormuller(x[p]);
            return _secYanlis(y, i ~/ 2 + p, formuller);
          }(),
      ],
      aciklama,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ──────────────────── 4 · Moleküler (kovalent) bileşiklerin adı ───────────────

// Birinci element adları ve ikinci element (-ür, -it) adları.
const _ametalAdi = {
  'C': 'karbon',
  'N': 'azot',
  'S': 'kükürt',
  'P': 'fosfor',
  'Si': 'silisyum',
  'Cl': 'klor',
  'Br': 'brom',
  'I': 'iyot',
  'B': 'bor',
  'Xe': 'ksenon',
  'O': 'oksijen',
  'Se': 'selenyum',
};

const _ametalEki = {
  'O': 'oksit',
  'S': 'sülfür',
  'Cl': 'klorür',
  'F': 'florür',
  'Br': 'bromür',
  'I': 'iyodür',
};

// (1. element, sayı, 2. element, sayı)
const _molekuller = [
  ('C', 1, 'O', 1), ('C', 1, 'O', 2), ('C', 1, 'S', 2), ('C', 1, 'Cl', 4), //
  ('C', 1, 'F', 4), ('C', 1, 'Br', 4),
  ('N', 1, 'O', 1), ('N', 1, 'O', 2), ('N', 2, 'O', 1), ('N', 2, 'O', 3),
  ('N', 2, 'O', 4), ('N', 2, 'O', 5), ('N', 1, 'F', 3), ('N', 1, 'Cl', 3),
  ('S', 1, 'O', 2), ('S', 1, 'O', 3), ('S', 1, 'F', 4), ('S', 1, 'F', 6),
  ('S', 1, 'Cl', 2), ('S', 2, 'Cl', 2),
  ('P', 1, 'Cl', 3), ('P', 1, 'Cl', 5), ('P', 1, 'F', 3), ('P', 1, 'F', 5),
  ('P', 1, 'Br', 3), ('P', 2, 'O', 5), ('P', 4, 'O', 10), ('P', 2, 'O', 3),
  ('P', 4, 'O', 6), ('P', 4, 'S', 3),
  ('Si', 1, 'O', 2), ('Si', 1, 'Cl', 4), ('Si', 1, 'F', 4),
  ('Cl', 2, 'O', 1), ('Cl', 1, 'O', 2), ('Cl', 2, 'O', 7),
  ('B', 1, 'F', 3), ('B', 1, 'Cl', 3), ('B', 2, 'O', 3), ('B', 1, 'Br', 3),
  ('Xe', 1, 'F', 2), ('Xe', 1, 'F', 4), ('Xe', 1, 'F', 6), ('Xe', 1, 'O', 3),
  ('I', 1, 'F', 5), ('I', 1, 'F', 7), ('I', 1, 'Cl', 1), ('I', 1, 'Cl', 3),
  ('Br', 1, 'F', 3), ('Br', 1, 'F', 5), ('Br', 1, 'Cl', 1),
  ('O', 1, 'F', 2),
  ('Se', 1, 'O', 2), ('Se', 1, 'F', 6),
];

String _molekulFormul(String e1, int n1, String e2, int n2) =>
    '$e1${n1 == 1 ? '' : _alt(n1)}$e2${n2 == 1 ? '' : _alt(n2)}';

String _molekulAdi(String e1, int n1, String e2, int n2) =>
    '${n1 == 1 ? '' : _onekler[n1]}${_ametalAdi[e1]} ${_onekli(n2, _ametalEki[e2]!)}';

/// Kesin yanlış adlar: ikinci ön ek bir fazla ya da eksik, birinci elemente
/// gereksiz “mono” ya da eksik ön ek, ön ekleri tümden atma.
List<String> _yanlisMolekulAdlari((String, int, String, int) m) {
  final (e1, n1, e2, n2) = m;
  final ek = _ametalEki[e2]!, ad1 = _ametalAdi[e1]!;
  final bas = n1 == 1 ? '' : _onekler[n1];
  return [
    if (n2 < 10) '$bas$ad1 ${_onekli(n2 + 1, ek)}',
    if (n2 > 1) '$bas$ad1 ${_onekli(n2 - 1, ek)}',
    n1 == 1 ? 'mono$ad1 ${_onekli(n2, ek)}' : '$ad1 ${_onekli(n2, ek)}',
    '$ad1 $ek',
  ];
}

/// Kesin yanlış formüller: alt simgelerin yer değiştirmesi, ikinci alt simgenin
/// bir fazla ya da eksik yazılması, birinci alt simgenin unutulması.
List<String> _yanlisMolekulFormulleri((String, int, String, int) m) {
  final (e1, n1, e2, n2) = m;
  final dogru = _molekulFormul(e1, n1, e2, n2);
  return [
    for (final f in [
      if (n1 != n2) _molekulFormul(e1, n2, e2, n1),
      _molekulFormul(e1, n1, e2, n2 + 1),
      if (n2 > 1) _molekulFormul(e1, n1, e2, n2 - 1),
      _molekulFormul(e1, n1 == 1 ? 2 : 1, e2, n2),
    ])
      if (f != dogru) f,
  ];
}

final _f04 = lmSirali(
  'km_kovalent_ad',
  'Moleküler bileşiklerin ön eklerle adlandırılması',
  Topic.chemistry,
  Difficulty.easy,
  BloomLevel.uygulama,
  (i) {
    final u = kombinasyon(_molekuller, 3, i);
    final d = ucluDizilimler[i % 6];
    final x = [for (final j in d) u[j]];
    final adlar = [for (final (a, b, c, e) in x) _molekulAdi(a, b, c, e)];
    final formuller = [
      for (final (a, b, c, e) in x) _molekulFormul(a, b, c, e),
    ];
    final aciklama =
        'Moleküler bileşiklerde atom sayıları ön eklerle belirtilir; birinci '
        'elementin sayısı 1 ise ön ek kullanılmaz. '
        '${[for (var p = 0; p < 3; p++) '${formuller[p]}: ${adlar[p]}'].join('; ')}.';
    if (i.isEven) {
      return _uclu(
        '${_uc(formuller)}\nBu moleküler bileşiklerin adları numara sırasıyla '
        'hangi seçenekte doğru verilmiştir?',
        adlar,
        [
          for (var p = 0; p < 3; p++)
            () {
              final y = _yanlisMolekulAdlari(x[p]);
              return _secYanlis(y, i ~/ 2 + p, adlar);
            }(),
        ],
        aciklama,
      );
    }
    return _uclu(
      '${_uc(adlar)}\nAdları verilen bu moleküler bileşiklerin formülleri '
      'numara sırasıyla hangi seçenekte doğru verilmiştir?',
      formuller,
      [
        for (var p = 0; p < 3; p++)
          () {
            final y = _yanlisMolekulFormulleri(x[p]);
            return _secYanlis(y, i ~/ 2 + p, formuller);
          }(),
      ],
      aciklama,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ─────────────────────── 5 · Bağ türü ve Lewis yapısı ────────────────────────

const _iyonikBag = 'iyonik';
const _polarBag = 'polar kovalent';
const _apolarBag = 'apolar kovalent';

// (madde, bağ türü, tipik karıştırılan tür)
const _bagTurleri = [
  ('NaCl', _iyonikBag, _polarBag),
  ('KBr', _iyonikBag, _polarBag),
  ('KCl', _iyonikBag, _polarBag),
  ('NaF', _iyonikBag, _polarBag),
  ('LiF', _iyonikBag, _polarBag),
  ('MgO', _iyonikBag, _polarBag),
  ('CaO', _iyonikBag, _polarBag),
  ('CaF₂', _iyonikBag, _polarBag),
  ('MgCl₂', _iyonikBag, _polarBag),
  ('CaCl₂', _iyonikBag, _polarBag),
  ('Na₂O', _iyonikBag, _polarBag),
  ('K₂O', _iyonikBag, _polarBag),
  ('BaO', _iyonikBag, _polarBag),
  ('Li₂O', _iyonikBag, _polarBag),
  ('NaBr', _iyonikBag, _polarBag),
  ('KI', _iyonikBag, _polarBag),
  ('MgF₂', _iyonikBag, _polarBag),
  ('BaCl₂', _iyonikBag, _polarBag),
  ('CaS', _iyonikBag, _polarBag),
  ('Na₂S', _iyonikBag, _polarBag),
  ('LiCl', _iyonikBag, _polarBag),
  ('KF', _iyonikBag, _polarBag),
  ('HCl', _polarBag, _iyonikBag),
  ('HF', _polarBag, _iyonikBag),
  ('HBr', _polarBag, _iyonikBag),
  ('HI', _polarBag, _apolarBag),
  ('H₂O', _polarBag, _apolarBag),
  ('NH₃', _polarBag, _apolarBag),
  ('H₂S', _polarBag, _apolarBag),
  ('CH₄', _polarBag, _apolarBag),
  ('CO₂', _polarBag, _apolarBag),
  ('CO', _polarBag, _iyonikBag),
  ('CCl₄', _polarBag, _apolarBag),
  ('SO₂', _polarBag, _iyonikBag),
  ('NO', _polarBag, _apolarBag),
  ('CHCl₃', _polarBag, _apolarBag),
  ('BF₃', _polarBag, _apolarBag),
  ('SiCl₄', _polarBag, _apolarBag),
  ('CF₄', _polarBag, _apolarBag),
  ('SO₃', _polarBag, _apolarBag),
  ('NF₃', _polarBag, _iyonikBag),
  ('CH₃Cl', _polarBag, _apolarBag),
  ('H₂', _apolarBag, _polarBag),
  ('N₂', _apolarBag, _polarBag),
  ('O₂', _apolarBag, _polarBag),
  ('F₂', _apolarBag, _polarBag),
  ('Cl₂', _apolarBag, _polarBag),
  ('Br₂', _apolarBag, _polarBag),
  ('I₂', _apolarBag, _iyonikBag),
  ('P₄', _apolarBag, _polarBag),
  ('S₈', _apolarBag, _polarBag),
];

// Molekülü apolar olduğu hâlde bağları polar olanlar.
const _apolarMolekul = {'CH₄', 'CO₂', 'CCl₄', 'BF₃', 'SiCl₄', 'CF₄', 'SO₃'};

String _bagNedeni(String f, String tur) => switch (tur) {
  _iyonikBag => 'metal ile ametal atomları arasında',
  _polarBag =>
    'farklı ametal atomları arasında${_apolarMolekul.contains(f) ? '; molekül apolar olsa da bağlar polardır' : ''}',
  _ => 'aynı cins ametal atomları arasında',
};

// Lewis yapısı: (molekül, bağ yapan elektron çifti, ortaklanmamış elektron
// çifti, merkez atomdaki ortaklanmamış çift (merkez atom yoksa −1), bağ sayısı
// (çoklu bağ tek sayılırsa)).
const _lewisYapilari = [
  ('H₂O', 2, 2, 2, 2),
  ('NH₃', 3, 1, 1, 3),
  ('CH₄', 4, 0, 0, 4),
  ('HF', 1, 3, -1, 1),
  ('HCl', 1, 3, -1, 1),
  ('HBr', 1, 3, -1, 1),
  ('F₂', 1, 6, -1, 1),
  ('Cl₂', 1, 6, -1, 1),
  ('Br₂', 1, 6, -1, 1),
  ('N₂', 3, 2, -1, 1),
  ('O₂', 2, 4, -1, 1),
  ('CO₂', 4, 4, 0, 2),
  ('CO', 3, 2, -1, 1),
  ('CCl₄', 4, 12, 0, 4),
  ('PCl₃', 3, 10, 1, 3),
  ('NF₃', 3, 10, 1, 3),
  ('OF₂', 2, 8, 2, 2),
  ('H₂S', 2, 2, 2, 2),
  ('PH₃', 3, 1, 1, 3),
  ('SiH₄', 4, 0, 0, 4),
  ('SiCl₄', 4, 12, 0, 4),
  ('H₂O₂', 3, 4, -1, 3),
  ('C₂H₂', 5, 0, -1, 3),
  ('C₂H₄', 6, 0, -1, 5),
  ('C₂H₆', 7, 0, -1, 7),
  ('CH₂O', 4, 2, 0, 3),
  ('CH₃OH', 5, 2, -1, 5),
  ('CHCl₃', 4, 9, 0, 4),
  ('CH₂Cl₂', 4, 6, 0, 4),
  ('CH₃Cl', 4, 3, 0, 4),
  ('HOCl', 2, 5, 2, 2),
  ('CS₂', 4, 4, 0, 2),
  ('CH₃NH₂', 6, 1, -1, 6),
  ('HCOOH', 5, 4, -1, 4),
  ('C₂H₅OH', 8, 2, -1, 8),
  ('CF₄', 4, 12, 0, 4),
  ('PF₃', 3, 10, 1, 3),
  ('SiF₄', 4, 12, 0, 4),
];

final _f05 = lmSirali(
  'km_bag_turu',
  'Kimyasal bağ türü ve Lewis yapısındaki elektron çiftleri',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final d = ucluDizilimler[i % 6];
    if (i % 3 == 0) {
      final u = kombinasyon(_bagTurleri, 3, i);
      final x = [for (final j in d) u[j]];
      return _uclu(
        '${_uc([for (final e in x) e.$1])}\nBu maddelerin yapısındaki kimyasal '
            'bağların türü numara sırasıyla hangi seçenekte doğru verilmiştir?',
        [for (final e in x) e.$2],
        [
          for (var p = 0; p < 3; p++)
            x[p].$2 == _polarBag && !_apolarMolekul.contains(x[p].$1)
                ? ((i ~/ 3 + p).isEven ? _iyonikBag : _apolarBag)
                : x[p].$3,
        ],
        '${[for (final e in x) '${e.$1}: ${e.$2} (${_bagNedeni(e.$1, e.$2)})'].join('; ')}.',
      );
    }
    final ortaklanmamis = i % 3 == 1;
    final u = kombinasyon(_lewisYapilari, 3, i);
    final x = [for (final j in d) u[j]];
    List<int> hatalar((String, int, int, int, int) m) {
      final (_, bag, yalniz, merkez, tekli) = m;
      final dogru = ortaklanmamis ? yalniz : bag;
      final aday = ortaklanmamis
          ? [if (merkez >= 0) merkez, 2 * yalniz, bag, yalniz + 2]
          : [tekli, 2 * bag, yalniz, bag + 1];
      return [
        for (final h in aday)
          if (h != dogru && h >= 0) h,
      ];
    }

    return _uclu(
      '${_uc([for (final e in x) e.$1])}\nBu moleküllerin Lewis yapılarındaki '
          '${ortaklanmamis ? 'ortaklanmamış (bağ yapmamış)' : 'bağ yapan'} '
          'elektron çifti sayıları numara sırasıyla hangi seçenekte doğru '
          'verilmiştir?',
      [for (final e in x) '${ortaklanmamis ? e.$3 : e.$2}'],
      [
        for (var p = 0; p < 3; p++)
          () {
            final h = hatalar(x[p]);
            return '${h[(i ~/ 3 + p) % h.length]}';
          }(),
      ],
      'Çift bağ iki, üçlü bağ üç bağ yapan elektron çifti sayılır; uç '
          'atomlardaki ortaklanmamış çiftler de hesaba katılır. '
          '${[for (final e in x) '${e.$1}: ${e.$2} bağ yapan, ${e.$3} ortaklanmamış çift'].join('; ')}.',
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ──────────────────────── 6 · Fiziksel ve kimyasal değişim ────────────────────

// (olay, kimyasal mı, gerekçe)
const _degisimler = [
  ('buzun erimesi', false, 'hâl değişimi'),
  ('suyun kaynaması', false, 'hâl değişimi'),
  ('suyun donması', false, 'hâl değişimi'),
  ('şekerin suda çözünmesi', false, 'şeker molekülleri değişmeden dağılır'),
  ('camın kırılması', false, 'yalnız şekil değişir'),
  ('kâğıdın yırtılması', false, 'yalnız şekil değişir'),
  ('naftalinin süblimleşmesi', false, 'hâl değişimi'),
  ('iyodun süblimleşmesi', false, 'hâl değişimi'),
  ('kolonyanın buharlaşması', false, 'hâl değişimi'),
  ('ıslak çamaşırın kuruması', false, 'suyun buharlaşması'),
  ('sabahları çimenlerde çiy oluşması', false, 'su buharının yoğuşması'),
  ('bakır telin bükülmesi', false, 'yalnız şekil değişir'),
  ('altının dövülerek levha hâline getirilmesi', false, 'yalnız şekil değişir'),
  ('mumun erimesi', false, 'hâl değişimi'),
  ('tebeşirin toz hâline getirilmesi', false, 'tanecik boyutu değişir'),
  (
    'ham petrolün damıtılarak bileşenlerine ayrılması',
    false,
    'karışım bileşenlerine ayrılır',
  ),
  ('havanın sıvılaştırılması', false, 'hâl değişimi'),
  (
    'deniz suyundan buharlaştırmayla tuz elde edilmesi',
    false,
    'karışım bileşenlerine ayrılır',
  ),
  ('zeytinyağının soğukta donması', false, 'hâl değişimi'),
  ('çikolatanın sıcakta erimesi', false, 'hâl değişimi'),
  ('kuru buzun süblimleşmesi', false, 'hâl değişimi'),
  ('sis oluşması', false, 'su buharının yoğuşması'),
  ('metal bir çubuğun ısıtılınca uzaması', false, 'genleşme'),
  ('kahve çekirdeklerinin öğütülmesi', false, 'tanecik boyutu değişir'),
  ('kaya tuzunun havanda dövülmesi', false, 'tanecik boyutu değişir'),
  ('lastik bir bandın gerilmesi', false, 'yalnız şekil değişir'),
  ('elmanın dilimlenmesi', false, 'yalnız şekil değişir'),
  ('eritilmiş demirin kalıpta katılaşması', false, 'hâl değişimi'),
  ('alkolün suyla karıştırılması', false, 'karışım oluşur'),
  (
    'demir tozu ile kumun mıknatısla ayrılması',
    false,
    'karışım bileşenlerine ayrılır',
  ),
  ('demirin paslanması', true, 'demir oksit oluşur'),
  ('kâğıdın yanması', true, 'yanma tepkimesi'),
  ('odunun yanması', true, 'yanma tepkimesi'),
  ('sütün ekşimesi', true, 'süt şekeri asite dönüşür'),
  ('sütten yoğurt yapılması', true, 'mayalanma (fermantasyon)'),
  ('hamurun mayalanması', true, 'mayalanma (fermantasyon)'),
  ('yumurtanın pişmesi', true, 'proteinlerin yapısı değişir'),
  ('kesilen elmanın havada kararması', true, 'oksijenle tepkime'),
  ('bitkilerde fotosentez yapılması', true, 'glikoz ve oksijen oluşur'),
  ('besinlerin sindirilmesi', true, 'büyük moleküller parçalanır'),
  ('mumun yanması', true, 'yanma tepkimesi'),
  ('gümüş eşyaların zamanla kararması', true, 'gümüş sülfür oluşur'),
  ('bakır çatıların zamanla yeşillenmesi', true, 'bakır bileşikleri oluşur'),
  ('üzüm suyunun sirkeye dönüşmesi', true, 'mayalanma (fermantasyon)'),
  ('meyvenin çürümesi', true, 'maddeler ayrışır'),
  ('doğal gazın yanması', true, 'yanma tepkimesi'),
  ('kibritin çakılınca tutuşması', true, 'yanma tepkimesi'),
  ('benzinin motorda yanması', true, 'yanma tepkimesi'),
  (
    'suyun elektrolizle hidrojen ve oksijene ayrışması',
    true,
    'yeni maddeler oluşur',
  ),
  ('kireç taşı üzerine sirke dökülünce gaz çıkması', true, 'CO₂ gazı oluşur'),
  ('sirkeye karbonat eklenince köpürmesi', true, 'CO₂ gazı oluşur'),
  ('şekerin ısıtılarak karamelleşmesi', true, 'şeker ayrışır'),
  ('sönmemiş kirecin suyla söndürülmesi', true, 'kalsiyum hidroksit oluşur'),
  ('pilin elektrik akımı üretmesi', true, 'indirgenme-yükseltgenme tepkimesi'),
  ('mide asidinin antiasit ilaçla nötrleşmesi', true, 'nötralleşme tepkimesi'),
  ('hücrelerde glikozun solunumla parçalanması', true, 'CO₂ ve su oluşur'),
  ('magnezyum şeridin yanması', true, 'magnezyum oksit oluşur'),
  (
    'yumurta kabuğunun sirkede gaz çıkararak çözünmesi',
    true,
    'CO₂ gazı oluşur',
  ),
  ('ekmeğin küflenmesi', true, 'maddeler ayrışır'),
  ('etin pişirilmesi', true, 'proteinlerin yapısı değişir'),
];

String _degisimTuru(bool kimyasal) => kimyasal ? 'kimyasal' : 'fiziksel';

final _f06 = lmSirali(
  'km_fiziksel_kimyasal',
  'Fiziksel ve kimyasal değişimlerin ayırt edilmesi',
  Topic.chemistry,
  Difficulty.easy,
  BloomLevel.anlama,
  (i) {
    final u = kombinasyon(_degisimler, 3, i);
    final x = [for (final j in ucluDizilimler[i % 6]) u[j]];
    final aciklama =
        'Kimyasal değişimde yeni madde oluşur; fiziksel değişimde maddenin '
        'kimliği korunur. '
        '${[for (var p = 0; p < 3; p++) '${_romaRakam[p]}: ${_degisimTuru(x[p].$2)} (${x[p].$3})'].join('; ')}.';
    final liste = _uc([for (final e in x) e.$1]);
    if (i % 3 == 0) {
      return _uclu(
        '$liste\nBu olayların türü numara sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
        [for (final e in x) _degisimTuru(e.$2)],
        [for (final e in x) _degisimTuru(!e.$2)],
        aciklama,
      );
    }
    var hedef = i % 3 == 1;
    var maske = 0;
    for (var p = 0; p < 3; p++) {
      if (x[p].$2 == hedef) maske |= 1 << p;
    }
    if (maske == 0) {
      hedef = !hedef;
      maske = 7;
    }
    return _hangileri(
      '$liste\nNumaralanmış olaylardan hangileri ${_degisimTuru(hedef)} '
      'değişimdir?',
      maske,
      aciklama,
      i,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ───────────────────────── 7 · Karışımların ayrılması ─────────────────────────

// Yöntem türleri: (yöntem, yöntemle yapılan ayırmayı anlatan ek, yararlanılan
// özellik, kesin yanlış yöntemler, kesin yanlış özellikler).
const _ayirmaTurleri =
    <String, (String, String, String, List<String>, List<String>)>{
      'huni': (
        'ayırma hunisi',
        'ayırma hunisiyle',
        'özkütle farkı',
        ['süzme', 'mıknatısla ayırma', 'eleme', 'ayrımsal kristallendirme'],
        [
          'manyetik özellik farkı',
          'süblimleşme özelliği',
          'kaynama noktası farkı',
        ],
      ),
      'ayrimsal': (
        'ayrımsal damıtma',
        'ayrımsal damıtmayla',
        'kaynama noktası farkı',
        ['süzme', 'ayırma hunisi', 'mıknatısla ayırma', 'eleme'],
        ['manyetik özellik farkı', 'tanecik boyutu farkı', 'özkütle farkı'],
      ),
      'suzme': (
        'süzme',
        'süzmeyle',
        'tanecik boyutu farkı',
        ['ayırma hunisi', 'mıknatısla ayırma', 'ayrımsal kristallendirme'],
        [
          'manyetik özellik farkı',
          'kaynama noktası farkı',
          'süblimleşme özelliği',
        ],
      ),
      'damitma': (
        'basit damıtma',
        'basit damıtmayla',
        'kaynama noktası farkı',
        ['süzme', 'ayırma hunisi', 'mıknatısla ayırma', 'eleme'],
        ['tanecik boyutu farkı', 'manyetik özellik farkı', 'özkütle farkı'],
      ),
      'buhar': (
        'buharlaştırma',
        'buharlaştırmayla',
        'kaynama noktası farkı',
        ['süzme', 'ayırma hunisi', 'mıknatısla ayırma', 'eleme'],
        ['tanecik boyutu farkı', 'manyetik özellik farkı', 'özkütle farkı'],
      ),
      'miknatis': (
        'mıknatısla ayırma',
        'mıknatısla',
        'manyetik özellik farkı',
        ['ayırma hunisi', 'ayrımsal damıtma', 'ayrımsal kristallendirme'],
        [
          'kaynama noktası farkı',
          'tanecik boyutu farkı',
          'süblimleşme özelliği',
        ],
      ),
      'eleme': (
        'eleme',
        'elemeyle',
        'tanecik boyutu farkı',
        ['ayırma hunisi', 'ayrımsal damıtma', 'mıknatısla ayırma'],
        [
          'kaynama noktası farkı',
          'manyetik özellik farkı',
          'süblimleşme özelliği',
        ],
      ),
      'sublim': (
        'süblimleştirme',
        'ısıtılıp süblimleştirilerek',
        'süblimleşme özelliği',
        ['ayırma hunisi', 'ayrımsal damıtma', 'mıknatısla ayırma'],
        ['manyetik özellik farkı', 'özkütle farkı', 'tanecik boyutu farkı'],
      ),
      'cozme': (
        'suda çözme ve süzme',
        'suda çözülüp süzülerek',
        'çözünürlük farkı',
        [
          'ayırma hunisi',
          'mıknatısla ayırma',
          'ayrımsal damıtma',
          'süblimleştirme',
        ],
        [
          'manyetik özellik farkı',
          'kaynama noktası farkı',
          'süblimleşme özelliği',
        ],
      ),
      'kristal': (
        'ayrımsal kristallendirme',
        'ayrımsal kristallendirmeyle',
        'çözünürlük farkı',
        ['süzme', 'ayırma hunisi', 'mıknatısla ayırma', 'eleme'],
        ['manyetik özellik farkı', 'tanecik boyutu farkı', 'özkütle farkı'],
      ),
      'yuzdurme': (
        'yüzdürme',
        'suya atılıp yüzdürülerek',
        'özkütle farkı',
        ['ayırma hunisi', 'ayrımsal damıtma', 'mıknatısla ayırma'],
        [
          'manyetik özellik farkı',
          'kaynama noktası farkı',
          'süblimleşme özelliği',
        ],
      ),
      'santrifuj': (
        'santrifüjleme',
        'santrifüjlenerek',
        'özkütle farkı',
        ['ayırma hunisi', 'mıknatısla ayırma', 'eleme', 'ayrımsal damıtma'],
        [
          'manyetik özellik farkı',
          'kaynama noktası farkı',
          'süblimleşme özelliği',
        ],
      ),
    };

// (ad tamlamasının ilk kısmı, eylem, yöntem türü): “zeytinyağı–su karışımının”
// + “ayrılması”; yöntem verilen sorularda yöntem eki ikisinin arasına girer.
const _ayirmaIslemleri = [
  ('zeytinyağı–su karışımının', 'ayrılması', 'huni'),
  ('benzin–su karışımının', 'ayrılması', 'huni'),
  ('ayçiçek yağı–su karışımının', 'ayrılması', 'huni'),
  ('gaz yağı–su karışımının', 'ayrılması', 'huni'),
  ('hekzan–su karışımının', 'ayrılması', 'huni'),
  ('mazot–su karışımının', 'ayrılması', 'huni'),
  ('etil alkol–su karışımının', 'ayrılması', 'ayrimsal'),
  ('aseton–su karışımının', 'ayrılması', 'ayrimsal'),
  ('metil alkol–su karışımının', 'ayrılması', 'ayrimsal'),
  ('ham petrolün', 'bileşenlerine ayrılması', 'ayrimsal'),
  ('sıvılaştırılmış havadan azot ve oksijenin', 'elde edilmesi', 'ayrimsal'),
  ('kum–su karışımının', 'ayrılması', 'suzme'),
  ('tebeşir tozu–su karışımının', 'ayrılması', 'suzme'),
  ('mermer tozu–su karışımının', 'ayrılması', 'suzme'),
  ('kükürt tozu–su karışımının', 'ayrılması', 'suzme'),
  ('demlenmiş çaydaki çay yapraklarının', 'ayrılması', 'suzme'),
  ('tuzlu sudan saf suyun', 'elde edilmesi', 'damitma'),
  ('şekerli sudan saf suyun', 'elde edilmesi', 'damitma'),
  ('deniz suyundan içme suyunun', 'elde edilmesi', 'damitma'),
  ('tuzlalarda deniz suyundan yemek tuzunun', 'elde edilmesi', 'buhar'),
  ('tuzlu sudan katı tuzun', 'elde edilmesi', 'buhar'),
  ('demir tozu–kükürt tozu karışımının', 'ayrılması', 'miknatis'),
  ('demir tozu–kum karışımının', 'ayrılması', 'miknatis'),
  ('demir tozu–şeker karışımının', 'ayrılması', 'miknatis'),
  ('demir talaşı–tahta talaşı karışımının', 'ayrılması', 'miknatis'),
  ('kum–çakıl karışımının', 'ayrılması', 'eleme'),
  ('un–kepek karışımının', 'ayrılması', 'eleme'),
  ('toprak–taş karışımının', 'ayrılması', 'eleme'),
  ('iyot–kum karışımının', 'ayrılması', 'sublim'),
  ('naftalin–kum karışımının', 'ayrılması', 'sublim'),
  ('naftalin–tuz karışımının', 'ayrılması', 'sublim'),
  ('tuz–kum karışımının', 'ayrılması', 'cozme'),
  ('şeker–kum karışımının', 'ayrılması', 'cozme'),
  ('tuz–tebeşir tozu karışımının', 'ayrılması', 'cozme'),
  ('potasyum nitrat–sodyum klorür karışımının', 'ayrılması', 'kristal'),
  ('tahta talaşı–kum karışımının', 'ayrılması', 'yuzdurme'),
  ('kanın', 'plazma ve kan hücrelerine ayrılması', 'santrifuj'),
  ('sütteki kaymağın', 'ayrılması', 'santrifuj'),
];

final _f07 = lmSirali(
  'km_karisim_ayirma',
  'Karışımların ayrılmasında yöntem ve ayırt edici özellik',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final u = kombinasyon(_ayirmaIslemleri, 3, i);
    final x = [for (final j in ucluDizilimler[i % 6]) u[j]];
    final tur = [for (final e in x) _ayirmaTurleri[e.$3]!];
    final aciklama =
        '${[for (var p = 0; p < 3; p++) '${_romaRakam[p]}: ${tur[p].$1} (${tur[p].$3})'].join('; ')}.';
    if (i.isEven) {
      return _uclu(
        '${_uc([for (final e in x) '${e.$1} ${e.$2}'])}\nBu ayırma '
        'işlemlerinde kullanılan yöntemler numara sırasıyla hangi seçenekte '
        'doğru verilmiştir?',
        [for (final t in tur) t.$1],
        [
          for (var p = 0; p < 3; p++)
            _secYanlis(tur[p].$4, i ~/ 2 + p, [for (final t in tur) t.$1]),
        ],
        aciklama,
      );
    }
    return _uclu(
      '${_uc([for (var p = 0; p < 3; p++) '${x[p].$1} ${tur[p].$2} ${x[p].$2}'])}\n'
      'Bu ayırma işlemlerinde yararlanılan ayırt edici özellikler numara '
      'sırasıyla hangi seçenekte doğru verilmiştir?',
      [for (final t in tur) t.$3],
      [
        for (var p = 0; p < 3; p++)
          _secYanlis(tur[p].$5, i ~/ 2 + p, [for (final t in tur) t.$3]),
      ],
      aciklama,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ─────────────────────────── 8 · Kimyasal tepkime türleri ─────────────────────

const _yanma = 'yanma';
const _sentez = 'sentez';
const _analiz = 'analiz';
const _notrlesme = 'nötralleşme';
const _cokelme = 'çözünme-çökelme';

// Her tepkime tek bir türe aittir: yanmalar organik maddelerin yanmasıdır (sentez
// değildir), sentezlerde oksijen yer almaz, çökelmeler asit-baz tepkimesi
// değildir ve nötralleşmelerde çökelek oluşmaz.
const _tepkimeler = [
  ('CH₄(g) + 2O₂(g) → CO₂(g) + 2H₂O(s)', _yanma),
  ('C₃H₈(g) + 5O₂(g) → 3CO₂(g) + 4H₂O(s)', _yanma),
  ('2C₂H₆(g) + 7O₂(g) → 4CO₂(g) + 6H₂O(s)', _yanma),
  ('C₂H₅OH(s) + 3O₂(g) → 2CO₂(g) + 3H₂O(s)', _yanma),
  ('2CH₃OH(s) + 3O₂(g) → 2CO₂(g) + 4H₂O(s)', _yanma),
  ('C₂H₄(g) + 3O₂(g) → 2CO₂(g) + 2H₂O(s)', _yanma),
  ('2C₂H₂(g) + 5O₂(g) → 4CO₂(g) + 2H₂O(s)', _yanma),
  ('2C₄H₁₀(g) + 13O₂(g) → 8CO₂(g) + 10H₂O(s)', _yanma),
  ('C₆H₁₂O₆(k) + 6O₂(g) → 6CO₂(g) + 6H₂O(s)', _yanma),
  ('C₅H₁₂(s) + 8O₂(g) → 5CO₂(g) + 6H₂O(s)', _yanma),
  ('2C₈H₁₈(s) + 25O₂(g) → 16CO₂(g) + 18H₂O(s)', _yanma),
  ('2C₆H₆(s) + 15O₂(g) → 12CO₂(g) + 6H₂O(s)', _yanma),
  ('2C₃H₆(g) + 9O₂(g) → 6CO₂(g) + 6H₂O(s)', _yanma),
  ('C₁₂H₂₂O₁₁(k) + 12O₂(g) → 12CO₂(g) + 11H₂O(s)', _yanma),
  ('N₂(g) + 3H₂(g) → 2NH₃(g)', _sentez),
  ('H₂(g) + Cl₂(g) → 2HCl(g)', _sentez),
  ('2Na(k) + Cl₂(g) → 2NaCl(k)', _sentez),
  ('Fe(k) + S(k) → FeS(k)', _sentez),
  ('CaO(k) + H₂O(s) → Ca(OH)₂(k)', _sentez),
  ('SO₃(g) + H₂O(s) → H₂SO₄(s)', _sentez),
  ('Zn(k) + S(k) → ZnS(k)', _sentez),
  ('H₂(g) + Br₂(s) → 2HBr(g)', _sentez),
  ('2K(k) + Br₂(s) → 2KBr(k)', _sentez),
  ('3Mg(k) + N₂(g) → Mg₃N₂(k)', _sentez),
  ('H₂(g) + I₂(k) → 2HI(g)', _sentez),
  ('Na₂O(k) + H₂O(s) → 2NaOH(suda)', _sentez),
  ('MgO(k) + H₂O(s) → Mg(OH)₂(k)', _sentez),
  ('2Cu(k) + S(k) → Cu₂S(k)', _sentez),
  ('CaCO₃(k) → CaO(k) + CO₂(g)', _analiz),
  ('2H₂O(s) → 2H₂(g) + O₂(g)', _analiz),
  ('MgCO₃(k) → MgO(k) + CO₂(g)', _analiz),
  ('2H₂O₂(s) → 2H₂O(s) + O₂(g)', _analiz),
  ('NH₄Cl(k) → NH₃(g) + HCl(g)', _analiz),
  ('2NaHCO₃(k) → Na₂CO₃(k) + H₂O(g) + CO₂(g)', _analiz),
  ('2Ag₂O(k) → 4Ag(k) + O₂(g)', _analiz),
  ('2NH₃(g) → N₂(g) + 3H₂(g)', _analiz),
  ('Cu(OH)₂(k) → CuO(k) + H₂O(g)', _analiz),
  ('2HI(g) → H₂(g) + I₂(g)', _analiz),
  ('BaCO₃(k) → BaO(k) + CO₂(g)', _analiz),
  ('2NaCl(s) → 2Na(s) + Cl₂(g)', _analiz),
  ('ZnCO₃(k) → ZnO(k) + CO₂(g)', _analiz),
  ('Ca(OH)₂(k) → CaO(k) + H₂O(g)', _analiz),
  ('HCl(suda) + NaOH(suda) → NaCl(suda) + H₂O(s)', _notrlesme),
  ('H₂SO₄(suda) + 2KOH(suda) → K₂SO₄(suda) + 2H₂O(s)', _notrlesme),
  ('2HNO₃(suda) + Ca(OH)₂(suda) → Ca(NO₃)₂(suda) + 2H₂O(s)', _notrlesme),
  ('HBr(suda) + KOH(suda) → KBr(suda) + H₂O(s)', _notrlesme),
  ('H₃PO₄(suda) + 3NaOH(suda) → Na₃PO₄(suda) + 3H₂O(s)', _notrlesme),
  ('CH₃COOH(suda) + NaOH(suda) → CH₃COONa(suda) + H₂O(s)', _notrlesme),
  ('2HCl(suda) + Ca(OH)₂(suda) → CaCl₂(suda) + 2H₂O(s)', _notrlesme),
  ('HNO₃(suda) + KOH(suda) → KNO₃(suda) + H₂O(s)', _notrlesme),
  ('H₂SO₄(suda) + 2NaOH(suda) → Na₂SO₄(suda) + 2H₂O(s)', _notrlesme),
  ('HI(suda) + LiOH(suda) → LiI(suda) + H₂O(s)', _notrlesme),
  ('2HBr(suda) + Ba(OH)₂(suda) → BaBr₂(suda) + 2H₂O(s)', _notrlesme),
  ('HCl(suda) + KOH(suda) → KCl(suda) + H₂O(s)', _notrlesme),
  ('2HCl(suda) + Ba(OH)₂(suda) → BaCl₂(suda) + 2H₂O(s)', _notrlesme),
  ('HNO₃(suda) + NaOH(suda) → NaNO₃(suda) + H₂O(s)', _notrlesme),
  ('AgNO₃(suda) + NaCl(suda) → AgCl(k) + NaNO₃(suda)', _cokelme),
  ('Pb(NO₃)₂(suda) + 2KI(suda) → PbI₂(k) + 2KNO₃(suda)', _cokelme),
  ('BaCl₂(suda) + Na₂SO₄(suda) → BaSO₄(k) + 2NaCl(suda)', _cokelme),
  ('CaCl₂(suda) + Na₂CO₃(suda) → CaCO₃(k) + 2NaCl(suda)', _cokelme),
  ('AgNO₃(suda) + KBr(suda) → AgBr(k) + KNO₃(suda)', _cokelme),
  ('Pb(NO₃)₂(suda) + Na₂SO₄(suda) → PbSO₄(k) + 2NaNO₃(suda)', _cokelme),
  ('BaCl₂(suda) + K₂CO₃(suda) → BaCO₃(k) + 2KCl(suda)', _cokelme),
  ('AgNO₃(suda) + KI(suda) → AgI(k) + KNO₃(suda)', _cokelme),
  ('Pb(NO₃)₂(suda) + 2NaCl(suda) → PbCl₂(k) + 2NaNO₃(suda)', _cokelme),
  ('Ba(NO₃)₂(suda) + K₂SO₄(suda) → BaSO₄(k) + 2KNO₃(suda)', _cokelme),
  ('CaCl₂(suda) + 2AgNO₃(suda) → 2AgCl(k) + Ca(NO₃)₂(suda)', _cokelme),
  ('SrCl₂(suda) + Na₂SO₄(suda) → SrSO₄(k) + 2NaCl(suda)', _cokelme),
  ('BaCl₂(suda) + Na₂CO₃(suda) → BaCO₃(k) + 2NaCl(suda)', _cokelme),
  ('CaCl₂(suda) + K₂CO₃(suda) → CaCO₃(k) + 2KCl(suda)', _cokelme),
];

// Tipik karıştırmalar: her türün kesin yanlış iki karşılığı.
const _tepkimeKarisan = {
  _yanma: [_analiz, _sentez],
  _sentez: [_analiz, _notrlesme],
  _analiz: [_sentez, _yanma],
  _notrlesme: [_cokelme, _sentez],
  _cokelme: [_notrlesme, _analiz],
};

const _tepkimeNedeni = {
  _yanma: 'madde oksijenle tepkimeye girip CO₂ ve H₂O oluşturur',
  _sentez: 'maddeler birleşerek tek bir bileşik oluşturur',
  _analiz: 'bir bileşik daha basit maddelere ayrışır',
  _notrlesme: 'asit ile baz tepkimeye girip tuz ve su oluşturur',
  _cokelme: 'çözünmüş iyonlardan suda az çözünen bir katı çöker',
};

final _f08 = lmSirali(
  'km_tepkime_turu',
  'Kimyasal tepkime türlerinin sınıflandırılması',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final u = kombinasyon(_tepkimeler, 3, i);
    final x = [for (final j in ucluDizilimler[i % 6]) u[j]];
    final liste = _uc([for (final e in x) e.$1]);
    final aciklama =
        '${[for (var p = 0; p < 3; p++) '${_romaRakam[p]}: ${x[p].$2} (${_tepkimeNedeni[x[p].$2]})'].join('; ')}.';
    if (i.isEven) {
      return _uclu(
        '$liste\nBu tepkimelerin türü numara sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
        [for (final e in x) e.$2],
        [
          for (var p = 0; p < 3; p++)
            _tepkimeKarisan[x[p].$2]![(i ~/ 2 + p) % 2],
        ],
        aciklama,
      );
    }
    final turler = <String>[];
    for (final e in x) {
      if (!turler.contains(e.$2)) turler.add(e.$2);
    }
    final hedef = turler[(i ~/ 2) % turler.length];
    var maske = 0;
    for (var p = 0; p < 3; p++) {
      if (x[p].$2 == hedef) maske |= 1 << p;
    }
    return _hangileri(
      '$liste\nNumaralanmış tepkimelerden hangileri $hedef tepkimesidir?',
      maske,
      aciklama,
      i,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ───────────────────────── 9 · Zayıf etkileşimler ─────────────────────────────

const _hidrojenBagli = [
  'H₂O', 'HF', 'NH₃', 'CH₃OH', 'C₂H₅OH', 'CH₃COOH', 'CH₃NH₂', 'H₂O₂', //
  'HCOOH', 'CH₃CH₂CH₂OH',
];
const _polarMolekuller = [
  'HCl', 'HBr', 'HI', 'H₂S', 'SO₂', 'CH₃Cl', 'CHCl₃', 'CH₂Cl₂', 'CH₃OCH₃', //
  'CH₃COCH₃', 'PCl₃', 'CH₂O',
];
const _apolarMolekuller = [
  'H₂', 'N₂', 'O₂', 'F₂', 'Cl₂', 'Br₂', 'I₂', 'CH₄', 'C₂H₆', 'C₃H₈', 'CO₂', //
  'CCl₄', 'BF₃', 'CS₂', 'C₆H₆', 'C₂H₄',
];

// 0: hidrojen bağı yapan, 1: polar, 2: apolar.
int _etkilesimSinifi(String m) =>
    _hidrojenBagli.contains(m) ? 0 : (_polarMolekuller.contains(m) ? 1 : 2);

String _etkilesimYazi(String m) => switch (_etkilesimSinifi(m)) {
  0 => '$m: hidrojen bağı, dipol-dipol ve London kuvvetleri',
  1 => '$m: polar; dipol-dipol ve London kuvvetleri',
  _ => '$m: apolar; yalnız London kuvvetleri',
};

final _etkilesimHepsi = [
  ..._hidrojenBagli,
  ..._polarMolekuller,
  ..._apolarMolekuller,
];

final _hidrojenUcluleri = [
  for (final u in _secimler(_etkilesimHepsi, 3))
    if (u.any((m) => _etkilesimSinifi(m) == 0)) u,
];
final _dipolUcluleri = [
  for (final u in _secimler([..._polarMolekuller, ..._apolarMolekuller], 3))
    if (u.any((m) => _etkilesimSinifi(m) == 1)) u,
];
final _londonUcluleri = [
  for (final u in _secimler(_etkilesimHepsi, 3))
    if (u.any((m) => _etkilesimSinifi(m) == 2)) u,
];

// Kaynama noktası serileri (°C, 1 atm): aynı türde etkileşen maddeler ya da mol
// kütleleri yakın, etkileşim türü farklı maddeler.
const _kaynamaSerileri = [
  (
    'soy',
    [('He', -269), ('Ne', -246), ('Ar', -186), ('Kr', -153), ('Xe', -108)],
  ),
  ('halojen', [('F₂', -188), ('Cl₂', -34), ('Br₂', 59), ('I₂', 184)]),
  (
    'alkan',
    [
      ('CH₄ (metan)', -162), ('C₂H₆ (etan)', -89), ('C₃H₈ (propan)', -42), //
      ('C₄H₁₀ (bütan)', -1), ('C₅H₁₂ (pentan)', 36), ('C₆H₁₄ (hekzan)', 69),
      ('C₇H₁₆ (heptan)', 98), ('C₈H₁₈ (oktan)', 126),
    ],
  ),
  ('hx', [('HF', 20), ('HCl', -85), ('HBr', -67), ('HI', -35)]),
  ('6a', [('H₂O', 100), ('H₂S', -60), ('H₂Se', -41), ('H₂Te', -2)]),
  ('4a', [('CH₄', -162), ('SiH₄', -112), ('GeH₄', -88), ('SnH₄', -52)]),
  ('karma', [('C₂H₅OH', 78), ('CH₃OCH₃', -24), ('C₃H₈', -42)]),
  ('karma', [('CH₃CH₂CH₂OH', 97), ('CH₃COCH₃', 56), ('C₄H₁₀', -1)]),
  ('karma', [('CH₃NH₂', -6), ('CH₃F', -78), ('C₂H₆', -89)]),
  ('karma', [('C₂H₅OH', 78), ('CH₃CHO', 20), ('C₃H₈', -42)]),
  ('karma', [('CH₃COOH', 118), ('CH₃COCH₃', 56), ('C₄H₁₀', -1)]),
];

/// (seri türü, seri içindeki üç madde) seçkileri; her biri üç dizilimle.
final _kaynamaSeckileri = [
  for (final (tur, seri) in _kaynamaSerileri)
    for (final u in _secimler(seri, 3)) (tur, u, seri.first.$1),
];

AdvancedItem _kaynamaSirasi(int j) {
  final (tur, u, ilk) = _kaynamaSeckileri[j ~/ 3];
  final d = _dizilim3[(j ~/ 3 + 2 * (j % 3)) % 6];
  final x = [for (final k in d) u[k]];
  final sira = [0, 1, 2]..sort((p, q) => x[q].$2.compareTo(x[p].$2));
  String yaz(List<int> s) => [for (final p in s) _romaRakam[p]].join(' > ');
  final adaylar = [
    yaz(sira.reversed.toList()),
    yaz([sira[1], sira[0], sira[2]]),
    yaz([sira[0], sira[2], sira[1]]),
    yaz([sira[2], sira[0], sira[1]]),
  ];
  final hbVar = x.any((e) => e.$1 == ilk);
  final gerekce = switch (tur) {
    'soy' =>
      'Soy gaz atomları arasında yalnız London kuvvetleri vardır; atom '
          'kütlesi büyüdükçe London kuvvetleri ve kaynama noktası artar.',
    'halojen' || '4a' =>
      'Bu moleküller apolardır; molekül kütlesi büyüdükçe London kuvvetleri '
          'güçlenir.',
    'alkan' =>
      'Alkanlar apolardır; karbon sayısı ve molekül kütlesi büyüdükçe London '
          'kuvvetleri güçlenir.',
    'karma' =>
      'Mol kütleleri yakın olduğundan etkileşim türü belirleyicidir: '
          '${u[0].$1} hidrojen bağı, ${u[1].$1} dipol-dipol etkileşimi, '
          '${u[2].$1} yalnız London kuvvetleri içerir.',
    _ =>
      hbVar
          ? '$ilk molekülleri arasında hidrojen bağı bulunduğundan kaynama '
                'noktası en yüksektir; ötekilerde molekül kütlesi büyüdükçe '
                'kaynama noktası artar.'
          : 'Bu moleküllerde molekül kütlesi büyüdükçe London kuvvetleri '
                'güçlenir ve kaynama noktası artar.',
  };
  return secenekli(
    '${_uc([for (final e in x) e.$1])}\nBu maddelerin 1 atm basınçtaki kaynama '
        'noktalarının büyükten küçüğe doğru sıralanışı hangi seçenekte doğru '
        'verilmiştir?',
    yaz(sira),
    adaylar,
    '$gerekce Kaynama noktaları: '
        '${[for (var p = 0; p < 3; p++) '${_romaRakam[p]} ${_yz(x[p].$2)} °C'].join(', ')}.',
  );
}

final _f09 = lmSirali(
  'km_zayif_etkilesim',
  'Zayıf etkileşimler ve kaynama noktası',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.analiz,
  (i) {
    const sira = 261, hidrojen = 1800, dipol = 1339;
    if (i < sira) return _kaynamaSirasi(i);
    final j = i - sira;
    final (liste, n, k, soru) = j < hidrojen
        ? (_hidrojenUcluleri, hidrojen, j, 'hidrojen bağı bulunur')
        : j < hidrojen + dipol
        ? (
            _dipolUcluleri,
            dipol,
            j - hidrojen,
            'dipol-dipol etkileşimi bulunur',
          )
        : (
            _londonUcluleri,
            lmAileBoyu - sira - hidrojen - dipol,
            j - hidrojen - dipol,
            'yalnız London kuvvetleri bulunur',
          );
    final u = liste[k * liste.length ~/ n];
    final x = [for (final p in ucluDizilimler[(k + k ~/ 6) % 6]) u[p]];
    final aranan = j < hidrojen ? 0 : (j < hidrojen + dipol ? 1 : 2);
    var maske = 0;
    for (var p = 0; p < 3; p++) {
      if (_etkilesimSinifi(x[p]) == aranan) maske |= 1 << p;
    }
    return _hangileri(
      '${_uc(x)}\nBu maddelerden hangilerinin saf hâlde molekülleri arasında '
          '$soru?',
      maske,
      '${[for (var p = 0; p < 3; p++) '${_romaRakam[p]}. ${_etkilesimYazi(x[p])}'].join('; ')}.',
      i,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ───────────────────────── 10 · Gazların kinetik teorisi ─────────────────────

const _gazKutlesi = {
  'H₂': 2,
  'He': 4,
  'CH₄': 16,
  'Ne': 20,
  'N₂': 28,
  'O₂': 32,
  'Ar': 40,
  'CO₂': 44,
};
// Gazın sıvılaşmadığı en düşük sıcaklık için kaynama (CO₂ için süblimleşme)
// noktası (K).
const _gazKaynama = {
  'H₂': 20,
  'He': 4,
  'CH₄': 112,
  'Ne': 27,
  'N₂': 77,
  'O₂': 90,
  'Ar': 87,
  'CO₂': 195,
};
const _tekAtomlu = {'He', 'Ne', 'Ar'};
const _soguGazlar = ['He', 'Ne', 'Ar', 'N₂', 'H₂'];

const _gazCiftleri = [
  ('He', 'CH₄'), ('H₂', 'He'), ('CH₄', 'O₂'), ('He', 'Ne'), ('Ne', 'Ar'), //
  ('N₂', 'O₂'), ('He', 'N₂'), ('CH₄', 'Ar'), ('CH₄', 'N₂'), ('Ne', 'O₂'),
  ('N₂', 'Ar'), ('O₂', 'Ar'), ('O₂', 'CH₄'), ('Ar', 'Ne'), ('Ne', 'CH₄'),
  ('Ar', 'CH₄'), ('O₂', 'N₂'), ('N₂', 'CH₄'), ('He', 'H₂'), ('N₂', 'CO₂'),
  ('O₂', 'CO₂'), ('CH₄', 'CO₂'), ('Ar', 'CO₂'), ('CO₂', 'O₂'), ('CO₂', 'N₂'),
];

// Ortalama hızın katları: (pay, payda) ve uygun m aralığı (T₁ = payda²·m).
const _hizKatlari = [
  (2, 1, 150, 500),
  (3, 2, 38, 222),
  (4, 3, 17, 125),
  (5, 4, 10, 80),
  (5, 3, 17, 80),
  (6, 5, 6, 55),
  (1, 2, 100, 375),
  (2, 3, 25, 166),
  (3, 4, 12, 93),
  (4, 5, 7, 60),
];

const _enerjiDegisimi = [
  10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, //
  -10, -20, -30, -40, -50,
];

String _tanecik(String g) =>
    _tekAtomlu.contains(g) ? 'atomlarının' : 'moleküllerinin';

final _f10 = lmAile(
  'km_kinetik_teori',
  'Kinetik teori: ortalama kinetik enerji ve hız',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    if (c < 2) {
      final t1k = 200 + 10 * (a + 25 * c), x = _enerjiDegisimi[b];
      final t2k = t1k * (100 + x) ~/ 100;
      final t1 = t1k - 273, t2 = t2k - 273;
      final gaz = _soguGazlar[(a + b) % 5];
      final artis = x > 0;
      final oran = (100 + x) / 100;
      return _say(
        'Sabit hacimli bir kapta ${_yz(t1)} °C sıcaklıkta bulunan $gaz gazının '
            '${_tanecik(gaz)} ortalama kinetik enerjisi %${x.abs()} '
            '${artis ? 'artırılmak' : 'azaltılmak'} isteniyor. Buna göre gaz kaç '
            '°C sıcaklığa ${artis ? 'ısıtılmalıdır' : 'soğutulmalıdır'}?',
        t2,
        [t1 * oran, t2k, t1k * oran * oran - 273, t1 + x],
        'Ortalama kinetik enerji mutlak sıcaklıkla doğru orantılıdır. T₁ = '
            '${_yz(t1)} + 273 = $t1k K, T₂ = $t1k·${_t(oran)} = $t2k K olur; '
            'gazın sıcaklığı $t2k − 273 = ${_yz(t2)} °C olmalıdır.',
        birim: '°C',
        basamak: 0,
        arti: false,
      );
    }
    if (c < 4) {
      final (p, q, lo, hi) = _hizKatlari[b % 10];
      final m = lo + (a + 25 * (c - 2)) * (hi - lo) ~/ 49;
      final t1k = q * q * m, t2k = p * p * m;
      final t1 = t1k - 273, t2 = t2k - 273;
      final gaz = _soguGazlar[(a + 2 * b) % 5];
      final artis = p > q;
      final kat = kesir(p, q), kare = kesir(p * p, q * q);
      final degisim = b >= 10;
      final giris =
          '${_yz(t1)} °C sıcaklıkta bulunan $gaz gazının ${_tanecik(gaz)} '
          'ortalama hızının $kat katına ${artis ? 'çıkması' : 'düşmesi'} için';
      final cozum =
          'Ortalama hız mutlak sıcaklığın kareköküyle orantılıdır. T₁ = '
          '${_yz(t1)} + 273 = $t1k K; hızın $kat katı olması için T₂ = '
          '($kat)²·$t1k = $kare·$t1k = $t2k K olmalıdır';
      if (degisim) {
        final fark = (t2k - t1k).abs();
        return _say(
          '$giris gazın sıcaklığı kaç °C ${artis ? 'artırılmalıdır' : 'azaltılmalıdır'}?',
          fark,
          [
            (p / q * t1k - t1k).abs(),
            (p * p / (q * q) * t1 - t1).abs(),
            t2k,
            t2.abs(),
          ],
          '$cozum. Sıcaklık ${artis ? '$t2k − $t1k' : '$t1k − $t2k'} = $fark °C '
              '${artis ? 'artırılmalıdır' : 'azaltılmalıdır'}.',
          birim: '°C',
          basamak: 0,
        );
      }
      return _say(
        '$giris gaz kaç °C sıcaklığa ${artis ? 'ısıtılmalıdır' : 'soğutulmalıdır'}?',
        t2,
        [p / q * t1k - 273, p * p / (q * q) * t1, t2k, p / q * t1],
        '$cozum; bu da $t2k − 273 = ${_yz(t2)} °C eder.',
        birim: '°C',
        basamak: 0,
        arti: false,
      );
    }
    final (gx, gy) = _gazCiftleri[a];
    final mx = _gazKutlesi[gx]!, my = _gazKutlesi[gy]!;
    final taban = mx ~/ mx.gcd(my);
    var lo = 1, hi = 1;
    bool uygun(int k) {
      final t1 = taban * k, t2 = t1 * my ~/ mx;
      return t1 >= 150 &&
          t1 >= _gazKaynama[gx]! + 30 &&
          t2 >= 100 &&
          t2 >= _gazKaynama[gy]! + 30 &&
          t1 <= 1500 &&
          t2 <= 2000;
    }

    while (!uygun(lo)) {
      lo++;
    }
    hi = lo;
    while (uygun(hi + 1)) {
      hi++;
    }
    final j = b + 20 * ((c - 4) ~/ 2);
    final k = lo + j * (hi - lo) ~/ 59;
    final t1k = taban * k, t2k = t1k * my ~/ mx;
    final t1 = t1k - 273, t2 = t2k - 273;
    final kelvin = c.isOdd;
    final kok = _karekok(my / mx);
    return _say(
      '${_yz(t1)} °C sıcaklıktaki $gx gazının ${_tanecik(gx)} ortalama hızı, '
          'kaç ${kelvin ? 'K' : '°C'} sıcaklıktaki $gy gazının ${_tanecik(gy)} '
          'ortalama hızına eşittir? ($gx: $mx g/mol, $gy: $my g/mol)',
      kelvin ? t2k : t2,
      kelvin
          ? [t1 * my / mx, t1k * mx / my, t1k * kok, t2]
          : [t1 * my / mx, t1k * mx / my - 273, t1k * kok - 273, t2k],
      'Ortalama hız √(T/M) ile orantılıdır; hızlar eşitse T₁/M₁ = T₂/M₂ olur. '
          'T₁ = ${_yz(t1)} + 273 = $t1k K, T₂ = $t1k·$my/$mx = $t2k K'
          '${kelvin ? '' : ' = ${_yz(t2)} °C'} bulunur.',
      birim: kelvin ? 'K' : '°C',
      basamak: 0,
      arti: kelvin,
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

double _karekok(double x) {
  var r = x < 1 ? 1.0 : x;
  for (var j = 0; j < 60; j++) {
    r = (r + x / r) / 2;
  }
  return r;
}

// ─────────────────────── Bilimsel gösterim yardımcıları ──────────────────────

/// pay·10^us değerini m·10ⁿ biçiminde kesin yazar (m ∈ [1, 10)).
String _bilimsel(int pay, int us) {
  if (pay <= 0) throw StateError('Pozitif olmalı: $pay');
  var p = pay, e = us;
  while (p % 10 == 0) {
    p ~/= 10;
    e++;
  }
  final s = '$p';
  final govde = s.length == 1 ? s : '${s[0]},${s.substring(1)}';
  final us10 = e + s.length - 1;
  return us10 == 0 ? govde : '$govde·10${_ust(us10)}';
}

/// Kesin değerin anlamlı basamak sayısı.
int _anlamli(int pay) {
  var p = pay;
  while (p % 10 == 0) {
    p ~/= 10;
  }
  return '$p'.length;
}

double _ondalik(int pay, int us) {
  var v = pay.toDouble();
  if (us >= 0) {
    for (var j = 0; j < us; j++) {
      v *= 10;
    }
  } else {
    for (var j = 0; j < -us; j++) {
      v /= 10;
    }
  }
  return v;
}

/// Yaklaşık değeri [anlamli] basamakla m·10ⁿ biçiminde yazar.
String _bilimselYaklasik(double v, int anlamli) {
  if (!v.isFinite || v <= 0) return '';
  var e = 0;
  var m = v;
  while (m >= 10) {
    m /= 10;
    e++;
  }
  while (m < 1) {
    m *= 10;
    e--;
  }
  var r = double.parse(m.toStringAsFixed(anlamli - 1));
  if (r >= 10) {
    r /= 10;
    e++;
  }
  final govde = tr(r, anlamli - 1);
  return e == 0 ? govde : '$govde·10${_ust(e)}';
}

/// Bilimsel gösterimli yanıt. Çeldiriciler doğru yanıtla aynı anlamlı basamak
/// sayısıyla yazılır; doğru yanıta %3'ten yakın olanlar atılır.
AdvancedItem _bilimselSoru(
  String kok,
  (int, int) dogru,
  Iterable<double> adaylar,
  String aciklama, {
  String birim = '',
}) {
  final d = _ondalik(dogru.$1, dogru.$2);
  final basamak = _anlamli(dogru.$1) < 2 ? 2 : _anlamli(dogru.$1);
  final havuz = [...adaylar, d * 2, d / 2, d * 10, d / 10, d * 4];
  return secenekli(kok, birimli(_bilimsel(dogru.$1, dogru.$2), birim), [
    for (final x in havuz)
      if (x.isFinite && x > 0 && (x / d - 1).abs() > 0.03)
        birimli(_bilimselYaklasik(x, basamak), birim),
  ], aciklama);
}

double _kupKok(double x) {
  var r = x < 1 ? 1.0 : x;
  for (var j = 0; j < 200; j++) {
    r = (2 * r + x / (r * r)) / 3;
  }
  return r;
}

// ─────────────────────── 11 · Çözünürlük çarpımı (Kçç) ───────────────────────

// Tuz türleri: (formül, katyon, anyon, katyon katsayısı, anyon katsayısı).
const _tuzTurleri = [
  ('XY', 'X⁺', 'Y⁻', 1, 1),
  ('XY₂', 'X²⁺', 'Y⁻', 1, 2),
  ('X₂Y', 'X⁺', 'Y²⁻', 2, 1),
];

// Molar çözünürlük gövdeleri (onda bir birimle): XY için kareleri, öteki iki
// tür için 4·m³ değerleri en çok dört anlamlı basamaklıdır.
const _kccGovdeXY = [
  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 25, 30, 40, 50, 60, 70, //
  80, 90,
];
const _kccGovdeXY2 = [
  10,
  11,
  12,
  13,
  15,
  20,
  25,
  30,
  35,
  40,
  45,
  50,
  60,
  70,
  80,
  90,
];
const _kccTamGovde = [10, 20, 30, 40, 50, 60, 70, 80, 90];

/// Kçç = [X]^a·[Y]^b; s onda bir birimli gövde ve üsle verilir.
(int, int) _kccDegeri(int t, int sGovde, int sUs) {
  final (_, _, _, a, b) = _tuzTurleri[t];
  var pay = 1, us = 0;
  for (var j = 0; j < a; j++) {
    pay *= a * sGovde;
    us += sUs;
  }
  for (var j = 0; j < b; j++) {
    pay *= b * sGovde;
    us += sUs;
  }
  return (pay, us);
}

String _kccIfade(int t) => switch (t) {
  0 => 'Kçç = [X⁺]·[Y⁻] = s²',
  1 => 'Kçç = [X²⁺]·[Y⁻]² = s·(2s)² = 4s³',
  _ => 'Kçç = [X⁺]²·[Y²⁻] = (2s)²·s = 4s³',
};

// Ortak iyon derişimleri: (gövde, üs) → gövde·10^üs mol/L.
const _ortakDerisim = [
  (1, -1),
  (2, -1),
  (4, -1),
  (5, -1),
  (1, -2),
  (2, -2),
  (5, -2),
];
const _kccHacim = [(5, -1, '500 mL'), (2, 0, '2 L'), (5, 0, '5 L')];

// Durumlar: A (s → Kçç; 4 sunuş), B (Kçç → s, [X], [Y]), C (ortak iyon).
final _kccDurumlari = () {
  final a = <(int, int, int, int, int, int)>[];
  for (var t = 0; t < 3; t++) {
    final govde = t == 0 ? _kccGovdeXY : _kccGovdeXY2;
    for (final m in govde) {
      for (var k = 0; k < 7; k++) {
        // XY için iki iyonun derişimi s'ye eşittir; yalnız s ve hacim sunuşu.
        for (final p in t == 0 ? const [0, 3] : const [0, 1, 2, 3]) {
          a.add((0, t, m, k, p, 0));
        }
      }
    }
  }
  final b = <(int, int, int, int, int, int)>[];
  for (var t = 0; t < 3; t++) {
    final govde = t == 0 ? _kccGovdeXY : _kccTamGovde;
    for (final m in govde) {
      for (var k = 0; k < 7; k++) {
        for (final p in t == 0 ? const [0] : const [0, 1, 2]) {
          b.add((1, t, m, k, p, 0));
        }
      }
    }
  }
  final c = <(int, int, int, int, int, int)>[];
  for (var t = 0; t < 3; t++) {
    for (final m in const [10, 15, 20, 25, 30, 40, 50, 60, 80]) {
      for (var k = 0; k < 7; k++) {
        // XY için ortak katyon ve ortak anyon aynı hesabı verir.
        for (final p in t == 0 ? const [0, 2] : const [0, 1, 2]) {
          for (var o = 0; o < _ortakDerisim.length; o++) {
            c.add((2, t, m, k, p, o));
          }
        }
      }
    }
  }
  final kalan = lmAileBoyu - a.length - b.length;
  return [...a, ...b, for (var j = 0; j < kalan; j++) c[j * c.length ~/ kalan]];
}();

final _f11 = lmSirali(
  'km_kcc',
  'Çözünürlük çarpımı, molar çözünürlük ve ortak iyon',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.uygulama,
  (i) {
    final (tur, t, m, k, p, o) = _kccDurumlari[i];
    final (f, kat, an, a, b) = _tuzTurleri[t];
    final giris =
        'Belirli bir sıcaklıkta suda az çözünen $f tuzu $kat ve $an iyonlarına '
        'ayrışarak çözünür.';
    if (tur == 0) {
      // s = m·10^(−sUs−1)
      final sUs = -(t == 0 ? 3 : 2) - k - 1;
      final kcc = _kccDegeri(t, m, sUs);
      final s = _ondalik(m, sUs);
      final (veri, cevir) = switch (p) {
        0 => (
          'Bu sıcaklıkta $f tuzunun molar çözünürlüğü '
              '${_bilimsel(m, sUs)} mol/L olarak ölçülüyor.',
          '',
        ),
        1 => (
          'Bu sıcaklıkta $f tuzunun doygun çözeltisinde $an iyonu '
              'derişimi ${_bilimsel(b * m, sUs)} mol/L olarak ölçülüyor.',
          b == 1
              ? ''
              : 's = ${_bilimsel(b * m, sUs)} / $b = ${_bilimsel(m, sUs)} mol/L olur. ',
        ),
        2 => (
          'Bu sıcaklıkta $f tuzunun doygun çözeltisinde $kat iyonu '
              'derişimi ${_bilimsel(a * m, sUs)} mol/L olarak ölçülüyor.',
          a == 1
              ? ''
              : 's = ${_bilimsel(a * m, sUs)} / $a = ${_bilimsel(m, sUs)} mol/L olur. ',
        ),
        _ => () {
          final (vg, vu, vy) = _kccHacim[(m + k) % 3];
          return (
            'Bu sıcaklıkta $vy doygun $f çözeltisinde '
                '${_bilimsel(m * vg, sUs + vu)} mol $f çözünmüş olarak '
                'bulunmaktadır.',
            's = ${_bilimsel(m * vg, sUs + vu)} / ${_t(_ondalik(vg, vu))} = ${_bilimsel(m, sUs)} mol/L olur. ',
          );
        }(),
      };
      final yanlisS = switch (p) {
        1 => b * s,
        2 => a * s,
        3 => s * _ondalik(_kccHacim[(m + k) % 3].$1, _kccHacim[(m + k) % 3].$2),
        _ => s,
      };
      return _bilimselSoru(
        '$giris $veri Buna göre bu sıcaklıkta $f tuzunun çözünürlük çarpımı '
            '(Kçç) kaçtır?',
        kcc,
        [
          if (t == 0) ...[
            2 * s * s,
            s,
            4 * s * s * s,
          ] else ...[
            s * s * s,
            2 * s * s * s,
            s * s,
          ],
          if (p != 0)
            t == 0 ? yanlisS * yanlisS : 4 * yanlisS * yanlisS * yanlisS,
        ],
        '$cevir${_kccIfade(t)} = ${_bilimsel(kcc.$1, kcc.$2)}.',
      );
    }
    if (tur == 1) {
      final sUs = -(t == 0 ? 3 : 2) - k - 1;
      final kcc = _kccDegeri(t, m, sUs);
      final s = _ondalik(m, sUs), kd = _ondalik(kcc.$1, kcc.$2);
      final (ad, katsayi) = switch (p) {
        0 => ('molar çözünürlüğü', 1),
        1 => ('doygun çözeltisindeki $an iyonu derişimi', b),
        _ => ('doygun çözeltisindeki $kat iyonu derişimi', a),
      };
      final dogruSayi = katsayi * m;
      final kok = t == 0 ? _karekok(kd) : _kupKok(kd);
      return _bilimselSoru(
        '$giris Bu sıcaklıkta $f tuzunun çözünürlük çarpımı Kçç = '
            '${_bilimsel(kcc.$1, kcc.$2)} olarak verilmiştir. Buna göre $f '
            'tuzunun $ad kaç mol/L olur?',
        (dogruSayi, sUs),
        [
          if (t == 0) ...[
            kd,
            2 * _karekok(kd),
            _karekok(kd) / 2,
          ] else ...[
            kok * katsayi,
            _karekok(kd / 4) * katsayi,
            _kupKok(kd / 2) * katsayi,
          ],
          if (katsayi > 1) s,
        ],
        '${_kccIfade(t)} = ${_bilimsel(kcc.$1, kcc.$2)} eşitliğinden s = '
            '${_bilimsel(m, sUs)} mol/L bulunur.'
            '${katsayi > 1 ? ' İstenen iyon derişimi $katsayi·s = ${_bilimsel(dogruSayi, sUs)} mol/L olur.' : ''}',
        birim: 'mol/L',
      );
    }
    // Ortak iyon: s = m·10^(−k−7) (10⁻⁶ ile 10⁻¹² arasında).
    final sUs = -6 - k - 1;
    final (cg, cu) = _ortakDerisim[o];
    final anyonOrtak = p != 1;
    final s = _ondalik(m, sUs), c = _ondalik(cg, cu);
    // Kçç = [X]^a·[Y]^b; ortak iyonun derişimi c alınır.
    var kp = 1, ku = 0;
    for (var j = 0; j < a; j++) {
      if (anyonOrtak) {
        kp *= a * m;
        ku += sUs;
      } else {
        kp *= cg;
        ku += cu;
      }
    }
    for (var j = 0; j < b; j++) {
      if (anyonOrtak) {
        kp *= cg;
        ku += cu;
      } else {
        kp *= b * m;
        ku += sUs;
      }
    }
    final kd = _ondalik(kp, ku);
    final ortak = anyonOrtak ? an : kat;
    final hacimli = p == 2;
    // Hacim ortak iyon derişimine sayıca eşit olmasın (yanıt Kçç ile çakışır).
    var hs = (m + k + o) % 3;
    if (_kccHacim[hs].$1 == cg && _kccHacim[hs].$2 == cu) hs = (hs + 1) % 3;
    final (vg, vu, vy) = _kccHacim[hs];
    final v = _ondalik(vg, vu);
    final ifade = anyonOrtak
        ? (t == 0
              ? 'Kçç = s·${_t(c)}'
              : t == 1
              ? 'Kçç = s·(${_t(c)})²'
              : 'Kçç = (2s)²·${_t(c)}')
        : (t == 0
              ? 'Kçç = ${_t(c)}·s'
              : t == 1
              ? 'Kçç = ${_t(c)}·(2s)²'
              : 'Kçç = (${_t(c)})²·s');
    final saf = t == 0 ? _karekok(kd) : _kupKok(kd / 4);
    final hatalar = anyonOrtak
        ? (t == 0
              ? [kd / (c * c), kd * c]
              : t == 1
              ? [kd / c, kd / (4 * c * c)]
              : [_karekok(kd / c), kd / (4 * c)])
        : (t == 0
              ? [kd / (c * c), kd * c]
              : t == 1
              ? [_karekok(kd / c), kd / (4 * c)]
              : [kd / c, kd / (4 * c * c)]);
    final kokSoru =
        '$giris Bu sıcaklıkta $f tuzunun çözünürlük çarpımı Kçç = '
        '${_bilimsel(kp, ku)} olarak verilmiştir. Buna göre $ortak iyonu '
        'derişimi ${_t(c)} mol/L olan ${hacimli ? vy : 'bir'} çözeltide';
    final notu =
        ' (Ortak iyonun derişimi, tuzun çözünmesiyle değişmeyecek kadar büyük '
        'kabul edilir.)';
    final yol =
        '$ortak iyonu derişimi ${_t(c)} mol/L alınır: $ifade = '
        '${_bilimsel(kp, ku)} eşitliğinden s = ${_bilimsel(m, sUs)} mol/L '
        'bulunur.';
    if (hacimli) {
      return _bilimselSoru(
        '$kokSoru en çok kaç mol $f çözünebilir?$notu',
        (m * vg, sUs + vu),
        [s, s / v, saf * v, for (final h in hatalar) h * v],
        '$yol $vy çözeltide ${_bilimsel(m, sUs)}·${_t(v)} = '
            '${_bilimsel(m * vg, sUs + vu)} mol $f çözünür.',
        birim: 'mol',
      );
    }
    return _bilimselSoru(
      '$kokSoru $f tuzunun molar çözünürlüğü kaç mol/L olur?$notu',
      (m, sUs),
      [saf, ...hatalar],
      yol,
      birim: 'mol/L',
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ──────────────────── 12 · Zayıf asit ve bazlarda pH ve iyonlaşma ─────────────

// (ad, formül, K gövdesi (onda bir), K üssü, asit mi, mol kütlesi; 0 ise
// saf hâlde tartılarak kullanılmaz). Değerler ders kitaplarında verilen 25 °C
// değerleridir.
const _zayiflar = [
  ('asetik asit', 'CH₃COOH', 18, -5, true, 60),
  ('formik asit', 'HCOOH', 18, -4, true, 46),
  ('propanoik asit', 'CH₃CH₂COOH', 13, -5, true, 74),
  ('hipokloröz asit', 'HClO', 30, -8, true, 0),
  ('nitröz asit', 'HNO₂', 45, -4, true, 0),
  ('amonyak', 'NH₃', 18, -5, false, 17),
  ('metilamin', 'CH₃NH₂', 44, -4, false, 31),
  ('piridin', 'C₅H₅N', 17, -9, false, 79),
  ('laktik asit', 'CH₃CH(OH)COOH', 14, -4, true, 90),
  ('bütanoik asit', 'CH₃CH₂CH₂COOH', 15, -5, true, 88),
];

// log(d/10) değerlerinin yüzde biri (d = 10 … 99), iki ondalığa yuvarlanmış.
const _logYuzde = [
  0, 4, 8, 11, 15, 18, 20, 23, 26, 28, 30, 32, 34, 36, 38, 40, 41, 43, 45, //
  46, 48, 49, 51, 52, 53, 54, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67,
  68, 69, 70, 71, 72, 72, 73, 74, 75, 76, 76, 77, 78, 79, 79, 80, 81, 81, 82,
  83, 83, 84, 85, 85, 86, 86, 87, 88, 88, 89, 89, 90, 90, 91, 91, 92, 92, 93,
  93, 94, 94, 95, 95, 96, 96, 97, 97, 98, 98, 99, 99, 100,
];

// Seyreltme: (alınan hacim, son hacim) mL.
const _seyreltmeler = [
  (10, 100), (20, 100), (25, 100), (50, 100), (10, 50), (20, 200), (25, 250), //
  (50, 250), (50, 500), (100, 500), (100, 1000), (25, 500), (10, 250),
  (20, 500), (50, 1000), (40, 200), (25, 1000), (10, 200), (20, 250),
  (40, 500),
];
const _cozeltiHacmi = [100, 200, 250, 400, 500, 1000];

/// Sondaki sıfırları atılmış (gövde, üs) çifti.
(int, int) _sade(int pay, int us) {
  var p = pay, e = us;
  while (p != 0 && p % 10 == 0) {
    p ~/= 10;
    e++;
  }
  return (p, e);
}

/// pay / payda kesrini sonlu ondalık olarak (gövde, üs) yazar; sonlu değilse
/// ya da [enCok] anlamlı basamağı aşarsa null.
(int, int)? _bolum(int pay, int payda, int us, [int enCok = 3]) {
  var p = pay, e = us;
  for (var t = 0; t <= 8; t++) {
    if (p % payda == 0) {
      final s = _sade(p ~/ payda, e);
      return _anlamli(s.$1) <= enCok ? s : null;
    }
    p *= 10;
    e--;
  }
  return null;
}

// Zayıf tür durumları: (tür, x gövdesi (iki basamak), x üssü, C, sunuş, soru).
// x = gövde·10^üs; sunuş 0: doğrudan derişim, 1…20: seyreltme, 21…: kütle.
final _zayifDurumlari = () {
  final out = <(int, int, int, (int, int), int, int)>[];
  for (var z = 0; z < _zayiflar.length; z++) {
    final (_, _, km, ke, _, mk) = _zayiflar[z];
    for (var n = 1; n <= 8; n++) {
      for (var d = 10; d < 100; d++) {
        final xUs = -n - 1;
        // C = x²/K = d²·10^(2xUs) / (km·10^(ke−1))
        final c = _bolum(d * d, km, 2 * xUs - ke + 1);
        if (c == null) continue;
        final cd = _ondalik(c.$1, c.$2), xd = _ondalik(d, xUs);
        if (cd < 0.001 - 1e-12 || cd > 2 + 1e-12 || xd / cd > 0.05 + 1e-12) {
          continue;
        }
        // İyonlaşma yüzdesi 100·K/x sonlu ve kısa olmalı.
        final yuzdeVar = _bolum(100 * km, d, ke - 1 - xUs, 3) != null;
        for (var q = 0; q < 5; q++) {
          if (q == 3 && !yuzdeVar) continue;
          out.add((z, d, xUs, c, 0, q));
        }
        for (var s = 0; s < _seyreltmeler.length; s++) {
          final (v1, v2) = _seyreltmeler[s];
          final c0 = _bolum(c.$1 * v2, v1, c.$2);
          if (c0 == null || _ondalik(c0.$1, c0.$2) > 2 + 1e-12) continue;
          for (var q = 0; q < 4; q++) {
            if (q == 3 && !yuzdeVar) continue;
            out.add((z, d, xUs, c, 1 + s, q));
          }
        }
        if (mk > 0) {
          for (var h = 0; h < _cozeltiHacmi.length; h++) {
            final (mp, mu) = _sade(c.$1 * _cozeltiHacmi[h] * mk, c.$2 - 3);
            if (mu < -2 || _ondalik(mp, mu) > 200) continue;
            for (var q = 0; q < 4; q++) {
              if (q == 3 && !yuzdeVar) continue;
              out.add((z, d, xUs, c, 21 + h, q));
            }
          }
        }
      }
    }
  }
  return out;
}();

final _f12 = lmSirali(
  'km_zayif_asit',
  'Zayıf asit ve bazlarda pH ve iyonlaşma yüzdesi',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.analiz,
  (i) {
    final (z, d, xUs, c, sunus, q) =
        _zayifDurumlari[i * _zayifDurumlari.length ~/ lmAileBoyu];
    final (ad, f, km, ke, asit, mk) = _zayiflar[z];
    final kim = '$ad ($f)';
    final sabit = '$f için ${asit ? 'Ka' : 'Kb'} = ${_bilimsel(km, ke - 1)}';
    final iyon = asit ? 'H⁺' : 'OH⁻';
    final cYazi = _t(_ondalik(c.$1, c.$2), 5);
    final cd = _ondalik(c.$1, c.$2), xd = _ondalik(d, xUs);
    final kd = _ondalik(km, ke - 1);
    final xYazi = _bilimsel(d, xUs);
    // pX = n − log(d/10), yüzde birlik birimle.
    final n = -xUs - 1;
    final logY = _logYuzde[d - 10];
    final px = 100 * n - logY;
    final logNotu = d % 10 == 0 && d == 10
        ? ''
        : '; log ${_t(d / 10, 1)} = ${_t(logY / 100)}';
    String sunusYazi() {
      if (sunus == 0) {
        return '25 °C sıcaklıkta $cYazi mol/L derişimli $kim çözeltisi '
            'hazırlanıyor.';
      }
      if (sunus <= 20) {
        final (v1, v2) = _seyreltmeler[sunus - 1];
        final c0 = _bolum(c.$1 * v2, v1, c.$2)!;
        return '25 °C sıcaklıkta ${_t(_ondalik(c0.$1, c0.$2), 5)} mol/L '
            'derişimli $kim çözeltisinden $v1 mL alınıp hacmi $v2 mL olacak '
            'biçimde saf suyla seyreltiliyor.';
      }
      final v = _cozeltiHacmi[sunus - 21];
      final (mp, mu) = _sade(c.$1 * v * mk, c.$2 - 3);
      return '25 °C sıcaklıkta ${_t(_ondalik(mp, mu))} gram $kim suda '
          'çözülerek $v mL çözelti hazırlanıyor.';
    }

    String derisimYolu() {
      if (sunus == 0) return '';
      if (sunus <= 20) {
        final (v1, v2) = _seyreltmeler[sunus - 1];
        final c0 = _bolum(c.$1 * v2, v1, c.$2)!;
        return 'Seyreltme sonunda derişim '
            '${_t(_ondalik(c0.$1, c0.$2), 5)}·$v1/$v2 = $cYazi mol/L olur. ';
      }
      final v = _cozeltiHacmi[sunus - 21];
      final (mp, mu) = _sade(c.$1 * v * mk, c.$2 - 3);
      final mol = _sade(c.$1 * v, c.$2 - 3);
      return 'Çözünen madde ${_t(_ondalik(mp, mu))}/$mk = '
          '${_t(_ondalik(mol.$1, mol.$2), 8)} mol, derişim '
          '${_t(_ondalik(mol.$1, mol.$2), 8)}/${_t(v / 1000)} = $cYazi mol/L '
          'olur. ';
    }

    final kokYol =
        '${derisimYolu()}[$iyon] = √(${asit ? 'Ka' : 'Kb'}·C) = '
        '√(${_bilimsel(km, ke - 1)}·$cYazi) = √(${_bilimsel(d * d, 2 * xUs)}) '
        '= $xYazi mol/L olur.';
    if (q == 4) {
      return _say(
        '25 °C sıcaklıkta hazırlanan bir $kim çözeltisinde $iyon iyonu '
            'derişimi $xYazi mol/L olarak ölçülüyor. Buna göre çözeltideki $f '
            'derişimi kaç mol/L olur? ($sabit)',
        cd,
        [if (xd >= 0.001) xd, cd * 10, cd / 10, cd * 2, cd / 2],
        '[$iyon]² = ${asit ? 'Ka' : 'Kb'}·C olduğundan C = ($xYazi)² / '
            '(${_bilimsel(km, ke - 1)}) = ${_bilimsel(d * d, 2 * xUs)} / '
            '(${_bilimsel(km, ke - 1)}) = $cYazi mol/L bulunur.',
        birim: 'mol/L',
        basamak: 5,
      );
    }
    final giris = sunusYazi();
    if (q == 0) {
      return _bilimselSoru(
        '$giris Bu çözeltideki $iyon iyonu derişimi kaç mol/L olur? ($sabit)',
        (d, xUs),
        [kd * cd, cd, _karekok(kd), xd * 10],
        kokYol,
        birim: 'mol/L',
      );
    }
    if (q == 3) {
      final yuzde = 100 * xd / cd;
      String y(double v) => '%${_yz(v, 6)}';
      return secenekli(
        '$giris ${asit ? 'Asidin' : 'Bazın'} iyonlaşma yüzdesi kaçtır? '
            '($sabit)',
        '%${_t(yuzde, 6)}',
        [
          for (final v in [100 * kd / cd, 100 * xd, yuzde / 10, yuzde * 10])
            if (v.isFinite && v > 0.0005 && v < 1000) y(v),
          y(yuzde * 2),
          y(yuzde / 2),
        ],
        '$kokYol İyonlaşma yüzdesi ($xYazi / $cYazi)·100 = %${_t(yuzde, 6)} '
            'olur.',
      );
    }
    // q == 1: pH, q == 2: pOH.
    final phSoru = q == 1;
    final dogru = (asit == phSoru) ? px : 1400 - px;
    final adim = asit
        ? 'pH = −log($xYazi) = $n − ${_t(logY / 100)} = ${_t(px / 100)}'
        : 'pOH = −log($xYazi) = $n − ${_t(logY / 100)} = ${_t(px / 100)}';
    final son = asit == phSoru
        ? ''
        : (asit
              ? '; pOH = 14 − ${_t(px / 100)} = ${_t(dogru / 100)}'
              : '; pH = 14 − ${_t(px / 100)} = ${_t(dogru / 100)}');
    final hatali = asit == phSoru ? 100 * n : 1400 - 100 * n;
    return _say(
      '$giris Bu çözeltinin ${phSoru ? 'pH' : 'pOH'} değeri kaçtır? '
          '($sabit$logNotu)',
      dogru / 100,
      [
        hatali / 100,
        (asit == phSoru ? px + 2 * logY : 1400 - px - 2 * logY) / 100,
        (1400 - dogru) / 100,
        (asit == phSoru ? 2 * px : 1400 - 2 * px) / 100,
      ],
      '$kokYol $adim$son.',
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ──────────────────────── 13 · Tuz çözeltilerinde hidroliz ───────────────────

const _kuvvetliAsitler = {'HCl', 'HBr', 'HI', 'HNO₃', 'H₂SO₄'};
const _kuvvetliBazlar = {'NaOH', 'KOH', 'LiOH', 'Ca(OH)₂', 'Ba(OH)₂'};

// (tuz, oluşturan asit, oluşturan baz)
const _tuzlar = [
  ('NaCl', 'HCl', 'NaOH'),
  ('KCl', 'HCl', 'KOH'),
  ('NaBr', 'HBr', 'NaOH'),
  ('KBr', 'HBr', 'KOH'),
  ('NaI', 'HI', 'NaOH'),
  ('KI', 'HI', 'KOH'),
  ('NaNO₃', 'HNO₃', 'NaOH'),
  ('KNO₃', 'HNO₃', 'KOH'),
  ('LiCl', 'HCl', 'LiOH'),
  ('LiNO₃', 'HNO₃', 'LiOH'),
  ('LiBr', 'HBr', 'LiOH'),
  ('CaCl₂', 'HCl', 'Ca(OH)₂'),
  ('Ca(NO₃)₂', 'HNO₃', 'Ca(OH)₂'),
  ('BaCl₂', 'HCl', 'Ba(OH)₂'),
  ('Ba(NO₃)₂', 'HNO₃', 'Ba(OH)₂'),
  ('CaBr₂', 'HBr', 'Ca(OH)₂'),
  ('CH₃COONa', 'CH₃COOH', 'NaOH'),
  ('CH₃COOK', 'CH₃COOH', 'KOH'),
  ('NaF', 'HF', 'NaOH'),
  ('KF', 'HF', 'KOH'),
  ('NaNO₂', 'HNO₂', 'NaOH'),
  ('KNO₂', 'HNO₂', 'KOH'),
  ('Na₂CO₃', 'H₂CO₃', 'NaOH'),
  ('K₂CO₃', 'H₂CO₃', 'KOH'),
  ('NaClO', 'HClO', 'NaOH'),
  ('HCOONa', 'HCOOH', 'NaOH'),
  ('HCOOK', 'HCOOH', 'KOH'),
  ('Na₃PO₄', 'H₃PO₄', 'NaOH'),
  ('K₃PO₄', 'H₃PO₄', 'KOH'),
  ('Ca(CH₃COO)₂', 'CH₃COOH', 'Ca(OH)₂'),
  ('CH₃CH₂COONa', 'CH₃CH₂COOH', 'NaOH'),
  ('NH₄Cl', 'HCl', 'NH₃'),
  ('NH₄Br', 'HBr', 'NH₃'),
  ('NH₄I', 'HI', 'NH₃'),
  ('(NH₄)₂SO₄', 'H₂SO₄', 'NH₃'),
  ('CH₃NH₃Cl', 'HCl', 'CH₃NH₂'),
  ('CH₃NH₃Br', 'HBr', 'CH₃NH₂'),
  ('C₅H₅NHCl', 'HCl', 'C₅H₅N'),
];

String _tuzSinifi((String, String, String) t) {
  final ka = _kuvvetliAsitler.contains(t.$2);
  final kb = _kuvvetliBazlar.contains(t.$3);
  return ka && kb ? 'nötr' : (ka ? 'asidik' : 'bazik');
}

String _tuzNedeni((String, String, String) t) {
  final ka = _kuvvetliAsitler.contains(t.$2);
  final kb = _kuvvetliBazlar.contains(t.$3);
  return '${ka ? 'kuvvetli' : 'zayıf'} asit ${t.$2} ile '
      '${kb ? 'kuvvetli' : 'zayıf'} baz ${t.$3}';
}

const _phIliskisi = {'asidik': 'pH < 7', 'bazik': 'pH > 7', 'nötr': 'pH = 7'};

final _f13 = lmSirali(
  'km_tuz_hidroliz',
  'Tuz çözeltilerinin asitlik ve bazlık durumu',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final u = kombinasyon(_tuzlar, 3, i);
    final x = [for (final j in ucluDizilimler[i % 6]) u[j]];
    final sinif = [for (final e in x) _tuzSinifi(e)];
    final liste = _uc([for (final e in x) e.$1]);
    final aciklama =
        '${[for (var p = 0; p < 3; p++) '${x[p].$1}: ${_tuzNedeni(x[p])} tuzu, ${sinif[p]}'].join('; ')}.';
    if (i % 3 == 0) {
      const karisan = {
        'asidik': ['bazik', 'nötr'],
        'bazik': ['asidik', 'nötr'],
        'nötr': ['asidik', 'bazik'],
      };
      return _uclu(
        '$liste\nBu tuzların sulu çözeltilerinin 25 °C sıcaklıktaki asitlik-'
        'bazlık durumu numara sırasıyla hangi seçenekte doğru verilmiştir?',
        sinif,
        [for (var p = 0; p < 3; p++) karisan[sinif[p]]![(i ~/ 3 + p) % 2]],
        aciklama,
      );
    }
    final turler = <String>[];
    for (final s in sinif) {
      if (!turler.contains(s)) turler.add(s);
    }
    final hedef = turler[(i ~/ 3) % turler.length];
    var maske = 0;
    for (var p = 0; p < 3; p++) {
      if (sinif[p] == hedef) maske |= 1 << p;
    }
    final soru = i % 3 == 1
        ? 'Bu tuzlardan hangilerinin sulu çözeltisi $hedef özellik gösterir?'
        : 'Bu tuzlardan hangilerinin sulu çözeltisinde 25 °C sıcaklıkta '
              '${_phIliskisi[hedef]} olur?';
    return _hangileri('$liste\n$soru', maske, aciklama, i);
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ─────────────────── 14 · Bağ enerjilerinden tepkime entalpisi ────────────────

// Ortalama bağ enerjileri (kJ/mol).
const _bagEnerjisi = {
  'H–H': 436,
  'Cl–Cl': 243,
  'Br–Br': 193,
  'I–I': 151,
  'H–Cl': 432,
  'H–Br': 366,
  'H–I': 299,
  'O=O': 498,
  'O–H': 464,
  'C–H': 413,
  'C–C': 348,
  'C=C': 614,
  'C≡C': 839,
  'C=O': 799,
  'C–O': 358,
  'C–Cl': 328,
  'N≡N': 946,
  'N–H': 391,
  'O–O': 146,
  'C≡O': 1072,
  'N=O': 630,
};

// Moleküllerdeki bağlar; mol kütlesi (g/mol, tam sayı değilse 0) ve içerdiği
// elementler.
const _molekulBagi = <String, (Map<String, int>, int, String)>{
  'H₂': ({'H–H': 1}, 2, 'H: 1'),
  'Cl₂': ({'Cl–Cl': 1}, 71, 'Cl: 35,5'),
  'Br₂': ({'Br–Br': 1}, 160, 'Br: 80'),
  'I₂': ({'I–I': 1}, 254, 'I: 127'),
  'O₂': ({'O=O': 1}, 32, 'O: 16'),
  'N₂': ({'N≡N': 1}, 28, 'N: 14'),
  'HCl': ({'H–Cl': 1}, 0, ''),
  'HBr': ({'H–Br': 1}, 81, 'H: 1, Br: 80'),
  'HI': ({'H–I': 1}, 128, 'H: 1, I: 127'),
  'H₂O': ({'O–H': 2}, 18, 'H: 1, O: 16'),
  'NH₃': ({'N–H': 3}, 17, 'N: 14, H: 1'),
  'CH₄': ({'C–H': 4}, 16, 'C: 12, H: 1'),
  'CO₂': ({'C=O': 2}, 44, 'C: 12, O: 16'),
  'CO': ({'C≡O': 1}, 28, 'C: 12, O: 16'),
  'NO': ({'N=O': 1}, 30, 'N: 14, O: 16'),
  'C₂H₆': ({'C–C': 1, 'C–H': 6}, 30, 'C: 12, H: 1'),
  'C₂H₄': ({'C=C': 1, 'C–H': 4}, 28, 'C: 12, H: 1'),
  'C₂H₂': ({'C≡C': 1, 'C–H': 2}, 26, 'C: 12, H: 1'),
  'CH₃Cl': ({'C–H': 3, 'C–Cl': 1}, 0, ''),
  'C₂H₄Cl₂': ({'C–C': 1, 'C–H': 4, 'C–Cl': 2}, 99, 'C: 12, H: 1, Cl: 35,5'),
  'C₂H₅Cl': ({'C–C': 1, 'C–H': 5, 'C–Cl': 1}, 0, ''),
  'H₂O₂': ({'O–H': 2, 'O–O': 1}, 34, 'H: 1, O: 16'),
  'C₃H₈': ({'C–C': 2, 'C–H': 8}, 44, 'C: 12, H: 1'),
  'CH₃OH': ({'C–H': 3, 'C–O': 1, 'O–H': 1}, 32, 'C: 12, H: 1, O: 16'),
  'C₂H₅OH': (
    {'C–C': 1, 'C–H': 5, 'C–O': 1, 'O–H': 1},
    46,
    'C: 12, H: 1, O: 16',
  ),
};

// Gaz fazında tepkimeler: (girenler, ürünler).
const _bagTepkimeleri = [
  ([(1, 'H₂'), (1, 'Cl₂')], [(2, 'HCl')]),
  ([(1, 'H₂'), (1, 'Br₂')], [(2, 'HBr')]),
  ([(1, 'H₂'), (1, 'I₂')], [(2, 'HI')]),
  ([(2, 'H₂'), (1, 'O₂')], [(2, 'H₂O')]),
  ([(1, 'N₂'), (3, 'H₂')], [(2, 'NH₃')]),
  ([(1, 'CH₄'), (2, 'O₂')], [(1, 'CO₂'), (2, 'H₂O')]),
  ([(1, 'C₂H₄'), (1, 'H₂')], [(1, 'C₂H₆')]),
  ([(1, 'C₂H₂'), (2, 'H₂')], [(1, 'C₂H₆')]),
  ([(1, 'C₂H₂'), (1, 'H₂')], [(1, 'C₂H₄')]),
  ([(1, 'CH₄'), (1, 'Cl₂')], [(1, 'CH₃Cl'), (1, 'HCl')]),
  ([(1, 'C₂H₄'), (1, 'Cl₂')], [(1, 'C₂H₄Cl₂')]),
  ([(1, 'C₂H₄'), (1, 'HCl')], [(1, 'C₂H₅Cl')]),
  ([(2, 'NH₃')], [(1, 'N₂'), (3, 'H₂')]),
  ([(2, 'H₂O₂')], [(2, 'H₂O'), (1, 'O₂')]),
  ([(2, 'CO'), (1, 'O₂')], [(2, 'CO₂')]),
  ([(2, 'C₂H₆'), (7, 'O₂')], [(4, 'CO₂'), (6, 'H₂O')]),
  ([(1, 'C₃H₈'), (5, 'O₂')], [(3, 'CO₂'), (4, 'H₂O')]),
  ([(2, 'CH₃OH'), (3, 'O₂')], [(2, 'CO₂'), (4, 'H₂O')]),
  ([(1, 'C₂H₅OH'), (3, 'O₂')], [(2, 'CO₂'), (3, 'H₂O')]),
  ([(1, 'C₂H₄'), (3, 'O₂')], [(2, 'CO₂'), (2, 'H₂O')]),
  ([(2, 'C₂H₂'), (5, 'O₂')], [(4, 'CO₂'), (2, 'H₂O')]),
  ([(1, 'CO₂'), (4, 'H₂')], [(1, 'CH₄'), (2, 'H₂O')]),
  ([(1, 'N₂'), (1, 'O₂')], [(2, 'NO')]),
  ([(2, 'HCl')], [(1, 'H₂'), (1, 'Cl₂')]),
  ([(1, 'C₂H₆')], [(1, 'C₂H₄'), (1, 'H₂')]),
];

String _terimYaz(List<(int, String)> t, [String hal = '(g)']) =>
    [for (final (k, f) in t) '${k == 1 ? '' : k}$f$hal'].join(' + ');

/// Tepkimede kırılan ve oluşan bağların sayısı.
Map<String, int> _bagSayilari(List<(int, String)> t) {
  final out = <String, int>{};
  for (final (k, f) in t) {
    _molekulBagi[f]!.$1.forEach((b, n) => out[b] = (out[b] ?? 0) + k * n);
  }
  return out;
}

int _bagToplami(Map<String, int> s) {
  var t = 0;
  s.forEach((b, n) => t += n * _bagEnerjisi[b]!);
  return t;
}

String _bagToplamYazi(Map<String, int> s) => [
  for (final e in s.entries)
    '${e.value == 1 ? '' : '${e.value}·'}${_bagEnerjisi[e.key]}',
].join(' + ');

final _f14 = lmAile(
  'km_bag_enerjisi',
  'Bağ enerjilerinden tepkime entalpisinin hesaplanması',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final (giren, urun) = _bagTepkimeleri[a];
    final denklem = '${_terimYaz(giren)} → ${_terimYaz(urun)}';
    final kirilan = _bagSayilari(giren), olusan = _bagSayilari(urun);
    final bk = _bagToplami(kirilan), bo = _bagToplami(olusan);
    final dh = bk - bo;
    final ekzo = dh < 0;
    final turler = [
      for (final (k, f) in giren) (k, f, true),
      for (final (k, f) in urun) (k, f, false),
    ];
    // Katsayıları yok sayma hatası: her molekül bir kez sayılır.
    var yanlisDh = 0;
    for (final (_, f) in giren) {
      yanlisDh += _bagToplami(_molekulBagi[f]!.$1);
    }
    for (final (_, f) in urun) {
      yanlisDh -= _bagToplami(_molekulBagi[f]!.$1);
    }
    final dhYol =
        'Kırılan bağlar: ${_bagToplamYazi(kirilan)} = $bk kJ; oluşan bağlar: '
        '${_bagToplamYazi(olusan)} = $bo kJ. ΔH = $bk − $bo = ${_isaretli(dh)} kJ '
        'olur.';
    if (c < 5) {
      final kutleli = c >= 3;
      final adaylar = kutleli
          ? [
              for (final t in turler)
                if (_molekulBagi[t.$2]!.$2 > 0) t,
            ]
          : turler;
      final secim = kutleli ? c - 3 : c;
      final (k, f, girenMi) = adaylar[secim % adaylar.length];
      final j = b + 1 + 20 * (secim ~/ adaylar.length);
      final mol = k * j / 20, q = dh.abs() * j / 20;
      final (_, mk, kut) = _molekulBagi[f]!;
      final miktar = kutleli ? '${_t(mol * mk)} gram $f' : '${_t(mol)} mol $f';
      final fiil = girenMi ? 'harcandığında' : 'oluştuğunda';
      return _say(
        '$denklem tepkimesi için bağ enerjileri (kJ/mol): '
            '${[
              for (final e in {...kirilan.keys, ...olusan.keys}) '$e: ${_bagEnerjisi[e]}',
            ].join(', ')}. '
            'Buna göre $miktar $fiil ${ekzo ? 'açığa çıkan' : 'alınan'} ısı kaç '
            'kJ olur?${kutleli ? ' ($kut)' : ''}',
        q,
        [
          dh.abs() * mol,
          bk * mol / k,
          bo * mol / k,
          yanlisDh.abs() * mol / k,
          dh.abs() / k,
        ],
        '$dhYol ${kutleli ? '${_t(mol * mk)} gram $f ${_t(mol)} mol eder. ' : ''}'
            'Bu değer denklemdeki $k mol $f içindir; ${_t(mol)} mol için '
            '${dh.abs()}·${_t(mol)}${k == 1 ? '' : '/$k'} = ${_t(q)} kJ ısı '
            '${ekzo ? 'açığa çıkar' : 'alınır'}.',
        birim: 'kJ',
      );
    }
    // Bilinmeyen bağ enerjisi.
    final baglar = [
      for (final e in {...kirilan.keys, ...olusan.keys})
        if ((kirilan[e] ?? 0) != (olusan[e] ?? 0)) e,
    ];
    final r = c - 5;
    final bilinmeyen = baglar[r % baglar.length];
    final (k, f, girenMi) = turler.firstWhere(
      (t) => !t.$3,
      orElse: () => turler.first,
    );
    final j = b + 1 + 20 * (r ~/ baglar.length);
    final mol = k * j / 20, q = dh.abs() * j / 20;
    final net = (kirilan[bilinmeyen] ?? 0) - (olusan[bilinmeyen] ?? 0);
    final x = _bagEnerjisi[bilinmeyen]!;
    final digerFark = dh - net * x;
    int coz(num d) => ((d - digerFark) / net).round();
    final yanlislar = <num>[
      (-dh - digerFark) / net,
      (dh - digerFark) / net.sign,
      ((ekzo ? -q : q) - digerFark) / net,
    ];
    final digerleri = [
      for (final e in {...kirilan.keys, ...olusan.keys})
        if (e != bilinmeyen) '$e: ${_bagEnerjisi[e]}',
    ];
    final kb = kirilan[bilinmeyen] ?? 0, kf = olusan[bilinmeyen] ?? 0;
    final b0 = bk - kb * x, f0 = bo - kf * x;
    String parca(int sabit, int kat) =>
        kat == 0 ? '$sabit' : '$sabit + ${kat == 1 ? '' : kat}x';
    return _say(
      '$denklem tepkimesinde ${_t(mol)} mol $f ${girenMi ? 'harcandığında' : 'oluştuğunda'} '
          '${_t(q)} kJ ısı ${ekzo ? 'açığa çıkmaktadır' : 'alınmaktadır'}. Bağ '
          'enerjileri (kJ/mol): ${digerleri.join(', ')}. Buna göre $bilinmeyen bağının '
          'enerjisi kaç kJ/mol olur?',
      coz(dh),
      [for (final y in yanlislar) y],
      'Denklemdeki $k mol $f için ΔH = ${_isaretli(dh)} kJ olur '
          '(${_t(q)}·$k/${_t(mol)}). $bilinmeyen bağının enerjisi x ile '
          'gösterilirse ΔH = Σ(kırılan) − Σ(oluşan) eşitliği '
          '${_isaretli(dh)} = ${parca(b0, kb)} − ${kf == 0 ? '$f0' : '(${parca(f0, kf)})'} olur; buradan '
          'x = $x kJ/mol bulunur.',
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

String _isaretli(int x) => x > 0 ? '+$x' : (x < 0 ? '−${-x}' : '0');

// ─────────────────────────── 15 · Le Chatelier ilkesi ────────────────────────

// (girenler, ürünler, ekzotermik mi): türler (katsayı, formül, gaz mı).
const _dengeTepkimeleri = [
  ([(1, 'N₂', true), (3, 'H₂', true)], [(2, 'NH₃', true)], true),
  ([(2, 'SO₂', true), (1, 'O₂', true)], [(2, 'SO₃', true)], true),
  ([(1, 'N₂O₄', true)], [(2, 'NO₂', true)], false),
  (
    [(1, 'CO', true), (1, 'H₂O', true)],
    [(1, 'CO₂', true), (1, 'H₂', true)],
    true,
  ),
  ([(1, 'H₂', true), (1, 'I₂', true)], [(2, 'HI', true)], true),
  ([(1, 'CaCO₃', false)], [(1, 'CaO', false), (1, 'CO₂', true)], false),
  (
    [(1, 'C', false), (1, 'H₂O', true)],
    [(1, 'CO', true), (1, 'H₂', true)],
    false,
  ),
  ([(1, 'N₂', true), (1, 'O₂', true)], [(2, 'NO', true)], false),
  ([(2, 'NO', true), (1, 'O₂', true)], [(2, 'NO₂', true)], true),
  ([(1, 'CO', true), (2, 'H₂', true)], [(1, 'CH₃OH', true)], true),
  (
    [(1, 'CH₄', true), (1, 'H₂O', true)],
    [(1, 'CO', true), (3, 'H₂', true)],
    false,
  ),
  ([(1, 'C', false), (1, 'CO₂', true)], [(2, 'CO', true)], false),
  ([(1, 'NH₄Cl', false)], [(1, 'NH₃', true), (1, 'HCl', true)], false),
  ([(2, 'NO₂', true)], [(1, 'N₂O₄', true)], true),
  ([(2, 'HI', true)], [(1, 'H₂', true), (1, 'I₂', true)], false),
  ([(2, 'SO₃', true)], [(2, 'SO₂', true), (1, 'O₂', true)], false),
  ([(2, 'NH₃', true)], [(1, 'N₂', true), (3, 'H₂', true)], false),
  (
    [(1, 'H₂', true), (1, 'CO₂', true)],
    [(1, 'H₂O', true), (1, 'CO', true)],
    false,
  ),
  ([(2, 'CO', true)], [(1, 'C', false), (1, 'CO₂', true)], true),
  ([(1, 'MgCO₃', false)], [(1, 'MgO', false), (1, 'CO₂', true)], false),
  ([(1, 'C₂H₄', true), (1, 'H₂', true)], [(1, 'C₂H₆', true)], true),
  ([(1, 'C₂H₆', true)], [(1, 'C₂H₄', true), (1, 'H₂', true)], false),
  (
    [(1, 'CO₂', true), (4, 'H₂', true)],
    [(1, 'CH₄', true), (2, 'H₂O', true)],
    true,
  ),
  ([(1, 'CH₃OH', true)], [(1, 'CO', true), (2, 'H₂', true)], false),
];

String _dengeTerim(List<(int, String, bool)> t) =>
    [for (final (k, f, g) in t) '${k == 1 ? '' : k}$f(${g ? 'g' : 'k'})']
        .join(' + ');

String _dengeDenklem(int r) {
  final (giren, urun, _) = _dengeTepkimeleri[r];
  return '${_dengeTerim(giren)} ⇌ ${_dengeTerim(urun)}';
}

int _gazMol(List<(int, String, bool)> t) {
  var s = 0;
  for (final (k, _, g) in t) {
    if (g) s += k;
  }
  return s;
}

// Değişiklik: (tür, madde): tür 0 T↑, 1 T↓, 2 V↓, 3 V↑, 4 gaz ekleme,
// 5 gaz çekme, 6 katı ekleme, 7 katalizör, 8 soy gaz.
List<(int, String)> _degisiklikler(int r) {
  final (giren, urun, _) = _dengeTepkimeleri[r];
  final hepsi = [...giren, ...urun];
  return [
    (0, ''),
    (1, ''),
    (2, ''),
    (3, ''),
    for (final (_, f, g) in hepsi)
      if (g) ...[(4, f), (5, f)],
    for (final (_, f, g) in hepsi)
      if (!g) (6, f),
    (7, ''),
    (8, ''),
  ];
}

/// (kayma: +1 ürünler, −1 girenler, 0 kaymaz; Kc: +1 artar, −1 azalır, 0).
(int, int) _etki(int r, (int, String) d) {
  final (giren, urun, ekzo) = _dengeTepkimeleri[r];
  final dn = _gazMol(urun) - _gazMol(giren);
  final girenMi = giren.any((t) => t.$2 == d.$2);
  return switch (d.$1) {
    0 => ekzo ? (-1, -1) : (1, 1),
    1 => ekzo ? (1, 1) : (-1, -1),
    2 => (dn < 0 ? 1 : (dn > 0 ? -1 : 0), 0),
    3 => (dn < 0 ? -1 : (dn > 0 ? 1 : 0), 0),
    4 => (girenMi ? 1 : -1, 0),
    5 => (girenMi ? -1 : 1, 0),
    _ => (0, 0),
  };
}

String _degisiklikMastar((int, String) d) => switch (d.$1) {
  0 => 'sıcaklığı artırmak',
  1 => 'sıcaklığı düşürmek',
  2 => 'sabit sıcaklıkta kabın hacmini küçültmek',
  3 => 'sabit sıcaklıkta kabın hacmini büyütmek',
  4 => 'sabit hacim ve sıcaklıkta kaba bir miktar ${d.$2} gazı eklemek',
  5 => 'sabit hacim ve sıcaklıkta kaptan bir miktar ${d.$2} gazı çekmek',
  6 => 'kaba bir miktar daha ${d.$2} katısı eklemek',
  7 => 'kaba katalizör eklemek',
  _ => 'sabit hacim ve sıcaklıkta kaba bir miktar He gazı eklemek',
};

String _degisiklikKosul((int, String) d) => switch (d.$1) {
  0 => 'Sıcaklık artırılırsa',
  1 => 'Sıcaklık düşürülürse',
  2 => 'Sabit sıcaklıkta kabın hacmi küçültülürse',
  3 => 'Sabit sıcaklıkta kabın hacmi büyütülürse',
  4 => 'Sabit hacim ve sıcaklıkta kaba bir miktar ${d.$2} gazı eklenirse',
  5 => 'Sabit hacim ve sıcaklıkta kaptan bir miktar ${d.$2} gazı çekilirse',
  6 => 'Kaba bir miktar daha ${d.$2} katısı eklenirse',
  7 => 'Kaba katalizör eklenirse',
  _ => 'Sabit hacim ve sıcaklıkta kaba bir miktar He gazı eklenirse',
};

String _kaymaYazi(int k) => k > 0
    ? 'ürünler yönüne kayar'
    : (k < 0 ? 'girenler yönüne kayar' : 'denge kaymaz');

String _kcYazi(int k) =>
    k > 0 ? 'Kc artar' : (k < 0 ? 'Kc azalır' : 'Kc değişmez');

String _etkiNedeni(int r, (int, String) d) {
  final (giren, urun, ekzo) = _dengeTepkimeleri[r];
  final ng = _gazMol(giren), nu = _gazMol(urun);
  return switch (d.$1) {
    0 || 1 =>
      'tepkime ${ekzo ? 'ekzotermik' : 'endotermik'} olduğundan sıcaklık '
          'değişimi dengeyi ${_kaymaYazi(_etki(r, d).$1).replaceFirst(' kayar', '')} '
          'kaydırır ve Kc yalnız sıcaklıkla değişir',
    2 || 3 =>
      ng == nu
          ? 'gaz mol sayıları eşit olduğundan (girenlerde $ng, ürünlerde $nu) '
                'hacim değişimi dengeyi etkilemez'
          : 'gaz mol sayıları girenlerde $ng, ürünlerde $nu; hacim '
                '${d.$1 == 2 ? 'küçülünce denge gaz mol sayısının az' : 'büyüyünce denge gaz mol sayısının çok'} '
                'olduğu yöne kayar',
    4 => 'denge eklenen ${d.$2} gazını harcayan yöne kayar',
    5 => 'denge çekilen ${d.$2} gazını yeniden oluşturan yöne kayar',
    6 => 'katıların derişimi sabit kabul edildiğinden katı eklemek dengeyi etkilemez',
    7 =>
      'katalizör ileri ve geri tepkimeyi eşit hızlandırır, dengeyi kaydırmaz',
    _ => 'sabit hacimde soy gaz eklemek derişimleri değiştirmediğinden denge kaymaz',
  };
}

// Tek değişiklik soruları ve üçlü değişiklik soruları.
final _leChatelierTekli = [
  for (var r = 0; r < _dengeTepkimeleri.length; r++)
    for (final d in _degisiklikler(r)) (r, d),
];

final _leChatelierUclu = () {
  final out = <(int, List<int>, int, int)>[];
  for (var r = 0; r < _dengeTepkimeleri.length; r++) {
    final ds = _degisiklikler(r);
    final secim = _secimler([for (var j = 0; j < ds.length; j++) j], 3);
    for (var s = 0; s < secim.length; s++) {
      for (var q = 0; q < 4; q++) {
        var maske = 0;
        for (var p = 0; p < 3; p++) {
          final (kay, kc) = _etki(r, ds[secim[s][p]]);
          final uygun = switch (q) {
            0 => kay > 0,
            1 => kay < 0,
            2 => kc != 0,
            _ => kay == 0,
          };
          if (uygun) maske |= 1 << p;
        }
        if (maske != 0) out.add((r, secim[s], q, maske));
      }
    }
  }
  return out;
}();

const _leChatelierSoru = [
  'dengeyi ürünler yönüne kaydırır',
  'dengeyi girenler yönüne kaydırır',
  'derişimler cinsinden denge sabitinin (Kc) değerini değiştirir',
  'dengenin konumunu değiştirmez',
];

final _f15 = lmSirali(
  'km_le_chatelier',
  'Le Chatelier ilkesi: dengeye etki eden etmenler',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.analiz,
  (i) {
    final tekli = _leChatelierTekli.length;
    if (i < tekli) {
      final (r, d) = _leChatelierTekli[i];
      final (kay, kc) = _etki(r, d);
      final ekzo = _dengeTepkimeleri[r].$3;
      String yaz(int a, int b) => '${_kaymaYazi(a)}, ${_kcYazi(b)}';
      return secenekli(
        'Kapalı bir kapta ${_dengeDenklem(r)} tepkimesi dengededir '
            '(ΔH ${ekzo ? '<' : '>'} 0). ${_degisiklikKosul(d)} denge hangi yöne '
            'kayar ve derişimler cinsinden denge sabiti (Kc) nasıl değişir?',
        yaz(kay, kc),
        [
          if (kc == 0 && kay != 0) yaz(kay, kay),
          if (kay != 0) yaz(-kay, kc),
          if (kc != 0) yaz(kay, 0),
          yaz(-kay, -kc),
          if (kay == 0) ...[yaz(1, 0), yaz(-1, 0), yaz(1, 1)],
          yaz(0, 0),
          yaz(1, 1),
          yaz(-1, -1),
        ],
        '${_bas(_etkiNedeni(r, d))}: ${yaz(kay, kc)}.',
      );
    }
    final j = i - tekli;
    final n = lmAileBoyu - tekli;
    final (r, secim, q, maske0) =
        _leChatelierUclu[j * _leChatelierUclu.length ~/ n];
    final ds = _degisiklikler(r);
    final dz = ucluDizilimler[j % 6];
    final sira = [for (final p in dz) secim[p]];
    var maske = 0;
    for (var p = 0; p < 3; p++) {
      if ((maske0 >> dz[p]) & 1 == 1) maske |= 1 << p;
    }
    final ekzo = _dengeTepkimeleri[r].$3;
    return _hangileri(
      'Kapalı bir kapta ${_dengeDenklem(r)} tepkimesi dengededir '
          '(ΔH ${ekzo ? '<' : '>'} 0). Bu sistemde yapılan\n'
          '${_uc([for (final s in sira) _degisiklikMastar(ds[s])])}\n'
          'işlemlerinden hangileri ${_leChatelierSoru[q]}?',
      maske,
      '${[for (var p = 0; p < 3; p++) () {
          final (kay, kc) = _etki(r, ds[sira[p]]);
          return '${_romaRakam[p]}: ${_kaymaYazi(kay)}${kc == 0 ? '' : ', ${_kcYazi(kc)}'}';
        }()].join('; ')}.',
      i,
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ─────────────────── 16 · Kp–Kc ilişkisi ve denge sabitinin dönüşümü ──────────

const _kelvinler = [300, 400, 500, 600, 800, 1000];

// Verilen denge sabitleri (yüzde birlik birimle).
const _kpKcDegerleri = [
  1, 2, 4, 5, 10, 20, 25, 40, 50, 80, 150, 200, 250, 400, 500, 800, 15, 30, //
  60, 120,
];

final _kpKcDurumlari = [
  for (var r = 0; r < _dengeTepkimeleri.length; r++)
    if (_gazMol(_dengeTepkimeleri[r].$2) != _gazMol(_dengeTepkimeleri[r].$1))
      for (var t = 0; t < _kelvinler.length; t++)
        for (var k = 0; k < _kpKcDegerleri.length; k++) (r, t, k),
];

// Dönüşümler: 0 ters, 1 iki katı, 2 yarısı, 3 ters ve iki katı, 4 ters ve
// yarısı. Her dönüşüm için K = gövde·10^üs değerleri kesin sonuç verir.
const _donusumGovdeleri = [
  [10, 20, 40, 50, 80, 25, 125, 16],
  [10, 12, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90],
  [10, 12, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90],
  [10, 20, 40, 50, 80, 25, 125],
  [10, 20, 40, 50, 80, 25, 125],
];

final _donusumDurumlari = [
  for (var r = 0; r < _dengeTepkimeleri.length; r++)
    for (var d = 0; d < 5; d++)
      for (final g in _donusumGovdeleri[d])
        for (var e = -3; e <= 3; e++) (r, d, g, e),
];

/// Katsayıları [pay]/[payda] ile çarpılmış terim listesi.
String _katsayiliTerim(List<(int, String, bool)> t, int pay, int payda) => [
  for (final (k, f, g) in t)
    () {
      final kk = kesir(k * pay, payda);
      return '${kk == '1' ? '' : (kk.contains('/') ? '$kk ' : kk)}$f(${g ? 'g' : 'k'})';
    }(),
].join(' + ');

/// (gövde, üs) çiftini, gövdesi 10'un kuvveti olmayan sayıların 1, 2 basamaklı
/// gövdeleriyle tam kesin biçimde kurar: gövde onda bir birimlidir.
(int, int) _govdeUs(int g, int e) => _sade(g, e - 1);

final _f16 = lmSirali(
  'km_kc_kp',
  'Kp ile Kc ilişkisi ve denge sabitinin dönüşümü',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.uygulama,
  (i) {
    final ab = _kpKcDurumlari.length;
    if (i < ab) {
      final (r, ti, ki) = _kpKcDurumlari[i];
      final (giren, urun, _) = _dengeTepkimeleri[r];
      final dn = _gazMol(urun) - _gazMol(giren);
      var tumu = 0;
      for (final (k, _, _) in urun) {
        tumu += k;
      }
      for (final (k, _, _) in giren) {
        tumu -= k;
      }
      final tk = _kelvinler[ti], tc = tk - 273;
      final rt = 0.082 * tk;
      final kv = _kpKcDegerleri[ki] / 100;
      final us = dn.abs();
      num kuvvet(num x, int n) {
        num p = 1;
        for (var j = 0; j < n; j++) {
          p *= x;
        }
        return p;
      }

      final cevap = kv * kuvvet(rt, us);
      final kpVerili = dn < 0;
      final verilen = kpVerili ? 'Kp' : 'Kc', istenen = kpVerili ? 'Kc' : 'Kp';
      final tumUs = tumu.abs();
      return _say(
        '${_dengeDenklem(r)} tepkimesinin $tc °C sıcaklıktaki '
            '${kpVerili ? 'kısmi basınçlar' : 'derişimler'} cinsinden denge sabiti '
            '$verilen = ${_t(kv)} olarak verilmiştir. Buna göre aynı sıcaklıkta '
            '${kpVerili ? 'derişimler' : 'kısmi basınçlar'} cinsinden denge sabiti '
            '($istenen) kaçtır? (R = 0,082 L·atm/(mol·K))',
        cevap,
        [
          kv * kuvvet(0.082 * tc, us),
          if (kv / kuvvet(rt, us) >= 0.001) kv / kuvvet(rt, us),
          kv * kuvvet(8.314 * tk, us),
          if (tumu != dn && tumu != 0)
            (tumu.sign == dn.sign
                ? kv * kuvvet(rt, tumUs)
                : kv / kuvvet(rt, tumUs)),
          if (us == 2) kv * rt,
          kv,
        ],
        'Gaz katsayılarına göre Δn = ${_gazMol(urun)} − ${_gazMol(giren)} = '
            '${_yz(dn)}${tumu != dn ? ' (katılar hesaba katılmaz)' : ''}. '
            'T = $tc + 273 = $tk K, RT = 0,082·$tk = ${_t(rt, 1)}. '
            '${kpVerili ? 'Kc = Kp·(RT)${us == 1 ? '' : _ust(us)}' : 'Kp = Kc·(RT)${us == 1 ? '' : _ust(us)}'} = '
            '${_t(kv)}·${us == 1 ? _t(rt, 1) : '(${_t(rt, 1)})${_ust(us)}'} = ${_t(cevap, 4)} bulunur.',
        basamak: 4,
      );
    }
    final j = i - ab;
    final n = lmAileBoyu - ab;
    final (r, d, g, e) = _donusumDurumlari[j * _donusumDurumlari.length ~/ n];
    final (giren, urun, _) = _dengeTepkimeleri[r];
    // K = g·10^(e−1); yarım dönüşümlerde K = g²·10^(2e−2).
    final kare = d == 2 || d == 4;
    final kVer = kare ? _sade(g * g, 2 * e - 2) : _govdeUs(g, e);
    final kd = _ondalik(kVer.$1, kVer.$2);
    final (yeniGiren, yeniUrun) = d == 0 || d == 3 || d == 4
        ? (urun, giren)
        : (giren, urun);
    final (pay, payda) = switch (d) {
      1 || 3 => (2, 1),
      2 || 4 => (1, 2),
      _ => (1, 1),
    };
    final yeni =
        '${_katsayiliTerim(yeniGiren, pay, payda)} ⇌ ${_katsayiliTerim(yeniUrun, pay, payda)}';
    // Kesin yanıt: (gövde, üs).
    final (int, int) cevap = switch (d) {
      0 => _bolum(1, kVer.$1, -kVer.$2, 6)!,
      1 => _sade(kVer.$1 * kVer.$1, 2 * kVer.$2),
      2 => _govdeUs(g, e),
      3 => _bolum(1, kVer.$1 * kVer.$1, -2 * kVer.$2, 6)!,
      _ => _bolum(10, g, -e, 6)!,
    };
    final kural = switch (d) {
      0 => 'Tepkime ters çevrilince denge sabitinin tersi alınır (K′ = 1/K)',
      1 =>
        'Katsayılar 2 ile çarpılınca denge sabitinin karesi alınır (K′ = K²)',
      2 =>
        'Katsayılar yarıya indirilince denge sabitinin karekökü alınır '
            '(K′ = √K)',
      3 =>
        'Tepkime ters çevrilip katsayıları 2 ile çarpılınca denge sabiti '
            'K′ = 1/K² olur',
      _ =>
        'Tepkime ters çevrilip katsayıları yarıya indirilince denge sabiti '
            'K′ = 1/√K olur',
    };
    return _bilimselSoru(
      'Belirli bir sıcaklıkta ${_dengeTerim(giren)} ⇌ ${_dengeTerim(urun)} '
          'tepkimesinin derişimler cinsinden denge sabiti Kc = '
          '${_bilimsel(kVer.$1, kVer.$2)} olarak verilmiştir. Buna göre aynı '
          'sıcaklıkta $yeni tepkimesinin derişimler cinsinden denge sabiti '
          'kaçtır?',
      cevap,
      switch (d) {
        0 => [kd, kd * kd, _karekok(kd)],
        1 => [2 * kd, kd, _karekok(kd)],
        2 => [kd / 2, kd, kd * kd],
        3 => [1 / (2 * kd), kd * kd, 1 / kd],
        _ => [2 / kd, _karekok(kd), 1 / kd],
      },
      '$kural; K′ = ${_bilimsel(cevap.$1, cevap.$2)}.',
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ───────────────────── 17 · Alkan, alken ve alkin genel formülleri ───────────

const _hidrokarbonSinifi = ['alkan', 'alken', 'alkin'];
const _genelFormul = ['CnH2n+2', 'CnH2n', 'CnH2n−2'];

/// a → (sınıf, karbon sayısı): 9 alkan (1–9 C), 8 alken ve 8 alkin (2–9 C).
(int, int) _hidrokarbon(int a) =>
    a < 9 ? (0, a + 1) : (a < 17 ? (1, a - 7) : (2, a - 15));

int _hSayisi(int sinif, int n) => 2 * n + 2 - 2 * sinif;

String _hkFormul(int n, int h) => 'C${n == 1 ? '' : _alt(n)}H${_alt(h)}';

final _f17 = lmAile(
  'km_organik_formul',
  'Alkan, alken ve alkinlerde genel formül ve yanma',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (k, n) = _hidrokarbon(a);
    final h = _hSayisi(k, n), mk = 12 * n + h;
    final sinif = _hidrokarbonSinifi[k];
    final f = _hkFormul(n, h);
    // 1,0 mol atlanır: yanıt köke yazılan karbon sayısıyla çakışmasın.
    final xo = b + 1 + (b >= 9 ? 1 : 0);
    final x = xo / 10;
    final co2 = x * n, h2o = x * h / 2, o2 = x * (n + h / 4);
    // Öteki sınıfların hidrojen sayıları (yanlış genel formül).
    final hY = [
      for (var s = 0; s < 3; s++)
        if (s != k && _hSayisi(s, n) > 0) _hSayisi(s, n),
    ];
    final bilgi =
        '${const ['Alkanların', 'Alkenlerin', 'Alkinlerin'][k]} genel formülü '
        '${_genelFormul[k]} olduğundan';
    String yanma(String verilen) =>
        'Bir $sinif bileşiğinin ${_t(x)} molü tamamen yakıldığında $verilen';
    // Yanıt köke yazılan bir sayıyla çakışırsa aynı nicelik gram olarak sorulur.
    AdvancedItem soru(
      String kok,
      String nicelik,
      double deger,
      double molKutle,
      List<double> hatalar,
      String cozum,
      List<double> yazilan,
    ) {
      final cakisir = yazilan.any((y) => (y - deger).abs() < 1e-9);
      if (!cakisir) {
        return _say(
          '$kok kaç mol $nicelik oluşur?'.replaceFirst(
            'kaç mol O₂ oluşur?',
            'kaç mol O₂ harcanır?',
          ),
          deger,
          hatalar,
          cozum,
          birim: 'mol',
        );
      }
      final g = deger * molKutle;
      return _say(
        '$kok kaç gram $nicelik ${nicelik == 'O₂' ? 'harcanır' : 'oluşur'}? '
            '(${nicelik == 'H₂O' ? 'H: 1, O: 16' : (nicelik == 'CO₂' ? 'C: 12, O: 16' : 'O: 16')})',
        g,
        [for (final e in hatalar) e * molKutle],
        '$cozum Bu ${_t(deger)} mol $nicelik ${_t(g)} gram eder.',
        birim: 'g',
      );
    }

    switch (c) {
      case 0 || 1:
        final kok =
            '${yanma('${_t(co2)} mol CO₂ oluşuyor.')} Buna göre bu yanmada';
        final yol =
            '$bilgi ${_t(x)} mol bileşikten ${_t(co2)} mol CO₂ oluşması n = $n '
            '($f) demektir.';
        if (c == 0) {
          return soru(
            kok,
            'H₂O',
            h2o,
            18,
            [for (final hh in hY) x * hh / 2, x * h, co2],
            '$yol 1 mol $f yanınca ${h ~/ 2} mol H₂O oluşur; ${_t(x)} mol için '
                '${_t(h2o)} mol H₂O oluşur.',
            [x, co2],
          );
        }
        return soru(
          kok,
          'O₂',
          o2,
          32,
          [
            x * (2 * n + h / 2),
            x * (n + h / 2),
            for (final hh in hY) x * (n + hh / 4),
          ],
          '$yol $f + ${_t(n + h / 4)} O₂ → $n CO₂ + ${h ~/ 2} H₂O denklemine '
              'göre ${_t(x)}·${_t(n + h / 4)} = ${_t(o2)} mol O₂ harcanır.',
          [x, co2],
        );
      case 2 || 3:
        final kok =
            '${yanma('${_t(h2o)} mol H₂O oluşuyor.')} Buna göre bu yanmada';
        final yol =
            '$bilgi ${_t(x)} mol bileşikten ${_t(h2o)} mol H₂O oluşması '
            'molekülde $h hidrojen, yani $n karbon ($f) bulunduğunu gösterir.';
        if (c == 2) {
          return soru(
            kok,
            'CO₂',
            co2,
            44,
            [
              for (var s = 0; s < 3; s++)
                if (s != k) x * ((h - 2 + 2 * s) / 2),
              h2o,
              x * h,
            ],
            '$yol ${_t(x)} mol $f yanınca ${_t(x)}·$n = ${_t(co2)} mol CO₂ '
                'oluşur.',
            [x, h2o],
          );
        }
        return soru(
          kok,
          'O₂',
          o2,
          32,
          [
            x * (2 * n + h / 2),
            x * (n + h / 2),
            for (var s = 0; s < 3; s++)
              if (s != k) x * ((h - 2 + 2 * s) / 2 + h / 4),
          ],
          '$yol Denkleme göre 1 mol $f için ${_t(n + h / 4)} mol O₂ gerekir; '
              '${_t(x)} mol için ${_t(o2)} mol O₂ harcanır.',
          [x, h2o],
        );
      case 4:
        final m = x * mk;
        return _say(
          'Molekülünde $n karbon atomu bulunan bir $sinif bileşiğinin ${_t(m)} '
              'gramı tamamen yakılıyor. Buna göre kaç mol CO₂ oluşur? (C: 12, '
              'H: 1)',
          co2,
          [for (final hh in hY) m / (12 * n + hh) * n, m / mk, m / 44, m / 12],
          '$bilgi bileşik $f, mol kütlesi $mk g/mol olur. ${_t(m)} / $mk = '
              '${_t(x)} mol bileşikten ${_t(x)}·$n = ${_t(co2)} mol CO₂ oluşur.',
          birim: 'mol',
        );
      case 5:
        final g = h2o * 18;
        return _say(
          'Molekülünde $n karbon atomu bulunan bir $sinif bileşiğinin ${_t(x)} '
              'molü tamamen yakılıyor. Buna göre kaç gram H₂O oluşur? (H: 1, '
              'O: 16)',
          g,
          [for (final hh in hY) x * hh / 2 * 18, x * h * 18, co2 * 18, h2o],
          '$bilgi bileşik $f olur. ${_t(x)} mol $f yanınca ${_t(x)}·${h ~/ 2} = '
              '${_t(h2o)} mol, yani ${_t(h2o)}·18 = ${_t(g)} gram H₂O oluşur.',
          birim: 'g',
        );
      case 6:
        final kok =
            'Mol kütlesi $mk g/mol olan bir $sinif bileşiğinin ${_t(x)} molü '
            'tamamen yakıldığında';
        final yol =
            '$bilgi 12n + ${_hSayisi(k, 0) == 2 ? '2n + 2' : (k == 1 ? '2n' : '2n − 2')} = $mk eşitliğinden n = $n ($f) bulunur.';
        return soru(
          kok,
          'CO₂',
          co2,
          44,
          [
            for (var s = 0; s < 3; s++)
              if (s != k && (mk - _hSayisi(s, 0)) % 14 == 0)
                x * (mk - _hSayisi(s, 0)) / 14,
            x * mk / 12,
            x * h / 2,
          ],
          '$yol ${_t(x)} mol $f yanınca ${_t(co2)} mol CO₂ oluşur.',
          [x, mk.toDouble()],
        );
      case 7:
        return _say(
          '${yanma('${_t(o2)} mol O₂ harcanıyor.')} Buna göre bu $sinif '
              'bileşiğinin mol kütlesi kaç g/mol olur? (C: 12, H: 1)',
          mk,
          [for (final hh in hY) 12 * n + hh, 12 * n, 14 * n, 12 * n + 2 * h],
          '$bilgi 1 mol bileşik için ${_t(o2 / x)} mol O₂ gerekir; n + '
              '${k == 0 ? '(2n + 2)/4' : (k == 1 ? '2n/4' : '(2n − 2)/4')} = '
              '${_t(o2 / x)} eşitliğinden n = $n ($f), mol kütlesi '
              '12·$n + $h = $mk g/mol olur.',
          birim: 'g/mol',
        );
      case 8:
        final hAtom = x * h;
        return _say(
          'Mol kütlesi $mk g/mol olan bir $sinif bileşiğinin ${_t(x)} molünde '
              'kaç mol hidrojen atomu bulunur? (C: 12, H: 1)',
          hAtom,
          [for (final hh in hY) x * hh, x * h / 2, x * n, x * 2 * n],
          '$bilgi mol kütlesi $mk g/mol olan bileşik $f olur. ${_t(x)} mol '
              '$f içinde ${_t(x)}·$h = ${_t(hAtom)} mol H atomu bulunur.',
          birim: 'mol',
        );
      default:
        final top = co2 + h2o;
        return soru(
          '${yanma('toplam ${_t(top)} mol CO₂ ve H₂O oluşuyor.')} Buna göre '
              'bu yanmada',
          n == 1 ? 'H₂O' : 'CO₂',
          n == 1 ? h2o : co2,
          n == 1 ? 18 : 44,
          n == 1
              ? [co2, top / 2, x * 4]
              : [
                  top / 2,
                  h2o,
                  for (var s = 0; s < 3; s++)
                    if (s != k) x * (top / x - (1 - s)) / 2,
                ],
          '$bilgi 1 mol bileşik yanınca n mol CO₂ ve ${k == 0 ? 'n + 1' : (k == 1 ? 'n' : 'n − 1')} '
              'mol H₂O oluşur; toplam ${_t(top / x)} mol olduğundan n = $n '
              '($f). Oluşan ${n == 1 ? 'H₂O ${_t(h2o)}' : 'CO₂ ${_t(co2)}'} mol olur.',
          [x, top],
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ─────────────────────────── 18 · Fonksiyonel gruplar ─────────────────────────

const _fgAlkol = 'alkol';
const _fgEter = 'eter';
const _fgAldehit = 'aldehit';
const _fgKeton = 'keton';
const _fgAsit = 'karboksilik asit';
const _fgEster = 'ester';
const _fgAmin = 'amin';

const _fgGrup = {
  _fgAlkol: '–OH',
  _fgEter: '–O–',
  _fgAldehit: '–CHO',
  _fgKeton: '–CO–',
  _fgAsit: '–COOH',
  _fgEster: '–COO–',
  _fgAmin: '–NH₂, –NH– ya da –N–',
};

const _fgKarisan = {
  _fgAlkol: [_fgEter, _fgAldehit],
  _fgEter: [_fgAlkol, _fgEster],
  _fgAldehit: [_fgKeton, _fgAsit],
  _fgKeton: [_fgAldehit, _fgEter],
  _fgAsit: [_fgEster, _fgAldehit],
  _fgEster: [_fgAsit, _fgEter],
  _fgAmin: [_fgAlkol, _fgEter],
};

const _organikler = [
  ('CH₃OH', _fgAlkol),
  ('CH₃CH₂OH', _fgAlkol),
  ('CH₃CH₂CH₂OH', _fgAlkol),
  ('CH₃CH(OH)CH₃', _fgAlkol),
  ('CH₃CH₂CH₂CH₂OH', _fgAlkol),
  ('(CH₃)₃COH', _fgAlkol),
  ('CH₃CH₂CH(OH)CH₃', _fgAlkol),
  ('HOCH₂CH₂OH', _fgAlkol),
  ('(CH₃)₂CHCH₂OH', _fgAlkol),
  ('CH₃OCH₃', _fgEter),
  ('CH₃OCH₂CH₃', _fgEter),
  ('CH₃CH₂OCH₂CH₃', _fgEter),
  ('CH₃OCH₂CH₂CH₃', _fgEter),
  ('CH₃CH₂OCH₂CH₂CH₃', _fgEter),
  ('(CH₃)₂CHOCH₃', _fgEter),
  ('C₆H₅OCH₃', _fgEter),
  ('HCHO', _fgAldehit),
  ('CH₃CHO', _fgAldehit),
  ('CH₃CH₂CHO', _fgAldehit),
  ('CH₃CH₂CH₂CHO', _fgAldehit),
  ('(CH₃)₂CHCHO', _fgAldehit),
  ('C₆H₅CHO', _fgAldehit),
  ('CH₃CH₂CH₂CH₂CHO', _fgAldehit),
  ('CH₃COCH₃', _fgKeton),
  ('CH₃COCH₂CH₃', _fgKeton),
  ('CH₃CH₂COCH₂CH₃', _fgKeton),
  ('CH₃COCH₂CH₂CH₃', _fgKeton),
  ('C₆H₅COCH₃', _fgKeton),
  ('CH₃COCH(CH₃)₂', _fgKeton),
  ('HCOOH', _fgAsit),
  ('CH₃COOH', _fgAsit),
  ('CH₃CH₂COOH', _fgAsit),
  ('CH₃CH₂CH₂COOH', _fgAsit),
  ('(CH₃)₂CHCOOH', _fgAsit),
  ('C₆H₅COOH', _fgAsit),
  ('HOOCCOOH', _fgAsit),
  ('HCOOCH₃', _fgEster),
  ('CH₃COOCH₃', _fgEster),
  ('CH₃COOCH₂CH₃', _fgEster),
  ('HCOOCH₂CH₃', _fgEster),
  ('CH₃CH₂COOCH₃', _fgEster),
  ('CH₃COOCH₂CH₂CH₃', _fgEster),
  ('CH₃CH₂COOCH₂CH₃', _fgEster),
  ('C₆H₅COOCH₃', _fgEster),
  ('CH₃NH₂', _fgAmin),
  ('CH₃CH₂NH₂', _fgAmin),
  ('(CH₃)₂NH', _fgAmin),
  ('(CH₃)₃N', _fgAmin),
  ('CH₃CH₂CH₂NH₂', _fgAmin),
  ('C₆H₅NH₂', _fgAmin),
  ('CH₃NHCH₂CH₃', _fgAmin),
];

final _f18 = lmSirali(
  'km_fonksiyonel_grup',
  'Organik bileşiklerde fonksiyonel grubun tanınması',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final u = kombinasyon(_organikler, 3, i);
    final x = [for (final j in ucluDizilimler[i % 6]) u[j]];
    final liste = _uc([for (final e in x) e.$1]);
    final aciklama =
        '${[for (var p = 0; p < 3; p++) '${x[p].$1}: ${x[p].$2} (${_fgGrup[x[p].$2]})'].join('; ')}.';
    if (i.isEven) {
      return _uclu(
        '$liste\nYoğun formülleri verilen bu organik bileşiklerin ait olduğu '
        'sınıflar numara sırasıyla hangi seçenekte doğru verilmiştir?',
        [for (final e in x) e.$2],
        [for (var p = 0; p < 3; p++) _fgKarisan[x[p].$2]![(i ~/ 2 + p) % 2]],
        aciklama,
      );
    }
    final turler = <String>[];
    for (final e in x) {
      if (!turler.contains(e.$2)) turler.add(e.$2);
    }
    final hedef = turler[(i ~/ 2) % turler.length];
    var maske = 0;
    for (var p = 0; p < 3; p++) {
      if (x[p].$2 == hedef) maske |= 1 << p;
    }
    return _hangileri(
      '$liste\nYoğun formülleri verilen bu bileşiklerden hangileri $hedef '
      'sınıfındadır?',
      maske,
      aciklama,
      i,
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ─────────────────────── 19 · Alkanların IUPAC adlandırması ──────────────────

const _anaZincir = [
  '', 'metan', 'etan', 'propan', 'bütan', 'pentan', 'hekzan', 'heptan', //
  'oktan', 'nonan', 'dekan',
];
const _carpanOnek = ['', '', 'di', 'tri', 'tetra'];

/// n karbonlu düz zincire (konum, dal boyu) dalları eklenmiş karbon iskeleti.
List<List<int>> _alkanKur(int n, List<(int, int)> dallar) {
  final adj = [for (var i = 0; i < n; i++) <int>[]];
  void bag(int a, int b) {
    adj[a].add(b);
    adj[b].add(a);
  }

  for (var i = 0; i + 1 < n; i++) {
    bag(i, i + 1);
  }
  for (final (konum, boy) in dallar) {
    var onceki = konum - 1;
    for (var k = 0; k < boy; k++) {
      adj.add(<int>[]);
      bag(onceki, adj.length - 1);
      onceki = adj.length - 1;
    }
  }
  return adj;
}

List<int> _agacYolu(List<List<int>> adj, int a, int b) {
  final once = List<int>.filled(adj.length, -2);
  once[a] = -1;
  final kuyruk = [a];
  for (var k = 0; k < kuyruk.length; k++) {
    for (final y in adj[kuyruk[k]]) {
      if (once[y] == -2) {
        once[y] = kuyruk[k];
        kuyruk.add(y);
      }
    }
  }
  final yol = <int>[];
  for (var v = b; v != -1; v = once[v]) {
    yol.add(v);
  }
  return yol.reversed.toList();
}

/// Zincirdeki dallar: (konum (1'den başlar), dal karbon sayısı).
List<(int, int)> _zincirDallari(List<List<int>> adj, List<int> yol) {
  final zincir = yol.toSet();
  final out = <(int, int)>[];
  for (var i = 0; i < yol.length; i++) {
    for (final y in adj[yol[i]]) {
      if (zincir.contains(y)) continue;
      final gorulen = {yol[i], y};
      final yigin = [y];
      var say = 0;
      while (yigin.isNotEmpty) {
        final v = yigin.removeLast();
        say++;
        for (final w in adj[v]) {
          if (gorulen.add(w)) yigin.add(w);
        }
      }
      out.add((i + 1, say));
    }
  }
  return out;
}

/// Konumlar ve dal adlarından ad: alfabetik sıra, di-/tri-/tetra- ön ekleri.
String _alkanAdiYaz(
  int uzunluk,
  List<(int, int)> dallar, {
  bool alfabetik = true,
  bool carpan = true,
}) {
  final gruplar = <String, List<int>>{};
  for (final (k, s) in dallar) {
    (gruplar[s == 1 ? 'metil' : 'etil'] ??= []).add(k);
  }
  final adlar = gruplar.keys.toList()..sort();
  if (!alfabetik) adlar.sort((x, y) => y.compareTo(x));
  final parca = [
    for (final a in adlar)
      '${(gruplar[a]!..sort()).join(',')}-${carpan ? _carpanOnek[gruplar[a]!.length] : ''}$a',
  ];
  return '${parca.join('-')}${_anaZincir[uzunluk]}';
}

int _listeKarsilastir(List<int> x, List<int> y) {
  for (var j = 0; j < x.length && j < y.length; j++) {
    if (x[j] != y[j]) return x[j].compareTo(y[j]);
  }
  return x.length.compareTo(y.length);
}

List<int> _konumlar(List<(int, int)> d) => [for (final e in d) e.$1]..sort();

/// Alfabetik sırada (etil önce) konumlar.
List<int> _alfabetikKonumlar(List<(int, int)> d) {
  final s = [
    ...d,
  ]..sort((x, y) => x.$2 != y.$2 ? y.$2.compareTo(x.$2) : x.$1.compareTo(y.$1));
  return [for (final e in s) e.$1];
}

int _zincirKarsilastir(
  (List<int>, List<(int, int)>) x,
  (List<int>, List<(int, int)>) y,
) {
  if (x.$2.length != y.$2.length) return y.$2.length.compareTo(x.$2.length);
  final k = _listeKarsilastir(_konumlar(x.$2), _konumlar(y.$2));
  if (k != 0) return k;
  return _listeKarsilastir(_alfabetikKonumlar(x.$2), _alfabetikKonumlar(y.$2));
}

/// En uzun zincir, en çok dal, en küçük konumlar ve alfabetik ilk dalın küçük
/// konumu kurallarıyla IUPAC adı. Dallar metil ya da etil değilse ya da bu
/// kurallar zinciri tek başına belirleyemiyorsa null döner.
(String, List<int>, List<(int, int)>)? _iupacAdi(List<List<int>> adj) {
  final yapraklar = [
    for (var v = 0; v < adj.length; v++)
      if (adj[v].length <= 1) v,
  ];
  var enUzun = 0;
  final adaylar = <(List<int>, List<(int, int)>)>[];
  for (final a in yapraklar) {
    for (final b in yapraklar) {
      if (a == b) continue;
      final y = _agacYolu(adj, a, b);
      if (y.length > enUzun) {
        enUzun = y.length;
        adaylar.clear();
      }
      if (y.length == enUzun) adaylar.add((y, _zincirDallari(adj, y)));
    }
  }
  if (enUzun > 10) return null;
  adaylar.sort(_zincirKarsilastir);
  final enIyi = adaylar.first;
  if (enIyi.$2.any((d) => d.$2 > 2)) return null;
  final ad = _alkanAdiYaz(enUzun, enIyi.$2);
  for (final a in adaylar.skip(1)) {
    if (a.$2.length == enIyi.$2.length &&
        _listeKarsilastir(_konumlar(a.$2), _konumlar(enIyi.$2)) == 0 &&
        (a.$2.any((d) => d.$2 > 2) || _alkanAdiYaz(enUzun, a.$2) != ad)) {
      return null;
    }
  }
  return (ad, enIyi.$1, enIyi.$2);
}

/// (ad, iskelet, ana zincir, dallar) — 4–10 karbonlu ana zincir, en çok dört
/// metil ya da etil dalı, en çok 14 karbon.
final _alkanlar = () {
  final adlar = <String>{};
  final out = <(String, List<List<int>>, List<int>, List<(int, int)>)>[];
  for (var n = 4; n <= 10; n++) {
    final yerler = [
      for (var k = 2; k < n; k++)
        for (final s in const [1, 2]) (k, s),
    ];
    void kur(int bas, List<(int, int)> secim, int karbon) {
      if (secim.isNotEmpty) {
        final adj = _alkanKur(n, secim);
        final ad = _iupacAdi(adj);
        if (ad != null && adlar.add(ad.$1)) out.add((ad.$1, adj, ad.$2, ad.$3));
      }
      if (secim.length == 4) return;
      for (var j = bas; j < yerler.length; j++) {
        final (k, s) = yerler[j];
        if (secim.where((e) => e.$1 == k).length >= 2 || karbon + s > 14) {
          continue;
        }
        secim.add((k, s));
        kur(j, secim, karbon + s);
        secim.removeLast();
      }
    }

    kur(0, [], n);
  }
  return out;
}();

String _yogunFormul(List<List<int>> adj, List<int> yol) {
  final zincir = yol.toSet();
  return [
    for (final v in yol)
      () {
        var metil = 0, etil = 0;
        for (final w in adj[v]) {
          if (zincir.contains(w)) continue;
          if (adj[w].length == 1) {
            metil++;
          } else {
            etil++;
          }
        }
        final h = 4 - adj[v].length;
        return 'C${h == 0 ? '' : (h == 1 ? 'H' : 'H${_alt(h)}')}'
            '${metil == 1 ? '(CH₃)' : (metil == 2 ? '(CH₃)₂' : '')}'
            '${etil == 1 ? '(C₂H₅)' : (etil == 2 ? '(C₂H₅)₂' : '')}';
      }(),
  ].join('–');
}

/// Zinciri ana zincir sanıp en küçük konumlarla numaralayan (yanlış) ad.
String _zincirAdi(List<List<int>> adj, List<int> yol) {
  final ileri = (yol, _zincirDallari(adj, yol));
  final geri = (
    yol.reversed.toList(),
    _zincirDallari(adj, yol.reversed.toList()),
  );
  final s = _zincirKarsilastir(ileri, geri) <= 0 ? ileri : geri;
  return _alkanAdiYaz(yol.length, s.$2);
}

int _karbonSayisi(List<List<int>> adj) => adj.length;

/// Bileşiğe özgü yanlış adlar: tuzak zincir adları, ters numaralama,
/// alfabetik sıra hatası.
List<String> _iupacYanlislari(
  (String, List<List<int>>, List<int>, List<(int, int)>) b,
) {
  final (ad, adj, yol, dallar) = b;
  final out = <String>[];
  void ekle(String s) {
    if (s != ad && !out.contains(s)) out.add(s);
  }

  ekle(_alkanAdiYaz(yol.length, _zincirDallari(adj, yol.reversed.toList())));
  if (dallar.any((d) => d.$2 == 1) && dallar.any((d) => d.$2 == 2)) {
    ekle(_alkanAdiYaz(yol.length, dallar, alfabetik: false));
  }
  final yapraklar = [
    for (var v = 0; v < adj.length; v++)
      if (adj[v].length <= 1) v,
  ];
  for (final x in yapraklar) {
    for (final y in yapraklar) {
      if (x >= y) continue;
      final p = _agacYolu(adj, x, y);
      if (p.length < yol.length &&
          _zincirDallari(adj, p).every((d) => d.$2 <= 2)) {
        ekle(_zincirAdi(adj, p));
      }
    }
  }
  return out;
}

/// Kesin yanlış ek çeldiriciler: konum kaydırma, çarpan ön ekini unutma,
/// toplam karbon sayısıyla düz zincir adı.
List<String> _iupacEkYanlislar(
  (String, List<List<int>>, List<int>, List<(int, int)>) b,
) {
  final (ad, adj, yol, dallar) = b;
  final n = yol.length;
  final ilk = dallar.first;
  final kayik = [
    (ilk.$1 + 1 <= n - 1 ? ilk.$1 + 1 : ilk.$1 - 1, ilk.$2),
    ...dallar.skip(1),
  ];
  final son = dallar.last;
  final sonKayik = [
    ...dallar.take(dallar.length - 1),
    (son.$1 - 1 >= 2 ? son.$1 - 1 : son.$1 + 1, son.$2),
  ];
  final enBuyukKonum = _konumlar(dallar).last;
  return [
    for (final s in [
      _alkanAdiYaz(n, kayik),
      if (dallar.length > 1) _alkanAdiYaz(n, dallar, carpan: false),
      if (_karbonSayisi(adj) <= 10) _anaZincir[_karbonSayisi(adj)],
      _alkanAdiYaz(n, [for (final d in dallar) (d.$1, 1)]),
      _alkanAdiYaz(n, sonKayik),
      // Ana zinciri bir eksik ya da bir fazla sayma.
      if (n < 10) _alkanAdiYaz(n + 1, dallar),
      if (enBuyukKonum <= n - 2) _alkanAdiYaz(n - 1, dallar),
      _carpanHatasi(n, dallar),
    ])
      if (s != ad) s,
  ];
}

/// Tekrarlanan dal için yanlış çarpan ön eki (ör. tetra yerine tri).
String _carpanHatasi(int n, List<(int, int)> dallar) {
  final dogru = _alkanAdiYaz(n, dallar);
  for (final k in const ['tetra', 'tri', 'di']) {
    final yeni = const {'tetra': 'tri', 'tri': 'di', 'di': 'tri'}[k]!;
    if (dogru.contains('${k}metil') || dogru.contains('${k}etil')) {
      return dogru.replaceFirst(RegExp('(?<=-)$k(?=(m|e)til)'), yeni);
    }
  }
  return dogru;
}

// Çizim soruları: (bileşik, çizilen zincir).
final _iupacCizimleri = () {
  final out = <(int, List<int>)>[];
  for (var c = 0; c < _alkanlar.length; c++) {
    final (_, adj, yol, _) = _alkanlar[c];
    final yollar = <List<int>>[c.isEven ? yol : yol.reversed.toList()];
    final yapraklar = [
      for (var v = 0; v < adj.length; v++)
        if (adj[v].length <= 1) v,
    ];
    for (final x in yapraklar) {
      for (final y in yapraklar) {
        if (x == y || yollar.length >= 2) continue;
        final p = _agacYolu(adj, x, y);
        if (p.length < yol.length &&
            _zincirDallari(adj, p).every((d) => d.$2 <= 2)) {
          yollar.add(p);
        }
      }
    }
    yollar.add(c.isEven ? yol.reversed.toList() : yol);
    final gorulen = <String>{};
    for (final p in yollar) {
      if (gorulen.add(_yogunFormul(adj, p))) out.add((c, p));
    }
  }
  return out;
}();

final _iupacYanlisAdlari = [
  for (var c = 0; c < _alkanlar.length; c++)
    for (final y in _iupacYanlislari(_alkanlar[c])) (c, y),
];

String _alkanFormulu(int c) => 'C${_alt(c)}H${_alt(2 * c + 2)}';

final _f19 = lmSirali(
  'km_iupac',
  'Alkanların IUPAC sistemine göre adlandırılması',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.uygulama,
  (i) {
    final tur = i % 5;
    final j = i ~/ 5;
    if (tur < 3) {
      final k = j * 3 + tur;
      final (c, p) = _iupacCizimleri[k * _iupacCizimleri.length ~/ 3000];
      final b = _alkanlar[c];
      final (ad, adj, yol, dallar) = b;
      final cizimTuzak = p.length < yol.length;
      return secenekli(
        'Yoğun yapı formülü ${_yogunFormul(adj, p)} olan alkanın IUPAC adı '
            'nedir?',
        ad,
        [
          if (cizimTuzak) _zincirAdi(adj, p),
          ..._iupacYanlislari(b),
          ..._iupacEkYanlislar(b),
        ],
        'En uzun karbon zinciri ${yol.length} karbonludur'
            '${cizimTuzak ? ' (yatay yazılan zincir en uzun zincir değildir)' : ''}; '
            'dallara en küçük numaralar verilir ve dallar alfabetik sırayla '
            'yazılır: $ad.',
      );
    }
    if (tur == 3) {
      final (c, yanlis) =
          _iupacYanlisAdlari[j * _iupacYanlisAdlari.length ~/ 1000];
      final b = _alkanlar[c];
      final (ad, _, yol, _) = b;
      return secenekli(
        'Bir öğrenci bir alkanı “$yanlis” olarak adlandırmıştır. Bu ad IUPAC '
            'kurallarına uymadığına göre bileşiğin doğru IUPAC adı nedir?',
        ad,
        [yanlis, ..._iupacYanlislari(b), ..._iupacEkYanlislar(b)],
        '“$yanlis” adıyla tanımlanan yapıda en uzun zincir ${yol.length} '
            'karbonludur; dallara en küçük numaralar verilip dallar alfabetik '
            'sırayla yazılınca doğru ad $ad olur.',
      );
    }
    final c = j * _alkanlar.length ~/ 1000;
    final (ad, adj, yol, dallar) = _alkanlar[c];
    final n = _karbonSayisi(adj);
    final etil = dallar.where((d) => d.$2 == 2).length;
    return secenekli(
      'IUPAC adı $ad olan alkanın molekül formülü nedir?',
      _alkanFormulu(n),
      [
        _alkanFormulu(yol.length),
        if (etil > 0) _alkanFormulu(n - etil),
        'C${_alt(n)}H${_alt(2 * n)}',
        _alkanFormulu(n + 1),
        'C${_alt(n)}H${_alt(2 * n - 2)}',
      ],
      'Ana zincir ${yol.length} karbonludur; dallar ${n - yol.length} karbon '
          'ekler. Toplam $n karbonlu alkanın formülü CnH2n+2 genel formülüne '
          'göre ${_alkanFormulu(n)} olur.',
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ──────────────────── 20 · Karbon atomlarında hibritleşme ─────────────────────

/// Molekül: (zincirdeki bağ dereceleri, karbon başına metil dalı sayısı).
final _hibritMolekulleri = () {
  final out = <(List<int>, List<int>)>[];
  final gorulen = <String>{};
  for (var n = 2; n <= 8; n++) {
    void kur(List<int> baglar) {
      if (baglar.length == n - 1) {
        if (baglar.every((b) => b == 1)) return;
        int sol(int i) => i > 0 ? baglar[i - 1] : 0;
        int sag(int i) => i < n - 1 ? baglar[i] : 0;
        for (var i = 0; i < n; i++) {
          if (sol(i) + sag(i) > 4 || (sol(i) > 1 && sag(i) > 1)) return;
        }
        final serbest = [
          for (var i = 0; i < n; i++)
            i == 0 || i == n - 1 ? 0 : 4 - sol(i) - sag(i),
        ];
        void dal(int i, List<int> d, int toplam) {
          if (i == n) {
            final anahtar = '${baglar.join()}|${d.join()}';
            final ters = '${baglar.reversed.join()}|${d.reversed.join()}';
            if (anahtar.compareTo(ters) <= 0 && gorulen.add(anahtar)) {
              out.add(([...baglar], [...d]));
            }
            return;
          }
          final ust = serbest[i] < 2 ? serbest[i] : 2;
          for (var k = 0; k <= ust && toplam + k <= 2; k++) {
            d.add(k);
            dal(i + 1, d, toplam + k);
            d.removeLast();
          }
        }

        dal(0, [], 0);
        return;
      }
      for (final b in const [1, 2, 3]) {
        baglar.add(b);
        kur(baglar);
        baglar.removeLast();
      }
    }

    kur([]);
  }
  return out;
}();

const _bagSimgesi = ['', '–', '=', '≡'];

String _hibritFormul((List<int>, List<int>) m) {
  final (baglar, dallar) = m;
  final n = dallar.length;
  final b = StringBuffer();
  for (var i = 0; i < n; i++) {
    final sol = i > 0 ? baglar[i - 1] : 0, sag = i < n - 1 ? baglar[i] : 0;
    final h = 4 - sol - sag - dallar[i];
    b.write('C${h == 0 ? '' : (h == 1 ? 'H' : 'H${_alt(h)}')}');
    if (dallar[i] == 1) b.write('(CH₃)');
    if (dallar[i] == 2) b.write('(CH₃)₂');
    if (i < n - 1) b.write(_bagSimgesi[sag]);
  }
  return b.toString();
}

/// 0: sp³, 1: sp², 2: sp (ana zincirdeki karbon).
int _hibrit((List<int>, List<int>) m, int i) {
  final (baglar, dallar) = m;
  final sol = i > 0 ? baglar[i - 1] : 0;
  final sag = i < dallar.length - 1 ? baglar[i] : 0;
  final enBuyuk = sol > sag ? sol : sag;
  return enBuyuk == 3 ? 2 : (enBuyuk == 2 ? 1 : 0);
}

const _hibritAdi = ['sp³', 'sp²', 'sp'];
const _bagAcisi = ['109,5°', '120°', '180°'];
const _hibritNedeni = [
  'yalnız tekli bağ yapar',
  'çift bağa katılır',
  'üçlü bağa katılır',
];

final _hibritKonumlari = [
  for (var m = 0; m < _hibritMolekulleri.length; m++)
    for (var k = 0; k < _hibritMolekulleri[m].$2.length; k++) (m, k),
];

final _f20 = lmSirali(
  'km_hibritlesme',
  'Karbon atomlarında hibritleşme ve σ, π bağları',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    const n0 = 1500, n1 = 1500;
    final tur = i < n0 ? 0 : (i < n0 + n1 ? 1 : 2);
    if (tur == 2) {
      final j = i - n0 - n1;
      final (m, k) =
          _hibritKonumlari[j *
              _hibritKonumlari.length ~/
              (lmAileBoyu - n0 - n1)];
      final mol = _hibritMolekulleri[m];
      final h = _hibrit(mol, k);
      String yaz(int t, int a) => '${_hibritAdi[t]}, ${_bagAcisi[a]}';
      return secenekli(
        'Yoğun formülü ${_hibritFormul(mol)} olan molekülde ana zincirdeki '
            'soldan ${k + 1}. karbon atomunun hibritleşme türü ve bu atomun '
            'bağları arasındaki açı hangi seçenekte doğru verilmiştir?',
        yaz(h, h),
        [
          yaz((h + 1) % 3, (h + 1) % 3),
          yaz((h + 2) % 3, (h + 2) % 3),
          yaz(h, (h + 1 + i % 2) % 3),
        ],
        'Soldan ${k + 1}. karbon atomu ${_hibritNedeni[h]}; ${_hibritAdi[h]} '
            'hibritleşmesi yapar ve bağ açısı ${_bagAcisi[h]} olur.',
      );
    }
    final mol =
        _hibritMolekulleri[(tur == 0 ? i : i - n0) *
            _hibritMolekulleri.length ~/
            (tur == 0 ? n0 : n1)];
    final (baglar, dallar) = mol;
    final n = dallar.length;
    var hToplam = 0, pi = 0, coklu = 0, uclu = 0;
    for (var t = 0; t < n; t++) {
      final sol = t > 0 ? baglar[t - 1] : 0, sag = t < n - 1 ? baglar[t] : 0;
      hToplam += 4 - sol - sag - dallar[t];
    }
    var dalSay = 0;
    for (final d in dallar) {
      dalSay += d;
    }
    hToplam += 3 * dalSay;
    for (final b in baglar) {
      pi += b - 1;
      if (b > 1) coklu++;
      if (b == 3) uclu++;
    }
    final cc = n - 1 + dalSay;
    final sigma = cc + hToplam;
    final f = _hibritFormul(mol);
    if (tur == 0) {
      String yaz(int s, int p) => 'σ: $s, π: $p';
      return secenekli(
        'Yoğun formülü $f olan molekülde kaç tane σ (sigma) ve kaç tane π '
            '(pi) bağı bulunur?',
        yaz(sigma, pi),
        [
          yaz(cc, pi),
          yaz(sigma + pi, pi),
          if (uclu > 0) yaz(sigma, coklu),
          yaz(cc + pi, pi),
          yaz(sigma, pi + 1),
          yaz(sigma - 1, pi),
        ],
        'Her tekli bağ bir σ, çift bağ bir σ ve bir π, üçlü bağ bir σ ve iki π '
            'bağından oluşur. Molekülde $cc karbon-karbon bağı ve $hToplam C–H '
            'bağı vardır: σ = $cc + $hToplam = $sigma, π = $pi.',
      );
    }
    final say = [0, 0, 0];
    for (var t = 0; t < n; t++) {
      say[_hibrit(mol, t)]++;
    }
    say[0] += dalSay;
    String yaz(List<int> s) => 'sp³: ${s[0]}, sp²: ${s[1]}, sp: ${s[2]}';
    return secenekli(
      'Yoğun formülü $f olan moleküldeki karbon atomlarından sp³, sp² ve sp '
          'hibritleşmesi yapanların sayıları hangi seçenekte doğru verilmiştir?',
      yaz(say),
      [
        if (say[2] > 0) yaz([say[0], say[1] + say[2], 0]),
        if (say[1] != say[2]) yaz([say[0], say[2], say[1]]),
        if (dalSay > 0) yaz([say[0] - dalSay, say[1], say[2]]),
        if (say[1] > 0) yaz([say[0] + 1, say[1] - 1, say[2]]),
        if (say[0] > 0) yaz([say[0] - 1, say[1] + 1, say[2]]),
        yaz([say[0] + say[1], 0, say[2]]),
        if (say[2] > 0) yaz([say[0] + say[2], say[1], 0]),
        if (say[2] > 0) yaz([say[0] + 1, say[1], say[2] - 1]),
        yaz([say[0], say[1] + 1, say[2]]),
      ],
      'Üçlü bağa katılan karbonlar sp, çift bağa katılanlar sp², yalnız tekli '
          'bağ yapanlar sp³ hibritleşmesi yapar${dalSay > 0 ? ' (metil dalları da sp³)' : ''}: '
          '${yaz(say)}.',
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

final lmKimyaEk = <AdvancedFamily>[
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
