// Seçeneklerin biçiminden doğan ipuçlarını önleyen çeldirici yardımcıları.
// Bilgisiz bir öğrenci anahtarı seçeneklerin düzeninden bulamamalıdır
// (ölçüm: tool/lise_metin/ipucu.dart). Bu yüzden sayısal seçeneklerde
// anahtarın değer sırası, "hangileri" sorularında da çeldirici kümeler
// vakadan vakaya anahtardan bağımsız olarak değiştirilir.
import 'ortak.dart';

/// [i] numaralı vaka için 0 … 3 arasında bir hedef sıra verir. 5.000 vakada
/// dört değer eşit sıklıkta görülür ve (a, b, c) koordinatlarıyla ilişkisizdir.
/// Aynı ailede ikinci bir bağımsız seçim gerekiyorsa farklı bir [tuz] verin.
int hedefSira(int i, [int tuz = 0]) => (_karma(i, tuz) >> 16) % 4;

/// [i] ve [tuz] için 32 bitlik belirlenimci karma değer (murmur3 karıştırıcısı).
/// Çarpımlar 2⁵³ altında kalacak biçimde 16 bitlik parçalarla yapılır.
int _karma(int i, int tuz) {
  var x = (i * 40503 + tuz * 2654435 + 0x165667B1) & 0xffffffff;
  x ^= x >> 16;
  x = _carp32(x, 0x85EBCA6B);
  x ^= x >> 13;
  x = _carp32(x, 0xC2B2AE35);
  x ^= x >> 16;
  return x;
}

int _carp32(int a, int b) =>
    ((a & 0xffff) * b + (((a >> 16) * b & 0xffff) << 16)) & 0xffffffff;

/// Sayısal çeldiricileri, anahtardan küçük olanların sayısı [sira] (0 … 3)
/// olacak biçimde seçer. [adaylar] öncelik sırasıyla (değer, yazım)
/// ikilileridir: önce tipik hata değerleri (anahtarın iki yanında da),
/// en sonda gerekirse komşu değerler. Bir yanda yeterli aday yoksa kalan
/// adaylarla tamamlanır. Yazımı anahtarla ya da birbiriyle aynı olan
/// (`ayniSecenek`) adaylar atlanır.
List<String> siraliCeldiriciler(
  num anahtar,
  String anahtarYazim,
  Iterable<(num, String)> adaylar,
  int sira,
) {
  final s = sira.clamp(0, 3);
  final kota = [s, 3 - s];
  final secilen = <String>[], yedek = <String>[];
  bool yeni(String x) =>
      x.trim().isNotEmpty &&
      !ayniSecenek(x, anahtarYazim) &&
      !secilen.any((w) => ayniSecenek(w, x)) &&
      !yedek.any((w) => ayniSecenek(w, x));
  for (final (deger, yazim) in adaylar) {
    if (secilen.length == 3) break;
    if (!yeni(yazim)) continue;
    final yan = deger < anahtar ? 0 : 1;
    if (kota[yan] > 0) {
      secilen.add(yazim);
      kota[yan]--;
    } else {
      yedek.add(yazim);
    }
  }
  for (final x in yedek) {
    if (secilen.length == 3) break;
    secilen.add(x);
  }
  if (secilen.length != 3) {
    throw StateError('Eksik çeldirici: $anahtarYazim → $secilen');
  }
  return secilen;
}

/// Tam sayı yanıtlı soru; anahtarın değer sırası [sira] ile belirlenir.
/// [alternatives] tipik hata değerleridir; yetmezse anahtarın iki yanındaki
/// komşu değerlerle tamamlanır.
AdvancedItem sayisalSirali(
  String prompt,
  int answer,
  Iterable<int> alternatives,
  String explanation,
  int sira, {
  String unit = '',
  bool positive = false,
}) {
  final step = answer.abs() >= 200 ? 10 : (answer.abs() >= 40 ? 5 : 1);
  final aday = [
    ...alternatives,
    for (var k = 1; k <= 6; k++) ...[answer + k * step, answer - k * step],
  ].where((x) => !positive || x > 0);
  final yazim = birimli('$answer', unit);
  return AdvancedItem(
    prompt,
    yazim,
    siraliCeldiriciler(answer, yazim, [
      for (final x in aday) (x, birimli('$x', unit)),
    ], sira),
    explanation,
  );
}

