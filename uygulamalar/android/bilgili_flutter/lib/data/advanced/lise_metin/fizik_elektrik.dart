// Lise fizik metin aileleri: elektrik, manyetizma, dalgalar, çembersel
// hareket, optik ve modern fizik. Her aile 5.000 ayrı vaka üretir; veriler
// sonuçlar tam ya da kısa ondalıklı çıkacak biçimde seçilmiştir.
import 'dart:math' as math;

import 'denge.dart';
import 'ortak.dart';

/// (a, b, c) koordinatlarının sıra numarası (lmAile ile aynı düzen).
int _no(int a, int b, int c) => a + 25 * b + 500 * c;

/// [siraliCeldiriciler] gibi seçer: anahtardan küçük çeldirici sayısı [sira]
/// olur ve adaylar öncelik sırasıyla alınır. Ek kural: anahtarı seçilmiş bir
/// çeldiriciyle birlikte tam ortaya (aritmetik ya da geometrik ortalama)
/// alacak aday, aynı yanda başka aday kaldıkça ertelenir; böylece "ortadaki
/// değer" kestirimi anahtarı göstermez. Değerler seçeneklerde yazılan
/// değerlerdir.
List<String> _sirali(
  num anahtar,
  String anahtarYazim,
  Iterable<(num, String)> adaylar,
  int sira,
) {
  final kota = [sira.clamp(0, 3), 3 - sira.clamp(0, 3)];
  final secilen = <(num, String)>[];
  final ertelenen = <(num, String)>[], yedek = <(num, String)>[];
  bool yeni(String x) =>
      x.trim().isNotEmpty &&
      !ayniSecenek(x, anahtarYazim) &&
      ![...secilen, ...ertelenen, ...yedek].any((w) => ayniSecenek(w.$2, x));
  bool ortaYapar(num y) => secilen.any((s) {
    final x = s.$1;
    if ((x - anahtar) * (y - anahtar) >= 0) return false;
    if ((x + y - 2 * anahtar).abs() <= 1e-9 * (1 + anahtar.abs())) return true;
    return anahtar > 0 &&
        x > 0 &&
        y > 0 &&
        (math.sqrt(x * y) / anahtar - 1).abs() <= 0.02;
  });
  int yan(num x) => x < anahtar ? 0 : 1;
  for (final (deger, yazim) in adaylar) {
    if (secilen.length == 3) break;
    if (!yeni(yazim)) continue;
    if (kota[yan(deger)] == 0) {
      yedek.add((deger, yazim));
    } else if (ortaYapar(deger)) {
      ertelenen.add((deger, yazim));
    } else {
      secilen.add((deger, yazim));
      kota[yan(deger)]--;
    }
  }
  // Eksik kalırsa önce anahtarı ortaya almayan adaylarla (gerekirse öteki
  // yandan) tamamlanır; sıra hedefinden sapmak, ortadaki değer ipucundan
  // iyidir.
  for (final x in [...yedek, ...ertelenen]) {
    if (secilen.length < 3 && !ortaYapar(x.$1)) secilen.add(x);
  }
  for (final x in [...ertelenen, ...yedek]) {
    if (secilen.length == 3) break;
    if (!secilen.contains(x)) secilen.add(x);
  }
  if (secilen.length != 3) {
    throw StateError('Eksik çeldirici: $anahtarYazim → $secilen');
  }
  return [for (final s in secilen) s.$2];
}

/// Ondalıklı yanıtlı soru; anahtarın seçenekler içindeki değer sırası vakadan
/// vakaya [hedefSira] ile değişir ([sira] verilirse o kullanılır). [hatalar]
/// anahtarın iki yanındaki tipik hata değerleridir (öncelik sırasıyla);
/// yetmezse en sonda anahtarın yakın komşuları kullanılır. Komşu katsayıları
/// (1,2 · 0,75 · 1,5 · 0,6) bilerek bakışımsızdır: anahtar komşuların ortası
/// olmaz. Sıfıra yuvarlanan ya da yazımı değerinden %10'dan çok sapan adaylar
/// atılır.
AdvancedItem _ondalikSira(
  String prompt,
  double answer,
  List<double> hatalar,
  String explanation,
  int i, {
  required String unit,
  int digits = 2,
  int? sira,
}) {
  double yuvarla(double x) =>
      double.parse(tr(x, digits).replaceFirst(',', '.'));
  final adim = answer.abs() >= 20 ? 1.0 : (answer.abs() >= 2 ? 0.5 : 0.1);
  final aday = [
    for (final x in [
      ...hatalar,
      for (final m in const [1.2, 0.75, 1.5, 0.6]) answer * m,
      for (var k = 1; k <= 6; k++) ...[answer + k * adim, answer - k * adim],
    ])
      if (x.isFinite &&
          yuvarla(x) > 0 &&
          (yuvarla(x) - x).abs() <= 0.1 * x.abs())
        x,
  ];
  final yazim = birimli(tr(answer, digits), unit);
  return AdvancedItem(
    prompt,
    yazim,
    _sirali(yuvarla(answer), yazim, [
      for (final x in aday) (yuvarla(x), birimli(tr(x, digits), unit)),
    ], sira ?? hedefSira(i)),
    explanation,
  );
}

/// Tam sayı yanıtlı soru; [_ondalikSira] gibi, komşular yuvarlanarak eklenir.
AdvancedItem _sayiSira(
  String prompt,
  int answer,
  List<int> hatalar,
  String explanation,
  int i, {
  String unit = '',
}) {
  final adim = answer.abs() >= 200 ? 10 : (answer.abs() >= 40 ? 5 : 1);
  final aday = [
    ...hatalar,
    for (final m in const [1.2, 0.75, 1.5, 0.6]) (answer * m).round(),
    for (var k = 1; k <= 6; k++) ...[answer + k * adim, answer - k * adim],
  ].where((x) => x > 0);
  final yazim = birimli('$answer', unit);
  return AdvancedItem(
    prompt,
    yazim,
    _sirali(answer, yazim, [
      for (final x in aday) (x, birimli('$x', unit)),
    ], hedefSira(i)),
    explanation,
  );
}

AdvancedFamily _fe(
  String key,
  String title,
  Difficulty difficulty,
  BloomLevel bloom,
  LmUretec build, {
  bool tyt = false,
}) => lmAile(
  'fe_$key',
  title,
  Topic.physics,
  difficulty,
  bloom,
  build,
  exam: tyt ? ExamKind.tyt : ExamKind.ayt,
  lesson: 'Fizik',
);

/// Aralarında asal, birbirinden farklı (p, q) ikilileri: orantı soruları.
const _oranlar = <(int, int)>[
  (1, 2), (2, 1), (1, 3), (3, 1), (1, 4), (4, 1), (1, 5), (5, 1),
  (2, 3), (3, 2), (2, 5), (5, 2), (3, 4), (4, 3), (3, 5), (5, 3),
  (4, 5), (5, 4), (1, 6), (6, 1),
];

/// Paralel (dirençte) ya da seri (sığada) eşdeğeri tam sayı olan ikililer.
const _tamParalel = <(int, int)>[
  (3, 6), (6, 3), (6, 12), (12, 6), (9, 18), (18, 9), (12, 24), (24, 12),
  (4, 12), (12, 4), (8, 24), (24, 8), (10, 15), (15, 10), (20, 30),
  (30, 20), (5, 20), (20, 5), (10, 40), (40, 10), (6, 30), (30, 6),
  (15, 30), (30, 15), (12, 36),
];

/// Uzunluk ve kesit katsayıları (birbirinden farklı).
final _telOran = <(int, int)>[
  for (var l = 2; l <= 6; l++)
    for (var s = 2; s <= 6; s++)
      if (l != s) (l, s),
];

const _omikIletken = [
  'Bir reosta telinin',
  'Bir ısıtıcı telinin',
  'Omik bir direncin',
  'Krom-nikel bir telin',
  'Bir bobin sargısının',
];

const _isiticilar = [
  'bir elektrikli ısıtıcı',
  'bir klima',
  'bir elektrikli fırın',
  'bir kurutma makinesi',
  'bir su ısıtıcısı',
];

/// (açı, 10·sin, 10·cos); cos yalnız 37° ve 53° için kullanılır.
const _acilar = <(int, int, int)>[
  (90, 10, 0), (30, 5, 0), (37, 6, 8), (53, 8, 6), (150, 5, 0),
];

/// Transformatörde primer : sekonder sarım oranları.
const _sarimOran = <(int, int)>[
  (2, 1), (3, 1), (4, 1), (5, 1), (10, 1), (1, 2), (1, 3), (1, 4), (1, 5),
  (1, 10), (3, 2), (2, 3), (5, 2), (2, 5), (4, 3), (3, 4), (5, 3), (3, 5),
  (5, 4), (4, 5),
];

/// (kütle katı, yarıçap katı): Dünya'ya göre gezegen; g oranı 1 olmaz.
const _gezegenler = <(int, int)>[
  (16, 2), (2, 2), (3, 2), (6, 2), (8, 2), (10, 2), (12, 2), (18, 3),
  (27, 3), (36, 3), (5, 5), (10, 5), (15, 5), (20, 5), (50, 5), (4, 4),
  (8, 4), (12, 4), (24, 4), (48, 4),
];

/// 360 / α değeri çift olan açılar: görüntü sayısı 360 / α − 1 kesin.
const _aynaAcilari = [10, 12, 15, 18, 20, 30, 36, 45, 60, 90];

/// (kırılma indisi payı, paydası, sıvıdaki ışık hızı, havadaki ve sıvıdaki
/// dalga boyu, uzaklık birimi): n = 4/3 · 10/7 · 1,5 · 1,6 · 5/3. İndisler
/// gerçek saydam sıvıların aralığındadır (yaklaşık 1,33 … 1,67); uzaklık
/// birimi h·n ve h / n değerlerini kısa ondalıklı yapar.
const _ortamlar = <(int, int, String, int, int, int)>[
  (4, 3, '2,25·10⁸', 600, 450, 6),
  (10, 7, '2,1·10⁸', 700, 490, 7),
  (3, 2, '2·10⁸', 660, 440, 6),
  (8, 5, '1,875·10⁸', 640, 400, 4),
  (5, 3, '1,8·10⁸', 650, 390, 6),
];

