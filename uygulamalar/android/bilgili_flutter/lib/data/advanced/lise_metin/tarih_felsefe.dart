// Lise tarih (12 olgu ailesi) ve felsefe-mantık (8 aile) metin soruları.
// Tarih ve felsefe aileleri olgu çizelgelerinden seçilen üçlülerle, mantık
// aileleri kurala göre kurulan önermelerle her biri 5.000 ayrı kök verir.
import 'ortak.dart';

// ───────────────────────────── Ortak yardımcılar ─────────────────────────────

const _rakam = ['I', 'II', 'III'];

String _liste(List<String> x) => 'I. ${x[0]}\nII. ${x[1]}\nIII. ${x[2]}\n';

/// İlk harfi Türkçe kurala göre büyütür (i → İ, ı → I).
String _buyuk(String s) {
  final h = s[0];
  return '${h == 'i' ? 'İ' : (h == 'ı' ? 'I' : h.toUpperCase())}${s.substring(1)}';
}

String _altkume(int maske) => switch (maske) {
  1 => 'Yalnız I',
  2 => 'Yalnız II',
  4 => 'Yalnız III',
  3 => 'I ve II',
  5 => 'I ve III',
  6 => 'II ve III',
  _ => 'I, II ve III',
};

/// Öncüllü soru: doğru yanıt [maske] alt kümesidir (bit 0 → I).
AdvancedItem _oncullu(String kok, int maske, int j, String aciklama) {
  const hepsi = [1, 2, 4, 3, 5, 6, 7];
  final kay = j % 7;
  return secenekli(
    kok,
    _altkume(maske),
    [for (var k = 0; k < 7; k++) hepsi[(kay + k) % 7]]
        .where((x) => x != maske)
        .map(_altkume),
    aciklama,
  );
}

/// Değerleri birbirinden farklı olan öge üçlülerinin sıra numaraları.
List<List<int>> _farkliUcluler(List<int> d) {
  final n = d.length;
  return [
    for (var x = 0; x < n; x++)
      for (var y = x + 1; y < n; y++)
        if (d[x] != d[y])
          for (var z = y + 1; z < n; z++)
            if (d[z] != d[x] && d[z] != d[y]) [x, y, z],
  ];
}

List<List<int>> _tumUcluler(int n) => [
  for (var x = 0; x < n; x++)
    for (var y = x + 1; y < n; y++)
      for (var z = y + 1; z < n; z++) [x, y, z],
];

/// i. vakanın [dongu] içindeki biçimi, o biçimdeki sırası (j) ve o biçimi
/// kullanan vaka sayısı (m). Biçim içinde liste [_dilim] ile seçilir.
(int, int, int) _bicim(int i, List<int> dongu) {
  final l = dongu.length, r = i % l, b = dongu[r];
  var once = 0, adet = 0, artik = 0;
  for (var k = 0; k < l; k++) {
    if (dongu[k] != b) continue;
    if (k < r) once++;
    if (k < lmAileBoyu % l) artik++;
    adet++;
  }
  return (b, i ~/ l * adet + once, lmAileBoyu ~/ l * adet + artik);
}

/// j ∈ [0, m) için eşit aralıklı seçim; liste en az m uzunluktaysa her j
/// farklı öge alır.
T _dilim<T>(List<T> l, int j, int m) => l[j * l.length ~/ m];

/// Önerme sorusunda gösterilecek değerler ve doğru önermelerin maskesi.
/// İstenen [maske] dışındaki konumlar doğru değerden ve [yasak] maskesindeki
/// değerlerden farklı (olabildiğince de gösterilenlerden farklı) bir değer alır;
/// uygun değer yoksa o konum doğru bırakılır.
(List<int>, int) _gosterilen(
  List<int> dogru,
  int maske,
  int n,
  List<int> yasak,
  int kay,
) {
  final g = [for (var j = 0; j < 3; j++) (maske >> j) & 1 == 1 ? dogru[j] : -1];
  for (var j = 0; j < 3; j++) {
    if (g[j] >= 0) continue;
    int? ilk, farkli;
    for (var k = 0; k < n && farkli == null; k++) {
      final v = (kay + 3 * j + k) % n;
      if (v == dogru[j] || (yasak[j] >> v) & 1 == 1) continue;
      ilk ??= v;
      if (!g.contains(v)) farkli = v;
    }
    g[j] = farkli ?? ilk ?? dogru[j];
  }
  var m = 0;
  for (var j = 0; j < 3; j++) {
    if (g[j] == dogru[j]) m |= 1 << j;
  }
  return (g, m);
}

/// Olgu çizelgesinden üç biçimli soru: 0 sıralı eşleştirme (değerleri farklı
/// üçlüler), 1 “hangileri X'e aittir / X'te gerçekleşmiştir”, 2 doğru önermeleri
/// seçme. Çizelge ögesi (öge, değer, yasak maske) biçimindedir; yasak maske,
/// ögenin tartışmalı biçimde yakıştırılabileceği değerleri işaretler.
///
/// Olağan kipte öge, değer adıyla başlayan cümlenin yüklemidir ve değerin ikinci
/// adı yönelme hâlidir (“Sümerlere”). [donem] kipinde öge bir gelişmedir, değerin
/// ikinci adı bulunma hâlidir (“Tanzimat Dönemi'nde”) ve önerme “öge + değer +
/// gerçekleşmiştir” biçimini alır.
class _Ozneli {
  _Ozneli(
    this.tablo,
    this.ozne,
    this.dongu, {
    required this.sirali,
    required this.hangileri,
    required this.onerme,
    this.donem = false,
    this.kronolojik = false,
    this.fiil = 'aittir',
    this.sifat = 'ait olanlar',
    this.grup,
    this.oge = 'bilgi',
    this.ogeYaz,
    this.onermeYaz,
    this.ozetYaz,
    this.dokumYaz,
    this.siraliYaz,
  });

  final List<(String, int, int)> tablo;
  final List<(String, String)> ozne;
  final List<int> dongu;
  final String sirali, onerme;
  final String Function(String ikinciAd) hangileri;
  final bool donem;

  /// Değerler zaman sırasıyla dizilmişse (dönemler, yıllar) sıralı biçimdeki
  /// çeldiricilerden biri doğru yanıtın zaman sırasını korur; böylece yalnız
  /// olayların birbirine göre sırasını bilen öğrenci yanıtı bulamaz.
  final bool kronolojik;

  /// İsteğe bağlı: sıralı biçimin soru cümlesini doğru değerlere göre kurar.
  final String Function(List<int> degerler)? siraliYaz;

  /// Olağan kipte açıklamanın yüklemi (“aittir”, “ilgilidir”) ve sıfat biçimi.
  final String fiil, sifat;

  /// Açıklamada ögeyi anan sözcük (“bilgi”, “görüş”, “tanım”).
  final String oge;

  /// İsteğe bağlı biçimlendiriciler: liste ögesi, önerme, ikinci biçimin
  /// açıklama etiketi ve açıklamadaki “öge: değer” dökümü.
  final String Function(String oge)? ogeYaz;
  final String Function(String oge, (String, String) deger)? onermeYaz;
  final String Function((String, String) deger)? ozetYaz;
  final String Function(String oge, (String, String) deger)? dokumYaz;

  bool get _dokumlu => donem || dokumYaz != null;

  /// Değerlerin öbekleri: yanlış önerme ve çeldirici yalnız aynı öbekten
  /// değer kullanır (ör. partiler ile olaylar birbirine karıştırılmaz).
  final List<int>? grup;

  /// Yanlış önerme ve komşu değerli çeldiricide kullanılmayacak değerler.
  int _yasak((String, int, int) e) {
    final gr = grup;
    if (gr == null) return e.$3;
    var m = e.$3;
    for (var v = 0; v < gr.length; v++) {
      if (gr[v] != gr[e.$2]) m |= 1 << v;
    }
    return m;
  }

  // Sıralı biçim için en az üç kesin yanlış dizilim bırakan üçlüler.
  late final List<List<int>> farkli = [
    for (final t in _farkliUcluler([for (final e in tablo) e.$2]))
      if (ucluDizilimler
              .skip(1)
              .where((p) => _kesinYanlis([for (final k in t) tablo[k]], p))
              .length >=
          3)
        t,
  ];
  late final List<List<int>> tum = [
    for (final t in _tumUcluler(tablo.length))
      if (_sorulabilir([for (final k in t) tablo[k]]).isNotEmpty) t,
  ];

  /// İkinci biçimde tartışmasız sorulabilecek değerler.
  static List<int> _sorulabilir(List<(String, int, int)> x) => [
    for (final s in {for (final e in x) e.$2})
      if (x.every((e) => e.$2 == s || (e.$3 >> s) & 1 == 0)) s,
  ];

  /// Dizilimin taşıdığı konumlardan en az biri tartışmasız yanlış mı?
  static bool _kesinYanlis(List<(String, int, int)> x, List<int> p) => [
    for (var k = 0; k < 3; k++)
      if (p[k] != k) (x[k].$3 >> x[p[k]].$2) & 1 == 0,
  ].any((y) => y);

  String _dokum(List<(String, int, int)> x) => _dokumlu
      ? '${[for (final e in x) dokumYaz?.call(e.$1, ozne[e.$2]) ?? '${e.$1}: ${ozne[e.$2].$1}'].join('; ')}.'
      : 'I. $oge ${ozne[x[0].$2].$2}, II. $oge ${ozne[x[1].$2].$2}, '
            'III. $oge ${ozne[x[2].$2].$2} $fiil.';

  /// Sıralı biçimin dengeli çeldiricileri: her konumda iki aday değer ikişer
  /// seçenekte geçer; böylece seçeneklerin birbirine benzerliği (konum
  /// uyuşması, öge kümesi, örtüşme) doğru yanıtı ele vermez. Kurgular:
  /// A) her çeldirici iki konumu vakada bulunmayan, kesin yanlış komşu
  ///    değerlerle değiştirir (üç ayrı komşu değer gerekir);
  /// B) iki ögenin yer değiştirmesi, üçüncü konumun komşu bir değerle
  ///    değiştirilmesi ve ikisinin birlikte uygulanması;
  /// C) yalnız dizilim: iki yer değiştirme ve bir döngü.
  /// Uygun kurgu yoksa null döner.
  List<List<int>>? _dengeliCeldirici(
    List<(String, int, int)> x,
    List<int> d,
    int kay,
  ) {
    final yon = kay.isEven ? const [1, -1] : const [-1, 1];
    // Konumun vakada bulunmayan, kesin yanlış değerleri; yakından uzağa.
    final aday = [
      for (var k = 0; k < 3; k++)
        [
          for (var a = 1; a < ozne.length; a++)
            for (final s in yon)
              if (d[k] + s * a >= 0 &&
                  d[k] + s * a < ozne.length &&
                  !d.contains(d[k] + s * a) &&
                  (_yasak(x[k]) >> (d[k] + s * a)) & 1 == 0)
                d[k] + s * a,
        ],
    ];
    bool duzen(List<int> v) {
      for (var p = 0; p < 3; p++) {
        for (var q = p + 1; q < 3; q++) {
          if ((v[p] < v[q]) != (d[p] < d[q])) return false;
        }
      }
      return true;
    }

    List<int> koy(List<int> v, int k, int deger) => [
      for (var q = 0; q < 3; q++) q == k ? deger : v[q],
    ];

    List<List<int>>? kurguA(bool sirayiKoru) {
      final ilk = [for (final l in aday) l.take(6).toList()];
      for (final x0 in ilk[0]) {
        for (final x1 in ilk[1]) {
          for (final x2 in ilk[2]) {
            if (x0 == x1 || x0 == x2 || x1 == x2) continue;
            final c = [
              [d[0], x1, x2],
              [x0, d[1], x2],
              [x0, x1, d[2]],
            ];
            if (sirayiKoru && !c.any(duzen)) continue;
            return c;
          }
        }
      }
      return null;
    }

    List<List<int>>? kurguB(bool sirayiKoru) {
      final gr = grup;
      for (final ayniObek in const [true, false]) {
        for (var t = 0; t < 3; t++) {
          final r = (kay + t) % 3, p = (r + 1) % 3, q = (r + 2) % 3;
          // Yer değiştirmede en az bir konum kesin yanlış olmalıdır.
          if ((x[p].$3 >> d[q]) & 1 == 1 && (x[q].$3 >> d[p]) & 1 == 1) {
            continue;
          }
          if (ayniObek && gr != null && gr[d[p]] != gr[d[q]]) continue;
          final takas = [
            for (var k = 0; k < 3; k++) k == p ? d[q] : (k == q ? d[p] : d[k]),
          ];
          for (final v in aday[r]) {
            final tek = koy(d, r, v);
            if (sirayiKoru && !duzen(tek)) continue;
            return [tek, takas, koy(takas, r, v)];
          }
        }
      }
      return null;
    }

    List<List<int>>? kurguC() {
      final yer = [
        for (final p in const [
          [0, 2, 1],
          [2, 1, 0],
          [1, 0, 2],
        ])
          if (_kesinYanlis(x, p)) p,
      ];
      final don = [
        for (final p in const [
          [1, 2, 0],
          [2, 0, 1],
        ])
          if (_kesinYanlis(x, p)) p,
      ];
      if (yer.length < 2 || don.isEmpty) return null;
      final a = kay % yer.length;
      return [
        for (final p in [
          yer[a],
          yer[(a + 1) % yer.length],
          don[kay % don.length],
        ])
          [for (final k in p) d[k]],
      ];
    }

    final sira = kronolojik
        ? [
            () => kurguB(true),
            () => kurguA(true),
            () => kurguB(false),
            () => kurguA(false),
            kurguC,
          ]
        : kay.isEven
        ? [() => kurguA(false), () => kurguB(false), kurguC]
        : [() => kurguB(false), () => kurguA(false), kurguC];
    for (final f in sira) {
      final c = f();
      if (c != null) return c;
    }
    return null;
  }

  AdvancedItem call(int i) {
    final (b, j, m) = _bicim(i, dongu);
    final u = _dilim(b == 0 ? farkli : tum, j, m);
    final x = [for (final k in ucluDizilimler[j % 6]) tablo[u[k]]];
    final d = [for (final e in x) e.$2];
    final liste = _liste([
      for (final e in x) ogeYaz?.call(e.$1) ?? (donem ? e.$1 : _buyuk(e.$1)),
    ]);
    if (b == 0) {
      String yaz(List<int> v) => [for (final k in v) ozne[k].$1].join(' – ');
      final kay = j ~/ 6;
      final secilen = _dengeliCeldirici(x, d, kay);
      // Yedek: bir konumun değerini vakada bulunmayan komşu bir değerle
      // değiştiren iki seçenek ve bir dizilim. Taşınan her konumu tartışmalı
      // kalan dizilim çeldirici olamaz.
      final diz = [
        for (final p in ucluDizilimler.skip(1))
          if (_kesinYanlis(x, p)) [for (final k in p) d[k]],
      ];
      final adim = kay.isEven
          ? const [1, -1, 2, -2, 3, -3]
          : const [-1, 1, -2, 2, -3, 3];
      final degisik = <List<int>>[];
      for (var t = 0; t < 3; t++) {
        final k = (kay + t) % 3;
        for (final a in adim) {
          final v = d[k] + a;
          if (v < 0 || v >= ozne.length || d.contains(v)) continue;
          if ((_yasak(x[k]) >> v) & 1 == 1) continue;
          degisik.add([for (var q = 0; q < 3; q++) q == k ? v : d[q]]);
          break;
        }
      }
      return secenekli('$liste${siraliYaz?.call(d) ?? sirali}', yaz(d), [
        if (secilen != null)
          for (final v in secilen) yaz(v),
        if (diz.isNotEmpty) yaz(diz[kay % diz.length]),
        for (final v in degisik) yaz(v),
        for (var t = 1; t < diz.length; t++) yaz(diz[(kay + t) % diz.length]),
      ], _dokum(x));
    }
    if (b == 1) {
      final adaylar = _sorulabilir(x);
      final s = adaylar[j % adaylar.length];
      var maske = 0;
      for (var k = 0; k < 3; k++) {
        if (d[k] == s) maske |= 1 << k;
      }
      return _oncullu(
        '$liste${hangileri(ozne[s].$2)}',
        maske,
        j ~/ 3,
        '${_dokum(x)} ${_buyuk(ozetYaz?.call(ozne[s]) ?? '${ozne[s].$2} ${donem ? 'gerçekleşenler' : sifat}')}: '
            '${_altkume(maske)}.',
      );
    }
    final (g, maske) = _gosterilen(d, 1 + j % 7, ozne.length, [
      for (final e in x) _yasak(e),
    ], j ~/ 7);
    final onermeler = [
      for (var k = 0; k < 3; k++)
        onermeYaz?.call(x[k].$1, ozne[g[k]]) ??
            (donem
                ? '${x[k].$1} ${ozne[g[k]].$2} gerçekleşmiştir.'
                : '${ozne[g[k]].$1} ${x[k].$1}'),
    ];
    final yorum = _dokumlu
        ? _dokum(x)
        : [
            for (var k = 0; k < 3; k++)
              g[k] == d[k]
                  ? '${_rakam[k]}. $oge doğrudur.'
                  : '${_rakam[k]}. $oge ${ozne[g[k]].$2} değil ${ozne[d[k]].$2} $fiil.',
          ].join(' ');
    return _oncullu(
      '${_liste(onermeler)}$onerme',
      maske,
      j ~/ 3,
      '$yorum Doğru olanlar: ${_altkume(maske)}.',
    );
  }
}

// ─────────────────────── 1 · İlk Çağ uygarlıkları ───────────────────────────

// (ad, yönelme hâli)
const _uygarlik = [
  ('Sümerler', 'Sümerlere'),
  ('Mısırlılar', 'Mısırlılara'),
  ('Babilliler', 'Babillilere'),
  ('Hititler', 'Hititlere'),
  ('Lidyalılar', 'Lidyalılara'),
  ('Fenikeliler', 'Fenikelilere'),
  ('İyonlar', 'İyonlara'),
  ('Urartular', 'Urartulara'),
  ('Persler', 'Perslere'),
  ('Çinliler', 'Çinlilere'),
  ('Hintliler', 'Hintlilere'),
  ('Romalılar', 'Romalılara'),
  ('Yunanlılar', 'Yunanlılara'),
];

