// Lise kimya metin aileleri: atomun yapısından elektrokimyaya 20 kazanım.
// Her aile 25 × 20 × 10 koordinatla 5.000 ayrı soru kökü üretir; veriler
// gerçek maddelerden seçilir, anahtarlar koordinatlardan kesin hesaplanır.
import 'ortak.dart';

const _altRakam = '₀₁₂₃₄₅₆₇₈₉';
const _ustRakam = '⁰¹²³⁴⁵⁶⁷⁸⁹';

/// Bu dosyada kullanılan atom kütleleri (g/mol); her kökte ayrıca yazılır.
const _atomKutlesi = <String, num>{
  'H': 1, 'He': 4, 'Li': 7, 'C': 12, 'N': 14, 'O': 16, 'F': 19, 'Ne': 20,
  'Na': 23, 'Mg': 24, 'Al': 27, 'Si': 28, 'P': 31, 'S': 32, 'Cl': 35.5,
  'Ar': 40, 'K': 39, 'Ca': 40, 'Ti': 48, 'Cr': 52, 'Mn': 55, 'Fe': 56,
  'Ni': 59, 'Cu': 64, 'Zn': 65, 'Br': 80, 'Kr': 84, 'Sr': 88, 'Ag': 108,
  'Sn': 119, 'I': 127, 'Xe': 131, 'Ba': 137, 'Au': 197, 'Pb': 207,
};

final _atomOnbellek = <String, Map<String, int>>{};

/// Formüldeki atom sayıları. Alt simgeleri ve parantezleri çözer; yük ve hâl
/// simgelerini atlar.
Map<String, int> _atomlar(String f) => _atomOnbellek[f] ??= () {
  final yigin = <Map<String, int>>[{}];
  var i = 0;
  int carpan() {
    var n = 0, var_ = false;
    while (i < f.length && _altRakam.contains(f[i])) {
      n = n * 10 + _altRakam.indexOf(f[i]);
      var_ = true;
      i++;
    }
    return var_ ? n : 1;
  }

  bool kucuk(int u) => u >= 97 && u <= 122;
  while (i < f.length) {
    final u = f.codeUnitAt(i);
    if (f[i] == '(') {
      yigin.add({});
      i++;
    } else if (f[i] == ')') {
      i++;
      final ic = yigin.removeLast();
      final k = carpan();
      ic.forEach((e, n) => yigin.last[e] = (yigin.last[e] ?? 0) + n * k);
    } else if (u >= 65 && u <= 90) {
      var s = f[i];
      i++;
      while (i < f.length && kucuk(f.codeUnitAt(i))) {
        s += f[i];
        i++;
      }
      final k = carpan();
      yigin.last[s] = (yigin.last[s] ?? 0) + k;
    } else {
      i++;
    }
  }
  return yigin.first;
}();

/// Mol kütlesi (g/mol).
num _mk(String f) {
  num m = 0;
  _atomlar(f).forEach((e, n) {
    final k = _atomKutlesi[e];
    if (k == null) throw StateError('Atom kütlesi yok: $e ($f)');
    m += k * n;
  });
  return m;
}

/// Verilen formüllerde geçen elementlerin atom kütleleri: “H: 1, O: 16”.
String _kut(List<String> formuller, {String haric = ''}) {
  final gorulen = <String>[];
  for (final f in formuller) {
    for (final e in _atomlar(f).keys) {
      if (e != haric && !gorulen.contains(e)) gorulen.add(e);
    }
  }
  return gorulen.map((e) => '$e: ${tr(_atomKutlesi[e]!)}').join(', ');
}

num _on(int d) {
  num p = 1;
  for (var j = 0; j < d; j++) {
    p *= 10;
  }
  return p;
}

/// Yuvarlayarak yazar; eksi işaretini “−” yapar.
String _yz(num x, [int d = 2]) => tr(x, d).replaceFirst('-', '−');

/// Kökte ve anahtarda kullanılan veriyi yazar; [d] basamakta kesin değilse
/// hata verir. Böylece yuvarlanmış bir sayı fark edilmeden köke giremez.
String _t(num x, [int d = 2]) {
  final y = x * _on(d);
  if ((y - y.roundToDouble()).abs() > 1e-6 * (1 + y.abs())) {
    throw StateError('Kesin değil: $x ($d basamak)');
  }
  return _yz(x, d);
}

String _isaretli(num x, [int d = 2]) => x > 0 ? '+${_t(x, d)}' : _t(x, d);

