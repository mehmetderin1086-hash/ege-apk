// Lise geometri ve analitik geometri metin aileleri: üçgen, çokgen, çember,
// katı cisimler, analitik düzlem ve dönüşümler. Her aile 5.000 ayrı vaka
// üretir; şekiller tümüyle sözle betimlenir.
import 'dart:math';

import 'denge.dart';
import 'ortak.dart';

const _mat = Topic.mathematics;
const _tm = 'Temel Matematik';
const _aytMat = 'Matematik';

/// (a, b, c) vakasının çeldirici seçim kodu: `% 4` hedef sıradır
/// (anahtardan küçük çeldirici sayısı, bkz. hedefSira), `~/ 4` ise hedef
/// sıra kurulamadığında kullanılan ikinci, bağımsız seçimdir (0 … 15).
int _hs(int a, int b, int c) {
  final i = a + 25 * b + 500 * c;
  return hedefSira(i) + 4 * (4 * hedefSira(i, 11) + hedefSira(i, 12));
}

/// Sayısal çeldirici seçimi. [hatalar] öncelik sırasıyla tipik hata
/// değerleri, [komsular] yalnız son çare olan komşu değerlerdir; ikisi de
/// (değer, yazım) ikilisidir. Anahtardan küçük çeldirici sayısı [sira] % 4
/// olacak biçimde seçilir; ancak bir vakada en çok bir komşu değer
/// kullanılır (hatalar üçten azsa gereken kadar). Hedef sıra bu sınırla
/// kurulamıyorsa kurulabilen sıralardan biri [sira] ~/ 4 ile seçilir.
/// Böylece seçenekler anahtarın çevresine dizilmiş komşulardan oluşmaz.
/// [enCokAlt] verilirse anahtardan küçük çeldirici sayısı onu aşmaz.
List<String> _celdirici(
  num anahtar,
  String yazim,
  Iterable<(num, String)> hatalar,
  Iterable<(num, String)> komsular,
  int sira, {
  int enCokAlt = 3,
}) {
  // Bir çağrıdaki bütün adaylar aynı birim ve biçimdedir ve yazımları
  // değerlerinden türetilir; bu yüzden değeri aynı olan aday aynı seçenektir.
  final alinan = <num>{anahtar};
  List<(num, String)> ayikla(Iterable<(num, String)> xs) => [
    for (final x in xs)
      if (x.$2.trim().isNotEmpty && alinan.add(x.$1)) x,
  ];
  final h = ayikla(hatalar), k = ayikla(komsular);
  final hA = [
    for (final x in h)
      if (x.$1 < anahtar) x,
  ];
  final hU = [
    for (final x in h)
      if (x.$1 > anahtar) x,
  ];
  final kA = [
    for (final x in k)
      if (x.$1 < anahtar) x,
  ];
  final kU = [
    for (final x in k)
      if (x.$1 > anahtar) x,
  ];
  int eksik(int r) => max(0, r - hA.length) + max(0, 3 - r - hU.length);
  bool olur(int r) =>
      r <= enCokAlt &&
      r - hA.length <= kA.length &&
      3 - r - hU.length <= kU.length;
  final olasi = [
    for (var r = 0; r < 4; r++)
      if (olur(r)) r,
  ];
  if (olasi.isEmpty) {
    throw StateError('Eksik çeldirici: $yazim → $hatalar');
  }
  final enAz = olasi.map(eksik).reduce(min);
  final izin = [
    for (final r in olasi)
      if (eksik(r) <= max(1, enAz)) r,
  ];
  final hedef = sira % 4;
  final r = izin.contains(hedef) ? hedef : izin[sira ~/ 4 % izin.length];
  final alt = [...hA, ...kA].take(r).toList();
  final ust = [...hU, ...kU].take(3 - r).toList();
  // Anahtar iki çeldiricinin geometrik ortası olmasın (x/2 ile 2x gibi;
  // "yarısı ve iki katı seçeneklerde olan" ipucu). Böyle bir çiftin bir
  // öğesi aynı yandaki sıradaki adayla değiştirilir: önce tipik hatalar
  // (önce üstte, sonra altta), sonra komşular. Hedef sıra değişmez.
  final kare = anahtar * anahtar;
  bool orta(num p, num q) => (p * q - kare).abs() <= 1e-9 * kare;
  bool ciftVar() => alt.any((p) => ust.any((q) => orta(p.$1, q.$1)));
  bool degistir(
    List<(num, String)> secilen,
    List<(num, String)> karsi,
    List<(num, String)> adaylar,
  ) {
    final i = secilen.indexWhere((p) => karsi.any((q) => orta(p.$1, q.$1)));
    if (i < 0) return false;
    for (final x in adaylar) {
      if (secilen.contains(x) || karsi.any((q) => orta(x.$1, q.$1))) continue;
      secilen[i] = x;
      return true;
    }
    return false;
  }

  for (var tur = 0; tur < 3 && ciftVar(); tur++) {
    if (!(degistir(ust, alt, hU) ||
        degistir(alt, ust, hA) ||
        degistir(ust, alt, kU) ||
        degistir(alt, ust, kA))) {
      break;
    }
  }
  return [
    for (final x in [...alt, ...ust]) x.$2,
  ];
}

/// Komşu değerlerin anahtara uzaklığı (adım sayısı). Üstte ve altta farklı
/// sırayla gelir: iki yana birer komşu düşerse anahtar ikisinin ortası
/// olmaz, aynı yana iki komşu düşerse anahtarla eşit aralıklı dizi kurmaz.
const _ustKat = [1, 3, 4, 2, 6, 5], _altKat = [2, 3, 1, 5, 4, 6];

/// [anahtar] çevresindeki komşu değerler (adımı [adim]).
List<num> _komsu(num anahtar, num adim) => [
  for (var j = 0; j < 6; j++) ...[
    anahtar + _ustKat[j] * adim,
    anahtar - _altKat[j] * adim,
  ],
];

/// Tam sayı yanıtlı soru; çeldiriciler [_celdirici] ile seçilir. Komşu
/// değerler anahtarın büyüklüğüne göre 1, 5 ya da 10 adımlıdır. [alt] ve
/// [ust] verilirse çeldiriciler bu iki değerin (ikisi de hariç) arasında
/// kalır: kökün kendi verisiyle çelişen (küçük üçgenin alanının büyüğünkünü
/// aşması, parçanın bütünden uzun olması gibi) seçenek kurulmaz. Aralıkta
/// üç farklı değer kalmayan çok küçük vakalarda yalnız pozitiflik aranır.
AdvancedItem _sayi(
  String prompt,
  int dogru,
  Iterable<int> yanlis,
  String aciklama,
  int sira, {
  String unit = '',
  int alt = 0,
  int? ust,
}) {
  final adim = dogru.abs() >= 200 ? 10 : (dogru.abs() >= 40 ? 5 : 1);
  final yazim = birimli('$dogru', unit);
  final komsu = [for (final x in _komsu(dogru, adim)) x as int];
  // Uzunluk, alan, hacim ve sayım yanıtlarında yalnız pozitif değerler.
  bool aralikta(int x) => x > alt && (ust == null || x < ust);
  final yeter =
      {
        for (final x in [...yanlis, ...komsu])
          if (x != dogru && aralikta(x)) x,
      }.length >=
      3;
  bool gecer(int x) => yeter ? aralikta(x) : x > 0;
  return AdvancedItem(
    prompt,
    yazim,
    _celdirici(
      dogru,
      yazim,
      [
        for (final x in yanlis)
          if (gecer(x)) (x, birimli('$x', unit)),
      ],
      [
        for (final x in komsu)
          if (gecer(x)) (x, birimli('$x', unit)),
      ],
      sira,
    ),
    aciklama,
  );
}

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

