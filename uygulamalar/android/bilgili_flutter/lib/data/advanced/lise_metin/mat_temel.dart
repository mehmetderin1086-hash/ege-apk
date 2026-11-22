// TYT temel matematik: sayılar, cebir ve sözel problemlerden oluşan 20 metin
// ailesi. Her aile (a, b, c) koordinatlarından 5.000 ayrı soru üretir;
// çeldiriciler tipik öğrenci hatalarından hesaplanır.
import 'denge.dart';
import 'ortak.dart';

AdvancedFamily _mt(
  String key,
  String title,
  Difficulty difficulty,
  BloomLevel bloom,
  LmUretec build, {
  bool shortAnswer = true,
}) => lmAile(
  'mt_$key',
  title,
  Topic.mathematics,
  difficulty,
  bloom,
  build,
  exam: ExamKind.tyt,
  lesson: 'Temel Matematik',
  shortAnswer: shortAnswer,
);

/// Yanıtı tek rakam olan soru: çeldiriciler 0–9 aralığında kalır.
AdvancedItem _rakam(
  String kok,
  int yanit,
  Iterable<int> adaylar,
  String aciklama,
) => secenekli(
  kok,
  '$yanit',
  [
    ...adaylar,
    for (final k in const [1, 9, 2, 8, 3, 7, 5]) (yanit + k) % 10,
  ].where((x) => x >= 0 && x <= 9).map((x) => '$x'),
  aciklama,
);

// ---------------------------------------------------------------------------
// 1. Basamak değeri ve çözümleme
// ---------------------------------------------------------------------------
AdvancedItem _basamak(int a, int b, int c) {
  final k = a + 3; // çarpan: 3 … 27
  final kucuk = 1 + b % 4, fark = 1 + b ~/ 4; // rakam farkı 1 … 5
  final buyuk = kucuk + fark; // 2 … 9
  final fazla = (a + b + c).isEven; // hatalı sonuç fazla mı çıktı
  final x = fazla ? kucuk : buyuk, z = fazla ? buyuk : kucuk;
  final y = c;
  final n = 100 * x + 10 * y + z, ters = 100 * z + 10 * y + x;
  final d = 99 * fark * k, s = x + y + z;
  final yon = fazla ? 'fazla' : 'eksik';
  return sayisal(
    'Bir öğrenci, üç basamaklı bir doğal sayıyı $k ile çarparken sayının '
        'yüzler ve birler basamağındaki rakamların yerini yanlışlıkla değiştirmiş '
        've sonucu olması gerekenden $d $yon bulmuştur. Çarpılması gereken sayının '
        'onlar basamağındaki rakam $y, rakamları toplamı $s olduğuna göre bu sayı '
        'kaçtır?',
    n,
    [
      ters,
      100 * x + 10 * z + y,
      if (y > 0) 100 * y + 10 * x + z,
      if (x < 9 && z > 0) n + 99,
      if (x > 1 && z < 9) n - 99,
    ],
    'Yüzler ve birler basamağındaki rakamlar yer değiştirince sayı, bu iki '
        'rakamın farkının 99 katı kadar değişir. $k · 99 · fark = $d eşitliğinden '
        'fark $fark bulunur. Bu iki rakamın toplamı $s − $y = ${s - y} olduğundan '
        'rakamlar $buyuk ve $kucuk olur. Sonuç $yon çıktığı için yüzler '
        'basamağındaki rakam $x olur; sayı $n bulunur.',
    positive: true,
  );
}

// ---------------------------------------------------------------------------
// 2. Bölünebilme kuralları
// ---------------------------------------------------------------------------
AdvancedItem _bolunebilme(int a, int b, int c) {
  final tur = c % 4, u = c ~/ 4;
  final k1 = 1 + a % 5 + 2 * u, k2 = 2 * (a ~/ 5), k3 = 3 + b % 5;
  String yaz(List<int> bilinen, int yer) {
    final r = [for (final x in bilinen) '$x']..insert(yer, 'A');
    return r.join();
  }

  List<int> uyanlar(bool Function(int) uygun) => [
    for (var x = 0; x <= 9; x++)
      if (uygun(x)) x,
  ];
  if (tur == 0 || tur == 1) {
    final k4 = 3 * (b ~/ 5);
    final sayi = yaz([k1, k2, k3, k4], u + 1);
    final s = k1 + k2 + k3 + k4;
    if (tur == 0) {
      final v = uyanlar((x) => (s + x) % 3 == 0);
      final t = v.fold<int>(0, (p, q) => p + q);
      return sayisal(
        'Beş basamaklı $sayi sayısı 3 ile tam bölünebildiğine göre A rakamının '
            'alabileceği değerlerin toplamı kaçtır?',
        t,
        [12, 15, 18, v.first, v.length, 9],
        'Bilinen rakamların toplamı $s olduğundan $s + A toplamı 3 sayısının '
            'katı olmalıdır. A yerine ${v.join(', ')} yazılabilir; bu değerlerin '
            'toplamı $t olur.',
        positive: true,
      );
    }
    final r = (9 - s % 9) % 9;
    if (r == 0) {
      return sayisal(
        'Beş basamaklı $sayi sayısı 9 ile tam bölünebildiğine göre A rakamının '
            'alabileceği değerlerin toplamı kaçtır?',
        9,
        [0, 18, 12, 6],
        'Bilinen rakamların toplamı $s zaten 9 sayısının katıdır. Bu nedenle A '
            'yerine 0 ya da 9 yazılabilir; bu değerlerin toplamı 9 olur.',
      );
    }
    return _rakam(
      'Beş basamaklı $sayi sayısı 9 ile tam bölünebildiğine göre A rakamı '
          'kaçtır?',
      r,
      [s % 9, (3 - s % 3) % 3, r + 3, r - 3],
      'Bilinen rakamların toplamı $s olduğundan $s + A toplamı 9 sayısının katı '
          'olmalıdır. $s + $r = ${s + r} olduğu için A = $r bulunur.',
    );
  }
  if (tur == 2) {
    final cift = 2 * (b ~/ 5);
    final sayi = u == 0
        ? yaz([k1, k2, cift, k3], 4)
        : yaz([k1, k2, k3, cift], 3);
    final v = uyanlar((x) => (u == 0 ? 10 * k3 + x : 10 * x + cift) % 4 == 0);
    final t = v.fold<int>(0, (p, q) => p + q);
    final son = u == 0 ? '${k3}A' : 'A$cift';
    return sayisal(
      'Beş basamaklı $sayi sayısı 4 ile tam bölünebildiğine göre A rakamının '
          'alabileceği değerlerin toplamı kaçtır?',
      t,
      [8, 12, 20, 25, v.length, 10, 16],
      'Bir sayının 4 ile bölünebilmesi için son iki basamağının oluşturduğu '
          'sayı 4 sayısının katı olmalıdır. Son iki basamak $son biçimindedir; A '
          'yerine ${v.join(', ')} yazılabilir ve bu değerlerin toplamı $t olur.',
      positive: true,
    );
  }
  // 11 ile bölünebilme: A üçüncü ya da dördüncü basamaktadır.
  final yer = u == 0 ? 2 : 3;
  final isaret = yer.isEven ? 1 : -1;
  var k4 = 3 * (b ~/ 5);
  int fark(int son) {
    final bilinen = [k1, k2, k3, son]..insert(yer, 0);
    var t = 0;
    for (var j = 0; j < 5; j++) {
      t += j.isEven ? bilinen[j] : -bilinen[j];
    }
    return t;
  }

  int coz(int son) => ((-isaret * fark(son)) % 11 + 11) % 11;
  if (coz(k4) == 10) k4 = k4 == 9 ? 8 : k4 + 1;
  final r = coz(k4);
  final sayi = yaz([k1, k2, k3, k4], yer);
  final hane = [
    for (final x in [k1, k2, k3, k4]) '$x',
  ]..insert(yer, 'A');
  final tek = '${hane[0]} + ${hane[2]} + ${hane[4]}';
  final cft = '${hane[1]} + ${hane[3]}';
  final s = k1 + k2 + k3 + k4;
  return _rakam(
    'Beş basamaklı $sayi sayısı 11 ile tam bölünebildiğine göre A rakamı '
        'kaçtır?',
    r,
    [(9 - s % 9) % 9, (isaret * fark(k4) % 11 + 11) % 11, 9 - r],
    'Birler basamağından başlayıp birer atlayarak alınan rakamların toplamı '
        '($tek) ile kalan rakamların toplamı ($cft) arasındaki fark 0 ya da 11 '
        'sayısının katı olmalıdır. Bu koşulu sağlayan tek rakam A = $r olur.',
  );
}

// ---------------------------------------------------------------------------
// 3. EBOB ve EKOK
// ---------------------------------------------------------------------------
const _asalCift = [
  (2, 3), (2, 5), (3, 4), (2, 7), (3, 5), (2, 9), (4, 5), (3, 7), (2, 11),
  (3, 8), (4, 7), (3, 10), (5, 6), (3, 11), (5, 7), (4, 9), (5, 8), (6, 7),
  (4, 11), (5, 9), (7, 8), (5, 11), (7, 9), (7, 10), (8, 9), //
];

AdvancedItem _ebobEkok(int a, int b, int c) {
  final (m, n) = _asalCift[a];
  final k = c ~/ 3, sira = _sira(a, b, c);
  if (c % 3 == 0) {
    final g = b + 2, x = g * m, y = g * n, l = g * m * n;
    final ayir =
        '$x = $g · $m ve $y = $g · $n olup $m ile $n aralarında asaldır; '
        'EBOB = $g, EKOK = $g · $m · $n = $l olur.';
    if (k == 0) {
      return _tamSirali(
        '$x ile $y sayılarının en büyük ortak böleni (EBOB) ile en küçük ortak '
            'katının (EKOK) toplamı kaçtır?',
        g + l,
        [
          l, // EBOB eklenmemiş
          l - g,
          x + y,
          g + m * n,
          g + x * y, // EKOK yerine sayıların çarpımı
          x + l, // EBOB yerine küçük sayı
          y + l, // EBOB yerine büyük sayı
        ],
        '$ayir Toplam $g + $l = ${g + l} bulunur.',
        sira,
        enAz: 1,
      );
    }
    if (k == 1) {
      return _tamSirali(
        'EKOK($x, $y) değerinin EBOB($x, $y) değerine bölümü kaçtır?',
        m * n,
        [
          m + n,
          g,
          l, // EKOK yanıt sanılmış
          l - g, // bölme yerine çıkarma
          n, // ara sonuç: büyük sayının EBOB'a bölümü
          l + g, // bölme yerine toplama
          m, // ara sonuç: küçük sayının EBOB'a bölümü
        ],
        '$ayir Bölüm $l / $g = ${m * n} bulunur.',
        sira,
        enAz: 1,
      );
    }
    final verilen = k == 2 ? x : y, diger = k == 2 ? y : x;
    return _tamSirali(
      'İki doğal sayının en büyük ortak böleni $g, en küçük ortak katı $l '
          'olarak veriliyor. Bu sayılardan biri $verilen olduğuna göre diğeri '
          'kaçtır?',
      diger,
      [
        l ~/ verilen, // çarpım EKOK sanılmış
        l - verilen,
        l ~/ g,
        verilen + g,
        g + l - verilen, // toplamlar eşit sanılmış
        l, // EKOK yanıt sanılmış
        g, // EBOB yanıt sanılmış
      ],
      'İki sayının çarpımı, EBOB ile EKOK değerlerinin çarpımına eşittir: '
          '$verilen · x = $g · $l = ${g * l}. Buradan x = ${g * l} / $verilen = '
          '$diger bulunur.',
      sira,
      enAz: 1,
    );
  }
  final s = b ~/ 5;
  if (c % 3 == 1) {
    if (k == 0) {
      final g = 2 + b % 5, x = g * m, y = g * n, l = g * m * n;
      final t = (s + 2) * l + x;
      return _tamSirali(
        'Bir limandaki iki fenerden biri $x saniyede bir, diğeri $y saniyede '
            'bir yanmaktadır. İki fener aynı anda yandıktan sonraki $t saniye '
            'içinde kaç kez daha aynı anda yanar?',
        s + 2,
        [
          s + 3, // ilk yanış da sayılmış
          s + 1,
          t ~/ y, // yalnız bir fenerin yanışları
          t ~/ x,
          t ~/ (x * y), // EKOK yerine çarpım
          t ~/ g, // EKOK yerine EBOB
        ],
        'Fenerler EKOK($x, $y) = $l saniyede bir aynı anda yanar. $t saniyenin '
            'içinde $l sayısının ${s + 2} tam katı bulunduğundan ${s + 2} kez daha '
            'aynı anda yanarlar.',
        sira,
        enAz: 1,
      );
    }
    if (k == 1) {
      final g = 3 + b % 5, x = g * m, y = g * n, l = g * m * n, r = s + 1;
      return _tamSirali(
        'Bir atölyedeki vidalar, her biri $x vida alan kutulara doldurulduğunda '
            'da her biri $y vida alan kutulara doldurulduğunda da $r vida '
            'artmaktadır. Her iki durumda da en az bir kutu dolduğuna göre '
            'atölyede en az kaç vida vardır?',
        l + r,
        [
          l, // kalan eklenmemiş
          l - r,
          x * y + r, // EKOK yerine çarpım
          x + y + r,
          l + 2 * r, // kalan iki kez eklenmiş
          g + r, // EKOK yerine EBOB
        ],
        'Vida sayısının $r eksiği hem $x hem $y ile bölünür; en küçük değer '
            'EKOK($x, $y) = $l olur. Vida sayısı en az $l + $r = ${l + r} bulunur.',
        sira,
        enAz: 1,
      );
    }
    final g = 2 + b % 5, x = g * m, y = g * n, l = g * m * n;
    final (soru, yanit) = [
      ('hızlı olan bisikletçi kaç tur atmış olur?', n),
      ('yavaş olan bisikletçi kaç tur atmış olur?', m),
      ('ikisinin attığı tur sayılarının toplamı kaç olur?', m + n),
      ('hızlı olan bisikletçi diğerinden kaç tur fazla atmış olur?', n - m),
    ][s];
    return _tamSirali(
      'Bir gölün çevresindeki parkurda aynı noktadan aynı anda ve aynı yönde '
          'yola çıkan iki bisikletçiden biri bir turu $x dakikada, diğeri $y '
          'dakikada tamamlamaktadır. İkisi başlangıç noktasında ilk kez yeniden '
          'buluştuğunda $soru',
      yanit,
      [n, m, m + n, n - m, g, m * n, l], // l: buluşma süresi (dakika)
      'İkisi başlangıç noktasında EKOK($x, $y) = $l dakika sonra buluşur. Bu '
          'sürede hızlı olan $l / $x = $n, yavaş olan $l / $y = $m tur atar; '
          'istenen değer $yanit olur.',
      sira,
      enAz: 1,
    );
  }
  final g = b + 2, x = g * m, y = g * n;
  if (k == 0) {
    return _tamSirali(
      'Uzunlukları $x cm ve $y cm olan iki tahta çıta, hiç parça artmayacak '
          'biçimde eşit uzunlukta ve olabilecek en uzun parçalara kesilecektir. '
          'Buna göre toplam kaç parça elde edilir?',
      m + n,
      [
        g, // parça uzunluğu yanıt sanılmış
        m * n, // parça sayıları çarpılmış
        m + n - 2, // kesim sayısı
        2 * (m + n),
        n, // yalnız uzun çıtanın parçaları
        x + y, // toplam uzunluk
        m, // yalnız kısa çıtanın parçaları
      ],
      'Parça uzunluğu EBOB($x, $y) = $g cm olmalıdır. Parça sayısı $x / $g + '
          '$y / $g = $m + $n = ${m + n} bulunur.',
      sira,
      enAz: 1,
    );
  }
  if (k == 1) {
    return _tamSirali(
      'Kenar uzunlukları $x m ve $y m olan dikdörtgen biçimindeki bir arsanın '
          'çevresine, köşelere de birer tane gelecek şekilde eşit aralıklarla '
          'fidan dikilecektir. Bu iş için en az kaç fidan gerekir?',
      2 * (m + n),
      [
        m + n, // yalnız iki kenar sayılmış
        2 * (m + n) + 4, // köşeler iki kez sayılmış
        2 * (m + n) - 4, // köşeler sayılmamış
        m * n,
        2 * (m + n) + 1, // kapalı çevrede bir fazla
        g, // aralık yanıt sanılmış
        2 * (x + y), // çevre uzunluğu
      ],
      'En az fidan için aralık EBOB($x, $y) = $g m seçilir. Çevre 2 · ($x + '
          '$y) = ${2 * (x + y)} m olduğundan fidan sayısı ${2 * (x + y)} / $g = '
          '${2 * (m + n)} bulunur.',
      sira,
      enAz: 1,
    );
  }
  return _tamSirali(
    'Kenar uzunlukları $x cm ve $y cm olan dikdörtgen biçimindeki bir karton, '
        'hiç parça artmayacak biçimde eş karelere ayrılacaktır. En az kaç kare '
        'elde edilir?',
    m * n,
    [
      m + n, // kenar başına kare sayıları toplanmış
      g, // kare kenarı yanıt sanılmış
      2 * (m + n),
      m * n * g, // alan kare kenarına bölünmüş
      n, // yalnız uzun kenar boyunca
      (m + 1) * (n + 1), // kareler yerine köşe noktaları
    ],
    'En az sayıda kare için kare kenarı EBOB($x, $y) = $g cm seçilir. Kare '
        'sayısı ($x / $g) · ($y / $g) = $m · $n = ${m * n} bulunur.',
    sira,
    enAz: 1,
  );
}

