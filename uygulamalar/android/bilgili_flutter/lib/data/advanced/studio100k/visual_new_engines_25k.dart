import '../common.dart';

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

List<String> _pickDistinct(List<String> pool, String correct, int seed) {
  final out = <String>[];
  final n = pool.length;
  var step = 1;
  for (final candStep in const [7, 5, 3, 2, 1]) {
    if (n > candStep && _gcd(n, candStep) == 1) {
      step = candStep;
      break;
    }
  }
  var cursor = (seed * 17 + 5) % n;
  var guard = 0;
  while (out.length < 3 && guard < n) {
    final cand = pool[cursor];
    if (cand != correct && !out.contains(cand)) {
      out.add(cand);
    }
    cursor = (cursor + step) % n;
    guard++;
  }
  return out;
}

List<String> _intWrong(
  int correct,
  int seed, {
  String suffix = '',
  int minVal = -999999,
  int maxVal = 999999,
  List<int> deltas = const [1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, 8, 10],
}) {
  final out = <String>[];
  final seen = <int>{correct};
  final offset = seed.abs() % deltas.length;
  for (var k = 0; k < deltas.length * 2 && out.length < 3; k++) {
    final d = deltas[(offset + k) % deltas.length];
    final v = correct + d;
    if (v >= minVal && v <= maxVal && seen.add(v)) {
      out.add('$v$suffix');
    }
  }
  var bump = 1;
  while (out.length < 3) {
    final v = correct + bump;
    if (v <= maxVal && seen.add(v)) {
      out.add('$v$suffix');
    } else {
      final v2 = correct - bump;
      if (v2 >= minVal && seen.add(v2)) {
        out.add('$v2$suffix');
      }
    }
    bump++;
  }
  return out;
}

// ===========================================================================
// 1. DİJİTAL MANTIK KAPILARI DEVRESİ (VisualKind.circuit, unit='logic' · 4.000)
// ===========================================================================
const _gates = ['AND', 'OR', 'XOR', 'NAND', 'NOR', 'XNOR'];

int _evalGate(String gate, int a, int b) => switch (gate) {
      'AND' => a & b,
      'OR' => a | b,
      'XOR' => a ^ b,
      'NAND' => (a & b) == 1 ? 0 : 1,
      'NOR' => (a | b) == 1 ? 0 : 1,
      'XNOR' => (a ^ b) == 0 ? 1 : 0,
      'NOT' => a == 1 ? 0 : 1,
      _ => 0,
    };

String _gateDesc(String gate) => switch (gate) {
      'AND' => 'her iki giriş 1 ise 1 verir',
      'OR' => 'en az bir giriş 1 ise 1 verir',
      'XOR' => 'girişler farklı ise 1 verir',
      'NAND' => 'her iki giriş 1 olmadıkça 1 verir',
      'NOR' => 'her iki giriş 0 ise 1 verir',
      'XNOR' => 'girişler eşit ise 1 verir',
      _ => 'girişi tersler',
    };

AdvancedItem _buildCircuitLogic(int i) {
  final g1 = _gates[i % _gates.length];
  final g2 = _gates[(i ~/ _gates.length) % _gates.length];
  final bits = (i ~/ 36) % 8; // 0..7 => (a, b, c)
  final a = (bits >> 2) & 1;
  final b = (bits >> 1) & 1;
  final c = bits & 1;
  final mid = _evalGate(g1, a, b);
  final out = _evalGate(g2, mid, c);
  final angle = (i ~/ 288) % 5; // 5 analytical angles across all 288 circuits

  final vis = QuestionVisual(
    kind: VisualKind.circuit,
    title: 'Sayısal Mantık Devresi #${i + 1}',
    summary: 'Giriş bitlerini kapılardan geçirerek çıkışları hesaplayın.',
    labels: [g1, '$a', '$b', g2, '$c'],
    unit: 'logic',
  );

  if (angle == 0) {
    final correct = 'Ara çıkış = $mid · Son çıkış = $out';
    const all4 = [
      'Ara çıkış = 0 · Son çıkış = 0',
      'Ara çıkış = 0 · Son çıkış = 1',
      'Ara çıkış = 1 · Son çıkış = 0',
      'Ara çıkış = 1 · Son çıkış = 1',
    ];
    return AdvancedItem(
      'İki kademeli mantık devresinde A=$a, B=$b ve C=$c girişleri için ($g1 → $g2) ara çıkış ve son (?) çıkışı sırasıyla nedir?',
      correct,
      _pickDistinct(all4, correct, i + 3),
      '1. kapı $g1($a, $b) = $mid (${_gateDesc(g1)}). 2. kapı $g2($mid, $c) = $out (${_gateDesc(g2)}).',
      visual: vis,
    );
  } else if (angle == 1) {
    // What happens if C flips? (out_now, out_flipped)
    final outFlip = _evalGate(g2, mid, 1 - c);
    final correct = 'Şimdi: $out · C terslenirse: $outFlip';
    const all4 = [
      'Şimdi: 0 · C terslenirse: 0',
      'Şimdi: 0 · C terslenirse: 1',
      'Şimdi: 1 · C terslenirse: 0',
      'Şimdi: 1 · C terslenirse: 1',
    ];
    return AdvancedItem(
      'Şekildeki $g1 → $g2 devresinin mevcut (?) çıkışı ve C girişi terslendiğinde ($c → ${1 - c}) oluşacak yeni çıkış sırasıyla nedir?',
      correct,
      _pickDistinct(all4, correct, i + 5),
      'Ara çıkış $g1($a, $b) = $mid. C=$c iken $g2($mid, $c) = $out; C=${1 - c} iken $g2($mid, ${1 - c}) = $outFlip olur.',
      visual: vis,
    );
  } else if (angle == 2) {
    // Two-bit binary number (mid, out) in decimal (0..3)
    final dec = mid * 2 + out;
    final correct = '$dec (ikili: $mid$out₂)';
    const all4 = [
      '0 (ikili: 00₂)',
      '1 (ikili: 01₂)',
      '2 (ikili: 10₂)',
      '3 (ikili: 11₂)',
    ];
    return AdvancedItem(
      'Devrenin ara çıkışı X ve son çıkışı Y olmak üzere iki bitlik (XY)₂ sayısının onluk (decimal) değeri kaçtır?',
      correct,
      _pickDistinct(all4, correct, i + 7),
      'X = $g1($a, $b) = $mid, Y = $g2($mid, $c) = $out olduğundan ($mid$out)₂ = $dec bulunur.',
      visual: vis,
    );
  } else if (angle == 3) {
    // Count how many of the 8 truth-table rows output 1 for (A g1 B) g2 C
    var ones = 0;
    for (var row = 0; row < 8; row++) {
      final ra = (row >> 2) & 1;
      final rb = (row >> 1) & 1;
      final rc = row & 1;
      if (_evalGate(g2, _evalGate(g1, ra, rb), rc) == 1) ones++;
    }
    return AdvancedItem(
      'Şekildeki ($g1 → $g2) devresinin 8 satırlık doğruluk tablosunda toplam kaç giriş kombinasyonu son çıkışta 1 üretir?',
      '$ones kombinasyon',
      _intWrong(ones, i, suffix: ' kombinasyon', minVal: 0, maxVal: 8, deltas: const [1, -1, 2, -2, 3, -3]),
      '3 girişli (A, B, C) tüm 8 durum incelendiğinde (A $g1 B) $g2 C ifadesi tam $ones durumda 1 değerini alır.',
      visual: vis,
    );
  } else {
    // If input A flips (a -> 1-a), compare original output vs new output
    final midFlipA = _evalGate(g1, 1 - a, b);
    final outFlipA = _evalGate(g2, midFlipA, c);
    final correct = 'Mevcut: $out · A terslenirse: $outFlipA';
    const all4 = [
      'Mevcut: 0 · A terslenirse: 0',
      'Mevcut: 0 · A terslenirse: 1',
      'Mevcut: 1 · A terslenirse: 0',
      'Mevcut: 1 · A terslenirse: 1',
    ];
    return AdvancedItem(
      'Şekildeki devrede mevcut (?) çıkışı ve A girişi terslendiğinde ($a → ${1 - a}) oluşacak çıkış sırasıyla nedir?',
      correct,
      _pickDistinct(all4, correct, i + 11),
      'Mevcut durumda $g1($a, $b)=$mid → $g2($mid, $c)=$out. A=${1 - a} olduğunda $g1(${1 - a}, $b)=$midFlipA → $g2($midFlipA, $c)=$outFlipA.',
      visual: vis,
    );
  }
}

