// Lise metin aileleri · Veri, sayma ve olasılık alanı: permütasyon,
// kombinasyon, binom, olasılık, merkezî eğilim ve yayılım ölçüleri, kümeler,
// önermeler, modüler aritmetik ve finansal matematik (20 aile × 5.000 vaka).
import 'denge.dart';
import 'ortak.dart';

// ---------------------------------------------------------------------------
// Ortak yardımcılar
// ---------------------------------------------------------------------------

int _fakt(int n) {
  var r = 1;
  for (var i = 2; i <= n; i++) {
    r *= i;
  }
  return r;
}

/// P(n, r) = n·(n − 1)·…·(n − r + 1).
int _perm(int n, int r) {
  if (r < 0 || r > n) return 0;
  var x = 1;
  for (var i = 0; i < r; i++) {
    x *= n - i;
  }
  return x;
}

int _komb(int n, int r) => kombinasyonSayisi(n, r);

/// lmAile koordinatlarından (a, b, c) vakanın sıra numarası.
int _no(int a, int b, int c) => a + 25 * b + 500 * c;

int _kuvvet(int x, int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= x;
  }
  return r;
}

/// n + (n − 1) + … + (n − r + 1): çarpım yerine toplama hatası.
int _carpimToplam(int n, int r) {
  var t = 0;
  for (var i = 0; i < r; i++) {
    t += n - i;
  }
  return t;
}

/// "7·6·5" biçiminde azalan çarpım.
String _carpimYaz(int n, int r) =>
    r <= 0 ? '1' : [for (var i = 0; i < r; i++) '${n - i}'].join('·');

const _ustRakam = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];

/// Üst simge olarak yazılmış doğal sayı.
String _ust(int n) => '$n'.split('').map((d) => _ustRakam[int.parse(d)]).join();

/// Negatif sayıyı eksi işaretiyle (−) yazar.
String _eksi(int x) => x < 0 ? '−${-x}' : '$x';

/// Negatif sayıyı işlem içinde parantezle yazar.
String _par(int x) => x < 0 ? '(−${-x})' : '$x';

/// "6/8 = 3/4" yazımı; kesir zaten sade ise yalnız "3/4".
String _sade(int n, int d) {
  final k = kesir(n, d);
  return k == '$n/$d' ? k : '$n/$d = $k';
}

const _adlar = [
  'Defne', 'Kerem', 'Elif', 'Mert', 'Zeynep', 'Emre', 'Selin', 'Burak',
  'İpek', 'Onur', 'Ceren', 'Tolga', 'Nehir', 'Kaan',
];

/// Olasılık yanıtlı soru: çeldiriciler 0 ile 1 arasındaki sade kesirlerdir.
AdvancedItem _olasilik(
  String prompt,
  int n,
  int d,
  Iterable<(int, int)> alternatives,
  String explanation,
) {
  final pool = [
    ...alternatives,
    (d - n, d),
    (n + 1, d),
    (n - 1, d),
    (n, d + 1),
    (n + 2, d),
    (n, d + 2),
    (n - 2, d),
    (n, d + 3),
    (n, d + 4),
  ].where((x) => x.$2 > 0 && x.$1 > 0 && x.$1 < x.$2);
  return secenekli(
    prompt,
    kesir(n, d),
    pool.map((x) => kesir(x.$1, x.$2)),
    explanation,
  );
}

final _sozcukAyrac = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

Set<String> _sozcukKumesi(String s) =>
    s.toLowerCase().split(_sozcukAyrac).where((w) => w.isNotEmpty).toSet();

/// Seçeneklerden ilki (anahtar), sözcük ya da sayı parçalarını ötekilerle en
/// çok paylaşan tek seçenek mi? (Jaccard benzerliklerinin toplamıyla.)
bool _anahtarEnBenzer(List<String> secenekler) {
  final k = [for (final s in secenekler) _sozcukKumesi(s)];
  final puan = [
    for (var a = 0; a < k.length; a++)
      [
        for (var b = 0; b < k.length; b++)
          if (b != a)
            k[a].union(k[b]).isEmpty
                ? 0.0
                : k[a].intersection(k[b]).length / k[a].union(k[b]).length,
      ].fold<double>(0, (t, x) => t + x),
  ];
  var enb = puan.first;
  for (final p in puan) {
    if (p > enb) enb = p;
  }
  return (puan.first - enb).abs() < 1e-9 &&
      puan.where((p) => (p - enb).abs() < 1e-9).length == 1;
}

/// Olasılık yanıtlı soru: çeldiriciler 0 ile 1 arasındaki sade kesirlerdir.
/// [adaylar] tipik hatalardır (öncelik sırasıyla); komşu kesirler yalnız
/// farklı tipik aday üçten azsa eklenir. Anahtarın değer sırası olası sıralar
/// arasında düzgün dağıtılır; aynı sırayı veren üçlüler arasında, anahtarın
/// sayı parçalarını ötekilerle en çok paylaşan tek seçenek olmadığı ilk üçlü
/// seçilir.
AdvancedItem _olasilikSirali(
  String prompt,
  int n,
  int d,
  Iterable<(int, int)> adaylar,
  String aciklama,
  int i,
) {
  final anahtar = n / d, yazim = kesir(n, d);
  final aday = <(double, String)>[];
  void ekle((int, int) x) {
    final (p, q) = x;
    if (q <= 0 || p <= 0 || p >= q) return;
    final v = p / q;
    if ((v - anahtar).abs() < 1e-12 ||
        aday.any((y) => (y.$1 - v).abs() < 1e-12)) {
      return;
    }
    aday.add((v, kesir(p, q)));
  }

  adaylar.forEach(ekle);
  if (aday.length < 3) {
    [
      (d - n, d),
      (n + 1, d),
      (n - 1, d),
      (n, d + 1),
      (n + 2, d),
      (n, d + 2),
      (n - 2, d),
      (n, d + 3),
      (n, d + 4),
    ].forEach(ekle);
  }
  final ust = aday.where((x) => x.$1 > anahtar).length;
  final alt = aday.length - ust;
  final lo = ust >= 3 ? 0 : 3 - ust, hi = alt >= 3 ? 3 : alt;
  final sira = _araliktaSira(i, lo, hi);
  List<String>? ilk;
  for (var x = 0; x < aday.length; x++) {
    for (var y = x + 1; y < aday.length; y++) {
      for (var z = y + 1; z < aday.length; z++) {
        final uc = [aday[x], aday[y], aday[z]];
        if (uc.where((e) => e.$1 < anahtar).length != sira) continue;
        final yazimlar = [for (final e in uc) e.$2];
        ilk ??= yazimlar;
        if (!_anahtarEnBenzer([yazim, ...yazimlar])) {
          return AdvancedItem(prompt, yazim, yazimlar, aciklama);
        }
      }
    }
  }
  return AdvancedItem(prompt, yazim, ilk!, aciklama);
}

/// İşaretli tam sayı yanıtlı soru (negatifler − ile yazılır). Vakaların
/// dörtte birinde seçenekler iki ± çiftidir (anahtar, ters işaretlisi ve bir
/// hata değerinin iki işaretlisi); ötekilerde mutlak değerleri farklı dört
/// sayıdır. Kip vakadan bağımsız seçildiği için ± eşleşmesi anahtarı
/// göstermez. Anahtarın değer sırası olası sıralar arasında düzgün dağıtılır
/// ve anahtar, işareti tek olan seçenek olarak kalmaz.
AdvancedItem _isaretliSirali(
  String prompt,
  int yanit,
  Iterable<int> adaylar,
  String aciklama,
  int i,
) {
  final tipik = <int>[];
  void ekle(int x) {
    if (x != 0 &&
        x.abs() != yanit.abs() &&
        !tipik.any((y) => y.abs() == x.abs())) {
      tipik.add(x);
    }
  }

  adaylar.forEach(ekle);
  if (hedefSira(i, 1) == 0 && tipik.isNotEmpty) {
    final kucuk = hedefSira(i) < 2;
    final e = tipik
        .firstWhere(
          (x) => (x.abs() < yanit.abs()) == kucuk,
          orElse: () => tipik.first,
        )
        .abs();
    return AdvancedItem(prompt, _eksi(yanit), [
      _eksi(-yanit),
      _eksi(e),
      _eksi(-e),
    ], aciklama);
  }
  final adim = yanit.abs() >= 200 ? 10 : (yanit.abs() >= 40 ? 5 : 1);
  for (var k = 1; tipik.length < 3; k++) {
    ekle(yanit + k * adim);
    ekle(yanit - k * adim);
  }
  final negatif = yanit < 0;
  bool ayni(int x) => (x < 0) == negatif;
  final ust = tipik.where((x) => x > yanit).toList();
  final alt = tipik.where((x) => x < yanit).toList();
  final lo0 = ust.length >= 3 ? 0 : 3 - ust.length;
  final hi0 = alt.length >= 3 ? 3 : alt.length;
  var lo = lo0, hi = hi0;
  if (!ust.any(ayni) && alt.any(ayni) && lo < 1) lo = 1;
  if (!alt.any(ayni) && ust.any(ayni) && hi > 2) hi = 2;
  if (lo > hi) (lo, hi) = (lo0, hi0);
  final sira = _araliktaSira(i, lo, hi);
  List<String> sec(List<int> xs) => siraliCeldiriciler(yanit, _eksi(yanit), [
    for (final x in xs) (x, _eksi(x)),
  ], sira);
  var secilen = sec(tipik);
  if (!secilen.any((s) => s.startsWith('−') == negatif)) {
    secilen = sec([...tipik.where(ayni), ...tipik.where((x) => !ayni(x))]);
  }
  return AdvancedItem(prompt, _eksi(yanit), secilen, aciklama);
}

/// Yüzde yanıtlı soru (%25 biçiminde).
AdvancedItem _yuzdeli(
  String prompt,
  int answer,
  Iterable<int> alternatives,
  String explanation,
) {
  final pool = [
    ...alternatives,
    answer + 5,
    answer - 5,
    answer + 10,
    answer + 2,
    answer + 15,
    answer + 20,
    answer - 10,
    answer - 2,
  ].where((x) => x > 0 && x < 100);
  return secenekli(prompt, '%$answer', pool.map((x) => '%$x'), explanation);
}

/// Pozitif tam sayı yanıtlı soru; anahtarın değer sırası [sira] (0 … 3) ile
/// seçilir. [adaylar] tipik hata değerleridir (anahtarın iki yanından,
/// öncelik sırasıyla). Bir yanda yeterli tipik aday yoksa öteki yandakilerle
/// tamamlanır; komşu değerler yalnız farklı tipik aday üçten azsa eklenir.
AdvancedItem _tamSirali(
  String prompt,
  int yanit,
  Iterable<int> adaylar,
  String aciklama,
  int sira, {
  String unit = '',
}) {
  final tipik = <int>[];
  for (final x in adaylar) {
    if (x > 0 && x != yanit && !tipik.contains(x)) tipik.add(x);
  }
  final adim = yanit >= 200 ? 10 : (yanit >= 40 ? 5 : 1);
  final aday = [
    ...tipik,
    if (tipik.length < 3)
      for (var k = 1; k <= 6; k++) ...[yanit + k * adim, yanit - k * adim],
  ].where((x) => x > 0);
  final yazim = birimli('$yanit', unit);
  return AdvancedItem(
    prompt,
    yazim,
    siraliCeldiriciler(yanit, yazim, [
      for (final x in aday) (x, birimli('$x', unit)),
    ], sira),
    aciklama,
  );
}

/// Olası sıralar [alt, ust] arasından [i] için düzgün dağılmış bir sıra
/// (iki bağımsız karmadan 16 değer).
int _araliktaSira(int i, int alt, int ust) =>
    alt + (hedefSira(i) * 4 + hedefSira(i, 7)) % (ust - alt + 1);

/// Pozitif tam sayı yanıtlı soru. [adaylar] tipik hatalardır; anahtarın
/// değer sırası, bu adaylarla ulaşılabilen sıralar arasında düzgün (ya da
/// [agirlik] verilirse ağırlıklı) dağıtılır. Komşu değerler yalnız farklı
/// tipik aday üçten azsa eklenir.
AdvancedItem _tamAralikli(
  String prompt,
  int yanit,
  Iterable<int> adaylar,
  String aciklama,
  int i, {
  String unit = '',
  List<int>? agirlik,
}) {
  final tipik = <int>[];
  for (final x in adaylar) {
    if (x > 0 && x != yanit && !tipik.contains(x)) tipik.add(x);
  }
  if (tipik.length < 3) {
    final adim = yanit >= 200 ? 10 : (yanit >= 40 ? 5 : 1);
    for (var k = 1; k <= 6; k++) {
      for (final x in [yanit + k * adim, yanit - k * adim]) {
        if (x > 0 && !tipik.contains(x)) tipik.add(x);
      }
    }
  }
  final ust = tipik.where((x) => x > yanit).length;
  final alt = tipik.length - ust;
  final lo = ust >= 3 ? 0 : 3 - ust, hi = alt >= 3 ? 3 : alt;
  final sira = agirlik == null
      ? _araliktaSira(i, lo, hi)
      : _agirlikliSira(i, lo, hi, agirlik);
  final yazim = birimli('$yanit', unit);
  return AdvancedItem(
    prompt,
    yazim,
    siraliCeldiriciler(yanit, yazim, [
      for (final x in tipik) (x, birimli('$x', unit)),
    ], sira),
    aciklama,
  );
}

/// [i] için [alt, ust] arasından ağırlıklı bir sıra seçer; [agirlik] dört
/// sıranın göreli ağırlıklarıdır (iki bağımsız karmadan 16 değer).
int _agirlikliSira(int i, int alt, int ust, List<int> agirlik) {
  final h = hedefSira(i) * 4 + hedefSira(i, 7);
  var toplam = 0;
  for (var r = alt; r <= ust; r++) {
    toplam += agirlik[r];
  }
  var birikim = 0;
  for (var r = alt; r <= ust; r++) {
    birikim += agirlik[r];
    if (16 * birikim > h * toplam) return r;
  }
  return ust;
}

/// Tam sayı yanıtlı, ondalıklı çeldiricilere izin veren soru. [adaylar]
/// (pay, payda) biçiminde tipik hata değerleridir; en çok iki ondalık
/// basamakla tam yazılabilenler kullanılır. Anahtarın değer sırası olası
/// sıralar arasından [agirlik] ile seçilir; anahtar tek tam sayılı seçenek
/// kalmasın diye en az bir çeldiricisi tam sayı olan ilk üçlü yeğlenir.
AdvancedItem _ondalikAralikli(
  String prompt,
  int yanit,
  Iterable<(int, int)> adaylar,
  String aciklama,
  int i,
  List<int> agirlik,
) {
  final aday = <(double, String)>[];
  void ekle(int p, int q) {
    if (q <= 0 || p <= 0 || (p * 100) % q != 0) return;
    final v = p / q;
    if ((v - yanit).abs() < 1e-9 ||
        aday.any((y) => (y.$1 - v).abs() < 1e-9)) {
      return;
    }
    aday.add((v, tr(v)));
  }

  for (final (p, q) in adaylar) {
    ekle(p, q);
  }
  for (var k = 1; aday.length < 3; k++) {
    ekle(yanit + k, 1);
    ekle(yanit - k, 1);
  }
  final ust = aday.where((x) => x.$1 > yanit).length;
  final alt = aday.length - ust;
  final sira = _agirlikliSira(
    i,
    ust >= 3 ? 0 : 3 - ust,
    alt >= 3 ? 3 : alt,
    agirlik,
  );
  List<String>? ilk;
  for (var x = 0; x < aday.length; x++) {
    for (var y = x + 1; y < aday.length; y++) {
      for (var z = y + 1; z < aday.length; z++) {
        final uc = [aday[x], aday[y], aday[z]];
        if (uc.where((e) => e.$1 < yanit).length != sira) continue;
        final yazimlar = [for (final e in uc) e.$2];
        ilk ??= yazimlar;
        if (yazimlar.any((s) => !s.contains(','))) {
          return AdvancedItem(prompt, '$yanit', yazimlar, aciklama);
        }
      }
    }
  }
  return AdvancedItem(prompt, '$yanit', ilk!, aciklama);
}

/// Bölünebiliyorsa a / b, bölünemiyorsa 0 (0 aday olarak elenir).
int _tamBol(int a, int b) => b != 0 && a % b == 0 ? a ~/ b : 0;

// ---------------------------------------------------------------------------
// 1. Permütasyon ve koşullu sıralama
// ---------------------------------------------------------------------------

const _gorevBaglamlari = [
  (
    on: 'üyeli bir satranç kulübünde üyeler arasından',
    kisi: 'üye',
    roller: ['başkan', 'başkan yardımcısı', 'sayman', 'sekreter'],
  ),
  (
    on: 'oyuncusu bulunan bir spor kulübünde oyuncular arasından',
    kisi: 'oyuncu',
    roller: ['kaptan', 'kaptan yardımcısı', 'sözcü', 'malzeme sorumlusu'],
  ),
  (
    on: 'öğrencinin bulunduğu bir sınıfta öğrenciler arasından',
    kisi: 'öğrenci',
    roller: [
      'sınıf başkanı',
      'başkan yardımcısı',
      'kitaplık sorumlusu',
      'pano sorumlusu',
    ],
  ),
  (
    on: 'çalışanı olan bir atölyede çalışanlar arasından',
    kisi: 'çalışan',
    roller: [
      'ustabaşı',
      'vardiya sorumlusu',
      'depo sorumlusu',
      'kalite sorumlusu',
    ],
  ),
  (
    on: 'gönüllünün katıldığı bir çevre projesinde gönüllüler arasından',
    kisi: 'gönüllü',
    roller: ['proje lideri', 'lider yardımcısı', 'yazman', 'sözcü'],
  ),
  (
    on: 'üyesi olan bir tiyatro topluluğunda üyeler arasından',
    kisi: 'üye',
    roller: [
      'yönetmen',
      'yönetmen yardımcısı',
      'sahne amiri',
      'ışık sorumlusu',
    ],
  ),
  (
    on: 'üyesi olan bir dağcılık kulübünde üyeler arasından',
    kisi: 'dağcı',
    roller: ['ekip lideri', 'rehber', 'telsiz sorumlusu', 'sağlık sorumlusu'],
  ),
  (
    on: 'öğrencinin üye olduğu bir bilim kulübünde üyeler arasından',
    kisi: 'öğrenci',
    roller: [
      'kulüp başkanı',
      'başkan yardımcısı',
      'laboratuvar sorumlusu',
      'arşiv sorumlusu',
    ],
  ),
  (
    on: 'kişilik bir izci grubunda izciler arasından',
    kisi: 'izci',
    roller: [
      'grup lideri',
      'lider yardımcısı',
      'kamp sorumlusu',
      'bayrak sorumlusu',
    ],
  ),
  (
    on: 'görevlisi olan bir kütüphanede görevliler arasından',
    kisi: 'görevli',
    roller: [
      'müdür',
      'müdür yardımcısı',
      'arşiv sorumlusu',
      'ödünç servisi sorumlusu',
    ],
  ),
];

/// (seçilecek kişi sayısı, koşul türü) ikilileri.
const _permKosullari = [
  (2, 0), (2, 2), (2, 3), (2, 4),
  (3, 0), (3, 1), (3, 2), (3, 3), (3, 4), (3, 5), (3, 6), (3, 7),
  (4, 0), (4, 1), (4, 2), (4, 3), (4, 4), (4, 5), (4, 6), (4, 7),
];

