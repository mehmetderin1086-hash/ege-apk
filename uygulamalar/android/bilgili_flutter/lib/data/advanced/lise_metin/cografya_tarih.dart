// Lise coğrafya (12 hesap ailesi) ve tarih (8 olgu ailesi) metin soruları.
// Coğrafya aileleri sayısal koordinatlarla, tarih aileleri olgu çizelgelerinden
// seçilen üçlülerle üretilir; her aile 5.000 ayrı kök verir.
import 'denge.dart';
import 'ortak.dart';

// ───────────────────────── Ortak küçük yardımcılar ─────────────────────────

/// lmAile koordinatlarından vaka numarası (hedef sıra seçimi için).
int _vaka(int a, int b, int c) => a + 25 * b + 500 * c;

/// Uç sıralara ağırlık veren hedef sıra (0 ve 3: 5/16, 1 ve 2: 3/16). Anahtarı
/// yalnız ortada kalabilen bir biçimle aynı ailede bulunan biçimlerde, ailenin
/// sıra dağılımını dengelemek için kullanılır.
int _ucaYakinSira(int i) {
  final s = hedefSira(i);
  if ((s == 1 || s == 2) && hedefSira(i, 7) == 0) return s == 1 ? 0 : 3;
  return s;
}

/// Anahtarın değer sırasını [sira] yapan çeldiriciler; `siraliCeldiriciler`
/// ile seçilir. Önce [tipik] hatalar, sonra (verilmişse) anahtarın iki yanında
/// birer [yakin] komşu değer denenir; bir yanda bunlar da yetmezse eksik
/// çeldirici öbür yandaki tipik hatalardan gelir (sıra kayar). Daha uzak [uzak]
/// komşular yalnız tipik hatalardan üç ayrı çeldirici çıkmadığında eklenir.
/// Böylece hiçbir hataya karşılık gelmeyen değerler en çok bir kez görünür.
List<String> _tipikSirali(
  num anahtar,
  String yazim,
  List<(num, String)> tipik,
  List<(num, String)> yakin,
  List<(num, String)> uzak,
  int sira,
) {
  final ayri = <String>[];
  for (final (_, y) in tipik) {
    if (!ayniSecenek(y, yazim) && !ayri.any((w) => ayniSecenek(w, y))) {
      ayri.add(y);
    }
  }
  return siraliCeldiriciler(anahtar, yazim, [
    ...tipik,
    ...yakin,
    if (ayri.length < 3) ...uzak,
  ], sira);
}

/// Pozitif tam sayı yanıtlı soru; çeldiriciler [_tipikSirali] ile seçilir.
/// [komsu] doğruysa anahtarın bir adım altı ve üstü son çare olarak kullanılır.
AdvancedItem _sayisalTipik(
  String prompt,
  int answer,
  Iterable<int> alternatives,
  String explanation,
  int sira, {
  String unit = '',
  bool komsu = false,
}) {
  final step = answer.abs() >= 200 ? 10 : (answer.abs() >= 40 ? 5 : 1);
  final yazim = birimli('$answer', unit);
  (int, String) aday(int x) => (x, birimli('$x', unit));
  List<(int, String)> komsular(int k) => [
    aday(answer + k * step),
    if (answer - k * step > 0) aday(answer - k * step),
  ];
  return AdvancedItem(
    prompt,
    yazim,
    _tipikSirali(
      answer,
      yazim,
      [
        for (final x in alternatives)
          if (x > 0) aday(x),
      ],
      komsu ? komsular(1) : const [],
      [for (var k = 1; k <= 6; k++) ...komsular(k)],
      sira,
    ),
    explanation,
  );
}

/// Pozitif ondalıklı yanıtlı soru; değerler [digits] basamakla yazılır, sıra
/// yazılan değere göre bulunur ve çeldiriciler [_tipikSirali] ile seçilir.
/// [komsu] doğruysa anahtarın bir adım altı ve üstü son çare olarak kullanılır.
/// [digits] basamakla tam yazılamayan (yuvarlanması gereken) tipik hata değerleri
/// kullanılmaz: tam anahtarın yanında "1,667 km" gibi yuvarlanmış bir değer göze batar.
AdvancedItem _ondalikliTipik(
  String prompt,
  double answer,
  Iterable<double> alternatives,
  String explanation,
  int sira, {
  String unit = '',
  int digits = 2,
  bool komsu = false,
}) {
  final step = answer.abs() >= 20 ? 1.0 : (answer.abs() >= 2 ? 0.5 : 0.1);
  double yuvarla(double x) =>
      double.parse(tr(x, digits).replaceFirst(',', '.'));
  var olcek = 1.0;
  for (var k = 0; k < digits; k++) {
    olcek *= 10;
  }
  bool tam(double x) => (x * olcek - (x * olcek).round()).abs() < 1e-6;
  (double, String) aday(double x) => (yuvarla(x), birimli(tr(x, digits), unit));
  List<(double, String)> komsular(int k) => [
    aday(answer + k * step),
    if (yuvarla(answer - k * step) > 0) aday(answer - k * step),
  ];
  final yazim = birimli(tr(answer, digits), unit);
  return AdvancedItem(
    prompt,
    yazim,
    _tipikSirali(
      yuvarla(answer),
      yazim,
      [
        for (final x in alternatives)
          if (x.isFinite && yuvarla(x) > 0 && tam(x)) aday(x),
      ],
      komsu ? komsular(1) : const [],
      [for (var k = 1; k <= 6; k++) ...komsular(k)],
      sira,
    ),
    explanation,
  );
}

/// Dakikayı 24 saatlik gösterime çevirir: 574 → 09:34.
String _saat(int dk) =>
    '${(dk ~/ 60).toString().padLeft(2, '0')}:${(dk % 60).toString().padLeft(2, '0')}';

/// Dakikayı "2 saat 24 dakika" biçiminde yazar.
String _sure(int dk) {
  final h = dk ~/ 60, m = dk % 60;
  if (h == 0) return '$m dakika';
  if (m == 0) return '$h saat';
  return '$h saat $m dakika';
}

/// İşaretli boylamı (doğu artı) yazar: 37 → 37° Doğu, −12 → 12° Batı.
String _boylam(int x) => '${x.abs()}° ${x >= 0 ? 'Doğu' : 'Batı'}';

/// Sayıyı gerçek eksi işaretiyle yazar.
String _n(num x, [int digits = 2]) => tr(x, digits).replaceFirst('-', '−');

String _derece(num x) => '${_n(x)} °C';

// ───────────────────────────── Coğrafya aileleri ────────────────────────────

AdvancedItem _yerelSaat(int a, int b, int c) {
  final k = c ~/ 2;
  final sira = hedefSira(_vaka(a, b, c));
  if (c.isEven) {
    // Yerel saat: K ve L boylamları (doğu artı), saati verilen ve sorulan merkez.
    final (lonK, lonL, kVerilir, taban) = switch (k) {
      0 => (8 + a, 36 + 2 * b, true, 9 * 60 + 10),
      1 => (-(8 + a), -(36 + 2 * b), true, 14 * 60 + 30),
      2 => (-(8 + a), 5 + 2 * b, true, 8 * 60 + 40),
      3 => (8 + a, -(5 + 2 * b), true, 15 * 60 + 20),
      _ => (40 + a, 70 + 3 * b, false, 17 * 60 + 30),
    };
    final t = taban + 10 * ((a + b) % 5);
    final verilen = kVerilir ? 'K' : 'L', sorulan = kVerilir ? 'L' : 'K';
    final lonV = kVerilir ? lonK : lonL, lonS = kVerilir ? lonL : lonK;
    final ayni = (lonK > 0) == (lonL > 0);
    final fark = (lonS - lonV).abs();
    final diger = ayni
        ? lonK.abs() + lonL.abs()
        : (lonK.abs() - lonL.abs()).abs();
    final yon = lonS > lonV ? 1 : -1;
    final dogru = t + yon * 4 * fark;
    // Tipik hatalar anahtarın iki yanından seçilir; anahtarın saat sırasındaki
    // yeri vakadan vakaya değişir: ters yön, 4 ile çarpmayı unutma, boylam farkını
    // yanlış alma, sorulan merkezin boylamını fark sanma, 4 yerine 15 ile çarpma,
    // bunların ters yönlü biçimleri ve en sonda bir saatlik ya da yarım saatlik kayma.
    final adaylar = [
      t - yon * 4 * fark,
      t + yon * fark,
      t + yon * 4 * diger,
      t + yon * 4 * lonS.abs(),
      t + yon * 15 * fark,
      t - yon * fark,
      t - yon * 4 * diger,
      dogru + 60,
      dogru - 60,
      dogru + 30,
      dogru - 30,
    ].where((x) => x >= 0 && x < 1440 && x != t);
    final buyuk = lonK.abs() > lonL.abs() ? lonK.abs() : lonL.abs();
    final kucuk = lonK.abs() > lonL.abs() ? lonL.abs() : lonK.abs();
    final farkYazi = ayni
        ? 'Merkezler aynı yarım kürede olduğundan boylam farkı $buyuk − $kucuk = $fark° olur'
        : 'Merkezler başlangıç meridyeninin farklı yanlarında olduğundan boylam farkı '
              '${lonK.abs()} + ${lonL.abs()} = $fark° olur';
    return AdvancedItem(
      'K merkezi ${_boylam(lonK)}, L merkezi ${_boylam(lonL)} boylamı üzerindedir. '
          'Bir boylam derecesi 4 dakikalık yerel saat farkı oluşturmaktadır. '
          '$verilen merkezinde yerel saat ${_saat(t)} iken $sorulan merkezinde yerel saat kaçtır?',
      _saat(dogru),
      siraliCeldiriciler(dogru, _saat(dogru), [
        for (final x in adaylar) (x, _saat(x)),
      ], sira),
      '$farkYazi; zaman farkı $fark × 4 = ${4 * fark} dakikadır (${_sure(4 * fark)}). '
          '$sorulan merkezi daha ${yon > 0 ? 'doğuda' : 'batıda'} olduğundan yerel saati '
          '${yon > 0 ? 'ileridir' : 'geridir'}: ${_saat(t)} ${yon > 0 ? '+' : '−'} ${_sure(4 * fark)} = ${_saat(dogru)}.',
    );
  }
  // Zaman farkı (dakika).
  final (lonK, lonL) = switch (k) {
    0 => (4 + a, 30 + 2 * b),
    1 => (-(4 + a), -(30 + 2 * b)),
    2 => (-(4 + a), 3 + 2 * b),
    3 => (4 + a, -(3 + 2 * b)),
    _ => (31 + a, 60 + 3 * b),
  };
  final ayni = (lonK > 0) == (lonL > 0);
  final fark = (lonK - lonL).abs();
  final diger = ayni
      ? lonK.abs() + lonL.abs()
      : (lonK.abs() - lonL.abs()).abs();
  final buyuk = lonK.abs() > lonL.abs() ? lonK.abs() : lonL.abs();
  final kucuk = lonK.abs() > lonL.abs() ? lonL.abs() : lonK.abs();
  return _sayisalTipik(
    'K merkezi ${_boylam(lonK)}, L merkezi ${_boylam(lonL)} boylamındadır. '
    'Ardışık iki boylam arasında 4 dakikalık yerel saat farkı bulunduğuna göre '
    'bu iki merkezin yerel saatleri arasındaki fark kaç dakikadır?',
    4 * fark,
    // Tipik hatalar: boylam farkını yanlış alma, 4 ile çarpmayı unutma, 4 yerine
    // 15 ile çarpma, iki merkez arasındaki boylam sayısını fark sanma (bir eksik ya da
    // bir fazla), "ardışık iki boylam" ifadesini iki derecede 4 dakika sanma.
    [
      4 * diger,
      fark,
      15 * fark,
      4 * (fark + 1),
      4 * (fark - 1),
      2 * fark,
      4 * (fark + 2),
      4 * (fark - 2),
    ],
    ayni
        ? 'İki merkez aynı yarım kürede olduğundan boylam farkı $buyuk − $kucuk = $fark° olur. '
              'Yerel saat farkı $fark × 4 = ${4 * fark} dakikadır.'
        : 'İki merkez başlangıç meridyeninin farklı yanlarında olduğundan boylam farkı '
              '${lonK.abs()} + ${lonL.abs()} = $fark° olur. Yerel saat farkı $fark × 4 = ${4 * fark} dakikadır.',
    sira,
    unit: 'dakika',
  );
}

AdvancedItem _boylamBul(int a, int b, int c) {
  final cfg = c % 5, yari = c ~/ 5;
  // (K boylamı, derece farkı, L ileride mi, K merkezindeki saat)
  final (lonK, d, ileri, tK) = switch (cfg) {
    0 => (10 + a, 3 + b, true, yari == 0 ? 9 * 60 + 20 : 13 * 60 + 45),
    1 => (30 + a, 3 + b, false, yari == 0 ? 11 * 60 + 30 : 16 * 60 + 10),
    2 => (10 + a, 36 + b, false, yari == 0 ? 12 * 60 + 50 : 17 * 60 + 25),
    3 => (-(10 + a), 36 + b, true, yari == 0 ? 7 * 60 + 15 : 10 * 60 + 40),
    _ => (-(10 + a), 3 + b, false, yari == 0 ? 14 * 60 + 5 : 8 * 60 + 55),
  };
  final s = ileri ? 1 : -1;
  final tL = tK + s * 4 * d;
  final lonL = lonK + s * d;
  String ad(int x) => '${_boylam(x)} boylamı';
  // Çeldiriciler 2 × 2 düzenindedir: doğru derece öbür yarım kürede (yönü
  // karıştırma) ve tipik bir hatadan gelen derece iki yarım kürede de verilir.
  // Böylece her derece ve her yön ikişer seçenekte görünür; ne sözcük benzerliği
  // ne yön çoğunluğu anahtarı gösterir. Hatalı derecenin doğru dereceden büyük ya
  // da küçük olması vakadan vakaya değişir.
  final dogru = lonL.abs();
  bool gecerli(int x) => x > 0 && x < 180 && x != dogru;
  final tipik = [
    (lonK - s * d).abs(), // gidiş yönünü ters alma
    d, // yalnız boylam farkını yanıt sanma
    (lonK + s * 4 * d).abs(), // dakika farkını derece farkı sanma
  ].where(gecerli).toList();
  final kucukIste = hedefSira(_vaka(a, b, c)) != 0;
  final m = tipik.isEmpty
      ? [dogru + 10, dogru + 15, dogru - 10].firstWhere(gecerli)
      : tipik.firstWhere(
          (x) => (x < dogru) == kucukIste,
          orElse: () => tipik.first,
        );
  final String yer;
  if ((lonL > 0) != (lonK > 0)) {
    yer =
        'K merkezinden $d° ${ileri ? 'doğuya' : 'batıya'} gidilirken başlangıç meridyeni '
        'geçilir: $d − ${lonK.abs()} = ${lonL.abs()}';
  } else if (lonL.abs() > lonK.abs()) {
    yer = '${lonK.abs()} + $d = ${lonL.abs()}';
  } else {
    yer = '${lonK.abs()} − $d = ${lonL.abs()}';
  }
  final once = ileri ? tK : tL, sonra = ileri ? tL : tK;
  return secenekli(
    'K merkezi ${ad(lonK)} üzerindedir. K merkezinde yerel saat ${_saat(tK)} iken aynı anda '
        'L merkezinde yerel saat ${_saat(tL)} olarak belirlenmiştir. Her boylam derecesi '
        '4 dakikalık yerel saat farkı oluşturduğuna göre L merkezi hangi boylam üzerindedir?',
    ad(lonL),
    [ad(-lonL), ad(m), ad(-m)],
    'Yerel saat farkı ${_saat(sonra)} − ${_saat(once)} = ${4 * d} dakikadır; ${4 * d} / 4 = $d° '
        'boylam farkı eder. L merkezinin yerel saati ${ileri ? 'ileri' : 'geri'} olduğundan L, '
        'K merkezinin ${ileri ? 'doğusundadır' : 'batısındadır'}. $yer; yanıt ${ad(lonL)} olur.',
  );
}