// ---------------------------------------------------------------------------
// 4. Bölme işlemi
// ---------------------------------------------------------------------------
AdvancedItem _bolme(int a, int b, int c) {
  final bolen = a + 6; // 6 … 30
  final kalan = 1 + c ~/ 2; // 1 … 5
  if (c.isEven) {
    final bolum = b + 3; // 3 … 22
    final bolunen = bolen * bolum + kalan, t = bolunen + bolen;
    return _tamSirali(
      'Bir bölme işleminde bölünen ile bölenin toplamı $t, bölüm $bolum ve '
          'kalan $kalan olduğuna göre bölünen kaçtır?',
      bolunen,
      [
        bolen, // bölen yanıt sanılmış
        bolen * bolum, // kalan eklenmemiş
        t - kalan, // (bölüm + 1) · x değeri yanıt sanılmış
        t - bolum, // kalan yerine bölüm çıkarılmış
        bolen * bolum - kalan, // kalan çıkarılmış
        t, // verilen toplam
      ],
      'Bölen x ise bölünen $bolum · x + $kalan olur. $bolum · x + $kalan + x = '
          '$t eşitliğinden ${bolum + 1} · x = ${t - kalan} ve x = $bolen bulunur. '
          'Bölünen $bolum · $bolen + $kalan = $bolunen olur.',
      _sira(a, b, c),
      enAz: 1,
    );
  }
  final d = 5 + b % 5, s = 1 + b ~/ 5; // ikinci bölen 5 … 9, kalan 1 … 4
  final yanit = bolen * s + kalan;
  return _tamSirali(
    'Bir A doğal sayısı $bolen ile bölündüğünde bölüm x, kalan $kalan oluyor. '
        'x sayısı $d ile bölündüğünde kalan $s olduğuna göre A sayısının '
        '${bolen * d} ile bölümünden kalan kaçtır?',
    yanit,
    [
      d * kalan + s, // bölenlerin rolü karıştırılmış
      kalan + s, // kalanlar toplanmış
      bolen * s, // ilk kalan eklenmemiş
      kalan * s, // kalanlar çarpılmış
      bolen * kalan + s, // kalanların rolü karıştırılmış
      d * s + kalan, // yanlış bölenle çarpılmış
      (bolen + kalan) * s, // ilk kalan da çarpılmış
      bolen * (s + kalan), // kalanlar toplanıp bölenle çarpılmış
    ],
    'A = $bolen · x + $kalan ve x = $d · y + $s yazılır. Yerine konursa '
        'A = ${bolen * d} · y + $bolen · $s + $kalan = ${bolen * d} · y + $yanit '
        'olur; $yanit sayısı ${bolen * d} sayısından küçük olduğundan kalan '
        '$yanit bulunur.',
    _sira(a, b, c),
    enAz: 1,
    enCok: bolen * d - 1,
  );
}

// ---------------------------------------------------------------------------
// Ortak sayı yardımcıları
// ---------------------------------------------------------------------------
String _n(int x) => x < 0 ? '−${-x}' : '$x';

/// Tam sayı yanıtlı soru; negatif değerler “−” işaretiyle yazılır.
AdvancedItem _tam(
  String kok,
  int yanit,
  Iterable<int> adaylar,
  String aciklama,
) {
  final adim = yanit.abs() >= 200 ? 10 : (yanit.abs() >= 40 ? 5 : 1);
  return secenekli(
    kok,
    _n(yanit),
    [
      ...adaylar,
      yanit + adim,
      yanit - adim,
      yanit + 2 * adim,
      yanit - 2 * adim,
      yanit + 3 * adim,
      yanit + 4 * adim,
    ].map(_n),
    aciklama,
  );
}

/// (a, b, c) vakasının sıra numarası için hedef değer sırası (0 … 3): anahtardan
/// küçük çeldirici sayısı vakadan vakaya dengeli değişir.
int _sira(int a, int b, int c, [int tuz = 0]) =>
    hedefSira(a + 25 * b + 500 * c, tuz);

/// [_tam] gibi; anahtardan küçük çeldirici sayısı [sira] olur. [adaylar] önce
/// tipik hata değerleridir; yetmezse anahtarın iki yanındaki komşu değerlerle
/// tamamlanır. [enAz] ve [enCok] verilirse bu aralığın dışındaki adaylar
/// elenir.
AdvancedItem _tamSirali(
  String kok,
  int yanit,
  Iterable<int> adaylar,
  String aciklama,
  int sira, {
  int? enAz,
  int? enCok,
}) {
  final adim = yanit.abs() >= 200 ? 10 : (yanit.abs() >= 40 ? 5 : 1);
  final hepsi = [
    ...adaylar,
    for (var k = 1; k <= 6; k++) ...[yanit + k * adim, yanit - k * adim],
  ].where((x) => (enAz == null || x >= enAz) && (enCok == null || x <= enCok));
  return AdvancedItem(
    kok,
    _n(yanit),
    siraliCeldiriciler(yanit, _n(yanit), [
      for (final x in hepsi) (x, _n(x)),
    ], sira),
    aciklama,
  );
}

/// İşaretli tam sayı yanıtı için ± tasarımı: çeldiriciler −yanıt, y ve −y
/// olur (y bir tipik hata değeridir). Her seçeneğin ters işaretlisi de
/// seçeneklerde bulunduğundan işaret, rakamlar ve uzunluk anahtarı göstermez.
/// |y|, [sira] ile |yanıt| değerinin üstünden ya da altından seçilir; o yanda
/// tipik hata yoksa komşu değer alınır. Yanıt sıfırsa [_tamSirali] kullanılır.
AdvancedItem _isaretli(
  String kok,
  int yanit,
  Iterable<int> adaylar,
  String aciklama,
  int sira,
) {
  if (yanit == 0) return _tamSirali(kok, yanit, adaylar, aciklama, sira);
  final m = yanit.abs(), buyuk = sira < 2 || m == 1;
  final tipik = [
    for (final y in adaylar)
      if (y != 0 && y.abs() != m) y.abs(),
  ];
  final y = [
    ...tipik.where((v) => buyuk ? v > m : v < m),
    buyuk ? m + 1 : m - 1,
  ].first;
  return AdvancedItem(kok, _n(yanit), [_n(-yanit), _n(y), _n(-y)], aciklama);
}

/// Sade kesir; işlemler tam sayılarla yapılır.
class _K {
  final int n, d;
  const _K._(this.n, this.d);
  factory _K(int n, [int d = 1]) {
    if (d == 0) throw StateError('Payda sıfır');
    if (d < 0) {
      n = -n;
      d = -d;
    }
    final g = n.gcd(d);
    return _K._(n ~/ g, d ~/ g);
  }
  _K operator +(_K o) => _K(n * o.d + o.n * d, d * o.d);
  _K operator -(_K o) => _K(n * o.d - o.n * d, d * o.d);
  _K operator *(_K o) => _K(n * o.n, d * o.d);
  _K operator /(_K o) => _K(n * o.d, d * o.n);
  @override
  String toString() => d == 1 ? _n(n) : '${_n(n)}/$d';
}

/// Sade kesir yanıtlı soru; anahtardan küçük çeldirici sayısı [sira] olur.
/// Tipik hatalar yetmezse anahtarın iki yanındaki yakın kesirlerle tamamlanır.
/// [pozitif] doğruysa sıfır ve negatif, [birdenKucuk] doğruysa 1 ve daha büyük
/// adaylar elenir (işin ya da havuzun kesri gibi).
AdvancedItem _kesirSirali(
  String kok,
  _K yanit,
  Iterable<_K> adaylar,
  String aciklama,
  int sira, {
  bool pozitif = false,
  bool birdenKucuk = false,
}) {
  final n = yanit.n, d = yanit.d;
  final hepsi = [
    ...adaylar,
    _K(2 * n + 1, 2 * d),
    _K(2 * n - 1, 2 * d),
    _K(n + 1, d),
    _K(n - 1, d),
    _K(n + d, d),
    _K(n - d, d),
    _K(3 * n + 1, 3 * d),
    _K(3 * n - 1, 3 * d),
  ].where((k) => (!pozitif || k.n > 0) && (!birdenKucuk || k.n < k.d));
  return AdvancedItem(
    kok,
    '$yanit',
    siraliCeldiriciler(n / d, '$yanit', [
      for (final k in hepsi) (k.n / k.d, '$k'),
    ], sira),
    aciklama,
  );
}

// ---------------------------------------------------------------------------
// 5. Rasyonel sayılarla işlem önceliği
// ---------------------------------------------------------------------------
const _kesirA = [
  (1, 2), (3, 2), (5, 2), (1, 3), (2, 3), (4, 3), (5, 3), (7, 3), (1, 4),
  (3, 4), (5, 4), (7, 4), (1, 5), (2, 5), (3, 5), (4, 5), (6, 5), (7, 5),
  (1, 6), (5, 6), (7, 6), (9, 4), (8, 3), (7, 2), (9, 5), //
];
const _kesirB = [
  (2, 7), (3, 7), (5, 7), (1, 8), (3, 8), (5, 8), (7, 8), (2, 9), (4, 9),
  (5, 9), (7, 9), (3, 10), (7, 10), (9, 10), (1, 12), (5, 12), (7, 12),
  (11, 12), (4, 7), (8, 9), //
];

AdvancedItem _rasyonel(int a, int b, int c) {
  final x = _K(_kesirA[a].$1, _kesirA[a].$2);
  final y = _K(_kesirB[b].$1, _kesirB[b].$2);
  final kk = c ~/ 3;
  if (c % 3 == 0) {
    final (m, t) = const [(1, 2), (1, 3), (2, 3), (1, 4)][kk];
    final z = _K(y.d * m, t);
    final p = y * z, r = x + p;
    return _kesirSirali(
      '$x + $y · $z işleminin sonucu kaçtır?',
      r,
      [
        (x + y) * z, // önce toplama yapılmış
        p, // ara sonuç yanıt sanılmış
        _K(x.n + p.n, x.d + p.d), // paylar ve paydalar toplanmış
        x * z + y,
        x + y + z,
        x * y + z,
      ],
      'İşlem önceliği gereği önce çarpma yapılır: $y · $z = $p. Ardından '
          '$x + $p = $r bulunur.',
      _sira(a, b, c),
      pozitif: true,
    );
  }
  if (c % 3 == 1) {
    final q = _K(kk + 2);
    final z = _K(y.n, y.d * (kk + 2));
    final r = x - q;
    return _kesirSirali(
      '$x − $y : $z işleminin sonucu kaçtır?',
      r,
      [
        (x - y) / z, // önce çıkarma yapılmış
        x - y * z, // bölme yerine çarpma
        q - x, // işaret hatası
        x + q,
        _K(x.n - q.n, x.d), // tam sayı paydayla genişletilmemiş
        _K(0) - (x + q), // fark yerine toplamın ters işaretlisi
        q, // ara sonuç yanıt sanılmış
        x - _K(1) / q, // ters çevrilecek kesir karıştırılmış
      ],
      'İşlem önceliği gereği önce bölme yapılır: $y : $z = $y · '
          '${_K(z.d, z.n)} = $q. Ardından $x − $q = $r bulunur.',
      _sira(a, b, c),
    );
  }
  final (m, t) = const [(1, 2), (2, 3), (3, 4)][kk];
  final z = _K(y.n * m, y.d * t);
  final bol = x / y, r = bol * z;
  return _kesirSirali(
    '$x : $y · $z işleminin sonucu kaçtır?',
    r,
    [
      x / (y * z), // sağdan sola işlem yapılmış
      x * y * z, // bölme yerine çarpma
      x * z, // bölme atlanmış
      bol, // ara sonuç yanıt sanılmış
      y / x * z, // ters çevrilecek kesir karıştırılmış
    ],
    'Çarpma ve bölme aynı önceliktedir; işlemler soldan sağa yapılır. '
        '$x : $y = $bol ve $bol · $z = $r bulunur.',
    _sira(a, b, c),
    pozitif: true,
  );
}

