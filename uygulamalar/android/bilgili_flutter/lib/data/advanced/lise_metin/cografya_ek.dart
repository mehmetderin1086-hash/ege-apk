// Lise coğrafya ek aileleri: Dünya'nın hareketleri, güneş ışınları, iklim, yer
// şekilleri, kayaçlar, toprak, bitki örtüsü ile Türkiye'nin beşerî ve ekonomik
// coğrafyası. Hesap aileleri koordinatlarla, olgu aileleri çizelge seçkileriyle üretilir.
import 'ortak.dart';

// ───────────────────────────── Ortak yardımcılar ─────────────────────────────

const _rakam = ['I', 'II', 'III', 'IV'];

/// Dakikayı 24 saatlik gösterime çevirir: 574 → 09:34.
String _saat(int dk) {
  final m = dk % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Dakikayı "2 saat 24 dakika" biçiminde yazar.
String _sure(int dk) {
  final h = dk ~/ 60, m = dk % 60;
  if (h == 0) return '$m dakika';
  if (m == 0) return '$h saat';
  return '$h saat $m dakika';
}

/// Sayıyı gerçek eksi işaretiyle yazar.
String _n(num x, [int d = 2]) => tr(x, d).replaceFirst('-', '−');

/// İşlem içinde negatif sayıyı parantezle yazar: −5 → (−5).
String _p(int x) => x < 0 ? '(−${-x})' : '$x';

/// Dakika cinsinden açıyı derece ve dakikayla yazar: 2787 → 46°27′.
String _aci(int dk) {
  final d = dk ~/ 60, m = dk % 60;
  return m == 0 ? '$d°' : '$d°${m.toString().padLeft(2, '0')}′';
}

/// İşaretli enlemi (kuzey artı, dakika cinsinden) kök içinde yazar.
String _enlemAd(int dk) => '${_aci(dk.abs())} ${dk > 0 ? 'kuzey' : 'güney'}';

/// İşaretli enlemi seçenek olarak yazar.
String _enlemSecenek(int dk) =>
    '${_aci(dk.abs())} ${dk > 0 ? 'Kuzey' : 'Güney'}';

String _liste(List<String> x) =>
    [for (var p = 0; p < x.length; p++) '${_rakam[p]}. ${x[p]}'].join('\n');

/// Maskedeki numaraları (bit 0 → I) seçenek metnine çevirir.
String _kume(int maske, int k) {
  final s = [
    for (var p = 0; p < k; p++)
      if ((maske >> p) & 1 == 1) _rakam[p],
  ];
  if (s.length == 1) return 'Yalnız ${s[0]}';
  return '${s.sublist(0, s.length - 1).join(', ')} ve ${s.last}';
}

/// Sıra numarasından türetilen karışık bir tam sayı. Ara değerler 2⁵³ altında
/// kaldığından her platformda aynı sonucu verir.
int _karisik(int x) {
  final h = (x * 7919 + 104729) % 1000003;
  return ((h * h + x * 31) % 1000003) * 48271 % 2147483647;
}

/// “Hangileri?” sorusu; doğru yanıt [maske] ile verilen alt kümedir. Çeldirici
/// alt kümeler doğru yanıttan bağımsız, karışık bir sırayla seçilir: seçenekler
/// doğru yanıtın tek öncüllük değişikliklerinden oluşursa öncüllerin seçeneklerde
/// kaç kez geçtiği sayılarak doğru yanıt bulunabilirdi.
AdvancedItem _hangileri(String kok, int maske, int k, String aciklama, int i) {
  final tum = (1 << k) - 1;
  int sirala(int x, int y) {
    final d = _karisik(16 * i + x).compareTo(_karisik(16 * i + y));
    return d != 0 ? d : x.compareTo(y);
  }

  final sira = [for (var m = 1; m <= tum; m++) m]..sort(sirala);
  return secenekli(
    kok,
    _kume(maske, k),
    sira.where((m) => m != maske).map((m) => _kume(m, k)),
    aciklama,
  );
}

/// [tablo] içinden [k] ögeli seçkilerin, [n] sıraya eşit aralıkla yayılmış
/// [s] numaralısını verir. Seçkiler farklı olduğundan kökler de farklıdır.
List<T> _secki<T>(List<T> tablo, int k, int s, int n) {
  final toplam = kombinasyonSayisi(tablo.length, k);
  if (toplam < n) throw StateError('Yetersiz seçki: $toplam < $n');
  final u = kombinasyon(tablo, k, s * toplam ~/ n, spread: false);
  if (k == 3) {
    final d = ucluDizilimler[s % 6];
    return [u[d[0]], u[d[1]], u[d[2]]];
  }
  final r = s % k;
  return [...u.sublist(r), ...u.sublist(0, r)];
}

/// [_uygunSecki] için ad başına bir kez çıkarılan uygun seçkiler (çizelgedeki
/// sıra numaralarıyla, sözlük sırasında).
final _uygunSeckiler = <String, List<List<int>>>{};

/// [tablo] içinden [uygun] koşulunu sağlayan [k] ögeli seçkilerin, [n] sıraya
/// eşit aralıkla yayılmış [s] numaralısını verir; ögelerin dizilişi [_secki]
/// ile aynıdır. [ad] çizelge ile koşulu birlikte adlandırır.
List<T> _uygunSecki<T>(
  String ad,
  List<T> tablo,
  int k,
  int s,
  int n,
  bool Function(List<T> x) uygun,
) {
  final liste = _uygunSeckiler.putIfAbsent(ad, () {
    final sira = [for (var q = 0; q < tablo.length; q++) q];
    final toplam = kombinasyonSayisi(tablo.length, k);
    return [
      for (var t = 0; t < toplam; t++)
        if (uygun([
          for (final q in kombinasyon(sira, k, t, spread: false)) tablo[q],
        ]))
          kombinasyon(sira, k, t, spread: false),
    ];
  });
  if (liste.length < n) {
    throw StateError('Yetersiz uygun seçki ($ad): ${liste.length} < $n');
  }
  final u = [for (final q in liste[s * liste.length ~/ n]) tablo[q]];
  if (k == 3) {
    final d = ucluDizilimler[s % 6];
    return [u[d[0]], u[d[1]], u[d[2]]];
  }
  final r = s % k;
  return [...u.sublist(r), ...u.sublist(0, r)];
}

/// Seçkideki ögelerin etiketleri birbirinden farklıdır. Ögeleri bir türün
/// tanımı olan çizelgelerde sıralı eşleştirme sorusu aynı türü iki öncülle
/// tanımlamasın diye kullanılır.
bool _farkliEtiket(List<_Etiketli> x) {
  for (var p = 0; p < x.length; p++) {
    for (var q = p + 1; q < x.length; q++) {
      if (x[p].$2 == x[q].$2) return false;
    }
  }
  return true;
}

/// Sıralı etiket yanıtı (üç ya da dört konum) için dengeli çeldiriciler. Her
/// konuma doğrusundan farklı bir etiket (havuzdaki komşu etiketlerden biri)
/// atanır; her çeldirici doğru etiketi yalnız bir konumda (dört konumda son iki
/// konumu üçüncü çeldirici) korur. Böylece her konumda doğru etiket ile seçilen
/// yanlış etiket ikişer seçenekte geçer ve doğru yanıt, seçeneklerin
/// birbirine benzerliğinden çıkarılamaz. Her çeldirici en az iki konumda
/// kesin yanlıştır ve üç çeldirici birbirinden farklıdır. [gecerli] verilirse
/// (doğru yanıtların uyduğu bir kural, ör. etiketlerin farklı olması) her
/// çeldirici de bu kurala uyar: önce yukarıdaki komşu etiket, uymazsa sıradaki
/// komşular denenir. Böylece kuralı bilen öğrenci çeldirici eleyemez.
List<String> _siraYanlis(
  List<String> dogru,
  List<String> havuz,
  int s, {
  bool Function(List<String> x)? gecerli,
}) {
  final k = dogru.length, n = havuz.length;
  final aday = <List<String>>[];
  for (var p = 0; p < k; p++) {
    final yer = havuz.indexOf(dogru[p]);
    final ilk = n == 2 ? 1 : const [1, -1, 2, -2][(s + p) % 4];
    final l = <String>[];
    for (final kay in [
      ilk,
      for (var d = 1; d < n; d++) ...[d, -d],
    ]) {
      final e = havuz[(yer + kay + 2 * n) % n];
      if (e != dogru[p] && !l.contains(e)) l.add(e);
    }
    aday.add(l);
  }
  List<List<String>> celdiriciler(List<String> alt) => [
    for (var r = 0; r < 3; r++)
      [for (var p = 0; p < k; p++) (p < 3 ? p : 2) == r ? dogru[p] : alt[p]],
  ];
  final alt = <String>[];
  bool ara(int p) {
    if (p == k) {
      return gecerli == null || celdiriciler(alt).every(gecerli);
    }
    for (final e in aday[p]) {
      alt.add(e);
      if (ara(p + 1)) return true;
      alt.removeLast();
    }
    return false;
  }

  if (!ara(0)) throw StateError('Kurala uyan çeldirici yok: $dogru');
  return [for (final c in celdiriciler(alt)) c.join(' – ')];
}

/// Etiketleri birbirinden farklı bir dizi.
bool _farkliDizi(List<String> x) => x.toSet().length == x.length;

/// Dört konumlu sıralı yanıtın döndürmeleriyle kurulan çeldiriciler: her
/// seçenek aynı etiketleri içerir, yalnız öncüllere dağılımı farklıdır.
List<String> _dondurmeYanlis(List<String> dogru) => [
  for (var r = 1; r < dogru.length; r++)
    [...dogru.sublist(r), ...dogru.sublist(0, r)].join(' – '),
];

/// (öge, etiket, grup) çizelgesi.
typedef _Etiketli = (String, String, String?);

/// Etiketli olgu sorusu. Çift [j] için sıralı eşleştirme, tek [j] için
/// “hangileri” sorusu üretir; seçkideki bütün ögelerin grubu varsa “hangileri”
/// sorusu gruba göre, yoksa etikete göre sorulur. Aynı seçki iki soru türünde
/// kullanıldığından kökler [n] vaka için farklıdır. [celisir], bir grubun
/// sorulduğu soruda başka bir grubun ögesi bulunursa sorunun tartışmalı olacağı
/// grup çiftlerini verir (ör. “karasal iklim” sorusunda sert karasal ögesi);
/// böyle bir seçkide seçkideki başka bir grup sorulur. [siraUygun] verilirse
/// sıralı eşleştirme seçkileri (ve [uygunHer] doğruysa “hangileri” seçkileri
/// de) yalnız bu koşulu sağlayan seçkiler arasından alınır; [uygunAd] bu
/// seçkilerin önbellek adıdır. [celdiriciUygun], doğru yanıtların uyduğu bir
/// etiket kuralını çeldiricilere de uygular; [siraCeldirici] verilirse sıralı
/// eşleştirmenin çeldiricileri onunla kurulur.
AdvancedItem _etiketli(
  int j,
  int n,
  List<_Etiketli> tablo,
  List<String> havuz, {
  int k = 3,
  String giris = '',
  required String siraSoru,
  required String Function(String hedef, bool grup) hangiSoru,
  required String Function(List<_Etiketli> x) aciklama,
  bool grupHer = true,
  bool Function(String hedef, String grup)? celisir,
  String Function(String hedef, bool grup)? olumsuzSoru,
  String uygunAd = '',
  bool Function(List<_Etiketli> x)? siraUygun,
  bool uygunHer = false,
  bool Function(List<String> x)? celdiriciUygun,
  List<String> Function(List<String> dogru)? siraCeldirici,
}) {
  final s = j ~/ 2;
  final x = siraUygun != null && (j.isEven || uygunHer)
      ? _uygunSecki(uygunAd, tablo, k, s, (n + 1) ~/ 2, siraUygun)
      : _secki(tablo, k, s, (n + 1) ~/ 2);
  final etiket = [for (final e in x) e.$2];
  final liste = '$giris${_liste([for (final e in x) e.$1])}\n';
  final acik = aciklama(x);
  if (j.isEven) {
    return secenekli(
      '$liste$siraSoru',
      etiket.join(' – '),
      siraCeldirici != null
          ? siraCeldirici(etiket)
          : _siraYanlis(etiket, havuz, s, gecerli: celdiriciUygun),
      acik,
    );
  }
  var grup = x.every((e) => e.$3 != null) && (grupHer || s.isEven);
  String? grupHedef;
  for (var r = 0; grup && r < k && grupHedef == null; r++) {
    final h = x[(s + r) % k].$3!;
    if (celisir == null || !x.any((e) => e.$3 != h && celisir(h, e.$3!))) {
      grupHedef = h;
    }
  }
  if (grupHedef == null) grup = false;
  final hedef = grupHedef ?? etiket[s % k];
  var maske = 0;
  for (var p = 0; p < k; p++) {
    if ((grup ? x[p].$3 : x[p].$2) == hedef) maske |= 1 << p;
  }
  // Etiketi çok olan çizelgelerde ögelerin etiketleri çoğunlukla farklıdır ve
  // olumlu sorunun yanıtı tek öncül olur; “Yalnız …” seçeneğini seçmek doğru
  // yanıtı sık verirdi. [olumsuzSoru] verilen ailelerde seçkilerin yarısında
  // olumsuz soru sorulur (bütün öncüller hedefe uyuyorsa soru olumlu kalır).
  final tum = (1 << k) - 1;
  if (olumsuzSoru != null && (s ~/ 2).isOdd && maske != tum) {
    return _hangileri(
      '$liste${olumsuzSoru(hedef, grup)}',
      tum ^ maske,
      k,
      acik,
      s,
    );
  }
  return _hangileri('$liste${hangiSoru(hedef, grup)}', maske, k, acik, s);
}

/// (özne, doğru yüklem, yanlış yüklemler) önermesi.
typedef _Onerme = (String, String, List<String>);

/// Üç önermenin hangilerinin doğru olduğunu soran soru. [j] numarası üçlü
/// seçkiyi, doğruluk maskesini ve yanlış yüklemin seçimini birebir belirler.
AdvancedItem _dogruYanlis(
  int j,
  List<_Onerme> tablo,
  String soru, {
  String giris = '',
}) {
  final toplam = kombinasyonSayisi(tablo.length, 3);
  final t = j % toplam, r = j ~/ toplam;
  if (r >= 13) throw StateError('Yetersiz önerme çizelgesi');
  final u = kombinasyon(tablo, 3, t, spread: false);
  final d = ucluDizilimler[t % 6];
  final x = [u[d[0]], u[d[1]], u[d[2]]];
  final maske = r < 7 ? 1 + (t + r) % 7 : 1 + (t + r) % 6;
  final kay = r ~/ 7;
  final cumle = <String>[], acik = <String>[];
  for (var p = 0; p < 3; p++) {
    final e = x[p];
    final dogruMu = (maske >> p) & 1 == 1;
    cumle.add('${e.$1} ${dogruMu ? e.$2 : e.$3[(t + p + kay) % e.$3.length]}');
    acik.add(
      dogruMu
          ? '${_rakam[p]}. öncül doğrudur.'
          : '${_rakam[p]}. öncül yanlıştır; doğrusu: ${e.$1} ${e.$2}',
    );
  }
  return _hangileri(
    '$giris${_liste(cumle)}\n$soru',
    maske,
    3,
    acik.join(' '),
    j,
  );
}

// ─────────────────── 1 · Öğle vakti güneş ışınlarının geliş açısı ──────────

// (tarih, ekli yazım, güneş ışınlarının dik geldiği enlem; dakika, kuzey artı)
const _gunler = [
  ('21 Mart', "21 Mart'ta", 0),
  ('21 Haziran', "21 Haziran'da", 1407),
  ('23 Eylül', "23 Eylül'de", 0),
  ('21 Aralık', "21 Aralık'ta", -1407),
];

// Dakikalar 5'in katıdır: 23°27′ ve 66°33′ değerlerine denk gelen ya da iki
// yerin açısını eşitleyen enlem oluşmaz.
const _dakikalar = [5, 10, 15, 20, 25, 35, 40, 45, 50, 55];

const _aciKural =
    'Öğle vakti geliş açısı, 90° − (yerin enlemi ile güneş ışınlarının dik '
    'geldiği enlem arasındaki fark) bağıntısıyla bulunur.';

String _dik(int t) => switch (t) {
  1 =>
    "Güneş ışınlarının 21 Haziran'da öğle vakti 23°27′ kuzey paraleline (Yengeç "
        'Dönencesi) dik geldiği kabul edilmektedir.',
  3 =>
    "Güneş ışınlarının 21 Aralık'ta öğle vakti 23°27′ güney paraleline (Oğlak "
        'Dönencesi) dik geldiği kabul edilmektedir.',
  _ =>
    "Güneş ışınlarının ${_gunler[t].$2} öğle vakti Ekvator'a dik geldiği kabul "
        'edilmektedir.',
};

String _dikAd(int t) => switch (t) {
  1 => '23°27′ kuzey paraleline',
  3 => '23°27′ güney paraleline',
  _ => "Ekvator'a",
};

/// Yerin, güneş ışınlarının dik geldiği paralele enlem farkını adım adım yazar.
String _uzaklikYaz(int fi, int dl) {
  final u = (fi - dl).abs();
  if (dl == 0) return "yerin Ekvator'a uzaklığı ${_aci(u)}";
  if ((fi > 0) == (dl > 0)) {
    return fi.abs() > dl.abs()
        ? 'enlem farkı ${_aci(fi.abs())} − 23°27′ = ${_aci(u)}'
        : 'enlem farkı 23°27′ − ${_aci(fi.abs())} = ${_aci(u)}';
  }
  return 'yer ile dik gelinen paralel farklı yarım kürelerde olduğundan enlem farkı '
      '${_aci(fi.abs())} + 23°27′ = ${_aci(u)}';
}

AdvancedItem _gunesAcisi(int a, int b, int c) {
  final bicim = c % 3, q = c ~/ 3;
  if (bicim == 0) {
    // Tek yerin açısı. 21 Mart ile 23 Eylül'de ve ayna tarihlerde derecelerin
    // tek-çift ayrımı aynı hesabın iki kez sorulmasını önler.
    final t = q;
    final fi =
        (b.isEven ? 1 : -1) * ((3 + 2 * a + t ~/ 2) * 60 + _dakikalar[b ~/ 2]);
    final dl = _gunler[t].$3;
    final u = (fi - dl).abs(), aci = 5400 - u;
    final yanlis = dl == 0
        ? [
            5400 - (fi - 1407).abs(),
            fi.abs(),
            5400 - fi.abs() - 1407,
            5400 - (fi + 1407).abs(),
          ]
        : [5400 - (fi + dl).abs(), u, 5400 - fi.abs()];
    return secenekli(
      '${_dik(t)} $_aciKural Buna göre ${_enlemAd(fi)} paralelindeki bir yerde '
          '${_gunler[t].$2} öğle vakti güneş ışınlarının geliş açısı kaçtır?',
      _aci(aci),
      [
        ...yanlis,
        aci + 60,
        aci - 60,
        aci + 120,
      ].where((x) => x > 0 && x <= 5400).map(_aci),
      '${_gunler[t].$1} günü güneş ışınları ${_dikAd(t)} dik gelir; ${_uzaklikYaz(fi, dl)} '
          'olur. Geliş açısı 90° − ${_aci(u)} = ${_aci(aci)} bulunur.',
    );
  }
  if (bicim == 1) {
    // İki yerin açı farkı. Aynı yarım küredeki L merkezi K merkezinden en az 5°
    // uzaktadır; K tek, L çift dereceli olduğundan açılar hiç eşitlenmez.
    // Kökü (a, b) ile tarih belirler; dakikalar kökün tekliğini etkilemez.
    final kd = 3 + 2 * a, j = b ~/ 2;
    final ld = b.isEven
        ? (kd + 5 + 4 * j > 58 ? kd + 5 + 4 * j - 56 : kd + 5 + 4 * j)
        : 4 + 4 * j;
    final isaret = b.isOdd ? -1 : 1;
    var km = _dakikalar[(a + 3 * b) % 10],
        lm = _dakikalar[(3 * a + b + 5) % 10];
    int farkAB(int k, int l, int d) => ((k - d).abs() - (l - d).abs()).abs();
    var t = (q + b) % 4;
    // İki merkez dik gelinen paralele neredeyse eşit uzaklıkta kalırsa fark 1°
    // altına düşer. Ekinokslarda dakikaların yer değiştirmesi farkı 1° üzerine
    // çıkarır; gündönümlerinde bu (a, b) için kullanılmayan tarih alınır.
    if (farkAB(kd * 60 + km, isaret * (ld * 60 + lm), _gunler[t].$3) < 60) {
      if (_gunler[t].$3 == 0) {
        final g = km;
        km = lm;
        lm = g;
      } else {
        t = (b + 3) % 4;
      }
    }
    final dl = _gunler[t].$3;
    final k = kd * 60 + km, l = isaret * (ld * 60 + lm);
    int fark(int d) => farkAB(k, l, d);
    final uk = (k - dl).abs(), ul = (l - dl).abs();
    final dogru = fark(dl);
    final ak = 5400 - uk, al = 5400 - ul;
    return secenekli(
      '${_dik(t)} $_aciKural K merkezi ${_enlemAd(k)}, L merkezi ${_enlemAd(l)} '
          'paralelinde bulunmaktadır. Buna göre ${_gunler[t].$2} öğle vakti bu iki merkezde '
          'güneş ışınlarının geliş açıları arasındaki fark kaçtır?',
      _aci(dogru),
      [
        (k - l).abs(),
        fark(dl == 0 ? 1407 : -dl),
        fark(dl == 0 ? -1407 : 0),
        uk + ul,
        dogru + 60,
        dogru - 60,
        dogru + 120,
        dogru + 180,
        // Yanıt en az 1° olduğundan 1° altındaki çeldiriciler de alınmaz.
      ].where((x) => x >= 60 && x < 5400).map(_aci),
      '${_gunler[t].$1} günü güneş ışınları ${_dikAd(t)} dik gelir. Geliş açısı K '
          'merkezinde 90° − ${_aci(uk)} = ${_aci(ak)}, L merkezinde 90° − ${_aci(ul)} = '
          '${_aci(al)} olur. Fark ${_aci(ak > al ? ak : al)} − ${_aci(ak > al ? al : ak)} = '
          '${_aci(dogru)} bulunur.',
    );
  }
  // Açısı verilen yerin enlemi.
  final t = (q + b) % 4;
  final dl = _gunler[t].$3;
  final fi = (b.isEven ? 1 : -1) * ((2 + 2 * a) * 60 + _dakikalar[b ~/ 2]);
  final u = (fi - dl).abs(), aci = 5400 - u, m = fi.abs();
  final String yer, yol;
  if (dl == 0) {
    yer = fi > 0 ? "Kuzey Yarım Küre'deki" : "Güney Yarım Küre'deki";
    yol =
        "Ekvator'a ${_aci(u)} uzaklıktaki bu yer ${fi > 0 ? 'Kuzey' : 'Güney'} Yarım "
        "Küre'de olduğundan enlemi ${_enlemSecenek(fi)} olur.";
  } else {
    final kuzeyDik = dl > 0;
    final ayni = (fi > 0) == kuzeyDik;
    if (ayni && m > 1407) {
      yer = kuzeyDik
          ? "Yengeç Dönencesi'nin kuzeyindeki"
          : "Oğlak Dönencesi'nin güneyindeki";
      yol =
          'Yer dönencenin kutup yönünde olduğundan enlemi 23°27′ + ${_aci(u)} = '
          '${_enlemSecenek(fi)} olur.';
    } else if (ayni) {
      yer = kuzeyDik
          ? 'Ekvator ile Yengeç Dönencesi arasındaki'
          : 'Ekvator ile Oğlak Dönencesi arasındaki';
      yol =
          'Yer Ekvator ile dönence arasında olduğundan enlemi 23°27′ − ${_aci(u)} = '
          '${_enlemSecenek(fi)} olur.';
    } else {
      yer = kuzeyDik ? "Güney Yarım Küre'deki" : "Kuzey Yarım Küre'deki";
      yol =
          'Yer öbür yarım kürede olduğundan enlemi ${_aci(u)} − 23°27′ = '
          '${_enlemSecenek(fi)} olur.';
    }
  }
  final sgn = fi > 0 ? 1 : -1;
  return secenekli(
    '${_dik(t)} $_aciKural ${_gunler[t].$2} öğle vakti $yer bir yerde güneş ışınlarının '
        'geliş açısı ${_aci(aci)} olarak ölçülmüştür. Bu yerin enlemi kaçtır?',
    _enlemSecenek(fi),
    [u, (u - 1407).abs(), u + 1407, aci, m + 60, m - 60, m + 120]
        .where((x) => x > 0 && x < 5400 && x != m)
        .map((x) => _enlemSecenek(sgn * x)),
    '90° − ${_aci(aci)} = ${_aci(u)} olduğundan yer, güneş ışınlarının dik geldiği '
        'paralelden ${_aci(u)} uzaklıktadır. $yol',
  );
}

final _f01 = lmAile(
  'cg_gunes_acisi',
  'Öğle vakti güneş ışınlarının geliş açısı',
  Topic.geography,
  Difficulty.medium,
  BloomLevel.uygulama,
  _gunesAcisi,
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
  shortAnswer: false,
);

// ───────────── 2 · Gün uzunluğu, gölge boyu ve güneşin doğuş saati ─────────

const _klm = ['K', 'L', 'M'];

AdvancedItem _gunSuresi(int a, int b, int c) {
  final bicim = c % 3, q = c ~/ 3;
  // Birinci yer tam dereceli kuzey, ikinci 15 dakikalı güney (1°15′ … 58°15′),
  // üçüncü 30 dakikalı kuzey enlemindedir; dakikalar farklı olduğundan hiçbir
  // tarihte iki yerin açısı eşitlenmez. Güneydeki yer Oğlak Dönencesi'nin iki
  // yanına da düşer.
  final yerler = [
    (2 + 2 * a) * 60,
    -((1 + 3 * b) * 60 + 15),
    (31 + (7 * a + 3 * b) % 22) * 60 + 30,
  ];
  final d = ucluDizilimler[(a + 2 * b + c) % 6];
  final x = [for (final j in d) yerler[j]];
  // Anahtarı büyükten küçüğe dizer.
  List<int> azalan(int Function(int v) f) =>
      [0, 1, 2]..sort((p, r) => f(x[r]).compareTo(f(x[p])));
  String yaz(List<int> s) => s.map((p) => _klm[p]).join(' – ');
  final giris =
      'Aynı meridyen üzerinde bulunan K merkezi ${_enlemAd(x[0])}, L merkezi '
      '${_enlemAd(x[1])}, M merkezi ${_enlemAd(x[2])} paralelindedir.';
  final List<int> dogru;
  final List<List<int>> hatalar;
  final String soru, aciklama;
  if (bicim == 0) {
    final t = q, dl = _gunler[t].$3;
    dogru = azalan((v) => (v - dl).abs());
    hatalar = [
      dogru.reversed.toList(),
      dl == 0 ? azalan((v) => v) : azalan((v) => v.abs()),
      dl == 0 ? azalan((v) => (v - 1407).abs()) : azalan((v) => v),
    ];
    soru =
        '${_dik(t)} Buna göre ${_gunler[t].$2} öğle vakti bu merkezlerde aynı boydaki '
        'cisimlerin gölge boylarının uzundan kısaya doğru sıralanışı hangisidir?';
    final acilar = [
      for (var p = 0; p < 3; p++)
        '${_klm[p]} merkezinde ${_aci(5400 - (x[p] - dl).abs())}',
    ];
    aciklama =
        '${_gunler[t].$1} günü güneş ışınları ${_dikAd(t)} dik gelir. Öğle vakti '
        'geliş açıları ${acilar.join(', ')} olur. Geliş açısı küçüldükçe gölge uzadığından '
        'sıralama ${yaz(dogru)} olur.';
  } else {
    // Gündüz süresi ve güneşin doğuşu kuzeye gidildikçe 21 Haziran'da uzar
    // (erkene kayar), 21 Aralık'ta kısalır (geçe kayar).
    final kuzeyOnce = switch ((bicim, q)) {
      (1, 0) || (1, 2) || (2, 0) => true,
      _ => false,
    };
    dogru = kuzeyOnce ? azalan((v) => v) : azalan((v) => -v);
    hatalar = [
      dogru.reversed.toList(),
      azalan((v) => v.abs()),
      azalan((v) => -v.abs()),
    ];
    final tarih = (bicim == 1 && q == 0) || (bicim == 2 && q != 1)
        ? "21 Haziran'da"
        : "21 Aralık'ta";
    soru = switch ((bicim, q)) {
      (1, 2) =>
        'Buna göre $tarih bu merkezlerin gece sürelerinin uzundan kısaya doğru '
            'sıralanışı hangisidir?',
      (1, _) =>
        'Buna göre $tarih bu merkezlerin gündüz sürelerinin uzundan kısaya doğru '
            'sıralanışı hangisidir?',
      (_, 2) =>
        'Buna göre $tarih bu merkezlerde güneşin yerel saate göre batış saatlerinin '
            'erkenden geçe doğru sıralanışı hangisidir?',
      _ =>
        'Buna göre $tarih bu merkezlerde güneşin yerel saate göre doğuş saatlerinin '
            'erkenden geçe doğru sıralanışı hangisidir?',
    };
    final kural = tarih.startsWith('21 Haziran')
        ? "21 Haziran'da kuzeye gidildikçe gündüz süresi uzar, gece süresi kısalır"
        : "21 Aralık'ta kuzeye gidildikçe gündüz süresi kısalır, gece süresi uzar";
    final ek = switch ((bicim, q)) {
      (2, 2) =>
        '; gündüzü kısa olan yerde güneş yerel saate göre daha erken batar',
      (2, _) =>
        '; gündüzü uzun olan yerde güneş yerel saate göre daha erken doğar',
      _ => '',
    };
    aciklama =
        '$kural$ek. Merkezler kuzeyden güneye ${yaz(azalan((v) => v))} biçiminde '
        'dizildiğinden sıralama ${yaz(dogru)} olur.';
  }
  final hepsi = [for (final p in ucluDizilimler) yaz(p)];
  final kay = (a + b) % 6;
  return secenekli('$giris $soru', yaz(dogru), [
    ...hatalar.map(yaz),
    ...hepsi.sublist(kay),
    ...hepsi.sublist(0, kay),
  ], aciklama);
}

final _f02 = lmAile(
  'cg_gun_suresi',
  'Enlem ve tarihe göre gün uzunluğu ve gölge boyu',
  Topic.geography,
  Difficulty.hard,
  BloomLevel.analiz,
  _gunSuresi,
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
  shortAnswer: false,
);

// ─────────────────────────── 3 · Saat dilimleri ─────────────────────────────

const _aylar = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];
// Şubat dışındaki aylar: gün 1 … 29 her ayda geçerlidir.
const _aylar11 = [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];