const _uzaklikBaglam = [
  'iki kent merkezi arasındaki kuş uçuşu uzaklık',
  'iki liman arasındaki kuş uçuşu uzaklık',
  'iki baraj arasındaki kuş uçuşu uzaklık',
  'iki havalimanı arasındaki kuş uçuşu uzaklık',
  'iki deniz feneri arasındaki kuş uçuşu uzaklık',
];

AdvancedItem _olcekUzunluk(int a, int b, int c) {
  final k = c ~/ 2;
  final payda = 20000 * (6 + a); // 1/120000 … 1/600000
  final s = (6 + a) / 5; // 1 cm kaç km
  final baglam = sec(_uzaklikBaglam, a + b + k);
  final sira = hedefSira(_vaka(a, b, c));
  if (c.isEven) {
    final cm10 = 20 + b + 20 * k; // 2,0 … 11,9 cm
    final km = cm10 * (6 + a) * 2 / 100;
    final ters = cm10 / 10 / s;
    return _ondalikliTipik(
      '1/$payda ölçekli bir haritada $baglam ${tr(cm10 / 10)} cm olarak ölçülmüştür. '
          'Bu uzaklık gerçekte kaç kilometredir?',
      km,
      // Tipik hatalar anahtarın iki yanında: çarpmak yerine bölme, km'ye çevirirken
      // bir ya da iki basamak kaydırma (×10, ÷10, ×100, ÷100) ve bölme hatasının
      // basamak kaymalı biçimleri, alan hesabıyla karıştırıp ölçeğin karesini alma.
      // Anahtarın değer sırası vakadan vakaya değişir. Bu ölçekteki bir haritada
      // gerçekçi olmayan 2000 km üstü değerler kullanılmaz.
      [
        ters,
        km * 10,
        km / 10,
        if (km * 100 <= 2000) km * 100,
        km / 100,
        ters * 10,
        ters * 100,
        km * s,
        s, // işlemi yarıda bırakıp 1 cm'nin gerçek karşılığını yanıt sanma
      ],
      'Haritadaki 1 cm gerçekte $payda cm, yani ${tr(s)} km eder. '
          '${tr(cm10 / 10)} × ${tr(s)} = ${tr(km)} km bulunur.',
      sira,
      komsu: true,
      unit: 'km',
      digits: 3,
    );
  }
  final cm10 = 15 + b + 20 * k; // 1,5 … 11,4 cm
  final km = cm10 * (6 + a) * 2 / 100;
  final cm = cm10 / 10;
  return _ondalikliTipik(
    'Gerçekte ${tr(km)} km olan $baglam, 1/$payda ölçekli bir haritada kaç santimetre '
        'ile gösterilir?',
    cm,
    // Tipik hatalar: bölmek yerine çarpma, cm'ye çevirirken basamak kaydırma,
    // orantıyı ters kurma (ölçek değerini uzunluğa bölme), çarpma hatasının basamak
    // kaymalı biçimi, alan hesabıyla karıştırıp ölçeğin karesine bölme. Haritada
    // 2 m'yi aşan iki basamaklı kaydırma gerçekçi olmadığından kullanılmaz.
    [
      (km * s * 10).round() / 10,
      cm * 10,
      cm / 10,
      if (cm * 100 <= 200) cm * 100,
      cm / 100,
      s / km,
      (km * s * 10).round() / 100,
      cm / s,
    ],
    'Bu ölçekte haritadaki 1 cm gerçekte $payda cm, yani ${tr(s)} km eder. '
        '${tr(km)} / ${tr(s)} = ${tr(cm)} cm bulunur.',
    sira,
    komsu: true,
    unit: 'cm',
    digits: 3,
  );
}

const _hatBaglam = [
  'bir kara yolu',
  'bir demir yolu hattı',
  'bir sulama kanalı',
  'bir kıyı şeridi',
  'bir boru hattı',
];
const _alanBaglam = [
  ('bir gölün', 'bir göl'),
  ('bir ovanın', 'bir ova'),
  ('bir ormanın', 'bir orman'),
  ('bir adanın', 'bir ada'),
  ('bir millî parkın', 'bir millî park'),
];

AdvancedItem _olcekAlan(int a, int b, int c) {
  final bicim = c % 3, q = c ~/ 3;
  final payda = 50000 * (a + 3); // 1/150000 … 1/1350000
  final s = (a + 3) / 2; // 1 cm kaç km
  final i = _vaka(a, b, c);
  if (bicim == 0) {
    final cm10 = 20 + b + 20 * q; // 2,0 … 9,9 cm
    final km = cm10 * (a + 3) / 20;
    final gercekCm = cm10 * (a + 3) * 5000;
    // Ölçek bulmada tipik hata paydada basamak kaydırmadır (×10, ÷10, ×100, ÷100).
    // Anahtar bu yüzden ikinci ya da üçüncü büyük ölçek olur; iki durum eşit
    // sıklıktadır. Alan biçimleri uç sıraları daha sık alarak ailede dengeyi kurar.
    final adaylar = [payda * 10, payda ~/ 10, payda * 100, payda ~/ 100];
    return AdvancedItem(
      'Gerçekte ${tr(km)} km uzunluğundaki ${sec(_hatBaglam, a + b + q)}, bir haritada '
          '${tr(cm10 / 10)} cm uzunluğunda gösterilmiştir. Bu haritanın ölçeği nedir?',
      '1/$payda',
      siraliCeldiriciler(1 / payda, '1/$payda', [
        for (final x in adaylar) (1 / x, '1/$x'),
      ], hedefSira(i)),
      '${tr(km)} km = $gercekCm cm eder. Ölçek = harita uzunluğu / gerçek uzunluk = '
          '${tr(cm10 / 10)} / $gercekCm = 1/$payda.',
    );
  }
  final yer = sec(_alanBaglam, a + b + q);
  if (bicim == 1) {
    final harita = 2 + b + 20 * q; // cm²
    final gercek = harita * (a + 3) * (a + 3) / 4;
    final unut = harita * s; // ölçeğin karesini almayı unutma
    return _ondalikliTipik(
      '1/$payda ölçekli bir haritada $harita cm² yer kaplayan ${yer.$1} gerçek alanı '
          'kaç kilometrekaredir?',
      gercek,
      // Tipik hatalar: kareyi almayı unutma, kare yerine 2 ile çarpma, birim
      // çevirmede basamak kaydırma (uzunlukta bir basamak alanda ×100 / ÷100 eder)
      // ve kareyi unutmanın basamak kaymalı biçimleri.
      // Türkiye'nin yüz ölçümüne yaklaşan (100000 km² üstü) iki basamaklı kaydırma
      // gerçekçi olmadığından kullanılmaz.
      [
        unut,
        gercek * 10,
        gercek / 10,
        if (gercek * 100 <= 100000) gercek * 100,
        gercek / 100,
        harita * 2 * s,
        unut * 10,
        unut * 100,
      ],
      'Haritadaki 1 cm gerçekte ${tr(s)} km olduğundan 1 cm² gerçekte ${tr(s)} × ${tr(s)} = '
          '${tr(s * s)} km² eder. $harita × ${tr(s * s)} = ${tr(gercek)} km² bulunur.',
      _ucaYakinSira(i),
      komsu: true,
      unit: 'km²',
      digits: 3,
    );
  }
  final harita = 3 + b + 20 * q; // cm²
  final gercek = harita * (a + 3) * (a + 3) / 4;
  final unut = harita * s; // ölçeğin karesi yerine kendisine bölme
  // Tipik hatalar: kare yerine ölçeğin kendisine ya da iki katına bölme, birim
  // çevirmede basamak kaydırma ve kareyi unutmanın basamak kaymalı biçimleri.
  // Tam sayı anahtarın rakamlarını ondalık kısmında taşıyan kaydırmalar ("23" için
  // "0,23") sona alınır; yoksa sözcük benzerliği anahtarı öne çıkarır.
  bool paylasir(double x) =>
      tr(x, 3).split(RegExp('[^0-9]+')).contains('$harita');
  final adaylar = [
    unut,
    harita * 10.0,
    harita / 10,
    harita * 100.0,
    harita / 100,
    harita * s / 2,
    unut / 10,
    unut / 100,
  ];
  return _ondalikliTipik(
    'Gerçek alanı ${tr(gercek)} km² olan ${yer.$2}, 1/$payda ölçekli bir haritada kaç '
        'santimetrekarelik yer kaplar?',
    harita.toDouble(),
    [...adaylar.where((x) => !paylasir(x)), ...adaylar.where(paylasir)],
    'Haritadaki 1 cm gerçekte ${tr(s)} km olduğundan 1 cm² gerçekte ${tr(s * s)} km² eder. '
        '${tr(gercek)} / ${tr(s * s)} = $harita cm² bulunur.',
    _ucaYakinSira(i),
    komsu: true,
    unit: 'cm²',
    digits: 3,
  );
}

// Çiftler, 8 m ile 1092 m arasındaki her yükselti farkı için anlamlı kalır.
const _egimYer = [
  ('bir köy', 'bir mesire alanı'),
  ('bir göl kıyısı', 'bir seyir terası'),
  ('bir vadi tabanı', 'bir sırt'),
  ('bir kasaba', 'bir tepe'),
  ('bir çiftlik', 'bir orman gözetleme kulesi'),
];

/// Eğim çeldiricileri: hepsi kökün sorduğu işaretle (% ya da ‰) yazılır ve
/// anahtarın değer sırası [sira] ile belirlenir. [adaylar] (değer, ondalık basamak)
/// ikilileridir.
List<String> _egimCeldirici(
  String isaret,
  int anahtar,
  List<(num, int)> adaylar,
  int sira,
) => siraliCeldiriciler(anahtar, '$isaret$anahtar', [
  for (final (x, d) in adaylar) (x, '$isaret${tr(x, d)}'),
], sira);

AdvancedItem _egim(int a, int b, int c) {
  final k = c ~/ 2;
  final sira = hedefSira(_vaka(a, b, c));
  if (c.isEven) {
    final p = 2 + a; // %2 … %26
    final yatay = (2 + b) * 200; // 400 … 4200 m
    final fark = p * (2 + b) * 2;
    final h1 = const [320, 550, 680, 860, 1040][k], h2 = h1 + fark;
    final yer = sec(_egimYer, a + b);
    final uzaklik = k.isOdd ? '${tr(yatay / 1000)} km' : '$yatay m';
    return AdvancedItem(
      'Yükseltisi $h1 m olan ${yer.$1} ile yükseltisi $h2 m olan ${yer.$2} arasındaki yatay '
          'uzaklık $uzaklik olarak ölçülmüştür. Bu iki yer arasındaki ortalama eğim yüzde (%) kaçtır?',
      '%$p',
      // Tipik hatalar: 100 yerine 1000 ile çarpma, 100 ile çarpmayı unutma, oranı ters
      // kurma (yatay uzaklık / yükselti farkı), yükselti farkı yerine yerlerden birinin
      // yükseltisini ya da iki yükseltinin toplamını kullanma, 100 yerine 10 ile çarpma.
      // Yuvarlanan değerler öğrencinin bulacağı sonuca en yakın tam sayıdır; %100'ü
      // (45°) aşan yükselti kaynaklı değerler gerçekçi olmadığından kullanılmaz.
      _egimCeldirici('%', p, [
        (10 * p, 0),
        (p / 100, 2),
        ((100 / p).round(), 0),
        for (final h in [h2, h1, h1 + h2])
          if (h * 100 / yatay <= 100) ((h * 100 / yatay).round(), 0),
        (p / 10, 1),
      ], sira),
      'Yükselti farkı $h2 − $h1 = $fark m, yatay uzaklık '
          '${k.isOdd ? '$uzaklik = $yatay m' : '$yatay m'} olduğundan '
          'eğim = $fark / $yatay × 100 = %$p olur.',
    );
  }
  final q = 5 + 3 * a; // ‰5 … ‰77
  final km = 2 + b; // 2 … 21 km
  final fark = q * km;
  final h1 = const [40, 150, 260, 380, 520][k], h2 = h1 + fark;
  final giris = switch ((a + b) % 3) {
    0 =>
      'Bir akarsu $h2 m yükseltideki kaynağından doğup $h1 m yükseltideki bir göle '
          'dökülmektedir. Akarsuyun kaynağı ile döküldüğü yer arasındaki yatay uzaklık $km km '
          'olduğuna göre akarsu yatağının',
    1 =>
      'Bir yol $h1 m yükseltideki bir kasabadan başlayıp $h2 m yükseltideki bir köye '
          'ulaşmaktadır. Kasaba ile köy arasındaki yatay uzaklık $km km olduğuna göre yolun',
    _ =>
      'Bir su iletim hattı $h2 m yükseltideki bir kaynaktan $h1 m yükseltideki bir depoya '
          'inmektedir. Kaynak ile depo arasındaki yatay uzaklık $km km olduğuna göre hattın',
  };
  return AdvancedItem(
    '$giris ortalama eğimi binde (‰) kaçtır?',
    '‰$q',
    // Tipik hatalar: 1000 yerine 100 ile çarpma (yüzde formülü), kilometreyi metreye
    // çevirirken 100 ile çarpma, oranı ters kurma, yükselti farkı yerine yerlerden
    // birinin yükseltisini ya da iki yükseltinin toplamını kullanma, 1000 ile
    // çarpmayı unutma, 1000 yerine 10 ile çarpma.
    _egimCeldirici('‰', q, [
      (q / 10, 1),
      (10 * q, 0),
      ((1000 / q).round(), 0),
      ((h2 / km).round(), 0),
      ((h1 / km).round(), 0),
      (((h1 + h2) / km).round(), 0),
      (q / 1000, 3),
      (q / 100, 2),
    ], sira),
    'Yükselti farkı $h2 − $h1 = $fark m, yatay uzaklık $km km = ${km * 1000} m olduğundan '
        'eğim = $fark / ${km * 1000} × 1000 = ‰$q olur.',
  );
}