// ---------------------------------------------------------------------------
// 6. Devirli ve sonlu ondalık gösterimler
// ---------------------------------------------------------------------------
AdvancedItem _ondalik(int a, int b, int c) {
  final kk = c ~/ 3;
  if (c % 3 == 0) {
    final t = a % 5, d = a == 24 ? 3 : t + 1 + a ~/ 5; // x = 0,tddd…, d ≠ 9
    final u = 6 + b % 4, e = 1 + b ~/ 4; // y = 0,ueee…
    final xs = 10 * t + d, ys = 10 * u + e;
    final x = _K(xs - t, 90), y = _K(ys - u, 90);
    final xo = _K(xs, 100), yo = _K(ys, 100); // devri yok sayma
    final xd = _K(xs, 99), yd = _K(ys, 99); // paydayı 99 alma
    final xe = _K(xs, 90), ye = _K(ys, 90); // devretmeyeni çıkarmama
    final x9 = _K(xs - t, 9), y9 = _K(ys - u, 9); // paydada 0 unutulmuş
    final xn = _K(xs - t, 99), yn = _K(ys - u, 99); // çıkarılıp 99 alınmış
    final xh = _K(xs - t, 100), yh = _K(ys - u, 100); // çıkarılıp 100 alınmış
    final (islem, r, yanlis) = switch (kk) {
      0 => (
        'x + y',
        x + y,
        [xo + yo, xd + yd, xe + ye, x9 + y9, xn + yn, xh + yh],
      ),
      1 => (
        'y − x',
        y - x,
        [yo - xo, yd - xd, ye - xe, y9 - x9, yn - xn, yh - xh],
      ),
      2 => (
        'x : y',
        x / y,
        [xo / yo, y / x, _K(xs - t, ys), _K(xs, ys - u), x9 / y, x / y9],
      ),
      _ => (
        'y : x',
        y / x,
        [yo / xo, x / y, _K(ys - u, xs), _K(ys, xs - t), y9 / x, y / x9],
      ),
    };
    return _kesirSirali(
      'Son yazılan rakamı sonsuza kadar tekrar eden x = 0,$t$d$d$d… ve '
          'y = 0,$u$e$e$e… devirli ondalık sayıları veriliyor. Buna göre $islem '
          'işleminin sonucu kaçtır?',
      r,
      yanlis,
      'x = ($xs − $t)/90 = $x ve y = ($ys − $u)/90 = $y olur. Buna göre '
          '$islem = $r bulunur.',
      _sira(a, b, c),
      pozitif: true,
    );
  }
  if (c % 3 == 1) {
    final p1 = 6 + a ~/ 5, q1 = 2 + a % 5, p2 = 2 + b ~/ 5, q2 = 2 + b % 5;
    final u = tr(p1 * q1 / 100), v = tr(q1 / 100);
    final w = tr(p2 * q2 / 10), z = tr(q2 / 10);
    double f(double s, double t) => kk == 0 ? s + t : (kk == 1 ? s - t : s * t);
    final r = f(p1.toDouble(), p2.toDouble()).round();
    final isaret = const ['+', '−', '·'][kk];
    final ifade = kk == 2 ? '($u : $v) · ($w : $z)' : '$u : $v $isaret $w : $z';
    final adaylar = [
      f(p1 / 10, p2.toDouble()), // virgül bir basamak kaydırılmış
      f(p1 * 10.0, p2.toDouble()),
      f(p1.toDouble(), p2 / 10),
      f(p1.toDouble(), p2 * 10.0),
      f(p1 / 10, p2 / 10), // iki bölmede de virgül kaydırılmış
      if (kk != 2) f(p1 * 10.0, p2 * 10.0),
      for (var k = 1; k <= 3; k++) ...[r + k.toDouble(), r - k.toDouble()],
    ].where((s) => s > 0);
    return AdvancedItem(
      '$ifade işleminin sonucu kaçtır?',
      '$r',
      siraliCeldiriciler(r, '$r', [
        for (final s in adaylar) (s, tr(s)),
      ], _sira(a, b, c)),
      '$u : $v = $p1 ve $w : $z = $p2 olduğundan sonuç $p1 $isaret $p2 = $r '
          'bulunur.',
    );
  }
  final t = b % 10;
  final d = [
    for (var k = 1; k <= 9; k++)
      if (k != t) k,
  ][(b ~/ 10) * 3 + kk];
  final tum = 100 * a + 10 * t + d, on = 10 * a + t;
  final x = _K(tum - on, 90);
  return _kesirSirali(
    'Son yazılan rakamı sonsuza kadar tekrar eden $a,$t$d$d$d… devirli ondalık '
        'sayısı en sade biçimde hangi kesre eşittir?',
    x,
    [
      _K(tum - on, 99), // paydada 90 yerine 99
      _K(tum, 100), // devir yok sayılmış
      _K(tum, 90), // devretmeyen kısım çıkarılmamış
      _K(tum - on, 9), // paydada 0 unutulmuş
      _K(tum - a, 90), // yalnız tam kısım çıkarılmış
      _K(tum - on, 100), // çıkarılıp 100 alınmış
      _K(9 * a + d, 9), // ondalık kısmın tamamı devreden sanılmış
    ],
    'Sayının virgülsüz yazılışından devretmeyen kısım çıkarılır; paydaya '
        'devreden basamak için 9, devretmeyen ondalık basamak için 0 yazılır: '
        '($tum − $on)/90 = $x.',
    _sira(a, b, c),
    pozitif: true,
  );
}

// ---------------------------------------------------------------------------
// 7. Üslü ifadeler
// ---------------------------------------------------------------------------
const _ustRakam = '⁰¹²³⁴⁵⁶⁷⁸⁹';
String _ust(int n) =>
    [for (final r in '$n'.split('')) _ustRakam[int.parse(r)]].join();
String _xArti(int p) => p == 0 ? 'x' : (p > 0 ? 'x + $p' : 'x − ${-p}');

AdvancedItem _uslu(int a, int b, int c) {
  final kk = c ~/ 2;
  if (c.isEven) {
    final (r, p) = const [(2, 2), (3, 2), (5, 2), (2, 3), (3, 3)][kk];
    final m = a + 4, n = b + 3, r2 = r * r, r3 = r * r * r;
    final yanit = m + 2 * n - 3 * p;
    return _tamSirali(
      '$r${_ust(m)} · $r2${_ust(n)} : $r3${_ust(p)} işleminin sonucu $r '
          'sayısının kaçıncı kuvvetidir?',
      yanit,
      [
        m + n - p, // tabanlar çevrilmemiş
        m + 2 * n + 3 * p, // bölmede üsler toplanmış
        m + 2 * n - p, // yalnız r² çevrilmiş
        m + n - 3 * p, // yalnız r³ çevrilmiş
        m + n - p - 1, // (aᵐ)ⁿ = aᵐ⁺ⁿ sanılmış
        m + 2 * n, // bölme unutulmuş
      ],
      '$r2 = $r² ve $r3 = $r³ olduğundan ifade $r${_ust(m)} · '
          '$r${_ust(2 * n)} : $r${_ust(3 * p)} biçiminde yazılır. Üsler toplanıp '
          'çıkarılır: $m + ${2 * n} − ${3 * p} = $yanit.',
      _sira(a, b, c),
      enAz: 1,
    );
  }
  final (r, k) = const [(2, 2), (3, 2), (2, 3), (5, 2), (3, 3)][kk];
  final buyuk = k == 2 ? r * r : r * r * r;
  final d = a - 12, q = b - 9;
  final x = q + d, p = (k - 1) * d - q;
  String us(int taban, int kayma) =>
      kayma == 0 ? '$taban^x' : '$taban^(${_xArti(kayma)})';
  final sag = q == 0 ? '${k}x' : '$k · (${_xArti(-q)})';
  return _tamSirali(
    '${us(r, p)} = ${us(buyuk, -q)} eşitliği veriliyor. Üsleri aynı tabana '
        'getirerek bu eşitliği sağlayan x gerçek sayısını bulunuz. x kaçtır?',
    x,
    [p + q, d, -x, k * d, x + q],
    '$buyuk = $r${_ust(k)} olduğundan iki taraf $r tabanında yazılır ve üsler '
        'eşitlenir: ${_xArti(p)} = $sag. Buradan x = ${_n(x)} bulunur.',
    _sira(a, b, c),
  );
}

// ---------------------------------------------------------------------------
// 8. Köklü ifadeler
// ---------------------------------------------------------------------------
const _kokCift = [
  (2, 3), (2, 4), (2, 5), (2, 6), (2, 7), (2, 8), (2, 9), (3, 4), (3, 5),
  (3, 6), (3, 7), (3, 8), (3, 9), (4, 5), (4, 6), (4, 7), (4, 8), (4, 9),
  (5, 6), (5, 7), (5, 8), (5, 9), (6, 7), (6, 8), (6, 9), //
];
const _karesiz = [
  (3, 2), (5, 2), (5, 3), (6, 2), (6, 3), (6, 5), (7, 2), (7, 3), (7, 5),
  (7, 6), (10, 2), (10, 3), (10, 6), (10, 7), (11, 2), (11, 3), (11, 5),
  (11, 6), (11, 7), (11, 10), (13, 2), (13, 3), (13, 5), (13, 6), (13, 7), //
];
String _kat(int k, String kok) => k == 1 ? kok : '$k$kok';

AdvancedItem _koklu(int a, int b, int c) {
  final kk = c ~/ 2;
  if (c.isEven) {
    final (p, q) = _kokCift[a];
    final s = 1 + b % 4, r = const [2, 3, 5, 6, 7][b ~/ 4];
    final ka = '√${p * p * r}', kb = '√${q * q * r}', kr = '√$r';
    final son = _kat(s, kr);
    final (ifade, u, v, w) = switch (kk) {
      0 => ('$kb − $ka + $son', 1, -1, 1),
      1 => ('2$kb − $ka + $son', 2, -1, 1),
      2 => ('$kb + $ka − $son', 1, 1, -1),
      3 => ('3$kb − 2$ka − $son', 3, -2, -1),
      _ => ('2$kb + $ka + $son', 2, 1, 1),
    };
    final yanit = u * q + v * p + w * s;
    final hesap =
        '${u == 1 ? '' : '$u · '}$q ${v < 0 ? '−' : '+'} '
        '${v.abs() == 1 ? '' : '${v.abs()} · '}$p ${w < 0 ? '−' : '+'} $s';
    return _tamSirali(
      '$ifade işleminin sonucu a√$r biçiminde yazıldığında a kaçtır?',
      yanit,
      [
        u * q * q + v * p * p + w * s, // kökler alınmamış
        u * q + v * p - w * s, // son terimin işareti
        u * q + v * p, // son terim unutulmuş
        u * q - v * p + w * s, // ortadaki terimin işareti
        if (u != 1 || v.abs() != 1) q + v.sign * p + w * s, // katsayılar
        u * q * q + v * p + w * s, // yalnız ilk kök alınmamış
        u * q + v * p * p + w * s, // yalnız ikinci kök alınmamış
        if (s > 1) u * q + v * p + w, // son katsayı unutulmuş
        u * q - v * p - w * s, // iki işaret hatası
      ],
      '$ka = $p√$r ve $kb = $q√$r yazılır. Katsayılar toplanır: $hesap = '
          '$yanit; sonuç ${_kat(yanit, kr)} olur.',
      _sira(a, b, c),
    );
  }
  final (m, n) = _karesiz[a];
  final t = 1 + b % 10, arti = b >= 10;
  final pay = (m - n) * t, bb = arti ? -t : t;
  int f(int x, int y) => switch (kk) {
    0 => arti ? x - y : x + y,
    1 => x * y,
    2 => x - 2 * y,
    3 => arti ? 2 * x - y : 2 * x + y,
    _ => x * x + y * y,
  };
  final soru = switch (kk) {
    0 => arti ? 'a − b farkı' : 'a + b toplamı',
    1 => 'a · b çarpımı',
    2 => 'a − 2b ifadesinin değeri',
    3 => arti ? '2a − b ifadesinin değeri' : '2a + b ifadesinin değeri',
    _ => 'a² + b² toplamı',
  };
  final yanit = f(t, bb);
  final yon = arti ? '+' : '−', es = arti ? '−' : '+';
  return _tamSirali(
    'a ve b rasyonel sayılar olmak üzere $pay/(√$m $yon √$n) = a√$m + b√$n '
        'eşitliği veriliyor. Buna göre $soru kaçtır?',
    yanit,
    [
      f(t, -bb), // eşlenik yanlış işaretle alınmış
      f(pay, arti ? -pay : pay), // m − n ile bölünmemiş
      t,
      kk == 4 ? t * t : -yanit,
      pay,
      ...switch (kk) {
        1 => [arti ? 0 : 2 * t], // çarpım yerine toplam
        2 => [arti ? 2 * t : 0], // a − 2b yerine a − b
        3 => [2 * t], // 2a yerine a
        4 => [4 * t * t, 2 * t], // (a ± b)², kare alınmamış
        _ => <int>[],
      },
    ],
    'Pay ve payda √$m $es √$n ile çarpılır; payda $m − $n = ${m - n} olur. '
        '$pay/${m - n} = $t olduğundan ifade ${_kat(t, '√$m')} $es '
        '${_kat(t, '√$n')} biçimine gelir. a = $t, b = ${_n(bb)} ve istenen değer '
        '${_n(yanit)} bulunur.',
    _sira(a, b, c),
    enAz: kk == 4 ? 1 : null,
  );
}

