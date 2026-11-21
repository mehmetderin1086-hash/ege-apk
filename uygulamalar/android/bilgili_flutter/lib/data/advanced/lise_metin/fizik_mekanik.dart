// Lise fizik · mekanik, enerji, basınç, kaldırma kuvveti ve ısı aileleri.
// Her aile 25 × 20 × 10 koordinattan 5.000 ayrı sayısal soru üretir; kökte
// görünen veriler a, b ve c ile birebir belirlenir.
import 'dart:math' as math;

import 'ortak.dart';

const _tyt = ExamKind.tyt, _ayt = ExamKind.ayt;
const _fizik = 'Fizik';

/// İki ondalığa sığmayan çeldiriciyi okunur bir değere yuvarlar.
num _yuvarla(num x) {
  final y = (x * 100).roundToDouble() / 100;
  if ((x - y).abs() < 1e-7) return y;
  return x.abs() >= 10 ? x.roundToDouble() : (x * 10).roundToDouble() / 10;
}

String _yaz(num x, String unit, bool yuzde) =>
    yuzde ? '%${tr(x)}' : birimli(tr(x), unit);

/// Pozitif sayısal yanıtlı soru. Anahtar iki ondalıkta kesin olmalıdır;
/// hata çeldiricileri yetmezse anahtarın katlarıyla tamamlanır.
AdvancedItem _s(
  String kok,
  num dogru,
  Iterable<num> hatalar,
  String aciklama, {
  String unit = '',
  bool yuzde = false,
}) {
  final k = (dogru * 100).roundToDouble() / 100;
  if ((dogru - k).abs() > 1e-7 || k <= 0) {
    throw StateError('Kesin olmayan anahtar $dogru: $kok');
  }
  final havuz = <num>[...hatalar, k * 2, k / 2, k * 1.5, k * 3, k / 4, k * 4, k * 5]
      .where((x) => x.isFinite && x > 0 && (!yuzde || x < 100))
      .map(_yuvarla)
      .where((x) => x > 0);
  return secenekli(
    kok,
    _yaz(k, unit, yuzde),
    [
      ...havuz.map((x) => _yaz(x, unit, yuzde)),
      if (yuzde) ...[for (final e in [5, 10, 15, 20, 30]) _yaz((k + e) % 100 + 1, unit, true)],
    ],
    aciklama,
  );
}

const _g = 'Sürtünmeler önemsizdir; g = 10 m/s² alınız.';

// 1 · Düzgün doğrusal hareket ve km/sa ↔ m/s dönüşümü.
final _f01 = lmAile(
  'fm_duzgun_hareket',
  'Düzgün doğrusal hareket ve birim dönüşümü',
  Topic.physics,
  Difficulty.easy,
  BloomLevel.anlama,
  (a, b, c) {
    final vk = 9 * (a + 2); // 18 … 234 km/sa
    final vm = 2.5 * (a + 2); // 5 … 65 m/s
    final arac = a < 3 ? 'bisikletli' : (a < 13 ? 'otomobil' : 'yüksek hızlı tren');
    final t = 2 * (b + 1) + 40 * (c ~/ 3); // 2 … 160 s
    final yol = (vm * t).round(); // 10 … 10400 m
    final cevir = '$vk km/sa = $vk / 3,6 = ${tr(vm)} m/s';
    if (c % 3 == 0) {
      return _s(
        'Düz bir yolda $vk km/sa sabit hızla ilerleyen bir $arac, $t saniyede '
        'kaç metre yol alır?',
        yol,
        [vk * t, vk * 3.6 * t, vk * t / 60],
        '$cevir olur. Alınan yol ${tr(vm)} · $t = $yol m bulunur.',
        unit: 'm',
      );
    }
    if (c % 3 == 1) {
      return _s(
        'Düz bir yolda sabit hızla ilerleyen bir $arac, $yol metrelik bölümü '
        '$t saniyede geçiyor. Buna göre sürat kaç km/sa olur?',
        vk,
        [vm, vm / 3.6, vm * 6],
        'Sürat $yol / $t = ${tr(vm)} m/s olur. km/sa birimine çevirmek için 3,6 '
        'ile çarpılır: ${tr(vm)} · 3,6 = $vk km/sa.',
        unit: 'km/sa',
      );
    }
    return _s(
      'Düz bir yolda $vk km/sa sabit hızla ilerleyen bir $arac, uzunluğu '
      '$yol m olan bir bölümü kaç saniyede geçer?',
      t,
      [yol / vk, t * 3.6, yol / (vk * 3.6)],
      '$cevir olur. Geçiş süresi $yol / ${tr(vm)} = $t s bulunur.',
      unit: 's',
    );
  },
  exam: _tyt,
  lesson: _fizik,
);

// 2 · Bağıl hız: aynı yönlü ve zıt yönlü araçlar, akıntılı nehirde tekne.
final _f02 = lmAile(
  'fm_bagil_hareket',
  'Bağıl hız: yetişme, karşılaşma ve akıntı',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final v2 = 6 + a, dv = 2 + b % 4, v1 = v2 + dv; // 6 … 35 m/s
      final t = 10 * (b ~/ 4 + 1) + 50 * k; // 10 … 200 s, yol 20 … 1000 m
      final d = dv * t;
      return _s(
        'Doğrusal bir yolda aynı yönde ilerleyen iki araçtan arkadaki $v1 m/s, '
        'öndeki $v2 m/s sabit hızla gitmektedir. Aralarındaki uzaklığın $d m '
        'olduğu andan kaç saniye sonra arkadaki araç öndekine yetişir?',
        t,
        [d / (v1 + v2), d / v1, d / v2],
        'Arkadaki araç öndekine her saniye $v1 − $v2 = $dv m yaklaşır. '
        'Yetişme süresi $d / $dv = $t s olur.',
        unit: 's',
      );
    }
    if (c % 3 == 1) {
      final v1 = 6 + a, v2 = 5 + 3 * (b % 4); // 6 … 30 ve 5 … 14 m/s
      final t = 5 * (b ~/ 4 + 1) + 25 * k; // 5 … 75 s
      final d = (v1 + v2) * t;
      return _s(
        'Doğrusal bir yolun iki ucundan aynı anda birbirine doğru harekete geçen '
        'iki araçtan biri $v1 m/s, diğeri $v2 m/s sabit hızla ilerlemektedir. '
        'Başlangıçta aralarındaki uzaklık $d m olduğuna göre araçlar kaç saniye '
        'sonra karşılaşır?',
        t,
        [if (v1 != v2) d / (v1 - v2).abs(), d / v1, d / v2, 2 * t],
        'Zıt yönlü araçlar birbirine her saniye $v1 + $v2 = ${v1 + v2} m yaklaşır. '
        'Karşılaşma süresi $d / ${v1 + v2} = $t s olur.',
        unit: 's',
      );
    }
    final vt = 6 + a % 5, va = 1 + a ~/ 5; // tekne 6 … 10, akıntı 1 … 5 m/s
    final ileri = b.isEven;
    final hiz = ileri ? vt + va : vt - va;
    final t = 10 * (b ~/ 2 + 1) + 100 * k; // 10 … 300 s
    final d = hiz * t;
    return _s(
      'Akıntı hızının $va m/s olduğu bir nehirde, suya göre hızı $vt m/s olan '
      'bir motorlu tekne kıyıya paralel olarak '
      '${ileri ? 'akıntıyla aynı yönde' : 'akıntıya karşı'} ilerliyor. Tekne, '
      'kıyıda duran bir gözlemciye göre $d metrelik yolu kaç saniyede alır?',
      t,
      [d / vt, d / (ileri ? vt - va : vt + va), d / va],
      'Teknenin kıyıya göre hızı $vt ${ileri ? '+' : '−'} $va = $hiz m/s olur. '
      'Süre $d / $hiz = $t s bulunur.',
      unit: 's',
    );
  },
  exam: _tyt,
  lesson: _fizik,
);

// 3 · Sabit ivmeli hareket: v = v₀ + at ve x = v₀t + ½at².
final _f03 = lmAile(
  'fm_ivmeli',
  'Sabit ivmeli harekette hız ve yer değiştirme',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final v0 = 2 + a; // 2 … 26 m/s
    final t = 2 + b % 10; // 2 … 11 s
    final ivme = 0.5 * (1 + b ~/ 10 + 2 * (c ~/ 3)); // 0,5 … 4 m/s²
    final v = v0 + ivme * t; // en çok 70 m/s
    final x = v0 * t + 0.5 * ivme * t * t;
    final arac = v <= 40 ? 'otomobil' : 'yarış otomobili';
    if (c % 3 == 0) {
      return _s(
        'Doğrusal bir yolda $v0 m/s hızla ilerleyen bir $arac, ${tr(ivme)} m/s² '
        'büyüklüğünde sabit ivmeyle $t saniye boyunca hızlanıyor. Bu sürenin '
        'sonunda hız kaç m/s olur?',
        v,
        [ivme * t, v0 + ivme, v0 + ivme * t / 2, v0 + ivme * t * 2],
        'v = v₀ + a·t bağıntısından v = $v0 + ${tr(ivme)} · $t = ${tr(v)} m/s olur.',
        unit: 'm/s',
      );
    }
    if (c % 3 == 1) {
      return _s(
        'Doğrusal bir yolda $v0 m/s hızla ilerleyen bir $arac, ${tr(ivme)} m/s² '
        'büyüklüğünde sabit ivmeyle $t saniye boyunca hızlanıyor. Hızlanma '
        'süresince alınan yol kaç metredir?',
        x,
        [v0 * t + ivme * t * t, 0.5 * ivme * t * t, v0 * t, v * t],
        'x = v₀·t + ½·a·t² bağıntısından x = $v0 · $t + ½ · ${tr(ivme)} · $t² = '
        '${v0 * t} + ${tr(0.5 * ivme * t * t)} = ${tr(x)} m olur.',
        unit: 'm',
      );
    }
    return _s(
      'Doğrusal bir yolda ilerleyen bir $arac, sabit ivmeyle hızlanarak hızını '
      '$t saniyede $v0 m/s değerinden ${tr(v)} m/s değerine çıkarıyor. Bu '
      '$t saniyelik sürede alınan yol kaç metredir?',
      x,
      [v * t, v0 * t, (v - v0) * t / 2, (v0 + v) * t],
      'Sabit ivmeli harekette ortalama hız ($v0 + ${tr(v)}) / 2 = '
      '${tr((v0 + v) / 2)} m/s olur. Alınan yol ${tr((v0 + v) / 2)} · $t = '
      '${tr(x)} m bulunur.',
      unit: 'm',
    );
  },
  exam: _ayt,
  lesson: _fizik,
);

