// Lise geometri ve analitik geometri ek aileleri: paralel doğrularda açılar,
// üçgen eşitsizliği, Heron, çemberler, düzgün çokgenler, piramit, hacim
// korunumu ve analitik düzlemde kesişim, alan, simetri ve döndürme.
import 'ortak.dart';

const _mat = Topic.mathematics;
const _tm = 'Temel Matematik';
const _aytMat = 'Matematik';

/// İşaretli tam sayı (Unicode eksi ile).
String _m(int x) => x < 0 ? '−${-x}' : '$x';

/// İşlem içinde kullanılan sayı: negatifse parantez içinde.
String _pz(int x) => x < 0 ? '(−${-x})' : '$x';

/// Nokta yazımı: (3, −2).
String _n(int x, int y) => '(${_m(x)}, ${_m(y)})';

/// n = c²·m ayrışımı (m kare çarpansız).
(int, int) _kokAyir(int n) {
  var c = 1, m = n;
  for (var d = 2; d * d <= m; d++) {
    while (m % (d * d) == 0) {
      m ~/= d * d;
      c *= d;
    }
  }
  return (c, m);
}

/// c·√n ifadesini sadeleştirerek yazar: _kok(1, 12) → 2√3, _kok(3, 4) → 6.
String _kok(int c, int n) {
  final (d, m) = _kokAyir(n);
  final k = c * d;
  if (m == 1) return '$k';
  return k == 1 ? '√$m' : '$k√$m';
}

/// px + q ifadesi: 3x + 15, x − 7, 4x.
String _dx(int p, int q, [String v = 'x']) {
  final px = p == 1 ? v : '$p$v';
  if (q == 0) return px;
  return q > 0 ? '$px + $q' : '$px − ${-q}';
}

/// Derece yanıtlı soru; çeldiriciler (0°, üst) aralığında tutulur.
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

/// Çeldiriciler için yalnız tam ve pozitif bölümleri alır.
int? _bol(int pay, int payda) =>
    payda != 0 && pay % payda == 0 && pay ~/ payda > 0 ? pay ~/ payda : null;

// ---------------------------------------------------------------------------
// 1 · Paralel doğrular ve kesen

const _kesenKatsayi = [
  (3, 1),
  (2, 5),
  (4, 1),
  (1, 3),
  (5, 2),
  (2, 3),
  (4, 3),
  (1, 4),
  (5, 3),
  (3, 5),
];
const _kesenAd = ['yöndeş', 'iç ters', 'dış ters', 'karşı durumlu'];
const _kesenKural = [
  'Paralel doğrularda yöndeş açıların ölçüleri eşittir',
  'Paralel doğrularda iç ters açıların ölçüleri eşittir',
  'Paralel doğrularda dış ters açıların ölçüleri eşittir',
  'Paralel doğrularda karşı durumlu açıların ölçüleri toplamı 180° olur',
];

AdvancedItem _kesenAcisi(int a, int b, int j) {
  final x = 7 + a;
  final (p, r) = _kesenKatsayi[b % 10];
  final butunler = j == 3;
  var t = 31 + 2 * a + 50 * (b ~/ 10);
  late int q, s;
  for (; ; t += 2) {
    q = t - p * x;
    s = (butunler ? 180 - t : t) - r * x;
    final yazili = {p, r, q.abs(), s.abs()};
    final buyuk = butunler && 180 - t > t ? 180 - t : t;
    if (!yazili.contains(x) && !yazili.contains(buyuk)) break;
  }
  final tanim = butunler
      ? 'kesenin aynı tarafında ve paralel doğruların arasında kalan karşı '
            'durumlu iki açının'
      : '${_kesenAd[j]} iki açının';
  final veri =
      'd₁ ∥ d₂ olmak üzere bu iki doğruyu kesen k doğrusunun oluşturduğu '
      '$tanim ölçüleri (${_dx(p, q)})° ve (${_dx(r, s)})° olarak veriliyor.';
  final String denklem, adim;
  if (butunler) {
    denklem = '(${_dx(p, q)}) + (${_dx(r, s)}) = 180';
    adim = '${p + r}x = ${(p + r) * x}';
  } else {
    denklem = '${_dx(p, q)} = ${_dx(r, s)}';
    final d = (p - r).abs();
    adim = d == 1 ? '' : '${d}x = ${d * x}';
  }
  final cozum =
      '${_kesenKural[j]}: $denklem. Buradan ${adim.isEmpty ? '' : '$adim, '}'
      'x = $x bulunur.';
  // Bağıntıyı karıştıran öğrencinin bulacağı x değeri.
  final xKarisik = butunler ? _bol(s - q, p - r) : _bol(180 - q - s, p + r);
  if ((a + b).isEven) {
    return sayisal(
      '$veri Buna göre x kaçtır?',
      x,
      [t, ?xKarisik, ?_bol(q + s, (p - r).abs())],
      cozum,
      positive: true,
    );
  }
  final yanlisAci = xKarisik == null ? null : p * xKarisik + q;
  if (butunler) {
    final buyuk = t > 180 - t ? t : 180 - t;
    return _aci(
      '$veri Buna göre bu iki açıdan büyük olanının ölçüsü kaç derecedir?',
      buyuk,
      [180 - buyuk, x, ?yanlisAci],
      '$cozum Açıların ölçüleri $t° ve ${180 - t}° olur; büyük olanı '
          '$buyuk°.',
    );
  }
  return _aci(
    '$veri Buna göre bu açılardan her birinin ölçüsü kaç derecedir?',
    t,
    [180 - t, x, ?yanlisAci],
    '$cozum Her bir açı ${_dx(p, q)} ifadesinde x = $x yazılarak $t° '
        'bulunur.',
  );
}

const _kirikGiris =
    'd₁ ∥ d₂ olmak üzere A noktası d₁, B noktası d₂ doğrusu üzerindedir. İki '
    'doğrunun arasında kalan bir E noktası A ve B noktalarıyla birleştiriliyor.';

AdvancedItem _kirikZ(int a, int b, int j) {
  const yer =
      ' d₁ üzerindeki C noktası ve d₂ üzerindeki D noktası, AB doğrusuna göre '
      'E noktasıyla aynı taraftadır.';
  const paralel =
      'E noktasından d₁ doğrusuna çizilen paralel, AEB açısını iç ters açılar '
      'yoluyla CAE ve DBE açılarına eşit iki parçaya ayırır';
  if (j == 2) {
    final y = 11 + b, t = 32 + a, x = y + t, z = x + y;
    return _aci(
      '$_kirikGiris$yer AEB açısının ölçüsü $z° ve CAE açısının ölçüsü DBE '
          'açısının ölçüsünden $t° fazla olduğuna göre DBE açısının ölçüsü kaç '
          'derecedir?',
      y,
      [x, z - t, ?_bol(180 - z - t, 2)],
      '$paralel: CAE + DBE = $z°. CAE = DBE + $t° olduğundan 2·DBE + $t° = '
          '$z°, DBE = ($z° − $t°) / 2 = $y°.',
    );
  }
  final x = 20 + 2 * a, y = 17 + 2 * b, z = x + y;
  if (j == 1) {
    return _aci(
      '$_kirikGiris$yer CAE açısının ölçüsü $x°, AEB açısının ölçüsü $z° '
          'olduğuna göre DBE açısının ölçüsü kaç derecedir?',
      y,
      [z + x, 180 - z - x, 180 - y],
      '$paralel: $z° = $x° + DBE, buradan DBE = $z° − $x° = $y°.',
    );
  }
  return _aci(
    '$_kirikGiris$yer CAE açısının ölçüsü $x°, DBE açısının ölçüsü $y° '
        'olduğuna göre AEB açısının ölçüsü kaç derecedir?',
    z,
    [180 - z, (x - y).abs(), 180 - (x - y).abs()],
    '$paralel: AEB = $x° + $y° = $z°.',
  );
}

AdvancedItem _kirikU(int a, int b, int j) {
  const yer =
      ' d₁ üzerindeki C noktası ve d₂ üzerindeki D noktası, AB doğrusuna göre '
      'E noktasının karşı tarafındadır.';
  const paralel =
      'E noktasından d₁ doğrusuna bir paralel çizilirse bu doğru CAE ve DBE '
      'açılarıyla karşı durumlu açılar oluşturur; bu yüzden CAE + AEB + DBE '
      '= 360° olur';
  if (j == 0) {
    var al = 100 + 2 * a;
    final be = 101 + 2 * b;
    // AEB açısı verilen DBE açısına eşit çıkmasın; tek sayıya kayan CAE
    // değeri başka bir vakanın CAE değeriyle çakışmaz.
    if (360 - al - be == be) al++;
    if (al + be == 270) al += 2;
    final z = 360 - al - be;
    return _aci(
      '$_kirikGiris$yer CAE açısının ölçüsü $al°, DBE açısının ölçüsü $be° '
          'olduğuna göre AEB açısının ölçüsü kaç derecedir?',
      z,
      [al + be - 180, (al - be).abs(), 180 - al + be, al + 180 - be],
      '$paralel. AEB = 360° − $al° − $be° = $z°.',
    );
  }
  if (j == 1) {
    final al = 125 + 2 * a, be = 120 + 2 * b, z = 360 - al - be;
    return _aci(
      '$_kirikGiris$yer CAE açısının ölçüsü $al°, AEB açısının ölçüsü $z° '
          'olduğuna göre DBE açısının ölçüsü kaç derecedir?',
      be,
      [al + z - 180, 180 - z, 180 - be],
      '$paralel. DBE = 360° − $al° − $z° = $be°.',
    );
  }
  final z = 44 + 2 * a, t = 2 + 2 * b;
  final be = (360 - z - t) ~/ 2, al = be + t;
  return _aci(
    '$_kirikGiris$yer AEB açısının ölçüsü $z° ve CAE açısının ölçüsü DBE '
        'açısının ölçüsünden $t° fazla olduğuna göre DBE açısının ölçüsü kaç '
        'derecedir?',
    be,
    [al, 360 - z - t, 180 - be],
    '$paralel. CAE + DBE = 360° − $z° = ${360 - z}° ve CAE = DBE + $t° '
        'olduğundan 2·DBE = ${360 - z - t}°, DBE = $be°.',
  );
}

// ---------------------------------------------------------------------------
// 3 · Açı-kenar bağıntısı

/// Köşenin karşısındaki kenar.
const _karsiKenar = {'A': '|BC|', 'B': '|AC|', 'C': '|AB|'};

/// Doğru sıralama ve üç yanlış sıralama (ters, ilk ikisinin ve son ikisinin
/// yer değiştirmesi).
(String, List<String>) _siralama(List<String> artan) {
  String yaz(List<String> l) => l.join(' < ');
  final [x, y, z] = artan;
  return (
    yaz([x, y, z]),
    [
      yaz([z, y, x]),
      yaz([y, x, z]),
      yaz([x, z, y]),
    ],
  );
}

/// Açıları verilen köşeleri ölçüye göre artan sırada döndürür.
List<String> _artanKose(Map<String, int> aci) =>
    (aci.keys.toList()..sort((p, q) => aci[p]!.compareTo(aci[q]!)));

String _aciListesi(Map<String, int> aci) =>
    ['A', 'B', 'C'].map((k) => '$k = ${aci[k]}°').join(', ');

const _ucluAci = [
  (50, 60, 70),
  (75, 40, 65),
  (35, 90, 55),
  (85, 45, 50),
  (30, 80, 70),
  (95, 25, 60),
  (58, 52, 70),
  (44, 76, 60),
];
const _ucluKatsayi = [(1, 2, 3), (2, 1, 3), (3, 2, 1), (2, 3, 1), (1, 3, 2)];

// ---------------------------------------------------------------------------
// 4 · Dik üçgende trigonometrik oranlar

/// İlkel Pisagor üçlüleri.
const _ilkel = [
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
];

/// a → (dik kenar 1, dik kenar 2, hipotenüs); 13 üçlü iki yönde.
(int, int, int) _yonluUclu(int a) {
  final (u, v, w) = _ilkel[a % 13];
  return a < 13 ? (u, v, w) : (v, u, w);
}

/// İki köşe harfinden kenar adı: |AB|, |AC|, |BC|.
String _kenar(String p, String q) => p.compareTo(q) < 0 ? '|$p$q|' : '|$q$p|';

/// Dik açı köşesi R, dar açı köşeleri P1 ve P2.
const _dikKoseler = [('B', 'A', 'C'), ('C', 'B', 'A'), ('A', 'C', 'B')];

// ---------------------------------------------------------------------------
// 5 · Heron

/// Kenarları tam sayı, ilkel, dik olmayan, eşkenar olmayan ve çevresi çift
/// üçgenler: (x, y, z, katsayı, kök içi); alan katsayı·√(kök içi) olur.
List<(int, int, int, int, int)> _ucgenler(int alt, int ust, int enCokKok) {
  final r = <(int, int, int, int, int)>[];
  for (var z = alt; z <= ust; z++) {
    for (var y = 1; y <= z; y++) {
      for (var x = 1; x <= y; x++) {
        if (x + y <= z || (x + y + z).isOdd) continue;
        if (x.gcd(y).gcd(z) != 1) continue;
        if (x * x + y * y == z * z || x == z) continue;
        final s = (x + y + z) ~/ 2;
        final (k, m) = _kokAyir(s * (s - x) * (s - y) * (s - z));
        if (m > enCokKok) continue;
        r.add((x, y, z, k, m));
      }
    }
  }
  return r;
}

/// Tarla vakaları: ilkel Heron üçgeni ve ölçek; en uzun kenar en çok 400 m.
final _heronTarla = [
  for (final t in _ucgenler(1, 65, 1))
    for (var k = 1; k * t.$3 <= 400; k++) (t, k),
];
final _heronA1 = _ucgenler(1, 30, 15);
final _heronA2 = _ucgenler(31, 40, 15);
final _heronA3 = _ucgenler(41, 50, 15);
final _heron50 = _ucgenler(1, 50, 15);
final _heron60 = _ucgenler(1, 60, 15);

/// Bir kenara ait yükseklik 2·Alan / kenar: m = 1 için en çok iki ondalık,
/// m > 1 için tam katsayılı kök olmalıdır.
bool _yukseklikTemiz(int k, int m, int kenar) {
  if (m == 1) {
    final g = (2 * k).gcd(kenar), d = kenar ~/ g;
    return 100 % d == 0;
  }
  return (2 * k) % kenar == 0;
}

final _yukseklikCiftleri = [
  for (final t in _heron50)
    for (final s in {t.$1, t.$2, t.$3})
      if (_yukseklikTemiz(t.$4, t.$5, s)) (t, s),
];
final _enUzunKenarli = [
  for (final t in _heron60)
    if (_yukseklikTemiz(t.$4, t.$5, t.$3)) t,
];
final _enKisaKenarli = [
  for (final t in _heron50)
    if (_yukseklikTemiz(t.$4, t.$5, t.$1)) t,
];

/// Yükseklik vakası: (üçgen, yüksekliği sorulan kenar, ölçek). c = 3…5 ortak
/// havuzu üç ayrı dilimde, c = 6 ve 7 en uzun ve en kısa kenar havuzlarını
/// kullanır.
((int, int, int, int, int), int, int) _yukseklikVerisi(int i, int c) {
  if (c <= 5) {
    final j = i + 500 * (c - 3), n = _yukseklikCiftleri.length;
    final (ucgen, kenar) = _yukseklikCiftleri[j % n];
    return (ucgen, kenar, 1 + j ~/ n);
  }
  final havuz = c == 6 ? _enUzunKenarli : _enKisaKenarli;
  final ucgen = havuz[i % havuz.length];
  return (ucgen, c == 6 ? ucgen.$3 : ucgen.$1, 1 + i ~/ havuz.length);
}

/// Kesirli katsayılı kök: (pay/payda)·√m metni; tam değilse null.
String? _kokluDeger(int pay, int payda, int m, {bool ondalik = true}) {
  final g = pay.gcd(payda);
  final p = pay ~/ g, q = payda ~/ g;
  if (m == 1) {
    if (q == 1) return '$p';
    if (!ondalik || 100 % q != 0) return null;
    return tr(p / q);
  }
  if (q != 1) return null;
  return _kok(p, m);
}

/// Heron çözümü: yarı çevre ve çarpanlar.
String _heronAdim(int x, int y, int z, int k, int m) {
  final s = (x + y + z) ~/ 2;
  final n = s * (s - x) * (s - y) * (s - z);
  return 'Yarı çevre s = ($x + $y + $z) / 2 = $s olur. Heron bağıntısına göre '
      'alan √(s·(s − $x)·(s − $y)·(s − $z)) = √($s·${s - x}·${s - y}·'
      '${s - z})${n <= 1000000 ? ' = √$n' : ''} = ${_kok(k, m)}';
}

/// Ölçeklenmiş Heron üçgeni: küçük üçgenin alanı ve ölçeğin karesi.
String _heronOlcekli(int x0, int y0, int z0, int a0, int t, String birim) {
  if (t == 1) return '${_heronAdim(x0, y0, z0, a0, 1)} $birim olur.';
  final s0 = (x0 + y0 + z0) ~/ 2;
  return 'Kenarlar $x0, $y0 ve $z0 sayılarının $t katıdır. Kenarları $x0, $y0 '
      've $z0 olan üçgende yarı çevre $s0, Heron bağıntısıyla alan '
      '√($s0·${s0 - x0}·${s0 - y0}·${s0 - z0}) = $a0 olur. Kenarlar $t katına '
      'çıkınca alan $t² katına çıkar: $t²·$a0 = ${t * t * a0} $birim.';
}

/// Tam sayı Heron alanı için çeldiriciler: dik üçgen sanma, karekök almayı
/// unutma, iki katını ya da yarısını alma.
List<String> _heronTamYanlis(
  int x,
  int y,
  int z,
  int alan,
  int t,
  String birim,
) => [
  if ((x * y).isEven) '${x * y ~/ 2} $birim',
  if (alan <= 3000) '${alan * alan} $birim',
  '${2 * alan} $birim',
  if (alan.isEven) '${alan ~/ 2} $birim',
  '${alan + t * t} $birim',
];

/// Heron alanı için çeldiriciler: çevreyi yarı çevre sanma, karekök almayı
/// unutma, dik üçgen sanma ve iki katını alma.
List<String> _heronYanlis(int x, int y, int z, int k, int m, String birim) {
  final u = x + y + z;
  final s = u ~/ 2;
  final n = s * (s - x) * (s - y) * (s - z);
  final (k2, m2) = _kokAyir(u * (u - x) * (u - y) * (u - z));
  return [
    if (m2 <= 1000) '${_kok(k2, m2)} $birim',
    if ((x * y).isEven) '${x * y ~/ 2} $birim',
    if (n <= 1000000) '$n $birim',
    '${_kok(2 * k, m)} $birim',
    if (k.isEven) '${_kok(k ~/ 2, m)} $birim',
    '${_kok(k + 1, m)} $birim',
  ];
}

// ---------------------------------------------------------------------------
// 6 · İç teğet ve çevrel çember

/// Hipotenüsü en çok 200 olan bütün Pisagor üçlüleri (u < v < w).
final _pisagor200 = [
  for (var w = 5; w <= 200; w++)
    for (var u = 3; u < w; u++)
      for (var v = u + 1; v < w; v++)
        if (u * u + v * v == w * w) (u, v, w),
];

/// Heron üçgenleri (dik olmayan, ilkel, kenarlar en çok 50, alan tam sayı).
final _heronTam50 = _ucgenler(1, 50, 1);

/// R ≥ (1 + √2)·r koşulunu sağlayan en küçük tam sayı R (dik üçgen vardır).
int _enKucukR(int r) {
  var R = 2 * r;
  while (R * R - 2 * r * R - r * r <= 0) {
    R++;
  }
  return R;
}

/// c ≥ 2r(1 + √2) koşulunu sağlayan en küçük tam sayı hipotenüs.
int _enKucukHip(int r) {
  var c = 4 * r;
  while (c * c - 4 * r * c - 4 * r * r <= 0) {
    c++;
  }
  return c;
}

// ---------------------------------------------------------------------------
// 7 · Paralelkenar ve eşkenar dörtgen

const _dortgenKatsayi = [
  (2, 3),
  (3, 1),
  (1, 2),
  (4, 1),
  (3, 2),
  (2, 1),
  (1, 3),
  (5, 2),
  (2, 5),
  (3, 4),
];

// ---------------------------------------------------------------------------
// 9 · Alan oranları

/// Aralarında asal, eşit olmayan oranlar.
const _orantilar = [
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
  (3, 5),
  (5, 3),
  (4, 5),
  (5, 4),
  (1, 5),
  (5, 1),
  (2, 7),
  (7, 2),
  (3, 7),
  (7, 3),
  (4, 7),
  (7, 4),
  (5, 6),
];

// ---------------------------------------------------------------------------
// 10 · Çemberde teğet ve iki çemberin konumu

const _konumlar = [
  'Çemberler dıştan teğettir.',
  'Çemberler iki noktada kesişir.',
  'Çemberler ayrıktır; biri diğerinin dışındadır.',
  'Çemberler içten teğettir.',
  'Küçük çember büyük çemberin içindedir; ortak noktaları yoktur.',
];

/// Konum türüne göre merkezler arası uzaklık (r1 < r2, r2 − r1 ≥ 2).
int _konumUzaklik(int tur, int r1, int r2, int s) => switch (tur) {
  0 => r1 + r2,
  1 => r2 + r1 ~/ 2,
  2 => r1 + r2 + 1 + s % 5,
  3 => r2 - r1,
  _ => r2 - r1 - 1,
};

const _konumGerekce = [
  'd = r₁ + r₂ olduğundan çemberler dıştan teğettir',
  'r₂ − r₁ < d < r₁ + r₂ olduğundan çemberler iki noktada kesişir',
  'd > r₁ + r₂ olduğundan çemberler ayrıktır ve biri diğerinin dışındadır',
  'd = r₂ − r₁ olduğundan çemberler içten teğettir',
  'd < r₂ − r₁ olduğundan küçük çember büyüğün içinde kalır',
];
const _ortakTeget = [3, 2, 4, 1, 0];

/// Tam kare ise karekökü, değilse null (n ≤ 0 için de null).
int? _tamKok(int n) {
  if (n <= 0) return null;
  var k = 0;
  while ((k + 1) * (k + 1) <= n) {
    k++;
  }
  return k * k == n ? k : null;
}

// ---------------------------------------------------------------------------
// 11 · Daire halkası

const _halkaAci = [30, 45, 60, 72, 90, 120, 135, 150, 216, 270];

/// Halka dilimi alanının tam çıkması için yarıçap farkının temel adımı.
int _halkaAdim(int aci) => switch (360 ~/ aci.gcd(360)) {
  12 || 6 => 6,
  8 => 4,
  5 => 5,
  4 => 2,
  _ => 3,
};

/// R² > 2r² koşulunu sağlayan en küçük tam sayı R.
int _karekokIkiUstu(int r) {
  var R = r + 1;
  while (R * R <= 2 * r * r) {
    R++;
  }
  return R;
}

// ---------------------------------------------------------------------------
// 12 · Düzgün altıgen ve sekizgen

/// Aynı paritede (x, y), x > y ≥ 1: altıgen çerçevede k = 3(x² − y²)/2 tam.
final _altigenCerceve = [
  for (var x = 3; x <= 70; x++)
    for (var y = x - 2; y >= 1; y -= 2) (x, y),
];

/// x > y ≥ 1 bütün ikililer (sekizgen çerçeve).
final _sekizgenCerceve = [
  for (var x = 2; x <= 50; x++)
    for (var y = x - 1; y >= 1; y--) (x, y),
];

const _sekizgenKatsayi = [
  (3, 1),
  (5, 1),
  (6, 1),
  (7, 2),
  (9, 1),
  (10, 1),
  (12, 1),
  (4, 1),
  (11, 2),
  (13, 1),
];
const _altigenKatsayi = [
  (3, 1),
  (5, 2),
  (1, 1),
  (4, 1),
  (5, 1),
  (7, 2),
  (3, 2),
  (5, 3),
  (7, 3),
  (6, 1),
];

// ---------------------------------------------------------------------------
// 13 · Piramit