String _utc(int o) => o == 0 ? 'UTC+0' : (o > 0 ? 'UTC+$o' : 'UTC−${-o}');

/// Gün × 1440 + dakika biçimindeki anı “14 Mart, 06:30” olarak yazar.
String _an(int ay, int dk) =>
    '${dk ~/ 1440} ${_aylar[ay]}, ${_saat(dk % 1440)}';

/// Anı kök içinde “14 Mart günü yerel saat 06:30” biçiminde yazar.
String _anKok(int ay, int dk) =>
    '${dk ~/ 1440} ${_aylar[ay]} günü yerel saat ${_saat(dk % 1440)}';

// Yaz saati uygulamayan kentler ve UTC farkları.
const _donusum = [
  (('Ankara', 3), ('Tokyo', 9)),
  (('Tokyo', 9), ('Lima', -5)),
  (('Pekin', 8), ('Buenos Aires', -3)),
  (('Honolulu', -10), ('Seul', 9)),
  (('Dakar', 0), ('Bangkok', 7)),
  (('Brasilia', -3), ('Moskova', 3)),
  (('Karakas', -4), ('Dubai', 4)),
  (('Brisbane', 10), ('Reykjavik', 0)),
  (('Lagos', 1), ('Phoenix', -7)),
  (('Taşkent', 5), ('Bogota', -5)),
  (('Manila', 8), ('Johannesburg', 2)),
  (('Riyad', 3), ('Perth', 8)),
  (('Akra', 0), ('Singapur', 8)),
  (('Phoenix', -7), ('İstanbul', 3)),
  (('Cakarta', 7), ('Honolulu', -10)),
  (('Nairobi', 3), ('Karakas', -4)),
  (('Seul', 9), ('Dakar', 0)),
  (('Johannesburg', 2), ('Brisbane', 10)),
  (('Buenos Aires', -3), ('Dakka', 6)),
  (('Bakü', 4), ('Lima', -5)),
  (('Reykjavik', 0), ('Tokyo', 9)),
  (('Dakka', 6), ('Kinşasa', 1)),
  (('Bogota', -5), ('Perth', 8)),
  (('Karaçi', 5), ('Honolulu', -10)),
  (('Moskova', 3), ('Brasilia', -3)),
];

// (kalkış kenti, varış kenti, uçuş süresi; dakika)
const _ucuslar = [
  (('İstanbul', 3), ('Tokyo', 9), 670),
  (('İstanbul', 3), ('Pekin', 8), 570),
  (('İstanbul', 3), ('Bangkok', 7), 560),
  (('İstanbul', 3), ('Singapur', 8), 630),
  (('İstanbul', 3), ('Dubai', 4), 260),
  (('İstanbul', 3), ('Bakü', 4), 180),
  (('İstanbul', 3), ('Taşkent', 5), 270),
  (('İstanbul', 3), ('Dakka', 6), 420),
  (('İstanbul', 3), ('Johannesburg', 2), 600),
  (('İstanbul', 3), ('Lagos', 1), 390),
  (('İstanbul', 3), ('Dakar', 0), 410),
  (('İstanbul', 3), ('Bogota', -5), 810),
  (('İstanbul', 3), ('Buenos Aires', -3), 930),
  (('Tokyo', 9), ('Honolulu', -10), 450),
  (('Honolulu', -10), ('Tokyo', 9), 510),
  (('Seul', 9), ('Honolulu', -10), 480),
  (('Perth', 8), ('Johannesburg', 2), 660),
  (('Bogota', -5), ('Buenos Aires', -3), 390),
  (('Phoenix', -7), ('Honolulu', -10), 390),
  (('Dubai', 4), ('Brisbane', 10), 840),
  (('Pekin', 8), ('Moskova', 3), 480),
  (('Moskova', 3), ('Bangkok', 7), 540),
  (('Cakarta', 7), ('Tokyo', 9), 450),
  (('Riyad', 3), ('Karaçi', 5), 210),
  (('Johannesburg', 2), ('Dubai', 4), 480),
];

String _kentAd((String, int) k) =>
    '${_utc(k.$2)} saat dilimini kullanan ${k.$1}';