// 4 · Zamansız hız bağıntısı: fren mesafesi ve kalkış.
const _frenCifti = <(int, double)>[
  (10, 2), (10, 2.5), (10, 4), (12, 2), (12, 3), (12, 4), (15, 2.5),
  (15, 3), (15, 5), (16, 2), (16, 4), (18, 3), (18, 6), (20, 2.5),
  (20, 4), (20, 5), (24, 3), (24, 4), (24, 6), (25, 2.5), (25, 5),
  (30, 5), (30, 6), (30, 7.5), (36, 6),
];

final _f04 = lmAile(
  'fm_fren',
  'Zamansız hız bağıntısı: fren mesafesi ve kalkış',
  Topic.physics,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final (v0, ivme) = _frenCifti[a];
      final fren = v0 * v0 / (2 * ivme); // 12,5 … 125 m
      final pay = b + 1 + 20 * k; // 1 … 80 m
      final engel = fren + pay;
      return _s(
        'Düz bir yolda $v0 m/s hızla ilerleyen bir otomobilin sürücüsü, '
        '${tr(engel)} m ilerideki engeli gördüğü anda frene basıyor ve otomobil '
        '${tr(ivme)} m/s² büyüklüğünde sabit ivmeyle yavaşlıyor. Otomobil engele '
        'kaç metre kala durur?',
        pay,
        [fren, engel - fren / 2, engel - 2 * fren, engel],
        'v² = v₀² − 2·a·x bağıntısında v = 0 alınırsa fren mesafesi '
        '$v0² / (2 · ${tr(ivme)}) = ${tr(fren)} m olur. Engele kalan uzaklık '
        '${tr(engel)} − ${tr(fren)} = $pay m bulunur.',
        unit: 'm',
      );
    }
    if (c % 3 == 1) {
      final x1 = 8 * (a + 2); // 16 … 208 m
      final a1 = const [1.0, 1.5, 2.0, 2.5, 3.0][b % 5];
      final a2 = const [4, 5, 8, 10][b ~/ 5];
      final kare = (2 * a1 * x1).round(); // v²
      final x2 = a1 * x1 / a2;
      final giris =
          'Trafik ışığında duran bir otomobil ${tr(a1)} m/s² büyüklüğünde sabit '
          'ivmeyle kalkışa geçip $x1 m yol alıyor. Tam bu noktada sürücü frene '
          'basıyor ve otomobil $a2 m/s² büyüklüğünde sabit ivmeyle yavaşlayarak '
          'duruyor.';
      final cozum =
          'Frene basıldığı anda v² = 2 · ${tr(a1)} · $x1 = $kare olur. Fren '
          'mesafesi v² / (2 · $a2) = $kare / ${2 * a2} = ${tr(x2)} m bulunur.';
      if (k == 0) {
        return _s(
          '$giris Otomobilin frene basıldıktan sonra durana kadar aldığı yol '
          'kaç metredir?',
          x2,
          [x1 * a2 / a1, x1, 2 * x2, x1 + x2],
          cozum,
          unit: 'm',
        );
      }
      if (k == 1) {
        return _s(
          '$giris Otomobilin kalkıştan durana kadar aldığı toplam yol kaç '
          'metredir?',
          x1 + x2,
          [x1 + x1 * a2 / a1, 2 * x1, x2, x1 + 2 * x2],
          '$cozum Toplam yol $x1 + ${tr(x2)} = ${tr(x1 + x2)} m olur.',
          unit: 'm',
        );
      }
      return _s(
        '$giris Otomobilin fren mesafesi, hızlanırken aldığı yoldan kaç metre '
        'kısadır?',
        x1 - x2,
        [x2, x1 + x2, x1 * a2 / a1 - x1, x1 - 2 * x2],
        '$cozum Aradaki fark $x1 − ${tr(x2)} = ${tr(x1 - x2)} m olur.',
        unit: 'm',
      );
    }
    final v0 = 16 + a; // 16 … 40 m/s
    final v = v0 - (1 + b ~/ 4 + 5 * k); // en az 1 m/s
    final ivme = const [1.0, 2.0, 2.5, 5.0][b % 4];
    final x = (v0 * v0 - v * v) / (2 * ivme);
    return _s(
      'Otoyolda $v0 m/s hızla ilerleyen bir otomobil, hız sınırının $v m/s '
      'olduğu bölgeye yaklaşırken ${tr(ivme)} m/s² büyüklüğünde sabit ivmeyle '
      'yavaşlıyor. Otomobilin bu bölgeye tam $v m/s hızla girebilmesi için '
      'sürücü, bölgenin başlangıcından kaç metre önce yavaşlamaya başlamalıdır?',
      x,
      [
        (v0 - v) * (v0 - v) / (2 * ivme),
        (v0 * v0 - v * v) / ivme,
        v0 * v0 / (2 * ivme),
        (v0 - v) / ivme,
      ],
      'v² = v₀² − 2·a·x bağıntısından x = ($v0² − $v²) / (2 · ${tr(ivme)}) = '
      '(${v0 * v0} − ${v * v}) / ${tr(2 * ivme)} = ${tr(x)} m olur.',
      unit: 'm',
    );
  },
  exam: _ayt,
  lesson: _fizik,
);

// 5 · Serbest düşme.
final _f05 = lmAile(
  'fm_serbest_dusme',
  'Serbest düşmede süre, hız ve yükseklik',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final t = 1 + b % 5; // 1 … 5 s
      final kalan = 1 + a + 25 * (b ~/ 5) + 100 * k; // 1 … 400 m
      final dusme = 5 * t * t;
      final h = dusme + kalan; // 6 … 525 m
      return _s(
        'Yerden $h m yükseklikte havada asılı duran bir helikopterden bir paket '
        'serbest bırakılıyor. Paket, bırakıldıktan $t saniye sonra yerden kaç '
        'metre yüksekte olur? ($_g)',
        kalan,
        [h - 10 * t, dusme, h - 10 * t * t, h - 5 * t],
        'Paketin $t saniyede düştüğü yol ½·g·t² = 5 · $t² = $dusme m olur. '
        'Yerden yükseklik $h − $dusme = $kalan m bulunur.',
        unit: 'm',
      );
    }
    if (c % 3 == 1) {
      final t = 1 + b % 5; // 1 … 5 s
      final alt = 2 + a + 25 * (b ~/ 5) + 100 * k; // 2 … 301 m
      final dusme = 5 * t * t;
      final ust = alt + dusme;
      return _s(
        'Yerden $ust m yükseklikte sabit duran bir balondan serbest bırakılan '
        'bir cisim, yerden $alt m yükseklikteki bir noktadan kaç m/s hızla '
        'geçer? ($_g)',
        10 * t,
        [math.sqrt(20.0 * ust), dusme, 5 * t, 20 * t],
        'Cismin düştüğü yol $ust − $alt = $dusme m olur. v² = 2·g·h bağıntısından '
        'v² = 2 · 10 · $dusme = ${20 * dusme}, v = ${10 * t} m/s bulunur.',
        unit: 'm/s',
      );
    }
    final t = 3 + b % 5; // K cisminin düşme süresi: 3 … 7 s
    final gec = 1 + (b ~/ 5) % 2; // 1 ya da 2 s
    final kalan = 1 + a + 25 * (b ~/ 10) + 50 * k; // 1 … 150 m
    final hk = 5 * t * t; // 45 … 245 m
    final dusme = 5 * (t - gec) * (t - gec);
    final hl = dusme + kalan;
    return _s(
      'K cismi yerden $hk m yükseklikten serbest bırakılıyor. K cismi '
      'bırakıldıktan $gec saniye sonra L cismi yerden $hl m yükseklikten '
      'serbest bırakılıyor. K cismi yere çarptığı anda L cismi yerden kaç metre '
      'yüksekte olur? ($_g)',
      kalan,
      [hl - hk, dusme, hl - 5 * gec * gec, hk - dusme, hl - 10 * (t - gec)],
      'K cismi için $hk = 5·t² eşitliğinden düşme süresi $t s olur. L cismi '
      '$t − $gec = ${t - gec} s düşer ve 5 · ${t - gec}² = $dusme m yol alır. '
      'Yerden yüksekliği $hl − $dusme = $kalan m bulunur.',
      unit: 'm',
    );
  },
  exam: _ayt,
  lesson: _fizik,
);