// Yükseltisi 600–2500 m arasında değişen yerler için geçerli adlar.
const _yuksekYer = [
  'bir dağ istasyonunda',
  'bir yaylada',
  'bir dağ köyünde',
  'bir dağ geçidinde',
  'bir dağ evinde',
];

AdvancedItem _sicaklik(int a, int b, int c) {
  final bicim = c % 3, q = c ~/ 3;
  const kural = 'Sıcaklığın her 200 metrede 1 °C değiştiği kabul edilmektedir.';
  // Sıcaklıklar onda bir °C olarak tam sayıyla tutulur. Yükseltiler 100 m
  // adımlıdır ve gerçekçi aralıkta kalır: istasyon en çok 2300 m, deniz
  // seviyesiyle karşılaştırılan yer en çok 2500 m, yayla en çok 2800 m.
  String say(int onda) => _n(onda / 10);
  String yaz(int onda) => _derece(onda / 10);
  // Yükselti farkının (m) yol açtığı sıcaklık farkı, onda bir °C.
  int fark(int metre) => metre ~/ 20;
  final i = _vaka(a, b, c);
  // Çeldiriciler anahtarın iki yanındaki tipik hatalardan, anahtarın değer sırası
  // [sira] olacak biçimde seçilir; tipik hata yetmezse 1–2 °C komşu değer gelir.
  AdvancedItem soru(
    String kok,
    int dogru,
    List<int> yanlis,
    String aciklama,
    int sira,
  ) => AdvancedItem(
    kok,
    yaz(dogru),
    siraliCeldiriciler(dogru, yaz(dogru), [
      for (final x in [
        ...yanlis,
        dogru + 10,
        dogru - 10,
        dogru + 20,
        dogru - 20,
      ])
        (x, yaz(x)),
    ], sira),
    aciklama,
  );
  // Tipik hatalar: ters yönde işlem, 100 m'de 1 °C sanma, 400 m'de 1 °C sanma
  // (400 m kuralı yalnız sonuç onda bire tam bölündüğünde) ve bunların ters
  // yönlü biçimleri. Çağıran yer bunlara sıcaklık değişimini sıcaklık sanmayı (d)
  // ekler; aynı hatanın işaretli biçimi (−d) ayrıca verilmez, yoksa iki çeldirici
  // aynı yanlışı gösterir.
  List<int> hatalar(int t0, int d, int yon, bool tam400) => [
    t0 - yon * d,
    t0 + 2 * yon * d,
    if (tam400) t0 + yon * (d ~/ 2),
    t0 - 2 * yon * d,
    if (tam400) t0 - yon * (d ~/ 2),
  ];
  if (bicim == 0) {
    final deniz = 120 + 10 * a + const [0, 5, 2, 7][q]; // 12 … 36,7 °C
    final h = 100 * (6 + b); // 600 … 2500 m
    final d = fark(h), t = deniz - d;
    return soru(
      'Deniz seviyesinde sıcaklığın ${yaz(deniz)} ölçüldüğü bir anda, aynı bölgede $h m '
          'yükseltideki ${sec(_yuksekYer, a + b)} sıcaklığın kaç °C olması beklenir? $kural',
      t,
      [...hatalar(deniz, d, -1, h % 200 == 0), d],
      'Yükselti farkı $h m olduğundan sıcaklık $h / 200 = ${say(d)} °C azalır: '
          '${say(deniz)} − ${say(d)} = ${yaz(t)}.',
      hedefSira(i),
    );
  }
  if (bicim == 1) {
    final deniz = 120 + 10 * a + const [0, 5, 2][q];
    final h = 100 * (4 + b); // 400 … 2300 m
    final d = fark(h), t = deniz - d; // t: istasyonda ölçülen, en az 0,5 °C
    // Bu biçimde anahtarın üstünde tek tipik hata vardır (100 m'de 1 °C sanma);
    // anahtar en küçük seçenek yapılmaz, ailenin öteki biçimleri bunu dengeler.
    final s0 = hedefSira(i);
    return soru(
      'Yükseltisi $h m olan bir meteoroloji istasyonunda sıcaklık ${yaz(t)} olarak '
          'ölçülmüştür. $kural Buna göre istasyonun deniz seviyesine indirgenmiş sıcaklığı kaç °C olur?',
      deniz,
      [...hatalar(t, d, 1, h % 200 == 0), d],
      'İndirgemede yükseltinin etkisi kaldırılır: $h / 200 = ${say(d)} °C eklenir. '
          '${say(t)} + ${say(d)} = ${yaz(deniz)}.',
      s0 == 0 ? 2 + hedefSira(i, 5) % 2 : s0,
    );
  }
  // İki nokta arasında: köy 300, 500 ya da 700 m; yayla 900 … 2800 m.
  final alt = const [300, 500, 700][q];
  final ust = 900 + 100 * b;
  final m = ust - alt, d = fark(m);
  if (q == 1) {
    final tUst = -100 + 10 * a; // −10 … 14 °C
    final tAlt = tUst + d;
    return soru(
      'Bir dağın yamacında $ust m yükseltideki yaylada sıcaklık ${yaz(tUst)} iken aynı anda '
          '$alt m yükseltideki köyde sıcaklığın kaç °C olması beklenir? $kural',
      tAlt,
      // Yükselti farkı yerine yaylanın yükseltisini kullanma da tipik bir hatadır.
      [...hatalar(tUst, d, 1, m % 200 == 0), tUst + fark(ust), d],
      'Yükselti farkı $ust − $alt = $m m olduğundan sıcaklık farkı '
          '$m / 200 = ${say(d)} °C olur. Alçaktaki köy daha sıcaktır: '
          '${say(tUst)} + ${say(d)} = ${yaz(tAlt)}.',
      hedefSira(i),
    );
  }
  final tAlt = 80 + 10 * a + (q == 2 ? 5 : 0); // 8 … 32,5 °C
  final tUst = tAlt - d;
  return soru(
    'Bir dağın yamacında $alt m yükseltideki köyde sıcaklık ${yaz(tAlt)} iken aynı anda '
        '$ust m yükseltideki yaylada sıcaklığın kaç °C olması beklenir? $kural',
    tUst,
    [...hatalar(tAlt, d, -1, m % 200 == 0), tAlt - fark(ust), d],
    'Yükselti farkı $ust − $alt = $m m olduğundan sıcaklık farkı '
        '$m / 200 = ${say(d)} °C olur. Yüksekteki yayla daha soğuktur: '
        '${say(tAlt)} − ${say(d)} = ${yaz(tUst)}.',
    hedefSira(i),
  );
}

AdvancedItem _paralel(int a, int b, int c) {
  const kural = 'Ardışık iki paralel arasındaki uzaklık 111 km';
  String enlem(int x) => '${x.abs()}° ${x >= 0 ? 'Kuzey' : 'Güney'}';
  // Uzaklık soran biçimler: K ve L enlemleri (kuzey artı).
  final uzaklik = switch (c) {
    0 => (5 + a, 8 + a + b),
    1 => (5 + a, -(2 + b)),
    2 => (-(10 + a), -(14 + a + b)),
    6 => (-(4 + a), 6 + 2 * b),
    7 => (40 + a, 35 + a - b),
    _ => null,
  };
  if (uzaklik != null) {
    final (k, l) = uzaklik;
    final ayni = (k > 0) == (l > 0);
    final fark = (k - l).abs();
    final diger = ayni ? k.abs() + l.abs() : (k.abs() - l.abs()).abs();
    final buyuk = k.abs() > l.abs() ? k.abs() : l.abs();
    final kucuk = k.abs() > l.abs() ? l.abs() : k.abs();
    return sayisal(
      'Aynı meridyen üzerindeki K merkezi ${enlem(k)}, L merkezi ${enlem(l)} paralelindedir. '
      '$kural olduğuna göre K ile L arasındaki kuş uçuşu uzaklık kaç kilometredir?',
      fark * 111,
      [diger * 111, (fark + 1) * 111, (fark - 1) * 111, fark * 100],
      ayni
          ? 'Merkezler aynı yarım kürede olduğundan enlem farkı $buyuk − $kucuk = $fark° olur. '
                '$fark × 111 = ${fark * 111} km bulunur.'
          : 'Merkezler Ekvator\'un farklı yanlarında olduğundan enlem farkı '
                '${k.abs()} + ${l.abs()} = $fark° olur. $fark × 111 = ${fark * 111} km bulunur.',
      unit: 'km',
      positive: true,
    );
  }
  // Enlem bulma: K enlemi, derece farkı, yön (kuzeye +1).
  final (k, d, yon) = switch (c) {
    3 => (5 + a, 3 + b, 1),
    4 => (30 + a, 3 + b, -1),
    5 => (3 + a, 30 + b, -1),
    8 => (-(8 + a), 3 + b, -1),
    _ => (-(12 + a), 40 + b, 1),
  };
  final l = k + yon * d;
  final gecer = (l > 0) != (k > 0);
  final yari = l > 0 ? 'kuzey' : 'güney';
  final ek = gecer || c == 4
      ? '${l > 0 ? 'Kuzey' : 'Güney'} Yarım Küre\'de yer alan L merkezi kaç derece '
            '$yari enlemindedir?'
      : 'L merkezi kaç derece $yari enlemindedir?';
  final String yol;
  if (gecer) {
    yol =
        '${yon > 0 ? 'Kuzeye' : 'Güneye'} doğru $d° gidilirken Ekvator geçilir: '
        '$d − ${k.abs()} = ${l.abs()}';
  } else if (l.abs() > k.abs()) {
    yol = 'Ekvator\'dan uzaklaşıldığı için ${k.abs()} + $d = ${l.abs()}';
  } else {
    yol = 'Ekvator\'a yaklaşıldığı için ${k.abs()} − $d = ${l.abs()}';
  }
  final dogru = l.abs();
  final yanlis = [
    gecer
        ? k.abs() + d
        : (l.abs() > k.abs() ? (k.abs() - d).abs() : k.abs() + d),
    d,
    dogru + 2,
    dogru - 2,
    dogru + 5,
    dogru + 10,
  ].where((x) => x > 0 && x <= 90);
  return secenekli(
    'K merkezi ${enlem(k)} paraleli üzerindedir. L merkezi, aynı meridyen üzerinde K merkezinin '
        '${d * 111} km ${yon > 0 ? 'kuzeyindedir' : 'güneyindedir'}. $kural kabul edildiğinde $ek',
    '$dogru°',
    yanlis.map((x) => '$x°'),
    '${d * 111} / 111 = $d° enlem farkı eder. $yol; L merkezi ${enlem(l)} enlemindedir.',
  );
}

const _yogunlukYer = [
  ('bir ilçenin', 'Bu ilçenin'),
  ('bir adanın', 'Bu adanın'),
  ('bir ilin', 'Bu ilin'),
  ('bir havzanın', 'Bu havzanın'),
];

AdvancedItem _nufusYogunlugu(int a, int b, int c) {
  // (biçim, tarım alanı payı 1/m, tarımla geçinenlerin onda payı)
  final (bicim, m, r) = const [
    (0, 2, 3),
    (1, 4, 4),
    (2, 5, 6),
    (0, 4, 6),
    (1, 5, 3),
    (2, 2, 4),
    (0, 5, 4),
    (1, 2, 6),
    (2, 4, 3),
    (0, 2, 7),
  ][c];
  final alan = 200 + 100 * b; // km²
  final ar = 10 * (2 + a); // aritmetik yoğunluk
  final nufus = alan * ar;
  final tarimAlani = alan ~/ m;
  final tarimNufusu = nufus * r ~/ 10;
  final fiz = ar * m;
  final tar = ar * m * r ~/ 10;
  final karisik = ar * r ~/ 10; // tarım nüfusu / yüz ölçümü
  final yer = sec(_yogunlukYer, a + b);
  final (ad, dogru, yanlis, aciklama) = switch (bicim) {
    0 => (
      'aritmetik',
      ar,
      [fiz, tar, karisik],
      'Aritmetik nüfus yoğunluğu = toplam nüfus / yüz ölçümü = $nufus / $alan = $ar kişi/km².',
    ),
    1 => (
      'tarımsal',
      tar,
      [fiz, ar, karisik],
      'Tarımsal nüfus yoğunluğu = tarımla geçinen nüfus / tarım alanı = '
          '$tarimNufusu / $tarimAlani = $tar kişi/km².',
    ),
    _ => (
      'fizyolojik',
      fiz,
      [ar, tar, karisik],
      'Fizyolojik nüfus yoğunluğu = toplam nüfus / tarım alanı = '
          '$nufus / $tarimAlani = $fiz kişi/km².',
    ),
  };
  return sayisal(
    'Yüz ölçümü $alan km² olan ${yer.$1} toplam nüfusu $nufus kişi, tarım alanı $tarimAlani km² '
    've tarımla geçinen nüfusu $tarimNufusu kişidir. ${yer.$2} $ad nüfus yoğunluğu km² başına '
    'kaç kişidir?',
    dogru,
    yanlis,
    aciklama,
    unit: 'kişi/km²',
    positive: true,
  );
}