AdvancedItem _permutasyon(int a, int b, int c) {
  final ctx = _gorevBaglamlari[c];
  final n = 5 + a + c % 5; // 5 … 33 kişi
  final (r, k) = _permKosullari[b];
  final roller = ctx.roller.sublist(0, r);
  final onceki = roller.sublist(0, r - 1).map((x) => 'bir $x').join(', ');
  final rolYazi = '$onceki ve bir ${roller[r - 1]}';
  final ilk = roller.first, son = roller.last;
  final ad1 = sec(_adlar, a + 2 * b + c), ad2 = sec(_adlar, a + 2 * b + c + 5);
  final kisi = ctx.kisi;
  final giris =
      '$n ${ctx.on} $rolYazi seçilecektir. Bir kişi en çok bir göreve '
      'getirilebilecektir.';
  const soru = 'Buna göre bu seçim kaç farklı şekilde yapılabilir?';
  final pnr = _perm(n, r), q = _perm(n - 1, r - 1);
  final String kosul, aciklama;
  final int yanit;
  // Tipik hatalar anahtarın iki yanından; sıra hedefSira ile seçilir.
  final List<int> yanlis;
  switch (k) {
    case 0:
      kosul = '';
      yanit = pnr;
      yanlis = [
        _komb(n, r), // sıra önemsenmez
        _kuvvet(n, r), // aynı kişi birden çok göreve
        _perm(n - 1, r),
        _perm(n, r + 1), // bir çarpan fazla
        _perm(n, r - 1) * (n - r),
        _perm(n + 1, r),
        _carpimToplam(n, r), // çarpım yerine toplama
      ];
      aciklama =
          'Görevler farklı olduğu için sıra önemlidir: P($n, $r) = '
          '${_carpimYaz(n, r)} = $pnr.';
    case 1:
      kosul = ' $ad1 adlı $kisi mutlaka $ilk olacaktır.';
      yanit = q;
      yanlis = [
        _perm(n, r - 1), // kişi havuzdan çıkarılmaz
        _komb(n - 1, r - 1), // sıra önemsenmez
        r * q, // her göreve getirilebilir sanılır
        _perm(n - 2, r - 1), // bir kişi fazla çıkarılır
        _perm(n - 1, r), // görev havuzdan çıkarılmaz
        _perm(n - 1, r - 2),
        pnr,
        _carpimToplam(n - 1, r - 1),
      ];
      aciklama =
          '$ad1 için tek seçenek vardır. Kalan ${r - 1} görev kalan ${n - 1} '
          'kişiye P(${n - 1}, ${r - 1}) = ${_carpimYaz(n - 1, r - 1)} = $yanit '
          'farklı şekilde dağıtılır.';
    case 2:
      kosul = ' $ad1 adlı $kisi bu görevlerden birine mutlaka getirilecektir.';
      yanit = r * q;
      yanlis = [
        q, // görev sayısıyla çarpılmaz
        pnr,
        r + q, // çarpma yerine toplama
        _perm(n - 1, r),
        r * _perm(n - 2, r - 1), // bir kişi fazla çıkarılır
        r * _perm(n, r - 1), // kişi havuzdan çıkarılmaz
        r * _komb(n - 1, r - 1),
        r * _kuvvet(n - 1, r - 1), // aynı kişi birden çok göreve
      ];
      aciklama =
          '$ad1 için $r görev seçeneği vardır. Kalan ${r - 1} görev kalan '
          '${n - 1} kişiye P(${n - 1}, ${r - 1}) = ${_perm(n - 1, r - 1)} '
          'şekilde dağıtılır: $r·${_perm(n - 1, r - 1)} = $yanit.';
    case 3:
      kosul = ' $ad1 adlı $kisi bu görevlerin hiçbirine getirilmeyecektir.';
      yanit = _perm(n - 1, r);
      yanlis = [
        pnr,
        q,
        pnr - q,
        _komb(n - 1, r), // sıra önemsenmez
        _kuvvet(n - 1, r), // aynı kişi birden çok göreve
        _perm(n - 2, r), // bir kişi fazla çıkarılır
        r * q, // görev alan seçimler sayılır
        n * _perm(n - 2, r - 1), // yalnız bir görevden çıkarılır
        _carpimToplam(n - 1, r),
      ];
      aciklama =
          '$ad1 dışarıda bırakılır; görevler kalan ${n - 1} kişiye '
          'P(${n - 1}, $r) = ${_carpimYaz(n - 1, r)} = $yanit farklı şekilde '
          'dağıtılır.';
    case 4:
      kosul =
          ' $ad1 adlı $kisi $ilk olmayacak, ancak öteki görevlere '
          'getirilebilecektir.';
      yanit = pnr - q;
      yanlis = [
        _perm(n - 1, r), // kişi hiç görev almaz sanılır
        pnr,
        q,
        (n - 1) * _perm(n, r - 1), // ilk görevlisi havuzdan çıkarılmaz
        _komb(n - 1, r), // sıra önemsenmez
        pnr + q, // çıkarma yerine toplama
        (n - 1) * _perm(n - 2, r - 1), // bir kişi fazla çıkarılır
        (n - 1) * _kuvvet(n, r - 1), // aynı kişi birden çok göreve
        _kuvvet(n, r) - q,
        (n - 1) + _carpimToplam(n - 1, r - 1), // çarpım yerine toplama
      ];
      aciklama =
          'Tüm seçimler P($n, $r) = $pnr tanedir. $ad1 adlı kişinin $ilk '
          'olduğu seçimler P(${n - 1}, ${r - 1}) = ${_perm(n - 1, r - 1)} '
          'tanedir. Fark: $pnr − ${_perm(n - 1, r - 1)} = $yanit.';
    case 5:
      kosul =
          ' $ad1 ve $ad2 adlı iki $kisi bu görevlerden birer tanesine '
          'mutlaka getirilecektir.';
      yanit = _perm(r, 2) * _perm(n - 2, r - 2);
      yanlis = [
        _perm(n - 2, r - 2),
        r * r * _perm(n - 2, r - 2), // ikisi aynı göreve de yazılır
        _komb(r, 2) * _perm(n - 2, r - 2),
        pnr,
        2 * _perm(n - 2, r - 2),
        _perm(r, 2) * _perm(n, r - 2), // iki kişi havuzdan çıkarılmaz
        _perm(r, 2) * _perm(n - 2, r - 1), // bir çarpan fazla
      ];
      aciklama =
          'İki kişi $r görevden ikisine P($r, 2) = ${_perm(r, 2)} şekilde '
          'yerleşir. Kalan ${r - 2} görev kalan ${n - 2} kişiye '
          'P(${n - 2}, ${r - 2}) = ${_perm(n - 2, r - 2)} şekilde dağıtılır: '
          '${_perm(r, 2)}·${_perm(n - 2, r - 2)} = $yanit.';
    case 6:
      kosul = ' $ad1 adlı $kisi ya $ilk ya da $son olacaktır.';
      yanit = 2 * q;
      yanlis = [
        q, // iki görev seçeneği unutulur
        r * q, // her göreve getirilebilir sanılır
        2 + q, // çarpma yerine toplama
        pnr,
        2 * _perm(n - 2, r - 1), // bir kişi fazla çıkarılır
        2 * _perm(n, r - 1), // kişi havuzdan çıkarılmaz
        2 * _komb(n - 1, r - 1), // sıra önemsenmez
        2 * _kuvvet(n - 1, r - 1), // aynı kişi birden çok göreve
      ];
      aciklama =
          '$ad1 için 2 görev seçeneği vardır. Kalan ${r - 1} görev kalan '
          '${n - 1} kişiye P(${n - 1}, ${r - 1}) = ${_perm(n - 1, r - 1)} '
          'şekilde dağıtılır: 2·${_perm(n - 1, r - 1)} = $yanit.';
    default:
      kosul =
          ' $ad1 adlı $kisi mutlaka $ilk olacak, $ad2 adlı $kisi ise hiçbir '
          'göreve getirilmeyecektir.';
      yanit = _perm(n - 2, r - 1);
      yanlis = [
        q, // ikinci kişi dışarıda bırakılmaz
        _perm(n - 2, r - 2),
        _perm(n - 2, r), // görev havuzdan çıkarılmaz
        _komb(n - 2, r - 1), // sıra önemsenmez
        _perm(n - 3, r - 1), // bir kişi fazla çıkarılır
        _perm(n, r - 1),
        _kuvvet(n - 2, r - 1), // aynı kişi birden çok göreve
        _carpimToplam(n - 2, r - 1), // çarpım yerine toplama
      ];
      aciklama =
          '$ad1 için tek seçenek vardır, $ad2 dışarıda kalır. Kalan ${r - 1} '
          'görev kalan ${n - 2} kişiye P(${n - 2}, ${r - 1}) = '
          '${_carpimYaz(n - 2, r - 1)} = $yanit farklı şekilde dağıtılır.';
  }
  return _tamSirali(
    '$giris$kosul $soru',
    yanit,
    yanlis,
    aciklama,
    hedefSira(_no(a, b, c)),
  );
}

// ---------------------------------------------------------------------------
// 2. Tekrarlı permütasyon ve dairesel sıralama
// ---------------------------------------------------------------------------

/// En az dört farklı harfi olan ve en az bir harfi yinelenen sözcükler.
const _yinelenenSozcukler = [
  'KELEBEK', 'MATEMATİK', 'PAPATYA', 'ANKARA', 'MALATYA',
  'ERZURUM', 'SAKARYA', 'KARAMAN', 'ISPARTA', 'KÜTAHYA',
  'MANİSA', 'ERZİNCAN', 'ÇANAKKALE', 'KIRIKKALE', 'ESKİŞEHİR',
  'GAZİANTEP', 'NEVŞEHİR', 'AMASYA', 'ARDAHAN', 'BATMAN',
  'BAYBURT', 'BİLECİK', 'BİTLİS', 'ÇANKIRI', 'DENİZLİ',
  'EDİRNE', 'HAKKARİ', 'KARABÜK', 'SAMSUN', 'TOKAT',
  'YALOVA', 'ŞANLIURFA', 'KARINCA', 'ARKADAŞ', 'KİTAPLIK',
  'TELEFON', 'PENCERE', 'ANAHTAR', 'KALEMLİK', 'SALATALIK',
  'PORTAKAL', 'MANDALİNA', 'LİMONATA', 'DONDURMA', 'BARDAK',
  'SANDALYE', 'KELİME', 'DEFTER', 'ÖĞRETMEN', 'GEOMETRİ',
];

const _harfCiftleri = [(0, 1), (1, 0), (0, 2), (2, 0), (1, 2), (2, 1), (0, 3)];

/// Çoklu küme dizilişi: (Σk)! / (k₁!·k₂!·…).
int _cokluDizilis(List<int> adetler) {
  var kalan = adetler.fold<int>(0, (x, y) => x + y), sonuc = 1;
  for (final k in adetler) {
    sonuc *= _komb(kalan, k);
    kalan -= k;
  }
  return sonuc;
}

/// "7!/(2!·3!)" biçiminde yazım; yinelenen yoksa yalnız "7!".
String _cokluYaz(List<int> adetler) {
  final n = adetler.fold<int>(0, (x, y) => x + y);
  final payda = [for (final k in adetler) if (k > 1) '$k!'];
  if (payda.isEmpty) return '$n!';
  return payda.length == 1 ? '$n!/${payda[0]}' : '$n!/(${payda.join('·')})';
}

const _ozdesBaglamlari = [
  (
    renkler: ['kırmızı', 'mavi', 'sarı'],
    nesne: 'boncuk',
    cogulGen: 'boncukların',
    eylem: 'bir ipe yan yana dizilecektir',
  ),
  (
    renkler: ['yeşil', 'beyaz', 'turuncu'],
    nesne: 'bayrak',
    cogulGen: 'bayrakların',
    eylem: 'gergin bir ipe yan yana asılacaktır',
  ),
  (
    renkler: ['mor', 'pembe', 'lacivert'],
    nesne: 'saksı',
    cogulGen: 'saksıların',
    eylem: 'bir pencere önüne yan yana dizilecektir',
  ),
  (
    renkler: ['kırmızı', 'yeşil', 'beyaz'],
    nesne: 'ampul',
    cogulGen: 'ampullerin',
    eylem: 'bir süs kablosuna yan yana takılacaktır',
  ),
  (
    renkler: ['siyah', 'gri', 'turkuaz'],
    nesne: 'kupa',
    cogulGen: 'kupaların',
    eylem: 'bir rafa yan yana dizilecektir',
  ),
];

const _halkaBaglamlari = [
  (
    g1: 'kız öğrenci',
    g2: 'erkek öğrenci',
    g1Gen: 'kız öğrencilerin',
    g2Gen: 'erkek öğrencilerin',
    de: 'de',
    lider: 'öğretmen',
  ),
  (
    g1: 'doktor',
    g2: 'hemşire',
    g1Gen: 'doktorların',
    g2Gen: 'hemşirelerin',
    de: 'de',
    lider: 'eczacı',
  ),
  (
    g1: 'kemancı',
    g2: 'gitarist',
    g1Gen: 'kemancıların',
    g2Gen: 'gitaristlerin',
    de: 'de',
    lider: 'solist',
  ),
  (
    g1: 'yüzücü',
    g2: 'atlet',
    g1Gen: 'yüzücülerin',
    g2Gen: 'atletlerin',
    de: 'de',
    lider: 'antrenör',
  ),
  (
    g1: 'mühendis',
    g2: 'mimar',
    g1Gen: 'mühendislerin',
    g2Gen: 'mimarların',
    de: 'da',
    lider: 'stajyer',
  ),
];

/// Listenin en büyük ögesi.
int _enBuyuk(List<int> xs) => xs.reduce((x, y) => x > y ? x : y);

AdvancedItem _sozcukDizilisi(int a, int b, int c, int sira) {
  final w = _yinelenenSozcukler[a + 25 * c];
  final harfler = w.split('');
  final n = harfler.length;
  final farkli = <String>[];
  for (final h in harfler) {
    if (!farkli.contains(h)) farkli.add(h);
  }
  if (farkli.length < 4 || farkli.length == n) {
    throw StateError('Uygun olmayan sözcük: $w');
  }
  List<int> adet({String? eksik1, String? eksik2}) {
    final m = {for (final h in farkli) h: harfler.where((x) => x == h).length};
    if (eksik1 != null) m[eksik1] = m[eksik1]! - 1;
    if (eksik2 != null) m[eksik2] = m[eksik2]! - 1;
    return [for (final h in farkli) if (m[h]! > 0) m[h]!];
  }

  final tum = adet();
  final toplam = _cokluDizilis(tum);
  // Tipik hata hesapları için harf adetlerinin çarpımları.
  final adetCarpimi = tum.fold<int>(1, (x, k) => x * k);
  final faktCarpimi = tum.fold<int>(1, (x, k) => x * _fakt(k));
  final yinelenenHarf = tum.where((k) => k > 1).fold<int>(0, (x, k) => x + k);
  final yinelenen = [
    for (final h in farkli)
      if (harfler.where((x) => x == h).length > 1)
        '$h harfi ${harfler.where((x) => x == h).length} kez',
  ].join(', ');
  final giris =
      '“$w” sözcüğünün harflerinin tümü kullanılarak anlamlı ya da anlamsız, '
      '$n harfli sözcükler yazılacaktır.';
  final genel =
      '“$w” sözcüğünde $n harf vardır ve $yinelenen geçer; tüm dizilişler '
      '${_cokluYaz(tum)} = $toplam tanedir.';
  if (b == 0) {
    return _tamSirali(
      '$giris Buna göre kaç farklı sözcük yazılabilir?',
      toplam,
      [
        _fakt(n), // yinelenenlere bölünmez
        _fakt(farkli.length), // yalnız farklı harfler dizilir
        _tamBol(_fakt(n), _fakt(_enBuyuk(tum))), // yalnız bir harfe bölünür
        _komb(n, _enBuyuk(tum)), // yalnız bir harfin yerleri seçilir
        _tamBol(_fakt(n), adetCarpimi), // faktöriyel alınmaz
        _tamBol(_fakt(n - 1), faktCarpimi), // dairesel diziliş sanılır
        toplam * 2,
        _tamBol(_fakt(n), _fakt(yinelenenHarf)),
        _tamBol(toplam, 2),
      ],
      genel,
      sira,
    );
  }
  if (b <= 12) {
    final h = farkli[(b - 1) % 4];
    final kalan = adet(eksik1: h);
    final sabit = _cokluDizilis(kalan);
    final tur = (b - 1) ~/ 4;
    final kh = harfler.where((x) => x == h).length;
    // Başa yazılan harfin adedi düşülmeden yapılan bölme.
    final azaltilmadan = _tamBol(_fakt(n - 1), faktCarpimi);
    if (tur == 2) {
      return _tamSirali(
        '$giris Bu sözcüklerin kaç tanesi $h harfi ile başlamaz?',
        toplam - sabit,
        [
          toplam,
          sabit,
          if (kh > 1 && azaltilmadan > 0) toplam - azaltilmadan,
          if (kh > 1) toplam - kh * sabit,
          _fakt(n) - _fakt(n - 1),
          toplam - _fakt(n - 1),
          toplam + sabit, // çıkarma yerine toplama
          _tamBol(toplam, 2),
        ],
        '$genel $h harfi ile başlayanlar ${_cokluYaz(kalan)} = $sabit '
        'tanedir. İstenen sayı $toplam − $sabit = ${toplam - sabit} olur.',
        sira,
      );
    }
    final yer = tur == 0 ? 'başa' : 'sona';
    final fiil = tur == 0 ? 'başlar' : 'biter';
    return _tamSirali(
      '$giris Bu sözcüklerin kaç tanesi $h harfi ile $fiil?',
      sabit,
      [
        toplam,
        if (kh > 1) azaltilmadan,
        _fakt(n - 1),
        _fakt(kalan.length),
        if (kh > 1) kh * sabit, // özdeş harfler ayrı sayılır
        _komb(n - 1, _enBuyuk(kalan)),
        toplam - sabit,
        _tamBol(toplam, n),
        2 * sabit,
        _tamBol(sabit, 2),
      ],
      'Bir $h harfi $yer yazılır. Kalan ${n - 1} harf ${_cokluYaz(kalan)} = '
      '$sabit farklı biçimde dizilir.',
      sira,
    );
  }
  final (i, j) = _harfCiftleri[b - 13];
  final h1 = farkli[i], h2 = farkli[j];
  final kalan = adet(eksik1: h1, eksik2: h2);
  final sonuc = _cokluDizilis(kalan);
  return _tamSirali(
    '$giris Bu sözcüklerin kaç tanesi $h1 harfi ile başlayıp $h2 harfi ile '
    'biter?',
    sonuc,
    [
      _cokluDizilis(adet(eksik1: h1)),
      _tamBol(_fakt(n - 2), faktCarpimi), // harf adetleri düşülmez
      _cokluDizilis(adet(eksik1: h2)),
      _fakt(kalan.length),
      _fakt(n - 2),
      _komb(n - 2, _enBuyuk(kalan)),
      2 * sonuc,
      toplam,
      _tamBol(sonuc, 2),
    ],
    'Başa bir $h1, sona bir $h2 harfi yazılır. Kalan ${n - 2} harf '
    '${_cokluYaz(kalan)} = $sonuc farklı biçimde dizilir.',
    sira,
  );
}

AdvancedItem _ozdesDizilis(int a, int b, int v, int sira) {
  final ctx = _ozdesBaglamlari[b ~/ 4];
  final p = 1 + a % 5, q = 1 + a ~/ 5, s = 2 + b % 4;
  final r1 = ctx.renkler[0], r2 = ctx.renkler[1], r3 = ctx.renkler[2];
  final nesne = ctx.nesne;
  final n = p + q + s;
  final giris =
      'Renkleri dışında özdeş olan $p $r1, $q $r2 ve $s $r3 $nesne '
      '${ctx.eylem}.';
  final toplam = _cokluDizilis([p, q, s]);
  final tumYazi = '${_cokluYaz([p, q, s])} = $toplam';
  // Bir grubun yinelenmesine bölmeyi unutma hatası için (küçükten büyüğe).
  final gruplar = [p, q, s].where((g) => g >= 2 && g <= 4).toList()..sort();
  switch (v) {
    case 0:
      return _tamSirali(
        '$giris Buna göre kaç farklı diziliş elde edilebilir?',
        toplam,
        [
          if (gruplar.isNotEmpty) toplam * _fakt(gruplar.first),
          _komb(n, s), // yalnız bir rengin yerleri seçilir
          toplam * 2,
          _fakt(p) * _fakt(q) * _fakt(s),
          _komb(n, q),
          for (final g in gruplar.skip(1)) toplam * _fakt(g),
          _tamBol(toplam, n),
          _tamBol(toplam, 2),
        ],
        'Toplam $n nesne vardır; aynı renkliler özdeş olduğundan diziliş '
        'sayısı $tumYazi olur.',
        sira,
      );
    case 1:
      final kalan = [if (p > 1) p - 1, q, s];
      final x = _cokluDizilis(kalan);
      return _tamSirali(
        '$giris İlk sırada $r1 bir $nesne bulunması koşuluyla kaç farklı '
        'diziliş elde edilebilir?',
        x,
        [
          if (toplam <= 40 * x) toplam,
          if (p > 1) _tamBol(x, p), // nesne adedi düşülmez
          toplam - x,
          _komb(n - 1, s), // yalnız bir rengin yerleri seçilir
          p * x,
          _tamBol(toplam, n),
          2 * x,
          _komb(n - 1, q),
          x + s,
          _tamBol(x, 2),
        ],
        'İlk sıraya bir $r1 $nesne konur. Kalan ${n - 1} nesne '
        '${_cokluYaz(kalan)} = $x farklı biçimde dizilir.',
        sira,
      );
    case 2:
      final kalan = [if (p > 1) p - 1, q, if (s > 1) s - 1];
      final x = _cokluDizilis(kalan);
      return _tamSirali(
        '$giris İlk sırada $r1, son sırada $r3 bir $nesne bulunması koşuluyla '
        'kaç farklı diziliş elde edilebilir?',
        x,
        [
          _cokluDizilis([if (p > 1) p - 1, q, s]),
          _tamBol(x, p * s), // nesne adetleri düşülmez
          p * s * x,
          _komb(n - 2, q),
          2 * x,
          _komb(n - 2, s - 1),
          if (toplam <= 40 * x) toplam,
          _tamBol(x, 2),
        ],
        'İlk sıraya bir $r1, son sıraya bir $r3 $nesne konur. Kalan ${n - 2} '
        'nesne ${_cokluYaz(kalan)} = $x farklı biçimde dizilir.',
        sira,
      );
    case 3:
      final kalan = [if (p > 1) p - 1, q, s];
      final x = _cokluDizilis(kalan);
      return _tamSirali(
        '$giris İlk sırada $r1 bir $nesne bulunmaması koşuluyla kaç farklı '
        'diziliş elde edilebilir?',
        toplam - x,
        [
          x,
          toplam,
          _cokluDizilis([q, s]),
          if (p > 1 && x % p == 0) toplam - x ~/ p, // adet düşülmez
          _cokluDizilis([p, if (q > 1) q - 1, s]), // yalnız bir renk başta
          toplam + x, // çıkarma yerine toplama
          toplam - p * x,
          _cokluDizilis([p, q, s - 1]),
        ],
        'Tüm dizilişler $tumYazi tanedir. İlk sırada $r1 $nesne bulunanlar '
        '${_cokluYaz(kalan)} = $x tanedir. Fark: $toplam − $x = ${toplam - x}.',
        sira,
      );
    case 4:
      final x = _cokluDizilis([p, q, 1]);
      return _tamSirali(
        '$giris Buna göre $r3 ${ctx.cogulGen} tümünün yan yana gelmesi '
        'koşuluyla kaç farklı diziliş elde edilebilir?',
        x,
        [
          if (s <= 3) x * _fakt(s),
          _cokluDizilis([p, q]),
          x * s,
          p + q + 1, // yalnız bloğun yeri sayılır
          2 * x,
          if (toplam <= 40 * x) toplam,
          _tamBol(x, 2),
        ],
        '$s $r3 $nesne tek bir blok sayılır; blokla birlikte ${p + q + 1} '
        'nesne ${_cokluYaz([p, q, 1])} = $x farklı biçimde dizilir. Blok '
        'içindeki nesneler özdeş olduğu için ayrıca çarpım yapılmaz.',
        sira,
      );
    default:
      final kalan = [p, q, if (s > 2) s - 2];
      final x = _cokluDizilis(kalan);
      return _tamSirali(
        '$giris İlk iki sıranın ikisinde de $r3 $nesne bulunması koşuluyla '
        'kaç farklı diziliş elde edilebilir?',
        x,
        [
          _cokluDizilis([p, q, s - 1]),
          _tamBol(x, s * (s - 1)), // nesne adedi düşülmez
          _perm(s, 2) * x,
          _cokluDizilis([p, q]),
          2 * x,
          _komb(n - 2, s - 2),
          if (toplam <= 40 * x) toplam,
          _tamBol(x, 2),
        ],
        'İlk iki sıraya birer $r3 $nesne konur. Kalan ${n - 2} nesne '
        '${_cokluYaz(kalan)} = $x farklı biçimde dizilir.',
        sira,
      );
  }
}