AdvancedItem _saatDilimi(int a, int b, int c) {
  final bicim = c % 3, q = c ~/ 3;
  String an(int ay, int x) => _an(ay, x);
  bool gecerli(int x) => x >= 1440 && x < 30 * 1440;
  if (bicim == 0) {
    final (ka, kb) = _donusum[a];
    final ay = const [2, 5, 8, 10][q];
    final t0 = (3 + a) * 1440 + 15 + 71 * b;
    final fark = kb.$2 - ka.$2;
    final dogru = t0 + 60 * fark;
    final ayniYon = (ka.$2 >= 0) == (kb.$2 >= 0);
    final hataFark = ayniYon
        ? ka.$2.abs() + kb.$2.abs()
        : (ka.$2.abs() - kb.$2.abs()).abs();
    final gunDegisti = dogru ~/ 1440 != t0 ~/ 1440;
    final adaylar = [
      t0 - 60 * fark,
      gunDegisti
          ? (t0 ~/ 1440) * 1440 + dogru % 1440
          : dogru + (fark > 0 ? 1440 : -1440),
      if (hataFark != fark.abs() && hataFark != 0)
        t0 + (fark > 0 ? 60 : -60) * hataFark,
      dogru + 60,
      dogru - 60,
      dogru + 120,
    ].where(gecerli);
    final ileri = fark > 0;
    return secenekli(
      '${_kentAd(ka)} kentinde ${_anKok(ay, t0)} iken ${_kentAd(kb)} kentinde yerel '
          'tarih ve saat nedir?',
      an(ay, dogru),
      adaylar.map((x) => an(ay, x)),
      'Saat farkı ${_p(ileri ? kb.$2 : ka.$2)} − ${_p(ileri ? ka.$2 : kb.$2)} = ${fark.abs()} '
          'saattir. ${kb.$1} kentinin UTC farkı daha ${ileri ? 'büyük' : 'küçük'} olduğundan saati '
          '${ileri ? 'ileridir' : 'geridir'}: ${an(ay, t0)} ${ileri ? '+' : '−'} ${fark.abs()} saat = '
          '${an(ay, dogru)}.',
    );
  }
  if (bicim == 1) {
    final (ka, kb, sure0) = _ucuslar[a];
    final sure = sure0 + 5 * (b % 5);
    final ay = _aylar11[(q * 4 + b) % 11];
    final fark = kb.$2 - ka.$2;
    final kalkis = (3 + (7 * a + b) % 24) * 1440 + 30 + 67 * b;
    final varis = kalkis + sure + 60 * fark;
    final farkYaz =
        '${kb.$1} kentinin saati ${ka.$1} kentinden ${fark.abs()} saat '
        '${fark > 0 ? 'ileridir' : 'geridir'}';
    if (q == 0) {
      return secenekli(
        '${_kentAd(ka)} kentinden ${_anKok(ay, kalkis)} iken kalkan bir uçak, ${_sure(sure)} '
            'süren yolculuğun ardından ${_kentAd(kb)} kentine iniyor. Uçak yerel saatle hangi '
            'tarih ve saatte iner?',
        an(ay, varis),
        [
          kalkis + sure,
          kalkis + sure - 60 * fark,
          kalkis + 60 * fark,
          varis + 60,
          varis - 60,
        ].where(gecerli).map((x) => an(ay, x)),
        '$farkYaz. Kalkış anında ${kb.$1} kentinde saat ${an(ay, kalkis + 60 * fark)} '
            'olur; buna ${_sure(sure)} eklenince varış ${an(ay, varis)} bulunur.',
      );
    }
    if (q == 1) {
      return secenekli(
        '${_kentAd(kb)} kentine ${_anKok(ay, varis)} iken inen bir uçağın ${_kentAd(ka)} '
            'kentinden başlayan yolculuğu ${_sure(sure)} sürmüştür. Bu uçak yerel saatle hangi '
            'tarih ve saatte kalkmıştır?',
        an(ay, kalkis),
        [
          varis - sure,
          varis - sure + 60 * fark,
          varis - 60 * fark,
          kalkis + 60,
          kalkis - 60,
        ].where(gecerli).map((x) => an(ay, x)),
        '$farkYaz. Varış anında ${ka.$1} kentinde saat ${an(ay, varis - 60 * fark)} olur; '
            'bundan ${_sure(sure)} çıkarılınca kalkış ${an(ay, kalkis)} bulunur.',
      );
    }
    final ham = varis - kalkis;
    return secenekli(
      '${_kentAd(ka)} kentinden ${_anKok(ay, kalkis)} iken kalkan bir uçak, ${_kentAd(kb)} '
          'kentine ${_anKok(ay, varis)} iken iniyor. Bu uçuş ne kadar sürmüştür?',
      _sure(sure),
      [
        ham,
        ham + 60 * fark,
        sure + 60,
        sure - 60,
        sure + 120,
      ].where((x) => x > 0).map(_sure),
      '$farkYaz. Kalkış anında ${kb.$1} kentinde saat ${an(ay, kalkis + 60 * fark)} olur; '
          'buradan varışa kadar geçen süre ${_sure(sure)} bulunur.',
    );
  }
  // Tarih değiştirme çizgisi: doğuya giden gemi takvimi bir gün geri,
  // batıya giden bir gün ileri alır.
  final doguya = b.isEven;
  final saat = const [4, 9, 15][q];
  final ay = _aylar11[(b ~/ 2 + 3 * q) % 11];
  final t0 = (3 + a) * 1440 + 45 + 137 * (b ~/ 2);
  final kayma = doguya ? -1440 : 1440;
  final dogru = t0 + kayma + 60 * saat;
  return secenekli(
    "Pasifik Okyanusu'nda ${doguya ? 'doğuya' : 'batıya'} doğru ilerleyen bir gemi, "
        'gemideki saat ${_an(ay, t0).replaceFirst(',', ' günü')} iken tarih değiştirme '
        'çizgisini (180° meridyeni) geçiyor. Çizgi geçilirken gemide yalnız takvim bir gün '
        'değiştirilmektedir. Gemi çizgiyi geçtikten $saat saat sonra bir limana ulaştığına '
        'göre limana varışta gemideki tarih ve saat nedir?',
    an(ay, dogru),
    [
      t0 - kayma + 60 * saat,
      t0 + 60 * saat,
      t0 + kayma,
      dogru + 60,
      dogru - 60,
    ].where(gecerli).map((x) => an(ay, x)),
    'Tarih değiştirme çizgisini ${doguya ? 'batıdan doğuya geçen gemide takvim bir gün geri' : 'doğudan batıya geçen gemide takvim bir gün ileri'} '
        'alınır: ${an(ay, t0)} → ${an(ay, t0 + kayma)}. $saat saat sonra ${an(ay, dogru)} olur.',
  );
}

final _f03 = lmAile(
  'cg_saat_dilimi',
  'Saat dilimleri, uçuş saatleri ve tarih değiştirme',
  Topic.geography,
  Difficulty.medium,
  BloomLevel.uygulama,
  _saatDilimi,
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
  shortAnswer: false,
);

// ─────────────── 4 · Dünya'nın günlük ve yıllık hareketinin sonuçları ───────

const _gunluk = 'günlük hareket', _yillik = 'yıllık hareket';
const _hareketler = <_Etiketli>[
  ('Gece ile gündüzün birbirini izlemesi', _gunluk, null),
  (
    'Farklı boylamlardaki yerlerin yerel saatlerinin farklı olması',
    _gunluk,
    null,
  ),
  ('Gece ile gündüz arasında sıcaklık farkı oluşması', _gunluk, null),
  ('Kara ve deniz meltemlerinin oluşması', _gunluk, null),
  ('Dağ ve vadi meltemlerinin oluşması', _gunluk, null),
  ('Cisimlerin gölge boyunun ve yönünün gün içinde değişmesi', _gunluk, null),
  ("Güneş'in doğudan doğup batıdan batıyormuş gibi görünmesi", _gunluk, null),
  (
    "Rüzgârların ve okyanus akıntılarının Kuzey Yarım Küre'de sağa, Güney Yarım Küre'de sola "
        'sapması',
    _gunluk,
    null,
  ),
  (
    "Dünya'nın kutuplardan basık, Ekvator'dan şişkin bir şekil alması",
    _gunluk,
    null,
  ),
  ("Ekvator'dan kutuplara doğru çizgisel hızın azalması", _gunluk, null),
  ('Doğudaki yerlerde güneşin batıdaki yerlerden önce doğması', _gunluk, null),
  ('Güneş ışınlarının geliş açısının gün içinde değişmesi', _gunluk, null),
  ("Güneş'in gün içinde en yüksek konuma öğle vakti ulaşması", _gunluk, null),
  (
    'Aynı meridyen üzerindeki yerlerde öğle vaktinin aynı anda yaşanması',
    _gunluk,
    null,
  ),
  ('Mevsimlerin oluşması', _yillik, null),
  ('Gece ve gündüz sürelerinin yıl içinde uzayıp kısalması', _yillik, null),
  (
    'Öğle vakti güneş ışınlarının geliş açısının yıl içinde değişmesi',
    _yillik,
    null,
  ),
  ('Öğle vakti cisimlerin gölge boyunun yıl içinde değişmesi', _yillik, null),
  ('Dönencelerin ve kutup dairelerinin oluşması', _yillik, null),
  ('Kutup noktalarında altı ay gece, altı ay gündüz yaşanması', _yillik, null),
  (
    'Güneş ışınlarının dik geldiği paralelin yıl içinde dönenceler arasında yer değiştirmesi',
    _yillik,
    null,
  ),
  (
    'Aydınlanma çemberinin kutup noktalarına göre konumunun yıl içinde değişmesi',
    _yillik,
    null,
  ),
  (
    "Güneş'in ufukta doğduğu ve battığı noktaların yıl içinde yer değiştirmesi",
    _yillik,
    null,
  ),
  (
    'Basınç ve rüzgâr kuşaklarının yıl içinde kuzeye ve güneye kayması',
    _yillik,
    null,
  ),
  ('Matematik iklim kuşaklarının oluşması', _yillik, null),
  ('Aylık ortalama sıcaklıkların yıl içinde değişmesi', _yillik, null),
  (
    "Kuzey Yarım Küre'de en uzun gündüzün 21 Haziran'da yaşanması",
    _yillik,
    null,
  ),
  (
    'Kuzey ve Güney yarım kürelerde mevsimlerin birbirinin tersi olarak yaşanması',
    _yillik,
    null,
  ),
  (
    'Güneş ışınlarının yalnız dönenceler arasındaki alana dik gelebilmesi',
    _yillik,
    null,
  ),
  ('Kutup dairelerinin 66°33′ enlemlerinde yer alması', _yillik, null),
  // Dünya–Güneş uzaklığının değişmesi eksen eğikliğinin değil yörüngenin elips
  // olmasının sonucudur; “dolanma ve eksen eğikliği” sorusunda tartışmalı olduğundan
  // alınmamıştır.
];

final _f04 = lmSirali(
  'cg_dunya_hareket',
  "Dünya'nın günlük ve yıllık hareketinin sonuçları",
  Topic.geography,
  Difficulty.easy,
  BloomLevel.anlama,
  (i) => _etiketli(
    i,
    lmAileBoyu,
    _hareketler,
    const [_gunluk, _yillik],
    siraSoru:
        "Bu durumlar sırasıyla Dünya'nın günlük hareketinin mi yoksa eksen "
        'eğikliğiyle birlikte yıllık hareketinin mi sonucudur?',
    hangiSoru: (h, _) => h == _gunluk
        ? "Bu durumlardan hangileri Dünya'nın kendi ekseni etrafında dönmesinin (günlük "
              'hareketin) sonucudur?'
        : "Bu durumlardan hangileri Dünya'nın Güneş etrafında dolanmasının ve eksen "
              'eğikliğinin (yıllık hareketin) sonucudur?',
    aciklama: (x) => '${x.map((e) => '${e.$1}: ${e.$2}').join('; ')}.',
  ),
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
);

// ─────────────────── 5 · Enlem ve boylamın sonuçları ────────────────────────

String _boylamAd(int x) => '${x.abs()}° ${x >= 0 ? 'doğu' : 'batı'}';

AdvancedItem _enlemSonuc(int a, int b, int c) {
  // K tek, L çift dereceli enlemdedir: iki merkez Ekvator'a hiç eşit uzaklıkta olmaz.
  final enK = (a.isEven ? 1 : -1) * (3 + 2 * a);
  final enL = (b % 3 == 0 ? -1 : 1) * (4 + 2 * b);
  const boylamlar = [28, -15, 45, 100, -70, 135, 12, -40, 75, -118];
  final boK = boylamlar[c];
  final fark = 7 + 3 * b + a % 3;
  // L, 0° ve 180° meridyenlerine düşmeyecek yönde seçilir.
  bool uygun(int x) => x != 0 && x.abs() < 180;
  final ilk = (a + c).isEven ? boK + fark : boK - fark;
  final boL = uygun(ilk) ? ilk : 2 * boK - ilk;
  final dogu = boK > boL ? 'K' : 'L', bati = boK > boL ? 'L' : 'K';
  final yakin = enK.abs() < enL.abs() ? 'K' : 'L',
      uzak = yakin == 'K' ? 'L' : 'K';
  final kuzey = enK > enL ? 'K' : 'L', guney = kuzey == 'K' ? 'L' : 'K';
  final ayniYan = (boK >= 0) == (boL >= 0);
  final hata = ayniYan ? boK.abs() + boL.abs() : (boK.abs() - boL.abs()).abs();
  // (doğru biçim, yanlış biçim) — her şablon iki merkezin yerini değiştirerek yanlışlanır.
  String saatIfade(String ileri, String geri, int dk) =>
      '$ileri merkezinin yerel saati $geri merkezinden $dk dakika ileridir.';
  final sablon = <(String, String)>[
    (
      saatIfade(dogu, bati, 4 * fark),
      (a + b).isEven || hata == fark || hata == 0
          ? saatIfade(bati, dogu, 4 * fark)
          : saatIfade(dogu, bati, 4 * hata),
    ),
    (
      'Çizgisel hız $yakin merkezinde $uzak merkezinden fazladır.',
      'Çizgisel hız $uzak merkezinde $yakin merkezinden fazladır.',
    ),
    (
      'Diğer koşullar aynı kabul edildiğinde yıllık ortalama sıcaklık $yakin merkezinde daha '
          'yüksektir.',
      'Diğer koşullar aynı kabul edildiğinde yıllık ortalama sıcaklık $uzak merkezinde daha '
          'yüksektir.',
    ),
    (
      "21 Haziran'da gündüz süresi $kuzey merkezinde $guney merkezinden uzundur.",
      "21 Haziran'da gündüz süresi $guney merkezinde $kuzey merkezinden uzundur.",
    ),
    (
      'Yıl içinde gündüz süresindeki değişim $uzak merkezinde daha fazladır.',
      'Yıl içinde gündüz süresindeki değişim $yakin merkezinde daha fazladır.',
    ),
    (
      "21 Aralık'ta güneş, yerel saate göre $guney merkezinde daha erken doğar.",
      "21 Aralık'ta güneş, yerel saate göre $kuzey merkezinde daha erken doğar.",
    ),
  ];
  final dogruSablon = (a + b + c) % 6;
  final yanlislar = [
    for (var r = 1; r < 6; r++) sablon[(dogruSablon + r) % 6].$2,
    "21 Mart'ta gündüz süresi ${(a + c).isEven ? 'K' : 'L'} merkezinde daha uzundur.",
  ];
  final kay = (3 * a + b) % 6;
  final farkYaz = ayniYan
      ? 'Merkezler başlangıç meridyeninin aynı yanında olduğundan boylam farkı '
            '${boK.abs() > boL.abs() ? boK.abs() : boL.abs()} − '
            '${boK.abs() > boL.abs() ? boL.abs() : boK.abs()} = $fark°'
      : 'Merkezler başlangıç meridyeninin farklı yanlarında olduğundan boylam farkı '
            '${boK.abs()} + ${boL.abs()} = $fark°';
  return secenekli(
    'K merkezi ${_enlemAd(enK * 60)} enlemi ile ${_boylamAd(boK)} boylamının, L merkezi '
        '${_enlemAd(enL * 60)} enlemi ile ${_boylamAd(boL)} boylamının kesiştiği yerdedir. '
        'Buna göre K ve L merkezleriyle ilgili hangi ifade doğrudur?',
    sablon[dogruSablon].$1,
    [...yanlislar.sublist(kay), ...yanlislar.sublist(0, kay)],
    '$farkYaz; yerel saat farkı $fark × 4 = ${4 * fark} dakikadır ve doğudaki $dogu merkezinin '
        'saati ileridir. $yakin merkezi Ekvator\'a daha yakın olduğundan çizgisel hızı ve ortalama '
        'sıcaklığı daha fazla, gündüz süresindeki yıllık değişimi daha azdır. $kuzey merkezi daha '
        "kuzeyde olduğundan 21 Haziran'da gündüzü daha uzun, 21 Aralık'ta daha kısadır; 21 Mart'ta "
        'gece ile gündüz her yerde eşittir.',
  );
}

final _f05 = lmAile(
  'cg_enlem_sonuc',
  'Enlem ve boylam farkının sonuçlarını karşılaştırma',
  Topic.geography,
  Difficulty.medium,
  BloomLevel.analiz,
  _enlemSonuc,
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
  shortAnswer: false,
);

// ──────────────────────── 6 · İklim tipini belirleme ────────────────────────

// (ad, yağış dağılımı, gerekçe, karışan iklimler, cümle içi yazım). Sıcaklıklar
// onda bir °C.
const _iklimler = [
  (
    'Ekvatoral iklim',
    'Yılın her ayı yağışlıdır; kurak dönem bulunmamaktadır.',
    'Her ay sıcak, yıllık sıcaklık farkı çok az ve yağış her mevsim bol olduğundan',
    [1, 2, 5],
    'ekvatoral iklim',
  ),
  (
    'Savan iklimi',
    'Yağışlar yaz döneminde düşmekte, kış dönemi kurak geçmektedir.',
    'Yıl boyunca sıcak, yazları yağışlı, kışları kurak ve yıllık yağışı ekvatoral ve muson '
        'iklimlerine göre az olduğundan',
    [2, 0, 3],
    'savan iklimi',
  ),
  (
    'Muson iklimi',
    'Yağışın büyük bölümü yaz aylarında denizden esen nemli rüzgârlarla düşmekte, kış ayları '
        'kurak geçmektedir.',
    'Sıcak, yazları denizden esen rüzgârlarla çok yağışlı, kışları kurak olduğundan',
    [1, 0, 4],
    'muson iklimi',
  ),
  (
    'Çöl iklimi',
    'Yağış çok az ve düzensizdir.',
    'Yazları çok sıcak ve yıllık yağışı 250 mm altında kaldığından',
    [6, 1, 4],
    'çöl iklimi',
  ),
  (
    'Akdeniz iklimi',
    'Yağışın büyük bölümü kış mevsiminde düşmekte, yaz ayları kurak geçmektedir.',
    'Yazları sıcak ve kurak, kışları ılık ve yağışlı olduğundan',
    [6, 5, 1],
    'Akdeniz iklimi',
  ),
  (
    'Ilıman okyanusal iklim',
    'Yağış bütün mevsimlere dengeli dağılmaktadır.',
    'Yazları serin, kışları ılık geçtiği ve her mevsim yağış aldığı için',
    [4, 7, 6],
    'ılıman okyanusal iklim',
  ),
  (
    'Karasal iklim',
    'Yağış en çok ilkbaharda düşmekte, yaz ayları kurak geçmekte, kış yağışları çoğunlukla kar '
        'biçiminde olmaktadır.',
    'Yazları sıcak ve kurak, kışları soğuk ve karlı, yıllık yağışı az olduğundan',
    [4, 7, 3],
    'karasal iklim',
  ),
  (
    'Sert karasal iklim',
    'Yağış daha çok yaz aylarında düşmektedir.',
    'Kışları çok uzun ve sert, yazları kısa ve serin geçtiğinden',
    [8, 6, 5],
    'sert karasal iklim',
  ),
  (
    'Tundra iklimi',
    'Yağış az olup çoğunlukla kısa süren yaz mevsiminde düşmektedir.',
    'En sıcak ay ortalaması 10 °C altında kalıp 0 °C üzerine çıktığından',
    [9, 7, 6],
    'tundra iklimi',
  ),
  (
    'Kutup iklimi',
    'Yağış çok az olup kar biçiminde düşmektedir.',
    'Bütün ayların ortalama sıcaklığı 0 °C altında kaldığından',
    [8, 7, 6],
    'kutup iklimi',
  ),
];

/// Onda bir °C cinsinden sıcaklığı işlem içinde yazar (negatifse parantezle).
String _derecePar(int onda) => onda < 0 ? '(${_n(onda / 10)})' : _n(onda / 10);

