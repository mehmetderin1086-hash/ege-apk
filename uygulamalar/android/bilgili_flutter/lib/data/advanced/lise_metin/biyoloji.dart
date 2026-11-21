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
  _f13,
  _f14,
  _f15,
  _f16,
  _f17,
  _f18,
  _f19,
  _f20,
];

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
          [k, top, top - 2 * k, 2 * top, k * n],
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
          [2 * k, top2 - melez2, top2, k << n1, k, 2 * melez2],
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

// ───────────────────────── 13. Ozmoz ─────────────────────────

// (kök üreteci, dış ortam daha derişikken doğru, iç ortam daha derişikken
//  doğru, her iki durumda da yanlış iki yargı)
final _ozmozDurumlari = <(String Function(String, String), String, String, String, String)>[
  (
    (x, y) =>
        'Yarı geçirgen bir zardan yapılmış kesenin içine %$x sakkaroz '
        'çözeltisi konuyor ve kese, içinde %$y sakkaroz çözeltisi bulunan bir '
        'kaba bırakılıyor. Zar suyu geçirip sakkarozu geçirmediğine göre bir '
        'süre sonra hangisi gözlenir?',
    'Su keseden kaba geçer; kesenin kütlesi azalır.',
    'Su kaptan keseye geçer; kesenin kütlesi artar.',
    'Su keseden kaba geçer; kesenin kütlesi artar.',
    'Su kaptan keseye geçer; kesenin kütlesi azalır.',
  ),
  (
    (x, y) =>
        'Hücre öz suyundaki çözünen madde derişimi %$x olan bir bitki hücresi, '
        'çözünen madde derişimi %$y olan bir çözeltiye konuyor. Çözünen madde '
        'hücre zarından geçemediğine göre hangisi doğrudur?',
    'Ortam hücreye göre hipertoniktir; hücre su kaybederek plazmoliz olur.',
    'Ortam hücreye göre hipotoniktir; hücre su alarak turgor durumuna geçer.',
    'Ortam hücreye göre hipertoniktir; hücre su alarak turgor durumuna geçer.',
    'Ortam hücreye göre hipotoniktir; hücre su kaybederek plazmoliz olur.',
  ),
  (
    (x, y) =>
        'Hücre öz suyundaki çözünen madde derişimi %$x olan soğan zarı '
        'hücrelerinin üzerine, zardan geçemeyen bir çözünenle hazırlanmış %$y '
        'derişimli çözelti damlatılıyor. Mikroskopta bir süre sonra hangisi '
        'gözlenir?',
    'Hücre zarı çeperden ayrılır; koful küçülür.',
    'Hücre zarı çepere doğru itilir; koful büyür.',
    'Hücre zarı çeperden ayrılır; koful büyür.',
    'Hücre zarı çepere doğru itilir; koful küçülür.',
  ),
  (
    (x, y) =>
        'Yalnız suyu geçiren bir zarla ikiye ayrılmış U borusunun K koluna '
        '%$x, L koluna %$y glikoz çözeltisi eşit yükseklikte konuyor. Bir süre '
        'sonra hangisi gözlenir?',
    'Su K kolundan L koluna geçer; L kolundaki sıvı yükselir.',
    'Su L kolundan K koluna geçer; K kolundaki sıvı yükselir.',
    'Su K kolundan L koluna geçer; K kolundaki sıvı yükselir.',
    'Su L kolundan K koluna geçer; L kolundaki sıvı yükselir.',
  ),
  (
    (x, y) =>
        'Plazmoliz olmuş bir bitki hücresinin hücre öz suyundaki çözünen madde '
        'derişimi %$x olarak ölçülüyor. Bu hücre, zardan geçemeyen bir '
        'çözünenle hazırlanmış %$y derişimli çözeltiye aktarılıyor. Hücrede '
        'hangisi gözlenir?',
    'Hücre su kaybetmeyi sürdürür; plazmoliz artar.',
    'Hücre su alır ve deplazmoliz olur.',
    'Hücre su alır; plazmoliz artar.',
    'Net su geçişi olmaz; hücrenin durumu değişmez.',
  ),
  (
    (x, y) =>
        'Hücrelerindeki çözünen madde derişimi %$x olan eşit kütleli patates '
        'dilimleri, %$y derişimli tuz çözeltisinde bir süre bekletiliyor. Tuz '
        'hücre zarından geçemediğine göre dilimlerde hangisi gözlenir?',
    'Dilimler su kaybeder; kütleleri azalır ve yumuşarlar.',
    'Dilimler su alır; kütleleri artar ve sertleşirler.',
    'Dilimler su kaybeder; kütleleri artar ve sertleşirler.',
    'Dilimler su alır; kütleleri azalır ve yumuşarlar.',
  ),
  (
    (x, y) =>
        'Nişastayı geçirmeyen, suyu geçiren bir zardan yapılmış kesede %$x, '
        'kesenin bırakıldığı kapta %$y nişasta çözeltisi vardır. Buna göre '
        'hangisi doğrudur?',
    'Kaptaki çözelti kesedekine göre hipertoniktir; kesenin hacmi küçülür.',
    'Kaptaki çözelti kesedekine göre hipotoniktir; kesenin hacmi büyür.',
    'Kaptaki çözelti kesedekine göre hipertoniktir; kesenin hacmi büyür.',
    'Kaptaki çözelti kesedekine göre hipotoniktir; kesenin hacmi küçülür.',
  ),
  (
    (x, y) =>
        'Kabuğu sirkede eritilmiş bir yumurtanın zarla çevrili iç kısmındaki '
        'çözünen madde derişimi %$x kabul ediliyor. Yumurta, zardan geçemeyen '
        'şekerle hazırlanmış %$y derişimli şuruba konuyor. Bir süre sonra '
        'hangisi gözlenir?',
    'Yumurta su kaybeder; hacmi küçülür.',
    'Yumurta su alır; hacmi büyür.',
    'Yumurta su kaybeder; hacmi büyür.',
    'Net su geçişi olmaz; yumurtanın hacmi değişmez.',
  ),
];