// (bilgi, uygarlık, yanlış önermede kullanılmayacak uygarlıkların bit maskesi).
// Bilgi, uygarlık adıyla başlayan cümlenin yüklemidir. Maskeler, bilginin
// tartışmaya açık biçimde başka bir uygarlığa da yakıştırılabileceği durumları
// (ör. İyonlar ile Yunanlılar) dışarıda bırakır.
const _ilkCag = <(String, int, int)>[
  ('çivi yazısını bulmuşlardır.', 0, 1 << 2 | 1 << 3),
  (
    'ziggurat adı verilen ve gözlemevi olarak da kullanılan tapınaklar yapmışlardır.',
    0,
    0,
  ),
  ("Urkagina Kanunları'nı hazırlamışlardır.", 0, 0),
  ('ay yılı esaslı takvimi bulmuşlardır.', 0, 1 << 2),
  ('Ur, Uruk ve Lagaş şehir devletlerini kurmuşlardır.', 0, 0),
  ('güneş yılı esaslı takvimi bulmuşlardır.', 1, 1 << 11),
  ('ölülerini mumyalayarak saklamışlardır.', 1, 0),
  ('Ölüler Kitabı adlı dinî metinleri yazmışlardır.', 1, 0),
  ('firavun adı verilen hükümdarlarca yönetilmişlerdir.', 1, 0),
  (
    "Nil Nehri'nin taşkınlarından sonra tarlaları yeniden ölçmek için geometriyi geliştirmişlerdir.",
    1,
    0,
  ),
  ("Gize'deki Keops Piramidi'ni yapmışlardır.", 1, 0),
  ("Hammurabi Kanunları'nı hazırlamışlardır.", 2, 0),
  ("Asma Bahçeleri'ni yapmışlardır.", 2, 0),
  ("Mısırlılarla Kadeş Antlaşması'nı imzalamışlardır.", 3, 1 << 1),
  ('Pankuş adı verilen bir meclise sahip olmuşlardır.', 3, 0),
  ('kraliçelerine Tavananna unvanını vermişlerdir.', 3, 0),
  ("Hattuşa'yı başkent yapmışlardır.", 3, 0),
  (
    'fethettikleri yerlerin tanrılarını da benimsedikleri için bin tanrılı halk olarak anılmışlardır.',
    3,
    0,
  ),
  (
    'krallarının yaptıklarını Anal adı verilen yıllıklara kaydetmişlerdir.',
    3,
    1 << 1,
  ),
  (
    'kanunlarında kısas yerine çoğunlukla tazminat cezasına yer vermişlerdir.',
    3,
    1 | 1 << 11,
  ),
  ('parayı ilk kez kullanmışlardır.', 4, 1 << 9),
  ("Sardes'i başkent yapmışlardır.", 4, 1 << 8),
  ('yirmi iki harften oluşan alfabeyi geliştirmişlerdir.', 5, 0),
  ('Kartaca kolonisini kurmuşlardır.', 5, 0),
  ('Sur, Sayda ve Biblos şehir devletlerini kurmuşlardır.', 5, 0),
  ('Milet Okulu filozoflarını yetiştirmişlerdir.', 6, 1 << 12),
  (
    'Batı Anadolu kıyısındaki Milet, Efes ve Foça şehirlerini kurmuşlardır.',
    6,
    1 << 3 | 1 << 4 | 1 << 8 | 1 << 11 | 1 << 12,
  ),
  ("Van Gölü kıyısındaki Tuşpa'yı başkent yapmışlardır.", 7, 0),
  ("Menua (Şamran) Kanalı'nı yapmışlardır.", 7, 0),
  (
    'ülkelerini satraplık adı verilen eyaletlere ayırarak yönetmişlerdir.',
    8,
    0,
  ),
  ('Zerdüşt dinini benimsemişlerdir.', 8, 0),
  ('kâğıdı icat etmişlerdir.', 9, 0),
  ('pusulayı icat etmişlerdir.', 9, 0),
  ("Hun akınlarına karşı Çin Seddi'ni inşa etmişlerdir.", 9, 0),
  ("Konfüçyüs'ün ahlak öğretisini benimsemişlerdir.", 9, 0),
  ('sıfır rakamını bulmuşlardır.', 10, 1 << 2),
  ('toplumu kast sistemine göre katmanlara ayırmışlardır.', 10, 0),
  ('Vedalar adlı kutsal metinleri oluşturmuşlardır.', 10, 0),
  ("On İki Levha Kanunları'nı hazırlamışlardır.", 11, 0),
  ('Jülyen takvimini kullanmaya başlamışlardır.', 11, 1 << 1),
  ('Latin alfabesini geliştirmişlerdir.', 11, 0),
  ("Kolezyum adlı büyük amfitiyatroyu Roma'da yapmışlardır.", 11, 0),
  ('senato ve konsüllerle yönetilen bir cumhuriyet kurmuşlardır.', 11, 1 << 5),
  ('ilk olimpiyat oyunlarını düzenlemişlerdir.', 12, 0),
  ("Atina'da doğrudan demokrasiyi uygulamışlardır.", 12, 0),
  ("Sparta'da askerî bir yönetim kurmuşlardır.", 12, 0),
  ("Sokrates ve Platon'u yetiştirmişlerdir.", 12, 1 << 6),
];

final _ilkCagOlgu = _Ozneli(
  _ilkCag,
  _uygarlik,
  const [0, 1, 2],
  sirali:
      'Bu bilgilerin ait olduğu İlk Çağ uygarlıkları sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
  hangileri: (s) =>
      'İlk Çağ uygarlıklarına ait bu bilgilerden hangileri $s aittir?',
  onerme: 'İlk Çağ uygarlıklarıyla ilgili bu bilgilerden hangileri doğrudur?',
);

// ─────────────────── 2 · Hz. Muhammed ve Dört Halife Dönemi ─────────────────

const _donem = [
  ('Hz. Muhammed', 'Hz. Muhammed döneminde'),
  ('Hz. Ebubekir', 'Hz. Ebubekir döneminde'),
  ('Hz. Ömer', 'Hz. Ömer döneminde'),
  ('Hz. Osman', 'Hz. Osman döneminde'),
  ('Hz. Ali', 'Hz. Ali döneminde'),
];

const _islam = <(String, int, int)>[
  ('Bedir Savaşı', 0, 0),
  ('Uhud Savaşı', 0, 0),
  ('Hendek Savaşı', 0, 0),
  ("Hudeybiye Antlaşması'nın imzalanması", 0, 0),
  ("Hayber'in fethedilmesi", 0, 0),
  ('Mute Savaşı', 0, 0),
  ("Mekke'nin fethedilmesi", 0, 0),
  ('Huneyn Savaşı', 0, 0),
  ('Tebük Seferi', 0, 0),
  ("Medine Sözleşmesi'nin yapılması", 0, 0),
  ('Akabe Biatları', 0, 0),
  ('Veda Haccı', 0, 0),
  ('Ridde (dinden dönme) olaylarının bastırılması', 1, 0),
  ("Yemame Savaşı'nda yalancı peygamber Müseylime'nin yenilmesi", 1, 0),
  ("Kur'an-ı Kerim'in kitap hâlinde bir araya getirilmesi", 1, 0),
  ('Zekât vermeyi reddeden kabilelerle mücadele edilmesi', 1, 0),
  ('Kadisiye Savaşı', 2, 0),
  ('Yermük Savaşı', 2, 0),
  ('Nihavend Savaşı', 2, 0),
  ("Kudüs'ün alınması", 2, 0),
  ("Mısır'ın fethedilmesi", 2, 0),
  ('Hicri takvimin kabul edilmesi', 2, 0),
  ('Divan teşkilatının kurulması', 2, 0),
  ('Basra ve Kûfe şehirlerinin kurulması', 2, 0),
  ("Emirü'l-müminin unvanının ilk kez kullanılması", 2, 0),
  ("Kur'an-ı Kerim'in çoğaltılarak eyaletlere gönderilmesi", 3, 0),
  ("Kıbrıs'a ilk İslam seferinin düzenlenmesi", 3, 0),
  ("Zatü's-Sevari Deniz Savaşı", 3, 0),
  ('İlk İslam donanmasının kurulması', 3, 0),
  ('Cemel Vakası', 4, 0),
  ('Sıffin Savaşı', 4, 0),
  ('Hakem Olayı', 4, 0),
  ('Nehrevan Savaşı', 4, 0),
  ("Başkentin Medine'den Kûfe'ye taşınması", 4, 0),
  ('Haricilerin ortaya çıkması', 4, 0),
];

final _islamOlgu = _Ozneli(
  _islam,
  _donem,
  const [0, 1, 2],
  donem: true,
  sirali: 'İslam tarihine ait bu gelişmeler sırasıyla kimlerin döneminde gerçekleşmiştir?',
  hangileri: (s) =>
      'İslam tarihine ait bu gelişmelerden hangileri $s gerçekleşmiştir?',
  onerme: 'İslam tarihine ait bu bilgilerden hangileri doğrudur?',
);

// ───────────── 3 · Emeviler, Abbasiler ve Endülüs Emevileri ─────────────────

const _emeviOzne = [
  ('Emevi Devleti', "Emevi Devleti'ne"),
  ('Abbasi Devleti', "Abbasi Devleti'ne"),
  ('Endülüs Emevi Devleti', "Endülüs Emevi Devleti'ne"),
];

// Dönemleri örtüştüğü için bilgiler zamana değil devlete bağlanır. Maskeler,
// Endülüs Emevilerinde de tartışılabilecek uygulamaları işaretler.
const _emevi = <(String, int, int)>[
  (
    'halifeliği babadan oğula geçen bir saltanata dönüştürmüştür.',
    0,
    1 << 1 | 1 << 2,
  ),
  ("Şam'ı başkent yapmıştır.", 0, 0),
  ('döneminde Kerbela Olayı yaşanmıştır.', 0, 0),
  (
    'Arap olmayan Müslümanları mevali olarak ikinci sınıf saymıştır.',
    0,
    1 << 2,
  ),
  ('Abdülmelik döneminde Arapçayı resmî dil yapmıştır.', 0, 0),
  ("Kudüs'te Kubbetü's-Sahra'yı yaptırmıştır.", 0, 0),
  ("İstanbul'u kuşatan ilk Müslüman devlet olmuştur.", 0, 0),
  ("Tarık bin Ziyad komutasında İspanya'ya geçmiştir.", 0, 0),
  ("Puvatya (Tours) Savaşı'nda Franklara yenilmiştir.", 0, 0),
  ("Kuteybe bin Müslim komutasında Maveraünnehir'i fethetmiştir.", 0, 0),
  ("Kuzey Afrika'da Kayrevan şehrini kurmuştur.", 0, 0),
  ('Muhammed bin Kasım komutasında Sind bölgesini fethetmiştir.', 0, 0),
  ("Talas Savaşı'nda Çinlileri yenmiştir.", 1, 0),
  ('Bağdat şehrini kurarak başkent yapmıştır.', 1, 0),
  ("Bağdat'ta Beytü'l-Hikme'yi kurmuştur.", 1, 0),
  ('Türk askerleri için Samerra şehrini kurmuştur.', 1, 0),
  (
    'tercüme faaliyetleriyle Antik Yunan eserlerini Arapçaya kazandırmıştır.',
    1,
    1 << 2,
  ),
  ('Arap olmayan Müslümanlara eşit davranmıştır.', 1, 1 << 2),
  ('Harun Reşid döneminde en parlak çağını yaşamıştır.', 1, 0),
  ("Moğol hükümdarı Hülagü'nün Bağdat'ı almasıyla yıkılmıştır.", 1, 0),
  ('Tuğrul Bey sayesinde Büveyhoğullarının baskısından kurtulmuştur.', 1, 0),
  ('Türk komutanlara orduda ve yönetimde geniş görevler vermiştir.', 1, 0),
  ("Abdurrahman bin Muaviye tarafından İspanya'da kurulmuştur.", 2, 0),
  ("Kurtuba'yı başkent yapmıştır.", 2, 0),
  ("Kurtuba Ulu Camii'ni yaptırmıştır.", 2, 0),
  ("Kurtuba'daki medreselerde Avrupalı öğrencilere eğitim vermiştir.", 2, 0),
  ('929 yılında halifeliğini ilan etmiştir.', 2, 0),
  ("Kurtuba yakınlarında Medinetü'z-Zehra sarayını yaptırmıştır.", 2, 0),
  (
    "İslam bilim ve kültürünün Avrupa'ya geçmesinde köprü görevi görmüştür.",
    2,
    1 | 1 << 1,
  ),
  ('1031 yılında küçük beyliklere bölünerek dağılmıştır.', 2, 0),
];

// Özneleri farklı üçlü sayısı (12 · 10 · 8 = 960) sıralı biçime 834 vaka verir.
final _emeviOlgu = _Ozneli(
  _emevi,
  _emeviOzne,
  const [0, 1, 2, 1, 2, 1],
  sirali:
      'Bu bilgilerin ait olduğu İslam devletleri sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
  hangileri: (s) => 'Bu bilgilerden hangileri $s aittir?',
  onerme:
      'Emeviler, Abbasiler ve Endülüs Emevileriyle ilgili bu bilgilerden hangileri '
      'doğrudur?',
);

// ─────────────────────── 4 · Türk-İslam bilginleri ──────────────────────────

const _bilgin = [
  ('Farabi', "Farabi'ye"),
  ('İbn-i Sina', "İbn-i Sina'ya"),
  ('Biruni', "Biruni'ye"),
  ('Harezmi', "Harezmi'ye"),
  ('Kaşgarlı Mahmut', "Kaşgarlı Mahmut'a"),
  ('Yusuf Has Hacip', "Yusuf Has Hacip'e"),
  ('Ahmet Yesevi', "Ahmet Yesevi'ye"),
  ('Nizamülmülk', "Nizamülmülk'e"),
  ('Uluğ Bey', "Uluğ Bey'e"),
  ('Ali Kuşçu', "Ali Kuşçu'ya"),
  ('İmam Maturidi', "İmam Maturidi'ye"),
  ('Gazali', "Gazali'ye"),
  ('Ömer Hayyam', "Ömer Hayyam'a"),
  ('Edip Ahmet Yükneki', "Edip Ahmet Yükneki'ye"),
  ('Akşemseddin', "Akşemseddin'e"),
  ('Piri Reis', "Piri Reis'e"),
  ('Katip Çelebi', "Katip Çelebi'ye"),
  ('Takiyüddin', "Takiyüddin'e"),
];

// Maskeler: Ali Kuşçu Uluğ Bey'in gözlemevinde ve zicinde çalışmış, Akşemseddin
// fetihte Fatih'in yanında bulunmuş, Piri Reis ile Katip Çelebi de dünya haritası
// çizmiştir; Gazali'nin İhya'sında da Kitabü't-Tevhid adlı bir bölüm vardır.
const _bilginOlgu = <(String, int, int)>[
  ("El-Medinetü'l-Fazıla (Erdemli Şehir) adlı eseri yazmıştır.", 0, 0),
  (
    "Aristoteles'ten sonra Muallim-i Sani (İkinci Öğretmen) olarak anılmıştır.",
    0,
    0,
  ),
  ("Kitabü'l-Musiki'l-Kebir adlı müzik eserini yazmıştır.", 0, 0),
  ("El-Kanun fi't-Tıb adlı tıp eserini yazmıştır.", 1, 0),
  ("Kitabü'ş-Şifa adlı felsefe eserini yazmıştır.", 1, 0),
  ("Batı'da Avicenna adıyla tanınmıştır.", 1, 0),
  ("Tahkiku ma li'l-Hind adlı eserinde Hint kültürünü incelemiştir.", 2, 0),
  ("El-Kanunü'l-Mesudi adlı eserini Gazneli Sultan Mesut'a sunmuştur.", 2, 0),
  (
    "El-Âsârü'l-Bâkiye adlı eserinde çeşitli milletlerin takvimlerini karşılaştırmıştır.",
    2,
    0,
  ),
  ("El-Cebr ve'l-Mukabele adlı eseriyle cebirin temellerini atmıştır.", 3, 0),
  ('adı Batı dillerinde algoritma kavramına kaynaklık etmiştir.', 3, 0),
  ('Kitabu Sureti\'l-Arz adlı coğrafya eserini yazmıştır.', 3, 0),
  ("Divanü Lügati't-Türk'ü yazmıştır.", 4, 0),
  ('bilinen ilk Türk dünya haritasını çizmiştir.', 4, 1 << 15),
  ('Araplara Türkçe öğretmek amacıyla bir sözlük hazırlamıştır.', 4, 0),
  ("Kutadgu Bilig'i yazmıştır.", 5, 0),
  ("eserini Karahanlı hükümdarı Tabgaç Buğra Han'a sunmuştur.", 5, 0),
  ("Divan-ı Hikmet'i yazmıştır.", 6, 0),
  ('Yesevilik tarikatını kurmuştur.', 6, 0),
  ('Pir-i Türkistan olarak anılmıştır.', 6, 0),
  ("Siyasetname'yi yazmıştır.", 7, 0),
  ('Nizamiye Medreselerini kurmuştur.', 7, 0),
  ('Alp Arslan ve Melikşah dönemlerinde vezirlik yapmıştır.', 7, 0),
  ("Semerkant'ta bir gözlemevi kurmuştur.", 8, 1 << 9),
  ('Zic-i Cedid-i Sultani adlı yıldız cetvelini hazırlatmıştır.', 8, 1 << 9),
  ('hem Timurlu hükümdarı hem de gökbilimci olarak tanınmıştır.', 8, 0),
  ("Fatih Sultan Mehmet'in daveti üzerine İstanbul'a gelmiştir.", 9, 1 << 14),
  ('Fethiye adlı astronomi eserini yazmıştır.', 9, 0),
  ('Muhammediye adlı matematik eserini yazmıştır.', 9, 0),
  ('Maturidilik adıyla bilinen itikadi mezhebin kurucusudur.', 10, 0),
  ("Kitabü't-Tevhid adlı eseri yazmıştır.", 10, 1 << 11),
  ("İhyau Ulumi'd-Din adlı eseri yazmıştır.", 11, 0),
  ("Tehafütü'l-Felasife adlı eserinde filozofları eleştirmiştir.", 11, 0),
  ("Bağdat Nizamiye Medresesi'nde müderrislik yapmıştır.", 11, 0),
  ("Celali Takvimi'ni hazırlayan heyete başkanlık etmiştir.", 12, 0),
  ('Rubailer adıyla bilinen dörtlükleri yazmıştır.', 12, 0),
  ("Atabetü'l-Hakayık adlı eseri yazmıştır.", 13, 0),
  ("Maddetü'l-Hayat adlı tıp eserini yazmıştır.", 14, 0),
  ("Fatih Sultan Mehmet'in hocalığını yapmıştır.", 14, 1 << 9),
  ('Kitab-ı Bahriye adlı denizcilik eserini yazmıştır.', 15, 0),
  ('Amerika kıtasını da gösteren bir dünya haritası çizmiştir.', 15, 1 << 16),
  ("Keşfü'z-Zunun adlı bibliyografya eserini yazmıştır.", 16, 0),
  ('Cihannüma adlı coğrafya eserini yazmıştır.', 16, 0),
  ("İstanbul'da Tophane sırtlarında bir gözlemevi kurmuştur.", 17, 0),
];

final _bilginSoru = _Ozneli(
  _bilginOlgu,
  _bilgin,
  const [0, 1, 2],
  sirali:
      'Bu bilgilerin ait olduğu Türk-İslam bilginleri sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
  hangileri: (s) =>
      'Türk-İslam bilginleriyle ilgili bu bilgilerden hangileri $s aittir?',
  onerme: 'Türk-İslam bilginleri ve eserleriyle ilgili bu bilgilerden hangileri doğrudur?',
);

// ─────────────────────── 5 · Osmanlı devlet yönetimi ─────────────────────────

const _divanUye = [
  ('Sadrazam', 'Sadrazama'),
  ('Kazasker', 'Kazaskere'),
  ('Defterdar', 'Defterdara'),
  ('Nişancı', 'Nişancıya'),
  ('Şeyhülislam', 'Şeyhülislama'),
  ('Reisülküttap', 'Reisülküttaba'),
  ('Kaptanıderya', 'Kaptanıderyaya'),
  ('Yeniçeri ağası', 'Yeniçeri ağasına'),
];