// ===========================================================================
// 2. ELEKTRİK DEVRELERİ & OHM YASASI (VisualKind.circuit · 3.000 soru)
// ===========================================================================
// Clean parallel resistor pairs with exact integer R_eq = (R1*R2)/(R1+R2)
const _parallelPairs = <(int r1, int r2, int req)>[
  (2, 2, 1), (3, 6, 2), (4, 4, 2), (4, 12, 3), (6, 6, 3),
  (6, 12, 4), (5, 20, 4), (8, 8, 4), (6, 30, 5), (10, 10, 5),
  (8, 24, 6), (9, 18, 6), (10, 15, 6), (12, 12, 6), (12, 24, 8),
  (16, 16, 8), (12, 36, 9), (15, 30, 10), (20, 20, 10), (12, 60, 10),
  (20, 30, 12), (15, 60, 12), (24, 24, 12), (20, 60, 15), (30, 30, 15),
  (24, 48, 16), (30, 60, 20), (40, 40, 20), (36, 72, 24), (60, 60, 30),
];

AdvancedItem _buildCircuitOhm(int i) {
  final isParallel = i.isOdd;
  final k = i ~/ 2;
  if (!isParallel) {
    // Series circuit: 2 or 3 resistors with exact integer I = V / R_eq
    final hasThree = (k % 3) == 2;
    final r1 = 2 + (k % 12);
    final r2 = 3 + ((k ~/ 12) % 11);
    final r3 = hasThree ? (2 + ((k ~/ 132) % 9)) : 0;
    final req = r1 + r2 + r3;
    final current = 1 + ((k ~/ 5) % 8); // 1..8 A
    final volt = current * req;
    final power = volt * current;
    final v1 = current * r1;
    final ask = k % 4;
    final vis = QuestionVisual(
      kind: VisualKind.circuit,
      title: 'Seri Elektrik Devresi',
      summary: 'V = $volt V · Dirençler seri bağlıdır (I = V / R_eş).',
      values: hasThree
          ? [volt.toDouble(), r1.toDouble(), r2.toDouble(), r3.toDouble()]
          : [volt.toDouble(), r1.toDouble(), r2.toDouble()],
      unit: 'series',
    );
    if (ask == 0) {
      return AdvancedItem(
        'Seri bağlı elektrik devresinde toplam eşdeğer direnç (R_eş) kaç Ohm (Ω) olur?',
        '$req Ω',
        _intWrong(req, i, suffix: ' Ω', minVal: 1, deltas: const [2, -2, 4, -4, 1, -1, 6]),
        'Seri devrede eşdeğer direnç doğrudan toplanır: ${hasThree ? '$r1 + $r2 + $r3' : '$r1 + $r2'} = $req Ω.',
        visual: vis,
      );
    } else if (ask == 1) {
      return AdvancedItem(
        'Şekildeki $volt V kaynaklı seri devreden geçen ana kol akımı (I) kaç Amper (A) olur?',
        '$current A',
        _intWrong(current, i, suffix: ' A', minVal: 1, deltas: const [1, -1, 2, -2, 3, -3, 4]),
        'R_eş = $req Ω olduğundan Ohm Yasası ile I = V / R_eş = $volt / $req = $current A bulunur.',
        visual: vis,
      );
    } else if (ask == 2) {
      return AdvancedItem(
        'Bu seri devrede $r1 Ω değerindeki ilk direncin uçları arasındaki gerilim düşümü (V₁) kaç Volt olur?',
        '$v1 V',
        _intWrong(v1, i, suffix: ' V', minVal: 1, deltas: [current, -current, 2 * current, -2 * current, 4, -4, 6]),
        'Ana kol akımı I = $volt / $req = $current A. V₁ = I · R₁ = $current × $r1 = $v1 V.',
        visual: vis,
      );
    } else {
      return AdvancedItem(
        'Şekildeki seri devrede kaynağın sağladığı toplam elektriksel güç (P = V · I) kaç Watt (W) olur?',
        '$power W',
        _intWrong(power, i, suffix: ' W', minVal: 2, deltas: [volt, -volt, req, -req, 10, -10, 20]),
        'I = $volt / $req = $current A olduğundan P = V · I = $volt × $current = $power W.',
        visual: vis,
      );
    }
  } else {
    // Parallel circuit: clean integer R_eq, exact integer I1, I2, I_tot, P
    final p = _parallelPairs[k % _parallelPairs.length];
    final r1 = p.$1, r2 = p.$2, req = p.$3;
    final lcm = (r1 * r2) ~/ _gcd(r1, r2);
    final mult = 1 + ((k ~/ _parallelPairs.length) % 6); // 1..6
    final volt = lcm * mult;
    final i1 = volt ~/ r1;
    final i2 = volt ~/ r2;
    final iTot = i1 + i2;
    final power = volt * iTot;
    final ask = k % 4;
    final vis = QuestionVisual(
      kind: VisualKind.circuit,
      title: 'Paralel Elektrik Devresi',
      summary: 'V = $volt V · R₁ = $r1 Ω ve R₂ = $r2 Ω paralel bağlıdır.',
      values: [volt.toDouble(), r1.toDouble(), r2.toDouble()],
      unit: 'parallel',
    );
    if (ask == 0) {
      return AdvancedItem(
        'R₁ = $r1 Ω ve R₂ = $r2 Ω dirençlerinin paralel bağlandığı devrede eşdeğer direnç (R_eş) kaç Ohm (Ω) olur?',
        '$req Ω',
        _intWrong(req, i, suffix: ' Ω', minVal: 1, deltas: const [1, -1, 2, -2, 3, -3, 4, 6]),
        'Paralel bağlantıda R_eş = (R₁·R₂)/(R₁+R₂) = ($r1·$r2)/(${r1 + r2}) = $req Ω.',
        visual: vis,
      );
    } else if (ask == 1) {
      return AdvancedItem(
        'Şekildeki $volt V gerilimli paralel devrede ana koldan çekilen toplam akım (I_top) kaç Amper olur?',
        '$iTot A',
        _intWrong(iTot, i, suffix: ' A', minVal: 1, deltas: const [1, -1, 2, -2, 3, -3, 4, 5]),
        'R_eş = $req Ω → I_top = $volt / $req = $iTot A (I₁ = $i1 A ve I₂ = $i2 A).',
        visual: vis,
      );
    } else if (ask == 2) {
      return AdvancedItem(
        'Paralel bağlı bu devrede yalnız R₁ = $r1 Ω kolundan geçen akım (I₁) kaç Amper olur?',
        '$i1 A',
        _intWrong(i1, i, suffix: ' A', minVal: 1, deltas: const [1, -1, 2, -2, 3, -3, 4]),
        'Paralel kollarda gerilim eşittir ($volt V): I₁ = V / R₁ = $volt / $r1 = $i1 A.',
        visual: vis,
      );
    } else {
      return AdvancedItem(
        'Şekildeki paralel devrenin toplam elektriksel gücü (P = V · I_top) kaç Watt (W) olur?',
        '$power W',
        _intWrong(power, i, suffix: ' W', minVal: 4, deltas: [volt, -volt, 2 * volt, 12, -12, 24]),
        'I_top = $iTot A olduğundan P = $volt × $iTot = $power W.',
        visual: vis,
      );
    }
  }
}