/// Ondalıklı yanıtlı soru; anahtarın değer sırası [sira] ile belirlenir.
/// Değerler [digits] basamakla yazılır ve sıra yazılan değere göre bulunur.
AdvancedItem ondalikliSirali(
  String prompt,
  double answer,
  Iterable<double> alternatives,
  String explanation,
  int sira, {
  String unit = '',
  int digits = 2,
  bool positive = false,
}) {
  final step = answer.abs() >= 20 ? 1.0 : (answer.abs() >= 2 ? 0.5 : 0.1);
  final aday = [
    ...alternatives,
    for (var k = 1; k <= 6; k++) ...[answer + k * step, answer - k * step],
  ].where((x) => x.isFinite && (!positive || x > 0));
  double yuvarla(double x) =>
      double.parse(tr(x, digits).replaceFirst(',', '.'));
  final yazim = birimli(tr(answer, digits), unit);
  return AdvancedItem(
    prompt,
    yazim,
    siraliCeldiriciler(yuvarla(answer), yazim, [
      for (final x in aday) (yuvarla(x), birimli(tr(x, digits), unit)),
    ], sira),
    explanation,
  );
}

/// Kesir yanıtlı soru; anahtarın değer sırası [sira] ile belirlenir.
AdvancedItem kesirliSirali(
  String prompt,
  int n,
  int d,
  Iterable<(int, int)> alternatives,
  String explanation,
  int sira, {
  String unit = '',
}) {
  final aday = [
    ...alternatives,
    (n + 1, d),
    (n - 1, d),
    (n, d + 1),
    (n, d - 1),
    (n + 2, d),
    (n - 2, d),
    (n + 1, d + 1),
    (n + 3, d),
  ].where((x) => x.$2 != 0);
  final yazim = birimli(kesir(n, d), unit);
  return AdvancedItem(
    prompt,
    yazim,
    siraliCeldiriciler(n / d, yazim, [
      for (final x in aday) (x.$1 / x.$2, birimli(kesir(x.$1, x.$2), unit)),
    ], sira),
    explanation,
  );
}

/// [n] öncüllü bir "hangileri" sorusunda, anahtar kümeden ([anahtar] bit
/// maskesi; I → 1, II → 2, III → 4 …) bağımsız seçilmiş üç çeldirici maske
/// verir. Boş küme ve anahtar dışarıda kalır; [uygun] verilirse yalnız onu
/// sağlayan maskeler kullanılır. Seçim [i] ile değişir; çeldiriciler anahtarın
/// tek öge değiştirilmiş komşuları olmak zorunda değildir, bu yüzden öge
/// çoğunluğu anahtarı göstermez.
List<int> kumeCeldiricileri(
  int anahtar,
  int n,
  int i, {
  bool Function(int maske)? uygun,
}) {
  final havuz = [
    for (var m = 1; m < (1 << n); m++)
      if (m != anahtar && (uygun == null || uygun(m))) m,
  ];
  if (havuz.length < 3) {
    throw StateError('Yetersiz çeldirici küme: n = $n, anahtar = $anahtar');
  }
  // Havuz boyuyla aralarında asal bir adım, üç farklı sırayı garanti eder.
  final l = havuz.length, h = _karma(i, 3);
  var adim = 1 + (h >> 8) % (l - 1);
  while (adim.gcd(l) != 1) {
    adim++;
  }
  return [for (var j = 0; j < 3; j++) havuz[(h + j * adim) % l]];
}

/// Bit maskesini Roma rakamlı öncül listesi olarak yazar: 1 → "Yalnız I",
/// 5 → "I ve III", 7 → "I, II ve III".
String kumeYazimi(int maske) {
  const romen = ['I', 'II', 'III', 'IV', 'V', 'VI'];
  final ogeler = [
    for (var j = 0; j < romen.length; j++)
      if (maske & (1 << j) != 0) romen[j],
  ];
  if (ogeler.isEmpty) throw StateError('Boş küme');
  if (ogeler.length == 1) return 'Yalnız ${ogeler.first}';
  return '${ogeler.sublist(0, ogeler.length - 1).join(', ')} ve ${ogeler.last}';
}