const _divan = <(String, int, int)>[
  ('padişahın mutlak vekili olarak devlet işlerini yürütür.', 0, 0),
  ('padişahın mührünü taşır.', 0, 0),
  (
    'padişah katılmadığında Divan-ı Hümayun toplantılarına başkanlık eder.',
    0,
    0,
  ),
  (
    'padişahın katılmadığı seferlerde orduya serdar-ı ekrem olarak komuta eder.',
    0,
    0,
  ),
  ('kadı ve müderrislerin atamalarını yapar.', 1, 1 << 4),
  ('divanda askerî sınıfa ait davalara bakar.', 1, 1),
  ('devletin mali işlerinden ve hazineden sorumludur.', 2, 0),
  ('devletin gelir ve giderlerini gösteren bütçeyi hazırlar.', 2, 0),
  ('padişah adına yazılan ferman ve beratlara tuğra çeker.', 3, 0),
  ('tapu ve tahrir kayıtlarını tutar.', 3, 1 << 2),
  ('divan kararlarının kanunlara uygunluğunu denetler.', 3, 1 << 4),
  ('devlet işlerinin dinî kurallara uygunluğu konusunda fetva verir.', 4, 0),
  ('ilmiye sınıfının en üst düzeydeki görevlisidir.', 4, 1 << 1),
  ('devletin dış yazışmalarını yürütür.', 5, 0),
  ('divan kâtiplerinin başıdır.', 5, 1 << 3),
  ('görevi II. Mahmud döneminde Hariciye Nezaretine dönüştürülmüştür.', 5, 0),
  ('donanmanın komutanıdır.', 6, 0),
  ("Tersane-i Amire'nin yönetiminden sorumludur.", 6, 0),
  ("İstanbul'un güvenliğinden sorumludur.", 7, 1 | 1 << 6),
  ('yeniçeri ocağının komutanıdır.', 7, 0),
];

// Biçim döngüsü: 0–2 Divan-ı Hümayun görevleri (2.000 vaka), 3 dirlik türü ve
// 4 yönetici sınıf (1.500'er vaka).
const _osmanliDongu = [0, 3, 4, 1, 3, 4, 2, 3, 4, 2];

final _divanOlgu = _Ozneli(
  _divan,
  _divanUye,
  _osmanliDongu,
  sirali:
      "Bu bilgilerin ait olduğu, Divan-ı Hümayun'da yer alan görevliler sırasıyla hangi "
      'seçenekte doğru verilmiştir?',
  hangileri: (s) =>
      "Divan-ı Hümayun'da yer alan görevlilerle ilgili bu bilgilerden hangileri "
      '$s aittir?',
  onerme: "Divan-ı Hümayun'da yer alan görevlilerle ilgili bu bilgilerden hangileri doğrudur?",
);

// Sınır değerlerinden (3000, 20000, 100000) uzak gelirler.
final _dirlikGelir = [
  for (var t = 4000; t <= 18000; t += 1000) t,
  25000,
  30000,
  35000,
  40000,
  45000,
  55000,
  60000,
  70000,
  80000,
  90000,
  120000,
  150000,
  180000,
  200000,
  250000,
  300000,
  350000,
  400000,
  450000,
  500000,
];
const _dirlikAd = ['Tımar', 'Zeamet', 'Has'];

int _dirlikTuru(int gelir, [int alt = 20000, int ust = 100000]) =>
    gelir < alt ? 0 : (gelir < ust ? 1 : 2);

/// Gelirleri yalnız büyüklüğe göre sıralamak ya da sınırları 10000–50000 veya
/// 50000–200000 sanmak doğru yanıtı vermesin diye bu yolların hepsinin yanlış
/// sonuç verdiği üçlüler kullanılır.
bool _dirlikAyirtar(List<int> g) {
  final d = [for (final x in g) _dirlikTuru(x)];
  final sira = [...g]..sort();
  bool farkli(List<int> w) =>
      [for (var k = 0; k < 3; k++) w[k] != d[k]].any((y) => y);
  return farkli([for (final x in g) sira.indexOf(x)]) &&
      farkli([for (final x in g) _dirlikTuru(x, 10000, 50000)]) &&
      farkli([for (final x in g) _dirlikTuru(x, 50000, 200000)]);
}

final _dirlikUclu = [
  for (final t in _tumUcluler(_dirlikGelir.length))
    if (_dirlikAyirtar([for (final k in t) _dirlikGelir[k]])) t,
];

AdvancedItem _dirlik(int j) {
  final u = _dilim(_dirlikUclu, j, 1500);
  final g = [for (final k in ucluDizilimler[j % 6]) _dirlikGelir[u[k]]];
  String yaz(List<int> t) => [for (final k in t) _dirlikAd[k]].join(' – ');
  final d = [for (final x in g) _dirlikTuru(x)];
  final sira = [...g]..sort();
  return secenekli(
    "Osmanlı Devleti'nde üç dirliğin yıllık gelirleri şöyledir:\n"
        '${_liste([for (final x in g) '$x akçe'])}'
        'Bu dirliklerin türleri sırasıyla hangi seçenekte doğru verilmiştir?',
    yaz(d),
    [
      // Gelirleri yalnız büyüklüğe göre sıralayıp türleri dağıtmak.
      yaz([for (final x in g) sira.indexOf(x)]),
      yaz([for (final x in g) _dirlikTuru(x, 10000, 50000)]),
      yaz([for (final x in g) _dirlikTuru(x, 50000, 200000)]),
      for (var k = 0; k < 3; k++)
        for (final y in [1, 2])
          yaz([for (var t = 0; t < 3; t++) t == k ? (d[t] + y) % 3 : d[t]]),
    ],
    'Yıllık geliri 3000 ile 20000 akçe arasında olan dirlik tımar, 20000 ile 100000 akçe '
        'arasında olan zeamet, 100000 akçeden fazla olan hastır. Buna göre '
        '${[for (var k = 0; k < 3; k++) '${g[k]} akçelik dirlik ${_dirlikAd[d[k]].toLowerCase()}'].join(', ')} '
        'olur.',
  );
}

const _sinif = ['seyfiye', 'ilmiye', 'kalemiye'];
const _gorevli = <(String, int)>[
  ('Sadrazam', 0),
  ('Kubbe veziri', 0),
  ('Beylerbeyi', 0),
  ('Sancakbeyi', 0),
  ('Subaşı', 0),
  ('Kaptanıderya', 0),
  ('Yeniçeri ağası', 0),
  ('Tımarlı sipahi', 0),
  ('Alaybeyi', 0),
  ('Şeyhülislam', 1),
  ('Kazasker', 1),
  ('Kadı', 1),
  ('Müderris', 1),
  ('Müftü', 1),
  ('Defterdar', 2),
  ('Nişancı', 2),
  ('Reisülküttap', 2),
  ('Divan kâtibi', 2),
];
final _gorevliUclu = _tumUcluler(_gorevli.length);

AdvancedItem _sinifSoru(int j) {
  final k = j ~/ 2;
  final u = _dilim(_gorevliUclu, k, 750);
  final x = [for (final t in ucluDizilimler[k % 6]) _gorevli[u[t]]];
  final d = [for (final e in x) e.$2];
  final dokum =
      '${[for (final e in x) '${e.$1}: ${_sinif[e.$2]}'].join('; ')}.';
  if (j.isEven) {
    final s = d[k % 3];
    var maske = 0;
    for (var t = 0; t < 3; t++) {
      if (d[t] == s) maske |= 1 << t;
    }
    return _oncullu(
      '${_liste([for (final e in x) e.$1])}'
          "Osmanlı Devleti'ndeki bu görevlilerden hangileri ${_sinif[s]} sınıfına mensuptur?",
      maske,
      k ~/ 3,
      '$dokum ${_buyuk(_sinif[s])} sınıfından olanlar: ${_altkume(maske)}.',
    );
  }
  final (g, maske) = _gosterilen(d, 1 + k % 7, 3, const [0, 0, 0], k ~/ 7);
  return _oncullu(
    '${_liste([for (var t = 0; t < 3; t++) '${x[t].$1} ${_sinif[g[t]]} sınıfına mensuptur.'])}'
        "Osmanlı Devleti'ndeki yönetici sınıflarla ilgili bu bilgilerden hangileri doğrudur?",
    maske,
    k ~/ 3,
    '$dokum Doğru olanlar: ${_altkume(maske)}.',
  );
}

AdvancedItem _osmanliSoru(int i) {
  final (b, j, _) = _bicim(i, _osmanliDongu);
  if (b < 3) return _divanOlgu(i);
  return b == 3 ? _dirlik(j) : _sinifSoru(j);
}

// ─────────────────────────── 6 · Avrupa tarihi ──────────────────────────────

const _avrupaOzne = [
  ('Coğrafi Keşifler', "Coğrafi Keşifler'e"),
  ('Rönesans', "Rönesans'a"),
  ('Reform', "Reform'a"),
  ('Fransız İhtilali', "Fransız İhtilali'ne"),
  ('Sanayi İnkılabı', "Sanayi İnkılabı'na"),
];

// Birden çok gelişmeye bağlanabilen sonuçlar (feodalitenin zayıflaması,
// kilisenin otoritesinin sarsılması gibi) bilerek alınmamıştır.
const _avrupa = <(String, int, int)>[
  ('Akdeniz limanlarının önemini kaybetmesine yol açmıştır.', 0, 0),
  (
    "Amerika kıtasından Avrupa'ya büyük miktarda altın ve gümüş taşınmasını sağlamıştır.",
    0,
    0,
  ),
  ('İpek ve Baharat yollarının önemini yitirmesine yol açmıştır.', 0, 0),
  (
    'pusulanın geliştirilmesi ve okyanuslara dayanıklı gemilerin yapılmasıyla mümkün olmuştur.',
    0,
    0,
  ),
  (
    'Kristof Kolomb, Vasco da Gama ve Macellan gibi denizcilerin yolculuklarını kapsar.',
    0,
    0,
  ),
  (
    "Macellan'ın yolculuğuyla Dünya'nın yuvarlak olduğunun kanıtlanmasını sağlamıştır.",
    0,
    0,
  ),
  ('Avrupalıların Amerika kıtasında sömürgeler kurmasına yol açmıştır.', 0, 0),
  ("İtalya'da başlamıştır.", 1, 1),
  ('Antik Yunan ve Roma eserlerinin yeniden incelenmesine dayanmıştır.', 1, 0),
  (
    'Leonardo da Vinci, Michelangelo ve Rafael gibi sanatçıların eserleriyle gelişmiştir.',
    1,
    0,
  ),
  (
    'mesen adı verilen zengin ailelerin sanatçıları desteklemesiyle gelişmiştir.',
    1,
    0,
  ),
  (
    'Dante, Petrarca ve Boccaccio gibi yazarların eserleriyle edebiyatta başlamıştır.',
    1,
    0,
  ),
  ('hümanizm akımının etkisiyle ortaya çıkmıştır.', 1, 1 << 2),
  (
    "Martin Luther'in 95 maddelik bildirisini yayımlamasıyla başlamıştır.",
    2,
    0,
  ),
  ("Almanya'da başlamıştır.", 2, 0),
  (
    'endülüjans (günah çıkarma belgesi) satışına tepki olarak ortaya çıkmıştır.',
    2,
    0,
  ),
  (
    'Protestanlık ve Kalvenizm gibi yeni mezheplerin doğmasına yol açmıştır.',
    2,
    0,
  ),
  ('Augsburg Barışı ile Lutheranlığın resmen tanınmasını sağlamıştır.', 2, 0),
  (
    "Katolik Kilisesi'nin Cizvit tarikatını kurarak karşı harekete geçmesine yol açmıştır.",
    2,
    0,
  ),
  ("İncil'in Almancaya çevrilmesini sağlamıştır.", 2, 0),
  ("Avrupa'da uzun süren mezhep savaşlarına yol açmıştır.", 2, 0),
  (
    'milliyetçilik akımını yayarak çok uluslu imparatorlukların dağılma sürecini hızlandırmıştır.',
    3,
    0,
  ),
  ("İnsan ve Yurttaş Hakları Bildirgesi'nin yayımlanmasını sağlamıştır.", 3, 0),
  ('özgürlük, eşitlik ve kardeşlik ilkelerini yaymıştır.', 3, 0),
  ("Bastille Hapishanesi'nin basılmasıyla başlamıştır.", 3, 0),
  ("Osmanlı Devleti'ndeki Sırp İsyanı'nın çıkmasında etkili olmuştur.", 3, 0),
  (
    'Montesquieu, Voltaire ve Rousseau gibi düşünürlerin fikirlerinden etkilenmiştir.',
    3,
    0,
  ),
  (
    "Fransa'da krallığın kaldırılarak cumhuriyetin ilan edilmesine yol açmıştır.",
    3,
    0,
  ),
  ("İngiltere'de başlamıştır.", 4, 0),
  ('buhar makinesinin üretimde kullanılmasıyla başlamıştır.', 4, 0),
  (
    'hammadde ve pazar ihtiyacını artırarak sömürgecilik yarışını hızlandırmıştır.',
    4,
    1,
  ),
  (
    'işçi sınıfının ortaya çıkmasına ve sosyalizm gibi ideolojilere zemin hazırlamıştır.',
    4,
    0,
  ),
  ('kırsaldan kentlere göçü artırarak şehirleşmeyi hızlandırmıştır.', 4, 0),
  ('el tezgâhlarının yerini fabrikaların almasına yol açmıştır.', 4, 0),
  (
    'ucuz seri üretimle Osmanlı el sanatlarının gerilemesine yol açmıştır.',
    4,
    0,
  ),
  ('demir yolu ve buharlı gemilerle ulaşımda büyük gelişme sağlamıştır.', 4, 0),
];

final _avrupaOlgu = _Ozneli(
  _avrupa,
  _avrupaOzne,
  const [0, 1, 2],
  sirali:
      'Bu bilgilerin ilgili olduğu Avrupa tarihindeki gelişmeler sırasıyla hangi '
      'seçenekte doğru verilmiştir?',
  hangileri: (s) =>
      'Avrupa tarihiyle ilgili bu bilgilerden hangileri $s aittir?',
  onerme: 'Avrupa tarihindeki gelişmelerle ilgili bu bilgilerden hangileri doğrudur?',
);

// ─────────────────────── 7 · Osmanlı yenileşme hareketleri ──────────────────

const _islahatDonem = [
  ('Lale Devri', "Lale Devri'nde"),
  ('I. Mahmud dönemi', 'I. Mahmud döneminde'),
  ('III. Selim dönemi', 'III. Selim döneminde'),
  ('II. Mahmud dönemi', 'II. Mahmud döneminde'),
  ('Tanzimat Dönemi', "Tanzimat Dönemi'nde"),
  ('I. Meşrutiyet Dönemi', "I. Meşrutiyet Dönemi'nde"),
  ('II. Meşrutiyet Dönemi', "II. Meşrutiyet Dönemi'nde"),
];

// Kaynaklarda farklı döneme bağlanan gelişmeler (Yalova kâğıt fabrikası,
// Hendesehane, çiçek aşısı, posta teşkilatı) alınmamıştır.
const _islahat = <(String, int, int)>[
  ("İbrahim Müteferrika'nın ilk Türk matbaasını kurması", 0, 0),
  ("Avrupa'ya ilk kez geçici elçilerin gönderilmesi", 0, 0),
  ("Tulumbacı Ocağı'nın kurulması", 0, 0),
  (
    'Doğu ve Batı eserlerini çevirmek için bir tercüme heyetinin oluşturulması',
    0,
    0,
  ),
  ("Patrona Halil İsyanı'nın çıkması", 0, 0),
  ("Kâğıthane'de Sadabad Köşkü'nün yaptırılması", 0, 0),
  (
    "Humbaracı Ocağı'nın Humbaracı Ahmet Paşa tarafından yeniden düzenlenmesi",
    1,
    0,
  ),
  ('Nizam-ı Cedid ordusunun kurulması', 2, 0),
  ('İrad-ı Cedid hazinesinin oluşturulması', 2, 0),
  ('Avrupa başkentlerinde sürekli elçiliklerin açılması', 2, 0),
  ("Mühendishane-i Berr-i Hümayun'un açılması", 2, 0),
  ("Kabakçı Mustafa İsyanı'nın çıkması", 2, 0),
  ("Sened-i İttifak'ın imzalanması", 3, 0),
  ("Yeniçeri Ocağı'nın kaldırılması", 3, 0),
  ('Asakir-i Mansure-i Muhammediye ordusunun kurulması', 3, 0),
  ('Takvim-i Vekayi gazetesinin çıkarılması', 3, 0),
  ("Osmanlı Devleti'nde ilk nüfus sayımının yapılması", 3, 0),
  ("Mekteb-i Tıbbiye'nin açılması", 3, 0),
  ("Mekteb-i Harbiye'nin açılması", 3, 0),
  ('Divan-ı Hümayun yerine nezaretlerin kurulması', 3, 0),
  ('Tımar sisteminin kaldırılması', 3, 0),
  ('Fesin resmî kıyafet olarak kabul edilmesi', 3, 0),
  ("Bâbıâli Tercüme Odası'nın kurulması", 3, 0),
  ('Sıbyan mekteplerine devam zorunluluğu getirilmesi', 3, 0),
  ("Tanzimat Fermanı'nın ilan edilmesi", 4, 0),
  ("Islahat Fermanı'nın ilan edilmesi", 4, 0),
  ('İlk kâğıt para olan kaimenin basılması', 4, 0),
  ('İlk dış borcun alınması', 4, 0),
  ("Mecelle'nin hazırlanması", 4, 0),
  ("Mekteb-i Sultani'nin (Galatasaray Lisesi) açılması", 4, 0),
  ("Arazi Kanunnamesi'nin çıkarılması", 4, 0),
  ("Vilayet Nizamnamesi'nin çıkarılması", 4, 0),
  ("Agâh Efendi ve Şinasi'nin Tercüman-ı Ahval gazetesini çıkarması", 4, 0),
  ("Ticaret Kanunnamesi'nin kabul edilmesi", 4, 0),
  ("Kanun-ı Esasi'nin ilan edilmesi", 5, 1 << 6),
  (
    "Meclis-i Mebusan ve Meclis-i Ayan'dan oluşan Meclis-i Umumi'nin açılması",
    5,
    0,
  ),
  ("93 Harbi gerekçe gösterilerek Meclis-i Mebusan'ın kapatılması", 5, 0),
  ("Meclis-i Mebusan'ın yeniden açılması", 6, 0),
  ("31 Mart Vakası'nın yaşanması", 6, 0),
  ("Padişah II. Abdülhamid'in tahttan indirilmesi", 6, 0),
  (
    "Kanun-ı Esasi'de padişahın yetkilerini kısıtlayan değişikliklerin yapılması",
    6,
    0,
  ),
  ('Siyasi partilerin kurularak çok partili hayata geçilmesi', 6, 0),
];

final _islahatOlgu = _Ozneli(
  _islahat,
  _islahatDonem,
  const [0, 1, 2],
  donem: true,
  sirali:
      'Osmanlı yenileşme hareketlerine ait bu gelişmelerin yaşandığı dönemler sırasıyla '
      'hangi seçenekte doğru verilmiştir?',
  hangileri: (s) =>
      'Osmanlı yenileşme hareketlerine ait bu gelişmelerden hangileri $s gerçekleşmiştir?',
  onerme: 'Osmanlı yenileşme hareketleriyle ilgili bu bilgilerden hangileri doğrudur?',
);

// ───────────────────────── 8 · Birinci Dünya Savaşı ─────────────────────────

const _cepheAd = [
  ('Kafkas Cephesi', "Kafkas Cephesi'nde"),
  ('Kanal Cephesi', "Kanal Cephesi'nde"),
  ('Irak Cephesi', "Irak Cephesi'nde"),
  ('Çanakkale Cephesi', "Çanakkale Cephesi'nde"),
  ('Suriye-Filistin Cephesi', "Suriye-Filistin Cephesi'nde"),
  ('Hicaz-Yemen Cephesi', "Hicaz-Yemen Cephesi'nde"),
  ('Galiçya Cephesi', "Galiçya Cephesi'nde"),
  ('Romanya Cephesi', "Romanya Cephesi'nde"),
  ('Makedonya Cephesi', "Makedonya Cephesi'nde"),
];