AdvancedItem _daireselDizilis(int a, int b, int duzen, int sira) {
  final ctx = _halkaBaglamlari[b ~/ 4];
  final x = 2 + a % 5, y = 2 + b % 4, tur = a ~/ 5;
  final eylem = duzen == 0
      ? 'yuvarlak bir masanın etrafına oturacaktır'
      : 'bir kamp ateşinin çevresinde çember biçiminde dizilecektir';
  final ne = duzen == 0 ? 'oturma düzeni' : 'diziliş';
  final fx = _fakt(x), fy = _fakt(y);
  final String grup, kosul, aciklama;
  final int yanit;
  final List<int> yanlis;
  switch (tur) {
    case 0:
      grup = '$x ${ctx.g1} ve $y ${ctx.g2}';
      kosul = '${ctx.g2Gen} tümünün yan yana bulunması';
      yanit = fx * fy;
      yanlis = [
        _fakt(x + 1) * fy, // doğrusal sıralama
        fx, // blok içi sıralama unutulur
        _fakt(x + y - 1), // blok koşulu unutulur
        _fakt(x - 1) * fy,
        2 * fx * fy,
        fx + fy, // çarpma yerine toplama
      ];
      aciklama =
          '$y ${ctx.g2} tek blok sayılır; blokla birlikte ${x + 1} birim '
          'çember üzerinde (${x + 1} − 1)! = $fx biçimde dizilir. Blok kendi '
          'içinde $y! = $fy biçimde sıralanır: $fx·$fy = $yanit.';
    case 1:
      grup = '$x ${ctx.g1}, $y ${ctx.g2} ve 1 ${ctx.lider}';
      kosul =
          '${ctx.g1Gen} kendi aralarında, ${ctx.g2Gen} ${ctx.de} kendi '
          'aralarında yan yana bulunması';
      yanit = 2 * fx * fy;
      yanlis = [
        fx * fy,
        6 * fx * fy, // doğrusal sıralama
        2 * _fakt(x - 1) * _fakt(y - 1), // bloklar da dairesel sanılır
        _fakt(x + y), // blok koşulu unutulur
        2 * fx, // bir blok içi sıralama unutulur
        fx + fy,
        4 * fx * fy,
      ];
      aciklama =
          'İki blok ve ${ctx.lider} olmak üzere 3 birim çember üzerinde '
          '(3 − 1)! = 2 biçimde dizilir. Bloklar kendi içlerinde $x! = $fx ve '
          '$y! = $fy biçimde sıralanır: 2·$fx·$fy = $yanit.';
    case 2:
      grup = '$x ${ctx.g1} ve $y ${ctx.g2}';
      kosul =
          '${ctx.g1Gen} kendi aralarında, ${ctx.g2Gen} ${ctx.de} kendi '
          'aralarında yan yana bulunması';
      yanit = fx * fy;
      yanlis = [
        2 * fx * fy, // doğrusal sıralama
        fx + fy, // çarpma yerine toplama
        _fakt(x + y - 1), // blok koşulu unutulur
        _fakt(x - 1) * _fakt(y - 1), // bloklar da dairesel sanılır
        _fakt(x + y),
        fx, // bir blok içi sıralama unutulur
      ];
      aciklama =
          'İki blok çember üzerinde (2 − 1)! = 1 biçimde dizilir. Bloklar '
          'kendi içlerinde $x! = $fx ve $y! = $fy biçimde sıralanır: '
          '$fx·$fy = $yanit.';
    case 3:
      grup = '$x ${ctx.g1}, $y ${ctx.g2} ve 1 ${ctx.lider}';
      kosul = '${ctx.g2Gen} tümünün yan yana bulunması';
      yanit = _fakt(x + 1) * fy;
      yanlis = [
        _fakt(x + 2) * fy, // doğrusal sıralama
        fx * fy,
        _fakt(x + 1) * fy * 2,
        _fakt(x + 1), // blok içi sıralama unutulur
        _fakt(x + y), // blok koşulu unutulur
        _fakt(x + 1) + fy, // çarpma yerine toplama
      ];
      aciklama =
          '$y ${ctx.g2} tek blok sayılır; blokla birlikte ${x + 2} birim '
          'çember üzerinde ${x + 1}! = ${_fakt(x + 1)} biçimde dizilir. Blok '
          'kendi içinde $y! = $fy biçimde sıralanır: '
          '${_fakt(x + 1)}·$fy = $yanit.';
    default:
      grup = '$x ${ctx.g1}, $y ${ctx.g2} ve 2 ${ctx.lider}';
      kosul =
          '${ctx.g1Gen} kendi aralarında, ${ctx.g2Gen} ${ctx.de} kendi '
          'aralarında yan yana bulunması';
      yanit = 6 * fx * fy;
      yanlis = [
        24 * fx * fy, // doğrusal sıralama
        2 * fx * fy,
        _fakt(x + y + 1), // blok koşulu unutulur
        fx * fy,
        12 * fx * fy,
        6 * _fakt(x - 1) * _fakt(y - 1), // bloklar da dairesel sanılır
      ];
      aciklama =
          'İki blok ve iki ${ctx.lider} olmak üzere 4 birim çember üzerinde '
          '(4 − 1)! = 6 biçimde dizilir. Bloklar kendi içlerinde $x! = $fx ve '
          '$y! = $fy biçimde sıralanır: 6·$fx·$fy = $yanit.';
  }
  return _tamSirali(
    '$grup $eylem. Yalnız kişilerin birbirine göre konumları dikkate '
    'alındığına göre, $kosul koşuluyla kaç farklı $ne oluşturulabilir?',
    yanit,
    yanlis,
    aciklama,
    sira,
  );
}

AdvancedItem _tekrarliPermutasyon(int a, int b, int c) {
  final sira = hedefSira(_no(a, b, c));
  if (c < 2) return _sozcukDizilisi(a, b, c, sira);
  if (c < 8) return _ozdesDizilis(a, b, c - 2, sira);
  return _daireselDizilis(a, b, c - 8, sira);
}

// ---------------------------------------------------------------------------
// 3. Kombinasyon ve koşullu seçim
// ---------------------------------------------------------------------------

const _secimBaglamlari = [
  (
    on: 'Bir okulun münazara takımına aday olan',
    a: 'kız öğrenci',
    b: 'erkek öğrenci',
    son: 'kişilik bir takım oluşturulacaktır',
  ),
  (
    on: 'Bir hastanede görevli',
    a: 'doktor',
    b: 'hemşire',
    son: 'kişilik bir sağlık ekibi oluşturulacaktır',
  ),
  (
    on: 'Bir üniversitede görevli',
    a: 'profesör',
    b: 'doçent',
    son: 'kişilik bir jüri oluşturulacaktır',
  ),
  (
    on: 'Bir şirkette çalışan',
    a: 'mühendis',
    b: 'teknisyen',
    son: 'kişilik bir proje ekibi oluşturulacaktır',
  ),
  (
    on: 'Bir gazetede çalışan',
    a: 'muhabir',
    b: 'fotoğrafçı',
    son: 'kişilik bir haber ekibi oluşturulacaktır',
  ),
  (
    on: 'Bir spor kulübüne kayıtlı',
    a: 'yüzücü',
    b: 'atlet',
    son: 'kişilik bir kafile oluşturulacaktır',
  ),
  (
    on: 'Bir okulda görevli',
    a: 'matematik öğretmeni',
    b: 'fizik öğretmeni',
    son: 'kişilik bir komisyon oluşturulacaktır',
  ),
  (
    on: 'Bir belediyede çalışan',
    a: 'mimar',
    b: 'avukat',
    son: 'kişilik bir kurul oluşturulacaktır',
  ),
  (
    on: 'Bir orkestrada yer alan',
    a: 'kemancı',
    b: 'flütçü',
    son: 'kişilik bir oda müziği topluluğu oluşturulacaktır',
  ),
  (
    on: 'Bir araştırma merkezinde çalışan',
    a: 'kimyager',
    b: 'biyolog',
    son: 'kişilik bir çalışma grubu oluşturulacaktır',
  ),
];

/// (seçilecek kişi sayısı, koşul türü, birinci gruptan istenen kişi sayısı).
const _kombKosullari = [
  (3, 0, 0), (3, 1, 1), (3, 1, 2), (3, 2, 0), (3, 3, 0),
  (3, 4, 0), (3, 5, 0), (3, 6, 0), (3, 7, 0), (4, 0, 0),
  (4, 1, 1), (4, 1, 2), (4, 1, 3), (4, 2, 0), (4, 3, 0),
  (4, 4, 0), (4, 5, 0), (4, 6, 0), (5, 1, 2), (5, 1, 3),
];

AdvancedItem _kombinasyon(int a, int b, int c) {
  final ctx = _secimBaglamlari[c];
  final g1 = 4 + a % 5 + c % 2, g2 = 4 + a ~/ 5; // 4 … 9 ve 4 … 8
  final n = g1 + g2;
  final (r, k, j) = _kombKosullari[b];
  final ad1 = sec(_adlar, a + b + 3 * c), ad2 = sec(_adlar, a + b + 3 * c + 6);
  final giris =
      '${ctx.on} $g1 ${ctx.a} ve $g2 ${ctx.b} arasından $r ${ctx.son}.';
  const soru = 'bu seçim kaç farklı şekilde yapılabilir?';
  final cnr = _komb(n, r);
  final String kok, aciklama;
  final int yanit;
  final List<int> yanlis;
  switch (k) {
    case 0:
      kok = '$giris Buna göre $soru';
      yanit = cnr;
      yanlis = [
        _perm(n, r), // sıra gözetilir
        _komb(g1, r) + _komb(g2, r), // gruplar ayrı ayrı seçilir
        _perm(n, r) ~/ r, // r! yerine r ile bölünür
        _komb(n - 1, r),
        _komb(n + 1, r),
        _komb(n, r - 1),
      ];
      aciklama =
          'Toplam $n kişi arasından sıra gözetmeden $r kişi seçilir: '
          'C($n, $r) = $cnr.';
    case 1:
      final x = _komb(g1, j), y = _komb(g2, r - j);
      kok =
          '$giris Seçilen $r kişi arasında tam $j ${ctx.a} bulunması koşuluyla '
          '$soru';
      yanit = x * y;
      yanlis = [
        x + y, // çarpma yerine toplama
        cnr, // koşul unutulur
        _perm(g1, j) * _perm(g2, r - j), // sıra gözetilir
        _komb(g1, r - j) * _komb(g2, j), // sayılar yer değiştirir
        x * _komb(n - j, r - j), // kalanlar herkesten seçilir
        x > y ? x : y, // yalnız bir grup seçilir
        x < y ? x : y,
      ];
      aciklama =
          '$g1 ${ctx.a} arasından $j kişi C($g1, $j) = $x, $g2 ${ctx.b} '
          'arasından ${r - j} kişi C($g2, ${r - j}) = $y şekilde seçilir: '
          '$x·$y = $yanit.';
    case 2:
      final hic = _komb(g2, r);
      kok =
          '$giris Seçilen $r kişi arasında en az bir ${ctx.a} bulunması '
          'koşuluyla $soru';
      yanit = cnr - hic;
      yanlis = [
        g1 * _komb(n - 1, r - 1), // bir kişi seçilip kalanlar herkesten
        g1 * _komb(g2, r - 1), // tam bir kişi
        cnr,
        hic,
        _perm(n, r) - _perm(g2, r), // sıra gözetilir
        cnr - g1 * _komb(g2, r - 1), // yanlış tümleyen çıkarılır
        cnr + hic, // çıkarma yerine toplama
        _komb(g1, r),
      ];
      aciklama =
          'Tüm seçimler C($n, $r) = $cnr tanedir. Hiç ${ctx.a} bulunmayan '
          'seçimler C($g2, $r) = $hic tanedir. Fark: $cnr − $hic = $yanit.';
    case 3:
      kok =
          '$giris Bu kişilerden $ad1 mutlaka seçilecektir. Buna göre $soru';
      yanit = _komb(n - 1, r - 1);
      yanlis = [
        cnr, // koşul unutulur
        _komb(n - 2, r - 1), // bir kişi fazla çıkarılır
        _komb(n - 1, r), // seçilecek sayı azaltılmaz
        _komb(n - 1, r - 2),
        _komb(n, r - 1), // kişi havuzdan çıkarılmaz
        _komb(n - 2, r - 2),
        _perm(n - 1, r - 1), // sıra gözetilir
      ];
      aciklama =
          '$ad1 seçilmiş sayılır; kalan ${n - 1} kişi arasından ${r - 1} kişi '
          'daha seçilir: C(${n - 1}, ${r - 1}) = $yanit.';
    case 4:
      kok = '$giris Bu kişilerden $ad1 seçilmeyecektir. Buna göre $soru';
      yanit = _komb(n - 1, r);
      yanlis = [
        cnr, // koşul unutulur
        _komb(n - 1, r - 1), // kişi seçilmiş sayılır
        cnr - 1, // yalnız bir seçim çıkarılır
        _komb(n - 2, r), // bir kişi fazla çıkarılır
        _perm(n - 1, r), // sıra gözetilir
        _komb(n - 2, r - 1),
      ];
      aciklama =
          '$ad1 dışarıda bırakılır; kalan ${n - 1} kişi arasından $r kişi '
          'seçilir: C(${n - 1}, $r) = $yanit.';
    case 5:
      final birlikte = _komb(n - 2, r - 2);
      kok =
          '$giris Bu kişilerden $ad1 ile $ad2 birlikte seçilemeyecektir. Buna '
          'göre $soru';
      yanit = cnr - birlikte;
      yanlis = [
        _komb(n - 2, r), // ikisi de dışarıda bırakılır
        cnr, // koşul unutulur
        birlikte,
        cnr + birlikte, // çıkarma yerine toplama
        cnr - _komb(n - 2, r),
        cnr - 1, // yalnız bir seçim çıkarılır
        _komb(n - 2, r) + _komb(n - 2, r - 1), // 2 ile çarpma unutulur
      ];
      aciklama =
          'Tüm seçimler C($n, $r) = $cnr tanedir. İkisinin birlikte yer '
          'aldığı seçimler C(${n - 2}, ${r - 2}) = $birlikte tanedir. Fark: '
          '$cnr − $birlikte = $yanit.';
    case 6:
      final hic = _komb(g2, r), bir = g1 * _komb(g2, r - 1);
      kok =
          '$giris Seçilen $r kişi arasında en çok bir ${ctx.a} bulunması '
          'koşuluyla $soru';
      yanit = hic + bir;
      yanlis = [
        bir,
        cnr - hic, // en az bir ile karıştırılır
        hic,
        cnr - bir,
        hic + g1, // C(g2, r − 1) çarpanı unutulur
        hic * bir, // toplama yerine çarpma
        hic + g1 * _komb(n - 1, r - 1),
      ];
      aciklama =
          'Hiç ${ctx.a} bulunmayan seçimler C($g2, $r) = $hic, tam bir '
          '${ctx.a} bulunan seçimler $g1·C($g2, ${r - 1}) = $bir tanedir: '
          '$hic + $bir = $yanit.';
    default:
      final x = _komb(g1, r), y = _komb(g2, r);
      kok =
          '$giris Seçilenlerin tümünün ${ctx.a} ya da tümünün ${ctx.b} olması '
          'koşuluyla $soru';
      yanit = x + y;
      yanlis = [
        x * y, // toplama yerine çarpma
        x > y ? x : y, // yalnız bir grup
        cnr,
        x < y ? x : y,
        cnr - x - y,
      ];
      aciklama =
          'Tümü ${ctx.a} olan seçimler C($g1, $r) = $x, tümü ${ctx.b} olan '
          'seçimler C($g2, $r) = $y tanedir: $x + $y = $yanit.';
  }
  return _tamSirali(kok, yanit, yanlis, aciklama, hedefSira(_no(a, b, c)));
}

// ---------------------------------------------------------------------------
// 4. Binom açılımı
// ---------------------------------------------------------------------------

const _binomHarfleri = [
  ('x', 'y'), ('a', 'b'), ('p', 'q'), ('u', 'v'), ('c', 'd'),
];

/// "x³y²" biçiminde terim; 0 üslü çarpan yazılmaz, 1 üssü gösterilmez.
String _terimYaz(String x, int i, String y, int k) {
  String parca(String h, int u) => u == 0 ? '' : (u == 1 ? h : '$h${_ust(u)}');
  return '${parca(x, i)}${parca(y, k)}';
}

/// (p·x + sq·y)ⁿ açılımında xⁿ⁻ᵏyᵏ katsayısı C(n, k)·pⁿ⁻ᵏ·sqᵏ için tipik
/// hatalar, öncelik sırasıyla.
List<int> _terimHatalari(int n, int k, int p, int sq) {
  final cnk = _komb(n, k);
  return [
    _kuvvet(p, n - k) * _kuvvet(sq, k), // C(n, k) unutulur
    cnk * _kuvvet(p, k) * _kuvvet(sq, n - k), // üsler yer değiştirir
    cnk, // yalnız binom katsayısı
    _perm(n, k) * _kuvvet(p, n - k) * _kuvvet(sq, k), // C yerine P
    cnk * p * _kuvvet(sq, k), // p'nin kuvveti alınmaz
    cnk * _kuvvet(p, n - k) * sq, // q'nun kuvveti alınmaz
    n * _kuvvet(p, n - k) * _kuvvet(sq, k), // C(n, k) yerine n
    _komb(n, k + 1) * _kuvvet(p, n - k) * _kuvvet(sq, k),
    cnk * p * sq,
    _komb(n, k + 1) * _kuvvet(p, n - k - 1) * _kuvvet(sq, k + 1),
    _komb(n, k - 1) * _kuvvet(p, n - k + 1) * _kuvvet(sq, k - 1),
  ];
}

AdvancedItem _binom(int a, int b, int c) {
  final i = _no(a, b, c);
  final p = 1 + a % 5;
  final t = a ~/ 5;
  final q = t + 1 < p ? t + 1 : t + 2; // 1 … 6, p'den farklı
  final n = 3 + b % 4; // 3 … 6
  final form = b ~/ 4;
  final s = c.isEven ? 1 : -1;
  final e = c ~/ 2;
  final (hx, hy) = _binomHarfleri[e];
  final sq = s * q;
  final isaret = s > 0 ? '+' : '−';
  String kat(int k, String h) => k == 1 ? h : '$k$h';
  final ikinci = s > 0 ? kat(q, hy) : '−${kat(q, hy)}';
  String ifade(String us, {bool tek = false}) =>
      '(${kat(p, hx)} $isaret ${tek ? '$q' : kat(q, hy)})$us';
  switch (form) {
    case 0:
      final m = n - 1;
      final yanit = _kuvvet(p + sq, m);
      return _isaretliSirali(
        '${ifade(_ust(m))} ifadesinin açılımındaki katsayıların toplamı '
        'kaçtır?',
        yanit,
        [
          _kuvvet(p - sq, m), // işaret hatası
          _kuvvet(2, m), // katsayılar 1 sanılır
          _kuvvet(p, m) + _kuvvet(sq, m), // yalnız uç terimler
          m + 1, // terim sayısı
          (p + sq) * m, // kuvvet yerine çarpım
          _kuvvet(p + sq, m + 1), // üs bir fazla
          _kuvvet(p, m),
          _kuvvet(p + sq, m - 1),
        ],
        'Katsayılar toplamı için $hx = $hy = 1 yazılır: '
        '($p $isaret $q)${_ust(m)} = ${_par(p + sq)}${_ust(m)} = '
        '${_eksi(yanit)}.',
        i,
      );
    case 1:
      final k = 1 + e % (n - 1);
      final cnk = _komb(n, k);
      final yanit = cnk * _kuvvet(p, n - k) * _kuvvet(sq, k);
      return _isaretliSirali(
        '${ifade(_ust(n))} ifadesinin açılımında '
        '${_terimYaz(hx, n - k, hy, k)} çarpanını içeren terimin katsayısı '
        'kaçtır?',
        yanit,
        _terimHatalari(n, k, p, sq),
        'Genel terim C($n, k)·(${kat(p, hx)})${_ust(n)}⁻ᵏ·($ikinci)ᵏ '
        'biçimindedir. k = $k için katsayı C($n, $k)·$p${_ust(n - k)}·'
        '${_par(sq)}${_ust(k)} = $cnk·${_kuvvet(p, n - k)}·'
        '${_par(_kuvvet(sq, k))} = ${_eksi(yanit)}.',
        i,
      );
    case 2:
      final k = 1 + (e + 1) % (n - 1);
      final r = k + 1;
      final cnk = _komb(n, k);
      final yanit = cnk * _kuvvet(p, n - k) * _kuvvet(sq, k);
      final hatalar = _terimHatalari(n, k, p, sq);
      return _isaretliSirali(
        '${ifade(_ust(n))} ifadesinin açılımı $hx değişkeninin azalan '
        'kuvvetlerine göre yazıldığında baştan $r. terimin katsayısı kaçtır?',
        yanit,
        [
          _komb(n, r) * _kuvvet(p, n - r) * _kuvvet(sq, r), // k = r alınır
          ...hatalar.take(3),
          _komb(n, k - 1) * _kuvvet(p, n - k + 1) * _kuvvet(sq, k - 1),
          ...hatalar.skip(3),
        ],
        'Baştan $r. terim k = $k için elde edilir: C($n, $k)·'
        '(${kat(p, hx)})${_ust(n - k)}·($ikinci)${_ust(k)}. Katsayı '
        '$cnk·${_kuvvet(p, n - k)}·${_par(_kuvvet(sq, k))} = ${_eksi(yanit)}.',
        i,
      );
    case 3:
      final jx = e % n; // x'in üssü: 0 … n − 1
      final cnj = _komb(n, jx);
      final yanit = cnj * _kuvvet(p, jx) * _kuvvet(sq, n - jx);
      final istenen = jx == 0
          ? 'sabit terim'
          : '$hx değişkeninin üssü $jx olan terimin katsayısı';
      return _isaretliSirali(
        '${ifade(_ust(n), tek: true)} ifadesinin açılımında $istenen kaçtır?',
        yanit,
        [
          _kuvvet(p, jx) * _kuvvet(sq, n - jx), // C(n, k) unutulur
          cnj * _kuvvet(p, n - jx) * _kuvvet(sq, jx), // üsler yer değiştirir
          cnj, // yalnız binom katsayısı
          _kuvvet(p + sq, n), // katsayılar toplamı
          cnj * p * _kuvvet(sq, n - jx),
          cnj * _kuvvet(p, jx) * sq,
          n * _kuvvet(p, jx) * _kuvvet(sq, n - jx),
          _perm(n, n - jx) * _kuvvet(p, jx) * _kuvvet(sq, n - jx),
          _komb(n, jx + 1) * _kuvvet(p, jx + 1) * _kuvvet(sq, n - jx - 1),
          if (jx > 0)
            _komb(n, jx - 1) * _kuvvet(p, jx - 1) * _kuvvet(sq, n - jx + 1),
        ],
        jx == 0
            ? 'Sabit terim $hx içermeyen terimdir; k = $n için elde edilir: '
                  '${_par(sq)}${_ust(n)} = ${_eksi(yanit)}.'
            : '$hx değişkeninin üssü $jx olan terim C($n, $jx)·'
                  '(${kat(p, hx)})${_ust(jx)}·${_par(sq)}${_ust(n - jx)} '
                  'biçimindedir. Katsayı $cnj·${_kuvvet(p, jx)}·'
                  '${_par(_kuvvet(sq, n - jx))} = ${_eksi(yanit)} olur.',
        i,
      );
    default:
      final m = n - 1;
      final yanit = _kuvvet(p + sq, m);
      return _isaretliSirali(
        '${ifade('ⁿ')} ifadesinin açılımında ${m + 1} terim vardır. Buna göre '
        'bu açılımdaki katsayıların toplamı kaçtır?',
        yanit,
        [
          _kuvvet(p + sq, m + 1), // terim sayısı üs sanılır
          _kuvvet(p - sq, m), // işaret hatası
          _kuvvet(p + sq, m + 2),
          m + 1,
          _kuvvet(2, m),
          (p + sq) * m,
          _kuvvet(p + sq, m - 1),
        ],
        'n. kuvvetin açılımında n + 1 terim bulunur; n + 1 = ${m + 1} '
        'olduğundan n = $m. $hx = $hy = 1 için katsayılar toplamı '
        '($p $isaret $q)${_ust(m)} = ${_par(p + sq)}${_ust(m)} = '
        '${_eksi(yanit)}.',
        i,
      );
  }
}

// ---------------------------------------------------------------------------
// 5. Zar ve madenî para deneylerinde olasılık
// ---------------------------------------------------------------------------