/// Yönlü ilkel üçlüler ve ölçek: taban yarısı k·l1, yükseklik k·l2, yan yüz
/// yüksekliği k·w; taban ayrıtı ve yükseklik en çok 200 cm.
final _piramitUclu = [
  for (var a = 0; a < 25; a++)
    for (var k = 1; k <= 10; k++)
      if (2 * k * _yonluUclu(a).$1 <= 200 && k * _yonluUclu(a).$2 <= 200)
        (_yonluUclu(a), k),
];

// ---------------------------------------------------------------------------
// 14 · Hacim korunumu

/// pay/payda en çok iki ondalıkla yazılabiliyorsa değeri, değilse null.
double? _ondalik(int pay, int payda) {
  if (payda == 0) return null;
  final g = pay.gcd(payda);
  return 100 % (payda ~/ g) == 0 ? pay / payda : null;
}

bool _temizAralik(int pay, int payda, double alt, double ust) {
  final v = _ondalik(pay, payda);
  return v != null && v >= alt && v <= ust;
}

/// Küp (ayrıt e) prizma kaba (taban L × W): yükselme e³ / (L·W).
final _suKup = [
  for (var e = 3; e <= 25; e++)
    for (var w = e + 2; w <= 70; w++)
      for (var l = w; l <= 90; l++)
        if (_temizAralik(e * e * e, l * w, 0.5, 30)) (e, l, w),
];

/// N bilye (yarıçap r) silindir kaba (yarıçap R): 4Nr³ / (3R²).
final _suBilye = [
  for (var n = 1; n <= 20; n++)
    for (var r = 1; r <= 8; r++)
      for (var R = 2 * r + 1; R <= 50; R++)
        if (_temizAralik(4 * n * r * r * r, 3 * R * R, 0.5, 30)) (n, r, R),
];

/// Blok (x × y × z) silindir kaba (yarıçap R, π = 3): xyz / (3R²).
final _suBlokSilindir = [
  for (var x = 2; x <= 15; x++)
    for (var y = x; y <= 15; y++)
      for (var z = 2; z <= 20; z++)
        for (var R = 4; R <= 40; R++)
          if (x * x + y * y < 4 * R * R &&
              _temizAralik(x * y * z, 3 * R * R, 0.5, 30))
            (x, y, z, R),
];

/// Silindirden silindire: h₂ = h₁·r₁² / r₂².
final _suSilindir = [
  for (var r1 = 2; r1 <= 30; r1++)
    for (var h1 = 2; h1 <= 40; h1++)
      for (var r2 = 2; r2 <= 30; r2++)
        if (r2 != r1 && _temizAralik(h1 * r1 * r1, r2 * r2, 0.5, 30))
          (r1, h1, r2),
];

/// Prizmadan prizmaya: h₂ = h₁·L₁W₁ / (L₂W₂).
final _suPrizma = [
  for (var l1 = 10; l1 <= 50; l1 += 5)
    for (var w1 = 10; w1 <= l1; w1 += 5)
      for (var h1 = 2; h1 <= 30; h1++)
        for (var l2 = 10; l2 <= 60; l2 += 5)
          for (var w2 = 10; w2 <= l2; w2 += 5)
            if ((l1, w1) != (l2, w2) &&
                _temizAralik(h1 * l1 * w1, l2 * w2, 0.5, 30))
              (l1, w1, h1, l2, w2),
];

/// Koniden silindire: h₂ = h·r₁² / (3r₂²).
final _suKoni = [
  for (var r1 = 2; r1 <= 30; r1++)
    for (var h = 3; h <= 60; h++)
      for (var r2 = 2; r2 <= 30; r2++)
        if (_temizAralik(h * r1 * r1, 3 * r2 * r2, 0.5, 30)) (r1, h, r2),
];

/// Prizma kaptan çıkarılan blok (x × y × z): düşüş xyz / (L·W).
final _suBlok = [
  for (var x = 2; x <= 20; x++)
    for (var y = x; y <= 20; y++)
      for (var z = 2; z <= 20; z++)
        for (var w = 10; w <= 60; w += 5)
          for (var l = w; l <= 80; l += 5)
            if (x < w && y < l && _temizAralik(x * y * z, l * w, 0.5, 30))
              (x, y, z, l, w),
];

/// Silindir çubuk (r, h) silindir kaba (R): r²h / R².
final _suCubuk = [
  for (var r = 1; r <= 10; r++)
    for (var h = 5; h <= 40; h++)
      for (var R = r + 2; R <= 40; R++)
        if (_temizAralik(r * r * h, R * R, 0.5, 30)) (r, h, R),
];

/// Prizmadan silindire (π = 3): h₂ = LWh / (3r²).
final _suPrizmaSilindir = [
  for (var l = 10; l <= 60; l++)
    for (var w = 10; w <= l; w++)
      for (var h = 2; h <= 30; h++)
        for (var r = 3; r <= 30; r++)
          if (_temizAralik(l * w * h, 3 * r * r, 0.5, 30)) (l, w, h, r),
];

/// Silindirden prizmaya (π = 3): h₂ = 3r²h / (LW).
final _suSilindirPrizma = [
  for (var r = 3; r <= 20; r++)
    for (var h = 2; h <= 30; h++)
      for (var w = 10; w <= 60; w += 2)
        for (var l = w; l <= 80; l += 2)
          if (_temizAralik(3 * r * r * h, l * w, 0.5, 30)) (r, h, l, w),
];

/// Koni biçimli cisim (r, h) silindir kaba (R): r²h / (3R²).
final _suKoniCisim = [
  for (var r = 2; r <= 15; r++)
    for (var h = 3; h <= 40; h++)
      for (var R = r + 1; R <= 40; R++)
        if (_temizAralik(r * r * h, 3 * R * R, 0.5, 30)) (r, h, R),
];

/// Listeden 500 vakayı eşit aralıkla seçer.
T _yay<T>(List<T> l, int i) => l[i * l.length ~/ 500];

// ---------------------------------------------------------------------------
// 15 · Benzer cisimler

/// Küçükten büyüğe benzerlik oranları (m < n, aralarında asal).
const _benzerOran = [
  (1, 2),
  (1, 3),
  (2, 3),
  (1, 4),
  (3, 4),
  (2, 5),
  (3, 5),
  (4, 5),
  (1, 5),
  (5, 6),
  (2, 7),
  (3, 7),
  (4, 7),
  (5, 7),
  (6, 7),
  (3, 8),
  (5, 8),
  (7, 8),
  (4, 9),
  (5, 9),
  (7, 9),
  (8, 9),
  (3, 10),
  (7, 10),
  (9, 10),
];
const _benzerCisim = [
  'dik dairesel koni',
  'dik dairesel silindir',
  'kare dik piramit',
  'dikdörtgenler prizması',
  'düzgün üçgen piramit',
];

// ---------------------------------------------------------------------------
// 16–20 · Analitik geometri

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

/// px + qy = r biçiminde doğru denklemi.
String _dogruEsit(int p, int q, int r) =>
    '${_ifade([(p, 'x'), (q, 'y')])} = ${_m(r)}';

/// y = mx + n biçimi.
String _egimli(int m, int n) => 'y = ${_ifade([(m, 'x'), (n, '')])}';

/// Nokta yanıtlı soru; yinelenenler atılır, gerekirse komşu noktalarla
/// tamamlanır.
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

/// İşaretli tam sayı yanıtlı soru.
AdvancedItem _tam(
  String prompt,
  int dogru,
  List<int> yanlis,
  String aciklama,
) => secenekli(
  prompt,
  _m(dogru),
  [...yanlis, dogru + 1, dogru - 1, dogru + 2, dogru - 2, dogru + 3].map(_m),
  aciklama,
);

/// Kesişim sorularında katsayı çiftleri (determinant sıfırdan farklı).
const _kesisimKatsayi = [
  ((1, 1), (1, -1)),
  ((2, 1), (1, -1)),
  ((1, 2), (3, -1)),
  ((2, -3), (1, 1)),
  ((3, 2), (1, -2)),
  ((1, -1), (2, 3)),
  ((4, 1), (1, 2)),
  ((2, 5), (1, -3)),
];
const _egimler = [2, -1, 3, -2, 1, -3, 4, -4];
const _yonler = [(1, 2), (2, 1), (1, -1), (3, 1), (1, 3), (2, -1)];

/// (x − h)² yazımı; h sıfırsa x².
String _kare(String v, int h) =>
    h == 0 ? '$v²' : (h > 0 ? '($v − $h)²' : '($v + ${-h})²');

String _cember(int h, int k, int sag) =>
    '${_kare('x', h)} + ${_kare('y', k)} = $sag';

/// px + qy + r = 0 biçiminde doğru denklemi.
String _dnk(int p, int q, int r) {
  final z = p < 0 || (p == 0 && q < 0) ? -1 : 1;
  return '${_ifade([(z * p, 'x'), (z * q, 'y'), (z * r, '')])} = 0';
}

/// Normal uzunluğu tam sayı olan doğru katsayıları (A, B, √(A² + B²)).
const _normaller = [
  (3, 4, 5),
  (4, -3, 5),
  (5, 12, 13),
  (12, -5, 13),
  (8, 15, 17),
  (15, -8, 17),
];

const _dogruKonum = [
  'Doğru çemberi iki noktada keser.',
  'Doğru çembere teğettir.',
  'Doğru çemberi kesmez.',
  'Doğru çemberin merkezinden geçer.',
];

/// Döndürme: orijin etrafında pozitif yönde 90°·n.
(int, int) _dondur(int n, (int, int) p) => switch (n % 4) {
  0 => p,
  1 => (-p.$2, p.$1),
  2 => (-p.$1, -p.$2),
  _ => (p.$2, -p.$1),
};

/// Unicode eksi işaretli sade kesir.
String _kesirli(int n, int d) => kesir(n, d).replaceFirst('-', '−');

/// Tam bölünüyorsa işaretli bölüm, değilse null.
int? _bolIsaretli(int pay, int payda) =>
    payda != 0 && pay % payda == 0 ? pay ~/ payda : null;

/// Sıfırdan farklı koordinat: a − 12 sıfıra düşerse 13 alınır.
int _sifirsiz(int v, int yerine) => v == 0 ? yerine : v;