// 6 · Aşağıdan yukarı düşey atış.
final _f06 = lmAile(
  'fm_dusey_atis',
  'Aşağıdan yukarı düşey atışta süre ve yükseklik',
  Topic.physics,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final v0 = 12 + 2 * a; // 12 … 60 m/s
      final t = 1 + b % 2; // 1 ya da 2 s
      final h = 3 + 2 * (b ~/ 2) + 20 * k; // 3 … 81 m
      final y = h + v0 * t - 5 * t * t;
      return _s(
        'Yerden $h m yükseklikteki bir platformda bulunan fırlatıcı, bir topu '
        '$v0 m/s hızla düşey yukarı doğru fırlatıyor. Top, fırlatıldıktan '
        '$t saniye sonra yerden kaç metre yüksekte olur? ($_g)',
        y,
        [v0 * t - 5 * t * t, h + v0 * t, h + v0 * t - 10 * t * t, h + v0 * t + 5 * t * t],
        'Topun platforma göre yer değiştirmesi v₀·t − ½·g·t² = $v0 · $t − 5 · $t² = '
        '${v0 * t - 5 * t * t} m olur. Yerden yükseklik $h + ${v0 * t - 5 * t * t} = '
        '$y m bulunur.',
        unit: 'm',
      );
    }
    if (c % 3 == 1) {
      final v0 = 12 + 2 * a; // 12 … 60 m/s
      final h = 2 + b + 20 * k; // 2 … 61 m
      final tepe = v0 * v0 / 20; // 7,2 … 180 m
      return _s(
        'Yerden $h m yükseklikteki bir terasa kurulan fırlatıcı, bir bilyeyi '
        '$v0 m/s hızla düşey yukarı doğru fırlatıyor. Bilyenin yerden '
        'çıkabildiği en büyük yükseklik kaç metredir? ($_g)',
        h + tepe,
        [tepe, h + 2 * tepe, h + tepe / 2, h + v0],
        'Bilye fırlatıldığı noktadan v₀² / (2·g) = $v0² / 20 = ${tr(tepe)} m '
        'yükselir. Yerden en büyük yükseklik $h + ${tr(tepe)} = ${tr(h + tepe)} m '
        'olur.',
        unit: 'm',
      );
    }
    final v = 2 + a; // 2 … 26 m/s
    final n = b + 1;
    final t = 0.2 * n; // 0,2 … 4 s
    final v0 = v + 2 * n; // 4 … 66 m/s
    final giris =
        'Yerden düşey yukarı doğru fırlatılan bir cismin hızı, fırlatıldıktan '
        '${tr(t)} saniye sonra yukarı yönde $v m/s oluyor.';
    final cozum =
        'v = v₀ − g·t bağıntısından fırlatma hızı v₀ = $v + 10 · ${tr(t)} = $v0 m/s '
        'olur.';
    if (k == 0) {
      return _s(
        '$giris Cisim, fırlatıldıktan kaç saniye sonra en yüksek noktaya '
        'ulaşır? ($_g)',
        v0 / 10,
        [v / 10, v0 / 5, v0 / 10 + t, v0 / 20],
        '$cozum Çıkış süresi v₀ / g = $v0 / 10 = ${tr(v0 / 10)} s bulunur.',
        unit: 's',
      );
    }
    if (k == 1) {
      return _s(
        '$giris Cisim, fırlatıldıktan kaç saniye sonra yere geri döner? ($_g)',
        v0 / 5,
        [v0 / 10, v / 5, v / 5 + t, v0 / 2.5],
        '$cozum Çıkış süresi $v0 / 10 = ${tr(v0 / 10)} s, uçuş süresi bunun iki '
        'katı olan ${tr(v0 / 5)} s bulunur.',
        unit: 's',
      );
    }
    return _s(
      '$giris Cismin yerden çıkabildiği en büyük yükseklik kaç metredir? ($_g)',
      v0 * v0 / 20,
      [v * v / 20, v0 * v0 / 10, v0 * t, v0 * v0 / 40],
      '$cozum En büyük yükseklik v₀² / (2·g) = $v0² / 20 = ${tr(v0 * v0 / 20)} m '
      'bulunur.',
      unit: 'm',
    );
  },
  exam: _ayt,
  lesson: _fizik,
);

// 7 · Yatay atış.
final _f07 = lmAile(
  'fm_yatay_atis',
  'Yatay atışta uçuş süresi ve menzil',
  Topic.physics,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final t = 1 + b % 5; // 1 … 5 s
      final h = 5 * t * t; // 5 … 125 m
      final v1 = 4 + a; // 4 … 28 m/s
      final fark = 1 + b ~/ 5 + 4 * k; // 1 … 16 m/s
      final v2 = v1 + fark;
      final zit = k.isEven;
      final ara = zit ? (v1 + v2) * t : fark * t;
      return _s(
        'Yerden $h m yükseklikteki bir kulenin tepesinden K ve L topları aynı '
        'anda, ${zit ? 'birbirine zıt yönlerde' : 'aynı yönde'} yatay olarak '
        'atılıyor. K topunun atılma hızı $v1 m/s, L topunun atılma hızı $v2 m/s '
        'olduğuna göre topların yere düştüğü noktalar arasındaki uzaklık kaç '
        'metredir? ($_g)',
        ara,
        [zit ? fark * t : (v1 + v2) * t, v2 * t, v1 * t, zit ? v1 + v2 : fark],
        '$h = 5·t² eşitliğinden uçuş süresi $t s olur. Menziller $v1 · $t = '
        '${v1 * t} m ve $v2 · $t = ${v2 * t} m bulunur. Toplar '
        '${zit ? 'zıt yönlerde atıldığından uzaklık ${v1 * t} + ${v2 * t}' : 'aynı yönde atıldığından uzaklık ${v2 * t} − ${v1 * t}'} = '
        '$ara m olur.',
        unit: 'm',
      );
    }
    if (c % 3 == 1) {
      final v0 = 4 + a; // 4 … 28 m/s
      final t = 1 + b % 4; // 1 … 4 s
      final kalan = 1 + b ~/ 4 + 5 * k; // 1 … 15 m
      final dusme = 5 * t * t;
      final h = dusme + kalan;
      final d = v0 * t;
      return _s(
        'Yerden $h m yükseklikteki bir noktadan $v0 m/s hızla yatay olarak '
        'atılan bir top, atış noktasından yatayda $d m uzakta bulunan düşey bir '
        'duvara çarpıyor. Top duvara yerden kaç metre yükseklikte çarpar? ($_g)',
        kalan,
        [dusme, h - 5 * t, h - 10 * t, h - dusme / 2, h - 2 * dusme],
        'Top duvara $d / $v0 = $t s sonra ulaşır. Bu sürede düşeyde 5 · $t² = '
        '$dusme m düşer. Çarpma yüksekliği $h − $dusme = $kalan m olur.',
        unit: 'm',
      );
    }
    final v0 = 3 + a; // 3 … 27 m/s
    final n = b + 2;
    final t = 0.2 * n; // 0,4 … 4,2 s
    final h = 0.2 * n * n; // 0,8 … 88,2 m
    final x = v0 * t;
    final sure =
        'h = ½·g·t² bağıntısından t² = ${tr(h)} / 5 = ${tr(t * t)}, t = ${tr(t)} s olur.';
    if (k == 0) {
      return _s(
        'Yerden ${tr(h)} m yükseklikteki bir noktadan $v0 m/s hızla yatay '
        'olarak atılan bir bilye, atış noktasının düşeyinden kaç metre uzakta '
        'yere düşer? ($_g)',
        x,
        [v0 * t * t, v0 * h, 2 * x, v0 * t / 2],
        '$sure Menzil v₀·t = $v0 · ${tr(t)} = ${tr(x)} m bulunur.',
        unit: 'm',
      );
    }
    if (k == 1) {
      return _s(
        '$v0 m/s hızla yatay olarak atılan bir bilye, atış noktasının '
        'düşeyinden ${tr(x)} m uzakta yere düşüyor. Bilye yerden kaç metre '
        'yükseklikten atılmıştır? ($_g)',
        h,
        [2 * h, 5 * t, 10 * t, h / 2],
        'Uçuş süresi ${tr(x)} / $v0 = ${tr(t)} s olur. Atış yüksekliği '
        '½·g·t² = 5 · ${tr(t)}² = ${tr(h)} m bulunur.',
        unit: 'm',
      );
    }
    return _s(
      'Yerden ${tr(h)} m yükseklikten yatay olarak atılan bir bilye, atış '
      'noktasının düşeyinden ${tr(x)} m uzakta yere düşüyor. Bilyenin atılma '
      'hızı kaç m/s olur? ($_g)',
      v0,
      [x / h, x / (t * t), 10 * t, x * t],
      '$sure Atılma hızı x / t = ${tr(x)} / ${tr(t)} = $v0 m/s bulunur.',
      unit: 'm/s',
    );
  },
  exam: _ayt,
  lesson: _fizik,
);

// 8 · Dinamiğin temel yasası.
final _f08 = lmAile(
  'fm_newton',
  'Dinamiğin temel yasası: net kuvvet ve ivme',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final m = 2 + a; // 2 … 26 kg
      final kat = 1 + b % 5; // μ = 0,1 … 0,5
      final mu = kat / 10;
      final ivme = 0.5 * (1 + b ~/ 5 + 4 * k); // 0,5 … 8 m/s²
      final f = m * kat; // sürtünme kuvveti
      final kuvvet = f + m * ivme;
      return _s(
        'Yatay bir zeminde duran $m kg kütleli bir sandık, zemine paralel '
        '${tr(kuvvet)} N büyüklüğünde bir kuvvetle çekilerek harekete '
        'geçiriliyor. Sandık ile zemin arasındaki kinetik sürtünme katsayısı '
        '${tr(mu)} olduğuna göre sandığın ivmesi kaç m/s² olur? (g = 10 m/s² '
        'alınız.)',
        ivme,
        [kuvvet / m, (kuvvet - mu * m) / m, kuvvet - f, (kuvvet + f) / m],
        'Sürtünme kuvveti μ·m·g = ${tr(mu)} · $m · 10 = $f N olur. Net kuvvet '
        '${tr(kuvvet)} − $f = ${tr(kuvvet - f)} N, ivme ${tr(kuvvet - f)} / $m = '
        '${tr(ivme)} m/s² bulunur.',
        unit: 'm/s²',
      );
    }
    final m1 = 2 + a; // K: 2 … 26 kg
    final m2 = 1 + b; // L: 1 … 20 kg
    final ivme = 2 + k; // 2 … 4 m/s²
    final kuvvet = (m1 + m2) * ivme, ip = m1 * ivme;
    const giris =
        'Sürtünmesiz yatay bir düzlemde duran K ve L cisimleri birbirine hafif '
        'bir iple bağlıdır.';
    if (c % 3 == 1) {
      return _s(
        '$giris K cisminin kütlesi $m1 kg, L cisminin kütlesi $m2 kg olarak '
        'veriliyor. L cismi, ipi gergin tutan yönde yatay $kuvvet N '
        'büyüklüğünde bir kuvvetle çekildiğinde K ile L arasındaki ipte oluşan '
        'gerilme kuvveti kaç N olur?',
        ip,
        [m2 * ivme, kuvvet, kuvvet / 2, ivme, kuvvet - ivme],
        'Sistemin ivmesi $kuvvet / ($m1 + $m2) = $ivme m/s² olur. İp yalnız '
        'K cismini çektiğinden gerilme kuvveti $m1 · $ivme = $ip N bulunur.',
        unit: 'N',
      );
    }
    return _s(
      '$giris K cisminin kütlesi $m1 kg, L cisminin kütlesi $m2 kg olarak '
      'veriliyor. L cismi, ipi gergin tutan yönde yatay bir F kuvvetiyle '
      'çekildiğinde ipteki gerilme kuvveti $ip N oluyor. Buna göre F kuvvetinin '
      'büyüklüğü kaç N olur?',
      kuvvet,
      [ip, m2 * ivme, ip * (m1 + m2) / m2, 2 * ip, ip + m2],
      'İp yalnız K cismini çektiğinden ivme $ip / $m1 = $ivme m/s² olur. '
      'F kuvveti iki cismi birlikte ivmelendirir: F = ($m1 + $m2) · $ivme = '
      '$kuvvet N.',
      unit: 'N',
    );
  },
  exam: _ayt,
  lesson: _fizik,
);