// ---------------------------------------------------------------------------
// Cebir yardımcıları
// ---------------------------------------------------------------------------
/// m·x + k ifadesi: “2x − 3”, “x + 4”, “5 − 2x”.
String _dogrusal(int m, int k) {
  final mx = m.abs() == 1 ? 'x' : '${m.abs()}x';
  if (m < 0 && k > 0) return '$k − $mx';
  final bas = m < 0 ? '−$mx' : mx;
  return k == 0 ? bas : (k > 0 ? '$bas + $k' : '$bas − ${-k}');
}

/// Katsayılı bilinmeyen: “x”, “−x”, “3x”, “−2x”.
String _kx(int m) => m == 1 ? 'x' : (m == -1 ? '−x' : '${_n(m)}x');

/// “3x = 12 ve x = 4” ya da katsayı 1 ise yalnız “x = 4”.
String _sonuc(int kat, int sag, int x) =>
    kat == 1 ? 'x = ${_n(x)}' : '${_kx(kat)} = ${_n(sag)} ve x = ${_n(x)}';

int _taban(int n, int d) => n >= 0 ? n ~/ d : -((-n + d - 1) ~/ d);
int _tavan(int n, int d) => -_taban(-n, d);

// ---------------------------------------------------------------------------
// 9. Mutlak değerli denklem ve eşitsizlik
// ---------------------------------------------------------------------------
AdvancedItem _mutlak(int a, int b, int c) {
  final kk = c ~/ 2, h = a - 12, w = b + 1, s = (a + b) % 3;
  final sira = _sira(a, b, c);
  if (c.isEven) {
    final m = kk + 1, ic = _dogrusal(m, -m * h), sag = m * w;
    final denk = '|$ic| = $sag denklemini sağlayan x değerlerinin';
    final k1 = h - w, k2 = h + w;
    final coz =
        '$ic = $sag ya da $ic = −$sag olmalıdır; kökler ${_n(k2)} ve '
        '${_n(k1)} bulunur.';
    if (s == 0) {
      return _tamSirali(
        '$denk toplamı kaçtır?',
        2 * h,
        [
          k2, // yalnız bir kök
          -2 * h, // işaret hatası
          2 * m * h, // m ile bölünmemiş
          h,
          2 * w, // toplam yerine fark
          k1,
          0, // kaydırma unutulup kökler ± alınmış
        ],
        '$coz Toplamları ${_n(2 * h)} olur.',
        sira,
      );
    }
    if (s == 1) {
      return _tamSirali(
        '$denk çarpımı kaçtır?',
        k1 * k2,
        [
          h * h + w * w, // çarpımda işaret hatası
          -(k1 * k2),
          k2 * k2, // bir kökün karesi
          h * w,
          if (m > 1) m * m * k1 * k2, // m ile bölünmemiş
          -w * w, // kökler ±w sanılmış
          k1 * k1,
          2 * h, // çarpım yerine toplam
        ],
        '$coz Çarpımları ${_n(k1 * k2)} olur.',
        sira,
      );
    }
    return _tamSirali(
      '$denk büyük olanı ile küçük olanının farkı kaçtır?',
      2 * w,
      [
        w,
        2 * m * w, // m ile bölünmemiş
        m * w,
        k2, // büyük kök yanıt sanılmış
        2 * h, // fark yerine toplam
        k1,
      ],
      '$coz Farkları ${_n(k2)} − ${k1 < 0 ? '(${_n(k1)})' : '$k1'} = ${2 * w} '
          'olur.',
      sira,
      enAz: 1,
    );
  }
  final (m, e, kesin) = const [
    (1, 0, true),
    (1, 0, false),
    (2, 1, false),
    (3, 0, true),
    (2, 1, true),
  ][kk];
  final q = m * w + e, ic = _dogrusal(m, -m * h), op = kesin ? '<' : '≤';
  final yari = kesin && e == 0 ? w - 1 : w;
  final adet = 2 * yari + 1, enB = h + yari, enK = h - yari;
  final esit = '|$ic| $op $q eşitsizliğini sağlayan';
  final coz =
      'Eşitsizlik −$q $op $ic $op $q biçiminde açılır. '
      '${adet == 1 ? 'Bunu yalnız x = ${_n(h)} tam sayısı sağlar' : 'Bunu '
                'sağlayan tam sayılar ${_n(enK)} ile ${_n(enB)} arasındaki (uçlar '
                'dâhil) $adet sayıdır'}';
  if (s == 0) {
    return _tamSirali(
      '$esit kaç farklı x tam sayısı vardır?',
      adet,
      [
        adet + 2, // uç değerler yanlış dâhil edilmiş
        if (adet > 2) adet - 2,
        2 * w,
        adet + 1,
        w,
        if (m > 1) 2 * q + 1, // m ile bölünmemiş
        adet - 1, // merkez sayılmamış
      ],
      '$coz.',
      sira,
      enAz: 0,
    );
  }
  if (s == 1) {
    return _tamSirali(
      '$esit x tam sayılarının toplamı kaçtır?',
      h * adet,
      [
        h * (adet + 2),
        h * (adet - 2),
        h,
        adet, // toplam yerine sayı adedi
        -h * adet, // işaret hatası
        0, // çözümler 0 çevresinde sanılmış
        2 * h, // yalnız uç değerler toplanmış
        h * (adet + 1),
      ],
      adet == 1
          ? '$coz; toplam ${_n(h)} olur.'
          : '$coz; bu sayılar ${_n(h)} çevresinde simetrik olduğundan toplamları '
                '$adet · ${h < 0 ? '(${_n(h)})' : '$h'} = ${_n(h * adet)} olur.',
      sira,
    );
  }
  return _tamSirali(
    '$esit en büyük x tam sayısı kaçtır?',
    enB,
    [
      enB + 1, // uç değer yanlış dâhil edilmiş
      enB - 1,
      h + q, // m ile bölünmemiş
      yari, // kaydırma unutulmuş
      enK, // en küçük çözüm
      yari - h, // merkezin işareti yanlış
      q,
    ],
    '$coz; en büyüğü ${_n(enB)} olur.',
    sira,
  );
}

// ---------------------------------------------------------------------------
// 10. Birinci dereceden bir bilinmeyenli denklemler
// ---------------------------------------------------------------------------
AdvancedItem _denklem(int a, int b, int c) {
  final kk = c ~/ 2;
  if (c.isEven) {
    final r = 2 + a % 5, p = r + 1 + a ~/ 5;
    final q = 1 + b % 5, s = 1 + b ~/ 5;
    final x = (3 * a + 7 * b + 5 * kk) % 19 - 9;
    final t = p * (x + q) - r * (x - s), f = p - r;
    int? bol(int pay) => pay % f == 0 ? pay ~/ f : null;
    return _isaretli(
      '$p(x + $q) − $r(x − $s) = ${_n(t)} denklemini sağlayan x değeri kaçtır?',
      x,
      [
        bol(t - p * q + r * s), // −r · (−s) işareti yanlış
        bol(t - q - s), // sabitler katsayıyla çarpılmamış
        if (f > 1) f * x, // ara sonuç yanıt sanılmış
        bol(t + p * q + r * s), // sabitler işaret değiştirmeden geçirilmiş
        bol(t - p * q - s), // yalnız ilk parantez açılmış
        bol(t - q - r * s), // yalnız ikinci parantez açılmış
        x + s,
        x - q,
        -x,
      ].whereType<int>(),
      'Parantezler açılır: ${p}x + ${p * q} − ${r}x + ${r * s} = ${_n(t)}. '
          'Buradan ${_sonuc(f, t - p * q - r * s, x)} bulunur.',
      _sira(a, b, c),
    );
  }
  final (m, n) = const [(2, 3), (3, 4), (2, 5), (3, 5), (4, 5)][kk];
  final u = a % 5 - 2, v = b % 5 - 2;
  final x = (a ~/ 5) * 4 + b ~/ 5 - 9;
  final p = m * u - x, q = x - n * v, t = u - v, f = n - m;
  String ks(int kayma, int payda) =>
      kayma == 0 ? 'x/$payda' : '(${_xArti(kayma)})/$payda';
  String carp(int kat, int kayma) =>
      kayma == 0 ? '${kat}x' : '$kat · (${_xArti(kayma)})';
  final sagTaraf = m * n * t;
  int? bol(int pay) => pay % f == 0 ? pay ~/ f : null;
  return _isaretli(
    '${ks(p, m)} − ${ks(-q, n)} = ${_n(t)} denklemini sağlayan x değeri '
        'kaçtır?',
    x,
    [
      bol(sagTaraf - n * p + m * q), // ikinci payın işareti yanlış
      bol(t - n * p - m * q), // sağ taraf paydalarla çarpılmamış
      bol(sagTaraf + n * p + m * q), // sabitler işaret değiştirmeden geçirilmiş
      if (f > 1) f * x, // ara sonuç yanıt sanılmış
      bol(m * t - n * p - m * q), // sağ taraf yalnız bir paydayla çarpılmış
      bol(n * t - n * p - m * q),
      x + 1,
      x - 1,
      -x,
    ].whereType<int>(),
    'Denklemin iki tarafı ${m * n} ile çarpılır: ${carp(n, p)} − '
        '${carp(m, -q)} = ${_n(sagTaraf)}. Parantezler açılıp düzenlenirse '
        '${_sonuc(f, sagTaraf - n * p - m * q, x)} bulunur.',
    _sira(a, b, c),
  );
}

// ---------------------------------------------------------------------------
// 11. Birinci dereceden eşitsizlikler
// ---------------------------------------------------------------------------
AdvancedItem _esitsizlik(int a, int b, int c) {
  final kk = c ~/ 2, sira = _sira(a, b, c);
  if (c.isEven) {
    final m = const [2, 3, -2, 5, -3][kk];
    final k = (a + 2 * b) % 9 - 4;
    final xlo = a - 12, xhi = xlo + b + 2, tip = (a + b) % 4;
    final altDahil = tip == 1 || tip == 3, ustDahil = tip == 0 || tip == 3;
    final sol = m > 0 ? m * xlo + k : m * xhi + k;
    final sag = m > 0 ? m * xhi + k : m * xlo + k;
    final solDahil = m > 0 ? altDahil : ustDahil;
    final sagDahil = m > 0 ? ustDahil : altDahil;
    final ifade =
        '${_n(sol)} ${solDahil ? '≤' : '<'} ${_dogrusal(m, k)} '
        '${sagDahil ? '≤' : '<'} ${_n(sag)} eşitsizliğini sağlayan';
    final enK = altDahil ? xlo : xlo + 1, enB = ustDahil ? xhi : xhi - 1;
    final adet = enB - enK + 1;
    final coz =
        'Eşitsizlikte x yalnız bırakılır'
        '${m < 0 ? ' (negatif sayıya bölünürken eşitsizlikler yön değiştirir)' : ''}'
        ': ${_n(xlo)} ${altDahil ? '≤' : '<'} x ${ustDahil ? '≤' : '<'} '
        '${_n(xhi)}.';
    if (b % 3 == 0) {
      return _tamSirali(
        '$ifade kaç farklı x tam sayısı vardır?',
        adet,
        [
          adet + 1, // bir uç değer yanlış dâhil edilmiş
          adet - 1, // bir uç değer yanlış dışarıda bırakılmış
          xhi - xlo + 2,
          sag - sol, // katsayıya bölünmemiş
          adet + 2, // iki uç değer yanlış dâhil edilmiş
          adet - 2,
          xhi - xlo, // aralığın uzunluğu
        ],
        adet == 1
            ? '$coz Bu aralıktaki tek tam sayı ${_n(enK)} olduğundan yanıt 1 olur.'
            : '$coz Bu aralıktaki tam sayılar ${_n(enK)} ile ${_n(enB)} '
                  'arasındadır (uçlar dâhil); sayıları $adet olur.',
        sira,
        enAz: 0,
      );
    }
    if (b % 3 == 1) {
      return _tamSirali(
        '$ifade en büyük x tam sayısı kaçtır?',
        enB,
        [
          ustDahil ? xhi - 1 : xhi, // uç değer yanlış yorumlanmış
          enK, // en küçük çözüm
          sag, // katsayıya bölünmemiş
          -enB, // işaret hatası
          enB + 1,
          enB - 1,
          sol,
        ],
        '$coz Bu aralıktaki en büyük tam sayı ${_n(enB)} olur.',
        sira,
      );
    }
    return _tamSirali(
      '$ifade en küçük x tam sayısı kaçtır?',
      enK,
      [
        altDahil ? xlo + 1 : xlo, // uç değer yanlış yorumlanmış
        enB, // en büyük çözüm
        sol, // katsayıya bölünmemiş
        -enK, // işaret hatası
        enK - 1,
        enK + 1,
        sag,
      ],
      '$coz Bu aralıktaki en küçük tam sayı ${_n(enK)} olur.',
      sira,
    );
  }
  final p = 4 + a % 5, r = p + const [-3, -2, -1, 1, 2][a ~/ 5];
  final u = 1 + b % 4, v = 3 + 2 * (b ~/ 4) + (kk == 4 ? 11 : 0);
  final isaret = const ['<', '≤', '>', '≥', '<'][kk];
  final ters = p < r;
  final yon = ters
      ? const {'<': '>', '≤': '≥', '>': '<', '≥': '≤'}[isaret]!
      : isaret;
  final dd = (p - r).abs(), nn = ters ? -(u + v) : u + v;
  final ustSinir = yon == '<' || yon == '≤';
  int cevap(String op, int pay, int payda) => switch (op) {
    '<' => _tavan(pay, payda) - 1,
    '≤' => _taban(pay, payda),
    '>' => _taban(pay, payda) + 1,
    _ => _tavan(pay, payda),
  };
  final yanit = cevap(yon, nn, dd);
  final uc = ustSinir ? 'büyük' : 'küçük';
  return _tamSirali(
    '${_dogrusal(p, -u)} $isaret ${_dogrusal(r, v)} eşitsizliğini sağlayan en '
        '$uc x tam sayısı kaçtır?',
    yanit,
    [
      yanit + 1, // sınır değer yanlış yorumlanmış
      yanit - 1,
      -yanit, // işaret hatası
      u + v, // katsayıya bölünmemiş
      cevap(yon, ters ? u - v : v - u, dd), // sabit karşıya geçerken işaret
      cevap(isaret, u + v, p + r), // rx karşıya geçerken işaret
      if (ters) cevap(isaret, nn, dd), // yön değiştirilmemiş
      yanit + 2,
    ],
    'Bilinmeyenler solda, sabitler sağda toplanır: ${_kx(p - r)} $isaret '
        '${u + v}. ${ters ? 'İki taraf negatif sayıya bölündüğünden eşitsizlik yön '
                  'değiştirir. ' : ''}'
        'Buradan x $yon ${_K(nn, dd)} olur; bu koşulu sağlayan en $uc tam sayı '
        '${_n(yanit)} bulunur.',
    sira,
  );
}