/// Zar olayları: (üst yüze gelen sayının tanımı, uygun yüzler).
final _zarOlaylari = <(String, bool Function(int))>[
  for (var k = 1; k <= 5; k++) ('$k sayısından büyük bir sayı', (x) => x > k),
  for (var k = 2; k <= 6; k++) ('$k sayısından küçük bir sayı', (x) => x < k),
  ('asal bir sayı', (x) => x == 2 || x == 3 || x == 5),
  ('çift bir sayı', (x) => x.isEven),
  ('tek bir sayı', (x) => x.isOdd),
  ('3 ile tam bölünen bir sayı', (x) => x % 3 == 0),
  ('tam kare bir sayı', (x) => x == 1 || x == 4),
  ('6 sayısını tam bölen bir sayı', (x) => 6 % x == 0),
  ('4 sayısını tam bölen bir sayı', (x) => 4 % x == 0),
  for (var k = 2; k <= 5; k++) ('değeri en az $k olan bir sayı', (x) => x >= k),
  for (var k = 2; k <= 5; k++)
    ('değeri en çok $k olan bir sayı', (x) => x <= k),
];

/// Para olayları: (para sayısı, tür, j). Tür 0: tam j tura, 1: en az j tura,
/// 2: en çok j tura, 3: hepsi aynı yüz.
const _paraOlaylari = [
  (2, 0, 1), (2, 1, 1), (2, 3, 0),
  (3, 0, 1), (3, 0, 2), (3, 1, 1), (3, 1, 2), (3, 2, 1), (3, 3, 0),
  (4, 0, 1), (4, 0, 2), (4, 0, 3), (4, 1, 1), (4, 1, 2), (4, 1, 3), (4, 2, 1),
  (5, 0, 2), (5, 0, 3), (5, 1, 4), (5, 2, 1),
];

AdvancedItem _zarPara(int a, int b, int c) {
  final (zarYazi, zarOlay) = _zarOlaylari[a];
  final (n, tur, j) = _paraOlaylari[b];
  final baglac = c % 5;
  final x = [for (var k = 1; k <= 6; k++) if (zarOlay(k)) k].length;
  final t = _kuvvet(2, n);
  var y = 0;
  for (var k = 0; k <= n; k++) {
    final uygun = switch (tur) {
      0 => k == j,
      1 => k >= j,
      2 => k <= j,
      _ => k == 0 || k == n,
    };
    if (uygun) y += _komb(n, k);
  }
  final paraYazi = switch (tur) {
    0 => 'paralardan tam $j tanesinin tura gelmesi',
    1 => 'paralardan en az $j tanesinin tura gelmesi',
    2 => 'paralardan en çok $j tanesinin tura gelmesi',
    _ => 'paraların tümünün aynı yüzünün üste gelmesi',
  };
  final giris = c < 5
      ? 'Hilesiz bir zar ile hilesiz $n madenî para aynı anda atılıyor.'
      : 'Bir oyunda önce hilesiz $n madenî para, ardından hilesiz bir zar '
            'atılıyor.';
  final tum = 6 * t;
  final ortak =
      'Zarın 6 sonucundan $x tanesi A olayına, paraların $t sonucundan $y '
      'tanesi B olayına uygundur; tüm sonuçlar 6·$t = $tum tanedir.';
  final String istenen, aciklama;
  final int pay;
  final List<(int, int)> yanlis;
  switch (baglac) {
    case 0:
      istenen = 'A ve B olaylarının ikisinin de gerçekleşmesi';
      pay = x * y;
      yanlis = [
        (x * t + 6 * y - x * y, tum), // birleşim
        (x + y, tum), // sonuç sayıları toplanır
        (x, 6),
        (x, tum), // paranın payı unutulur
        (y, t),
        (y, tum),
        (x + y, 6 + t),
        (x * t + 6 * y, tum),
        ((6 - x) * (t - y), tum),
      ];
      aciklama =
          '$ortak İkisine de uygun sonuç sayısı $x·$y = $pay olduğundan '
          'olasılık ${_sade(pay, tum)} olur.';
    case 1:
      istenen = 'A ve B olaylarından en az birinin gerçekleşmesi';
      pay = x * t + 6 * y - x * y;
      yanlis = [
        (x * y, tum), // kesişim
        (x * t + 6 * y, tum), // kesişim çıkarılmaz
        (x, 6),
        (tum - x * y, tum), // “ikisi birden değil” ile karıştırılır
        (y, t),
        (tum - (6 - x) - (t - y), tum), // tümleyende toplama
        (x + y, 6 + t),
        ((6 - x) * (t - y), tum),
      ];
      aciklama =
          '$ortak Hiçbirine uygun olmayan sonuç sayısı ${6 - x}·${t - y} = '
          '${(6 - x) * (t - y)} olduğundan istenen sonuç sayısı '
          '$tum − ${(6 - x) * (t - y)} = $pay, olasılık ${_sade(pay, tum)} '
          'olur.';
    case 2:
      istenen = 'A olayının gerçekleşip B olayının gerçekleşmemesi';
      pay = x * (t - y);
      yanlis = [
        (x * y, tum),
        (x, 6),
        ((6 - x) * y, tum), // olaylar yer değiştirir
        (x * t - 6 * y, tum), // olasılıklar çıkarılır
        (t - y, t),
        (x + t - y, tum), // sonuç sayıları toplanır
        (x * t + 6 * (t - y) - x * (t - y), tum),
        (x, tum),
        ((6 - x) * (t - y), tum),
        (t - y, tum),
      ];
      aciklama =
          '$ortak B olayına uygun olmayan ${t - y} sonuç vardır. İstenen '
          'sonuç sayısı $x·${t - y} = $pay, olasılık ${_sade(pay, tum)} olur.';
    case 3:
      istenen = 'B olayının gerçekleşip A olayının gerçekleşmemesi';
      pay = (6 - x) * y;
      yanlis = [
        (x * y, tum),
        (y, t),
        (x * (t - y), tum), // olaylar yer değiştirir
        (6 * y - x * t, tum), // olasılıklar çıkarılır
        (6 - x, 6),
        (6 - x + y, tum), // sonuç sayıları toplanır
        ((6 - x) * t + 6 * y - (6 - x) * y, tum),
        (y, tum),
        ((6 - x) * (t - y), tum),
        (6 - x, tum),
      ];
      aciklama =
          '$ortak A olayına uygun olmayan ${6 - x} sonuç vardır. İstenen '
          'sonuç sayısı ${6 - x}·$y = $pay, olasılık ${_sade(pay, tum)} olur.';
    default:
      istenen = 'A ve B olaylarından hiçbirinin gerçekleşmemesi';
      pay = (6 - x) * (t - y);
      yanlis = [
        (tum - x * y, tum),
        (x * y, tum),
        (6 - x, 6),
        (tum - x * t - 6 * y, tum), // kesişim geri eklenmez
        (t - y, t),
        ((6 - x) + (t - y), tum), // sonuç sayıları toplanır
        (x * t + 6 * y - x * y, tum),
        (6 - x, tum),
        (t - y, tum),
      ];
      aciklama =
          '$ortak A olayına uygun olmayan ${6 - x}, B olayına uygun olmayan '
          '${t - y} sonuç vardır. İstenen sonuç sayısı ${6 - x}·${t - y} = '
          '$pay, olasılık ${_sade(pay, tum)} olur.';
  }
  return _olasilikSirali(
    '$giris A olayı, zarın üst yüzüne $zarYazi gelmesi; B olayı ise '
    '$paraYazi olarak tanımlanıyor. Buna göre $istenen olasılığı kaçtır?',
    pay,
    tum,
    yanlis,
    aciklama,
    _no(a, b, c),
  );
}

// ---------------------------------------------------------------------------
// 6. Torbadan çekilişlerde olasılık (iadeli ve iadesiz)
// ---------------------------------------------------------------------------

const _torbaBaglamlari = [
  (
    kapta: 'Bir torbada',
    kaptan: 'Torbadan',
    kaba: 'torbaya',
    nesne: 'top',
    renkler: ['kırmızı', 'mavi', 'sarı'],
  ),
  (
    kapta: 'Bir kutuda',
    kaptan: 'Kutudan',
    kaba: 'kutuya',
    nesne: 'bilye',
    renkler: ['yeşil', 'beyaz', 'siyah'],
  ),
  (
    kapta: 'Bir kavanozda',
    kaptan: 'Kavanozdan',
    kaba: 'kavanoza',
    nesne: 'boncuk',
    renkler: ['mor', 'turuncu', 'pembe'],
  ),
  (
    kapta: 'Bir kesede',
    kaptan: 'Keseden',
    kaba: 'keseye',
    nesne: 'jeton',
    renkler: ['kırmızı', 'yeşil', 'mavi'],
  ),
  (
    kapta: 'Bir çekmecede',
    kaptan: 'Çekmeceden',
    kaba: 'çekmeceye',
    nesne: 'kalem',
    renkler: ['siyah', 'mavi', 'kırmızı'],
  ),
];

AdvancedItem _torba(int a, int b, int c) {
  final ctx = _torbaBaglamlari[c ~/ 2];
  final iadeli = c.isOdd;
  final k = 2 + a % 5, m = 2 + a ~/ 5, s = 1 + b % 4;
  final olay = b ~/ 4;
  final n = k + m + s;
  final r1 = ctx.renkler[0], r2 = ctx.renkler[1], r3 = ctx.renkler[2];
  final nesne = ctx.nesne;
  final cekilis = iadeli
      ? '${ctx.kaptan} rastgele bir $nesne çekilip rengi not ediliyor ve '
            'çekilen $nesne ${ctx.kaba} geri atılıyor; ardından ikinci bir '
            '$nesne çekiliyor.'
      : '${ctx.kaptan} art arda iki $nesne, çekilen $nesne ${ctx.kaba} geri '
            'atılmadan rastgele çekiliyor.';
  final giris =
      '${ctx.kapta} yalnız renkleri farklı olan $k $r1, $m $r2 ve $s $r3 '
      '$nesne vardır. $cekilis';
  final payda = iadeli ? n * n : n * (n - 1);
  final digerPayda = iadeli ? n * (n - 1) : n * n;
  // İkinci çekilişte bir renkten kalan sayı: iadeli ise değişmez.
  final e = iadeli ? 0 : 1;
  final ayni = k * (k - e) + m * (m - e) + s * (s - e);
  final digerAyni = iadeli
      ? k * (k - 1) + m * (m - 1) + s * (s - 1)
      : k * k + m * m + s * s;
  final kural = iadeli
      ? 'Çekilen $nesne geri atıldığı için iki çekilişte de $n $nesne vardır.'
      : 'Çekilen $nesne geri atılmadığı için ikinci çekilişte ${n - 1} $nesne '
            'kalır.';
  final String istenen, aciklama;
  final int pay;
  final List<(int, int)> yanlis;
  switch (olay) {
    case 0:
      istenen = 'iki çekilişte de $r1 $nesne gelme';
      pay = k * (k - e);
      yanlis = [
        (iadeli ? k * (k - 1) : k * k, digerPayda),
        (k, n),
        (2 * k, 2 * n - e),
        (k - 1, n - 1),
      ];
      aciklama =
          '$kural Olasılık ($k/$n)·(${k - e}/${n - e}) = '
          '${_sade(pay, payda)} olur.';
    case 1:
      istenen = 'iki çekilişte aynı renkte $nesne gelme';
      pay = ayni;
      yanlis = [
        (digerAyni, digerPayda),
        (payda - ayni, payda),
        (k * (k - e), payda),
        (3, n),
      ];
      aciklama =
          '$kural Aynı renk için uygun sıralı durum sayısı '
          '$k·${k - e} + $m·${m - e} + $s·${s - e} = $pay, tüm durumlar '
          '$n·${n - e} = $payda tanedir. Olasılık ${_sade(pay, payda)} '
          'olur.';
    case 2:
      istenen = 'iki çekilişte farklı renklerde $nesne gelme';
      pay = payda - ayni;
      yanlis = [
        (digerPayda - digerAyni, digerPayda),
        (ayni, payda),
        (k * m + k * s + m * s, payda),
        (2, 3),
      ];
      aciklama =
          '$kural Aynı renk gelen sıralı durum sayısı '
          '$k·${k - e} + $m·${m - e} + $s·${s - e} = $ayni, tüm durumlar '
          '$n·${n - e} = $payda tanedir. Olasılık 1 − $ayni/$payda = '
          '${kesir(pay, payda)} olur.';
    case 3:
      istenen = 'ilk çekilişte $r1, ikinci çekilişte $r2 $nesne gelme';
      pay = k * m;
      yanlis = [
        (k * m, digerPayda),
        (2 * k * m, payda),
        (k + m, n),
        (k * m, n * (n + 1)),
      ];
      aciklama =
          '$kural Olasılık ($k/$n)·($m/${n - e}) = '
          '${_sade(pay, payda)} olur.';
    default:
      final yok = (n - k) * (n - k - e);
      // Öteki çekiliş kuralıyla (iadeli ↔ iadesiz) hesaplanan hatalı değer.
      final digerYok = (n - k) * (iadeli ? n - k - 1 : n - k);
      istenen = 'çekilişlerin en az birinde $r1 $nesne gelme';
      pay = payda - yok;
      yanlis = [
        (digerPayda - digerYok, digerPayda),
        (yok, payda),
        (k * (k - e), payda),
        (k, n),
      ];
      aciklama =
          '$kural Hiç $r1 gelmeme olasılığı (${n - k}/$n)·'
          '(${n - k - e}/${n - e}) = $yok/$payda olduğundan istenen olasılık '
          '1 − $yok/$payda = ${kesir(pay, payda)} olur.';
  }
  return _olasilik(
    '$giris Buna göre $istenen olasılığı kaçtır?',
    pay,
    payda,
    yanlis,
    aciklama,
  );
}

// ---------------------------------------------------------------------------
// 7. Bağımsız olaylar ve koşullu olasılık
// ---------------------------------------------------------------------------

const _kosulluBaglamlari = [
  (
    yer: 'Bir sınıftaki',
    g1Gen: 'kız öğrencilerin',
    g2Gen: 'erkek öğrencilerin',
    t1: 'gözlüklü',
    t0: 'gözlüksüz',
    t0Bildirme: 'gözlüksüzdür',
    secim: 'Bu sınıftan rastgele seçilen bir öğrencinin',
    g1: 'kız',
    g2: 'erkek',
  ),
  (
    yer: 'Bir şirketteki',
    g1Gen: 'mühendislerin',
    g2Gen: 'teknisyenlerin',
    t1: 'sertifikalı',
    t0: 'sertifikasız',
    t0Bildirme: 'sertifikasızdır',
    secim: 'Bu mühendis ve teknisyenler arasından rastgele seçilen bir '
        'çalışanın',
    g1: 'mühendis',
    g2: 'teknisyen',
  ),
  (
    yer: 'Bir spor kulübündeki',
    g1Gen: 'yüzücülerin',
    g2Gen: 'atletlerin',
    t1: 'lisanslı',
    t0: 'lisanssız',
    t0Bildirme: 'lisanssızdır',
    secim: 'Bu yüzücü ve atletler arasından rastgele seçilen bir sporcunun',
    g1: 'yüzücü',
    g2: 'atlet',
  ),
  (
    yer: 'Bir kargo firmasındaki',
    g1Gen: 'kuryelerin',
    g2Gen: 'depo görevlilerinin',
    t1: 'ehliyetli',
    t0: 'ehliyetsiz',
    t0Bildirme: 'ehliyetsizdir',
    secim: 'Bu kurye ve depo görevlileri arasından rastgele seçilen bir '
        'çalışanın',
    g1: 'kurye',
    g2: 'depo görevlisi',
  ),
  (
    yer: 'Bir çiftlikteki',
    g1Gen: 'ineklerin',
    g2Gen: 'koyunların',
    t1: 'aşılı',
    t0: 'aşısız',
    t0Bildirme: 'aşısızdır',
    secim: 'Bu inek ve koyunlar arasından rastgele seçilen bir hayvanın',
    g1: 'inek',
    g2: 'koyun',
  ),
];

const _kesirler25 = [
  (1, 2), (1, 3), (2, 3), (1, 4), (3, 4), (1, 5), (2, 5), (3, 5), (4, 5),
  (1, 6), (5, 6), (1, 7), (2, 7), (3, 7), (4, 7), (5, 7), (6, 7), (1, 8),
  (3, 8), (5, 8), (7, 8), (1, 9), (2, 9), (4, 9), (5, 9),
];

const _kesirler20 = [
  (1, 2), (1, 3), (2, 3), (1, 4), (3, 4), (1, 5), (2, 5), (3, 5), (4, 5),
  (1, 6), (5, 6), (1, 10), (3, 10), (7, 10), (9, 10), (1, 12), (5, 12),
  (7, 12), (11, 12), (7, 9),
];

AdvancedItem _kosulluSayim(int a, int b, int tur) {
  final ctx = _kosulluBaglamlari[(a + b) % 5];
  final u = 3 + a % 5, v = 2 + a ~/ 5; // özelliği taşıyanlar
  final p = 4 + b % 4, q = 3 + b ~/ 4; // özelliği taşımayanlar
  final n = u + v + p + q;
  final giris =
      '${ctx.yer} ${ctx.g1Gen} $u tanesi ${ctx.t1}, $p tanesi '
      '${ctx.t0Bildirme}; ${ctx.g2Gen} $v tanesi ${ctx.t1}, $q tanesi '
      '${ctx.t0Bildirme}.';
  final (bilinen, sorulan, pay, payda, yanlis) = switch (tur) {
    0 => (
      ctx.t1, ctx.g1, u, u + v,
      [(u, u + p), (u, n), (u + v, n), (v, u + v)],
    ),
    1 => (
      ctx.g1, ctx.t1, u, u + p,
      [(u, u + v), (u, n), (u + p, n), (p, u + p)],
    ),
    2 => (
      ctx.t0, ctx.g2, q, p + q,
      [(q, v + q), (q, n), (p + q, n), (p, p + q)],
    ),
    3 => (
      ctx.g2, ctx.t0, q, v + q,
      [(q, p + q), (q, n), (v + q, n), (v, v + q)],
    ),
    _ => (
      ctx.t1, ctx.g2, v, u + v,
      [(v, v + q), (v, n), (u + v, n), (u, u + v)],
    ),
  };
  return _olasilik(
    '$giris ${ctx.secim} $bilinen olduğu bilindiğine göre $sorulan olma '
    'olasılığı kaçtır?',
    pay,
    payda,
    yanlis,
    'Koşul örnek uzayı daraltır: $bilinen olanların sayısı $payda, bunlardan '
    '$sorulan olanların sayısı $pay olduğundan olasılık '
    '${_sade(pay, payda)} olur.',
  );
}

AdvancedItem _bagimsizOlay(int a, int b, int tur) {
  final (pn, pd) = _kesirler25[a];
  final (qn, qd) = _kesirler20[b];
  final okcu = (a + b).isOdd;
  final p = kesir(pn, pd), q = kesir(qn, qd);
  final d = pd * qd;
  final kesisim = kesir(pn * qn, d);
  final birlesimPay = pn * qd + qn * pd - pn * qn;
  final birlesim = kesir(birlesimPay, d);
  const soyut = 'A ve B, aynı deneye ait bağımsız iki olaydır.';
  const okcuGiris =
      'Birbirinden bağımsız atış yapan iki okçudan birincisinin hedefi vurma '
      'olasılığı';
  switch (tur) {
    case 0:
      return _olasilik(
        okcu
            ? '$okcuGiris $p, ikincisinin hedefi vurma olasılığı $q olarak '
                  'veriliyor. Okçular birer atış yaptığında hedefin en az bir '
                  'kez vurulma olasılığı kaçtır?'
            : '$soyut P(A) = $p ve P(B) = $q olduğuna göre P(A ∪ B) kaçtır?',
        birlesimPay,
        d,
        [
          (pn * qd + qn * pd, d),
          (pn * qn, d),
          (pn * qd + qn * pd - 2 * pn * qn, d),
          ((pd - pn) * (qd - qn), d),
        ],
        'Bağımsız olaylarda kesişimin olasılığı ($p)·($q) = $kesisim olur. '
        'Birleşimin olasılığı $p + $q − $kesisim = $birlesim bulunur.',
      );
    case 1:
      return _olasilik(
        okcu
            ? '$okcuGiris $p, birer atış yaptıklarında ikisinin de hedefi '
                  'vurma olasılığı $kesisim olarak veriliyor. Buna göre '
                  'ikinci okçunun hedefi vurma olasılığı kaçtır?'
            : '$soyut P(A) = $p ve P(A ∩ B) = $kesisim olduğuna göre P(B) '
                  'kaçtır?',
        qn,
        qd,
        [
          (pn * pn * qn, pd * d),
          (pn * (pd * qd - pd * qn) , pd * d),
          (pn * qd - pn * qn, d),
          (pd * qd - pn * qn, d),
        ],
        'Bağımsız olaylarda kesişimin olasılığı olasılıkların çarpımıdır. '
        'Aranan olasılık ($kesisim) : ($p) = $q olur.',
      );
    case 2:
      final pay = pn * (qd - qn);
      return _olasilik(
        okcu
            ? '$okcuGiris $p, ikincisinin hedefi vurma olasılığı $q olarak '
                  'veriliyor. Okçular birer atış yaptığında hedefi yalnızca '
                  'birinci okçunun vurma olasılığı kaçtır?'
            : '$soyut P(A) = $p ve P(B) = $q olduğuna göre A olayının '
                  'gerçekleşip B olayının gerçekleşmemesi olasılığı kaçtır?',
        pay,
        d,
        [
          (pn * qn, d),
          ((pd - pn) * qn, d),
          (pn * qd - qn * pd, d),
          ((pd - pn) * (qd - qn), d),
        ],
        'B olayının gerçekleşmeme olasılığı 1 − $q = ${kesir(qd - qn, qd)} '
        'olur. Olaylar bağımsız olduğundan istenen olasılık '
        '($p)·(${kesir(qd - qn, qd)}) = ${kesir(pay, d)} bulunur.',
      );
    case 3:
      final pay = (pd - pn) * (qd - qn);
      return _olasilik(
        okcu
            ? '$okcuGiris $p, ikincisinin hedefi vurma olasılığı $q olarak '
                  'veriliyor. Okçular birer atış yaptığında hedefin hiç '
                  'vurulmama olasılığı kaçtır?'
            : '$soyut P(A) = $p ve P(B) = $q olduğuna göre bu iki olayın '
                  'ikisinin de gerçekleşmemesi olasılığı kaçtır?',
        pay,
        d,
        [
          (d - pn * qn, d),
          (pn * qn, d),
          ((pd - pn) * qn, d),
          (d - pn * qd - qn * pd, d),
        ],
        'Gerçekleşmeme olasılıkları 1 − $p = ${kesir(pd - pn, pd)} ve '
        '1 − $q = ${kesir(qd - qn, qd)} olur. Olaylar bağımsız olduğundan '
        'istenen olasılık (${kesir(pd - pn, pd)})·(${kesir(qd - qn, qd)}) = '
        '${kesir(pay, d)} bulunur.',
      );
    default:
      return _olasilik(
        okcu
            ? '$okcuGiris $p, birer atış yaptıklarında hedefin en az bir kez '
                  'vurulma olasılığı $birlesim olarak veriliyor. Buna göre '
                  'ikinci okçunun hedefi vurma olasılığı kaçtır?'
            : '$soyut P(A) = $p ve P(A ∪ B) = $birlesim olduğuna göre P(B) '
                  'kaçtır?',
        qn,
        qd,
        [
          (birlesimPay * pd - pn * d, d * pd),
          (birlesimPay * pn, d * pd),
          (d - birlesimPay, d),
          (pd - pn, pd),
        ],
        'P(A ∪ B) = P(A) + P(B) − P(A)·P(B) eşitliğinde P(B) = x yazılır: '
        '$birlesim = $p + x·(1 − $p). Buradan x·(${kesir(pd - pn, pd)}) = '
        '${kesir(birlesimPay * pd - pn * d, d * pd)} ve x = $q bulunur.',
      );
  }
}

