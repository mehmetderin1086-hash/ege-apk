// Lise biyoloji (ikinci tur): hücre, biyomoleküller, sınıflandırma, madde
// döngüleri, soyağacı, insan fizyolojisi ve bitki biyolojisi kazanımlarından
// 20 metin ailesi; her aile 5.000 ayrı vaka üretir.
import 'ortak.dart';

final lmBiyolojiEk = <AdvancedFamily>[
  _organel,
  _maddeGecisi,
  _biyomolekul,
  _vitamin,
  _siniflandirma,
  _maddeDongusu,
  _soyagaci,
  _sindirim,
  _bosaltim,
  _sinir,
  _endokrin,
  _duyu,
  _kanYolu,
  _bagisiklik,
  _solunumYolu,
  _destekHareket,
  _embriyonik,
  _bitkiDokuAilesi,
  _bitkiHormonAilesi,
  _bitkiHareketAilesi,
];

// ───────────────────────────── Ortak yardımcılar ─────────────────────────────

const _romen = ['I', 'II', 'III', 'IV', 'V'];

/// Numaralı öncül listesi (satır sonu ile biter).
String _liste(List<String> x) =>
    '${[for (var k = 0; k < x.length; k++) '${_romen[k]}. ${x[k]}'].join('\n')}\n';

String _altkume(int maske) => switch (maske) {
  1 => 'Yalnız I',
  2 => 'Yalnız II',
  4 => 'Yalnız III',
  3 => 'I ve II',
  5 => 'I ve III',
  6 => 'II ve III',
  _ => 'I, II ve III',
};

/// Öncüllü soru: [deger] her öncülün istenen koşulu sağlayıp sağlamadığını
/// taşır. Çeldiricilerin ikisi yanıttan tek öncülle ayrılan, biri daha uzak
/// bir alt kümedir.
AdvancedItem _oncullu(String kok, List<bool> deger, int i, String aciklama) {
  var maske = 0;
  for (var k = 0; k < 3; k++) {
    if (deger[k]) maske |= 1 << k;
  }
  if (maske == 0) throw StateError('Boş yanıt: $kok');
  final yakin = [
    for (final b in const [1, 2, 4])
      if ((maske ^ b) != 0) maske ^ b,
  ];
  final uzak = [
    for (final m in const [1, 2, 4, 3, 5, 6, 7])
      if (m != maske && !yakin.contains(m)) m,
  ];
  final ky = i % yakin.length, ku = i ~/ 3 % uzak.length;
  final sira = [...yakin.sublist(ky), ...yakin.sublist(0, ky)];
  return secenekli(
    kok,
    _altkume(maske),
    [
      sira[0],
      sira[1],
      ...uzak.sublist(ku),
      ...uzak.sublist(0, ku),
      ...sira.sublist(2),
    ].map(_altkume),
    aciklama,
  );
}

/// Sıralı eşleştirme: [v] üç farklı değerdir; çeldiriciler değerlerin başka
/// dizilimleridir.
AdvancedItem _esle(String kok, List<String> v, int i, String aciklama) {
  final k = i % 5;
  return secenekli(kok, v.join(' – '), [
    for (var r = 0; r < 5; r++)
      [for (final j in ucluDizilimler[1 + (k + r) % 5]) v[j]].join(' – '),
  ], aciklama);
}

/// Türkçe büyük harfle başlatır (i → İ, ı → I).
String _bas(String s) {
  if (s.isEmpty) return s;
  final h = s[0];
  final b = h == 'i' ? 'İ' : (h == 'ı' ? 'I' : h.toUpperCase());
  return '$b${s.substring(1)}';
}

/// “a, b ve c” biçiminde birleştirir.
String _ve(List<String> x) => x.length <= 1
    ? x.join()
    : '${x.sublist(0, x.length - 1).join(', ')} ve ${x.last}';

/// (bilgi, değer) çizelgesinden [sira] (verilmezse [i]) numaralı üçlü seçki.
/// Değerler farklıysa (dört vakadan üçünde) sıralı eşleştirme, değilse
/// öncüllü soru üretir; dizilim ve biçim [i] ile değişir.
AdvancedItem _olgu(
  int i,
  List<(String, String)> tablo, {
  required String eslestirme,
  required String Function(String deger) oncul,
  required String Function(List<(String, String)> x) aciklama,
  int? sira,
}) {
  final u = kombinasyon(tablo, 3, sira ?? i);
  final d = ucluDizilimler[i % 6];
  final x = [for (final j in d) u[j]];
  final v = [for (final e in x) e.$2];
  final liste = _liste([for (final e in x) e.$1]);
  if (v.toSet().length == 3 && i % 4 != 3) {
    return _esle('$liste$eslestirme', v, i ~/ 6, aciklama(x));
  }
  final sorulan = v[i ~/ 6 % 3];
  return _oncullu(
    '$liste${oncul(sorulan)}',
    [for (final e in v) e == sorulan],
    i ~/ 2,
    aciklama(x),
  );
}

/// Öge üçlüleri ve soru numaraları (−1: eşleştirme). [deger] bir sorunun bir
/// öge için doğru, yanlış ya da belirsiz (null) olduğunu verir; belirsiz öge
/// taşıyan ya da boş yanıtlı üçlü o soruda kullanılmaz.
List<(int, int, int, int)> _adaylar(
  int n,
  int soruSayisi,
  bool? Function(int soru, int oge) deger, {
  String? Function(int oge)? sinif,
  bool Function(int a, int b, int c)? uygun,
}) {
  final out = <(int, int, int, int)>[];
  for (var a = 0; a < n; a++) {
    for (var b = a + 1; b < n; b++) {
      for (var c = b + 1; c < n; c++) {
        if (uygun != null && !uygun(a, b, c)) continue;
        if (sinif != null) {
          final s = {sinif(a), sinif(b), sinif(c)};
          if (!s.contains(null) && s.length == 3) out.add((a, b, c, -1));
        }
        for (var q = 0; q < soruSayisi; q++) {
          final x = deger(q, a), y = deger(q, b), z = deger(q, c);
          if (x == null || y == null || z == null) continue;
          if (x || y || z) out.add((a, b, c, q));
        }
      }
    }
  }
  return out;
}

/// [n] vakaya yayılmış seçki: [j] ∈ [0, n) için farklı ögeler verir.
T _yay<T>(List<T> liste, int j, int n) {
  if (liste.length < n) {
    throw StateError('Yetersiz aday: ${liste.length} < $n');
  }
  return liste[j * liste.length ~/ n];
}

/// 5.000 vakayı [k] biçime böler: [i] numaralı vaka [i] % [k] biçimindedir;
/// biçim içindeki sıra ve o biçimdeki vaka sayısı döner.
(int, int, int) _bicim(int i, int k) =>
    (i % k, i ~/ k, (lmAileBoyu - i % k + k - 1) ~/ k);

// ───────────────────────────── 1. Organeller ─────────────────────────────

// Her bilgi yalnız bir hücre yapısı için doğrudur.
const _organelGorev = <(String, String)>[
  (
    'Amino asitleri peptit bağlarıyla birleştirerek protein sentezler.',
    'ribozom',
  ),
  ('Prokaryot hücrelerde bulunan tek organel çeşididir.', 'ribozom'),
  (
    'rRNA ve proteinlerden oluşan büyük ve küçük iki alt birimden yapılmıştır.',
    'ribozom',
  ),
  (
    'Oksijenli solunumla hücrede en fazla ATP üretiminin yapıldığı organeldir.',
    'mitokondri',
  ),
  (
    'İç zarı krista adı verilen kıvrımlar oluşturan, çift zarlı solunum organelidir.',
    'mitokondri',
  ),
  (
    'Işık enerjisini kimyasal bağ enerjisine dönüştürerek fotosentez yapar.',
    'kloroplast',
  ),
  (
    'Klorofil taşıyan tilakoit zarları ile stromadan oluşan çift zarlı organeldir.',
    'kloroplast',
  ),
  (
    'Domates ve havuç gibi bitki kısımlarına kırmızı, turuncu ya da sarı renk veren '
        'pigmentleri taşır.',
    'kromoplast',
  ),
  (
    'Renksiz bir plastittir; patates yumrusu gibi kısımlarda nişasta depolar.',
    'lökoplast',
  ),
  (
    'Hidrolitik enzimler taşır ve hücre içi sindirimi gerçekleştirir.',
    'lizozom',
  ),
  (
    'Hücrenin yaşlanmış ya da işlevini yitirmiş organellerini parçalar.',
    'lizozom',
  ),
  (
    'Kurbağa larvasının kuyruğunun yok olmasında görev alan enzim keseciğidir.',
    'lizozom',
  ),
  (
    'Hücrede üretilen salgı maddelerini paketleyerek hücre dışına gönderilmeye hazırlar.',
    'Golgi cisimciği',
  ),
  (
    'Üst üste dizilmiş yassı keseciklerden oluşur; lizozomların oluşumunu sağlar.',
    'Golgi cisimciği',
  ),
  (
    'Üzerinde ribozom taşır; ribozomlarda üretilen proteinlerin hücre içinde taşınmasını '
        'sağlar.',
    'granüllü endoplazmik retikulum',
  ),
  (
    'Üzerinde ribozom bulunmaz; yağ ve steroit hormon sentezinde görev alır.',
    'granülsüz endoplazmik retikulum',
  ),
  (
    'Hayvan hücrelerinde bölünme sırasında iğ ipliklerinin oluşumunu sağlar.',
    'sentrozom',
  ),
  (
    'Birbirine dik konumlanmış iki sentriyolden oluşan zarsız organeldir.',
    'sentrozom',
  ),
  (
    'Zarsızdır; hayvan hücrelerinde bulunur, çiçekli bitki hücrelerinde bulunmaz.',
    'sentrozom',
  ),
  (
    'Hidrojen peroksiti katalaz enzimiyle su ve oksijene parçalayan keseciktir.',
    'peroksizom',
  ),
  (
    'Hücrenin yönetim merkezidir; metabolik olayları ve kalıtsal özellikleri denetler.',
    'çekirdek',
  ),
  (
    "Ökaryot hücrede DNA'nın büyük bölümünü çift katlı ve porlu bir zar içinde taşır.",
    'çekirdek',
  ),
  (
    'Çekirdek içinde bulunan ve ribozom alt birimlerinin üretildiği yoğun bölgedir.',
    'çekirdekçik',
  ),
  (
    'Seçici geçirgen yapısıyla hücreye madde giriş ve çıkışını denetler.',
    'hücre zarı',
  ),
  (
    'Hücreyi dış ortamdan ayıran, fosfolipit çift tabakası ve proteinlerden oluşan yapıdır.',
    'hücre zarı',
  ),
  (
    'Yüzeyindeki glikoprotein ve glikolipitlerle hücrelerin birbirini tanımasını sağlar.',
    'hücre zarı',
  ),
  (
    'Bitki hücresine şekil ve destek veren, selülozdan yapılmış, tam geçirgen yapıdır.',
    'hücre çeperi',
  ),
  (
    'Bitki hücresinin fazla su alarak patlamasını önleyen sağlam dış yapıdır.',
    'hücre çeperi',
  ),
  (
    'Bitki hücrelerinde su, mineral ve atık maddeleri depolayarak turgor basıncını sağlar.',
    'merkezî koful',
  ),
  (
    'Tatlı suda yaşayan tek hücrelilerde hücreye giren fazla suyu dışarı atar.',
    'kontraktil koful',
  ),
  (
    'Tek hücrelilerde besinlerin içine alındığı ve lizozomla birleşerek sindirildiği '
        'keseciktir.',
    'besin kofulu',
  ),
  (
    'Mikrotübül, ara filament ve mikrofilamentlerden oluşan, hücreye şekil veren ağ yapıdır.',
    'hücre iskeleti',
  ),
  (
    'Hücre zarı ile çekirdek arasını dolduran ve glikolizin gerçekleştiği sıvı ortamdır.',
    'sitoplazma',
  ),
];

// Yapı ve (yaprak hücresi, karaciğer hücresi, bakteri) bulunuşu. Bitki
// hücresinde lizozomun varlığı kaynaklarda farklı anlatıldığından belirsizdir.
const _organelVar = <(String, List<bool?>)>[
  ('hücre zarı', [true, true, true]),
  ('ribozom', [true, true, true]),
  ('sitoplazma', [true, true, true]),
  ('DNA', [true, true, true]),
  ('hücre çeperi', [true, false, true]),
  ('çekirdek zarı', [true, true, false]),
  ('mitokondri', [true, true, false]),
  ('endoplazmik retikulum', [true, true, false]),
  ('Golgi cisimciği', [true, true, false]),
  ('peroksizom', [true, true, false]),
  ('çekirdekçik', [true, true, false]),
  ('kloroplast', [true, false, false]),
  ('büyük merkezî koful', [true, false, false]),
  ('sentrozom', [false, true, false]),
  ('lizozom', [null, true, false]),
];

const _hucreYer = [
  'çiçekli bir bitkinin fotosentez yapan yaprak hücresinde',
  'insanın karaciğer hücresinde',
  'bir bakteri hücresinde',
];
const _hucreKisa = ['yaprak hücresinde', 'karaciğer hücresinde', 'bakteride'];

// (soru metni, bulunuş vektörü → doğru/yanlış/belirsiz)
final _organelSorulari = <(String, bool? Function(List<bool?>))>[
  for (var h = 0; h < 3; h++)
    ('Bu yapılardan hangileri ${_hucreYer[h]} bulunur?', (v) => v[h]),
  for (var h = 0; h < 3; h++)
    (
      'Bu yapılardan hangileri ${_hucreYer[h]} bulunmaz?',
      (v) => v[h] == null ? null : !v[h]!,
    ),
  for (var h = 0; h < 3; h++)
    for (var k = h + 1; k < 3; k++)
      (
        'Bu yapılardan hangileri hem ${_hucreYer[h]} hem de ${_hucreYer[k]} bulunur?',
        (v) => v[h] == null || v[k] == null ? null : v[h]! && v[k]!,
      ),
  for (var h = 0; h < 3; h++)
    for (var k = 0; k < 3; k++)
      if (h != k)
        (
          'Bu yapılardan hangileri ${_hucreYer[h]} bulunup ${_hucreYer[k]} bulunmaz?',
          (v) => v[h] == null || v[k] == null ? null : v[h]! && !v[k]!,
        ),
  (
    'Bu yapılardan hangileri ${_hucreYer[0]}, ${_hucreYer[1]} ve ${_hucreYer[2]} bulunur?',
    (v) => v.contains(null) ? null : v.every((e) => e!),
  ),
];

final _organelAdaylari = _adaylar(
  _organelVar.length,
  _organelSorulari.length,
  (q, o) => _organelSorulari[q].$2(_organelVar[o].$2),
);

String _bulunus((String, List<bool?>) e) {
  final (ad, v) = e;
  if (v.every((x) => x == true)) return '${_bas(ad)} üç hücrede de bulunur.';
  final var_ = [
    for (var h = 0; h < 3; h++)
      if (v[h] == true) _hucreKisa[h],
  ];
  final yok = [
    for (var h = 0; h < 3; h++)
      if (v[h] == false) _hucreKisa[h],
  ];
  return '${_bas(ad)} ${_ve(var_)} bulunur; ${_ve(yok)} bulunmaz.';
}