const _cephe = <(String, int, int)>[
  ('Sarıkamış Harekâtı', 0, 0),
  ("Mustafa Kemal'in Muş ve Bitlis'i Ruslardan geri alması", 0, 0),
  ("Rus ordusunun Erzurum, Trabzon ve Erzincan'ı işgal etmesi", 0, 0),
  (
    "Rusya'nın savaştan çekilmesiyle Kars, Ardahan ve Batum'un geri alınması",
    0,
    0,
  ),
  ("Kafkas İslam Ordusu'nun Bakü'ye girmesi", 0, 0),
  ("Osmanlı kuvvetlerinin Süveyş Kanalı'nı geçmeye çalışması", 1, 0),
  (
    "İngiltere'nin sömürge yolunu kesmek amacıyla Mısır'a yönelik harekât düzenlenmesi",
    1,
    0,
  ),
  ("İngilizlerin Basra'ya asker çıkarması", 2, 0),
  ("Kut'ül-Amare'de İngiliz kuvvetlerinin teslim alınması", 2, 0),
  ("İngilizlerin Bağdat'ı ele geçirmesi", 2, 0),
  ('18 Mart 1915 deniz zaferinin kazanılması', 3, 0),
  ("Mustafa Kemal'in Anafartalar'da İtilaf kuvvetlerini durdurması", 3, 0),
  ("İtilaf kuvvetlerinin Seddülbahir ve Arıburnu'na asker çıkarması", 3, 0),
  ('Nusret mayın gemisinin boğaza mayın döşemesi', 3, 0),
  ("İtilaf kuvvetlerinin Gelibolu Yarımadası'ndan çekilmesi", 3, 0),
  ("Yıldırım Orduları Grubu'nun İngilizlere karşı savaşması", 4, 1 << 2),
  ("İngilizlerin Kudüs'ü ele geçirmesi", 4, 0),
  ("Mustafa Kemal'in Halep'in kuzeyinde İngiliz ilerleyişini durdurması", 4, 0),
  ("İngilizlerin Gazze'yi ele geçirmesi", 4, 0),
  ("Şerif Hüseyin'in İngilizlerle iş birliği yaparak ayaklanması", 5, 1 << 4),
  ("Fahrettin Paşa'nın Medine'yi uzun süre savunması", 5, 0),
  (
    "Osmanlı kuvvetlerinin Aden'deki İngiliz kuvvetlerine karşı savaşması",
    5,
    0,
  ),
  (
    "Osmanlı birliklerinin Avusturya-Macaristan'a yardım için Ruslara karşı savaşması",
    6,
    0,
  ),
  ("Osmanlı birliklerinin Dobruca'da Romen ordusuna karşı savaşması", 7, 0),
  (
    "Osmanlı birliklerinin Bulgarlarla birlikte Selanik'ten ilerleyen İtilaf kuvvetlerine "
        'karşı savaşması',
    8,
    0,
  ),
];

const _savasYili = [
  ('1914', '1914 yılında'),
  ('1915', '1915 yılında'),
  ('1916', '1916 yılında'),
  ('1917', '1917 yılında'),
  ('1918', '1918 yılında'),
];

// Yılı tartışmasız (iki yıla yayılmayan) gelişmeler.
const _savasOlay = <(String, int, int)>[
  ('Saraybosna Suikastı', 0, 0),
  (
    'Osmanlı Devleti ile Almanya arasında gizli ittifak antlaşmasının imzalanması',
    0,
    0,
  ),
  ("Goben ve Breslau zırhlılarının Osmanlı Devleti'ne sığınması", 0, 0),
  ("Osmanlı donanmasının Karadeniz'de Rus limanlarını bombalaması", 0, 0),
  ("Almanya'nın Belçika'yı işgal etmesi", 0, 0),
  ("Osmanlı Devleti'nin kapitülasyonları tek taraflı olarak kaldırması", 0, 0),
  ('18 Mart Çanakkale Deniz Zaferi', 1, 0),
  ("İtalya'nın İtilaf Devletleri safında savaşa girmesi", 1, 0),
  ("Bulgaristan'ın İttifak Devletleri safında savaşa girmesi", 1, 0),
  ("İtilaf Devletleri arasında Londra Antlaşması'nın imzalanması", 1, 0),
  ("Tehcir Kanunu'nun çıkarılması", 1, 0),
  ('Lusitania yolcu gemisinin bir Alman denizaltısınca batırılması', 1, 0),
  ('Anafartalar Muharebeleri', 1, 0),
  ("Sykes-Picot Antlaşması'nın imzalanması", 2, 0),
  ("Kut'ül-Amare Zaferi", 2, 0),
  ('Verdun Muharebesi', 2, 0),
  ("Romanya'nın İtilaf Devletleri safında savaşa girmesi", 2, 0),
  ("Şerif Hüseyin'in Osmanlı Devleti'ne karşı ayaklanması", 2, 0),
  ("Mustafa Kemal'in Muş ve Bitlis'i geri alması", 2, 0),
  ('Jutland Deniz Savaşı', 2, 0),
  ("ABD'nin İtilaf Devletleri safında savaşa girmesi", 3, 0),
  ("Rusya'da Bolşevik İhtilali'nin gerçekleşmesi", 3, 0),
  ("Rusya'da Çarlık yönetiminin yıkılması", 3, 0),
  ("St. Jean de Maurienne Antlaşması'nın imzalanması", 3, 0),
  ("Bağdat'ın İngilizlerin eline geçmesi", 3, 0),
  ("Kudüs'ün İngilizlerin eline geçmesi", 3, 0),
  ("Yunanistan'ın İtilaf Devletleri safında savaşa girmesi", 3, 0),
  ("Balfour Deklarasyonu'nun yayımlanması", 3, 0),
  ("Wilson İlkeleri'nin açıklanması", 4, 0),
  ("Brest-Litovsk Antlaşması'nın imzalanması", 4, 0),
  ("Mondros Ateşkes Antlaşması'nın imzalanması", 4, 0),
  ("Almanya'nın Compiègne (Rethondes) Ateşkesi'ni imzalaması", 4, 0),
  ("Bulgaristan'ın ateşkes imzalayarak savaştan çekilmesi", 4, 0),
  ("Bakü'nün Kafkas İslam Ordusunca alınması", 4, 0),
  ("Avusturya-Macaristan İmparatorluğu'nun dağılması", 4, 0),
];

// On beşlik döngü: cephe biçimleri (0–2), olay-yıl biçimleri (0–2) ve
// bloklar; 9 öteki parçaların yerini tutar.
const _cepheDongu = [0, 9, 9, 1, 9, 2, 9, 9, 0, 9, 1, 9, 9, 2, 9];
const _olayDongu = [9, 0, 9, 9, 1, 9, 2, 9, 9, 0, 9, 1, 9, 9, 2];
const _blokDongu = [9, 9, 0, 9, 9, 9, 9, 0, 9, 9, 9, 9, 0, 9, 9];

final _cepheOlgu = _Ozneli(
  _cephe,
  _cepheAd,
  _cepheDongu,
  donem: true,
  sirali:
      "I. Dünya Savaşı'nda yaşanan bu gelişmelerin gerçekleştiği cepheler sırasıyla hangi "
      'seçenekte doğru verilmiştir?',
  hangileri: (s) =>
      "I. Dünya Savaşı'nda yaşanan bu gelişmelerden hangileri $s gerçekleşmiştir?",
  onerme:
      "I. Dünya Savaşı'nda Osmanlı Devleti'nin savaştığı cephelerle ilgili bu bilgilerden "
      'hangileri doğrudur?',
);

final _savasOlgu = _Ozneli(
  _savasOlay,
  _savasYili,
  _olayDongu,
  donem: true,
  sirali:
      'I. Dünya Savaşı sürecindeki bu gelişmelerin yılları sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
  hangileri: (s) =>
      'I. Dünya Savaşı sürecindeki bu gelişmelerden hangileri $s gerçekleşmiştir?',
  onerme: 'I. Dünya Savaşı sürecindeki gelişmelerle ilgili bu bilgilerden hangileri doğrudur?',
);

const _blokAd = ['İttifak Devletleri', 'İtilaf Devletleri'];
const _blokDevlet = <(String, int, int)>[
  ('Almanya', 0, 0),
  ('Avusturya-Macaristan', 0, 0),
  ('Osmanlı Devleti', 0, 0),
  ('Bulgaristan', 0, 0),
  ('İngiltere', 1, 0),
  ('Fransa', 1, 0),
  ('Rusya', 1, 0),
  ('Sırbistan', 1, 0),
  ('Belçika', 1, 0),
  ('Japonya', 1, 0),
  ('İtalya', 1, 0),
  ('Romanya', 1, 0),
  ('ABD', 1, 0),
  ('Yunanistan', 1, 0),
  ('Karadağ', 1, 0),
  ('Portekiz', 1, 0),
];

/// İki bloklu savaşlarda devlet–blok sorusu: çift sıra numaraları “hangileri
/// X safındadır”, tekler doğru önermeleri seçme biçimindedir. Devlet ögesi
/// (ad, blok, tartışmalı blok maskesi) biçimindedir.
class _Blok {
  _Blok(
    this.devlet,
    this.ad, {
    required this.hangileri,
    required this.onermeYaz,
    required this.onerme,
    required this.yer,
  });

  final List<(String, int, int)> devlet;
  final List<String> ad;
  final String Function(String blok) hangileri, yer;
  final String Function(String devlet, String blok) onermeYaz;
  final String onerme;
  late final List<List<int>> uclu = _tumUcluler(devlet.length);

  /// j ∈ [0, m) blok vakalarının sırası.
  AdvancedItem call(int j, int m) {
    final k = j ~/ 2;
    final u = _dilim(uclu, k, (m + 1) ~/ 2);
    final x = [for (final t in ucluDizilimler[k % 6]) devlet[u[t]]];
    final d = [for (final e in x) e.$2];
    final dokum = '${[for (final e in x) '${e.$1}: ${ad[e.$2]}'].join('; ')}.';
    if (j.isEven) {
      final adaylar = [
        for (final s in {...d})
          if (x.every((e) => e.$2 == s || (e.$3 >> s) & 1 == 0)) s,
      ];
      final s = adaylar[k % adaylar.length];
      var maske = 0;
      for (var t = 0; t < 3; t++) {
        if (d[t] == s) maske |= 1 << t;
      }
      return _oncullu(
        '${_liste([for (final e in x) e.$1])}${hangileri(ad[s])}',
        maske,
        k ~/ 3,
        '$dokum ${yer(ad[s])}: ${_altkume(maske)}.',
      );
    }
    final (g, maske) = _gosterilen(d, 1 + k % 7, 2, [
      for (final e in x) e.$3,
    ], k ~/ 7);
    return _oncullu(
      '${_liste([for (var t = 0; t < 3; t++) onermeYaz(x[t].$1, ad[g[t]])])}$onerme',
      maske,
      k ~/ 3,
      '$dokum Doğru olanlar: ${_altkume(maske)}.',
    );
  }
}

final _birinciBlok = _Blok(
  _blokDevlet,
  _blokAd,
  hangileri: (b) =>
      "Bu devletlerden hangileri I. Dünya Savaşı'nda $b safında yer almıştır?",
  onermeYaz: (d, b) => '$d $b safında savaşmıştır.',
  onerme: "I. Dünya Savaşı'ndaki bloklarla ilgili bu bilgilerden hangileri doğrudur?",
  yer: (b) => '$b safında yer alanlar',
);

AdvancedItem _birinciDunyaSoru(int i) {
  if (_cepheDongu[i % 15] < 3) return _cepheOlgu(i);
  if (_olayDongu[i % 15] < 3) return _savasOlgu(i);
  final (_, j, m) = _bicim(i, _blokDongu);
  return _birinciBlok(j, m);
}

// ───────────────────────── 9 · İkinci Dünya Savaşı ──────────────────────────

const _ikinciYil = [
  ('1939', '1939 yılında'),
  ('1940', '1940 yılında'),
  ('1941', '1941 yılında'),
  ('1942', '1942 yılında'),
  ('1943', '1943 yılında'),
  ('1944', '1944 yılında'),
  ('1945', '1945 yılında'),
];

// İki yıla yayılan gelişmeler (Stalingrad Muharebesi'nin bütünü gibi) alınmamıştır.
const _ikinciOlay = <(String, int, int)>[
  ("Almanya'nın Polonya'ya saldırması", 0, 0),
  ('Almanya ile SSCB arasında saldırmazlık paktının imzalanması', 0, 0),
  ("İtalya'nın Arnavutluk'u işgal etmesi", 0, 0),
  (
    "Türkiye, İngiltere ve Fransa arasında Ankara Antlaşması'nın imzalanması",
    0,
    0,
  ),
  ("SSCB'nin Finlandiya'ya saldırması", 0, 0),
  ("Almanya'nın Fransa'yı yenerek Paris'e girmesi", 1, 0),
  ("Almanya'nın Norveç ve Danimarka'yı işgal etmesi", 1, 0),
  ("Dunkirk'te Müttefik askerlerinin tahliye edilmesi", 1, 0),
  ("Almanya, İtalya ve Japonya arasında Üçlü Pakt'ın imzalanması", 1, 0),
  ("İtalya'nın Yunanistan'a saldırması", 1, 0),
  ("Britanya Savaşı'nda Alman hava saldırılarının püskürtülmesi", 1, 0),
  ("Almanya'nın SSCB'ye saldırması (Barbarossa Harekâtı)", 2, 0),
  ("Japonya'nın Pearl Harbor'a saldırması", 2, 0),
  ("Türk-Alman Saldırmazlık Antlaşması'nın imzalanması", 2, 0),
  ("Atlantik Bildirisi'nin yayımlanması", 2, 0),
  ("ABD'de Ödünç Verme ve Kiralama Yasası'nın kabul edilmesi", 2, 0),
  ("Almanya'nın Yugoslavya ve Yunanistan'ı işgal etmesi", 2, 0),
  ('Midway Deniz Savaşı', 3, 0),
  ('El Alamein Muharebeleri', 3, 0),
  ("Türkiye'de Varlık Vergisi'nin çıkarılması", 3, 0),
  (
    "Birleşmiş Milletler Bildirisi'nin (Washington Bildirisi) imzalanması",
    3,
    0,
  ),
  ('Almanların Stalingrad kuşatmasını başlatması', 3, 0),
  ("Stalingrad'daki Alman ordusunun teslim olması", 4, 0),
  ('Kursk Muharebesi', 4, 0),
  ('İsmet İnönü ile Churchill arasında Adana Görüşmesi', 4, 0),
  ("İsmet İnönü'nün katıldığı Kahire Konferansı", 4, 0),
  ('Tahran Konferansı', 4, 0),
  ("İtalya'nın Müttefiklere teslim olması", 4, 0),
  ('Kazablanka Konferansı', 4, 0),
  ('Normandiya Çıkarması', 5, 0),
  ("Paris'in Alman işgalinden kurtarılması", 5, 0),
  ('Bretton Woods Konferansı', 5, 0),
  ("Türkiye'nin Almanya ile diplomatik ilişkilerini kesmesi", 5, 0),
  ('Dumbarton Oaks Konferansı', 5, 0),
  ('Yalta Konferansı', 6, 0),
  ("Türkiye'nin Almanya ve Japonya'ya savaş ilan etmesi", 6, 0),
  ("Almanya'nın koşulsuz teslim olması", 6, 0),
  ("Hiroşima ve Nagazaki'ye atom bombası atılması", 6, 0),
  ('Potsdam Konferansı', 6, 0),
  (
    "San Francisco Konferansı'nda Birleşmiş Milletler Antlaşması'nın imzalanması",
    6,
    0,
  ),
  ("Japonya'nın teslim olması", 6, 0),
];

const _orgAd = [
  ('Birleşmiş Milletler', "Birleşmiş Milletler'e"),
  ('UNESCO', "UNESCO'ya"),
  ('UNICEF', "UNICEF'e"),
  ('Dünya Sağlık Örgütü', "Dünya Sağlık Örgütü'ne"),
  ('Uluslararası Para Fonu', "Uluslararası Para Fonu'na"),
  ('Dünya Bankası', "Dünya Bankası'na"),
  ('Avrupa Konseyi', "Avrupa Konseyi'ne"),
  ('Arap Birliği', "Arap Birliği'ne"),
  ('Avrupa Ekonomik İş Birliği Örgütü', "Avrupa Ekonomik İş Birliği Örgütü'ne"),
  ('Avrupa Kömür ve Çelik Topluluğu', "Avrupa Kömür ve Çelik Topluluğu'na"),
  ('Avrupa Ekonomik Topluluğu', "Avrupa Ekonomik Topluluğu'na"),
];

const _org = <(String, int, int)>[
  (
    'uluslararası barış ve güvenliği korumak amacıyla 1945 yılında kurulmuştur.',
    0,
    0,
  ),
  ("Güvenlik Konseyi'ndeki beş daimi üyeye veto hakkı tanımıştır.", 0, 0),
  ("Milletler Cemiyeti'nin yerini almıştır.", 0, 0),
  ("San Francisco Konferansı'nda imzalanan bir antlaşmayla kurulmuştur.", 0, 0),
  (
    'eğitim, bilim ve kültür alanlarında uluslararası iş birliğini geliştirmek amacıyla kurulmuştur.',
    1,
    0,
  ),
  (
    'dünyadaki çocukların sağlık, beslenme ve eğitim ihtiyaçlarını desteklemek amacıyla kurulmuştur.',
    2,
    0,
  ),
  (
    'uluslararası alanda halk sağlığını korumak ve salgın hastalıklarla mücadele etmek amacıyla kurulmuştur.',
    3,
    1 << 2,
  ),
  (
    'üye ülkelere ödemeler dengesi sorunlarında kısa vadeli kredi desteği vermek amacıyla kurulmuştur.',
    4,
    0,
  ),
  (
    "kuruluşu 1944 yılındaki Bretton Woods Konferansı'nda kararlaştırılmıştır.",
    4,
    1 << 5,
  ),
  (
    'savaşta yıkılan ülkelerin yeniden yapılanması ve kalkınması için uzun vadeli kredi vermek amacıyla kurulmuştur.',
    5,
    0,
  ),
  ("Avrupa İnsan Hakları Sözleşmesi'ni hazırlamıştır.", 6, 0),
  ("merkezi Strazburg'dadır.", 6, 0),
  ('1949 yılında kurulmuş ve Türkiye aynı yıl bu örgüte üye olmuştur.', 6, 0),
  (
    "Arap ülkeleri arasında iş birliğini sağlamak amacıyla 1945 yılında Kahire'de kurulmuştur.",
    7,
    0,
  ),
  (
    'Marshall Planı yardımlarının dağıtımını düzenlemek amacıyla 1948 yılında kurulmuştur.',
    8,
    0,
  ),
  (
    '1961 yılında Ekonomik İş Birliği ve Kalkınma Örgütüne (OECD) dönüşmüştür.',
    8,
    0,
  ),
  (
    'üye ülkelerin kömür ve çelik üretimini ortak bir yönetime bağlamak amacıyla 1951 yılında kurulmuştur.',
    9,
    0,
  ),
  ('1957 yılında imzalanan Roma Antlaşması ile kurulmuştur.', 10, 0),
  (
    'Türkiye ile 1963 yılında Ankara Anlaşması adlı ortaklık anlaşmasını imzalamıştır.',
    10,
    0,
  ),
];

// On beşlik döngü: olay-yıl biçimleri (3.000 vaka), örgüt biçimleri ve bloklar
// (1.000'er vaka); 9 öteki parçaların yerini tutar.
const _ikinciOlayDongu = [0, 9, 9, 1, 9, 2, 9, 0, 9, 1, 9, 2, 0, 1, 2];
const _orgDongu = [9, 0, 9, 9, 1, 9, 9, 9, 2, 9, 9, 9, 9, 9, 9];
const _ikinciBlokDongu = [9, 9, 0, 9, 9, 9, 0, 9, 9, 9, 0, 9, 9, 9, 9];