// ---------------------------------------------------------------------------
// 12. İki bilinmeyenli doğrusal denklem sistemi
// ---------------------------------------------------------------------------
const _sistemKatsayi = [
  (1, 1, 1, -1), (2, 1, 1, -1), (3, 2, 1, 1), (2, 3, 3, -2), (1, 2, 3, -1),
  (2, 3, 3, 2), (5, 2, 3, 1), (4, -3, 2, 1), (2, 5, 1, 3), (3, 4, 2, -1), //
];

String _ikili(int p, int q, int e) {
  final px = p == 1 ? 'x' : '${p}x';
  final qy = q.abs() == 1 ? 'y' : '${q.abs()}y';
  return '$px ${q < 0 ? '−' : '+'} $qy = ${_n(e)}';
}

AdvancedItem _sistem(int a, int b, int c) {
  final (p, q, r, s) = _sistemKatsayi[c];
  final x = a - 8, y = b - 6;
  final e1 = p * x + q * y, e2 = r * x + s * y;
  final toplamVar = (p == 1 && q == 1) || (r == 1 && s == 1);
  final (soru, yanit, yanlis) = switch ((a + b) % 4) {
    0 => ('x', x, [y, x + y, -x]),
    1 => ('y', y, [x, x + y, -y]),
    2 when !toplamVar => ('x + y toplamı', x + y, [x - y, x, y]),
    _ => ('x · y çarpımı', x * y, [x + y, -(x * y), x * x]),
  };
  final ms = s.abs(), mq = q.abs(), topla = q * s < 0;
  final kat = topla ? p * ms + r * mq : p * ms - r * mq;
  final sagTaraf = topla ? e1 * ms + e2 * mq : e1 * ms - e2 * mq;
  final carpim = ms == 1 && mq == 1
      ? 'Denklemler'
      : ms == 1
      ? 'İkinci denklem $mq ile çarpılıp denklemler'
      : mq == 1
      ? 'Birinci denklem $ms ile çarpılıp denklemler'
      : 'Birinci denklem $ms ile, ikinci denklem $mq ile çarpılıp';
  return _tam(
    '${_ikili(p, q, e1)} ve ${_ikili(r, s, e2)} denklemlerini birlikte '
        'sağlayan x ve y gerçek sayıları için $soru kaçtır?',
    yanit,
    yanlis,
    '$carpim taraf tarafa '
        '${topla ? 'toplanırsa' : 'çıkarılırsa'} ${_sonuc(kat, sagTaraf, x)} '
        'bulunur. Yerine yazılınca y = ${_n(y)} olur; istenen değer ${_n(yanit)} '
        'bulunur.',
  );
}

/// Yüzde yanıtlı soru: seçenekler “%25” biçimindedir.
AdvancedItem _yuzdeSoru(
  String kok,
  int yanit,
  Iterable<int> adaylar,
  String aciklama,
) => secenekli(
  kok,
  '%$yanit',
  [
    ...adaylar,
    yanit + 5,
    yanit - 5,
    yanit + 10,
    yanit - 10,
    yanit + 15,
    yanit + 20,
    yanit + 2,
  ].where((x) => x > 0).map((x) => '%$x'),
  aciklama,
);

// ---------------------------------------------------------------------------
// 13. Oran ve orantı
// ---------------------------------------------------------------------------
const _paylar = [
  (1, 2, 3), (1, 2, 4), (1, 3, 4), (2, 3, 4), (1, 2, 5), (1, 3, 5), (1, 4, 5),
  (2, 3, 5), (2, 4, 5), (3, 4, 5), (1, 3, 6), (1, 4, 6), (1, 5, 6), (2, 3, 6),
  (2, 5, 6), (3, 4, 6), (3, 5, 6), (4, 5, 6), (1, 2, 7), (1, 3, 7), (2, 3, 7),
  (2, 5, 7), (3, 4, 7), (3, 5, 7), (4, 5, 7), //
];

AdvancedItem _oran(int a, int b, int c) {
  final kk = c ~/ 3;
  final (u0, v0) = _asalCift[a];
  if (c % 3 == 0) {
    final ters = (a + b).isOdd;
    final u = ters ? v0 : u0, v = ters ? u0 : v0, g = kk + 2;
    final w = switch (kk) {
      0 => 30 + 10 * b,
      1 => 9 + b,
      2 => 40 + 2 * b,
      _ => 20 + 3 * b, // 5 dakikada 20–77 litre: dakikada 4–15,4 litre
    };
    final t1 = u * g, t2 = v * g, n1 = u * w, yanit = v * w;
    final kok = switch (kk) {
      0 =>
        'Bir matbaa makinesi $t1 dakikada $n1 broşür basmaktadır. Aynı hızla '
            'çalışan bu makine $t2 dakikada kaç broşür basar?',
      1 =>
        'Bir fırında $t1 kg undan $n1 ekmek yapılmaktadır. Aynı tarifle $t2 kg '
            'undan kaç ekmek yapılır?',
      2 =>
        'Bir araç $t1 litre yakıtla $n1 km yol gitmektedir. Aynı koşullarda '
            '$t2 litre yakıtla kaç km yol gider?',
      _ =>
        'Bir musluktan $t1 dakikada $n1 litre su akmaktadır. Aynı debiyle $t2 '
            'dakikada kaç litre su akar?',
    };
    return sayisal(
      kok,
      yanit,
      [
        n1 + (t2 - t1),
        if (n1 * t1 % t2 == 0) n1 * t1 ~/ t2,
        (n1 ~/ t1) * t2,
        w,
      ],
      'Çokluklar doğru orantılıdır: $t1 için $n1, $t2 için x alınırsa '
      'x = $n1 · $t2 / $t1 = $yanit bulunur.',
      positive: true,
    );
  }
  if (c % 3 == 1) {
    final azalt = a.isOdd, g = kk + 1, farkSor = b >= 10;
    final w = 1 + b % 10 + (1 + b % 10 >= g ? 1 : 0); // w ≠ g
    final p = (azalt ? v0 : u0) * g, q = (azalt ? u0 : v0) * g;
    final d1 = (azalt ? u0 : v0) * w, d2 = (azalt ? v0 : u0) * w;
    // Kat g = kk + 1: pompa sayısı en çok 11, makine 22, işçi 33 olur.
    final (nit, birim, isAdi, sure, zb, f1, f2) = const [
      (
        'Özdeş',
        'pompa',
        'depoyu',
        'saatte',
        'saat',
        'doldurmaktadır',
        'doldurur',
      ),
      (
        'Özdeş',
        'makine',
        'siparişi',
        'saatte',
        'saat',
        'tamamlamaktadır',
        'tamamlar',
      ),
      (
        'Eşit güçteki',
        'işçi',
        'işi',
        'günde',
        'gün',
        'bitirmektedir',
        'bitirir',
      ),
    ][kk];
    final bas =
        '$nit $p $birim bir $isAdi $d1 $sure $f1. Aynı nitelikteki $q $birim '
        'bu $isAdi';
    final coz =
        'Bu iki çokluk ters orantılıdır; çarpımları sabittir: $p · $d1 = '
        '$q · x. Buradan x = ${p * d1} / $q = $d2 bulunur.';
    if (!farkSor) {
      return sayisal(
        '$bas kaç $sure $f2?',
        d2,
        [if (d1 * q % p == 0) d1 * q ~/ p, d1 + p - q, d1, (d1 - d2).abs()],
        coz,
        positive: true,
      );
    }
    final fark = (d1 - d2).abs();
    return sayisal(
      '$bas kaç $zb daha ${azalt ? 'geç' : 'erken'} $f2?',
      fark,
      [d2, (p - q).abs(), d1, if (d1 * q % p == 0) (d1 * q ~/ p - d1).abs()],
      '$coz Süreler arasındaki fark $fark $zb olur.',
      positive: true,
    );
  }
  final (x, y, z) = _paylar[a];
  final k = 25 * (b + 2), t = k * (x + y + z);
  String pay(int kat) => kat == 1 ? 'k' : '${kat}k';
  final (soru, yanit) = [
    ('en büyük pay kaç TL olur?', z * k),
    ('en küçük pay kaç TL olur?', x * k),
    ('en büyük pay ile en küçük pay arasındaki fark kaç TL olur?', (z - x) * k),
  ][kk];
  return sayisal(
    '$t TL, üç ortak arasında sırasıyla $x, $y ve $z sayılarıyla doğru orantılı '
        'olarak paylaştırılıyor. Buna göre $soru',
    yanit,
    [y * k, k, z * k, x * k, (z - x) * k, t ~/ 3, (z + x) * k],
    'Paylar ${pay(x)}, ${pay(y)} ve ${pay(z)} olsun. ${x + y + z}k = $t '
        'eşitliğinden k = $k bulunur; istenen değer $yanit TL olur.',
    unit: 'TL',
    positive: true,
  );
}

// ---------------------------------------------------------------------------
// 14. Yüzde problemleri
// ---------------------------------------------------------------------------
const _urunler = [
  'ceket',
  'mont',
  'çanta',
  'ayakkabı',
  'kulaklık',
  'saat',
  'gözlük',
  'valiz', //
];
const _yuzdeler = [
  4,
  5,
  8,
  10,
  12,
  15,
  16,
  20,
  24,
  25,
  30,
  32,
  35,
  40,
  45,
  48,
  50,
  60,
  64,
  75, //
];

AdvancedItem _yuzde(int a, int b, int c) {
  final kk = c ~/ 2;
  if (c.isEven) {
    final p = 10 * (1 + a % 5), q = 10 * (1 + a ~/ 5);
    final k = b + 2, f = 100 * k, urun = sec(_urunler, a + b);
    final (s1, s2) = switch (kk) {
      0 || 4 => (1, -1),
      1 => (1, 1),
      2 => (-1, -1),
      _ => (-1, 1),
    };
    final c1 = 100 + s1 * p, c2 = 100 + s2 * q;
    final ara = k * c1, son = ara * c2 ~/ 100;
    final w1 = s1 > 0 ? 'zam' : 'indirim', w2 = s2 > 0 ? 'zam' : 'indirim';
    if (kk == 4) {
      return sayisal(
        'Bir $urun için önce %$p zam, ardından yeni fiyat üzerinden %$q indirim '
            'yapıldığında son fiyat $son TL oluyor. Buna göre ilk fiyat kaç TL '
            'idi?',
        f,
        [
          son * (100 + q) ~/ 100 * (100 - p) ~/ 100,
          son * 100 ~/ (100 + p - q),
          son * 100 ~/ c1,
          son * 100 ~/ c2,
        ],
        'İlk fiyat x TL olsun. x · $c1/100 · $c2/100 = $son eşitliğinden '
            'x = $f bulunur.',
        unit: 'TL',
        positive: true,
      );
    }
    return sayisal(
      'Etiket fiyatı $f TL olan bir $urun için önce %$p $w1, ardından yeni '
          'fiyat üzerinden %$q $w2 yapılıyor. Buna göre son fiyat kaç TL olur?',
      son,
      [k * (100 + s1 * p + s2 * q), ara, ara * (100 - s2 * q) ~/ 100, f],
      'İlk işlemden sonra fiyat $f · $c1/100 = $ara TL olur. İkinci işlemden '
          'sonra $ara · $c2/100 = $son TL bulunur.',
      unit: 'TL',
      positive: true,
    );
  }
  final p = _yuzdeler[b], artis = kk.isEven;
  final v =
      100 *
      switch (kk) {
        0 => 12 + a,
        1 => 3 + a,
        2 => 20 + 2 * a,
        3 => 5 + a,
        _ => 1 + a,
      };
  final w = v * (artis ? 100 + p : 100 - p) ~/ 100, fark = (w - v).abs();
  final kok = switch (kk) {
    0 =>
      'Bir kasabanın nüfusu $v kişiden $w kişiye çıkmıştır. Buna göre '
          'kasabanın nüfusu yüzde kaç artmıştır?',
    1 =>
      'Bir ürünün fiyatı $v TL iken $w TL olarak değiştirilmiştir. Buna göre '
          'ürünün fiyatı yüzde kaç azalmıştır?',
    2 =>
      'Bir fabrikanın aylık üretimi $v adetten $w adede çıkmıştır. Buna göre '
          'üretim yüzde kaç artmıştır?',
    3 =>
      'Bir depodaki su miktarı $v litreden $w litreye düşmüştür. Buna göre '
          'depodaki su miktarı yüzde kaç azalmıştır?',
    _ =>
      'Bir internet sitesinin günlük ziyaretçi sayısı $v iken $w olmuştur. '
          'Buna göre ziyaretçi sayısı yüzde kaç artmıştır?',
  };
  return _yuzdeSoru(
    kok,
    p,
    [if (fark * 100 % w == 0) fark * 100 ~/ w, w * 100 ~/ v, 100 - p],
    'Değişim miktarı $fark olur. Bu miktarın ilk değere oranı $fark/$v = '
    '$p/100 olduğundan değişim %$p bulunur.',
  );
}