// 9 · Eğik düzlemde ivme ve kuvvet.
const _egim = <(int, double, double)>[(30, 0.5, 0), (37, 0.6, 0.8), (53, 0.8, 0.6)];

String _trig(int i, {bool cos = false}) {
  final (aci, s, k) = _egim[i];
  return cos || i > 0
      ? 'sin $aci° = ${tr(s)}; cos $aci° = ${tr(k)}; g = 10 m/s² alınız.'
      : 'sin $aci° = ${tr(s)}; g = 10 m/s² alınız.';
}

final _f09 = lmAile(
  'fm_egik_duzlem',
  'Eğik düzlemde ivme ve kuvvet',
  Topic.physics,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 1) {
      final m = 2 + a; // 2 … 26 kg
      final i = 1 + b % 2; // 37° ya da 53°
      final (aci, sin, cos) = _egim[i];
      final mu = 0.05 * (1 + b ~/ 2); // 0,05 … 0,5
      final tepki = m * 10 * cos, paralel = m * 10 * sin;
      final f = mu * tepki;
      final giris =
          'Eğim açısı $aci° olan bir eğik düzlem üzerinde aşağı doğru kaymakta '
          'olan $m kg kütleli bir cisim ile düzlem arasındaki kinetik sürtünme '
          'katsayısı ${tr(mu)} olarak veriliyor.';
      final cozum =
          'Yüzeyin tepki kuvveti m·g·cos θ = $m · 10 · ${tr(cos)} = ${tr(tepki)} N, '
          'sürtünme kuvveti ${tr(mu)} · ${tr(tepki)} = ${tr(f)} N olur.';
      if (k == 0) {
        return _s(
          '$giris Cisme etki eden sürtünme kuvveti kaç N olur? (${_trig(i)})',
          f,
          [mu * m * 10, mu * paralel, tepki, mu * m * cos],
          cozum,
          unit: 'N',
        );
      }
      if (k == 1) {
        return _s(
          '$giris Cisme etki eden net kuvvet kaç N olur? (${_trig(i)})',
          paralel - f,
          [paralel, paralel + f, f, m * 10 - f],
          '$cozum Ağırlığın düzleme paralel bileşeni $m · 10 · ${tr(sin)} = '
          '${tr(paralel)} N olduğundan net kuvvet ${tr(paralel)} − ${tr(f)} = '
          '${tr(paralel - f)} N bulunur.',
          unit: 'N',
        );
      }
      return _s(
        '$giris Bu cismi düzlem boyunca yukarı doğru sabit hızla çekmek için '
        'düzleme paralel kaç N büyüklüğünde kuvvet uygulanmalıdır? (${_trig(i)})',
        paralel + f,
        [paralel, paralel - f, f, m * 10 + f],
        '$cozum Yukarı çekilirken sürtünme aşağı yönlüdür. Ağırlığın paralel '
        'bileşeni $m · 10 · ${tr(sin)} = ${tr(paralel)} N olduğundan gereken '
        'kuvvet ${tr(paralel)} + ${tr(f)} = ${tr(paralel + f)} N bulunur.',
        unit: 'N',
      );
    }
    final m = 5 * (a + 1); // 5 … 125 kg
    final i = b % 3;
    final (aci, sin, _) = _egim[i];
    final n = 1 + b ~/ 3 + 7 * k;
    final ivme = n / 5; // 0,2 … 5,6 m/s²
    final paralel = (m * 10 * sin).round();
    final kuvvet = paralel + (a + 1) * n;
    if (c % 3 == 0) {
      return _s(
        'Eğim açısı $aci° olan sürtünmesiz bir eğik düzlem üzerindeki $m kg '
        'kütleli bir sandık, düzleme paralel ve yukarı yönlü $kuvvet N '
        'büyüklüğünde bir kuvvetle çekiliyor. Sandığın düzlem boyunca yukarı '
        'yönlü ivmesi kaç m/s² olur? (${_trig(i)})',
        ivme,
        [kuvvet / m, (kuvvet - m * 10) / m, kuvvet - paralel, (kuvvet + paralel) / m, 10 * sin],
        'Ağırlığın düzleme paralel bileşeni m·g·sin θ = $m · 10 · ${tr(sin)} = '
        '$paralel N olur. Net kuvvet $kuvvet − $paralel = ${kuvvet - paralel} N, '
        'ivme ${kuvvet - paralel} / $m = ${tr(ivme)} m/s² bulunur.',
        unit: 'm/s²',
      );
    }
    return _s(
      'Eğim açısı $aci° olan sürtünmesiz bir eğik düzlem üzerindeki $m kg '
      'kütleli bir sandığın, düzlem boyunca yukarı doğru ${tr(ivme)} m/s² '
      'ivmeyle hızlanması isteniyor. Bunun için sandığa düzleme paralel ve '
      'yukarı yönlü kaç N büyüklüğünde kuvvet uygulanmalıdır? (${_trig(i)})',
      kuvvet,
      [m * ivme, m * (ivme + 10), paralel, paralel - m * ivme],
      'Ağırlığın düzleme paralel bileşeni $m · 10 · ${tr(sin)} = $paralel N olur. '
      'F − $paralel = m·a eşitliğinden F = $paralel + $m · ${tr(ivme)} = '
      '$kuvvet N bulunur.',
      unit: 'N',
    );
  },
  exam: _ayt,
  lesson: _fizik,
);

// 10 · İş, güç ve verim.
final _f10 = lmAile(
  'fm_is_guc',
  'İş, güç ve verim hesapları',
  Topic.physics,
  Difficulty.easy,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final kuvvet = 10 * (a + 2); // 20 … 260 N
      final x = 1.5 * (1 + b % 5 + 5 * k); // 1,5 … 30 m
      final t = const [4, 5, 10, 20][b ~/ 5];
      final w = kuvvet * x;
      return _s(
        'Bir elektrik motoru, yatay zemindeki bir sandığı halat yardımıyla '
        'zemine paralel $kuvvet N büyüklüğünde sabit bir kuvvetle ${tr(x)} m çekiyor. '
        'Bu çekme işi $t saniye sürdüğüne göre motorun sandık üzerinde yaptığı '
        'işin ortalama gücü kaç W olur?',
        w / t,
        [w, w * t, kuvvet * t / x, kuvvet / t],
        'Yapılan iş F·x = $kuvvet · ${tr(x)} = ${tr(w)} J olur. Güç, işin süreye '
        'oranıdır: ${tr(w)} / $t = ${tr(w / t)} W.',
        unit: 'W',
      );
    }
    final m = 10 * (a + 2); // 20 … 260 kg
    if (c % 3 == 1) {
      final h = 2 + b ~/ 5 + 4 * k; // 2 … 13 m
      final t = const [4, 5, 8, 10, 20][b % 5];
      final w = m * 10 * h;
      return _s(
        'Bir vinç, $m kg kütleli bir yükü sabit hızla $h m yükseğe $t saniyede '
        'çıkarıyor. Vincin yük üzerinde yaptığı işin gücü kaç W olur? '
        '(g = 10 m/s² alınız.)',
        w / t,
        [m * h / t, w, m * 10 / t, w * t],
        'Yapılan iş m·g·h = $m · 10 · $h = $w J olur. Güç $w / $t = '
        '${tr(w / t)} W bulunur.',
        unit: 'W',
      );
    }
    final h = 1 + b ~/ 5 + 4 * k; // 1 … 12 m
    final verim = const [20, 25, 40, 50, 80][b % 5];
    final yararli = m * 10 * h;
    final harcanan = yararli * 100 ~/ verim;
    return _s(
      'Bir elektrik motoru, $harcanan J elektrik enerjisi harcayarak $m kg '
      'kütleli bir yükü sabit hızla $h m yükseğe çıkarıyor. Bu motorun verimi '
      'yüzde kaçtır? (g = 10 m/s² alınız.)',
      verim,
      [100 - verim, verim / 10, verim / 2, 100 - verim / 2],
      'Yararlı iş m·g·h = $m · 10 · $h = $yararli J olur. Verim '
      '$yararli / $harcanan = ${tr(verim / 100)}, yani %$verim bulunur.',
      yuzde: true,
    );
  },
  exam: _tyt,
  lesson: _fizik,
);

