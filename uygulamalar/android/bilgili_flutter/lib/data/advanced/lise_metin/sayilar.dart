// TYT temel matematik, ikinci tur: 9.–10. sınıf sayılar ve cebir konularından
// (asal çarpanlar, faktöriyel, aralık, fonksiyon, polinom, ikinci derece ve
// sözel problemler) 20 metin ailesi; her aile 5.000 ayrı soru üretir.
import 'denge.dart';
import 'ortak.dart';

// ---------------------------------------------------------------------------
// Ortak yardımcılar
// ---------------------------------------------------------------------------

AdvancedFamily _sy(
  String key,
  String title,
  Difficulty difficulty,
  BloomLevel bloom,
  LmUretec build, {
  bool shortAnswer = true,
}) => lmAile(
  'sy_$key',
  title,
  Topic.mathematics,
  difficulty,
  bloom,
  build,
  exam: ExamKind.tyt,
  lesson: 'Temel Matematik',
  shortAnswer: shortAnswer,
);

AdvancedFamily _sySirali(
  String key,
  String title,
  Difficulty difficulty,
  BloomLevel bloom,
  AdvancedItem Function(int i) build, {
  bool shortAnswer = false,
}) => lmSirali(
  'sy_$key',
  title,
  Topic.mathematics,
  difficulty,
  bloom,
  build,
  exam: ExamKind.tyt,
  lesson: 'Temel Matematik',
  shortAnswer: shortAnswer,
);

const _ustRakam = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];

/// Üst simge: `_ust(12)` → `¹²`, `_ust(-3)` → `⁻³`.
String _ust(int n) => n < 0
    ? '⁻${_ust(-n)}'
    : [for (final r in '$n'.codeUnits) _ustRakam[r - 48]].join();

/// İşaretli tam sayı: `_n(-3)` → `−3`.
String _n(int x) => x < 0 ? '−${-x}' : '$x';

/// İşlem içinde negatif sayı paranteze alınır: `_p(-3)` → `(−3)`.
String _p(int x) => x < 0 ? '(−${-x})' : '$x';

/// Sade kesir, eksi işareti tipografik: `_q(-6, 4)` → `−3/2`.
String _q(int n, int d) => kesir(n, d).replaceAll('-', '−');

int _kuvvet(int taban, int us) {
  var r = 1;
  for (var i = 0; i < us; i++) {
    r *= taban;
  }
  return r;
}

int _carp(Iterable<int> x) => x.fold(1, (s, e) => s * e);

int _topla(Iterable<int> x) => x.fold(0, (s, e) => s + e);

/// [adaylar] içinden [uygun] koşulunu sağlayanların [i] numaralısı. Sıra
/// korunduğundan farklı [i] farklı değer verir.
T _uygun<T>(Iterable<T> adaylar, int i, bool Function(T) uygun) =>
    adaylar.where(uygun).elementAt(i);

final _kokSayiDeseni = RegExp(r'(?<![\w,/])(-?\d+(?:,\d+)?(?:/\d+)?)(?![\d,])');
final _onluKuvvet = RegExp('10[⁰¹²³⁴⁵⁶⁷⁸⁹⁻]+');
final _simgeler = RegExp('[⁰¹²³⁴⁵⁶⁷⁸⁹⁻₀₁₂₃₄₅₆₇₈₉]');

/// Sayı yazısının mutlak değeri sade kesir olarak: `−3,5` → (7, 2).
(int, int)? _rasyonelDeger(String t) {
  var s = t.replaceAll('−', '-');
  if (s.startsWith('-')) s = s.substring(1);
  var pay = 0, payda = 1;
  final kesirli = s.split('/');
  final govde = kesirli.first.split(',');
  pay = int.tryParse(govde.first) ?? -1;
  if (pay < 0) return null;
  if (govde.length == 2) {
    final ondalik = govde[1];
    final k = _kuvvet(10, ondalik.length);
    pay = pay * k + (int.tryParse(ondalik) ?? 0);
    payda = k;
  }
  if (kesirli.length == 2) {
    final d = int.tryParse(kesirli[1]);
    if (d == null || d == 0) return null;
    payda *= d;
  }
  final g = pay.gcd(payda);
  return g == 0 ? (0, 1) : (pay ~/ g, payda ~/ g);
}

/// Yanıt, kökte yazılı bir sayıya (üsler ve alt simgeler hariç) eşitse doğru.
/// Öğrencinin kökteki bir sayıyı seçerek doğru yanıta ulaşabildiği vakaları
/// ayıklamak için kullanılır.
bool _yanitKokte(AdvancedItem r) {
  final y = r.correct.trim();
  if (RegExp(r'[x√{·]').hasMatch(y) ||
      y.startsWith('Yalnız') ||
      y.startsWith('I')) {
    return false;
  }
  final m = RegExp(r'^([−-]?\d+(?:,\d+)?(?:/\d+)?)(\s.*)?$').firstMatch(y);
  if (m == null) return false;
  final deger = _rasyonelDeger(m.group(1)!);
  if (deger == null) return false;
  final kok = r.prompt
      .replaceAll(_onluKuvvet, ' ')
      .replaceAll(_simgeler, ' ')
      .replaceAll('−', '-');
  for (final t in _kokSayiDeseni.allMatches(kok)) {
    if (_rasyonelDeger(t.group(1)!) == deger) return true;
  }
  return false;
}

/// [uret] ikincil bir parametreyi v ile değiştirir; yanıtı kökte yazılı olmayan
/// ilk vaka seçilir (hiçbiri uymazsa ilk vaka kullanılır).
AdvancedItem _kokteOlmayan(
  AdvancedItem Function(int v) uret, [
  int deneme = 8,
]) {
  final ilk = uret(0);
  if (!_yanitKokte(ilk)) return ilk;
  for (var v = 1; v < deneme; v++) {
    final r = uret(v);
    if (!_yanitKokte(r)) return r;
  }
  return ilk;
}

/// Kök metninden hesaplanan, platformdan bağımsız bir özet sayı.
int _ozet(String s) {
  var h = 0;
  for (final u in s.codeUnits) {
    h = (h * 31 + u) & 0x3fffffff;
  }
  return h;
}

/// Çeldiricileri seçer. [adayK] ve [adayB] hatalardan türetilen, yanıttan
/// küçük ve büyük adaylardır; [dolguK] ve [dolguB] aynı yanlardaki komşu
/// değerlerdir. Komşu değer yalnızca aday yetmezse ya da yanıt iki çeldiricinin
/// tam ortasında kalıyorsa (yanıtı ele veren simetrik çift) kullanılır. Kaç
/// çeldiricinin yanıttan küçük olacağı için kökten bir hedef seçilir (0 … 3) ve
/// bu sınırlar içinde tutturulur; seçenek kaldıkça, dört seçenekten üçünü eşit
/// aralıklı yapan değerler alınmaz ([carpimsal] ise eşit oranlı: 0,3 · 3 · 30).
/// [kaydir] doğruysa hataların yanıtın tek yanında toplandığı vakalarda
/// yanıtın hep en büyük ya da en küçük seçenek olması da önlenir (aşağıda).
List<String> _dengeli(
  String kok,
  double yanit,
  Iterable<(double, String)> adayK,
  Iterable<(double, String)> adayB,
  Iterable<(double, String)> dolguK,
  Iterable<(double, String)> dolguB, {
  bool carpimsal = false,
  bool kaydir = false,
}) {
  final gorulen = <String>{};
  List<(double, String)> tekil(Iterable<(double, String)> x) => [
    for (final e in x)
      if (gorulen.add(e.$2)) e,
  ];
  final ak = tekil(adayK), ab = tekil(adayB);
  final dk = tekil(dolguK), db = tekil(dolguB);
  final hedef = (_ozet(kok) ~/ 7) % 4;
  final degerler = <double>[yanit];
  final sonuc = <String>[];
  // m, a ile b'nin tam ortasında mı (çarpımsal durumda oran olarak)?
  bool orta(double a, double b, double m) => carpimsal
      ? (a * b - m * m).abs() <= 1e-9 * m * m
      : (a + b - 2 * m).abs() < 1e-9;
  bool esitAralikli(double x) {
    for (var i = 0; i < degerler.length; i++) {
      for (var j = i + 1; j < degerler.length; j++) {
        final p = degerler[i], q = degerler[j];
        if (orta(p, q, x) || orta(p, x, q) || orta(q, x, p)) return true;
      }
    }
    return false;
  }

  void ekle((double, String) e) {
    degerler.add(e.$1);
    sonuc.add(e.$2);
  }

  void sec(List<(double, String)> liste, int adet) {
    final kalan = [...liste];
    for (var n = 0; n < adet && kalan.isNotEmpty; n++) {
      final i = kalan.indexWhere((e) => !esitAralikli(e.$1));
      ekle(kalan.removeAt(i < 0 ? 0 : i));
    }
  }

  int sinirla(int x, int alt, int ust) => x < alt ? alt : (x > ust ? ust : x);
  if (ak.length + ab.length >= 3) {
    // Yalnızca hatalardan türetilen adaylar kullanılır.
    var s = sinirla(
      hedef,
      3 - ab.length < 0 ? 0 : 3 - ab.length,
      ak.length < 3 ? ak.length : 3,
    );
    sec(ak, s);
    sec(ab, 3 - s);
    if (kaydir) {
      // Hatalar yanıtın bir yanında toplanınca yanıt hep en büyük (ya da en
      // küçük) seçenek olur ve seçenekler sıralanarak bulunur. Yanıt, hedef
      // istemediği hâlde uçta ya da hedefin öbür yarısında kaldıysa yanıta en
      // uzak hatalı çeldirici, karşı yandaki en yakın uygun komşu değerle
      // değiştirilir (en çok bir kez; en az iki çeldirici hatalardan gelir).
      bool sapma() =>
          (s != hedef && (s == 0 || s == 3)) || ((s < 2) != (hedef < 2));
      for (var n = 0; n < 1 && sapma(); n++) {
        final asagi = s < hedef; // yanıttan küçük bir komşu gerekir
        final kalabalik = [
          for (var x = 1; x <= 3; x++)
            if (asagi ? x > s : x <= s) x,
        ];
        if (kalabalik.isEmpty) break;
        final cikan = kalabalik.reduce(
          (p, q) => (degerler[p] - yanit).abs() >= (degerler[q] - yanit).abs()
              ? p
              : q,
        );
        final eskiD = [...degerler], eskiS = [...sonuc];
        degerler.removeAt(cikan);
        sonuc.removeAt(cikan - 1);
        final uygun = (asagi ? dk : db)
            .where((e) => !sonuc.contains(e.$2) && !esitAralikli(e.$1))
            .toList();
        if (uygun.isEmpty) {
          degerler
            ..clear()
            ..addAll(eskiD);
          sonuc
            ..clear()
            ..addAll(eskiS);
          break;
        }
        // Küçük çeldiriciler önde kalır (ortaCift bu sırayı kullanır).
        if (asagi) {
          degerler.insert(s + 1, uygun.first.$1);
          sonuc.insert(s, uygun.first.$2);
          s++;
        } else {
          ekle(uygun.first);
          s--;
        }
      }
    }
    // Yanıt, biri küçük biri büyük iki çeldiricinin tam ortasında kaldıysa
    // çiftin bir üyesi komşu bir değerle değiştirilir: küçük çeldirici hedefin
    // altındaysa büyük üye küçük bir komşuyla, üstündeyse küçük üye büyük bir
    // komşuyla, hedefteyse büyük üye büyük bir komşuyla.
    int? ortaCift() {
      for (var i = 1; i <= s; i++) {
        for (var t = s + 1; t <= 3; t++) {
          if (orta(degerler[i], degerler[t], yanit)) return t;
        }
      }
      return null;
    }

    final t = ortaCift();
    if (t != null) {
      final i = [
        for (var x = 1; x <= s; x++)
          if (orta(degerler[x], degerler[t], yanit)) x,
      ].first;
      final yon = s < hedef ? -1 : (s > hedef ? 1 : 0);
      final yedek = yon < 0 || (yon == 0 && db.isEmpty) ? dk : db;
      final cikan = yon > 0 ? i : t;
      final eskiD = [...degerler], eskiS = [...sonuc];
      degerler.removeAt(cikan);
      sonuc.removeAt(cikan - 1);
      final uygun = yedek
          .where((e) => !sonuc.contains(e.$2) && !esitAralikli(e.$1))
          .toList();
      if (uygun.isEmpty) {
        degerler
          ..clear()
          ..addAll(eskiD);
        sonuc
          ..clear()
          ..addAll(eskiS);
      } else {
        ekle(uygun.first);
      }
    }
  } else {
    ak.forEach(ekle);
    ab.forEach(ekle);
    final bos = 3 - ak.length - ab.length;
    var ek = sinirla(hedef - ak.length, 0, bos);
    if (ek > dk.length) ek = dk.length;
    if (bos - ek > db.length) ek = bos - db.length;
    sec(dk, ek);
    sec(db, bos - ek);
  }
  return sonuc;
}

/// Tam sayı yanıtlı soru; eksi işareti tipografik yazılır. Adaylar yetmezse
/// komşu değerlerle tamamlanır. [enCok] verilirse ondan büyük çeldirici
/// alınmaz (ör. sayma sorusunda evrensel kümenin eleman sayısı); [enAz]
/// verilirse ondan küçük çeldirici alınmaz. [komsuAdim] komşu değerlerin
/// aralığıdır (ör. hep çift olan yanıtlarda 2).
AdvancedItem _tam(
  String kok,
  int yanit,
  Iterable<int> adaylar,
  String aciklama, {
  String birim = '',
  bool pozitif = false,
  int? enAz,
  int? enCok,
  int? komsuAdim,
}) {
  final adim =
      komsuAdim ?? (yanit.abs() >= 200 ? 10 : (yanit.abs() >= 40 ? 5 : 1));
  bool uygun(int x) =>
      x != yanit &&
      (!pozitif || x > 0) &&
      (enAz == null || x >= enAz) &&
      (enCok == null || x <= enCok);
  final aday = [
    for (final x in adaylar)
      if (uygun(x)) x,
  ];
  (double, String) yaz(int x) => (x.toDouble(), birimli(_n(x), birim));
  return secenekli(
    kok,
    birimli(_n(yanit), birim),
    _dengeli(
      kok,
      yanit.toDouble(),
      aday.where((x) => x < yanit).map(yaz),
      aday.where((x) => x > yanit).map(yaz),
      [
        for (var j = 1; j <= 8; j++)
          if (uygun(yanit - j * adim)) yanit - j * adim,
      ].map(yaz),
      [
        for (var j = 1; j <= 8; j++)
          if (uygun(yanit + j * adim)) yanit + j * adim,
      ].map(yaz),
      kaydir: true,
    ),
    aciklama,
  );
}

/// Kesir yanıtlı soru; adaylar (pay, payda) ikilileridir. Paydası sıfır olan
/// adaylar atılır, eksikler komşu değerlerle tamamlanır. [ters] doğruysa
/// yanıtın tersi (kesri ters çevirme hatası) de aday olur; süre gibi
/// büyüklüklerde bu bir hata yolu olmadığından kapatılır. [birdenKucuk]
/// doğruysa yalnız 0 ile 1 arasındaki değerler çeldirici olur (bütünün kaçta
/// kaçı soruları).
AdvancedItem _kes(
  String kok,
  int n,
  int d,
  Iterable<(int, int)> adaylar,
  String aciklama, {
  bool pozitif = false,
  String birim = '',
  bool ters = true,
  bool birdenKucuk = false,
}) {
  final tam = n % d == 0;
  // x − n/d farkının işareti.
  int kars((int, int) x) => ((x.$1 * d - n * x.$2) * (x.$2 * d).sign).sign;
  bool uygun((int, int) x) =>
      x.$2 != 0 &&
      (!pozitif || x.$1 * x.$2 > 0) &&
      (!birdenKucuk || (x.$1 * x.$2 > 0 && x.$1.abs() < x.$2.abs())) &&
      kars(x) != 0;
  final aday = [
    for (final x in [...adaylar, if (ters && n != 0 && !tam) (d, n)])
      if (uygun(x)) x,
  ];
  (double, String) yaz((int, int) x) =>
      (x.$1 / x.$2, birimli(_q(x.$1, x.$2), birim));
  final komsu = [
    for (var j = 1; j <= 6; j++) ...[(n - j * d, d), (n + j * d, d)],
    (n - 1, d),
    (n + 1, d),
    if (birdenKucuk) ...[(n - 2, d), (n + 2, d), (n, d + 1), (n + 1, d + 1)],
  ].where(uygun);
  return secenekli(
    kok,
    birimli(_q(n, d), birim),
    _dengeli(
      kok,
      n / d,
      aday.where((x) => kars(x) < 0).map(yaz),
      aday.where((x) => kars(x) > 0).map(yaz),
      komsu.where((x) => kars(x) < 0).map(yaz),
      komsu.where((x) => kars(x) > 0).map(yaz),
    ),
    aciklama,
  );
}

/// Değer sırası dengeli çeldirici seçimi: anahtardan küçük çeldirici sayısı
/// [hedef] (0 … 3) olur. [hatalar] tipik hata değerleri, [komsular] anahtarın
/// iki yanındaki komşu değerlerdir (yakından uzağa); ikililer (değer, yazım)
/// biçimindedir. Öncelik: o yandaki hatalar, sonra o yandaki komşular; o yanda
/// aday kalmazsa öbür yanın adayları. Anahtarla birlikte eşit aralıklı bir üçlü
/// kuran hata, aynı yanda başka hata kaldıkça alınmaz; böyle bir komşu değer ise
/// ancak başka aday kalmazsa alınır (komşular anahtarla eşit aralıklı bir dizi
/// kurup anahtarı dizinin ucunda ele vermesin). Anahtarı iki çeldiricinin tam
/// ortasında bırakan aday (yanıtı ele veren simetrik çift) en son alınır.
/// Kökte yazılı bir sayıya eşit aday ([kokte]; anahtar kökte yazılı değilken
/// öğrenci bu seçenekleri eleyebilir) ve tam sayı seçeneklerde anahtarı tek ya
/// da çift olan tek seçenek bırakacak aday da eşit aralık kuran aday gibi sona
/// bırakılır.
/// Yazımı anahtarla ya da birbiriyle aynı olan (`ayniSecenek`) adaylar atlanır.
List<String> _dengeliSec(
  double yanit,
  String yanitYazim,
  List<(double, String)> hatalar,
  List<(double, String)> komsular,
  int hedef, {
  Set<(int, int)> kokte = const {},
}) {
  final kota = [hedef, 3 - hedef];
  final secilen = <(double, String)>[];
  bool yeni((double, String) e) =>
      !ayniSecenek(e.$2, yanitYazim) &&
      !secilen.any((s) => ayniSecenek(s.$2, e.$2));
  bool esit(double p, double q) =>
      (p - q).abs() <= 1e-9 * (1 + p.abs() + q.abs());
  // 2: anahtar, x ile bir çeldiricinin tam ortasında; 1: x, anahtar ve bir
  // çeldiriciyle anahtarın uçta kaldığı eşit aralıklı bir üçlü kurar ya da
  // kökte yazılıdır; 0: hiçbiri. Yalnız çeldiricilerden oluşan eşit aralıklı
  // üçlü anahtarı göstermediğinden sayılmaz.
  int duzey((double, String) e) {
    final x = e.$1;
    if (secilen.any((s) => esit(x + s.$1, 2 * yanit))) return 2;
    final deger = _rasyonelDeger(e.$2.split(' ').first);
    if (deger != null && kokte.contains(deger)) return 1;
    // Son çeldirici, tam sayı seçeneklerde anahtarı tek ya da çift olan tek
    // seçenek bırakmasın.
    bool tam(double v) => v == v.roundToDouble();
    bool cift(double v) => v.round().isEven;
    if (secilen.length == 2 &&
        tam(yanit) &&
        tam(x) &&
        secilen.every((s) => tam(s.$1) && cift(s.$1) != cift(yanit)) &&
        cift(x) != cift(yanit)) {
      return 1;
    }
    return secilen.any(
          (s) => esit(yanit + s.$1, 2 * x) || esit(yanit + x, 2 * s.$1),
        )
        ? 1
        : 0;
  }

  void tur(List<(double, String)> liste, int enCok, bool serbest) {
    for (final e in liste) {
      if (secilen.length == 3) return;
      if (!yeni(e) || duzey(e) > enCok) continue;
      final yan = e.$1 < yanit ? 0 : 1;
      if (!serbest) {
        if (kota[yan] == 0) continue;
        kota[yan]--;
      }
      secilen.add(e);
    }
  }

  // Eşit aralıklı üçlü kuran komşu değer, hedef sıradan sapmaktan daha çok
  // ipucu verdiğinden önce öbür yanın adaylarına bakılır.
  for (final serbest in const [false, true]) {
    tur(hatalar, 0, serbest);
    tur(hatalar, 1, serbest);
    tur(komsular, 0, serbest);
  }
  for (final serbest in const [false, true]) {
    tur(komsular, 1, serbest);
  }
  for (final serbest in const [false, true]) {
    tur(hatalar, 2, serbest);
    tur(komsular, 2, serbest);
  }
  if (secilen.length != 3) {
    throw StateError('Eksik çeldirici: $yanitYazim → $secilen');
  }
  return [for (final e in secilen) e.$2];
}

/// Kökte yazılı sayıların (üsler ve alt simgeler hariç) mutlak değerleri, sade
/// kesir olarak ([_yanitKokte] ile aynı okuma).
Set<(int, int)> _kokDegerleri(String kok) {
  final metin = kok
      .replaceAll(_onluKuvvet, ' ')
      .replaceAll(_simgeler, ' ')
      .replaceAll('−', '-');
  return {
    for (final t in _kokSayiDeseni.allMatches(metin))
      ?_rasyonelDeger(t.group(1)!),
  };
}

/// Kökün karmasından hedef değer sırası (0 … 3): vakadan vakaya dengeli değişir.
int _hedef(String kok, [int tuz = 0]) => hedefSira(_ozet(kok), 7 + tuz);

/// [_tam] gibi; ancak anahtardan küçük çeldirici sayısı kökten seçilen hedef
/// sıraya eşit olur ([_dengeliSec]). Önce [adaylar] (tipik hatalar) denenir;
/// bir yanda yetmezse o yandaki komşu değerler ([komsuAdim] aralıkla) alınır.
AdvancedItem _tamD(
  String kok,
  int yanit,
  Iterable<int> adaylar,
  String aciklama, {
  String birim = '',
  bool pozitif = false,
  int? enAz,
  int? enCok,
  int? komsuAdim,
}) {
  final adim =
      komsuAdim ?? (yanit.abs() >= 200 ? 10 : (yanit.abs() >= 40 ? 5 : 1));
  bool uygun(int x) =>
      x != yanit &&
      (!pozitif || x > 0) &&
      (enAz == null || x >= enAz) &&
      (enCok == null || x <= enCok);
  (double, String) yaz(int x) => (x.toDouble(), birimli(_n(x), birim));
  final yazim = birimli(_n(yanit), birim);
  return AdvancedItem(
    kok,
    yazim,
    _dengeliSec(
      yanit.toDouble(),
      yazim,
      [
        for (final x in adaylar)
          if (uygun(x)) yaz(x),
      ],
      [
        for (var j = 1; j <= 8; j++)
          for (final x in [yanit - j * adim, yanit + j * adim])
            if (uygun(x)) yaz(x),
      ],
      _hedef(kok),
      kokte: _kokDegerleri(kok),
    ),
    aciklama,
  );
}

/// Komşu değer aralığı: [birim] sayısının, [yanit] değerinin yaklaşık %5'i
/// kadar olan katı. Problemdeki miktarlar [birim] katı olduğundan komşu
/// değerler de aynı “parça” yapısını korur. [birim] yanıtın %10'undan büyükse
/// (komşular yanıttan çok uzaklaşmasın diye) yanıtın %5'ini aşmayan 1, 2 ya da
/// 5 ile başlayan en büyük yuvarlak aralık alınır.
int _katAdim(int yanit, int birim) {
  final k = (yanit / (20 * birim)).round();
  if (k >= 1) return birim * k;
  if (10 * birim <= yanit) return birim;
  var adim = 1;
  for (var u = 1; u * 20 <= yanit; u *= 10) {
    for (final c in const [1, 2, 5]) {
      if (c * u * 20 <= yanit) adim = c * u;
    }
  }
  return adim;
}

/// [_kes] gibi; değer sırası [_tamD] gibi dengelenir. Komşu değerler
/// yanıtın paydasıyla yazılan yakın kesirlerdir.
AdvancedItem _kesD(
  String kok,
  int n,
  int d,
  Iterable<(int, int)> adaylar,
  String aciklama, {
  bool pozitif = false,
  String birim = '',
  bool ters = true,
  bool birdenKucuk = false,
}) {
  final tam = n % d == 0;
  bool uygun((int, int) x) =>
      x.$2 != 0 &&
      (!pozitif || x.$1 * x.$2 > 0) &&
      (!birdenKucuk || (x.$1 * x.$2 > 0 && x.$1.abs() < x.$2.abs())) &&
      x.$1 * d != n * x.$2;
  (double, String) yaz((int, int) x) =>
      (x.$1 / x.$2, birimli(_q(x.$1, x.$2), birim));
  final yazim = birimli(_q(n, d), birim);
  return AdvancedItem(
    kok,
    yazim,
    _dengeliSec(
      n / d,
      yazim,
      [
        for (final x in [...adaylar, if (ters && n != 0 && !tam) (d, n)])
          if (uygun(x)) yaz(x),
      ],
      [
        for (final x in [
          for (var j = 1; j <= 6; j++) ...[(n - j * d, d), (n + j * d, d)],
          (n - 1, d),
          (n + 1, d),
          if (birdenKucuk) ...[
            (n - 2, d),
            (n + 2, d),
            (n - 3, d),
            (n + 3, d),
            (n, d + 1),
            (n + 1, d + 1),
          ],
        ])
          if (uygun(x)) yaz(x),
      ],
      _hedef(kok),
      kokte: _kokDegerleri(kok),
    ),
    aciklama,
  );
}

// ---------------------------------------------------------------------------
// 1. Asal çarpanlara ayırma
// ---------------------------------------------------------------------------

/// Asal çarpanlar: (asal, üs) ikilileri, küçükten büyüğe.
List<(int, int)> _asalCarpan(int n) {
  final r = <(int, int)>[];
  var m = n;
  for (var p = 2; p * p <= m; p++) {
    var e = 0;
    while (m % p == 0) {
      m ~/= p;
      e++;
    }
    if (e > 0) r.add((p, e));
  }
  if (m > 1) r.add((m, 1));
  return r;
}

/// `2³ · 3² · 5` biçimi.
String _carpanYaz(List<(int, int)> f) =>
    [for (final x in f) x.$2 == 1 ? '${x.$1}' : '${x.$1}${_ust(x.$2)}']
        .join(' · ');

/// Bölen sayısı çarpımının yazılışı: `(3 + 1) · (2 + 1) · (1 + 1)`.
String _bolenYaz(List<(int, int)> f) =>
    [for (final x in f) '(${x.$2} + 1)'].join(' · ');

bool _asalUygun(int n, int tur) {
  final f = _asalCarpan(n);
  if (f.length < 2 || f.last.$1 > 19) return false;
  final us = [for (final x in f) x.$2];
  if (_topla(us) < 3) return false;
  return switch (tur) {
    // Asal bölenlerin toplamı: üsleri hesaba katan yanlış toplam farklı olsun.
    2 => us.any((e) => e >= 2),
    // Tam kare: hem tek hem çift üs bulunsun; bütün asalları çarpan yol ve
    // tek üslüleri unutan yol doğru yanıtı vermesin.
    3 => us.any((e) => e.isEven) && us.any((e) => e.isOdd),
    // Tam küp: en az bir üs 3k + 1 biçiminde olsun; her asalı bir kez çarpan
    // yol doğru yanıtı vermesin. Büyük asalların karesi k değerini milyonlara
    // çıkarmasın diye k en çok 2000 tutulur.
    4 => us.any((e) => e % 3 == 1) && _kupTamlayan(f) <= 2000,
    _ => true,
  };
}

List<int> _asalListe(int tur, int adet) {
  final r = <int>[];
  for (var n = 24; r.length < adet; n++) {
    if (_asalUygun(n, tur)) r.add(n);
  }
  return r;
}

final _asalSayilar = [
  _asalListe(0, 1000),
  _asalListe(2, 500),
  _asalListe(3, 500),
  _asalListe(4, 500),
];

/// Kuvvetleri çarpılacak bileşik taban çiftleri.
const _tabanCiftleri = [
  (4, 6),
  (6, 9),
  (6, 10),
  (6, 15),
  (8, 12),
  (9, 12),
  (10, 12),
  (10, 15),
  (12, 15),
  (12, 18),
  (14, 21),
  (15, 20),
  (18, 24),
  (20, 30),
  (6, 14),
  (10, 14),
  (12, 20),
  (15, 21),
  (18, 30),
  (21, 35),
  (8, 18),
  (9, 15),
  (4, 10),
  (14, 35),
  (22, 33),
];

/// Tam kare sorusu için taban çiftleri: üslerin bir kısmı tek, bir kısmı çift
/// çıkabilir ve tabanları asal sanan yol çoğu üs için yanlış sonuç verir.
const _kareCiftleri = [
  (8, 12),
  (9, 12),
  (12, 15),
  (12, 18),
  (15, 20),
  (18, 24),
  (20, 30),
  (12, 20),
  (18, 30),
  (8, 18),
  (12, 25),
  (18, 20),
  (20, 27),
  (24, 45),
  (9, 20),
  (8, 45),
  (12, 35),
  (28, 15),
  (18, 35),
  (27, 4),
  (4, 45),
  (8, 9),
  (15, 28),
  (12, 49),
  (18, 25),
];

/// (s, t) üs ikilileri; toplam üs küçükten büyüğe sıralıdır.
final _usCiftleri = [
  for (var top = 3; top <= 18; top++)
    for (var s = 2; s <= 9; s++)
      if (top - s >= 1 && top - s <= 9) (s, top - s),
];

/// m^s · n^t çarpımının asal çarpanları.
List<(int, int)> _kuvvetCarpani(int m, int s, int n, int t) {
  final us = <int, int>{};
  for (final (p, e) in _asalCarpan(m)) {
    us[p] = (us[p] ?? 0) + e * s;
  }
  for (final (p, e) in _asalCarpan(n)) {
    us[p] = (us[p] ?? 0) + e * t;
  }
  final asallar = us.keys.toList()..sort();
  return [for (final p in asallar) (p, us[p]!)];
}

int _kareTamlayan(List<(int, int)> f) => _carp([
  for (final x in f)
    if (x.$2.isOdd) x.$1,
]);

int _kupTamlayan(List<(int, int)> f) =>
    _carp([for (final x in f) _kuvvet(x.$1, (3 - x.$2 % 3) % 3)]);

int _tamKok(int x, int derece) {
  var r = 1;
  while (_kuvvet(r + 1, derece) <= x) {
    r++;
  }
  return r;
}

/// Kuvvet yazımı; üs 1 ise yalnız taban yazılır.
String _kuvvetYaz(int taban, int us) =>
    us == 1 ? '$taban' : '$taban${_ust(us)}';

/// Tam kare açıklaması: tek üslü çarpanlar birer kez eklenir.
String _kareAciklama(List<(int, int)> f, int k) {
  final tekler = [
    for (final x in f)
      if (x.$2.isOdd) '${x.$1}',
  ];
  return tekler.length == 1
      ? 'Tam karede her asal çarpanın üssü çifttir; üssü tek olan ${tekler.first} '
            'çarpanı bir kez daha eklenir ve en küçük k değeri $k bulunur.'
      : 'Tam karede her asal çarpanın üssü çifttir; üssü tek olan '
            '${_liste(tekler)} çarpanları birer kez daha eklenir ve en küçük k '
            'değeri ${tekler.join(' · ')} = $k bulunur.';
}

/// Tam küp açıklaması: üsler üçün katına tamamlanır.
String _kupAciklama(List<(int, int)> f, int k) {
  final eksik = [
    for (final x in f)
      if (x.$2 % 3 != 0) _kuvvetYaz(x.$1, 3 - x.$2 % 3),
  ];
  final carpim = eksik.join(' · ');
  return 'Tam küpte her asal çarpanın üssü üçün katıdır; üsleri üçün katına '
      'tamamlamak için k = ${carpim == '$k' ? '$k' : '$carpim = $k'} alınır.';
}

String _liste(List<String> x) => x.length == 1
    ? x.first
    : '${x.sublist(0, x.length - 1).join(', ')} ve ${x.last}';