// ===========================================================================
// 3. VENN ŞEMASI, KÜMELER & OLASILIK STÜDYOSU (VisualKind.venn · 5.000 soru)
// ===========================================================================
const _vennThemes = <(String a, String b, String title)>[
  ('İngilizce', 'Almanca', 'Dil Kulübü Kümesi'),
  ('Futbol', 'Basketbol', 'Spor Tercihleri'),
  ('Fizik', 'Kimya', 'Bilim Olimpiyatı'),
  ('Roman', 'Şiir', 'Okuma Kulübü'),
  ('Piyano', 'Keman', 'Müzik Akademisi'),
  ('Kodlama', 'Tasarım', 'Teknoloji Atölyesi'),
  ('Yüzme', 'Koşu', 'Atletizm Grubu'),
  ('Kahve', 'Çay', 'Kafeterya Anketi'),
  ('Sinema', 'Tiyatro', 'Sanat İzleyicileri'),
  ('Satranç', 'Briç', 'Akıl Oyunları'),
  ('Tarih', 'Coğrafya', 'Sosyal Bilimler'),
  ('Android', 'Web', 'Yazılım Topluluğu'),
];

AdvancedItem _buildVennSets(int i) {
  final theme = _vennThemes[i % _vennThemes.length];
  final k = i ~/ _vennThemes.length;
  final onlyA = 4 + (k % 21);
  final both = 2 + ((k * 3) % 15);
  final onlyB = 5 + ((k * 7) % 19);
  final outside = 1 + ((k * 5) % 12);
  final totalE = onlyA + both + onlyB + outside;
  final unionAB = onlyA + both + onlyB;
  final setA = onlyA + both;
  final setB = onlyB + both;
  final symDiff = onlyA + onlyB;
  final notA = onlyB + outside;

  final qType = i % 8;
  final highlight = switch (qType) {
    0 => 'union',
    1 => 'both',
    2 => 'onlyA',
    3 => 'onlyB',
    _ => 'none',
  };

  final vis = QuestionVisual(
    kind: VisualKind.venn,
    title: theme.$3,
    summary: 'A = ${theme.$1}, B = ${theme.$2}, E = Evrensel Küme',
    labels: [theme.$1, theme.$2],
    values: [onlyA.toDouble(), both.toDouble(), onlyB.toDouble(), outside.toDouble()],
    unit: highlight,
  );

  switch (qType) {
    case 0:
      return AdvancedItem(
        'Venn şemasına göre ${theme.$1} veya ${theme.$2} kümelerinden EN AZ BİRİNDE bulunan kişi sayısı s(A ∪ B) kaçtır?',
        '$unionAB kişi',
        _intWrong(unionAB, i, suffix: ' kişi', minVal: 1, deltas: [outside, -outside, both, -both, 2, -2, 4]),
        's(A ∪ B) = $onlyA + $both + $onlyB = $unionAB kişi.',
        visual: vis,
      );
    case 1:
      return AdvancedItem(
        'Venn şemasına göre evrensel kümedeki toplam kişi sayısı s(E) kaçtır?',
        '$totalE kişi',
        _intWrong(totalE, i, suffix: ' kişi', minVal: 1, deltas: [outside, -outside, both, -both, 3, -3, 5]),
        's(E) = $onlyA + $both + $onlyB + $outside = $totalE kişi.',
        visual: vis,
      );
    case 2:
      return AdvancedItem(
        'Şemaya göre ${theme.$1} kümesinin toplam eleman sayısı s(A) kaçtır?',
        '$setA kişi',
        _intWrong(setA, i, suffix: ' kişi', minVal: 1, deltas: [both, -both, 2, -2, 3, -3, 5]),
        's(A) = Yalnız A + Kesişim = $onlyA + $both = $setA kişi.',
        visual: vis,
      );
    case 3:
      return AdvancedItem(
        'Şemaya göre ${theme.$2} kümesinin toplam eleman sayısı s(B) kaçtır?',
        '$setB kişi',
        _intWrong(setB, i, suffix: ' kişi', minVal: 1, deltas: [both, -both, 2, -2, 4, -4, 5]),
        's(B) = Yalnız B + Kesişim = $onlyB + $both = $setB kişi.',
        visual: vis,
      );
    case 4:
      return AdvancedItem(
        'Şemada YALNIZ BİR kümede yer alanların toplamı (simetrik fark s(A △ B)) kaçtır?',
        '$symDiff kişi',
        _intWrong(symDiff, i, suffix: ' kişi', minVal: 1, deltas: [both, -both, outside, 2, -2, 4]),
        'Yalnız ${theme.$1} ($onlyA) + Yalnız ${theme.$2} ($onlyB) = $symDiff kişi.',
        visual: vis,
      );
    case 5:
      return AdvancedItem(
        'Şemaya göre ${theme.$1} kümesinde BULUNMAYAN kişi sayısı s(A\') kaçtır?',
        '$notA kişi',
        _intWrong(notA, i, suffix: ' kişi', minVal: 1, deltas: [outside, -outside, both, 2, -2, 3]),
        'A\'nın tümleyeni = Yalnız B ($onlyB) + Dış ($outside) = $notA kişi.',
        visual: vis,
      );
    case 6:
      final diffAB = (setA - setB).abs();
      return AdvancedItem(
        '${theme.$1} kümesinin eleman sayısı ile ${theme.$2} kümesinin eleman sayısı arasındaki pozitif fark |s(A) − s(B)| kaçtır?',
        '$diffAB',
        _intWrong(diffAB, i, minVal: 0, deltas: const [1, 2, 3, -1, -2, 4, 5]),
        's(A) = $setA, s(B) = $setB olduğundan |s(A) − s(B)| = |$setA − $setB| = $diffAB.',
        visual: vis,
      );
    default:
      // Simplified fraction probability P(A ∩ B)
      final g = _gcd(both, totalE);
      final num = both ~/ g;
      final den = totalE ~/ g;
      final correct = '$num / $den';
      final wrong = <String>[];
      for (final pair in [
        (onlyA, totalE),
        (onlyB, totalE),
        (both, unionAB),
        (outside, totalE),
        (both + 1, totalE),
        (both, totalE + 2),
      ]) {
        final gg = _gcd(pair.$1, pair.$2);
        final cand = '${pair.$1 ~/ gg} / ${pair.$2 ~/ gg}';
        if (cand != correct && !wrong.contains(cand)) wrong.add(cand);
        if (wrong.length == 3) break;
      }
      var bump = 1;
      while (wrong.length < 3) {
        final cand = '${num + bump} / ${den + bump * 2}';
        if (cand != correct && !wrong.contains(cand)) wrong.add(cand);
        bump++;
      }
      return AdvancedItem(
        'Evrensel kümeden rastgele seçilen bir kişinin HER İKİ grupta da (${theme.$1} ∩ ${theme.$2}) olma olasılığı nedir?',
        correct,
        wrong,
        'Kesişim $both, evrensel küme $totalE kişi olduğundan olasılık $both / $totalE = $correct olur.',
        visual: vis,
      );
  }
}