AdvancedItem _nufusArtisi(int a, int b, int c) {
  final bicim = c % 3, q = c ~/ 3;
  final bin = 20 + 4 * a; // nüfus (bin kişi)
  final nufus = bin * 1000;
  final sira = hedefSira(_vaka(a, b, c));
  if (bicim == 0) {
    final dogum = 16 + b, olum = 5 + 2 * q;
    final hiz = dogum - olum, artis = bin * hiz;
    return _sayisalTipik(
      'Yıl ortası nüfusu $nufus olan bir ilçede bir yıl içinde doğum oranı ‰$dogum, ölüm oranı '
          '‰$olum olarak gerçekleşmiştir. Göçler dikkate alınmadığında bu ilçenin nüfusu bir yılda '
          'doğal yolla kaç kişi artmıştır?',
      artis,
      // Tipik hatalar anahtarın iki yanında: ölümleri düşmeme, yalnız ölümleri
      // hesaplama, oranları toplama, artış hızını (‰) kişi sayısı sanma, binde yerine
      // yüzde alma, on binde sanma (tam sayı çıktığında) ve oran farkında bir birimlik
      // işlem hatası.
      [
        bin * dogum,
        bin * olum,
        bin * (dogum + olum),
        hiz,
        artis * 10,
        if (artis % 10 == 0) artis ~/ 10,
        bin * (hiz - 1),
        bin * (hiz + 1),
      ],
      'Doğal nüfus artış hızı ‰$dogum − ‰$olum = ‰$hiz olur. '
          '$nufus × $hiz / 1000 = ${bin * hiz} kişi.',
      sira,
      unit: 'kişi',
    );
  }
  if (bicim == 1) {
    final hiz = 3 + b, olumOrani = 6 + q;
    final olum = bin * olumOrani, dogum = olum + bin * hiz;
    String binde(num x, [int d = 2]) => '‰${tr(x, d)}';
    return AdvancedItem(
      'Yıl ortası nüfusu $nufus olan bir ilçede bir yıl boyunca $dogum doğum ve $olum ölüm '
          'kaydedilmiştir. Bu ilçenin doğal nüfus artış hızı binde (‰) kaçtır?',
      '‰$hiz',
      // Bütün seçenekler kökün sorduğu binde (‰) ile yazılır. Tipik hatalar: ölümleri
      // düşmeme (doğum hızı), 1000 yerine 100 ile çarpma, ölüm hızını verme, doğum ile
      // ölümü toplama, 1000 ile çarpmayı unutma, 1000 yerine 10000 ile çarpma (yalnız
      // gerçekçi kaldığında, ‰40'a kadar); en sonda binde birlik komşu değerler.
      siraliCeldiriciler(hiz, '‰$hiz', [
        for (final (x, d) in [
          (hiz + olumOrani, 0),
          (hiz / 10, 1),
          (olumOrani, 0),
          (hiz + 2 * olumOrani, 0),
          (hiz / 1000, 3),
          if (hiz * 10 <= 40) (hiz * 10, 0),
          (hiz + 1, 0),
          (hiz - 1, 0),
        ])
          (x, binde(x, d)),
      ], sira),
      'Doğal artış $dogum − $olum = ${dogum - olum} kişidir. '
          '${dogum - olum} / $nufus × 1000 = ‰$hiz bulunur.',
    );
  }
  final dogum = 400 + 30 * b;
  final olum = 180 + 20 * (a % 6) + 10 * q;
  final gelen = 900 + 40 * a + 100 * q;
  final giden = 300 + 25 * b + 50 * q;
  final dogal = dogum - olum, net = gelen - giden;
  if (q == 2) {
    final son = nufus + dogal + net;
    final toplam = son - nufus;
    return _sayisalTipik(
      'Yıl başında nüfusu $nufus olan bir ilçede yıl içinde $dogum doğum ve $olum ölüm '
          'gerçekleşmiş, yıl sonunda nüfus $son olarak belirlenmiştir. Bu ilçenin yıl içindeki net '
          'göçü (aldığı göç ile verdiği göç arasındaki fark) kaç kişidir?',
      net,
      // Tipik hatalar: toplam artışı net göç sanma, doğal artışı çıkarmak yerine
      // ekleme, doğal artışı verme, doğal artış yerine yalnız doğumları ya da doğum
      // ile ölümün toplamını çıkarma.
      [toplam, toplam + dogal, dogal, toplam - dogum, toplam - dogum - olum],
      'Toplam artış $son − $nufus = ${son - nufus} kişi, doğal artış $dogum − $olum = $dogal '
          'kişidir. Net göç ${son - nufus} − $dogal = $net kişi olur.',
      sira,
      komsu: true,
      unit: 'kişi',
    );
  }
  const giris = 'yıl içinde';
  final veri =
      'Yıl başında nüfusu $nufus olan bir ilçede $giris $dogum doğum ve $olum ölüm gerçekleşmiş; '
      'ilçe dışarıdan $gelen kişi göç almış, dışarıya $giden kişi göç vermiştir.';
  if (q == 0) {
    final son = nufus + dogal + net;
    return _sayisalTipik(
      '$veri Bu ilçenin yıl sonundaki nüfusu kaç kişidir?',
      son,
      // Tipik hatalar: göçü unutma, göçleri toplama, ölümleri ekleme, doğal artışı
      // unutma, ölümleri düşmeme, net göçü çıkarma, verilen göçü düşmeme.
      [
        nufus + dogal,
        nufus + dogal + gelen + giden,
        nufus + dogum + olum + net,
        nufus + net,
        nufus + dogum + net,
        nufus + dogal - net,
        nufus + dogal + gelen,
      ],
      'Doğal artış $dogum − $olum = $dogal, net göç $gelen − $giden = $net kişidir. '
          '$nufus + $dogal + $net = $son kişi.',
      sira,
      unit: 'kişi',
    );
  }
  return _sayisalTipik(
    '$veri Bu ilçenin nüfusu bir yılda toplam kaç kişi artmıştır?',
    dogal + net,
    // Tipik hatalar: göçü unutma, göçleri toplama, ölümleri ekleme, doğal artışı
    // unutma, ölümleri düşmeme, verilen göçü düşmeme, iki artışı toplamak yerine
    // birbirinden çıkarma.
    [
      dogal,
      dogal + gelen + giden,
      dogum + olum + net,
      net,
      dogum + net,
      dogal + gelen,
      (dogal - net).abs(),
    ],
    'Doğal artış $dogum − $olum = $dogal, net göç $gelen − $giden = $net kişidir. '
        'Toplam artış $dogal + $net = ${dogal + net} kişi.',
    sira,
    unit: 'kişi',
  );
}

AdvancedItem _bagilNem(int a, int b, int c) {
  final bicim = c % 4, q = c ~/ 4;
  final maks = 10 + a; // g/m³
  final r = 10 + 4 * b + q; // bağıl nem (%)
  final mutlak = maks * r / 100;
  final acik = maks * (100 - r) / 100;
  switch (bicim) {
    case 0:
      return secenekli(
        'Bir hava kütlesinin mutlak nemi ${tr(mutlak)} g/m³, bulunduğu sıcaklıkta taşıyabileceği '
            'en fazla nem (maksimum nem) $maks g/m³ olarak ölçülmüştür. Bu havanın bağıl nemi '
            'yüzde kaçtır?',
        '%$r',
        [
          '%${100 - r}',
          '%${tr(acik)}',
          '%${tr(mutlak)}',
          '%${r + 10}',
          '%${r + 5}',
        ],
        'Bağıl nem = mutlak nem / maksimum nem × 100 = ${tr(mutlak)} / $maks × 100 = %$r.',
      );
    case 1:
      return ondalikli(
        'Sıcaklığı sabit olan bir hava kütlesinin maksimum nemi $maks g/m³, bağıl nemi %$r '
            'olarak ölçülmüştür. Bu havanın mutlak nemi kaç g/m³ olur?',
        mutlak,
        [acik, mutlak * 10, mutlak / 10, maks + mutlak],
        'Mutlak nem = maksimum nem × bağıl nem / 100 = $maks × $r / 100 = ${tr(mutlak)} g/m³.',
        digits: 3,
        positive: true,
      );
    case 2:
      return ondalikli(
        'Mutlak nemi ${tr(mutlak)} g/m³ olan bir hava kütlesinin bağıl nemi %$r olarak '
            'ölçülmüştür. Bu havanın maksimum nemi kaç g/m³ olur?',
        maks.toDouble(),
        [(mutlak * r).round() / 100, acik, maks / 10],
        'Maksimum nem = mutlak nem × 100 / bağıl nem = ${tr(mutlak)} × 100 / $r = $maks g/m³.',
        positive: true,
      );
    default:
      return ondalikli(
        'Maksimum nemi $maks g/m³ olan bir hava kütlesinin bağıl nemi %$r olarak ölçülmüştür. '
            'Bu havanın doyma noktasına ulaşması için gereken nem miktarı (nem açığı) kaç g/m³ olur?',
        acik,
        [mutlak, maks - r / 10, acik * 10, acik / 10],
        'Mutlak nem $maks × $r / 100 = ${tr(mutlak)} g/m³ olur. '
            'Nem açığı = maksimum nem − mutlak nem = $maks − ${tr(mutlak)} = ${tr(acik)} g/m³.',
        digits: 3,
        positive: true,
      );
  }
}

AdvancedItem _bagimliNufus(int a, int b, int c) {
  final k = c ~/ 2;
  final oran = 40 + 2 * a; // %40 … %88
  final calisan = (20 + 5 * b) * 1000; // 15–64 yaş
  final bagimli = (200 + 50 * b) * oran; // 0–14 ile 65+
  final sira = hedefSira(_vaka(a, b, c));
  if (c.isEven) {
    final pay = const [60, 65, 70, 75, 80][k];
    final genc = bagimli * pay ~/ 100, yasli = bagimli - genc;
    final toplamdaPay = (bagimli * 100 / (calisan + bagimli)).round();
    final calisanPay = (calisan * 100 / (calisan + bagimli)).round();
    return AdvancedItem(
      'Bir ilçede 0–14 yaş grubunda $genc, 15–64 yaş grubunda $calisan, 65 ve üzeri yaş grubunda '
          '$yasli kişi yaşamaktadır. Bağımlı nüfus oranı, 0–14 ile 65 ve üzeri yaş gruplarındaki '
          'toplam nüfusun 15–64 yaş grubundaki nüfusa oranının 100 ile çarpılmasıyla bulunduğuna '
          'göre bu ilçenin bağımlı nüfus oranı yüzde kaçtır?',
      '%$oran',
      // Tipik hatalar anahtarın iki yanında: bağımlı nüfusu toplam nüfusa oranlama,
      // oranı ters kurma (15–64 / bağımlı), yalnız 0–14 yaşı ya da yalnız 65 ve üzeri
      // yaşı hesaba katma, toplam nüfusu 15–64 yaş nüfusuna oranlama, 15–64 yaşın
      // toplamdaki payını verme, bağımlı nüfusu 0–14 yaş nüfusuna oranlama; en sonda
      // komşu değerler. Gerçekçi olmayan %170 üstü oranlar kullanılmaz. Komşu değerler
      // yalnız anahtarın üstüne düşer; çok kullanılırlarsa anahtar yakın değerlerin
      // en küçüğü olarak göze batar.
      siraliCeldiriciler(oran, '%$oran', [
        for (final x in <num>[
          toplamdaPay,
          if (10000 / oran <= 170) (10000 / oran).round(),
          oran * pay / 100,
          if (100 + oran <= 170) 100 + oran,
          oran * (100 - pay) / 100,
          calisanPay,
          if (10000 / pay <= 170) (10000 / pay).round(),
          oran + 10,
          oran + 6,
        ])
          (x, '%${tr(x)}'),
      ], sira),
      'Bağımlı nüfus $genc + $yasli = $bagimli kişidir. '
          '$bagimli / $calisan × 100 = %$oran bulunur.',
    );
  }
  final pay = const [55, 62, 68, 72, 78][k];
  final yasli = bagimli * (100 - pay) ~/ 100, genc = bagimli - yasli;
  return _sayisalTipik(
    'Bir ilçede 15–64 yaş grubundaki nüfus $calisan, 65 ve üzeri yaş grubundaki nüfus $yasli '
        'kişidir. Bağımlı nüfus oranı (0–14 ile 65 ve üzeri yaş nüfusunun 15–64 yaş nüfusuna '
        'oranının 100 katı) %$oran olduğuna göre bu ilçede 0–14 yaş grubunda kaç kişi yaşamaktadır?',
    genc,
    // Tipik hatalar: 65 ve üzeri nüfusu çıkarmama ya da ekleme, bağımlı nüfusu 15–64
    // yaş nüfusundan çıkarma (65 ve üzeri ile birlikte ya da değil), bağımlı nüfusu iki
    // yaş grubuna eşit bölme, 65 ve üzeri nüfusu iki kez çıkarma; tipik hata yetmezse
    // en sonda %10 ve %25 komşu değerler. Anahtarın altındaki tipik hatalar olmadan
    // komşular çoğunlukla altta kalır ve anahtar yakın değerlerin en büyüğü olarak
    // göze batar. Kökte verilen 65 ve üzeri nüfus çeldirici yapılmaz.
    [
      bagimli,
      calisan - bagimli,
      bagimli + yasli,
      if (calisan - bagimli - yasli >= genc / 4) calisan - bagimli - yasli,
      bagimli ~/ 2,
      if (bagimli - 2 * yasli >= genc / 4) bagimli - 2 * yasli,
      genc * 9 ~/ 10,
      genc * 11 ~/ 10,
      genc * 3 ~/ 4,
    ],
    'Bağımlı nüfus = $calisan × $oran / 100 = $bagimli kişidir. '
        '0–14 yaş nüfusu = $bagimli − $yasli = $genc kişi.',
    sira,
    unit: 'kişi',
  );
}

AdvancedItem _disTicaret(int a, int b, int c) {
  final bicim = c % 3, q = c ~/ 3;
  if (bicim == 2) {
    final nufus = 4 + 2 * b; // milyon
    final kbg = (3 + a + 25 * q) * 500; // dolar
    final gsyh = (2 + b) * (3 + a + 25 * q); // milyar dolar
    return sayisal(
      'Nüfusu $nufus milyon olan bir ülkenin gayrisafi yurt içi hasılası $gsyh milyar dolardır. '
          'Bu ülkede kişi başına düşen gelir kaç dolardır?',
      kbg,
      [kbg * 10, kbg ~/ 10, kbg ~/ 100],
      '$gsyh milyar dolar = ${gsyh * 1000} milyon dolardır. Kişi başına gelir = '
          '${gsyh * 1000} milyon dolar / $nufus milyon kişi = $kbg dolar.',
      positive: true,
    );
  }
  final oran = 50 + 2 * a; // %50 … %98
  final ithalat = 50 * (3 + b + 20 * q); // milyon dolar
  final ihracat = ithalat * oran ~/ 100;
  if (bicim == 0) {
    return secenekli(
      'Bir ülkenin yıllık ihracatı $ihracat milyon dolar, ithalatı $ithalat milyon dolardır. '
          'Bu ülkede ihracatın ithalatı karşılama oranı yüzde kaçtır?',
      '%$oran',
      [
        '%${100 - oran}',
        '%${(10000 / oran).round()}',
        '%${oran + 10}',
        '%${oran - 10}',
        '%${oran + 5}',
      ],
      'Karşılama oranı = ihracat / ithalat × 100 = $ihracat / $ithalat × 100 = %$oran.',
    );
  }
  final acik = ithalat - ihracat;
  return sayisal(
    'Yıllık ithalatı $ithalat milyon dolar olan bir ülkede ihracatın ithalatı karşılama oranı '
        '%$oran olarak hesaplanmıştır. Bu ülkenin dış ticaret açığı kaç milyon dolardır?',
    acik,
    [ihracat, ithalat + ihracat, ithalat - oran],
    'İhracat = $ithalat × $oran / 100 = $ihracat milyon dolardır. '
        'Dış ticaret açığı = ithalat − ihracat = $ithalat − $ihracat = $acik milyon dolar.',
    positive: true,
  );
}

// ────────────────────────────── Tarih yardımcıları ──────────────────────────

String _altkume(int maske) => switch (maske) {
  1 => 'Yalnız I',
  2 => 'Yalnız II',
  4 => 'Yalnız III',
  3 => 'I ve II',
  5 => 'I ve III',
  6 => 'II ve III',
  _ => 'I, II ve III',
};

/// Öncüllü soru: doğru yanıt [maske] ile verilen alt kümedir (bit 0 → I).
AdvancedItem _oncullu(String kok, int maske, int i, String aciklama) {
  assert(maske >= 1 && maske <= 7);
  const hepsi = [1, 2, 4, 3, 5, 6, 7];
  final kay = i ~/ 3 % 7;
  final sirali = [...hepsi.sublist(kay), ...hepsi.sublist(0, kay)];
  return secenekli(
    kok,
    _altkume(maske),
    sirali.where((x) => x != maske).map(_altkume),
    aciklama,
  );
}