AdvancedItem _iklimTipi(int a, int b, int c) {
  final h = a % 5, k = a ~/ 5;
  final (sicak, soguk, yagis) = switch (c) {
    0 => (260 + 5 * h, 250 + 5 * h - 5 * k - 5, 2000 + 100 * b),
    1 => (270 + 10 * h, 230 + 10 * h - 10 * k, 750 + 25 * b),
    2 => (280 + 10 * h, 220 + 10 * h - 10 * k, 2400 + 60 * b),
    3 => (320 + 10 * h, 120 + 20 * k, 20 + 8 * b),
    4 => (230 + 10 * h, 60 + 15 * k, 550 + 20 * b),
    5 => (150 + 10 * h, 20 + 10 * k, 650 + 25 * b),
    6 => (220 + 10 * h, -10 - 20 * k, 280 + 10 * b),
    7 => (150 + 10 * h, -180 - 40 * k, 350 + 10 * b),
    8 => (30 + 15 * h, -220 - 30 * k, 150 + 6 * b),
    _ => (-20 - 25 * h, -300 - 40 * k, 40 + 5 * b),
  };
  final iklim = _iklimler[c];
  final karisan = iklim.$4;
  final diger = [
    for (var r = 0; r < 10; r++)
      if (r != c && !karisan.contains(r)) r,
  ];
  final kay = (a + b) % diger.length;
  final fark = sicak - soguk;
  return secenekli(
    'Bir meteoroloji istasyonunda en sıcak ayın ortalama sıcaklığı ${_n(sicak / 10)} °C, en '
        'soğuk ayın ortalama sıcaklığı ${_n(soguk / 10)} °C, yıllık toplam yağış $yagis mm olarak '
        'ölçülmüştür. ${iklim.$2} Bu verilere göre istasyonda hangi iklim tipi görülür?',
    iklim.$1,
    [
      for (final r in karisan) _iklimler[r].$1,
      for (final r in [...diger.sublist(kay), ...diger.sublist(0, kay)])
        _iklimler[r].$1,
    ],
    'Yıllık sıcaklık farkı ${_n(sicak / 10)} − ${_derecePar(soguk)} = ${_n(fark / 10)} °C, yıllık '
        'yağış $yagis mm olarak verilmiştir. ${iklim.$3} istasyonda görülen iklim tipi '
        '${iklim.$5} olarak belirlenir.',
  );
}

final _f06 = lmAile(
  'cg_iklim_tipi',
  'Sıcaklık ve yağış verilerinden iklim tipini bulma',
  Topic.geography,
  Difficulty.medium,
  BloomLevel.analiz,
  _iklimTipi,
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
);

// ─────────── 7 · Basınç kuşakları, sürekli ve yerel rüzgârlar ───────────────

const _ruzgarOnerme = <_Onerme>[
  (
    'Yıldız rüzgârı',
    'kuzeyden eser.',
    ['güneyden eser.', 'güneybatıdan eser.', 'doğudan eser.'],
  ),
  (
    'Poyraz',
    'kuzeydoğudan eser.',
    ['güneybatıdan eser.', 'kuzeybatıdan eser.', 'güneyden eser.'],
  ),
  (
    'Gündoğusu',
    'doğudan eser.',
    ['batıdan eser.', 'kuzeyden eser.', 'güneybatıdan eser.'],
  ),
  (
    'Keşişleme',
    'güneydoğudan eser.',
    ['kuzeybatıdan eser.', 'kuzeydoğudan eser.', 'batıdan eser.'],
  ),
  (
    'Kıble rüzgârı',
    'güneyden eser.',
    ['kuzeyden eser.', 'kuzeydoğudan eser.', 'batıdan eser.'],
  ),
  (
    'Lodos',
    'güneybatıdan eser.',
    ['kuzeydoğudan eser.', 'güneydoğudan eser.', 'kuzeyden eser.'],
  ),
  (
    'Günbatısı',
    'batıdan eser.',
    ['doğudan eser.', 'güneydoğudan eser.', 'kuzeydoğudan eser.'],
  ),
  (
    'Karayel',
    'kuzeybatıdan eser.',
    ['güneydoğudan eser.', 'kuzeydoğudan eser.', 'güneyden eser.'],
  ),
  (
    "Kuzey Yarım Küre'de alize rüzgârları",
    'kuzeydoğudan eser.',
    ['güneydoğudan eser.', 'güneybatıdan eser.'],
  ),
  (
    "Güney Yarım Küre'de alize rüzgârları",
    'güneydoğudan eser.',
    ['kuzeydoğudan eser.', 'kuzeybatıdan eser.'],
  ),
  (
    "Kuzey Yarım Küre'de batı rüzgârları",
    'güneybatıdan eser.',
    ['kuzeybatıdan eser.', 'kuzeydoğudan eser.'],
  ),
  (
    "Güney Yarım Küre'de batı rüzgârları",
    'kuzeybatıdan eser.',
    ['güneybatıdan eser.', 'güneydoğudan eser.'],
  ),
  (
    "Kuzey Yarım Küre'de kutup rüzgârları",
    'kuzeydoğudan eser.',
    ['güneybatıdan eser.', 'kuzeybatıdan eser.'],
  ),
  (
    "Güney Yarım Küre'de kutup rüzgârları",
    'güneydoğudan eser.',
    ['kuzeybatıdan eser.', 'kuzeydoğudan eser.'],
  ),
  (
    'Ekvator alçak basınç kuşağı',
    'termik kökenlidir.',
    ['dinamik kökenlidir.', 'yaklaşık 60° enlemleri çevresinde yer alır.'],
  ),
  (
    'Dönence (subtropikal) yüksek basınç kuşakları',
    'dinamik kökenlidir.',
    ['termik kökenlidir.', 'kutup noktaları çevresinde yer alır.'],
  ),
  (
    '60° (kutup altı) alçak basınç kuşakları',
    'dinamik kökenlidir.',
    ['termik kökenlidir.', "Ekvator çevresinde yer alır."],
  ),
  (
    'Kutup yüksek basınç kuşakları',
    'termik kökenlidir.',
    ['dinamik kökenlidir.', 'yaklaşık 30°–35° enlemlerinde yer alır.'],
  ),
  (
    'Alize rüzgârları',
    'dönence yüksek basınç kuşaklarından Ekvator alçak basınç kuşağına doğru eser.',
    [
      'Ekvator alçak basınç kuşağından dönence yüksek basınç kuşaklarına doğru eser.',
      'kutup yüksek basınç kuşaklarından 60° alçak basınç kuşaklarına doğru eser.',
    ],
  ),
  (
    'Batı rüzgârları',
    'dönence yüksek basınç kuşaklarından 60° alçak basınç kuşaklarına doğru eser.',
    [
      '60° alçak basınç kuşaklarından dönence yüksek basınç kuşaklarına doğru eser.',
      'dönence yüksek basınç kuşaklarından Ekvator alçak basınç kuşağına doğru eser.',
    ],
  ),
  (
    'Kutup rüzgârları',
    'kutup yüksek basınç kuşaklarından 60° alçak basınç kuşaklarına doğru eser.',
    [
      '60° alçak basınç kuşaklarından kutup yüksek basınç kuşaklarına doğru eser.',
      'dönence yüksek basınç kuşaklarından 60° alçak basınç kuşaklarına doğru eser.',
    ],
  ),
];

final _f07 = lmSirali(
  'cg_basinc_ruzgar',
  'Basınç kuşakları, sürekli ve yerel rüzgârlar',
  Topic.geography,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) => _dogruYanlis(
    i,
    _ruzgarOnerme,
    'Basınç kuşakları ve rüzgârlarla ilgili bu bilgilerden hangileri doğrudur?',
  ),
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
);

// ───────────────── 8 · Dış kuvvetler ve oluşturdukları yer şekilleri ────────

const _akarsu = 'akarsu', _ruzgar = 'rüzgâr', _buzul = 'buzul';
const _dalga = 'dalga ve akıntılar', _karst = 'karstik süreçler';
const _yerSekilleri = <_Etiketli>[
  ('Çentik (V biçimli) vadi', _akarsu, null),
  ('Kanyon vadi', _akarsu, null),
  ('Menderes', _akarsu, null),
  // Dev kazanı (buzul dev kazanları da vardır) ve peneplen (bütün dış
  // kuvvetlerin uzun süreli aşındırması) tek bir dış kuvvete bağlanamadığından
  // alınmamıştır.
  ('Delta', _akarsu, null),
  ('Birikinti konisi', _akarsu, null),
  ('Birikinti yelpazesi', _akarsu, null),
  ('Akarsu taraçası (seki)', _akarsu, null),
  ('Kırgıbayır', _akarsu, null),
  ('Irmak adası', _akarsu, null),
  ('Çağlayan (şelale)', _akarsu, null),
  ('Mantar kaya (şeytan masası)', _ruzgar, null),
  ('Barkan (hilal biçimli kumul)', _ruzgar, null),
  ('Lös', _ruzgar, null),
  ('Kum tepesi (kumul)', _ruzgar, null),
  ('Sirk', _buzul, null),
  ('Hörgüç kaya', _buzul, null),
  ('Moren', _buzul, null),
  ('Buzul vadisi (U biçimli vadi)', _buzul, null),
  ('Falez', _dalga, null),
  ('Abrazyon platformu (aşınım düzlüğü)', _dalga, null),
  ('Kıyı oku', _dalga, null),
  ('Kıyı kordonu', _dalga, null),
  ('Tombolo', _dalga, null),
  ('Lagün (kıyı set gölü)', _dalga, null),
  ('Kumsal (plaj)', _dalga, null),
  ('Lapya', _karst, null),
  ('Dolin', _karst, null),
  ('Uvala', _karst, null),
  ('Polye', _karst, null),
  ('Obruk', _karst, null),
  ('Sarkıt', _karst, null),
  ('Dikit', _karst, null),
  ('Traverten', _karst, null),
  ('Düden', _karst, null),
];

const _kuvvetIle = {
  _akarsu: 'akarsuların etkisiyle',
  _ruzgar: 'rüzgârın etkisiyle',
  _buzul: 'buzulların etkisiyle',
  _dalga: 'dalga ve akıntıların etkisiyle',
  _karst: 'karstik süreçlerle',
};

final _f08 = lmSirali(
  'cg_yer_sekli',
  'Dış kuvvetler ve oluşturdukları yer şekilleri',
  Topic.geography,
  Difficulty.easy,
  BloomLevel.hatirlama,
  (i) => _etiketli(
    i,
    lmAileBoyu,
    _yerSekilleri,
    const [_akarsu, _ruzgar, _buzul, _dalga, _karst],
    siraSoru:
        'Bu yer şekillerini oluşturan dış kuvvetler sırasıyla hangisidir?',
    hangiSoru: (h, _) =>
        'Bu yer şekillerinden hangileri ${_kuvvetIle[h]} oluşur?',
    olumsuzSoru: (h, _) =>
        'Bu yer şekillerinden hangileri ${_kuvvetIle[h]} oluşmaz?',
    aciklama: (x) => '${x.map((e) => '${e.$1}: ${e.$2}').join('; ')}.',
  ),
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
);

// ─────────── 9 · İç kuvvetler, levha sınırları ve deprem türleri ───────────

const _oro = 'orojenez',
    _epi = 'epirojenez',
    _vol = 'volkanizma',
    _dep = 'deprem';
const _icKuvvetler = <_Etiketli>[
  ("Toros Dağları'nın kıvrılarak yükselmesi", _oro, null),
  ("Kuzey Anadolu Dağları'nın kıvrılarak yükselmesi", _oro, null),
  ("Batı Anadolu'da horst ve grabenlerin oluşması", _oro, null),
  ('Gediz ve Büyük Menderes grabenlerinin oluşması', _oro, null),
  ('Alp-Himalaya kıvrım kuşağının oluşması', _oro, null),
  (
    'Tortul tabakaların yan basınçlarla kıvrılarak antiklinal ve senklinalleri oluşturması',
    _oro,
    null,
  ),
  (
    'Sert tabakaların kırılarak yükselen ve alçalan bloklara ayrılması',
    _oro,
    null,
  ),
  ('Bozdağlar ve Aydın Dağları gibi horstların yükselmesi', _oro, null),
  ("Himalaya Dağları'nın iki levhanın çarpışmasıyla yükselmesi", _oro, null),
  (
    'Kıtaların geniş alanlarda yavaş yavaş yükselmesi ya da alçalması',
    _epi,
    null,
  ),
  (
    'Karaların alçalmasıyla denizin kara üzerine ilerlemesi (transgresyon)',
    _epi,
    null,
  ),
  ('Karaların yükselmesiyle denizin geri çekilmesi (regresyon)', _epi, null),
  (
    "Buzulların erimesiyle yükü azalan İskandinav Yarımadası'nın yavaşça yükselmesi",
    _epi,
    null,
  ),
  ("Anadolu'nun geniş bir alanda toptan yükselmesi", _epi, null),
  ('Erciyes, Hasan ve Nemrut dağlarının oluşması', _vol, null),
  ("Kapadokya'da kalın tüf tabakalarının birikmesi", _vol, null),
  ("Erzurum-Kars Platosu'nun lav akıntılarıyla oluşması", _vol, null),
  ('Kula çevresinde genç volkan konilerinin oluşması', _vol, null),
  ('Magmanın yer kabuğundaki çatlaklardan yeryüzüne çıkması', _vol, null),
  ('Gayzer ve fümerol gibi sıcak su ve gaz çıkışlarının görülmesi', _vol, null),
  ('Krater ve kaldera çukurlarının oluşması', _vol, null),
  ('Ağrı ve Süphan dağlarının oluşması', _vol, null),
  (
    'Fay hatları boyunca biriken enerjinin aniden boşalmasıyla yer kabuğunun sarsılması',
    _dep,
    null,
  ),
  (
    'Merkez üssüne yakın yerlerde en şiddetli hissedilen ani yer sarsıntıları',
    _dep,
    null,
  ),
  ('Odak noktasından yayılan dalgalarla yer kabuğunun titreşmesi', _dep, null),
  ('Sismograf ile kaydedilen ani yer sarsıntılarının oluşması', _dep, null),
];
const _icKuvvetIle = {
  _oro: 'orojenik (dağ oluşumu) hareketlerin sonucudur',
  _epi: 'epirojenik (kıta oluşumu) hareketlerin sonucudur',
  _vol: 'volkanizmanın sonucudur',
  _dep: 'deprem olarak tanımlanır',
};

const _uzak = 'uzaklaşan sınır',
    _yakin = 'yakınlaşan sınır',
    _yanal = 'yanal (transform) sınır';
const _levhalar = <_Etiketli>[
  ('Atlas Okyanusu ortasındaki okyanus ortası sırtının oluşması', _uzak, null),
  ("Doğu Afrika Rift Vadisi'nin oluşması", _uzak, null),
  ("Kızıldeniz'in giderek genişlemesi", _uzak, null),
  ('Okyanus tabanında yeni okyanus kabuğunun oluşması', _uzak, null),
  ("İzlanda'nın ortasından geçen yarık sisteminin oluşması", _uzak, null),
  ("Himalaya Dağları'nın yükselmesi", _yakin, null),
  ("And Dağları'nın oluşması", _yakin, null),
  ('Mariana Çukuru gibi derin okyanus çukurlarının oluşması', _yakin, null),
  ('Japon Adaları gibi volkanik ada yaylarının oluşması', _yakin, null),
  ("Alp Dağları'nın oluşması", _yakin, null),
  ('Bir levhanın diğerinin altına dalması (dalma-batma)', _yakin, null),
  ("Kaliforniya'daki San Andreas Fayı'nın oluşması", _yanal, null),
  ("Kuzey Anadolu Fay Hattı'nın oluşması", _yanal, null),
  ('Doğu Anadolu Fayı boyunca levhaların yatay yönde kayması', _yanal, null),
  (
    'İki levhanın birbirine göre yatay yönde, yanlamasına kayması',
    _yanal,
    null,
  ),
  (
    'Okyanus ortası sırtlarını kesen dönüşüm (transform) faylarının oluşması',
    _yanal,
    null,
  ),
];
const _levhaIle = {
  _uzak: 'uzaklaşan (birbirinden ayrılan) levha sınırlarında',
  _yakin: 'yakınlaşan (çarpışan) levha sınırlarında',
  _yanal: 'yanal (transform) hareket eden levha sınırlarında',
};

const _tek = 'tektonik deprem',
    _vdep = 'volkanik deprem',
    _cok = 'çöküntü depremi';
// Türkiye'deki adı bilinen büyük depremler (hepsi fay hatları boyunca oluşmuş
// tektonik depremlerdir). Bir seçkide birden çok örnek bulunabilir; türün
// tanımı olan ögelerden ise her türden en çok biri bulunur.
const _depremOrnekleri = {
  '1999 Gölcük depremi',
  '1939 Erzincan depremi',
  '2023 Kahramanmaraş depremleri',
  '1999 Düzce depremi',
  '2020 Elazığ depremi',
  '2020 İzmir depremi',
};
const _depremler = <_Etiketli>[
  (
    'Levhaların hareketi sonucu fay hatları boyunca oluşan depremler',
    _tek,
    null,
  ),
  ('Etki alanı en geniş ve en yıkıcı olan depremler', _tek, null),
  ("Türkiye'de görülen depremlerin büyük bölümü", _tek, null),
  ('1999 Gölcük depremi', _tek, null),
  ('1939 Erzincan depremi', _tek, null),
  ('2023 Kahramanmaraş depremleri', _tek, null),
  ('1999 Düzce depremi', _tek, null),
  ('2020 Elazığ depremi', _tek, null),
  ('2020 İzmir depremi', _tek, null),
  // Volkanik ve çöküntü depremlerinde her öge ayrı bir bilgi verir (neden, örnek,
  // görüldüğü yer ya da etki alanı); aynı bilgiyi yineleyen öncül çifti oluşmaz.
  (
    'Yer altındaki magma ve gazların yükselme hareketleriyle oluşan depremler',
    _vdep,
    null,
  ),
  (
    "İtalya'da Etna ve Vezüv çevresinde patlamalarla birlikte görülen depremler",
    _vdep,
    null,
  ),
  (
    'Yalnız etkin yanardağların bulunduğu alanlarda görülen, etki alanı dar depremler',
    _vdep,
    null,
  ),
  (
    'Yer altındaki mağara ve boşlukların tavanlarının çökmesiyle oluşan depremler',
    _cok,
    null,
  ),
  (
    'Kireç taşı, jips ve kaya tuzu gibi kolay eriyen kayaçların yaygın olduğu alanlarda '
        'görülen, etkisi yerel kalan depremler',
    _cok,
    null,
  ),
];
// Aynı olguyu anlatan iç kuvvet ögeleri: sıralı eşleştirmede bir seçkide her
// kümeden en çok bir öge bulunur. Deprem ögelerinin dördü de depremin
// tanımıdır; bu yüzden bir seçkide en çok bir deprem ögesi bulunur.
const _icKuvvetAyniOlgu = [
  {
    "Batı Anadolu'da horst ve grabenlerin oluşması",
    'Gediz ve Büyük Menderes grabenlerinin oluşması',
    'Bozdağlar ve Aydın Dağları gibi horstların yükselmesi',
    'Sert tabakaların kırılarak yükselen ve alçalan bloklara ayrılması',
  },
  {
    'Alp-Himalaya kıvrım kuşağının oluşması',
    "Himalaya Dağları'nın iki levhanın çarpışmasıyla yükselmesi",
  },
  {
    'Kıtaların geniş alanlarda yavaş yavaş yükselmesi ya da alçalması',
    "Anadolu'nun geniş bir alanda toptan yükselmesi",
  },
];

/// Seçkide verilen kümelerin her birinden en çok bir öge bulunur.
bool _enCokBir(List<_Etiketli> x, List<Set<String>> kumeler) =>
    kumeler.every((g) => x.where((e) => g.contains(e.$1)).length <= 1);