final _f13 = lmAile(
  'biy_osmoz',
  'Ozmozda suyun yönü ve hücrenin durumu',
  Topic.biology,
  Difficulty.easy,
  BloomLevel.anlama,
  (a, b, c) {
    final ic = 2 + a; // hücre ya da kese içindeki derişim (%)
    final dis = b + 1.5; // dış ortamın derişimi (%)
    final x = '$ic', y = tr(dis);
    if (c >= 8) {
      // Üç kap: derişimi dış ortamdan sırasıyla 0, 4 ve 8 birim fazla.
      final kaplar = [dis, dis + 4, dis + 8];
      final giris =
          'Hücre öz suyundaki çözünen madde derişimi %$x olan özdeş üç bitki '
          'hücresi; K kabındaki %${tr(kaplar[0])}, L kabındaki '
          '%${tr(kaplar[1])} ve M kabındaki %${tr(kaplar[2])} derişimli '
          'çözeltilere ayrı ayrı konuyor. Çözünen madde hücre zarından '
          'geçemediğine göre';
      if (c == 8) {
        final sayi = kaplar.where((k) => k > ic).length;
        const yanit = ['Hiçbirinde', 'Yalnız M', 'L ve M', 'K, L ve M'];
        return secenekli(
          '$giris hücreler hangi kaplarda su kaybederek plazmoliz olur?',
          yanit[sayi],
          [for (var j = 0; j < 4; j++) yanit[j], 'Yalnız K', 'K ve L'],
          'Hücre, derişimi kendi öz suyundan (%$x) yüksek olan çözeltilerde '
          'su kaybeder. Bu koşulu sağlayan kap sayısı $sayi olduğundan yanıt '
          '“${yanit[sayi]}” olur.',
        );
      }
      final sayi = kaplar.where((k) => k < ic).length;
      const yanit = ['Hiçbirinde', 'Yalnız K', 'K ve L', 'K, L ve M'];
      return secenekli(
        '$giris hücreler hangi kaplarda su alarak şişer?',
        yanit[sayi],
        [for (var j = 0; j < 4; j++) yanit[j], 'Yalnız M', 'L ve M'],
        'Hücre, derişimi kendi öz suyundan (%$x) düşük olan çözeltilerde su '
        'alır. Bu koşulu sağlayan kap sayısı $sayi olduğundan yanıt '
        '“${yanit[sayi]}” olur.',
      );
    }
    final (kok, hiper, hipo, y1, y2) = _ozmozDurumlari[c];
    final disDerisik = dis > ic;
    return secenekli(
      kok(x, y),
      disDerisik ? hiper : hipo,
      [disDerisik ? hipo : hiper, y1, y2],
      'Su, çözünen madde derişimi düşük olan taraftan yüksek olan tarafa '
      'geçer. Karşılaştırılan derişimlerden %$y, %$x değerinden '
      '${disDerisik ? 'büyük' : 'küçük'} olduğundan su '
      '${disDerisik ? '%$x derişimli taraftan %$y derişimli tarafa' : '%$y derişimli taraftan %$x derişimli tarafa'} '
      'geçer.',
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
  shortAnswer: false,
);

// ───────────────────────── 14. Mikroskopta büyütme ─────────────────────────

bool _ikiBasamakli(double x) => ((x * 100).round() - x * 100).abs() < 1e-6;

final _f14 = lmAile(
  'biy_mikroskop',
  'Mikroskopta büyütme, görüntü boyu ve gerçek boy',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    const objektifler = [4, 10, 20, 40, 100];
    final ok = const [5, 10, 15, 20][b % 4], ob = objektifler[b ~/ 4];
    final boy = 5 * (a + 1) + (c >= 5 ? 2 : 0); // gerçek boy (mikrometre)
    final m = ok * ob;
    final goruntu = boy * m / 1000; // milimetre
    Iterable<double> uygun(List<double> adaylar) =>
        adaylar.where((v) => v > 0 && _ikiBasamakli(v));
    const birim = '1 mm = 1000 mikrometre';
    switch (c % 5) {
      case 0:
        return ondalikli(
          'Oküleri $ok×, objektifi $ob× büyütmeli bir ışık mikroskobunda gerçek '
          'boyu $boy mikrometre olan bir hücre inceleniyor. Hücrenin '
          'görüntüsünün boyu kaç milimetre olur?',
          goruntu,
          uygun([goruntu * 10, boy * (ok + ob) / 1000, goruntu / 10, boy * ob / 1000, goruntu * 100]),
          'Toplam büyütme $ok · $ob = $m olur. Görüntü boyu $boy · $m = '
          '${boy * m} mikrometre, yani ${tr(goruntu)} mm bulunur ($birim).',
          unit: 'mm',
          positive: true,
        );
      case 1:
        return sayisal(
          'Oküleri $ok×, objektifi $ob× büyütmeli bir ışık mikroskobunda bir '
          'hücrenin görüntüsünün boyu ${tr(goruntu)} milimetre olarak '
          'ölçülüyor. Bu hücrenin gerçek boyu kaç mikrometredir?',
          boy,
          [10 * boy, boy * ok, boy * ob, boy ~/ 10, 100 * boy],
          'Toplam büyütme $ok · $ob = $m olur. Görüntü boyu ${tr(goruntu)} mm '
          '= ${boy * m} mikrometredir ($birim). Gerçek boy ${boy * m} / $m = '
          '$boy mikrometre bulunur.',
          positive: true,
        );
      case 2:
        return sayisal(
          'Oküleri $ok× büyütmeli bir ışık mikroskobunda gerçek boyu $boy '
          'mikrometre olan bir hücrenin görüntüsü ${tr(goruntu)} milimetre '
          'boyunda görülüyor. Kullanılan objektifin büyütmesi kaç kattır?',
          ob,
          [...objektifler, m],
          'Görüntü boyu ${tr(goruntu)} mm = ${boy * m} mikrometredir ($birim). '
          'Toplam büyütme ${boy * m} / $boy = $m, objektifin büyütmesi '
          '$m / $ok = $ob olur.',
          positive: true,
        );
      case 3:
        return sayisal(
          'Objektifi $ob× büyütmeli bir ışık mikroskobunda gerçek boyu $boy '
          'mikrometre olan bir hücrenin görüntüsü ${tr(goruntu)} milimetre '
          'boyunda görülüyor. Kullanılan okülerin büyütmesi kaç kattır?',
          ok,
          const [5, 10, 15, 20],
          'Görüntü boyu ${tr(goruntu)} mm = ${boy * m} mikrometredir ($birim). '
          'Toplam büyütme ${boy * m} / $boy = $m, okülerin büyütmesi '
          '$m / $ob = $ok olur.',
          positive: true,
        );
      default:
        final ob2 = objektifler[(b ~/ 4 + 1) % 5];
        final yeni = boy * ok * ob2 / 1000;
        return ondalikli(
          'Oküleri $ok× büyütmeli bir ışık mikroskobunda $ob× objektifle '
          'incelenen bir hücrenin görüntüsü ${tr(goruntu)} milimetre boyunda '
          'görülüyor. Objektif $ob2× olanla değiştirildiğinde aynı hücrenin '
          'görüntüsünün boyu kaç milimetre olur?',
          yeni,
          uygun([goruntu * ob / ob2, goruntu * ob2, goruntu, goruntu * ok, yeni * 10, yeni / 10, yeni * 2]),
          'Oküler değişmediğinden görüntü boyu objektifin büyütmesiyle doğru '
          'orantılıdır: ${tr(goruntu)} · $ob2 / $ob = ${tr(yeni)} mm.',
          unit: 'mm',
          positive: true,
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 15. Enerji piramidi ─────────────────────────

const _besinZincirleri = [
  ['ot', 'çekirge', 'kurbağa', 'yılan', 'şahin'],
  ['fitoplankton', 'zooplankton', 'hamsi', 'palamut', 'yunus'],
  ['yaprak', 'tırtıl', 'serçe', 'yılan', 'kartal'],
  ['su yosunu', 'su piresi', 'küçük balık', 'turna balığı', 'balıkçıl'],
  ['bitki', 'yaprak biti', 'uğur böceği', 'örümcek', 'kertenkele'],
];

final _f15 = lmAile(
  'biy_enerji_piramidi',
  'Besin zincirinde enerji aktarımı ve biyokütle',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final z = _besinZincirleri[b % 5];
    final v = b ~/ 5;
    final t = 1 + v; // hedef basamak (0 = üretici)
    final e0 = 200000 * (a + 2);
    final giris =
        'Bir ekosistemde “${z.join(' → ')}” besin zincirinde her beslenme '
        'basamağındaki enerjinin %10 kadarı bir üst basamağa aktarılmaktadır.';
    final uretici = 'Zincirin üreticisi olan ${z[0]} basamağında';
    int enerji(int basamak) => e0 ~/ _us(10, basamak);
    switch (c) {
      case 0:
        return sayisal(
          '$giris $uretici $e0 kcal enerji bulunduğuna göre ${z[t]} '
          'popülasyonuna aktarılan enerji kaç kcal olur?',
          enerji(t),
          [enerji(t - 1), enerji(t) ~/ 10, e0 * t ~/ 10, enerji(t) * 100, e0 ~/ (10 * t)],
          'Enerji her basamakta 10 kat azalır. Üreticiden ${z[t]} basamağına '
          '$t aktarım olduğundan enerji $e0 / 10${_ust(t)} = ${enerji(t)} kcal '
          'olur.',
          positive: true,
        );
      case 1:
        return sayisal(
          '$giris Bu zincirde ${z[t]} popülasyonuna aktarılan enerji '
          '${enerji(t)} kcal olduğuna göre zincirin üreticisi olan ${z[0]} '
          'basamağındaki enerji kaç kcal olur?',
          e0,
          [e0 ~/ 10, e0 * 10, enerji(t) * 10 * t, enerji(t) * 10, e0 ~/ 100],
          'Üreticiden ${z[t]} basamağına $t aktarım vardır; her aktarımda '
          'enerji 10 kat azaldığından üreticideki enerji ${enerji(t)} · '
          '10${_ust(t)} = $e0 kcal olur.',
          positive: true,
        );
      case 2:
        final (s, u) = const [(1, 3), (2, 4), (1, 4), (1, 2)][v];
        return sayisal(
          '$giris Bu zincirde ${z[s]} popülasyonundaki enerji ${enerji(s)} '
          'kcal olduğuna göre ${z[u]} popülasyonuna aktarılan enerji kaç kcal '
          'olur?',
          enerji(u),
          [enerji(u) * 10, enerji(u) * 100, enerji(s) ~/ 10, enerji(s) * 9 ~/ 10, enerji(u) ~/ 10],
          'Bu iki basamak arasında ${u - s} aktarım vardır: ${enerji(s)} / '
          '10${_ust(u - s)} = ${enerji(u)} kcal.',
          positive: true,
        );
      case 3:
        return sayisal(
          '$giris $uretici $e0 kcal enerji bulunduğuna göre bu enerjinin kaç '
          'kcal kadarı ${z[t]} popülasyonuna ulaşmadan zincirden ayrılır?',
          e0 - enerji(t),
          [enerji(t), e0 * 9 ~/ 10, e0 - enerji(t) ~/ 10, e0 * (10 - t) ~/ 10, e0 * 99 ~/ 100, e0 * 8 ~/ 10],
          'Sorulan basamağa (${z[t]}) ulaşan enerji $e0 / 10${_ust(t)} = '
          '${enerji(t)} kcal olur. Ulaşmayan enerji $e0 − ${enerji(t)} = '
          '${e0 - enerji(t)} kcal bulunur.',
          positive: true,
        );
      case 4:
        final kg = a + 2;
        return sayisal(
          '$giris Biyokütle de aynı oranda aktarıldığına göre ${z[t]} '
          'popülasyonunun biyokütlesinin $kg kg artması için ${z[0]} '
          'basamağından en az kaç kg besin tüketilmelidir?',
          kg * _us(10, t),
          [kg * 10 * t, kg * _us(10, t + 1), kg * _us(10, t - 1), kg * _us(10, t) ~/ 2, kg * 100 * t],
          'Her basamakta biyokütlenin %10 kadarı aktarıldığından üreticiden '
          '${z[t]} basamağına $t aktarım için $kg · 10${_ust(t)} = '
          '${kg * _us(10, t)} kg besin gerekir.',
          positive: true,
        );
      case 5:
        final (s, u) = const [(1, 2), (2, 3), (3, 4), (1, 3)][v];
        return sayisal(
          '$giris $uretici $e0 kcal enerji bulunduğuna göre ${z[s]} ve '
          '${z[u]} popülasyonlarına aktarılan enerjilerin toplamı kaç kcal '
          'olur?',
          enerji(s) + enerji(u),
          [enerji(s), 2 * enerji(u), enerji(s - 1) + enerji(u - 1), enerji(s) + enerji(u) ~/ 10, 2 * enerji(s)],
          'Aktarılan enerji ${z[s]} basamağı için $e0 / 10${_ust(s)} = '
          '${enerji(s)} kcal, ${z[u]} basamağı için $e0 / 10${_ust(u)} = '
          '${enerji(u)} kcal olur. Toplam '
          '${enerji(s) + enerji(u)} kcal olur.',
          positive: true,
        );
      case 6:
        final (s, u) = const [(1, 2), (2, 3), (3, 4), (1, 3)][v];
        return sayisal(
          '$giris $uretici $e0 kcal enerji bulunduğuna göre ${z[s]} '
          'popülasyonuna aktarılan enerji, ${z[u]} popülasyonuna aktarılan '
          'enerjiden kaç kcal fazladır?',
          enerji(s) - enerji(u),
          [enerji(s), enerji(s) + enerji(u), enerji(u) * 10, enerji(s - 1) - enerji(u - 1), enerji(u)],
          'Aktarılan enerji ${z[s]} basamağı için $e0 / 10${_ust(s)} = '
          '${enerji(s)} kcal, ${z[u]} basamağı için $e0 / 10${_ust(u)} = '
          '${enerji(u)} kcal olur. Fark '
          '${enerji(s) - enerji(u)} kcal olur.',
          positive: true,
        );
      case 7:
        final gerek = const [500, 800, 1000, 2000][v];
        final say = a + 2;
        final ust = say * gerek * 100;
        return sayisal(
          '$giris $uretici $ust kcal enerji bulunmaktadır. Bir ${z[2]} '
          'bireyinin enerji gereksinimi $gerek kcal olduğuna göre bu enerji '
          'en çok kaç ${z[2]} bireyinin gereksinimini karşılar?',
          say,
          [say * 10, say * 100, say ~/ 10, say * 5, say + 10],
          'Üreticiden ${z[2]} basamağına 2 aktarım vardır: $ust / 10² = '
          '${ust ~/ 100} kcal. Birey sayısı ${ust ~/ 100} / $gerek = $say '
          'olur.',
          positive: true,
        );
      case 8:
        return sayisal(
          '$giris Biyokütle de aynı oranda aktarıldığına göre zincirin '
          'üreticisi olan ${z[0]} basamağındaki $e0 kg biyokütle, ${z[t]} '
          'basamağında en çok kaç kg biyokütle oluşmasını sağlar?',
          enerji(t),
          [enerji(t - 1), enerji(t) ~/ 10, e0 * t ~/ 10, enerji(t) * 100, e0 ~/ (10 * t)],
          'Biyokütle her basamakta 10 kat azalır. Üreticiden ${z[t]} '
          'basamağına $t aktarım olduğundan $e0 / 10${_ust(t)} = ${enerji(t)} '
          'kg biyokütle oluşur.',
          positive: true,
        );
      default:
        return secenekli(
          '$giris $uretici $e0 kcal enerji bulunmaktadır. Bu zincirde '
          '${enerji(t)} kcal enerji hangi canlının popülasyonuna aktarılır?',
          z[t],
          [for (var j = 1; j < 5; j++) z[j]],
          'Üreticideki enerji $e0 kcal, aranan enerji ${enerji(t)} kcal '
          'olduğundan oran 10${_ust(t)} olur; bu da $t aktarım demektir. '
          'Üreticiden sonraki $t. basamakta ${z[t]} bulunur.',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 16. Popülasyon büyüklüğü ve yoğunluğu ─────────────────────────

const _populasyonlar = [
  'Bir adadaki tavşan popülasyonunda',
  'Bir ormandaki geyik popülasyonunda',
  'Bir göldeki sazan popülasyonunda',
  'Bir bozkırdaki tarla faresi popülasyonunda',
  'Bir sulak alandaki ördek popülasyonunda',
];

final _f16 = lmAile(
  'biy_populasyon',
  'Popülasyon büyüklüğü, yoğunluğu ve büyüme hızı',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final yuzde = 2 * (a + 3); // başlangıcın %1 kadarı
    final n0 = 100 * yuzde;
    final dy = 12 + 2 * (b % 5); // doğum yüzdesi
    final (oy, gy, ay) = const [(5, 3, 2), (8, 2, 4), (6, 4, 1), (9, 1, 3)][b ~/ 5];
    final dogum = yuzde * dy, olum = yuzde * oy;
    final gelen = yuzde * gy, giden = yuzde * ay;
    final net = dogum + gelen - olum - giden, netY = dy + gy - oy - ay;
    final son = n0 + net;
    final alan = (a + 3) * (1 + a % 2); // km²
    final ortam = sec(_populasyonlar, a + b);
    final olaylar =
        'Yıl içinde $dogum birey doğmuş, $olum birey ölmüş, $gelen birey '
        'dışarıdan göç ederek popülasyona katılmış ve $giden birey göç ederek '
        'popülasyondan ayrılmıştır.';
    final tam = '$ortam yılın başında $n0 birey vardır. $olaylar';
    final denklem =
        'Değişim = doğum + içe göç − ölüm − dışa göç = $dogum + $gelen − '
        '$olum − $giden = $net birey olur.';
    switch (c) {
      case 0:
        return sayisal(
          '$tam Yıl sonunda popülasyonda kaç birey bulunur?',
          son,
          [n0 + dogum - olum, n0 + dogum + gelen, n0 - net, n0 + dogum + gelen + olum + giden],
          '$denklem Yıl sonundaki büyüklük $n0 + $net = $son olur.',
          positive: true,
        );
      case 1:
        return sayisal(
          '$tam Popülasyondaki birey sayısı yıl içinde kaç artmıştır?',
          net,
          [dogum - olum, dogum + gelen, dogum + gelen + olum + giden, dogum - olum - gelen + giden],
          denklem,
          positive: true,
        );
      case 2:
        return sayisal(
          '$tam Popülasyonun yıllık büyüme hızı, yıl başındaki büyüklüğün '
          'yüzde kaçıdır?',
          netY,
          [dy - oy, dy + gy, dy, netY * 10, dy + gy + oy + ay],
          '$denklem Büyüme hızı $net / $n0 · 100 = $netY olarak bulunur.',
          positive: true,
        );
      case 3:
        return sayisal(
          '$tam Popülasyon $alan km² büyüklüğünde bir alanda yaşadığına göre '
          'yıl sonundaki popülasyon yoğunluğu km² başına kaç birey olur?',
          son ~/ alan,
          [n0 ~/ alan, net ~/ alan, (n0 + dogum - olum) ~/ alan, son ~/ alan * 2],
          '$denklem Yıl sonunda $n0 + $net = $son birey vardır. Yoğunluk '
          '$son / $alan = ${son ~/ alan} birey/km² olur.',
          positive: true,
        );
      case 4:
        return sayisal(
          '$ortam yılın başında $n0 birey vardır. Yıl içinde $dogum birey '
          'doğmuş, $gelen birey dışarıdan göç ederek popülasyona katılmış ve '
          '$giden birey göç ederek popülasyondan ayrılmıştır. Yıl sonunda '
          '$son birey sayıldığına göre yıl içinde kaç birey ölmüştür?',
          olum,
          [olum + giden, n0 + dogum - son, son - n0, olum + gelen, dogum - olum],
          'Ölüm = yıl başı + doğum + içe göç − dışa göç − yıl sonu = $n0 + '
          '$dogum + $gelen − $giden − $son = $olum birey olur.',
          positive: true,
        );
      case 5:
        return sayisal(
          '$ortam yılın başında $n0 birey vardır. Yıl içinde $dogum birey '
          'doğmuş, $olum birey ölmüş ve $giden birey göç ederek popülasyondan '
          'ayrılmıştır. Yıl sonunda $son birey sayıldığına göre yıl içinde '
          'dışarıdan göç ederek popülasyona kaç birey katılmıştır?',
          gelen,
          [son - n0, gelen + giden, son - n0 - dogum + olum, dogum - olum, gelen + olum],
          'İçe göç = yıl sonu − yıl başı − doğum + ölüm + dışa göç = $son − '
          '$n0 − $dogum + $olum + $giden = $gelen birey olur.',
          positive: true,
        );
      case 6:
        return sayisal(
          '$ortam bir yıl boyunca sayım yapılmıştır. $olaylar Yıl sonunda '
          '$son birey sayıldığına göre yılın başında popülasyonda kaç birey '
          'vardı?',
          n0,
          [son + net, son - dogum + olum, son - dogum - gelen, n0 + giden],
          '$denklem Yıl başındaki büyüklük $son − $net = $n0 olur.',
          positive: true,
        );
      case 7:
        return sayisal(
          '$tam Popülasyon $alan km² büyüklüğünde bir alanda yaşadığına göre '
          'popülasyon yoğunluğu yıl içinde km² başına kaç birey artmıştır?',
          net ~/ alan,
          [son ~/ alan, n0 ~/ alan, (dogum - olum) ~/ alan, (dogum + gelen) ~/ alan],
          '$denklem Yoğunluktaki artış $net / $alan = ${net ~/ alan} '
          'birey/km² olur.',
          positive: true,
        );
      case 8:
        return sayisal(
          '$tam Göçler olmasaydı popülasyonun yıllık büyüme hızı, yıl '
          'başındaki büyüklüğün yüzde kaçı olurdu?',
          dy - oy,
          [netY, dy, dy + oy, dy - oy + gy, (dy - oy) * 10],
          'Göçler olmadığında değişim doğum − ölüm = $dogum − $olum = '
          '${dogum - olum} birey olur. Büyüme hızı ${dogum - olum} / $n0 · '
          '100 = ${dy - oy} bulunur.',
          positive: true,
        );
      default:
        return sayisal(
          '$tam Yıl sonunda popülasyon yoğunluğu km² başına ${son ~/ alan} '
          'birey olarak hesaplandığına göre popülasyon kaç km² büyüklüğünde '
          'bir alanda yaşamaktadır?',
          alan,
          [n0 ~/ (son ~/ alan), alan * 2, alan + 1, alan + 3, alan * 10],
          '$denklem Yıl sonunda $n0 + $net = $son birey vardır. Alan '
          '$son / ${son ~/ alan} = $alan km² olur.',
          positive: true,
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 17. Kalp debisi ve solunum hacmi ─────────────────────────

final _f17 = lmAile(
  'biy_dolasim_solunum',
  'Kalp debisi ve dakikadaki solunum hacmi',
  Topic.biology,
  Difficulty.easy,
  BloomLevel.uygulama,
  (a, b, c) {
    final nabiz = 56 + 2 * a, atim = 50 + 5 * b; // atım/dk, mL
    final debi = nabiz * atim / 1000; // L/dk
    final soluk = 10 + a, hacim = 400 + 50 * b; // soluk/dk, mL
    final hava = soluk * hacim / 1000; // L/dk
    Iterable<double> uygun(List<double> adaylar) =>
        adaylar.where((v) => v > 0 && _ikiBasamakli(v));
    const debiTanim =
        'Kalp debisi, kalbin bir dakikada pompaladığı kan miktarıdır: nabız · '
        'atım hacmi.';
    const havaTanim =
        'Dakikadaki solunum hacmi = soluk sayısı · bir solukta alınan hava.';
    switch (c) {
      case 0:
        return ondalikli(
          'Bir kişinin nabzı dakikada $nabiz atım, kalbinin bir kasılmada '
          'pompaladığı kan miktarı (atım hacmi) $atim mL olarak ölçülüyor. Bu '
          'kişinin kalp debisi dakikada kaç litredir?',
          debi,
          uygun([debi * 10, debi / 10, (nabiz + atim) / 10, debi * 2, debi / 2, debi * 100]),
          '$debiTanim $nabiz · $atim = ${nabiz * atim} mL, yani ${tr(debi)} L '
          'olur.',
          unit: 'L',
          positive: true,
        );
      case 1:
        return sayisal(
          'Bir kişinin kalp debisi dakikada ${tr(debi)} litre, nabzı dakikada '
          '$nabiz atım olarak ölçülüyor. Bu kişinin kalbinin bir kasılmada '
          'pompaladığı kan miktarı (atım hacmi) kaç mL olur?',
          atim,
          [atim * 10, atim + 10, atim - 10, atim * 2, atim + 20],
          '$debiTanim Atım hacmi ${nabiz * atim} mL / $nabiz = $atim mL '
          'bulunur (${tr(debi)} L = ${nabiz * atim} mL).',
          positive: true,
        );
      case 2:
        return sayisal(
          'Bir kişinin kalp debisi dakikada ${tr(debi)} litre, kalbinin bir '
          'kasılmada pompaladığı kan miktarı (atım hacmi) $atim mL olarak '
          'ölçülüyor. Bu kişinin nabzı dakikada kaç atımdır?',
          nabiz,
          [nabiz + 10, nabiz - 10, nabiz + 20, nabiz * 2, nabiz - 20],
          '$debiTanim Nabız ${nabiz * atim} mL / $atim mL = $nabiz atım '
          'bulunur (${tr(debi)} L = ${nabiz * atim} mL).',
          positive: true,
        );
      case 3:
        return ondalikli(
          'Egzersiz yapan bir sporcu dakikada $soluk kez soluk alıp veriyor ve '
          'her solukta akciğerlerine $hacim mL hava alıyor. Bu sporcunun '
          'akciğerlerine bir dakikada giren hava kaç litredir?',
          hava,
          uygun([hava * 10, hava / 10, (soluk + hacim) / 100, hava * 2, hava / 2, hava * 100]),
          '$havaTanim $soluk · $hacim = ${soluk * hacim} mL, yani ${tr(hava)} '
          'L olur.',
          unit: 'L',
          positive: true,
        );
      case 4:
        return sayisal(
          'Egzersiz yapan bir sporcunun akciğerlerine bir dakikada '
          '${tr(hava)} litre hava giriyor. Sporcu dakikada $soluk kez soluk '
          'alıp verdiğine göre her solukta akciğerlerine kaç mL hava alır?',
          hacim,
          [hacim + 50, hacim - 50, hacim * 2, hacim + 100, hacim ~/ 2],
          '$havaTanim Bir solukta alınan hava ${soluk * hacim} mL / $soluk = '
          '$hacim mL bulunur (${tr(hava)} L = ${soluk * hacim} mL).',
          positive: true,
        );
      case 5:
        return sayisal(
          'Egzersiz yapan bir sporcunun akciğerlerine bir dakikada '
          '${tr(hava)} litre hava giriyor. Sporcu her solukta $hacim mL hava '
          'aldığına göre dakikada kaç kez soluk alıp verir?',
          soluk,
          [soluk + 2, soluk - 2, soluk * 2, soluk + 4, soluk + 6],
          '$havaTanim Soluk sayısı ${soluk * hacim} mL / $hacim mL = $soluk '
          'bulunur (${tr(hava)} L = ${soluk * hacim} mL).',
          positive: true,
        );
      case 6:
        final nabiz2 = nabiz + 50, atim2 = atim + 25;
        final debi2 = nabiz2 * atim2 / 1000;
        return ondalikli(
          'Bir kişinin dinlenirken nabzı dakikada $nabiz atım, atım hacmi '
          '$atim mL; koşarken nabzı dakikada $nabiz2 atım, atım hacmi $atim2 '
          'mL olarak ölçülüyor. Bu kişinin kalp debisi koşarken dinlenme '
          'durumuna göre dakikada kaç litre artmıştır?',
          debi2 - debi,
          uygun([debi2, debi, 50 * 25 / 1000, (debi2 - debi) * 10, debi2 + debi]),
          '$debiTanim Dinlenirken $nabiz · $atim = ${nabiz * atim} mL, '
          'koşarken $nabiz2 · $atim2 = ${nabiz2 * atim2} mL olur. Artış '
          '${nabiz2 * atim2 - nabiz * atim} mL, yani ${tr(debi2 - debi)} L '
          'bulunur.',
          unit: 'L',
          positive: true,
        );
      case 7:
        return ondalikli(
          'Bir kişinin nabzı dakikada $nabiz atım, kalbinin bir kasılmada '
          'pompaladığı kan miktarı (atım hacmi) $atim mL olarak ölçülüyor. '
          'Nabız ve atım hacmi değişmediğine göre bu kişinin kalbi bir saatte '
          'kaç litre kan pompalar?',
          debi * 60,
          uygun([debi, debi * 6, debi * 600, debi * 30, debi * 3600 / 100]),
          '$debiTanim $nabiz · $atim = ${nabiz * atim} mL, yani ${tr(debi)} L '
          'olur. Bir saatte ${tr(debi)} · 60 = ${tr(debi * 60)} L kan '
          'pompalanır.',
          unit: 'L',
          positive: true,
        );
      case 8:
        return ondalikli(
          'Egzersiz yapan bir sporcu dakikada $soluk kez soluk alıp veriyor ve '
          'her solukta akciğerlerine $hacim mL hava alıyor. Bu sporcunun '
          'akciğerlerine 5 dakikada giren hava kaç litredir?',
          hava * 5,
          uygun([hava, hava * 50, hava * 10, hava * 2.5, hava / 2]),
          '$havaTanim Bir dakikada $soluk · $hacim = ${soluk * hacim} mL, yani '
          '${tr(hava)} L hava girer. Beş dakikada ${tr(hava)} · 5 = '
          '${tr(hava * 5)} L olur.',
          unit: 'L',
          positive: true,
        );
      default:
        final soluk2 = soluk + 12, hacim2 = hacim + 500;
        final hava2 = soluk2 * hacim2 / 1000;
        return ondalikli(
          'Bir sporcu hafif tempoda dakikada $soluk kez soluk alıp veriyor ve '
          'her solukta $hacim mL hava alıyor. Tempo artınca dakikada $soluk2 '
          'kez soluk alıp veriyor ve her solukta $hacim2 mL hava alıyor. '
          'Sporcunun akciğerlerine bir dakikada giren hava kaç litre '
          'artmıştır?',
          hava2 - hava,
          uygun([hava2, hava, 12 * 500 / 1000, (hava2 - hava) * 10, hava2 + hava]),
          '$havaTanim İlk durumda $soluk · $hacim = ${soluk * hacim} mL, '
          'ikinci durumda $soluk2 · $hacim2 = ${soluk2 * hacim2} mL olur. '
          'Artış ${soluk2 * hacim2 - soluk * hacim} mL, yani '
          '${tr(hava2 - hava)} L bulunur.',
          unit: 'L',
          positive: true,
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 18. Fotosentez, solunum ve fermantasyon ─────────────────────────

final _f18 = lmAile(
  'biy_fotosentez_solunum',
  'Fotosentez, solunum ve fermantasyonda madde miktarı',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.analiz,
  (a, b, c) {
    final m = b + 1; // oksijenli solunumda (ya da ilk yolda) kullanılan glikoz
    final n = a + b + 3; // toplam glikoz
    final k = n - m; // kalan glikoz
    const denklem =
        'Fotosentezin net denklemi 6CO₂ + 6H₂O → C₆H₁₂O₆ + 6O₂, oksijenli '
        'solunumun net denklemi C₆H₁₂O₆ + 6O₂ → 6CO₂ + 6H₂O biçimindedir.';
    final maya =
        'Bir maya kültüründe $n molekül glikozun $m tanesi oksijenli '
        'solunumla, kalanı etil alkol fermantasyonuyla parçalanıyor.';
    const mayaBilgi =
        'Oksijenli solunumda 1 glikoz için 6 O₂ tüketilir, 6 CO₂ ve 6 H₂O '
        'oluşur; etil alkol fermantasyonunda 1 glikozdan 2 etil alkol ve 2 CO₂ '
        'oluşur.';
    switch (c) {
      case 0:
        return sayisal(
          '$denklem Bir bitki hücresi belirli bir sürede fotosentezle $n '
          'molekül glikoz üretiyor ve oksijenli solunumda $m molekül glikoz '
          'harcıyor. Bu sürede hücrenin ortama verdiği net O₂ molekülü sayısı '
          'kaçtır?',
          6 * k,
          [6 * n, 6 * m, k, 6 * (n + m), 12 * k],
          'Fotosentezde 6 · $n = ${6 * n} O₂ üretilir, solunumda 6 · $m = '
          '${6 * m} O₂ tüketilir. Net çıkış ${6 * n} − ${6 * m} = ${6 * k} '
          'olur.',
          positive: true,
        );
      case 1:
        return sayisal(
          '$maya Bu olaylar sonunda açığa çıkan toplam CO₂ molekülü sayısı '
          'kaçtır?',
          6 * m + 2 * k,
          [6 * n, 2 * n, 6 * m, 2 * m + 6 * k, 6 * m + k],
          '$mayaBilgi Toplam CO₂: 6 · $m + 2 · $k = ${6 * m + 2 * k}.',
          positive: true,
        );
      case 2:
        return sayisal(
          '$maya Bu olaylar sonunda oluşan etil alkol molekülü sayısı kaçtır?',
          2 * k,
          [k, 2 * n, 2 * m, 6 * k, 3 * k],
          'Fermantasyona giren glikoz sayısı $n − $m = $k olur. Her glikozdan '
          '2 etil alkol oluştuğundan 2 · $k = ${2 * k} molekül etil alkol '
          'oluşur.',
          positive: true,
        );
      case 3:
        return sayisal(
          'Yoğun çalışan bir kas dokusunda $n molekül glikozun $m tanesi '
          'oksijenli solunumla, kalanı laktik asit fermantasyonuyla '
          'parçalanıyor. Bu olaylar sonunda açığa çıkan toplam CO₂ molekülü '
          'sayısı kaçtır?',
          6 * m,
          [6 * m + 2 * k, 6 * n, 2 * k, 6 * k, 6 * m + k],
          'Oksijenli solunumda 1 glikozdan 6 CO₂ oluşur; laktik asit '
          'fermantasyonunda CO₂ oluşmaz (1 glikozdan 2 laktik asit oluşur). '
          'Toplam CO₂: 6 · $m = ${6 * m}.',
          positive: true,
        );
      case 4:
        return sayisal(
          '$denklem Bir bitki hücresi belirli bir sürede fotosentezde '
          '${6 * n} molekül CO₂ kullanıyor ve oksijenli solunumda ${6 * m} '
          'molekül O₂ tüketiyor. Bu sürede hücrede biriken net glikoz molekülü '
          'sayısı kaçtır?',
          k,
          [n, 6 * k, n + m, m, 2 * k],
          'Fotosentezde ${6 * n} / 6 = $n glikoz üretilir, solunumda '
          '${6 * m} / 6 = $m glikoz harcanır. Net birikim $n − $m = $k olur.',
          positive: true,
        );
      case 5:
        return sayisal(
          'Bir maya kültüründe $n molekül glikozun bir bölümü oksijenli '
          'solunumla, kalanı etil alkol fermantasyonuyla parçalanıyor ve '
          'toplam ${6 * m + 2 * k} molekül CO₂ açığa çıkıyor. Oksijenli '
          'solunumla parçalanan glikoz molekülü sayısı kaçtır?',
          m,
          [k, (6 * m + 2 * k) ~/ 6, n - (6 * m + 2 * k) ~/ 6, 2 * m, m + 1, m + 2],
          '$mayaBilgi Oksijenli solunuma giren glikoz x ise 6x + 2 · ($n − x) '
          '= ${6 * m + 2 * k} olur; 4x = ${4 * m} ve x = $m bulunur.',
          positive: true,
        );
      case 6:
        return sayisal(
          'Bir maya kültüründe $n molekül glikozun bir bölümü etil alkol '
          'fermantasyonuyla parçalanıyor ve ${2 * k} molekül etil alkol '
          'oluşuyor. Kalan glikozun tamamı oksijenli solunumla parçalandığına '
          'göre tüketilen O₂ molekülü sayısı kaçtır?',
          6 * m,
          [6 * n, 6 * k, 6 * m + 2 * k, m, 12 * m],
          'Fermantasyona giren glikoz ${2 * k} / 2 = $k, oksijenli solunuma '
          'giren glikoz $n − $k = $m olur. Tüketilen O₂: 6 · $m = ${6 * m}.',
          positive: true,
        );
      case 7:
        return sayisal(
          '$maya Bu olaylar sonunda oluşan CO₂ ve H₂O moleküllerinin toplam '
          'sayısı kaçtır?',
          12 * m + 2 * k,
          [6 * m + 2 * k, 12 * n, 12 * m + 4 * k, 12 * m, 6 * n],
          '$mayaBilgi CO₂: 6 · $m + 2 · $k = ${6 * m + 2 * k}; H₂O: 6 · $m = '
          '${6 * m}. Toplam ${12 * m + 2 * k} olur.',
          positive: true,
        );
      case 8:
        return sayisal(
          'Bir hamur örneğinde $n molekül glikozun $m tanesi mayalar '
          'tarafından etil alkol fermantasyonuyla, kalanı bakteriler '
          'tarafından laktik asit fermantasyonuyla parçalanıyor. Bu olaylar '
          'sonunda oluşan etil alkol, laktik asit ve CO₂ moleküllerinin toplam '
          'sayısı kaçtır?',
          2 * n + 2 * m,
          [2 * n, 4 * n, 2 * n + 2 * k, 2 * m + k, 3 * n],
          'Etil alkol fermantasyonunda 1 glikozdan 2 etil alkol ve 2 CO₂, '
          'laktik asit fermantasyonunda 1 glikozdan 2 laktik asit oluşur. '
          'Toplam: 4 · $m + 2 · $k = ${2 * n + 2 * m}.',
          positive: true,
        );
      default:
        return kesirli(
          '$denklem Bir bitki hücresi belirli bir sürede fotosentezle $n '
          'molekül glikoz üretiyor ve oksijenli solunumda $m molekül glikoz '
          'harcıyor. Fotosentezde üretilen O₂ molekülü sayısı, solunumda '
          'tüketilen O₂ molekülü sayısının kaç katıdır?',
          n,
          m,
          [(m, n), (6 * n, 1), (k, m), (n, 6 * m), (6 * n, m), (n + m, m)],
          'Fotosentezde 6 · $n = ${6 * n} O₂ üretilir, solunumda 6 · $m = '
          '${6 * m} O₂ tüketilir. Oran ${6 * n} / ${6 * m} = ${kesir(n, m)} '
          'olur.',
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 19. Glikoliz ve fermantasyonda ATP ─────────────────────────

final _f19 = lmAile(
  'biy_atp',
  'Glikoliz ve fermantasyonda ATP hesabı',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final x = a + 2, y = b + 2; // maya ve kas hücrelerinin parçaladığı glikoz
    final deney =
        'Bir deneyde maya hücreleri etil alkol fermantasyonuyla $x molekül, '
        'oksijensiz kalan kas hücreleri laktik asit fermantasyonuyla $y '
        'molekül glikoz parçalıyor.';
    const atp =
        'Her glikoz için glikolizde 2 ATP harcanır ve 4 ATP üretilir; net '
        'kazanç 2 ATP olur.';
    const urun =
        'Etil alkol fermantasyonunda 1 glikozdan 2 etil alkol ve 2 CO₂, laktik '
        'asit fermantasyonunda 1 glikozdan 2 laktik asit oluşur.';
    switch (c) {
      case 0:
        return sayisal(
          '$deney Bu iki olayda hücrelerin toplam net ATP kazancı kaç '
          'moleküldür?',
          2 * (x + y),
          [4 * (x + y), x + y, 2 * x, 2 * x + 4 * y, 6 * (x + y)],
          '$atp Toplam net kazanç 2 · ($x + $y) = ${2 * (x + y)} ATP bulunur.',
          positive: true,
        );
      case 1:
        return sayisal(
          '$deney Bu iki olayda substrat düzeyinde fosforilasyonla üretilen '
          'toplam ATP kaç moleküldür?',
          4 * (x + y),
          [2 * (x + y), x + y, 4 * x + 2 * y, 6 * (x + y), 4 * x],
          '$atp Üretilen toplam ATP 4 · ($x + $y) = ${4 * (x + y)} olur.',
          positive: true,
        );
      case 2:
        return sayisal(
          '$deney Maya hücrelerinin glikozu etkinleştirmek için harcadığı ATP '
          'ile kas hücrelerinin ürettiği toplam ATP sayılarının toplamı '
          'kaçtır?',
          2 * x + 4 * y,
          [4 * x + 2 * y, 2 * (x + y), 4 * (x + y), 2 * x + 2 * y + 2, x + 2 * y],
          '$atp Mayalar 2 · $x = ${2 * x} ATP harcar, kas hücreleri 4 · $y = '
          '${4 * y} ATP üretir. Toplam ${2 * x + 4 * y} olur.',
          positive: true,
        );
      case 3:
        return sayisal(
          '$deney Bu iki olayda açığa çıkan toplam CO₂ molekülü sayısı '
          'kaçtır?',
          2 * x,
          [2 * (x + y), 2 * y, x, 6 * x, x + y],
          '$urun Yalnız maya hücreleri CO₂ oluşturur: 2 · $x = ${2 * x}.',
          positive: true,
        );
      case 4:
        return sayisal(
          '$deney Maya hücrelerinin oluşturduğu etil alkol ve CO₂ molekülleri '
          'ile kas hücrelerinin oluşturduğu laktik asit moleküllerinin toplam '
          'sayısı kaçtır?',
          4 * x + 2 * y,
          [2 * (x + y), 4 * (x + y), 2 * x + 4 * y, 2 * x + y, 3 * (x + y)],
          '$urun Mayalarda 2 · $x + 2 · $x = ${4 * x}, kas hücrelerinde '
          '2 · $y = ${2 * y} molekül oluşur. Toplam ${4 * x + 2 * y} bulunur.',
          positive: true,
        );
      case 5:
        return sayisal(
          'Bir deneyde maya hücreleri etil alkol fermantasyonu, oksijensiz '
          'kalan kas hücreleri laktik asit fermantasyonu yapıyor. İki hücre '
          'grubunun toplam net ATP kazancı ${2 * (x + y)} molekül, maya '
          'hücrelerinin açığa çıkardığı CO₂ ${2 * x} molekül olarak '
          'ölçülüyor. Kas hücrelerinin parçaladığı glikoz molekülü sayısı '
          'kaçtır?',
          y,
          [x + y, 2 * y, x, y + 1, y + 2, y + x + 1],
          '$atp Toplam glikoz ${2 * (x + y)} / 2 = ${x + y} olur. Mayalar '
          '${2 * x} / 2 = $x glikoz parçalamıştır; kas hücrelerine '
          '${x + y} − $x = $y glikoz kalır.',
          positive: true,
        );
      case 6:
        return sayisal(
          'Bir deneyde maya hücrelerinin etil alkol fermantasyonuyla ${2 * x} '
          'molekül etil alkol, oksijensiz kalan kas hücrelerinin laktik asit '
          'fermantasyonuyla ${2 * y} molekül laktik asit oluşturduğu '
          'belirleniyor. Bu iki olayda substrat düzeyinde fosforilasyonla '
          'üretilen toplam ATP kaç moleküldür?',
          4 * (x + y),
          [2 * (x + y), x + y, 8 * (x + y), 4 * x + 2 * y, 6 * (x + y)],
          'Parçalanan glikoz sayısı ${2 * x} / 2 + ${2 * y} / 2 = ${x + y} '
          'olur. $atp Üretilen toplam ATP 4 · ${x + y} = ${4 * (x + y)} '
          'bulunur.',
          positive: true,
        );
      case 7:
        return sayisal(
          'Bir deneyde maya hücreleri etil alkol fermantasyonuyla $x molekül '
          'glikoz parçalıyor; oksijensiz kalan kas hücreleri de laktik asit '
          'fermantasyonu yapıyor. İki olayda substrat düzeyinde '
          'fosforilasyonla toplam ${4 * (x + y)} molekül ATP üretildiğine '
          'göre kas hücrelerinde oluşan laktik asit molekülü sayısı kaçtır?',
          2 * y,
          [y, 2 * (x + y), 4 * y, x + y, 2 * x],
          '$atp Toplam glikoz ${4 * (x + y)} / 4 = ${x + y}, kas hücrelerinin '
          'parçaladığı glikoz ${x + y} − $x = $y olur. Her glikozdan 2 laktik '
          'asit oluştuğundan 2 · $y = ${2 * y} bulunur.',
          positive: true,
        );
      case 8:
        return sayisal(
          '$deney Bu iki olayın glikoliz evresinde oluşan toplam pirüvat '
          '(pirüvik asit) molekülü sayısı kaçtır?',
          2 * (x + y),
          [x + y, 4 * (x + y), 2 * x, 3 * (x + y), 2 * y],
          'Glikolizde 6 karbonlu 1 glikozdan 3 karbonlu 2 pirüvat oluşur. '
          'Toplam pirüvat 2 · ($x + $y) = ${2 * (x + y)} olur.',
          positive: true,
        );
      default:
        return sayisal(
          '$deney Maya hücrelerinin net ATP kazancı ile oluşturduğu CO₂ '
          'molekülü sayısının toplamına, kas hücrelerinin net ATP kazancı '
          'eklenirse hangi sayı bulunur?',
          4 * x + 2 * y,
          [2 * (x + y), 4 * (x + y), 6 * x + 2 * y, 2 * x + 4 * y, 4 * x + 4 * y],
          '$atp $urun Mayalarda 2 · $x ATP ve 2 · $x CO₂, kas hücrelerinde '
          '2 · $y ATP vardır: ${2 * x} + ${2 * x} + ${2 * y} = '
          '${4 * x + 2 * y}.',
          positive: true,
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────── 20. Besinlerin enerji değeri ─────────────────────────

final _f20 = lmAile(
  'biy_besin_enerji',
  'Besinlerin enerji değeri ve günlük enerji payı',
  Topic.biology,
  Difficulty.easy,
  BloomLevel.uygulama,
  (a, b, c) {
    final kh = 10 * (a + 6), yag = b + 5; // gram
    final pro = 5 * (1 + (a + 2 * b) % 6);
    final toplam = 4 * kh + 4 * pro + 9 * yag;
    final gunluk = (a + b).isEven ? 2000 : 2500;
    const deger =
        'Karbonhidrat ve protein gram başına 4 kcal, yağ gram başına 9 kcal '
        'enerji verir.';
    final ogun =
        '$deger Bir öğrenci bir öğünde $kh g karbonhidrat, $pro g protein ve '
        '$yag g yağ tüketiyor.';
    final hesap =
        'Enerji 4 · $kh + 4 · $pro + 9 · $yag = ${4 * kh} + ${4 * pro} + '
        '${9 * yag} = $toplam kcal olur.';
    switch (c) {
      case 0:
        return sayisal(
          '$ogun Öğrencinin bu öğünden aldığı enerji kaç kcal olur?',
          toplam,
          [4 * (kh + pro + yag), 9 * kh + 4 * pro + 4 * yag, 4 * kh + 9 * pro + 9 * yag, 4 * kh + 9 * yag],
          hesap,
          positive: true,
        );
      case 1:
        return sayisal(
          '$deger Bir öğrencinin bir öğünde tükettiği besinlerde $kh g '
          'karbonhidrat ve $pro g protein vardır. Öğünün toplam enerjisi '
          '$toplam kcal olduğuna göre öğündeki yağ miktarı kaç gramdır?',
          yag,
          [9 * yag ~/ 4, 9 * yag, yag + 4, yag + 9, yag + 5, yag + 2],
          'Karbonhidrat ve proteinden gelen enerji 4 · ($kh + $pro) = '
          '${4 * (kh + pro)} kcal olur. Yağdan gelen enerji $toplam − '
          '${4 * (kh + pro)} = ${9 * yag} kcal, yağ miktarı ${9 * yag} / 9 = '
          '$yag g bulunur.',
          positive: true,
        );
      case 2:
        return ondalikli(
          '$ogun Günlük enerji gereksinimi $gunluk kcal olan bu öğrencinin '
          'öğünden aldığı enerji, günlük gereksiniminin yüzde kaçıdır?',
          toplam * 100 / gunluk,
          [4 * (kh + pro + yag) * 100 / gunluk, 100 - toplam * 100 / gunluk, (4 * kh + 4 * pro) * 100 / gunluk, 9 * yag * 100 / gunluk]
              .where(_ikiBasamakli),
          '$hesap Günlük gereksinime oranı $toplam / $gunluk · 100 = '
          '${tr(toplam * 100 / gunluk)} bulunur.',
          positive: true,
        );
      case 3:
        final k = 10 + 2 * a, p = 4 + (a + b) % 8, y = b + 2;
        final gram = const [50, 150, 200, 250][(a + b) % 4];
        final yuz = 4 * k + 4 * p + 9 * y;
        return ondalikli(
          '$deger Bir besinin 100 gramında $k g karbonhidrat, $p g protein ve '
          '$y g yağ vardır. Bu besinden $gram g yiyen bir kişi kaç kcal enerji '
          'alır?',
          yuz * gram / 100,
          [yuz.toDouble(), 4.0 * (k + p + y) * gram / 100, yuz * gram / 1000, yuz * 100 / gram]
              .where(_ikiBasamakli),
          'Besinin 100 gramı 4 · $k + 4 · $p + 9 · $y = $yuz kcal enerji '
          'verir. $gram g için $yuz · $gram / 100 = ${tr(yuz * gram / 100)} '
          'kcal bulunur.',
          positive: true,
        );
      case 4:
        return sayisal(
          '$ogun Bu öğünde karbonhidrat ve proteinden gelen toplam enerji, '
          'yağdan gelen enerjiden kaç kcal fazladır?',
          4 * (kh + pro) - 9 * yag,
          [toplam, 4 * kh - 9 * yag, 4 * (kh + pro) - 4 * yag, 9 * (kh + pro) - 4 * yag],
          'Karbonhidrat ve proteinden 4 · ($kh + $pro) = ${4 * (kh + pro)} '
          'kcal, yağdan 9 · $yag = ${9 * yag} kcal gelir. Fark '
          '${4 * (kh + pro) - 9 * yag} kcal olur.',
          positive: true,
        );
      case 5:
        return sayisal(
          '$deger Bir öğrencinin bir öğünde tükettiği besinlerde $pro g '
          'protein ve $yag g yağ vardır. Öğünün toplam enerjisi $toplam kcal '
          'olduğuna göre öğündeki karbonhidrat miktarı kaç gramdır?',
          kh,
          [kh + 10, kh - 10, 4 * kh ~/ 9, kh + 20, 4 * kh],
          'Protein ve yağdan gelen enerji 4 · $pro + 9 · $yag = '
          '${4 * pro + 9 * yag} kcal olur. Karbonhidrattan gelen enerji '
          '$toplam − ${4 * pro + 9 * yag} = ${4 * kh} kcal, miktarı '
          '${4 * kh} / 4 = $kh g bulunur.',
          positive: true,
        );
      case 6:
        return sayisal(
          '$ogun Günlük enerji gereksinimi $gunluk kcal olan bu öğrenci, '
          'gereksinimini tam karşılamak için günün kalanında kaç kcal daha '
          'enerji almalıdır?',
          gunluk - toplam,
          [gunluk - 4 * (kh + pro + yag), toplam, gunluk - 4 * kh - 9 * yag, gunluk - toplam + 100],
          '$hesap Kalan gereksinim $gunluk − $toplam = ${gunluk - toplam} kcal '
          'bulunur.',
          positive: true,
        );
      case 7:
        return ondalikli(
          '$ogun Öğrenci aynı enerjiyi yalnız proteinden alsaydı kaç gram '
          'protein tüketmesi gerekirdi?',
          toplam / 4,
          [toplam / 9, (kh + pro + yag).toDouble(), toplam / 2, toplam.toDouble()]
              .where(_ikiBasamakli),
          '$hesap Protein gram başına 4 kcal verdiğinden $toplam / 4 = '
          '${tr(toplam / 4)} g protein gerekir.',
          unit: 'g',
          positive: true,
        );
      case 8:
        return sayisal(
          '$deger Bir sporcu antrenmandan önce $kh g karbonhidrat içeren bir '
          'içecek, antrenmandan sonra $yag g yağ içeren bir atıştırmalık '
          'tüketiyor. Karbonhidrattan alınan enerji, yağdan alınan enerjiden '
          'kaç kcal fazladır?',
          4 * kh - 9 * yag,
          [4 * kh + 9 * yag, 9 * kh - 4 * yag, 4 * (kh - yag), kh - yag],
          'Karbonhidrattan 4 · $kh = ${4 * kh} kcal, yağdan 9 · $yag = '
          '${9 * yag} kcal alınır. Fark ${4 * kh - 9 * yag} kcal olur.',
          positive: true,
        );
      default:
        return sayisal(
          '$ogun Öğündeki yağın tamamı yerine aynı kütlede karbonhidrat '
          'tüketilseydi öğünün enerjisi kaç kcal olurdu?',
          toplam - 5 * yag,
          [toplam, toplam + 5 * yag, toplam - 9 * yag, toplam - 4 * yag],
          '$hesap Yağ yerine karbonhidrat alındığında her gram için 9 − 4 = '
          '5 kcal eksilir: $toplam − 5 · $yag = ${toplam - 5 * yag} kcal.',
          positive: true,
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);