final _ikinciOlayOlgu = _Ozneli(
  _ikinciOlay,
  _ikinciYil,
  _ikinciOlayDongu,
  donem: true,
  sirali:
      'II. Dünya Savaşı sürecindeki bu gelişmelerin yılları sırasıyla hangi seçenekte '
      'doğru verilmiştir?',
  hangileri: (s) =>
      'II. Dünya Savaşı sürecindeki bu gelişmelerden hangileri $s gerçekleşmiştir?',
  onerme: 'II. Dünya Savaşı sürecindeki gelişmelerle ilgili bu bilgilerden hangileri doğrudur?',
);

final _orgOlgu = _Ozneli(
  _org,
  _orgAd,
  _orgDongu,
  sirali:
      'II. Dünya Savaşı sonrasında kurulan örgütlerle ilgili bu bilgilerin ait olduğu '
      'örgütler sırasıyla hangi seçenekte doğru verilmiştir?',
  hangileri: (s) =>
      'II. Dünya Savaşı sonrasında kurulan örgütlerle ilgili bu bilgilerden hangileri $s aittir?',
  onerme: 'II. Dünya Savaşı sonrasında kurulan örgütlerle ilgili bu bilgilerden hangileri doğrudur?',
);

// Savaş sırasında taraf değiştiren ya da kısa süre Mihver'e katılan devletler
// (Romanya, Bulgaristan, Macaristan, Finlandiya, Yugoslavya) alınmamıştır;
// İtalya 1943'ten sonra Müttefiklerle birlikte savaştığı için maskelidir.
final _ikinciBlok = _Blok(
  const [
    ('Almanya', 0, 0),
    ('İtalya', 0, 1 << 1),
    ('Japonya', 0, 0),
    ('İngiltere', 1, 0),
    ('Fransa', 1, 0),
    ('SSCB', 1, 0),
    ('ABD', 1, 0),
    ('Çin', 1, 0),
    ('Polonya', 1, 0),
    ('Kanada', 1, 0),
    ('Avustralya', 1, 0),
    ('Hollanda', 1, 0),
    ('Belçika', 1, 0),
    ('Norveç', 1, 0),
    ('Yunanistan', 1, 0),
    ('Brezilya', 1, 0),
  ],
  const ['Mihver Devletleri', 'Müttefik Devletler'],
  hangileri: (b) =>
      "Bu devletlerden hangileri II. Dünya Savaşı'nda $b arasında yer almıştır?",
  onermeYaz: (d, b) => '$d $b arasında yer almıştır.',
  onerme: "II. Dünya Savaşı'ndaki bloklarla ilgili bu bilgilerden hangileri doğrudur?",
  yer: (b) => '$b arasında yer alanlar',
);

AdvancedItem _ikinciDunyaSoru(int i) {
  if (_ikinciOlayDongu[i % 15] < 3) return _ikinciOlayOlgu(i);
  if (_orgDongu[i % 15] < 3) return _orgOlgu(i);
  final (_, j, m) = _bicim(i, _ikinciBlokDongu);
  return _ikinciBlok(j, m);
}

// ─────────────────────────── 10 · Soğuk Savaş ───────────────────────────────

const _sogukYilDegeri = [
  1947,
  1948,
  1949,
  1950,
  1952,
  1953,
  1954,
  1955,
  1956,
  1957,
  1959,
  1961,
  1962,
  1964,
  1968,
  1969,
  1972,
  1974,
  1975,
  1979,
  1983,
  1986,
  1989,
  1990,
  1991,
];
final _sogukYil = [for (final y in _sogukYilDegeri) ('$y', '$y yılında')];

int _sy(int yil) => _sogukYilDegeri.indexOf(yil);

// Yılı kaynaklarda tartışmalı olanlar (Vietnam Savaşı'nın sonu, Balkan Paktı)
// alınmamıştır.
final _sogukOlay = <(String, int, int)>[
  ("Truman Doktrini'nin ilan edilmesi", _sy(1947), 0),
  ("Marshall Planı'nın açıklanması", _sy(1947), 0),
  ("Berlin Ablukası'nın başlaması", _sy(1948), 0),
  ("NATO'nun kurulması", _sy(1949), 0),
  ("Çin Halk Cumhuriyeti'nin ilan edilmesi", _sy(1949), 0),
  ("SSCB'nin ilk atom bombası denemesini yapması", _sy(1949), 0),
  ("Kore Savaşı'nın başlaması", _sy(1950), 0),
  ("Türkiye'nin Kore'ye asker göndermesi", _sy(1950), 0),
  ("Türkiye'nin NATO'ya üye olması", _sy(1952), 0),
  ("Kore Savaşı'nda ateşkes imzalanması", _sy(1953), 0),
  ("Stalin'in ölmesi", _sy(1953), 0),
  ("SEATO'nun kurulması", _sy(1954), 0),
  ("Bağdat Paktı'nın kurulması", _sy(1955), 0),
  ("Varşova Paktı'nın kurulması", _sy(1955), 0),
  ('Süveyş Krizi', _sy(1956), 0),
  ("Macaristan'daki ayaklanmanın Sovyet ordusunca bastırılması", _sy(1956), 0),
  ('Sputnik uydusunun fırlatılması', _sy(1957), 0),
  ("Eisenhower Doktrini'nin ilan edilmesi", _sy(1957), 0),
  (
    "Türkiye'nin Avrupa Ekonomik Topluluğuna ortaklık başvurusu yapması",
    _sy(1959),
    0,
  ),
  ("Bağdat Paktı'nın CENTO adını alması", _sy(1959), 0),
  ("Berlin Duvarı'nın yapılması", _sy(1961), 0),
  ('Küba Füze Krizi', _sy(1962), 0),
  ("Johnson Mektubu'nun Türkiye'ye gönderilmesi", _sy(1964), 0),
  ("Prag Baharı'nın Varşova Paktı kuvvetlerince bastırılması", _sy(1968), 0),
  ("İnsanlı bir uzay aracının Ay'a ilk kez inmesi", _sy(1969), 0),
  ("ABD ile SSCB arasında SALT I Antlaşması'nın imzalanması", _sy(1972), 0),
  ('Kıbrıs Barış Harekâtı', _sy(1974), 0),
  ("Helsinki Nihai Senedi'nin imzalanması", _sy(1975), 0),
  ("ABD'nin Türkiye'ye silah ambargosu uygulamaya başlaması", _sy(1975), 0),
  ("SSCB'nin Afganistan'ı işgal etmesi", _sy(1979), 0),
  ('İran İslam Devrimi', _sy(1979), 0),
  ("Kuzey Kıbrıs Türk Cumhuriyeti'nin ilan edilmesi", _sy(1983), 0),
  ('Çernobil Nükleer Santrali kazası', _sy(1986), 0),
  ("Berlin Duvarı'nın yıkılması", _sy(1989), 0),
  ("Doğu ve Batı Almanya'nın birleşmesi", _sy(1990), 0),
  ("Varşova Paktı'nın feshedilmesi", _sy(1991), 0),
  ("SSCB'nin dağılması", _sy(1991), 0),
];

const _ittifakAd = [
  ('NATO', "NATO'ya"),
  ('Varşova Paktı', "Varşova Paktı'na"),
  ('Bağdat Paktı', "Bağdat Paktı'na"),
  ('SEATO', "SEATO'ya"),
  ('Balkan Paktı', "Balkan Paktı'na"),
  ('Truman Doktrini', "Truman Doktrini'ne"),
  ('Marshall Planı', "Marshall Planı'na"),
  ('Eisenhower Doktrini', "Eisenhower Doktrini'ne"),
];

// Truman Doktrini, Marshall Planı ve Eisenhower Doktrini'nin kapsamları kısmen
// örtüştüğü için ilgili bilgiler karşılıklı maskelidir.
const _ittifak = <(String, int, int)>[
  ('1949 yılında ABD önderliğinde kurulmuştur.', 0, 0),
  ("1952 yılında Türkiye ve Yunanistan'ı üyeliğe kabul etmiştir.", 0, 0),
  ('Kuzey Atlantik ülkelerinin ortak savunması amacıyla kurulmuştur.', 0, 0),
  ('1955 yılında SSCB önderliğinde kurulmuştur.', 1, 0),
  ("Doğu Bloku ülkelerinin NATO'ya karşı oluşturduğu askerî ittifaktır.", 1, 0),
  ('1991 yılında feshedilmiştir.', 1, 0),
  ('Türkiye, Irak, İran, Pakistan ve İngiltere tarafından kurulmuştur.', 2, 0),
  ("Irak'ın ayrılmasından sonra CENTO adını almıştır.", 2, 0),
  (
    "Orta Doğu'da Sovyet yayılmacılığını önlemek amacıyla kurulmuştur.",
    2,
    1 << 5 | 1 << 7,
  ),
  (
    "Güneydoğu Asya'da komünizmin yayılmasını önlemek amacıyla kurulmuştur.",
    3,
    0,
  ),
  ('1954 yılında Manila Antlaşması ile kurulmuştur.', 3, 0),
  ('Türkiye, Yunanistan ve Yugoslavya arasında kurulmuştur.', 4, 0),
  (
    "Yugoslavya'nın SSCB ile ilişkilerini düzeltmesi üzerine etkisini yitirmiştir.",
    4,
    0,
  ),
  (
    "Türkiye ve Yunanistan'a askerî ve ekonomik yardım yapılmasını öngörmüştür.",
    5,
    1 << 6 | 1 << 7,
  ),
  ('1947 yılında ABD Başkanı tarafından ilan edilmiştir.', 5, 1 << 6),
  (
    "SSCB'nin Boğazlar ve Doğu Anadolu üzerindeki isteklerine karşı Türkiye'ye destek sağlamıştır.",
    5,
    1 << 6,
  ),
  (
    'Avrupa ülkelerinin savaş sonrasında ekonomik olarak kalkınmasını amaçlamıştır.',
    6,
    1 << 5,
  ),
  (
    "yardımların dağıtımı için Avrupa Ekonomik İş Birliği Örgütü'nün kurulmasına yol açmıştır.",
    6,
    0,
  ),
  (
    "1957 yılında Orta Doğu ülkelerine askerî ve ekonomik yardım yapılmasını öngörmüştür.",
    7,
    0,
  ),
  (
    "Süveyş Krizi'nden sonra Orta Doğu'da oluşan boşluğu doldurmak amacıyla ilan edilmiştir.",
    7,
    0,
  ),
];

// On beşlik döngü: olay-yıl biçimleri (3.000 vaka) ve ittifak-doktrin biçimleri
// (2.000 vaka).
const _sogukOlayDongu = [0, 9, 1, 9, 2, 0, 9, 1, 9, 2, 0, 1, 9, 2, 9];
const _ittifakDongu = [9, 0, 9, 1, 9, 9, 2, 9, 0, 9, 9, 9, 1, 9, 2];

final _sogukOlayOlgu = _Ozneli(
  _sogukOlay,
  _sogukYil,
  _sogukOlayDongu,
  donem: true,
  sirali:
      'Soğuk Savaş dönemine ait bu gelişmelerin yılları sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
  hangileri: (s) =>
      'Soğuk Savaş dönemine ait bu gelişmelerden hangileri $s gerçekleşmiştir?',
  onerme: 'Soğuk Savaş dönemindeki gelişmelerle ilgili bu bilgilerden hangileri doğrudur?',
);

final _ittifakOlgu = _Ozneli(
  _ittifak,
  _ittifakAd,
  _ittifakDongu,
  sirali:
      'Soğuk Savaş dönemindeki ittifak ve doktrinlerle ilgili bu bilgilerin ait olduğu '
      'ittifak ya da doktrinler sırasıyla hangi seçenekte doğru verilmiştir?',
  hangileri: (s) =>
      'Soğuk Savaş dönemindeki ittifak ve doktrinlerle ilgili bu bilgilerden hangileri $s aittir?',
  onerme: 'Soğuk Savaş dönemindeki ittifak ve doktrinlerle ilgili bu bilgilerden hangileri doğrudur?',
);

AdvancedItem _sogukSavasSoru(int i) =>
    _sogukOlayDongu[i % 15] < 3 ? _sogukOlayOlgu(i) : _ittifakOlgu(i);

// ─────────────────── 11 · Atatürk dönemi Türk dış politikası ────────────────

const _disKonu = [
  ('Musul Sorunu', 'Musul Sorunu ile'),
  ('Türk-Yunan nüfus mübadelesi', 'Türk-Yunan nüfus mübadelesi ile'),
  ('Balkan Antantı', 'Balkan Antantı ile'),
  ('Montrö Boğazlar Sözleşmesi', 'Montrö Boğazlar Sözleşmesi ile'),
  ('Sadabat Paktı', 'Sadabat Paktı ile'),
  ('Hatay Sorunu', 'Hatay Sorunu ile'),
  ('Osmanlı borçları', 'Osmanlı borçları ile'),
];

// Yükleme özne olarak konunun adı gelir. Balkan Antantı ile Sadabat Paktı'nın
// ortak arka planı (İtalya'nın yayılmacılığı) karşılıklı maskelidir.
const _dis = <(String, int, int)>[
  (
    "Lozan Konferansı'nda çözülemeyerek Türkiye ile İngiltere arasındaki ikili görüşmelere bırakılmıştır.",
    0,
    0,
  ),
  (
    "1924 yılındaki Haliç Konferansı'nda görüşülmüş ancak çözüme kavuşturulamamıştır.",
    0,
    0,
  ),
  (
    "Milletler Cemiyeti'ne götürülmüş ve Cemiyet bölgenin Irak'a bırakılmasına karar vermiştir.",
    0,
    1 << 5,
  ),
  ('Şeyh Sait İsyanı nedeniyle Türkiye aleyhine sonuçlanmıştır.', 0, 0),
  ('1926 Ankara Antlaşması ile çözülmüştür.', 0, 0),
  (
    'Lozan Konferansı sırasında Türkiye ile Yunanistan arasında imzalanan bir sözleşmeyle kararlaştırılmıştır.',
    1,
    0,
  ),
  (
    "İstanbul'daki Rumları ve Batı Trakya'daki Türkleri kapsam dışında bırakmıştır.",
    1,
    0,
  ),
  (
    'etabli sorunu nedeniyle Türk-Yunan ilişkilerinin gerginleşmesine yol açmıştır.',
    1,
    0,
  ),
  ('1930 Ankara Antlaşması ile kesin çözüme kavuşturulmuştur.', 1, 0),
  (
    '1934 yılında Türkiye, Yunanistan, Romanya ve Yugoslavya arasında imzalanmıştır.',
    2,
    0,
  ),
  (
    "İtalya'nın Balkanlara yönelik yayılmacı politikasına karşı oluşturulmuştur.",
    2,
    1 << 4,
  ),
  ("Bulgaristan ve Arnavutluk'un katılmadığı bir bölgesel ittifaktır.", 2, 0),
  ('1936 yılında imzalanmıştır.', 3, 0),
  ("Boğazlar Komisyonu'nun kaldırılmasını sağlamıştır.", 3, 0),
  ('Boğazlar bölgesinin Türk askerî denetimine geçmesini sağlamıştır.', 3, 0),
  (
    "Lozan'da Boğazlarla ilgili alınan kararların Türkiye lehine değiştirilmesini sağlamıştır.",
    3,
    0,
  ),
  (
    '1937 yılında Türkiye, İran, Irak ve Afganistan arasında imzalanmıştır.',
    4,
    0,
  ),
  ("Tahran'daki Sadabat Sarayı'nda imzalanmıştır.", 4, 0),
  (
    "Orta Doğu'da barışı korumayı amaçlayan bir saldırmazlık paktıdır.",
    4,
    1 << 2,
  ),
  (
    "Fransa'nın 1936 yılında Suriye'ye bağımsızlık tanımak istemesi üzerine gündeme gelmiştir.",
    5,
    0,
  ),
  (
    "Milletler Cemiyeti'nin hazırladığı bir statüyle bölgeye özerklik tanınmasıyla yeni bir aşamaya girmiştir.",
    5,
    1,
  ),
  ("1938 yılında Hatay Devleti'nin kurulmasına yol açmıştır.", 5, 0),
  ("1939 yılında bölgenin Türkiye'ye katılmasıyla çözülmüştür.", 5, 0),
  ("Atatürk'ün “şahsi meselem” olarak nitelendirdiği sorundur.", 5, 0),
  (
    "Lozan Antlaşması ile Osmanlı Devleti'nden ayrılan devletler arasında paylaştırılmıştır.",
    6,
    0,
  ),
  (
    "Türkiye'nin payına düşen kısmın 1954 yılında ödenmesiyle kapanmıştır.",
    6,
    0,
  ),
  ('1929 yılından itibaren taksitler hâlinde ödenmeye başlanmıştır.', 6, 0),
];

final _disOlgu = _Ozneli(
  _dis,
  _disKonu,
  const [0, 1, 2],
  fiil: 'ilgilidir',
  sifat: 'ilgili olanlar',
  sirali:
      'Atatürk dönemi Türk dış politikasına ait bu bilgilerin ilgili olduğu konular '
      'sırasıyla hangi seçenekte doğru verilmiştir?',
  hangileri: (s) =>
      'Atatürk dönemi Türk dış politikasına ait bu bilgilerden hangileri $s ilgilidir?',
  onerme: 'Atatürk dönemi Türk dış politikasıyla ilgili bu bilgilerden hangileri doğrudur?',
);

// ─────────────── 12 · Çok partili hayata geçiş denemeleri (1924–1950) ───────

const _siyasiAd = [
  ('Terakkiperver Cumhuriyet Fırkası', 'Terakkiperver Cumhuriyet Fırkası ile'),
  ('Serbest Cumhuriyet Fırkası', 'Serbest Cumhuriyet Fırkası ile'),
  ('Milli Kalkınma Partisi', 'Milli Kalkınma Partisi ile'),
  ('Demokrat Parti', 'Demokrat Parti ile'),
  ('Cumhuriyet Halk Partisi', 'Cumhuriyet Halk Partisi ile'),
  ('Şeyh Sait İsyanı', 'Şeyh Sait İsyanı ile'),
  ('Takrir-i Sükûn Kanunu', 'Takrir-i Sükûn Kanunu ile'),
  ('İzmir Suikastı girişimi', 'İzmir Suikastı girişimi ile'),
  ('Menemen Olayı', 'Menemen Olayı ile'),
  ('Dörtlü Takrir', 'Dörtlü Takrir ile'),
  ('12 Temmuz Beyannamesi', '12 Temmuz Beyannamesi ile'),
  ('1946 seçimleri', '1946 seçimleri ile'),
  ('1950 seçimleri', '1950 seçimleri ile'),
];