bool _icKuvvetSira(List<_Etiketli> x) =>
    x.where((e) => e.$2 == _dep).length <= 1 && _enCokBir(x, _icKuvvetAyniOlgu);

// Aynı olguyu anlatan levha ögeleri (tanım ile onu yineleyen örnek, aynı sırtın
// iki parçası): sıralı eşleştirmede bir seçkide birlikte bulunmaz.
const _levhaAyniOlgu = [
  {
    'Doğu Anadolu Fayı boyunca levhaların yatay yönde kayması',
    'İki levhanın birbirine göre yatay yönde, yanlamasına kayması',
  },
  {
    'Atlas Okyanusu ortasındaki okyanus ortası sırtının oluşması',
    "İzlanda'nın ortasından geçen yarık sisteminin oluşması",
  },
];

bool _levhaSira(List<_Etiketli> x) => _enCokBir(x, _levhaAyniOlgu);

/// Deprem seçkisinde üç tür de bulunur ya da tektonik deprem üç kez geçer:
/// volkanik ve çöküntü depremi ögeleri birer tanım olduğundan en çok birer
/// kez, tektonik depremin tanımı olan ögelerden de en çok biri alınır; dört
/// öncülün dördü de tektonik olmaz.
bool _depremSira(List<_Etiketli> x) {
  var tek = 0, tanim = 0, vdep = 0, cok = 0;
  for (final e in x) {
    if (e.$2 == _tek) {
      tek++;
      if (!_depremOrnekleri.contains(e.$1)) tanim++;
    } else if (e.$2 == _vdep) {
      vdep++;
    } else {
      cok++;
    }
  }
  return tek <= 3 && tanim <= 1 && vdep <= 1 && cok <= 1;
}

String _eslesme(List<_Etiketli> x) =>
    '${x.map((e) => '${e.$1}: ${e.$2}').join('; ')}.';

AdvancedItem _icKuvvet(int i) {
  final r = i % 10, tur = i ~/ 10;
  if (r < 7) {
    return _etiketli(
      tur * 7 + r,
      3500,
      _icKuvvetler,
      const [_oro, _epi, _vol, _dep],
      siraSoru: 'Bu oluşumlar sırasıyla hangi iç kuvvet olayına örnektir?',
      hangiSoru: (h, _) => 'Bu oluşumlardan hangileri ${_icKuvvetIle[h]}?',
      aciklama: _eslesme,
      uygunAd: 'icKuvvet',
      siraUygun: _icKuvvetSira,
      celdiriciUygun: (x) => x.where((e) => e == _dep).length <= 1,
    );
  }
  if (r < 9) {
    return _etiketli(
      tur * 2 + r - 7,
      1000,
      _levhalar,
      const [_uzak, _yakin, _yanal],
      siraSoru:
          'Bu oluşumların görüldüğü levha sınırı türleri sırasıyla hangisidir?',
      hangiSoru: (h, _) => 'Bu oluşumlardan hangileri ${_levhaIle[h]} görülür?',
      aciklama: _eslesme,
      uygunAd: 'levha',
      siraUygun: _levhaSira,
    );
  }
  return _etiketli(
    tur,
    500,
    _depremler,
    const [_tek, _vdep, _cok],
    k: 4,
    siraSoru: 'Bu depremler sırasıyla hangi deprem türüne aittir?',
    hangiSoru: (h, _) => 'Bu depremlerden hangileri $h türündendir?',
    aciklama: _eslesme,
    uygunAd: 'deprem',
    siraUygun: _depremSira,
    uygunHer: true,
    // Doğru yanıtta her tür bulunur ya da tektonik deprem üç kez geçer;
    // komşu etiketli çeldiriciler bu kurala uyamadığından döndürmeler kullanılır.
    siraCeldirici: _dondurmeYanlis,
  );
}

final _f09 = lmSirali(
  'cg_ic_kuvvet',
  'İç kuvvetler, levha sınırları ve deprem türleri',
  Topic.geography,
  Difficulty.medium,
  BloomLevel.anlama,
  _icKuvvet,
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
);

// ─────────────────────────────── 10 · Kayaçlar ──────────────────────────────

const _icP = 'iç püskürük', _disP = 'dış püskürük', _fiz = 'fiziksel tortul';
const _kim = 'kimyasal tortul', _org = 'organik tortul', _bas = 'başkalaşım';
const _kayaclar = <_Etiketli>[
  ('Granit', _icP, 'püskürük'),
  ('Siyenit', _icP, 'püskürük'),
  ('Diyorit', _icP, 'püskürük'),
  ('Gabro', _icP, 'püskürük'),
  ('Bazalt', _disP, 'püskürük'),
  ('Andezit', _disP, 'püskürük'),
  ('Riyolit', _disP, 'püskürük'),
  ('Volkanik tüf', _disP, 'püskürük'),
  ('Obsidiyen (volkan camı)', _disP, 'püskürük'),
  ('Ponza (sünger taşı)', _disP, 'püskürük'),
  ('Kum taşı', _fiz, 'tortul'),
  ('Konglomera (yuvarlak çakıllı)', _fiz, 'tortul'),
  ('Breş (köşeli çakıllı)', _fiz, 'tortul'),
  ('Kil', _fiz, 'tortul'),
  ('Traverten', _kim, 'tortul'),
  ('Jips', _kim, 'tortul'),
  ('Kaya tuzu', _kim, 'tortul'),
  ('Taş kömürü', _org, 'tortul'),
  ('Linyit', _org, 'tortul'),
  ('Turba', _org, 'tortul'),
  ('Tebeşir', _org, 'tortul'),
  ('Mercan kalkeri', _org, 'tortul'),
  ('Mermer', _bas, 'başkalaşım'),
  ('Kuvarsit', _bas, 'başkalaşım'),
  ('Gnays', _bas, 'başkalaşım'),
  ('Şist', _bas, 'başkalaşım'),
];
const _kayacOlusum = {
  'Mermer': 'kalkerin başkalaşımıyla oluşur',
  'Kuvarsit': 'kum taşının başkalaşımıyla oluşur',
  'Gnays': 'granitin başkalaşımıyla oluşur',
  'Şist': 'kilin başkalaşımıyla oluşur',
};
const _kayacIfade = {
  'püskürük': 'püskürük (magmatik) kayaçtır',
  'tortul': 'tortul kayaçtır',
  'başkalaşım': 'başkalaşım kayacıdır',
  _icP: 'iç püskürük (derinlik) kayacıdır',
  _disP: 'dış püskürük (yüzey) kayacıdır',
  _fiz: 'fiziksel (mekanik) tortul kayaçtır',
  _kim: 'kimyasal tortul kayaçtır',
  _org: 'organik tortul kayaçtır',
};

final _f10 = lmSirali(
  'cg_kayac',
  'Kayaç türleri ve başkalaşımla oluşan kayaçlar',
  Topic.geography,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) => _etiketli(
    i,
    lmAileBoyu,
    _kayaclar,
    const [_icP, _disP, _fiz, _kim, _org, _bas],
    grupHer: false,
    siraSoru: 'Bu kayaçların türleri sırasıyla hangisidir?',
    hangiSoru: (h, _) => 'Bu kayaçlardan hangileri ${_kayacIfade[h]}?',
    aciklama: (x) =>
        '${x.map((e) {
          final o = _kayacOlusum[e.$1];
          return '${e.$1}: ${e.$2}${o == null ? '' : ' ($o)'}';
        }).join('; ')}.',
  ),
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
);

// ──────────────────────────── 11 · Toprak tipleri ───────────────────────────

const _zonal = 'zonal', _azonal = 'azonal', _intra = 'intrazonal';
const _topraklar = <_Etiketli>[
  (
    'Ekvatoral iklimde yoğun kimyasal ayrışmayla oluşan, demir ve alüminyum oksitçe zengin '
        'kırmızı topraklar',
    'Laterit',
    _zonal,
  ),
  (
    'Aşırı yağış nedeniyle besin maddeleri yıkanmış, yağmur ormanları altında gelişen topraklar',
    'Laterit',
    _zonal,
  ),
  (
    'Soğuk ve nemli iklimde iğne yapraklı ormanların altında oluşan topraklar',
    'Podzol',
    _zonal,
  ),
  (
    'Üst katmanı yıkanmış, kül renkli ve asitli olan, tayga ormanlarının altında gelişen '
        'topraklar',
    'Podzol',
    _zonal,
  ),
  (
    "Sibirya ve Kanada'daki tayga ormanlarının altında geniş alan kaplayan topraklar",
    'Podzol',
    _zonal,
  ),
  (
    'Organik maddece çok zengin, kara renkli ve çok verimli çayır (step) toprakları',
    'Çernozyom',
    _zonal,
  ),
  (
    "Ukrayna ve Kazakistan'daki tahıl alanlarında yaygın olan kara topraklar",
    'Çernozyom',
    _zonal,
  ),
  (
    'Karasal iklimde uzun boylu çayırların altında oluşan topraklar',
    'Çernozyom',
    _zonal,
  ),
  // Türkiye'deki yayılışı ders kitaplarında farklı adlarla (kestane renkli,
  // kahverengi bozkır) verildiğinden yalnız oluşum koşulu sorulur.
  (
    'Yarı kurak karasal iklimde kısa boylu bozkırların altında oluşan topraklar',
    'Kestane renkli toprak',
    _zonal,
  ),
  (
    'Ilıman ve nemli iklimde yaprak döken ormanların altında oluşan topraklar',
    'Kahverengi orman toprağı',
    _zonal,
  ),
  (
    'Kayın, meşe ve gürgen ormanlarının altında oluşan, humusça zengin topraklar',
    'Kahverengi orman toprağı',
    _zonal,
  ),
  (
    'Akdeniz ikliminde kireç taşı (kalker) üzerinde oluşan kırmızı renkli topraklar',
    'Terra rossa',
    null,
  ),
  (
    "Türkiye'de Akdeniz ve Ege kıyılarında kalker arazilerde yaygın olan kırmızı topraklar",
    'Terra rossa',
    null,
  ),
  (
    'Alt katmanı yıl boyunca donmuş kalan, yazın yalnız üst kısmı çözülen kutup çevresi '
        'toprakları',
    'Tundra toprağı',
    _zonal,
  ),
  (
    'Yosun ve likenlerle örtülü soğuk kutup çevresinde oluşan ince topraklar',
    'Tundra toprağı',
    _zonal,
  ),
  (
    'Kurak alanlarda fiziksel ayrışmayla oluşan, organik maddece çok fakir topraklar',
    'Çöl toprağı',
    _zonal,
  ),
  (
    'Bitki örtüsünün çok seyrek olduğu kurak alanlarda gelişen, ince ve taşlı topraklar',
    'Çöl toprağı',
    _zonal,
  ),
  (
    'Oluşumunda iklimden çok kalker ve marn gibi kireçli ana kayanın etkili olduğu koyu renkli '
        'topraklar',
    'Rendzina',
    _intra,
  ),
  (
    'Taban suyunun yüzeye yakın olduğu kurak alanlarda tuz birikmesiyle oluşan çorak topraklar',
    'Halomorfik toprak',
    _intra,
  ),
  (
    "Türkiye'de Tuz Gölü çevresinde ve Iğdır Ovası'nda görülen tuzlu topraklar",
    'Halomorfik toprak',
    _intra,
  ),
  (
    'Taban suyunun yüzeye çok yakın olduğu bataklık alanlarda oluşan topraklar',
    'Hidromorfik toprak',
    _intra,
  ),
  (
    'Akarsuların taşıyıp ova ve deltalarda biriktirdiği verimli topraklar',
    'Alüvyal toprak',
    _azonal,
  ),
  (
    'Çukurova, Bafra ve Çarşamba ovalarında yaygın olan akarsu kökenli topraklar',
    'Alüvyal toprak',
    _azonal,
  ),
  (
    'Akarsu taşkın ovalarında katmanlar hâlinde biriken topraklar',
    'Alüvyal toprak',
    _azonal,
  ),
  (
    'Yamaçlardan yer çekimi ve yüzey sularıyla taşınıp dağ eteklerinde biriken topraklar',
    'Kolüvyal toprak',
    _azonal,
  ),
  (
    'Dağ eteklerinde yamaç molozlarıyla karışık olarak biriken topraklar',
    'Kolüvyal toprak',
    _azonal,
  ),
  (
    'Rüzgârların taşıyıp biriktirdiği ince taneli, verimli topraklar',
    'Lös',
    _azonal,
  ),
  ('Buzulların taşıyıp biriktirdiği topraklar', 'Moren toprağı', _azonal),
];
const _toprakAdlari = [
  'Laterit',
  'Podzol',
  'Çernozyom',
  'Kestane renkli toprak',
  'Kahverengi orman toprağı',
  'Terra rossa',
  'Tundra toprağı',
  'Çöl toprağı',
  'Rendzina',
  'Halomorfik toprak',
  'Hidromorfik toprak',
  'Alüvyal toprak',
  'Kolüvyal toprak',
  'Lös',
  'Moren toprağı',
];
const _kusakIfade = {
  _zonal: 'zonal (iklimin etkisiyle yerinde oluşan)',
  _azonal: 'azonal (taşınmış)',
  _intra: 'intrazonal (ana kaya ya da taban suyunun etkisiyle yerinde oluşan)',
};

final _f11 = lmSirali(
  'cg_toprak',
  'Zonal, azonal ve intrazonal toprak tipleri',
  Topic.geography,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) => _etiketli(
    i,
    lmAileBoyu,
    _topraklar,
    _toprakAdlari,
    // Her öge bir toprak tipinin tanımıdır: sıralı eşleştirmede aynı tipi iki
    // öncülle tanımlayan seçki alınmaz.
    uygunAd: 'toprak',
    siraUygun: _farkliEtiket,
    celdiriciUygun: _farkliDizi,
    siraSoru: 'Bu özelliklerin ait olduğu toprak tipleri sırasıyla hangisidir?',
    hangiSoru: (h, grup) => grup
        ? 'Bu özelliklerden hangileri ${_kusakIfade[h]} topraklara aittir?'
        : 'Bu özelliklerden hangileri ${h[0].toLowerCase()}${h.substring(1)} için '
              'geçerlidir?',
    aciklama: (x) =>
        'Sırasıyla: ${x.map((e) => '${e.$2}${e.$3 == null ? '' : ' (${e.$3})'}').join(', ')}.',
  ),
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
);

// ───────────────────── 12 · Türkiye'de madenler ve yatakları ────────────────

// Her yöreye ders kitaplarında en çok anılan madeni eşlenmiştir. Yanlış yüklemler
// yalnız belirli yörelerde bulunan madenlerden (bor, taş kömürü, petrol, asfaltit,
// boksit) o yörede kesinlikle bulunmayanlardır; krom, demir, linyit gibi ülkenin
// pek çok yerinde bulunan madenler yanlış yüklem yapılmamıştır. Üretimi azalan ya
// da duran yörelerde “yatakları bulunur” denir.
const _madenOnerme = <_Onerme>[
  (
    'Kırka (Eskişehir) yöresinde',
    'bor çıkarılır.',
    ['taş kömürü çıkarılır.', 'petrol çıkarılır.', 'asfaltit çıkarılır.'],
  ),
  (
    'Bigadiç (Balıkesir) yöresinde',
    'bor çıkarılır.',
    ['taş kömürü çıkarılır.', 'asfaltit çıkarılır.', 'petrol çıkarılır.'],
  ),
  (
    'Emet (Kütahya) yöresinde',
    'bor çıkarılır.',
    ['petrol çıkarılır.', 'taş kömürü çıkarılır.', 'asfaltit çıkarılır.'],
  ),
  (
    'Guleman (Elazığ) yöresinde',
    'krom çıkarılır.',
    ['bor çıkarılır.', 'taş kömürü çıkarılır.', 'asfaltit çıkarılır.'],
  ),
  (
    'Divriği (Sivas) yöresinde',
    'demir çıkarılır.',
    ['bor çıkarılır.', 'asfaltit çıkarılır.', 'taş kömürü çıkarılır.'],
  ),
  (
    'Hekimhan (Malatya) yöresinde',
    'demir çıkarılır.',
    ['taş kömürü çıkarılır.', 'bor çıkarılır.', 'asfaltit çıkarılır.'],
  ),
  (
    'Murgul (Artvin) yöresinde',
    'bakır çıkarılır.',
    ['bor çıkarılır.', 'petrol çıkarılır.', 'asfaltit çıkarılır.'],
  ),
  (
    'Küre (Kastamonu) yöresinde',
    'bakır çıkarılır.',
    ['bor çıkarılır.', 'asfaltit çıkarılır.', 'petrol çıkarılır.'],
  ),
  (
    'Seydişehir (Konya) yöresinde',
    'boksit çıkarılır.',
    ['taş kömürü çıkarılır.', 'bor çıkarılır.', 'asfaltit çıkarılır.'],
  ),
  (
    'Akseki (Antalya) yöresinde',
    'boksit çıkarılır.',
    ['bor çıkarılır.', 'taş kömürü çıkarılır.', 'asfaltit çıkarılır.'],
  ),
  (
    'Balya (Balıkesir) yöresinde',
    'kurşun ve çinko yatakları bulunur.',
    [
      'taş kömürü yatakları bulunur.',
      'petrol yatakları bulunur.',
      'asfaltit yatakları bulunur.',
    ],
  ),
  (
    'Halıköy (Ödemiş, İzmir) yöresinde',
    'cıva yatakları bulunur.',
    [
      'bor yatakları bulunur.',
      'taş kömürü yatakları bulunur.',
      'petrol yatakları bulunur.',
    ],
  ),
  (
    'Zonguldak çevresinde',
    'taş kömürü çıkarılır.',
    ['bor çıkarılır.', 'petrol çıkarılır.', 'asfaltit çıkarılır.'],
  ),
  (
    'Afşin-Elbistan (Kahramanmaraş) yöresinde',
    'linyit çıkarılır.',
    ['taş kömürü çıkarılır.', 'bor çıkarılır.', 'asfaltit çıkarılır.'],
  ),
  (
    'Soma (Manisa) yöresinde',
    'linyit çıkarılır.',
    ['taş kömürü çıkarılır.', 'asfaltit çıkarılır.', 'bor çıkarılır.'],
  ),
  (
    'Tunçbilek (Kütahya) yöresinde',
    'linyit çıkarılır.',
    ['taş kömürü çıkarılır.', 'petrol çıkarılır.', 'asfaltit çıkarılır.'],
  ),
  (
    'Batman çevresinde',
    'petrol çıkarılır.',
    ['bor çıkarılır.', 'taş kömürü çıkarılır.', 'boksit çıkarılır.'],
  ),
  (
    'Adıyaman çevresinde',
    'petrol çıkarılır.',
    ['taş kömürü çıkarılır.', 'bor çıkarılır.', 'boksit çıkarılır.'],
  ),
  (
    'Hamitabat (Kırklareli) yöresinde',
    'doğal gaz yatakları bulunur.',
    [
      'bor yatakları bulunur.',
      'taş kömürü yatakları bulunur.',
      'asfaltit yatakları bulunur.',
    ],
  ),
  (
    'Keçiborlu (Isparta) yöresinde',
    'kükürt yatakları bulunur.',
    [
      'bor yatakları bulunur.',
      'taş kömürü yatakları bulunur.',
      'petrol yatakları bulunur.',
    ],
  ),
  (
    'Silopi (Şırnak) yöresinde',
    'asfaltit çıkarılır.',
    ['bor çıkarılır.', 'taş kömürü çıkarılır.', 'boksit çıkarılır.'],
  ),
  (
    'Ovacık (Bergama, İzmir) yöresinde',
    'altın çıkarılır.',
    ['bor çıkarılır.', 'taş kömürü çıkarılır.', 'petrol çıkarılır.'],
  ),
  (
    'Kışladağ (Uşak) yöresinde',
    'altın çıkarılır.',
    ['bor çıkarılır.', 'taş kömürü çıkarılır.', 'petrol çıkarılır.'],
  ),
];

