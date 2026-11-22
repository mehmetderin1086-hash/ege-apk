// Lise metin aileleri · Bilgisayar bilimi: sayı sistemleri, veri birimleri,
// mantık kapıları ve algoritmalar (20 aile × 5.000 vaka). Sözde kodlarda tek
// yazım kullanılır: ← atama, · çarpma, mod kalan, div tam sayı bölümüdür;
// "i = 1, 2, …, n için" ve "… olduğu sürece" döngülerinin gövdesi "döngü
// sonu" satırına kadar sürer; dizilerin ilk elemanının indisi 1 alınır.
import 'denge.dart';
import 'ortak.dart';

AdvancedFamily _bs(
  String key,
  String title,
  Difficulty difficulty,
  BloomLevel bloom,
  LmUretec build, {
  bool shortAnswer = true,
}) => lmAile(
  'bs_$key',
  title,
  Topic.computing,
  difficulty,
  bloom,
  build,
  lesson: 'Bilgisayar Bilimi',
  shortAnswer: shortAnswer,
);

// ---------------------------------------------------------------------------
// Ortak yardımcılar
// ---------------------------------------------------------------------------

String _ikilik(int n) => n.toRadixString(2);
String _onaltilik(int n) => n.toRadixString(16).toUpperCase();
String _sekizlik(int n) => n.toRadixString(8);
String _ters(String s) => String.fromCharCodes(s.codeUnits.reversed);
bool _palindrom(String s) => s == _ters(s);

const _altSimge = {2: '₂', 8: '₈', 10: '₁₀', 16: '₁₆'};

/// "(101101)₂" biçiminde tabanlı yazım.
String _tabanli(String rakamlar, int taban) => '($rakamlar)${_altSimge[taban]}';

/// Havuzun [j] numaralı elemanını, adımı havuz boyuyla aralarında asal olan
/// bir dolaşımla verir: j < havuz boyu olan her j farklı bir eleman seçer.
T _dolas<T>(List<T> havuz, int j, int adim) {
  final n = havuz.length;
  var s = adim % n;
  while (s.gcd(n) != 1) {
    s++;
  }
  return havuz[(j * s + 11) % n];
}

/// Sayıyı ikinin kuvvetlerinin toplamı olarak yazar: 45 → "32 + 8 + 4 + 1".
String _kuvvetToplami(int n) => [
  for (var k = n.bitLength - 1; k >= 0; k--)
    if (n >> k & 1 == 1) '${1 << k}',
].join(' + ');

bool _ikininKuvveti(int n) => n > 0 && n & (n - 1) == 0;

/// Onaltılık rakam değeri: '7' → 7, 'B' → 11.
int _rakamDegeri(String r) => int.parse(r, radix: 16);

int _topla(Iterable<int> x) => x.fold(0, (p, q) => p + q);

/// (a, b, c) koordinatlı vakanın 0 … 4999 arasındaki sıra numarası.
int _no(int a, int b, int c) => a + 25 * b + 500 * c;

/// Seçenekleri sınırlı bir havuzdan gelen sayısal soru: üç çeldirici,
/// anahtardan küçük olanların sayısı vakanın hedef sırasına ([hedefSira])
/// eşit olacak biçimde [adaylar] arasından seçilir. Havuz bir yanda kısa
/// kalıyorsa hedef, olası sıralar arasında döndürülerek alınır (ör. yalnız
/// 1, 2 ya da 3 olabiliyorsa 0 yerine 3). Adaylar öncelik sırasıyla (değer,
/// yazım) ikilileridir.
AdvancedItem _sirali(
  String prompt,
  num anahtar,
  String yazim,
  Iterable<(num, String)> adaylar,
  String explanation,
  int i,
) {
  final tekil = <(num, String)>[];
  for (final x in adaylar) {
    if (ayniSecenek(x.$2, yazim) || tekil.any((w) => ayniSecenek(w.$2, x.$2))) {
      continue;
    }
    tekil.add(x);
  }
  final alt = tekil.where((x) => x.$1 < anahtar).length;
  final lo = 3 - (tekil.length - alt) < 0 ? 0 : 3 - (tekil.length - alt);
  final hi = alt > 3 ? 3 : alt, h = hedefSira(i);
  final sira = lo <= hi ? lo + (h - lo) % (hi - lo + 1) : h;
  return AdvancedItem(
    prompt,
    yazim,
    siraliCeldiriciler(anahtar, yazim, tekil, sira),
    explanation,
  );
}

/// Tam sayı yanıtlı, seçenekleri [enAz] … [enCok] aralığında kalan soru
/// (küçük sayımlar): tipik hatalardan sonra ±1 … ±6 komşular eklenir ve
/// çeldiriciler [_sirali] ile seçilir.
AdvancedItem _sinirliSayisal(
  String prompt,
  int answer,
  Iterable<int> alternatives,
  String explanation,
  int i, {
  required int enAz,
  required int enCok,
}) => _sirali(
  prompt,
  answer,
  '$answer',
  [
    for (final x in [
      ...alternatives,
      for (var k = 1; k <= 6; k++) ...[answer + k, answer - k],
    ])
      if (x >= enAz && x <= enCok) (x, '$x'),
  ],
  explanation,
  i,
);

/// Sayısal iki hatalı tasarım: A hatası [yanlislar] içinden bir değer (ör.
/// yanlış dal), B hatası anahtara eklenen [kaymalar] içinden bir hesap hatası;
/// çeldiriciler A, B ve A + B (w, n + e, w + e) olur ve hiçbiri ötekilere
/// anahtardan daha yakın değildir. [yanlislar] içindeki ilk üç değer de tek
/// başına bir tasarımdır. Anahtardan küçük çeldirici sayısı [sira] olan ilk
/// geçerli tasarım, yoksa sıraya en yakını seçilir.
List<int> _ikiHataliSayisal(
  int n,
  List<int> yanlislar,
  List<int> kaymalar,
  int sira, {
  bool Function(int)? uygun,
}) {
  final tasarimlar = [
    if (yanlislar.length >= 3) yanlislar.sublist(0, 3),
    for (final w in yanlislar)
      for (final e in kaymalar) [w, n + e, w + e],
  ];
  List<int>? enIyi;
  var fark = 9;
  for (final t in tasarimlar) {
    if (t.toSet().length != 3 ||
        t.contains(n) ||
        (uygun != null && !t.every(uygun))) {
      continue;
    }
    final d = (t.where((v) => v < n).length - sira).abs();
    if (d < fark) {
      enIyi = t;
      fark = d;
      if (d == 0) break;
    }
  }
  return enIyi!;
}

/// [n] sayısının ikilik gösteriminde 1 (ya da [bit] 0 ise 0) olan, en soldaki
/// basamak dışındaki ve [enAz] numaralı basamaktan başlayan konumlar
/// (sağdan 0 ile başlayarak), [n] sayısına bağlı bir noktadan dolaşılarak.
List<int> _bitKonumlari(int n, int bit, {int enAz = 0}) {
  final l = n.bitLength, r = <int>[];
  if (l - 1 <= enAz) return r;
  final bas = n % (l - 1 - enAz);
  for (var t = 0; t < l - 1 - enAz; t++) {
    final k = enAz + (bas + t) % (l - 1 - enAz);
    if ((n >> k & 1) == bit) r.add(k);
  }
  return r;
}

// ---------------------------------------------------------------------------
// 1. İkilik ve onluk taban arasında dönüşüm
// ---------------------------------------------------------------------------

/// 20 … 1620 arasındaki, ikilik gösterimi tersinden okununca değişen sayılar:
/// kalanları ters sırayla yazma hatası hiçbir vakada anahtarı vermez.
final _ikilikHavuzu = [
  for (var n = 20; n <= 1620; n++)
    if (!_palindrom(_ikilik(n))) n,
];

/// 16 … 255 arasındaki, ikilik gösterimi simetrik olmayan sayılar.
final _ikilikKucuk = [
  for (var n = 16; n <= 255; n++)
    if (!_palindrom(_ikilik(n))) n,
];

/// Gösterim sorularında iki hatalı tasarım: [hatalar] içindeki her A hatası
/// ve [kaymalar] içindeki her B hatası (bir basamağı yanlış bulma; değere
/// uygulanır) için çeldiriciler A(n), B(n) ve A(B(n)) olur. Böylece hiçbir
/// seçenek ötekilere anahtardan daha yakın olmaz. A hatası null verirse o
/// tasarım kullanılmaz. Anahtardan küçük çeldirici sayısı [sira] olan ilk
/// geçerli tasarım, yoksa sıraya en yakını seçilir; [yaz] doğru gösterimi,
/// [deger] bir yazımın sıralamadaki değerini verir.
List<String> _ikiHataliTasarim(
  int n,
  String Function(int) yaz,
  List<String? Function(int)> hatalar,
  List<int Function(int)> kaymalar,
  int sira,
  num Function(String) deger,
) {
  final anahtar = yaz(n), d0 = deger(anahtar);
  List<String>? enIyi;
  var fark = 9;
  for (final h in hatalar) {
    for (final g in kaymalar) {
      final f = g(n);
      final a1 = f > 0 ? h(n) : null, a2 = f > 0 ? h(f) : null;
      if (a1 == null || a2 == null) continue;
      final t = [a1, yaz(f), a2];
      final hepsi = [anahtar, ...t];
      var ayri = true;
      for (var x = 0; x < 4; x++) {
        for (var y = x + 1; y < 4; y++) {
          if (ayniSecenek(hepsi[x], hepsi[y])) ayri = false;
        }
      }
      if (!ayri) continue;
      final d = (t.where((x) => deger(x) < d0).length - sira).abs();
      if (d < fark) {
        enIyi = t;
        fark = d;
        if (d == 0) return t;
      }
    }
  }
  return enIyi!;
}

/// Verilen konumlardaki bitlerden birini değiştiren B hataları.
List<int Function(int)> _bitDegisimleri(List<int> konumlar) => [
  for (final k in konumlar) (int x) => x ^ (1 << k),
];

/// Ondan ikiliğe çevirme sorusunun çeldiricileri. İki tipik hata tek tek ve
/// birlikte uygulanır (A, B ve A + B): A kalanları ters sırayla yazma, ilk
/// kalanı unutma ya da sona fazladan 0 ekleme; B bir kalanı yanlış bulma (bir
/// bitin değişmesi). Böylece hiçbir seçenek ötekilere anahtardan daha yakın
/// olmaz. Anahtardan küçük çeldirici sayısı [sira] olan ilk tasarım seçilir.
List<String> _ikilikCeldiricileri(int n, int sira) {
  final s = _ikilik(n), l = s.length;
  int ters(int x) => int.parse(_ters(_ikilik(x)), radix: 2);
  // Değiştirilen bitler sağdan en az üçüncü basamaktadır: 11 basamaklı
  // gösterimler onluk sayı gibi okunduğunda da seçenekler ayrışır.
  final ic = [for (var t = 0; t < l - 3; t++) 2 + (n + t) % (l - 3)];
  final tasarimlar = [
    for (final k in ic) [ters(n), n ^ (1 << k), ters(n ^ (1 << k))],
    for (final k in ic) ...[
      [n >> 1, n ^ (1 << k), (n ^ (1 << k)) >> 1],
      [n << 1, n ^ (1 << k), (n ^ (1 << k)) << 1],
    ],
  ];
  List<String>? enIyi;
  var fark = 9;
  for (final t in tasarimlar) {
    final yazim = [for (final x in t) _ikilik(x)];
    final hepsi = [s, ...yazim];
    var ayri = true;
    for (var x = 0; x < 4; x++) {
      for (var y = x + 1; y < 4; y++) {
        if (ayniSecenek(hepsi[x], hepsi[y])) ayri = false;
      }
    }
    if (!ayri) continue;
    final d = (t.where((x) => x < n).length - sira).abs();
    if (d < fark) {
      enIyi = yazim;
      fark = d;
      if (d == 0) break;
    }
  }
  return enIyi!;
}

AdvancedItem _ikilikDonusum(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 3) {
    final n = _dolas(_ikilikHavuzu, j + 500 * c, 389);
    final s = _ikilik(n);
    return AdvancedItem(
      'Onluk tabandaki $n sayısı bilgisayar belleğinde ikilik tabanda '
          'saklanacaktır. Bu sayının başında sıfır bulunmayan ikilik gösterimi '
          'nedir?',
      s,
      _ikilikCeldiricileri(n, hedefSira(_no(a, b, c))),
      '${_ikininKuvveti(n) ? '$n sayısı ikinin bir kuvveti olduğundan yalnız $n basamak değerine 1, diğerlerine 0' : '$n = ${_kuvvetToplami(n)} olduğundan bu basamak değerlerine 1, diğerlerine 0'} '
          'yazılır: $s. Art arda ikiye bölmede kalanlar sondan başa doğru '
          'yazılarak da aynı sonuç bulunur.',
    );
  }
  if (c < 6) {
    final n = _dolas(_ikilikHavuzu, j + 500 * (c - 3), 1013);
    final s = _ikilik(n);
    final konum = _topla([
      for (var k = 0; k < s.length; k++)
        if (n >> k & 1 == 1) k + 1,
    ]);
    final hata = _okumaHatalari(n);
    return sayisalSirali(
      'Bilgisayar belleğinde ikilik tabanda ${_tabanli(s, 2)} olarak saklanan '
      'sayının onluk tabandaki değeri kaçtır?',
      n,
      [...hata.take(3), konum, ...hata.skip(3)],
      _ikininKuvveti(n)
          ? '${_tabanli(s, 2)} sayısında yalnız bir basamakta 1 vardır; bu '
                'basamağın değeri $n olur.'
          : '${_tabanli(s, 2)} sayısında 1 bulunan basamakların değerleri '
                'toplanır: ${_kuvvetToplami(n)} = $n.',
      hedefSira(_no(a, b, c)),
      positive: true,
    );
  }
  final k = j + 500 * (c - 6);
  final r = k % _ikilikKucuk.length, q = k ~/ _ikilikKucuk.length;
  final x = _ikilikKucuk[r];
  final y = 12 + (29 * q + 7 * r) % 85;
  final s = _ikilik(x);
  final hata = _okumaHatalari(x);
  final cevir = _ikininKuvveti(x)
      ? '${_tabanli(s, 2)} = $x'
      : '${_tabanli(s, 2)} = ${_kuvvetToplami(x)} = $x';
  if ((q + r).isEven || x <= y || x == 2 * y) {
    return sayisalSirali(
      'İkilik tabanda yazılmış ${_tabanli(s, 2)} sayısı ile onluk tabandaki $y '
          'sayısının toplamı onluk tabanda kaçtır?',
      x + y,
      [for (final h in hata) h + y],
      '$cevir olur. Toplam $x + $y = ${x + y} bulunur.',
      hedefSira(_no(a, b, c)),
      positive: true,
    );
  }
  return sayisalSirali(
    '${_tabanli(s, 2)} − $y işleminde ilk sayı ikilik, ikinci sayı onluk '
        'tabandadır. Bu işlemin sonucu onluk tabanda kaçtır?',
    x - y,
    [
      for (final h in hata.take(3)) h - y,
      x + y,
      for (final h in hata.skip(3)) h - y,
    ],
    '$cevir olur. Fark $x − $y = ${x - y} bulunur.',
    hedefSira(_no(a, b, c)),
    positive: true,
  );
}

/// İkilik gösterimi verilen [x] sayısını onluğa çevirirken yapılan tipik
/// hatalar, öncelik sırasıyla: basamakları ters sırayla okuma, basamak
/// değerlerini 2 ile başlatma, en soldaki basamağı atlama, 1 olan bir
/// basamağın değerini eklemeyi unutma, 0 olan bir basamağın değerini de
/// ekleme, basamak değerlerini bir basamak sağa kaydırma.
List<int> _okumaHatalari(int x) {
  final s = _ikilik(x);
  final bir = _bitKonumlari(x, 1), sifir = _bitKonumlari(x, 0);
  return [
    int.parse(_ters(s), radix: 2),
    2 * x,
    x - (1 << (s.length - 1)),
    if (bir.isNotEmpty) x - (1 << bir.first),
    if (sifir.isNotEmpty) x + (1 << sifir.first),
    x >> 1,
    if (bir.length > 1) x - (1 << bir[1]),
    if (sifir.length > 1) x + (1 << sifir[1]),
  ];
}

// ---------------------------------------------------------------------------
// 2. Onaltılık ve sekizlik tabanlar
// ---------------------------------------------------------------------------

/// İki basamaklı onaltılık sayıların tamamı ve üç basamaklılardan bir seçki;
/// rakamları simetrik olanlar (ters okuma hatası anahtarı verir) dışarıda.
final _onaltiHavuzu = [
  for (var n = 16; n < 256; n++)
    if (!_palindrom(_onaltilik(n))) n,
  for (var n = 259; n < 4096; n += 6)
    if (!_palindrom(_onaltilik(n))) n,
];

/// Üç basamaklı sekizlik sayıların tamamı ve dört basamaklılardan bir seçki;
/// dört basamaklılarda 8² basamağı sıfır değildir (8² yerine 16 alma hatası
/// anahtarı vermez).
final _sekizHavuzu = [
  for (var n = 64; n < 512; n++)
    if (!_palindrom(_sekizlik(n))) n,
  for (var n = 515; n < 4096; n += 8)
    if (!_palindrom(_sekizlik(n)) && _sekizlik(n)[1] != '0') n,
];

/// "1·256 + 10·16 + 7" biçiminde basamak açılımı.
String _acilim(String s, int taban) {
  final p = <String>[];
  for (var k = 0; k < s.length; k++) {
    final d = _rakamDegeri(s[k]);
    var w = 1;
    for (var t = 0; t < s.length - 1 - k; t++) {
      w *= taban;
    }
    p.add(w == 1 ? '$d' : '$d·$w');
  }
  return p.join(' + ');
}

/// Rakamları verilen ağırlıklarla toplar (hatalı okuma çeldiricileri için).
int _agirlikli(List<int> rakam, int Function(int) agirlik) => _topla([
  for (var k = 0; k < rakam.length; k++)
    rakam[k] * agirlik(rakam.length - 1 - k),
]);

int _kuvvet(int x, int n) {
  var r = 1;
  for (var t = 0; t < n; t++) {
    r *= x;
  }
  return r;
}

const _harfNotu = '(A = 10, B = 11, C = 12, D = 13, E = 14, F = 15)';

/// Sağdan [g] bitlik gruplarla tabana çevirme; [soldan] doğruysa gruplar
/// soldan ayrılır (tipik hata).
String _grupla(String bit, int g, {bool soldan = false}) {
  final gruplar = <String>[];
  if (soldan) {
    for (var k = 0; k < bit.length; k += g) {
      gruplar.add(bit.substring(k, k + g > bit.length ? bit.length : k + g));
    }
  } else {
    for (var k = bit.length; k > 0; k -= g) {
      gruplar.insert(0, bit.substring(k - g < 0 ? 0 : k - g, k));
    }
  }
  return gruplar.map((x) => _onaltilik(int.parse(x, radix: 2))).join();
}

/// Sağdan gruplamanın gruplarını boşlukla ayırarak gösterir.
String _gruplarYaz(String bit, int g) {
  final gruplar = <String>[];
  for (var k = bit.length; k > 0; k -= g) {
    gruplar.insert(0, bit.substring(k - g < 0 ? 0 : k - g, k));
  }
  return gruplar.join(' ');
}

String _dolgulu(int d, int g) => _ikilik(d).padLeft(g, '0');

/// Baştaki sıfırları atar.
String _sifirsiz(String s) {
  final t = s.replaceFirst(RegExp('^0+'), '');
  return t.isEmpty ? '0' : t;
}