// Partiler (0–4) ve olaylar (5–12) ayrı öbeklerdir.
const _siyasi = <(String, int, int)>[
  (
    '1924 yılında Kâzım Karabekir, Ali Fuat Cebesoy ve Rauf Orbay gibi isimlerce kurulmuştur.',
    0,
    0,
  ),
  ("Şeyh Sait İsyanı'yla ilişkilendirilerek 1925 yılında kapatılmıştır.", 0, 0),
  ('programında dinî inançlara saygılı olduğunu belirtmiştir.', 0, 0),
  ('Cumhuriyet döneminin ilk muhalefet partisidir.', 0, 0),
  ('yerinden yönetim (adem-i merkeziyet) anlayışını savunmuştur.', 0, 0),
  (
    "1930 yılında Atatürk'ün isteğiyle Fethi Okyar tarafından kurulmuştur.",
    1,
    0,
  ),
  (
    'rejim karşıtlarının etrafında toplanması üzerine kendini kapatmıştır.',
    1,
    0,
  ),
  (
    '1930 belediye seçimlerinde Cumhuriyet Halk Fırkasına rakip olmuştur.',
    1,
    1 << 4,
  ),
  ('1945 yılında Nuri Demirağ tarafından kurulmuştur.', 2, 0),
  (
    'çok partili hayata geçiş sürecinde kurulan ilk muhalefet partisidir.',
    2,
    1 | 1 << 1,
  ),
  ("Dörtlü Takrir'i veren milletvekillerince 1946 yılında kurulmuştur.", 3, 0),
  ('1950 seçimlerini kazanarak iktidara gelmiştir.', 3, 0),
  ('1946 seçimlerine katılarak Büyük Millet Meclisine girmiştir.', 3, 1 << 4),
  ('1923 yılında Halk Fırkası adıyla kurulmuştur.', 4, 0),
  ('1924 yılında adına Cumhuriyet sözcüğünü eklemiştir.', 4, 0),
  ('1931 kurultayında altı ilkeyi programına almıştır.', 4, 0),
  ('1946 seçimlerinde iktidarını korumuştur.', 4, 0),
  ("1950 seçimlerinde iktidarı Demokrat Parti'ye bırakmıştır.", 4, 1 << 3),
  ("1925 yılında Doğu Anadolu'da çıkmıştır.", 5, 1 << 6),
  ("Takrir-i Sükûn Kanunu'nun çıkarılmasına yol açmıştır.", 5, 0),
  ("Musul Sorunu'nun Türkiye aleyhine sonuçlanmasında etkili olmuştur.", 5, 0),
  ('hükûmete olağanüstü yetkiler vermiştir.', 6, 1 << 5),
  ('1929 yılına kadar yürürlükte kalmıştır.', 6, 0),
  ('basın üzerinde sıkı bir denetim kurulmasına imkân vermiştir.', 6, 1 << 5),
  ("1926 yılında Mustafa Kemal'e karşı planlanmıştır.", 7, 0),
  ('eski İttihatçıların yargılanmasına yol açmıştır.', 7, 0),
  (
    "1930 yılında yedek subay Kubilay'ın şehit edilmesiyle sonuçlanmıştır.",
    8,
    0,
  ),
  ('Serbest Cumhuriyet Fırkası kapandıktan kısa süre sonra yaşanmıştır.', 8, 0),
  (
    "1945 yılında Celal Bayar, Adnan Menderes, Refik Koraltan ve Fuat Köprülü tarafından "
        "Cumhuriyet Halk Partisi'ne verilmiştir.",
    9,
    0,
  ),
  ('parti içi demokrasinin genişletilmesini istemiştir.', 9, 0),
  ('1947 yılında İsmet İnönü tarafından yayımlanmıştır.', 10, 0),
  ('iktidar ile muhalefete eşit davranılacağını duyurmuştur.', 10, 0),
  ('açık oy, gizli sayım yöntemiyle yapılmıştır.', 11, 0),
  ('çok partili ilk genel seçimdir.', 11, 0),
  ('gizli oy, açık sayım yöntemiyle yapılmıştır.', 12, 0),
  ("Demokrat Parti'nin iktidara gelmesini sağlamıştır.", 12, 0),
];

final _siyasiOlgu = _Ozneli(
  _siyasi,
  _siyasiAd,
  const [0, 1, 2],
  fiil: 'ilgilidir',
  sifat: 'ilgili olanlar',
  grup: const [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1],
  sirali:
      'Cumhuriyet döneminin siyasi gelişmelerine ait bu bilgilerin ilgili olduğu parti ya da '
      'gelişmeler sırasıyla hangi seçenekte doğru verilmiştir?',
  hangileri: (s) =>
      'Cumhuriyet döneminin siyasi gelişmelerine ait bu bilgilerden hangileri $s ilgilidir?',
  onerme: 'Cumhuriyet dönemindeki siyasi gelişmelerle ilgili bu bilgilerden hangileri doğrudur?',
);

// ─────────────────────── 13 · Felsefe disiplinleri ──────────────────────────

const _disiplin = [
  ('Bilgi felsefesi', 'bilgi felsefesinin'),
  ('Varlık felsefesi', 'varlık felsefesinin'),
  ('Ahlak felsefesi', 'ahlak felsefesinin'),
  ('Sanat felsefesi', 'sanat felsefesinin'),
  ('Siyaset felsefesi', 'siyaset felsefesinin'),
  ('Din felsefesi', 'din felsefesinin'),
  ('Bilim felsefesi', 'bilim felsefesinin'),
];

// Sorular, ait oldukları disiplin açıkça anlaşılacak biçimde yazılmıştır;
// iki alana yakıştırılabilecekler maskelidir.
const _felsefeSoru = <(String, int, int)>[
  ('Doğru bilgi mümkün müdür?', 0, 0),
  ('Bilginin kaynağı akıl mıdır, deney midir?', 0, 1 << 6),
  ('İnsan bilgisinin sınırları var mıdır?', 0, 1 << 6),
  ('Doğruluğun ölçütü nedir?', 0, 1 << 6),
  ('Bir bilginin doğru olduğundan nasıl emin olabiliriz?', 0, 1 << 6),
  ('Duyularımız bizi yanıltabilir mi?', 0, 0),
  ('Bilen özne ile bilinen nesne arasındaki ilişki nasıldır?', 0, 0),
  ('Şüphe götürmez kesin bir bilgiye ulaşılabilir mi?', 0, 1 << 6),
  ('Varlığın ilk nedeni nedir?', 1, 1 << 5),
  ('Varlığın ana maddesi (arkhesi) nedir?', 1, 0),
  ('Varlık tek bir ilkeden mi yoksa birden çok ilkeden mi oluşur?', 1, 0),
  ('Gerçekten var olan madde midir, düşünce midir?', 1, 0),
  ('Varlık sürekli değişir mi, yoksa değişmez midir?', 1, 0),
  ('Hiçlik var mıdır?', 1, 0),
  ('Var olmak ne demektir?', 1, 0),
  ('Görünen dünyanın ardında değişmeyen bir gerçeklik var mıdır?', 1, 0),
  ('İyi ve kötünün ölçütü nedir?', 2, 0),
  ('Evrensel bir ahlak yasası var mıdır?', 2, 0),
  (
    'İnsanın eylemlerinden sorumlu tutulabilmesi için özgür olması gerekir mi?',
    2,
    0,
  ),
  ('Mutluluk ahlaki eylemin amacı olabilir mi?', 2, 0),
  ('Bir eylemi ahlaki kılan, sonucu mudur yoksa niyeti midir?', 2, 0),
  ('Erdemli bir insan nasıl davranır?', 2, 0),
  ('Vicdan ahlaki kararlarımızda güvenilir bir rehber midir?', 2, 0),
  ('Yalan söylemek her durumda yanlış mıdır?', 2, 0),
  ('Güzel nedir?', 3, 0),
  ('Bir sanat eserini değerli kılan nedir?', 3, 0),
  (
    'Güzellik nesnenin kendisinde midir, yoksa onu algılayan kişide midir?',
    3,
    0,
  ),
  ('Sanat doğanın taklidi midir?', 3, 0),
  ('Sanatçıyı yaratmaya yönelten nedir?', 3, 0),
  ('Bir resmin sanat eseri sayılmasının ölçütü nedir?', 3, 0),
  (
    'Sanatın bir amacı olmalı mıdır, yoksa sanat kendi başına mı değerlidir?',
    3,
    0,
  ),
  ('Güzellik yargıları herkes için geçerli olabilir mi?', 3, 0),
  ('İdeal devlet düzeni nasıl olmalıdır?', 4, 0),
  ('Siyasi iktidarın meşruiyetinin kaynağı nedir?', 4, 0),
  ('Bireyin hakları ile devletin yetkileri arasındaki sınır nedir?', 4, 0),
  ('Yönetme hakkı kime aittir?', 4, 0),
  ('Devlet düzeninde adalet nasıl sağlanır?', 4, 1 << 2),
  ('Toplum sözleşmesi devletin temeli olabilir mi?', 4, 0),
  ('Halkın yönetime katılması neden önemlidir?', 4, 0),
  ('Yurttaşlar devlete hangi koşullarda itaat etmelidir?', 4, 0),
  ("Tanrı'nın varlığı akılla kanıtlanabilir mi?", 5, 1),
  ('Ruh ölümsüz müdür?', 5, 1 << 1),
  (
    "Evrendeki kötülük, iyi ve her şeye gücü yeten bir Tanrı inancıyla nasıl bağdaşır?",
    5,
    1 << 2,
  ),
  ("Tanrı ile evren arasında nasıl bir ilişki vardır?", 5, 1 << 1),
  ('Ölümden sonra yaşam var mıdır?', 5, 0),
  ('Dinî inanç ile akıl arasında nasıl bir ilişki vardır?', 5, 1),
  ("Tanrı'nın sıfatları nelerdir?", 5, 0),
  ('Bilimsel yöntemin özellikleri nelerdir?', 6, 0),
  ('Bilimsel bir kuramı bilimsel olmayandan ayıran ölçüt nedir?', 6, 0),
  ('Bilimsel bilgi kesin midir?', 6, 1),
  ('Bilim değerlerden bağımsız mıdır?', 6, 1 << 2),
  ('Bilimsel gelişme birikimle mi yoksa devrimlerle mi gerçekleşir?', 6, 0),
  ('Bilimsel bir yasa nasıl doğrulanır?', 6, 1),
  ('Bilimin amacı doğayı açıklamak mı, yoksa ona hâkim olmak mıdır?', 6, 0),
  ('Bilimsel bilgi nasıl üretilir?', 6, 1),
];

final _disiplinOlgu = _Ozneli(
  _felsefeSoru,
  _disiplin,
  const [0, 1, 2],
  ogeYaz: (s) => s,
  onermeYaz: (s, d) => '“$s” sorusu ${d.$2} konusudur.',
  ozetYaz: (d) => '${_buyuk(d.$2)} konusu olanlar',
  dokumYaz: (s, d) => '“$s” ${d.$2} konusudur',
  sirali:
      'Bu soruların ait olduğu felsefe disiplinleri sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
  hangileri: (s) => 'Bu sorulardan hangileri $s konusudur?',
  onerme: 'Felsefe disiplinleriyle ilgili bu bilgilerden hangileri doğrudur?',
);

// ────────────────────── 14 · Filozoflar ve görüşleri ────────────────────────

const _filozof = [
  ('Thales', "Thales'e"),
  ('Anaksimandros', "Anaksimandros'a"),
  ('Anaksimenes', "Anaksimenes'e"),
  ('Herakleitos', "Herakleitos'a"),
  ('Parmenides', "Parmenides'e"),
  ('Pisagor', "Pisagor'a"),
  ('Empedokles', "Empedokles'e"),
  ('Demokritos', "Demokritos'a"),
  ('Protagoras', "Protagoras'a"),
  ('Sokrates', "Sokrates'e"),
  ('Platon', "Platon'a"),
  ('Aristoteles', "Aristoteles'e"),
  ('Descartes', "Descartes'a"),
  ('Francis Bacon', "Francis Bacon'a"),
  ('Kant', "Kant'a"),
  ('Hegel', "Hegel'e"),
  ('Marx', "Marx'a"),
  ('Nietzsche', "Nietzsche'ye"),
  ('Sartre', "Sartre'a"),
  ('Spinoza', "Spinoza'ya"),
  ('Leibniz', "Leibniz'e"),
  ('Wittgenstein', "Wittgenstein'a"),
  ('Hume', "Hume'a"),
  ('Locke', "Locke'a"),
];

// Siyaset ve ahlak akımlarına ait görüşler 16. ve 17. ailelerde sorulduğu için
// burada ağırlık ünlü söz ve temel düşüncelerdedir.
const _filozofGorus = <(String, int, int)>[
  ('her şeyin ana maddesinin su olduğunu ileri sürmüştür.', 0, 0),
  (
    'evreni mitolojiye başvurmadan açıklamaya çalışan ilk filozof kabul edilir.',
    0,
    0,
  ),
  (
    'varlığın ana maddesinin sınırsız ve belirsiz olan apeiron olduğunu söylemiştir.',
    1,
    0,
  ),
  ('varlığın ana maddesinin hava olduğunu savunmuştur.', 2, 0),
  (
    '“Aynı ırmakta iki kez yıkanılmaz.” sözüyle her şeyin değiştiğini anlatmıştır.',
    3,
    0,
  ),
  ('evrendeki değişimi yöneten düzen ilkesine logos adını vermiştir.', 3, 0),
  ('ana maddenin ateş olduğunu ileri sürmüştür.', 3, 1 << 6),
  (
    'değişimin bir yanılsama olduğunu, varlığın tek ve değişmez olduğunu savunmuştur.',
    4,
    0,
  ),
  ('“Var olan vardır, var olmayan yoktur.” demiştir.', 4, 0),
  ('varlığın temel ilkesinin sayı olduğunu ileri sürmüştür.', 5, 0),
  (
    'varlığın su, hava, toprak ve ateşten oluştuğunu, bunları sevgi ile nefretin birleştirip '
        'ayırdığını söylemiştir.',
    6,
    0,
  ),
  (
    'varlığın bölünemeyen küçük parçacıklardan, yani atomlardan oluştuğunu savunmuştur.',
    7,
    0,
  ),
  (
    '“İnsan her şeyin ölçüsüdür.” sözüyle bilginin göreceli olduğunu savunmuştur.',
    8,
    0,
  ),
  ('“Kendini bil.” ilkesini benimsemiştir.', 9, 0),
  (
    'erdemin bilgi olduğunu, kimsenin bile bile kötülük yapmayacağını savunmuştur.',
    9,
    1 << 10,
  ),
  (
    'doğru bilgiye soru sorarak ulaşmayı amaçlayan doğurtma yöntemini kullanmıştır.',
    9,
    0,
  ),
  ('“Bildiğim tek şey, hiçbir şey bilmediğimdir.” demiştir.', 9, 0),
  (
    'duyular dünyasının ötesinde değişmez idealar dünyasının bulunduğunu savunmuştur.',
    10,
    0,
  ),
  (
    'mağara alegorisiyle duyularla algılanan dünyanın gerçeğin gölgesi olduğunu anlatmıştır.',
    10,
    0,
  ),
  ("Atina'da Akademia adlı okulu kurmuştur.", 10, 0),
  ('mantığın kurucusu kabul edilir.', 11, 0),
  ("Atina'da Lykeion adlı okulu kurmuştur.", 11, 0),
  (
    'erdemi aşırılık ile eksiklik arasındaki orta yol olarak tanımlamıştır.',
    11,
    0,
  ),
  (
    '“Düşünüyorum, öyleyse varım.” sözüyle kesin bilgiye ulaştığını ileri sürmüştür.',
    12,
    0,
  ),
  ('kesin bilgiye ulaşmak için yöntemli şüpheyi kullanmıştır.', 12, 0),
  ('“Bilgi güçtür.” sözüyle tanınır.', 13, 0),
  (
    'doğru bilgiye ulaşmayı engelleyen yanılgılara idoller adını vermiştir.',
    13,
    0,
  ),
  ('“İçeriksiz düşünceler boş, kavramsız görüler kördür.” demiştir.', 14, 0),
  (
    'insanın hiçbir zaman yalnızca bir araç olarak görülmemesi gerektiğini savunmuştur.',
    14,
    0,
  ),
  ('tarihi tinin diyalektik gelişimi olarak açıklamıştır.', 15, 0),
  (
    '“Filozoflar dünyayı yalnızca yorumladılar, oysa önemli olan onu değiştirmektir.” demiştir.',
    16,
    0,
  ),
  (
    '“Tanrı öldü.” sözüyle geleneksel değerlerin çöktüğünü ileri sürmüştür.',
    17,
    0,
  ),
  ('üstinsan kavramını geliştirmiştir.', 17, 0),
  ('“Varoluş özden önce gelir.” demiştir.', 18, 0),
  ('insanın özgür olmaya mahkûm olduğunu söylemiştir.', 18, 0),
  ('Tanrı ile doğayı özdeş görmüştür.', 19, 0),
  (
    'evrenin monad adı verilen bölünmez birimlerden oluştuğunu söylemiştir.',
    20,
    0,
  ),
  ('“Dilimin sınırları dünyamın sınırlarıdır.” demiştir.', 21, 0),
  ('nedensellik düşüncesinin alışkanlıktan doğduğunu ileri sürmüştür.', 22, 0),
  (
    'insan zihninin doğuştan boş bir levha olduğunu savunmuştur.',
    23,
    1 << 11 | 1 << 22,
  ),
];

final _filozofOlgu = _Ozneli(
  _filozofGorus,
  _filozof,
  const [0, 1, 2],
  oge: 'görüş',
  sirali:
      'Bu görüş ve sözlerin sahibi olan filozoflar sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
  hangileri: (s) => 'Bu görüş ve sözlerden hangileri $s aittir?',
  onerme: 'Filozoflarla ilgili bu bilgilerden hangileri doğrudur?',
);

// ───────────────────── 15 · Bilgi felsefesinde akımlar ──────────────────────

const _bilgiAkim = [
  ('Rasyonalizm', 'rasyonalizme'),
  ('Empirizm', 'empirizme'),
  ('Kritisizm', 'kritisizme'),
  ('Sezgicilik', 'sezgiciliğe'),
  ('Pozitivizm', 'pozitivizme'),
  ('Pragmatizm', 'pragmatizme'),
  ('Fenomenoloji', 'fenomenolojiye'),
  ('Septisizm', 'septisizme'),
];

// Sezgicilik ile fenomenolojinin doğrudan kavrayış, septisizm ile
// fenomenolojinin yargıyı askıya alma vurguları karşılıklı maskelidir; Kant'ın
// a priori bilgi ve metafizik eleştirisi rasyonalizm ve pozitivizm görüşlerinde,
// deneycilerin metafizik eleştirisi pozitivizm görüşlerinde maskelenmiştir.
const _bilgiGorus = <(String, int, int)>[
  ('doğru bilginin kaynağının akıl olduğunu savunur.', 0, 0),
  (
    'insan zihninde doğuştan getirilen ilkeler bulunduğunu kabul eder.',
    0,
    1 << 2,
  ),
  (
    'kesin bilginin evrensel ve zorunlu olduğunu, bunun da ancak akılla elde edilebileceğini savunur.',
    0,
    1 << 2,
  ),
  (
    'matematiksel akıl yürütmeyi kesin bilginin örneği sayar.',
    0,
    1 << 2 | 1 << 4,
  ),
  ('Descartes, Spinoza ve Leibniz tarafından temsil edilir.', 0, 0),
  ('bilginin kaynağının duyu deneyimi olduğunu savunur.', 1, 0),
  ('insan zihninin doğuştan boş bir levha olduğunu kabul eder.', 1, 0),
  (
    'duyularda bulunmayan hiçbir şeyin akılda da bulunamayacağını ileri sürer.',
    1,
    1 << 4,
  ),
  (
    'genel bilgilere tek tek gözlemlerden tümevarım yoluyla ulaşılacağını savunur.',
    1,
    1 << 4,
  ),
  ('John Locke, George Berkeley ve David Hume tarafından temsil edilir.', 1, 0),
  ('bilginin akıl ile deneyin birlikte çalışmasıyla oluştuğunu savunur.', 2, 0),
  (
    'kendinde şeyin bilinemeyeceğini, yalnızca bize görünen dünyanın bilinebileceğini ileri sürer.',
    2,
    0,
  ),
  (
    'duyuların sağladığı malzemenin aklın kategorileriyle düzenlendiğini savunur.',
    2,
    0,
  ),
  ('Immanuel Kant tarafından geliştirilmiştir.', 2, 0),
  (
    'gerçek bilgiye akıl ya da duyularla değil sezgi yoluyla ulaşılabileceğini savunur.',
    3,
    0,
  ),
  (
    'varlığın özünün ancak doğrudan ve aracısız bir kavrayışla bilinebileceğini ileri sürer.',
    3,
    1 << 6,
  ),
  (
    'akla dayalı bilginin parçalı olduğunu, bütünü ancak sezginin kavrayabileceğini savunur.',
    3,
    0,
  ),
  ('Henri Bergson ve Gazali tarafından temsil edilir.', 3, 0),
  (
    'yalnızca gözlemlenebilen olgulara dayanan bilimsel bilginin geçerli olduğunu savunur.',
    4,
    1 << 1,
  ),
  ('metafizik konuları bilginin alanı dışında bırakır.', 4, 1 << 1 | 1 << 2),
  (
    'insanlığın teolojik, metafizik ve pozitif aşamalardan geçtiğini ileri sürer.',
    4,
    0,
  ),
  ('Auguste Comte tarafından kurulmuştur.', 4, 0),
  (
    'bir bilginin doğruluğunu pratik yaşamdaki yararına göre değerlendirir.',
    5,
    0,
  ),
  ('işe yarayan bilginin doğru bilgi olduğunu savunur.', 5, 0),
  (
    'bilgiyi insanın karşılaştığı sorunları çözmeye yarayan bir araç olarak görür.',
    5,
    0,
  ),
  (
    'William James, Charles Peirce ve John Dewey tarafından temsil edilir.',
    5,
    0,
  ),
  (
    'bilginin, bilincin yöneldiği nesnelerin özünün betimlenmesiyle elde edileceğini savunur.',
    6,
    0,
  ),
  (
    'ön yargıları paranteze alarak “şeylerin kendisine” dönmek gerektiğini ileri sürer.',
    6,
    1 << 7,
  ),
  (
    'özün ancak öz görüsü adı verilen bir bilinç tutumuyla kavranabileceğini savunur.',
    6,
    1 << 3,
  ),
  ('Edmund Husserl tarafından geliştirilmiştir.', 6, 0),
  ('kesin ve doğru bilginin mümkün olmadığını savunur.', 7, 0),
  (
    'hiçbir konuda kesin yargıda bulunmamanın insanı huzura kavuşturacağını savunur.',
    7,
    1 << 6,
  ),
  ('Pyrrhon tarafından kurulmuştur.', 7, 0),
];