// 11 · Kinetik ve potansiyel enerji, mekanik enerjinin korunumu.
final _f11 = lmAile(
  'fm_enerji',
  'Mekanik enerji ve enerjinin korunumu',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final m = 1 + a; // 1 … 25 kg
      final h = 2 + b; // 2 … 21 m
      final v = const [2, 4, 6, 10][k];
      final pe = m * 10 * h, ke = m * v * v / 2;
      return _s(
        'Kütlesi $m kg olan bir insansız hava aracı, yerden $h m yükseklikte '
        '$v m/s hızla yatay doğrultuda uçuyor. Yer düzeyi potansiyel enerjinin '
        'sıfır alındığı düzey olduğuna göre aracın mekanik enerjisi kaç J olur? '
        '(g = 10 m/s² alınız.)',
        pe + ke,
        [pe, pe + 2 * ke, ke, m * h + ke],
        'Potansiyel enerji m·g·h = $m · 10 · $h = $pe J, kinetik enerji '
        '½·m·v² = ½ · $m · $v² = ${tr(ke)} J olur. Mekanik enerji $pe + ${tr(ke)} = '
        '${tr(pe + ke)} J bulunur.',
        unit: 'J',
      );
    }
    if (c % 3 == 1) {
      final alt = 1 + a; // 1 … 25 m
      final n = b + 1;
      final fark = n * n / 5; // 0,2 … 80 m
      final ust = alt + fark;
      final v = 2 * n; // 2 … 40 m/s
      const pist = 'Sürtünmesiz bir kayak pistinin yerden';
      if (k == 0) {
        return _s(
          '$pist ${tr(ust)} m yükseklikteki noktasından durgun hâlden kaymaya '
          'başlayan bir kayakçı, pistin yerden $alt m yükseklikteki noktasından '
          'kaç m/s hızla geçer? (g = 10 m/s² alınız.)',
          v,
          [math.sqrt(20 * ust), math.sqrt(10 * fark), 2 * v, v / 2],
          'Kayakçı ${tr(ust)} − $alt = ${tr(fark)} m alçalır. Mekanik enerji '
          'korunduğundan v² = 2·g·h = 2 · 10 · ${tr(fark)} = ${4 * n * n}, '
          'v = $v m/s olur.',
          unit: 'm/s',
        );
      }
      if (k == 1) {
        final m = 40 + 5 * ((a + b) % 9); // 40 … 80 kg
        final ke = 2 * m * n * n;
        return _s(
          '$pist ${tr(ust)} m yükseklikteki noktasından durgun hâlden kaymaya '
          'başlayan $m kg kütleli bir kayakçının, pistin yerden $alt m '
          'yükseklikteki noktasından geçerken kinetik enerjisi kaç J olur? '
          '(g = 10 m/s² alınız.)',
          ke,
          [m * 10 * ust, m * 10 * alt, m * fark, ke / 2],
          'Kayakçı ${tr(ust)} − $alt = ${tr(fark)} m alçalır. Kaybedilen '
          'potansiyel enerji kinetik enerjiye dönüşür: $m · 10 · ${tr(fark)} = '
          '$ke J.',
          unit: 'J',
        );
      }
      return _s(
        'Sürtünmesiz bir kayak pistinde durgun hâlden kaymaya başlayan bir '
        'kayakçı, pistin yerden $alt m yükseklikteki noktasından $v m/s hızla '
        'geçiyor. Kayakçı yerden kaç metre yükseklikten kaymaya başlamıştır? '
        '(g = 10 m/s² alınız.)',
        ust,
        [fark, alt + 2 * fark, alt + fark / 2, alt + v],
        'Mekanik enerji korunduğundan alçalma miktarı v² / (2·g) = $v² / 20 = '
        '${tr(fark)} m olur. Başlangıç yüksekliği $alt + ${tr(fark)} = '
        '${tr(ust)} m bulunur.',
        unit: 'm',
      );
    }
    final m = 20 + 2 * a; // 20 … 68 kg
    final h = 2 + b / 2; // 2 … 11,5 m
    final v = 2 * (k + 1); // 2, 4, 6 m/s
    final pe = (m * 10 * h).round(), ke = m * v * v ~/ 2;
    return _s(
      'Kütlesi $m kg olan bir çocuk, yerden ${tr(h)} m yükseklikteki bir su '
      'kaydırağının tepesinden durgun hâlden kaymaya başlıyor ve kaydırağın '
      'yer düzeyindeki ucuna $v m/s hızla ulaşıyor. Kayma sırasında sürtünme '
      'nedeniyle ısıya dönüşen enerji kaç J olur? (g = 10 m/s² alınız.)',
      pe - ke,
      [pe, ke, pe + ke, pe - 2 * ke],
      'Başlangıçtaki potansiyel enerji $m · 10 · ${tr(h)} = $pe J, tabandaki '
      'kinetik enerji ½ · $m · $v² = $ke J olur. Isıya dönüşen enerji '
      '$pe − $ke = ${pe - ke} J bulunur.',
      unit: 'J',
    );
  },
  exam: _tyt,
  lesson: _fizik,
);

// 12 · Hooke yasası ve esneklik potansiyel enerjisi.
final _f12 = lmAile(
  'fm_yay',
  'Hooke yasası ve esneklik potansiyel enerjisi',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final boy = 20 + 2 * a; // 20 … 68 cm
      final yay = const [100, 200, 250, 400, 500][b % 5]; // N/m
      final j = 1 + b ~/ 5 + 4 * k;
      final m = j / 5; // 0,2 … 3,2 kg
      final uzama = 200 * j / yay; // cm
      return _s(
        'Serbest boyu $boy cm, yay sabiti $yay N/m olan bir yay tavana asılıyor '
        've alt ucuna ${tr(m)} kg kütleli bir cisim bağlanıyor. Cisim dengeye '
        'geldiğinde yayın boyu kaç cm olur? (g = 10 m/s² alınız.)',
        boy + uzama,
        [uzama, boy + uzama / 10, boy - uzama, boy + 2 * uzama, boy + uzama / 100],
        'Dengede k·x = m·g olduğundan x = ${tr(m)} · 10 / $yay = '
        '${tr(uzama / 100, 4)} m = ${tr(uzama)} cm olur. Yayın boyu $boy + '
        '${tr(uzama)} = ${tr(boy + uzama)} cm bulunur.',
        unit: 'cm',
      );
    }
    if (c % 3 == 1) {
      final yay = 200 * (a + 1); // 200 … 5000 N/m
      final x1 = 1 + b % 5; // 1 … 5 cm
      final x2 = x1 + 1 + b ~/ 5 + 4 * k; // 2 … 17 cm
      final e1 = (a + 1) * x1 * x1 / 100, e2 = (a + 1) * x2 * x2 / 100;
      return _s(
        'Yay sabiti $yay N/m olan bir yay, serbest boyuna göre $x1 cm gerilmiş '
        'durumdadır. Yayın uzamasını $x2 cm değerine çıkarmak için yaya karşı '
        'yapılması gereken iş kaç J olur?',
        e2 - e1,
        [
          (a + 1) * (x2 - x1) * (x2 - x1) / 100,
          2 * (e2 - e1),
          e2,
          (e2 - e1) * 100,
        ],
        'Yayda depolanan enerji ½·k·x² olduğundan başlangıçta ½ · $yay · '
        '${tr(x1 / 100)}² = ${tr(e1)} J, sonda ½ · $yay · ${tr(x2 / 100)}² = '
        '${tr(e2)} J enerji vardır. Yapılan iş ${tr(e2)} − ${tr(e1)} = '
        '${tr(e2 - e1)} J olur.',
        unit: 'J',
      );
    }
    final m = (a + 1) / 5; // 0,2 … 5 kg
    final w = const [5, 10, 20][k]; // √(k/m)
    final yay = (a + 1) * w * w ~/ 5; // 5 … 2000 N/m
    final x = b + 1; // 1 … 20 cm
    final v = w * x / 100; // 0,05 … 4 m/s
    return _s(
      'Sürtünmesiz yatay bir düzlemde, yay sabiti $yay N/m olan bir yay $x cm '
      'sıkıştırılıp önüne ${tr(m)} kg kütleli bir cisim konuluyor. Yay serbest '
      'bırakıldığında cisim yaydan kaç m/s hızla ayrılır?',
      v,
      [w * w * x / 100, w * x / 10, v * math.sqrt2, v / 2],
      'Yayın enerjisi kinetik enerjiye dönüşür: ½·k·x² = ½·m·v². Buradan '
      'v² = k·x² / m = $yay · ${tr(x / 100)}² / ${tr(m)} = ${tr(v * v, 4)}, '
      'v = ${tr(v)} m/s olur.',
      unit: 'm/s',
    );
  },
  exam: _ayt,
  lesson: _fizik,
);

// 13 · İtme ve momentum, esnek olmayan çarpışma.
const _oran = [0.5, 1.0, 1.5, 2.0, 3.0];

final _f13 = lmAile(
  'fm_momentum',
  'İtme, momentum ve kenetlenen cisimlerin ortak hızı',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.analiz,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final m = (a + 1) / 10; // 0,1 … 2,5 kg
      final v1 = 6 + 2 * (b % 5); // 6 … 14 m/s
      final v2 = v1 - 1 - b ~/ 5; // en az 2 m/s
      final sure = const [0.01, 0.02, 0.05, 0.1][k];
      final dp = (a + 1) * (v1 + v2) / 10; // kg·m/s
      final kuvvet = (a + 1) * (v1 + v2) * const [10, 5, 2, 1][k];
      return _s(
        'Kütlesi ${tr(m)} kg olan bir top, düşey bir duvara dik doğrultuda '
        '$v1 m/s hızla çarpıp aynı doğrultuda $v2 m/s hızla geri dönüyor. Topun '
        'duvarla teması ${tr(sure)} saniye sürdüğüne göre duvarın topa '
        'uyguladığı ortalama kuvvetin büyüklüğü kaç N olur?',
        kuvvet,
        [m * (v1 - v2) / sure, m * v1 / sure, dp, m * v2 / sure],
        'Hız yön değiştirdiğinden momentum değişiminin büyüklüğü m·(v₁ + v₂) = '
        '${tr(m)} · ($v1 + $v2) = ${tr(dp)} kg·m/s olur. F·Δt = Δp eşitliğinden '
        'F = ${tr(dp)} / ${tr(sure)} = $kuvvet N bulunur.',
        unit: 'N',
      );
    }
    final m1 = 2 * (a + 1); // 2 … 50 kg
    final oran = _oran[b % 5];
    final m2 = (m1 * oran).round(); // 1 … 150 kg
    if (c % 3 == 1) {
      final ortak = (1 + b ~/ 5 + 4 * k) / 5; // 0,2 … 2,4 m/s
      final v1 = (1 + oran) * ortak; // 0,3 … 9,6 m/s
      return _s(
        'Sürtünmesiz yatay bir rayda ${tr(v1)} m/s hızla ilerleyen $m1 kg '
        'kütleli bir yük arabası, önünde durmakta olan $m2 kg kütleli başka bir '
        'arabaya çarpıp ona kenetleniyor. Kenetlenen arabaların çarpışmadan '
        'hemen sonraki ortak hızı kaç m/s olur?',
        ortak,
        [v1 / 2, v1 * m1 / m2, v1 * m2 / (m1 + m2), v1],
        'Çarpışmada momentum korunur: $m1 · ${tr(v1)} = ($m1 + $m2) · v. Buradan '
        'v = ${tr(m1 * v1)} / ${m1 + m2} = ${tr(ortak)} m/s olur.',
        unit: 'm/s',
      );
    }
    final v2 = (1 + b ~/ 5) / 2; // 0,5 … 2 m/s
    final ortak = 2 * (k + 1) / 5; // 0,4 … 1,2 m/s
    final v1 = (1 + oran) * ortak + oran * v2; // 0,85 … 10,8 m/s
    final p1 = m1 * v1, p2 = m2 * v2;
    return _s(
      'Sürtünmesiz yatay bir rayda $m1 kg kütleli K arabası ${tr(v1)} m/s, '
      '$m2 kg kütleli L arabası ${tr(v2)} m/s hızla birbirine doğru ilerliyor. '
      'Arabalar çarpışıp kenetlendiğine göre çarpışmadan hemen sonraki ortak '
      'hızlarının büyüklüğü kaç m/s olur?',
      ortak,
      [(p1 + p2) / (m1 + m2), (v1 - v2) / 2, v1 - v2, (v1 + v2) / 2],
      'K arabasının hareket yönü pozitif alınırsa toplam momentum $m1 · '
      '${tr(v1)} − $m2 · ${tr(v2)} = ${tr(p1 - p2)} kg·m/s olur. Ortak hız '
      '${tr(p1 - p2)} / ($m1 + $m2) = ${tr(ortak)} m/s bulunur.',
      unit: 'm/s',
    );
  },
  exam: _ayt,
  lesson: _fizik,
);