// ===========================================================================
// 4. PUSULA, ROTA, AZİMUT & YÖN NAVİGASYONU (VisualKind.compass · 4.500 soru)
// ===========================================================================
const _compassDirs = <(int deg, String tr, String en, String abbr)>[
  (0, 'Kuzey (0°)', 'North (N)', 'K'),
  (45, 'Kuzeydoğu (45°)', 'Northeast (NE)', 'KD'),
  (90, 'Doğu (90°)', 'East (E)', 'D'),
  (135, 'Güneydoğu (135°)', 'Southeast (SE)', 'GD'),
  (180, 'Güney (180°)', 'South (S)', 'G'),
  (225, 'Güneybatı (225°)', 'Southwest (SW)', 'GB'),
  (270, 'Batı (270°)', 'West (W)', 'B'),
  (315, 'Kuzeybatı (315°)', 'Northwest (NW)', 'KB'),
];

const _turnSteps = [45, 90, 135, 180, 225, 270, -45, -90, -135, -225, -270];
const _navContexts = [
  'Bir yelkenli tekne',
  'Otonom keşif dronu',
  'Dağcılık ekibi',
  'Kargo gemisi',
  'Kutup araştırma aracı',
  'Keşif uçağı',
];

AdvancedItem _buildCompassNav(int i) {
  final startIdx = i % 8;
  final start = _compassDirs[startIdx];
  final mode = (i ~/ 8) % 5;
  final k = i ~/ 40;
  final vehicle = _navContexts[k % _navContexts.length];

  if (mode == 0 || mode == 1) {
    // Turn by clockwise/counter-clockwise angle and find resulting direction
    final turn = _turnSteps[(k + mode * 3) % _turnSteps.length];
    final endDeg = ((start.$1 + turn) % 360 + 360) % 360;
    final endDir = _compassDirs[endDeg ~/ 45];
    final dirWord = turn > 0 ? 'saat yönünde (sağa)' : 'saat yönünün tersine (sola)';
    final absTurn = turn.abs();
    final askEn = mode == 1;
    final pool = askEn
        ? [for (final d in _compassDirs) d.$3]
        : [for (final d in _compassDirs) d.$2];
    final ans = askEn ? endDir.$3 : endDir.$2;
    return AdvancedItem(
      askEn
          ? '$vehicle ${start.$2} yönüne ilerlerken $dirWord $absTurn° dönüyor. Yeni yönün İNGİLİZCE adı hangisidir?'
          : '$vehicle pusulada gösterilen ${start.$2} yönüne giderken $dirWord $absTurn° dönerse hangi yöne bakar?',
      ans,
      _pickDistinct(pool, ans, i + 5),
      '${start.$1}° ${turn > 0 ? '+' : '−'} $absTurn° = $endDeg° → ${endDir.$2} (${endDir.$3}).',
      visual: QuestionVisual(
        kind: VisualKind.compass,
        title: 'Pusula Rota Navigasyonu',
        summary: 'Başlangıç kerterizi ${start.$1}°, dönüş ${turn > 0 ? '+$absTurn°' : '−$absTurn°'}.',
        values: [start.$1.toDouble(), turn.toDouble()],
        unit: '${start.$4} (${start.$1}°) → ${turn > 0 ? '+$absTurn°' : '−$absTurn°'}',
      ),
    );
  } else if (mode == 2) {
    // Precise azimuth angle arithmetic (steps of 15°)
    final bearing = ((k * 15) % 360);
    const fineTurns = [30, 45, 60, 75, 90, 120, 135, 150, -30, -45, -60, -90, -120];
    final turn = fineTurns[(k ~/ 3) % fineTurns.length];
    final targetDeg = ((bearing + turn) % 360 + 360) % 360;
    final dirWord = turn > 0 ? 'saat yönünde' : 'saat yönünün tersine';
    return AdvancedItem(
      '$vehicle $bearing° azimut açısıyla ilerlerken $dirWord ${turn.abs()}° yön değiştiriyor. Yeni azimut (kerteriz) açısı kaç derecedir?',
      '$targetDeg°',
      _intWrong(targetDeg, i, suffix: '°', minVal: 0, maxVal: 359, deltas: const [15, -15, 30, -30, 45, -45, 90, -90]),
      '($bearing° ${turn > 0 ? '+' : '−'} ${turn.abs()}°) mod 360° = $targetDeg°.',
      visual: QuestionVisual(
        kind: VisualKind.compass,
        title: 'Azimut & Kerteriz Hesabı',
        summary: 'Başlangıç açısı $bearing° · Dönüş ${turn > 0 ? '+$turn°' : '$turn°'}.',
        values: [bearing.toDouble(), turn.toDouble()],
        unit: 'Azimut: $bearing°',
      ),
    );
  } else if (mode == 3) {
    // Back-azimuth (exact opposite bearing)
    final bearing = ((k * 15 + 5) % 360);
    final back = (bearing + 180) % 360;
    return AdvancedItem(
      '$vehicle $bearing° pusula açısıyla ilerlemektedir. Geldiği noktaya tam zıt yönde (ters azimut) dönmek için hangi açıyı izlemelidir?',
      '$back°',
      _intWrong(back, i, suffix: '°', minVal: 0, maxVal: 359, deltas: const [15, -15, 30, -30, 45, -45, 90, -90]),
      'Ters azimut = ($bearing° + 180°) mod 360° = $back°.',
      visual: QuestionVisual(
        kind: VisualKind.compass,
        title: 'Ters Azimut (Geri Dönüş)',
        summary: 'Mevcut yön $bearing° · Tam zıt kerterizi hesaplayın.',
        values: [bearing.toDouble(), 180.0],
        unit: 'Gidiş: $bearing° → Dönüş: ?',
      ),
    );
  } else {
    // Two-step navigation turn
    const t1List = [45, 90, 135, -45, -90];
    const t2List = [90, 135, -45, -90, 180];
    final t1 = t1List[k % t1List.length];
    final t2 = t2List[(k ~/ 5) % t2List.length];
    final net = t1 + t2;
    final endDeg = ((start.$1 + net) % 360 + 360) % 360;
    final endDir = _compassDirs[endDeg ~/ 45];
    String turnPhrase(int t) => t > 0 ? 'sağa $t°' : 'sola ${t.abs()}°';
    return AdvancedItem(
      '$vehicle ${start.$2} yönüne bakarken önce ${turnPhrase(t1)}, ardından ${turnPhrase(t2)} dönüyor. Son yönü hangisidir?',
      endDir.$2,
      _pickDistinct([for (final d in _compassDirs) d.$2], endDir.$2, i + 13),
      'Toplam dönüş ${t1 >= 0 ? '+$t1°' : '$t1°'} ve ${t2 >= 0 ? '+$t2°' : '$t2°'} → net $net°. ${start.$1}° + ($net°) ≡ $endDeg° (${endDir.$2}).',
      visual: QuestionVisual(
        kind: VisualKind.compass,
        title: 'Çift Adımlı Pusula Manevrası',
        summary: 'Başlangıç ${start.$2} · İki ardışık dönüşün bileşkesi.',
        values: [start.$1.toDouble(), net.toDouble()],
        unit: '${start.$4} · 2 Manevra',
      ),
    );
  }
}