/// Derece yanıtlı soru; çeldiriciler [_celdirici] ile seçilir: [yanlis]
/// iki yandaki tipik hata değerleridir, son çare olarak 5°'nin katı olan
/// komşular kullanılır. Bütün seçenekler 0° ile [ust] arasında kalır.
AdvancedItem _aci(
  String prompt,
  int dogru,
  List<int> yanlis,
  String aciklama,
  int sira, {
  int ust = 180,
}) {
  bool gecer(int x) => x > 0 && x < ust;
  return AdvancedItem(
    prompt,
    '$dogru°',
    _celdirici(
      dogru,
      '$dogru°',
      [
        for (final x in yanlis)
          if (gecer(x)) (x, '$x°'),
      ],
      [
        for (final x in _komsu(dogru, 5))
          if (gecer(x as int)) (x, '$x°'),
      ],
      sira,
    ),
    aciklama,
  );
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
  [...yanlis, dogru + 1, dogru - 1, dogru + 2, dogru - 2, dogru + 3].map(_m),
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
      final j = c ~/ 3, sira = _hs(a, b, c);
      if (c % 3 == 0) {
        final al = 25 + 2 * a, be = 15 + 4 * b + j, d = al + be;
        return _aci(
          'ABC üçgeninde A köşesindeki iç açının ölçüsü $al°, C köşesindeki '
          'dış açının ölçüsü $d° olarak veriliyor. Buna göre B köşesindeki iç '
          'açının ölçüsü kaç derecedir?',
          be,
          // C iç açısını bulma, dış açıyı iç açı sanma, B'nin dış açısını
          // verme, çıkarmak yerine toplama, A'nın dış açısını verme, A'nın
          // iç açısı yerine dış açısını çıkarma, üçgeni A = B ikizkenarı
          // sanma. (B = C sanmak (180° − A) / 2 verir; A hep tek olduğundan
          // bu değer tam sayı olmaz ve eklenmez.)
          [
            180 - d,
            180 - al - d,
            180 - be,
            d + al,
            180 - al,
            d - (180 - al),
            if (d.isEven) d ~/ 2,
          ],
          'Bir dış açının ölçüsü, kendisine komşu olmayan iki iç açının '
              'ölçüleri toplamına eşittir: $al° + B = $d°, B = $d° − $al° = $be°.',
          sira,
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
          // ADB açısını verme, A'yı ikiye bölmeme, toplamak yerine çıkarma,
          // C açısını verme, yarım açıyı yanıt sanma, B'nin dış açısı.
          [180 - be - y, al + be, be - y, ga, y, 180 - be],
          'Açıortay A açısını $y° ölçülü iki açıya ayırır. ADC açısı ABD '
              'üçgeninin D köşesindeki dış açısıdır: B + BAD = $be° + $y° = '
              '${be + y}°.',
          sira,
        );
      }
      final p = 20 + 3 * a, q = 15 + b + 20 * j;
      final x = 180 - p, y = 180 - q, g = 180 - p - q;
      return _aci(
        'Bir ABC üçgeninde A köşesindeki dış açının ölçüsü $x°, B köşesindeki '
        'dış açının ölçüsü $y° olarak veriliyor. Buna göre C köşesindeki iç '
        'açının ölçüsü kaç derecedir?',
        g,
        // C'nin dış açısını verme, dış açıları çıkarma, iç açıları çıkarma,
        // ara sonuç olan A ya da B iç açısını yanıt sanma, A'daki dış açıyı
        // yanıt sanma.
        [p + q, (p - q).abs(), 180 - (p - q).abs(), p, q, x],
        'A ve B köşelerindeki iç açılar 180° − $x° = $p° ve 180° − $y° = $q° '
            'olur. C = 180° − ($p° + $q°) = $g°.',
        sira,
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
      final j = c ~/ 2, sira = _hs(a, b, c);
      if (c.isOdd) {
        final x = 6 + a, r = 1 + b % 5, p = 2 + b ~/ 5, s = 2 + j;
        final q = (p - 1) * x - r, kol = x + r, tab = 2 * x - s;
        return _sayi(
          'ABC üçgeninde |AB| = |AC| olmak üzere |AB| = (${p}x − $q) cm, '
          '|AC| = (x + $r) cm ve |BC| = (2x − $s) cm olarak veriliyor. Buna '
          'göre ABC üçgeninin çevresi kaç cm olur?',
          2 * kol + tab,
          // Tabanı iki kez, bacağı bir kez alma; tabanı ya da bir bacağı
          // unutma; tabanı kenar alıp eşkenar sanma; x değerini yanıt sanma.
          // (3·bacak ile 2·(bacak + taban) eklenmez: ikisi de başka bir
          // çeldiriciyle anahtarın tam iki yanında kalırdı.)
          [kol + 2 * tab, 2 * kol, kol + tab, 3 * tab, x],
          'Eş kenarlar eşitlenir: ${p}x − $q = x + $r, buradan x = $x bulunur. '
              '|AB| = |AC| = $kol cm ve |BC| = $tab cm olduğundan çevre '
              '2·$kol + $tab = ${2 * kol + tab} cm olur.',
          sira,
          unit: 'cm',
        );
      }
      if (j == 4) {
        final x = 10 + 2 * a, y = 8 + 2 * b;
        return _aci(
          'ABC eşkenar üçgeninde D noktası [BC] kenarı, E noktası [AC] kenarı '
          'üzerindedir. BAD açısının ölçüsü $x°, CDE açısının ölçüsü $y° '
          'olduğuna göre ADE açısının ölçüsü kaç derecedir?',
          60 + x - y,
          // y'yi çıkarmama, ADB'yi verme, toplama, işaretleri karıştırma,
          // DEC açısını ya da ADE'nin bütünlerini verme.
          [
            60 + x,
            60 + y - x,
            120 - x,
            60 + x + y,
            120 - x - y,
            120 - y,
            120 - x + y,
          ],
          'Eşkenar üçgende her açı 60° olduğundan ABD üçgeninde ADB = 180° − '
              '60° − $x° = ${120 - x}° olur. ADE = 180° − ${120 - x}° − $y° = '
              '${60 + x - y}°.',
          sira,
        );
      }
      final al = 20 + 2 * a, be = 80 - a, t = 8 + 2 * b;
      final verilen = j == 3 ? 'ACD' : 'BCD';
      final (sorulan, yanit, yanlis, cozum) = switch (j) {
        0 => (
          'ADC',
          be + t,
          // BDC'yi verme, toplamak yerine çıkarma, B yerine A'yı alma,
          // BCD'yi ACD sanma, taban açısını yanıt sanma.
          [180 - be - t, be - t, al + t, 2 * be - t, be],
          'ADC açısı DBC üçgeninin D köşesindeki dış açısıdır: B + BCD = '
              '$be° + $t° = ${be + t}°.',
        ),
        1 => (
          'ACD',
          be - t,
          // Toplama, BDC'yi verme, çıkarmayı unutma, C yerine A'yı alma.
          [be + t, 180 - be - t, be, al - t, 2 * be - t],
          'ACD = ACB − BCD = $be° − $t° = ${be - t}°.',
        ),
        2 => (
          'BDC',
          180 - be - t,
          // ADC'yi verme, çıkarma, B yerine A'yı alma, taban açısı.
          [be + t, be - t, 180 - al - t, al + t, be],
          'DBC üçgeninde BDC = 180° − $be° − $t° = ${180 - be - t}°.',
        ),
        _ => (
          'BDC',
          al + t,
          // ADC'yi verme, A yerine B'yi alma, BCD'yi verme, t'yi unutma.
          [180 - al - t, be + t, be - t, al, 180 - be - t],
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
        sira,
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
        return _sayi(
          '$kim önce doğuya $x1 $br, sonra kuzeye $dy $br, ardından yine '
          'doğuya $x2 $br $fiil. Son durumda başlangıç noktasına olan kuş '
          'uçuşu uzaklığı kaç $br olur?',
          h,
          // Yolları toplama ya da çıkarma, uzun dik kenarı yanıt sanma;
          // üçlünün katını bir eksik ya da fazla alma.
          [
            dx + dy,
            (dx - dy).abs(),
            dx > dy ? dx : dy,
            u.$3 * (s + 1),
            u.$3 * (s - 1),
          ],
          'Doğu yönünde toplam $x1 + $x2 = $dx $br, kuzey yönünde $dy $br yol '
              'alınmıştır. Uzaklık √($dx² + $dy²) = √${dx * dx + dy * dy} = $h $br '
              'olur (${u.$1}-${u.$2}-${u.$3} üçgeninin $s katı).',
          _hs(a, b, c),
          unit: br,
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
      // Üçüncü çeldirici: yanıt köklüyse öteki Öklid bağıntısı ya da
      // Pisagor'u yanlış dik kenarla kurma (köklü, hipotenüsten kısa). Yanıt
      // tam sayıysa (kök içi tam kare) seçeneklerde yalnız o tam sayı
      // kalmasın diye tam sayı bir hata: geometrik ortalama yerine aritmetik
      // ortalama, o da tam sayı değilse iki parçanın farkı. ("Karekökü
      // almayı unutma" eklenmez: hipotenüsten kat kat uzun bir dik kenar
      // ya da yükseklik verirdi.)
      bool tamKare(int x) {
        for (var y = 1; y * y <= x; y++) {
          if (y * y == x) return true;
        }
        return false;
      }

      (int, int) tamHata(int u, int v, int fark) =>
          (u + v).isEven ? ((u + v) ~/ 2, 1) : (fark, 1);
      if (j == 0 || j == 3) {
        return _koklu(
          '$giris $veri olduğuna göre |AH| kaç cm olur?',
          (g, s * t),
          [
            tamKare(s * t) ? tamHata(p, q, (q - p).abs()) : (g, t * (s + t)),
            (g, s * s + t * t),
            (g, s * (s + t)),
          ],
          '${j == 3 ? '|HC| = $hip − $p = $q cm olur. ' : ''}Öklid bağıntısına '
          'göre |AH|² = |BH|·|HC| = $p·$q = ${p * q}, buradan |AH| = '
          '${_kok(g, s * t)} cm bulunur.',
        );
      }
      if (j == 2) {
        return _koklu(
          '$giris $veri olduğuna göre |AC| kaç cm olur?',
          (g, t * (s + t)),
          [
            (g, s * t),
            tamKare(t * (s + t)) ? tamHata(q, hip, p) : (g, t * (2 * s + t)),
            (g, s * (s + t)),
          ],
          '|BC| = $p + $q = $hip cm olur. Öklid bağıntısına göre |AC|² = '
          '|HC|·|BC| = $q·$hip = ${q * hip}, buradan |AC| = '
          '${_kok(g, t * (s + t))} cm bulunur.',
        );
      }
      return _koklu(
        '$giris $veri olduğuna göre |AB| kaç cm olur?',
        (g, s * (s + t)),
        [
          (g, s * t),
          tamKare(s * (s + t)) ? tamHata(p, hip, q) : (g, s * (s + 2 * t)),
          (g, t * (s + t)),
        ],
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
        return _sayi(
          'ABC üçgeninde |BC| = $t cm ve [BC] kenarına ait yükseklik $r cm '
          'olarak veriliyor. |AC| = $u cm olduğuna göre [AC] kenarına ait '
          'yükseklik kaç cm olur?',
          q,
          // Tek tarafta ikiye bölmeyi unutma (iki yönde), çarpım yerine toplam
          // eşitliği kurma, yükseklikleri eşit sanma, oranı ters kurma, oranı
          // karesiyle uygulama, kenarlarla yükseklikleri çapraz çarpma.
          [
            2 * q,
            if (q.isEven) q ~/ 2,
            t + r - u,
            r,
            if (r * u % t == 0) r * u ~/ t,
            if (q * t % u == 0) q * t ~/ u,
            u - r,
            if (t * u % r == 0) t * u ~/ r,
          ],
          'Üçgenin alanı iki ayrı kenar ve o kenara ait yükseklik ile '
              'yazılır: $t·$r / 2 = $u·h / 2. Buradan h = ${t * r} / $u = $q cm '
              'bulunur.',
          _hs(a, b, c),
          unit: 'cm',
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
      // Seçenekler iki bağımsız hatanın dört birleşimidir: katsayıda 1/2'yi
      // unutma (2k) ya da ikiye iki kez bölme (k/2) ve sinüs yerine yanlış
      // özel değer (√3/2 ile √2/2 karışır, 1/2 yerine √3/2). Böylece hiçbir
      // seçenek ötekilere anahtardan daha çok benzemez.
      final i = a + 25 * b + 500 * c;
      final k2 = k.isEven && hedefSira(i, 7) < 2 ? k ~/ 2 : 2 * k;
      final yanlisKok = kokIci == 3 ? 2 : 3;
      return AdvancedItem(
        'ABC üçgeninde |AB| = ${2 * x} cm, |AC| = ${2 * y} cm ve bu iki '
            'kenarın oluşturduğu A açısının ölçüsü $th° olduğuna göre ABC '
            'üçgeninin alanı kaç cm² olur?',
        _kok(k, kokIci),
        [_kok(k2, kokIci), _kok(k, yanlisKok), _kok(k2, yanlisKok)],
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
      final j = c ~/ 2, sira = _hs(a, b, c);
      final (m, n) = _oran[a];
      // p / q tam bölünüyorsa bölüm, değilse seçenek olarak elenen 0.
      int bol(int p, int q) => p % q == 0 ? p ~/ q : 0;
      if (c.isEven) {
        final s = 2 + b, w = 2 + j;
        final ad = m * s, db = (n - m) * s, de = m * w, bc = n * w;
        return _sayi(
          'ABC üçgeninde D noktası [AB] kenarı, E noktası [AC] kenarı üzerinde '
          'olup [DE] ∥ [BC] olarak veriliyor. |AD| = $ad cm, |DB| = $db cm ve '
          '|DE| = $de cm olduğuna göre |BC| kaç cm olur?',
          bc,
          // |AB| yerine |DB| ile orantı kurma (iki yönde), oranı ters kurma,
          // uzunlukları toplama, [DE]'yi orta taban sanma, |AB|'yi verme.
          [
            (n - m) * w,
            bol(de * n * s, db),
            bol(de * ad, n * s),
            de + db,
            2 * de,
            bol(de * ad, db),
            n * s,
          ],
          'ADE ve ABC üçgenleri benzerdir: |AD| / |AB| = |DE| / |BC|. |AB| = '
              '$ad + $db = ${n * s} cm olduğundan $ad / ${n * s} = $de / |BC|, '
              '|BC| = $de·${n * s} / $ad = $bc cm.',
          sira,
          unit: 'cm',
          // [DE] ∥ [BC] ve D, [AB] üzerinde olduğundan |BC| > |DE|.
          alt: de,
        );
      }
      final k = 1 + b, s1 = m * m * k, s2 = n * n * k;
      switch (j) {
        case 0:
          return _sayi(
            'Benzerlik oranı $m/$n olan iki benzer üçgenden küçüğünün alanı '
            '$s1 cm² olduğuna göre büyüğünün alanı kaç cm² olur?',
            s2,
            // Oranın karesini almama, paydayı ya da payı karelememe,
            // hacimdeki gibi küpünü alma.
            [
              m * n * k,
              m * n * n * k,
              m * m * n * k,
              m * m * n * n * k,
              bol(n * n * n * k, m),
            ],
            'Alanlar oranı benzerlik oranının karesidir: ($m/$n)² = '
                '${m * m}/${n * n}. Büyük alan $s1·${n * n} / ${m * m} = $s2 cm².',
            sira,
            unit: 'cm²',
            alt: s1,
          );
        case 1:
          return _sayi(
            'Benzerlik oranı $m/$n olan iki benzer üçgenden büyüğünün alanı '
            '$s2 cm² olduğuna göre küçüğünün alanı kaç cm² olur?',
            s1,
            // Oranın karesini almama, payı ya da paydayı karelememe, yalnız
            // n ile bölme, hacimdeki gibi küpünü alma.
            [
              m * n * k,
              m * k,
              m * m * n * k,
              n * k,
              m * m * n * n * k,
              bol(m * m * m * k, n),
            ],
            'Alanlar oranı benzerlik oranının karesidir: ($m/$n)² = '
                '${m * m}/${n * n}. Küçük alan $s2·${m * m} / ${n * n} = $s1 cm².',
            sira,
            unit: 'cm²',
            ust: s2,
          );
        case 2:
          final p1 = m * (k + 2), p2 = n * (k + 2);
          return _sayi(
            'Benzerlik oranı $m/$n olan iki benzer üçgenden küçüğünün çevresi '
            '$p1 cm olduğuna göre büyüğünün çevresi kaç cm olur?',
            p2,
            // Alandaki gibi oranın karesini alma, oranı fark olarak ekleme,
            // oranı ters kurma, farkı yanıt sanma, m ile bölmeyi unutma.
            [
              bol(n * n * (k + 2), m),
              p1 + n - m,
              bol(m * m * (k + 2), n),
              (n - m) * (k + 2),
              m * n * (k + 2),
              n * n * (k + 2),
            ],
            'Çevreler oranı benzerlik oranına eşittir: $p1 / Ç = $m/$n, '
                'Ç = $p1·$n / $m = $p2 cm.',
            sira,
            unit: 'cm',
            alt: p1,
          );
        case 3:
          final e1 = m * (k + 1), e2 = n * (k + 1);
          return _sayi(
            'Alanları $s1 cm² ve $s2 cm² olan benzer iki üçgenden küçüğünün '
            'bir kenarı $e1 cm olduğuna göre büyük üçgende bu kenara karşılık '
            'gelen kenar kaç cm olur?',
            e2,
            // Alan oranının karekökünü almama, alan farkını ekleme, oranı
            // ters kurma, oranı fark olarak ekleme, farkı yanıt sanma.
            [
              bol(n * n * (k + 1), m),
              e1 + (n * n - m * m) * k,
              bol(m * m * (k + 1), n),
              e1 + n - m,
              (n - m) * (k + 1),
              n * n * (k + 1),
            ],
            'Alanlar oranı $s1/$s2 = ${m * m}/${n * n} olduğundan benzerlik '
                'oranı $m/$n olur. Karşılık gelen kenar $e1·$n / $m = $e2 cm.',
            sira,
            unit: 'cm',
            alt: e1,
          );
        default:
          final e1 = m * (k + 1), e2 = n * (k + 1);
          return _sayi(
            'Benzer iki üçgenin karşılıklı iki kenarının uzunlukları $e1 cm ve '
            '$e2 cm olarak veriliyor. Küçük üçgenin alanı $s1 cm² olduğuna '
            'göre büyük üçgenin alanı kaç cm² olur?',
            s2,
            // Oranın karesini almama, paydayı karelememe, kenar farkını
            // ekleme, m² ile bölmeyi unutma, küpünü alma.
            [
              m * n * k,
              s1 * n,
              s1 + e2 - e1,
              m * n * n * k,
              m * m * n * n * k,
              bol(n * n * n * k, m),
            ],
            'Benzerlik oranı $e1/$e2 = $m/$n, alanlar oranı bunun karesi olan '
                '${m * m}/${n * n} olur. Büyük alan $s1·${n * n} / ${m * m} = '
                '$s2 cm².',
            sira,
            unit: 'cm²',
            alt: s1,
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
      final j = c ~/ 3, sira = _hs(a, b, c);
      // p / q tam bölünüyorsa bölüm, değilse seçenek olarak elenen 0.
      int bol(int p, int q) => p % q == 0 ? p ~/ q : 0;
      if (c % 3 == 0) {
        final u = _aciortayOran[a ~/ 2];
        final m = a.isEven ? u.$1 : u.$2, n = a.isEven ? u.$2 : u.$1;
        final w = 2 + b ~/ 2, s = w + 1 + j;
        final ab = m * s, ac = n * s, bd = m * w, dc = n * w, bc = bd + dc;
        const giris =
            'ABC üçgeninde A açısının iç açıortayı [BC] kenarını D noktasında '
            'kesiyor.';
        if (b.isEven) {
          return _sayi(
            '$giris |AB| = $ab cm, |AC| = $ac cm ve |BD| = $bd cm olduğuna '
            'göre |DC| kaç cm olur?',
            dc,
            // D'yi orta nokta sanma, oranı ters kurma, oran yerine farkı
            // ekleme, oranın karesini alma, |AC|'den |BD|'yi çıkarma, oranın
            // bir birimini yanıt sanma.
            [
              bd,
              bol(bd * ab, ac),
              bd + (n - m) * s,
              bol(n * n * w, m),
              ac - bd,
              w,
            ],
            'Açıortay teoremine göre |BD| / |DC| = |AB| / |AC| = $ab/$ac = '
                '$m/$n olur. $bd / |DC| = $m/$n eşitliğinden |DC| = $dc cm.',
            sira,
            unit: 'cm',
          );
        }
        return _sayi(
          '$giris |AB| = $ab cm, |AC| = $ac cm ve |BC| = $bc cm olduğuna göre '
          '|BD| kaç cm olur?',
          bd,
          // Oranı ters kurma, D'yi orta nokta sanma, |BC|'yi m/n ile
          // çarpma, |AB|'yi |BC|'den çıkarma, oranın bir birimini yanıt
          // sanma, |AB|'nin yarısı.
          [
            dc,
            if (bc.isEven) bc ~/ 2,
            bol(bc * m, n),
            bc - ab,
            w,
            if (ab.isEven) ab ~/ 2,
          ],
          'Açıortay teoremine göre |BD| / |DC| = |AB| / |AC| = $ab/$ac = '
              '$m/$n olur. |BD| = $bc·$m / ${m + n} = $bd cm.',
          sira,
          unit: 'cm',
          // D, [BC] üzerinde olduğundan |BD| < |BC|.
          ust: bc,
        );
      }
      if (c % 3 == 1) {
        // |AD| = |BE| olursa yanıt verilen kenarortaya eşit çıkar; q bu
        // değeri atlar (a sabitken b → q bire birdir).
        final p = 2 + a, q = 3 + b >= p ? 4 + b : 3 + b;
        final (ad, yanit, yanlis) = switch (j) {
          // 2:1 oranını ters alma, iki kısa ya da iki uzun parçayı alma,
          // kenarortayın tamamını alma.
          0 => (
            '|AG| + |GE|',
            2 * p + q,
            [p + 2 * q, p + q, 2 * p + 2 * q, 3 * p + q, 2 * p + 3 * q],
          ),
          1 => (
            '|GD| + |BG|',
            p + 2 * q,
            [2 * p + q, p + q, 2 * p + 2 * q, p + 3 * q, 3 * p + 2 * q],
          ),
          _ => (
            '|AG| + |BG|',
            2 * p + 2 * q,
            [p + q, 2 * p + q, p + 2 * q, 3 * p + 2 * q, 2 * p + 3 * q],
          ),
        };
        return _sayi(
          'ABC üçgeninde [AD] ve [BE] kenarortayları G noktasında kesişiyor. '
          '|AD| = ${3 * p} cm ve |BE| = ${3 * q} cm olduğuna göre $ad toplamı '
          'kaç cm olur?',
          yanit,
          [...yanlis, 3 * p + 3 * q],
          'Ağırlık merkezi her kenarortayı köşeden başlayarak 2:1 oranında '
              'böler: |AG| = ${2 * p}, |GD| = $p, |BG| = ${2 * q} ve |GE| = $q '
              'cm olur. $ad = $yanit cm.',
          sira,
          unit: 'cm',
        );
      }
      final x = 3 + a, r = 14 + b;
      const giris = 'ABC dik üçgeninde A açısının ölçüsü 90° olup D noktası '
          '[BC] hipotenüsünün orta noktasıdır.';
      const kural =
          'Dik üçgende hipotenüse ait kenarortay hipotenüsün yarısına eşittir';
      return switch (j) {
        0 => _sayi(
          '$giris |AB| = $x cm ve |BC| = ${2 * r} cm olduğuna göre ABD '
              'üçgeninin çevresi kaç cm olur?',
          x + 2 * r,
          // Bir kenarı unutma, |AD| ya da |BD| için hipotenüsü alma,
          // |AD| = |AB| sanma.
          [x + r, x + 4 * r, 2 * r, x + 3 * r, 2 * x + r],
          '$kural: |AD| = |BD| = ${2 * r} / 2 = $r cm. Çevre $x + $r + $r = '
              '${x + 2 * r} cm.',
          sira,
          unit: 'cm',
        ),
        1 => _sayi(
          '$giris |AB| = $x cm ve ABD üçgeninin çevresi ${x + 2 * r} cm '
              'olduğuna göre |BC| kaç cm olur?',
          2 * r,
          // Yarısını verme, iki katını alma, |AB|'yi iki kez çıkarma,
          // çevreyi ikiye bölme, çevreyi yanıt sanma.
          [
            r,
            4 * r,
            if (2 * r > x) 2 * r - x,
            if (x.isEven) x ~/ 2 + r,
            3 * r,
            x + 2 * r,
          ],
          '$kural: |AD| = |BD| = |BC| / 2. Çevre |AB| + |BC| = ${x + 2 * r} '
              'olduğundan |BC| = ${x + 2 * r} − $x = ${2 * r} cm.',
          sira,
          unit: 'cm',
          // Hipotenüs dik kenardan uzundur: |BC| > |AB|.
          alt: x,
        ),
        _ => _sayi(
          '$giris |AB| = $x cm ve |AD| = $r cm olduğuna göre ABD üçgeninin '
              'çevresi kaç cm olur?',
          x + 2 * r,
          [x + r, x + 3 * r, 2 * r, x + 4 * r, 2 * x + r],
          '$kural: |BD| = |DC| = |AD| = $r cm. Çevre $x + $r + $r = '
              '${x + 2 * r} cm.',
          sira,
          unit: 'cm',
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
      final j = c ~/ 3, sira = _hs(a, b, c);
      // p / q tam bölünüyorsa bölüm, değilse seçenek olarak elenen 0.
      int bol(int p, int q) => q > 0 && p % q == 0 ? p ~/ q : 0;
      if (c % 3 == 0) {
        final n = 5 + a, x = 30 + 7 * b + j, ic = (n - 2) * 180, t = ic - x;
        return _aci(
          'Kenar sayısı $n olan konveks bir çokgenin iç açılarından biri '
          'dışındaki diğer iç açılarının ölçüleri toplamı $t° olarak '
          'veriliyor. Buna göre toplamın dışında bırakılan iç açının ölçüsü '
          'kaç derecedir?',
          x,
          // Dış açıyı verme, çokgeni düzgün sanma (iç ya da dış açı), kalan
          // açıların ortalamasını alma.
          [180 - x, bol(ic, n), bol(t, n - 1), bol(360, n)],
          '$n kenarlı çokgenin iç açıları toplamı ($n − 2)·180° = $ic° olur. '
              'Aranan açı $ic° − $t° = $x°.',
          sira,
        );
      }
      if (c % 3 == 1) {
        final n = 5 + a, x = 25 + 7 * b + j, ic = (n - 2) * 180, t = ic - x;
        final d = n * (n - 3) ~/ 2;
        return _sayi(
          'Konveks bir çokgenin iç açılarından biri dışındaki diğer iç '
          'açılarının ölçüleri toplamı $t° olduğuna göre bu çokgenin köşegen '
          'sayısı kaçtır?',
          d,
          // İkiye bölmeyi unutma, bir köşeden çizilenleri sayma, kenarları da
          // sayma (C(n, 2)), kenar sayısını verme, n'yi bir fazla ya da eksik
          // bulma.
          [
            n * (n - 3),
            n - 3,
            n * (n - 1) ~/ 2,
            n,
            (n + 1) * (n - 2) ~/ 2,
            (n - 1) * (n - 4) ~/ 2,
          ],
          'Dışarıda bırakılan açı 0° ile 180° arasında olduğundan iç açılar '
              'toplamı, $t° değerinden büyük ilk 180° katı olan $ic° olur. '
              '(n − 2)·180° = $ic° eşitliğinden n = $n bulunur. Köşegen sayısı '
              'n·(n − 3) / 2 = $n·${n - 3} / 2 = $d.',
          sira,
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
          // Dış açıyı verme, düzgün çokgen sanma, toplamı (n − 3)·180° ya da
          // (n − 1)·180° alma, verilen açıların ortalamasını alma, kalan
          // toplamı yanlış sayıya bölme.
          [
            y,
            bol(ic, n),
            bol(ic - ver - 180, m),
            bol(ic - ver + 180, m),
            bol(ver, k),
            bol(ic - ver, m + 1),
            bol(ic - ver, m - 1),
          ],
          'İç açılar toplamı ($n − 2)·180° = $ic° olur. Kalan $m açının '
              'toplamı $ic° − $ver° = ${ic - ver}°, her biri ${ic - ver}° / $m = '
              '${180 - y}°.',
          sira,
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
      // İç açıyı verme, verilen dış açıların ortalamasını alma, düzgün
      // çokgen sanma, verilen açıları 360°'tan çıkarmayı unutma, kalan
      // toplamı yanlış sayıya bölme.
      final dis = [
        bol(e, k),
        bol(360, m),
        bol(360, k + m),
        bol(m * y, k + m),
        bol(m * y, m - 1),
        bol(m * y, k),
        bol(m * y, m + 1),
      ];
      if (j == 0) {
        return _aci(
          '$veri Buna göre eşit olan dış açılardan her biri kaç derecedir?',
          y,
          [180 - y, ...dis],
          cozum,
          sira,
        );
      }
      return _aci(
        '$veri Buna göre eşit olan dış açılara komşu iç açılardan her biri '
        'kaç derecedir?',
        180 - y,
        [y, for (final d in dis) d > 0 ? 180 - d : 0],
        '$cozum Komşu iç açı 180° − $y° = ${180 - y}°.',
        sira,
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
      final j = c ~/ 2, sira = _hs(a, b, c);
      // p / q tam bölünüyorsa bölüm, değilse seçenek olarak elenen 0.
      int bol(int p, int q) => p % q == 0 ? p ~/ q : 0;
      if (c.isEven) {
        final q = 4 + b, p = q + 2 * (1 + a), h = 3 + j + a % 4;
        final alan = (p + q) * h ~/ 2;
        return _sayi(
          'ABCD yamuğunda [AB] ∥ [DC] olup |AB| = $p cm, |DC| = $q cm ve '
          'yamuğun yüksekliği $h cm olarak veriliyor. Buna göre ABCD yamuğunun '
          'alanı kaç cm² olur?',
          alan,
          // İkiye bölmeyi unutma ya da iki kez bölme, uzun tabanla çarpma,
          // tabanları çıkarma. (Kısa tabanla çarpım eklenmez: uzun tabanla
          // çarpımla birlikte anahtarın tam iki yanında kalırdı.)
          [(p + q) * h, p * h, (p - q) * h ~/ 2, bol((p + q) * h, 4)],
          'Yamuğun alanı, taban uzunlukları toplamı ile yüksekliğin '
              'çarpımının yarısıdır: ($p + $q)·$h / 2 = ${p + q}·$h / 2 = '
              '$alan cm².',
          sira,
          unit: 'cm²',
        );
      }
      // f, e değerini atlar: köşegenleri eşit "eşkenar dörtgen" kare olur ve
      // diğer köşegen sorusunda yanıt verilen köşegene eşit çıkar.
      final e = 2 * (3 + a), f = 5 + b >= e ? 6 + b : 5 + b;
      switch (j) {
        case 0:
          return _sayi(
            'Köşegen uzunlukları $e cm ve $f cm olan bir eşkenar dörtgenin '
            'alanı kaç cm² olur?',
            e * f ~/ 2,
            // İkiye bölmeyi unutma ya da iki kez bölme, dört üçgenin dik
            // kenarlarını köşegen alma, köşegenleri toplama, küçük üçgenlerden
            // birinin alanını verme.
            [
              e * f,
              e + f,
              2 * e * f,
              bol(e * f, 4),
              2 * (e + f),
              bol(e * f, 8),
            ],
            'Eşkenar dörtgenin alanı köşegen uzunlukları çarpımının yarısıdır: '
                '$e·$f / 2 = ${e * f ~/ 2} cm².',
            sira,
            unit: 'cm²',
          );
        case 1:
          final g = f + 20;
          return _sayi(
            'Köşegenleri birbirini dik kesen bir deltoidin köşegen uzunlukları '
            '$e cm ve $g cm olduğuna göre bu deltoidin alanı kaç cm² olur?',
            e * g ~/ 2,
            [
              e * g,
              e + g,
              2 * e * g,
              bol(e * g, 4),
              2 * (e + g),
              bol(e * g, 8),
            ],
            'Deltoidin alanı köşegen uzunlukları çarpımının yarısıdır: '
                '$e·$g / 2 = ${e * g ~/ 2} cm².',
            sira,
            unit: 'cm²',
          );
        case 2:
          final s = e * f ~/ 2;
          return _sayi(
            'Alanı $s cm² olan bir eşkenar dörtgenin köşegenlerinden biri '
            '$e cm olduğuna göre diğer köşegeni kaç cm olur?',
            f,
            // 2 ile çarpmayı unutma, alanı köşegenlerin çarpımının dörtte
            // biri sanma, kare sanıp diğer köşegeni eşit alma, köşegeni alanın
            // yarısı sanma, 2 ile çarpmak yerine 2'ye bölme.
            [bol(s, e), 2 * f, e, bol(s, 2), bol(f, 4)],
            'Alan köşegenler çarpımının yarısıdır: $e·k / 2 = $s. Buradan '
                'k = ${2 * s} / $e = $f cm.',
            sira,
            unit: 'cm',
          );
        case 3:
          final p = 6 + a, h = 4 + b;
          return _sayi(
            'ABCD paralelkenarında |AB| = $p cm ve [AB] kenarına ait yükseklik '
            '$h cm olduğuna göre ABCD paralelkenarının alanı kaç cm² olur?',
            p * h,
            // Üçgen sanıp ikiye bölme, çevre gibi toplama, iki üçgenin
            // alanını ayrı ayrı p·h alma.
            [bol(p * h, 2), 2 * (p + h), p + h, 2 * p * h],
            'Paralelkenarın alanı bir kenar ile o kenara ait yüksekliğin '
                'çarpımıdır: $p·$h = ${p * h} cm².',
            sira,
            unit: 'cm²',
          );
        default:
          final (u, v) = const [(3, 2), (4, 3), (5, 2), (5, 3), (5, 4)][b % 5];
          final t = 1 + b ~/ 5, m = 5 + a;
          final p = m * u, q = m * v, hp = v * t, hq = u * t;
          return _sayi(
            'ABCD paralelkenarında |AB| = $p cm, |AD| = $q cm ve [AB] kenarına '
            'ait yükseklik $hp cm olduğuna göre [AD] kenarına ait yükseklik '
            'kaç cm olur?',
            hq,
            // Yükseklikleri eşit sanma, oranı ters kurma, üçgen formülüyle
            // iki katını ya da yarısını bulma, toplama eşitliği kurma.
            [hp, bol(q * hp, p), 2 * hq, bol(hq, 2), p + hp - q],
            'Alan iki ayrı kenar ve yükseklikle yazılır: $p·$hp = $q·h. '
                'Buradan h = ${p * hp} / $q = $hq cm.',
            sira,
            unit: 'cm',
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
          'Yarı çevre ${p + q} cm olduğundan uzun kenar ${p + q} − $p = $q cm '
              'olur. $pisagor: k² = $p² + $q² = '
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
      // π = 3 alındığında 60°'lik yayın uzunluğu yarıçapa eşit çıkar ve yanıt
      // verilen sayıyı tekrarlar; bu vakalarda tabloda olmayan 36° kullanılır.
      final (al, carpan) = uc && _yay[b].$1 == 60 ? (36, 10) : _yay[b];
      final r = carpan * (1 + a);
      final y = r * al ~/ 180, s = r * r * al ~/ 360;
      String sim(int k) => k == 1 ? 'π' : '$kπ';
      String yaz(int k) => uc ? '${3 * k}' : sim(k);
      final ek = uc ? ' (π = 3 alınız.)' : '';
      final pi = uc ? '' : 'π ';
      String son(int k) => uc ? ' π = 3 alınırsa ${3 * k} bulunur.' : '';
      int deger(int k) => uc ? 3 * k : k;
      // Yarısı tam sayıysa yarısı, değilse elenen 0.
      int yari(int k) => k.isEven ? k ~/ 2 : 0;
      final sira = _hs(a, b, c);
      switch (j) {
        case 0:
          return _sayi(
            'Yarıçapı $r cm olan bir çemberde, merkez açısının ölçüsü $al° '
            'olan yayın uzunluğu kaç ${pi}cm olur?$ek',
            deger(y),
            // 2'yi unutma, çevrenin tamamı, 180'e bölme, alan formülü, öteki
            // yay, çap ile çalışma; π = 3 iken π'yi katmama.
            [
              ...[yari(y), 2 * r, 2 * y, 2 * r - y, s].map(deger),
              if (uc) y,
            ],
            'Yay uzunluğu 2πr·(α / 360) = 2π·$r·$al / 360 = ${sim(y)} cm olur.'
                '${son(y)}',
            sira,
          );
        case 1:
          return _sayi(
            'Yarıçapı $r cm olan bir dairede, merkez açısının ölçüsü $al° olan '
            'daire diliminin alanı kaç ${pi}cm² olur?$ek',
            deger(s),
            // Dairenin tamamı, yay formülü, 180'e bölme, ikiye bölme, öteki
            // dilim, çap ile çalışma; π = 3 iken π'yi katmama.
            [
              ...[y, r * r, yari(s), 2 * s, r * r - s, 4 * s].map(deger),
              if (uc) s,
            ],
            'Dilimin alanı πr²·(α / 360) = π·${r * r}·$al / 360 = ${sim(s)} cm² '
                'olur.${son(s)}',
            sira,
          );
        case 2:
          return _sayi(
            'Bir çemberde merkez açısının ölçüsü $al° olan yayın uzunluğu '
            '${yaz(y)} cm olduğuna göre bu çemberin yarıçapı kaç cm olur?$ek',
            r,
            // Formüldeki 2'yi unutma ya da iki kez bölme, öteki yayın
            // açısıyla çalışma, yay uzunluğunu yarıçap sanma; π = 3 iken
            // π'ye bölmeme.
            [
              2 * r,
              yari(r),
              if (r * al % (360 - al) == 0) r * al ~/ (360 - al),
              deger(y),
              if (uc) 3 * r,
            ],
            'Yay uzunluğu 2πr·($al / 360) = ${yaz(y)} eşitliğinden '
                'r = $r cm bulunur.',
            sira,
            unit: 'cm',
          );
        case 3:
          return _sayi(
            'Bir dairede merkez açısının ölçüsü $al° olan daire diliminin '
            'alanı ${yaz(s)} cm² olduğuna göre bu dairenin yarıçapı kaç cm '
            'olur?$ek',
            r,
            // Karekök almayı unutma, yay formülüyle karıştırma, çapı verme,
            // ikiye bölme, α/360 ile bölmek yerine çarpma, α/360 çarpanını
            // unutup karekök alma.
            [
              r * r,
              2 * r,
              yari(r),
              yari(r * r),
              if (r * al % 360 == 0) r * al ~/ 360,
              for (var k = 1; k < r; k++)
                if (k * k == s) k,
            ],
            'Dilimin alanı πr²·($al / 360) = ${yaz(s)} eşitliğinden '
                'r² = ${r * r}, r = $r cm bulunur.',
            sira,
            unit: 'cm',
          );
        default:
          return _aci(
            'Yarıçapı $r cm olan bir çemberde uzunluğu ${yaz(y)} cm olan yayı '
            'gören merkez açının ölçüsü kaç derecedir?$ek',
            al,
            // 180'e ya da 720'ye bölme, öteki yayın açısı, bütünler açı;
            // π = 3 iken π'ye bölmeme.
            [yari(al), 2 * al, 360 - al, 180 - al, if (uc) 3 * al],
            'Çemberin çevresi 2πr = ${yaz(2 * r)} cm olur. Yay çevrenin '
                '${kesir(y, 2 * r)} kadarı olduğundan merkez açı '
                '360°·${kesir(y, 2 * r)} = $al°.',
            sira,
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
      final ikinci = c >= 5, sira = _hs(a, b, c);
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
              // Açıyı yay sanma, AC yayını verme, x'i çıkarmayı unutma,
              // bütünler açıyı verme.
              [360 - th - x, 2 * th, 360 - 2 * th, 180 - th, th, 2 * th - x],
              'ABC çevre açısının gördüğü, B noktasını içermeyen AC yayı '
                  '2·$th° = $kalan° olur. Üç yayın toplamı 360° olduğundan BC yayı '
                  '360° − $kalan° − $x° = $y°.',
              sira,
              ust: 360,
            );
          }
          return _aci(
            '$veri $x°, A noktasını içermeyen BC yayının ölçüsü $y° olduğuna '
            'göre ABC açısının ölçüsü kaç derecedir?',
            kalan ~/ 2,
            // Çevre açı 180°'den küçüktür; yayı açı sanma, yanlış yayın
            // yarısını alma.
            [kalan, (x + y) ~/ 2, x ~/ 2, y ~/ 2, x + y, 180 - kalan ~/ 2],
            '$cozum ABC çevre açısı bu yayı gördüğünden ölçüsü $kalan° / 2 = '
                '${kalan ~/ 2}°.',
            sira,
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
              // Yay yerine açıyı verme, AB ya da AC yayını verme, öteki
              // yay, yarıya bölme.
              [t, 2 * (u + v), 2 * u, 2 * v, 360 - 2 * t, u + v],
              'T, A ve K doğrusal olduğundan BAC = 180° − $u° − $v° = $t° '
                  'olur. BAC çevre açısının gördüğü BC yayı 2·$t° = ${2 * t}°.',
              sira,
              ust: 360,
            );
          }
          return _aci(
            '$veri BAC açısının ölçüsü kaç derecedir?',
            t,
            // Teğet-kiriş açılarını toplama, bütünler açılar, farkı alma,
            // TAB'yi BAC sanma, yayı verme.
            [u + v, 180 - u, 180 - v, (u - v).abs(), u, 2 * t],
            'T, A ve K noktaları doğrusal olduğundan TAB + BAC + KAC = 180° '
                'olur. BAC = 180° − $u° − $v° = $t°.',
            sira,
          );
        case 2:
          final al = 70 + 2 * a, u = 12 + 2 * b;
          if (ikinci) {
            return _aci(
              'ABCD kirişler dörtgeninde BAD açısının ölçüsü $al°, ABD '
              'açısının ölçüsü $u° olduğuna göre ACB açısının ölçüsü kaç '
              'derecedir?',
              180 - al - u,
              [al - u, 180 - al, 180 - u, u, 180 - al + u],
              'ABD üçgeninde ADB = 180° − $al° − $u° = ${180 - al - u}° olur. '
                  'ACB ve ADB çevre açıları aynı AB yayını gördüğünden ACB = '
                  '${180 - al - u}°.',
              sira,
            );
          }
          return _aci(
            'ABCD kirişler dörtgeninde BAD açısının ölçüsü $al°, CBD açısının '
            'ölçüsü $u° olduğuna göre BDC açısının ölçüsü kaç derecedir?',
            al - u,
            [180 - al - u, 180 - al + u, al + u, 180 - al, al],
            'Kirişler dörtgeninde karşılıklı açılar bütünlerdir: BCD = 180° − '
                '$al° = ${180 - al}°. BCD üçgeninde BDC = 180° − ${180 - al}° − '
                '$u° = ${al - u}°.',
            sira,
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
              [2 * t, 180 - t, 180 - 2 * t, (u - v).abs(), u],
              cozum,
              sira,
            );
          }
          return _aci(
            '$veri AOC açısının ölçüsü kaç derecedir?',
            2 * t,
            [t, 180 - t, 360 - 2 * t, 180 - 2 * t, 4 * t],
            '$cozum Merkez açı aynı yayı gören çevre açının iki katıdır: AOC = '
                '2·$t° = ${2 * t}°.',
            sira,
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
              [u + v, 90 + u - v, 180 - u - v, 90 - u, 90 + v, 90 - v],
              '$cap ABC üçgeninde CBA = 90° − $u° = ${90 - u}° bulunur. '
                  'CBD = ${90 - u}° + $v° = ${90 - u + v}°.',
              sira,
            );
          }
          return _aci(
            '$veri CAD açısının ölçüsü kaç derecedir?',
            90 + u - v,
            [u + v, 90 - u + v, 180 - u - v, 90 - v, 90 + u, 90 - u],
            '$cap ABD üçgeninde DAB = 90° − $v° = ${90 - v}° bulunur. '
                'CAD = $u° + ${90 - v}° = ${90 + u - v}°.',
            sira,
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
      final sira = _hs(a, b, c);
      // p / q tam bölünüyorsa bölüm, değilse seçenek olarak elenen 0.
      int bol(int p, int q) => p % q == 0 ? p ~/ q : 0;
      const silindir = 'olan dik dairesel silindirin';
      switch (c % 5) {
        case 0:
          return _sayi(
            'Taban yarıçapı $r cm, yüksekliği $h cm $silindir hacmi kaç π cm³ '
            'olur?',
            r * r * h,
            // Yanal alan formülü, r ile h'yi karıştırma, koni formülü, r'nin
            // karesini almama, çapla çalışma, tüm yüzey alanı.
            [
              2 * r * h,
              r * h * h,
              bol(r * r * h, 3),
              r * h,
              4 * r * r * h,
              2 * r * (r + h),
              2 * r * r * h,
            ],
            'Silindirin hacmi πr²h = π·$r²·$h = π·${r * r}·$h = '
                '${r * r * h}π cm³.',
            sira,
          );
        case 1:
          return _sayi(
            'Taban yarıçapı $r cm, yüksekliği $h cm $silindir yanal yüzey '
            'alanı kaç π cm² olur?',
            2 * r * h,
            // 2'yi unutma, hacim formülü, tabanları ekleme, çapla çalışma,
            // taban çevresini yanıt sanma, tek taban ekleme.
            [
              r * h,
              r * r * h,
              2 * r,
              2 * r * (r + h),
              4 * r * h,
              2 * r * h + r * r,
            ],
            'Yanal yüzey, taban çevresi ile yüksekliğin çarpımıdır: 2πrh = '
                '2π·$r·$h = ${2 * r * h}π cm².',
            sira,
          );
        case 2:
          return _sayi(
            'Taban yarıçapı $r cm, yüksekliği $h cm $silindir tüm yüzey alanı '
            'kaç π cm² olur?',
            2 * r * (r + h),
            // Tabanları ya da bir tabanı unutma, 2'yi unutma, yanal yüzeyde
            // çapla çalışma, hacim formülü, her şeyi iki kez sayma.
            [
              2 * r * h,
              r * (r + h),
              2 * r * h + r * r,
              2 * r * r + r * h,
              2 * r * r + 4 * r * h,
              r * r * h,
              4 * r * (r + h),
            ],
            'Tüm yüzey alanı iki taban ile yanal yüzeyin toplamıdır: 2πr² + '
                '2πrh = 2π·$r·($r + $h) = ${2 * r * (r + h)}π cm².',
            sira,
          );
        case 3:
          final n = 1 + hh ~/ 2;
          if (hh.isEven) {
            return _sayi(
              'Taban yarıçapı $r cm, yüksekliği ${3 * n} cm olan dik dairesel '
              'koninin hacmi kaç π cm³ olur?',
              r * r * n,
              // 3'e bölmeyi unutma ya da 2'ye bölme, r ile h'yi karıştırma,
              // r'nin karesini almama, iki kez 3'e bölme, çapla çalışma.
              [
                3 * r * r * n,
                r * n,
                r * n * n * 3,
                bol(3 * r * r * n, 2),
                bol(r * r * n, 3),
                4 * r * r * n,
                3 * r * n,
              ],
              'Koninin hacmi πr²h / 3 = π·${r * r}·${3 * n} / 3 = '
                  '${r * r * n}π cm³.',
              sira,
            );
          }
          final yuk = r + 3 * n, v = r * r * (r + n);
          return _sayi(
            'Taban yarıçapı $r cm, yüksekliği $yuk cm olan dik dairesel bir '
            'koninin tabanına, yarıçapı $r cm olan bir yarım küre düz '
            'yüzünden yapıştırılıyor. Oluşan cismin hacmi kaç π cm³ olur?',
            v,
            // Yalnız koniyi ya da yalnız yarım küreyi alma, tam küre alma,
            // 3'e bölmeyi unutma (tümünde ya da konide), yarım küreyi 2πr³
            // alma, r'nin karesini almama, yarım küreyi unutup koniyi silindir
            // gibi hesaplama, çapla çalışma.
            [
              bol(r * r * yuk, 3),
              bol(r * r * (yuk + 4 * r), 3),
              r * r * (yuk + 2 * r),
              bol(2 * r * r * r, 3),
              bol(3 * r * r * yuk + 2 * r * r * r, 3),
              bol(r * r * yuk + 6 * r * r * r, 3),
              r * (r + n),
              r * r * yuk,
              4 * v,
            ],
            'Koninin hacmi π·${r * r}·$yuk / 3, yarım kürenin hacmi '
                '(2/3)·π·$r³ olur. Toplam π·${r * r}·($yuk + ${2 * r}) / 3 = '
                '$vπ cm³.',
            sira,
          );
        default:
          final s = r * (3 * r + 2 * h);
          return _sayi(
            'Taban yarıçapı $r cm, yüksekliği $h cm $silindir üst tabanına, '
            'yarıçapı $r cm olan bir yarım küre düz yüzünden yapıştırılıyor. '
            'Oluşan cismin dış yüzey alanı kaç π cm² olur?',
            s,
            // Tam küre alma ya da üst tabanı da sayma, alt tabanı unutma,
            // yanal yüzeyde 2'yi unutma, yarım küreyi unutma, tam küre ve
            // alt taban, yanal yüzeyde çapla çalışma, hacim formülü.
            [
              r * (4 * r + 2 * h),
              r * (2 * r + 2 * h),
              r * (3 * r + h),
              r * (r + 2 * h),
              r * (5 * r + 2 * h),
              r * (3 * r + 4 * h),
              r * r * h,
            ],
            'Dış yüzey; alt taban πr², yanal yüzey 2πrh ve yarım kürenin '
                'yüzeyi 2πr² toplamıdır: π·${r * r} + 2π·$r·$h + 2π·${r * r} = '
                '$sπ cm².',
            sira,
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
      final sira = _hs(a, b, c);
      // Çeldiriciler paydası aynı (√(A² + B²)) kalan pay hatalarıdır; pay ya
      // da paydası anahtarla ortak olan "kökü unutma", "paydayı unutma" gibi
      // seçenekler anahtarı ötekilerin ortası yapardı. Bu ikisi yalnız pay
      // hataları çakıştığında (nokta orijindeyse, sabit sıfırsa) eklenir.
      // Anahtar tam sayıysa paydayı unutma hatası en başa alınır ve her
      // vakada kullanılır; böylece anahtar tek tam sayı seçenek kalmaz.
      List<String> celdir(int pay, Iterable<int> paylar) {
        final yazim = kesir(pay, h);
        final farkli = {
          for (final e in paylar)
            if (e > 0 && e != pay) e,
        };
        return _celdirici(
          pay / h,
          yazim,
          [
            if (pay % h == 0) (pay, '$pay'),
            for (final e in farkli) (e / h, kesir(e, h)),
            if (farkli.length < 2) ...[
              (pay, '$pay'),
              (pay / (h * h), kesir(pay, h * h)),
            ],
          ],
          [
            for (final e in _komsu(pay, 1))
              if (e > 0) (e / h, kesir(e as int, h)),
          ],
          sira,
          // Tam sayı anahtarda tek tam sayı çeldirici (paydayı unutma)
          // anahtardan büyüktür; üç çeldiricinin de küçük olduğu sıra
          // seçilmez.
          enCokAlt: pay % h == 0 ? 2 : 3,
        );
      }

      if (c.isEven) {
        final x0 = a - 12, y0 = b - 10, t = ka * x0 + kb * y0;
        var k = ((a + 2 * b) % 9 + 1) * ((a + b).isEven ? 1 : -1);
        if (t + k == 0) k++;
        final n = (t + k).abs();
        return AdvancedItem(
          'Analitik düzlemde A${_n(x0, y0)} noktasının ${_dnk(ka, kb, k)} '
              'doğrusuna uzaklığı kaç birimdir?',
          kesir(n, h),
          // Sabit terimin işaretini çevirme, x ile y katsayılarını karıştırma,
          // bir terimin işaretini çevirme, mutlak değeri terim terim alma,
          // sabit terimi unutma. (Sonuncusu, işareti çevrilmiş sabitle
          // birlikte anahtarla eşit aralıklı dizi kurduğu için en sondadır.)
          celdir(n, [
            (t - k).abs(),
            (kb * x0 + ka * y0 + k).abs(),
            (ka * x0 - kb * y0 + k).abs(),
            (kb * y0 - ka * x0 + k).abs(),
            (ka * x0).abs() + (kb * y0).abs() + k.abs(),
            t.abs(),
          ]),
          'Pay |$ka·${_pz(x0)} + ${_pz(kb)}·${_pz(y0)} + ${_pz(k)}| = $n, '
          'payda $payda olur. Uzaklık ${sonuc(n)} birimdir.',
        );
      }
      final c1 = a - 12, d = 1 + b + a % 4, c2 = c1 + d;
      final kat = (a + b).isEven ? 1 : 2;
      return AdvancedItem(
        'Analitik düzlemde ${_dnk(ka, kb, c1)} ve '
            '${_dnk(kat * ka, kat * kb, kat * c2)} paralel doğruları arasındaki '
            'uzaklık kaç birimdir?',
        kesir(d, h),
        // Sabitleri toplama, ikinci denklemi sadeleştirmeden sabitleri
        // çıkarma ya da yalnız birinci denklemi 2 ile genişletme, doğrulardan
        // birinin orijine uzaklığını verme. Orijine uzaklıklardan, anahtar
        // ile sabitleri toplama hatasının tam ortasına düşen eklenmez.
        celdir(d, [
          (c1 + c2).abs(),
          if (kat == 2) (c1 - 2 * c2).abs(),
          if (kat == 2) 2 * d,
          for (final e in [c2.abs(), c1.abs()])
            if (2 * e != d + (c1 + c2).abs()) e,
        ]),
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
      final genel =
          '${_ifade([(1, 'x²'), (1, 'y²'), (-2 * h, 'x'), (-2 * k, 'y'), (h * h + k * k - r * r, '')])} = 0';
      final tamKare = 'Denklem tam kareye tamamlanırsa $std biçimine gelir';
      switch (c % 5) {
        case 0:
          final top = h + k + r;
          return AdvancedItem(
            'Analitik düzlemde denklemi $std olan çemberin merkezi M(a, b) ve '
                'yarıçapı r birim olduğuna göre a + b + r toplamı kaçtır?',
            _m(top),
            // Merkezin ya da bir koordinatın işaretini çevirme, r yerine r²
            // alma (işaret hatasıyla birlikte de), karekök yerine ikiye bölme,
            // r'yi eklemeyi unutma.
            _celdirici(
              top,
              _m(top),
              [
                for (final x in [
                  -h - k + r,
                  h + k + r * r,
                  -h - k + r * r,
                  -h + k + r,
                  h - k + r,
                  if (r.isEven) h + k + r * r ~/ 2,
                  h + k,
                ])
                  (x, _m(x)),
              ],
              [for (final x in _komsu(top, 1)) (x, _m(x as int))],
              _hs(a, b, c),
            ),
            'Merkez M${_n(h, k)} ve r² = ${r * r} olduğundan r = $r bulunur. '
            'a + b + r = ${_m(h)} + ${_pz(k)} + $r = ${_m(h + k + r)}.',
          );
        case 1:
          // Tam kare ise karekökü, değilse elenen 0.
          int kok(int x) {
            for (var y = 1; y * y <= x; y++) {
              if (y * y == x) return y;
            }
            return 0;
          }
          final sabit = h * h + k * k - r * r;
          return _sayi(
            'Analitik düzlemde denklemi $genel olan çemberin yarıçapı kaç '
            'birimdir?',
            r,
            // Karekök almayı unutma, çapı verme, ikiye fazladan bölme, sabit
            // terimin karekökünü alma, r² = a² + b² + F diye işaret hatası,
            // sabit terimi unutma, merkezin bir koordinatını yarıçap sanma.
            [
              r * r,
              2 * r,
              if (r.isEven) r ~/ 2,
              kok(sabit.abs()),
              kok(h * h + k * k + sabit),
              kok(h * h + k * k),
              h.abs(),
              k.abs(),
            ],
            '$tamKare; r² = ${r * r} olduğundan yarıçap $r birimdir.',
            _hs(a, b, c),
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
                'olduğundan P noktası ${const ['çemberin iç bölgesindedir', 'çemberin dış bölgesindedir', 'çemberin üzerindedir'][durum]}.',
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