// 14 · Tork ve denge.
final _f14 = lmAile(
  'fm_tork',
  'Tork ve dönme dengesi',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final (p, q) = const [(2, 3), (3, 4), (4, 5), (3, 5), (2, 5)][b % 5];
      final u = 5 * (a + 1);
      final w1 = q * u, w2 = p * u; // 10 … 625 N
      final w = 2 * (1 + b ~/ 5 + 4 * k); // 2 … 32 cm
      final d1 = p * w, d2 = q * w;
      return _s(
        'Ağırlığı önemsiz bir çubuk, bir destek üzerinde yatay durmaktadır. '
        'Desteğin bir yanına, destekten $d1 cm uzağa $w1 N ağırlığında bir yük '
        'asılıyor. Çubuğun yatay dengede kalması için $w2 N ağırlığındaki '
        'ikinci yük, desteğin diğer yanında destekten kaç cm uzağa asılmalıdır?',
        d2,
        [d1 * w2 / w1, d1, d1 + d2, 2 * d1],
        'Desteğe göre torklar eşit olmalıdır: $w1 · $d1 = $w2 · d. Buradan '
        'd = ${w1 * d1} / $w2 = $d2 cm bulunur.',
        unit: 'cm',
      );
    }
    if (c % 3 == 1) {
      final agirlik = 10 * (a + 1); // 10 … 250 N
      final s = const [0.5, 1.5, 2.0, 3.0, 4.0][b % 5];
      final d = 5 * (1 + b ~/ 5 + 4 * k); // 5 … 60 cm
      final boy = (2 * d * (1 + s)).round(); // 15 … 600 cm
      final kol = d * s; // ağırlık merkezinin desteğe uzaklığı (cm)
      final yuk = agirlik * s;
      return _s(
        'Uzunluğu $boy cm, ağırlığı $agirlik N olan türdeş bir çubuk, bir '
        'ucundan $d cm uzaktaki bir desteğe oturtuluyor. Çubuğun yatay dengede '
        'kalması için desteğe yakın olan ucuna kaç N ağırlığında bir yük '
        'asılmalıdır?',
        yuk,
        [agirlik * (boy - d) / d, agirlik / s, agirlik * boy / (2 * d), agirlik],
        'Türdeş çubuğun ağırlık merkezi ortasındadır ve desteğe uzaklığı '
        '$boy / 2 − $d = ${tr(kol)} cm olur. Tork dengesinden P · $d = $agirlik · ${tr(kol)}, '
        'P = ${tr(yuk)} N bulunur.',
        unit: 'N',
      );
    }
    final f1 = 30 + 2 * a; // 30 … 78 N
    final j1 = 3 + b % 5, j2 = 1 + b ~/ 5;
    final d1 = j1 / 5; // 0,6 … 1,4 m
    final d2 = j2 / 10; // 0,1 … 0,4 m
    final f2 = 10 * (k + 1); // 10 … 30 N
    final t1 = f1 * j1 / 5, t2 = f2 * j2 / 10;
    return _s(
      'Sürtünmesiz yatay bir masanın üzerindeki bir çubuk, bir ucundaki '
      'O noktası etrafında masa düzleminde serbestçe dönebilmektedir. Çubuğa '
      'masa düzleminde ve çubuğa dik iki kuvvet uygulanıyor: O noktasından '
      '${tr(d1)} m uzağa uygulanan $f1 N büyüklüğündeki kuvvet çubuğu saat '
      'yönünde, O noktasından ${tr(d2)} m uzağa uygulanan $f2 N büyüklüğündeki '
      'kuvvet ise saat yönünün tersine döndürmeye çalışıyor. Bu iki kuvvetin '
      'O noktasına göre oluşturduğu net torkun büyüklüğü kaç N·m olur?',
      t1 - t2,
      [t1 + t2, t1, (f1 - f2) * (d1 - d2), (f1 - f2) * d1],
      'Torklar F·d ile bulunur: $f1 · ${tr(d1)} = ${tr(t1)} N·m ve $f2 · '
      '${tr(d2)} = ${tr(t2)} N·m. Zıt yönlü oldukları için net tork '
      '${tr(t1)} − ${tr(t2)} = ${tr(t1 - t2)} N·m olur.',
      unit: 'N·m',
    );
  },
  exam: _ayt,
  lesson: _fizik,
);

// 15 · Basit makineler: palanga, eğik düzlem, çıkrık.
final _f15 = lmAile(
  'fm_basit_makine',
  'Basit makinelerde kuvvet ve verim',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final n = 2 + b % 5; // 2 … 6 ip kolu
      final makara = 10 * (1 + b ~/ 5); // 10 … 40 N
      final kuvvet = 5 * (a + 10 + 25 * k); // 50 … 545 N
      final yuk = n * kuvvet - makara;
      return _s(
        'Bir palangada yük ile hareketli makara grubunu $n ip kolu '
        'taşımaktadır. Hareketli makara grubunun ağırlığı $makara N, yükün '
        'ağırlığı $yuk N olduğuna göre yükü sabit hızla yükseltmek için ipin '
        'serbest ucuna kaç N büyüklüğünde kuvvet uygulanmalıdır? (Sürtünmeler '
        've ip ağırlığı önemsizdir.)',
        kuvvet,
        [yuk / n, (yuk - makara) / n, yuk + makara, (yuk + makara) / (n - 1), (yuk + makara) / 2],
        'İp kollarının her birindeki gerilme F kadardır ve $n kol toplam '
        '$yuk + $makara = ${yuk + makara} N ağırlığı taşır. F = ${yuk + makara} / '
        '$n = $kuvvet N olur.',
        unit: 'N',
      );
    }
    if (c % 3 == 1) {
      final kuvvet = 40 * (a + 1); // 40 … 1000 N
      final r = const [2.5, 4.0, 5.0, 8.0][b % 4]; // boy / yükseklik
      final verim = const [50, 60, 75, 80, 90][b ~/ 4];
      final h = k + 2; // 2 … 4 m
      final boy = r * h; // 5 … 32 m
      final yuk = (kuvvet * r * verim / 100).round();
      final yararli = yuk * h, harcanan = kuvvet * boy;
      return _s(
        'Ağırlığı $yuk N olan bir sandık, uzunluğu ${tr(boy)} m ve yüksekliği '
        '$h m olan bir eğik düzlemin tabanından tepesine, düzleme paralel '
        '$kuvvet N büyüklüğünde bir kuvvetle sabit hızla çekiliyor. Bu eğik '
        'düzlemin verimi yüzde kaçtır?',
        verim,
        [100 - verim, 100 / r, verim / r, verim / 2],
        'Yararlı iş G·h = $yuk · $h = $yararli J, harcanan iş F·L = $kuvvet · '
        '${tr(boy)} = ${tr(harcanan)} J olur. Verim $yararli / ${tr(harcanan)} = '
        '${tr(verim / 100)}, yani %$verim bulunur.',
        yuzde: true,
      );
    }
    final n = 2 + b % 5; // kol / yarıçap oranı
    final yuk = 60 * (a + 1); // 60 … 1500 N
    final r = 5 + b ~/ 5 + 4 * k; // 5 … 16 cm
    final kol = n * r;
    return _s(
      'Bir kuyu çıkrığında silindirin yarıçapı $r cm, çevirme kolunun uzunluğu '
      '$kol cm olarak ölçülüyor. Silindire sarılı ipin ucuna bağlı $yuk N '
      'ağırlığındaki yükü sabit hızla yukarı çekmek için kolun ucuna, '
      'kola dik doğrultuda kaç N büyüklüğünde kuvvet uygulanmalıdır? '
      '(Sürtünmeler önemsizdir.)',
      yuk ~/ n,
      [yuk * n, yuk * r / (kol + r), yuk / (n - 1), yuk / 2, yuk - kol],
      'Çıkrıkta F · R = G · r eşitliği geçerlidir: F · $kol = $yuk · $r. Buradan '
      'F = ${yuk * r} / $kol = ${yuk ~/ n} N olur.',
      unit: 'N',
    );
  },
  exam: _ayt,
  lesson: _fizik,
);

// 16 · Özkütle ve karışımların özkütlesi.
const _karisim = [(1, 1), (1, 2), (2, 1), (1, 3), (3, 1)];