AdvancedItem _onaltilikDonusum(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 3) {
    final k = j + 500 * c;
    if (k.isEven) {
      final n = _dolas(_onaltiHavuzu, k ~/ 2, 211);
      final s = _onaltilik(n);
      final r = [for (final h in s.split('')) _rakamDegeri(h)];
      final harfli = r.any((d) => d >= 10);
      // Tipik hatalar: basamak değerlerini 10, 8 ya da 16 ile başlayan
      // kuvvetler alma, harf değerlerini kaydırma, ters okuma, 16² yerine 32
      // alma, harf değerlerini yan yana yazma; sonda komşu değerler.
      return sayisalSirali(
        'Onaltılık tabanda ${_tabanli(s, 16)} olarak yazılan sayının onluk '
            'tabandaki değeri kaçtır? $_harfNotu',
        n,
        [
          _agirlikli(r, (e) => _kuvvet(10, e)),
          if (harfli)
            _agirlikli([
              for (final d in r) d >= 10 ? d + 1 : d,
            ], (e) => _kuvvet(16, e)),
          int.parse(_ters(s), radix: 16),
          if (s.length == 3) _agirlikli(r, (e) => e == 2 ? 32 : _kuvvet(16, e)),
          _agirlikli(r, (e) => _kuvvet(8, e)),
          if (harfli) int.parse(r.join()),
          16 * n,
          n + 16,
          n - 16,
          n + 1,
          n - 1,
        ],
        '${_tabanli(s, 16)} = ${_acilim(s, 16)} = $n olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    }
    final n = _dolas(_sekizHavuzu, k ~/ 2, 193);
    final s = _sekizlik(n);
    final r = [for (final h in s.split('')) _rakamDegeri(h)];
    return sayisalSirali(
      'Sekizlik tabanda ${_tabanli(s, 8)} olarak yazılan sayının onluk '
          'tabandaki değeri kaçtır?',
      n,
      [
        int.parse(s),
        int.parse(_ters(s), radix: 8),
        _agirlikli(r, (e) => e == 2 ? 16 : _kuvvet(8, e)),
        _agirlikli(r, (e) => _kuvvet(16, e)),
        n + 8,
        8 * n,
        n - 8,
        n - 1,
        n + 1,
      ],
      '${_tabanli(s, 8)} = ${_acilim(s, 8)} = $n olur.',
      hedefSira(_no(a, b, c)),
      positive: true,
    );
  }
  if (c < 6) {
    final k = j + 500 * (c - 3);
    if (k.isEven) {
      final n = _dolas(_onaltiHavuzu, k ~/ 2, 337);
      final s = _onaltilik(n);
      final r = [for (final h in s.split('')) _rakamDegeri(h)];
      List<int> rakam(int x) => [
        for (final h in _onaltilik(x).split('')) _rakamDegeri(h),
      ];
      // A hataları: kalanları ters sırayla yazma, 16 yerine 8 ile bölme,
      // ilk kalanı unutma, harf yerine rakam değerini yazma, harfleri bir
      // kaydırma. B hatası: bir kalanı bir fazla ya da eksik bulma.
      return AdvancedItem(
        'Onluk tabandaki $n sayısının onaltılık tabandaki gösterimi nedir? '
            '$_harfNotu',
        s,
        _ikiHataliTasarim(
          n,
          _onaltilik,
          [
            (x) => _sifirsiz(_ters(_onaltilik(x))),
            _sekizlik,
            (x) => x < 16 ? null : _onaltilik(x ~/ 16),
            (x) => rakam(x).any((d) => d >= 10) ? rakam(x).join() : null,
            (x) => rakam(x).any((d) => d >= 11)
                ? [for (final d in rakam(x)) _onaltilik(d >= 11 ? d - 1 : d)]
                      .join()
                : null,
          ],
          [(x) => x - 1, (x) => x + 1, (x) => x - 16, (x) => x + 16],
          hedefSira(_no(a, b, c)),
          (x) => int.parse(x, radix: 16),
        ),
        '$n = ${_acilim(s, 16)} olduğundan basamaklar '
            '${r.map((d) => d >= 10 ? '$d (${_onaltilik(d)})' : '$d').join(', ')} '
            'olur: $s. Art arda 16 ile bölmede kalanlar sondan başa yazılarak '
            'da aynı sonuç bulunur.',
      );
    }
    final n = _dolas(_sekizHavuzu, k ~/ 2, 401);
    final s = _sekizlik(n);
    // A hataları: kalanları ters sırayla yazma, ilk kalanı unutma, en büyük
    // rakam 7 olduğu için 7 ile bölme. B hatası: bir kalanı bir fazla ya da
    // eksik bulma. Sıralama onluk okumaya göredir (geçerli sekizlik
    // yazımlarda aynı sıra).
    return AdvancedItem(
      'Onluk tabandaki $n sayısının sekizlik tabandaki gösterimi nedir?',
      s,
      _ikiHataliTasarim(
        n,
        _sekizlik,
        [
          (x) => _sifirsiz(_ters(_sekizlik(x))),
          (x) => x < 8 ? null : _sekizlik(x ~/ 8),
          (x) => x.toRadixString(7),
        ],
        [(x) => x - 1, (x) => x + 1, (x) => x - 8, (x) => x + 8],
        hedefSira(_no(a, b, c)),
        int.parse,
      ),
      '$n = ${_acilim(s, 8)} olduğundan gösterim $s olur. Art arda 8 ile '
          'bölmede kalanlar sondan başa yazılarak da aynı sonuç bulunur.',
    );
  }
  final k = j + 500 * (c - 6);
  final tur = k % 4, m = k ~/ 4;
  if (tur == 0) {
    // İkilikten onaltılığa: bit sayısı 4 ile bölünmez.
    final n = _dolas(_ikilikDortlu, m, 173);
    final bit = _ikilik(n);
    final dogru = _onaltilik(n);
    final tam = (1 << (4 * (bit.length ~/ 4))) - 1;
    // A hataları: soldan gruplama, rakamları ters yazma, üçerli gruplama,
    // soldaki eksik grubu atlama, harf yerine grup değerini yazma. B hatası:
    // bir grubu bir fazla ya da eksik çevirme.
    return AdvancedItem(
      'İkilik tabandaki ${_tabanli(bit, 2)} sayısı, bitleri sağdan dörderli '
          'gruplanarak onaltılık tabana çevrilecektir. Sayının onaltılık '
          'tabandaki gösterimi nedir?',
      dogru,
      _ikiHataliTasarim(
        n,
        _onaltilik,
        [
          (x) => _grupla(_ikilik(x), 4, soldan: true),
          (x) => _sifirsiz(_ters(_onaltilik(x))),
          (x) => _grupla(_ikilik(x), 3),
          (x) => _onaltilik(x & tam),
          (x) {
            final q = [
              for (final h in _onaltilik(x).split('')) _rakamDegeri(h),
            ];
            return q.any((d) => d >= 10) ? q.join() : null;
          },
        ],
        [(x) => x - 1, (x) => x + 1, (x) => x - 16, (x) => x + 16],
        hedefSira(_no(a, b, c)),
        (x) => int.parse(x, radix: 16),
      ),
      'Sağdan dörderli gruplar ${_gruplarYaz(bit, 4)} olur; her grup bir '
          'onaltılık rakam verir: $dogru.',
    );
  }
  if (tur == 1) {
    final n = _dolas(_ikilikUclu, m, 181);
    final bit = _ikilik(n);
    final dogru = _sekizlik(n);
    final tam = (1 << (3 * (bit.length ~/ 3))) - 1;
    // A hataları: soldan gruplama, rakamları ters yazma, dörderli gruplama,
    // soldaki eksik grubu atlama. B hatası: bir grubu bir fazla ya da eksik
    // çevirme. Harfsiz yazımlar onluk okumayla sıralanır.
    return AdvancedItem(
      'İkilik tabandaki ${_tabanli(bit, 2)} sayısı, bitleri sağdan üçerli '
          'gruplanarak sekizlik tabana çevrilecektir. Sayının sekizlik '
          'tabandaki gösterimi nedir?',
      dogru,
      _ikiHataliTasarim(
        n,
        _sekizlik,
        [
          (x) => _grupla(_ikilik(x), 3, soldan: true),
          (x) => _sifirsiz(_ters(_sekizlik(x))),
          (x) => _grupla(_ikilik(x), 4),
          (x) => _sekizlik(x & tam),
        ],
        [(x) => x - 1, (x) => x + 1, (x) => x - 8, (x) => x + 8],
        hedefSira(_no(a, b, c)),
        (x) => int.tryParse(x) ?? int.parse(x, radix: 16),
      ),
      'Sağdan üçerli gruplar ${_gruplarYaz(bit, 3)} olur; her grup bir '
          'sekizlik rakam verir: $dogru.',
    );
  }
  if (tur == 2) {
    final n = _dolas(_onaltiIc, m, 157);
    final s = _onaltilik(n);
    final r = [for (final h in s.split('')) _rakamDegeri(h)];
    final dogru = _ikilik(n);
    List<int> rakam(int x) => [
      for (final h in _onaltilik(x).split('')) _rakamDegeri(h),
    ];
    final l = n.bitLength;
    // Hatalar: rakamları dolgusuz yazma, rakamları ters sırayla yazma,
    // rakamları üç bitle yazma; her biri bir bitin yanlış yazılmasıyla
    // birlikte de kullanılır.
    return AdvancedItem(
      'Onaltılık tabandaki ${_tabanli(s, 16)} sayısının her rakamı dört bitle '
          'yazılarak ikilik tabana çevrilecektir. Sayının başında sıfır '
          'bulunmayan ikilik gösterimi nedir? $_harfNotu',
      dogru,
      _ikiHataliTasarim(
        n,
        _ikilik,
        [
          (x) => rakam(x).map(_ikilik).join(),
          (x) => _sifirsiz(rakam(x).reversed.map((d) => _dolgulu(d, 4)).join()),
          (x) => _sifirsiz(rakam(x).map((d) => _dolgulu(d, 3)).join()),
        ],
        _bitDegisimleri([for (var t = 0; t < l - 1; t++) (n + t) % (l - 1)]),
        hedefSira(_no(a, b, c)),
        (x) => int.parse(x, radix: 2),
      ),
      'Rakamlar dörder bitle ${r.map((d) => _dolgulu(d, 4)).join(' ')} olarak '
          'yazılır; baştaki sıfırlar atılınca $dogru elde edilir.',
    );
  }
  final n = _dolas(_sekizIc, m, 163);
  final s = _sekizlik(n);
  final r = [for (final h in s.split('')) _rakamDegeri(h)];
  final dogru = _ikilik(n);
  List<int> rakam(int x) => [
    for (final h in _sekizlik(x).split('')) _rakamDegeri(h),
  ];
  final l = n.bitLength;
  return AdvancedItem(
    'Sekizlik tabandaki ${_tabanli(s, 8)} sayısının her rakamı üç bitle '
        'yazılarak ikilik tabana çevrilecektir. Sayının başında sıfır '
        'bulunmayan ikilik gösterimi nedir?',
    dogru,
    _ikiHataliTasarim(
      n,
      _ikilik,
      [
        (x) => rakam(x).map(_ikilik).join(),
        (x) => _sifirsiz(rakam(x).map((d) => _dolgulu(d, 4)).join()),
        (x) => _sifirsiz(rakam(x).reversed.map((d) => _dolgulu(d, 3)).join()),
      ],
      _bitDegisimleri([for (var t = 0; t < l - 1; t++) (n + t) % (l - 1)]),
      hedefSira(_no(a, b, c)),
      (x) => int.parse(x, radix: 2),
    ),
    'Rakamlar üçer bitle ${r.map((d) => _dolgulu(d, 3)).join(' ')} olarak '
        'yazılır; baştaki sıfırlar atılınca $dogru elde edilir.',
  );
}

/// Bit sayısı 4 ile bölünmeyen ve soldan gruplama hatası farklı sonuç veren
/// sayılar (6, 7, 9, 10 ya da 11 bit).
final _ikilikDortlu = [
  for (var n = 32; n < 2048; n++)
    if (n.bitLength % 4 != 0 &&
        _grupla(_ikilik(n), 4, soldan: true) != _onaltilik(n) &&
        !_palindrom(_onaltilik(n)))
      n,
];

/// Bit sayısı 3 ile bölünmeyen (7, 8, 10 ya da 11 bit) sayılar.
final _ikilikUclu = [
  for (var n = 64; n < 2048; n++)
    if (n.bitLength % 3 != 0 &&
        _grupla(_ikilik(n), 3, soldan: true) != _sekizlik(n) &&
        !_palindrom(_sekizlik(n)))
      n,
];

/// İçinde 8 değerinden küçük bir rakam bulunan, iki ya da üç basamaklı
/// onaltılık sayılar (dolgusuz yazma hatası farklı sonuç versin diye).
final _onaltiIc = [
  for (var n = 16; n < 4096; n++)
    if (_onaltilik(n).substring(1).split('').any((h) => _rakamDegeri(h) < 8) &&
        !_palindrom(_onaltilik(n)))
      n,
];

/// İlk rakamı dışında 4 değerinden küçük rakam içeren sekizlik sayılar.
final _sekizIc = [
  for (var n = 64; n < 4096; n++)
    if (_sekizlik(n).substring(1).split('').any((h) => _rakamDegeri(h) < 4) &&
        !_palindrom(_sekizlik(n)))
      n,
];

// ---------------------------------------------------------------------------
// 3. İkilik tabanda toplama, çıkarma ve kaydırma
// ---------------------------------------------------------------------------

/// Toplamada en az iki elde oluşan sayı çiftleri (x > y).
final _toplamaCiftleri = [
  for (var x = 40; x < 256; x += 3)
    for (var y = 9; y < 128 && y < x; y += 2)
      if (_ikilik(x & y).replaceAll('0', '').length >= 2) (x, y),
];

/// Çıkarmada en az bir ödünç alınan sayı çiftleri (x > y).
final _cikarmaCiftleri = [
  for (var x = 40; x < 256; x += 3)
    for (var y = 9; y < x - 4; y += 2)
      if (~x & y != 0 && x != 2 * y) (x, y),
];

/// İlk elde (ya da ödünç) oluşan basamak: elde sayılmazsa sonuç 2^(p+1)
/// kadar değişir.
int _ilkElde(int x, int y, {required bool cikarma}) {
  var elde = 0;
  for (var p = 0; p < 12; p++) {
    final u = x >> p & 1, v = y >> p & 1;
    if (cikarma) {
      if (u - v - elde < 0) return p;
      elde = 0;
    } else {
      if (u + v + elde >= 2) return p;
      elde = 0;
    }
  }
  return 0;
}

AdvancedItem _ikilikIslem(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 4) {
    final (x, y) = _dolas(_toplamaCiftleri, j + 500 * c, 2003);
    final t = x + y, p = _ilkElde(x, y, cikarma: false);
    return secenekli(
      'İkilik tabanda ${_tabanli(_ikilik(x), 2)} + ${_tabanli(_ikilik(y), 2)} '
          'toplama işlemi yapılıyor. Sonucun ikilik tabandaki gösterimi nedir?',
      _ikilik(t),
      // Kökteki bir sayıya eşit aday atlanır: y sayısının bitleri x içinde
      // kalınca VEYA hatası x sayısının kendisini verir.
      [
        for (final v in [x ^ y, t - (1 << (p + 1)), x | y, t + 4, t - 2, t + 8])
          if (v > 0 && v != x && v != y) _ikilik(v),
      ],
      'Sağdan başlayarak basamaklar toplanır; 1 + 1 = 10 olduğundan 0 yazılıp 1 '
          'elde bir sonraki basamağa aktarılır. Onluk tabanda denetim: $x + $y '
          '= $t ve $t = ${_tabanli(_ikilik(t), 2)}.',
    );
  }
  if (c < 7) {
    final (x, y) = _dolas(_cikarmaCiftleri, j + 500 * (c - 4), 1201);
    final f = x - y, p = _ilkElde(x, y, cikarma: true);
    return secenekli(
      'İkilik tabanda ${_tabanli(_ikilik(x), 2)} − ${_tabanli(_ikilik(y), 2)} '
          'çıkarma işlemi yapılıyor. Sonucun başında sıfır bulunmayan ikilik '
          'gösterimi nedir?',
      _ikilik(f),
      [
        for (final v in [x ^ y, f + (1 << (p + 1)), x + y, f + 2, f - 1, f + 4])
          if (v > 0 && v != x && v != y) _ikilik(v),
      ],
      'Sağdan başlanır; 0 − 1 yapılamayan basamakta soldaki basamaktan ödünç '
          'alınır (10 − 1 = 1) ve o basamak bir azaltılır. Onluk tabanda '
          'denetim: $x − $y = $f ve $f = ${_tabanli(_ikilik(f), 2)}.',
    );
  }
  // Kaydırma: x ∈ [33, 1023], k ∈ {1, 2, 3}, yön sola ya da sağa.
  final m = j + 500 * (c - 7); // 0 … 1499
  final kay = 1 + m % 3, sola = (m ~/ 3).isEven;
  final x = 33 + (m ~/ 6 * 4 + m % 3 + (sola ? 0 : 2)) % 990;
  final s = _ikilik(x), us = 1 << kay;
  if (sola) {
    return sayisal(
      'İkilik tabandaki ${_tabanli(s, 2)} sayısına $kay bitlik sola kaydırma '
          'uygulanıyor: bitler $kay basamak sola kayar ve sağdan $kay tane 0 '
          'eklenir. Elde edilen sayının onluk tabandaki değeri kaçtır?',
      x * us,
      [x * kay, x ~/ us, x * us * 2, x * us ~/ 2],
      '${_tabanli(s, 2)} = $x olur. Sola her bitlik kaydırma sayıyı 2 ile '
          'çarpar; $kay bitlik kaydırma $us ile çarpmadır: $x · $us = '
          '${x * us}.',
      positive: true,
    );
  }
  return sayisal(
    'İkilik tabandaki ${_tabanli(s, 2)} sayısına $kay bitlik sağa kaydırma '
        'uygulanıyor: bitler $kay basamak sağa kayar ve en sağdaki $kay bit '
        'atılır. Elde edilen sayının onluk tabandaki değeri kaçtır?',
    x ~/ us,
    [x * us, x ~/ kay, x ~/ us + 1, x ~/ (us * 2)],
    '${_tabanli(s, 2)} = $x olur. Sağa her bitlik kaydırma sayıyı 2 ile tam '
        'böler; $kay bitlik kaydırma $us ile tam bölmedir: $x div $us = '
        '${x ~/ us}.',
    positive: true,
  );
}

// ---------------------------------------------------------------------------
// 4. Veri birimleri ve aktarım
// ---------------------------------------------------------------------------

/// Dönüşüm türleri: kaynak birim, hedef birim, çarpan (bölme türlerinde
/// bölen), türün kökte verilen birim eşitlikleri.
const _donusumler = [
  ('GB', 'MB', 1024, '1 GB = 1024 MB'),
  ('MB', 'KB', 1024, '1 MB = 1024 KB'),
  ('KB', 'bayt', 1024, '1 KB = 1024 bayt'),
  ('GB', 'KB', 1048576, '1 GB = 1024 MB ve 1 MB = 1024 KB'),
  ('KB', 'bit', 8192, '1 KB = 1024 bayt ve 1 bayt = 8 bit'),
  ('MB', 'bayt', 1048576, '1 MB = 1024 KB ve 1 KB = 1024 bayt'),
  ('KB', 'MB', 1024, '1 MB = 1024 KB'),
  ('MB', 'GB', 1024, '1 GB = 1024 MB'),
  ('bit', 'KB', 8192, '1 bayt = 8 bit ve 1 KB = 1024 bayt'),
  ('bayt', 'KB', 1024, '1 KB = 1024 bayt'),
];

/// Kaynak birimin büyüklüğüne uygun bağlamlar: KB ve altı, MB, GB.
const _veriAdlari = [
  [
    'Bir metin belgesinin boyutu',
    'Bir e-posta iletisinin boyutu',
    'Bir kaynak kod dosyasının boyutu',
    'Bir simge dosyasının boyutu',
    'Bir web sayfasının boyutu',
  ],
  [
    'Bir video klibin boyutu',
    'Bir sunum dosyasının boyutu',
    'Bir fotoğraf albümünün boyutu',
    'Bir uygulama güncellemesinin boyutu',
    'Bir ses kaydının boyutu',
  ],
  [
    'Bir yedekleme klasörünün boyutu',
    'Bir film arşivinin boyutu',
    'Bir oyunun kurulum dosyalarının boyutu',
    'Bir sunucu yedeğinin boyutu',
    'Bir fotoğraf arşivinin boyutu',
  ],
];

/// Dönüşüm türünün kaynak büyüklüğü: 0 küçük (bit, bayt, KB), 1 MB, 2 GB.
const _veriOlcegi = [2, 1, 0, 2, 0, 1, 1, 2, 0, 0];

/// Fotoğraf, film, belge ve uygulama bağlamlarında (kapasite, birim,
/// dosya, dosya birimi, kapasite değerleri, dosya boyutu aralığı).
const _kapasiteBaglami = [
  ('fotoğraf', 'GB', 'MB', [2, 4, 8, 16, 32], 3, 14),
  ('film', 'GB', 'MB', [4, 8, 16, 32, 64, 128], 650, 1500),
  ('belge', 'MB', 'KB', [10, 15, 20, 25, 30], 150, 950),
  ('uygulama', 'GB', 'MB', [3, 5, 6, 7, 9, 10, 11, 12], 45, 400),
];

/// Kapasite sorusunun kökü: bağlam [t], kapasite [x], dosya boyutu [y].
String _kapasiteKoku(int t, int x, int y) => switch (t) {
  0 =>
    'Kapasitesi $x GB olan bir bellek kartına her biri $y MB büyüklüğünde '
        'fotoğraflar kaydedilecektir. Karta bu fotoğraflardan en çok kaç tane '
        'sığar? (1 GB = 1024 MB alınız.)',
  1 =>
    'Kapasitesi $x GB olan taşınabilir bir belleğe her biri $y MB '
        'büyüklüğünde filmler kaydedilecektir. Belleğe bu filmlerden en çok kaç '
        'tane sığar? (1 GB = 1024 MB alınız.)',
  2 =>
    'Bir e-posta servisinde bir iletiye eklenen dosyaların toplam boyutu en '
        'çok $x MB olabilir. Her biri $y KB büyüklüğündeki belgelerden bir '
        'iletiye en çok kaç tane eklenebilir? (1 MB = 1024 KB alınız.)',
  _ =>
    'Bir telefonda $x GB boş alan vardır. Her biri $y MB büyüklüğündeki '
        'uygulamalardan bu alana en çok kaç tane yüklenebilir? (1 GB = 1024 '
        'MB alınız.)',
};

/// Kapasite vakaları: (bağlam, kapasite, dosya boyutu). Kalan sıfır olmaz;
/// 1000 ile çevirme ve GB başına hesaplayıp çarpma hataları anahtarı vermez.
final _kapasiteHavuzu = [
  for (var t = 0; t < _kapasiteBaglami.length; t++)
    for (final x in _kapasiteBaglami[t].$4)
      for (var y = _kapasiteBaglami[t].$5; y <= _kapasiteBaglami[t].$6; y++)
        if ((1024 * x) % y != 0 &&
            1024 * x ~/ y != 1000 * x ~/ y &&
            1024 * x ~/ y != x * (1024 ~/ y) &&
            1024 * x ~/ y >= 3)
          (t, x, y),
];

const _hizlar = [4, 5, 8, 10, 16, 20, 25, 32, 40, 50, 64, 80, 100];

/// İndirme vakaları: (boyut milyon bayt, hız Mbps); süre tam sayı saniye ve
/// kökteki sayılardan farklıdır.
final _indirmeHavuzu = [
  for (var n = 6; n <= 900; n++)
    for (final r in _hizlar)
      if (8 * n % r == 0 &&
          8 * n ~/ r >= 5 &&
          8 * n ~/ r <= 900 &&
          ![1, 6, 8, 10, n, r].contains(8 * n ~/ r))
        (n, r),
];

/// Kopyalama vakaları: (boyut GB, hız MB/s); süre tam sayı saniye.
final _kopyaHavuzu = [
  for (var x = 2; x <= 64; x++)
    for (var y = 16; y <= 512; y++)
      if (1024 * x % y == 0 &&
          1024 * x ~/ y >= 10 &&
          1024 * x ~/ y <= 2000 &&
          ![x, y, 1024].contains(1024 * x ~/ y))
        (x, y),
];

AdvancedItem _veriBirim(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 3) {
    final k = j + 500 * c;
    final tur = k % 10, m = k ~/ 10;
    final (kaynak, hedef, f, esitlik) = _donusumler[tur];
    final ad = sec(_veriAdlari[_veriOlcegi[tur]], m + tur);
    if (tur < 6) {
      final x = 2 + m;
      final dogru = x * f;
      // Tipik hatalar: 1024 yerine 1000 alma, bir adım fazla ya da eksik
      // çevirme, bit ile baytı karıştırma (8 ile çarpma ya da bölme),
      // çarpanları toplama, 1024 · x çarpımında 24 · x terimini unutma; sonda
      // bir birim fazla ya da eksik komşu değerler.
      final List<int> hatalar = switch (tur) {
        0 || 1 => [
          x * 1000,
          x * 1048576,
          128 * x,
          8192 * x,
          1000 * x + 24,
          f * (x + 1),
          f * (x - 1),
        ],
        2 => [
          x * 1000,
          x * 8192,
          x * 1048576,
          128 * x,
          8 * x,
          1000 * x + 24,
          f * (x + 1),
        ],
        3 || 5 => [
          x * 1024,
          x * 1000000,
          x * 1024000,
          8 * f * x,
          2048 * x,
          1024 * f * x,
          f * (x + 1),
        ],
        _ => [
          x * 1024,
          x * 8000,
          x * 8,
          8 * 1048576 * x,
          128 * x,
          64 * 1024 * x,
          f * (x + 1),
        ],
      };
      return sayisalSirali(
        '$ad $x $kaynak olarak verilmiştir. $esitlik olduğuna göre bu boyut '
            'kaç $hedef eder?',
        dogru,
        hatalar,
        '${esitlik.replaceAll(' ve ', ', ')} olduğundan $x $kaynak = $x · $f '
            '= $dogru $hedef olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    }
    // Bölme türleri: sonuç en çok iki ondalık basamaklıdır.
    final v = 5 + m + (tur == 8 && m >= 27 ? 1 : 0);
    final x = tur == 8 ? 2048 * v : 256 * v;
    final dogru = x / f;
    // Küçük yanda: bit ile baytı karıştırıp ayrıca 8 ile bölme, ondalık
    // kısmı atma; sonda çeyrek birim komşular.
    final List<double> hatalar = [
      ...switch (tur) {
        6 || 7 => [x / 1000, x * 1024.0, dogru * 8],
        8 => [x / 1024, x / 8, x / 8000],
        _ => [x / 1000, x / 8, x * 8 / 1024],
      },
      dogru / 8,
      if (v % 4 != 0) (v ~/ 4).toDouble(),
      (v - 1) / 4,
      (v + 1) / 4,
      (v - 2) / 4,
      (v + 2) / 4,
    ];
    return ondalikliSirali(
      '$ad $x $kaynak olarak verilmiştir. $esitlik olduğuna göre bu boyut '
          'kaç $hedef eder?',
      dogru,
      hatalar,
      '${esitlik.replaceAll(' ve ', ', ')} olduğundan $x $kaynak = $x / $f = '
          '${tr(dogru)} $hedef olur.',
      hedefSira(_no(a, b, c)),
      positive: true,
    );
  }
  if (c < 6) {
    final (t, x, y) = _dolas(_kapasiteHavuzu, j + 500 * (c - 3), 3001);
    final (ad, kb, db, _, _, _) = _kapasiteBaglami[t];
    final adet = 1024 * x ~/ y, kalan = 1024 * x - adet * y;
    // Bölüm ve kalan birlikte yazılır: yuvarlanmış bölüm (ör. 98,997 → 99)
    // açıklamada yanıtla çelişmez.
    // Tipik hatalar: 1000 ile çevirme, kalanı yuvarlayıp bir fazla sayma,
    // birim başına sığanı aşağı ya da yukarı yuvarlayıp çarpma, ikisini
    // birlikte yapma (1000 ve birim başına aşağı yuvarlama).
    final ceil = (1024 + y - 1) ~/ y;
    return sayisalSirali(
      _kapasiteKoku(t, x, y),
      adet,
      [1000 * x ~/ y, adet + 1, x * (1024 ~/ y), x * ceil, x * (1000 ~/ y)],
      '$x $kb = $x · 1024 = ${1024 * x} $db eder. ${1024 * x} = $adet · $y + '
      '$kalan olduğundan en çok $adet $ad sığar; kalan $kalan $db bir $ad '
      'daha almaya yetmez.',
      hedefSira(_no(a, b, c)),
      positive: true,
    );
  }
  final k = j + 500 * (c - 6);
  final tur = k % 3, m = k ~/ 3;
  if (tur == 0) {
    final (n, r) = _dolas(_indirmeHavuzu, m, 4001);
    final t = 8 * n ~/ r, d = (t + 4) ~/ 8;
    // 8 ile çarpmayı unutma, 8 ile bölme ve iki kez 8 ile çarpma
    // hatalarından sonra yaklaşık %12 ve %25 uzaklıkta komşular.
    return ondalikliSirali(
      'Boyutu $n milyon bayt olan bir dosya, hızı $r Mbps olan bir bağlantıyla '
          'indiriliyor. 1 bayt = 8 bit ve 1 Mbps = 10⁶ bit/s olduğuna göre '
          'indirme kaç saniye sürer?',
      t.toDouble(),
      [
        n / r,
        n / (8 * r),
        64 * n / r,
        for (final k in [1, -1, 2, -2]) (t + k * d).toDouble(),
      ],
      'Dosya $n · 10⁶ · 8 = ${8 * n} · 10⁶ bittir. Hız $r · 10⁶ bit/s olduğundan '
          'süre ${8 * n} / $r = $t saniye olur.',
      hedefSira(_no(a, b, c)),
      positive: true,
    );
  }
  if (tur == 1) {
    final (x, y) = _dolas(_kopyaHavuzu, m, 2999);
    final t = 1024 * x ~/ y, d = (t + 4) ~/ 8;
    return ondalikliSirali(
      'Boyutu $x GB olan bir yedek dosyası, saniyede $y MB hızla harici diske '
          'kopyalanıyor. 1 GB = 1024 MB olduğuna göre kopyalama kaç saniye '
          'sürer?',
      t.toDouble(),
      [
        1000 * x / y,
        8192 * x / y,
        128 * x / y,
        for (final k in [1, -1, 2, -2]) (t + k * d).toDouble(),
      ],
      '$x GB = ${1024 * x} MB eder. Süre ${1024 * x} / $y = $t saniye olur.',
      hedefSira(_no(a, b, c)),
      positive: true,
    );
  }
  // Belirli sürede indirilen veri miktarı (süre dakika cinsinden).
  final r = sec(_hizlar, m), dk = 2 + m ~/ _hizlar.length;
  final miktar = r * 60 * dk / 8;
  // Tipik hatalar: dakikayı saniyeye çevirmeme, 8 ile bölmeyi unutma ya da
  // iki kez bölme, 8 ile bölme yerine çarpma, dakikayı 3600 saniye alma,
  // süreyle çarpmayı unutma.
  return ondalikliSirali(
    'Hızı $r Mbps olan bir bağlantıyla $dk dakika boyunca kesintisiz indirme '
        'yapılıyor. 1 bayt = 8 bit ve 1 Mbps = 10⁶ bit/s olduğuna göre bu sürede '
        'kaç milyon bayt veri indirilir?',
    miktar,
    [
      r * dk / 8,
      r * 60.0 * dk,
      r * 60 * dk / 64,
      r * 480.0 * dk,
      r * 3600 * dk / 8,
      r * 60 / 8,
    ],
    '$dk dakika ${60 * dk} saniyedir. İndirilen veri $r · 10⁶ · ${60 * dk} = '
        '${r * 60 * dk} · 10⁶ bit, yani ${r * 60 * dk} / 8 = ${tr(miktar)} '
        'milyon bayt olur.',
    hedefSira(_no(a, b, c)),
    positive: true,
  );
}

// ---------------------------------------------------------------------------
// 5. Sıkıştırılmamış görüntü ve ses dosyasının boyutu
// ---------------------------------------------------------------------------

const _renkDerinlikleri = [1, 8, 16, 24, 32];

/// Görüntü vakaları: (genişlik, yükseklik, renk derinliği); boyut KB ya da MB
/// cinsinden en çok iki ondalık basamakla tam yazılır.
final _goruntuHavuzu = [
  for (var p = 10; p <= 160; p++)
    for (var q = 8; q <= 120; q++)
      if (q <= p && 5 * p <= 12 * q)
        for (final d in _renkDerinlikleri)
          if ((256 * p * q * d) % 2048 == 0 &&
              ![
                16 * p,
                16 * q,
                d,
                1,
                8,
                256,
                1024,
              ].contains(_goruntuBoyutu(16 * p, 16 * q, d)))
            (16 * p, 16 * q, d),
];

/// Görüntü verisinin soruda istenen birimdeki (KB ya da MB) boyutu.
double _goruntuBoyutu(int w, int h, int d) {
  final bayt = w * h * d ~/ 8;
  final mb = bayt >= 4 * 1048576 && bayt % 262144 == 0;
  return bayt / (mb ? 1048576 : 1024);
}

/// Renk derinliğini bulma sorusu: 16, 24 ya da 32 bit (kökte 1 bayt = 8 bit
/// yazdığı için 8 bit yanıtı kullanılmaz).
final _derinlikHavuzu = [
  for (final x in _goruntuHavuzu)
    if (x.$3 >= 16) x,
];

String _derinlikYaz(int d) => switch (d) {
  1 => '1 bit (siyah-beyaz)',
  8 => '8 bit (256 renk)',
  _ => '$d bit',
};

const _ornekleme = [8000, 11025, 16000, 22050, 32000, 44100, 48000];

/// Ses vakaları: (örnekleme hızı, bit derinliği, kanal sayısı, süre s);
/// boyut KB cinsinden en çok iki ondalık basamakla tam yazılır.
final _sesHavuzu = [
  for (final f in _ornekleme)
    for (final bd in const [8, 16, 24])
      for (final k in const [1, 2])
        for (var t = 5; t <= 240; t++)
          if ((f * bd * k * t * 100) % 8192 == 0 &&
              ![8, 16, 24].contains(t) &&
              ![
                f,
                bd,
                k,
                t,
                t ~/ 60,
                1,
                8,
                1024,
              ].contains(f * bd * k * t / 8192))
            (f, bd, k, t),
];

String _kanalYaz(int k) =>
    k == 1 ? 'tek kanallı (mono)' : 'iki kanallı (stereo)';

String _sureYaz(int t) => t % 60 == 0 ? '${t ~/ 60} dakikalık' : '$t saniyelik';

AdvancedItem _dosyaBoyut(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 4) {
    final (w, h, d) = _dolas(_goruntuHavuzu, j + 500 * c, 7919);
    final bayt = w * h * d ~/ 8;
    final mb = bayt >= 4 * 1048576 && bayt % 262144 == 0;
    final birim = mb ? 'MB' : 'KB', bolen = mb ? 1048576 : 1024;
    final dogru = bayt / bolen;
    return ondalikli(
      'Genişliği $w piksel, yüksekliği $h piksel olan sıkıştırılmamış bir '
          'görüntüde renk derinliği (piksel başına bit sayısı) '
          '${_derinlikYaz(d)} olarak verilmiştir. 1 bayt = 8 bit ve 1 KB = '
          '1024 bayt${mb ? ', 1 MB = 1024 KB' : ''} olduğuna göre görüntü '
          'verisi kaç $birim yer kaplar?',
      dogru,
      [
        dogru * 8,
        bayt / (mb ? 1000000 : 1000),
        if (d != 24) dogru * 24 / d else dogru / 3,
        dogru * 1024,
      ],
      'Piksel sayısı $w · $h = ${w * h}, toplam bit ${w * h} · $d = '
          '${w * h * d} olur. Bu ${w * h * d} / 8 = $bayt bayt, yani $bayt / '
          '$bolen = ${tr(dogru)} $birim eder.',
      positive: true,
    );
  }
  if (c < 7) {
    final (f, bd, k, t) = _dolas(_sesHavuzu, j + 500 * (c - 4), 6007);
    final bit = f * bd * k * t;
    final dogru = bit / 8192;
    final dakika = t % 60 == 0;
    return ondalikli(
      'Örnekleme hızı $f Hz, bit derinliği $bd bit olan ${_kanalYaz(k)} '
          '${_sureYaz(t)} sıkıştırılmamış bir ses kaydı yapılıyor. 1 bayt = 8 '
          'bit ve 1 KB = 1024 bayt olduğuna göre ses verisi kaç KB yer kaplar?',
      dogru,
      [
        dogru * 8,
        k == 2 ? dogru / 2 : dogru * 2,
        bit / 8000,
        if (dakika) dogru / 60,
      ],
      '${dakika ? '${t ~/ 60} dakika = $t saniye olur. ' : ''}Toplam bit $f · '
          '$bd · $k · $t = $bit, bayt $bit / 8 = ${bit ~/ 8} olur. Boyut '
          '${bit ~/ 8} / 1024 = ${tr(dogru)} KB eder.',
      positive: true,
    );
  }
  final m = j + 500 * (c - 7);
  if (m.isEven) {
    final (w, h, d) = _dolas(_derinlikHavuzu, m ~/ 2, 4999);
    final kb = w * h * d / 8192;
    return ondalikli(
      'Genişliği $w piksel, yüksekliği $h piksel olan sıkıştırılmamış bir '
          'görüntünün verisi ${tr(kb)} KB yer kaplamaktadır. 1 bayt = 8 bit ve '
          '1 KB = 1024 bayt olduğuna göre görüntünün renk derinliği (piksel '
          'başına bit sayısı) kaç bittir?',
      d.toDouble(),
      [d / 8, d * 1000 / 1024, if (d <= 16) _kuvvet(2, d).toDouble()],
      '${tr(kb)} KB = ${tr(kb)} · 1024 · 8 = ${w * h * d} bit eder. Piksel '
          'sayısı $w · $h = ${w * h} olduğundan renk derinliği ${w * h * d} / '
          '${w * h} = $d bit olur.',
      positive: true,
    );
  }
  final (f, bd, k, t) = _dolas(_sesHavuzu, m ~/ 2, 3989);
  final kb = f * bd * k * t / 8192;
  return ondalikli(
    'Örnekleme hızı $f Hz, bit derinliği $bd bit olan ${_kanalYaz(k)} '
        'sıkıştırılmamış bir ses kaydının verisi ${tr(kb)} KB yer kaplamaktadır. '
        '1 bayt = 8 bit ve 1 KB = 1024 bayt olduğuna göre kayıt kaç saniye '
        'sürmektedir?',
    t.toDouble(),
    // Kanal hatası: stereoda kanal sayısını unutmak süreyi iki katına,
    // monoda iki kanal saymak yarıya indirir.
    [k == 2 ? 2.0 * t : t / 2, t / 8, t * 1000 / 1024],
    '${tr(kb)} KB = ${tr(kb)} · 1024 · 8 = ${f * bd * k * t} bit eder. Bir '
        'saniyelik kayıt $f · $bd · $k = ${f * bd * k} bit olduğundan süre '
        '${f * bd * k * t} / ${f * bd * k} = $t saniye olur.',
    positive: true,
  );
}