AdvancedItem _asalCarpanSoru(int a, int b, int c) {
  final j = a + 25 * b;
  if (c < 5) {
    final n = switch (c) {
      0 => _asalSayilar[0][2 * j],
      1 => _asalSayilar[0][2 * j + 1],
      2 => _asalSayilar[1][j],
      3 => _asalSayilar[2][j],
      _ => _asalSayilar[3][j],
    };
    final f = _asalCarpan(n);
    final yaz = '$n = ${_carpanYaz(f)}';
    final bolen = _carp([for (final x in f) x.$2 + 1]);
    final usCarpim = _carp([for (final x in f) x.$2]);
    final usTop = _topla([for (final x in f) x.$2 + 1]);
    final asallar = [for (final x in f) x.$1];
    final altKume = _kuvvet(2, _topla([for (final x in f) x.$2]));
    switch (c) {
      case 0:
        return _tamD(
          '$n sayısının pozitif bölenlerinin sayısı kaçtır?',
          bolen,
          [
            usCarpim,
            usTop,
            2 * bolen,
            bolen - f.length,
            // Her asal çarpanı ayrı bir çarpan sayıp alt küme sayısını almak.
            if (altKume <= 3 * bolen) altKume,
          ],
          '$yaz olduğundan pozitif bölen sayısı ${_bolenYaz(f)} = $bolen '
              'olur.',
          pozitif: true,
        );
      case 1:
        return _tamD(
          '$n sayısının tam sayı bölenlerinin sayısı kaçtır?',
          2 * bolen,
          [
            bolen,
            2 * usCarpim,
            2 * usTop,
            bolen + 1,
            if (altKume <= 3 * bolen) 2 * altKume,
          ],
          '$yaz olduğundan pozitif bölen sayısı ${_bolenYaz(f)} = $bolen '
              'olur. Her pozitif bölenin negatifi de bir bölen olduğundan tam '
              'sayı bölen sayısı 2 · $bolen = ${2 * bolen} bulunur.',
          pozitif: true,
          komsuAdim: 2, // tam sayı bölen sayısı hep çifttir
        );
      case 2:
        final top = _topla(asallar);
        return _tamD(
          '$n sayısının asal bölenlerinin toplamı kaçtır?',
          top,
          [
            _topla([for (final x in f) x.$1 * x.$2]),
            top + 1,
            _carp(asallar),
            f.length,
            // Asal bölenlerden birini (en büyüğünü ya da en küçüğünü) unutmak.
            top - asallar.last,
            top - asallar.first,
          ],
          '$yaz olduğundan asal bölenler ${_liste([for (final p in asallar) '$p'])} '
              'sayılarıdır. Bu asal sayıların toplamı $top olur.',
          pozitif: true,
        );
      case 3:
        final k = _kareTamlayan(f);
        final tekUslu = [
          for (final x in f)
            if (x.$2.isOdd) x.$1,
        ];
        return _tamD(
          'k bir pozitif tam sayı olmak üzere $n · k çarpımı bir tam kare '
              'sayıdır. Buna göre k sayısının alabileceği en küçük değer kaçtır?',
          k,
          [
            _carp(asallar),
            _carp([
              for (final x in f)
                if (x.$2.isEven) x.$1,
            ]),
            _tamKok(n * k, 2),
            _kupTamlayan(f),
            // Üssü tek olan çarpanlardan yalnız birini tamamlamak.
            if (tekUslu.length > 1) ...[k ~/ tekUslu.last, k ~/ tekUslu.first],
            // En küçük asal çarpanla çarpmanın yeteceğini sanmak.
            asallar.first,
          ].where((x) => x > 1 && x <= 10 * k),
          '$yaz olur. ${_kareAciklama(f, k)} Gerçekten $n · $k = ${n * k} = '
              '${_tamKok(n * k, 2)}² olur.',
          pozitif: true,
        );
      default:
        final k = _kupTamlayan(f);
        return _tamD(
          'k bir pozitif tam sayı olmak üzere $n · k çarpımı bir tam küp '
              'sayıdır. Buna göre k sayısının alabileceği en küçük değer kaçtır?',
          k,
          [
            _carp([
              for (final x in f)
                if (x.$2 % 3 != 0) x.$1,
            ]),
            _carp([for (final x in f) _kuvvet(x.$1, x.$2 % 3)]),
            _tamKok(n * k, 3),
            _kareTamlayan(f),
            // Üssü zaten üçün katı olan çarpanı da bir sonraki kata tamamlamak.
            _carp([for (final x in f) _kuvvet(x.$1, 3 - x.$2 % 3)]),
          ].where((x) => x > 1 && x <= 10 * k),
          '$yaz olur. ${_kupAciklama(f, k)} Gerçekten $n · $k = ${n * k} = '
              '${_tamKok(n * k, 3)}³ olur.',
          pozitif: true,
        );
    }
  }
  // c ≥ 5: bileşik tabanlı kuvvetlerin çarpımı.
  // Tam küp sorusunda (12, 18) çifti yerine (12, 25) kullanılır: 12^s · 18^t için
  // k değeri hep tabanlardan birine (12 ya da 18) eşit çıkar.
  final (m, n) = c == 7
      ? _kareCiftleri[a]
      : (c == 8 && a == 9 ? (12, 25) : _tabanCiftleri[a]);
  bool kosul((int, int) st) {
    final f = _kuvvetCarpani(m, st.$1, n, st.$2);
    final us = [for (final x in f) x.$2];
    final bolen = _carp([for (final e in us) e + 1]);
    final saf = (st.$1 + 1) * (st.$2 + 1);
    // Yanıtın kökteki tabanlardan birine eşit olduğu üsler atlanır.
    final yanit = switch (c) {
      5 => bolen,
      6 => 2 * bolen,
      7 => _kareTamlayan(f),
      8 => _kupTamlayan(f),
      _ => bolen - f.length,
    };
    if (yanit == m || yanit == n) return false;
    // Tabanları asal sanan yolun da doğru yanıtı verdiği üsler atlanır.
    return switch (c) {
      5 || 6 || 9 => saf != bolen,
      7 =>
        us.any((e) => e.isOdd) &&
            us.any((e) => e.isEven) &&
            (st.$1.isOdd ? m : 1) * (st.$2.isOdd ? n : 1) != _kareTamlayan(f),
      _ =>
        us.any((e) => e % 3 == 1) &&
            _kuvvet(m, (3 - st.$1 % 3) % 3) * _kuvvet(n, (3 - st.$2 % 3) % 3) !=
                _kupTamlayan(f),
    };
  }

  final (s, t) = _uygun(_usCiftleri, b, kosul);
  final f = _kuvvetCarpani(m, s, n, t);
  final ifade = '${_kuvvetYaz(m, s)} · ${_kuvvetYaz(n, t)}';
  final ayrim = _liste([
    for (final x in [m, n]) '$x = ${_carpanYaz(_asalCarpan(x))}',
  ]);
  final yaz = '$ayrim olduğundan A = ${_carpanYaz(f)} olur.';
  final bolen = _carp([for (final x in f) x.$2 + 1]);
  final saf = (s + 1) * (t + 1);
  // Ortak asal çarpanı birleştirmeden her tabanın çarpanlarını ayrı sayan yol:
  // 4² · 6 = 2⁴ · 2 · 3 için (4 + 1) · (1 + 1) · (1 + 1). Tabanlar ortak bir
  // asal içerdiğinden bu değer doğru yanıttan hep büyüktür.
  final ayrik = _carp([
    for (final x in _asalCarpan(m)) x.$2 * s + 1,
    for (final x in _asalCarpan(n)) x.$2 * t + 1,
  ]);
  final asallar = [for (final x in f) x.$1];
  final altKume = _kuvvet(2, _topla([for (final x in f) x.$2]));
  final tekUslu = [
    for (final x in f)
      if (x.$2.isOdd) x.$1,
  ];
  switch (c) {
    case 5:
      return _tamD(
        'A = $ifade olduğuna göre A sayısının pozitif bölenlerinin sayısı '
            'kaçtır?',
        bolen,
        [
          saf,
          _carp([for (final x in f) x.$2]),
          2 * bolen,
          _topla([for (final x in f) x.$2 + 1]),
          ayrik,
          // Her asal çarpanı ayrı bir çarpan sayıp alt küme sayısını almak.
          if (altKume <= 3 * bolen) altKume,
        ],
        '$yaz Pozitif bölen sayısı ${_bolenYaz(f)} = $bolen bulunur.',
        pozitif: true,
      );
    case 6:
      return _tamD(
        'A = $ifade olduğuna göre A sayısının tam sayı bölenlerinin sayısı '
            'kaçtır?',
        2 * bolen,
        [
          bolen,
          2 * saf,
          saf,
          2 * _carp([for (final x in f) x.$2]),
          2 * ayrik,
          if (altKume <= 3 * bolen) 2 * altKume,
        ],
        '$yaz Pozitif bölen sayısı ${_bolenYaz(f)} = $bolen, tam sayı bölen '
            'sayısı 2 · $bolen = ${2 * bolen} bulunur.',
        pozitif: true,
        komsuAdim: 2, // tam sayı bölen sayısı hep çifttir
      );
    case 7:
      final k = _kareTamlayan(f);
      return _tamD(
        'k bir pozitif tam sayı olmak üzere A = $ifade için A · k çarpımı bir '
            'tam kare sayıdır. Buna göre k sayısının alabileceği en küçük değer '
            'kaçtır?',
        k,
        [
          (s.isOdd ? m : 1) * (t.isOdd ? n : 1),
          _carp(asallar),
          _carp([
            for (final x in f)
              if (x.$2.isEven) x.$1,
          ]),
          _kupTamlayan(f),
          // Üssü tek olan çarpanlardan yalnız birini tamamlamak.
          if (tekUslu.length > 1) ...[k ~/ tekUslu.last, k ~/ tekUslu.first],
        ].where((x) => x > 1 && x <= 10 * k),
        '$yaz ${_kareAciklama(f, k)}',
        pozitif: true,
      );
    case 8:
      final k = _kupTamlayan(f);
      return _tamD(
        'k bir pozitif tam sayı olmak üzere A = $ifade için A · k çarpımı bir '
            'tam küp sayıdır. Buna göre k sayısının alabileceği en küçük değer '
            'kaçtır?',
        k,
        [
          _kuvvet(m, (3 - s % 3) % 3) * _kuvvet(n, (3 - t % 3) % 3),
          _carp([
            for (final x in f)
              if (x.$2 % 3 != 0) x.$1,
          ]),
          _carp([for (final x in f) _kuvvet(x.$1, x.$2 % 3)]),
          _kareTamlayan(f),
          // Üssü zaten üçün katı olan çarpanı da bir sonraki kata tamamlamak.
          if (_carp([for (final x in f) _kuvvet(x.$1, 3 - x.$2 % 3)]) <= 10 * k)
            _carp([for (final x in f) _kuvvet(x.$1, 3 - x.$2 % 3)]),
        ].where((x) => x > 1 && x <= 10 * k),
        '$yaz ${_kupAciklama(f, k)}',
        pozitif: true,
      );
    default:
      return _tamD(
        'A = $ifade olduğuna göre A sayısının asal olmayan pozitif '
            'bölenlerinin sayısı kaçtır?',
        bolen - f.length,
        [
          bolen,
          bolen - f.length - 1,
          saf - 2,
          bolen - 1,
          ayrik - f.length,
          // Üslerin birer fazlasını çarpmak yerine toplamak.
          _topla([for (final x in f) x.$2 + 1]) - f.length,
        ],
        '$yaz Pozitif bölen sayısı ${_bolenYaz(f)} = $bolen olur. Bunlardan '
            '${f.length} tanesi (${_liste([for (final p in asallar) '$p'])}) '
            'asal olduğundan asal olmayan bölen sayısı $bolen − ${f.length} = '
            '${bolen - f.length} bulunur.',
        pozitif: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 2. Faktöriyel
// ---------------------------------------------------------------------------

/// n! içindeki p asalının kuvveti (Legendre): ⌊n/p⌋ + ⌊n/p²⌋ + …
int _legendre(int n, int p) {
  var t = 0;
  for (var q = p; q <= n; q *= p) {
    t += n ~/ q;
  }
  return t;
}

/// Legendre toplamının terimleri: [⌊n/p⌋, ⌊n/p²⌋, …] (sıfır olmayanlar).
List<int> _legendreTerim(int n, int p) => [
  for (var q = p; q <= n; q *= p) n ~/ q,
];

String _legendreYaz(int n, int p) {
  final terim = _legendreTerim(n, p);
  final kesirler = [
    for (var k = 1; k <= terim.length; k++) '⌊$n/${_kuvvet(p, k)}⌋',
  ];
  if (terim.length == 1) return '${kesirler.first} = ${terim.first}';
  return '${kesirler.join(' + ')} = ${terim.join(' + ')} = ${_topla(terim)}';
}

/// Tek parametreli sadeleştirme kalıpları: (ifade, değer, açıklama, çeldirici).
/// Kalıplar birbirinin kaydırılmışı değildir; n değiştikçe aynı ifade iki
/// kalıptan üretilmez.
(String, int, String, List<int>) _faktoriyelKalip(int t, int n) {
  String f(int k) => '$k!';
  final ust = n * (n + 1); // (n + 1)! / (n − 1)!
  switch (t) {
    case 0:
      return (
        '${f(n + 1)} / ${f(n - 1)}',
        ust,
        '${f(n + 1)} = ${n + 1} · $n · ${f(n - 1)} olduğundan bölüm ${n + 1} · $n '
            '= $ust olur.',
        [
          n + 1,
          2,
          n * (n - 1),
          (n + 1) * (n - 1),
          // (n − 1) çarpanını da yazmak (büyük n için aşırı büyük olur).
          if (n <= 11) (n + 1) * n * (n - 1),
        ],
      );
    case 1:
      return (
        '(${f(n)} + ${f(n + 1)}) / ${f(n)}',
        n + 2,
        '${f(n + 1)} = ${n + 1} · ${f(n)} olduğundan pay ${f(n)} · (1 + ${n + 1}) = '
            '${f(n)} · ${n + 2} olur; sonuç ${n + 2} bulunur.',
        [n + 1, n, 2 * n + 1],
      );
    case 2:
      return (
        '(${f(n)} + ${f(n + 1)}) / ${f(n - 1)}',
        n * (n + 2),
        '${f(n)} / ${f(n - 1)} = $n ve ${f(n + 1)} / ${f(n - 1)} = ${n + 1} · $n = '
            '$ust olduğundan sonuç $n + $ust = ${n * (n + 2)} olur.',
        [ust, 2 * n + 1, (n + 1) * (n + 2)],
      );
    case 3:
      return (
        '(${f(n + 1)} − ${f(n)}) / ${f(n - 1)}',
        n * n,
        '${f(n + 1)} − ${f(n)} = ${f(n)} · (${n + 1} − 1) = ${f(n)} · $n olur. '
            '${f(n)} / ${f(n - 1)} = $n olduğundan sonuç $n · $n = ${n * n} bulunur.',
        [ust, n * (n - 1), n * n - 1],
      );
    case 4:
      return (
        '${f(n + 2)} / (2 · ${f(n)})',
        (n + 1) * (n + 2) ~/ 2,
        '${f(n + 2)} = ${n + 2} · ${n + 1} · ${f(n)} olduğundan sonuç ${n + 2} · '
            '${n + 1} / 2 = ${(n + 1) * (n + 2) ~/ 2} olur.',
        [(n + 1) * (n + 2), (n + 2) * (n + 3) ~/ 2, ust ~/ 2],
      );
    case 5:
      final k = (n + 2) * (n + 2);
      return (
        '(${f(n + 2)} + ${f(n + 1)} + ${f(n)}) / ${f(n)}',
        k,
        'Her terim ${f(n)} ile bölünür: ${f(n + 2)} / ${f(n)} = ${n + 2} · ${n + 1} '
            '= ${(n + 2) * (n + 1)}, ${f(n + 1)} / ${f(n)} = ${n + 1} ve ${f(n)} / '
            '${f(n)} = 1. Toplam ${(n + 2) * (n + 1)} + ${n + 1} + 1 = $k olur.',
        [k - 1, (n + 1) * (n + 2), (n + 2) * (n + 3)],
      );
    case 6:
      final k = n * (n + 2);
      return (
        '(${f(n + 2)} − ${f(n + 1)} − ${f(n)}) / ${f(n)}',
        k,
        'Her terim ${f(n)} ile bölünür: ${f(n + 2)} / ${f(n)} = ${n + 2} · ${n + 1} '
            '= ${(n + 2) * (n + 1)}, ${f(n + 1)} / ${f(n)} = ${n + 1} ve ${f(n)} / '
            '${f(n)} = 1. Sonuç ${(n + 2) * (n + 1)} − ${n + 1} − 1 = $k olur.',
        [k + 1, (n + 1) * (n + 2), ust],
      );
    case 7:
      return (
        '(2 · ${f(n)} + ${f(n + 1)}) / ${f(n - 1)}',
        n * (n + 3),
        '2 · ${f(n)} / ${f(n - 1)} = 2 · $n = ${2 * n} ve ${f(n + 1)} / ${f(n - 1)} = '
            '${n + 1} · $n = $ust olduğundan sonuç ${2 * n} + $ust = ${n * (n + 3)} '
            'olur.',
        [ust + 2, n * (n + 2), (n + 1) * (n + 3)],
      );
    case 8:
      return (
        '(${f(n + 1)} − 2 · ${f(n)}) / ${f(n - 1)}',
        n * (n - 1),
        '${f(n + 1)} / ${f(n - 1)} = ${n + 1} · $n = $ust ve 2 · ${f(n)} / '
            '${f(n - 1)} = 2 · $n = ${2 * n} olduğundan sonuç $ust − ${2 * n} = '
            '${n * (n - 1)} olur.',
        [ust - 2, n * n, n * (n - 2)],
      );
    default:
      return (
        '(${f(n + 1)} − ${f(n - 1)}) / ${f(n - 1)}',
        ust - 1,
        '${f(n + 1)} / ${f(n - 1)} = ${n + 1} · $n = $ust ve ${f(n - 1)} / '
            '${f(n - 1)} = 1 olduğundan sonuç $ust − 1 = ${ust - 1} olur.',
        [ust, ust + 1, n * n - 1],
      );
  }
}

/// Sonunda sıfır sayısı tam [k] olan n! için en küçük n; yoksa null.
int? _sifirdanN(int k) {
  for (var n = 5 * (k * 4 ~/ 5); n <= 5 * k + 5; n += 5) {
    if (_legendre(n, 5) == k) return n;
  }
  return null;
}

final _sifirSayilari = [
  for (var k = 6; k < 400; k++)
    if (_sifirdanN(k) != null) k,
];

/// n! sayısını tam bölen B^k için en büyük k.
int _tabanKuvveti(int n, int taban) {
  var k = 1 << 30;
  for (final (p, e) in _asalCarpan(taban)) {
    final v = _legendre(n, p) ~/ e;
    if (v < k) k = v;
  }
  return k;
}

/// Bileşik tabanı asal sanıp Legendre uygulayan yanlış yol.
int _yanlisLegendre(int n, int taban) {
  var t = 0;
  for (var q = taban; q <= n; q *= taban) {
    t += n ~/ q;
  }
  return t;
}

/// Üsleri gözetmeden en küçük asal kuvvetini alan yanlış yol.
int _ussuzKuvvet(int n, int taban) {
  var k = 1 << 30;
  for (final (p, _) in _asalCarpan(taban)) {
    final v = _legendre(n, p);
    if (v < k) k = v;
  }
  return k;
}

/// Kısıtların büyüğünü alan yanlış yol.
int _buyukKisit(int n, int taban) {
  var k = 0;
  for (final (p, e) in _asalCarpan(taban)) {
    final v = _legendre(n, p) ~/ e;
    if (v > k) k = v;
  }
  return k;
}

const _asalKuvvetTaban = [4, 8, 9, 16, 27];

/// Tek asalın bağlayıcı olduğu bileşik tabanlar; k değeri asal kuvvetli
/// tabanların (4, 8, 9, 16, 27) verdiği değerlerle aynı hesaba düşmez.
const _bilesikTaban = [50, 96, 98, 162, 250];

AdvancedItem _faktoriyelSoru(int a, int b, int c) {
  switch (c) {
    case 0:
      final t = b % 10, n = 4 + a + 25 * (b ~/ 10);
      final (ifade, deger, aciklama, celdirici) = _faktoriyelKalip(t, n);
      return _tamD(
        '$ifade işleminin sonucu kaçtır?',
        deger,
        celdirici,
        aciklama,
        pozitif: true,
      );
    case 1:
      final m = 4 + a;
      final n = _uygun([for (var x = 3; x <= 60; x++) x], b, (x) {
        if (x == m - 2 || x == m - 1) return false;
        final d = x + 1, pay = m * (m - 1);
        if (pay % d == 0 && {m, x, m - 2, x + 1}.contains(pay ~/ d)) {
          return false;
        }
        return true;
      });
      final pay = m * (m - 1), payda = n + 1;
      return _kesD(
        '($m! · $n!) / (${m - 2}! · ${n + 1}!) işleminin sonucu kaçtır?',
        pay,
        payda,
        [(m, payda), (pay * payda, 1), (pay, n), (m - 1, payda)],
        '$m! / ${m - 2}! = $m · ${m - 1} = $pay ve $n! / ${n + 1}! = 1/${n + 1} '
            'olduğundan sonuç ${_q(pay, payda) == '$pay/$payda' ? '$pay/$payda' : '$pay/$payda = ${_q(pay, payda)}'} '
            'olur.',
        pozitif: true,
      );
    case 2:
      final n = 25 + a + 25 * b;
      final z = _legendre(n, 5);
      final terim = _legendreTerim(n, 5);
      return _tamD(
        '$n! sayısının sonunda kaç tane sıfır vardır?',
        z,
        [
          n ~/ 5,
          if (terim.length > 2) terim[0] + terim[1],
          n ~/ 10,
          _legendre(n, 2),
          // 25'in katlarını iki, 125'in katlarını üç kez daha saymak.
          _topla([for (var k = 0; k < terim.length; k++) (k + 1) * terim[k]]),
        ],
        'Sondaki sıfırları 2 · 5 çarpanları oluşturur; 5 çarpanları daha az '
            'olduğundan 5 çarpanları sayılır: ${_legendreYaz(n, 5)}.',
        pozitif: true,
      );
    case 3:
      // Yanıt kökteki sayılardan birine eşit çıkarsa n, aralığın dışına
      // (125 ileri) kaydırılır; böylece kökler yine birbirinden farklı kalır.
      return _kokteOlmayan((v) {
        final m = 10 + b, n = 30 + 5 * a + b % 5 + 125 * v;
        final zn = _legendre(n, 5), zm = _legendre(m, 5);
        return _tamD(
          '$n! · $m! çarpımının sonunda kaç tane sıfır vardır?',
          zn + zm,
          [n ~/ 5 + m ~/ 5, zn, zn * zm, zn + zm + 1],
          'Çarpımdaki 5 çarpanları sayılır. $n! için ${_legendreYaz(n, 5)}, '
              '$m! için ${_legendreYaz(m, 5)} bulunur. 2 çarpanları daha çok '
              'olduğundan sondaki sıfır sayısı $zn + $zm = ${zn + zm} olur.',
          pozitif: true,
        );
      });
    case 4:
      final m = 10 + b, n = m + 5 + 3 * a;
      final zn = _legendre(n, 5), zm = _legendre(m, 5);
      return _tamD(
        '$n! + $m! toplamının sonunda kaç tane sıfır vardır?',
        zm,
        // Son yanlış: 5 çarpanı yerine 10'un katlarını saymak.
        [zn + zm, zn, zn * zm, m ~/ 10],
        'Toplam $m! · (1 + ${m + 1} · … · $n) biçiminde yazılır. ${m + 1} · … · '
            '$n çarpımı 10 sayısının katı olduğundan parantezin içi 1 ile biten, '
            '2 ve 5 çarpanı içermeyen bir sayıdır. Bu nedenle sondaki sıfır sayısı '
            '$m! sayısınınkine eşittir: ${_legendreYaz(m, 5)}.',
        pozitif: true,
      );
    case 5 || 6:
      final ilk = b < 10;
      final p = c == 5 ? (ilk ? 2 : 3) : (ilk ? 7 : 11);
      final taban = c == 5 ? (ilk ? 10 : 27) : (ilk ? 49 : 121);
      final n = taban + a + 25 * (b % 10);
      final v = _legendre(n, p);
      final terim = _legendreTerim(n, p);
      return _tamD(
        '$n! sayısı $p^k ile tam bölünebildiğine göre k doğal sayısının '
            'alabileceği en büyük değer kaçtır?',
        v,
        [
          n ~/ p,
          v - terim.last,
          if (terim.length > 2) terim[0] + terim[1],
          v + 1,
          // p² katlarını iki, p³ katlarını üç kez daha saymak.
          _topla([for (var k = 0; k < terim.length; k++) (k + 1) * terim[k]]),
        ],
        '$n! içindeki $p çarpanları sayılır: ${_legendreYaz(n, p)}. En büyük k '
            'değeri $v olur.',
        pozitif: true,
      );
    case 7 || 8:
      final taban = (c == 7 ? _asalKuvvetTaban : _bilesikTaban)[b % 5];
      final n = _uygun([for (var x = 10; x <= 400; x++) x], a + 25 * (b ~/ 5), (
        x,
      ) {
        final k = _tabanKuvveti(x, taban);
        if (k < 1 || k == x || k == taban) return false;
        return k != _yanlisLegendre(x, taban) &&
            k != _ussuzKuvvet(x, taban) &&
            (c == 7 || k != _buyukKisit(x, taban));
      });
      final k = _tabanKuvveti(n, taban);
      final f = _asalCarpan(taban);
      final adimlar = [
        for (final (p, e) in f)
          e == 1
              ? '$n! içinde $p çarpanının kuvveti ${_legendreYaz(n, p)}'
              : '$n! içinde $p çarpanının kuvveti ${_legendreYaz(n, p)}; '
                    '$p${_ust(e)} kuvvetinden ⌊${_legendre(n, p)}/$e⌋ = '
                    '${_legendre(n, p) ~/ e} tane bulunur',
      ];
      return _tamD(
        '$n! sayısı $taban^k ile tam bölünebildiğine göre k doğal sayısının '
            'alabileceği en büyük değer kaçtır?',
        k,
        [
          _yanlisLegendre(n, taban),
          _ussuzKuvvet(n, taban),
          if (f.length > 1) _buyukKisit(n, taban),
          if (f.length == 1) _legendre(n, f.first.$1),
          k + 1,
          // Legendre toplamının yalnız ilk terimini alıp üsse bölmek.
          [for (final (p, e) in f) n ~/ p ~/ e].reduce((x, y) => x < y ? x : y),
        ],
        '$taban = ${_carpanYaz(f)} olur. ${adimlar.join('. ')}. '
            '${f.length > 1 ? 'Bu değerlerin küçüğü alınır: ' : ''}k en çok $k '
            'olur.',
        pozitif: true,
      );
    default:
      final j = a + 25 * b;
      final k = _sifirSayilari[j ~/ 2];
      final enAz = j.isEven;
      final nMin = _sifirdanN(k)!;
      final yanit = enAz ? nMin : nMin + 4;
      return _tamD(
        'n! sayısının sonunda tam $k tane sıfır olduğuna göre n doğal sayısının '
            'alabileceği en ${enAz ? 'küçük' : 'büyük'} değer kaçtır?',
        yanit,
        [5 * k, 4 * k, enAz ? nMin + 4 : nMin, enAz ? nMin - 5 : nMin + 5],
        'n! sayısının sonundaki sıfır sayısı ⌊n/5⌋ + ⌊n/25⌋ + ⌊n/125⌋ + … '
            'toplamıdır. ${_legendreYaz(nMin, 5)} ve ${_legendreYaz(nMin - 1, 5)} '
            'olduğundan $k sıfır n = $nMin ile başlar ve n = ${nMin + 4} sayısına '
            'kadar sürer. Aranan değer $yanit olur.',
        pozitif: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 3. Ardışık sayıların toplamı
// ---------------------------------------------------------------------------

/// Aritmetik artışlı toplamın açılımı: `7 + 11 + 15 + … + 95`.
String _artanToplam(int ilk, int artis, int son) =>
    '$ilk + ${ilk + artis} + ${ilk + 2 * artis} + … + $son';

/// Tam bölünüyorsa bölüm, değilse null (yanlış yolların tam sayı olmayan
/// sonuçları çeldirici yapılmaz).
int? _bol(int pay, int payda) =>
    payda != 0 && pay % payda == 0 ? pay ~/ payda : null;

AdvancedItem _ardisikSoru(int a, int b, int c) {
  switch (c) {
    case 0:
      final ilk = 1 + a, adet = 11 + 3 * b, son = ilk + adet - 1;
      final top = (ilk + son) * adet ~/ 2;
      if (ilk == 1) {
        return _tamD(
          '1 + 2 + 3 + … + $son toplamı kaçtır?',
          top,
          [
            son * (son - 1) ~/ 2,
            son * son,
            (son + 1) * (son + 2) ~/ 2,
            // 2 ile bölmeyi unutmak; n · (n + 1) yerine n · n almak.
            son * (son + 1),
            ?_bol(son * son, 2),
          ],
          '1 + 2 + … + n = n · (n + 1) / 2 formülünde n = $son alınır: $son · '
              '${son + 1} / 2 = $top.',
          pozitif: true,
        );
      }
      return _tamD(
        '$ilk + ${ilk + 1} + ${ilk + 2} + … + $son toplamı kaçtır?',
        top,
        [
          ?_bol((ilk + son) * (adet - 1), 2),
          son * (son + 1) ~/ 2,
          son * (son + 1) ~/ 2 - ilk * (ilk + 1) ~/ 2,
          ?_bol((ilk + son) * (adet + 1), 2),
          // Son terimi toplama katmamak.
          top - son,
        ],
        'Terim sayısı $son − $ilk + 1 = $adet olur. Toplam (ilk terim + son '
            'terim) · terim sayısı / 2 = ($ilk + $son) · $adet / 2 = $top bulunur.',
        pozitif: true,
      );
    case 1 || 2:
      final tek = c == 1;
      final ilk = tek ? 2 * a + 1 : 2 * a + 2, adet = 6 + b;
      final son = ilk + 2 * (adet - 1);
      final top = (ilk + son) * adet ~/ 2;
      final bastan = tek ? ilk == 1 : ilk == 2;
      return _tamD(
        'Ardışık ${tek ? 'tek' : 'çift'} sayılardan oluşan '
            '${_artanToplam(ilk, 2, son)} toplamı kaçtır?',
        top,
        [
          (ilk + son) * (adet - 1) ~/ 2,
          if (!bastan) tek ? (son + 1) * (son + 1) ~/ 4 : son * (son + 2) ~/ 4,
          ?_bol((son - ilk + 1) * (ilk + son), 2),
          (ilk + son) * adet,
          // Aradaki bütün tam sayıların toplamının yarısını almak.
          ?_bol((son - ilk + 1) * (ilk + son), 4),
          // İlk ya da son terimi toplama katmamak.
          top - ilk,
          top - son,
        ],
        'Terim sayısı ($son − $ilk) / 2 + 1 = $adet olur. Toplam ($ilk + $son) '
            '· $adet / 2 = $top bulunur.',
        pozitif: true,
      );
    case 3:
      final ilk = 2 + a, artis = 3 + b % 5, adet = 10 + 4 * (b ~/ 5);
      final son = ilk + (adet - 1) * artis;
      final top = (ilk + son) * adet ~/ 2;
      return _tamD(
        'Her terimi bir öncekinden $artis fazla olan '
            '${_artanToplam(ilk, artis, son)} toplamı kaçtır?',
        top,
        [
          ?_bol((ilk + son) * (adet - 1), 2),
          (ilk + son) * adet,
          ?_bol((ilk + son) * (adet + 1), 2),
          ?_bol((ilk + son) * (son - ilk + 1), 2),
          // n · ilk + artış · n(n − 1)/2 formülünde artışla çarpmayı unutmak.
          adet * ilk + adet * (adet - 1) ~/ 2,
          // İlk ya da son terimi toplama katmamak.
          top - ilk,
          top - son,
        ],
        'Terim sayısı ($son − $ilk) / $artis + 1 = $adet olur. Toplam ($ilk + '
            '$son) · $adet / 2 = $top bulunur.',
        pozitif: true,
      );
    case 4:
      // İlk terim artışa eşitse “son terim / artış” yanlış yolu doğru sonucu
      // verir; bu durumda ilk terim aralığın dışına kaydırılır.
      final artis = 3 + b % 5, adet = 12 + 5 * (b ~/ 5);
      final ilk = 2 + a == artis ? 27 + a : 2 + a;
      final son = ilk + (adet - 1) * artis;
      return _tamD(
        'Her terimi bir öncekinden $artis fazla olan $ilk, ${ilk + artis}, '
            '${ilk + 2 * artis}, …, $son sayı dizisinde kaç terim vardır?',
        adet,
        [
          adet - 1,
          adet + 1,
          if (son % artis == 0) son ~/ artis,
          son - ilk + 1,
          son - ilk,
        ],
        'Terim sayısı (son terim − ilk terim) / artış + 1 = ($son − $ilk) / '
            '$artis + 1 = ${adet - 1} + 1 = $adet olur.',
        pozitif: true,
      );
    case 5:
      final ilk = 10 + a, artis = 1 + b % 4, sira = 8 + 2 * (b ~/ 4);
      final son = ilk + (sira - 1) * artis;
      final top = (ilk + son) * sira ~/ 2;
      return _tamD(
        'Bir açık hava tiyatrosunun ilk sırasında $ilk koltuk vardır ve sonraki '
            'her sırada bir önceki sıradan $artis koltuk fazla bulunmaktadır. '
            'Tiyatroda $sira sıra koltuk olduğuna göre tiyatroda toplam kaç koltuk '
            'vardır?',
        top,
        [
          (ilk + son) * sira,
          ?_bol((2 * ilk + sira * artis) * sira, 2),
          son * sira,
          ilk * sira,
          ?_bol((ilk + son) * (sira - 1), 2),
          // Her sıraya ilk sıradan yalnız bir kez artış eklemek.
          sira * (ilk + artis),
        ],
        'Son sırada $ilk + ($sira − 1) · $artis = $son koltuk vardır. Toplam '
            '($ilk + $son) · $sira / 2 = $top koltuk olur.',
        pozitif: true,
      );
    case 6:
      final ilk = 10 + 2 * a, artis = 2 + b % 5, hafta = 8 + 3 * (b ~/ 5);
      final son = ilk + (hafta - 1) * artis;
      final top = (ilk + son) * hafta ~/ 2;
      return _tamD(
        'Bir öğrenci kumbarasına ilk hafta $ilk TL atıyor ve sonraki her hafta '
            'bir önceki haftadan $artis TL fazla para atıyor. Kumbaraya son olarak '
            '$son TL attığına göre kumbarada toplam kaç TL birikmiştir?',
        top,
        [
          ?_bol((ilk + son) * (hafta - 1), 2),
          (ilk + son) * hafta,
          son * hafta,
          ?_bol((ilk + son) * (hafta + 1), 2),
          // Artışları unutmak ya da her haftaya yalnız bir kez eklemek.
          ilk * hafta,
          hafta * (ilk + artis),
        ],
        'Para atılan hafta sayısı ($son − $ilk) / $artis + 1 = $hafta olur. '
            'Toplam ($ilk + $son) · $hafta / 2 = $top TL bulunur.',
        birim: 'TL',
        pozitif: true,
      );
    case 7:
      final ilk = 2 * a + 1, adet = 12 + 2 * b, son = ilk + 2 * (adet - 1);
      return _tamD(
        'Bir sokağın bir yanındaki evlerin kapı numaraları $ilk, ${ilk + 2}, '
            '${ilk + 4}, … biçiminde ardışık tek sayılardır. Bu yandaki son evin '
            'kapı numarası $son olduğuna göre sokağın bu yanında kaç ev vardır?',
        adet,
        [adet - 1, son - ilk + 1, if (ilk > 1) (son + 1) ~/ 2, adet + 1],
        'Ev sayısı (son numara − ilk numara) / 2 + 1 = ($son − $ilk) / 2 + 1 = '
            '$adet olur.',
        pozitif: true,
      );
    case 8:
      final ilk = 2 + a, son = ilk + 9 + 2 * b;
      final top = (son * (son + 1) - (ilk - 1) * ilk) ~/ 2;
      return _tamD(
        'Ardışık doğal sayılardan oluşan $ilk + ${ilk + 1} + ${ilk + 2} + … + n '
            'toplamı $top olduğuna göre n kaçtır?',
        son,
        [son - ilk + 1, son + 1, son - 1, son + ilk],
        '1 + 2 + … + n = n · (n + 1) / 2 olduğundan $ilk + … + n = n · (n + 1) / 2 '
            '− ${(ilk - 1) * ilk ~/ 2} yazılır. n · (n + 1) / 2 = $top + '
            '${(ilk - 1) * ilk ~/ 2} = ${son * (son + 1) ~/ 2}, yani n · (n + 1) = '
            '${son * (son + 1)} = $son · ${son + 1} bulunur; n = $son olur.',
        pozitif: true,
      );
    default:
      // Yanıt (gün sayısı) kökteki bir sayıya eşitse ilk gün sayısı aralığın
      // dışına kaydırılır.
      return _kokteOlmayan((v) {
        final ilk = 5 + a + 25 * v, artis = 2 + b % 4, gun = 6 + b ~/ 4;
        final son = ilk + (gun - 1) * artis;
        final top = (ilk + son) * gun ~/ 2;
        return _tamD(
          'Bir öğrenci deneme sınavına hazırlanırken ilk gün $ilk soru çözüyor ve '
              'sonraki her gün bir önceki günden $artis soru fazla çözüyor. Buna göre '
              'öğrencinin çözdüğü soruların toplamı kaçıncı günün sonunda $top olur?',
          gun,
          [gun - 1, gun + 1],
          '$gun gün sonunda son gün $ilk + ($gun − 1) · $artis = $son soru çözülür '
              've toplam ($ilk + $son) · $gun / 2 = $top olur. Buna göre aranan gün '
              '$gun. gündür.',
          pozitif: true,
        );
      });
  }
}

// ---------------------------------------------------------------------------
// 4. Tek-çift ve işaret özellikleri (öncüllü)
// ---------------------------------------------------------------------------

const _kumeAdi = {
  1: 'Yalnız I',
  2: 'Yalnız II',
  4: 'Yalnız III',
  3: 'I ve II',
  5: 'I ve III',
  6: 'II ve III',
  7: 'I, II ve III',
};

const _romen = ['I', 'II', 'III'];

/// “Hangileri?” sorusu. [maske] doğru öncülleri bit olarak taşır (bit 0 = I).
/// [yanilgi] tipik bir hatanın verdiği alt kümedir (0 ise kullanılmaz).
AdvancedItem _hangileri(
  String kok,
  int maske,
  Iterable<int> yanilgilar,
  String aciklama,
  int i,
) {
  assert(maske >= 1 && maske <= 7);
  final adaylar = [
    ...yanilgilar,
    for (var r = 0; r < 3; r++) maske ^ (1 << ((i + r) % 3)),
    maske ^ 7,
    for (var m = 0; m < 7; m++) (m + i) % 7 + 1,
  ].where((m) => m >= 1 && m <= 7 && m != maske);
  return secenekli(
    kok,
    _kumeAdi[maske]!,
    adaylar.map((m) => _kumeAdi[m]!),
    aciklama,
  );
}

/// Tek-çift koşulları: (metin, açıklama, izin verilen (x, y, z) pariteleri).
/// Parite 1 tek, 0 çift demektir. Üç değişkenli koşullarda z de kullanılır.
const _pariteKosul = <(String, String, List<(int, int, int)>)>[
  ('x tek, y çifttir.', 'x tek, y çifttir.', [(1, 0, 0)]),
  ('x çift, y tektir.', 'x çift, y tektir.', [(0, 1, 0)]),
  (
    'x · y çarpımı tek sayıdır.',
    'x · y tek ise x ve y sayılarının ikisi de tektir.',
    [(1, 1, 0)],
  ),
  (
    'x çift ve x + y toplamı tek sayıdır.',
    'x çift ve x + y tek ise y tektir.',
    [(0, 1, 0)],
  ),
  (
    'x tek ve x + y toplamı çift sayıdır.',
    'x tek ve x + y çift ise y de tektir.',
    [(1, 1, 0)],
  ),
  (
    'x tek ve x · y çarpımı çift sayıdır.',
    'x tek ve x · y çift ise y çifttir.',
    [(1, 0, 0)],
  ),
  (
    'y çift ve x² + y toplamı tek sayıdır.',
    'y çift ve x² + y tek ise x² tek, dolayısıyla x tektir.',
    [(1, 0, 0)],
  ),
  (
    'x + y toplamı tek sayıdır.',
    'x + y tek ise x ile y sayılarından biri tek, diğeri çifttir.',
    [(1, 0, 0), (0, 1, 0)],
  ),
  (
    'x · y çarpımı çift sayıdır.',
    'x · y çift ise x ile y sayılarından en az biri çifttir.',
    [(0, 0, 0), (0, 1, 0), (1, 0, 0)],
  ),
  (
    '3x + 2y toplamı tek ve y tek sayıdır.',
    '2y daima çift olduğundan 3x tek, yani x tektir; y de tektir.',
    [(1, 1, 0)],
  ),
  ('x tek, y çift ve z tektir.', 'x tek, y çift, z tektir.', [(1, 0, 1)]),
  (
    'x + y toplamı tek ve y + z toplamı çift sayıdır.',
    'x + y tek ise x ile y farklı paritede, y + z çift ise y ile z aynı paritededir.',
    [(1, 0, 0), (0, 1, 1)],
  ),
  (
    'x · y · z çarpımı tek sayıdır.',
    'x · y · z tek ise x, y ve z sayılarının üçü de tektir.',
    [(1, 1, 1)],
  ),
  (
    'x · y çift, x + y tek ve y · z tek sayıdır.',
    'y · z tek ise y ve z tektir; x + y tek olduğundan x çifttir.',
    [(0, 1, 1)],
  ),
];

/// İki değişkenli parite ifadeleri.
final _pariteIfade2 = <(String, int Function(int, int, int))>[
  ('x + y', (x, y, z) => x + y),
  ('x · y', (x, y, z) => x * y),
  ('x − y', (x, y, z) => x - y),
  ('x² + y', (x, y, z) => x * x + y),
  ('x + y²', (x, y, z) => x + y * y),
  ('x² + y²', (x, y, z) => x * x + y * y),
  ('2x + y', (x, y, z) => 2 * x + y),
  ('x + 3y', (x, y, z) => x + 3 * y),
  ('x · y + x', (x, y, z) => x * y + x),
  ('x · y + y', (x, y, z) => x * y + y),
  ('(x + 1) · y', (x, y, z) => (x + 1) * y),
  ('x · (y + 1)', (x, y, z) => x * (y + 1)),
  ('x² · y', (x, y, z) => x * x * y),
  ('x³ + y²', (x, y, z) => x * x * x + y * y),
  ('3x + 5y', (x, y, z) => 3 * x + 5 * y),
  ('x · y + 1', (x, y, z) => x * y + 1),
  ('(x + y)²', (x, y, z) => (x + y) * (x + y)),
  ('x² − y²', (x, y, z) => x * x - y * y),
  ('(x + 1) · (y + 1)', (x, y, z) => (x + 1) * (y + 1)),
  ('x + y + 1', (x, y, z) => x + y + 1),
  ('x² + x · y', (x, y, z) => x * x + x * y),
  ('4x + y²', (x, y, z) => 4 * x + y * y),
];

/// Üç değişkenli parite ifadeleri.
final _pariteIfade3 = <(String, int Function(int, int, int))>[
  ('x + y + z', (x, y, z) => x + y + z),
  ('x · y · z', (x, y, z) => x * y * z),
  ('x · y + z', (x, y, z) => x * y + z),
  ('x + y · z', (x, y, z) => x + y * z),
  ('x · z + y', (x, y, z) => x * z + y),
  ('(x + y) · z', (x, y, z) => (x + y) * z),
  ('x² + y² + z', (x, y, z) => x * x + y * y + z),
  ('x · y + y · z', (x, y, z) => x * y + y * z),
  ('(x + z) · y', (x, y, z) => (x + z) * y),
  ('x + z', (x, y, z) => x + z),
  ('x · z', (x, y, z) => x * z),
  ('y + z', (x, y, z) => y + z),
  ('x² + z²', (x, y, z) => x * x + z * z),
  ('x · y + x · z', (x, y, z) => x * y + x * z),
  ('(x + y) · (y + z)', (x, y, z) => (x + y) * (y + z)),
  ('x + 2y + z', (x, y, z) => x + 2 * y + z),
  ('x · z + 1', (x, y, z) => x * z + 1),
];

/// Bir ifadenin koşul altındaki paritesi: 1 daima tek, 0 daima çift, −1 belirsiz.
int _parite(
  (String, int Function(int, int, int)) ifade,
  List<(int, int, int)> izin,
) {
  final degerler = {for (final (x, y, z) in izin) ifade.$2(x, y, z) % 2};
  return degerler.length == 1 ? degerler.first : -1;
}

/// İşaret koşulları: (metin, açıklama, koşul, üç değişkenli mi).
final _isaretKosul =
    <(String, String, bool Function(double, double, double), bool)>[
      (
        'x < 0 < y',
        'x negatif, y pozitiftir.',
        (x, y, z) => x < 0 && y > 0,
        false,
      ),
      (
        'x < y < 0',
        'x ve y negatiftir; x sayısının mutlak değeri daha büyüktür.',
        (x, y, z) => x < y && y < 0,
        false,
      ),
      (
        'y < x < 0',
        'x ve y negatiftir; y sayısının mutlak değeri daha büyüktür.',
        (x, y, z) => y < x && x < 0,
        false,
      ),
      (
        '0 < x < y',
        'x ve y pozitiftir; y daha büyüktür.',
        (x, y, z) => 0 < x && x < y,
        false,
      ),
      (
        'x · y < 0 ve x < y',
        'x · y < 0 ise x ile y zıt işaretlidir; x < y olduğundan x negatif, y pozitiftir.',
        (x, y, z) => x < 0 && y > 0,
        false,
      ),
      (
        'x · y > 0 ve x + y < 0',
        'x · y > 0 ise x ile y aynı işaretlidir; toplamları negatif olduğundan ikisi de negatiftir.',
        (x, y, z) => x < 0 && y < 0,
        false,
      ),
      (
        'x² · y < 0 ve x · y > 0',
        'x² pozitif olduğundan y negatiftir; x · y > 0 olduğundan x de negatiftir.',
        (x, y, z) => x < 0 && y < 0,
        false,
      ),
      (
        'x · y² > 0 ve x · y < 0',
        'y² pozitif olduğundan x pozitiftir; x · y < 0 olduğundan y negatiftir.',
        (x, y, z) => x > 0 && y < 0,
        false,
      ),
      (
        'x³ · y < 0 ve y > 0',
        'y pozitif olduğundan x³ ve dolayısıyla x negatiftir.',
        (x, y, z) => x < 0 && y > 0,
        false,
      ),
      (
        'x < 0, y > 0 ve z < 0',
        'x ve z negatif, y pozitiftir.',
        (x, y, z) => x < 0 && y > 0 && z < 0,
        true,
      ),
      (
        'x > 0, x · y < 0 ve y · z > 0',
        'x pozitif ve x · y < 0 ise y negatiftir; y · z > 0 ise z de negatiftir.',
        (x, y, z) => x > 0 && y < 0 && z < 0,
        true,
      ),
      (
        'x < 0 < y ve x · y · z > 0',
        'x negatif, y pozitif ve x · y negatif olduğundan z de negatiftir.',
        (x, y, z) => x < 0 && y > 0 && z < 0,
        true,
      ),
    ];

final _isaretIfade2 = <(String, double Function(double, double, double))>[
  ('x · y', (x, y, z) => x * y),
  ('x / y', (x, y, z) => x / y),
  ('x − y', (x, y, z) => x - y),
  ('y − x', (x, y, z) => y - x),
  ('x + y', (x, y, z) => x + y),
  ('x² · y', (x, y, z) => x * x * y),
  ('x · y²', (x, y, z) => x * y * y),
  ('x³ · y', (x, y, z) => x * x * x * y),
  ('x² + y²', (x, y, z) => x * x + y * y),
  ('x² · y³', (x, y, z) => x * x * y * y * y),
  ('(x − y) · x', (x, y, z) => (x - y) * x),
  ('(y − x) · y', (x, y, z) => (y - x) * y),
  ('x − y²', (x, y, z) => x - y * y),
  ('y − x²', (x, y, z) => y - x * x),
  ('x² − y²', (x, y, z) => x * x - y * y),
  ('x / y²', (x, y, z) => x / (y * y)),
  ('(x + y) · y', (x, y, z) => (x + y) * y),
];

final _isaretIfade3 = <(String, double Function(double, double, double))>[
  ('x · y · z', (x, y, z) => x * y * z),
  ('x · z', (x, y, z) => x * z),
  ('y · z', (x, y, z) => y * z),
  ('x + z', (x, y, z) => x + z),
  ('x · y² · z', (x, y, z) => x * y * y * z),
  ('x − y', (x, y, z) => x - y),
  ('y − z', (x, y, z) => y - z),
  ('x · y + z', (x, y, z) => x * y + z),
  ('x² · y · z', (x, y, z) => x * x * y * z),
  ('(x + z) · y', (x, y, z) => (x + z) * y),
  ('x / z', (x, y, z) => x / z),
  ('x · z − y', (x, y, z) => x * z - y),
  ('y² · z', (x, y, z) => y * y * z),
  ('x + y', (x, y, z) => x + y),
];

const _ornekDeger = [
  -9.0, -4.0, -3.0, -2.0, -1.5, -1.0, -0.75, -0.5, -0.25, 0.25, 0.5, 0.75, //
  1.0, 1.5, 2.0, 3.0, 4.0, 9.0,
];

/// İşaret sınıfı: 1 daima pozitif, −1 daima negatif, 0 belirsiz.
int _isaret(
  double Function(double, double, double) f,
  bool Function(double, double, double) kosul,
  bool ucDegisken,
) {
  var poz = false, neg = false;
  for (final x in _ornekDeger) {
    for (final y in _ornekDeger) {
      for (final z in ucDegisken ? _ornekDeger : const [1.0]) {
        if (!kosul(x, y, z)) continue;
        final v = f(x, y, z);
        if (v > 1e-12) {
          poz = true;
        } else if (v < -1e-12) {
          neg = true;
        } else {
          return 0;
        }
        if (poz && neg) return 0;
      }
    }
  }
  return poz ? 1 : -1;
}

final _isaretTablo = [
  for (final k in _isaretKosul)
    [
      for (final e in k.$4 ? _isaretIfade3 : _isaretIfade2)
        _isaret(e.$2, k.$3, k.$4),
    ],
];

bool _ucDegiskenParite(int k) => _pariteKosul[k].$1.contains('z');

final _pariteTablo = [
  for (var k = 0; k < _pariteKosul.length; k++)
    [
      for (final e in _ucDegiskenParite(k) ? _pariteIfade3 : _pariteIfade2)
        _parite(e, _pariteKosul[k].$3),
    ],
];

/// [n] ögeden üçlü seçkilerin sözlük sıralı listesi (i < j < l).
List<List<int>> _ucluler(int n) => [
  for (var i = 0; i < n; i++)
    for (var j = i + 1; j < n; j++)
      for (var l = j + 1; l < n; l++) [i, j, l],
];

/// Bir koşul ve sorulan özellik için uygun üçlüler: en az bir öncül doğru.
/// Üçlüler, liste boyunca dağılsın diye sabit adımla dolaşılır. [yasak]
/// içindeki ifadeler (koşulu aynen yineleyenler) hiçbir üçlüye girmez.
List<List<int>> _uygunUcluler(
  List<int> sinif,
  int hedef, [
  Set<int> yasak = const {},
]) {
  final hepsi = _ucluler(sinif.length);
  final adim = _adimSec(hepsi.length);
  final r = <List<int>>[];
  for (var k = 0; k < hepsi.length; k++) {
    final u = hepsi[k * adim % hepsi.length];
    if (u.any(yasak.contains)) continue;
    if (u.any((j) => sinif[j] == hedef)) r.add(u);
  }
  return r;
}

final _onculSonu = RegExp(r'^ (<|>|toplamı|çarpımı|tek|çift)');

/// İfade, koşul metninde tek başına bir öncül olarak geçiyor mu? (“x · y
/// çarpımı tek sayıdır.” ya da “x · y < 0 ve x < y” koşulunda x · y gibi.)
/// Böyle bir öncül verilen bilgiyi aynen yineler ve seçenekleri ele verir.
bool _onculuYineler(String kosul, String ifade) {
  for (var i = kosul.indexOf(ifade); i >= 0; i = kosul.indexOf(ifade, i + 1)) {
    final once = kosul.substring(0, i);
    if ((once.isEmpty || once.endsWith(', ') || once.endsWith('ve ')) &&
        _onculSonu.hasMatch(kosul.substring(i + ifade.length))) {
      return true;
    }
  }
  return false;
}

/// Koşulu aynen yineleyen ifadelerin dizinleri.
Set<int> _yineleyenler(String kosul, List<String> ifadeler) => {
  for (var j = 0; j < ifadeler.length; j++)
    if (_onculuYineler(kosul, ifadeler[j])) j,
};

/// n ile aralarında asal, n/3 civarında bir adım.
int _adimSec(int n) {
  var a = n ~/ 3 + 1;
  while (a.gcd(n) != 1) {
    a++;
  }
  return a;
}

final _pariteUclu = [
  for (var k = 0; k < _pariteKosul.length; k++)
    [
      for (final h in const [1, 0])
        _uygunUcluler(
          _pariteTablo[k],
          h,
          _yineleyenler(_pariteKosul[k].$1, [
            for (final e
                in _ucDegiskenParite(k) ? _pariteIfade3 : _pariteIfade2)
              e.$1,
          ]),
        ),
    ],
];

final _isaretUclu = [
  for (var k = 0; k < _isaretKosul.length; k++)
    [
      for (final h in const [1, -1])
        _uygunUcluler(
          _isaretTablo[k],
          h,
          _yineleyenler(_isaretKosul[k].$1, [
            for (final e in _isaretKosul[k].$4 ? _isaretIfade3 : _isaretIfade2)
              e.$1,
          ]),
        ),
    ],
];

AdvancedItem _tekCiftSoru(int i) {
  final parite = i < 2500;
  final j = parite ? i : i - 2500;
  final kosulSayisi = parite ? _pariteKosul.length : _isaretKosul.length;
  final kk = j % (2 * kosulSayisi);
  final k = kk ~/ 2, h = kk % 2;
  final r = j ~/ (2 * kosulSayisi);
  final uclu = (parite ? _pariteUclu : _isaretUclu)[k][h];
  final secki = uclu[r % uclu.length];
  final sira = ucluDizilimler[(r + k) % 6];
  final x = [for (final p in sira) secki[p]];
  final sinif = parite ? _pariteTablo[k] : _isaretTablo[k];
  final hedef = parite ? (h == 0 ? 1 : 0) : (h == 0 ? 1 : -1);
  final karsi = parite ? 1 - hedef : -hedef;
  final yazi = [
    for (final e in x)
      parite
          ? (_ucDegiskenParite(k) ? _pariteIfade3 : _pariteIfade2)[e].$1
          : (_isaretKosul[k].$4 ? _isaretIfade3 : _isaretIfade2)[e].$1,
  ];
  var maske = 0, belirsiz = 0, ters = 0;
  for (var t = 0; t < 3; t++) {
    final v = sinif[x[t]];
    if (v == hedef) maske |= 1 << t;
    if (parite ? v == -1 : v == 0) belirsiz |= 1 << t;
    if (v == karsi) ters |= 1 << t;
  }
  final ozellik = parite
      ? (hedef == 1 ? 'tek sayıdır' : 'çift sayıdır')
      : (hedef == 1 ? 'pozitiftir' : 'negatiftir');
  String durum(int v) => parite
      ? switch (v) {
          1 => 'daima tektir',
          0 => 'daima çifttir',
          _ => 'tek de olabilir çift de',
        }
      : switch (v) {
          1 => 'daima pozitiftir',
          -1 => 'daima negatiftir',
          _ => 'pozitif de olabilir negatif de',
        };
  final degisken = parite
      ? (_ucDegiskenParite(k)
            ? 'x, y ve z tam sayılardır.'
            : 'x ve y tam sayılardır.')
      : (_isaretKosul[k].$4
            ? 'x, y ve z gerçek sayıları için ${_isaretKosul[k].$1} olduğu biliniyor.'
            : 'x ve y gerçek sayıları için ${_isaretKosul[k].$1} olduğu biliniyor.');
  final kosulMetni = parite ? ' ${_pariteKosul[k].$1}' : '';
  final ozet = parite ? _pariteKosul[k].$2 : _isaretKosul[k].$2;
  final kok =
      '$degisken$kosulMetni\n'
      'I. ${yazi[0]}\nII. ${yazi[1]}\nIII. ${yazi[2]}\n'
      'Bu ifadelerden hangileri daima $ozellik?';
  final aciklama =
      '$ozet Buna göre ${[for (var t = 0; t < 3; t++) '${_romen[t]}. ifade ${durum(sinif[x[t]])}'].join('; ')}. '
      'Yanıt: ${_kumeAdi[maske]}.';
  return _hangileri(
    kok,
    maske,
    [maske | belirsiz, if (ters != 0) ters, belirsiz],
    aciklama,
    i,
  );
}

// ---------------------------------------------------------------------------
// 5. Gerçek sayıları sıralama (öncüllü)
// ---------------------------------------------------------------------------

/// Sıralanacak sayı: (yazılış, değer, tür). Tür: 0 kesir, 1 ondalık, 2 köklü,
/// 3 üslü.
typedef _Sayi = (String, double, int);

String _ondalikYaz(int k, int basamak) {
  final b = _kuvvet(10, basamak);
  final tam = k ~/ b, kalan = k % b;
  if (kalan == 0) return '$tam';
  var s = '$kalan'.padLeft(basamak, '0');
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return '$tam,$s';
}

final List<_Sayi> _siraSayilari = () {
  final r = <_Sayi>[];
  const alt = 0.15, ust = 6.0;
  bool aralikta(double v) => v >= alt && v <= ust;
  // Kesirler.
  for (final q in const [2, 3, 4, 5, 6, 7, 8, 9, 11, 12]) {
    for (var p = 1; p <= 6 * q; p++) {
      if (p.gcd(q) != 1 || p % q == 0) continue;
      final v = p / q;
      if (aralikta(v)) r.add(('$p/$q', v, 0));
    }
  }
  // Ondalık sayılar: 0,05 adımlı, tam sayı olmayanlar.
  for (var k = 15; k <= 600; k += 5) {
    if (k % 100 == 0) continue;
    r.add((_ondalikYaz(k, 2), k / 100, 1));
  }
  // Köklü sayılar.
  for (var n = 2; n <= 35; n++) {
    final kok = _tamKok(n, 2);
    if (kok * kok == n) continue;
    r.add(('√$n', _karekok(n.toDouble()), 2));
  }
  for (final k in const [1, 2, 3, 5, 6, 7, 8, 9]) {
    r.add(('√0,$k', _karekok(k / 10), 2));
  }
  for (final (a, b) in const [
    (2, 2),
    (2, 3),
    (3, 2),
    (2, 5),
    (3, 3),
    (2, 6),
    (2, 7),
  ]) {
    r.add(('$a√$b', a * _karekok(b.toDouble()), 2));
  }
  // Üslü sayılar.
  for (final (p, q) in const [
    (1, 2),
    (1, 3),
    (2, 3),
    (3, 4),
    (3, 2),
    (4, 3),
    (5, 4),
    (5, 3),
    (7, 4),
    (5, 2),
    (7, 3),
    (2, 5),
    (3, 5),
    (4, 5),
    (6, 5),
    (7, 5),
    (5, 6),
    (7, 6),
  ]) {
    for (final e in const [2, 3, -1, -2]) {
      final v = e > 0
          ? _kuvvet(p, e) / _kuvvet(q, e)
          : _kuvvet(q, -e) / _kuvvet(p, -e);
      if (aralikta(v)) r.add(('($p/$q)${_ust(e)}', v, 3));
    }
  }
  for (var k = 3; k <= 19; k++) {
    if (k == 10) continue;
    for (final e in const [2, 3]) {
      final v = _kuvvet(k, e) / _kuvvet(10, e);
      if (aralikta(v)) r.add(('${_ondalikYaz(k, 1)}${_ust(e)}', v, 3));
    }
  }
  for (final (t, e) in const [
    (2, -1),
    (2, -2),
    (3, -1),
    (4, -1),
    (5, -1),
    (2, -3),
  ]) {
    r.add(('$t${_ust(e)}', 1 / _kuvvet(t, -e), 3));
  }
  for (final (t, e) in const [(2, 3), (3, 3), (2, 5)]) {
    r.add(('(√$t)${_ust(e)}', _kuvvet(t, e ~/ 2) * _karekok(t.toDouble()), 3));
  }
  r.sort((x, y) => x.$2.compareTo(y.$2));
  return r;
}();

double _karekok(double x) {
  // Newton yöntemi; dart:math içe aktarılmadan karekök.
  var r = x < 1 ? 1.0 : x;
  for (var i = 0; i < 60; i++) {
    r = (r + x / r) / 2;
  }
  return r;
}

/// Farklı türden, birbirine yakın ama ayırt edilebilir üç sayının dizinleri.
final List<List<int>> _siraUclu = () {
  final s = _siraSayilari;
  final r = <List<int>>[];
  for (var i = 0; i < s.length; i++) {
    for (var j = i + 1; j < s.length; j++) {
      if (s[j].$2 > s[i].$2 * 1.3) break;
      if (s[j].$2 < s[i].$2 * 1.02 || s[j].$3 == s[i].$3) continue;
      for (var k = j + 1; k < s.length; k++) {
        if (s[k].$2 > s[i].$2 * 1.3) break;
        if (s[k].$2 < s[j].$2 * 1.02) continue;
        if (s[k].$3 == s[i].$3 || s[k].$3 == s[j].$3) continue;
        r.add([i, j, k]);
      }
    }
  }
  return r;
}();

String _yaklasik(_Sayi x) {
  final v = x.$2;
  final bin = (v * 1000).round();
  final kesin = ((v * 1000) - bin).abs() < 1e-9;
  final yazi = _ondalikYaz(bin, 3);
  if (yazi == x.$1) return x.$1;
  return '${x.$1} ${kesin ? '=' : '≈'} $yazi';
}

const _harf = ['a', 'b', 'c'];

AdvancedItem _siralamaSoru(int i) {
  final toplam = _siraUclu.length;
  final secki = _siraUclu[i * toplam ~/ 5000];
  final dizilim = ucluDizilimler[i % 6];
  // sayi[t]: t harfine (a, b, c) atanan sayı; sira[t]: küçükten büyüğe yeri.
  final sayi = [for (final d in dizilim) _siraSayilari[secki[d]]];
  final yer = [for (final d in dizilim) d];
  bool kucuk(int x, int y) => yer[x] < yer[y];
  // Öncüller: I a–b, II b–c, III a–c; yönler i ile değişir. Bazı vakalarda
  // III. öncül üçlü sıralamadır.
  final yon = i ~/ 6 % 8;
  final zincir = i ~/ 48 % 4 == 3;
  final ciftler = const [(0, 1), (1, 2), (0, 2)];
  final metin = <String>[];
  final dogru = <bool>[];
  for (var t = 0; t < 3; t++) {
    if (t == 2 && zincir) {
      final z = ucluDizilimler[i ~/ 192 % 6];
      metin.add('${_harf[z[0]]} < ${_harf[z[1]]} < ${_harf[z[2]]}');
      dogru.add(kucuk(z[0], z[1]) && kucuk(z[1], z[2]));
      continue;
    }
    final (x, y) = ciftler[t];
    final ters = (yon >> t) & 1 == 1;
    final buyukYaz = (i ~/ 3 + t) % 2 == 0;
    final (sol, sag) = ters ? (y, x) : (x, y);
    metin.add(
      buyukYaz
          ? '${_harf[sag]} > ${_harf[sol]}'
          : '${_harf[sol]} < ${_harf[sag]}',
    );
    dogru.add(kucuk(sol, sag));
  }
  if (!dogru.contains(true)) {
    // Hiçbir öncül doğru değilse bir öncül doğru biçimine çevrilir.
    final t = i ~/ 7 % 3;
    if (t == 2 && zincir) {
      final s = [0, 1, 2]..sort((x, y) => yer[x].compareTo(yer[y]));
      metin[2] = s.map((x) => _harf[x]).join(' < ');
    } else {
      final (x, y) = ciftler[t];
      final (sol, sag) = kucuk(x, y) ? (x, y) : (y, x);
      metin[t] = (i ~/ 3 + t) % 2 == 0
          ? '${_harf[sag]} > ${_harf[sol]}'
          : '${_harf[sol]} < ${_harf[sag]}';
    }
    dogru[t] = true;
  }
  var maske = 0;
  for (var t = 0; t < 3; t++) {
    if (dogru[t]) maske |= 1 << t;
  }
  final sirali = [0, 1, 2]..sort((x, y) => yer[x].compareTo(yer[y]));
  final kok =
      'a = ${sayi[0].$1}, b = ${sayi[1].$1} ve c = ${sayi[2].$1} sayıları '
      'veriliyor.\nI. ${metin[0]}\nII. ${metin[1]}\nIII. ${metin[2]}\n'
      'Bu ifadelerden hangileri doğrudur?';
  final aciklama =
      '${[for (var t = 0; t < 3; t++) '${_harf[t]} = ${_yaklasik(sayi[t])}'].join('; ')} '
      'olduğundan ${sirali.map((t) => _harf[t]).join(' < ')} sıralaması bulunur. '
      'Buna göre doğru öncüller: ${_kumeAdi[maske]!.replaceFirst('Yalnız ', '')}.';
  return _hangileri(kok, maske, [maske ^ 7], aciklama, i);
}

// ---------------------------------------------------------------------------
// 6. Bilimsel gösterim
// ---------------------------------------------------------------------------

/// N · 10^k biçimli kesin sayı; N sondaki sıfırlardan arındırılır.
(int, int) _sade((int, int) x) {
  var (n, k) = x;
  while (n != 0 && n % 10 == 0) {
    n ~/= 10;
    k++;
  }
  return (n, k);
}

int _basamakSayisi(int n) => '${n.abs()}'.length;

/// Bilimsel gösterimin katsayısı ve üssü: (katsayı yazısı, üs).
(String, int) _bilimsel((int, int) x) {
  final (n, k) = _sade(x);
  final d = _basamakSayisi(n);
  return (_ondalikYaz(n, d - 1), k + d - 1);
}

String _bilimselYaz(String katsayi, int us) => '$katsayi · 10${_ust(us)}';

/// N · 10^k sayısının düz yazımı: `0,000384`, `52000000`.
String _duzYaz((int, int) x) {
  final (n, k) = _sade(x);
  if (k >= 0) return '$n${'0' * k}';
  return _ondalikYaz(n, -k);
}

/// Sondaki sıfırı olmayan iki ve üç basamaklı katsayı gövdeleri.
final _govdeler = [
  for (var x = 12; x <= 998; x++)
    if (x % 10 != 0 && x % 11 != 0) x,
];

int _govde(int j) => _govdeler[j * 7 % _govdeler.length];

/// Bilimsel gösterimde çarpma ve bölme için bir ya da iki anlamlı basamaklı
/// katsayılar (N, ondalık basamak sayısı): 25 → 2,5.
const _katsayi1 = [
  (12, 1),
  (15, 1),
  (2, 0),
  (25, 1),
  (3, 0),
  (32, 1),
  (4, 0),
  (45, 1),
  (5, 0),
  (6, 0),
  (64, 1),
  (75, 1),
  (8, 0),
  (9, 0),
  (125, 2),
  (24, 1),
  (35, 1),
  (16, 1),
  (48, 1),
  (22, 1),
  (55, 1),
  (7, 0),
  (18, 1),
  (36, 1),
  (95, 1),
];
const _katsayi2 = [
  (2, 0),
  (3, 0),
  (4, 0),
  (5, 0),
  (6, 0),
  (8, 0),
  (15, 1),
  (25, 1),
];

/// Üç çarpanlı işlem için katsayı adayları.
const _katsayiGenis = [
  ..._katsayi1,
  (14, 1),
  (28, 1),
  (42, 1),
  (56, 1),
  (65, 1),
  (85, 1),
  (26, 1),
  (34, 1),
  (38, 1),
  (46, 1),
  (52, 1),
  (58, 1),
  (62, 1),
  (68, 1),
  (72, 1),
  (78, 1),
  (82, 1),
  (88, 1),
  (92, 1),
  (98, 1),
  (21, 1),
  (27, 1),
  (33, 1),
  (39, 1),
  (44, 1),
  (54, 1),
  (66, 1),
  (77, 1),
  (84, 1),
  (96, 1),
];

AdvancedItem _bilimselSecenek(
  String kok,
  (String, int) yanit,
  Iterable<(String, int)> adaylar,
  String aciklama,
) => secenekli(kok, _bilimselYaz(yanit.$1, yanit.$2), [
  for (final (a, e) in adaylar)
    if (e != 0 && e.abs() <= 30) _bilimselYaz(a, e),
  _bilimselYaz(yanit.$1, yanit.$2 + 2),
  _bilimselYaz(yanit.$1, yanit.$2 - 2),
], aciklama);

AdvancedItem _bilimselSoru(int a, int b, int c) =>
    _kokteOlmayan((v) => _bilimselUret(a, b, c, v));

/// [v]: üs gibi ikincil bir parametreyi kaydırır (yanıt kökte yazılıysa).
AdvancedItem _bilimselUret(int a, int b, int c, int v) {
  final j = a + 25 * b;
  final usSor = c >= 6;
  final tur = usSor ? const [0, 2, 3, 4][c - 6] : c;
  // Her tür için kök ifadesi, doğru (katsayı, üs), yanlış adaylar, açıklama.
  late final String ifade, aciklama;
  late final (String, int) dogru;
  late final List<(String, int)> yanlis;
  switch (tur) {
    case 0 || 1:
      final kucuk = tur == 0;
      final g = _govde(usSor ? j + 500 : (kucuk ? j : j + 1000));
      final d = _basamakSayisi(g);
      final n = kucuk ? -(usSor ? 3 : 2) - b ~/ 4 : 4 + b ~/ 4;
      final deger = (g, n - d + 1);
      ifade = _duzYaz(deger);
      dogru = _bilimsel(deger);
      final kat = dogru.$1;
      if (kucuk) {
        yanlis = [(kat, n + 1), (kat, -n), (kat, n - 1)];
        aciklama =
            'Virgül, sıfırdan farklı ilk rakamın sağına gelene kadar ${-n} '
            'basamak sağa kaydırılır. Katsayı $kat, üs −${-n} olur: '
            '${_bilimselYaz(kat, n)}.';
      } else {
        yanlis = [(kat, n - 1), (kat, n + 1), (kat, -n)];
        aciklama =
            'Virgül, ilk rakamın sağına gelene kadar $n basamak sola kaydırılır. '
            'Katsayı $kat, üs $n olur: ${_bilimselYaz(kat, n)}.';
      }
    case 2:
      final g = _govde(usSor ? j + 1500 : j + 2000);
      final d = _basamakSayisi(g);
      // Katsayı 10 ya da daha büyük (r > 0) veya 1 sayısından küçük (r < 0).
      final r = const [1, 2, 3, -1, -2][b % 5];
      var q =
          (usSor ? 1 : -1) * (2 + b ~/ 5 + 4 * v) * ((a + b).isEven ? 1 : -1);
      if (r + q == 0) q += q > 0 ? 1 : -1; // sonuç üssü sıfır olmasın
      final katYazi = _duzYaz((g, r - d + 1));
      ifade = '$katYazi · 10${_ust(q)}';
      dogru = _bilimsel((g, r - d + 1 + q));
      final k = dogru.$1;
      yanlis = [(k, q - r), (k, q), (k, q + r + (r > 0 ? 1 : -1))];
      aciklama =
          '$katYazi = ${_bilimselYaz(k, r)} olduğundan sayı ${_bilimselYaz(k, r)} · '
          '10${_ust(q)} = ${_bilimselYaz(k, r + q)} olur.';
    case 3:
      final (n1, b1) = _katsayi1[a];
      final (n2, b2) = _katsayi2[b % 8];
      var e1 =
          const [3, -4, 5, -2, 7, -6, 2, -8, 6, -3][(a + b) % 10] *
          (b < 10 ? 1 : -1);
      e1 += (e1 > 0 ? 1 : -1) * 3 * v;
      final e2 = const [
        -5,
        4,
        -7,
        6,
        2,
        -3,
        8,
        -2,
      ][b ~/ 4 % 5 + (usSor ? 3 : 0)];
      final carpim = (n1 * n2, -b1 - b2);
      final x = _bilimsel(carpim);
      // Sonuç üssü sıfır olmasın.
      if (x.$2 + e1 + e2 == 0) e1 += e1 > 0 ? 1 : -1;
      dogru = (x.$1, x.$2 + e1 + e2);
      final kaydi = dogru.$2 - e1 - e2; // 0 ya da 1
      final k1 = _ondalikYaz(n1, b1), k2 = _ondalikYaz(n2, b2);
      final ham = _duzYaz(carpim);
      ifade = '(${_bilimselYaz(k1, e1)}) · (${_bilimselYaz(k2, e2)})';
      yanlis = [
        (dogru.$1, e1 + e2 + (kaydi == 1 ? 0 : 1)),
        (dogru.$1, e1 * e2),
        (dogru.$1, e1 - e2 + kaydi),
      ];
      aciklama =
          'Katsayılar çarpılır, üsler toplanır: $k1 · $k2 = $ham ve 10${_ust(e1)} '
          '· 10${_ust(e2)} = 10${_ust(e1 + e2)}. '
          '${kaydi == 1 ? '$ham · 10${_ust(e1 + e2)} = ' : 'Sonuç '}'
          '${_bilimselYaz(dogru.$1, dogru.$2)} bulunur.';
    case 4:
      // Bölüm katsayısı ve bölen seçilir; bölünen bunların çarpımıdır.
      final (nq, bq) = _katsayi1[a];
      final (n2, b2) = _katsayi2[b % 8];
      final bolunen = _bilimsel((nq * n2, -bq - b2));
      var e1 =
          const [8, -3, 6, -5, 9, -2, 4, -7, 5, -4][(a + 2 * b) % 10] *
          (b < 10 ? 1 : -1);
      e1 += (e1 > 0 ? 1 : -1) * 3 * v;
      final e2 = const [
        3,
        -6,
        5,
        -4,
        2,
        -8,
        7,
        -3,
      ][b ~/ 4 % 5 + (usSor ? 3 : 0)];
      final k1 = bolunen.$1, k2 = _ondalikYaz(n2, b2);
      final q = _bilimsel((nq, -bq));
      final kaydi = q.$2 - bolunen.$2; // −1 ya da 0
      // Sonuç üssü sıfır olmasın.
      if (e1 - e2 + kaydi == 0) e1 += e1 > 0 ? 1 : -1;
      dogru = (q.$1, e1 - e2 + kaydi);
      ifade = '(${_bilimselYaz(k1, e1)}) / (${_bilimselYaz(k2, e2)})';
      yanlis = [
        (dogru.$1, e2 - e1 + kaydi),
        (dogru.$1, e1 + e2 + kaydi),
        (dogru.$1, e1 - e2 + (kaydi == 0 ? -1 : 0)),
      ];
      final ham = _duzYaz((nq, -bq - bolunen.$2));
      aciklama =
          'Katsayılar bölünür, üsler çıkarılır: $k1 / $k2 = $ham ve 10${_ust(e1)} '
          '/ 10${_ust(e2)} = 10${_ust(e1 - e2)}. '
          '${kaydi == 0 ? 'Sonuç ' : '$ham · 10${_ust(e1 - e2)} = '}'
          '${_bilimselYaz(dogru.$1, dogru.$2)} bulunur.';
    default:
      // Üç çarpanlı işlem: (k1 · 10^e1) · (k2 · 10^e2) / (k3 · 10^e3).
      final (n2, b2) = _katsayi2[b % 8];
      final n3 = const [2, 4, 5, 8][b ~/ 5];
      // Sonuç katsayısı en çok dört anlamlı basamaklı olsun.
      final (n1, b1) = _uygun(_katsayiGenis, a, (k) {
        final t = k.$1 * n2 * 1000;
        return t % n3 == 0 && _basamakSayisi(_sade((t ~/ n3, 0)).$1) <= 4;
      });
      final e1 = const [4, -3, 6, -5, 2, -7, 5, -2, 3, -6][(a + b) % 10];
      final e2 = const [-6, 5, -2, 7, -4, 3, -8, 2][(b + a ~/ 5) % 8];
      // Pay N1 · N2 / n3 tam sayı olsun diye 1000 ile genişletilir.
      final pay = n1 * n2 * 1000 ~/ n3;
      final kaydi0 = _bilimsel((pay, -b1 - b2 - 3)).$2;
      final e3 = _uygun(
        const [2, -3, 4, -5, 3, -2, 5, -4, 6, -6, 7, -7, 1, -1],
        (a + 3 * b) % 5,
        (x) {
          final son = e1 + e2 - x + kaydi0;
          return son != 0 && son.abs() <= 14;
        },
      );
      final ham = (pay, -b1 - b2 - 3);
      final x = _bilimsel(ham);
      final us = e1 + e2 - e3;
      dogru = (x.$1, x.$2 + us);
      final kaydi = x.$2; // −1, 0 ya da 1
      final k1 = _ondalikYaz(n1, b1), k2 = _ondalikYaz(n2, b2);
      ifade =
          '(${_bilimselYaz(k1, e1)}) · (${_bilimselYaz(k2, e2)}) / '
          '(${_bilimselYaz('$n3', e3)})';
      yanlis = [
        (dogru.$1, e1 + e2 + e3 + kaydi),
        (dogru.$1, us + (kaydi == 0 ? 1 : 0)),
        (dogru.$1, e3 - e1 - e2 + kaydi),
      ];
      final hamYazi = _duzYaz(ham);
      aciklama =
          'Katsayılar: $k1 · $k2 / $n3 = $hamYazi; üsler: ${_n(e1)} + ${_p(e2)} − '
          '${_p(e3)} = ${_n(us)}. '
          '${kaydi == 0 ? 'Sonuç ' : '$hamYazi · 10${_ust(us)} = '}'
          '${_bilimselYaz(dogru.$1, dogru.$2)} bulunur.';
  }
  if (usSor) {
    final soru = tur == 0 || tur == 2
        ? '$ifade sayısı'
        : '$ifade işleminin sonucu';
    return _tam(
      '$soru a · 10ⁿ biçiminde bilimsel gösterimle yazıldığında n kaçtır?',
      dogru.$2,
      [for (final y in yanlis) y.$2],
      aciklama,
    );
  }
  final soru = tur <= 2
      ? '$ifade sayısının bilimsel gösterimi nedir?'
      : '$ifade işleminin sonucunun bilimsel gösterimi nedir?';
  return _bilimselSecenek(soru, dogru, yanlis, aciklama);
}

// ---------------------------------------------------------------------------
// 7. Sayı aralıkları
// ---------------------------------------------------------------------------

/// Gerçek sayı aralığı: (alt uç, alt uç dâhil mi, üst uç, üst uç dâhil mi).
typedef _Ar = (int, bool, int, bool);

bool _bos(_Ar x) => x.$1 > x.$3 || (x.$1 == x.$3 && !(x.$2 && x.$4));

String _arYaz(_Ar x) =>
    '${x.$2 ? '[' : '('}${_n(x.$1)}, ${_n(x.$3)}${x.$4 ? ']' : ')'}';

String _esitsizlikYaz(_Ar x) =>
    '${_n(x.$1)} ${x.$2 ? '≤' : '<'} x ${x.$4 ? '≤' : '<'} ${_n(x.$3)}';

_Ar _kesisim(_Ar x, _Ar y) {
  final (int lo, bool loK) = x.$1 > y.$1
      ? (x.$1, x.$2)
      : x.$1 < y.$1
      ? (y.$1, y.$2)
      : (x.$1, x.$2 && y.$2);
  final (int hi, bool hiK) = x.$3 < y.$3
      ? (x.$3, x.$4)
      : x.$3 > y.$3
      ? (y.$3, y.$4)
      : (x.$3, x.$4 && y.$4);
  return (lo, loK, hi, hiK);
}

/// Kesişen iki aralığın birleşimi.
_Ar _birlesim(_Ar x, _Ar y) {
  final (int lo, bool loK) = x.$1 < y.$1
      ? (x.$1, x.$2)
      : x.$1 > y.$1
      ? (y.$1, y.$2)
      : (x.$1, x.$2 || y.$2);
  final (int hi, bool hiK) = x.$3 > y.$3
      ? (x.$3, x.$4)
      : x.$3 < y.$3
      ? (y.$3, y.$4)
      : (x.$3, x.$4 || y.$4);
  return (lo, loK, hi, hiK);
}

/// x \ y: en çok iki parça.
List<_Ar> _fark(_Ar x, _Ar y) => [
  for (final p in [
    _kesisim(x, (-1000, false, y.$1, !y.$2)),
    _kesisim(x, (y.$3, !y.$4, 1000, false)),
  ])
    if (!_bos(p)) p,
];

List<int> _tamlar(List<_Ar> parcalar) => [
  for (final p in parcalar)
    if (!_bos(p))
      for (var t = p.$2 ? p.$1 : p.$1 + 1; p.$4 ? t <= p.$3 : t < p.$3; t++) t,
];

String _parcaYaz(List<_Ar> x) => x.isEmpty ? '∅' : x.map(_arYaz).join(' ∪ ');

String _tamListe(List<int> liste) {
  final t = [...liste]..sort();
  if (t.isEmpty) return 'tam sayı yoktur';
  if (t.length == 1) return 'yalnızca ${_n(t.first)} olup 1 tanedir';
  if (t.length <= 6) {
    return '${[for (final x in t) _n(x)].join(', ')} olup ${t.length} tanedir';
  }
  // Aradaki boşluklar “…” ile örtülmesin diye her ardışık blok ayrı yazılır:
  // −10, −9, …, −6 ile −4, −3.
  final bloklar = <List<int>>[];
  for (final x in t) {
    if (bloklar.isNotEmpty && bloklar.last.last + 1 == x) {
      bloklar.last.add(x);
    } else {
      bloklar.add([x]);
    }
  }
  String blok(List<int> b) => b.length <= 3
      ? [for (final x in b) _n(x)].join(', ')
      : '${_n(b[0])}, ${_n(b[1])}, …, ${_n(b.last)}';
  final yazi = [for (final b in bloklar) blok(b)];
  final birlesik = yazi.length <= 2
      ? yazi.join(' ile ')
      : '${yazi.sublist(0, yazi.length - 1).join('; ')} ve ${yazi.last}';
  return '$birlesik olup ${t.length} tanedir';
}

AdvancedItem _aralikSoru(int a, int b, int c) {
  final p1 = a - 12, uzun = 6 + b % 5, ara = 2 + b ~/ 5;
  final q1 = p1 + uzun, p2 = p1 + ara;
  final ic =
      (a + b + c) % 3 == 0 && uzun - 2 > ara; // ikinci aralık ilkinin içinde mi
  final q2 = ic ? q1 - 1 - (a + b) % 2 : q1 + 2 + (a + b) % 4;
  // İç içe aralıklarda farkı sorulan küme dıştaki aralık olur.
  final takas = ic && (c == 2 || c == 5 || c == 3) ? c == 3 : (a * b + c).isOdd;
  // Uçların açık/kapalı oluşu; yanıtı sıfır yapan (tam sayısı olmayan küme,
  // sıfır toplam) seçimler atlanır.
  (_Ar, _Ar) araliklar(int tip) {
    final _Ar ilk = (p1, tip & 1 == 1, q1, tip & 2 == 2);
    final _Ar ikinci = (p2, tip & 4 == 4, q2, tip & 8 == 8);
    return takas ? (ikinci, ilk) : (ilk, ikinci);
  }

  int sorulan(_Ar x, _Ar y) => switch (c) {
    0 || 8 || 4 =>
      _tamlar([_kesisim(x, y)]).length *
          (c == 4 ? _topla(_tamlar([_kesisim(x, y)])) : 1),
    2 || 5 =>
      _tamlar(_fark(x, y)).length * (c == 5 ? _topla(_tamlar(_fark(x, y))) : 1),
    3 => _tamlar(_fark(y, x)).length,
    _ => 1,
  };
  final ilkTip = (3 * a + b + 5 * c) % 16;
  // Uçların açık/kapalı oluşu ikincil parametredir: yanıtı sıfır olan ya da
  // kökte yazılı bir sayıya eşit çıkan seçimler atlanır.
  final adaylar = [
    for (var k = 0; k < 16; k++)
      if (!_bos(
            _kesisim(
              araliklar((ilkTip + 7 * k) % 16).$1,
              araliklar((ilkTip + 7 * k) % 16).$2,
            ),
          ) &&
          sorulan(
                araliklar((ilkTip + 7 * k) % 16).$1,
                araliklar((ilkTip + 7 * k) % 16).$2,
              ) !=
              0)
        (ilkTip + 7 * k) % 16,
  ];
  _Ar kapat(_Ar x) => (x.$1, true, x.$3, true);
  _Ar ac(_Ar x) => (x.$1, false, x.$3, false);
  // _aralikUret içindeki çeldirici yollarının (uç türü yanlışları, kesişim ile
  // birleşimi ya da iki farkı karıştırmak …) verdiği değerler.
  List<int> uyarlamalar(_Ar x, _Ar y) {
    int say(List<_Ar> t) => _tamlar(t).length;
    int top(List<_Ar> t) => _topla(_tamlar(t));
    List<int> uc(List<int> t) => t.isEmpty ? const [] : [t.first + t.last];
    final kes = [_kesisim(x, y)], bir = [_birlesim(x, y)];
    return switch (c) {
      0 || 8 => [
        say([_kesisim(kapat(x), kapat(y))]),
        say([_kesisim(ac(x), ac(y))]),
        say(bir),
      ],
      1 || 9 => [
        say([_birlesim(kapat(x), kapat(y))]),
        say([_birlesim(ac(x), ac(y))]),
        say([x]) + say([y]),
        say(kes),
      ],
      2 => [
        say(_fark(y, x)),
        say(_fark(kapat(x), ac(y))),
        say(_fark(ac(x), kapat(y))),
        say(kes),
      ],
      3 => [
        say(_fark(x, y)),
        say(_fark(kapat(y), ac(x))),
        say(_fark(ac(y), kapat(x))),
        say(kes),
      ],
      4 => [
        top([_kesisim(kapat(x), kapat(y))]),
        top([_kesisim(ac(x), ac(y))]),
        top(bir),
        say(kes),
      ],
      5 => [
        top(_fark(y, x)),
        top(_fark(kapat(x), ac(y))),
        top(_fark(ac(x), kapat(y))),
        say(_fark(x, y)),
      ],
      6 => [
        ...uc(_tamlar([_birlesim(kapat(x), kapat(y))])),
        ...uc(_tamlar([_birlesim(ac(x), ac(y))])),
        ...uc(_tamlar(kes)),
        bir.first.$1 + bir.first.$3,
      ],
      _ => [
        say(bir),
        say(kes),
        say(_fark(x, y)) + say(_fark(y, x)) + 1,
        say(bir) - say(kes) + 1,
      ],
    };
  }

  // Her seçim puanlanır: yanıt kökte yazılıysa 100, en yaygın yanlış (bütün
  // uçları kapalı sanmak) doğru sonucu veriyorsa 3, öteki çeldirici yollarından
  // doğru sonucu veren her biri için 1. En düşük puanlı seçim alınır (eşitlikte
  // ilk sıradaki). Kaydırılmış uçlar (40 birim; bu kadar büyük uçlar başka hiçbir
  // vakada kullanılmadığından kökler yine farklı kalır) yalnız puanı düşürürse
  // kullanılır. (Tek uç çiftli farklarda üç uç yanlışından biri her zaman doğru
  // sonucu verir; orada en az bir puan kaçınılmazdır.)
  _Ar kaydir(_Ar x) => (x.$1 + 40, x.$2, x.$3 + 40, x.$4);
  (int, AdvancedItem) puanla(_Ar x, _Ar y) {
    final r = _aralikUret(c, (x, y));
    var p = _yanitKokte(r) ? 100 : 0;
    if (_aralikUret(c, (kapat(x), kapat(y))).correct == r.correct) p += 3;
    p += uyarlamalar(x, y).where((v) => _n(v) == r.correct).length;
    return (p, r);
  }

  (int, AdvancedItem)? enIyi;
  for (final kaydirilmis in const [false, true]) {
    for (final t in adaylar) {
      final (x0, y0) = araliklar(t);
      final (x, y) = kaydirilmis ? (kaydir(x0), kaydir(y0)) : (x0, y0);
      final aday = puanla(x, y);
      if (enIyi == null || aday.$1 < enIyi.$1) enIyi = aday;
      if (enIyi.$1 == 0) return enIyi.$2;
    }
  }
  return enIyi!.$2;
}

AdvancedItem _aralikUret(int c, (_Ar, _Ar) ikili) {
  final (A, B) = ikili;
  final esitsizlik = c >= 8;
  final veri = esitsizlik
      ? 'A = {x | ${_esitsizlikYaz(A)}} ve B = {x | ${_esitsizlikYaz(B)}} '
            'gerçek sayı aralıkları veriliyor.'
      : 'A = ${_arYaz(A)} ve B = ${_arYaz(B)} gerçek sayı aralıkları veriliyor.';
  final kes = _kesisim(A, B);
  final bir = _birlesim(A, B);
  final ab = _fark(A, B), ba = _fark(B, A);
  final kesT = _tamlar([kes]), birT = _tamlar([bir]);
  final abT = _tamlar(ab), baT = _tamlar(ba);
  _Ar kapali(_Ar x) => (x.$1, true, x.$3, true);
  _Ar acik(_Ar x) => (x.$1, false, x.$3, false);
  int adet(List<_Ar> x) => _tamlar(x).length;
  switch (c) {
    case 0 || 8:
      return _tamD(
        '$veri A ∩ B kümesinde kaç tam sayı vardır?',
        kesT.length,
        [
          adet([_kesisim(kapali(A), kapali(B))]),
          adet([_kesisim(acik(A), acik(B))]),
          birT.length,
          kesT.length + 1,
          // Uçların farkını tam sayı adedi sanmak.
          kes.$3 - kes.$1,
        ],
        'A ∩ B = ${_arYaz(kes)} olur. Bu aralıktaki tam sayılar ${_tamListe(kesT)}.',
        pozitif: true,
      );
    case 1 || 9:
      return _tamD(
        '$veri A ∪ B kümesinde kaç tam sayı vardır?',
        birT.length,
        [
          adet([_birlesim(kapali(A), kapali(B))]),
          adet([_birlesim(acik(A), acik(B))]),
          _tamlar([A]).length + _tamlar([B]).length,
          kesT.length,
        ],
        'A ∪ B = ${_arYaz(bir)} olur. Bu aralıktaki tam sayılar ${_tamListe(birT)}.',
        pozitif: true,
      );
    case 2:
      return _tamD(
        '$veri A \\ B kümesinde kaç tam sayı vardır?',
        abT.length,
        [
          baT.length,
          _tamlar(_fark(kapali(A), acik(B))).length,
          _tamlar(_fark(acik(A), kapali(B))).length,
          kesT.length,
          // s(A \ B) = s(A) − s(B) sanmak.
          _tamlar([A]).length - _tamlar([B]).length,
        ],
        'A \\ B = ${_parcaYaz(ab)} olur. Bu kümedeki tam sayılar ${_tamListe(abT)}.',
        pozitif: true,
      );
    case 3:
      return _tamD(
        '$veri B \\ A kümesinde kaç tam sayı vardır?',
        baT.length,
        [
          abT.length,
          _tamlar(_fark(kapali(B), acik(A))).length,
          _tamlar(_fark(acik(B), kapali(A))).length,
          kesT.length,
          // s(B \ A) = s(B) − s(A) sanmak.
          _tamlar([B]).length - _tamlar([A]).length,
        ],
        'B \\ A = ${_parcaYaz(ba)} olur. Bu kümedeki tam sayılar ${_tamListe(baT)}.',
        pozitif: true,
      );
    case 4:
      final t = _topla(kesT);
      return _tamD(
        '$veri A ∩ B kümesindeki tam sayıların toplamı kaçtır?',
        t,
        [
          _topla(_tamlar([_kesisim(kapali(A), kapali(B))])),
          _topla(_tamlar([_kesisim(acik(A), acik(B))])),
          _topla(birT),
          kesT.length,
        ],
        'A ∩ B = ${_arYaz(kes)} olur. Bu aralıktaki tam sayılar '
            '${_tamListe(kesT)}; toplamları ${_n(t)} bulunur.',
      );
    case 5:
      final t = _topla(abT);
      return _tamD(
        '$veri A \\ B kümesindeki tam sayıların toplamı kaçtır?',
        t,
        [
          _topla(baT),
          _topla(_tamlar(_fark(kapali(A), acik(B)))),
          _topla(_tamlar(_fark(acik(A), kapali(B)))),
          abT.length,
        ],
        'A \\ B = ${_parcaYaz(ab)} olur. Bu kümedeki tam sayılar '
            '${_tamListe(abT)}; toplamları ${_n(t)} bulunur.',
      );
    case 6:
      final t = birT.first + birT.last;
      final kap = _tamlar([_birlesim(kapali(A), kapali(B))]);
      final ac = _tamlar([_birlesim(acik(A), acik(B))]);
      return _tamD(
        '$veri A ∪ B kümesindeki en küçük tam sayı ile en büyük tam sayının '
            'toplamı kaçtır?',
        t,
        [
          kap.first + kap.last,
          if (ac.isNotEmpty) ac.first + ac.last,
          if (kesT.isNotEmpty) kesT.first + kesT.last,
          bir.$1 + bir.$3,
        ],
        'A ∪ B = ${_arYaz(bir)} olur. Bu aralıktaki en küçük tam sayı '
            '${_n(birT.first)}, en büyük tam sayı ${_n(birT.last)} olduğundan '
            'toplam ${_n(t)} bulunur.',
      );
    default:
      final simetrik = [...ab, ...ba]..sort((x, y) => x.$1.compareTo(y.$1));
      final t = _tamlar(simetrik);
      return _tamD(
        '$veri (A ∪ B) \\ (A ∩ B) kümesinde kaç tam sayı vardır?',
        t.length,
        [
          birT.length,
          kesT.length,
          abT.length + baT.length + 1,
          birT.length - kesT.length + 1,
          // Farklardan yalnız birini almak.
          abT.length,
          baT.length,
        ],
        '(A ∪ B) \\ (A ∩ B) = (A \\ B) ∪ (B \\ A) = ${_parcaYaz(simetrik)} olur. '
            'Bu kümedeki tam sayılar ${_tamListe(t..sort())}.',
        pozitif: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 8. Kartezyen çarpım
// ---------------------------------------------------------------------------

/// {1, …, 9} kümesinin üç ve dört elemanlı alt kümeleri (sözlük sırasıyla).
final List<List<int>> _kucukKumeler = [
  for (final k in const [3, 4])
    for (var m = 0; m < 512; m++)
      if (_bitSay(m) == k)
        [
          for (var t = 0; t < 9; t++)
            if (m >> t & 1 == 1) t + 1,
        ],
];

int _bitSay(int m) {
  var r = 0;
  for (var x = m; x > 0; x >>= 1) {
    r += x & 1;
  }
  return r;
}

String _kumeYaz(List<int> x) => '{${x.join(', ')}}';

int _ciftSay(List<int> a, List<int> b, bool Function(int, int) kosul) {
  var r = 0;
  for (final x in a) {
    for (final y in b) {
      if (kosul(x, y)) r++;
    }
  }
  return r;
}

/// Bir soru türü için uygun (A, B) ikilileri; liste boyunca yayılarak seçilir.
List<(List<int>, List<int>)> _kumeCiftleri(
  bool Function(List<int>, List<int>) uygun,
) {
  final k = _kucukKumeler;
  final r = <(List<int>, List<int>)>[];
  final n = k.length;
  final adim = _adimSec(n * n);
  for (var t = 0; t < n * n; t++) {
    final u = t * adim % (n * n);
    final a = k[u ~/ n], b = k[u % n];
    if (a != b && uygun(a, b)) r.add((a, b));
  }
  return r;
}

bool _bolerMi(int x, int y) => y % x == 0;

final _kartezyenCiftler = <int, List<(List<int>, List<int>)>>{};

List<(List<int>, List<int>)> _kartezyenListe(int c) =>
    _kartezyenCiftler.putIfAbsent(
      c,
      () => _kumeCiftleri((a, b) {
        final kume = a.toSet().intersection(b.toSet());
        final n = a.length * b.length;
        // Yanıt, kümelerde yazılı bir elemana eşit olmasın.
        bool yazili(int k) => a.contains(k) || b.contains(k);
        switch (c) {
          case 1:
            final k = _ciftSay(a, b, (x, y) => x < y);
            return k > 0 &&
                !yazili(k) &&
                k != _ciftSay(a, b, (x, y) => x <= y) &&
                k != _ciftSay(a, b, (x, y) => x > y) &&
                k != n - k;
          case 2:
            final k = _ciftSay(a, b, (x, y) => (x + y).isEven);
            return k > 0 &&
                !yazili(k) &&
                2 * k != n &&
                k != _ciftSay(a, b, (x, y) => x.isEven && y.isEven) &&
                k != _ciftSay(a, b, (x, y) => x.isOdd && y.isOdd);
          case 3:
            final k = _ciftSay(a, b, _bolerMi);
            return k > 1 &&
                !yazili(k) &&
                k != _ciftSay(a, b, (x, y) => _bolerMi(y, x)) &&
                a.contains(1) == false;
          case 4:
            // m = 1 ve m = 2 için m² sırasıyla m ve 2m değerine eşittir.
            return kume.length >= 3 && !yazili(kume.length * kume.length);
          case 5:
            final ab = a.length - kume.length, ba = b.length - kume.length;
            return ab > 1 &&
                ba > 1 &&
                kume.isNotEmpty &&
                ab * ba != ab + ba &&
                !yazili(ab * ba);
          case 6:
            final k = _ciftSay(a, b, (x, y) => x < y);
            return k >= 3 && k <= 11 && k != n && !yazili(_kuvvet(2, k));
          default:
            return true;
        }
      }),
    );

/// Toplamı k olan ikililer sorusu için (A, B, k) üçlüleri.
final List<(List<int>, List<int>, int)> _toplamUclu = () {
  final r = <(List<int>, List<int>, int)>[];
  for (final (a, b) in _kumeCiftleri((a, b) => true)) {
    final sayi = <int, int>{};
    for (final x in a) {
      for (final y in b) {
        sayi[x + y] = (sayi[x + y] ?? 0) + 1;
      }
    }
    // En sık toplamlardan biri seçilir; komşu toplamların sayısı farklı olsun.
    final adaylar =
        sayi.keys
            .where(
              (k) =>
                  sayi[k]! >= 2 &&
                  (sayi[k - 1] ?? 0) != sayi[k] &&
                  (sayi[k + 1] ?? 0) != sayi[k],
            )
            .toList()
          ..sort();
    final uygunlar = adaylar
        .where(
          (k) => !a.contains(sayi[k]) && !b.contains(sayi[k]) && sayi[k] != k,
        )
        .toList();
    if (uygunlar.isNotEmpty) {
      r.add((a, b, uygunlar[(a.first + b.last) % uygunlar.length]));
    }
    if (r.length >= 500) break;
  }
  return r;
}();

const _bolenSayilari = [
  12,
  18,
  20,
  24,
  28,
  30,
  36,
  40,
  42,
  45,
  48,
  50,
  54,
  60,
  63,
  64,
  72,
  75,
  80,
  84,
  90,
  96,
  98,
  100,
  108,
];

List<int> _bolenler(int n) => [
  for (var d = 1; d <= n; d++)
    if (n % d == 0) d,
];

AdvancedItem _kartezyenSoru(int a, int b, int c) =>
    _kokteOlmayan((v) => _kartezyenUret(a, b, c, v));

/// [v]: ikincil parametreleri değiştirir (yanıt kökte yazılıysa).
AdvancedItem _kartezyenUret(int a, int b, int c, int v) {
  final j = a + 25 * b;
  switch (c) {
    case 0:
      // A: tam sayı aralığı, B: doğal sayılar.
      final alt = a - 12 - 50 * (v ~/ 2), genislik = 3 + b % 5;
      final altDahil = (a + b).isEven != v.isOdd, ustDahil = b ~/ 5 % 2 == 0;
      final ust = alt + genislik;
      final r = 3 + b ~/ 10 * 2 + b % 2; // B'nin üst sınırı
      final bDahil = b ~/ 5 % 2 == 1;
      final sa = genislik - 1 + (altDahil ? 1 : 0) + (ustDahil ? 1 : 0);
      final sb = r + (bDahil ? 1 : 0); // 0 doğal sayıdır
      return _tamD(
        'A = {x | x tam sayı ve ${_n(alt)} ${altDahil ? '≤' : '<'} x '
            '${ustDahil ? '≤' : '<'} ${_n(ust)}} ve B = {y | y doğal sayı ve y '
            '${bDahil ? '≤' : '<'} $r} kümeleri veriliyor. A × B kümesinin eleman '
            'sayısı kaçtır?',
        sa * sb,
        [
          sa * (sb - 1),
          sa + sb,
          (sa + 1) * sb,
          (sa - 1) * sb,
          // Uç değerleri yanlış sayıp bir kümeye fazladan eleman katmak.
          sa * (sb + 1),
          (sa + 1) * (sb + 1),
        ],
        'A kümesinin $sa, B kümesinin $sb elemanı vardır (0 bir doğal sayıdır). '
            's(A × B) = s(A) · s(B) = $sa · $sb = ${sa * sb} olur.',
        pozitif: true,
      );
    case 7:
      // Sıralı ikili eşitliği: (p·x + q, y + s) = (u, r·y + t).
      final p = 2 + a % 4;
      final x0 = a ~/ 4 - 2 + (b % 3); // −2 … 6
      final x = x0 == 0
          ? 7
          : x0; // x = 0 için çarpım soruları kendiliğinden 0 olurdu
      final q = const [-5, -3, -1, 1, 3, 5, 7][b % 7];
      // y: 1 … 9; son varyantlarda 10 … 18 (kökte yazılı yanıtları önlemek için).
      final r = 2 + b % 3, y = 1 + b ~/ 3 + a % 3 + 9 * (v ~/ 4);
      final sSabit = const [4, -2, 6, 1, -4][(a + b) % 5] + 10 * (v ~/ 2);
      final t = sSabit - (r - 1) * y;
      final u = p * x + q;
      final toplamMi = (a + b).isEven != v.isOdd;
      final yanit = toplamMi ? x + y : x * y;
      String dog(int k, String v, int sabit) =>
          '${k == 1 ? '' : '$k'}$v${sabit == 0 ? '' : (sabit > 0 ? ' + $sabit' : ' − ${-sabit}')}';
      final xYanlis = (u + q) % p == 0 ? (u + q) ~/ p : x + 1;
      return _tamD(
        '(${dog(p, 'x', q)}, ${dog(1, 'y', sSabit)}) = (${_n(u)}, ${dog(r, 'y', t)}) '
            'sıralı ikilileri eşit olduğuna göre ${toplamMi ? 'x + y' : 'x · y'} kaçtır?',
        yanit,
        [
          toplamMi ? x - y : x + y,
          toplamMi ? xYanlis + y : xYanlis * y,
          toplamMi ? x - y + 2 * x : -yanit,
          toplamMi ? x + y + 1 : x * (y + 1),
        ],
        'Sıralı ikililerde karşılıklı bileşenler eşittir: ${dog(p, 'x', q)} = ${_n(u)} '
            'eşitliğinden x = ${_n(x)}, ${dog(1, 'y', sSabit)} = ${dog(r, 'y', t)} '
            'eşitliğinden y = $y bulunur. ${toplamMi ? 'x + y' : 'x · y'} = '
            '${_n(yanit)} olur.',
      );
    case 8:
      final (A, B, k) = _toplamUclu[j];
      final say = _ciftSay(A, B, (x, y) => x + y == k);
      final liste = [
        for (final x in A)
          for (final y in B)
            if (x + y == k) '($x, $y)',
      ];
      return _tamD(
        'A = ${_kumeYaz(A)} ve B = ${_kumeYaz(B)} kümeleri veriliyor. A × B '
            'kümesinin (x, y) elemanlarından kaç tanesinde x + y = $k olur?',
        say,
        [
          _ciftSay(A, B, (x, y) => x + y == k - 1),
          _ciftSay(A, B, (x, y) => x + y == k + 1),
          _ciftSay(A, B, (x, y) => x + y <= k),
        ],
        'Toplamı $k olan sıralı ikililer ${liste.join(', ')} olup $say tanedir.',
        // Yanıt çoğunlukla 2 olduğundan “hiçbiri” (0) de çeldirici olabilir.
        enAz: 0,
        enCok: A.length * B.length,
      );
    case 9:
      final n = _bolenSayilari[a];
      final ust = 10 + b * 3 + (a % 3) + 50 * v; // asal sayıların üst sınırı
      final asallar = [
        for (var x = 2; x < ust; x++)
          if (_asalCarpan(x).length == 1 && _asalCarpan(x).first.$2 == 1) x,
      ];
      final d = _bolenler(n).length;
      final pp = asallar.length;
      return _tamD(
        'A = {x | x, $n sayısının pozitif bölenidir} ve B = {y | y asal sayı ve '
            'y < $ust} kümeleri veriliyor. A × B kümesinin eleman sayısı kaçtır?',
        d * pp,
        [
          d + pp,
          (d - 2) * pp,
          d * (pp + 1),
          d * (pp - 1),
          // Pozitif bölenler yerine tam sayı bölenleri saymak.
          2 * d * pp,
        ],
        '$n sayısının pozitif bölenleri ${_bolenler(n).join(', ')} olup $d tanedir. '
            '$ust sayısından küçük asal sayılar ${asallar.join(', ')} olup $pp tanedir. '
            's(A × B) = $d · $pp = ${d * pp} olur.',
        pozitif: true,
      );
    default:
      break;
  }
  final liste = _kartezyenListe(c);
  final (A, B) = liste[j * liste.length ~/ 500];
  final veri = 'A = ${_kumeYaz(A)} ve B = ${_kumeYaz(B)} kümeleri veriliyor.';
  final n = A.length * B.length;
  switch (c) {
    case 1:
      final k = _ciftSay(A, B, (x, y) => x < y);
      return _tamD(
        '$veri A × B kümesinin (x, y) elemanlarından kaç tanesinde x < y olur?',
        k,
        [
          _ciftSay(A, B, (x, y) => x <= y),
          _ciftSay(A, B, (x, y) => x > y),
          n,
          // İkililerin yarısının koşulu sağladığını sanmak.
          ?_bol(n, 2),
        ],
        'A × B kümesinin $n elemanından x < y koşulunu sağlayanlar '
            '${[for (final x in A)
              for (final y in B)
                if (x < y) '($x, $y)'].join(', ')} '
            'olup $k tanedir.',
        pozitif: true,
        enCok: n,
      );
    case 2:
      final k = _ciftSay(A, B, (x, y) => (x + y).isEven);
      final tekA = A.where((x) => x.isOdd).length,
          tekB = B.where((x) => x.isOdd).length;
      final ciftA = A.length - tekA, ciftB = B.length - tekB;
      return _tamD(
        '$veri A × B kümesinin (x, y) elemanlarından kaç tanesinde x + y toplamı '
            'çift sayıdır?',
        k,
        [n - k, ciftA * ciftB, tekA * tekB, ?_bol(n, 2)],
        'Toplamın çift olması için x ile y aynı türden (ikisi de tek ya da ikisi '
            'de çift) olmalıdır: $tekA · $tekB + $ciftA · $ciftB = $k.',
        pozitif: true,
        enCok: n,
      );
    case 3:
      final k = _ciftSay(A, B, _bolerMi);
      final liste = [
        for (final x in A)
          for (final y in B)
            if (_bolerMi(x, y)) '($x, $y)',
      ];
      return _tamD(
        '$veri A × B kümesinin (x, y) elemanlarından kaç tanesinde x sayısı y '
            'sayısını tam böler?',
        k,
        [_ciftSay(A, B, (x, y) => _bolerMi(y, x)), k - 1, k + 1, n - k],
        'Koşulu sağlayan sıralı ikililer ${liste.join(', ')} olup $k tanedir.',
        pozitif: true,
        enCok: n,
      );
    case 4:
      final ortak = [
        for (final x in A)
          if (B.contains(x)) x,
      ];
      final m = ortak.length;
      return _tamD(
        '$veri (A × B) ∩ (B × A) kümesinin eleman sayısı kaçtır?',
        m * m,
        [m, 2 * m, n, 2 * m * m],
        '(A × B) ∩ (B × A) = (A ∩ B) × (A ∩ B) olur. A ∩ B = ${_kumeYaz(ortak)} '
            'kümesi $m elemanlı olduğundan sonuç $m · $m = ${m * m} bulunur.',
        pozitif: true,
        enCok: n,
      );
    case 5:
      final ab = [
        for (final x in A)
          if (!B.contains(x)) x,
      ];
      final ba = [
        for (final x in B)
          if (!A.contains(x)) x,
      ];
      return _tamD(
        '$veri (A \\ B) × (B \\ A) kümesinin eleman sayısı kaçtır?',
        ab.length * ba.length,
        [
          ab.length + ba.length,
          ab.length * B.length,
          A.length * ba.length,
          n,
          // Farklardan biri yerine kesişimi almak.
          A.where(B.contains).length * ba.length,
          ab.length * A.where(B.contains).length,
        ],
        'A \\ B = ${_kumeYaz(ab)} ve B \\ A = ${_kumeYaz(ba)} olduğundan eleman '
            'sayısı ${ab.length} · ${ba.length} = ${ab.length * ba.length} olur.',
        pozitif: true,
        enCok: n,
      );
    default:
      final k = _ciftSay(A, B, (x, y) => x < y);
      final t = _kuvvet(2, k);
      return _tamD(
        '$veri A × B kümesinin, her (x, y) elemanı için x < y koşulunu sağlayan '
            'kaç tane alt kümesi vardır?',
        t,
        [
          t - 1,
          k,
          _kuvvet(2, k + 1),
          2 * k,
          // x < y koşulunu x ≤ y ya da x ≥ y gibi okumak (yanıttan çok
          // büyük çıkan değerler alınmaz).
          for (final e in [_ciftSay(A, B, (x, y) => x <= y), n - k])
            if (e <= k + 4) _kuvvet(2, e),
        ],
        'x < y koşulunu sağlayan sıralı ikililerin sayısı $k olur. Bu $k '
            'ikiliden oluşan kümenin her alt kümesi istenen özelliktedir (boş küme '
            'dâhil); sayıları 2${_ust(k)} = $t bulunur.',
        pozitif: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 9. Fonksiyon sayısı
// ---------------------------------------------------------------------------

List<List<int>> _altKumeler(int n, int enAz, int enCok) => [
  for (var k = enAz; k <= enCok; k++)
    for (var m = 0; m < 1 << n; m++)
      if (_bitSay(m) == k)
        [
          for (var t = 0; t < n; t++)
            if (m >> t & 1 == 1) t + 1,
        ],
];

final _fonkA = _altKumeler(6, 2, 4);
final _fonkB = _altKumeler(8, 3, 6);

/// P(n, r) = n · (n − 1) · … · (n − r + 1).
int _permutasyon(int n, int r) {
  if (r < 0 || r > n) return 0;
  var t = 1;
  for (var k = 0; k < r; k++) {
    t *= n - k;
  }
  return t;
}

/// f(x) ≥ x koşulunda her x için seçenek sayıları.
List<int> _buyukEsit(List<int> a, List<int> b) => [
  for (final x in a) b.where((y) => y >= x).length,
];

/// Bire bir ve f(x) ≥ x: büyük x değerlerinden başlayarak seçim yapılır.
int _bireBirBuyuk(List<int> a, List<int> b) {
  final s = [...a]..sort((x, y) => y.compareTo(x));
  var t = 1;
  for (var k = 0; k < s.length; k++) {
    final secim = b.where((y) => y >= s[k]).length - k;
    if (secim <= 0) return 0;
    t *= secim;
  }
  return t;
}

/// Tipik yanlış: küçük x değerlerinden başlayıp her adımda bir eksiltmek.
int _bireBirYanlis(List<int> a, List<int> b) {
  final s = [...a]..sort();
  var t = 1;
  for (var k = 0; k < s.length; k++) {
    final secim = b.where((y) => y >= s[k]).length - k;
    if (secim <= 0) return 0;
    t *= secim;
  }
  return t;
}

int _ayniParite(List<int> a, List<int> b) =>
    _carp([for (final x in a) b.where((y) => (x + y).isEven).length]);

int _bireBirParite(List<int> a, List<int> b) {
  final tA = a.where((x) => x.isOdd).length,
      tB = b.where((y) => y.isOdd).length;
  return _permutasyon(tB, tA) * _permutasyon(b.length - tB, a.length - tA);
}

int _sabitDegil(List<int> a, List<int> b) =>
    _carp(_buyukEsit(a, b)) -
    b.where((y) => y >= a.reduce((p, q) => p > q ? p : q)).length;

/// Her soru türü için (doğru yanıt, çeldiriciler).
(int, List<int>) _fonksiyonDeger(int c, List<int> a, List<int> b) {
  final m = a.length, n = b.length;
  final hepsi = _kuvvet(n, m);
  final cift = b.where((y) => y.isEven).length, tek = n - cift;
  final ortak = a.where(b.contains).length;
  final esitDegil = _carp([for (final x in a) n - (b.contains(x) ? 1 : 0)]);
  final buyuk = _carp(_buyukEsit(a, b));
  // f(x) ≥ x koşulunda tipik yanlışlar: eşitliği unutmak (f(x) > x) ve
  // seçenek sayılarını çarpmak yerine toplamak.
  final kesin = _carp([for (final x in a) b.where((y) => y > x).length]);
  final toplamYanlis = _topla(_buyukEsit(a, b));
  switch (c) {
    case 0:
      return (
        buyuk,
        [
          hepsi,
          _carp([for (final x in a) b.where((y) => y > x).length]),
          _topla(_buyukEsit(a, b)),
          _carp([for (final x in a) b.where((y) => y <= x).length]),
        ],
      );
    case 1:
      return (esitDegil, [hepsi, _kuvvet(n - 1, m), hepsi - esitDegil]);
    case 2:
      return (
        _ayniParite(a, b),
        [
          hepsi,
          _carp([for (final x in a) b.where((y) => (x + y).isOdd).length]),
          _kuvvet(cift, m),
        ],
      );
    case 3:
      return (
        _bireBirBuyuk(a, b),
        [buyuk, _permutasyon(n, m), _bireBirYanlis(a, b), kesin, toplamYanlis],
      );
    case 4:
      final tA = a.where((x) => x.isOdd).length,
          tB = b.where((y) => y.isOdd).length;
      return (
        _bireBirParite(a, b),
        [
          _permutasyon(n, m),
          _ayniParite(a, b),
          _permutasyon(n, m) ~/ 2,
          // Yalnız tek ya da yalnız çift elemanların eşlenmesini saymak.
          _permutasyon(tB, tA),
          _permutasyon(n - tB, m - tA),
        ],
      );
    case 5:
      return (hepsi - esitDegil, [esitDegil, hepsi, ortak * _kuvvet(n, m - 1)]);
    case 6:
      return (
        cift * tek * _kuvvet(n, m - 2),
        [
          hepsi,
          cift * tek,
          cift * tek * _kuvvet(n, m - 1),
          // Çarpmak yerine toplamak; diğer elemanlara seçilen iki değeri
          // yeniden vermemek.
          cift + tek + (m - 2) * n,
          cift * tek * _kuvvet(n - 2, m - 2),
        ],
      );
    case 7:
      return (
        cift * _permutasyon(n - 1, m - 1),
        [
          _permutasyon(n, m),
          cift * _kuvvet(n, m - 1),
          cift * _permutasyon(n, m - 1),
          // f(x₁) için seçenek sayısıyla çarpmayı unutmak ya da toplamak.
          _permutasyon(n - 1, m - 1),
          cift + _permutasyon(n - 1, m - 1),
        ],
      );
    case 8:
      final sabit = b
          .where((y) => y >= a.reduce((p, q) => p > q ? p : q))
          .length;
      return (
        _sabitDegil(a, b),
        [
          buyuk,
          buyuk - n,
          buyuk - 1,
          hepsi - n + 0 * sabit,
          kesin - sabit,
          toplamYanlis,
          kesin,
        ],
      );
    default:
      final bb = _bireBirBuyuk(a, b);
      return (
        buyuk - bb,
        [
          buyuk,
          hepsi - _permutasyon(n, m),
          bb,
          kesin - bb,
          toplamYanlis,
          kesin,
        ],
      );
  }
}

bool _fonksiyonUygun(int c, List<int> a, List<int> b) {
  final m = a.length, n = b.length;
  if (c == 3 || c == 4 || c == 7 || c == 9) {
    if (n < m) return false;
  }
  if (c == 0 || c == 3 || c == 8 || c == 9) {
    if (_buyukEsit(a, b).any((k) => k == 0)) return false;
  }
  if (c == 6 && m < 3) return false;
  // Parite sorularında A kümesinde hem tek hem çift eleman bulunsun.
  if ((c == 2 || c == 4) &&
      (a.every((x) => x.isOdd) || a.every((x) => x.isEven))) {
    return false;
  }
  if ((c == 6 || c == 7) && b.where((y) => y.isEven).length < 2) return false;
  if (c == 6 && b.where((y) => y.isOdd).length < 2) return false;
  if (c == 5 && a.where(b.contains).length < 2) return false;
  if (c == 1 && (a.every((x) => !b.contains(x)) || a.every(b.contains))) {
    return false;
  }
  final (yanit, yanlis) = _fonksiyonDeger(c, a, b);
  // Yanıt 1 ya da kümelerde yazılı bir eleman olmasın.
  if (yanit <= 1 || a.contains(yanit) || b.contains(yanit)) return false;
  // Tipik bir yanlış yolun da doğru yanıtı verdiği kümeler atlanır.
  return !yanlis.contains(yanit) && yanit <= 4000;
}

final _fonksiyonCiftler = <int, List<(List<int>, List<int>)>>{};

List<(List<int>, List<int>)> _fonksiyonListe(int c) =>
    _fonksiyonCiftler.putIfAbsent(c, () {
      final r = <(List<int>, List<int>)>[];
      final na = _fonkA.length, nb = _fonkB.length;
      final adim = _adimSec(na * nb);
      for (var t = 0; t < na * nb; t++) {
        final u = t * adim % (na * nb);
        final a = _fonkA[u % na], b = _fonkB[u ~/ na];
        if (_fonksiyonUygun(c, a, b)) r.add((a, b));
      }
      return r;
    });

AdvancedItem _fonksiyonSayisiSoru(int a, int b, int c) {
  final liste = _fonksiyonListe(c);
  final (A, B) = liste[(a + 25 * b) * liste.length ~/ 500];
  final m = A.length, n = B.length;
  final (yanit, yanlis) = _fonksiyonDeger(c, A, B);
  final veri = 'A = ${_kumeYaz(A)} ve B = ${_kumeYaz(B)} kümeleri veriliyor.';
  final secim = _buyukEsit(A, B);
  final cift = B.where((y) => y.isEven).toList(),
      tek = B.where((y) => y.isOdd).toList();
  String carpimYaz(List<int> x) =>
      x.length == 1 ? '${x.first}' : '${x.join(' · ')} = ${_carp(x)}';
  late final String kok, aciklama;
  switch (c) {
    case 0:
      kok =
          '$veri f: A → B fonksiyonlarından kaç tanesi her x ∈ A için f(x) ≥ x '
          'koşulunu sağlar?';
      aciklama =
          '${[for (var k = 0; k < m; k++) 'f(${A[k]}) için ${secim[k]}'].join(', ')} '
          'seçenek vardır. Çarpma kuralına göre ${carpimYaz(secim)} fonksiyon bulunur.';
    case 1:
      final s = [for (final x in A) n - (B.contains(x) ? 1 : 0)];
      kok =
          '$veri f: A → B fonksiyonlarından kaç tanesi her x ∈ A için f(x) ≠ x '
          'koşulunu sağlar?';
      aciklama =
          'B kümesinde bulunan her x için f(x) değeri x dışındaki ${n - 1} '
          'elemandan, bulunmayanlar için $n elemandan seçilir: ${carpimYaz(s)}.';
    case 2:
      final s = [for (final x in A) B.where((y) => (x + y).isEven).length];
      kok =
          '$veri f: A → B fonksiyonlarından kaç tanesinde her x ∈ A için x + f(x) '
          'toplamı çift sayıdır?';
      aciklama =
          'x tek ise f(x) tek (${tek.length} seçenek), x çift ise f(x) çift '
          '(${cift.length} seçenek) olmalıdır: ${carpimYaz(s)}.';
    case 3:
      final sirali = [...A]..sort((x, y) => y.compareTo(x));
      final s = [
        for (var k = 0; k < m; k++) B.where((y) => y >= sirali[k]).length - k,
      ];
      kok =
          '$veri f: A → B bire bir fonksiyonlarından kaç tanesi her x ∈ A için '
          'f(x) ≥ x koşulunu sağlar?';
      aciklama =
          'Seçime en büyük elemandan başlanır: '
          '${[for (var k = 0; k < m; k++) 'f(${sirali[k]}) için ${s[k]}'].join(', ')} '
          'seçenek kalır (kullanılan değerler bir daha seçilemez). Sonuç ${carpimYaz(s)}.';
    case 4:
      final tA = A.where((x) => x.isOdd).length, cA = m - tA;
      kok =
          '$veri f: A → B bire bir fonksiyonlarından kaç tanesinde her x ∈ A için '
          'x + f(x) toplamı çift sayıdır?';
      aciklama =
          'A kümesindeki $tA tek eleman B kümesindeki ${tek.length} tek '
          'elemana, $cA çift eleman ${cift.length} çift elemana bire bir eşlenir: '
          'P(${tek.length}, $tA) · P(${cift.length}, $cA) = '
          '${_permutasyon(tek.length, tA)} · ${_permutasyon(cift.length, cA)} = $yanit.';
    case 5:
      final hepsi = _kuvvet(n, m);
      final s = [for (final x in A) n - (B.contains(x) ? 1 : 0)];
      kok =
          '$veri f: A → B fonksiyonlarından kaç tanesinde en az bir x ∈ A için '
          'f(x) = x olur?';
      aciklama =
          'Tüm fonksiyonlar $n${_ust(m)} = $hepsi tanedir. Hiçbir x için '
          'f(x) = x olmayanlar ${carpimYaz(s)} tanedir. Sonuç $hepsi − ${_carp(s)} = '
          '$yanit olur.';
    case 6:
      final x1 = A.first, x2 = A.last;
      kok =
          '$veri f: A → B fonksiyonlarından kaç tanesinde f($x1) çift sayı ve '
          'f($x2) tek sayıdır?';
      final digerleri = m - 2 == 1
          ? 'f(${A[1]}) için $n seçenek vardır'
          : 'diğer ${m - 2} elemanın her biri için $n seçenek vardır';
      aciklama =
          'f($x1) için ${cift.length}, f($x2) için ${tek.length}, $digerleri: '
          '${cift.length} · ${tek.length} · $n${m - 2 == 1 ? '' : _ust(m - 2)} = '
          '$yanit.';
    case 7:
      final x1 = A[(a + b) % m];
      kok =
          '$veri f: A → B bire bir fonksiyonlarından kaç tanesinde f($x1) çift '
          'sayıdır?';
      final kalanlar = m - 1 == 1
          ? 'kalan eleman, kalan ${n - 1} değerden biriyle eşlenir'
          : 'kalan ${m - 1} eleman kalan ${n - 1} değerle bire bir eşlenir';
      aciklama =
          'f($x1) değeri ${cift.length} çift sayıdan biri olur; $kalanlar: '
          '${cift.length} · P(${n - 1}, ${m - 1}) = ${cift.length} · '
          '${_permutasyon(n - 1, m - 1)} = $yanit.';
    case 8:
      final enBuyuk = A.reduce((p, q) => p > q ? p : q);
      final sabit = B.where((y) => y >= enBuyuk).length;
      kok =
          '$veri f: A → B fonksiyonlarından her x ∈ A için f(x) ≥ x koşulunu '
          'sağlayıp sabit olmayan kaç tane vardır?';
      aciklama =
          'Koşulu sağlayan fonksiyonlar ${carpimYaz(secim)} tanedir. Bunlardan '
          'sabit olanlar f(x) = k biçimindedir ve k ≥ $enBuyuk olmalıdır; B kümesinde '
          'bu koşulu sağlayan $sabit eleman bulunduğundan $sabit sabit fonksiyon '
          'vardır. Sonuç ${_carp(secim)} − $sabit = $yanit olur.';
    default:
      final bb = _bireBirBuyuk(A, B);
      kok =
          '$veri f: A → B fonksiyonlarından her x ∈ A için f(x) ≥ x koşulunu '
          'sağlayıp bire bir olmayan kaç tane vardır?';
      aciklama =
          'Koşulu sağlayan fonksiyonlar ${carpimYaz(secim)} tanedir. Bunların '
          'bire bir olanları büyük elemandan başlayarak sayılır ve $bb tanedir. '
          'Sonuç ${_carp(secim)} − $bb = $yanit olur.';
  }
  // Çeldirici, A → B fonksiyonlarının toplam sayısını (n^m) aşmaz.
  return _tamD(
    kok,
    yanit,
    yanlis,
    aciklama,
    pozitif: true,
    enCok: _kuvvet(n, m),
  );
}

// ---------------------------------------------------------------------------
// 10. f(ax + b) biçimindeki fonksiyonlar
// ---------------------------------------------------------------------------

/// Doğrusal ifade: `_dogrusal(3, -7)` → `3x − 7`, `_dogrusal(-1, 4)` → `−x + 4`.
String _dogrusal(int m, int n, [String v = 'x']) {
  final bas = m == 0
      ? ''
      : m == 1
      ? v
      : m == -1
      ? '−$v'
      : '${_n(m)}$v';
  if (bas.isEmpty) return _n(n);
  if (n == 0) return bas;
  return n > 0 ? '$bas + $n' : '$bas − ${-n}';
}

/// İkinci dereceden ifade: x² + bx + c.
String _ikinci(int a, int b, int c, [String v = 'x']) {
  final terimler = <String>[];
  void ekle(int k, String govde) {
    if (k == 0) return;
    final m = k.abs();
    final t = govde.isEmpty ? '$m' : (m == 1 ? govde : '$m$govde');
    if (terimler.isEmpty) {
      terimler.add(k < 0 ? '−$t' : t);
    } else {
      terimler.add(k < 0 ? '− $t' : '+ $t');
    }
  }

  ekle(a, '$v²');
  ekle(b, v);
  ekle(c, '');
  return terimler.isEmpty ? '0' : terimler.join(' ');
}

AdvancedItem _ifadeSecenek(
  String kok,
  String dogru,
  Iterable<String> yanlis,
  String aciklama,
) => secenekli(kok, dogru, yanlis, aciklama);

AdvancedItem _fonksiyonDegerSoru(int a, int b, int c) =>
    _kokteOlmayan((w) => _fonksiyonDegerUret(a, b, c, w));

/// [w]: ikincil bir parametreyi değiştirir (yanıt kökte yazılıysa).
AdvancedItem _fonksiyonDegerUret(int a, int b, int c, int w) {
  final p = const [2, 3, 4, 5, -2][a % 5];
  final q = const [-5, -3, -1, 2, 4][a ~/ 5];
  final ic = _dogrusal(p, q);
  switch (c) {
    case 0 || 6:
      final r0 = const [2, 3, 4, 5, -3, 6, -2, 7, 8, -4][b % 10];
      final sabit = const [3, -4][b ~/ 10] + (c == 6 ? 2 : 0);
      // Sağ taraf −(px + q) olursa f(u) = −u olur ve soru kendiliğinden çözülür;
      // bu durumda r listenin dışındaki bir değere kaydırılır.
      // c = 6'da r = p iken “iç ifadenin katsayısını kullanmak” yanlışı da doğru
      // sonucu verir; o durumda da r kaydırılır.
      final r = (r0 == -p && sabit == -q) || (c == 6 && r0 == p)
          ? r0 + (r0 > 0 ? 7 : -7)
          : r0;
      final dis = _dogrusal(r, sabit);
      // x0 değeri, doğru yanıt tipik yanlışlarla ve kökteki sayılarla
      // çakışmayacak biçimde seçilir.
      final x0 = _uygun(
        const [3, -2, 4, 5, -3, 6, 2, -4, 7, 8, -5, 9],
        (a + b) % 3 + w,
        (x) {
          final k = p * x + q, v = r * x + sabit;
          return x != k &&
              v != r * k + sabit &&
              !{p, q, r, sabit, k}.contains(v) &&
              v != x;
        },
      );
      final k = p * x0 + q, v = r * x0 + sabit;
      if (c == 0) {
        final yanlisX = (k + q) % p == 0 ? (k + q) ~/ p : x0 + 1;
        return _tam(
          'f($ic) = $dis olduğuna göre f(${_n(k)}) değeri kaçtır?',
          v,
          [r * k + sabit, r * yanlisX + sabit, x0, v + r],
          '$ic = ${_n(k)} eşitliğinden x = ${_n(x0)} bulunur. Bu değer verilen '
              'eşitlikte yerine yazılırsa f(${_n(k)}) = ${_n(r)} · ${_p(x0)} '
              '${sabit < 0 ? '−' : '+'} ${sabit.abs()} = ${_n(v)} olur.',
        );
      }
      return _tam(
        'f($ic) = $dis olduğuna göre f(t) = ${_n(v)} eşitliğini sağlayan t sayısı '
            'kaçtır?',
        k,
        [x0, r * x0 + q, p * v + q, k + p],
        '$dis = ${_n(v)} eşitliğinden x = ${_n(x0)} bulunur. Bu x değerinde '
            'fonksiyonun girdisi $ic = ${_n(k)} olduğundan t = ${_n(k)} olur.',
      );
    case 1:
      final r = const [2, -3, 4, -1, 5, -4, 1, -2, 3, -5][b % 10];
      final sabit = const [-6, 5][b ~/ 10];
      final kk = _uygun(
        const [
          2,
          5,
          -1,
          3,
          7,
          -2,
          4,
          6,
          -3,
          8,
          9,
          -4,
          10,
          -5,
          11,
          12,
          -6,
          13,
          -7,
          14,
          15,
          -8,
          16,
          17,
          -9,
          18,
        ],
        a % 5 + 5 * w,
        (k) {
          final x0 = k - q;
          final v = x0 * x0 + r * x0 + sabit;
          final dogrudan = k * k + r * k + sabit;
          return v != dogrudan && !{q, r, sabit, k}.contains(v) && x0 != 0;
        },
      );
      final x0 = kk - q;
      final v = x0 * x0 + r * x0 + sabit;
      final ters = kk + q;
      return _tam(
        'f(${_dogrusal(1, q)}) = ${_ikinci(1, r, sabit)} olduğuna göre f(${_n(kk)}) '
            'değeri kaçtır?',
        v,
        [kk * kk + r * kk + sabit, ters * ters + r * ters + sabit, x0, v + 1],
        '${_dogrusal(1, q)} = ${_n(kk)} için x = ${_n(x0)} olur. f(${_n(kk)}) = '
            '${_p(x0)}² ${r < 0 ? '−' : '+'} ${r.abs()} · ${_p(x0)} '
            '${sabit < 0 ? '−' : '+'} ${sabit.abs()} = ${_n(v)} bulunur.',
      );
    case 2:
      final m = const [2, 3, -2, 4, -3, 5, 1, -1, 6, -4][b % 10];
      final r = m * p;
      final s0 = const [7, -6][b ~/ 10] + a % 3;
      // m = ±1 iken n = 0 olursa f(x) = ±x olur (iki taraf aynı ifade); sabit
      // kaydırılır.
      final sabit = m.abs() == 1 && s0 == m * q ? s0 + 10 : s0;
      final n = sabit - m * q;
      return _ifadeSecenek(
        'f($ic) = ${_dogrusal(r, sabit)} olduğuna göre f(x) fonksiyonunun kuralı '
            'nedir?',
        _dogrusal(m, n),
        [
          _dogrusal(m, sabit + m * q),
          _dogrusal(r, sabit - r * q),
          _dogrusal(m, sabit),
          _dogrusal(m, n + m),
          _dogrusal(m, n + 1),
          _dogrusal(-m, n),
        ],
        '$ic = t denirse x = (t ${q < 0 ? '+' : '−'} ${q.abs()}) / ${_p(p)} olur. '
            'f(t) = ${_n(r)} · (t ${q < 0 ? '+' : '−'} ${q.abs()}) / ${_p(p)} '
            '${sabit < 0 ? '−' : '+'} ${sabit.abs()} = ${_dogrusal(m, n, 't')} bulunur; '
            'buna göre f(x) = ${_dogrusal(m, n)} olur.',
      );
    case 3:
      final m = const [2, 3, -2, 4, -3, 5, -1, 6, -4, 7][b % 10];
      final n = const [5, -4][b ~/ 10] + a % 5 - 2;
      final x1 = 1 + a ~/ 5, x2 = x1 + 2 + a % 2;
      final y1 = m * x1 + n, y2 = m * x2 + n;
      final k = _uygun(const [-2, 6, 7, -3, 8, 9, -1, 10, 11], b % 3 + w, (x) {
        final v = m * x + n;
        return x != x1 && x != x2 && x != 0 && !{x1, x2, y1, y2, x}.contains(v);
      });
      final v = m * k + n;
      return _tam(
        'f(x) = ax + b doğrusal fonksiyonu için f($x1) = ${_n(y1)} ve '
            'f($x2) = ${_n(y2)} olduğuna göre f(${_n(k)}) değeri kaçtır?',
        v,
        [m * k, ?_bol(y1 * k, x1), m * k + n + m, -v],
        '${_n(y2)} − ${_p(y1)} = a · ($x2 − $x1) eşitliğinden a = ${_n(m)}, '
            'f($x1) = ${_n(y1)} eşitliğinden b = ${_n(n)} bulunur. f(${_n(k)}) = '
            '${_n(m)} · ${_p(k)} ${n < 0 ? '−' : '+'} ${n.abs()} = ${_n(v)} olur.',
      );
    case 4:
      final r = const [2, 3, -2, 4, 5, -3, 6, -4, 7, 8][b % 10];
      final sabit = const [-3, 5][b ~/ 10];
      final pp = 2 + a % 5;
      final qq = const [1, 3, -2, 5, -4][a ~/ 5];
      final kk = _uygun(const [3, -1, 4, 2, 5, -2, 6, 7], a % 3 + w, (k) {
        final x0 = pp * k - qq, v = r * x0 + sabit;
        return v != r * k + sabit &&
            !{pp, qq, r, sabit, k}.contains(v) &&
            x0 != 0;
      });
      final x0 = pp * kk - qq, v = r * x0 + sabit;
      final payYazi = _dogrusal(1, qq);
      return _tam(
        'f(($payYazi) / $pp) = ${_dogrusal(r, sabit)} olduğuna göre f(${_n(kk)}) '
            'değeri kaçtır?',
        v,
        [r * kk + sabit, r * (pp * kk + qq) + sabit, x0, r * pp * kk + sabit],
        '($payYazi) / $pp = ${_n(kk)} eşitliğinden x = $pp · ${_p(kk)} '
            '${qq < 0 ? '+' : '−'} ${qq.abs()} = ${_n(x0)} bulunur. f(${_n(kk)}) = '
            '${_n(r)} · ${_p(x0)} ${sabit < 0 ? '−' : '+'} ${sabit.abs()} = ${_n(v)} olur.',
      );
    case 5:
      final m = const [3, -2, 4, 5, -3, 2, 6, -4, 7, -5][b % 10];
      final n = const [-4, 6][b ~/ 10] + a % 3 - 1;
      final sonuc = _dogrusal(m * p, m * q + n);
      return _ifadeSecenek(
        'f(x) = ${_dogrusal(m, n)} olduğuna göre f($ic) ifadesi nedir?',
        sonuc,
        [
          _dogrusal(m * p, q + n),
          _dogrusal(p * m, p * n + q),
          _dogrusal(m * p, m * q),
          _dogrusal(m + p, n + q),
          _dogrusal(m * p, m * q + n + 1),
          _dogrusal(m * p, -(m * q + n)),
        ],
        'f(x) kuralında x yerine $ic yazılır: f($ic) = ${_n(m)} · ($ic) '
            '${n < 0 ? '−' : '+'} ${n.abs()} = $sonuc olur.',
      );
    case 7:
      final r0 = const [2, -4, 6, -2, 4, -6, 8, 0, 3, -3][b % 10];
      final sabit = const [5, -3][b ~/ 10] + a % 5;
      final qq = q;
      // r = q iken “sabit terimi değiştirmemek” yanlışı doğru sonucu verir; r
      // listenin dışına kaydırılır.
      final r = r0 == qq ? r0 + (r0 > 0 ? 10 : -10) : r0;
      // f(x) = (x − q)² + r(x − q) + s
      final bb = r - 2 * qq, cc = qq * qq - r * qq + sabit;
      return _ifadeSecenek(
        'f(${_dogrusal(1, qq)}) = ${_ikinci(1, r, sabit)} olduğuna göre f(x) '
            'fonksiyonunun kuralı nedir?',
        _ikinci(1, bb, cc),
        [
          _ikinci(1, r + 2 * qq, qq * qq + r * qq + sabit),
          _ikinci(1, r, cc),
          _ikinci(1, bb, sabit),
          _ikinci(1, r - qq, cc),
          _ikinci(1, bb, cc + 1),
          _ikinci(1, -bb, cc),
        ],
        '${_dogrusal(1, qq)} = t denirse x = ${_dogrusal(1, -qq, 't')} olur. '
            'f(t) = (${_dogrusal(1, -qq, 't')})² '
            '${r == 0 ? '' : '${r < 0 ? '−' : '+'} ${r.abs()} · (${_dogrusal(1, -qq, 't')}) '}'
            '${sabit < 0 ? '−' : '+'} ${sabit.abs()} = ${_ikinci(1, bb, cc, 't')} bulunur; '
            'f(x) = ${_ikinci(1, bb, cc)} olur.',
      );
    case 8:
      final m = const [2, 3, -2, 4, -3, 5, -4, 6, 7, -5][b % 10];
      final r = m * p;
      final sabit = const [4, -5][b ~/ 10] + a % 3;
      final n = sabit - m * q; // f(x) = mx + n
      final t = const [3, -2, 4, -3, 5][(a + b) % 5];
      final sonuc = _dogrusal(m, m * t + n);
      return _ifadeSecenek(
        'f($ic) = ${_dogrusal(r, sabit)} olduğuna göre f(${_dogrusal(1, t)}) '
            'ifadesi nedir?',
        sonuc,
        [
          _dogrusal(m, n + t),
          _dogrusal(m, n),
          _dogrusal(r, r * t + sabit),
          _dogrusal(m, m * t + sabit),
          _dogrusal(m, m * t + n + 1),
          _dogrusal(-m, m * t + n),
        ],
        'Önce f(x) bulunur: $ic = u denirse f(u) = ${_dogrusal(m, n, 'u')}, yani '
            'f(x) = ${_dogrusal(m, n)} olur. Buna göre f(${_dogrusal(1, t)}) = '
            '${_n(m)} · (${_dogrusal(1, t)}) ${n < 0 ? '−' : '+'} ${n.abs()} = $sonuc bulunur.',
      );
    default:
      final m = const [2, 3, 4, 5, 6, -2, -3, 7, -4, 8][b % 10];
      final n = const [4, -3, 5, -6, 7][a % 5] + (b ~/ 10) * 9 + 40 * (w ~/ 3);
      final h = 1 + (a ~/ 5 + w) % 3; // f(x + h) − f(x − h) = 2mh
      final k = const [3, -2, 5, 4, -3][a ~/ 5];
      final v = m * k + n;
      return _tam(
        'f(x) doğrusal bir fonksiyondur. Her x için f(x + $h) − f(x − $h) = '
            '${_n(2 * m * h)} ve f(0) = ${_n(n)} olduğuna göre f(${_n(k)}) değeri '
            'kaçtır?',
        v,
        [2 * m * h * k + n, if (h > 1) m * h * k + n, m * k, v + m, m * k - n],
        'f(x) = ax + b olsun. f(x + $h) − f(x − $h) = ${2 * h}a = ${_n(2 * m * h)} '
            'eşitliğinden a = ${_n(m)}, f(0) = b = ${_n(n)} bulunur. f(${_n(k)}) = '
            '${_n(m)} · ${_p(k)} ${n < 0 ? '−' : '+'} ${n.abs()} = ${_n(v)} olur.',
      );
  }
}

// ---------------------------------------------------------------------------
// 11. Çarpanlara ayırma ve özdeşliklerle sayısal hesap
// ---------------------------------------------------------------------------

AdvancedItem _carpanlaraAyirmaSoru(int a, int b, int c) {
  switch (c) {
    case 0:
      // m² − n² = (m − n)(m + n); toplam ve fark yuvarlak sayılardır.
      final top = 60 + 10 * a, fark = 2 + 2 * b;
      final m = (top + fark) ~/ 2, n = (top - fark) ~/ 2;
      return _tamD(
        '$m² − $n² işleminin sonucu kaçtır?',
        top * fark,
        // Yanıt yuvarlak bir sayı olduğundan çeldiricilerin bir kısmı da
        // yuvarlaktır: m + n toplamını 10 eksik ya da fazla bulmak, sonucu
        // ikiye bölmek. Son yanlış: işareti karıştırıp m² + n² hesaplamak.
        [
          top * fark ~/ 2,
          (top + 10) * fark,
          fark * fark,
          (top - 10) * fark,
          top + fark,
          m * m + n * n,
        ],
        'İki kare farkı özdeşliğine göre $m² − $n² = ($m − $n) · ($m + $n) = '
            '$fark · $top = ${top * fark} olur.',
        pozitif: true,
        komsuAdim: top, // m − n farkını yanlış bulmak: (m + n) · (fark ± 1)
      );
    case 1:
      final m = 31 + 2 * a, n = 11 + b;
      return _tamD(
        '($m² − $n²) / ($m − $n) işleminin sonucu kaçtır?',
        m + n,
        [m - n, 2 * m, 2 * n, m + n + 2],
        '$m² − $n² = ($m − $n) · ($m + $n) olduğundan pay ve payda ${m - n} ile '
            'sadeleşir; sonuç $m + $n = ${m + n} olur.',
        pozitif: true,
      );
    case 2 || 3:
      // (m ± n)² tam kare özdeşliği; m ± n onun katıdır.
      final topla = c == 2;
      final n = 1 + b;
      final t = topla ? 5 + a : 2 + a;
      final m = topla ? 10 * t - n : 10 * t + n;
      final k = 10 * t;
      final isaret = topla ? '+' : '−';
      return _tamD(
        '$m² $isaret 2 · $m · $n + $n² işleminin sonucu kaçtır?',
        k * k,
        [
          // Yanıt yuvarlak bir sayının karesi olduğundan çeldiricilerin bir
          // kısmı da öyledir: m ± n değerini 10 eksik ya da fazla bulmak.
          (k - 10) * (k - 10),
          // Ortadaki 2mn terimini unutmak.
          m * m + n * n,
          // Kare almak yerine 2 ile çarpmak.
          2 * k,
          (k + 10) * (k + 10),
          // Ortadaki terimin 2 katsayısını unutmak: m² ± mn + n².
          m * m + (topla ? 1 : -1) * m * n + n * n,
          topla ? (m - n) * (m - n) : (m + n) * (m + n),
          // 2 katsayısını ikinci terime yazmak: (m ± 2n)².
          (topla ? m + 2 * n : m - 2 * n) * (topla ? m + 2 * n : m - 2 * n),
        ],
        '$m² $isaret 2 · $m · $n + $n² = ($m $isaret $n)² = $k² = ${k * k} olur.',
        pozitif: true,
        komsuAdim: 100,
      );
    case 4:
      final k = 13 + 2 * a, x = 11 + 4 * b, y = 100 - x;
      return _tamD(
        '$k · $x + $k · $y işleminin sonucu kaçtır?',
        100 * k,
        // Yanıt yuvarlak olduğundan çeldiricilerin bir kısmı da yuvarlaktır:
        // ortak çarpanı bir eksik almak, bir sıfır eksik ya da fazla yazmak.
        [
          k * x + y,
          2 * k * 100,
          100 * (k - 1),
          10 * k,
          1000 * k,
          k + 100,
          k * (x - y),
        ],
        'Ortak çarpan $k parantezine alınır: $k · ($x + $y) = $k · 100 = ${100 * k}.',
        pozitif: true,
        komsuAdim: 100,
      );
    case 5:
      final k = 14 + 2 * a, x = 52 + 2 * b, f = 10 * (1 + b % 3), y = x - f;
      return _tamD(
        '$k · $x − $k · $y işleminin sonucu kaçtır?',
        k * f,
        [
          k * x - y,
          // x − y farkını 10 eksik ya da fazla bulmak.
          k * (f + 10),
          k * (x + y),
          k * (f - 10),
          f,
          k * f + k,
        ],
        'Ortak çarpan $k parantezine alınır: $k · ($x − $y) = $k · $f = ${k * f}.',
        pozitif: true,
        komsuAdim: 10,
      );
    case 6:
      final top = 7 + a, fark = 2 + b;
      return _tamD(
        'x + y = $top ve x − y = $fark olduğuna göre x² − y² ifadesinin değeri '
            'kaçtır?',
        top * fark,
        [top + fark, top * top - fark * fark, fark * fark, top * top],
        'x² − y² = (x − y) · (x + y) = $fark · $top = ${top * fark} olur.',
        pozitif: true,
      );
    case 7:
      // x² − y² = P ve x − y = D verilir; x istenir.
      final fark = 1 + b % 10;
      final top = fark + 2 * (2 + a) + 2 * (b ~/ 10) * 25;
      final P = top * fark, x = (top + fark) ~/ 2, y = (top - fark) ~/ 2;
      return _tamD(
        'x ve y pozitif tam sayılar olmak üzere x² − y² = $P ve x − y = $fark '
            'olduğuna göre x kaçtır?',
        x,
        [
          top,
          y,
          ?_bol(P, 2),
          x + fark,
          // x + y toplamının yarısını x sanmak.
          ?_bol(top, 2),
        ],
        'x² − y² = (x − y) · (x + y) olduğundan x + y = $P / $fark = $top olur. '
            'x + y = $top ve x − y = $fark eşitlikleri taraf tarafa toplanırsa '
            '2x = ${top + fark}, x = $x bulunur.',
        pozitif: true,
      );
    case 8:
      final m = 21 + 2 * a, n = 3 + b;
      return _tamD(
        '($m + $n)² − ($m − $n)² işleminin sonucu kaçtır?',
        4 * m * n,
        [
          2 * m * n,
          4 * n * n,
          (2 * n) * (2 * n) + 2 * m * n,
          m * n,
          // Kareleri çıkarmak yerine toplamak: 2m² + 2n².
          2 * (m * m + n * n),
        ],
        '(x + y)² − (x − y)² = 4xy özdeşliğine göre sonuç 4 · $m · $n = '
            '${4 * m * n} olur.',
        pozitif: true,
      );
    default:
      // Gruplandırma: p·r + p·s + q·r + q·s = (p + q)(r + s).
      final t1 = const [50, 100][b ~/ 10], t2 = const [20, 30, 40][a % 3];
      final pp = 11 + a + (t1 == 100 ? 20 : 0), q = t1 - pp;
      final r = 3 + b % 10 + (t2 == 40 ? 5 : 0), sx = t2 - r;
      return _tamD(
        '$pp · $r + $pp · $sx + $q · $r + $q · $sx işleminin sonucu kaçtır?',
        t1 * t2,
        [
          pp * r + q * sx,
          // r + s toplamını 10 eksik ya da fazla bulmak.
          t1 * (t2 + 10),
          (pp + r) * (q + sx),
          t1 * (t2 - 10),
          t1 + t2,
          t1 * t2 ~/ 2,
        ],
        'Gruplandırma yapılır: $pp · ($r + $sx) + $q · ($r + $sx) = ($pp + $q) · '
            '($r + $sx) = $t1 · $t2 = ${t1 * t2}.',
        pozitif: true,
        komsuAdim: 10 * t1,
      );
  }
}

// ---------------------------------------------------------------------------
// 12. Rasyonel ifadeler
// ---------------------------------------------------------------------------

/// Doğrusal çarpan yazımı: (x − 3), (x + 2), x.
String _carpanX(int r) => r == 0 ? 'x' : '(${_dogrusal(1, -r)})';

/// (x − r1)(x − r2) çarpımının açılımı.
String _ikiKok(int r1, int r2) => _ikinci(1, -(r1 + r2), r1 * r2);

const _ortakKokler = [
  3,
  -2,
  4,
  -3,
  5,
  2,
  -4,
  6,
  -5,
  1,
  -1,
  7,
  -6,
  8,
  -7,
  9,
  -8,
  10,
  -9,
  11,
  12,
  -10,
  13,
  -11,
  14,
];

/// Dört sadeleşme kalıbı ve genel kalıp için rasyonel ifade soruları.
/// tür 0: (x² − r²)/((x − r)(x − q)), 1: ((x − r)(x − p))/(x² − r²),
/// 2: (x − r)²/((x − r)(x − q)), 3: k(x − r)/((x − r)(x − q)),
/// 4: ((x − r)(x − p))/((x − r)(x − q)).
AdvancedItem _rasyonelSoru(int a, int b, int c) {
  final r = _ortakKokler[a];
  final tur = c % 5, deger = c >= 5;
  final adaylar = [for (var x = -15; x <= 15; x++) x];
  // Kalan kök(ler): ortak kökten, onun ters işaretlisinden ve birbirinden
  // farklıdır; böylece başka bir çarpan sadeleşmez. Değer sorularında yanıtı
  // kökte yazılı bir sayıya eşit çıkan kökler de atlanır.
  bool uygun(int x) => x != r && x != -r;
  final kay = deger ? 7 : 0;
  final sira = (b + kay) % 20;
  if (tur == 4) {
    final ikililer = [
      for (final x in adaylar)
        for (final y in adaylar)
          if (uygun(x) && uygun(y) && x != y && x != -y) (x, y),
    ];
    final bas = (sira * 37 + a * 11) % ikililer.length;
    for (var d = 0; d < ikililer.length; d++) {
      final (x, y) = ikililer[(bas + d * 97) % ikililer.length];
      final soru = _rasyonelUret(a, b, c, r, x, y);
      if (!deger || !_yanitKokte(soru)) return soru;
    }
    final (x, y) = ikililer[bas];
    return _rasyonelUret(a, b, c, r, x, y);
  }
  AdvancedItem uret(int x) => switch (tur) {
    0 => _rasyonelUret(a, b, c, r, -r, x),
    1 => _rasyonelUret(a, b, c, r, x, -r),
    _ => _rasyonelUret(a, b, c, r, r, x),
  };
  final uygunlar = [
    for (final x in adaylar)
      if (uygun(x) && (!deger || !_yanitKokte(uret(x)))) x,
  ];
  return uret(uygunlar[sira % uygunlar.length]);
}

/// Ortak kök [r]; sadeleşmiş ifade (x − pk)/(x − qk) (tür 3: k/(x − qk)).
AdvancedItem _rasyonelUret(int a, int b, int c, int r, int pk, int qk) {
  final tur = c % 5, deger = c >= 5;
  final k = tur == 3 ? 2 + (a + b) % 4 : 1;
  final (String pay, String payAyrim) = switch (tur) {
    0 => (_ikinci(1, 0, -r * r), '${_carpanX(r)}${_carpanX(-r)}'),
    2 => (_ikinci(1, -2 * r, r * r), '${_carpanX(r)}²'),
    3 => (_dogrusal(k, -k * r), '$k${_carpanX(r)}'),
    _ => (_ikiKok(r, pk), '${_carpanX(r)}${_carpanX(pk)}'),
  };
  final (String payda, String paydaAyrim) = tur == 1
      ? (_ikinci(1, 0, -r * r), '${_carpanX(r)}${_carpanX(-r)}')
      : (_ikiKok(r, qk), '${_carpanX(r)}${_carpanX(qk)}');
  final ifade = '($pay) / ($payda)';
  final ust = tur == 3 ? '$k' : _carpanX(pk);
  final dogruYazi = '$ust / ${_carpanX(qk)}';
  final adim =
      'Pay $payAyrim, payda $paydaAyrim biçiminde çarpanlarına ayrılır; '
      'ortak ${_carpanX(r)} çarpanı sadeleşir.';
  if (!deger) {
    final yanlis = tur == 3
        ? [
            '$k / ${_carpanX(-qk)}',
            '1 / ${_carpanX(qk)}',
            '${_carpanX(qk)} / $k',
            '$k / ${_carpanX(r)}',
            '$k${_carpanX(r)} / ${_carpanX(qk)}',
          ]
        : [
            '${_carpanX(-pk)} / ${_carpanX(qk)}',
            '$ust / ${_carpanX(-qk)}',
            '${_carpanX(qk)} / $ust',
            '${_carpanX(-pk)} / ${_carpanX(-qk)}',
            '${_carpanX(r)} / ${_carpanX(qk)}',
            '$ust / ${_carpanX(r)}',
          ];
    return secenekli(
      'Paydayı sıfır yapmayan x gerçek sayıları için $ifade ifadesinin en sade '
          'biçimi nedir?',
      dogruYazi,
      yanlis,
      '$adim En sade biçim $dogruYazi olur.',
    );
  }
  // Değer sorusu: x0, ilk ifadenin tanımlı olduğu ve köklerden uzak bir
  // sayıdır (sadeleşmiş ifadenin payı ya da paydası 100 ya da 50 olur).
  // Doğrudan yerine koymak uzun sürdüğünden sadeleştirmek beklenir. İlk
  // ifadeyi tanımsız yapan x = r (sadeleşen çarpanın kökü) sorulmaz.
  final dayanak = tur == 3 ? [r] : [qk, pk];
  final secenek = [
    for (final u in const [100, 50, 20, 10])
      for (final t in dayanak) t + u,
  ];
  final bas0 = (a + 2 * b + c) % (2 * dayanak.length);
  final x0 = _uygun(
    [...secenek.sublist(bas0), ...secenek.sublist(0, bas0)],
    0,
    (x) => x != r && x != -r && x != pk && x != qk && 2 * x != pk + qk,
  );
  final n = tur == 3 ? k : x0 - pk, d = x0 - qk;
  final (hn, hd) = d < 0 ? (-n, -d) : (n, d);
  final ham = '${_n(hn)}/$hd';
  return _kes(
    '$ifade ifadesinin x = ${_n(x0)} için değeri kaçtır?',
    n,
    d,
    [
      // Çarpanlarda işaret hatası.
      if (tur != 3 && x0 + pk != 0) (x0 + pk, d),
      if (x0 + qk != 0) (n, x0 + qk),
      // x² − r² ifadesini (x − r)² sanmak (tür 0 payda, tür 1 paydada).
      if (tur == 0) (x0 - r, d),
      if (tur == 1) (n, x0 - r),
      // Kareyi tümüyle sadeleştirmek (tür 2) ya da katsayıyı unutmak (tür 3).
      if (tur == 2 || tur == 3) (1, d),
      if (n != 0) (d, n),
      (-n, d),
    ],
    '$adim x = ${_n(x0)} paydayı sıfır yapmadığından sadeleşmiş ifade '
        '$dogruYazi kullanılır: ${tur == 3 ? '$k' : _sayiYerine(x0, pk)} / '
        '${_sayiYerine(x0, qk)} = $ham${_q(n, d) == ham ? '' : ' = ${_q(n, d)}'} '
        'bulunur.',
  );
}

/// (x − r) çarpanında x yerine değer yazımı: `(4 − 3)`, `(−2 + 5)`, `4`.
String _sayiYerine(int x, int kok) =>
    kok == 0 ? _p(x) : '(${_n(x)} ${kok < 0 ? '+' : '−'} ${kok.abs()})';

// ---------------------------------------------------------------------------
// 13. Polinom eşitliği ve çarpım polinomunun katsayıları
// ---------------------------------------------------------------------------

/// Katsayıları büyük dereceden küçüğe verilen polinomun yazımı.
String _polinom(List<int> k, [String v = 'x']) {
  final terimler = <String>[];
  final n = k.length - 1;
  for (var i = 0; i <= n; i++) {
    final c = k[i];
    if (c == 0) continue;
    final d = n - i, m = c.abs();
    final govde = d == 0
        ? '$m'
        : '${m == 1 ? '' : m}$v${d == 1 ? '' : _ust(d)}';
    if (terimler.isEmpty) {
      terimler.add(c < 0 ? '−$govde' : govde);
    } else {
      terimler.add(c < 0 ? '− $govde' : '+ $govde');
    }
  }
  return terimler.isEmpty ? '0' : terimler.join(' ');
}

/// Polinom çarpımı (katsayılar büyük dereceden küçüğe).
List<int> _polCarp(List<int> x, List<int> y) {
  final r = List.filled(x.length + y.length - 1, 0);
  for (var i = 0; i < x.length; i++) {
    for (var j = 0; j < y.length; j++) {
      r[i + j] += x[i] * y[j];
    }
  }
  return r;
}

/// xᵏ teriminin katsayısı.
int _katsayiAl(List<int> p, int derece) {
  final i = p.length - 1 - derece;
  return i < 0 || i >= p.length ? 0 : p[i];
}

/// kx tek terimlisi: `_xTek(1)` → `x`, `_xTek(-1)` → `−x`, `_xTek(-3)` → `−3x`.
String _xTek(int k) => k == 1 ? 'x' : (k == -1 ? '−x' : '${_n(k)}x');

/// Çarpımın ikinci çarpanı olarak tek terimli; negatifse parantez içinde.
String _pxTek(int k) => k < 0 ? '(${_xTek(k)})' : _xTek(k);

String _terimAdi(int d) => d == 0
    ? 'sabit terimi'
    : (d == 1 ? 'x teriminin katsayısı' : 'x${_ust(d)} teriminin katsayısı');

AdvancedItem _polinomEsitlikSoru(int a, int b, int c) =>
    _kokteOlmayan((w) => _polinomEsitlikUret(a, b, c, w));

/// [w]: ikincil bir parametreyi değiştirir (yanıt kökte yazılıysa).
AdvancedItem _polinomEsitlikUret(int a, int b, int c, int w) {
  switch (c) {
    case 0:
      final p = 1 + a % 5, q = 2 + a ~/ 5;
      final A = 2 + b % 5, B = const [-7, 4, -3, 6][b ~/ 5];
      final r = _uygun(
        const [3, -2, 5, -4, 1, 6, -1],
        (a + b) % 4 + w % 3,
        (x) => p - q + x != 0,
      );
      final C = const [5, -8, 9, -6][(a + 2 * b + w ~/ 3) % 4];
      final m = A + p, n = B - q, k = C + r;
      return _tamD(
        '(m − $p)x² + (n + $q)x + k ${r < 0 ? '+' : '−'} ${r.abs()} = '
            '${_polinom([A, B, C])} eşitliği her x gerçek sayısı için sağlandığına '
            'göre m + n + k toplamı kaçtır?',
        m + n + k,
        [A + B + C, A + B + C - p + q - r, m + n - k, m + n + k + 2 * q],
        'Özdeş polinomlarda aynı dereceli terimlerin katsayıları eşittir: '
            'm − $p = $A, n + $q = ${_n(B)}, k ${r < 0 ? '+' : '−'} ${r.abs()} = '
            '${_n(C)}. Buradan m = $m, n = ${_n(n)}, k = ${_n(k)} ve toplam '
            '${_n(m + n + k)} olur.',
      );
    case 1:
      final p = const [2, 3, 4, 5, -2][a % 5],
          q = const [-3, 7, -1, -4, -5][a ~/ 5];
      final r = const [4, -3, 2, -5, 6][b % 5],
          sv = const [-1, 7, -6, 3][b ~/ 5] + 10 * (w ~/ 2);
      final carpim = _polCarp([p, q], [1, r, sv]);
      final d = (a + b).isEven != w.isOdd ? 2 : 1;
      final yanit = _katsayiAl(carpim, d);
      return _tamD(
        '(${_polinom([p, q])}) · (${_polinom([1, r, sv])}) çarpımının ${_terimAdi(d)} '
        'kaçtır?',
        yanit,
        d == 2
            ? [p * r, p * r - q, q * r + p, p + r]
            : [q * r, p * sv, p * sv - q * r, q + sv],
        d == 2
            ? 'x² terimi ${_xTek(p)} · ${_pxTek(r)} ve ${_n(q)} · x² çarpımlarından '
                  'gelir: ${_n(p * r)} ${q < 0 ? '−' : '+'} ${q.abs()} = ${_n(yanit)}.'
            : 'x terimi ${_xTek(p)} · ${_p(sv)} ve ${_n(q)} · ${_pxTek(r)} '
                  'çarpımlarından gelir: ${_n(p * sv)} ${q * r < 0 ? '−' : '+'} '
                  '${(q * r).abs()} = ${_n(yanit)}.',
      );
    case 2:
      // p = 1 alınmaz: (x + 1)(mx + n) açılımında m + n doğrudan x katsayısıdır.
      final p = const [2, 3, -2, 4, -3, 5, -4, 7, -5, 6][b % 10];
      // n = −1 alınmaz: m · n = −m baş katsayı olarak kökte yazılı olurdu.
      final m = 2 + a % 5,
          n = const [-5, 3, -4, 7, 8][a ~/ 5] + (b ~/ 10) * 9 + 40 * (w ~/ 2);
      final toplam = (a + b).isEven != w.isOdd;
      final kat = _polCarp([1, p], [m, n]);
      return _tamD(
        '(${_polinom([1, p])}) · (mx + n) = ${_polinom(kat)} eşitliği her x için '
            'doğru olduğuna göre m ${toplam ? '+' : '·'} n değeri kaçtır?',
        toplam ? m + n : m * n,
        toplam
            ? [m - n, kat[1], m * n, m + kat[2]]
            : [m + n, kat[1] * m, -m * n, m * kat[2]],
        'x² katsayılarından m = $m, sabit terimlerden ${_n(p)} · n = ${_n(kat[2])}, '
            'yani n = ${_n(n)} bulunur. Sonuç '
            '${toplam ? '$m + ${_p(n)} = ${_n(m + n)}' : '$m · ${_p(n)} = ${_n(m * n)}'} olur.',
      );
    default:
      break;
  }
  // Diğer türler aşağıda.
  return _polinomEsitlikSoru2(a, b, c, w);
}

AdvancedItem _polinomEsitlikSoru2(int a, int b, int c, int w) {
  switch (c) {
    case 3:
      // r1 + r2 = 0 olmasın: o zaman x² katsayısı −r3 olur ve kökte yazılıdır.
      final r1 = const [1, 2, -1, 3, -2][a % 5],
          r2 = const [4, -6, 5, -4, 6][a ~/ 5];
      final r3 = _uygun(
        const [
          -5,
          6,
          -6,
          7,
          3,
          -7,
          8,
          -8,
          9,
          1,
          -9,
          10,
          11,
          -10,
          12,
          -11,
          13,
          -12,
          14,
          -13,
          15,
          -14,
          16,
          -15,
          17,
          -16,
          18,
          -17,
          19,
          -18,
          20,
          -19,
        ],
        b % 10 + 10 * (w % 3),
        (x) => x != r1 && x != r2,
      );
      final d = b < 10 ? 1 : 2;
      final carpim = _polCarp(_polCarp([1, -r1], [1, -r2]), [1, -r3]);
      final yanit = _katsayiAl(carpim, d);
      final ikiliToplam = r1 * r2 + r1 * r3 + r2 * r3;
      return _tamD(
        '${_carpanX(r1)} · ${_carpanX(r2)} · ${_carpanX(r3)} çarpımının '
            '${_terimAdi(d)} kaçtır?',
        yanit,
        d == 1
            ? [-ikiliToplam, r1 + r2 + r3, r1 * r2 * r3]
            : [r1 + r2 + r3, ikiliToplam, -(r1 * r2 * r3)],
        'Çarpım ${_polinom(carpim)} olur. Bu açılımda ${_terimAdi(d)} ${_n(yanit)} '
            'bulunur.',
      );
    case 4:
      // (x² + mx + p)(x + q) çarpımında x teriminin katsayısı K → m.
      final p = const [2, -3, 4, -5, 1][a % 5],
          q = const [-3, 2, -4, 5, -2][a ~/ 5];
      final m =
          const [3, -2, 5, -4, 1, -5, 6, 2, -6, 7][b % 10] +
          (b ~/ 10) * 20 +
          40 * w;
      final K = m * q + p;
      return _tamD(
        '(x² + mx ${p < 0 ? '−' : '+'} ${p.abs()}) · (${_polinom([1, q])}) çarpımında '
            'x teriminin katsayısı ${_n(K)} olduğuna göre m kaçtır?',
        m,
        [?_bol(K, q), ?_bol(K + p, q), -m, m + 1],
        'x terimi mx · ${_p(q)} ve ${_n(p)} · x çarpımlarından gelir: '
            '${_n(q)}m ${p < 0 ? '−' : '+'} ${p.abs()} = ${_n(K)} eşitliğinden m = ${_n(m)} '
            'bulunur.',
      );
    case 5:
      // Tam kare özdeşliği; v bilinmeyen katsayının yerini seçer.
      final k = 1 + a % 5, v = a ~/ 5, n = (v == 4 ? 2 + b : 1 + b) + 25 * w;
      final A = k * k, B = 2 * k * n, C = n * n;
      final kx = k == 1 ? 'x' : '${k}x';
      switch (v) {
        case 0 || 1 || 4:
          final eksi = v == 1;
          final sonuc = v == 4 ? C * n : C + n;
          return _tamD(
            '${A == 1 ? '' : '$A'}x² ${eksi ? '−' : '+'} ${B}x + m = ($kx ${eksi ? '−' : '+'} n)² '
                'eşitliği her x için doğru olduğuna göre m ${v == 4 ? '·' : '+'} n '
                'değeri kaçtır?',
            sonuc,
            v == 4 ? [C + n, B * n, C * C] : [2 * C, C - n, B + n],
            '($kx ${eksi ? '−' : '+'} n)² = ${A == 1 ? '' : '$A'}x² ${eksi ? '−' : '+'} ${2 * k}nx + n² '
                'olduğundan ${2 * k}n = $B, n = $n ve m = n² = $C bulunur. Sonuç '
                '${v == 4 ? '$C · $n' : '$C + $n'} = $sonuc olur.',
            pozitif: true,
          );
        case 2:
          return _tamD(
            'n > 0 olmak üzere ${A == 1 ? '' : '$A'}x² + mx + $C = ($kx + n)² eşitliği her '
                'x için doğru olduğuna göre m + n değeri kaçtır?',
            B + n,
            [B, k * n + n, B + C],
            '($kx + n)² = ${A == 1 ? '' : '$A'}x² + ${2 * k}nx + n² olduğundan n² = $C, '
                'n > 0 için n = $n olur. m = ${2 * k}n = $B ve m + n = ${B + n} bulunur.',
            pozitif: true,
          );
        default:
          return _tamD(
            'k > 0 olmak üzere mx² + ${B}x + $C = (kx + $n)² eşitliği her x için '
                'doğru olduğuna göre m + k değeri kaçtır?',
            A + k,
            [A, B ~/ n + A, k + C],
            '(kx + $n)² = k²x² + ${2 * n}kx + $C olduğundan ${2 * n}k = $B, k = $k '
                've m = k² = $A bulunur. m + k = ${A + k} olur.',
            pozitif: true,
          );
      }
    case 6:
      // a(x − p) + b(x + q) = Ax + B. n = −1 alınmaz: p = m olduğunda m · n = −p
      // kökte yazılı olurdu.
      final u = 2 + a % 5, v = const [3, -8, 4, 5, -7][a ~/ 5];
      final p = 1 + b % 5, q = 2 + b ~/ 5 + 4 * w;
      final A = u + v, B = -u * p + v * q;
      return _tamD(
        'm(x − $p) + n(x + $q) = ${_polinom([A, B])} eşitliği her x için doğru '
            'olduğuna göre m · n çarpımı kaçtır?',
        u * v,
        [u + v, -u * v, ?_bol(B, A)],
        'x katsayıları: m + n = ${_n(A)}; sabit terimler: ${p == 1 ? '−' : '−$p'}m + '
            '${q}n = ${_n(B)}. '
            'Bu sistemden m = $u, n = ${_n(v)} bulunur; m · n = ${_n(u * v)} olur.',
      );
    case 7:
      final p = const [2, -3, 1, 4, -2][a % 5],
          q = const [-1, -3, -4, 2, 4][a ~/ 5];
      final r = const [3, -1, -2, 4, 5][b % 5],
          sv = const [2, -5, 6, -3][b ~/ 5] + 10 * (w ~/ 2);
      final carpim = _polCarp([1, p, q], [1, r, sv]);
      final d = (a + b).isEven != w.isOdd ? 2 : 1;
      final yanit = _katsayiAl(carpim, d);
      return _tamD(
        '(${_polinom([1, p, q])}) · (${_polinom([1, r, sv])}) çarpımının '
        '${_terimAdi(d)} kaçtır?',
        yanit,
        d == 2 ? [q + sv, p * r, q * sv] : [p * sv, q * r, p + r],
        d == 2
            ? 'x² terimi x² · ${_p(sv)}, ${_xTek(p)} · ${_pxTek(r)} ve ${_n(q)} · x² '
                  'çarpımlarından gelir: ${_n(sv)} ${p * r < 0 ? '−' : '+'} ${(p * r).abs()} '
                  '${q < 0 ? '−' : '+'} ${q.abs()} = ${_n(yanit)}.'
            : 'x terimi ${_xTek(p)} · ${_p(sv)} ve ${_n(q)} · ${_pxTek(r)} '
                  'çarpımlarından gelir: ${_n(p * sv)} ${q * r < 0 ? '−' : '+'} '
                  '${(q * r).abs()} = ${_n(yanit)}.',
      );
    case 8:
      final m = 11 + a;
      final nn = const [
        1,
        -2,
        2,
        -1,
        3,
        -3,
        4,
        -4,
        5,
        -5,
        6,
        -6,
        7,
        -7,
        8,
        -8,
        9,
        -9,
        10,
        -10,
      ][b];
      final A = m + nn, B = m - nn;
      return _tamD(
        '(m + n)x + m − n = ${_polinom([A, B])} eşitliği her x için doğru olduğuna '
            'göre m · n çarpımı kaçtır?',
        m * nn,
        [A * B, m + nn, -m * nn, m * nn + 1],
        'm + n = ${_n(A)} ve m − n = ${_n(B)} olur. Taraf tarafa toplanırsa 2m = '
            '${_n(A + B)}, m = $m; buradan n = ${_n(nn)} ve m · n = ${_n(m * nn)} '
            'bulunur.',
      );
    default:
      final p = const [2, 3, -2, 4, 5][a % 5],
          q = const [-1, 4, -3, 2, -5][a ~/ 5];
      final r = const [3, -2, 5, -4][b % 4],
          sv = const [5, -3, 4, -2, 6][b ~/ 4];
      final carpim = _polCarp([p, q, r], [1, sv]);
      // (x + 1) çarpanı kullanılmaz: o zaman katsayılar kökteki sayıların toplamı
      // ya da kendisi olurdu.
      final d = (a + b + w) % 3;
      final yanit = _katsayiAl(carpim, d);
      return _tamD(
        '(${_polinom([p, q, r])}) · (${_polinom([1, sv])}) çarpımının ${_terimAdi(d)} '
            'kaçtır?',
        yanit,
        switch (d) {
          0 => [r + sv, r, sv],
          1 => [q * sv, r, q + r * sv + 1],
          _ => [q, p * sv, q * sv + p],
        },
        'Çarpım ${_polinom(carpim)} olur; ${_terimAdi(d)} ${_n(yanit)} bulunur.',
      );
  }
}

// ---------------------------------------------------------------------------
// 14. Polinom bölmesi
// ---------------------------------------------------------------------------

/// Polinom bölmesi: bölünen ve bölen katsayıları (büyük dereceden küçüğe);
/// bölen baş katsayısı 1 olmalıdır. (bölüm, kalan) döner.
(List<int>, List<int>) _polBol(List<int> bolunen, List<int> bolen) {
  final r = [...bolunen];
  final d = bolen.length - 1;
  final bolum = <int>[];
  for (var i = 0; i + d < r.length; i++) {
    final k = r[i];
    bolum.add(k);
    for (var j = 0; j <= d; j++) {
      r[i + j] -= k * bolen[j];
    }
  }
  return (bolum, r.sublist(r.length - d));
}

int _polDeger(List<int> p, int x) => p.fold(0, (t, c) => t * x + c);

List<int> _polTopla(List<int> x, List<int> y) {
  final n = x.length > y.length ? x.length : y.length;
  final xx = [...List.filled(n - x.length, 0), ...x];
  final yy = [...List.filled(n - y.length, 0), ...y];
  return [for (var i = 0; i < n; i++) xx[i] + yy[i]];
}

AdvancedItem _polinomBolmeSoru(int a, int b, int c) =>
    _kokteOlmayan((w) => _polinomBolmeUret(a, b, c, w));

/// [w]: kalan gibi ikincil bir parametreyi değiştirir (yanıt kökte yazılıysa).
AdvancedItem _polinomBolmeUret(int a, int b, int c, int w) {
  final q2 = const [1, 2, 3, -1, -2][a % 5];
  final q1 = const [-3, 2, -1, 4, 1][a ~/ 5];
  final q0 = const [5, -4, 3, -2, 6, -5, 1, -6, 4, 2][b % 10] + 20 * (w ~/ 3);
  final sinif = c.isEven ? const [2, -1] : const [3, -2];
  final k0 = sinif[b ~/ 10], kDiger = sinif[1 - b ~/ 10];
  // Bazı bölenlerde yanlış yollar doğru sonucu verir: c = 1'de x + k ile bölmek
  // (q1 = (k − 1)·q2 iken) ya da P'nin x katsayısını okumak (q2 = −(k + 1)·q1
  // iken), c = 2'de x + k ile bölmek (q1 = k·q2 iken), c = 8'de −k ile çarpmayı
  // unutmak (k = −1 iken). Bu durumlarda başka bir bölen alınır.
  bool cakisir(int k) => switch (c) {
    1 => q1 == (k - 1) * q2 || q2 == -(k + 1) * q1,
    2 => q1 == k * q2,
    _ => false,
  };
  final k = c == 8 && k0 == -1
      ? 3
      : (!cakisir(k0) ? k0 : (!cakisir(kDiger) ? kDiger : 2));
  final R = const [3, -4, 5, -2, 7, -1, 4][(a + b + c + w) % 7];
  final Q = [q2, q1, q0];
  final P = _polTopla(_polCarp(Q, [1, -k]), [R]);
  final bolen = _polinom([1, -k]);
  final pYazi = _polinom(P);
  // Bölen x + k sanılarak yapılan bölme (işaret hatası).
  final (yanlisQ, _) = _polBol(P, [1, k]);
  final sentetik =
      'Bölme sonucunda bölüm ${_polinom(Q)}, kalan ${_n(R)} bulunur; gerçekten '
      '($bolen) · (${_polinom(Q)}) ${R < 0 ? '−' : '+'} ${R.abs()} = $pYazi olur.';
  switch (c) {
    case 0:
      return secenekli(
        'P(x) = $pYazi polinomunun $bolen ile bölümünden elde edilen bölüm nedir?',
        _polinom(Q),
        [
          _polinom(yanlisQ),
          _polinom([q2, q1, q0 + R]),
          _polinom([q2, -q1, q0]),
          _polinom([q2, q1, -q0]),
          _polinom([q2, q1 + 1, q0]),
        ],
        sentetik,
      );
    case 1:
      final t = q2 + q1 + q0;
      return _tam(
        'P(x) = $pYazi polinomunun $bolen ile bölümünden elde edilen bölümün '
            'katsayılar toplamı kaçtır?',
        t,
        [_polDeger(P, 1), _topla(yanlisQ), t + R, R],
        '$sentetik Bölümün katsayılar toplamı ${_n(q2)} ${q1 < 0 ? '−' : '+'} '
            '${q1.abs()} ${q0 < 0 ? '−' : '+'} ${q0.abs()} = ${_n(t)} olur.',
      );
    case 2:
      return _tam(
        'P(x) = $pYazi polinomunun $bolen ile bölümünden elde edilen bölümün sabit '
            'terimi kaçtır?',
        q0,
        [P.last, yanlisQ.last, R, -q0],
        '$sentetik Bölümün sabit terimi ${_n(q0)} olur.',
      );
    case 7:
      final t = const [2, -1, 3, -2, 1][(a + 2 * b + w ~/ 2) % 5];
      final v = _polDeger(Q, t);
      return _tam(
        'P(x) = $pYazi polinomunun $bolen ile bölümünden elde edilen bölüm Q(x) '
            'olduğuna göre Q(${_n(t)}) değeri kaçtır?',
        v,
        [_polDeger(P, t), _polDeger(yanlisQ, t), v + R],
        '$sentetik Q(${_n(t)}) = ${_n(v)} olur.',
      );
    case 8:
      final sabit = -k * q0 + R;
      return _tam(
        'Bir P(x) polinomunun $bolen ile bölümünden elde edilen bölüm '
            '${_polinom(Q)}, kalan ${_n(R)} olduğuna göre P(x) polinomunun sabit '
            'terimi kaçtır?',
        sabit,
        [q0 + R, k * q0 + R, -k * q0, q0 * R],
        'Bölme özdeşliğine göre P(x) = ($bolen) · (${_polinom(Q)}) '
            '${R < 0 ? '−' : '+'} ${R.abs()} olur. Sabit terim ${_p(-k)} · ${_p(q0)} '
            '${R < 0 ? '−' : '+'} ${R.abs()} = ${_n(sabit)} bulunur.',
      );
    default:
      break;
  }
  // İkinci dereceden bölenler.
  final d1 = const [-1, 2, -3, 1, 0][a % 5];
  final d0Taban = const [1, -2, 3, 2, -3][a ~/ 5];
  // c = 6'da D(1) = 1 iken “D(1) ile çarpmayı unutmak”, D(1) = 0 iken “D(1)
  // eklemek” yanlışları doğru sonucu verir; bu durumda sabit terim 3 artırılır.
  final d0 = c == 6 && (1 + d1 + d0Taban == 0 || 1 + d1 + d0Taban == 1)
      ? d0Taban + 3
      : d0Taban;
  final D = [1, d1, d0];
  // İşaret hatası: x katsayısı 0 ise sabit terimin işareti ters alınır.
  final yanlisBolen = d1 == 0 ? [1, 0, -d0] : [1, -d1, d0];
  final dYazi = _polinom(D);
  // c = 6'da D(1) · T(1) = −r1 ise yanıt kalanın sabit terimine eşit olur;
  // bu yüzden ikinci varyant r1'i de kaydırır.
  final r1Taban = const [2, -3, 1, 4, -1, 3, -2, 5, -4, 6][b % 10];
  final r1 = r1Taban + (c == 6 ? r1Taban.sign * 10 * (w ~/ 2) : 0);
  final r0Taban = const [-5, 4][b ~/ 10] + c + 20 * (w % 2);
  // c = 6'da R(1) = 0 iken “kalanı eklemeyi unutmak” yanlışı doğru sonucu verir.
  final r0 = c == 6 && r1 + r0Taban == 0 ? r0Taban + 40 : r0Taban;
  final kalanYazi = _dogrusal(r1, r0);
  switch (c) {
    case 3 || 4:
      final m1 = const [2, 1, 3, -1, -2][(a + b) % 5],
          m0 = const [3, -1, 4, -2, 1][(a + 2 * b) % 5];
      final T = [m1, m0];
      final p3 = _polTopla(_polCarp(D, T), [r1, r0]);
      final (yanlisB, yanlisK) = _polBol(p3, yanlisBolen);
      final aciklama =
          'Bölme sonucunda bölüm ${_polinom(T)}, kalan $kalanYazi bulunur; gerçekten '
          '($dYazi) · (${_polinom(T)}) + ($kalanYazi) = ${_polinom(p3)} olur.';
      if (c == 3) {
        return secenekli(
          'P(x) = ${_polinom(p3)} polinomunun $dYazi ile bölümünden kalan nedir?',
          kalanYazi,
          [
            _polinom(yanlisK),
            _dogrusal(r1, -r0),
            _dogrusal(-r1, r0),
            _dogrusal(r0, r1),
            _dogrusal(r1, r0 + d0),
          ],
          aciklama,
        );
      }
      return secenekli(
        'P(x) = ${_polinom(p3)} polinomunun $dYazi ile bölümünden elde edilen bölüm '
        'nedir?',
        _polinom(T),
        [
          // x katsayısı 0 iken işaret hatası bölümü değiştirmez.
          if (d1 != 0) _polinom(yanlisB),
          _dogrusal(m1, -m0),
          _dogrusal(m1, m0 + 1),
          _dogrusal(-m1, m0),
          _dogrusal(m1, m0 - 1),
        ],
        aciklama,
      );
    case 5:
      final T = [q2, q1, q0];
      final p4 = _polTopla(_polCarp(D, T), [r1, r0]);
      final (yanlisB, _) = _polBol(p4, yanlisBolen);
      return secenekli(
        'P(x) = ${_polinom(p4)} polinomunun $dYazi ile bölümünden elde edilen bölüm '
            'nedir?',
        _polinom(T),
        [
          _polinom(yanlisB),
          _polinom([q2, -q1, q0]),
          _polinom([q2, q1, q0 + 1]),
          _polinom([q2, q1, -q0]),
          if (d1 != 0) _polinom([q2, q1 + d1, q0]),
        ],
        'Bölme sonucunda bölüm ${_polinom(T)}, kalan $kalanYazi bulunur; gerçekten '
            '($dYazi) · (${_polinom(T)}) + ($kalanYazi) = ${_polinom(p4)} olur.',
      );
    case 6:
      // T(1) = 0 iken P(1) kalanın değerine eşit olur ve birçok yanlış yol doğru
      // sonucu verir; bölümün sabit terimi kaydırılır.
      final T = [q2, q2 + q1 == 0 ? q1 + 10 : q1];
      final top = _polDeger(T, 1) * _polDeger(D, 1) + (r1 + r0);
      return _tam(
        'Bir P(x) polinomunun $dYazi ile bölümünden elde edilen bölüm '
            '${_polinom(T)}, kalan $kalanYazi olduğuna göre P(x) polinomunun '
            'katsayılar toplamı kaçtır?',
        top,
        [
          _polDeger(T, 1) + r1 + r0,
          _polDeger(T, 1) * _polDeger(D, 1),
          _polDeger(T, 1) * (r1 + r0),
          top + _polDeger(D, 1),
        ],
        'P(x) = ($dYazi) · (${_polinom(T)}) + ($kalanYazi) olur. Katsayılar toplamı '
            'P(1) = ${_n(_polDeger(D, 1))} · ${_p(_polDeger(T, 1))} + ${_p(r1 + r0)} = '
            '${_n(top)} bulunur.',
      );
    default:
      // P = (x − k)Q + r1k, Q = (x − m)T + S ⇒ P'nin (x − k)(x − m) ile
      // bölümünden kalan S(x − k) + r1k.
      final k = const [2, -1, 3, -2, 1][a % 5];
      final m = const [-3, 4, -4, 5, 6][a ~/ 5];
      final r1k = const [3, -4, 5, -2, 7, -1, 4, -5, 6, 1][b % 10];
      final S = const [2, -3][b ~/ 10];
      final bolen = _polinom([1, -k]);
      final kalan = _dogrusal(S, r1k - S * k);
      return secenekli(
        'Bir P(x) polinomunun $bolen ile bölümünden elde edilen bölüm Q(x), kalan '
            '${_n(r1k)} olarak bulunuyor. Q(x) polinomunun ${_polinom([1, -m])} ile '
            'bölümünden kalan ${_n(S)} olduğuna göre P(x) polinomunun '
            '(${_polinom(_polCarp([1, -k], [1, -m]))}) ile bölümünden kalan nedir?',
        kalan,
        [
          _dogrusal(S, r1k + S * k),
          _dogrusal(r1k, S),
          _dogrusal(S, r1k - S * m),
          _dogrusal(S, r1k),
          _dogrusal(r1k, S - r1k * k),
          _dogrusal(S, r1k - S * k + 1),
          _dogrusal(-S, r1k - S * k),
        ],
        'Q(x) = (${_polinom([1, -m])}) · T(x) ${S < 0 ? '−' : '+'} ${S.abs()} yazılırsa '
            'P(x) = ($bolen) · (${_polinom([1, -m])}) · T(x) ${S < 0 ? '−' : '+'} '
            '${S.abs()} · ($bolen) ${r1k < 0 ? '−' : '+'} ${r1k.abs()} olur. Kalan '
            '${_n(S)} · ($bolen) ${r1k < 0 ? '−' : '+'} ${r1k.abs()} = $kalan bulunur.',
      );
  }
}

// ---------------------------------------------------------------------------
// 15. İkinci dereceden denklemin kökleri
// ---------------------------------------------------------------------------

/// c·√n sadeleştirmesi: (katsayı, kök içi).
(int, int) _kokSade(int n) {
  var k = 1, m = n;
  for (var t = 2; t * t <= m; t++) {
    while (m % (t * t) == 0) {
      m ~/= t * t;
      k *= t;
    }
  }
  return (k, m);
}

String _kokYaz(int k, int m) => m == 1 ? '$k' : (k == 1 ? '√$m' : '$k√$m');

/// p ± k√m yazımı.
String _surd(int p, int k, int m, bool arti) {
  final kok = _kokYaz(k, m);
  if (p == 0) return arti ? kok : '−$kok';
  return '${_n(p)} ${arti ? '+' : '−'} $kok';
}

const _tamOlmayan = [
  2,
  3,
  5,
  6,
  7,
  8,
  10,
  11,
  12,
  13,
  14,
  15,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  26,
  27,
  28,
  29,
  30,
];

AdvancedItem _ikinciDereceSoru(int a, int b, int c) =>
    _kokteOlmayan((w) => _ikinciDereceUret(a, b, c, w));

/// [w]: ikincil bir parametreyi değiştirir (yanıt kökte yazılıysa).
AdvancedItem _ikinciDereceUret(int a, int b, int c, int w) {
  switch (c) {
    case 0 || 1 || 9:
      // Büyük kök −6 … 18; 0 yerine 19 alınır (0, kökteki “= 0” ile karışmasın).
      // Küçük kökün sorulduğu c = 1 için büyük kök ±1 olursa sabit terim küçük
      // kökün mutlak değeri olur; orada −1 ve 1 yerine −7 ve −8 alınır.
      final r1Taban = c == 1 && (a == 5 || a == 7)
          ? (a == 5 ? -7 : -8)
          : (a == 6 ? 19 : -6 + a);
      final r1 = r1Taban + 30 * (w ~/ 2);
      final r2 = r1 - 1 - b - 25 * (w % 2); // küçük kök
      final denklem = '${_polinom([1, -(r1 + r2), r1 * r2])} = 0';
      final ayrim = '${_carpanX(r1)}${_carpanX(r2)} = 0';
      if (c == 9) {
        final v = 2 * r1 - r2;
        return _tam(
          '$denklem denkleminin kökleri x₁ ve x₂ olmak üzere x₁ > x₂ olduğuna göre '
              '2x₁ − x₂ değeri kaçtır?',
          v,
          [2 * r2 - r1, 2 * r1 + r2, r1 - r2, -v],
          'Denklem $ayrim biçiminde çarpanlarına ayrılır; kökler ${_n(r1)} ve '
              '${_n(r2)} olur. x₁ = ${_n(r1)}, x₂ = ${_n(r2)} için 2x₁ − x₂ = '
              '2 · ${_p(r1)} − ${_p(r2)} = ${_n(v)} bulunur.',
        );
      }
      final buyuk = c == 0;
      return _tam(
        '$denklem denkleminin ${buyuk ? 'büyük' : 'küçük'} kökü kaçtır?',
        buyuk ? r1 : r2,
        buyuk ? [r2, -r1, -r2, r1 + r2] : [r1, -r2, -r1, r1 * r2],
        'Denklem $ayrim biçiminde çarpanlarına ayrılır; kökler ${_n(r1)} ve '
            '${_n(r2)} olur. ${buyuk ? 'Büyük' : 'Küçük'} kök ${_n(buyuk ? r1 : r2)} bulunur.',
      );
    case 2 || 3 || 8:
      // (p·x − m)(x − n) = 0; kökler m/p ve n. n = p olduğunda büyük kök baş
      // katsayıyla aynı çıkar; ikinci varyant baş katsayıyı 7 … 11 aralığına taşır.
      final pk = const [2, 3, 4, 5, 6][a % 5] + 5 * (w ~/ 2);
      final m = _uygun(
        const [1, -1, 3, -3, 5, -5, 7, -7, 2, -2, 9, -9, 11, -11, 13, -13, 17],
        a ~/ 5 + (c == 8 ? 3 : 5 * (w % 2)),
        (x) => x.gcd(pk) == 1,
      );
      final n = const [
        1,
        -2,
        3,
        -4,
        2,
        -1,
        4,
        -3,
        5,
        -5,
        6,
        -6,
        7,
        -7,
        8,
        -8,
        9,
        -9,
        10,
        -10,
      ][b];
      final denklem = '${_polinom(_polCarp([pk, -m], [1, -n]))} = 0';
      final ayrim = '(${_polinom([pk, -m])}) · ${_carpanX(n)} = 0';
      final k1 = (m, pk), k2 = (n, 1);
      final buyukMu = m * 1 > n * pk; // m/p > n
      final (bn, bd) = buyukMu ? k1 : k2;
      final (kn, kd) = buyukMu ? k2 : k1;
      final kokler = 'kökler ${_q(m, pk)} ve ${_n(n)} olur';
      if (c == 8) {
        final kume = '{${_q(kn, kd)}, ${_q(bn, bd)}}';
        return secenekli(
          '$denklem denkleminin çözüm kümesi nedir?',
          kume,
          [
            '{${_q(-kn, kd)}, ${_q(-bn, bd)}}',
            '{${_q(kd * kn.sign, kn.abs())}, ${_q(bn, bd)}}'.replaceAll(
              '{0,',
              '{0,',
            ),
            '{${_q(kn, kd)}, ${_q(-bn, bd)}}',
            '{${_q(-kn, kd)}, ${_q(bn, bd)}}',
            '{${_q(m, 1)}, ${_q(n, 1)}}',
          ],
          'Denklem $ayrim biçiminde çarpanlarına ayrılır; $kokler. Çözüm kümesi '
              '$kume bulunur.',
        );
      }
      if (c == 2) {
        return _kes(
          '$denklem denkleminin büyük kökü kaçtır?',
          bn,
          bd,
          [(kn, kd), (-bn, bd), (-kn, kd), (pk * m, 1)],
          'Denklem $ayrim biçiminde çarpanlarına ayrılır; $kokler. Büyük kök '
              '${_q(bn, bd)} bulunur.',
        );
      }
      // kökler farkı (büyük − küçük)
      final fn = bn * kd - kn * bd, fd = bd * kd;
      return _kes(
        '$denklem denkleminin büyük kökü ile küçük kökü arasındaki fark kaçtır?',
        fn,
        fd,
        [(bn * kd + kn * bd, fd), (m - n, 1), (fn, fd * pk)],
        'Denklem $ayrim biçiminde çarpanlarına ayrılır; $kokler. Fark '
            '${_q(bn, bd)} − ${_sar(_q(kn, kd))} = ${_q(fn, fd)} bulunur.',
        pozitif: true,
      );
    case 4 || 5:
      // x² − 2px + (p² − q) = 0; kökler p ± √q.
      final p = b - 9;
      final q = _tamOlmayan[(a + (c == 5 ? 7 : 0)) % 25];
      final (kk, mm) = _kokSade(q);
      final denklem = '${_polinom([1, -2 * p, p * p - q])} = 0';
      final delta = 4 * p * p - 4 * (p * p - q);
      final (dk, dm) = _kokSade(delta);
      final adim =
          'Δ = ${_p(-2 * p)}² − 4 · 1 · ${_p(p * p - q)} = $delta olur. x = '
                  '(${_n(2 * p)} ± √$delta) / 2 = (${_n(2 * p)} ± ${_kokYaz(dk, dm)}) / 2 = '
                  '${_surd(p, kk, mm, true).replaceAll(' + ', ' ± ')}.'
              .replaceAll('(0 ± ', '(± ');
      if (c == 4) {
        return secenekli(
          '$denklem denkleminin büyük kökü nedir?',
          _surd(p, kk, mm, true),
          [
            _surd(p, kk, mm, false),
            _surd(-p, kk, mm, true),
            _surd(2 * p, kk, mm, true),
            _surd(p, 2 * kk, mm, true),
            _surd(p + 1, kk, mm, true),
          ],
          '$adim Büyük kök ${_surd(p, kk, mm, true)} olur.',
        );
      }
      final fark = _kokYaz(2 * kk, mm);
      return secenekli(
        '$denklem denkleminin büyük kökü ile küçük kökü arasındaki fark nedir?',
        fark,
        [
          _kokYaz(kk, mm),
          _kokYaz(4 * kk, mm),
          // Kökler farkı √Δ / |a| iken karekökü almayı unutmak: Δ.
          '$delta',
          _kokYaz(kk * 3, mm),
        ],
        '$adim Kökler farkı (${_surd(p, kk, mm, true)}) − (${_surd(p, kk, mm, false)}) = '
            '$fark olur.',
      );
    case 6:
      // x² + mx + C = 0 denkleminin bir kökü r ise diğeri s (rs = C).
      // ±1 kullanılmaz: r = ±1 iken sabit terim diğer köke eşit görünürdü.
      final r = const [
        2,
        -3,
        4,
        12,
        5,
        -2,
        3,
        -4,
        6,
        -10,
        -5,
        7,
        -6,
        8,
        -7,
        9,
        -8,
        10,
        -9,
        11,
      ][b];
      final sv = _uygun(
        const [
          3,
          -5,
          6,
          -2,
          7,
          -4,
          1,
          -6,
          8,
          2,
          -7,
          9,
          4,
          -3,
          5,
          -8,
          10,
          -9,
          11,
          -10,
          12,
          -11,
          13,
          -12,
          14,
          -1,
          15,
          -13,
        ],
        a,
        (x) => x != r && x != -r,
      );
      final C = r * sv, m = -(r + sv);
      return _tam(
        'x² + mx ${C < 0 ? '−' : '+'} ${C.abs()} = 0 denkleminin köklerinden biri '
            '${_n(r)} olduğuna göre diğer kökü kaçtır?',
        sv,
        [m, -sv, ?_bol(-C, r), r + sv],
        'x = ${_n(r)} denklemi sağlar: ${_p(r)}² + m · ${_p(r)} ${C < 0 ? '−' : '+'} '
            '${C.abs()} = 0 eşitliğinden m = ${_n(m)} bulunur. Denklem '
            '${_polinom([1, m, C])} = ${_carpanX(r)}${_carpanX(sv)} = 0 olduğundan diğer kök '
            '${_n(sv)} olur.',
      );
    default:
      // (x − p)(x + q) = K biçimi; pozitif kök istenir.
      final r1 = 2 + a; // pozitif kök
      final r2 = -(1 + b); // negatif kök
      final p = const [1, 2, 3, -1, 4, -2, 5][(a + b + w) % 7];
      // (x − p)(x + q) − K = (x − r1)(x − r2) ⇒ q − p = −(r1 + r2), −pq − K = r1·r2
      final qq = p - (r1 + r2);
      final K = -p * qq - r1 * r2;
      return _tam(
        '${_carpanX(p)} · ${_carpanX(-qq)} = ${_n(K)} denkleminin pozitif kökü kaçtır?',
        r1,
        [r2.abs(), p, K, r1 + 1],
        'Çarpım açılıp sabit terim sola alınır: ${_polinom([1, -(r1 + r2), r1 * r2])} '
            '= 0. Bu denklem ${_carpanX(r1)}${_carpanX(r2)} = 0 biçiminde çarpanlarına '
            'ayrılır; kökler $r1 ve ${_n(r2)} olur. Pozitif kök $r1 bulunur.',
      );
  }
}

String _sar(String s) => s.contains('/') || s.startsWith('−') ? '($s)' : s;

// ---------------------------------------------------------------------------
// 16. İşaret tablosuyla çözülen eşitsizlikler
// ---------------------------------------------------------------------------

/// Doğrusal çarpanlı eşitsizlik: pay ve payda kökleri, ters yazılan çarpan
/// (r − x biçimi), kare çarpan ve eşitsizlik işareti.
AdvancedItem _isaretSoru(int a, int b, int c) =>
    _kokteOlmayan((w) => _isaretUret(a, b, c, w));

/// [w]: pay/payda dağılımı, ters yazılan çarpan ya da kare çarpanın yeri gibi
/// ikincil parametreleri değiştirir (yanıt kökte yazılıysa).
AdvancedItem _isaretUret(int a, int b, int c, int w) {
  final say = c.isEven; // tam sayı adedi mi, toplam mı
  final esit = ((a + b + c) % 2 == 0) != (w ~/ 2).isOdd; // ≤ mi < mi
  if (c < 6) {
    // Dört farklı kök: t1 < t2 < t3 < t4.
    final t1 = -9 + a % 13 + 30 * (w ~/ 4 % 2),
        g1 = 2 + b % 4,
        g2 =
            2 + (a + b) % 3, // ortadaki aralıkta en az bir tam sayı kalır
        g3 = 2 + b ~/ 4 % 5;
    final t2 = t1 + g1, t3 = t2 + g2, t4 = t3 + g3;
    final kokler = [t1, t2, t3, t4];
    // Paydaki kökler: türüne göre 2, 3 ya da 1 tane.
    final payAdet = const [2, 2, 3, 3, 1, 1][c];
    final secimler = switch (payAdet) {
      2 => const [
        [0, 1],
        [0, 2],
        [0, 3],
        [1, 2],
        [1, 3],
        [2, 3],
      ],
      3 => const [
        [0, 1, 2],
        [0, 1, 3],
        [0, 2, 3],
        [1, 2, 3],
      ],
      _ => const [
        [0],
        [1],
        [2],
        [3],
      ],
    };
    final secim = secimler[(a ~/ 13 + 2 * b + w % 2) % secimler.length];
    final pay = [for (final j in secim) kokler[j]];
    final payda = [
      for (var j = 0; j < 4; j++)
        if (!secim.contains(j)) kokler[j],
    ];
    // Bir çarpan (r − x) biçiminde yazılırsa işaret yön değiştirir.
    final ters = (a + c) % 3 == 0;
    final tersKok = ters ? pay.first : null;
    String carpan(int r) => r == tersKok
        ? '(${_dogrusal(-1, r).replaceFirst('−x + ', '')} − x)'.replaceFirst(
            '(−x)',
            '(−x)',
          )
        : _carpanX(r);
    String tersYaz(int r) => r == 0 ? '(−x)' : '(${_n(r)} − x)';
    String yaz(int r) => r == tersKok ? tersYaz(r) : _carpanX(r);
    carpan(0);
    final payYazi = pay.map(yaz).join(''), paydaYazi = payda.map(yaz).join('');
    final isaret = ters ? (esit ? '≥' : '>') : (esit ? '≤' : '<');
    final ifade =
        '$payYazi / ${payda.length == 1 ? paydaYazi : '($paydaYazi)'}';
    // Çözüm: E = Π(x − r) / Π(x − s) için E < 0 ⇔ (t1, t2) ∪ (t3, t4).
    bool saglar(int x) {
      if (payda.contains(x)) return false;
      if (pay.contains(x)) return esit;
      var negatif = 0;
      for (final r in kokler) {
        if (x < r) negatif++;
      }
      return negatif.isOdd;
    }

    final cozum = [
      for (var x = t1 - 3; x <= t4 + 3; x++)
        if (saglar(x)) x,
    ];
    // Tipik yanlışlar: payda köklerini dâhil etmek, pay köklerini dışarıda
    // bırakmak, iç aralıkları karıştırmak.
    final paydaDahil = [
      for (var x = t1; x <= t4; x++)
        if (saglar(x) || payda.contains(x)) x,
    ];
    // Eşitlik durumunun ters ele alınması: ≤ için pay kökleri atılır, < için
    // pay kökleri eklenir.
    final payHata = esit
        ? [
            for (final x in cozum)
              if (!pay.contains(x)) x,
          ]
        : [
            for (var x = t1; x <= t4; x++)
              if (saglar(x) || pay.contains(x)) x,
          ];
    final tumAralik = [
      for (var x = t1; x <= t4; x++)
        if (!payda.contains(x)) x,
    ];
    final orta = [
      for (var x = t2; x <= t3; x++)
        if (!payda.contains(x) && (esit || (x != t2 && x != t3))) x,
    ];
    int deger(List<int> t) => say ? t.length : _topla(t);
    final aralik = '${_n(t1)}, ${_n(t2)}, ${_n(t3)} ve ${_n(t4)}';
    final parca = [
      '${pay.contains(t1) && esit ? '[' : '('}${_n(t1)}, ${_n(t2)}${pay.contains(t2) && esit ? ']' : ')'}',
      '${pay.contains(t3) && esit ? '[' : '('}${_n(t3)}, ${_n(t4)}${pay.contains(t4) && esit ? ']' : ')'}',
    ].join(' ∪ ');
    final aciklama =
        'Kritik noktalar $aralik olur. ${ters ? '${tersYaz(tersKok!)} çarpanı −${_carpanX(tersKok)} biçiminde yazılıp eşitsizlik −1 ile çarpılırsa yön değişir. ' : ''}'
        'İşaret tablosunda en sağdaki aralık pozitiftir ve her kökte işaret değişir; '
        'çözüm kümesi $parca olur (paydanın kökleri dâhil edilmez). Bu kümedeki tam '
        'sayılar ${_tamListe(cozum)}${say ? '' : '; toplamları ${_n(_topla(cozum))} bulunur'}.';
    return _tamD(
      '$ifade $isaret 0 eşitsizliğini sağlayan ${say ? 'kaç tane x tam sayısı vardır' : 'x tam sayılarının toplamı kaçtır'}?',
      deger(cozum),
      [deger(paydaDahil), deger(payHata), deger(tumAralik), deger(orta)],
      aciklama,
      pozitif: say,
    );
  }
  // c ≥ 6: kare çarpanlı eşitsizlik (x − p)²(x − q)/(x − r) ≤ 0 ya da < 0.
  final esit2 = c == 6 || c == 7;
  final q = -12 + a + 30 * (w % 3), gen = 3 + b % 5, ek = b ~/ 10;
  final r = (b ~/ 5).isEven
      ? q + gen
      : q - gen; // r, q'nun sağında ya da solunda
  final alt = q < r ? q : r, ust = q < r ? r : q;
  // Kare çarpan yalnız iki durumda sonucu değiştirir: ≤ iken p aralığın
  // dışındaysa p eklenir, < iken p aralığın içindeyse p çıkarılır. Yalnız bu
  // iki durum sorulur; böylece kare çarpanı yok sayan yol yanlış sonuç verir.
  final icMi = !esit2;
  final p = icMi
      ? alt + 1 + (a + ek) % (gen - 1)
      : (a.isEven
            ? ust + 2 + a % 3 + 3 * ek + 6 * (w ~/ 3)
            : alt - 2 - a % 3 - 3 * ek - 6 * (w ~/ 3));
  final isaret = esit2 ? '≤' : '<';
  bool saglar(int x) {
    if (x == r) return false;
    if (x == p || x == q) return esit2;
    return (x - q) * (x - r) < 0;
  }

  final cozum = [
    for (var x = (p < alt ? p : alt) - 2; x <= (p > ust ? p : ust) + 2; x++)
      if (saglar(x)) x,
  ];
  final kareYok = [
    for (var x = alt; x <= ust; x++)
      if (x != r && (x - q) * (x - r) <= 0 && (esit2 || x != q)) x,
  ];
  final rDahil = [...cozum, if (!cozum.contains(r)) r]..sort();
  final hepsi = [
    for (var x = alt; x <= ust; x++)
      if (x != r && x != p) x,
  ];
  int deger(List<int> t) => say ? t.length : _topla(t);
  final ifade = '${_carpanX(p)}² · ${_carpanX(q)} / ${_carpanX(r)}';
  final aralik = q < r
      ? '${esit2 ? '[' : '('}${_n(q)}, ${_n(r)})'
      : '(${_n(r)}, ${_n(q)}${esit2 ? ']' : ')'}';
  final aciklama =
      '${_carpanX(p)}² çarpanı negatif olamaz; bu çarpan x = ${_n(p)} dışında işareti '
      'etkilemez. Kalan ${_carpanX(q)} / ${_carpanX(r)} $isaret 0 eşitsizliğinin '
      'çözümü $aralik aralığıdır. x = ${_n(p)} için ifade 0 olduğundan bu değer '
      '${esit2 ? 'çözüme katılır' : 'çözüme katılmaz'}. Çözümdeki tam sayılar '
      '${_tamListe(cozum)}${say ? '' : '; toplamları ${_n(_topla(cozum))} bulunur'}.';
  return _tamD(
    '$ifade $isaret 0 eşitsizliğini sağlayan ${say ? 'kaç tane x tam sayısı vardır' : 'x tam sayılarının toplamı kaçtır'}?',
    deger(cozum),
    [deger(kareYok), deger(rDahil), deger(hepsi), deger(cozum) + (say ? 1 : p)],
    aciklama,
    pozitif: say,
  );
}

// ---------------------------------------------------------------------------
// 17. Saat problemleri: akrep ile yelkovan arasındaki açı
// ---------------------------------------------------------------------------

/// Yarım derece cinsinden açıyı küçük açıya indirger (0 … 360 yarım derece).
int _kucukAci2(int yarim) {
  final d = yarim % 720;
  return d > 360 ? 720 - d : d;
}

String _derece2(int yarim) =>
    yarim.isEven ? '${yarim ~/ 2}' : '${yarim ~/ 2},5';

/// Saat h tam iken akrep 12 rakamından 30h derece ileridedir; t dakika sonra
/// yelkovan akrebe göre 5,5t derece yol alır. Küçük açının θ olduğu pozitif
/// t anları (11t tam sayıdır) küçükten büyüğe.
List<int> _aciAnlari(int h, int teta, int adet) {
  final r = <int>{};
  for (var j = -2; j < 4; j++) {
    for (final isaret in const [1, -1]) {
      final n = 60 * (h % 12) + isaret * 2 * teta + 720 * j; // 11t
      if (n > 0) r.add(n);
    }
  }
  final l = r.toList()..sort();
  return l.take(adet).toList();
}

/// (saat, dakika) ya da (saat, açı, kaçıncı) vakaları.
final List<(int, int, int)> _saatVakalari = () {
  final aciVaka = <(int, int, int)>[];
  for (var h = 1; h <= 12; h++) {
    for (var m = 1; m <= 59; m++) {
      final v2 = _kucukAci2(60 * h - 11 * m);
      final saf2 = _kucukAci2(60 * h - 12 * m); // akrebin hareketini unutan yol
      if (v2 == 0 || v2 == saf2 || v2 == 2 * h || v2 == 2 * m) continue;
      aciVaka.add((h, m, 0));
    }
  }
  final anVaka = <(int, int, int)>[];
  for (var teta = 0; teta <= 180; teta++) {
    for (var h = 1; h <= 12; h++) {
      if (teta * 2 == _kucukAci2(60 * h)) continue; // saat başındaki açı
      for (final k in const [1, 2]) {
        final t11 = _aciAnlari(h, teta, 2)[k - 1];
        if (t11 % 11 == 0 && {h, teta, k}.contains(t11 ~/ 11)) continue;
        anVaka.add((h, teta, k));
      }
    }
  }
  final r = <(int, int, int)>[];
  var ia = 0, ib = 0;
  // Anvaka listesi açıya göre sıralıdır; geniş bir yayılım için adımla okunur.
  final adim = _adimSec(anVaka.length);
  while (r.length < lmAileBoyu) {
    if (r.length % 7 == 0 && ia < aciVaka.length) {
      r.add(aciVaka[ia++]);
    } else {
      r.add(anVaka[ib * adim % anVaka.length]);
      ib++;
    }
  }
  return r;
}();

AdvancedItem _saatSoru(int i) {
  final (h, x, k) = _saatVakalari[i];
  if (k == 0) {
    final m = x;
    final akrep2 = 60 * (h % 12) + m; // yarım derece (30h + 0,5m)
    final yelkovan2 = 12 * m; // yarım derece (6m)
    final fark2 = (akrep2 - yelkovan2).abs();
    final v2 = _kucukAci2(60 * h - 11 * m);
    final buyuk2 = 720 - v2;
    final saf2 = _kucukAci2(60 * h - 12 * m);
    final sonraki2 = _kucukAci2(60 * (h % 12 + 1) - 11 * m);
    return secenekli(
      'Saat $h:${m.toString().padLeft(2, '0')} iken akrep ile yelkovan arasındaki '
          'küçük açı kaç derecedir?',
      _derece2(v2),
      [
        _derece2(buyuk2),
        _derece2(saf2),
        _derece2(sonraki2),
        _derece2(v2 + 60),
        _derece2((v2 - 60).abs()),
      ],
      'Yelkovan 12 rakamından $m · 6 = ${_derece2(yelkovan2)}°, akrep '
          '${h == 12 ? '' : '$h · 30 + '}$m · 0,5 = ${_derece2(akrep2)}° ilerdedir. Aradaki fark '
          '${_derece2(fark2)}°${fark2 > 360 ? ' olup 180 dereceden büyük olduğundan küçük açı 360 − ${_derece2(fark2)} = ${_derece2(v2)}° olur' : ' olduğundan küçük açı ${_derece2(v2)}° olur'}.',
    );
  }
  final teta = x;
  final anlar = _aciAnlari(h, teta, 3);
  final t11 = anlar[k - 1];
  final bas = _kucukAci2(60 * h) ~/ 2;
  final neZaman = k == 1 ? 'ilk' : 'ikinci';
  final olay = switch (teta) {
    0 => 'akrep ile yelkovan $neZaman kez üst üste gelir',
    180 => 'akrep ile yelkovan arasındaki açı $neZaman kez 180° olur',
    _ => 'akrep ile yelkovan arasındaki küçük açı $neZaman kez $teta° olur',
  };
  // Hedef: 5,5t = 30h ± θ + 360j, yani 11t = 60h ± 2θ + 720j.
  final hedef = t11 ~/ 2 * 2 == t11 ? '${t11 ~/ 2}' : '${t11 ~/ 2},5';
  final saf = 2 * teta; // başlangıç açısını unutup θ = 5,5t alan yol
  // Akrebi sabit sanıp yelkovanın 6° yolunu kullanan yol: 12t = 60h ∓ 2θ.
  final akrepsiz = (60 * (h % 12) - 2 * teta).abs();
  final akrepsiz2 = 60 * (h % 12) + 2 * teta;
  // Süre sorusunda yanıtın tersi (11/60 dakika gibi) bir hata yolu değildir.
  return _kes(
    'Saat tam $h olduktan kaç dakika sonra $olay?',
    t11,
    11,
    [
      (anlar[k == 1 ? 1 : 0], 11),
      (anlar[2], 11),
      if (saf > 0) (saf, 11),
      if (akrepsiz > 0) (akrepsiz, 12),
      if (akrepsiz2 > 0) (akrepsiz2, 12),
    ],
    'Saat tam $h iken akrep 12 rakamından ${(30 * h) % 360}°, yelkovan 0° '
        'konumundadır; aralarındaki küçük açı $bas° olur. Yelkovan akrebe göre '
        'dakikada 6 − 0,5 = 5,5° yol alır. t dakika sonra açı farkı |5,5t − '
        '${(30 * h) % 360}| olur ve bu farkın küçük açısı $teta° olmalıdır. Pozitif '
        'çözümler küçükten büyüğe ${anlar.take(2).map((n) => _q(n, 11)).join(' ve ')} '
        'dakikadır; $neZaman çözüm 5,5t = $hedef eşitliğinden t = ${_q(t11, 11)} '
        'bulunur.',
    pozitif: true,
    ters: false,
  );
}

// ---------------------------------------------------------------------------
// 18. Kesirli harcama ve kalan miktar problemleri
// ---------------------------------------------------------------------------

const _kesirA = [
  (1, 3),
  (2, 5),
  (1, 4),
  (3, 8),
  (2, 7),
  (1, 5),
  (3, 5),
  (1, 6),
  (2, 9),
  (3, 10),
  (1, 2),
  (3, 4),
  (4, 9),
  (5, 12),
  (2, 3),
  (1, 8),
  (3, 7),
  (4, 7),
  (5, 8),
  (1, 7),
  (2, 11),
  (5, 9),
  (7, 12),
  (3, 11),
  (4, 11),
];
const _kesirB = [
  (1, 4),
  (2, 3),
  (1, 5),
  (3, 4),
  (1, 3),
  (2, 5),
  (1, 2),
  (3, 5),
  (1, 6),
  (5, 6),
  (2, 7),
  (4, 5),
  (3, 8),
  (1, 8),
  (2, 9),
  (3, 7),
  (5, 7),
  (4, 9),
  (1, 10),
  (7, 10),
];

const _kesirEk = [(3, 10), (5, 9), (4, 7), (2, 11), (5, 11), (7, 9)];

String _kesYaz((int, int) f) => '${f.$1}/${f.$2}';

AdvancedItem _kalanKesirSoru(int a, int b, int c) {
  final f1 = _kesirA[a];
  // Kesir sorularında (c = 3, 9) yanıtın kökteki kesirlerden birine eşit
  // çıktığı ikinci kesirler atlanır.
  bool yazili((int, int) f) {
    final kn = (f1.$2 - f1.$1) * (f.$2 - f.$1), kd = f1.$2 * f.$2;
    final n = c == 9 ? kd - kn : kn;
    return {_q(f1.$1, f1.$2), _q(f.$1, f.$2)}.contains(_q(n, kd));
  }

  // c = 0, 3, 4 için ikinci kesir 1/2 olmasın: o zaman kalan ile ikinci
  // harcama eşit çıkar ve birini soran soruda ötekini bulan da doğru yanıta
  // ulaşır.
  final yarimOlmasin = c == 0 || c == 3 || c == 4;
  final f2 = c == 3 || c == 9 || yarimOlmasin
      ? _uygun(
          [..._kesirB, ..._kesirEk],
          b,
          (f) =>
              (!(c == 3 || c == 9) || !yazili(f)) &&
              (!yarimOlmasin || f != (1, 2)),
        )
      : _kesirB[b];
  final (p1, q1) = f1;
  final (p2, q2) = f2;
  final k1 = q1 - p1, k2 = q2 - p2; // kalan kesirlerin payları
  final birim = q1 * q2; // başlangıç miktarının bu sayının katı olması yeterli
  final carpan = 1 + (a + 2 * b) % 4;
  // Başlangıç miktarı: [taban] değerinden büyük ilk [kat] katı, ardından
  // [kat] adımlarıyla artar; böylece miktar bağlamına uygun dar bir aralıkta
  // kalır (ör. maaş 42000 … 64000 TL, buğday 2400 … 5200 kg).
  int miktar(int kat, int taban, int adimSayisi) =>
      kat * ((taban + kat - 1) ~/ kat + adimSayisi);
  switch (c) {
    case 0 || 4:
      // Maaş: kira ve mutfak. Maaş 42000 … 64000 TL aralığında kalır.
      final m = miktar(birim, 42000, 40 * carpan);
      final ilk = m * p1 ~/ q1, kalan1 = m - ilk;
      final ikinci = kalan1 * p2 ~/ q2, kalan = kalan1 - ikinci;
      final kok =
          'Aylık geliri $m TL olan bir memur, gelirinin ${_kesYaz(f1)} kadarını kiraya, '
          'kalan paranın ${_kesYaz(f2)} kadarını mutfak giderlerine ayırıyor.';
      if (c == 0) {
        return _tamD(
          '$kok Bu harcamalardan sonra memurun elinde kaç TL kalır?',
          kalan,
          [
            ?_bol(m * (q1 * q2 - p1 * q2 - p2 * q1), q1 * q2),
            ikinci,
            ilk + ikinci,
            kalan1,
          ],
          'Kiradan sonra $m · $k1/$q1 = $kalan1 TL kalır. Mutfak giderleri '
              '$kalan1 · ${_kesYaz(f2)} = $ikinci TL olduğundan elde $kalan1 − $ikinci = '
              '$kalan TL kalır.',
          birim: 'TL',
          pozitif: true,
          komsuAdim: _katAdim(kalan, m ~/ birim),
        );
      }
      return _tamD(
        '$kok Buna göre memur mutfak giderlerine kaç TL ayırır?',
        ikinci,
        [
          m * p2 ~/ q2,
          kalan,
          ilk,
          kalan1 - ilk,
          // Kalan para yerine kiraya ayrılan paranın kesrini almak.
          m * p1 * p2 ~/ (q1 * q2),
        ],
        'Kiraya $m · ${_kesYaz(f1)} = $ilk TL ayrılır ve $kalan1 TL kalır. Mutfak '
            'giderleri bu kalanın ${_kesYaz(f2)} kadarı olduğundan $kalan1 · '
            '${_kesYaz(f2)} = $ikinci TL olur.',
        birim: 'TL',
        pozitif: true,
        komsuAdim: _katAdim(ikinci, m ~/ birim),
      );
    case 1 || 8:
      // Kalandan başlangıç miktarı: buğday (kg) ya da depodaki su (L).
      final su = c == 8;
      // Buğday 2400 … 5200 kg, depodaki su 2400 … 5200 L.
      final bas = miktar(birim, 2400, 4 * ((a + b) % 6));
      final kalan = bas * k1 * k2 ~/ (q1 * q2);
      final kok = su
          ? 'Bir depodaki suyun ${_kesYaz(f1)} kadarı bahçe sulamada, kalan suyun '
                '${_kesYaz(f2)} kadarı temizlikte kullanılıyor. Depoda $kalan L su '
                'kaldığına göre başlangıçta depoda kaç litre su vardı?'
          : 'Bir çiftçi ürettiği buğdayın ${_kesYaz(f1)} kadarını satıyor, kalan '
                'buğdayın ${_kesYaz(f2)} kadarını hayvan yemi olarak ayırıyor. Geriye '
                '$kalan kg buğday kaldığına göre çiftçi kaç kilogram buğday üretmiştir?';
      final ters =
          q1 * q2 - p1 * q2 - p2 * q1; // kesirleri doğrudan çıkaran yol
      return _tamD(
        kok,
        bas,
        [
          if (ters > 0) ?_bol(kalan * q1 * q2, ters),
          kalan * q1 ~/ k1,
          kalan * q2 ~/ k2,
          ?_bol(kalan * q1 * q2, p1 * p2),
        ],
        'Başlangıç miktarı x olsun. İlk adımdan sonra x · $k1/$q1, ikinci adımdan '
        'sonra x · $k1/$q1 · $k2/$q2 = x · ${_q(k1 * k2, q1 * q2)} kalır. '
        'x · ${_q(k1 * k2, q1 * q2)} = $kalan eşitliğinden x = $bas bulunur.',
        birim: su ? 'L' : 'kg',
        pozitif: true,
        komsuAdim: _katAdim(bas, birim),
      );
    case 2:
      // Üç aşamalı harcama; başlangıç parası istenir.
      final f3 = _kesirB[(b + 7) % 20];
      final (p3, q3) = f3;
      final k3 = q3 - p3;
      // Harçlık 2000 … 6000 TL.
      final bas = miktar(birim * q3, 2000, (a + b) % 3);
      final kalan = bas * k1 * k2 * k3 ~/ (q1 * q2 * q3);
      return _tamD(
        'Bir öğrenci harçlığının ${_kesYaz(f1)} kadarını kitaba, kalan paranın '
            '${_kesYaz(f2)} kadarını yemeğe, en son kalan paranın ${_kesYaz(f3)} '
            'kadarını ulaşıma harcıyor. Öğrencinin $kalan TL parası kaldığına göre '
            'başlangıçta kaç TL harçlığı vardı?',
        bas,
        [
          kalan * q1 * q2 ~/ (k1 * k2),
          kalan * q3 ~/ k3,
          ?_bol(
            kalan * q1 * q2 * q3,
            q1 * q2 * q3 - p1 * q2 * q3 - p2 * q1 * q3 - p3 * q1 * q2,
          ),
          kalan * 3,
          // Kalan kesirler yerine harcanan kesirleri çarpmak.
          ?_bol(kalan * q1 * q2 * q3, p1 * p2 * p3),
        ].where((x) => x > 0),
        'Harçlık x olsun. Kalan para x · $k1/$q1 · $k2/$q2 · $k3/$q3 = x · '
            '${_q(k1 * k2 * k3, q1 * q2 * q3)} olur. Bu değer $kalan olduğundan '
            'x = $bas bulunur.',
        birim: 'TL',
        pozitif: true,
        komsuAdim: _katAdim(bas, birim * q3),
      );
    case 3 || 9:
      // Kalan ya da kullanılan kesir.
      final kn = k1 * k2, kd = q1 * q2;
      final kullanilan = c == 9;
      final n = kullanilan ? kd - kn : kn;
      return _kesD(
        kullanilan
            ? 'Bir su deposundaki suyun önce ${_kesYaz(f1)} kadarı, sonra kalan suyun '
                  '${_kesYaz(f2)} kadarı kullanılıyor. Kullanılan su, deponun başlangıçtaki '
                  'suyunun kaçta kaçıdır?'
            : 'Bir öğrenci harçlığının önce ${_kesYaz(f1)} kadarını, sonra kalan '
                  'paranın ${_kesYaz(f2)} kadarını harcıyor. Öğrencinin kalan parası '
                  'başlangıçtaki harçlığının kaçta kaçıdır?',
        n,
        kd,
        [
          if (kullanilan)
            (p1 * q2 + p2 * q1, q1 * q2)
          else
            (q1 * q2 - p1 * q2 - p2 * q1, q1 * q2),
          if (kullanilan) (p1 * p2, q1 * q2) else (k1 * p2, q1 * q2),
          (kd - n, kd),
          if (kullanilan) (p1 + p2, q1 + q2) else (k1 + k2, q1 + q2),
          // Kalanı 1 − (harcanan kesirlerin çarpımı) ya da harcanan
          // kesirlerin çarpımı sanmak; ikinci adımı unutup ilk adımdaki
          // kalanı yanıt sanmak. Kullanılanı yalnız ikinci adımda kullanılan
          // kısım ya da 1 − (harcanan kesirlerin çarpımı) sanmak.
          if (kullanilan) ...[
            (k1 * p2, q1 * q2),
            (kd - p1 * p2, kd),
          ] else ...[
            (kd - p1 * p2, kd),
            (p1 * p2, q1 * q2),
            (k1, q1),
          ],
        ].where((t) => t.$1 > 0 && t.$1 < t.$2 && t.$1 * kd != n * t.$2),
        'İlk adımdan sonra $k1/$q1, ikinci adımdan sonra $k1/$q1 · $k2/$q2 = '
        '${_q(kn, kd)} kalır. ${kullanilan ? 'Kullanılan kısım 1 − ${_q(kn, kd)} = ${_q(n, kd)} olur.' : 'Kalan para harçlığın ${_q(kn, kd)} kadarıdır.'}',
        pozitif: true,
        // Bütünün bir parçası sorulduğundan 1 ya da daha büyük kesir (yanıtın
        // tersi gibi) çeldirici olmaz.
        ters: false,
        birdenKucuk: true,
      );
    case 5:
      // İlk harcama ikinci harcamadan D TL fazla ya da az; iki harcamanın eşit
      // olduğu kesir ikilileri atlanır.
      final g2 = _uygun(
        [..._kesirB, ..._kesirEk],
        b,
        (f) => p1 * f.$2 != k1 * f.$1,
      );
      final (r2, s2) = g2;
      final ilkPay = p1 * s2, ikinciPay = k1 * r2; // payda q1·s2
      final farkPay = ilkPay - ikinciPay;
      // Harçlık 1500 … 2500 TL.
      final bas = miktar(q1 * s2, 1500, 2 * ((a + b) % 4));
      final fark = (bas * farkPay ~/ (q1 * s2)).abs();
      final fazla = farkPay > 0;
      return _tamD(
        'Bir öğrenci harçlığının ${_kesYaz(f1)} kadarını kitaba, kalan paranın '
            '${_kesYaz(g2)} kadarını yemeğe harcıyor. Kitaba harcadığı para, yemeğe '
            'harcadığından $fark TL ${fazla ? 'fazla' : 'az'} olduğuna göre başlangıçta '
            'kaç TL harçlığı vardı?',
        bas,
        [
          ?_bol(fark * q1 * s2, (p1 * s2 - r2 * q1).abs()),
          ?_bol(fark * q1, p1),
          ?_bol(fark * q1 * s2, ilkPay + ikinciPay),
          bas * p1 ~/ q1,
          bas * ikinciPay ~/ (q1 * s2),
          2 * fark,
        ].where((x) => x > 0 && x != fark),
        'Harçlık x olsun. Kitaba x · ${_kesYaz(f1)}, yemeğe x · $k1/$q1 · ${_kesYaz(g2)} = '
            'x · ${_q(ikinciPay, q1 * s2)} harcanır. Fark x · ${_q(farkPay.abs(), q1 * s2)} = '
            '$fark olduğundan x = $bas bulunur.',
        birim: 'TL',
        pozitif: true,
        komsuAdim: _katAdim(bas, q1 * s2),
      );
    case 6:
      // Kesir + sabit tutar: x · (1 − f1) − T = x · (1 − f1) · h.
      final (hp, hq) = f2;
      final gn = k1 * hp, gd = q1 * hq;
      // Para 4000 … 5400 TL; fatura birkaç yüz ile birkaç bin TL arasında.
      final bas = miktar(q1 * hq, 4000, 3 * ((a + b) % 4));
      final T = bas * k1 * (hq - hp) ~/ (q1 * hq);
      final g = _q(gn, gd);
      final (gp, gq) = (gn ~/ gn.gcd(gd), gd ~/ gn.gcd(gd));
      return _tamD(
        'Bir kişi parasının ${_kesYaz(f1)} kadarını market alışverişine harcadıktan '
            'sonra $T TL de fatura ödüyor. Geriye başlangıçtaki parasının $g kadarı '
            'kaldığına göre kişinin başlangıçta kaç TL parası vardı?',
        bas,
        [
          ?_bol(T * q1, k1),
          ?_bol(T * gq, gq - gp),
          ?_bol(T * q1 * gq, k1 * gq + gp * q1),
          bas * k1 ~/ q1,
          bas - T,
          2 * T,
        ].where((x) => x > 0 && x != bas),
        'Para x olsun. Marketten sonra x · $k1/$q1 kalır; fatura ödenince '
            'x · $k1/$q1 − $T = x · $g olur. Buradan x · '
            '${_q(k1 * gq - gp * q1, q1 * gq)} = $T ve x = $bas bulunur.',
        birim: 'TL',
        pozitif: true,
        komsuAdim: _katAdim(bas, q1 * hq),
      );
    default:
      // Roman 160 … 660 sayfa.
      final sayfa = miktar(birim, 160, (a + b) % 4);
      final kalan = sayfa * k1 * k2 ~/ (q1 * q2);
      return _tamD(
        'Bir öğrenci okuduğu romanın önce ${_kesYaz(f1)} kadarını, sonra kalan '
            'sayfaların ${_kesYaz(f2)} kadarını okuyor. Okumadığı $kalan sayfa '
            'kaldığına göre roman kaç sayfadır?',
        sayfa,
        [
          kalan * q1 ~/ k1,
          kalan * q2 ~/ k2,
          if (q1 * q2 - p1 * q2 - p2 * q1 > 0)
            ?_bol(kalan * q1 * q2, q1 * q2 - p1 * q2 - p2 * q1),
          // Okunmayan kesirler yerine okunan kesirleri çarpmak.
          ?_bol(kalan * q1 * q2, p1 * p2),
        ],
        'Roman x sayfa olsun. Okunmayan kısım x · $k1/$q1 · $k2/$q2 = x · '
            '${_q(k1 * k2, q1 * q2)} olur. x · ${_q(k1 * k2, q1 * q2)} = $kalan '
            'eşitliğinden x = $sayfa bulunur.',
        pozitif: true,
        komsuAdim: _katAdim(sayfa, birim),
      );
  }
}

// ---------------------------------------------------------------------------
// 19. Tren, tünel ve köprü problemleri
// ---------------------------------------------------------------------------

/// km/sa → m/s: 18k km/sa = 5k m/s.
String _hizYaz(int ms) => '${ms * 18 ~/ 5} km/sa';

AdvancedItem _trenSoru(int a, int b, int c) =>
    _kokteOlmayan((w) => _trenUret(a, b, c, w));

/// [w]: yanıt kökte yazılıysa süreyi uzatır (c = 9 için ikinci trenin hızını
/// değiştirir). Kaydırma, aynı türdeki başka bir vakayla çakışmayacak kadar
/// büyüktür.
AdvancedItem _trenUret(int a, int b, int c, int w) {
  final v = const [10, 15, 20, 25, 30][a % 5]; // m/s (36 … 108 km/sa)
  final ek = 2 * (a ~/ 5) + 11 * (b ~/ 10);
  final cevir = '${_hizYaz(v)} = $v m/s';
  switch (c) {
    case 0 || 2 || 7:
      final L = (c == 2 ? 110 : 100) + 20 * (b % 10); // tren boyu (m)
      // Tüneli tamamen geçme süresi.
      final t = (L + 400 + v - 1) ~/ v + ek + 20 * w;
      final T = v * t - L; // tünel boyu
      final tren = 'Uzunluğu $L m olan bir tren ${_hizYaz(v)} sabit hızla';
      if (c == 0) {
        return _tamD(
          '$tren ilerliyor. Bu tren $T m uzunluğundaki bir tünele girmeye başladığı '
              'andan tünelden tamamen çıktığı ana kadar kaç saniye geçer?',
          t,
          [
            ?_bol(T, v),
            ?_bol(T - L, v),
            ?_bol(T + L, 2 * v),
            ?_bol(L + T, v * 18 ~/ 5),
            // Trenin tünele girme süresini (L / v) ayrıca eklemek.
            ?_bol(T + 2 * L, v),
          ],
          '$cevir olur. Trenin tüneli tamamen geçmesi için tünel boyu ile kendi boyu '
              'kadar yol alması gerekir: ($T + $L) / $v = $t s.',
          birim: 's',
          pozitif: true,
        );
      }
      if (c == 7) {
        return _tamD(
          '$tren bir tünele girmeye başladığı andan tünelden tamamen çıktığı ana kadar '
              '$t saniye geçiyor. Tünelin uzunluğu kaç metredir?',
          T,
          [
            v * t,
            // Hızı km/sa biriminden m/s birimine çevirmemek.
            (v * 18 ~/ 5) * t - L,
            v * t + L,
            v * t - 2 * L,
          ],
          '$cevir olur. Tren $t saniyede $v · $t = ${v * t} m yol alır. Bu yol tünel '
              'boyu ile tren boyunun toplamıdır: ${v * t} − $L = $T m.',
          birim: 'm',
          pozitif: true,
        );
      }
      return _tamD(
        'Bir tren ${_hizYaz(v)} sabit hızla ilerliyor ve $T m uzunluğundaki bir tüneli, '
            'tünele girmeye başladığı andan tamamen çıktığı ana kadar $t saniyede '
            'geçiyor. Trenin uzunluğu kaç metredir?',
        L,
        [v * t, v * t + T, v * (t - 1) - T, (v * 18 ~/ 5) * t - T],
        '$cevir olur. Tren $t saniyede $v · $t = ${v * t} m yol alır. Bu yol tünel '
            'boyu ile tren boyunun toplamıdır: ${v * t} − $T = $L m.',
        birim: 'm',
        pozitif: true,
        komsuAdim: 10, // tren boyları 10 metrenin katıdır
      );
    case 1:
      final L = 120 + 20 * (b % 10);
      final tIc = 15 + ek + (a % 5); // tamamen içinde kalma süresi
      final T = v * tIc + L;
      return _tamD(
        'Uzunluğu $L m olan bir tren ${_hizYaz(v)} sabit hızla, uzunluğu $T m olan '
            'bir tünelden geçiyor. Tren kaç saniye boyunca tamamen tünelin içinde '
            'kalır?',
        tIc,
        [?_bol(T + L, v), ?_bol(T, v), ?_bol(L, v)],
        '$cevir olur. Trenin tamamen tünel içinde kaldığı süre boyunca aldığı yol '
            'tünel boyundan tren boyu çıkarılarak bulunur: ($T − $L) / $v = $tIc s.',
        birim: 's',
        pozitif: true,
      );
    case 3:
      // Direk ve köprü: L = v·t1, B = v·(t2 − t1).
      final t1 = (120 + v - 1) ~/ v + b % 10;
      final dt = 20 + 4 * (a ~/ 5) + 13 * (b ~/ 10) + 30 * w;
      final L = v * t1, B = v * dt, t2 = t1 + dt;
      return _tamD(
        'Sabit hızla giden bir tren, yol kenarındaki bir direğin önünden $t1 saniyede '
            'geçiyor. Aynı tren $B m uzunluğundaki bir köprüyü, köprüye girmeye '
            'başladığı andan tamamen çıktığı ana kadar $t2 saniyede geçiyor. Trenin '
            'uzunluğu kaç metredir?',
        L,
        [?_bol(B * t1, t2), ?_bol(B * t2, dt), (B - L).abs(), v * t2],
        'Köprüyü geçerken fazladan geçen $t2 − $t1 = $dt saniyede tren köprü boyu '
            'kadar yol alır: hız $B / $dt = $v m/s. Trenin boyu, direği geçme süresinde '
            'aldığı yoldur: $v · $t1 = $L m.',
        birim: 'm',
        pozitif: true,
      );
    case 4 || 5 || 9:
      // İki tren: zıt yönde ya da aynı yönde. Tren boyları 120 … 400 m.
      final v2 = const [10, 15, 20, 25, 5][(a ~/ 5 + b + (c == 9 ? w : 0)) % 5];
      final v1 = v + (c == 5 ? v2 : 0); // aynı yönde v1 > v2
      final goreli = c == 5 ? v1 - v2 : v1 + v2;
      // c = 9 için a ~/ 5 tren boyunda taşınır; böylece hız seçimi serbest kalır.
      final uz1 = 120 + 20 * (b % 10) + (c == 9 ? 4 * (a ~/ 5) : 0);
      final t =
          (uz1 + 120 + goreli - 1) ~/ goreli +
          b ~/ 10 +
          2 * (a ~/ 5 % 2) +
          (c == 9 ? 0 : 4 * w);
      final toplam = goreli * t;
      final uz2 = toplam - uz1;
      // Boylar eşitse “Uzunlukları 120 m ve 120 m” yerine tek değer yazılır;
      // trenler o zaman boylarıyla ayırt edilemediğinden “birinci, ikinci” ya
      // da “sırasıyla” denmez.
      final esitBoy = uz1 == uz2;
      final trenler = esitBoy
          ? 'Her birinin uzunluğu $uz1 m olan iki tren'
          : 'Uzunlukları $uz1 m ve $uz2 m olan iki tren';
      if (c == 9) {
        final bir = esitBoy ? 'Trenlerden birinin' : 'Birinci trenin';
        final obur = esitBoy ? 'diğer trenin' : 'ikinci trenin';
        return _tamD(
          '$trenler paralel raylarda birbirine doğru ilerliyor. $bir hızı '
              '${_hizYaz(v1)} olup trenlerin ön uçlarının karşılaştığı andan arka '
              'uçlarının ayrıldığı ana kadar $t saniye geçiyor. '
              '${esitBoy ? 'Diğer' : 'İkinci'} trenin hızı kaç km/sa olur?',
          v2 * 18 ~/ 5,
          [
            (goreli + v1) * 18 ~/ 5,
            goreli * 18 ~/ 5,
            ?_bol(toplam * 18, 5 * t * 2),
            // m/s cinsinden bulunan hızı km/sa birimine çevirmemek.
            v2,
          ],
          'İki tren birbirini geçerken toplam ${uz1 + uz2} m yol alınır; göreli hız '
              '${uz1 + uz2} / $t = $goreli m/s olur. $bir hızı $v1 m/s '
              'olduğundan $obur hızı $goreli − $v1 = $v2 m/s = '
              '${v2 * 18 ~/ 5} km/sa bulunur.',
          birim: 'km/sa',
          pozitif: true,
          komsuAdim: 18, // 5 m/s adımı
        );
      }
      final zit = c == 4;
      // Hızlar yalnız zıt yönde eşit olabilir: “sırasıyla 54 km/sa ve 54 km/sa”
      // yerine “ikisi de 54 km/sa” yazılır.
      final esitHiz = v1 == v2;
      final hizlar = esitHiz
          ? ', ikisi de ${_hizYaz(v1)} sabit hızla'
          : ' ${esitBoy ? '' : 'sırasıyla '}${_hizYaz(v1)} ve ${_hizYaz(v2)} '
                'sabit hızlarla';
      return _tamD(
        '$trenler paralel raylarda ${zit ? 'birbirine doğru' : 'aynı yönde'}'
            '$hizlar ilerliyor. ${zit ? 'Trenlerin ön uçlarının karşılaştığı andan arka uçlarının ayrıldığı ana kadar' : 'Hızlı trenin ön ucunun yavaş trenin arka ucuna yetiştiği andan hızlı trenin yavaş treni tamamen geçtiği ana kadar'} '
            'kaç saniye geçer?',
        t,
        [
          ?_bol(toplam, zit ? (v1 - v2).abs() : v1 + v2),
          ?_bol(uz1, goreli),
          ?_bol(uz2, goreli),
          ?_bol(toplam, v1),
        ],
        '${_hizYaz(v1)} = $v1 m/s${esitHiz ? '' : ' ve ${_hizYaz(v2)} = $v2 m/s'} olur. '
            '${zit ? 'Zıt yönde' : 'Aynı yönde'} hareket eden trenlerin göreli hızı '
            '${zit ? '$v1 + $v2' : '$v1 − $v2'} = $goreli m/s, alınması gereken yol '
            '$uz1 + $uz2 = $toplam m olduğundan süre $toplam / $goreli = $t s bulunur.',
        birim: 's',
        pozitif: true,
      );
    case 6:
      final L = 150 + 25 * (b % 10);
      final t = (L + 200 + v - 1) ~/ v + ek + 20 * w;
      final B = v * t - L;
      return _tamD(
        'Uzunluğu $L m olan bir tren, $B m uzunluğundaki bir köprüyü, köprüye girmeye '
            'başladığı andan tamamen çıktığı ana kadar $t saniyede geçiyor. Trenin hızı '
            'kaç km/sa olur?',
        v * 18 ~/ 5,
        [
          ?_bol(B * 18, t * 5),
          v,
          ?_bol((B - L) * 18, t * 5),
          // Tren boyunu iki kez eklemek: (B + 2L) / t.
          ?_bol((B + 2 * L) * 18, t * 5),
        ],
        'Tren $t saniyede köprü boyu ile kendi boyunun toplamı kadar, yani $B + $L = '
            '${B + L} m yol alır. Hız ${B + L} / $t = $v m/s olur; $v · 3,6 = '
            '${v * 18 ~/ 5} km/sa bulunur.',
        birim: 'km/sa',
        pozitif: true,
        komsuAdim: 18, // 5 m/s adımı
      );
    default:
      // Tünelde tamamen içinde kalma süresi t1, tamamen geçme süresi t2.
      final t1 = 20 + 5 * (b % 10) + a ~/ 5;
      final yari = (120 + v - 1) ~/ v + 2 * (b ~/ 10) + (a ~/ 5) % 2;
      final fark = 2 * yari; // t2 − t1
      final t2 = t1 + fark;
      final L = v * fark ~/ 2, T = v * (t1 + t2) ~/ 2;
      return _tamD(
        'Sabit ${_hizYaz(v)} hızla giden bir tren bir tünelden geçiyor. Tren $t1 saniye '
            'boyunca tamamen tünelin içinde kalıyor ve tüneli, girmeye başladığı andan '
            'tamamen çıktığı ana kadar $t2 saniyede geçiyor. Trenin uzunluğu kaç '
            'metredir?',
        L,
        [v * fark, v * t1, T],
        '$cevir olur. Tamamen geçerken alınan yol T + L = $v · $t2 = ${v * t2} m, '
            'tamamen içinde kalırken alınan yol T − L = $v · $t1 = ${v * t1} m olur. '
            'Farkın yarısı tren boyudur: (${v * t2} − ${v * t1}) / 2 = $L m.',
        birim: 'm',
        pozitif: true,
      );
  }
}

// ---------------------------------------------------------------------------
// 20. Uzunluk, alan, hacim ve sıvı ölçü birimleri
// ---------------------------------------------------------------------------

const _dekarBilgi = '(1 dekar = 1000 m², 1 hektar = 10000 m²)';

AdvancedItem _birimSoru(int a, int b, int c) =>
    _kokteOlmayan((w) => _birimUret(a, b, c, w));

/// [w]: akvaryum yüksekliği gibi ikincil bir ölçüyü değiştirir.
AdvancedItem _birimUret(int a, int b, int c, int w) {
  String d(num x) => tr(x, 3);
  AdvancedItem ondalik(
    String kok,
    double yanit,
    List<double> yanlis,
    String aciklama,
  ) {
    final dy = d(yanit);
    // Yazılışı değeri tam göstermeyen (yuvarlanan) değerler alınmaz.
    bool uygun(double y) {
      final t = d(y);
      return y > 0 &&
          t != dy &&
          (double.parse(t.replaceAll(',', '.')) - y).abs() <= 1e-9 * y;
    }

    List<(double, String)> yan(Iterable<double> x, bool kucuk) => [
      for (final y in x)
        if (uygun(y) && (kucuk ? y < yanit : y > yanit)) (y, d(y)),
    ];
    // Virgülü bir, iki ya da üç basamak kaydırmak tipik dönüşüm hatalarıdır;
    // bu değerler aday sayılır, diğerleri yalnızca dolgudur.
    final aday = [
      ...yanlis,
      for (final k in const [10, 100, 1000]) ...[yanit / k, yanit * k],
    ];
    return secenekli(
      kok,
      dy,
      _dengeli(
        kok,
        yanit,
        yan(aday, true),
        yan(aday, false),
        yan([yanit / 2, yanit - 1], true),
        yan([yanit * 2, yanit + 1], false),
        carpimsal: true,
      ),
      aciklama,
    );
  }

  switch (c) {
    case 0:
      final km = 1 + a % 5,
          m = 105 + 45 * b,
          cm = 500 * (1 + a ~/ 5) + 50 * (b % 3);
      final top = km * 1000 + m + cm / 100;
      return ondalik(
        'Bir yürüyüş parkuru $km km, $m m ve $cm cm uzunluğundaki üç bölümden '
            'oluşuyor. Parkurun toplam uzunluğu kaç metredir?',
        top,
        [
          km * 1000 + m + cm / 10,
          km * 100 + m + cm / 100,
          km * 1000 + m + cm / 1000,
        ],
        '$km km = ${km * 1000} m ve $cm cm = ${d(cm / 100)} m olur (1 m = 100 cm). '
            'Toplam ${km * 1000} + $m + ${d(cm / 100)} = ${d(top)} m bulunur.',
      );
    case 1:
      // Hektar ↔ dekar.
      final hektar = (b < 10);
      final x = 3 + a + 25 * (b % 10) + 250 * w; // onda bir birim
      if (hektar) {
        final h = x / 10;
        return ondalik(
          'Alanı ${d(h)} hektar olan bir arazi kaç dekardır? $_dekarBilgi',
          h * 10,
          [h * 100, h / 10, h * 1000],
          '1 hektar = 10000 m² = 10 dekar olduğundan ${d(h)} hektar = ${d(h)} · 10 = '
              '${d(h * 10)} dekar olur.',
        );
      }
      final dk = x.toDouble();
      return ondalik(
        'Alanı ${d(dk)} dekar olan bir arazi kaç hektardır? $_dekarBilgi',
        dk / 10,
        [dk * 10, dk / 100, dk / 1000],
        '1 hektar = 10 dekar olduğundan ${d(dk)} dekar = ${d(dk)} / 10 = ${d(dk / 10)} '
            'hektar olur.',
      );
    case 2:
      final en = 40 + 10 * a, boy = 25 * (2 + b);
      final alan = en * boy;
      // Kenarlar eşitse (50 m ve 50 m gibi) tarla kare olarak anlatılır.
      return ondalik(
        '${en == boy ? 'Bir kenarı $en m olan kare' : 'Kenarları $en m ve $boy m olan dikdörtgen'} '
            'biçimli bir tarlanın alanı kaç dekardır? (1 dekar = 1000 m²)',
        alan / 1000,
        [alan / 100, alan / 10000, 2 * (en + boy) / 1000],
        'Tarlanın alanı $en · $boy = $alan m² olur. 1 dekar = 1000 m² olduğundan '
            '$alan / 1000 = ${d(alan / 1000)} dekar bulunur.',
      );
    case 3:
      // x · y = 1000 iken yanıt z olur; bu yüzden ikinci varyant y'yi değiştirir.
      final x = 30 + 5 * a,
          y = 20 + 5 * (b % 10) + 50 * (w ~/ 2),
          z = 30 + 10 * (b ~/ 10) + (a % 2) * 5 + 20 * (w % 2);
      final hacim = x * y * z;
      // Üç boyut eşitse akvaryum küp olarak anlatılır.
      return ondalik(
        '${x == y && y == z ? 'Bir ayrıtının uzunluğu $x cm olan küp' : 'Boyutları $x cm, $y cm ve $z cm olan dikdörtgenler prizması'} '
            'biçimindeki bir akvaryum tamamen dolduğunda kaç litre su alır? '
            '(1 L = 1 dm³)',
        hacim / 1000,
        [hacim / 100, hacim / 10000, (x * y + y * z + x * z) * 2 / 1000],
        'Hacim $x · $y · $z = $hacim cm³ olur. 1 dm³ = 1000 cm³ ve 1 L = 1 dm³ '
            'olduğundan $hacim / 1000 = ${d(hacim / 1000)} L bulunur.',
      );
    case 4:
      final vv = (a + 25 * b + 3) / 10;
      return ondalik(
        'Hacmi ${d(vv)} m³ olan dikdörtgenler prizması biçimindeki bir su deposu '
            'tamamen dolduğunda kaç litre su alır? (1 L = 1 dm³)',
        vv * 1000,
        [vv * 100, vv * 10, vv * 10000],
        '1 m³ = 1000 dm³ ve 1 L = 1 dm³ olduğundan ${d(vv)} m³ = ${d(vv)} · 1000 = '
            '${d(vv * 1000)} L bulunur.',
      );
    case 5:
      final ml = const [200, 250, 400, 500, 750][a % 5];
      final adet = 12 + 2 * b + 40 * (a ~/ 5) + 200 * w;
      final litre = ml * adet / 1000;
      final kok =
          '${d(litre)} L zeytinyağı, her biri $ml mL alan şişelere dolduruluyor. '
          'Bu iş için kaç şişe gerekir?';
      // Şişe sayısı tam sayıdır; 1,2 ya da 0,012 gibi tam olmayan çeldiriciler
      // hemen elenir. Bu yüzden yalnız tam sayı çıkan hatalar kullanılır ve her
      // yanın listesinde önce gelir: küçük yanda 1 L = 100 mL sanmak ve bölmek
      // yerine çarpmak (litre · şişe hacmi), büyük yanda 1 L = 10000 mL sanmak;
      // ardından yakın çift sayılar. Yanıtın kaç çeldiriciden büyük olacağı
      // kökten seçilen hedefle belirlenir; böylece yanıt her sırada görülür.
      (double, String) yaz(int x) => (x.toDouble(), '$x');
      return secenekli(
        kok,
        '$adet',
        _dengeli(
          kok,
          adet.toDouble(),
          const [],
          const [],
          [
            ?_bol(adet, 10),
            ?_bol(adet * ml * ml, 1000000),
            for (var j = 1; j <= 8; j++)
              if (adet - 2 * j > 0) adet - 2 * j,
          ].map(yaz),
          [10 * adet, for (var j = 1; j <= 8; j++) adet + 2 * j].map(yaz),
        ),
        '${d(litre)} L = ${d(litre * 1000)} mL olur (1 L = 1000 mL). Şişe sayısı '
            '${d(litre * 1000)} / $ml = $adet bulunur.',
      );
    case 6:
      final hektarMi = b >= 10;
      // 1 dekar ya da 10 dekar gibi değerlerde yanıt verilen dönüşüm bilgisiyle
      // aynı olur; o zaman ikinci varyant kullanılır.
      final x = (1 + a + 25 * (b % 10) + 250 * w) / 2;
      final m2 = hektarMi ? x * 10000 : x * 1000;
      return ondalik(
        'Bir tarlanın ${d(x)} ${hektarMi ? 'hektar' : 'dekar'} büyüklüğündeki bölümüne '
            'buğday ekilmiştir. Bu bölümün alanı kaç metrekaredir? $_dekarBilgi',
        m2,
        [hektarMi ? x * 1000 : x * 10000, m2 / 10, m2 * 10],
        '1 ${hektarMi ? 'hektar = 10000' : 'dekar = 1000'} m² olduğundan ${d(x)} · '
            '${hektarMi ? 10000 : 1000} = ${d(m2)} m² bulunur.',
      );
    case 7:
      final en = 120 + 20 * a, boy = 150 + 25 * b;
      final alan = en * boy;
      // Kenarlar eşitse (200 cm ve 200 cm gibi) halı kare olarak anlatılır.
      return ondalik(
        '${en == boy ? 'Bir kenarının uzunluğu $en cm olan kare' : 'Kenar uzunlukları $en cm ve $boy cm olan dikdörtgen'} '
            'biçimli bir halının alanı kaç metrekaredir?',
        alan / 10000,
        [alan / 1000, alan / 100, 2 * (en + boy) / 100],
        'Halının alanı $en · $boy = $alan cm² olur. 1 m² = 10000 cm² olduğundan '
            '$alan / 10000 = ${d(alan / 10000)} m² bulunur.',
      );
    case 8:
      final ml = const [150, 200, 180, 250, 120][a % 5];
      final adet = 2 + a ~/ 5;
      final litre =
          (adet * ml + 100 * (1 + b) + 50 * (w % 2) + 2000 * (w ~/ 2)) / 1000;
      final kalan = (litre * 1000).round() - adet * ml;
      return ondalik(
        'Bir sürahide ${d(litre)} L su vardır. Bu sudan her biri $ml mL alan $adet '
            'bardak dolduruluyor. Sürahide kaç mL su kalır?',
        kalan.toDouble(),
        [litre * 100 - adet * ml, (litre * 1000 - ml), (adet * ml).toDouble()],
        '${d(litre)} L = ${(litre * 1000).round()} mL olur. Bardaklara $adet · $ml = '
            '${adet * ml} mL su konduğundan ${(litre * 1000).round()} − ${adet * ml} = '
            '$kalan mL su kalır.',
      );
    default:
      final hiz = const [20, 25, 40, 50, 80][a % 5];
      final dakika = 30 + 6 * (a ~/ 5) + 10 * b + 5 * (w % 2);
      final m3 = hiz * dakika / 1000;
      return ondalik(
        'Hacmi ${d(m3)} m³ olan boş bir depoya dakikada $hiz L su akıtan bir musluk '
            'açılıyor. Depo kaç dakikada dolar? (1 m³ = 1000 L)',
        dakika.toDouble(),
        [m3 * 100 / hiz, m3 * 10000 / hiz, dakika + 10.0],
        '${d(m3)} m³ = ${d(m3 * 1000)} L olur. Dolma süresi ${d(m3 * 1000)} / $hiz = '
            '$dakika dakika bulunur.',
      );
  }
}

// ---------------------------------------------------------------------------
// Aileler
// ---------------------------------------------------------------------------

final lmSayilar = <AdvancedFamily>[
  _sy(
    'asal_carpan',
    'Asal çarpanlar: bölen sayısı ve tam kare çarpanı',
    Difficulty.medium,
    BloomLevel.uygulama,
    _asalCarpanSoru,
  ),
  _sy(
    'faktoriyel',
    'Faktöriyel: sadeleştirme, sondaki sıfırlar, asal kuvveti',
    Difficulty.medium,
    BloomLevel.analiz,
    _faktoriyelSoru,
  ),
  _sy(
    'ardisik_toplam',
    'Ardışık sayıların toplamı ve terim sayısı',
    Difficulty.medium,
    BloomLevel.uygulama,
    _ardisikSoru,
  ),
  _sySirali(
    'tek_cift',
    'Tek-çift ve işaret özellikleri: daima doğru ifadeler',
    Difficulty.medium,
    BloomLevel.analiz,
    _tekCiftSoru,
  ),
  _sySirali(
    'siralama',
    'Kesir, ondalık, köklü ve üslü sayıları sıralama',
    Difficulty.medium,
    BloomLevel.analiz,
    _siralamaSoru,
  ),
  _sy(
    'bilimsel',
    'Bilimsel gösterim: dönüştürme, çarpma ve bölme',
    Difficulty.medium,
    BloomLevel.anlama,
    _bilimselSoru,
    shortAnswer: false,
  ),
  _sy(
    'aralik',
    'Sayı aralıklarında kesişim, birleşim ve fark',
    Difficulty.medium,
    BloomLevel.uygulama,
    _aralikSoru,
  ),
  _sy(
    'kartezyen',
    'Kartezyen çarpım: eleman sayısı ve koşullu ikililer',
    Difficulty.medium,
    BloomLevel.uygulama,
    _kartezyenSoru,
  ),
  _sy(
    'fonksiyon_sayisi',
    'Fonksiyon, bire bir ve sabit fonksiyon sayısı',
    Difficulty.hard,
    BloomLevel.analiz,
    _fonksiyonSayisiSoru,
  ),
  _sy(
    'fonksiyon_deger',
    'f(ax + b) biçimindeki fonksiyonda değer ve kural',
    Difficulty.medium,
    BloomLevel.uygulama,
    _fonksiyonDegerSoru,
    shortAnswer: false,
  ),
  _sy(
    'carpanlara_ayirma',
    'Çarpanlara ayırma ve özdeşliklerle hesaplama',
    Difficulty.easy,
    BloomLevel.uygulama,
    _carpanlaraAyirmaSoru,
  ),
  _sy(
    'rasyonel_ifade',
    'Rasyonel ifadeleri çarpanlara ayırarak sadeleştirme',
    Difficulty.medium,
    BloomLevel.uygulama,
    _rasyonelSoru,
    shortAnswer: false,
  ),
  _sy(
    'polinom_esitlik',
    'Polinom eşitliği ve çarpım polinomunun katsayıları',
    Difficulty.medium,
    BloomLevel.uygulama,
    _polinomEsitlikSoru,
  ),
  _sy(
    'polinom_bolme',
    'Polinom bölmesi: bölüm, katsayılar toplamı ve kalan',
    Difficulty.medium,
    BloomLevel.uygulama,
    _polinomBolmeSoru,
    shortAnswer: false,
  ),
  _sy(
    'ikinci_derece_kok',
    'İkinci dereceden denklemin kökleri ve kökler farkı',
    Difficulty.medium,
    BloomLevel.uygulama,
    _ikinciDereceSoru,
    shortAnswer: false,
  ),
  _sy(
    'isaret_tablosu',
    'İşaret tablosuyla çarpım ve bölüm eşitsizlikleri',
    Difficulty.hard,
    BloomLevel.analiz,
    _isaretSoru,
  ),
  _sySirali(
    'saat_aci',
    'Saat problemleri: akrep ile yelkovan arasındaki açı',
    Difficulty.medium,
    BloomLevel.analiz,
    _saatSoru,
    shortAnswer: true,
  ),
  _sy(
    'kalan_kesir',
    'Kesirli harcama ve kalan miktar problemleri',
    Difficulty.medium,
    BloomLevel.analiz,
    _kalanKesirSoru,
  ),
  _sy(
    'tren_tunel',
    'Tren, tünel ve köprü problemleri',
    Difficulty.medium,
    BloomLevel.uygulama,
    _trenSoru,
  ),
  _sy(
    'birim_donusum',
    'Uzunluk, alan, hacim ve sıvı ölçü birimleri dönüşümü',
    Difficulty.easy,
    BloomLevel.anlama,
    _birimSoru,
  ),
];
