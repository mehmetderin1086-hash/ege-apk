// Lise biyoloji: hesap ve akıl yürütme gerektiren 20 metin ailesi.
// Kalıtım, hücre bölünmesi, nükleik asitler, madde alışverişi, ekoloji ve
// sistemlerle ilgili kazanımlar; her aile 5.000 ayrı vaka üretir.
import 'ortak.dart';

final lmBiyoloji = <AdvancedFamily>[
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
  _gecici(13),
  _gecici(14),
  _gecici(15),
  _gecici(16),
  _gecici(17),
  _gecici(18),
  _gecici(19),
  _gecici(20),
];

AdvancedFamily _gecici(int k) => lmAile(
  'biy_gecici_$k',
  'Geçici aile $k',
  Topic.biology,
  Difficulty.easy,
  BloomLevel.uygulama,
  (a, b, c) => sayisal(
    'Geçici soru $k: ${a + 1} ile ${b + 30} ve ${c + 100} sayılarının toplamı kaçtır?',
    a + b + c + 131,
    const [],
    'Geçici açıklama metni.',
  ),
  lesson: 'Biyoloji',
);

// ───────────────────────── Ortak yardımcılar ─────────────────────────

const _olasilikHavuzu = [
  (1, 2), (1, 4), (3, 4), (1, 8), (3, 8), (1, 16), (3, 16), (9, 16), //
  (5, 8), (1, 32), (3, 32), (7, 8),
];

/// Kesir yanıtlı olasılık sorusu; adaylardan (0, 1] aralığındakiler kullanılır.
AdvancedItem _olasilik(
  String kok,
  int n,
  int d,
  Iterable<(int, int)> adaylar,
  String aciklama,
) {
  final uygun = [
    ...adaylar,
    ..._olasilikHavuzu,
  ].where((x) => x.$1 > 0 && x.$2 > 0 && x.$1 <= x.$2);
  return secenekli(
    kok,
    kesir(n, d),
    uygun.map((x) => kesir(x.$1, x.$2)),
    aciklama,
  );
}

int _us(int taban, int kuvvet) {
  var r = 1;
  for (var i = 0; i < kuvvet; i++) {
    r *= taban;
  }
  return r;
}

const _ustRakam = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];

/// Üs olarak yazılacak küçük tam sayı: `_ust(12)` → `¹²`.
String _ust(int n) => '$n'.split('').map((r) => _ustRakam[int.parse(r)]).join();

/// (baskın özellik, çekinik özellik, alel harfi, baskın fenotip, çekinik fenotip)
typedef _Karakter = (String, String, String, String, String);

const _bezelye = <_Karakter>[
  ('uzun boy', 'kısa boy', 'U', 'uzun boylu', 'kısa boylu'),
  ('sarı tohum', 'yeşil tohum', 'S', 'sarı tohumlu', 'yeşil tohumlu'),
  ('düzgün tohum', 'buruşuk tohum', 'D', 'düzgün tohumlu', 'buruşuk tohumlu'),
  ('mor çiçek', 'beyaz çiçek', 'M', 'mor çiçekli', 'beyaz çiçekli'),
  ('yeşil meyve', 'sarı meyve', 'Y', 'yeşil meyveli', 'sarı meyveli'),
  ('şişkin meyve', 'boğumlu meyve', 'B', 'şişkin meyveli', 'boğumlu meyveli'),
  ('yan çiçek', 'uç çiçek', 'A', 'yan çiçekli', 'uç çiçekli'),
];

/// Alel harfi ve gen kodundan (0 = homozigot baskın, 1 = heterozigot,
/// 2 = homozigot çekinik) genotip yazımı.
String _gt(String harf, int kod) {
  final k = harf.toLowerCase();
  return switch (kod) {
    0 => '$harf$harf',
    1 => '$harf$k',
    _ => '$k$k',
  };
}

/// İki ebeveynin gen kodlarından yavru dağılımı: 4 üzerinden
/// [homozigot baskın, heterozigot, homozigot çekinik].
List<int> _dort(int p, int q) {
  const alel = [
    [1, 1],
    [1, 0],
    [0, 0],
  ];
  final s = [0, 0, 0];
  for (final x in alel[p]) {
    for (final y in alel[q]) {
      s[2 - x - y]++;
    }
  }
  return s;
}

// ───────────────────────── 1. Monohibrit çaprazlama ─────────────────────────

const _tekKarakter = <(String, _Karakter)>[
  ('Bezelyelerde', ('uzun boy', 'kısa boy', 'U', 'uzun boylu', 'kısa boylu')),
  ('Bezelyelerde', ('sarı tohum', 'yeşil tohum', 'S', 'sarı tohumlu', 'yeşil tohumlu')),
  ('Bezelyelerde', ('düzgün tohum', 'buruşuk tohum', 'D', 'düzgün tohumlu', 'buruşuk tohumlu')),
  ('Bezelyelerde', ('mor çiçek', 'beyaz çiçek', 'M', 'mor çiçekli', 'beyaz çiçekli')),
  ('Bezelyelerde', ('yeşil meyve', 'sarı meyve', 'Y', 'yeşil meyveli', 'sarı meyveli')),
  ('Bezelyelerde', ('şişkin meyve', 'boğumlu meyve', 'B', 'şişkin meyveli', 'boğumlu meyveli')),
  ('Bezelyelerde', ('yan çiçek', 'uç çiçek', 'A', 'yan çiçekli', 'uç çiçekli')),
  ('Meyve sineklerinde', ('uzun kanat', 'körelmiş kanat', 'K', 'uzun kanatlı', 'körelmiş kanatlı')),
  ('Meyve sineklerinde', ('gri gövde', 'siyah gövde', 'G', 'gri gövdeli', 'siyah gövdeli')),
  ('Domateslerde', ('kırmızı meyve', 'sarı meyve', 'R', 'kırmızı meyveli', 'sarı meyveli')),
  ('Kobaylarda', ('siyah kıl', 'beyaz kıl', 'S', 'siyah kıllı', 'beyaz kıllı')),
  ('Kobaylarda', ('kısa kıl', 'uzun kıl', 'K', 'kısa kıllı', 'uzun kıllı')),
];