final _f16 = lmAile(
  'fm_ozkutle',
  'Özkütle ve karışımların özkütlesi',
  Topic.physics,
  Difficulty.easy,
  BloomLevel.anlama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final x = 2 + a % 5, y = 7 + a ~/ 5; // 2 … 6 ve 7 … 11 cm
      final z = const [2, 4, 5, 10][k];
      final d = (3 + 5 * b) / 10; // 0,3 … 9,8 g/cm³
      final hacim = x * y * z;
      final m = d * hacim;
      return _s(
        'Ayrıt uzunlukları $x cm, $y cm ve $z cm olan dikdörtgenler prizması '
        'biçimindeki türdeş bir cismin kütlesi ${tr(m)} g olarak ölçülüyor. Bu '
        'cismin yapıldığı maddenin özkütlesi kaç g/cm³ olur?',
        d,
        [hacim / m, m / (x * y), m / (x + y + z), m / (y * z)],
        'Cismin hacmi $x · $y · $z = $hacim cm³ olur. Özkütle kütlenin hacme '
        'oranıdır: ${tr(m)} / $hacim = ${tr(d)} g/cm³.',
      );
    }
    final (p, q) = _karisim[b % 5];
    final d100 = 90 + 5 * (b ~/ 5 + 4 * k); // karışım: 0,9 … 1,45 g/cm³
    final d1 = (d100 + 10 * q) / 100, d2 = (d100 - 10 * p) / 100, dk = d100 / 100;
    final v1 = p * 10 * (a + 1), v2 = q * 10 * (a + 1); // cm³
    final m1 = (d100 + 10 * q) * p * (a + 1) / 10; // g
    final m2 = (d100 - 10 * p) * q * (a + 1) / 10;
    const kosul =
        'Karışımın hacmi sıvıların hacimleri toplamına eşit olduğuna göre '
        'karışımın özkütlesi kaç g/cm³ olur?';
    if (c % 3 == 1) {
      return _s(
        'Birbiriyle karışabilen iki sıvıdan, özkütlesi ${tr(d1)} g/cm³ olan '
        'K sıvısından $v1 cm³ ve özkütlesi ${tr(d2)} g/cm³ olan L sıvısından '
        '$v2 cm³ alınarak türdeş bir karışım hazırlanıyor. $kosul',
        dk,
        [
          (d1 + d2) / 2,
          (d1 * v2 + d2 * v1) / (v1 + v2),
          2 * d1 * d2 / (d1 + d2),
          d1 + d2,
          d1,
          d2,
        ],
        'K sıvısının kütlesi ${tr(d1)} · $v1 = ${tr(m1)} g, L sıvısının kütlesi '
        '${tr(d2)} · $v2 = ${tr(m2)} g olur. Karışımın özkütlesi (${tr(m1)} + ${tr(m2)}) / '
        '($v1 + $v2) = ${tr(m1 + m2)} / ${v1 + v2} = ${tr(dk)} g/cm³ bulunur.',
      );
    }
    return _s(
      'Birbiriyle karışabilen iki sıvıdan, özkütlesi ${tr(d1)} g/cm³ olan '
      'K sıvısından ${tr(m1)} g ve özkütlesi ${tr(d2)} g/cm³ olan L sıvısından ${tr(m2)} g '
      'alınarak türdeş bir karışım hazırlanıyor. $kosul',
      dk,
      [
        (d1 + d2) / 2,
        (m1 * d1 + m2 * d2) / (m1 + m2),
        d1 + d2,
        d1,
        d2,
        (m1 + m2) / (m1 * d1 + m2 * d2),
      ],
      'K sıvısının hacmi ${tr(m1)} / ${tr(d1)} = $v1 cm³, L sıvısının hacmi ${tr(m2)} / '
      '${tr(d2)} = $v2 cm³ olur. Karışımın özkütlesi (${tr(m1)} + ${tr(m2)}) / ($v1 + $v2) = '
      '${tr(m1 + m2)} / ${v1 + v2} = ${tr(dk)} g/cm³ bulunur.',
    );
  },
  exam: _tyt,
  lesson: _fizik,
);

// 17 · Katı ve sıvı basıncı, basınç kuvveti.
final _f17 = lmAile(
  'fm_basinc',
  'Katı ve sıvı basıncı, basınç kuvveti',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final n1 = 2 + a % 5, n2 = 7 + a ~/ 5; // 20 … 60 cm ve 70 … 110 cm
      final alan = n1 * n2 / 100; // 0,14 … 0,66 m²
      final basinc = 100 * (b + 1 + 20 * k); // 100 … 8000 Pa
      final agirlik = (b + 1 + 20 * k) * n1 * n2; // 14 … 5280 N
      return _s(
        'Ağırlığı $agirlik N olan dikdörtgenler prizması biçimindeki bir '
        'sandık, ayrıt uzunlukları ${10 * n1} cm ve ${10 * n2} cm olan yüzü '
        'üzerine yatay zemine konuluyor. Sandığın zemine uyguladığı basınç kaç '
        'Pa olur?',
        basinc,
        [basinc / 10000, basinc / 100, agirlik * alan, agirlik / ((n1 + n2) / 10)],
        'Temas yüzeyinin alanı ${tr(n1 / 10)} m · ${tr(n2 / 10)} m = ${tr(alan)} m² '
        'olur. Basınç ağırlığın alana oranıdır: $agirlik / ${tr(alan)} = '
        '$basinc Pa.',
        unit: 'Pa',
      );
    }
    if (c % 3 == 1) {
      final d = 700 + 50 * b; // 700 … 1650 kg/m³
      final h = (a + 1) / 10; // 0,1 … 2,5 m
      final alan = const [0.01, 0.02, 0.05][k]; // m²
      final basinc = d * (a + 1); // h·d·g
      final kuvvet = basinc * alan;
      return _s(
        'Taban alanı ${tr(alan)} m² olan düşey silindirik bir kapta, özkütlesi '
        '$d kg/m³ olan bir sıvı ${tr(h)} m yüksekliğe kadar doludur. Sıvının '
        'kap tabanına uyguladığı basınç kuvveti kaç N olur? (g = 10 m/s² '
        'alınız.)',
        kuvvet,
        [basinc, kuvvet / 10, d * 10 * alan, basinc / 10],
        'Tabandaki sıvı basıncı h·d·g = ${tr(h)} · $d · 10 = $basinc Pa olur. '
        'Basınç kuvveti P·A = $basinc · ${tr(alan)} = ${tr(kuvvet)} N bulunur.',
        unit: 'N',
      );
    }
    final h1 = 5 * (a + 1); // üst sıvı: 5 … 125 cm
    final d1 = const [600, 700, 800, 900][b % 4];
    final h2 = 10 * (1 + b ~/ 4); // alt sıvı: 10 … 50 cm
    final d2 = const [1000, 1200, 1500][k];
    final p1 = h1 * d1 ~/ 10, p2 = h2 * d2 ~/ 10;
    return _s(
      'Düşey bir kapta birbirine karışmayan iki sıvı bulunmaktadır. Altta, '
      'özkütlesi $d2 kg/m³ olan sıvı $h2 cm; üstte, özkütlesi $d1 kg/m³ olan '
      'sıvı $h1 cm yüksekliğindedir. Yalnız sıvıların kap tabanında '
      'oluşturduğu toplam basınç kaç Pa olur? (g = 10 m/s² alınız.)',
      p1 + p2,
      [p2, (h1 + h2) * d2 / 10, (h1 + h2) * (d1 + d2) / 10, p1, (p1 + p2) / 10],
      'Üstteki sıvının basıncı ${tr(h1 / 100)} · $d1 · 10 = $p1 Pa, alttaki '
      'sıvının basıncı ${tr(h2 / 100)} · $d2 · 10 = $p2 Pa olur. Tabandaki '
      'toplam sıvı basıncı $p1 + $p2 = ${p1 + p2} Pa bulunur.',
      unit: 'Pa',
    );
  },
  exam: _tyt,
  lesson: _fizik,
);

// 18 · Kaldırma kuvveti, yüzme ve batma.
final _f18 = lmAile(
  'fm_kaldirma',
  'Kaldırma kuvveti, yüzme ve batma',
  Topic.physics,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final hacim = 100 * (a + 1); // 100 … 2500 cm³
      final dc = 2 + b / 2; // 2 … 11,5 g/cm³
      final ds = const [0.8, 1.0, 1.2, 1.5][k];
      final m = (a + 1) * dc / 10; // 0,2 … 28,75 kg
      final agirlik = (a + 1) * dc, fk = (a + 1) * ds;
      return _s(
        'Kütlesi ${tr(m)} kg, hacmi $hacim cm³ olan bir metal parçası bir ipe '
        'bağlanarak özkütlesi ${tr(ds)} g/cm³ olan bir sıvının içine tamamen '
        'daldırılıyor. Metal parçası kabın tabanına değmeden dengede kaldığına '
        'göre ipteki gerilme kuvveti kaç N olur? (g = 10 m/s² alınız.)',
        agirlik - fk,
        [fk, agirlik, agirlik + fk, agirlik - fk / 10],
        'Metal parçasının ağırlığı ${tr(m)} · 10 = ${tr(agirlik)} N olur. Yerini '
        'değiştirdiği $hacim cm³ sıvının kütlesi $hacim · ${tr(ds)} = '
        '${tr(hacim * ds)} g olduğundan kaldırma kuvveti ${tr(fk)} N bulunur. '
        'İp gerilmesi ${tr(agirlik)} − ${tr(fk)} = ${tr(agirlik - fk)} N olur.',
        unit: 'N',
      );
    }
    if (c % 3 == 1) {
      final oran = const [0.25, 0.4, 0.5, 0.6, 0.75][b % 5];
      final ds = const [0.8, 1.0, 1.2][k];
      final dc = oran * ds; // 0,2 … 0,9 g/cm³
      final hacim = 20 * (a + 1) + 500 * (b ~/ 5); // 20 … 2000 cm³
      final batan = hacim * oran, disari = hacim - batan;
      final ust = (b ~/ 5).isOdd;
      return _s(
        'Hacmi $hacim cm³, özkütlesi ${tr(dc)} g/cm³ olan türdeş bir tahta '
        'takoz, özkütlesi ${tr(ds)} g/cm³ olan bir sıvıda yüzmektedir. Takozun '
        'sıvı ${ust ? 'yüzeyinin üzerinde kalan' : 'içinde kalan'} bölümünün '
        'hacmi kaç cm³ olur?',
        ust ? disari : batan,
        [ust ? batan : disari, hacim * dc, hacim * (1 - dc), hacim / 2],
        'Yüzen cisimde batan hacmin toplam hacme oranı özkütlelerin oranına '
        'eşittir: ${tr(dc)} / ${tr(ds)} = ${tr(oran)}. Batan hacim $hacim · '
        '${tr(oran)} = ${tr(batan)} cm³'
        '${ust ? ', sıvı yüzeyinin üzerinde kalan hacim $hacim − ${tr(batan)} = ${tr(disari)} cm³ olur.' : ' olur.'}',
        unit: 'cm³',
      );
    }
    final hacim = 100 * (a + 1); // 100 … 2500 cm³
    final dc = (25 + 10 * b) / 100; // 0,25 … 2,15 g/cm³
    final ds = const [0.8, 1.0, 1.2][k];
    final m = (a + 1) * (25 + 10 * b); // 25 … 5375 g
    final agirlik = m / 100; // N
    final tamBatik = (a + 1) * ds; // tamamen batmış cisme etki eden kuvvet
    final yuzer = dc < ds;
    return _s(
      'Kütlesi $m g, hacmi $hacim cm³ olan içi dolu türdeş bir cisim, '
      'özkütlesi ${tr(ds)} g/cm³ olan sıvıyla dolu derin bir kaba serbest '
      'bırakılıyor. Cisim dengeye geldiğinde ona etki eden kaldırma kuvveti '
      'kaç N olur? (g = 10 m/s² alınız.)',
      yuzer ? agirlik : tamBatik,
      [
        yuzer ? tamBatik : agirlik,
        (agirlik - tamBatik).abs(),
        agirlik + tamBatik,
        (yuzer ? agirlik : tamBatik) * 10,
      ],
      'Cismin özkütlesi $m / $hacim = ${tr(dc)} g/cm³ olur. Bu değer sıvının '
      'özkütlesinden ${yuzer ? 'küçük olduğundan cisim yüzer ve kaldırma kuvveti ağırlığına eşit olur: ${tr(m / 1000, 3)} · 10 = ${tr(agirlik)} N.' : 'büyük olduğundan cisim dibe batar. Yerini değiştirdiği $hacim cm³ sıvının kütlesi ${tr(hacim * ds)} g olduğundan kaldırma kuvveti ${tr(tamBatik)} N olur.'}',
      unit: 'N',
    );
  },
  exam: _tyt,
  lesson: _fizik,
);

