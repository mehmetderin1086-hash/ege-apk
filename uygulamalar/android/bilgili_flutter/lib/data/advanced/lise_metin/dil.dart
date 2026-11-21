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

/// Sıralı üçlü yanıt. [yanlis] her konum için kesin yanlış adayları taşır;
/// çeldiriciler bir ya da iki konumu bu adaylarla değiştirerek kurulur.
/// [karistir] doğruysa doğru etiketlerin, en az bir konumu kesin yanlış olan
/// dizilimleri de çeldirici adayıdır.
AdvancedItem _sirali(
  String kok,
  List<String> dogru,
  List<List<String>> yanlis,
  String aciklama,
  int i, {
  bool karistir = false,
}) {
  String yaz(List<String> v) => v.join(' – ');
  List<String> degis(Map<int, int> secim) => [
    for (var p = 0; p < 3; p++)
      secim.containsKey(p) ? yanlis[p][secim[p]! % yanlis[p].length] : dogru[p],
  ];
  final dizilimler = <String>[];
  if (karistir) {
    for (var r = 1; r < 6; r++) {
      final d = ucluDizilimler[1 + (i + r) % 5];
      final v = [for (final j in d) dogru[j]];
      var kesinYanlis = false;
      for (var p = 0; p < 3; p++) {
        if (v[p] != dogru[p] && yanlis[p].contains(v[p])) kesinYanlis = true;
      }
      if (kesinYanlis) dizilimler.add(yaz(v));
    }
  }
  final tekli = [
    for (var r = 0; r < 3; r++) yaz(degis({(i + r) % 3: i ~/ 3 + r})),
  ];
  final adaylar = <String>[
    if (dizilimler.isNotEmpty) dizilimler[0],
    tekli[0],
    if (dizilimler.length > 1 && i.isOdd) dizilimler[1],
    tekli[1],
    tekli[2],
    for (var r = 0; r < 3; r++)
      yaz(degis({(i + r) % 3: i ~/ 7 + r, (i + r + 1) % 3: i ~/ 11 + r + 1})),
    for (var r = 0; r < 3; r++) yaz(degis({(i + r) % 3: i ~/ 3 + r + 1})),
    for (var r = 0; r < 3; r++) yaz(degis({(i + r) % 3: i ~/ 3 + r + 2})),
  ];
  return secenekli(kok, yaz(dogru), adaylar, aciklama);
}

const _kumeAdi = {
  1: 'Yalnız I',
  2: 'Yalnız II',
  4: 'Yalnız III',
  3: 'I ve II',
  5: 'I ve III',
  6: 'II ve III',
  7: 'I, II ve III',
};