AdvancedItem _kosullu(int a, int b, int c) =>
    c.isEven ? _kosulluSayim(a, b, c ~/ 2) : _bagimsizOlay(a, b, c ~/ 2);

// ---------------------------------------------------------------------------
// 8. Aritmetik ortalama: eklenen, çıkan ve eksik veri
// ---------------------------------------------------------------------------

AdvancedItem _ortalama(int a, int b, int c) {
  final i = _no(a, b, c);
  final n = 5 + a; // 5 … 29 gün
  final m = 240 + 20 * (b ~/ 4); // ilk ortalama
  final d = 1 + c % 5; // ortalamadaki değişim
  final s = c < 5 ? 1 : -1;
  switch (b % 4) {
    case 0:
      final x = m + s * d * (n + 1), yeni = m + s * d;
      return _tamAralikli(
        'Bir kırtasiyede $n gün boyunca günde ortalama $m kalem satılmıştır. '
        'Sonraki gün $x kalem satıldığına göre ${n + 1} günlük satış '
        'ortalaması kaç kalem olur?',
        yeni,
        [
          (m + x) ~/ 2, // eski ortalama ile yeni değerin ortalaması
          n * m ~/ (n + 1), // yeni değer toplama eklenmez
          m + s * d * (n + 1) ~/ n, // fark n'ye bölünür
          m - s * d, // değişimin yönü ters alınır
          (n * m + x) ~/ n, // yeni toplam n'ye bölünür
          m + s * (d + 1),
          m - s * d * (n + 1) ~/ n,
          (n * m + x) ~/ (n + 2),
          m, // ortalama değişmez sanılır
        ],
        'İlk $n günün toplamı $n·$m = ${n * m} kalemdir. Yeni toplam '
        '${n * m} + $x = ${n * m + x} olur; ortalama ${n * m + x} : ${n + 1} '
        '= $yeni bulunur.',
        i,
      );
    case 1:
      final x = m + s * d * (n - 1), yeni = m - s * d;
      return _tamAralikli(
        'Bir kütüphaneye $n gün boyunca günde ortalama $m kişi gelmiştir. '
        '$x kişinin geldiği gün hesaba katılmazsa kalan ${n - 1} günün '
        'ortalaması kaç kişi olur?',
        yeni,
        [
          m + s * d, // değişimin yönü ters alınır
          (n * m - x) ~/ n, // kalan toplam n'ye bölünür
          (m + x) ~/ 2,
          m - s * (d + 1),
          m - s * d * (n - 1), // fark bölünmeden çıkarılır
          m, // ortalama değişmez sanılır
        ],
        'Toplam $n·$m = ${n * m} kişidir. Bir gün çıkarılınca toplam '
        '${n * m} − $x = ${n * m - x} olur; ortalama ${n * m - x} : ${n - 1} '
        '= $yeni bulunur.',
        i,
      );
    case 2:
      final yeni = m + s * d, x = m + s * d * (n + 1);
      return _tamAralikli(
        'Bir fırında $n gün boyunca günde ortalama $m ekmek satılmıştır. '
        'Sonraki günün satışı da hesaba katıldığında ${n + 1} günlük ortalama '
        '$yeni ekmek olmuştur. Buna göre sonraki gün kaç ekmek satılmıştır?',
        x,
        [
          m + s * d * n, // fark n ile çarpılır
          m + s * d * (n + 2),
          yeni, // yeni ortalama yanıt sanılır
          2 * yeni - m,
          m - s * d * (n + 1), // değişimin yönü ters alınır
          m + s * d * (n - 1),
          (n + 1) * yeni - (n - 1) * m, // gün sayıları karıştırılır
          (n + 2) * yeni - n * m,
        ],
        'İlk $n günün toplamı $n·$m = ${n * m}, ${n + 1} günün toplamı '
        '${n + 1}·$yeni = ${(n + 1) * yeni} ekmektir. Fark: '
        '${(n + 1) * yeni} − ${n * m} = $x.',
        i,
      );
    default:
      final yeni = m - s * d, x = m + s * d * (n - 1);
      return _tamAralikli(
        'Bir otoparka $n gün boyunca günde ortalama $m araç girmiştir. Bu '
        'günlerden biri hesaba katılmadığında kalan ${n - 1} günün ortalaması '
        '$yeni araç olmuştur. Buna göre hesaba katılmayan gün otoparka kaç '
        'araç girmiştir?',
        x,
        [
          m + s * d * n, // fark n ile çarpılır
          m + s * d * (n - 2),
          yeni, // yeni ortalama yanıt sanılır
          2 * m - yeni,
          m - s * d * (n - 1), // değişimin yönü ters alınır
          m + s * d * (n + 1),
          n * m - (n - 2) * yeni, // gün sayıları karıştırılır
        ],
        '$n günün toplamı $n·$m = ${n * m}, kalan ${n - 1} günün toplamı '
        '${n - 1}·$yeni = ${(n - 1) * yeni} araçtır. Fark: '
        '${n * m} − ${(n - 1) * yeni} = $x.',
        i,
      );
  }
}

// ---------------------------------------------------------------------------
// 9. Medyan, mod ve açıklık
// ---------------------------------------------------------------------------

/// (beş düzeyin tekrar sayıları, soru türü). Türler: 0 medyan, 1 mod,
/// 2 açıklık, 3 medyan + mod, 4 açıklık + medyan, 5 mod + açıklık,
/// 6 mod − medyan, 7 medyan + mod + açıklık.
const _medyanKaliplari = [
  ([3, 1, 1, 1, 1], 0),
  ([1, 3, 1, 2, 1], 0),
  ([1, 1, 2, 1, 3], 1),
  ([2, 1, 1, 2, 1], 2),
  ([4, 1, 1, 2, 1], 0),
  ([1, 1, 1, 1, 3], 3),
  ([1, 3, 2, 1, 1], 4),
  ([1, 3, 1, 2, 1], 5),
  ([1, 1, 2, 1, 4], 6),
  ([3, 1, 1, 1, 1], 7),
];

const _karistirma = {
  7: [3, 0, 5, 1, 6, 2, 4],
  8: [5, 2, 7, 0, 3, 6, 1, 4],
  9: [4, 8, 1, 6, 0, 3, 7, 2, 5],
};

const _veriBaglamlari = [
  ('Bir kafede', 'gün boyunca satılan kek dilimi sayıları'),
  ('Bir kütüphaneden art arda', 'günde ödünç alınan kitap sayıları'),
  ('Bir sinema salonunda art arda', 'seansta satılan bilet sayıları'),
  ('Bir otobüs hattında art arda', 'seferde taşınan yolcu sayıları'),
  ('Bir sınıftaki', 'öğrencinin bir ayda çözdüğü test sayıları'),
];

String _liste(List<int> xs) =>
    '${xs.sublist(0, xs.length - 1).join(', ')} ve ${xs.last}';

AdvancedItem _medyanMod(int a, int b, int c) {
  final (tekrar, tur) = _medyanKaliplari[c];
  final l0 = 10 + a;
  final l1 = l0 + 1 + b % 2;
  final l2 = l1 + 2 * (1 + (b ~/ 2) % 2);
  final l3 = l2 + 2 * (1 + b ~/ 4);
  final l4 = l3 + 1 + (b * 7) % 4;
  final duzey = [l0, l1, l2, l3, l4];
  final sirali = [
    for (var i = 0; i < 5; i++)
      for (var j = 0; j < tekrar[i]; j++) duzey[i],
  ];
  final n = sirali.length;
  final perm = _karistirma[n]!;
  final kay = (a + b) % n;
  final veri = [for (var i = 0; i < n; i++) sirali[perm[(i + kay) % n]]];
  final enCok = tekrar.reduce((x, y) => x > y ? x : y);
  final mod = duzey[tekrar.indexOf(enCok)];
  final aciklik = l4 - l0;
  final iki = n.isEven
      ? sirali[n ~/ 2 - 1] + sirali[n ~/ 2]
      : 2 * sirali[n ~/ 2];
  if (iki.isOdd) throw StateError('Medyan tam sayı değil: $sirali');
  final medyan = iki ~/ 2;
  final ortadaki = veri[n ~/ 2]; // sıralamadan ortadakini alma hatası
  // Tipik hatalar için: ortanın komşu değerleri, ortanın sıra numarası,
  // tam sayıysa aritmetik ortalama ve en küçükle en büyüğün ortalaması
  // (tam sayı değilse 0; 0 aday olarak elenir).
  final altKomsu = sirali[(n - 1) ~/ 2 - 1], ustKomsu = sirali[n ~/ 2 + 1];
  final ortaSira = (n + 1) ~/ 2;
  final toplam = sirali.fold<int>(0, (x, y) => x + y);
  final ortalama = toplam % n == 0 ? toplam ~/ n : 0;
  final uclarOrtasi = (l0 + l4).isEven ? (l0 + l4) ~/ 2 : 0;
  final (yer, ne) = _veriBaglamlari[(a + 2 * c) % 5];
  final giris = '$yer $n $ne şöyledir: ${_liste(veri)}.';
  final medyanYazi = n.isOdd
      ? 'ortadaki ${n ~/ 2 + 1}. değer $medyan'
      : 'ortadaki iki değerin ortalaması '
            '(${sirali[n ~/ 2 - 1]} + ${sirali[n ~/ 2]}) : 2 = $medyan';
  final siraliYazi =
      'Veriler küçükten büyüğe ${sirali.join(', ')} biçiminde sıralanır.';
  final (soru, yanit, yanlis, cozum) = switch (tur) {
    0 => (
      'medyanı (ortancası)',
      medyan,
      [
        ortadaki, // veriler sıralanmaz
        mod,
        l2, // farklı değerlerin ortancası
        ortaSira, // değer yerine sıra numarası
        ortalama,
        altKomsu,
        ustKomsu,
        uclarOrtasi,
        aciklik,
        sirali[n ~/ 2] + 1,
      ],
      '$siraliYazi Medyan, $medyanYazi olur.',
    ),
    1 => (
      'modu (tepe değeri)',
      mod,
      [
        medyan,
        enCok, // değer yerine tekrar sayısı
        l2,
        aciklik,
        ortalama,
        l4,
        l0,
      ],
      '$siraliYazi En çok yinelenen değer $enCok kez geçen $mod olduğundan '
          'mod $mod olur.',
    ),
    2 => (
      'açıklığı',
      aciklik,
      [
        l4, // en büyük değer
        veri.last - veri.first, // veriler sıralanmaz
        l4 - l1,
        aciklik + 1,
        l3 - l0,
        medyan,
        uclarOrtasi,
        mod,
      ],
      'En büyük değer $l4, en küçük değer $l0 olduğundan açıklık '
          '$l4 − $l0 = $aciklik olur.',
    ),
    3 => (
      'medyanı ile modunun toplamı',
      medyan + mod,
      [
        ortadaki + mod,
        2 * mod,
        medyan + enCok, // mod yerine tekrar sayısı
        medyan + aciklik,
        2 * medyan,
        l2 + mod,
        if (ortalama > 0) ortalama + mod,
      ],
      '$siraliYazi Medyan, $medyanYazi; mod ise $enCok kez geçen $mod olur. '
          'Toplam: $medyan + $mod = ${medyan + mod}.',
    ),
    4 => (
      'açıklığı ile medyanının toplamı',
      aciklik + medyan,
      [
        aciklik + ortadaki,
        l4 + medyan,
        l4 - l1 + medyan,
        aciklik + mod,
        aciklik + ortaSira, // medyan yerine sıra numarası
        aciklik + 1 + medyan,
        aciklik + sirali[n ~/ 2],
        aciklik + l2,
        aciklik + altKomsu,
      ],
      '$siraliYazi Açıklık $l4 − $l0 = $aciklik; medyan, $medyanYazi olur. '
          'Toplam: $aciklik + $medyan = ${aciklik + medyan}.',
    ),
    5 => (
      'modu ile açıklığının toplamı',
      mod + aciklik,
      [
        medyan + aciklik,
        mod + l4,
        enCok + aciklik, // mod yerine tekrar sayısı
        mod + aciklik + 1,
        mod + l4 - l1,
        l2 + aciklik,
        mod + l3 - l0,
      ],
      'Mod, $enCok kez geçen $mod; açıklık $l4 − $l0 = $aciklik olur. '
          'Toplam: $mod + $aciklik = ${mod + aciklik}.',
    ),
    6 => (
      'modu ile medyanı arasındaki fark',
      mod - medyan,
      [
        (mod - ortadaki).abs(),
        mod - l2,
        aciklik,
        mod + medyan, // fark yerine toplam
        l3 - l2,
        (mod - altKomsu).abs(),
        (mod - ustKomsu).abs(),
        if (ortalama > 0) (mod - ortalama).abs(),
      ],
      '$siraliYazi Mod, $enCok kez geçen $mod; medyan, $medyanYazi olur. '
          'Fark: $mod − $medyan = ${mod - medyan}.',
    ),
    _ => (
      'medyanı, modu ve açıklığının toplamı',
      medyan + mod + aciklik,
      [
        ortadaki + mod + aciklik,
        medyan + mod + l4,
        medyan + mod, // açıklık eklenmez
        medyan + enCok + aciklik,
        2 * medyan + aciklik,
        ortaSira + mod + aciklik,
        medyan + mod + aciklik + 1,
        l2 + mod + aciklik,
      ],
      '$siraliYazi Medyan $medyan, mod $mod, açıklık $l4 − $l0 = $aciklik '
          'olur. Toplam: $medyan + $mod + $aciklik = '
          '${medyan + mod + aciklik}.',
    ),
  };
  return _tamAralikli(
    '$giris Bu veri grubunun $soru kaçtır?',
    yanit,
    yanlis,
    cozum,
    _no(a, b, c),
  );
}

// ---------------------------------------------------------------------------
// 10. Varyans ve standart sapma
// ---------------------------------------------------------------------------

/// Toplamı sıfır olan ve kareler toplamı (n − 1)·k² veren sapma kalıpları.
const _sapmaKaliplari = [
  [1, -1, 0, 1, -1],
  [1, -3, 2, 1, -1],
  [-1, 3, -2, 1, -1],
  [1, -5, 3, 0, 1],
  [-3, 1, 4, -3, 1],
  [3, -1, -4, 3, -1],
  [-1, 5, -3, 0, -1],
  [1, -3, 1, 1],
  [-1, 3, -1, -1],
  [0, -3, 1, 3, 0, -1],
  [2, -1, -3, 1, 2, -1],
  [1, 0, -4, 1, 1, 1],
];