final _f12 = lmSirali(
  'cg_maden',
  "Türkiye'de madenler ve çıkarıldıkları yerler",
  Topic.geography,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) => _dogruYanlis(
    i,
    _madenOnerme,
    "Türkiye'deki maden yöreleriyle ilgili bu bilgilerden hangileri doğrudur?",
  ),
  exam: ExamKind.ayt,
  lesson: 'Coğrafya-1',
);

// ─────────────── 13 · Türkiye'de tarım ürünleri ve yetişme koşulları ────────

const _tarimOnerme = <_Onerme>[
  (
    'Çay',
    "en çok Karadeniz Bölgesi'nde yetiştirilir.",
    [
      "en çok İç Anadolu Bölgesi'nde yetiştirilir.",
      "en çok Güneydoğu Anadolu Bölgesi'nde yetiştirilir.",
      "en çok Ege Bölgesi'nde yetiştirilir.",
    ],
  ),
  (
    'Fındık',
    "en çok Karadeniz Bölgesi'nde yetiştirilir.",
    [
      "en çok Güneydoğu Anadolu Bölgesi'nde yetiştirilir.",
      "en çok İç Anadolu Bölgesi'nde yetiştirilir.",
      "en çok Akdeniz Bölgesi'nde yetiştirilir.",
    ],
  ),
  (
    'Ayçiçeği',
    "en çok Marmara Bölgesi'nin Trakya kesiminde yetiştirilir.",
    [
      "en çok Doğu Anadolu Bölgesi'nde yetiştirilir.",
      "en çok Akdeniz Bölgesi'nde yetiştirilir.",
      "en çok Karadeniz Bölgesi'nde yetiştirilir.",
    ],
  ),
  (
    'Kırmızı mercimek',
    "en çok Güneydoğu Anadolu Bölgesi'nde yetiştirilir.",
    [
      "en çok Karadeniz Bölgesi'nde yetiştirilir.",
      "en çok Marmara Bölgesi'nde yetiştirilir.",
      "en çok Ege Bölgesi'nde yetiştirilir.",
    ],
  ),
  (
    'Antep fıstığı',
    "en çok Güneydoğu Anadolu Bölgesi'nde yetiştirilir.",
    [
      "en çok Karadeniz Bölgesi'nde yetiştirilir.",
      "en çok Marmara Bölgesi'nde yetiştirilir.",
      "en çok Doğu Anadolu Bölgesi'nde yetiştirilir.",
    ],
  ),
  (
    'Kayısı',
    "en çok Doğu Anadolu Bölgesi'nde, Malatya çevresinde yetiştirilir.",
    [
      "en çok Karadeniz Bölgesi'nde yetiştirilir.",
      "en çok Marmara Bölgesi'nde yetiştirilir.",
      "en çok Akdeniz Bölgesi'nde yetiştirilir.",
    ],
  ),
  (
    'Muz',
    "en çok Akdeniz Bölgesi'nde yetiştirilir.",
    [
      "en çok Karadeniz Bölgesi'nde yetiştirilir.",
      "en çok İç Anadolu Bölgesi'nde yetiştirilir.",
      "en çok Doğu Anadolu Bölgesi'nde yetiştirilir.",
    ],
  ),
  (
    'Turunçgiller',
    "en çok Akdeniz Bölgesi'nde yetiştirilir.",
    [
      "en çok İç Anadolu Bölgesi'nde yetiştirilir.",
      "en çok Doğu Anadolu Bölgesi'nde yetiştirilir.",
      "en çok Güneydoğu Anadolu Bölgesi'nde yetiştirilir.",
    ],
  ),
  (
    'Yer fıstığı',
    "en çok Akdeniz Bölgesi'nde, Osmaniye ve Adana çevresinde yetiştirilir.",
    [
      "en çok Karadeniz Bölgesi'nde yetiştirilir.",
      "en çok Doğu Anadolu Bölgesi'nde yetiştirilir.",
      "en çok Marmara Bölgesi'nde yetiştirilir.",
    ],
  ),
  (
    'İncir',
    "en çok Ege Bölgesi'nde, Aydın çevresinde yetiştirilir.",
    [
      "en çok Doğu Anadolu Bölgesi'nde yetiştirilir.",
      "en çok İç Anadolu Bölgesi'nde yetiştirilir.",
      "en çok Karadeniz Bölgesi'nde yetiştirilir.",
    ],
  ),
  (
    'Çekirdeksiz üzüm',
    "en çok Ege Bölgesi'nde, Manisa çevresinde yetiştirilir.",
    [
      "en çok Karadeniz Bölgesi'nde yetiştirilir.",
      "en çok Doğu Anadolu Bölgesi'nde yetiştirilir.",
      "en çok Marmara Bölgesi'nde yetiştirilir.",
    ],
  ),
  (
    'Çay bitkisi',
    'her mevsimi yağışlı ve nemli bir iklim ister.',
    [
      'yaz kuraklığının belirgin olduğu bir iklim ister.',
      'kışları sert ve kurak geçen bir iklim ister.',
    ],
  ),
  (
    'Pamuk',
    'yetişme döneminde bol su ve yüksek sıcaklık, hasat döneminde kurak hava ister.',
    [
      'hasat döneminde bol yağış ister.',
      'yetişme döneminde serin ve kurak hava ister.',
    ],
  ),
  (
    'Buğday',
    'yetişme döneminde serin ve nemli, olgunlaşma döneminde sıcak ve kurak hava ister.',
    [
      'olgunlaşma döneminde bol yağış ister.',
      'yetişme döneminde sıcak ve kurak hava ister.',
    ],
  ),
  (
    'Turunçgil ağaçları',
    'don olayına karşı çok hassastır; kışları ılık geçen yerlerde yetişir.',
    [
      'kışları sert ve soğuk geçen yerlerde yetişir.',
      'don olayına karşı dayanıklıdır.',
    ],
  ),
  (
    'Muz bitkisi',
    'yüksek sıcaklık ve nem ister.',
    [
      'soğuk ve kurak koşullara dayanıklıdır.',
      'kışları karlı geçen yerlerde yetişir.',
    ],
  ),
  (
    'Zeytin',
    'Akdeniz iklimine özgü bir bitkidir.',
    [
      'karasal iklime özgü bir bitkidir.',
      'sert karasal iklime özgü bir bitkidir.',
    ],
  ),
  (
    'Çeltik (pirinç)',
    'yetişme döneminde bol su ister; sulanabilen düz alanlarda yetiştirilir.',
    [
      'suya az ihtiyaç duyar; kuru tarımla yetiştirilir.',
      'sulama yapılmadan kurak yamaçlarda yetiştirilir.',
    ],
  ),
  (
    'Fındık bitkisi',
    'nemli ve yağışlı bir iklim ister.',
    [
      'kurak ve sıcak bir iklim ister.',
      'yağışın çok az olduğu yerlerde yetişir.',
    ],
  ),
];

final _f13 = lmSirali(
  'cg_tarim',
  "Türkiye'de tarım ürünleri, bölgeleri ve yetişme koşulları",
  Topic.geography,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) => _dogruYanlis(
    i,
    _tarimOnerme,
    "Türkiye'de tarım ürünleri ve yetişme koşullarıyla ilgili bu bilgilerden hangileri "
    'doğrudur?',
  ),
  exam: ExamKind.ayt,
  lesson: 'Coğrafya-1',
);

// ─────────────── 14 · Enerji kaynakları ve Türkiye'deki santraller ──────────

const _yenilenebilir = 'yenilenebilir bir enerji kaynağıdır.';
const _yenilenemez = 'yenilenemez bir enerji kaynağıdır.';
const _enerjiOnerme = <_Onerme>[
  (
    'Güneş enerjisi',
    _yenilenebilir,
    [_yenilenemez, 'fosil yakıtlar arasında yer alır.'],
  ),
  (
    'Rüzgâr enerjisi',
    _yenilenebilir,
    [_yenilenemez, 'fosil yakıtlar arasında yer alır.'],
  ),
  (
    'Jeotermal enerji',
    _yenilenebilir,
    [_yenilenemez, 'fosil yakıtlar arasında yer alır.'],
  ),
  (
    'Akarsulardan elde edilen hidroelektrik enerji',
    _yenilenebilir,
    [_yenilenemez, 'fosil yakıtlar arasında yer alır.'],
  ),
  (
    'Biyokütle enerjisi',
    _yenilenebilir,
    [_yenilenemez, 'tükenen bir enerji kaynağıdır.'],
  ),
  (
    'Dalga ve gelgit enerjisi',
    _yenilenebilir,
    [_yenilenemez, 'fosil yakıtlar arasında yer alır.'],
  ),
  (
    'Taş kömürü',
    _yenilenemez,
    [_yenilenebilir, 'tükenmeyen bir enerji kaynağıdır.'],
  ),
  (
    'Linyit',
    _yenilenemez,
    [_yenilenebilir, 'tükenmeyen bir enerji kaynağıdır.'],
  ),
  (
    'Petrol',
    _yenilenemez,
    [_yenilenebilir, 'tükenmeyen bir enerji kaynağıdır.'],
  ),
  (
    'Doğal gaz',
    _yenilenemez,
    [_yenilenebilir, 'tükenmeyen bir enerji kaynağıdır.'],
  ),
  (
    'Nükleer santrallerde kullanılan uranyum',
    _yenilenemez,
    [_yenilenebilir, 'tükenmeyen bir enerji kaynağıdır.'],
  ),
  (
    'Atatürk Barajı üzerindeki santral',
    'hidroelektrik santralidir.',
    ['jeotermal santraldir.', 'termik santraldir.'],
  ),
  (
    'Keban Barajı üzerindeki santral',
    'hidroelektrik santralidir.',
    ['nükleer santraldir.', 'termik santraldir.'],
  ),
  (
    'Deriner Barajı üzerindeki santral',
    'hidroelektrik santralidir.',
    ['jeotermal santraldir.', 'rüzgâr santralidir.'],
  ),
  (
    'Ilısu Barajı üzerindeki santral',
    'hidroelektrik santralidir.',
    ['termik santraldir.', 'güneş santralidir.'],
  ),
  (
    'Afşin-Elbistan santralleri',
    'linyitle çalışan termik santrallerdir.',
    ['hidroelektrik santralleridir.', 'jeotermal santrallerdir.'],
  ),
  (
    'Soma termik santrali',
    'yakıt olarak linyit kullanır.',
    ['yakıt olarak uranyum kullanır.', 'akarsu enerjisiyle çalışır.'],
  ),
  (
    'Kangal termik santrali',
    'yakıt olarak linyit kullanır.',
    ['jeotermal enerjiyle çalışır.', 'akarsu enerjisiyle çalışır.'],
  ),
  (
    'Çatalağzı (Zonguldak) termik santrali',
    'yakıt olarak taş kömürü kullanır.',
    ['akarsu enerjisiyle çalışır.', 'jeotermal enerjiyle çalışır.'],
  ),
  (
    'Kızıldere (Denizli) santrali',
    'jeotermal enerjiyle elektrik üretir.',
    ['linyitle elektrik üretir.', 'rüzgâr enerjisiyle elektrik üretir.'],
  ),
  (
    'Germencik (Aydın) santralleri',
    'jeotermal enerjiyle elektrik üretir.',
    ['taş kömürüyle elektrik üretir.', 'akarsu enerjisiyle elektrik üretir.'],
  ),
  (
    'Akkuyu (Mersin) santrali',
    'nükleer enerjiyle elektrik üretmek için kurulmuştur.',
    [
      'jeotermal enerjiyle elektrik üretmek için kurulmuştur.',
      'linyitle elektrik üretmek için kurulmuştur.',
    ],
  ),
  (
    'Hamitabat (Kırklareli) santrali',
    'doğal gazla çalışan bir termik santraldir.',
    ['hidroelektrik santralidir.', 'jeotermal santraldir.'],
  ),
  (
    'Bozcaada (Çanakkale) santrali',
    'rüzgâr enerjisiyle elektrik üretir.',
    ['jeotermal enerjiyle elektrik üretir.', 'linyitle elektrik üretir.'],
  ),
];

final _f14 = lmSirali(
  'cg_enerji',
  "Enerji kaynakları ve Türkiye'deki santral türleri",
  Topic.geography,
  Difficulty.easy,
  BloomLevel.anlama,
  (i) => _dogruYanlis(
    i,
    _enerjiOnerme,
    "Enerji kaynakları ve Türkiye'deki santrallerle ilgili bu bilgilerden hangileri doğrudur?",
  ),
  exam: ExamKind.ayt,
  lesson: 'Coğrafya-1',
);

// ─────────────── 15 · Türkiye'nin coğrafi bölgeleri ve bölümleri ────────────

// İl merkezlerinin bulunduğu bölge. Toprakları birkaç bölgeye yayılan ve
// sınavlarda tartışmalı sorulan iller (Afyonkarahisar, Bilecik, Kahramanmaraş,
// Sivas, Malatya, Adıyaman vb.) alınmamıştır.
const _bolgeIller = {
  'Marmara': [
    'İstanbul',
    'Edirne',
    'Kırklareli',
    'Tekirdağ',
    'Çanakkale',
    'Kocaeli',
    'Yalova',
    'Sakarya',
    'Bursa',
    'Balıkesir',
  ],
  'Ege': ['İzmir', 'Aydın', 'Muğla', 'Manisa', 'Denizli', 'Uşak', 'Kütahya'],
  'Akdeniz': [
    'Antalya',
    'Mersin',
    'Adana',
    'Hatay',
    'Osmaniye',
    'Isparta',
    'Burdur',
  ],
  'İç Anadolu': [
    'Ankara',
    'Konya',
    'Eskişehir',
    'Kayseri',
    'Yozgat',
    'Kırıkkale',
    'Kırşehir',
    'Nevşehir',
    'Aksaray',
    'Niğde',
    'Karaman',
  ],
  'Karadeniz': [
    'Samsun',
    'Trabzon',
    'Rize',
    'Artvin',
    'Giresun',
    'Ordu',
    'Sinop',
    'Kastamonu',
    'Zonguldak',
    'Bartın',
    'Düzce',
    'Amasya',
    'Tokat',
    'Çorum',
  ],
  'Doğu Anadolu': [
    'Erzurum',
    'Kars',
    'Ardahan',
    'Iğdır',
    'Ağrı',
    'Van',
    'Muş',
    'Bitlis',
    'Bingöl',
    'Tunceli',
    'Elazığ',
    'Hakkari',
  ],
  'Güneydoğu Anadolu': [
    'Gaziantep',
    'Şanlıurfa',
    'Diyarbakır',
    'Mardin',
    'Batman',
    'Siirt',
    'Şırnak',
    'Kilis',
  ],
};

// İl merkezlerinin bulunduğu bölüm; yalnız ders kitaplarında tek bölüme
// bağlanan il merkezleri alınmıştır.
const _bolumIller = {
  'Çatalca-Kocaeli Bölümü': ['İstanbul', 'Kocaeli'],
  'Ergene Bölümü': ['Edirne'],
  'Güney Marmara Bölümü': ['Bursa', 'Balıkesir', 'Çanakkale'],
  'Kıyı Ege Bölümü': ['İzmir', 'Aydın', 'Manisa', 'Muğla'],
  'İç Batı Anadolu Bölümü': ['Uşak', 'Kütahya'],
  'Antalya Bölümü': ['Antalya', 'Isparta', 'Burdur'],
  'Adana Bölümü': ['Adana', 'Mersin', 'Hatay', 'Osmaniye'],
  'Konya Bölümü': ['Konya', 'Karaman'],
  'Yukarı Sakarya Bölümü': ['Ankara', 'Eskişehir'],
  'Orta Kızılırmak Bölümü': [
    'Kayseri',
    'Kırşehir',
    'Nevşehir',
    'Kırıkkale',
    'Yozgat',
  ],
  'Batı Karadeniz Bölümü': ['Zonguldak', 'Bartın', 'Kastamonu', 'Düzce'],
  'Orta Karadeniz Bölümü': ['Samsun', 'Amasya', 'Tokat', 'Çorum'],
  'Doğu Karadeniz Bölümü': ['Giresun', 'Trabzon', 'Rize', 'Artvin'],
  'Erzurum-Kars Bölümü': ['Erzurum', 'Kars', 'Ardahan'],
  'Yukarı Fırat Bölümü': ['Elazığ', 'Tunceli'],
  'Yukarı Murat-Van Bölümü': ['Van', 'Muş', 'Bitlis'],
  'Hakkari Bölümü': ['Hakkari'],
  'Orta Fırat Bölümü': ['Gaziantep', 'Şanlıurfa', 'Kilis'],
  'Dicle Bölümü': ['Diyarbakır', 'Mardin', 'Batman', 'Siirt'],
};

final _bolgeTablo = <_Etiketli>[
  for (final e in _bolgeIller.entries)
    for (final il in e.value) (il, e.key, null),
];
final _bolumTablo = <_Etiketli>[
  for (final e in _bolumIller.entries)
    for (final il in e.value) (il, e.key, null),
];

AdvancedItem _bolge(int i) {
  final r = i % 5, tur = i ~/ 5;
  if (r < 3) {
    return _etiketli(
      tur * 3 + r,
      3000,
      _bolgeTablo,
      _bolgeIller.keys.toList(),
      siraSoru: 'Bu illerin merkezlerinin bulunduğu coğrafi bölgeler sırasıyla hangisidir?',
      hangiSoru: (h, _) =>
          "Bu illerden hangilerinin merkezi $h Bölgesi'ndedir?",
      olumsuzSoru: (h, _) =>
          "Bu illerden hangilerinin merkezi $h Bölgesi'nde değildir?",
      aciklama: (x) =>
          '${x.map((e) => '${e.$1}: ${e.$2} Bölgesi').join('; ')}.',
    );
  }
  return _etiketli(
    tur * 2 + r - 3,
    2000,
    _bolumTablo,
    _bolumIller.keys.toList(),
    siraSoru: 'Bu illerin merkezlerinin bulunduğu coğrafi bölümler sırasıyla hangisidir?',
    hangiSoru: (h, _) => "Bu illerden hangilerinin merkezi $h'ndedir?",
    olumsuzSoru: (h, _) => "Bu illerden hangilerinin merkezi $h'nde değildir?",
    aciklama: (x) => '${x.map((e) => '${e.$1}: ${e.$2}').join('; ')}.',
  );
}

