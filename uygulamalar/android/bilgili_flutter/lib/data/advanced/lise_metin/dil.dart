// Lise metin bankası · Dil alanı: Türk dili ve edebiyatı (10 aile) ile lise
// İngilizcesi (10 aile). Kökler elle yazılmış tablolardan, üçlü seçkilerden ve
// parça birleşimlerinden kurulur; her aile 5.000 ayrı vaka üretir.
import 'ortak.dart';

// ───────────────────────────── Ortak yardımcılar ─────────────────────────────

String _uc(List<String> x) => 'I. ${x[0]}\nII. ${x[1]}\nIII. ${x[2]}';

/// Tablodan [i] numaralı üçlü seçkiyi alır ve sıra numarasına bağlı dizer.
List<T> _dizili<T>(List<T> tablo, int i) {
  final u = kombinasyon(tablo, 3, i);
  final d = ucluDizilimler[i % 6];
  return [u[d[0]], u[d[1]], u[d[2]]];
}

/// [n] ardışık sıra numarasını tablonun bütün üçlü seçkilerine yayar.
List<T> _yayili<T>(List<T> tablo, int j, int n) {
  final toplam = kombinasyonSayisi(tablo.length, 3);
  if (toplam < n) throw StateError('Yetersiz seçki: $toplam < $n');
  final u = kombinasyon(tablo, 3, j * toplam ~/ n, spread: false);
  final d = ucluDizilimler[j % 6];
  return [u[d[0]], u[d[1]], u[d[2]]];
}

/// Tabloyu, art arda gelen ögeler farklı kümelerden olacak biçimde yeniden
/// sıralar; adım, uzunlukla aralarında asal seçilir.
List<T> _serpistir<T>(List<T> tablo, int kume) {
  final n = tablo.length;
  var adim = n ~/ kume + 1;
  while (adim.gcd(n) != 1) {
    adim++;
  }
  return [for (var k = 0; k < n; k++) tablo[k * adim % n]];
}

/// [t] sırasındaki değerden farklı değerler; tablodaki yakın komşular önce.
List<String> _komsular(List<String> degerler, int t) {
  final out = <String>[];
  for (var k = 1; k < degerler.length; k++) {
    for (final j in [t + k, t - k]) {
      if (j < 0 || j >= degerler.length) continue;
      final v = degerler[j];
      if (v != degerler[t] && !out.contains(v)) out.add(v);
    }
  }
  return out;
}

/// [dogru] dışındaki etiketler; önce [once] (tipik karıştırma), sonra kalanlar.
List<String> _digerleri(
  List<String> havuz,
  String dogru,
  int kay, [
  List<String> once = const [],
]) {
  final kalan = [
    for (final e in havuz)
      if (e != dogru && !once.contains(e)) e,
  ];
  final k = kalan.isEmpty ? 0 : kay % kalan.length;
  return [
    ...once.where((e) => e != dogru),
    ...kalan.sublist(k),
    ...kalan.sublist(0, k),
  ];
}

/// [i] ve [tuz] için belirlenimci 32 bitlik karma (murmur3 karıştırıcısı).
/// Çeldirici seçimini vakanın tablo koordinatlarından bağımsız kılar;
/// çarpımlar 2⁵³ altında kalacak biçimde 16 bitlik parçalarla yapılır.
int _karma(int i, int tuz) {
  var x = (i * 40503 + tuz * 2654435 + 0x2545F491) & 0xffffffff;
  x ^= x >> 16;
  x = _carp32(x, 0x85EBCA6B);
  x ^= x >> 13;
  x = _carp32(x, 0xC2B2AE35);
  x ^= x >> 16;
  return x;
}

int _carp32(int a, int b) =>
    ((a & 0xffff) * b + (((a >> 16) * b & 0xffff) << 16)) & 0xffffffff;

/// Sıralı üçlü yanıt. [yanlis] her konum için kesin yanlış adayları taşır
/// (önce tipik karıştırmalar). Her konum için ilk [genislik] aday içinden
/// bir yanlış etiket seçilir; her çeldirici anahtarın iki konumunu bu
/// etiketlerle değiştirir (110, 101, 011 deseni). Böylece her iki seçenek
/// tam iki konumda ayrışır ve her konumda doğru etiket iki seçenekte,
/// yanlış etiket öteki iki seçenekte görünür: konum çoğunluğu, ortak öge ya
/// da benzerlik anahtarı göstermez. [tekrarsiz] doğruysa aynı etiketi iki
/// konumda taşıyan seçenek kurulmaz (her konumun yanıtı ayrı bir eserse böyle
/// bir seçenek kendi kendini eler). [agirlik] verilirse (bkz. [_dengeAgirlik])
/// yanlış etiket bütün aday listesinden ağırlığıyla orantılı seçilir; böylece
/// bir etiket çeldiricide doğru yanıttaki sıklığıyla görünür ve vakalar
/// boyunca “genellikle doğru” olmaz. [boyDengeli] doğruysa yanlış etiketler,
/// anahtardan uzun çeldirici sayısı vakadan vakaya 0 … 3 arasında eşit
/// dağılacak biçimde seçilir (uzun yanlış biçimleri az olan ailelerde anahtar
/// en uzun seçenek olmasın diye).
AdvancedItem _sirali(
  String kok,
  List<String> dogru,
  List<List<String>> yanlis,
  String aciklama,
  int i, {
  bool tekrarsiz = false,
  int genislik = 3,
  bool boyDengeli = false,
  Map<String, double>? agirlik,
}) {
  String yaz(List<String> v) => v.join(' – ');
  List<String> secenekler(List<String> w) => [
    yaz([w[0], w[1], dogru[2]]),
    yaz([w[0], dogru[1], w[2]]),
    yaz([dogru[0], w[1], w[2]]),
  ];
  if (boyDengeli) {
    final aday = [
      for (var p = 0; p < 3; p++)
        [
          for (final s in yanlis[p])
            if (s != dogru[p] && (!tekrarsiz || !dogru.contains(s))) s,
        ].take(genislik).toList(),
    ];
    final hedef = _karma(i, 17) % 4, boy = yaz(dogru).length;
    var enIyi = <List<String>>[], fark = 4;
    for (final a in aday[0]) {
      for (final b in aday[1]) {
        for (final c in aday[2]) {
          if (tekrarsiz && (a == b || a == c || b == c)) continue;
          final w = [a, b, c];
          final uzun = secenekler(w).where((x) => x.length > boy).length;
          final f = (uzun - hedef).abs();
          if (f < fark) {
            fark = f;
            enIyi = [];
          }
          if (f == fark) enIyi.add(w);
        }
      }
    }
    if (enIyi.isEmpty) throw StateError('Yanlış aday yok: $kok');
    return secenekli(
      kok,
      yaz(dogru),
      secenekler(enIyi[_karma(i, 18) % enIyi.length]),
      aciklama,
    );
  }
  final w = <String>[];
  for (var p = 0; p < 3; p++) {
    final aday = [
      for (final s in yanlis[p])
        if (s != dogru[p] &&
            (!tekrarsiz || (!dogru.contains(s) && !w.contains(s))))
          s,
    ];
    if (aday.isEmpty) throw StateError('Yanlış aday yok: $kok');
    String? secilen;
    if (agirlik != null) {
      double a(String s) => agirlik[s] ?? 0.05;
      var r =
          _karma(i, 11 + p) /
          4294967296 *
          aday.fold<double>(0, (t, s) => t + a(s));
      for (final s in aday) {
        r -= a(s);
        if (r < 0) {
          secilen = s;
          break;
        }
      }
      secilen ??= aday.last;
    }
    w.add(
      secilen ??
          aday[_karma(i, 11 + p) %
              (aday.length < genislik ? aday.length : genislik)],
    );
  }
  return secenekli(kok, yaz(dogru), secenekler(w), aciklama);
}

/// Yanlış etiket ağırlıkları. [kayitlar] ailenin tablosundaki her kayıt için
/// (doğru etiket, o kayıtta çeldiriciye yazılabilecek etiketler) taşır.
/// Çeldirici etiket adaylar arasından ağırlığıyla orantılı seçildiğinde her
/// etiketin çeldiricide beklenen görünme sayısı doğru yanıttaki sayısına eşit
/// olacak biçimde ağırlıklar yinelemeli orantılı uydurmayla bulunur.
Map<String, double> _dengeAgirlik(List<(String, List<String>)> kayitlar) {
  final dogru = <String, double>{};
  for (final (d, _) in kayitlar) {
    dogru[d] = (dogru[d] ?? 0) + 1;
  }
  final v = {
    for (final (_, y) in kayitlar)
      for (final s in y) s: 1.0,
  };
  for (var tur = 0; tur < 300; tur++) {
    final say = <String, double>{};
    for (final (_, y) in kayitlar) {
      final t = y.fold<double>(0, (a, s) => a + v[s]!);
      for (final s in y) {
        say[s] = (say[s] ?? 0) + v[s]! / t;
      }
    }
    for (final s in v.keys.toList()) {
      final x = v[s]! * (1 + (dogru[s] ?? 0) / say[s]!) / 2;
      v[s] = x < 0.05 ? 0.05 : (x > 20 ? 20 : x);
    }
  }
  return v;
}

/// [havuz] içinden [dogru] ve [disi] dışında kalan etiketler.
List<String> _haric(
  List<String> havuz,
  String dogru, [
  List<String> disi = const [],
]) => [
  for (final s in havuz)
    if (s != dogru && !disi.contains(s)) s,
];

const _kumeAdi = {
  1: 'Yalnız I',
  2: 'Yalnız II',
  4: 'Yalnız III',
  3: 'I ve II',
  5: 'I ve III',
  6: 'II ve III',
  7: 'I, II ve III',
};

/// Dört seçenekteki (tek öncüllü, iki öncüllü, üç öncüllü) küme sayıları.
const _desenler = [
  (3, 1, 0),
  (3, 0, 1),
  (2, 2, 0),
  (2, 1, 1),
  (1, 3, 0),
  (1, 2, 1),
  (0, 3, 1),
];

/// Anahtar yedi kümeye eşit dağılıyorsa: dört seçenek yedi kümeden rastgele
/// seçilmiş gibi dağılır (desen sıklıkları C(3, a)·C(3, b)·C(1, c)).
const _desenEsit = [3, 1, 9, 9, 3, 9, 1];

/// “Hangileri?” sorusu. [maske] doğru numaraları bit olarak taşır (bit 0 = I).
/// Dört seçeneğin desen dağılımı ([agirlik], [_desenler] sırasıyla) ailedeki
/// anahtar boylarına göre seçilir: önce anahtarın boyunu içeren bir desen
/// (ağırlığı × o boydaki seçenek sayısı), sonra her boyda kümeler karma ile.
/// Ağırlıklar, desende her boydan beklenen seçenek sayısı anahtarın o boyda
/// olma olasılığının dört katı olacak biçimde kurulduğundan seçeneklerin boyu,
/// öge çoğunluğu ya da benzerliği anahtarı göstermez.
AdvancedItem _hangileri(
  String kok,
  int maske,
  String aciklama,
  int i, [
  List<int> agirlik = _desenEsit,
]) {
  assert(maske >= 1 && maske <= 7);
  const sinif = [
    <int>[],
    [1, 2, 4],
    [3, 5, 6],
    [7],
  ];
  int adet((int, int, int) d, int b) => b == 1 ? d.$1 : (b == 2 ? d.$2 : d.$3);
  final boy = (maske & 1) + (maske >> 1 & 1) + (maske >> 2 & 1);
  final pay = [
    for (var k = 0; k < _desenler.length; k++)
      agirlik[k] * adet(_desenler[k], boy),
  ];
  var r = _karma(i, 21) % pay.fold<int>(0, (t, x) => t + x);
  var k = 0;
  while (r >= pay[k]) {
    r -= pay[k];
    k++;
  }
  final secilen = <int>[];
  for (var b = 1; b <= 3; b++) {
    final aday = [
      for (final m in sinif[b])
        if (m != maske) m,
    ];
    final gerek = adet(_desenler[k], b) - (b == boy ? 1 : 0);
    final bas = aday.isEmpty ? 0 : _karma(i, 30 + b) % aday.length;
    for (var j = 0; j < gerek; j++) {
      secilen.add(aday[(bas + j) % aday.length]);
    }
  }
  return secenekli(kok, _kumeAdi[maske]!, [
    for (final m in secilen) _kumeAdi[m]!,
  ], aciklama);
}

/// Tek seçenekli sorularda aday çeldirici üçlülerinden (her biri anahtarla
/// birlikte bir etmen deseni kurar) birini seçer: anahtarın tek başına en uzun
/// seçenek olmadığı üçlüler önceliklidir, aralarından biri karma ile seçilir.
List<String> _desenSec(String dogru, List<List<String>> desenler, int i) {
  final uygun = [
    for (final d in desenler)
      if (d.any((x) => x.length >= dogru.length)) d,
  ];
  final havuz = uygun.isEmpty ? desenler : uygun;
  return havuz[_karma(i, 41) % havuz.length];
}

/// Üç ögeden [hedef] etiketini taşıyanların maskesi.
int _maske(List<String> etiketler, String hedef) {
  var m = 0;
  for (var p = 0; p < 3; p++) {
    if (etiketler[p] == hedef) m |= 1 << p;
  }
  return m;
}

// ───────────────────────────── 1 · Ses olayları ─────────────────────────────

const _yum = 'ünsüz yumuşaması';
const _ben = 'ünsüz benzeşmesi';
const _dus = 'ünlü düşmesi';
const _dar = 'ünlü daralması';
const _tur = 'ünsüz türemesi';
const _sesHavuzu = [_yum, _ben, _dus, _dar, _tur];

// (oluşum, ses olayı, gerekçe)
const _sesOlaylari = [
  ('kitap + ı → kitabı', _yum, 'p → b'),
  ('ağaç + ı → ağacı', _yum, 'ç → c'),
  ('kanat + ı → kanadı', _yum, 't → d'),
  ('çocuk + u → çocuğu', _yum, 'k → ğ'),
  ('dolap + a → dolaba', _yum, 'p → b'),
  ('kâğıt + ı → kâğıdı', _yum, 't → d'),
  ('renk + i → rengi', _yum, 'k → g'),
  ('yaprak + ı → yaprağı', _yum, 'k → ğ'),
  ('ilaç + ı → ilacı', _yum, 'ç → c'),
  ('umut + u → umudu', _yum, 't → d'),
  ('cevap + ı → cevabı', _yum, 'p → b'),
  ('borç + u → borcu', _yum, 'ç → c'),
  ('yurt + u → yurdu', _yum, 't → d'),
  ('köpek + i → köpeği', _yum, 'k → ğ'),
  ('sokak + da → sokakta', _ben, 'd → t'),
  ('kitap + cı → kitapçı', _ben, 'c → ç'),
  ('ağaç + dan → ağaçtan', _ben, 'd → t'),
  ('sınıf + da → sınıfta', _ben, 'd → t'),
  ('simit + ci → simitçi', _ben, 'c → ç'),
  ('balık + cı → balıkçı', _ben, 'c → ç'),
  ('uçak + dan → uçaktan', _ben, 'd → t'),
  ('sepet + de → sepette', _ben, 'd → t'),
  ('çalış- + gan → çalışkan', _ben, 'g → k'),
  ('seç- + gin → seçkin', _ben, 'g → k'),
  ('unut- + gan → unutkan', _ben, 'g → k'),
  ('süt + cü → sütçü', _ben, 'c → ç'),
  ('otobüs + de → otobüste', _ben, 'd → t'),
  ('park + da → parkta', _ben, 'd → t'),
  ('ağız + ı → ağzı', _dus, 'ı düşer'),
  ('burun + u → burnu', _dus, 'u düşer'),
  ('oğul + u → oğlu', _dus, 'u düşer'),
  ('gönül + ü → gönlü', _dus, 'ü düşer'),
  ('alın + ı → alnı', _dus, 'ı düşer'),
  ('karın + ı → karnı', _dus, 'ı düşer'),
  ('boyun + u → boynu', _dus, 'u düşer'),
  ('omuz + u → omzu', _dus, 'u düşer'),
  ('şehir + i → şehri', _dus, 'i düşer'),
  ('fikir + i → fikri', _dus, 'i düşer'),
  ('ömür + ü → ömrü', _dus, 'ü düşer'),
  ('akıl + ı → aklı', _dus, 'ı düşer'),
  ('resim + i → resmi', _dus, 'i düşer'),
  ('isim + i → ismi', _dus, 'i düşer'),
  ('göğüs + ü → göğsü', _dus, 'ü düşer'),
  ('beyin + i → beyni', _dus, 'i düşer'),
  ('bekle- + yor → bekliyor', _dar, 'e → i'),
  ('söyle- + yor → söylüyor', _dar, 'e → ü'),
  ('anla- + yor → anlıyor', _dar, 'a → ı'),
  ('oyna- + yor → oynuyor', _dar, 'a → u'),
  ('başla- + yor → başlıyor', _dar, 'a → ı'),
  ('dinle- + yor → dinliyor', _dar, 'e → i'),
  ('iste- + yor → istiyor', _dar, 'e → i'),
  ('ağla- + yor → ağlıyor', _dar, 'a → ı'),
  ('özle- + yor → özlüyor', _dar, 'e → ü'),
  ('yaşa- + yor → yaşıyor', _dar, 'a → ı'),
  ('gelme- + yor → gelmiyor', _dar, 'e → i'),
  ('sorma- + yor → sormuyor', _dar, 'a → u'),
  ('de- + yor → diyor', _dar, 'e → i'),
  ('ye- + yor → yiyor', _dar, 'e → i'),
  ('his + i → hissi', _tur, 's türer'),
  ('hak + ı → hakkı', _tur, 'k türer'),
  ('af + ı → affı', _tur, 'f türer'),
  ('zan + ı → zannı', _tur, 'n türer'),
  ('hat + ı → hattı', _tur, 't türer'),
  ('sır + ı → sırrı', _tur, 'r türer'),
  ('zam + ı → zammı', _tur, 'm türer'),
  ('şık + ı → şıkkı', _tur, 'k türer'),
  ('haz + ı → hazzı', _tur, 'z türer'),
  ('üs + ü → üssü', _tur, 's türer'),
  ('his + etmek → hissetmek', _tur, 's türer'),
  ('af + etmek → affetmek', _tur, 'f türer'),
  ('zan + etmek → zannetmek', _tur, 'n türer'),
  ('hal + etmek → halletmek', _tur, 'l türer'),
];

final _sesSerpik = _serpistir(_sesOlaylari, 5);
final _sesAgirlik = _dengeAgirlik([
  for (final e in _sesOlaylari) (e.$2, _haric(_sesHavuzu, e.$2)),
]);

// “Hangileri” sorularında anahtarın üçte ikisi tek öncüllüdür; desen
// ağırlıkları seçeneklerin boy dağılımını buna göre kurar (bkz. _hangileri).
const _desenSes = [72, 7, 31, 8, 1, 1, 0];

const _sesKarisan = {
  _yum: [_ben],
  _ben: [_yum, _tur],
  _dus: [_dar],
  _dar: [_dus],
  _tur: [_ben],
};