// ===========================================================================
// 5. RENK LABORATUVARI, RGB HEX & OPTİK SPEKTRUM (VisualKind.colorLab · 4.500)
// ===========================================================================
typedef _ColorMixSpec = ({
  String hexA,
  String nameA,
  String hexB,
  String nameB,
  String result,
  String kind,
  String explain,
});

const _colorMixes = <_ColorMixSpec>[
  (hexA: '#FF2222', nameA: 'Kırmızı Işık', hexB: '#22EE44', nameB: 'Yeşil Işık', result: 'Sarı (Yellow)', kind: 'Toplamsal Işık (RGB)', explain: 'RGB ışık karışımında Kırmızı + Yeşil = Sarı ışık oluşturur.'),
  (hexA: '#FF2222', nameA: 'Kırmızı Işık', hexB: '#2266FF', nameB: 'Mavi Işık', result: 'Magenta (Eflatun)', kind: 'Toplamsal Işık (RGB)', explain: 'RGB ışık karışımında Kırmızı + Mavi = Magenta üretir.'),
  (hexA: '#22EE44', nameA: 'Yeşil Işık', hexB: '#2266FF', nameB: 'Mavi Işık', result: 'Camgöbeği (Cyan)', kind: 'Toplamsal Işık (RGB)', explain: 'RGB ışık karışımında Yeşil + Mavi = Camgöbeği (Cyan) oluşturur.'),
  (hexA: '#FFE600', nameA: 'Sarı Işık', hexB: '#2266FF', nameB: 'Mavi Işık', result: 'Beyaz Işık', kind: 'Tamamlayıcı Işıklar', explain: 'Sarı (Kırmızı+Yeşil) ile Mavi ışık birleştiğinde Beyaz ışık elde edilir.'),
  (hexA: '#00E5FF', nameA: 'Cyan Işık', hexB: '#FF2222', nameB: 'Kırmızı Işık', result: 'Beyaz Işık', kind: 'Tamamlayıcı Işıklar', explain: 'Cyan (Yeşil+Mavi) ile Kırmızı ışık tamamlayıcıdır ve Beyaz ışık verir.'),
  (hexA: '#FF22CC', nameA: 'Magenta Işık', hexB: '#22EE44', nameB: 'Yeşil Işık', result: 'Beyaz Işık', kind: 'Tamamlayıcı Işıklar', explain: 'Magenta (Kırmızı+Mavi) ile Yeşil ışık tamamlayıcıdır ve Beyaz ışık verir.'),
  (hexA: '#E62229', nameA: 'Kırmızı Boya', hexB: '#FFD600', nameB: 'Sarı Boya', result: 'Turuncu (Orange)', kind: 'Boya / Pigment (RYB)', explain: 'Pigment karışımında Kırmızı + Sarı ana renkleri Turuncu ara rengini verir.'),
  (hexA: '#1E6BFF', nameA: 'Mavi Boya', hexB: '#FFD600', nameB: 'Sarı Boya', result: 'Yeşil (Green)', kind: 'Boya / Pigment (RYB)', explain: 'Boya karışımında Mavi + Sarı = Yeşil elde edilir.'),
  (hexA: '#E62229', nameA: 'Kırmızı Boya', hexB: '#1E6BFF', nameB: 'Mavi Boya', result: 'Mor (Purple)', kind: 'Boya / Pigment (RYB)', explain: 'Boya karışımında Kırmızı + Mavi = Mor ara rengini oluşturur.'),
  (hexA: '#E62229', nameA: 'Kırmızı Boya', hexB: '#FFFFFF', nameB: 'Beyaz Boya', result: 'Pembe (Pink)', kind: 'Açık Ton (Tint)', explain: 'Kırmızı boyaya beyaz eklenmesiyle açık ton olan Pembe elde edilir.'),
  (hexA: '#111111', nameA: 'Siyah Boya', hexB: '#FFFFFF', nameB: 'Beyaz Boya', result: 'Gri (Gray)', kind: 'Nötr Karışım', explain: 'Siyah ve beyaz boyanın karışımı nötr Gri tonunu oluşturur.'),
  (hexA: '#1E6BFF', nameA: 'Mavi Boya', hexB: '#22C55E', nameB: 'Yeşil Boya', result: 'Turkuaz (Teal)', kind: 'Üçüncül Pigment', explain: 'Mavi ile Yeşil boyanın karışımı Turkuaz (mavi-yeşil) tonu verir.'),
  (hexA: '#E62229', nameA: 'Kırmızı Boya', hexB: '#22C55E', nameB: 'Yeşil Boya', result: 'Kahverengi', kind: 'Tamamlayıcı Boya', explain: 'Tamamlayıcı pigmentler (Kırmızı + Yeşil boya) birleştiğinde koyu Kahverengi verir.'),
  (hexA: '#00D4FF', nameA: 'Cyan Mürekkep', hexB: '#FFE600', nameB: 'Sarı Mürekkep', result: 'Yeşil (Green)', kind: 'CMYK Baskı', explain: 'CMYK matbaa baskısında Cyan + Sarı mürekkep Yeşil rengi basar.'),
  (hexA: '#FF1EAA', nameA: 'Magenta Mürekkep', hexB: '#FFE600', nameB: 'Sarı Mürekkep', result: 'Kırmızı (Red)', kind: 'CMYK Baskı', explain: 'CMYK matbaa baskısında Magenta + Sarı mürekkep Kırmızı rengi üretir.'),
  (hexA: '#00D4FF', nameA: 'Cyan Mürekkep', hexB: '#FF1EAA', nameB: 'Magenta Mürekkep', result: 'Mavi (Blue)', kind: 'CMYK Baskı', explain: 'CMYK matbaa baskısında Cyan + Magenta mürekkep Mavi rengi üretir.'),
];

const _mixPool = [
  'Sarı (Yellow)', 'Magenta (Eflatun)', 'Camgöbeği (Cyan)', 'Beyaz Işık',
  'Turuncu (Orange)', 'Yeşil (Green)', 'Mor (Purple)', 'Pembe (Pink)',
  'Gri (Gray)', 'Turkuaz (Teal)', 'Kahverengi', 'Kırmızı (Red)', 'Mavi (Blue)',
];