final _organel = lmSirali(
  'bl_organel',
  'Organellerin görevleri ve bulundukları hücreler',
  Topic.biology,
  Difficulty.easy,
  BloomLevel.hatirlama,
  (i) {
    final (f, j, n) = _bicim(i, 2);
    if (f == 0) {
      return _olgu(
        j,
        sira: j * 2,
        _organelGorev,
        eslestirme:
            'Bu görevleri üstlenen hücre yapıları sırasıyla hangi seçenekte '
            'doğru verilmiştir?',
        oncul: (y) => 'Bu bilgilerden hangileri “$y” için doğrudur?',
        aciklama: (x) =>
            'Birinci bilgi ${x[0].$2}, ikinci bilgi ${x[1].$2}, üçüncü '
            'bilgi ${x[2].$2} için doğrudur.',
      );
    }
    final (a, b, c, q) = _yay(_organelAdaylari, j, n);
    final d = ucluDizilimler[j % 6];
    final x = [
      for (final k in d) _organelVar[[a, b, c][k]],
    ];
    final (soru, f2) = _organelSorulari[q];
    return _oncullu(
      '${_liste([for (final e in x) e.$1])}$soru',
      [for (final e in x) f2(e.$2)!],
      j,
      x.map(_bulunus).join(' '),
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 2. Madde geçişi ─────────────────────────────

const _gecisAdi = [
  'basit difüzyon',
  'kolaylaştırılmış difüzyon',
  'aktif taşıma',
  'endositoz',
  'ekzositoz',
];

// (olay, geçiş biçimi)
const _gecisOlay = <(String, int)>[
  (
    'Alveollerdeki oksijenin, alveolleri saran kılcal damarlardaki kana geçmesi',
    0,
  ),
  (
    'Doku hücrelerinde oluşan karbondioksitin kılcal damarlardaki kana geçmesi',
    0,
  ),
  ('Kandaki oksijenin kılcal damarlardan doku hücrelerine geçmesi', 0),
  (
    'Etil alkol gibi küçük ve yağda çözünen moleküllerin derişim farkı yönünde zardan geçmesi',
    0,
  ),
  (
    'Steroit yapılı hormonların hedef hücrenin zarındaki fosfolipitler arasından geçmesi',
    0,
  ),
  (
    'Glikozun alyuvar zarındaki taşıyıcı proteinlerle derişim farkı yönünde hücreye girmesi',
    1,
  ),
  ('İyonların zardaki kanal proteinlerinden derişim farkı yönünde geçmesi', 1),
  (
    'Amino asitlerin zardaki taşıyıcı proteinlerle derişim farkı yönünde hücreye girmesi',
    1,
  ),
  (
    'Sinir hücresinde sodyum iyonlarının hücre dışına, potasyum iyonlarının hücre içine '
        'pompalanması',
    2,
  ),
  (
    'Kök tüyü hücrelerinin, topraktaki kendi içindekinden daha az derişimde bulunan '
        'mineralleri alması',
    2,
  ),
  (
    'Deniz yosunlarının iyot iyonlarını deniz suyundakinden çok daha yüksek derişimde biriktirmesi',
    2,
  ),
  (
    'Tiroit bezi hücrelerinin kandaki iyotu kendi içlerinde yüksek derişimde biriktirmesi',
    2,
  ),
  (
    'Böbrek kanalcığındaki glikozun derişim farkına karşı kana geri emilmesi',
    2,
  ),
  (
    'İnce bağırsakta glikozun bağırsak hücrelerine derişim farkına karşı alınması',
    2,
  ),
  (
    'Akyuvarın bir bakteriyi zarının oluşturduğu uzantılarla sararak içine alması',
    3,
  ),
  (
    'Amibin besin parçacığını yalancı ayaklarıyla sararak hücre içine alması',
    3,
  ),
  (
    'Hücrenin, zarında oluşan çukurcuklarla sıvı damlacıklarını içine alması',
    3,
  ),
  (
    'Hücre dışındaki büyük moleküllerin zarla sarılıp kesecik hâlinde hücreye alınması',
    3,
  ),
  (
    'Pankreas hücrelerinin sindirim enzimlerini, salgı keseciklerinin hücre zarıyla '
        'kaynaşmasıyla dışarı vermesi',
    4,
  ),
  (
    'Sinir hücresinin akson ucundan sinaptik boşluğa nörotransmitter salması',
    4,
  ),
  (
    'Akyuvarın, sindirdiği bakterinin artıklarını kesecik içinde hücre dışına atması',
    4,
  ),
  (
    'Tükürük bezi hücrelerinin mukus ve enzim içeren salgılarını hücre dışına vermesi',
    4,
  ),
  (
    'Bez hücrelerinin protein yapılı hormonları salgı kesecikleriyle hücre dışına vermesi',
    4,
  ),
];

// (soru, geçiş biçimlerine göre doğruluk, kural cümlesi)
const _gecisSorulari = <(String, List<bool?>, String)>[
  (
    'Bu olaylardan hangilerinde ATP harcanır?',
    [false, false, true, true, true],
    'Aktif taşıma, endositoz ve ekzositozda ATP harcanır; basit ve kolaylaştırılmış '
        'difüzyonda harcanmaz.',
  ),
  (
    'Bu olaylardan hangileri ATP harcanmadan gerçekleşir?',
    [true, true, false, false, false],
    'Basit ve kolaylaştırılmış difüzyon derişim farkı yönünde kendiliğinden gerçekleşir, ATP '
        'harcanmaz; aktif taşıma, endositoz ve ekzositozda ATP harcanır.',
  ),
  (
    'Bu olaylardan hangilerinde zardaki taşıyıcı ya da kanal proteinleri kullanılır?',
    [false, true, true, null, null],
    'Kolaylaştırılmış difüzyonda ve aktif taşımada zar proteinleri kullanılır; basit '
        'difüzyonda madde doğrudan fosfolipitler arasından geçer.',
  ),
  (
    'Bu olaylardan hangilerinde madde, derişimin düşük olduğu taraftan yüksek olduğu tarafa '
        'taşınır?',
    [false, false, true, null, null],
    'Maddeyi derişimin düşük olduğu taraftan yüksek olduğu tarafa yalnız aktif taşıma '
        'götürür; difüzyonda madde çok olduğu yerden az olduğu yere geçer.',
  ),
  (
    'Bu olaylardan hangilerinde hücre zarının yüzey alanı azalır?',
    [false, false, false, true, false],
    'Endositozda zarın bir bölümü kesecik olarak hücre içine geçtiğinden zarın yüzey alanı '
        'azalır; ekzositozda artar, difüzyon ve aktif taşımada değişmez.',
  ),
  (
    'Bu olaylardan hangilerinde hücre zarının yüzey alanı artar?',
    [false, false, false, false, true],
    'Ekzositozda kesecik zarı hücre zarına katıldığından zarın yüzey alanı artar; '
        'endositozda azalır, difüzyon ve aktif taşımada değişmez.',
  ),
  (
    'Bu olaylardan hangilerinde madde, zarın oluşturduğu keseciklerle taşınır?',
    [false, false, false, true, true],
    'Endositoz ve ekzositozda maddeler zarın oluşturduğu keseciklerle taşınır; difüzyon ve '
        'aktif taşımada kesecik oluşmaz.',
  ),
];

final _gecisAdaylari = _adaylar(
  _gecisOlay.length,
  _gecisSorulari.length,
  (q, o) => _gecisSorulari[q].$2[_gecisOlay[o].$2],
  sinif: (o) => _gecisAdi[_gecisOlay[o].$2],
);

final _maddeGecisi = lmSirali(
  'bl_madde_gecisi',
  'Hücre zarından madde geçişi: ATP ve taşıyıcı kullanımı',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final (a, b, c, q) = _yay(_gecisAdaylari, i, lmAileBoyu);
    final d = ucluDizilimler[i % 6];
    final x = [
      for (final k in d) _gecisOlay[[a, b, c][k]],
    ];
    final liste = _liste([for (final e in x) e.$1]);
    final turler =
        'I. olay ${_gecisAdi[x[0].$2]}, II. olay ${_gecisAdi[x[1].$2]}, III. '
        'olay ${_gecisAdi[x[2].$2]} örneğidir.';
    if (q < 0) {
      return _esle(
        '${liste}Bu olaylarda görülen madde geçiş biçimleri sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
        [for (final e in x) _gecisAdi[e.$2]],
        i ~/ 6,
        turler,
      );
    }
    final (soru, tablo, kural) = _gecisSorulari[q];
    return _oncullu(
      '$liste$soru',
      [for (final e in x) tablo[e.$2]!],
      i,
      '$turler $kural',
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 3. Organik moleküller ─────────────────────────────

const _bagAdi = [
  'glikozit bağı',
  'peptit bağı',
  'ester bağı',
  'fosfodiester bağı',
];

// (ad, yapı birimi, yapı birimleri arasındaki bağ, azot içerir mi (null:
//  belirsiz), grup, açıklama cümlesi)
const _molekuller = <(String, String, int, bool?, String, String)>[
  (
    'nişasta',
    'glikoz',
    0,
    false,
    'depo',
    'Nişasta, bitkilerin depo polisakkaritidir; glikozların glikozit bağlarıyla '
        'bağlanmasından oluşur.',
  ),
  (
    'glikojen',
    'glikoz',
    0,
    false,
    'depo',
    'Glikojen, hayvanların ve mantarların depo polisakkaritidir; glikozlardan glikozit '
        'bağlarıyla oluşur.',
  ),
  (
    'selüloz',
    'glikoz',
    0,
    false,
    'yapı',
    'Selüloz, bitki hücre çeperinin yapısına katılan polisakkarittir; glikozlardan glikozit '
        'bağlarıyla oluşur.',
  ),
  (
    'kitin',
    'azotlu glikoz türevi',
    0,
    true,
    'yapı',
    'Kitin, eklem bacaklıların dış iskeletine ve mantar çeperine katılır; azot içeren glikoz '
        'türevlerinden glikozit bağlarıyla oluşur.',
  ),
  (
    'maltoz',
    'glikoz',
    0,
    false,
    'disakkarit',
    'Maltoz, iki glikozun glikozit bağıyla bağlanmasından oluşan disakkarittir.',
  ),
  (
    'sakkaroz',
    'glikoz ve fruktoz',
    0,
    false,
    'disakkarit',
    'Sakkaroz, glikoz ve fruktozun glikozit bağıyla bağlanmasından oluşan disakkarittir.',
  ),
  (
    'laktoz',
    'glikoz ve galaktoz',
    0,
    false,
    'disakkarit',
    'Laktoz, glikoz ve galaktozun glikozit bağıyla bağlanmasından oluşan disakkarittir.',
  ),
  (
    'keratin',
    'amino asit',
    1,
    true,
    'protein',
    'Keratin, saç ve tırnağın yapısındaki proteindir; amino asitlerden peptit bağlarıyla '
        'oluşur.',
  ),
  (
    'hemoglobin',
    'amino asit',
    1,
    true,
    'protein',
    'Hemoglobin, oksijen taşıyan proteindir; amino asitlerden peptit bağlarıyla oluşur.',
  ),
  (
    'kolajen',
    'amino asit',
    1,
    true,
    'protein',
    'Kolajen, bağ dokunun yapısındaki proteindir; amino asitlerden peptit bağlarıyla oluşur.',
  ),
  (
    'insülin',
    'amino asit',
    1,
    true,
    'protein',
    'İnsülin, protein yapılı bir hormondur; amino asitlerden peptit bağlarıyla oluşur.',
  ),
  (
    'amilaz enzimi',
    'amino asit',
    1,
    true,
    'protein',
    'Amilaz, protein yapılı bir enzimdir; amino asitlerden peptit bağlarıyla oluşur.',
  ),
  (
    'antikor',
    'amino asit',
    1,
    true,
    'protein',
    'Antikor, bağışıklıkta görev alan proteindir; amino asitlerden peptit bağlarıyla oluşur.',
  ),
  (
    'aktin',
    'amino asit',
    1,
    true,
    'protein',
    'Aktin, kas kasılmasında görev alan proteindir; amino asitlerden peptit bağlarıyla '
        'oluşur.',
  ),
  (
    'DNA',
    'nükleotit',
    3,
    true,
    'nükleik asit',
    'DNA, kalıtım bilgisini taşıyan nükleik asittir; nükleotitlerden fosfodiester bağlarıyla '
        'oluşur.',
  ),
  (
    'mRNA',
    'nükleotit',
    3,
    true,
    'nükleik asit',
    'mRNA, şifreyi ribozoma taşıyan nükleik asittir; nükleotitlerden fosfodiester bağlarıyla '
        'oluşur.',
  ),
  (
    'tRNA',
    'nükleotit',
    3,
    true,
    'nükleik asit',
    'tRNA, amino asitleri ribozoma taşıyan nükleik asittir; nükleotitlerden fosfodiester '
        'bağlarıyla oluşur.',
  ),
  (
    'rRNA',
    'nükleotit',
    3,
    true,
    'nükleik asit',
    'rRNA, ribozomun yapısına katılan nükleik asittir; nükleotitlerden fosfodiester '
        'bağlarıyla oluşur.',
  ),
  (
    'nötr yağ (trigliserit)',
    'gliserol ve yağ asidi',
    2,
    false,
    'lipit',
    'Nötr yağ, bir gliserol ile üç yağ asidinin ester bağlarıyla bağlanmasından oluşur.',
  ),
  (
    'fosfolipit',
    'gliserol, yağ asidi ve fosfat',
    2,
    null,
    'lipit',
    'Fosfolipit, gliserole iki yağ asidi ve fosfat grubunun ester bağlarıyla bağlanmasından '
        'oluşur.',
  ),
];

// (soru, molekül → doğru/yanlış/belirsiz)
final _molekulSorulari = <(String, bool? Function(int))>[
  (
    'Bu moleküllerden hangileri hidroliz edildiğinde yalnız glikoz molekülleri oluşur?',
    (m) => _molekuller[m].$2 == 'glikoz',
  ),
  (
    'Bu moleküllerden hangilerinin yapısında azot bulunur?',
    (m) => _molekuller[m].$4,
  ),
  (
    'Bu moleküllerden hangilerinde yapı birimleri birbirine peptit bağıyla bağlanmıştır?',
    (m) => _molekuller[m].$3 == 1,
  ),
  (
    'Bu moleküllerden hangilerinde yapı birimleri birbirine glikozit bağıyla bağlanmıştır?',
    (m) => _molekuller[m].$3 == 0,
  ),
  (
    'Bu moleküllerden hangilerinde yapı birimleri birbirine ester bağıyla bağlanmıştır?',
    (m) => _molekuller[m].$3 == 3 ? null : _molekuller[m].$3 == 2,
  ),
  (
    'Bu moleküllerden hangileri nükleotitlerden oluşur?',
    (m) => _molekuller[m].$2 == 'nükleotit',
  ),
  (
    'Bu moleküllerden hangileri depo polisakkaritidir?',
    (m) => _molekuller[m].$5 == 'depo',
  ),
  (
    'Bu moleküllerden hangileri hücre ya da vücut yapısına katılan bir polisakkarittir?',
    (m) => _molekuller[m].$5 == 'yapı',
  ),
  (
    'Bu moleküllerden hangileri disakkarittir?',
    (m) => _molekuller[m].$5 == 'disakkarit',
  ),
];

// Eşleştirme: −1 yapı birimi, −2 bağ türü (yalnız değerler farklıysa).
final _molekulAdaylari = [
  ..._adaylar(
    _molekuller.length,
    _molekulSorulari.length,
    (q, m) => _molekulSorulari[q].$2(m),
    sinif: (m) => _molekuller[m].$2,
  ),
  for (final (a, b, c, _) in _adaylar(
    _molekuller.length,
    0,
    (q, m) => null,
    // Fosfolipitte fosfat ile baş grubu arasında fosfodiester bağı da
    // bulunduğundan bağ eşleştirmesine alınmaz.
    sinif: (m) =>
        _molekuller[m].$1 == 'fosfolipit' ? null : _bagAdi[_molekuller[m].$3],
  ))
    (a, b, c, -2),
];

final _biyomolekul = lmSirali(
  'bl_biyomolekul',
  'Organik moleküllerin yapı birimleri ve bağları',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) {
    final (a, b, c, q) = _yay(_molekulAdaylari, i, lmAileBoyu);
    final d = ucluDizilimler[i % 6];
    final x = [
      for (final k in d) _molekuller[[a, b, c][k]],
    ];
    final liste = _liste([for (final e in x) e.$1]);
    final aciklama = [for (final e in x) e.$6].join(' ');
    if (q == -1) {
      return _esle(
        '${liste}Bu moleküllerin yapı birimleri (monomerleri) sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
        [for (final e in x) e.$2],
        i ~/ 6,
        aciklama,
      );
    }
    if (q == -2) {
      return _esle(
        '${liste}Bu moleküllerde yapı birimlerini birbirine bağlayan bağlar sırasıyla hangi '
        'seçenekte doğru verilmiştir?',
        [for (final e in x) _bagAdi[e.$3]],
        i ~/ 6,
        aciklama,
      );
    }
    final (soru, f) = _molekulSorulari[q];
    final azot = q == 1
        ? ' ${_bas(_ve([for (final e in x) '${e.$1} ${e.$4! ? 'azot içerir' : 'azot içermez'}']))}.'
        : '';
    return _oncullu(
      '$liste$soru',
      [
        for (final k in d) f([a, b, c][k])!,
      ],
      i,
      '$aciklama$azot',
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 4. Vitaminler ve mineraller ─────────────────────────────

// (ad, yağda çözünür mü, eksikliğinde görülen hastalık)
const _vitaminTablo = <(String, bool, String?)>[
  ('A vitamini', true, 'gece körlüğü'),
  ('D vitamini', true, 'raşitizm'),
  ('E vitamini', true, null),
  ('K vitamini', true, 'kanın geç pıhtılaşması'),
  ('B₁ vitamini', false, 'beriberi'),
  ('B₂ vitamini', false, null),
  ('B₃ vitamini (niasin)', false, 'pellagra'),
  ('B₅ vitamini (pantotenik asit)', false, null),
  ('B₆ vitamini', false, null),
  ('B₇ vitamini (biyotin)', false, null),
  ('B₁₂ vitamini', false, 'kansızlık'),
  ('folik asit (B₉ vitamini)', false, null),
  ('C vitamini', false, 'skorbüt'),
];

const _mineralTablo = <(String, String)>[
  ('demir', 'kansızlık'),
  ('iyot', 'guatr'),
  ('flor', 'diş çürükleri'),
];

// Yanlış eşleştirme cümlelerinde kullanılan, belirgin vitamin hastalıkları.
const _vitaminHastalik = [
  'gece körlüğü',
  'raşitizm',
  'kanın geç pıhtılaşması',
  'beriberi',
  'pellagra',
  'skorbüt',
];

// (konu, ifade, doğru mu)
final _vitaminIfade = <(String, String, bool)>[
  for (final (ad, yag, _) in _vitaminTablo) ...[
    (ad, '${_bas(ad)} yağda çözünür.', yag),
    (ad, '${_bas(ad)} suda çözünür.', !yag),
  ],
  for (final (ad, _, h) in _vitaminTablo)
    if (h != null) ...[
      (ad, '${_bas(ad)} eksikliğinde $h görülür.', true),
      for (final y in _vitaminHastalik)
        if (y != h && !(ad == 'C vitamini' && y == 'kanın geç pıhtılaşması'))
          (ad, '${_bas(ad)} eksikliğinde $y görülür.', false),
    ],
  for (final (ad, h) in _mineralTablo) ...[
    (ad, '${_bas(ad)} eksikliğinde $h görülür.', true),
    for (final y in _vitaminHastalik)
      (ad, '${_bas(ad)} eksikliğinde $y görülür.', false),
  ],
  ('demir', 'Demir, hemoglobinin yapısına katılır.', true),
  ('iyot', 'İyot, tiroksin hormonunun yapısına katılır.', true),
  ('magnezyum', 'Magnezyum, klorofilin yapısına katılır.', true),
  ('demir', 'Demir, klorofilin yapısına katılır.', false),
  ('magnezyum', 'Magnezyum, hemoglobinin yapısına katılır.', false),
  ('iyot', 'İyot, hemoglobinin yapısına katılır.', false),
  (
    'D vitamini',
    'D vitamini, güneş ışığının etkisiyle deride sentezlenebilir.',
    true,
  ),
  (
    'C vitamini',
    'C vitamini, güneş ışığının etkisiyle deride sentezlenebilir.',
    false,
  ),
  (
    'K vitamini',
    'K vitamini, kalın bağırsakta yaşayan bakteriler tarafından üretilebilir.',
    true,
  ),
  (
    'A vitamini',
    'A vitamini, havuç gibi besinlerdeki karotenden vücutta oluşturulabilir.',
    true,
  ),
  ('kalsiyum', 'Kalsiyum, kemik ve dişlerin yapısına katılır.', true),
  ('kalsiyum', 'Kalsiyum, kanın pıhtılaşmasında görev alır.', true),
  ('genel', 'Vitaminler vücutta enerji kaynağı olarak kullanılır.', false),
  ('genel', 'Vitaminler ve mineraller sindirime uğramadan emilir.', true),
  ('genel', 'Yağda çözünen vitaminlerin fazlası vücutta depolanabilir.', true),
  ('genel', 'Suda çözünen vitaminlerin fazlası idrarla atılabilir.', true),
  ('genel', 'Mineraller vücutta yıkılarak enerji verir.', false),
];

// Konuları farklı, en az biri doğru olan ifade üçlüleri.
final _vitaminUcluleri = [
  for (final (a, b, c, _) in _adaylar(
    _vitaminIfade.length,
    1,
    (q, k) => _vitaminIfade[k].$3,
    uygun: (a, b, c) =>
        {
          _vitaminIfade[a].$1,
          _vitaminIfade[b].$1,
          _vitaminIfade[c].$1,
        }.length ==
        3,
  ))
    (a, b, c),
];

// Eşleştirme ve çözünürlük soruları: (öge üçlüsü, soru) ögeleri ayrı listelerden.
final _eksiklikOgeleri = <(String, String)>[
  for (final (ad, _, h) in _vitaminTablo)
    if (h != null) (ad, h),
  ..._mineralTablo,
];

final _vitaminKucuk = <(int, int, int, int)>[
  // −1: eksiklik eşleştirmesi (hastalıklar farklıysa)
  for (final (a, b, c, _) in _adaylar(
    _eksiklikOgeleri.length,
    0,
    (q, k) => null,
    sinif: (k) => _eksiklikOgeleri[k].$2,
  ))
    (a, b, c, -1),
  // 0: yağda çözünür, 1: suda çözünür
  ..._adaylar(
    _vitaminTablo.length,
    2,
    (q, k) => q == 0 ? _vitaminTablo[k].$2 : !_vitaminTablo[k].$2,
  ),
];

final _vitamin = lmSirali(
  'bl_vitamin',
  'Vitaminler ve mineraller: çözünürlük ve eksiklik',
  Topic.biology,
  Difficulty.easy,
  BloomLevel.hatirlama,
  (i) {
    final (f, j, n) = _bicim(i, 9);
    if (f == 0) {
      final (a, b, c, q) = _yay(_vitaminKucuk, j, n);
      final d = ucluDizilimler[j % 6];
      if (q < 0) {
        final x = [
          for (final k in d) _eksiklikOgeleri[[a, b, c][k]],
        ];
        return _esle(
          '${_liste([for (final e in x) e.$1])}Bu maddelerin eksikliğinde görülen rahatsızlıklar '
              'sırasıyla hangi seçenekte doğru verilmiştir?',
          [for (final e in x) e.$2],
          j,
          '${_ve([for (final e in x) '${_bas(e.$1)} eksikliğinde ${e.$2}'])} görülür.',
        );
      }
      final x = [
        for (final k in d) _vitaminTablo[[a, b, c][k]],
      ];
      final yagda = [
        for (final e in x)
          if (e.$2) e.$1,
      ];
      final suda = [
        for (final e in x)
          if (!e.$2) e.$1,
      ];
      final aciklama = [
        if (yagda.isNotEmpty) '${_bas(_ve(yagda))} yağda çözünür.',
        if (suda.isNotEmpty) '${_bas(_ve(suda))} suda çözünür.',
      ].join(' ');
      return _oncullu(
        '${_liste([for (final e in x) e.$1])}Bu vitaminlerden hangileri '
            '${q == 0 ? 'yağda' : 'suda'} çözünür?',
        [for (final e in x) q == 0 ? e.$2 : !e.$2],
        j,
        'A, D, E ve K vitaminleri yağda; B grubu vitaminleri ve C vitamini suda çözünür. '
            '$aciklama',
      );
    }
    // Küçük biçim dışındaki vakalar tek bir sıra oluşturur.
    final k9 = i - i ~/ 9 - 1;
    final (a, b, c) = _yay(
      _vitaminUcluleri,
      k9,
      lmAileBoyu - (lmAileBoyu + 8) ~/ 9,
    );
    final d = ucluDizilimler[k9 % 6];
    final x = [
      for (final k in d) _vitaminIfade[[a, b, c][k]],
    ];
    final dogru = [
      for (var k = 0; k < 3; k++)
        if (x[k].$3) _romen[k],
    ];
    final yanlis = [
      for (var k = 0; k < 3; k++)
        if (!x[k].$3) _romen[k],
    ];
    return _oncullu(
      '${_liste([for (final e in x) e.$2])}Vitaminler ve minerallerle ilgili bu ifadelerden '
      'hangileri doğrudur?',
      [for (final e in x) e.$3],
      j,
      [
        '${_ve(dogru)} doğrudur${yanlis.isEmpty ? '' : '; ${_ve(yanlis)} yanlıştır'}.',
        _vitaminDuzeltme(x),
      ].where((e) => e.isNotEmpty).join(' '),
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

/// Her ifadenin dayandığı bilgiyi yazar; yanlış ifadelerin doğrusunu verir.
String _vitaminDuzeltme(List<(String, String, bool)> x) {
  final out = <String>[];
  void ekle(String s) {
    if (!out.contains(s)) out.add(s);
  }

  for (final (konu, ifade, dogru) in x) {
    final v = _vitaminTablo.where((e) => e.$1 == konu).firstOrNull;
    final m = _mineralTablo.where((e) => e.$1 == konu).firstOrNull;
    if (ifade.contains('çözünür')) {
      ekle('${_bas(konu)} ${v!.$2 ? 'yağda' : 'suda'} çözünür.');
    } else if (ifade.contains('eksikliğinde')) {
      ekle('${_bas(konu)} eksikliğinde ${v?.$3 ?? m!.$2} görülür.');
    } else if (dogru) {
      continue;
    } else if (ifade.contains('klorofil')) {
      ekle('Klorofilin yapısına magnezyum katılır.');
    } else if (ifade.contains('hemoglobin')) {
      ekle('Hemoglobinin yapısına demir katılır.');
    } else if (ifade.contains('deride')) {
      ekle('Deride güneş ışığının etkisiyle D vitamini sentezlenir.');
    } else if (ifade.startsWith('Vitaminler')) {
      ekle('Vitaminler enerji vermez, düzenleyici olarak görev yapar.');
    } else {
      ekle(
        'Mineraller enerji vermez, yapıya katılır ve düzenleyici görev yapar.',
      );
    }
  }
  return out.join(' ');
}

// ───────────────────────────── 5. Sınıflandırma ─────────────────────────────

const _alemAdi = [
  'Bakteriler',
  'Arkeler',
  'Protistler',
  'Mantarlar',
  'Bitkiler',
  'Hayvanlar',
];

// (canlı, âlem, fotosentez yapabilir mi, çok hücreli mi, heterotrof mu);
// null: kaynaklarda kesin olmayan ya da türler arasında değişen özellik.
const _canlilar = <(String, int, bool?, bool?, bool?)>[
  ('yoğurt yapımında kullanılan laktik asit bakterisi', 0, false, false, true),
  ('insan kalın bağırsağında yaşayan E. coli bakterisi', 0, false, false, true),
  ('fotosentez yapan siyanobakteri', 0, true, null, false),
  ('baklagil köklerinde yaşayan azot bağlayıcı bakteri', 0, false, false, true),
  ('verem hastalığının etkeni olan bakteri', 0, false, false, true),
  ('aşırı tuzlu göllerde yaşayan tuzcul arke', 1, null, false, null),
  ('kaplıca sularında yaşayan termofil arke', 1, false, false, null),
  ('bataklıklarda metan gazı üreten arke', 1, false, false, null),
  ('amip', 2, false, false, true),
  ('öglena', 2, true, false, null),
  ('paramesyum (terliksi hayvan)', 2, false, false, true),
  ('sıtma etkeni plazmodyum', 2, false, false, true),
  ('uyku hastalığı etkeni tripanozom', 2, false, false, true),
  ('cıvık mantar', 2, false, null, true),
  ('kahverengi alg', 2, true, true, false),
  ('ekmek mayası', 3, false, false, true),
  ('şapkalı mantar', 3, false, true, true),
  ('ekmek küfü', 3, false, null, true),
  ('penisilin elde edilen küf mantarı', 3, false, null, true),
  ('kara yosunu', 4, true, true, false),
  ('eğrelti otu', 4, true, true, false),
  ('at kuyruğu', 4, true, true, false),
  ('çam ağacı', 4, true, true, false),
  ('buğday', 4, true, true, false),
  ('papatya', 4, true, true, false),
  ('sünger', 5, false, true, true),
  ('deniz anası', 5, false, true, true),
  ('toprak solucanı', 5, false, true, true),
  ('salyangoz', 5, false, true, true),
  ('bal arısı', 5, false, true, true),
  ('deniz yıldızı', 5, false, true, true),
  ('kurbağa', 5, false, true, true),
  ('yarasa', 5, false, true, true),
  ('penguen', 5, false, true, true),
];

final _canliAlem = [for (final c in _canlilar) (c.$1, _alemAdi[c.$2])];

// Her özellik yalnız bir âlem için doğrudur.
const _alemOzellik = <(String, String)>[
  (
    'Hücre çeperlerinde peptidoglikan bulunan prokaryot canlılardır.',
    'Bakteriler',
  ),
  (
    'Fotosentez yapan siyanobakterileri de içeren, çekirdek zarı bulunmayan tek hücreli '
        'canlılardır.',
    'Bakteriler',
  ),
  (
    'Çeperlerinde peptidoglikan bulunmayan, aşırı tuzlu ya da çok sıcak ortamlarda da '
        'yaşayabilen prokaryotlardır.',
    'Arkeler',
  ),
  (
    'Bitki, hayvan ve mantar âlemlerine girmeyen, çoğu tek hücreli ökaryot canlılardır.',
    'Protistler',
  ),
  (
    'Öglena, amip ve paramesyumun yer aldığı ökaryot canlı grubudur.',
    'Protistler',
  ),
  (
    'Hücre çeperleri kitinden yapılmış, fotosentez yapmayan ökaryotlardır.',
    'Mantarlar',
  ),
  (
    'Salgıladıkları enzimlerle besinleri hücre dışında sindirip emerek beslenen, glikojen '
        'depolayan çeperli ökaryotlardır.',
    'Mantarlar',
  ),
  (
    'Çok hücreli, fotosentez yapan, hücre çeperi selülozdan oluşan ökaryotlardır.',
    'Bitkiler',
  ),
  (
    'Depo karbonhidratı nişasta olan, embriyo evresi geçiren çok hücreli ototroflardır.',
    'Bitkiler',
  ),
  (
    'Çok hücreli, hücre çeperi bulunmayan, besinlerini hazır alan ökaryotlardır.',
    'Hayvanlar',
  ),
  (
    'Hücrelerinde sentrozom bulunan, çoğu hareket edebilen çok hücreli heterotroflardır.',
    'Hayvanlar',
  ),
];

// (soru, olumlu yüklem, olumsuz yüklem)
const _canliSorulari = <(String, String, String)>[
  (
    'Bu canlılardan hangileri prokaryot hücre yapısındadır?',
    'prokaryottur',
    'ökaryottur',
  ),
  (
    'Bu canlılardan hangilerinin hücrelerinde zarla çevrili çekirdek bulunur?',
    'ökaryottur, zarla çevrili çekirdeği vardır',
    'prokaryottur, zarla çevrili çekirdeği yoktur',
  ),
  (
    'Bu canlılardan hangileri fotosentez yapabilir?',
    'fotosentez yapabilir',
    'fotosentez yapmaz',
  ),
  (
    'Bu canlılardan hangileri çok hücreli yapıdadır?',
    'çok hücrelidir',
    'tek hücrelidir',
  ),
  (
    'Bu canlılardan hangilerinin hücrelerinde hücre çeperi bulunur?',
    'hücre çeperi taşır',
    'hücre çeperi taşımaz',
  ),
  (
    'Bu canlılardan hangileri besinini dışarıdan hazır alan (heterotrof) canlılardır?',
    'heterotroftur',
    'ototroftur',
  ),
];

bool? _canliDeger(int q, int k) {
  final c = _canlilar[k];
  return switch (q) {
    0 => c.$2 <= 1,
    1 => c.$2 >= 2,
    2 => c.$3,
    3 => c.$4,
    4 => switch (c.$2) {
      2 => null,
      5 => false,
      _ => true,
    },
    _ => c.$5,
  };
}

final _canliAdaylari = _adaylar(
  _canlilar.length,
  _canliSorulari.length,
  _canliDeger,
);

const _basamak = ['tür', 'cins', 'familya', 'takım', 'sınıf', 'şube', 'âlem'];
const _basamakDe = [
  'türde',
  'cinste',
  'familyada',
  'takımda',
  'sınıfta',
  'şubede',
  'âlemde',
];
const _basamakLerde = [
  'türlerde',
  'cinslerde',
  'familyalarda',
  'takımlarda',
  'sınıflarda',
  'şubelerde',
  'âlemlerde',
];

/// K ile L en geç (kesinse tam olarak) x basamağında, K ile M tam olarak y
/// basamağında ortaklaşıyorsa olası (dKL, dKM, dLM) ilk ortak basamakları.
List<(int, int, int)> _basamakDunyalari(int x, bool kesin, int y) => [
  for (var a = kesin ? x : 0; a <= x; a++)
    if (a < y)
      (a, y, y)
    else if (a > y)
      (a, y, a)
    else
      for (var l = 0; l <= y; l++) (a, y, l),
];

// (tür, basamak): 0 L–M aynı, 1 L–M farklı, 2 K–L farklı, 3–5 ortak özellik
// karşılaştırmaları.
final _basamakIfadeleri = <(int, int)>[
  for (var l = 0; l <= 6; l++) (0, l),
  for (var l = 0; l <= 5; l++) (1, l),
  for (var l = 0; l <= 5; l++) (2, l),
  (3, 0),
  (4, 0),
  (5, 0),
];

bool _basamakDogru((int, int) e, (int, int, int) w) {
  final (kl, km, lm) = w;
  return switch (e.$1) {
    0 => lm <= e.$2,
    1 => lm > e.$2,
    2 => kl > e.$2,
    3 => kl < km,
    4 => lm < kl,
    _ => km < lm,
  };
}

String _basamakIfade((int, int) e) => switch (e.$1) {
  0 => 'L ile M aynı ${_basamakDe[e.$2]} bulunur.',
  1 => 'L ile M farklı ${_basamakLerde[e.$2]} bulunur.',
  2 => 'K ile L farklı ${_basamakLerde[e.$2]} bulunur.',
  3 => "K ile L'nin ortak özellikleri, K ile M'nin ortak özelliklerinden fazladır.",
  4 => "L ile M'nin ortak özellikleri, K ile L'nin ortak özelliklerinden fazladır.",
  _ => "K ile M'nin ortak özellikleri, L ile M'nin ortak özelliklerinden fazladır.",
};

// (x, kesin, y, üç ifade numarası): en az bir ifade kesinlikle doğru.
final _basamakAdaylari = () {
  final out = <(int, int, int, int, int, int)>[];
  final n = _basamakIfadeleri.length;
  for (var x = 0; x <= 5; x++) {
    for (var k = 0; k < 2; k++) {
      if (k == 1 && x == 0) continue;
      for (var y = 1; y <= 6; y++) {
        final w = _basamakDunyalari(x, k == 1, y);
        final kesinDogru = [
          for (final e in _basamakIfadeleri)
            w.every((d) => _basamakDogru(e, d)),
        ];
        for (var a = 0; a < n; a++) {
          for (var b = a + 1; b < n; b++) {
            for (var c = b + 1; c < n; c++) {
              if (kesinDogru[a] || kesinDogru[b] || kesinDogru[c]) {
                out.add((x, k, y, a, b, c));
              }
            }
          }
        }
      }
    }
  }
  return out;
}();

AdvancedItem _basamakSorusu((int, int, int, int, int, int) aday, int j) {
  final (x, k, y, a, b, c) = aday;
  final kesin = k == 1;
  final w = _basamakDunyalari(x, kesin, y);
  final d = ucluDizilimler[j % 6];
  final ifadeler = [
    for (final t in d) _basamakIfadeleri[[a, b, c][t]],
  ];
  final deger = [for (final e in ifadeler) w.every((u) => _basamakDogru(e, u))];
  final lmler = [for (final u in w) u.$3];
  final lo = lmler.reduce((p, q) => p < q ? p : q);
  final hi = lmler.reduce((p, q) => p > q ? p : q);
  final kl = kesin
      ? 'K ile L ilk kez ${_basamak[x]} basamağında ortaklaşır'
      : 'K ile L ${_basamak[x]} basamağında ve üstündeki basamaklarda kesinlikle ortaktır';
  final lm = lo == hi
      ? (lo == 0
            ? 'Buna göre L ile M aynı türdedir.'
            : 'Buna göre L ile M de ilk kez ${_basamak[lo]} basamağında ortaklaşır.')
      : 'Buna göre L ile M ${_basamak[hi]} basamağında kesinlikle ortaktır; daha alt '
            'basamaklarda ortak olup olmadıkları kesin değildir.';
  final dogrular = [
    for (var t = 0; t < 3; t++)
      if (deger[t]) _romen[t],
  ];
  return _oncullu(
    'K, L ve M canlılarından K ile L aynı ${_basamakDe[x]}'
        '${kesin ? ', farklı ${_basamakLerde[x - 1]}' : ''} bulunur; K ile M ise aynı '
        '${_basamakDe[y]}, farklı ${_basamakLerde[y - 1]} bulunur.\n'
        '${_liste([for (final e in ifadeler) _basamakIfade(e)])}'
        'Buna göre bu ifadelerden hangileri kesinlikle doğrudur?',
    deger,
    j,
    '$kl; K ile M ise ilk kez ${_basamak[y]} basamağında ortaklaşır. $lm Alt basamakta '
        'ortaklaşan canlıların ortak özellikleri daha fazladır. Kesinlikle doğru olan '
        'ifadeler: ${_ve(dogrular)}.',
  );
}

final _siniflandirma = lmSirali(
  'bl_siniflandirma',
  'Canlı âlemleri ve sınıflandırma basamakları',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final (f, j, n) = _bicim(i, 3);
    if (f == 0) {
      if (j % 11 == 10) {
        return _olgu(
          j,
          sira: (j ~/ 11) * 165 ~/ 152,
          _alemOzellik,
          eslestirme:
              'Bu özelliklerin ait olduğu âlemler sırasıyla hangi seçenekte doğru '
              'verilmiştir?',
          oncul: (a) => 'Bu özelliklerden hangileri $a âlemi için doğrudur?',
          aciklama: (x) =>
              'Birinci özellik ${x[0].$2}, ikinci özellik ${x[1].$2}, '
              'üçüncü özellik ${x[2].$2} âlemine aittir.',
        );
      }
      return _olgu(
        j,
        sira: j * 3,
        _canliAlem,
        eslestirme:
            'Bu canlıların yer aldığı âlemler sırasıyla hangi seçenekte doğru '
            'verilmiştir?',
        oncul: (a) => 'Bu canlılardan hangileri $a âleminde yer alır?',
        aciklama: (x) =>
            '${_bas(x[0].$1)} ${x[0].$2}, ${x[1].$1} ${x[1].$2}, '
            '${x[2].$1} ${x[2].$2} âlemindedir.',
      );
    }
    if (f == 1) {
      final (a, b, c, q) = _yay(_canliAdaylari, j, n);
      final d = ucluDizilimler[j % 6];
      final x = [
        for (final t in d) [a, b, c][t],
      ];
      final (soru, evet, hayir) = _canliSorulari[q];
      return _oncullu(
        '${_liste([for (final k in x) _canlilar[k].$1])}$soru',
        [for (final k in x) _canliDeger(q, k)!],
        j,
        [
          for (final k in x)
            '${_bas(_canlilar[k].$1)} (${_alemAdi[_canlilar[k].$2]}) '
                '${_canliDeger(q, k)! ? evet : hayir}.',
        ].join(' '),
      );
    }
    return _basamakSorusu(_yay(_basamakAdaylari, j, n), j);
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 6. Madde döngüleri ─────────────────────────────

// (olay, [karbon, azot, su] döngüsünde yer alır mı, atmosferdeki CO₂ etkisi,
//  topraktaki nitrat etkisi, gerçekleştiren canlı grubu, açıklama). null:
//  kaynaklarda kesin olmayan ya da birden çok yoruma açık değer.
const _donguOlay = <(String, List<bool?>, int?, int?, String?, String)>[
  (
    'Atmosferdeki serbest azotun (N₂) amonyağa dönüştürülmesi',
    [false, true, false],
    null,
    null,
    'azot bağlayıcı bakteriler',
    'Azot bağlama: azot bağlayıcı bakteriler havadaki azotu amonyağa dönüştürür (azot '
        'döngüsü).',
  ),
  (
    'Baklagillerin kök yumrularında yaşayan bakterilerin havadaki azotu bağlaması',
    [false, true, false],
    null,
    null,
    'azot bağlayıcı bakteriler',
    'Kök yumrularındaki azot bağlayıcı bakteriler havadaki azotu bitkinin kullanabileceği '
        'bileşiklere dönüştürür (azot döngüsü).',
  ),
  (
    'Topraktaki amonyağın önce nitrite, sonra nitrata dönüştürülmesi',
    [null, true, false],
    null,
    1,
    'nitrifikasyon bakterileri',
    'Nitrifikasyon: nitrifikasyon bakterileri amonyağı nitrit ve nitrata dönüştürür; '
        'topraktaki nitrat artar (azot döngüsü).',
  ),
  (
    'Topraktaki nitratın serbest azota (N₂) dönüştürülerek atmosfere verilmesi',
    [null, true, false],
    null,
    -1,
    'denitrifikasyon bakterileri',
    'Denitrifikasyon: denitrifikasyon bakterileri nitratı serbest azota dönüştürür; '
        'topraktaki nitrat azalır (azot döngüsü).',
  ),
  (
    'Oksijensiz topraklarda nitratın azot gazına dönüştürülmesi',
    [null, true, false],
    null,
    -1,
    'denitrifikasyon bakterileri',
    'Oksijensiz ortamda denitrifikasyon bakterileri nitratı azot gazına dönüştürür; '
        'topraktaki nitrat azalır (azot döngüsü).',
  ),
  (
    'Ölü canlılardaki ve boşaltım atıklarındaki azotlu organik maddelerin amonyağa '
        'dönüştürülmesi',
    [null, true, false],
    null,
    null,
    'ayrıştırıcılar',
    'Amonyaklaşma: ayrıştırıcılar (çürükçül bakteri ve mantarlar) azotlu organik '
        'maddeleri amonyağa dönüştürür (azot döngüsü).',
  ),
  (
    'Topraktaki nitratın bitki kökleriyle alınarak protein ve nükleik asit sentezinde '
        'kullanılması',
    [false, true, false],
    null,
    -1,
    'üreticiler',
    'Bitkiler (üreticiler) topraktaki nitratı alıp azotlu organik maddelere katar; topraktaki '
        'nitrat azalır (azot döngüsü).',
  ),
  (
    'Yıldırım ve şimşek enerjisiyle atmosferdeki azotun nitrata dönüşmesi',
    [false, true, false],
    0,
    1,
    null,
    'Yıldırımlar atmosferdeki azotun bir bölümünü nitrata dönüştürür; topraktaki nitrat '
        'artar (azot döngüsü).',
  ),
  (
    'Hayvanların bitkileri yiyerek azotlu organik maddeleri alması',
    [null, true, false],
    null,
    null,
    'tüketiciler',
    'Tüketiciler azotlu organik maddeleri besin yoluyla üreticilerden alır (azot döngüsü).',
  ),
  (
    'Azotlu gübre kullanılarak toprağa nitrat eklenmesi',
    [false, true, false],
    null,
    1,
    null,
    'Azotlu gübreler topraktaki nitrat miktarını artırır (azot döngüsü).',
  ),
  (
    'Bitkilerin fotosentezle atmosferdeki karbondioksiti organik maddeye dönüştürmesi',
    [true, false, null],
    -1,
    0,
    'üreticiler',
    'Fotosentez: üreticiler atmosferdeki karbondioksiti kullanır; karbondioksit miktarı '
        'azalır (karbon döngüsü).',
  ),
  (
    'Deniz ve okyanuslardaki fitoplanktonların fotosentez yapması',
    [true, false, null],
    -1,
    0,
    'üreticiler',
    'Fitoplanktonlar (üreticiler) fotosentezle karbondioksit kullanır; karbondioksit miktarı '
        'azalır (karbon döngüsü).',
  ),
  (
    'Canlıların oksijenli solunumla organik maddeleri parçalayıp karbondioksit açığa '
        'çıkarması',
    [true, false, null],
    1,
    0,
    null,
    'Oksijenli solunum karbondioksit açığa çıkarır; atmosferdeki karbondioksit artar (karbon '
        'döngüsü).',
  ),
  (
    'Ayrıştırıcıların ölü bitki ve hayvan kalıntılarındaki organik maddeleri parçalaması',
    [true, null, null],
    1,
    null,
    'ayrıştırıcılar',
    'Ayrıştırıcılar ölü kalıntıları parçalarken karbondioksit açığa çıkarır; atmosferdeki '
        'karbondioksit artar (karbon döngüsü).',
  ),
  (
    'Kömür, petrol ve doğal gaz gibi fosil yakıtların yakılması',
    [true, null, null],
    1,
    null,
    null,
    'Fosil yakıtların yanması karbondioksit açığa çıkarır; atmosferdeki karbondioksit artar '
        '(karbon döngüsü).',
  ),
  (
    'Ormanların yanması',
    [true, null, null],
    1,
    null,
    null,
    'Orman yangınlarında organik maddeler yanar ve karbondioksit açığa çıkar; atmosferdeki '
        'karbondioksit artar (karbon döngüsü).',
  ),
  (
    'Kemosentetik bakterilerin karbondioksiti kullanarak organik madde üretmesi',
    [true, null, null],
    -1,
    null,
    null,
    'Kemosentez karbondioksiti organik maddeye katar; atmosferdeki karbondioksit azalır '
        '(karbon döngüsü).',
  ),
  (
    'Ölü canlı kalıntılarının milyonlarca yılda kömür ve petrole dönüşmesi',
    [true, false, false],
    null,
    null,
    null,
    'Fosilleşme, karbonun uzun süre kömür ve petrol olarak depolanmasını sağlar (karbon '
        'döngüsü).',
  ),
  (
    'Hayvanların bitkileri yiyerek organik karbon bileşiklerini alması',
    [true, null, false],
    0,
    null,
    'tüketiciler',
    'Tüketiciler organik karbon bileşiklerini besin yoluyla üreticilerden alır (karbon '
        'döngüsü).',
  ),
  (
    'Yanardağ patlamalarıyla atmosfere gaz verilmesi',
    [true, null, null],
    1,
    null,
    null,
    'Yanardağlar atmosfere karbondioksit verir; atmosferdeki karbondioksit artar (karbon '
        'döngüsü).',
  ),
  (
    'Bitkilerin yapraklarındaki stomalardan su buharı vermesi (terleme)',
    [false, false, true],
    0,
    0,
    'üreticiler',
    'Terleme: bitkiler (üreticiler) yapraklarından su buharı verir (su döngüsü).',
  ),
  (
    'Deniz, göl ve akarsu yüzeylerinden suyun buharlaşması',
    [false, false, true],
    0,
    0,
    null,
    'Buharlaşma, suyu sıvı hâlden su buharına dönüştürür (su döngüsü).',
  ),
  (
    'Atmosferdeki su buharının yoğunlaşıp yağış olarak yeryüzüne düşmesi',
    [false, false, true],
    null,
    null,
    null,
    'Yoğunlaşan su buharı yağış olarak yeryüzüne döner (su döngüsü).',
  ),
  (
    'Yağışla düşen suyun toprağa sızarak yer altı sularına karışması',
    [false, false, true],
    0,
    null,
    null,
    'Sızma ile su yer altı sularına karışır (su döngüsü).',
  ),
  (
    'Hayvanların ter ve idrarla vücutlarından su atması',
    [false, null, true],
    0,
    null,
    'tüketiciler',
    'Tüketiciler terleme ve boşaltımla çevreye su verir (su döngüsü).',
  ),
  (
    'Bitkilerin kökleriyle topraktan su alması',
    [false, false, true],
    0,
    0,
    'üreticiler',
    'Bitkiler (üreticiler) topraktaki suyu kökleriyle alır (su döngüsü).',
  ),
  (
    'Buzulların erimesiyle oluşan suyun akarsulara karışması',
    [false, false, true],
    0,
    0,
    null,
    'Eriyen buzul suları akarsulara karışır (su döngüsü).',
  ),
  (
    'Hayvanların oksijenli solunumla atmosfere karbondioksit vermesi',
    [true, false, null],
    1,
    0,
    'tüketiciler',
    'Tüketiciler solunumla karbondioksit verir; atmosferdeki karbondioksit artar (karbon '
        'döngüsü).',
  ),
  (
    'Bitkilerin gece solunum yaparak karbondioksit açığa çıkarması',
    [true, false, null],
    1,
    0,
    'üreticiler',
    'Geceleri fotosentez yapamayan bitkiler (üreticiler) solunumla karbondioksit verir; '
        'atmosferdeki karbondioksit artar (karbon döngüsü).',
  ),
  (
    'Mantarların ölü ağaç gövdelerini çürüterek parçalaması',
    [true, null, null],
    1,
    null,
    'ayrıştırıcılar',
    'Ayrıştırıcı mantarlar ölü ağaçtaki organik maddeleri parçalarken karbondioksit açığa '
        'çıkarır (karbon döngüsü).',
  ),
  (
    'Atmosferdeki karbondioksitin okyanus yüzeyinde suda çözünmesi',
    [true, false, null],
    -1,
    0,
    null,
    'Okyanuslar atmosferdeki karbondioksiti çözerek depolar; atmosferdeki karbondioksit '
        'azalır (karbon döngüsü).',
  ),
  (
    'Çürükçül bakterilerin idrardaki üreyi amonyağa dönüştürmesi',
    [null, true, false],
    null,
    null,
    'ayrıştırıcılar',
    'Ayrıştırıcı bakteriler azotlu atık olan üreyi amonyağa dönüştürür (azot döngüsü).',
  ),
];

const _donguSorulari = [
  'Bu olaylardan hangileri karbon döngüsünde yer alır?',
  'Bu olaylardan hangileri azot döngüsünde yer alır?',
  'Bu olaylardan hangileri su döngüsünde yer alır?',
  'Bu olaylardan hangileri atmosferdeki karbondioksit miktarını artırır?',
  'Bu olaylardan hangileri atmosferdeki karbondioksit miktarını azaltır?',
  'Bu olaylardan hangileri topraktaki nitrat miktarını artırır?',
  'Bu olaylardan hangileri topraktaki nitrat miktarını azaltır?',
];

bool? _donguDeger(int q, int k) {
  final (_, uyelik, co2, nitrat, _, _) = _donguOlay[k];
  return switch (q) {
    0 || 1 || 2 => uyelik[q],
    3 => co2 == null ? null : co2 == 1,
    4 => co2 == null ? null : co2 == -1,
    5 => nitrat == null ? null : nitrat == 1,
    _ => nitrat == null ? null : nitrat == -1,
  };
}

final _donguAdaylari = _adaylar(
  _donguOlay.length,
  _donguSorulari.length,
  _donguDeger,
  sinif: (k) => _donguOlay[k].$5,
);

final _maddeDongusu = lmSirali(
  'bl_madde_dongusu',
  'Karbon, azot ve su döngüsünde olaylar ve canlılar',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final (a, b, c, q) = _yay(_donguAdaylari, i, lmAileBoyu);
    final d = ucluDizilimler[i % 6];
    final x = [
      for (final t in d) [a, b, c][t],
    ];
    final liste = _liste([for (final k in x) _donguOlay[k].$1]);
    final aciklama = [
      for (var t = 0; t < 3; t++) '${_romen[t]}. ${_donguOlay[x[t]].$6}',
    ].join(' ');
    if (q < 0) {
      return _esle(
        '${liste}Bu olayları gerçekleştiren canlılar sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
        [for (final k in x) _donguOlay[k].$5!],
        i ~/ 6,
        aciklama,
      );
    }
    return _oncullu(
      '$liste${_donguSorulari[q]}',
      [for (final k in x) _donguDeger(q, k)!],
      i,
      aciklama,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 7. Soyağacı ─────────────────────────────

/// Sadeleşmiş kesir (olasılık hesapları).
class _K {
  final int p, q;
  const _K._(this.p, this.q);
  factory _K(int p, [int q = 1]) {
    if (q < 0) {
      p = -p;
      q = -q;
    }
    final g = p.gcd(q);
    return _K._(p ~/ g, q ~/ g);
  }
  _K operator +(_K o) => _K(p * o.q + o.p * q, q * o.q);
  _K operator -(_K o) => _K(p * o.q - o.p * q, q * o.q);
  _K operator *(_K o) => _K(p * o.p, q * o.q);
  _K operator /(_K o) => _K(p * o.q, q * o.p);
  bool get sifir => p == 0;
  bool get bir => p == q;
  bool get gecerli => p > 0 && p <= q;
  @override
  bool operator ==(Object o) => o is _K && o.p == p && o.q == q;
  @override
  int get hashCode => Object.hash(p, q);
  String get s => kesir(p, q);
}

final _yarim = _K(1, 2);

// 0: otozomal çekinik, 1: otozomal baskın, 2: X'e bağlı çekinik.
const _kalitimCumle = [
  'Bir hastalık otozomal çekinik bir alelle kalıtılmaktadır.',
  'Bir hastalık otozomal baskın bir alelle kalıtılmaktadır.',
  'Bir hastalık X kromozomunda taşınan çekinik bir alelle kalıtılmaktadır.',
];

/// Hastalık aleli sayısı [g] olan bireyin hasta olup olmadığı.
bool _hastaMi(int m, bool erkek, int g) => switch (m) {
  0 => g == 2,
  1 => g >= 1,
  _ => erkek ? g == 1 : g == 2,
};

/// Anne aleli [ga], baba aleli [gb] olan çiftin çocuğunda hastalık aleli
/// sayısının (0, 1, 2) dağılımı. X'e bağlı kalıtımda baba kızına X
/// kromozomunu, oğluna Y kromozomunu verir.
List<_K> _cocukDagilim(int m, bool erkek, int ga, int gb) {
  final pa = _K(ga, 2), bir = _K(1), sifir = _K(0);
  if (m == 2) {
    if (erkek || gb == 0) return [bir - pa, pa, sifir];
    return [sifir, bir - pa, pa];
  }
  final pb = _K(gb, 2);
  return [(bir - pa) * (bir - pb), pa * (bir - pb) + (bir - pa) * pb, pa * pb];
}

/// Belirli cinsiyetteki çocuğun [durum] (0 hasta, 1 sağlıklı, 2 heterozigot ya
/// da taşıyıcı) olma olasılığı.
_K _durumOlasilik(int m, bool erkek, int durum, int ga, int gb) {
  final d = _cocukDagilim(m, erkek, ga, gb);
  if (durum == 2) return d[1];
  var t = _K(0);
  for (var g = 0; g < 3; g++) {
    if (_hastaMi(m, erkek, g) == (durum == 0)) t = t + d[g];
  }
  return t;
}

/// Doğacak çocuk tanımı: (cinsiyet: 0 belirsiz, 1 kız, 2 erkek; durum).
typedef _Tanim = (int, int);

String _tanimYazi(int m, _Tanim t) {
  final (c, d) = t;
  if (d == 2) return m == 2 ? 'taşıyıcı bir kız' : 'heterozigot';
  final s = d == 0 ? 'hasta' : 'sağlıklı';
  return switch (c) {
    0 => s,
    1 => '$s bir kız',
    _ => '$s bir erkek',
  };
}

/// Ortak (cinsiyet dâhil) olasılık.
_K _tanimOlasilik(int m, _Tanim t, int ga, int gb) {
  final (c, d) = t;
  if (d == 2 && m == 2) return _yarim * _durumOlasilik(m, false, 2, ga, gb);
  if (c == 0) {
    return _yarim * _durumOlasilik(m, false, d, ga, gb) +
        _yarim * _durumOlasilik(m, true, d, ga, gb);
  }
  return _yarim * _durumOlasilik(m, c == 2, d, ga, gb);
}

/// Cinsiyet çarpanı unutulduğunda bulunan (koşullu) olasılık.
_K _tanimKosullu(int m, _Tanim t, int ga, int gb) {
  final (c, d) = t;
  if (d == 2 && m == 2) return _durumOlasilik(m, false, 2, ga, gb);
  if (c == 0) return _tanimOlasilik(m, t, ga, gb);
  return _durumOlasilik(m, c == 2, d, ga, gb);
}

/// Olasılık yanıtlı soru: adaylardan (0, 1] aralığındakiler, gerekirse
/// yaygın kesirler çeldirici olur.
AdvancedItem _olasilikSorusu(
  String kok,
  _K dogru,
  Iterable<_K> adaylar,
  String aciklama,
) {
  const havuz = [
    (1, 4), (1, 2), (3, 4), (1, 8), (3, 8), (1, 16), (3, 16), (1, 3), (2, 3), //
    (1, 6), (1, 9), (5, 8), (1, 32), (9, 16), (1, 12),
  ];
  final uygun = [
    ...adaylar,
    for (final (p, q) in havuz) _K(p, q),
  ].where((x) => x.gecerli);
  return secenekli(kok, dogru.s, uygun.map((x) => x.s), aciklama);
}

String _ebeveynYazi(int m, bool erkek, int g) {
  if (m == 2) {
    if (erkek) return g == 1 ? 'hasta' : 'sağlıklı';
    return const ['hastalık alelini taşımayan', 'taşıyıcı', 'hasta'][g];
  }
  return m == 0
      ? const [
          'hastalık alelini taşımayan',
          'heterozigot (taşıyıcı)',
          'hasta',
        ][g]
      : const ['sağlıklı', 'heterozigot hasta', 'homozigot hasta'][g];
}

/// Kalıtım biçimine göre çocukların hasta olma olasılıkları cümlesi.
String _cocukOrani(int m, int ga, int gb) {
  if (m == 2) {
    return 'Bu çiftin oğullarının hasta olma olasılığı '
        '${_durumOlasilik(m, true, 0, ga, gb).s}, kızlarının hasta olma olasılığı '
        '${_durumOlasilik(m, false, 0, ga, gb).s}, kızlarının taşıyıcı olma olasılığı '
        '${_durumOlasilik(m, false, 2, ga, gb).s} olur; bir çocuğun kız ya da erkek olma '
        'olasılığı 1/2 alınır.';
  }
  return 'Bu çiftin bir çocuğunun hasta olma olasılığı ${_durumOlasilik(m, true, 0, ga, gb).s}, '
      'heterozigot olma olasılığı ${_durumOlasilik(m, true, 2, ga, gb).s} olur; bir çocuğun '
      'kız ya da erkek olma olasılığı 1/2 alınır.';
}

// Çift tanımları: (kalıtım, metin, mevcut çocuklar (erkek mi, hasta mı),
//  anne aleli, baba aleli, çıkarım).
const _ciftler = <(int, String, List<(bool, bool)>, int, int, String)>[
  (
    0,
    'Sağlıklı bir anne ile sağlıklı bir babanın ilk çocukları hasta bir kız, ikinci '
        'çocukları sağlıklı bir erkektir.',
    [(false, true), (true, false)],
    1,
    1,
    'Sağlıklı anne ve babanın hasta (aa) bir çocuğu olduğundan ikisi de a aleli taşır; anne '
        've baba Aa genotiplidir (A: sağlıklı alel, a: hastalık aleli).',
  ),
  (
    0,
    'Sağlıklı bir anne ile hasta bir babanın ilk çocukları hasta bir erkek, ikinci çocukları '
        'sağlıklı bir kızdır.',
    [(true, true), (false, false)],
    1,
    2,
    'Hasta baba aa genotiplidir. Sağlıklı annenin hasta bir çocuğu olduğundan anne Aa '
        'genotiplidir (A: sağlıklı alel, a: hastalık aleli).',
  ),
  (
    0,
    'Hasta bir anne ile sağlıklı bir babanın ilk çocukları sağlıklı bir kız, ikinci çocukları '
        'hasta bir kızdır.',
    [(false, false), (false, true)],
    2,
    1,
    'Hasta anne aa genotiplidir. Sağlıklı babanın hasta bir çocuğu olduğundan baba Aa '
        'genotiplidir (A: sağlıklı alel, a: hastalık aleli).',
  ),
  (
    0,
    'Annesi hasta olan sağlıklı bir kadın, babası hasta olan sağlıklı bir erkekle '
        'evlenmiştir.',
    [],
    1,
    1,
    'Kadın hasta annesinden, erkek hasta babasından a aleli almıştır; ikisi de sağlıklı '
        'olduğundan genotipleri Aa olur (A: sağlıklı alel, a: hastalık aleli).',
  ),
  (
    0,
    'Hasta bir kadın, annesi hasta olan sağlıklı bir erkekle evlenmiştir.',
    [],
    2,
    1,
    'Hasta kadın aa genotiplidir. Erkek hasta annesinden a aleli almıştır; sağlıklı '
        'olduğundan genotipi Aa olur (A: sağlıklı alel, a: hastalık aleli).',
  ),
  (
    0,
    'Babası hasta olan sağlıklı bir kadın, hasta bir erkekle evlenmiştir.',
    [],
    1,
    2,
    'Kadın hasta babasından a aleli almıştır; sağlıklı olduğundan genotipi Aa olur. Hasta '
        'erkek aa genotiplidir (A: sağlıklı alel, a: hastalık aleli).',
  ),
  (
    1,
    'Hasta bir anne ile hasta bir babanın ilk çocukları sağlıklı bir erkek, ikinci çocukları '
        'hasta bir kızdır.',
    [(true, false), (false, true)],
    1,
    1,
    'Hasta anne ve babanın sağlıklı (aa) bir çocuğu olduğundan ikisi de a aleli taşır; anne '
        've baba Aa genotiplidir (A: hastalık aleli, a: sağlıklı alel).',
  ),
  (
    1,
    'Hasta bir anne ile sağlıklı bir babanın ilk çocukları sağlıklı bir kız, ikinci çocukları '
        'hasta bir erkektir.',
    [(false, false), (true, true)],
    1,
    0,
    'Sağlıklı baba aa genotiplidir. Hasta annenin sağlıklı bir çocuğu olduğundan anne Aa '
        'genotiplidir (A: hastalık aleli, a: sağlıklı alel).',
  ),
  (
    1,
    'Sağlıklı bir anne ile hasta bir babanın ilk çocukları hasta bir kız, ikinci çocukları '
        'sağlıklı bir kızdır.',
    [(false, true), (false, false)],
    0,
    1,
    'Sağlıklı anne aa genotiplidir. Hasta babanın sağlıklı bir çocuğu olduğundan baba Aa '
        'genotiplidir (A: hastalık aleli, a: sağlıklı alel).',
  ),
  (
    1,
    'Annesi sağlıklı olan hasta bir kadın, babası sağlıklı olan hasta bir erkekle '
        'evlenmiştir.',
    [],
    1,
    1,
    'Kadın sağlıklı annesinden, erkek sağlıklı babasından a aleli almıştır; ikisi de hasta '
        'olduğundan genotipleri Aa olur (A: hastalık aleli, a: sağlıklı alel).',
  ),
  (
    1,
    'Babası sağlıklı olan hasta bir kadın, sağlıklı bir erkekle evlenmiştir.',
    [],
    1,
    0,
    'Kadın sağlıklı babasından a aleli almıştır; hasta olduğundan genotipi Aa olur. Sağlıklı '
        'erkek aa genotiplidir (A: hastalık aleli, a: sağlıklı alel).',
  ),
  (
    1,
    'Sağlıklı bir kadın, annesi sağlıklı olan hasta bir erkekle evlenmiştir.',
    [],
    0,
    1,
    'Sağlıklı kadın aa genotiplidir. Erkek sağlıklı annesinden a aleli almıştır; hasta '
        'olduğundan genotipi Aa olur (A: hastalık aleli, a: sağlıklı alel).',
  ),
  (
    2,
    'Sağlıklı bir anne ile sağlıklı bir babanın ilk çocukları hasta bir erkek, ikinci '
        'çocukları sağlıklı bir kızdır.',
    [(true, true), (false, false)],
    1,
    0,
    'Hasta oğul, hastalık alelini taşıyan X kromozomunu annesinden almıştır; sağlıklı anne '
        'taşıyıcıdır. Baba sağlıklıdır.',
  ),
  (
    2,
    'Sağlıklı bir anne ile hasta bir babanın ilk çocukları hasta bir kız, ikinci çocukları '
        'sağlıklı bir kızdır.',
    [(false, true), (false, false)],
    1,
    1,
    'Hasta kız X kromozomlarından birini annesinden aldığından sağlıklı anne taşıyıcıdır. '
        'Baba hastadır.',
  ),
  (
    2,
    'Sağlıklı bir anne ile hasta bir babanın ilk çocukları sağlıklı bir kız, ikinci '
        'çocukları hasta bir erkektir.',
    [(false, false), (true, true)],
    1,
    1,
    'Hasta oğul hastalık alelini annesinden aldığından sağlıklı anne taşıyıcıdır. Baba '
        'hastadır.',
  ),
  (
    2,
    'Hasta bir kadın, sağlıklı bir erkekle evlenmiştir.',
    [],
    2,
    0,
    'Hasta kadının iki X kromozomu da hastalık aleli taşır. Erkek sağlıklıdır.',
  ),
  (
    2,
    'Babası hasta olan sağlıklı bir kadın, sağlıklı bir erkekle evlenmiştir.',
    [],
    1,
    0,
    'Kadın, hasta babasından hastalık aleli taşıyan X kromozomunu almıştır; sağlıklı '
        'olduğundan taşıyıcıdır. Erkek sağlıklıdır.',
  ),
  (
    2,
    'Babası hasta olan sağlıklı bir kadın, hasta bir erkekle evlenmiştir.',
    [],
    1,
    1,
    'Kadın, hasta babasından hastalık aleli taşıyan X kromozomunu almıştır; sağlıklı '
        'olduğundan taşıyıcıdır. Erkek hastadır.',
  ),
  (
    2,
    'Hastalık alelini taşımadığı bilinen sağlıklı bir kadın, hasta bir erkekle evlenmiştir.',
    [],
    0,
    1,
    'Kadın hastalık aleli taşımaz. Erkek hastadır; X kromozomunu kızlarına verir.',
  ),
  (
    2,
    'Annesi hasta olan sağlıklı bir kadın, sağlıklı bir erkekle evlenmiştir.',
    [],
    1,
    0,
    'Kadın, hasta annesinden hastalık aleli taşıyan bir X kromozomu almıştır; sağlıklı '
        'olduğundan taşıyıcıdır. Erkek sağlıklıdır.',
  ),
];

const _sira = ['birincisinin', 'ikincisinin', 'üçüncüsünün'];
const _siraSifat = ['birinci', 'ikinci', 'üçüncü'];

/// Çiftin yeni doğacak çocukları için tanım dizisi sorusu.
AdvancedItem _ciftDizi(int c, List<_Tanim> dizi, bool sirasiz, int i) {
  final (m, metin, _, ga, gb, cikarim) = _ciftler[c];
  final p = [for (final t in dizi) _tanimOlasilik(m, t, ga, gb)];
  final k = [for (final t in dizi) _tanimKosullu(m, t, ga, gb)];
  var dogru = p.reduce((x, y) => x * y);
  if (sirasiz) dogru = dogru * _K(2);
  final yazi = [for (final t in dizi) _tanimYazi(m, t)];
  final String soru;
  if (dizi.length == 1) {
    soru =
        'Bu çiftin yeni doğacak bir çocuğunun ${yazi[0]} olma olasılığı kaçtır?';
  } else if (sirasiz) {
    soru =
        'Bu çiftin yeni doğacak iki çocuğundan birinin ${yazi[0]}, diğerinin ${yazi[1]} '
        'olma olasılığı kaçtır?';
  } else {
    soru =
        'Bu çiftin yeni doğacak ${dizi.length == 2 ? 'iki' : 'üç'} çocuğundan '
        '${[for (var t = 0; t < dizi.length; t++) '${_sira[t]} ${yazi[t]}'].join(', ')} olma '
        'olasılığı kaçtır?';
  }
  // Her farklı tanım için türetme: cinsiyetli tanımlarda 1/2 çarpanı, X'e
  // bağlı kalıtımda cinsiyetsiz tanımlarda iki cinsiyetin ortalaması.
  final turetme = <String>[];
  for (var t = 0; t < dizi.length; t++) {
    final (c, d) = dizi[t];
    final ad = '${yazi[t]} olma olasılığı';
    if (turetme.any((x) => x.startsWith(ad))) continue;
    if (c != 0 || (d == 2 && m == 2)) {
      turetme.add('$ad 1/2 · ${k[t].s} = ${p[t].s}');
    } else if (m == 2) {
      final kiz = _durumOlasilik(m, false, d, ga, gb);
      final erkek = _durumOlasilik(m, true, d, ga, gb);
      turetme.add('$ad 1/2 · ${kiz.s} + 1/2 · ${erkek.s} = ${p[t].s}');
    } else if (d == 1) {
      turetme.add(
        '$ad 1 − ${_durumOlasilik(m, true, 0, ga, gb).s} = ${p[t].s}',
      );
    }
  }
  final carpim = sirasiz
      ? '2 · ${p.map((x) => x.s).join(' · ')}'
      : p.map((x) => x.s).join(' · ');
  final aciklama = [
    cikarim,
    _cocukOrani(m, ga, gb),
    if (turetme.isNotEmpty) '${_bas(_ve(turetme))} olur.',
    dizi.length == 1 && !sirasiz
        ? 'İstenen olasılık ${dogru.s} olur.'
        : 'Çocuklar birbirinden bağımsız olduğundan istenen olasılık $carpim = ${dogru.s} '
              'olur.',
  ].join(' ');
  final kosulluCarpim = k.reduce((x, y) => x * y) * (sirasiz ? _K(2) : _K(1));
  return _olasilikSorusu('${_kalitimCumle[m]} $metin $soru', dogru, [
    kosulluCarpim,
    if (dizi.length > 1) p.first,
    if (sirasiz) dogru * _yarim else dogru * _K(2),
    _K(1) - dogru,
    if (dizi.length > 1) p.reduce((x, y) => x + y),
    dogru * _yarim,
  ], aciklama);
}

/// Çiftin yeni doğacak bir çocuğu belli cinsiyette olursa hasta olma olasılığı.
AdvancedItem _ciftKosullu(int c, bool erkek) {
  final (m, metin, _, ga, gb, cikarim) = _ciftler[c];
  final dogru = _durumOlasilik(m, erkek, 0, ga, gb);
  return _olasilikSorusu(
    '${_kalitimCumle[m]} $metin Bu çiftin yeni doğacak bir çocuğu '
        '${erkek ? 'erkek' : 'kız'} olursa bu çocuğun hasta olma olasılığı kaçtır?',
    dogru,
    [
      dogru * _yarim,
      _durumOlasilik(m, !erkek, 0, ga, gb),
      _K(1) - dogru,
      _tanimOlasilik(m, (0, 0), ga, gb),
    ],
    '$cikarim ${_cocukOrani(m, ga, gb)} Çocuğun cinsiyeti verildiğinden 1/2 çarpanı '
        'kullanılmaz; yanıt ${dogru.s} olur.',
  );
}

/// Mevcut bir çocuğun heterozigot (taşıyıcı) olma olasılığı.
AdvancedItem _ciftMevcut(int c, int k) {
  final (m, metin, cocuklar, ga, gb, cikarim) = _ciftler[c];
  final (erkek, hasta) = cocuklar[k];
  final d = _cocukDagilim(m, erkek, ga, gb);
  // Koşul: çocuğun görülen fenotipi.
  final uygun = [
    for (var g = 0; g < 3; g++)
      if (_hastaMi(m, erkek, g) == hasta) g,
  ];
  final toplam = uygun.fold(_K(0), (x, g) => x + d[g]);
  final dogru = d[1] / toplam;
  final durum = hasta ? 'hasta' : 'sağlıklı';
  final ad = m == 2 ? 'taşıyıcı' : 'heterozigot';
  return _olasilikSorusu(
    '${_kalitimCumle[m]} $metin Bu çiftin $durum olan ${_siraSifat[k]} çocuğunun $ad olma '
        'olasılığı kaçtır?',
    dogru,
    [d[1], _yarim, _K(1) - dogru, _K(1, 4), _K(2, 3), _K(1, 3)],
    '$cikarim Bu çaprazlamada ${erkek ? 'oğulların' : 'kızların'} genotip olasılıkları '
        '${[for (var g = 0; g < 3; g++)
          if (!d[g].sifir) '${_genotipAdi(m, erkek, g)} ${d[g].s}'].join(', ')} '
        'olur. Çocuğun $durum olduğu bilindiğinden yalnız ${_ve([for (final g in uygun)
          if (!d[g].sifir) _genotipAdi(m, erkek, g)])} '
        'olasılıkları kalır; $ad olma olasılığı ${d[1].s} / ${toplam.s} = ${dogru.s} olur.',
  );
}

String _genotipAdi(int m, bool erkek, int g) {
  if (m == 2) {
    if (erkek) return g == 1 ? 'hasta' : 'sağlıklı';
    return const ['alel taşımayan', 'taşıyıcı', 'hasta'][g];
  }
  return m == 0 ? const ['AA', 'Aa', 'aa'][g] : const ['aa', 'Aa', 'AA'][g];
}

/// Otozomal çiftlerde anne ve babanın genotipi.
AdvancedItem _ciftGenotip(int c, int i) {
  final (m, metin, _, ga, gb, cikarim) = _ciftler[c];
  // Otozomal kalıtımda alel sayısına göre genotip adı: hastalık aleli
  // çekinikse 0 → homozigot baskın, baskınsa 0 → homozigot çekinik.
  String g(int x) => switch (m == 0 ? x : 2 - x) {
    0 => 'homozigot baskın',
    1 => 'heterozigot',
    _ => 'homozigot çekinik',
  };
  final dogru = '${g(ga)} – ${g(gb)}';
  bool uyar(bool erkek, int x, int gercek) =>
      _hastaMi(m, erkek, x) == _hastaMi(m, erkek, gercek);
  final ciftler = [
    for (var r = 0; r < 9; r++) ((ga + r ~/ 3 + i) % 3, (gb + r + i) % 3),
  ];
  return secenekli(
    '${_kalitimCumle[m]} $metin Buna göre anne ve babanın bu hastalık bakımından '
        'genotipleri sırasıyla hangi seçenekte doğru verilmiştir?',
    dogru,
    [
      // Önce fenotiple uyumlu (tipik çıkarım hatası), sonra diğer birleşimler.
      for (final (x, y) in ciftler)
        if (uyar(false, x, ga) && uyar(true, y, gb)) '${g(x)} – ${g(y)}',
      '${g(gb)} – ${g(ga)}',
      for (final (x, y) in ciftler) '${g(x)} – ${g(y)}',
    ],
    '$cikarim Buna göre anne ${g(ga)}, baba ${g(gb)} olur.',
  );
}

// Üç kuşak: hedef birey (T) tanımları: (kalıtım, cinsiyet erkek mi, metin
//  (ad yerine #), aleli sayısı dağılımı, açıklama).
const _hedefTanim = <(int, bool, String, List<(int, int, int)>, String)>[
  (
    0,
    false,
    '# sağlıklıdır; anne ve babası da sağlıklıdır, ancak bir kardeşi hastadır.',
    [(0, 1, 3), (1, 2, 3)],
    "#'in anne ve babası sağlıklı, kardeşi hasta olduğundan anne ve babası Aa × Aa olur; "
        "sağlıklı #'in Aa olma olasılığı 2/3 olur.",
  ),
  (
    0,
    false,
    '# sağlıklıdır; annesi hastadır.',
    [(1, 1, 1)],
    "# hasta annesinden a aleli almıştır; genotipi Aa olur.",
  ),
  (
    0,
    false,
    '# sağlıklıdır; babası hastadır.',
    [(1, 1, 1)],
    "# hasta babasından a aleli almıştır; genotipi Aa olur.",
  ),
  (
    0,
    false,
    '# hastadır; anne ve babası sağlıklıdır.',
    [(2, 1, 1)],
    '# hasta olduğundan genotipi aa olur.',
  ),
  (
    0,
    true,
    '# sağlıklıdır; anne ve babası da sağlıklıdır, ancak bir kardeşi hastadır.',
    [(0, 1, 3), (1, 2, 3)],
    "#'ın anne ve babası sağlıklı, kardeşi hasta olduğundan anne ve babası Aa × Aa olur; "
        "sağlıklı #'ın Aa olma olasılığı 2/3 olur.",
  ),
  (
    0,
    true,
    '# sağlıklıdır; annesi hastadır.',
    [(1, 1, 1)],
    '# hasta annesinden a aleli almıştır; genotipi Aa olur.',
  ),
  (
    0,
    true,
    '# sağlıklıdır; babası hastadır.',
    [(1, 1, 1)],
    '# hasta babasından a aleli almıştır; genotipi Aa olur.',
  ),
  (
    0,
    true,
    '# hastadır; anne ve babası sağlıklıdır.',
    [(2, 1, 1)],
    '# hasta olduğundan genotipi aa olur.',
  ),
  (
    1,
    false,
    '# hastadır; anne ve babası da hastadır, ancak bir kardeşi sağlıklıdır.',
    [(1, 2, 3), (2, 1, 3)],
    "#'in anne ve babası hasta, kardeşi sağlıklı olduğundan anne ve babası Aa × Aa olur; "
        "hasta #'in Aa olma olasılığı 2/3, AA olma olasılığı 1/3 olur.",
  ),
  (
    1,
    false,
    '# hastadır; annesi sağlıklıdır.',
    [(1, 1, 1)],
    '# sağlıklı annesinden a aleli almıştır; genotipi Aa olur.',
  ),
  (
    1,
    false,
    '# hastadır; babası sağlıklıdır.',
    [(1, 1, 1)],
    '# sağlıklı babasından a aleli almıştır; genotipi Aa olur.',
  ),
  (
    1,
    false,
    '# sağlıklıdır; anne ve babası hastadır.',
    [(0, 1, 1)],
    '# sağlıklı olduğundan genotipi aa olur.',
  ),
  (
    1,
    true,
    '# hastadır; anne ve babası da hastadır, ancak bir kardeşi sağlıklıdır.',
    [(1, 2, 3), (2, 1, 3)],
    "#'ın anne ve babası hasta, kardeşi sağlıklı olduğundan anne ve babası Aa × Aa olur; "
        "hasta #'ın Aa olma olasılığı 2/3, AA olma olasılığı 1/3 olur.",
  ),
  (
    1,
    true,
    '# hastadır; annesi sağlıklıdır.',
    [(1, 1, 1)],
    '# sağlıklı annesinden a aleli almıştır; genotipi Aa olur.',
  ),
  (
    1,
    true,
    '# hastadır; babası sağlıklıdır.',
    [(1, 1, 1)],
    '# sağlıklı babasından a aleli almıştır; genotipi Aa olur.',
  ),
  (
    1,
    true,
    '# sağlıklıdır; anne ve babası hastadır.',
    [(0, 1, 1)],
    '# sağlıklı olduğundan genotipi aa olur.',
  ),
  (
    2,
    false,
    '# sağlıklıdır; anne ve babası da sağlıklıdır, ancak erkek kardeşi hastadır.',
    [(0, 1, 2), (1, 1, 2)],
    "#'in hasta erkek kardeşi alelini annesinden aldığından annesi taşıyıcıdır; sağlıklı "
        "#'in taşıyıcı olma olasılığı 1/2 olur.",
  ),
  (
    2,
    false,
    '# sağlıklıdır; babası hastadır.',
    [(1, 1, 1)],
    '# hasta babasından hastalık alelini taşıyan X kromozomunu almıştır; taşıyıcıdır.',
  ),
  (
    2,
    false,
    '# sağlıklıdır; annesi hastadır.',
    [(1, 1, 1)],
    '# hasta annesinden hastalık aleli taşıyan bir X kromozomu almıştır; sağlıklı olduğundan taşıyıcıdır.',
  ),
  (
    2,
    false,
    '# hastadır; babası da hastadır.',
    [(2, 1, 1)],
    '# hasta olduğundan iki X kromozomunda da hastalık aleli taşır.',
  ),
  (
    2,
    true,
    '# sağlıklıdır; anne ve babası da sağlıklıdır, ancak erkek kardeşi hastadır.',
    [(0, 1, 1)],
    '# erkek olduğundan tek X kromozomu taşır; sağlıklı olduğundan hastalık aleli taşımaz.',
  ),
  (
    2,
    true,
    '# hastadır; anne ve babası sağlıklıdır.',
    [(1, 1, 1)],
    '# erkek ve hasta olduğundan tek X kromozomunda hastalık aleli taşır.',
  ),
];

// Eş tanımları: (kalıtım, cinsiyet erkek mi, metin, dağılım, açıklama).
const _esTanim = <(int, bool, String, List<(int, int, int)>, String)>[
  (0, true, 'hasta olan #', [(2, 1, 1)], '# hasta olduğundan aa genotiplidir.'),
  (
    0,
    true,
    'sağlıklı ve heterozigot olduğu bilinen #',
    [(1, 1, 1)],
    '# Aa genotiplidir.',
  ),
  (
    0,
    true,
    'babası hasta olan sağlıklı #',
    [(1, 1, 1)],
    '# hasta babasından a aleli aldığından Aa genotiplidir.',
  ),
  (
    0,
    true,
    'anne ve babası sağlıklı, bir kardeşi hasta olan sağlıklı #',
    [(0, 1, 3), (1, 2, 3)],
    "#'ın anne ve babası sağlıklı, kardeşi hasta olduğundan anne ve babası Aa × Aa olur; sağlıklı #'ın Aa olma olasılığı 2/3 olur.",
  ),
  (
    0,
    true,
    'hastalık alelini taşımadığı bilinen sağlıklı #',
    [(0, 1, 1)],
    '# AA genotiplidir.',
  ),
  (
    0,
    false,
    'hasta olan #',
    [(2, 1, 1)],
    '# hasta olduğundan aa genotiplidir.',
  ),
  (
    0,
    false,
    'sağlıklı ve heterozigot olduğu bilinen #',
    [(1, 1, 1)],
    '# Aa genotiplidir.',
  ),
  (
    0,
    false,
    'babası hasta olan sağlıklı #',
    [(1, 1, 1)],
    '# hasta babasından a aleli aldığından Aa genotiplidir.',
  ),
  (
    0,
    false,
    'anne ve babası sağlıklı, bir kardeşi hasta olan sağlıklı #',
    [(0, 1, 3), (1, 2, 3)],
    "#'in anne ve babası sağlıklı, kardeşi hasta olduğundan anne ve babası Aa × Aa olur; sağlıklı #'in Aa olma olasılığı 2/3 olur.",
  ),
  (
    0,
    false,
    'hastalık alelini taşımadığı bilinen sağlıklı #',
    [(0, 1, 1)],
    '# AA genotiplidir.',
  ),
  (
    1,
    true,
    'sağlıklı olan #',
    [(0, 1, 1)],
    '# sağlıklı olduğundan aa genotiplidir.',
  ),
  (
    1,
    true,
    'hasta ve heterozigot olduğu bilinen #',
    [(1, 1, 1)],
    '# Aa genotiplidir.',
  ),
  (
    1,
    true,
    'annesi sağlıklı olan hasta #',
    [(1, 1, 1)],
    '# sağlıklı annesinden a aleli aldığından Aa genotiplidir.',
  ),
  (
    1,
    true,
    'anne ve babası hasta, bir kardeşi sağlıklı olan hasta #',
    [(1, 2, 3), (2, 1, 3)],
    "#'ın anne ve babası hasta, kardeşi sağlıklı olduğundan anne ve babası Aa × Aa olur; hasta #'ın Aa olma olasılığı 2/3, AA olma olasılığı 1/3 olur.",
  ),
  (
    1,
    false,
    'sağlıklı olan #',
    [(0, 1, 1)],
    '# sağlıklı olduğundan aa genotiplidir.',
  ),
  (
    1,
    false,
    'hasta ve heterozigot olduğu bilinen #',
    [(1, 1, 1)],
    '# Aa genotiplidir.',
  ),
  (
    1,
    false,
    'annesi sağlıklı olan hasta #',
    [(1, 1, 1)],
    '# sağlıklı annesinden a aleli aldığından Aa genotiplidir.',
  ),
  (
    1,
    false,
    'anne ve babası hasta, bir kardeşi sağlıklı olan hasta #',
    [(1, 2, 3), (2, 1, 3)],
    "#'in anne ve babası hasta, kardeşi sağlıklı olduğundan anne ve babası Aa × Aa olur; hasta #'in Aa olma olasılığı 2/3, AA olma olasılığı 1/3 olur.",
  ),
  (
    2,
    true,
    'sağlıklı olan #',
    [(0, 1, 1)],
    '# sağlıklıdır; X kromozomunda hastalık aleli yoktur.',
  ),
  (
    2,
    true,
    'hasta olan #',
    [(1, 1, 1)],
    '# hastadır; X kromozomunda hastalık aleli taşır.',
  ),
  (
    2,
    false,
    'taşıyıcı olmadığı bilinen sağlıklı #',
    [(0, 1, 1)],
    '# hastalık aleli taşımaz.',
  ),
  (
    2,
    false,
    'babası hasta olan sağlıklı #',
    [(1, 1, 1)],
    '# hasta babasından hastalık alelini aldığından taşıyıcıdır.',
  ),
  (
    2,
    false,
    'anne ve babası sağlıklı, erkek kardeşi hasta olan sağlıklı #',
    [(0, 1, 2), (1, 1, 2)],
    "#'in hasta erkek kardeşi alelini annesinden aldığından annesi taşıyıcıdır; sağlıklı #'in taşıyıcı olma olasılığı 1/2 olur.",
  ),
  (
    2,
    false,
    'hasta olan #',
    [(2, 1, 1)],
    '# hastadır; iki X kromozomunda da hastalık aleli taşır.',
  ),
];

const _kadinAd = 'Elif',
    _erkekAd = 'Kerem',
    _esKadin = 'Zeynep',
    _esErkek = 'Burak';

// Tek çocuk tanımları (üç kuşak ve tek çocuk soruları için).
const _tekTanimlar = <_Tanim>[
  (0, 0),
  (0, 1),
  (1, 0),
  (2, 0),
  (1, 1),
  (2, 1),
  (0, 2),
];

/// Üç kuşak sorusunun doğru yanıtı, iki hatalı yolun sonucu ve açıklama
/// terimleri: (doğru, belirsiz birey kesin heterozigot sayılırsa, belirsiz
/// olasılık 1/2 alınırsa, terimler).
(_K, _K, _K, List<String>) _ucKusakDeger(int h, int e, _Tanim t) {
  final (m, erkek, _, dag, _) = _hedefTanim[h];
  final (_, _, _, esDag, _) = _esTanim[e];
  var dogru = _K(0), kesinHet = _K(0), yariHet = _K(0);
  final terimler = <String>[];
  for (final (g1, p1, q1) in dag) {
    for (final (g2, p2, q2) in esDag) {
      final ga = erkek ? g2 : g1, gb = erkek ? g1 : g2;
      final o = _tanimOlasilik(m, t, ga, gb);
      dogru = dogru + _K(p1, q1) * _K(p2, q2) * o;
      if (!o.sifir) {
        terimler.add(
          [if (q1 > 1) _K(p1, q1).s, if (q2 > 1) _K(p2, q2).s, o.s].join(' · '),
        );
      }
      final k1 = q1 > 1 ? (g1 == 1 ? _K(1) : _K(0)) : _K(p1, q1);
      final k2 = q2 > 1 ? (g2 == 1 ? _K(1) : _K(0)) : _K(p2, q2);
      kesinHet = kesinHet + k1 * k2 * o;
      final y1 = q1 > 1 ? _yarim : _K(p1, q1);
      final y2 = q2 > 1 ? _yarim : _K(p2, q2);
      yariHet = yariHet + y1 * y2 * o;
    }
  }
  return (dogru, kesinHet, yariHet, terimler);
}

/// Üç kuşak sorusu: hedef birey ile eşinin doğacak çocuğu.
AdvancedItem _ucKusak(int h, int e, _Tanim t) {
  final (m, erkek, metin, _, ack) = _hedefTanim[h];
  final (_, _, esMetin, _, esAck) = _esTanim[e];
  final ad = erkek ? _erkekAd : _kadinAd;
  final esAd = erkek ? _esKadin : _esErkek;
  final (dogru, kesinHet, yariHet, terimler) = _ucKusakDeger(h, e, t);
  final yazi = _tanimYazi(m, t);
  final kok =
      '${_kalitimCumle[m]} ${metin.replaceAll('#', ad)} $ad, '
      '${esMetin.replaceAll('#', esAd)} ile evleniyor. Bu çiftin doğacak ilk çocuğunun '
      '$yazi olma olasılığı kaçtır?';
  return _olasilikSorusu(
    kok,
    dogru,
    [kesinHet, yariHet, _K(1) - dogru, dogru * _K(2), dogru * _yarim],
    '${ack.replaceAll('#', ad)} ${esAck.replaceAll('#', esAd)} Çocuğun $yazi olma olasılığı '
    '${terimler.length == 1 && terimler.first == dogru.s ? dogru.s : '${terimler.length == 1 ? terimler.first : terimler.map((x) => '($x)').join(' + ')} = ${dogru.s}'} '
    'olur.',
  );
}

/// Kalıtım biçimi olasılığı: anne ve baba hasta mı, çocuklar (erkek mi, hasta
/// mı), alel taşımadığı bilinen ebeveyn (0 yok, 1 anne, 2 baba).
(List<bool>, String) _bicimUygun(
  bool aH,
  bool bH,
  List<(bool, bool)> cocuklar,
  int bilinen,
) {
  final uygun = <bool>[];
  final notlar = <String>[];
  const ad = ['otozomal çekinik', 'otozomal baskın', "X'e bağlı çekinik"];
  for (var m = 0; m < 3; m++) {
    final ciftler = <(int, int)>[];
    for (var ga = 0; ga < 3; ga++) {
      for (var gb = 0; gb < (m == 2 ? 2 : 3); gb++) {
        if (_hastaMi(m, false, ga) != aH || _hastaMi(m, true, gb) != bH) {
          continue;
        }
        if (bilinen == 1 && ga != 0 || bilinen == 2 && gb != 0) continue;
        ciftler.add((ga, gb));
      }
    }
    bool olur((int, int) cf, (bool, bool) c) =>
        !_durumOlasilik(m, c.$1, c.$2 ? 0 : 1, cf.$1, cf.$2).sifir;
    final tanik = ciftler
        .where((cf) => cocuklar.every((c) => olur(cf, c)))
        .firstOrNull;
    uygun.add(tanik != null);
    if (tanik != null) {
      notlar.add(
        '${_bas(ad[m])} kalıtımda anne ${_ebeveynYazi(m, false, tanik.$1)}, baba '
        '${_ebeveynYazi(m, true, tanik.$2)} olursa bütün çocuklar açıklanır.',
      );
    } else {
      final k = [
        for (var j = 0; j < cocuklar.length; j++)
          if (ciftler.every((cf) => !olur(cf, cocuklar[j]))) j,
      ].firstOrNull;
      notlar.add(
        k == null
            ? '${_bas(ad[m])} kalıtımda anne ve babanın hiçbir genotip birleşimi bütün çocukları '
                  'birlikte açıklayamaz.'
            : '${_bas(ad[m])} kalıtımda ${_siraSifat4[k]} çocuk '
                  '(${cocuklar[k].$2 ? 'hasta' : 'sağlıklı'} bir ${cocuklar[k].$1 ? 'erkek' : 'kız'}) '
                  'bu anne ve babadan doğamaz.',
      );
    }
  }
  return (uygun, notlar.join(' '));
}

const _siraSifat4 = ['birinci', 'ikinci', 'üçüncü', 'dördüncü'];
const _sayiAdi = ['bir', 'iki', 'üç', 'dört'];
const _siraEk = ['birincisi', 'ikincisi', 'üçüncüsü', 'dördüncüsü'];

String _cocukListesi(List<(bool, bool)> c) {
  String t((bool, bool) x) =>
      '${x.$2 ? 'hasta' : 'sağlıklı'} bir ${x.$1 ? 'erkek' : 'kız'}';
  if (c.length == 1) {
    return 'tek çocukları ${t(c[0])}${c[0].$1 ? 'tir' : 'dır'}';
  }
  return '${_sayiAdi[c.length - 1]} çocuğundan '
      '${[for (var j = 0; j < c.length; j++) '${_siraEk[j]} ${t(c[j])}'].join(', ')}'
      '${c.last.$1 ? 'tir' : 'dır'}';
}

AdvancedItem _bicimSorusu(
  bool aH,
  bool bH,
  List<(bool, bool)> cocuklar,
  int bilinen,
  int i,
) {
  final (uygun, notlar) = _bicimUygun(aH, bH, cocuklar, bilinen);
  final anne = aH ? 'hasta' : 'sağlıklı', baba = bH ? 'hasta' : 'sağlıklı';
  return _oncullu(
    'Bir hastalığın tek bir genle kalıtıldığı ve mutasyon görülmediği biliniyor. ${_bas(anne)} bir '
    'anne ile $baba bir babanın ${_cocukListesi(cocuklar)}.'
    '${bilinen == 0 ? '' : ' ${bilinen == 1 ? 'Annenin' : 'Babanın'} hastalık alelini taşımadığı biliniyor.'}\n'
    '${_liste(const ['otozomal çekinik kalıtım', 'otozomal baskın kalıtım', "X'e bağlı çekinik kalıtım"])}'
    'Buna göre hastalık bu kalıtım biçimlerinden hangileriyle aktarılıyor olabilir?',
    uygun,
    i,
    notlar,
  );
}

/// Soyağacı ailesinin 5.000 vakası: biçimler karıştırılmış sırayla.
final _soyAdaylari = () {
  final tek = <AdvancedItem Function(int)>[];
  final ikili = <AdvancedItem Function(int)>[];
  final uclu = <AdvancedItem Function(int)>[];
  const dizim = <_Tanim>[(0, 0), (0, 1), (1, 0), (2, 0), (1, 1), (2, 1)];
  const sirasizCiftler = <(_Tanim, _Tanim)>[
    ((0, 0), (0, 1)),
    ((1, 0), (2, 0)),
    ((1, 0), (2, 1)),
    ((2, 0), (1, 1)),
    ((1, 1), (2, 1)),
    ((1, 0), (1, 1)),
    ((2, 0), (2, 1)),
  ];
  // Yanıtı 0, 1 ya da 1/2 olan sorular alınmaz: 1/2 yanıtta tümleyen olayı
  // hesaplayan öğrenci de doğru sonuca ulaşır.
  bool olasi(int c, List<_Tanim> d, [bool sirasiz = false]) {
    final (m, _, _, ga, gb, _) = _ciftler[c];
    var p = d.map((t) => _tanimOlasilik(m, t, ga, gb)).reduce((x, y) => x * y);
    if (sirasiz) p = p * _K(2);
    return !p.sifir && !p.bir && p != _yarim;
  }

  for (var c = 0; c < _ciftler.length; c++) {
    final (m, _, cocuklar, _, _, _) = _ciftler[c];
    for (final t in _tekTanimlar) {
      if (olasi(c, [t])) tek.add((i) => _ciftDizi(c, [t], false, i));
    }
    for (final erkek in [false, true]) {
      final (_, _, _, ga, gb, _) = _ciftler[c];
      final p = _durumOlasilik(m, erkek, 0, ga, gb);
      if (!p.bir && !p.sifir && p != _yarim) {
        tek.add((i) => _ciftKosullu(c, erkek));
      }
    }
    for (var k = 0; k < cocuklar.length; k++) {
      final (erkek, hasta) = cocuklar[k];
      final anlamli = switch (m) {
        0 => !hasta,
        1 => hasta,
        _ => !erkek && !hasta,
      };
      if (anlamli && _ciftMevcut(c, k).correct != _yarim.s) {
        tek.add((i) => _ciftMevcut(c, k));
      }
    }
    if (m < 2 && cocuklar.isNotEmpty) tek.add((i) => _ciftGenotip(c, i));
    for (final (a, b) in sirasizCiftler) {
      if (olasi(c, [a, b], true)) {
        ikili.add((i) => _ciftDizi(c, [a, b], true, i));
      }
    }
    for (final a in dizim) {
      for (final b in dizim) {
        if (olasi(c, [a, b])) ikili.add((i) => _ciftDizi(c, [a, b], false, i));
        for (final d in dizim) {
          if (olasi(c, [a, b, d])) {
            uclu.add((i) => _ciftDizi(c, [a, b, d], false, i));
          }
        }
      }
    }
  }
  final kusak = <AdvancedItem Function(int)>[];
  for (var h = 0; h < _hedefTanim.length; h++) {
    final (m, erkek, _, dag, _) = _hedefTanim[h];
    for (var e = 0; e < _esTanim.length; e++) {
      final (m2, esErkek, _, esDag, _) = _esTanim[e];
      if (m2 != m || esErkek == erkek) continue;
      for (final t in _tekTanimlar) {
        if (m == 2 && t.$2 == 2 && t.$1 != 0) continue;
        final (p, kesinHet, yariHet, _) = _ucKusakDeger(h, e, t);
        // Belirsiz bireyi kesin heterozigot sayan ya da otozomal kalıtımda 2/3
        // yerine 1/2 alan hatalı yolun yanıtı verdiği vakalar alınmaz.
        if (p.sifir || p.bir || p == _yarim || p == kesinHet) continue;
        if (m < 2 && p == yariHet) continue;
        kusak.add((i) => _ucKusak(h, e, t));
      }
    }
  }
  final bicim = <AdvancedItem Function(int)>[];
  for (final aH in [false, true]) {
    for (final bH in [false, true]) {
      for (var n = 1; n <= 4; n++) {
        for (var kod = 0; kod < 1 << (2 * n); kod++) {
          final cocuklar = [
            for (var j = 0; j < n; j++)
              ((kod >> (2 * j)) & 1 == 1, (kod >> (2 * j + 1)) & 1 == 1),
          ];
          for (var bilinen = 0; bilinen < 3; bilinen++) {
            if (bilinen == 1 && aH || bilinen == 2 && bH) continue;
            final (u, _) = _bicimUygun(aH, bH, cocuklar, bilinen);
            if (u.contains(true)) {
              bicim.add((i) => _bicimSorusu(aH, bH, cocuklar, bilinen, i));
            }
          }
        }
      }
    }
  }
  // Tek, ikili ve üç kuşak sorularının tamamı; kalan yer biçim ve üçlü
  // sorulardan yayılarak doldurulur.
  final secili = [...tek, ...ikili, ...kusak];
  final kalan = lmAileBoyu - secili.length;
  final bicimPay = kalan * 2 ~/ 5;
  final ucluPay = kalan - bicimPay;
  for (var j = 0; j < bicimPay; j++) {
    secili.add(_yay(bicim, j, bicimPay));
  }
  for (var j = 0; j < ucluPay; j++) {
    secili.add(_yay(uclu, j, ucluPay));
  }
  if (secili.length != lmAileBoyu) {
    throw StateError('Soyağacı: ${secili.length}');
  }
  return secili;
}();

final _soyagaci = lmSirali(
  'bl_soyagaci',
  'Soyağacında genotip ve çocuk olasılıkları',
  Topic.biology,
  Difficulty.hard,
  BloomLevel.analiz,
  (i) => _soyAdaylari[i * 2477 % lmAileBoyu](i),
  exam: ExamKind.tyt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── Sıralama yardımcıları ─────────────────────────────

final _dizilimOnbellek = <int, List<List<int>>>{};

/// 0 … k−1 sayılarının bütün dizilimleri (sözlük sırasıyla).
List<List<int>> _dizilimler(int k) => _dizilimOnbellek[k] ??= () {
  final out = <List<int>>[];
  void kur(List<int> on, List<int> kalan) {
    if (kalan.isEmpty) {
      out.add(on);
      return;
    }
    for (final x in kalan) {
      kur([...on, x], [...kalan.where((y) => y != x)]);
    }
  }

  kur([], [for (var j = 0; j < k; j++) j]);
  return out;
}();

/// Sıralama sorusu: [dogru] ögelerin doğru sırasıdır. Kökte ögeler karışık
/// numaralanır; yanıt ve çeldiriciler numara dizileridir. Doğru sıra ile
/// listelenen sıra hiçbir zaman aynı olmaz.
AdvancedItem _siralama(
  String giris,
  List<String> dogru,
  String soru,
  int i,
  String aciklama,
) {
  final k = dogru.length;
  final tum = _dizilimler(k);
  // Listeleme dizilimi: birim ve ters dizilim dışında.
  final uygun = [
    for (final p in tum)
      if (!_ayni(p, tum.first) && !_ayni(p, tum.last)) p,
  ];
  final p = uygun[i % uygun.length]; // p[t]: t. sıradaki gösterilen öge
  final yer = List.filled(k, 0);
  for (var t = 0; t < k; t++) {
    yer[p[t]] = t;
  }
  String yaz(List<int> sira) =>
      [for (final r in sira) _romen[yer[r]]].join(' → ');
  final dogruSira = [for (var r = 0; r < k; r++) r];
  List<int> takas(int a, int b) => [
    for (var r = 0; r < k; r++) r == a ? b : (r == b ? a : r),
  ];
  final adaylar = <List<int>>[
    dogruSira.reversed.toList(),
    takas(i % (k - 1), i % (k - 1) + 1),
    takas((i + 1) % (k - 1), (i + 1) % (k - 1) + 1),
    [...dogruSira.sublist(1), 0],
    takas(0, k - 1),
    for (final q in tum) q,
  ];
  return secenekli(
    '$giris${_liste([for (var t = 0; t < k; t++) dogru[p[t]]])}$soru',
    yaz(dogruSira),
    adaylar.map(yaz),
    '$aciklama Numaralarla doğru sıra ${yaz(dogruSira)} olur.',
  );
}

bool _ayni(List<int> a, List<int> b) {
  for (var j = 0; j < a.length; j++) {
    if (a[j] != b[j]) return false;
  }
  return true;
}

// ───────────────────────────── 8. Sindirim sistemi ─────────────────────────────

// (enzim, salgılandığı yer, etki ettiği madde, etki gösterdiği yer, ortam
//  (0 asidik, 1 bazik, null belirtilmez), etkin olmayan öncül hâlinde mi
//  salgılanır (null: kaynaklarda belirtilmez))
const _enzimler = <(String, String, String, String, int?, bool?)>[
  ('tükürük amilazı', 'tükürük bezleri', 'nişasta', 'ağız', null, false),
  ('pepsin', 'mide', 'protein', 'mide', 0, true),
  ('pankreas amilazı', 'pankreas', 'nişasta', 'ince bağırsak', 1, false),
  ('tripsin', 'pankreas', 'protein', 'ince bağırsak', 1, true),
  ('kimotripsin', 'pankreas', 'protein', 'ince bağırsak', 1, true),
  ('pankreas lipazı', 'pankreas', 'yağ', 'ince bağırsak', 1, null),
  ('nükleaz', 'pankreas', 'nükleik asit', 'ince bağırsak', 1, null),
  ('maltaz', 'ince bağırsak', 'maltoz', 'ince bağırsak', 1, false),
  ('sakkaraz', 'ince bağırsak', 'sakkaroz', 'ince bağırsak', 1, false),
  ('laktaz', 'ince bağırsak', 'laktoz', 'ince bağırsak', 1, false),
  ('dipeptidaz', 'ince bağırsak', 'dipeptit', 'ince bağırsak', 1, false),
  ('enterokinaz', 'ince bağırsak', 'tripsinojen', 'ince bağırsak', 1, false),
];

const _karbonhidrat = {'nişasta', 'maltoz', 'sakkaroz', 'laktoz'};

final _enzimSorulari =
    <(String, bool? Function((String, String, String, String, int?, bool?)))>[
      (
        'Bu enzimlerden hangileri pankreastan salgılanır?',
        (e) => e.$2 == 'pankreas',
      ),
      (
        'Bu enzimlerden hangileri ince bağırsak çeperindeki bezlerden salgılanır?',
        (e) => e.$2 == 'ince bağırsak',
      ),
      (
        'Bu enzimlerden hangileri ince bağırsakta etkinlik gösterir?',
        (e) => e.$4 == 'ince bağırsak',
      ),
      (
        'Bu enzimlerden hangileri proteinlerin ya da peptitlerin sindiriminde görev alır?',
        (e) => e.$1 == 'enterokinaz'
            ? null
            : (e.$3 == 'protein' || e.$3 == 'dipeptit'),
      ),
      (
        'Bu enzimlerden hangileri karbonhidratların sindiriminde görev alır?',
        (e) => _karbonhidrat.contains(e.$3),
      ),
      (
        'Bu enzimlerden hangileri disakkaritleri monosakkaritlere parçalar?',
        (e) => {'maltoz', 'sakkaroz', 'laktoz'}.contains(e.$3),
      ),
      (
        'Bu enzimlerden hangileri asidik ortamda etkinlik gösterir?',
        (e) => e.$5 == 0,
      ),
      (
        'Bu enzimlerden hangileri bazik ortamda etkinlik gösterir?',
        (e) => e.$5 == null ? null : e.$5 == 1,
      ),
      (
        'Bu enzimlerden hangileri etkin olmayan öncül hâlinde salgılanıp sonradan etkinleşir?',
        (e) => e.$6,
      ),
    ];

final _enzimAdaylari = [
  ..._adaylar(
    _enzimler.length,
    _enzimSorulari.length,
    (q, k) => _enzimSorulari[q].$2(_enzimler[k]),
    sinif: (k) => _enzimler[k].$3,
  ),
  for (final (a, b, c, _) in _adaylar(
    _enzimler.length,
    0,
    (q, k) => null,
    sinif: (k) => _enzimler[k].$2,
  ))
    (a, b, c, -2),
];

// (konu, ifade, doğru mu, yanlışsa doğrusu)
const _sindirimIfade = <(int, String, bool, String)>[
  (0, 'Safra karaciğerde üretilir ve safra kesesinde depolanır.', true, ''),
  (0, 'Safra pankreasta üretilir.', false, 'Safra karaciğerde üretilir.'),
  (1, 'Safra sindirim enzimi içermez.', true, ''),
  (
    1,
    'Safra, yağları kimyasal olarak yağ asidi ve gliserole parçalar.',
    false,
    'Safra yağları yalnız küçük damlacıklara ayırır (fiziksel sindirim); kimyasal sindirimi '
        'lipaz yapar.',
  ),
  (
    1,
    'Safra, yağları küçük damlacıklara ayırarak lipazın etki yüzeyini artırır.',
    true,
    '',
  ),
  (
    2,
    'Safra ve pankreas öz suyu ince bağırsağın onikiparmak bağırsağı bölümüne dökülür.',
    true,
    '',
  ),
  (
    3,
    'Midedeki hidroklorik asit, pepsinojeni etkin pepsine dönüştürür.',
    true,
    '',
  ),
  (4, 'Proteinlerin kimyasal sindirimi midede başlar.', true, ''),
  (
    4,
    'Proteinlerin kimyasal sindirimi ağızda başlar.',
    false,
    'Proteinlerin kimyasal sindirimi midede başlar.',
  ),
  (5, 'Karbonhidratların kimyasal sindirimi ağızda başlar.', true, ''),
  (
    5,
    'Nişastanın kimyasal sindirimi midede başlar.',
    false,
    'Nişastanın kimyasal sindirimi ağızda başlar.',
  ),
  (
    6,
    'Tripsin, pankreastan etkin olmayan tripsinojen hâlinde salgılanır.',
    true,
    '',
  ),
  (
    6,
    'Tripsin, pankreastan etkin hâlde salgılanır.',
    false,
    'Tripsin, pankreastan tripsinojen hâlinde salgılanır ve ince bağırsakta etkinleşir.',
  ),
  (
    7,
    'Kalın bağırsakta sindirim enzimleri salgılanır.',
    false,
    'Kalın bağırsakta sindirim enzimi salgılanmaz.',
  ),
  (
    7,
    'Kalın bağırsakta su ve bazı minerallerin emilimi gerçekleşir.',
    true,
    '',
  ),
  (8, 'Sindirilmiş besinlerin büyük bölümü ince bağırsakta emilir.', true, ''),
  (
    8,
    'Mide, ince bağırsaktan daha fazla besin emer.',
    false,
    'Besinlerin büyük bölümü ince bağırsakta emilir.',
  ),
  (
    9,
    'Nükleik asitlerin kimyasal sindirimi ince bağırsakta gerçekleşir.',
    true,
    '',
  ),
  (
    10,
    'Pepsin bazik ortamda en iyi çalışır.',
    false,
    'Pepsin midenin asidik ortamında çalışır.',
  ),
  (
    11,
    'Mide öz suyu nişastayı sindiren amilaz enzimi içerir.',
    false,
    'Mide öz suyunda amilaz bulunmaz; nişasta ağızda ve ince bağırsakta sindirilir.',
  ),
  (12, 'Yemek borusunda sindirim enzimi salgılanmaz.', true, ''),
  (
    13,
    'Safra kesesi sindirim enzimi salgılar.',
    false,
    'Safra kesesi safrayı depolar; enzim salgılamaz.',
  ),
  (14, 'İnce bağırsaktaki villuslar emilim yüzeyini artırır.', true, ''),
  (
    14,
    'Glikoz ve amino asitler villuslardaki kan kılcallarına geçer.',
    true,
    '',
  ),
  (
    15,
    'Selüloz, insanın sindirim enzimleriyle glikoza parçalanır.',
    false,
    'İnsanda selülozu sindiren enzim bulunmaz.',
  ),
  (
    16,
    'Mide çeperini örten mukus, midenin kendi salgılarıyla sindirilmesini önler.',
    true,
    '',
  ),
  (
    17,
    'Kalın bağırsakta yaşayan bakteriler K vitamini ve bazı B vitaminlerini üretir.',
    true,
    '',
  ),
  (
    18,
    'Laktaz enzimi pankreastan salgılanır.',
    false,
    'Laktaz ince bağırsak çeperindeki bezlerden salgılanır.',
  ),
  (
    19,
    'Pankreas öz suyu asidik özelliktedir.',
    false,
    'Pankreas öz suyu bikarbonat içerdiğinden baziktir.',
  ),
  (
    19,
    'Pankreas öz suyundaki bikarbonat, mideden gelen asidik besin lapasını nötrleştirir.',
    true,
    '',
  ),
];

// Konuları farklı üçlüler; 0: doğru olanlar, 1: yanlış olanlar sorulur.
final _sindirimUcluleri = [
  for (final (a, b, c, q) in _adaylar(
    _sindirimIfade.length,
    2,
    (q, k) => q == 0 ? _sindirimIfade[k].$3 : !_sindirimIfade[k].$3,
    uygun: (a, b, c) =>
        {
          _sindirimIfade[a].$1,
          _sindirimIfade[b].$1,
          _sindirimIfade[c].$1,
        }.length ==
        3,
  ))
    (a, b, c, q),
];

String _enzimCumle((String, String, String, String, int?, bool?) e) {
  final (ad, yer, madde, etki, ph, _) = e;
  final kaynak = switch (yer) {
    'tükürük bezleri' => 'tükürük bezlerinden',
    'mide' => 'mideden',
    'pankreas' => 'pankreastan',
    _ => 'ince bağırsak çeperinden',
  };
  final yerde = switch (etki) {
    'ağız' => 'ağızda',
    'mide' => 'midede',
    _ => 'ince bağırsakta',
  };
  final ortam = ph == null ? '' : ', ${ph == 0 ? 'asidik' : 'bazik'} ortamda';
  return '${_bas(ad)} $kaynak salgılanır; $yerde$ortam $madde üzerine etki eder.';
}

final _sindirim = lmSirali(
  'bl_sindirim',
  'Sindirim enzimleri, safra ve sindirim olayları',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) {
    // 10 vakalık döngü: 3 enzim sorusu, 7 ifade sorusu.
    final r = i % 10, tur = i ~/ 10;
    final d = ucluDizilimler[(tur + r) % 6];
    if (r < 3) {
      final jj = tur * 3 + r, nn = lmAileBoyu * 3 ~/ 10;
      final (a, b, c, q) = _yay(_enzimAdaylari, jj, nn);
      final x = [
        for (final t in d) _enzimler[[a, b, c][t]],
      ];
      final liste = _liste([for (final e in x) e.$1]);
      final aciklama = x.map(_enzimCumle).join(' ');
      if (q == -1) {
        return _esle(
          '${liste}Bu enzimlerin etki ettiği maddeler sırasıyla hangi seçenekte doğru '
          'verilmiştir?',
          [for (final e in x) e.$3],
          jj,
          aciklama,
        );
      }
      if (q == -2) {
        return _esle(
          '${liste}Bu enzimlerin salgılandığı yerler sırasıyla hangi seçenekte doğru '
          'verilmiştir?',
          [for (final e in x) e.$2],
          jj,
          aciklama,
        );
      }
      final (soru, deger) = _enzimSorulari[q];
      return _oncullu(
        '$liste$soru',
        [for (final e in x) deger(e)!],
        jj,
        aciklama,
      );
    }
    final jj = tur * 7 + r - 3, nn = lmAileBoyu * 7 ~/ 10;
    final (a, b, c, q) = _yay(_sindirimUcluleri, jj, nn);
    final x = [
      for (final t in d) _sindirimIfade[[a, b, c][t]],
    ];
    final dogru = [
      for (var t = 0; t < 3; t++)
        if (x[t].$3) _romen[t],
    ];
    final yanlis = [
      for (var t = 0; t < 3; t++)
        if (!x[t].$3) _romen[t],
    ];
    return _oncullu(
      '${_liste([for (final e in x) e.$2])}Sindirim sistemiyle ilgili bu ifadelerden hangileri '
      '${q == 0 ? 'doğrudur' : 'yanlıştır'}?',
      [for (final e in x) q == 0 ? e.$3 : !e.$3],
      jj,
      [
        if (dogru.isNotEmpty) '${_ve(dogru)} doğrudur.',
        if (yanlis.isNotEmpty) '${_ve(yanlis)} yanlıştır.',
        for (final e in x)
          if (!e.$3) e.$4,
      ].join(' '),
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 9. Boşaltım sistemi ─────────────────────────────

const _evreAdi = ['süzülme', 'geri emilim', 'salgılama'];

// (olay, evre (null: sağlıklı insanda gerçekleşmez), ATP harcanır mı)
const _bosaltimOlay = <(String, int?, bool?)>[
  ('Suyun glomerulustan Bowman kapsülüne geçmesi', 0, false),
  ('Glikozun glomerulustan Bowman kapsülüne geçmesi', 0, false),
  ('Amino asitlerin glomerulustan Bowman kapsülüne geçmesi', 0, false),
  ('Ürenin glomerulustan Bowman kapsülüne geçmesi', 0, false),
  ('Sodyum iyonlarının glomerulustan Bowman kapsülüne geçmesi', 0, false),
  ('Ürik asidin glomerulustan Bowman kapsülüne geçmesi', 0, false),
  ('Potasyum iyonlarının glomerulustan Bowman kapsülüne geçmesi', 0, false),
  ('Glikozun böbrek kanalcığından kılcal damarlara geçmesi', 1, true),
  ('Amino asitlerin böbrek kanalcığından kılcal damarlara geçmesi', 1, true),
  ('Suyun böbrek kanalcığından kılcal damarlara geçmesi', 1, false),
  ('Sodyum iyonlarının böbrek kanalcığından kılcal damarlara geçmesi', 1, true),
  (
    'Bikarbonat iyonlarının böbrek kanalcığından kılcal damarlara geçmesi',
    1,
    null,
  ),
  (
    'Hidrojen iyonlarının kılcal damarlardan böbrek kanalcığına aktarılması',
    2,
    true,
  ),
  (
    'Potasyum iyonlarının kılcal damarlardan böbrek kanalcığına aktarılması',
    2,
    null,
  ),
  ('Amonyağın kılcal damarlardan böbrek kanalcığına aktarılması', 2, null),
  (
    'Penisilin gibi bazı ilaçların kılcal damarlardan böbrek kanalcığına aktarılması',
    2,
    null,
  ),
  ('Alyuvarların glomerulustan Bowman kapsülüne geçmesi', null, null),
  ('Akyuvarların glomerulustan Bowman kapsülüne geçmesi', null, null),
  ('Kan pulcuklarının glomerulustan Bowman kapsülüne geçmesi', null, null),
  ('Glikozun idrarla vücut dışına atılması', null, null),
];

const _bosaltimSorulari = [
  'Bu olaylardan hangileri idrar oluşumunun süzülme evresinde gerçekleşir?',
  'Bu olaylardan hangileri idrar oluşumunun geri emilim evresinde gerçekleşir?',
  'Bu olaylardan hangileri idrar oluşumunun salgılama evresinde gerçekleşir?',
  'Bu olaylardan hangilerinde ATP harcanır?',
  'Bu olaylardan hangileri sağlıklı bir insanın böbreklerinde gerçekleşir?',
  'Bu olaylardan hangilerinde madde kandan nefron boşluğuna geçer?',
];

bool? _bosaltimDeger(int q, int k) {
  final (_, evre, atp) = _bosaltimOlay[k];
  if (q == 4) return evre != null;
  if (evre == null) return null;
  return switch (q) {
    0 || 1 || 2 => evre == q,
    3 => atp,
    _ => evre != 1,
  };
}

final _bosaltimAdaylari = _adaylar(
  _bosaltimOlay.length,
  _bosaltimSorulari.length,
  _bosaltimDeger,
  sinif: (k) =>
      _bosaltimOlay[k].$2 == null ? null : _evreAdi[_bosaltimOlay[k].$2!],
);

String _bosaltimCumle((String, int?, bool?) e) {
  final (olay, evre, atp) = e;
  if (evre == null) {
    return olay.startsWith('Glikozun')
        ? '${_bas(olay)} sağlıklı bir insanda gerçekleşmez; glikozun tamamı geri emilir.'
        : '${_bas(olay)} sağlıklı bir insanda gerçekleşmez; kan hücreleri süzülmez.';
  }
  final atpYazi = atp == null
      ? ''
      : (atp
            ? '; ATP harcanır'
            : (evre == 0
                  ? '; kan basıncıyla olur, ATP harcanmaz'
                  : '; ozmozla olur, ATP harcanmaz'));
  return '${_bas(olay)} ${_evreAdi[evre]} olayıdır$atpYazi.';
}

// Nefron bölümleri ve böbreği etkileyen hormonlar: her bilgi tek yapıya aittir.
const _nefronGorev = <(String, String)>[
  (
    'Kan basıncının etkisiyle süzülmenin gerçekleştiği kılcal damar yumağıdır.',
    'glomerulus',
  ),
  (
    'Glomerulustan süzülen sıvıyı toplayan çift katlı çanak biçimli yapıdır.',
    'Bowman kapsülü',
  ),
  (
    'Süzüntüdeki glikoz ve amino asitlerin tamamına yakınının geri emildiği bölümdür.',
    'proksimal tüp',
  ),
  (
    'Böbreğin öz bölgesine uzanan, su ve tuz geri emilimiyle öz bölgede derişim farkı '
        'oluşturan U biçimli bölümdür.',
    'Henle kulpu',
  ),
  (
    'Aldosteron etkisiyle sodyum iyonlarının geri emildiği, toplama kanalına açılan kıvrımlı '
        'bölümdür.',
    'distal tüp',
  ),
  (
    'Birçok nefrondan gelen idrarı toplayıp böbrek havuzuna ileten kanaldır.',
    'toplama kanalı',
  ),
  ('Böbrekte oluşan idrarı idrar kesesine taşıyan borudur.', 'üreter'),
  ('İdrarın biriktirildiği kaslı kesedir.', 'idrar kesesi'),
  ('İdrarın vücut dışına atıldığı kanaldır.', 'üretra'),
  (
    'Toplama kanallarından gelen idrarın toplandığı, üretere açılan boşluktur.',
    'böbrek havuzu',
  ),
  (
    'Glomerulusa kan getiren, böbrek atardamarından ayrılan damarcıktır.',
    'getirici damarcık',
  ),
  (
    'Distal tüp ve toplama kanallarında suyun geri emilimini artıran, hipofizin arka lobundan '
        'kana verilen hormondur.',
    'ADH',
  ),
  (
    'Böbreklerde sodyum iyonlarının geri emilimini artıran, böbrek üstü bezinin kabuk '
        'bölgesinden salgılanan hormondur.',
    'aldosteron',
  ),
  (
    'Böbreklerden kalsiyum geri emilimini artıran, paratiroit bezinden salgılanan hormondur.',
    'parathormon',
  ),
];

// (konu, ifade, doğru mu, yanlışsa doğrusu)
const _bosaltimIfade = <(int, String, bool, String)>[
  (0, 'Süzülme glomerulustan Bowman kapsülüne doğru gerçekleşir.', true, ''),
  (
    0,
    'Süzülme Bowman kapsülünden glomerulusa doğru gerçekleşir.',
    false,
    'Süzülme glomerulustan Bowman kapsülüne doğrudur.',
  ),
  (
    1,
    'Süzülme kan basıncının etkisiyle gerçekleşir ve ATP harcanmaz.',
    true,
    '',
  ),
  (
    2,
    'Sağlıklı bir insanda kan hücreleri ve büyük proteinler süzülmez.',
    true,
    '',
  ),
  (
    3,
    'Sağlıklı bir insanın idrarında glikoz bulunur.',
    false,
    'Sağlıklı bir insanda glikozun tamamı geri emilir; idrarda glikoz bulunmaz.',
  ),
  (3, 'Glikozun tamamına yakını proksimal tüpte geri emilir.', true, ''),
  (
    4,
    'Geri emilimde maddeler böbrek kanalcığından kılcal damarlara geçer.',
    true,
    '',
  ),
  (
    4,
    'Geri emilimde maddeler kılcal damarlardan böbrek kanalcığına geçer.',
    false,
    'Geri emilimde maddeler kanalcıktan kılcal damarlara geçer.',
  ),
  (
    5,
    'Salgılamada bazı maddeler kılcal damarlardan böbrek kanalcığına aktarılır.',
    true,
    '',
  ),
  (
    6,
    'Hidrojen iyonlarının salgılanması kanın pH değerinin düzenlenmesine katkı sağlar.',
    true,
    '',
  ),
  (
    7,
    'ADH, distal tüp ve toplama kanallarında suyun geri emilimini artırır.',
    true,
    '',
  ),
  (
    7,
    'ADH salgısı arttığında idrar miktarı artar.',
    false,
    'ADH suyun geri emilimini artırdığından idrar miktarı azalır.',
  ),
  (
    8,
    'ADH hipotalamusta üretilir ve hipofizin arka lobundan kana verilir.',
    true,
    '',
  ),
  (9, 'Aldosteron sodyum iyonlarının geri emilimini artırır.', true, ''),
  (
    10,
    'Aldosteron hipofizin arka lobundan salgılanır.',
    false,
    'Aldosteron böbrek üstü bezinin kabuk bölgesinden salgılanır.',
  ),
  (
    10,
    'Aldosteron böbrek üstü bezinin kabuk bölgesinden salgılanır.',
    true,
    '',
  ),
  (11, 'Bowman kapsülleri böbreğin kabuk bölgesinde bulunur.', true, ''),
  (
    11,
    'Henle kulpları böbreğin kabuk bölgesinde bulunur.',
    false,
    'Henle kulpları böbreğin öz bölgesine uzanır.',
  ),
  (12, 'Toplama kanalları idrarı böbrek havuzuna taşır.', true, ''),
  (
    13,
    'Suyun geri emilimi aktif taşımayla gerçekleşir.',
    false,
    'Suyun geri emilimi ozmozla gerçekleşir.',
  ),
  (13, 'Suyun geri emilimi ozmozla gerçekleşir.', true, ''),
  (
    14,
    'İdrar kesesinde suyun geri emilimi gerçekleşir.',
    false,
    'İdrar kesesi idrarı biriktirir; geri emilim nefron kanalcıklarında olur.',
  ),
  (15, 'Üreter idrarı böbrekten idrar kesesine taşır.', true, ''),
  (
    15,
    'Üretra idrarı böbrekten idrar kesesine taşır.',
    false,
    'İdrarı böbrekten idrar kesesine üreter taşır; üretra idrarı dışarı atar.',
  ),
  (
    16,
    'Üre böbreklerde amonyaktan üretilir.',
    false,
    'Üre karaciğerde amonyaktan üretilir; böbrekler üreyi kandan süzerek atar.',
  ),
  (16, 'Üre karaciğerde amonyaktan üretilir ve böbreklerle atılır.', true, ''),
];

final _bosaltimUcluleri = [
  for (final (a, b, c, q) in _adaylar(
    _bosaltimIfade.length,
    2,
    (q, k) => q == 0 ? _bosaltimIfade[k].$3 : !_bosaltimIfade[k].$3,
    uygun: (a, b, c) =>
        {
          _bosaltimIfade[a].$1,
          _bosaltimIfade[b].$1,
          _bosaltimIfade[c].$1,
        }.length ==
        3,
  ))
    (a, b, c, q),
];

const _idrarYolu = [
  'Bowman kapsülü',
  'proksimal tüp',
  'Henle kulpu',
  'distal tüp',
  'toplama kanalı',
  'böbrek havuzu',
  'üreter',
  'idrar kesesi',
  'üretra',
];

// Sıralama soruları: 3–5 yapılı alt diziler.
final _idrarAltDizileri = [
  for (var k = 3; k <= 5; k++)
    for (final s in _altKumeler(_idrarYolu.length, k)) s,
];

/// 0 … n−1 içinden k elemanlı artan alt diziler.
List<List<int>> _altKumeler(int n, int k) {
  final out = <List<int>>[];
  void kur(int bas, List<int> on) {
    if (on.length == k) {
      out.add(on);
      return;
    }
    for (var x = bas; x < n; x++) {
      kur(x + 1, [...on, x]);
    }
  }

  kur(0, []);
  return out;
}

final _bosaltim = lmSirali(
  'bl_bosaltim',
  'Nefron ve idrar oluşumu: süzülme, geri emilim, salgılama',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    // 20 vakalık döngü: 11 olay, 7 ifade, 1 sıralama, 1 nefron bilgisi.
    final r = i % 20, tur = i ~/ 20;
    if (r < 11) {
      final j = tur * 11 + r;
      final (a, b, c, q) = _yay(_bosaltimAdaylari, j, 250 * 11);
      final d = ucluDizilimler[j % 6];
      final x = [
        for (final t in d) _bosaltimOlay[[a, b, c][t]],
      ];
      final liste = _liste([for (final e in x) e.$1]);
      final aciklama = x.map(_bosaltimCumle).join(' ');
      if (q < 0) {
        return _esle(
          '${liste}Bu olayların ait olduğu idrar oluşumu evreleri sırasıyla hangi seçenekte '
          'doğru verilmiştir?',
          [for (final e in x) _evreAdi[e.$2!]],
          j,
          aciklama,
        );
      }
      return _oncullu(
        '$liste${_bosaltimSorulari[q]}',
        [
          for (final t in d) _bosaltimDeger(q, [a, b, c][t])!,
        ],
        j,
        aciklama,
      );
    }
    if (r < 18) {
      final j = tur * 7 + r - 11;
      final (a, b, c, q) = _yay(_bosaltimUcluleri, j, 250 * 7);
      final d = ucluDizilimler[j % 6];
      final x = [
        for (final t in d) _bosaltimIfade[[a, b, c][t]],
      ];
      final dogru = [
        for (var t = 0; t < 3; t++)
          if (x[t].$3) _romen[t],
      ];
      final yanlis = [
        for (var t = 0; t < 3; t++)
          if (!x[t].$3) _romen[t],
      ];
      return _oncullu(
        '${_liste([for (final e in x) e.$2])}Boşaltım sistemiyle ilgili bu ifadelerden '
        'hangileri ${q == 0 ? 'doğrudur' : 'yanlıştır'}?',
        [for (final e in x) q == 0 ? e.$3 : !e.$3],
        j,
        [
          if (dogru.isNotEmpty) '${_ve(dogru)} doğrudur.',
          if (yanlis.isNotEmpty) '${_ve(yanlis)} yanlıştır.',
          for (final e in x)
            if (!e.$3) e.$4,
        ].join(' '),
      );
    }
    if (r == 18) {
      final s = _yay(_idrarAltDizileri, tur, 250);
      final yapilar = [for (final k in s) _idrarYolu[k]];
      return _siralama(
        '',
        yapilar,
        'Bowman kapsülüne süzülen sıvı, idrar olarak vücut dışına atılıncaya kadar bu '
            'yapılardan hangi sırayla geçer?',
        tur,
        'Süzüntünün yolu: ${_idrarYolu.join(' → ')}. Buna göre verilen yapıların sırası '
            '${yapilar.join(' → ')} olur.',
      );
    }
    return _olgu(
      tur,
      sira: tur * 364 ~/ 250,
      _nefronGorev,
      eslestirme:
          'Bu bilgilerin ait olduğu yapılar ya da hormonlar sırasıyla hangi seçenekte '
          'doğru verilmiştir?',
      oncul: (y) => 'Bu bilgilerden hangileri “$y” için doğrudur?',
      aciklama: (x) =>
          'Birinci bilgi ${x[0].$2}, ikinci bilgi ${x[1].$2}, üçüncü bilgi '
          '${x[2].$2} için doğrudur.',
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 10. Sinir sistemi ─────────────────────────────

// Her bilgi yalnız bir yapı için doğrudur.
const _sinirGorev = <(String, String)>[
  (
    'Düşünme, öğrenme ve hafıza (bellek) gibi zihinsel etkinliklerin merkezidir.',
    'uç beyin',
  ),
  ('İstemli (isteğe bağlı) hareketlerin başlatıldığı merkezdir.', 'uç beyin'),
  (
    'Görme, işitme ve tat gibi duyuların bilinç düzeyinde algılandığı bölümdür.',
    'uç beyin',
  ),
  (
    'Kıvrımlı yüzeyi gri maddeden oluşan beyin kabuğunu taşıyan, en büyük beyin bölümüdür.',
    'uç beyin',
  ),
  (
    'Koku dışındaki duyu impulslarını beyin kabuğundaki ilgili merkezlere ileten aktarma '
        'merkezidir.',
    'talamus',
  ),
  ('Vücut sıcaklığının düzenlenmesinde merkez görevi yapar.', 'hipotalamus'),
  ('Açlık, tokluk ve susama duygularının merkezidir.', 'hipotalamus'),
  (
    'Salgıladığı hormonlarla hipofiz bezinin çalışmasını denetler.',
    'hipotalamus',
  ),
  ('Görme ve işitmeyle ilgili bazı reflekslerin merkezidir.', 'orta beyin'),
  (
    'Göz bebeğinin ışık şiddetine göre daralıp genişlemesi refleksinin merkezidir.',
    'orta beyin',
  ),
  ('Vücudun dengesinin korunmasını sağlar.', 'beyincik'),
  (
    'İstemli hareketlerin düzenli ve uyumlu (koordineli) yapılmasını sağlar.',
    'beyincik',
  ),
  (
    'Beyin kabuğu ile beyincik arasında köprü görevi yapar; solunumun düzenlenmesine yardım '
        'eder.',
    'pons (köprü)',
  ),
  (
    'Kalp atışı, soluk alıp verme ve kan basıncını düzenleyen merkezdir.',
    'omurilik soğanı',
  ),
  (
    'Yutkunma, öksürme, hapşırma ve kusma reflekslerinin merkezidir.',
    'omurilik soğanı',
  ),
  ('Diz kapağı refleksi gibi basit reflekslerin merkezidir.', 'omurilik'),
  (
    'Omurların oluşturduğu kanal içinde bulunur; vücut ile beyin arasında uyartı iletimini '
        'sağlar.',
    'omurilik',
  ),
  (
    'Uyartıları alarak hücre gövdesine ileten, kısa ve dallanmış uzantılardır.',
    'dendrit',
  ),
  (
    'Uyartıyı hücre gövdesinden uzaklaştırıp akson uçlarına ileten uzun uzantıdır.',
    'akson',
  ),
  (
    'Aksonu saran ve uyartının iletim hızını artıran yalıtkan örtüdür.',
    'miyelin kılıf',
  ),
  (
    'Miyelin kılıfın kesintiye uğradığı, uyartının atlayarak iletilmesini sağlayan bölgelerdir.',
    'Ranvier boğumları',
  ),
  (
    'Çekirdek ve organellerin bulunduğu, nöronun metabolik merkezi olan kısımdır.',
    'hücre gövdesi',
  ),
  (
    'Akson ucunda bulunan ve sinaptik boşluğa nörotransmitter salgılayan şişkinliklerdir.',
    'sinaptik düğmecikler',
  ),
  (
    'Çevresel sinir sisteminde aksonun etrafında miyelin kılıfı oluşturan hücrelerdir.',
    'Schwann hücreleri',
  ),
  (
    'Uyartıyı duyu organlarındaki almaçlardan merkezî sinir sistemine taşır.',
    'duyu nöronu',
  ),
  (
    'Merkezî sinir sisteminden aldığı emri kaslara ya da bezlere iletir.',
    'motor nöron',
  ),
  (
    'Merkezî sinir sistemi içinde bulunur; duyu nöronu ile motor nöron arasında bağlantı kurar.',
    'ara nöron',
  ),
  (
    'Refleks yayında uyartıyı ilk olarak algılayan yapıdır.',
    'almaç (reseptör)',
  ),
  (
    'Refleks yayında motor nöronla gelen emri yerine getiren kas ya da bezdir.',
    'tepki organı (efektör)',
  ),
  (
    'Elini sıcak bir cisimden çeken bir kişide uyartıyı deriden omuriliğe getiren nörondur.',
    'duyu nöronu',
  ),
  (
    'Elini sıcak bir cisimden çeken bir kişide emri omurilikten kol kaslarına götüren nörondur.',
    'motor nöron',
  ),
  (
    'Elini sıcak bir cisimden çeken bir kişide omurilikte duyu ve motor nöronları birbirine '
        'bağlayan nörondur.',
    'ara nöron',
  ),
  (
    'Sinaptik boşluğa salınarak uyartının bir nörondan diğerine geçmesini sağlayan kimyasal '
        'maddedir.',
    'nörotransmitter',
  ),
  ('Beyni ve omuriliği saran, koruyan üç katlı zardır.', 'beyin zarları'),
  (
    'İskelet kaslarını ve istemli hareketleri denetleyen çevresel sinir sistemi bölümüdür.',
    'somatik sinir sistemi',
  ),
  (
    'Kalbin, düz kasların ve bezlerin istem dışı çalışmasını düzenleyen; sempatik ve '
        'parasempatik kısımlardan oluşan sistemdir.',
    'otonom sinir sistemi',
  ),
];

final _sinir = lmSirali(
  'bl_sinir',
  'Sinir sistemi: nöron, merkezî sinir sistemi ve refleks',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) => _olgu(
    i,
    _sinirGorev,
    eslestirme: 'Bu görevleri üstlenen yapılar sırasıyla hangi seçenekte doğru verilmiştir?',
    oncul: (y) => 'Bu bilgilerden hangileri “$y” için doğrudur?',
    aciklama: (x) =>
        'Birinci bilgi ${x[0].$2}, ikinci bilgi ${x[1].$2}, üçüncü bilgi '
        '${x[2].$2} için doğrudur.',
  ),
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 11. Endokrin sistem ─────────────────────────────

// (bez, kana verildiği bezden söz eden ayrılma eki biçimi)
const _bezler = <(String, String)>[
  ('pankreas', 'pankreastan'),
  ('tiroit', 'tiroit bezinden'),
  ('paratiroit', 'paratiroit bezlerinden'),
  ('hipofiz ön lobu', 'hipofizin ön lobundan'),
  ('hipofiz arka lobu', 'hipofizin arka lobundan'),
  ('epifiz', 'epifiz bezinden'),
  ('böbrek üstü bezi özü', 'böbrek üstü bezinin öz bölgesinden'),
  ('böbrek üstü bezi kabuğu', 'böbrek üstü bezinin kabuk bölgesinden'),
  ('testis', 'testislerden'),
  ('yumurtalık', 'yumurtalıklardan'),
  ('timüs', 'timüs bezinden'),
];

// (hormon, kana verildiği bez, etkisi). Her etki cümlesi tek hormona aittir.
const _hormonlar = <(String, int, String)>[
  (
    'insülin',
    0,
    'Kandaki glikozun hücrelere alınmasını ve karaciğerde glikojen olarak depolanmasını sağlar.',
  ),
  (
    'glukagon',
    0,
    'Açlıkta kan şekeri düşünce salgılanır; karaciğerdeki glikojeni glikoza yıkar.',
  ),
  (
    'tiroksin',
    1,
    'Yapısında iyot bulunur; hücrelerde metabolizma hızını artırır.',
  ),
  (
    'kalsitonin',
    1,
    'Kandaki kalsiyumun kemiklerde depolanmasını sağlayarak kan kalsiyum düzeyini düşürür.',
  ),
  (
    'parathormon',
    2,
    'Kemiklerden kana kalsiyum geçişini artırarak kan kalsiyum düzeyini yükseltir.',
  ),
  (
    'büyüme hormonu',
    3,
    'Çocuklukta fazla salgılanırsa devlik, az salgılanırsa cücelik görülür.',
  ),
  ('prolaktin', 3, 'Doğumdan sonra süt bezlerinde süt üretimini uyarır.'),
  ('TSH', 3, 'Tiroit bezini uyararak tiroksin salgılanmasını sağlar.'),
  (
    'ACTH',
    3,
    'Böbrek üstü bezinin kabuk bölgesini uyararak hormon salgılatır.',
  ),
  (
    'FSH',
    3,
    'Yumurtalıkta folikül gelişimini, testislerde sperm üretimini uyarır.',
  ),
  ('LH', 3, 'Yumurtlamayı (ovulasyonu) ve sarı cisim oluşumunu sağlar.'),
  (
    'ADH',
    4,
    'Böbreklerin distal tüp ve toplama kanallarında suyun geri emilimini artırır.',
  ),
  (
    'oksitosin',
    4,
    'Doğum sırasında dölyatağı (rahim) kaslarının kasılmasını sağlar.',
  ),
  (
    'melatonin',
    5,
    'Uyku ve uyanıklık döngüsünün (biyolojik saatin) düzenlenmesinde görev alır.',
  ),
  (
    'adrenalin',
    6,
    'Heyecan ve tehlike anında kalp atış hızını ve kan şekerini hızla artırır.',
  ),
  (
    'aldosteron',
    7,
    'Böbreklerde sodyum iyonlarının geri emilimini ve potasyumun atılmasını artırır.',
  ),
  (
    'kortizol',
    7,
    'Uzun süreli streste kan şekerini yükseltir ve bağışıklık tepkilerini baskılar.',
  ),
  (
    'testosteron',
    8,
    'Erkeklerde ikincil eşey özelliklerinin gelişmesini sağlar.',
  ),
  ('östrojen', 9, 'Dişilerde ikincil eşey özelliklerinin gelişmesini sağlar.'),
  (
    'progesteron',
    9,
    'Dölyatağının iç çeperini gebeliğe hazırlar ve gebeliğin sürmesini sağlar.',
  ),
  ('timozin', 10, 'T lenfositlerinin olgunlaşmasını sağlar.'),
];

/// Hormonun [bez] bezinden kana verilip verilmediği. Böbrek üstü bezinin
/// kabuğu az miktarda eşey hormonu da salgıladığından eşey hormonları o bez
/// için belirsiz sayılır.
bool? _hormonBezde(int h, int bez) {
  final (_, b, _) = _hormonlar[h];
  if (bez == 7 && b >= 8) return null;
  return b == bez;
}

// Hormon üçlüleri: −1 bez eşleştirmesi, q ≥ 0: q. bezden salgılananlar.
final _hormonBezAdaylari = _adaylar(
  _hormonlar.length,
  _bezler.length,
  (q, h) => _hormonBezde(h, q),
  sinif: (h) => _bezler[_hormonlar[h].$2].$1,
  uygun: (a, b, c) {
    // Eşey hormonu ile böbrek üstü kabuk hormonu aynı eşleştirmede yer almaz.
    final bz = {_hormonlar[a].$2, _hormonlar[b].$2, _hormonlar[c].$2};
    return !(bz.contains(7) && (bz.contains(8) || bz.contains(9)));
  },
);

// Etki üçlüleri: q ≥ 0 ise o bezden salgılanan hormonlara ait etkiler sorulur.
final _hormonEtkiAdaylari = _adaylar(
  _hormonlar.length,
  _bezler.length,
  (q, h) => _hormonBezde(h, q),
);

String _hormonCumle((String, int, String) h) {
  final (ad, b, _) = h;
  final ek = b == 4 ? ' (hipotalamusta üretilir)' : '';
  return '${_bas(ad)} ${_bezler[b].$2} kana verilir$ek.';
}

final _endokrin = lmSirali(
  'bl_endokrin',
  'Endokrin bezler, hormonlar ve etkileri',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) {
    final (f, j, n) = _bicim(i, 4);
    final d = ucluDizilimler[j % 6];
    if (f == 0) {
      // Etkilerden hormonlara eşleştirme.
      final u = kombinasyon(
        [for (var k = 0; k < _hormonlar.length; k++) k],
        3,
        j * 1330 ~/ 1250,
      );
      final x = [for (final t in d) _hormonlar[u[t]]];
      return _esle(
        '${_liste([for (final e in x) e.$3])}Bu etkileri gösteren hormonlar sırasıyla hangi '
            'seçenekte doğru verilmiştir?',
        [for (final e in x) e.$1],
        j,
        'Birinci etki ${x[0].$1}, ikinci etki ${x[1].$1}, üçüncü etki ${x[2].$1} hormonuna '
            'aittir. ${x.map(_hormonCumle).join(' ')}',
      );
    }
    if (f == 1) {
      final (a, b, c, q) = _yay(_hormonEtkiAdaylari, j, n);
      final x = [
        for (final t in d) [a, b, c][t],
      ];
      return _oncullu(
        '${_liste([for (final k in x) _hormonlar[k].$3])}Bu etkileri gösteren hormonlardan '
        'hangileri ${_bezler[q].$2} kana verilir?',
        [for (final k in x) _hormonBezde(k, q)!],
        j,
        [
          for (var t = 0; t < 3; t++)
            '${_romen[t]}. etki ${_hormonlar[x[t]].$1} hormonuna aittir; bu hormon '
                '${_bezler[_hormonlar[x[t]].$2].$2} kana verilir'
                '${_hormonlar[x[t]].$2 == 4 ? ' (hipotalamusta üretilir)' : ''}.',
        ].join(' '),
      );
    }
    final jj = j * 2 + f - 2, nn = lmAileBoyu - 2500;
    final (a, b, c, q) = _yay(_hormonBezAdaylari, jj, nn);
    final x = [
      for (final t in d) [a, b, c][t],
    ];
    final liste = _liste([for (final k in x) _hormonlar[k].$1]);
    final aciklama = [for (final k in x) _hormonCumle(_hormonlar[k])].join(' ');
    if (q < 0) {
      return _esle(
        '${liste}Bu hormonların kana verildiği bezler sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
        [for (final k in x) _bezler[_hormonlar[k].$2].$1],
        jj,
        aciklama,
      );
    }
    return _oncullu(
      '${liste}Bu hormonlardan hangileri ${_bezler[q].$2} kana verilir?',
      [for (final k in x) _hormonBezde(k, q)!],
      jj,
      aciklama,
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 12. Duyu organları ─────────────────────────────

const _duyuGorev = <(String, String)>[
  (
    'Gözün en dış tabakasının önde oluşturduğu, ışığı ilk kıran saydam bölümdür.',
    'kornea (saydam tabaka)',
  ),
  ('Göze rengini veren, göz bebeğinin çapını ayarlayan kaslı yapıdır.', 'iris'),
  (
    'Işığın göze girdiği, iris tarafından çapı ayarlanan açıklıktır.',
    'göz bebeği',
  ),
  (
    'Kirpiksi kaslarla kalınlığı değiştirilerek ışığı ağ tabakaya odaklayan saydam yapıdır.',
    'göz merceği',
  ),
  (
    'Merceğin kalınlığını değiştirerek uzağa ve yakına uyum yapılmasını sağlar.',
    'kirpiksi cisim',
  ),
  (
    'Görme almaçlarının (çubuk ve koni hücrelerinin) bulunduğu en iç tabakadır.',
    'ağ tabaka (retina)',
  ),
  (
    'Loş ışıkta görmeyi sağlayan, renkleri ayırt etmeyen görme almaçlarıdır.',
    'çubuk hücreleri',
  ),
  (
    'Parlak ışıkta renkli ve ayrıntılı görmeyi sağlayan görme almaçlarıdır.',
    'koni hücreleri',
  ),
  (
    'Koni hücrelerinin en yoğun bulunduğu, en net görüntünün oluştuğu bölgedir.',
    'sarı benek',
  ),
  (
    'Görme sinirinin gözden çıktığı, almaç bulunmadığından görüntü oluşmayan bölgedir.',
    'kör nokta',
  ),
  ('Gözü dıştan saran ve koruyan, beyaz renkli sert tabakadır.', 'sert tabaka'),
  (
    'Kan damarları ve pigment bakımından zengin olan, gözü besleyen orta tabakadır.',
    'damar tabaka',
  ),
  (
    'Göz küresinin iç boşluğunu dolduran, gözün şeklini korumasını sağlayan jelimsi saydam '
        'yapıdır.',
    'camsı cisim',
  ),
  ('Ağ tabakadaki uyartıları beyindeki görme merkezine taşır.', 'görme siniri'),
  ('Ses dalgalarını toplayarak dış kulak yoluna yönlendirir.', 'kulak kepçesi'),
  (
    'Gelen ses dalgalarıyla titreşerek titreşimleri orta kulağa iletir.',
    'kulak zarı',
  ),
  (
    'Titreşimleri kulak zarından oval pencereye ileten ve şiddetlendiren küçük kemiklerdir.',
    'çekiç, örs ve üzengi',
  ),
  (
    'Orta kulağı yutağa bağlayarak kulak zarının iki yanındaki basıncı dengeler.',
    'östaki borusu',
  ),
  (
    'Üzengi kemiğinin titreşimlerini iç kulaktaki sıvıya aktaran zarlı açıklıktır.',
    'oval pencere',
  ),
  (
    'İşitme almaçlarını taşıyan, iç kulakta bulunan helezon biçimli yapıdır.',
    'salyangoz',
  ),
  (
    'Salyangozdaki almaçlardan aldığı uyartıları beyindeki işitme merkezine taşır.',
    'işitme siniri',
  ),
  (
    'Başın dönme hareketlerini algılayarak dengenin korunmasına yardım eder.',
    'yarım daire kanalları',
  ),
  (
    'Başın yer çekimine göre konumunu ve doğrusal hareketleri algılayan iç kulak yapılarıdır.',
    'tulumcuk ve kesecik',
  ),
  ('Deride hafif dokunmayı algılayan almaçlardır.', 'Meissner cisimcikleri'),
  ('Deride basınç ve titreşimi algılayan almaçlardır.', 'Pacini cisimcikleri'),
  ('Deride sıcaklığı algılayan almaçlardır.', 'Ruffini cisimcikleri'),
  ('Deride soğuğu algılayan almaçlardır.', 'Krause cisimcikleri'),
  (
    'Deride acı (ağrı) duyusunu algılayan, uçları dallanmış almaçlardır.',
    'serbest sinir uçları',
  ),
  (
    'Üst derinin canlı ve bölünebilen hücrelerden oluşan, melanin pigmenti taşıyan tabakasıdır.',
    'Malpighi tabakası',
  ),
  (
    'Alt deride bulunur; salgısıyla vücut sıcaklığının düzenlenmesine yardım eder.',
    'ter bezleri',
  ),
  (
    'Kıl köklerine açılır; salgısıyla deriyi ve kılları yumuşak tutar.',
    'yağ bezleri',
  ),
  (
    'Dilin üzerindeki kabarıklıklarda bulunan, tat almaçlarını içeren yapılardır.',
    'tat tomurcukları',
  ),
  (
    'Burun boşluğunun üst kısmında bulunan, koku almaçlarını taşıyan bölgedir.',
    'koku epiteli (sarı bölge)',
  ),
  (
    'Koku moleküllerinin algılanabilmesi için içinde çözündüğü, burun boşluğunu örten yapışkan '
        'salgıdır.',
    'mukus',
  ),
  (
    'Dış kulak yolunda yabancı maddelerin içeri girmesini engelleyen salgıyı üreten yapılardır.',
    'kulak kiri bezleri',
  ),
];

final _duyu = lmSirali(
  'bl_duyu',
  'Duyu organlarının yapıları ve görevleri',
  Topic.biology,
  Difficulty.easy,
  BloomLevel.hatirlama,
  (i) => _olgu(
    i,
    _duyuGorev,
    eslestirme: 'Bu görevleri üstlenen yapılar sırasıyla hangi seçenekte doğru verilmiştir?',
    oncul: (y) => 'Bu bilgilerden hangileri “$y” için doğrudur?',
    aciklama: (x) =>
        'Birinci bilgi ${x[0].$2}, ikinci bilgi ${x[1].$2}, üçüncü bilgi '
        '${x[2].$2} için doğrudur.',
  ),
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 13. Kanın izlediği yol ─────────────────────────────

// (yapı, ayrılma eki biçimi, oksijence zengin mi (null: kılcal damar))
const _kanYapi = <String, (String, bool?)>{
  'sağ kulakçık': ('sağ kulakçıktan', false),
  'sağ karıncık': ('sağ karıncıktan', false),
  'akciğer atardamarı': ('akciğer atardamarından', false),
  'akciğer kılcalları': ('akciğer kılcallarından', null),
  'akciğer toplardamarları': ('akciğer toplardamarlarından', true),
  'sol kulakçık': ('sol kulakçıktan', true),
  'sol karıncık': ('sol karıncıktan', true),
  'aort': ('aorttan', true),
  'şah damarı': ('şah damarından', true),
  'beyin kılcalları': ('beyin kılcallarından', null),
  'boyun toplardamarı': ('boyun toplardamarından', false),
  'üst ana toplardamar': ('üst ana toplardamardan', false),
  'kol atardamarı': ('kol atardamarından', true),
  'kol kılcalları': ('kol kılcallarından', null),
  'kol toplardamarı': ('kol toplardamarından', false),
  'böbrek atardamarı': ('böbrek atardamarından', true),
  'böbrek kılcalları': ('böbrek kılcallarından', null),
  'böbrek toplardamarı': ('böbrek toplardamarından', false),
  'alt ana toplardamar': ('alt ana toplardamardan', false),
  'bacak atardamarı': ('bacak atardamarından', true),
  'bacak kılcalları': ('bacak kılcallarından', null),
  'bacak toplardamarı': ('bacak toplardamarından', false),
  'bağırsak atardamarı': ('bağırsak atardamarından', true),
  'bağırsak kılcalları': ('bağırsak kılcallarından', null),
  'kapı toplardamarı': ('kapı toplardamarından', false),
  'karaciğer kılcalları': ('karaciğer kılcallarından', null),
  'karaciğer toplardamarı': ('karaciğer toplardamarından', false),
};

const _kalpAkciger = [
  'sağ kulakçık',
  'sağ karıncık',
  'akciğer atardamarı',
  'akciğer kılcalları',
  'akciğer toplardamarları',
  'sol kulakçık',
  'sol karıncık',
  'aort',
];

// Aorttan sonra organdan geçip sağ kulakçığa dönen yollar.
const _organYolu = [
  [
    'şah damarı',
    'beyin kılcalları',
    'boyun toplardamarı',
    'üst ana toplardamar',
  ],
  [
    'kol atardamarı',
    'kol kılcalları',
    'kol toplardamarı',
    'üst ana toplardamar',
  ],
  [
    'böbrek atardamarı',
    'böbrek kılcalları',
    'böbrek toplardamarı',
    'alt ana toplardamar',
  ],
  [
    'bacak atardamarı',
    'bacak kılcalları',
    'bacak toplardamarı',
    'alt ana toplardamar',
  ],
  [
    'bağırsak atardamarı',
    'bağırsak kılcalları',
    'kapı toplardamarı',
    'karaciğer kılcalları',
    'karaciğer toplardamarı',
    'alt ana toplardamar',
  ],
];

// (yol, başlangıç konumu, sıradaki yapıların konumları): aynı başlangıç ve
// yapı kümesi bir kez alınır.
final _kanYoluAdaylari = () {
  final out = <(int, int, List<int>)>[];
  final gorulen = <String>{};
  for (var r = 0; r < _organYolu.length; r++) {
    final dongu = [..._kalpAkciger, ..._organYolu[r]];
    final n = dongu.length;
    for (final k in [3, 4]) {
      for (var s = 0; s < n; s++) {
        for (final alt in _altKumeler(n - 1, k)) {
          final konum = [for (final a in alt) (s + 1 + a) % n];
          final anahtar =
              '${dongu[s]}|${([for (final c in konum) dongu[c]]..sort()).join(',')}';
          if (gorulen.add(anahtar)) out.add((r, s, konum));
        }
      }
    }
  }
  return out;
}();

const _oksijenYapi = [
  'sağ kulakçık',
  'sağ karıncık',
  'akciğer atardamarı',
  'akciğer toplardamarları',
  'sol kulakçık',
  'sol karıncık',
  'aort',
  'şah damarı',
  'boyun toplardamarı',
  'üst ana toplardamar',
  'kol atardamarı',
  'kol toplardamarı',
  'böbrek atardamarı',
  'böbrek toplardamarı',
  'alt ana toplardamar',
  'bacak atardamarı',
  'bacak toplardamarı',
  'bağırsak atardamarı',
  'kapı toplardamarı',
  'karaciğer toplardamarı',
];

final _oksijenAdaylari = _adaylar(
  _oksijenYapi.length,
  2,
  (q, k) =>
      q == 0 ? _kanYapi[_oksijenYapi[k]]!.$2 : !_kanYapi[_oksijenYapi[k]]!.$2!,
);

final _kanYolu = lmSirali(
  'bl_kan_yolu',
  'Kalbin bölümleri ve kanın izlediği yol',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final (f, j, n) = _bicim(i, 3);
    if (f < 2) {
      final jj = j * 2 + f, nn = lmAileBoyu - lmAileBoyu ~/ 3;
      final (r, s, konum) = _yay(_kanYoluAdaylari, jj, nn);
      final dongu = [..._kalpAkciger, ..._organYolu[r]];
      final bas = dongu[s];
      final son = konum.last;
      // Başlangıçtan en uzaktaki listelenmiş yapıya kadar olan yol.
      final uzaklik = (son - s) % dongu.length;
      final yol = [
        for (var t = 0; t <= uzaklik; t++) dongu[(s + t) % dongu.length],
      ];
      return _siralama(
        '',
        [for (final c in konum) dongu[c]],
        'Sağlıklı bir insanda ${_kanYapi[bas]!.$1} çıkan kan bu yapılardan hangi sırayla '
            'geçer?',
        jj,
        'Kanın yolu: ${yol.join(' → ')}.',
      );
    }
    final (a, b, c, q) = _yay(_oksijenAdaylari, j, n);
    final d = ucluDizilimler[j % 6];
    final x = [
      for (final t in d) _oksijenYapi[[a, b, c][t]],
    ];
    final zengin = [
      for (final y in x)
        if (_kanYapi[y]!.$2!) y,
    ];
    final fakir = [
      for (final y in x)
        if (!_kanYapi[y]!.$2!) y,
    ];
    return _oncullu(
      '${_liste(x)}Sağlıklı bir yetişkin insanda bu yapılardan hangilerinde oksijence '
      '${q == 0 ? 'zengin' : 'fakir'} kan bulunur?',
      [for (final y in x) q == 0 ? _kanYapi[y]!.$2! : !_kanYapi[y]!.$2!],
      j,
      [
        'Akciğerlerden dönen toplardamarlarda, sol kulakçık ve karıncıkta, aortta ve organlara '
            'giden atardamarlarda oksijence zengin; organlardan dönen toplardamarlarda, sağ '
            'kulakçık ve karıncıkta ve akciğer atardamarında oksijence fakir kan bulunur.',
        if (zengin.isNotEmpty) '${_bas(_ve(zengin))}: oksijence zengin.',
        if (fakir.isNotEmpty) '${_bas(_ve(fakir))}: oksijence fakir.',
      ].join(' '),
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 14. Kan hücreleri ve bağışıklık ─────────────────────────────

const _bagisiklikTuru = [
  'doğal aktif',
  'yapay aktif',
  'doğal pasif',
  'yapay pasif',
];

const _bagisiklikDurum = <(String, int)>[
  (
    'Kızamık hastalığını geçiren bir çocuğun bu hastalığa karşı bağışıklık kazanması',
    0,
  ),
  ('Su çiçeği geçiren bir kişinin bu hastalığa yeniden yakalanmaması', 0),
  (
    'Kabakulak geçiren bir çocukta bu hastalığa karşı hafıza hücrelerinin oluşması',
    0,
  ),
  (
    'Boğmaca hastalığını atlatan bir kişinin bu hastalığa karşı bağışıklık kazanması',
    0,
  ),
  ('Kızamıkçık geçiren bir kişinin bu hastalığa karşı bağışıklık kazanması', 0),
  (
    'Bir grip virüsüyle hastalanıp iyileşen kişinin aynı virüse karşı bağışıklık kazanması',
    0,
  ),
  ('Bebeğe hepatit B aşısı yapılması', 1),
  ('Çocuğa kızamık aşısı yapılması', 1),
  ('Çocuğa ağız yoluyla çocuk felci aşısı verilmesi', 1),
  ('Yeni doğan bebeğe verem (BCG) aşısı yapılması', 1),
  ('Bir kişiye tetanos aşısı yapılması', 1),
  ('Kuduz şüphesi olan bir kişiye kuduz aşısı yapılması', 1),
  ('Bir kişiye mevsimsel grip aşısı yapılması', 1),
  ('Anne karnındaki bebeğe plasenta yoluyla annenin antikorlarının geçmesi', 2),
  ('Bebeğin anne sütüyle antikor alması', 2),
  (
    'Paslı bir çiviyle yaralanan kişiye hazır antikor içeren tetanos serumu verilmesi',
    3,
  ),
  ('Yılan sokan bir kişiye yılan zehrine karşı hazırlanmış serum verilmesi', 3),
  (
    'Kuduz şüphesi olan bir kişiye hazır antikor içeren kuduz serumu verilmesi',
    3,
  ),
  ('Akrep sokan bir kişiye akrep zehrine karşı hazırlanmış serum verilmesi', 3),
  ('Difteri hastasına hazır antikor içeren difteri serumu verilmesi', 3),
  (
    'Başka bir canlıda üretilmiş hazır antikorların bir kişiye enjeksiyonla verilmesi',
    3,
  ),
];

const _bagisiklikSorulari = [
  'Bu durumlardan hangilerinde aktif bağışıklık kazanılır?',
  'Bu durumlardan hangilerinde pasif bağışıklık kazanılır?',
  'Bu durumlardan hangilerinde bağışıklık doğal yolla kazanılır?',
  'Bu durumlardan hangilerinde bağışıklık yapay yolla (tıbbi uygulamayla) kazanılır?',
];

bool _bagisiklikDeger(int q, int k) {
  final t = _bagisiklikDurum[k].$2;
  return switch (q) {
    0 => t <= 1,
    1 => t >= 2,
    2 => t == 0 || t == 2,
    _ => t == 1 || t == 3,
  };
}

final _bagisiklikAdaylari = _adaylar(
  _bagisiklikDurum.length,
  _bagisiklikSorulari.length,
  _bagisiklikDeger,
  sinif: (k) => _bagisiklikTuru[_bagisiklikDurum[k].$2],
);

const _bagisiklikAciklama = [
  'hastalık geçirilerek kazanılan doğal aktif bağışıklıktır',
  'aşıyla kazanılan yapay aktif bağışıklıktır',
  'anneden hazır antikor geçmesiyle kazanılan doğal pasif bağışıklıktır',
  'hazır antikor (serum) verilerek kazanılan yapay pasif bağışıklıktır',
];

// Kan hücrelerinin özellikleri: (özellik, [alyuvar, akyuvar, kan pulcukları]).
const _kanHucresiOzellik = <(String, List<bool>)>[
  ('Olgun hâlde çekirdek taşımaz.', [true, false, true]),
  ('Hemoglobin taşıyarak oksijen taşınmasını sağlar.', [true, false, false]),
  ('Kanın pıhtılaşmasında görev alır.', [false, false, true]),
  ('Fagositozla mikropları yok edebilir.', [false, true, false]),
  ('Kılcal damar çeperinden geçerek dokulara gidebilir.', [false, true, false]),
  ('Kırmızı kemik iliğinde üretilir.', [true, true, true]),
  ('Bir grubu antikor üretimini gerçekleştirir.', [false, true, false]),
  ('Kanda sayıca en fazla bulunan hücredir.', [true, false, false]),
  (
    'Büyük hücrelerin (megakaryositlerin) parçalanmasıyla oluşan hücre parçalarıdır.',
    [false, false, true],
  ),
  ('Enfeksiyon sırasında kandaki sayısı artar.', [false, true, false]),
  ('Olgun hâlde mitokondri taşımaz.', [true, false, false]),
  (
    'Karbondioksitin bir bölümünün taşınmasında görev alır.',
    [true, false, false],
  ),
];

const _kanHucresi = ['alyuvarlar', 'akyuvarlar', 'kan pulcukları'];

final _kanHucresiSorulari = <(String, bool Function(List<bool>))>[
  for (var h = 0; h < 3; h++)
    (
      'Bu özelliklerden hangileri ${_kanHucresi[h]} için doğrudur?',
      (v) => v[h],
    ),
  for (var h = 0; h < 3; h++)
    for (var k = h + 1; k < 3; k++)
      (
        'Bu özelliklerden hangileri hem ${_kanHucresi[h]} hem de ${_kanHucresi[k]} için '
            'doğrudur?',
        (v) => v[h] && v[k],
      ),
  for (var h = 0; h < 3; h++)
    (
      'Bu özelliklerden hangileri kan hücreleri içinde yalnız ${_kanHucresi[h]} için '
          'doğrudur?',
      (v) => v[h] && v.where((e) => e).length == 1,
    ),
];

final _kanHucresiAdaylari = _adaylar(
  _kanHucresiOzellik.length,
  _kanHucresiSorulari.length,
  (q, k) => _kanHucresiSorulari[q].$2(_kanHucresiOzellik[k].$2),
);

String _kanHucresiCumle((String, List<bool>) e) {
  final (oz, v) = e;
  final olan = [
    for (var h = 0; h < 3; h++)
      if (v[h]) _kanHucresi[h],
  ];
  final ozellik = oz.substring(0, oz.length - 1);
  return '“$ozellik” özelliği ${olan.length == 3 ? 'üç kan hücresi için de' : '${_ve(olan)} için'} '
      'doğrudur.';
}

final _bagisiklik = lmSirali(
  'bl_bagisiklik',
  'Kan hücreleri ve bağışıklık türleri',
  Topic.biology,
  Difficulty.easy,
  BloomLevel.anlama,
  (i) {
    final (f, j, n) = _bicim(i, 6);
    final d = ucluDizilimler[j % 6];
    if (f == 5) {
      final (a, b, c, q) = _yay(_kanHucresiAdaylari, j, n);
      final x = [
        for (final t in d) _kanHucresiOzellik[[a, b, c][t]],
      ];
      return _oncullu(
        '${_liste([for (final e in x) e.$1])}${_kanHucresiSorulari[q].$1}',
        [for (final e in x) _kanHucresiSorulari[q].$2(e.$2)],
        j,
        x.map(_kanHucresiCumle).join(' '),
      );
    }
    // f = 0 … 4 vakaları tek bir sıra oluşturur (f = 5 kan hücresi sorularıdır).
    final kk = j * 5 + f;
    final (a, b, c, q) = _yay(
      _bagisiklikAdaylari,
      kk,
      lmAileBoyu - lmAileBoyu ~/ 6,
    );
    final xk = [
      for (final t in d) [a, b, c][t],
    ];
    final x = [for (final k in xk) _bagisiklikDurum[k]];
    final liste = _liste([for (final e in x) e.$1]);
    final aciklama = [
      for (var t = 0; t < 3; t++)
        '${_romen[t]}. durum ${_bagisiklikAciklama[x[t].$2]}.',
      'Aktif bağışıklıkta vücut antikorlarını ve hafıza hücrelerini kendisi üretir; pasif '
          'bağışıklıkta antikorlar hazır alınır ve etkisi kısa sürer.',
    ].join(' ');
    if (q < 0) {
      return _esle(
        '${liste}Bu durumlarda kazanılan bağışıklık türleri sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
        [for (final e in x) _bagisiklikTuru[e.$2]],
        kk,
        aciklama,
      );
    }
    return _oncullu(
      '$liste${_bagisiklikSorulari[q]}',
      [for (final k in xk) _bagisiklikDeger(q, k)],
      kk,
      aciklama,
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 15. Solunum sistemi ─────────────────────────────

const _havaYolu = [
  'burun boşluğu',
  'yutak',
  'gırtlak',
  'soluk borusu',
  'bronşlar',
  'bronşçuklar',
  'alveoller',
  'alveolleri saran kılcal damarlar',
];

// (konu, olay, normal soluk almada mı (değilse soluk vermede) gerçekleşir)
const _solunumOlay = <(int, String, bool)>[
  (0, 'Diyafram kası kasılarak düzleşir.', true),
  (0, 'Diyafram aşağı doğru iner.', true),
  (0, 'Diyafram kası gevşeyerek kubbe biçimini alır.', false),
  (0, 'Diyafram yukarı doğru yükselir.', false),
  (1, 'Dış kaburgalar arası kaslar kasılır.', true),
  (1, 'Dış kaburgalar arası kaslar gevşer.', false),
  (2, 'Kaburgalar yukarı ve dışa doğru hareket eder.', true),
  (2, 'Kaburgalar aşağı ve içe doğru hareket eder.', false),
  (3, 'Göğüs boşluğunun hacmi artar.', true),
  (3, 'Göğüs boşluğunun hacmi azalır.', false),
  (4, 'Akciğerlerin hacmi artar.', true),
  (4, 'Akciğerlerin hacmi azalır.', false),
  (5, 'Akciğerlerdeki hava basıncı atmosfer basıncının altına düşer.', true),
  (5, 'Akciğerlerdeki hava basıncı atmosfer basıncının üzerine çıkar.', false),
  (6, 'Hava dış ortamdan akciğerlere doğru akar.', true),
  (6, 'Hava akciğerlerden dış ortama doğru akar.', false),
];

// Konuları farklı olay üçlüleri.
final _solunumUcluleri = [
  for (final (a, b, c) in _ucluler(_solunumOlay.length))
    if ({_solunumOlay[a].$1, _solunumOlay[b].$1, _solunumOlay[c].$1}.length ==
        3)
      (a, b, c),
];

/// 0 ≤ a < b < c < n üçlüleri.
List<(int, int, int)> _ucluler(int n) => [
  for (var a = 0; a < n; a++)
    for (var b = a + 1; b < n; b++)
      for (var c = b + 1; c < n; c++) (a, b, c),
];

const _solunumKurali = [
  'Normal soluk vermede diyafram ve dış kaburgalar arası kaslar gevşer, diyafram kubbeleşir, '
      'kaburgalar aşağı ve içe iner; göğüs boşluğunun ve akciğerlerin hacmi azalır, akciğer '
      'içi basınç atmosfer basıncının üzerine çıkar ve hava dışarı akar.',
  'Normal soluk almada diyafram ve dış kaburgalar arası kaslar kasılır, diyafram düzleşip '
      'iner, kaburgalar yukarı ve dışa kalkar; göğüs boşluğunun ve akciğerlerin hacmi artar, '
      'akciğer içi basınç atmosfer basıncının altına düşer ve hava içeri akar.',
];

AdvancedItem _solunumMekanik(
  (int, int, int) u,
  bool alma,
  int? atm,
  int fark,
  int i,
) {
  final (a, b, c) = u;
  final d = ucluDizilimler[i % 6];
  final x = [
    for (final t in d) _solunumOlay[[a, b, c][t]],
  ];
  final dogru = [
    for (var t = 0; t < 3; t++)
      if (x[t].$3 == alma) _romen[t],
  ];
  final liste = _liste([for (final e in x) e.$2]);
  final String kok;
  final String giris;
  if (atm == null) {
    kok =
        '${liste}Dinlenmekte olan bir kişide normal ${alma ? 'soluk alma' : 'soluk verme'} '
        'sırasında bu olaylardan hangileri gerçekleşir?';
    giris = '';
  } else {
    final ic = alma ? atm - fark : atm + fark;
    kok =
        'Atmosfer basıncının $atm mmHg olduğu bir yerde dinlenmekte olan bir kişinin '
        'akciğerlerindeki hava basıncı bir anda $ic mmHg olarak ölçülüyor.\n${liste}Bu anda '
        'bu olaylardan hangileri gerçekleşmektedir?';
    giris =
        'Akciğerlerdeki basınç ($ic mmHg) atmosfer basıncından ($atm mmHg) '
        '${alma ? 'düşük' : 'yüksek'} olduğundan hava ${alma ? 'akciğerlere girer; kişi soluk '
                  'almaktadır' : 'akciğerlerden çıkar; kişi soluk vermektedir'}. ';
  }
  return _oncullu(
    kok,
    [for (final e in x) e.$3 == alma],
    i,
    '$giris${_solunumKurali[alma ? 1 : 0]} Bu nedenle ${_ve(dogru)} gerçekleşir.',
  );
}

final _solunumAdaylari = () {
  final out = <AdvancedItem Function(int)>[];
  // Hava yolu sıralaması: soluk almada oksijen, soluk vermede karbondioksit.
  for (final alma in [true, false]) {
    for (var k = 3; k <= 5; k++) {
      for (final s in _altKumeler(_havaYolu.length, k)) {
        final yapilar = [for (final j in s) _havaYolu[j]];
        final sira = alma ? yapilar : yapilar.reversed.toList();
        final yol = alma ? _havaYolu : _havaYolu.reversed.toList();
        out.add(
          (i) => _siralama(
            '',
            sira,
            alma
                ? 'Soluk alma sırasında burundan alınan havadaki bir oksijen molekülü kana '
                      'geçinceye kadar bu yapılardan hangi sırayla geçer?'
                : 'Kandan alveollere geçen bir karbondioksit molekülü soluk verme sırasında '
                      'burundan dışarı çıkıncaya kadar bu yapılardan hangi sırayla geçer?',
            i,
            '${alma ? 'Oksijenin' : 'Karbondioksitin'} yolu: ${yol.join(' → ')}.',
          ),
        );
      }
    }
  }
  // Evresi verilen mekanik sorular.
  for (final alma in [true, false]) {
    for (final u in _solunumUcluleri) {
      final (a, b, c) = u;
      if ([a, b, c].any((k) => _solunumOlay[k].$3 == alma)) {
        out.add((i) => _solunumMekanik(u, alma, null, 0, i));
      }
    }
  }
  // Basınçları verilen sorular: kalan vakalar yayılarak seçilir.
  final basinc = <AdvancedItem Function(int)>[];
  for (var atm = 760; atm >= 600; atm -= 10) {
    for (var fark = 1; fark <= 3; fark++) {
      for (final alma in [true, false]) {
        for (final u in _solunumUcluleri) {
          final (a, b, c) = u;
          if ([a, b, c].any((k) => _solunumOlay[k].$3 == alma)) {
            basinc.add((i) => _solunumMekanik(u, alma, atm, fark, i));
          }
        }
      }
    }
  }
  final kalan = lmAileBoyu - out.length;
  for (var j = 0; j < kalan; j++) {
    out.add(_yay(basinc, j, kalan));
  }
  return out;
}();

final _solunumYolu = lmSirali(
  'bl_solunum_yolu',
  'Havanın yolu, soluk alıp vermede kas ve basınç',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) => _solunumAdaylari[i * 2477 % lmAileBoyu](i),
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 16. Destek ve hareket sistemi ─────────────────────────────

// (yapı, grup (0 kas, 1 kemik, 2 eklem), tür)
const _destekYapi = <(String, int, String)>[
  ('mide çeperindeki kaslar', 0, 'düz kas'),
  ('atardamar çeperindeki kaslar', 0, 'düz kas'),
  ('idrar kesesi çeperindeki kaslar', 0, 'düz kas'),
  ('ince bağırsak çeperindeki kaslar', 0, 'düz kas'),
  ('dölyatağı (rahim) çeperindeki kaslar', 0, 'düz kas'),
  ('göz bebeğinin çapını ayarlayan iris kasları', 0, 'düz kas'),
  ('kalbin karıncık çeperindeki kaslar', 0, 'kalp kası'),
  ('kalbin kulakçık çeperindeki kaslar', 0, 'kalp kası'),
  ('kolu dirsekten büken pazu kası', 0, 'çizgili kas'),
  ('baldırdaki kaslar', 0, 'çizgili kas'),
  ('soluk almada kasılan diyafram', 0, 'çizgili kas'),
  ('dil kasları', 0, 'çizgili kas'),
  ('göz küresini hareket ettiren kaslar', 0, 'çizgili kas'),
  ('yüz ifadesini oluşturan mimik kasları', 0, 'çizgili kas'),
  ('uyluk kemiği', 1, 'uzun kemik'),
  ('kaval kemiği', 1, 'uzun kemik'),
  ('üst kol (pazu) kemiği', 1, 'uzun kemik'),
  ('ön kol kemikleri', 1, 'uzun kemik'),
  ('el bileği kemikleri', 1, 'kısa kemik'),
  ('ayak bileği kemikleri', 1, 'kısa kemik'),
  ('kafatası kemikleri', 1, 'yassı kemik'),
  ('kaburgalar', 1, 'yassı kemik'),
  ('göğüs kemiği', 1, 'yassı kemik'),
  ('kürek kemiği', 1, 'yassı kemik'),
  ('omurlar', 1, 'düzensiz kemik'),
  ('kafatası kemikleri arasındaki eklemler', 2, 'oynamaz eklem'),
  ('omurlar arasındaki eklemler', 2, 'yarı oynar eklem'),
  ('kaburgaların göğüs kemiğine bağlandığı eklemler', 2, 'yarı oynar eklem'),
  ('diz eklemi', 2, 'oynar eklem'),
  ('dirsek eklemi', 2, 'oynar eklem'),
  ('omuz eklemi', 2, 'oynar eklem'),
  ('kalça eklemi', 2, 'oynar eklem'),
  ('alt çene ile kafatası arasındaki eklem', 2, 'oynar eklem'),
  ('parmak kemikleri arasındaki eklemler', 2, 'oynar eklem'),
];

const _destekSoru = {
  'düz kas': 'düz kas dokusundan oluşur',
  'kalp kası': 'kalp kası dokusundan oluşur',
  'çizgili kas': 'çizgili (iskelet) kas dokusundan oluşur',
  'uzun kemik': 'uzun kemik grubunda yer alır',
  'kısa kemik': 'kısa kemik grubunda yer alır',
  'yassı kemik': 'yassı kemik grubunda yer alır',
  'düzensiz kemik': 'düzensiz kemik grubunda yer alır',
  'oynamaz eklem': 'oynamaz eklem grubunda yer alır',
  'yarı oynar eklem': 'yarı oynar eklem grubunda yer alır',
  'oynar eklem': 'oynar eklem grubunda yer alır',
};

const _destekEslestirme = [
  'Bu kasların türleri sırasıyla hangi seçenekte doğru verilmiştir?',
  'Bu kemiklerin şekillerine göre türleri sırasıyla hangi seçenekte doğru verilmiştir?',
  'Bu eklemlerin türleri sırasıyla hangi seçenekte doğru verilmiştir?',
];

// Kas özellikleri: (özellik, [çizgili kas, düz kas, kalp kası]).
const _kasOzellik = <(String, List<bool>)>[
  ('İstemli olarak çalışır.', [true, false, false]),
  ('İstemsiz olarak çalışır.', [false, true, true]),
  ('Mikroskopta enine bantlar (çizgiler) görülür.', [true, false, true]),
  ('Hücreleri çok çekirdeklidir.', [true, false, false]),
  ('Hücreleri iğ biçimlidir ve tek çekirdek taşır.', [false, true, false]),
  ('Çabuk yorulur.', [true, false, false]),
  ('Ömür boyu yorulmadan ritmik olarak kasılır.', [false, false, true]),
  ('Kirişlerle (tendonlarla) kemiklere bağlanır.', [true, false, false]),
  ('İç organların ve damarların çeperinde bulunur.', [false, true, false]),
  (
    'Hücreleri dallanmıştır ve ara disklerle birbirine bağlanır.',
    [false, false, true],
  ),
  ('Kasılmasında aktin ve miyozin iplikleri görev alır.', [true, true, true]),
  ('Otonom sinir sistemi tarafından denetlenir.', [false, true, true]),
  ('Somatik sinir sistemi tarafından denetlenir.', [true, false, false]),
  ('Kasılması için ATP harcanır.', [true, true, true]),
];

const _kasAdi = ['çizgili (iskelet) kas', 'düz kas', 'kalp kası'];

final _kasSorulari = <(String, bool Function(List<bool>))>[
  for (var h = 0; h < 3; h++)
    ('Bu özelliklerden hangileri ${_kasAdi[h]} için doğrudur?', (v) => v[h]),
  for (var h = 0; h < 3; h++)
    for (var k = h + 1; k < 3; k++)
      (
        'Bu özelliklerden hangileri hem ${_kasAdi[h]} hem de ${_kasAdi[k]} için doğrudur?',
        (v) => v[h] && v[k],
      ),
];

final _kasAdaylari = _adaylar(
  _kasOzellik.length,
  _kasSorulari.length,
  (q, k) => _kasSorulari[q].$2(_kasOzellik[k].$2),
);

final _destekHareket = lmSirali(
  'bl_destek_hareket',
  'Kas tipleri, kemik ve eklem türleri',
  Topic.biology,
  Difficulty.easy,
  BloomLevel.hatirlama,
  (i) {
    final (f, j, n) = _bicim(i, 5);
    final d = ucluDizilimler[j % 6];
    if (f == 4) {
      final (a, b, c, q) = _yay(_kasAdaylari, j, n);
      final x = [
        for (final t in d) _kasOzellik[[a, b, c][t]],
      ];
      return _oncullu(
        '${_liste([for (final e in x) e.$1])}${_kasSorulari[q].$1}',
        [for (final e in x) _kasSorulari[q].$2(e.$2)],
        j,
        [
          for (final (oz, v) in x)
            '“${oz.substring(0, oz.length - 1)}” özelliği '
                '${v.every((e) => e) ? 'üç kas tipi için de' : '${_ve([for (var h = 0; h < 3; h++)
                        if (v[h]) _kasAdi[h]])} için'} '
                'doğrudur.',
        ].join(' '),
      );
    }
    final kk = j * 4 + f, nn = lmAileBoyu - lmAileBoyu ~/ 5;
    final u = kombinasyon(_destekYapi, 3, kk * lmAileBoyu ~/ nn);
    final x = [for (final t in d) u[t]];
    final liste = _liste([for (final e in x) e.$1]);
    final aciklama = '${_bas(_ve([for (final e in x) '${e.$1}: ${e.$3}']))}.';
    final ayniGrup = x[0].$2 == x[1].$2 && x[1].$2 == x[2].$2;
    final farkli = {for (final e in x) e.$3}.length == 3;
    if (ayniGrup && farkli && kk % 4 != 3) {
      return _esle(
        '$liste${_destekEslestirme[x[0].$2]}',
        [for (final e in x) e.$3],
        kk,
        aciklama,
      );
    }
    final sorulan = x[kk ~/ 6 % 3].$3;
    return _oncullu(
      '${liste}Bu yapılardan hangileri ${_destekSoru[sorulan]}?',
      [for (final e in x) e.$3 == sorulan],
      kk,
      aciklama,
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 17. Embriyonik tabakalar ─────────────────────────────

const _embriyoYapi = <(String, String)>[
  ('derinin üst tabakası (epidermis)', 'ektoderm'),
  ('saç ve kıllar', 'ektoderm'),
  ('tırnaklar', 'ektoderm'),
  ('ter bezleri', 'ektoderm'),
  ('derideki yağ bezleri', 'ektoderm'),
  ('süt bezleri', 'ektoderm'),
  ('beyin', 'ektoderm'),
  ('omurilik', 'ektoderm'),
  ('çevresel sinirler', 'ektoderm'),
  ('göz merceği', 'ektoderm'),
  ('gözün ağ tabakası (retina)', 'ektoderm'),
  ('iç kulak', 'ektoderm'),
  ('diş minesi', 'ektoderm'),
  ('böbrek üstü bezinin öz bölgesi', 'ektoderm'),
  ('hipofiz bezi', 'ektoderm'),
  ('iskelet kasları', 'mezoderm'),
  ('düz kaslar', 'mezoderm'),
  ('kalp', 'mezoderm'),
  ('kemikler', 'mezoderm'),
  ('kıkırdaklar', 'mezoderm'),
  ('kan hücreleri', 'mezoderm'),
  ('kan damarları', 'mezoderm'),
  ('böbrekler', 'mezoderm'),
  ('eşey bezleri (yumurtalık ve testis)', 'mezoderm'),
  ('derinin alt tabakası (dermis)', 'mezoderm'),
  ('böbrek üstü bezinin kabuk bölgesi', 'mezoderm'),
  ('lenf damarları', 'mezoderm'),
  ('dalak', 'mezoderm'),
  ('sindirim kanalının iç yüzeyini örten epitel', 'endoderm'),
  ('karaciğer', 'endoderm'),
  ('pankreas', 'endoderm'),
  ('akciğerlerdeki hava keseciklerinin epiteli', 'endoderm'),
  ('soluk borusunun iç yüzey epiteli', 'endoderm'),
  ('tiroit bezi', 'endoderm'),
  ('paratiroit bezleri', 'endoderm'),
  ('timüs bezi', 'endoderm'),
  ('idrar kesesinin iç yüzey epiteli', 'endoderm'),
];

const _tabakaDen = {
  'ektoderm': 'ektodermden',
  'mezoderm': 'mezodermden',
  'endoderm': 'endodermden',
};

final _embriyonik = lmSirali(
  'bl_embriyonik',
  'Embriyonik tabakalar ve gelişen yapılar',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) => _olgu(
    i,
    _embriyoYapi,
    eslestirme:
        'Bu yapıların geliştiği embriyonik tabakalar sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
    oncul: (y) => 'Bu yapılardan hangileri ${_tabakaDen[y]} gelişir?',
    aciklama: (x) =>
        '${_bas(_ve([for (final e in x) '${e.$1} ${_tabakaDen[e.$2]}']))} '
        'gelişir.',
  ),
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 18. Bitki dokuları ve organları ─────────────────────────────

const _bitkiDoku = <(String, String)>[
  (
    'Kök ve gövde uçlarında bulunur; bitkinin boyca uzamasını sağlar.',
    'uç meristem',
  ),
  (
    'Kök ve gövde ucundaki büyüme konisini oluşturan, sürekli bölünebilen hücrelerdir.',
    'uç meristem',
  ),
  (
    'Odunsu bitkilerde gövde ve kökün enine kalınlaşmasını sağlar.',
    'yanal meristem (kambiyum)',
  ),
  (
    'İçe doğru ksilem, dışa doğru floem hücreleri üretir.',
    'yanal meristem (kambiyum)',
  ),
  (
    'Yaprağın üst yüzeyine yakın, sık dizilmiş ve kloroplastça zengin silindirik hücrelerden '
        'oluşur.',
    'palizat parankiması',
  ),
  (
    'Hücreleri arasında geniş boşluklar bulunan, gaz alışverişini kolaylaştıran yaprak '
        'parankimasıdır.',
    'sünger parankiması',
  ),
  (
    'Patates yumrusu gibi organlarda nişasta depolayan parankimadır.',
    'depo parankiması',
  ),
  (
    'Su bitkilerinde geniş hücreler arası boşluklarıyla bitkinin suda durmasını ve gaz '
        'alışverişini kolaylaştırır.',
    'havalandırma parankiması',
  ),
  (
    'Kaktüs gibi kurak ortam bitkilerinde su biriktiren parankimadır.',
    'su depolayan parankima',
  ),
  (
    'Suyu ve mineralleri kökten yapraklara taşır; olgun hücreleri ölüdür.',
    'ksilem (odun borusu)',
  ),
  (
    'Trake ve trakeitlerden oluşur; çeperinde lignin birikmiştir.',
    'ksilem (odun borusu)',
  ),
  (
    'Odunsu bitkilerde yıllık halkaları oluşturan iletim dokusudur.',
    'ksilem (odun borusu)',
  ),
  (
    'Fotosentez ürünlerini bitkinin diğer kısımlarına taşır; hücreleri canlıdır.',
    'floem (soymuk borusu)',
  ),
  ('Kalbur boruları ve arkadaş hücrelerinden oluşur.', 'floem (soymuk borusu)'),
  (
    'Taşımanın hem yukarı hem aşağı yönde gerçekleşebildiği iletim dokusudur.',
    'floem (soymuk borusu)',
  ),
  (
    'Yaprak ve genç gövdenin dış yüzeyini örten, genellikle tek sıra hücreden oluşan örtü '
        'dokusudur.',
    'epidermis',
  ),
  (
    'Yüzeyindeki mumsu kütikula tabakasıyla su kaybını azaltan örtü dokusudur.',
    'epidermis',
  ),
  (
    'İki bekçi hücresi arasındaki açıklıktan gaz alışverişini ve terlemeyi sağlar.',
    'stoma',
  ),
  (
    'Bekçi hücreleri kloroplast taşır; turgor değişimiyle açılıp kapanır.',
    'stoma',
  ),
  (
    'Kök epidermis hücrelerinin uzantılarıdır; su ve mineral emilim yüzeyini artırır.',
    'emici tüyler',
  ),
  (
    'Kök ucunu örterek toprakta ilerlerken uç meristemi korur.',
    'kök şapkası (kaliptra)',
  ),
  (
    'Odunsu gövdelerde epidermisin yerini alan, ölü ve süberinli hücrelerden oluşan örtü '
        'dokusudur.',
    'mantar doku (periderm)',
  ),
  (
    'Mantar dokuda gaz alışverişini sağlayan açıklıklardır.',
    'lentisel (kovucuk)',
  ),
  (
    'Yaprak kenarlarından suyun sıvı hâlde atılmasını (damlama) sağlayan su stomalarıdır.',
    'hidatot',
  ),
  (
    'Genç gövde ve yaprak saplarında, çeperlerinin köşeleri kalınlaşmış canlı hücrelerle destek '
        'sağlar.',
    'kollenkima',
  ),
  (
    'Çeperinde lignin biriken ölü hücrelerden oluşur; armuttaki taş hücreleri bu dokuya '
        'aittir.',
    'sklerenkima',
  ),
  ('Bitkiyi toprağa tutturur; topraktan su ve mineral emer.', 'kök'),
  ('Havuç ve şeker pancarında besin depolayan organdır.', 'kök'),
  (
    'Yaprak, çiçek ve meyveleri taşır; kök ile yapraklar arasında madde iletimini sağlar.',
    'gövde',
  ),
  (
    'Patates yumrusu, bu organın toprak altında besin depolayan bir biçimidir.',
    'gövde',
  ),
  ('Fotosentezin ve terlemenin en çok gerçekleştiği organdır.', 'yaprak'),
  (
    'Soğanın besin depolayan etli katmanları bu organın değişmiş biçimidir.',
    'yaprak',
  ),
  (
    'Kaktüslerde su kaybını azaltan dikenler bu organın değişmiş biçimidir.',
    'yaprak',
  ),
];

final _bitkiDokuAilesi = lmSirali(
  'bl_bitki_doku',
  'Bitki dokuları ve kök, gövde, yaprağın görevleri',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) => _olgu(
    i,
    _bitkiDoku,
    eslestirme:
        'Bu bilgilerin ait olduğu bitki dokuları ya da organları sırasıyla hangi '
        'seçenekte doğru verilmiştir?',
    oncul: (y) => 'Bu bilgilerden hangileri “$y” için doğrudur?',
    aciklama: (x) =>
        'Birinci bilgi ${x[0].$2}, ikinci bilgi ${x[1].$2}, üçüncü bilgi '
        '${x[2].$2} için doğrudur.',
  ),
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 19. Bitki hormonları ─────────────────────────────

const _bitkiHormon = <(String, String)>[
  (
    'Işık alan taraftan gölge tarafa geçerek gövdenin ışığa doğru bükülmesine neden olur.',
    'oksin',
  ),
  (
    'Tepe tomurcuğunda üretilerek yan tomurcukların gelişmesini baskılar (tepe baskınlığı).',
    'oksin',
  ),
  ('Çeliklerin kesik ucunda kök oluşumunu uyarır.', 'oksin'),
  (
    'Çit bitkilerinin tepe tomurcukları budandığında yan dalların gelişmesi bu hormonun etkisinin '
        'kalkmasıyla açıklanır.',
    'oksin',
  ),
  (
    'Gül çeliklerinin kök salmasını hızlandırmak için çelik uçlarına uygulanır.',
    'oksin',
  ),
  (
    'Yatay konuma getirilen bir fidenin kökünün aşağı, gövdesinin yukarı bükülmesinde dengesiz '
        'dağılımı etkilidir.',
    'oksin',
  ),
  (
    'Yüksek derişimdeki sentetik biçimleri geniş yapraklı yabani otları öldürmek için '
        'kullanılır.',
    'oksin',
  ),
  (
    'Meyvelerin olgunlaşmadan dökülmesini geciktirmek için kullanılır.',
    'oksin',
  ),
  ('Köklerde üretilir; hücre bölünmesini (sitokinezi) uyarır.', 'sitokinin'),
  (
    'Koparılmış yaprakların sararmasını (yaşlanmasını) geciktirir.',
    'sitokinin',
  ),
  (
    'Yan tomurcukların gelişmesini uyararak tepe baskınlığına karşı etki eder.',
    'sitokinin',
  ),
  (
    'Doku kültüründe hücre bölünmesini artırmak için besi ortamına eklenir.',
    'sitokinin',
  ),
  (
    'Kesme çiçeklerin ve yaprakların daha uzun süre taze kalmasını sağlar.',
    'sitokinin',
  ),
  ('Köklerde üretilip ksilemle gövdeye taşınır.', 'sitokinin'),
  (
    'Hücre bölünmesini uyardığı için meristemlerde ve gelişen meyvelerde miktarı fazladır.',
    'sitokinin',
  ),
  (
    'Boğum aralarının uzamasını sağlayarak cüce bitkilerin boylanmasına neden olur.',
    'giberellin',
  ),
  (
    'Tohumdaki uyku hâlini (dormansiyi) kırarak çimlenmeyi başlatır.',
    'giberellin',
  ),
  (
    'Çekirdeksiz üzüm tanelerinin irileşmesi için üzüm bağlarına püskürtülür.',
    'giberellin',
  ),
  (
    'Arpa tohumlarının çimlenmesini hızlandırmak için malt üretiminde kullanılır.',
    'giberellin',
  ),
  (
    'Cüce bezelye fidelerine uygulandığında fidelerin normal boya ulaşmasını sağlar.',
    'giberellin',
  ),
  (
    'Çimlenen tohumda nişastayı parçalayan amilaz enziminin üretimini uyarır.',
    'giberellin',
  ),
  (
    'Kuraklıkta yapraklarda miktarı artarak stomaların kapanmasını sağlar.',
    'absisik asit',
  ),
  (
    'Tohum ve tomurcukların uyku (dormansi) hâline geçmesini sağlar.',
    'absisik asit',
  ),
  ('Sonbaharda tomurcukların kış uykusuna girmesini sağlar.', 'absisik asit'),
  ('Uygun koşullar oluşmadan tohumun çimlenmesini engeller.', 'absisik asit'),
  ('Su stresi sırasında büyümeyi yavaşlatan hormondur.', 'absisik asit'),
  (
    'Olumsuz çevre koşullarında tohum ve tomurcukların uyku hâlini sürdürmesini sağlar.',
    'absisik asit',
  ),
  ('Gaz hâlinde bulunan bitki hormonudur.', 'etilen'),
  ('Meyvelerin olgunlaşmasını hızlandırır.', 'etilen'),
  (
    'Kapalı bir kapta olgun elmanın yanındaki ham muzların daha çabuk olgunlaşmasına neden '
        'olur.',
    'etilen',
  ),
  (
    'Yeşilken toplanıp depolanan muzları olgunlaştırmak için depoya verilir.',
    'etilen',
  ),
  (
    'Bir sepetteki tek bir çürük meyvenin diğer meyvelerin de çabuk olgunlaşmasına yol açmasında '
        'etkilidir.',
    'etilen',
  ),
  (
    'Ham toplanan domateslerin taşındıktan sonra kızarıp olgunlaşmasını sağlar.',
    'etilen',
  ),
];

final _bitkiHormonAilesi = lmSirali(
  'bl_bitki_hormon',
  'Bitki hormonlarının etkileri ve kullanımları',
  Topic.biology,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) => _olgu(
    i,
    _bitkiHormon,
    eslestirme:
        'Bu bilgilerle ilgili bitki hormonları sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
    oncul: (y) => 'Bu bilgilerden hangileri $y hormonuyla ilgilidir?',
    aciklama: (x) =>
        'Birinci bilgi ${x[0].$2}, ikinci bilgi ${x[1].$2}, üçüncü bilgi '
        '${x[2].$2} hormonuyla ilgilidir.',
  ),
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);

// ───────────────────────────── 20. Bitkilerde hareket ─────────────────────────────

const _hareketTuru = [
  'fototropizma',
  'gravitropizma',
  'tigmotropizma',
  'kemotropizma',
  'sismonasti',
  'fotonasti',
  'termonasti',
];
const _hareketYuklem = [
  'fototropizmadır',
  'gravitropizmadır',
  'tigmotropizmadır',
  'kemotropizmadır',
  'sismonastidir',
  'fotonastidir',
  'termonastidir',
];
// Türün uyarısı: 0 ışık, 1 yer çekimi, 2 dokunma, 3 kimyasal madde, 4 sıcaklık.
const _hareketUyari = [0, 1, 2, 3, 2, 0, 4];
const _uyariAdi = [
  'ışık',
  'yer çekimi',
  'dokunma',
  'kimyasal madde',
  'sıcaklık',
];

// (hareket, tür, yön: 1 pozitif, −1 negatif, 0 nasti)
const _bitkiHareketi = <(String, int, int)>[
  (
    'Pencere önündeki saksı bitkisinin gövdesinin pencereye doğru eğilmesi',
    0,
    1,
  ),
  ('Bir kutunun tek açıklığından giren ışığa doğru fidelerin uzaması', 0, 1),
  ('Ayçiçeği fidelerinin ışığın geldiği yöne doğru bükülmesi', 0, 1),
  ('Kökün ışık kaynağının ters yönüne doğru büyümesi', 0, -1),
  ('Tohumdan çıkan kökün yer çekimi yönünde aşağı doğru büyümesi', 1, 1),
  (
    'Tohumdan çıkan gövdenin yer çekimine ters yönde yukarı doğru büyümesi',
    1,
    -1,
  ),
  ('Yan yatırılan bir saksıdaki bitkinin kökünün aşağı doğru kıvrılması', 1, 1),
  (
    'Yan yatırılan bir saksıdaki bitkinin gövdesinin yukarı doğru kıvrılması',
    1,
    -1,
  ),
  ('Fasulye gövdesinin dokunduğu bir sırığa sarılarak yükselmesi', 2, 1),
  ('Asma sülüklerinin dokundukları tele sarılması', 2, 1),
  ('Bezelye sülüklerinin dokundukları desteğe sarılması', 2, 1),
  ('Kabak sülüklerinin dokundukları desteğe sarılması', 2, 1),
  ('Sarılıcı bitkilerin dallarının destek çevresinde dolanarak büyümesi', 2, 1),
  ('Polen tüpünün dişicik borusu içinde yumurtalığa doğru büyümesi', 3, 1),
  ('Kökün topraktaki mineral bakımından zengin bölgeye doğru büyümesi', 3, 1),
  (
    'Kökün topraktaki zehirli bir kimyasal maddeden uzaklaşacak yönde büyümesi',
    3,
    -1,
  ),
  ('Küstüm otu yapraklarının dokunulunca hızla kapanması', 4, 0),
  ('Küstüm otu yaprakçıklarının sarsıldığında katlanması', 4, 0),
  ('Küstüm otu yapraklarının üzerine su damlası düşünce kapanması', 4, 0),
  ('Akşam sefası çiçeklerinin ışık şiddeti azalınca açılması', 5, 0),
  (
    'Bazı çiçeklerin ışık şiddetine bağlı olarak sabah açılıp akşam kapanması',
    5,
    0,
  ),
  ('Lale çiçeklerinin ortam sıcaklığı artınca açılması', 6, 0),
  ('Lale çiçeklerinin ortam sıcaklığı düşünce kapanması', 6, 0),
  ('Çiğdem çiçeklerinin sıcak ortamda açılıp soğukta kapanması', 6, 0),
];

const _hareketSorulari = [
  'Bu hareketlerden hangileri tropizmadır?',
  'Bu hareketlerden hangileri nastidir?',
  'Bu hareketlerden hangilerinde etkili olan uyarı ışıktır?',
  'Bu hareketlerden hangilerinde etkili olan uyarı yer çekimidir?',
  'Bu hareketlerden hangilerinde etkili olan uyarı dokunma ya da sarsıntıdır?',
  'Bu hareketlerden hangilerinde etkili olan uyarı kimyasal maddedir?',
  'Bu hareketlerden hangilerinde etkili olan uyarı sıcaklıktır?',
  'Bu hareketlerden hangileri uyarıya doğru gerçekleşen pozitif bir tropizmadır?',
  'Bu hareketlerden hangileri uyarıdan uzaklaşan negatif bir tropizmadır?',
];

bool _hareketDeger(int q, int k) {
  final (_, t, y) = _bitkiHareketi[k];
  return switch (q) {
    0 => t <= 3,
    1 => t >= 4,
    2 => _hareketUyari[t] == 0,
    3 => _hareketUyari[t] == 1,
    4 => _hareketUyari[t] == 2,
    5 => _hareketUyari[t] == 3,
    6 => _hareketUyari[t] == 4,
    7 => y == 1,
    _ => y == -1,
  };
}

final _hareketAdaylari = _adaylar(
  _bitkiHareketi.length,
  _hareketSorulari.length,
  _hareketDeger,
  sinif: (k) => _hareketTuru[_bitkiHareketi[k].$2],
);

String _hareketCumle((String, int, int) e) {
  final (ad, t, y) = e;
  final yon = y == 1 ? 'pozitif ' : (y == -1 ? 'negatif ' : '');
  return '${_bas(ad)} $yon${_hareketYuklem[t]} (uyarı: ${_uyariAdi[_hareketUyari[t]]}).';
}

final _bitkiHareketAilesi = lmSirali(
  'bl_bitki_hareket',
  'Bitkilerde tropizma ve nasti hareketleri',
  Topic.biology,
  Difficulty.easy,
  BloomLevel.anlama,
  (i) {
    final (a, b, c, q) = _yay(_hareketAdaylari, i, lmAileBoyu);
    final d = ucluDizilimler[i % 6];
    final xk = [
      for (final t in d) [a, b, c][t],
    ];
    final x = [for (final k in xk) _bitkiHareketi[k]];
    final liste = _liste([for (final e in x) e.$1]);
    final aciklama =
        '${x.map(_hareketCumle).join(' ')} Tropizmada hareketin yönü uyarının '
        'geldiği yöne bağlıdır; nastide bağlı değildir.';
    if (q < 0) {
      return _esle(
        '${liste}Bu bitki hareketlerinin türleri sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
        [for (final e in x) _hareketTuru[e.$2]],
        i ~/ 6,
        aciklama,
      );
    }
    return _oncullu(
      '$liste${_hareketSorulari[q]}',
      [for (final k in xk) _hareketDeger(q, k)],
      i,
      aciklama,
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Biyoloji',
);