/// “Hangileri?” sorusu. [maske] doğru numaraları bit olarak taşır (bit 0 = I).
AdvancedItem _hangileri(String kok, int maske, String aciklama, int i) {
  assert(maske >= 1 && maske <= 7);
  final adaylar = [
    for (var r = 0; r < 3; r++) maske ^ (1 << ((i + r) % 3)),
    maske ^ 7,
    for (var m = 0; m < 7; m++) (m + i) % 7 + 1,
  ].where((m) => m != 0 && m != maske);
  return secenekli(
    kok,
    _kumeAdi[maske]!,
    adaylar.map((m) => _kumeAdi[m]!),
    aciklama,
  );
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
    final x = _dizili(_sesOlaylari, i);
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
      karistir: true,
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
  ('Emekli öğretmen', 'emekli öğretmen'),
  ('Genç kadın', 'genç kadın'),
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

const _turHavuzu = ['isim', 'sıfat', 'zarf', 'zamir', 'edat', 'bağlaç', 'fiil'];

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
  ('Arkadaşım merdivenlerden “aşağı” indi.', 'zarf', 'eylemin yönünü belirtir'),
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

const _turKarisan = {
  'isim': ['zamir', 'sıfat'],
  'sıfat': ['zarf', 'zamir'],
  'zarf': ['sıfat', 'edat'],
  'zamir': ['sıfat', 'isim'],
  'edat': ['bağlaç', 'zarf'],
  'bağlaç': ['edat', 'zarf'],
  'fiil': ['isim', 'zarf'],
};

final _sozcukTuru = lmSirali(
  'tde_sozcuk_turu',
  'Sözcük türleri: tırnak içindeki sözcüğün türü',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.analiz,
  (i) {
    final x = _dizili(_sozcukTurleri, i);
    final etiket = [for (final e in x) e.$2];
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nBu cümlelerde tırnak içinde verilen '
      'sözcüklerin türleri sırasıyla hangi seçenekte doğru verilmiştir?',
      etiket,
      [
        for (var p = 0; p < 3; p++)
          _digerleri(_turHavuzu, etiket[p], i + p, _turKarisan[etiket[p]]!),
      ],
      [
        for (var p = 0; p < 3; p++)
          '${_rakam[p]}. cümlede ${x[p].$2}: ${x[p].$3}',
      ].join('; ') +
          '.',
      i,
      karistir: true,
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
  (8, [1, 2, 4, 5], ['taşı', 'taşısın', 'taşıyın', 'taşısınlar']),
];

// (çekimli fiil, kip, kişi)
final _cekimler = [
  for (final t in _cekimTablosu)
    for (var j = 0; j < t.$3.length; j++)
      (t.$3[j], _kipHavuzu[t.$1], _kisiHavuzu[t.$2[j]]),
];

const _kipKarisan = {
  'görülen geçmiş zaman': ['duyulan geçmiş zaman'],
  'duyulan geçmiş zaman': ['görülen geçmiş zaman'],
  'şimdiki zaman': ['geniş zaman'],
  'gelecek zaman': ['istek kipi'],
  'geniş zaman': ['şimdiki zaman'],
  'gereklilik kipi': ['emir kipi'],
  'dilek-şart kipi': ['istek kipi'],
  'istek kipi': ['emir kipi', 'dilek-şart kipi'],
  'emir kipi': ['istek kipi', 'gereklilik kipi'],
};

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
        karistir: true,
      );
    }
    final kip = [for (final e in x) e.$2];
    return _sirali(
      '$liste\nNumaralanmış çekimli fiillerin kipleri sırasıyla hangi '
      'seçenekte doğru verilmiştir?',
      kip,
      [
        for (var p = 0; p < 3; p++)
          _digerleri(_kipHavuzu, kip[p], i + p, _kipKarisan[kip[p]]!),
      ],
      aciklama,
      i,
      karistir: true,
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

final _yapi = lmSirali(
  'tde_yapi',
  'Yapı bakımından sözcükler: basit, türemiş, birleşik',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final x = _dizili(_yapilar, i);
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
      );
    }
    return _sirali(
      '$liste\nNumaralanmış sözcüklerin yapı bakımından türleri sırasıyla '
      'hangi seçenekte doğru verilmiştir?',
      etiket,
      [for (var p = 0; p < 3; p++) _digerleri(_yapiHavuzu, etiket[p], i + p)],
      aciklama,
      i,
      karistir: true,
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

const _rakam = ['I', 'II', 'III'];

final _cumleTuru = lmSirali(
  'tde_cumle_turu',
  'Cümle türleri: yüklemin türü, yeri ve anlam',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final x = _dizili(_cumleler, i);
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
      '$liste\nNumaralanmış cümlelerin $soru türleri sırasıyla hangi seçenekte '
      'doğru verilmiştir?',
      etiket,
      [
        for (var p = 0; p < 3; p++) [adlar[deger(x[p]) ? 0 : 1]],
      ],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede ${gerekce(x[p])}'].join('; ')}.',
      i,
      karistir: true,
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
  ('ya da', 'yada'),
  ('sarımsak', 'sarmısak'),
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

// Her intakta kişileştirme de bulunduğundan intak örneğinde “teşhis” kesin
// yanlış sayılmaz; çeldiricilerde bu konuma teşhis yazılmaz.
const _sanatKarisan = {
  _tesbih: [_istiare, _mubalaga],
  _teshis: [_intak, _istiare],
  _intak: [_istiare, _tekrir],
  _mubalaga: [_tesbih, _tezat],
  _tezat: [_tekrir, _mubalaga],
  _tekrir: [_tezat, _mubalaga],
  _istiare: [_tesbih, _teshis],
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
  ('Karınca, ağustos böceğine “Yazın çalışsaydın kışın aç kalmazdın.” dedi.', _intak),
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
  ('Akşam, yine akşam, hep aynı akşam.', _tekrir),
  ('Çalıştı, çalıştı, hiç durmadan çalıştı.', _tekrir),
  ('Takımın aslanları sahaya alkışlarla çıktı.', _istiare),
  ('Gökyüzündeki inciler bu gece pırıl pırıldı.', _istiare),
  ('Annem, kuzusunu her sabah okul kapısına kadar götürür.', _istiare),
  ('Havuzun en hızlı balığı, yarışı yine birinci bitirdi.', _istiare),
  ('Sınıfımızın bülbülü, törende iki şarkı söyledi.', _istiare),
  ('Gecenin gümüş tepsisi dağların üstünde yükseldi.', _istiare),
  ('Mahallenin tilkisi, pazarlıkta yine herkesi ikna etti.', _istiare),
];

final _sozSanati = lmSirali(
  'tde_soz_sanati',
  'Söz sanatları: örnek cümledeki sanatı belirleme',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.analiz,
  (i) {
    final x = _dizili(_sanatlar, i);
    final etiket = [for (final e in x) e.$2];
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde belirgin '
      'olarak görülen söz sanatları sırasıyla hangi seçenekte doğru '
      'verilmiştir?',
      etiket,
      [
        for (var p = 0; p < 3; p++)
          _digerleri(
            etiket[p] == _intak
                ? [
                  for (final s in _sanatHavuzu)
                    if (s != _teshis) s,
                ]
                : _sanatHavuzu,
            etiket[p],
            i + p,
            _sanatKarisan[etiket[p]]!,
          ),
      ],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede ${etiket[p]}: ${_sanatGerekce[etiket[p]]}'].join('; ')}.',
      i,
      karistir: true,
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Edebiyat',
);

// GECICI_BASLANGIC
AdvancedFamily _gecici(int n) => lmSirali(
  'tmp_$n',
  'Geçici yer tutucu aile $n',
  Topic.language,
  Difficulty.easy,
  BloomLevel.hatirlama,
  (i) => sayisal(
    'Geçici $n numaralı ailede $i sayısının bir fazlası kaçtır?',
    i + 1,
    const [],
    'Bir eklenir: ${i + 1}.',
  ),
  lesson: 'İngilizce',
);
// GECICI_BITIS

final lmDil = <AdvancedFamily>[
  _sesOlayi,
  _cumleOgesi,
  _sozcukTuru,
  _fiilCekimi,
  _yapi,
  _cumleTuru,
  _yazim,
  _sozSanati,
  for (var n = 9; n <= 20; n++) _gecici(n),
];