const _spectrumBands = <(int minNm, int maxNm, String name)>[
  (385, 445, 'Mor (Violet)'),
  (455, 490, 'Mavi (Blue)'),
  (500, 565, 'Yeşil (Green)'),
  (572, 588, 'Sarı (Yellow)'),
  (593, 618, 'Turuncu (Orange)'),
  (625, 740, 'Kırmızı (Red)'),
];

String _hex2(int v) => v.toRadixString(16).toUpperCase().padLeft(2, '0');

AdvancedItem _buildColorLab(int i) {
  final mode = i % 3; // 3 modes × 1.500 = 4.500
  final k = i ~/ 3;
  if (mode == 0) {
    // Color mixing (RGB light, RYB pigment, CMYK print)
    final m = _colorMixes[k % _colorMixes.length];
    final style = (k ~/ _colorMixes.length) % 4;
    final prompts = [
      '${m.kind} modelinde ${m.nameA} ile ${m.nameB} karıştırıldığında hangi sonuç renk elde edilir?',
      'Görseldeki renk deneyinde (${m.kind}) soru işareti (?) yerine hangi renk gelmelidir?',
      'Optik & Tasarım Laboratuvarı: ${m.nameA} + ${m.nameB} (${m.kind}) işleminin sonucu nedir?',
      '${m.kind} kuralına göre şekilde birleştirilen iki rengin bileşimi hangisidir?',
    ];
    return AdvancedItem(
      prompts[style],
      m.result,
      _pickDistinct(_mixPool, m.result, i + 7),
      m.explain,
      visual: QuestionVisual(
        kind: VisualKind.colorLab,
        title: 'Renk Karışım Laboratuvarı · ${m.kind}',
        summary: '${m.nameA} + ${m.nameB} = ?',
        labels: [m.hexA, m.nameA, m.hexB, m.nameB],
        unit: 'mix',
      ),
    );
  } else if (mode == 1) {
    // RGB & Hex studio
    const levels = [0, 32, 64, 96, 128, 160, 192, 224, 255];
    final r = levels[k % levels.length];
    final g = levels[(k ~/ levels.length) % levels.length];
    final b = levels[(k ~/ (levels.length * levels.length) + k * 2) % levels.length];
    final hex = '#${_hex2(r)}${_hex2(g)}${_hex2(b)}';
    final sub = k % 3;
    final vis = QuestionVisual(
      kind: VisualKind.colorLab,
      title: 'RGB & Hex Renk Okuma',
      summary: 'Kırmızı (R), Yeşil (G) ve Mavi (B) kanallarını inceleyin.',
      labels: [hex],
      unit: 'rgb',
    );
    if (sub == 0) {
      // Exact hex code from R, G, B bars
      final wrong = <String>[];
      for (final c in [
        '#${_hex2(g)}${_hex2(r)}${_hex2(b)}',
        '#${_hex2(r)}${_hex2(b)}${_hex2(g)}',
        '#${_hex2(255 - r)}${_hex2(g)}${_hex2(b)}',
        '#${_hex2(r)}${_hex2(255 - g)}${_hex2(b)}',
        '#${_hex2(r)}${_hex2(g)}${_hex2(255 - b)}',
        '#${_hex2((r + 64) % 256)}${_hex2(g)}${_hex2(b)}',
      ]) {
        if (c != hex && !wrong.contains(c)) wrong.add(c);
        if (wrong.length == 3) break;
      }
      return AdvancedItem(
        'Kanal değerleri R=$r, G=$g, B=$b olarak verilen bu rengin 16\'lık (HEX) kodu hangisidir?',
        hex,
        wrong,
        'R=$r → ${_hex2(r)}, G=$g → ${_hex2(g)}, B=$b → ${_hex2(b)} olduğundan HEX kodu $hex olur.',
        visual: vis,
      );
    } else if (sub == 1) {
      // Complementary (inverted) RGB color
      final ir = 255 - r, ig = 255 - g, ib = 255 - b;
      final ans = 'RGB($ir, $ig, $ib)';
      final wrong = <String>[];
      for (final cand in [
        'RGB($r, $ig, $ib)',
        'RGB($ir, $g, $ib)',
        'RGB($ir, $ig, $b)',
        'RGB($ig, $ir, $ib)',
        'RGB(${(ir + 32) % 256}, $ig, $ib)',
      ]) {
        if (cand != ans && !wrong.contains(cand)) wrong.add(cand);
        if (wrong.length == 3) break;
      }
      return AdvancedItem(
        'RGB($r, $g, $b) renginin tam dijital tersi (negatif / tamamlayıcı RGB) değeri hangisidir?',
        ans,
        wrong,
        'Dijital negatif (255−R, 255−G, 255−B) = (${255 - r}, ${255 - g}, ${255 - b}) olarak hesaplanır.',
        visual: vis,
      );
    } else {
      // Sum of RGB channels or rounded average brightness
      final sum = r + g + b;
      return AdvancedItem(
        'Görseldeki renk örneğinin R ($r), G ($g) ve B ($b) kanal değerlerinin toplamı kaçtır?',
        '$sum',
        _intWrong(sum, i, minVal: 0, maxVal: 765, deltas: const [32, -32, 64, -64, 16, -16, 48]),
        'R + G + B = $r + $g + $b = $sum (en parlak beyaz için toplam 765\'tir).',
        visual: vis,
      );
    }
  } else {
    // Visible light spectrum (380..750 nm)
    final band = _spectrumBands[k % _spectrumBands.length];
    final span = band.$2 - band.$1 + 1;
    final nm = band.$1 + ((k * 7) % span);
    final askBand = (k ~/ 6) % 3 != 2;
    final vis = QuestionVisual(
      kind: VisualKind.colorLab,
      title: 'Görünür Işık Spektrumu',
      summary: 'İşaretli dalga boyu λ = $nm nm',
      values: [nm.toDouble()],
      unit: 'spectrum',
    );
    if (askBand) {
      return AdvancedItem(
        'Görünür ışık spektrumunda λ = $nm nm dalga boyu hangi renk kuşağına karşılık gelir?',
        band.$3,
        _pickDistinct([for (final b in _spectrumBands) b.$3], band.$3, i + 11),
        '$nm nm dalga boyu ${band.$1}–${band.$2} nm aralığındaki ${band.$3} ışığa aittir.',
        visual: vis,
      );
    }
    // Compare photon energy with another wavelength
    final otherBand = _spectrumBands[(k + 2) % _spectrumBands.length];
    final otherNm = (otherBand.$1 + otherBand.$2) ~/ 2;
    final higher = nm < otherNm
        ? '$nm nm (${band.$3}) daha yüksek enerjilidir'
        : '$otherNm nm (${otherBand.$3}) daha yüksek enerjilidir';
    final opts = [
      '$nm nm (${band.$3}) daha yüksek enerjilidir',
      '$otherNm nm (${otherBand.$3}) daha yüksek enerjilidir',
      'İki fotonun enerjisi her zaman eşittir',
      'Dalga boyu foton enerjisini etkilemez',
    ];
    return AdvancedItem(
      'Spektrumdaki λ₁ = $nm nm ışık ile λ₂ = $otherNm nm ışığın foton enerjileri (E = hc/λ) karşılaştırıldığında hangisi doğrudur?',
      higher,
      _pickDistinct(opts, higher, i + 13),
      'Foton enerjisi dalga boyu ile ters orantılıdır (E = hc/λ). Kısa dalga boylu ışık daha yüksek frekans ve enerjiye sahiptir.',
      visual: vis,
    );
  }
}