String _ust(int n) =>
    '${n < 0 ? '⁻' : ''}${'${n.abs()}'.split('').map((r) => _ustRakam[int.parse(r)]).join()}';

String _alt(int n) => '$n'.split('').map((r) => _altRakam[int.parse(r)]).join();

/// İyon yükü üst simgesi: 2 → “²⁺”, −1 → “⁻”.
String _yuk(int q) =>
    q == 0 ? '' : '${q.abs() == 1 ? '' : _ust(q.abs())}${q > 0 ? '⁺' : '⁻'}';

/// İyon yükünün yazıyla gösterimi: 2 → “2+”, −1 → “1−”.
String _yukYazi(int q) => '${q.abs()}${q > 0 ? '+' : '−'}';

/// m·10ᵉ biçiminde bilimsel gösterim; m, [1, 10) aralığına getirilir.
String _bilimsel(num m, int e) {
  var x = m.toDouble(), us = e;
  while (x >= 10 - 1e-9) {
    x /= 10;
    us++;
  }
  while (x < 1 - 1e-9) {
    x *= 10;
    us--;
  }
  final govde = _t(x, 3);
  return govde == '1' ? '10${_ust(us)}' : '$govde·10${_ust(us)}';
}

/// Sayısal yanıtlı soru. Doğru yanıt kesin yazılır; çeldiriciler tipik
/// hatalardan gelir, yetmezse komşu değerlerle tamamlanır.
AdvancedItem _say(
  String kok,
  num dogru,
  Iterable<num> adaylar,
  String aciklama, {
  String birim = '',
  String on = '',
  int basamak = 2,
  bool arti = true,
  bool isaret = false,
}) {
  String yaz(num x, {bool kesin = false}) {
    var s = kesin ? _t(x, basamak) : _yz(x, basamak);
    if (isaret && x > 0 && s != '0') s = '+$s';
    return birimli('$on$s', birim);
  }

  final d = dogru.toDouble(), m = d.abs();
  final tam = (d - d.roundToDouble()).abs() < 1e-9;
  final adim = tam
      ? (m >= 200 ? 10.0 : (m >= 40 ? 5.0 : 1.0))
      : (m >= 20
            ? 1.0
            : (m >= 2 ? 0.5 : (m >= 0.3 ? 0.1 : (m >= 0.03 ? 0.01 : 0.001))));
  final esik = 0.5 / _on(basamak);
  final havuz = <num>[
    ...adaylar,
    d + adim,
    d - adim,
    d + 2 * adim,
    d - 2 * adim,
    d + 3 * adim,
    d + 4 * adim,
    d + 5 * adim,
  ];
  return secenekli(
    kok,
    yaz(dogru, kesin: true),
    havuz.where((x) => x.isFinite && (!arti || x >= esik)).map(yaz),
    aciklama,
  );
}

/// Oranı en çok iki ondalıkla yazılabiliyorsa ondalık, değilse kesir yazar.
String _oran(int n, int d) {
  if (d < 0) return _oran(-n, -d);
  final g = n.gcd(d);
  final p = n ~/ g, q = d ~/ g;
  return 100 % q == 0 ? _yz(p / q) : kesir(p, q);
}

/// Oran yanıtlı soru; adaylar (pay, payda) ikilileridir.
AdvancedItem _oranli(
  String kok,
  int n,
  int d,
  Iterable<(int, int)> adaylar,
  String aciklama,
) => secenekli(
  kok,
  _oran(n, d),
  [
    ...adaylar,
    (2 * n, d),
    (n, 2 * d),
    (3 * n, d),
    (n, 3 * d),
    (n + d, d),
    (5 * n, d),
    (n, 5 * d),
  ].where((x) => x.$1 > 0 && x.$2 > 0).map((x) => _oran(x.$1, x.$2)),
  aciklama,
);