// ---------------------------------------------------------------------------
// 6. RGB renk kodları
// ---------------------------------------------------------------------------

const _renkYerleri = [
  'Bir web sayfasında',
  'Bir çizim programında',
  'Bir logo tasarımında',
  'Bir sunum şablonunda',
  'Bir oyunun arayüzünde',
];

const _bilesenAdlari = ['kırmızı', 'yeşil', 'mavi'];

const _renkKurali =
    '#RRGGBB biçimindeki renk kodunda ilk iki onaltılık rakam kırmızı, sonraki '
    'iki rakam yeşil, son iki rakam mavi bileşenin 0 ile 255 arasındaki '
    'değerini gösterir.';

String _bayt(int x) => _onaltilik(x).padLeft(2, '0');
String _renkKodu(List<int> r) => '#${r.map(_bayt).join()}';

/// Bileşenleri birbirinden farklı; her bileşeni 16 ile 255 arasında ve iki
/// onaltılık rakamı farklı olan renkler (ters okuma hatası anahtarı vermez).
final _renkHavuzu = () {
  final r = <List<int>>[];
  bool iyi(int u) => u >= 16 && u >> 4 != (u & 15);
  for (var t = 0; r.length < 5000; t++) {
    final v = (t * 2654435761 + 977) & 0xFFFFFF;
    final x = v >> 16, y = v >> 8 & 255, z = v & 255;
    if (iyi(x) && iyi(y) && iyi(z) && x != y && y != z && x != z) {
      r.add([x, y, z]);
    }
  }
  return r;
}();

/// Harf değerlerini bir fazla sanma hatası (A = 11, …).
int _harfKaymasi(int u) {
  final d1 = u >> 4, d0 = u & 15;
  return (d1 >= 10 ? d1 + 1 : d1) * 16 + (d0 >= 10 ? d0 + 1 : d0);
}

String _baytCoz(int u) => '${u >> 4}·16 + ${u & 15} = $u';

AdvancedItem _rgb(int a, int b, int c) {
  final j = a + 25 * b;
  final yer = sec(_renkYerleri, a + b);
  if (c < 4) {
    final k = j + 500 * c;
    final r = _renkHavuzu[k];
    // Bileşenin onluk değeri renk kodunda rakam dizisi olarak görünmesin.
    final gorunen = {
      for (final m in RegExp(r'\d+').allMatches(_renkKodu(r))) int.parse(m[0]!),
    };
    var i = k % 3;
    for (var t = 0; t < 2 && gorunen.contains(r[i]); t++) {
      i = (i + 1) % 3;
    }
    final u = r[i], h = _bayt(u);
    final d1 = u >> 4, d0 = u & 15;
    return sayisal(
      '$yer ${_renkKodu(r)} kodlu renk kullanılmıştır. $_renkKurali Bu rengin '
          '${_bilesenAdlari[i]} bileşeninin onluk değeri kaçtır? $_harfNotu',
      u,
      [
        r[(i + 1) % 3],
        d0 * 16 + d1,
        d1 * 10 + d0,
        // 255 üstü değer kökteki 0–255 aralığıyla elenir; kullanılmaz.
        if ((d1 >= 10 || d0 >= 10) && _harfKaymasi(u) <= 255) _harfKaymasi(u),
        r[(i + 2) % 3],
        // Yedek adaylar 0–255 aralığında kalır (komşu değerle tamamlama 255
        // üstüne çıkabilir): bir basamak kayması ya da birim kayması.
        for (final s in const [-16, 16, -1, 1])
          if (u + s >= 0 && u + s <= 255) u + s,
      ],
      '${_renkKodu(r)} kodunda ${_bilesenAdlari[i]} bileşen $h rakamlarıyla '
          'gösterilir: ${_tabanli(h, 16)} = ${_baytCoz(u)}.',
      positive: true,
    );
  }
  if (c < 7) {
    final r = _renkHavuzu[2000 + j + 500 * (c - 4)];
    final dogru = _renkKodu(r);
    // Harf kayması bir bileşeni 255 üstüne taşırsa kod altı onaltılık rakamı
    // aşar (ör. #10710DDE) ve seçenek bakar bakmaz elenir; kullanılmaz.
    final harfli =
        r.any((u) => _harfKaymasi(u) != u) &&
        r.every((u) => _harfKaymasi(u) <= 255);
    return secenekli(
      '$yer kırmızı bileşeni ${r[0]}, yeşil bileşeni ${r[1]}, mavi bileşeni '
          '${r[2]} olan bir renk seçilmiştir. $_renkKurali Bu rengin onaltılık '
          'renk kodu nedir? $_harfNotu',
      dogru,
      [
        _renkKodu([r[2], r[1], r[0]]),
        '#${r.map((u) => _ters(_bayt(u))).join()}',
        if (harfli) _renkKodu([for (final u in r) _harfKaymasi(u)]),
        _renkKodu([r[1], r[0], r[2]]),
        _renkKodu([r[0], r[2], r[1]]),
      ],
      '${[for (var t = 0; t < 3; t++) '${r[t]} = ${r[t] >> 4}·16 + ${r[t] & 15} → ${_bayt(r[t])}'].join(', ')} '
          'olduğundan kod $dogru olur.',
    );
  }
  final k = j + 500 * (c - 7);
  final r = _renkHavuzu[3500 + k];
  final i = k % 3, delta = 10 + (k ~/ 3) % 45;
  final u = r[i];
  final artir = u + delta <= 255;
  final yeni = artir ? u + delta : u - delta;
  List<int> degistir(int yer, int deger) => [
    for (var t = 0; t < 3; t++) t == yer ? deger : r[t],
  ];
  bool gecerli(int x) => x >= 0 && x <= 255;
  final delta16 = int.parse('$delta', radix: 16);
  final hexHata = artir ? u + delta16 : u - delta16;
  final komsu = (i + 1) % 3, komsuYeni = r[komsu] + (artir ? delta : -delta);
  final komsu2 = (i + 2) % 3;
  final komsu2Yeni = r[komsu2] + (artir ? delta : -delta);
  final yonHata = artir ? u - delta : u + delta;
  final dogru = _renkKodu(degistir(i, yeni));
  return secenekli(
    '$yer ${_renkKodu(r)} kodlu rengin ${_bilesenAdlari[i]} bileşeninin değeri '
        '$delta ${artir ? 'artırılıyor' : 'azaltılıyor'}, diğer bileşenler '
        'değişmiyor. $_renkKurali Yeni rengin onaltılık kodu nedir? '
        '$_harfNotu',
    dogru,
    [
      if (gecerli(hexHata)) _renkKodu(degistir(i, hexHata)),
      if (gecerli(komsuYeni)) _renkKodu(degistir(komsu, komsuYeni)),
      if (gecerli(yonHata)) _renkKodu(degistir(i, yonHata)),
      '#${[for (var t = 0; t < 3; t++) t == i ? _ters(_bayt(yeni)) : _bayt(r[t])].join()}',
      if (gecerli(komsu2Yeni)) _renkKodu(degistir(komsu2, komsu2Yeni)),
      for (final s in const [16, -16, 32, -32])
        if (gecerli(yeni + s)) _renkKodu(degistir(i, yeni + s)),
    ],
    '${_bilesenAdlari[i][0].toUpperCase()}${_bilesenAdlari[i].substring(1)} '
        'bileşen ${_tabanli(_bayt(u), 16)} = $u olur; $u ${artir ? '+' : '−'} '
        '$delta = $yeni ve $yeni = ${yeni >> 4}·16 + ${yeni & 15} → '
        '${_bayt(yeni)}. Yeni kod $dogru olur.',
  );
}

// ---------------------------------------------------------------------------
// 7. Mantık kapıları: verilen girişler için devrenin çıkışı
// ---------------------------------------------------------------------------

const _kapilar = ['VE', 'VEYA', 'ÖZEL VEYA', 'VE DEĞİL', 'VEYA DEĞİL'];

int _kapi(int g, int x, int y) => switch (g) {
  0 => x & y,
  1 => x | y,
  2 => x ^ y,
  3 => 1 - (x & y),
  _ => 1 - (x | y),
};

/// Tipik okuma hatası: VE ↔ VEYA, ÖZEL VEYA → VEYA, VE DEĞİL → VE,
/// VEYA DEĞİL → VEYA (değil unutulur).
const _yanlisKapi = [1, 0, 1, 0, 1];

const _girisAdi = ['A', 'B', 'C'];

/// P ve Q kapılarına bağlanan giriş çiftleri.
const _baglantilar = [((0, 1), (1, 2)), ((0, 1), (0, 2)), ((0, 2), (1, 2))];

/// Devre: (bağlantı, DEĞİL kapısının yeri, P, Q ve X kapıları). DEĞİL yeri:
/// 0 yok; 1, 2 P kapısının birinci ya da ikinci girişi; 3, 4 Q kapısının
/// birinci ya da ikinci girişi; 5 X çıkışı.
typedef _Devre = (int, int, int, int, int);

/// [hata]: 0 doğru okuma; 1, 2, 3 sırasıyla P, Q ya da X kapısının yanlış
/// okunması; 4 DEĞİL kapısının unutulması.
(int, int, int) _devreDeger(_Devre e, List<int> v, [int hata = 0]) {
  final (w, d, g1, g2, g3) = e;
  final ((p1, p2), (q1, q2)) = _baglantilar[w];
  final degil = hata != 4;
  int giris(int x, int konum) => degil && d == konum ? 1 - v[x] : v[x];
  final p = _kapi(hata == 1 ? _yanlisKapi[g1] : g1, giris(p1, 1), giris(p2, 2));
  final q = _kapi(hata == 2 ? _yanlisKapi[g2] : g2, giris(q1, 3), giris(q2, 4));
  final x = _kapi(hata == 3 ? _yanlisKapi[g3] : g3, p, q);
  return (p, q, degil && d == 5 ? 1 - x : x);
}

/// Sabit çıkış vermeyen devreler.
final _devreler = [
  for (var w = 0; w < 3; w++)
    for (var d = 0; d < 6; d++)
      for (var g1 = 0; g1 < 5; g1++)
        for (var g2 = 0; g2 < 5; g2++)
          for (var g3 = 0; g3 < 5; g3++)
            if (_birSayisi((w, d, g1, g2, g3)) % 8 != 0) (w, d, g1, g2, g3),
];

List<int> _giris(int s) => [s >> 2 & 1, s >> 1 & 1, s & 1];

/// Değer sorusu için (devre sırası, giriş): her tipik okuma hatası (P, Q ya
/// da X kapısını yanlış okumak, DEĞİL kapısını unutmak) P, Q, X üçlüsünü
/// değiştirir; yanlış yöntem anahtarı vermez.
final _kapiDegerHavuzu = [
  for (var t = 0; t < _devreler.length; t++)
    for (var s = 0; s < 8; s++)
      if (_hatalarDegistirir(_devreler[t], _giris(s))) (t, s),
];

bool _hatalarDegistirir(_Devre e, List<int> v) {
  final dogru = _devreDeger(e, v);
  for (var h = 1; h <= (e.$2 == 0 ? 3 : 4); h++) {
    if (_devreDeger(e, v, h) == dogru) return false;
  }
  return true;
}

/// Giriş bulma sorusu: (devre sırası, hedef çıkış, doğru giriş, üç yanlış
/// giriş). Her tipik okuma hatasında ya doğru giriş hedefi vermez ya da bir
/// yanlış seçenek de hedefi verir: hata yapan öğrenci anahtara ulaşamaz.
final _kapiGirisHavuzu = () {
  final r = <(int, int, int, List<int>)>[];
  for (var t = 0; t < _devreler.length; t++) {
    for (final hedef in const [1, 0]) {
      final x = _girisSecimi(_devreler[t], hedef);
      if (x != null) r.add((t, hedef, x.$1, x.$2));
    }
  }
  return r;
}();

(int, List<int>)? _girisSecimi(_Devre e, int hedef) {
  final deger = [for (var s = 0; s < 8; s++) _devreDeger(e, _giris(s)).$3];
  final uyan = [
    for (var s = 0; s < 8; s++)
      if (deger[s] == hedef) s,
  ];
  final uymayan = [
    for (var s = 0; s < 8; s++)
      if (deger[s] != hedef) s,
  ];
  if (uyan.isEmpty || uymayan.length < 3) return null;
  final hatalar = e.$2 == 0 ? 3 : 4;
  int x(int s, int h) => _devreDeger(e, _giris(s), h).$3;
  for (final k in uyan) {
    for (var i = 0; i < uymayan.length; i++) {
      for (var i2 = i + 1; i2 < uymayan.length; i2++) {
        for (var i3 = i2 + 1; i3 < uymayan.length; i3++) {
          final ds = [uymayan[i], uymayan[i2], uymayan[i3]];
          var iyi = true;
          for (var h = 1; h <= hatalar && iyi; h++) {
            if (x(k, h) == hedef && ds.every((d) => x(d, h) != hedef)) {
              iyi = false;
            }
          }
          if (iyi) return (k, ds);
        }
      }
    }
  }
  return null;
}

int _birSayisi(_Devre e) =>
    _topla([for (var s = 0; s < 8; s++) _devreDeger(e, _giris(s)).$3]);

String _devreYaz(_Devre e) {
  final (w, d, g1, g2, g3) = e;
  final ((p1, p2), (q1, q2)) = _baglantilar[w];
  String kapi(int x1, int x2, int g, int ters) => switch (ters) {
    1 =>
      '${_girisAdi[x1]} girişi bir DEĞİL kapısından geçirildikten sonra '
          '${_girisAdi[x2]} girişiyle birlikte bir ${_kapilar[g]} kapısına',
    2 =>
      '${_girisAdi[x2]} girişi bir DEĞİL kapısından geçirildikten sonra '
          '${_girisAdi[x1]} girişiyle birlikte bir ${_kapilar[g]} kapısına',
    _ =>
      '${_girisAdi[x1]} ve ${_girisAdi[x2]} girişleri bir ${_kapilar[g]} '
          'kapısına',
  };
  final xYaz = d == 5
      ? 'bu kapının çıkışı da bir DEĞİL kapısından geçirilerek X çıkışı elde '
            'edilmiştir.'
      : 'bu kapının çıkışı X olarak adlandırılmıştır.';
  return 'Bir mantık devresinde ${kapi(p1, p2, g1, d == 1 || d == 2 ? d : 0)} '
      'bağlanmış, bu kapının çıkışı P olarak adlandırılmıştır. '
      '${kapi(q1, q2, g2, d == 3 || d == 4 ? d - 2 : 0)} bağlanmış, bu kapının '
      'çıkışı Q olarak adlandırılmıştır. P ve Q bir ${_kapilar[g3]} kapısına '
      'bağlanmış, $xYaz (1 doğru, 0 yanlış değerini gösterir.)';
}

/// Girişteki DEĞİL kapısının etkisini açıklar.
String _degilNotu(_Devre e, List<int> v) {
  final (w, d, _, _, _) = e;
  if (d == 0 || d == 5) return '';
  final ((p1, p2), (q1, q2)) = _baglantilar[w];
  final x = [p1, p2, q1, q2][d - 1];
  return 'DEĞİL kapısından sonra ${_girisAdi[x]} girişinin değeri '
      '${1 - v[x]} olur; ';
}

String _uclu((int, int, int) t) => 'P = ${t.$1}, Q = ${t.$2}, X = ${t.$3}';
String _girisYaz(List<int> v) => '(${v.join(', ')})';

/// [k] numaralı elemanı [n] elemanlı bir uzayın dolaşımından seçer.
int _sira(int k, int n, int adim) {
  var s = adim % n;
  while (s.gcd(n) != 1) {
    s++;
  }
  return (k * s + 11) % n;
}

AdvancedItem _mantikKapisi(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 6) {
    final (t, s) =
        _kapiDegerHavuzu[_sira(j + 500 * c, _kapiDegerHavuzu.length, 7919)];
    final e = _devreler[t];
    final v = _giris(s);
    final dogru = _devreDeger(e, v);
    final (p, q, x) = dogru;
    return secenekli(
      '${_devreYaz(e)} A = ${v[0]}, B = ${v[1]} ve C = ${v[2]} iken P, Q ve X '
          'çıkışlarının değerleri sırasıyla hangisidir?',
      _uclu(dogru),
      [
        for (var h = 1; h <= 4; h++) _uclu(_devreDeger(e, v, h)),
        _uclu((p, q, 1 - x)),
        _uclu((1 - p, q, x)),
        _uclu((p, 1 - q, x)),
      ],
      'Girişler A = ${v[0]}, B = ${v[1]}, C = ${v[2]} iken '
          '${_degilNotu(e, v)}${_kapilar[e.$3]} '
          'kapısının çıkışı P = $p, ${_kapilar[e.$4]} kapısının çıkışı Q = $q '
          'olur. ${_kapilar[e.$5]} kapısına P = $p ve Q = $q girdiğinde'
          '${e.$2 == 5 ? ' çıkış ${1 - x} olur; DEĞİL kapısından sonra' : ''} '
          'X = $x bulunur.',
    );
  }
  final (t, hedef, secilen, sirali) =
      _kapiGirisHavuzu[_sira(j + 500 * (c - 6), _kapiGirisHavuzu.length, 1009)];
  final e = _devreler[t];
  final secenekler = [secilen, ...sirali];
  // Çoğu devrede hedef çıkışı veren birden çok giriş vardır (seçeneklerde
  // yalnız biri bulunur); soru bu yüzden “hangisi olabilir” biçimindedir.
  return secenekli(
    '${_devreYaz(e)} Girişler (A, B, C) biçiminde yazıldığına göre X çıkışının '
        '$hedef olması için giriş değerleri hangisi olabilir?',
    _girisYaz(_giris(secilen)),
    [for (final s in sirali) _girisYaz(_giris(s))],
    '${secenekler.map((s) => '${_girisYaz(_giris(s))} için X = ${_devreDeger(e, _giris(s)).$3}').join('; ')}. '
        'Yalnız ${_girisYaz(_giris(secilen))} girişi X = $hedef verir.',
  );
}

// ---------------------------------------------------------------------------
// 8. Boole ifadesi ve doğruluk tablosu
// ---------------------------------------------------------------------------

const _islecler = ['VE', 'VEYA', 'ÖZEL VEYA'];

/// Boole ifadesi: değişken (harf ≥ 0) ya da iki işlenenli işlem; [degil]
/// değişkenin ya da işlem grubunun değilinin alındığını gösterir.
class _Ifade {
  const _Ifade.harf(this.harf, this.degil) : islec = -1, sol = null, sag = null;
  const _Ifade.islem(this.islec, this.sol, this.sag, this.degil) : harf = -1;
  final int harf, islec;
  final _Ifade? sol, sag;
  final bool degil;

  bool get xorlu =>
      islec == 2 || (sol?.xorlu ?? false) || (sag?.xorlu ?? false);
  bool get grupDegilli =>
      islec >= 0 &&
      (degil || (sol?.grupDegilli ?? false) || (sag?.grupDegilli ?? false));
}

/// [xorVeya]: ÖZEL VEYA, VEYA gibi okunur; [grupsuz]: grupların DEĞİL'i
/// unutulur; [kokTers]: en dıştaki VE ile VEYA karıştırılır.
int _ifadeDeger(
  _Ifade e,
  List<int> v, {
  bool xorVeya = false,
  bool grupsuz = false,
  bool kokTers = false,
}) {
  if (e.islec < 0) return e.degil ? 1 - v[e.harf] : v[e.harf];
  final x = _ifadeDeger(e.sol!, v, xorVeya: xorVeya, grupsuz: grupsuz);
  final y = _ifadeDeger(e.sag!, v, xorVeya: xorVeya, grupsuz: grupsuz);
  var o = xorVeya && e.islec == 2 ? 1 : e.islec;
  if (kokTers && o < 2) o = 1 - o;
  final r = [x & y, x | y, x ^ y][o];
  return e.degil && !grupsuz ? 1 - r : r;
}

String _ifadeYaz(_Ifade e, {bool kok = false, List<int>? v}) {
  if (e.islec < 0) {
    final ad = v == null ? 'ABCD'[e.harf] : '${v[e.harf]}';
    return e.degil ? '(DEĞİL $ad)' : ad;
  }
  final ic =
      '${_ifadeYaz(e.sol!, v: v)} ${_islecler[e.islec]} '
      '${_ifadeYaz(e.sag!, v: v)}';
  // Değili alınan alt grup ayraç içinde yazılır: “VE (DEĞİL (…))” yazımı
  // VE DEĞİL kapı adıyla karışmaz.
  if (e.degil) return kok ? 'DEĞİL ($ic)' : '(DEĞİL ($ic))';
  return kok ? ic : '($ic)';
}

_Ifade _h(int harf, int degil) => _Ifade.harf(harf, degil == 1);

/// Bütün ifadeler: (değişken sayısı, ifade).
final _ifadeler = <(int, _Ifade)>[
  // (L1 ∘ L2) ∘ L3, grup değilli ya da değilsiz; ayrıca tümünün değili.
  for (var yalniz = 0; yalniz < 3; yalniz++)
    for (var n = 0; n < 8; n++)
      for (var o1 = 0; o1 < 3; o1++)
        for (var o2 = 0; o2 < 3; o2++)
          for (var g = 0; g < 3; g++)
            (
              3,
              _Ifade.islem(
                o2,
                _Ifade.islem(
                  o1,
                  _h(yalniz == 0 ? 1 : 0, n >> 2 & 1),
                  _h(yalniz == 2 ? 1 : 2, n >> 1 & 1),
                  g == 1,
                ),
                _h(yalniz, n & 1),
                g == 2,
              ),
            ),
  // (X ∘ Y) ∘ (Y ∘ Z): ortak değişkenli, en çok bir değilli harf.
  for (var ortak = 0; ortak < 3; ortak++)
    for (var dk = 0; dk < 5; dk++)
      for (var o1 = 0; o1 < 3; o1++)
        for (var o2 = 0; o2 < 3; o2++)
          for (var o3 = 0; o3 < 3; o3++)
            (
              3,
              _Ifade.islem(
                o2,
                _Ifade.islem(
                  o1,
                  _h(ortak == 0 ? 1 : 0, dk == 1 ? 1 : 0),
                  _h(ortak, dk == 2 ? 1 : 0),
                  false,
                ),
                _Ifade.islem(
                  o3,
                  _h(ortak, dk == 3 ? 1 : 0),
                  _h(ortak == 2 ? 1 : 2, dk == 4 ? 1 : 0),
                  false,
                ),
                false,
              ),
            ),
  // Dört değişken: (A ∘ B) ∘ (C ∘ D) ve ((A ∘ B) ∘ C) ∘ D.
  for (var n = 0; n < 16; n++)
    for (var o1 = 0; o1 < 3; o1++)
      for (var o2 = 0; o2 < 3; o2++)
        for (var o3 = 0; o3 < 3; o3++) ...[
          for (var g = 0; g < 3; g++)
            (
              4,
              _Ifade.islem(
                o2,
                _Ifade.islem(o1, _h(0, n >> 3 & 1), _h(1, n >> 2 & 1), g == 1),
                _Ifade.islem(o3, _h(2, n >> 1 & 1), _h(3, n & 1), g == 2),
                false,
              ),
            ),
          (
            4,
            _Ifade.islem(
              o3,
              _Ifade.islem(
                o2,
                _Ifade.islem(o1, _h(0, n >> 3 & 1), _h(1, n >> 2 & 1), false),
                _h(2, n >> 1 & 1),
                false,
              ),
              _h(3, n & 1),
              false,
            ),
          ),
        ],
];