// 19 · Isı, öz ısı ve ısıl denge.
final _f19 = lmAile(
  'fm_isi',
  'Isı, öz ısı ve ısıl denge',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final m = 100 * (a + 1); // 100 … 2500 g
      final c100 = const [40, 90, 210, 420][k]; // öz ısı · 100
      final t1 = 10 + 5 * (b % 4); // 10 … 25 °C
      final fark = 5 * (1 + b ~/ 4); // 5 … 25 °C
      final t2 = t1 + fark;
      final q = (a + 1) * c100 * fark;
      final oz = c100 / 100;
      return _s(
        'Kütlesi $m g, öz ısısı ${tr(oz)} J/(g·°C) olan bir maddenin sıcaklığını '
        '$t1 °C değerinden $t2 °C değerine çıkarmak için maddeye kaç J ısı '
        'verilmelidir? (Madde hâl değiştirmemektedir.)',
        q,
        [m * oz * t2, m * oz * t1, m * fark, m * oz * (t1 + t2)],
        'Sıcaklık artışı $t2 − $t1 = $fark °C olur. Q = m·c·ΔT bağıntısından '
        'Q = $m · ${tr(oz)} · $fark = $q J bulunur.',
        unit: 'J',
      );
    }
    if (c % 3 == 1) {
      final (p, q) = _karisim[b % 5];
      final u = 20 * (a + 1);
      final m1 = p * u, m2 = q * u; // 20 … 1500 g
      final denge = 30 + 5 * (b ~/ 5); // 30 … 45 °C
      final adim = 2 * (k + 1);
      final t1 = denge - q * adim, t2 = denge + p * adim; // 12 … 63 °C
      return _s(
        'Isıca yalıtılmış bir kapta, sıcaklığı $t1 °C olan $m1 g su ile '
        'sıcaklığı $t2 °C olan $m2 g su karıştırılıyor. Isı alışverişi yalnız '
        'sular arasında gerçekleştiğine göre ısıl denge sağlandığında karışımın '
        'sıcaklığı kaç °C olur?',
        denge,
        [(t1 + t2) / 2, (m1 * t2 + m2 * t1) / (m1 + m2), t2 - t1, denge + adim, t1 + t2],
        'Alınan ısı verilen ısıya eşittir: $m1 · (T − $t1) = $m2 · ($t2 − T). '
        'Buradan T = ($m1 · $t1 + $m2 · $t2) / ($m1 + $m2) = '
        '${m1 * t1 + m2 * t2} / ${m1 + m2} = $denge °C olur.',
        unit: '°C',
      );
    }
    final m = 50 * (a + 1); // 50 … 1250 g
    final fark = 2 * (b + 1); // 2 … 40 °C
    final c10 = const [4, 9, 24][k]; // öz ısı · 10
    final oz = c10 / 10;
    final q = 10 * (a + 1) * (b + 1) * c10;
    return _s(
      'Kütlesi $m g olan bir maddeye $q J ısı verildiğinde maddenin sıcaklığı '
      'hâl değiştirmeden $fark °C artıyor. Bu maddenin öz ısısı kaç J/(g·°C) '
      'olur?',
      oz,
      [q / m, q / fark, m * fark / q, oz * 10],
      'Q = m·c·ΔT bağıntısından c = Q / (m·ΔT) = $q / ($m · $fark) = '
      '$q / ${m * fark} = ${tr(oz)} J/(g·°C) bulunur.',
    );
  },
  exam: _tyt,
  lesson: _fizik,
);

// 20 · Hâl değişimi ısısı, boyca genleşme ve sıcaklık ölçekleri.
final _f20 = lmAile(
  'fm_hal_genlesme',
  'Hâl değişimi, genleşme ve sıcaklık ölçekleri',
  Topic.physics,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final k = c ~/ 3;
    if (c % 3 == 0) {
      final m = 10 * (a + 1); // 10 … 250 g
      final t0 = 4 * (1 + b % 5); // buz: −4 … −20 °C
      final t = 5 * (1 + b ~/ 5 + 4 * k); // su: 5 … 80 °C
      final q1 = m * t0 ~/ 2, q2 = m * 80, q3 = m * t;
      return _s(
        'Sıcaklığı −$t0 °C olan $m g buzun tamamını $t °C sıcaklığında suya '
        'dönüştürmek için gereken ısı kaç kaloridir? (Buzun öz ısısı '
        '0,5 cal/(g·°C), suyun öz ısısı 1 cal/(g·°C), buzun erime ısısı '
        '80 cal/g alınacaktır.)',
        q1 + q2 + q3,
        [q2 + q3, q1 + q3, 2 * q1 + q2 + q3, q1 + q2 + q3 / 2, q1 + q2],
        'Buzu 0 °C sıcaklığına getirmek için $m · 0,5 · $t0 = $q1 cal, eritmek '
        'için $m · 80 = $q2 cal, oluşan suyu $t °C sıcaklığına çıkarmak için '
        '$m · 1 · $t = $q3 cal gerekir. Toplam ısı ${q1 + q2 + q3} cal olur.',
      );
    }
    if (c % 3 == 1) {
      final boy = 2 * (a + 1); // 2 … 50 m
      final fark = 5 * (b + 1); // 5 … 100 °C
      final alfa = const [1.2, 2.0, 2.5][k]; // ·10⁻⁵ 1/°C
      final uzama = (a + 1) * (b + 1) * alfa / 10; // mm
      return _s(
        'Boyu $boy m olan metal bir çubuğun sıcaklığı $fark °C artırılıyor. '
        'Çubuğun yapıldığı metalin boyca genleşme katsayısı ${tr(alfa)}·10⁻⁵ 1/°C '
        'olduğuna göre çubuğun boyu kaç mm uzar?',
        uzama,
        [uzama / 10, uzama * 10, uzama / boy, uzama * 100],
        'ΔL = L₀·α·ΔT bağıntısından ΔL = $boy · ${tr(alfa)}·10⁻⁵ · $fark = '
        '${tr(uzama)}·10⁻³ m olur. Bu değer ${tr(uzama)} mm eder.',
        unit: 'mm',
      );
    }
    final cel = a + 25 * b + 1; // 1 … 500 °C
    final fah = 1.8 * cel + 32, kel = cel + 273;
    if (k == 0) {
      return _s(
        'Celsius ölçeğinde $cel °C olarak ölçülen bir sıcaklık, Fahrenheit '
        'ölçeğinde kaç °F olarak okunur?',
        fah,
        [1.8 * cel, 1.8 * (cel + 32), cel / 1.8 + 32, cel + 32],
        'F = 1,8·C + 32 bağıntısından F = 1,8 · $cel + 32 = ${tr(1.8 * cel)} + 32 = '
        '${tr(fah)} °F olur.',
      );
    }
    if (k == 1) {
      return _s(
        'Fahrenheit ölçeğinde ${tr(fah)} °F olarak ölçülen bir sıcaklık, '
        'Celsius ölçeğinde kaç °C olarak okunur?',
        cel,
        [fah - 32, (fah - 32) * 1.8, fah / 1.8, fah / 1.8 - 32],
        'C = (F − 32) / 1,8 bağıntısından C = (${tr(fah)} − 32) / 1,8 = '
        '${tr(fah - 32)} / 1,8 = $cel °C olur.',
        unit: '°C',
      );
    }
    return _s(
      'Kelvin ölçeğinde $kel K olarak ölçülen bir sıcaklık, Fahrenheit '
      'ölçeğinde kaç °F olarak okunur?',
      fah,
      [1.8 * kel + 32, 1.8 * cel, cel, kel + 32],
      'Önce Celsius değeri bulunur: $kel − 273 = $cel °C. Sonra F = 1,8·C + 32 '
      'bağıntısından F = 1,8 · $cel + 32 = ${tr(fah)} °F olur.',
    );
  },
  exam: _tyt,
  lesson: _fizik,
);

final lmFizikMekanik = <AdvancedFamily>[
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