// Geçici yer tutucu; dosya tamamlanınca kaldırılır.
AdvancedFamily _gecici(int n) => lmAile(
  'kim_gecici_$n',
  'Geçici yer tutucu aile $n',
  Topic.chemistry,
  Difficulty.easy,
  BloomLevel.uygulama,
  (a, b, c) => sayisal(
    'Geçici $n numaralı ailede $a, $b ve $c sayılarının toplamının ${n + 2} fazlası kaçtır? (yer tutucu)',
    a + b + c + n + 2,
    [a + b + c, a + b + c + n + 40],
    'Toplam ${a + b + c + n + 2} olur.',
  ),
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 1. Atomun temel tanecikleri
// ---------------------------------------------------------------------------

final _f01 = lmAile(
  'kim_atom',
  'Atom ve iyonlarda proton, nötron, elektron sayısı',
  Topic.chemistry,
  Difficulty.easy,
  BloomLevel.anlama,
  (a, b, c) {
    final z = 9 + a + 25 * (c ~/ 5); // 9 … 58
    final n = z + z * z ~/ 140 + b % 5; // kararlılık kuşağına yakın nötron sayısı
    final q = const [1, 2, 3, -1, -2][c % 5];
    final kn = z + n, e = z - q;
    final x = 'X${_yuk(q)}';
    final yuk = _yukYazi(q);
    final eIslem = q > 0 ? '$z − $q = $e' : '$z + ${-q} = $e';
    final zIslem = q > 0 ? '$e + $q = $z' : '$e − ${-q} = $z';
    switch (b ~/ 5) {
      case 0:
        return sayisal(
          'Kütle numarası $kn olan $x iyonunun çekirdeğinde $n nötron bulunmaktadır. '
          'Bu iyonun elektron sayısı kaçtır?',
          e,
          [z, z + q, kn - q, n],
          'Proton sayısı $kn − $n = $z olur. İyonun yükü $yuk olduğundan '
          'elektron sayısı $eIslem bulunur.',
          positive: true,
        );
      case 1:
        return sayisal(
          '$x iyonunda $e elektron ve $n nötron bulunmaktadır. '
          'X atomunun kütle numarası kaçtır?',
          kn,
          [e + n, e - q + n, z, kn + q + q],
          'İyonun yükü $yuk olduğundan proton sayısı $zIslem olur. '
          'Kütle numarası $z + $n = $kn bulunur.',
          positive: true,
        );
      case 2:
        return sayisal(
          'Kütle numarası $kn olan $x iyonunda $e elektron bulunmaktadır. '
          'X atomunun çekirdeğindeki nötron sayısı kaçtır?',
          n,
          [kn - e, kn - e + q, z, e],
          'İyonun yükü $yuk olduğundan proton sayısı $zIslem olur. '
          'Nötron sayısı $kn − $z = $n bulunur.',
          positive: true,
        );
      default:
        return sayisal(
          'Atom numarası $z, kütle numarası $kn olan X atomundan oluşan $x '
          'iyonunda proton, nötron ve elektron sayılarının toplamı kaçtır?',
          kn + e,
          [kn + z, kn + z + q, kn + n, z + e],
          'Proton sayısı $z, nötron sayısı $kn − $z = $n, elektron sayısı '
          '$eIslem olur. Toplam $z + $n + $e = ${kn + e} bulunur.',
          positive: true,
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 2. İzotoplar ve ortalama atom kütlesi
// ---------------------------------------------------------------------------

final _f02 = lmAile(
  'kim_izotop',
  'İzotop bolluğu ve ortalama atom kütlesi',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final m1 = 10 + 3 * a; // hafif izotopun kütle numarası
    final fark = 1 + c ~/ 3;
    final m2 = m1 + fark;
    final p = 8 + 4 * b, r = 100 - p; // hafif ve ağır izotop yüzdeleri
    final ort = m1 + fark * r / 100;
    const giris =
        'Doğada yalnızca iki izotopu bulunan X elementinin izotoplarının '
        'kütle numaraları';
    switch (c % 3) {
      case 0:
        return _say(
          '$giris $m1 ve $m2 olarak verilmiştir. Kütle numarası $m1 olan '
          'izotopun doğadaki bolluğu %$p olduğuna göre X elementinin ortalama '
          'atom kütlesi kaçtır?',
          ort,
          [(m1 + m2) / 2, m1 + fark * p / 100, m1 * p / 100 + m2, m2 * r / 100],
          'Ortalama atom kütlesi ($m1·$p + $m2·$r) / 100 = ${_t(ort)} olur.',
        );
      case 1:
        return _say(
          '$giris $m1 ve $m2 olarak verilmiştir. Elementin ortalama atom kütlesi '
          '${_t(ort)} olduğuna göre kütle numarası $m2 olan izotopun doğadaki '
          'bolluk yüzdesi kaçtır?',
          r,
          [p, 50, r / 2, 100 - r / 2],
          on: '%',
          'Ağır izotopun kesri x olsun: $m1·(1 − x) + $m2·x = ${_t(ort)} '
          'eşitliğinden x = ${_t(ort - m1)} / $fark = ${_t(r / 100)} bulunur; '
          'bolluk %$r olur.',
        );
      default:
        return sayisal(
          'Doğada yalnızca iki izotopu bulunan X elementinin ortalama atom '
          'kütlesi ${_t(ort)} olarak hesaplanmıştır. Kütle numarası $m1 olan '
          'izotopun doğadaki bolluğu %$p olduğuna göre diğer izotopun kütle '
          'numarası kaçtır?',
          m2,
          [m2 + 1, m2 - 1, m1 + 2 * fark, m2 + 2],
          'Diğer izotopun bolluğu %$r olur. $m1·$p + m·$r = ${_t(ort)}·100 '
          'eşitliğinden m = ${_t(ort * 100 - m1 * p)} / $r = $m2 bulunur.',
          positive: true,
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 3. Elektron dizilimi, değerlik elektronu, periyot ve grup
// ---------------------------------------------------------------------------

// (baş kuantum sayısı, tür, orbital sayısı) — Z ≤ 38 için dolma sırası.
const _altKabuk = [
  (1, 's', 1), (2, 's', 1), (2, 'p', 3), (3, 's', 1), (3, 'p', 3),
  (4, 's', 1), (3, 'd', 5), (4, 'p', 3), (5, 's', 1),
];

// B, C, …, Ca; Sc; Ga, …, Sr. Dizilimi kural dışı olan element yoktur.
const _dizilimZ = [
  5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
  31, 32, 33, 34, 35, 36, 37, 38,
];

class _Dizilim {
  _Dizilim(this.z) {
    var kalan = z;
    final parca = <String>[];
    for (final (n, tur, orb) in _altKabuk) {
      if (kalan == 0) break;
      final e = kalan < 2 * orb ? kalan : 2 * orb;
      kalan -= e;
      parca.add('$n$tur${_ust(e)}');
      son = '$n$tur';
      katman[n - 1] += e;
      if (tur == 's') s += e;
      if (tur == 'p') p += e;
      tamDolu += e <= orb ? 0 : e - orb;
      dolu += e <= orb ? e : orb;
      if (n > periyot) periyot = n;
    }
    yazim = parca.join(' ');
    final dis = katman[periyot - 1];
    degerlik = z >= 21 && z <= 30 ? z - 18 : dis;
    grup = z >= 21 && z <= 30 ? z - 18 : (dis <= 2 ? dis : dis + 10);
    onceki = katman[periyot - 2];
    alt = z + (z <= 12 ? 8 : 18);
  }
  final int z;
  final katman = [0, 0, 0, 0, 0];
  var periyot = 0, s = 0, p = 0, tamDolu = 0, dolu = 0;
  late final int degerlik, grup, onceki, alt;
  late final String yazim;
  var son = '';
  String get katmanYazim => katman.where((e) => e > 0).join(', ');
}

final _f03 = lmAile(
  'kim_dizilim',
  'Elektron dizilimi, değerlik elektronu, periyot ve grup',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.anlama,
  (a, b, c) {
    final d = _Dizilim(_dizilimZ[a]);
    final z = d.z, alt = b % 5;
    final String veri, bulus;
    switch (b ~/ 5) {
      case 0:
        final q = const [1, 2, 3, -1, -2][alt];
        final e = z - q;
        veri = 'X${_yuk(q)} iyonunda $e elektron bulunmaktadır.';
        bulus = 'İyonun yükü ${_yukYazi(q)} olduğundan atom numarası '
            '${q > 0 ? '$e + $q' : '$e − ${-q}'} = $z olur.';
      case 1:
        final n = z + z * z ~/ 140 + alt;
        veri = 'Kütle numarası ${z + n} olan nötr X atomunun çekirdeğinde $n '
            'nötron bulunmaktadır.';
        bulus = 'Atom numarası ${z + n} − $n = $z olur.';
      case 2:
        final f = z * z ~/ 140 + 1 + alt;
        veri = 'Nötr X atomunun kütle numarası ${2 * z + f} olup nötron sayısı '
            'proton sayısından $f fazladır.';
        bulus = 'Proton sayısı p ise p + (p + $f) = ${2 * z + f} eşitliğinden '
            'atom numarası $z olur.';
      default:
        final q = const [1, 2, 3, -1, -2][alt];
        final e = z - q;
        veri = 'X${_yuk(q)} iyonu ile atom numarası $e olan nötr Y atomunun '
            'elektron sayıları eşittir.';
        bulus = 'İyonda $e elektron vardır; yük ${_yukYazi(q)} olduğundan atom '
            'numarası ${q > 0 ? '$e + $q' : '$e − ${-q}'} = $z olur.';
    }
    final dizi = '$bulus Temel hâl dizilimi: ${d.yazim}.';
    AdvancedItem tamSayi(String soru, int yanit, List<int> yanlis, String son) =>
        sayisal('$veri $soru', yanit, yanlis, '$dizi $son', positive: true);
    switch (c) {
      case 0:
        return tamSayi(
          'Buna göre X elementi periyodik sistemin kaçıncı periyodunda yer alır?',
          d.periyot,
          [d.degerlik, d.periyot + 1, d.periyot - 1, d.grup],
          'Elektron bulunduran en yüksek katman ${d.periyot} olduğundan element '
              '${d.periyot}. periyottadır.',
        );
      case 1:
        return tamSayi(
          'Buna göre X elementinin periyodik sistemdeki grup numarası '
          '(IUPAC, 1–18 arası) kaçtır?',
          d.grup,
          [d.degerlik, d.grup + 1, d.grup - 1, d.periyot, d.degerlik + 8],
          'Değerlik elektron sayısı ${d.degerlik} olduğundan element '
              '${d.grup}. grupta yer alır.',
        );
      case 2:
        return tamSayi(
          'Buna göre X atomunun değerlik elektron sayısı kaçtır?',
          d.degerlik,
          [d.periyot, d.grup, d.degerlik + 1, d.onceki, d.degerlik - 1],
          'Değerlik elektron sayısı ${d.degerlik} bulunur.',
        );
      case 3:
        return tamSayi(
          'Buna göre temel hâldeki X atomunun tam dolu orbital sayısı kaçtır?',
          d.tamDolu,
          [d.dolu, d.tamDolu + 1, d.tamDolu - 1, d.yazim.split(' ').length],
          'İki elektron taşıyan orbital sayısı ${d.tamDolu} olur.',
        );
      case 4:
        return tamSayi(
          'Buna göre temel hâldeki X atomunda elektron bulunduran orbital '
          'sayısı kaçtır?',
          d.dolu,
          [d.tamDolu, d.yazim.split(' ').length, d.dolu + 1, d.dolu - 1],
          'En az bir elektron taşıyan orbital sayısı ${d.dolu} olur.',
        );
      case 5:
        return tamSayi(
          'Buna göre temel hâldeki X atomunun s orbitallerinde toplam kaç '
          'elektron bulunur?',
          d.s,
          [d.p, d.s + 2, d.s - 2, d.s + 1, d.periyot],
          's orbitallerindeki elektronların toplamı ${d.s} olur.',
        );
      case 6:
        return tamSayi(
          'Buna göre temel hâldeki X atomunun p orbitallerinde toplam kaç '
          'elektron bulunur?',
          d.p,
          [d.s, d.p + 6, d.p - 6, d.degerlik, d.p + 1],
          'p orbitallerindeki elektronların toplamı ${d.p} olur.',
        );
      case 7:
        return tamSayi(
          'Buna göre X ile aynı grupta ve bir sonraki periyotta yer alan '
          'elementin atom numarası kaçtır?',
          d.alt,
          [z + 8, z + 18, z + 10, z + 2, z + 32],
          'Element ${d.periyot}. periyot ${d.grup}. gruptadır. Bir alt periyotta '
              'aynı gruba ${d.alt - z} element sonra gelinir: $z + '
              '${d.alt - z} = ${d.alt}.',
        );
      case 8:
        return tamSayi(
          'Buna göre temel hâldeki X atomunun katman elektron diziliminde, en '
          'dış katmandan bir önceki katmanda kaç elektron bulunur?',
          d.onceki,
          [d.degerlik, 8, 18, 2, d.katman[d.periyot - 1]],
          'Katman dizilimi ${d.katmanYazim} olduğundan aranan sayı '
              '${d.onceki} olur.',
        );
      default:
        final sira = [for (final (n, tur, _) in _altKabuk) '$n$tur'];
        final yer = sira.indexOf(d.son);
        return secenekli(
          '$veri Buna göre temel hâldeki X atomunun elektron dizilimi hangi '
          'orbital türüyle sona erer?',
          d.son,
          [
            sira[yer - 1],
            if (yer + 1 < sira.length) sira[yer + 1],
            sira[yer - 2],
            if (yer + 2 < sira.length) sira[yer + 2],
          ],
          '$dizi Dizilimin son terimi ${d.son} orbitalidir.',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

final lmKimya = <AdvancedFamily>[
  _f01, _f02, _f03,
  for (var n = 4; n <= 20; n++) _gecici(n),
];