final _bilgiAkimOlgu = _Ozneli(
  _bilgiGorus,
  _bilgiAkim,
  const [0, 1, 2],
  oge: 'görüş',
  sirali:
      'Bu görüşlerin ait olduğu bilgi felsefesi akımları sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
  hangileri: (s) => 'Bilgi felsefesine ait bu görüşlerden hangileri $s aittir?',
  onerme: 'Bilgi felsefesindeki akımlarla ilgili bu bilgilerden hangileri doğrudur?',
);

// ─────────────────────── 16 · Ahlak felsefesinde yaklaşımlar ────────────────

const _ahlakAkim = [
  ('Hazcılık', 'hazcılığa'),
  ('Mutluluk ahlakı', 'mutluluk ahlakına'),
  ('Faydacılık', 'faydacılığa'),
  ('Ödev ahlakı', 'ödev ahlakına'),
  ('Bencillik', 'bencilliğe'),
  ('Varoluşçuluk', 'varoluşçuluğa'),
  ('Nihilizm', 'nihilizme'),
  ('Ahlaki görecelik', 'ahlaki göreceliğe'),
];

// Haz, mutluluk ve fayda kavramlarının örtüştüğü yerler karşılıklı maskelidir.
const _ahlakGorus = <(String, int, int)>[
  ('ahlaki eylemin amacının haz elde etmek olduğunu savunur.', 0, 1 << 2),
  ('iyiyi hazla, kötüyü acıyla özdeşleştirir.', 0, 1 << 2),
  (
    'ölçülü hazların ve ruhsal dinginliğin peşinden gidilmesini öğütler.',
    0,
    1 << 1,
  ),
  ('Aristippos ve Epikuros tarafından temsil edilir.', 0, 0),
  ('Kyrene okulunun ahlak anlayışının temelini oluşturur.', 0, 0),
  (
    'mutluluğa erdemli bir yaşam ve ölçülülükle ulaşılabileceğini savunur.',
    1,
    0,
  ),
  ('Aristoteles ve Farabi tarafından temsil edilir.', 1, 0),
  ('erdemi aşırılık ile eksiklik arasındaki orta yol olarak tanımlar.', 1, 0),
  (
    'mutluluğu, insanın kendi doğasına uygun etkinliği akıl yoluyla gerçekleştirmesi olarak görür.',
    1,
    0,
  ),
  (
    'en çok sayıda insana en büyük mutluluğu sağlayan eylemin doğru olduğunu savunur.',
    2,
    1 << 1,
  ),
  ('Jeremy Bentham ve John Stuart Mill tarafından temsil edilir.', 2, 0),
  (
    'bir eylemin ahlaki değerini doğurduğu sonuçların topluma yararına göre belirler.',
    2,
    1 << 4,
  ),
  ('hazların nicelik bakımından hesaplanabileceğini öne sürer.', 2, 1),
  (
    'ahlaki eylemin sonucuna değil, ödev bilinciyle yapılıp yapılmadığına bakar.',
    3,
    0,
  ),
  ('Immanuel Kant tarafından temsil edilir.', 3, 0),
  (
    '“Öyle davran ki eyleminin ilkesi evrensel bir yasa olabilsin.” ilkesini benimser.',
    3,
    0,
  ),
  (
    'insanın hiçbir zaman yalnızca bir araç olarak değil, her zaman bir amaç olarak görülmesini ister.',
    3,
    0,
  ),
  ('koşulsuz olarak iyi olan tek şeyin iyi niyet olduğunu savunur.', 3, 0),
  (
    'insanın bütün eylemlerinin kendi çıkarını korumaya yönelik olduğunu savunur.',
    4,
    0,
  ),
  ('Thomas Hobbes tarafından temsil edilir.', 4, 0),
  (
    'ahlaki davranışın temelinde bireyin kendini koruma isteğinin bulunduğunu ileri sürer.',
    4,
    0,
  ),
  (
    'insanın kendi değerlerini kendisinin yarattığını ve seçimlerinden sorumlu olduğunu savunur.',
    5,
    1 << 6,
  ),
  ('Jean-Paul Sartre tarafından temsil edilir.', 5, 0),
  ('insanın özgür olmaya mahkûm olduğunu ileri sürer.', 5, 0),
  (
    'insanın önceden belirlenmiş bir özü olmadığını, kendini eylemleriyle oluşturduğunu savunur.',
    5,
    0,
  ),
  (
    'geleneksel ahlak değerlerinin geçersiz olduğunu ve yeniden değerlendirilmesi gerektiğini savunur.',
    6,
    0,
  ),
  ('Friedrich Nietzsche tarafından temsil edilir.', 6, 0),
  ('ahlakı efendi ahlakı ve köle ahlakı olarak ikiye ayırır.', 6, 0),
  (
    'evrensel ve mutlak bir ahlak yasasının bulunmadığını ileri sürer.',
    6,
    1 << 4 | 1 << 5 | 1 << 7,
  ),
  (
    'ahlaki değerlerin kişiden kişiye ve toplumdan topluma değiştiğini savunur.',
    7,
    0,
  ),
  ('Protagoras gibi sofistler tarafından temsil edilir.', 7, 0),
];

final _ahlakOlgu = _Ozneli(
  _ahlakGorus,
  _ahlakAkim,
  const [0, 1, 2],
  oge: 'görüş',
  sirali:
      'Bu görüşlerin ait olduğu ahlak felsefesi yaklaşımları sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
  hangileri: (s) => 'Ahlak felsefesine ait bu görüşlerden hangileri $s aittir?',
  onerme: 'Ahlak felsefesindeki yaklaşımlarla ilgili bu bilgilerden hangileri doğrudur?',
);

// ───────────────────── 17 · Siyaset felsefesi ve düşünürleri ────────────────

const _siyasetci = [
  ('Platon', "Platon'a"),
  ('Aristoteles', "Aristoteles'e"),
  ('Farabi', "Farabi'ye"),
  ('Thomas More', "Thomas More'a"),
  ('Campanella', "Campanella'ya"),
  ('Francis Bacon', "Francis Bacon'a"),
  ('Augustinus', "Augustinus'a"),
  ('Thomas Hobbes', "Thomas Hobbes'a"),
  ('John Locke', "John Locke'a"),
  ('Rousseau', "Rousseau'ya"),
  ('Montesquieu', "Montesquieu'ye"),
  ('Machiavelli', "Machiavelli'ye"),
  ('Karl Marx', "Karl Marx'a"),
  ('İbn Haldun', "İbn Haldun'a"),
];

// Toplum sözleşmesi ve halk egemenliği görüşleri Hobbes, Locke ve Rousseau
// arasında karşılıklı maskelidir.
const _siyasetGorus = <(String, int, int)>[
  (
    'Devlet adlı eserinde yöneticilerin filozoflar olduğu ideal bir devlet tasarlamıştır.',
    0,
    0,
  ),
  (
    'ideal devlette toplumu yöneticiler, bekçiler ve üreticiler olarak üç sınıfa ayırmıştır.',
    0,
    0,
  ),
  (
    'yönetici sınıfın özel mülkiyete ve aileye sahip olmaması gerektiğini savunmuştur.',
    0,
    1 << 3 | 1 << 4,
  ),
  ('insanın doğası gereği siyasal bir varlık olduğunu söylemiştir.', 1, 0),
  (
    'yönetim biçimlerini yönetenlerin sayısına ve kimin çıkarını gözettiklerine göre sınıflandırmıştır.',
    1,
    0,
  ),
  ('en iyi yönetimin orta sınıfa dayanan yönetim olduğunu savunmuştur.', 1, 0),
  ("El-Medinetü'l-Fazıla adlı eserinde erdemli bir şehir tasarlamıştır.", 2, 0),
  (
    'erdemli şehrin başkanının filozof ve peygamber niteliklerine sahip olması gerektiğini savunmuştur.',
    2,
    1,
  ),
  (
    'Ütopya adlı eserinde özel mülkiyetin bulunmadığı ideal bir ada toplumu tasarlamıştır.',
    3,
    0,
  ),
  ('Güneş Ülkesi adlı eserinde ideal bir devlet düzeni tasarlamıştır.', 4, 0),
  (
    'Yeni Atlantis adlı eserinde bilim insanlarının yönettiği bir toplum tasarlamıştır.',
    5,
    0,
  ),
  (
    "Tanrı Devleti adlı eserinde ideal düzeni Tanrı'ya yönelen insanların topluluğu olarak düşünmüştür.",
    6,
    0,
  ),
  ("siyasi iktidarın meşruiyetini Tanrı'nın iradesine dayandırmıştır.", 6, 0),
  ('Leviathan adlı eserinde güçlü ve mutlak bir devleti savunmuştur.', 7, 0),
  ('doğa durumunu herkesin herkese karşı savaşı olarak tanımlamıştır.', 7, 0),
  (
    'insanların güvenlik için bütün haklarını mutlak bir egemene devrettiğini savunmuştur.',
    7,
    1 << 8 | 1 << 9,
  ),
  (
    'devletin temel görevinin yaşam, özgürlük ve mülkiyet haklarını korumak olduğunu savunmuştur.',
    8,
    0,
  ),
  (
    'halkın, haklarını çiğneyen yönetime karşı direnme hakkı olduğunu savunmuştur.',
    8,
    0,
  ),
  ('yönetimin meşruiyetini yönetilenlerin rızasına dayandırmıştır.', 8, 1 << 9),
  (
    'Toplum Sözleşmesi adlı eserinde egemenliğin genel iradeye, yani halka ait olduğunu savunmuştur.',
    9,
    0,
  ),
  ('“İnsan özgür doğar, oysa her yerde zincire vurulmuştur.” demiştir.', 9, 0),
  (
    'doğa durumundaki insanın iyi olduğunu, toplumun onu bozduğunu savunmuştur.',
    9,
    0,
  ),
  (
    'Kanunların Ruhu adlı eserinde yasama, yürütme ve yargı güçlerinin ayrılması gerektiğini savunmuştur.',
    10,
    0,
  ),
  (
    'toplumların yasalarının iklim ve coğrafya gibi koşullara göre biçimlendiğini savunmuştur.',
    10,
    0,
  ),
  (
    'Hükümdar adlı eserinde devletin korunması için her yolun mubah olduğunu savunmuştur.',
    11,
    0,
  ),
  ('siyaseti ahlak ve dinden ayırmıştır.', 11, 0),
  ('sınıfsız bir toplumun kurulması gerektiğini savunmuştur.', 12, 0),
  ('devleti egemen sınıfın baskı aracı olarak görmüştür.', 12, 0),
  (
    'devletlerin kuruluşunu ve yıkılışını asabiyet kavramıyla açıklamıştır.',
    13,
    0,
  ),
];

final _siyasetOlgu = _Ozneli(
  _siyasetGorus,
  _siyasetci,
  const [0, 1, 2],
  oge: 'görüş',
  sirali:
      'Siyaset felsefesine ait bu görüşlerin sahibi olan düşünürler sırasıyla hangi '
      'seçenekte doğru verilmiştir?',
  hangileri: (s) =>
      'Siyaset felsefesine ait bu görüşlerden hangileri $s aittir?',
  onerme: 'Siyaset felsefesindeki görüşlerle ilgili bu bilgilerden hangileri doğrudur?',
);

// ──────────────────────── 18 · Felsefi kavramlar ────────────────────────────

const _kavramAd = [
  ('Arkhe', 'arkhe'),
  ('Apeiron', 'apeiron'),
  ('Logos', 'logos'),
  ('İdea', 'idea'),
  ('Töz', 'töz'),
  ('Erdem', 'erdem'),
  ('Determinizm', 'determinizm'),
  ('İndeterminizm', 'indeterminizm'),
  ('Fatalizm', 'fatalizm'),
  ('Özgürlük', 'özgürlük'),
  ('Sorumluluk', 'sorumluluk'),
  ('Vicdan', 'vicdan'),
  ('Önerme', 'önerme'),
  ('Kavram', 'kavram'),
  ('Terim', 'terim'),
  ('Tümevarım', 'tümevarım'),
  ('Tümdengelim', 'tümdengelim'),
  ('Analoji', 'analoji'),
  ('Paradoks', 'paradoks'),
  ('Hipotez', 'hipotez'),
  ('Metafizik', 'metafizik'),
  ('Diyalektik', 'diyalektik'),
  ('Dogma', 'dogma'),
  ('Sezgi', 'sezgi'),
  ('Kuram', 'kuram'),
  ('Değer', 'değer'),
  ('Doğruluk', 'doğruluk'),
  ('Özne', 'özne'),
  ('Nesne', 'nesne'),
  ('Akıl', 'akıl'),
  ('Yasa', 'yasa'),
  ('Felsefe', 'felsefe'),
];

// Her tanım bir kavrama aittir; anlamca yakın kavram çiftleri (arkhe–apeiron,
// arkhe–töz, determinizm–fatalizm, logos–diyalektik, metafizik–felsefe)
// karşılıklı maskelidir.
const _kavramTanim = <(String, int, int)>[
  (
    'varlığın kendisinden türediği ilk ana madde ve ilkedir.',
    0,
    1 << 1 | 1 << 4,
  ),
  (
    "Anaksimandros'a göre her şeyin kaynağı olan sınırsız ve belirsiz ana maddedir.",
    1,
    1,
  ),
  ('evrendeki değişimi yöneten akıl ve düzen ilkesidir.', 2, 1 << 21),
  (
    "Platon'a göre duyulur nesnelerin, duyular ötesi dünyadaki değişmez ve gerçek örneğidir.",
    3,
    0,
  ),
  (
    'var olmak için kendisinden başka hiçbir şeye gereksinim duymayan varlıktır.',
    4,
    1,
  ),
  ('ahlaki açıdan iyi olanı istikrarlı biçimde yapabilme yetkinliğidir.', 5, 0),
  (
    'her olayın kendinden önceki nedenlerle zorunlu olarak belirlendiğini savunan görüştür.',
    6,
    1 << 8,
  ),
  (
    'olayların zorunlu nedenlerle önceden belirlenmediğini, insan iradesinin özgür olduğunu savunan görüştür.',
    7,
    0,
  ),
  (
    'her şeyin önceden belirlenmiş bir yazgıya göre gerçekleştiğini, insanın bunu değiştiremeyeceğini savunan görüştür.',
    8,
    1 << 6,
  ),
  (
    'kişinin dış bir zorlama olmadan kendi iradesiyle seçim yapabilmesidir.',
    9,
    0,
  ),
  ('kişinin kendi eylemlerini ve bunların sonuçlarını üstlenmesidir.', 10, 0),
  (
    'kişinin kendi davranışlarının iyi ya da kötü olduğuna ilişkin iç yargısıdır.',
    11,
    0,
  ),
  ('doğru ya da yanlış olduğu söylenebilen, yargı bildiren cümledir.', 12, 0),
  ('nesnelerin ortak özelliklerini kapsayan zihinsel tasarımdır.', 13, 0),
  ('bir kavramın dildeki karşılığı olan sözcük ya da sözcük grubudur.', 14, 0),
  ('tek tek olgulardan genel bir sonuca ulaşılan akıl yürütmedir.', 15, 0),
  ('genel bir yargıdan özel bir sonuca ulaşılan akıl yürütmedir.', 16, 0),
  (
    'iki şey arasındaki benzerlikten yola çıkarak sonuca ulaşılan akıl yürütmedir.',
    17,
    0,
  ),
  (
    'birbiriyle çelişen ama her biri doğru görünen iki yargıyı içeren düşüncedir.',
    18,
    0,
  ),
  (
    'bir olguyu açıklamak için öne sürülen ve henüz doğrulanmamış varsayımdır.',
    19,
    0,
  ),
  ('duyular ötesi varlığı ve onun ilkelerini inceleyen alandır.', 20, 1 << 31),
  (
    'karşıtların çatışması yoluyla gerçekleşen gelişme ve değişme sürecidir.',
    21,
    1 << 2,
  ),
  ('doğruluğu sorgulanmadan kesin kabul edilen düşüncedir.', 22, 0),
  ('bir şeyi aracısız ve doğrudan kavrama yetisidir.', 23, 0),
  (
    'olgular ve yasalar arasındaki ilişkileri açıklayan sistemli bilgi bütünüdür.',
    24,
    0,
  ),
  ('bir şeyi istenir kılan, ona önem kazandıran niteliktir.', 25, 0),
  ('bilginin konusu olan nesneye uygun olmasıdır.', 26, 0),
  ('bilme eylemini gerçekleştiren varlıktır.', 27, 0),
  ('bilinen, hakkında bilgi edinilen varlıktır.', 28, 0),
  ('insanın düşünme, kavrama ve çıkarım yapma yetisidir.', 29, 0),
  (
    'olgular arasındaki değişmeyen ve tekrarlanan ilişkileri dile getiren önermedir.',
    30,
    0,
  ),
  (
    'varlık, bilgi ve değer üzerine eleştirel ve sistemli düşünme etkinliğidir.',
    31,
    1 << 20,
  ),
];

final _kavramOlgu = _Ozneli(
  _kavramTanim,
  _kavramAd,
  const [0, 2],
  oge: 'tanım',
  fiil: 'kavramını açıklar',
  sirali:
      'Bu tanımların karşılığı olan felsefi kavramlar sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
  hangileri: (s) => 'Bu tanımlardan hangileri $s kavramına aittir?',
  onerme: 'Felsefi kavramlarla ilgili bu tanımlardan hangileri doğrudur?',
);

// ───────────────── 19–20 · Klasik mantık: ortak terim araçları ──────────────