String _liste(List<String> x) => 'I. ${x[0]}\nII. ${x[1]}\nIII. ${x[2]}\n';

/// (öge, değer) çizelgesinden üçlü seçer. Değerler birbirinden farklıysa
/// sıralı eşleştirme, değilse (ya da her dört vakadan birinde) öncüllü soru üretir.
AdvancedItem _ucluOlgu(
  int i,
  List<(String, String)> tablo, {
  required String eslestirme,
  required String Function(String deger) oncul,
  required String Function(List<String> degerler) aciklama,
}) {
  final uclu = kombinasyon(tablo, 3, i);
  final d = ucluDizilimler[i % 6];
  final x = [for (final j in d) uclu[j]];
  final v = [for (final e in x) e.$2];
  final liste = _liste([for (final e in x) e.$1]);
  if (v.toSet().length == 3 && i % 4 != 3) {
    final kay = 1 + i ~/ 6 % 5;
    final diger = [
      ...ucluDizilimler.sublist(kay),
      ...ucluDizilimler.sublist(1, kay),
    ];
    return secenekli('$liste$eslestirme', v.join(' – '), [
      for (final p in diger) [for (final j in p) v[j]].join(' – '),
    ], aciklama(v));
  }
  final sorulan = v[i ~/ 6 % 3];
  var maske = 0;
  for (var j = 0; j < 3; j++) {
    if (v[j] == sorulan) maske |= 1 << j;
  }
  return _oncullu('$liste${oncul(sorulan)}', maske, i, aciklama(v));
}

// ─────────────────────────── 13 · Yüzyıl hesabı ─────────────────────────────

final _kalanlar = [
  for (var r = 2; r < 100; r++)
    if (!const {25, 26, 50, 51, 75, 76}.contains(r)) r,
];
const _yuzyilOlay = [
  'imzalanan bir antlaşma',
  'yapılan bir savaş',
  'kurulan bir kent',
  'dikilen bir yazıt',
  'çıkarılan bir kanun',
  'yapılan bir köprü',
];
const _sureOlay = [
  ('Bir kent', 'kurulmuş', 'bir depremle yıkılmıştır'),
  ('Bir tapınak', 'yapılmış', 'onarılmıştır'),
  ('Bir yazıt', 'dikilmiş', 'başka bir kente taşınmıştır'),
  ('Bir liman', 'kurulmuş', 'terk edilmiştir'),
];
const _ceyrekAdi = ['ilk', 'ikinci', 'üçüncü', 'son'];

AdvancedItem _yuzyil(int i) {
  final bicim = i % 4, k = i ~/ 4;
  if (bicim == 3) {
    final mo = 110 + 37 * (k % 50), ms = 105 + 73 * (k ~/ 50);
    final olay = sec(_sureOlay, k);
    final t = mo + ms, fark = (mo - ms).abs(), sira = hedefSira(i);
    // Çeldiriciler 2 × 2 düzenindedir: iki tipik hata (toplamak yerine çıkarma;
    // yüzler ya da onlar basamağında elde hatası) ayrı ayrı ve birlikte verilir.
    // Böylece çeldiricilerin hepsi anahtarın tek basamaklı sapması olmaz ve basamak
    // benzerliği anahtarı göstermez. Anahtarın değer sırası [sira] ile belirlenir;
    // kökteki yıllarla aynı olan değer atlanır.
    final duzen = switch (sira) {
      0 => [t + 100, t + 10, t + 110],
      1 => [t + 100, t - 10, t + 90],
      2 => [fark, t + 100, fark + 100],
      _ =>
        fark > 100 ? [fark, t - 100, fark - 100] : [t - 100, t - 10, t - 110],
    };
    return _sayisalTipik(
      '${olay.$1} M.Ö. $mo yılında ${olay.$2}, M.S. $ms yılında ${olay.$3}. Milattan önceki bir '
          'tarih ile milattan sonraki bir tarih arasındaki süre iki tarihin toplanmasıyla '
          'bulunduğuna göre bu iki olay arasında kaç yıl vardır?',
      t,
      [
        ...duzen,
        fark,
        t + 100,
        fark + 100,
        t - 100,
        t + 10,
        t - 10,
      ].where((x) => x != mo && x != ms),
      'Tarihlerden biri milattan önce, diğeri milattan sonra olduğundan yıllar toplanır: '
          '$mo + $ms = ${mo + ms} yıl.',
      sira,
      unit: 'yıl',
    );
  }
  final mo = bicim == 2;
  final ceyrek = mo ? k.isOdd : bicim == 1;
  final kk = mo ? k ~/ 2 : k;
  final yuz = kk ~/ 64;
  final kalan =
      _kalanlar[((kk % 64) * 29 + (mo ? 57 : (ceyrek ? 31 : 0))) % 92];
  final yil = yuz * 100 + kalan;
  final n = yuz + 1;
  final parca = ceyrek ? 4 : 2, boy = 100 ~/ parca;
  // Yüzyıl içindeki sıra: M.S. için baştan, M.Ö. için geriye doğru sayılır.
  final konum = mo ? (100 - kalan) ~/ boy : (kalan - 1) ~/ boy;
  final on = mo ? 'M.Ö.' : 'M.S.';
  String ad(int yy, int j) =>
      '${mo ? 'M.Ö. ' : ''}$yy. yüzyılın ${ceyrek ? '${_ceyrekAdi[j]} çeyreği' : '${j == 0 ? 'ilk' : 'ikinci'} yarısı'}';
  // Çeldiriciler 2 × 2 düzenindedir: yüzyıl hatası ile parça hatası (yarıyı ya da
  // çeyreği ters uçtan sayma) ayrı ayrı ve birlikte verilir; her yüzyıl ve her
  // parça adı ikişer seçenekte görünür. Yüzyıl hatası vakaların yarısında yılın ilk
  // basamaklarını yüzyıl sanmak (bir eksik), yarısında yüzyılı bir fazla saymaktır;
  // böylece anahtarın yüzyılı seçeneklerdeki iki yüzyılın büyüğü de küçüğü de olur.
  final komsu = yuz >= 1 && hedefSira(i, 11) < 2 ? n - 1 : n + 1;
  final yanlis = ceyrek
      ? [ad(n, 3 - konum), ad(komsu, konum), ad(komsu, 3 - konum)]
      : [
          ad(n, 1 - konum),
          ad(komsu, konum),
          ad(komsu, 1 - konum),
          ad(n + 1, konum),
        ];
  final (bas, son) = mo
      ? (yuz * 100 + 100 - boy * konum, yuz * 100 + 101 - boy * (konum + 1))
      : (yuz * 100 + boy * konum + 1, yuz * 100 + boy * (konum + 1));
  final aralik = mo
      ? '${yuz * 100 + 100}–${yuz * 100 + 1}'
      : '${yuz * 100 + 1}–${yuz * 100 + 100}';
  final parcaAdi = ceyrek
      ? '${_ceyrekAdi[konum]} çeyreği'
      : '${konum == 0 ? 'ilk' : 'ikinci'} yarısı';
  return secenekli(
    '$on $yil yılında ${sec(_yuzyilOlay, kk + bicim)} hangi yüzyılın hangi '
        '${ceyrek ? 'çeyreğine' : 'yarısına'} tarihlenir?',
    ad(n, konum),
    yanlis,
    '$on $yil yılı, $on $aralik yıllarını kapsayan $n. yüzyıldadır. '
        '${mo ? 'Milattan önce yıllar geriye doğru sayılır. ' : ''}'
        'Bu yüzyılın $parcaAdi $bas–$son yıllarıdır.',
  );
}

// ─────────────────────────── 14 · Kronoloji ─────────────────────────────────

// Her gelişmenin yılı çizelgede tektir; böylece hiçbir üçlüde aynı yıla ait
// iki gelişme bulunmaz.
const _kronoloji = <(int, String)>[
  (375, "Kavimler Göçü'nün başlaması"),
  (552, "Birinci Köktürk Devleti'nin kurulması"),
  (622, "Hicret'in gerçekleşmesi"),
  (751, 'Talas Savaşı'),
  (1040, 'Dandanakan Savaşı'),
  (1048, 'Pasinler Savaşı'),
  (1071, 'Malazgirt Savaşı'),
  (1176, 'Miryokefalon Savaşı'),
  (1187, 'Hıttin Savaşı'),
  (1215, "Magna Carta'nın ilan edilmesi"),
  (1230, 'Yassıçemen Savaşı'),
  (1243, 'Kösedağ Savaşı'),
  (1260, 'Ayn Calut Savaşı'),
  (1299, "Osmanlı Beyliği'nin kurulması"),
  (1326, "Bursa'nın fethedilmesi"),
  (1389, 'Birinci Kosova Savaşı'),
  (1396, 'Niğbolu Savaşı'),
  (1402, 'Ankara Savaşı'),
  (1444, 'Varna Savaşı'),
  (1453, "İstanbul'un fethedilmesi"),
  (1473, 'Otlukbeli Savaşı'),
  (1492, "Kristof Kolomb'un Amerika kıtasına ulaşması"),
  (1514, 'Çaldıran Savaşı'),
  (1516, 'Mercidabık Savaşı'),
  (1517, 'Ridaniye Savaşı'),
  (1526, 'Mohaç Meydan Muharebesi'),
  (1538, 'Preveze Deniz Savaşı'),
  (1555, 'Amasya Antlaşması'),
  (1571, 'İnebahtı Deniz Savaşı'),
  (1590, 'Ferhat Paşa Antlaşması'),
  (1606, 'Zitvatorok Antlaşması'),
  (1639, 'Kasr-ı Şirin Antlaşması'),
  (1648, 'Vestfalya Antlaşması'),
  (1683, 'İkinci Viyana Kuşatması'),
  (1699, 'Karlofça Antlaşması'),
  (1711, 'Prut Antlaşması'),
  (1718, 'Pasarofça Antlaşması'),
  (1739, 'Belgrad Antlaşması'),
  (1774, 'Küçük Kaynarca Antlaşması'),
  (1789, "Fransız İhtilali'nin başlaması"),
  (1792, 'Yaş Antlaşması'),
  (1808, "Sened-i İttifak'ın imzalanması"),
  (1826, "Yeniçeri Ocağı'nın kaldırılması"),
  // Yıl verilmeden 1713 tarihli Edirne Antlaşması'ndan ayırt edilsin diye niteleme eklendi.
  (1829, "Yunanistan'ın bağımsızlığının tanındığı Edirne Antlaşması"),
  (1833, 'Hünkâr İskelesi Antlaşması'),
  (1838, 'Balta Limanı Ticaret Antlaşması'),
  (1839, "Tanzimat Fermanı'nın ilan edilmesi"),
  (1856, "Islahat Fermanı'nın ilan edilmesi"),
  (1876, "Kanun-ı Esasi'nin ilan edilmesi"),
  (1878, 'Berlin Antlaşması'),
  (1881, 'Düyun-ı Umumiye İdaresinin kurulması'),
  (1908, "İkinci Meşrutiyet'in ilan edilmesi"),
  (1912, 'Uşi Antlaşması'),
  (1913, 'Bâbıâli Baskını'),
  (1914, "Birinci Dünya Savaşı'nın başlaması"),
  (1918, 'Mondros Ateşkes Antlaşması'),
  (1919, 'Sivas Kongresi'),
  (1920, 'Türkiye Büyük Millet Meclisinin açılması'),
  (1921, 'Sakarya Meydan Muharebesi'),
  (1922, 'Saltanatın kaldırılması'),
  (1923, 'Cumhuriyetin ilan edilmesi'),
  (1924, 'Halifeliğin kaldırılması'),
  (1925, "Şapka Kanunu'nun kabul edilmesi"),
  (1926, "Türk Medeni Kanunu'nun kabul edilmesi"),
  (1928, 'Yeni Türk harflerinin kabul edilmesi'),
  (1934, "Soyadı Kanunu'nun kabul edilmesi"),
  (1936, "Montrö Boğazlar Sözleşmesi'nin imzalanması"),
  (1939, "Hatay'ın Türkiye'ye katılması"),
];

AdvancedItem _kronolojiSoru(int i) {
  final uclu = kombinasyon(_kronoloji, 3, i);
  final d = ucluDizilimler[i % 6];
  final x = [for (final j in d) uclu[j]];
  const rakam = ['I', 'II', 'III'];
  final sira = [0, 1, 2]..sort((p, q) => x[p].$1.compareTo(x[q].$1));
  String yaz(List<int> s) => s.map((j) => rakam[j]).join(' – ');
  final kay = i ~/ 6 % 6;
  final hepsi = [for (final p in ucluDizilimler) yaz(p)];
  return secenekli(
    '${_liste([for (final e in x) e.$2])}'
        'Bu gelişmelerin kronolojik olarak eskiden yeniye doğru sıralanışı hangi seçenekte '
        'doğru verilmiştir?',
    yaz(sira),
    [
      yaz(sira.reversed.toList()),
      ...hepsi.sublist(kay),
      ...hepsi.sublist(0, kay),
    ],
    'Kronolojik sıra: ${sira.map((j) => '${x[j].$2} (${x[j].$1})').join(', ')}.',
  );
}

// ─────────────────────────── 15 · Antlaşmalar ───────────────────────────────

// (antlaşma, taraf çiftleri). Çok taraflı kongre antlaşmaları ve taraflığı
// tartışmaya açık olanlar bilerek dışarıda bırakılmıştır.
const _osm = 'Osmanlı Devleti ile';
const _tbmm = 'TBMM Hükûmeti ile';
const _itilaf = 'İtilaf Devletleri ile';
const _antlasmalar = <(String, List<String>)>[
  ('Kadeş Antlaşması', ['Hititler ile Mısırlılar']),
  ('Edirne-Segedin Antlaşması', ['$_osm Macaristan']),
  ('Amasya Antlaşması', ['$_osm Safevi Devleti']),
  ('Ferhat Paşa Antlaşması', ['$_osm Safevi Devleti']),
  ('Zitvatorok Antlaşması', ['$_osm Avusturya']),
  ('Nasuh Paşa Antlaşması', ['$_osm Safevi Devleti']),
  ('Serav Antlaşması', ['$_osm Safevi Devleti']),
  ('Kasr-ı Şirin Antlaşması', ['$_osm Safevi Devleti']),
  ('Vasvar Antlaşması', ['$_osm Avusturya']),
  ('Bucaş Antlaşması', ['$_osm Lehistan']),
  ('Bahçesaray Antlaşması', ['$_osm Rusya']),
  ('1700 tarihli İstanbul Antlaşması', ['$_osm Rusya']),
  ('Prut Antlaşması', ['$_osm Rusya']),
  ('Pasarofça Antlaşması', ['$_osm Avusturya', '$_osm Venedik']),
  ('1739 tarihli Belgrad Antlaşması', ['$_osm Avusturya', '$_osm Rusya']),
  ('Küçük Kaynarca Antlaşması', ['$_osm Rusya']),
  ('Ziştovi Antlaşması', ['$_osm Avusturya']),
  ('Yaş Antlaşması', ['$_osm Rusya']),
  ('1812 tarihli Bükreş Antlaşması', ['$_osm Rusya']),
  ('1829 tarihli Edirne Antlaşması', ['$_osm Rusya']),
  ('Hünkâr İskelesi Antlaşması', ['$_osm Rusya']),
  ('Kütahya Antlaşması', ['$_osm Mısır Valisi Kavalalı Mehmet Ali Paşa']),
  ('Balta Limanı Ticaret Antlaşması', ['$_osm İngiltere']),
  ('Ayastefanos Antlaşması', ['$_osm Rusya']),
  ('Uşi Antlaşması', ['$_osm İtalya']),
  ('1913 tarihli İstanbul Antlaşması', ['$_osm Bulgaristan']),
  ('Atina Antlaşması', ['$_osm Yunanistan']),
  ('Versay Antlaşması', ['$_itilaf Almanya']),
  ('Sen Jermen Antlaşması', ['$_itilaf Avusturya']),
  ('Nöyyi Antlaşması', ['$_itilaf Bulgaristan']),
  ('Triyanon Antlaşması', ['$_itilaf Macaristan']),
  ('Gümrü Antlaşması', ['$_tbmm Ermenistan']),
  ('Moskova Antlaşması', ['$_tbmm Sovyet Rusya']),
  ('1921 tarihli Ankara Antlaşması', ['$_tbmm Fransa']),
];