// ===========================================================================
// 6. 2 OKTAV PİYANO KLAVYESİ, ARALIK & AKOR STÜDYOSU (VisualKind.piano · 4.000)
// ===========================================================================
const _pianoKeys24 = <(String code, String tr, int semi)>[
  ('C4', 'Do (C4)', 0), ('C#4', 'Do♯ / Re♭ (C♯4)', 1), ('D4', 'Re (D4)', 2),
  ('D#4', 'Re♯ / Mi♭ (D♯4)', 3), ('E4', 'Mi (E4)', 4), ('F4', 'Fa (F4)', 5),
  ('F#4', 'Fa♯ / Sol♭ (F♯4)', 6), ('G4', 'Sol (G4)', 7), ('G#4', 'Sol♯ / La♭ (G♯4)', 8),
  ('A4', 'La (A4)', 9), ('A#4', 'La♯ / Si♭ (A♯4)', 10), ('B4', 'Si (B4)', 11),
  ('C5', 'İnce Do (C5)', 12), ('C#5', 'İnce Do♯ (C♯5)', 13), ('D5', 'İnce Re (D5)', 14),
  ('D#5', 'İnce Re♯ (D♯5)', 15), ('E5', 'İnce Mi (E5)', 16), ('F5', 'İnce Fa (F5)', 17),
  ('F#5', 'İnce Fa♯ (F♯5)', 18), ('G5', 'İnce Sol (G5)', 19), ('G#5', 'İnce Sol♯ (G♯5)', 20),
  ('A5', 'İnce La (A5)', 21), ('A#5', 'İnce La♯ (A♯5)', 22), ('B5', 'İnce Si (B5)', 23),
];

const _pianoChordShapes = <(String trName, String kind, List<int> steps)>[
  ('Majör Akor', 'Majör (0–4–7)', [0, 4, 7]),
  ('Minör Akor', 'Minör (0–3–7)', [0, 3, 7]),
  ('Eksilmiş (Dim)', 'Eksilmiş (0–3–6)', [0, 3, 6]),
  ('Artmış (Aug)', 'Artmış (0–4–8)', [0, 4, 8]),
  ('Sus2 Akoru', 'Sus2 (0–2–7)', [0, 2, 7]),
  ('Sus4 Akoru', 'Sus4 (0–5–7)', [0, 5, 7]),
  ('Majör 7\'li (Maj7)', 'Maj7 (0–4–7–11)', [0, 4, 7, 11]),
  ('Dominant 7\'li (7)', 'Dom7 (0–4–7–10)', [0, 4, 7, 10]),
];

const _rootShortTr = ['Do', 'Do♯', 'Re', 'Mi♭', 'Mi', 'Fa', 'Fa♯', 'Sol', 'La♭', 'La', 'Si♭', 'Si'];

const _pianoIntervals = <(int semi, String label)>[
  (1, 'Küçük İkili (1 yarım ses)'),
  (2, 'Büyük İkili (2 yarım ses)'),
  (3, 'Küçük Üçlü (3 yarım ses)'),
  (4, 'Büyük Üçlü (4 yarım ses)'),
  (5, 'Tam Dörtlü (5 yarım ses)'),
  (6, 'Artık Dörtlü / Triton (6 yarım ses)'),
  (7, 'Tam Beşli (7 yarım ses)'),
  (8, 'Küçük Altılı (8 yarım ses)'),
  (9, 'Büyük Altılı (9 yarım ses)'),
  (10, 'Küçük Yedili (10 yarım ses)'),
  (11, 'Büyük Yedili (11 yarım ses)'),
  (12, 'Tam Oktav (12 yarım ses)'),
];