/// (kalıp numarası, çarpan).
const _sapmaSecimleri = [
  (0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (1, 1), (1, 2), (2, 1), (2, 2),
  (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (7, 2), (8, 1), (8, 3), (9, 1),
  (10, 1), (11, 1),
];

const _sapmaBaglamlari = [
  ('Bir öğrencinin', 'sınavdan aldığı puanlar', 60),
  ('Bir çiçekçide art arda', 'günde satılan buket sayıları', 15),
  ('Bir kafede art arda', 'günde satılan sandviç sayıları', 25),
  ('Bir fidanlıktaki', 'fidanın santimetre cinsinden boyları', 30),
  ('Bir çiftlikte art arda', 'günde toplanan yumurta sayıları', 45),
];

AdvancedItem _standartSapma(int a, int b, int c) {
  final (kalip, carpan) = _sapmaSecimleri[b];
  final (yer, ne, taban) = _sapmaBaglamlari[c ~/ 2];
  final ort = taban + a;
  final sapma = [for (final x in _sapmaKaliplari[kalip]) x * carpan];
  final n = sapma.length;
  final kay = a % n;
  final veri = [for (var i = 0; i < n; i++) ort + sapma[(i + kay) % n]];
  final toplam = veri.fold<int>(0, (x, y) => x + y);
  final kareler = sapma.fold<int>(0, (x, y) => x + y * y);
  if (toplam != ort * n || kareler % (n - 1) != 0) {
    throw StateError('Hatalı sapma kalıbı: $sapma');
  }
  final varyans = kareler ~/ (n - 1);
  var ss = 0;
  while (ss * ss < varyans) {
    ss++;
  }
  if (ss * ss != varyans) throw StateError('Tam kare olmayan varyans: $sapma');
  final enBuyuk = veri.reduce((x, y) => x > y ? x : y);
  final enKucuk = veri.reduce((x, y) => x < y ? x : y);
  final aciklik = enBuyuk - enKucuk;
  final mutlak = sapma.fold<int>(0, (x, y) => x + y.abs());
  // Kareler toplamının karekökü (tam kare değilse 0; 0 aday olarak elenir).
  var kok = 0;
  while (kok * kok < kareler) {
    kok++;
  }
  if (kok * kok != kareler) kok = 0;
  final kareYazi = [
    for (var i = 0; i < n; i++) '${_par(veri[i] - ort)}²',
  ].join(' + ');
  final giris =
      '$yer $n $ne ${_liste(veri)} olarak kaydedilmiştir. Varyans, verilerin '
      'aritmetik ortalamadan farklarının kareleri toplamı veri sayısının 1 '
      'eksiğine bölünerek hesaplanmaktadır.';
  final ortak =
      'Ortalama $toplam : $n = $ort olur. Farkların kareleri toplamı '
      '$kareYazi = $kareler, varyans $kareler : ${n - 1} = $varyans';
  if (c.isEven) {
    return _ondalikAralikli(
      '$giris Buna göre bu veri grubunun standart sapması kaçtır?',
      ss,
      [
        (varyans, 1), // karekök alınmaz
        (mutlak, n), // mutlak sapmaların ortalaması
        (kareler, n), // n'ye bölünür, karekök alınmaz
        (kok, n - 1), // önce karekök alınır
        (mutlak, n - 1),
        (aciklik, 1),
        (2 * ss, 1),
        (kareler, 1),
      ],
      '$ortak bulunur. Standart sapma varyansın kareköküdür: √$varyans = $ss.',
      _no(a, b, c),
      const [1, 1, 2, 4],
    );
  }
  return _ondalikAralikli(
    '$giris Buna göre bu veri grubunun varyansı kaçtır?',
    varyans,
    [
      (ss, 1), // karekök alınır
      (kareler, 1), // bölme unutulur
      (kareler, n), // n'ye bölünür
      (kareler, n - 2),
      (aciklik, 1),
      (mutlak, n - 1), // kareler yerine mutlak değerler
      (2 * varyans, 1),
      (aciklik * aciklik, 1),
    ],
    '$ortak bulunur.',
    _no(a, b, c),
    const [1, 1, 2, 4],
  );
}

// ---------------------------------------------------------------------------
// 11. Ağırlıklı ortalama
// ---------------------------------------------------------------------------

const _karisimUrunleri = ['çay', 'kahve', 'fındık', 'kuru üzüm'];

const _dersUcluleri = [
  ['İstatistik', 'Ekonomi', 'Hukuk'],
  ['Fizik', 'Kimya', 'Biyoloji'],
  ['Sosyoloji', 'Psikoloji', 'Felsefe'],
  ['Programlama', 'Mantık', 'Cebir'],
];

const _krediUcluleri = [
  (2, 3, 4), (2, 4, 3), (2, 1, 3), (2, 3, 1), (2, 2, 3),
  (2, 3, 2), (2, 4, 2), (3, 2, 4), (3, 4, 2), (3, 2, 2),
  (3, 1, 2), (3, 2, 1), (3, 4, 3), (3, 2, 5), (4, 2, 3),
  (4, 3, 2), (4, 3, 3), (4, 2, 2), (4, 1, 3), (4, 5, 2),
];

AdvancedItem _agirlikli(int a, int b, int c) {
  if (c.isEven) {
    // Karışım fiyatı: p1 = P − d·m2, p2 = P + d·m1 seçilince ortalama P olur.
    final fiyat = 120 + 5 * a;
    final m1 = 2 + b ~/ 4;
    final m2 = [for (var k = 2; k <= 6; k++) if (k != m1) k][b % 4];
    final d = 2 * (c ~/ 2 + 1);
    final p1 = fiyat - d * m2, p2 = fiyat + d * m1;
    final urun = _karisimUrunleri[(a + b) % 4];
    final tutar = p1 * m1 + p2 * m2;
    // Karışımın fiyatı iki fiyat arasında kalır; çeldiriciler de öyle.
    return _tamAralikli(
      'Bir aktar, kilogramı $p1 TL olan $m1 kg $urun ile kilogramı $p2 TL '
      'olan $m2 kg $urun karıştırıyor. Bu karışımın kilogramı kaç TL olur?',
      fiyat,
      [
        (p1 + p2) ~/ 2, // fiyatların düz ortalaması
        fiyat + d * (m1 - m2), // kütleler yer değiştirir
        (p1 * m1 + p2) ~/ (m1 + 1), // ikinci kütle çarpılmaz
        (p1 + p2 * m2) ~/ (1 + m2), // birinci kütle çarpılmaz
        (p1 + p2) ~/ 2 + d,
      ].where((x) => x > p1 && x < p2),
      'Karışımın toplam değeri $p1·$m1 + $p2·$m2 = $tutar TL, toplam kütlesi '
      '$m1 + $m2 = ${m1 + m2} kg olur. Kilogram fiyatı '
      '$tutar : ${m1 + m2} = $fiyat TL bulunur.',
      _no(a, b, c),
      unit: 'TL',
      agirlik: const [2, 1, 2, 3],
    );
  }
  // Kredili not ortalaması: sapmalar krediyle ağırlıklı olarak sıfırlanır.
  final ort = 50 + a;
  final (k1, k2, k3) = _krediUcluleri[b];
  final d = 1 + c ~/ 2;
  // t çarpanı, üçüncü notun ortalamaya eşit çıkmasını önler.
  final t = d * k1 == k2 ? 2 : 1;
  final g1 = ort - d * (k2 + k3);
  final g2 = ort + d * k1 + t * k3, g3 = ort + d * k1 - t * k2;
  final dersler = _dersUcluleri[(a + b) % 4];
  final toplam = k1 * g1 + k2 * g2 + k3 * g3, kredi = k1 + k2 + k3;
  if (toplam != ort * kredi) throw StateError('Ağırlıklı ortalama tutmuyor');
  final duz = (g1 + g2 + g3) ~/ 3;
  // Ağırlıklı ortalama en düşük ve en yüksek not arasında kalır.
  final enDusuk = [g1, g2, g3].reduce((x, y) => x < y ? x : y);
  final enYuksek = [g1, g2, g3].reduce((x, y) => x > y ? x : y);
  return _tamAralikli(
    'Bir üniversite öğrencisi $k1 kredilik ${dersler[0]} dersinden $g1, '
    '$k2 kredilik ${dersler[1]} dersinden $g2 ve $k3 kredilik ${dersler[2]} '
    'dersinden $g3 almıştır. Bu üç notun krediye göre ağırlıklı ortalaması '
    'kaçtır?',
    ort,
    [
      duz, // düz ortalama
      (k3 * g1 + k2 * g2 + k1 * g3) ~/ kredi, // krediler ters eşlenir
      (g2 + g3) ~/ 2,
      (g1 + k2 * g2 + k3 * g3) ~/ (1 + k2 + k3), // bir kredi unutulur
      (k1 * g1 + g2 + k3 * g3) ~/ (k1 + 1 + k3),
      (k1 * g1 + k2 * g2 + g3) ~/ (k1 + k2 + 1),
      duz + 1,
      ort + d,
      ort - d,
    ].where((x) => x > enDusuk && x < enYuksek),
    'Notlar kredileriyle çarpılıp toplanır: $k1·$g1 + $k2·$g2 + $k3·$g3 = '
    '$toplam. Toplam kredi $kredi olduğundan ortalama $toplam : $kredi = '
    '$ort olur.',
    _no(a, b, c),
    agirlik: const [2, 1, 2, 3],
  );
}

// ---------------------------------------------------------------------------
// 12. Kümelerde eleman sayısı ve alt küme sayısı
// ---------------------------------------------------------------------------

const _kumeBaglamlari = [
  (
    grup: 'kişilik bir sınıfta',
    x: 'İngilizce bilen',
    y: 'Almanca bilen',
    ikisi: 'iki dili de bilen',
    hic: 'bu dillerden hiçbirini bilmeyen',
    yalnizBir: 'bu dillerden yalnız birini bilen',
    enCokBir: 'bu dillerden en çok birini bilen',
  ),
  (
    grup: 'kişilik bir kafilede',
    x: 'futbol oynayan',
    y: 'basketbol oynayan',
    ikisi: 'iki oyunu da oynayan',
    hic: 'bu oyunlardan hiçbirini oynamayan',
    yalnizBir: 'bu oyunlardan yalnız birini oynayan',
    enCokBir: 'bu oyunlardan en çok birini oynayan',
  ),
  (
    grup: 'kişilik bir müzik topluluğunda',
    x: 'gitar çalan',
    y: 'piyano çalan',
    ikisi: 'iki çalgıyı da çalan',
    hic: 'bu çalgılardan hiçbirini çalmayan',
    yalnizBir: 'bu çalgılardan yalnız birini çalan',
    enCokBir: 'bu çalgılardan en çok birini çalan',
  ),
  (
    grup: 'kişilik bir ofiste',
    x: 'çay içen',
    y: 'kahve içen',
    ikisi: 'iki içeceği de içen',
    hic: 'bu içeceklerden hiçbirini içmeyen',
    yalnizBir: 'bu içeceklerden yalnız birini içen',
    enCokBir: 'bu içeceklerden en çok birini içen',
  ),
];

AdvancedItem _kume(int a, int b, int c) {
  final p = 2 + a % 5, q = 3 + a ~/ 5; // yalnız A, yalnız B
  final z = 1 + b % 5, n0 = 2 + b ~/ 5; // kesişim, dışarıda kalan
  final sa = p + z, sb = q + z, bir = p + q + z, n = bir + n0;
  const on = 'E evrensel kümesinin alt kümeleri olan A ve B kümeleri için';
  final ctx = _kumeBaglamlari[(a + b) % 4];
  switch (c) {
    case 0:
      return sayisal(
        '$on s(E) = $n, s(A) = $sa, s(B) = $sb ve s(A ∩ B) = $z olduğuna '
        'göre A ∪ B kümesinin tümleyeninin eleman sayısı kaçtır?',
        n0,
        [n - sa - sb, bir, n0 + z, n - z],
        's(A ∪ B) = s(A) + s(B) − s(A ∩ B) = $sa + $sb − $z = $bir olur. '
        'Tümleyenin eleman sayısı $n − $bir = $n0 bulunur.',
        positive: true,
      );
    case 1:
      return sayisal(
        '$on s(E) = $n, s(A) = $sa ve s(B) = $sb veriliyor. A ∪ B kümesinin '
        'tümleyeni $n0 elemanlı olduğuna göre s(A ∩ B) kaçtır?',
        z,
        [sa + sb - n, z + n0, bir - sb, n - bir],
        's(A ∪ B) = $n − $n0 = $bir olur. s(A ∩ B) = s(A) + s(B) − s(A ∪ B) '
        '= $sa + $sb − $bir = $z bulunur.',
        positive: true,
      );
    case 2:
      return sayisal(
        '$on s(E) = $n, s(A) = $sa, s(B) = $sb ve s(A ∩ B) = $z olduğuna '
        'göre s(A′ ∪ B′) kaçtır?',
        n - z,
        [n0, n - bir + z, 2 * n - sa - sb, bir - z],
        'De Morgan kuralına göre A′ ∪ B′ = (A ∩ B)′ olur. Eleman sayısı '
        's(E) − s(A ∩ B) = $n − $z = ${n - z} bulunur.',
        positive: true,
      );
    case 3:
      final alt = _kuvvet(2, p);
      return sayisal(
        '$on s(E) = $n, s(A) = $sa ve s(B) = $sb veriliyor. A ∪ B kümesinin '
        'tümleyeni $n0 elemanlı olduğuna göre A \\ B kümesinin alt küme '
        'sayısı kaçtır?',
        alt,
        [_kuvvet(2, sa), p, 2 * p, _kuvvet(2, z), alt - 1],
        's(A ∪ B) = $n − $n0 = $bir ve s(A \\ B) = s(A ∪ B) − s(B) = '
        '$bir − $sb = $p olur. $p elemanlı kümenin alt küme sayısı '
        '2${_ust(p)} = $alt bulunur.',
        positive: true,
      );
    case 4:
      return sayisal(
        '$on s(E) = $n, s(A \\ B) = $p, s(B \\ A) = $q ve s(A ∩ B) = $z '
        'olduğuna göre s(B′) kaçtır?',
        n - sb,
        [n - q, n0, p, n - bir + z],
        's(B) = s(B \\ A) + s(A ∩ B) = $q + $z = $sb olur. '
        's(B′) = s(E) − s(B) = $n − $sb = ${n - sb} bulunur.',
        positive: true,
      );
    case 5:
      return sayisal(
        '$n ${ctx.grup} ${ctx.x} $sa, ${ctx.y} $sb, ${ctx.ikisi} $z kişi '
        'vardır. Buna göre ${ctx.hic} kaç kişi vardır?',
        n0,
        [n - sa - sb, n0 + z, bir, n - sa],
        'En az birini sağlayanların sayısı $sa + $sb − $z = $bir olur. '
        'Hiçbirini sağlamayanların sayısı $n − $bir = $n0 bulunur.',
        positive: true,
      );
    case 6:
      return sayisal(
        '$n ${ctx.grup} ${ctx.x} $sa, ${ctx.y} $sb, ${ctx.ikisi} $z kişi '
        'vardır. Buna göre ${ctx.yalnizBir} kaç kişi vardır?',
        p + q,
        [bir, sa + sb, sa + sb - z, n - z, p + q + n0],
        'Yalnız ${ctx.x} $sa − $z = $p, yalnız ${ctx.y} $sb − $z = $q '
        'kişidir. Toplam $p + $q = ${p + q} bulunur.',
        positive: true,
      );
    case 7:
      return sayisal(
        '$n ${ctx.grup} ${ctx.x} $sa, ${ctx.y} $sb, ${ctx.hic} $n0 kişi '
        'vardır. Buna göre ${ctx.ikisi} kaç kişi vardır?',
        z,
        [sa + sb - n, z + n0, n - bir, bir - sa],
        'En az birini sağlayanların sayısı $n − $n0 = $bir olur. İkisini de '
        'sağlayanların sayısı $sa + $sb − $bir = $z bulunur.',
        positive: true,
      );
    case 8:
      return sayisal(
        'Bir toplulukta ${ctx.x} $sa, ${ctx.y} $sb, ${ctx.ikisi} $z, '
        '${ctx.hic} $n0 kişi vardır. Buna göre bu toplulukta toplam kaç kişi '
        'vardır?',
        n,
        [sa + sb + z + n0, sa + sb + n0, bir, n + z + 1],
        'En az birini sağlayanların sayısı $sa + $sb − $z = $bir olur. '
        'Hiçbirini sağlamayan $n0 kişi eklenince toplam $bir + $n0 = $n '
        'bulunur.',
        positive: true,
      );
    default:
      return sayisal(
        '$n ${ctx.grup} ${ctx.x} $sa, ${ctx.y} $sb, ${ctx.ikisi} $z kişi '
        'vardır. Buna göre ${ctx.enCokBir} kaç kişi vardır?',
        n - z,
        [p + q, bir, n0, n - bir + z],
        'En çok birini sağlayanlar, ikisini birden sağlayanların dışında '
        'kalanlardır: $n − $z = ${n - z}.',
        positive: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 13. Bileşik önermelerin doğruluk değeri
// ---------------------------------------------------------------------------

const _baglaclar = ['∧', '∨', '⇒', '⇔'];

bool _bagla(int op, bool x, bool y) => switch (op) {
  0 => x && y,
  1 => x || y,
  2 => !x || y,
  _ => x == y,
};

/// Yalın önerme ya da değili: 0 p, 1 q, 2 r, 3 p′, 4 q′, 5 r′.
String _yalinYaz(int l) => '${'pqr'[l % 3]}${l >= 3 ? '′' : ''}';

bool _yalinDeger(int l, List<bool> d) => l >= 3 ? !d[l % 3] : d[l % 3];

String _bit(bool x) => x ? '1' : '0';

// I. (X ∘ Y) ∘ Z kalıbı: 5 üçlü × 5 bağlaç çifti.
const _onermeUclu1 = [(0, 1, 2), (0, 4, 2), (3, 1, 5), (1, 2, 3), (5, 0, 1)];
const _onermeBaglac1 = [(0, 2), (1, 2), (2, 1), (0, 3), (1, 0)];
// II. X ∘ (Y ∘ Z) kalıbı: 4 üçlü × 5 bağlaç çifti.
const _onermeUclu2 = [(0, 1, 2), (4, 0, 2), (2, 3, 1), (3, 5, 1)];
const _onermeBaglac2 = [(2, 1), (0, 2), (1, 0), (3, 0), (2, 2)];
// III. (X ∘ Y)′ ∘ Z kalıbı: 2 üçlü × 5 bağlaç çifti.
const _onermeUclu3 = [(0, 2, 1), (1, 5, 0)];
const _onermeBaglac3 = [(0, 1), (1, 2), (2, 0), (1, 3), (3, 1)];

AdvancedItem _onerme(int a, int b, int c) {
  final kod = (a + 2 * b + 3 * c) % 8;
  final d = [kod & 4 != 0, kod & 2 != 0, kod & 1 != 0];
  String dy(bool x) => x ? 'D' : 'Y';
  String ad(bool x) => x ? 'doğru' : 'yanlış';

  // I
  final (x1, y1, z1) = _onermeUclu1[a ~/ 5];
  final (o1, p1) = _onermeBaglac1[a % 5];
  final ic1 = _bagla(o1, _yalinDeger(x1, d), _yalinDeger(y1, d));
  final s1 = _bagla(p1, ic1, _yalinDeger(z1, d));
  final yazi1 =
      '(${_yalinYaz(x1)} ${_baglaclar[o1]} ${_yalinYaz(y1)}) '
      '${_baglaclar[p1]} ${_yalinYaz(z1)}';
  final cozum1 =
      '(${_bit(_yalinDeger(x1, d))} ${_baglaclar[o1]} '
      '${_bit(_yalinDeger(y1, d))}) ${_baglaclar[p1]} '
      '${_bit(_yalinDeger(z1, d))} ≡ ${_bit(ic1)} ${_baglaclar[p1]} '
      '${_bit(_yalinDeger(z1, d))} ≡ ${_bit(s1)}';

  // II
  final (x2, y2, z2) = _onermeUclu2[b ~/ 5];
  final (o2, p2) = _onermeBaglac2[b % 5];
  final ic2 = _bagla(p2, _yalinDeger(y2, d), _yalinDeger(z2, d));
  final s2 = _bagla(o2, _yalinDeger(x2, d), ic2);
  final yazi2 =
      '${_yalinYaz(x2)} ${_baglaclar[o2]} '
      '(${_yalinYaz(y2)} ${_baglaclar[p2]} ${_yalinYaz(z2)})';
  final cozum2 =
      '${_bit(_yalinDeger(x2, d))} ${_baglaclar[o2]} '
      '(${_bit(_yalinDeger(y2, d))} ${_baglaclar[p2]} '
      '${_bit(_yalinDeger(z2, d))}) ≡ ${_bit(_yalinDeger(x2, d))} '
      '${_baglaclar[o2]} ${_bit(ic2)} ≡ ${_bit(s2)}';

  // III
  final (x3, y3, z3) = _onermeUclu3[c ~/ 5];
  final (o3, p3) = _onermeBaglac3[c % 5];
  final ic3 = _bagla(o3, _yalinDeger(x3, d), _yalinDeger(y3, d));
  final s3 = _bagla(p3, !ic3, _yalinDeger(z3, d));
  final yazi3 =
      '(${_yalinYaz(x3)} ${_baglaclar[o3]} ${_yalinYaz(y3)})′ '
      '${_baglaclar[p3]} ${_yalinYaz(z3)}';
  final cozum3 =
      '(${_bit(_yalinDeger(x3, d))} ${_baglaclar[o3]} '
      '${_bit(_yalinDeger(y3, d))})′ ${_baglaclar[p3]} '
      '${_bit(_yalinDeger(z3, d))} ≡ ${_bit(!ic3)} ${_baglaclar[p3]} '
      '${_bit(_yalinDeger(z3, d))} ≡ ${_bit(s3)}';

  String dizi(bool u, bool v, bool w) => '${dy(u)} – ${dy(v)} – ${dy(w)}';
  return secenekli(
    'p ${ad(d[0])}, q ${ad(d[1])} ve r ${ad(d[2])} birer önermedir; ′ işareti, '
    'sonuna yazıldığı önermenin değilini gösterir.\n'
    'I. $yazi1\nII. $yazi2\nIII. $yazi3\n'
    'Bu bileşik önermelerin doğruluk değerleri (D: doğru, Y: yanlış) numara '
    'sırasıyla hangi seçenekte doğru verilmiştir?',
    dizi(s1, s2, s3),
    [dizi(s1, s2, !s3), dizi(!s1, s2, s3), dizi(s1, !s2, s3)],
    'p ≡ ${_bit(d[0])}, q ≡ ${_bit(d[1])}, r ≡ ${_bit(d[2])} alınır; '
    'değiller bunların tersidir. I. $cozum1. II. $cozum2. III. $cozum3. '
    'Sonuç: ${dizi(s1, s2, s3)}.',
  );
}

// ---------------------------------------------------------------------------
// 14. Modüler aritmetik
// ---------------------------------------------------------------------------

/// 5, 7 ve 11 ile bölümünden kalanı 0 ya da 1 olmayan tabanlar.
const _modTabanlari = [
  2, 3, 4, 9, 13, 17, 18, 19, 24, 27, 32, 37, 38,
  39, 47, 48, 52, 53, 54, 58, 59, 62, 68, 69, 72,
];

/// Seçenek ve cümle başı yazımı.
const _gunler = [
  'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar',
];

/// Cümle içi yazım: belirli bir tarih bildirmeyen gün adı küçük harfle
/// başlar.
const _gunlerKucuk = [
  'pazartesi', 'salı', 'çarşamba', 'perşembe', 'cuma', 'cumartesi', 'pazar',
];

int _modKuvvet(int taban, int us, int m) {
  var sonuc = 1, t = taban % m, e = us;
  while (e > 0) {
    if (e.isOdd) sonuc = sonuc * t % m;
    t = t * t % m;
    e ~/= 2;
  }
  return sonuc;
}

AdvancedItem _kalanSecenekli(
  String prompt,
  int yanit,
  int m,
  Iterable<int> adaylar,
  String aciklama, {
  int alt = 0,
}) {
  final pool = [
    ...adaylar,
    for (var k = 1; k < m; k++) alt + (yanit - alt + k) % m,
  ].where((x) => x >= alt && x < alt + m);
  return secenekli(prompt, '$yanit', pool.map((x) => '$x'), aciklama);
}

AdvancedItem _moduler(int a, int b, int c) {
  if (c < 3) {
    final x = _modTabanlari[a], e = 13 + 7 * b, m = const [5, 7, 11][c];
    final r = x % m;
    var periyot = 1, guc = r;
    while (guc != 1) {
      guc = guc * r % m;
      periyot++;
    }
    final j = e % periyot;
    final yanit = _modKuvvet(x, e, m);
    final adim1 = r == x ? '' : '$x ≡ $r (mod $m) olur. ';
    final aciklama = periyot == 1
        ? '$x ≡ 1 (mod $m) olduğundan her kuvveti de 1 kalanını verir.'
        : '$adim1$r${_ust(periyot)} ≡ 1 (mod $m) olduğundan kalanlar $periyot '
              'adımda yinelenir. $e = $periyot·${e ~/ periyot} + $j yazılır; '
              '${j == 0 ? 'kalan 1' : '$r${_ust(j)} ≡ $yanit (mod $m)'} '
              'bulunur.';
    return _kalanSecenekli(
      '$x${_ust(e)} sayısının $m ile bölümünden kalan kaçtır?',
      yanit,
      m,
      [_modKuvvet(r, e % m, m), r, r * e % m, e % m, 1],
      aciklama,
    );
  }
  if (c < 5) {
    final kalan = 1 + a % 6, bolum = 3 + a ~/ 6 + 5 * b;
    final n = 7 * bolum + kalan;
    final bas = (a + 2 * b) % 7;
    final ileri = c == 3;
    final son = ileri ? (bas + kalan) % 7 : (bas - kalan + 7) % 7;
    final ters = ileri ? (bas - kalan + 7) % 7 : (bas + kalan) % 7;
    final yon = ileri ? 'sonraki' : 'önceki';
    final yonKisa = ileri ? 'sonrasıyla' : 'öncesiyle';
    final adaylar = [ters, (son + 1) % 7, (son + 6) % 7, bas, (son + 2) % 7];
    return secenekli(
      'Bugün günlerden ${_gunlerKucuk[bas]} olduğuna göre bugünden $n gün '
      '$yon gün hangisidir?',
      _gunler[son],
      adaylar.map((g) => _gunler[g]),
      '$n = 7·$bolum + $kalan olduğundan $n gün, $kalan gün $yonKisa aynı '
      'güne denk gelir. ${_gunler[bas]} gününden $kalan gün $yon gün '
      '${_gunlerKucuk[son]} olur.',
    );
  }
  if (c < 7) {
    final kalan = 1 + a % 11, bolum = 2 + a ~/ 11 + 3 * b;
    final n = 12 * bolum + kalan;
    final bas = 1 + (a + b) % 12;
    final ileri = c == 5;
    int kadran(int x) => (x - 1) % 12 + 1;
    final son = ileri ? kadran(bas + kalan) : kadran(bas - kalan + 12);
    final ters = ileri ? kadran(bas - kalan + 12) : kadran(bas + kalan);
    return _kalanSecenekli(
      ileri
          ? 'Bir duvar saatinin akrebi şu anda tam $bas sayısının '
                'üzerindedir. Bu andan $n saat sonra akrep hangi sayının '
                'üzerinde olur?'
          : 'Bir duvar saatinin akrebi şu anda tam $bas sayısının '
                'üzerindedir. Bu andan $n saat önce akrep hangi sayının '
                'üzerindeydi?',
      son,
      12,
      [ters, kadran(son + 1), kadran(son + 11), kalan, bas],
      '$n = 12·$bolum + $kalan olduğundan akrep $bolum tam tur atar ve '
      '$kalan saat ${ileri ? 'ileride' : 'geride'} bulunur: '
      '${ileri ? '$bas + $kalan' : '$bas − $kalan'} işlemi 12 saatlik '
      'kadranda $son sayısına karşılık gelir.',
      alt: 1,
    );
  }
  final m = const [7, 8, 9, 11, 13][b % 5];
  final r1 = 2 + a % 5, r2 = 1 + a ~/ 5, k = 2 + b ~/ 5;
  final (ifade, deger, hesap) = switch (c) {
    7 => ('x·y + $k', r1 * r2 + k, '$r1·$r2 + $k'),
    8 => ('${k}x + y', k * r1 + r2, '$k·$r1 + $r2'),
    _ => ('x² + ${k}y', r1 * r1 + k * r2, '$r1² + $k·$r2'),
  };
  final yanit = deger % m;
  return _kalanSecenekli(
    'x ve y birer pozitif tam sayıdır. x sayısının $m ile bölümünden kalan '
    '$r1, y sayısının $m ile bölümünden kalan $r2 olduğuna göre $ifade '
    'sayısının $m ile bölümünden kalan kaçtır?',
    yanit,
    m,
    [(r1 + r2 + k) % m, r1 * r2 % m, (deger + r1) % m, (r1 + r2) % m],
    'Kalanlar yerine yazılır: $hesap = $deger. $deger sayısının $m ile '
    'bölümünden kalan $yanit olur.',
  );
}

// ---------------------------------------------------------------------------
// 15. Toplama ve çarpma yoluyla sayma
// ---------------------------------------------------------------------------

const _rakamlar = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

/// (a, b) ikilisine özgü rakam kümesi: 250 beşli, 210 altılı, 40 yedili.
List<int> _rakamKumesi(int a, int b) {
  final idx = a + 25 * b;
  if (idx >= 460) return kombinasyon(_rakamlar, 7, idx - 460, spread: false);
  if (idx >= 250) return kombinasyon(_rakamlar, 6, idx - 250, spread: false);
  final s = kombinasyon(_rakamlar, 5, idx, spread: false);
  // Tümü çift ya da tümü tek olan iki küme yerine sıradaki son iki küme.
  if (s.every((x) => x.isEven)) {
    return kombinasyon(_rakamlar, 5, 250, spread: false);
  }
  if (s.every((x) => x.isOdd)) {
    return kombinasyon(_rakamlar, 5, 251, spread: false);
  }
  return s;
}

AdvancedItem _rakamlaSayi(int a, int b, int c) {
  final s = _rakamKumesi(a, b);
  final n = s.length;
  final z = s.contains(0) ? 1 : 0;
  final cift = s.where((x) => x.isEven).length, tek = n - cift;
  final ciftSifirsiz = cift - z;
  final giris = '${_liste(s)} rakamları kullanılarak';
  final ilk = z == 1
      ? 'Sıfır başa gelemeyeceği için ilk basamağa ${n - 1}'
      : 'İlk basamağa $n';
  switch (c) {
    case 4:
      final yanit = (n - z) * (n - 1) * (n - 2);
      return sayisal(
        '$giris üç basamaklı, rakamları birbirinden farklı kaç doğal sayı '
        'yazılabilir?',
        yanit,
        [
          n * (n - 1) * (n - 2),
          (n - z) * n * n,
          _komb(n, 3),
          (n - 1) * (n - 2) * (n - 3),
        ],
        '$ilk, ikinci basamağa ${n - 1}, üçüncü basamağa ${n - 2} rakam '
        'yazılabilir: ${n - z}·${n - 1}·${n - 2} = $yanit.',
        positive: true,
      );
    case 5:
      final sifirli = z * (n - 1) * (n - 2);
      final diger = ciftSifirsiz * (n - 1 - z) * (n - 2);
      final yanit = sifirli + diger;
      return sayisal(
        '$giris üç basamaklı, rakamları birbirinden farklı kaç çift doğal '
        'sayı yazılabilir?',
        yanit,
        [
          cift * (n - 1) * (n - 2),
          (n - z) * (n - 1) * cift,
          (n - z) * (n - 1) * (n - 2),
          tek * (n - 1 - z) * (n - 2),
        ],
        z == 1 && ciftSifirsiz == 0
            ? 'Verilen rakamlardan çift olan yalnız 0 olduğundan birler '
                  'basamağına 0 yazılır. İlk basamağa kalan ${n - 1}, ortaya '
                  'kalan ${n - 2} rakamdan biri gelir: ${n - 1}·${n - 2} = '
                  '$yanit.'
            : z == 1
            ? 'Birler basamağı 0 ise ${n - 1}·${n - 2} = $sifirli sayı '
                  'yazılır. Birler basamağı sıfırdan farklı $ciftSifirsiz '
                  'çift rakamdan biri ise ilk basamağa ${n - 2}, ortaya '
                  '${n - 2} rakam gelir: $ciftSifirsiz·${n - 2}·${n - 2} = '
                  '$diger. Toplam $sifirli + $diger = $yanit.'
            : 'Birler basamağına $cift çift rakamdan biri, ilk basamağa kalan '
                  '${n - 1}, ortaya kalan ${n - 2} rakamdan biri yazılır: '
                  '$cift·${n - 1}·${n - 2} = $yanit.',
        positive: true,
      );
    case 6:
      final yanit = (n - z) * n * n;
      return sayisal(
        '$giris, bir rakam birden çok kez kullanılabilmek koşuluyla üç '
        'basamaklı kaç doğal sayı yazılabilir?',
        yanit,
        [
          (n - z) * (n - 1) * (n - 2),
          n * n * n + z,
          (n - z) * (n - z) * (n - z) + z,
          3 * n,
        ],
        '$ilk, öteki iki basamağın her birine $n rakam yazılabilir: '
        '${n - z}·$n·$n = $yanit.',
        positive: true,
      );
    case 7:
      final yanit = tek * (n - 1 - z) * (n - 2);
      return sayisal(
        '$giris üç basamaklı, rakamları birbirinden farklı kaç tek doğal '
        'sayı yazılabilir?',
        yanit,
        [
          tek * (n - 1) * (n - 2) + z,
          (n - z) * (n - 1) * tek,
          (n - z) * (n - 1) * (n - 2),
          tek * n * n,
        ],
        'Birler basamağına $tek tek rakamdan biri yazılır. '
        '${z == 1 ? 'Sıfır başa gelemeyeceği için ilk' : 'İlk'} basamağa '
        'kalan ${n - 1 - z}, ortaya kalan ${n - 2} rakamdan biri gelir: '
        '$tek·${n - 1 - z}·${n - 2} = $yanit.',
        positive: true,
      );
    case 8:
      final yanit = (n - z) * (n - 1) * (n - 2) * (n - 3);
      return sayisal(
        '$giris dört basamaklı, rakamları birbirinden farklı kaç doğal sayı '
        'yazılabilir?',
        yanit,
        [
          n * (n - 1) * (n - 2) * (n - 3) + z,
          (n - z) * n * n * n,
          _komb(n, 4),
          (n - z) * (n - 1) * (n - 2),
        ],
        '$ilk, sonraki basamaklara sırasıyla ${n - 1}, ${n - 2} ve ${n - 3} '
        'rakam yazılabilir: ${n - z}·${n - 1}·${n - 2}·${n - 3} = $yanit.',
        positive: true,
      );
    default:
      final yanit = (n - z) * n * cift;
      return sayisal(
        '$giris, bir rakam birden çok kez kullanılabilmek koşuluyla üç '
        'basamaklı kaç çift doğal sayı yazılabilir?',
        yanit,
        [
          (n - z) * n * n,
          n * n * cift + z,
          (n - z) * n * tek,
          (n - z) * (n - 1) * cift,
        ],
        '$ilk, onlar basamağına $n, birler basamağına $cift çift rakamdan '
        'biri yazılabilir: ${n - z}·$n·$cift = $yanit.',
        positive: true,
      );
  }
}

const _yerAdlari = [
  ['A', 'B', 'C', 'D'],
  ['K', 'L', 'M', 'N'],
  ['P', 'R', 'S', 'T'],
];

AdvancedItem _sayma(int a, int b, int c) {
  if (c >= 4) return _rakamlaSayi(a, b, c);
  final x = 2 + a % 5, y = 2 + a ~/ 5;
  final yer = _yerAdlari[(a + b) % 3];
  final k1 = yer[0], k2 = yer[1], k3 = yer[2], k4 = yer[3];
  switch (c) {
    case 0:
      final z = 1 + b % 4, t = 2 + b ~/ 4;
      final yanit = (x * y + z) * t;
      return sayisal(
        '$k1 kentinden $k2 kentine $x, $k2 kentinden $k3 kentine $y farklı '
        'yol vardır. Ayrıca $k1 kentinden $k3 kentine, $k2 kentine uğramadan '
        'giden $z farklı yol bulunmaktadır. $k3 kentinden $k4 kentine ise $t '
        'farklı yol vardır. Buna göre $k1 kentinden $k4 kentine kaç farklı '
        'yoldan gidilebilir?',
        yanit,
        [x * y * z * t, (x + y + z) * t, x * y + z + t, x * y * t + z],
        '$k1 kentinden $k3 kentine $k2 üzerinden $x·$y = ${x * y}, doğrudan '
        '$z yolla gidilir: ${x * y} + $z = ${x * y + z}. Her biri $t yolla '
        'sürdürülür: ${x * y + z}·$t = $yanit.',
        positive: true,
      );
    case 1:
      final u = 2 + b % 4, tur = b ~/ 4;
      final gidis = x * y * u;
      final giris =
          '$k1 köyünden $k2 köyüne $x, $k2 köyünden $k3 köyüne $y, $k3 '
          'köyünden $k4 köyüne $u farklı yol vardır; köyler arasında başka '
          'yol yoktur.';
      final (soru, yanit, yanlis, cozum) = switch (tur) {
        0 => (
          '$k1 köyünden $k4 köyüne kaç farklı yoldan gidilebilir?',
          gidis,
          [x + y + u, x * y + u, x * (y + u), 2 * gidis],
          'Her aşamadaki seçenekler çarpılır: $x·$y·$u = $gidis.',
        ),
        1 => (
          '$k1 köyünden $k4 köyüne gidip yeniden $k1 köyüne dönen biri bu '
              'yolculuğu kaç farklı şekilde yapabilir?',
          gidis * gidis,
          [
            2 * gidis,
            gidis,
            gidis * (gidis - 1),
            gidis * (x - 1) * (y - 1) * (u - 1),
          ],
          'Gidiş $x·$y·$u = $gidis, dönüş de $gidis farklı şekilde yapılır: '
              '$gidis·$gidis = ${gidis * gidis}.',
        ),
        2 => (
          '$k1 köyünden $k4 köyüne gidip yeniden $k1 köyüne dönen biri, '
              'gidişte kullandığı yolların hiçbirini dönüşte kullanmamak '
              'koşuluyla bu yolculuğu kaç farklı şekilde yapabilir?',
          gidis * (x - 1) * (y - 1) * (u - 1),
          [
            gidis * gidis,
            gidis * (gidis - 1),
            gidis + (x - 1) * (y - 1) * (u - 1),
            gidis,
          ],
          'Gidiş $x·$y·$u = $gidis şekilde yapılır. Dönüşte her aşamada bir '
              'yol eksilir: ${u - 1}·${y - 1}·${x - 1} = '
              '${(x - 1) * (y - 1) * (u - 1)}. Çarpım: '
              '$gidis·${(x - 1) * (y - 1) * (u - 1)} = '
              '${gidis * (x - 1) * (y - 1) * (u - 1)}.',
        ),
        3 => (
          '$k1 köyünden $k4 köyüne gidip yeniden $k1 köyüne dönen biri, '
              'dönüş güzergâhının gidiş güzergâhıyla tümüyle aynı olmaması '
              'koşuluyla bu yolculuğu kaç farklı şekilde yapabilir?',
          gidis * (gidis - 1),
          [
            gidis * gidis,
            gidis * (x - 1) * (y - 1) * (u - 1),
            2 * gidis - 1,
            gidis - 1,
          ],
          'Gidiş $x·$y·$u = $gidis şekilde yapılır. Dönüş için gidişin '
              'aynısı dışında $gidis − 1 = ${gidis - 1} güzergâh kalır: '
              '$gidis·${gidis - 1} = ${gidis * (gidis - 1)}.',
        ),
        _ => (
          '$k1 köyünden $k4 köyüne gidip yeniden $k1 köyüne dönen biri, '
              'dönüşte yalnızca $k1 ile $k2 köyleri arasında gidişte '
              'kullandığı yolu kullanmamak koşuluyla bu yolculuğu kaç farklı '
              'şekilde yapabilir?',
          gidis * u * y * (x - 1),
          [
            gidis * gidis,
            gidis * (x - 1) * (y - 1) * (u - 1),
            gidis * (x - 1),
            gidis * (gidis - 1),
          ],
          'Gidiş $x·$y·$u = $gidis şekilde yapılır. Dönüşte $u·$y·${x - 1} '
              '= ${u * y * (x - 1)} seçenek vardır: '
              '$gidis·${u * y * (x - 1)} = ${gidis * u * y * (x - 1)}.',
        ),
      };
      return sayisal('$giris $soru', yanit, yanlis, cozum, positive: true);
    case 2:
      final e = 1 + b % 4, k = 2 + b ~/ 4;
      final yanit = x * (y + e) * k;
      return sayisal(
        'Bir mağazada $x farklı gömlek, $y farklı pantolon, $e farklı etek '
        've $k farklı ayakkabı beğenen biri; bir gömlek, alt giyim olarak bir '
        'pantolon ya da bir etek ve bir ayakkabıdan oluşan bir takımı kaç '
        'farklı şekilde seçebilir?',
        yanit,
        [x * y * e * k, x + y + e + k, x * y * k + e, (x + y + e) * k],
        'Alt giyim için $y + $e = ${y + e} seçenek vardır. Gömlek, alt '
        'giyim ve ayakkabı seçimleri çarpılır: $x·${y + e}·$k = $yanit.',
        positive: true,
      );
    default:
      final z = 1 + b % 4, t = 2 + b ~/ 4;
      final yanit = y * t * (x + z);
      return sayisal(
        'Bir lokantanın menüsünde $x çeşit çorba, $y çeşit ana yemek, $z '
        'çeşit tatlı ve $t çeşit içecek vardır. Bir ana yemek ile bir içecek '
        'mutlaka, çorba ve tatlı çeşitlerinin tümü içinden ise yalnızca bir '
        'tane seçilerek kaç farklı öğün oluşturulabilir?',
        yanit,
        [x * y * z * t, y * t * x * z + 1, x + y + z + t, y * t + x + z],
        'Çorba ya da tatlı için $x + $z = ${x + z} seçenek vardır. Ana '
        'yemek, içecek ve bu seçim çarpılır: $y·$t·${x + z} = $yanit.',
        positive: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 16. Deneysel olasılık ve göreli sıklık
// ---------------------------------------------------------------------------

const _sikliBaglamlari = [
  (
    veri: 'Bir kavşaktan geçen',
    son: 'aracın',
    olgu: 'tanesinin şehir dışı plakalı olduğu gözlenmiştir',
    olumlu: 'kavşaktan geçen bir aracın şehir dışı plakalı olmasının',
    olumsuz: 'kavşaktan geçen bir aracın şehir dışı plakalı olmamasının',
  ),
  (
    veri: 'Bir kargo merkezine gelen',
    son: 'paketin',
    olgu: 'tanesinin şehir dışından geldiği görülmüştür',
    olumlu: 'merkeze gelen bir paketin şehir dışından gelmesinin',
    olumsuz: 'merkeze gelen bir paketin şehir dışından gelmemesinin',
  ),
  (
    veri: 'Bir ankete katılan',
    son: 'kişinin',
    olgu: 'tanesi “evet” yanıtını vermiştir',
    olumlu: 'bir katılımcının “evet” yanıtı vermesinin',
    olumsuz: 'bir katılımcının “evet” yanıtı vermemesinin',
  ),
  (
    veri: 'Bir kütüphaneden ödünç alınan',
    son: 'kitabın',
    olgu: 'tanesinin roman olduğu belirlenmiştir',
    olumlu: 'ödünç alınan bir kitabın roman olmasının',
    olumsuz: 'ödünç alınan bir kitabın roman olmamasının',
  ),
  (
    veri: 'Bir seradaki',
    son: 'fidenin',
    olgu: 'tanesinin çiçek açtığı gözlenmiştir',
    olumlu: 'seradaki bir fidenin çiçek açmasının',
    olumsuz: 'seradaki bir fidenin çiçek açmamasının',
  ),
];

/// Çimlenme ve serbest atış isabeti için gerçekçi oranlar (1/2 … 11/12).
const _basariOranlari = [
  (1, 2), (3, 5), (2, 3), (3, 4), (4, 5), (5, 6), (4, 7), (5, 7), (6, 7),
  (5, 8), (7, 8), (5, 9), (7, 9), (8, 9), (7, 10), (9, 10), (6, 11), (7, 11),
  (8, 11), (9, 11), (10, 11), (7, 12), (11, 12), (9, 13), (11, 13),
];

AdvancedItem _deneysel(int a, int b, int c) {
  final v = c ~/ 5;
  switch (c % 5) {
    case 0:
      final f1 = 6 + a, f2 = 5 + b, f3 = 4 + (3 * a + 5 * b) % 9;
      final n = f1 + f2 + f3;
      final giris =
          'Üç renkli bir çark $n kez çevrilmiş; ibre $f1 kez kırmızı, $f2 kez '
          'mavi, $f3 kez sarı bölgede durmuştur.';
      if (v == 0) {
        return _olasilik(
          '$giris Bu deneye göre ibrenin mavi bölgede durmasının deneysel '
          'olasılığı kaçtır?',
          f2,
          n,
          [(1, 3), (f2, f1 + f3), (f1, n), (f3, n)],
          'Deneysel olasılık, olayın gerçekleşme sayısının deneme sayısına '
          'oranıdır: ${_sade(f2, n)}.',
        );
      }
      return _olasilik(
        '$giris Bu deneye göre ibrenin kırmızı ya da sarı bölgede durmasının '
        'deneysel olasılığı kaçtır?',
        f1 + f3,
        n,
        [(2, 3), (f2, n), (f1, n), (f1 * f3, n * n)],
        'Kırmızı ya da sarı bölgede durma sayısı $f1 + $f3 = ${f1 + f3} '
        'olur. Deneysel olasılık ${_sade(f1 + f3, n)} bulunur.',
      );
    case 1:
      final (k0, n0) = _basariOranlari[a];
      final g = 3 + 2 * (b % 5), t = 2 + b ~/ 5;
      final n = n0 * g * 5, k = k0 * g * 5, m = n0 * t * 10;
      final beklenen = k0 * t * 10;
      return sayisal(
        v == 0
            ? 'Bir fidanlıkta ekilen $n tohumdan $k tanesi çimlenmiştir. Aynı '
                  'koşullarda $m tohum ekilirse bu deneysel olasılığa göre '
                  'kaç tohumun çimlenmesi beklenir?'
            : 'Bir basketbolcu antrenmanlarda attığı $n serbest atışın $k '
                  'tanesini sayıya çevirmiştir. Bu deneysel olasılığa göre '
                  'oyuncunun atacağı $m serbest atışın kaç tanesini sayıya '
                  'çevirmesi beklenir?',
        beklenen,
        [m - beklenen, k, (m - n + k).abs(), beklenen + 10 * t, m ~/ 2],
        'Deneysel olasılık $k/$n = ${kesir(k, n)} olur. Beklenen sayı '
        '$m·(${kesir(k, n)}) = $beklenen bulunur.',
        positive: true,
      );
    case 2:
      final ctx = _sikliBaglamlari[a ~/ 5];
      final n = 100 * (2 + a % 5), yuzde = 3 + 4 * b;
      final k = n * yuzde ~/ 100;
      final giris = '${ctx.veri} $n ${ctx.son} $k ${ctx.olgu}.';
      if (v == 0) {
        return _yuzdeli(
          '$giris Bu gözleme göre ${ctx.olumlu} göreli sıklığı yüzde kaçtır?',
          yuzde,
          [100 - yuzde, k, 100 * k ~/ (n - k), yuzde * 2],
          'Göreli sıklık $k/$n olur. Yüzde olarak $k·100 : $n = $yuzde '
          'bulunur.',
        );
      }
      return _yuzdeli(
        '$giris Bu gözleme göre ${ctx.olumsuz} göreli sıklığı yüzde kaçtır?',
        100 - yuzde,
        [yuzde, k, 100 * (n - k) ~/ (n + k), 100 - yuzde ~/ 2],
        'Olayın gerçekleşmediği durum sayısı $n − $k = ${n - k} olur. '
        'Göreli sıklık ${n - k}/$n, yüzde olarak ${n - k}·100 : $n = '
        '${100 - yuzde} bulunur.',
      );
    case 3:
      final f = [
        5 + a % 5,
        4 + a ~/ 5,
        6 + b % 4,
        5 + b ~/ 4,
        7 + (a + b) % 3,
        5 + (2 * a + b) % 4,
      ];
      final n = f.fold<int>(0, (x, y) => x + y);
      final giris =
          'Bir zar $n kez atılmış; 1 sayısı ${f[0]}, 2 sayısı ${f[1]}, 3 '
          'sayısı ${f[2]}, 4 sayısı ${f[3]}, 5 sayısı ${f[4]} ve 6 sayısı '
          '${f[5]} kez üste gelmiştir.';
      if (v == 0) {
        final pay = f[1] + f[3] + f[5];
        return _olasilik(
          '$giris Bu deneye göre zarın üst yüzüne çift sayı gelmesinin '
          'deneysel olasılığı kaçtır?',
          pay,
          n,
          [(1, 2), (n - pay, n), (f[1] + f[3], n), (3, n)],
          'Çift sayıların gelme sayısı ${f[1]} + ${f[3]} + ${f[5]} = $pay '
          'olur. Deneysel olasılık ${_sade(pay, n)} bulunur.',
        );
      }
      final pay = f[1] + f[2] + f[4];
      return _olasilik(
        '$giris Bu deneye göre zarın üst yüzüne asal sayı gelmesinin '
        'deneysel olasılığı kaçtır?',
        pay,
        n,
        [
          (1, 2),
          (f[0] + f[1] + f[2] + f[4], n),
          (f[0] + f[2] + f[4], n),
          (n - pay, n),
        ],
        'Asal sayılar 2, 3 ve 5 olduğundan gelme sayısı '
        '${f[1]} + ${f[2]} + ${f[4]} = $pay olur. Deneysel olasılık '
        '${_sade(pay, n)} bulunur.',
      );
    default:
      final n = 2 * (20 + a), d = 1 + b % 5;
      final tura = n ~/ 2 + d, yazi = n - tura;
      final giris = v == 0
          ? 'Bir madenî para $n kez atılmış ve $tura kez tura gelmiştir.'
          : 'Bir madenî para $n kez atılmış ve $yazi kez yazı gelmiştir.';
      final ek = v == 0
          ? 'Yazı sayısı $n − $tura = $yazi olur.'
          : 'Tura sayısı $n − $yazi = $tura olur.';
      switch (b ~/ 5) {
        case 0:
          return _olasilik(
            '$giris Bu deneye göre tura gelmesinin deneysel olasılığı '
            'kaçtır?',
            tura,
            n,
            [(1, 2), (yazi, n), (tura, yazi + n), (yazi, tura)],
            '${v == 0 ? '' : '$ek '}Tura gelmesinin deneysel olasılığı '
            '${_sade(tura, n)} olur.',
          );
        case 1:
          return _olasilik(
            '$giris Bu deneye göre yazı gelmesinin deneysel olasılığı '
            'kaçtır?',
            yazi,
            n,
            [(1, 2), (tura, n), (yazi, tura), (yazi, tura + n)],
            '${v == 0 ? '$ek ' : ''}Yazı gelmesinin deneysel olasılığı '
            '${_sade(yazi, n)} olur.',
          );
        case 2:
          return _olasilik(
            '$giris Bu deneyde tura gelmesinin deneysel olasılığı, teorik '
            'olasılığından kaç fazladır?',
            d,
            n,
            [(2 * d, n), (tura, n), (d, n ~/ 2 + d), (yazi, n)],
            '${v == 0 ? '' : '$ek '}Deneysel olasılık $tura/$n, teorik '
            'olasılık 1/2 = ${n ~/ 2}/$n olur. Fark ${_sade(d, n)} bulunur.',
          );
        default:
          return _olasilik(
            '$giris Bu deneye göre tura gelmesinin deneysel olasılığı ile '
            'yazı gelmesinin deneysel olasılığı arasındaki fark kaçtır?',
            2 * d,
            n,
            [(d, n), (tura, n), (2 * d, tura), (yazi, n)],
            '$ek Deneysel olasılıklar $tura/$n ve $yazi/$n olduğundan fark '
            '${_sade(tura - yazi, n)} bulunur.',
          );
      }
  }
}

// ---------------------------------------------------------------------------
// 17. Basit faiz
// ---------------------------------------------------------------------------

AdvancedItem _basitFaiz(int a, int b, int c) {
  final v = c ~/ 5;
  final oran = 8 + 2 * (b % 5) + v; // %8 … %17
  final yil = 2 + b ~/ 5; // 2 … 5 yıl
  switch (c % 5) {
    case 0:
      final ana = 3000 + 500 * a, faiz = ana * oran * yil ~/ 100;
      return sayisal(
        'Bir bankaya yıllık %$oran basit faizle yatırılan $ana TL, $yil yıl '
        'sonunda kaç TL faiz getirir?',
        faiz,
        [ana * oran ~/ 100, ana + faiz, faiz ~/ 10, ana * (oran + yil) ~/ 100],
        'Basit faiz = ana para·oran·süre : 100 = $ana·$oran·$yil : 100 = '
        '$faiz TL.',
        unit: 'TL',
        positive: true,
      );
    case 1:
      final ana = 3000 + 500 * a, faiz = ana * oran * yil ~/ 100;
      return sayisal(
        'Yıllık %$oran basit faizle bankaya yatırılan bir miktar para $yil '
        'yılda $faiz TL faiz getirmiştir. Bankaya yatırılan para kaç '
        'TL\'dir?',
        ana,
        [faiz * 100 ~/ oran, ana + faiz, faiz * oran * yil ~/ 100, ana - faiz],
        'Ana para = faiz·100 : (oran·süre) = $faiz·100 : ($oran·$yil) = '
        '$ana TL.',
        unit: 'TL',
        positive: true,
      );
    case 2:
      final ana = 3000 + 500 * a, faiz = ana * oran * yil ~/ 100;
      return _yuzdeli(
        'Bankaya basit faizle yatırılan $ana TL, $yil yılda $faiz TL faiz '
        'getirmiştir. Buna göre yıllık faiz oranı yüzde kaçtır?',
        oran,
        [oran * yil, oran + yil, oran - 2, oran + 1, oran + 3],
        'Oran = faiz·100 : (ana para·süre) = $faiz·100 : ($ana·$yil) = '
        '$oran; yıllık faiz oranı %$oran olur.',
      );
    case 3:
      final ana = 3000 + 500 * a, faiz = ana * oran * yil ~/ 100;
      return sayisal(
        'Yıllık %$oran basit faizle bankaya yatırılan $ana TL kaç yılda '
        '$faiz TL faiz getirir?',
        yil,
        [yil + 1, yil - 1, 2 * yil, yil + 2],
        'Süre = faiz·100 : (ana para·oran) = $faiz·100 : ($ana·$oran) = '
        '$yil yıl.',
        unit: 'yıl',
        positive: true,
      );
    default:
      final ana = 1200 * (2 + a), ay = 3 * yil; // 6, 9, 12 ya da 15 ay
      final faiz = (2 + a) * oran * ay;
      return sayisal(
        'Yıllık %$oran basit faizle bankaya yatırılan $ana TL, $ay ay '
        'sonunda kaç TL faiz getirir?',
        faiz,
        [ana * oran * ay ~/ 100, ana * oran ~/ 100, faiz + ana, faiz ~/ 2],
        'Süre ay olarak verildiğinde faiz = ana para·oran·ay : 1200 '
        'bağıntısı kullanılır: $ana·$oran·$ay : 1200 = $faiz TL.',
        unit: 'TL',
        positive: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 18. Bileşik faiz
// ---------------------------------------------------------------------------

AdvancedItem _bilesikFaiz(int a, int b, int c) {
  final ana = 8000 * (1 + a); // 8000 … 200000 TL
  final j = 1 + b % 10; // oran = %5·j
  final oran = 5 * j;
  final yil = 2 + b ~/ 10; // 2 ya da 3 yıl
  final fon = c >= 5;
  final kazanc = fon ? 'getiri' : 'faiz';
  final fiil = fon ? 'sağlar' : 'getirir';
  // Yıl sonu tutarları: her yıl (20 + j)/20 ile çarpılır.
  final tutar = [ana];
  for (var y = 0; y < yil; y++) {
    tutar.add(tutar.last * (20 + j) ~/ 20);
  }
  final son = tutar.last;
  final basit = ana * oran * yil ~/ 100;
  final carpan = tr(1 + oran / 100);
  final adimlar = [
    for (var y = 1; y <= yil; y++) '$y. yıl sonunda ${tutar[y]} TL',
  ].join(', ');
  final giris = fon
      ? 'Yıllık %$oran bileşik getiri sağlayan bir yatırım fonuna yatırılan '
            '$ana TL'
      : 'Bir bankaya yıllık %$oran bileşik faizle yatırılan $ana TL';
  final geri = [
    for (var y = yil; y >= 1; y--) '${tutar[y]} : $carpan = ${tutar[y - 1]}',
  ].join(', ');
  final ortak = 'Para her yıl $carpan ile çarpılır: $adimlar olur.';
  switch (c % 5) {
    case 0:
      return sayisal(
        '$giris, $yil yıl sonunda toplam kaç TL olur?',
        son,
        [
          ana + basit,
          son - ana,
          tutar[yil - 1],
          ana + basit + ana * oran ~/ 100,
        ],
        '$ortak Toplam para $son TL bulunur.',
        unit: 'TL',
        positive: true,
      );
    case 1:
      return sayisal(
        '$giris, $yil yıl sonunda toplam kaç TL $kazanc $fiil?',
        son - ana,
        [basit, son, tutar[yil - 1] - ana, son - ana + ana * oran ~/ 100],
        '$ortak Toplam $kazanc $son − $ana = ${son - ana} TL bulunur.',
        unit: 'TL',
        positive: true,
      );
    case 2:
      return sayisal(
        '$giris için $yil yıl sonunda elde edilen bileşik $kazanc, aynı '
        'oranla basit $kazanc hesaplansaydı elde edilecek tutardan kaç TL '
        'fazla olur?',
        son - ana - basit,
        [son - ana, basit, ana * oran ~/ 100, (son - ana - basit) * 2],
        '$ortak Bileşik $kazanc $son − $ana = ${son - ana} TL, basit $kazanc '
        '$ana·$oran·$yil : 100 = $basit TL olur. Fark '
        '${son - ana} − $basit = ${son - ana - basit} TL bulunur.',
        unit: 'TL',
        positive: true,
      );
    case 3:
      final sonYil = son - tutar[yil - 1];
      return sayisal(
        '$giris, yalnızca $yil. yıl içinde kaç TL $kazanc $fiil?',
        sonYil,
        [
          ana * oran ~/ 100,
          son - ana,
          basit,
          tutar[yil - 1] * oran ~/ 100 + ana * oran ~/ 100,
        ],
        '$ortak $yil. yılın $kazanc tutarı $son − ${tutar[yil - 1]} = '
        '$sonYil TL bulunur.',
        unit: 'TL',
        positive: true,
      );
    default:
      return sayisal(
        fon
            ? 'Yıllık %$oran bileşik getiri sağlayan bir yatırım fonuna '
                  'yatırılan bir miktar para $yil yıl sonunda $son TL '
                  'olmuştur. Başlangıçta fona yatırılan para kaç '
                  'TL\'dir?'
            : 'Bir bankaya yıllık %$oran bileşik faizle yatırılan bir miktar '
                  'para $yil yıl sonunda $son TL olmuştur. Başlangıçta '
                  'bankaya yatırılan para kaç TL\'dir?',
        ana,
        [
          son * 100 ~/ (100 + oran * yil),
          son - basit,
          tutar[1],
          son * (100 - oran) ~/ 100,
        ],
        'Para her yıl $carpan ile çarpıldığından geriye doğru $carpan ile '
        'bölünür: $geri. Başlangıçtaki para $ana TL bulunur.',
        unit: 'TL',
        positive: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 19. KDV, indirim ve taksit hesapları
// ---------------------------------------------------------------------------

const _kdvOranlari = [1, 8, 10, 20];

AdvancedItem _indirimKdv(int a, int b, int c) {
  final v = c ~/ 5;
  switch (c % 5) {
    case 0:
      final fiyat = 2000 * (1 + a);
      final x = 5 * (1 + b % 5), k = _kdvOranlari[b ~/ 5];
      final indirimli = fiyat * (100 - x) ~/ 100;
      final kdv = indirimli * k ~/ 100;
      final giris =
          'KDV hariç fiyatı $fiyat TL olan bir ürüne önce %$x indirim '
          'uygulanıyor, ardından indirimli fiyata %$k KDV ekleniyor.';
      final ortak =
          'İndirimli fiyat $fiyat·${100 - x} : 100 = $indirimli TL, KDV '
          'tutarı $indirimli·$k : 100 = $kdv TL olur.';
      if (v == 0) {
        return sayisal(
          '$giris Bu ürün için ödenecek toplam tutar kaç TL olur?',
          indirimli + kdv,
          [
            fiyat * (100 - x + k) ~/ 100,
            indirimli,
            fiyat + fiyat * k ~/ 100,
            indirimli + fiyat * k ~/ 100,
          ],
          '$ortak Ödenecek tutar $indirimli + $kdv = ${indirimli + kdv} TL '
          'bulunur.',
          unit: 'TL',
          positive: true,
        );
      }
      return sayisal(
        '$giris Bu üründen alınan KDV tutarı kaç TL olur?',
        kdv,
        [fiyat * k ~/ 100, indirimli + kdv, fiyat * x ~/ 100, kdv + k],
        ortak,
        unit: 'TL',
        positive: true,
      );
    case 1:
      final haric = 500 + 100 * a + 2500 * (b ~/ 4);
      final k = _kdvOranlari[b % 4];
      final dahil = haric * (100 + k) ~/ 100;
      final giris =
          'KDV oranının %$k olduğu bir üründe KDV dâhil satış fiyatı $dahil '
          'TL olarak belirlenmiştir.';
      final ortak =
          'KDV hariç fiyat x ise x·${100 + k} : 100 = $dahil olur; buradan '
          'x = $dahil·100 : ${100 + k} = $haric TL bulunur.';
      if (v == 0) {
        return sayisal(
          '$giris Bu ürünün KDV hariç fiyatı kaç TL\'dir?',
          haric,
          [dahil * (100 - k) ~/ 100, dahil - k, dahil - haric, haric + 100],
          ortak,
          unit: 'TL',
          positive: true,
        );
      }
      return sayisal(
        '$giris Bu ürünün fiyatının içindeki KDV tutarı kaç '
        'TL\'dir?',
        dahil - haric,
        [dahil * k ~/ 100, haric, k * 10, (dahil - haric) * 2],
        '$ortak KDV tutarı $dahil − $haric = ${dahil - haric} TL olur.',
        unit: 'TL',
        positive: true,
      );
    case 2:
      final fiyat = 400 * (2 + a);
      final x = 10 + 5 * (b % 5), y = 5 + 5 * (b ~/ 5);
      final ara = fiyat * (100 - x) ~/ 100;
      final son = ara * (100 - y) ~/ 100;
      final giris =
          'Etiket fiyatı $fiyat TL olan bir ceket önce %$x, ardından '
          'indirimli fiyat üzerinden %$y indirimle satılıyor.';
      final ortak =
          'İlk indirimden sonra fiyat $fiyat·${100 - x} : 100 = $ara TL, '
          'ikinci indirimden sonra $ara·${100 - y} : 100 = $son TL olur.';
      if (v == 0) {
        return sayisal(
          '$giris Ceketin son satış fiyatı kaç TL olur?',
          son,
          [
            fiyat * (100 - x - y) ~/ 100,
            ara,
            fiyat - son,
            fiyat * (100 - y) ~/ 100,
          ],
          ortak,
          unit: 'TL',
          positive: true,
        );
      }
      return sayisal(
        '$giris Bu iki indirim sonunda etiket fiyatından toplam kaç TL '
        'düşülmüş olur?',
        fiyat - son,
        [fiyat * (x + y) ~/ 100, son, fiyat - ara, ara - son],
        '$ortak Toplam indirim $fiyat − $son = ${fiyat - son} TL bulunur.',
        unit: 'TL',
        positive: true,
      );
    case 3:
      final taksit = const [3, 4, 6, 8, 10][b % 5];
      final vade = const [5, 10, 15, 20][b ~/ 5];
      final q = 2 + a;
      final pesin = 100 * taksit * q;
      final toplam = pesin * (100 + vade) ~/ 100;
      final giris =
          'Peşin fiyatı $pesin TL olan bir ürün, peşin fiyatına %$vade vade '
          'farkı eklenerek $taksit eşit taksitle satılıyor.';
      if (v == 0) {
        return sayisal(
          '$giris Buna göre her bir taksit kaç TL olur?',
          toplam ~/ taksit,
          [
            pesin ~/ taksit,
            toplam,
            pesin * vade ~/ 100,
            pesin ~/ taksit + vade,
          ],
          'Taksitli fiyat $pesin·${100 + vade} : 100 = $toplam TL olur. Her '
          'taksit $toplam : $taksit = ${toplam ~/ taksit} TL bulunur.',
          unit: 'TL',
          positive: true,
        );
      }
      return sayisal(
        '$giris Ürünü taksitle alan biri, peşin alan birine göre toplam kaç '
        'TL fazla öder?',
        toplam - pesin,
        [
          (toplam - pesin) ~/ taksit,
          toplam ~/ taksit,
          toplam,
          pesin * vade ~/ 100 * taksit,
        ],
        'Vade farkı peşin fiyatın %$vade kadarıdır: $pesin·$vade : 100 = '
        '${toplam - pesin} TL.',
        unit: 'TL',
        positive: true,
      );
    default:
      final etiket = 100 * (3 + a), x = 5 + 2 * b; // %5 … %43
      final satis = (3 + a) * (100 - x);
      if (v == 0) {
        return _yuzdeli(
          'Etiket fiyatı $etiket TL olan bir ayakkabı indirim döneminde '
          '$satis TL fiyatla satılıyor. Uygulanan indirim oranı yüzde '
          'kaçtır?',
          x,
          [100 - x, (etiket - satis) * 100 ~/ satis, x + 2, x - 2, x + 4],
          'İndirim tutarı $etiket − $satis = ${etiket - satis} TL olur. '
          'Oran ${etiket - satis}·100 : $etiket = $x; indirim %$x bulunur.',
        );
      }
      return sayisal(
        'Bir ayakkabı, etiket fiyatı üzerinden %$x indirim yapılarak $satis '
        'TL fiyatla satılıyor. Ayakkabının etiket fiyatı kaç '
        'TL\'dir?',
        etiket,
        [
          satis * (100 + x) ~/ 100,
          satis + x,
          satis * 100 ~/ (100 + x),
          etiket + 100,
        ],
        'Satış fiyatı etiket fiyatının %${100 - x} kadarıdır: etiket fiyatı '
        '$satis·100 : ${100 - x} = $etiket TL bulunur.',
        unit: 'TL',
        positive: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 20. Döviz çevirme ve birim fiyat karşılaştırması
// ---------------------------------------------------------------------------

const _paketler = [(250, 400), (200, 500), (400, 750), (300, 500), (150, 250)];
const _paketUrunleri = ['kahve', 'çay', 'fındık', 'badem', 'zeytin'];
const _caprazOranlar = [(6, 5), (5, 4), (7, 6), (9, 8)];

AdvancedItem _kurBirim(int a, int b, int c) {
  final v = c ~/ 5;
  switch (c % 5) {
    case 0:
      final para = v == 0 ? 'dolar' : 'avro';
      final kur = (v == 0 ? 28 : 34) + b, miktar = 50 + 10 * a;
      return sayisal(
        'Bir döviz bürosunda 1 $para $kur TL olarak işlem görmektedir. Bu '
        'büroda $miktar $para bozduran biri kaç TL alır?',
        miktar * kur,
        [
          miktar * kur ~/ 10,
          miktar + kur,
          miktar * (kur + 1),
          miktar * kur + miktar,
        ],
        'Her $para $kur TL ettiğinden $miktar·$kur = ${miktar * kur} TL '
        'alınır.',
        unit: 'TL',
        positive: true,
      );
    case 1:
      final para = v == 0 ? 'dolar' : 'avro';
      final kur = (v == 0 ? 28 : 34) + b, miktar = 40 + 5 * a;
      final tl = miktar * kur;
      return sayisal(
        'Bir döviz bürosunda 1 $para $kur TL olarak işlem görmektedir. Bu '
        'büroda $tl TL ile kaç $para alınabilir?',
        miktar,
        [miktar + kur, tl ~/ 100, miktar * 2, miktar + 5, miktar - 5],
        'Eldeki tutar kura bölünür: $tl : $kur = $miktar $para.',
        positive: true,
      );
    case 2:
      final w = const [6, 7, 5, 4][b ~/ 5] + b % 5;
      final (r1, r2) = _caprazOranlar[b ~/ 5];
      final avroKuru = r1 * w, dolarKuru = r2 * w;
      final m = 10 + 2 * a;
      final giris =
          'Bir döviz bürosunda 1 avro $avroKuru TL, 1 dolar $dolarKuru TL '
          'olarak işlem görmektedir.';
      if (v == 0) {
        final avro = r2 * m, dolar = r1 * m;
        return sayisal(
          '$giris Buna göre $avro avro kaç dolar eder?',
          dolar,
          [avro * r2 ~/ r1, avro + (avroKuru - dolarKuru), avro, dolar + m],
          '$avro avro $avro·$avroKuru = ${avro * avroKuru} TL eder. Bu tutar '
          '${avro * avroKuru} : $dolarKuru = $dolar dolar olur.',
          positive: true,
        );
      }
      final dolar = r1 * m, avro = r2 * m;
      return sayisal(
        '$giris Buna göre $dolar dolar kaç avro eder?',
        avro,
        [dolar * r1 ~/ r2, dolar - (avroKuru - dolarKuru), dolar, avro - m],
        '$dolar dolar $dolar·$dolarKuru = ${dolar * dolarKuru} TL eder. Bu '
        'tutar ${dolar * dolarKuru} : $avroKuru = $avro avro olur.',
        positive: true,
      );
    case 3:
      final u1 = 100 + 20 * a, fark = 20 * (1 + b ~/ 5);
      final u2 = a.isEven ? u1 + fark : u1 - fark;
      final (m1, m2) = _paketler[b % 5];
      final p1 = u1 * m1 ~/ 1000, p2 = u2 * m2 ~/ 1000;
      final urun = _paketUrunleri[(a + b) % 5];
      final giris =
          'Bir markette A marka $urun $m1 gramlık pakette $p1 TL, B marka '
          '$urun $m2 gramlık pakette $p2 TL fiyatla satılmaktadır.';
      final ortak =
          'Kilogram fiyatları A için $p1·1000 : $m1 = $u1 TL, B için '
          '$p2·1000 : $m2 = $u2 TL olur.';
      final dusuk = u1 < u2 ? u1 : u2;
      if (v == 0) {
        return sayisal(
          '$giris Bu iki markanın kilogram fiyatları arasındaki fark kaç '
          'TL\'dir?',
          fark,
          [(p1 - p2).abs(), dusuk, (m1 - m2).abs() ~/ 10, fark * 2, fark ~/ 2],
          '$ortak Fark ${u1 > u2 ? '$u1 − $u2' : '$u2 − $u1'} = $fark TL '
          'bulunur.',
          unit: 'TL',
          positive: true,
        );
      }
      return sayisal(
        '$giris Kilogram fiyatı daha düşük olan markanın kilogram fiyatı kaç '
        'TL\'dir?',
        dusuk,
        [
          u1 < u2 ? u2 : u1,
          p1 < p2 ? p1 * 2 : p2 * 2,
          dusuk + 20,
          dusuk - 20,
          fark,
        ],
        '$ortak Daha düşük olan ${u1 < u2 ? 'A' : 'B'} markasının kilogram '
        'fiyatı $dusuk TL bulunur.',
        unit: 'TL',
        positive: true,
      );
    default:
      final birim = v == 0 ? 200 + 10 * a : 80 + 5 * a;
      final x = 2 + b % 4, y = x + 1 + b ~/ 4;
      final tutar = birim * x;
      return sayisal(
        v == 0
            ? 'Bir markette $x litre zeytinyağı $tutar TL fiyatla '
                  'satılmaktadır. Aynı birim fiyatla $y litre zeytinyağı kaç '
                  'TL olur?'
            : 'Bir mağazada $x metre kumaş $tutar TL fiyatla satılmaktadır. '
                  'Aynı birim fiyatla $y metre kumaş kaç TL olur?',
        birim * y,
        [
          tutar + (y - x) * 10,
          tutar * y,
          birim,
          tutar + birim,
          birim * (y - x),
        ],
        'Birim fiyat $tutar : $x = $birim TL olur. $y birim için '
        '$birim·$y = ${birim * y} TL ödenir.',
        unit: 'TL',
        positive: true,
      );
  }
}

// ---------------------------------------------------------------------------
// Aile listesi
// ---------------------------------------------------------------------------

final lmVeriOlasilik = <AdvancedFamily>[
  lmAile(
    'vo_permutasyon',
    'Permütasyon ve koşullu sıralama',
    Topic.mathematics,
    Difficulty.medium,
    BloomLevel.uygulama,
    _permutasyon,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_tekrarli_permutasyon',
    'Tekrarlı permütasyon ve dairesel sıralama',
    Topic.mathematics,
    Difficulty.hard,
    BloomLevel.analiz,
    _tekrarliPermutasyon,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_kombinasyon',
    'Kombinasyon ve koşullu seçim',
    Topic.mathematics,
    Difficulty.medium,
    BloomLevel.uygulama,
    _kombinasyon,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_binom',
    'Binom açılımında katsayılar ve terimler',
    Topic.mathematics,
    Difficulty.medium,
    BloomLevel.uygulama,
    _binom,
    exam: ExamKind.ayt,
    lesson: 'Matematik',
  ),
  lmAile(
    'vo_olasilik_zar',
    'Zar ve madenî para deneylerinde olasılık',
    Topic.statistics,
    Difficulty.medium,
    BloomLevel.analiz,
    _zarPara,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_olasilik_torba',
    'Torbadan çekilişlerde olasılık',
    Topic.statistics,
    Difficulty.medium,
    BloomLevel.uygulama,
    _torba,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_kosullu',
    'Bağımsız olaylar ve koşullu olasılık',
    Topic.statistics,
    Difficulty.hard,
    BloomLevel.analiz,
    _kosullu,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_ortalama',
    'Aritmetik ortalamada eklenen ve çıkan veri',
    Topic.statistics,
    Difficulty.medium,
    BloomLevel.uygulama,
    _ortalama,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_medyan_mod',
    'Medyan, mod ve açıklık',
    Topic.statistics,
    Difficulty.easy,
    BloomLevel.anlama,
    _medyanMod,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_standart_sapma',
    'Varyans ve standart sapma',
    Topic.statistics,
    Difficulty.medium,
    BloomLevel.uygulama,
    _standartSapma,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_agirlikli',
    'Ağırlıklı ortalama',
    Topic.statistics,
    Difficulty.medium,
    BloomLevel.uygulama,
    _agirlikli,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_kume',
    'Kümelerde eleman ve alt küme sayısı',
    Topic.mathematics,
    Difficulty.easy,
    BloomLevel.uygulama,
    _kume,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_onerme',
    'Bileşik önermelerin doğruluk değeri',
    Topic.mathematics,
    Difficulty.medium,
    BloomLevel.uygulama,
    _onerme,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
    shortAnswer: false,
  ),
  lmAile(
    'vo_moduler',
    'Modüler aritmetikte kalan, gün ve saat',
    Topic.mathematics,
    Difficulty.medium,
    BloomLevel.uygulama,
    _moduler,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_sayma',
    'Toplama ve çarpma yoluyla sayma',
    Topic.mathematics,
    Difficulty.medium,
    BloomLevel.uygulama,
    _sayma,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_deneysel',
    'Deneysel olasılık ve göreli sıklık',
    Topic.statistics,
    Difficulty.easy,
    BloomLevel.anlama,
    _deneysel,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_basit_faiz',
    'Basit faiz hesapları',
    Topic.economics,
    Difficulty.easy,
    BloomLevel.uygulama,
    _basitFaiz,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_bilesik_faiz',
    'Yıllık bileşik faiz',
    Topic.economics,
    Difficulty.hard,
    BloomLevel.analiz,
    _bilesikFaiz,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_indirim_kdv',
    'KDV, indirim ve taksit hesapları',
    Topic.economics,
    Difficulty.medium,
    BloomLevel.uygulama,
    _indirimKdv,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
  lmAile(
    'vo_kur_birim',
    'Döviz çevirme ve birim fiyat karşılaştırması',
    Topic.economics,
    Difficulty.easy,
    BloomLevel.uygulama,
    _kurBirim,
    exam: ExamKind.tyt,
    lesson: 'Temel Matematik',
  ),
];