AdvancedItem _antlasma(int i) {
  final uclu = kombinasyon(_antlasmalar, 3, i);
  final d = ucluDizilimler[i % 6];
  final x = [for (final j in d) uclu[j]];
  final e = x[i ~/ 6 % 3];
  final taraf = e.$2[i ~/ 18 % e.$2.length];
  var maske = 0;
  for (var j = 0; j < 3; j++) {
    if (x[j].$2.contains(taraf)) maske |= 1 << j;
  }
  String ozet((String, List<String>) a) => a.$2.length == 1
      ? '${a.$1} ${a.$2.first} arasında'
      : '${a.$1} hem ${a.$2.first} hem de ${a.$2.last} arasında';
  return _oncullu(
    '${_liste([for (final a in x) a.$1])}'
        'Bu antlaşmalardan hangileri $taraf arasında imzalanmıştır?',
    maske,
    i,
    '${x.map(ozet).join('; ')} imzalanmıştır.',
  );
}

// ─────────────────────────── 16 · Osmanlı padişahları ───────────────────────

const _padisahOlgu = <(String, String)>[
  ("Koyunhisar (Bafeus) Savaşı'nın kazanılması", 'Osman Bey'),
  ("Bursa'nın fethedilmesi", 'Orhan Bey'),
  ("Maltepe (Palekanon) Savaşı'nın kazanılması", 'Orhan Bey'),
  ("İznik'in fethedilmesi", 'Orhan Bey'),
  ("Karesioğulları Beyliği'nin Osmanlı topraklarına katılması", 'Orhan Bey'),
  ("Çimpe Kalesi'nin alınarak Rumeli'ye geçilmesi", 'Orhan Bey'),
  ('Yaya ve müsellem adıyla ilk düzenli ordunun kurulması', 'Orhan Bey'),
  ("Sırpsındığı Savaşı'nın kazanılması", 'I. Murad'),
  ("Çirmen Savaşı'nın kazanılması", 'I. Murad'),
  ("Birinci Kosova Savaşı'nın kazanılması", 'I. Murad'),
  ('Rumeli Beylerbeyliğinin kurulması', 'I. Murad'),
  ("Niğbolu Savaşı'nın kazanılması", 'Yıldırım Bayezid'),
  ("Ankara Savaşı'nın kaybedilmesi", 'Yıldırım Bayezid'),
  ("Anadolu Hisarı'nın yaptırılması", 'Yıldırım Bayezid'),
  ('Anadolu Beylerbeyliğinin kurulması', 'Yıldırım Bayezid'),
  ("Fetret Devri'nin sona erdirilmesi", 'Çelebi Mehmed'),
  ("Şeyh Bedreddin İsyanı'nın bastırılması", 'Çelebi Mehmed'),
  ("Edirne-Segedin Antlaşması'nın imzalanması", 'II. Murad'),
  ("İkinci Kosova Savaşı'nın kazanılması", 'II. Murad'),
  ("İstanbul'un fethedilmesi", 'Fatih Sultan Mehmed'),
  ("Otlukbeli Savaşı'nın kazanılması", 'Fatih Sultan Mehmed'),
  ("Kırım'ın Osmanlı egemenliğine girmesi", 'Fatih Sultan Mehmed'),
  ("Trabzon Rum İmparatorluğu'na son verilmesi", 'Fatih Sultan Mehmed'),
  ("Rumeli Hisarı'nın yaptırılması", 'Fatih Sultan Mehmed'),
  ("Kanunname-i Âli Osman'ın hazırlanması", 'Fatih Sultan Mehmed'),
  ('Cem Sultan olayının yaşanması', 'II. Bayezid'),
  ("Şahkulu İsyanı'nın çıkması", 'II. Bayezid'),
  ("Çaldıran Savaşı'nın kazanılması", 'Yavuz Sultan Selim'),
  ("Mercidabık Savaşı'nın kazanılması", 'Yavuz Sultan Selim'),
  ("Ridaniye Savaşı'nın kazanılması", 'Yavuz Sultan Selim'),
  ('Halifeliğin Osmanlılara geçmesi', 'Yavuz Sultan Selim'),
  ("Belgrad'ın fethedilmesi", 'Kanuni Sultan Süleyman'),
  ("Rodos'un fethedilmesi", 'Kanuni Sultan Süleyman'),
  ("Mohaç Meydan Muharebesi'nin kazanılması", 'Kanuni Sultan Süleyman'),
  ("Birinci Viyana Kuşatması'nın yapılması", 'Kanuni Sultan Süleyman'),
  ("Preveze Deniz Savaşı'nın kazanılması", 'Kanuni Sultan Süleyman'),
  ("Amasya Antlaşması'nın imzalanması", 'Kanuni Sultan Süleyman'),
  ("Zigetvar Seferi'nin yapılması", 'Kanuni Sultan Süleyman'),
  ("Kıbrıs'ın fethedilmesi", 'II. Selim'),
  ("İnebahtı Deniz Savaşı'nın kaybedilmesi", 'II. Selim'),
  ("Ferhat Paşa Antlaşması'nın imzalanması", 'III. Murad'),
  ("Zitvatorok Antlaşması'nın imzalanması", 'I. Ahmed'),
  ('Ekber ve erşed sisteminin getirilmesi', 'I. Ahmed'),
  ("Hotin Seferi'nin yapılması", 'II. Osman'),
  ('Revan ve Bağdat seferlerinin yapılması', 'IV. Murad'),
  ("Kasr-ı Şirin Antlaşması'nın imzalanması", 'IV. Murad'),
  ("Vasvar Antlaşması'nın imzalanması", 'IV. Mehmed'),
  ("Girit'in fethinin tamamlanması", 'IV. Mehmed'),
  ("Bucaş Antlaşması'nın imzalanması", 'IV. Mehmed'),
  ("İkinci Viyana Kuşatması'nın yapılması", 'IV. Mehmed'),
  ("Karlofça Antlaşması'nın imzalanması", 'II. Mustafa'),
  ("Prut Antlaşması'nın imzalanması", 'III. Ahmed'),
  ("Pasarofça Antlaşması'nın imzalanması", 'III. Ahmed'),
  ('İlk Türk matbaasının kurulması', 'III. Ahmed'),
  ("Patrona Halil İsyanı'nın çıkması", 'III. Ahmed'),
  ("1739 tarihli Belgrad Antlaşması'nın imzalanması", 'I. Mahmud'),
  ("Küçük Kaynarca Antlaşması'nın imzalanması", 'I. Abdülhamid'),
  ("Ziştovi Antlaşması'nın imzalanması", 'III. Selim'),
  ("Yaş Antlaşması'nın imzalanması", 'III. Selim'),
  ("Nizam-ı Cedid Ordusu'nun kurulması", 'III. Selim'),
  ("Kabakçı Mustafa İsyanı'nın çıkması", 'III. Selim'),
  ("Sened-i İttifak'ın imzalanması", 'II. Mahmud'),
  ("Yeniçeri Ocağı'nın kaldırılması", 'II. Mahmud'),
  ("1829 tarihli Edirne Antlaşması'nın imzalanması", 'II. Mahmud'),
  ('Takvim-i Vekayi gazetesinin çıkarılması', 'II. Mahmud'),
  ("Hünkâr İskelesi Antlaşması'nın imzalanması", 'II. Mahmud'),
  ("Balta Limanı Ticaret Antlaşması'nın imzalanması", 'II. Mahmud'),
  ("Tanzimat Fermanı'nın ilan edilmesi", 'Abdülmecid'),
  ("Kırım Savaşı'nın yapılması", 'Abdülmecid'),
  ('Osmanlı Devleti\'nin ilk dış borcunu alması', 'Abdülmecid'),
  ("Islahat Fermanı'nın ilan edilmesi", 'Abdülmecid'),
  ("Bir Osmanlı padişahının ilk kez Avrupa'ya resmî gezi yapması", 'Abdülaziz'),
  ("Kanun-ı Esasi'nin ilan edilmesi", 'II. Abdülhamid'),
  ("1877-1878 Osmanlı-Rus Savaşı'nın (93 Harbi) yapılması", 'II. Abdülhamid'),
  ("Berlin Antlaşması'nın imzalanması", 'II. Abdülhamid'),
  ('Düyun-ı Umumiye İdaresinin kurulması', 'II. Abdülhamid'),
  ("İkinci Meşrutiyet'in ilan edilmesi", 'II. Abdülhamid'),
];

AdvancedItem _padisah(int i) => _ucluOlgu(
  i,
  _padisahOlgu,
  eslestirme:
      'Bu gelişmelerin yaşandığı dönemlerde Osmanlı tahtında bulunan hükümdarlar '
      'sırasıyla hangi seçenekte doğru verilmiştir?',
  oncul: (p) => 'Bu gelişmelerden hangileri $p döneminde yaşanmıştır?',
  aciklama: (v) =>
      'Birinci gelişme ${v[0]}, ikinci gelişme ${v[1]}, üçüncü gelişme ${v[2]} '
      'dönemindedir.',
);

// ─────────────────────────── 17 · İnkılaplar ────────────────────────────────

// (gelişme, yıl, alan). Alanı ders kitaplarında tek biçimde verilmeyenlerde
// alan boş bırakılmıştır; bu gelişmeler yalnız yıl sorularında kullanılır.
const _inkilaplar = <(String, int, String?)>[
  ('Saltanatın kaldırılması', 1922, 'siyasi'),
  ('Halk Fırkasının kurulması', 1923, 'siyasi'),
  ("İzmir İktisat Kongresi'nin toplanması", 1923, 'ekonomi'),
  ("Ankara'nın başkent olması", 1923, 'siyasi'),
  ('Cumhuriyetin ilan edilmesi', 1923, 'siyasi'),
  ('Halifeliğin kaldırılması', 1924, 'siyasi'),
  ("Tevhid-i Tedrisat Kanunu'nun kabul edilmesi", 1924, 'eğitim'),
  ("Şer'iye ve Evkaf Vekâletinin kaldırılması", 1924, null),
  ('Türkiye İş Bankasının kurulması', 1924, 'ekonomi'),
  ('Terakkiperver Cumhuriyet Fırkasının kurulması', 1924, 'siyasi'),
  ('Aşar vergisinin kaldırılması', 1925, 'ekonomi'),
  ("Şapka Kanunu'nun kabul edilmesi", 1925, 'toplumsal'),
  ('Tekke, zaviye ve türbelerin kapatılması', 1925, 'toplumsal'),
  ("Türk Medeni Kanunu'nun kabul edilmesi", 1926, null),
  ("Türk Ceza Kanunu'nun kabul edilmesi", 1926, 'hukuk'),
  ("Borçlar Kanunu'nun kabul edilmesi", 1926, 'hukuk'),
  ("Kabotaj Kanunu'nun kabul edilmesi", 1926, 'ekonomi'),
  ("Teşvik-i Sanayi Kanunu'nun çıkarılması", 1927, 'ekonomi'),
  ('Cumhuriyet Dönemi\'nin ilk nüfus sayımının yapılması', 1927, null),
  ("Nutuk'un Mustafa Kemal tarafından okunması", 1927, null),
  (
    'Anayasa\'dan "Devletin dini İslam\'dır." ifadesinin çıkarılması',
    1928,
    null,
  ),
  ('Yeni Türk harflerinin kabul edilmesi', 1928, 'eğitim'),
  ('Kadınlara belediye seçimlerine katılma hakkının verilmesi', 1930, null),
  ('Serbest Cumhuriyet Fırkasının kurulması', 1930, 'siyasi'),
  (
    'Türk Tarihi Tetkik Cemiyetinin (Türk Tarih Kurumu) kurulması',
    1931,
    'eğitim',
  ),
  ('Ölçü ve tartı birimlerinin değiştirilmesi', 1931, 'toplumsal'),
  ('Türk Dili Tetkik Cemiyetinin (Türk Dil Kurumu) kurulması', 1932, 'eğitim'),
  ('Kadınlara muhtarlık seçimlerine katılma hakkının verilmesi', 1933, null),
  ("Üniversite Reformu'nun yapılması", 1933, 'eğitim'),
  ('Sümerbankın kurulması', 1933, 'ekonomi'),
  ("Soyadı Kanunu'nun kabul edilmesi", 1934, 'toplumsal'),
  ('Kadınlara milletvekili seçme ve seçilme hakkının verilmesi', 1934, null),
  ('Etibankın kurulması', 1935, 'ekonomi'),
  ('Maden Tetkik ve Arama Enstitüsünün kurulması', 1935, 'ekonomi'),
  ('Hafta sonu tatilinin cumadan pazara alınması', 1935, 'toplumsal'),
  ('Laiklik ilkesinin anayasaya girmesi', 1937, null),
];
const _alanSorusu = {
  'siyasi': 'siyasi alandaki',
  'hukuk': 'hukuk alanındaki',
  'eğitim': 'eğitim ve kültür alanındaki',
  'ekonomi': 'ekonomi alanındaki',
  'toplumsal': 'toplumsal alandaki',
};
const _alanAdi = {
  'siyasi': 'siyasi alan',
  'hukuk': 'hukuk alanı',
  'eğitim': 'eğitim ve kültür alanı',
  'ekonomi': 'ekonomi alanı',
  'toplumsal': 'toplumsal alan',
};