final _sesOlayi = lmSirali(
  'tde_ses_olayi',
  'Ses olayları: sözcüklerdeki ses değişimleri',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final x = _dizili(_sesSerpik, i);
    final etiket = [for (final e in x) e.$2];
    final liste = _uc([for (final e in x) e.$1]);
    final aciklama =
        '${[for (final e in x) '${e.$1}: ${e.$2} (${e.$3})'].join('; ')}.';
    if (i.isOdd) {
      final hedef = etiket[i ~/ 2 % 3];
      return _hangileri(
        '$liste\nNumaralanmış sözcüklerin hangilerinin oluşumunda $hedef '
        'görülür?',
        _maske(etiket, hedef),
        aciklama,
        i,
        _desenSes,
      );
    }
    return _sirali(
      '$liste\nNumaralanmış sözcüklerin oluşumunda görülen ses olayları '
      'sırasıyla hangi seçenekte doğru verilmiştir?',
      etiket,
      [
        for (var p = 0; p < 3; p++)
          _digerleri(_sesHavuzu, etiket[p], i + p, _sesKarisan[etiket[p]]!),
      ],
      aciklama,
      i,
      agirlik: _sesAgirlik,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ──────────────────────────── 2 · Cümlenin ögeleri ───────────────────────────

// (cümle başında, cümle içinde)
const _ogeOzneler = [
  ('Zeynep', 'Zeynep'),
  ('Mert', 'Mert'),
  ('Ablam', 'ablam'),
  ('Komşumuzun kızı', 'komşumuzun kızı'),
  ('Okulun müdürü', 'okulun müdürü'),
  ('Annem', 'annem'),
  ('Yaşlı adam', 'yaşlı adam'),
  ('Elif\'in dayısı', 'Elif\'in dayısı'),
  ('Küçük kardeşim', 'küçük kardeşim'),
  ('Kasabanın yeni doktoru', 'kasabanın yeni doktoru'),
];

const _ogeZarflar = [
  ('Dün akşam', 'dün akşam'),
  ('Sabah erkenden', 'sabah erkenden'),
  ('Geçen hafta', 'geçen hafta'),
  ('Az önce', 'az önce'),
  ('Öğleden sonra', 'öğleden sonra'),
  ('Geçen pazar', 'geçen pazar'),
  ('İki gün önce', 'iki gün önce'),
  ('Bu sabah', 'bu sabah'),
  ('Dün', 'dün'),
  ('Akşamüstü', 'akşamüstü'),
];

// (dolaylı tümleç, sorusu, nesne, yüklem)
const _ogeKaliplar = [
  ('arkadaşına', 'kime?', 'eski fotoğrafları', 'gösterdi'),
  ('kütüphaneye', 'nereye?', 'iki kitap', 'bağışladı'),
  ('kuzenine', 'kime?', 'taze meyveler', 'götürdü'),
  ('masanın üstüne', 'nereye?', 'renkli bir örtü', 'serdi'),
  ('çantasından', 'nereden?', 'kalın bir defter', 'çıkardı'),
  ('pazardan', 'nereden?', 'taze sebzeler', 'aldı'),
  ('teyzesine', 'kime?', 'uzun bir mektup', 'yazdı'),
  ('duvara', 'nereye?', 'büyük bir tablo', 'astı'),
  ('misafirlere', 'kime?', 'sıcak çay', 'ikram etti'),
  ('yeğenine', 'kime?', 'ilginç bir masal', 'anlattı'),
  ('bahçeye', 'nereye?', 'iki fidan', 'dikti'),
  ('rafa', 'nereye?', 'temiz tabakları', 'dizdi'),
  ('çocuklara', 'kime?', 'renkli balonlar', 'dağıttı'),
  ('köydeki evden', 'nereden?', 'eski sandığı', 'getirdi'),
  ('depoya', 'nereye?', 'ağır kolileri', 'taşıdı'),
  ('hasta komşusuna', 'kime?', 'sıcak bir çorba', 'pişirdi'),
  ('okulun panosuna', 'nereye?', 'duyuruyu', 'astı'),
  ('kapının önüne', 'nereye?', 'boş saksıları', 'bıraktı'),
  ('çekmecede', 'nerede?', 'eski bir anahtar', 'buldu'),
  ('salonun penceresine', 'nereye?', 'yeni perdeleri', 'taktı'),
];

const _ogeAdlari = ['özne', 'zarf tümleci', 'dolaylı tümleç', 'nesne', 'yüklem'];

final _cumleOgesi = lmSirali(
  'tde_cumle_ogesi',
  'Cümlenin ögeleri: tırnak içindeki ögeyi bulma',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.analiz,
  (i) {
    final hedef = i % 5;
    final k = i ~/ 5 % 20, z = i ~/ 100 % 10;
    final s = i ~/ 1000 * 2 + (k + z) % 2;
    final kalip = _ogeKaliplar[k];
    final duzen = (k + z + s) % 3;
    // Parçalar öge sırasına göre: 0 özne, 1 zarf, 2 dolaylı tümleç, 3 nesne,
    // 4 yüklem. Nesne her dizilişte yüklemin hemen önündedir.
    final sira = const [
      [0, 1, 2, 3, 4],
      [1, 0, 2, 3, 4],
      [0, 2, 1, 3, 4],
    ][duzen];
    String parca(int oge, bool basta) => switch (oge) {
      0 => basta ? _ogeOzneler[s].$1 : _ogeOzneler[s].$2,
      1 => basta ? _ogeZarflar[z].$1 : _ogeZarflar[z].$2,
      2 => kalip.$1,
      3 => kalip.$3,
      _ => kalip.$4,
    };
    final sozler = <String>[];
    for (var p = 0; p < 5; p++) {
      final metin = parca(sira[p], p == 0);
      sozler.add(sira[p] == hedef ? '“$metin”' : metin);
    }
    final dogru = _ogeAdlari[hedef];
    return secenekli(
      '${sozler.join(' ')}.\nBu cümlede tırnak içinde verilen söz ya da söz '
      'öbeği cümlenin hangi ögesidir?',
      dogru,
      _digerleri(_ogeAdlari, dogru, i ~/ 5),
      'Yüklem: ${kalip.$4}. Özne (kim?): ${_ogeOzneler[s].$2}. Zarf tümleci '
      '(ne zaman?): ${_ogeZarflar[z].$2}. Dolaylı tümleç (${kalip.$2}): '
      '${kalip.$1}. Nesne (ne? / neyi?): ${kalip.$3}. Tırnak içindeki bölüm '
      'bu nedenle şu ögedir: $dogru.',
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ───────────────────────────── 3 · Sözcük türleri ────────────────────────────

// (cümle, tırnak içindeki sözcüğün türü, gerekçe)
const _sozcukTurleri = [
  ('Bahçedeki “ağaç” bu yıl erken çiçek açtı.', 'isim', 'bir varlığın adı'),
  ('Masanın üzerindeki “defter” kardeşime ait.', 'isim', 'bir nesnenin adı'),
  ('Çocukların “sevinci” herkesi mutlu etti.', 'isim', 'bir duygunun adı'),
  ('“Deniz” bugün çok dalgalıydı.', 'isim', 'bir varlığın adı'),
  ('Yolun sonundaki “köprü” geçen yıl onarıldı.', 'isim', 'bir yapının adı'),
  ('Kütüphaneden aldığım “roman” çok sürükleyiciydi.', 'isim', 'bir eserin adı'),
  ('Annemin pişirdiği “çorba” çok lezzetliydi.', 'isim', 'bir yiyeceğin adı'),
  ('“Yeşil” vadide küçük bir köy vardı.', 'sıfat', 'vadi adını niteler'),
  ('“Bu” kitap geçen ay yayımlandı.', 'sıfat', 'kitap adını işaret yoluyla belirtir'),
  ('Sınıfta “üç” öğrenci ödül aldı.', 'sıfat', 'öğrenci adını sayı yönünden belirtir'),
  ('“Bazı” sorular oldukça zordu.', 'sıfat', 'sorular adını belgisiz olarak belirtir'),
  ('“Hangi” filmi izlemek istiyorsun?', 'sıfat', 'film adını soru yoluyla belirtir'),
  ('Sokakta “yaşlı” bir adam yürüyordu.', 'sıfat', 'adam adını niteler'),
  ('Pazardan “taze” meyveler aldık.', 'sıfat', 'meyveler adını niteler'),
  ('“Uzun” yolculuk hepimizi yordu.', 'sıfat', 'yolculuk adını niteler'),
  ('Atlet parkurda “hızlı” koştu.', 'zarf', 'koşma eylemini durum yönünden belirtir'),
  ('Toplantı “yarın” yapılacak.', 'zarf', 'eylemin zamanını belirtir'),
  ('Misafirler “biraz” dinlendi.', 'zarf', 'eylemi miktar yönünden belirtir'),
  ('Öğrenciler sınıfa “sessizce” girdi.', 'zarf', 'girme eylemini durum yönünden belirtir'),
  ('Kardeşim bu dönem “çok” çalıştı.', 'zarf', 'eylemi miktar yönünden belirtir'),
  ('Otobüs durağa “geç” geldi.', 'zarf', 'eylemin zamanını belirtir'),
  ('Asansör az önce “aşağı” indi.', 'zarf', 'eylemin yönünü belirtir'),
  ('Babam işten “erken” döndü.', 'zarf', 'eylemin zamanını belirtir'),
  ('“Ben” bu konuyu daha önce araştırdım.', 'zamir', 'konuşan kişinin yerini tutar'),
  ('“Bunu” masanın üzerine bırakabilirsin.', 'zamir', 'bir nesnenin yerini işaret yoluyla tutar'),
  ('“Kimse” toplantıya geç kalmadı.', 'zamir', 'kişilerin yerini belgisiz olarak tutar'),
  ('Dün akşam bizi “kim” aradı?', 'zamir', 'bir kişinin yerini soru yoluyla tutar'),
  ('“Onlar” yarın köye gidecekler.', 'zamir', 'kişilerin yerini tutar'),
  ('“Herkes” konseri ayakta alkışladı.', 'zamir', 'kişilerin yerini belgisiz olarak tutar'),
  ('Bu işi “kendim” yapmak istiyorum.', 'zamir', 'dönüşlülük zamiridir'),
  ('“Şunu” da sepete koyar mısın?', 'zamir', 'bir nesnenin yerini işaret yoluyla tutar'),
  ('“Hepsi” sınavı başarıyla geçti.', 'zamir', 'adların yerini belgisiz olarak tutar'),
  ('Kardeşim “için” güzel bir hediye aldım.', 'edat', 'tek başına anlamı yoktur, amaç ilgisi kurar'),
  ('Eve otobüs “ile” döndük.', 'edat', 'araç ilgisi kurar, “ve” anlamı taşımaz'),
  ('Akşama “kadar” ders çalıştık.', 'edat', 'tek başına anlamı yoktur, sınır ilgisi kurar'),
  ('Pamuk “gibi” bulutlar gökyüzünü kaplamıştı.', 'edat', 'benzerlik ilgisi kurar'),
  ('Sabaha “doğru” yağmur başladı.', 'edat', 'zaman yönünden yaklaşma ilgisi kurar'),
  ('Yağmura “rağmen” maç ertelenmedi.', 'edat', 'karşıtlık ilgisi kurar'),
  ('Öğretmene “göre” bu soru kolaydı.', 'edat', 'görelik ilgisi kurar'),
  ('Senin “kadar” çalışkan bir öğrenci görmedim.', 'edat', 'karşılaştırma ilgisi kurar'),
  ('Sinemaya gidecektik “ama” bilet bulamadık.', 'bağlaç', 'iki cümleyi karşıtlık ilgisiyle bağlar'),
  ('Kitabı aldım “ve” hemen okumaya başladım.', 'bağlaç', 'iki cümleyi birbirine bağlar'),
  ('Çok çalıştı “fakat” istediği sonucu alamadı.', 'bağlaç', 'iki cümleyi karşıtlık ilgisiyle bağlar'),
  ('Dışarı çıkmadık, “çünkü” kar yağıyordu.', 'bağlaç', 'iki cümleyi neden ilgisiyle bağlar'),
  ('Bugün uğrayabilirsin “veya” yarın arayabilirsin.', 'bağlaç', 'iki cümleyi seçenek ilgisiyle bağlar'),
  ('Annem “ile” babam çarşıya gitti.', 'bağlaç', 'iki adı bağlar, yerine “ve” getirilebilir'),
  ('Erken yattı, “oysa” hiç uykusu yoktu.', 'bağlaç', 'iki cümleyi karşıtlık ilgisiyle bağlar'),
  ('Çocuklar bahçede top “oynuyor”.', 'fiil', 'bir eylemi bildirir'),
  ('Akşam yemeğinden sonra kitap “okudum”.', 'fiil', 'bir eylemi bildirir'),
  ('Yarın sabah erkenden yola “çıkacağız”.', 'fiil', 'bir eylemi bildirir'),
  ('Kuşlar güneye doğru “uçtu”.', 'fiil', 'bir eylemi bildirir'),
  ('Kardeşim her sabah süt “içer”.', 'fiil', 'bir eylemi bildirir'),
  ('Bu şiiri mutlaka “ezberlemelisin”.', 'fiil', 'bir eylemi bildirir'),
  ('Rüzgâr pencereyi “açmış”.', 'fiil', 'bir eylemi bildirir'),
];

final _turSerpik = _serpistir(_sozcukTurleri, 7);

// Her türdeki sözcüğün öğrencilerce gerçekten karıştırıldığı türler; çeldirici
// etiketler yalnız bunlardan seçilir. Ad soylu sözcükler cümledeki görevine
// göre birbirine geçebildiği için birbiriyle (isim–sıfat–zamir, sıfat–zarf),
// edat bağlaç ve zarfla, bağlaç edatla, çekimli fiil adlarını taşıdığı
// fiilimsilerle (isim-fiil, sıfat-fiil, zarf-fiil) karıştırılır. “Deniz” için
// “bağlaç”, “ve” için “fiil” gibi hiçbir öğrencinin yapmayacağı eşleştirmeler
// yazılmaz: her çeldiricide iki konum yanlış olduğundan böyle bir etiket
// seçenekleri tek başına eler.
const _turKarisan = {
  'isim': ['sıfat', 'zamir'],
  'sıfat': ['zarf', 'isim'],
  'zarf': ['sıfat', 'isim'],
  'zamir': ['sıfat', 'isim'],
  'edat': ['bağlaç', 'zarf'],
  'bağlaç': ['edat'],
  'fiil': ['isim', 'sıfat', 'zarf'],
};

// Türünün genel listesinden ayrılan sözcükler (tırnak içindeki biçimiyle):
// işaret, belgisiz ve soru sıfatları zamirle; “çok” ve “aşağı” (-den çok,
// -den aşağı) edatla; “biraz” zamirle; “geç” “geç-”, “göre” “gör-” fiiliyle;
// “Hepsi” “hep” zarfıyla; “doğru” sıfat ve zarf olan biçimiyle; “çünkü” ve
// “oysa” zarfla karıştırılır; -mış, -er, -acak, -me ekli çekimli fiiller aynı
// ekli sıfat-fiil ve isim-fiillerle karışır. Kimi sözcüklerde genel listedeki
// tür hiç karıştırılmadığı için yazılmaz (“Ben” için sıfat, “çok” için isim).
const _turKarisanOzel = {
  'Bu': ['zamir'],
  'Bazı': ['zamir'],
  'Hangi': ['zamir'],
  'Yeşil': ['isim'],
  'üç': ['isim'],
  'yaşlı': ['isim'],
  'hızlı': ['sıfat'],
  'sessizce': ['sıfat'],
  'çok': ['sıfat', 'edat'],
  'aşağı': ['sıfat', 'isim', 'edat'],
  'erken': ['sıfat'],
  'biraz': ['sıfat', 'zamir'],
  'geç': ['sıfat', 'fiil'],
  'Ben': ['isim'],
  'Hepsi': ['sıfat', 'isim', 'zarf'],
  'doğru': ['sıfat', 'zarf'],
  'göre': ['zarf', 'fiil'],
  'çünkü': ['edat', 'zarf'],
  'oysa': ['edat', 'zarf'],
  'açmış': ['sıfat'],
  'içer': ['sıfat'],
  'çıkacağız': ['sıfat', 'isim'],
  'ezberlemelisin': ['isim'],
};

List<String> _turYanlis((String, String, String) e) {
  final s = e.$1;
  return _turKarisanOzel[s.substring(s.indexOf('“') + 1, s.indexOf('”'))] ??
      _turKarisan[e.$2]!;
}

final _turAgirlik = _dengeAgirlik([
  for (final e in _sozcukTurleri) (e.$2, _turYanlis(e)),
]);

final _sozcukTuru = lmSirali(
  'tde_sozcuk_turu',
  'Sözcük türleri: tırnak içindeki sözcüğün türü',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.analiz,
  (i) {
    final x = _dizili(_turSerpik, i);
    final etiket = [for (final e in x) e.$2];
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nBu cümlelerde tırnak içinde verilen '
      'sözcüklerin türleri sırasıyla hangi seçenekte doğru verilmiştir?',
      etiket,
      [for (final e in x) _turYanlis(e)],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede ${x[p].$2}: ${x[p].$3}'].join('; ')}.',
      i,
      agirlik: _turAgirlik,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ────────────────────────────── 4 · Fiil çekimi ──────────────────────────────

const _kipHavuzu = [
  'görülen geçmiş zaman',
  'duyulan geçmiş zaman',
  'şimdiki zaman',
  'gelecek zaman',
  'geniş zaman',
  'gereklilik kipi',
  'dilek-şart kipi',
  'istek kipi',
  'emir kipi',
];
const _kisiHavuzu = [
  '1. tekil kişi',
  '2. tekil kişi',
  '3. tekil kişi',
  '1. çoğul kişi',
  '2. çoğul kişi',
  '3. çoğul kişi',
];

// (kip sırası, kişi sıraları, çekimli biçimler)
const _cekimTablosu = [
  (0, [0, 1, 2, 3, 4, 5], ['geldim', 'geldin', 'geldi', 'geldik', 'geldiniz', 'geldiler']),
  (0, [0, 1, 2, 3, 4, 5], ['okudum', 'okudun', 'okudu', 'okuduk', 'okudunuz', 'okudular']),
  (1, [0, 1, 2, 3, 4, 5], ['yazmışım', 'yazmışsın', 'yazmış', 'yazmışız', 'yazmışsınız', 'yazmışlar']),
  (1, [0, 1, 2, 3, 4, 5], ['görmüşüm', 'görmüşsün', 'görmüş', 'görmüşüz', 'görmüşsünüz', 'görmüşler']),
  (2, [0, 1, 2, 3, 4, 5], ['bekliyorum', 'bekliyorsun', 'bekliyor', 'bekliyoruz', 'bekliyorsunuz', 'bekliyorlar']),
  (2, [0, 1, 2, 3, 4, 5], ['koşuyorum', 'koşuyorsun', 'koşuyor', 'koşuyoruz', 'koşuyorsunuz', 'koşuyorlar']),
  (3, [0, 1, 2, 3, 4, 5], ['soracağım', 'soracaksın', 'soracak', 'soracağız', 'soracaksınız', 'soracaklar']),
  (3, [0, 1, 2, 3, 4, 5], ['dinleyeceğim', 'dinleyeceksin', 'dinleyecek', 'dinleyeceğiz', 'dinleyeceksiniz', 'dinleyecekler']),
  (4, [0, 1, 2, 3, 4, 5], ['severim', 'seversin', 'sever', 'severiz', 'seversiniz', 'severler']),
  (4, [0, 1, 2, 3, 4, 5], ['konuşurum', 'konuşursun', 'konuşur', 'konuşuruz', 'konuşursunuz', 'konuşurlar']),
  (5, [0, 1, 2, 3, 4, 5], ['çalışmalıyım', 'çalışmalısın', 'çalışmalı', 'çalışmalıyız', 'çalışmalısınız', 'çalışmalılar']),
  (5, [0, 1, 2, 3, 4, 5], ['gitmeliyim', 'gitmelisin', 'gitmeli', 'gitmeliyiz', 'gitmelisiniz', 'gitmeliler']),
  (6, [0, 1, 2, 3, 4, 5], ['bilsem', 'bilsen', 'bilse', 'bilsek', 'bilseniz', 'bilseler']),
  (6, [0, 1, 2, 3, 4, 5], ['baksam', 'baksan', 'baksa', 'baksak', 'baksanız', 'baksalar']),
  (7, [0, 1, 3, 4], ['anlayayım', 'anlayasın', 'anlayalım', 'anlayasınız']),
  (7, [0, 1, 3, 4], ['oturayım', 'oturasın', 'oturalım', 'oturasınız']),
  (8, [1, 2, 4, 5], ['söyle', 'söylesin', 'söyleyin', 'söylesinler']),
  (8, [1, 2, 4, 5], ['dinlen', 'dinlensin', 'dinlenin', 'dinlensinler']),
];

// (çekimli fiil, kip, kişi)
final _cekimler = _serpistir([
  for (final t in _cekimTablosu)
    for (var j = 0; j < t.$3.length; j++)
      (t.$3[j], _kipHavuzu[t.$1], _kisiHavuzu[t.$2[j]]),
], 9);
final _kisiAgirlik = _dengeAgirlik([
  for (final e in _cekimler) (e.$3, _haric(_kisiHavuzu, e.$3)),
]);

const _kipKarisan = {
  'görülen geçmiş zaman': ['duyulan geçmiş zaman'],
  'duyulan geçmiş zaman': ['görülen geçmiş zaman'],
  'şimdiki zaman': ['geniş zaman'],
  'gelecek zaman': ['istek kipi'],
  'geniş zaman': ['şimdiki zaman'],
  'gereklilik kipi': ['emir kipi'],
  'dilek-şart kipi': ['istek kipi'],
  'istek kipi': ['dilek-şart kipi', 'gereklilik kipi'],
  'emir kipi': ['gereklilik kipi', 'geniş zaman'],
};

// Kimi kaynaklar “-alım, -ayım” biçimlerini emir kipinde saydığı için istek
// ile emir kipleri birbirinin çeldiricisi yapılmaz.
const _kipDisi = {
  'istek kipi': ['emir kipi'],
  'emir kipi': ['istek kipi'],
};

final _kipAgirlik = _dengeAgirlik([
  for (final e in _cekimler)
    (e.$2, _haric(_kipHavuzu, e.$2, _kipDisi[e.$2] ?? const [])),
]);

final _fiilCekimi = lmSirali(
  'tde_fiil_cekimi',
  'Fiil çekimi: çekimli fiilin kipi ve kişisi',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final x = _dizili(_cekimler, i);
    final liste = _uc([for (final e in x) e.$1]);
    final aciklama =
        '${[for (final e in x) '${e.$1}: ${e.$2}, ${e.$3}'].join('; ')}.';
    if (i.isOdd) {
      final kisi = [for (final e in x) e.$3];
      return _sirali(
        '$liste\nNumaralanmış çekimli fiillerin kişileri (şahısları) sırasıyla '
        'hangi seçenekte doğru verilmiştir?',
        kisi,
        [
          for (var p = 0; p < 3; p++)
            _digerleri(_kisiHavuzu, kisi[p], i + p, [
              // Tekil–çoğul karışıklığı en sık yapılan hatadır.
              _kisiHavuzu[(_kisiHavuzu.indexOf(kisi[p]) + 3) % 6],
            ]),
        ],
        aciklama,
        i,
        agirlik: _kisiAgirlik,
      );
    }
    final kip = [for (final e in x) e.$2];
    return _sirali(
      '$liste\nNumaralanmış çekimli fiillerin kipleri sırasıyla hangi '
      'seçenekte doğru verilmiştir?',
      kip,
      [
        for (var p = 0; p < 3; p++)
          _digerleri(
            [
              for (final k in _kipHavuzu)
                if (!(_kipDisi[kip[p]] ?? const <String>[]).contains(k)) k,
            ],
            kip[p],
            i + p,
            _kipKarisan[kip[p]]!,
          ),
      ],
      aciklama,
      i,
      agirlik: _kipAgirlik,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ─────────────────────── 5 · Yapı bakımından sözcükler ───────────────────────

const _yapiHavuzu = ['basit', 'türemiş', 'birleşik'];

// (sözcük, yapı, çözümleme)
const _yapilar = [
  ('kitaplar', 'basit', 'kitap + lar, yalnız çekim eki almıştır'),
  ('evde', 'basit', 'ev + de, yalnız çekim eki almıştır'),
  ('gözümüz', 'basit', 'göz + ümüz, yalnız çekim eki almıştır'),
  ('yoldan', 'basit', 'yol + dan, yalnız çekim eki almıştır'),
  ('kalemim', 'basit', 'kalem + im, yalnız çekim eki almıştır'),
  ('masada', 'basit', 'masa + da, yalnız çekim eki almıştır'),
  ('dağlar', 'basit', 'dağ + lar, yalnız çekim eki almıştır'),
  ('kapıyı', 'basit', 'kapı + yı, yalnız çekim eki almıştır'),
  ('kuşlar', 'basit', 'kuş + lar, yalnız çekim eki almıştır'),
  ('denize', 'basit', 'deniz + e, yalnız çekim eki almıştır'),
  ('bahçede', 'basit', 'bahçe + de, yalnız çekim eki almıştır'),
  ('çiçek', 'basit', 'yapım eki almamış köktür'),
  ('ağaç', 'basit', 'yapım eki almamış köktür'),
  ('balık', 'basit', 'yapım eki almamış köktür'),
  ('bulut', 'basit', 'yapım eki almamış köktür'),
  ('pencere', 'basit', 'yapım eki almamış köktür'),
  ('yıldız', 'basit', 'yapım eki almamış köktür'),
  ('elma', 'basit', 'yapım eki almamış köktür'),
  ('kitaplık', 'türemiş', 'kitap + lık, yapım eki almıştır'),
  ('gözlük', 'türemiş', 'göz + lük, yapım eki almıştır'),
  ('evli', 'türemiş', 'ev + li, yapım eki almıştır'),
  ('yolcu', 'türemiş', 'yol + cu, yapım eki almıştır'),
  ('tuzluk', 'türemiş', 'tuz + luk, yapım eki almıştır'),
  ('sevgi', 'türemiş', 'sev- + gi, yapım eki almıştır'),
  ('bilgi', 'türemiş', 'bil- + gi, yapım eki almıştır'),
  ('yazı', 'türemiş', 'yaz- + ı, yapım eki almıştır'),
  ('çalışkan', 'türemiş', 'çalış- + kan, yapım eki almıştır'),
  ('simitçi', 'türemiş', 'simit + çi, yapım eki almıştır'),
  ('susuz', 'türemiş', 'su + suz, yapım eki almıştır'),
  ('korkak', 'türemiş', 'kork- + ak, yapım eki almıştır'),
  ('sözlük', 'türemiş', 'söz + lük, yapım eki almıştır'),
  ('balıkçı', 'türemiş', 'balık + çı, yapım eki almıştır'),
  ('silgi', 'türemiş', 'sil- + gi, yapım eki almıştır'),
  ('kalemlik', 'türemiş', 'kalem + lik, yapım eki almıştır'),
  ('duygu', 'türemiş', 'duy- + gu, yapım eki almıştır'),
  ('seçim', 'türemiş', 'seç- + im, yapım eki almıştır'),
  ('güzellik', 'türemiş', 'güzel + lik, yapım eki almıştır'),
  ('kışlık', 'türemiş', 'kış + lık, yapım eki almıştır'),
  ('hanımeli', 'birleşik', 'hanım + eli'),
  ('aslanağzı', 'birleşik', 'aslan + ağzı'),
  ('kuşburnu', 'birleşik', 'kuş + burnu'),
  ('gecekondu', 'birleşik', 'gece + kondu'),
  ('imambayıldı', 'birleşik', 'imam + bayıldı'),
  ('kahvaltı', 'birleşik', 'kahve + altı'),
  ('pazartesi', 'birleşik', 'pazar + ertesi'),
  ('bilgisayar', 'birleşik', 'bilgi + sayar'),
  ('ayakkabı', 'birleşik', 'ayak + kabı'),
  ('başöğretmen', 'birleşik', 'baş + öğretmen'),
  ('buzdolabı', 'birleşik', 'buz + dolabı'),
  ('yeryüzü', 'birleşik', 'yer + yüzü'),
  ('gökyüzü', 'birleşik', 'gök + yüzü'),
  ('anayasa', 'birleşik', 'ana + yasa'),
  ('atasözü', 'birleşik', 'ata + sözü'),
  ('bugün', 'birleşik', 'bu + gün'),
  ('sivrisinek', 'birleşik', 'sivri + sinek'),
  ('açıkgöz', 'birleşik', 'açık + göz'),
  ('kuşkonmaz', 'birleşik', 'kuş + konmaz'),
  ('dedikodu', 'birleşik', 'dedi + kodu'),
  ('cumartesi', 'birleşik', 'cuma + ertesi'),
  ('ilkbahar', 'birleşik', 'ilk + bahar'),
  ('başkent', 'birleşik', 'baş + kent'),
  ('denizaltı', 'birleşik', 'deniz + altı'),
  ('ayçiçeği', 'birleşik', 'ay + çiçeği'),
  ('gözyaşı', 'birleşik', 'göz + yaşı'),
];

final _yapiSerpik = _serpistir(_yapilar, 3);
final _yapiAgirlik = _dengeAgirlik([
  for (final e in _yapilar) (e.$2, _haric(_yapiHavuzu, e.$2)),
]);

// “Hangileri” sorularındaki anahtar boylarına göre desen ağırlıkları.
const _desenYapi = [15, 3, 40, 25, 12, 22, 2];

final _yapi = lmSirali(
  'tde_yapi',
  'Yapı bakımından sözcükler: basit, türemiş, birleşik',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final x = _dizili(_yapiSerpik, i);
    final etiket = [for (final e in x) e.$2];
    final liste = _uc([for (final e in x) e.$1]);
    final aciklama =
        '${[for (final e in x) '${e.$1}: ${e.$2} (${e.$3})'].join('; ')}.';
    if (i.isOdd) {
      final hedef = etiket[i ~/ 2 % 3];
      return _hangileri(
        '$liste\nNumaralanmış sözcüklerden hangileri yapı bakımından $hedef '
        'sözcüktür?',
        _maske(etiket, hedef),
        aciklama,
        i,
        _desenYapi,
      );
    }
    return _sirali(
      '$liste\nNumaralanmış sözcüklerin yapı bakımından türleri sırasıyla '
      'hangi seçenekte doğru verilmiştir?',
      etiket,
      [for (var p = 0; p < 3; p++) _digerleri(_yapiHavuzu, etiket[p], i + p)],
      aciklama,
      i,
      agirlik: _yapiAgirlik,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ───────────────────────────── 6 · Cümle türleri ─────────────────────────────

// (cümle, yüklem, isim cümlesi mi, devrik mi, olumsuz mu)
const _cumleler = [
  ('Bu yıl kış çok soğuktu.', 'soğuktu', true, false, false),
  ('Bahçedeki güller rengârenkti.', 'rengârenkti', true, false, false),
  ('Kardeşim bu okulun en çalışkan öğrencisidir.', 'öğrencisidir', true, false, false),
  ('Kütüphane bugün oldukça kalabalıktı.', 'kalabalıktı', true, false, false),
  ('Bu romanın yazarı çok ünlüdür.', 'ünlüdür', true, false, false),
  ('Dolapta yeterince süt var.', 'var', true, false, false),
  ('Bu soru zor değildi.', 'zor değildi', true, false, true),
  ('Evde ekmek yok.', 'yok', true, false, true),
  ('Hava bugün soğuk değil.', 'soğuk değil', true, false, true),
  ('Salonda boş koltuk yoktu.', 'yoktu', true, false, true),
  ('Yeni komşumuz buralı değilmiş.', 'buralı değilmiş', true, false, true),
  ('Bu film çocuklara uygun değildir.', 'uygun değildir', true, false, true),
  ('Çok güzeldi dün akşamki konser.', 'güzeldi', true, true, false),
  ('Pek tatlıdır bu bahçenin elmaları.', 'tatlıdır', true, true, false),
  ('Oldukça uzundu köye giden yol.', 'uzundu', true, true, false),
  ('Çok kalabalıktı sabahki otobüs.', 'kalabalıktı', true, true, false),
  ('Sessizdir bu sokağın akşamları.', 'sessizdir', true, true, false),
  ('Hepimizin dostuydu yaşlı bekçi.', 'dostuydu', true, true, false),
  ('Kolay değildi bu yolculuk.', 'kolay değildi', true, true, true),
  ('Yoktu evde bir damla su.', 'yoktu', true, true, true),
  ('Uzak değildir köyümüz şehre.', 'uzak değildir', true, true, true),
  ('Pahalı değildi vitrindeki ceket.', 'pahalı değildi', true, true, true),
  ('Yorgun değilim bugün.', 'yorgun değilim', true, true, true),
  ('Boş değildi arka sıralar.', 'boş değildi', true, true, true),
  ('Çocuklar bahçede top oynuyor.', 'oynuyor', false, false, false),
  ('Annem akşam yemeğini hazırladı.', 'hazırladı', false, false, false),
  ('Tren istasyona tam vaktinde ulaştı.', 'ulaştı', false, false, false),
  ('Öğrenciler müzeyi ilgiyle gezdi.', 'gezdi', false, false, false),
  ('Yarın sabah erkenden köye gideceğiz.', 'gideceğiz', false, false, false),
  ('Dedem her akşam gazete okur.', 'okur', false, false, false),
  ('Otobüs bu sabah zamanında gelmedi.', 'gelmedi', false, false, true),
  ('Kardeşim ödevini henüz bitirmedi.', 'bitirmedi', false, false, true),
  ('Bu hafta sinemaya gitmeyeceğiz.', 'gitmeyeceğiz', false, false, true),
  ('Yağmur bütün gün dinmedi.', 'dinmedi', false, false, true),
  ('Sorunun yanıtını kimse bilemedi.', 'bilemedi', false, false, true),
  ('Kütüphaneden aldığım kitabı okumadım.', 'okumadım', false, false, true),
  ('Geldi beklediğimiz misafirler.', 'geldi', false, true, false),
  ('Çok sevdim bu şehri.', 'sevdim', false, true, false),
  ('Koşarak çıktı çocuklar bahçeye.', 'çıktı', false, true, false),
  ('Anlattı bütün olanları arkadaşına.', 'anlattı', false, true, false),
  ('Yağdı sabaha kadar kar.', 'yağdı', false, true, false),
  ('Özledim köyümün serin akşamlarını.', 'özledim', false, true, false),
  ('Unutmadım o günleri.', 'unutmadım', false, true, true),
  ('Gelmedi beklediğimiz mektup.', 'gelmedi', false, true, true),
  ('Bitmedi bu yolun yokuşları.', 'bitmedi', false, true, true),
  ('Sevmezdi kalabalık caddeleri.', 'sevmezdi', false, true, true),
  ('Duymadım kapının sesini.', 'duymadım', false, true, true),
  ('Açmadı o yıl bahçedeki erik ağacı.', 'açmadı', false, true, true),
];

final _cumleSerpik = _serpistir(_cumleler, 8);

const _rakam = ['I', 'II', 'III'];

final _cumleTuru = lmSirali(
  'tde_cumle_turu',
  'Cümle türleri: yüklemin türü, yeri ve anlam',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final x = _dizili(_cumleSerpik, i);
    final liste = _uc([for (final e in x) e.$1]);
    final olcut = i % 3;
    final adlar = const [
      ['fiil cümlesi', 'isim cümlesi'],
      ['kurallı cümle', 'devrik cümle'],
      ['olumlu cümle', 'olumsuz cümle'],
    ][olcut];
    bool deger((String, String, bool, bool, bool) e) =>
        olcut == 0 ? e.$3 : (olcut == 1 ? e.$4 : e.$5);
    final etiket = [for (final e in x) adlar[deger(e) ? 1 : 0]];
    final soru = const [
      'yüklemin türüne göre',
      'yüklemin yerine göre',
      'anlamına göre',
    ][olcut];
    String gerekce((String, String, bool, bool, bool) e) => switch (olcut) {
      0 =>
        e.$3
            ? 'yüklem (“${e.$2}”) ad soylu bir sözdür, isim cümlesi'
            : 'yüklem (“${e.$2}”) çekimli bir fiildir, fiil cümlesi',
      1 =>
        e.$4
            ? 'yüklem (“${e.$2}”) sonda değildir, devrik cümle'
            : 'yüklem (“${e.$2}”) sondadır, kurallı cümle',
      _ =>
        e.$5
            ? 'yüklem (“${e.$2}”) yargının gerçekleşmediğini bildirir, olumsuz cümle'
            : 'yüklem (“${e.$2}”) yargının gerçekleştiğini bildirir, olumlu cümle',
    };
    return _sirali(
      '$liste\nNumaralanmış cümleler $soru sırasıyla nasıl adlandırılır?',
      etiket,
      [
        for (var p = 0; p < 3; p++) [adlar[deger(x[p]) ? 0 : 1]],
      ],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede ${gerekce(x[p])}'].join('; ')}.',
      i,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ───────────────────────────── 7 · Yazım kuralları ───────────────────────────

// (doğru yazım, sık yapılan yanlış yazım)
const _yazimlar = [
  ('herkes', 'herkez'),
  ('yalnız', 'yanlız'),
  ('yanlış', 'yalnış'),
  ('şoför', 'şöför'),
  ('orijinal', 'orjinal'),
  ('egzoz', 'egsoz'),
  ('kılavuz', 'klavuz'),
  ('tıraş', 'traş'),
  ('sürpriz', 'süpriz'),
  ('entelektüel', 'entellektüel'),
  ('kirpik', 'kiprik'),
  ('kibrit', 'kirbit'),
  ('makine', 'makina'),
  ('meyve', 'meyva'),
  ('eczane', 'ezcane'),
  ('laboratuvar', 'laboratuar'),
  ('tişört', 'tişort'),
  ('birkaç', 'bir kaç'),
  ('birçok', 'bir çok'),
  ('hiçbir', 'hiç bir'),
  ('her şey', 'herşey'),
  ('bir şey', 'birşey'),
  ('pek çok', 'pekçok'),
  ('metot', 'metod'),
  ('koreografi', 'kareografi'),
  ('mahcup', 'mahçup'),
  ('unvan', 'ünvan'),
  ('penguen', 'penguin'),
  ('kolonya', 'kolanya'),
  ('ambulans', 'ambülans'),
  ('aksesuar', 'aksesuvar'),
  ('dinozor', 'dinazor'),
  ('doküman', 'döküman'),
  ('espri', 'espiri'),
  ('fasulye', 'fasülye'),
  ('inisiyatif', 'insiyatif'),
  ('maydanoz', 'maydonoz'),
  ('motosiklet', 'motorsiklet'),
  ('pantolon', 'pantalon'),
  ('pardösü', 'pardesü'),
  ('poğaça', 'poaça'),
  ('sandviç', 'sandöviç'),
  ('stajyer', 'stajer'),
  ('zürafa', 'zürefa'),
  ('çikolata', 'çukulata'),
  ('kravat', 'kıravat'),
  ('kulüp', 'klüp'),
  ('gardırop', 'gardrop'),
  ('tren', 'tiren'),
  ('profesör', 'proföser'),
  ('erozyon', 'erezyon'),
  ('şarj', 'şarz'),
  ('eşofman', 'eşortman'),
  ('mozaik', 'mozayik'),
  ('vejetaryen', 'vejeteryan'),
  ('çünkü', 'çünki'),
  ('antrenman', 'antreman'),
  ('psikoloji', 'pisikoloji'),
  ('restoran', 'restorant'),
  ('apartman', 'apartıman'),
  ('çiftçi', 'çifçi'),
  ('aferin', 'aferim'),
];

final _yazim = lmSirali(
  'tde_yazim',
  'Yazım kuralları: yazımı karıştırılan sözcükler',
  Topic.literature,
  Difficulty.easy,
  BloomLevel.hatirlama,
  (i) {
    final x = _dizili(_yazimlar, i);
    final yanlisSorulur = i.isOdd;
    // Sorulan nitelikte (doğru ya da yanlış yazılmış) olan numaralar.
    final hedef = 1 + i ~/ 2 % 7;
    bool dogruYazildi(int p) => ((hedef >> p) & 1 == 1) != yanlisSorulur;
    final gorunen = [
      for (var p = 0; p < 3; p++) dogruYazildi(p) ? x[p].$1 : x[p].$2,
    ];
    return _hangileri(
      '${_uc(gorunen)}\nNumaralanmış sözcüklerden hangilerinin yazımı '
      '${yanlisSorulur ? 'yanlıştır' : 'doğrudur'}?',
      hedef,
      '${[for (var p = 0; p < 3; p++) dogruYazildi(p) ? '${_rakam[p]}. “${x[p].$1}” doğru yazılmıştır' : '${_rakam[p]}. “${x[p].$2}” yanlıştır, doğru yazım “${x[p].$1}” biçimindedir'].join('; ')}.',
      i,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ───────────────────────────── 8 · Söz sanatları ─────────────────────────────

const _tesbih = 'teşbih';
const _teshis = 'teşhis';
const _intak = 'intak';
const _mubalaga = 'mübalağa';
const _tezat = 'tezat';
const _tekrir = 'tekrir';
const _istiare = 'açık istiare';
const _sanatHavuzu = [
  _tesbih,
  _teshis,
  _intak,
  _mubalaga,
  _tezat,
  _tekrir,
  _istiare,
];

const _sanatGerekce = {
  _tesbih: 'iki varlık arasında benzetme ilgisi açıkça kurulmuştur',
  _teshis: 'insan dışındaki varlığa insana özgü bir nitelik verilmiştir',
  _intak: 'insan dışındaki varlık konuşturulmuştur',
  _mubalaga: 'durum olabileceğinden çok büyük gösterilmiştir',
  _tezat: 'karşıt kavramlar bir arada kullanılmıştır',
  _tekrir: 'aynı söz, anlamı pekiştirmek için yinelenmiştir',
  _istiare: 'yalnız kendisine benzetilen söylenmiş, benzeyen anılmamıştır',
};

const _sanatKarisan = {
  _tesbih: [_istiare, _mubalaga],
  _teshis: [_intak, _tesbih],
  _intak: [_istiare, _tekrir],
  _mubalaga: [_tesbih, _tezat],
  _tezat: [_tekrir, _mubalaga],
  _tekrir: [_tezat, _mubalaga],
  _istiare: [_tesbih, _mubalaga],
};

// Her intakta kişileştirme de bulunur; kişileştirme ile eğretileme de
// birbirine yakındır. Bu nedenle aşağıdaki etiketler ilgili örneklerde kesin
// yanlış sayılmaz ve o konuma çeldirici olarak yazılmaz.
const _sanatDisi = {
  _intak: [_teshis],
  _istiare: [_teshis],
  _teshis: [_istiare],
};

// (örnek cümle, söz sanatı)
const _sanatlar = [
  ('Küçük kızın yanakları elma gibi kırmızıydı.', _tesbih),
  ('Göl, sabahları ayna gibi parlıyordu.', _tesbih),
  ('Bebeğin teni pamuk gibi yumuşaktı.', _tesbih),
  ('Kar taneleri kelebek gibi süzülüyordu.', _tesbih),
  ('Buğday tarlaları sarı bir halıyı andırıyordu.', _tesbih),
  ('Annesinin sesi ninni kadar dinlendiriciydi.', _tesbih),
  ('Gökteki bulutlar pamuk yığınlarına benziyordu.', _tesbih),
  ('Yorgun güneş, dağların ardında uykuya daldı.', _teshis),
  ('Söğütler, dere kenarında başlarını eğmiş düşünüyordu.', _teshis),
  ('Küskün bulutlar, şehre sırtını dönüp gitti.', _teshis),
  ('Eski kapı, her açılışında acıyla iç çekiyordu.', _teshis),
  ('Papatyalar, sabah güneşine gülümsüyordu.', _teshis),
  ('Ay, pencereden içeri merakla bakıyordu.', _teshis),
  ('Sonbahar gelince yapraklar ağaçlarla vedalaştı.', _teshis),
  ('Karınca, ağustosböceğine “Biraz da sen çalışsan olmaz mı?” dedi.', _intak),
  ('Dere, kıyısındaki söğüde “Benimle denize gelir misin?” diye sordu.', _intak),
  ('Yaşlı çınar, altında oynayan çocuklara “Gölgem hepinize yeter.” diye seslendi.', _intak),
  ('Kırlangıç, yavrularına “Artık uçma vakti geldi.” dedi.', _intak),
  ('Ay, yıldızlara “Bu gece nöbet bende.” dedi.', _intak),
  ('Küçük fidan, bahçıvana “Bana biraz su verir misin?” dedi.', _intak),
  ('Rüzgâr, kapıya “Aç da içeri gireyim.” diye fısıldadı.', _intak),
  ('O gün seni bin kere aradım.', _mubalaga),
  ('Çantası o kadar ağırdı ki taşırken kolları yere değiyordu.', _mubalaga),
  ('Öyle çok ağladı ki gözyaşlarıyla bütün mahalleyi su bastı.', _mubalaga),
  ('Bir bağırdı, sesinden dağlar yerinden oynadı.', _mubalaga),
  ('O kadar acıkmıştı ki bir fırın ekmeği tek başına yiyebilirdi.', _mubalaga),
  ('Seni kapının önünde bir asır bekledim.', _mubalaga),
  ('Öyle hızlı koştu ki ayakları yere değmedi.', _mubalaga),
  ('Gülerken ağladığımız günleri hiç unutmadım.', _tezat),
  ('Kalabalıkların ortasında yapayalnız kaldım.', _tezat),
  ('Yakın sandığım dostlar, en zor günümde uzak kaldı.', _tezat),
  ('Küçük bir odada büyük hayaller kurardık.', _tezat),
  ('Acı günlerin ardından tatlı haberler geldi.', _tezat),
  ('Zengin sofralarda yoksul gönüller gördüm.', _tezat),
  ('Sevinçle başlayan gün hüzünle bitti.', _tezat),
  ('Yollar, yollar, hep önümde uzanan yollar.', _tekrir),
  ('Bekledim, günlerce bekledim, yılmadan bekledim.', _tekrir),
  ('Yağmur yağıyordu; ince ince, durmadan yağmur yağıyordu.', _tekrir),
  ('Sustum, sustukça sustum; söyleyecek söz kalmadı.', _tekrir),
  ('Köyüm, yeşil köyüm, uzaktaki köyüm hep aklımda.', _tekrir),
  ('Deniz, yine deniz, her yanımız deniz.', _tekrir),
  ('Çalıştı, çalıştı, hiç durmadan çalıştı.', _tekrir),
  ('Takımın aslanları sahaya alkışlarla çıktı.', _istiare),
  ('Gökyüzündeki inciler bu gece pırıl pırıldı.', _istiare),
  ('Annem, kuzusunu her sabah okul kapısına kadar götürür.', _istiare),
  ('Millî takımın en hızlı balığı, yüz metre serbestte altın madalya kazandı.', _istiare),
  ('Sınıfımızın bülbülü, törende iki şarkı söyledi.', _istiare),
  ('Gecenin gümüş tepsisi dağların üstünde yükseldi.', _istiare),
  ('Mahallenin tilkisi, pazarlıkta yine herkesi ikna etti.', _istiare),
];

final _sanatSerpik = _serpistir(_sanatlar, 7);
final _sanatAgirlik = _dengeAgirlik([
  for (final e in _sanatlar)
    (e.$2, _haric(_sanatHavuzu, e.$2, _sanatDisi[e.$2] ?? const [])),
]);

final _sozSanati = lmSirali(
  'tde_soz_sanati',
  'Söz sanatları: örnek cümledeki sanatı belirleme',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.analiz,
  (i) {
    final x = _dizili(_sanatSerpik, i);
    final etiket = [for (final e in x) e.$2];
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde belirgin '
      'olarak görülen söz sanatları sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
      etiket,
      [
        for (var p = 0; p < 3; p++)
          _digerleri(
            [
              for (final s in _sanatHavuzu)
                if (!(_sanatDisi[etiket[p]] ?? const <String>[]).contains(s)) s,
            ],
            etiket[p],
            i + p,
            _sanatKarisan[etiket[p]]!,
          ),
      ],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede ${etiket[p]}: ${_sanatGerekce[etiket[p]]}'].join('; ')}.',
      i,
      agirlik: _sanatAgirlik,
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Edebiyat',
);

// ───────────────────────────── 9 · Yazar ve eser ─────────────────────────────

// (eser, yazar) · Tanzimat'tan Cumhuriyet'e, dönem sırasıyla.
const _eserler = [
  ('Şair Evlenmesi', 'Şinasi'),
  ('İntibah', 'Namık Kemal'),
  ('Cezmi', 'Namık Kemal'),
  ('Vatan yahut Silistre', 'Namık Kemal'),
  ('Taaşşuk-ı Talat ve Fitnat', 'Şemsettin Sami'),
  ('Felatun Bey ile Rakım Efendi', 'Ahmet Mithat Efendi'),
  ('Araba Sevdası', 'Recaizade Mahmut Ekrem'),
  ('Sergüzeşt', 'Samipaşazade Sezai'),
  ('Karabibik', 'Nabizade Nazım'),
  ('Zehra', 'Nabizade Nazım'),
  ('Makber', 'Abdülhak Hamit Tarhan'),
  ('Mai ve Siyah', 'Halit Ziya Uşaklıgil'),
  ('Aşk-ı Memnu', 'Halit Ziya Uşaklıgil'),
  ('Kırık Hayatlar', 'Halit Ziya Uşaklıgil'),
  ('Eylül', 'Mehmet Rauf'),
  ('Rübab-ı Şikeste', 'Tevfik Fikret'),
  ('Haluk\'un Defteri', 'Tevfik Fikret'),
  ('Göl Saatleri', 'Ahmet Haşim'),
  ('Piyale', 'Ahmet Haşim'),
  ('Safahat', 'Mehmet Âkif Ersoy'),
  ('Türkçülüğün Esasları', 'Ziya Gökalp'),
  ('Kızıl Elma', 'Ziya Gökalp'),
  ('Kaşağı', 'Ömer Seyfettin'),
  ('Efruz Bey', 'Ömer Seyfettin'),
  ('Yaban', 'Yakup Kadri Karaosmanoğlu'),
  ('Kiralık Konak', 'Yakup Kadri Karaosmanoğlu'),
  ('Nur Baba', 'Yakup Kadri Karaosmanoğlu'),
  ('Sinekli Bakkal', 'Halide Edib Adıvar'),
  ('Ateşten Gömlek', 'Halide Edib Adıvar'),
  ('Vurun Kahpeye', 'Halide Edib Adıvar'),
  ('Çalıkuşu', 'Reşat Nuri Güntekin'),
  ('Yaprak Dökümü', 'Reşat Nuri Güntekin'),
  ('Yeşil Gece', 'Reşat Nuri Güntekin'),
  ('Memleket Hikâyeleri', 'Refik Halit Karay'),
  ('Sürgün', 'Refik Halit Karay'),
  ('Huzur', 'Ahmet Hamdi Tanpınar'),
  ('Saatleri Ayarlama Enstitüsü', 'Ahmet Hamdi Tanpınar'),
  ('Beş Şehir', 'Ahmet Hamdi Tanpınar'),
  ('Dokuzuncu Hariciye Koğuşu', 'Peyami Safa'),
  ('Fatih-Harbiye', 'Peyami Safa'),
  ('Kuyucaklı Yusuf', 'Sabahattin Ali'),
  ('Kürk Mantolu Madonna', 'Sabahattin Ali'),
  ('İnce Memed', 'Yaşar Kemal'),
  ('Yılanların Öcü', 'Fakir Baykurt'),
  ('Bereketli Topraklar Üzerinde', 'Orhan Kemal'),
  ('Tutunamayanlar', 'Oğuz Atay'),
  ('Aylak Adam', 'Yusuf Atılgan'),
  ('Anayurt Oteli', 'Yusuf Atılgan'),
  ('Çile', 'Necip Fazıl Kısakürek'),
  ('Han Duvarları', 'Faruk Nafiz Çamlıbel'),
  ('Kendi Gök Kubbemiz', 'Yahya Kemal Beyatlı'),
  ('Otuz Beş Yaş', 'Cahit Sıtkı Tarancı'),
  ('Memleketimden İnsan Manzaraları', 'Nâzım Hikmet'),
  ('Semaver', 'Sait Faik Abasıyanık'),
  ('Devlet Ana', 'Kemal Tahir'),
  ('Yorgun Savaşçı', 'Kemal Tahir'),
  ('Küçük Ağa', 'Tarık Buğra'),
  ('Çankaya', 'Falih Rıfkı Atay'),
  ('Zeytindağı', 'Falih Rıfkı Atay'),
  ('Suyu Arayan Adam', 'Şevket Süreyya Aydemir'),
];

final _eserSiralari = _serpistir(
  List<int>.generate(_eserler.length, (k) => k),
  12,
);
final _yazarAdlari = [for (final e in _eserler) e.$2];
// Her eser için, dönemce yakın ama farklı yazarlar (yakından uzağa).
final _yakinYazarlar = [
  for (var t = 0; t < _eserler.length; t++) _komsular(_yazarAdlari, t),
];
final _yazarAgirlik = _dengeAgirlik([
  for (var t = 0; t < _eserler.length; t++)
    (_eserler[t].$2, _yakinYazarlar[t].sublist(0, 6)),
]);

final _yazarEser = lmSirali(
  'tde_yazar_eser',
  'Yazar ve eser eşleştirmesi (Tanzimat–Cumhuriyet)',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) {
    final sira = _dizili(_eserSiralari, i);
    final x = [for (final t in sira) _eserler[t]];
    final aciklama = '${[for (final e in x) '${e.$1}: ${e.$2}'].join('; ')}.';
    if (i.isOdd) {
      final alt = i ~/ 2;
      final yanlisSorulur = alt.isOdd;
      final hedef = 1 + alt ~/ 2 % 7;
      bool dogruEslesti(int p) => ((hedef >> p) & 1 == 1) != yanlisSorulur;
      final satirlar = [
        for (var p = 0; p < 3; p++)
          '${x[p].$1} – '
              '${dogruEslesti(p) ? x[p].$2 : _yakinYazarlar[sira[p]][(alt ~/ 14 + p) % 4]}',
      ];
      return _hangileri(
        '${_uc(satirlar)}\nNumaralanmış eser–yazar eşleştirmelerinden '
        'hangileri ${yanlisSorulur ? 'yanlıştır' : 'doğrudur'}?',
        hedef,
        aciklama,
        i,
      );
    }
    final dogru = [for (final e in x) e.$2];
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış eserlerin yazarları '
      'sırasıyla hangi seçenekte doğru verilmiştir?',
      dogru,
      [for (final t in sira) _yakinYazarlar[t].sublist(0, 6)],
      aciklama,
      i,
      agirlik: _yazarAgirlik,
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Edebiyat',
);

// ──────────────────── 10 · Dönemler, topluluklar ve ilkler ───────────────────

const _tanzimat = 'Tanzimat';
const _servet = 'Servetifünun';
const _fecr = 'Fecriati';
const _milli = 'Millî Edebiyat';
const _hece = 'Beş Hececiler';
const _mesale = 'Yedi Meşaleciler';
const _garip = 'Garip';
const _ikinciYeni = 'İkinci Yeni';
const _hisar = 'Hisarcılar';
const _toplulukHavuzu = [
  _tanzimat,
  _servet,
  _fecr,
  _milli,
  _hece,
  _mesale,
  _garip,
  _ikinciYeni,
  _hisar,
];

const _toplulukKarisan = {
  _tanzimat: [_servet],
  _servet: [_fecr, _tanzimat],
  _fecr: [_servet],
  _milli: [_hece, _fecr],
  _hece: [_mesale],
  _mesale: [_hece, _garip],
  _garip: [_ikinciYeni, _mesale],
  _ikinciYeni: [_garip, _hisar],
  _hisar: [_ikinciYeni, _mesale],
};

// (sanatçı, dönem ya da topluluk, çeldiricide kullanılmayacak tartışmalı adlar)
const _temsilciler = [
  ('Şinasi', _tanzimat, <String>[]),
  ('Namık Kemal', _tanzimat, <String>[]),
  ('Ziya Paşa', _tanzimat, <String>[]),
  ('Ahmet Mithat Efendi', _tanzimat, <String>[]),
  ('Recaizade Mahmut Ekrem', _tanzimat, [_servet]),
  ('Abdülhak Hamit Tarhan', _tanzimat, <String>[]),
  ('Samipaşazade Sezai', _tanzimat, <String>[]),
  ('Nabizade Nazım', _tanzimat, <String>[]),
  ('Tevfik Fikret', _servet, <String>[]),
  ('Cenap Şahabettin', _servet, <String>[]),
  ('Halit Ziya Uşaklıgil', _servet, <String>[]),
  ('Mehmet Rauf', _servet, <String>[]),
  // Ahmet Haşim kimi ders kitaplarında Millî Edebiyat döneminde, o dönemin
  // anlayışı dışında kalan şairler arasında anılır.
  ('Ahmet Haşim', _fecr, [_milli]),
  ('Emin Bülent Serdaroğlu', _fecr, <String>[]),
  ('Tahsin Nahit', _fecr, <String>[]),
  ('Ömer Seyfettin', _milli, <String>[]),
  ('Ziya Gökalp', _milli, <String>[]),
  ('Ali Canip Yöntem', _milli, [_fecr]),
  // İlk şiirleri Servetifünun yıllarında yayımlandığı için o dönemde de anılır.
  ('Mehmet Emin Yurdakul', _milli, [_servet]),
  // Beş Hececiler Millî Edebiyat döneminin içindedir; Halit Fahri gibi kimi
  // üyeler önce Fecriati'ye katılmıştır.
  ('Faruk Nafiz Çamlıbel', _hece, [_milli, _fecr]),
  ('Orhan Seyfi Orhon', _hece, [_milli, _fecr]),
  ('Enis Behiç Koryürek', _hece, [_milli, _fecr]),
  ('Halit Fahri Ozansoy', _hece, [_milli, _fecr]),
  ('Yusuf Ziya Ortaç', _hece, [_milli, _fecr]),
  ('Ziya Osman Saba', _mesale, <String>[]),
  ('Yaşar Nabi Nayır', _mesale, <String>[]),
  ('Sabri Esat Siyavuşgil', _mesale, <String>[]),
  ('Kenan Hulusi Koray', _mesale, <String>[]),
  ('Cevdet Kudret Solok', _mesale, <String>[]),
  ('Vasfi Mahir Kocatürk', _mesale, <String>[]),
  ('Orhan Veli Kanık', _garip, <String>[]),
  ('Melih Cevdet Anday', _garip, <String>[]),
  ('Oktay Rifat Horozcu', _garip, [_ikinciYeni]),
  ('Cemal Süreya', _ikinciYeni, <String>[]),
  ('Edip Cansever', _ikinciYeni, <String>[]),
  ('Turgut Uyar', _ikinciYeni, <String>[]),
  ('İlhan Berk', _ikinciYeni, <String>[]),
  ('Ece Ayhan', _ikinciYeni, <String>[]),
  ('Sezai Karakoç', _ikinciYeni, <String>[]),
  ('Ülkü Tamer', _ikinciYeni, <String>[]),
  ('Mehmet Çınarlı', _hisar, <String>[]),
  ('İlhan Geçer', _hisar, <String>[]),
  ('Mustafa Necati Karaer', _hisar, <String>[]),
  ('Gültekin Samanoğlu', _hisar, <String>[]),
];

// (ilk, eser ya da yayın, sahibi ya da tarihi) · konuca yakın olanlar art arda.
const _ilkler = [
  ('İlk yerli roman', 'Taaşşuk-ı Talat ve Fitnat', 'Şemsettin Sami'),
  ('İlk edebî roman', 'İntibah', 'Namık Kemal'),
  ('İlk tarihî roman', 'Cezmi', 'Namık Kemal'),
  ('İlk realist roman', 'Araba Sevdası', 'Recaizade Mahmut Ekrem'),
  ('İlk köy romanı', 'Karabibik', 'Nabizade Nazım'),
  ('İlk psikolojik roman', 'Eylül', 'Mehmet Rauf'),
  ('İlk çeviri roman', 'Telemak', 'Yusuf Kâmil Paşa çevirisi'),
  ('Batılı anlamda ilk modern hikâyeler', 'Küçük Şeyler', 'Samipaşazade Sezai'),
  ('İlk yerli tiyatro eseri', 'Şair Evlenmesi', 'Şinasi'),
  ('Batı edebiyatından ilk şiir çevirileri', 'Tercüme-i Manzume', 'Şinasi'),
  ('İlk kafiyesiz şiir', 'Validem', 'Abdülhak Hamit Tarhan'),
  ('İlk pastoral şiir', 'Sahra', 'Abdülhak Hamit Tarhan'),
  ('İlk mensur şiir örnekleri', 'Mensur Şiirler', 'Halit Ziya Uşaklıgil'),
  ('İlk antoloji', 'Harabat', 'Ziya Paşa'),
  ('İlk eleştiri eseri', 'Tahrib-i Harabat', 'Namık Kemal'),
  ('İlk edebiyat tarihi', 'Tarih-i Edebiyat-ı Osmaniye', 'Abdülhalim Memduh'),
  ('İlk makale', 'Tercüman-ı Ahval Mukaddimesi', 'Şinasi'),
  ('Türklerin çıkardığı ilk özel gazete', 'Tercüman-ı Ahval', 'Şinasi ve Agâh Efendi'),
  ('İlk resmî gazete', 'Takvim-i Vekayi', '1831'),
  ('İlk yarı resmî gazete', 'Ceride-i Havadis', '1840'),
  ('İlk dergi', 'Vakayi-i Tıbbiye', '1849'),
  ('İlk mizah dergisi', 'Diyojen', 'Teodor Kasap'),
  ('Türkçenin bilinen ilk yazılı belgeleri', 'Orhun Yazıtları', 'Göktürkler'),
  ('Türk dilinin bilinen ilk sözlüğü', 'Divanü Lügati\'t-Türk', 'Kâşgarlı Mahmud'),
  ('Türk edebiyatının ilk mesnevisi', 'Kutadgu Bilig', 'Yusuf Has Hacib'),
  ('Hikmet türünün ilk örnekleri', 'Divan-ı Hikmet', 'Ahmet Yesevi'),
  ('İlk şairler tezkiresi', 'Mecalisü\'n-Nefais', 'Ali Şir Nevai'),
  ('Anı türünün ilk örneği', 'Babürname', 'Babür Şah'),
  ('Gezi yazısı türünün ilk örneği', 'Mir\'atü\'l-Memalik', 'Seydi Ali Reis'),
  ('İlk şehrengiz', 'Şehrengiz-i Edirne', 'Mesihi'),
];

// Bir ilkin yanıtıyla karıştırılması tartışmaya açık olduğu için o ilkin
// konumuna çeldirici olarak yazılmayan eserler.
const _ilkDisi = {
  'İlk makale': ['Tercüman-ı Ahval'],
  // Ceride-i Havadis bir yabancının özel girişimi olduğu için kimi kaynaklarda
  // “ilk özel gazete” diye de geçer.
  'Türklerin çıkardığı ilk özel gazete': [
    'Tercüman-ı Ahval Mukaddimesi',
    'Ceride-i Havadis',
  ],
  'İlk realist roman': ['Karabibik'],
};

final _ilkSiralari = _serpistir(
  List<int>.generate(_ilkler.length, (k) => k),
  6,
);
final _ilkEserleri = [for (final e in _ilkler) e.$2];
final _yakinIlkler = [
  for (var t = 0; t < _ilkler.length; t++) _komsular(_ilkEserleri, t),
];
final _ilkAgirlik = _dengeAgirlik([
  for (var t = 0; t < _ilkler.length; t++)
    (
      _ilkler[t].$2,
      _haric(
        _yakinIlkler[t],
        _ilkler[t].$2,
        _ilkDisi[_ilkler[t].$1] ?? const [],
      ).sublist(0, 6),
    ),
]);

final _temsilciSerpik = _serpistir(_temsilciler, 9);
final _toplulukAgirlik = _dengeAgirlik([
  for (final e in _temsilciler) (e.$2, _haric(_toplulukHavuzu, e.$2, e.$3)),
]);

final _donem = lmSirali(
  'tde_donem',
  'Edebî dönemler, topluluklar ve edebiyatta ilkler',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) {
    final j = i ~/ 2;
    if (i.isOdd) {
      final sira = _yayili(_ilkSiralari, j, 2500);
      final x = [for (final t in sira) _ilkler[t]];
      final dogru = [for (final e in x) e.$2];
      List<String> disi(int p) => _ilkDisi[x[p].$1] ?? const <String>[];
      return _sirali(
        '${_uc([for (final e in x) e.$1])}\nTürk edebiyatındaki bu ilklerin '
        'karşılığı olan eser ya da yayınlar sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
        dogru,
        [
          // Öteki iki ilkin yanıtı olan eserler bu konuma yazılmaz; yoksa
          // aynı eser bir seçenekte iki kez geçer.
          for (var p = 0; p < 3; p++)
            [
              for (final s in _yakinIlkler[sira[p]])
                if (!dogru.contains(s) && !disi(p).contains(s)) s,
            ].sublist(0, 6),
        ],
        '${[for (final e in x) '${e.$1}: ${e.$2} (${e.$3})'].join('; ')}.',
        i,
        tekrarsiz: true,
        agirlik: _ilkAgirlik,
      );
    }
    final x = _yayili(_temsilciSerpik, j, 2500);
    final dogru = [for (final e in x) e.$2];
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış sanatçıların bağlı '
      'olduğu edebî dönem ya da topluluklar sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
      dogru,
      [
        for (var p = 0; p < 3; p++)
          _digerleri(
            [
              for (final s in _toplulukHavuzu)
                if (!x[p].$3.contains(s)) s,
            ],
            dogru[p],
            i + p,
            [
              for (final s in _toplulukKarisan[dogru[p]]!)
                if (!x[p].$3.contains(s)) s,
            ],
          ),
      ],
      '${[for (final e in x) '${e.$1}: ${e.$2}'].join('; ')}.',
      i,
      agirlik: _toplulukAgirlik,
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Edebiyat',
);

// ─────────────────────────── 11 · Simple present ─────────────────────────────

// (cümle başında, cümle içinde, üçüncü tekil kişi mi)
const _spOzneler = [
  ('My sister', 'my sister', true),
  ('We', 'we', false),
  ('Mr Brown', 'Mr Brown', true),
  ('My parents', 'my parents', false),
  ('Our neighbour', 'our neighbour', true),
  ('They', 'they', false),
  ('The manager', 'the manager', true),
  ('The students', 'the students', false),
  ('Ali', 'Ali', true),
  ('You', 'you', false),
  ('Her brother', 'her brother', true),
  ('Our neighbours', 'our neighbours', false),
];

// (yalın hâl, üçüncü tekil kişi, tümleç)
const _spFiiller = [
  ('go', 'goes', 'to the gym'),
  ('watch', 'watches', 'a film'),
  ('study', 'studies', 'English'),
  ('play', 'plays', 'tennis'),
  ('have', 'has', 'lunch with friends'),
  ('do', 'does', 'the shopping'),
  ('wash', 'washes', 'the car'),
  ('fix', 'fixes', 'old bikes'),
  ('try', 'tries', 'a new recipe'),
  ('fly', 'flies', 'to Ankara'),
  ('finish', 'finishes', 'work early'),
  ('miss', 'misses', 'the first bus'),
  ('visit', 'visits', 'the library'),
  ('buy', 'buys', 'fresh bread'),
  ('catch', 'catches', 'the early train'),
  ('brush', 'brushes', 'the dog'),
  ('stay', 'stays', 'at home'),
  ('read', 'reads', 'the newspaper'),
  ('clean', 'cleans', 'the kitchen'),
  ('write', 'writes', 'a blog post'),
  ('take', 'takes', 'a long walk'),
  ('meet', 'meets', 'old friends'),
  ('cook', 'cooks', 'dinner'),
  ('carry', 'carries', 'heavy boxes'),
  ('teach', 'teaches', 'a dance class'),
];

const _spZamanlar = [
  'every day',
  'every week',
  'on Mondays',
  'at the weekend',
  'twice a week',
  'every Friday',
];

final _simplePresent = lmSirali(
  'ing_simple_present',
  'Simple present: olumlu, olumsuz ve soru cümleleri',
  Topic.language,
  Difficulty.easy,
  BloomLevel.uygulama,
  (i) {
    final f = _spFiiller[i % 25];
    final idx = i ~/ 25;
    final tur = idx % 3;
    final zaman = _spZamanlar[idx ~/ 3 % 6];
    final o = _spOzneler[idx ~/ 18 % 12];
    final ucuncu = o.$3;
    final son = '${f.$3} $zaman';
    final be = ucuncu ? 'is' : 'are';
    final String dogru, aciklama;
    final List<String> yanlis;
    switch (tur) {
      case 0:
        dogru = '${o.$1} ${ucuncu ? f.$2 : f.$1} $son.';
        // Yardımcı fiil (yok / be) × fiil biçimi (yalın / -s) deseni.
        yanlis = [
          '${o.$1} ${ucuncu ? f.$1 : f.$2} $son.',
          '${o.$1} $be ${f.$1} $son.',
          '${o.$1} $be ${f.$2} $son.',
        ];
        aciklama = ucuncu
            ? 'Özne üçüncü tekil kişidir; olumlu cümlede fiil üçüncü tekil '
                  'biçimini alır (${f.$1} → ${f.$2}).'
            : 'Özne üçüncü tekil kişi değildir; olumlu cümlede fiil yalın '
                  'kalır (${f.$1}) ve yardımcı fiil kullanılmaz.';
      case 1:
        dogru = '${o.$1} ${ucuncu ? 'doesn\'t' : 'don\'t'} ${f.$1} $son.';
        // Yardımcı fiilin uyumu × fiil biçimi deseni: her iki seçenek bir
        // ya da iki sözcükte ayrışır, anahtar ortada kalmaz.
        yanlis = [
          '${o.$1} ${ucuncu ? 'don\'t' : 'doesn\'t'} ${f.$1} $son.',
          '${o.$1} ${ucuncu ? 'doesn\'t' : 'don\'t'} ${f.$2} $son.',
          '${o.$1} ${ucuncu ? 'don\'t' : 'doesn\'t'} ${f.$2} $son.',
        ];
        aciklama =
            'Özne üçüncü tekil kişi${ucuncu ? 'dir' : ' değildir'}; olumsuz '
            'cümle “${ucuncu ? 'doesn\'t' : 'don\'t'}” ile kurulur ve fiil '
            'yalın kalır (${f.$1}).';
      default:
        dogru = '${ucuncu ? 'Does' : 'Do'} ${o.$2} ${f.$1} $son?';
        yanlis = [
          '${ucuncu ? 'Do' : 'Does'} ${o.$2} ${f.$1} $son?',
          '${ucuncu ? 'Does' : 'Do'} ${o.$2} ${f.$2} $son?',
          '${ucuncu ? 'Do' : 'Does'} ${o.$2} ${f.$2} $son?',
        ];
        aciklama =
            'Özne üçüncü tekil kişi${ucuncu ? 'dir' : ' değildir'}; soru '
            '“${ucuncu ? 'Does' : 'Do'}” ile kurulur ve fiil yalın kalır '
            '(${f.$1}).';
    }
    return secenekli(
      '${o.$2} / ${f.$1} / ${f.$3} / $zaman\nVerilen sözcüklerle “simple '
      'present tense” kullanılarak kurulan '
      '${const ['olumlu cümle', 'olumsuz cümle', 'soru cümlesi'][tur]} '
      'aşağıdakilerden hangisidir?',
      dogru,
      yanlis,
      '$aciklama Doğru cümle: $dogru',
    );
  },
  lesson: 'İngilizce',
);

// ───────────────────────── 12 · Present continuous ───────────────────────────

// (cümle başında, cümle içinde, yardımcı fiil)
const _pcOzneler = [
  ('I', 'I', 'am'),
  ('My sister', 'my sister', 'is'),
  ('The children', 'the children', 'are'),
  ('We', 'we', 'are'),
  ('Our neighbour', 'our neighbour', 'is'),
  ('They', 'they', 'are'),
  ('Mr Brown', 'Mr Brown', 'is'),
  ('The students', 'the students', 'are'),
  ('You', 'you', 'are'),
  ('Ali and Ayşe', 'Ali and Ayşe', 'are'),
];

// (yalın hâl, -ing biçimi, yanlış yazılmış -ing biçimi, tümleç)
const _pcFiiller = [
  ('make', 'making', 'makeing', 'a cake'),
  ('run', 'running', 'runing', 'in the park'),
  ('swim', 'swimming', 'swiming', 'in the pool'),
  ('sit', 'sitting', 'siting', 'on the sofa'),
  ('write', 'writing', 'writeing', 'an email'),
  ('study', 'studying', 'studing', 'for the exam'),
  ('take', 'taking', 'takeing', 'photos'),
  ('dance', 'dancing', 'danceing', 'on the stage'),
  ('cut', 'cutting', 'cuting', 'the vegetables'),
  ('put', 'putting', 'puting', 'the books on the shelf'),
  ('get', 'getting', 'geting', 'ready for the party'),
  ('shop', 'shopping', 'shoping', 'for new shoes'),
  ('plan', 'planning', 'planing', 'a surprise party'),
  ('ride', 'riding', 'rideing', 'a bike'),
  ('drive', 'driving', 'driveing', 'to the city centre'),
  ('have', 'having', 'haveing', 'lunch'),
  ('lie', 'lying', 'lieing', 'on the beach'),
  ('carry', 'carrying', 'carring', 'a heavy bag'),
  ('play', 'playing', 'plaing', 'chess'),
  ('chat', 'chatting', 'chating', 'with a friend'),
  ('bake', 'baking', 'bakeing', 'bread'),
  ('smile', 'smiling', 'smileing', 'at the camera'),
  ('use', 'using', 'useing', 'the computer'),
  ('jog', 'jogging', 'joging', 'along the river'),
  ('close', 'closing', 'closeing', 'the windows'),
];

// (cümle başı ipucu, cümle sonu ipucu, ipucundan sonra yeni cümle başlar mı)
const _pcIpuclari = [
  ('Look! ', '', true),
  ('', ' now', true),
  ('At the moment, ', '', false),
  ('', ' at the moment', true),
  ('Right now, ', '', false),
  ('', ' right now', true),
  ('', ' at present', true),
];

String _buyuk(String s) => s[0].toUpperCase() + s.substring(1);

final _presentContinuous = lmSirali(
  'ing_present_continuous',
  'Present continuous: am/is/are + -ing yapısı',
  Topic.language,
  Difficulty.easy,
  BloomLevel.uygulama,
  (i) {
    final f = _pcFiiller[i % 25];
    final idx = i ~/ 25;
    final tur = idx % 3;
    final o = _pcOzneler[idx ~/ 3 % 10];
    final ip = _pcIpuclari[idx ~/ 30 % 7];
    final be = o.$3;
    final yanlisBe = be == 'is' ? 'are' : 'is';
    // Özneye uyan ve uymayan do biçimi (yardımcı fiil türü hatası için).
    final uyanDo = be == 'is' ? 'does' : 'do';
    final uymayanDo = be == 'is' ? 'do' : 'does';
    final ozne = ip.$3 ? o.$1 : o.$2;
    final String cumle, aciklama;
    // Yardımcı fiil: [doğru, uyumsuz be, uyan do, uymayan do].
    final List<String> yardimci;
    switch (tur) {
      case 0:
        cumle = '${ip.$1}$ozne ___ (${f.$1}) ${f.$4}${ip.$2}.';
        yardimci = [be, yanlisBe, uyanDo, uymayanDo];
        aciklama =
            'Özne “${o.$2}” ile “$be” kullanılır; fiil -ing eki alırken '
            '${f.$1} → ${f.$2} biçiminde yazılır.';
      case 1:
        cumle = '${ip.$1}$ozne ___ (not / ${f.$1}) ${f.$4}${ip.$2}.';
        final olumsuz = be == 'am' ? 'am not' : '${be}n\'t';
        yardimci = [
          olumsuz,
          '${yanlisBe}n\'t',
          '${uyanDo}n\'t',
          '${uymayanDo}n\'t',
        ];
        aciklama =
            'Özne “${o.$2}” ile olumsuzda “$olumsuz” kullanılır; fiil -ing '
            'eki alırken ${f.$1} → ${f.$2} biçiminde yazılır.';
      default:
        cumle = '${ip.$1}___ ${o.$2} ___ (${f.$1}) ${f.$4}${ip.$2}?';
        // İlk boşluk “At the moment, …” gibi bir girişten sonra geliyorsa
        // yardımcı fiil küçük harfle yazılır.
        String bas(String s) => ip.$3 ? _buyuk(s) : s;
        yardimci = [
          for (final y in [be, yanlisBe, uyanDo, uymayanDo]) bas(y),
        ];
        aciklama =
            'Soru, özneye uygun yardımcı fiilin (“${o.$2}” için “$be”) başa '
            'alınmasıyla kurulur; fiil ${f.$1} → ${f.$2} biçiminde yazılır.';
    }
    String secenek(String yard, String fiil) =>
        tur == 2 ? '$yard / $fiil' : '$yard $fiil';
    // 2 × 2 desenlerden biri: yardımcı fiilin uyumu × (-ing yazım hatası,
    // yalın fiil ya da be yerine do). Anahtarın en uzun seçenek olmadığı
    // desenler önce gelir. Olumlu cümlede “do running” gibi bir dizi “koşu
    // yapmak” anlamında okunabileceği için do deseni yalnız olumsuz ve soru
    // cümlelerinde (“don't running”, “Do … running?”) kullanılır.
    final desenler = [
      for (final ikinci in [f.$3, f.$1])
        [
          secenek(yardimci[1], f.$2),
          secenek(yardimci[0], ikinci),
          secenek(yardimci[1], ikinci),
        ],
      if (tur != 0)
        [
          secenek(yardimci[1], f.$2),
          secenek(yardimci[2], f.$2),
          secenek(yardimci[3], f.$2),
        ],
    ];
    final dogru = secenek(yardimci[0], f.$2);
    return secenekli(
      '$cumle\nBu cümlede boş bırakılan '
      '${tur == 2 ? 'yerlere sırasıyla' : 'yere'} “present continuous tense” '
      'kuralına göre aşağıdakilerden hangisi getirilmelidir?',
      dogru,
      _desenSec(dogru, desenler, i),
      aciklama,
    );
  },
  lesson: 'İngilizce',
);

// ───────────────────────────── 13 · Simple past ──────────────────────────────

// (cümle başında, cümle içinde, was/were)
const _gzOzneler = [
  ('I', 'I', 'was'),
  ('We', 'we', 'were'),
  ('My sister', 'my sister', 'was'),
  ('They', 'they', 'were'),
  ('Our neighbour', 'our neighbour', 'was'),
  ('The children', 'the children', 'were'),
  ('Mr Brown', 'Mr Brown', 'was'),
  ('The students', 'the students', 'were'),
  ('You', 'you', 'were'),
  ('Ali and Ayşe', 'Ali and Ayşe', 'were'),
];

// (yalın hâl, ikinci hâl, sık yapılan yanlış biçim, tümleç)
const _gzFiiller = [
  ('go', 'went', 'goed', 'to the cinema'),
  ('see', 'saw', 'seed', 'a great film'),
  ('buy', 'bought', 'buyed', 'a new jacket'),
  ('take', 'took', 'taked', 'a taxi home'),
  ('write', 'wrote', 'writed', 'a long email'),
  ('eat', 'ate', 'eated', 'fish for dinner'),
  ('drink', 'drank', 'drinked', 'green tea'),
  ('make', 'made', 'maked', 'a chocolate cake'),
  ('give', 'gave', 'gived', 'a short speech'),
  ('find', 'found', 'finded', 'a wallet in the street'),
  ('leave', 'left', 'leaved', 'the office early'),
  ('meet', 'met', 'meeted', 'an old friend'),
  ('catch', 'caught', 'catched', 'the last bus'),
  ('bring', 'brought', 'bringed', 'a bottle of juice'),
  ('swim', 'swam', 'swimmed', 'in the lake'),
  ('sing', 'sang', 'singed', 'a folk song'),
  ('break', 'broke', 'breaked', 'a window'),
  ('wear', 'wore', 'weared', 'a red scarf'),
  ('drive', 'drove', 'drived', 'to the airport'),
  ('fly', 'flew', 'flied', 'to Izmir'),
  ('study', 'studied', 'studyed', 'for the exam'),
  ('stop', 'stopped', 'stoped', 'at the bakery'),
  ('carry', 'carried', 'carryed', 'the shopping bags'),
  ('plan', 'planned', 'planed', 'a picnic'),
  ('try', 'tried', 'tryed', 'a new restaurant'),
];

const _gzZamanlar = [
  'yesterday',
  'last night',
  'last week',
  'two days ago',
  'last Saturday',
  'yesterday evening',
  'last month',
];

final _simplePast = lmSirali(
  'ing_simple_past',
  'Simple past: olumlu, olumsuz ve soru dönüşümleri',
  Topic.language,
  Difficulty.easy,
  BloomLevel.uygulama,
  (i) {
    final f = _gzFiiller[i % 25];
    final idx = i ~/ 25;
    final tur = idx % 3;
    final o = _gzOzneler[idx ~/ 3 % 10];
    final son = '${f.$4} ${_gzZamanlar[idx ~/ 30 % 7]}';
    final olumlu = '${o.$1} ${f.$2} $son.';
    final olumsuz = '${o.$1} didn\'t ${f.$1} $son.';
    final String verilen, istenen, dogru, aciklama;
    final List<String> yanlis;
    switch (tur) {
      case 0:
        verilen = olumlu;
        istenen = 'olumsuz';
        dogru = olumsuz;
        // Yardımcı fiil (didn't / don't ya da wasn't) × fiil biçimi deseni.
        final yard = _karma(i, 51).isEven ? 'don\'t' : '${o.$3}n\'t';
        yanlis = [
          '${o.$1} $yard ${f.$1} $son.',
          '${o.$1} didn\'t ${f.$2} $son.',
          '${o.$1} $yard ${f.$2} $son.',
        ];
        aciklama =
            'Geçmiş zamanda olumsuz cümle “didn\'t” ile kurulur ve fiil yalın '
            'hâline döner (${f.$2} → ${f.$1}).';
      case 1:
        verilen = olumlu;
        istenen = 'soru';
        dogru = 'Did ${o.$2} ${f.$1} $son?';
        // Yardımcı fiil (Did / Do ya da Was) × fiil biçimi deseni.
        final yard = _karma(i, 51).isEven ? 'Do' : _buyuk(o.$3);
        yanlis = [
          '$yard ${o.$2} ${f.$1} $son?',
          'Did ${o.$2} ${f.$2} $son?',
          '$yard ${o.$2} ${f.$2} $son?',
        ];
        aciklama =
            'Geçmiş zamanda soru “Did” ile kurulur ve fiil yalın hâline döner '
            '(${f.$2} → ${f.$1}).';
      default:
        verilen = olumsuz;
        istenen = 'olumlu';
        dogru = olumlu;
        // Düzenli sanılan biçim, yalın biçim ve was/were + yalın biçim:
        // anahtar, öteki seçeneklerin ortak sözcüklerini toplamaz.
        yanlis = [
          '${o.$1} ${f.$3} $son.',
          '${o.$1} ${f.$1} $son.',
          '${o.$1} ${o.$3} ${f.$1} $son.',
        ];
        aciklama =
            'Olumlu cümlede “did” kullanılmaz; fiil ikinci hâlini alır '
            '(${f.$1} → ${f.$2}).';
    }
    return secenekli(
      '“$verilen”\nBu “simple past tense” cümlesinin $istenen biçimi '
      'aşağıdakilerden hangisidir?',
      dogru,
      yanlis,
      '$aciklama Doğru cümle: $dogru',
    );
  },
  lesson: 'İngilizce',
);

// ─────────────────────────── 14 · Present perfect ────────────────────────────

// (cümle başında, cümle içinde, has mı)
const _ppOzneler = [
  ('I', 'I', false),
  ('My sister', 'my sister', true),
  ('We', 'we', false),
  ('Our neighbour', 'our neighbour', true),
  ('They', 'they', false),
  ('Mr Brown', 'Mr Brown', true),
  ('My parents', 'my parents', false),
  ('My best friend', 'my best friend', true),
  ('Ali and Ayşe', 'Ali and Ayşe', false),
  ('Their daughter', 'their daughter', true),
  ('You', 'you', false),
  ('Her cousins', 'her cousins', false),
];

// Süreklilik bildiren fiiller: (yalın hâl, üçüncü hâl, tümleç)
const _ppSurekli = [
  ('live', 'lived', 'in this town'),
  ('work', 'worked', 'at the same company'),
  ('know', 'known', 'the Taylor family'),
  ('be', 'been', 'interested in art'),
  ('have', 'had', 'the same car'),
  ('study', 'studied', 'English'),
  ('play', 'played', 'the piano'),
  ('keep', 'kept', 'a diary'),
  ('collect', 'collected', 'old coins'),
  ('wear', 'worn', 'glasses'),
  ('support', 'supported', 'the local team'),
  ('own', 'owned', 'a small boat'),
];

// (zaman ifadesi, başlangıç noktası mı)
const _ppZamanlar = [
  ('2012', true),
  ('three years', false),
  ('last summer', true),
  ('a long time', false),
  ('2015', true),
  ('six months', false),
  ('last spring', true),
  ('ages', false),
  ('last winter', true),
  ('ten years', false),
  ('the beginning of the year', true),
  ('a few months', false),
  ('2018', true),
  ('several years', false),
  ('last March', true),
  ('many years', false),
  ('the end of 2019', true),
  ('over a year', false),
  ('January', true),
  ('more than five years', false),
  ('2020', true),
  ('a decade', false),
  ('last autumn', true),
  ('two years', false),
  ('last year', true),
];

// Sonuç bildiren fiiller: (yalın hâl, üçüncü hâl, tümleç)
const _ppSonuc = [
  ('finish', 'finished', 'the report'),
  ('see', 'seen', 'the new film'),
  ('buy', 'bought', 'the tickets'),
  ('write', 'written', 'the invitations'),
  ('eat', 'eaten', 'lunch'),
  ('do', 'done', 'the washing-up'),
  ('make', 'made', 'a decision'),
  ('take', 'taken', 'the exam'),
  ('send', 'sent', 'the parcel'),
  ('clean', 'cleaned', 'the kitchen'),
  ('pay', 'paid', 'the bill'),
  ('book', 'booked', 'the hotel'),
  ('find', 'found', 'the keys'),
  ('choose', 'chosen', 'a present'),
  ('give', 'given', 'the presentation'),
  ('speak', 'spoken', 'to the manager'),
  ('begin', 'begun', 'the new project'),
  ('feed', 'fed', 'the cat'),
  ('meet', 'met', 'the new teacher'),
  ('sell', 'sold', 'the old car'),
  ('tell', 'told', 'the others'),
  ('hear', 'heard', 'the news'),
  ('leave', 'left', 'the building'),
  ('visit', 'visited', 'the new museum'),
  ('open', 'opened', 'the letter'),
  ('watch', 'watched', 'the match'),
  ('pack', 'packed', 'the suitcases'),
  ('wash', 'washed', 'the car'),
  ('cook', 'cooked', 'dinner'),
  ('call', 'called', 'the dentist'),
];

/// Üç hata boyutlu (bit 1, 2, 4) tek seçenekli sorularda çeldirici desenleri:
/// iki boyutun 2 × 2 deseni (anahtar, A, B, A+B) ya da üç boyutta ikişer hata
/// (A+B, A+C, B+C). Her desende seçenekler birbirinden eşit uzaklıktadır ya da
/// 2 × 2 düzeninde simetriktir; anahtar ortada kalmaz.
const _ucBoyutDesen = [
  [1, 2, 3],
  [1, 4, 5],
  [2, 4, 6],
  [3, 5, 6],
];

final _presentPerfect = lmSirali(
  'ing_present_perfect',
  'Present perfect: have/has, since/for, already/yet/just',
  Topic.language,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    const soru =
        'Bu cümledeki boşluklara “present perfect tense” kuralına göre '
        'sırasıyla aşağıdakilerden hangileri getirilmelidir?';
    if (i % 25 < 18) {
      // since / for: 12 fiil × 12 özne × 25 zaman ifadesi = 3.600 vaka.
      final j = i ~/ 25 * 18 + i % 25;
      final f = _ppSurekli[j % 12];
      final o = _ppOzneler[j ~/ 12 % 12];
      final z = _ppZamanlar[j ~/ 144];
      final aux = o.$3 ? 'has' : 'have', ters = o.$3 ? 'have' : 'has';
      final baglac = z.$2 ? 'since' : 'for', diger = z.$2 ? 'for' : 'since';
      // Hata boyutları: 1 yardımcı fiil, 2 fiil biçimi, 4 since/for.
      String yaz(int h) =>
          '${h & 1 == 0 ? aux : ters} ${h & 2 == 0 ? f.$2 : f.$1} / '
          '${h & 4 == 0 ? baglac : diger}';
      return secenekli(
        '${o.$1} ___ (${f.$1}) ${f.$3} ___ ${z.$1}.\n$soru',
        yaz(0),
        _desenSec(yaz(0), [
          for (final d in _ucBoyutDesen) [for (final h in d) yaz(h)],
        ], i),
        'Özne “${o.$2}” ile “$aux” kullanılır ve fiil üçüncü hâlini alır '
        '(${f.$1} → ${f.$2}). “${z.$1}” '
        '${z.$2 ? 'bir başlangıç noktası bildirdiği için “since”' : 'bir süre bildirdiği için “for”'} '
        'gelir.',
      );
    }
    // already / just / yet: 30 fiil × 12 özne × 4 kalıp içinden 1.400 vaka.
    final j = i ~/ 25 * 7 + i % 25 - 18;
    final f = _ppSonuc[j % 30];
    final r = j ~/ 30;
    final tur = r % 4;
    final o = _ppOzneler[r ~/ 4];
    final aux = o.$3 ? 'has' : 'have', ters = o.$3 ? 'have' : 'has';
    switch (tur) {
      case 0:
        // Hata boyutları: 1 yardımcı fiil, 2 fiil biçimi, 4 yet/already.
        // Açıklama “already” sözünü andığı için yet/already boyutu her
        // desende yer alır (ilk desen dışarıda kalır).
        String yaz(int h) =>
            '${h & 1 == 0 ? aux : ters}n\'t ${h & 2 == 0 ? f.$2 : f.$1} / '
            '${h & 4 == 0 ? 'yet' : 'already'}';
        return secenekli(
          '${o.$1} ___ (not / ${f.$1}) ${f.$3} ___.\n$soru',
          yaz(0),
          _desenSec(yaz(0), [
            for (final d in _ucBoyutDesen.skip(1)) [for (final h in d) yaz(h)],
          ], i),
          'Özne “${o.$2}” ile olumsuzda “${aux}n\'t” kullanılır ve fiil '
          'üçüncü hâlini alır (${f.$1} → ${f.$2}). Olumsuz cümlenin sonuna '
          '“yet” gelir; “already” olumsuz cümlede kullanılmaz.',
        );
      case 3:
        return secenekli(
          '___ ${o.$2} ___ (${f.$1}) ${f.$3} yet?\n$soru',
          '${_buyuk(aux)} / ${f.$2}',
          // Yardımcı fiilin uyumu × fiil biçimi deseni. “Did” yardımcı fiil
          // hatası olarak alınmaz: desenin çift hatası “Did / yalın fiil”
          // olurdu ve bu Amerikan İngilizcesinde doğru sayılabilir.
          [
            '${_buyuk(ters)} / ${f.$2}',
            '${_buyuk(aux)} / ${f.$1}',
            '${_buyuk(ters)} / ${f.$1}',
          ],
          'Soru, özneye uygun yardımcı fiille (“${o.$2}” için “$aux”) başlar '
          've fiil üçüncü hâlini alır (${f.$1} → ${f.$2}).',
        );
      default:
        final zarf = tur == 1 ? 'already' : 'just';
        return secenekli(
          '${o.$1} ___ $zarf ___ (${f.$1}) ${f.$3}.\n$soru',
          '$aux / ${f.$2}',
          // Yardımcı fiilin uyumu × fiil biçimi deseni.
          ['$ters / ${f.$2}', '$aux / ${f.$1}', '$ters / ${f.$1}'],
          'Özne “${o.$2}” ile “$aux” kullanılır; “$zarf” yardımcı fiil ile '
          'fiilin üçüncü hâli (${f.$1} → ${f.$2}) arasına girer.',
        );
    }
  },
  lesson: 'İngilizce',
);

// ──────────────── 15 · will / be going to ve koşul cümleleri ─────────────────

// (if öznesi, yalın hâl, geniş zaman biçimi, ikinci hâl, if tümleci,
//  ana cümle öznesi, yalın hâl, ikinci hâl, ana cümle tümleci)
const _kosullar = [
  ('it', 'rain', 'rains', 'rained', 'tomorrow', 'we', 'stay', 'stayed', 'at home'),
  ('you', 'study', 'study', 'studied', 'harder', 'you', 'pass', 'passed', 'the exam'),
  ('she', 'miss', 'misses', 'missed', 'the bus', 'she', 'need', 'needed', 'a taxi'),
  ('we', 'leave', 'leave', 'left', 'now', 'we', 'catch', 'caught', 'the early train'),
  ('he', 'save', 'saves', 'saved', 'enough money', 'he', 'buy', 'bought', 'a new bike'),
  ('they', 'invite', 'invite', 'invited', 'us', 'we', 'go', 'went', 'to the party'),
  ('I', 'find', 'find', 'found', 'your keys', 'I', 'call', 'called', 'you'),
  ('the weather', 'get', 'gets', 'got', 'better', 'we', 'have', 'had', 'a picnic'),
  ('you', 'eat', 'eat', 'ate', 'too much cake', 'you', 'feel', 'felt', 'sick'),
  ('my brother', 'get', 'gets', 'got', 'the job', 'he', 'move', 'moved', 'to Ankara'),
  ('we', 'win', 'win', 'won', 'the match', 'we', 'celebrate', 'celebrated', 'all night'),
  ('you', 'ask', 'ask', 'asked', 'the teacher', 'she', 'explain', 'explained', 'it again'),
  ('I', 'see', 'see', 'saw', 'Ali', 'I', 'give', 'gave', 'him your message'),
  ('she', 'take', 'takes', 'took', 'a taxi', 'she', 'arrive', 'arrived', 'on time'),
  ('they', 'sell', 'sell', 'sold', 'their car', 'they', 'use', 'used', 'public transport'),
  ('you', 'drink', 'drink', 'drank', 'coffee at night', 'you', 'sleep', 'slept', 'badly'),
  ('he', 'tell', 'tells', 'told', 'the truth', 'everyone', 'forgive', 'forgave', 'him'),
  ('we', 'take', 'take', 'took', 'the motorway', 'we', 'get', 'got', 'there faster'),
  ('I', 'have', 'have', 'had', 'some free time', 'I', 'visit', 'visited', 'my grandparents'),
  ('the shop', 'close', 'closes', 'closed', 'early', 'we', 'buy', 'bought', 'bread somewhere else'),
  ('you', 'forget', 'forget', 'forgot', 'your umbrella', 'you', 'get', 'got', 'wet'),
  ('she', 'practise', 'practises', 'practised', 'every day', 'she', 'improve', 'improved', 'quickly'),
  ('it', 'snow', 'snows', 'snowed', 'at the weekend', 'the children', 'build', 'built', 'a snowman'),
  ('you', 'lend', 'lend', 'lent', 'me your notes', 'I', 'copy', 'copied', 'them tonight'),
];

const _anlik = 'anlık karar ya da teklif';
const _soz = 'söz verme';
const _plan = 'önceden yapılmış plan';
const _kanit = 'kanıta dayalı tahmin';

const _gelecekGerekce = {
  _anlik: '“will” konuşma anında verilen kararı ya da teklifi bildirir',
  _soz: '“will” söz vermeyi bildirir',
  _plan: '“be going to” önceden yapılmış planı bildirir',
  _kanit: '“be going to” eldeki kanıta dayalı tahmini bildirir',
};

// Söz verme ile anlık karar birbirine yakın olduğundan bu iki etiket
// birbirinin çeldiricisi yapılmaz.
const _gelecekYanlis = {
  _anlik: [_plan, _kanit],
  _soz: [_plan, _kanit],
  _plan: [_kanit, _anlik, _soz],
  _kanit: [_plan, _anlik, _soz],
};

// (cümle, kullanım amacı)
const _gelecekler = [
  ('A: The phone is ringing. B: OK, I\'ll answer it.', _anlik),
  ('A: This bag is very heavy. B: Wait, I\'ll carry it for you.', _anlik),
  ('A: It\'s cold in here. B: You\'re right, I\'ll close the window.', _anlik),
  ('A: We\'ve run out of bread. B: Really? I\'ll buy some on my way home.', _anlik),
  ('A: I\'m thirsty. B: Sit down, I\'ll get you a glass of water.', _anlik),
  ('A: There\'s someone at the door. B: I\'ll open it.', _anlik),
  ('I promise I\'ll call you as soon as I arrive.', _soz),
  ('I won\'t tell anyone your secret. I promise.', _soz),
  ('I promise I\'ll pay you back on Friday.', _soz),
  ('I\'ll never be late again, I promise.', _soz),
  ('We\'re going to visit my aunt in Izmir next week; we\'ve already bought the tickets.', _plan),
  ('I\'ve decided to change my job. I\'m going to look for a new one in spring.', _plan),
  ('I\'ve saved enough money and chosen the model; I\'m going to buy a laptop on Saturday.', _plan),
  ('They\'re going to paint the house next month; they\'ve already chosen the colour.', _plan),
  ('I\'m going to study medicine; I made up my mind last year.', _plan),
  ('Look at those dark clouds! It\'s going to rain.', _kanit),
  ('Be careful! That glass is going to fall off the table.', _kanit),
  ('He\'s driving too fast on the ice. He\'s going to crash.', _kanit),
  ('The team is losing by four goals with two minutes left. They\'re going to lose the match.', _kanit),
  ('She\'s carrying too many plates. She\'s going to drop them.', _kanit),
];

final _gelecekSerpik = _serpistir(_gelecekler, 4);
final _gelecekAgirlik = _dengeAgirlik([
  for (final e in _gelecekler) (e.$2, _gelecekYanlis[e.$2]!),
]);

final _futureConditional = lmSirali(
  'ing_future_conditional',
  'will / be going to ve koşul cümleleri (Type 1–2)',
  Topic.language,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    if (i % 5 == 0) {
      final x = _yayili(_gelecekSerpik, i ~/ 5, 1000);
      final etiket = [for (final e in x) e.$2];
      return _sirali(
        '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde “will” ya '
        'da “be going to” yapısının kullanım amacı sırasıyla hangi seçenekte '
        'doğru verilmiştir?',
        etiket,
        [for (final e in etiket) _gelecekYanlis[e]!],
        '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede ${_gelecekGerekce[etiket[p]]}'].join('; ')}.',
        i,
        agirlik: _gelecekAgirlik,
      );
    }
    // Koşul cümleleri: 24 çiftten üçlü seçki (2.024) × iki boşluk düzeni.
    final j = i - i ~/ 5 - 1;
    const toplam = 2024;
    final ci = j % toplam, k = j ~/ toplam;
    final u = kombinasyon(_kosullar, 3, ci, spread: false);
    final d = ucluDizilimler[j % 6];
    final cumle = <String>[], dogru = <String>[], gerekce = <String>[];
    final yanlis = <List<String>>[];
    for (var p = 0; p < 3; p++) {
      final e = u[d[p]];
      final bicim = (k + ci + p * (1 + ci ~/ 7)) % 4;
      switch (bicim) {
        case 0:
          cumle.add('If ${e.$1} ${e.$3} ${e.$5}, ${e.$6} ___ (${e.$7}) ${e.$9}.');
          dogru.add('will ${e.$7}');
          yanlis.add(['would ${e.$7}', e.$8, 'will ${e.$8}']);
          gerekce.add(
            'if cümlesi geniş zamandadır (Type 1), ana cümle “will” ile kurulur (will ${e.$7})',
          );
        case 1:
          cumle.add('If ${e.$1} ___ (${e.$2}) ${e.$5}, ${e.$6} will ${e.$7} ${e.$9}.');
          dogru.add(e.$3);
          yanlis.add([
            'will ${e.$2}',
            e.$4,
            'would ${e.$2}',
            if (e.$2 != e.$3) e.$2,
          ]);
          gerekce.add(
            'ana cümlede “will” vardır (Type 1), if cümlesi geniş zamanda olur (${e.$3})',
          );
        case 2:
          cumle.add('If ${e.$1} ${e.$4} ${e.$5}, ${e.$6} ___ (${e.$7}) ${e.$9}.');
          dogru.add('would ${e.$7}');
          yanlis.add(['will ${e.$7}', 'would ${e.$8}', e.$7]);
          gerekce.add(
            'if cümlesinde ikinci hâl vardır (Type 2), ana cümle “would” ile kurulur (would ${e.$7})',
          );
        default:
          cumle.add('If ${e.$1} ___ (${e.$2}) ${e.$5}, ${e.$6} would ${e.$7} ${e.$9}.');
          dogru.add(e.$4);
          yanlis.add([e.$3, 'would ${e.$2}', 'will ${e.$2}']);
          gerekce.add(
            'ana cümlede “would” vardır (Type 2), if cümlesinde ikinci hâl kullanılır (${e.$4})',
          );
      }
    }
    return _sirali(
      // Kalıp kısıtı olmadan “If she missed the bus, she will need a taxi.”
      // gibi karma (gerçek geçmiş koşullu) cümleler de savunulabilir.
      '${_uc(cumle)}\nNumaralanmış cümlelerin her biri “Type 1” ya da “Type 2” '
      'koşul cümlesi kalıbına göre kurulacaktır. Boş bırakılan yerlere '
      'sırasıyla hangileri getirilmelidir?',
      dogru,
      yanlis,
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede ${gerekce[p]}'].join('; ')}.',
      i,
      // Doğru if biçimi (rains) çoğu yanlış biçimden kısadır; uzunluk
      // dengesi anahtarın en kısa seçenek olmasını önler.
      boyDengeli: true,
    );
  },
  lesson: 'İngilizce',
);

// ───────────────────────────────── 16 · Modals ───────────────────────────────

const _modalGerekce = {
  'can': 'şimdiki yeteneği bildirir',
  'can\'t': 'yapılamayanı bildirir',
  'could': 'geçmişteki yeteneği bildirir',
  'couldn\'t': 'geçmişte yapılamayanı bildirir',
  'must': 'kuralı ya da güçlü zorunluluğu bildirir',
  'mustn\'t': 'yasağı bildirir',
  'should': 'tavsiye bildirir',
  'shouldn\'t': 'yapılmaması yönünde tavsiye bildirir',
  'has to': 'üçüncü tekil kişide zorunluluğu bildirir',
  'have to': 'zorunluluğu bildirir',
  'doesn\'t have to': 'üçüncü tekil kişide zorunluluk olmadığını bildirir',
  'don\'t have to': 'zorunluluk olmadığını bildirir',
};

// (cümle, doğru söz, o cümlede kesin yanlış olan sözler)
const _modallar = [
  ('Elif is a great musician; she ___ play the piano and the violin.', 'can', ['mustn\'t', 'couldn\'t', 'doesn\'t have to']),
  ('I took lessons last summer, so now I ___ swim very well.', 'can', ['mustn\'t', 'couldn\'t', 'don\'t have to']),
  ('My grandfather is ninety, but he ___ still walk five kilometres a day.', 'can', ['mustn\'t', 'couldn\'t', 'shouldn\'t']),
  ('Dolphins are very intelligent; they ___ learn many tricks.', 'can', ['mustn\'t', 'couldn\'t', 'don\'t have to']),
  ('Penguins are birds, but they ___ fly.', 'can\'t', ['mustn\'t', 'shouldn\'t', 'couldn\'t']),
  ('Please speak up. I ___ hear you at the back.', 'can\'t', ['mustn\'t', 'shouldn\'t', 'don\'t have to']),
  ('I am sorry, I ___ come to your party tomorrow; I will be in Ankara.', 'can\'t', ['mustn\'t', 'shouldn\'t', 'don\'t have to']),
  ('When my grandmother was young, she ___ run very fast.', 'could', ['can', 'must', 'should']),
  ('Mozart ___ play the piano when he was a small child.', 'could', ['can', 'has to', 'should']),
  ('I ___ read when I was only four years old.', 'could', ['can', 'must', 'should']),
  ('Twenty years ago, people ___ reach the island only by boat.', 'could', ['can', 'must', 'should']),
  ('The exam was so difficult that I ___ answer the last question.', 'couldn\'t', ['can\'t', 'mustn\'t', 'shouldn\'t']),
  ('It was very dark, so we ___ see the path.', 'couldn\'t', ['can\'t', 'mustn\'t', 'don\'t have to']),
  ('When I was a baby, I ___ walk or talk.', 'couldn\'t', ['can\'t', 'mustn\'t', 'shouldn\'t']),
  ('The sign says “Stop”. All drivers ___ stop here.', 'must', ['mustn\'t', 'can\'t', 'don\'t have to']),
  ('It is a very important meeting. You ___ be on time.', 'must', ['mustn\'t', 'can\'t', 'don\'t have to']),
  ('Passengers ___ show their tickets before they get on the plane; it is the rule.', 'must', ['mustn\'t', 'can\'t', 'don\'t have to']),
  ('You ___ wear a seat belt in a car; it is the law.', 'must', ['mustn\'t', 'can\'t', 'don\'t have to']),
  ('This is a hospital. You ___ make noise here.', 'mustn\'t', ['must', 'don\'t have to', 'could']),
  ('The traffic light is red. You ___ cross the road now.', 'mustn\'t', ['must', 'don\'t have to', 'could']),
  ('You ___ use your phone during the exam; it is strictly forbidden.', 'mustn\'t', ['must', 'don\'t have to', 'should']),
  ('Students ___ run in the corridors; it is against the school rules.', 'mustn\'t', ['must', 'don\'t have to', 'should']),
  ('You ___ touch that wire. It is very dangerous.', 'mustn\'t', ['must', 'don\'t have to', 'should']),
  ('You look very tired. I think you ___ go to bed early tonight.', 'should', ['shouldn\'t', 'mustn\'t', 'couldn\'t']),
  ('If you have a toothache, you ___ see a dentist.', 'should', ['shouldn\'t', 'mustn\'t', 'couldn\'t']),
  ('That film is wonderful. I think you ___ watch it.', 'should', ['shouldn\'t', 'mustn\'t', 'can\'t']),
  ('You have an exam tomorrow, so you ___ revise your notes tonight.', 'should', ['shouldn\'t', 'mustn\'t', 'couldn\'t']),
  ('You ___ eat so much fast food; it is bad for your health.', 'shouldn\'t', ['should', 'must', 'have to']),
  ('It is very late. The children ___ be awake at this hour.', 'shouldn\'t', ['should', 'must', 'have to']),
  ('You ___ believe everything you read on the internet.', 'shouldn\'t', ['should', 'must', 'have to']),
  ('My father is a pilot. It is the airline\'s rule, so he ___ wear a uniform at work.', 'has to', ['have to', 'mustn\'t', 'doesn\'t have to']),
  ('In Turkey, drivers ___ drive on the right side of the road.', 'have to', ['has to', 'mustn\'t', 'don\'t have to']),
  ('My sister starts work at six, so she ___ get up very early.', 'has to', ['have to', 'mustn\'t', 'doesn\'t have to']),
  ('It is compulsory at our school: we ___ wear a uniform.', 'have to', ['has to', 'mustn\'t', 'don\'t have to']),
  ('A night nurse ___ work while other people are sleeping.', 'has to', ['have to', 'mustn\'t', 'shouldn\'t']),
  ('Tomorrow is a holiday, so we ___ get up early.', 'don\'t have to', ['mustn\'t', 'doesn\'t have to', 'have to']),
  ('You ___ bring any food to the picnic; we already have plenty.', 'don\'t have to', ['mustn\'t', 'must', 'doesn\'t have to']),
  ('The museum is free on Sundays, so visitors ___ pay.', 'don\'t have to', ['mustn\'t', 'must', 'doesn\'t have to']),
  ('My brother works from home, so he ___ wear a suit.', 'doesn\'t have to', ['mustn\'t', 'don\'t have to', 'has to']),
  ('It is Saturday, so Ayşe ___ go to school today.', 'doesn\'t have to', ['mustn\'t', 'don\'t have to', 'has to']),
];

final _modalSerpik = _serpistir(_modallar, 10);
final _modalAgirlik = _dengeAgirlik([for (final e in _modallar) (e.$2, e.$3)]);

final _modals = lmSirali(
  'ing_modals',
  'Modals: can, could, must, should, have to (bağlamda)',
  Topic.language,
  Difficulty.medium,
  BloomLevel.analiz,
  (i) {
    final x = _dizili(_modalSerpik, i);
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde boş '
      'bırakılan yerlere anlam ve dil bilgisi bakımından uygun düşen sözler '
      'sırasıyla hangi seçenekte verilmiştir?',
      [for (final e in x) e.$2],
      [for (final e in x) e.$3],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$2}” ${_modalGerekce[x[p].$2]}'].join('; ')}.',
      i,
      agirlik: _modalAgirlik,
    );
  },
  lesson: 'İngilizce',
);

// ───────────────────── 17 · Comparatives and superlatives ────────────────────

// (yalın, karşılaştırma, üstünlük, yanlış karşılaştırma, yanlış üstünlük,
//  karşılaştırma cümlesi, üstünlük cümlesi)
const _sifatlar = [
  ('tall', 'taller', 'the tallest', 'more tall', 'the most tall', 'My brother is ___ (tall) than my father.', 'The giraffe is ___ (tall) animal in the world.'),
  ('big', 'bigger', 'the biggest', 'biger', 'the bigest', 'An elephant is ___ (big) than a horse.', 'Russia is ___ (big) country in the world.'),
  ('hot', 'hotter', 'the hottest', 'hoter', 'the hotest', 'July is usually ___ (hot) than May in Turkey.', 'The Sahara is one of ___ (hot) places on Earth.'),
  ('easy', 'easier', 'the easiest', 'easyer', 'the easyest', 'This puzzle is ___ (easy) than the last one.', 'The first question was ___ (easy) one in the whole test.'),
  ('happy', 'happier', 'the happiest', 'happyer', 'the happyest', 'She looks ___ (happy) than she did yesterday.', 'It was ___ (happy) day of my life.'),
  ('good', 'better', 'the best', 'gooder', 'the goodest', 'Your idea is ___ (good) than mine.', 'This is ___ (good) restaurant in town.'),
  ('bad', 'worse', 'the worst', 'badder', 'the baddest', 'The weather today is ___ (bad) than it was yesterday.', 'That was ___ (bad) film I have ever seen.'),
  ('expensive', 'more expensive', 'the most expensive', 'expensiver', 'the expensivest', 'A plane ticket is ___ (expensive) than a bus ticket.', 'This is ___ (expensive) hotel in the city.'),
  ('beautiful', 'more beautiful', 'the most beautiful', 'beautifuller', 'the beautifullest', 'The garden is ___ (beautiful) in spring than in winter.', 'It is ___ (beautiful) beach on the island.'),
  ('interesting', 'more interesting', 'the most interesting', 'interestinger', 'the interestingest', 'I think history is ___ (interesting) than geography.', 'It is ___ (interesting) book I have ever read.'),
  ('difficult', 'more difficult', 'the most difficult', 'difficulter', 'the difficultest', 'For many people, Chinese is ___ (difficult) to learn than Spanish.', 'The last question was ___ (difficult) one in the exam.'),
  ('small', 'smaller', 'the smallest', 'more small', 'the most small', 'A mouse is ___ (small) than a cat.', 'Mercury is ___ (small) planet in the solar system.'),
  ('fast', 'faster', 'the fastest', 'more fast', 'the most fast', 'A train is ___ (fast) than a bicycle.', 'The cheetah is ___ (fast) land animal in the world.'),
  ('long', 'longer', 'the longest', 'more long', 'the most long', 'The Nile is ___ (long) than the Thames.', 'The Kızılırmak is ___ (long) river in Turkey.'),
  ('cold', 'colder', 'the coldest', 'more cold', 'the most cold', 'Winters in Erzurum are ___ (cold) than winters in Antalya.', 'Antarctica is ___ (cold) continent on Earth.'),
  ('heavy', 'heavier', 'the heaviest', 'heavyer', 'the heavyest', 'A lorry is ___ (heavy) than a car.', 'The blue whale is ___ (heavy) animal on Earth.'),
  ('thin', 'thinner', 'the thinnest', 'thiner', 'the thinest', 'This laptop is ___ (thin) than my old one.', 'It is ___ (thin) phone in the shop.'),
  ('large', 'larger', 'the largest', 'more large', 'the most large', 'Istanbul is ___ (large) than Bursa.', 'The Pacific is ___ (large) ocean in the world.'),
  ('busy', 'busier', 'the busiest', 'busyer', 'the busyest', 'The city centre is ___ (busy) than our village.', 'Friday is ___ (busy) day of the week at the market.'),
  ('cheap', 'cheaper', 'the cheapest', 'more cheap', 'the most cheap', 'Travelling by bus is ___ (cheap) than travelling by plane.', 'This is ___ (cheap) shirt in the shop.'),
  ('comfortable', 'more comfortable', 'the most comfortable', 'comfortabler', 'the comfortablest', 'An armchair is ___ (comfortable) than a wooden stool.', 'This is ___ (comfortable) bed in the hotel.'),
  ('dangerous', 'more dangerous', 'the most dangerous', 'dangerouser', 'the dangerousest', 'Driving in fog is ___ (dangerous) than driving in sunshine.', 'It is ___ (dangerous) road in the region.'),
  ('young', 'younger', 'the youngest', 'more young', 'the most young', 'My sister is three years ___ (young) than me.', 'Ali is ___ (young) player in the team.'),
  ('old', 'older', 'the oldest', 'more old', 'the most old', 'This castle is much ___ (old) than the bridge.', 'It is ___ (old) building in our town.'),
  ('funny', 'funnier', 'the funniest', 'funnyer', 'the funnyest', 'This comedy is ___ (funny) than the one we saw last week.', 'He is ___ (funny) person in our class.'),
  ('popular', 'more popular', 'the most popular', 'popularer', 'the popularest', 'Football is ___ (popular) than golf in Turkey.', 'It is ___ (popular) song of the year.'),
  ('short', 'shorter', 'the shortest', 'more short', 'the most short', 'February is ___ (short) than March.', 'February is ___ (short) month of the year.'),
  ('noisy', 'noisier', 'the noisiest', 'noisyer', 'the noisyest', 'The street is ___ (noisy) during the day than at night.', 'It is ___ (noisy) classroom in the school.'),
  ('important', 'more important', 'the most important', 'importanter', 'the importantest', 'For me, health is ___ (important) than money.', 'It was ___ (important) decision of his career.'),
  ('sad', 'sadder', 'the saddest', 'sader', 'the sadest', 'The ending of the book is ___ (sad) than the beginning.', 'It was ___ (sad) scene in the film.'),
];

// (cümle, doğru biçim, yanlış biçimler, üstünlük mü)
final _sifatMaddeleri = _serpistir([
  for (final s in _sifatlar) ...[
    (s.$6, s.$2, [s.$4, s.$3, s.$1], false),
    (s.$7, s.$3, [s.$5, s.$2, s.$1], true),
  ],
], 2);

final _comparative = lmSirali(
  'ing_comparative',
  'Comparatives and superlatives: sıfatların biçimleri',
  Topic.language,
  Difficulty.easy,
  BloomLevel.uygulama,
  (i) {
    final x = _dizili(_sifatMaddeleri, i);
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde ayraç '
      'içinde verilen sıfatların uygun biçimleri sırasıyla hangi seçenekte '
      'doğru verilmiştir?',
      [for (final e in x) e.$2],
      [for (final e in x) e.$3],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede ${x[p].$4 ? 'bir kümenin en üstünü anlatıldığı için üstünlük biçimi (superlative)' : 'iki şey karşılaştırıldığı için karşılaştırma biçimi (comparative)'} gelir: ${x[p].$2}'].join('; ')}.',
      i,
      boyDengeli: true,
    );
  },
  lesson: 'İngilizce',
);

// ─────────────────── 18 · Prepositions of time and place ─────────────────────

const _edatHavuzu = ['in', 'on', 'at'];

// (cümle, doğru edat, kullanım nedeni)
const _edatlar = [
  ('The film starts ___ 8 o\'clock.', 'at', 'saat'),
  ('We usually have lunch ___ noon.', 'at', 'günün belirli anı'),
  ('The streets are very quiet ___ night.', 'at', 'kalıplaşmış kullanım (at night)'),
  ('The fireworks began ___ midnight.', 'at', 'günün belirli anı'),
  ('She is waiting for us ___ the bus stop.', 'at', 'belirli bir nokta'),
  ('There is someone ___ the door.', 'at', 'belirli bir nokta'),
  ('Turn left ___ the traffic lights.', 'at', 'belirli bir nokta'),
  ('My father isn\'t ___ home right now.', 'at', 'kalıplaşmış kullanım (at home)'),
  ('Let\'s meet ___ lunchtime.', 'at', 'günün belirli anı'),
  ('Our plane arrived ___ the airport two hours late.', 'at', 'belirli bir nokta (arrive at)'),
  ('The lesson finishes ___ half past three.', 'at', 'saat'),
  ('I can\'t talk now; I am very busy ___ the moment.', 'at', 'kalıplaşmış kullanım (at the moment)'),
  ('The farmers start work ___ sunrise.', 'at', 'günün belirli anı'),
  ('He lives ___ 24 Baker Street.', 'at', 'kapı numarası verilen adres'),
  ('Both runners crossed the line ___ the same time.', 'at', 'kalıplaşmış kullanım (at the same time)'),
  ('We have a maths exam ___ Monday.', 'on', 'gün adı'),
  ('My birthday is ___ 5 May.', 'on', 'tarih'),
  ('There is a beautiful picture ___ the wall.', 'on', 'yüzey'),
  ('The cat is sleeping ___ the sofa.', 'on', 'yüzey'),
  ('Our flat is ___ the third floor.', 'on', 'bina katı'),
  ('The dictionaries are ___ the top shelf.', 'on', 'yüzey'),
  ('We always visit our grandparents ___ New Year\'s Day.', 'on', 'özel gün'),
  ('The answer is ___ page 45.', 'on', 'sayfa'),
  ('The children sat ___ the floor and played a game.', 'on', 'yüzey'),
  ('I usually go swimming ___ Friday mornings.', 'on', 'gün adı'),
  ('We had a picnic ___ the first day of the holiday.', 'on', 'belirli bir gün'),
  ('The Republic of Turkey was proclaimed ___ 29 October 1923.', 'on', 'tarih'),
  ('Dinner is ___ the table; come and eat.', 'on', 'yüzey'),
  ('The price is written ___ the label.', 'on', 'yüzey'),
  ('What do you usually do ___ weekdays?', 'on', 'günler'),
  ('My sister was born ___ 2015.', 'in', 'yıl'),
  ('The trees lose their leaves ___ autumn.', 'in', 'mevsim'),
  ('School starts ___ September.', 'in', 'ay'),
  ('I usually drink tea ___ the morning.', 'in', 'günün bölümü'),
  ('The keys are ___ my pocket.', 'in', 'bir şeyin içi'),
  ('The milk is ___ the fridge.', 'in', 'bir şeyin içi'),
  ('My cousin lives ___ London.', 'in', 'şehir'),
  ('Atatürk was born ___ 1881.', 'in', 'yıl'),
  ('The children are playing ___ the garden.', 'in', 'sınırları belli alan'),
  ('We often go for a walk ___ the evening.', 'in', 'günün bölümü'),
  ('The internet became popular ___ the 1990s.', 'in', 'on yıllık dönem'),
  ('There are thousands of fish ___ this lake.', 'in', 'bir şeyin içi'),
  ('It often snows here ___ winter.', 'in', 'mevsim'),
  ('She keeps her old letters ___ a wooden box.', 'in', 'bir şeyin içi'),
  ('They spent two weeks ___ Italy last summer.', 'in', 'ülke'),
];

final _edatSerpik = _serpistir(_edatlar, 3);

// “Hangileri” sorularındaki anahtar boylarına göre desen ağırlıkları.
const _desenEdat = [15, 2, 43, 22, 14, 21, 2];

final _preposition = lmSirali(
  'ing_preposition',
  'Prepositions of time and place: in, on, at',
  Topic.language,
  Difficulty.easy,
  BloomLevel.hatirlama,
  (i) {
    final x = _dizili(_edatSerpik, i);
    final etiket = [for (final e in x) e.$2];
    final liste = _uc([for (final e in x) e.$1]);
    final aciklama =
        '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$2}”: ${x[p].$3}'].join('; ')}.';
    if (i.isOdd) {
      final hedef = etiket[i ~/ 2 % 3];
      return _hangileri(
        '$liste\nNumaralanmış cümlelerin hangilerinde boş bırakılan yere '
        '“$hedef” getirilmelidir?',
        _maske(etiket, hedef),
        aciklama,
        i,
        _desenEdat,
      );
    }
    return _sirali(
      '$liste\nNumaralanmış cümlelerde boş bırakılan yerlere “in, on, at” '
      'edatlarından hangileri sırasıyla getirilmelidir?',
      etiket,
      [for (var p = 0; p < 3; p++) _digerleri(_edatHavuzu, etiket[p], i + p)],
      aciklama,
      i,
    );
  },
  lesson: 'İngilizce',
);

// ────────────────────────────── 19 · Passive voice ───────────────────────────

// (özne, fiilin yalın hâli, yardımcı fiil, üçüncü hâl,
//  üçüncü hâlden farklıysa ikinci hâl, cümlenin devamı)
const _edilgenler = <(String, String, String, String, String?, String)>[
  ('Rice', 'grow', 'is', 'grown', 'grew', 'in many Asian countries.'),
  ('English', 'speak', 'is', 'spoken', 'spoke', 'in Australia.'),
  ('Thousands of cars', 'produce', 'are', 'produced', null, 'in this factory every year.'),
  ('The streets', 'sweep', 'are', 'swept', null, 'every morning.'),
  ('Cheese', 'make', 'is', 'made', null, 'from milk.'),
  ('The mail', 'deliver', 'is', 'delivered', null, 'at nine o\'clock every day.'),
  ('These toys', 'make', 'are', 'made', null, 'of wood.'),
  ('Breakfast', 'serve', 'is', 'served', null, 'between seven and ten.'),
  ('The windows', 'wash', 'are', 'washed', null, 'once a month.'),
  ('Coffee', 'grow', 'is', 'grown', 'grew', 'in Brazil.'),
  ('This magazine', 'publish', 'is', 'published', null, 'every month.'),
  ('Many accidents', 'cause', 'are', 'caused', null, 'by careless driving.'),
  ('The gates', 'lock', 'are', 'locked', null, 'at ten o\'clock every night.'),
  ('Olive oil', 'produce', 'is', 'produced', null, 'in the Aegean region.'),
  ('The classrooms', 'paint', 'are', 'painted', null, 'every summer.'),
  ('Fresh bread', 'bake', 'is', 'baked', null, 'here every morning.'),
  ('Tickets', 'sell', 'are', 'sold', null, 'at the entrance.'),
  ('I', 'pay', 'am', 'paid', null, 'at the end of every month.'),
  ('Spanish', 'speak', 'is', 'spoken', 'spoke', 'in most of South America.'),
  ('These carpets', 'weave', 'are', 'woven', 'wove', 'by hand.'),
  ('The new words', 'write', 'are', 'written', 'wrote', 'on the board every lesson.'),
  ('Paper', 'make', 'is', 'made', null, 'from wood.'),
  ('This bridge', 'build', 'was', 'built', null, 'in 1973.'),
  ('The telephone', 'invent', 'was', 'invented', null, 'by Alexander Graham Bell.'),
  ('These photos', 'take', 'were', 'taken', 'took', 'during our holiday last year.'),
  ('The letter', 'write', 'was', 'written', 'wrote', 'two weeks ago.'),
  ('Two windows', 'break', 'were', 'broken', 'broke', 'in the storm last night.'),
  ('The meetings', 'hold', 'were', 'held', null, 'in the main hall last week.'),
  ('My bike', 'steal', 'was', 'stolen', 'stole', 'yesterday.'),
  ('The Eiffel Tower', 'finish', 'was', 'finished', null, 'in 1889.'),
  ('We', 'invite', 'were', 'invited', null, 'to the wedding last month.'),
  ('The match', 'postpone', 'was', 'postponed', null, 'because of heavy rain yesterday.'),
  ('Those houses', 'design', 'were', 'designed', null, 'by a famous architect in the 1950s.'),
  ('The winners', 'announce', 'were', 'announced', null, 'at the end of the ceremony last night.'),
  ('This novel', 'translate', 'was', 'translated', null, 'into Turkish in 2005.'),
  ('The cake', 'eat', 'was', 'eaten', 'ate', 'before the guests arrived.'),
  ('All the tickets', 'sell', 'were', 'sold', null, 'within an hour yesterday.'),
  ('I', 'give', 'was', 'given', 'gave', 'a wonderful present on my last birthday.'),
  ('The thieves', 'catch', 'were', 'caught', null, 'by the police last night.'),
  ('Penicillin', 'discover', 'was', 'discovered', null, 'by Alexander Fleming in 1928.'),
  ('The Mona Lisa', 'paint', 'was', 'painted', null, 'by Leonardo da Vinci.'),
  ('The injured passengers', 'take', 'were', 'taken', 'took', 'to hospital immediately after the crash.'),
  ('The old library', 'destroy', 'was', 'destroyed', null, 'by a fire in 1998.'),
  ('The keys', 'find', 'were', 'found', null, 'under the sofa this morning.'),
  ('The new class president', 'choose', 'was', 'chosen', 'chose', 'last Friday.'),
  ('The dishes', 'do', 'were', 'done', 'did', 'by my brother last night.'),
  ('This song', 'sing', 'was', 'sung', 'sang', 'at the opening ceremony last year.'),
  ('The lost child', 'see', 'was', 'seen', 'saw', 'near the park an hour ago.'),
  ('The exam results', 'send', 'were', 'sent', null, 'to the students last week.'),
];

const _tersBe = {'am': 'is', 'is': 'are', 'are': 'is', 'was': 'were', 'were': 'was'};

final _edilgenSerpik = _serpistir(_edilgenler, 2);

/// Edilgen yapının üç tipik hatası: sayıca uyumsuz yardımcı fiil, fiilin
/// yalın hâli, üçüncü hâl yerine ikinci hâl (yoksa çifte hata).
List<String> _edilgenYanlis((String, String, String, String, String?, String) e) => [
  '${_tersBe[e.$3]} ${e.$4}',
  '${e.$3} ${e.$2}',
  e.$5 != null ? '${e.$3} ${e.$5}' : '${_tersBe[e.$3]} ${e.$2}',
];

final _passive = lmSirali(
  'ing_passive',
  'Passive voice: am/is/are/was/were + past participle',
  Topic.language,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final x = _dizili(_edilgenSerpik, i);
    if (i.isOdd) {
      final alt = i ~/ 2;
      final yanlisSorulur = alt.isOdd;
      final hedef = 1 + alt ~/ 2 % 7;
      bool dogruMu(int p) => ((hedef >> p) & 1 == 1) != yanlisSorulur;
      final yapi = [
        for (var p = 0; p < 3; p++)
          dogruMu(p)
              ? '${x[p].$3} ${x[p].$4}'
              : _edilgenYanlis(x[p])[(alt ~/ 14 + p) % 3],
      ];
      return _hangileri(
        '${_uc([for (var p = 0; p < 3; p++) '${x[p].$1} ${yapi[p]} ${x[p].$6}'])}\n'
        'Numaralanmış edilgen (passive) cümlelerden hangileri dil bilgisi '
        'yönünden ${yanlisSorulur ? 'yanlıştır' : 'doğrudur'}?',
        hedef,
        '${[for (var p = 0; p < 3; p++) dogruMu(p) ? '${_rakam[p]}. cümle doğrudur (${yapi[p]})' : '${_rakam[p]}. cümlede “${yapi[p]}” yanlıştır, doğrusu “${x[p].$3} ${x[p].$4}” biçimidir'].join('; ')}.',
        i,
      );
    }
    return _sirali(
      '${_uc([for (final e in x) '${e.$1} ___ (${e.$2}) ${e.$6}'])}\n'
      'Numaralanmış cümleler edilgen (passive) yapıda kurulacaktır. Boş '
      'bırakılan yerlere sırasıyla hangileri getirilmelidir?',
      [for (final e in x) '${e.$3} ${e.$4}'],
      [for (final e in x) _edilgenYanlis(e)],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede özne “${x[p].$1}” ile “${x[p].$3}” kullanılır, fiil üçüncü hâlini alır (${x[p].$2} → ${x[p].$4})'].join('; ')}.',
      i,
      boyDengeli: true,
    );
  },
  lesson: 'İngilizce',
);

// ───────────────────────── 20 · Articles and quantifiers ─────────────────────

const _nAn = 'ünlü sesle başlayan sözcükten önce “an” gelir';
const _nA = 'ünsüz sesle başlayan sözcükten önce “a” gelir';
const _nAnOkunus = 'okunuşu ünlü sesle başlayan sözcükten önce “an” gelir';
const _nAOkunus = 'okunuşu ünsüz sesle başlayan sözcükten önce “a” gelir';
const _nAnyOlumsuz = 'olumsuz cümlede “any” kullanılır';
const _nAnySoru = 'soru cümlesinde “any” kullanılır';
const _nSome = 'olumlu cümlede “some” kullanılır';
const _nSomeSayilamaz = 'sayılamayan adla olumlu cümlede “some” kullanılır';
const _nMuch = 'sayılamayan adla “much” kullanılır';
const _nMany = 'sayılabilen çoğul adla “many” kullanılır';
const _nAFew = 'sayılabilen çoğul adla “a few” kullanılır';
const _nALittle = 'sayılamayan adla “a little” kullanılır';

// (cümle, doğru söz, o cümlede kesin yanlış olan sözler, neden)
const _miktarlar = [
  ('She is eating ___ apple.', 'an', ['a', 'much', 'many'], _nAn),
  ('My uncle is ___ engineer.', 'an', ['a', 'much', 'many'], _nAn),
  ('We waited for ___ hour.', 'an', ['a', 'much', 'many'], _nAnOkunus),
  ('He wants to study at ___ university in Ankara.', 'a', ['an', 'much', 'many'], _nAOkunus),
  ('There is ___ bank next to the post office.', 'a', ['an', 'much', 'many'], _nA),
  ('She bought ___ umbrella because it was raining.', 'an', ['a', 'much', 'many'], _nAn),
  ('My father drives ___ European car.', 'a', ['an', 'much', 'many'], _nAOkunus),
  ('That was ___ honest answer.', 'an', ['a', 'much', 'many'], _nAnOkunus),
  ('He works as ___ nurse in a big hospital.', 'a', ['an', 'much', 'many'], _nA),
  ('There isn\'t ___ milk in the fridge.', 'any', ['some', 'many', 'a few'], _nAnyOlumsuz),
  ('Are there ___ eggs in the basket?', 'any', ['much', 'a little', 'an'], _nAnySoru),
  ('I would like ___ water, please.', 'some', ['any', 'many', 'a few'], _nSomeSayilamaz),
  ('We don\'t have ___ homework today.', 'any', ['some', 'many', 'a few'], _nAnyOlumsuz),
  ('There are ___ biscuits on the plate; help yourself.', 'some', ['any', 'much', 'a little'], _nSome),
  ('She didn\'t buy ___ bread yesterday.', 'any', ['some', 'many', 'a few'], _nAnyOlumsuz),
  ('I need ___ information about the course.', 'some', ['an', 'many', 'a few'], _nSomeSayilamaz),
  ('He gave me ___ good advice.', 'some', ['a', 'many', 'a few'], _nSomeSayilamaz),
  ('There aren\'t ___ chairs in the room.', 'any', ['some', 'much', 'a little'], _nAnyOlumsuz),
  ('Is there ___ sugar in my tea?', 'any', ['many', 'a few', 'an'], _nAnySoru),
  ('I bought ___ new furniture last week.', 'some', ['a', 'many', 'a few'], _nSomeSayilamaz),
  ('How ___ students are there in your class?', 'many', ['much', 'any', 'a little'], _nMany),
  ('How ___ money do you need?', 'much', ['many', 'any', 'a few'], _nMuch),
  ('We don\'t have ___ time; the train leaves in five minutes.', 'much', ['many', 'a few', 'an'], _nMuch),
  ('There aren\'t ___ cars on the road at this hour.', 'many', ['much', 'a little', 'an'], _nMany),
  ('How ___ sugar do you take in your coffee?', 'much', ['many', 'any', 'a few'], _nMuch),
  ('How ___ brothers and sisters do you have?', 'many', ['much', 'any', 'a little'], _nMany),
  ('I didn\'t eat ___ rice at lunch.', 'much', ['many', 'a few', 'an'], _nMuch),
  ('How ___ languages can she speak?', 'many', ['much', 'any', 'a little'], _nMany),
  ('There isn\'t ___ traffic in our village.', 'much', ['many', 'a few', 'an'], _nMuch),
  ('She doesn\'t read ___ books in summer.', 'many', ['much', 'a little', 'an'], _nMany),
  ('How ___ water should we drink every day?', 'much', ['many', 'any', 'a few'], _nMuch),
  ('How ___ days are there in a week?', 'many', ['much', 'any', 'a little'], _nMany),
  ('I have ___ friends in Izmir, so I never feel lonely there.', 'a few', ['a little', 'much', 'any'], _nAFew),
  ('Could I have ___ milk in my coffee, please?', 'a little', ['a few', 'many', 'an'], _nALittle),
  ('There are ___ apples left; take one.', 'a few', ['a little', 'much', 'any'], _nAFew),
  ('We still have ___ time before the film starts; let\'s have a coffee.', 'a little', ['a few', 'many', 'any'], _nALittle),
  ('She speaks ___ French, but not very well.', 'a little', ['a few', 'many', 'an'], _nALittle),
  ('He asked me ___ questions about my hometown.', 'a few', ['a little', 'much', 'any'], _nAFew),
  ('Add ___ salt to the soup; it tastes plain.', 'a little', ['a few', 'many', 'an'], _nALittle),
  ('There are ___ shops near here, so we can buy bread easily.', 'a few', ['a little', 'much', 'any'], _nAFew),
  ('I only need ___ minutes to finish this.', 'a few', ['a little', 'much', 'any'], _nAFew),
  ('There is ___ juice in the bottle; you can drink it.', 'a little', ['a few', 'many', 'an'], _nALittle),
  ('We invited ___ people to dinner, just four or five.', 'a few', ['a little', 'much', 'any'], _nAFew),
  ('Put ___ butter on the bread.', 'a little', ['a few', 'many', 'an'], _nALittle),
];

final _miktarSerpik = _serpistir(_miktarlar, 4);
final _miktarAgirlik = _dengeAgirlik([
  for (final e in _miktarlar) (e.$2, e.$3),
]);

final _quantifier = lmSirali(
  'ing_quantifier',
  'Articles and quantifiers: a/an, some/any, much/many',
  Topic.language,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final x = _dizili(_miktarSerpik, i);
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerdeki boşluklara '
      'uygun düşen tanımlık ya da miktar sözleri sırasıyla hangi seçenekte '
      'verilmiştir?',
      [for (final e in x) e.$2],
      [for (final e in x) e.$3],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede ${x[p].$4} (${x[p].$2})'].join('; ')}.',
      i,
      agirlik: _miktarAgirlik,
    );
  },
  lesson: 'İngilizce',
);

final lmDil = <AdvancedFamily>[
  _sesOlayi,
  _cumleOgesi,
  _sozcukTuru,
  _fiilCekimi,
  _yapi,
  _cumleTuru,
  _yazim,
  _sozSanati,
  _yazarEser,
  _donem,
  _simplePresent,
  _presentContinuous,
  _simplePast,
  _presentPerfect,
  _futureConditional,
  _modals,
  _comparative,
  _preposition,
  _passive,
  _quantifier,
];