List<int> _satir(int s, int nv) => [
  for (var t = nv - 1; t >= 0; t--) s >> t & 1,
];

int _ifadeSay(
  (int, _Ifade) f, {
  bool xorVeya = false,
  bool grupsuz = false,
  bool kokTers = false,
}) => _topla([
  for (var s = 0; s < 1 << f.$1; s++)
    _ifadeDeger(
      f.$2,
      _satir(s, f.$1),
      xorVeya: xorVeya,
      grupsuz: grupsuz,
      kokTers: kokTers,
    ),
]);

/// Satır sayma sorusuna uygun ifadeler: 1 olan satır sayısı 0, 1, yarı ya da
/// tüm satırlar değildir; tipik okuma hataları farklı sayı verir.
final _sayimIfadeleri = [
  for (final f in _ifadeler)
    if (_sayimUygun(f)) f,
];

bool _sayimUygun((int, _Ifade) f) {
  final k = _ifadeSay(f), t = 1 << f.$1;
  if (k <= 1 || k == t ~/ 2 || k == t) return false;
  if (f.$2.xorlu && _ifadeSay(f, xorVeya: true) == k) return false;
  if (f.$2.grupDegilli && _ifadeSay(f, grupsuz: true) == k) return false;
  if (f.$2.islec < 2 && _ifadeSay(f, kokTers: true) == k) return false;
  return true;
}

String _degiskenler(int nv) => nv == 3 ? 'A, B ve C' : 'A, B, C ve D';

/// Değer sorusunun iki satırı (satır numaraları).
(int, int) _satirCifti(int nv, int p) {
  if (nv == 3) {
    final s1 = p ~/ 7;
    return (s1, (s1 + 1 + p % 7) % 8);
  }
  final s1 = p % 16;
  return (s1, (s1 + 1 + p ~/ 16) % 16);
}

/// Değer sorusu için (ifade sırası, satır çifti): uygulanabilen her tipik
/// okuma hatası (ÖZEL VEYA yerine VEYA, grup değilini unutma, en dıştaki VE
/// ile VEYA karışması) iki değerden en az birini değiştirir.
final _degerHavuzu = () {
  final r = <(int, int)>[];
  for (var t = 0; t < _ifadeler.length; t++) {
    final (nv, e) = _ifadeler[t];
    for (var p = 0; p < 56; p++) {
      final (s1, s2) = _satirCifti(nv, p);
      final v1 = _satir(s1, nv), v2 = _satir(s2, nv);
      final f1 = _ifadeDeger(e, v1), f2 = _ifadeDeger(e, v2);
      bool degisir({bool x = false, bool g = false, bool k = false}) =>
          _ifadeDeger(e, v1, xorVeya: x, grupsuz: g, kokTers: k) != f1 ||
          _ifadeDeger(e, v2, xorVeya: x, grupsuz: g, kokTers: k) != f2;
      if (e.xorlu && !degisir(x: true)) continue;
      if (e.grupDegilli && !degisir(g: true)) continue;
      if (e.islec < 2 && !degisir(k: true)) continue;
      r.add((t, p));
    }
  }
  return r;
}();

String _satirYaz(List<int> v, int nv) =>
    [for (var t = 0; t < nv; t++) '${'ABCD'[t]} = ${v[t]}'].join(', ');

AdvancedItem _dogrulukTablosu(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 3) {
    final f = _dolas(_sayimIfadeleri, j + 500 * c, 389);
    final (nv, e) = f;
    final t = 1 << nv, k = _ifadeSay(f);
    final birMi = k <= t ~/ 2;
    final liste = [
      for (var s = 0; s < t; s++)
        if ((_ifadeDeger(e, _satir(s, nv)) == 1) == birMi)
          '(${_satir(s, nv).join(', ')})',
    ];
    return sayisal(
      '${_degiskenler(nv)} mantık değişkenleri için F = ${_ifadeYaz(e, kok: true)} '
          'ifadesi veriliyor (1 doğru, 0 yanlış değerini gösterir). '
          'Değişkenlerin bütün değer birleşimlerini içeren doğruluk tablosunun '
          'kaç satırında F = 1 olur?',
      k,
      [
        t - k,
        if (e.xorlu) _ifadeSay(f, xorVeya: true),
        if (e.grupDegilli) _ifadeSay(f, grupsuz: true),
        if (e.islec < 2) _ifadeSay(f, kokTers: true),
      ],
      'Tablo $t satırdır. F = ${birMi ? 1 : 0} olan satırlar '
          '(${'ABCD'.substring(0, nv).split('').join(', ')}): '
          '${liste.join(', ')}. ${birMi ? 'Bu satırların sayısı $k olur.' : 'Bu ${t - k} satır dışındaki $t − ${t - k} = $k satırda F = 1 olur.'}',
      positive: true,
    );
  }
  final (t, p) =
      _degerHavuzu[_sira(j + 500 * (c - 3), _degerHavuzu.length, 104729)];
  final (nv, e) = _ifadeler[t];
  final (s1, s2) = _satirCifti(nv, p);
  final v1 = _satir(s1, nv), v2 = _satir(s2, nv);
  final f1 = _ifadeDeger(e, v1), f2 = _ifadeDeger(e, v2);
  String cift(int x, int y) => '$x ve $y';
  return secenekli(
    '${_degiskenler(nv)} mantık değişkenleri için F = ${_ifadeYaz(e, kok: true)} '
        'ifadesi veriliyor (1 doğru, 0 yanlış değerini gösterir). '
        '${_satirYaz(v1, nv)} için ve ${_satirYaz(v2, nv)} için F '
        'ifadesinin değerleri sırasıyla hangisidir?',
    cift(f1, f2),
    [cift(1 - f1, f2), cift(f1, 1 - f2), cift(1 - f1, 1 - f2)],
    'Birinci girişte F = ${_ifadeYaz(e, kok: true, v: v1)} = $f1, ikinci '
        'girişte F = ${_ifadeYaz(e, kok: true, v: v2)} = $f2 bulunur.',
  );
}

// ---------------------------------------------------------------------------
// 9. Döngü izleme
// ---------------------------------------------------------------------------

const _kodGiris =
    'Aşağıdaki sözde kodda ← atama işlemidir; döngünün gövdesi “döngü sonu” '
    'satırına kadar olan satırlardır.';

const _modNotu = ' a mod b, a sayısının b ile bölümünden kalanı verir.';

const _divNotu =
    ' a div b, a sayısının b ile bölümündeki tam sayı bölümü verir.';

String _kod(String giris, List<String> satirlar, String soru) =>
    '$giris\n${satirlar.join('\n')}\n$soru';

const _yazSorusu = 'Bu kod çalıştırıldığında yazdırılan değer kaçtır?';

/// s ← m · s ± k · i biçimleri: (m, k, işaret); değerler pozitif kalır.
const _guncellemeler = [(2, 1, -1), (2, 1, 1), (2, 2, 1), (2, 3, 1), (2, 4, 1)];

/// Tek sayıda uygulanan güncelleme (çift sayıda s ← s div 2).
/// Tek/çift güncelleme sorusu için (başlangıç, adım sayısı, tek kalıbı): son
/// değer kökteki sayılardan farklıdır; bir eksik ya da fazla adım ve dalların
/// karıştırılması anahtarı vermez. Koşulun iki dalı da en az ikişer kez
/// çalışır (hiç çalışmayan dal koşulu anlamsız kılardı).
final _tekCiftHavuzu = [
  for (var p = 12; p <= 90; p++)
    for (var n = 4; n <= 8; n++)
      for (var v = 0; v < 4; v++)
        if (_tekCiftUygun(p, n, v)) (p, n, v),
];

List<int> _tekCiftIz(int p, int v, int adim, {bool ters = false}) {
  final r = [p];
  for (var i = 1; i <= adim; i++) {
    final s = r.last;
    r.add((s.isEven != ters) ? s ~/ 2 : _tekUygula(v, s, i));
  }
  return r;
}

bool _tekCiftUygun(int p, int n, int v) {
  final iz = _tekCiftIz(p, v, n);
  final ciftAdim = iz.take(n).where((s) => s.isEven).length;
  if (ciftAdim < 2 || n - ciftAdim < 2) return false;
  final son = iz.last;
  final basili = {p, n, 0, 1, 2, if (v == 1 || v == 2) 3};
  if (basili.contains(son)) return false;
  final hatalar = [
    _tekCiftIz(p, v, n - 1).last,
    _tekCiftIz(p, v, n + 1).last,
    _tekCiftIz(p, v, n, ters: true).last,
  ];
  return !hatalar.contains(son);
}

/// Tek s değerine uygulanan kalıplar; her biri en az bazı adımlarda çift
/// sonuç verir (s ← s + 2 · i gibi tek sayı koruyan kalıp çift dalı
/// çalıştırmazdı).
const _tekGuncelleme = [
  's ← s + i',
  's ← s + 3',
  's ← 3 · s + 1',
  's ← s + 2 · i + 1',
];

int _tekUygula(int v, int s, int i) => switch (v) {
  0 => s + i,
  1 => s + 3,
  2 => 3 * s + 1,
  _ => s + 2 * i + 1,
};

/// "veya" sorusunun çiftleri: ortak katların en küçüğü en çok 10 olduğundan
/// 10 ile 34 arasındaki her üst sınırda ortak kat vardır (çift sayma hatası
/// anahtarı vermez).
const _veyaCiftleri = [
  (2, 3),
  (2, 4),
  (2, 5),
  (2, 6),
  (2, 8),
  (2, 10),
  (3, 6),
  (3, 9),
  (4, 8),
  (5, 10),
];

/// Kat sayma soruları: (fark sorusu mu, çift sırası, üst sınır). Yanıt kökteki
/// sayılardan farklıdır; tipik hatalar (çift sayma, yalnız ortak katlar,
/// tümleyen, ikinci koşulu yok sayma) anahtarı vermez.
final _katHavuzu = [
  for (final fark in const [false, true])
    for (var ci = 0; ci < 10; ci++)
      for (var n = 10; n <= 50; n++)
        if (_katUygun(fark, ci, n)) (fark, ci, n),
];

bool _katUygun(bool fark, int ci, int n) {
  final (u, w) = fark ? _farkCiftleri[ci] : _veyaCiftleri[ci];
  final ok = u * w ~/ u.gcd(w);
  final ikisi = n ~/ ok, birlesim = n ~/ u + n ~/ w - ikisi;
  final d = fark ? n ~/ u - ikisi : birlesim;
  if ([u, w, n, 0, 1].contains(d)) return false;
  return fark
      ? n ~/ w != d && n ~/ u != d
      : ikisi != d && n - birlesim != d && n ~/ u + n ~/ w != d;
}

/// "u katı olup w katı olmayan" sorusunun çiftleri (ortak kat ≤ 10).
const _farkCiftleri = [
  (2, 3),
  (3, 2),
  (2, 5),
  (5, 2),
  (2, 4),
  (2, 6),
  (3, 6),
  (2, 8),
  (3, 9),
  (5, 10),
];