/// Potansiyeli gerçek eksi işaretiyle (−) yazar.
String _volt(int x) => x < 0 ? '−${-x} V' : '$x V';

/// (dalga boyu nm, foton enerjisi 0,01 eV): h·c = 1240 eV·nm ile tam bölünür.
const _fotonlar = <(int, int)>[
  (100, 1240), (124, 1000), (155, 800), (200, 620), (248, 500), (250, 496),
  (310, 400), (400, 310), (496, 250), (500, 248), (620, 200),
];

final lmFizikElektrik = <AdvancedFamily>[
  // 1 · Ohm yasası ve R = ρ·L / A orantıları.
  _fe(
    'ohm',
    'Ohm yasası ve iletkenin direnci',
    Difficulty.easy,
    BloomLevel.uygulama,
    (a, b, c) {
      final k = c ~/ 2;
      if (c.isEven) {
        final r = 2 + a; // 2 … 26 Ω
        final i1 = 2 * (1 + b % 5); // onda bir amper: 0,2 … 1 A
        final i2 = i1 + 2 * (1 + b ~/ 5 + 4 * k); // 0,4 … 5 A
        final v1 = r * i1 / 10, v2 = r * i2 / 10;
        return _ondalikSira(
          '${sec(_omikIletken, a + b)} uçları arasına ${tr(v1)} V gerilim '
          'uygulandığında iletkenden ${tr(i1 / 10)} A akım geçiyor. Sıcaklığı '
          'değişmeyen aynı iletkenin uçları arasındaki gerilim ${tr(v2)} V '
          'yapılırsa iletkenden geçen akım kaç A olur?',
          i2 / 10,
          [
            i1 * i1 / i2 / 10, // akım gerilimle ters orantılı sanılmış
            (i1 + i2) / 10, // yeni akım eskisine eklenmiş
            r.toDouble(), // direnç değeri akım sanılmış
            (i2 - i1) / 10, // akımdaki artış
            i1 / 10, // akım değişmez sanılmış
            if (i2 <= 2 * i1) i2 * i2 / i1 / 10, // akım gerilimin karesiyle
            v2, // gerilim değeri akım sanılmış
          ],
          'İletkenin direnci R = V / I = ${tr(v1)} / ${tr(i1 / 10)} = $r Ω '
          'olur. Direnç değişmediğinden yeni akım I = ${tr(v2)} / $r = '
          '${tr(i2 / 10)} A bulunur.',
          _no(a, b, c),
          unit: 'A',
        );
      }
      // Krom-nikelin özdirenci yaklaşık 1 Ω·mm²/m alınır: L = R·A. Böylece
      // verilen uzunluk, kesit ve direnç gerçek bir telle tutarlı kalır.
      final (nl, ns) = _telOran[b];
      final r1 = ns * (1 + k), r2 = nl * (1 + k); // Ω
      final s100 = const [10, 20, 25, 40, 50][a ~/ 5]; // kesit, 0,01 mm²
      final l1 = tr(r1 * s100 / 100), l2 = tr(nl * r1 * s100 / 100); // m
      final s1 = tr(s100 / 100), s2 = tr(ns * s100 / 100); // mm²
      final akim = tr((1 + a % 5) / 2); // 0,5 … 2,5 A
      final gerilim = tr(r1 * (1 + a % 5) / 2); // V
      return _sayiSira(
        'Uzunluğu $l1 m, kesit alanı $s1 mm² olan krom-nikel bir telin '
        'uçları arasına $gerilim V gerilim uygulandığında telden $akim A '
        'akım geçiyor. Aynı maddeden yapılmış, uzunluğu $l2 m ve kesit alanı '
        '$s2 mm² olan başka bir telin aynı sıcaklıktaki direnci kaç Ω olur?',
        r2,
        [
          r1 * nl * ns, // kesit alanıyla çarpılmış
          if (r1 * ns % nl == 0) r1 * ns ~/ nl, // iki oran da ters
          r1, // direnç değişmez sanılmış
          r1 * nl, // kesit alanı hesaba katılmamış
          1 + k, // uzunluk hesaba katılmamış
          if (r1 % (nl * ns) == 0) r1 ~/ (nl * ns), // ikisine de bölünmüş
        ],
        'Birinci telin direnci R = V / I = $gerilim / $akim = $r1 Ω olur. '
        'R = ρ·L / A olduğundan direnç uzunlukla doğru, kesit alanıyla ters '
        'orantılıdır. Uzunluk $nl katına, kesit alanı $ns katına çıktığı '
        'için R = $r1·$nl / $ns = $r2 Ω bulunur.',
        _no(a, b, c),
        unit: 'Ω',
      );
    },
    tyt: true,
  ),
  // 2 · Paralel kol + seri direnç: eşdeğer direnç ve akım paylaşımı.
  _fe(
    'direnc',
    'Seri ve paralel dirençlerde eşdeğer direnç ve akım',
    Difficulty.medium,
    BloomLevel.analiz,
    (a, b, c) {
      final (r1, r2) = _tamParalel[a];
      final g = r1.gcd(r2);
      final rp = r1 * r2 ~/ (r1 + r2);
      final r3 = 2 + b; // 2 … 21 Ω
      final j = 1 + c ~/ 2;
      final i10 = j * (r1 + r2) ~/ g; // ana kol akımı, onda bir amper
      final v = i10 * (rp + r3) / 10, i = i10 / 10;
      final giris =
          'Dirençleri R₁ = $r1 Ω ve R₂ = $r2 Ω olan iki direnç birbirine '
          'paralel bağlanmış, bu gruba R₃ = $r3 Ω değerindeki direnç seri '
          'bağlanmıştır. Devre, iç direnci önemsiz ${tr(v)} V gerilimli bir '
          'üretece bağlandığında';
      final ortak =
          'Paralel kolun eşdeğeri $r1·$r2 / ($r1 + $r2) = $rp Ω, devrenin '
          'eşdeğer direnci $rp + $r3 = ${rp + r3} Ω olur. Ana kol akımı '
          'I = ${tr(v)} / ${rp + r3} = ${tr(i)} A bulunur.';
      final i1 = j * (r2 ~/ g) / 10, i2 = j * (r1 ~/ g) / 10;
      if (c.isEven) {
        return _ondalikSira(
          '$giris üreteçten çekilen akım (ana kol akımı) kaç A olur?',
          i,
          [
            v / (r1 + r2 + r3), // tüm dirençler seri sanılmış
            v / r3, // paralel kol unutulmuş
            v / rp, // seri direnç unutulmuş
            v * (rp + r3) / (rp * r3), // R₃ de paralel sanılmış
            i1, // R₁ kolunun akımı
            v / (r1 + r2), // paralel kol seri sanılmış, R₃ unutulmuş
            i2, // R₂ kolunun akımı
            v / (r1 * r2 + r3), // paralel eşdeğerde paydaya bölünmemiş
          ],
          ortak,
          _no(a, b, c),
          unit: 'A',
        );
      }
      return _ondalikSira(
        '$giris R₁ direncinden geçen akım kaç A olur?',
        i1,
        [
          i2, // akım dirençle doğru orantılı paylaştırılmış
          i, // ana kol akımı
          i / 2, // akım eşit paylaştırılmış
          v / r1, // üretecin gerilimi R₁'e uygulanmış
          v / (r1 + r3), // R₂ yok sayılmış
          v * r3 / ((rp + r3) * r1), // gerilim payları yer değiştirmiş
          v / (r1 + r2 + r3), // tüm dirençler seri sanılmış
        ],
        '$ortak Paralel kollarda akım dirençle ters orantılı paylaşılır: '
        'I₁ = ${tr(i)}·$r2 / ($r1 + $r2) = ${tr(i1)} A.',
        _no(a, b, c),
        unit: 'A',
      );
    },
    tyt: true,
  ),
  // 3 · Güç, enerji (kWh) ve fatura.
  _fe(
    'guc',
    'Elektriksel güç, enerji ve elektrik faturası',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final t = 1 + b % 5; // günlük çalışma süresi (saat)
      final gun = const [10, 20, 30, 60][b ~/ 5];
      final f10 = const [20, 25, 30, 40, 50][c ~/ 2]; // kWh ücreti (0,1 TL)
      final cihaz = sec(_isiticilar, a + b);
      final p = (c.isEven ? 100 : 110) * (5 + a); // W
      final e = p * t * gun / 1000; // kWh
      final ucret = p * t * gun * f10 / 10000; // TL
      final soru =
          'Elektrik enerjisinin kilovatsaat (kWh) ücreti ${tr(f10 / 10)} TL '
          'olduğuna göre bu cihazın $gun günde harcadığı elektrik enerjisinin '
          'bedeli kaç TL olur?';
      final hesap =
          'Harcanan enerji E = P·t = ${tr(p / 1000)} kW·${t * gun} saat = '
          '${tr(e)} kWh olur. Bedeli ${tr(e)}·${tr(f10 / 10)} = '
          '${tr(ucret)} TL bulunur.';
      final celdirici = [
        e, // enerji (kWh) bedel sanılmış
        ucret * 10, // W → kW çevirmesinde 100'e bölünmüş
        ucret / gun, // gün sayısıyla çarpılmamış
        if (gun < 30) ucret * 30 / gun, // dönem 30 gün sanılmış
        ucret / t, // günlük süreyle çarpılmamış
        ucret / 10,
        e * 10 / f10, // birim fiyatla çarpmak yerine bölmek
      ];
      if (c.isEven) {
        return _ondalikSira(
          'Gücü $p W olan $cihaz her gün $t saat çalıştırılıyor. $soru',
          ucret,
          celdirici,
          hesap,
          _no(a, b, c),
          unit: 'TL',
        );
      }
      final akim = tr((5 + a) / 2);
      return _ondalikSira(
        '220 V gerilimli şehir şebekesine bağlı $cihaz çalışırken $akim A '
        'akım çekiyor ve her gün $t saat çalıştırılıyor. $soru',
        ucret,
        celdirici,
        'Cihazın gücü P = V·I = 220·$akim = $p W olur. $hesap',
        _no(a, b, c),
        unit: 'TL',
      );
    },
    tyt: true,
  ),
  // 4 · Özdeş üreteçlerin seri ve paralel bağlanması.
  _fe(
    'uretec',
    'Seri ve paralel bağlı üreteçlerde emk ve iç direnç',
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) {
      final n = 2 + b ~/ 4; // üreteç sayısı
      final tt = 3 + c ~/ 2; // üreteç başına düşen toplam direnç (Ω)
      final i = (a + 2) / 5; // 0,4 … 5,2 A
      final emk = (a + 2) * tt / 5; // V
      if (c.isEven) {
        final r = (1 + b % 4) / 2; // iç direnç 0,5 … 2 Ω
        final rd = n * (tt - r);
        return _ondalikSira(
          'Her birinin emk değeri ${tr(emk)} V, iç direnci ${tr(r)} Ω olan '
          '$n özdeş üreteç seri bağlanarak ${tr(rd)} Ω değerindeki bir '
          'direncin uçlarına bağlanıyor. Dirençten geçen akım kaç A olur?',
          i,
          [
            n * emk / (rd + r), // iç dirençler toplanmamış
            emk / (rd + n * r), // emk değerleri toplanmamış
            n * emk / rd, // iç direnç yok sayılmış
            emk / (rd + r), // tek üreteç
            n * emk / (rd + r / n), // iç direnç paralel kuralıyla
            emk / (rd + r / n), // paralel bağlama kuralları
            emk / rd, // tek üreteç, iç direnç yok
          ],
          'Seri bağlı üreteçlerde emk değerleri ve iç dirençler toplanır: '
          'toplam emk $n·${tr(emk)} = ${tr(n * emk)} V, toplam iç direnç '
          '$n·${tr(r)} = ${tr(n * r)} Ω olur. I = ${tr(n * emk)} / '
          '(${tr(rd)} + ${tr(n * r)}) = ${tr(i)} A.',
          _no(a, b, c),
          unit: 'A',
        );
      }
      final r0 = const [10, 20, 25, 50][b % 4] / 100;
      final r = n * r0, rd = tt - r0;
      return _ondalikSira(
        'Her birinin emk değeri ${tr(emk)} V, iç direnci ${tr(r)} Ω olan $n '
        'özdeş üreteç, aynı kutupları birleştirilerek paralel bağlanıyor ve '
        '${tr(rd)} Ω değerindeki bir direncin uçlarına bağlanıyor. Dirençten '
        'geçen akım kaç A olur?',
        i,
        [
          n * emk / (rd + r0), // emk değerleri toplanmış
          emk / (rd + r), // iç direnç n'ye bölünmemiş
          emk / rd, // iç direnç yok sayılmış
          emk / (rd + n * r), // iç direnç n ile çarpılmış
          n * emk / (rd + r), // seri kuralı: emk toplanmış
          emk / (n * (rd + r0)), // emk üreteçlere paylaştırılmış
          n * emk / (rd + n * r), // seri bağlama kuralları
        ],
        'Özdeş üreteçler paralel bağlandığında emk değişmez (${tr(emk)} V), '
        'eşdeğer iç direnç ${tr(r)} / $n = ${tr(r0)} Ω olur. I = ${tr(emk)} '
        '/ (${tr(rd)} + ${tr(r0)}) = ${tr(i)} A.',
        _no(a, b, c),
        unit: 'A',
      );
    },
  ),
  // 5 · Coulomb kuvveti: orantı ve k = 9·10⁹ ile hesap.
  _fe(
    'coulomb',
    'Coulomb yasası ve elektriksel kuvvet',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final k = c ~/ 2;
      if (c.isEven) {
        final (ust, alt) = const [(2, 1), (3, 1), (4, 1), (1, 2), (1, 3)][b % 5];
        final m = 2 + b ~/ 5; // yük katsayısı 2 … 5
        final d1 = 6 * (1 + k), d2 = d1 * ust ~/ alt; // cm
        final f1 = ust * ust * (a + 1) / 10;
        final f2 = (a + 1) * m * alt * alt / 10;
        return ondalikli(
          'Aralarındaki uzaklık $d1 cm olan noktasal iki yük birbirine '
          '${tr(f1)} N büyüklüğünde elektriksel kuvvet uyguluyor. Yüklerden '
          'yalnız birinin yük miktarı $m katına çıkarılıp aralarındaki '
          'uzaklık $d2 cm yapılırsa yüklerin birbirine uyguladığı kuvvetin '
          'büyüklüğü kaç N olur?',
          f2,
          [
            f1 * m * alt / ust,
            f1 * m * ust * ust / (alt * alt),
            f1 * alt * alt / (ust * ust),
            f1 * m,
          ],
          'F = k·q₁·q₂ / d² olduğundan kuvvet yük çarpımıyla doğru, uzaklığın '
          'karesiyle ters orantılıdır. Yük $m katına çıkarken uzaklık ilk '
          'değerinin ${kesir(ust, alt)} katı olduğundan F = ${tr(f1)}·$m·'
          '${kesir(alt * alt, ust * ust)} = ${tr(f2)} N olur.',
          unit: 'N',
          positive: true,
        );
      }
      final q1 = (a + 1) / 5, q2 = (b + 1) / 2; // µC
      final z = const [5, 6, 10, 15, 30][k]; // cm
      final f = 9 * (a + 1) * (b + 1) / (z * z);
      final isaret = (a + b).isOdd ? '−' : '+';
      return ondalikli(
        'Yükleri +${tr(q1)} µC ve $isaret${tr(q2)} µC olan noktasal iki cisim '
        'havada birbirinden $z cm uzağa yerleştiriliyor. Cisimlerin birbirine '
        'uyguladığı elektriksel kuvvetin büyüklüğü kaç N olur? '
        '(k = 9·10⁹ N·m²/C², 1 µC = 10⁻⁶ C)',
        f,
        [f * z / 100, f * 10, f / 10, f * 100],
        'F = k·q₁·q₂ / d² = 9·10⁹·${tr(q1)}·10⁻⁶·${tr(q2)}·10⁻⁶ / '
        '${tr(z / 100)}² = ${tr(f, 3)} N olur. Kuvvetin büyüklüğü yüklerin '
        'işaretine bağlı değildir.',
        unit: 'N',
        digits: 3,
        positive: true,
      );
    },
  ),
  // 6 · Düzgün elektrik alan, potansiyel farkı ve iş.
  _fe(
    'alan_potansiyel',
    'Elektrik alan, potansiyel farkı ve elektriksel iş',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final k = c ~/ 2;
      final q = b + 1; // µC
      if (c.isEven) {
        final e = 500 * (a + 1); // V/m
        final d = const [2, 4, 5, 10, 20][k]; // cm
        final v = e * d ~/ 100;
        final w = q * v;
        return _sayiSira(
          'Aralarındaki uzaklık $d cm olan yüklü paralel iki levha arasında '
          'büyüklüğü $e V/m olan düzgün bir elektrik alan bulunuyor. Yükü '
          '$q µC olan bir parçacık levhalardan birinden diğerine '
          'götürüldüğünde elektriksel kuvvetin yaptığı işin büyüklüğü kaç µJ '
          '(mikrojoule) olur?',
          w,
          [
            w * 100, // uzaklık cm olarak kullanılmış
            v, // yükle çarpılmamış (potansiyel farkı)
            q * e, // uzaklık unutulmuş
            if (w.isEven) w ~/ 2, // kondansatör enerjisindeki 1/2
            e * d, // uzaklık cm ile, yük unutulmuş
            if (q * e % d == 0) q * e ~/ d, // uzaklıkla çarpmak yerine bölmek
            w * 10,
            if (w % 10 == 0) w ~/ 10,
            if (v % q == 0) v ~/ q, // yükle çarpmak yerine bölmek
          ],
          'Levhalar arasındaki potansiyel farkı V = E·d = $e·${tr(d / 100)} '
          '= $v V olur. İşin büyüklüğü W = q·V = $q·$v = $w µJ bulunur.',
          _no(a, b, c),
        );
      }
      final vk = 10 * (a + 2);
      final dv = const [20, 40, 50, 80, 100][k];
      final w = q * dv;
      final vl = vk + dv;
      final adim = vl >= 200 ? 10 : (vl >= 40 ? 5 : 1);
      // İşaret hatası (vk − dv) negatif çıkabilir; gerçek eksiyle yazılır.
      final adaylar = [
        vk - dv, // işaret hatası
        vk + w, // yüke bölünmemiş
        dv, // yalnız potansiyel farkı
        if (q <= 5) vk + w * q, // yüke bölmek yerine çarpmak
        w, // iş potansiyel sanılmış
        vk, // potansiyel değişmez sanılmış
        dv - vk, // işaret hatası (K'nin potansiyeli çıkarılmış)
        for (final m in const [1.2, 0.75, 1.5, 0.6]) (vl * m).round(),
        for (var j = 1; j <= 3; j++) ...[vl + j * adim, vl - j * adim],
      ];
      return AdvancedItem(
        'Bir elektrik alanında, potansiyeli $vk V olan K noktasındaki +$q µC '
        'yüklü parçacığı L noktasına sabit hızla götürmek için elektriksel '
        'kuvvetlere karşı $w µJ iş yapılıyor. L noktasının potansiyeli kaç V '
        'olur?',
        _volt(vl),
        _sirali(vl, _volt(vl), [
          for (final x in adaylar) (x, _volt(x)),
        ], hedefSira(_no(a, b, c))),
        'K ile L arasındaki potansiyel farkı W / q = $w / $q = $dv V olur. '
        'Pozitif yük elektriksel kuvvetlere karşı taşındığından L daha '
        'yüksek potansiyeldedir: $vk + $dv = $vl V.',
      );
    },
  ),
  // 7 · Sığa, yük, bağlama ve depolanan enerji.
  _fe(
    'siga',
    'Kondansatörlerde sığa, yük ve depolanan enerji',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final k = c ~/ 2;
      if (c.isEven) {
        final (c1, c2) = _tamParalel[a];
        final cs = c1 * c2 ~/ (c1 + c2);
        final c3 = const [2, 3, 5, 6, 10][k];
        final v = 5 * (b + 1);
        final q = (cs + c3) * v;
        final hepsiSeri = cs * c3 * v, tersBag = (c1 + c2) * c3 * v;
        return _sayiSira(
          'Sığaları $c1 µF ve $c2 µF olan iki kondansatör seri bağlanmış, '
          'bu kola sığası $c3 µF olan üçüncü bir kondansatör paralel '
          'bağlanmıştır. Sistem $v V gerilimli bir üretecin uçlarına bağlanıp '
          'tamamen dolduğunda üreteçten çekilen toplam yük kaç µC '
          '(mikrokulon) olur?',
          q,
          [
            (c1 + c2 + c3) * v, // seri kol paralel sanılmış
            cs * v, // paralel kondansatör unutulmuş
            (2 * cs + c3) * v, // seri kondansatörlerin yükleri toplanmış
            c3 * v, // yalnız paralel kondansatör
            (c1 + c2) * v,
            if (hepsiSeri % (cs + c3) == 0) hepsiSeri ~/ (cs + c3), // tümü seri
            if (tersBag % (c1 + c2 + c3) == 0)
              tersBag ~/ (c1 + c2 + c3), // seri ve paralel yer değiştirmiş
            if (q.isEven) q ~/ 2, // enerji bağıntısındaki 1/2
          ],
          'Seri kolun eşdeğer sığası $c1·$c2 / ($c1 + $c2) = $cs µF, paralel '
          'kolla birlikte eşdeğer sığa $cs + $c3 = ${cs + c3} µF olur. '
          'Q = C·V = ${cs + c3}·$v = $q µC.',
          _no(a, b, c),
        );
      }
      final n = 2 + k;
      final seri = (a + b).isOdd;
      final tek = seri ? n * (a + 1) : a + 1; // µF
      final ces = seri ? a + 1 : n * (a + 1);
      final v = 2 * (b + 1);
      final e = ces * v * v ~/ 2;
      final tekV2 = tek * v * v;
      return _sayiSira(
        'Her birinin sığası $tek µF olan $n özdeş kondansatör birbirine '
        '${seri ? 'seri' : 'paralel'} bağlanıyor ve $v V gerilimli bir '
        'üretecin uçlarına bağlanarak dolduruluyor. Kondansatörlerde '
        'depolanan toplam enerji kaç µJ (mikrojoule) olur?',
        e,
        [
          ces * v * v, // 1/2 unutulmuş
          (seri ? n * tek : tek) * v * v ~/ 2, // bağlama kuralı karışmış
          ces * v ~/ 2, // gerilimin karesi alınmamış
          tek * v * v, // tek kondansatör, 1/2 unutulmuş
          // Seride tek kondansatörün enerjisi (gerilimi V / n); paralelde
          // eşdeğer sığayla bulunan enerji bir de n ile çarpılmış.
          if (seri && tekV2 % (2 * n * n) == 0) tekV2 ~/ (2 * n * n),
          if (!seri) n * e,
          if (!seri && tekV2 % (2 * n) == 0) tekV2 ~/ (2 * n), // seri kuralı
        ],
        '${seri ? 'Özdeş $n kondansatör seri bağlandığında eşdeğer sığa '
                  '$tek / $n = $ces µF olur.' : 'Özdeş $n kondansatör paralel '
                  'bağlandığında eşdeğer sığa $n·$tek = $ces µF olur.'} '
        'E = C·V² / 2 = $ces·$v² / 2 = $e µJ.',
        _no(a, b, c),
      );
    },
  ),
  // 8 · Akım taşıyan tele ve hareketli yüke etkiyen manyetik kuvvet.
  _fe(
    'manyetik',
    'Akım taşıyan tele ve hareketli yüke manyetik kuvvet',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final (aci, s10, c10) = _acilar[c ~/ 2];
      final dik = aci == 90;
      final sinus = tr(s10 / 10);
      if (c.isEven) {
        final m1 = 1 + a % 5, m2 = 1 + a ~/ 5;
        final alan = tr(m1 / 5); // 0,2 … 1 T
        final l = 10 * m2; // cm
        final i = b + 1; // A
        final f = 2 * m1 * m2 * i * s10 / 1000;
        final tam = 2 * m1 * m2 * i / 100;
        return _ondalikSira(
          'Büyüklüğü $alan T olan düzgün bir manyetik alanın içinde, $l cm '
          'uzunluğundaki düz bir iletken telden $i A akım geçiyor. '
          '${dik ? 'Tel, manyetik alan çizgilerine dik konumdadır.' : 'Tel, '
                    'manyetik alan çizgileriyle $aci° açı yapmaktadır '
                    '(sin $aci° = $sinus).'} '
          'Tele etkiyen manyetik kuvvetin büyüklüğü kaç N olur?',
          f,
          [
            if (!dik) tam, // sin θ unutulmuş
            if (c10 > 0) tam * c10 / 10, // sin yerine cos
            f * 100, // uzunluk cm olarak kullanılmış
            f / i, // akım unutulmuş
            f * 10,
            f / 10,
            f / 100,
          ],
          dik
              ? 'Tel alana dik olduğundan F = B·I·L = $alan·$i·'
                    '${tr(l / 100)} = ${tr(f, 3)} N olur.'
              : 'F = B·I·L·sin θ = $alan·$i·${tr(l / 100)}·$sinus = '
                    '${tr(f, 3)} N olur.',
          _no(a, b, c),
          unit: 'N',
          digits: 3,
        );
      }
      final q = 1 + a % 5, mv = 2 + a ~/ 5;
      final alan = tr((b + 1) / 10); // 0,1 … 2 T
      final f = q * mv * (b + 1) * s10 / 1000;
      final tam = q * mv * (b + 1) / 100;
      return _ondalikSira(
        'Yükü $q µC olan bir parçacık, büyüklüğü $alan T olan düzgün bir '
        'manyetik alana $mv·10⁵ m/s hızla giriyor. '
        '${dik ? 'Parçacığın hızı manyetik alan çizgilerine diktir.' : 'Parçacığın '
                  'hızı manyetik alan çizgileriyle $aci° açı yapmaktadır '
                  '(sin $aci° = $sinus).'} '
        'Parçacığa etkiyen manyetik kuvvetin büyüklüğü kaç N olur? '
        '(1 µC = 10⁻⁶ C)',
        f,
        [
          if (!dik) tam, // sin θ unutulmuş
          if (c10 > 0) tam * c10 / 10, // sin yerine cos
          f * 10, // on üsleri yanlış
          f / 10,
          f * 100,
          f / 100,
        ],
        dik
            ? 'Hız alana dik olduğundan F = q·v·B = $q·10⁻⁶·$mv·10⁵·$alan = '
                  '${tr(f, 3)} N olur.'
            : 'F = q·v·B·sin θ = $q·10⁻⁶·$mv·10⁵·$alan·$sinus = '
                  '${tr(f, 3)} N olur.',
        _no(a, b, c),
        unit: 'N',
        digits: 3,
      );
    },
  ),
  // 9 · Transformatör: sarım, gerilim, akım ve verim.
  _fe(
    'transformator',
    'Transformatörde sarım, gerilim, akım ve verim',
    Difficulty.easy,
    BloomLevel.uygulama,
    (a, b, c) {
      final k = c ~/ 2;
      if (c.isEven) {
        final (np, ns) = _sarimOran[b];
        final n1 = np * 50 * (1 + k), n2 = ns * 50 * (1 + k);
        final giris =
            'İdeal bir transformatörün primer sargısında $n1, sekonder '
            'sargısında $n2 sarım bulunuyor.';
        if (a.isEven) {
          final v = 2 * (a + 3);
          final vp = np * v, vs = ns * v;
          return sayisal(
            '$giris Primer sargıya $vp V etkin değerli alternatif gerilim '
            'uygulandığında sekonder sargının uçları arasındaki gerilim kaç '
            'V olur?',
            vs,
            [
              if (np * vp % ns == 0) np * vp ~/ ns,
              v,
              vp * ns,
              vp + vs,
              vs * (ns > 1 ? ns : np),
            ],
            'İdeal transformatörde gerilim sarım sayısıyla doğru orantılıdır: '
            'Vs = Vp·Ns / Np = $vp·$n2 / $n1 = $vs V.',
            unit: 'V',
            positive: true,
          );
        }
        final ik = np * (a + 3) / 10, ip = ns * (a + 3) / 10;
        return ondalikli(
          '$giris Sekonder sargıya bağlı alıcıdan ${tr(ik)} A akım geçtiğine '
          'göre primer sargıdan geçen akım kaç A olur?',
          ip,
          [ik * np / ns, (a + 3) / 10, ik * ns, ik + ip],
          'İdeal transformatörde güç korunduğundan akım sarım sayısıyla ters '
          'orantılıdır: Ip = Is·Ns / Np = ${tr(ik)}·$n2 / $n1 = ${tr(ip)} A.',
          unit: 'A',
          positive: true,
        );
      }
      final u = a + 1;
      final vp = const [200, 250, 400, 500][b % 4];
      final vs = const [10, 20, 25, 50, 100][b ~/ 4];
      final verim = const [50, 60, 75, 80, 90][k];
      final ip = tr(100 * u / vp), ik = tr(verim * u / vs);
      return secenekli(
        'Bir transformatörün primer sargısına $vp V gerilim uygulandığında '
        'primer akımı $ip A; sekonder sargısının uçları arasındaki gerilim '
        '$vs V, sekonder akımı $ik A olarak ölçülüyor. Bu transformatörün '
        'verimi yüzde kaçtır?',
        '%$verim',
        [
          '%${100 - verim}',
          '%${tr(vs * 100 / vp)}',
          for (final x in const [75, 80, 60, 90, 50]) '%$x',
        ],
        'Primer gücü $vp·$ip = ${100 * u} W, sekonder gücü $vs·$ik = '
        '${verim * u} W olur. Verim = ${verim * u} / ${100 * u} = %$verim.',
      );
    },
  ),
  // 10 · Dalga hızı, dalga boyu, frekans ve periyot.
  _fe(
    'dalga',
    'Dalgalarda hız, dalga boyu, frekans ve periyot',
    Difficulty.easy,
    BloomLevel.uygulama,
    (a, b, c) {
      final k = c ~/ 2;
      if (c.isEven) {
        // Gergin halatta gerçekçi hızlar: v = 2 … 39,1 m/s.
        final lam = (a + 10) / 10; // 1 … 3,4 m
        final f = (b + 4) / 2; // 2 … 11,5 Hz
        final t = const [4, 6, 8, 10, 20][k]; // s
        final n = (b + 4) * t ~/ 2;
        final v = (a + 10) * (b + 4) / 20;
        return _ondalikSira(
          'Gergin ve uzun bir halatın ucundaki kaynak $t saniyede $n tam '
          'dalga üretiyor. Halat üzerinde ilerleyen periyodik dalgalarda '
          'ardışık iki dalga tepesi arasındaki uzaklık ${tr(lam)} m olduğuna '
          'göre dalgaların yayılma hızı kaç m/s olur?',
          v,
          [
            lam / f, // frekans yerine periyot
            lam * n, // dalga sayısı frekans sanılmış
            lam / t, // toplam süre periyot sanılmış
            2 * v, // ardışık tepeler arası λ / 2 sanılmış
            f, // frekans yanıt sanılmış
            lam * t,
          ],
          'Frekans f = $n / $t = ${tr(f)} Hz, dalga boyu λ = ${tr(lam)} m '
          'olur. v = λ·f = ${tr(lam)}·${tr(f)} = ${tr(v)} m/s.',
          _no(a, b, c),
          unit: 'm/s',
        );
      }
      final v = (a + 1) / 2; // 0,5 … 12,5 m/s
      final per = (b + 1) / 5; // 0,2 … 4 s
      final n = 2 + k;
      final lam = (a + 1) * (b + 1) / 10;
      final d = (n - 1) * lam;
      final ikili = n == 2;
      return _ondalikSira(
        'Esnek bir ortamda ${tr(v)} m/s hızla yayılan periyodik dalgalarda, '
        '${ikili ? 'ardışık iki dalga tepesi arasındaki' : 'art arda gelen '
                  '$n dalga tepesinden ilki ile sonuncusu arasındaki'} '
        'uzaklık ${tr(d)} m olarak ölçülüyor. Bu dalgaların periyodu kaç s '
        'olur?',
        per,
        [
          d / v, // uzaklık dalga boyu sanılmış
          d / (n * v), // n − 1 yerine n aralık
          v / lam, // periyot yerine frekans
          2 * per, // ardışık tepeler arası λ / 2 sanılmış
          lam * v, // bölmek yerine çarpmak
          per / 2, // ardışık tepeler arası 2λ sanılmış
          lam, // dalga boyu yanıt sanılmış
        ],
        '${ikili ? 'Ardışık iki dalga tepesi arasındaki uzaklık bir dalga '
                  'boyudur: λ = ${tr(lam)} m.' : 'Art arda gelen $n tepe '
                  'arasında ${n - 1} dalga boyu bulunur: λ = ${tr(d)} / '
                  '${n - 1} = ${tr(lam)} m.'} '
        'T = λ / v = ${tr(lam)} / ${tr(v)} = ${tr(per)} s olur.',
        _no(a, b, c),
        unit: 's',
      );
    },
    tyt: true,
  ),
  // 11 · Yankı ve sonar: gidiş-dönüş süresinden uzaklık.
  _fe(
    'ses',
    'Seste yankı, sonar ve ses hızı',
    Difficulty.medium,
    BloomLevel.analiz,
    (a, b, c) {
      final k = c ~/ 2;
      final t1 = tr((a + 1) / 5), t2 = tr((a + b + 2) / 5); // s
      if (c.isEven) {
        final v = 320 + 10 * k;
        final d1 = v * (a + 1) ~/ 10, d2 = v * (a + b + 2) ~/ 10;
        return _sayiSira(
          'Karşılıklı iki dik yamaç arasında duran bir dağcı kısa bir düdük '
          'sesi çıkarıyor. Dağcı, yakın yamaçtan gelen yankıyı $t1 s, uzak '
          'yamaçtan gelen yankıyı $t2 s sonra duyuyor. Sesin havadaki hızı '
          '$v m/s olduğuna göre iki yamaç arasındaki uzaklık kaç m olur?',
          d1 + d2,
          [
            2 * (d1 + d2), // gidiş-dönüş için ikiye bölünmemiş
            d2, // yalnız uzak yamacın uzaklığı
            2 * d1 + d2, // yalnız uzak yankının süresi ikiye bölünmüş
            d2 - d1, // uzaklıkların farkı
            d1 + 2 * d2, // yalnız yakın yankının süresi ikiye bölünmüş
            if ((d1 + d2).isEven) (d1 + d2) ~/ 2, // iki kez ikiye bölünmüş
            2 * d2, // uzak yankının süresi ikiye bölünmemiş
            d1, // yalnız yakın yamacın uzaklığı
          ],
          'Ses her yamaca gidip döndüğünden uzaklıklar $v·$t1 / 2 = $d1 m ve '
          '$v·$t2 / 2 = $d2 m olur. Yamaçlar arasındaki uzaklık $d1 + $d2 = '
          '${d1 + d2} m bulunur.',
          _no(a, b, c),
          unit: 'm',
        );
      }
      final v = const [1450, 1480, 1500, 1520, 1550][k];
      final h1 = v * (a + 1) ~/ 10, h2 = v * (a + b + 2) ~/ 10;
      return _sayiSira(
        'Bir araştırma gemisinin sonar cihazından deniz tabanına doğru '
        'gönderilen ses sinyali önce bir balık sürüsünden, sonra deniz '
        'tabanından yansıyor. Sürüden yansıyan sinyal $t1 s, tabandan '
        'yansıyan sinyal $t2 s sonra gemiye ulaşıyor. Sesin deniz suyundaki '
        'hızı $v m/s olduğuna göre balık sürüsü deniz tabanından kaç m '
        'yukarıdadır?',
        h2 - h1,
        [
          2 * (h2 - h1), // gidiş-dönüş için ikiye bölünmemiş
          h2, // deniz tabanının derinliği
          h1, // sürünün derinliği
          h1 + h2, // derinlikler toplanmış
          if ((h2 - h1).isEven) (h2 - h1) ~/ 2, // iki kez ikiye bölünmüş
          2 * h2 - h1, // yalnız sürü yankısının süresi ikiye bölünmüş
          h2 - 2 * h1, // yalnız taban yankısının süresi ikiye bölünmüş
        ],
        'Sürünün derinliği $v·$t1 / 2 = $h1 m, deniz tabanının derinliği '
        '$v·$t2 / 2 = $h2 m olur. Sürü tabandan $h2 − $h1 = ${h2 - h1} m '
        'yukarıdadır.',
        _no(a, b, c),
        unit: 'm',
      );
    },
    tyt: true,
  ),
  // 12 · Yay sarkacı ve basit sarkaçta periyodun orantısal değişimi.
  _fe(
    'harmonik',
    'Yay sarkacı ve basit sarkaçta periyot',
    Difficulty.medium,
    BloomLevel.anlama,
    (a, b, c) {
      final (p, q) = _oranlar[b];
      final adim = a % 5 + 5 * (c ~/ 2); // 0 … 24
      final kat = kesir(p, q), kareKat = kesir(p * p, q * q);
      // Tipik hatalar t₁·(p/q)ᵏ biçimindedir (kök alınmamış, oran ters, periyot
      // değişmez sanılmış); bunların üçü anahtarın bir yanında, biri öteki
      // yanında kalır. Bu yüzden periyot artıyorsa anahtar 3. ya da 4.,
      // azalıyorsa 1. ya da 2. sıraya konur: dört sıra eşit sıklıkta görülür.
      final sira = (p > q ? 2 : 0) + hedefSira(_no(a, b, c)) % 2;
      if (c.isEven) {
        final tau = 10 + 2 * adim; // 0,01 s
        final mu = 10 * (1 + a ~/ 5); // g
        final m1 = q * q * mu, m2 = p * p * mu;
        final t1 = q * tau / 100, t2 = p * tau / 100;
        return _ondalikSira(
          'Sürtünmesiz yatay düzlemde, bir yayın ucuna bağlı $m1 g kütleli '
          'cisim ${tr(t1)} s periyotla basit harmonik hareket yapıyor. Cisim '
          'çıkarılıp aynı yaya $m2 g kütleli başka bir cisim bağlanırsa '
          'salınımın periyodu kaç s olur?',
          t2,
          [
            t1 * p * p / (q * q), // kök alınmamış
            t1 * q / p, // oran ters alınmış
            t1, // periyot değişmez sanılmış
            t1 * q * q / (p * p), // oran ters, kök alınmamış
          ],
          'Yay sarkacında T = 2π·√(m / k) olduğundan periyot kütlenin '
          'kareköküyle doğru orantılıdır. Kütle oranı $m2 / $m1 = $kareKat '
          'olduğundan periyot ilk değerinin $kat katı olur: '
          'T = ${tr(t1)}·$kat = ${tr(t2)} s.',
          _no(a, b, c),
          unit: 's',
          sira: sira,
        );
      }
      final tau = 40 + 2 * adim; // 0,01 s
      final lam = const [4, 5, 6, 8, 10][a ~/ 5]; // cm
      final l1 = q * q * lam, l2 = p * p * lam;
      final t1 = q * tau / 100, t2 = p * tau / 100;
      return _ondalikSira(
        'Bir gezegenin yüzeyinde, ip uzunluğu $l1 cm olan basit sarkacın '
        'küçük genlikli salınımlarının periyodu ${tr(t1)} s olarak ölçülüyor. '
        'Aynı yerde ip uzunluğu $l2 cm yapılırsa sarkacın periyodu kaç s '
        'olur?',
        t2,
        [
          t1 * p * p / (q * q), // kök alınmamış
          t1 * q / p, // oran ters alınmış
          t1, // periyot değişmez sanılmış
          t1 * q * q / (p * p), // oran ters, kök alınmamış
        ],
        'Basit sarkaçta T = 2π·√(L / g) olduğundan periyot ip uzunluğunun '
        'kareköküyle doğru orantılıdır. Uzunluk oranı $l2 / $l1 = $kareKat '
        'olduğundan periyot ilk değerinin $kat katı olur: '
        'T = ${tr(t1)}·$kat = ${tr(t2)} s.',
        _no(a, b, c),
        unit: 's',
        sira: sira,
      );
    },
  ),
  // 13 · Düzgün çembersel hareket: açısal hız, çizgisel hız, merkezcil kuvvet.
  _fe(
    'cembersel',
    'Düzgün çembersel harekette hız, ivme ve kuvvet',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final k = c ~/ 2;
      if (c.isEven) {
        final r = (a + 1) / 5; // 0,2 … 5 m
        final m = (b + 1) / 2; // 0,5 … 10 kg
        final w = 1 + k; // rad/s
        final ivme = w * w * (a + 1) / 5;
        final f = w * w * (a + 1) * (b + 1) / 10;
        return _ondalikSira(
          'Sürtünmesiz yatay bir düzlemde, ${tr(m)} kg kütleli bir cisim '
          '${tr(r)} m yarıçaplı çembersel yörüngede $w rad/s sabit açısal '
          'hızla dönüyor. Cisme etkiyen merkezcil kuvvetin büyüklüğü kaç N '
          'olur?',
          f,
          [
            m * w * r, // ω'nın karesi alınmamış
            2 * f, // yarıçap yerine çap
            m * w * w / r, // r ile çarpmak yerine bölmek
            ivme, // ivme kuvvet sanılmış
            f / 2, // kinetik enerjideki 1/2 katsayısı
            m * w * w, // yarıçap unutulmuş
            m * r, // açısal hız unutulmuş
            m * w * w * r * r, // F = m·v² (r'ye bölünmemiş)
          ],
          'Merkezcil ivme a = ω²·r = $w²·${tr(r)} = ${tr(ivme)} m/s² olur. '
          'Merkezcil kuvvet F = m·a = ${tr(m)}·${tr(ivme)} = ${tr(f)} N '
          'bulunur.',
          _no(a, b, c),
          unit: 'N',
        );
      }
      final r = (a + 1) / 10; // 0,1 … 2,5 m
      final fr = (b + 1) / 4; // 0,25 … 5 s⁻¹
      final t = const [4, 8, 12, 20, 40][k]; // s
      final n = (b + 1) * t ~/ 4;
      final v = 3 * (a + 1) * (b + 1) / 20;
      return _ondalikSira(
        'Yarıçapı ${tr(r)} m olan bir çark sabit hızla dönerken $t saniyede '
        '$n tam devir yapıyor. Çarkın kenarındaki bir noktanın çizgisel '
        'hızının büyüklüğü kaç m/s olur? (π = 3 alınız.)',
        v,
        [
          6 * r * t / n, // frekans yerine periyot
          r * fr, // 2π unutulmuş
          2 * v, // yarıçap yerine çap
          v / 2, // 2 unutulmuş (π·r·f)
          6 * fr, // yarıçap unutulmuş
          6 * r / t, // çevre toplam süreye bölünmüş
          6 * fr / r, // r ile çarpmak yerine bölmek
          if (t <= 8) 6 * r * n, // süreye bölünmemiş
        ],
        'Frekans f = $n / $t = ${tr(fr)} s⁻¹ olur. v = 2·π·r·f = '
        '2·3·${tr(r)}·${tr(fr)} = ${tr(v)} m/s bulunur.',
        _no(a, b, c),
        unit: 'm/s',
      );
    },
  ),
  // 14 · Gezegende ağırlık ve yükseklikle değişen çekim ivmesi.
  _fe(
    'kutle_cekim',
    'Kütle çekimi, çekim ivmesi ve gezegende ağırlık',
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) {
      final k = c ~/ 2;
      if (c.isEven) {
        final (x, y) = _gezegenler[b];
        final m = 2 * (1 + a + 25 * k); // kg
        final w = 10 * m * x ~/ (y * y);
        return _sayiSira(
          "Kütlesi $m kg olan bir keşif aracı, kütlesi Dünya'nın kütlesinin "
          "$x katı, yarıçapı Dünya'nın yarıçapının $y katı olan bir "
          'gezegenin yüzeyine indiriliyor. Dünya yüzeyindeki çekim ivmesi '
          '10 m/s² olduğuna göre aracın bu gezegenin yüzeyindeki ağırlığı '
          'kaç N olur?',
          w,
          [
            10 * m * x ~/ y, // yarıçapın karesi alınmamış
            10 * m, // Dünya'daki ağırlık
            if (10 * m * y * y % x == 0) 10 * m * y * y ~/ x, // oran ters
            10 * m * x, // yarıçap hesaba katılmamış
            if (10 * m % (y * y) == 0) 10 * m ~/ (y * y), // kütle oranı yok
            if (10 * m * x % (y * y * y) == 0)
              10 * m * x ~/ (y * y * y), // yarıçapın küpü alınmış
            if (w % 10 == 0) w ~/ 10, // g ile çarpılmamış
          ],
          'g = G·M / R² olduğundan gezegenin yüzeyindeki çekim ivmesi '
          '10·$x / $y² = ${tr(10 * x / (y * y))} m/s² olur. Ağırlık '
          '$m·${tr(10 * x / (y * y))} = $w N bulunur.',
          _no(a, b, c),
          unit: 'N',
        );
      }
      final n = 1 + b % 4;
      // Yarıçap çekim ivmesiyle birlikte büyür: gezegenin ortalama yoğunluğu
      // Dünya'nınkinin yaklaşık 0,15 … 1,25 katında kalır.
      final yaricap = 500 * (a + 2) + 100 * (b ~/ 4 + 5 * k); // km
      final h = n * yaricap;
      final g100 = const [25, 10, 5, 4][n - 1] * (a + 1);
      final kare = (n + 1) * (n + 1);
      final g0 = g100 * kare / 100, g = g100 / 100;
      return _ondalikSira(
        'Yarıçapı $yaricap km olan bir gezegenin yüzeyindeki çekim ivmesi '
        '${tr(g0)} m/s² olarak biliniyor. Bu gezegenin yüzeyinden $h km '
        'yükseklikteki bir noktada çekim ivmesi kaç m/s² olur?',
        g,
        [
          g0 / (n * n), // merkez yerine yüzeyden uzaklık
          g0 / (n + 1), // uzaklığın karesi alınmamış
          g0 / (1 + n * n), // (R + h)² yerine R² + h²
          g0 / n, // iki hata birlikte
          g0 / ((n + 2) * (n + 2)), // yarıçap yerine çap eklenmiş
          g0 / (kare * (n + 1)), // uzaklığın küpü alınmış
        ],
        'Noktanın gezegenin merkezine uzaklığı $yaricap + $h = '
        '${yaricap + h} km, yani yarıçapın ${n + 1} katıdır. Çekim ivmesi '
        'merkeze uzaklığın karesiyle ters orantılı olduğundan g = ${tr(g0)} '
        '/ $kare = ${tr(g)} m/s² olur.',
        _no(a, b, c),
        unit: 'm/s²',
      );
    },
  ),
  // 15 · Aydınlanma şiddeti: E = I / d².
  _fe(
    'aydinlanma',
    'Aydınlanma şiddeti ve ışık şiddeti',
    Difficulty.easy,
    BloomLevel.anlama,
    (a, b, c) {
      final k = c ~/ 2;
      if (c.isEven) {
        final (p, q) = _oranlar[b];
        final d1 = tr(p * (1 + k) / 2), d2 = tr(q * (1 + k) / 2); // m
        final e1 = q * q * (a + 1), e2 = p * p * (a + 1); // lüks
        final dogrusal = p * q * (a + 1);
        final m1 = p * (1 + k) / 2, m2 = q * (1 + k) / 2; // d₁, d₂ (m)
        // Tipik hatalar e₁·(p/q)ᵏ biçimindedir ve anahtarın (k = 2) hep bir
        // yanında kalır; öteki yanda yalnız iki adımlı hatalar (ışık şiddeti
        // bulunurken ya da yeni aydınlanmada uzaklığın karesi unutulmuş)
        // bulunur. Bu yüzden aydınlanma artıyorsa anahtar 3. ya da 4.,
        // azalıyorsa 1. ya da 2. sıraya konur.
        final sira = (p > q ? 2 : 0) + hedefSira(_no(a, b, c)) % 2;
        return _ondalikSira(
          'Noktasal bir ışık kaynağından $d1 m uzakta, ışınlara dik tutulan '
          'bir ekranın üzerindeki aydınlanma şiddeti $e1 lüks olarak '
          'ölçülüyor. Ekran aynı kaynaktan $d2 m uzağa, yine ışınlara dik '
          'olacak biçimde götürülürse üzerindeki aydınlanma şiddeti kaç lüks '
          'olur?',
          e2.toDouble(),
          [
            dogrusal.toDouble(), // uzaklıkla ters orantılı sanılmış
            q * q * e1 / (p * p), // uzaklığın karesiyle doğru orantılı
            e1.toDouble(), // aydınlanma değişmez sanılmış
            q * e1 / p, // uzaklıkla doğru orantılı sanılmış
            e1 * m1 * m1 / m2, // yeni uzaklığın karesi alınmamış
            e1 * m1 / (m2 * m2), // ışık şiddetinde karesi alınmamış
          ],
          'E = I / d² olduğundan aydınlanma şiddeti uzaklığın karesiyle ters '
          'orantılıdır: E = $e1·($d1 / $d2)² = $e1·${kesir(p * p, q * q)} = '
          '$e2 lüks.',
          _no(a, b, c),
          unit: '',
          sira: sira,
        );
      }
      final n = 2 + k;
      // Yüksek tavanlı yapılarda gerçekçi değerler: 3 … 12,5 m yükseklik,
      // lamba başına 36 … 15625 cd, zeminde 8 … 600 lüks.
      final d = tr((b + 6) / 2); // m
      final siddet = (a + 1) * (b + 6) * (b + 6); // cd
      final e = 4 * n * (a + 1);
      final yer = b < 8
          ? sec(const ['Bir fabrika atölyesinin', 'Bir depo binasının'], a)
          : sec(const ['Bir spor salonunun', 'Bir fuar salonunun'], a);
      return _sayiSira(
        '$yer tavanına asılmış bir aydınlatma armatüründe, her birinin ışık '
        'şiddeti $siddet cd olan $n özdeş lamba bulunuyor. Armatür, tam '
        'altındaki zemin noktasından $d m yüksektedir ve bu noktaya gelen '
        'ışınlar zemine diktir. Lambalar birlikte tek bir noktasal kaynak '
        'gibi kabul edildiğine göre, bu noktadaki aydınlanma şiddeti kaç '
        'lüks olur?',
        e,
        [
          2 * n * (a + 1) * (b + 6), // uzaklığın karesi alınmamış
          4 * (a + 1), // tek lamba
          n * (a + 1) * (b + 6), // d² yerine 2d
          2 * (a + 1) * (b + 6), // tek lamba, karesi alınmamış
          if (4 * (a + 1) % n == 0) 4 * (a + 1) ~/ n, // şiddet n'ye bölünmüş
          n * siddet, // uzaklığa bölünmemiş
        ],
        'Toplam ışık şiddeti $n·$siddet = ${n * siddet} cd olur. '
        'E = I / d² = ${n * siddet} / $d² = $e lüks bulunur.',
        _no(a, b, c),
      );
    },
    tyt: true,
  ),
  // 16 · Düzlem ayna: uzaklık, yaklaşma hızı ve görüntü sayısı.
  _fe(
    'duzlem_ayna',
    'Düzlem aynada görüntü uzaklığı, hız ve sayısı',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final kk = c ~/ 3;
      final v = b + 1; // cm/s
      if (c % 3 == 0) {
        final d = 150 + 10 * a, t = 2 + kk;
        final son = d - v * t;
        return _sayiSira(
          'Düşey duran bir düzlem aynadan $d cm uzakta bulunan oyuncak bir '
          'araba, aynaya dik doğrultuda $v cm/s sabit hızla aynaya doğru '
          'harekete geçiyor. Araba harekete başladıktan $t s sonra araba ile '
          'aynadaki görüntüsü arasındaki uzaklık kaç cm olur?',
          2 * son,
          [
            // 2d − vt ile 2d − 3vt anahtarın iki yanında eşit uzaklıktadır;
            // _sirali ikisini birlikte seçmez.
            son, // görüntü unutulmuş: arabanın aynaya uzaklığı
            2 * d - v * t, // görüntünün de yaklaştığı unutulmuş
            2 * d - 3 * v * t, // görüntünün hızı 2v sanılmış
            2 * (d + v * t), // hareket yönünde işaret hatası
            d - 2 * v * t, // aynaya uzaklık 2v ile azalıyor sanılmış
            d, // başlangıçtaki araba – ayna uzaklığı
            2 * d, // başlangıçtaki araba – görüntü uzaklığı
            2 * v * t, // uzaklığın azalma miktarı
          ],
          'Araba $t s içinde $v·$t = ${v * t} cm yol alır ve aynaya uzaklığı '
          '$d − ${v * t} = $son cm olur. Görüntü aynanın arkasında aynı '
          'uzaklıkta oluştuğundan aradaki uzaklık 2·$son = ${2 * son} cm '
          'bulunur.',
          _no(a, b, c),
          unit: 'cm',
        );
      }
      if (c % 3 == 1) {
        final t = 2 + a % 5;
        final r = 10 * (1 + a ~/ 5 + 5 * kk);
        final d = v * t + r, ara = 2 * r;
        return _sayiSira(
          'Bir bilye, düşey duran bir düzlem aynaya dik doğrultuda $v cm/s '
          'sabit hızla yaklaşıyor. Bilye aynadan $d cm uzaktayken süre '
          'ölçülmeye başlanıyor. Bilye ile aynadaki görüntüsü arasındaki '
          'uzaklık kaç saniye sonra $ara cm olur?',
          t,
          [
            2 * t, // görüntünün hareketi unutulmuş
            if (d > ara && (d - ara) % v == 0) (d - ara) ~/ v,
            if (d % v == 0) d ~/ v, // aynaya varış süresi
            if (t.isEven) t ~/ 2, // aynaya uzaklık 2v ile azalıyor sanılmış
            if (2 * r % v == 0) t + 2 * r ~/ v, // işaret hatası
            if (r % v == 0) r ~/ v,
          ],
          'Başlangıçta bilye ile görüntüsü arasındaki uzaklık 2·$d = '
          '${2 * d} cm olur. Görüntü de aynaya $v cm/s hızla yaklaştığından '
          'aralarındaki uzaklık saniyede 2·$v = ${2 * v} cm azalır. Süre '
          '(${2 * d} − $ara) / ${2 * v} = $t s bulunur.',
          _no(a, b, c),
          unit: 's',
        );
      }
      final mum = a + 2;
      final idx = (b + 20 * kk) * 3 ~/ 2;
      final i = idx ~/ 9, j = idx % 9;
      final alfa = _aynaAcilari[i], beta = _aynaAcilari[j < i ? j : j + 1];
      final n1 = 360 ~/ alfa - 1, n2 = 360 ~/ beta - 1;
      final yon = n2 > n1 ? 'artar' : 'azalır';
      final fark = (n2 - n1).abs();
      return _sayiSira(
        'Aralarındaki açı $alfa° olan kesişen iki düzlem aynanın arasına '
        '$mum küçük mum yerleştiriliyor. Aynalar arasındaki açı $beta° '
        'yapılırsa aynalarda oluşan toplam görüntü sayısı kaç $yon?',
        mum * fark,
        [
          fark, // mum sayısıyla çarpılmamış
          mum * n2, // son görüntü sayısı
          mum * (fark + 1), // −1 yalnız bir sayımda uygulanmış
          mum * n1, // ilk görüntü sayısı
          if (fark > 1) mum * (fark - 1),
          mum * (alfa - beta).abs(),
        ],
        'Kesişen iki düzlem ayna arasındaki bir cismin görüntü sayısı '
        '360 / α − 1 olur. Her mumun görüntü sayısı $n1 iken $n2 olur. '
        'Toplam görüntü sayısı $mum·$n1 = ${mum * n1} iken $mum·$n2 = '
        '${mum * n2} olduğundan ${mum * fark} $yon.',
        _no(a, b, c),
      );
    },
    tyt: true,
  ),
  // 17 · Çukur ayna ve ince kenarlı mercek: 1/f bağıntısı ve büyütme.
  _fe(
    'mercek_ayna',
    'Küresel ayna ve ince mercekte görüntü, büyütme',
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) {
      final (p, q) = _oranlar[b]; // büyütme p / q
      final carpim = p * q;
      final s = (carpim >= 12 ? 1 : 12 ~/ carpim) * (1 + c ~/ 2);
      final f = carpim * s, dc = q * s * (p + q), dg = p * s * (p + q); // cm
      final h1 = q * (a + 2) / 4, h2 = p * (a + 2) / 4; // cm
      final ayna = a.isEven;
      final oran = kesir(p, q);
      if (c.isEven) {
        return _ondalikSira(
          'Odak uzaklığı $f cm olan '
          '${ayna ? 'bir çukur aynanın' : 'ince kenarlı bir merceğin'} asal '
          'ekseni üzerine, ${ayna ? 'aynadan' : 'mercekten'} $dc cm uzağa '
          'boyu ${tr(h1)} cm olan bir cisim yerleştiriliyor. Oluşan gerçek '
          'görüntünün boyu kaç cm olur?',
          h2,
          [
            h1 * q / p, // büyütme ters alınmış
            h1 * p / (p + q), // büyütme f / d(cisim) alınmış
            h1 * (p + q) / q, // büyütme d(görüntü) / f alınmış
            h1 * (p + q) / p, // büyütme d(cisim) / f alınmış
            h1 * p * p / (q * q), // büyütmenin karesi alınmış
            h1 * q / (p + q), // büyütme f / d(görüntü) alınmış
          ],
          '1/f = 1/d(cisim) + 1/d(görüntü) bağıntısından 1/d(görüntü) = '
          '1/$f − 1/$dc olur ve görüntü uzaklığı $dg cm bulunur. Büyütme '
          '$dg / $dc = $oran olduğundan görüntünün boyu ${tr(h1)}·$oran = '
          '${tr(h2)} cm olur.',
          _no(a, b, c),
          unit: 'cm',
        );
      }
      final fark = (dc - dg).abs();
      return _sayiSira(
        '${ayna ? 'Bir çukur aynanın' : 'İnce kenarlı bir merceğin'} asal '
        'ekseni üzerine, ${ayna ? 'aynadan' : 'mercekten'} $dc cm uzağa boyu '
        '${tr(h1)} cm olan bir cisim yerleştirildiğinde bir perde üzerinde '
        'boyu ${tr(h2)} cm olan net bir görüntü elde ediliyor. Buna göre '
        '${ayna ? 'aynanın' : 'merceğin'} odak uzaklığı kaç cm olur?',
        f,
        [
          dg, // görüntü uzaklığı odak sanılmış
          dc + dg, // ters değerler yerine uzaklıklar toplanmış
          2 * f, // odak yerine eğrilik merkezi (2F)
          if (dc.isEven) dc ~/ 2, // cisim 2F'de sanılmış
          if (dg.isEven) dg ~/ 2, // görüntü 2F'de sanılmış
          if (dc * dg % fark == 0) dc * dg ~/ fark, // ters değerlerde işaret
          if (f.isEven) f ~/ 2, // bulunan değer bir de ikiye bölünmüş
          dc, // cisim uzaklığı odak sanılmış
        ],
        'Büyütme ${tr(h2)} / ${tr(h1)} = $oran olduğundan görüntü uzaklığı '
        '$dc·$oran = $dg cm olur. 1/f = 1/$dc + 1/$dg bağıntısından '
        'f = $dc·$dg / ($dc + $dg) = $f cm bulunur.',
        _no(a, b, c),
        unit: 'cm',
      );
    },
  ),
  // 18 · Kırılma indisi (hız ya da dalga boyu oranından) ve görünür uzaklık.
  _fe(
    'kirilma',
    'Kırılma indisi, ışık hızı, dalga boyu ve görünür derinlik',
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) {
      final (ust, alt, hiz, l0, l1, birim) = _ortamlar[c ~/ 2];
      final indis = alt == 3 || alt == 7 ? kesir(ust, alt) : tr(ust / alt);
      final y = 5 * (b + 1); // cm
      final h = birim * (a + 1); // cm
      if (c.isEven) {
        final gor = h * alt / ust;
        final kap = h > 60 ? 'bir tankın' : 'bir kabın';
        return _ondalikSira(
          'Işığın boşluktaki hızı 3·10⁸ m/s, saydam bir sıvıdaki hızı $hiz '
          'm/s olarak veriliyor. Bu sıvıyla dolu $kap tabanındaki madenî '
          'para sıvı yüzeyinden $h cm aşağıdadır. Sıvı yüzeyinin $y cm '
          'yukarısından, yüzeye dik doğrultuda bakan bir gözlemci parayı '
          'kendisinden kaç cm uzakta görür? (Havanın kırılma indisini 1 '
          'alınız.)',
          y + gor,
          [
            y + h * ust / alt, // n'ye bölmek yerine n ile çarpmak
            gor, // gözlemcinin yüksekliği eklenmemiş
            (y + h).toDouble(), // kırılma hesaba katılmamış
            (y + h) * alt / ust, // gözlemcinin yüksekliği de n'ye bölünmüş
            (y + h) * ust / alt, // toplam uzaklık n ile çarpılmış
            y + h - gor, // görünür yükselme derinlik sanılmış
          ],
          'Sıvının kırılma indisi n = c / v = $indis olur. Paranın görünür '
          'derinliği h / n = $h·${kesir(alt, ust)} = ${tr(gor)} cm, '
          'gözlemciye görünür uzaklığı $y + ${tr(gor)} = ${tr(y + gor)} cm '
          'bulunur.',
          _no(a, b, c),
          unit: 'cm',
        );
      }
      final gor = h * ust / alt;
      return _ondalikSira(
        'Havadaki dalga boyu $l0 nm olan tek renkli ışığın saydam bir sıvı '
        'içindeki dalga boyu $l1 nm olarak ölçülüyor. Bu sıvının içinde, '
        'yüzeyden $y cm derinlikteki bir noktadan yüzeye dik doğrultuda '
        'yukarı bakan bir gözlemci, yüzeyin $h cm yukarısında asılı duran '
        'küçük bir lambayı kendisinden kaç cm uzakta görür? (Havanın kırılma '
        'indisini 1 alınız.)',
        y + gor,
        [
          y + h * alt / ust, // n ile çarpmak yerine n'ye bölmek
          gor, // gözlemcinin derinliği eklenmemiş
          (y + h).toDouble(), // kırılma hesaba katılmamış
          (y + h) * ust / alt, // gözlemcinin derinliği de n ile çarpılmış
          y * ust / alt + h, // n ile yanlış uzaklık çarpılmış
          (y + h) * alt / ust, // toplam uzaklık n'ye bölünmüş
          y + gor - h, // görünür yükselme uzaklık sanılmış
          y * alt / ust + gor, // gözlemcinin derinliği de n'ye bölünmüş
        ],
        'Sıvının kırılma indisi n = $l0 / $l1 = $indis olur. Sıvının içinden '
        'bakıldığında lamba yüzeyden h·n = $h·${kesir(ust, alt)} = '
        '${tr(gor)} cm yukarıda görünür; gözlemciye görünür uzaklığı $y + '
        '${tr(gor)} = ${tr(y + gor)} cm bulunur.',
        _no(a, b, c),
        unit: 'cm',
      );
    },
  ),
  // 19 · Fotoelektrik olay: eşik enerjisi, kinetik enerji, kesme gerilimi.
  _fe(
    'foton',
    'Foton enerjisi ve fotoelektrik olay',
    Difficulty.hard,
    BloomLevel.analiz,
    (a, b, c) {
      final k = c ~/ 2;
      if (c.isEven) {
        final w = 18 + a, k1 = 3 + b; // 0,1 eV
        final e1 = w + k1, e2 = e1 + const [6, 11, 15, 24, -2][k];
        final k2 = e2 - w;
        return _ondalikSira(
          'Bir fotoselin katoduna enerjisi ${tr(e1 / 10)} eV olan fotonlar '
          'düşürüldüğünde sökülen elektronların maksimum kinetik enerjisi '
          '${tr(k1 / 10)} eV oluyor. Aynı katoda enerjisi ${tr(e2 / 10)} eV '
          'olan fotonlar düşürülürse fotoelektronları durdurmak için gereken '
          'kesme (durdurma) gerilimi kaç V olur?',
          k2 / 10,
          [
            (e2 - k1) / 10, // eşik yerine ilk kinetik enerji çıkarılmış
            w / 10, // eşik enerjisi yanıt sanılmış
            e2 / 10, // foton enerjisi yanıt sanılmış
            (e2 - e1).abs() / 10, // foton enerjilerinin farkı
            k1 / 10, // kinetik enerji değişmez sanılmış
            k1 * e2 / e1 / 10, // kinetik enerji foton enerjisiyle orantılı
            (e2 + w) / 10, // eşik enerjisi eklenmiş
          ],
          'Katodun eşik enerjisi ${tr(e1 / 10)} − ${tr(k1 / 10)} = '
          '${tr(w / 10)} eV olur. İkinci durumda maksimum kinetik enerji '
          '${tr(e2 / 10)} − ${tr(w / 10)} = ${tr(k2 / 10)} eV olduğundan '
          'kesme gerilimi ${tr(k2 / 10)} V bulunur.',
          _no(a, b, c),
          unit: 'V',
        );
      }
      final idx = b + 20 * k;
      final i = idx ~/ 10, j = idx % 10;
      final (l1, e1) = _fotonlar[i];
      final (l2, e2) = _fotonlar[j < i ? j : j + 1];
      final w = 120 + 3 * a; // 0,01 eV
      final k1 = e1 - w, k2 = e2 - w;
      return _ondalikSira(
        'Bir fotokatoda dalga boyu $l1 nm olan ışık düşürüldüğünde sökülen '
        'elektronların maksimum kinetik enerjisi ${tr(k1 / 100)} eV oluyor. '
        'Aynı fotokatoda dalga boyu $l2 nm olan ışık düşürülürse sökülen '
        'elektronların maksimum kinetik enerjisi kaç eV olur? '
        '(h·c = 1240 eV·nm)',
        k2 / 100,
        [
          e2 / 100, // foton enerjisi yanıt sanılmış
          (e2 - k1) / 100, // eşik yerine ilk kinetik enerji çıkarılmış
          k1 * l1 / l2 / 100, // kinetik enerji frekansla orantılı sanılmış
          w / 100, // eşik enerjisi yanıt sanılmış
          k1 / 100, // kinetik enerji değişmez sanılmış
          (e2 - e1).abs() / 100, // foton enerjilerinin farkı
          k1 * l2 / l1 / 100, // dalga boyuyla doğru orantılı sanılmış
          (e2 + w) / 100, // eşik enerjisi eklenmiş
        ],
        'Foton enerjileri 1240 / $l1 = ${tr(e1 / 100)} eV ve 1240 / $l2 = '
        '${tr(e2 / 100)} eV olur. Eşik enerjisi ${tr(e1 / 100)} − '
        '${tr(k1 / 100)} = ${tr(w / 100)} eV olduğundan yeni maksimum '
        'kinetik enerji ${tr(e2 / 100)} − ${tr(w / 100)} = ${tr(k2 / 100)} '
        'eV bulunur.',
        _no(a, b, c),
        unit: '',
      );
    },
  ),
  // 20 · Yarı ömür ve alfa-beta bozunmalarında A ile Z değişimi.
  _fe(
    'cekirdek',
    'Yarı ömür ve radyoaktif bozunma hesapları',
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      final k = c ~/ 2;
      if (c.isEven) {
        // En az iki yarı ömür geçer; çeldiricilerin tümü başlangıç
        // miktarından küçüktür.
        final omur = 2 + a, n = 2 + k;
        final birim = const ['saat', 'gün', 'yıl'][a % 3];
        final ilk = (b + 1) << (n - 1), sure = n * omur; // 2 … 640 g
        final kalan = (b + 1) / 2; // 0,5 … 10 g
        final kalanSor = (a + b).isEven;
        return ondalikli(
          'Yarı ömrü $omur $birim olan radyoaktif bir izotopun $ilk gramlık '
          'örneği kapalı bir kapta bekletiliyor. $sure $birim sonunda '
          'örnekteki bu izotopun '
          '${kalanSor ? 'bozunmadan kalan' : 'bozunmuş olan'} miktarı kaç g '
          'olur?',
          kalanSor ? kalan : ilk - kalan,
          kalanSor
              ? [ilk - kalan, 2 * kalan, if (n > 2) ilk / 2, kalan / 2]
              : [kalan, ilk - 2 * kalan, if (n > 2) ilk / 2, ilk - kalan / 2],
          'Geçen süre $sure / $omur = $n yarı ömürdür. Her yarı ömürde miktar '
          'yarıya indiğinden kalan miktar $ilk / ${1 << n} = ${tr(kalan)} g '
          'olur.'
          '${kalanSor ? '' : ' Bozunan miktar $ilk − ${tr(kalan)} = ${tr(ilk - kalan)} g bulunur.'}',
          unit: 'g',
          positive: true,
        );
      }
      final z = 80 + a;
      final kutle = 2 * z + z ~/ 2 + 2 * k;
      final x = 1 + b % 4, y = 1 + b ~/ 4; // alfa ve beta sayısı
      final z2 = z - 2 * x + y, a2 = kutle - 4 * x;
      final nn = kutle - z, n2 = a2 - z2;
      final tur = a % 3;
      final (yanit, yanlis) = switch (tur) {
        0 => (z2, [z - 2 * x - y, z - 2 * x, z - 4 * x + y, z - x + y]),
        1 => (
          a2,
          [kutle - 4 * x - y, kutle - 2 * x, kutle - 4 * x + y, kutle - x],
        ),
        _ => (n2, [nn - 2 * x + y, nn - 2 * x, nn - 4 * x, a2]),
      };
      return sayisal(
        'Kütle numarası $kutle, atom numarası $z olan radyoaktif bir çekirdek '
        'art arda $x alfa ve $y beta (β⁻) bozunması yapıyor. Bozunmalar '
        'sonunda oluşan çekirdeğin '
        '${const ['atom numarası', 'kütle numarası', 'nötron sayısı'][tur]} '
        'kaç olur?',
        yanit,
        yanlis,
        'Alfa bozunması kütle numarasını 4, atom numarasını 2 azaltır; β⁻ '
        'bozunması kütle numarasını değiştirmez, atom numarasını 1 artırır. '
        'Kütle numarası $kutle − 4·$x = $a2, atom numarası $z − 2·$x + $y = '
        '$z2 olur.'
        '${tur == 2 ? ' Nötron sayısı $a2 − $z2 = $n2 bulunur.' : ''}',
        positive: true,
      );
    },
  ),
];