// Gerçek dünya bilgisinin karışmaması için terimler uydurmadır.
const _uydurmaKok = [
  'tolvir',
  'zemrak',
  'pirsel',
  'kandut',
  'folvem',
  'mirzak',
  'suvrat',
  'nebrin',
  'galdur',
  'vesrim',
  'korlap',
  'zindol',
  'pemtur',
  'lasvin',
  'dorkul',
  'mursep',
  'tilvan',
  'garnok',
  'senvil',
  'hurdel',
  'balvez',
  'nostir',
  'rubkan',
  'delvim',
];

String _sonUnlu(String s) {
  for (var k = s.length - 1; k >= 0; k--) {
    if ('aıoueiöü'.contains(s[k])) return s[k];
  }
  return 'e';
}

/// (tekil, çoğul, ek-fiilli tekil): tolvir → tolvirler, tolvirdir.
final _terim = [
  for (final k in _uydurmaKok)
    (
      k,
      '$k${'aıou'.contains(_sonUnlu(k)) ? 'lar' : 'ler'}',
      '$k${'çfhkpsşt'.contains(k[k.length - 1]) ? 't' : 'd'}'
          '${switch (_sonUnlu(k)) {
            'a' || 'ı' => 'ı',
            'e' || 'i' => 'i',
            'o' || 'u' => 'u',
            _ => 'ü',
          }}r',
    ),
];

typedef _Terim = (String, String, String);

/// Tür 0 tümel olumlu, 1 tümel olumsuz, 2 tikel olumlu, 3 tikel olumsuz.
String _onerme(int tur, _Terim s, _Terim p) => switch (tur) {
  0 => 'bütün ${s.$2} ${p.$3}',
  1 => 'hiçbir ${s.$1} ${p.$1} değildir',
  2 => 'bazı ${s.$2} ${p.$3}',
  _ => 'bazı ${s.$2} ${p.$1} değildir',
};

const _turAd = [
  'tümel olumlu',
  'tümel olumsuz',
  'tikel olumlu',
  'tikel olumsuz',
];

// ─────────────────────── 19 · Karşı olum ilişkileri ─────────────────────────

const _iliskiAd = ['çelişiklik', 'karşıtlık', 'alt karşıtlık', 'alt içerme'];
const _turCifti = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)];

/// İki farklı türdeki önerme arasındaki karşı olum ilişkisi.
int _iliski(int a, int b) {
  // a + b = 3: tümel olumlu–tikel olumsuz ya da tümel olumsuz–tikel olumlu
  // (çelişik); 1: iki tümel (karşıt); 5: iki tikel (alt karşıt); kalan
  // durumlar aynı nitelikte tümel ve tikel önermelerdir (alt içerme).
  return switch (a + b) {
    3 => 0,
    1 => 1,
    5 => 2,
    _ => 3,
  };
}

/// g türündeki önermenin değeri v iken t türündekinin durumu:
/// 0 kesinlikle doğru, 1 kesinlikle yanlış, 2 belirsiz.
int _durum(int g, bool v, int t) {
  if (t == g) return v ? 0 : 1;
  return switch (_iliski(g, t)) {
    0 => v ? 1 : 0,
    1 => v ? 1 : 2,
    2 => v ? 2 : 0,
    _ => g < 2 ? (v ? 0 : 2) : (v ? 2 : 1),
  };
}

/// Yargı dizilimleri: üç doğruluk yargısı (6 sıra) ya da iki doğruluk yargısı
/// ile bir ilişki yargısı (3 konum · 6 sıra · 6 tür çifti). Doğruluk konusu
/// 0–2, verilen önerme dışındaki türlerin sırasıdır; ilişki konusu 3–8'dir.
final _yargiDizilimi = [
  for (final p in ucluDizilimler) p,
  for (var yer = 0; yer < 3; yer++)
    for (var x = 0; x < 3; x++)
      for (var y = 0; y < 3; y++)
        if (x != y)
          for (var c = 3; c < 9; c++)
            [
              for (var k = 0, t = 0; k < 3; k++)
                if (k == yer) c else [x, y][t++],
            ],
];

/// Tipik yanlış çıkarımlar: “belirsiz” durumunu tanımamak (0) ve her ilişkiyi
/// çelişiklik gibi değerlendirmek (1).
int _yanlisDurum(int g, bool v, int t, int yol) {
  if (yol == 1) return v ? 1 : 0;
  return switch (_iliski(g, t)) {
    0 || 1 || 2 => v ? 1 : 0,
    _ => v ? 0 : 1,
  };
}

AdvancedItem _karsiOlumSoru(int i) {
  final g = i % 8 % 4, v = i % 8 < 4, j = i ~/ 8;
  final maske = 1 + j % 7;
  final konu = _dilim(_yargiDizilimi, j ~/ 7, 90);
  final si = i % 24;
  final s = _terim[si], p = _terim[(si + 1 + i ~/ 24 % 23) % 24];
  String q(int tur) => '“${_buyuk(_onerme(tur, s, p))}.”';
  final digerTur = [
    for (var t = 0; t < 4; t++)
      if (t != g) t,
  ];
  // Yanlış ilişki yargısında en sık karıştırılan ilişki kullanılır.
  const karisan = [1, 0, 3, 2];
  final yargi = <String>[], aciklama = <String>[];
  for (var k = 0; k < 3; k++) {
    final dogru = (maske >> k) & 1 == 1;
    final c = konu[k];
    if (c < 3) {
      final t = digerTur[c], d = _durum(g, v, t);
      // Yanlış yargı, tipik yanlış çıkarımın vereceği durumu söyler.
      final tuzak = [
        for (final x in [
          _yanlisDurum(g, v, t, 0),
          _yanlisDurum(g, v, t, 1),
          0,
          1,
          2,
        ])
          if (x != d) x,
      ];
      final soylenen = dogru ? d : tuzak.first;
      yargi.add(switch (soylenen) {
        0 => '${q(t)} önermesi kesinlikle doğrudur.',
        1 => '${q(t)} önermesi kesinlikle yanlıştır.',
        _ => '${q(t)} önermesinin doğruluk değeri belirsizdir.',
      });
      aciklama.add(
        '${_rakam[k]}. ${_buyuk(_turAd[t])} önerme verilen önermeyle ${_iliskiAd[_iliski(g, t)]} '
        'ilişkisindedir ve ${const ['doğrudur', 'yanlıştır', 'doğruluk değeri belirsizdir'][d]}; '
        'yargı ${dogru ? 'doğru' : 'yanlış'}.',
      );
    } else {
      final (a, b) = _turCifti[c - 3];
      final r = _iliski(a, b);
      final soylenen = dogru ? r : karisan[r];
      yargi.add(
        '${q(a)} ile ${q(b)} önermeleri arasında ${_iliskiAd[soylenen]} ilişkisi vardır.',
      );
      aciklama.add(
        '${_rakam[k]}. ${_buyuk(_turAd[a])} ile ${_turAd[b]} önermeler arasında '
        '${_iliskiAd[r]} ilişkisi vardır; yargı ${dogru ? 'doğru' : 'yanlış'}.',
      );
    }
  }
  return _oncullu(
    'Terimleri uydurma olan ${q(g)} önermesinin ${v ? 'doğru' : 'yanlış'} olduğu biliniyor.\n'
        '${_liste(yargi)}'
        'Klasik mantıktaki karşı olum ilişkilerine göre bu yargılardan hangileri doğrudur?',
    maske,
    j ~/ 3,
    '${aciklama.join(' ')} Doğru yargılar: ${_altkume(maske)}.',
  );
}

// ─────────────────────────── 20 · Kıyas (tasım) ─────────────────────────────

/// (şekil, büyük öncül türü, küçük öncül türü, sonuç türü). Şekil 1: O–B, K–O;
/// 2: B–O, K–O; 3: O–B, O–K; 4: B–O, O–K (O orta, B büyük, K küçük terim).
typedef _Kiyas = (int, int, int, int);

bool _dagitir(int tur, bool ozne) => ozne ? tur <= 1 : tur == 1 || tur == 3;

/// Klasik kıyas kurallarından ilk çiğneneni; kıyas geçerliyse null.
String? _kiyasKusur(_Kiyas k) {
  final (sekil, b, c, s) = k;
  bool olumsuz(int t) => t == 1 || t == 3;
  final ortaBOzne = sekil == 1 || sekil == 3, ortaKOzne = sekil >= 3;
  if (olumsuz(b) && olumsuz(c)) return 'iki öncül de olumsuzdur';
  if (!_dagitir(b, ortaBOzne) && !_dagitir(c, ortaKOzne)) {
    return 'orta terim öncüllerin hiçbirinde dağıtılmamıştır';
  }
  if (_dagitir(s, false) && !_dagitir(b, !ortaBOzne)) {
    return 'büyük terim öncülde dağıtılmadığı hâlde sonuçta dağıtılmıştır';
  }
  if (_dagitir(s, true) && !_dagitir(c, !ortaKOzne)) {
    return 'küçük terim öncülde dağıtılmadığı hâlde sonuçta dağıtılmıştır';
  }
  if ((olumsuz(b) || olumsuz(c)) && !olumsuz(s)) {
    return 'öncüllerden biri olumsuz olduğu hâlde sonuç olumludur';
  }
  if (!olumsuz(b) && !olumsuz(c) && olumsuz(s)) {
    return 'iki öncül de olumlu olduğu hâlde sonuç olumsuzdur';
  }
  return null;
}

final _tumKiyas = <_Kiyas>[
  for (var f = 1; f <= 4; f++)
    for (var b = 0; b < 4; b++)
      for (var c = 0; c < 4; c++)
        for (var s = 0; s < 4; s++) (f, b, c, s),
];
final _gecerliKiyas = [
  for (final k in _tumKiyas)
    if (_kiyasKusur(k) == null) k,
];

/// Tümel öncüllerden tikel sonuç çıkaran (yalnız klasik mantıkta geçerli) biçimler.
bool _kosullu(_Kiyas k) => k.$2 <= 1 && k.$3 <= 1 && k.$4 >= 2;

/// Çiğnenen kural öbekleri: 1 nitelik (olumlu–olumsuz), 2 dağıtılma kuralları.
int _kiyasIhlal(_Kiyas k) {
  final (sekil, b, c, s) = k;
  bool olumsuz(int t) => t == 1 || t == 3;
  final ortaBOzne = sekil == 1 || sekil == 3, ortaKOzne = sekil >= 3;
  var m = 0;
  if (olumsuz(b) && olumsuz(c) || (olumsuz(b) || olumsuz(c)) != olumsuz(s)) {
    m |= 1;
  }
  if (!_dagitir(b, ortaBOzne) && !_dagitir(c, ortaKOzne) ||
      _dagitir(s, false) && !_dagitir(b, !ortaBOzne) ||
      _dagitir(s, true) && !_dagitir(c, !ortaKOzne)) {
    m |= 2;
  }
  return m;
}

// Havuzlar: koşullu geçerli, koşulsuz geçerli, yalnız nitelik kuralını ve yalnız
// dağıtılma kurallarını çiğneyen biçimler. Her vakada bir koşullu geçerli
// biçim bulunur; geçersizler bu iki öbekten seçilir ki kuralların yalnız bir
// kısmını uygulayan çözüm anahtarı veremesin.
final _kiyasHavuz = [
  [
    for (final k in _gecerliKiyas)
      if (_kosullu(k)) k,
  ],
  [
    for (final k in _gecerliKiyas)
      if (!_kosullu(k)) k,
  ],
  [
    for (final k in _tumKiyas)
      if (_kiyasIhlal(k) == 1) k,
  ],
  [
    for (final k in _tumKiyas)
      if (_kiyasIhlal(k) == 2) k,
  ],
];

String _kiyasYaz(_Kiyas k, _Terim kucuk, _Terim orta, _Terim buyuk) {
  final (f, b, c, s) = k;
  final ob = f == 1 || f == 3
      ? _onerme(b, orta, buyuk)
      : _onerme(b, buyuk, orta);
  final ok = f >= 3 ? _onerme(c, orta, kucuk) : _onerme(c, kucuk, orta);
  return '${_buyuk(ob)}. ${_buyuk(ok)}. O hâlde ${_onerme(s, kucuk, buyuk)}.';
}

AdvancedItem _kiyasSoru(int i) {
  final maske = 1 + i % 7, u = i ~/ 7;
  // Her konumun havuzu: ilk geçerli konum koşullu, öteki geçerliler koşulsuz;
  // geçersiz konumlar sırayla (u'ya göre değişen) nitelik ve dağıtılma öbeği.
  final gecersizSira = u.isEven ? const [2, 3] : const [3, 2];
  final havuzNo = <int>[];
  var gecerliVar = false, gecersizSay = 0;
  for (var k = 0; k < 3; k++) {
    if ((maske >> k) & 1 == 1) {
      havuzNo.add(gecerliVar ? 1 : 0);
      gecerliVar = true;
    } else {
      havuzNo.add(gecersizSira[(gecersizSay++ + u ~/ 2) % 2]);
    }
  }
  // Yinelenmeyen seçim: u, olası seçimler arasında eşit aralıkla yayılır.
  final havuz = [
    for (final h in _kiyasHavuz) [...h],
  ];
  var toplam = 1;
  final kalan = [for (final h in havuz) h.length];
  for (final h in havuzNo) {
    toplam *= kalan[h]--;
  }
  var z = u * toplam ~/ 715;
  final secim = <_Kiyas>[];
  for (final h in havuzNo) {
    final liste = havuz[h];
    secim.add(liste.removeAt(z % liste.length));
    z ~/= liste.length + 1;
  }
  final si = i % 24, oi = (si + 1 + i ~/ 24 % 23) % 24;
  final bos = [
    for (var k = 0; k < 24; k++)
      if (k != si && k != oi) k,
  ];
  final ki = _terim[si],
      or = _terim[oi],
      bu = _terim[bos[(i ~/ 24 + i ~/ 552) % 22]];
  return _oncullu(
    'Terimleri uydurma olan şu kıyaslar veriliyor:\n'
        '${_liste([for (final k in secim) _kiyasYaz(k, ki, or, bu)])}'
        'Klasik mantığın kıyas kurallarına göre bu kıyaslardan hangileri geçerlidir?',
    maske,
    u ~/ 3,
    '${[for (var k = 0; k < 3; k++) '${_rakam[k]}. kıyas ${switch (_kiyasKusur(secim[k])) {
        null => 'geçerlidir',
        final e => 'geçersizdir; $e',
      }}.'].join(' ')} Geçerli olanlar: ${_altkume(maske)}.',
  );
}

// ─────────────────────────────── Aile listesi ───────────────────────────────

final lmTarihFelsefe = <AdvancedFamily>[
  lmSirali(
    'th_ilk_cag',
    'İlk Çağ uygarlıkları ve insanlığa katkıları',
    Topic.history,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _ilkCagOlgu.call,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'th_islam',
    'Hz. Muhammed ve Dört Halife dönemindeki gelişmeler',
    Topic.history,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _islamOlgu.call,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'th_emevi_abbasi',
    'Emeviler, Abbasiler ve Endülüs Emevileri',
    Topic.history,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _emeviOlgu.call,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'th_bilgin_eser',
    'Türk-İslam bilginleri ve eserleri',
    Topic.history,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _bilginSoru.call,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'th_osmanli_yonetim',
    'Osmanlı yönetimi: Divan, yönetici sınıflar ve dirlik',
    Topic.history,
    Difficulty.medium,
    BloomLevel.anlama,
    _osmanliSoru,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'th_avrupa',
    'Avrupa tarihi: Keşifler, Rönesans, Reform, ihtilaller',
    Topic.history,
    Difficulty.medium,
    BloomLevel.anlama,
    _avrupaOlgu.call,
    exam: ExamKind.ayt,
    lesson: 'Tarih-1',
  ),
  lmSirali(
    'th_islahat',
    'Osmanlı yenileşme hareketleri ve dönemleri',
    Topic.history,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _islahatOlgu.call,
    exam: ExamKind.ayt,
    lesson: 'Tarih-1',
  ),
  lmSirali(
    'th_birinci_dunya',
    'I. Dünya Savaşı: bloklar, cepheler ve olayların yılı',
    Topic.history,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _birinciDunyaSoru,
    exam: ExamKind.ayt,
    lesson: 'Tarih-1',
  ),
  lmSirali(
    'th_ikinci_dunya',
    'II. Dünya Savaşı: bloklar, olaylar ve kurulan örgütler',
    Topic.history,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _ikinciDunyaSoru,
    exam: ExamKind.ayt,
    lesson: 'Tarih-1',
  ),
  lmSirali(
    'th_soguk_savas',
    'Soğuk Savaş: ittifaklar, doktrinler, krizler ve Türkiye',
    Topic.history,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _sogukSavasSoru,
    exam: ExamKind.ayt,
    lesson: 'Tarih-1',
  ),
  lmSirali(
    'th_dis_politika',
    'Atatürk dönemi Türk dış politikası',
    Topic.history,
    Difficulty.medium,
    BloomLevel.anlama,
    _disOlgu.call,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'th_cok_partili',
    'Çok partili hayata geçiş denemeleri (1924–1950)',
    Topic.history,
    Difficulty.medium,
    BloomLevel.anlama,
    _siyasiOlgu.call,
    exam: ExamKind.tyt,
    lesson: 'Tarih',
  ),
  lmSirali(
    'fl_disiplin',
    'Felsefe disiplinleri ve temel soruları',
    Topic.socialScience,
    Difficulty.easy,
    BloomLevel.anlama,
    _disiplinOlgu.call,
    exam: ExamKind.tyt,
    lesson: 'Felsefe',
  ),
  lmSirali(
    'fl_filozof',
    'Filozoflar ve görüşleri',
    Topic.socialScience,
    Difficulty.medium,
    BloomLevel.hatirlama,
    _filozofOlgu.call,
    exam: ExamKind.tyt,
    lesson: 'Felsefe',
  ),
  lmSirali(
    'fl_bilgi_kaynagi',
    'Bilgi felsefesinde akımlar ve bilginin kaynağı',
    Topic.socialScience,
    Difficulty.medium,
    BloomLevel.anlama,
    _bilgiAkimOlgu.call,
    exam: ExamKind.tyt,
    lesson: 'Felsefe',
  ),
  lmSirali(
    'fl_ahlak',
    'Ahlak felsefesinde yaklaşımlar ve temsilcileri',
    Topic.socialScience,
    Difficulty.medium,
    BloomLevel.anlama,
    _ahlakOlgu.call,
    exam: ExamKind.tyt,
    lesson: 'Felsefe',
  ),
  lmSirali(
    'fl_siyaset',
    'Siyaset felsefesi: ideal devlet ve meşruiyet',
    Topic.socialScience,
    Difficulty.medium,
    BloomLevel.anlama,
    _siyasetOlgu.call,
    exam: ExamKind.tyt,
    lesson: 'Felsefe',
  ),
  lmSirali(
    'fl_kavram',
    'Felsefi kavramlar ve tanımları',
    Topic.socialScience,
    Difficulty.medium,
    BloomLevel.anlama,
    _kavramOlgu.call,
    exam: ExamKind.tyt,
    lesson: 'Felsefe',
  ),
  lmSirali(
    'fl_karsi_olum',
    'Önerme türleri ve karşı olum ilişkileri',
    Topic.socialScience,
    Difficulty.hard,
    BloomLevel.analiz,
    _karsiOlumSoru,
    exam: ExamKind.tyt,
    lesson: 'Felsefe',
  ),
  lmSirali(
    'fl_kiyas',
    'Kıyas: geçerli ve geçersiz kıyas',
    Topic.socialScience,
    Difficulty.hard,
    BloomLevel.analiz,
    _kiyasSoru,
    exam: ExamKind.tyt,
    lesson: 'Felsefe',
  ),
];
