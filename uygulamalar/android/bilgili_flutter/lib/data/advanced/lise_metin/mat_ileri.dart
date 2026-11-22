// AYT Matematik metin aileleri: fonksiyon, polinom, ikinci derece, logaritma,
// dizi, trigonometri, limit, türev, integral ve toplam sembolü.
// Her aile (a, b, c) koordinatlarından 5.000 ayrı soru kökü üretir.
import 'denge.dart';
import 'ortak.dart';

// ---------------------------------------------------------------------------
// Yazım yardımcıları
// ---------------------------------------------------------------------------

const _ustRakam = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];
const _altRakam = ['₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉'];

/// Üst simge: `_ust(12)` → `¹²`.
String _ust(int n) =>
    [for (final r in '$n'.codeUnits) _ustRakam[r - 48]].join();

/// Alt simge: `_alt(12)` → `₁₂`.
String _alt(int n) =>
    [for (final r in '$n'.codeUnits) _altRakam[r - 48]].join();

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

/// Sıfırı atlayan tam sayı aralığı: `_sifirsizAralik(-2, 3)` → −2, −1, 1, 2, 3.
List<int> _sifirsizAralik(int bas, int son) => [
  for (var x = bas; x <= son; x++)
    if (x != 0) x,
];

/// [adaylar] içinden [uygun] koşulunu sağlayanların [i] numaralısı. Tipik bir
/// yanlış yolun da doğru yanıtı verdiği yozlaşmış değerleri ayıklamak için
/// kullanılır; sıra korunduğundan farklı [i] farklı değer verir.
T _uygun<T>(Iterable<T> adaylar, int i, bool Function(T) uygun) =>
    adaylar.where(uygun).elementAt(i);

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
  // Tam sayı yanıtlarda komşu tam sayılar, kesirli yanıtlarda önce ters
  // çevrilmiş kesir denenir.
  final tam = n % d == 0;
  final havuz = [
    ...adaylar,
    (-n, d),
    if (n != 0 && !tam) (d, n),
    (n + d, d),
    (n - d, d),
    (n + 2 * d, d),
    (n - 2 * d, d),
    (n + 3 * d, d),
    (n + 4 * d, d),
    (n + 5 * d, d),
  ].where((x) => x.$2 != 0 && (!pozitif || x.$1 * x.$2 > 0));
  return secenekli(kok, _q(n, d), havuz.map((x) => _q(x.$1, x.$2)), aciklama);
}

/// Seçeneklerin biçiminden ipucu çıkmasın diye vakanın hedef sırası
/// (`hedefSira`); [tuz] ikinci bağımsız seçim içindir.
int _hs(int a, int b, int c, [int tuz = 0]) =>
    hedefSira(a + 25 * b + 500 * c, tuz);

/// [_tam] gibi; ama anahtardan küçük çeldirici sayısı [sira] olur. Adaylar
/// öncelik sırasıyla verilir (iki yandan da tipik hatalar); bir yan eksik
/// kalırsa anahtara yakın komşu değerler kullanılır.
AdvancedItem _tamS(
  String kok,
  int yanit,
  Iterable<int> adaylar,
  String aciklama,
  int sira, {
  String birim = '',
  bool pozitif = false,
}) {
  final adim = yanit.abs() >= 200 ? 10 : (yanit.abs() >= 40 ? 5 : 1);
  final havuz = [
    ...adaylar,
    for (var k = 1; k <= 6; k++) ...[yanit + k * adim, yanit - k * adim],
  ].where((x) => !pozitif || x > 0);
  final yazim = birimli(_n(yanit), birim);
  return AdvancedItem(
    kok,
    yazim,
    siraliCeldiriciler(yanit, yazim, [
      for (final x in havuz) (x, birimli(_n(x), birim)),
    ], sira),
    aciklama,
  );
}

/// [_kes] gibi; ama anahtardan küçük çeldirici sayısı [sira] olur. Son çare
/// komşular tam sayı yanıtta ±1, ±2 …; kesirli yanıtta önce payı ve paydası
/// birlikte, sonra yalnız biri değişen kesirlerdir. [komsuPozitif] yalnız
/// komşuları pozitif tutar ([pozitif] tüm adayları).
AdvancedItem _kesS(
  String kok,
  int n,
  int d,
  Iterable<(int, int)> adaylar,
  String aciklama,
  int sira, {
  bool pozitif = false,
  bool komsuPozitif = false,
}) {
  bool arti((int, int) x) => x.$1 * x.$2 > 0;
  final tam = n % d == 0;
  final komsu = [
    if (tam)
      for (var k = 1; k <= 6; k++) ...[(n + k * d, d), (n - k * d, d)]
    else ...[
      (n + 1, d + 1), (n - 1, d - 1), (n + 1, d), (n - 1, d), (n, d + 1), //
      (n, d - 1), (n + 2, d), (n - 2, d), (n + 3, d), (n - 3, d),
    ],
  ].where((x) => !komsuPozitif || arti(x));
  final havuz = [
    ...adaylar,
    ...komsu,
  ].where((x) => x.$2 != 0 && (!pozitif || arti(x)));
  final yazim = _q(n, d);
  return AdvancedItem(
    kok,
    yazim,
    siraliCeldiriciler(n / d, yazim, [
      for (final x in havuz) (x.$1 / x.$2, _q(x.$1, x.$2)),
    ], sira),
    aciklama,
  );
}

/// Anahtarla (n/d) birlikte dengeli bir takım kuran aday üçlülerden (ör. iki
/// hata boyutunun bileşimi: A, B, A + B) anahtardan küçük öge sayısı [sira]
/// olan, değerleri birbirinden ve anahtardan farklı ilkini verir; uygun üçlü
/// yoksa boş liste. Sonuç [_kesS] ya da [_tamS] adaylarının başına konur.
List<(int, int)> _uclu(
  int n,
  int d,
  Iterable<List<(int, int)>> ucluler,
  int sira, {
  bool pozitif = false,
}) {
  final k = n / d;
  for (final u in ucluler) {
    if (u.any((x) => x.$2 == 0 || (pozitif && x.$1 * x.$2 <= 0))) continue;
    final v = [k, for (final x in u) x.$1 / x.$2];
    var farkli = true;
    for (var i = 0; i < 4; i++) {
      for (var j = i + 1; j < 4; j++) {
        if ((v[i] - v[j]).abs() < 1e-9) farkli = false;
      }
    }
    if (farkli && v.skip(1).where((x) => x < k).length == sira) return u;
  }
  return const [];
}

/// [adaylar] içinden üçlü seçkiler; öncelik sırası korunur (sözlük sırası).
/// [kosul] verilirse yalnız onu sağlayan üçlüler gelir.
Iterable<List<T>> _seckiler<T>(
  List<T> adaylar, [
  bool Function(List<T>)? kosul,
]) sync* {
  for (var i = 0; i < adaylar.length; i++) {
    for (var j = i + 1; j < adaylar.length; j++) {
      for (var k = j + 1; k < adaylar.length; k++) {
        final u = [adaylar[i], adaylar[j], adaylar[k]];
        if (kosul == null || kosul(u)) yield u;
      }
    }
  }
}

/// Tam sayı yanıtlar için [_uclu].
List<int> _ucluTam(
  int yanit,
  Iterable<List<int>> ucluler,
  int sira, {
  bool pozitif = false,
}) => [
  for (final x in _uclu(
    yanit,
    1,
    [
      for (final u in ucluler) [for (final x in u) (x, 1)],
    ],
    sira,
    pozitif: pozitif,
  ))
    x.$1,
];

/// Üçlüde anahtarla aynı işaretli (negatif ya da negatif olmayan) çeldirici
/// sayısı 1 ya da 3 mü? Böylece ne anahtar ne de bir çeldirici işaretiyle
/// tek kalır.
bool _isaretDengeli(int yanit, List<int> u) {
  final ayni = u.where((x) => (x < 0) == (yanit < 0)).length;
  return ayni == 1 || ayni == 3;
}

/// Üçlü, anahtarla (n/d) birlikte işaretçe (negatif / negatif olmayan) ve
/// biçimce (tam sayı / kesir) dengeli mi? Her özellikte anahtarla aynı olan
/// çeldirici sayısı 1 ya da 3 olmalı: ne anahtar ne de bir çeldirici tek
/// kalır.
/// [tumBicim] doğruysa üç çeldirici de anahtarla aynı biçimde olmalıdır.
bool _dengeli(int n, int d, List<(int, int)> u, {bool tumBicim = false}) {
  if (u.any((x) => x.$2 == 0)) return false;
  bool neg((int, int) x) => x.$1 != 0 && (x.$1 < 0) != (x.$2 < 0);
  bool tam((int, int) x) => x.$1 % x.$2 == 0;
  final isaret = u.where((x) => neg(x) == neg((n, d))).length;
  final bicim = u.where((x) => tam(x) == tam((n, d))).length;
  return (isaret == 1 || isaret == 3) &&
      (bicim == 3 || (!tumBicim && bicim == 1));
}

/// Seçeneğin sözcükleri (ipucu taramasındaki gibi): işaretsiz pay ve payda.
Set<String> _sozler((int, int) x) =>
    _q(x.$1, x.$2).replaceAll('−', '').split('/').toSet();

/// Sözcük benzerliğinde (Jaccard toplamı) anahtar öne çıkmıyor mu? Anahtar
/// en benzer seçenekse en az üç seçenek bu puanı paylaşmalıdır.
bool _sozcukDengeli(List<Set<String>> s) {
  final puan = [
    for (var a = 0; a < 4; a++)
      [
        for (var b = 0; b < 4; b++)
          if (b != a) s[a].intersection(s[b]).length / s[a].union(s[b]).length,
      ].fold<double>(0, (t, x) => t + x),
  ];
  final enb = puan.fold<double>(puan[0], (t, x) => x > t ? x : t);
  if (puan[0] < enb - 1e-9) return true;
  return puan.where((x) => (x - enb).abs() < 1e-9).length >= 3;
}

/// Üçlü adaylarını öncelik geçişleriyle verir: önce biçimce tümüyle aynı,
/// işaretçe, sözcükçe ve uzunlukça dengeli; sonra [_dengeli] ile sözcük ve
/// uzunluk dengesi; sonra bunların bir kısmı; en sonda koşulsuz. Her geçişte önce [tasarim]
/// üçlüleri (bileşik tasarımlar), sonra [adaylar] seçkileri gelir.
Iterable<List<(int, int)>> _gecisler(
  int n,
  int d,
  List<List<(int, int)>> tasarim,
  List<(int, int)> adaylar,
) sync* {
  final onbellek = <(int, int), Set<String>>{};
  Set<String> soz((int, int) x) => onbellek.putIfAbsent(x, () => _sozler(x));
  bool sozcuk(List<(int, int)> u) =>
      u.every((x) => x.$2 != 0) &&
      _sozcukDengeli([soz((n, d)), for (final x in u) soz(x)]);
  // Anahtar tek başına en uzun ya da en kısa seçenek olmasın: onunla aynı
  // uzunlukta en az iki çeldirici ya da hem daha uzun hem daha kısa birer
  // çeldirici bulunsun.
  final boy = _q(n, d).length;
  bool uzun(List<(int, int)> u) {
    final l = [for (final x in u) _q(x.$1, x.$2).length];
    return l.where((x) => x == boy).length >= 2 ||
        (l.any((x) => x > boy) && l.any((x) => x < boy));
  }

  for (final kosul in <bool Function(List<(int, int)>)>[
    (u) => _dengeli(n, d, u, tumBicim: true) && sozcuk(u) && uzun(u),
    (u) => _dengeli(n, d, u) && sozcuk(u) && uzun(u),
    (u) => sozcuk(u) && uzun(u),
    (u) => _dengeli(n, d, u) && sozcuk(u),
    (u) => _dengeli(n, d, u),
    sozcuk,
    (u) => true,
  ]) {
    yield* tasarim.where(kosul);
    yield* _seckiler(adaylar, kosul);
  }
}

/// Üçlüde değeri tam sayı olan bir kesir var mı?
bool _tamVar(List<(int, int)> u) => u.any((x) => x.$2 != 0 && x.$1 % x.$2 == 0);

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

// ---------------------------------------------------------------------------
// Tablolar
// ---------------------------------------------------------------------------

/// (a, c, t): a·c = t² olan katsayı çiftleri; çakışık kök soruları için.
const _tamKareCiftleri = [
  (1, 1, 1),
  (1, 4, 2),
  (1, 9, 3),
  (1, 16, 4),
  (1, 25, 5),
  (2, 2, 2),
  (2, 8, 4),
  (2, 18, 6),
  (3, 3, 3),
  (3, 12, 6),
  (4, 1, 2),
  (4, 4, 4),
  (4, 9, 6),
  (9, 1, 3),
  (9, 4, 6),
  (8, 2, 4),
  (5, 5, 5),
  (1, 36, 6),
  (1, 49, 7),
  (3, 27, 9),
];

/// (taban, üs): log_t(t^m) = m.
const _logTanim = [
  (2, 2),
  (2, 3),
  (2, 4),
  (2, 5),
  (2, 6),
  (2, 7),
  (2, 8),
  (2, 9),
  (2, 10),
  (3, 2),
  (3, 3),
  (3, 4),
  (3, 5),
  (3, 6),
  (4, 2),
  (4, 3),
  (4, 4),
  (4, 5),
  (5, 2),
  (5, 3),
  (5, 4),
  (6, 2),
  (6, 3),
  (7, 2),
  (7, 3),
];

/// (taban, k, y): log_t(t^k·y) − log_t(y) = k.
const _logBolum = [
  (2, 3, 3),
  (2, 2, 5),
  (2, 4, 3),
  (2, 3, 5),
  (2, 5, 3),
  (2, 2, 7),
  (2, 4, 5),
  (2, 3, 7),
  (3, 2, 2),
  (3, 3, 2),
  (3, 2, 5),
  (3, 3, 4),
  (3, 2, 4),
  (3, 4, 2),
  (3, 2, 7),
  (5, 2, 2),
  (5, 2, 3),
  (5, 3, 2),
  (5, 2, 4),
  (5, 3, 4),
  (6, 2, 2),
  (6, 2, 5),
  (7, 2, 2),
  (7, 2, 3),
  (4, 2, 3),
];

/// (u, w, k): log_{uw}(u^k) + log_{uw}(w^k) = k.
const _logCarpim = [
  (2, 3, 2),
  (2, 3, 3),
  (2, 7, 2),
  (3, 4, 2),
  (3, 5, 2),
  (2, 9, 2),
  (4, 5, 2),
  (3, 7, 2),
  (3, 4, 3),
  (3, 5, 3),
  (2, 3, 4),
  (2, 7, 3),
  (2, 11, 2),
  (3, 8, 2),
  (4, 5, 3),
  (5, 6, 2),
  (2, 13, 2),
  (4, 7, 2),
  (2, 9, 3),
  (3, 10, 2),
  (2, 15, 2),
  (3, 11, 2),
  (5, 7, 2),
  (3, 13, 2),
  (2, 17, 2),
];

/// (r, p, q): log_{r^p}(r^q) = q/p, tam sayı olmayan değerler.
const _logKesir = [
  (2, 2, 3),
  (2, 2, 5),
  (2, 2, 1),
  (2, 3, 2),
  (2, 3, 4),
  (2, 3, 5),
  (2, 3, 1),
  (3, 2, 3),
  (3, 2, 1),
  (3, 2, 5),
  (3, 3, 2),
  (3, 3, 1),
  (3, 3, 4),
  (2, 4, 3),
  (2, 4, 1),
  (2, 4, 5),
  (2, 4, 2),
  (2, 5, 2),
  (2, 5, 3),
  (2, 5, 4),
  (5, 2, 3),
  (5, 2, 1),
  (5, 3, 2),
  (3, 4, 3),
  (2, 6, 4),
];

/// (taban, ara taban, k): log_t(s)·log_s(t^k) = k.
const _logZincir = [
  (2, 3, 3),
  (2, 3, 4),
  (2, 5, 2),
  (2, 5, 3),
  (3, 2, 2),
  (3, 2, 3),
  (3, 5, 2),
  (3, 5, 4),
  (5, 2, 2),
  (5, 3, 3),
  (2, 7, 5),
  (2, 7, 2),
  (3, 7, 3),
  (7, 2, 2),
  (5, 7, 2),
  (2, 3, 5),
  (2, 5, 6),
  (3, 4, 2),
  (5, 4, 3),
  (7, 3, 2),
  (2, 6, 4),
  (3, 11, 2),
  (6, 5, 2),
  (2, 11, 3),
  (3, 2, 4),
];

/// (taban, n): log_t(1/t^n) = −n.
const _logTers = [
  (2, 1),
  (2, 2),
  (2, 3),
  (2, 4),
  (2, 5),
  (2, 6),
  (3, 1),
  (3, 2),
  (3, 3),
  (3, 4),
  (4, 1),
  (4, 2),
  (4, 3),
  (5, 1),
  (5, 2),
  (5, 3),
  (6, 1),
  (6, 2),
  (7, 1),
  (7, 2),
];

/// (taban, üs): üstel denklemin sağ tarafı t^m ya da 1/t^m.
const _ustelTaban = [
  (2, 2),
  (2, 3),
  (2, 4),
  (2, 5),
  (2, 6),
  (2, 7),
  (2, 8),
  (3, 2),
  (3, 3),
  (3, 4),
  (3, 5),
  (4, 2),
  (4, 3),
  (4, 4),
  (5, 2),
  (5, 3),
  (5, 4),
  (6, 2),
  (6, 3),
  (7, 2),
  (7, 3),
  (8, 2),
  (8, 3),
  (9, 2),
  (9, 3),
];

/// (r, i, j): r^i ve r^j tabanlı üstel denklemler, i ≠ j.
const _ustelCift = [
  (2, 1, 2),
  (2, 1, 3),
  (2, 1, 4),
  (2, 2, 3),
  (2, 2, 5),
  (2, 3, 4),
  (2, 3, 5),
  (2, 4, 5),
  (2, 2, 4),
  (2, 1, 5),
  (3, 1, 2),
  (3, 1, 3),
  (3, 1, 4),
  (3, 2, 3),
  (3, 2, 4),
  (3, 3, 4),
  (3, 2, 5),
  (5, 1, 2),
  (5, 1, 3),
  (5, 2, 3),
  (5, 2, 4),
  (7, 1, 2),
  (7, 1, 3),
  (7, 2, 3),
  (6, 1, 2),
];

