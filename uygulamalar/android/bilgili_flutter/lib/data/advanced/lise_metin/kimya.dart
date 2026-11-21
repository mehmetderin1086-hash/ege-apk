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
  final govde = _t(x, 4);
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
          [(m1 + m2) / 2, m1 + fark * p / 100, m1 + fark * r / 200, m2 - fark * p / 200],
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
        final sira = [for (final (n, tur, _) in _altKabuk) '$n$tur', '4d', '5p'];
        final yer = sira.indexOf(d.son);
        return secenekli(
          '$veri Buna göre temel hâldeki X atomunun elektron dizilimi hangi '
          'orbital türüyle sona erer?',
          d.son,
          [
            sira[yer - 1],
            sira[yer + 1],
            sira[yer - 2],
            sira[yer + 2],
          ],
          '$dizi Dizilimin son terimi ${d.son} orbitalidir.',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 4. Mol, kütle ve tanecik sayısı
// ---------------------------------------------------------------------------

const _molekuller = [
  ('H₂O', 'su'), ('CO₂', 'karbon dioksit'), ('NH₃', 'amonyak'),
  ('CH₄', 'metan'), ('O₂', 'oksijen gazı'), ('N₂', 'azot gazı'),
  ('SO₂', 'kükürt dioksit'), ('SO₃', 'kükürt trioksit'), ('C₂H₆', 'etan'),
  ('C₃H₈', 'propan'), ('C₂H₄', 'eten'), ('C₂H₂', 'asetilen'),
  ('C₆H₁₂O₆', 'glikoz'), ('C₂H₅OH', 'etanol'), ('HCl', 'hidrojen klorür'),
  ('NO₂', 'azot dioksit'), ('CO', 'karbon monoksit'),
  ('H₂S', 'hidrojen sülfür'), ('H₂SO₄', 'sülfürik asit'),
  ('HNO₃', 'nitrik asit'), ('CH₃OH', 'metanol'), ('C₄H₁₀', 'bütan'),
  ('N₂O₅', 'diazot pentaoksit'), ('C₆H₆', 'benzen'),
  ('CH₃COOH', 'asetik asit'),
];

final _f04 = lmAile(
  'kim_mol',
  'Mol, kütle ve tanecik sayısı dönüşümleri',
  Topic.chemistry,
  Difficulty.easy,
  BloomLevel.uygulama,
  (a, b, c) {
    final (f, ad) = _molekuller[a];
    final mk = _mk(f);
    final atomlar = _atomlar(f);
    final atom = atomlar.values.fold(0, (x, y) => x + y);
    num yalin = 0; // alt simgeleri yok sayan hatalı mol kütlesi
    for (final e in atomlar.keys) {
      yalin += _atomKutlesi[e]!;
    }
    final t = b + 1 + 20 * (c ~/ 5);
    final n = t / 10, m = mk * t / 10;
    final madde = '$ad ($f)';
    final kut = _kut([f]);
    final mkYazi = 'Mol kütlesi ${_t(mk)} g/mol olur.';
    switch (c % 5) {
      case 0:
        return _say(
          'Kütlesi ${_t(m)} gram olan $madde örneği kaç moldür? ($kut)',
          n,
          [n * atom, mk / m, m / yalin, n / atom, n * 10],
          '$mkYazi n = ${_t(m)} / ${_t(mk)} = ${_t(n)} mol bulunur.',
          birim: 'mol',
        );
      case 1:
        return _say(
          '${_t(n)} mol $madde kaç gramdır? ($kut)',
          m,
          [n * yalin, mk / n, m / atom, m * atom, mk + n],
          '$mkYazi m = ${_t(n)}·${_t(mk)} = ${_t(m)} gram bulunur.',
          birim: 'g',
        );
      case 2:
        return _say(
          'Kütlesi ${_t(m)} gram olan $madde örneğinde toplam kaç mol atom '
          'bulunur? ($kut)',
          n * atom,
          [n, n * atomlar.length, m / yalin, n * atom * 2, n * (atom + 1)],
          '$mkYazi Örnek ${_t(m)} / ${_t(mk)} = ${_t(n)} moldür. Bir molekülde '
          '$atom atom bulunduğundan toplam ${_t(n)}·$atom = ${_t(n * atom)} '
          'mol atom vardır.',
          birim: 'mol',
        );
      case 3:
        return _say(
          '${_bilimsel(6.02 * t, 22)} tane molekül içeren $madde örneği kaç '
          'gramdır? ($kut; Avogadro sayısı N_A = 6,02·10²³)',
          m,
          [n * yalin, m * atom, m / atom, n * 10 + mk, mk],
          'Mol sayısı ${_bilimsel(6.02 * t, 22)} / 6,02·10²³ = ${_t(n)} olur. '
          '$mkYazi m = ${_t(n)}·${_t(mk)} = ${_t(m)} gram bulunur.',
          birim: 'g',
        );
      default:
        return _say(
          'Toplam ${_t(n * atom)} mol atom içeren $madde örneği kaç gramdır? '
          '($kut)',
          m,
          [n * atom * mk, n * atom * yalin, m / atom, n * yalin],
          'Bir molekülde $atom atom bulunduğundan örnek ${_t(n * atom)} / $atom '
          '= ${_t(n)} moldür. $mkYazi m = ${_t(n)}·${_t(mk)} = ${_t(m)} gram '
          'bulunur.',
          birim: 'g',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 5. Mol kütlesi ve kütlece yüzde bileşim
// ---------------------------------------------------------------------------

// (bileşik, ad, sorulan element): kütlece yüzdesi en çok iki ondalıklıdır.
const _yuzdeCiftleri = [
  ('CaCO₃', 'kalsiyum karbonat', 'Ca'), ('CaCO₃', 'kalsiyum karbonat', 'O'),
  ('SO₃', 'kükürt trioksit', 'S'), ('CH₄', 'metan', 'C'),
  ('NaOH', 'sodyum hidroksit', 'Na'), ('MgO', 'magnezyum oksit', 'Mg'),
  ('Fe₂O₃', 'demir(III) oksit', 'Fe'), ('CuO', 'bakır(II) oksit', 'Cu'),
  ('C₂H₆', 'etan', 'C'), ('NH₄NO₃', 'amonyum nitrat', 'N'),
  ('CuSO₄', 'bakır(II) sülfat', 'Cu'), ('CuSO₄', 'bakır(II) sülfat', 'S'),
  ('C₃H₄', 'propin', 'C'), ('CaBr₂', 'kalsiyum bromür', 'Br'),
  ('KHCO₃', 'potasyum bikarbonat', 'K'), ('C₆H₁₂O₆', 'glikoz', 'C'),
  ('HF', 'hidrojen florür', 'F'), ('Fe₂(SO₄)₃', 'demir(III) sülfat', 'Fe'),
  ('Fe₂(SO₄)₃', 'demir(III) sülfat', 'S'), ('C₇H₁₆', 'heptan', 'C'),
  ('TiO₂', 'titanyum dioksit', 'Ti'), ('Cu₂S', 'bakır(I) sülfür', 'Cu'),
  ('CaC₂', 'kalsiyum karbür', 'Ca'), ('CH₃OH', 'metanol', 'O'),
  ('Mg₃N₂', 'magnezyum nitrür', 'Mg'),
];

final _f05 = lmAile(
  'kim_yuzde_bilesim',
  'Mol kütlesi ve kütlece yüzde bileşim',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (f, ad, el) = _yuzdeCiftleri[a];
    final mk = _mk(f);
    final atomlar = _atomlar(f);
    final adet = atomlar[el]!;
    final atomSay = atomlar.values.fold(0, (x, y) => x + y);
    final ak = _atomKutlesi[el]!;
    final pay = adet * ak, kalan = mk - pay; // 1 moldeki element ve diğerleri
    final yuzde = 100 * pay / mk;
    final t = b + 1 + 20 * (c ~/ 5);
    final m = mk * t / 10, g = pay * t / 10, n = t / 10;
    final madde = '$ad ($f)';
    final kut = _kut([f]);
    final payYazi = adet == 1 ? _t(ak) : '$adet·${_t(ak)} = ${_t(pay)}';
    final molYazi =
        'Bir mol bileşik ${_t(mk)} gramdır ve $payYazi gram $el içerir.';
    switch (c % 5) {
      case 0:
        return _say(
          '${_t(m)} gram $madde bileşiğinde kaç gram $el elementi bulunur? '
          '($kut)',
          g,
          [m - g, m * ak / mk, m * adet / atomSay, g / 2, (m - g) / 2],
          '$molYazi ${_t(m)} gram bileşikte ${_t(m)}·${_t(pay)} / ${_t(mk)} = '
          '${_t(g)} gram $el bulunur.',
          birim: 'g',
        );
      case 1:
        return _say(
          '${_t(g)} gram $el elementi içeren $madde örneğinin kütlesi kaç '
          'gramdır? ($kut)',
          m,
          [g * kalan / pay, g * mk / ak, g + kalan, g * atomSay / adet, m - g],
          '$molYazi Örneğin kütlesi ${_t(g)}·${_t(mk)} / ${_t(pay)} = ${_t(m)} '
          'gram olur.',
          birim: 'g',
        );
      case 2:
        return _say(
          'Bir $madde örneğinin ${_t(m)} gramında ${_t(g)} gram $el elementi '
          'bulunduğu belirlenmiştir. Buna göre bileşikteki $el elementinin '
          'kütlece yüzdesi kaçtır?',
          yuzde,
          [100 - yuzde, 100 * ak / mk, 100 * adet / atomSay, yuzde / 2],
          on: '%',
          'Kütlece yüzde ${_t(g)} / ${_t(m)}·100 = %${_t(yuzde)} olur.',
        );
      case 3:
        return _say(
          '${_t(n)} mol $madde bileşiğinde kaç gram $el elementi bulunur? '
          '($kut)',
          g,
          [n * ak, n * mk, n * kalan, g / (adet + 1), n * adet],
          '$molYazi ${_t(n)} mol bileşikte ${_t(n)}·${_t(pay)} = ${_t(g)} gram '
          '$el bulunur.',
          birim: 'g',
        );
      default:
        return _say(
          'Formülü $f olan bileşiğin ${_t(m)} gramlık örneğinde ${_t(g)} gram '
          '$el elementi bulunmaktadır. Buna göre $el elementinin atom kütlesi '
          'kaçtır? (${_kut([f], haric: el)})',
          ak,
          [pay, kalan, ak * 2, mk, kalan * g / (m - g) * 2],
          'Bir mol bileşikte diğer atomların kütlesi ${_t(kalan)} gramdır. '
          '$el atom kütlesi x ise ${adet == 1 ? 'x' : '$adet·x'} / '
          '${_t(kalan)} = ${_t(g)} / ${_t(m - g)} eşitliğinden x = ${_t(ak)} '
          'bulunur.',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 6. Kaba formül ve molekül formülü
// ---------------------------------------------------------------------------

// İki elementli bileşiklerin kaba formülleri; aynı element çiftinde oranlar
// birbirinden farklıdır.
const _kabaFormuller = [
  'Fe₂O₃', 'Fe₃O₄', 'FeO', 'Al₂O₃', 'SO₂', 'SO₃', 'CO₂', 'CO', 'CH₄', 'CH₃',
  'CH₂', 'C₃H₈', 'N₂O', 'NO', 'N₂O₃', 'NO₂', 'N₂O₅', 'Cu₂O', 'CuO', 'MgO',
  'Na₂O', 'P₂O₅', 'Mg₃N₂', 'Al₄C₃', 'FeS₂',
];

// Molekül formülü kaba formülünün en az iki katı olan bileşikler.
const _molekulFormulleri = [
  'C₂H₆', 'C₂H₄', 'C₃H₆', 'C₄H₈', 'C₂H₂', 'C₆H₆', 'C₄H₁₀', 'C₆H₁₂O₆',
  'C₂H₄O₂', 'C₃H₆O₃', 'H₂O₂', 'N₂O₄', 'N₂H₄', 'P₄O₁₀', 'C₆H₁₄', 'C₈H₁₈',
  'C₂H₆O₂', 'C₄H₈O₂', 'C₆H₁₂', 'C₅H₁₀', 'C₄H₆', 'C₂H₂O₄', 'C₁₀H₂₂',
  'C₅H₁₀O₅', 'Na₂O₂',
];

String _formul(List<String> el, List<int> adet) => [
  for (var j = 0; j < el.length; j++)
    '${el[j]}${adet[j] == 1 ? '' : _alt(adet[j])}',
].join();

String _sirala(List<String> x) => x.length == 1
    ? x.first
    : '${x.sublist(0, x.length - 1).join(', ')} ve ${x.last}';

final _f06 = lmAile(
  'kim_formul',
  'Kaba formül ve molekül formülü bulma',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.analiz,
  (a, b, c) {
    if (c < 5) {
      final atomlar = _atomlar(_kabaFormuller[a]);
      final el = atomlar.keys.toList(), adet = atomlar.values.toList();
      final k1 = _atomKutlesi[el[0]]!, k2 = _atomKutlesi[el[1]]!;
      final t = b + 1 + (c == 2 || c == 3 ? 20 : 0);
      final n1 = adet[0] * t / 50, n2 = adet[1] * t / 50;
      final m1 = n1 * k1, m2 = n2 * k2;
      final kut = _kut([_kabaFormuller[a]]);
      const soru = 'Bu bileşiğin kaba (basit) formülü nedir?';
      final giris = 'Yalnızca ${el[0]} ve ${el[1]} elementlerinden oluşan bir '
          'bileşiğin';
      final kok = switch (c) {
        0 => '$giris bir örneğinde ${_t(m1)} gram ${el[0]} ve ${_t(m2)} gram '
            '${el[1]} bulunmaktadır. $soru ($kut)',
        1 => '$giris ${_t(m1 + m2)} gramlık örneğinde ${_t(m1)} gram ${el[0]} '
            'bulunmaktadır. $soru ($kut)',
        2 => '${_t(m1)} gram ${el[0]} elementi ile ${_t(m2)} gram ${el[1]} '
            'elementi artansız birleşerek tek bir bileşik oluşturuyor. $soru '
            '($kut)',
        3 => '$giris ${_t(m1 + m2)} gramlık örneğinde ${_t(m2)} gram ${el[1]} '
            'bulunmaktadır. $soru ($kut)',
        _ => '$giris bir örneğinde ${_t(n1)} mol ${el[0]} atomu ve ${_t(m2)} '
            'gram ${el[1]} bulunmaktadır. $soru ($kut)',
      };
      // Kütle oranını mol oranı sanma hatası.
      final p1 = (adet[0] * k1).round(), p2 = (adet[1] * k2).round();
      final g = p1.gcd(p2);
      final on = switch (c) {
        1 => '${el[1]} kütlesi ${_t(m1 + m2)} − ${_t(m1)} = ${_t(m2)} gramdır. ',
        3 => '${el[0]} kütlesi ${_t(m1 + m2)} − ${_t(m2)} = ${_t(m1)} gramdır. ',
        _ => '',
      };
      final ilk = c == 4
          ? '${el[0]}: ${_t(n1)} mol'
          : '${el[0]}: ${_t(m1)} / ${_t(k1)} = ${_t(n1)} mol';
      return secenekli(
        kok,
        _formul(el, adet),
        [
          _formul(el, [adet[1], adet[0]]),
          if (p1 ~/ g <= 12 && p2 ~/ g <= 12) _formul(el, [p1 ~/ g, p2 ~/ g]),
          _formul(el, [2 * adet[0], 2 * adet[1]]),
          _formul(el, [adet[0], adet[1] + 1]),
          _formul(el, [adet[0] + 1, adet[1]]),
          _formul(el, [adet[0] + 1, adet[1] + 2]),
        ],
        '$on$ilk, ${el[1]}: ${_t(m2)} / ${_t(k2)} = ${_t(n2)} mol. Mol oranı '
        '${_t(n1)} : ${_t(n2)} = ${adet[0]} : ${adet[1]} olduğundan kaba formül '
        '${_formul(el, adet)} olur.',
      );
    }
    final f = _molekulFormulleri[a];
    final atomlar = _atomlar(f);
    final el = atomlar.keys.toList(), adet = atomlar.values.toList();
    final kat = adet.reduce((x, y) => x.gcd(y));
    final kabaAdet = [for (final x in adet) x ~/ kat];
    final kaba = _formul(el, kabaAdet);
    final mk = _mk(f), kabaMk = mk / kat;
    final kut = _kut([f]);
    final t = b + 1;
    final yanlis = [
      kaba,
      _formul(el, [for (final x in kabaAdet) x * (kat + 1)]),
      _formul(el, [for (final x in kabaAdet) x * (kat > 2 ? kat - 1 : kat + 2)]),
      _formul(el, [adet[1], adet[0], ...adet.sublist(2)]),
      _formul(el, [adet[0], adet[1] + 2, ...adet.sublist(2)]),
    ];
    final elYazi = 'Yalnızca ${_sirala(el)} elementlerinden oluşan';
    const soru = 'Bu bileşiğin molekül formülü nedir?';
    final katYazi = 'Kaba formül kütlesi ${_t(kabaMk)} olduğundan ${_t(mk)} / '
        '${_t(kabaMk)} = $kat; molekül formülü $f olur.';
    switch (c) {
      case 5:
      case 8:
        final n = t / 20, m = mk * t / 20;
        final giris = 'Kaba formülü $kaba olan bir bileşiğin ${_t(n)} molü '
            '${_t(m)} gramdır.';
        final mkYazi = 'Mol kütlesi ${_t(m)} / ${_t(n)} = ${_t(mk)} g/mol olur.';
        if (c == 5) {
          return secenekli('$giris $soru ($kut)', f, yanlis, '$mkYazi $katYazi');
        }
        final toplam = adet.fold(0, (x, y) => x + y);
        return sayisal(
          '$giris Bu bileşiğin bir molekülünde toplam kaç atom bulunur? ($kut)',
          toplam,
          [toplam ~/ kat, toplam ~/ kat * (kat + 1), kat, toplam + kat],
          '$mkYazi $katYazi Bir molekülde toplam $toplam atom bulunur.',
          positive: true,
        );
      case 6:
        final n = t / 20;
        final veri = _sirala([
          for (var j = 0; j < el.length; j++)
            '${_t(n * adet[j] * _atomKutlesi[el[j]]!)} gram ${el[j]}',
        ]);
        return secenekli(
          '$elYazi bir bileşiğin ${_t(n)} molünde $veri bulunmaktadır. $soru '
          '($kut)',
          f,
          yanlis,
          'Bir moldeki atom sayıları: ${[
            for (var j = 0; j < el.length; j++) '${el[j]} için ${_t(n * adet[j] * _atomKutlesi[el[j]]!)} / (${_t(n)}·${_t(_atomKutlesi[el[j]]!)}) = ${adet[j]}',
          ].join(', ')}. Molekül formülü $f olur.',
        );
      case 7:
        final n = t / 20;
        final veri = _sirala([
          for (var j = 0; j < el.length; j++)
            '${_t(n * adet[j])} mol ${el[j]} atomu',
        ]);
        return secenekli(
          '$elYazi bir bileşiğin ${_t(n)} molünde $veri bulunmaktadır. $soru',
          f,
          yanlis,
          'Bir moldeki atom sayıları: ${[
            for (var j = 0; j < el.length; j++) '${el[j]} için ${_t(n * adet[j])} / ${_t(n)} = ${adet[j]}',
          ].join(', ')}. Molekül formülü $f olur.',
        );
      default:
        final s = t / 50;
        final veri = _sirala([
          for (var j = 0; j < el.length; j++)
            '${_t(s * adet[j] * _atomKutlesi[el[j]]!)} gram ${el[j]}',
        ]);
        return secenekli(
          '$elYazi ve mol kütlesi ${_t(mk)} g/mol olan bir bileşiğin bir '
          'örneğinde $veri bulunmaktadır. $soru ($kut)',
          f,
          yanlis,
          'Mol sayıları: ${[
            for (var j = 0; j < el.length; j++) '${el[j]} ${_t(s * adet[j])}',
          ].join(', ')}. En küçük tam sayı oranı kaba formülü $kaba verir. '
          '$katYazi',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
  shortAnswer: false,
);

// ---------------------------------------------------------------------------
// 7. Tepkime denkleştirme ve mol oranları
// ---------------------------------------------------------------------------

// (girenler, ürünler, en küçük tam sayılı katsayılar). Her tepkimede dört tür
// vardır ve katsayıları farklı en az on sıralı tür çifti bulunur.
const _denklemler = [
  ('C₂H₆ + O₂', 'CO₂ + H₂O', [2, 7, 4, 6]),
  ('C₃H₈ + O₂', 'CO₂ + H₂O', [1, 5, 3, 4]),
  ('C₄H₁₀ + O₂', 'CO₂ + H₂O', [2, 13, 8, 10]),
  ('C₂H₄ + O₂', 'CO₂ + H₂O', [1, 3, 2, 2]),
  ('C₂H₂ + O₂', 'CO₂ + H₂O', [2, 5, 4, 2]),
  ('C₂H₅OH + O₂', 'CO₂ + H₂O', [1, 3, 2, 3]),
  ('CH₃OH + O₂', 'CO₂ + H₂O', [2, 3, 2, 4]),
  ('NH₃ + O₂', 'NO + H₂O', [4, 5, 4, 6]),
  ('NH₃ + O₂', 'N₂ + H₂O', [4, 3, 2, 6]),
  ('Fe₂O₃ + CO', 'Fe + CO₂', [1, 3, 2, 3]),
  ('Fe₂O₃ + H₂', 'Fe + H₂O', [1, 3, 2, 3]),
  ('Al + HCl', 'AlCl₃ + H₂', [2, 6, 2, 3]),
  ('Al + H₂SO₄', 'Al₂(SO₄)₃ + H₂', [2, 3, 1, 3]),
  ('Al(OH)₃ + H₂SO₄', 'Al₂(SO₄)₃ + H₂O', [2, 3, 1, 6]),
  ('FeS₂ + O₂', 'Fe₂O₃ + SO₂', [4, 11, 2, 8]),
  ('C₆H₆ + O₂', 'CO₂ + H₂O', [2, 15, 12, 6]),
  ('Fe₃O₄ + H₂', 'Fe + H₂O', [1, 4, 3, 4]),
  ('NO₂ + H₂O', 'HNO₃ + NO', [3, 1, 2, 1]),
  ('Al₂O₃ + HCl', 'AlCl₃ + H₂O', [1, 6, 2, 3]),
  ('SiO₂ + HF', 'SiF₄ + H₂O', [1, 4, 1, 2]),
  ('CS₂ + O₂', 'CO₂ + SO₂', [1, 3, 1, 2]),
  ('C₅H₁₂ + O₂', 'CO₂ + H₂O', [1, 8, 5, 6]),
  ('Ca(OH)₂ + H₃PO₄', 'Ca₃(PO₄)₂ + H₂O', [3, 2, 1, 6]),
  ('Mg₃N₂ + H₂O', 'Mg(OH)₂ + NH₃', [1, 6, 3, 2]),
  ('Al₄C₃ + H₂O', 'Al(OH)₃ + CH₄', [1, 12, 4, 3]),
];

String _katsayili(int k, String f) => k == 1 ? f : '$k$f';

final _f07 = lmAile(
  'kim_denklestirme',
  'Tepkime denkleştirme ve mol oranları',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (sol, sag, k) = _denklemler[a];
    final tur = [...sol.split(' + '), ...sag.split(' + ')];
    final ciftler = [
      for (var i = 0; i < 4; i++)
        for (var j = 0; j < 4; j++)
          if (i != j && k[i] != k[j]) (i, j),
    ];
    final (i, j) = ciftler[c];
    final n = k[i] * (b + 1) / 20, yanit = k[j] * (b + 1) / 20;
    final denk =
        '${_katsayili(k[0], tur[0])} + ${_katsayili(k[1], tur[1])} → '
        '${_katsayili(k[2], tur[2])} + ${_katsayili(k[3], tur[3])}';
    final veri = '${_t(n)} mol ${tur[i]}';
    final soru = i < 2
        ? (j < 2
              ? '$veri ile artansız tepkimeye girmek için kaç mol ${tur[j]} '
                    'gerekir?'
              : '$veri tamamen harcandığında en çok kaç mol ${tur[j]} oluşur?')
        : (j < 2
              ? '$veri elde etmek için en az kaç mol ${tur[j]} harcanmalıdır?'
              : '$veri oluştuğunda aynı anda kaç mol ${tur[j]} oluşur?');
    return _say(
      '$sol → $sag tepkimesi en küçük tam sayılarla denkleştiriliyor. Buna '
      'göre $soru',
      yanit,
      [n, n * k[i] / k[j], n * k[j], n / k[i], yanit / 2, yanit * 2],
      'Denk tepkime: $denk. Mol oranı ${tur[i]} : ${tur[j]} = ${k[i]} : ${k[j]} '
      'olduğundan ${_t(n)}·${k[j]} / ${k[i]} = ${_t(yanit)} mol bulunur.',
      birim: 'mol',
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 8. Kütle–kütle ve hacim hesapları
// ---------------------------------------------------------------------------

// (denk tepkime, tepken, katsayısı, gaz ürün, katsayısı)
const _gazTepkimeleri = [
  ('CaCO₃ → CaO + CO₂', 'CaCO₃', 1, 'CO₂', 1),
  ('2KClO₃ → 2KCl + 3O₂', 'KClO₃', 2, 'O₂', 3),
  ('Zn + 2HCl → ZnCl₂ + H₂', 'Zn', 1, 'H₂', 1),
  ('Mg + 2HCl → MgCl₂ + H₂', 'Mg', 1, 'H₂', 1),
  ('2Al + 6HCl → 2AlCl₃ + 3H₂', 'Al', 2, 'H₂', 3),
  ('2Na + 2H₂O → 2NaOH + H₂', 'Na', 2, 'H₂', 1),
  ('CH₄ + 2O₂ → CO₂ + 2H₂O', 'CH₄', 1, 'CO₂', 1),
  ('C₃H₈ + 5O₂ → 3CO₂ + 4H₂O', 'C₃H₈', 1, 'CO₂', 3),
  ('2H₂O₂ → 2H₂O + O₂', 'H₂O₂', 2, 'O₂', 1),
  ('2NaHCO₃ → Na₂CO₃ + H₂O + CO₂', 'NaHCO₃', 2, 'CO₂', 1),
  ('Fe + 2HCl → FeCl₂ + H₂', 'Fe', 1, 'H₂', 1),
  ('CaC₂ + 2H₂O → Ca(OH)₂ + C₂H₂', 'CaC₂', 1, 'C₂H₂', 1),
  ('2H₂O → 2H₂ + O₂', 'H₂O', 2, 'O₂', 1),
  ('N₂ + 3H₂ → 2NH₃', 'N₂', 1, 'NH₃', 2),
  ('S + O₂ → SO₂', 'S', 1, 'SO₂', 1),
  ('C + O₂ → CO₂', 'C', 1, 'CO₂', 1),
  ('MgCO₃ → MgO + CO₂', 'MgCO₃', 1, 'CO₂', 1),
  ('NH₄NO₂ → N₂ + 2H₂O', 'NH₄NO₂', 1, 'N₂', 1),
  ('2KNO₃ → 2KNO₂ + O₂', 'KNO₃', 2, 'O₂', 1),
  ('CaCO₃ + 2HCl → CaCl₂ + H₂O + CO₂', 'CaCO₃', 1, 'CO₂', 1),
  ('C₂H₅OH + 3O₂ → 2CO₂ + 3H₂O', 'C₂H₅OH', 1, 'CO₂', 2),
  ('Na₂CO₃ + 2HCl → 2NaCl + H₂O + CO₂', 'Na₂CO₃', 1, 'CO₂', 1),
  ('2C₂H₂ + 5O₂ → 4CO₂ + 2H₂O', 'C₂H₂', 2, 'CO₂', 4),
  ('C₆H₁₂O₆ → 2C₂H₅OH + 2CO₂', 'C₆H₁₂O₆', 1, 'CO₂', 2),
  ('CaH₂ + 2H₂O → Ca(OH)₂ + 2H₂', 'CaH₂', 1, 'H₂', 2),
];

final _f08 = lmAile(
  'kim_stokiyometri',
  'Tepkimelerde kütle ve gaz hacmi hesapları',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (denk, fa, ka, fb, kb) = _gazTepkimeleri[a];
    final ma = _mk(fa), mb = _mk(fb);
    final t = b + 1 + 20 * (c ~/ 5);
    final na = ka * t / 20, nb = kb * t / 20;
    final ga = na * ma, gb = nb * mb, v = nb * 22.4;
    final giris = '$denk tepkimesine göre';
    const nk = 'normal koşullarda 1 mol gaz 22,4 L hacim kaplar';
    final oran = '$fa : $fb mol oranı $ka : $kb olduğundan';
    switch (c % 5) {
      case 0:
        return _say(
          '$giris ${_t(ga)} gram $fa tamamen tepkimeye girdiğinde kaç gram $fb '
          'oluşur? (${_kut([fa, fb])})',
          gb,
          [na * mb, ga * kb / ka, gb * ka / kb, nb, ga * mb / ma * ka / kb],
          '${_t(ga)} / ${_t(ma)} = ${_t(na)} mol $fa harcanır. $oran '
          '${_t(nb)} mol $fb oluşur; kütlesi ${_t(nb)}·${_t(mb)} = ${_t(gb)} '
          'gramdır.',
          birim: 'g',
        );
      case 1:
        return _say(
          '$giris ${_t(ga)} gram $fa tamamen tepkimeye girdiğinde normal '
          'koşullarda kaç litre $fb gazı oluşur? (${_kut([fa])}; $nk)',
          v,
          [na * 22.4, v * ka / kb, na * kb * 22.4, nb, gb],
          '${_t(ga)} / ${_t(ma)} = ${_t(na)} mol $fa harcanır. $oran '
          '${_t(nb)} mol $fb oluşur; hacmi ${_t(nb)}·22,4 = ${_t(v)} L olur.',
          birim: 'L',
        );
      case 2:
        return _say(
          '$giris normal koşullarda ${_t(v)} litre $fb gazı elde etmek için kaç '
          'gram $fa harcanmalıdır? (${_kut([fa])}; $nk)',
          ga,
          [nb * ma, nb * kb / ka * ma, na, v * ma / 22.4 * kb / ka, ga * 2],
          '${_t(v)} / 22,4 = ${_t(nb)} mol $fb oluşur. $oran ${_t(na)} mol $fa '
          'harcanır; kütlesi ${_t(na)}·${_t(ma)} = ${_t(ga)} gramdır.',
          birim: 'g',
        );
      case 3:
        return _say(
          '$giris ${_t(gb)} gram $fb oluşması için kaç gram $fa tepkimeye '
          'girmelidir? (${_kut([fa, fb])})',
          ga,
          [nb * ma, gb * ka / kb, ga * kb / ka, na, gb * ma / mb * kb / ka],
          '${_t(gb)} / ${_t(mb)} = ${_t(nb)} mol $fb oluşur. $oran ${_t(na)} '
          'mol $fa harcanır; kütlesi ${_t(na)}·${_t(ma)} = ${_t(ga)} gramdır.',
          birim: 'g',
        );
      default:
        return _say(
          '$giris normal koşullarda ${_t(v)} litre $fb gazı oluştuğunda kaç mol '
          '$fa harcanmış olur? ($nk)',
          na,
          [nb, nb * kb / ka, v * ka / kb, nb / 2, nb * 2, na * 2],
          '${_t(v)} / 22,4 = ${_t(nb)} mol $fb oluşur. $oran ${_t(nb)}·$ka / $kb '
          '= ${_t(na)} mol $fa harcanır.',
          birim: 'mol',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 9. Sınırlayıcı bileşen ve artan madde
// ---------------------------------------------------------------------------

// (denk tepkime, 1. tepken, katsayı, 2. tepken, katsayı, ürün, katsayı)
const _ikiTepkenli = [
  ('2H₂ + O₂ → 2H₂O', 'H₂', 2, 'O₂', 1, 'H₂O', 2),
  ('N₂ + 3H₂ → 2NH₃', 'N₂', 1, 'H₂', 3, 'NH₃', 2),
  ('2Mg + O₂ → 2MgO', 'Mg', 2, 'O₂', 1, 'MgO', 2),
  ('4Al + 3O₂ → 2Al₂O₃', 'Al', 4, 'O₂', 3, 'Al₂O₃', 2),
  ('2Na + Cl₂ → 2NaCl', 'Na', 2, 'Cl₂', 1, 'NaCl', 2),
  ('H₂ + Cl₂ → 2HCl', 'H₂', 1, 'Cl₂', 1, 'HCl', 2),
  ('2SO₂ + O₂ → 2SO₃', 'SO₂', 2, 'O₂', 1, 'SO₃', 2),
  ('2CO + O₂ → 2CO₂', 'CO', 2, 'O₂', 1, 'CO₂', 2),
  ('C + O₂ → CO₂', 'C', 1, 'O₂', 1, 'CO₂', 1),
  ('S + O₂ → SO₂', 'S', 1, 'O₂', 1, 'SO₂', 1),
  ('2Fe + 3Cl₂ → 2FeCl₃', 'Fe', 2, 'Cl₂', 3, 'FeCl₃', 2),
  ('2Al + 3Cl₂ → 2AlCl₃', 'Al', 2, 'Cl₂', 3, 'AlCl₃', 2),
  ('Ca + 2H₂O → Ca(OH)₂ + H₂', 'Ca', 1, 'H₂O', 2, 'Ca(OH)₂', 1),
  ('CaO + H₂O → Ca(OH)₂', 'CaO', 1, 'H₂O', 1, 'Ca(OH)₂', 1),
  ('2NO + O₂ → 2NO₂', 'NO', 2, 'O₂', 1, 'NO₂', 2),
  ('CH₄ + 2O₂ → CO₂ + 2H₂O', 'CH₄', 1, 'O₂', 2, 'CO₂', 1),
  ('Zn + 2HCl → ZnCl₂ + H₂', 'Zn', 1, 'HCl', 2, 'H₂', 1),
  ('Mg + 2HCl → MgCl₂ + H₂', 'Mg', 1, 'HCl', 2, 'MgCl₂', 1),
  ('NaOH + HCl → NaCl + H₂O', 'NaOH', 1, 'HCl', 1, 'NaCl', 1),
  ('3Mg + N₂ → Mg₃N₂', 'Mg', 3, 'N₂', 1, 'Mg₃N₂', 1),
  ('2Cu + O₂ → 2CuO', 'Cu', 2, 'O₂', 1, 'CuO', 2),
  ('Fe + S → FeS', 'Fe', 1, 'S', 1, 'FeS', 1),
  ('2Al + 3S → Al₂S₃', 'Al', 2, 'S', 3, 'Al₂S₃', 1),
  ('P₄ + 5O₂ → P₄O₁₀', 'P₄', 1, 'O₂', 5, 'P₄O₁₀', 1),
  ('N₂ + O₂ → 2NO', 'N₂', 1, 'O₂', 1, 'NO', 2),
];

final _f09 = lmAile(
  'kim_sinirlayici',
  'Sınırlayıcı bileşen ve artan madde',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final (denk, fa, ka, fb, kb, fc, kc) = _ikiTepkenli[a];
    final x = (1 + b % 10) / 10; // tepkime ilerlemesi (mol)
    final artan = (1 + (b + 3 * (c ~/ 5)) % 8) / 10; // artan madde (mol)
    final aSinir = b < 10;
    final na = ka * x + (aSinir ? 0 : artan), nb = kb * x + (aSinir ? artan : 0);
    final ma = _mk(fa), mb = _mk(fb), mc = _mk(fc);
    final fs = aSinir ? fa : fb, fe = aSinir ? fb : fa; // sınırlayıcı, artan
    final ks = aSinir ? ka : kb, ke = aSinir ? kb : ka;
    final ns = aSinir ? na : nb, ne = aSinir ? nb : na;
    final me = aSinir ? mb : ma;
    final nc = kc * x;
    final yanlisUrun = kc * ne / ke; // artan maddeden hesaplama hatası
    final giris = '$denk tepkimesine göre';
    final karar =
        '${_t(ns)} mol $fs için ${_t(ns)}·$ke / $ks = ${_t(ke * x)} mol $fe '
        'gerekir; eldeki ${_t(ne)} mol bundan fazla olduğundan sınırlayıcı '
        'bileşen $fs olur.';
    final molVeri = '${_t(na)} mol $fa ile ${_t(nb)} mol $fb';
    final kutleVeri = '${_t(na * ma)} gram $fa ile ${_t(nb * mb)} gram $fb';
    final cevir =
        '$fa: ${_t(na * ma)} / ${_t(ma)} = ${_t(na)} mol, $fb: ${_t(nb * mb)} / '
        '${_t(mb)} = ${_t(nb)} mol.';
    switch (c % 5) {
      case 0:
        return _say(
          '$giris $molVeri tam verimle tepkimeye sokuluyor. En çok kaç mol $fc '
          'oluşur?',
          nc,
          [yanlisUrun, na + nb, ns, ne, nc / 2, nc * 2],
          '$karar Oluşan $fc miktarı ${_t(ns)}·$kc / $ks = ${_t(nc)} mol olur.',
          birim: 'mol',
        );
      case 1:
        return _say(
          '$giris $molVeri tam verimle tepkimeye sokuluyor. Tepkime sonunda '
          'artan maddeden kaç mol kalır?',
          artan,
          [(na - nb).abs(), ne - x, ne, ns, artan + x, ke * x],
          '$karar Artan $fe miktarı ${_t(ne)} − ${_t(ke * x)} = ${_t(artan)} '
          'mol olur.',
          birim: 'mol',
        );
      case 2:
        return _say(
          '$giris $kutleVeri tam verimle tepkimeye sokuluyor. En çok kaç gram '
          '$fc oluşur? (${_kut([fa, fb, fc])})',
          nc * mc,
          [na * ma + nb * mb, yanlisUrun * mc, ns * mc, nc * mc / 2, nc],
          '$cevir $karar Oluşan $fc miktarı ${_t(nc)} mol, kütlesi '
          '${_t(nc)}·${_t(mc)} = ${_t(nc * mc)} gram olur.',
          birim: 'g',
        );
      case 3:
        return _say(
          '$giris $kutleVeri tam verimle tepkimeye sokuluyor. Tepkime sonunda '
          'artan maddenin kütlesi kaç gramdır? (${_kut([fa, fb])})',
          artan * me,
          [
            (na * ma - nb * mb).abs(),
            artan * (aSinir ? ma : mb),
            ne * me,
            (ne - x) * me,
            artan,
            ke * x * me,
          ],
          '$cevir $karar Artan $fe miktarı ${_t(ne)} − ${_t(ke * x)} = '
          '${_t(artan)} mol, kütlesi ${_t(artan)}·${_t(me)} = '
          '${_t(artan * me)} gram olur.',
          birim: 'g',
        );
      default:
        return _say(
          '$giris $molVeri tam verimle tepkimeye sokuluyor. En çok kaç gram $fc '
          'oluşur? (${_kut([fc])})',
          nc * mc,
          [yanlisUrun * mc, ns * mc, (na + nb) * mc, nc, nc * mc / 2],
          '$karar Oluşan $fc miktarı ${_t(nc)} mol, kütlesi ${_t(nc)}·${_t(mc)} '
          '= ${_t(nc * mc)} gram olur.',
          birim: 'g',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 10. Yüzde verim ve saflık
// ---------------------------------------------------------------------------

// (denk tepkime, tepken, katsayısı, ürün, katsayısı)
const _verimTepkimeleri = [
  ('CaCO₃ → CaO + CO₂', 'CaCO₃', 1, 'CaO', 1),
  ('Fe₂O₃ + 3CO → 2Fe + 3CO₂', 'Fe₂O₃', 1, 'Fe', 2),
  ('C₆H₁₂O₆ → 2C₂H₅OH + 2CO₂', 'C₆H₁₂O₆', 1, 'C₂H₅OH', 2),
  ('CaO + H₂O → Ca(OH)₂', 'CaO', 1, 'Ca(OH)₂', 1),
  ('2Al₂O₃ → 4Al + 3O₂', 'Al₂O₃', 2, 'Al', 4),
  ('CuO + H₂ → Cu + H₂O', 'CuO', 1, 'Cu', 1),
  ('2KClO₃ → 2KCl + 3O₂', 'KClO₃', 2, 'O₂', 3),
  ('CaC₂ + 2H₂O → Ca(OH)₂ + C₂H₂', 'CaC₂', 1, 'C₂H₂', 1),
  ('2NaHCO₃ → Na₂CO₃ + H₂O + CO₂', 'NaHCO₃', 2, 'Na₂CO₃', 1),
  ('MgCO₃ → MgO + CO₂', 'MgCO₃', 1, 'MgO', 1),
  ('2Mg + O₂ → 2MgO', 'Mg', 2, 'MgO', 2),
  ('S + O₂ → SO₂', 'S', 1, 'SO₂', 1),
  ('Zn + H₂SO₄ → ZnSO₄ + H₂', 'Zn', 1, 'ZnSO₄', 1),
  ('2H₂O₂ → 2H₂O + O₂', 'H₂O₂', 2, 'O₂', 1),
  ('C + O₂ → CO₂', 'C', 1, 'CO₂', 1),
  ('Fe + S → FeS', 'Fe', 1, 'FeS', 1),
  ('4FeS₂ + 11O₂ → 2Fe₂O₃ + 8SO₂', 'FeS₂', 4, 'SO₂', 8),
  ('SiO₂ + 2C → Si + 2CO', 'SiO₂', 1, 'Si', 1),
  ('2Cu + O₂ → 2CuO', 'Cu', 2, 'CuO', 2),
  ('CaCO₃ + 2HCl → CaCl₂ + H₂O + CO₂', 'CaCO₃', 1, 'CO₂', 1),
  ('3Fe + 4H₂O → Fe₃O₄ + 4H₂', 'Fe', 3, 'Fe₃O₄', 1),
  ('2Al + 3H₂SO₄ → Al₂(SO₄)₃ + 3H₂', 'Al', 2, 'H₂', 3),
  ('Mg + 2HCl → MgCl₂ + H₂', 'Mg', 1, 'H₂', 1),
  ('2NaCl → 2Na + Cl₂', 'NaCl', 2, 'Cl₂', 1),
  ('Fe₃O₄ + 4H₂ → 3Fe + 4H₂O', 'Fe₃O₄', 1, 'Fe', 3),
];

final _f10 = lmAile(
  'kim_verim',
  'Tepkimelerde yüzde verim ve saflık',
  Topic.chemistry,
  Difficulty.hard,
  BloomLevel.analiz,
  (a, b, c) {
    final (denk, fa, ka, fb, kb) = _verimTepkimeleri[a];
    final ma = _mk(fa), mb = _mk(fb);
    final t = b + 1;
    final p = const [80, 60, 50, 90, 70, 40, 30, 20][(a + b + 4 * (c ~/ 5)) % 8];
    final na = ka * t / 10, nb = kb * t / 10;
    final ga = na * ma, teorik = nb * mb, gercek = teorik * p / 100;
    final kut = _kut([fa, fb]);
    final teorikYazi =
        '${_t(ga)} gram $fa ${_t(na)} moldür; tam verimle ${_t(nb)} mol, yani '
        '${_t(teorik)} gram $fb oluşur.';
    switch (c % 5) {
      case 0:
        return _say(
          '$denk tepkimesine göre ${_t(ga)} gram $fa tepkimeye sokulduğunda '
          '${_t(gercek)} gram $fb elde ediliyor. Tepkimenin yüzde verimi '
          'kaçtır? ($kut)',
          p,
          [100 - p, if (gercek < ga) 100 * gercek / ga, p / 2, p + 10, p - 10],
          on: '%',
          '$teorikYazi Verim ${_t(gercek)} / ${_t(teorik)}·100 = %$p olur.',
        );
      case 1:
        return _say(
          '$denk tepkimesine göre ${_t(ga)} gram $fa %$p verimle tepkimeye '
          'girdiğinde kaç gram $fb elde edilir? ($kut)',
          gercek,
          [teorik, teorik * (100 - p) / 100, ga * p / 100, na * mb * p / 100],
          '$teorikYazi Verim %$p olduğundan ${_t(teorik)}·$p / 100 = '
          '${_t(gercek)} gram $fb elde edilir.',
          birim: 'g',
        );
      case 2:
        return _say(
          'Kütlece %$p saflıktaki ${_t(ga)} gram $fa örneği $denk tepkimesine '
          'göre tamamen tepkimeye giriyor; safsızlıklar tepkimeye katılmıyor. '
          'Kaç gram $fb oluşur? ($kut)',
          gercek,
          [teorik, teorik * (100 - p) / 100, ga * p / 100, na * mb * p / 100],
          'Örnekteki saf $fa kütlesi ${_t(ga)}·$p / 100 = ${_t(ga * p / 100)} '
          'gram, yani ${_t(na * p / 100, 3)} moldür. Oluşan $fb '
          '${_t(nb * p / 100, 3)} mol olup kütlesi ${_t(gercek)} gramdır.',
          birim: 'g',
        );
      case 3:
        return _say(
          'Saf olmayan ${_t(ga)} gramlık bir $fa örneği $denk tepkimesine göre '
          'tepkimeye sokulduğunda ${_t(gercek)} gram $fb oluşuyor; safsızlıklar '
          'tepkimeye katılmıyor. Örnekteki $fa kütlece yüzde kaçtır? ($kut)',
          p,
          [100 - p, if (gercek < ga) 100 * gercek / ga, p / 2, p + 10, p - 10],
          on: '%',
          '${_t(gercek)} gram $fb ${_t(nb * p / 100, 3)} moldür; bunun için '
          '${_t(na * p / 100, 3)} mol, yani ${_t(ga * p / 100)} gram saf $fa '
          'gerekir. Saflık ${_t(ga * p / 100)} / ${_t(ga)}·100 = %$p olur.',
        );
      default:
        return _say(
          '$denk tepkimesi %$p verimle gerçekleşmektedir. ${_t(gercek)} gram '
          '$fb elde etmek için kaç gram $fa kullanılmalıdır? ($kut)',
          ga,
          [ga * p / 100, ga * p / 100 * p / 100, teorik, gercek, ga * 2],
          'Tam verimle oluşması gereken $fb kütlesi ${_t(gercek)}·100 / $p = '
          '${_t(teorik)} gram, yani ${_t(nb)} moldür. Gereken $fa ${_t(na)} mol '
          'olup kütlesi ${_t(na)}·${_t(ma)} = ${_t(ga)} gramdır.',
          birim: 'g',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 11. Gaz yasaları
// ---------------------------------------------------------------------------

const _oranCiftleri = [
  (1, 2), (2, 1), (1, 3), (3, 1), (2, 3), (3, 2), (1, 4), (4, 1), (3, 4),
  (4, 3), (1, 5), (5, 1), (2, 5), (5, 2), (3, 5), (5, 3), (4, 5), (5, 4),
  (1, 6), (6, 1),
];

// Kelvin karşılıkları basit oran veren Celsius sıcaklık çiftleri.
const _sicaklikCiftleri = [
  (27, 127), (27, 327), (127, 27), (127, 327), (327, 27), (327, 127),
  (0, 273), (273, 0), (-73, 27), (27, -73), (-73, 127), (127, -73),
  (227, 27), (27, 227), (227, 127), (127, 227), (-23, 227), (227, -23),
  (-23, 27), (27, 477),
];

const _besOran = [(1, 2), (2, 1), (1, 3), (3, 2), (2, 3)];

final _f11 = lmAile(
  'kim_gaz_yasalari',
  'Boyle, Charles, Gay-Lussac ve birleşik gaz yasası',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (n1, n2) = _oranCiftleri[b];
    final (c1, c2) = _sicaklikCiftleri[b];
    final k1 = c1 + 273, k2 = c2 + 273;
    final g = k1.gcd(k2);
    final r1 = k1 ~/ g, r2 = k2 ~/ g;
    final kelvin = 'T₁ = ${_t(c1)} + 273 = $k1 K, T₂ = ${_t(c2)} + 273 = $k2 K.';
    switch (c) {
      case 0:
        final p1 = n1 / 2, p2 = n2 / 2;
        final v1 = n2 * (a + 1) / 2, v2 = n1 * (a + 1) / 2;
        return _say(
          'Sabit sıcaklıkta, sürtünmesiz pistonlu bir kapta bulunan ideal gazın '
          'basıncı ${_t(p1)} atm iken hacmi ${_t(v1)} L olarak ölçülüyor. Piston '
          'hareket ettirilerek gazın basıncı ${_t(p2)} atm yapıldığında hacmi '
          'kaç litre olur?',
          v2,
          [v1 * p2 / p1, v1, v2 / 2, v2 * 2, v1 + v2],
          'Boyle yasasına göre P₁V₁ = P₂V₂ olur: ${_t(p1)}·${_t(v1)} = '
          '${_t(p2)}·V₂ eşitliğinden V₂ = ${_t(v2)} L bulunur.',
          birim: 'L',
        );
      case 4:
        final p1 = n1 / 5, p2 = n2 / 5;
        final v1 = n2 * (a + 1) / 2, v2 = n1 * (a + 1) / 2;
        return _say(
          'Sabit sıcaklıkta ${_t(p1)} atm basınç altında ${_t(v1)} L hacim '
          'kaplayan ideal gazın hacmi ${_t(v2)} L yapılıyor. Gazın son basıncı '
          'kaç atm olur?',
          p2,
          [p1 * v2 / v1, p1, p2 * 2, p2 / 2, p1 + p2],
          'Boyle yasasına göre P₁V₁ = P₂V₂ olur: ${_t(p1)}·${_t(v1)} = '
          'P₂·${_t(v2)} eşitliğinden P₂ = ${_t(p2)} atm bulunur.',
        );
      case 8:
        final p1 = n1 * 190, p2 = n2 * 190;
        final v1 = n2 * (a + 1) * 20, v2 = n1 * (a + 1) * 20;
        return sayisal(
          'Sabit sıcaklıkta $p1 mmHg basınç altında $v1 mL hacim kaplayan bir '
          'miktar ideal gazın basıncı $p2 mmHg değerine getiriliyor. Gazın son '
          'hacmi kaç mL olur?',
          v2,
          [v1 * n2 ~/ n1, v1, v2 * 2, v2 ~/ 2, v1 + v2],
          'Boyle yasasına göre P₁V₁ = P₂V₂ olur: $p1·$v1 = $p2·V₂ eşitliğinden '
          'V₂ = $v2 mL bulunur.',
          unit: 'mL',
          positive: true,
        );
      case 1:
        final v1 = r1 * (a + 1) / 2, v2 = r2 * (a + 1) / 2;
        return _say(
          'Sabit basınçta, sürtünmesiz pistonlu bir kapta bulunan ideal gazın '
          'sıcaklığı ${_t(c1)} °C iken hacmi ${_t(v1)} L olarak ölçülüyor. Gazın '
          'sıcaklığı ${_t(c2)} °C yapıldığında hacmi kaç litre olur?',
          v2,
          [if (c1 != 0) v1 * c2 / c1, v1 * r1 / r2, v1, v2 * 2, v2 / 2],
          '$kelvin Charles yasasına göre V₁ / T₁ = V₂ / T₂ olur: V₂ = '
          '${_t(v1)}·$k2 / $k1 = ${_t(v2)} L bulunur.',
          birim: 'L',
        );
      case 5:
        final v1 = r1 * (a + 1) / 2, v2 = r2 * (a + 1) / 2;
        return _say(
          'Sabit basınçta ${_t(c1)} °C sıcaklıkta ${_t(v1)} L hacim kaplayan '
          'ideal gazın sıcaklığı, hacmi ${_t(v2)} L oluncaya kadar '
          'değiştiriliyor. Gazın son sıcaklığı kaç °C olur?',
          c2,
          [k2, c1 * r2 / r1, k2 + 273, c2 + 100, c2 - 100, c1 + 273],
          'T₁ = ${_t(c1)} + 273 = $k1 K olur. V₁ / T₁ = V₂ / T₂ eşitliğinden '
          'T₂ = $k1·${_t(v2)} / ${_t(v1)} = $k2 K, yani $k2 − 273 = ${_t(c2)} '
          '°C bulunur.',
          birim: '°C',
          arti: false,
        );
      case 9:
        final v1 = r1 * (a + 1) * 10, v2 = r2 * (a + 1) * 10;
        return sayisal(
          'Sabit basınçta $k1 K sıcaklıkta $v1 mL hacim kaplayan ideal gazın '
          'sıcaklığı $k2 K değerine getiriliyor. Gazın son hacmi kaç mL olur?',
          v2,
          [v1 * r1 ~/ r2, v1, v2 * 2, v2 ~/ 2, v1 + v2],
          'Charles yasasına göre V₁ / T₁ = V₂ / T₂ olur: V₂ = $v1·$k2 / $k1 = '
          '$v2 mL bulunur.',
          unit: 'mL',
          positive: true,
        );
      case 2:
        final p1 = r1 * (a + 1) / 10, p2 = r2 * (a + 1) / 10;
        return _say(
          'Sabit hacimli kapalı bir çelik kapta bulunan ideal gazın sıcaklığı '
          '${_t(c1)} °C iken basıncı ${_t(p1)} atm olarak ölçülüyor. Gazın '
          'sıcaklığı ${_t(c2)} °C yapıldığında basıncı kaç atm olur?',
          p2,
          [if (c1 != 0) p1 * c2 / c1, p1 * r1 / r2, p1, p2 * 2, p2 / 2],
          '$kelvin Gay-Lussac yasasına göre P₁ / T₁ = P₂ / T₂ olur: P₂ = '
          '${_t(p1)}·$k2 / $k1 = ${_t(p2)} atm bulunur.',
        );
      case 6:
        final p1 = r1 * (a + 1) * 20, p2 = r2 * (a + 1) * 20;
        return _say(
          'Sabit hacimli kapalı bir kapta ${_t(c1)} °C sıcaklıkta $p1 mmHg '
          'basınç yapan ideal gazın sıcaklığı, basıncı $p2 mmHg oluncaya kadar '
          'değiştiriliyor. Gazın son sıcaklığı kaç °C olur?',
          c2,
          [k2, c1 * r2 / r1, k2 + 273, c2 + 100, c2 - 100, c1 + 273],
          'T₁ = ${_t(c1)} + 273 = $k1 K olur. P₁ / T₁ = P₂ / T₂ eşitliğinden '
          'T₂ = $k1·$p2 / $p1 = $k2 K, yani $k2 − 273 = ${_t(c2)} °C bulunur.',
          birim: '°C',
          arti: false,
        );
      default:
        // Birleşik gaz yasası. Oranlar birbirini götürüp sonucu verilen
        // değere eşitlemesin diye gerekirse ilk oran kaydırılır.
        var (x, y) = _besOran[a % 5];
        if (x * r2 == y * r1) x += 3;
        final s = 1 + a ~/ 5;
        if (c == 3) {
          final p1 = x / 2, p2 = y / 2;
          final v1 = y * r1 * s / 2, v2 = x * r2 * s / 2;
          return _say(
            '${_t(c1)} °C sıcaklıkta ve ${_t(p1)} atm basınçta ${_t(v1)} L hacim '
            'kaplayan bir miktar ideal gaz, ${_t(c2)} °C sıcaklığa ve ${_t(p2)} '
            'atm basınca getiriliyor. Gazın son hacmi kaç litre olur?',
            v2,
            [v1 * p2 / p1 * k2 / k1, v1 * p1 / p2 * k1 / k2, v1 * k2 / k1, v1 * p1 / p2],
            '$kelvin P₁V₁ / T₁ = P₂V₂ / T₂ eşitliğinden V₂ = '
            '${_t(p1)}·${_t(v1)}·$k2 / ($k1·${_t(p2)}) = ${_t(v2)} L bulunur.',
            birim: 'L',
          );
        }
        final v1 = 2 * x, v2 = 2 * y;
        final p1 = y * r1 * s / 10, p2 = x * r2 * s / 10;
        return _say(
          '${_t(c1)} °C sıcaklıkta ${_t(v1)} L hacim kaplayan ideal gazın '
          'basıncı ${_t(p1)} atm olarak ölçülüyor. Gaz ${_t(c2)} °C sıcaklığa '
          'getirilip hacmi ${_t(v2)} L yapıldığında basıncı kaç atm olur?',
          p2,
          [p1 * v2 / v1 * k2 / k1, p1 * v1 / v2 * k1 / k2, p1 * k2 / k1, p1 * v1 / v2],
          '$kelvin P₁V₁ / T₁ = P₂V₂ / T₂ eşitliğinden P₂ = '
          '${_t(p1)}·${_t(v1)}·$k2 / ($k1·${_t(v2)}) = ${_t(p2)} atm bulunur.',
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 12. İdeal gaz denklemi ve gaz yoğunluğu
// ---------------------------------------------------------------------------

// Mol kütleleri birbirinden farklı, oda sıcaklığında gaz olan maddeler.
const _gazlar = [
  ('H₂', 'hidrojen'), ('He', 'helyum'), ('CH₄', 'metan'), ('NH₃', 'amonyak'),
  ('Ne', 'neon'), ('C₂H₂', 'asetilen'), ('N₂', 'azot'), ('C₂H₆', 'etan'),
  ('O₂', 'oksijen'), ('H₂S', 'hidrojen sülfür'), ('F₂', 'flor'),
  ('Ar', 'argon'), ('C₃H₆', 'propen'), ('CO₂', 'karbon dioksit'),
  ('C₄H₁₀', 'bütan'), ('SO₂', 'kükürt dioksit'), ('Cl₂', 'klor'),
  ('HBr', 'hidrojen bromür'), ('Kr', 'kripton'), ('Xe', 'ksenon'),
];

const _rYazi = 'R = 0,082 L·atm/(mol·K)';

final _f12 = lmAile(
  'kim_ideal_gaz',
  'İdeal gaz denklemi ve gaz yoğunluğu',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final tc = const [27, 127, 227, 327, 527][a % 5];
    final tk = tc + 273;
    final rt = 0.082 * tk;
    final kelvin = 'T = $tc + 273 = $tk K.';
    if (c % 5 == 4) {
      final (f, ad) = _gazlar[b];
      final mk = _mk(f);
      final j = 1 + a ~/ 5;
      final p = j * rt / 20, d = j * mk / 20;
      if (c == 4) {
        return _say(
          '$tc °C sıcaklıkta ve ${_t(p)} atm basınçta $ad ($f) gazının '
          'yoğunluğu kaç g/L olur? (${_kut([f])}; $_rYazi)',
          d,
          [p * mk / (0.082 * tc), d * 2, d / 2, mk / 22.4, p * mk],
          '$kelvin d = P·M / (R·T) = ${_t(p)}·${_t(mk)} / (0,082·$tk) = '
          '${_t(d)} g/L bulunur.',
          birim: 'g/L',
        );
      }
      return _say(
        '$tc °C sıcaklıkta ve ${_t(p)} atm basınçta yoğunluğu ${_t(d)} g/L olan '
        'ideal gazın mol kütlesi kaç g/mol olur? ($_rYazi)',
        mk,
        [d * 0.082 * tc / p, d * 22.4, mk * 2, mk / 2, d * tk / p],
        '$kelvin M = d·R·T / P = ${_t(d)}·0,082·$tk / ${_t(p)} = ${_t(mk)} '
        'g/mol bulunur.',
        birim: 'g/mol',
      );
    }
    final p = (c < 5
        ? const [0.5, 1, 2, 3, 4]
        : const [0.2, 0.4, 0.8, 1.5, 2.5])[a ~/ 5];
    final k = b + 1;
    final v = k * rt / 10, n = k * p / 10;
    switch (c % 5) {
      case 0:
        return _say(
          '${_t(n)} mol ideal gaz $tc °C sıcaklıkta ${_t(p)} atm basınç '
          'yapmaktadır. Gazın hacmi kaç litredir? ($_rYazi)',
          v,
          [n * 0.082 * tc / p, n * rt * p, v / 2, v * 2, n * 22.4],
          '$kelvin V = n·R·T / P = ${_t(n)}·0,082·$tk / ${_t(p)} = ${_t(v)} L '
          'bulunur.',
          birim: 'L',
        );
      case 1:
        return _say(
          '${_t(v)} L hacimli kapalı bir kapta $tc °C sıcaklıkta ${_t(n)} mol '
          'ideal gaz bulunmaktadır. Gazın basıncı kaç atm olur? ($_rYazi)',
          p,
          [n * 0.082 * tc / v, v / (n * rt), p * 2, p / 2, n * 22.4 / v],
          '$kelvin P = n·R·T / V = ${_t(n)}·0,082·$tk / ${_t(v)} = ${_t(p)} '
          'atm bulunur.',
        );
      case 2:
        return _say(
          '$tc °C sıcaklıkta ${_t(v)} L hacimli kapalı bir kapta ${_t(p)} atm '
          'basınç yapan ideal gaz kaç moldür? ($_rYazi)',
          n,
          [p * v / (0.082 * tc), v / 22.4, n * 2, n / 2, p * v],
          '$kelvin n = P·V / (R·T) = ${_t(p)}·${_t(v)} / (0,082·$tk) = '
          '${_t(n)} mol bulunur.',
          birim: 'mol',
        );
      default:
        final (f, ad) = _gazlar[(a + b) % 20];
        final mk = _mk(f);
        return _say(
          '$tc °C sıcaklıkta ${_t(v)} L hacimli kapalı bir kapta ${_t(p)} atm '
          'basınç yapan $ad ($f) gazı kaç gramdır? (${_kut([f])}; $_rYazi)',
          n * mk,
          [n, p * v / (0.082 * tc) * mk, v / 22.4 * mk, n * mk / 2, n * mk * 2],
          '$kelvin n = P·V / (R·T) = ${_t(p)}·${_t(v)} / (0,082·$tk) = '
          '${_t(n)} mol olur. Kütle ${_t(n)}·${_t(mk)} = ${_t(n * mk)} gramdır.',
          birim: 'g',
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 13. Kısmi basınç, mol kesri ve Graham difüzyon yasası
// ---------------------------------------------------------------------------

// (hafif gaz, ağır gaz, hız oranı = √(M_ağır / M_hafif))
const _grahamCiftleri = [
  ('He', 'CH₄', 2), ('H₂', 'O₂', 4), ('CH₄', 'SO₂', 2), ('He', 'SO₂', 4),
  ('O₂', 'HI', 2),
];

final _f13 = lmAile(
  'kim_kismi_basinc',
  'Kısmi basınç, mol kesri ve Graham difüzyon yasası',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final ikinci = c >= 5;
    switch (c % 5) {
      case 0:
        final n = [1 + a % 5, 1 + a ~/ 5, 1 + b % 4];
        final top = n[0] + n[1] + n[2];
        final u = 20 * (1 + b ~/ 4);
        final j = ikinci ? 1 : 0;
        final gaz = const ['He', 'Ne', 'Ar'][j];
        return sayisal(
          'Kapalı bir kapta ${n[0]} mol He, ${n[1]} mol Ne ve ${n[2]} mol Ar '
          'gazlarından oluşan karışımın toplam basıncı ${top * u} mmHg olarak '
          'ölçülüyor. Buna göre $gaz gazının kısmi basıncı kaç mmHg olur?',
          n[j] * u,
          [top * u ~/ 3, n[1 - j] * u, top * u - n[j] * u, n[2] * u, u],
          'Toplam mol sayısı $top olduğundan $gaz gazının mol kesri '
          '${n[j]}/$top olur. Kısmi basınç ${top * u}·${n[j]} / $top = '
          '${n[j] * u} mmHg bulunur.',
          positive: true,
        );
      case 1:
        final n1 = 1 + a % 5, n2 = 1 + a ~/ 5, top = n1 + n2;
        if (!ikinci) {
          final pt = top * (b + 1) / 20, p2 = n2 * (b + 1) / 20;
          final m1 = 4 * n1, m2 = 16 * n2;
          return _say(
            'Kapalı bir kapta $m1 gram He ve $m2 gram CH₄ gazları '
            'bulunmaktadır. Karışımın toplam basıncı ${_t(pt)} atm olduğuna '
            'göre CH₄ gazının kısmi basıncı kaç atm olur? '
            '(${_kut(['He', 'CH₄'])})',
            p2,
            [pt * m2 / (m1 + m2), pt - p2, pt / 2, pt * n2 / (n1 + 2 * n2)],
            'He: $m1 / 4 = $n1 mol, CH₄: $m2 / 16 = $n2 mol. CH₄ gazının mol '
            'kesri $n2/$top olduğundan kısmi basıncı ${_t(pt)}·$n2 / $top = '
            '${_t(p2)} atm bulunur.',
          );
        }
        // Mol sayıları onda bir adımlarla; her (a, b) ayrı bir çift verir.
        final h1 = 1 + a % 5 + 5 * (b % 4), h2 = 1 + a ~/ 5 + 5 * (b ~/ 4);
        final g1 = 2 * h1 / 10, g2 = 32 * h2 / 10;
        return kesirli(
          'Kapalı bir kapta ${_t(g1)} gram H₂ ve ${_t(g2)} gram O₂ gazları '
          'bulunmaktadır. Buna göre karışımdaki O₂ gazının mol kesri kaçtır? '
          '(${_kut(['H₂', 'O₂'])})',
          h2,
          h1 + h2,
          [(h1, h1 + h2), (16 * h2, h1 + 16 * h2), (h2, h1 + 2 * h2), (h2, 2 * h1 + h2)],
          'H₂: ${_t(g1)} / 2 = ${_t(h1 / 10)} mol, O₂: ${_t(g2)} / 32 = '
          '${_t(h2 / 10)} mol. O₂ gazının mol kesri ${_t(h2 / 10)} / '
          '${_t((h1 + h2) / 10)} = ${kesir(h2, h1 + h2)} olur.',
        );
      case 2:
        final v1 = 1 + a % 5, v2 = 1 + a ~/ 5, top = v1 + v2;
        final p = (1 + b % 4) / 10, q = (1 + b ~/ 4) / 10 + 0.05;
        final p1 = top * p, p2 = top * q;
        final son = v1 * p + v2 * q;
        final giris =
            'Sabit sıcaklıkta, $v1 L hacimli kapta ${_t(p1)} atm basınçta He '
            'gazı, $v2 L hacimli kapta ${_t(p2)} atm basınçta Ne gazı '
            'bulunmaktadır. Kaplar arasındaki musluk açılarak gazların '
            'karışması sağlanıyor.';
        if (!ikinci) {
          return _say(
            '$giris Son durumda toplam basınç kaç atm olur?',
            son,
            [(p1 + p2) / 2, p1 + p2, v1 * p, v2 * q, (p1 * v2 + p2 * v1) / top],
            'Toplam hacim $top L olur. P = (${_t(p1)}·$v1 + ${_t(p2)}·$v2) / '
            '$top = ${_t(son)} atm bulunur.',
          );
        }
        return _say(
          '$giris Son durumda Ne gazının kısmi basıncı kaç atm olur?',
          v2 * q,
          [son, p2 / 2, v1 * p, p2 * v1 / top, p2],
          'Ne gazı $v2 L hacimden $top L hacme yayılır. Kısmi basıncı '
          '${_t(p2)}·$v2 / $top = ${_t(v2 * q)} atm bulunur.',
        );
      default:
        final (hafif, agir, oran) = _grahamCiftleri[a % 5];
        final k = 5 + b + 20 * (a ~/ 5);
        final mh = _mk(hafif), ma = _mk(agir);
        final kut = _kut([hafif, agir]);
        final hiz =
            'Graham yasasına göre hız oranı √(${_t(ma)} / ${_t(mh)}) = $oran '
            'olur; $hafif gazı $oran kat hızlı yayılır.';
        if (c % 5 == 3) {
          final giris = 'Aynı sıcaklık ve basınçta, özdeş cam borularda';
          if (!ikinci) {
            return sayisal(
              '$giris $hafif gazı borunun diğer ucuna $k saniyede ulaşıyor. '
              'Aynı koşullarda $agir gazı aynı yolu kaç saniyede alır? ($kut)',
              oran * k,
              [k * ma ~/ mh, k * oran * oran, k + oran, k * (oran + 1)],
              '$hiz Süre hızla ters orantılı olduğundan $agir gazı yolu '
              '$k·$oran = ${oran * k} saniyede alır.',
              unit: 's',
              positive: true,
            );
          }
          return sayisal(
            '$giris $agir gazı borunun diğer ucuna ${oran * k} saniyede '
            'ulaşıyor. Aynı koşullarda $hafif gazı aynı yolu kaç saniyede alır? '
            '($kut)',
            k,
            [oran * oran * k, oran * k * mh ~/ ma, oran * k - oran, 2 * k],
            '$hiz Süre hızla ters orantılı olduğundan $hafif gazı yolu '
            '${oran * k} / $oran = $k saniyede alır.',
            unit: 's',
            positive: true,
          );
        }
        final boy = (oran + 1) * k;
        final uc = ikinci ? agir : hafif;
        final yanit = ikinci ? k : oran * k;
        return sayisal(
          'Aynı sıcaklıktaki $hafif ve $agir gazları, $boy cm uzunluğundaki '
          'cam borunun iki ucundan aynı anda gönderiliyor. Gazlar, $uc gazının '
          'gönderildiği uçtan kaç cm uzakta karşılaşır? ($kut)',
          yanit,
          [
            boy ~/ 2,
            boy - yanit,
            ikinci ? boy * mh ~/ (mh + ma) : boy * ma ~/ (mh + ma),
            boy ~/ oran,
            yanit + oran,
          ],
          '$hiz Aynı sürede alınan yollar $oran : 1 oranındadır. $uc gazı '
          '$boy·${ikinci ? 1 : oran} / ${oran + 1} = $yanit cm yol alır.',
          unit: 'cm',
          positive: true,
        );
    }
  },
  exam: ExamKind.ayt,
  lesson: 'Kimya',
);

// ---------------------------------------------------------------------------
// 14. Molarite, kütlece yüzde derişim ve ppm
// ---------------------------------------------------------------------------

// Suda çok çözünen maddeler.
const _cozunenler = [
  ('NaOH', 'sodyum hidroksit'), ('KOH', 'potasyum hidroksit'),
  ('NaCl', 'sodyum klorür'), ('KNO₃', 'potasyum nitrat'),
  ('C₆H₁₂O₆', 'glikoz'), ('CaCl₂', 'kalsiyum klorür'),
  ('NaNO₃', 'sodyum nitrat'), ('MgSO₄', 'magnezyum sülfat'),
  ('NH₄Cl', 'amonyum klorür'), ('KBr', 'potasyum bromür'),
  ('AgNO₃', 'gümüş nitrat'), ('CaBr₂', 'kalsiyum bromür'),
  ('C₁₂H₂₂O₁₁', 'sakkaroz'), ('NH₄NO₃', 'amonyum nitrat'),
  ('KI', 'potasyum iyodür'), ('MgCl₂', 'magnezyum klorür'),
  ('NaBr', 'sodyum bromür'), ('Ca(NO₃)₂', 'kalsiyum nitrat'),
  ('Al(NO₃)₃', 'alüminyum nitrat'), ('NaI', 'sodyum iyodür'),
  ('HNO₃', 'nitrik asit'), ('H₂SO₄', 'sülfürik asit'),
  ('KCl', 'potasyum klorür'), ('ZnSO₄', 'çinko sülfat'),
  ('Mg(NO₃)₂', 'magnezyum nitrat'),
];

final _f14 = lmAile(
  'kim_derisim',
  'Molarite, kütlece yüzde derişim ve ppm',
  Topic.chemistry,
  Difficulty.medium,
  BloomLevel.uygulama,
  (a, b, c) {
    final (f, ad) = _cozunenler[a];
    final mk = _mk(f);
    final madde = '$ad ($f)';
    final w = c ~/ 5;
    switch (c % 5) {
      case 0:
      case 1:
        final hacim = const [200, 250, 400, 500, 1000, 2000][(a + 3 * w) % 6];
        final n = (b + 1) / 50, m = n * mk;
        final der = n * 1000 / hacim;
        final kut = _kut([f]);
        if (c % 5 == 0) {
          return _say(
            'Kütlesi ${_t(m)} gram olan $madde saf suda çözülerek $hacim mL '
            'çözelti hazırlanıyor. Çözeltinin molar derişimi kaç mol/L olur? '
            '($kut)',
            der,
            [n, m * 1000 / hacim / 100, n * hacim / 1000, der * 2, der / 2],
            'n = ${_t(m)} / ${_t(mk)} = ${_t(n)} mol ve V = ${_t(hacim / 1000)} '
            'L olur. Derişim ${_t(n)} / ${_t(hacim / 1000)} = ${_t(der)} mol/L '
            'bulunur.',
            birim: 'mol/L',
          );
        }
        return _say(
          'Derişimi ${_t(der)} mol/L olan $hacim mL $madde çözeltisi hazırlamak '
          'için kaç gram $f gerekir? ($kut)',
          m,
          [der * mk, m * 2, m / 2, n, m * 10],
          'n = ${_t(der)}·${_t(hacim / 1000)} = ${_t(n)} mol olur. Kütle '
          '${_t(n)}·${_t(mk)} = ${_t(m)} gram bulunur.',
          birim: 'g',
        );
      case 3:
        final iyon = const ['Ca²⁺', 'Mg²⁺', 'Na⁺', 'Cl⁻', 'NO₃⁻'][a % 5];
        final kg = const [0.5, 2, 2.5, 4, 5][a ~/ 5];
        final ppm = 2 * (b + 1), mg = ppm * kg;
        const tanim =
            'ppm, 1 kg çözeltideki çözünenin miligram cinsinden kütlesidir.';
        if (w == 0) {
          return _say(
            'Kütlesi ${_t(kg)} kg olan bir içme suyu örneğinde ${_t(mg)} mg '
            '$iyon iyonu bulunmaktadır. Bu iyonun sudaki derişimi kaç ppm '
            'olur?',
            ppm,
            [mg * kg, mg, ppm * 10, ppm / 10, mg / (kg * 10)],
            '$tanim Derişim ${_t(mg)} / ${_t(kg)} = $ppm ppm bulunur.',
          );
        }
        return _say(
          'Bir içme suyu örneğinde $iyon iyonu derişimi $ppm ppm olarak '
          'ölçülmüştür. Bu suyun ${_t(kg)} kg kütleli örneğinde kaç mg $iyon '
          'iyonu bulunur?',
          mg,
          [ppm / kg, ppm, mg * 10, mg / 10, ppm * kg * kg],
          '$tanim Örnekte $ppm·${_t(kg)} = ${_t(mg)} mg iyon bulunur.',
          birim: 'mg',
        );
      default:
        final top = 40 * (a + 2), p = 2 + b;
        final ms = top * p / 100, su = top - ms;
        if (c % 5 == 2) {
          if (w == 0) {
            return _say(
              '${_t(ms)} gram $madde, ${_t(su)} gram saf suda tamamen '
              'çözünüyor. Oluşan çözelti kütlece yüzde kaçlıktır?',
              p,
              [100 * ms / su, 100 - p, p / 2, p * 2],
              on: '%',
              'Çözelti kütlesi ${_t(ms)} + ${_t(su)} = $top gramdır. Kütlece '
              'yüzde ${_t(ms)} / $top·100 = %$p olur.',
            );
          }
          return _say(
            'Kütlesi $top gram olan bir $madde çözeltisinde ${_t(ms)} gram '
            'çözünen madde bulunmaktadır. Çözeltinin kütlece yüzde derişimi '
            'kaçtır?',
            p,
            [100 * ms / su, 100 * ms / (top + ms), 100 - p, p / 2],
            on: '%',
            'Kütlece yüzde ${_t(ms)} / $top·100 = %$p olur.',
          );
        }
        if (w == 0) {
          return _say(
            'Kütlece %$p oranında $madde içeren $top gram çözeltide kaç gram '
            'su bulunur?',
            su,
            [ms, top * 100 / (100 + p), top - p, su / 2],
            'Çözünen kütlesi $top·$p / 100 = ${_t(ms)} gramdır. Su kütlesi '
            '$top − ${_t(ms)} = ${_t(su)} gram olur.',
            birim: 'g',
          );
        }
        return _say(
          'Kütlece %$p oranında $madde içeren $top gram çözelti hazırlamak '
          'için kaç gram çözünen madde tartılmalıdır?',
          ms,
          [su, top * p / (100 + p), top / p, ms * 2],
          'Çözünen kütlesi $top·$p / 100 = ${_t(ms)} gram olur.',
          birim: 'g',
        );
    }
  },
  exam: ExamKind.tyt,
  lesson: 'Kimya',
);

final lmKimya = <AdvancedFamily>[
  _f01, _f02, _f03, _f04, _f05, _f06, _f07, _f08, _f09, _f10, _f11, _f12,
  _f13, _f14,
  for (var n = 15; n <= 20; n++) _gecici(n),
];