AdvancedItem _inkilap(int i) {
  final uclu = kombinasyon(_inkilaplar, 3, i);
  final d = ucluDizilimler[i % 6];
  final x = [for (final j in d) uclu[j]];
  final liste = _liste([for (final e in x) e.$1]);
  if (x.every((e) => e.$3 != null) && (i ~/ 6).isEven) {
    final alan = x[i ~/ 12 % 3].$3!;
    var maske = 0;
    for (var j = 0; j < 3; j++) {
      if (x[j].$3 == alan) maske |= 1 << j;
    }
    return _oncullu(
      '${liste}Türk inkılabı sürecindeki bu gelişmelerden hangileri ${_alanSorusu[alan]} '
          'çalışmalar arasında yer alır?',
      maske,
      i,
      '${x.map((e) => '${e.$1}: ${_alanAdi[e.$3]}').join('; ')}.',
    );
  }
  final yillar = [for (final e in x) e.$2];
  final aciklama = '${x.map((e) => '${e.$1}: ${e.$2}').join('; ')}.';
  if (yillar.toSet().length == 3 && i % 4 != 3) {
    final kay = 1 + i ~/ 6 % 5;
    final diger = [
      ...ucluDizilimler.sublist(kay),
      ...ucluDizilimler.sublist(1, kay),
    ];
    return secenekli(
      '${liste}Türk inkılabı sürecindeki bu gelişmelerin gerçekleştiği yıllar sırasıyla hangi '
      'seçenekte doğru verilmiştir?',
      yillar.join(' – '),
      [
        for (final p in diger) [for (final j in p) yillar[j]].join(' – '),
      ],
      aciklama,
    );
  }
  final yil = yillar[i ~/ 6 % 3];
  var maske = 0;
  for (var j = 0; j < 3; j++) {
    if (yillar[j] == yil) maske |= 1 << j;
  }
  return _oncullu(
    '${liste}Türk inkılabı sürecindeki bu gelişmelerden hangileri $yil yılında gerçekleşmiştir?',
    maske,
    i,
    aciklama,
  );
}

// ─────────────────── 18 · İlk Türk ve Türk-İslam devletleri ─────────────────

// Her bilgi, çizelgedeki devletlerden yalnız biri için doğrudur.
const _devletOlgu = <(String, String)>[
  ("Bilinen ilk hükümdarı Teoman'dır.", 'Asya Hun Devleti'),
  ('Mete Han döneminde orduda onlu sistemi uygulamıştır.', 'Asya Hun Devleti'),
  ('Tarihte bilinen ilk teşkilatlı Türk devletidir.', 'Asya Hun Devleti'),
  ('Balamir tarafından kurulmuştur.', 'Avrupa Hun Devleti'),
  ('En parlak dönemini Attila zamanında yaşamıştır.', 'Avrupa Hun Devleti'),
  ('Bumin Kağan tarafından kurulmuştur.', 'I. Köktürk Devleti'),
  (
    'Türk adını devlet adı olarak kullanan ilk devlettir.',
    'I. Köktürk Devleti',
  ),
  (
    'İstemi Yabgu döneminde İpek Yolu için Sasani ve Bizans ile ilişki kurmuştur.',
    'I. Köktürk Devleti',
  ),
  ('İlteriş Kutluk Kağan tarafından kurulmuştur.', 'II. Köktürk Devleti'),
  ('Orhun Yazıtları bu devlet döneminde dikilmiştir.', 'II. Köktürk Devleti'),
  (
    'Bilge Kağan, Kültigin ve Tonyukuk bu devletin yöneticileridir.',
    'II. Köktürk Devleti',
  ),
  ('Kutluk Bilge Kül Kağan tarafından kurulmuştur.', 'Uygur Devleti'),
  ("Başkenti Karabalgasun'dur (Ordubalık).", 'Uygur Devleti'),
  ("Bögü Kağan döneminde Maniheizm'i benimsemiştir.", 'Uygur Devleti'),
  ('Yerleşik hayata geçen ilk Türk devletidir.', 'Uygur Devleti'),
  ("Uygur Devleti'ne son vermiştir.", 'Kırgızlar'),
  ("Talas Savaşı'nda Abbasilerin yanında yer almıştır.", 'Karluklar'),
  ('Museviliği benimseyen Türk devletidir.', 'Hazarlar'),
  ("İstanbul'u kuşatan ilk Türk devletidir.", 'Avarlar'),
  ("Almış Han döneminde İslamiyet'i kabul etmiştir.", 'İtil Bulgarları'),
  (
    "Satuk Buğra Han döneminde İslamiyet'i resmî din olarak benimsemiştir.",
    'Karahanlılar',
  ),
  (
    "Kutadgu Bilig ve Divanü Lügati't-Türk bu devlet döneminde yazılmıştır.",
    'Karahanlılar',
  ),
  ('Alp Tigin tarafından kurulmuştur.', 'Gazneliler'),
  (
    "Sultan Mahmut döneminde Hindistan'a on yedi sefer düzenlemiştir.",
    'Gazneliler',
  ),
  (
    'Hükümdarı, sultan unvanını kullanan ilk Türk hükümdarı olmuştur.',
    'Gazneliler',
  ),
  ("Dandanakan Savaşı'nı kaybetmiştir.", 'Gazneliler'),
  ('Tuğrul ve Çağrı Beyler tarafından kurulmuştur.', 'Büyük Selçuklu Devleti'),
  ("Pasinler Savaşı'nda Bizans'ı yenmiştir.", 'Büyük Selçuklu Devleti'),
  ("Malazgirt Savaşı'nı kazanmıştır.", 'Büyük Selçuklu Devleti'),
  ('Nizamiye Medreselerini açmıştır.', 'Büyük Selçuklu Devleti'),
  (
    'Melikşah döneminde en geniş sınırlarına ulaşmıştır.',
    'Büyük Selçuklu Devleti',
  ),
  (
    'Celali Takvimi bu devlet döneminde hazırlanmıştır.',
    'Büyük Selçuklu Devleti',
  ),
  ("Katvan Savaşı'nda Karahıtaylara yenilmiştir.", 'Büyük Selçuklu Devleti'),
  ("Mısır'da kurulan ilk Türk-İslam devletidir.", 'Tolunoğulları'),
  ("Muhammed bin Tuğç tarafından Mısır'da kurulmuştur.", 'İhşidiler'),
  ('Selahaddin Eyyubi tarafından kurulmuştur.', 'Eyyubiler'),
  ("Hıttin Savaşı'nda Haçlıları yenerek Kudüs'ü almıştır.", 'Eyyubiler'),
  ("Ayn Calut Savaşı'nda Moğolları yenmiştir.", 'Memlükler'),
  ("Yavuz Sultan Selim'in Mısır Seferi sonunda yıkılmıştır.", 'Memlükler'),
  ("Yassıçemen Savaşı'nı kaybetmiştir.", 'Harzemşahlar'),
  ("Son hükümdarı Celaleddin Harzemşah'tır.", 'Harzemşahlar'),
  (
    'Kutalmışoğlu Süleyman Şah tarafından kurulmuştur.',
    'Türkiye Selçuklu Devleti',
  ),
  ("İlk başkenti İznik'tir.", 'Türkiye Selçuklu Devleti'),
  ("Miryokefalon Savaşı'nı kazanmıştır.", 'Türkiye Selçuklu Devleti'),
  ("Kösedağ Savaşı'nı kaybetmiştir.", 'Türkiye Selçuklu Devleti'),
  (
    'I. Alaeddin Keykubad zamanında en parlak dönemini yaşamıştır.',
    'Türkiye Selçuklu Devleti',
  ),
  ("Anadolu'da kurulan ilk Türk beyliğidir.", 'Saltuklular'),
  (
    "Anadolu'nun ilk medresesi olan Yağıbasan Medresesi'ni yaptırmıştır.",
    'Danişmentliler',
  ),
  ("Divriği Ulu Camii ve Darüşşifası'nı yaptırmıştır.", 'Mengücekliler'),
  ("Malabadi Köprüsü'nü yaptırmıştır.", 'Artuklular'),
  ("İzmir'de kurulmuş ve ilk Türk donanmasını oluşturmuştur.", 'Çaka Beyliği'),
];

AdvancedItem _devlet(int i) => _ucluOlgu(
  i,
  _devletOlgu,
  eslestirme:
      'Bu bilgilerin ait olduğu devletler ya da beylikler sırasıyla hangi seçenekte '
      'doğru verilmiştir?',
  oncul: (dv) => 'Bu bilgilerden hangileri $dv için doğrudur?',
  aciklama: (v) =>
      'Birinci bilgi ${v[0]}, ikinci bilgi ${v[1]}, üçüncü bilgi ${v[2]} '
      'ile ilgilidir.',
);

// ─────────────────────────── 19 · Millî Mücadele ────────────────────────────

// Her bilgi, çizelgedeki gelişmelerden yalnız biri için doğrudur.
const _mucadeleOlgu = <(String, String)>[
  (
    "Osmanlı Devleti'nin Birinci Dünya Savaşı'ndan çekildiği ateşkes antlaşmasıdır.",
    'Mondros Ateşkes Antlaşması',
  ),
  (
    'Yedinci maddesi, İtilaf Devletlerine güvenliklerini tehdit eden stratejik noktaları '
        'işgal etme hakkı tanımıştır.',
    'Mondros Ateşkes Antlaşması',
  ),
  (
    'İşgallere karşı protesto mitingleri düzenlenmesi istenmiştir.',
    'Havza Genelgesi',
  ),
  (
    "Millî Mücadele'nin gerekçesi, amacı ve yöntemi ilk kez belirtilmiştir.",
    'Amasya Genelgesi',
  ),
  (
    '"Milletin bağımsızlığını yine milletin azim ve kararı kurtaracaktır." ifadesi yer almıştır.',
    'Amasya Genelgesi',
  ),
  (
    'Toplanış amacı bakımından bölgesel, aldığı kararlar bakımından ulusal bir kongredir.',
    'Erzurum Kongresi',
  ),
  ('İlk kez bir Temsil Heyeti oluşturulmuştur.', 'Erzurum Kongresi'),
  (
    'Hem toplanış amacı hem de aldığı kararlar bakımından ulusal bir kongredir.',
    'Sivas Kongresi',
  ),
  (
    'Millî cemiyetler Anadolu ve Rumeli Müdafaa-i Hukuk Cemiyeti adı altında birleştirilmiştir.',
    'Sivas Kongresi',
  ),
  (
    'Temsil Heyetinin yetkisi bütün yurdu kapsayacak biçimde genişletilmiştir.',
    'Sivas Kongresi',
  ),
  (
    'Ali Fuat Paşa, Batı Cephesi Kuvayımilliye Komutanlığına atanmıştır.',
    'Sivas Kongresi',
  ),
  (
    'İrade-i Milliye gazetesinin çıkarılması kararlaştırılmıştır.',
    'Sivas Kongresi',
  ),
  (
    'İstanbul Hükûmeti, Temsil Heyetini resmen tanımıştır.',
    'Amasya Görüşmeleri',
  ),
  (
    'Temsil Heyeti adına Mustafa Kemal, İstanbul Hükûmeti adına Salih Paşa görüşmüştür.',
    'Amasya Görüşmeleri',
  ),
  ('Son Osmanlı Mebusan Meclisinde kabul edilmiştir.', 'Misakımillî'),
  (
    'Kars, Ardahan ve Batum için gerekirse halk oylamasına başvurulabileceği belirtilmiştir.',
    'Misakımillî',
  ),
  (
    "İstanbul'un resmen işgal edilmesi ve Mebusan Meclisinin dağıtılması üzerine gerçekleşmiştir.",
    "Türkiye Büyük Millet Meclisinin açılması",
  ),
  (
    'Osmanlı Mebusan Meclisinde onaylanmadığı için hukuken geçersiz sayılmıştır.',
    'Sevr Antlaşması',
  ),
  (
    'TBMM tarafından tanınmamış, imzalayanlar vatan haini ilan edilmiştir.',
    'Sevr Antlaşması',
  ),
  (
    "TBMM Hükûmetinin imzaladığı ilk uluslararası antlaşmadır.",
    'Gümrü Antlaşması',
  ),
  (
    "Ermenistan, Sevr Antlaşması'nı tanımadığını kabul etmiştir.",
    'Gümrü Antlaşması',
  ),
  (
    "Düzenli ordunun Batı Cephesi'nde kazandığı ilk zaferdir.",
    'Birinci İnönü Muharebesi',
  ),
  (
    "Ardından İtilaf Devletleri, TBMM Hükûmetini Londra Konferansı'na çağırmıştır.",
    'Birinci İnönü Muharebesi',
  ),
  ('Yeni Türk devletinin ilk anayasasıdır.', '1921 Anayasası'),
  // Kars Antlaşması'na Sovyet Rusya da katıldığından bilgi ikili antlaşmayı belirtir.
  (
    'TBMM Hükûmeti ile Sovyet Rusya arasında ikili olarak imzalanmıştır.',
    'Moskova Antlaşması',
  ),
  (
    "Batum'un Gürcistan'a bırakılmasıyla Misakımillî'den ilk kez ödün verilmiştir.",
    'Moskova Antlaşması',
  ),
  (
    'Mustafa Kemal, İsmet Paşa\'ya "Siz orada yalnız düşmanı değil, milletin makûs talihini de '
        'yendiniz." telgrafını çekmiştir.',
    'İkinci İnönü Muharebesi',
  ),
  (
    "Türk ordusu Sakarya Irmağı'nın doğusuna çekilmiştir.",
    'Kütahya-Eskişehir Muharebeleri',
  ),
  (
    "Ardından Mustafa Kemal'e Başkomutanlık yetkisi verilmiştir.",
    'Kütahya-Eskişehir Muharebeleri',
  ),
  (
    'Ordunun ihtiyaçlarını karşılamak için halktan yardım istenmiştir.',
    'Tekâlif-i Milliye Emirleri',
  ),
  (
    "Zaferin ardından Mustafa Kemal'e Gazi unvanı ve mareşal rütbesi verilmiştir.",
    'Sakarya Meydan Muharebesi',
  ),
  (
    '"Hattımüdafaa yoktur, sathımüdafaa vardır. O satıh bütün vatandır." emri verilmiştir.',
    'Sakarya Meydan Muharebesi',
  ),
  ('Türk ordusunun son savunma savaşıdır.', 'Sakarya Meydan Muharebesi'),
  ('Azerbaycan, Gürcistan ve Ermenistan ile imzalanmıştır.', 'Kars Antlaşması'),
  (
    'Fransa ile imzalanmış, Güney Cephesi kapanmıştır.',
    '1921 tarihli Ankara Antlaşması',
  ),
  ('Başkomutanlık Meydan Muharebesi ile sonuçlanmıştır.', 'Büyük Taarruz'),
  (
    '"Ordular, ilk hedefiniz Akdeniz\'dir. İleri!" emri verilmiştir.',
    'Büyük Taarruz',
  ),
  (
    'Doğu Trakya savaş yapılmadan kurtarılmıştır.',
    'Mudanya Ateşkes Antlaşması',
  ),
  (
    "İstanbul ve Boğazlar'ın yönetimi TBMM Hükûmetine bırakılmıştır.",
    'Mudanya Ateşkes Antlaşması',
  ),
  ('Kapitülasyonlar kesin olarak kaldırılmıştır.', 'Lozan Barış Antlaşması'),
  (
    'Yeni Türk devletinin bağımsızlığı uluslararası alanda tanınmıştır.',
    'Lozan Barış Antlaşması',
  ),
];