/// (taban, m): log_t(…) = m denklemleri. (2, 2) yoktur: 2² = 2·2 olduğundan
/// üs almak yerine çarpan da aynı sonucu bulurdu.
const _logDenklemTaban = [
  (10, 2),
  (2, 3),
  (2, 4),
  (2, 5),
  (2, 6),
  (2, 7),
  (3, 2),
  (3, 3),
  (3, 4),
  (4, 2),
  (4, 3),
  (5, 2),
  (5, 3),
  (6, 2),
  (7, 2),
  (8, 2),
  (9, 2),
  (11, 2),
  (2, 1),
  (3, 1),
  (5, 1),
  (7, 1),
  (6, 1),
  (4, 1),
  (11, 1),
];

/// (taban, i, p): p·t^(x + i) + q·t^x biçimli toplamlar.
const _ustelToplam = [
  (2, 1, 1),
  (2, 1, 2),
  (2, 1, 3),
  (2, 1, 4),
  (2, 1, 5),
  (2, 2, 1),
  (2, 2, 2),
  (2, 2, 3),
  (2, 2, 4),
  (2, 2, 5),
  (2, 3, 1),
  (2, 3, 2),
  (2, 3, 3),
  (2, 3, 4),
  (2, 4, 1),
  (2, 4, 2),
  (3, 1, 1),
  (3, 1, 2),
  (3, 1, 3),
  (3, 1, 4),
  (3, 1, 5),
  (3, 2, 1),
  (3, 2, 2),
  (3, 2, 3),
  (4, 1, 1),
];

/// (ortak çarpan, sıra): geometrik dizide n. terim, ilk terim ve toplam.
/// (2, 3) yoktur: 2² = 2·2 olduğundan r^(n − 1) yerine r·(n − 1) alan da aynı
/// terimi bulurdu.
const _geoOranSira = [
  (2, 10),
  (2, 4),
  (2, 5),
  (2, 6),
  (2, 7),
  (2, 8),
  (2, 9),
  (3, 3),
  (3, 4),
  (3, 5),
  (3, 6),
  (4, 3),
  (4, 4),
  (4, 5),
  (5, 3),
  (5, 4),
  (6, 3),
  (6, 4),
  (7, 3),
  (8, 3),
  (9, 3),
  (11, 3),
  (12, 3),
  (10, 3),
  (10, 4),
];

/// (ortak çarpan, sıra farkı): iki terimden ortak çarpan bulma.
const _geoOran1 = [
  (2, 2),
  (2, 3),
  (2, 4),
  (2, 5),
  (3, 2),
  (3, 3),
  (3, 4),
  (4, 2),
  (4, 3),
  (5, 2),
];

/// (ortak çarpan, sıra farkı): iki terimden üçüncü terimi bulma.
const _geoOran3 = [
  (2, 2),
  (2, 3),
  (2, 4),
  (3, 2),
  (3, 3),
  (4, 2),
  (5, 2),
  (2, 5),
  (4, 3),
  (6, 2),
];

/// Bölüm yazımı; sadeleşiyorsa sade biçimi de verir: `_oranYaz(8, 2)` →
/// `8/2 = 4`, `_oranYaz(1, 4)` → `1/4`.
String _oranYaz(int n, int d) {
  final sade = _q(n, d);
  return sade == '$n/$d' ? sade : '$n/$d = $sade';
}

/// Üstel ifade: `_ustlu(2, 'x + 3')` → `2^(x + 3)`, `_ustlu(2, 'x')` → `2^x`.
String _ustlu(int taban, String us) => us == 'x' ? '$taban^x' : '$taban^($us)';

/// Sayısal kuvvet: `_kuvvet(2, -5)` → `2^(−5)`, `_kuvvet(3, 4)` → `3⁴`.
String _kuvvet(int taban, int us) =>
    us < 0 ? '$taban^(−${-us})' : '$taban${_ust(us)}';