AdvancedItem _buildPianoStudio(int i) {
  final mode = i % 4; // 4 modes × 1.000 = 4.000
  final k = i ~/ 4;
  if (mode == 0) {
    // Single key recognition across 2 octaves
    final keySpec = _pianoKeys24[k % _pianoKeys24.length];
    final style = (k ~/ 24) % 4;
    const prompts = [
      'Piyano klavyesinde altın renkle işaretlenen tuş hangi notadır?',
      '2 oktavlık piyano düzeninde (C4–B5) vurgulanan tuş aşağıdakilerden hangisidir?',
      'Klavyede basılı gösterilen tuşun solfej ve oktav adı hangisidir?',
      'Piyano pratiği: C4 ve C5 işaretlerine bakarak vurgulanan notayı bulun.',
    ];
    return AdvancedItem(
      prompts[style],
      keySpec.$2,
      _pickDistinct([for (final x in _pianoKeys24) x.$2], keySpec.$2, i + 3),
      'İki siyah tuş grubunun solundaki beyaz tuş Do (C)\'dir; işaretli tuş ${keySpec.$2} notasına karşılık gelir.',
      visual: QuestionVisual(
        kind: VisualKind.piano,
        title: 'Piyano Klavye Okuma',
        summary: 'C4 (Orta Do) ile B5 aralığında işaretli tuşu tanıyın.',
        labels: [keySpec.$1],
        unit: 'Tek Nota · C4–B5',
      ),
    );
  } else if (mode == 1) {
    // Interval between 2 highlighted piano keys
    final root = k % 12; // 0..11 => root + 12 <= 23
    final iv = _pianoIntervals[(k ~/ 12) % _pianoIntervals.length];
    final k1 = _pianoKeys24[root];
    final k2 = _pianoKeys24[root + iv.$1];
    final askSemi = (k ~/ 144).isOdd;
    if (askSemi) {
      return AdvancedItem(
        'Piyanoda turkuaz kök (${k1.$1}) ile altın üst tuş (${k2.$1}) arasında kaç YARIM SES (semitone) vardır?',
        '${iv.$1} yarım ses',
        _intWrong(iv.$1, i, suffix: ' yarım ses', minVal: 1, maxVal: 12, deltas: const [1, -1, 2, -2, 3, -3]),
        '${k1.$1} tuşundan ${k2.$1} tuşuna her beyaz ve siyah tuş 1 yarım ses sayılarak toplam ${iv.$1} yarım ses (${iv.$2}) bulunur.',
        visual: QuestionVisual(
          kind: VisualKind.piano,
          title: 'Klavyede Yarım Ses Mesafesi',
          summary: 'Turkuaz kök notadan altın notaya yarım ses sayın.',
          labels: [k1.$1, k2.$1],
          unit: 'Kök: ${k1.$1}',
        ),
      );
    }
    return AdvancedItem(
      'Piyano klavyesinde turkuaz (${k1.$1}) ve altın (${k2.$1}) tuşları arasındaki müzik aralığı hangisidir?',
      iv.$2,
      _pickDistinct([for (final x in _pianoIntervals) x.$2], iv.$2, i + 7),
      '${k1.$1} ile ${k2.$1} arasında ${iv.$1} yarım ses olduğundan bu aralık ${iv.$2} olarak adlandırılır.',
      visual: QuestionVisual(
        kind: VisualKind.piano,
        title: 'Piyano Aralık Stüdyosu',
        summary: 'İki basılı tuş arasındaki armonik aralığı belirleyin.',
        labels: [k1.$1, k2.$1],
        unit: 'Aralık · 2 Tuş',
      ),
    );
  } else if (mode == 2) {
    // Chord identification on piano (all 12 roots × 8 chord shapes)
    final root = k % 12;
    final shape = _pianoChordShapes[(k ~/ 12) % _pianoChordShapes.length];
    final keys = [for (final st in shape.$3) _pianoKeys24[root + st].$1];
    final askFullName = (k ~/ 96).isEven;
    if (askFullName) {
      final correct = '${_rootShortTr[root]} ${shape.$1}';
      final pool = [
        for (var r = 0; r < 12; r++)
          for (final sh in _pianoChordShapes) '${_rootShortTr[r]} ${sh.$1}',
      ];
      return AdvancedItem(
        'Piyano klavyesinde turkuaz kök (${_pianoKeys24[root].$1}) üzerine kurulan bu akor hangisidir?',
        correct,
        _pickDistinct(pool, correct, i + 11),
        'Kök ${_rootShortTr[root]} (${_pianoKeys24[root].$1}) ve ${shape.$2} yarım ses adımları birleşerek $correct akorunu oluşturur.',
        visual: QuestionVisual(
          kind: VisualKind.piano,
          title: 'Piyano Akor Stüdyosu',
          summary: 'Turkuaz tuş akorun kök sesini gösterir.',
          labels: keys,
          unit: '${keys.length} Sesli Akor',
        ),
      );
    }
    return AdvancedItem(
      'Klavyede turkuaz kök üzerine basılan (${keys.join(' – ')}) akorunun yapısı (kalitesi) hangisidir?',
      shape.$2,
      _pickDistinct([for (final sh in _pianoChordShapes) sh.$2], shape.$2, i + 13),
      'Kök sesten itibaren yarım ses adımları ${shape.$3.join('–')} olduğundan akor yapısı ${shape.$2} olur.',
      visual: QuestionVisual(
        kind: VisualKind.piano,
        title: 'Akor Yapısı (Kalite) Analizi',
        summary: 'Basılı tuşların yarım ses formülünü belirleyin.',
        labels: keys,
        unit: 'Kök: ${_pianoKeys24[root].$1}',
      ),
    );
  } else {
    // Scale / Triad / Black-key count analysis
    final root = k % 12;
    final isMajorScale = (k ~/ 12).isEven;
    final steps = isMajorScale ? const [0, 2, 4, 5, 7, 9, 11, 12] : const [0, 2, 3, 5, 7, 8, 10, 12];
    final keys = [for (final st in steps) _pianoKeys24[root + st].$1];
    final blackCount = keys.where((c) => c.contains('#')).length;
    final askCount = (k ~/ 24).isOdd;
    final scaleName = '${_rootShortTr[root]} ${isMajorScale ? 'Majör' : 'Doğal Minör'} Dizisi';
    if (askCount) {
      return AdvancedItem(
        'Klavyede vurgulanan $scaleName içinde kaç adet SİYAH TUŞ (diyez/bemol) basılıdır?',
        '$blackCount siyah tuş',
        _intWrong(blackCount, i, suffix: ' siyah tuş', minVal: 0, maxVal: 6, deltas: const [1, -1, 2, -2, 3]),
        '$scaleName notaları: ${keys.join(', ')}. Bunların $blackCount tanesi siyah tuştur.',
        visual: QuestionVisual(
          kind: VisualKind.piano,
          title: 'Dizi & Siyah Tuş Analizi',
          summary: 'Vurgulanan dizideki siyah tuş sayısını sayın.',
          labels: keys,
          unit: isMajorScale ? 'Majör Dizi (T-T-Y-T-T-T-Y)' : 'Minör Dizi (T-Y-T-T-Y-T-T)',
        ),
      );
    }
    final pool = [
      for (var r = 0; r < 12; r++) '${_rootShortTr[r]} Majör Dizisi',
      for (var r = 0; r < 12; r++) '${_rootShortTr[r]} Doğal Minör Dizisi',
    ];
    return AdvancedItem(
      'Piyano klavyesinde turkuaz kök (${_pianoKeys24[root].$1}) ile başlayan bu 8 notalık dizi hangisidir?',
      scaleName,
      _pickDistinct(pool, scaleName, i + 17),
      '${isMajorScale ? 'Tam-Tam-Yarım-Tam-Tam-Tam-Yarım' : 'Tam-Yarım-Tam-Tam-Yarım-Tam-Tam'} adımları $scaleName oluşturur.',
      visual: QuestionVisual(
        kind: VisualKind.piano,
        title: 'Piyano Dizi (Gam) Stüdyosu',
        summary: 'Turkuaz kök notadan başlayan gamı tanıyın.',
        labels: keys,
        unit: 'Kök: ${_pianoKeys24[root].$1}',
      ),
    );
  }
}

final List<AdvancedFamily> visualNewEngines25kFamilies = [
  AdvancedFamily(
    key: 's100_circuit_logic',
    title: 'Sayısal Mantık Kapıları & 2 Kademeli Devreler',
    topic: Topic.computing,
    level: StudyLevel.lise,
    count: 4000,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.circuit,
    bloom: BloomLevel.analiz,
    sourceLabel: 'Bilgili 3.21 · Yeni Görsel Motorlar',
    build: _buildCircuitLogic,
  ),
  AdvancedFamily(
    key: 's100_circuit_ohm',
    title: 'Seri & Paralel Elektrik Devreleri (Ohm Yasası)',
    topic: Topic.physics,
    level: StudyLevel.lise,
    count: 3000,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.circuit,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.21 · Yeni Görsel Motorlar',
    build: _buildCircuitOhm,
  ),
  AdvancedFamily(
    key: 's100_venn_sets',
    title: 'Venn Şeması, Küme İşlemleri & Olasılık',
    topic: Topic.mathematics,
    level: StudyLevel.lise,
    count: 5000,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.venn,
    bloom: BloomLevel.analiz,
    sourceLabel: 'Bilgili 3.21 · Yeni Görsel Motorlar',
    build: _buildVennSets,
  ),
  AdvancedFamily(
    key: 's100_compass_nav',
    title: 'Pusula, Rota, Azimut & İngilizce Yön Navigasyonu',
    topic: Topic.geography,
    level: StudyLevel.lise,
    count: 4500,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.compass,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.21 · Yeni Görsel Motorlar',
    build: _buildCompassNav,
  ),
  AdvancedFamily(
    key: 's100_color_optik',
    title: 'Renk Karışımı, RGB Hex & Görünür Işık Spektrumu',
    topic: Topic.art,
    level: StudyLevel.lise,
    count: 4500,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.colorLab,
    bloom: BloomLevel.anlama,
    sourceLabel: 'Bilgili 3.21 · Yeni Görsel Motorlar',
    build: _buildColorLab,
  ),
  AdvancedFamily(
    key: 's100_piano_studio',
    title: '2 Oktav Piyano Klavyesi, Aralık, Akor & Gamlar',
    topic: Topic.music,
    level: StudyLevel.lise,
    count: 4000,
    difficulty: Difficulty.medium,
    visualKind: VisualKind.piano,
    bloom: BloomLevel.uygulama,
    sourceLabel: 'Bilgili 3.21 · Yeni Görsel Motorlar',
    build: _buildPianoStudio,
  ),
];