AdvancedItem _dongu(int a, int b, int c) {
  final j = a + 25 * b;
  switch (c) {
    case 0:
      final p = 3 + 2 * a, n = 4 + b % 9, k = 2 + b ~/ 9;
      final g = n * (n + 1) ~/ 2, t = p + k * g;
      return sayisalSirali(
        _kod(_kodGiris, [
          't ← $p',
          'i = 1, 2, …, $n için',
          't ← t + $k · i',
          'döngü sonu',
          'yaz t',
        ], _yazSorusu),
        t,
        [
          p + k * (n - 1) * n ~/ 2,
          p + k * (n + 1) * (n + 2) ~/ 2,
          k * g,
          p + k * n,
          p + g,
          p + k * n * (n + 1),
        ],
        'Döngü $n kez çalışır ve t değerine $k · (1 + 2 + … + $n) = $k · $g = '
        '${k * g} eklenir. Yazdırılan değer $p + ${k * g} = $t olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 1:
      final p = 1 + a, q = 2 + b % 5, d = 1 + b ~/ 5, n = 4 + (a + b) % 7;
      int son(int adim, {bool ters = false}) {
        var x = p, y = q;
        for (var t = 0; t < adim; t++) {
          if (ters) {
            y += d;
            x += y;
          } else {
            x += y;
            y += d;
          }
        }
        return x;
      }
      final x = son(n);
      return sayisalSirali(
        _kod(_kodGiris, [
          'x ← $p',
          'y ← $q',
          'i = 1, 2, …, $n için',
          'x ← x + y',
          'y ← y + $d',
          'döngü sonu',
          'yaz x',
        ], _yazSorusu),
        x,
        // Ek hatalar: y değerinin arttığını unutma, x başlangıcını eklememe.
        [
          son(n, ters: true),
          son(n - 1),
          q + n * d,
          son(n + 1),
          p + n * q,
          x - p,
        ],
        'Her adımda x değerine o anki y eklenir, sonra y değeri $d artar. '
        'Eklenen y değerleri ${[for (var t = 0; t < n; t++) q + t * d].join(', ')} '
        'olduğundan x = $p + ${_topla([for (var t = 0; t < n; t++) q + t * d])} '
        '= $x olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 2:
      final (m, k, isaret) = _guncellemeler[b ~/ 4];
      // s ← 2 · s − i kalıbında s = 2 başlangıcı her adımda s = i + 2 verir
      // (dizi bozulur); bu kalıpta başlangıç 3 ile 27 arasındadır.
      final n = 4 + b % 4, p = 2 + a + (b ~/ 4 == 0 ? 1 : 0);
      // hata: işlem önceliği (m · (s ± k · i)); sabit: k · i yerine k;
      // sifir: i değerini 0 ile başlatma.
      List<int> iz(
        int adim, {
        bool hata = false,
        bool sabit = false,
        bool sifir = false,
      }) {
        final r = [p];
        for (var i = 1; i <= adim; i++) {
          final s = r.last, e = sabit ? k : k * (sifir ? i - 1 : i);
          r.add(hata ? m * (s + isaret * e) : m * s + isaret * e);
        }
        return r;
      }
      final dogru = iz(n);
      final ek = '${isaret > 0 ? '+' : '−'} ${k == 1 ? 'i' : '$k · i'}';
      return sayisalSirali(
        _kod(_kodGiris, [
          's ← $p',
          'i = 1, 2, …, $n için',
          's ← $m · s $ek',
          'döngü sonu',
          'yaz s',
        ], _yazSorusu),
        dogru.last,
        [
          iz(n - 1).last,
          iz(n + 1).last,
          iz(n, hata: true).last,
          iz(n, sabit: true).last,
          p * _kuvvet(m, n),
          iz(n, sifir: true).last,
        ],
        'Her adımda önce $m · s hesaplanır, sonra ${k == 1 ? 'i' : '$k · i'} '
        '${isaret > 0 ? 'eklenir' : 'çıkarılır'}. s değeri sırasıyla '
        '${dogru.join(' → ')} olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 3:
      final p = 1 + a, q = 1 + b, n = 4 + (a + 2 * b) % 6;
      List<int> iz(int adim) {
        var x = p, y = q;
        final r = [y];
        for (var t = 0; t < adim; t++) {
          final z = x + y;
          x = y;
          y = z;
          r.add(y);
        }
        return r;
      }
      final dogru = iz(n);
      return sayisalSirali(
        _kod(_kodGiris, [
          'x ← $p',
          'y ← $q',
          'i = 1, 2, …, $n için',
          'z ← x + y',
          'x ← y',
          'y ← z',
          'döngü sonu',
          'yaz y',
        ], _yazSorusu),
        dogru.last,
        // Ek hatalar: x ← y satırını atlama (x hep p kalır), x ← y satırını
        // z hesaplanmadan önce çalıştırma.
        [
          iz(n - 1).last,
          iz(n + 1).last,
          (p + q) * (1 << (n - 1)),
          q + n * p,
          q * (1 << n),
        ],
        'Her adımda yeni y, önceki x ile y değerlerinin toplamıdır. y değeri '
        'sırasıyla ${dogru.join(', ')} olur; yazdırılan değer '
        '${dogru.last} bulunur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 4:
      final s = 1 + a, d = 2 + b % 5;
      // Çalışma sayısı döngü satırında yazılı bir değere (s, s + d, s + 2d)
      // eşit olursa bir artırılır: tek sayılar (7, 9, 11, 13) başka vakada
      // kullanılmaz ve ardışık yazılı değerler d ≥ 2 aralıklı olduğundan yeni
      // değer de yazılı değildir.
      var m = 6 + 2 * (b ~/ 5);
      if ([s, s + d, s + 2 * d].contains(m)) m++;
      final e = s + d * (m - 1);
      // Ek hatalar: aralıktaki tam sayıları sayarken 1 eklememe, yazdırılan
      // toplamı çalışma sayısı sanma.
      return sayisalSirali(
        _kod(_kodGiris, [
          't ← 0',
          'i = $s, ${s + d}, ${s + 2 * d}, …, $e için',
          't ← t + i',
          'döngü sonu',
          'yaz t',
        ], 'Bu kod çalıştırıldığında döngünün gövdesi kaç kez çalışır?'),
        m,
        [m - 1, m + 1, e - s + 1, e - s, m * (s + e) ~/ 2],
        'i değeri $s sayısından başlayıp $d artarak $e sayısına ulaşır. Çalışma '
        'sayısı ($e − $s) / $d + 1 = ${m - 1} + 1 = $m olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 5:
      final d = 3 + b % 7, adet = 5 + (a + b) % 8, alt = 10 + a;
      // Yazdırılan değer kökteki sayılardan (alt, d, n, 0, 1) farklı olsun:
      // gerekirse yazdırılan değişken ve kalan r değiştirilir (n, a ve b ile
      // birlikte tek kalır).
      var sayac = (a + b).isEven;
      if ([alt, d, 0, 1].contains(adet)) sayac = false;
      var r = 1 + (a + 2 * b) % (d - 1);
      if (!sayac) {
        for (var t = 0; t < d - 1; t++) {
          final r2 = 1 + (r - 1 + t) % (d - 1);
          final son2 = alt + r2 - d, n2 = alt + (adet - 1) * d + r2;
          if (![alt, d, n2, 0, 1].contains(son2)) {
            r = r2;
            break;
          }
        }
      }
      final n = alt + (adet - 1) * d + r, son = alt + r - d;
      final satirlar = [
        'x ← $n',
        'say ← 0',
        'x > $alt olduğu sürece',
        'x ← x − $d',
        'say ← say + 1',
        'döngü sonu',
        sayac ? 'yaz say' : 'yaz x',
      ];
      const giris =
          'Aşağıdaki sözde kodda ← atama işlemidir; “olduğu sürece” '
          'döngüsünün gövdesi, koşul doğru olduğu sürece “döngü sonu” '
          'satırına kadar tekrar çalışır.';
      final aciklama =
          'x değeri her adımda $d azalır: $n, ${n - d}, … biçiminde ilerler. '
          '${alt + r} değerinden sonra x = $son olur ve $son > $alt koşulu '
          'sağlanmadığından döngü $adet adımda biter.';
      // Ek hatalar: alt sınırı unutup n / d alma, birim farkı sayma; x
      // için iki adım erken ya da geç durma, kalanı (n mod d) yazma.
      if (sayac) {
        return sayisalSirali(
          _kod(giris, satirlar, _yazSorusu),
          adet,
          [adet - 1, adet + 1, adet + 2, n ~/ d, n - alt],
          '$aciklama Yazdırılan say değeri $adet olur.',
          hedefSira(_no(a, b, c)),
          positive: true,
        );
      }
      return sayisalSirali(
        _kod(giris, satirlar, _yazSorusu),
        son,
        [alt, alt + r, son - d, alt + r + d, son - 2 * d, n % d],
        '$aciklama Yazdırılan x değeri $son olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 6:
      final p = 1 + a, n = 100 + 47 * b;
      var x = p, adet = 0;
      final iz = [p];
      while (x < n) {
        x *= 2;
        adet++;
        iz.add(x);
      }
      // say değeri kökteki bir sayıya eşitse x değeri sorulur.
      final sayYaz = ![p, n, 0, 1].contains(adet) || [p, n].contains(x);
      // Ek hatalar: x başlangıcını 1 alma (sayaç için), bir fazla ya da eksik
      // ikiye katlama (x için).
      return sayisalSirali(
        _kod(
          'Aşağıdaki sözde kodda ← atama işlemidir; “olduğu sürece” '
          'döngüsünün gövdesi, koşul doğru olduğu sürece “döngü sonu” '
          'satırına kadar tekrar çalışır.',
          [
            'x ← $p',
            'say ← 0',
            'x < $n olduğu sürece',
            'x ← x + x',
            'say ← say + 1',
            'döngü sonu',
            sayYaz ? 'yaz say' : 'yaz x',
          ],
          _yazSorusu,
        ),
        sayYaz ? adet : x,
        sayYaz
            ? [adet - 1, adet + 1, x, (n - 1).bitLength]
            : [x ~/ 2, 2 * x, adet, x ~/ 4, 4 * x],
        'x değeri sırasıyla ${iz.join(', ')} olur. $x < $n koşulu '
        'sağlanmadığından döngü durur; '
        '${sayYaz ? 'say değeri $adet olur.' : 'yazdırılan x değeri $x olur.'}',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 7:
      final p = 20 + a, n = 6 + b % 7, k = 2 + b ~/ 7;
      final katlar = [for (var i = k; i <= n; i += k) i];
      int hesap(int son, {bool degilseYok = false, bool artir = false}) {
        var t = p;
        for (var i = 1; i <= son; i++) {
          if (i % k == 0) {
            t += i;
          } else if (!degilseYok) {
            t += artir ? 1 : -1;
          }
        }
        return t;
      }
      final t = hesap(n);
      // Ek hatalar: katlarda da 1 çıkarma, her adımda yalnız 1 çıkarma, bir
      // fazla adım.
      return sayisalSirali(
        _kod('$_kodGiris$_modNotu', [
          't ← $p',
          'i = 1, 2, …, $n için',
          'eğer i mod $k = 0 ise t ← t + i değilse t ← t − 1',
          'döngü sonu',
          'yaz t',
        ], _yazSorusu),
        t,
        [
          hesap(n, degilseYok: true),
          hesap(n, artir: true),
          hesap(n - 1),
          t - katlar.length,
          p - n,
          hesap(n + 1),
        ],
        '1 ile $n arasında $k sayısının katları ${katlar.join(', ')} olup '
        'toplamları ${_topla(katlar)} olur. Diğer ${n - katlar.length} '
        'adımda t birer azalır: $p + ${_topla(katlar)} − '
        '${n - katlar.length} = $t.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 8:
      final (p, n, v) = _dolas(_tekCiftHavuzu, j, 211);
      List<int> iz(int adim, {bool ters = false}) =>
          _tekCiftIz(p, v, adim, ters: ters);
      final dogru = iz(n);
      return sayisal(
        _kod('$_kodGiris$_modNotu$_divNotu', [
          's ← $p',
          'i = 1, 2, …, $n için',
          'eğer s mod 2 = 0 ise s ← s div 2 değilse ${_tekGuncelleme[v]}',
          'döngü sonu',
          'yaz s',
        ], _yazSorusu),
        dogru.last,
        [iz(n - 1).last, iz(n + 1).last, iz(n, ters: true).last],
        's değeri sırasıyla ${dogru.join(' → ')} olur.',
        positive: true,
      );
    default:
      final (fark, ci, n) = _katHavuzu[_sira(j, _katHavuzu.length, 307)];
      final (u, w) = fark ? _farkCiftleri[ci] : _veyaCiftleri[ci];
      final ok = u * w ~/ u.gcd(w);
      final ikisi = n ~/ ok, birlesim = n ~/ u + n ~/ w - ikisi;
      final dogru = fark ? n ~/ u - ikisi : birlesim;
      // Ek hatalar: yalnız bir koşulun katlarını sayma, ortak katları sayma,
      // birleşimi sayma, bir eksik sayma.
      return sayisalSirali(
        _kod('$_kodGiris$_modNotu', [
          'say ← 0',
          'i = 1, 2, …, $n için',
          fark
              ? 'eğer i mod $u = 0 ve i mod $w ≠ 0 ise say ← say + 1'
              : 'eğer i mod $u = 0 veya i mod $w = 0 ise say ← say + 1',
          'döngü sonu',
          'yaz say',
        ], _yazSorusu),
        dogru,
        fark
            ? [
                n ~/ u,
                n ~/ u - n ~/ w,
                n ~/ w,
                dogru + 1,
                ikisi,
                birlesim,
                dogru - 1,
              ]
            : [
                n ~/ u + n ~/ w,
                ikisi,
                n - birlesim,
                birlesim + 1,
                n ~/ u,
                n ~/ w,
                birlesim - 1,
              ],
        fark
            ? '1 ile $n arasında $u sayısının ${n ~/ u} katı vardır. Bunlardan '
                  '$w sayısının da katı olanlar $ok sayısının katlarıdır ve '
                  '$ikisi tanedir. Sayı ${n ~/ u} − $ikisi = $dogru olur.'
            : '1 ile $n arasında $u sayısının ${n ~/ u}, $w sayısının ${n ~/ w} '
                  'katı vardır; ikisinin ortak katları ($ok sayısının katları) '
                  '$ikisi tanedir. Sayı ${n ~/ u} + ${n ~/ w} − $ikisi = '
                  '$birlesim olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 10. Koşullu yapı izleme: iç içe eğer-değilse
// ---------------------------------------------------------------------------

const _kosulGiris =
    'Aşağıdaki sözde kodda ← atama işlemidir; parantez içindeki “eğer … ise … '
    'değilse …” satırı tek bir koşullu yapıdır.';

const _atamaGiris = 'Aşağıdaki sözde kodda ← atama işlemidir.';

/// Kodda geçen mod ve div işlemlerinin açıklamasını girişe ekler.
String _notlu(String giris, List<String> satirlar) {
  final metin = satirlar.join(' ');
  return '$giris${metin.contains(' mod ') ? _modNotu : ''}'
      '${metin.contains(' div ') ? _divNotu : ''}';
}

/// İki girişli iç içe koşul kalıbı: dış koşul, iki iç koşul ve dört dalın
/// formülleri (yazımı ve hesabı).
class _Kosul {
  const _Kosul(this.dis, this.ic1, this.ic2, this.dallar);
  final (String, bool Function(int, int)) dis, ic1, ic2;
  final List<(String, int Function(int, int))> dallar;
}

final _kosulKaliplari = [
  _Kosul(
    ('x > y', (x, y) => x > y),
    ('x mod 2 = 0', (x, y) => x % 2 == 0),
    ('y mod 3 = 0', (x, y) => y % 3 == 0),
    [
      ('x − y', (x, y) => x - y),
      ('x + y', (x, y) => x + y),
      ('y div 3', (x, y) => y ~/ 3),
      ('y − x', (x, y) => y - x),
    ],
  ),
  _Kosul(
    ('x + y ≥ 60', (x, y) => x + y >= 60),
    ('x ≥ y', (x, y) => x >= y),
    ('x mod 5 = 0', (x, y) => x % 5 == 0),
    [
      ('x − y', (x, y) => x - y),
      ('2 · y', (x, y) => 2 * y),
      ('x div 5', (x, y) => x ~/ 5),
      ('x + 2 · y', (x, y) => x + 2 * y),
    ],
  ),
  _Kosul(
    ('x mod 2 = 1', (x, y) => x % 2 == 1),
    ('y mod 2 = 1', (x, y) => y % 2 == 1),
    ('x > y', (x, y) => x > y),
    [
      ('x + y', (x, y) => x + y),
      ('2 · x', (x, y) => 2 * x),
      ('x div 2', (x, y) => x ~/ 2),
      ('y − x', (x, y) => y - x),
    ],
  ),
  _Kosul(
    ('x ≥ 2 · y', (x, y) => x >= 2 * y),
    ('y > 10', (x, y) => y > 10),
    ('x > y', (x, y) => x > y),
    [
      ('x − 2 · y', (x, y) => x - 2 * y),
      ('x + y', (x, y) => x + y),
      ('x − y', (x, y) => x - y),
      ('y div 2', (x, y) => y ~/ 2),
    ],
  ),
  _Kosul(
    ('y > 25', (x, y) => y > 25),
    ('x > 25', (x, y) => x > 25),
    ('x > y', (x, y) => x > y),
    [
      ('x + y − 50', (x, y) => x + y - 50),
      ('y − x', (x, y) => y - x),
      ('x − y', (x, y) => x - y),
      ('x + y', (x, y) => x + y),
    ],
  ),
];

/// Bir kalıbın dalı: 0 (dış ve birinci iç koşul doğru) … 3.
int _dal(_Kosul k, int x, int y) =>
    k.dis.$2(x, y) ? (k.ic1.$2(x, y) ? 0 : 1) : (k.ic2.$2(x, y) ? 2 : 3);

/// Kalıp başına giriş havuzu: dört dalın değeri birbirinden, sıfırdan ve
/// girişlerden farklıdır (yanlış dala sapma hatası anahtarı vermez); doğru
/// dalın değeri pozitiftir.
final _kosulHavuzlari = [
  for (final k in _kosulKaliplari)
    [
      for (var x = 4; x <= 60; x++)
        for (var y = 4; y <= 60; y++)
          if (x != y && _dallarUygun(k, x, y)) (x, y),
    ],
];

bool _dallarUygun(_Kosul k, int x, int y) {
  final d = [for (final f in k.dallar) f.$2(x, y)];
  final dogru = d[_dal(k, x, y)];
  return dogru > 0 &&
      !_kosulSabitleri(k).contains(dogru) &&
      d.every((v) => v != 0 && v != x && v != y) &&
      d.toSet().length == 4;
}

/// Kalıbın koşul ve formüllerinde yazılı sayılar.
Set<int> _kosulSabitleri(_Kosul k) => {
  for (final m in RegExp(r'\d+').allMatches(
    [k.dis.$1, k.ic1.$1, k.ic2.$1, for (final f in k.dallar) f.$1].join(' '),
  ))
    int.parse(m[0]!),
};

/// Formüldeki x ve y yerine değerleri yazar.
String _yerine(String formul, int x, int y) =>
    formul.replaceAll('x', '$x').replaceAll('y', '$y');

const _notEsikleri = [85, 70, 60, 50];

int _karne(int p, {bool kesin = false}) {
  for (var t = 0; t < 4; t++) {
    if (kesin ? p > _notEsikleri[t] : p >= _notEsikleri[t]) return 5 - t;
  }
  return 1;
}

/// Kargo ücreti: ilk 2 kg için t0, 2–10 kg arasında kg başına r1, 10 kg
/// üstünde kg başına r2; hızlı teslimde e eklenir. [dal] verilirse o dalın
/// formülü kullanılır (yanlış dal hatası).
int _kargo(int t0, int r1, int r2, int e, int kg, int h, {int dal = -1}) {
  final d = dal >= 0 ? dal : (kg <= 2 ? 0 : (kg <= 10 ? 1 : 2));
  final u = switch (d) {
    0 => t0,
    1 => t0 + (kg - 2) * r1,
    _ => t0 + 8 * r1 + (kg - 10) * r2,
  };
  return h == 1 ? u + e : u;
}

/// Sınır ağırlıkları (2 ve 10 kg) dışarıda: bu ağırlıklarda iki dalın
/// formülü aynı sonucu verir.
const _kargoKilolari = [
  1,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
];

bool _artik(int y) => y % 400 == 0 || (y % 4 == 0 && y % 100 != 0);

/// Artık yıl sorusu için beş yıl: biri 400 ile bölünmeyen yüzyıl başı, biri
/// 400 sayısının katı, bir ya da ikisi 4 sayısının katı, kalanı tek yıl.
List<int> _yilSecimi(int j) {
  final yuzyil = const [1700, 1800, 1900, 2100, 2200, 2300][j % 6];
  final dortyuz = const [1600, 2000, 2400][j ~/ 6 % 3];
  final iki = j ~/ 18 % 2 == 1;
  final q = j ~/ 36;
  return [
    yuzyil,
    dortyuz,
    1908 + 4 * q,
    if (iki) 2012 + 4 * (j % 13) else 1975 + 2 * (j % 11),
    2101 + 2 * ((j * 7) % 13),
  ]..sort();
}

AdvancedItem _kosul(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 5) {
    final k = _kosulKaliplari[c];
    final (x, y) = _dolas(_kosulHavuzlari[c], j, 211);
    final d = [for (final f in k.dallar) f.$2(x, y)];
    final dal = _dal(k, x, y);
    final satirlar = [
      'x ← $x',
      'y ← $y',
      'eğer ${k.dis.$1} ise',
      '(eğer ${k.ic1.$1} ise z ← ${k.dallar[0].$1} değilse z ← '
          '${k.dallar[1].$1})',
      'değilse',
      '(eğer ${k.ic2.$1} ise z ← ${k.dallar[2].$1} değilse z ← '
          '${k.dallar[3].$1})',
      'yaz z',
    ];
    // Çeldiriciler: üç yanlış dal ya da iki hatalı tasarım (bir yanlış dal w,
    // doğru dalda elde, ödünç ya da birler basamağı hatası n + e ve ikisi
    // birlikte w + e). Girişlerle ve sıfırla aynı değerler kullanılmaz.
    String yaz(int v) => v < 0 ? '−${-v}' : '$v';
    final secilen = _ikiHataliSayisal(
      d[dal],
      [
        for (var t = 0; t < 4; t++)
          if (t != dal) d[t],
      ],
      const [10, -10, 1, -1, 2, -2, 3, -3, 20, -20],
      hedefSira(_no(a, b, c)),
      uygun: (v) => v != 0 && v != x && v != y,
    );
    return AdvancedItem(
      _kod(_notlu(_kosulGiris, satirlar), satirlar, _yazSorusu),
      yaz(d[dal]),
      [for (final v in secilen) yaz(v)],
      'x = $x ve y = $y için ${k.dis.$1} koşulu '
      '${k.dis.$2(x, y) ? 'doğrudur ve ilk' : 'yanlıştır ve ikinci'} '
      'parantezdeki yapı çalışır. ${dal < 2 ? k.ic1.$1 : k.ic2.$1} koşulu '
      '${dal.isEven ? 'doğru' : 'yanlış'} olduğundan z = '
      '${_yerine(k.dallar[dal].$1, x, y)} = ${d[dal]} yazdırılır.',
    );
  }
  switch (c) {
    case 5:
      // Ortalama tam olarak bir eşik değerine eşittir: “≥” yerine “>” alma
      // hatası her vakada başka bir not verir; toplam 3 ile tam bölünür.
      final s1 = 40 + 2 * a, s2 = 35 + 3 * b;
      var esik = _notEsikleri[(a + b) % 4];
      for (var t = 0; t < 4; t++) {
        final aday = 3 * _notEsikleri[((a + b) % 4 + t) % 4] - s1 - s2;
        if (aday >= 20 && aday <= 100) {
          esik = _notEsikleri[((a + b) % 4 + t) % 4];
          break;
        }
      }
      final s3 = 3 * esik - s1 - s2;
      final toplam = s1 + s2 + s3, p = toplam ~/ 3;
      final n = _karne(p);
      final ustler = [
        for (final e in _notEsikleri)
          if (e > p) 'p ≥ $e',
      ];
      final yanlislar = switch (ustler.length) {
        0 => '',
        1 => '${ustler.first} koşulu yanlıştır; ',
        _ =>
          '${ustler.sublist(0, ustler.length - 1).join(', ')} ve '
              '${ustler.last} koşulları yanlıştır; ',
      };
      final satirlar = [
        's1 ← $s1',
        's2 ← $s2',
        's3 ← $s3',
        'p ← (s1 + s2 + s3) div 3',
        'eğer p ≥ 85 ise n ← 5',
        'değilse eğer p ≥ 70 ise n ← 4',
        'değilse eğer p ≥ 60 ise n ← 3',
        'değilse eğer p ≥ 50 ise n ← 2',
        'değilse n ← 1',
        'yaz n',
      ];
      // Notlar 1 … 5 arasındadır. Tipik hatalar: ≥ yerine > alma, koşulları
      // bağımsız sanıp son doğru koşulun notunu (2) yazma; sonra komşu notlar.
      return _sirali(
        _kod(_notlu(_atamaGiris, satirlar), satirlar, _yazSorusu),
        n,
        '$n',
        [
          for (final x in [
            _karne(p, kesin: true),
            2,
            n + 1,
            n - 1,
            n + 2,
            n - 2,
            n + 3,
            n - 3,
          ])
            if (x >= 1 && x <= 5) (x, '$x'),
        ],
        'p = $toplam div 3 = $p olur. Koşullar yukarıdan aşağı sırayla denenir: '
            '${ustler.isEmpty ? 'ilk koşul p ≥ $p, $p ≥ $p olduğundan doğrudur' : '${yanlislar}p ≥ $p koşulu ise $p ≥ $p olduğundan doğrudur'} '
            '(≥ koşulu eşitlikte de sağlanır). Yazdırılan değer $n olur.',
        _no(a, b, c),
      );
    case 6:
      // 10 kg üstündeki kilogram ücreti daha düşüktür (r2 < r1): üç dalın
      // formülü hiçbir ağırlıkta aynı sonucu vermez.
      final t0 = 30 + a, r1 = 4 + a % 5, r2 = 2 + a % 2, e = 15 + 5 * (a % 4);
      final kg = _kargoKilolari[b];
      // 2 kg ve altında hızlı teslim eklenir (yoksa yanıt koddaki sabit
      // olurdu); yanıt koddaki bir sayıya eşit çıkarsa hızlı teslim değişir.
      var h = kg <= 2 ? 1 : (a + b) % 2;
      if (kg > 2 &&
          [
            kg,
            t0,
            r1,
            r2,
            e,
            t0 + 8 * r1,
            2,
            10,
          ].contains(_kargo(t0, r1, r2, e, kg, h))) {
        h = 1 - h;
      }
      final dal = kg <= 2 ? 0 : (kg <= 10 ? 1 : 2);
      final u = _kargo(t0, r1, r2, e, kg, h);
      final temel = _kargo(t0, r1, r2, e, kg, 0);
      final satirlar = [
        'k ← $kg',
        'h ← $h',
        'eğer k ≤ 2 ise u ← $t0',
        'değilse eğer k ≤ 10 ise u ← $t0 + (k − 2) · $r1',
        'değilse u ← ${t0 + 8 * r1} + (k − 10) · $r2',
        'eğer h = 1 ise u ← u + $e',
        'yaz u',
      ];
      final hesap = switch (dal) {
        0 => 'k ≤ 2 koşulu doğrudur; u = $t0',
        1 =>
          'k ≤ 2 yanlış, k ≤ 10 doğrudur; u = $t0 + ${kg - 2} · $r1 = $temel',
        _ =>
          'k ≤ 2 ve k ≤ 10 yanlıştır; u = ${t0 + 8 * r1} + ${kg - 10} · $r2 = '
              '$temel',
      };
      // Ek hatalar: kilogram ücretini 2 kg'dan değil baştan hesaplama, sabit
      // ücreti eklememe, 10 kg üstünde sınırı (− 10) ya da orta dilimi
      // (8 · r1) unutma, tüm kilogramlara düşük ücreti uygulama.
      final ek = h == 1 ? e : 0;
      return sayisalSirali(
        _kod(_atamaGiris, satirlar, _yazSorusu),
        u,
        [
          for (var t = 0; t < 3; t++)
            if (t != dal) _kargo(t0, r1, r2, e, kg, h, dal: t),
          _kargo(t0, r1, r2, e, kg, 1 - h),
          ...switch (dal) {
            0 => [t0 + kg * r1 + ek],
            1 => [t0 + kg * r1 + ek, (kg - 2) * r1 + ek],
            _ => [
              t0 + 8 * r1 + kg * r2 + ek,
              t0 + (kg - 10) * r2 + ek,
              t0 + (kg - 2) * r2 + ek,
            ],
          },
        ],
        'k = $kg için $hesap olur. '
        '${h == 1 ? 'h = 1 olduğundan $e eklenir ve $u yazdırılır.' : 'h = 0 olduğundan ekleme yapılmaz ve $u yazdırılır.'}',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 7:
      final yillar = _yilSecimi(j);
      final dogru = yillar.where(_artik).length;
      int say(bool Function(int) f) => yillar.where(f).length;
      final satirlar = [
        'eğer y mod 400 = 0 ise s ← 1',
        'değilse eğer y mod 100 = 0 ise s ← 0',
        'değilse eğer y mod 4 = 0 ise s ← 1',
        'değilse s ← 0',
        'yaz s',
      ];
      // Sayılar 0 … 5 arasındadır. Tipik hatalar: yalnız 4 kuralı, 400
      // kuralını unutma, 0 yazdırılanları sayma, yalnız 400 kuralı; sonra
      // komşu sayılar.
      return _sirali(
        _kod(
          _notlu(_atamaGiris, satirlar),
          satirlar,
          'Bu kod y = ${yillar.join(', ')} değerleri için ayrı ayrı '
          'çalıştırılıyor. Bu değerlerden kaç tanesi için 1 yazdırılır?',
        ),
        dogru,
        '$dogru',
        [
          for (final x in [
            say((y) => y % 4 == 0),
            say((y) => y % 4 == 0 && y % 100 != 0),
            yillar.length - dogru,
            say((y) => y % 400 == 0),
            dogru + 1,
            dogru - 1,
            dogru + 2,
            dogru - 2,
            dogru + 3,
            dogru - 3,
          ])
            if (x >= 0 && x <= yillar.length) (x, '$x'),
        ],
        '${yillar.map((y) => '$y için ${_artik(y) ? 1 : 0}').join(', ')} '
            'yazdırılır; 1 yazdırılan değer sayısı $dogru olur.',
        _no(a, b, c),
      );
    case 8:
      final t = 120 + 20 * a + b;
      int indirimli(int uye) => t >= 500
          ? (uye == 1 ? t - t ~/ 5 : t - t ~/ 10)
          : (uye == 1 ? t - 10 : t + 15);
      // Sonuç kökteki bir sayıya (500, 5, 10, 15) eşit olmasın.
      var u = (a + b) % 2;
      if ([500, 5, 10, 15, t].contains(indirimli(u))) u = 1 - u;
      int hesap(int d) => switch (d) {
        0 => t - t ~/ 5,
        1 => t - t ~/ 10,
        2 => t - 10,
        _ => t + 15,
      };
      final dal = t >= 500 ? (u == 1 ? 0 : 1) : (u == 1 ? 2 : 3);
      // Sonuç değişkeni f: tek harfli “o” adı 0 rakamıyla karışabilir.
      final satirlar = [
        't ← $t',
        'u ← $u',
        'eğer t ≥ 500 ise',
        '(eğer u = 1 ise f ← t − t div 5 değilse f ← t − t div 10)',
        'değilse',
        '(eğer u = 1 ise f ← t − 10 değilse f ← t + 15)',
        'yaz f',
      ];
      const formul = ['t − t div 5', 't − t div 10', 't − 10', 't + 15'];
      // Yanlış dallardan sonra: indirimi çıkarmak yerine ekleme, yalnız
      // indirim tutarını yazma, 10 ya da 15 eklemede işareti ters alma; en
      // sonda öbür dalların indirimini artış sanma.
      return sayisalSirali(
        _kod(_notlu(_kosulGiris, satirlar), satirlar, _yazSorusu),
        hesap(dal),
        [
          for (var d = 0; d < 4; d++)
            if (d != dal) hesap(d),
          ...switch (dal) {
            0 => [t + t ~/ 5, t ~/ 5],
            1 => [t + t ~/ 10, t ~/ 10],
            2 => [t + 10],
            _ => [t - 15],
          },
          t + 10,
          t - 15,
          t + t ~/ 10,
          t + t ~/ 5,
        ],
        't ≥ 500 koşulu ${t >= 500 ? 'doğru' : 'yanlış'}, u = 1 koşulu '
        '${u == 1 ? 'doğru' : 'yanlış'} olduğundan f = '
        '${formul[dal].replaceAll('t', '$t')} = ${hesap(dal)} yazdırılır.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    default:
      final f = [30 + a, 60 + 2 * b, 80 + a + b, 120 + 2 * a];
      final tur = (a + b) % 4, ogr = b % 2;
      var yas = switch (tur) {
        0 => 5 + (a + b) % 7,
        1 => 65 + (a * 3 + b) % 16,
        _ => 12 + (a * 7 + b * 3) % 53,
      };
      if (f.contains(yas)) yas += tur == 0 ? -1 : 1;
      final dal = yas < 12 ? 0 : (yas >= 65 ? 1 : (ogr == 1 ? 2 : 3));
      // Öğrenci bilgisi ogr adlı değişkende tutulur: tek harfli “o” adı 0
      // rakamıyla karışabilir.
      final satirlar = [
        'y ← $yas',
        'ogr ← $ogr',
        'eğer y < 12 ise f ← ${f[0]}',
        'değilse eğer y ≥ 65 ise f ← ${f[1]}',
        'değilse (eğer ogr = 1 ise f ← ${f[2]} değilse f ← ${f[3]})',
        'yaz f',
      ];
      final neden = switch (dal) {
        0 => 'y < 12 koşulu doğrudur',
        1 => 'y < 12 yanlış, y ≥ 65 doğrudur',
        _ =>
          'y < 12 ve y ≥ 65 yanlıştır; ogr = $ogr olduğundan parantezdeki '
              '${ogr == 1 ? 'ilk' : 'ikinci'} atama yapılır',
      };
      return sayisal(
        _kod(_kosulGiris, satirlar, _yazSorusu),
        f[dal],
        [
          for (var d = 0; d < 4; d++)
            if (d != dal) f[d],
        ],
        'y = $yas için $neden. Yazdırılan değer ${f[dal]} olur.',
        positive: true,
      );
  }
}

// ---------------------------------------------------------------------------
// Dizi aileleri için ortak araçlar
// ---------------------------------------------------------------------------

/// Sıra numarasından belirlenimli sözde rastgele sayılar (doğrusal eşlik).
class _Uretec {
  _Uretec(int tohum) : _x = (tohum * 2654435761 + 12345) & 0x7fffffff;
  int _x;

  /// 0 … n − 1 arasında bir sayı.
  int sonraki(int n) {
    _x = (_x * 1103515245 + 12345) & 0x7fffffff;
    return (_x >> 8) % n;
  }

  /// [lo, hi] aralığından birbirinden farklı [adet] sayı.
  List<int> farkli(int adet, int lo, int hi) {
    final r = <int>[];
    while (r.length < adet) {
      final x = lo + sonraki(hi - lo + 1);
      if (!r.contains(x)) r.add(x);
    }
    return r;
  }
}

String _diziYaz(List<int> d) => '[${d.join(', ')}]';

/// 1 … n sayılarının [sira] numaralı dizilişi (sira, n! ile bölümünden
/// kalanına göre alınır; farklı kalanlar farklı diziliş verir).
List<int> _permutasyon(int sira, int n) {
  var f = 1;
  for (var t = 2; t <= n; t++) {
    f *= t;
  }
  var k = sira % f;
  final kalan = [for (var t = 1; t <= n; t++) t], r = <int>[];
  for (var t = n; t >= 1; t--) {
    f ~/= t;
    r.add(kalan.removeAt(k ~/ f));
    k %= f;
  }
  return r;
}

const _ustRakam = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];

/// Üst simgeli üs: 2 ve 10 → "2¹⁰".
String _us(int taban, int us) =>
    '$taban${'$us'.split('').map((h) => _ustRakam[int.parse(h)]).join()}';

const _diziNotu =
    'A[i], A dizisinin i numaralı elemanını gösterir; numaralandırma 1 ile '
    'başlar (ilk eleman A[1]).';

const _kodDiziGiris =
    'Aşağıdaki sözde kodda ← atama işlemidir; döngünün gövdesi “döngü sonu” '
    'satırına kadar olan satırlardır. $_diziNotu';

// ---------------------------------------------------------------------------
// 11. Dizi işlemleri
// ---------------------------------------------------------------------------

AdvancedItem _dizi(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 3) {
    // İndisle iki adımlı erişim: x ← A[k], y ← A[x]; 10 · x + y yazdırılır
    // (yanıt dizideki tek basamaklı değerlerden biri olamaz).
    const n = 8;
    final d = _permutasyon((j + 500 * c) * 7919 + 101, n);
    int al(int t) => d[t - 1];
    // A[A[k]] = A[k] olan k seçilmez: y ← x sanma hatası anahtarı vermez.
    var k = 1 + (j + c) % (n - 1);
    for (var t = 0; t < n - 1 && al(al(k)) == al(k); t++) {
      k = 1 + k % (n - 1);
    }
    final x = al(k), y = al(x);
    final x0 = al(k + 1);
    // Ek hatalar: erişimlerden yalnız birini 0 ile başlayan indisle okuma
    // (bir sağdaki ya da soldaki eleman).
    return sayisalSirali(
      _kod(
        'A = ${_diziYaz(d)} dizisi veriliyor. $_diziNotu Aşağıdaki sözde '
        'kodda ← atama işlemidir.',
        ['x ← A[$k]', 'y ← A[x]', 'yaz 10 · x + y'],
        _yazSorusu,
      ),
      10 * x + y,
      [
        if (x0 < n) 10 * x0 + al(x0 + 1),
        11 * x,
        10 * k + x,
        10 * y + x,
        if (x < n) 10 * x + al(x + 1),
        10 * x0 + al(x0),
        if (x > 1) 10 * x + al(x - 1),
        if (k > 1) 10 * al(k - 1) + al(al(k - 1)),
      ],
      'A[$k] = $x olduğundan x = $x olur. y = A[$x] = $y bulunur. Yazdırılan '
      'değer 10 · $x + $y = ${10 * x + y} olur.',
      hedefSira(_no(a, b, c)),
      positive: true,
    );
  }
  if (c < 6) {
    // En büyük elemanın indisi: > ile ilk, ≥ ile son görülen.
    final m = j + 500 * (c - 3);
    final g = _Uretec(11 * m + 5);
    final n = 7 + m % 3;
    final esit = (m ~/ 3).isOdd;
    while (true) {
      final d = g.farkli(n, 10, 99);
      final enb = d.reduce((u, v) => u > v ? u : v);
      final p1 = d.indexOf(enb) + 1;
      var p2 = p1;
      if ((m ~/ 6).isOdd) {
        // En büyük değer bir kez daha yazılır.
        p2 = 3 + g.sonraki(n - 3);
        if (p2 == p1) continue;
        d[p2 - 1] = enb;
      }
      final ilk = p1 < p2 ? p1 : p2, son = p1 < p2 ? p2 : p1;
      final dogru = esit ? son : ilk;
      if (dogru < 3 || dogru >= n) continue;
      final enk = d.indexOf(d.reduce((u, v) => u < v ? u : v)) + 1;
      // Ek hatalar: m değerinin döngü sonundaki i olduğunu sanma, indisi bir
      // fazla sayma, m değerinin hiç değişmediğini sanma.
      return sayisalSirali(
        _kod(_kodDiziGiris, [
          'A ← ${_diziYaz(d)}',
          'm ← 1',
          'i = 2, 3, …, $n için',
          'eğer A[i] ${esit ? '≥' : '>'} A[m] ise m ← i',
          'döngü sonu',
          'yaz m',
        ], _yazSorusu),
        dogru,
        [
          if (ilk != son) esit ? ilk : son,
          dogru - 1,
          enk,
          enb,
          n,
          dogru + 1,
          1,
        ],
        'm, o ana kadar görülen en büyük elemanın indisini tutar. En büyük '
        'değer $enb olup ${ilk == son ? '$ilk numaralı konumdadır' : '$ilk ve $son numaralı konumlarda bulunur; koşul ${esit ? '≥' : '>'} olduğundan ${esit ? 'eşit değerde de m güncellenir ve son konum' : 'eşit değerde m değişmez ve ilk konum'} kalır'}. '
        'Yazdırılan değer $dogru olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    }
  }
  // Koşula uyan elemanların toplamı.
  final m = j + 500 * (c - 6);
  final g = _Uretec(13 * m + 3);
  final tur = m ~/ 3 % 4;
  // Tek indisli toplamda n tektir: son eleman da toplama girer.
  final n = tur == 2 ? 7 : 6 + m % 3;
  while (true) {
    final d = g.farkli(n, 3, 60);
    final esik = d[1 + g.sonraki(n - 1)];
    final (kosul, uyar, sinirli) = switch (tur) {
      0 => ('A[i] mod 2 = 0', (int i) => d[i - 1].isEven, null),
      1 => (
        'A[i] > $esik',
        (int i) => d[i - 1] > esik,
        (int i) => d[i - 1] >= esik,
      ),
      2 => ('i mod 2 = 1', (int i) => i.isOdd, (int i) => i.isEven),
      _ => ('A[i] mod 3 = 0', (int i) => d[i - 1] % 3 == 0, null),
    };
    int topla(bool Function(int) f) => _topla([
      for (var i = 1; i <= n; i++)
        if (f(i)) d[i - 1],
    ]);
    final uyanlar = [
      for (var i = 1; i <= n; i++)
        if (uyar(i)) i,
    ];
    final dogru = topla(uyar), tum = _topla(d);
    // En az iki eleman koşulu sağlar; anahtar kökteki bir sayıya, tümleyen
    // toplama ya da sınır/indis hatasıyla bulunan toplama eşit değildir.
    if (uyanlar.length < 2 ||
        uyanlar.length == n ||
        (tur != 2 && !uyar(n)) ||
        d.contains(dogru) ||
        dogru == n ||
        dogru == esik ||
        2 * dogru == tum ||
        (sinirli != null && topla(sinirli) == dogru)) {
      continue;
    }
    // Ek hatalar: döngüyü son elemandan önce bitirme, A[i] yerine i
    // toplama, toplamak yerine sayma.
    return sayisalSirali(
      _kod('$_kodDiziGiris$_modNotu', [
        'A ← ${_diziYaz(d)}',
        't ← 0',
        'i = 1, 2, …, $n için',
        'eğer $kosul ise t ← t + A[i]',
        'döngü sonu',
        'yaz t',
      ], _yazSorusu),
      dogru,
      [
        if (sinirli != null) topla(sinirli),
        tum - dogru,
        tum,
        dogru + d[0],
        dogru - d[n - 1],
        _topla(uyanlar),
        uyanlar.length,
      ],
      'Koşulu sağlayan elemanlar '
      '${uyanlar.map((i) => 'A[$i] = ${d[i - 1]}').join(', ')} olduğundan '
      't = ${uyanlar.map((i) => d[i - 1]).join(' + ')} = $dogru olur.',
      hedefSira(_no(a, b, c)),
      positive: true,
    );
  }
}

// ---------------------------------------------------------------------------
// 12. Sıralama algoritmaları
// ---------------------------------------------------------------------------

/// Kabarcık sıralamasının bir geçişi (küçükten büyüğe).
List<int> _kabarcikGecis(List<int> d, {bool azalan = false}) {
  final r = [...d];
  for (var i = 0; i + 1 < r.length; i++) {
    if (azalan ? r[i] < r[i + 1] : r[i] > r[i + 1]) {
      final t = r[i];
      r[i] = r[i + 1];
      r[i + 1] = t;
    }
  }
  return r;
}

int _gecisDegisimi(List<int> d) {
  final r = [...d];
  var s = 0;
  for (var i = 0; i + 1 < r.length; i++) {
    if (r[i] > r[i + 1]) {
      final t = r[i];
      r[i] = r[i + 1];
      r[i + 1] = t;
      s++;
    }
  }
  return s;
}

int _tersCiftler(List<int> d) => _topla([
  for (var i = 0; i < d.length; i++)
    for (var k = i + 1; k < d.length; k++)
      if (d[i] > d[k]) 1,
]);

/// Seçerek sıralamanın yer değiştirme sayısı (en küçük eleman yerindeyse
/// değiştirme yapılmaz).
int _secmeDegisimi(List<int> d) {
  final r = [...d];
  var s = 0;
  for (var i = 0; i + 1 < r.length; i++) {
    var m = i;
    for (var k = i + 1; k < r.length; k++) {
      if (r[k] < r[m]) m = k;
    }
    if (m != i) {
      final t = r[i];
      r[i] = r[m];
      r[m] = t;
      s++;
    }
  }
  return s;
}

const _kabarcikKodu = [
  'i = 1, 2, …, n − 1 için',
  'eğer A[i] > A[i + 1] ise A[i] ile A[i + 1] değerlerinin yerini değiştir',
  'döngü sonu',
];

AdvancedItem _siralama(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 4) {
    final m = j + 500 * c;
    final g = _Uretec(17 * m + 7);
    final n = 6 + m % 2;
    while (true) {
      final d = g.farkli(n, 1, 60);
      final dogru = _kabarcikGecis(d);
      final sirali = [...d]..sort();
      final enb = sirali.last;
      final yalnizEnb = [...d.where((x) => x != enb), enb];
      final ilkEnk = [...d];
      final km = ilkEnk.indexOf(sirali.first);
      ilkEnk[km] = ilkEnk[0];
      ilkEnk[0] = sirali.first;
      final adaylar = <String>{
        for (final r in [
          sirali,
          yalnizEnb,
          ilkEnk,
          _kabarcikGecis(d, azalan: true),
        ])
          if (_diziYaz(r) != _diziYaz(dogru)) _diziYaz(r),
      };
      if (adaylar.length < 3 ||
          _diziYaz(dogru) == _diziYaz(sirali) ||
          _diziYaz(dogru) == _diziYaz(yalnizEnb)) {
        continue;
      }
      return secenekli(
        'Kabarcık sıralamasının bir geçişi aşağıdaki sözde kodla yapılmaktadır. '
            '$_diziNotu\n${_kabarcikKodu.join('\n')}\nn = $n ve A = '
            '${_diziYaz(d)} iken bu geçiş bir kez uygulanırsa dizi hangi '
            'duruma gelir?',
        _diziYaz(dogru),
        adaylar,
        'Yan yana elemanlar soldan sağa karşılaştırılır ve soldaki büyükse yer '
            'değiştirilir. ${d.last == enb ? 'En büyük eleman $enb zaten en sondadır ve yerinde kalır; geçiş sonunda' : 'Geçiş sonunda en büyük eleman $enb en sona taşınır ve'} '
            'dizi ${_diziYaz(dogru)} olur.',
      );
    }
  }
  if (c < 7) {
    final m = j + 500 * (c - 4);
    final g = _Uretec(19 * m + 11);
    final n = 6 + m % 3;
    while (true) {
      final d = g.farkli(n, 10, 79);
      final s = _secmeDegisimi(d), ters = _tersCiftler(d);
      final sirali = [...d]..sort();
      final yersiz = _topla([
        for (var i = 0; i < n; i++)
          if (d[i] != sirali[i]) 1,
      ]);
      if (s == n - 1 || s == ters || s == yersiz || s < 2) continue;
      // Ek hatalar: son değiştirmeyi saymama, değiştirme yapılmayan adımları
      // sayma, her değiştirmenin iki elemanı yerleştirdiğini sanma, başta
      // yerinde olan elemanları sayma.
      return sayisalSirali(
        'Seçerek sıralama, her adımda dizinin henüz sıralanmamış bölümündeki en '
            'küçük elemanı bulur; bu eleman o bölümün ilk konumunda değilse '
            'ikisinin yerini değiştirir, ilk konumdaysa değiştirme yapmaz. '
            '${_diziYaz(d)} dizisi bu yöntemle küçükten büyüğe sıralanırsa '
            'toplam kaç yer değiştirme yapılır?',
        s,
        [
          n - 1,
          ters,
          yersiz,
          s + 1,
          s - 1,
          n - 1 - s,
          (yersiz + 1) ~/ 2,
          n - yersiz,
        ],
        'Adım adım: ${_secmeIzi(d)}. Toplam $s yer değiştirme yapılır.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    }
  }
  final m = j + 500 * (c - 7);
  final g = _Uretec(23 * m + 13);
  final n = 6 + m % 3;
  while (true) {
    final d = g.farkli(n, 10, 89);
    final s = _gecisDegisimi(d), ters = _tersCiftler(d);
    if (s < 3 || s >= n - 1 || s == ters) continue;
    final gecis = _kabarcikGecis(d);
    final yeri = [
      for (var i = 0; i < n; i++)
        if (gecis[i] != d[i]) 1,
    ].length;
    // Ek hatalar: yer değiştirme olmayan karşılaştırmaları sayma, yeri
    // değişen eleman sayısını yazma.
    return sayisalSirali(
      'Kabarcık sıralamasının bir geçişi aşağıdaki sözde kodla yapılmaktadır. '
          '$_diziNotu\n${_kabarcikKodu.join('\n')}\nn = $n ve A = '
          '${_diziYaz(d)} iken bu geçiş bir kez uygulanırsa toplam kaç yer '
          'değiştirme yapılır?',
      s,
      [n - 1, ters, s + 1, s - 1, n - 1 - s, yeri],
      'Geçişte yan yana çiftler soldan sağa karşılaştırılır; soldaki büyük '
          'olduğunda yer değiştirilir. Geçiş sonunda dizi '
          '${_diziYaz(_kabarcikGecis(d))} olur ve $s yer değiştirme yapılmış '
          'olur.',
      hedefSira(_no(a, b, c)),
      positive: true,
    );
  }
}

/// Seçerek sıralamanın adımlarını kısa biçimde yazar.
String _secmeIzi(List<int> d) {
  final r = [...d], adimlar = <String>[];
  for (var i = 0; i + 1 < r.length; i++) {
    var m = i;
    for (var k = i + 1; k < r.length; k++) {
      if (r[k] < r[m]) m = k;
    }
    if (m != i) {
      adimlar.add('${r[m]} ile ${r[i]} yer değiştirir');
      final t = r[i];
      r[i] = r[m];
      r[m] = t;
    } else {
      adimlar.add('${r[i]} yerinde kalır');
    }
  }
  return adimlar.join(', ');
}

// ---------------------------------------------------------------------------
// 13. İkili arama
// ---------------------------------------------------------------------------

const _ikiliAramaKodu = [
  'alt ← 1',
  'ust ← n',
  'alt ≤ ust olduğu sürece',
  'orta ← (alt + ust) div 2',
  'eğer A[orta] = x ise “bulundu” yaz ve dur',
  'değilse eğer A[orta] < x ise alt ← orta + 1',
  'değilse ust ← orta − 1',
  'döngü sonu',
];

/// İkili aramada bakılan elemanlar. [yukari] doğruysa orta yukarı yuvarlanır;
/// [kayik] doğruysa A[orta] yerine bir sağdaki eleman okunur (indisi 0 ile
/// başlıyormuş gibi okuma hatası).
List<int> _ikiliIz(
  List<int> d,
  int x, {
  bool yukari = false,
  bool kayik = false,
}) {
  var alt = 1, ust = d.length;
  final r = <int>[];
  while (alt <= ust) {
    final orta = (alt + ust + (yukari ? 1 : 0)) ~/ 2;
    final i = kayik ? orta : orta - 1;
    if (i >= d.length) break;
    r.add(d[i]);
    if (d[i] == x) break;
    if (d[i] < x) {
      alt = orta + 1;
    } else {
      ust = orta - 1;
    }
  }
  return r;
}

int _enKotu(int n) => n.bitLength;

AdvancedItem _ikiliArama(int a, int b, int c) {
  final j = a + 25 * b;
  const giris =
      'Küçükten büyüğe sıralı A dizisinde x değeri aşağıdaki ikili aramayla '
      'aranıyor. ← atama, a div b tam sayı bölümdür; “olduğu sürece” döngüsü '
      'koşul doğru oldukça tekrar eder. A[i], i numaralı elemandır (ilk '
      'eleman A[1]).';
  if (c < 7) {
    final m = j + 500 * (c < 4 ? c : c - 4);
    final g = _Uretec((c < 4 ? 29 : 31) * m + 17);
    while (true) {
      final n = 11 + g.sonraki(17);
      final d = g.farkli(n, 10, 99)..sort();
      final yok = c < 4 && m % 4 == 3;
      int x;
      if (yok) {
        x = d[0] + 1 + g.sonraki(d.last - d[0] - 1);
        if (d.contains(x)) continue;
      } else {
        x = d[g.sonraki(n)];
      }
      final iz = _ikiliIz(d, x);
      final konum = d.indexOf(x) + 1;
      final dogrusal = yok ? n : konum;
      if (c < 4) {
        final say = iz.length;
        if (say < 3 || say == dogrusal || say == n || say == _enKotu(n)) {
          continue;
        }
        // Ek hatalar: orta değeri yukarı yuvarlama, A[orta] değerini bir
        // sağdan okuma, yalnız aralığı daraltan adımları sayma.
        return sayisalSirali(
          '$giris\nn = $n, A = ${_diziYaz(d)} ve x = $x için:\n'
              '${_ikiliAramaKodu.join('\n')}\nHer döngü adımında A[orta] '
              'elemanına bakılması bir karşılaştırma sayılırsa algoritma kaç '
              'karşılaştırma yapar?',
          say,
          [
            dogrusal,
            _enKotu(n),
            say + 1,
            say - 1,
            _ikiliIz(d, x, yukari: true).length,
            _ikiliIz(d, x, kayik: true).length,
            say - 2,
          ],
          'Bakılan elemanlar sırasıyla ${iz.join(', ')} olur. '
              '${yok ? 'Son adımda alt değeri ust değerini geçer ve x bulunamaz' : 'Son bakılan eleman x değerine eşittir'}; '
              'toplam $say karşılaştırma yapılır.',
          hedefSira(_no(a, b, c)),
          positive: true,
        );
      }
      final yukari = _ikiliIz(d, x, yukari: true);
      final sifir = _ikiliIz(d, x, kayik: true);
      final aday = <String>{
        for (final r in [yukari, sifir, d.sublist(0, iz.length)])
          if (r.join(', ') != iz.join(', ')) r.join(', '),
      };
      if (iz.length < 3 || aday.length < 3) continue;
      return secenekli(
        '$giris\nn = $n, A = ${_diziYaz(d)} ve x = $x için:\n'
            '${_ikiliAramaKodu.join('\n')}\nAlgoritmanın sırasıyla baktığı '
            'A[orta] değerleri hangi seçenekte verilmiştir?',
        iz.join(', '),
        aday,
        'İlk adımda orta = (1 + $n) div 2 = ${(1 + n) ~/ 2} ve A[orta] = '
            '${iz.first} olur. Aralık her adımda yarıya iner; bakılan değerler '
            '${iz.join(', ')} bulunur.',
      );
    }
  }
  final m = j + 500 * (c - 7);
  if (m.isEven) {
    final n = 100 + 37 * (m ~/ 2) + (m ~/ 2) * (m ~/ 2) * 3;
    final k = _enKotu(n);
    // Ek hatalar: doğrusal aramanın en kötü durumu (n), yarıya indirme
    // sayısını bir eksik ya da iki eksik alma.
    return sayisalSirali(
      'Küçükten büyüğe sıralı bir listede $n kayıt bulunmaktadır. İkili arama '
          'her adımda aranan değeri aralığın ortasındaki kayıtla karşılaştırıp '
          'aralığı yarıya indirir. Bir değer en kötü durumda en çok kaç '
          'karşılaştırmada bulunur ya da listede olmadığı anlaşılır?',
      k,
      [k - 1, k + 1, n ~/ 2, n, k - 2, k + 2],
      '${_us(2, k - 1)} = ${1 << (k - 1)} ≤ $n < ${_us(2, k)} = ${1 << k} '
          'olduğundan en kötü durumda ${k - 1} kez yarıya indirmeden sonra tek '
          'kayıt kalır; toplam $k karşılaştırma yapılır.',
      hedefSira(_no(a, b, c)),
      positive: true,
    );
  }
  final n = 40 + 11 * (m ~/ 2) + (m ~/ 2) * (m ~/ 2);
  final k = _enKotu(n);
  // Ek hatalar: farkı almayı unutma, iki sayıyı toplama, ikili arama için
  // k + 1 alma, doğrusal arama için n / 2 alıp ayrıca bir eksik sayma.
  return sayisalSirali(
    'Küçükten büyüğe sıralı bir listede $n kayıt vardır. Doğrusal arama '
        'kayıtları baştan sona tek tek, ikili arama ise her adımda aralığın '
        'ortasındaki kayda bakarak aralığı yarıya indirerek arar. Listede '
        'bulunmayan bir değer arandığında doğrusal aramanın yaptığı '
        'karşılaştırma sayısı, ikili aramanın en kötü durumdaki karşılaştırma '
        'sayısından kaç fazladır?',
    n - k,
    [
      n - k + 1,
      n - k - 1,
      n ~/ 2 - k,
      n - (k - 1),
      n,
      n + k,
      n - k - 2,
      n ~/ 2 - k + 1,
    ],
    'Doğrusal arama $n kaydın hepsine bakar. İkili arama için '
        '${_us(2, k - 1)} = ${1 << (k - 1)} ≤ $n < ${_us(2, k)} = ${1 << k} '
        'olduğundan en çok $k karşılaştırma gerekir. Fark $n − $k = ${n - k} '
        'olur.',
    hedefSira(_no(a, b, c)),
    positive: true,
  );
}

// ---------------------------------------------------------------------------
// 14. Özyinelemeli fonksiyonlar: değer ve çağrı sayısı
// ---------------------------------------------------------------------------

const _ozGiris =
    'Aşağıdaki özyinelemeli fonksiyon kendini çağırarak çalışır; “döndür” '
    'komutu, hesaplanan değeri çağrının yapıldığı yere geri verir.';

String _fonksiyon(String ad, List<String> satirlar) =>
    '$ad:\n${satirlar.join('\n')}';

/// Bölme özyinelemesi için (n, k) havuzu: n mod k en az 2 (kalanı unutma ya
/// da bir fazla sayma hatası anahtarı vermez), sonuç k sayısına eşit değildir
/// ve çağrı derinliği en çok 15 olur.
final _bolmeHavuzu = [
  for (var k = 3; k <= 12; k++)
    for (var n = 2 * k + 1; n <= 15 * k; n++)
      if (n % k > 1 && n ~/ k != n % k && n ~/ k + n % k != k) (n, k),
];

/// Öklid algoritması zinciri: x, y, kalanlar …, 0.
List<int> _oklid(int x, int y) {
  final r = [x, y];
  while (r.last != 0) {
    r.add(r[r.length - 2] % r.last);
  }
  return r;
}

/// mod yerine div ile ilerleyen (hatalı) Öklid zincirinin döndürdüğü değer.
int _divZinciri(int x, int y) {
  while (y != 0) {
    final t = x ~/ y;
    x = y;
    y = t;
  }
  return x;
}

/// EBOB vakaları: en az dört çağrı, EBOB en az 2; x − y farkı EBOB değerine
/// eşit değildir (çıkarma hatası anahtarı vermez).
final _ebobHavuzu = [
  for (var x = 40; x <= 300; x += 3)
    for (var y = 18; y < x; y += 5)
      if (x.gcd(y) >= 2 &&
          _oklid(x, y).length >= 5 &&
          x % y != 0 &&
          x - y != x.gcd(y))
        (x, y),
];

/// Çağrı sayısı sorusu için: EBOB değeri çağrı sayısına eşit değildir.
final _ebobCagriHavuzu = [
  for (final (x, y) in _ebobHavuzu)
    if (x.gcd(y) != _oklid(x, y).length - 1) (x, y),
];

AdvancedItem _ozyineleme(int a, int b, int c) {
  final j = a + 25 * b;
  switch (c) {
    case 0:
      final p = 1 + a, k = 2 + b % 4, m = 4 + b ~/ 4;
      int f(int n) => p + k * n * (n + 1) ~/ 2;
      return sayisalSirali(
        _kod(_ozGiris, [
          _fonksiyon('f(n)', [
            'eğer n = 0 ise $p döndür',
            'değilse f(n − 1) + $k · n döndür',
          ]),
        ], 'f($m) çağrısının döndürdüğü değer kaçtır?'),
        f(m),
        // Ek hata: 1 + 2 + … + m toplamında 2 ile bölmeyi unutma.
        [f(m - 1), f(m + 1), f(m) - p, p + k * m, p + k * m * (m + 1)],
        'f($m) = f(${m - 1}) + $k · $m = … = f(0) + $k · (1 + 2 + … + $m) = '
        '$p + $k · ${m * (m + 1) ~/ 2} = ${f(m)} olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 1:
      final p = 1 + a, q = 2 + b % 2, m = 3 + (b ~/ 2) % 4, r = 1 + b ~/ 8;
      final iz = [p];
      for (var n = 2; n <= m + 1; n++) {
        iz.add(q * iz.last + r);
      }
      final dogru = iz[m - 1], once = iz[m - 2];
      return sayisalSirali(
        _kod(_ozGiris, [
          _fonksiyon('f(n)', [
            'eğer n = 1 ise $p döndür',
            'değilse $q · f(n − 1) + $r döndür',
          ]),
        ], 'f($m) çağrısının döndürdüğü değer kaçtır?'),
        dogru,
        // Ek hatalar: r eklemeyi hiç yapmama, temel durumda da r ekleme.
        [
          once,
          iz[m],
          q * once,
          q * (once + r),
          p * _kuvvet(q, m - 1),
          dogru + r * _kuvvet(q, m - 1),
        ],
        'f(1) = $p olup her adımda önceki değer $q ile çarpılıp $r eklenir: '
        '${[for (var n = 1; n <= m; n++) 'f($n) = ${iz[n - 1]}'].join(', ')}.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 2:
      final p = 1 + a, q = 1 + b;
      int fm(int m) {
        var u = p, v = q;
        for (var t = 2; t < m; t++) {
          final w = u + v;
          u = v;
          v = w;
        }
        return v;
      }
      // f(m) kökteki bir sayıya eşitse m bir sonraki değere alınır (p ve q
      // vakayı belirlediği için m değişse de kök tek kalır).
      var m = 5 + (a + b) % 5;
      for (var t = 0; t < 4 && [p, q, m, 1, 2].contains(fm(m)); t++) {
        m = 5 + (m - 4) % 5;
      }
      List<int> iz(int u, int v) {
        final r = [u, v];
        while (r.length < m + 1) {
          r.add(r[r.length - 1] + r[r.length - 2]);
        }
        return r;
      }
      final d = iz(p, q);
      return sayisalSirali(
        _kod(_ozGiris, [
          _fonksiyon('f(n)', [
            'eğer n = 1 ise $p döndür',
            'değilse eğer n = 2 ise $q döndür',
            'değilse f(n − 1) + f(n − 2) döndür',
          ]),
        ], 'f($m) çağrısının döndürdüğü değer kaçtır?'),
        d[m - 1],
        // Ek hatalar: iki adım eksik, iki temel değeri de aynı alma.
        [
          d[m - 2],
          d[m],
          if (p != q) iz(q, p)[m - 1],
          d[m - 1] + d[m - 3],
          d[m - 3],
          iz(p, p)[m - 1],
          iz(q, q)[m - 1],
        ],
        'Değerler sırasıyla '
        '${[for (var n = 1; n <= m; n++) 'f($n) = ${d[n - 1]}'].join(', ')} '
        'olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 3:
      final (n, k) = _dolas(_bolmeHavuzu, j, 307);
      final dogru = n ~/ k + n % k;
      return sayisalSirali(
        _kod(_ozGiris, [
          _fonksiyon('f(n)', [
            'eğer n < $k ise n döndür',
            'değilse f(n − $k) + 1 döndür',
          ]),
        ], 'f($n) çağrısının döndürdüğü değer kaçtır?'),
        dogru,
        [n ~/ k, n % k, dogru + 1, n ~/ k + 1, dogru - 1],
        'Her çağrıda n değeri $k azalır ve sonuca 1 eklenir. $n sayısından '
        '${n ~/ k} kez $k çıkarılınca ${n % k} kalır; bu değer $k sayısından '
        'küçük olduğundan kendisi döndürülür. Sonuç ${n ~/ k} + ${n % k} = '
        '$dogru olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 4:
      final m = 8 + a, d = 2 + b % 3, k = 1 + b ~/ 3;
      final terimler = [for (var n = m; n > 0; n -= d) n];
      final dogru = k * _topla(terimler);
      return sayisalSirali(
        _kod(_ozGiris, [
          _fonksiyon('f(n)', [
            'eğer n ≤ 0 ise 0 döndür',
            'değilse ${k == 1 ? 'n' : '$k · n'} + f(n − $d) döndür',
          ]),
        ], 'f($m) çağrısının döndürdüğü değer kaçtır?'),
        dogru,
        [
          dogru - k * m,
          k * m * (m + 1) ~/ 2,
          if (k > 1) _topla(terimler),
          dogru + k * (terimler.last - d),
          // Ek hatalar: ilk terimi iki kez ekleme, son çağrıdan önce durma,
          // yalnız ilk terimi alma.
          dogru + k * m,
          dogru - k * terimler.last,
          k * m,
        ],
        'f($m) = ${terimler.map((n) => k == 1 ? '$n' : '$k · $n').join(' + ')} '
        '+ 0 = $dogru olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 5:
      final (x, y) = _dolas(_ebobHavuzu, j, 401);
      final z = _oklid(x, y);
      final dogru = z[z.length - 2];
      return sayisalSirali(
        _kod('$_ozGiris$_modNotu', [
          _fonksiyon('g(x, y)', [
            'eğer y = 0 ise x döndür',
            'değilse g(y, x mod y) döndür',
          ]),
        ], 'g($x, $y) çağrısının döndürdüğü değer kaçtır?'),
        dogru,
        // Ek hatalar: çağrı sayısını yazma, mod yerine div ile ilerleme,
        // sayıları aralarında asal sanma.
        [z[2], z[z.length - 3], y, x - y, z.length - 1, _divZinciri(x, y), 1],
        'Çağrılar ${[for (var t = 0; t + 1 < z.length; t++) 'g(${z[t]}, ${z[t + 1]})'].join(' → ')} '
        'biçiminde ilerler; y = 0 olduğunda x = $dogru döndürülür.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 6:
      final m = 20 + a;
      final t = const [0, 1, 2, 3, 5][b % 5], d = 2 + b ~/ 5;
      final cagri = <int>[];
      for (var n = m; ; n -= d) {
        cagri.add(n);
        if (n <= t) break;
      }
      final say = cagri.length;
      final fonk = _fonksiyon('f(n)', [
        'eğer n ≤ $t ise 0 döndür',
        'değilse n + f(n − $d) döndür',
      ]);
      final zincir =
          'Çağrılar ${cagri.map((n) => 'f($n)').join(' → ')} biçiminde ilerler; '
          'son çağrıda n ≤ $t olduğundan yeni çağrı yapılmaz.';
      if (![m, t, d, 0].contains(say)) {
        return sayisalSirali(
          _kod(
            _ozGiris,
            [fonk],
            'f($m) çağrıldığında f fonksiyonu ilk çağrı da sayılmak üzere '
            'toplam kaç kez çalışır?',
          ),
          say,
          [say - 1, say + 1, m - t, say + 2, (m - t) ~/ d, m ~/ d],
          '$zincir Toplam $say çağrı vardır.',
          hedefSira(_no(a, b, c)),
          positive: true,
        );
      }
      // Çağrı sayısı kökte yazılı bir sayıya eşitse döndürülen değer sorulur.
      final terimler = cagri.sublist(0, say - 1);
      final deger = _topla(terimler);
      return sayisalSirali(
        _kod(_ozGiris, [fonk], 'f($m) çağrısının döndürdüğü değer kaçtır?'),
        deger,
        [
          deger + cagri.last,
          deger - m,
          _topla([for (var n = t + 1; n <= m; n++) n]),
          deger + d,
          deger - terimler.last,
        ],
        '$zincir Döndürülen değer ${terimler.join(' + ')} + 0 = $deger olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 7:
      final k = const [2, 3, 4, 10][b % 4], n = 21 + 40 * a + 2 * (b ~/ 4);
      final iz = [n];
      while (iz.last >= k) {
        iz.add(iz.last ~/ k);
      }
      final say = iz.length, deger = say - 1;
      final fonk = _fonksiyon('f(n)', [
        'eğer n < $k ise 0 döndür',
        'değilse f(n div $k) + 1 döndür',
      ]);
      // Çağrı sayısı kökteki bir sayıya eşitse döndürülen değer sorulur.
      final cagriSor =
          ![n, k, 0, 1].contains(say) || [n, k, 0, 1].contains(deger);
      return sayisalSirali(
        _kod(
          '$_ozGiris$_divNotu',
          [fonk],
          cagriSor
              ? 'f($n) çağrıldığında f fonksiyonu ilk çağrı da sayılmak üzere '
                    'toplam kaç kez çalışır?'
              : 'f($n) çağrısının döndürdüğü değer kaçtır?',
        ),
        cagriSor ? say : deger,
        cagriSor
            ? [say - 1, say + 1, if (k != 2) n.bitLength, n ~/ k]
            : [say, deger + 1, if (k != 2) n.bitLength - 1, n ~/ k],
        'Çağrılar ${iz.map((v) => 'f($v)').join(' → ')} biçimindedir; son '
        'çağrı 0 döndürür ve her önceki çağrı 1 ekler. '
        '${cagriSor ? 'Toplam $say çağrı yapılır.' : 'Döndürülen değer $deger olur.'}',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 8:
      final (x, y) = _dolas(_ebobCagriHavuzu, j, 211);
      final z = _oklid(x, y);
      final say = z.length - 1;
      return sayisalSirali(
        _kod(
          '$_ozGiris$_modNotu',
          [
            _fonksiyon('g(x, y)', [
              'eğer y = 0 ise x döndür',
              'değilse g(y, x mod y) döndür',
            ]),
          ],
          'g($x, $y) çağrıldığında g fonksiyonu ilk çağrı da sayılmak üzere '
              'toplam kaç kez çalışır?',
        ),
        say,
        [say - 1, say + 1, z[z.length - 2]],
        'Çağrılar ${[for (var t = 0; t + 1 < z.length; t++) 'g(${z[t]}, ${z[t + 1]})'].join(' → ')} '
        'biçimindedir; toplam $say çağrı yapılır.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    default:
      final x = a, y = 30 + 2 * b;
      // x ve y vakayı belirler; adım büyüklükleri d ve e, sorulan sayı kökte
      // yazılı olmayacak biçimde seçilir.
      var d = 1 + (a + b) % 3, e = 1 + (a + 2 * b) % 4, adim = 0;
      for (var t = 0; t < 12; t++) {
        final d2 = 1 + (d - 1 + t) % 3, e2 = 1 + (e - 1 + t ~/ 3) % 4;
        final ad2 = ((y - x) + d2 + e2 - 1) ~/ (d2 + e2);
        final bas = [x, y, d2, e2, 0, 1];
        if (!bas.contains(ad2 + 1) || !bas.contains(ad2)) {
          d = d2;
          e = e2;
          break;
        }
      }
      var u = x, v = y;
      while (u < v) {
        u += d;
        v -= e;
        adim++;
      }
      final say = adim + 1;
      final basili = [x, y, d, e, 0, 1];
      final cagriSor = !basili.contains(say) || basili.contains(adim);
      return sayisalSirali(
        _kod(
          _ozGiris,
          [
            _fonksiyon('h(x, y)', [
              'eğer x ≥ y ise 0 döndür',
              'değilse 1 + h(x + $d, y − $e) döndür',
            ]),
          ],
          cagriSor
              ? 'h($x, $y) çağrıldığında h fonksiyonu ilk çağrı da sayılmak '
                    'üzere toplam kaç kez çalışır?'
              : 'h($x, $y) çağrısının döndürdüğü değer kaçtır?',
        ),
        cagriSor ? say : adim,
        // Ek hatalar: farkın yalnız x ya da yalnız y adımıyla kapandığını
        // sanma.
        cagriSor
            ? [
                adim,
                say + 1,
                (y - x) ~/ (d + e),
                say + 2,
                (y - x) ~/ d,
                (y - x) ~/ e,
              ]
            : [
                say,
                adim + 1,
                (y - x) ~/ (d + e),
                adim - 1,
                (y - x) ~/ d,
                (y - x) ~/ e,
              ],
        'Her çağrıda x değeri $d artar, y değeri $e azalır; aradaki fark '
        '${d + e} küçülür. Fark ${y - x} iken $adim adımda x ≥ y olur. '
        '${cagriSor ? 'Bu $adim çağrıya koşulun sağlandığı son çağrı da eklenince $say bulunur.' : 'Her adım sonuca 1 ekler ve son çağrı 0 döndürdüğünden değer $adim olur.'}',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 15. Algoritmanın adım sayısı: iç içe döngülerde temel işlem
// ---------------------------------------------------------------------------

const _sayGiris =
    'Aşağıdaki sözde kodda ← atama işlemidir; her “… için” satırı, kendisiyle '
    'eşleşen “döngü sonu” satırına kadar olan satırları tekrarlar (iç içe '
    'döngülerde içteki döngü önce kapanır).';

const _saySorusu =
    'Bu kod çalıştırıldığında say ← say + 1 komutu kaç kez çalışır?';

AdvancedItem _islemSayisi(int a, int b, int c) {
  List<String> ic(String dis, String ic, [String? kosul]) => [
    'say ← 0',
    dis,
    ic,
    kosul ?? 'say ← say + 1',
    'döngü sonu',
    'döngü sonu',
    'yaz say',
  ];
  switch (c) {
    case 0:
      final n = 24 + a, m = 4 + b;
      return sayisalSirali(
        _kod(
          _sayGiris,
          ic('i = 1, 2, …, $n için', 'j = 1, 2, …, $m için'),
          _saySorusu,
        ),
        n * m,
        // Ek hatalar: döngülerden birini bir fazla sayma.
        [n + m, (n - 1) * m, n * (m - 1), n * n, (n + 1) * m, n * (m + 1)],
        'Dıştaki döngü $n kez, içteki döngü her seferinde $m kez çalışır: '
        '$n · $m = ${n * m}.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 1:
      final s = 2 + b % 10, n = 12 + a + (b ~/ 10) * 25;
      final dogru = (n * (n + 1) - (s - 1) * s) ~/ 2;
      // Çıkarılan baştaki terimler: 1, (1 + 2) ya da (1 + 2 + … + s − 1).
      final bas = switch (s) {
        2 => '1',
        3 => '(1 + 2)',
        _ => '(1 + 2 + … + ${s - 1})',
      };
      return sayisalSirali(
        _kod(
          _sayGiris,
          ic('i = $s, ${s + 1}, …, $n için', 'j = 1, 2, …, i için'),
          _saySorusu,
        ),
        dogru,
        // Ek hatalar: s ile değil s + 1 ile başlama, her turu en küçük s
        // değeriyle sayma, tur sayısını bir eksik alma.
        [
          n * (n + 1) ~/ 2,
          (n - s + 1) * n,
          dogru - n,
          dogru + s,
          dogru - s,
          (n - s + 1) * s,
          (n - s) * (n + s) ~/ 2,
        ],
        'İçteki döngü i kez çalışır; toplam $s + ${s + 1} + … + $n olur. Bu '
        'toplam (1 + 2 + … + $n) − $bas = ${n * (n + 1) ~/ 2} − '
        '${(s - 1) * s ~/ 2} = $dogru bulunur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 2:
      final n = 6 + a, m = n + 2 + b;
      final dogru = n * m - n * (n - 1) ~/ 2;
      return sayisalSirali(
        _kod(
          _sayGiris,
          ic('i = 1, 2, …, $n için', 'j = i, i + 1, …, $m için'),
          _saySorusu,
        ),
        dogru,
        // Ek hatalar: iç döngünün m − i kez çalıştığını sanıp her turu en kısa
        // turla sayma, 1 … m toplamını alma.
        [
          n * m,
          n * (m - n + 1),
          dogru + n,
          dogru - n,
          n * (m - n),
          m * (m + 1) ~/ 2,
        ],
        'i değeri için içteki döngü $m − i + 1 kez çalışır: $m + ${m - 1} + … '
        '+ ${m - n + 1} = $dogru.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 3:
      final n = 4 + a % 5, m = 4 + a ~/ 5, p = 4 + b;
      return sayisalSirali(
        _kod(_sayGiris, [
          'say ← 0',
          'i = 1, 2, …, $n için',
          'j = 1, 2, …, $m için',
          'k = 1, 2, …, $p için',
          'say ← say + 1',
          'döngü sonu',
          'döngü sonu',
          'döngü sonu',
          'yaz say',
        ], _saySorusu),
        n * m * p,
        // Ek hatalar: döngülerden birini bir fazla sayma.
        [
          n * m + p,
          n + m + p,
          n * m * (p - 1),
          n * p,
          n * m * (p + 1),
          (n + 1) * m * p,
          n * (m + 1) * p,
        ],
        'Üç döngü iç içe olduğundan çalışma sayıları çarpılır: $n · $m · $p = '
        '${n * m * p}.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 4:
      final s = 1 + a % 5, d = 2 + a ~/ 5, adet = 5 + b % 10;
      final e = s + d * (adet - 1);
      // Yanıt kökteki bir sayıya eşitse iç döngünün sınırı bir artırılır
      // (m değerleri 4, 5, 11, 12 olup a ve b ile birlikte tek kalır).
      var m = 4 + b ~/ 10 * 7;
      if ([s, s + d, s + 2 * d, e, 0, 1].contains(adet * m)) m++;
      return sayisalSirali(
        _kod(
          _sayGiris,
          ic(
            'i = $s, ${s + d}, ${s + 2 * d}, …, $e için',
            'j = 1, 2, …, $m için',
          ),
          _saySorusu,
        ),
        adet * m,
        // Ek hatalar: dış ya da iç döngüyü bir fazla ya da eksik sayma.
        [
          (adet - 1) * m,
          e * m,
          (e - s) * m,
          adet + m,
          (adet + 1) * m,
          adet * (m - 1),
          adet * (m + 1),
        ],
        'Dıştaki döngü ($e − $s) / $d + 1 = $adet kez, içteki döngü her '
        'seferinde $m kez çalışır: $adet · $m = ${adet * m}.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 5:
      final n = 4 + a;
      var m = 20 + 23 * b;
      // Yanıt m sayısına eşit olmasın (m en çok iki artırılır; 23 aralıklı
      // değerler çakışmaz).
      while (n * (m.bitLength - 1) == m) {
        m++;
      }
      final log = m.bitLength - 1;
      return sayisalSirali(
        _kod('$_sayGiris$_divNotu', [
          'say ← 0',
          'i = 1, 2, …, $n için',
          'k ← $m',
          'k > 1 olduğu sürece',
          'k ← k div 2',
          'say ← say + 1',
          'döngü sonu',
          'döngü sonu',
          'yaz say',
        ], _saySorusu),
        n * log,
        // Ek hatalar: ikiye bölme sayısını bir eksik alma, dış döngüyü bir
        // fazla sayma, iç döngünün m kez döndüğünü sanma.
        [
          n * (log + 1),
          n + log,
          n * (m ~/ 2),
          log,
          n * (log - 1),
          (n + 1) * log,
          n * m,
        ],
        '$m sayısı ikiye bölüne bölüne $log adımda 1 olur '
        '(${_us(2, log)} ≤ $m < ${_us(2, log + 1)}). Bu iç döngü dıştaki '
        'döngünün $n turunda da çalışır: $n · $log = ${n * log}.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 6:
      // n ve m tek: çift ve tek toplamlı çiftlerin sayısı farklıdır.
      final n = 5 + 2 * a, m = 5 + 2 * b;
      final dogru = ((n + 1) ~/ 2) * ((m + 1) ~/ 2) + (n ~/ 2) * (m ~/ 2);
      return sayisalSirali(
        _kod(
          '$_sayGiris$_modNotu',
          ic(
            'i = 1, 2, …, $n için',
            'j = 1, 2, …, $m için',
            'eğer (i + j) mod 2 = 0 ise say ← say + 1',
          ),
          _saySorusu,
        ),
        dogru,
        // Ek hatalar: yalnız ikisi de tek ya da ikisi de çift olan çiftleri
        // sayma, yalnız i değerinin tek olmasına bakma.
        [
          n * m,
          n * m - dogru,
          n + m,
          dogru + 1,
          ((n + 1) ~/ 2) * ((m + 1) ~/ 2),
          (n ~/ 2) * (m ~/ 2),
          ((n + 1) ~/ 2) * m,
        ],
        'i + j toplamı, i ile j ikisi de tek ya da ikisi de çift olduğunda '
        'çifttir: ${(n + 1) ~/ 2} · ${(m + 1) ~/ 2} + ${n ~/ 2} · ${m ~/ 2} '
        '= $dogru.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 7:
      final n = 6 + a;
      int say(int m) => _topla([
        for (var i = 1; i <= n; i++)
          if (m - i + 1 > 0) m - i + 1,
      ]);
      // Yanıt kökteki bir sayıya eşitse m değeri 20 artırılır (24 … 43
      // aralığı başka vakada kullanılmaz).
      var m = 4 + b;
      if ([n, m, 0, 1].contains(say(m))) m += 20;
      final dogru = say(m);
      return sayisalSirali(
        _kod(
          _sayGiris,
          ic(
            'i = 1, 2, …, $n için',
            'j = 1, 2, …, $m için',
            'eğer i ≤ j ise say ← say + 1',
          ),
          _saySorusu,
        ),
        dogru,
        // Ek hatalar: eşitsizliği ters okuyup i ≥ j çiftlerini sayma, bir
        // eksik ya da iki fazla sayma.
        [
          n * m,
          n * m - dogru,
          dogru - (n < m ? n : m),
          dogru + 1,
          n * m - dogru + (n < m ? n : m),
          dogru - 1,
          dogru + 2,
        ],
        'Her i için i ≤ j koşulunu sağlayan j değerleri sayılır: '
        '${[for (var i = 1; i <= n && i <= m; i++) '${m - i + 1}'].join(' + ')} '
        '= $dogru.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    case 8:
      final n = 5 + a, k = 2 + b % 5, ek = b ~/ 5;
      final dogru = k * n * (n + 1) ~/ 2 + ek * n;
      final ust = ek == 0 ? '$k · i' : '$k · i + $ek';
      return sayisalSirali(
        _kod(
          _sayGiris,
          ic('i = 1, 2, …, $n için', 'j = 1, 2, …, $ust için'),
          _saySorusu,
        ),
        dogru,
        [
          n * (k * n + ek),
          k * n * (n - 1) ~/ 2 + ek * n,
          if (ek > 0) k * n * (n + 1) ~/ 2,
          n * k + ek,
          // Ek hatalar: dış döngüyü bir fazla sayma, toplamda 2 ile bölmeyi
          // unutma.
          k * (n + 1) * (n + 2) ~/ 2 + ek * (n + 1),
          k * n * (n + 1) + ek * n,
        ],
        'i değeri için içteki döngü $ust kez çalışır. Toplam $k · (1 + 2 + … + '
        '$n)${ek == 0 ? '' : ' + $ek · $n'} = $dogru.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
    default:
      final n = 12 + a, m = 7 + b;
      return sayisalSirali(
        _kod(_sayGiris, [
          'say ← 0',
          'i = 1, 2, …, $n için',
          'say ← say + 1',
          'döngü sonu',
          'j = 1, 2, …, $m için',
          'say ← say + 1',
          'döngü sonu',
          'yaz say',
        ], 'Bu kod çalıştırıldığında yazdırılan değer kaçtır?'),
        n + m,
        [n * m, n + m + 2, n + m - 1, 2 * n + m, n + m - 2, n + m + 1],
        'İki döngü iç içe değil, art ardadır: önce $n, sonra $m kez çalışır. '
        'Yazdırılan değer $n + $m = ${n + m} olur.',
        hedefSira(_no(a, b, c)),
        positive: true,
      );
  }
}

// ---------------------------------------------------------------------------
// Tekrarsız havuz
// ---------------------------------------------------------------------------

/// t = 0, 1, 2, … için [uret] ile aday üretir; null olmayan ve [anahtar]
/// değeri daha önce görülmemiş ilk [adet] adayı toplar. Üretim belirlenimlidir
/// ve havuzdaki her eleman farklı bir soru verisidir.
List<T> _tekil<T>(
  int adet,
  T? Function(int t) uret,
  Object Function(T) anahtar,
) {
  final r = <T>[];
  final gorulen = <Object>{};
  for (var t = 0; r.length < adet; t++) {
    final x = uret(t);
    if (x != null && gorulen.add(anahtar(x))) r.add(x);
  }
  return r;
}

// ---------------------------------------------------------------------------
// 16. Yığın ve kuyruk
// ---------------------------------------------------------------------------

const _yapiIlkesi =
    'Yığın (stack) “son giren ilk çıkar”, kuyruk (queue) “ilk giren ilk çıkar” '
    'ilkesiyle çalışır.';

/// İşlem dizisi: pozitif değer ekle(x), 0 çıkar.
String _islemYaz(List<int> islem) =>
    islem.map((x) => x > 0 ? 'ekle($x)' : 'çıkar').join(', ');

/// İşlemleri uygular: (kalan elemanlar, çıkarılanlar, atlanan çıkarma sayısı).
(List<int>, List<int>, int) _uygula(List<int> islem, {required bool yigin}) {
  final r = <int>[], cikan = <int>[];
  var atlanan = 0;
  for (final x in islem) {
    if (x > 0) {
      r.add(x);
    } else if (r.isEmpty) {
      atlanan++;
    } else {
      cikan.add(yigin ? r.removeLast() : r.removeAt(0));
    }
  }
  return (r, cikan, atlanan);
}

/// [ekleme] ekleme ve [cikarma] çıkarma içeren işlem dizisi; [bosCikarma]
/// doğruysa yapı boşken gelen çıkarma istekleri de bulunabilir.
List<int> _islemUret(
  _Uretec g,
  int ekleme,
  int cikarma, {
  bool bosCikarma = false,
}) {
  final degerler = g.farkli(ekleme, 11, 98);
  final islem = <int>[];
  var e = 0, c = 0, boy = 0;
  while (e < ekleme || c < cikarma) {
    final cik =
        c < cikarma &&
        (e == ekleme || ((bosCikarma || boy > 0) && g.sonraki(3) == 0));
    if (cik) {
      islem.add(0);
      c++;
      if (boy > 0) boy--;
    } else {
      islem.add(degerler[e++]);
      boy++;
    }
  }
  return islem;
}

/// Yığın (ilk 2000) ve kuyruk (sonraki 1500) soruları için işlem dizileri.
final _yiginHavuzu = _tekil<List<int>>(2000, (t) {
  final g = _Uretec(37 * t + 19);
  final islem = _islemUret(g, 5 + g.sonraki(4), 2 + g.sonraki(3));
  final (r, cikan, _) = _uygula(islem, yigin: true);
  final (q, _, _) = _uygula(islem, yigin: false);
  // Son işlem çıkarmadır (son ekleneni yanıt sanma hatası anahtarı vermez);
  // kuyruk gibi düşünmek de farklı sonuç verir.
  if (r.length < 2 || cikan.isEmpty || islem.last != 0) return null;
  if (q.first == r.last) return null;
  return islem;
}, (x) => x.join(','));

final _kuyrukHavuzu = _tekil<List<int>>(1500, (t) {
  final g = _Uretec(41 * t + 7);
  final islem = _islemUret(g, 5 + g.sonraki(4), 2 + g.sonraki(3));
  final (r, cikan, _) = _uygula(islem, yigin: false);
  final (q, _, _) = _uygula(islem, yigin: true);
  if (r.length < 2 || cikan.isEmpty || q.last == r.first) return null;
  return islem;
}, (x) => x.join(','));

final _sayimHavuzu = _tekil<List<int>>(1500, (t) {
  final g = _Uretec(43 * t + 23);
  final ekleme = 5 + g.sonraki(4), cikarma = 3 + g.sonraki(3);
  final islem = _islemUret(g, ekleme, cikarma, bosCikarma: true);
  final (r, cikan, atlanan) = _uygula(islem, yigin: true);
  if (atlanan == 0 ||
      r.length < 2 ||
      cikan.isEmpty ||
      cikan.length == r.length ||
      ekleme - cikarma < 1) {
    return null;
  }
  return islem;
}, (x) => x.join(','));

AdvancedItem _yiginKuyruk(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 7) {
    final yigin = c < 4;
    final islem = yigin
        ? _yiginHavuzu[_sira(j + 500 * c, 2000, 7919)]
        : _kuyrukHavuzu[_sira(j + 500 * (c - 4), 1500, 6007)];
    final (r, cikan, _) = _uygula(islem, yigin: yigin);
    final (q, _, _) = _uygula(islem, yigin: !yigin);
    final eklenen = islem.where((x) => x > 0).toList();
    final dogru = yigin ? r.last : r.first;
    final ad = yigin ? 'yığın' : 'kuyruk';
    return sayisal(
      'Boş bir ${yigin ? 'yığına' : 'kuyruğa'} sırasıyla şu işlemler '
          'uygulanıyor: ${_islemYaz(islem)}. ekle(x) işlemi x değerini '
          '${yigin ? 'yığına' : 'kuyruğa'} koyar, çıkar işlemi '
          '${yigin ? 'yığından' : 'kuyruktan'} bir eleman alır. $_yapiIlkesi '
          'İşlemler bittiğinde '
          '${yigin ? 'yığının en üstündeki' : 'kuyruğun en önündeki'} eleman '
          'kaçtır?',
      dogru,
      [
        yigin ? q.first : q.last,
        yigin ? eklenen.last : eklenen.first,
        yigin ? r.first : r.last,
        cikan.last,
      ],
      'Çıkarılan elemanlar sırasıyla ${cikan.join(', ')} olur. Sonunda '
          '$ad içinde ${r.length} eleman kalır: '
          '${yigin ? 'alttan üste' : 'önden arkaya'} ${r.join(', ')}. '
          '${yigin ? 'En üstteki' : 'En öndeki'} eleman $dogru olur.',
      positive: true,
    );
  }
  final m = j + 500 * (c - 7);
  final islem = _sayimHavuzu[_sira(m, 1500, 4001)];
  final yigin = m.isEven;
  final (r, cikan, atlanan) = _uygula(islem, yigin: yigin);
  final ekleme = islem.where((x) => x > 0).length;
  final cikarma = islem.length - ekleme;
  final yapi = yigin ? 'yığın' : 'kuyruk';
  return sayisal(
    'Boş bir ${yigin ? 'yığına' : 'kuyruğa'} sırasıyla şu işlemler '
        'uygulanıyor: ${_islemYaz(islem)}. ekle(x) işlemi x değerini '
        '${yigin ? 'yığına' : 'kuyruğa'} koyar, çıkar işlemi bir eleman alır; '
        '$yapi boşken gelen çıkar isteği yerine getirilmeden atlanır. '
        '$_yapiIlkesi İşlemler bittiğinde ${yigin ? 'yığında' : 'kuyrukta'} '
        'kaç eleman bulunur?',
    r.length,
    [ekleme - cikarma, ekleme, cikan.length, r.length + 1],
    '$ekleme ekleme yapılır. $cikarma çıkar isteğinden $atlanan tanesi $yapi '
        'boşken geldiği için atlanır, ${cikan.length} tanesi eleman alır. Kalan '
        'eleman sayısı $ekleme − ${cikan.length} = ${r.length} olur.',
    positive: true,
  );
}

// ---------------------------------------------------------------------------
// 17. Karakter dizisi (metin) işlemleri
// ---------------------------------------------------------------------------

/// Yalnız A–Z harflerinden oluşan, I harfi bulunmayan Türkçe sözcükler.
const _kelimeler = [
  'KALEM',
  'MASA',
  'DEFTER',
  'BARDAK',
  'TELEFON',
  'KAMERA',
  'PROGRAM',
  'KODLAMA',
  'KLAVYE',
  'TABLET',
  'PANDA',
  'MERCAN',
  'KARTAL',
  'LAMBA',
  'SEPET',
  'ORMAN',
  'DENEME',
  'ANKARA',
  'ADANA',
  'KONYA',
  'SAMSUN',
  'BURSA',
  'TRABZON',
  'ERZURUM',
  'MALATYA',
  'ELMA',
  'ARMUT',
  'KAVUN',
  'KARPUZ',
  'PORTAKAL',
  'MODEM',
  'SUNUCU',
  'BELLEK',
  'EKRAN',
  'FARE',
  'KABLO',
  'DOMATES',
  'PATATES',
  'TOPRAK',
  'BULUT',
  'ROKET',
  'GEZEGEN',
  'DOKTOR',
  'ASKER',
  'KAPTAN',
  'PALET',
  'MOTOR',
  'VAGON',
  'TREN',
  'MEKTUP',
  'ZARF',
  'MERMER',
  'TAHTA',
  'BAKLAVA',
  'KEBAP',
  'SALATA',
  'MAKARNA',
  'KAHVE',
  'LOKANTA',
  'PAZAR',
  'SOKAK',
  'CADDE',
  'KAPAK',
  'ROMAN',
  'KELEBEK',
  'KAPLAN',
  'ZEBRA',
  'TAVUK',
  'HOROZ',
  'KAZAN',
  'TENCERE',
  'ORKESTRA',
  'NOTA',
  'BANDO',
  'YELKEN',
  'KAYAK',
  'PATEN',
  'FUTBOL',
  'VOLEYBOL',
  'HENTBOL',
  'MEYVE',
  'SEBZE',
  'TOHUM',
  'FASULYE',
  'NOHUT',
  'MERCEK',
  'ATOM',
  'PROTON',
  'ELEKTRON',
  'KUVVET',
  'TERMOMETRE',
  'BALON',
  'KUMPAS',
  'PERDE',
  'SEHPA',
  'KANEPE',
  'YORGAN',
  'MANTAR',
];

const _metinNotu =
    'uzunluk(s), s metnindeki karakter sayısını; say(s, h), s metninde h '
    'karakterinin kaç kez geçtiğini; parca(s, i, k), s metninin i numaralı '
    'karakterinden başlayan k karakterlik bölümünü; ters(s), s metninin '
    'sondan başa yazılışını verir. + işareti iki metni birleştirir ve '
    'karakterler 1 ile başlayarak numaralanır.';

String _parca(String s, int i, int k) => s.substring(i - 1, i - 1 + k);

/// Sayma soruları: (s, t, h, fark mı).
final _saymaHavuzu = _tekil<(String, String, String, bool)>(2000, (t) {
  final g = _Uretec(47 * t + 29);
  final s = _kelimeler[g.sonraki(_kelimeler.length)];
  final u2 = _kelimeler[g.sonraki(_kelimeler.length)];
  if (s == u2) return null;
  final u = s + u2;
  final ortak = [
    for (final h in s.split('').toSet())
      if (u2.contains(h)) h,
  ];
  if (ortak.isEmpty) return null;
  final h = ortak[g.sonraki(ortak.length)];
  final ns = h.allMatches(s).length, nt = h.allMatches(u2).length;
  final say = ns + nt, fark = t.isOdd;
  if (fark && [say, ns, nt].contains(u.length - say)) return null;
  return (s, u2, h, fark);
}, (x) => x);

/// Parça soruları: (s, t ya da boş, i, k, ters çevirme türü: 0 yok, 1 önce
/// ters, 2 sonra ters). [tersli] yanlışsa yalnız 0 türü üretilir.
List<(String, String, int, int, int)> _parcaUret(bool tersli, int tohum) =>
    _tekil<(String, String, int, int, int)>(1500, (t) {
      final g = _Uretec(tohum * t + 31);
      final s = _kelimeler[g.sonraki(_kelimeler.length)];
      final birlesik = g.sonraki(2) == 1;
      final t2 = birlesik ? _kelimeler[g.sonraki(_kelimeler.length)] : '';
      if (s == t2) return null;
      final v = s + t2;
      if (v.length < 6) return null;
      final k = 3 + g.sonraki(3);
      if (v.length - k < 2) return null;
      final i = 2 + g.sonraki(v.length - k - 1);
      final tur = tersli ? 1 + g.sonraki(2) : 0;
      final p = _parca(v, i, k);
      // Parça tersinden okununca değişmeli; ters çevirme ile parça alma
      // sırasını karıştırmak anahtarı vermemeli.
      if (_palindrom(p) || _ters(p) == _parca(_ters(v), i, k)) return null;
      if (_parcaSecenekleri(v, i, k, tur).$2.length < 3) return null;
      return (s, t2, i, k, tur);
    }, (x) => x);

final _parcaHavuzu = _parcaUret(false, 53);
final _tersParcaHavuzu = _parcaUret(true, 59);

/// Parça sorusunun doğru yanıtı ve tipik hatalardan gelen çeldiricileri.
(String, Set<String>) _parcaSecenekleri(String v, int i, int k, int tur) {
  final p = _parca(v, i, k);
  final kayik = _parca(v, i + 1, k);
  final tv = _ters(v);
  if (tur == 0) {
    return (
      p,
      {
        kayik,
        _parca(v, i, k - 1),
        if (i < k) v.substring(i - 1, k),
        if (i + k <= v.length) _parca(v, i, k + 1),
        _ters(p),
      }..remove(p),
    );
  }
  if (tur == 1) {
    final d = _parca(tv, i, k);
    return (d, {_ters(p), _parca(tv, i + 1, k), p, _ters(d)}..remove(d));
  }
  final d = _ters(p);
  return (
    d,
    {_parca(tv, i, k), _ters(kayik), p, _ters(_parca(v, i, k - 1))}..remove(d),
  );
}

AdvancedItem _metin(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 4) {
    final (s, t, h, fark) = _saymaHavuzu[_sira(j + 500 * c, 2000, 7919)];
    final u = s + t;
    final ns = h.allMatches(s).length, nt = h.allMatches(t).length;
    final say = ns + nt;
    final dogru = fark ? u.length - say : say;
    // Ek hatalar: yalnız bir metindeki sayıyı kullanma, bir geçişi gözden
    // kaçırma, tümleyeni yazma (uzunluk − sayı ya da sayı).
    return _sinirliSayisal(
      _kod('Aşağıdaki sözde kodda ← atama işlemidir. $_metinNotu', [
        's ← "$s"',
        't ← "$t"',
        'u ← s + t',
        fark ? 'yaz uzunluk(u) − say(u, "$h")' : 'yaz say(u, "$h")',
      ], _yazSorusu),
      dogru,
      fark
          ? [
              say,
              u.length,
              u.length - ns,
              dogru + 1,
              u.length - nt,
              s.length - ns,
              t.length - nt,
              dogru - 1,
            ]
          : [ns, nt, u.length, say + 1, say - 1, u.length - say, s.length],
      'u = "$u" olur ve ${u.length} karakter içerir. "$h" karakteri s '
      'metninde $ns, t metninde $nt kez, toplam $say kez geçer. '
      '${fark ? 'Yazdırılan değer ${u.length} − $say = $dogru olur.' : 'Yazdırılan değer $say olur.'}',
      _no(a, b, c),
      enAz: 1,
      enCok: u.length,
    );
  }
  final ilk = c < 7;
  final (s, t, i, k, tur) = ilk
      ? _parcaHavuzu[_sira(j + 500 * (c - 4), 1500, 6007)]
      : _tersParcaHavuzu[_sira(j + 500 * (c - 7), 1500, 4001)];
  final v = s + t;
  final (dogru, aday) = _parcaSecenekleri(v, i, k, tur);
  final ad = t.isEmpty ? 's' : 'u';
  final ifade = switch (tur) {
    0 => 'parca($ad, $i, $k)',
    1 => 'parca(ters($ad), $i, $k)',
    _ => 'ters(parca($ad, $i, $k))',
  };
  final aciklama = switch (tur) {
    0 =>
      '$i numaralı karakter "${v[i - 1]}" harfidir; buradan başlayan $k '
          'karakter "$dogru" olur.',
    1 =>
      'Önce ters çevrilir: "${_ters(v)}". Bu metnin $i numaralı karakterinden '
          'başlayan $k karakter "$dogru" olur.',
    _ =>
      'Önce parça alınır: "${_parca(v, i, k)}". Bu parça ters çevrilince '
          '"$dogru" olur.',
  };
  return secenekli(
    _kod('Aşağıdaki sözde kodda ← atama işlemidir. $_metinNotu', [
      's ← "$s"',
      if (t.isNotEmpty) ...['t ← "$t"', 'u ← s + t'],
      'yaz $ifade',
    ], 'Bu kod çalıştırıldığında ekrana ne yazdırılır?'),
    dogru,
    aday,
    '${t.isEmpty ? '' : 'u = "$v" olur. '}$aciklama',
  );
}

// ---------------------------------------------------------------------------
// 18. Basamak algoritmaları: mod 10 ve div 10
// ---------------------------------------------------------------------------

const _basamakGiris =
    'Aşağıdaki sözde kodda ← atama işlemidir; “olduğu sürece” döngüsü koşul '
    'doğru oldukça “döngü sonu” satırına kadar tekrar eder. a mod 10, a '
    'sayısının 10 ile bölümünden kalanı (son rakamı); a div 10, bu bölmedeki '
    'tam sayı bölümü verir.';

List<int> _rakamlar(int n) => '$n'.split('').map(int.parse).toList();

/// [basamak] basamaklı, son rakamı sıfır olmayan ve [t] ile birebir
/// belirlenen sayı: önce (basamak − 1) basamaklı bir q, sonra son rakam.
int _basamakSayisi(int basamak, int t, int adim) {
  final alt = _kuvvet(10, basamak - 2);
  final q = alt + (t * adim) % (9 * alt);
  return 10 * q + 1 + t % 9;
}

/// Rakam sayma soruları: (sayı, çift rakam mı, eşik).
final _rakamHavuzu = _tekil<(int, bool, int)>(1500, (t) {
  final g = _Uretec(61 * t + 37);
  final basamak = 6 + g.sonraki(3);
  final r = [1 + g.sonraki(9), for (var x = 1; x < basamak; x++) g.sonraki(10)];
  final cift = t.isOdd, k = 3 + g.sonraki(4);
  final dogru = cift
      ? r.where((x) => x.isEven).length
      : r.where((x) => x > k).length;
  if (dogru < 2 || 2 * dogru == basamak || dogru == basamak) return null;
  // Çift rakam sorusunda kökte 2 sayısı geçer; yanıt 2 olmasın.
  if (cift && dogru == 2) return null;
  if (!cift && (dogru == k || !r.contains(k))) return null;
  return (int.parse(r.join()), cift, cift ? 0 : k);
}, (x) => x);

AdvancedItem _basamak(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 4) {
    final m = j + 500 * c;
    final n = _basamakSayisi(4 + m % 3, m ~/ 3, 7919);
    final r = _rakamlar(n);
    final t = _topla(r);
    return sayisal(
      _kod(_basamakGiris, [
        'n ← $n',
        't ← 0',
        'n > 0 olduğu sürece',
        't ← t + n mod 10',
        'n ← n div 10',
        'döngü sonu',
        'yaz t',
      ], _yazSorusu),
      t,
      [t - r.first, t - r.last, r.length, t + r.last],
      'Her adımda son rakam t değerine eklenip sayıdan atılır. Rakamlar '
      'toplamı ${r.reversed.join(' + ')} = $t olur.',
      positive: true,
    );
  }
  if (c < 7) {
    final m = j + 500 * (c - 4);
    var n = _basamakSayisi(4 + m % 3, m ~/ 3, 6007);
    // Tersinden okunuşu aynı olan sayıda yalnız son rakam değiştirilir.
    if (_palindrom('$n')) n = n - n % 10 + n % 10 % 9 + 1;
    final ters = int.parse(_ters('$n'));
    final r = _rakamlar(n);
    return sayisal(
      _kod(_basamakGiris, [
        'n ← $n',
        'r ← 0',
        'n > 0 olduğu sürece',
        'r ← r · 10 + n mod 10',
        'n ← n div 10',
        'döngü sonu',
        'yaz r',
      ], _yazSorusu),
      ters,
      [ters ~/ 10, n, ters * 10, _topla(r)],
      'Son rakamlar sırayla r sayısının sağına eklenir: r değeri '
      '${[for (var k = 1; k <= r.length; k++) _ters('$n').substring(0, k)].join(', ')} '
      'olur. Yazdırılan değer $ters bulunur.',
      positive: true,
    );
  }
  final (n, cift, k) = _rakamHavuzu[_sira(j + 500 * (c - 7), 1500, 4999)];
  final r = _rakamlar(n);
  final dogru = cift
      ? r.where((x) => x.isEven).length
      : r.where((x) => x > k).length;
  return sayisal(
    _kod(
      '$_basamakGiris${cift ? ' a mod 2, a sayısının 2 ile bölümünden kalanı verir.' : ''}',
      [
        'n ← $n',
        's ← 0',
        'n > 0 olduğu sürece',
        cift
            ? 'eğer (n mod 10) mod 2 = 0 ise s ← s + 1'
            : 'eğer n mod 10 > $k ise s ← s + 1',
        'n ← n div 10',
        'döngü sonu',
        'yaz s',
      ],
      _yazSorusu,
    ),
    dogru,
    [
      r.length - dogru,
      r.length,
      if (!cift) r.where((x) => x >= k).length,
      dogru + 1,
    ],
    'Döngü $n sayısının ${r.length} rakamını sondan başa doğru tek tek '
    'inceler. ${cift ? 'Çift rakamlar' : '$k sayısından büyük rakamlar'} '
    '${r.reversed.where((x) => cift ? x.isEven : x > k).join(', ')} '
    'olduğundan s = $dogru olur.',
    positive: true,
  );
}

// ---------------------------------------------------------------------------
// 19. Sezar şifreleme
// ---------------------------------------------------------------------------

const _ingilizAlfabe = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _turkAlfabe = 'ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ';

/// Sezar sözcükleri: _kelimeler ile ı harfini (büyük yazımı I) içeren
/// sözcükler.
const _sezarKelimeleri = [
  ..._kelimeler,
  'KAPI',
  'HALI',
  'ALTIN',
  'BALIK',
  'DONANIM',
  'YAZILIM',
  'KARINCA',
  'ASLAN',
  'KUZU',
  'KOYUN',
  'BAYRAK',
  'DAVUL',
  'ZURNA',
  'KUPA',
  'MADALYA',
  'SANDALYE',
  'KAYNAK',
  'TARLA',
  'BAHAR',
  'YAPRAK',
  'ODUN',
  'KOVAN',
  'BALKON',
  'KASA',
];

/// Kaydırma miktarları: 13 dışarıda (ileri ve geri kaydırma aynı sonucu
/// verir).
const _kaydirmalar = [
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
  11,
  12,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
];

String _kaydir(String s, int k, [String alfabe = _ingilizAlfabe]) {
  final n = alfabe.length;
  return [
    for (final h in s.split('')) alfabe[((alfabe.indexOf(h) + k) % n + n) % n],
  ].join();
}

bool _turkce(String s) => s.split('').every(_turkAlfabe.contains);

/// Şifreleme ve çözme vakaları (sözcük sırası, kaydırma): Türk alfabesiyle
/// kaydırma hatası farklı sonuç verir.
final _sezarHavuzu = [
  for (var k = 0; k < _kaydirmalar.length; k++)
    for (var w = 0; w < _sezarKelimeleri.length; w++)
      if (_kaydir(_sezarKelimeleri[w], _kaydirmalar[k], _turkAlfabe) !=
          _kaydir(_sezarKelimeleri[w], _kaydirmalar[k]))
        (w, _kaydirmalar[k]),
];

/// Kaydırma bulma vakaları: ilk harflerin Türk alfabesindeki uzaklığı
/// kaydırma miktarına eşit değildir.
final _kaydirmaHavuzu = [
  for (final (w, k) in _sezarHavuzu)
    if (_turkUzaklik(_sezarKelimeleri[w], k) != k && k != 1 && k != 25) (w, k),
];

/// İlk harften şifreli ilk harfe Türk alfabesinde ileri uzaklık (şifreli harf
/// bu alfabede yoksa 0).
int _turkUzaklik(String duz, int k) {
  final son = _kaydir(duz[0], k);
  if (!_turkAlfabe.contains(son)) return 0;
  return (_turkAlfabe.indexOf(son) - _turkAlfabe.indexOf(duz[0]) + 29) % 29;
}

const _sezarKurali =
    'Sezar şifrelemesinde metindeki her harf, alfabede belirli bir sayı '
    '(kaydırma miktarı) kadar ileri kaydırılır. Bu soruda 26 harfli İngiliz '
    'alfabesi (A, B, C, …, Z) kullanılır; Z harfinden sonra yeniden A harfine '
    'dönülür.';

/// Harf tekrarı düzeni: "MERCEK" → 0,1,2,3,1,4. Sezar şifrelemesi bu düzeni
/// korur.
String _harfDuzeni(String s) {
  final ilk = <String, int>{};
  return [for (final h in s.split('')) ilk.putIfAbsent(h, () => ilk.length)]
      .join(',');
}

/// Her Sezar sözcüğü için aynı uzunlukta ve aynı harf tekrarı düzeninde olan
/// öteki sözcükler (liste sırasıyla).
final _sezarEsleri = () {
  final duzen = [for (final s in _sezarKelimeleri) _harfDuzeni(s)];
  return [
    for (var w = 0; w < _sezarKelimeleri.length; w++)
      [
        for (var v = 0; v < _sezarKelimeleri.length; v++)
          if (v != w && duzen[v] == duzen[w]) _sezarKelimeleri[v],
      ],
  ];
}();

/// Şifre çözme vakaları: sözcüğün aynı uzunlukta ve aynı harf tekrarı
/// düzeninde en az üç komşusu vardır. Çeldiriciler bu komşulardır; böylece
/// dört seçenek de anlamlı sözcüktür ve ne anlam, ne uzunluk, ne de harf
/// tekrarı doğru seçeneği şifre çözülmeden ele verir.
final _cozmeHavuzu = [
  for (final (w, k) in _sezarHavuzu)
    if (_sezarEsleri[w].length >= 3) (w, k),
];

/// Şifre çözme sorusu. Şifreli metni geri yerine ileri kaydırma (tipik yön
/// hatası) sonucunun ilk harfiyle başlayan komşu sözcük varsa öne alınır;
/// kalan komşular vakaya göre döndürülerek sıralanır.
AdvancedItem _sezarCoz(int m) {
  final (w, k) = _cozmeHavuzu[_sira(m, _cozmeHavuzu.length, 6007)];
  final duz = _sezarKelimeleri[w];
  final sifreli = _kaydir(duz, k);
  final yonHatasi = _kaydir(sifreli[0], k);
  final esler = _sezarEsleri[w];
  final d = m % esler.length;
  final donmus = [...esler.sublist(d), ...esler.sublist(0, d)];
  return secenekli(
    '$_sezarKurali Bir sözcük, kaydırma miktarı $k olan Sezar şifrelemesiyle '
        'şifrelenmiş ve "$sifreli" metni elde edilmiştir. Şifrelenen sözcük '
        'hangisidir?',
    duz,
    [
      ...donmus.where((s) => s[0] == yonHatasi),
      ...donmus.where((s) => s[0] != yonHatasi),
    ],
    'Şifre çözmek için her harf $k harf geri kaydırılır: '
        '${[for (var t = 0; t < duz.length; t++) '${sifreli[t]} → ${duz[t]}'].join(', ')}. '
        'Sözcük "$duz" olur; diğer seçenekler $k harf ileri kaydırıldığında '
        '"$sifreli" metnini vermez.',
  );
}

AdvancedItem _sezar(int a, int b, int c) {
  final j = a + 25 * b;
  if (c >= 4 && c < 7) return _sezarCoz(j + 500 * (c - 4));
  if (c < 4) {
    final (w, k) = _sezarHavuzu[_sira(j + 500 * c, _sezarHavuzu.length, 7919)];
    final duz = _sezarKelimeleri[w];
    final sifreli = _kaydir(duz, k);
    // 26 ile bölünen kaydırma metni değiştirmez (seçenek kökteki sözcüğün
    // kendisi olurdu); bu adaylar atlanır.
    String? kay(int m) => m % 26 == 0 ? null : _kaydir(duz, m);
    // Türk alfabesiyle kaydırma tipik bir hatadır; ama sonuç Ç, Ğ, İ, Ö, Ş ya
    // da Ü içerirse 26 harfli alfabede yazılamayacağından bakar bakmaz
    // elenir. Bu durumda yalnız İngiliz alfabesindeki adaylar kullanılır.
    final turkHata = _turkce(duz) ? _kaydir(duz, k, _turkAlfabe) : '';
    final aday = <String>{
      ?kay(-k),
      if (turkHata.isNotEmpty &&
          turkHata.split('').every(_ingilizAlfabe.contains))
        turkHata,
      ?kay(k + 1),
      ?kay(k - 1),
      ?kay(k + 2),
      ?kay(k - 2),
    }..remove(sifreli);
    return secenekli(
      '$_sezarKurali Kaydırma miktarı $k olduğuna göre "$duz" sözcüğünün '
          'şifrelenmiş hâli nedir?',
      sifreli,
      aday,
      'Her harf $k harf ileri kaydırılır: '
          '${[for (var t = 0; t < duz.length; t++) '${duz[t]} → ${sifreli[t]}'].join(', ')}. '
          'Şifreli metin "$sifreli" olur.',
    );
  }
  final (w, k) =
      _kaydirmaHavuzu[_sira(j + 500 * (c - 7), _kaydirmaHavuzu.length, 4999)];
  final duz = _sezarKelimeleri[w];
  final sifreli = _kaydir(duz, k);
  final ilk = duz[0], son = sifreli[0];
  final turk = _turkUzaklik(duz, k);
  return sayisal(
    '$_sezarKurali "$duz" sözcüğü Sezar şifrelemesiyle "$sifreli" biçimine '
        'getirilmiştir. Kullanılan kaydırma miktarı kaçtır? (Kaydırma miktarı '
        '1 ile 25 arasındadır.)',
    k,
    [26 - k, if (turk >= 1) turk, k + 1, k - 1],
    'İlk harf $ilk alfabede ${_ingilizAlfabe.indexOf(ilk) + 1} numaralı, '
        '$son ise ${_ingilizAlfabe.indexOf(son) + 1} numaralı harftir. '
        '$ilk harfinden ileri doğru sayıldığında $son harfine $k adımda '
        'ulaşılır; diğer harfler de $k harf kaydırılmıştır.',
    positive: true,
  );
}

// ---------------------------------------------------------------------------
// 20. Eşlik biti ile hata denetimi
// ---------------------------------------------------------------------------

int _birler(String s) => '1'.allMatches(s).length;

/// Cümle başı için ilk harfi büyütür (yalnız "çift" ve "tek" için).
String _buyukHarf(String s) => s == 'çift' ? 'Çift' : 'Tek';

String _bitler(int x, int w) => _ikilik(x).padLeft(w, '0');

const _eslikTanimi =
    'Çift eşlikte gönderilen dizideki 1 sayısı çift, tek eşlikte tek olacak '
    'biçimde eşlik biti 0 ya da 1 seçilir.';

/// Alıcı soruları: (eşlik türü çift mi, diziler, hatalı dizinin sırası).
final _alimHavuzu = _tekil<(bool, List<String>, int)>(1500, (t) {
  final g = _Uretec(67 * t + 41);
  final cift = t.isEven;
  final diziler = <String>[];
  final hatali = g.sonraki(4);
  while (diziler.length < 4) {
    final veri = _bitler(1 + g.sonraki(126), 7);
    final p = (_birler(veri).isOdd == cift) ? 1 : 0;
    var d = '$veri$p';
    if (diziler.length == hatali) {
      final konum = g.sonraki(8);
      d = d.replaceRange(konum, konum + 1, d[konum] == '1' ? '0' : '1');
    }
    if (diziler.contains(d) || d == '00000000' || d == '11111111') continue;
    diziler.add(d);
  }
  return (cift, diziler, hatali);
}, (x) => '${x.$1}${x.$2.join()}');

/// Paket sayma soruları: (eşlik türü çift mi, paketler).
final _paketHavuzu = _tekil<(bool, List<String>)>(2000, (t) {
  final g = _Uretec(71 * t + 43);
  final cift = t.isOdd, adet = 5 + g.sonraki(3);
  final paketler = <String>[];
  while (paketler.length < adet) {
    final veri = _bitler(1 + g.sonraki(126), 7);
    final p = (_birler(veri).isOdd == cift) ? 1 : 0;
    var d = '$veri$p';
    if (g.sonraki(5) < 2) {
      final konum = g.sonraki(8);
      d = d.replaceRange(konum, konum + 1, d[konum] == '1' ? '0' : '1');
    }
    if (paketler.contains(d)) continue;
    paketler.add(d);
  }
  final yanlis = paketler.where((d) => _birler(d).isEven != cift).length;
  if (yanlis < 2 || yanlis > adet - 2 || 2 * yanlis == adet) return null;
  return (cift, paketler);
}, (x) => '${x.$1}${x.$2.join()}');

AdvancedItem _eslik(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 3) {
    // 6, 7 ya da 8 bitlik sabit olmayan veri; çift ya da tek eşlik; eşlik
    // biti verinin sonuna ya da başına eklenir.
    final yer = _sira(j + 500 * c, 442 * 4, 7919);
    final basta = yer % 2 == 1, cift = yer ~/ 2 % 2 == 0;
    final v = yer ~/ 4;
    final (w, deger) = v < 62
        ? (6, 1 + v)
        : (v < 188 ? (7, 1 + v - 62) : (8, 1 + v - 188));
    final veri = _bitler(deger, w);
    final birSayisi = _birler(veri);
    final p = (birSayisi.isOdd == cift) ? 1 : 0;
    String ekle(int bit, bool bas) => bas ? '$bit$veri' : '$veri$bit';
    final tur = cift ? 'çift' : 'tek';
    return secenekli(
      '$w bitlik $veri verisi $tur eşlik kullanılarak gönderilecektir. Eşlik '
          'biti verinin ${basta ? 'başına (en sola)' : 'sonuna (en sağa)'} '
          'eklenir. $_eslikTanimi Gönderilen ${w + 1} bitlik dizi hangisidir?',
      ekle(p, basta),
      [ekle(1 - p, basta), ekle(p, !basta), ekle(1 - p, !basta)],
      '$veri verisinde $birSayisi tane 1 vardır. ${_buyukHarf(tur)} eşlikte toplam 1 '
          'sayısının $tur olması için eşlik biti $p seçilir ve '
          '${basta ? 'başa' : 'sona'} eklenince ${ekle(p, basta)} elde edilir.',
    );
  }
  if (c < 6) {
    final (cift, diziler, hatali) =
        _alimHavuzu[_sira(j + 500 * (c - 3), 1500, 6007)];
    final tur = cift ? 'çift' : 'tek';
    return secenekli(
      '${_buyukHarf(tur)} eşlik kullanılan bir iletimde her dizi 7 veri biti ve en sağdaki '
          'eşlik bitinden oluşur. $_eslikTanimi Alıcıya ${diziler.join(', ')} '
          'dizileri ulaşmıştır. Bu dizilerden hangisinde iletim hatası olduğu '
          'kesin olarak söylenebilir?',
      diziler[hatali],
      [
        for (var t = 0; t < 4; t++)
          if (t != hatali) diziler[t],
      ],
      '${diziler.map((d) => '$d: ${_birler(d)} tane 1').join('; ')}. ${_buyukHarf(tur)} '
          'eşlikte 1 sayısı ${cift ? 'tek' : 'çift'} olan dizi hatalıdır: '
          '${diziler[hatali]}.',
    );
  }
  final (cift, paketler) = _paketHavuzu[_sira(j + 500 * (c - 6), 2000, 4999)];
  final tur = cift ? 'çift' : 'tek';
  final hatali = [
    for (final d in paketler)
      if (_birler(d).isEven != cift) d,
  ];
  final say = hatali.length;
  // Ek hatalar: eşlik türünü karıştırıp doğru paketleri sayma, bir paketi
  // gözden kaçırma ya da fazla sayma.
  return _sinirliSayisal(
    '${_buyukHarf(tur)} eşlik kullanılan bir iletimde her paket 7 veri biti ve en sağdaki '
        'eşlik bitinden oluşur. $_eslikTanimi Alıcıya ${paketler.join(', ')} '
        'paketleri ulaşmıştır. Alıcı eşlik denetimiyle kaç pakette hata '
        'saptar?',
    say,
    [
      paketler.length - say,
      say + 1,
      say - 1,
      paketler.length,
      say + 2,
      say - 2,
    ],
    'Her paketteki 1 sayısı sayılır; $tur eşlikte 1 sayısı '
        '${cift ? 'tek' : 'çift'} olan paketler hatalıdır: ${hatali.join(', ')}. '
        'Hata saptanan paket sayısı $say olur.',
    _no(a, b, c),
    enAz: 1,
    enCok: paketler.length,
  );
}

final lmBilisim = <AdvancedFamily>[
  _bs(
    'ikilik',
    'İkilik ve onluk taban arasında dönüşüm',
    Difficulty.medium,
    BloomLevel.uygulama,
    _ikilikDonusum,
  ),
  _bs(
    'onaltilik',
    'Onaltılık ve sekizlik tabanlarla dönüşüm',
    Difficulty.medium,
    BloomLevel.uygulama,
    _onaltilikDonusum,
    shortAnswer: false,
  ),
  _bs(
    'ikilik_islem',
    'İkilik tabanda toplama, çıkarma ve kaydırma',
    Difficulty.medium,
    BloomLevel.uygulama,
    _ikilikIslem,
  ),
  _bs(
    'veri_birim',
    'Veri birimleri, dönüşümler ve indirme süresi',
    Difficulty.easy,
    BloomLevel.uygulama,
    _veriBirim,
  ),
  _bs(
    'dosya_boyut',
    'Sıkıştırılmamış görüntü ve ses dosyasının boyutu',
    Difficulty.medium,
    BloomLevel.analiz,
    _dosyaBoyut,
  ),
  _bs(
    'rgb',
    'RGB renk kodları ve onaltılık bileşen değerleri',
    Difficulty.medium,
    BloomLevel.uygulama,
    _rgb,
  ),
  _bs(
    'mantik_kapisi',
    'Mantık kapılarından oluşan devrenin çıkışı',
    Difficulty.medium,
    BloomLevel.analiz,
    _mantikKapisi,
    shortAnswer: false,
  ),
  _bs(
    'dogruluk_tablosu',
    'Boole ifadesinin doğruluk tablosu ve değeri',
    Difficulty.hard,
    BloomLevel.analiz,
    _dogrulukTablosu,
    shortAnswer: false,
  ),
  _bs(
    'dongu',
    'Döngü izleme: değişkenlerin son değeri ve tekrar sayısı',
    Difficulty.medium,
    BloomLevel.analiz,
    _dongu,
  ),
  _bs(
    'kosul',
    'İç içe eğer-değilse yapılarında çıktıyı bulma',
    Difficulty.medium,
    BloomLevel.uygulama,
    _kosul,
  ),
  _bs(
    'dizi',
    'Dizi işlemleri: indisle erişim, en büyük eleman, toplam',
    Difficulty.medium,
    BloomLevel.uygulama,
    _dizi,
  ),
  _bs(
    'siralama',
    'Kabarcık ve seçerek sıralama adımları',
    Difficulty.medium,
    BloomLevel.analiz,
    _siralama,
    shortAnswer: false,
  ),
  _bs(
    'ikili_arama',
    'İkili arama: karşılaştırma sayısı ve bakılan elemanlar',
    Difficulty.medium,
    BloomLevel.analiz,
    _ikiliArama,
    shortAnswer: false,
  ),
  _bs(
    'ozyineleme',
    'Özyinelemeli fonksiyonların değeri ve çağrı sayısı',
    Difficulty.hard,
    BloomLevel.analiz,
    _ozyineleme,
  ),
  _bs(
    'islem_sayisi',
    'İç içe döngülerde temel işlemin çalışma sayısı',
    Difficulty.medium,
    BloomLevel.analiz,
    _islemSayisi,
  ),
  _bs(
    'yigin_kuyruk',
    'Yığın ve kuyruk işlemlerinden sonraki durum',
    Difficulty.easy,
    BloomLevel.anlama,
    _yiginKuyruk,
  ),
  _bs(
    'metin',
    'Karakter dizisi işlemleri: uzunluk, parça, ters çevirme',
    Difficulty.medium,
    BloomLevel.uygulama,
    _metin,
  ),
  _bs(
    'basamak_algoritma',
    'Basamak algoritmaları: mod 10 ve div 10 ile rakamlar',
    Difficulty.medium,
    BloomLevel.uygulama,
    _basamak,
  ),
  _bs(
    'sezar',
    'Sezar şifreleme: kaydırmayla şifreleme ve çözme',
    Difficulty.easy,
    BloomLevel.uygulama,
    _sezar,
    shortAnswer: false,
  ),
  _bs(
    'eslik',
    'Eşlik biti ile hata denetimi',
    Difficulty.medium,
    BloomLevel.anlama,
    _eslik,
    shortAnswer: false,
  ),
];