/// Artan dereceli yazım; katsayılar sabit terimden başlar.
/// `_polArtan([3, -4, 2])` → `3 − 4x + 2x²`.
String _polArtan(List<int> k, [String v = 'x']) {
  final sb = StringBuffer();
  for (var d = 0; d < k.length; d++) {
    final c = k[d];
    if (c == 0) continue;
    final m = c.abs();
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

// Trigonometri -------------------------------------------------------------

/// sin değerleri: açı → (pay, payda, kök içi); değer = pay·√kök/payda.
const _sinTablo = {
  0: (0, 1, 1),
  30: (1, 2, 1),
  45: (1, 2, 2),
  60: (1, 2, 3),
  90: (1, 1, 1),
  120: (1, 2, 3),
  135: (1, 2, 2),
  150: (1, 2, 1),
  180: (0, 1, 1),
  210: (-1, 2, 1),
  225: (-1, 2, 2),
  240: (-1, 2, 3),
  270: (-1, 1, 1),
  300: (-1, 2, 3),
  315: (-1, 2, 2),
  330: (-1, 2, 1),
};

/// tan değerleri (tanımsız açılar tabloda yoktur).
const _tanTablo = {
  0: (0, 1, 1),
  30: (1, 3, 3),
  45: (1, 1, 1),
  60: (1, 1, 3),
  120: (-1, 1, 3),
  135: (-1, 1, 1),
  150: (-1, 3, 3),
  180: (0, 1, 1),
  210: (1, 3, 3),
  225: (1, 1, 1),
  240: (1, 1, 3),
  300: (-1, 1, 3),
  315: (-1, 1, 1),
  330: (-1, 3, 3),
};

/// Özel açının trigonometrik değeri: (pay, payda, kök içi).
(int, int, int) _trig(String f, int derece) {
  final t = derece % 360;
  return switch (f) {
    'sin' => _sinTablo[t]!,
    'cos' => _sinTablo[(t + 90) % 360]!,
    'tan' => _tanTablo[t]!,
    _ => _tanTablo[(450 - t) % 360]!, // cot θ = tan(90° − θ)
  };
}

String _trigYaz((String, int) t) =>
    t.$2 < 0 ? '${t.$1}(−${-t.$2}°)' : '${t.$1} ${t.$2}°';

String _trigDeger((int, int, int) v) {
  final (n, d, k) = v;
  if (k == 1) return _q(n, d);
  final m = n.abs();
  return '${n < 0 ? '−' : ''}${m == 1 ? '' : m}√$k${d == 1 ? '' : '/$d'}';
}

/// İndirgeme adımları: `sin(−150°) = sin 210° = −sin 30° = −1/2`.
String _indirge((String, int) t) {
  final f = t.$1, esas = t.$2 % 360;
  final v = _trig(f, t.$2);
  final adimlar = [_trigYaz(t)];
  if (esas != t.$2) adimlar.add('$f $esas°');
  if (esas % 90 != 0) {
    final dar = esas < 90
        ? esas
        : esas < 180
        ? 180 - esas
        : esas < 270
        ? esas - 180
        : 360 - esas;
    if (dar != esas) adimlar.add('${v.$1 < 0 ? '−' : ''}$f $dar°');
  }
  adimlar.add(_trigDeger(v));
  return adimlar.join(' = ');
}

/// Değeri ±1/2 ya da ±1 olan terimler.
const _trigA = [
  ('sin', 30),
  ('sin', 150),
  ('sin', 210),
  ('sin', 330),
  ('sin', 270),
  ('cos', 60),
  ('cos', 120),
  ('cos', 240),
  ('cos', 300),
  ('cos', 180),
  ('tan', 45),
  ('tan', 135),
  ('tan', 225),
  ('tan', 315),
  ('cot', 135),
  ('cot', 225),
  ('cot', 315),
  ('sin', 390),
  ('sin', 510),
  ('cos', 420),
  ('cos', 480),
  ('tan', 405),
  ('sin', 570),
  ('cos', 600),
  ('tan', 495),
];

/// Negatif ya da 360° üstü açılı, değeri ±1/2 ya da ±1 olan terimler.
const _trigB = [
  ('sin', -30),
  ('sin', -150),
  ('sin', -210),
  ('sin', -330),
  ('cos', -60),
  ('cos', -120),
  ('cos', -240),
  ('cos', -300),
  ('tan', -45),
  ('tan', -135),
  ('tan', -225),
  ('tan', -315),
  ('cot', -45),
  ('cot', -135),
  ('sin', 750),
  ('cos', 780),
  ('sin', 690),
  ('cos', 660),
  ('tan', 585),
  ('tan', 675),
];

/// Değeri √3 içeren terimler.
const _trigR = [
  ('sin', 60),
  ('sin', 120),
  ('sin', 240),
  ('sin', 300),
  ('cos', 30),
  ('cos', 150),
  ('cos', 210),
  ('cos', 330),
  ('tan', 30),
  ('tan', 60),
  ('tan', 120),
  ('tan', 150),
  ('tan', 210),
  ('tan', 240),
  ('tan', 300),
  ('tan', 330),
  ('cot', 30),
  ('cot', 60),
  ('cot', 120),
  ('cot', 150),
  ('cot', 210),
  ('cot', 240),
  ('cot', 300),
  ('cot', 330),
  ('sin', 420),
];

/// Negatif ya da 360° üstü açılı, değeri √3 içeren terimler.
const _trigS = [
  ('sin', -60),
  ('sin', -120),
  ('cos', -30),
  ('cos', -150),
  ('tan', -30),
  ('tan', -60),
  ('tan', -120),
  ('tan', -150),
  ('cot', -30),
  ('cot', -60),
  ('sin', 480),
  ('cos', 390),
  ('cos', 510),
  ('tan', 390),
  ('tan', 420),
  ('tan', 480),
  ('tan', 510),
  ('cot', 390),
  ('cot', 420),
  ('sin', 600),
];

// Radyan -------------------------------------------------------------------

/// π li sade yazım: `_pili(10, 12)` → `5π/6`, `_pili(2, 2)` → `π`.
String _pili(int p, int q) {
  final g = p.gcd(q), x = p ~/ g, y = q ~/ g;
  return '${x == 1 ? '' : x}π${y == 1 ? '' : '/$y'}';
}

/// (p, q): pπ/q radyanlık üçgen açıları; derece karşılıkları tam sayıdır.
const _ucgenRadyan = [
  (1, 3),
  (1, 4),
  (1, 5),
  (1, 6),
  (1, 9),
  (1, 10),
  (1, 12),
  (2, 5),
  (2, 9),
  (3, 10),
  (5, 12),
  (5, 18),
  (7, 18),
  (4, 9),
  (1, 2),
  (5, 9),
  (7, 12),
  (1, 15),
  (1, 18),
  (7, 36),
];

/// (p, q): pπ/q radyanlık merkez açılar. π/3 yoktur: π = 3 alındığında yay
/// uzunluğu yarıçapa eşit çıkar ve yanıt kökte verilen sayı olur.
const _yayAcilari = [
  (1, 6),
  (1, 4),
  (17, 12),
  (1, 2),
  (2, 3),
  (3, 4),
  (5, 6),
  (1, 1),
  (7, 6),
  (5, 4),
  (4, 3),
  (3, 2),
  (5, 3),
  (7, 4),
  (11, 6),
  (1, 12),
  (5, 12),
  (7, 12),
  (11, 12),
  (13, 12),
];

/// (q, m): esas ölçüsü mπ/q olan açılar; m ile q aralarında asaldır.
const _radyanEsas = [
  (3, 1),
  (3, 2),
  (3, 4),
  (3, 5),
  (4, 1),
  (4, 3),
  (4, 5),
  (4, 7),
  (6, 1),
  (6, 5),
  (6, 7),
  (6, 11),
  (5, 1),
  (5, 3),
  (5, 4),
  (5, 7),
  (5, 9),
  (2, 1),
  (2, 3),
  (9, 2),
  (9, 5),
  (9, 8),
  (9, 13),
  (12, 5),
  (12, 7),
];

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
      final f = [
        const [2, 3, -2, 4, -3][a % 5],
        const [-3, -1, 1, 2, 4][a ~/ 5],
      ];
      final g = [
        1,
        const [-2, -1, 1, 2, 3][b % 5],
        const [-1, 1, 2, 3][b ~/ 5],
      ];
      final fog = c.isEven;
      // Bileşke sırasını karıştıran, değerleri çarpan ya da toplayan, iç
      // değerde duran yolların da doğru yanıtı verdiği noktalar atlanır.
      final k = _uygun(const [-2, -1, 1, 2, 3, -3, 4, -4, 5], c ~/ 2, (x) {
        final fx = _deg(f, x), gx = _deg(g, x);
        final fg = _deg(f, gx), gf = _deg(g, fx);
        final yanit = fog ? fg : gf;
        return fg != gf &&
            yanit != fx * gx &&
            yanit != fx + gx &&
            yanit != (fog ? gx : fx);
      });
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
        // f(t) = t olan sabit noktada f⁻¹(k) = f(k) = k olur; bu değer atlanır.
        final t = _uygun(_sifirsizAralik(-9, 12), b, (x) => p * x + q != x);
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
      // p = d olsaydı f kendi tersine eşit olur, f⁻¹(k) yerine f(k) hesaplayan
      // da doğru yanıtı bulurdu; tablolar ortak değer taşımaz. Aynı nedenle
      // sabit noktayı (f(k) = k) veren u = p + j − d değeri atlanır.
      final p = const [2, 3, 4, 5, -2][a % 5];
      final d = const [1, -1, -3, -4, 6][a ~/ 5];
      final j = const [-2, -1, 1, 2, 3][v];
      final u = _uygun(_sifirsizAralik(-10, 11), b, (x) => x != p + j - d);
      final q = j * u - p * d, k = p + j, t = d + u;
      String pay(String h) => q == 0 ? _pol([p, 0], h) : '(${_pol([p, q], h)})';
      return _kes(
        'x ≠ ${_n(d)} için tanımlı f(x) = ${pay('x')}/(${_pol([1, -d])}) '
            'fonksiyonunun tersi f⁻¹ olduğuna göre f⁻¹(${_n(k)}) değeri kaçtır?',
        t,
        1,
        [if (k != d) (p * k + q, k - d), (k * d - q, k - p), (-t, 1)],
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
        // r ≥ 2 ve s ≥ 3 iken üsleri çarpmak yerine toplayan yol (p + q + r + s)
        // hiçbir zaman doğru dereceyi vermez.
        final p = 2 + a % 5, q = 2 + a ~/ 5, r = 2 + b % 5, s = 3 + b ~/ 5;
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
      final w = _sifirsiz(b, 9);
      if (c % 3 == 0) {
        final m = const [1, 2, 3, -2][v];
        final x0 = 1 + m;
        // x yerine 1, m ya da 1 − m yazan yolların da aynı toplamı verdiği,
        // toplamın sabit terime eşit çıktığı katsayılar atlanır.
        final u = _uygun(_sifirsizAralik(-12, 17), a, (x) {
          final y = _deg([1, x, w], x0);
          return y != _deg([1, x, w], 1) &&
              y != _deg([1, x, w], m) &&
              y != _deg([1, x, w], 1 - m) &&
              y != w;
        });
        final sag = [1, u, w];
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
      // Verilen ifadenin sabit terimini yanıt sanan ya da x yerine −x₀, 1 yazan
      // yolların da doğru sonucu verdiği katsayılar atlanır.
      final u = _uygun(_sifirsizAralik(-12, 17), a, (x) {
        final y = _deg([1, x, w], x0);
        return y != w && y != _deg([1, x, w], -x0) && y != _deg([1, x, w], 1);
      });
      final sag = [1, u, w];
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
        final c2 = const [-3, -2, 1, 2, 4][a % 5];
        // x = −k yazan (işaret hatası) ya da sabit terimi kalan sanan yolların
        // da doğru kalanı verdiği katsayılar atlanır.
        final c1 = _uygun(const [-4, -1, 2, 3, 5, -5, 6, -2, 7, -6], a ~/ 5, (
          x,
        ) {
          final y = _deg([1, c2, x, 0], k);
          return y != 0 && y != _deg([1, c2, x, 0], -k);
        });
        final pol = [1, c2, c1, w];
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
      final x0 = k + m;
      // Ötelemeyi atlayan (P(k)), ters uygulayan (P(k − m)) ya da P(m) alan
      // yolların da doğru kalanı verdiği, kalanın sabit terime eşit çıktığı
      // katsayılar atlanır.
      final u = _uygun(_sifirsizAralik(-12, 17), a, (x) {
        final y = _deg([1, x, 0], x0);
        return y != 0 &&
            y != _deg([1, x, 0], k) &&
            y != _deg([1, x, 0], k - m) &&
            y != _deg([1, x, 0], m);
      });
      final pol = [1, u, w];
      final kalan = _deg(pol, x0);
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
      // Kökler gerçek kalsın: diskriminant pozitif değilse sabit terim
      // negatif bir değere taşınır. Ters çevrilmiş oranın (1/x₁ + 1/x₂) ya da
      // toplam ile çarpımı karıştıran yolun (x₁²·x₂ + x₁·x₂²) da doğru yanıtı
      // verdiği sabit terimler atlanır.
      final kc = _uygun(
        [
          for (final x in _sifirsizAralik(-14, 8))
            x > 0 && kb * kb <= 4 * bas * x ? -(14 + x) : x,
        ],
        b,
        (x) => switch (e) {
          1 => x.abs() != kb.abs(),
          3 => -kb * x != (x - kb) * bas && -kb * x != (kb + x) * bas,
          _ => true,
        },
      );
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

  // 6 · Diskriminant: c % 3 → Δ değeri, çakışık kök ya da kök varlığı.
  _aile(
    'diskriminant',
    'Diskriminant ve gerçek köklerin varlığı',
    Difficulty.medium,
    BloomLevel.analiz,
    (a, b, c) {
      final v = c ~/ 3, hs = _hs(a, b, c);
      // Δ > 0 sorusunda b = ±1 iken 4·a·c yerine a·c alan yol da aynı tam
      // sayıyı verir; bu katsayılar atlanır.
      final kb = c % 3 == 2 && v == 0
          ? _uygun(_sifirsizAralik(-12, 15), a, (x) => x.abs() != 1)
          : _sifirsiz(a, 12);
      final b2 = kb * kb;
      if (c % 3 == 0) {
        final bas = const [1, 2, 3, -1][v];
        final kc = _sifirsiz(b, 9);
        final delta = b2 - 4 * bas * kc;
        return _tamS(
          '${_pol([bas, kb, kc])} = 0 denkleminin diskriminantı kaçtır?',
          delta,
          // İşaret, 4'ü unutma, b'nin karesini almama, a'yı unutma; negatif
          // b'nin karesini negatif alma, 4 yerine 2 ya da 8, 4ac − b² yazma
          // (anahtarın ters işaretlisi olduğundan en sonda).
          [
            b2 + 4 * bas * kc,
            b2 - bas * kc,
            kb - 4 * bas * kc,
            b2 - 4 * kc,
            if (kb < 0) -b2 - 4 * bas * kc,
            b2 - 2 * bas * kc,
            b2 - 8 * bas * kc,
            4 * bas * kc - b2,
          ],
          'Δ = b² − 4ac formülünde a = ${_n(bas)}, b = ${_n(kb)}, '
              'c = ${_n(kc)} alınır: Δ = ${_p(kb)}² − 4·${_p(bas)}·${_p(kc)} = '
              '${_n(delta)}.',
          hs,
        );
      }
      if (c % 3 == 1) {
        final (bas, sabit, t) = _tamKareCiftleri[b];
        final p = kb;
        final denklem =
            '${_pol([bas, 0, 0])} + (${_pol([1, -p], 'm')})x + $sabit = 0';
        final giris =
            'Çakışık kök için Δ = 0 olmalıdır: (${_pol([1, -p], 'm')})² − '
            '4·$bas·$sabit = 0, yani (${_pol([1, -p], 'm')})² = ${4 * t * t}. '
            'Buradan ${_pol([1, -p], 'm')} = ${2 * t} veya '
            '${_pol([1, -p], 'm')} = −${2 * t}; m = ${_n(p + 2 * t)} veya '
            'm = ${_n(p - 2 * t)} bulunur.';
        // Kök alırken 4'ün kökünü almama (±t) ya da 4t alma, p'yi unutma,
        // p'nin işaretini çevirme, öteki kökü verme.
        return switch (v) {
          0 => _tamS(
            '$denklem denkleminin çakışık iki kökü olduğuna göre m sayısının '
                'alabileceği en büyük değer kaçtır?',
            p + 2 * t,
            [p + t, p - 2 * t, 2 * t, p + 4 * t, -p + 2 * t, p - t, p - 4 * t],
            '$giris En büyük değer ${_n(p + 2 * t)} olur.',
            hs,
          ),
          1 => _tamS(
            '$denklem denkleminin çakışık iki kökü olduğuna göre m sayısının '
                'alabileceği en küçük değer kaçtır?',
            p - 2 * t,
            [p - t, p + 2 * t, -2 * t, p - 4 * t, -p - 2 * t, p + t, p + 4 * t],
            '$giris En küçük değer ${_n(p - 2 * t)} olur.',
            hs,
          ),
          // Kökler yerine 4'ün kökünü almadan ya da 4t ile çarpma, toplamı
          // verme, p² ya da 4t² terimini unutma, işaret.
          _ => _tamS(
            '$denklem denkleminin çakışık iki kökü olduğuna göre m sayısının '
                'alabileceği değerlerin çarpımı kaçtır?',
            p * p - 4 * t * t,
            [
              p * p - t * t,
              p * p + 4 * t * t,
              2 * p,
              p * p - 16 * t * t,
              -4 * t * t,
              p * p,
              4 * t * t - p * p,
              -2 * p,
            ],
            '$giris Çarpımları ${_p(p + 2 * t)}·${_p(p - 2 * t)} = '
                '${_n(p * p - 4 * t * t)} olur.',
            hs,
          ),
        };
      }
      final q = _sifirsiz(b, 9);
      final denklem = '${_pol([1, kb, 0])} + ${_pol([1, -q], 'm')} = 0';
      final sinir = _q(b2 + 4 * q, 4);
      final taban = q + b2 ~/ 4; // ⌊q + b²/4⌋
      final delta =
          'Δ = ${_p(kb)}² − 4·(${_pol([1, -q], 'm')}) = ${_n(b2 + 4 * q)} − 4m '
          'olur.';
      // 4'ü yalnız m ile çarpma: Δ = b² + q − 4m sanılır.
      final dagit = b2 + q;
      int alt4(int x) => (x / 4).floor();
      switch (v) {
        case 0:
          final yanit = kb.isEven ? taban - 1 : taban;
          return _tamS(
            '$denklem denkleminin birbirinden farklı iki gerçek kökü olduğuna '
                'göre m sayısının alabileceği en büyük tam sayı değeri kaçtır?',
            yanit,
            // Sınırı dâhil etme, q'nun işareti, 4'ü unutma, eşitsizliği ters
            // çevirme, bir eksik, 4'e bölmeyi unutma, 4'ü dağıtmama.
            [
              yanit + 1,
              yanit - 2 * q,
              b2 + q - 1,
              taban + 1,
              yanit - 1,
              b2 + 4 * q - 1,
              alt4(dagit - 1),
            ],
            '$delta İki farklı gerçek kök için Δ > 0, yani m < $sinir '
                'olmalıdır. Bu koşulu sağlayan en büyük tam sayı ${_n(yanit)} olur.',
            hs,
          );
        case 1:
          final yanit = taban + 1;
          return _tamS(
            '$denklem denkleminin gerçek kökü olmadığına göre m sayısının '
                'alabileceği en küçük tam sayı değeri kaçtır?',
            yanit,
            // Sınırı dâhil etme, q'nun işareti, 4'ü unutma, eşitsizliği ters
            // çevirme, bir fazla, 4'e bölmeyi unutma, 4'ü dağıtmama.
            [
              yanit - 1,
              yanit - 2 * q,
              b2 + q + 1,
              kb.isEven ? taban - 1 : taban,
              yanit + 1,
              b2 + 4 * q + 1,
              alt4(dagit) + 1,
            ],
            '$delta Gerçek kök olmaması için Δ < 0, yani m > $sinir '
                'olmalıdır. Bu koşulu sağlayan en küçük tam sayı ${_n(yanit)} olur.',
            hs,
          );
        default:
          return _tamS(
            '$denklem denkleminin en az bir gerçek kökü olduğuna göre m '
                'sayısının alabileceği en büyük tam sayı değeri kaçtır?',
            taban,
            // Bir fazla ya da eksik, q'nun işareti, 4'ü unutma, 4'e bölmeyi
            // unutma, 4'ü dağıtmama.
            [
              taban + 1,
              taban - 1,
              taban - 2 * q,
              b2 + q,
              b2 + 4 * q,
              alt4(dagit),
            ],
            '$delta En az bir gerçek kök için Δ ≥ 0, yani m ≤ $sinir '
                'olmalıdır. Bu koşulu sağlayan en büyük tam sayı ${_n(taban)} olur.',
            hs,
          );
      }
    },
  ),

  // 7 · Parabol: a → tepe apsisi ve baş katsayı, b → tepe ordinatı,
  // c → soru türü ve apsis kümesi.
  _aile(
    'parabol',
    'Parabolün tepe noktası ve simetri ekseni',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final r = const [
        [-2, -1, 1, 2, 3],
        [-4, -3, 4, 5, -5],
      ][c ~/ 5][a % 5];
      final bas = const [1, 2, -1, -2, 3][a ~/ 5];
      // Tepe noktasının apsisi ile ordinatı eşit olursa birini soran soruda
      // ötekini bulan da doğru yanıta ulaşır; k = r atlanır.
      final k = _uygun(_sifirsizAralik(-9, 12), b, (x) => x != r);
      final kb = -2 * bas * r, kc = bas * r * r + k;
      final pol = [bas, kb, kc];
      final apsis =
          'Tepe noktasının apsisi −b/(2a) = −${_p(kb)}/(2·${_p(bas)}) = '
          '${_n(r)} olur.';
      switch (c % 5) {
        case 0:
          return _tam(
            'y = ${_pol(pol)} parabolünün tepe noktasının apsisi kaçtır?',
            r,
            [-r, 2 * r, -2 * r, k],
            apsis,
          );
        case 1:
          return _tam(
            'f(x) = ${_pol(pol)} fonksiyonunun alabileceği en '
                '${bas > 0 ? 'küçük' : 'büyük'} değer kaçtır?',
            k,
            [kc, _deg(pol, -r), r, -k],
            '$apsis Fonksiyon en ${bas > 0 ? 'küçük' : 'büyük'} değerini tepe '
                'noktasında alır: f(${_n(r)}) = ${_yerine(pol, r)} = ${_n(k)}.',
          );
        case 2:
          return _tam(
            'y = ${_pol(pol)} parabolünün tepe noktası T(r, k) olduğuna göre '
                'r + k toplamı kaçtır?',
            r + k,
            [k - r, r + kc, r - k, r + _deg(pol, -r)],
            '$apsis Ordinatı k = ${_yerine(pol, r)} = ${_n(k)} olduğundan '
                'r + k = ${_n(r)} + ${_p(k)} = ${_n(r + k)} bulunur.',
          );
        case 3:
          final sabit = kc == 0 ? '' : (kc < 0 ? ' − ${-kc}' : ' + $kc');
          return _tam(
            'y = ${_pol([bas, 0, 0])} + mx$sabit parabolünün simetri ekseni '
                'x = ${_n(r)} doğrusu olduğuna göre m kaçtır?',
            kb,
            [-kb, -bas * r, bas * r, -2 * r],
            'Simetri ekseni x = −b/(2a) doğrusudur. −m/(2·${_p(bas)}) = '
                '${_n(r)} eşitliğinden m = −2·${_p(bas)}·${_p(r)} = ${_n(kb)} '
                'bulunur.',
          );
        default:
          return _tam(
            'y = ${_pol([bas, kb, 0])} + m parabolünün tepe noktasının '
                'ordinatı ${_n(k)} olduğuna göre m kaçtır?',
            kc,
            [k, k - bas * r * r, bas * r * r, k + kb],
            '$apsis Tepe noktasının ordinatı ${_yerine([bas, kb, 0], r)} + m = '
                '${_n(k - kc)} + m olur. ${_n(k - kc)} + m = ${_n(k)} eşitliğinden '
                'm = ${_n(kc)} bulunur.',
          );
      }
    },
  ),

  // 8 · İkinci dereceden eşitsizlik: a ve b kökleri, c biçimi ve soruyu seçer.
  _aile(
    'esitsizlik2',
    'İkinci dereceden eşitsizlikte tam sayı çözümler',
    Difficulty.medium,
    BloomLevel.analiz,
    (a, b, c) {
      final dahil = c.isOdd;
      final t = c ~/ 2;
      final sayiSorusu = t == 0 || t == 2;
      // Kökler arası uzaklık. Toplam sorularında arada tam iki tam sayı kalan
      // açık aralık (uzaklık 3) atlanır: o durumda toplam, kökler toplamına
      // eşit olur.
      final g = !sayiSorusu && !dahil && b >= 1 ? b + 3 : b + 2;
      // Toplam sorularında toplamın 0 çıktığı simetrik aralık ile toplamın
      // tam sayı adedine ya da kökler çarpımına eşit olduğu aralıklar atlanır.
      final p = sayiSorusu
          ? a - 12 - g ~/ 2
          : _uygun([for (var x = -12; x <= 18; x++) x - g ~/ 2], a, (x) {
              final y = x + g;
              final adet = dahil ? g + 1 : g - 1;
              final toplam = (x + y) * adet ~/ 2;
              return toplam != 0 && toplam != adet && toplam != x * y;
            });
      final q = p + g;
      final top = p + q, carp = p * q;
      final ilk = dahil ? p : p + 1, son = dahil ? q : q - 1;
      final adet = son - ilk + 1;
      final toplam = (ilk + son) * adet ~/ 2;
      final kucuk = dahil ? '≤' : '<', buyuk = dahil ? '≥' : '>';
      String carpan(int r) => r == 0 ? 'x' : '(${_pol([1, -r])})';
      final carpanli = '${carpan(p)}·${carpan(q)}';
      final standart = _pol([1, -top, carp]);
      final esitsizlik = switch (t) {
        0 || 1 => '$standart $kucuk 0',
        2 => '$carpanli $kucuk 0',
        3 => 'x² $kucuk ${_pol([top, -carp])}',
        _ => '${_pol([-1, top, -carp])} $buyuk 0',
      };
      final hazirlik = switch (t) {
        0 || 1 => '$standart = $carpanli olduğundan',
        2 => 'Çarpanlara göre',
        3 =>
          'Eşitsizlik $standart $kucuk 0 biçiminde düzenlenir; '
              '$standart = $carpanli olduğundan',
        _ =>
          'Eşitsizlik −1 ile çarpılıp yön değiştirilir: $standart $kucuk 0. '
              '$standart = $carpanli olduğundan',
      };
      final aralik = '${_n(p)} $kucuk x $kucuk ${_n(q)}';
      final sayilar = adet == 1
          ? 'Bu aralıktaki tek tam sayı ${_n(ilk)} olur.'
          : adet <= 4
          ? 'Bu aralıktaki tam sayılar '
                '${[for (var x = ilk; x <= son; x++) _n(x)].join(', ')} olur.'
          : 'Bu aralıktaki tam sayılar ${_n(ilk)}, ${_n(ilk + 1)}, …, '
                '${_n(son)} olup $adet tanedir.';
      final cozum =
          '$hazirlik kökler ${_n(p)} ve ${_n(q)} olur; eşitsizlik $aralik '
          'aralığında sağlanır. $sayilar';
      if (t == 0 || t == 2) {
        return _tam(
          '$esitsizlik eşitsizliğini sağlayan kaç farklı x tam sayısı vardır?',
          adet,
          dahil ? [g, g - 1, g + 2] : [g, g + 1, g - 2],
          adet == 1
              ? '$cozum Eşitsizliği yalnız bu sayı sağlar.'
              : adet <= 4
              ? '$cozum Bu sayılar $adet tanedir.'
              : cozum,
          pozitif: true,
        );
      }
      return _tam(
        '$esitsizlik eşitsizliğini sağlayan x tam sayılarının toplamı kaçtır?',
        toplam,
        [dahil ? toplam - top : toplam + top, top, adet, carp],
        adet == 1
            ? cozum
            : '$cozum Toplamları (${_n(ilk)} + ${_p(son)})·$adet/2 = '
                  '${_n(toplam)} olur.',
      );
    },
  ),

  // 9 · Özdeşlikler: (a, b) → toplam ya da fark ile çarpım, c → ifade.
  _aile(
    'ozdeslik',
    'İki sayının toplamı ve çarpımıyla özdeşlikler',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final j = a + 25 * b;
      final s = const [2, 3, 4, 5, 6, 7, -2, -3, -4, -5, -6, -7][j % 12];
      final sira = j ~/ 12;
      final farkli = c >= 5;
      // a ve b gerçek kalsın: toplam verilirken s² − 4p > 0, fark verilirken
      // s² + 4p > 0 olacak biçimde çarpım seçilir; sıfır atlanır.
      final esik = (s * s - 1) ~/ 4;
      var p = farkli ? sira - esik : esik - sira;
      if (farkli && p >= 0) p++;
      if (!farkli && p <= 0) p--;
      final i = farkli ? 1 : -1; // özdeşlikteki işaret
      final verilen = farkli ? 'a − b' : 'a + b';
      final imi = farkli ? '+' : '−';
      final s2 = s * s, s3 = s * s * s;
      final kare = s2 + 2 * i * p, kup = s3 + 3 * i * p * s;
      final bas = 'a ve b gerçek sayıları için $verilen = ${_n(s)} ve';
      final hs = _hs(a, b, c);
      switch (c % 5) {
        case 0:
          return _tamS(
            '$bas a·b = ${_n(p)} olduğuna göre a² + b² ifadesinin değeri '
                'kaçtır?',
            kare,
            // İşaret hatası, 2'yi unutma, çarpımı atma, (a ∓ b)²'deki 4'ü ya
            // da küp özdeşliğindeki 3'ü kullanma, işaret ve katsayı birlikte
            // (kareler toplamı pozitif).
            [
              s2 - 2 * i * p,
              s2 + i * p,
              s2,
              s2 + 4 * i * p,
              s2 + 3 * i * p,
              s2 - i * p,
            ],
            'a² + b² = ($verilen)² $imi 2·a·b = ${_p(s)}² $imi 2·${_p(p)} = '
                '${_n(kare)}.',
            hs,
            pozitif: true,
          );
        case 1:
          final diger = farkli ? 'a + b' : 'a − b';
          return _tamS(
            '$bas a·b = ${_n(p)} olduğuna göre ($diger)² ifadesinin değeri '
                'kaçtır?',
            s2 + 4 * i * p,
            // 4 yerine 2 (a² + b² ile karıştırma) ya da 8 (iki katı), işaret,
            // çarpımı atma, 2(a² + b²)'den (a ± b)²'yi çıkarmayı unutma,
            // işaret ve katsayı birlikte, katsayıyı 1 alma (kare pozitif).
            [
              kare,
              s2 - 4 * i * p,
              s2,
              s2 + 8 * i * p,
              2 * kare,
              s2 - 2 * i * p,
              s2 + i * p,
            ],
            '($diger)² = ($verilen)² $imi 4·a·b = ${_p(s)}² $imi 4·${_p(p)} = '
                '${_n(s2 + 4 * i * p)}.',
            hs,
            pozitif: true,
          );
        case 2:
          final kupler = farkli ? 'a³ − b³' : 'a³ + b³';
          return _tamS(
            '$bas a·b = ${_n(p)} olduğuna göre $kupler ifadesinin değeri '
                'kaçtır?',
            kup,
            // İşaret, 3'ü unutma ya da iki kez alma, çarpımı atma, (a ± b)
            // çarpanını unutma, karedeki 2'yi kullanma; çarpanlara ayrılmış
            // biçimde (a ± b) ile çarpmayı unutma, küp yerine kare alma.
            [
              s3 - 3 * i * p * s,
              s3 + i * p * s,
              s3,
              s3 + 6 * i * p * s,
              s3 + 3 * i * p,
              s3 + 2 * i * p * s,
              s2 + 3 * i * p,
              s2 + 3 * i * p * s,
              s3 - i * p * s,
            ],
            '$kupler = ($verilen)³ $imi 3·a·b·($verilen) = ${_p(s)}³ $imi '
                '3·${_p(p)}·${_p(s)} = ${_n(kup)}.',
            hs,
          );
        case 3:
          // İşaret × 2'ye bölme hatası (bölmeyi unutma, iki kez bölme, 2 ile
          // çarpma) bileşik üçlüleri: her biri anahtarla iki ikiz çift kurar.
          // Gerekirse çıkarma yerine toplama ((s² ± kare)/2) da kullanılır.
          final ciftler = [
            [2 * p, -p, -2 * p],
            if (p.isEven) [p ~/ 2, -p, -p ~/ 2],
            [4 * p, -p, -4 * p],
          ];
          final tekler = [
            2 * p, -p, s2 + i * p, 4 * p, if (p.isEven) p ~/ 2, //
            -2 * p, p + 1, p - 1,
          ];
          return _tamS(
            '$bas a² + b² = ${_n(kare)} olduğuna göre a·b çarpımı kaçtır?',
            p,
            [
              ..._ucluTam(p, [
                ...ciftler,
                ..._seckiler(tekler, (u) => _isaretDengeli(p, u)),
              ], hs),
              ...tekler,
            ],
            '($verilen)² = a² + b² ${farkli ? '−' : '+'} 2·a·b olduğundan '
                '${_p(s)}² = ${_n(kare)} ${farkli ? '−' : '+'} 2·a·b, yani '
                '2·a·b = ${_n(2 * p)} ve a·b = ${_n(p)} bulunur.',
            hs,
          );
        default:
          final kupler = farkli ? 'a³ − b³' : 'a³ + b³';
          // İşaret × bölme hatası (3'e, (a ± b) değerine ya da ikisine
          // birden bölmeyi unutma) bileşik üçlüleri önce denenir.
          // Seçenekler işaretçe dengeli tutulur; gerekirse anahtara bir
          // yakın değer eklenir.
          final ps = p * s;
          final tekler = [3 * p, -p, 3 * ps, ps, -3 * p, -ps, p + 1, p - 1];
          return _tamS(
            '$bas $kupler = ${_n(kup)} olduğuna göre a·b çarpımı kaçtır?',
            p,
            [
              ..._ucluTam(p, [
                [3 * p, -p, -3 * p],
                [ps, -p, -ps],
                [3 * ps, -p, -3 * ps],
                [3 * p, ps, 3 * ps],
                ..._seckiler(tekler, (u) => _isaretDengeli(p, u)),
              ], hs),
              ...tekler,
            ],
            '$kupler = ($verilen)³ $imi 3·a·b·($verilen) olduğundan '
                '${_n(kup)} = ${_p(s)}³ $imi 3·${_p(s)}·a·b, yani '
                '${_n(3 * s)}·a·b = ${_n(3 * s * p)} ve a·b = ${_n(p)} bulunur.',
            hs,
          );
      }
    },
  ),

  // 10 · Logaritma: a → kural içeren terim, b → 1/y biçimli terim,
  // c → kural türü ve aradaki işlem.
  _aile(
    'logaritma',
    'Logaritma kurallarıyla ifadenin değeri',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final arti = c < 5, hs = _hs(a, b, c);
      final (tb, tn) = _logTers[b];
      final ikinci = 'log${_alt(tb)}(1/${_us(tb, tn)})';
      // Birinci terim: yazımı, değeri (pay/payda), çözüm adımı ve tipik
      // yanlış değerleri (biri anahtarın altında, biri üstünde olabilir).
      late final String ilk, adim;
      late final int pay, payda;
      late final List<(int, int)> ilkY;
      switch (c % 5) {
        case 0:
          final (t, m) = _logTanim[a];
          ilk = 'log${_alt(t)} ${_us(t, m)}';
          adim = '${_us(t, m)} = $t${_ust(m)} olduğundan $ilk = $m';
          (pay, payda, ilkY) = (m, 1, [(m + 1, 1), (m - 1, 1)]);
        case 1:
          final (t, k, y) = _logBolum[a];
          final x = _us(t, k) * y;
          ilk = 'log${_alt(t)} $x − log${_alt(t)} $y';
          adim =
              '$ilk = log${_alt(t)}($x/$y) = log${_alt(t)} ${_us(t, k)} = $k';
          (pay, payda, ilkY) = (k, 1, [(k + 1, 1), (k - 1, 1)]);
        case 2:
          final (u, w, k) = _logCarpim[a];
          final t = u * w;
          ilk = 'log${_alt(t)} ${_us(u, k)} + log${_alt(t)} ${_us(w, k)}';
          adim =
              '$ilk = log${_alt(t)}(${_us(u, k)}·${_us(w, k)}) = '
              'log${_alt(t)} ${_us(t, k)} = $k';
          // Üsleri toplama (2k) ya da üssü unutma (1).
          (pay, payda, ilkY) = (k, 1, [(2 * k, 1), (1, 1)]);
        case 3:
          final (r, p, q) = _logKesir[a];
          ilk = 'log${_alt(_us(r, p))} ${_us(r, q)}';
          adim =
              '${_us(r, p)} = $r${_ust(p)} ve ${_us(r, q)} = '
              '${q == 1 ? '$r' : '$r${_ust(q)}'} olduğundan $ilk = '
              '${_q(q, p)}';
          // Oranı ters çevirme, üsleri çarpma; argümanın üssünü unutma
          // (1/p), üsleri çıkarma.
          (pay, payda, ilkY) = (
            q,
            p,
            [(p, q), (p * q, 1), (1, p), if (q != p) (q - p, 1)],
          );
        default:
          final (t, ara, k) = _logZincir[a];
          ilk = 'log${_alt(t)} $ara · log${_alt(ara)} ${_us(t, k)}';
          adim = '$ilk = log${_alt(t)} ${_us(t, k)} = $k';
          (pay, payda, ilkY) = (k, 1, [(k + 1, 1), (k - 1, 1)]);
      }
      final i = arti ? -1 : 1; // ikinci terimin katkısı: i·tn
      final deger = _q(pay, payda);
      (int, int) top((int, int) x, (int, int) y) =>
          (x.$1 * y.$2 + y.$1 * x.$2, x.$2 * y.$2);
      // İkinci terimin tipik yanlış değerleri: işaret (+n) ve log_t 1 = 1
      // sanma (1 − n); katkıları işleme göre işaretlenir.
      final dogruK = (i * tn, 1), ilkD = (pay, payda);
      final ikinciY = [
        for (final y in [tn, 1 - tn]) (arti ? y : -y, 1),
      ];
      // Birinci terim × ikinci terim hataları: bileşik (2 × 2) üçlüler önce,
      // sonra ızgaranın öteki üçlüleri.
      final izgara = [
        for (final e in ikinciY) top(ilkD, e),
        for (final y in ilkY) top(y, dogruK),
        for (final y in ilkY)
          for (final e in ikinciY) top(y, e),
      ];
      final n0 = pay + i * tn * payda;
      return _kesS(
        '$ilk ${arti ? '+' : '−'} $ikinci işleminin sonucu kaçtır?',
        n0,
        payda,
        [
          // Son çare: değerin bir fazlası ya da eksiği (üssü bir kaydırma).
          ..._uclu(
            n0,
            payda,
            _gecisler(
              n0,
              payda,
              [
                for (final y in ilkY)
                  for (final e in ikinciY)
                    [top(ilkD, e), top(y, dogruK), top(y, e)],
              ],
              [...izgara, (n0 - payda, payda), (n0 + payda, payda)],
            ),
            hs,
          ),
          ...izgara,
        ],
        '$adim; 1/${_us(tb, tn)} = $tb^(−$tn) olduğundan $ikinci = −$tn '
            'olur. Sonuç $deger ${arti ? '+' : '−'} (−$tn) = '
            '${_q(pay + i * tn * payda, payda)}.',
        hs,
      );
    },
  ),

  // 11 · Üstel ve logaritmik denklemler: c % 5 denklem türünü seçer.
  _aile(
    'ustel_denklem',
    'Üstel ve logaritmik denklemlerin çözümü',
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) {
      final v = c ~/ 5, hs = _hs(a, b, c);
      const soru = 'denklemini sağlayan x değeri kaçtır?';
      switch (c % 5) {
        case 0:
          // t^(px + q) = t^M, M pozitif ya da negatif.
          final (t, m) = _ustelTaban[a];
          final p = 2 + b ~/ 5, x = const [-2, -1, 1, 2, 3][b % 5];
          final us = v == 0 ? m : -m;
          final q = us - p * x;
          final sag = v == 0 ? '${_us(t, m)}' : '1/${_us(t, m)}';
          // p'ye bölmeyi unutma, q'yu işaretiyle taşıma, 1/t^m'yi t^m sanma
          // (ya da tersi), q'yu atma; üssü sayının kendisine eşitleme. En az
          // bir tam sayı yanlış bulunur (anahtar tek tam sayı seçenek
          // kalmasın); son adımdaki işaret hatası (−x, anahtarla aynı
          // rakamlar) yalnız gerekince kullanılır.
          final adaylar = [
            (us - q, 1),
            (us + q, p),
            (-us - q, p),
            (us, p),
            if (v == 0) (_us(t, m) - q, p),
          ];
          final isaret = (-x, 1);
          return _kesS(
            '${_ustlu(t, _pol([p, q]))} = $sag $soru',
            x,
            1,
            [
              ..._uclu(x, 1, [
                ..._seckiler(adaylar, _tamVar),
                ..._seckiler([...adaylar, isaret], (u) => u.contains(isaret)),
              ], hs),
              ...adaylar,
              isaret,
            ],
            '$sag = ${_kuvvet(t, us)} olduğundan üsler eşitlenir: '
                '${_pol([p, q])} = ${_n(us)}. Buradan '
                '${q == 0 ? '' : '${p}x = ${_n(us - q)} ve '}x = ${_n(x)} bulunur.',
            hs,
          );
        case 1:
          // Tabanlar aynı sayının kuvvetleri: A^(x + u) = C^(x + w).
          final (r, i, j) = _ustelCift[a];
          final k = (1 + b ~/ 10) * (v == 0 ? 1 : -1);
          final x = b % 10 - 4;
          final u = j * k - x, w = i * k - x;
          final sol = _us(r, i), sag = _us(r, j);
          // Üs ifadesinin katı: 1·(x + u) → x + u, 2·(x) → 2x.
          String katli(int c, int kay) => c == 1
              ? _pol([1, kay])
              : (kay == 0 ? '${c}x' : '$c·(${_pol([1, kay])})');
          final solUs = katli(i, u), sagUs = katli(j, w);
          final acik = solUs == _pol([i, i * u]) && sagUs == _pol([j, j * w])
              ? ''
              : ', yani ${_pol([i, i * u])} = ${_pol([j, j * w])}';
          return _tamS(
            '${_ustlu(sol, _pol([1, u]))} = ${_ustlu(sag, _pol([1, w]))} $soru',
            x,
            // Üs katsayısını yalnız x'e dağıtma (k), üs katsayılarını iki
            // tarafta yer değiştirme, işaret hatası.
            [k, x - (i + j) * k, x + k, x - k, -x],
            '${i == 1 ? '' : '$sol = $r${_ust(i)} ve '}$sag = $r${_ust(j)} '
                'olduğundan iki taraf $r tabanında yazılır ve üsler eşitlenir: '
                '$solUs = $sagUs$acik. Buradan x = ${_n(x)} bulunur.',
            hs,
          );
        case 2:
          // log_t(px + q) = m.
          final (t, m) = _logDenklemTaban[a];
          final p = 2 + b ~/ 5;
          final x = const [
            [1, 2, 3, 4, 6],
            [-1, -2, -3, 5, 7],
          ][v][b % 5];
          final deger = _us(t, m), q = deger - p * x;
          // Taban ile üssü yer değiştirme (m^t), yakın değerliyse.
          final takas = m >= 2 && _us(m, t) <= 2 * deger ? _us(m, t) : null;
          // p'ye bölmeyi unutma, t^m yerine t·m, işaret hatası, logaritmayı
          // atma (px + q = m), q'yu atma. En az bir tam sayı yanlış bulunur;
          // son adımdaki işaret hatası (−x) yalnız gerekince kullanılır.
          final adaylar = [
            (deger - q, 1),
            (t * m - q, p),
            (deger + q, p),
            (m - q, p),
            if (takas != null) (takas - q, p),
            (deger, p),
          ];
          final isaret = (-x, 1);
          return _kesS(
            'log${_alt(t)}(${_pol([p, q])}) = $m $soru',
            x,
            1,
            [
              ..._uclu(x, 1, [
                ..._seckiler(adaylar, _tamVar),
                ..._seckiler([...adaylar, isaret], (u) => u.contains(isaret)),
              ], hs),
              ...adaylar,
              isaret,
            ],
            'Logaritmanın tanımından ${_pol([p, q])} = '
                '${m == 1 ? '' : '${_kuvvet(t, m)} = '}$deger olur. Buradan '
                '${q == 0 ? '' : '${p}x = ${_n(deger - q)} ve '}x = ${_n(x)} '
                'bulunur.',
            hs,
          );
        case 3:
          // log_t(x + u) − log_t(x + w) = m.
          final (t, m) = const [(2, 1), (2, 2), (3, 1), (2, 3), (3, 2)][a % 5];
          final k = 1 + a ~/ 5, x = b - 9;
          final oran = _us(t, m);
          final u = oran * k - x, w = k - x;
          String lg(int kay) =>
              kay == 0 ? 'log${_alt(t)} x' : 'log${_alt(t)}(${_pol([1, kay])})';
          String par(int kay) => kay == 0 ? 'x' : '(${_pol([1, kay])})';
          final denklem = v == 0
              ? '${lg(u)} − ${lg(w)} = $m'
              : '${lg(u)} = $m + ${lg(w)}';
          // x + A = r·(x + B) denkleminin tam sayı kökü: t^m yerine m ya da
          // t·m alma, bölümü ters kurma.
          final yanlis = [
            for (final (r, sol, sagK) in [
              (m, u, w),
              (t * m, u, w),
              (oran, w, u),
            ])
              if (r != 1 && (r * sagK - sol) % (1 - r) == 0)
                (r * sagK - sol) ~/ (1 - r),
          ];
          return _tamS(
            '$denklem $soru',
            x,
            // Ara sonucu yanıt sanma (x + w = k, x + u = oran·k), bölüm
            // yerine fark, işaret.
            [k, oran * k, u - w, ...yanlis, -x],
            '${v == 0 ? '' : 'Denklem ${lg(u)} − ${lg(w)} = $m biçiminde '
                          'yazılır. '}'
                'Bölüm kuralından ${par(u)}/${par(w)} = '
                '${m == 1 ? '' : '${_kuvvet(t, m)} = '}$oran olur. '
                '${_pol([1, u])} = '
                '${_pol([oran, oran * w])} eşitliğinden x = ${_n(x)} bulunur; bu '
                'değer için logaritması alınan ifadeler pozitiftir.',
            hs,
          );
        default:
          // p·t^(x + i) + q·t^x = N; v = 1 iken üsler bir azaltılır.
          final (t, i, p) = _ustelToplam[a];
          final q = const [1, 3, 5, -1, 7][b % 5];
          final s = b ~/ 5 + (t == 2 ? 1 : 0);
          final ti = _us(t, i), kat = p * ti + q;
          final sag = kat * _us(t, s);
          final x = s + v;
          final buyukUs = _ustlu(t, _pol([1, i - v]));
          final kucukUs = _ustlu(t, _pol([1, -v]));
          final qm = q.abs();
          final sol =
              '${p == 1 ? '' : '$p·'}$buyukUs ${q < 0 ? '−' : '+'} '
              '${qm == 1 ? '' : '$qm·'}$kucukUs';
          return _tamS(
            '$sol = $sag $soru',
            x,
            // Büyük üssün kaymasını yanıta ekleme, bir eksik ya da fazla;
            // üs kaymasını geri eklemeyi unutma ya da ters ekleme.
            [
              x + i,
              x - 1,
              x + 1,
              s + i + 1,
              if (v == 1) s - 1,
              x - i,
              x + 2,
              x - 2,
            ],
            '$buyukUs = $ti·$kucukUs olduğundan denklem '
                '(${p == 1 ? '' : '$p·'}$ti ${q < 0 ? '−' : '+'} $qm)·$kucukUs = '
                '$sag biçimine gelir. ${kat == 1 ? '' : '$kat·$kucukUs = $sag, '
                          'yani '}'
                '$kucukUs = ${_us(t, s)} = ${_kuvvet(t, s)} olduğundan '
                'x = $x bulunur.',
            hs,
          );
      }
    },
  ),

  // 12 · Aritmetik dizi: a → ilk terim ya da verilen terim, b → fark ve
  // sıra numaraları, c → soru türü ve farkın işareti.
  _aile(
    'aritmetik_dizi',
    'Aritmetik dizide terim, ortak fark ve toplam',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final d = const [2, 3, 4, 6][b ~/ 5] * (c >= 5 ? -1 : 1);
      final i5 = b % 5;
      final ilk = _sifirsiz(a, 12);
      switch (c % 5) {
        case 0:
          final n = const [8, 10, 12, 15, 21][i5];
          final an = ilk + (n - 1) * d;
          return _tam(
            'İlk terimi ${_n(ilk)} ve ortak farkı ${_n(d)} olan bir aritmetik '
                'dizinin $n. terimi kaçtır?',
            an,
            [ilk + n * d, ilk + (n - 2) * d, (n - 1) * d],
            'a${_alt(n)} = a₁ + ${n - 1}·d = ${_n(ilk)} + ${n - 1}·${_p(d)} = '
                '${_n(an)}.',
          );
        case 1:
          final (m, n) = const [(3, 7), (4, 9), (2, 8), (5, 11), (6, 13)][i5];
          final am = ilk, an = am + (n - m) * d;
          return _kes(
            'Bir aritmetik dizide a${_alt(m)} = ${_n(am)} ve a${_alt(n)} = '
                '${_n(an)} olduğuna göre bu dizinin ortak farkı kaçtır?',
            d,
            1,
            [(an - am, n - m + 1), (an - am, 1), (-d, 1), (an - am, n)],
            'a${_alt(n)} − a${_alt(m)} = ${n - m}·d olduğundan ${_n(an)} − '
                '${_p(am)} = ${n - m}·d, yani d = ${_n(an - am)}/${n - m} = '
                '${_n(d)} bulunur.',
          );
        case 2:
          final n = const [10, 12, 15, 20, 9][i5];
          // Toplamın 0 ya da son terime eşit çıktığı ilk terimler atlanır:
          // ikiye bölmeyi unutan ya da son terimi yazan da doğru yanıtı
          // bulurdu.
          final ilk = _uygun(_sifirsizAralik(-12, 17), a, (x) {
            final son = x + (n - 1) * d, t = n * (x + son) ~/ 2;
            return t != 0 && t != son;
          });
          final an = ilk + (n - 1) * d;
          final toplam = n * (ilk + an) ~/ 2;
          return _tam(
            'İlk terimi ${_n(ilk)} ve ortak farkı ${_n(d)} olan bir aritmetik '
                'dizinin ilk $n teriminin toplamı kaçtır?',
            toplam,
            [2 * toplam, n * an, an, toplam - an],
            'a${_alt(n)} = ${_n(ilk)} + ${n - 1}·${_p(d)} = ${_n(an)} olur. '
                'İlk $n terimin toplamı $n·(a₁ + a${_alt(n)})/2 = '
                '$n·(${_n(ilk)} + ${_p(an)})/2 = ${_n(toplam)} bulunur.',
          );
        case 3:
          final (m, n, k) = const [
            (3, 7, 12),
            (2, 6, 15),
            (4, 9, 20),
            (5, 8, 14),
            (3, 10, 17),
          ][i5];
          final am = ilk, an = am + (n - m) * d, ak = am + (k - m) * d;
          return _tam(
            'Bir aritmetik dizide a${_alt(m)} = ${_n(am)} ve a${_alt(n)} = '
                '${_n(an)} olduğuna göre a${_alt(k)} kaçtır?',
            ak,
            [
              an + (k - n + 1) * d,
              am + k * d,
              an + (k - m) * d,
              an + (an - am),
            ],
            'Ortak fark d = (${_n(an)} − ${_p(am)})/${n - m} = ${_n(d)} olur. '
                'a${_alt(k)} = a${_alt(n)} + ${k - n}·d = ${_n(an)} + '
                '${k - n}·${_p(d)} = ${_n(ak)}.',
          );
        default:
          final n = const [8, 10, 12, 15, 20][i5];
          // Toplamın 0 ya da son terime eşit çıktığı sabitler atlanır.
          final q = _uygun(_sifirsizAralik(-12, 17), a, (x) {
            final son = d * n + x, t = n * (d + x + son) ~/ 2;
            return t != 0 && t != son;
          });
          final a1 = d + q, an = d * n + q;
          final toplam = n * (a1 + an) ~/ 2;
          return _tam(
            'Genel terimi ${_pol([d, q], 'n')} olan aritmetik dizinin ilk $n '
                'teriminin toplamı kaçtır?',
            toplam,
            [n * an, an, toplam - n * d, 2 * toplam],
            'İlk terim ${_yerine([d, q], 1)} = ${_n(a1)}, $n. terim '
                '${_yerine([d, q], n)} = ${_n(an)} olur. Toplam '
                '$n·(${_n(a1)} + ${_p(an)})/2 = ${_n(toplam)} bulunur.',
          );
      }
    },
  ),

  // 13 · Geometrik dizi: c % 5 soru türünü, c ≥ 5 işareti ya da hedef
  // terimi değiştirir.
  _aile(
    'geometrik_dizi',
    'Geometrik dizide terim, ortak çarpan ve toplam',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final tur = c % 5, ikinci = c >= 5, hs = _hs(a, b, c);
      if (tur == 1 || tur == 3) {
        // İki terimi verilen pozitif terimli dizi; b ≥ 10 iken azalan.
        final (r, e) = (tur == 1 ? _geoOran1 : _geoOran3)[b % 10];
        final azalan = b >= 10;
        final m = 1 + a ~/ 5, n = m + e;
        if (tur == 1) {
          final u = const [
            [1, 2, 3, 5, 7],
            [4, 6, 10, 11, 9],
          ][ikinci ? 1 : 0][a % 5];
          final re = _us(r, e);
          final am = azalan ? u * re : u, an = azalan ? u : u * re;
          final (yp, yq) = azalan ? (1, r) : (r, 1);
          // Kök almayı unutma (r^e), kök yerine e'ye bölme, ters çevirme ×
          // bunlar (bileşik üçlüler); aritmetik dizi gibi farkı e'ye bölme.
          final ters = (yq, yp), kok = (an, am), bol = (an, am * e);
          final fark = (an - am, e);
          return _kesS(
            'Tüm terimleri pozitif olan bir geometrik dizide a${_alt(m)} = '
                '$am ve a${_alt(n)} = $an olduğuna göre bu dizinin ortak çarpanı '
                'kaçtır?',
            yp,
            yq,
            [
              ..._uclu(
                yp,
                yq,
                _gecisler(
                  yp,
                  yq,
                  [
                    [ters, kok, (am, an)],
                    [ters, bol, (am * e, an)],
                    [kok, bol, fark],
                  ],
                  // Son çare: bir fazlası ya da eksiği.
                  [
                    kok, ters, fark, bol, (am, an), (am * e, an), //
                    (yp, yq * e), (yp - yq, yq), (yp + yq, yq),
                  ],
                ),
                hs,
                pozitif: true,
              ),
              kok,
              ters,
              fark,
              (yp, yq * e),
            ],
            'a${_alt(n)} = a${_alt(m)}·r${_ust(e)} olduğundan r${_ust(e)} = '
                '${_oranYaz(an, am)} olur. Terimler pozitif olduğundan '
                'r = ${_q(yp, yq)} bulunur.',
            hs,
            pozitif: true,
          );
        }
        final u = const [1, 2, 3, 5, 7][a % 5];
        // Artan dizide a_m = u; azalan dizide a_(n+1) = u.
        int terim(int sira) =>
            u * _us(r, azalan ? e + 1 - (sira - m) : sira - m);
        final am = terim(m), an = terim(n);
        final k = ikinci ? m + 1 : n + 1;
        final ak = terim(k);
        final oran = azalan ? '1/$r' : '$r';
        // Aritmetik dizi gibi ara değer ya da öteleme, bir adım fazla, r ile
        // bölme–çarpmayı karıştırma, ortak çarpanı ekleme, kök almayı unutma
        // (a_m'den bir adımda a_n bulunacağından yalnız a_n'den giderken),
        // kök yerine e'ye bölme.
        final taban = ikinci ? am : an;
        final yanlis = [
          ...(ikinci
              ? [(am * (e - 1) + an, e), (am + an, 2)]
              : [(an * an, am), (an * (e + 1) - am, e)]),
          azalan ? (ak, r) : (ak * r, 1),
          azalan ? (taban * r, 1) : (taban, r),
          azalan ? (taban * r + 1, r) : (taban + r, 1),
          (taban * an, am * e),
        ];
        return _kesS(
          'Tüm terimleri pozitif olan bir geometrik dizide a${_alt(m)} = $am '
              've a${_alt(n)} = $an olduğuna göre a${_alt(k)} kaçtır?',
          ak,
          1,
          [
            ..._uclu(
              ak,
              1,
              _gecisler(ak, 1, const [], [...yanlis, (ak - 1, 1), (ak + 1, 1)]),
              hs,
              pozitif: true,
            ),
            ...yanlis,
          ],
          'a${_alt(n)} = a${_alt(m)}·r${_ust(e)} olduğundan r${_ust(e)} = '
              '${_oranYaz(an, am)} ve terimler pozitif olduğundan r = $oran '
              'olur. a${_alt(k)} = a${_alt(ikinci ? m : n)}·r = '
              '${ikinci ? am : an}·${_sar(oran)} = $ak.',
          hs,
          pozitif: true,
        );
      }
      final (rm, n) = _geoOranSira[a];
      final r = ikinci ? -rm : rm;
      final a1 = (tur == 2 ? 1 + b ~/ 2 : 2 + b ~/ 2) * (b.isEven ? 1 : -1);
      final kuvvet = _us(r, n - 1);
      final an = a1 * kuvvet;
      if (tur == 0) {
        // Bir fazla ya da eksik kuvvet (r^n, r^(n − 2)), kuvvet yerine
        // çarpma, işaret, aritmetik dizi formülü; işaret × kuvvet hatası
        // bileşik üçlüler kurar.
        final fazla = an * r, eksik = a1 * _us(r, n - 2);
        final yanlis = [
          (fazla, 1), (a1 * r * (n - 1), 1), (-an, 1), //
          (a1 + (n - 1) * r, 1), (eksik, 1), (-fazla, 1), (-eksik, 1),
        ];
        return _kesS(
          'İlk terimi ${_n(a1)} ve ortak çarpanı ${_n(r)} olan bir geometrik '
              'dizinin $n. terimi kaçtır?',
          an,
          1,
          [
            ..._uclu(
              an,
              1,
              _gecisler(an, 1, [
                [(-an, 1), (fazla, 1), (-fazla, 1)],
                [(-an, 1), (eksik, 1), (-eksik, 1)],
              ], yanlis),
              hs,
            ),
            ...yanlis,
          ],
          'a${_alt(n)} = a₁·r${_ust(n - 1)} = ${_n(a1)}·${_p(r)}${_ust(n - 1)} '
              '= ${_n(a1)}·${_p(kuvvet)} = ${_n(an)}.',
          hs,
        );
      }
      if (tur == 4) {
        // r^n'ye ya da r·(n − 1)'e bölme, işaret, r^(n − 2)'ye bölme,
        // aritmetik dizi formülü (a₁ = aₙ − (n − 1)·r); işaret × kuvvet
        // hatası bileşik üçlüler kurar.
        final yanlis = [
          (an, kuvvet * r), (an, r * (n - 1)), (-a1, 1), (a1 * r, 1), //
          (-a1 * r, 1), (-an, kuvvet * r), (an - (n - 1) * r, 1),
        ];
        return _kesS(
          'Ortak çarpanı ${_n(r)} ve $n. terimi ${_n(an)} olan bir geometrik '
              'dizinin ilk terimi kaçtır?',
          a1,
          1,
          [
            ..._uclu(
              a1,
              1,
              _gecisler(a1, 1, [
                [(-a1, 1), (a1 * r, 1), (-a1 * r, 1)],
                [(-a1, 1), (an, kuvvet * r), (-an, kuvvet * r)],
              ], yanlis),
              hs,
            ),
            ...yanlis,
          ],
          'a${_alt(n)} = a₁·r${_ust(n - 1)} olduğundan ${_n(an)} = '
              'a₁·${_p(r)}${_ust(n - 1)} = a₁·${_p(kuvvet)} olur. Buradan '
              'a₁ = ${_n(an)}/${_p(kuvvet)} = ${_n(a1)} bulunur.',
          hs,
        );
      }
      final rn = kuvvet * r;
      final toplam = a1 * (rn - 1) ~/ (r - 1);
      // (r − 1)'e bölmeyi unutma, son terim, bir terim eksik ya da fazla,
      // işaret, aritmetik dizi toplam formülü.
      final aritmetik = (a1 + an) * n;
      return _tamS(
        'İlk terimi ${_n(a1)} ve ortak çarpanı ${_n(r)} olan bir geometrik '
            'dizinin ilk $n teriminin toplamı kaçtır?',
        toplam,
        [
          a1 * (rn - 1),
          an,
          a1 * (kuvvet - 1) ~/ (r - 1),
          -toplam,
          a1 * (rn * r - 1) ~/ (r - 1),
          if (aritmetik.isEven) aritmetik ~/ 2,
        ],
        'İlk $n terimin toplamı a₁·(r${_ust(n)} − 1)/(r − 1) = '
            '${_n(a1)}·(${_p(r)}${_ust(n)} − 1)/(${_p(r)} − 1) = '
            '${_n(a1)}·${_p(rn - 1)}${r == 2 ? '' : '/${_p(r - 1)}'} = '
            '${_n(toplam)} bulunur.',
        hs,
      );
    },
  ),

  // 14 · Özel açılar: c çift → rasyonel değerli iki terimin doğrusal
  // birleşimi, c tek → √3 içeren iki değerin çarpımı.
  _aile(
    'trigonometri_deger',
    'Özel açılarda trigonometrik ifadenin değeri',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      if (c.isEven) {
        final (p, q, i) = const [
          (2, 4, 1),
          (4, 2, -1),
          (6, 2, 1),
          (2, 6, -1),
          (4, 4, -1),
        ][c ~/ 2];
        final t1 = _trigA[a], t2 = _trigB[b];
        final (n1, d1, k1) = _trig(t1.$1, t1.$2);
        final (n2, d2, k2) = _trig(t2.$1, t2.$2);
        if (k1 != 1 || k2 != 1) throw StateError('Rasyonel olmayan terim');
        final payda = d1 * d2;
        final x = p * n1 * d2, y = i * q * n2 * d1;
        return _kes(
          '$p·${_trigYaz(t1)} ${i > 0 ? '+' : '−'} $q·${_trigYaz(t2)} '
              'ifadesinin değeri kaçtır?',
          x + y,
          payda,
          [(y - x, payda), (x - y, payda), (-x - y, payda)],
          '${_indirge(t1)} ve ${_indirge(t2)} olduğundan '
              '$p·${_sar(_q(n1, d1))} ${i > 0 ? '+' : '−'} '
              '$q·${_sar(_q(n2, d2))} = ${_q(x + y, payda)} bulunur.',
        );
      }
      final kat = const [2, 4, 6, 8, 12][c ~/ 2];
      final t1 = _trigR[a], t2 = _trigS[b];
      final v1 = _trig(t1.$1, t1.$2), v2 = _trig(t2.$1, t2.$2);
      if (v1.$3 != 3 || v2.$3 != 3) throw StateError('√3 içermeyen terim');
      final pay = kat * v1.$1 * v2.$1 * 3, payda = v1.$2 * v2.$2;
      return _kes(
        '$kat·${_trigYaz(t1)}·${_trigYaz(t2)} ifadesinin değeri kaçtır?',
        pay,
        payda,
        [(-pay, payda), (pay, 3 * payda), (3 * pay, payda), (-pay, 3 * payda)],
        '${_indirge(t1)} ve ${_indirge(t2)} olduğundan '
            '$kat·${_sar(_trigDeger(v1))}·${_sar(_trigDeger(v2))} = '
            '${_q(pay, payda)} bulunur.',
      );
    },
  ),

  // 15 · Radyan: c % 5 → üçgende dönüşüm, yay uzunluğu, esas ölçü (derece),
  // esas ölçü (radyan) ya da yarıçap.
  _aile(
    'radyan',
    'Radyan, esas ölçü ve yay uzunluğu',
    Difficulty.medium,
    BloomLevel.anlama,
    (a, b, c) {
      final v = c ~/ 5, hs = _hs(a, b, c);
      switch (c % 5) {
        case 0:
          final (p, q) = _ucgenRadyan[b];
          final r = 180 * p ~/ q;
          // Verilen iki açının toplamı 90° olursa üçüncü açı da 90° olur ve
          // iki açıyı toplayıp bırakan da doğru yanıtı bulur; bu açı atlanır.
          // Üçüncü açının verilen açılardan birine eşit çıktığı (yanıtın kökte
          // yazılı olduğu) ölçüler de atlanır.
          final aci = _uygun(
            [for (var x = 10; x <= 64; x += 2) x],
            a,
            (x) => x + r != 90 && 180 - x - r != x && 180 - x - r != r,
          );
          final ucuncu = 180 - aci - r;
          final bas =
              'Bir üçgenin iki iç açısının ölçüleri $aci° ve ${_pili(p, q)} '
              'radyandır.';
          final cevir =
              '${_pili(p, q)} radyan = ${p == 1 ? '' : '$p·'}180°/$q = $r° '
              'olur. Üçüncü açı 180° − $aci° − $r° = $ucuncu° bulunur.';
          // İki açıyı toplayıp bırakma, bir açıyı unutma, π'yi 360° ya da
          // 90° alma, iç açılar toplamını 360° sanma.
          final hatalar = [
            aci + r,
            180 - r,
            180 - aci - 2 * r,
            360 - aci - r,
            180 - aci,
            if (r.isEven) 180 - aci - r ~/ 2,
          ];
          if (v == 0) {
            return _tamS(
              '$bas Bu üçgenin üçüncü iç açısının ölçüsü kaç derecedir?',
              ucuncu,
              hatalar,
              cevir,
              hs,
              pozitif: true,
            );
          }
          // Pay hatası × payda hatası (π'yi 360° ya da 90° alma): anahtar
          // her yazım ögesini iki seçenekle paylaşır.
          return _kesS(
            '$bas Bu üçgenin üçüncü iç açısının ölçüsü k·π radyan olduğuna '
                'göre k kaçtır?',
            ucuncu,
            180,
            [
              ..._uclu(
                ucuncu,
                180,
                [
                  for (final e in hatalar)
                    for (final p in const [360, 90])
                      [(e, 180), (ucuncu, p), (e, p)],
                ],
                hs,
                pozitif: true,
              ),
              (aci + r, 180),
              (ucuncu, 360),
              (ucuncu, 90),
              (180 - r, 180),
            ],
            '$cevir Radyan cinsinden $ucuncu·π/180 = '
                '${_pili(ucuncu, 180)} olduğundan k = ${_q(ucuncu, 180)} olur.',
            hs,
            pozitif: true,
          );
        case 1 || 4:
          final r = 4 * (a + 1);
          final (p, q) = _yayAcilari[b];
          final yay = 3 * r * p ~/ q, derece = 180 * p ~/ q;
          final aci = v == 0 ? '${_pili(p, q)} radyan' : '$derece°';
          final hesap = v == 0
              ? 'Yay uzunluğu r·θ bağıntısıyla bulunur; π = 3 için '
                    'θ = ${_q(3 * p, q)} radyandır.'
              : 'Yay uzunluğu 2πr·($derece/360) bağıntısıyla bulunur; π = 3 '
                    'için bu değer r·${_sar(_q(derece, 60))} olur.';
          if (c % 5 == 1) {
            return _tamS(
              'Yarıçapı $r cm olan bir çemberde, ölçüsü $aci olan merkez '
                  'açının gördüğü yayın uzunluğu kaç cm olur? (π = 3 alınız.)',
              yay,
              // Çap alma, yayın tümleyenini bulma, π'yi unutma, yarıya bölme,
              // açıyı unutup çemberin tamamını ya da yarısını alma.
              [
                2 * yay,
                6 * r - yay,
                if (r * p % q == 0) r * p ~/ q,
                if (yay.isEven) yay ~/ 2,
                6 * r,
                3 * r,
              ],
              '$hesap Yay uzunluğu $r·${_sar(_q(3 * p, q))} = $yay cm '
                  'bulunur.',
              hs,
              birim: 'cm',
              pozitif: true,
            );
          }
          return _tamS(
            'Bir çemberde ölçüsü $aci olan merkez açının gördüğü yayın '
                'uzunluğu $yay cm olduğuna göre bu çemberin yarıçapı kaç cm '
                'olur? (π = 3 alınız.)',
            r,
            // π'yi unutma, çap verme, bulunanı çap sanma, yayı yanıt sanma,
            // yalnız π'ye ya da 2π'ye bölme.
            [
              3 * r,
              2 * r,
              r ~/ 2,
              yay,
              if (yay % 3 == 0) yay ~/ 3,
              if (yay % 6 == 0) yay ~/ 6,
            ],
            '$hesap r·${_sar(_q(3 * p, q))} = $yay eşitliğinden r = $r cm '
                'bulunur.',
            hs,
            birim: 'cm',
            pozitif: true,
          );
        case 2:
          final esas = 2 * (5 * a + b % 5) + 11;
          final tur = b ~/ 5 + 2;
          // Tümleyen (360° − x), ters yön (x + 180°), bütünler, onlar
          // basamağında işlem hatası (yanıt tek sayı; ±10 teklik bozmaz).
          final ortak = [
            360 - esas,
            (esas + 180) % 360,
            if (esas < 180) 180 - esas,
            esas - 10,
            esas + 10,
            if (esas > 20) esas - 20,
          ];
          if (v == 0) {
            final aci = 360 * tur + esas;
            return _tamS(
              'Ölçüsü $aci° olan açının esas ölçüsü kaç derecedir?',
              esas,
              // Tur sayısını yanıt sanma, bir tur eksik çıkarma.
              [ortak[0], ortak[1], tur, esas + 360, ...ortak.skip(2)],
              '$aci° = $tur·360° + $esas° olduğundan esas ölçü $esas° olur.',
              hs,
              pozitif: true,
            );
          }
          final aci = esas - 360 * (tur - 1);
          return _tamS(
            'Ölçüsü ${_n(aci)}° olan açının esas ölçüsü kaç derecedir?',
            esas,
            // Bir tur eksik ya da fazla ekleme.
            [ortak[0], ortak[1], esas - 360, esas + 360, ...ortak.skip(2)],
            'Esas ölçü 0° ile 360° arasındadır (0° dâhil). ${_n(aci)}° + '
                '${tur - 1}·360° = $esas° olduğundan esas ölçü $esas° olur.',
            hs,
          );
        default:
          final (q, m) = _radyanEsas[a];
          final tur = 1 + b % 10;
          final pay = v == 0 ? 2 * q * tur + m : m - 2 * q * tur;
          final aci = pay < 0 ? '−${_pili(-pay, q)}' : _pili(pay, q);
          final indir = v == 0
              ? '$aci = $tur·2π + ${_pili(m, q)}'
              : '$aci + $tur·2π = ${_pili(m, q)}';
          if (b >= 10) {
            final derece = 180 * m ~/ q;
            return _tamS(
              'Ölçüsü $aci radyan olan açının esas ölçüsü kaç derecedir?',
              derece,
              // Tümleyen, ters yön, π'yi 90° ya da 360° alma, bütünler, bir
              // tur eksik çıkarma.
              [
                360 - derece,
                (derece + 180) % 360,
                if (derece.isEven) derece ~/ 2,
                if (2 * derece < 360) 2 * derece,
                if (derece < 180) 180 - derece,
                derece + 360,
              ],
              '$indir olduğundan esas ölçü ${_pili(m, q)} radyandır. Bu da '
                  '${m == 1 ? '' : '$m·'}180°/$q = $derece° eder.',
              hs,
              pozitif: true,
            );
          }
          // Ters yön (2π − x), π kadar kayma, bir tur eksik ya da fazla
          // çıkarma (negatif kalma); payda hatası (2q, π ile 2π'yi
          // karıştırma) ile bileşik üçlüler önce denenir.
          final ters = 2 * q - m, kay = (m + q) % (2 * q);
          final eksik = m + 2 * q, fazla = m - 2 * q;
          return _kesS(
            'Ölçüsü $aci radyan olan açının esas ölçüsü k·π radyan olduğuna '
                'göre k kaçtır?',
            m,
            q,
            [
              ..._uclu(m, q, [
                for (final e in [ters, kay, eksik, fazla])
                  [(e, q), (m, 2 * q), (e, 2 * q)],
                [(ters, q), (kay, q), (eksik, q)],
                [(fazla, q), (m, 2 * q), (ters, q)],
                [(fazla, q), (m, 2 * q), (eksik, q)],
                [(fazla, q), (ters, q), (eksik, q)],
              ], hs),
              (ters, q),
              (kay, q),
              (m, 2 * q),
              (eksik, q),
              (fazla, q),
            ],
            '$indir olduğundan esas ölçü ${_pili(m, q)} radyandır; '
                'k = ${_q(m, q)} olur.',
            hs,
            komsuPozitif: true,
          );
      }
    },
  ),

  // 16 · Limit: c % 5 → polinom, sadeleşen kesir (iki tür), sonsuzda derece
  // karşılaştırması (iki tür).
  _aile(
    'limit',
    'Polinom ve rasyonel ifadelerde limit',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final v = c ~/ 5, hs = _hs(a, b, c);
      const son = 'limitinin değeri kaçtır?';
      switch (c % 5) {
        case 0:
          final k = const [-2, -1, 1, 2, 3][a % 5];
          final p = const [1, 2, 3, -1][b ~/ 5];
          final w = const [-5, -2, 1, 4, 7][b % 5];
          // x = −k yazan (işaret hatası) ya da sabit terimi limit sanan
          // yolların da doğru değeri verdiği katsayılar atlanır.
          final u = _uygun(const [-4, -3, 2, 5, 6, -7, 7, -6, 8], a ~/ 5, (x) {
            final govde = v == 0 ? [p, x, 0] : [1, p, x, 0];
            final y = _deg(govde, k);
            return y != 0 && y != _deg(govde, -k);
          });
          final pol = v == 0 ? [p, u, w] : [1, p, u, w];
          final deger = _deg(pol, k);
          return _tam(
            'lim (x → ${_n(k)}) (${_pol(pol)}) $son',
            deger,
            [_deg(pol, -k), deger - w, w, deger - 2 * w],
            'Polinom fonksiyonlar sürekli olduğundan limit, x = ${_n(k)} '
                'için ifadenin değerine eşittir: ${_yerine(pol, k)} = '
                '${_n(deger)}.',
          );
        case 1:
          final i = v == 0 ? 1 : -1;
          final k = i * (1 + a % 5), m = i * const [1, 2, 3, 5, 7][a ~/ 5];
          final p = 1 + b ~/ 5;
          // Limit 1 çıkarsa “0/0 = 1” diyen de doğru yanıtı bulur; bu payda
          // katsayısı atlanır.
          final n = _uygun(
            const [1, 2, 3, 4, 5, 6],
            b % 5,
            (x) => x != p * k + m,
          );
          final pay = [p, m - p * k, -m * k], payda = [n, -n * k];
          final kok = _pol([1, -k]);
          // Pay hatası (−k yazma: m − pk; türevde yalnız 2px: 2pk) × payda
          // hatası (n'ye bölmeyi unutma) bileşik üçlüleri; 0/0 = 0 ya da 1
          // sanma.
          final y = p * k + m;
          return _kesS(
            'lim (x → ${_n(k)}) (${_pol(pay)})/(${_pol(payda)}) $son',
            y,
            n,
            [
              ..._uclu(
                y,
                n,
                _gecisler(
                  y,
                  n,
                  [
                    for (final e in [m - p * k, 2 * p * k])
                      [(e, n), (y, 1), (e, 1)],
                  ],
                  // Sabitlerin oranı (x = 0 koyma), baş katsayıların oranı,
                  // çarpanlara ayırırken m'nin işaretini karıştırma da
                  // tipik yanlışlardır.
                  [
                    (y, 1), (m - p * k, n), (2 * p * k, n), (m - p * k, 1), //
                    (2 * p * k, 1), (m, n), (p, n), (p * k - m, n),
                    (p * k - m, 1), (0, 1), (1, 1),
                  ],
                ),
                hs,
              ),
              (y, 1),
              (m - p * k, n),
              (0, 1),
              (y, n * k),
            ],
            'x = ${_n(k)} için pay ve payda sıfır olur. Pay ($kok)·'
                '(${_pol([p, m])}), payda ${n == 1 ? kok : '$n·($kok)'} biçiminde '
                'yazılıp sadeleştirilir: (${_pol([p, m])})'
                '${n == 1 ? '' : '/$n'} ifadesinin x = ${_n(k)} için değeri '
                '${_q(p * k + m, n)} olur.',
            hs,
          );
        case 2:
          // p ≠ q olduğundan oranı ters çeviren (q/p) aynı değeri bulamaz.
          // x'li terimlerin ya da sabit terimlerin oranı p/q değerine eşit
          // olursa yanlış katsayıları oranlayan da doğru yanıtı bulur; bu
          // katsayılar atlanır, sabit terimin işareti çevrilir.
          final p = const [2, 3, 5, 7, 9][a % 5];
          final q = const [4, 6, 8, 10][b ~/ 5];
          final s = const [-5, -2, 1, 4, 7][b % 5];
          final u = _uygun(
            const [-4, -1, 3, 6, 8, -7, 10],
            a ~/ 5,
            (x) => x * q != p * s,
          );
          final w = const [3, -1, 4, -5, 7][(a + b) % 5];
          final t0 = const [-2, 5, 1, -3, 6][(a ~/ 5 + b) % 5];
          final t = w * q == p * t0 ? -t0 : t0;
          final ifade = v == 0
              ? '(${_pol([p, u, w])})/(${_pol([q, s, t])})'
              : '(${_polArtan([w, u, p])})/(${_polArtan([t, s, q])})';
          // Oranı ters çevirme × yanlış terimlerin (x'li ya da sabit)
          // oranını alma bileşik üçlüleri: anahtar ile tersi, yanlış oran ile
          // tersi iki ikiz çift kurar. ∞/∞ = 1 ya da 0 sanma.
          return _kesS(
            'lim (x → ∞) $ifade $son',
            p,
            q,
            [
              ..._uclu(
                p,
                q,
                _gecisler(
                  p,
                  q,
                  [
                    [(q, p), (u, s), (s, u)],
                    [(q, p), (w, t), (t, w)],
                  ],
                  [(q, p), (u, s), (w, t), (s, u), (t, w), (0, 1), (1, 1)],
                ),
                hs,
              ),
              (q, p),
              (u, s),
              (w, t),
              (0, 1),
            ],
            'Pay ve paydanın dereceleri eşit (2) olduğundan limit, en büyük '
                'dereceli terimlerin katsayıları oranıdır: $p/$q'
                '${_q(p, q) == '$p/$q' ? '' : ' = ${_q(p, q)}'}.',
            hs,
          );
        case 3:
          // q ≥ 3 olduğundan baş katsayıları çarpmak yerine toplayan (p + q)
          // aynı değeri bulamaz. Sabit terimlerin oranı limite eşit olursa
          // paydadaki sabitin işareti çevrilir.
          final p = 1 + a % 5, u = const [-3, -1, 2, 4, 5][a ~/ 5];
          final q = const [3, 4, 5, 6][b ~/ 5];
          // r = p·q olursa limit 1 çıkar ve “∞/∞ = 1” diyen de doğru yanıtı
          // bulur; bu katsayı atlanır.
          final r = _uygun(const [2, 3, 5, 7, 9, 11], b % 5, (x) => x != p * q);
          final e = const [1, -2, 3, -1, 2][(a + b) % 5];
          final w0 = const [3, -4, 1, 5, -2][(a ~/ 5 + b ~/ 5) % 5];
          final w = u * e * r == p * q * w0 ? -w0 : w0;
          final carpim = '(${_pol([p, u])})·(${_pol([q, e])})';
          final kare = _pol([r, 0, w]);
          final acilim =
              'Çarpım açıldığında en büyük dereceli terim '
              '${_pol([p, 0])}·${_pol([q, 0])} = ${_pol([p * q, 0, 0])} olur; '
              'pay ve paydanın dereceleri eşittir.';
          // Tek çarpanın katsayısını alma, katsayıları toplama, sabitlerin
          // oranı, oranı ters çevirme, paydayı (ya da payı) unutma, 0 sanma.
          final pq = p * q, ue = u * e;
          if (v == 0) {
            final yanlis = [
              (p, r), (q, r), (p + q, r), (ue, w), (r, pq), (pq, 1), (0, 1), //
            ];
            // Bileşik üçlüler: pay hatası × paydayı unutma, pay hatası ×
            // ters çevirme.
            final tasarim = [
              for (final e in [p + q, p, q]) ...[
                [(e, r), (pq, 1), (e, 1)],
                [(r, pq), (e, r), (r, e)],
              ],
            ];
            return _kesS(
              'lim (x → ∞) [$carpim]/($kare) $son',
              pq,
              r,
              [
                ..._uclu(pq, r, _gecisler(pq, r, tasarim, yanlis), hs),
                ...yanlis,
              ],
              '$acilim Limit, en büyük dereceli terimlerin katsayıları '
                  'oranıdır: ${p * q}/$r'
                  '${_q(p * q, r) == '${p * q}/$r' ? '' : ' = ${_q(p * q, r)}'}.',
              hs,
            );
          }
          final yanlis = [
            (r, p), (r, q), (r, p + q), (w, ue), (pq, r), (r, 1), (0, 1), //
          ];
          // Bileşik üçlüler: payda hatası × ters çevirme.
          final tasarim = [
            for (final e in [p + q, p, q]) [(pq, r), (r, e), (e, r)],
          ];
          return _kesS(
            'lim (x → ∞) ($kare)/[$carpim] $son',
            r,
            pq,
            [..._uclu(r, pq, _gecisler(r, pq, tasarim, yanlis), hs), ...yanlis],
            '$acilim Limit, en büyük dereceli terimlerin katsayıları '
                'oranıdır: $r/${p * q}'
                '${_q(r, p * q) == '$r/${p * q}' ? '' : ' = ${_q(r, p * q)}'}.',
            hs,
          );
        default:
          final i = v == 0 ? 1 : -1;
          final k = i * (1 + a % 5), m = i * const [1, 2, 3, 5, 7][a ~/ 5];
          final p = 1 + b ~/ 10;
          // Limitin 1 çıktığı (p·k + m = k + n) payda sabiti atlanır.
          final n = _uygun(
            [
              for (final x in const [4, 6, 8, 9, 10, 11, 12, 14, 15, 16, 18])
                i * x,
            ],
            b % 10,
            (x) => p * k + m != k + x,
          );
          final pay = [p, m - p * k, -m * k], payda = [1, n - k, -n * k];
          final kok = _pol([1, -k]);
          final ham = '${_n(p * k + m)}/${_p(k + n)}';
          final sade = _q(p * k + m, k + n);
          // Pay ya da paydada −k yazma (biri ya da ikisi), x = 0 koyma, baş
          // katsayıların oranı, paydayı unutma, ters çevirme, 0/0 = 0 ya da
          // 1 sanma.
          // Çarpanlara ayırırken payda ya da paydada sabitin işaretini
          // karıştırma (biri ya da ikisi) da bileşik üçlü kurar.
          final y = p * k + m, z = k + n, yT = m - p * k, zT = n - k;
          final yS = p * k - m, zS = k - n;
          final yanlis = [
            (m, n), (p, 1), (yT, zT), (y, 1), (yT, z), (y, zT), (z, y), //
            (yS, z), (y, zS), (yS, zS), (0, 1), (1, 1),
          ];
          return _kesS(
            'lim (x → ${_n(k)}) (${_pol(pay)})/(${_pol(payda)}) $son',
            y,
            z,
            [
              ..._uclu(
                y,
                z,
                _gecisler(y, z, [
                  [(yT, z), (y, zT), (yT, zT)],
                  [(yS, z), (y, zS), (yS, zS)],
                ], yanlis),
                hs,
              ),
              ...yanlis,
            ],
            'x = ${_n(k)} için pay ve payda sıfır olur. Pay ($kok)·'
                '(${_pol([p, m])}), payda ($kok)·(${_pol([1, n])}) biçiminde '
                'yazılıp sadeleştirilir: (${_pol([p, m])})/(${_pol([1, n])}) '
                'ifadesinin x = ${_n(k)} için değeri '
                '$ham${ham == sade ? '' : ' = $sade'} olur.',
            hs,
          );
      }
    },
  ),

  // 17 · Türev kuralları: c % 5 → polinom, çarpım, bölüm, değerlerle çarpım
  // ve değerlerle bölüm.
  _aile(
    'turev',
    'Türev alma kuralları ve bir noktadaki türev',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final v = c ~/ 5;
      switch (c % 5) {
        case 0:
          final p = const [1, 2, -1, 3, -2][a % 5];
          final r = const [-7, -3, 2, 6, 9][b % 5];
          final k = const [-2, -1, 1, 2][b ~/ 5];
          List<int> kur(int q, int s) =>
              v == 0 ? [p, q, r, s] : [1, p, q, r, s];
          List<int> turevi(List<int> f) => [
            for (var j = 0; j < f.length - 1; j++) f[j] * (f.length - 1 - j),
          ];
          // Üsle çarpmayı unutan ya da x = −k yazan yolların da doğru değeri
          // verdiği katsayılar atlanır.
          final q = _uygun(const [-4, -2, 1, 3, 5, -5, 2, 6], a ~/ 5, (x) {
            final f = kur(x, 0), y = _deg(turevi(f), k);
            return y != _deg(f.sublist(0, f.length - 1), k) &&
                y != _deg(turevi(f), -k);
          });
          // f(k) = f′(k) olursa türev almadan da doğru yanıt bulunur; o
          // durumda sabit terimin işareti çevrilir.
          final s0 = const [4, -6, 1, -3, 8][(a + b) % 5];
          final s = _deg(kur(q, s0), k) == _deg(turevi(kur(q, s0)), k)
              ? -s0
              : s0;
          final pol = kur(q, s);
          final n = pol.length - 1;
          final turev = turevi(pol);
          final deger = _deg(turev, k);
          return _tam(
            'f(x) = ${_pol(pol)} fonksiyonu için f′(${_n(k)}) değeri kaçtır?',
            deger,
            [
              _deg(pol, k),
              _deg(pol.sublist(0, n), k),
              deger + s,
              _deg(turev, -k),
            ],
            'f′(x) = ${_pol(turev)} olduğundan f′(${_n(k)}) = '
                '${_yerine(turev, k)} = ${_n(deger)}.',
          );
        case 1:
          final p = 1 + a % 5;
          final r = const [1, 2, 3, -1][b ~/ 5];
          final k = 1 + v;
          final wt = 2 * r * k;
          // Birinci çarpan k noktasında sıfır olursa kuralın tek terimi de
          // doğru yanıtı verir; bu sabit atlanır.
          final q = _uygun(
            const [-3, -1, 1, 2, 4, -2, 3],
            a ~/ 5,
            (x) => p * k + x != 0,
          );
          final u = p * k + q;
          // Türevleri çarpan (f′·g′) ya da türev almadan f(k) hesaplayan
          // yolların da doğru değeri verdiği sabitler atlanır.
          final s = _uygun(const [-4, -1, 2, 3, 5, -5, 1, 4, 6, -2], b % 5, (
            x,
          ) {
            final y = p * (r * k * k + x) + u * wt;
            return y != p * wt && y != u * (r * k * k + x);
          });
          final w = r * k * k + s;
          final deger = p * w + u * wt;
          return _tam(
            'f(x) = (${_pol([p, q])})·(${_pol([r, 0, s])}) fonksiyonu için '
                'f′($k) değeri kaçtır?',
            deger,
            [p * wt, p * w - u * wt, p * w, u * w],
            'Çarpım kuralından f′(x) = $p·(${_pol([r, 0, s])}) + '
                '(${_pol([p, q])})·(${_pol([2 * r, 0])}) olur. f′($k) = '
                '$p·${_p(w)} + ${_p(u)}·${_p(wt)} = ${_n(deger)}.',
          );
        case 2:
          final p = 1 + a % 5;
          final r = 1 + b ~/ 5, sm = 1 + b % 5;
          final s = v == 0 ? sm : -sm;
          final k = v == 0 ? 1 : -1;
          final alt = r * k + s;
          // Pay ve paydanın türevlerini oranlayan (p/r) yolun da doğru değeri
          // verdiği sabitler atlanır.
          final q = _uygun(
            [
              for (final x in const [1, 2, 3, 5, 7, 4, 6]) v == 0 ? -x : x,
            ],
            a ~/ 5,
            (x) => (p * s - x * r) * r != p * alt * alt,
          );
          final pay = p * s - q * r;
          return _kes(
            'f(x) = (${_pol([p, q])})/(${_pol([r, s])}) fonksiyonu için '
                'f′(${_n(k)}) değeri kaçtır?',
            pay,
            alt * alt,
            [(p * s + q * r, alt * alt), (p, r), (pay, alt), (-pay, alt * alt)],
            'Bölüm kuralından f′(x) = [$p·(${_pol([r, s])}) − '
                '(${_pol([p, q])})·$r]/(${_pol([r, s])})² = ${_n(pay)}/'
                '(${_pol([r, s])})² olur. f′(${_n(k)}) = ${_n(pay)}/${_p(alt)}² = '
                '${_q(pay, alt * alt)}.',
          );
        default:
          // f çift, f′ ve g tek seçilir: f′·g tek, f·g′ çift olduğundan
          // çarpım ve bölüm türevinin payı hiçbir zaman sıfır olmaz.
          // g(k) ≠ 1 olduğundan paydanın karesini almayı unutan aynı değeri
          // bulamaz. Türevleri çarpan ya da oranlayan (f′·g′, f′/g′) ve
          // f·f′ + g·g′ alan yolların da doğru değeri verdiği g′ değerleri
          // atlanır.
          final fa = const [2, 4, -2, 6, -4][a % 5];
          final ft = const [-3, -1, 1, 3, 5][a ~/ 5];
          final ga = const [3, -3, -1, 5][b ~/ 5];
          final gt = _uygun(const [-4, -1, 2, 3, 5, -2, 4, -5, 1, 6], b % 5, (
            x,
          ) {
            if (c % 5 == 3) {
              final ht = ft * ga + fa * x;
              return ht != ft * x && ht != fa * ft + ga * x;
            }
            return v == 0
                ? (ft * ga - fa * x) * x != ft * ga * ga
                : (x * fa - ga * ft) * ft != x * fa * fa;
          });
          final k = 1 + (a + b) % 4;
          final veri =
              'Türevlenebilir f ve g fonksiyonları için f($k) = ${_n(fa)}, '
              'f′($k) = ${_n(ft)}, g($k) = ${_n(ga)}';
          if (c % 5 == 3) {
            final ht = ft * ga + fa * gt;
            if (v == 0) {
              return _tam(
                '$veri ve g′($k) = ${_n(gt)} veriliyor. h(x) = f(x)·g(x) '
                    'olduğuna göre h′($k) değeri kaçtır?',
                ht,
                [ft * gt, ft * ga - fa * gt, fa * ga, fa * ft + ga * gt],
                'Çarpım kuralından h′($k) = f′($k)·g($k) + f($k)·g′($k) = '
                    '${_p(ft)}·${_p(ga)} + ${_p(fa)}·${_p(gt)} = ${_n(ht)}.',
              );
            }
            return _kes(
              '$veri veriliyor. h(x) = f(x)·g(x) ve h′($k) = ${_n(ht)} '
                  'olduğuna göre g′($k) değeri kaçtır?',
              gt,
              1,
              [(ht, ft), (ht - ft * ga, 1), (ht + ft * ga, fa), (-gt, 1)],
              'Çarpım kuralından h′($k) = f′($k)·g($k) + f($k)·g′($k), yani '
                  '${_n(ht)} = ${_p(ft)}·${_p(ga)} + ${_p(fa)}·g′($k) olur. '
                  'Buradan ${_n(fa)}·g′($k) = ${_n(ht - ft * ga)} ve g′($k) = '
                  '${_n(gt)} bulunur.',
            );
          }
          if (v == 0) {
            final pay = ft * ga - fa * gt;
            return _kes(
              '$veri ve g′($k) = ${_n(gt)} veriliyor. h(x) = f(x)/g(x) '
                  'olduğuna göre h′($k) değeri kaçtır?',
              pay,
              ga * ga,
              [
                (ft * ga + fa * gt, ga * ga),
                (ft, gt),
                (pay, ga),
                (-pay, ga * ga),
              ],
              'Bölüm kuralından h′($k) = [f′($k)·g($k) − f($k)·g′($k)]/'
                  '[g($k)]² = [${_p(ft)}·${_p(ga)} − ${_p(fa)}·${_p(gt)}]/'
                  '${_p(ga)}² = ${_q(pay, ga * ga)}.',
            );
          }
          final pay = gt * fa - ga * ft;
          return _kes(
            '$veri ve g′($k) = ${_n(gt)} veriliyor. h(x) = g(x)/f(x) '
                'olduğuna göre h′($k) değeri kaçtır?',
            pay,
            fa * fa,
            [
              (gt * fa + ga * ft, fa * fa),
              (gt, ft),
              (pay, fa),
              (-pay, fa * fa),
            ],
            'Bölüm kuralından h′($k) = [g′($k)·f($k) − g($k)·f′($k)]/'
                '[f($k)]² = [${_p(gt)}·${_p(fa)} − ${_p(ga)}·${_p(ft)}]/'
                '${_p(fa)}² = ${_q(pay, fa * fa)}.',
          );
      }
    },
  ),

  // 18 · Türevin uygulamaları: c % 5 → teğet eğimi, teğet denklemi, yerel
  // ekstremum apsisi, monotonluk aralığı, ekstremum değeri.
  _aile(
    'turev_uygulama',
    'Türevle teğet, yerel ekstremum ve monotonluk',
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) {
      final v = c ~/ 5;
      String carpan(int r) => r == 0 ? 'x' : '(${_pol([1, -r])})';
      switch (c % 5) {
        case 0:
          final q = _sifirsiz(a, 12);
          final p = const [1, 2, 3, -1][b ~/ 5];
          final k = const [-2, -1, 1, 2, 3][b % 5];
          final egim = 2 * p * k + q;
          // y(k) = y′(k) olursa türev almadan da eğim bulunur; o durumda
          // sabit terimin işareti çevrilir.
          final r0 = const [5, -3, 2, -7, 4, 1, -6][(a + b) % 7];
          final r = v == 0 && _deg([p, q, r0], k) == egim ? -r0 : r0;
          final pol = [p, q, r], turev = [2 * p, q];
          if (v == 0) {
            return _tam(
              'y = ${_pol(pol)} parabolüne x = ${_n(k)} apsisli noktasından '
                  'çizilen teğetin eğimi kaçtır?',
              egim,
              [p * k + q, 2 * p * k, _deg(pol, k), 2 * p * k - q],
              'Teğetin eğimi türevin o noktadaki değeridir. y′ = '
                  '${_pol(turev)} olduğundan eğim ${_yerine(turev, k)} = '
                  '${_n(egim)} olur.',
            );
          }
          return _kes(
            'y = ${_pol(pol)} parabolüne üzerindeki bir noktadan çizilen '
                'teğetin eğimi ${_n(egim)} olduğuna göre bu noktanın apsisi '
                'kaçtır?',
            k,
            1,
            [(egim + q, 2 * p), (egim - q, p), (egim - q, 1), (-k, 1)],
            'Teğetin eğimi türevin o noktadaki değeridir. y′ = '
                '${_pol(turev)} = ${_n(egim)} eşitliğinden ${_pol([2 * p, 0])} = '
                '${_n(egim - q)} ve x = ${_n(k)} bulunur.',
          );
        case 1:
          final k = const [-2, -1, 1, 2, 3][b % 5];
          final p0 = const [1, 2, 3, -1][b ~/ 5];
          // Yatay teğet (m = 0) ile orijinden geçen teğet (n = 0) atlanır:
          // bu durumlarda m + n, yalnız n ya da yalnız m bulunarak da elde
          // edilir. v = 0 iken n = r − p·k², v = 1 iken n = d − 2k³ olur.
          final q = _uygun(
            _sifirsizAralik(-12, 14),
            a,
            (x) => (v == 0 ? 2 * p0 * k : 3 * k * k) + x != 0,
          );
          final r0 = const [5, -3, 2, -7, 4, 1, -6][(a + b) % 7];
          final pol = v == 0
              ? [p0, q, r0 == p0 * k * k ? -r0 : r0]
              : [
                  1,
                  0,
                  q,
                  const [-6, -3, 3, 7][b ~/ 5],
                ];
          final n = pol.length - 1;
          final turev = [for (var j = 0; j < n; j++) pol[j] * (n - j)];
          final m = _deg(turev, k), yk = _deg(pol, k), kesen = yk - m * k;
          return _tam(
            'f(x) = ${_pol(pol)} eğrisine x = ${_n(k)} apsisli noktasından '
                'çizilen teğetin denklemi y = mx + n olduğuna göre m + n toplamı '
                'kaçtır?',
            m + kesen,
            [m, m + yk, m - kesen, kesen],
            'f′(x) = ${_pol(turev)} olduğundan m = f′(${_n(k)}) = ${_n(m)} '
                'olur. Değme noktası (${_n(k)}, ${_n(yk)}) olduğundan ${_n(yk)} = '
                '${_p(m)}·${_p(k)} + n, yani n = ${_n(kesen)} bulunur. m + n = '
                '${_n(m + kesen)}.',
          );
        case 2 || 4:
          // f(x) = ±(x³ − 3c₀x² + 3(c₀² − g²)x) + d; kritik noktalar c₀ ∓ g.
          // Ekstremum değeri sorulurken değer sabit terime eşit çıkarsa
          // (ekstremum x = 0 noktasında ya da sabitsiz kısım orada sıfır)
          // sabit terimi yanıt sanan da doğru yanıtı bulur; bu (c₀, g)
          // ikilileri atlanır.
          final (c0, g) = c % 5 == 2
              ? (a % 5 - 2, 1 + a ~/ 5)
              : _uygun(
                  [
                    for (var h = 1; h <= 5; h++)
                      for (var s = -2; s <= 2; s++) (s, h),
                    (-3, 1),
                    (3, 1),
                    (-3, 2),
                    (3, 2),
                  ],
                  a,
                  (t) {
                    final (s, h) = t;
                    final x0 = v == 0 ? s - h : s + h;
                    return _deg([1, -3 * s, 3 * (s * s - h * h), 0], x0) != 0;
                  },
                );
          final r1 = c0 - g, r2 = c0 + g;
          final i = c % 5 == 2 && b >= 10 ? -1 : 1;
          // Ekstremum değeri sorulurken değerin, noktanın apsisine eşit
          // çıktığı sabit terim atlanır.
          final d = c % 5 == 2
              ? _sifirsiz(b % 10, 5)
              : _uygun(_sifirsizAralik(-9, 12), b, (x) {
                  final x0 = v == 0 ? r1 : r2;
                  return _deg([1, -3 * c0, 3 * (c0 * c0 - g * g), x], x0) != x0;
                });
          final pol = [i, -3 * c0 * i, 3 * (c0 * c0 - g * g) * i, d];
          final turev = [3 * i, -6 * c0 * i, 3 * (c0 * c0 - g * g) * i];
          final kritik =
              'f′(x) = ${_pol(turev)} = ${_n(3 * i)}·${carpan(r1)}·'
              '${carpan(r2)} olduğundan kritik noktalar x = ${_n(r1)} ve '
              'x = ${_n(r2)} olur.';
          // i = 1 iken türev r1 noktasında +'dan −'ye geçer (yerel maksimum).
          final maks = i == 1 ? r1 : r2, min = i == 1 ? r2 : r1;
          final isaret =
              'Türev x = ${_n(maks)} noktasında pozitiften negatife, '
              'x = ${_n(min)} noktasında negatiften pozitife geçer.';
          if (c % 5 == 2) {
            final aranan = v == 0 ? min : maks;
            return _tam(
              'f(x) = ${_pol(pol)} fonksiyonunun yerel '
                  '${v == 0 ? 'minimum' : 'maksimum'} noktasının apsisi kaçtır?',
              aranan,
              [v == 0 ? maks : min, -aranan, c0, 2 * c0],
              '$kritik $isaret Yerel ${v == 0 ? 'minimum' : 'maksimum'} '
                  'noktasının apsisi ${_n(aranan)} olur.',
            );
          }
          final x0 = v == 0 ? maks : min, diger = v == 0 ? min : maks;
          return _tam(
            'f(x) = ${_pol(pol)} fonksiyonunun yerel '
                '${v == 0 ? 'maksimum' : 'minimum'} değeri kaçtır?',
            _deg(pol, x0),
            [_deg(pol, diger), d, _deg(pol, c0), x0],
            '$kritik $isaret Yerel ${v == 0 ? 'maksimum' : 'minimum'} değeri '
                'f(${_n(x0)}) = ${_yerine(pol, x0)} = ${_n(_deg(pol, x0))} olur.',
          );
        default:
          // f(x) = ±(2x³ − 3(r₁ + r₂)x² + 6r₁r₂x) + d.
          // m = 0 olursa n − m ile m + n aynı sayı olur; bu yüzden aralığın
          // sol ucu sıfırdan farklı seçilir.
          final r1 = const [-3, -2, -1, 1, 2][a % 5], r2 = r1 + 1 + a ~/ 5;
          final i = b >= 10 ? -1 : 1;
          final d = _sifirsiz(b % 10, 5);
          final pol = [2 * i, -3 * (r1 + r2) * i, 6 * r1 * r2 * i, d];
          final turev = [6 * i, -6 * (r1 + r2) * i, 6 * r1 * r2 * i];
          final yon = i == 1 ? 'azalan' : 'artan';
          final giris =
              'f′(x) = ${_pol(turev)} = ${_n(6 * i)}·${carpan(r1)}·'
              '${carpan(r2)} olur. Türev yalnız ${_n(r1)} < x < ${_n(r2)} '
              'için ${i == 1 ? 'negatif' : 'pozitif'} olduğundan fonksiyon '
              '(${_n(r1)}, ${_n(r2)}) aralığında $yon olur; m = ${_n(r1)}, '
              'n = ${_n(r2)}.';
          final kok =
              'f(x) = ${_pol(pol)} fonksiyonunun $yon olduğu en geniş aralık '
              '(m, n) olduğuna göre';
          if (v == 0) {
            return _tam('$kok n − m farkı kaçtır?', r2 - r1, [
              r1 + r2,
              2 * (r2 - r1),
              r1 * r2,
              r2 - r1 + 1,
            ], '$giris n − m = ${_n(r2)} − ${_p(r1)} = ${r2 - r1}.');
          }
          return _tam('$kok m + n toplamı kaçtır?', r1 + r2, [
            r2 - r1,
            -(r1 + r2),
            r1 * r2,
            2 * (r1 + r2),
          ], '$giris m + n = ${_n(r1)} + ${_p(r2)} = ${_n(r1 + r2)}.');
      }
    },
  ),

  // 19 · İntegral: c % 5 → belirli integral, eğri altı alan, parabol–doğru
  // arası alan, işaret değiştiren doğruda alan, integralden parametre.
  _aile(
    'integral',
    'Belirli integral ve integralle alan hesabı',
    Difficulty.hard,
    BloomLevel.uygulama,
    (a, b, c) {
      final v = c ~/ 5, hs = _hs(a, b, c);
      // (0, 3) yoktur: 3³ = 3·3² olduğundan parametre sorusunda ilkel yerine
      // integrandı kullanan da aynı sonucu bulurdu.
      const sinirlar = [
        [(0, 1), (0, 2), (1, 2), (1, 3)],
        [(0, 4), (2, 3), (1, 4), (2, 4)],
      ];
      switch (c % 5) {
        case 0:
          final p = 1 + a % 5, q = const [-2, -1, 1, 2, 3][a ~/ 5];
          final (alt, ust) = sinirlar[v][b ~/ 5];
          // İntegralin 0 çıktığı ya da integral almadan f(üst) − f(alt)
          // hesaplayan yolun da doğru değeri verdiği sabitler atlanır.
          final r = _uygun(const [-4, -1, 2, 5, 7, -7, 1, 4, -2, 8], b % 5, (
            x,
          ) {
            final y = _deg([p, q, x, 0], ust) - _deg([p, q, x, 0], alt);
            return y != 0 &&
                y !=
                    _deg([3 * p, 2 * q, x], ust) - _deg([3 * p, 2 * q, x], alt);
          });
          final f = [3 * p, 2 * q, r], ilkel = [p, q, r, 0];
          final fu = _deg(ilkel, ust), fa = _deg(ilkel, alt);
          return _tamS(
            '∫${_alt(alt)}${_ust(ust)} (${_pol(f)}) dx belirli integralinin '
                'değeri kaçtır?',
            fu - fa,
            [
              fu + fa,
              _deg(f, ust) - _deg(f, alt),
              fu,
              // Üssü artırıp yeni üsse bölmeyi unutma (x·f(x)) ve sabitin
              // ilkelini x'siz bırakma; sınırları ters alma en sonda (yanıtın
              // ters işaretlisi, anahtarla sözcük ortaklığı kurar).
              ust * _deg(f, ust) - alt * _deg(f, alt),
              fu - fa - r * (ust - alt),
              fa - fu,
            ],
            'İlkel fonksiyon F(x) = ${_pol(ilkel)} olur. F($ust) − F($alt) = '
                '${_n(fu)} − ${_p(fa)} = ${_n(fu - fa)}.',
            hs,
          );
        case 1:
          final p = 1 + a % 5, r = 1 + a ~/ 5;
          final f = [3 * p, 2 * v, r], ilkel = [p, v, r, 0];
          // Alanın, taban × uç yükseklik çarpımına ya da uç yüksekliklerin
          // farkına eşit çıktığı aralıklar atlanır: integral almadan da doğru
          // yanıt bulunurdu.
          final (alt, ust) = _uygun(
            [
              for (var boy = 1; boy <= 4; boy++)
                for (var x = -2; x <= 2; x++) (x, x + boy),
              (-3, -2),
              (3, 4),
              (-3, -1),
              (3, 5),
              (-3, 0),
              (-3, 1),
              (-3, 2),
              (-2, 3),
              (-3, 3),
              (-4, -3),
              (4, 5),
              (-1, 4),
            ],
            b,
            (s) {
              final alan = _deg(ilkel, s.$2) - _deg(ilkel, s.$1);
              final y1 = _deg(f, s.$1), y2 = _deg(f, s.$2);
              return alan != y1 * (s.$2 - s.$1) &&
                  alan != y2 * (s.$2 - s.$1) &&
                  alan != (y2 - y1).abs();
            },
          );
          final fu = _deg(ilkel, ust), fa = _deg(ilkel, alt);
          final boy = ust - alt, ya = _deg(f, alt), yu = _deg(f, ust);
          return _tamS(
            'y = ${_pol(f)} eğrisi, x ekseni, x = ${_n(alt)} ve x = ${_n(ust)} '
                'doğruları ile sınırlanan bölgenin alanı kaç birimkaredir?',
            fu - fa,
            // Yamuk ya da dikdörtgen sanma, integral almadan fark alma;
            // yeni üsse bölmeyi unutma (x·f(x)), sabitin ilkelini x'siz
            // bırakma, alt sınırı unutma.
            [
              if ((ya + yu) * boy % 2 == 0) (ya + yu) * boy ~/ 2,
              (yu - ya).abs(),
              yu * boy,
              ya * boy,
              (fu + fa).abs(),
              ust * yu - alt * ya,
              fu - fa - r * boy,
              fu,
            ],
            'Eğri x ekseninin üstünde kaldığından alan, fonksiyonun '
                'x = ${_n(alt)} ile x = ${_n(ust)} arasındaki belirli '
                'integralidir. F(x) = ${_pol(ilkel)} için F(${_n(ust)}) − '
                'F(${_n(alt)}) = ${_n(fu)} − ${_p(fa)} = ${fu - fa}.',
            hs,
            pozitif: true,
          );
        case 2:
          final sabit = _sifirsiz(a, 12);
          final k = 1 + b % 5, t = 1 + b ~/ 5;
          final i = v == 0 ? 1 : -1;
          final dogru = sabit + i * 3 * k * t * t;
          final alan = 4 * k * t * t * t;
          final fark = [-3 * k, 0, 3 * k * t * t];
          final ilkel = [-k, 0, 3 * k * t * t, 0];
          final kt3 = k * t * t * t;
          return _tamS(
            'y = ${_pol([3 * k * i, 0, sabit])} parabolü ile y = ${_n(dogru)} '
                'doğrusu arasında kalan sınırlı bölgenin alanı kaç birimkaredir?',
            alan,
            // Yarım aralık, dikdörtgen, iki kat, üçgen; farkı almadan yalnız
            // parabolün ya da yalnız doğrunun [−t, t] integrali.
            [
              alan ~/ 2,
              6 * kt3,
              2 * alan,
              3 * kt3,
              (2 * i * kt3 + 2 * sabit * t).abs(),
              (2 * t * dogru).abs(),
            ],
            '${_pol([3 * k * i, 0, sabit])} = ${_n(dogru)} eşitliğinden '
                'x² = ${t * t}, yani x = −$t ve x = $t bulunur. Bu aralıkta '
                'üstteki eğri ile alttaki eğrinin farkı ${_pol(fark)} olur; '
                'ilkeli F(x) = ${_pol(ilkel)} için alan F($t) − F(−$t) = '
                '${alan ~/ 2} − (−${alan ~/ 2}) = $alan.',
            hs,
            pozitif: true,
          );
        case 3:
          final m = const [1, 2, 3, -1, -2][a % 5];
          final z = (1 + a ~/ 5) * (v == 0 ? 1 : -1);
          final u = 1 + b ~/ 5, w = 1 + b % 5;
          final alt = z - u, ust = z + w;
          final mm = m.abs();
          final alan = mm * (u * u + w * w);
          final net = mm * (w * w - u * u).abs();
          return _tamS(
            'y = ${_pol([2 * m, -2 * m * z])} doğrusu, x ekseni, '
                'x = ${_n(alt)} ve x = ${_n(ust)} doğruları arasında kalan '
                'bölgelerin alanları toplamı kaç birimkaredir?',
            alan,
            // Net integral, üçgende 1/2'yi unutma, tek büyük üçgen, yarım;
            // yalnız eksenin üstündeki parça, uç yükseklikli dikdörtgen.
            [
              net,
              2 * alan,
              mm * (u + w) * (u + w),
              if (alan.isEven) alan ~/ 2,
              m > 0 ? mm * w * w : mm * u * u,
              2 * mm * (m > 0 ? w : u) * (u + w),
            ],
            'Doğru x eksenini x = ${_n(z)} noktasında keser ve bu noktada '
                'işaret değiştirir. [${_n(alt)}, ${_n(z)}] aralığındaki üçgenin '
                'alanı $u·${2 * mm * u}/2 = ${mm * u * u}, [${_n(z)}, ${_n(ust)}] '
                'aralığındaki üçgenin alanı $w·${2 * mm * w}/2 = ${mm * w * w} '
                'olur. Toplam alan $alan.',
            hs,
            pozitif: true,
          );
        default:
          final m = _sifirsiz(a, 12);
          final p = 1 + b % 5;
          final (alt, ust) = sinirlar[v][b ~/ 5];
          final kup = p * (ust * ust * ust - alt * alt * alt);
          final boy = ust - alt;
          final deger = kup + m * boy;
          return _kesS(
            '∫${_alt(alt)}${_ust(ust)} (${_pol([3 * p, 0, 0])} + m) dx = '
                '${_n(deger)} olduğuna göre m kaçtır?',
            m,
            1,
            // m'nin ilkelini x'siz alma, ilkel yerine integrandı kullanma,
            // işaret hatası, x² terimini atma, 3'e bölmeyi unutma.
            [
              (deger - kup, 1),
              (deger - 3 * p * (ust * ust - alt * alt), boy),
              (deger + kup, boy),
              (deger, boy),
              (deger - 3 * kup, boy),
            ],
            'İlkel fonksiyon F(x) = ${_pol([p, 0, 0, 0])} + mx olur. '
                'F($ust) − F($alt) = $kup + ${boy == 1 ? '' : boy}m = '
                '${_n(deger)} eşitliğinden '
                '${boy == 1 ? '' : '${boy}m = ${_n(deger - kup)} ve '}'
                'm = ${_n(m)} bulunur.',
            hs,
          );
      }
    },
  ),

  // 20 · Toplam ve çarpım sembolü: c % 5 → Σ(pk + q), Σ(pk² + …), alt sınırı
  // 1 olmayan toplam, sabit terimli toplam, sadeleşen çarpım.
  _aile(
    'toplam_sembolu',
    'Toplam ve çarpım sembolüyle hesaplama',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final v = c ~/ 5, hs = _hs(a, b, c);
      String sigma(int alt, int ust, String ifade) =>
          'Alt sınırı k = $alt ve üst sınırı $ust olan Σ $ifade toplamının '
          'değeri kaçtır?';
      switch (c % 5) {
        case 0:
          final p = (2 + b ~/ 5) * (v == 0 ? 1 : -1);
          final n = const [8, 10, 12, 15, 20][b % 5];
          final t = n * (n + 1) ~/ 2;
          // Toplamın, yalnız son terime (p·n + q) eşit çıktığı sabit atlanır.
          final q = _uygun(
            _sifirsizAralik(-12, 17),
            a,
            (x) => p * t + x * n != p * n + x,
          );
          final toplam = p * t + q * n;
          return _tamS(
            sigma(
              1,
              n,
              '(${v == 0 ? _pol([p, q], 'k') : _polArtan([q, p], 'k')})',
            ),
            toplam,
            // Sabiti bir kez alma, son terimi n kez alma, Σ k için n(n − 1)/2,
            // yalnız son terim, 2'ye bölmeyi unutma, sabiti k ile ortak alma.
            [
              p * t + q,
              n * (p * n + q),
              p * (t - n) + q * n,
              p * n + q,
              2 * p * t + q * n,
              (p + q) * t,
            ],
            'k = 1 için başlayan toplamda Σ k = $n·${n + 1}/2 = $t olur; '
            'sabit terim $n kez toplanır. Sonuç ${_p(p)}·$t + '
            '$n·${_p(q)} = ${_n(toplam)}.',
            hs,
          );
        case 1:
          final p = 1 + b ~/ 5;
          final n = const [5, 6, 7, 8, 10][b % 5];
          final k1 = n * (n + 1) ~/ 2, k2 = n * (n + 1) * (2 * n + 1) ~/ 6;
          // Toplamın yalnız son terime eşit çıktığı sabit atlanır: son terimi
          // toplam sanan da doğru yanıtı bulurdu.
          final q = _uygun(
            _sifirsizAralik(-12, 15),
            a,
            (x) => v == 0
                ? p * k2 + x * n != p * n * n + x
                : p * k2 + x * k1 != p * n * n + x * n,
          );
          final kareler = 'Σ k² = $n·${n + 1}·${2 * n + 1}/6 = $k2';
          // Yanlış Σ k² formülleri: (Σ k)², Σ k, n(n + 1)(2n + 1)/3 ve
          // n(n + 1)(n + 2)/6.
          final k2b = n * (n + 1) * (n + 2) ~/ 6;
          if (v == 0) {
            final toplam = p * k2 + q * n;
            return _tamS(
              sigma(1, n, '(${_pol([p, 0, q], 'k')})'),
              toplam,
              // Sabiti bir kez alma ya da atma, son terimi n kez alma, yalnız
              // son terim.
              [
                p * k1 * k1 + q * n,
                p * k2 + q,
                p * k1 + q * n,
                p * k2,
                2 * p * k2 + q * n,
                p * k2b + q * n,
                n * (p * n * n + q),
                p * n * n + q,
              ],
              '$kareler olur; sabit terim $n kez toplanır. Sonuç '
              '${p == 1 ? '' : '$p·'}$k2 + $n·${_p(q)} = ${_n(toplam)}.',
              hs,
            );
          }
          final toplam = p * k2 + q * k1;
          return _tamS(
            sigma(1, n, '(${_pol([p, q, 0], 'k')})'),
            toplam,
            // Σ k yerine n ya da 1 alma, k²'yi atma; iki terimde de aynı
            // toplamı kullanma, son terimi n kez alma.
            [
              p * k1 * k1 + q * k1,
              p * k2 + q * n,
              p * k2 + q,
              p * k2,
              2 * p * k2 + q * k1,
              p * k2b + q * k1,
              (p + q) * k2,
              (p + q) * k1,
              n * (p * n * n + q * n),
            ],
            '$kareler ve Σ k = $n·${n + 1}/2 = $k1 olur. Sonuç '
            '${p == 1 ? '' : '$p·'}$k2 + ${_p(q)}·$k1 = ${_n(toplam)}.',
            hs,
          );
        case 2:
          final m = 3 + a % 5;
          final p = 2 + b ~/ 5;
          final adet = const [6, 8, 10, 12, 14][b % 5];
          final n = m + adet - 1;
          // Alt sınırı 1 sayan yolun da doğru toplamı verdiği (ilk m − 1
          // terimin toplamı 0) ya da ilk terimin 0 olduğu sabitler atlanır.
          final q = _uygun(
            [for (var x = 1; x <= 8; x++) v == 0 ? x : -x],
            a ~/ 5,
            (x) => 2 * x != -p * m && x != -p * m && x != -p * n,
          );
          final kt = (m + n) * adet ~/ 2;
          final toplam = p * kt + q * adet;
          return _tamS(
            sigma(m, n, '(${_pol([p, q], 'k')})'),
            toplam,
            // Son terimi eksik ya da fazla alma, 1'den başlatma, ilk terimi
            // atma, sabiti bir kez ya da n kez alma, 2'ye bölmeyi unutma.
            [
              toplam - (p * n + q),
              p * n * (n + 1) ~/ 2 + q * n,
              toplam - (p * m + q),
              p * kt + q,
              toplam + p * (n + 1) + q,
              p * kt + q * n,
              2 * p * kt + q * adet,
            ],
            'Terim sayısı $n − $m + 1 = $adet olur. Σ k = ($m + $n)·$adet/2 '
            '= $kt ve sabit terim $adet kez toplanır. Sonuç $p·$kt + '
            '$adet·${_p(q)} = ${_n(toplam)}.',
            hs,
          );
        case 3:
          final sabit = 2 + a;
          final m = const [
            [2, 3, 4, 5],
            [6, 7, 8, 10],
          ][v][b ~/ 5];
          final adet = const [5, 7, 9, 12, 16][b % 5];
          final n = m + adet - 1;
          return _tamS(
            sigma(m, n, '$sabit'),
            sabit * adet,
            // Terim sayısını n − m, n, n + m ya da n − m + 2 alma; yalnız
            // terim sayısını verme, sabiti bir kez alma (kökteki sayı olduğu
            // için en sonda).
            [
              sabit * (n - m),
              sabit * n,
              sabit * (n + m),
              sabit * (adet + 1),
              adet,
              sabit,
            ],
            'Sabit terim, terim sayısı kadar toplanır. Terim sayısı '
            '$n − $m + 1 = $adet olduğundan toplam $adet·$sabit = '
            '${sabit * adet} olur.',
            hs,
            pozitif: true,
          );
        default:
          final m = 1 + b, n = m + 1 + a;
          final (pay, payda) = v == 0 ? (n + 1, m) : (m, n + 1);
          final ifade = v == 0 ? '(k + 1)/k' : 'k/(k + 1)';
          String carpan(int k) => v == 0 ? '(${k + 1}/$k)' : '($k/${k + 1})';
          final acik = n - m <= 2
              ? [for (var k = m; k <= n; k++) carpan(k)].join('·')
              : '${carpan(m)}·${carpan(m + 1)}·…·${carpan(n)}';
          final sade = _q(pay, payda);
          // Pay ve paydada birer sınır kaydırma hatası (bir eksik ya da bir
          // fazla) bileşik üçlüler kurar: anahtar her ögeyi iki seçenekle
          // paylaşır.
          final (p0, p1, p2) = v == 0 ? (n, n + 1, n + 2) : (m - 1, m, m + 1);
          final (d0, d1, d2) = v == 0 ? (m - 1, m, m + 1) : (n, n + 1, n + 2);
          return _kesS(
            'Alt sınırı k = $m ve üst sınırı $n olan Π [$ifade] çarpımının '
                'değeri kaçtır?',
            pay,
            payda,
            [
              ..._uclu(
                pay,
                payda,
                [
                  for (final (x, y) in [(p0, d2), (p2, d0), (p0, d0), (p2, d2)])
                    [(x, d1), (p1, y), (x, y)],
                ],
                hs,
                pozitif: true,
              ),
              (p0, d1),
              (p1, d2),
              (p2, d1),
              (p1, d0),
              ...(v == 0 ? [(n + 1, 1), (m, n + 1)] : [(1, n + 1), (n + 1, m)]),
            ],
            'Çarpım açık yazılırsa $acik olur. Ardışık çarpanlarda bir '
                'kesrin ${v == 0 ? 'payı' : 'paydası'} sonraki kesrin '
                '${v == 0 ? 'paydasıyla' : 'payıyla'} sadeleşir; geriye '
                '$pay/$payda${sade == '$pay/$payda' ? '' : ' = $sade'} kalır.',
            hs,
            pozitif: true,
          );
      }
    },
  ),
];