final _f01 = lmAile(
  'biy_monohibrit',
  'Monohibrit çaprazlamada beklenen yavru sayısı',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (org, (domOz, recOz, harf, domF, recF)) = _tekKarakter[a % 12];
    final het = _gt(harf, 1), dom = _gt(harf, 0), rec = _gt(harf, 2);
    final m = 6 + b + 2 * a; // yavruların dörtte biri
    final n = 4 * m;
    final giris =
        '$org $domOz aleli ($harf), $recOz aleline (${harf.toLowerCase()}) '
        'baskındır.';
    final hetIki = '$giris Heterozigot ($het) iki bireyin çaprazlanmasıyla';
    final oran =
        '$het × $het çaprazlamasında yavruların 1/4 kadarı $dom, 1/2 kadarı '
        '$het, 1/4 kadarı $rec genotipli olur.';
    switch (c) {
      case 0:
        return sayisal(
          '$hetIki toplam $n yavru elde ediliyor. Bu yavrulardan kaç tanesinin '
          '$domF olması beklenir?',
          3 * m,
          [m, 2 * m, n],
          '$oran $dom ve $het genotipliler $domF olduğundan beklenen sayı '
          '$n · 3/4 = ${3 * m} olur.',
          positive: true,
        );
      case 1:
        return sayisal(
          '$hetIki toplam $n yavru elde ediliyor. Bu yavrulardan kaç tanesinin '
          'heterozigot genotipli olması beklenir?',
          2 * m,
          [m, 3 * m, n],
          '$oran Heterozigot yavru sayısı $n · 1/2 = ${2 * m} olur.',
          positive: true,
        );
      case 2:
        return sayisal(
          '$giris $het genotipli bir birey ile $rec genotipli bir bireyin '
          'çaprazlanmasıyla toplam $n yavru elde ediliyor. Bu yavrulardan kaç '
          'tanesinin $recF olması beklenir?',
          2 * m,
          [m, 3 * m, n],
          '$het × $rec çaprazlamasında yavruların yarısı $het, yarısı $rec '
          'genotipli olur. Beklenen $recF yavru sayısı $n · 1/2 = ${2 * m} '
          'olur.',
          positive: true,
        );
      case 3:
        return sayisal(
          '$hetIki elde edilen yavrulardan $m tanesi $recF çıkıyor. Buna göre '
          '$domF yavru sayısının kaç olması beklenir?',
          3 * m,
          [n, 2 * m, m],
          '$oran Fenotip oranı 3 $domF : 1 $recF olduğundan $domF yavru '
          'sayısı $m · 3 = ${3 * m} olur.',
          positive: true,
        );
      case 4:
        return sayisal(
          '$hetIki elde edilen yavrulardan ${3 * m} tanesi $domF çıkıyor. Bu '
          '$domF yavrulardan kaç tanesinin heterozigot genotipli olması '
          'beklenir?',
          2 * m,
          [m, 3 * m ~/ 2, 3 * m, 9 * m ~/ 4],
          'Fenotipi $domF olan yavruların genotip oranı 1 $dom : 2 $het '
          'biçimindedir; 2/3 kadarı heterozigottur: ${3 * m} · 2/3 = '
          '${2 * m}.',
          positive: true,
        );
      case 5:
        return sayisal(
          '$giris $dom genotipli bir birey ile $het genotipli bir bireyin '
          'çaprazlanmasıyla toplam $n yavru elde ediliyor. Bu yavrulardan kaç '
          'tanesinin heterozigot genotipli olması beklenir?',
          2 * m,
          [m, 3 * m, n],
          '$dom × $het çaprazlamasında yavruların yarısı $dom, yarısı $het '
          'genotipli olur; hepsi $domF olsa da heterozigot sayısı '
          '$n · 1/2 = ${2 * m} olur.',
          positive: true,
        );
      case 6:
        return sayisal(
          '$hetIki toplam $n yavru elde ediliyor. Bu yavrularda $domF '
          'olanların sayısının, $recF olanların sayısından kaç fazla olması '
          'beklenir?',
          2 * m,
          [3 * m, m, n],
          'Beklenen $domF yavru sayısı $n · 3/4 = ${3 * m}, $recF yavru '
          'sayısı $n · 1/4 = $m olur. Fark ${3 * m} − $m = ${2 * m} bulunur.',
          positive: true,
        );
      case 7:
        return sayisal(
          '$hetIki elde edilen yavrulardan ${2 * m} tanesinin heterozigot '
          'genotipli olduğu belirleniyor. Buna göre toplam yavru sayısının kaç '
          'olması beklenir?',
          n,
          [8 * m, 3 * m, 6 * m],
          '$oran Heterozigotlar toplamın yarısı olduğundan toplam yavru '
          'sayısı ${2 * m} · 2 = $n olur.',
          positive: true,
        );
      case 8:
        return sayisal(
          '$hetIki toplam $n yavru elde ediliyor. Bu yavrulardan kaç tanesinin '
          'homozigot baskın ($dom) genotipli olması beklenir?',
          m,
          [2 * m, 3 * m, n],
          '$oran Homozigot baskın yavru sayısı $n · 1/4 = $m olur.',
          positive: true,
        );
      default:
        return sayisal(
          '$giris Fenotipi $domF olan iki bireyin çaprazlanmasıyla elde edilen '
          '$n yavrudan $m tanesi $recF çıkıyor. Buna göre yavrulardan kaç '
          'tanesinin heterozigot genotipli olması beklenir?',
          2 * m,
          [3 * m, m, 3 * m ~/ 2],
          'Çaprazlamada $recF yavru oluştuğuna göre ebeveynlerin ikisi de $het '
          'genotiplidir ($m / $n = 1/4). $het × $het çaprazlamasında '
          'heterozigot yavru sayısı $n · 1/2 = ${2 * m} olur.',
          positive: true,
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 2. Dihibrit çaprazlama ─────────────────────────

const _digerCiftler = <(String, _Karakter, _Karakter)>[
  (
    'Kobaylarda',
    ('siyah kıl', 'beyaz kıl', 'S', 'siyah kıllı', 'beyaz kıllı'),
    ('kısa kıl', 'uzun kıl', 'K', 'kısa kıllı', 'uzun kıllı'),
  ),
  (
    'Sığırlarda',
    ('boynuzsuzluk', 'boynuzluluk', 'B', 'boynuzsuz', 'boynuzlu'),
    ('siyah kıl', 'kırmızı kıl', 'S', 'siyah kıllı', 'kırmızı kıllı'),
  ),
  (
    'Domateslerde',
    ('kırmızı meyve', 'sarı meyve', 'R', 'kırmızı meyveli', 'sarı meyveli'),
    ('uzun boy', 'bodur boy', 'U', 'uzun boylu', 'bodur boylu'),
  ),
  (
    'Mısır bitkisinde',
    ('mor tane', 'sarı tane', 'M', 'mor taneli', 'sarı taneli'),
    ('dolgun tane', 'buruşuk tane', 'D', 'dolgun taneli', 'buruşuk taneli'),
  ),
];

/// 25 karakter çifti: 21 bezelye çifti ve dört ayrı canlıdan birer çift.
(String, _Karakter, _Karakter) _karakterCifti(int a) {
  if (a >= 21) return _digerCiftler[a - 21];
  var s = a, i = 0;
  while (s >= 6 - i) {
    s -= 6 - i;
    i++;
  }
  return ('Bezelyelerde', _bezelye[i], _bezelye[i + 1 + s]);
}

// Tek gen için ebeveyn kodları: fenotipçe açılım verenler ve yalnız
// genotipçe açılım verenler.
const _acilimli = [(1, 1), (1, 2), (2, 1)];
const _yariAcilimli = [(0, 1), (1, 0)];
final _dihibritCaprazlar = [
  for (final x in _acilimli)
    for (final y in _acilimli) (x, y),
  for (final x in _acilimli)
    for (final y in _yariAcilimli) (x, y),
  for (final x in _yariAcilimli)
    for (final y in _acilimli) (x, y),
];

final _f02 = lmAile(
  'biy_dihibrit',
  'Dihibrit çaprazlamada genotip ve fenotip olasılığı',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.analiz,
  (a, b, c) {
    final (org, k1, k2) = _karakterCifti(a);
    final ((p1, q1), (p2, q2)) = _dihibritCaprazlar[b * 8 % 21];
    final h1 = k1.$3, h2 = k2.$3;
    // Küçük/büyük harf ayrımı kaybolsa da ayırt edilebilen tanım.
    String zig(_Karakter k, int kod) => switch (kod) {
      0 => 'homozigot ${k.$4}',
      1 => 'heterozigot ${k.$4}',
      _ => k.$5,
    };
    String tanim(int x, int y) =>
        '${zig(k1, x)} ve ${zig(k2, y)} (${_gt(h1, x)}${_gt(h2, y)} genotipli)';
    final s1 = _dort(p1, q1), s2 = _dort(p2, q2);
    final d1 = s1[0] + s1[1], d2 = s2[0] + s2[1];
    final cap1 = '${_gt(h1, p1)} × ${_gt(h1, q1)}';
    final cap2 = '${_gt(h2, p2)} × ${_gt(h2, q2)}';
    // (hedef, 16 üzerinden pay, açıklama, çeldirici adayları)
    final hedefler = <(String, int, String, List<(int, int)>)>[];
    void carpim(String hedef, String ad1, int n1, String ad2, int n2) {
      final n = n1 * n2;
      if (n <= 0 || n >= 16) return;
      hedefler.add((
        hedef,
        n,
        'Karakterler ayrı ayrı incelenir: $cap1 çaprazlamasında $ad1 '
            'olasılığı ${kesir(n1, 4)}, $cap2 çaprazlamasında $ad2 olasılığı '
            '${kesir(n2, 4)} olur. Bağımsız olayların olasılıkları çarpılır: '
            '${kesir(n, 16)}.',
        [(n1, 4), (n2, 4), (n1 + n2, 8), (16 - n, 16), (n1 + n2, 4)],
      ));
    }

    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        final g1 = _gt(h1, i), g2 = _gt(h2, j);
        carpim(tanim(i, j), g1, s1[i], g2, s2[j]);
      }
    }
    for (final x in [(k1.$4, d1), (k1.$5, 4 - d1)]) {
      for (final y in [(k2.$4, d2), (k2.$5, 4 - d2)]) {
        carpim('${x.$1} ve ${y.$1}', '${x.$1} olma', x.$2, '${y.$1} olma', y.$2);
      }
    }
    final hom1 = 4 - s1[1], hom2 = 4 - s2[1];
    void bilesik(String hedef, int n, String aciklama, List<(int, int)> aday) {
      if (n > 0 && n < 16) hedefler.add((hedef, n, aciklama, aday));
    }

    bilesik(
      'her iki karakter bakımından homozigot',
      hom1 * hom2,
      'Homozigot olma olasılığı $cap1 çaprazlamasında ${kesir(hom1, 4)}, '
          '$cap2 çaprazlamasında ${kesir(hom2, 4)} olur. Çarpım: '
          '${kesir(hom1 * hom2, 16)}.',
      [(hom1, 4), (hom2, 4), (hom1 + hom2, 8), (16 - hom1 * hom2, 16)],
    );
    bilesik(
      'her iki karakter bakımından heterozigot',
      s1[1] * s2[1],
      'Heterozigot olma olasılığı $cap1 çaprazlamasında ${kesir(s1[1], 4)}, '
          '$cap2 çaprazlamasında ${kesir(s2[1], 4)} olur. Çarpım: '
          '${kesir(s1[1] * s2[1], 16)}.',
      [(s1[1], 4), (s1[1] + s2[1], 8), (16 - s1[1] * s2[1], 16), (hom1 * hom2, 16)],
    );
    final tekHet = s1[1] * hom2 + hom1 * s2[1];
    bilesik(
      'yalnızca bir karakter bakımından heterozigot',
      tekHet,
      'Heterozigot olma olasılığı birinci karakterde ${kesir(s1[1], 4)}, '
          'ikincide ${kesir(s2[1], 4)} olur. Yalnız birinde heterozigot: '
          '${kesir(s1[1], 4)} · ${kesir(hom2, 4)} + ${kesir(hom1, 4)} · '
          '${kesir(s2[1], 4)} = ${kesir(tekHet, 16)}.',
      [(s1[1] * s2[1], 16), (s1[1] * hom2, 16), (16 - tekHet, 16), (s1[1], 4)],
    );
    bilesik(
      'en az bir karakter bakımından çekinik fenotipli',
      16 - d1 * d2,
      'İki karakter bakımından da baskın fenotipli olma olasılığı '
          '${kesir(d1, 4)} · ${kesir(d2, 4)} = ${kesir(d1 * d2, 16)} olur. '
          'İstenen olasılık 1 − ${kesir(d1 * d2, 16)} = '
          '${kesir(16 - d1 * d2, 16)} bulunur.',
      [(d1 * d2, 16), ((4 - d1) * (4 - d2), 16), (8 - d1 - d2, 8), (8 - d1 - d2, 4)],
    );
    final (hedef, n, aciklama, aday) = hedefler[(c + a) % hedefler.length];
    return _olasilik(
      '$org ${k1.$1} aleli ($h1) ${k1.$2} aleline (${h1.toLowerCase()}), '
      '${k2.$1} aleli ($h2) ${k2.$2} aleline (${h2.toLowerCase()}) baskındır '
      've bu iki gen farklı kromozomlarda bulunur. Bu türden ${tanim(p1, p2)} '
      'bir birey ile ${tanim(q1, q2)} bir birey çaprazlanıyor. Bu '
      'çaprazlamadan oluşacak bir yavrunun $hedef olma olasılığı kaçtır?',
      n,
      16,
      aday,
      aciklama,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 3. Gamet çeşidi ve olasılığı ─────────────────────────

// Gen harfleri seçkiyle belirlenir; böylece kökler harf büyüklüğünden
// bağımsız olarak da birbirinden ayrılır.
const _genHarfleri = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'K', 'L', 'M', 'N'];

/// k genli ve en az bir geni heterozigot olan genotiplerden j numaralısı.
/// İlk heterozigot genin yerine göre bloklara ayrılır; her j ayrı bir
/// genotip verir (0 = homozigot baskın, 1 = heterozigot, 2 = homozigot çekinik).
List<int> _genotipSec(int k, int j) {
  for (var p = 0; p < k; p++) {
    final blok = (1 << p) * _us(3, k - 1 - p);
    if (j < blok) {
      final d = List<int>.filled(k, 1);
      var r = j;
      for (var q = 0; q < p; q++) {
        d[q] = (r % 2) * 2;
        r ~/= 2;
      }
      for (var q = p + 1; q < k; q++) {
        d[q] = r % 3;
        r ~/= 3;
      }
      return d;
    }
    j -= blok;
  }
  throw StateError('Genotip sırası aralık dışında');
}

String _genotipYaz(List<String> harf, List<int> d) => [
  for (var q = 0; q < d.length; q++) _gt(harf[q], d[q]),
].join();

final _f03 = lmAile(
  'biy_gamet',
  'Gamet çeşidi sayısı ve gamet olasılığı',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = (c == 4 || c == 5 || c == 9) ? 7 : 6;
    final gecerli = _us(3, k) - (1 << k);
    final sira = (a + 25 * b) * 277 + 31 * c;
    final d = _genotipSec(k, sira % gecerli);
    final harf = kombinasyon(
      _genHarfleri,
      k,
      sira % kombinasyonSayisi(12, k),
      spread: false,
    );
    final g = _genotipYaz(harf, d);
    final hetler = [
      for (var q = 0; q < k; q++)
        if (d[q] == 1) q,
    ];
    final n = hetler.length;
    final hetAd = hetler.map((q) => _gt(harf[q], 1)).join(', ');
    final giris =
        'Genotipi $g olan bir bireyde genler bağımsızdır (her gen çifti ayrı '
        'bir homolog kromozom çiftinde bulunur).';
    final ortak =
        'Heterozigot gen çifti sayısı $n olduğundan ($hetAd) gamet çeşidi '
        'sayısı 2${_ust(n)} = ${1 << n} olur.';
    String alel(int q) {
      final h = harf[q];
      return switch (d[q]) {
        0 => h,
        2 => h.toLowerCase(),
        _ => (q + a + b).isEven ? h : h.toLowerCase(),
      };
    }

    switch (c) {
      case 0 || 4:
        return sayisal(
          '$giris Bu birey mayozla en çok kaç çeşit gamet oluşturabilir?',
          1 << n,
          [2 * n, 1 << (n + 1), 1 << k, n, 1 << (n - 1), 2 * k],
          ortak,
          positive: true,
        );
      case 1 || 5:
        final gamet = [for (var q = 0; q < k; q++) alel(q)].join();
        return _olasilik(
          '$giris Bu bireyin oluşturduğu bir gametin $gamet alel bileşiminde '
          'olma olasılığı kaçtır?',
          1,
          1 << n,
          [(1, 1 << k), (1, 2 * n), (1, 1 << (n + 1)), (1, 1 << (n - 1)), (1, k)],
          '$ortak Gamet çeşitleri eşit olasılıkla oluştuğundan $gamet '
          'gametinin oluşma olasılığı 1/${1 << n} olur.',
        );
      case 2:
        final q0 = (a + b) % k;
        final x = alel(q0);
        final het = d[q0] == 1;
        return sayisal(
          '$giris Bu bireyin oluşturabileceği gamet çeşitlerinden kaç tanesi '
          '$x alelini taşır?',
          het ? 1 << (n - 1) : 1 << n,
          [het ? 1 << n : 1 << (n - 1), 1 << (n + 1), n, 2 * n, 1],
          het
              ? '$ortak ${_gt(harf[q0], 1)} gen çiftinden gelen $x aleli '
                    'bu çeşitlerin yarısında bulunur: ${1 << n} / 2 = '
                    '${1 << (n - 1)}.'
              : '$ortak Birey $x aleli bakımından homozigot olduğundan gamet '
                    'çeşitlerinin tamamı bu aleli taşır: ${1 << n}.',
          positive: true,
        );
      case 7:
        final q0 = (a + b) % k, q1 = (q0 + 2) % k;
        final ilk = q0 < q1 ? q0 : q1, son = q0 < q1 ? q1 : q0;
        final h = (d[q0] == 1 ? 1 : 0) + (d[q1] == 1 ? 1 : 0);
        return sayisal(
          '$giris Bu bireyin oluşturabileceği gamet çeşitlerinden kaç tanesi '
          'hem ${alel(ilk)} hem ${alel(son)} alelini birlikte taşır?',
          1 << (n - h),
          [
            1 << n,
            if (n >= 1) 1 << (n - 1),
            if (n >= 2) 1 << (n - 2),
            1 << (n + 1),
            n,
            2 * n,
          ],
          h == 0
              ? '$ortak Sorulan iki alel de homozigot gen çiftlerine ait '
                    'olduğundan gamet çeşitlerinin tamamında bulunur: ${1 << n}.'
              : '$ortak Sorulan alellerden $h tanesi heterozigot gen çiftine '
                    'aittir; her biri çeşit sayısını yarıya indirir: '
                    '${1 << n} / ${1 << h} = ${1 << (n - h)}.',
          positive: true,
        );
      case 3 || 8:
        final p = hetler.first;
        final secim = (c == 3 ? [p, (p + 2) % k, (p + 4) % k] : [p, (p + 3) % k])
          ..sort();
        final h = secim.where((q) => d[q] == 1).length;
        final adlar = secim.map(alel).toList();
        final liste = c == 3
            ? '${adlar[0]}, ${adlar[1]} ve ${adlar[2]}'
            : '${adlar[0]} ve ${adlar[1]}';
        return _olasilik(
          '$giris Bu bireyin oluşturduğu bir gametin $liste alellerini '
          'birlikte taşıma olasılığı kaçtır?',
          1,
          1 << h,
          [(1, 1 << n), (1, 1 << secim.length), (1, 1 << (h + 1)), (1, 1 << (h - 1)), (1, secim.length)],
          'Heterozigot gen çiftinden gelen bir alelin gamete geçme olasılığı '
          '1/2, homozigot gen çiftinden gelen alelin 1 olur. Sorulan '
          'alellerden $h tanesi heterozigot gen çiftine aittir: '
          '(1/2)${_ust(h)} = 1/${1 << h}.',
        );
      default:
        final z = [...d];
        final int n2;
        if (n >= 2) {
          final t = (1 + a % 2) < n ? 1 + a % 2 : n - 1;
          for (final q in hetler.take(t)) {
            z[q] = q.isEven ? 0 : 2;
          }
          n2 = n - t;
        } else {
          final homlar = [
            for (var q = 0; q < k; q++)
              if (d[q] != 1) q,
          ];
          for (final q in homlar.take(2)) {
            z[q] = 1;
          }
          n2 = 3;
        }
        return kesirli(
          'Genleri bağımsız olan iki bireyden birincisinin genotipi $g, '
          'ikincisinin genotipi ${_genotipYaz(harf, z)} biçimindedir. Birinci bireyin '
          'oluşturabileceği gamet çeşidi sayısı, ikinci bireyin '
          'oluşturabileceği gamet çeşidi sayısının kaç katıdır?',
          1 << n,
          1 << n2,
          [
            (n, n2),
            (1 << n2, 1 << n),
            (((1 << n) - (1 << n2)).abs(), 1),
            (1 << n, 1),
            (2 * (n - n2).abs(), 1),
            (1 << n2, 1),
          ],
          'Birinci bireyde $n, ikinci bireyde $n2 heterozigot gen çifti vardır. '
          'Gamet çeşidi sayıları 2${_ust(n)} = ${1 << n} ve 2${_ust(n2)} = '
          '${1 << n2} olur; oran ${kesir(1 << n, 1 << n2)} bulunur.',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 4. AB0 ve Rh kan grupları ─────────────────────────

// Çocuklarda birden çok kan grubu fenotipi çıkabilen 23 anne–baba çifti.
const _aboCiftler = [
  ('A0', 'B0'), ('B0', 'A0'), ('A0', 'A0'), ('B0', 'B0'), ('AB', 'AB'), //
  ('A0', 'AB'), ('AB', 'A0'), ('B0', 'AB'), ('AB', 'B0'), ('A0', '00'), //
  ('00', 'A0'), ('B0', '00'), ('00', 'B0'), ('AB', '00'), ('00', 'AB'), //
  ('AA', 'B0'), ('B0', 'AA'), ('A0', 'BB'), ('BB', 'A0'), ('AA', 'AB'), //
  ('AB', 'AA'), ('BB', 'AB'), ('AB', 'BB'),
];

String _aboFenotip(String g) => switch (g) {
  'AA' || 'A0' => 'A',
  'BB' || 'B0' => 'B',
  'AB' => 'AB',
  _ => '0',
};

/// Bir çiftin çocuklarında görülebilecek AB0 fenotip ve genotipleri:
/// (hedef metni, 4 üzerinden pay).
List<(String, int)> _aboHedefler(String anne, String baba) {
  const sira = 'AB0';
  final fen = <String, int>{}, gen = <String, int>{};
  for (final x in anne.split('')) {
    for (final y in baba.split('')) {
      final g = sira.indexOf(x) <= sira.indexOf(y) ? '$x$y' : '$y$x';
      gen[g] = (gen[g] ?? 0) + 1;
      final f = _aboFenotip(g);
      fen[f] = (fen[f] ?? 0) + 1;
    }
  }
  return [
    for (final e in fen.entries) ('${e.key} kan gruplu', e.value),
    for (final e in gen.entries) ('kan grubu genotipi ${e.key} olan', e.value),
  ];
}

// (anne Rh genotipi, baba Rh genotipi, hedef, 4 üzerinden pay)
const _rhBaskin = 'Rh bakımından homozigot baskın (RR)';
const _rhHet = 'Rh bakımından heterozigot (Rr)';
const _rhCekinik = 'Rh bakımından homozigot çekinik (rr)';
const _rhDurumlar = [
  ('Rr', 'Rr', 'Rh(+)', 3), ('Rr', 'Rr', 'Rh(−)', 1), //
  ('Rr', 'Rr', _rhBaskin, 1), ('Rr', 'Rr', _rhHet, 2), //
  ('Rr', 'rr', 'Rh(+)', 2), ('Rr', 'rr', 'Rh(−)', 2), //
  ('rr', 'Rr', 'Rh(+)', 2), ('rr', 'Rr', 'Rh(−)', 2), //
  ('RR', 'Rr', _rhBaskin, 2), ('RR', 'Rr', _rhHet, 2), //
  ('Rr', 'RR', _rhBaskin, 2), ('Rr', 'RR', _rhHet, 2), //
  ('RR', 'Rr', 'Rh(+)', 4), ('Rr', 'RR', 'Rh(+)', 4), ('RR', 'rr', 'Rh(+)', 4), //
  ('rr', 'RR', 'Rh(+)', 4), ('rr', 'rr', 'Rh(−)', 4), ('RR', 'RR', 'Rh(+)', 4), //
  ('', '', '', 4), ('Rr', 'Rr', _rhCekinik, 1),
];

/// Rh genotipinin harf büyüklüğünden bağımsız okunabilen yazımı.
String _rhYaz(String g) => switch (g) {
  'RR' => 'RR (homozigot Rh pozitif)',
  'Rr' => 'Rr (heterozigot Rh pozitif)',
  _ => 'rr (Rh negatif)',
};

final _f04 = lmAile(
  'biy_kan_grubu',
  'AB0 ve Rh kan gruplarında çaprazlama olasılığı',
  Topic.biology,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final (anne, baba) = _aboCiftler[a % 23];
    final (anneRh, babaRh, rhHedef, rhPay) = _rhDurumlar[b * 7 % 20];
    final rhVar = rhHedef.isNotEmpty;
    final hedefler = _aboHedefler(anne, baba);
    final t = c + (a >= 23 ? 10 : 0);
    final (aboHedef, aboPay) = hedefler[t % hedefler.length];
    final cins = t ~/ hedefler.length % 3; // 0: belirtilmez, 1: kız, 2: erkek
    final hedef =
        '$aboHedef${rhVar ? ' ve $rhHedef' : ''}'
        '${const ['', ' bir kız', ' bir erkek'][cins]}';
    final n = aboPay * rhPay, d = cins == 0 ? 16 : 32;
    final carpanlar = [
      kesir(aboPay, 4),
      if (rhVar) kesir(rhPay, 4),
      if (cins != 0) '1/2',
    ];
    return _olasilik(
      'AB0 kan grubu sisteminde A ve B alelleri eş baskın, 0 aleli '
      'çekiniktir${rhVar ? '; Rh(+) aleli (R), Rh(−) aleline (r) baskındır' : ''}. '
      'Kan grubu genotipi $anne${rhVar ? ' ${_rhYaz(anneRh)}' : ''} olan bir '
      'anne ile $baba${rhVar ? ' ${_rhYaz(babaRh)}' : ''} olan bir babanın '
      'doğacak bir çocuğunun '
      '$hedef olma olasılığı kaçtır?',
      n,
      d,
      [
        (aboPay * rhPay, 16),
        (aboPay, cins == 0 ? 4 : 8),
        (aboPay, 4),
        (d - n, d),
        (aboPay + rhPay, 8),
        (rhPay, 8),
      ],
      '$anne × $baba çaprazlamasında istenen AB0 sonucunun olasılığı '
      '${kesir(aboPay, 4)} olur'
      '${rhVar ? '; $anneRh × $babaRh çaprazlamasında istenen Rh sonucunun olasılığı ${kesir(rhPay, 4)} olur' : ''}'
      '${cins != 0 ? '; istenen cinsiyetin olasılığı 1/2 olur' : ''}. '
      '${carpanlar.length == 1 ? 'İstenen olasılık' : 'Bağımsız olasılıklar çarpılır: ${carpanlar.join(' · ')} ='} '
      '${kesir(n, d)}${carpanlar.length == 1 ? ' bulunur' : ''}.',
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 5. X'e bağlı çekinik kalıtım ─────────────────────────

// (hastalık adı, hasta olanı niteleyen söz, hasta olmayanı niteleyen söz)
const _xHastaliklar = [
  ('Kırmızı-yeşil renk körlüğü', 'renk körü', 'renk körü olmayan'),
  ('Hemofili', 'hemofili hastası', 'hemofili hastası olmayan'),
  (
    'Kalıtsal bir enzim eksikliği',
    'enzim eksikliği görülen',
    'enzim eksikliği görülmeyen',
  ),
];

// (anne: 0 taşıyıcı, 1 hasta, 2 alel taşımayan; baba: 0 sağlam, 1 hasta;
//  hedef türü; pay; payda)
const _xDurumlar = [
  (0, 0, 0, 1, 4), (0, 0, 2, 1, 4), (0, 0, 3, 1, 4), (0, 0, 4, 1, 4), //
  (0, 0, 5, 1, 4), (0, 0, 6, 3, 4), (0, 0, 7, 1, 2), (0, 0, 8, 1, 2), //
  (0, 0, 9, 1, 2), (0, 1, 0, 1, 4), (0, 1, 1, 1, 4), (0, 1, 2, 1, 4), //
  (0, 1, 3, 1, 2), (0, 1, 4, 1, 4), (0, 1, 6, 1, 2), (0, 1, 7, 1, 2), //
  (0, 1, 8, 1, 2), (0, 1, 10, 1, 2), (1, 0, 0, 1, 2), (1, 0, 2, 1, 2), //
  (1, 0, 3, 1, 2), (1, 0, 6, 1, 2), (2, 1, 2, 1, 2), (2, 1, 4, 1, 2), //
  (2, 1, 8, 1, 1),
];

final _f05 = lmAile(
  'biy_eseye_bagli',
  'X kromozomuna bağlı çekinik kalıtımda olasılık',
  Topic.biology,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final (anneX, babaX, tur, xPay, xPayda) = _xDurumlar[(a * 7) % 25];
    final (ad, hasta, saglam) = _xHastaliklar[c % 3];
    final (anne, baba) = _aboCiftler[b];
    final hedefler = _aboHedefler(anne, baba);
    final (abo, aboPay) = hedefler[(c ~/ 3 + a) % hedefler.length];
    final anneSoz = switch (anneX) {
      0 => 'bu özellik bakımından taşıyıcı',
      1 => hasta,
      _ => 'çekinik aleli taşımayan',
    };
    final babaSoz = babaX == 0 ? saglam : hasta;
    final soru = switch (tur) {
      0 => 'doğacak bir çocuğunun $abo ve $hasta bir erkek olma',
      1 => 'doğacak bir çocuğunun $abo ve $hasta bir kız olma',
      2 => 'doğacak bir çocuğunun $abo ve taşıyıcı bir kız olma',
      3 => 'doğacak bir çocuğunun $abo ve $hasta bir çocuk olma',
      4 => 'doğacak bir çocuğunun $abo ve $saglam bir erkek olma',
      5 => 'doğacak bir çocuğunun $abo ve çekinik aleli taşımayan bir kız olma',
      6 => 'doğacak bir çocuğunun $abo ve $saglam bir çocuk olma',
      7 => 'doğacak bir erkek çocuğunun $abo ve $hasta bir birey olma',
      8 => 'doğacak bir kız çocuğunun $abo ve taşıyıcı bir birey olma',
      9 => 'doğacak bir çocuğunun $abo ve $saglam bir kız olma',
      _ => 'doğacak bir kız çocuğunun $abo ve $hasta bir birey olma',
    };
    final xAciklama = switch ((anneX, babaX)) {
      (0, 0) =>
        'Taşıyıcı anne ile hasta olmayan babanın çocukları eşit olasılıkla '
            'alel taşımayan kız, taşıyıcı kız, sağlam erkek ve hasta erkek olur',
      (0, 1) =>
        'Taşıyıcı anne ile hasta babanın çocukları eşit olasılıkla taşıyıcı '
            'kız, hasta kız, sağlam erkek ve hasta erkek olur',
      (1, 0) =>
        'Hasta anne ile hasta olmayan babanın kızlarının tümü taşıyıcı, '
            'erkeklerinin tümü hasta olur',
      _ =>
        'Alel taşımayan anne ile hasta babanın kızlarının tümü taşıyıcı, '
            'erkeklerinin tümü sağlam olur',
    };
    final n = xPay * aboPay, d = xPayda * 4;
    return _olasilik(
      '$ad, X kromozomunda taşınan çekinik bir alelle kalıtılır. AB0 kan '
      'grubu sisteminde A ve B alelleri eş baskın, 0 aleli çekiniktir. Kan '
      'grubu genotipi $anne olan, $anneSoz bir anne ile kan grubu genotipi '
      '$baba olan, $babaSoz bir babanın $soru olasılığı kaçtır?',
      n,
      d,
      [
        (xPay, xPayda),
        (aboPay, 4),
        (n, 2 * d),
        (2 * n, d),
        (xPay * 4 + aboPay * xPayda, 2 * d),
        (d - n, d),
      ],
      '$xAciklama; X kromozomuna bağlı özellik için istenen sonucun olasılığı '
      '${kesir(xPay, xPayda)} olur. $anne × $baba çaprazlamasında istenen kan '
      'grubu sonucunun olasılığı ${kesir(aboPay, 4)} olur. Çarpım: '
      '${kesir(xPay, xPayda)} · ${kesir(aboPay, 4)} = ${kesir(n, d)}.',
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 6. Çok alellilik ve baskınlık ilişkileri ─────────────────────────

const _altRakam = ['₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉'];

/// 2–6 alelli karakterler için baskınlık dizileri: (alel sayısı, eşitlik
/// yerleri). Ardışık iki “=” bulunmaz; her “=” ayrı bir fenotip ekler.
final List<(int, List<bool>)> _alelDizileri = [
  for (var n = 2; n <= 6; n++)
    for (var maske = 0; maske < 1 << (n - 1); maske++)
      if (maske & (maske >> 1) == 0)
        (n, [for (var j = 0; j < n - 1; j++) maske >> j & 1 == 1]),
];

final _f06 = lmAile(
  'biy_alel',
  'Çok alellilikte genotip ve fenotip çeşidi sayısı',
  Topic.biology,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    // 31 diziden birincisi için 25, ikincisi için 20 ayrı seçim; ikinci
    // karakterde iki alelli eş baskın dizi (sıra 1) kullanılmaz.
    final (n1, es1) = _alelDizileri[a * 5 % 31];
    final (n2, es2) = _alelDizileri[2 + (b * 7 + 3) % 29];
    String iliski(String harf, int n, List<bool> es) {
      final sb = StringBuffer('$harf${_altRakam[1]}');
      for (var j = 1; j < n; j++) {
        sb.write(' ${es[j - 1] ? '=' : '>'} $harf${_altRakam[j + 1]}');
      }
      return sb.toString();
    }

    final e1 = es1.where((x) => x).length, e2 = es2.where((x) => x).length;
    final g1 = n1 * (n1 + 1) ~/ 2, g2 = n2 * (n2 + 1) ~/ 2;
    final h1 = n1 * (n1 - 1) ~/ 2, h2 = n2 * (n2 - 1) ~/ 2;
    final f1 = n1 + e1, f2 = n2 + e2;
    final esVar = e1 + e2 > 0;
    final giris =
        'Diploit bir canlı türünde iki karakter, farklı kromozomlarda bulunan '
        'genlerle belirlenir. Birinci karakterin alelleri arasındaki ilişki '
        '${iliski('A', n1, es1)}, ikinci karakterin alelleri arasındaki ilişki '
        '${iliski('B', n2, es2)} biçimindedir (“>” baskınlığı gösterir'
        '${esVar ? '; “=” ile bağlanan iki alelin heterozigot durumunda eş ya da eksik baskınlık nedeniyle ayrı bir fenotip oluşur' : ''}).';
    final sayim =
        'Birinci karakterde $n1 alel vardır: $g1 genotip ($n1 homozigot, $h1 '
        'heterozigot); ikinci karakterde $n2 alel vardır: $g2 genotip ($n2 '
        'homozigot, $h2 heterozigot).';
    final (String soru, int yanit, List<int> aday, String sonuc) = switch (c) {
      0 => (
        'iki karakter bakımından en çok kaç çeşit genotip bulunabilir?',
        g1 * g2,
        [g1 + g2, n1 * n2, f1 * f2, n1 * n1 * n2 * n2],
        'Toplam genotip çeşidi $g1 · $g2 = ${g1 * g2} olur.',
      ),
      1 => (
        'iki karakter bakımından en çok kaç çeşit fenotip görülebilir?',
        f1 * f2,
        [f1 + f2, n1 * n2, g1 * g2, (n1 + e1 + 1) * f2],
        'Fenotip çeşidi, alel sayısına “=” ile bağlanan alel çifti sayısı '
            'eklenerek bulunur: birinci karakterde $n1 + $e1 = $f1, ikinci '
            'karakterde $n2 + $e2 = $f2. Toplam $f1 · $f2 = ${f1 * f2} olur.',
      ),
      2 => (
        'iki karakter bakımından da homozigot olan en çok kaç çeşit genotip '
            'bulunabilir?',
        n1 * n2,
        [n1 + n2, g1 * g2, h1 * h2, 2 * n1 * n2],
        'İki karakterde de homozigot genotip çeşidi $n1 · $n2 = ${n1 * n2} '
            'olur.',
      ),
      3 => (
        'iki karakter bakımından da heterozigot olan en çok kaç çeşit genotip '
            'bulunabilir?',
        h1 * h2,
        [h1 + h2, n1 * n2, g1 * g2, n1 * h2],
        'İki karakterde de heterozigot genotip çeşidi $h1 · $h2 = ${h1 * h2} '
            'olur.',
      ),
      4 => (
        'birinci karakter bakımından homozigot, ikinci karakter bakımından '
            'heterozigot olan en çok kaç çeşit genotip bulunabilir?',
        n1 * h2,
        [h1 * n2, n1 + h2, n1 * n2, h1 * h2],
        'İstenen genotip çeşidi $n1 · $h2 = ${n1 * h2} olur.',
      ),
      5 => (
        'iki karakter bakımından bulunabilecek genotip çeşidi sayısı, '
            'görülebilecek fenotip çeşidi sayısından kaç fazladır?',
        g1 * g2 - f1 * f2,
        [g1 + g2 - f1 - f2, g1 * g2 - n1 * n2, (g1 - f1) * (g2 - f2), g1 * g2],
        'Fenotip çeşidi birinci karakterde $n1 + $e1 = $f1, ikincide '
            '$n2 + $e2 = $f2 olur. Fark $g1 · $g2 − $f1 · $f2 = '
            '${g1 * g2 - f1 * f2} bulunur.',
      ),
      6 => (
        'en az bir karakter bakımından heterozigot olan en çok kaç çeşit '
            'genotip bulunabilir?',
        g1 * g2 - n1 * n2,
        [h1 * h2, h1 + h2, g1 * g2, n1 * h2 + h1 * n2],
        'Toplam genotip çeşidinden iki karakterde de homozigot olanlar '
            'çıkarılır: $g1 · $g2 − $n1 · $n2 = ${g1 * g2 - n1 * n2}.',
      ),
      7 => (
        'birinci karakter bakımından heterozigot, ikinci karakter bakımından '
            'homozigot olan en çok kaç çeşit genotip bulunabilir?',
        h1 * n2,
        [n1 * h2, h1 + n2, n1 * n2, h1 * h2],
        'İstenen genotip çeşidi $h1 · $n2 = ${h1 * n2} olur.',
      ),
      8 => (
        'yalnızca bir karakter bakımından homozigot olan en çok kaç çeşit '
            'genotip bulunabilir?',
        n1 * h2 + h1 * n2,
        [n1 * n2, n1 * h2, h1 * n2, g1 * g2 - h1 * h2],
        'İstenen genotip çeşidi $n1 · $h2 + $h1 · $n2 = '
            '${n1 * h2 + h1 * n2} olur.',
      ),
      _ => (
        'en az bir karakter bakımından homozigot olan en çok kaç çeşit genotip '
            'bulunabilir?',
        g1 * g2 - h1 * h2,
        [n1 * n2, n1 + n2, g1 * g2, n1 * h2 + h1 * n2],
        'Toplam genotip çeşidinden iki karakterde de heterozigot olanlar '
            'çıkarılır: $g1 · $g2 − $h1 · $h2 = ${g1 * g2 - h1 * h2}.',
      ),
    };
    return sayisal(
      '$giris Bu türün popülasyonunda $soru',
      yanit,
      aday,
      '$sayim $sonuc',
      positive: true,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 7. Bölünme evrelerinde kromozom ve DNA ─────────────────────────

// (nicelik, haploit kromozom sayısı n cinsinden katsayı)
const _kromozomNicelikleri = [
  ('vücut hücrelerinin G1 evresindeki kromozom sayısı', 2),
  ('mitozun profaz evresindeki bir hücrenin kromatit sayısı', 4),
  ('mitozun metafaz evresindeki bir hücrenin kromozom sayısı', 2),
  ('mitozun metafaz evresindeki bir hücrenin kromatit sayısı', 4),
  ('mitozun anafaz evresindeki bir hücrenin toplam kromozom sayısı', 4),
  ('mitozun anafaz evresinde her bir kutba çekilen kromozom sayısı', 2),
  ('mitoz sonunda oluşan yavru hücrelerin her birindeki kromozom sayısı', 2),
  ('mayozun profaz I evresinde oluşan tetrat sayısı', 1),
  ('mayozun profaz I evresindeki bir hücrenin kromatit sayısı', 4),
  ('mayozun metafaz I evresindeki bir hücrenin kromozom sayısı', 2),
  ('mayozun anafaz I evresinde her bir kutba çekilen kromozom sayısı', 1),
  ('mayoz I sonunda oluşan hücrelerin her birindeki kromozom sayısı', 1),
  ('mayoz I sonunda oluşan hücrelerin her birindeki kromatit sayısı', 2),
  ('mayozun metafaz II evresindeki bir hücrenin kromozom sayısı', 1),
  ('mayozun metafaz II evresindeki bir hücrenin kromatit sayısı', 2),
  ('mayozun anafaz II evresindeki bir hücrenin toplam kromozom sayısı', 2),
  ('mayoz sonunda oluşan gametlerin her birindeki kromozom sayısı', 1),
  ('mayozun profaz I evresinde sinapsis yapan homolog kromozom çifti sayısı', 1),
  ('mayozun anafaz II evresinde her bir kutba çekilen kromozom sayısı', 1),
  ('interfazın G2 evresindeki bir vücut hücresinin kromatit sayısı', 4),
];

// Verilen nicelik için iki seçenek; katsayısı sorulanınkinden farklı olan
// kullanılır. On altı sıra da birbirinden farklıdır.
const _kromozomVerilen = [
  (0, 16), (3, 9), (7, 1), (11, 6), (4, 13), (14, 8), (10, 19), (15, 17), //
];

// (nicelik, gamet DNA miktarı cinsinden katsayı)
const _dnaNicelikleri = [
  ('G1 evresindeki bir vücut hücresinin DNA miktarı', 2),
  ('G2 evresindeki bir vücut hücresinin DNA miktarı', 4),
  ('mitozun metafaz evresindeki bir hücrenin DNA miktarı', 4),
  ('mitoz sonunda oluşan yavru hücrelerin her birinin DNA miktarı', 2),
  ('mayozun profaz I evresindeki bir hücrenin DNA miktarı', 4),
  ('mayoz I sonunda oluşan hücrelerin her birinin DNA miktarı', 2),
  ('mayozun metafaz II evresindeki bir hücrenin DNA miktarı', 2),
  ('mayoz sonunda oluşan gametlerin her birinin DNA miktarı', 1),
  ('mitozun anafaz evresindeki bir hücrenin toplam DNA miktarı', 4),
  ('mayozun anafaz I evresindeki bir hücrenin toplam DNA miktarı', 4),
  ('mayozun anafaz II evresindeki bir hücrenin toplam DNA miktarı', 2),
  ('döllenmeyle oluşan zigotun DNA eşlenmesinden önceki DNA miktarı', 2),
];
const _dnaVerilen = [(0, 1), (7, 3), (4, 5), (2, 6)];

String _kat(int m, String birim) => m == 1 ? birim : '$m$birim';

final _f07 = lmAile(
  'biy_kromozom',
  'Mitoz ve mayoz evrelerinde kromozom ve DNA miktarı',
  Topic.biology,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    if (c % 5 == 4) {
      // DNA miktarı: 40 ayrı (sorulan, verilen) ikilisi.
      final x = a + 2; // gametteki DNA miktarı (pikogram)
      final u = 2 * b + (c == 9 ? 1 : 0);
      final (sorulan, ms) = _dnaNicelikleri[u % 12];
      final (i1, i2) = _dnaVerilen[u ~/ 12];
      final (verilen, mv) = _dnaNicelikleri[i1].$2 != ms
          ? _dnaNicelikleri[i1]
          : _dnaNicelikleri[i2];
      return sayisal(
        'Bir canlı türünde $verilen ${mv * x} pikogram olarak ölçülmüştür. '
        'Buna göre bu türde $sorulan kaç pikogramdır?',
        ms * x,
        [x, 2 * x, 4 * x, 8 * x, mv * x],
        'Gametteki DNA miktarı x ile gösterilirse G1 evresinde 2x, eşlenmeden '
        'sonra 4x, mayoz I sonunda 2x, mayoz II sonunda x olur. Verilen değer '
        '${_kat(mv, 'x')} olduğundan x = $x pikogramdır. Sorulan değer '
        '${_kat(ms, 'x')} = ${ms * x} pikogram olur.',
        positive: true,
      );
    }
    final n = a + 3; // haploit kromozom sayısı
    final (sorulan, ms) = _kromozomNicelikleri[b];
    final (i1, i2) = _kromozomVerilen[c < 4 ? c : c - 1];
    final (verilen, mv) = _kromozomNicelikleri[i1].$2 != ms
        ? _kromozomNicelikleri[i1]
        : _kromozomNicelikleri[i2];
    return sayisal(
      'Bir canlı türünde $verilen ${mv * n} olarak belirlenmiştir. Buna göre '
      'bu türde $sorulan kaçtır?',
      ms * n,
      [n, 2 * n, 4 * n, 8 * n, mv * n],
      'Haploit kromozom sayısı n ile gösterilirse verilen sayı '
      '${_kat(mv, 'n')} değerine karşılık gelir; buradan n = $n, 2n = ${2 * n} '
      'bulunur. Sorulan sayı ${_kat(ms, 'n')} = ${ms * n} olur.',
      positive: true,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 8. Art arda bölünmelerde hücre sayısı ─────────────────────────

const _kesirSoz = ['tamamı', 'yarısı', 'dörtte biri', 'dörtte üçü'];
const _kesirPay = [4, 2, 1, 3]; // dörtte kaç

final _f08 = lmAile(
  'biy_bolunme_sayisi',
  'Art arda bölünmelerle oluşan hücre sayısı',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = a + 2; // başlangıçtaki hücre sayısı
    final n = 2 + b % 5; // bölünme sayısı
    final j = b ~/ 5;
    final kat = 1 << n;
    final son = k * kat;
    final dk = const [20, 30, 40, 60][j], sa = const [12, 18, 24, 36][j];
    final bakteri =
        'Uygun koşullarda $dk dakikada bir ikiye bölünerek çoğalan bir bakteri '
        'türü besiyerine ekiliyor ve hiçbir bakteri ölmüyor.';
    final kultur =
        'Bir doku kültüründeki hücrelerin her biri $sa saatte bir mitozla '
        'bölünüyor ve hiçbir hücre ölmüyor.';
    final bolunmeDk =
        'Geçen sürede ${n * dk} / $dk = $n bölünme gerçekleşir; her bölünmede '
        'sayı iki katına çıkar.';
    final bolunmeSa =
        'Geçen sürede ${n * sa} / $sa = $n bölünme gerçekleşir; her bölünmede '
        'sayı iki katına çıkar.';
    switch (c) {
      case 0:
        return sayisal(
          '$bakteri Başlangıçta $k bakteri bulunduğuna göre ${n * dk} dakika '
          'sonra besiyerinde kaç bakteri bulunur?',
          son,
          [k * 2 * n, k * n, son ~/ 2, son * 2, k + kat],
          '$bolunmeDk Bakteri sayısı $k · 2${_ust(n)} = $son olur.',
          positive: true,
        );
      case 1:
        return sayisal(
          '$kultur Başlangıçta $k hücre bulunduğuna göre ${n * sa} saat sonra '
          'kültürde kaç hücre bulunur?',
          son,
          [k * 2 * n, k * n, son ~/ 2, son * 2, k + kat],
          '$bolunmeSa Hücre sayısı $k · 2${_ust(n)} = $son olur.',
          positive: true,
        );
      case 2:
        return sayisal(
          '$bakteri Başlangıçta $k bakteri bulunduğuna göre bakteri sayısının '
          '$son olması için kaç dakika geçmesi gerekir?',
          n * dk,
          [kat * dk, (n - 1) * dk, (n + 1) * dk, 2 * n * dk],
          'Bakteri sayısı $son / $k = $kat katına, yani 2${_ust(n)} katına '
          'çıkmıştır; bunun için $n bölünme gerekir. Süre $n · $dk = '
          '${n * dk} dakika olur.',
          positive: true,
        );
      case 3:
        return sayisal(
          'Bir doku kültüründeki hücreler eşit aralıklarla mitozla bölünüyor '
          've hiçbir hücre ölmüyor. Başlangıçta $k hücre bulunan kültürde '
          '${n * sa} saat sonra $son hücre sayıldığına göre bir hücrenin art '
          'arda iki bölünmesi arasında kaç saat geçmektedir?',
          sa,
          [n * sa ~/ kat, n * sa ~/ 2, n * sa ~/ (n + 1), sa * 2, sa ~/ 2],
          'Hücre sayısı $son / $k = $kat = 2${_ust(n)} katına çıkmıştır; '
          '${n * sa} saatte $n bölünme olmuştur. Bölünme aralığı '
          '${n * sa} / $n = $sa saat bulunur.',
          positive: true,
        );
      case 4:
        return sayisal(
          '$bakteri ${n * dk} dakika sonra besiyerinde $son bakteri '
          'sayıldığına göre başlangıçta kaç bakteri ekilmiştir?',
          k,
          [2 * k, son ~/ n, son ~/ (2 * n), 4 * k, k + n],
          '$bolunmeDk Başlangıçtaki sayı '
          '$son / 2${_ust(n)} = $son / $kat = $k olur.',
          positive: true,
        );
      case 5:
        final mayoz = son * _kesirPay[j] ~/ 4;
        return sayisal(
          'Bir memelinin testisinde $k eşey ana hücresi art arda $n kez mitoz '
          'geçiriyor. Oluşan hücrelerin ${_kesirSoz[j]} mayoz geçirdiğine göre '
          'en çok kaç sperm hücresi oluşur?',
          4 * mayoz,
          [mayoz, 2 * mayoz, 8 * mayoz, 4 * k * n, 4 * k],
          'Mitozlar sonunda $k · 2${_ust(n)} = $son hücre oluşur. Bunlardan '
          '$mayoz tanesi mayoz geçirir ve her biri 4 sperm verir: '
          '$mayoz · 4 = ${4 * mayoz}.',
          positive: true,
        );
      case 6:
        final mayoz = son * _kesirPay[j] ~/ 4;
        return sayisal(
          'Bir memelinin yumurtalığında $k eşey ana hücresi art arda $n kez '
          'mitoz geçiriyor. Oluşan hücrelerin ${_kesirSoz[j]} mayoz '
          'geçirdiğine göre en çok kaç yumurta hücresi oluşur?',
          mayoz,
          [4 * mayoz, 3 * mayoz, 2 * mayoz, son, k * n],
          'Mitozlar sonunda $k · 2${_ust(n)} = $son hücre oluşur. Bunlardan '
          '$mayoz tanesi mayoz geçirir; her mayozdan 1 yumurta ve 3 kutup '
          'hücresi oluştuğundan yumurta sayısı $mayoz olur.',
          positive: true,
        );
      case 7:
        return sayisal(
          '$kultur Başlangıçta $k hücre bulunan kültürde ${n * sa} saat '
          'içinde toplam kaç mitoz bölünme gerçekleşir?',
          son - k,
          [son, k * n, son - 1, son ~/ 2, n],
          '$bolunmeSa Hücre sayısı $k · 2${_ust(n)} = $son olur. Her mitoz '
          'hücre sayısını 1 artırdığından bölünme sayısı '
          '$son − $k = ${son - k} bulunur.',
          positive: true,
        );
      case 8:
        return sayisal(
          '$bakteri Başlangıçta $k bakteri bulunan besiyerinde ${n * dk} '
          'dakikalık sürenin son $dk dakikasında bakteri sayısı kaç artar?',
          son ~/ 2,
          [son, k, son ~/ 4, son - k, k * n],
          '$bolunmeDk Son bölünmeden önce '
          '$k · 2${_ust(n - 1)} = ${son ~/ 2}, sonra $son bakteri vardır; artış '
          '$son − ${son ~/ 2} = ${son ~/ 2} olur.',
          positive: true,
        );
      default:
        final mayoz = son * _kesirPay[j] ~/ 4;
        return sayisal(
          'Bir memelinin yumurtalığında $k eşey ana hücresi art arda $n kez '
          'mitoz geçiriyor. Oluşan hücrelerin ${_kesirSoz[j]} mayoz '
          'geçirdiğine göre mayozlar sonunda toplam kaç kutup hücresi oluşur?',
          3 * mayoz,
          [mayoz, 4 * mayoz, 2 * mayoz, 3 * son, 3 * k * n],
          'Mitozlar sonunda $k · 2${_ust(n)} = $son hücre oluşur. Bunlardan '
          '$mayoz tanesi mayoz geçirir; her mayozdan 1 yumurta ve 3 kutup '
          'hücresi oluştuğundan kutup hücresi sayısı $mayoz · 3 = '
          '${3 * mayoz} olur.',
          positive: true,
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 9. Chargaff kuralı ve hidrojen bağları ─────────────────────────

final _f09 = lmAile(
  'biy_dna_baz',
  'DNA molekülünde baz sayıları ve hidrojen bağı',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final ad = 10 * (a + 6), gu = 10 * (b + 4) + 5; // adenin, guanin
    final top = 2 * (ad + gu), hb = 2 * ad + 3 * gu;
    final p = 10 + a; // adenin yüzdesi
    final top2 = 200 * (b + 2);
    const kural =
        'Adenin timinle 2, guanin sitozinle 3 hidrojen bağı kurar; A = T ve '
        'G = C olur.';
    switch (c) {
      case 0:
        return sayisal(
          'Çift zincirli bir DNA molekülünde toplam $top nükleotit '
          'bulunmaktadır ve bunların $ad tanesi adenin içerir. Bu DNA '
          'molekülünde guanin içeren nükleotit sayısı kaçtır?',
          gu,
          [top - ad, 2 * gu, ad ~/ 2 + gu, top ~/ 2],
          'A = T olduğundan A + T = ${2 * ad} olur. G + C = $top − ${2 * ad} = '
          '${2 * gu} ve G = C olduğundan G = $gu bulunur.',
          positive: true,
        );
      case 1:
        return sayisal(
          'Çift zincirli bir DNA molekülünde $ad adenin ve $gu guanin '
          'nükleotidi vardır. Bu molekülün iki zinciri arasında toplam kaç '
          'hidrojen bağı bulunur?',
          hb,
          [3 * ad + 2 * gu, 2 * (ad + gu), 3 * (ad + gu), ad + gu],
          '$kural Hidrojen bağı sayısı 2 · $ad + 3 · $gu = $hb olur.',
          positive: true,
        );
      case 2:
        return sayisal(
          'Toplam $top nükleotit içeren çift zincirli bir DNA molekülünün iki '
          'zinciri arasında $hb hidrojen bağı vardır. Bu moleküldeki adenin '
          'sayısı kaçtır?',
          ad,
          [gu, top ~/ 2, hb - top ~/ 2, 2 * ad],
          'A + G = $top / 2 = ${top ~/ 2} ve 2A + 3G = $hb olur. İkinci '
          'eşitlikten birincinin iki katı çıkarılırsa G = $hb − $top = $gu, '
          'A = ${top ~/ 2} − $gu = $ad bulunur.',
          positive: true,
        );
      case 3:
        final si = 2 * (b + 2) * (50 - p);
        return sayisal(
          'Toplam $top2 nükleotit içeren çift zincirli bir DNA molekülünde '
          'nükleotitlerin %$p kadarı adenin içerir. Bu moleküldeki sitozin '
          'sayısı kaçtır?',
          si,
          [2 * (b + 2) * p, 2 * si, 2 * (b + 2) * (100 - p), si ~/ 2],
          'A = T olduğundan A + T = %${2 * p}, G + C = %${100 - 2 * p} ve '
          'C = %${50 - p} olur. Sitozin sayısı $top2 · ${50 - p} / 100 = $si '
          'bulunur.',
          positive: true,
        );
      case 4 || 5:
        final a1 = 20 + a, t1 = 15 + b;
        final g1 = 30 + (a + 2 * b) % 17, c1 = 25 + (2 * a + b) % 13;
        final zincir =
            'Bir DNA molekülünün zincirlerinden birinde $a1 adenin, $t1 timin, '
            '$g1 guanin ve $c1 sitozin nükleotidi vardır.';
        if (c == 4) {
          final h = 2 * (a1 + t1) + 3 * (g1 + c1);
          return sayisal(
            '$zincir Bu DNA molekülünün iki zinciri arasında toplam kaç '
            'hidrojen bağı bulunur?',
            h,
            [
              3 * (a1 + t1) + 2 * (g1 + c1),
              2 * a1 + 3 * g1,
              2 * (a1 + t1 + g1 + c1),
              2 * h,
            ],
            'Bir zincirdeki her A ve T karşı zincirle 2, her G ve C ise 3 '
            'hidrojen bağı kurar: 2 · ($a1 + $t1) + 3 · ($g1 + $c1) = $h.',
            positive: true,
          );
        }
        return sayisal(
          '$zincir Bu DNA molekülünün iki zincirinde toplam kaç adenin '
          'nükleotidi bulunur?',
          a1 + t1,
          [2 * a1, a1, a1 + c1, 2 * (a1 + t1)],
          'Verilen zincirdeki her timinin karşısında diğer zincirde bir adenin '
          'bulunur. Toplam adenin sayısı $a1 + $t1 = ${a1 + t1} olur.',
          positive: true,
        );
      case 6:
        final h = 2 * (b + 2) * (150 - p);
        return sayisal(
          'Toplam $top2 nükleotit içeren çift zincirli bir DNA molekülünde '
          'nükleotitlerin %$p kadarı timin içerir. Bu molekülün iki zinciri '
          'arasında toplam kaç hidrojen bağı bulunur?',
          h,
          [2 * (b + 2) * (100 + p), 2 * (b + 2) * 125, 2 * h, top2],
          'A = T = $top2 · $p / 100 = ${2 * (b + 2) * p}, G = C = $top2 · '
          '${50 - p} / 100 = ${2 * (b + 2) * (50 - p)} olur. Hidrojen bağı '
          'sayısı 2 · ${2 * (b + 2) * p} + 3 · ${2 * (b + 2) * (50 - p)} = $h '
          'bulunur.',
          positive: true,
        );
      case 7:
        return sayisal(
          'Çift zincirli bir DNA molekülünde $gu guanin nükleotidi vardır ve '
          'iki zincir arasında toplam $hb hidrojen bağı bulunur. Bu '
          'moleküldeki toplam nükleotit sayısı kaçtır?',
          top,
          [ad + gu, hb - gu, 2 * ad + gu, top + 2 * gu],
          'G–C çiftlerindeki bağ sayısı 3 · $gu = ${3 * gu} olur. A–T çifti '
          'sayısı ($hb − ${3 * gu}) / 2 = $ad bulunur. Toplam nükleotit '
          '2 · ($ad + $gu) = $top olur.',
          positive: true,
        );
      case 8:
        final q = 100 - 2 * p;
        final say = 2 * (b + 2) * p;
        return sayisal(
          'Toplam $top2 nükleotit içeren çift zincirli bir DNA molekülünde '
          'guanin ve sitozin nükleotitlerinin toplamı bütün nükleotitlerin '
          '%$q kadarıdır. Bu moleküldeki adenin sayısı kaçtır?',
          say,
          [2 * say, 2 * (b + 2) * q, (b + 2) * q, top2 ~/ 2 - say],
          'A + T = %${100 - q} olur ve A = T olduğundan A = %$p bulunur. '
          'Adenin sayısı $top2 · $p / 100 = $say olur.',
          positive: true,
        );
      default:
        // Timin yüzdesi adenin yüzdesiyle aynı tekliktedir ve ona eşit olmaz.
        var q = a % 2 + 12 + 2 * b;
        if (q >= p) q += 2;
        return sayisal(
          'Bir DNA molekülünün zincirlerinden birindeki nükleotitlerin %$p '
          'kadarı adenin, %$q kadarı timin içerir. Bu DNA molekülünün '
          'tamamında adenin içeren nükleotitlerin oranı yüzde kaçtır?',
          (p + q) ~/ 2,
          [p + q, p, q, 50 - (p + q) ~/ 2],
          'Karşı zincirde adenin oranı %$q, timin oranı %$p olur. İki zincir '
          'eşit uzunlukta olduğundan molekülün tamamında adenin oranı '
          '($p + $q) / 2 = ${(p + q) ~/ 2} bulunur.',
          positive: true,
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 10. Yarı korunumlu eşlenme ─────────────────────────

final _f10 = lmAile(
  'biy_replikasyon',
  'Yarı korunumlu DNA eşlenmesinde molekül sayıları',
  Topic.biology,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final k = a + 2; // başlangıçtaki bakteri (DNA) sayısı
    final n = 2 + b % 5, sure = const [20, 25, 30, 40][b ~/ 5];
    final n1 = 1 + b % 5, m = 1 + b ~/ 5; // iki aşamalı deney
    final top = k << n;
    const tek = 'Her bakteride tek bir DNA molekülü bulunduğu kabul ediliyor.';
    final agirdan =
        "DNA'larındaki azotun tamamı ¹⁵N (ağır azot) olan $k bakteri, azot "
        'kaynağı olarak yalnız ¹⁴N içeren besiyerine aktarılıyor. $sure '
        'dakikada bir bölünen bakteriler bu ortamda ${n * sure} dakika '
        'çoğalıyor. $tek';
    final ikiAsama =
        "DNA'larındaki azotun tamamı ¹⁵N (ağır azot) olan $k bakteri önce "
        'yalnız ¹⁴N içeren besiyerinde art arda $n1 kez, ardından yalnız ¹⁵N '
        'içeren besiyerinde art arda $m kez bölünüyor. $tek';
    final ozet =
        '${n * sure} / $sure = $n eşlenme sonunda $k · 2${_ust(n)} = $top DNA '
        'molekülü oluşur. Başlangıçtaki ${2 * k} ağır zincir korunur ve ayrı '
        'birer molekülde yer alır.';
    final melez2 = 2 * k * ((1 << n1) - 1), top2 = k << (n1 + m);
    final ozet2 =
        '¹⁴N ortamındaki $n1 eşlenmede $k · 2${_ust(n1 + 1)} − ${2 * k} = '
        '$melez2 hafif zincir sentezlenir. ¹⁵N ortamında yeni zincirlerin '
        'tümü ağırdır; her hafif zincir bir ağır zincirle eşleşerek melez '
        'molekül oluşturur.';
    switch (c) {
      case 0:
        return sayisal(
          '$agirdan Süre sonunda kaç DNA molekülü melezdir (bir zinciri ¹⁵N, '
          'diğer zinciri ¹⁴N içerir)?',
          2 * k,
          [k, top, top - 2 * k, k * n],
          '$ozet Melez molekül sayısı ${2 * k} olur.',
          positive: true,
        );
      case 1:
        return sayisal(
          '$agirdan Süre sonunda kaç DNA molekülünün her iki zinciri de ¹⁴N '
          'içerir?',
          top - 2 * k,
          [top, 2 * k, top - k, top ~/ 2],
          '$ozet Yalnız ¹⁴N içeren molekül sayısı $top − ${2 * k} = '
          '${top - 2 * k} olur.',
          positive: true,
        );
      case 2:
        return _olasilik(
          '$agirdan Süre sonunda melez DNA moleküllerinin (bir zinciri ¹⁵N, '
          'diğer zinciri ¹⁴N) sayısının bütün DNA moleküllerinin sayısına '
          'oranı kaçtır?',
          2 * k,
          top,
          [(1, 1 << n), (1, n), (top - 2 * k, top), (1, 2 * n), (2, n + 2)],
          '$ozet Oran ${2 * k} / $top = ${kesir(2 * k, top)} bulunur.',
        );
      case 3:
        return _olasilik(
          '$agirdan Süre sonunda her iki zinciri de ¹⁴N içeren DNA '
          'moleküllerinin sayısının bütün DNA moleküllerinin sayısına oranı '
          'kaçtır?',
          top - 2 * k,
          top,
          [(2 * k, top), (top - k, top), (1, 1 << n), (n - 1, n), (1, n)],
          '$ozet Yalnız ¹⁴N içeren molekül sayısı ${top - 2 * k} olduğundan '
          'oran ${top - 2 * k} / $top = ${kesir(top - 2 * k, top)} bulunur.',
        );
      case 4:
        return sayisal(
          "DNA'larındaki azotun tamamı ¹⁴N olan $k bakteri, azot kaynağı "
          'olarak yalnız ¹⁵N (ağır azot) içeren besiyerine aktarılıyor. $sure '
          'dakikada bir bölünen bakteriler bu ortamda ${n * sure} dakika '
          'çoğalıyor. $tek Süre sonunda DNA moleküllerindeki kaç '
          'polinükleotit zinciri ¹⁵N içerir?',
          2 * top - 2 * k,
          [2 * top, top - 2 * k, 2 * k, top - k],
          '${n * sure} / $sure = $n eşlenme sonunda $top DNA molekülü, yani '
          '${2 * top} zincir bulunur. Başlangıçtaki ${2 * k} zincir ¹⁴N '
          'içerir; ¹⁵N içeren zincir sayısı ${2 * top} − ${2 * k} = '
          '${2 * top - 2 * k} olur.',
          positive: true,
        );
      case 5:
        return sayisal(
          '$ikiAsama Son durumda kaç DNA molekülü melezdir (bir zinciri ¹⁵N, '
          'diğer zinciri ¹⁴N içerir)?',
          melez2,
          [2 * k, top2 - melez2, top2, k << n1],
          '$ozet2 Melez molekül sayısı $melez2 olur.',
          positive: true,
        );
      case 6:
        return sayisal(
          '$ikiAsama Son durumda kaç DNA molekülünün her iki zinciri de ¹⁵N '
          'içerir?',
          top2 - melez2,
          [melez2, top2, 2 * k, top2 - 2 * k],
          '$ozet2 Toplam $k · 2${_ust(n1 + m)} = $top2 molekülün $melez2 '
          'tanesi melezdir; kalan $top2 − $melez2 = ${top2 - melez2} molekül '
          'yalnız ¹⁵N içerir.',
          positive: true,
        );
      case 7:
        return sayisal(
          '$agirdan Süre sonunda DNA moleküllerindeki kaç polinükleotit '
          'zinciri ¹⁴N içerir?',
          2 * top - 2 * k,
          [2 * top, top - 2 * k, top, 2 * k],
          '$ozet Toplam ${2 * top} zincirin ${2 * k} tanesi ¹⁵N içerir; ¹⁴N '
          'içeren zincir sayısı ${2 * top} − ${2 * k} = ${2 * top - 2 * k} '
          'olur.',
          positive: true,
        );
      case 8:
        return sayisal(
          "DNA'larındaki azotun tamamı ¹⁵N (ağır azot) olan bakteriler, azot "
          'kaynağı olarak yalnız ¹⁴N içeren besiyerine aktarılıyor ve $sure '
          'dakikada bir bölünüyor. $tek Bir süre sonra besiyerindeki $top DNA '
          'molekülünden ${2 * k} tanesinin melez (bir zinciri ¹⁵N, diğer '
          'zinciri ¹⁴N) olduğu belirleniyor. Bakteriler bu ortamda kaç dakika '
          'çoğalmıştır?',
          n * sure,
          [(n - 1) * sure, (n + 1) * sure, (1 << n) * sure, 2 * n * sure],
          'Her ağır DNA iki melez molekül verdiğinden başlangıçta '
          '${2 * k} / 2 = $k bakteri vardır. $top / $k = ${1 << n} = '
          '2${_ust(n)} olduğundan $n eşlenme olmuştur; süre $n · $sure = '
          '${n * sure} dakikadır.',
          positive: true,
        );
      default:
        return _olasilik(
          '$ikiAsama Son durumda melez DNA moleküllerinin (bir zinciri ¹⁵N, '
          'diğer zinciri ¹⁴N) sayısının bütün DNA moleküllerinin sayısına '
          'oranı kaçtır?',
          melez2,
          top2,
          [
            (2 * k, top2),
            (top2 - melez2, top2),
            (1, 1 << m),
            (1, 1 << (n1 + m)),
            (1, n1 + m),
          ],
          '$ozet2 Toplam $k · 2${_ust(n1 + m)} = $top2 molekülün $melez2 '
          'tanesi melezdir; oran ${kesir(melez2, top2)} bulunur.',
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 11. Protein sentezinde sayısal ilişkiler ─────────────────────────

final _f11 = lmAile(
  'biy_protein_sentezi',
  'Protein sentezinde nükleotit, kodon ve amino asit',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final n1 = 50 + 4 * a, n2 = 31 + 5 * b; // zincirlerdeki amino asit sayıları
    final r = b + 2; // ribozom sayısı
    final m1 = 3 * (n1 + 1), m2 = 3 * (n2 + 1);
    final iki =
        'Bir bakteride sentezlenen bir protein iki polipeptit zincirinden '
        'oluşur; zincirlerden biri $n1, diğeri $n2 amino asit içerir.';
    const kodonKural =
        'Her amino asit bir kodonla şifrelenir; durdurma kodonunun amino asit '
        'karşılığı yoktur.';
    switch (c) {
      case 0:
        return sayisal(
          '$iki Bu proteinin iki zincirinin sentezi sırasında toplam kaç '
          'peptit bağı kurulur?',
          n1 + n2 - 2,
          [n1 + n2, n1 + n2 - 1, n1 + n2 + 2, 3 * (n1 + n2)],
          'Bir zincirdeki peptit bağı sayısı amino asit sayısından 1 eksiktir: '
          '($n1 − 1) + ($n2 − 1) = ${n1 + n2 - 2}.',
          positive: true,
        );
      case 1:
        return sayisal(
          '$iki Bu zincirlerin sentezinde kalıp olarak kullanılan iki mRNA '
          'molekülünün protein kodlayan bölgelerinde, durdurma kodonları da '
          'sayıldığında toplam kaç kodon bulunur?',
          n1 + n2 + 2,
          [n1 + n2, n1 + n2 + 1, 3 * (n1 + n2 + 2), n1 + n2 - 2],
          '$kodonKural Kodon sayısı ($n1 + 1) + ($n2 + 1) = ${n1 + n2 + 2} '
          'olur.',
          positive: true,
        );
      case 2:
        return sayisal(
          '$iki Bu zincirlerin sentezinde kalıp olarak kullanılan iki mRNA '
          'molekülünün protein kodlayan bölgelerinde, durdurma kodonları da '
          'sayıldığında toplam kaç nükleotit bulunur?',
          m1 + m2,
          [3 * (n1 + n2), n1 + n2 + 2, 6 * (n1 + n2 + 2), 3 * (n1 + n2 + 1)],
          '$kodonKural Kodon sayısı ($n1 + 1) + ($n2 + 1) = ${n1 + n2 + 2}, '
          'nükleotit sayısı 3 · ${n1 + n2 + 2} = ${m1 + m2} olur.',
          positive: true,
        );
      case 3:
        return sayisal(
          '$iki Bu iki zinciri şifreleyen çift zincirli DNA bölgelerinde, '
          'durdurma kodonlarının karşılıkları da sayıldığında toplam kaç '
          'nükleotit bulunur?',
          2 * (m1 + m2),
          [m1 + m2, 6 * (n1 + n2), 3 * (n1 + n2), 2 * (n1 + n2 + 2)],
          '$kodonKural mRNA üzerindeki kodon sayısı ${n1 + n2 + 2}, nükleotit '
          'sayısı ${m1 + m2} olur. DNA çift zincirli olduğundan nükleotit '
          'sayısı 2 · ${m1 + m2} = ${2 * (m1 + m2)} bulunur.',
          positive: true,
        );
      case 4 || 5:
        final mrna =
            'Bir bakteride, protein kodlayan bölgeleri durdurma kodonu dâhil '
            '$m1 ve $m2 nükleotitten oluşan iki mRNA molekülünden birer '
            'polipeptit zinciri sentezleniyor.';
        final cozum =
            '$kodonKural Kodon sayıları $m1 / 3 = ${n1 + 1} ve $m2 / 3 = '
            '${n2 + 1}, amino asit sayıları $n1 ve $n2 olur.';
        if (c == 4) {
          return sayisal(
            '$mrna Bu iki zincirde toplam kaç amino asit bulunur?',
            n1 + n2,
            [n1 + n2 + 2, n1 + n2 - 2, m1 + m2, n1 + n2 + 1],
            '$cozum Toplam $n1 + $n2 = ${n1 + n2} amino asit bulunur.',
            positive: true,
          );
        }
        return sayisal(
          '$mrna Bu iki zincirin sentezi sırasında toplam kaç peptit bağı '
          'kurulur?',
          n1 + n2 - 2,
          [n1 + n2 + 2, n1 + n2, n1 + n2 - 1, n1 + n2 + 1],
          '$cozum Peptit bağı sayısı ($n1 − 1) + ($n2 − 1) = ${n1 + n2 - 2} '
          'olur.',
          positive: true,
        );
      case 6:
        return sayisal(
          'Bir bakteride sentezlenen iki polipeptit zincirinden birinde '
          '${n1 - 1}, diğerinde ${n2 - 1} peptit bağı vardır. Bu zincirlerin '
          'mRNA moleküllerinde protein kodlayan bölgeler, durdurma kodonları '
          'dâhil toplam kaç nükleotitten oluşur?',
          m1 + m2,
          [3 * (n1 + n2 - 2), 3 * (n1 + n2), n1 + n2 + 2, 3 * (n1 + n2 + 1)],
          'Amino asit sayıları ${n1 - 1} + 1 = $n1 ve ${n2 - 1} + 1 = $n2 '
          'olur. $kodonKural Kodon sayısı ${n1 + n2 + 2}, nükleotit sayısı '
          '3 · ${n1 + n2 + 2} = ${m1 + m2} bulunur.',
          positive: true,
        );
      case 7:
        return sayisal(
          'Bir bakteride $n1 amino asitten oluşan bir polipeptidi şifreleyen '
          'mRNA molekülü, $r ribozom tarafından birer kez okunuyor ve her '
          'ribozom bir polipeptit zinciri sentezliyor. Bu sentezler sırasında '
          'toplam kaç molekül su açığa çıkar?',
          r * (n1 - 1),
          [r * n1, r * (n1 + 1), n1 - 1, r * (n1 - 1) - r],
          'Her zincirde $n1 − 1 = ${n1 - 1} peptit bağı kurulur ve her bağda '
          '1 molekül su açığa çıkar. Toplam $r · ${n1 - 1} = ${r * (n1 - 1)} '
          'molekül su oluşur.',
          positive: true,
        );
      case 8:
        return sayisal(
          'Bir bakteride protein kodlayan bölgesi durdurma kodonu dâhil $m1 '
          'nükleotitten oluşan bir mRNA molekülü, $r ribozom tarafından birer '
          'kez okunuyor ve her ribozom bir polipeptit zinciri sentezliyor. Bu '
          'sentezlerde toplam kaç amino asit kullanılır?',
          r * n1,
          [r * (n1 + 1), r * (n1 - 1), n1, r * m1],
          '$kodonKural Kodon sayısı $m1 / 3 = ${n1 + 1}, bir zincirdeki amino '
          'asit sayısı $n1 olur. $r zincir için $r · $n1 = ${r * n1} amino '
          'asit kullanılır.',
          positive: true,
        );
      default:
        return sayisal(
          'Bir bakteride iki polipeptit zincirini şifreleyen çift zincirli DNA '
          'bölgeleri, durdurma kodonlarının karşılıkları dâhil ${2 * m1} ve '
          '${2 * m2} nükleotitten oluşur. Bu iki zincirin sentezi sırasında '
          'ribozomlara toplam kaç amino asit taşınır?',
          n1 + n2,
          [n1 + n2 + 2, 2 * (n1 + n2), n1 + n2 - 2, n1 + n2 + 1],
          'Kalıp zincirlerdeki nükleotit sayıları ${2 * m1} / 2 = $m1 ve '
          '${2 * m2} / 2 = $m2, kodon sayıları ${n1 + 1} ve ${n2 + 1} olur. '
          'Durdurma kodonlarına amino asit taşınmadığından toplam '
          '$n1 + $n2 = ${n1 + n2} amino asit taşınır.',
          positive: true,
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 12. Dehidrasyon sentezi ve hidroliz ─────────────────────────

final _f12 = lmAile(
  'biy_dehidrasyon',
  'Dehidrasyon ve hidrolizde su ve bağ sayıları',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final x = a + 2, y = b + 3;
    switch (c) {
      case 0:
        final p = 20 + 5 * a;
        return sayisal(
          'Bir hücrede her biri $p amino asitten oluşan $y polipeptit zinciri '
          'sentezleniyor. Bu sentezler sırasında toplam kaç molekül su açığa '
          'çıkar?',
          y * (p - 1),
          [y * p, y * (p + 1), p - 1, y * (p - 1) - y],
          'Bir zincirde $p − 1 = ${p - 1} peptit bağı kurulur ve her bağda 1 '
          'molekül su açığa çıkar: $y · ${p - 1} = ${y * (p - 1)}.',
          positive: true,
        );
      case 1:
        final p = 50 + 10 * a;
        return sayisal(
          'Sindirim sırasında her biri $p glikoz biriminden oluşan $y nişasta '
          'molekülü tamamen glikoza hidroliz ediliyor. Bu olayda toplam kaç '
          'molekül su harcanır?',
          y * (p - 1),
          [y * p, y * (p + 1), p - 1, y * p ~/ 2],
          'Bir moleküldeki $p − 1 = ${p - 1} glikozit bağının her biri 1 '
          'molekül su harcanarak koparılır: $y · ${p - 1} = ${y * (p - 1)}.',
          positive: true,
        );
      case 2:
        final p = 20 + 3 * b;
        return sayisal(
          'Bir hücrede $x molekül trigliserit (nötr yağ) ile $p amino asitten '
          'oluşan bir polipeptit zinciri sentezleniyor. Bu sentezler sırasında '
          'toplam kaç molekül su açığa çıkar?',
          3 * x + p - 1,
          [x + p - 1, 3 * x + p, 4 * x + p - 1, 3 * (x + p - 1)],
          'Bir trigliserit, 1 gliserol ile 3 yağ asidi arasında 3 ester bağı '
          'kurulurken 3 su verir: 3 · $x = ${3 * x}. Polipeptitte $p − 1 = '
          '${p - 1} su açığa çıkar. Toplam ${3 * x + p - 1} olur.',
          positive: true,
        );
      case 3:
        final p = 20 + 3 * b;
        return sayisal(
          'Sindirim sırasında $x molekül trigliserit (nötr yağ) ile $p glikoz '
          'biriminden oluşan bir glikojen molekülü yapı taşlarına kadar '
          'hidroliz ediliyor. Bu olayda toplam kaç yapı taşı molekülü oluşur?',
          4 * x + p,
          [3 * x + p, 3 * x + p - 1, 4 * x + p - 1, x + p],
          'Her trigliseritten 1 gliserol ve 3 yağ asidi, yani 4 molekül '
          'oluşur: 4 · $x = ${4 * x}. Glikojenden $p glikoz oluşur. Toplam '
          '${4 * x} + $p = ${4 * x + p} bulunur.',
          positive: true,
        );
      case 4:
        final p = 20 + 5 * a;
        return sayisal(
          'Bir hücrede eşit sayıda amino asit içeren $y polipeptit zincirinin '
          'sentezi sırasında toplam ${y * (p - 1)} molekül su açığa çıkıyor. '
          'Bu zincirlerin her birinde kaç amino asit bulunur?',
          p,
          [p - 1, p + 1, p - 2, y * (p - 1) ~/ (y + 1)],
          'Bir zincir için açığa çıkan su ${y * (p - 1)} / $y = ${p - 1} '
          'olur. Amino asit sayısı peptit bağı sayısından 1 fazladır: '
          '${p - 1} + 1 = $p.',
          positive: true,
        );
      case 5:
        final parca = a + 4, boy = b + 2;
        return sayisal(
          'Sindirim sırasında ${parca * boy} glikoz biriminden oluşan bir '
          'nişasta molekülü, her biri $boy glikoz içeren parçalara ayrılacak '
          'biçimde kısmen hidroliz ediliyor. Bu olayda kaç molekül su '
          'harcanır?',
          parca - 1,
          [parca, parca * boy - 1, parca * (boy - 1), parca + 1],
          'Molekül ${parca * boy} / $boy = $parca parçaya ayrılır. Bunun için '
          '$parca − 1 = ${parca - 1} glikozit bağı koparılır ve her bağ için 1 '
          'molekül su harcanır.',
          positive: true,
        );
      case 6:
        final p = 200 + 12 * a;
        return sayisal(
          'Bir hücrede toplam $p amino asit kullanılarak $y ayrı polipeptit '
          'zinciri sentezleniyor. Bu sentezler sırasında toplam kaç peptit '
          'bağı kurulur?',
          p - y,
          [p - 1, p, p + y, p - y - 1],
          'Her zincirde peptit bağı sayısı amino asit sayısından 1 eksiktir; '
          '$y zincir için toplam $p − $y = ${p - y} peptit bağı kurulur.',
          positive: true,
        );
      case 7:
        return sayisal(
          'Bir hücrede $x molekül trigliserit (nötr yağ) ile $y molekül '
          'disakkarit sentezleniyor. Bu sentezler sırasında toplam kaç molekül '
          'su açığa çıkar?',
          3 * x + y,
          [x + y, 3 * x + 2 * y, 4 * x + 2 * y, 3 * (x + y)],
          'Her trigliserit için 3, her disakkarit için 1 molekül su açığa '
          'çıkar: 3 · $x + $y = ${3 * x + y}.',
          positive: true,
        );
      case 8:
        final p1 = 30 + 4 * a, p2 = 21 + 5 * b;
        return sayisal(
          'Karaciğerde biri $p1, diğeri $p2 glikoz biriminden oluşan iki '
          'glikojen molekülü tamamen glikoza hidroliz ediliyor. Bu olayda '
          'toplam kaç molekül su harcanır?',
          p1 + p2 - 2,
          [p1 + p2, p1 + p2 - 1, p1 + p2 + 2, 2 * (p1 + p2)],
          'Her molekülde glikozit bağı sayısı glikoz sayısından 1 eksiktir: '
          '($p1 − 1) + ($p2 − 1) = ${p1 + p2 - 2}.',
          positive: true,
        );
      default:
        return sayisal(
          'Bir deney tüpünde ${x + 1} molekül dipeptit ile $y molekül tripeptit '
          'tamamen amino asitlerine hidroliz ediliyor. Bu olayda toplam kaç '
          'molekül su harcanır?',
          x + 1 + 2 * y,
          [x + 1 + y, 2 * (x + 1) + 3 * y, 2 * (x + 1) + 2 * y, x + 3 * y],
          'Bir dipeptitte 1, bir tripeptitte 2 peptit bağı vardır; her bağ '
          'için 1 molekül su harcanır: ${x + 1} + 2 · $y = ${x + 1 + 2 * y}.',
          positive: true,
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);
