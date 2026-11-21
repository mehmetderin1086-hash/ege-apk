// Lise fizik metin aileleri: elektrik, manyetizma, dalgalar, çembersel
// hareket, optik ve modern fizik. Her aile 5.000 ayrı vaka üretir; veriler
// sonuçlar tam ya da kısa ondalıklı çıkacak biçimde seçilmiştir.
import 'ortak.dart';

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
        return ondalikli(
          '${sec(_omikIletken, a + b)} uçları arasına ${tr(v1)} V gerilim '
          'uygulandığında iletkenden ${tr(i1 / 10)} A akım geçiyor. Sıcaklığı '
          'değişmeyen aynı iletkenin uçları arasındaki gerilim ${tr(v2)} V '
          'yapılırsa iletkenden geçen akım kaç A olur?',
          i2 / 10,
          [i1 * i1 / i2 / 10, r.toDouble(), (i2 - i1) / 10, (i1 + i2) / 10],
          'İletkenin direnci R = V / I = ${tr(v1)} / ${tr(i1 / 10)} = $r Ω '
          'olur. Direnç değişmediğinden yeni akım I = ${tr(v2)} / $r = '
          '${tr(i2 / 10)} A bulunur.',
          unit: 'A',
          positive: true,
        );
      }
      final (nl, ns) = _telOran[b];
      final r1 = ns * (1 + k), r2 = nl * (1 + k);
      final l1 = 1 + a % 5, l2 = l1 * nl; // m
      final s1 = 2 * (1 + a ~/ 5), s2 = s1 * ns; // onda bir mm²
      return sayisal(
        'Uzunluğu $l1 m, kesit alanı ${tr(s1 / 10)} mm² olan krom-nikel bir '
        'telin direnci $r1 Ω olarak ölçülüyor. Aynı maddeden yapılmış, '
        'uzunluğu $l2 m ve kesit alanı ${tr(s2 / 10)} mm² olan başka bir '
        'telin aynı sıcaklıktaki direnci kaç Ω olur?',
        r2,
        [
          r1 * nl * ns,
          r1 * nl,
          if (r1 * ns % nl == 0) r1 * ns ~/ nl,
          1 + k,
        ],
        'R = ρ·L / A olduğundan direnç uzunlukla doğru, kesit alanıyla ters '
        'orantılıdır. Uzunluk $nl katına, kesit alanı $ns katına çıktığı '
        'için R = $r1·$nl / $ns = $r2 Ω olur.',
        unit: 'Ω',
        positive: true,
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
      if (c.isEven) {
        return ondalikli(
          '$giris üreteçten çekilen akım (ana kol akımı) kaç A olur?',
          i,
          [v / (r1 + r2 + r3), v / r3, v / rp, v / (r1 + r2)],
          ortak,
          unit: 'A',
          positive: true,
        );
      }
      final i1 = j * (r2 ~/ g) / 10, i2 = j * (r1 ~/ g) / 10;
      return ondalikli(
        '$giris R₁ direncinden geçen akım kaç A olur?',
        i1,
        [i2, i, i / 2, v / r1],
        '$ortak Paralel kollarda akım dirençle ters orantılı paylaşılır: '
        'I₁ = ${tr(i)}·$r2 / ($r1 + $r2) = ${tr(i1)} A.',
        unit: 'A',
        positive: true,
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
      final celdirici = [e, ucret / gun, ucret / t, ucret * 10, ucret / 10];
      if (c.isEven) {
        return ondalikli(
          'Gücü $p W olan $cihaz her gün $t saat çalıştırılıyor. $soru',
          ucret,
          celdirici,
          hesap,
          unit: 'TL',
          positive: true,
        );
      }
      final akim = tr((5 + a) / 2);
      return ondalikli(
        '220 V gerilimli şehir şebekesine bağlı $cihaz çalışırken $akim A '
        'akım çekiyor ve her gün $t saat çalıştırılıyor. $soru',
        ucret,
        celdirici,
        'Cihazın gücü P = V·I = 220·$akim = $p W olur. $hesap',
        unit: 'TL',
        positive: true,
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
        return ondalikli(
          'Her birinin emk değeri ${tr(emk)} V, iç direnci ${tr(r)} Ω olan '
          '$n özdeş üreteç seri bağlanarak ${tr(rd)} Ω değerindeki bir '
          'direncin uçlarına bağlanıyor. Dirençten geçen akım kaç A olur?',
          i,
          [
            n * emk / (rd + r),
            emk / (rd + r),
            emk / (rd + n * r),
            n * emk / rd,
          ],
          'Seri bağlı üreteçlerde emk değerleri ve iç dirençler toplanır: '
          'toplam emk $n·${tr(emk)} = ${tr(n * emk)} V, toplam iç direnç '
          '$n·${tr(r)} = ${tr(n * r)} Ω olur. I = ${tr(n * emk)} / '
          '(${tr(rd)} + ${tr(n * r)}) = ${tr(i)} A.',
          unit: 'A',
          positive: true,
        );
      }
      final r0 = const [10, 20, 25, 50][b % 4] / 100;
      final r = n * r0, rd = tt - r0;
      return ondalikli(
        'Her birinin emk değeri ${tr(emk)} V, iç direnci ${tr(r)} Ω olan $n '
        'özdeş üreteç, aynı kutupları birleştirilerek paralel bağlanıyor ve '
        '${tr(rd)} Ω değerindeki bir direncin uçlarına bağlanıyor. Dirençten '
        'geçen akım kaç A olur?',
        i,
        [
          n * emk / (rd + r),
          emk / (rd + r),
          emk / (rd + n * r),
          n * emk / (rd + r0),
        ],
        'Özdeş üreteçler paralel bağlandığında emk değişmez (${tr(emk)} V), '
        'eşdeğer iç direnç ${tr(r)} / $n = ${tr(r0)} Ω olur. I = ${tr(emk)} '
        '/ (${tr(rd)} + ${tr(r0)}) = ${tr(i)} A.',
        unit: 'A',
        positive: true,
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
        return sayisal(
          'Aralarındaki uzaklık $d cm olan yüklü paralel iki levha arasında '
          'büyüklüğü $e V/m olan düzgün bir elektrik alan bulunuyor. Yükü '
          '$q µC olan bir parçacık levhalardan birinden diğerine '
          'götürüldüğünde elektriksel kuvvetin yaptığı işin büyüklüğü kaç µJ '
          '(mikrojoule) olur?',
          w,
          [w * 100, v, q * e, e * d],
          'Levhalar arasındaki potansiyel farkı V = E·d = $e·${tr(d / 100)} '
          '= $v V olur. İşin büyüklüğü W = q·V = $q·$v = $w µJ bulunur.',
          positive: true,
        );
      }
      final vk = 10 * (a + 2);
      final dv = const [20, 40, 50, 80, 100][k];
      final w = q * dv;
      return sayisal(
        'Bir elektrik alanında, potansiyeli $vk V olan K noktasındaki +$q µC '
        'yüklü parçacığı L noktasına sabit hızla götürmek için elektriksel '
        'kuvvetlere karşı $w µJ iş yapılıyor. L noktasının potansiyeli kaç V '
        'olur?',
        vk + dv,
        [vk - dv, dv, vk + w, w],
        'K ile L arasındaki potansiyel farkı W / q = $w / $q = $dv V olur. '
        'Pozitif yük elektriksel kuvvetlere karşı taşındığından L daha '
        'yüksek potansiyeldedir: $vk + $dv = ${vk + dv} V.',
        unit: 'V',
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
        return sayisal(
          'Sığaları $c1 µF ve $c2 µF olan iki kondansatör seri bağlanmış, '
          'bu kola sığası $c3 µF olan üçüncü bir kondansatör paralel '
          'bağlanmıştır. Sistem $v V gerilimli bir üretecin uçlarına bağlanıp '
          'tamamen dolduğunda üreteçten çekilen toplam yük kaç µC '
          '(mikrokulon) olur?',
          q,
          [(c1 + c2 + c3) * v, cs * v, (c1 + c2) * v, c3 * v],
          'Seri kolun eşdeğer sığası $c1·$c2 / ($c1 + $c2) = $cs µF, paralel '
          'kolla birlikte eşdeğer sığa $cs + $c3 = ${cs + c3} µF olur. '
          'Q = C·V = ${cs + c3}·$v = $q µC.',
          positive: true,
        );
      }
      final n = 2 + k;
      final seri = (a + b).isOdd;
      final tek = seri ? n * (a + 1) : a + 1; // µF
      final ces = seri ? a + 1 : n * (a + 1);
      final v = 2 * (b + 1);
      final e = ces * v * v ~/ 2;
      return sayisal(
        'Her birinin sığası $tek µF olan $n özdeş kondansatör birbirine '
        '${seri ? 'seri' : 'paralel'} bağlanıyor ve $v V gerilimli bir '
        'üretecin uçlarına bağlanarak dolduruluyor. Kondansatörlerde '
        'depolanan toplam enerji kaç µJ (mikrojoule) olur?',
        e,
        [
          ces * v * v,
          (seri ? n * tek : tek) * v * v ~/ 2,
          ces * v ~/ 2,
          tek * v * v,
        ],
        '${seri ? 'Özdeş $n kondansatör seri bağlandığında eşdeğer sığa '
                  '$tek / $n = $ces µF olur.' : 'Özdeş $n kondansatör paralel '
                  'bağlandığında eşdeğer sığa $n·$tek = $ces µF olur.'} '
        'E = C·V² / 2 = $ces·$v² / 2 = $e µJ.',
        positive: true,
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
        return ondalikli(
          'Büyüklüğü $alan T olan düzgün bir manyetik alanın içinde, $l cm '
          'uzunluğundaki düz bir iletken telden $i A akım geçiyor. '
          '${dik ? 'Tel, manyetik alan çizgilerine dik konumdadır.' : 'Tel, '
                    'manyetik alan çizgileriyle $aci° açı yapmaktadır '
                    '(sin $aci° = $sinus).'} '
          'Tele etkiyen manyetik kuvvetin büyüklüğü kaç N olur?',
          f,
          [
            if (!dik) tam,
            if (c10 > 0) tam * c10 / 10,
            f * 100,
            f / i,
            f * 10,
            f / 10,
          ],
          dik
              ? 'Tel alana dik olduğundan F = B·I·L = $alan·$i·'
                    '${tr(l / 100)} = ${tr(f, 3)} N olur.'
              : 'F = B·I·L·sin θ = $alan·$i·${tr(l / 100)}·$sinus = '
                    '${tr(f, 3)} N olur.',
          unit: 'N',
          digits: 3,
          positive: true,
        );
      }
      final q = 1 + a % 5, mv = 2 + a ~/ 5;
      final alan = tr((b + 1) / 10); // 0,1 … 2 T
      final f = q * mv * (b + 1) * s10 / 1000;
      final tam = q * mv * (b + 1) / 100;
      return ondalikli(
        'Yükü $q µC olan bir parçacık, büyüklüğü $alan T olan düzgün bir '
        'manyetik alana $mv·10⁵ m/s hızla giriyor. '
        '${dik ? 'Parçacığın hızı manyetik alan çizgilerine diktir.' : 'Parçacığın '
                  'hızı manyetik alan çizgileriyle $aci° açı yapmaktadır '
                  '(sin $aci° = $sinus).'} '
        'Parçacığa etkiyen manyetik kuvvetin büyüklüğü kaç N olur? '
        '(1 µC = 10⁻⁶ C)',
        f,
        [
          if (!dik) tam,
          if (c10 > 0) tam * c10 / 10,
          f * 10,
          f / 10,
          f * 100,
        ],
        dik
            ? 'Hız alana dik olduğundan F = q·v·B = $q·10⁻⁶·$mv·10⁵·$alan = '
                  '${tr(f, 3)} N olur.'
            : 'F = q·v·B·sin θ = $q·10⁻⁶·$mv·10⁵·$alan·$sinus = '
                  '${tr(f, 3)} N olur.',
        unit: 'N',
        digits: 3,
        positive: true,
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
            [if (np * vp % ns == 0) np * vp ~/ ns, v, vp * ns, vp + vs],
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
  for (var n = 10; n <= 20; n++) _dolgu(n),
];

// Geçici dolgu: aileler tamamlanınca kaldırılacak.
AdvancedFamily _dolgu(int n) => _fe(
  'dolgu$n',
  'Geçici dolgu ailesi $n',
  Difficulty.easy,
  BloomLevel.uygulama,
  (a, b, c) => sayisal(
    'Geçici dolgu sorusu $n: $a, $b ve $c sayılarının toplamı kaçtır?',
    a + b + c,
    const [],
    'Toplam ${a + b + c} olur; bu aile geçicidir.',
  ),
);