// ---------------------------------------------------------------------------
// 15. Kâr-zarar problemleri
// ---------------------------------------------------------------------------
AdvancedItem _karZarar(int a, int b, int c) {
  final kk = c ~/ 2, sira = _sira(a, b, c);
  if (c.isEven) {
    final m = 200 * (b + 1);
    final p = 40 + 10 * (a % 5), q = 5 * (1 + a ~/ 5);
    final etiket = m * (100 + p) ~/ 100, satis = etiket * (100 - q) ~/ 100;
    final kar = satis - m, indirim = etiket - satis;
    final oran = (100 + p) * (100 - q) / 10000;
    if (kk == 2 || kk == 3) {
      final veri = kk == 2
          ? '$satis TL fiyatla satılıyor'
          : 'satıldığında $kar TL kâr elde ediliyor';
      return sayisalSirali(
        'Maliyeti üzerinden %$p kârla etiketlenen bir ürün, etiket fiyatı '
            'üzerinden %$q indirimle $veri. Buna göre ürünün maliyeti kaç TL olur?',
        m,
        kk == 2
            ? [
                satis * 100 ~/ (100 + p - q), // yüzdeler çıkarılmış
                etiket,
                satis * 100 ~/ (100 + p), // indirim hesaba katılmamış
                satis, // satış fiyatı yanıt sanılmış
                satis * (100 - p) ~/ 100, // kâr satış fiyatından düşülmüş
              ]
            : [
                kar * 100 ~/ (p - q), // yüzdeler çıkarılmış
                kar * 100 ~/ p, // indirim hesaba katılmamış
                satis,
                etiket,
                kar * 100 ~/ q,
              ],
        'Maliyet x TL olsun. Satış fiyatı x · ${100 + p}/100 · ${100 - q}/100 '
            '= ${tr(oran, 4)}x olur. '
            '${kk == 2 ? '${tr(oran, 4)}x = $satis' : '${tr(oran, 4)}x − x = $kar'} '
            'eşitliğinden x = $m bulunur.',
        sira,
        unit: 'TL',
        positive: true,
      );
    }
    final (soru, yanit, yanlis) = switch (kk) {
      0 => (
        'ürünün satış fiyatı kaç TL olur?',
        satis,
        [
          etiket, // indirim yapılmamış
          m * (100 + p - q) ~/ 100, // yüzdeler çıkarılmış
          kar,
          m,
          etiket * (100 + q) ~/ 100, // indirim eklenmiş
          m * (100 - q) ~/ 100, // indirim maliyete uygulanmış
          indirim,
        ],
      ),
      1 => (
        'bu satıştan kaç TL kâr elde edilir?',
        kar,
        [
          m * (p - q) ~/ 100, // yüzdeler çıkarılmış
          etiket - m, // indirim düşülmemiş
          indirim,
          satis,
          m * q ~/ 100, // indirim oranı maliyete uygulanmış
          etiket,
        ],
      ),
      _ => (
        'yapılan indirim kaç TL olur?',
        indirim,
        [
          m * q ~/ 100, // indirim maliyet üzerinden
          kar,
          etiket - m, // etiket farkı
          satis * q ~/ 100, // indirim satış fiyatı üzerinden
          satis,
          m * (p + q) ~/ 100,
        ],
      ),
    };
    return sayisalSirali(
      'Maliyeti $m TL olan bir ürün, maliyet üzerinden %$p kârla '
          'etiketlenmiştir. Bu ürün etiket fiyatı üzerinden %$q indirimle '
          'satılıyor. Buna göre $soru',
      yanit,
      yanlis,
      'Etiket fiyatı $m · ${100 + p}/100 = $etiket TL, satış fiyatı $etiket · '
          '${100 - q}/100 = $satis TL olur. İndirim $indirim TL, kâr $satis − $m = '
          '$kar TL olduğundan istenen değer $yanit TL bulunur.',
      sira,
      unit: 'TL',
      positive: true,
    );
  }
  final m = 100 * (b + 2), p = 10 + 10 * (a % 5), q = 10 + 5 * (a ~/ 5);
  final karli = m * (100 + p) ~/ 100, zararli = m * (100 - q) ~/ 100;
  final d = karli - zararli;
  final maliyet =
      'Maliyet x TL olsun; %$p kârlı satış ${100 + p}x/100, %$q zararlı satış '
      '${100 - q}x/100 olur.';
  switch (kk) {
    case 0:
      return sayisal(
        'Bir ürün $karli TL fiyatla satıldığında %$p kâr elde ediliyor. Aynı '
            'ürün %$q zararla satılsaydı satış fiyatı kaç TL olurdu?',
        zararli,
        [m, karli * (100 - q) ~/ 100, karli * (100 - p - q) ~/ 100, d],
        '$maliyet ${100 + p}x/100 = $karli eşitliğinden x = $m bulunur. '
            'Zararlı satış fiyatı $m · ${100 - q}/100 = $zararli TL olur.',
        unit: 'TL',
        positive: true,
      );
    case 1:
      return sayisal(
        'Bir ürün $zararli TL fiyatla satıldığında %$q zarar ediliyor. Aynı '
            'ürün %$p kârla satılsaydı satış fiyatı kaç TL olurdu?',
        karli,
        [m, zararli * (100 + p) ~/ 100, zararli * (100 + p + q) ~/ 100, d],
        '$maliyet ${100 - q}x/100 = $zararli eşitliğinden x = $m bulunur. '
            'Kârlı satış fiyatı $m · ${100 + p}/100 = $karli TL olur.',
        unit: 'TL',
        positive: true,
      );
    case 2:
      return sayisal(
        'Bir ürünün %$p kârla satış fiyatı, %$q zararla satış fiyatından $d TL '
            'fazladır. Buna göre ürünün maliyeti kaç TL olur?',
        m,
        [d * 100 ~/ p, d, if (p != q) d * 100 ~/ (p - q).abs(), karli],
        '$maliyet Fark ${p + q}x/100 = $d olduğundan x = $m bulunur.',
        unit: 'TL',
        positive: true,
      );
    case 3:
      return _yuzdeSoru(
        'Bir ürün $karli TL fiyatla satıldığında %$p kâr elde ediliyor. Aynı '
            'ürün $zararli TL fiyatla satılırsa yüzde kaç zarar edilir?',
        q,
        [d * 100 ~/ karli, p + q, 100 - q],
        '$maliyet ${100 + p}x/100 = $karli eşitliğinden x = $m bulunur. Zarar '
            '$m − $zararli = ${m - zararli} TL olup maliyetin %$q kadarıdır.',
      );
    default:
      return sayisal(
        'Bir ürün $zararli TL fiyatla satıldığında %$q zarar ediliyor. Bu '
            'üründen %$p kâr elde edilmesi için satış fiyatı kaç TL '
            'artırılmalıdır?',
        d,
        [m * p ~/ 100, zararli * (p + q) ~/ 100, karli, m - zararli],
        '$maliyet ${100 - q}x/100 = $zararli eşitliğinden x = $m bulunur. '
            'Kârlı satış fiyatı $karli TL olacağından fiyat $karli − $zararli = '
            '$d TL artırılmalıdır.',
        unit: 'TL',
        positive: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 16. Karışım problemleri
// ---------------------------------------------------------------------------
// Tuzlu su en çok %25, şekerli su en çok %49 derişimle kullanılır; daha
// yüksek oranlar asit ya da alkol çözeltisiyle sorulur.
const _tuz = ('tuz', 'tuzlu su'), _seker = ('şeker', 'şekerli su');
const _asit = ('asit', 'asit çözeltisi'), _alkol = ('alkol', 'alkol çözeltisi');

AdvancedItem _karisim(int a, int b, int c) {
  final kk = c ~/ 3;
  final cift = (a + b + c).isEven;
  if (c % 3 == 0) {
    final (madde, sivi) = cift ? _asit : _alkol;
    final d1 = 5 * (1 + a % 5), d2 = 5 * (1 + a ~/ 5);
    final p = 5 + 2 * b, r = p + d1, q = r + d2, k = 2 * (kk + 1);
    final m1 = d2 * k, m2 = d1 * k;
    final s1 = m1 * p / 100, s2 = m2 * q / 100;
    return _yuzdeSoru(
      'Kütlece %$p oranında $madde içeren $m1 gram $sivi ile kütlece %$q '
          'oranında $madde içeren $m2 gram $sivi karıştırılıyor. Oluşan karışımın '
          '$madde oranı yüzde kaçtır?',
      r,
      [(p + q) ~/ 2, p + d2, q - p, r + 10],
      'Çözünen madde miktarı $m1 · $p/100 + $m2 · $q/100 = ${tr(s1)} + '
          '${tr(s2)} = ${tr(s1 + s2)} gram, toplam kütle ${m1 + m2} gramdır. Oran '
          '${tr(s1 + s2)}/${m1 + m2} = $r/100, yani %$r olur.',
    );
  }
  final kp = const [5, 20, 10][kk], d = 2 + b;
  if (c % 3 == 1) {
    final r = 4 + a, p = r + d, m = r * kp, w = d * kp;
    final s = m * p / 100;
    final (madde, sivi) = cift ? _seker : (p <= 25 ? _tuz : _asit);
    if (kk < 2) {
      return _yuzdeSoru(
        'Kütlece %$p oranında $madde içeren $m gram $sivi içine $w gram saf su '
            'ekleniyor. Oluşan karışımın $madde oranı yüzde kaçtır?',
        r,
        [d, 100 * w ~/ (m + w), (p / 2).round(), p - 1],
        'Çözünen madde miktarı $m · $p/100 = ${tr(s)} gram olup değişmez. '
            'Toplam kütle $m + $w = ${m + w} gram olduğundan oran ${tr(s)}/${m + w} '
            '= $r/100, yani %$r olur.',
      );
    }
    return sayisal(
      'Kütlece %$p oranında $madde içeren $m gram $sivi içine kaç gram saf su '
          'eklenirse karışımın $madde oranı %$r olur?',
      w,
      [m * (p - r) ~/ 100, m + w, (s).round(), m * r ~/ p],
      'Çözünen madde miktarı $m · $p/100 = ${tr(s)} gram olup değişmez. Yeni '
          'toplam kütle ${tr(s)} · 100/$r = ${m + w} gram olmalıdır; eklenecek su '
          '${m + w} − $m = $w gram bulunur.',
      unit: 'g',
      positive: true,
    );
  }
  final p = 4 + a, r = p + d, m = r * kp, w = d * kp;
  final s = m * p / 100;
  final (madde, sivi) = !cift && r <= 25 ? _tuz : _seker;
  if (kk < 2) {
    return _yuzdeSoru(
      'Kütlece %$p oranında $madde içeren $m gram $sivi ısıtılarak $w gram su '
          'buharlaştırılıyor. Kalan karışımın $madde oranı yüzde kaçtır?',
      r,
      [p * m ~/ (m + w), 100 * w ~/ m, d, 2 * p],
      'Çözünen madde miktarı $m · $p/100 = ${tr(s)} gram olup değişmez. Kalan '
          'kütle $m − $w = ${m - w} gram olduğundan oran ${tr(s)}/${m - w} = '
          '$r/100, yani %$r olur.',
    );
  }
  return sayisal(
    'Kütlece %$p oranında $madde içeren $m gram $sivi ısıtılarak kaç gram su '
        'buharlaştırılırsa kalan karışımın $madde oranı %$r olur?',
    w,
    [m - w, m * (r - p) ~/ 100, (s).round(), m * p ~/ 100 + w],
    'Çözünen madde miktarı $m · $p/100 = ${tr(s)} gram olup değişmez. Kalan '
        'kütle ${tr(s)} · 100/$r = ${m - w} gram olmalıdır; buharlaşan su $m − '
        '${m - w} = $w gram bulunur.',
    unit: 'g',
    positive: true,
  );
}

// ---------------------------------------------------------------------------
// 17. İşçi ve havuz problemleri
// ---------------------------------------------------------------------------
/// (k, j): birlikte çalışılan gün sayısı kalan işi pozitif bırakır (j < k/2).
const _kjBirlikte = [
  (3, 1), (4, 1), (5, 1), (5, 2), (6, 1), (6, 2), (7, 1), (7, 2), (7, 3),
  (8, 1), (8, 2), (8, 3), (9, 1), (9, 2), (9, 3), (9, 4), (10, 1), (10, 2),
  (10, 3), (10, 4), //
];
const _kjSirayla = [
  (2, 1), (3, 1), (3, 2), (4, 1), (4, 2), (4, 3), (5, 1), (5, 2), (5, 3),
  (5, 4), (6, 1), (6, 2), (6, 3), (6, 4), (6, 5), (7, 1), (7, 2), (7, 3),
  (7, 4), (7, 5), //
];

/// (x, y, t): 1/x + 1/y = 1/t.
const _birlikteUclu = [
  (3, 6, 2), (6, 12, 4), (9, 18, 6), (12, 24, 8), (15, 30, 10), (18, 36, 12),
  (21, 42, 14), (24, 48, 16), (4, 12, 3), (8, 24, 6), (12, 36, 9),
  (16, 48, 12), (20, 60, 15), (10, 15, 6), (20, 30, 12), (30, 45, 18),
  (40, 60, 24), (5, 20, 4), (10, 40, 8), (15, 60, 12), (21, 28, 12),
  (6, 30, 5), (12, 60, 10), (14, 35, 10), (24, 40, 15), //
];

AdvancedItem _isciHavuz(int a, int b, int c) {
  final kk = c ~/ 3, sira = _sira(a, b, c);
  final (m, n) = _asalCift[a];
  const bir = _K._(1, 1);
  if (c % 3 == 0) {
    final (k, j) = _kjBirlikte[b];
    final x = m * k, y = n * k, d = m * j;
    final kalanGun = n * k - (m + n) * j;
    final biten = _K(d, x) + _K(d, y), kalan = bir - biten;
    final bas =
        'Bir işi usta tek başına $x günde, kalfa tek başına $y günde '
        'bitirebilmektedir. İkisi birlikte $d gün çalıştıktan sonra usta işten '
        'ayrılıyor.';
    final coz =
        'Usta günde işin 1/$x, kalfa 1/$y kadarını yapar. $d günde $d · '
        '(1/$x + 1/$y) = $biten kadarı biter.';
    if (kk == 0) {
      return _tamSirali(
        '$bas Kalan işi kalfa tek başına kaç günde bitirir?',
        kalanGun,
        [
          n * (k - j), // kalfanın yaptığı kısım düşülmemiş
          y - d, // ustanın yaptığı kısım düşülmemiş
          kalanGun + d,
          x - d,
          (m + n) * j, // biten kısmın süresi
          d,
        ],
        '$coz Kalan $kalan kadarlık işi kalfa $y · $kalan = $kalanGun günde '
            'bitirir.',
        sira,
        enAz: 1,
      );
    }
    if (kk == 1) {
      return _tamSirali(
        '$bas Kalan işi kalfa tek başına tamamladığına göre işin tamamı kaç '
            'günde bitmiştir?',
        d + kalanGun,
        [
          kalanGun, // birlikte çalışılan günler eklenmemiş
          n * (k - j) + d,
          y - d,
          y,
          x,
          (m + n) * j + d, // biten kısmın süresi eklenmiş
          d,
        ],
        '$coz Kalan $kalan kadarlık işi kalfa $y · $kalan = $kalanGun günde '
            'bitirir; iş toplam $d + $kalanGun = ${d + kalanGun} günde tamamlanır.',
        sira,
        enAz: 1,
      );
    }
    if (kk == 2) {
      return _kesirSirali(
        '$bas Usta ayrıldığı anda işin kaçta kaçı bitmiştir?',
        biten,
        [
          kalan, // biten yerine kalan
          _K(d, x), // yalnız ustanın yaptığı
          _K(d, y),
          _K(d, x + y), // günler toplanmış
          _K(2 * d, x + y), // paylar ve paydalar toplanmış
          bir - _K(d, y),
          bir - _K(d, x),
        ],
        coz,
        sira,
        pozitif: true,
        birdenKucuk: true,
      );
    }
    return _kesirSirali(
      '$bas Usta ayrıldığı anda işin kaçta kaçı kalmıştır?',
      kalan,
      [
        biten, // kalan yerine biten
        bir - _K(d, x), // yalnız ustanın yaptığı düşülmüş
        bir - _K(d, y),
        _K(d, x + y),
        bir - _K(2 * d, x + y), // paylar ve paydalar toplanmış
        _K(d, x),
        _K(d, y),
      ],
      '$coz Geriye 1 − $biten = $kalan kadarı kalır.',
      sira,
      pozitif: true,
      birdenKucuk: true,
    );
  }
  if (c % 3 == 1) {
    final (k, j) = _kjSirayla[b];
    final x = m * k, y = n * k;
    final bas =
        'Bir işi usta tek başına $x günde, kalfa tek başına $y günde '
        'bitirebilmektedir.';
    if (kk == 2) {
      final d = n * j, yanit = m * (k - j);
      final biten = _K(d, y), kalan = bir - biten;
      return _tamSirali(
        '$bas Kalfa bu işte tek başına $d gün çalıştıktan sonra işi ustaya '
            'devrediyor. Kalan işi usta tek başına kaç günde bitirir?',
        yanit,
        [
          n * (k - j), // kalan iş kalfanın hızıyla hesaplanmış
          if (x > d) x - d, // ustanın süresinden kalfanın günleri düşülmüş
          d,
          x, // kalfanın yaptığı düşülmemiş
          m * j, // biten kısmın usta süresi
          yanit + d, // toplam süre
        ],
        'Kalfa $d günde işin $d/$y = $biten kadarını yapar. Kalan $kalan '
            'kadarlık işi usta $x · $kalan = $yanit günde bitirir.',
        sira,
        enAz: 1,
      );
    }
    final d = m * j, kalanGun = n * (k - j);
    final biten = _K(d, x), kalan = bir - biten;
    final coz =
        'Usta $d günde işin $d/$x = $biten kadarını yapar. Kalan $kalan '
        'kadarlık işi kalfa $y · $kalan = $kalanGun günde bitirir';
    final devir =
        '$bas Usta bu işte tek başına $d gün çalıştıktan sonra işi kalfaya '
        'devrediyor.';
    if (kk == 0) {
      return _tamSirali(
        '$devir Kalan işi kalfa tek başına kaç günde bitirir?',
        kalanGun,
        [
          m * (k - j), // kalan iş ustanın hızıyla hesaplanmış
          y - d, // kalfanın süresinden ustanın günleri düşülmüş
          kalanGun + d, // toplam süre
          y, // ustanın yaptığı düşülmemiş
          n * j, // biten kısmın kalfa süresi
          d,
        ],
        '$coz.',
        sira,
        enAz: 1,
      );
    }
    return _tamSirali(
      '$devir Buna göre işin tamamı kaç günde bitmiş olur?',
      d + kalanGun,
      [
        kalanGun, // ustanın günleri eklenmemiş
        y - d,
        x,
        y,
        d + y, // kalfa işin tamamını yapmış sanılmış
        x + y, // iki süre toplanmış
        d + m * (k - j), // kalan iş ustanın hızıyla hesaplanmış
      ],
      '$coz; iş toplam $d + $kalanGun = ${d + kalanGun} günde tamamlanır.',
      sira,
      enAz: 1,
    );
  }
  if (kk == 1) {
    final (x, y, t) = _birlikteUclu[a];
    final adet = b + 2;
    return _tamSirali(
      'Bir duvarı usta tek başına $x saatte, kalfa tek başına $y saatte '
          'örebilmektedir. İkisi birlikte çalışarak aynı büyüklükteki $adet duvarı '
          'kaç saatte örer?',
      adet * t,
      [
        t, // tek duvarın süresi
        adet * (x + y) ~/ 2, // sürelerin ortalaması
        adet * x, // usta tek başına
        adet * (y - x),
        if ((adet * x).isEven) adet * x ~/ 2, // iki kişi ustanın hızında sanılmış
        if ((adet * y).isEven) adet * y ~/ 2, // iki kişi kalfanın hızında sanılmış
        (adet - 1) * t,
      ],
      'Birlikte bir saatte duvarın 1/$x + 1/$y = 1/$t kadarını örerler. Bir '
          'duvar $t saatte, $adet duvar $adet · $t = ${adet * t} saatte biter.',
      sira,
      enAz: 1,
    );
  }
  final k = 4 + b % 5, h = 1 + b ~/ 5;
  final x = m * k, y = n * k;
  final gx = _K(h, x), gy = _K(h, y);
  if (kk == 0) {
    return _kesirSirali(
      'Bir işi usta tek başına $x günde, kalfa tek başına $y günde '
          'bitirebilmektedir. İkisi birlikte $h gün çalıştığında işin kaçta kaçı '
          'bitmiş olur?',
      gx + gy,
      [
        gx, // yalnız ustanın yaptığı
        gy,
        _K(h, x + y), // günler toplanmış
        _K(2 * h, x + y), // paylar ve paydalar toplanmış
        bir - (gx + gy), // biten yerine kalan
        gx + gx, // ikisi de ustanın hızında sanılmış
      ],
      'Usta günde işin 1/$x, kalfa 1/$y kadarını yapar. $h günde $h · (1/$x + '
          '1/$y) = $gx + $gy = ${gx + gy} kadarı biter.',
      sira,
      pozitif: true,
      birdenKucuk: true,
    );
  }
  return _kesirSirali(
    'Boş bir havuzu bir musluk $x saatte doldurmakta, havuzun dibindeki bir '
        'gider ise dolu havuzu $y saatte boşaltmaktadır. Havuz tamamen boşken '
        'musluk ve gider aynı anda açılırsa $h saat sonra havuzun kaçta kaçı '
        'dolmuş olur?',
    gx - gy,
    [
      gx + gy, // gider de dolduruyor sanılmış
      gx, // gider hesaba katılmamış
      gy,
      _K(h, y - x), // süreler çıkarılmış
      bir - (gx - gy), // dolan yerine boş kalan kısım
      if (h > 1) _K(1, x) - _K(1, y), // bir saatlik değişim
    ],
    'Musluk saatte havuzun 1/$x kadarını doldurur, gider 1/$y kadarını '
        'boşaltır. Başlangıçta boş olan havuzun $h saatte $h · (1/$x − 1/$y) = '
        '$gx − $gy = ${gx - gy} kadarı dolar.',
    sira,
    pozitif: true,
    birdenKucuk: true,
  );
}

// ---------------------------------------------------------------------------
// 18. Hareket problemleri
// ---------------------------------------------------------------------------
AdvancedItem _hareket(int a, int b, int c) {
  final kk = c ~/ 3;
  if (c % 3 == 0) {
    final v1 = 50 + 2 * a, v2 = 40 + 3 * b, t = kk + 2, d = (v1 + v2) * t;
    final bas =
        'Aralarında $d km uzaklık bulunan A ve B kentlerinden aynı anda '
        'birbirine doğru yola çıkan iki araçtan A kentinden çıkanın hızı saatte '
        '$v1 km, B kentinden çıkanın hızı saatte $v2 km olup hızlar sabittir.';
    final coz =
        'Araçlar birbirine saatte $v1 + $v2 = ${v1 + v2} km yaklaşır; '
        'karşılaşma süresi $d / ${v1 + v2} = $t saat olur.';
    if ((a + b).isEven) {
      return sayisal(
        '$bas Bu iki araç kaç saat sonra karşılaşır?',
        t,
        [d ~/ v1, d ~/ v2, 2 * t, t + 1],
        coz,
        unit: 'saat',
        positive: true,
      );
    }
    return sayisal(
      '$bas İki araç karşılaştığında A kentinden çıkan araç kaç km yol almış '
          'olur?',
      v1 * t,
      [v2 * t, d ~/ 2, v1 * (t + 1), d - v1],
      '$coz A kentinden çıkan araç bu sürede $v1 · $t = ${v1 * t} km yol alır.',
      unit: 'km',
      positive: true,
    );
  }
  if (c % 3 == 1) {
    final v2 = 45 + 2 * a, dv = 5 * (1 + b % 5) + 2 * kk;
    final v1 = v2 + dv, t = 2 + b ~/ 5, d = dv * t;
    final bas =
        'Aynı yolda aynı yöne doğru sabit hızlarla ilerleyen iki araçtan '
        'öndekinin hızı saatte $v2 km, arkadakinin hızı saatte $v1 km olarak '
        'veriliyor. Aralarındaki uzaklığın $d km olduğu andan başlayarak '
        'arkadaki araç';
    final coz =
        'Arkadaki araç öndekine saatte $v1 − $v2 = $dv km yaklaşır; yetişme '
        'süresi $d / $dv = $t saat olur.';
    if ((a + b).isEven) {
      return sayisal(
        '$bas öndekine kaç saat sonra yetişir?',
        t,
        [t + 1, 2 * t, t + 2, t + 3],
        coz,
        unit: 'saat',
        positive: true,
      );
    }
    return sayisal(
      '$bas, öndekine yetişene kadar kaç km yol alır?',
      v1 * t,
      [v2 * t, v1 * t + d, d, (v1 + v2) * t],
      '$coz Arkadaki araç bu sürede $v1 · $t = ${v1 * t} km yol alır.',
      unit: 'km',
      positive: true,
    );
  }
  // Hız oranı m : n ve bu oranın birim hızı s; bisiklet hızları dakikada
  // 150–360 metre (9–21,6 km/sa), yol en çok 16,5 km, tek yön en çok 66 dakika.
  final (m, n) = const [(2, 3), (3, 4), (4, 5), (5, 6), (3, 5)][a % 5];
  final s = const [
    [80, 90, 100, 110, 120],
    [50, 60, 70, 80, 90],
    [40, 45, 50, 55, 60],
    [30, 35, 40, 45, 50],
    [50, 55, 60, 65, 70],
  ][a % 5][a ~/ 5];
  final k = 2 + b % 10, hizliGidis = b < 10;
  final vg = s * (hizliGidis ? n : m), vd = s * (hizliGidis ? m : n);
  final yol = s * m * n * k, tg = yol ~/ vg, td = yol ~/ vd, top = tg + td;
  if (kk == 0) {
    return sayisal(
      'Bir bisikletli evinden göl kıyısına dakikada $vg metre hızla gidiyor ve '
          'hiç beklemeden aynı yoldan dakikada $vd metre hızla geri dönüyor. Gidiş '
          've dönüş toplam $top dakika sürdüğüne göre ev ile göl kıyısı arasındaki '
          'yol kaç metredir?',
      yol,
      [(vg + vd) * top ~/ 4, vg * top ~/ 2, vd * top ~/ 2, 2 * yol],
      'Yol x metre ise x/$vg + x/$vd = $top olmalıdır. Buradan x = $yol '
          'bulunur; gidiş $tg, dönüş $td dakika sürer.',
      positive: true,
    );
  }
  if (kk == 1) {
    return sayisal(
      'Bir bisikletli evinden $yol metre uzaklıktaki göl kıyısına dakikada $vg '
          'metre hızla gidiyor ve hiç beklemeden aynı yoldan dakikada $vd metre '
          'hızla geri dönüyor. Gidiş ve dönüş toplam kaç dakika sürer?',
      top,
      [4 * yol ~/ (vg + vd), tg, td, 2 * tg, 2 * td],
      'Gidiş $yol / $vg = $tg dakika, dönüş $yol / $vd = $td dakika sürer. '
          'Toplam süre $tg + $td = $top dakika olur.',
      positive: true,
    );
  }
  return sayisal(
    'Bir bisikletli evinden $yol metre uzaklıktaki göl kıyısına dakikada $vg '
        'metre hızla gidiyor ve hiç beklemeden aynı yoldan sabit hızla geri '
        'dönüyor. Gidiş ve dönüş toplam $top dakika sürdüğüne göre bisikletlinin '
        'dönüş hızı dakikada kaç metredir?',
    vd,
    [yol ~/ top, 2 * yol ~/ top, vg, yol ~/ tg + yol ~/ top],
    'Gidiş $yol / $vg = $tg dakika sürer; dönüşe $top − $tg = $td dakika '
        'kalır. Dönüş hızı $yol / $td = $vd metre/dakika olur.',
    positive: true,
  );
}

// ---------------------------------------------------------------------------
// 19. Yaş problemleri
// ---------------------------------------------------------------------------
/// (kızın yaşı, kat): annenin yaşı 24–54 aralığında kalır.
const _anneKiz = [
  (18, 2), (20, 2), (22, 2), (24, 2), (26, 2), (9, 3), (10, 3), (12, 3),
  (14, 3), (15, 3), (16, 3), (18, 3), (6, 4), (7, 4), (8, 4), (9, 4), (11, 4),
  (13, 4), (5, 5), (6, 5), (7, 5), (9, 5), (4, 6), (5, 6), (7, 6), //
];

/// (çocukların o günkü yaşları toplamı, kat).
const _babaCocuk = [
  (14, 2), (16, 2), (18, 2), (20, 2), (22, 2), (24, 2), (8, 3), (9, 3),
  (10, 3), (11, 3), (12, 3), (13, 3), (14, 3), (15, 3), (6, 4), (7, 4), (8, 4),
  (9, 4), (10, 4), (11, 4), (5, 5), (6, 5), (7, 5), (8, 5), (9, 5), //
];

AdvancedItem _yas(int a, int b, int c) {
  final kk = c ~/ 2, n = b + 1;
  if (c.isEven) {
    final (y, k) = _anneKiz[a];
    final anne = k * y, s = anne + y + 2 * n;
    final (soru, yanit, yanlis) = switch (kk) {
      0 => ('anne bugün kaç yaşındadır?', anne, [y, anne + n, s - 2 * n]),
      1 => (
        'kızı bugün kaç yaşındadır?',
        y,
        [(s - n) ~/ (k + 1), s ~/ (k + 1), y + n, anne],
      ),
      2 => (
        '$n yıl sonra anne kaç yaşında olur?',
        anne + n,
        [anne, k * (y + n), y + n, anne + 2 * n],
      ),
      3 => (
        'anne ile kızının yaşları farkı kaçtır?',
        anne - y,
        [anne, y, anne - y + n, anne + y],
      ),
      _ => (
        'ikisinin bugünkü yaşları toplamı kaçtır?',
        anne + y,
        [s - n, s, anne, anne - y],
      ),
    };
    return sayisal(
      'Bir annenin bugünkü yaşı, kızının bugünkü yaşının $k katıdır. $n yıl '
          'sonra ikisinin yaşları toplamı $s olacağına göre $soru',
      yanit,
      yanlis,
      'Kızın bugünkü yaşı x ise annenin yaşı ${k}x olur. $n yıl sonra toplam '
          '${k + 1}x + ${2 * n} = $s olduğundan x = $y bulunur; anne $anne '
          'yaşındadır. İstenen değer $yanit olur.',
      positive: true,
    );
  }
  final (x, k) = _babaCocuk[a];
  final baba = k * x, s = baba + x + 3 * n;
  final (soru, yanit, yanlis) = switch (kk) {
    0 => (
      'baba bugün kaç yaşındadır?',
      baba + n,
      [baba, x + 2 * n, baba + 2 * n],
    ),
    1 => (
      'iki çocuğun bugünkü yaşları toplamı kaçtır?',
      x + 2 * n,
      [x, x + n, baba + n, s ~/ (k + 1)],
    ),
    2 => ('$n yıl önce baba kaç yaşındaydı?', baba, [baba + n, x, baba - n]),
    3 => (
      '$n yıl önce iki çocuğun yaşları toplamı kaçtı?',
      x,
      [x + 2 * n, x + n, s ~/ (k + 1), baba],
    ),
    _ => (
      '$n yıl sonra baba kaç yaşında olur?',
      baba + 2 * n,
      [baba + n, baba, x + 3 * n, baba + 3 * n],
    ),
  };
  return sayisal(
    'Bir baba ile iki çocuğunun bugünkü yaşları toplamı $s olarak veriliyor. '
        '$n yıl önce babanın yaşı, iki çocuğunun yaşları toplamının $k katı '
        'olduğuna göre $soru',
    yanit,
    yanlis,
    '$n yıl önce çocukların yaşları toplamı x ise babanın yaşı ${k}x idi. '
        'Üç kişi için bugünkü toplam ${k + 1}x + ${3 * n} = $s olduğundan x = $x '
        'bulunur. O gün baba $baba yaşındaydı; istenen değer $yanit olur.',
    positive: true,
  );
}

// ---------------------------------------------------------------------------
// 20. Sayı ve kesir problemleri
// ---------------------------------------------------------------------------
const _kesirCift = [
  (1, 2, 1, 3), (1, 2, 1, 4), (1, 2, 1, 5), (1, 3, 1, 4), (1, 3, 1, 5),
  (1, 4, 1, 5), (2, 3, 1, 2), (2, 3, 1, 4), (2, 3, 1, 5), (3, 4, 1, 2),
  (3, 4, 1, 3), (3, 4, 2, 3), (3, 4, 1, 5), (2, 5, 1, 3), (2, 5, 1, 4),
  (3, 5, 1, 2), (3, 5, 1, 3), (3, 5, 1, 4), (4, 5, 1, 2), (4, 5, 2, 3),
  (4, 5, 3, 4), (4, 5, 1, 3), (5, 6, 1, 2), (5, 6, 2, 3), (5, 6, 3, 4), //
];

AdvancedItem _sayiProblemi(int a, int b, int c) {
  final kk = c ~/ 3;
  if (c % 3 == 0) {
    final x0 = 3 + a + 25 * b;
    final (adet, tur) = const [(3, 0), (5, 0), (4, 2), (3, 1)][kk];
    final adim = tur == 0 ? 1 : 2;
    final ilk = tur == 0 ? x0 : (tur == 1 ? 2 * x0 + 1 : 2 * x0);
    final son = ilk + adim * (adet - 1);
    final toplam = adet * (ilk + son) ~/ 2;
    final ad = const ['ardışık', 'ardışık tek', 'ardışık çift'][tur];
    final buyuk = (a + b).isEven;
    final sabit = adim * adet * (adet - 1) ~/ 2;
    return sayisal(
      'Toplamları $toplam olan $adet $ad doğal sayıdan en '
          '${buyuk ? 'büyüğü' : 'küçüğü'} kaçtır?',
      buyuk ? son : ilk,
      [
        buyuk ? ilk : son,
        toplam ~/ adet,
        (buyuk ? son : ilk) + adim,
        ilk + adim,
      ],
      'En küçük sayı x ise sayılar x, x + $adim, … biçimindedir ve toplamları '
          '${adet}x + $sabit = $toplam olur. Buradan x = $ilk bulunur; en büyük '
          'sayı $son olur.',
      positive: true,
    );
  }
  if (c % 3 == 1) {
    final (p1, q1, p2, q2) = _kesirCift[a];
    final f1 = _K(p1, q1), f2 = _K(p2, q2);
    if (kk == 2) {
      final para = q1 * q2 * 5 * (b + 1);
      final ilkKalan = para * (q1 - p1) ~/ q1;
      final kalan = ilkKalan * (q2 - p2) ~/ q2;
      final naif = q1 * q2 - p1 * q2 - p2 * q1; // kesirleri doğrudan toplama
      return sayisal(
        'Bir öğrenci parasının $f1 kadarını kitaba, kalan parasının $f2 '
            'kadarını kırtasiyeye harcıyor. Geriye $kalan TL kaldığına göre '
            'öğrencinin başlangıçta kaç TL parası vardı?',
        para,
        [
          if (naif > 0) kalan * q1 * q2 ~/ naif,
          ilkKalan,
          kalan * q2 ~/ (q2 - p2) + kalan,
          kalan * q1 ~/ (q1 - p1),
        ],
        'Para x TL olsun. Kitaptan sonra x · ${_K(q1 - p1, q1)} kalır; '
            'kırtasiyeden sonra bunun ${_K(q2 - p2, q2)} kadarı, yani x · '
            '${_K(q1 - p1, q1) * _K(q2 - p2, q2)} kalır. Bu değer $kalan olduğundan '
            'x = $para bulunur.',
        unit: 'TL',
        positive: true,
      );
    }
    final x = q1 * q2 ~/ q1.gcd(q2) * (b + 1);
    final oran = kk == 0 ? f1 + f2 : f1 - f2;
    final t = x * oran.n ~/ oran.d;
    return sayisal(
      kk == 0
          ? 'Bir sayının $f1 kadarı ile $f2 kadarının toplamı $t olduğuna göre '
                'bu sayı kaçtır?'
          : 'Bir sayının $f1 kadarı, aynı sayının $f2 kadarından $t fazla '
                'olduğuna göre bu sayı kaçtır?',
      x,
      [t, t * q1 ~/ p1, t * q2 ~/ p2, t * (q1 + q2) ~/ (p1 + p2), t * oran.n],
      'Sayı x olsun. x · $f1 ${kk == 0 ? '+' : '−'} x · $f2 = x · $oran = $t '
      'eşitliğinden x = $x bulunur.',
      positive: true,
    );
  }
  if (kk == 2) {
    final k = 2 + b % 4, r = 1 + b ~/ 4, kucuk = 6 + a;
    final buyuk = k * kucuk + r, s = buyuk + kucuk;
    return sayisal(
      'Toplamları $s olan iki sayıdan büyüğü, küçüğünün $k katından $r '
          'fazladır. Buna göre büyük sayı kaçtır?',
      buyuk,
      [kucuk, k * kucuk, s - r, s ~/ (k + 1) * k],
      'Küçük sayı x ise büyük sayı ${k}x + $r olur. ${k + 1}x + $r = $s '
          'eşitliğinden x = $kucuk ve büyük sayı $k · $kucuk + $r = $buyuk '
          'bulunur.',
      positive: true,
    );
  }
  final kucuk = 11 + 3 * a, fark = 4 + 5 * b;
  final buyuk = kucuk + fark, s = buyuk + kucuk;
  return sayisal(
    'Toplamları $s, farkları $fark olan iki sayıdan '
        '${kk == 0 ? 'büyük' : 'küçük'} olanı kaçtır?',
    kk == 0 ? buyuk : kucuk,
    [kk == 0 ? kucuk : buyuk, s - fark, s ~/ 2, s + fark],
    'Büyük sayı ($s + $fark) / 2 = $buyuk, küçük sayı ($s − $fark) / 2 = '
        '$kucuk olur.',
    positive: true,
  );
}

final lmMatTemel = <AdvancedFamily>[
  _mt(
    'basamak',
    'Basamak değeri: rakamların yer değiştirmesi',
    Difficulty.hard,
    BloomLevel.analiz,
    _basamak,
  ),
  _mt(
    'bolunebilme',
    'Bölünebilme kurallarıyla bilinmeyen rakam',
    Difficulty.medium,
    BloomLevel.uygulama,
    _bolunebilme,
  ),
  _mt(
    'ebob_ekok',
    'EBOB ve EKOK: sayılar ve günlük problemler',
    Difficulty.medium,
    BloomLevel.uygulama,
    _ebobEkok,
  ),
  _mt(
    'bolme',
    'Bölme işleminde bölünen, bölen, bölüm ve kalan',
    Difficulty.medium,
    BloomLevel.uygulama,
    _bolme,
  ),
  _mt(
    'rasyonel',
    'Rasyonel sayılarla işlem önceliği',
    Difficulty.easy,
    BloomLevel.uygulama,
    _rasyonel,
  ),
  _mt(
    'ondalik',
    'Devirli ve sonlu ondalık sayılarla işlemler',
    Difficulty.medium,
    BloomLevel.anlama,
    _ondalik,
  ),
  _mt(
    'uslu',
    'Üslü ifadeler: üs kuralları ve üslü denklem',
    Difficulty.medium,
    BloomLevel.uygulama,
    _uslu,
  ),
  _mt(
    'koklu',
    'Köklü ifadeler: sadeleştirme ve paydayı rasyonel yapma',
    Difficulty.medium,
    BloomLevel.uygulama,
    _koklu,
  ),
  _mt(
    'mutlak',
    'Mutlak değerli denklem ve eşitsizlikler',
    Difficulty.medium,
    BloomLevel.uygulama,
    _mutlak,
  ),
  _mt(
    'denklem',
    'Birinci dereceden denklemler: parantezli ve kesirli',
    Difficulty.easy,
    BloomLevel.uygulama,
    _denklem,
  ),
  _mt(
    'esitsizlik',
    'Birinci dereceden eşitsizlikler ve tam sayı çözümleri',
    Difficulty.medium,
    BloomLevel.uygulama,
    _esitsizlik,
  ),
  _mt(
    'denklem_sistemi',
    'İki bilinmeyenli doğrusal denklem sistemleri',
    Difficulty.medium,
    BloomLevel.uygulama,
    _sistem,
  ),
  _mt(
    'oran',
    'Oran ve orantı: doğru, ters ve orantılı paylaşım',
    Difficulty.easy,
    BloomLevel.anlama,
    _oran,
  ),
  _mt(
    'yuzde',
    'Yüzde problemleri: ardışık değişim ve yüzde oranı',
    Difficulty.medium,
    BloomLevel.uygulama,
    _yuzde,
  ),
  _mt(
    'kar_zarar',
    'Kâr-zarar: maliyet, etiket ve satış fiyatı',
    Difficulty.medium,
    BloomLevel.analiz,
    _karZarar,
  ),
  _mt(
    'karisim',
    'Karışım problemleri: birleştirme, su ekleme, buharlaştırma',
    Difficulty.medium,
    BloomLevel.analiz,
    _karisim,
  ),
  _mt(
    'isci_havuz',
    'İşçi ve havuz problemleri: birlikte ve sırayla çalışma',
    Difficulty.hard,
    BloomLevel.analiz,
    _isciHavuz,
  ),
  _mt(
    'hareket',
    'Hareket problemleri: karşılaşma, yetişme, gidiş-dönüş',
    Difficulty.medium,
    BloomLevel.analiz,
    _hareket,
  ),
  _mt('yas', 'Yaş problemleri', Difficulty.medium, BloomLevel.uygulama, _yas),
  _mt(
    'sayi_problemleri',
    'Sayı ve kesir problemleri',
    Difficulty.easy,
    BloomLevel.uygulama,
    _sayiProblemi,
  ),
];