final _f15 = lmSirali(
  'cg_bolge',
  "Türkiye'nin coğrafi bölgeleri ve bölümleri",
  Topic.geography,
  Difficulty.easy,
  BloomLevel.hatirlama,
  _bolge,
  exam: ExamKind.ayt,
  lesson: 'Coğrafya-1',
);

// ───────────────── 16 · Bitki örtüsü türleri ve görüldükleri iklimler ───────

const _maki = 'maki',
    _garig = 'garig',
    _bozkir = 'bozkır (step)',
    _cayir = 'çayır';
const _savan = 'savan', _tundra = 'tundra', _yagmur = 'ekvatoral yağmur ormanı';
const _tayga = 'tayga (iğne yapraklı orman)',
    _yaprak = 'yaprak döken geniş yapraklı orman';
const _muson = 'muson ormanı', _col = 'çöl bitkileri';
const _bitkiler = <_Etiketli>[
  (
    'Yaz kuraklığına dayanıklı, her mevsim yeşil kalan sık ve sert yapraklı çalılar',
    _maki,
    'Akdeniz iklimi',
  ),
  (
    'Kocayemiş, sandal, defne ve mersin gibi türlerden oluşan çalı topluluğu',
    _maki,
    'Akdeniz iklimi',
  ),
  (
    "Türkiye'de kızılçam ormanlarının tahrip edildiği alanlarda gelişen her dem yeşil çalılar",
    _maki,
    'Akdeniz iklimi',
  ),
  (
    'Makilerin tahrip edildiği yerlerde gelişen, daha kısa boylu ve seyrek çalılar',
    _garig,
    'Akdeniz iklimi',
  ),
  (
    'Kekik, adaçayı ve lavanta gibi kokulu, kısa boylu bitkilerden oluşan topluluk',
    _garig,
    'Akdeniz iklimi',
  ),
  (
    'İlkbahar yağışlarıyla yeşeren, yaz kuraklığında sararıp kuruyan otsu bitkiler',
    _bozkir,
    'karasal iklim',
  ),
  (
    "Türkiye'de İç Anadolu'nun yağışı az alanlarında geniş yer kaplayan otsu bitki örtüsü",
    _bozkir,
    'karasal iklim',
  ),
  (
    'Karasal iklimde yağış azlığı nedeniyle ağaçların yetişemediği alanlardaki otsu bitki örtüsü',
    _bozkir,
    'karasal iklim',
  ),
  (
    'Yaz yağışlarının bol olduğu yüksek kesimlerde yazın da yeşil kalan uzun boylu otlar',
    _cayir,
    null,
  ),
  (
    "Türkiye'de Erzurum-Kars Platosu'nda yaygın olan, büyükbaş hayvancılığa elverişli otsu "
        'bitki örtüsü',
    _cayir,
    null,
  ),
  (
    'Yazları yağışlı, kışları kurak tropikal alanlarda uzun boylu otlar ve seyrek ağaçlardan '
        'oluşan bitki örtüsü',
    _savan,
    'savan iklimi',
  ),
  (
    "Afrika'da baobab ağaçlarıyla tanınan, yaz yağışlarıyla yeşeren uzun boylu ot toplulukları",
    _savan,
    'savan iklimi',
  ),
  (
    'Tropikal kuşakta yağışlı ve kurak iki dönemin belirgin olduğu alanların otsu bitki örtüsü',
    _savan,
    'savan iklimi',
  ),
  (
    'Kutup çevresinde, yazları kısa ve serin geçen alanlarda yosun ve likenlerden oluşan bitki '
        'örtüsü',
    _tundra,
    'tundra iklimi',
  ),
  (
    'Toprağın büyük bölümü yıl boyunca donmuş kaldığından ağaçların yetişemediği alanlardaki '
        'bitki örtüsü',
    _tundra,
    'tundra iklimi',
  ),
  (
    'Sıcak ve yağışlı iklimde çok katlı, sık ve her dem yeşil geniş yapraklı ağaçlardan oluşan '
        'ormanlar',
    _yagmur,
    'ekvatoral iklim',
  ),
  (
    'Amazon ve Kongo havzalarında geniş alan kaplayan, tür çeşitliliği çok fazla olan ormanlar',
    _yagmur,
    'ekvatoral iklim',
  ),
  (
    'Ekvator çevresinde yıl boyunca sıcak ve yağışlı koşullarda gelişen sık ormanlar',
    _yagmur,
    'ekvatoral iklim',
  ),
  (
    'Sert karasal iklimde çam, ladin ve köknar gibi iğne yapraklı ağaçlardan oluşan ormanlar',
    _tayga,
    'sert karasal iklim',
  ),
  (
    "Sibirya ve Kanada'da geniş alan kaplayan iğne yapraklı ormanlar",
    _tayga,
    'sert karasal iklim',
  ),
  (
    'Uzun ve sert kışlara dayanıklı, iğne yapraklı ve çoğu her dem yeşil ağaçlardan oluşan '
        'ormanlar',
    _tayga,
    'sert karasal iklim',
  ),
  (
    'Ilıman ve nemli iklimlerde kayın, meşe ve gürgen gibi ağaçlardan oluşan, kışın yaprağını '
        'döken ormanlar',
    _yaprak,
    'ılıman okyanusal iklim',
  ),
  (
    "Batı ve Orta Avrupa'da ılıman okyanusal iklimin etkili olduğu alanlarda yaygın olan ormanlar",
    _yaprak,
    'ılıman okyanusal iklim',
  ),
  (
    'Altında humusça zengin kahverengi orman topraklarının geliştiği ormanlar',
    _yaprak,
    'ılıman okyanusal iklim',
  ),
  (
    "Yazları çok yağışlı, kışları kurak geçen Güney ve Güneydoğu Asya'da görülen, kurak dönemde "
        'yaprağını döken ormanlar',
    _muson,
    'muson iklimi',
  ),
  (
    "Hindistan ve Bangladeş'te yaz aylarında Hint Okyanusu'ndan esen nemli rüzgârların "
        'getirdiği yağışlarla gelişen ormanlar',
    _muson,
    'muson iklimi',
  ),
  (
    'Yağışın çok az olduğu alanlarda kaktüs gibi kuraklığa dayanıklı, seyrek bitkiler',
    _col,
    'çöl iklimi',
  ),
  (
    'Kökleri derinlere uzanan, yapraklarını dikene dönüştürerek su kaybını azaltan bitkiler',
    _col,
    'çöl iklimi',
  ),
];
const _iklimde = {
  'Akdeniz iklimi': 'Akdeniz ikliminde',
  'karasal iklim': 'karasal iklimde',
  'savan iklimi': 'savan ikliminde',
  'tundra iklimi': 'tundra ikliminde',
  'ekvatoral iklim': 'ekvatoral iklimde',
  'sert karasal iklim': 'sert karasal iklimde',
  'ılıman okyanusal iklim': 'ılıman okyanusal iklimde',
  'muson iklimi': 'muson ikliminde',
  'çöl iklimi': 'çöl ikliminde',
};

final _f16 = lmSirali(
  'cg_bitki_ortusu',
  'Bitki örtüsü türleri ve görüldükleri iklimler',
  Topic.geography,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) => _etiketli(
    i,
    lmAileBoyu,
    _bitkiler,
    const [
      _maki,
      _garig,
      _bozkir,
      _cayir,
      _savan,
      _tundra,
      _yagmur,
      _tayga,
      _yaprak,
      _muson,
      _col,
    ],
    grupHer: false,
    // Karasal ile sert karasal, karasal ya da Akdeniz iklimi ile nemli ılıman
    // ormanlar, Akdeniz iklimi ile bozkır, savan ile muson bitki örtüsü bir
    // arada sorulursa “görülür/görülmez” yanıtı tartışmalı olabileceğinden bu
    // çiftlerde seçkideki başka bir grup sorulur.
    celisir: (h, g) => switch ((h, g)) {
      ('karasal iklim', 'sert karasal iklim') ||
      ('sert karasal iklim', 'karasal iklim') ||
      ('karasal iklim', 'ılıman okyanusal iklim') ||
      ('Akdeniz iklimi', 'ılıman okyanusal iklim') ||
      ('Akdeniz iklimi', 'karasal iklim') ||
      ('muson iklimi', 'savan iklimi') ||
      ('savan iklimi', 'muson iklimi') => true,
      _ => false,
    },
    // Her öge bir bitki örtüsünün tanımıdır: sıralı eşleştirmede aynı türü
    // iki öncülle tanımlayan seçki alınmaz.
    uygunAd: 'bitki',
    siraUygun: _farkliEtiket,
    celdiriciUygun: _farkliDizi,
    siraSoru:
        'Bu özelliklerin ait olduğu bitki örtüsü türleri sırasıyla hangisidir?',
    hangiSoru: (h, grup) => grup
        ? 'Bu bitki örtülerinden hangileri ${_iklimde[h]} görülür?'
        : 'Bu özelliklerden hangileri $h için geçerlidir?',
    olumsuzSoru: (h, grup) => grup
        ? 'Bu bitki örtülerinden hangileri ${_iklimde[h]} görülmez?'
        : 'Bu özelliklerden hangileri $h için geçerli değildir?',
    aciklama: (x) =>
        'Sırasıyla: ${x.map((e) => '${e.$2}${e.$3 == null ? '' : ', ${_iklimde[e.$3]} görülür'}').join('; ')}.',
  ),
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
);

// ───────────────── 17 · Ekonomik faaliyetlerin sınıflandırılması ────────────

const _bir = 'birincil', _iki = 'ikincil', _uc = 'üçüncül';
const _faaliyetler = <_Etiketli>[
  ('Tarlada buğday hasat eden bir çiftçi', _bir, null),
  ("Karadeniz'de hamsi avlayan bir balıkçı", _bir, null),
  ('Yaylada küçükbaş hayvan yetiştiren bir çoban', _bir, null),
  ('Ormanda ağaç kesen bir orman işçisi', _bir, null),
  ('Ocakta krom cevheri çıkaran bir maden işçisi', _bir, null),
  ('Kovanlardan bal elde eden bir arıcı', _bir, null),
  ('Bahçesinde fındık toplayan bir üretici', _bir, null),
  ('Serada domates yetiştiren bir üretici', _bir, null),
  ('Süt ineği yetiştiriciliği yapan bir besici', _bir, null),
  ('Ocaktan mermer blokları çıkaran bir işçi', _bir, null),
  ('Havuzlarda alabalık yetiştiren bir üretici', _bir, null),
  ('Dağlarda kekik toplayan bir toplayıcı', _bir, null),
  ('Pamuk tarlasında çalışan bir tarım işçisi', _bir, null),
  ('Şeker fabrikasında pancarı şekere işleyen bir işçi', _iki, null),
  ('Dokuma fabrikasında iplikten kumaş üreten bir işçi', _iki, null),
  ('Kereste fabrikasında tomrukları biçen bir işçi', _iki, null),
  ('Otomobil fabrikasında montaj hattında çalışan bir işçi', _iki, null),
  ('Un fabrikasında buğdayı öğüten bir işçi', _iki, null),
  ('Süt fabrikasında peynir üreten bir işçi', _iki, null),
  ('Demir-çelik fabrikasında çelik üreten bir işçi', _iki, null),
  ('Konserve fabrikasında balık konservesi hazırlayan bir işçi', _iki, null),
  ('Kâğıt fabrikasında odundan kâğıt hamuru üreten bir işçi', _iki, null),
  ('Zeytinyağı fabrikasında zeytinden yağ elde eden bir işçi', _iki, null),
  ('Çay fabrikasında yaş çayı kuru çaya işleyen bir işçi', _iki, null),
  ('Mobilya atölyesinde masa yapan bir marangoz', _iki, null),
  ('Mermer fabrikasında blokları plakaya dönüştüren bir işçi', _iki, null),
  // Eğitim, bankacılık ve hukuk gibi bilgiye dayalı hizmetler bazı ders
  // kitaplarında dördüncül faaliyet sayıldığından üçüncül örnek yapılmamıştır.
  ('Hastanede hasta muayene eden bir doktor', _uc, null),
  ('Otelde konukları karşılayan bir resepsiyon görevlisi', _uc, null),
  ('Ürünleri limandan kente taşıyan bir tır şoförü', _uc, null),
  ('Pazarda sebze satan bir esnaf', _uc, null),
  ('Turistlere kent turu yaptıran bir turist rehberi', _uc, null),
  ('Kargo şirketinde paket dağıtan bir kurye', _uc, null),
  ('Mağazada giysi satan bir satış görevlisi', _uc, null),
  ('Uçakta yolculara hizmet veren bir kabin görevlisi', _uc, null),
  ('Belediyede çöp toplayan bir temizlik görevlisi', _uc, null),
  ('Eczanede ilaç satan bir eczacı', _uc, null),
  ('Lokantada yemek servisi yapan bir garson', _uc, null),
  ('Berber dükkânında saç kesen bir berber', _uc, null),
];

final _f17 = lmSirali(
  'cg_ekonomik_faaliyet',
  'Birincil, ikincil ve üçüncül ekonomik faaliyetler',
  Topic.geography,
  Difficulty.easy,
  BloomLevel.anlama,
  (i) => _etiketli(
    i,
    lmAileBoyu,
    _faaliyetler,
    const [_bir, _iki, _uc],
    siraSoru: 'Bu kişilerin yaptığı ekonomik faaliyetler sırasıyla hangi gruba girer?',
    hangiSoru: (h, _) =>
        'Bu kişilerden hangileri $h ekonomik faaliyette bulunmaktadır?',
    aciklama: (x) => '${x.map((e) => '${e.$1}: ${e.$2} faaliyet').join('; ')}.',
  ),
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
);

// ─────────────────────── 18 · Göç türleri ve nedenleri ──────────────────────

const _icGoc = 'iç göç', _disGoc = 'dış göç', _beyin = 'beyin göçü';
const _mevsim = 'mevsimlik göç',
    _zorunlu = 'zorunlu göç',
    _gonullu = 'gönüllü göç';
const _gocTurleri = [_icGoc, _disGoc, _beyin, _mevsim, _zorunlu, _gonullu];
const _gocaYonelme = {
  _icGoc: 'iç göçe',
  _disGoc: 'dış göçe',
  _beyin: 'beyin göçüne',
  _mevsim: 'mevsimlik göçe',
  _zorunlu: 'zorunlu göçe',
  _gonullu: 'gönüllü göçe',
};
// Her örnek iç ya da dış göçtür ve gönüllü ya da zorunludur; beyin göçü ile
// mevsimlik göç ayrıca işaretlenmiştir.
const _gocOrnekleri = <(String, List<String>)>[
  (
    'Kırsal kesimden iş bulmak amacıyla büyük kentlere yerleşen aileler',
    [_icGoc, _gonullu],
  ),
  (
    "1961 yılında imzalanan iş gücü anlaşmasıyla çalışmak için Almanya'ya giden işçiler",
    [_disGoc, _gonullu],
  ),
  (
    'Daha iyi araştırma olanakları için yurt dışındaki üniversitelere yerleşen bilim insanları',
    [_disGoc, _beyin, _gonullu],
  ),
  (
    'Yüksek ücretle yurt dışındaki bir şirkette çalışmaya başlayan yazılım mühendisleri',
    [_disGoc, _beyin, _gonullu],
  ),
  (
    'Yurt dışındaki hastanelerde çalışmak üzere ülkesinden ayrılan uzman doktorlar',
    [_disGoc, _beyin, _gonullu],
  ),
  (
    'Yurt dışında doktora yapıp eğitim aldıkları ülkede kalarak çalışmaya başlayan araştırmacılar',
    [_disGoc, _beyin, _gonullu],
  ),
  (
    "Fındık hasadı için her yıl Karadeniz'e gidip hasattan sonra memleketine dönen tarım işçileri",
    [_icGoc, _mevsim, _gonullu],
  ),
  (
    "Pamuk toplamak için her yıl Çukurova'ya gidip mevsim sonunda geri dönen tarım işçileri",
    [_icGoc, _mevsim, _gonullu],
  ),
  (
    "Turizm sezonunda Antalya'daki otellerde çalışıp sezon bitince evine dönen gençler",
    [_icGoc, _mevsim, _gonullu],
  ),
  (
    'Komşu ülkeden her yıl hasat döneminde gelip mevsim sonunda ülkesine dönen tarım işçileri',
    [_disGoc, _mevsim, _gonullu],
  ),
  (
    'Savaş nedeniyle evlerini terk ederek komşu ülkeye sığınan aileler',
    [_disGoc, _zorunlu],
  ),
  (
    '1923 yılında Türkiye ile Yunanistan arasında yapılan nüfus mübadelesi',
    [_disGoc, _zorunlu],
  ),
  (
    'Siyasi baskılar nedeniyle ülkesini terk etmek zorunda kalan kişiler',
    [_disGoc, _zorunlu],
  ),
  (
    'Baraj gölünün altında kalan köyden başka bir ile yerleştirilen aileler',
    [_icGoc, _zorunlu],
  ),
  (
    'Depremde evleri yıkıldığı için başka bir kente taşınmak zorunda kalan aileler',
    [_icGoc, _zorunlu],
  ),
  (
    'Sel felaketinde köyleri yaşanamaz hâle gelince başka bir ilçeye yerleştirilen aileler',
    [_icGoc, _zorunlu],
  ),
  (
    'Kuraklık nedeniyle tarım yapılamayan köylerinden kentlere göç etmek zorunda kalan aileler',
    [_icGoc, _zorunlu],
  ),
  (
    'Heyelan tehlikesi nedeniyle devlet tarafından başka bir yere taşınan köy halkı',
    [_icGoc, _zorunlu],
  ),
  (
    'Emekli olduktan sonra Ege kıyısındaki bir ilçeye kalıcı olarak yerleşen kişiler',
    [_icGoc, _gonullu],
  ),
  (
    'Fabrikalarda çalışmak için doğdukları ilden ayrılıp bir sanayi kentine yerleşen gençler',
    [_icGoc, _gonullu],
  ),
  (
    'Daha iyi iş olanakları için başka bir ülkeye yerleşen inşaat işçileri',
    [_disGoc, _gonullu],
  ),
  (
    'Kentteki yaşam koşulları daha iyi olduğu için ailesiyle birlikte köyünden kente taşınan bir '
        'esnaf',
    [_icGoc, _gonullu],
  ),
];