final lmGeometriEk = <AdvancedFamily>[
  // 1 · Paralel doğrular ve kesen; kırık çizgi kuralı.
  lmAile(
    'gm_paralel_aci',
    'Paralel doğrularda kesenle oluşan açılar ve kırık çizgi',
    _mat,
    Difficulty.easy,
    BloomLevel.uygulama,
    (a, b, c) {
      final j = c ~/ 3;
      return switch (c % 3) {
        0 => _kesenAcisi(a, b, j),
        1 => _kirikZ(a, b, j),
        _ => _kirikU(a, b, j),
      };
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 2 · Üçgen eşitsizliği: üçüncü kenar, çevre ve ortak köşegen.
  lmAile(
    'gm_ucgen_esitsizligi',
    'Üçgen eşitsizliği: kenar ve çevrenin tam sayı değerleri',
    _mat,
    Difficulty.medium,
    BloomLevel.analiz,
    (a, b, c) {
      final j = c ~/ 3;
      if (c % 3 == 2) {
        // ABD üçgeni üst sınırı, CBD üçgeni alt sınırı belirler.
        final l = 16 + a, n = 2 + b % 10, o = b ~/ 10, ust = l + n + 1;
        final p = ust ~/ 2 - 2 * o, q = ust - p;
        final r = n + 2 + o, s = r + l;
        final veri =
            'ABCD dörtgeninde |AB| = $p cm, |AD| = $q cm, |BC| = $r cm ve '
            '|CD| = $s cm olarak veriliyor. [BD] köşegeninin uzunluğu cm '
            'cinsinden bir tam sayı olduğuna göre';
        final cozum =
            'ABD üçgeninde ${(q - p).abs()} < |BD| < $ust, CBD üçgeninde $l < '
            '|BD| < ${r + s} olur. İki koşul birlikte $l < |BD| < $ust verir;';
        return switch (j) {
          0 => sayisal(
            '$veri bu uzunluk kaç farklı değer alabilir?',
            n,
            [2 * (p < q ? p : q) - 1, 2 * r - 1, n + 2, n + 1],
            '$cozum uygun tam sayılar en küçüğü ${l + 1}, en büyüğü '
                '${ust - 1} olmak üzere $n tanedir.',
            positive: true,
          ),
          1 => sayisal(
            '$veri |BD| en çok kaç cm olabilir?',
            ust - 1,
            [r + s - 1, ust, l + 1],
            '$cozum en büyük tam sayı değeri ${ust - 1} cm olur.',
            unit: 'cm',
            positive: true,
          ),
          _ => sayisal(
            '$veri |BD| en az kaç cm olabilir?',
            l + 1,
            [(q - p).abs() + 1, l, ust - 1],
            '$cozum en küçük tam sayı değeri ${l + 1} cm olur.',
            unit: 'cm',
            positive: true,
          ),
        };
      }
      final cevre = c % 3 == 1;
      final cesit = cevre && j == 2;
      final p = cesit ? 4 + a : 3 + a;
      var q = p + 1 + b;
      // Yanıtın kökteki bir kenara eşit çıktığı değerler atlanır.
      final atla = cesit
          ? 2 * p - 3
          : (!cevre && j != 1 && j != 3 ? 2 * p - 1 : 0);
      if (atla > p && q >= atla) q++;
      final ters = (a + b + c).isOdd;
      final ab = ters ? q : p, ac = ters ? p : q;
      final lo = q - p + 1, hi = p + q - 1, adet = 2 * p - 1;
      final giris = cesit
          ? 'Kenarlarından hiçbiri birbirine eşit olmayan bir ABC üçgeninde '
                '|AB| = $ab cm ve |AC| = $ac cm olarak veriliyor.'
          : 'ABC üçgeninde |AB| = $ab cm ve |AC| = $ac cm olarak veriliyor.';
      final veri =
          '$giris |BC| uzunluğu cm cinsinden bir tam sayı olduğuna göre';
      final kural =
          'Üçgen eşitsizliğine göre $q − $p < |BC| < $q + $p, yani '
          '${q - p} < |BC| < ${p + q} olur.';
      if (!cevre) {
        return switch (j) {
          0 => sayisal(
            '$veri bu uzunluk kaç farklı değer alabilir?',
            adet,
            [adet + 2, adet + 1, hi, 2 * p],
            '$kural Uygun tam sayılar en küçüğü $lo, en büyüğü $hi olmak '
                'üzere $adet tanedir.',
            positive: true,
          ),
          1 => sayisal(
            '$veri |BC| en çok kaç cm olabilir?',
            hi,
            [p + q, p + q + 1, lo],
            '$kural En büyük tam sayı değeri $hi cm olur.',
            unit: 'cm',
            positive: true,
          ),
          2 => sayisal(
            '$veri |BC| en az kaç cm olabilir?',
            lo,
            [q - p, hi, lo + 1],
            '$kural En küçük tam sayı değeri $lo cm olur.',
            unit: 'cm',
            positive: true,
          ),
          _ => sayisal(
            '$veri |BC| uzunluğunun alabileceği değerlerin toplamı kaçtır?',
            adet * q,
            [(adet + 2) * q, p * (2 * q + 1), (adet - 2) * q],
            '$kural Değerler $lo, ${lo + 1}, …, $hi olup $adet tanedir; '
                'toplamları $adet·($lo + $hi) / 2 = ${adet * q}.',
            positive: true,
          ),
        };
      }
      return switch (j) {
        0 => sayisal(
          '$veri ABC üçgeninin çevresi en çok kaç cm olabilir?',
          p + q + hi,
          [2 * (p + q), hi, p + q + lo, 2 * (p + q) + 1],
          '$kural |BC| en çok $hi cm olduğundan çevre en çok $p + $q + $hi = '
              '${p + q + hi} cm olur.',
          unit: 'cm',
          positive: true,
        ),
        1 => sayisal(
          '$veri ABC üçgeninin çevresi en az kaç cm olabilir?',
          p + q + lo,
          [2 * q, lo, p + q + hi, 2 * q + 2],
          '$kural |BC| en az $lo cm olduğundan çevre en az $p + $q + $lo = '
              '${p + q + lo} cm olur.',
          unit: 'cm',
          positive: true,
        ),
        // $p değeri aralıkta yalnız q < 2p olduğunda bulunur.
        _ =>
          q < 2 * p
              ? sayisal(
                  '$veri |BC| kaç farklı değer alabilir?',
                  adet - 2,
                  [adet, adet - 1, adet + 2],
                  '$kural Bu aralıktaki $adet tam sayıdan üçgeni ikizkenar yapan '
                      '$p ve $q değerleri çıkarılır: $adet − 2 = ${adet - 2}.',
                  positive: true,
                )
              : sayisal(
                  '$veri |BC| kaç farklı değer alabilir?',
                  adet - 1,
                  [adet, adet - 2, adet + 1],
                  '$kural Bu aralıktaki $adet tam sayıdan yalnız $q değeri üçgeni '
                      'ikizkenar yapar ($p değeri aralıkta değildir): $adet − 1 = '
                      '${adet - 1}.',
                  positive: true,
                ),
      };
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 3 · Açı-kenar bağıntısı: sıralama, açı ifadeleri, dar ve geniş açı.
  lmAile(
    'gm_aci_kenar',
    'Üçgende açı-kenar bağıntısı ve sıralama',
    _mat,
    Difficulty.easy,
    BloomLevel.anlama,
    (a, b, c) {
      const soruKenar =
          'Buna göre üçgenin kenar uzunlukları arasındaki doğru sıralama '
          'hangisidir?';
      if (c < 3) {
        final u = 35 + 2 * a;
        var v = 30 + 3 * b;
        int w() => 180 - u - v;
        while (u == v || u == w() || v == w()) {
          v++;
        }
        final (k1, k2, k3) = const [
          ('A', 'B', 'C'),
          ('A', 'C', 'B'),
          ('B', 'C', 'A'),
        ][c];
        final aci = {k1: u, k2: v, k3: w()};
        final artan = _artanKose(aci);
        final (dogru, yanlis) = _siralama([
          for (final k in artan) _karsiKenar[k]!,
        ]);
        return secenekli(
          'ABC üçgeninde $k1 açısının ölçüsü $u°, $k2 açısının ölçüsü $v° '
              'olarak veriliyor. $soruKenar',
          dogru,
          yanlis,
          'Üçüncü açı $k3 = 180° − $u° − $v° = ${w()}° olur. Büyük açı '
              'karşısında büyük kenar bulunur: ${artan.map((k) => '$k = ${aci[k]}°').join(' < ')} '
              'olduğundan $dogru.',
        );
      }
      if (c < 6) {
        final s1 = 5 + a, s2 = s1 + 1 + b % 5, s3 = s2 + 1 + b ~/ 5;
        final d = ucluDizilimler[(c - 3) * 2 + a % 2];
        final uz = [s1, s2, s3];
        final ab = uz[d[0]], bc = uz[d[1]], ac = uz[d[2]];
        // Kenarın karşısındaki açı: |AB| → C, |BC| → A, |AC| → B.
        final karsi = {'C': ab, 'A': bc, 'B': ac};
        final artan = _artanKose(karsi);
        final (dogru, yanlis) = _siralama([for (final k in artan) 'm($k)']);
        return secenekli(
          'ABC üçgeninde |AB| = $ab cm, |BC| = $bc cm ve |AC| = $ac cm olarak '
              'veriliyor. m(A), m(B) ve m(C) sırasıyla A, B ve C köşelerindeki iç '
              'açıların ölçüleri olduğuna göre bu ölçüler arasındaki doğru '
              'sıralama hangisidir?',
          dogru,
          yanlis,
          'Büyük kenar karşısında büyük açı bulunur. |AB| kenarı C, |BC| '
              'kenarı A, |AC| kenarı B köşesinin karşısındadır. '
              '${artan.map((k) => '${karsi[k]}').join(' < ')} olduğundan $dogru.',
        );
      }
      if (c < 8) {
        final x = 8 + a;
        final (p1, p2, p3) = _ucluKatsayi[b % 5];
        final (t1, t2, t3) = _ucluAci[(b ~/ 5) * 2 + (c - 6)];
        final q1 = t1 - p1 * x, q2 = t2 - p2 * x, q3 = t3 - p3 * x;
        final aci = {'A': t1, 'B': t2, 'C': t3};
        final artan = _artanKose(aci);
        final (dogru, yanlis) = _siralama([
          for (final k in artan) _karsiKenar[k]!,
        ]);
        return secenekli(
          'ABC üçgeninde A açısının ölçüsü (${_dx(p1, q1)})°, B açısının '
              'ölçüsü (${_dx(p2, q2)})° ve C açısının ölçüsü (${_dx(p3, q3)})° '
              'olarak veriliyor. $soruKenar',
          dogru,
          yanlis,
          'İç açılar toplamı 180° olduğundan 6x ${q1 + q2 + q3 < 0 ? '−' : '+'} '
              '${(q1 + q2 + q3).abs()} = 180, x = $x bulunur. Açılar '
              '${_aciListesi(aci)} olur. Büyük açı karşısında büyük kenar '
              'bulunduğundan $dogru.',
        );
      }
      final dar = c == 9;
      final p = dar ? 8 + a : 3 + a, q = p + 1 + b;
      final ters = (a + b).isOdd;
      final ab = ters ? q : p, ac = ters ? p : q;
      final kare = p * p + q * q;
      var kk = 0;
      while ((kk + 1) * (kk + 1) <= kare) {
        kk++;
      }
      final tam = kk * kk == kare;
      final veri =
          'ABC üçgeninde |AB| = $ab cm, |AC| = $ac cm ve A açısı '
          '${dar ? 'dar' : 'geniş'} açıdır. |BC| uzunluğu cm cinsinden bir tam '
          'sayı olduğuna göre';
      final kok = tam
          ? '√$kare = $kk'
          : '√$kare sayısı $kk ile ${kk + 1} arasında';
      if (dar) {
        final enb = tam ? kk - 1 : kk;
        return sayisal(
          '$veri |BC| en çok kaç cm olabilir?',
          enb,
          [p + q - 1, kk + 1, if (tam) kk else kk - 1],
          'A açısı dar olduğundan |BC|² < $ab² + $ac² = $kare olur; $kok '
              'olduğundan |BC| en çok $enb cm olabilir. Bu değer üçgen '
              'eşitsizliğini de sağlar.',
          unit: 'cm',
          positive: true,
        );
      }
      final adet = p + q - 1 - kk;
      return sayisal(
        '$veri bu uzunluk kaç farklı değer alabilir?',
        adet,
        [2 * p - 1, adet + 1, if (adet > 1) adet - 1, p + q - kk],
        'A açısı geniş olduğundan |BC|² > $ab² + $ac² = $kare olur; $kok '
            'olduğundan |BC| ≥ ${kk + 1}. Üçgen eşitsizliğinden |BC| < ${p + q} '
            'olur. Uygun tam sayılar en küçüğü ${kk + 1}, en büyüğü '
            '${p + q - 1} olmak üzere $adet tanedir.',
        positive: true,
      );
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 4 · Dik üçgende sinüs, kosinüs ve tanjant.
  lmAile(
    'gm_dik_ucgen_trig',
    'Dik üçgende sinüs, kosinüs ve tanjant oranları',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final (l1, l2, w) = _yonluUclu(a);
      if (c < 4) {
        final k = 1 + b % 4, g = b ~/ 4;
        // (dik köşe, P1, P2, verilen kenarlar).
        final (r, p1, p2) = switch (g) {
          0 || 1 => ('B', 'A', 'C'),
          2 => ('C', 'B', 'A'),
          3 => ('A', 'B', 'C'),
          _ => ('C', 'A', 'B'),
        };
        final kom = _kenar(p1, r), kar = _kenar(p2, r), hip = _kenar(p1, p2);
        final (veri, eksik) = switch (g) {
          0 || 3 => (
            '$kom = ${k * l1} cm ve $kar = ${k * l2} cm',
            'Hipotenüs $hip = √(${k * l1}² + ${k * l2}²) = ${k * w} cm olur.',
          ),
          // g = 1, 2, 4: bir dik kenar ve hipotenüs; dik kenarın adı her
          // düzende farklıdır (|AB|, |BC|, |AC|).
          _ => (
            '$kom = ${k * l1} cm ve $hip = ${k * w} cm',
            'Diğer dik kenar $kar = √(${k * w}² − ${k * l1}²) = ${k * l2} cm '
                'olur.',
          ),
        };
        final (ad, kose, pay, payda, yanlis, tanim) = switch (c) {
          0 => (
            'sin',
            p1,
            l2,
            w,
            [(l1, w), (l2, l1), (l1, l2)],
            'sin $p1 = karşı dik kenar / hipotenüs = $kar / $hip',
          ),
          1 => (
            'cos',
            p1,
            l1,
            w,
            [(l2, w), (l2, l1), (l1, l2)],
            'cos $p1 = komşu dik kenar / hipotenüs = $kom / $hip',
          ),
          2 => (
            'tan',
            p1,
            l2,
            l1,
            [(l2, w), (l1, w), (l1, l2)],
            'tan $p1 = karşı dik kenar / komşu dik kenar = $kar / $kom',
          ),
          _ => (
            'sin',
            p2,
            l1,
            w,
            [(l2, w), (l1, l2), (l2, l1)],
            'sin $p2 = karşı dik kenar / hipotenüs = $kom / $hip',
          ),
        };
        final ham = switch (c) {
          0 => '${k * l2}/${k * w}',
          1 => '${k * l1}/${k * w}',
          2 => '${k * l2}/${k * l1}',
          _ => '${k * l1}/${k * w}',
        };
        final sade = kesir(pay, payda);
        return kesirli(
          'ABC üçgeninde $r açısının ölçüsü 90° olup $veri olarak veriliyor. '
              'Buna göre $ad $kose değeri kaçtır?',
          pay,
          payda,
          yanlis,
          '$eksik $tanim = $ham${ham == sade ? '' : ' = $sade'}.',
        );
      }
      // Ölçek en az 2: kenarlar orandaki sayılarla aynı çıkmaz.
      final v = b % 5;
      var k = 2 + b ~/ 5;
      // 6-8-10 üçgeninde alan çevreye eşittir; bu vaka ölçek 6 ile sorulur.
      if (c == 9 && k * l1 * l2 == 2 * (l1 + l2 + w)) k = 6;
      final (r, p1, p2) = c < 7 ? _dikKoseler[c - 4] : _dikKoseler[v % 3];
      final kom = _kenar(p1, r), kar = _kenar(p2, r), hip = _kenar(p1, p2);
      final sinP = kesir(l2, w), cosP = kesir(l1, w), tanP = kesir(l2, l1);
      if (c < 7) {
        final (oran, verilen, sorulan, yanit, yanlis, cozum) = switch (v) {
          0 => (
            'sin $p1 = $sinP',
            '$hip = ${k * w} cm',
            kom,
            k * l1,
            [k * l2, k * (w - l2), k * w],
            'sin $p1 = $kar / $hip = $sinP olduğundan $kar = ${k * l2} cm '
                'olur. Pisagor bağıntısıyla $kom = √(${k * w}² − '
                '${k * l2}²) = ${k * l1} cm bulunur.',
          ),
          1 => (
            'cos $p1 = $cosP',
            '$kom = ${k * l1} cm',
            hip,
            k * w,
            [k * l2, k * (l1 + l2)],
            'cos $p1 = $kom / $hip = $cosP olduğundan ${k * l1} / $hip = '
                '$cosP, $hip = ${k * w} cm bulunur.',
          ),
          2 => (
            'tan $p1 = $tanP',
            '$kom = ${k * l1} cm',
            kar,
            k * l2,
            [k * w, k * (w - l1), k * l1],
            'tan $p1 = $kar / $kom = $tanP olduğundan $kar = ${k * l1}·'
                '$tanP = ${k * l2} cm bulunur.',
          ),
          3 => (
            'tan $p1 = $tanP',
            '$kar = ${k * l2} cm',
            hip,
            k * w,
            [k * l1, k * (l1 + l2)],
            'tan $p1 = $kar / $kom = $tanP olduğundan $kom = ${k * l1} cm '
                'olur. Pisagor bağıntısıyla $hip = √(${k * l1}² + '
                '${k * l2}²) = ${k * w} cm bulunur.',
          ),
          _ => (
            'cos $p1 = $cosP',
            '$hip = ${k * w} cm',
            kar,
            k * l2,
            [k * l1, k * (w - l1), k * w],
            'cos $p1 = $kom / $hip = $cosP olduğundan $kom = ${k * l1} cm '
                'olur. Pisagor bağıntısıyla $kar = √(${k * w}² − '
                '${k * l1}²) = ${k * l2} cm bulunur.',
          ),
        };
        return sayisal(
          'ABC üçgeninde $r açısının ölçüsü 90°, $oran ve $verilen olarak '
          'veriliyor. Buna göre $sorulan kaç cm olur?',
          yanit,
          yanlis,
          cozum,
          unit: 'cm',
          positive: true,
        );
      }
      final kenarlar =
          '$kom = ${k * l1} cm, $kar = ${k * l2} cm ve $hip = ${k * w} cm';
      final cevre = k * (l1 + l2 + w), alan = k * k * l1 * l2 ~/ 2;
      if (c == 9) {
        final (oran, deger) = switch (v) {
          0 => ('sin $p1', sinP),
          1 => ('cos $p1', cosP),
          2 => ('tan $p1', tanP),
          3 => ('sin $p2', cosP),
          _ => ('cos $p2', sinP),
        };
        return sayisal(
          'ABC üçgeninde $r açısının ölçüsü 90°, $oran = $deger ve üçgenin '
              'çevresi $cevre cm olarak veriliyor. Buna göre ABC üçgeninin alanı '
              'kaç cm² olur?',
          alan,
          [k * k * l1 * l2, l1 * l2 ~/ 2, k * k * l1 * w ~/ 2, cevre],
          'Oran $deger olduğundan kenarlar ${l1}t, ${l2}t ve ${w}t biçimindedir. '
              'Çevre ${l1 + l2 + w}t = $cevre eşitliğinden t = $k olur; '
              '$kenarlar. Alan ${k * l1}·${k * l2} / 2 = $alan cm².',
          unit: 'cm²',
          positive: true,
        );
      }
      final kl1 = k * l1, kl2 = k * l2, kw = k * w;
      final (oran, verilen, cozum) = switch (v) {
        0 => (
          'sin $p1 = $sinP',
          '$hip = $kw cm',
          'sin $p1 = $kar / $hip olduğundan $kar = $kl2 cm, Pisagor '
              'bağıntısıyla $kom = √($kw² − $kl2²) = $kl1 cm olur.',
        ),
        1 => (
          'cos $p1 = $cosP',
          '$kom = $kl1 cm',
          'cos $p1 = $kom / $hip olduğundan $hip = $kw cm, Pisagor '
              'bağıntısıyla $kar = √($kw² − $kl1²) = $kl2 cm olur.',
        ),
        2 => (
          'tan $p1 = $tanP',
          '$kom = $kl1 cm',
          'tan $p1 = $kar / $kom olduğundan $kar = $kl2 cm, Pisagor '
              'bağıntısıyla $hip = √($kl1² + $kl2²) = $kw cm olur.',
        ),
        3 => (
          'tan $p1 = $tanP',
          '$kar = $kl2 cm',
          'tan $p1 = $kar / $kom olduğundan $kom = $kl1 cm, Pisagor '
              'bağıntısıyla $hip = √($kl1² + $kl2²) = $kw cm olur.',
        ),
        _ => (
          'sin $p1 = $sinP',
          '$kar = $kl2 cm',
          'sin $p1 = $kar / $hip olduğundan $hip = $kw cm, Pisagor '
              'bağıntısıyla $kom = √($kw² − $kl2²) = $kl1 cm olur.',
        ),
      };
      final veri =
          'ABC üçgeninde $r açısının ölçüsü 90°, $oran ve $verilen olarak '
          'veriliyor.';
      if (c == 7) {
        return sayisal(
          '$veri Buna göre ABC üçgeninin çevresi kaç cm olur?',
          cevre,
          [k * (l2 + w), k * (l1 + w), l1 + l2 + w, k * (l1 + l2)],
          '$cozum Çevre ${k * l1} + ${k * l2} + ${k * w} = $cevre cm.',
          unit: 'cm',
          positive: true,
        );
      }
      return sayisal(
        '$veri Buna göre ABC üçgeninin alanı kaç cm² olur?',
        alan,
        [
          k * k * l1 * l2,
          if ((l2 * w).isEven) k * k * l2 * w ~/ 2,
          if ((l1 * w).isEven) k * k * l1 * w ~/ 2,
          cevre,
        ],
        '$cozum Alan, dik kenarların çarpımının yarısıdır: ${k * l1}·'
            '${k * l2} / 2 = $alan cm².',
        unit: 'cm²',
        positive: true,
      );
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 5 · Heron bağıntısı: alan ve bir kenara ait yükseklik.
  lmAile(
    'gm_heron',
    'Heron bağıntısıyla üçgenin alanı ve yüksekliği',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final i = a + 25 * b;
      if (c == 0) {
        // 500 vaka tarla havuzuna eşit aralıkla yayılır.
        final n = _heronTarla.length;
        final ((x0, y0, z0, a0, _), t) = _heronTarla[i * n ~/ 500];
        final x = t * x0, y = t * y0, z = t * z0, alan = t * t * a0;
        return secenekli(
          'Kenar uzunlukları $x m, $y m ve $z m olan üçgen biçimindeki bir '
              'tarlanın alanı kaç m² olur?',
          '$alan m²',
          _heronTamYanlis(x, y, z, alan, t, 'm²'),
          _heronOlcekli(x0, y0, z0, a0, t, 'm²'),
        );
      }
      if (c <= 2 || c >= 8) {
        // c = 1 ve 8: kenarlar verilir; c = 2 ve 9: çevre ve iki kenar.
        final (havuz, ilk) = switch (c) {
          1 => (_heronA1, 1),
          2 => (_heronA2, 1),
          8 => (_heronA3, 1),
          _ => (_heronA1, 4),
        };
        final (x0, y0, z0, k0, m) = havuz[i % havuz.length];
        final t = ilk + i ~/ havuz.length;
        final x = t * x0, y = t * y0, z = t * z0, kk = t * t * k0;
        final cozum = '${_heronAdim(x, y, z, kk, m)} cm² olur.';
        final yanlis = m == 1
            ? _heronTamYanlis(x, y, z, kk, t, 'cm²')
            : _heronYanlis(x, y, z, kk, m, 'cm²');
        if (c == 1 || c == 8) {
          return secenekli(
            'ABC üçgeninde |AB| = $x cm, |BC| = $y cm ve |AC| = $z cm olarak '
                'veriliyor. Buna göre ABC üçgeninin alanı kaç cm² olur?',
            '${_kok(kk, m)} cm²',
            yanlis,
            cozum,
          );
        }
        // Çevre ve iki kenar verilir; eksik kenar sırayla değişir.
        final kenar = [x, y, z];
        final e = i % 3;
        final verilen = [
          for (var j = 0; j < 3; j++)
            if (j != e) kenar[j],
        ];
        return secenekli(
          'Çevresi ${x + y + z} cm olan bir üçgenin iki kenarının uzunlukları '
              '${verilen[0]} cm ve ${verilen[1]} cm olduğuna göre bu üçgenin alanı '
              'kaç cm² olur?',
          '${_kok(kk, m)} cm²',
          yanlis,
          'Üçüncü kenar ${x + y + z} − ${verilen[0]} − ${verilen[1]} = '
              '${kenar[e]} cm olur. $cozum',
        );
      }
      // Yükseklik soruları.
      final ((x0, y0, z0, k0, m), kenar0, t) = _yukseklikVerisi(i, c);
      final soru = switch (c) {
        6 => 'en kısa yüksekliğinin',
        7 => 'en uzun yüksekliğinin',
        _ => 'A köşesinden [BC] kenarına inen yüksekliğin',
      };
      final x = t * x0, y = t * y0, z = t * z0, kk = t * t * k0;
      final s = t * kenar0;
      final h = _kokluDeger(2 * kk, s, m)!;
      final digerleri = [x, y, z]..remove(s);
      final String kok;
      if (c <= 5) {
        final (ab, ac) = i.isEven
            ? (digerleri[0], digerleri[1])
            : (digerleri[1], digerleri[0]);
        kok =
            'ABC üçgeninde |AB| = $ab cm, |BC| = $s cm ve |AC| = $ac cm '
            'olarak veriliyor. Buna göre $soru uzunluğu kaç cm olur?';
      } else {
        kok =
            'Kenar uzunlukları $x cm, $y cm ve $z cm olan bir üçgenin '
            '$soru uzunluğu kaç cm olur?';
      }
      final yanlis = <String>[
        for (final d in digerleri)
          if (_kokluDeger(2 * kk, d, m) case final v?) '$v cm',
        if (_kokluDeger(kk, s, m) case final v?) '$v cm',
        if (_kokluDeger(4 * kk, s, m) case final v?) '$v cm',
        '${_kok(kk, m)} cm',
        // Yedekler: yanıtın bir, iki ve üç fazlası.
        for (var e = 1; e <= 3; e++) '${_kokluDeger(2 * kk + e * s, s, m)} cm',
      ];
      final neden = c == 6
          ? 'En kısa yükseklik en uzun kenara, yani $s cm uzunluğundaki '
                'kenara aittir. '
          : (c == 7
                ? 'En uzun yükseklik en kısa kenara, yani $s cm uzunluğundaki '
                      'kenara aittir. '
                : '');
      return secenekli(
        kok,
        '$h cm',
        yanlis,
        '${_heronAdim(x, y, z, kk, m)} cm² olur. ${neden}Alan = $s·h / 2 '
            'olduğundan h = 2·${_kok(kk, m)} / $s = $h cm.',
      );
    },
    exam: ExamKind.tyt,
    lesson: _tm,
    shortAnswer: false,
  ),
  // 6 · İç teğet çemberin ve çevrel çemberin yarıçapı.
  lmAile(
    'gm_ic_cevrel',
    'İç teğet ve çevrel çemberin yarıçapı',
    _mat,
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) {
      final i = a + 25 * b;
      if (c == 0) {
        // Pisagor üçlüleri dört biçimde: dik kenarlar → r, dik kenarlar → R,
        // kısa dik kenar ve hipotenüs → r, uzun dik kenar ve hipotenüs → r.
        final n = _pisagor200.length, tur = i ~/ n;
        final (u, v, w) = _pisagor200[i % n];
        final r = u * v ~/ (u + v + w), alan = u * v ~/ 2, s2 = u + v + w;
        final rCozum =
            'Alan $u·$v / 2 = $alan cm², yarı çevre ($u + $v + $w) / 2 = '
            '${tr(s2 / 2)} cm olur. İç teğet çemberin yarıçapı r = Alan / '
            'yarı çevre = $alan / ${tr(s2 / 2)} = $r cm.';
        final rYanlis = [2.0 * r, w / 2, r / 2];
        if (tur == 1) {
          return ondalikli(
            'Dik kenarlarının uzunlukları $u cm ve $v cm olan bir dik üçgenin '
                'çevrel çemberinin yarıçapı kaç cm olur?',
            w / 2,
            [w.toDouble(), r.toDouble(), (u + v) / 2, w / 4],
            'Hipotenüs √($u² + $v²) = $w cm olur. Dik üçgende çevrel çemberin '
                'merkezi hipotenüsün orta noktasıdır: R = $w / 2 = ${tr(w / 2)} '
                'cm.',
            unit: 'cm',
            positive: true,
          );
        }
        final (veri, eksik) = switch (tur) {
          0 => (
            'Dik kenarlarının uzunlukları $u cm ve $v cm olan',
            'Hipotenüs √($u² + $v²) = $w cm olur.',
          ),
          2 => (
            'Bir dik kenarı $u cm, hipotenüsü $w cm olan',
            'Diğer dik kenar √($w² − $u²) = $v cm olur.',
          ),
          _ => (
            'Bir dik kenarı $v cm, hipotenüsü $w cm olan',
            'Diğer dik kenar √($w² − $v²) = $u cm olur.',
          ),
        };
        return ondalikli(
          '$veri bir dik üçgenin iç teğet çemberinin yarıçapı kaç cm olur?',
          r.toDouble(),
          rYanlis,
          '$eksik $rCozum',
          unit: 'cm',
          positive: true,
        );
      }
      if (c == 1) {
        // Heron üçgenleri: ilk 250 vaka r, sonraki 250 vaka R.
        final cevrel = i >= 250, j = i % 250, n = _heronTam50.length;
        final (x0, y0, z0, a0, _) = _heronTam50[j % n];
        final t = 1 + j ~/ n;
        final x = t * x0, y = t * y0, z = t * z0, alan = t * t * a0;
        final s = (x + y + z) ~/ 2;
        final veri =
            'ABC üçgeninde |AB| = $x cm, |BC| = $y cm ve |AC| = $z cm olarak '
            'veriliyor. Buna göre ABC üçgeninin';
        final heron =
            'Yarı çevre s = $s cm, Heron bağıntısıyla alan √($s·${s - x}·'
            '${s - y}·${s - z}) = $alan cm² olur.';
        if (!cevrel) {
          return kesirli(
            '$veri iç teğet çemberinin yarıçapı kaç cm olur?',
            alan,
            s,
            [(alan, 2 * s), (2 * alan, s), (x * y * z, 4 * alan)],
            '$heron İç teğet çemberin yarıçapı r = Alan / s = $alan / $s = '
                '${kesir(alan, s)} cm.',
            unit: 'cm',
          );
        }
        return kesirli(
          '$veri çevrel çemberinin yarıçapı kaç cm olur?',
          x * y * z,
          4 * alan,
          [(x * y * z, 2 * alan), (x * y * z, alan), (alan, s)],
          '$heron Çevrel çemberin yarıçapı R = |AB|·|BC|·|AC| / (4·Alan) = '
              '${x * y * z} / ${4 * alan} = ${kesir(x * y * z, 4 * alan)} cm.',
          unit: 'cm',
        );
      }
      if (c == 2 || c == 3 || c == 9) {
        final r = 1 + a, R = _enKucukR(r) + b, hip = 2 * R;
        final veri =
            'Bir dik üçgenin iç teğet çemberinin yarıçapı $r cm, çevrel '
            'çemberinin yarıçapı $R cm olduğuna göre';
        final adim =
            'Dik üçgende hipotenüs çevrel çemberin çapıdır: c = 2·$R = $hip '
            'cm. Dik kenarlar a ve b olmak üzere r = (a + b − c) / 2 '
            'olduğundan a + b = 2·$r + $hip = ${2 * r + hip} cm olur.';
        return switch (c) {
          2 => sayisal(
            '$veri bu üçgenin çevresi kaç cm olur?',
            2 * r + 4 * R,
            [2 * r + 2 * R, r + 4 * R, 4 * r + 4 * R],
            '$adim Çevre ${2 * r + hip} + $hip = ${2 * r + 4 * R} cm.',
            unit: 'cm',
            positive: true,
          ),
          3 => sayisal(
            '$veri bu üçgenin alanı kaç cm² olur?',
            r * (r + 2 * R),
            [2 * r * (r + 2 * R), 2 * r * R, r * (r + R)],
            '$adim Yarı çevre s = ${2 * r + 4 * R} / 2 = ${r + 2 * R} cm ve '
                'alan r·s = $r·${r + 2 * R} = ${r * (r + 2 * R)} cm².',
            unit: 'cm²',
            positive: true,
          ),
          _ => sayisal(
            '$veri dik kenarlarının uzunlukları toplamı kaç cm olur?',
            2 * r + 2 * R,
            [2 * r + 4 * R, r + R, 4 * R],
            adim,
            unit: 'cm',
            positive: true,
          ),
        };
      }
      if (c == 4 || c == 8) {
        final r = c == 4 ? 1 + b : 1 + a % 20;
        final hip = _enKucukHip(r) + (c == 4 ? a : b + 20 * (a ~/ 20));
        final veri =
            'Hipotenüsü $hip cm olan bir dik üçgenin iç teğet çemberinin '
            'yarıçapı $r cm olduğuna göre';
        final adim =
            'Dik kenarlar a ve b olmak üzere r = (a + b − c) / 2 olduğundan '
            'a + b = 2·$r + $hip = ${2 * r + hip} cm olur.';
        if (c == 4) {
          return sayisal(
            '$veri bu üçgenin çevresi kaç cm olur?',
            2 * r + 2 * hip,
            [2 * hip + r, hip + 2 * r, 2 * hip + 4 * r],
            '$adim Çevre ${2 * r + hip} + $hip = ${2 * r + 2 * hip} cm.',
            unit: 'cm',
            positive: true,
          );
        }
        return sayisal(
          '$veri bu üçgenin alanı kaç cm² olur?',
          r * (r + hip),
          [r * hip, r * (r + 2 * hip), 2 * r * (r + hip)],
          '$adim Yarı çevre s = (${2 * r + hip} + $hip) / 2 = ${r + hip} cm, '
              'alan r·s = $r·${r + hip} = ${r * (r + hip)} cm².',
          unit: 'cm²',
          positive: true,
        );
      }
      if (c == 5) {
        // r = 1 ve r = 2 için alan yarı çevreye ya da çevreye eşit çıkar.
        final r = 3 + a, s = 6 * r + b, cevre = 2 * s;
        return sayisal(
          'Çevresi $cevre cm olan bir üçgenin iç teğet çemberinin yarıçapı $r '
              'cm olduğuna göre bu üçgenin alanı kaç cm² olur?',
          r * s,
          [r * cevre, if ((r * s).isEven) r * s ~/ 2, r + s],
          'Alan, iç teğet çemberin yarıçapı ile yarı çevrenin çarpımıdır: '
              'yarı çevre $cevre / 2 = $s cm, alan $r·$s = ${r * s} cm².',
          unit: 'cm²',
          positive: true,
        );
      }
      if (c == 6) {
        final r2 = a + b + 2, s = 6 + 6 * a + 7 * b;
        // r = r2 / 2; alan = r·s.
        final alanPay = r2 * s;
        final alan = alanPay / 2;
        return ondalikli(
          'Alanı ${tr(alan)} cm², çevresi ${2 * s} cm olan bir üçgenin iç '
              'teğet çemberinin yarıçapı kaç cm olur?',
          r2 / 2,
          [r2 / 4, r2.toDouble(), r2 / 2 + 1],
          'Alan = r·s eşitliğinde yarı çevre s = ${2 * s} / 2 = $s cm olur. '
              'r = Alan / s = ${tr(alan)} / $s = ${tr(r2 / 2)} cm.',
          unit: 'cm',
          positive: true,
        );
      }
      final m = 2 + a, n = m + 1 + b;
      return sayisal(
        'Bir dik üçgenin iç teğet çemberi hipotenüse D noktasında değiyor. D '
            'noktası hipotenüsü $m cm ve $n cm uzunluğunda iki parçaya ayırdığına '
            'göre bu üçgenin alanı kaç cm² olur?',
        m * n,
        [if ((m * n).isEven) m * n ~/ 2, 2 * m * n, m * m + n * n],
        'İç teğet çemberin yarıçapı r olsun. Köşeden çizilen teğet parçaları '
            'eşit olduğundan dik kenarlar ($m + r) ve ($n + r) cm olur. Pisagor '
            'bağıntısı ($m + r)² + ($n + r)² = ${m + n}² sadeleşince r² + '
            '${m + n}r = ${m * n} verir. Alan r·s = r·(${m + n} + r) = r² + '
            '${m + n}r = ${m * n} cm².',
        unit: 'cm²',
        positive: true,
      );
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 7 · Paralelkenar ve eşkenar dörtgen: açı, kenar, köşegen ve çevre.
  lmAile(
    'gm_paralelkenar',
    'Paralelkenar ve eşkenar dörtgende açı, kenar ve köşegen',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      if (c <= 1) {
        final x = 10 + a;
        final (p, r) = _dortgenKatsayi[b % 10];
        final ardisik = c == 0, sorC = (a + b).isEven;
        var t = 51 + 3 * (b % 10) + 40 * (b ~/ 10);
        // Yanıt kökte yazılı bir sayıya eşit çıkarsa A açısı bir derece
        // kaydırılır (kaydırılan değerler hiçbir vakanın asıl değeri değildir).
        int yanitAci(int u) => ardisik && sorC ? u : 180 - u;
        if ({
          (t - p * x).abs(),
          ((ardisik ? 180 - t : t) - r * x).abs(),
          p,
          r,
          x,
        }.contains(yanitAci(t))) {
          t++;
        }
        final q = t - p * x, s = (ardisik ? 180 - t : t) - r * x;
        final ikinci = ardisik ? 'B' : 'C';
        final cozum = ardisik
            ? 'Paralelkenarda ardışık iki açının ölçüleri toplamı 180° olur: '
                  '(${_dx(p, q)}) + (${_dx(r, s)}) = 180, ${p + r}x = '
                  '${(p + r) * x}, x = $x. m(A) = $t°, m(B) = ${180 - t}°.'
            : 'Paralelkenarda karşılıklı açıların ölçüleri eşittir: '
                  '${_dx(p, q)} = ${_dx(r, s)}, x = $x. m(A) = m(C) = $t°.';
        // Ardışık sorusunda C ya da D, karşılıklı sorusunda B ya da D sorulur.
        final (sorulan, yanit) = ardisik
            ? (sorC ? ('C', t) : ('D', 180 - t))
            : (sorC ? ('B', 180 - t) : ('D', 180 - t));
        final xKarisik = ardisik
            ? _bol(s - q, p - r)
            : _bol(180 - q - s, p + r);
        final karisik = xKarisik == null ? null : p * xKarisik + q;
        final son = ardisik
            ? (sorulan == 'C'
                  ? ' Karşılıklı açılar eşit olduğundan m(C) = m(A) = $t°.'
                  : ' Karşılıklı açılar eşit olduğundan m(D) = m(B) = '
                        '${180 - t}°.')
            : ' m($sorulan) açısı A açısına komşu olduğundan 180° − $t° = '
                  '${180 - t}°.';
        return _aci(
          'ABCD paralelkenarında A açısının ölçüsü (${_dx(p, q)})°, $ikinci '
              'açısının ölçüsü (${_dx(r, s)})° olarak veriliyor. Buna göre '
              '$sorulan açısının ölçüsü kaç derecedir?',
          yanit,
          [180 - yanit, x, ?karisik],
          '$cozum$son',
        );
      }
      if (c <= 3) {
        final p = 4 + a, q = 1 + b, cevre = 2 * (2 * p + q);
        const giris =
            'ABCD paralelkenarında A açısının açıortayı [DC] kenarını E '
            'noktasında kesiyor.';
        const kural =
            '[AB] ∥ [DC] olduğundan DEA ve EAB açıları iç ters açılardır; AE '
            'açıortay olduğundan DAE = EAB = DEA olur ve ADE üçgeni '
            'ikizkenardır.';
        if (c == 2) {
          return sayisal(
            '$giris |AD| = $p cm ve |EC| = $q cm olduğuna göre ABCD '
                'paralelkenarının çevresi kaç cm olur?',
            cevre,
            [2 * (p + q), 4 * p + q, 2 * p + q],
            '$kural |DE| = |AD| = $p cm, |DC| = $p + $q = ${p + q} cm. Çevre '
                '2·($p + ${p + q}) = $cevre cm.',
            unit: 'cm',
            positive: true,
          );
        }
        return sayisal(
          '$giris Paralelkenarın çevresi $cevre cm ve |EC| = $q cm olduğuna '
              'göre |AB| kaç cm olur?',
          p + q,
          [p, cevre ~/ 2 - q, ?_bol(cevre, 4)],
          '$kural |AD| = |DE| = x olsun; |AB| = |DC| = x + $q olur. Çevre '
              '2·(x + x + $q) = $cevre eşitliğinden x = $p cm ve |AB| = '
              '${p + q} cm.',
          unit: 'cm',
          positive: true,
        );
      }
      if (c == 4) {
        final p = 2 + a, q = p + 1 + b, k2 = p * p + q * q;
        return secenekli(
          'Köşegen uzunlukları ${2 * p} cm ve ${2 * q} cm olan bir eşkenar '
              'dörtgenin çevresi kaç cm olur?',
          '${_kok(4, k2)} cm',
          [
            '${_kok(8, k2)} cm',
            '${4 * (p + q)} cm',
            '${_kok(1, k2)} cm',
            '${_kok(2, k2)} cm',
          ],
          'Eşkenar dörtgenin köşegenleri birbirini dik ortalar; köşegenlerin '
              'yarıları $p cm ve $q cm olan dik üçgende kenar √($p² + $q²) = '
              '${_kok(1, k2)} cm olur. Çevre 4·${_kok(1, k2)} = ${_kok(4, k2)} '
              'cm.',
        );
      }
      if (c == 5) {
        final d = 1 + a, s = d + 1 + b, f2 = s * s - d * d;
        return secenekli(
          'Bir kenarının uzunluğu $s cm ve köşegenlerinden biri ${2 * d} cm '
              'olan eşkenar dörtgenin diğer köşegeni kaç cm olur?',
          '${_kok(2, f2)} cm',
          [
            '${_kok(1, f2)} cm',
            if (s > 2 * d) '${_kok(2, s * s - 4 * d * d)} cm',
            '${_kok(2, s * s + d * d)} cm',
            '${_kok(4, f2)} cm',
          ],
          'Köşegenler birbirini dik ortalar; köşegen yarısı $d cm ve kenar $s '
              'cm olan dik üçgende diğer köşegenin yarısı √($s² − $d²) = '
              '${_kok(1, f2)} cm olur. Diğer köşegen 2·${_kok(1, f2)} = '
              '${_kok(2, f2)} cm.',
        );
      }
      if (c == 6) {
        final x = 5 + a;
        final (p, r) = _dortgenKatsayi[b % 10];
        // ABD açısı 3'e bölümünden 1 kalan değerler alır (45° hiç çıkmaz);
        // yanıt kökteki bir sayıya eşitse bir derece kaydırılır.
        var be = 22 + 3 * (b % 10) + 30 * (b ~/ 10);
        final xSor = (a + b).isEven;
        if ({
          (be - p * x).abs(),
          (180 - 2 * be - r * x).abs(),
          p,
          r,
        }.contains(xSor ? x : 2 * be)) {
          be++;
        }
        final q = be - p * x, s = 180 - 2 * be - r * x;
        final veri =
            'ABCD eşkenar dörtgeninde ABD açısının ölçüsü (${_dx(p, q)})°, '
            'BCD açısının ölçüsü (${_dx(r, s)})° olarak veriliyor.';
        final cozum =
            'Eşkenar dörtgende köşegenler açıortaydır: m(ABC) = 2·m(ABD). '
            'Ardışık açılar bütünler olduğundan 2·(${_dx(p, q)}) + '
            '(${_dx(r, s)}) = 180, ${2 * p + r}x = ${(2 * p + r) * x}, x = $x '
            'bulunur. m(ABD) = $be° olur.';
        if (xSor) {
          return sayisal(
            '$veri Buna göre x kaçtır?',
            x,
            [be, ?_bol(180 - q - s, p + r)],
            cozum,
            positive: true,
          );
        }
        return _aci(
          '$veri Buna göre ADC açısının ölçüsü kaç derecedir?',
          2 * be,
          [be, 180 - 2 * be, 180 - be],
          '$cozum m(ADC) = m(ABC) = 2·$be° = ${2 * be}°.',
        );
      }
      if (c == 7) {
        final x = 2 + a;
        final (p, r) = _dortgenKatsayi[b % 10];
        final h = 6 + b + 3 * a ~/ 2;
        final q = h - p * x, s = h - r * x;
        return sayisal(
          'ABCD paralelkenarının köşegenleri E noktasında kesişiyor. |AE| = '
              '(${_dx(p, q)}) cm ve |EC| = (${_dx(r, s)}) cm olduğuna göre |AC| '
              'kaç cm olur?',
          2 * h,
          [h, x, 4 * h],
          'Paralelkenarın köşegenleri birbirini ortalar: ${_dx(p, q)} = '
              '${_dx(r, s)}, x = $x. |AE| = |EC| = $h cm olduğundan |AC| = '
              '${2 * h} cm.',
          unit: 'cm',
          positive: true,
        );
      }
      if (c == 8) {
        final p = 4 + a, q = p + 1 + b % 10;
        final e = b < 10 ? q - p + 1 : p + q - 1;
        final f2 = 2 * p * p + 2 * q * q - e * e;
        final alt = (p + q) * (p + q) - e * e;
        return secenekli(
          'ABCD paralelkenarında |AB| = $q cm, |BC| = $p cm ve [AC] '
              'köşegeninin uzunluğu $e cm olduğuna göre [BD] köşegeninin '
              'uzunluğu kaç cm olur?',
          '${_kok(1, f2)} cm',
          [
            '$e cm',
            '${_kok(1, p * p + q * q)} cm',
            '${_kok(1, alt)} cm',
            '${_kok(2, f2)} cm',
          ],
          'Paralelkenarda köşegen uzunluklarının kareleri toplamı, kenar '
              'uzunluklarının kareleri toplamının iki katıdır: $e² + |BD|² = '
              '2·($q² + $p²) = ${2 * (p * p + q * q)}. Buradan |BD|² = $f2 ve '
              '|BD| = ${_kok(1, f2)} cm.',
        );
      }
      final ic = b >= 10, q = 1 + b % 10, p = (ic ? 11 : 5) + a;
      final dc = ic ? 2 * p - q : 2 * p + q, cevre = 2 * (p + dc);
      final sira = ic ? 'D, F, E, C' : 'D, E, F, C';
      return sayisal(
        'ABCD paralelkenarında A ve B açılarının açıortayları [DC] kenarını '
            'sırasıyla E ve F noktalarında kesiyor; bu noktalar [DC] üzerinde '
            '$sira sırasıyla dizilidir. |AD| = $p cm ve |EF| = $q cm olduğuna '
            'göre ABCD paralelkenarının çevresi kaç cm olur?',
        cevre,
        [2 * (p + (ic ? 2 * p + q : 2 * p - q)), 2 * (p + p + q), 6 * p],
        'Açıortaylar ADE ve BCF ikizkenar üçgenlerini oluşturur: |DE| = |AD| '
            '= $p cm ve |CF| = |BC| = $p cm. ${ic ? '|DC| = |DE| + |CF| − |EF| = '
                      '$p + $p − $q' : '|DC| = |DE| + |EF| + |FC| = $p + $q + $p'} = '
            '$dc cm. Çevre 2·($p + $dc) = $cevre cm.',
        unit: 'cm',
        positive: true,
      );
    },
    exam: ExamKind.tyt,
    lesson: _tm,
    shortAnswer: false,
  ),
  // 8 · Yamuk: orta taban, ikizkenar yamuk ve dik yamuk.
  lmAile(
    'gm_yamuk',
    'Yamukta orta taban, ikizkenar ve dik yamuk',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      if (c <= 2) {
        final q = 4 + a;
        var p = q + 2 + b;
        // |KL| = |DC| çakışması (|AB| = 3·|DC|) kaydırılır.
        if (c == 2 && p == 3 * q) p += 20;
        const giris = 'ABCD yamuğunda [AB] ∥ [DC] olup';
        const orta =
            '[AD] ve [BC] kenarlarının orta noktalarını birleştiren orta taban';
        if (c == 0) {
          return ondalikli(
            '$giris |AB| = $p cm ve |DC| = $q cm olarak veriliyor. $orta kaç '
                'cm olur?',
            (p + q) / 2,
            [(p + q).toDouble(), (p - q) / 2, (p - q).toDouble()],
            'Orta tabanın uzunluğu, tabanların uzunlukları toplamının '
                'yarısıdır: ($p + $q) / 2 = ${tr((p + q) / 2)} cm.',
            unit: 'cm',
            positive: true,
          );
        }
        if (c == 1) {
          final m2 = p + q;
          return ondalikli(
            '$giris |DC| = $q cm ve $orta ${tr(m2 / 2)} cm olarak veriliyor. '
                'Buna göre |AB| kaç cm olur?',
            p.toDouble(),
            [m2 / 2 + q, m2 / 2 - q, m2 / 2 + q / 2],
            'Orta taban (|AB| + |DC|) / 2 olduğundan |AB| = 2·${tr(m2 / 2)} − '
                '$q = $p cm.',
            unit: 'cm',
            positive: true,
          );
        }
        return ondalikli(
          '$giris |AB| = $p cm ve |DC| = $q cm olarak veriliyor. $orta, [AC] '
              've [BD] köşegenlerini sırasıyla K ve L noktalarında kesiyor. Buna '
              'göre |KL| kaç cm olur?',
          (p - q) / 2,
          [(p + q) / 2, (p - q).toDouble(), q / 2],
          'Orta taban ABC üçgeninde |AB| / 2, ADC üçgeninde |DC| / 2 '
              'uzunluğunda parçalar ayırır: |KL| = ($p − $q) / 2 = '
              '${tr((p - q) / 2)} cm.',
          unit: 'cm',
          positive: true,
        );
      }
      final (l1, l2, w) = _yonluUclu(a);
      if (c == 5) {
        // Köşegen: (|AB| + |DC|) / 2, yükseklik ve köşegen bir Pisagor üçlüsü.
        final k = 1 + 20 ~/ l1, dd = k * l1, h = k * l2, kg = k * w;
        final q = 1 + b, p = 2 * dd - q;
        return sayisal(
          'ABCD ikizkenar yamuğunda [AB] ∥ [DC], |AB| = $p cm, |DC| = $q cm '
              've yamuğun yüksekliği $h cm olarak veriliyor. Buna göre [AC] '
              'köşegeninin uzunluğu kaç cm olur?',
          kg,
          [dd + h, dd, h],
          'C köşesinden [AB] tabanına inen dikmenin ayağı H olsun. |AH| = '
              '($p + $q) / 2 = $dd cm olur. AHC dik üçgeninde |AC| = √($dd² + '
              '$h²) = $kg cm.',
          unit: 'cm',
          positive: true,
        );
      }
      var q = 2 + b;
      // Sorulan uzunluk kökte yazılı bir tabana eşit çıkarsa küçük taban
      // 20 cm uzatılır (kaydırılan değerler başka vakada kullanılmaz).
      final sorulanUz = switch (c) {
        3 || 7 => l2,
        4 || 6 => w,
        _ => -1,
      };
      if ({q, c <= 4 ? q + 2 * l1 : q + l1}.contains(sorulanUz)) q += 20;
      if (c <= 4 || c == 9) {
        // İkizkenar yamuk: her uçtaki parça d, yükseklik h, yan kenar w.
        final d = l1, h = l2, p = q + 2 * d;
        const giris = 'ABCD ikizkenar yamuğunda [AB] ∥ [DC] ve |AD| = |BC|';
        final ayir =
            'D ve C köşelerinden [AB] tabanına inen dikmeler, tabanın iki '
            'ucunda ($p − $q) / 2 = $d cm uzunluğunda parçalar ayırır.';
        return switch (c) {
          3 => sayisal(
            '$giris olup |AB| = $p cm, |DC| = $q cm ve |AD| = $w cm olarak '
                'veriliyor. Buna göre yamuğun yüksekliği kaç cm olur?',
            h,
            [w - d, 2 * d, d],
            '$ayir Yükseklik √($w² − $d²) = $h cm.',
            unit: 'cm',
            positive: true,
          ),
          4 => sayisal(
            '$giris olup |AB| = $p cm, |DC| = $q cm ve yamuğun yüksekliği $h '
                'cm olarak veriliyor. Buna göre |AD| kaç cm olur?',
            w,
            [h + d, h + 2 * d, 2 * d],
            '$ayir |AD| = √($h² + $d²) = $w cm.',
            unit: 'cm',
            positive: true,
          ),
          _ => sayisal(
            '$giris olup |DC| = $q cm, |AD| = $w cm ve yamuğun yüksekliği $h '
                'cm olarak veriliyor. Buna göre yamuğun çevresi kaç cm olur?',
            p + q + 2 * w,
            [2 * q + 2 * w + d, 2 * q + 2 * w, 2 * q + 2 * w + 4 * d],
            'D ve C köşelerinden [AB] tabanına inen dikmelerin tabanın '
                'uçlarında ayırdığı parçalar √($w² − $h²) = $d cm olur. |AB| = '
                '$q + 2·$d = $p cm, çevre $p + $q + 2·$w = ${p + q + 2 * w} cm.',
            unit: 'cm',
            positive: true,
          ),
        };
      }
      // Dik yamuk: |AB| − |DC| = l1, |AD| = l2, |BC| = w.
      final p = q + l1;
      const giris =
          'ABCD dik yamuğunda [AB] ∥ [DC] olup [AD] kenarı iki tabana da '
          'diktir.';
      final dikme =
          'C köşesinden [AB] tabanına inen dikmenin ayağı H olsun; AHCD bir '
          'dikdörtgen olduğundan |HB| = $p − $q = $l1 cm olur.';
      return switch (c) {
        6 => sayisal(
          '$giris |AB| = $p cm, |DC| = $q cm ve |AD| = $l2 cm olduğuna göre '
              '|BC| kaç cm olur?',
          w,
          [l1 + l2, l2, p],
          '$dikme CHB dik üçgeninde |BC| = √($l2² + $l1²) = $w cm.',
          unit: 'cm',
          positive: true,
        ),
        7 => sayisal(
          '$giris |AB| = $p cm, |DC| = $q cm ve |BC| = $w cm olduğuna göre '
              '|AD| kaç cm olur?',
          l2,
          [w - l1, l1, w],
          '$dikme CHB dik üçgeninde |CH| = √($w² − $l1²) = $l2 cm ve |AD| = '
              '|CH| = $l2 cm.',
          unit: 'cm',
          positive: true,
        ),
        _ => sayisal(
          '$giris |AB| = $p cm, |DC| = $q cm ve |AD| = $l2 cm olduğuna göre '
              'yamuğun çevresi kaç cm olur?',
          p + q + l2 + w,
          [p + q + 2 * l2, p + q + l2 + l1 + l2, p + q + l2],
          '$dikme |BC| = √($l2² + $l1²) = $w cm. Çevre $p + $q + $l2 + $w = '
              '${p + q + l2 + w} cm.',
          unit: 'cm',
          positive: true,
        ),
      };
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 9 · Üçgende alan oranları.
  lmAile(
    'gm_alan_oran',
    'Üçgende alan oranları: ortak yükseklik ve kenarortay',
    _mat,
    Difficulty.medium,
    BloomLevel.analiz,
    (a, b, c) {
      final (m, n) = _orantilar[a];
      // Alan birimi 10 cm² ve üstü: alanlar kökteki uzunluklarla karışmaz.
      final u = 10 + b;
      const ortak =
          'Bu üçgenlerin A köşesinden [BC] doğrusuna inen yükseklikleri '
          'ortaktır; alanları tabanlarıyla orantılıdır.';
      switch (c) {
        case 0:
          return sayisal(
            'ABC üçgeninde D noktası [BC] kenarı üzerindedir. |BD| = $m cm, '
                '|DC| = $n cm ve ABD üçgeninin alanı ${m * u} cm² olduğuna göre '
                'ADC üçgeninin alanı kaç cm² olur?',
            n * u,
            [(m + n) * u, ?_bol(m * m * u, n), m * u + n],
            '$ortak A(ADC) = ${m * u}·$n / $m = ${n * u} cm².',
            unit: 'cm²',
            positive: true,
          );
        case 1:
          return sayisal(
            'ABC üçgeninde D noktası [BC] kenarı üzerindedir. |BD| = $m cm, '
                '|DC| = $n cm ve ADC üçgeninin alanı ${n * u} cm² olduğuna göre '
                'ABC üçgeninin alanı kaç cm² olur?',
            (m + n) * u,
            [m * u, n * u + m, ?_bol(n * (m + n) * u, m)],
            '$ortak A(ABD) = ${n * u}·$m / $n = ${m * u} cm², A(ABC) = '
                '${m * u} + ${n * u} = ${(m + n) * u} cm².',
            unit: 'cm²',
            positive: true,
          );
        case 2 || 3:
          final s = 2 * (m + n) * u;
          final veri =
              'ABC üçgeninde [AD] kenarortaydır. E noktası [AD] üzerinde olup '
              '|AE| = $m cm, |ED| = $n cm ve ABC üçgeninin alanı $s cm² '
              'olarak veriliyor.';
          final cozum =
              'Kenarortay alanı ikiye böler: A(ABD) = $s / 2 = ${s ~/ 2} cm². '
              'ABE ve EBD üçgenlerinin B köşesinden [AD] doğrusuna inen '
              'yükseklikleri ortaktır: A(EBD) = ${s ~/ 2}·$n / ${m + n} = '
              '${n * u} cm².';
          if (c == 2) {
            return sayisal(
              '$veri Buna göre EBD üçgeninin alanı kaç cm² olur?',
              n * u,
              [2 * n * u, m * u, (m + n) * u],
              cozum,
              unit: 'cm²',
              positive: true,
            );
          }
          return sayisal(
            '$veri Buna göre EBC üçgeninin alanı kaç cm² olur?',
            2 * n * u,
            [n * u, 2 * m * u, (m + n) * u],
            '$cozum Aynı biçimde A(ECD) = ${n * u} cm² olduğundan A(EBC) = '
                '${2 * n * u} cm².',
            unit: 'cm²',
            positive: true,
          );
        case 4 || 5:
          final (p, q) = _orantilar[b];
          final s = 10 * (m + n) * (p + q), ade = 10 * m * p;
          final veri =
              'ABC üçgeninde D noktası [AB], E noktası [AC] kenarı üzerindedir. '
              '|AD| = $m cm, |DB| = $n cm, |AE| = $p cm, |EC| = $q cm ve ABC '
              'üçgeninin alanı $s cm² olarak veriliyor.';
          final cozum =
              'ADE ve ABC üçgenlerinde A açısı ortaktır; alanları oranı '
              '(|AD|·|AE|) / (|AB|·|AC|) = ($m·$p) / (${m + n}·${p + q}) olur. '
              'A(ADE) = $s·${m * p} / ${(m + n) * (p + q)} = $ade cm².';
          if (c == 4) {
            return sayisal(
              '$veri Buna göre ADE üçgeninin alanı kaç cm² olur?',
              ade,
              [10 * m * (p + q), 10 * p * (m + n), ?_bol(s * m * p, n * q)],
              cozum,
              unit: 'cm²',
              positive: true,
            );
          }
          return sayisal(
            '$veri Buna göre DBCE dörtgeninin alanı kaç cm² olur?',
            s - ade,
            [ade, s - 10 * m * (p + q), s - 10 * n * q],
            '$cozum A(DBCE) = $s − $ade = ${s - ade} cm².',
            unit: 'cm²',
            positive: true,
          );
        case 6:
          final s = 3 * (m + n) * u;
          return sayisal(
            'ABC üçgeninin ağırlık merkezi G noktasıdır. E noktası [BC] kenarı '
                'üzerinde olup |BE| = $m cm, |EC| = $n cm ve ABC üçgeninin alanı '
                '$s cm² olarak veriliyor. Buna göre GBE üçgeninin alanı kaç cm² '
                'olur?',
            m * u,
            [3 * m * u, ?_bol(m * u, 2), (m + n) * u],
            'Ağırlık merkezi ile bir kenarın oluşturduğu üçgenin alanı tüm '
                'alanın üçte biridir: A(GBC) = $s / 3 = ${(m + n) * u} cm². GBE ve '
                'GEC üçgenlerinin G köşesinden inen yükseklikleri ortaktır: '
                'A(GBE) = ${(m + n) * u}·$m / ${m + n} = ${m * u} cm².',
            unit: 'cm²',
            positive: true,
          );
        case 7:
          return sayisal(
            'ABC üçgeninin ağırlık merkezi G noktasıdır. E noktası [AB] kenarı '
                'üzerinde olup |AE| = $m cm, |EB| = $n cm ve AGE üçgeninin alanı '
                '${m * u} cm² olarak veriliyor. Buna göre ABC üçgeninin alanı kaç '
                'cm² olur?',
            3 * (m + n) * u,
            [(m + n) * u, 6 * (m + n) * u, 3 * m * u],
            'AGE ve EGB üçgenlerinin G köşesinden inen yükseklikleri ortaktır: '
                'A(AGB) = ${m * u}·${m + n} / $m = ${(m + n) * u} cm². Ağırlık '
                'merkezi ile bir kenarın oluşturduğu üçgen tüm alanın üçte biri '
                'olduğundan A(ABC) = 3·${(m + n) * u} = ${3 * (m + n) * u} cm².',
            unit: 'cm²',
            positive: true,
          );
        case 8:
          final x = 1 + a % 5, z = 1 + a ~/ 5, y = 1 + b % 10;
          final v = 10 + 5 * (b ~/ 10);
          return sayisal(
            'ABC üçgeninin [BC] kenarı üzerinde B, D, E, C sırasıyla dizilen D '
                've E noktaları alınıyor. |BD| = $x cm, |DE| = $y cm, |EC| = $z cm '
                've ADE üçgeninin alanı ${y * v} cm² olduğuna göre ABC üçgeninin '
                'alanı kaç cm² olur?',
            (x + y + z) * v,
            [(x + z) * v, 3 * y * v, (x + y + z) * y],
            '$ortak Taban 1 cm başına ${y * v} / $y = $v cm² alan düşer. '
                'A(ABC) = ($x + $y + $z)·$v = ${(x + y + z) * v} cm².',
            unit: 'cm²',
            positive: true,
          );
        default:
          return sayisal(
            'ABC üçgeninde D noktası [BC] kenarı üzerinde olup |BD| = $m cm ve '
                '|DC| = $n cm olarak veriliyor. [AD] doğru parçasının orta noktası '
                'E ve ABD üçgeninin alanı ${2 * m * u} cm² olduğuna göre EDC '
                'üçgeninin alanı kaç cm² olur?',
            n * u,
            [2 * n * u, m * u, (m + n) * u],
            '$ortak A(ADC) = ${2 * m * u}·$n / $m = ${2 * n * u} cm². ADC '
                'üçgeninde [CE] kenarortay olduğundan A(EDC) = ${2 * n * u} / 2 = '
                '${n * u} cm².',
            unit: 'cm²',
            positive: true,
          );
      }
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 10 · Çemberde teğet; iki çemberin konumu ve ortak teğetler.
  lmAile(
    'gm_cember_teget',
    'Çemberde teğet, iki çemberin konumu ve ortak teğet',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      if (c == 0) {
        final x = 3 + a;
        final (p, r) = _kesenKatsayi[b % 10];
        var l = 8 + b + a ~/ 3;
        final yr = 3 + (a + 2 * b) % 9;
        // Teğet uzunluğu kökteki bir katsayıya eşit çıkmasın.
                if ({(l - p * x).abs(), (l - r * x).abs(), p, r, x}.contains(l)) {
          l += 30;
        }
        final q = l - p * x, s = l - r * x;
        final veri =
            'O merkezli çembere dışındaki P noktasından çizilen iki teğet '
            'çembere A ve B noktalarında değiyor. |PA| = (${_dx(p, q)}) cm ve '
            '|PB| = (${_dx(r, s)}) cm olarak veriliyor.';
        final cozum =
            'Dış noktadan çizilen teğet parçalarının uzunlukları eşittir: '
            '${_dx(p, q)} = ${_dx(r, s)}, x = $x ve |PA| = |PB| = $l cm.';
        final xHata = _bol(q + s, (p - r).abs());
        if ((a + b).isEven) {
          return sayisal(
            '$veri Buna göre |PA| kaç cm olur?',
            l,
            [x, 2 * l, if (xHata != null) p * xHata + q],
            cozum,
            unit: 'cm',
            positive: true,
          );
        }
        return sayisal(
          '$veri Çemberin yarıçapı $yr cm olduğuna göre PAOB dörtgeninin '
              'çevresi kaç cm olur?',
          2 * l + 2 * yr,
          [l + 2 * yr, 2 * l + yr, 2 * l],
          '$cozum |OA| = |OB| = $yr cm olduğundan çevre 2·$l + 2·$yr = '
              '${2 * l + 2 * yr} cm.',
          unit: 'cm',
          positive: true,
        );
      }
      if (c <= 2) {
        final ta = 2 + 2 * a, tb = 3 + 2 * b, tc = 2 + 2 * ((a + 2 * b) % 8);
        final ab = ta + tb, bc = tb + tc, ac = ta + tc, s = ta + tb + tc;
        const giris =
            'ABC üçgeninin iç teğet çemberi [AB], [BC] ve [AC] kenarlarına '
            'sırasıyla D, E ve F noktalarında değiyor.';
        const kural =
            'Bir köşeden çembere çizilen teğet parçaları eşittir: |AD| = '
            '|AF|, |BD| = |BE| ve |CE| = |CF|.';
        if (c == 1) {
          return sayisal(
            '$giris |AB| = $ab cm, |BC| = $bc cm ve |AC| = $ac cm olduğuna '
                'göre |BD| kaç cm olur?',
            tb,
            [ta, tc],
            '$kural Yarı çevre ($ab + $bc + $ac) / 2 = $s cm olduğundan |BD| = '
                '$s − |AC| = $s − $ac = $tb cm.',
            unit: 'cm',
            positive: true,
          );
        }
        return sayisal(
          '$giris ABC üçgeninin çevresi ${2 * s} cm ve |BC| = $bc cm olduğuna '
              'göre |AD| kaç cm olur?',
          ta,
          [2 * s - bc, s, ?_bol(bc, 2)],
          '$kural |BD| + |CF| = |BE| + |CE| = |BC| olduğundan çevre 2·|AD| + '
              '2·|BC| olur. 2·|AD| = ${2 * s} − 2·$bc = ${2 * ta}, |AD| = $ta cm.',
          unit: 'cm',
          positive: true,
        );
      }
      if (c <= 4) {
        final r1 = 2 + a, r2 = r1 + 2 + b;
        final tur = (c == 3 ? a + b : a + 2 * b) % 5;
        final d = _konumUzaklik(tur, r1, r2, a + b);
        final veri =
            'Yarıçapları $r1 cm ve $r2 cm olan iki çemberin merkezleri '
            'arasındaki uzaklık $d cm olarak veriliyor.';
        final gerekce =
            'r₁ + r₂ = ${r1 + r2} ve r₂ − r₁ = ${r2 - r1} olur; '
            '${_konumGerekce[tur]}.';
        if (c == 3) {
          return secenekli(
            '$veri Buna göre bu iki çemberin birbirine göre durumu '
            'hangisidir?',
            _konumlar[tur],
            [for (var k = 1; k < 5; k++) _konumlar[(tur + k) % 5]],
            gerekce,
          );
        }
        final ortak = _ortakTeget[tur];
        return sayisal(
          '$veri Buna göre bu iki çemberin kaç ortak teğeti vardır?',
          ortak,
          [
            for (var k = 0; k <= 4; k++)
              if (k != ortak) k,
          ],
          '$gerekce Bu durumda ortak teğet sayısı $ortak olur.',
        );
      }
      if (c == 5) {
        final r1 = 2 + a;
        var r2 = r1 + 1 + b;
        // Yanıt 2r₁ − 1 büyük yarıçapa eşit çıkmasın.
        if (r2 == 2 * r1 - 1) r2 += 20;
        return sayisal(
          'Yarıçapları $r1 cm ve $r2 cm olan iki çember iki farklı noktada '
              'kesişiyor. Merkezler arasındaki uzaklık cm cinsinden bir tam sayı '
              'olduğuna göre bu uzaklık kaç farklı değer alabilir?',
          2 * r1 - 1,
          [2 * r1 + 1, 2 * r1, r1 + r2 - 1],
          'Kesişen çemberlerde r₂ − r₁ < d < r₁ + r₂, yani ${r2 - r1} < d < '
              '${r1 + r2} olur. Uygun tam sayılar en küçüğü ${r2 - r1 + 1}, en '
              'büyüğü ${r1 + r2 - 1} olmak üzere ${2 * r1 - 1} tanedir.',
          positive: true,
        );
      }
      if (c == 6) {
        final r1 = 2 + a;
        var r2 = r1 + 2 + b;
        // İç içe durumda yanıt r₂ − r₁ − 1 küçük yarıçapa eşit çıkmasın.
        if (r2 == 2 * r1 + 1) r2 += 20;
        if ((a + b).isEven) {
          return sayisal(
            'Yarıçapları $r1 cm ve $r2 cm olan iki çemberin dört ortak teğeti '
                'vardır. Merkezler arasındaki uzaklık cm cinsinden bir tam sayı '
                'olduğuna göre bu uzaklık en az kaç cm olabilir?',
            r1 + r2 + 1,
            [r1 + r2, r2 - r1 + 1, r1 + r2 - 1],
            'Dört ortak teğet yalnız çemberler birbirinin dışında ve ayrık '
                'olduğunda vardır: d > r₁ + r₂ = ${r1 + r2}. En küçük tam sayı '
                'değeri ${r1 + r2 + 1} cm olur.',
            unit: 'cm',
            positive: true,
          );
        }
        return sayisal(
          'Yarıçapları $r1 cm ve $r2 cm olan iki çemberin hiç ortak noktası '
              'yoktur ve küçük çember büyük çemberin içindedir. Merkezler '
              'arasındaki uzaklık cm cinsinden pozitif bir tam sayı olduğuna göre '
              'bu uzaklık en çok kaç cm olabilir?',
          r2 - r1 - 1,
          [r2 - r1, r1 + r2 - 1, r2 - r1 + 1],
          'Küçük çember büyüğün içinde ve ortak nokta yoksa d < r₂ − r₁ = '
              '${r2 - r1} olur. En büyük tam sayı değeri ${r2 - r1 - 1} cm.',
          unit: 'cm',
          positive: true,
        );
      }
      final (l1, l2, w) = _yonluUclu(a);
      if (c == 7) {
        var r1 = 2 + b;
        if (l2 == r1 || l2 == r1 + l1) r1 += 20;
        final r2 = r1 + l1;
        return sayisal(
          'Yarıçapları $r1 cm ve $r2 cm olan iki çemberin merkezleri '
              'arasındaki uzaklık $w cm olarak veriliyor. Bu çemberlere çizilen '
              'bir ortak dış teğetin, değme noktaları arasında kalan parçasının '
              'uzunluğu kaç cm olur?',
          l2,
          [w - l1, ?_tamKok(w * w - (r1 + r2) * (r1 + r2)), w],
          'Küçük çemberin merkezinden ortak teğete paralel çizilirse dik '
              'kenarlarından biri r₂ − r₁ = ${r2 - r1} cm, hipotenüsü $w cm olan '
              'bir dik üçgen oluşur. Ortak dış teğet parçası √($w² − ${r2 - r1}²) '
              '= $l2 cm.',
          unit: 'cm',
          positive: true,
        );
      }
      if (c == 8) {
        final k = 1 + 40 ~/ l1, top = k * l1, uz = k * l2, d = k * w;
        var r1 = 1 + b;
        if (uz == r1 || uz == top - r1) r1 += 20;
        final r2 = top - r1;
        return sayisal(
          'Yarıçapları $r1 cm ve $r2 cm olan iki çemberin merkezleri '
              'arasındaki uzaklık $d cm olarak veriliyor. Bu çemberlere çizilen '
              'bir ortak iç teğetin, değme noktaları arasında kalan parçasının '
              'uzunluğu kaç cm olur?',
          uz,
          [d - top, d, top],
          'Merkezlerden birinden ortak iç teğete paralel çizilirse dik '
              'kenarlarından biri r₁ + r₂ = $top cm, hipotenüsü $d cm olan bir '
              'dik üçgen oluşur. Ortak iç teğet parçası √($d² − $top²) = $uz cm.',
          unit: 'cm',
          positive: true,
        );
      }
      final r1 = 1 + a;
      var r2 = r1 + 1 + b;
      // r₂ = 4r₁ olursa 2√(r₁r₂) büyük yarıçapa eşit çıkar.
      if (r2 == 4 * r1) r2 += 20;
      final pr = r1 * r2;
      return secenekli(
        'Yarıçapları $r1 cm ve $r2 cm olan iki çember dıştan teğettir. Bu '
            'çemberlere çizilen bir ortak dış teğetin, değme noktaları arasında '
            'kalan parçasının uzunluğu kaç cm olur?',
        '${_kok(2, pr)} cm',
        [
          '${_kok(1, pr)} cm',
          '${r1 + r2} cm',
          '${_kok(2, r1 + r2)} cm',
          '${_kok(4, pr)} cm',
        ],
        'Merkezler arası uzaklık ${r1 + r2} cm olur. Küçük çemberin '
            'merkezinden ortak teğete paralel çizilen doğru ile dik kenarı '
            '${r2 - r1} cm, hipotenüsü ${r1 + r2} cm olan dik üçgen oluşur: '
            '√(${r1 + r2}² − ${r2 - r1}²) = √${4 * pr} = ${_kok(2, pr)} cm.',
      );
    },
    exam: ExamKind.tyt,
    lesson: _tm,
    shortAnswer: false,
  ),
  // 11 · Daire halkası; dairenin içine ve dışına çizilen kareler.
  lmAile(
    'gm_daire_halka',
    'Daire halkası ve daireye içten ve dıştan çizilen kare',
    _mat,
    Difficulty.easy,
    BloomLevel.uygulama,
    (a, b, c) {
      final i = a + 25 * b;
      const esMerkez = 'Merkezleri aynı olan ve yarıçapları';
      switch (c) {
        case 0:
          final r = 1 + a, R = r + 1 + b, fark = R * R - r * r;
          return sayisal(
            '$esMerkez $r cm ve $R cm olan iki çember arasında kalan daire '
                'halkasının alanı kaç π cm² olur?',
            fark,
            [(R - r) * (R - r), R * R + r * r, 2 * (R - r)],
            'Halkanın alanı büyük dairenin alanından küçük dairenin alanı '
                'çıkarılarak bulunur: π·$R² − π·$r² = π·(${R * R} − ${r * r}) = '
                '$farkπ cm².',
            positive: true,
          );
        case 1:
          final r = 1 + a, R = r + 1 + b, fark = R * R - r * r;
          return sayisal(
            '$esMerkez farklı olan iki çemberden büyüğünün yarıçapı $R cm, iki '
                'çember arasında kalan daire halkasının alanı $farkπ cm² olduğuna '
                'göre küçük çemberin yarıçapı kaç cm olur?',
            r,
            [r * r, ?_tamKok(R * R + fark), R - r],
            'π·$R² − π·r² = $farkπ eşitliğinden r² = ${R * R} − $fark = '
                '${r * r}, r = $r cm bulunur.',
            unit: 'cm',
            positive: true,
          );
        case 2:
          final aci = _halkaAci[b % 10], adim = _halkaAdim(aci);
          final r = 1 + a;
          var R = r + adim * (1 + b ~/ 10);
          // Dilim alanı kökteki açıya ya da bir yarıçapa eşit çıkarsa yarıçap
          // farkı üç adım alınır (bu fark başka vakada kullanılmaz).
          int dilim(int rr) => (rr * rr - r * r) * aci ~/ 360;
          if ({aci, r, R}.contains(dilim(R))) R = r + 3 * adim;
          final fark = R * R - r * r, alan = fark * aci ~/ 360;
          return sayisal(
            '$esMerkez $r cm ve $R cm olan iki çember veriliyor. Ortak merkezden '
                'çıkan ve aralarındaki açının ölçüsü $aci° olan iki ışın, iki çember '
                'arasındaki halkadan bir halka dilimi ayırıyor. Bu halka diliminin '
                'alanı kaç π cm² olur?',
            alan,
            [
              fark,
              ?_bol(R * R * aci, 360),
              ?_bol((R - r) * (R - r) * aci, 360),
            ],
            'Halkanın alanı π·($R² − $r²) = $farkπ cm² olur. Halka dilimi bunun '
                '$aci / 360 = ${kesir(aci, 360)} kadarıdır: $fark·${kesir(aci, 360)} '
                '= $alanπ cm².',
            positive: true,
          );
        case 3:
          final q = 2 * (1 + i);
          return sayisal(
            'Alanı $q cm² olan bir karenin köşelerinden geçen çemberin '
                'sınırladığı dairenin alanı kaç π cm² olur?',
            q ~/ 2,
            [?_bol(q, 4), q, 2 * q],
            'Karenin kenarı a ise köşegeni a√2 olur ve bu köşegen çemberin '
                'çapıdır: r² = (a√2 / 2)² = a² / 2. a² = $q olduğundan dairenin '
                'alanı π·$q / 2 = ${q ~/ 2}π cm².',
            positive: true,
          );
        case 4:
          final q = 4 * (1 + i);
          return sayisal(
            'Alanı $q cm² olan bir karenin kenarlarına içten teğet olan '
                'çemberin sınırladığı dairenin alanı kaç π cm² olur?',
            q ~/ 4,
            [q ~/ 2, q, ?_bol(q, 8)],
            'Çemberin çapı karenin bir kenarına eşittir: r = a / 2, r² = a² / 4. '
                'a² = $q olduğundan dairenin alanı π·$q / 4 = ${q ~/ 4}π cm².',
            positive: true,
          );
        case 5:
          final s = 1 + i;
          return sayisal(
            'Alanı $sπ cm² olan bir dairenin içine, köşeleri çember üzerinde '
                'olan bir kare çiziliyor. Bu karenin alanı kaç cm² olur?',
            2 * s,
            [4 * s, s, if (s.isEven) s ~/ 2],
            'Dairenin yarıçapı r olsun; r² = $s olur. Karenin köşegeni çapa '
                'eşittir: 2r. Köşegeni 2r olan karenin alanı (2r)² / 2 = 2r² = '
                '${2 * s} cm².',
            unit: 'cm²',
            positive: true,
          );
        case 6:
          final s = 1 + i;
          return sayisal(
            'Alanı $sπ cm² olan bir dairenin dışına, kenarları çembere teğet '
                'olan bir kare çiziliyor. Bu karenin alanı kaç cm² olur?',
            4 * s,
            [2 * s, s, 8 * s],
            'Dairenin yarıçapı r olsun; r² = $s olur. Karenin bir kenarı çapa '
                'eşittir: 2r. Karenin alanı (2r)² = 4r² = ${4 * s} cm².',
            unit: 'cm²',
            positive: true,
          );
        case 7:
          final r = 1 + a, R = _karekokIkiUstu(r) + b;
          final alan = 2 * R * R - 4 * r * r;
          return sayisal(
            '$esMerkez $r cm ve $R cm olan iki çember veriliyor. Büyük çemberin '
                'içine köşeleri çember üzerinde olan bir kare, küçük çemberin '
                'dışına da kenarları çembere teğet ve ilk karenin kenarlarına '
                'paralel olan bir kare çiziliyor. İki kare arasında kalan bölgenin '
                'alanı kaç cm² olur?',
            alan,
            [2 * R * R - 2 * r * r, 4 * R * R - 4 * r * r, R * R - r * r],
            'Büyük karenin köşegeni ${2 * R} cm olduğundan alanı (${2 * R})² / 2 '
                '= ${2 * R * R} cm², küçük karenin kenarı ${2 * r} cm olduğundan '
                'alanı ${4 * r * r} cm² olur. Aradaki bölge ${2 * R * R} − '
                '${4 * r * r} = $alan cm².',
            unit: 'cm²',
            positive: true,
          );
        case 8:
          final s = 1 + i;
          return sayisal(
            'Bir karenin kenarlarına içten teğet olan çemberin sınırladığı '
                'dairenin alanı $sπ cm² olduğuna göre aynı karenin köşelerinden '
                'geçen çemberin sınırladığı dairenin alanı kaç π cm² olur?',
            2 * s,
            [4 * s, if (s.isEven) s ~/ 2, 3 * s],
            'İç çemberin yarıçapı r ise karenin kenarı 2r, köşegeni 2r√2 olur. '
                'Dış çemberin yarıçapı r√2, karesi 2r² olduğundan alan 2·$sπ = '
                '${2 * s}π cm².',
            positive: true,
          );
        default:
          final r = 1 + a, R = r + 1 + b, fark = R * R - r * r;
          return kesirli(
            '$esMerkez $r cm ve $R cm olan iki çember arasında kalan daire '
                'halkasının alanı, küçük dairenin alanının kaç katıdır?',
            fark,
            r * r,
            [((R - r) * (R - r), r * r), (fark, R * R), (R * R, r * r)],
            'Halkanın alanı π·(${R * R} − ${r * r}) = $farkπ, küçük dairenin '
                'alanı ${r * r}π olur. Oran $fark / ${r * r}'
                '${kesir(fark, r * r) == '$fark/${r * r}' ? '' : ' = ${kesir(fark, r * r)}'}.',
          );
      }
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 12 · Düzgün altıgen ve düzgün sekizgen.
  lmAile(
    'gm_duzgun_cokgen',
    'Düzgün altıgen ve sekizgende kenar, köşegen ve alan',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final i = a + 25 * b;
      const altigenAlan =
          'Kenarı a olan düzgün altıgen, kenarı a olan altı eşkenar üçgenden '
          'oluşur; alanı 6·(a²√3 / 4) = (3a² / 2)√3 olur.';
      if (c == 0 || c == 8) {
        final (x, y) = _altigenCerceve[i + (c == 8 ? 500 : 0)];
        final k = 3 * (x * x - y * y) ~/ 2;
        return sayisal(
          'Bir kenarı $x cm olan düzgün altıgen biçimindeki bir levhanın '
              'ortasından, kenarı $y cm olan ve kenarları levhanın kenarlarına '
              'paralel düzgün altıgen biçiminde bir parça çıkarılıyor. Kalan '
              'çerçevenin alanı k√3 cm² olduğuna göre k kaçtır?',
          k,
          [
            3 * (x * x - y * y),
            ?_bol(3 * (x - y) * (x - y), 2),
            ?_bol(3 * (x * x - y * y), 4),
          ],
          '$altigenAlan Çerçeve alanı (3·$x² / 2)√3 − (3·$y² / 2)√3 = '
              '(3·${x * x - y * y} / 2)√3 = $k√3 cm², k = $k.',
          positive: true,
        );
      }
      if (c == 1) {
        final n = 2 + a;
        var t = 5 + b;
        if (6 * n * n == n * t || 6 * n * n == t) t += 20;
        final kenar = n * t;
        return sayisal(
          'Bir kenarı $kenar cm olan düzgün altıgen biçimindeki bir salonun '
              'zemini, bir kenarı $t cm olan eşkenar üçgen biçimindeki karolarla '
              'boşluk kalmadan ve karolar üst üste gelmeden kaplanıyor. Bu iş için '
              'kaç karo gerekir?',
          6 * n * n,
          [6 * n, n * n, 3 * n * n],
          'Düzgün altıgen, kenarı $kenar cm olan altı eşkenar üçgenden oluşur. '
              'Kenarı $kenar cm olan eşkenar üçgenin kenarı karonun kenarının $n '
              'katı olduğundan bu üçgen $n² = ${n * n} karoya ayrılır. Toplam '
              '6·${n * n} = ${6 * n * n} karo.',
          positive: true,
        );
      }
      if (c == 2) {
        final x = 2 + a;
        var y = 3 + b;
        // Oran tam sayı olup kökteki bir kenara eşitse üçgenin kenarı değişir.
        if ((6 * x * x) % (y * y) == 0 &&
            {x, y}.contains(6 * x * x ~/ (y * y))) {
          y += 20;
        }
        return kesirli(
          'Bir kenarı $x cm olan düzgün altıgenin alanı, bir kenarı $y cm olan '
              'eşkenar üçgenin alanının kaç katıdır?',
          6 * x * x,
          y * y,
          [(6 * x, y), (x * x, y * y), (3 * x * x, y * y)],
          'Altıgen, kenarı $x cm olan altı eşkenar üçgenden oluşur. Eşkenar '
              'üçgenlerin alanları oranı kenarlar oranının karesidir: '
              '6·$x² / $y² = ${6 * x * x}/${y * y}'
              '${kesir(6 * x * x, y * y) == '${6 * x * x}/${y * y}' ? '' : ' = ${kesir(6 * x * x, y * y)}'}.',
        );
      }
      if (c == 3 || c == 7) {
        final x = 2 + a;
        final kisa = c == 3;
        final (p, r) = kisa ? _dortgenKatsayi[b % 10] : _altigenKatsayi[b % 10];
        final kenar = 4 + b + a ~/ 2;
        // Kısa köşegen: |AC| = kenar·√3; uzun köşegen: |AD| = 2·kenar.
        final hedef = kisa ? kenar : 2 * kenar;
        final q = hedef - p * x, s = kenar - r * x;
        final kosegen = kisa
            ? '|AC| = (${_dx(p, q)})√3 cm'
            : '|AD| = (${_dx(p, q)}) cm';
        final kural = kisa
            ? 'Düzgün altıgende kısa köşegen kenarın √3 katıdır: |AC| = '
                  '|AB|·√3. Buradan ${_dx(p, q)} = ${_dx(r, s)}'
            : 'Düzgün altıgende uzun köşegen kenarın iki katıdır: |AD| = '
                  '2·|BC|. Buradan ${_dx(p, q)} = 2·(${_dx(r, s)})';
        return sayisal(
          'ABCDEF düzgün altıgeninde $kosegen ve |${kisa ? 'AB' : 'BC'}| = '
              '(${_dx(r, s)}) cm olarak veriliyor. Buna göre altıgenin çevresi kaç '
              'cm olur?',
          6 * kenar,
          [kenar, 3 * kenar, 6 * x, 12 * kenar],
          '$kural, x = $x bulunur. Bir kenar $kenar cm olduğundan çevre '
              '6·$kenar = ${6 * kenar} cm.',
          unit: 'cm',
          positive: true,
        );
      }
      if (c == 4) {
        final ak = 20 + 2 * a, tur = 2 + b, yol = 6 * ak * tur + 2 * ak;
        return sayisal(
          'Bir kenarının uzunluğu $ak m olan düzgün altıgen biçimindeki bir '
              'parkın çevresinde $tur tur koşan bir sporcu, ardından bulunduğu '
              'köşeden karşı köşeye parkın en uzun köşegeni boyunca yürüyor. '
              'Sporcu toplam kaç m yol almıştır?',
          yol,
          [6 * ak * tur + ak, 6 * ak * tur, 6 * ak * (tur + 1)],
          'Parkın çevresi 6·$ak = ${6 * ak} m, $tur turda ${6 * ak * tur} m '
              'koşulur. Düzgün altıgende en uzun köşegen kenarın iki katıdır: '
              '${2 * ak} m. Toplam ${6 * ak * tur} + ${2 * ak} = $yol m.',
          unit: 'm',
          positive: true,
        );
      }
      if (c == 5 || c == 9) {
        final (x, y) = _sekizgenCerceve[i + (c == 9 ? 500 : 0)];
        final m = 2 * (x * x - y * y);
        return sayisal(
          'Bir kenarı $x cm olan düzgün sekizgen biçimindeki bir levhanın '
              'ortasından, kenarı $y cm olan ve kenarları levhanın kenarlarına '
              'paralel düzgün sekizgen biçiminde bir parça çıkarılıyor. Kalan '
              'çerçevenin alanı (m + n√2) cm² olduğuna göre m + n toplamı kaçtır?',
          2 * m,
          [m, 4 * (x - y) * (x - y), 4 * m],
          'Kenarı a olan düzgün sekizgenin alanı 2a²(1 + √2) olur. Çerçeve '
              'alanı 2·($x² − $y²)·(1 + √2) = $m + $m√2 cm² olduğundan m = n = $m '
              've m + n = ${2 * m}.',
          positive: true,
        );
      }
      // c == 6: düzgün sekizgende çevre ve kenar.
      final x = 2 + a;
      final (p, r) = _sekizgenKatsayi[b % 10];
      var kenar = 14 + b + a % 3;
      if ({
        (8 * kenar - p * x).abs(),
        (kenar - r * x).abs(),
        p,
        r,
        x,
      }.contains(kenar)) {
        kenar += 30;
      }
      final q = 8 * kenar - p * x, s = kenar - r * x;
      return sayisal(
        'ABCDEFGH düzgün sekizgeninin çevresi (${_dx(p, q)}) cm ve bir '
            'kenarının uzunluğu (${_dx(r, s)}) cm olarak veriliyor. Buna göre '
            'sekizgenin bir kenarı kaç cm olur?',
        kenar,
        [8 * kenar, x, ?_bol(p * x + q, 6)],
        'Düzgün sekizgenin sekiz kenarı eşittir: ${_dx(p, q)} = '
            '8·(${_dx(r, s)}). Buradan x = $x ve bir kenar ${_dx(r, s)} = $kenar '
            'cm bulunur.',
        unit: 'cm',
        positive: true,
      );
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 13 · Kare dik piramit ve düzgün üçgen piramit.
  lmAile(
    'gm_piramit',
    'Kare dik piramit ve düzgün üçgen piramit',
    _mat,
    Difficulty.hard,
    BloomLevel.uygulama,
    (a, b, c) {
      const kare = 'kare dik piramidin';
      switch (c) {
        case 0:
          final t = 3 + a, h = 3 + 3 * b, v = t * t * h ~/ 3;
          return sayisal(
            'Taban ayrıtı $t cm, yüksekliği $h cm olan bir $kare hacmi kaç cm³ '
                'olur?',
            v,
            [t * t * h, ?_bol(t * t * h, 2), ?_bol(t * h, 3)],
            'Piramidin hacmi taban alanı ile yüksekliğin çarpımının üçte '
                'biridir: $t²·$h / 3 = ${t * t}·$h / 3 = $v cm³.',
            unit: 'cm³',
            positive: true,
          );
        case 1:
          final t = 4 + a;
          var h = 3 + 3 * b;
          if (h == t) h += 60;
          final v = t * t * h ~/ 3;
          return sayisal(
            'Taban ayrıtı $t cm olan bir kare dik piramidin hacmi $v cm³ '
                'olduğuna göre yüksekliği kaç cm olur?',
            h,
            [h ~/ 3, ?_bol(v, t), ?_bol(v, t * t)],
            'Hacim taban alanı · yükseklik / 3 olduğundan ${t * t}·h / 3 = $v, '
                'h = 3·$v / ${t * t} = $h cm.',
            unit: 'cm',
            positive: true,
          );
        case 2:
          final i = a + 25 * b, alt = i % 5, n = _piramitUclu.length;
          final ((l1, l2, w), k) = _piramitUclu[(i ~/ 5) * n ~/ 100];
          final t = 2 * k * l1, h = k * l2, ys = k * w;
          const dik =
              'Piramidin yüksekliği ile taban merkezinden bir taban ayrıtının '
              'orta noktasına olan uzaklık (taban ayrıtının yarısı) dik '
              'kenarlar, yan yüz yüksekliği hipotenüs olmak üzere bir dik üçgen '
              'oluşturur';
          return switch (alt) {
            0 => sayisal(
              'Taban ayrıtı $t cm, yüksekliği $h cm olan bir $kare yan yüz '
                  'yüksekliği kaç cm olur?',
              ys,
              [h + k * l1, ?_tamKok(h * h + t * t), t],
              '$dik: √($h² + ${k * l1}²) = $ys cm.',
              unit: 'cm',
              positive: true,
            ),
            1 => sayisal(
              'Taban ayrıtı $t cm, yan yüz yüksekliği $ys cm olan bir $kare '
                  'yüksekliği kaç cm olur?',
              h,
              [ys - k * l1, ?_tamKok(ys * ys - t * t), k * l1],
              '$dik: √($ys² − ${k * l1}²) = $h cm.',
              unit: 'cm',
              positive: true,
            ),
            2 => sayisal(
              'Taban ayrıtı $t cm, yüksekliği $h cm olan bir $kare yanal alanı '
                  'kaç cm² olur?',
              2 * t * ys,
              [4 * t * ys, t * ys, 2 * t * h],
              '$dik; yan yüz yüksekliği √($h² + ${k * l1}²) = $ys cm. Dört yan '
                  'yüzün alanları toplamı 4·($t·$ys / 2) = ${2 * t * ys} cm².',
              unit: 'cm²',
              positive: true,
            ),
            3 => sayisal(
              'Taban ayrıtı $t cm, yan yüz yüksekliği $ys cm olan bir $kare '
                  'hacmi kaç cm³ olur?',
              t * t * h ~/ 3,
              [t * t * h, ?_bol(t * t * ys, 3), t * t * ys],
              '$dik; yükseklik √($ys² − ${k * l1}²) = $h cm. Hacim $t²·$h / 3 '
                  '= ${t * t * h ~/ 3} cm³.',
              unit: 'cm³',
              positive: true,
            ),
            _ => sayisal(
              'Yüksekliği $h cm, yan yüz yüksekliği $ys cm olan bir $kare tüm '
                  'yüzey alanı kaç cm² olur?',
              t * t + 2 * t * ys,
              [
                2 * t * ys,
                t * t + 4 * t * ys,
                k * l1 * k * l1 + 2 * k * l1 * ys,
              ],
              '$dik; taban ayrıtının yarısı √($ys² − $h²) = ${k * l1} cm, taban '
                  'ayrıtı $t cm olur. Tüm alan $t² + 4·($t·$ys / 2) = '
                  '${t * t + 2 * t * ys} cm².',
              unit: 'cm²',
              positive: true,
            ),
          };
        case 3 || 4 || 7:
          final t = 2 + 2 * a;
          var ys = a + 2 + b;
          if (c == 7 && ys == t) ys += 30;
          final yanal = 2 * t * ys, tum = t * t + yanal;
          if (c == 3) {
            return sayisal(
              'Taban ayrıtı $t cm, yan yüz yüksekliği $ys cm olan bir $kare '
                  'yanal alanı kaç cm² olur?',
              yanal,
              [t * ys, 4 * t * ys, tum],
              'Her yan yüz tabanı $t cm, yüksekliği $ys cm olan bir ikizkenar '
                  'üçgendir. Yanal alan 4·($t·$ys / 2) = $yanal cm².',
              unit: 'cm²',
              positive: true,
            );
          }
          if (c == 4) {
            return sayisal(
              'Taban ayrıtı $t cm, yan yüz yüksekliği $ys cm olan bir $kare '
                  'tüm yüzey alanı kaç cm² olur?',
              tum,
              [yanal, t * t + 4 * t * ys, t * t + t * ys],
              'Taban alanı $t² = ${t * t} cm², yanal alan 4·($t·$ys / 2) = '
                  '$yanal cm². Tüm alan ${t * t} + $yanal = $tum cm².',
              unit: 'cm²',
              positive: true,
            );
          }
          return sayisal(
            'Taban ayrıtı $t cm olan bir kare dik piramidin tüm yüzey alanı '
                '$tum cm² olduğuna göre yan yüz yüksekliği kaç cm olur?',
            ys,
            [2 * ys, ?_bol(tum, 2 * t), ?_bol(ys, 2)],
            'Tüm alan $t² + 4·($t·h / 2) = ${t * t} + ${2 * t}h = $tum, '
                '${2 * t}h = $yanal ve h = $ys cm.',
            unit: 'cm',
            positive: true,
          );
        case 5 || 8:
          final t = c == 5 ? 2 + 2 * a : 6 + 2 * a;
          var h = 3 + 3 * b;
          // Yanıt kökteki bir sayıya eşit çıkmasın.
          if (c == 8 ? h == t : {t, h}.contains(t * t * h ~/ 12)) h += 60;
          final k = t * t * h ~/ 12;
          const ucgen = 'düzgün üçgen piramidin';
          final taban = 'Taban alanı ($t²·√3) / 4 = ${t * t ~/ 4}√3 cm² olur.';
          if (c == 5) {
            return sayisal(
              'Taban ayrıtı $t cm, yüksekliği $h cm olan bir $ucgen hacmi k√3 '
                  'cm³ olduğuna göre k kaçtır?',
              k,
              [t * t * h ~/ 4, ?_bol(t * t * h, 6), t * t * h ~/ 3],
              '$taban Hacim (1/3)·${t * t ~/ 4}√3·$h = $k√3 cm³, k = $k.',
              positive: true,
            );
          }
          return sayisal(
            'Taban ayrıtı $t cm olan bir $ucgen hacmi $k√3 cm³ olduğuna göre '
                'yüksekliği kaç cm olur?',
            h,
            [h ~/ 3, ?_bol(4 * k, t), ?_bol(12 * k, t)],
            '$taban (1/3)·${t * t ~/ 4}√3·h = $k√3 eşitliğinden h = 3·$k / '
                '${t * t ~/ 4} = $h cm.',
            unit: 'cm',
            positive: true,
          );
        case 6:
          final t = 2 + 2 * a, ys = t ~/ 3 + 1 + b, yanal = 3 * t * ys ~/ 2;
          return sayisal(
            'Taban ayrıtı $t cm ve yan yüz yüksekliği $ys cm olan bir düzgün '
                'üçgen piramidin yanal alanı kaç cm² olur?',
            yanal,
            [3 * t * ys, t * ys ~/ 2, 2 * t * ys],
            'Düzgün üçgen piramidin üç yan yüzü tabanı $t cm, yüksekliği $ys '
                'cm olan eş ikizkenar üçgenlerdir. Yanal alan 3·($t·$ys / 2) = '
                '$yanal cm².',
            unit: 'cm²',
            positive: true,
          );
        default:
          final t = 2 + a, h = 3 + 3 * b;
          final prizma = t * t * h, piramit = prizma ~/ 3;
          return sayisal(
            'Taban ayrıtı $t cm, yüksekliği $h cm olan kare dik prizma '
                'biçimindeki bir tahta bloktan, tabanı prizmanın alt tabanı ve '
                'tepe noktası üst tabanın merkezi olan bir kare dik piramit oyularak '
                'çıkarılıyor. Kalan parçanın hacmi kaç cm³ olur?',
            prizma - piramit,
            [piramit, prizma, ?_bol(prizma, 2)],
            'Prizmanın hacmi $t²·$h = $prizma cm³, piramidin hacmi $prizma / 3 '
                '= $piramit cm³ olur. Kalan $prizma − $piramit = '
                '${prizma - piramit} cm³.',
            unit: 'cm³',
            positive: true,
          );
      }
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 14 · Hacim korunumu: su seviyesi ve kaptan kaba aktarma.
  lmAile(
    'gm_su_seviyesi',
    'Hacim korunumu: su seviyesi ve sıvı aktarma',
    _mat,
    Difficulty.medium,
    BloomLevel.analiz,
    (a, b, c) {
      final i = a + 25 * b;
      String cm(num x) => '${tr(x)} cm';
      switch (c) {
        case 0:
          final (e, l, w) = _yay(_suKup, i);
          final d = _ondalik(e * e * e, l * w)!, h0 = e + 2 + (l + w) % 7;
          final sor = i.isEven;
          final yanit = sor ? d : h0 + d;
          return ondalikli(
            'Taban ayrıtları $l cm ve $w cm olan dikdörtgenler prizması '
                'biçimindeki bir kapta $h0 cm yüksekliğinde su vardır. Kaba bir '
                'ayrıtı $e cm olan küp biçiminde bir demir parça bırakılıyor ve '
                'parça tamamen suya batıyor. Su taşmadığına göre '
                '${sor ? 'su seviyesi kaç cm yükselir' : 'suyun son yüksekliği kaç cm olur'}?',
            yanit,
            [
              sor ? h0 + d : d,
              ?_ondalik(6 * e * e, l * w),
              ?_ondalik(e * e, l * w),
              ?_ondalik(e * e * e, 2 * l * w),
            ],
            'Küpün hacmi $e³ = ${e * e * e} cm³ kadar su yer değiştirir. Kabın '
                'taban alanı $l·$w = ${l * w} cm² olduğundan su seviyesi '
                '${e * e * e} / ${l * w} = ${cm(d)} yükselir.'
                '${sor ? '' : ' Son yükseklik $h0 + ${tr(d)} = ${cm(h0 + d)}.'}',
            unit: 'cm',
            positive: true,
          );
        case 1:
          if (i < 250) {
            final (n, r, R) = _yay(_suBilye, 2 * i);
            final d = _ondalik(4 * n * r * r * r, 3 * R * R)!;
            return ondalikli(
              'Taban yarıçapı $R cm olan dik dairesel silindir biçimindeki bir '
                  'kapta su vardır. Kaba, her birinin yarıçapı $r cm olan $n tane '
                  'metal bilye bırakılıyor. Bilyeler tamamen suya battığına ve su '
                  'taşmadığına göre su seviyesi kaç cm yükselir?',
              d,
              [
                ?_ondalik(n * r * r * r, R * R),
                ?_ondalik(4 * n * r * r, 3 * R),
                ?_ondalik(4 * r * r * r, 3 * R * R),
                ?_ondalik(32 * n * r * r * r, 3 * R * R),
              ],
              'Bilyelerin toplam hacmi $n·(4/3)·π·$r³ = '
                  '${kesir(4 * n * r * r * r, 3)}π cm³ olur. Bu hacim π·$R²·h '
                  'kadar suyu yükseltir: h = ${kesir(4 * n * r * r * r, 3)} / '
                  '${R * R} = ${cm(d)}.',
              unit: 'cm',
              positive: true,
            );
          }
          final (x, y, z, R) = _yay(_suBlokSilindir, 2 * (i - 250));
          final v = x * y * z, d = _ondalik(v, 3 * R * R)!;
          return ondalikli(
            'Taban yarıçapı $R cm olan dik dairesel silindir biçimindeki bir '
                'kapta su vardır. Kaba, ayrıtları $x cm, $y cm ve $z cm olan '
                'dikdörtgenler prizması biçiminde bir metal blok bırakılıyor; blok '
                'tamamen suya batıyor ve su taşmıyor. Buna göre su seviyesi kaç cm '
                'yükselir? (π = 3 alınız.)',
            d,
            [?_ondalik(v, R * R), ?_ondalik(v, 6 * R * R), ?_ondalik(v, 3 * R)],
            'Bloğun hacmi $x·$y·$z = $v cm³, kabın taban alanı 3·$R² = '
                '${3 * R * R} cm² olur. Yükselme $v / ${3 * R * R} = ${cm(d)}.',
            unit: 'cm',
            positive: true,
          );
        case 2:
          final (r1, h1, r2) = _yay(_suSilindir, i);
          final d = _ondalik(h1 * r1 * r1, r2 * r2)!;
          return ondalikli(
            'Taban yarıçapı $r1 cm olan dik dairesel silindir biçimindeki bir '
                'kapta $h1 cm yüksekliğinde su vardır. Bu suyun tamamı, taban '
                'yarıçapı $r2 cm olan dik dairesel silindir biçimindeki boş bir '
                'kaba taşmadan boşaltılıyor. İkinci kaptaki suyun yüksekliği kaç cm '
                'olur?',
            d,
            [
              ?_ondalik(h1 * r2 * r2, r1 * r1),
              ?_ondalik(h1 * r1, r2),
              ?_ondalik(h1 * r1 * r1, 2 * r2 * r2),
            ],
            'Suyun hacmi π·$r1²·$h1 = ${r1 * r1 * h1}π cm³ olur. İkinci kapta '
                'π·$r2²·h = ${r1 * r1 * h1}π eşitliğinden h = ${r1 * r1 * h1} / '
                '${r2 * r2} = ${cm(d)}.',
            unit: 'cm',
            positive: true,
          );
        case 3:
          final (l1, w1, h1, l2, w2) = _yay(_suPrizma, i);
          final d = _ondalik(h1 * l1 * w1, l2 * w2)!;
          return ondalikli(
            'Taban ayrıtları $l1 cm ve $w1 cm olan dikdörtgenler prizması '
                'biçimindeki bir kapta $h1 cm yüksekliğinde su vardır. Bu suyun '
                'tamamı, taban ayrıtları $l2 cm ve $w2 cm olan dikdörtgenler '
                'prizması biçimindeki boş bir kaba taşmadan boşaltılıyor. İkinci '
                'kaptaki suyun yüksekliği kaç cm olur?',
            d,
            [
              ?_ondalik(h1 * l2 * w2, l1 * w1),
              ?_ondalik(h1 * (l1 + w1), l2 + w2),
              ?_ondalik(h1 * l1 * w1, 2 * l2 * w2),
            ],
            'Suyun hacmi $l1·$w1·$h1 = ${l1 * w1 * h1} cm³ olur. İkinci kabın '
                'taban alanı $l2·$w2 = ${l2 * w2} cm² olduğundan yükseklik '
                '${l1 * w1 * h1} / ${l2 * w2} = ${cm(d)}.',
            unit: 'cm',
            positive: true,
          );
        case 4:
          final (r1, h, r2) = _yay(_suKoni, i);
          final d = _ondalik(h * r1 * r1, 3 * r2 * r2)!;
          return ondalikli(
            'Taban yarıçapı $r1 cm, yüksekliği $h cm olan dik dairesel koni '
                'biçimindeki bir kap ağzına kadar su ile doludur. Bu suyun tamamı, '
                'taban yarıçapı $r2 cm olan dik dairesel silindir biçimindeki boş '
                'bir kaba taşmadan boşaltılıyor. Silindirdeki suyun yüksekliği kaç '
                'cm olur?',
            d,
            [
              ?_ondalik(h * r1 * r1, r2 * r2),
              ?_ondalik(h * r1, 3 * r2),
              ?_ondalik(h * r2 * r2, 3 * r1 * r1),
            ],
            'Koninin hacmi π·$r1²·$h / 3 = ${kesir(r1 * r1 * h, 3)}π cm³ olur. '
                'π·$r2²·x = ${kesir(r1 * r1 * h, 3)}π eşitliğinden x = '
                '${kesir(r1 * r1 * h, 3)} / ${r2 * r2} = ${cm(d)}.',
            unit: 'cm',
            positive: true,
          );
        case 5:
          final (x, y, z, l, w) = _yay(_suBlok, i);
          final d = _ondalik(x * y * z, l * w)!, h0 = z + 3 + (x + l) % 6;
          return ondalikli(
            'Taban ayrıtları $l cm ve $w cm olan dikdörtgenler prizması '
                'biçimindeki bir kapta, ayrıtları $x cm, $y cm ve $z cm olan '
                'dikdörtgenler prizması biçiminde bir metal blok tamamen su içinde '
                'durmaktadır ve suyun yüksekliği $h0 cm olarak ölçülmüştür. Blok '
                'kaptan çıkarılırsa su seviyesi kaç cm düşer?',
            d,
            [
              h0 - d,
              ?_ondalik(x * y * z, l * w * z),
              ?_ondalik(x * y * z, 2 * (l + w)),
            ],
            'Bloğun hacmi $x·$y·$z = ${x * y * z} cm³ kadar su seviyesi düşer: '
                '${x * y * z} / ($l·$w) = ${cm(d)}.',
            unit: 'cm',
            positive: true,
          );
        case 6:
          final (r, h, R) = _yay(_suCubuk, i);
          final d = _ondalik(r * r * h, R * R)!, h0 = h + 2 + (r + R) % 5;
          return ondalikli(
            'Taban yarıçapı $R cm olan dik dairesel silindir biçimindeki bir '
                'kapta $h0 cm yüksekliğinde su vardır. Kaba, taban yarıçapı $r cm '
                've yüksekliği $h cm olan silindir biçiminde bir metal çubuk dik '
                'olarak bırakılıyor ve çubuk tamamen suya batıyor. Su taşmadığına '
                'göre su seviyesi kaç cm yükselir?',
            d,
            [?_ondalik(r * h, R), ?_ondalik(r * r * h, R * R - r * r), h0 + d],
            'Çubuğun hacmi π·$r²·$h = ${r * r * h}π cm³ olur. Bu hacim π·$R²·x '
                'kadar suyu yükseltir: x = ${r * r * h} / ${R * R} = ${cm(d)}.',
            unit: 'cm',
            positive: true,
          );
        case 7:
          final (l, w, h, r) = _yay(_suPrizmaSilindir, i);
          final d = _ondalik(l * w * h, 3 * r * r)!;
          return ondalikli(
            'Taban ayrıtları $l cm ve $w cm olan dikdörtgenler prizması '
                'biçimindeki bir kapta $h cm yüksekliğinde su vardır. Bu suyun '
                'tamamı, taban yarıçapı $r cm olan dik dairesel silindir biçimindeki '
                'boş bir kaba taşmadan boşaltılıyor. Silindirdeki suyun yüksekliği '
                'kaç cm olur? (π = 3 alınız.)',
            d,
            [
              ?_ondalik(l * w * h, r * r),
              ?_ondalik(l * w * h, 6 * r * r),
              ?_ondalik(l * w * h, 3 * r),
            ],
            'Suyun hacmi $l·$w·$h = ${l * w * h} cm³, silindirin taban alanı '
                '3·$r² = ${3 * r * r} cm² olur. Yükseklik ${l * w * h} / '
                '${3 * r * r} = ${cm(d)}.',
            unit: 'cm',
            positive: true,
          );
        case 8:
          final (r, h, l, w) = _yay(_suSilindirPrizma, i);
          final d = _ondalik(3 * r * r * h, l * w)!;
          return ondalikli(
            'Taban yarıçapı $r cm olan dik dairesel silindir biçimindeki bir '
                'kapta $h cm yüksekliğinde su vardır. Bu suyun tamamı, taban '
                'ayrıtları $l cm ve $w cm olan dikdörtgenler prizması biçimindeki '
                'boş bir kaba taşmadan boşaltılıyor. İkinci kaptaki suyun '
                'yüksekliği kaç cm olur? (π = 3 alınız.)',
            d,
            [
              ?_ondalik(r * r * h, l * w),
              ?_ondalik(6 * r * h, l * w),
              ?_ondalik(3 * r * r * h, 2 * (l + w)),
            ],
            'Suyun hacmi 3·$r²·$h = ${3 * r * r * h} cm³, prizmanın taban '
                'alanı $l·$w = ${l * w} cm² olur. Yükseklik ${3 * r * r * h} / '
                '${l * w} = ${cm(d)}.',
            unit: 'cm',
            positive: true,
          );
        default:
          final (r, h, R) = _yay(_suKoniCisim, i);
          final d = _ondalik(r * r * h, 3 * R * R)!, h0 = h + 2 + (r + R) % 5;
          return ondalikli(
            'Taban yarıçapı $R cm olan dik dairesel silindir biçimindeki bir '
                'kapta $h0 cm yüksekliğinde su vardır. Kaba, taban yarıçapı $r cm '
                've yüksekliği $h cm olan dik dairesel koni biçiminde bir metal '
                'parça tabanı kabın tabanına oturacak biçimde bırakılıyor ve parça '
                'tamamen suya batıyor. Su taşmadığına göre su seviyesi kaç cm '
                'yükselir?',
            d,
            [?_ondalik(r * r * h, R * R), ?_ondalik(r * h, 3 * R), h0 + d],
            'Koninin hacmi π·$r²·$h / 3 = ${kesir(r * r * h, 3)}π cm³ olur. Bu '
                'hacim π·$R²·x kadar suyu yükseltir: x = ${kesir(r * r * h, 3)} / '
                '${R * R} = ${cm(d)}.',
            unit: 'cm',
            positive: true,
          );
      }
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 15 · Benzer katı cisimlerde uzunluk, alan ve hacim oranları.
  lmAile(
    'gm_benzer_cisim',
    'Benzer cisimlerde uzunluk, yüzey alanı ve hacim oranı',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final (m, n) = _benzerOran[a];
      final u = 1 + b, cisim = _benzerCisim[(a + b) % 5];
      final m3 = m * m * m, n3 = n * n * n;
      switch (c) {
        case 0:
          return sayisal(
            'Benzerlik oranı $m/$n olan benzer iki $cisim biçimindeki cisimden '
                'küçüğünün hacmi ${m3 * u} cm³ olduğuna göre büyüğünün hacmi kaç '
                'cm³ olur?',
            n3 * u,
            [
              ?_bol(m3 * u * n, m),
              ?_bol(m3 * u * n * n, m * m),
              n3 * u - m3 * u,
            ],
            'Benzer cisimlerde hacimler oranı benzerlik oranının küpüdür: '
                '($m/$n)³ = $m3/$n3. Büyüğün hacmi ${m3 * u}·$n3 / $m3 = '
                '${n3 * u} cm³.',
            unit: 'cm³',
            positive: true,
          );
        case 1:
          return sayisal(
            'Benzer iki $cisim biçimindeki cisimden küçüğünün yüzey alanının '
                'büyüğünün yüzey alanına oranı ${m * m}/${n * n} olarak veriliyor. '
                'Küçüğünün hacmi ${m3 * u} cm³ olduğuna göre büyüğünün hacmi kaç '
                'cm³ olur?',
            n3 * u,
            [?_bol(m3 * u * n * n, m * m), ?_bol(m3 * u * n, m), n3 * u * 2],
            'Yüzey alanları oranı benzerlik oranının karesidir; benzerlik oranı '
                '$m/$n olur. Hacimler oranı $m3/$n3 olduğundan büyüğün hacmi '
                '${m3 * u}·$n3 / $m3 = ${n3 * u} cm³.',
            unit: 'cm³',
            positive: true,
          );
        case 2:
          final h = 1 + b == n * n ? 21 + b : 1 + b;
          return sayisal(
            'Benzer iki kaptan küçüğünün hacmi $m3 L, büyüğünün hacmi $n3 L '
                'olarak veriliyor. Küçük kabın yüksekliği ${m * h} cm olduğuna göre '
                'büyük kabın yüksekliği kaç cm olur?',
            n * h,
            [?_bol(n3 * h, m * m), ?_bol(n * n * h, m), n3 * h],
            'Hacimler oranı $m3/$n3 benzerlik oranının küpüdür; benzerlik oranı '
                '$m/$n olur. Büyük kabın yüksekliği ${m * h}·$n / $m = ${n * h} '
                'cm.',
            unit: 'cm',
            positive: true,
          );
        case 3 || 4:
          // 1/10 ölçeğinde kütle sorusunun yanıtı (kg) gram değerine eşit çıkar;
          // kütle sorusunda 10 yerine 12 kullanılır.
          final k = c == 4
              ? const [2, 3, 4, 5, 6, 7, 8, 9, 12][b % 9]
              : 2 + b % 9;
          final q = b ~/ 9;
          if (c == 3) {
            final x = 10 + 5 * a + 125 * q;
            return sayisal(
              'Bir heykelin 1/$k ölçekli benzer maketinin dış yüzeyini boyamak '
                  'için $x mL boya harcanıyor. Aynı boya ile heykelin kendisinin '
                  'dış yüzeyini boyamak için kaç mL boya gerekir?',
              x * k * k,
              [x * k, x * k * k * k, x * 2 * k],
              'Boya miktarı yüzey alanıyla orantılıdır. Yüzey alanları oranı '
                  'ölçeğin karesi olduğundan heykel için $x·$k² = ${x * k * k} mL '
                  'boya gerekir.',
              unit: 'mL',
              positive: true,
            );
          }
          final x = 10 * (1 + a) + 250 * q, g = x * k * k * k;
          return ondalikli(
            'Bir heykelin 1/$k ölçekli benzer maketi, heykelle aynı malzemeden '
                'yapılmış ve kütlesi $x g olarak ölçülmüştür. Buna göre heykelin '
                'kütlesi kaç kg olur?',
            g / 1000,
            [x * k * k / 1000, x * k / 1000, g / 100],
            'Aynı malzemede kütle hacimle orantılıdır. Hacimler oranı ölçeğin '
                'küpü olduğundan heykelin kütlesi $x·$k³ = $g g = ${tr(g / 1000)} '
                'kg olur.',
            unit: 'kg',
            positive: true,
          );
        case 5 || 6:
          final v = {4 * m, 4 * n}.contains(m3 * u) ? u + 20 : u;
          final hacim = n3 * v, kucuk = m3 * v;
          final veri =
              'Yüksekliği ${4 * n} cm ve hacmi $hacim cm³ olan bir dik dairesel '
              'koni, tepe noktasından ${4 * m} cm uzaklıkta tabana paralel bir '
              'düzlemle kesiliyor.';
          final cozum =
              'Kesitin üstünde kalan koni büyük koniye benzerdir; benzerlik '
              'oranı ${4 * m}/${4 * n} = $m/$n, hacimler oranı $m3/$n3 olur. '
              'Küçük koninin hacmi '
              '$hacim·$m3 / $n3 = $kucuk cm³.';
          if (c == 5) {
            return sayisal(
              '$veri Tepedeki küçük koninin hacmi kaç cm³ olur?',
              kucuk,
              [?_bol(hacim * m, n), ?_bol(hacim * m * m, n * n), hacim - kucuk],
              cozum,
              unit: 'cm³',
              positive: true,
            );
          }
          return sayisal(
            '$veri Kesik koninin hacmi kaç cm³ olur?',
            hacim - kucuk,
            [
              kucuk,
              ?_bol(hacim * (n - m), n),
              ?_bol(hacim * (n * n - m * m), n * n),
            ],
            '$cozum Kesik koninin hacmi $hacim − $kucuk = ${hacim - kucuk} cm³.',
            unit: 'cm³',
            positive: true,
          );
        case 7 || 8:
          final v = {m, n}.contains(m3 * u) ? u + 20 : u;
          final hacim = n3 * v, su = m3 * v;
          const kap =
              'Tepe noktası aşağıda ve ekseni düşey olan dik dairesel koni '
              'biçimindeki bir kap';
          const cozum =
              'Kaptaki su, kapla benzer bir koni oluşturur; hacimler oranı '
              'yükseklikler oranının küpüdür.';
          if (c == 7) {
            return sayisal(
              '$kap ağzına kadar doldurulduğunda $hacim cm³ su alıyor. Kaba, su '
                  'yüksekliği kabın yüksekliğinin $m/$n katı olana kadar su '
                  'konuyor. Kaptaki su kaç cm³ olur?',
              su,
              [?_bol(hacim * m, n), ?_bol(hacim * m * m, n * n), hacim - su],
              '$cozum Su $hacim·($m/$n)³ = $hacim·$m3 / $n3 = $su cm³.',
              unit: 'cm³',
              positive: true,
            );
          }
          return sayisal(
            '$kap içinde $su cm³ su vardır ve suyun yüksekliği kabın '
                'yüksekliğinin $m/$n katıdır. Kap ağzına kadar doldurulursa kaç cm³ '
                'su alır?',
            hacim,
            [?_bol(su * n, m), ?_bol(su * n * n, m * m), hacim - su],
            '$cozum Kabın hacmi $su·($n/$m)³ = $su·$n3 / $m3 = $hacim cm³.',
            unit: 'cm³',
            positive: true,
          );
        default:
          final w = 1 + b == n ? 21 + b : 1 + b;
          return sayisal(
            'Benzer iki $cisim biçimindeki cisimden küçüğünün hacmi $m3 cm³, '
                'büyüğünün hacmi $n3 cm³ olarak veriliyor. Küçüğünün yüzey alanı '
                '${m * m * w} cm² olduğuna göre büyüğünün yüzey alanı kaç cm² olur?',
            n * n * w,
            [n3 * w, ?_bol(m * m * w * n, m), ?_bol(m * m * w * n3, m3)],
            'Hacimler oranı $m3/$n3 olduğundan benzerlik oranı $m/$n, yüzey '
                'alanları oranı ${m * m}/${n * n} olur. Büyüğün yüzey alanı '
                '${m * m * w}·${n * n} / ${m * m} = ${n * n * w} cm².',
            unit: 'cm²',
            positive: true,
          );
      }
    },
    exam: ExamKind.tyt,
    lesson: _tm,
  ),
  // 16 · İki doğrunun kesişim noktası; doğrusal ve aynı noktadan geçen.
  lmAile(
    'gm_dogru_kesisim',
    'İki doğrunun kesişimi ve noktaların doğrusallığı',
    _mat,
    Difficulty.easy,
    BloomLevel.uygulama,
    (a, b, c) {
      if (c <= 2) {
        final x0 = a - 12, y0 = b - 9;
        if (c == 1) {
          // Birinci doğru eğimli biçimde: y = mx + n.
          final m = _egimler[(a + 2 * b) % 8], n = y0 - m * x0;
          var j = (a + b + c) % 8;
          var (p2, q2) = _kesisimKatsayi[j].$2;
          while (p2 + q2 * m == 0) {
            j++;
            (p2, q2) = _kesisimKatsayi[j % 8].$2;
          }
          final c2 = p2 * x0 + q2 * y0;
          return _noktali(
            'Analitik düzlemde ${_egimli(m, n)} ve ${_dogruEsit(p2, q2, c2)} '
                'doğrularının kesişim noktasının koordinatları hangisidir?',
            (x0, y0),
            [(y0, x0), (-x0, -y0), (x0, -y0), (-x0, y0)],
            'y = ${_ifade([(m, 'x'), (n, '')])} ifadesi ikinci denklemde '
                'yerine yazılırsa ${_ifade([(p2 + q2 * m, 'x'), (q2 * n, '')])} = '
                '${_m(c2)}, buradan x = ${_m(x0)} bulunur. y = ${_m(m)}·${_pz(x0)}'
                '${n == 0 ? '' : (n < 0 ? ' − ${-n}' : ' + $n')} = ${_m(y0)} olur.',
          );
        }
        final ((p1, q1), (p2, q2)) = _kesisimKatsayi[(a + b + c) % 8];
        final c1 = p1 * x0 + q1 * y0, c2 = p2 * x0 + q2 * y0;
        final det = p1 * q2 - p2 * q1, sag = c1 * q2 - c2 * q1;
        final cozum =
            'Birinci denklem ${_pz(q2)} ile, ikinci denklem ${_pz(q1)} ile '
            'çarpılıp taraf tarafa çıkarılırsa ${_m(det)}x = ${_m(sag)} olur ve '
            'x = ${_m(x0)} bulunur. Bu değer birinci denklemde yerine '
            'yazılırsa y = ${_m(y0)} olur.';
        final veri =
            'Analitik düzlemde ${_dogruEsit(p1, q1, c1)} ve '
            '${_dogruEsit(p2, q2, c2)} doğruları';
        if (c == 0) {
          return _noktali(
            '$veri bir noktada kesişiyor. Bu kesişim noktasının koordinatları '
            'hangisidir?',
            (x0, y0),
            [(y0, x0), (-x0, -y0), (x0, -y0), (-x0, y0)],
            cozum,
          );
        }
        return _tam(
          '$veri (a, b) noktasında kesiştiğine göre a + b toplamı kaçtır?',
          x0 + y0,
          [x0 - y0, y0 - x0, -(x0 + y0)],
          '$cozum a + b = ${_m(x0)} + ${_pz(y0)} = ${_m(x0 + y0)}.',
        );
      }
      if (c <= 5) {
        final x1 = a - 12, ham = b % 10 - 4, y1 = ham == 0 ? 6 : ham;
        if (c == 5) {
          const tek = [(1, 1), (2, 1), (1, -1), (3, 1), (2, -1), (3, -1)];
          final (dx, dy) = tek[(b ~/ 10) * 3 + a % 3];
          final adim = y1 + dy == 0 ? 2 : 1;
          final bx = x1 + adim * dx, by = y1 + adim * dy;
          final k = x1 - y1 * dx ~/ dy;
          return _tam(
            'Analitik düzlemde A${_n(x1, y1)}, B${_n(bx, by)} ve C(k, 0) '
                'noktaları doğrusal olduğuna göre k kaçtır?',
            k,
            [x1 + y1 * dx ~/ dy, ?_bolIsaretli(x1 * dx - y1 * dy, dx), -k],
            'Doğrusal noktalarda AB ve AC doğrularının eğimleri eşittir. AB '
                'doğrusunun eğimi (${_m(by)} − ${_pz(y1)}) / (${_m(bx)} − '
                '${_pz(x1)}) = ${_kesirli(adim * dy, adim * dx)} olur. AC için '
                '(0 − ${_pz(y1)}) / (k − ${_pz(x1)}) = '
                '${_kesirli(adim * dy, adim * dx)} eşitliğinden k = ${_m(k)} '
                'bulunur.',
          );
        }
        final (dx, dy) = _yonler[(b ~/ 10) * 3 + a % 3];
        var t = 2 + (a + b) % 3;
        // c = 3 sorusunda C noktası x ekseni üzerine düşerse c = 5 köküyle
        // çakışır; bu durumda C noktası ötelenir.
        if (c == 3 && y1 + t * dy == 0) t += 3;
        final bx = x1 + dx, by = y1 + dy, cx = x1 + t * dx, cy = y1 + t * dy;
        final egim = _kesirli(dy, dx);
        if (c == 3) {
          return _tam(
            'Analitik düzlemde A${_n(x1, y1)}, B${_n(bx, by)} ve '
                'C(k, ${_m(cy)}) noktaları doğrusal olduğuna göre k kaçtır?',
            cx,
            [x1 - t * dx, x1 + (t - 1) * dx, x1 + t * dy],
            'AB doğrusunun eğimi (${_m(by)} − ${_pz(y1)}) / (${_m(bx)} − '
                '${_pz(x1)}) = $egim olur. AC doğrusunun eğimi de aynı olmalıdır: '
                '(${_m(cy)} − ${_pz(y1)}) / (k − ${_pz(x1)}) = $egim, buradan '
                'k = ${_m(cx)} bulunur.',
          );
        }
        return _tam(
          'Analitik düzlemde A${_n(x1, y1)}, B${_n(bx, by)} ve '
              'C(${_m(cx)}, k) noktaları doğrusal olduğuna göre k kaçtır?',
          cy,
          [y1 - t * dy, y1 + (t - 1) * dy, y1 + t * dx],
          'AB doğrusunun eğimi (${_m(by)} − ${_pz(y1)}) / (${_m(bx)} − '
              '${_pz(x1)}) = $egim olur. AC doğrusunun eğimi de aynı olmalıdır: '
              '(k − ${_pz(y1)}) / (${_m(cx)} − ${_pz(x1)}) = $egim, buradan '
              'k = ${_m(cy)} bulunur.',
        );
      }
      final x0 = _sifirsiz(a - 12, 13), y0 = _sifirsiz(b - 9, 11);
      final ((p1, q1), (p2, q2)) = _kesisimKatsayi[(a + 2 * b) % 8];
      final c1 = p1 * x0 + q1 * y0, c2 = p2 * x0 + q2 * y0;
      final iki =
          '${_dogruEsit(p1, q1, c1)} ve ${_dogruEsit(p2, q2, c2)} doğrularının '
          'kesişim noktası';
      final kesisim =
          'İlk iki denklem birlikte çözülürse kesişim noktası '
          '${_n(x0, y0)} bulunur.';
      if (c == 6 || c == 7) {
        final k = const [2, -3, 4, -1, 5, -2, 3, 1][(a + b) % 8];
        final e = const [1, 2, -1, 3, -2][b % 5];
        if (c == 6) {
          final c3 = k * x0 + e * y0;
          final ucuncu = _dogruEsit(1, e, c3).replaceFirst('x', 'kx');
          return _tam(
            'Analitik düzlemde ${_dogruEsit(p1, q1, c1)}, '
                '${_dogruEsit(p2, q2, c2)} ve $ucuncu doğruları aynı noktadan '
                'geçtiğine göre k kaçtır?',
            k,
            [?_bolIsaretli(c3 - e * x0, y0), -k, k + e],
            '$kesisim Bu nokta üçüncü doğrunun denklemini sağlar: '
                'k·${_pz(x0)} ${e * y0 < 0 ? '−' : '+'} ${(e * y0).abs()} = '
                '${_m(c3)}, buradan k = ${_m(k)}.',
          );
        }
        final c3 = e * x0 + k * y0;
        final ucuncu = '${_ifade([(e, 'x')])} + ky = ${_m(c3)}';
        return _tam(
          'Analitik düzlemde ${_dogruEsit(p1, q1, c1)}, '
              '${_dogruEsit(p2, q2, c2)} ve $ucuncu doğruları aynı noktadan '
              'geçtiğine göre k kaçtır?',
          k,
          [?_bolIsaretli(c3 - e * y0, x0), -k, k + e],
          '$kesisim Bu nokta üçüncü doğrunun denklemini sağlar: '
              '${_m(e * x0)} + k·${_pz(y0)} = ${_m(c3)}, buradan k = ${_m(k)}.',
        );
      }
      if (c == 8) {
        const ikinci = [(1, 1), (2, -1), (3, 1), (1, -1), (2, 1), (4, -1)];
        final (r, s) = ikinci[(a + b) % 6];
        final m = const [2, -3, 4, -1, 5, -2, 3, 1][b % 8];
        final d2 = r * x0 + s * y0, d1 = m * x0 + y0;
        return _tam(
          'Analitik düzlemde mx + y = ${_m(d1)} ve ${_dogruEsit(r, s, d2)} '
              'doğrularının kesişim noktasının apsisi ${_m(x0)} olduğuna göre m '
              'kaçtır?',
          m,
          [?_bolIsaretli(d1 + y0, x0), -m, ?_bolIsaretli(d1, x0)],
          'x = ${_m(x0)} ikinci denklemde yerine yazılırsa y = ${_m(y0)} '
              'bulunur. Kesişim noktası ${_n(x0, y0)} birinci denklemi de '
              'sağlar: m·${_pz(x0)} + ${_pz(y0)} = ${_m(d1)}, m = ${_m(m)}.',
        );
      }
      final m = const [2, -3, 4, -1, 5, -2, 3, 1][(a + 3 * b) % 8];
      final n = y0 - m * x0;
      return _tam(
        'Analitik düzlemde $iki ile eğimi ${_m(m)} olan bir doğru üzerindedir. '
            'Bu doğrunun y eksenini kestiği noktanın ordinatı kaçtır?',
        n,
        [y0 + m * x0, m * x0 - y0, x0 - m * y0],
        '$kesisim Eğimi ${_m(m)} olan doğru y − ${_pz(y0)} = '
            '${_m(m)}·(x − ${_pz(x0)}) olur. x = 0 yazılırsa y = ${_m(y0)} − '
            '${_pz(m)}·${_pz(x0)} = ${_m(n)}.',
      );
    },
    exam: ExamKind.ayt,
    lesson: _aytMat,
    shortAnswer: false,
  ),
  // 17 · Köşeleri verilen üçgen ve dörtgenin alanı.
  lmAile(
    'gm_koordinat_alan',
    'Köşe koordinatları verilen üçgen ve dörtgenin alanı',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final x1 = a - 12, y1 = b - 10;
      if (c <= 3) {
        final (u1, v1, u2, v2) = switch (c) {
          0 => (3 + a % 5, -(1 + b % 4), 1 + b % 6, 4 + a % 7),
          1 => (-(2 + a % 4), 3 + b % 5, 5 + b % 4, 1 + a % 6),
          2 => (4 + b % 5, 2 + a % 3, -(1 + a % 4), 5 + b % 6),
          _ => (6 + a % 4, -(3 + b % 5), 2 + b % 3, 2 + a % 5),
        };
        final x2 = x1 + u1, y2 = y1 + v1, x3 = x1 + u2, y3 = y1 + v2;
        final t = x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2);
        final yarim = x1 * y2 + x2 * y3 + x3 * y1;
        return ondalikli(
          'Analitik düzlemde köşeleri A${_n(x1, y1)}, B${_n(x2, y2)} ve '
              'C${_n(x3, y3)} olan ABC üçgeninin alanı kaç birimkaredir?',
          t.abs() / 2,
          [
            t.abs().toDouble(),
            (u1 * v2 + u2 * v1).abs() / 2,
            if (yarim != 0) yarim.abs() / 2,
          ],
          'Alan |x₁(y₂ − y₃) + x₂(y₃ − y₁) + x₃(y₁ − y₂)| / 2 bağıntısıyla '
              'bulunur: |${_pz(x1)}·${_pz(y2 - y3)} + ${_pz(x2)}·${_pz(y3 - y1)} + '
              '${_pz(x3)}·${_pz(y1 - y2)}| / 2 = |${_m(t)}| / 2 = '
              '${tr(t.abs() / 2)} birimkare.',
          positive: true,
        );
      }
      if (c <= 6) {
        final vs = switch (c) {
          4 => [
            (0, 0),
            (6 + a % 4, -1 - b % 3),
            (7 + b % 4, 5 + a % 4),
            (-1 - (a + b) % 3, 5 + b % 4),
          ],
          5 => [
            (0, 0),
            (5 + b % 4, 1 + a % 3),
            (4 + a % 4, 7 + b % 4),
            (-2 - b % 3, 4 + a % 4),
          ],
          _ => [
            (0, 0),
            (7 + a % 3, -2 - b % 3),
            (5 + b % 3, 6 + a % 4),
            (-3 - a % 2, 3 + b % 4),
          ],
        };
        final p = [for (final (u, v) in vs) (x1 + u, y1 + v)];
        int kos(List<(int, int)> l) {
          var s = 0;
          for (var j = 0; j < l.length; j++) {
            final (xa, ya) = l[j];
            final (xb, yb) = l[(j + 1) % l.length];
            s += xa * yb - xb * ya;
          }
          return s;
        }

        final s = kos(p), ters = kos([p[0], p[1], p[3], p[2]]);
        final abc = kos([p[0], p[1], p[2]]);
        final ad = ['A', 'B', 'C', 'D'];
        return ondalikli(
          'Analitik düzlemde köşeleri ${[for (var j = 0; j < 4; j++) '${ad[j]}${_n(p[j].$1, p[j].$2)}'].join(', ')} '
              'olan ABCD dörtgeninin alanı kaç birimkaredir?',
          s.abs() / 2,
          [s.abs().toDouble(), ters.abs() / 2, abc.abs() / 2],
          'Köşeler sırasıyla alınarak alan |Σ(xᵢ·yᵢ₊₁ − xᵢ₊₁·yᵢ)| / 2 '
              'bağıntısıyla bulunur. ${[for (var j = 0; j < 4; j++) '${_pz(p[j].$1)}·${_pz(p[(j + 1) % 4].$2)} − ${_pz(p[(j + 1) % 4].$1)}·${_pz(p[j].$2)}'].join(' + ')} '
              '= ${_m(s)} olduğundan alan |${_m(s)}| / 2 = ${tr(s.abs() / 2)} '
              'birimkare.',
          positive: true,
        );
      }
      if (c == 7) {
        final taban = 2 + b % 10, xb = x1 + taban, xc = x1 + a % 4 - 1;
        final yc = (3 + (a + b) % 9) * (b < 10 ? 1 : -1);
        final alan = taban * yc.abs() / 2;
        return ondalikli(
          'Analitik düzlemde köşeleri A(${_m(x1)}, 0), B(${_m(xb)}, 0) ve '
              'C${_n(xc, yc)} olan ABC üçgeninin alanı kaç birimkaredir?',
          alan,
          [
            (taban * yc.abs()).toDouble(),
            (taban + yc.abs()) / 2,
            if (xc != 0) (xc.abs() * yc.abs()) / 2,
          ],
          '[AB] kenarı x ekseni üzerindedir ve uzunluğu ${_m(xb)} − ${_pz(x1)} '
              '= $taban birimdir. C noktasının x eksenine uzaklığı |${_m(yc)}| = '
              '${yc.abs()} birim olduğundan alan $taban·${yc.abs()} / 2 = '
              '${tr(alan)} birimkare.',
          positive: true,
        );
      }
      final h = 1 + (a + 2 * b) % 9, w = 2 + 4 * (b ~/ 10) + a % 3;
      final alan = w * h / 2;
      if (c == 8) {
        final yy = b % 10 - 5, xc = x1 + a % 3;
        return _tam(
          'Analitik düzlemde A${_n(x1, yy)}, B${_n(x1 + w, yy)} ve '
              'C(${_m(xc)}, k) noktaları veriliyor. k > ${_m(yy)} olmak üzere ABC '
              'üçgeninin alanı ${tr(alan)} birimkare olduğuna göre k kaçtır?',
          yy + h,
          [yy + 2 * h, h, yy - h],
          '[AB] kenarı yatay olup uzunluğu $w birimdir. C noktasının AB '
              'doğrusuna uzaklığı k − ${_pz(yy)} olur: $w·(k − ${_pz(yy)}) / 2 = '
              '${tr(alan)}, k − ${_pz(yy)} = $h ve k = ${_m(yy + h)}.',
        );
      }
      final xx = b % 10 - 5, yc = x1 + a % 3;
      return _tam(
        'Analitik düzlemde A${_n(xx, x1)}, B${_n(xx, x1 + w)} ve '
            'C(k, ${_m(yc)}) noktaları veriliyor. k > ${_m(xx)} olmak üzere ABC '
            'üçgeninin alanı ${tr(alan)} birimkare olduğuna göre k kaçtır?',
        xx + h,
        [xx + 2 * h, h, xx - h],
        '[AB] kenarı düşey olup uzunluğu $w birimdir. C noktasının AB '
            'doğrusuna uzaklığı k − ${_pz(xx)} olur: $w·(k − ${_pz(xx)}) / 2 = '
            '${tr(alan)}, k − ${_pz(xx)} = $h ve k = ${_m(xx + h)}.',
      );
    },
    exam: ExamKind.ayt,
    lesson: _aytMat,
  ),
  // 18 · Noktanın doğruya ve noktaya göre simetriği.
  lmAile(
    'gm_nokta_simetri',
    'Noktanın bir doğruya ve bir noktaya göre simetriği',
    _mat,
    Difficulty.medium,
    BloomLevel.anlama,
    (a, b, c) {
      final x = a - 12, y = b - 9;
      String giris(String eksen) =>
          'Analitik düzlemde A${_n(x, y)} noktasının $eksen göre simetriği '
          'olan noktanın koordinatları hangisidir?';
      switch (c) {
        case 0:
          var k = (a + 2 * b) % 9 - 4;
          if (k == x) k += 9;
          return _noktali(
            giris('x = ${_m(k)} doğrusuna'),
            (2 * k - x, y),
            [(2 * k + x, y), (x - 2 * k, y), (x, 2 * k - y), (k - x, y)],
            'x = ${_m(k)} doğrusuna göre simetride ordinat değişmez; apsis '
            '${_m(k)} değerine göre yansır: 2·${_pz(k)} − ${_pz(x)} = '
            '${_m(2 * k - x)}. Simetrik nokta ${_n(2 * k - x, y)} olur.',
          );
        case 1:
          var k = (2 * a + b) % 9 - 4;
          if (k == y) k += 9;
          return _noktali(
            giris('y = ${_m(k)} doğrusuna'),
            (x, 2 * k - y),
            [(x, 2 * k + y), (x, y - 2 * k), (2 * k - x, y), (x, k - y)],
            'y = ${_m(k)} doğrusuna göre simetride apsis değişmez; ordinat '
            '${_m(k)} değerine göre yansır: 2·${_pz(k)} − ${_pz(y)} = '
            '${_m(2 * k - y)}. Simetrik nokta ${_n(x, 2 * k - y)} olur.',
          );
        case 2 || 3:
          // c = 2 pozitif, c = 3 negatif c değerleri kullanır; kökler çakışmaz.
          var k = c == 2 ? 1 + (a + b) % 6 : -(1 + (a + 2 * b) % 6);
          if (y == x + k) k += k > 0 ? 1 : -1;
          final dogru = 'y = ${_ifade([(1, 'x'), (k, '')])} doğrusuna';
          return _noktali(
            giris(dogru),
            (y - k, x + k),
            [(y + k, x - k), (y, x), (x - k, y + k), (-y + k, -x - k)],
            'y = x + c doğrusuna göre simetride (x, y) noktası (y − c, x + c) '
            'noktasına gider. c = ${_m(k)} için (${_m(y)} − ${_pz(k)}, '
            '${_m(x)} + ${_pz(k)}) = ${_n(y - k, x + k)}.',
          );
        case 4 || 5:
          // c = 4 negatif olmayan, c = 5 negatif c değerleri kullanır.
          var k = c == 4 ? (2 * a + b) % 6 : -(1 + (a + 3 * b) % 6);
          if (x + y == k) k += k >= 0 ? 1 : -1;
          final dogru = 'y = ${_ifade([(-1, 'x'), (k, '')])} doğrusuna';
          return _noktali(
            giris(dogru),
            (k - y, k - x),
            [(-y, -x), (k + y, k + x), (y - k, x - k), (k - x, k - y)],
            'y = −x + c doğrusuna göre simetride (x, y) noktası (c − y, c − x) '
            'noktasına gider. c = ${_m(k)} için (${_m(k)} − ${_pz(y)}, '
            '${_m(k)} − ${_pz(x)}) = ${_n(k - y, k - x)}.',
          );
        case 6 || 7:
          var p = (a + b) % 9 - 4;
          final q = c == 6 ? (a + 2 * b) % 4 : -1 - (2 * a + b) % 4;
          if (p == x && q == y) p += 1;
          return _noktali(
            giris('M${_n(p, q)} noktasına'),
            (2 * p - x, 2 * q - y),
            [
              (2 * p + x, 2 * q + y),
              (p - x, q - y),
              (x - 2 * p, y - 2 * q),
              (2 * q - x, 2 * p - y),
            ],
            'M noktası A ile simetriğinin orta noktasıdır: (2·${_pz(p)} − '
            '${_pz(x)}, 2·${_pz(q)} − ${_pz(y)}) = '
            '${_n(2 * p - x, 2 * q - y)}.',
          );
        case 8:
          final k = (a + 3 * b) % 13 - 6;
          var x2 = 2 * k - x;
          final yy = y;
          if (x2 == x) x2 = x + 2 * (b % 3 + 1);
          final kk = (x + x2) ~/ 2;
          return _tam(
            'Analitik düzlemde A${_n(x, yy)} ve B${_n(x2, yy)} noktaları x = k '
                'doğrusuna göre birbirinin simetriği olduğuna göre k kaçtır?',
            kk,
            [(x2 - x) ~/ 2, x + x2, (x - x2) ~/ 2],
            'Simetri doğrusu [AB] doğru parçasının orta noktasından geçer: '
                'k = (${_m(x)} + ${_pz(x2)}) / 2 = ${_m(kk)}.',
          );
        default:
          final k = (a + b) % 7 - 3, m = (2 * a + 3 * b) % 7 - 3;
          final ilk = (2 * k - x, y), son = (2 * k - x, 2 * m - y);
          return _noktali(
            'Analitik düzlemde A${_n(x, y)} noktasının önce x = ${_m(k)} '
                'doğrusuna göre simetriği alınıyor, ardından elde edilen noktanın '
                'y = ${_m(m)} doğrusuna göre simetriği alınıyor. Son durumda elde '
                'edilen noktanın koordinatları hangisidir?',
            son,
            [
              ilk,
              (x, 2 * m - y),
              (2 * m - x, 2 * k - y),
              (2 * k + x, 2 * m + y),
            ],
            'x = ${_m(k)} doğrusuna göre simetri ${_n(ilk.$1, ilk.$2)} '
                'noktasını, bu noktanın y = ${_m(m)} doğrusuna göre simetriği '
                '${_n(son.$1, son.$2)} noktasını verir.',
          );
      }
    },
    exam: ExamKind.ayt,
    lesson: _aytMat,
    shortAnswer: false,
  ),
  // 19 · Analitik düzlemde çember ile doğru; dış noktadan teğet.
  lmAile(
    'gm_cember_dogru',
    'Çember ile doğrunun durumu ve teğet uzunluğu',
    _mat,
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) {
      final h = a - 12, k = b - 10;
      if (c <= 2) {
        final r = 2 + (a + b) % 7;
        final (pa, pb, nn) = _normaller[(c + a) % 6];
        final tur = (a + 2 * b + c) % 3, isaret = b.isEven ? 1 : -1;
        final t = switch (tur) {
          0 => r * nn - 1 - (a + b) % (r * nn - 1),
          1 => r * nn,
          _ => r * nn + 1 + (a + b) % 7,
        };
        final cc = isaret * t - (pa * h + pb * k);
        final d = kesir(t, nn);
        final karsilastir = ['<', '=', '>'][tur];
        return secenekli(
          'Analitik düzlemde ${_cember(h, k, r * r)} çemberi ile '
              '${_dnk(pa, pb, cc)} doğrusunun birbirine göre durumu hangisidir?',
          _dogruKonum[tur],
          [
            for (var j = 0; j < 4; j++)
              if (j != tur) _dogruKonum[j],
          ],
          'Merkez M${_n(h, k)}, yarıçap $r birimdir. Merkezin doğruya '
              'uzaklığı |$pa·${_pz(h)} + ${_pz(pb)}·${_pz(k)} + ${_pz(cc)}| / '
              '√(${pa * pa} + ${pb * pb}) = $t / $nn${d == '$t/$nn' ? '' : ' = $d'} '
              'olur. Bu uzaklık $karsilastir r = $r olduğundan '
              '${const ['doğru çemberi iki noktada keser', 'doğru çembere teğettir', 'doğru çemberi kesmez'][tur]}.',
        );
      }
      if (c <= 4) {
        final (l1, l2, w) = _yonluUclu(a);
        final s = 1 + b % 4, yon = b ~/ 4;
        final r = s * l1, uz = s * l2, d = s * w;
        final (dx, dy) = switch (yon) {
          0 => (d, 0),
          1 => (0, -d),
          2 => (-s * l1, s * l2),
          3 => (s * l2, s * l1),
          _ => (-d, 0),
        };
        final mx = (a + b) % 7 - 3, my = (a + 2 * b) % 5 - 2;
        final px = mx + dx, py = my + dy;
        final String denklem;
        if (c == 3) {
          denklem = _cember(mx, my, r * r);
        } else {
          denklem =
              '${_ifade([(1, 'x²'), (1, 'y²'), (-2 * mx, 'x'), (-2 * my, 'y'), (mx * mx + my * my - r * r, '')])} = 0';
        }
        return sayisal(
          'Analitik düzlemde $denklem çemberine, dışındaki P${_n(px, py)} '
              'noktasından çizilen teğet çembere T noktasında değiyor. Buna göre '
              '|PT| kaç birimdir?',
          uz,
          [d, d - r, uz * uz, r + uz],
          '${c == 4 ? 'Denklem tam kareye tamamlanırsa ${_cember(mx, my, r * r)} olur. ' : ''}'
              'Merkez M${_n(mx, my)}, yarıçap $r birimdir. |PM|² = ${_pz(dx)}² + '
              '${_pz(dy)}² = ${d * d}. Teğet yarıçapa dik olduğundan |PT|² = '
              '${d * d} − ${r * r} = ${uz * uz} ve |PT| = $uz birim.',
          positive: true,
        );
      }
      if (c <= 6) {
        final r = 1 + (a + b) % 6;
        final (pa, pb, nn) = _normaller[(a + 2 * b) % 6];
        final e = pa * h + pb * k;
        final dogru = '${_ifade([(pa, 'x'), (pb, 'y')])} + n = 0';
        final kural =
            'Doğru çembere teğet ise merkezin doğruya uzaklığı yarıçapa '
            'eşittir: |$pa·${_pz(h)} + ${_pz(pb)}·${_pz(k)} + n| / $nn = $r, '
            'yani |${_m(e)} + n| = ${r * nn}. Buradan n = ${_m(-e + r * nn)} '
            'ya da n = ${_m(-e - r * nn)} bulunur.';
        final veri =
            'Analitik düzlemde $dogru doğrusu ${_cember(h, k, r * r)} çemberine '
            'teğet olduğuna göre';
        if (c == 5) {
          return _tam(
            '$veri n sayısının alabileceği değerlerin toplamı kaçtır?',
            -2 * e,
            [2 * e, -e, 2 * r * nn],
            '$kural Toplam ${_m(-2 * e)}.',
          );
        }
        final carpim = e * e - r * r * nn * nn;
        return _tam(
          '$veri n sayısının alabileceği değerlerin çarpımı kaçtır?',
          carpim,
          [e * e + r * r * nn * nn, -carpim, e * e - r * r],
          '$kural Çarpım (${_m(-e + r * nn)})·(${_m(-e - r * nn)}) = '
              '${_m(carpim)}.',
        );
      }
      if (c == 7) {
        // x² + y² = R ve y = mx + n: iki noktada kesişme n² < R(1 + m²).
        final m = const [1, -1, 2, -2, 3][a % 5], oran = 1 + m * m;
        final R = 2 + b + 20 * (a ~/ 5), sinir = R * oran;
        var e = 0;
        while ((e + 1) * (e + 1) < sinir) {
          e++;
        }
        final adet = 2 * e + 1;
        return sayisal(
          'Analitik düzlemde y = ${_ifade([(m, 'x')])} + n doğrusu x² + y² = '
              '$R çemberini iki farklı noktada kestiğine göre n sayısının '
              'alabileceği kaç farklı tam sayı değeri vardır?',
          adet,
          [2 * e + 3, e, 2 * e],
          'Doğru denklemi çemberde yerine yazılırsa '
              '${_ifade([(oran, 'x²'), (2 * m, 'nx')])} + n² − $R = 0 olur. İki '
              'noktada kesişme için diskriminant pozitif olmalıdır: n² < $R·$oran '
              '= $sinir. Bu koşulu sağlayan tam sayılar −$e ile $e arasındaki '
              '(uçlar dâhil) $adet sayıdır.',
          positive: true,
        );
      }
      if (c == 8) {
        final m = const [1, -1, 2, -2, 3, -3][(a + b) % 6], oran = 1 + m * m;
        final j = 1 + (a + 2 * b) % 4, sabit = k - m * h;
        final n1 = sabit + j * oran, n2 = sabit - j * oran;
        return _tam(
          'Analitik düzlemde y = ${_ifade([(m, 'x')])} + n doğrusu '
              '${_cember(h, k, j * j * oran)} çemberine teğet olduğuna göre n '
              'sayısının alabileceği değerlerden büyük olanı kaçtır?',
          n1,
          [n2, sabit, -n1],
          'Merkez M${_n(h, k)}, yarıçap √${j * j * oran} = ${_kok(j, oran)} '
              'birimdir. Merkezin ${_ifade([(m, 'x')])} − y + n = 0 doğrusuna '
              'uzaklığı |${_m(m)}·${_pz(h)} − ${_pz(k)} + n| / √$oran olur. Bu '
              'uzaklık yarıçapa eşitlenirse |n − ${_pz(sabit)}| = ${j * oran}, n = '
              '${_m(n1)} ya da n = ${_m(n2)} bulunur; büyük olanı ${_m(n1)}.',
        );
      }
      final r = 2 + (a + b) % 7;
      final (pa, pb, nn) = _normaller[(a + b) % 6];
      final fark = 1 + (a + 2 * b) % 9, isaret = a.isEven ? 1 : -1;
      final t = (r + fark) * nn, cc = isaret * t - (pa * h + pb * k);
      return sayisal(
        'Analitik düzlemde ${_cember(h, k, r * r)} çemberi ile '
            '${_dnk(pa, pb, cc)} doğrusu kesişmiyor. Çember üzerindeki noktaların '
            'bu doğruya olan uzaklıklarının en küçüğü kaç birimdir?',
        fark,
        [r + fark, 2 * r + fark, r],
        'Merkez M${_n(h, k)}, yarıçap $r birimdir. Merkezin doğruya uzaklığı '
            '|$pa·${_pz(h)} + ${_pz(pb)}·${_pz(k)} + ${_pz(cc)}| / $nn = $t / $nn '
            '= ${r + fark} birim olur. En yakın nokta merkezle doğru arasındadır: '
            '${r + fark} − $r = $fark birim.',
        positive: true,
      );
    },
    exam: ExamKind.ayt,
    lesson: _aytMat,
    shortAnswer: false,
  ),
  // 20 · Analitik düzlemde döndürme ve öteleme ile birleşik dönüşümler.
  lmAile(
    'gm_dondurme',
    'Analitik düzlemde döndürme ve öteleme',
    _mat,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final x = _sifirsiz(a - 12, 13), y = _sifirsiz(b - 9, 11);
      const pozitif = 'pozitif yönde (saatin dönme yönünün tersine)';
      final hepsi = [
        for (var n = 1; n <= 3; n++) _dondur(n, (x, y)),
        (-x, y),
        (x, -y),
        (y, x),
      ];
      List<(int, int)> digerleri((int, int) d) => [
        for (final p in hepsi)
          if (p != d) p,
      ];
      final p = 1 + (a + 2 * b) % 6, q = (2 * a + b) % 7 - 3;
      final oteleme = 'u = ${_n(p, q)} vektörü kadar';
      switch (c) {
        case 0 || 1 || 2 || 3:
          final n = c == 3 ? 3 : c + 1;
          final aci = c == 3 ? 'saat yönünde 90°' : '$pozitif ${90 * n}°';
          final d = _dondur(n, (x, y));
          const kural = [
            '',
            'Orijin etrafında pozitif yönde 90° döndürme (x, y) noktasını '
                '(−y, x) noktasına götürür',
            'Orijin etrafında 180° döndürme (x, y) noktasını (−x, −y) '
                'noktasına götürür',
            'Orijin etrafında pozitif yönde 270° döndürme, yani saat yönünde '
                '90° döndürme (x, y) noktasını (y, −x) noktasına götürür',
          ];
          return _noktali(
            'Analitik düzlemde A${_n(x, y)} noktası orijin etrafında $aci '
                'döndürülüyor. Elde edilen noktanın koordinatları hangisidir?',
            d,
            digerleri(d),
            '${kural[n]}: ${_n(d.$1, d.$2)}.',
          );
        case 4 || 6:
          final n = c == 4 ? 1 : 3;
          final r = _dondur(n, (x, y)), d = (r.$1 + p, r.$2 + q);
          return _noktali(
            'Analitik düzlemde A${_n(x, y)} noktası önce orijin etrafında '
                '$pozitif ${90 * n}° döndürülüyor, sonra elde edilen nokta '
                '$oteleme öteleniyor. Son durumda elde edilen noktanın '
                'koordinatları hangisidir?',
            d,
            [
              r,
              _dondur(n, (x + p, y + q)),
              (_dondur(4 - n, (x, y)).$1 + p, _dondur(4 - n, (x, y)).$2 + q),
              (r.$1 - p, r.$2 - q),
            ],
            'Döndürme sonrası nokta ${_n(r.$1, r.$2)} olur. Öteleme ile '
                '(${_m(r.$1)} + ${_pz(p)}, ${_m(r.$2)} + ${_pz(q)}) = '
                '${_n(d.$1, d.$2)} bulunur.',
          );
        case 5:
          final o = (x + p, y + q), d = (-o.$1, -o.$2);
          return _noktali(
            'Analitik düzlemde A${_n(x, y)} noktası önce $oteleme öteleniyor, '
                'sonra elde edilen nokta orijin etrafında 180° döndürülüyor. Son '
                'durumda elde edilen noktanın koordinatları hangisidir?',
            d,
            [o, (-x + p, -y + q), (-x - p, y + q), (o.$1, -o.$2)],
            'Öteleme sonrası nokta ${_n(o.$1, o.$2)} olur. 180° döndürme '
                'koordinatların işaretini değiştirir: ${_n(d.$1, d.$2)}.',
          );
        case 7:
          final mx = (a + b) % 7 - 3;
          var my = (a + 3 * b) % 7 - 3;
          if (mx == x && my == y) my++;
          final g = (x - mx, y - my), r = _dondur(1, g);
          final d = (mx + r.$1, my + r.$2);
          return _noktali(
            'Analitik düzlemde A${_n(x, y)} noktası M${_n(mx, my)} noktası '
                'etrafında $pozitif 90° döndürülüyor. Elde edilen noktanın '
                'koordinatları hangisidir?',
            d,
            [
              _dondur(1, (x, y)),
              (mx - r.$1, my - r.$2),
              (mx + r.$2, my - r.$1),
            ],
            'M noktası orijine ötelenirse A noktası ${_n(g.$1, g.$2)} olur. '
                'Orijin etrafında 90° döndürme bunu ${_n(r.$1, r.$2)} yapar. Geri '
                'öteleme ile (${_m(r.$1)} + ${_pz(mx)}, ${_m(r.$2)} + ${_pz(my)}) '
                '= ${_n(d.$1, d.$2)} bulunur.',
          );
        case 8:
          final n = 1 + (a + b) % 3, goruntu = _dondur(n, (x, y));
          return _noktali(
            'Analitik düzlemde bir A noktası orijin etrafında $pozitif '
                '${90 * n}° döndürüldüğünde A′${_n(goruntu.$1, goruntu.$2)} '
                'noktası elde ediliyor. Buna göre A noktasının koordinatları '
                'hangisidir?',
            (x, y),
            [
              _dondur(n, goruntu),
              (-goruntu.$1, goruntu.$2),
              (goruntu.$2, goruntu.$1),
            ],
            'A noktası, A′ noktasının ters yönde ${90 * n}° döndürülmesiyle '
                'bulunur: ${_n(x, y)}.',
          );
        default:
          final n = 1 + (a + 2 * b) % 3, goruntu = _dondur(n, (x, y));
          return secenekli(
            'Analitik düzlemde A${_n(x, y)} noktası orijin etrafında $pozitif '
                'en az kaç derece döndürülürse B${_n(goruntu.$1, goruntu.$2)} '
                'noktası elde edilir?',
            '${90 * n}°',
            [
              for (final v in [90, 180, 270, 360])
                if (v != 90 * n) '$v°',
            ],
            'Pozitif yönde 90° döndürme (x, y) → (−y, x), 180° döndürme '
                '(x, y) → (−x, −y), 270° döndürme (x, y) → (y, −x) verir. '
                'B${_n(goruntu.$1, goruntu.$2)} noktası ${90 * n}° döndürmeyle elde '
                'edilir.',
          );
      }
    },
    exam: ExamKind.ayt,
    lesson: _aytMat,
    shortAnswer: false,
  ),
];