AdvancedItem _mucadele(int i) => _ucluOlgu(
  i,
  _mucadeleOlgu,
  eslestirme:
      "Millî Mücadele Dönemi'ne ait bu bilgilerin ilgili olduğu gelişmeler sırasıyla "
      'hangi seçenekte doğru verilmiştir?',
  oncul: (g) =>
      "Millî Mücadele Dönemi'ne ait bu bilgilerden hangileri “$g” için doğrudur?",
  aciklama: (v) =>
      'Birinci bilgi ${v[0]}, ikinci bilgi ${v[1]}, üçüncü bilgi ${v[2]} '
      'ile ilgilidir.',
);

// ─────────────────────────── 20 · Kurum ve kavramlar ────────────────────────

// Yalnız Türk-İslam devletleri ile Osmanlı Devleti'ne ait kurum ve kavramlar;
// İslamiyet öncesi Türk devletlerine ait olanlar (kut, kurultay, töre) alınmaz.
const _kavramlar = <(String, String)>[
  (
    'İkta',
    'Büyük Selçuklu Devleti\'nde toprak gelirlerinin hizmet karşılığında komutan ve '
        'görevlilere bırakılması',
  ),
  (
    'Atabey',
    'Selçuklularda meliklerin yetiştirilmesinden sorumlu olan deneyimli devlet adamı',
  ),
  (
    'Gulam sistemi',
    'Selçuklularda küçük yaşta alınan çocukların özel eğitimle asker ve yönetici olarak '
        'yetiştirilmesi',
  ),
  (
    'Divan-ı Saltanat',
    "Büyük Selçuklu Devleti'nde devlet işlerinin görüşüldüğü büyük divan",
  ),
  (
    'Divan-ı Mezalim',
    'Türk-İslam devletlerinde hükümdarın başkanlık ettiği, halkın şikâyetlerinin dinlendiği '
        'yüksek mahkeme',
  ),
  (
    'Ahilik',
    'Anadolu Selçuklu Dönemi\'nde esnaf ve zanaatkârların kurduğu dinî ve iktisadi '
        'dayanışma teşkilatı',
  ),
  ('Lonca', "Osmanlı Devleti'nde esnaf ve zanaatkârların meslek örgütü"),
  (
    'Divan-ı Hümayun',
    "Osmanlı Devleti'nde devlet işlerinin görüşülüp karara bağlandığı kurul",
  ),
  ('Sadrazam', "Osmanlı Devleti'nde padişahın mührünü taşıyan mutlak vekili"),
  (
    'Kazasker',
    'Divan-ı Hümayunda adalet ve eğitim işlerine bakan, kadı ve müderrisleri atayan üye',
  ),
  ('Defterdar', 'Divan-ı Hümayunda maliye işlerinden sorumlu üye'),
  (
    'Nişancı',
    'Divan-ı Hümayunda ferman ve beratlara padişahın tuğrasını çeken, tapu kayıtlarını tutan üye',
  ),
  (
    'Şeyhülislam',
    'Osmanlı Devleti\'nde ilmiye sınıfının başı olup kararların dine uygunluğu konusunda '
        'fetva veren görevli',
  ),
  (
    'Reisülküttap',
    'Osmanlı Devleti\'nde divan kâtiplerinin başı olup zamanla dış işlerine bakan görevli',
  ),
  ('Kaptanıderya', 'Osmanlı donanmasının başkomutanı'),
  ('Beylerbeyi', "Osmanlı Devleti'nde eyaletlerin en üst yöneticisi"),
  ('Sancak beyi', "Osmanlı Devleti'nde sancakların en üst yöneticisi"),
  (
    'Lala',
    'Osmanlı Devleti\'nde sancağa gönderilen şehzadeleri devlet yönetimi konusunda '
        'yetiştiren deneyimli devlet adamı',
  ),
  (
    'Kadı',
    'Osmanlı Devleti\'nde kazalarda yargı ve belediye işlerine bakan görevli',
  ),
  ('Subaşı', "Osmanlı Devleti'nde şehirlerin güvenliğini sağlayan görevli"),
  (
    'Muhtesip',
    'Çarşı ve pazarlarda fiyatları, ölçü ve tartıyı denetleyen görevli',
  ),
  (
    'Dirlik',
    'Osmanlı Devleti\'nde vergi gelirleri hizmet karşılığında asker ve görevlilere '
        'bırakılan topraklar',
  ),
  (
    'Cebelü',
    'Dirlik sahiplerinin gelirlerine göre yetiştirmek zorunda olduğu atlı asker',
  ),
  (
    'İltizam',
    'Bir bölgenin vergi gelirini toplama hakkının açık artırmayla ve peşin olarak belirli '
        'bir süreliğine satılması',
  ),
  (
    'Malikâne',
    'Vergi toplama hakkının kişilere ömür boyu verilmesi uygulaması',
  ),
  (
    'Devşirme',
    'Osmanlı Devleti\'nde Hristiyan ailelerin çocuklarının alınıp asker ve yönetici olarak '
        'yetiştirilmesi',
  ),
  (
    'Pençik',
    'Savaş esirlerinin beşte birinin asker yapılmak üzere devletçe alınması',
  ),
  (
    'Enderun',
    'Osmanlı sarayında devşirmelerin yönetici olarak yetiştirildiği saray okulu',
  ),
  (
    'Kapıkulu Ocakları',
    "Osmanlı Devleti'nde doğrudan padişaha bağlı olan maaşlı ve sürekli ordu",
  ),
  ('Ulufe', 'Kapıkulu askerlerine üç ayda bir ödenen maaş'),
  (
    'Cülus bahşişi',
    'Padişah tahta çıktığında kapıkulu askerlerine dağıtılan para',
  ),
  (
    'Akıncılar',
    'Sınır boylarında keşif ve yıpratma akınları yapan hafif süvari birlikleri',
  ),
  (
    'Cizye',
    'Gayrimüslim erkeklerden askerlik yapmamaları karşılığında alınan vergi',
  ),
  ('Öşür', 'Müslüman çiftçilerden ürünün onda biri oranında alınan vergi'),
  ('Haraç', 'Gayrimüslim çiftçilerden ürün üzerinden alınan vergi'),
  ('Ağnam', 'Küçükbaş hayvanlardan alınan vergi'),
  ('Avarız', 'Savaş gibi olağanüstü durumlarda halktan toplanan vergi'),
  (
    'Çift bozan',
    'Toprağını izinsiz terk eden ya da üç yıl üst üste boş bırakan köylüden alınan vergi',
  ),
  (
    'Müsadere',
    'Devlet görevlilerinin mal varlığına devlet tarafından el konulması',
  ),
  ('Narh', 'Devletin mallara en yüksek satış fiyatını belirlemesi'),
  (
    'Vakıf',
    'Bir kişinin malını toplum yararına hizmetler için kalıcı olarak bağışlamasıyla oluşan kurum',
  ),
  ('İmaret', 'Yoksullara ve yolculara ücretsiz yemek dağıtılan hayır kurumu'),
  (
    'Kervansaray',
    'Ticaret yolları üzerinde kervanların ve yolcuların konakladığı yapı',
  ),
  (
    'Darüşşifa',
    'Türk-İslam devletlerinde hastaların tedavi edildiği sağlık kurumu',
  ),
  ('Bedesten', 'Değerli malların alınıp satıldığı kapalı çarşı'),
  (
    'Sıbyan mektebi',
    "Osmanlı Devleti'nde ilköğretim düzeyinde eğitim veren mahalle okulu",
  ),
  ('Müderris', 'Medreselerde ders veren öğretim görevlisi'),
  ('Ferman', 'Padişahın herhangi bir konudaki yazılı emri'),
  ('Tuğra', 'Padişahın belgelerde kullanılan özel imza işareti'),
  (
    'Ekber ve erşed',
    'Hanedanın en yaşlı ve olgun erkek üyesinin tahta çıkmasını öngören veraset sistemi',
  ),
  (
    'Kafes usulü',
    'Şehzadelerin sancağa gönderilmeyip sarayda gözetim altında tutulması uygulaması',
  ),
  (
    'Millet sistemi',
    'Osmanlı toplumunun din ve mezhep esasına göre örgütlenmesi',
  ),
  (
    'Seyfiye',
    'Osmanlı Devleti\'nde yönetim ve askerlik görevlerini yürüten sınıf',
  ),
  (
    'İlmiye',
    'Osmanlı Devleti\'nde eğitim, yargı ve din işlerini yürüten sınıf',
  ),
  ('Kalemiye', 'Osmanlı Devleti\'nde yazışma ve maliye işlerini yürüten sınıf'),
  (
    'Reaya',
    'Osmanlı Devleti\'nde yönetime katılmayan, üretim yapıp vergi veren halk kesimi',
  ),
];

AdvancedItem _kavram(int i) {
  final uclu = kombinasyon(_kavramlar, 3, i);
  final d = ucluDizilimler[i % 6];
  final x = [for (final j in d) uclu[j]];
  final v = [for (final e in x) e.$1];
  final kay = 1 + i ~/ 6 % 5;
  final diger = [
    ...ucluDizilimler.sublist(kay),
    ...ucluDizilimler.sublist(1, kay),
  ];
  return secenekli(
    '${_liste([for (final e in x) e.$2])}'
        'Türk-İslam devletleri ile Osmanlı Devleti\'ndeki kurum ve kavramlara ait bu tanımların '
        'karşılıkları sırasıyla hangi seçenekte doğru verilmiştir?',
    v.join(' – '),
    [
      for (final p in diger) [for (final j in p) v[j]].join(' – '),
    ],
    'Birinci tanım ${v[0]}, ikinci tanım ${v[1]}, üçüncü tanım ${v[2]} kavramını açıklar.',
  );
}

// ─────────────────────────────── Aile listesi ───────────────────────────────

final lmCografyaTarih = <AdvancedFamily>[
  lmAile(
    'cog_yerel_saat',
    'Boylam farkından yerel saat ve zaman farkı',
    Topic.geography,
    Difficulty.medium,
    BloomLevel.uygulama,
    _yerelSaat,
    exam: ExamKind.tyt,
    lesson: 'Coğrafya',
    shortAnswer: false,
  ),
  lmAile(
    'cog_boylam',
    'Yerel saat farkından boylam bulma',
    Topic.geography,
    Difficulty.medium,
    BloomLevel.analiz,
    _boylamBul,
    exam: ExamKind.tyt,
    lesson: 'Coğrafya',
    shortAnswer: false,
  ),
  lmAile(
    'cog_olcek_uzunluk',
    'Kesir ölçekle harita ve gerçek uzunluk',
    Topic.geography,
    Difficulty.medium,
    BloomLevel.uygulama,
    _olcekUzunluk,
    exam: ExamKind.tyt,
    lesson: 'Coğrafya',
  ),
  lmAile(
    'cog_olcek_alan',
    'Ölçek bulma ve ölçekle alan hesabı',
    Topic.geography,
    Difficulty.hard,
    BloomLevel.uygulama,
    _olcekAlan,
    exam: ExamKind.tyt,
    lesson: 'Coğrafya',
  ),
  lmAile(
    'cog_egim',
    'Yükselti farkı ve yatay uzaklıktan eğim',
    Topic.geography,
    Difficulty.medium,
    BloomLevel.uygulama,
    _egim,
    exam: ExamKind.tyt,
    lesson: 'Coğrafya',
  ),
  lmAile(
    'cog_sicaklik_yukselti',
    'Yükseltiye bağlı gerçek ve indirgenmiş sıcaklık',
    Topic.geography,
    Difficulty.medium,
    BloomLevel.uygulama,
    _sicaklik,
    exam: ExamKind.tyt,
    lesson: 'Coğrafya',
  ),
  lmAile(
    'cog_paralel_mesafe',
    'Paraleller arası uzaklık ve enlem bulma',
    Topic.geography,
    Difficulty.medium,
    BloomLevel.uygulama,
    _paralel,
    exam: ExamKind.tyt,
    lesson: 'Coğrafya',
  ),
  lmAile(
    'cog_nufus_yogunlugu',
    'Aritmetik, tarımsal ve fizyolojik nüfus yoğunluğu',
    Topic.geography,
    Difficulty.medium,
    BloomLevel.uygulama,
    _nufusYogunlugu,
    exam: ExamKind.tyt,
    lesson: 'Coğrafya',
  ),
  lmAile(
    'cog_nufus_artisi',
    'Doğal nüfus artışı, göç ve nüfus değişimi',
    Topic.geography,
    Difficulty.medium,
    BloomLevel.uygulama,
    _nufusArtisi,
    exam: ExamKind.tyt,
    lesson: 'Coğrafya',
  ),
  lmAile(
    'cog_bagil_nem',
    'Mutlak nem, maksimum nem, bağıl nem ve nem açığı',
    Topic.geography,
    Difficulty.medium,
    BloomLevel.uygulama,
    _bagilNem,
    exam: ExamKind.tyt,
    lesson: 'Coğrafya',
  ),
  lmAile(
    'cog_bagimli_nufus',
    'Yaş grupları ve bağımlı nüfus oranı',
    Topic.geography,
    Difficulty.medium,
    BloomLevel.uygulama,
    _bagimliNufus,
    exam: ExamKind.ayt,
    lesson: 'Coğrafya-1',
  ),
  lmAile(
    'cog_dis_ticaret',
    'Dış ticaret dengesi, karşılama oranı ve kişi başı gelir',
    Topic.geography,
    Difficulty.medium,
    BloomLevel.uygulama,
    _disTicaret,
    exam: ExamKind.ayt,
    lesson: 'Coğrafya-1',
  ),
  lmSirali(
    'tar_yuzyil',
    'Yüzyıl, yarı ve çeyrek hesabı; M.Ö.–M.S. süre',
    Topic.history,
    Difficulty.easy,
    BloomLevel.uygulama,
    _yuzyil,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'tar_kronoloji',
    'Üç gelişmenin kronolojik sıralaması',
    Topic.history,
    Difficulty.medium,
    BloomLevel.anlama,
    _kronolojiSoru,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'tar_antlasma',
    'Antlaşmalar ve tarafları',
    Topic.history,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _antlasma,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'tar_osmanli_padisah',
    'Osmanlı padişahları ve dönemlerindeki gelişmeler',
    Topic.history,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _padisah,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'tar_inkilap',
    'Türk inkılabı: gelişmelerin yılı ve alanı',
    Topic.history,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _inkilap,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'tar_ilk_turk_islam',
    'İlk Türk devletleri ve Türk-İslam devletleri',
    Topic.history,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _devlet,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'tar_milli_mucadele',
    'Millî Mücadele: kongreler, savaşlar ve antlaşmalar',
    Topic.history,
    Difficulty.medium,
    BloomLevel.anlama,
    _mucadele,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'tar_kurum_kavram',
    'Türk-İslam ve Osmanlı teşkilatında kurum ve kavramlar',
    Topic.history,
    Difficulty.medium,
    BloomLevel.anlama,
    _kavram,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
];