const _itici = 'itici etmen', _cekici = 'çekici etmen';
const _gocEtmenleri = <_Etiketli>[
  ('Kırsal kesimde tarım arazilerinin miras yoluyla küçülmesi', _itici, null),
  (
    'Tarımda makineleşmeyle kırsal kesimde iş gücüne duyulan ihtiyacın azalması',
    _itici,
    null,
  ),
  ('Köylerde eğitim ve sağlık hizmetlerinin yetersiz olması', _itici, null),
  ('Kırsal kesimde iş olanaklarının az olması', _itici, null),
  (
    'Kırsal kesimde nüfusun hızla artması ve toprağın yetersiz kalması',
    _itici,
    null,
  ),
  ('Yaşanılan yerde sık görülen doğal afetler', _itici, null),
  ('Kırsal kesimde kan davaları ve güvenlik sorunları', _itici, null),
  ('Köylerde gelir düzeyinin düşük olması', _itici, null),
  ('Tarım ürünlerinden elde edilen gelirin yetersiz kalması', _itici, null),
  ('Kentlerde sanayi kuruluşlarının iş olanağı sağlaması', _cekici, null),
  ('Kentlerde eğitim ve sağlık hizmetlerinin gelişmiş olması', _cekici, null),
  ('Kentlerde ücretlerin daha yüksek olması', _cekici, null),
  ('Kentlerde ulaşım ve altyapı olanaklarının gelişmiş olması', _cekici, null),
  ('Kentlerde kültürel ve sosyal etkinliklerin fazla olması', _cekici, null),
  (
    'Turizm merkezlerinde hizmet sektöründe iş olanaklarının artması',
    _cekici,
    null,
  ),
  ('Kentlerde ticaret ve hizmet sektörünün gelişmiş olması', _cekici, null),
  ('Büyük kentlerde iş bulma olasılığının yüksek olması', _cekici, null),
  ('Gelişmiş ülkelerde yaşam standartlarının yüksek olması', _cekici, null),
];

AdvancedItem _goc(int i) {
  final r = i % 5, tur = i ~/ 5;
  if (r < 3) {
    // Seçki ve sorulan göç türü birlikte kökü belirler; her örnek en az iki
    // türe girdiğinden aynı üçlü iki farklı türle sorulabilir.
    final j = tur * 3 + r;
    final toplam = kombinasyonSayisi(_gocOrnekleri.length, 3);
    final t = j % toplam, kat = j ~/ toplam;
    final u = kombinasyon(_gocOrnekleri, 3, t, spread: false);
    final d = ucluDizilimler[t % 6];
    final x = [u[d[0]], u[d[1]], u[d[2]]];
    final birlesim = [
      for (final g in _gocTurleri)
        if (x.any((e) => e.$2.contains(g))) g,
    ];
    final hedef = birlesim[(t + kat) % birlesim.length];
    var maske = 0;
    for (var p = 0; p < 3; p++) {
      if (x[p].$2.contains(hedef)) maske |= 1 << p;
    }
    return _hangileri(
      '${_liste([for (final e in x) e.$1])}\nBu göç örneklerinden hangileri '
          '${_gocaYonelme[hedef]} örnektir?',
      maske,
      3,
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. örnek: ${x[p].$2.join(', ')}'].join('; ')}.',
      j,
    );
  }
  return _etiketli(
    tur * 2 + r - 3,
    2000,
    _gocEtmenleri,
    const [_itici, _cekici],
    k: 4,
    siraSoru:
        'Bu etmenler göçün itici mi yoksa çekici etmeni mi olduklarına göre sırasıyla nasıl '
        'sınıflandırılır?',
    hangiSoru: (h, _) =>
        'Bu etmenlerden hangileri göçün ${h == _itici ? 'itici' : 'çekici'} etmenlerindendir?',
    aciklama: (x) => '${x.map((e) => '${e.$1}: ${e.$2}').join('; ')}.',
  );
}

final _f18 = lmSirali(
  'cg_goc',
  'Göç türleri, itici ve çekici etmenler',
  Topic.geography,
  Difficulty.medium,
  BloomLevel.anlama,
  _goc,
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
);

// ─────────────── 19 · Doğal afetler: nedenler, alanlar ve önlemler ──────────

const _afDeprem = 'deprem',
    _afHeyelan = 'heyelan',
    _afSel = 'sel',
    _afCig = 'çığ';
const _afErozyon = 'erozyon',
    _afKurak = 'kuraklık',
    _afYangin = 'orman yangını';
const _afTsunami = 'tsunami', _afVolkan = 'volkan patlaması';
const _afetler = <_Etiketli>[
  (
    'Yer kabuğunda biriken enerjinin fay hatları boyunca aniden boşalmasıyla oluşur.',
    _afDeprem,
    null,
  ),
  (
    "Türkiye'de Kuzey Anadolu ve Doğu Anadolu fay hatları boyunca sık yaşanır.",
    _afDeprem,
    null,
  ),
  (
    'Eşyaların duvara sabitlenmesi ve binalarda taşıyıcı kolonların kesilmemesi zararını azaltır.',
    _afDeprem,
    null,
  ),
  (
    'Odak noktasından yayılan sarsıntı dalgalarıyla geniş alanlarda yıkıma yol açar.',
    _afDeprem,
    null,
  ),
  (
    'Eğimli yamaçlarda kil gibi kaygan tabakaların suya doyarak yer çekimiyle kaymasıyla oluşur.',
    _afHeyelan,
    null,
  ),
  (
    "Türkiye'de en sık, eğimli ve yağışlı yamaçların bulunduğu Karadeniz Bölgesi'nde görülen "
        'kütle hareketidir.',
    _afHeyelan,
    null,
  ),
  (
    'Yamaç eteklerinin yol ve bina yapımı için kazılmaması ve istinat duvarları yapılması '
        'zararını azaltır.',
    _afHeyelan,
    null,
  ),
  (
    'Kısa sürede düşen sağanak yağışlar ya da ani kar erimeleriyle akarsuların yatağından '
        'taşmasıyla oluşur.',
    _afSel,
    null,
  ),
  (
    'Dere yataklarına yapı yapılmaması ve akarsu yataklarının ıslah edilmesi zararını azaltır.',
    _afSel,
    null,
  ),
  (
    'Ani yağışlarla dar vadilerde kısa sürede yükselen sular can ve mal kaybına yol açar.',
    _afSel,
    null,
  ),
  (
    'Eğimli dağ yamaçlarında biriken kar kütlesinin aniden kayarak aşağı inmesidir.',
    _afCig,
    null,
  ),
  (
    "Türkiye'de en çok Doğu Anadolu'nun ve Doğu Karadeniz'in yüksek kesimlerinde görülür.",
    _afCig,
    null,
  ),
  (
    'Yamaçlara kar tutucu çitler ve bariyerler kurulması zararını azaltır.',
    _afCig,
    null,
  ),
  (
    'Bitki örtüsünden yoksun eğimli arazilerde toprağın rüzgâr ve sularla taşınmasıdır.',
    _afErozyon,
    null,
  ),
  (
    'Eğimli arazilerde taraçalama yapılması ve eğime dik sürüm uygulanması etkisini azaltır.',
    _afErozyon,
    null,
  ),
  (
    'Toprağın verimli üst katmanının taşınmasına yol açarak tarım alanlarını verimsizleştirir.',
    _afErozyon,
    null,
  ),
  (
    'Yağışın uzun süre normalin altında kalmasıyla su kaynaklarının azalmasıdır.',
    _afKurak,
    null,
  ),
  (
    'Damla sulamaya geçilmesi ve suyun tasarruflu kullanılması etkisini azaltır.',
    _afKurak,
    null,
  ),
  (
    'Uzun süre yağış almayan tarım alanlarında ürün kaybına ve su sıkıntısına yol açar.',
    _afKurak,
    null,
  ),
  (
    "Türkiye'de en çok yazları sıcak ve kurak geçen Akdeniz ve Ege kıyılarında görülür.",
    _afYangin,
    null,
  ),
  (
    'Ormanlarda yangın şeritleri açılması ve gözetleme kuleleri kurulması zararını azaltır.',
    _afYangin,
    null,
  ),
  (
    'Çoğu insan kaynaklı olup kızılçam ormanlarının yaygın olduğu kıyılarda büyük zarar verir.',
    _afYangin,
    null,
  ),
  (
    'Deniz tabanındaki ani hareketlerin oluşturduğu, kıyıya ulaştığında büyük yıkıma yol açan dev dalgalardır.',
    _afTsunami,
    null,
  ),
  (
    'Kıyılarda dev dalgalara karşı erken uyarı sistemleri kurulması zararını azaltır.',
    _afTsunami,
    null,
  ),
  (
    'Açık denizde fark edilmeyen dalgaların kıyıya yaklaştıkça yükselerek kıyı yerleşmelerini '
        'su altında bırakmasıdır.',
    _afTsunami,
    null,
  ),
  (
    'Magmanın yer kabuğundaki çatlaklardan lav ve kül olarak yeryüzüne çıkmasıyla oluşur.',
    _afVolkan,
    null,
  ),
  (
    "İtalya'daki Etna ve Vezüv dağlarında lav ve kül çıkışıyla yaşanan afettir.",
    _afVolkan,
    null,
  ),
  (
    'Etkin yanardağların çevresine yerleşilmemesi ve yanardağların sürekli izlenmesi '
        'zararını azaltır.',
    _afVolkan,
    null,
  ),
];

final _f19 = lmSirali(
  'cg_afet',
  'Doğal afetler: nedenleri, görüldüğü yerler ve önlemler',
  Topic.geography,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) => _etiketli(
    i,
    lmAileBoyu,
    _afetler,
    const [
      _afDeprem,
      _afHeyelan,
      _afSel,
      _afCig,
      _afErozyon,
      _afKurak,
      _afYangin,
      _afTsunami,
      _afVolkan,
    ],
    // Her öge bir afete ait bilgidir: sıralı eşleştirmede aynı afete ait iki
    // bilgi bir seçkide bulunmaz.
    uygunAd: 'afet',
    siraUygun: _farkliEtiket,
    celdiriciUygun: _farkliDizi,
    siraSoru: 'Bu bilgilerin ait olduğu doğal afetler sırasıyla hangisidir?',
    hangiSoru: (h, _) => 'Bu bilgilerden hangileri $h afetine aittir?',
    olumsuzSoru: (h, _) => 'Bu bilgilerden hangileri $h afetine ait değildir?',
    aciklama: (x) => 'Sırasıyla: ${x.map((e) => e.$2).join(', ')}.',
  ),
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
);

// ─────────────── 20 · Göl türleri, Türkiye'den örnekler ve akarsu rejimi ────

const _gTek = 'tektonik göl', _gVol = 'volkanik göl', _gKar = 'karstik göl';
const _gHey = 'heyelan set gölü',
    _gLav = 'volkanik set gölü',
    _gAlu = 'alüvyal set gölü';
const _gKiy = 'kıyı set gölü';
const _setGolleri = {_gHey, _gLav, _gAlu, _gKiy};
const _goller = <(String, String)>[
  ('Tuz Gölü', _gTek),
  ('Burdur Gölü', _gTek),
  ('Acıgöl (Denizli-Afyonkarahisar)', _gTek),
  ('Hazar Gölü', _gTek),
  ('Sapanca Gölü', _gTek),
  ('İznik Gölü', _gTek),
  ('Manyas (Kuş) Gölü', _gTek),
  ('Uluabat Gölü', _gTek),
  ('Eber Gölü', _gTek),
  ('Akşehir Gölü', _gTek),
  ('Nemrut Krater Gölü', _gVol),
  ('Meke Gölü', _gVol),
  ('Gölcük Gölü (Isparta)', _gVol),
  // Salda Gölü bazı kaynaklarda tektonik-karstik sayıldığından alınmamıştır.
  ('Avlan Gölü', _gKar),
  ('Suğla Gölü', _gKar),
  ('Hafik Gölü', _gKar),
  ('Tödürge Gölü', _gKar),
  ('Kızören Obruğu', _gKar),
  ('Tortum Gölü', _gHey),
  ('Sera Gölü', _gHey),
  ('Yedigöller', _gHey),
  ('Borabay Gölü', _gHey),
  ('Zinav Gölü', _gHey),
  ('Van Gölü', _gLav),
  ('Çıldır Gölü', _gLav),
  ('Nazik Gölü', _gLav),
  ('Haçlı Gölü', _gLav),
  ('Bafa Gölü', _gAlu),
  ('Marmara Gölü (Manisa)', _gAlu),
  ('Eymir Gölü', _gAlu),
  ('Mogan Gölü', _gAlu),
  ('Terkos (Durusu) Gölü', _gKiy),
  ('Küçükçekmece Gölü', _gKiy),
  ('Büyükçekmece Gölü', _gKiy),
  ('Akyatan Gölü', _gKiy),
  ('Paradeniz Gölü', _gKiy),
];
const _golIfade = {
  _gTek: 'tektonik kökenlidir',
  _gVol: 'volkanik bir çanakta (krater, kaldera ya da maar) oluşmuştur',
  _gKar: 'karstik kökenlidir',
  _gHey: 'heyelan set gölüdür',
  _gLav: 'volkanik set (lav seti) gölüdür',
  _gAlu: 'alüvyal set gölüdür',
  _gKiy: 'kıyı set gölüdür',
};

const _rejimOnerme = <_Onerme>[
  (
    'Ekvatoral iklim bölgesindeki akarsuların',
    'akımı yıl boyunca yüksektir ve rejimleri düzenlidir.',
    [
      'akımı yaz aylarında kesilir.',
      'en yüksek akımı kar erimeleriyle ilkbaharda görülür.',
    ],
  ),
  (
    'Akdeniz iklim bölgesindeki akarsuların',
    'akımı kışın artar, yazın azalır.',
    ['akımı yazın en yüksek düzeye çıkar.', 'akımı yıl boyunca aynı kalır.'],
  ),
  (
    'Ilıman okyanusal iklim bölgesindeki akarsuların',
    'rejimi, yağış yıla dengeli dağıldığından düzenlidir.',
    [
      'rejimi çok düzensizdir ve yazın kururlar.',
      'akımı yalnız kış aylarında görülür.',
    ],
  ),
  (
    'Muson iklim bölgesindeki akarsuların',
    'akımı yaz yağışlarıyla yazın en yüksek düzeye ulaşır.',
    ['akımı kışın en yüksek düzeye ulaşır.', 'akımı yıl boyunca aynı kalır.'],
  ),
  (
    'Sert karasal iklim bölgesindeki akarsular',
    'kışın donar, ilkbaharda buzların çözülmesiyle taşkınlara yol açar.',
    ['kışın en yüksek akıma ulaşır.', 'yıl boyunca donmadan akar.'],
  ),
  (
    'Karasal iklim bölgesindeki akarsuların',
    'akımı ilkbaharda kar erimeleri ve yağışlarla artar, yazın azalır.',
    ['akımı yazın en yüksek düzeye çıkar.', 'akımı yıl boyunca aynı kalır.'],
  ),
  (
    'Fırat ve Dicle nehirlerinin',
    'en yüksek akımı kar erimelerinin etkisiyle ilkbaharda görülür.',
    [
      'en yüksek akımı sonbaharda görülür.',
      'en düşük akımı ilkbaharda görülür.',
    ],
  ),
  (
    "Doğu Karadeniz'deki akarsuların",
    "rejimi Türkiye'nin diğer bölgelerindeki akarsulara göre daha düzenlidir.",
    [
      "rejimi Türkiye'deki akarsular arasında en düzensiz olanıdır.",
      'akımı yaz aylarında tamamen kesilir.',
    ],
  ),
  (
    "Akdeniz Bölgesi'ndeki akarsuların",
    'akımı yaz aylarında en düşük düzeye iner.',
    [
      'akımı yaz aylarında en yüksek düzeye çıkar.',
      'akımı kış aylarında en düşük düzeye iner.',
    ],
  ),
  (
    'Karstik kaynaklardan beslenen akarsuların',
    'rejimi daha düzenlidir.',
    ['rejimi çok düzensizdir.', 'akımı yağışlardan hemen sonra kesilir.'],
  ),
  (
    'Bir gölden beslenen akarsuların',
    'rejimi, göl suyu düzenlediği için daha düzenlidir.',
    [
      'rejimi, göl suyu biriktirdiği için çok düzensizdir.',
      'akımı yalnız kar erimesiyle oluşur.',
    ],
  ),
  (
    'Buzullarla beslenen akarsuların',
    'akımı buzulların eridiği yaz aylarında artar.',
    [
      'akımı kış aylarında en yüksek düzeye çıkar.',
      'akımı yaz aylarında kesilir.',
    ],
  ),
  (
    'Akarsular üzerine kurulan barajlar',
    'akarsuların rejimini düzenler.',
    [
      'akarsuların rejimini düzensizleştirir.',
      'akarsuların taşıdığı su miktarını artırır.',
    ],
  ),
  (
    'Yağışın yıl içinde düzensiz dağıldığı yerlerdeki akarsuların',
    'rejimi de düzensizdir.',
    ['rejimi çok düzenlidir.', 'akımı yıl boyunca değişmez.'],
  ),
];

AdvancedItem _golAkarsu(int i) {
  final r = i % 10, tur = i ~/ 10;
  if (r >= 7) {
    return _dogruYanlis(
      tur * 3 + r - 7,
      _rejimOnerme,
      'Akarsu rejimleriyle ilgili bu bilgilerden hangileri doğrudur?',
    );
  }
  final j = tur * 7 + r, s = j ~/ 2;
  final x = _secki(_goller, 3, s, 1750);
  final tur3 = [for (final e in x) e.$2];
  final liste = '${_liste([for (final e in x) e.$1])}\n';
  final aciklama = '${x.map((e) => '${e.$1}: ${e.$2}').join('; ')}.';
  if (j.isEven) {
    return secenekli(
      '${liste}Bu göllerin oluşumlarına göre türleri sırasıyla hangisidir?',
      tur3.join(' – '),
      _siraYanlis(tur3, const [
        _gTek,
        _gVol,
        _gKar,
        _gHey,
        _gLav,
        _gAlu,
        _gKiy,
      ], s),
      aciklama,
    );
  }
  final setVar = tur3.any(_setGolleri.contains);
  if (s % 3 == 0 && setVar) {
    var maske = 0;
    for (var p = 0; p < 3; p++) {
      if (_setGolleri.contains(tur3[p])) maske |= 1 << p;
    }
    return _hangileri(
      '${liste}Bu göllerden hangileri set gölüdür?',
      maske,
      3,
      aciklama,
      s,
    );
  }
  final hedef = tur3[s % 3];
  var maske = 0;
  for (var p = 0; p < 3; p++) {
    if (tur3[p] == hedef) maske |= 1 << p;
  }
  return _hangileri(
    '${liste}Bu göllerden hangileri ${_golIfade[hedef]}?',
    maske,
    3,
    aciklama,
    s,
  );
}

final _f20 = lmSirali(
  'cg_gol_akarsu',
  "Göl türleri, Türkiye'deki örnekleri ve akarsu rejimi",
  Topic.geography,
  Difficulty.medium,
  BloomLevel.hatirlama,
  _golAkarsu,
  exam: ExamKind.tyt,
  lesson: 'Coğrafya',
);

// ─────────────────────────────── Aile listesi ───────────────────────────────

final lmCografyaEk = <AdvancedFamily>[
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
