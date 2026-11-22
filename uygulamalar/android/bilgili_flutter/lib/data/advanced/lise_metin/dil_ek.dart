// Lise metin bankası · Dil alanı, ikinci bölüm: Türkçe ve Türk edebiyatı
// (10 aile) ile lise İngilizcesi (10 aile). Kökler elle yazılmış tablolardan
// ve üçlü seçkilerden kurulur; her aile 5.000 ayrı vaka üretir.
import 'ortak.dart';

// ───────────────────────────── Ortak yardımcılar ─────────────────────────────

const _rakam = ['I', 'II', 'III'];

String _uc(List<String> x) => 'I. ${x[0]}\nII. ${x[1]}\nIII. ${x[2]}';

/// Tablonun [i] numaralı üçlü seçkisi; dizilim sıra numarasına bağlıdır.
/// [secki] verilirse seçki onun [i] numaralı sırasından alınır
/// ([_uygunSecki]).
List<T> _dizili<T>(List<T> tablo, int i, [List<int>? secki]) {
  final u = secki == null
      ? kombinasyon(tablo, 3, i)
      : kombinasyon(tablo, 3, secki[i], spread: false);
  final d = ucluDizilimler[i % 6];
  return [u[d[0]], u[d[1]], u[d[2]]];
}

/// [n] ardışık sıra numarasını (j = 0 … n − 1) tablonun bütün üçlü
/// seçkilerine eşit aralıkla yayar; her j ayrı bir seçki verir. [secki]
/// verilirse seçki onun [j] numaralı sırasından alınır ([_uygunSecki]).
List<T> _yayili<T>(List<T> tablo, int j, int n, [List<int>? secki]) {
  final toplam = kombinasyonSayisi(tablo.length, 3);
  if (toplam < n) throw StateError('Yetersiz seçki: $toplam < $n');
  final u = kombinasyon(
    tablo,
    3,
    secki == null ? j * toplam ~/ n : secki[j],
    spread: false,
  );
  final d = ucluDizilimler[j % 6];
  return [u[d[0]], u[d[1]], u[d[2]]];
}

/// [k] soru biçimli bir ailede bir biçime düşen sıra numarası sayısı.
int _bicimBoyu(int k) => (lmAileBoyu + k - 1) ~/ k;

/// [i] sıra numaralı vakanın kendi biçimi (i % k) içindeki sırası
/// (0 … [_bicimBoyu] − 1); biçimler birbirine göre kaydırılmıştır.
int _bicimSirasi(int i, int k) =>
    (i ~/ k + i % k * (_bicimBoyu(k) ~/ k)) % _bicimBoyu(k);

/// Sıra numarasını [k] soru biçimine böler (biçim = i % k) ve o biçimin
/// üçlü seçkisini verir. Her biçimin seçkileri tablonun bütün üçlülerine
/// yayılır; biçimler birbirine göre kaydırıldığı için art arda gelen sıra
/// numaraları aynı üçlüyü göstermez. Bir biçim içinde her sıra numarası ayrı
/// bir üçlü verir. [seckiler] her biçim için ya null (bütün üçlüler) ya da
/// o biçimin [_uygunSecki] listesidir.
List<T> _bicimSecki<T>(
  List<T> tablo,
  int i,
  int k, [
  List<List<int>?>? seckiler,
]) {
  return _yayili(tablo, _bicimSirasi(i, k), _bicimBoyu(k), seckiler?[i % k]);
}

/// [n] sıra numarası (j = 0 … n − 1) için tablonun yalnız [uygun] üçlü
/// seçkilerinin sıraları (sözlük sırasındaki konumları). Her j önce
/// [_yayili] ile aynı varsayılan seçkiyi (j · toplam ~/ n) alır; bu seçki
/// uygun değilse ondan sonra gelen ilk uygun ve kullanılmamış seçkiyi alır.
/// Böylece uygun seçkili vakaların kökü değişmez ve her j ayrı bir üçlü
/// verir. Liste ailenin ilk kullanımında bir kez kurulur.
List<int> _uygunSecki<T>(List<T> tablo, int n, bool Function(List<T>) uygun) {
  final toplam = kombinasyonSayisi(tablo.length, 3);
  if (toplam < n) throw StateError('Yetersiz seçki: $toplam < $n');
  bool iyi(int r) => uygun(kombinasyon(tablo, 3, r, spread: false));
  final secki = List<int>.filled(n, -1);
  final dolu = <int>{};
  for (var j = 0; j < n; j++) {
    final r = j * toplam ~/ n;
    if (iyi(r)) {
      secki[j] = r;
      dolu.add(r);
    }
  }
  for (var j = 0; j < n; j++) {
    if (secki[j] >= 0) continue;
    var r = j * toplam ~/ n;
    var adim = 0;
    do {
      r = (r + 1) % toplam;
      if (++adim > toplam) throw StateError('Yetersiz uygun seçki: $n');
    } while (dolu.contains(r) || !iyi(r));
    secki[j] = r;
    dolu.add(r);
  }
  return secki;
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

/// [dogru] dışındaki etiketler: önce [once] (tipik karıştırmalar), sonra
/// havuzun kalanı [kay] kadar kaydırılarak.
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
    for (final e in once)
      if (e != dogru) e,
    ...kalan.sublist(k),
    ...kalan.sublist(0, k),
  ];
}

/// Sıralı üçlü yanıt. [yanlis] her konum için o konumda kesin yanlış olan
/// etiketleri, önce tipik karıştırmaları taşır. Her konum için bunlardan biri
/// (w) seçilir ve her çeldirici doğru üçlünün iki konumunu değiştirir:
/// (w0, w1, d2), (w0, d1, w2), (d0, w1, w2). Böylece her çeldiricide iki konum
/// kesin yanlıştır; her konumda doğru etiket de w de dört seçeneğin tam
/// ikisinde görünür ve her iki seçenek birbirinden iki konumda ayrılır.
/// “Seçeneklerde en sık geçen etiketleri seç” gibi bilgi gerektirmeyen bir
/// yol yanıtı vermez (tek konumu değiştiren çeldiricilerde bu yol her vakada
/// doğru seçeneği bulur). [tekrarsiz] doğruysa w'ler doğru etiketlerden ve
/// birbirinden farklı seçilir (her konumun yanıtı ayrı bir ögeye ait
/// olduğunda bir seçenek aynı etiketi iki kez taşımaz).
///
/// w'ler her konumun (sıra numarasına göre kaydırılan) ilk üç uygun adayı
/// arasından birlikte seçilir: önce hiçbir seçeneğin ötekilerden göze
/// çarpacak kadar uzun ya da kısa olmadığı, sonra uzunluğu doğru etikete
/// yakın w'ler taşıyan, sonra kaydırma sırasında önce gelen üçlü alınır.
/// Böylece “en uzun ya da en kısa seçenek” de yanıtı ele vermez ve
/// çeldiriciler vakadan vakaya değişir. [tekrarsiz] kuralına ilk üç adayla
/// uyulamıyorsa bütün adaylar denenir.
///
/// [dengeli] doğruysa seçeneklerdeki etiket yinelemesi de yanıtı ele vermez.
/// Doğru üçlünün üç etiketi ayrıysa w'ler [tekrarsiz] kuralıyla seçilir:
/// dört seçeneğin her biri üç ayrı etiket taşır ve her etiket tam iki
/// seçenekte geçer. Doğru üçlünün tam iki etiketi aynıysa w'ler, dört
/// seçeneğin her birinde de tam iki etiket aynı olacak biçimde bütün adaylar
/// arasından seçilir (ör. X – X – Y için A – A – Y, A – X – A, X – A – A).
/// Böylece ne “tek tekdüze seçenek”, ne “etiket yineleyen tek seçenek”, ne
/// de “her seçenekte geçen etiket” yolu yanıtı verir. Üç etiketi aynı doğru
/// üçlü (her seçenekte geçen tek etiketi taşıdığı için kolayca seçilir) bu
/// kipte kabul edilmez; dengeli biçimlerin seçkileri [_dengeliKurulur] ile
/// süzülür.
///
/// [secim] verilirse w'ler aranmaz, o dizi kullanılır (sayısal biçimlerde
/// [_toplamDengesi]).
AdvancedItem _sirali(
  String kok,
  List<String> dogru,
  List<List<String>> yanlis,
  String aciklama,
  int i, {
  bool tekrarsiz = false,
  bool dengeli = false,
  List<String>? secim,
}) {
  final ayri = {...dogru}.length;
  if (dengeli && ayri == 1) throw StateError('Tekdüze doğru üçlü: $kok');
  final ikili = dengeli && ayri == 2;
  final temiz = tekrarsiz || (dengeli && ayri == 3);
  String yaz(List<String> v) => v.join(' – ');

  // Konum p'nin, sıra numarasına göre kaydırılan sırayla en çok [sinir]
  // uygun adayı.
  List<String> adaylar(int p, int sinir) {
    final aday = yanlis[p];
    final bas = (i ~/ 3 + p) % (aday.length < 3 ? aday.length : 3);
    final c = <String>[];
    for (var t = 0; t < aday.length && c.length < sinir; t++) {
      final s = aday[(bas + t) % aday.length];
      if (s == dogru[p] || c.contains(s)) continue;
      if (temiz && dogru.contains(s)) continue;
      c.add(s);
    }
    if (c.isEmpty) {
      throw StateError('Konum ${p + 1} için çeldirici etiket yok: $kok');
    }
    return c;
  }

  int gozeCarpan(List<String> w) => _gozeCarpan(_secenekler(dogru, w));

  // Verilen aday kümelerinden en düşük maliyetli w üçlüsü (yoksa null).
  List<String>? enIyiUclu(List<List<String>> c) {
    List<String>? w;
    var enAz = 1 << 30, sira = 0;
    for (final a in c[0]) {
      for (final b in c[1]) {
        for (final d in c[2]) {
          sira++;
          if (temiz && (a == b || a == d || b == d)) continue;
          final aday = [a, b, d];
          var uzak = 0;
          for (var p = 0; p < 3; p++) {
            final pay = dogru[p].length ~/ 5 > 2 ? dogru[p].length ~/ 5 : 2;
            if ((aday[p].length - dogru[p].length).abs() > pay) uzak++;
          }
          final maliyet = gozeCarpan(aday) * 1000 + uzak * 100 + sira;
          if (maliyet < enAz) {
            enAz = maliyet;
            w = aday;
          }
        }
      }
    }
    return w;
  }

  List<String>? w;
  if (secim != null) {
    w = secim;
  } else if (ikili) {
    // Doğru seçeneğin rolü ([_ikiliRol]) dört vakanın birinde en düşük,
    // birinde ikinci düşük, ikisinde en yüksek etiket sıklığı puanlıdır; bu
    // sıklık, gösterilen seçenek yerinden bağımsız olarak dörtlü sıra
    // numarası öbeklerinden seçilir. Böylece küme yapısından doğru seçenek
    // çıkarılamaz. O roldeki diziler arasından uzunluğu göze çarpan seçenek
    // bırakmayanlardan, sıra numarasına göre değişen biri alınır.
    final gecerli = _ikiliSecimler(dogru, [
      for (var p = 0; p < 3; p++) adaylar(p, 1 << 30),
    ]);
    final rol = const [3, 2, 0, 0][(i ~/ 4 + i ~/ 64) % 4];
    final rolde = [
      for (final g in gecerli)
        if (_ikiliRol(dogru, g) == rol) g,
    ];
    final enIyi = _enAzGozeCarpan(dogru, rolde.isEmpty ? gecerli : rolde);
    if (enIyi.isNotEmpty) w = enIyi[(7 * i + i ~/ 7) % enIyi.length];
  } else {
    w = enIyiUclu([for (var p = 0; p < 3; p++) adaylar(p, 3)]);
    if (w == null && temiz) {
      w = enIyiUclu([for (var p = 0; p < 3; p++) adaylar(p, 1 << 30)]);
    }
  }
  if (w == null) throw StateError('Ayrı çeldirici etiketler yok: $kok');
  return secenekli(kok, yaz(dogru), [
    yaz([w[0], w[1], dogru[2]]),
    yaz([w[0], dogru[1], w[2]]),
    yaz([dogru[0], w[1], w[2]]),
  ], aciklama);
}

/// Etiketleri ayrı doğru üçlü için, her konumda doğru etiketlerden ve
/// birbirinden ayrı birer w seçilebilir mi?
bool _temizKurulur(List<String> dogru, List<List<String>> aday) {
  for (final a in aday[0]) {
    if (dogru.contains(a)) continue;
    for (final b in aday[1]) {
      if (b == a || dogru.contains(b)) continue;
      for (final c in aday[2]) {
        if (c != a && c != b && !dogru.contains(c)) return true;
      }
    }
  }
  return false;
}

/// Tam iki etiketi aynı doğru üçlü için, dört seçeneğin her birinde de tam
/// iki etiketi aynı kılan w dizileri (adayların sırasıyla).
List<List<String>> _ikiliSecimler(List<String> dogru, List<List<String>> aday) {
  bool ikiAyni(String a, String b, String c) => {a, b, c}.length == 2;
  return [
    for (final a in aday[0])
      if (a != dogru[0])
        for (final b in aday[1])
          if (b != dogru[1] && ikiAyni(a, b, dogru[2]))
            for (final c in aday[2])
              if (c != dogru[2] &&
                  ikiAyni(a, dogru[1], c) &&
                  ikiAyni(dogru[0], b, c))
                [a, b, c],
  ];
}

/// Doğru üçlü ile w dizisinin verdiği dört seçeneğin etiketleri.
List<List<String>> _etiketSecenekleri(List<String> dogru, List<String> w) => [
  dogru,
  [w[0], w[1], dogru[2]],
  [w[0], dogru[1], w[2]],
  [dogru[0], w[1], w[2]],
];

/// Seçeneklerin etiket sıklığı puanları: her etiketin dört seçenekte toplam
/// kaç kez geçtiği sayılır; bir seçeneğin puanı, etiketlerinin bu sayılarının
/// toplamıdır.
List<int> _siklikPuanlari(List<List<String>> secenekler) {
  final say = <String, int>{};
  for (final s in secenekler) {
    for (final x in s) {
      say[x] = (say[x] ?? 0) + 1;
    }
  }
  return [for (final s in secenekler) s.fold(0, (t, x) => t + say[x]!)];
}

/// Tam iki etiketi aynı doğru üçlüde doğru seçeneğin rolü: etiket sıklığı
/// puanı kendisininkinden büyük seçenek sayısı. Bu kümelerde w dizisi dört
/// biçimden birini alır (X – X – Y için A – A – A, A – A – X, Y – A – X ya da
/// A – Y – X). Dördü de aynı küme yapısını verir; yalnız doğru seçenek o
/// yapıda sırasıyla en düşük puanlı (3), ikinci düşük puanlı (2) ya da en
/// yüksek puanlı iki seçenekten biri (0) olur.
int _ikiliRol(List<String> dogru, List<String> w) {
  final p = _siklikPuanlari(_etiketSecenekleri(dogru, w));
  var n = 0;
  for (var t = 1; t < 4; t++) {
    if (p[t] > p[0]) n++;
  }
  return n;
}

/// [_sirali] dengeli kipinin bu doğru üçlü için çeldirici kurabilmesi:
/// etiketleri ayrı üçlülerde ([ayri]) temiz w'ler bulunmalıdır. Tam iki
/// etiketi aynı üçlülerde ([ikili]) doğru seçeneğin üç rolünün ([_ikiliRol])
/// her biri için dengeli bir w dizisi bulunmalıdır; böylece rol vakadan
/// vakaya eşit sıklıkla seçilebilir. Üç etiketi aynı üçlü hiçbir zaman uygun
/// değildir. [aday], o konumlarda kesin yanlış olan etiketlerdir (sırası
/// önemsizdir).
bool _dengeliKurulur(
  List<String> dogru,
  List<List<String>> aday, {
  bool ayri = true,
  bool ikili = false,
}) {
  final k = {...dogru}.length;
  if (k == 3) return ayri && _temizKurulur(dogru, aday);
  if (k != 2 || !ikili) return false;
  final roller = {
    for (final w in _ikiliSecimler(dogru, aday)) _ikiliRol(dogru, w),
  };
  return roller.containsAll(const [0, 2, 3]);
}

/// Doğru üçlü ile w dizisinin verdiği dört seçenek (önce doğru seçenek).
List<String> _secenekler(List<String> dogru, List<String> w) => [
  dogru.join(' – '),
  [w[0], w[1], dogru[2]].join(' – '),
  [w[0], dogru[1], w[2]].join(' – '),
  [dogru[0], w[1], w[2]].join(' – '),
];

/// Uzunluğu ötekilerin hepsinden en az 3 karakter ve %10 ayrılan seçenek
/// sayısı; doğru seçeneğin (ilk seçenek) göze çarpması, yanıtı ele verdiği
/// için iki kat sayılır.
int _gozeCarpan(List<String> secenekler) {
  final u = [for (final s in secenekler) s.length];
  var n = 0;
  for (var j = 0; j < 4; j++) {
    final agirlik = j == 0 ? 2 : 1;
    var enUzun = 0, enKisa = 1 << 30;
    for (var t = 0; t < 4; t++) {
      if (t == j) continue;
      if (u[t] > enUzun) enUzun = u[t];
      if (u[t] < enKisa) enKisa = u[t];
    }
    if (u[j] - enUzun >= 3 && 10 * (u[j] - enUzun) >= u[j]) n += agirlik;
    if (enKisa - u[j] >= 3 && 10 * (enKisa - u[j]) >= enKisa) n += agirlik;
  }
  return n;
}

/// [gecerli] w dizilerinden, uzunluğu göze çarpan seçeneği en az olanlar.
List<List<String>> _enAzGozeCarpan(
  List<String> dogru,
  List<List<String>> gecerli,
) {
  var enAz = 1 << 30;
  final enIyi = <List<String>>[];
  for (final g in gecerli) {
    final m = _gozeCarpan(_secenekler(dogru, g));
    if (m < enAz) {
      enAz = m;
      enIyi.clear();
    }
    if (m == enAz) enIyi.add(g);
  }
  return enIyi;
}

/// Dengeli kipin geçerli bütün w dizileri: etiketleri ayrı doğru üçlüde
/// doğru etiketlerden ve birbirinden ayrı w'ler, tam iki etiketi aynı doğru
/// üçlüde [_ikiliSecimler].
List<List<String>> _dengeliSecimler(
  List<String> dogru,
  List<List<String>> aday,
) {
  final k = {...dogru}.length;
  if (k == 2) return _ikiliSecimler(dogru, aday);
  if (k != 3) return const [];
  return [
    for (final a in {...aday[0]})
      if (!dogru.contains(a))
        for (final b in {...aday[1]})
          if (b != a && !dogru.contains(b))
            for (final c in {...aday[2]})
              if (c != a && c != b && !dogru.contains(c)) [a, b, c],
  ];
}

/// Sayısal sıralı biçimlerin w dizileri. Sayma yanlışları çoğunlukla fazla
/// saymaktır; çeldiriciler kendiliğinden büyük kalırsa “toplamı en küçük
/// seçeneği işaretle” gibi bilgi gerektirmeyen yollar doğru yanıtı sık bulur.
/// Bu yollar altıdır: seçeneklerin toplamına bakıp tek başına en küçüğü, tek
/// başına en büyüğü, tek uçlar elendikten sonra kalanlardan birini, ne en
/// küçük ne en büyük olanlardan birini, en küçüklerden birini ya da en
/// büyüklerden birini seçmek. Biçimin [n] vakası sırayla ele alınır; her yolun
/// o ana dek şanstan (dörtte bir) fazla bulduğu doğru yanıt (kazanç) tutulur
/// ve her vakada, uzunluğu göze çarpan seçenek bırakmayan dengeli w
/// dizilerinden ([_dengeliSecimler]) kazançları sıfıra en çok yaklaştıranı
/// seçilir. Böylece bu yolların hiçbiri biçim boyunca şanstan belirgin
/// biçimde fazla doğru yanıt bulmaz. [vaka], j numaralı vakanın doğru
/// üçlüsünü ve konumlarında kesin yanlış olan etiketleri verir. Liste biçimin
/// ilk kullanımında bir kez kurulur.
List<List<String>> _toplamDengesi(
  int n,
  (List<String>, List<List<String>>) Function(int j) vaka,
) {
  int toplam(List<String> v) => v.fold(0, (s, x) => s + int.parse(x));
  // Kazançlar 12 ile çarpılmış tam sayılardır (1/k − 1/4, k = 1 … 4). Orta
  // toplamlılar yolu, tek başına doğru yanıta en sık yaklaşan yol olduğu için
  // iki kat tartılır.
  const agirlik = [1, 1, 1, 2, 1, 1];
  final kazanc = List<int>.filled(6, 0);
  final sonuc = <List<String>>[];
  for (var j = 0; j < n; j++) {
    final (dogru, aday) = vaka(j);
    final gecerli = _enAzGozeCarpan(dogru, _dengeliSecimler(dogru, aday));
    if (gecerli.isEmpty) throw StateError('Dengeli çeldirici yok: $dogru');
    var enAz = 1 << 30;
    final enIyi = <(List<String>, List<int>)>[];
    for (final w in gecerli) {
      final v = [
        toplam(dogru),
        toplam([w[0], w[1], dogru[2]]),
        toplam([w[0], dogru[1], w[2]]),
        toplam([dogru[0], w[1], w[2]]),
      ];
      var enKucuk = v[0], enBuyuk = v[0];
      for (final x in v) {
        if (x < enKucuk) enKucuk = x;
        if (x > enBuyuk) enBuyuk = x;
      }
      final kucukler = [
        for (var t = 0; t < 4; t++)
          if (v[t] == enKucuk) t,
      ];
      final buyukler = [
        for (var t = 0; t < 4; t++)
          if (v[t] == enBuyuk) t,
      ];
      final tekKucuk = kucukler.length == 1 ? kucukler : const <int>[];
      final tekBuyuk = buyukler.length == 1 ? buyukler : const <int>[];
      final kumeler = [
        tekKucuk,
        tekBuyuk,
        [
          for (var t = 0; t < 4; t++)
            if (!tekKucuk.contains(t) && !tekBuyuk.contains(t)) t,
        ],
        [
          for (var t = 0; t < 4; t++)
            if (v[t] != enKucuk && v[t] != enBuyuk) t,
        ],
        kucukler,
        buyukler,
      ];
      final artis = [
        for (final k in kumeler)
          k.isEmpty ? 0 : (k.contains(0) ? 12 ~/ k.length : 0) - 3,
      ];
      var sapma = 0;
      for (var s = 0; s < 6; s++) {
        sapma += agirlik[s] * (kazanc[s] + artis[s]).abs();
      }
      if (sapma < enAz) {
        enAz = sapma;
        enIyi.clear();
      }
      if (sapma == enAz) enIyi.add((w, artis));
    }
    final (w, artis) = enIyi[(7 * j + j ~/ 7) % enIyi.length];
    for (var s = 0; s < 6; s++) {
      kazanc[s] += artis[s];
    }
    sonuc.add(w);
  }
  return sonuc;
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
/// Çeldiriciler, her numara dört seçeneğin tam ikisinde yer alacak biçimde
/// seçilir; böylece “seçeneklerin çoğunda geçen numaraları al” yolu yanıtı
/// vermez. Yanıt üç numarayı da içeriyorsa çeldiriciler tek numaralı üç
/// seçenektir; iki numaralı yanıtta (x, y) çeldiriciler {x, z}, {y}, {z};
/// tek numaralı yanıtta (x) ya {y}, {z}, {x, y, z} ya da {y, z}, {y}, {x, z}.
AdvancedItem _hangileri(String kok, int maske, String aciklama, int i) {
  assert(maske >= 1 && maske <= 7);
  final icinde = [
    for (final m in const [1, 2, 4])
      if (maske & m != 0) m,
  ];
  final disinda = [
    for (final m in const [1, 2, 4])
      if (maske & m == 0) m,
  ];
  final v = i ~/ 2;
  final s = v ~/ 2 % 2;
  final List<int> adaylar;
  if (icinde.length == 3) {
    adaylar = const [1, 2, 4];
  } else if (icinde.length == 2) {
    final z = disinda[0];
    adaylar = [icinde[s] | z, icinde[1 - s], z];
  } else {
    final x = icinde[0], y = disinda[s], z = disinda[1 - s];
    adaylar = v.isEven ? [y, z, 7] : [y | z, y, x | z];
  }
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

/// Her konum için, tablodaki öteki ögelerin etiketlerinden [dogru] ile aynı
/// olmayanlar; [kay] ile döndürülür. Etiketleri tek tek ayrı olan tablolarda
/// (her deyimin ayrı bir anlamı olması gibi) bütün bu etiketler kesin
/// yanlıştır.
List<String> _baskaEtiketler(List<String> etiketler, String dogru, int kay) {
  final kalan = [
    for (final e in etiketler)
      if (e != dogru) e,
  ];
  final k = kay % kalan.length;
  return [...kalan.sublist(k), ...kalan.sublist(0, k)];
}

// ──────────────────────────────── 1 · Deyimler ───────────────────────────────

// (deyim, TDK sözlüğündeki anlamı, deyimin o anlamla geçtiği cümle). Bütün
// anlamlar birbirinden ayrıdır; eş anlamlı iki deyim tabloya alınmamıştır.
const _deyimler = [
  (
    'ağzı kulaklarına varmak',
    'çok sevinmek',
    'Sınav sonucunu öğrenince “ağzı kulaklarına vardı”.',
  ),
  (
    'kulak asmamak',
    'önem vermemek, dinlememek',
    'Annesinin uyarılarına “kulak asmadı”, şemsiyesini almadan çıktı.',
  ),
  (
    'ayağını denk almak',
    'tedbirli davranmak',
    'Yeni müdür çok sert biri, bundan sonra “ayağını denk al”.',
  ),
  (
    'burnu havada olmak',
    'kibirli olmak',
    'Ödülü kazandığından beri “burnu havada”, eski arkadaşlarına selam bile vermiyor.',
  ),
  (
    'dili tutulmak',
    'heyecandan konuşamaz olmak',
    'Sahneye çıkınca “dili tutuldu”, tek söz söyleyemedi.',
  ),
  (
    'kulak kabartmak',
    'belli etmeden dinlemeye çalışmak',
    'Yan masadaki konuşmaya merakla “kulak kabarttı”.',
  ),
  ('ateş pahası', 'çok pahalı', 'Bu mevsimde domatesin kilosu “ateş pahası”.'),
  (
    'dört gözle beklemek',
    'çok istekle beklemek',
    'Çocuklar yaz tatilini “dört gözle bekliyor”.',
  ),
  (
    'göze girmek',
    'birinin güvenini kazanmak',
    'Çalışkanlığıyla kısa sürede ustasının “gözüne girdi”.',
  ),
  ('yüzü kızarmak', 'utanmak', 'Yalanı ortaya çıkınca “yüzü kızardı”.'),
  (
    'kılı kırk yarmak',
    'aşırı titiz davranmak',
    'Ödevini hazırlarken “kılı kırk yarar”, en küçük ayrıntıyı bile atlamaz.',
  ),
  (
    'ipe un sermek',
    'bir işi yapmamak için bahaneler bulmak',
    'Odasını toplaması gerektiğinde hep “ipe un serer”.',
  ),
  (
    'nabzına göre şerbet vermek',
    'birinin hoşuna gidecek biçimde davranmak',
    'Herkesin “nabzına göre şerbet verdiği” için kimseyle tartışmaz.',
  ),
  (
    'pireyi deve yapmak',
    'küçük bir şeyi çok büyütmek',
    'Küçük bir çizik için bu kadar ağlayıp “pireyi deve yapma”.',
  ),
  (
    'ağzı sıkı',
    'sır saklayabilen',
    'Sırrını ona rahatça anlatabilirsin, “ağzı sıkıdır”.',
  ),
  (
    'çam devirmek',
    'yersiz bir sözle birini kırmak',
    'Toplantıda düşünmeden konuşup yine “çam devirdi”.',
  ),
  (
    'eli kulağında',
    'olması çok yakın',
    'Kar yağışı “eli kulağında”, kış hazırlıklarımızı yapalım.',
  ),
  (
    'gözü kara',
    'korkusuz, atılgan',
    '“Gözü kara” itfaiyeci, hiç düşünmeden alevlerin arasına daldı.',
  ),
  (
    'hapı yutmak',
    'kötü bir duruma düşmek',
    'Bu otobüsü de kaçırırsak sınava yetişemeyiz, o zaman “hapı yuttuk”.',
  ),
  (
    'kulağına küpe olmak',
    'unutulmayacak bir ders olmak',
    'Geçen yılki kaza “kulağıma küpe oldu”, artık hızlı araba sürmüyorum.',
  ),
  (
    'omuz omuza vermek',
    'dayanışmak, birlikte çalışmak',
    'Köylüler “omuz omuza verip” yıkılan okulu yeniden yaptı.',
  ),
  (
    'pişmiş aşa su katmak',
    'yoluna girmiş bir işi bozmak',
    'Anlaşma tam sağlanmışken araya girip “pişmiş aşa su kattı”.',
  ),
  (
    'küplere binmek',
    'çok öfkelenmek',
    'Vazosunun kırıldığını görünce “küplere bindi”.',
  ),
  (
    'göz boyamak',
    'aldatıcı bir görünüş yaratmak',
    'Odayı gerçekten temizlemedi, yalnızca “göz boyadı”.',
  ),
  (
    'yüz vermek',
    'aşırı yakınlık gösterip şımartmak',
    'Çocuğa bu kadar “yüz verme”, sonra sözünü dinlemez.',
  ),
  (
    'kuyusunu kazmak',
    'birine gizlice kötülük hazırlamak',
    'Onu işten attırmak için gizlice “kuyusunu kazıyormuş”.',
  ),
  (
    'göz atmak',
    'kısaca bakmak',
    'Sınavdan önce notlarına şöyle bir “göz attı”.',
  ),
  (
    'can kulağıyla dinlemek',
    'büyük bir dikkatle dinlemek',
    'Öğrenciler, dedenin anlattığı anıları “can kulağıyla dinledi”.',
  ),
  (
    'gün görmüş',
    'deneyimli, çok yaşamış',
    'Köyün “gün görmüş” yaşlıları gençlere öğütler verdi.',
  ),
  (
    'eli işe yatmak',
    'bir işi kolayca, ustaca yapabilmek',
    'Yeğenimin “eli her işe yatıyor”, bozulan her şeyi onarabiliyor.',
  ),
  (
    'ağzından kaçırmak',
    'söylememesi gerekeni istemeden söylemek',
    'Doğum günü sürprizini yanlışlıkla “ağzından kaçırdı”.',
  ),
  (
    'gözüne uyku girmemek',
    'kaygıdan uyuyamamak',
    'Sınav sonucunu beklerken bütün gece “gözüne uyku girmedi”.',
  ),
  (
    'çenesi düşük',
    'çok konuşan, geveze',
    'Yolculukta yanıma oturan “çenesi düşük” adam bir an bile susmadı.',
  ),
  (
    'bel bağlamak',
    'güvenmek, umut bağlamak',
    'Bu işte sana “bel bağlamıştım”, beni yarı yolda bırakma.',
  ),
  (
    'yüreğine su serpilmek',
    'rahatlamak, içi ferahlamak',
    'Oğlunun sağ salim döndüğünü görünce “yüreğine su serpildi”.',
  ),
  (
    'dişini tırnağına takmak',
    'bütün gücüyle çalışmak',
    'Ailesine bakabilmek için “dişini tırnağına takıp” çalıştı.',
  ),
  (
    'elini çabuk tutmak',
    'acele etmek',
    'Film başlamak üzere, “elini çabuk tut”.',
  ),
  ('sudan ucuz', 'çok ucuz', 'Pazar kapanırken meyveler “sudan ucuzdu”.'),
  (
    'ele avuca sığmamak',
    'çok yaramaz olmak',
    'Küçük kardeşim “ele avuca sığmıyor”, evin her yerini dağıtıyor.',
  ),
  (
    'kara çalmak',
    'iftira etmek',
    'Kıskandığı arkadaşına “kara çalmaya” kalktı.',
  ),
  (
    'hevesi kursağında kalmak',
    'isteği gerçekleşmemek',
    'Gezi iptal edilince çocukların “hevesi kursağında kaldı”.',
  ),
  (
    'kılını kıpırdatmamak',
    'hiçbir çaba göstermemek',
    'Herkes taşınma için koştururken o “kılını kıpırdatmadı”.',
  ),
  (
    'kafasına koymak',
    'bir şeyi yapmaya kesin karar vermek',
    'Doktor olmayı küçük yaşta “kafasına koymuştu”.',
  ),
  (
    'ayak uydurmak',
    'uyum sağlamak',
    'Yeni okuluna kısa sürede “ayak uydurdu”.',
  ),
  (
    'dilinde tüy bitmek',
    'aynı şeyi söylemekten bıkmak',
    'Odanı topla demekten “dilimde tüy bitti”.',
  ),
  (
    'kulaktan dolma',
    'duyarak edinilmiş, yüzeysel',
    'Bu konudaki bilgileri “kulaktan dolma”, hiç kitap okumamış.',
  ),
  (
    'göz göre göre',
    'bile bile',
    'Yanlış olduğunu bildiği hâlde “göz göre göre” bu hatayı yaptı.',
  ),
  (
    'gözü tutmak',
    'beğenmek',
    'Vitrindeki ceket “gözünü tuttu”, hemen satın aldı.',
  ),
  (
    'ipiyle kuyuya inilmez',
    'güvenilmez',
    'O adamın “ipiyle kuyuya inilmez”, sözünde hiç durmaz.',
  ),
  (
    'başını taştan taşa vurmak',
    'çok pişman olmak',
    'Fırsatı kaçırdığı için şimdi “başını taştan taşa vuruyor”.',
  ),
  (
    'içine kurt düşmek',
    'kuşkulanmak',
    'Arkadaşının telaşını görünce “içine kurt düştü”.',
  ),
  (
    'gönül koymak',
    'kırılmak, darılmak',
    'Düğüne çağrılmadığı için bize “gönül koydu”.',
  ),
  (
    'toz kondurmamak',
    'kusur yakıştırmamak',
    'Annesi, oğluna hiç “toz kondurmaz”.',
  ),
  (
    'göz kulak olmak',
    'gözetmek, korumak',
    'Ben dönene kadar kardeşine “göz kulak ol”.',
  ),
  (
    'kafası çalışmak',
    'zeki olmak',
    'Bu çocuğun “kafası çok çalışıyor”, her bulmacayı çözüyor.',
  ),
  (
    'ağır başlı',
    'ciddi ve olgun davranışlı',
    'Sınıfın en “ağır başlı” öğrencisi oydu.',
  ),
  (
    'hoşbeş etmek',
    'sohbet etmek',
    'Kapının önünde komşularla biraz “hoşbeş etti”.',
  ),
  (
    'baş göz etmek',
    'evlendirmek',
    'Yaşlı kadın, torununu “baş göz etmeyi” çok istiyordu.',
  ),
  (
    'ortalığı birbirine katmak',
    'karışıklık çıkarmak',
    'Kaybolan anahtarı ararken “ortalığı birbirine kattı”.',
  ),
  (
    'zaman öldürmek',
    'boş yere vakit geçirmek',
    'Tren gelene kadar istasyonda “zaman öldürdük”.',
  ),
  (
    'deveye hendek atlatmak',
    'çok güç bir işi başarmak',
    'Dedemi bu yolculuğa razı etmek “deveye hendek atlatmak” gibiydi.',
  ),
  (
    'gözü yüksekte olmak',
    'durumundan daha iyisini istemek',
    'Hiçbir işi beğenmiyor, “gözü yüksekte”.',
  ),
  ('eli açık', 'cömert', 'Dedem çok “eli açık” biridir, herkese yardım eder.'),
  (
    'eli sıkı',
    'cimri',
    'Komşumuz o kadar “eli sıkı” ki çocuklarına bile harçlık vermez.',
  ),
  (
    'gözü tok',
    'kanaatkâr, açgözlü olmayan',
    'O “gözü tok” biridir, kimsenin malına imrenmez.',
  ),
  (
    'boynu bükük',
    'üzgün ve kimsesiz',
    'Annesini kaybeden çocuk “boynu bükük” kalmıştı.',
  ),
  (
    'dünyadan haberi olmamak',
    'çevresinde olanları bilmemek',
    'Kitabına öyle dalmıştı ki “dünyadan haberi yoktu”.',
  ),
  (
    'kapı kapı dolaşmak',
    'bir iş için birçok yere başvurmak',
    'İş bulmak için günlerce “kapı kapı dolaştı”.',
  ),
  (
    'göze batmak',
    'dikkati çekip rahatsız etmek',
    'Beyaz duvardaki büyük leke çok “göze batıyor”.',
  ),
  (
    'kervana katılmak',
    'bir topluluğa katılmak',
    'Bu yıl da yeni gönüllüler “kervana katıldı”.',
  ),
  (
    'nalıncı keseri gibi kendine yontmak',
    'her şeyi kendi çıkarına yormak',
    'Paylaşım yaparken hep “nalıncı keseri gibi kendine yontar”.',
  ),
];

final _deyimAnlamlari = [for (final e in _deyimler) e.$2];
final _deyimAdlari = [for (final e in _deyimler) e.$1];

final _deyim = lmSirali(
  'tk_deyim',
  'Deyimlerin anlamı ve anlamı karşılayan deyim',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final x = _bicimSecki(_deyimler, i, 2);
    if (i.isEven) {
      final dogru = [for (final e in x) e.$2];
      return _sirali(
        '${_uc([for (final e in x) e.$3])}\nNumaralanmış cümlelerde tırnak '
            'içinde verilen deyimlerin cümleye kattığı anlamlar sırasıyla hangi '
            'seçenekte doğru verilmiştir?',
        dogru,
        [
          for (var p = 0; p < 3; p++)
            _baskaEtiketler(_deyimAnlamlari, dogru[p], i + 17 * p),
        ],
        '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$1}” deyimi “${x[p].$2}” anlamında kullanılmıştır'].join('; ')}.',
        i,
        tekrarsiz: true,
      );
    }
    final dogru = [for (final e in x) e.$1];
    return _sirali(
      '${_uc([for (final e in x) e.$2])}\nNumaralanmış açıklamalarla verilen '
          'anlamları karşılayan deyimler sırasıyla hangi seçenekte doğru '
          'verilmiştir?',
      dogru,
      [
        for (var p = 0; p < 3; p++)
          _baskaEtiketler(_deyimAdlari, dogru[p], i + 17 * p),
      ],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. “${x[p].$2}” anlamını “${x[p].$1}” deyimi karşılar'].join('; ')}.',
      i,
      tekrarsiz: true,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ────────────────────────────── 2 · Atasözleri ───────────────────────────────

// (atasözü, anlamı ya da verdiği öğüt). Anlamları birbirine yakın atasözleri
// (ör. “Ne ekersen onu biçersin” ile “Gülme komşuna, gelir başına”) birlikte
// alınmamıştır; her açıklama tablodaki tek bir atasözüne uyar. Sözlüklerde
// deyim olarak geçen kalıp sözler (ör. “ekmek elden, su gölden”) alınmamıştır.
const _atasozleri = [
  ('Ağaç yaşken eğilir', 'Eğitime küçük yaşta başlanmalıdır'),
  ('Damlaya damlaya göl olur', 'Küçük birikimler zamanla büyür'),
  ('Sakla samanı, gelir zamanı', 'Gereksiz görünen şey bir gün işe yarar'),
  ('Bugünün işini yarına bırakma', 'Yapılacak iş ertelenmemelidir'),
  ('Dost kara günde belli olur', 'Gerçek dost zor günde anlaşılır'),
  ('Üzüm üzüme baka baka kararır', 'İnsan arkadaşlarından etkilenir'),
  ('Ayağını yorganına göre uzat', 'Harcamanı gelirine göre ayarla'),
  (
    'Sütten ağzı yanan yoğurdu üfleyerek yer',
    'Zarar gören, sonra aşırı tedbirli olur',
  ),
  ('Bin bilsen de bir bilene danış', 'Ne kadar bilsen de bilene danışmalısın'),
  ('Komşu komşunun külüne muhtaçtır', 'Komşular birbirine her zaman muhtaçtır'),
  ('Taşıma su ile değirmen dönmez', 'Sürekli iş, geçici yardımla yürümez'),
  ('Acele işe şeytan karışır', 'Aceleyle yapılan işte hata olur'),
  ('Az olsun, öz olsun', 'Nicelikten çok nitelik önemlidir'),
  ('Bir elin nesi var, iki elin sesi var', 'Birlikte çalışmak başarı getirir'),
  ('Dereyi görmeden paçaları sıvama', 'Zamanı gelmeden hazırlığa girişme'),
  ('Ne ekersen onu biçersin', 'Herkes yaptığının karşılığını görür'),
  ('Gülü seven dikenine katlanır', 'Bir şeyi seven, zahmetine katlanır'),
  ('Tatlı dil yılanı deliğinden çıkarır', 'Güzel sözle her iş çözülür'),
  ('Söz gümüşse sükût altındır', 'Bazen susmak konuşmaktan iyidir'),
  ('Keskin sirke küpüne zarar', 'Öfkeli kişi en çok kendine zarar verir'),
  ('Görünen köy kılavuz istemez', 'Apaçık olan şey kanıt gerektirmez'),
  ('Ateş düştüğü yeri yakar', 'Acıyı en çok başına gelen çeker'),
  ('Emek olmadan yemek olmaz', 'Çalışmadan kazanç elde edilmez'),
  ('Mum dibine ışık vermez', 'Kimi insan yakınlarına yararlı olmaz'),
  ('Ağlamayan çocuğa meme vermezler', 'İstemeyen, istediğini elde edemez'),
  (
    'Her yiğidin bir yoğurt yiyişi vardır',
    'Herkesin iş yapma biçimi farklıdır',
  ),
  ('Kurunun yanında yaş da yanar', 'Suçlunun yanında suçsuz da zarar görür'),
  ('Çivi çiviyi söker', 'Bir şey ancak benzeriyle giderilir'),
  ('Balık baştan kokar', 'Bozulma önce yöneticilerden başlar'),
  ('Dervişin fikri ne ise zikri de odur', 'İnsan aklındakini dile getirir'),
  ('El elden üstündür', 'Her zaman daha üstünü bulunur'),
  ('Eski dost düşman olmaz', 'Eski dostluk kolay kolay bozulmaz'),
  ('Hatasız kul olmaz', 'Herkes hata yapabilir'),
  (
    'Kaz gelecek yerden tavuk esirgenmez',
    'Büyük kazanç için küçük fedakârlık yapılır',
  ),
  (
    'Minareyi çalan kılıfını hazırlar',
    'Suç işleyen, önceden bahanesini hazırlar',
  ),
  ('Sabreden derviş muradına ermiş', 'Sabırlı olan isteğine kavuşur'),
  ('Üzüm ye de bağını sorma', 'Yararlan ama nereden geldiğini sorma'),
  ('Yalancının mumu yatsıya kadar yanar', 'Yalan kısa sürede ortaya çıkar'),
  (
    'Dağ dağa kavuşmaz, insan insana kavuşur',
    'İnsanlar bir gün yeniden karşılaşabilir',
  ),
  ('Kendi düşen ağlamaz', 'Kendi hatasıyla zarar gören yakınmamalı'),
  ('Meyve veren ağacı taşlarlar', 'Başarılı kişiler kıskanılır'),
  (
    'Perşembenin gelişi çarşambadan bellidir',
    'Bir işin sonu başından bellidir',
  ),
  (
    'Bir fincan kahvenin kırk yıl hatırı vardır',
    'Küçük bir iyilik uzun süre unutulmaz',
  ),
  ('Doğru söyleyeni dokuz köyden kovarlar', 'Doğruyu söyleyen sevilmez'),
  ('Her işte bir hayır vardır', 'Kötü görünen olayın da iyi yanı vardır'),
  ('Sel gider, kum kalır', 'Geçici olan gider, kalıcı olan kalır'),
  ('Bal tutan parmağını yalar', 'Bir işi yöneten, ondan çıkar sağlar'),
  ('Ateş olmayan yerden duman çıkmaz', 'Her söylentinin bir aslı vardır'),
  ('Ak koyunun kara kuzusu da olur', 'İyi bir aileden kötü çocuk da çıkabilir'),
  (
    'Misafir umduğunu değil, bulduğunu yer',
    'Konuk, ev sahibinin sunduğuyla yetinir',
  ),
];

final _atasozuAnlamlari = [for (final e in _atasozleri) e.$2];
final _atasozuAdlari = [for (final e in _atasozleri) e.$1];

final _atasozu = lmSirali(
  'tk_atasozu',
  'Atasözlerinin anlamı ve verdiği öğüt',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.anlama,
  (i) {
    final x = _bicimSecki(_atasozleri, i, 2);
    final aciklama =
        '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. “${x[p].$1}” atasözü “${x[p].$2}” düşüncesini anlatır'].join('; ')}.';
    if (i.isEven) {
      final dogru = [for (final e in x) e.$2];
      return _sirali(
        '${_uc([for (final e in x) '${e.$1}.'])}\nNumaralanmış atasözlerinin '
        'anlamları ya da verdikleri öğütler sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
        dogru,
        [
          for (var p = 0; p < 3; p++)
            _baskaEtiketler(_atasozuAnlamlari, dogru[p], i + 13 * p),
        ],
        aciklama,
        i,
        tekrarsiz: true,
      );
    }
    final dogru = [for (final e in x) e.$1];
    return _sirali(
      '${_uc([for (final e in x) '${e.$2}.'])}\nNumaralanmış açıklamalarda '
      'dile getirilen düşünceleri anlatan atasözleri sırasıyla hangi seçenekte '
      'doğru verilmiştir?',
      dogru,
      [
        for (var p = 0; p < 3; p++)
          _baskaEtiketler(_atasozuAdlari, dogru[p], i + 13 * p),
      ],
      aciklama,
      i,
      tekrarsiz: true,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ───────────────── 3 · Eş anlamlı, zıt anlamlı, eş sesli sözcükler ───────────

// (sözcük, eş anlamlısı, zıt anlamlısı). Sözcükler anlamca birbirinden
// uzaktır: hiçbir sözcüğün eş ya da zıt anlamlısı başka bir sözcüğe de uymaz.
const _esZitler = [
  ('cesur', 'yürekli', 'korkak'),
  ('zengin', 'varlıklı', 'yoksul'),
  ('yaşlı', 'ihtiyar', 'genç'),
  ('siyah', 'kara', 'beyaz'),
  ('hızlı', 'süratli', 'yavaş'),
  ('eski', 'köhne', 'yeni'),
  ('geniş', 'engin', 'dar'),
  ('sevinç', 'kıvanç', 'keder'),
  ('düşman', 'hasım', 'dost'),
  ('barış', 'sulh', 'savaş'),
  ('cevap', 'yanıt', 'soru'),
  ('ilk', 'birinci', 'son'),
  ('tembel', 'üşengeç', 'çalışkan'),
  ('cimri', 'pinti', 'cömert'),
  ('temiz', 'pak', 'kirli'),
  ('özgür', 'hür', 'tutsak'),
  ('kâr', 'kazanç', 'zarar'),
  ('zor', 'güç', 'kolay'),
  ('yüksek', 'yüce', 'alçak'),
  ('eğri', 'çarpık', 'düz'),
  ('neden', 'sebep', 'sonuç'),
  ('yorgun', 'bitkin', 'dinç'),
  ('ıslak', 'yaş', 'kuru'),
  ('kibar', 'nazik', 'kaba'),
  ('sevgi', 'muhabbet', 'nefret'),
  ('hayal', 'düş', 'gerçek'),
  ('yokuş', 'bayır', 'iniş'),
  ('uzak', 'ırak', 'yakın'),
  ('sert', 'katı', 'yumuşak'),
  ('savunma', 'müdafaa', 'saldırı'),
  ('eksik', 'noksan', 'tam'),
  ('gizli', 'saklı', 'açık'),
  ('alçakgönüllü', 'mütevazı', 'kibirli'),
  ('kuzey', 'şimal', 'güney'),
  ('doğu', 'şark', 'batı'),
  ('içten', 'samimi', 'yapmacık'),
  ('övmek', 'methetmek', 'yermek'),
  ('yitirmek', 'kaybetmek', 'bulmak'),
  ('artmak', 'çoğalmak', 'azalmak'),
  ('deneyimli', 'tecrübeli', 'acemi'),
];

final _esAnlamlilar = [for (final e in _esZitler) e.$2];
final _zitAnlamlilar = [for (final e in _esZitler) e.$3];

// Başka bir sözcüğün zıt anlamlısı olup bu sözcüğe de karşıt sayılabilecek
// sözcükler (“düz yol” ile “yokuş”); bunlar o konuma çeldirici yazılmaz.
const _zitDisi = {
  'yokuş': ['düz'],
};

// (cümle, eş sesli sözcük, cümledeki anlamı, aynı sözcüğün öteki anlamları)
const _esSesliler = [
  (
    'Annesi, çocuğun kirli “yüzünü” ılık suyla yıkadı.',
    'yüz',
    'surat, çehre',
    ['sayı adı (100)', 'suda ilerlemek'],
  ),
  (
    'Kütüphaneye “yüz” yeni kitap bağışlandı.',
    'yüz',
    'sayı adı (100)',
    ['surat, çehre', 'suda ilerlemek'],
  ),
  (
    'Çocuklar gölün serin sularında saatlerce “yüzdü”.',
    'yüz',
    'suda ilerlemek',
    ['surat, çehre', 'sayı adı (100)'],
  ),
  (
    'Bahçedeki “güller” bu yıl erken açtı.',
    'gül',
    'bir çiçek',
    ['neşeyle ses çıkarmak'],
  ),
  (
    'Fıkrayı duyunca herkes kahkahalarla “güldü”.',
    'gül',
    'neşeyle ses çıkarmak',
    ['bir çiçek'],
  ),
  ('Kahvaltıda iki bardak “çay” içtim.', 'çay', 'bir içecek', ['küçük akarsu']),
  (
    'Köyün kenarından küçük bir “çay” akıyordu.',
    'çay',
    'küçük akarsu',
    ['bir içecek'],
  ),
  (
    'Öğleden sonra yağan “dolu”, bağlara zarar verdi.',
    'dolu',
    'buz taneleri hâlinde yağış',
    ['içi boş olmayan'],
  ),
  (
    'Çantası kitaplarla “doluydu”.',
    'dolu',
    'içi boş olmayan',
    ['buz taneleri hâlinde yağış'],
  ),
  (
    'Gemideki yolcular günlerce “kara” görmedi.',
    'kara',
    'denizle kaplı olmayan yer',
    ['siyah renkli'],
  ),
  (
    'Kapının önünde “kara” bir kedi oturuyordu.',
    'kara',
    'siyah renkli',
    ['denizle kaplı olmayan yer'],
  ),
  (
    'Dedem bu yıl seksen “yaşına” girdi.',
    'yaş',
    'ömür süresi',
    ['ıslak', 'gözyaşı'],
  ),
  (
    'Yağmurdan sonra çimenler hâlâ “yaştı”.',
    'yaş',
    'ıslak',
    ['ömür süresi', 'gözyaşı'],
  ),
  (
    'Veda ederken gözlerinden “yaşlar” süzüldü.',
    'yaş',
    'gözyaşı',
    ['ömür süresi', 'ıslak'],
  ),
  (
    'Sonbaharda üzüm toplamak için “bağa” gittik.',
    'bağ',
    'üzüm bahçesi',
    ['bağlamaya yarayan ip'],
  ),
  (
    'Ayakkabısının “bağı” çözülünce yere eğildi.',
    'bağ',
    'bağlamaya yarayan ip',
    ['üzüm bahçesi'],
  ),
  (
    'Pazar günü ailece “kırda” piknik yaptık.',
    'kır',
    'şehir dışındaki açık arazi',
    ['parçalara ayırmak'],
  ),
  (
    'Ceviz kabuklarını taşla “kırdık”.',
    'kır',
    'parçalara ayırmak',
    ['şehir dışındaki açık arazi'],
  ),
  (
    'Çiftlikteki beyaz “at” çok hızlı koşuyordu.',
    'at',
    'bir binek hayvanı',
    ['fırlatmak'],
  ),
  ('Çocuk topu duvara doğru “attı”.', 'at', 'fırlatmak', ['bir binek hayvanı']),
  (
    'Bu “yaz” tatilimizi köyde geçireceğiz.',
    'yaz',
    'bir mevsim',
    ['yazıya geçirmek'],
  ),
  (
    'Arkadaşına uzun bir mektup “yazdı”.',
    'yaz',
    'yazıya geçirmek',
    ['bir mevsim'],
  ),
  (
    'Toplantıya “ben” de katılacağım.',
    'ben',
    'birinci tekil kişi zamiri',
    ['deride koyu renkli leke'],
  ),
  (
    'Yanağındaki küçük “ben” onu çok sevimli gösteriyordu.',
    'ben',
    'deride koyu renkli leke',
    ['birinci tekil kişi zamiri'],
  ),
  (
    'Yemekten önce “ellerimizi” sabunla yıkadık.',
    'el',
    'vücut organı',
    ['yabancı kimse'],
  ),
  (
    'Gurbette “el” kapısında çalışmak çok zordu.',
    'el',
    'yabancı kimse',
    ['vücut organı'],
  ),
  (
    'Kuş, ağacın en yüksek “dalına” kondu.',
    'dal',
    'ağacın kolu',
    ['suyun içine girmek'],
  ),
  (
    'Batık gemiyi görmek için denizin derinliklerine “daldı”.',
    'dal',
    'suyun içine girmek',
    ['ağacın kolu'],
  ),
  (
    'Ağır kutuyu kaldırınca “beli” ağrıdı.',
    'bel',
    'vücudun orta bölümü',
    ['toprak kazma aracı'],
  ),
  (
    'Bahçıvan, toprağı “belle” derin derin kazdı.',
    'bel',
    'toprak kazma aracı',
    ['vücudun orta bölümü'],
  ),
  (
    'Çiftlikteki “kazlar” göle doğru yürüdü.',
    'kaz',
    'bir kümes hayvanı',
    ['toprağı oymak'],
  ),
  (
    'İşçiler binanın temeli için toprağı derin “kazdı”.',
    'kaz',
    'toprağı oymak',
    ['bir kümes hayvanı'],
  ),
  ('Dün gece çok güzel bir “düş” gördüm.', 'düş', 'rüya', ['yere yıkılmak']),
  ('Buzlu yolda yürürken “düştü”.', 'düş', 'yere yıkılmak', ['rüya']),
  (
    'Depremden üç gün sonra enkazdan “sağ” olarak çıkarıldı.',
    'sağ',
    'canlı, diri',
    ['sol karşıtı yön'],
  ),
  ('İkinci sokaktan “sağa” dönün.', 'sağ', 'sol karşıtı yön', ['canlı, diri']),
  (
    'Ağaçlar fırtınaya rağmen “dik” duruyordu.',
    'dik',
    'dikey, eğik olmayan',
    ['iğne ve iplikle tutturmak'],
  ),
  (
    'Terzi, kopan düğmeyi hemen “dikti”.',
    'dik',
    'iğne ve iplikle tutturmak',
    ['dikey, eğik olmayan'],
  ),
  (
    'Stadyumu yaklaşık “bin” kişi doldurmuştu.',
    'bin',
    'sayı adı (1000)',
    ['bir taşıta yerleşmek'],
  ),
  (
    'Okula gitmek için sabah servise “bindik”.',
    'bin',
    'bir taşıta yerleşmek',
    ['sayı adı (1000)'],
  ),
  (
    'İki evin “arası” yalnızca iki metreydi.',
    'ara',
    'iki şey arasındaki uzaklık',
    ['bulmaya çalışmak'],
  ),
  (
    'Kaybolan anahtarı her yerde “aradık”.',
    'ara',
    'bulmaya çalışmak',
    ['iki şey arasındaki uzaklık'],
  ),
  (
    'Limana lüks bir “yat” yanaştı.',
    'yat',
    'gezinti teknesi',
    ['uykuya çekilmek'],
  ),
  (
    'Çok yorulduğu için erkenden “yattı”.',
    'yat',
    'uykuya çekilmek',
    ['gezinti teknesi'],
  ),
  (
    'Âşık, “sazını” eline alıp türküler söyledi.',
    'saz',
    'telli bir çalgı',
    ['su kıyısında biten bitki'],
  ),
  (
    'Gölün kıyısını uzun “sazlar” kaplamıştı.',
    'saz',
    'su kıyısında biten bitki',
    ['telli bir çalgı'],
  ),
  (
    'Merdivenleri koşarak çıkınca “soluğu” kesildi.',
    'soluk',
    'nefes',
    ['rengi atmış'],
  ),
  (
    'Güneşte kalan perdenin rengi “soluk” görünüyordu.',
    'soluk',
    'rengi atmış',
    ['nefes'],
  ),
  (
    'Mektubun ilk “satırını” okuyunca gülümsedi.',
    'satır',
    'yazı dizisi',
    ['et kesme bıçağı'],
  ),
  (
    'Kasap, eti büyük bir “satırla” parçaladı.',
    'satır',
    'et kesme bıçağı',
    ['yazı dizisi'],
  ),
  (
    'Yazarken kalemin “ucu” kırıldı.',
    'uç',
    'bir şeyin son noktası',
    ['havada ilerlemek'],
  ),
  (
    'Leylekler sonbaharda güneye doğru “uçtu”.',
    'uç',
    'havada ilerlemek',
    ['bir şeyin son noktası'],
  ),
  (
    'Ayı, kış uykusu için “inine” çekildi.',
    'in',
    'yabani hayvan barınağı',
    ['bir taşıttan çıkmak'],
  ),
  (
    'Otobüsten son durakta “indik”.',
    'in',
    'bir taşıttan çıkmak',
    ['yabani hayvan barınağı'],
  ),
  (
    'Tekne, rüzgârdan korunmak için küçük bir “koya” sığındı.',
    'koy',
    'küçük körfez',
    ['bir yere bırakmak'],
  ),
  (
    'Okuduğum kitapları rafa “koydum”.',
    'koy',
    'bir yere bırakmak',
    ['küçük körfez'],
  ),
  (
    'Kamp ateşini yakmak için “çakmak” aradık.',
    'çakmak',
    'ateş yakma aracı',
    ['vurarak sokmak'],
  ),
  (
    'Tabloyu asmak için duvara bir çivi “çaktı”.',
    'çakmak',
    'vurarak sokmak',
    ['ateş yakma aracı'],
  ),
  (
    'Fırından sıcak bir “ekmek” aldım.',
    'ekmek',
    'undan yapılan yiyecek',
    ['toprağa tohum atmak'],
  ),
  (
    'Çiftçi bu yıl tarlasına buğday “ekti”.',
    'ekmek',
    'toprağa tohum atmak',
    ['undan yapılan yiyecek'],
  ),
  (
    'Coğrafya dersinde “atlastan” Türkiye haritasını inceledik.',
    'atlas',
    'harita kitabı',
    ['parlak ipek kumaş'],
  ),
  (
    'Gelinlik, parlak beyaz bir “atlastan” dikilmişti.',
    'atlas',
    'parlak ipek kumaş',
    ['harita kitabı'],
  ),
];

final _esSesliAnlamlari = [for (final e in _esSesliler) e.$3];

final _esZit = lmSirali(
  'tk_es_zit',
  'Eş anlamlı, zıt anlamlı ve eş sesli sözcükler',
  Topic.literature,
  Difficulty.easy,
  BloomLevel.anlama,
  (i) {
    final bicim = i % 3;
    if (bicim == 2) {
      final x = _bicimSecki(_esSesliler, i, 3);
      final dogru = [for (final e in x) e.$3];
      return _sirali(
        '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde tırnak '
            'içinde verilen eş sesli sözcüklerin bu cümlelerdeki anlamları '
            'sırasıyla hangi seçenekte doğru verilmiştir?',
        dogru,
        [
          for (var p = 0; p < 3; p++)
            [
              ...x[p].$4,
              ..._baskaEtiketler(
                _esSesliAnlamlari,
                dogru[p],
                i + 11 * p,
              ).where((s) => !x[p].$4.contains(s)),
            ],
        ],
        '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$2}” sözcüğü “${x[p].$3}” anlamındadır'].join('; ')}.',
        i,
        tekrarsiz: true,
      );
    }
    final x = _bicimSecki(_esZitler, i, 3);
    final esMi = bicim == 0;
    final dogru = [for (final e in x) esMi ? e.$2 : e.$3];
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış sözcüklerin '
          '${esMi ? 'eş anlamlıları' : 'zıt (karşıt) anlamlıları'} sırasıyla '
          'hangi seçenekte doğru verilmiştir?',
      dogru,
      [
        for (var p = 0; p < 3; p++)
          [
            // En sık yapılan hata eş ve zıt anlamlıyı karıştırmaktır.
            esMi ? x[p].$3 : x[p].$2,
            ..._baskaEtiketler(
              esMi ? _esAnlamlilar : _zitAnlamlilar,
              dogru[p],
              i + 11 * p,
            ).where(
              (s) => esMi || !(_zitDisi[x[p].$1] ?? const []).contains(s),
            ),
          ],
      ],
      '${[for (final e in x) '${e.$1}: eş anlamlısı “${e.$2}”, zıt anlamlısı “${e.$3}”'].join('; ')}.',
      i,
      tekrarsiz: true,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ──────────────────────────── 4 · Noktalama işaretleri ───────────────────────

const _nokta = 'nokta';
const _virgul = 'virgül';
const _nvirgul = 'noktalı virgül';
const _ikinokta = 'iki nokta';
const _soru = 'soru işareti';
const _unlem = 'ünlem işareti';
const _kesme = 'kesme işareti';
const _cizgi = 'kısa çizgi';

// (cümle, ayraçla gösterilen yere gelen işaret, o yerde kesin yanlış olan ve
//  çeldiricide kullanılan işaretler, o yerde tartışılabileceği için hiçbir
//  soruda yanlış sayılmayan işaretler, TDK kuralı). Ayraçtan sonra küçük
//  harfle süren cümlelerde nokta, ünlem ve soru işareti kendiliğinden elenir.
const _noktalamalar = [
  (
    'Bu cami 16( ) yüzyılda yapılmıştır.',
    _nokta,
    [_kesme, _cizgi, _virgul],
    <String>[],
    'sıra bildiren rakamdan sonra nokta konur',
  ),
  (
    'Kardeşim bu yıl 9( ) sınıfa başladı.',
    _nokta,
    [_kesme, _cizgi, _virgul],
    <String>[],
    'sıra bildiren rakamdan sonra nokta konur',
  ),
  (
    'Yarışmayı 3( ) sırada bitiren öğrenci de ödül aldı.',
    _nokta,
    [_kesme, _cizgi, _virgul],
    <String>[],
    'sıra bildiren rakamdan sonra nokta konur',
  ),
  (
    'Toplantı binanın 4( ) katındaki salonda yapılacak.',
    _nokta,
    [_kesme, _cizgi, _virgul],
    <String>[],
    'sıra bildiren rakamdan sonra nokta konur',
  ),
  (
    'Konferansı Prof( ) Dr. Ayşe Yılmaz verdi.',
    _nokta,
    [_kesme, _virgul, _cizgi],
    <String>[],
    'kısaltmalardan sonra nokta konur',
  ),
  (
    'Masaya kalem, defter, silgi vb( ) araçları koyduk.',
    _nokta,
    [_virgul, _kesme, _ikinokta],
    <String>[],
    'kısaltmalardan sonra nokta konur',
  ),
  (
    'Mektubu Atatürk Cad( ) üzerindeki postaneden gönderdim.',
    _nokta,
    [_kesme, _virgul, _cizgi],
    <String>[],
    'kısaltmalardan sonra nokta konur',
  ),
  (
    'Hastaneye yeni gelen Dr( ) Mehmet Bey hastaları tek tek muayene etti.',
    _nokta,
    [_kesme, _virgul, _cizgi],
    <String>[],
    'kısaltmalardan sonra nokta konur',
  ),
  (
    'Pazardan elma( ) armut ve kiraz aldık.',
    _virgul,
    [_nvirgul, _ikinokta, _nokta],
    <String>[],
    'eş görevli sözcükler arasına virgül konur',
  ),
  (
    'Çantasına kalem( ) silgi ve cetvel koydu.',
    _virgul,
    [_nvirgul, _ikinokta, _nokta],
    <String>[],
    'eş görevli sözcükler arasına virgül konur',
  ),
  (
    'Kapıyı açtı( ) içeri girdi ve ışığı yaktı.',
    _virgul,
    [_ikinokta, _nokta, _cizgi],
    [_nvirgul],
    'sıralı cümleler arasına virgül konur',
  ),
  (
    'Sabah erkenden kalktı( ) kahvaltısını yaptı ve okula gitti.',
    _virgul,
    [_ikinokta, _nokta, _cizgi],
    [_nvirgul],
    'sıralı cümleler arasına virgül konur',
  ),
  (
    'Çocuklar bahçede koştu( ) bağırdı ve sonunda yoruldu.',
    _virgul,
    [_ikinokta, _nokta, _cizgi],
    [_nvirgul],
    'sıralı cümleler arasına virgül konur',
  ),
  // TDK, seslenme ve hitap sözlerinden sonra ünlem de konabileceğini yazar;
  // bu yüzden bu iki cümlede ünlem ne çeldirici yapılır ne de sorulur.
  (
    'Ayşe( ) bana şu kitabı uzatır mısın?',
    _virgul,
    [_ikinokta, _nokta, _nvirgul],
    [_unlem],
    'hitap sözünden sonra virgül konur',
  ),
  (
    'Sevgili Elif( ) mektubunu büyük bir sevinçle okudum.',
    _virgul,
    [_ikinokta, _nokta, _nvirgul],
    [_unlem],
    'hitap sözünden sonra virgül konur',
  ),
  (
    'Evet( ) yarın sabah erkenden yola çıkacağız.',
    _virgul,
    [_ikinokta, _nokta, _nvirgul],
    <String>[],
    'cümle başındaki “evet” sözünden sonra virgül konur',
  ),
  (
    'Hayır( ) bu akşam sinemaya gitmiyorum.',
    _virgul,
    [_ikinokta, _nokta, _nvirgul],
    <String>[],
    'cümle başındaki “hayır” sözünden sonra virgül konur',
  ),
  (
    'Peki( ) bu konuyu yarın yeniden konuşalım.',
    _virgul,
    [_ikinokta, _nokta, _nvirgul],
    <String>[],
    'cümle başındaki “peki” sözünden sonra virgül konur',
  ),
  (
    'Bebeğin doğum ağırlığı 3( )2 kilogramdı.',
    _virgul,
    [_nokta, _kesme, _nvirgul],
    <String>[],
    'ondalık sayılarda tam kısım virgülle ayrılır',
  ),
  (
    'Kumaşın eni 1( )5 metre olarak ölçüldü.',
    _virgul,
    [_nokta, _kesme, _nvirgul],
    <String>[],
    'ondalık sayılarda tam kısım virgülle ayrılır',
  ),
  (
    'Erkek çocuklara Ali, Murat, Orhan( ) kız çocuklara Ayşe, Fatma, Zeynep adları verilmiş.',
    _nvirgul,
    [_virgul, _ikinokta, _nokta],
    <String>[],
    'virgüllerle ayrılmış takımlar noktalı virgülle ayrılır',
  ),
  (
    'Bahçeye domates, biber, patlıcan( ) tarlaya buğday, arpa, mısır ektik.',
    _nvirgul,
    [_virgul, _ikinokta, _nokta],
    <String>[],
    'virgüllerle ayrılmış takımlar noktalı virgülle ayrılır',
  ),
  (
    'Birinci rafa romanları, öyküleri( ) ikinci rafa sözlükleri, ansiklopedileri yerleştirdik.',
    _nvirgul,
    [_virgul, _ikinokta, _nokta],
    <String>[],
    'virgüllerle ayrılmış takımlar noktalı virgülle ayrılır',
  ),
  (
    'Kahvaltıda peynir, zeytin, bal( ) akşam yemeğinde çorba, pilav, salata vardı.',
    _nvirgul,
    [_virgul, _ikinokta, _nokta],
    <String>[],
    'virgüllerle ayrılmış takımlar noktalı virgülle ayrılır',
  ),
  (
    'Kırmızı takımda Ece, Can, Deniz( ) mavi takımda Emre, Selin, Ozan oynadı.',
    _nvirgul,
    [_virgul, _ikinokta, _nokta],
    <String>[],
    'virgüllerle ayrılmış takımlar noktalı virgülle ayrılır',
  ),
  (
    'Sabahları matematik, fizik( ) öğleden sonra tarih, coğrafya çalışıyorum.',
    _nvirgul,
    [_virgul, _ikinokta, _nokta],
    <String>[],
    'virgüllerle ayrılmış takımlar noktalı virgülle ayrılır',
  ),
  (
    'Çantama şunları koydum( ) kalem, defter ve silgi.',
    _ikinokta,
    [_nvirgul, _virgul, _cizgi],
    <String>[],
    'örnek verilecek cümleden sonra iki nokta konur',
  ),
  (
    'Bahçemizde dört tür ağaç var( ) elma, armut, erik ve ceviz.',
    _ikinokta,
    [_nvirgul, _virgul, _cizgi],
    <String>[],
    'örnek verilecek cümleden sonra iki nokta konur',
  ),
  (
    'Sınavda üç dersten soru çıktı( ) matematik, fizik ve kimya.',
    _ikinokta,
    [_nvirgul, _virgul, _cizgi],
    <String>[],
    'örnek verilecek cümleden sonra iki nokta konur',
  ),
  (
    'Kütüphaneden iki kitap aldım( ) bir roman ve bir şiir kitabı.',
    _ikinokta,
    [_nvirgul, _virgul, _kesme],
    <String>[],
    'örnek verilecek cümleden sonra iki nokta konur',
  ),
  (
    'Başarının tek bir sırrı var( ) düzenli çalışmak.',
    _ikinokta,
    [_nvirgul, _virgul, _kesme],
    <String>[],
    'açıklama yapılacak cümleden sonra iki nokta konur',
  ),
  (
    'Bu yolculukta tek bir şey istiyorum( ) huzur.',
    _ikinokta,
    [_nvirgul, _virgul, _kesme],
    <String>[],
    'açıklama yapılacak cümleden sonra iki nokta konur',
  ),
  (
    'Bu kitabı kütüphaneden ne zaman aldın( )',
    _soru,
    [_unlem, _nokta, _virgul],
    <String>[],
    'soru bildiren cümlenin sonuna soru işareti konur',
  ),
  (
    'Yarın bize gelecek misiniz( )',
    _soru,
    [_unlem, _nokta, _virgul],
    <String>[],
    'soru bildiren cümlenin sonuna soru işareti konur',
  ),
  (
    'Toplantı saat kaçta başlayacak( )',
    _soru,
    [_unlem, _nokta, _virgul],
    <String>[],
    'soru bildiren cümlenin sonuna soru işareti konur',
  ),
  (
    'Ödevini bitirdin mi( )',
    _soru,
    [_unlem, _nokta, _virgul],
    <String>[],
    'soru bildiren cümlenin sonuna soru işareti konur',
  ),
  (
    'Bu güzel resmi kim yaptı( )',
    _soru,
    [_unlem, _nokta, _virgul],
    <String>[],
    'soru bildiren cümlenin sonuna soru işareti konur',
  ),
  (
    'Hafta sonu bizimle pikniğe gelir misin( )',
    _soru,
    [_unlem, _nokta, _virgul],
    <String>[],
    'soru bildiren cümlenin sonuna soru işareti konur',
  ),
  (
    'Ne kadar güzel bir manzara( )',
    _unlem,
    [_soru, _virgul, _ikinokta],
    [_nokta],
    'şaşma ve hayranlık bildiren cümlenin sonuna ünlem işareti konur',
  ),
  (
    'Ne güzel bir sürpriz( )',
    _unlem,
    [_soru, _virgul, _ikinokta],
    [_nokta],
    'sevinç bildiren cümlenin sonuna ünlem işareti konur',
  ),
  (
    'Yaşasın, takımımız şampiyon oldu( )',
    _unlem,
    [_soru, _virgul, _ikinokta],
    [_nokta],
    'sevinç bildiren cümlenin sonuna ünlem işareti konur',
  ),
  (
    'Ne kadar da büyümüşsün( )',
    _unlem,
    [_soru, _virgul, _ikinokta],
    [_nokta],
    'şaşma bildiren cümlenin sonuna ünlem işareti konur',
  ),
  (
    'İmdat, biri bana yardım etsin( )',
    _unlem,
    [_soru, _virgul, _ikinokta],
    [_nokta],
    'korku ve yardım isteği bildiren cümlenin sonuna ünlem işareti konur',
  ),
  (
    'Eyvah, otobüsü kaçırdık( )',
    _unlem,
    [_soru, _virgul, _ikinokta],
    [_nokta],
    'üzüntü bildiren cümlenin sonuna ünlem işareti konur',
  ),
  (
    'Aman, ne tatlı bir kedi( )',
    _unlem,
    [_soru, _virgul, _ikinokta],
    [_nokta],
    'hayranlık bildiren cümlenin sonuna ünlem işareti konur',
  ),
  (
    'Geçen yaz ailemle Antalya( )ya gittik.',
    _kesme,
    [_cizgi, _nokta, _virgul],
    <String>[],
    'özel adlara getirilen ekler kesme işaretiyle ayrılır',
  ),
  (
    'Bu yıl tatilde Kapadokya( )yı gezdik.',
    _kesme,
    [_cizgi, _nokta, _virgul],
    <String>[],
    'özel adlara getirilen ekler kesme işaretiyle ayrılır',
  ),
  (
    'Elif( )in doğum günü yarın kutlanacak.',
    _kesme,
    [_cizgi, _nokta, _virgul],
    <String>[],
    'özel adlara getirilen ekler kesme işaretiyle ayrılır',
  ),
  (
    'Mektubu Mehmet( )e verdim.',
    _kesme,
    [_cizgi, _nokta, _virgul],
    <String>[],
    'özel adlara getirilen ekler kesme işaretiyle ayrılır',
  ),
  (
    'Akşamki haberleri TRT( )den izledik.',
    _kesme,
    [_cizgi, _nokta, _virgul],
    <String>[],
    'kısaltmalara getirilen ekler kesme işaretiyle ayrılır',
  ),
  (
    'TBMM( )nin açılış töreni televizyonda yayımlandı.',
    _kesme,
    [_cizgi, _nokta, _virgul],
    <String>[],
    'kısaltmalara getirilen ekler kesme işaretiyle ayrılır',
  ),
  (
    'Van Gölü( )nün kıyısında güzel bir akşam geçirdik.',
    _kesme,
    [_cizgi, _nokta, _virgul],
    <String>[],
    'özel adlara getirilen ekler kesme işaretiyle ayrılır',
  ),
  (
    'Ankara( )İstanbul hızlı treni üç saatte gidiyor.',
    _cizgi,
    [_kesme, _nokta, _ikinokta],
    [_virgul],
    '“arası” anlamı veren iki ad arasına kısa çizgi konur',
  ),
  (
    'Kütüphaneden Türkçe( )İngilizce bir sözlük aldım.',
    _cizgi,
    [_kesme, _nokta, _ikinokta],
    [_virgul],
    '“ve” anlamı veren iki ad arasına kısa çizgi konur',
  ),
  (
    'Akşam Türkiye( )Almanya maçını izledik.',
    _cizgi,
    [_kesme, _nokta, _ikinokta],
    [_virgul],
    '“ile” anlamı veren iki ad arasına kısa çizgi konur',
  ),
  (
    'Okulumuzda öğrenci( )öğretmen ilişkileri çok iyidir.',
    _cizgi,
    [_kesme, _nokta, _ikinokta],
    [_virgul],
    '“ile” anlamı veren iki ad arasına kısa çizgi konur',
  ),
  (
    'Birinci Dünya Savaşı 1914( )1918 yılları arasında sürdü.',
    _cizgi,
    [_kesme, _nokta, _ikinokta],
    [_virgul],
    '“arası” anlamı veren iki sayı arasına kısa çizgi konur',
  ),
  (
    'İzmir( )Ankara kara yolu bayram boyunca çok yoğundu.',
    _cizgi,
    [_kesme, _nokta, _ikinokta],
    [_virgul],
    '“arası” anlamı veren iki ad arasına kısa çizgi konur',
  ),
];

final _noktalamaSerpik = _serpistir(_noktalamalar, 8);

// Sıralı biçimin (çift sıra numaraları) seçkileri: üç cümleye ayrı işaretler
// gelir ve her konuma öteki iki cümlenin işaretinden ayrı birer çeldirici
// bulunur ([_sirali] dengeli kipi).
final _noktalamaSecki = _uygunSecki(
  _noktalamaSerpik,
  _bicimBoyu(2),
  (x) => _dengeliKurulur([for (final e in x) e.$2], [for (final e in x) e.$3]),
);

final _noktalama = lmSirali(
  'tk_noktalama',
  'Noktalama işaretleri: boş bırakılan yere gelen işaret',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final x = _bicimSecki(_noktalamaSerpik, i, 2, [_noktalamaSecki, null]);
    final etiket = [for (final e in x) e.$2];
    final liste = _uc([for (final e in x) e.$1]);
    final aciklama =
        '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede ${x[p].$2}: ${x[p].$5}'].join('; ')}.';
    if (i.isOdd) {
      // Sorulan işaret, öteki cümlelerin hiçbirinde tartışmalı olmamalıdır.
      var hedef = etiket[0];
      for (var s = 0; s < 3; s++) {
        final aday = etiket[(i ~/ 2 + s) % 3];
        var uygun = true;
        for (var p = 0; p < 3; p++) {
          if (etiket[p] != aday && x[p].$4.contains(aday)) uygun = false;
        }
        if (uygun) {
          hedef = aday;
          break;
        }
      }
      return _hangileri(
        '$liste\nNumaralanmış cümlelerin hangilerinde ayraçla gösterilen yere '
        '$hedef getirilmelidir?',
        _maske(etiket, hedef),
        aciklama,
        i,
      );
    }
    return _sirali(
      '$liste\nNumaralanmış cümlelerde ayraçla gösterilen yerlere sırasıyla '
      'hangi noktalama işaretleri getirilmelidir?',
      etiket,
      [for (final e in x) e.$3],
      aciklama,
      i,
      dengeli: true,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ─────────────────────────────── 5 · Fiilimsiler ─────────────────────────────

const _isimFiil = 'isim-fiil';
const _sifatFiil = 'sıfat-fiil';
const _zarfFiil = 'zarf-fiil';
const _fiilimsiTurleri = [_isimFiil, _sifatFiil, _zarfFiil];

// (cümle, tırnak içindeki fiilimsi, türü, ekin temel biçimi, çözümleme).
// Bütün soru biçimleri yalnız tırnak içindeki sözcüğü sorar (birkaç cümlede
// başka bir fiilimsi de vardır: sandığım, olduğunu); kalıcı ad olmuş sözcükler
// (dondurma, yakacak, gelecek gibi) alınmamıştır.
const _fiilimsiler = [
  (
    'Her sabah parkta “yürümek” bana iyi geliyor.',
    'yürümek',
    _isimFiil,
    '-mak',
    'yürü-mek',
  ),
  (
    'Kardeşim kitap “okumayı” çok sever.',
    'okumayı',
    _isimFiil,
    '-ma',
    'oku-ma-yı',
  ),
  (
    'Annemin bana öyle “bakışından” kızgın olduğunu anladım.',
    'bakışından',
    _isimFiil,
    '-ış',
    'bak-ış-ından',
  ),
  (
    'Bu soruyu “çözmek” sandığım kadar kolay değildi.',
    'çözmek',
    _isimFiil,
    '-mak',
    'çöz-mek',
  ),
  (
    'Erken “uyumak” sağlığa çok yararlıdır.',
    'uyumak',
    _isimFiil,
    '-mak',
    'uyu-mak',
  ),
  (
    'Çocuklar bahçede top “oynamayı” çok seviyor.',
    'oynamayı',
    _isimFiil,
    '-ma',
    'oyna-ma-yı',
  ),
  (
    'Sınavı “kazanması” bütün aileyi sevindirdi.',
    'kazanması',
    _isimFiil,
    '-ma',
    'kazan-ma-sı',
  ),
  (
    'Kardeşimin bu kadar hızlı “koşması” hepimizi şaşırttı.',
    'koşması',
    _isimFiil,
    '-ma',
    'koş-ma-sı',
  ),
  (
    'Onun böyle yüksek sesle “konuşması” hoşuma gitmedi.',
    'konuşması',
    _isimFiil,
    '-ma',
    'konuş-ma-sı',
  ),
  // -ış biçimleri kalıcı ad sayılmasın diye eylem anlamını koruyan bir tümleç
  // ya da zarfla birlikte verilir (bana öyle bakış, bize sevgiyle gülüş).
  (
    'Dedemin bize sevgiyle “gülüşü” içimizi ısıtırdı.',
    'gülüşü',
    _isimFiil,
    '-ış',
    'gül-üş-ü',
  ),
  (
    'Arkadaşlarıyla sinemaya “gitmek” istiyordu.',
    'gitmek',
    _isimFiil,
    '-mak',
    'git-mek',
  ),
  (
    'Akşamları balkonda çay “içmek” en büyük keyfimdir.',
    'içmek',
    _isimFiil,
    '-mak',
    'iç-mek',
  ),
  (
    'Yağmurda “ıslanmak” hiç hoşuma gitmez.',
    'ıslanmak',
    _isimFiil,
    '-mak',
    'ıslan-mak',
  ),
  (
    'Dedemin olayları “anlatışı” hepimizi etkiledi.',
    'anlatışı',
    _isimFiil,
    '-ış',
    'anlat-ış-ı',
  ),
  (
    'Bahçede “oynayan” çocuklar çok neşeliydi.',
    'oynayan',
    _sifatFiil,
    '-an',
    'oyna-y-an',
  ),
  (
    '“Okuduğum” kitabı arkadaşıma ödünç verdim.',
    'okuduğum',
    _sifatFiil,
    '-dık',
    'oku-duğ-um',
  ),
  (
    'Yarın sabah “gidecek” yolcular erkenden hazırlandı.',
    'gidecek',
    _sifatFiil,
    '-acak',
    'gid-ecek',
  ),
  (
    'Gezide “görülesi” bir manzarayla karşılaştık.',
    'görülesi',
    _sifatFiil,
    '-ası',
    'gör-ül-esi',
  ),
  (
    'Ağaca “tırmanan” kediyi itfaiye kurtardı.',
    'tırmanan',
    _sifatFiil,
    '-an',
    'tırman-an',
  ),
  (
    'Dün “izlediğimiz” film çok etkileyiciydi.',
    'izlediğimiz',
    _sifatFiil,
    '-dık',
    'izle-diğ-imiz',
  ),
  (
    'Masada “kırılmış” bir vazo duruyordu.',
    'kırılmış',
    _sifatFiil,
    '-mış',
    'kır-ıl-mış',
  ),
  (
    'Kapıda “bekleyen” adam babamın eski bir arkadaşıydı.',
    'bekleyen',
    _sifatFiil,
    '-an',
    'bekle-y-en',
  ),
  (
    'Tören için “okunacak” şiiri birlikte seçtik.',
    'okunacak',
    _sifatFiil,
    '-acak',
    'oku-n-acak',
  ),
  (
    'Bize “gülümseyen” kız yeni komşumuzdu.',
    'gülümseyen',
    _sifatFiil,
    '-an',
    'gülümse-y-en',
  ),
  (
    'Annemin “ördüğü” kazak çok sıcak tutuyor.',
    'ördüğü',
    _sifatFiil,
    '-dık',
    'ör-düğ-ü',
  ),
  (
    'Yolda “unutulmuş” bir çanta bulduk.',
    'unutulmuş',
    _sifatFiil,
    '-mış',
    'unut-ul-muş',
  ),
  (
    'Pazardan “alacağımız” meyveleri listeye yazdık.',
    'alacağımız',
    _sifatFiil,
    '-acak',
    'al-acağ-ımız',
  ),
  (
    'Duvara “asılmış” tabloyu çok beğendim.',
    'asılmış',
    _sifatFiil,
    '-mış',
    'as-ıl-mış',
  ),
  (
    'Eve “gelince” hemen ödevini yaptı.',
    'gelince',
    _zarfFiil,
    '-ınca',
    'gel-ince',
  ),
  (
    'Çocuklar sınıfa “koşarak” girdi.',
    'koşarak',
    _zarfFiil,
    '-arak',
    'koş-arak',
  ),
  (
    'Kapıyı “çalmadan” içeri girdi.',
    'çalmadan',
    _zarfFiil,
    '-madan',
    'çal-madan',
  ),
  ('Kitabını “alıp” kütüphaneye gitti.', 'alıp', _zarfFiil, '-ıp', 'al-ıp'),
  (
    'Okula “giderken” yolda bir arkadaşına rastladı.',
    'giderken',
    _zarfFiil,
    '-ken',
    'gid-er-ken',
  ),
  ('Bu şehre “geleli” iki yıl oldu.', 'geleli', _zarfFiil, '-alı', 'gel-eli'),
  (
    'Kitap “okudukça” ufkumuz genişler.',
    'okudukça',
    _zarfFiil,
    '-dıkça',
    'oku-dukça',
  ),
  (
    'Çocuk “ağlaya ağlaya” annesinin yanına koştu.',
    'ağlaya ağlaya',
    _zarfFiil,
    '-a … -a',
    'ağla-y-a ağla-y-a',
  ),
  (
    'Hiç “durmadan” saatlerce çalıştı.',
    'durmadan',
    _zarfFiil,
    '-madan',
    'dur-madan',
  ),
  (
    'Sınıftan “çıkınca” telefonunu açtı.',
    'çıkınca',
    _zarfFiil,
    '-ınca',
    'çık-ınca',
  ),
  ('Yemeğini “yiyip” odasına çekildi.', 'yiyip', _zarfFiil, '-ıp', 'yi-y-ip'),
  (
    'Yüzüme “bakarak” tatlı tatlı gülümsedi.',
    'bakarak',
    _zarfFiil,
    '-arak',
    'bak-arak',
  ),
  (
    'Kütüphaneden “çıkar çıkmaz” arkadaşını aradı.',
    'çıkar çıkmaz',
    _zarfFiil,
    '-ar … -maz',
    'çık-ar çık-maz',
  ),
  (
    'Kardeşim okuldan eve “koşa koşa” geldi.',
    'koşa koşa',
    _zarfFiil,
    '-a … -a',
    'koş-a koş-a',
  ),
];

const _fiilimsiEkleri = [
  '-ma', '-mak', '-ış', '-an', '-ası', '-dık', '-acak', '-mış', //
  '-ınca', '-arak', '-ıp', '-madan', '-ken', '-alı', '-dıkça', '-a … -a', //
  '-ar … -maz',
];

// Tipik karıştırmalar. “-madan” içinde “-ma”, “-dıkça” içinde “-dık” sesleri
// bulunduğundan bu ikililer birbirinin çeldiricisi yapılmaz.
const _ekKarisan = {
  '-ma': ['-mak', '-ış'],
  '-mak': ['-ma', '-acak'],
  '-ış': ['-ıp', '-ma'],
  '-an': ['-ınca', '-arak'],
  '-ası': ['-a … -a', '-an'],
  '-dık': ['-mış', '-an'],
  '-acak': ['-arak', '-an'],
  '-mış': ['-dık', '-an'],
  '-ınca': ['-an', '-ıp'],
  '-arak': ['-acak', '-an'],
  '-ıp': ['-ış', '-ınca'],
  '-madan': ['-arak', '-ınca'],
  '-ken': ['-ınca', '-arak'],
  '-alı': ['-a … -a', '-ınca'],
  '-dıkça': ['-ınca', '-madan'],
  '-a … -a': ['-arak', '-alı'],
  '-ar … -maz': ['-ınca', '-a … -a'],
};
const _ekDisi = {
  '-madan': ['-ma'],
  '-dıkça': ['-dık'],
  '-ma': ['-madan'],
  '-dık': ['-dıkça'],
};

final _fiilimsiSerpik = _serpistir(_fiilimsiler, 3);

List<String> _turYanlislari(String tur) => [
  for (final t in _fiilimsiTurleri)
    if (t != tur) t,
];

List<String> _ekYanlislari(String ek, int kay) => _digerleri(
  [
    for (final s in _fiilimsiEkleri)
      if (!(_ekDisi[ek] ?? const <String>[]).contains(s)) s,
  ],
  ek,
  kay,
  _ekKarisan[ek]!,
);

// Sıralı biçimlerin seçkileri ([_sirali] dengeli kipi). Üç tür bulunduğundan
// tür biçiminde üç türü ayrı üçlüye temiz çeldirici kurulamaz; bu biçimde
// tam iki fiilimsisi aynı türden üçlüler alınır. Ek biçiminde üç ek ayrıdır.
final _fiilimsiSecki = <List<int>?>[
  _uygunSecki(
    _fiilimsiSerpik,
    _bicimBoyu(3),
    (x) => _dengeliKurulur(
      [for (final e in x) e.$3],
      [for (final e in x) _turYanlislari(e.$3)],
      ayri: false,
      ikili: true,
    ),
  ),
  null,
  _uygunSecki(
    _fiilimsiSerpik,
    _bicimBoyu(3),
    (x) => _dengeliKurulur(
      [for (final e in x) e.$4],
      [for (final e in x) _ekYanlislari(e.$4, 0)],
    ),
  ),
];

final _fiilimsi = lmSirali(
  'tk_fiilimsi',
  'Fiilimsiler: tür ve fiilimsi eki',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.analiz,
  (i) {
    final bicim = i % 3;
    final x = _bicimSecki(_fiilimsiSerpik, i, 3, _fiilimsiSecki);
    final tur = [for (final e in x) e.$3];
    final liste = _uc([for (final e in x) e.$1]);
    final aciklama =
        '${[for (final e in x) '“${e.$2}” (${e.$5}): ${e.$3}, eki ${e.$4}'].join('; ')}.';
    if (bicim == 1) {
      final hedef = tur[i ~/ 3 % 3];
      return _hangileri(
        '$liste\nNumaralanmış cümlelerin hangilerinde tırnak içinde verilen '
        'sözcük $hedef türünde bir fiilimsidir?',
        _maske(tur, hedef),
        aciklama,
        i,
      );
    }
    if (bicim == 2) {
      final ek = [for (final e in x) e.$4];
      return _sirali(
        '$liste\nNumaralanmış cümlelerde tırnak içinde verilen fiilimsilerin '
        'ekleri sırasıyla hangi seçenekte doğru verilmiştir? (Ekler, ünlü '
        'uyumuyla aldıkları biçimlerden bağımsız olarak temel biçimleriyle '
        'yazılmıştır.)',
        ek,
        [for (var p = 0; p < 3; p++) _ekYanlislari(ek[p], i + 5 * p)],
        aciklama,
        i,
        dengeli: true,
      );
    }
    return _sirali(
      '$liste\nNumaralanmış cümlelerde tırnak içinde verilen fiilimsilerin '
      'türleri sırasıyla hangi seçenekte doğru verilmiştir?',
      tur,
      [for (final t in tur) _turYanlislari(t)],
      aciklama,
      i,
      dengeli: true,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ──────────────────────────────── 6 · Fiilde çatı ─────────────────────────────

const _etken = 'etken';
const _edilgen = 'edilgen';
const _donuslu = 'dönüşlü';
const _istes = 'işteş';
const _ozneCatilari = [_etken, _edilgen, _donuslu, _istes];
const _gecisli = 'geçişli';
const _gecissiz = 'geçişsiz';

const _ozneGerekce = {
  _etken: 'eylemi özne kendisi yapar',
  _edilgen: 'özne eylemi yapan değil, eylemden etkilenendir (sözde özne)',
  _donuslu: 'özne eylemi kendi üzerine yapar',
  _istes: 'eylem birlikte ya da karşılıklı yapılır',
};

// Kimi kaynaklar dönüşlü ve işteş fiilleri de etken sayar (öznesi eylemi
// yapandır). Bu yüzden bu iki çatının konumuna “etken” çeldirici yazılmaz ve
// bunlardan biri bulunan soruda “hangileri etken çatılıdır?” sorulmaz.
bool _etkenTartismali(String cati) => cati == _donuslu || cati == _istes;

// (cümle, tırnak içindeki yüklem, öznesine göre çatı, nesnesine göre çatı).
// Edilgen, dönüşlü ve işteş fiiller nesne almadığı için geçişsizdir. Ünlüyle
// biten gövdelerde edilgenlik ve dönüşlülük eki aynıdır (-n: yıkandı,
// tarandı); bu dönüşlü cümlelerde öznenin eylemi kendisinin yaptığı bağlamdan
// açıkça anlaşılır (havlusunu alıp, kimseden yardım almadan).
const _catilar = [
  ('Annem bize sıcak bir çorba “pişirdi”.', 'pişirdi', _etken, _gecisli),
  ('Kardeşim odasının duvarına bir resim “astı”.', 'astı', _etken, _gecisli),
  ('Babam bahçeye iki fidan “dikti”.', 'dikti', _etken, _gecisli),
  (
    'Öğretmen sınav kâğıtlarını öğrencilere “dağıttı”.',
    'dağıttı',
    _etken,
    _gecisli,
  ),
  ('Dedem her sabah gazetesini “okur”.', 'okur', _etken, _gecisli),
  ('Elif arkadaşına uzun bir mektup “yazdı”.', 'yazdı', _etken, _gecisli),
  ('Çiftçi tarlasını sabah erkenden “sürdü”.', 'sürdü', _etken, _gecisli),
  ('Komşumuz bize taze ekmek “getirdi”.', 'getirdi', _etken, _gecisli),
  ('Usta, eski saati özenle “onardı”.', 'onardı', _etken, _gecisli),
  ('Çocuklar kumsalda kumdan bir kale “yaptı”.', 'yaptı', _etken, _gecisli),
  ('Ressam köyün manzarasını tuvaline “çizdi”.', 'çizdi', _etken, _gecisli),
  ('Teyzem bize ilginç bir hikâye “anlattı”.', 'anlattı', _etken, _gecisli),
  ('Bekçi, bahçe kapısını her akşam “kilitler”.', 'kilitler', _etken, _gecisli),
  (
    'Öğrenciler müzedeki tabloları ilgiyle “inceledi”.',
    'inceledi',
    _etken,
    _gecisli,
  ),
  (
    'Ablam akşam yemeğinden sonra bulaşıkları “yıkadı”.',
    'yıkadı',
    _etken,
    _gecisli,
  ),
  ('Çocuklar bahçede saatlerce “koştu”.', 'koştu', _etken, _gecissiz),
  ('Bebek beşiğinde mışıl mışıl “uyuyor”.', 'uyuyor', _etken, _gecissiz),
  ('Misafirlerimiz akşamüstü “geldi”.', 'geldi', _etken, _gecissiz),
  ('Kuşlar sonbaharda güneye doğru “uçtu”.', 'uçtu', _etken, _gecissiz),
  (
    'Yaşlı adam parktaki bankta bir süre “oturdu”.',
    'oturdu',
    _etken,
    _gecissiz,
  ),
  ('Kardeşim filmin sonunda çok “güldü”.', 'güldü', _etken, _gecissiz),
  ('Tren istasyona tam vaktinde “ulaştı”.', 'ulaştı', _etken, _gecissiz),
  ('Bebek gece boyunca “ağladı”.', 'ağladı', _etken, _gecissiz),
  ('Koşucu, ayağı kayınca pistte “düştü”.', 'düştü', _etken, _gecissiz),
  ('Babam her sabah erkenden “kalkar”.', 'kalkar', _etken, _gecissiz),
  (
    'Yollar dün gece belediye ekiplerince “temizlendi”.',
    'temizlendi',
    _edilgen,
    _gecissiz,
  ),
  ('Mektuplar sabah erkenden “dağıtıldı”.', 'dağıtıldı', _edilgen, _gecissiz),
  ('Bu köprü geçen yıl “yapıldı”.', 'yapıldı', _edilgen, _gecissiz),
  ('Sınav sonuçları dün akşam “açıklandı”.', 'açıklandı', _edilgen, _gecissiz),
  ('Olgunlaşan elmalar bahçeden “toplandı”.', 'toplandı', _edilgen, _gecissiz),
  ('Kitaplar raflara özenle “dizildi”.', 'dizildi', _edilgen, _gecissiz),
  ('Ödüller törenle sahiplerine “verildi”.', 'verildi', _edilgen, _gecissiz),
  (
    'Akşam yemeğinden sonra bulaşıklar “yıkandı”.',
    'yıkandı',
    _edilgen,
    _gecissiz,
  ),
  (
    'Kayıp çocuk iki saat sonra ormanda “bulundu”.',
    'bulundu',
    _edilgen,
    _gecissiz,
  ),
  ('Toplantı salonu çiçeklerle “süslendi”.', 'süslendi', _edilgen, _gecissiz),
  ('Kardeşim sabah erkenden “giyindi”.', 'giyindi', _donuslu, _gecissiz),
  (
    'Gelin, kimseden yardım almadan aynanın karşısında uzun uzun “süslendi”.',
    'süslendi',
    _donuslu,
    _gecissiz,
  ),
  (
    'Küçük kız tarağını alıp aynanın önünde “tarandı”.',
    'tarandı',
    _donuslu,
    _gecissiz,
  ),
  ('Çocuk maçtan sonra duşa girip “yıkandı”.', 'yıkandı', _donuslu, _gecissiz),
  (
    'Kardeşim yeni bisikletiyle arkadaşlarına “övündü”.',
    'övündü',
    _donuslu,
    _gecissiz,
  ),
  ('Üşüyen çocuk battaniyeye “sarındı”.', 'sarındı', _donuslu, _gecissiz),
  (
    'Saklambaç oynarken çocuk dolabın arkasına “saklandı”.',
    'saklandı',
    _donuslu,
    _gecissiz,
  ),
  ('Kedi korkup yatağın altına “gizlendi”.', 'gizlendi', _donuslu, _gecissiz),
  (
    'Banyodan çıkan çocuk havlusunu alıp “kurulandı”.',
    'kurulandı',
    _donuslu,
    _gecissiz,
  ),
  ('Köpek sudan çıkınca “silkindi”.', 'silkindi', _donuslu, _gecissiz),
  (
    'İki arkadaş yıllar sonra havaalanında “kucaklaştı”.',
    'kucaklaştı',
    _istes,
    _gecissiz,
  ),
  (
    'Öğrenciler sabah okul kapısında “selamlaştı”.',
    'selamlaştı',
    _istes,
    _gecissiz,
  ),
  (
    'Sınıftakiler bu komik duruma hep birlikte “gülüştü”.',
    'gülüştü',
    _istes,
    _gecissiz,
  ),
  (
    'Serçeler sabah erkenden ağaçlarda “cıvıldaştı”.',
    'cıvıldaştı',
    _istes,
    _gecissiz,
  ),
  (
    'Yolcular perondaki akrabalarıyla “vedalaştı”.',
    'vedalaştı',
    _istes,
    _gecissiz,
  ),
  (
    'İki eski arkadaş yıllarca “mektuplaştı”.',
    'mektuplaştı',
    _istes,
    _gecissiz,
  ),
  ('İki kardeş şaşkınlıkla “bakıştı”.', 'bakıştı', _istes, _gecissiz),
  ('Çocuklar bahçede oraya buraya “koşuştu”.', 'koşuştu', _istes, _gecissiz),
  (
    'Proje boyunca iki öğretmen e-postayla “yazıştı”.',
    'yazıştı',
    _istes,
    _gecissiz,
  ),
  (
    'Maç bitince iki takımın oyuncuları “tokalaştı”.',
    'tokalaştı',
    _istes,
    _gecissiz,
  ),
];

final _catiSerpik = _serpistir(_catilar, 5);

List<String> _ozneYanlislari(String cati, int kay) => _digerleri(
  [
    for (final c in _ozneCatilari)
      if (!(c == _etken && _etkenTartismali(cati))) c,
  ],
  cati,
  kay,
);

// Öznesine göre çatı biçiminin (i % 3 == 0) seçkileri ([_sirali] dengeli
// kipi). Dört çatı bulunduğundan üç yüklemi ayrı çatılı üçlüye temiz
// çeldirici kurulamaz; tam iki yüklemi aynı çatılı üçlüler alınır.
final _catiSecki = <List<int>?>[
  _uygunSecki(
    _catiSerpik,
    _bicimBoyu(3),
    (x) => _dengeliKurulur(
      [for (final e in x) e.$3],
      [for (final e in x) _ozneYanlislari(e.$3, 0)],
      ayri: false,
      ikili: true,
    ),
  ),
  null,
  null,
];

final _gecisliCatilar = [
  for (final e in _catiSerpik)
    if (e.$4 == _gecisli) e,
];
final _gecissizCatilar = [
  for (final e in _catiSerpik)
    if (e.$4 == _gecissiz) e,
];

/// Nesnesine göre çatı biçiminin (i % 3 == 1) üçlüsü. İki etiketli bu
/// biçimde her çeldirici doğru dizinin iki konumunu değiştirdiği için dört
/// seçenekten biri her zaman tekdüzedir (ör. geçişsiz – geçişsiz –
/// geçişsiz). Doğru dizinin sekiz geçişlilik deseni eşit sıklıkta seçilir;
/// böylece tekdüze seçenek vakaların tam dörtte birinde doğru yanıt olur ve
/// seçeneklerin yapısı yanıtı ele vermez. Aynı desenli vakalar ayrı yüklem
/// üçlüleri alır.
List<(String, String, String, String)> _nesneUclusu(int i) {
  final j = i ~/ 3;
  final desen = j % 8, r = j ~/ 8;
  final g = (desen & 1) + (desen >> 1 & 1) + (desen >> 2 & 1);
  final adet = (_bicimBoyu(3) - desen + 7) ~/ 8;
  final zSayisi = kombinasyonSayisi(_gecissizCatilar.length, 3 - g);
  final toplam = kombinasyonSayisi(_gecisliCatilar.length, g) * zSayisi;
  final s = r * toplam ~/ adet;
  final gs = kombinasyon(_gecisliCatilar, g, s ~/ zSayisi, spread: false);
  final zs = kombinasyon(_gecissizCatilar, 3 - g, s % zSayisi, spread: false);
  var a = 0, b = 0;
  return [
    for (var p = 0; p < 3; p++)
      desen >> p & 1 == 1 ? gs[(a++ + r) % g] : zs[(b++ + r) % (3 - g)],
  ];
}

final _cati = lmSirali(
  'tk_cati',
  'Fiilde çatı: öznesine ve nesnesine göre çatı',
  Topic.literature,
  Difficulty.hard,
  BloomLevel.analiz,
  (i) {
    final bicim = i % 3;
    final x = bicim == 1
        ? _nesneUclusu(i)
        : _bicimSecki(_catiSerpik, i, 3, _catiSecki);
    final liste = _uc([for (final e in x) e.$1]);
    final ozne = [for (final e in x) e.$3];
    final aciklama =
        '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. “${x[p].$2}”: ${x[p].$3} (${_ozneGerekce[x[p].$3]}), ${x[p].$4 == _gecisli ? 'geçişli (nesne alır)' : 'geçişsiz (nesne almaz)'}'].join('; ')}.';
    if (bicim == 2) {
      var hedef = ozne[i ~/ 3 % 3];
      if (hedef == _etken && ozne.any(_etkenTartismali)) {
        for (var s = 1; s < 3; s++) {
          final aday = ozne[(i ~/ 3 + s) % 3];
          if (aday != _etken) {
            hedef = aday;
            break;
          }
        }
      }
      return _hangileri(
        '$liste\nNumaralanmış cümlelerin hangilerinde tırnak içinde verilen '
        'yüklem $hedef çatılıdır?',
        _maske(ozne, hedef),
        aciklama,
        i,
      );
    }
    if (bicim == 1) {
      final nesne = [for (final e in x) e.$4];
      return _sirali(
        '$liste\nNumaralanmış cümlelerde tırnak içinde verilen yüklemlerin '
        'nesnesine göre çatıları sırasıyla hangi seçenekte doğru verilmiştir?',
        nesne,
        [
          for (final n in nesne) [n == _gecisli ? _gecissiz : _gecisli],
        ],
        aciklama,
        i,
      );
    }
    return _sirali(
      '$liste\nNumaralanmış cümlelerde tırnak içinde verilen yüklemlerin '
      'öznesine göre çatıları sırasıyla hangi seçenekte doğru verilmiştir?',
      ozne,
      [for (var p = 0; p < 3; p++) _ozneYanlislari(ozne[p], i + p)],
      aciklama,
      i,
      dengeli: true,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ───────────────────────── 7 · İsim ve sıfat tamlamaları ──────────────────────

const _belirtili = 'belirtili isim tamlaması';
const _belirtisiz = 'belirtisiz isim tamlaması';
const _takisiz = 'takısız isim tamlaması';
const _zincirleme = 'zincirleme isim tamlaması';
const _sifatTamlamasi = 'sıfat tamlaması';
const _tamlamaTurleri = [
  _belirtili,
  _belirtisiz,
  _takisiz,
  _zincirleme,
  _sifatTamlamasi,
];

const _tamlamaGerekce = {
  _belirtili: 'tamlayan ilgi eki (-ın), tamlanan iyelik eki (-ı) almıştır',
  _belirtisiz: 'tamlayan ek almamış, tamlanan iyelik eki (-ı) almıştır',
  _takisiz: 'iki ad da ek almamıştır; tamlayan, tamlananın neden yapıldığını bildirir',
  _zincirleme: 'tamlayan ya da tamlanan kendi içinde bir isim tamlamasıdır',
  _sifatTamlamasi: 'sıfat, bir adı niteler ya da belirtir',
};

// Kimi dil bilgisi kitapları “demir kapı” türünü sıfat tamlaması sayar; bu
// nedenle takısız tamlamaların konumuna sıfat tamlaması çeldirici yazılmaz ve
// bir takısız tamlama bulunan soruda “sıfat tamlaması hangileridir?” sorulmaz.
// Zincirleme tamlamalar da içlerinde belirtili ve belirtisiz tamlama taşır
// (“dedemin el yazısı”); bu iki tür onların konumuna çeldirici yazılmaz ve
// zincirleme tamlama bulunan soruda bu iki tür sorulmaz.
const _tamlamaDisi = {
  _takisiz: [_sifatTamlamasi],
  _zincirleme: [_belirtili, _belirtisiz],
};

// (tamlama, türü)
const _tamlamalar = [
  ('evin kapısı', _belirtili),
  ('kitabın kapağı', _belirtili),
  ('ağacın dalları', _belirtili),
  ('okulun bahçesi', _belirtili),
  ('denizin rengi', _belirtili),
  ('çocuğun oyuncağı', _belirtili),
  ('şehrin sokakları', _belirtili),
  ('kuşun kanadı', _belirtili),
  ('dağın zirvesi', _belirtili),
  ('masanın ayağı', _belirtili),
  ('yolun sonu', _belirtili),
  ('gölün kıyısı', _belirtili),
  ('okul bahçesi', _belirtisiz),
  ('kapı kolu', _belirtisiz),
  ('çay bardağı', _belirtisiz),
  ('masa örtüsü', _belirtisiz),
  ('diş fırçası', _belirtisiz),
  ('ayakkabı kutusu', _belirtisiz),
  ('çocuk parkı', _belirtisiz),
  ('domates çorbası', _belirtisiz),
  ('deniz kıyısı', _belirtisiz),
  ('yaz tatili', _belirtisiz),
  ('el çantası', _belirtisiz),
  ('kış mevsimi', _belirtisiz),
  ('demir kapı', _takisiz),
  ('altın yüzük', _takisiz),
  ('taş duvar', _takisiz),
  ('tahta masa', _takisiz),
  ('gümüş kolye', _takisiz),
  ('yün çorap', _takisiz),
  ('ipek mendil', _takisiz),
  ('cam bardak', _takisiz),
  ('deri çanta', _takisiz),
  ('bakır tencere', _takisiz),
  ('okul bahçesinin duvarı', _zincirleme),
  ('evimizin mutfak penceresi', _zincirleme),
  ('dedemin el yazısı', _zincirleme),
  ('çocuğun diş fırçası', _zincirleme),
  ('köyün çeşme suyu', _zincirleme),
  ('masa örtüsünün rengi', _zincirleme),
  ('çay bardağının kulpu', _zincirleme),
  ('kapı kolunun rengi', _zincirleme),
  ('şehrin otobüs durakları', _zincirleme),
  ('sınıfın kitap dolabı', _zincirleme),
  ('kırmızı elma', _sifatTamlamasi),
  ('büyük ev', _sifatTamlamasi),
  ('üç kitap', _sifatTamlamasi),
  ('bu çocuk', _sifatTamlamasi),
  ('uzun yol', _sifatTamlamasi),
  ('yaşlı adam', _sifatTamlamasi),
  ('temiz hava', _sifatTamlamasi),
  ('beyaz bulut', _sifatTamlamasi),
  ('küçük kedi', _sifatTamlamasi),
  ('birkaç öğrenci', _sifatTamlamasi),
  ('sıcak çorba', _sifatTamlamasi),
  ('şu kalem', _sifatTamlamasi),
];

const _tamlamaKarisan = {
  _belirtili: [_zincirleme, _belirtisiz],
  _belirtisiz: [_belirtili, _takisiz],
  _takisiz: [_belirtisiz, _belirtili],
  _zincirleme: [_takisiz, _sifatTamlamasi],
  _sifatTamlamasi: [_takisiz, _belirtisiz],
};

final _tamlamaSerpik = _serpistir(_tamlamalar, 5);

List<String> _tamlamaYanlislari(String tur, int kay) {
  final disi = _tamlamaDisi[tur] ?? const <String>[];
  return _digerleri(
    [
      for (final t in _tamlamaTurleri)
        if (!disi.contains(t)) t,
    ],
    tur,
    kay,
    [
      for (final t in _tamlamaKarisan[tur]!)
        if (!disi.contains(t)) t,
    ],
  );
}

// Sıralı biçimin (çift sıra numaraları) seçkileri ([_sirali] dengeli kipi).
// Beş tür bulunduğundan üç tamlaması ayrı türden üçlüye temiz çeldirici
// kurulamaz; tam iki tamlaması aynı türden üçlüler alınır.
final _tamlamaSecki = _uygunSecki(
  _tamlamaSerpik,
  _bicimBoyu(2),
  (x) => _dengeliKurulur(
    [for (final e in x) e.$2],
    [for (final e in x) _tamlamaYanlislari(e.$2, 0)],
    ayri: false,
    ikili: true,
  ),
);

final _tamlama = lmSirali(
  'tk_tamlama',
  'İsim tamlamaları ve sıfat tamlamaları',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.analiz,
  (i) {
    final x = _bicimSecki(_tamlamaSerpik, i, 2, [_tamlamaSecki, null]);
    final tur = [for (final e in x) e.$2];
    final liste = _uc([for (final e in x) e.$1]);
    final aciklama =
        '${[for (final e in x) '“${e.$1}”: ${e.$2} (${_tamlamaGerekce[e.$2]})'].join('; ')}.';
    if (i.isOdd) {
      var hedef = tur[i ~/ 2 % 3];
      if (hedef == _sifatTamlamasi && tur.contains(_takisiz)) hedef = _takisiz;
      if ((hedef == _belirtili || hedef == _belirtisiz) &&
          tur.contains(_zincirleme)) {
        hedef = _zincirleme;
      }
      return _hangileri(
        '$liste\nNumaralanmış tamlamalardan hangileri $hedef örneğidir?',
        _maske(tur, hedef),
        aciklama,
        i,
      );
    }
    return _sirali(
      '$liste\nNumaralanmış tamlamaların türleri sırasıyla hangi seçenekte '
      'doğru verilmiştir?',
      tur,
      [for (var p = 0; p < 3; p++) _tamlamaYanlislari(tur[p], i + p)],
      aciklama,
      i,
      dengeli: true,
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ──────────────────────────────── 8 · Kök ve ek ──────────────────────────────

// (sözcük, artı ile ayrılmış parçaları, parça türleri: k ad kökü, f fiil
//  kökü, y yapım eki, ç çekim eki). Çözümlemesi tartışmalı sözcükler (okul,
//  arkadaş, yazar; kaynağa göre sev-in-ç ya da sev-inç diye ayrılan sevinç),
//  fiilimsi ekleri ile “-ki” ve “-ca” ekleri alınmamıştır.
const _kokEkler = [
  ('gözlükçüler', 'göz+lük+çü+ler', 'kyyç'),
  ('yazıcılar', 'yaz+ı+cı+lar', 'fyyç'),
  ('sevgisizlik', 'sev+gi+siz+lik', 'fyyy'),
  ('denizcilerimiz', 'deniz+ci+ler+imiz', 'kyçç'),
  ('evlerimizden', 'ev+ler+imiz+den', 'kççç'),
  ('balıkçılık', 'balık+çı+lık', 'kyy'),
  ('güzelleşti', 'güzel+leş+ti', 'kyç'),
  ('yolculuklarımız', 'yol+cu+luk+lar+ımız', 'kyyçç'),
  ('başkanlığı', 'baş+kan+lığ+ı', 'kyyç'),
  ('taşçılara', 'taş+çı+lar+a', 'kyçç'),
  ('kuşlarımız', 'kuş+lar+ımız', 'kçç'),
  ('sütçülerden', 'süt+çü+ler+den', 'kyçç'),
  ('simitçilerden', 'simit+çi+ler+den', 'kyçç'),
  ('kalemlikte', 'kalem+lik+te', 'kyç'),
  ('dostluğumuz', 'dost+luğ+umuz', 'kyç'),
  ('sağlıklı', 'sağ+lık+lı', 'kyy'),
  ('kitapçılarımız', 'kitap+çı+lar+ımız', 'kyçç'),
  ('gözlüksüz', 'göz+lük+süz', 'kyy'),
  ('temizlikçiler', 'temiz+lik+çi+ler', 'kyyç'),
  ('evcilleşti', 'ev+cil+leş+ti', 'kyyç'),
  ('işçilerimiz', 'iş+çi+ler+imiz', 'kyçç'),
  ('susuzluktan', 'su+suz+luk+tan', 'kyyç'),
  ('tuzluklarımız', 'tuz+luk+lar+ımız', 'kyçç'),
  ('çiçekçiye', 'çiçek+çi+ye', 'kyç'),
  ('yoldaşlığımız', 'yol+daş+lığ+ımız', 'kyyç'),
  ('kalemler', 'kalem+ler', 'kç'),
  ('kitaplarımızı', 'kitap+lar+ımız+ı', 'kççç'),
  ('şekerlik', 'şeker+lik', 'ky'),
  ('yazılarımızı', 'yaz+ı+lar+ımız+ı', 'fyççç'),
  ('sevgililer', 'sev+gi+li+ler', 'fyyç'),
  ('gözcü', 'göz+cü', 'ky'),
  ('kulaklık', 'kulak+lık', 'ky'),
  ('sınıflarımız', 'sınıf+lar+ımız', 'kçç'),
  ('çocukluğumda', 'çocuk+luğ+um+da', 'kyçç'),
  ('bilgilerimizden', 'bil+gi+ler+imiz+den', 'fyççç'),
  ('silgilerde', 'sil+gi+ler+de', 'fyçç'),
  ('seçimlerde', 'seç+im+ler+de', 'fyçç'),
  ('korkaklar', 'kork+ak+lar', 'fyç'),
  ('durgunluk', 'dur+gun+luk', 'fyy'),
  ('kırgınlık', 'kır+gın+lık', 'fyy'),
  ('yorgunluğu', 'yor+gun+luğ+u', 'fyyç'),
  ('uçaklarımız', 'uç+ak+lar+ımız', 'fyçç'),
  ('yapımcılar', 'yap+ım+cı+lar', 'fyyç'),
  ('bilgisiz', 'bil+gi+siz', 'fyy'),
  ('kuşçular', 'kuş+çu+lar', 'kyç'),
  ('ağaçlık', 'ağaç+lık', 'ky'),
  ('evlerde', 'ev+ler+de', 'kçç'),
  ('dağcılarımız', 'dağ+cı+lar+ımız', 'kyçç'),
  ('tuzsuz', 'tuz+suz', 'ky'),
  ('renkli', 'renk+li', 'ky'),
  ('çalgıcılar', 'çal+gı+cı+lar', 'fyyç'),
];

int _ekSayisi(String turler, String t) =>
    turler.split('').where((c) => c == t).length;

/// Kök sorusunda tipik yanlışlar: kökü ekleriyle birlikte almak (gövdeyi ya
/// da çekimli bir biçimi kök sanmak).
List<String> _kokYanlislari(String parcalar) {
  final p = parcalar.split('+');
  final out = <String>[];
  var s = p[0];
  for (var k = 1; k < p.length; k++) {
    s += p[k];
    // Yumuşamış gövde sözlük biçimiyle yazılır: dostluğ- → dostluk.
    out.add(s.endsWith('ğ') ? '${s.substring(0, s.length - 1)}k' : s);
  }
  // Sözcüğün kendisi, başka aday yoksa çeldiricidir.
  return out.length > 1 ? out.sublist(0, out.length - 1) : out;
}

String _cozumle(String parcalar, String turler) {
  final p = parcalar.split('+');
  const ad = {'k': 'kök', 'f': 'fiil kökü', 'y': 'yapım eki', 'ç': 'çekim eki'};
  return [
    for (var k = 0; k < p.length; k++)
      '${p[k]}${turler[k] == 'f' ? '-' : ''} (${ad[turler[k]]})',
  ].join(' + ');
}

final _kokEkSerpik = _serpistir(_kokEkler, 4);

String _kokEtiketi((String, String, String) e) =>
    '${e.$2.split('+').first}${e.$3.startsWith('f') ? '-' : ''}';

/// Ek sayısı sorusunda [hedef] türünden eklerin sayısı için tipik yanlışlar:
/// bütün ekleri saymak, öteki ek türünü saymak, bir eksik, bir ya da iki
/// fazla saymak.
List<String> _sayiYanlislari((String, String, String) e, String hedef) {
  final d = _ekSayisi(e.$3, hedef);
  return [
    for (final n in {
      e.$3.length - 1,
      _ekSayisi(e.$3, hedef == 'y' ? 'ç' : 'y'),
      d + 1,
      d - 1,
      d + 2,
    })
      if (n >= 0 && n != d) '$n',
  ];
}

// Biçimlerin seçkileri ([_sirali] dengeli kipi): kök biçiminde üç kök
// ayrıdır. Ek sayısı biçimlerinde sayıların üçü de ayrı olursa çeldiricilere
// yalnız daha büyük sayılar kalır ve en küçük toplamlı seçenek yanıtı ele
// verir; bu biçimlerde tam iki sözcüğün ek sayısı aynıdır.
final _kokEkSecki = <List<int>?>[
  _uygunSecki(
    _kokEkSerpik,
    _bicimBoyu(3),
    (x) => _dengeliKurulur(
      [for (final e in x) _kokEtiketi(e)],
      [for (final e in x) _kokYanlislari(e.$2)],
    ),
  ),
  for (final hedef in const ['y', 'ç'])
    _uygunSecki(
      _kokEkSerpik,
      _bicimBoyu(3),
      (x) => _dengeliKurulur(
        [for (final e in x) '${_ekSayisi(e.$3, hedef)}'],
        [for (final e in x) _sayiYanlislari(e, hedef)],
        ayri: false,
        ikili: true,
      ),
    ),
];

// Ek sayısı biçimlerinin (yapım: i % 3 == 1, çekim: i % 3 == 2) çeldirici
// dizileri ([_toplamDengesi]).
final _ekSayisiSecimi = {
  for (final (b, hedef) in const [(1, 'y'), (2, 'ç')])
    b: _toplamDengesi(_bicimBoyu(3), (j) {
      final x = _yayili(_kokEkSerpik, j, _bicimBoyu(3), _kokEkSecki[b]);
      return (
        [for (final e in x) '${_ekSayisi(e.$3, hedef)}'],
        [for (final e in x) _sayiYanlislari(e, hedef)],
      );
    }),
};

final _kokEk = lmSirali(
  'tk_kok_ek',
  'Kök ve ek: kök, yapım eki ve çekim eki sayısı',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.analiz,
  (i) {
    final bicim = i % 3;
    final x = _bicimSecki(_kokEkSerpik, i, 3, _kokEkSecki);
    final liste = _uc([for (final e in x) e.$1]);
    final aciklama =
        '${[for (final e in x) '${e.$1}: ${_cozumle(e.$2, e.$3)}; ${_ekSayisi(e.$3, 'y')} yapım, ${_ekSayisi(e.$3, 'ç')} çekim eki'].join('. ')}.';
    if (bicim == 0) {
      return _sirali(
        '$liste\nNumaralanmış sözcüklerin kökleri sırasıyla hangi seçenekte '
        'doğru verilmiştir?',
        [for (final e in x) _kokEtiketi(e)],
        // Başka sözcüklerin kökleriyle kurulan dizilimler kolayca elendiği
        // için çeldiriciler yalnız kökü ekleriyle birlikte alma hatasıdır.
        [for (final e in x) _kokYanlislari(e.$2)],
        aciklama,
        i,
        dengeli: true,
      );
    }
    final hedef = bicim == 1 ? 'y' : 'ç';
    return _sirali(
      '$liste\nNumaralanmış sözcüklerdeki '
      '${bicim == 1 ? 'yapım' : 'çekim'} eki sayıları sırasıyla hangi '
      'seçenekte doğru verilmiştir?',
      [for (final e in x) '${_ekSayisi(e.$3, hedef)}'],
      [for (final e in x) _sayiYanlislari(e, hedef)],
      aciklama,
      i,
      dengeli: true,
      secim: _ekSayisiSecimi[bicim]![_bicimSirasi(i, 3)],
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ─────────────────────────────── 9 · Hece ölçüsü ─────────────────────────────

// (dize, durak kalıbı). Dizeler bu bölüm için yazılmıştır. Hece sayısı ünlü
// sayısıdır; ünlüleri yan yana gelen ya da hecesi tartışmalı sözcük yoktur.
// Her dizede sözcük sınırları yalnız kendi kalıbının duraklarına uyar; aynı
// hece sayısının öteki kalıpları (ör. 11 hecede 6+5 ile 4+4+3) o dizeye
// uymaz.
const _dizeler = [
  ('Dağlar yine yeşerdi', '4+3'),
  ('Gönlüm sana küskündür', '4+3'),
  ('Irmak boyu söğütler', '4+3'),
  ('Akşam olur karanlık', '4+3'),
  ('Bahar gelmiş köyüme', '4+3'),
  ('Yollar uzun gurbette', '4+3'),
  ('Yağmur yağar derede', '4+3'),
  ('Kuşlar uçar dallardan', '4+3'),
  ('Rüzgâr eser tepeden', '4+3'),
  ('Annem bekler kapıda', '4+3'),
  ('Çiçek açmış bahçemde', '4+3'),
  ('Karlar erir dağlarda', '4+3'),
  ('Dağlar başı dumanlıdır', '4+4'),
  ('Gurbet elde yalnız kaldım', '4+4'),
  ('Bir gün gelir sevdan biter', '4+4'),
  ('Yüce dağlar karla dolu', '4+4'),
  ('Yeşil ova sarı başak', '4+4'),
  ('Pınar başı serin olur', '4+4'),
  ('Kervan gider uzaklara', '4+4'),
  ('Gönül dağı yüksek olur', '4+4'),
  ('Sabah oldu horoz öttü', '4+4'),
  ('Kızılcıklar dalda kızar', '4+4'),
  ('Bulut olsam yağsam sana', '4+4'),
  ('Elma dalı çiçeklendi', '4+4'),
  ('Yine karanlıkta bekledim seni', '6+5'),
  ('Sabah pencereden güneş doğuyor', '6+5'),
  ('Yine yapraklarda sonbahar rengi', '6+5'),
  ('Gönül sevdiğine kavuşur bir gün', '6+5'),
  ('Uzak yollarından haber gelmedi', '6+5'),
  ('İnce yağmurlarla yıkandı şehir', '6+5'),
  ('Derin vadilerde akar bir ırmak', '6+5'),
  ('Köyün akşamları ne kadar sessiz', '6+5'),
  ('Annem bahçesinde gül yetiştirir', '6+5'),
  ('Dağlar arasında bir küçük köy var', '6+5'),
  ('Bahar sabahları kuşlar şakıyor', '6+5'),
  ('Deniz kıyısında dalgalar coştu', '6+5'),
  ('Yolcu menziline akşam ulaştı', '6+5'),
  ('Yaşlı çınarların gölgesi serin', '6+5'),
  ('Çoban sürüsüyle yaylaya çıktı', '6+5'),
  ('Gönül derdi yolculuğun sonunda', '4+4+3'),
  ('Bahar geldi çiçekleri açtırdı', '4+4+3'),
  ('Akşam oldu pencereden bakarım', '4+4+3'),
  ('Rüzgâr eser yaylalarda her sabah', '4+4+3'),
  ('Kuşlar uçar ormanlardan güneye', '4+4+3'),
  ('Yollar uzun sevdiğime varmadan', '4+4+3'),
  ('Annem bekler akşamları kapıda', '4+4+3'),
  ('Derin deniz dalgaları köpürür', '4+4+3'),
  ('Karlar erir ilkbaharda yeniden', '4+4+3'),
  ('Bir gün döner yolcularım sılaya', '4+4+3'),
  ('İnce ince yağmurlarla ıslandı', '4+4+3'),
  ('Yaşlı çoban sürüsünü otlatır', '4+4+3'),
  ('Gece oldu yıldızları sayarım', '4+4+3'),
  ('Yine bahçelerinde güller açtı yeniden', '7+7'),
  ('Köyün akşamlarında sessizlik çöker dağa', '7+7'),
  ('Uzak ormanlarından rüzgâr getirir sesi', '7+7'),
  ('Eski pencerelerden bakarım ben yollara', '7+7'),
  ('Çınar yapraklarından süzülür ay ışığı', '7+7'),
  ('Gönül sevdiklerinden ayrı düştü bu yıl da', '7+7'),
  ('Bütün yollarımızda bahar kokusu vardı', '7+7'),
  ('Dağın eteklerinde koyunlar otlar sessiz', '7+7'),
  ('Kuşlar yuvalarına döndü akşam olunca', '7+7'),
  ('Sılam çiçeklerini özledim bu bahar da', '7+7'),
  ('İnce yağmurlarıyla ıslandı bütün şehir', '7+7'),
  ('Yolcu dağlarımızın ardına baktı uzun', '7+7'),
];

const _heceKarisan = {
  '4+3': ['3+4', '5+2', '4+4'],
  '4+4': ['5+3', '3+5', '4+3'],
  '6+5': ['4+4+3', '5+6', '3+3+5'],
  '4+4+3': ['6+5', '4+3+4', '3+5+3'],
  '7+7': ['4+3+4+3', '6+5', '4+4+3'],
};

const _unluler = 'aeıioöuüâîûAEIİOÖUÜÂÎÛ';

int _heceSayisi(String s) =>
    s.split('').where((c) => _unluler.contains(c)).length;

/// Dizeyi durak yerlerine “/” koyarak yazar; durakların sözcük sınırına
/// düşmesi gerekir.
String _durakli(String dize, String kalip) {
  final duraklar = <int>{};
  var t = 0;
  for (final p in kalip.split('+')) {
    t += int.parse(p);
    duraklar.add(t);
  }
  final sozler = dize.split(' ');
  final out = <String>[];
  var h = 0;
  for (var k = 0; k < sozler.length; k++) {
    h += _heceSayisi(sozler[k]);
    out.add(sozler[k]);
    if (k < sozler.length - 1 && duraklar.contains(h)) out.add('/');
  }
  if (h != t) throw StateError('Kalıp ile hece sayısı uyuşmuyor: $dize');
  return out.join(' ');
}

final _heceSerpik = _serpistir(_dizeler, 5);

/// Hece sayısı sorusunda tipik yanlışlar: bir fazla, bir eksik, iki fazla,
/// iki eksik saymak.
List<String> _heceSayiYanlislari(int n) => [
  '${n + 1}',
  '${n - 1}',
  '${n + 2}',
  '${n - 2}',
];

// Biçimlerin seçkileri ([_sirali] dengeli kipi): hece sayısı (çift sıra
// numaraları) ve durak kalıbı (tek sıra numaraları). Üç dizenin hece sayıları
// da kalıpları da birbirinden ayrıdır; her konuma yanıtlardan ve birbirinden
// ayrı birer çeldirici bulunur.
final _heceSecki = <List<int>?>[
  _uygunSecki(
    _heceSerpik,
    _bicimBoyu(2),
    (x) => _dengeliKurulur(
      [for (final e in x) '${_heceSayisi(e.$1)}'],
      [for (final e in x) _heceSayiYanlislari(_heceSayisi(e.$1))],
    ),
  ),
  _uygunSecki(
    _heceSerpik,
    _bicimBoyu(2),
    (x) => _dengeliKurulur(
      [for (final e in x) e.$2],
      [for (final e in x) _heceKarisan[e.$2]!],
    ),
  ),
];

// Hece sayısı biçiminin çeldirici dizileri ([_toplamDengesi]).
final _heceSayiSecimi = _toplamDengesi(_bicimBoyu(2), (j) {
  final x = _yayili(_heceSerpik, j, _bicimBoyu(2), _heceSecki[0]);
  return (
    [for (final e in x) '${_heceSayisi(e.$1)}'],
    [for (final e in x) _heceSayiYanlislari(_heceSayisi(e.$1))],
  );
});

final _heceOlcu = lmSirali(
  'tk_hece_olcu',
  'Hece ölçüsü: dizelerin hece sayısı ve durak kalıbı',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final x = _bicimSecki(_heceSerpik, i, 2, _heceSecki);
    final liste = _uc([for (final e in x) e.$1]);
    final sayi = [for (final e in x) _heceSayisi(e.$1)];
    final aciklama =
        '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. dize ${sayi[p]} hecelidir ve ${x[p].$2} duraklıdır: ${_durakli(x[p].$1, x[p].$2)}'].join('; ')}.';
    if (i.isOdd) {
      return _sirali(
        '$liste\nNumaralanmış dizelerde kullanılan hece ölçüsü kalıpları, '
        'durakların yerine göre sırasıyla hangi seçenekte doğru verilmiştir?',
        [for (final e in x) e.$2],
        [for (final e in x) _heceKarisan[e.$2]!],
        aciklama,
        i,
        dengeli: true,
      );
    }
    return _sirali(
      '$liste\nNumaralanmış dizelerin hece sayıları sırasıyla hangi seçenekte '
      'doğru verilmiştir?',
      [for (final n in sayi) '$n'],
      [for (final n in sayi) _heceSayiYanlislari(n)],
      aciklama,
      i,
      dengeli: true,
      secim: _heceSayiSecimi[_bicimSirasi(i, 2)],
    );
  },
  exam: ExamKind.tyt,
  lesson: 'Türkçe',
);

// ─────────────── 10 · Nazım biçimleri ve Batı edebiyatı akımları ──────────────

const _kosma = 'koşma';
const _mani = 'mani';
const _semai = 'semai';
const _gazel = 'gazel';
const _kaside = 'kaside';
const _rubai = 'rubai';
const _tuyug = 'tuyuğ';
const _sarki = 'şarkı';
const _nazimHavuzu = [
  _kosma,
  _mani,
  _semai,
  _gazel,
  _kaside,
  _rubai,
  _tuyug,
  _sarki,
];

const _nazimOzet = {
  _kosma: 'halk şiiri, 11 heceli dörtlüklerle yazılır; güzelleme, koçaklama, taşlama ve ağıt türleri vardır',
  _mani: 'anonim halk şiiri, çoğunlukla 7 heceli tek dörtlükten oluşur, uyak düzeni aaxa',
  _semai: 'halk şiiri, 8 heceli dörtlüklerle yazılır ve kendine özgü ezgisiyle söylenir',
  _gazel: 'divan şiiri, aşk ve sevgilinin güzelliğini işleyen 5 ile 15 beyitlik biçim',
  _kaside: 'divan şiiri, büyükleri övmek için yazılan 33 ile 99 beyitlik biçim',
  _rubai: 'divan şiiri, aruzun 24 özel kalıbıyla yazılan, felsefi nitelikli dörtlük',
  _tuyug: 'divan şiirinde Türklere özgü dörtlük, “fâilâtün fâilâtün fâilün” kalıbıyla yazılır',
  _sarki: 'divan şiirinde bestelenmek için yazılan, nakaratlı ve Türklere özgü biçim',
};

const _nazimKarisan = {
  _kosma: [_semai, _gazel],
  _mani: [_tuyug, _rubai],
  _semai: [_kosma, _sarki],
  _gazel: [_kaside, _sarki],
  _kaside: [_gazel, _kosma],
  _rubai: [_tuyug, _mani],
  _tuyug: [_rubai, _mani],
  _sarki: [_gazel, _semai],
};

// (nazım biçimini tanıtan açıklama, nazım biçimi). Her açıklama listedeki
// sekiz biçimden yalnız birine uyar.
const _nazimlar = [
  (
    'Halk şiirinde 11 heceli ölçüyle ve dörtlüklerle yazılan; aşk, doğa ve ayrılık konularını işleyen nazım biçimi',
    _kosma,
  ),
  (
    'Güzelleme, koçaklama, taşlama ve ağıt türlerine ayrılan halk şiiri nazım biçimi',
    _kosma,
  ),
  (
    'Âşık edebiyatında en güzel örneklerini Karacaoğlan’ın verdiği, 11 heceli dörtlüklerle yazılan nazım biçimi',
    _kosma,
  ),
  (
    'Uyak düzeni abab, cccb, dddb biçiminde olan ve 11 heceli ölçüyle yazılan halk şiiri nazım biçimi',
    _kosma,
  ),
  (
    'Son dörtlüğünde âşığın mahlasını söylediği, 6+5 duraklı 11 heceli ölçüyle yazılan lirik halk şiiri',
    _kosma,
  ),
  (
    'Âşık edebiyatında en yaygın biçim olan, genellikle 3 ile 5 dörtlük arasında yazılan 11 heceli nazım biçimi',
    _kosma,
  ),
  (
    'Genellikle 7 heceli tek bir dörtlükten oluşan, aaxa uyaklı anonim halk şiiri nazım biçimi',
    _mani,
  ),
  (
    'Kesik, cinaslı ve yedekli türleri bulunan, tek dörtlükten oluşan anonim nazım biçimi',
    _mani,
  ),
  (
    'İlk iki dizesi çoğunlukla doldurma olan, asıl duygunun son iki dizede verildiği anonim nazım biçimi',
    _mani,
  ),
  (
    'Halk arasında düğün ve eğlencelerde söylenen, tek dörtlükten oluşan, 7 heceli anonim nazım biçimi',
    _mani,
  ),
  (
    'Halk şiirinde tek dörtlükten oluşan, çoğunlukla aaxa uyak düzeniyle kurulan ve söyleyeni bilinmeyen nazım biçimi',
    _mani,
  ),
  (
    'İlk dizesi 7 heceden az olan türüne “kesik” adı verilen, tek dörtlüklük anonim halk şiiri nazım biçimi',
    _mani,
  ),
  (
    'Halk şiirinde 8 heceli ölçüyle ve dörtlüklerle yazılan, kendine özgü bir ezgiyle söylenen nazım biçimi',
    _semai,
  ),
  (
    'Âşık edebiyatında 4+4 duraklı 8 heceli ölçüyle yazılan, adını söylendiği ezgiden alan nazım biçimi',
    _semai,
  ),
  (
    'Koşmayla aynı uyak düzenine sahip olup ondan 8 heceli ölçüsüyle ayrılan halk şiiri nazım biçimi',
    _semai,
  ),
  (
    'Divan şiirinde aşk, şarap ve sevgilinin güzelliğini işleyen, genellikle 5 ile 15 beyit arasında yazılan nazım biçimi',
    _gazel,
  ),
  (
    'Divan şiirinde beyitlerle ve aa, ba, ca uyak düzeniyle yazılan, aşkı ve sevgilinin güzelliğini işleyen nazım biçimi',
    _gazel,
  ),
  (
    'Fuzûlî ve Bâkî’nin en güzel örneklerini verdiği, aşk ve şarap konulu, beyitlerle yazılan divan şiiri nazım biçimi',
    _gazel,
  ),
  (
    'Divan şiirinde her beyti anlamca kendi içinde tamamlanan, aşk konulu, matla beytiyle başlayan kısa nazım biçimi',
    _gazel,
  ),
  (
    'Divan şiirinin en çok kullanılan nazım biçimi olan, aşk ve sevgili konulu beyitlerden oluşan biçim',
    _gazel,
  ),
  (
    'Divan şiirinde son beytine makta denen, aşkı işleyen ve genellikle 5 ile 15 beyitten oluşan nazım biçimi',
    _gazel,
  ),
  (
    'Divan şiirinde din ve devlet büyüklerini övmek amacıyla yazılan, 33 ile 99 beyit arasındaki nazım biçimi',
    _kaside,
  ),
  (
    'Nesib, girizgâh, methiye, fahriye ve dua bölümlerinden oluşan divan şiiri nazım biçimi',
    _kaside,
  ),
  (
    'Teşbib ya da nesib adı verilen giriş bölümüyle başlayan, övgü amaçlı uzun divan şiiri nazım biçimi',
    _kaside,
  ),
  (
    'Türk edebiyatında en büyük ustası Nef’î sayılan, övgü amaçlı uzun divan şiiri nazım biçimi',
    _kaside,
  ),
  (
    'Divan şiirinde övgü bölümüne methiye, şairin kendini övdüğü bölüme fahriye denen nazım biçimi',
    _kaside,
  ),
  (
    'Divan şiirinde aruzun 24 özel kalıbıyla yazılan, dört dizelik, aaxa uyaklı nazım biçimi',
    _rubai,
  ),
  (
    'İran edebiyatında Ömer Hayyam’ın ünlü örneklerini verdiği, dört dizelik, felsefi nitelikli nazım biçimi',
    _rubai,
  ),
  (
    'Hayat, ölüm ve varlığın anlamı gibi felsefi düşünceleri dört dizede işleyen, aruzun özel kalıplarıyla yazılan nazım biçimi',
    _rubai,
  ),
  (
    'Divan şiirinde aruzun ahreb ve ahrem kalıplarından türetilen kalıplarla yazılan dört dizelik nazım biçimi',
    _rubai,
  ),
  (
    'Türk edebiyatında Yahya Kemal’in de örneklerini verdiği, aruzla yazılan dört dizelik felsefi nazım biçimi',
    _rubai,
  ),
  (
    'Türklerin divan şiirine kazandırdığı, “fâilâtün fâilâtün fâilün” kalıbıyla yazılan dört dizelik nazım biçimi',
    _tuyug,
  ),
  (
    'Divan şiirinde Kadı Burhaneddin’in başarılı örneklerini verdiği, Türklere özgü dört dizelik nazım biçimi',
    _tuyug,
  ),
  (
    'Halk şiirindeki maninin divan şiirindeki karşılığı sayılan, cinaslı uyağa çok yer veren nazım biçimi',
    _tuyug,
  ),
  (
    'Aruzla yazılan ve yalnız Türk şairlerince kullanılan, aaba uyaklı dört dizelik nazım biçimi',
    _tuyug,
  ),
  (
    'Divan şiirinde bestelenmek amacıyla yazılan, nakarat dizesi bulunan, genellikle dörder dizelik bentlerden oluşan nazım biçimi',
    _sarki,
  ),
  (
    'Türklerin divan şiirine kazandırdığı, en güzel örneklerini Nedim’in verdiği, bestelenmek için yazılan nazım biçimi',
    _sarki,
  ),
  (
    'Nedim ve Enderunlu Vâsıf’ın sevilen örneklerini verdiği, nakaratlı divan şiiri nazım biçimi',
    _sarki,
  ),
  (
    'Divan şiirinde musikiyle birlikte gelişen, bentlerinde nakarat yinelenen nazım biçimi',
    _sarki,
  ),
  (
    'Divan şiirinde Lale Devri’nde Nedim’le en parlak dönemini yaşayan, bestelenmek için yazılan nazım biçimi',
    _sarki,
  ),
];

const _klasisizm = 'klasisizm';
const _romantizm = 'romantizm';
const _realizm = 'realizm';
const _naturalizm = 'natüralizm';
const _parnasizm = 'parnasizm';
const _sembolizm = 'sembolizm';
const _futurizm = 'fütürizm';
const _surrealizm = 'sürrealizm';
const _varolusculuk = 'egzistansiyalizm';
const _dadaizm = 'dadaizm';
const _akimHavuzu = [
  _klasisizm,
  _romantizm,
  _realizm,
  _naturalizm,
  _parnasizm,
  _sembolizm,
  _futurizm,
  _surrealizm,
  _varolusculuk,
  _dadaizm,
];

const _akimKarisan = {
  _klasisizm: [_romantizm, _realizm],
  _romantizm: [_klasisizm, _realizm],
  _realizm: [_naturalizm, _romantizm],
  _naturalizm: [_realizm, _parnasizm],
  _parnasizm: [_sembolizm, _romantizm],
  _sembolizm: [_parnasizm, _surrealizm],
  _futurizm: [_dadaizm, _surrealizm],
  _surrealizm: [_dadaizm, _sembolizm],
  _varolusculuk: [_surrealizm, _realizm],
  _dadaizm: [_surrealizm, _futurizm],
};

// (sanatçı, ders kitaplarında temsilcisi sayıldığı akım, kimi kaynaklarda
//  onunla da anıldığı için çeldirici yapılmayan akımlar)
const _temsilciler = [
  ('Racine', _klasisizm, <String>[]),
  ('Corneille', _klasisizm, <String>[]),
  ('Molière', _klasisizm, <String>[]),
  ('La Fontaine', _klasisizm, <String>[]),
  ('Boileau', _klasisizm, <String>[]),
  ('La Bruyère', _klasisizm, <String>[]),
  ('Victor Hugo', _romantizm, <String>[]),
  ('Lamartine', _romantizm, <String>[]),
  ('Alfred de Musset', _romantizm, <String>[]),
  ('Lord Byron', _romantizm, <String>[]),
  ('Walter Scott', _romantizm, <String>[]),
  ('Chateaubriand', _romantizm, <String>[]),
  ('Goethe', _romantizm, [_klasisizm]),
  ('Schiller', _romantizm, [_klasisizm]),
  ('Puşkin', _romantizm, [_realizm]),
  ('Balzac', _realizm, <String>[]),
  ('Flaubert', _realizm, [_naturalizm]),
  ('Stendhal', _realizm, [_romantizm]),
  ('Dostoyevski', _realizm, [_varolusculuk]),
  ('Tolstoy', _realizm, <String>[]),
  ('Turgenyev', _realizm, <String>[]),
  ('Charles Dickens', _realizm, [_romantizm]),
  ('Gogol', _realizm, [_romantizm]),
  ('Émile Zola', _naturalizm, <String>[]),
  ('Guy de Maupassant', _naturalizm, [_realizm]),
  ('Alphonse Daudet', _naturalizm, [_realizm]),
  ('Goncourt Kardeşler', _naturalizm, [_realizm]),
  ('Leconte de Lisle', _parnasizm, <String>[]),
  ('Théophile Gautier', _parnasizm, [_romantizm]),
  ('José Maria de Heredia', _parnasizm, <String>[]),
  ('Sully Prudhomme', _parnasizm, <String>[]),
  ('Théodore de Banville', _parnasizm, [_romantizm]),
  ('Charles Baudelaire', _sembolizm, [_parnasizm, _romantizm]),
  ('Paul Verlaine', _sembolizm, [_parnasizm]),
  ('Arthur Rimbaud', _sembolizm, <String>[]),
  ('Stéphane Mallarmé', _sembolizm, [_parnasizm]),
  ('Paul Valéry', _sembolizm, <String>[]),
  ('Marinetti', _futurizm, <String>[]),
  ('Mayakovski', _futurizm, <String>[]),
  ('André Breton', _surrealizm, [_dadaizm]),
  ('Paul Éluard', _surrealizm, [_dadaizm]),
  ('Louis Aragon', _surrealizm, [_dadaizm, _realizm]),
  ('Jean-Paul Sartre', _varolusculuk, <String>[]),
  ('Albert Camus', _varolusculuk, <String>[]),
  ('Simone de Beauvoir', _varolusculuk, <String>[]),
  ('Tristan Tzara', _dadaizm, [_surrealizm]),
];

final _nazimSerpik = _serpistir(_nazimlar, 8);
final _temsilciSerpik = _serpistir(_temsilciler, 10);

List<String> _nazimYanlislari(String nazim, int kay) =>
    _digerleri(_nazimHavuzu, nazim, kay, _nazimKarisan[nazim]!);

List<String> _akimYanlislari((String, String, List<String>) e, int kay) =>
    _digerleri(
      [
        for (final s in _akimHavuzu)
          if (!e.$3.contains(s)) s,
      ],
      e.$2,
      kay,
      [
        for (final s in _akimKarisan[e.$2]!)
          if (!e.$3.contains(s)) s,
      ],
    );

// Biçimlerin seçkileri ([_sirali] dengeli kipi). Üç açıklama üç ayrı nazım
// biçimini, üç sanatçı üç ayrı akımı gösterir: aynı biçimi tanıtan iki
// açıklama aynı özellikleri yineleyeceği için birlikte alınmaz.
final _nazimSecki = _uygunSecki(
  _nazimSerpik,
  _bicimBoyu(2),
  (x) => _dengeliKurulur(
    [for (final e in x) e.$2],
    [for (final e in x) _nazimYanlislari(e.$2, 0)],
  ),
);
final _temsilciSecki = _uygunSecki(
  _temsilciSerpik,
  _bicimBoyu(2),
  (x) => _dengeliKurulur(
    [for (final e in x) e.$2],
    [for (final e in x) _akimYanlislari(e, 0)],
  ),
);

final _nazimAkim = lmSirali(
  'tk_nazim_akim',
  'Nazım biçimleri ve Batı edebiyatı akımları',
  Topic.literature,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) {
    if (i.isEven) {
      final x = _bicimSecki(_nazimSerpik, i, 2, [_nazimSecki, null]);
      final dogru = [for (final e in x) e.$2];
      return _sirali(
        '${_uc([for (final e in x) '${e.$1}.'])}\nNumaralanmış açıklamaların '
            'tanıttığı nazım biçimleri sırasıyla hangi seçenekte doğru '
            'verilmiştir?',
        dogru,
        [for (var p = 0; p < 3; p++) _nazimYanlislari(dogru[p], i + p)],
        '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. açıklama: ${dogru[p]} (${_nazimOzet[dogru[p]]})'].join('; ')}.',
        i,
        dengeli: true,
      );
    }
    final x = _bicimSecki(_temsilciSerpik, i, 2, [null, _temsilciSecki]);
    final dogru = [for (final e in x) e.$2];
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış sanatçıların temsilcisi '
          'olduğu Batı edebiyatı akımları sırasıyla hangi seçenekte doğru '
          'verilmiştir?',
      dogru,
      [for (var p = 0; p < 3; p++) _akimYanlislari(x[p], i + p)],
      '${[for (final e in x) '${e.$1}: ${e.$2}'].join('; ')}.',
      i,
      dengeli: true,
    );
  },
  exam: ExamKind.ayt,
  lesson: 'Edebiyat',
);

// ───────────────────── 11 · Past continuous ve simple past ────────────────────

const _sureEylem =
    'geçmişte belli bir anda süren eylem: was/were ve fiilin -ing biçimi (past continuous)';
const _kisaEylem =
    'süren eylemin arasına giren kısa, tamamlanmış eylem: simple past';
const _ardEylem =
    'when ile art arda gerçekleşen tamamlanmış eylem: simple past';

// (cümle, boşluğa gelen biçim, o boşlukta kesin yanlış biçimler, gerekçe).
// Bağlamın hem simple past hem past continuous kaldırdığı boşluklarda öteki
// zaman çeldirici yapılmaz; çeldiriciler uyum, yardımcı fiil ve biçim
// yanlışlarıdır.
const _pastCont = [
  (
    "I ___ (read) a novel when the lights suddenly went out.",
    "was reading",
    ["were reading", "am reading", "reading"],
    _sureEylem,
  ),
  (
    "While we ___ (have) dinner, the doorbell rang.",
    "were having",
    ["was having", "are having", "having"],
    _sureEylem,
  ),
  (
    "While my mother was cooking, she ___ (cut) her finger.",
    "cut",
    ["cutted", "cuts", "has cut"],
    _kisaEylem,
  ),
  (
    "The children ___ (play) in the garden when it started to rain.",
    "were playing",
    ["was playing", "are playing", "playing"],
    _sureEylem,
  ),
  (
    "It ___ (rain) heavily when we left the cinema, so we took a taxi.",
    "was raining",
    ["were raining", "is raining", "raining"],
    _sureEylem,
  ),
  (
    "While Ali was riding his bike, he ___ (fall) off and hurt his knee.",
    "fell",
    ["falled", "falls", "has fallen"],
    _kisaEylem,
  ),
  (
    "I ___ (see) an accident while I was walking to school.",
    "saw",
    ["seed", "sees", "have seen"],
    _kisaEylem,
  ),
  (
    "What ___ (you / do) at eight o'clock last night?",
    "were you doing",
    ["was you doing", "did you doing", "you were doing"],
    _sureEylem,
  ),
  (
    "When the teacher came in, the students ___ (talk) loudly, so she got angry.",
    "were talking",
    ["was talking", "are talking", "talking"],
    _sureEylem,
  ),
  (
    "My father ___ (watch) the news when I got home last night.",
    "was watching",
    ["were watching", "is watching", "watching"],
    _sureEylem,
  ),
  (
    "While she was jogging in the park, she ___ (meet) an old friend.",
    "met",
    ["meeted", "meets", "has met"],
    _kisaEylem,
  ),
  (
    "We ___ (drive) along the coast when the car broke down.",
    "were driving",
    ["was driving", "are driving", "driving"],
    _sureEylem,
  ),
  (
    "Most people ___ (sleep) when the earthquake happened, so many of them woke up in panic.",
    "were sleeping",
    ["was sleeping", "are sleeping", "sleeping"],
    _sureEylem,
  ),
  (
    "The phone ___ (ring) while I was having a shower.",
    "rang",
    ["ringed", "rings", "has rung"],
    _kisaEylem,
  ),
  (
    "While Ayşe ___ (study) for her exam, her brother turned on loud music.",
    "was studying",
    ["were studying", "is studying", "studying"],
    _sureEylem,
  ),
  (
    "I ___ (lose) my keys while I was running for the bus.",
    "lost",
    ["losed", "loses", "have lost"],
    _kisaEylem,
  ),
  (
    "They ___ (not / listen) when the teacher explained the homework, so they didn't know what to do.",
    "weren't listening",
    ["wasn't listening", "didn't listening", "aren't listening"],
    _sureEylem,
  ),
  (
    "___ (it / snow) when you woke up this morning?",
    "Was it snowing",
    ["Were it snowing", "Did it snowing", "Is it snowing"],
    _sureEylem,
  ),
  (
    "While the guests were dancing, somebody ___ (break) a glass.",
    "broke",
    ["breaked", "breaks", "has broken"],
    _kisaEylem,
  ),
  (
    "When I looked out of the window, the sun ___ (shine) and the birds were singing.",
    "was shining",
    ["were shining", "is shining", "shining"],
    _sureEylem,
  ),
  (
    "While I was waiting for the bus, it ___ (start) to rain.",
    "started",
    ["starts", "has started", "was start"],
    _kisaEylem,
  ),
  (
    "Somebody stole her bag while she ___ (sit) in the café.",
    "was sitting",
    ["were sitting", "is sitting", "sitting"],
    _sureEylem,
  ),
  (
    "We ___ (walk) home from school when we saw a strange light in the sky.",
    "were walking",
    ["was walking", "are walking", "walking"],
    _sureEylem,
  ),
  (
    "When the bell rang, the students quickly ___ (leave) the classroom.",
    "left",
    ["leaved", "leaves", "has left"],
    _ardEylem,
  ),
  (
    "He ___ (fix) the roof when he fell off the ladder.",
    "was fixing",
    ["were fixing", "is fixing", "fixing"],
    _sureEylem,
  ),
  (
    "While the baby ___ (sleep), I finished all my homework.",
    "was sleeping",
    ["were sleeping", "is sleeping", "sleeping"],
    _sureEylem,
  ),
  (
    "The lights went out while we ___ (watch) a horror film.",
    "were watching",
    ["was watching", "are watching", "watching"],
    _sureEylem,
  ),
  (
    "I ___ (find) a twenty-lira note while I was cleaning my room.",
    "found",
    ["finded", "finds", "have found"],
    _kisaEylem,
  ),
  (
    "Where ___ (you / go) when I saw you yesterday?",
    "were you going",
    ["was you going", "did you going", "are you going"],
    _sureEylem,
  ),
  (
    "While Emre was playing football, he ___ (hurt) his ankle.",
    "hurt",
    ["hurted", "hurts", "has hurt"],
    _kisaEylem,
  ),
  (
    "At midnight last night, I ___ (still / study) for the test.",
    "was still studying",
    ["were still studying", "am still studying", "still studying"],
    _sureEylem,
  ),
  (
    "When we got to the beach, the sun ___ (set) and the sky was turning red.",
    "was setting",
    ["were setting", "is setting", "setting"],
    _sureEylem,
  ),
  (
    "While my brother was washing the dishes, he ___ (drop) a plate.",
    "dropped",
    ["droped", "drops", "has dropped"],
    _kisaEylem,
  ),
  (
    "Our teacher ___ (write) on the board when the fire alarm went off.",
    "was writing",
    ["were writing", "is writing", "writing"],
    _sureEylem,
  ),
  (
    "The kids ___ (make) a lot of noise when their father came home, so he asked them to be quiet.",
    "were making",
    ["was making", "are making", "making"],
    _sureEylem,
  ),
  (
    "While I was crossing the street, a car almost ___ (hit) me.",
    "hit",
    ["hitted", "hits", "has hit"],
    _kisaEylem,
  ),
  (
    "It ___ (get) dark when we finally reached the village.",
    "was getting",
    ["were getting", "is getting", "getting"],
    _sureEylem,
  ),
  (
    "While they were climbing the mountain, they ___ (hear) a strange noise.",
    "heard",
    ["heared", "hears", "have heard"],
    _kisaEylem,
  ),
  (
    "I ___ (talk) to my friend on the phone when the battery died.",
    "was talking",
    ["were talking", "am talking", "talking"],
    _sureEylem,
  ),
  (
    "While Selin was shopping, someone ___ (steal) her wallet.",
    "stole",
    ["stealed", "steals", "has stolen"],
    _kisaEylem,
  ),
  (
    "___ (they / play) tennis when the storm began?",
    "Were they playing",
    ["Was they playing", "Did they playing", "Are they playing"],
    _sureEylem,
  ),
  (
    "Mert ___ (sleep) on the sofa when his mother came home, so she covered him with a blanket.",
    "was sleeping",
    ["were sleeping", "is sleeping", "sleeping"],
    _sureEylem,
  ),
  (
    "My sister ___ (cry) when I found her in the garden, so I gave her a hug.",
    "was crying",
    ["were crying", "is crying", "crying"],
    _sureEylem,
  ),
  (
    "We ___ (have) a picnic when it suddenly started to rain.",
    "were having",
    ["was having", "are having", "having"],
    _sureEylem,
  ),
  (
    "While Can was reading in bed, the lamp suddenly ___ (go) out.",
    "went",
    ["goed", "goes", "has gone"],
    _kisaEylem,
  ),
];

// Seçkiler ([_sirali] dengeli kipi): üç boşluğun yanıtı ayrıdır ve her
// konuma öteki iki yanıttan ayrı birer çeldirici bulunur.
final _pastContSecki = _uygunSecki(
  _pastCont,
  lmAileBoyu,
  (x) => _dengeliKurulur([for (final e in x) e.$2], [for (final e in x) e.$3]),
);

final _pastContinuous = lmSirali(
  'en_past_continuous',
  'Past continuous ve simple past: when ve while',
  Topic.language,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final x = _dizili(_pastCont, i, _pastContSecki);
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde ayraç '
          'içinde verilen fiillerin boşluklara gelmesi gereken biçimleri sırasıyla '
          'hangi seçenekte doğru verilmiştir?',
      [for (final e in x) e.$2],
      [for (final e in x) e.$3],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$2}”: ${x[p].$4}'].join('; ')}.',
      i,
      dengeli: true,
    );
  },
  lesson: 'İngilizce',
);

// ───────────────────── 12 · used to, be used to, get used to ──────────────────

const _usedA =
    'geçmişte olup artık sürmeyen alışkanlık ya da durum: used to + yalın fiil';
const _usedB =
    'bir şeye alışkın olmak: be used to ardından -ing biçimi ya da ad';
const _usedC = 'bir şeye alışmak: get used to ardından -ing biçimi ya da ad';
const _usedD = 'olumsuz ve soru cümlesinde did ile birlikte “use to” yazılır';

// (cümle, boşluğa gelen söz, o boşlukta kesin yanlış sözler, gerekçe).
// Boşluktan sonraki yalın fiil, -ing biçimi ya da ad hangi yapının
// geleceğini dil bilgisi bakımından belirler. Boşluğa yapının bir parçası
// (yalnız “used” ya da yalnız yardımcı fiil) değil, uygun biçiminin tamamı
// gelir; “did” ile kurulan soru ve olumsuzlarda bu biçim “use to”dur.
// Tartışmalı “didn't used to” biçimi çeldirici yapılmaz.
const _usedTo = [
  (
    "When I was younger, I ___ play tennis every weekend.",
    "used to",
    ["was used to", "am used to", "use to"],
    _usedA,
  ),
  (
    "My grandfather ___ work on a farm, but now he lives in the city.",
    "used to",
    ["is used to", "was used to", "use to"],
    _usedA,
  ),
  (
    "There ___ be a cinema in our street, but it closed years ago.",
    "used to",
    ["was used to", "is used to", "use to"],
    _usedA,
  ),
  (
    "My sister ___ have long hair, but now it is very short.",
    "used to",
    ["is used to", "was used to", "use to"],
    _usedA,
  ),
  (
    "People ___ travel by horse before cars were invented.",
    "used to",
    ["were used to", "are used to", "use to"],
    _usedA,
  ),
  (
    "We ___ live in a small village, but we moved to Izmir in 2015.",
    "used to",
    ["were used to", "are used to", "use to"],
    _usedA,
  ),
  (
    "Our teacher ___ give us a quiz every Friday last year.",
    "used to",
    ["was used to", "is used to", "use to"],
    _usedA,
  ),
  (
    "My father ___ smoke, but he gave up five years ago.",
    "used to",
    ["is used to", "was used to", "use to"],
    _usedA,
  ),
  (
    "I ___ getting up early, so the new job is easy for me.",
    "am used to",
    ["used to", "use to", "am use to"],
    _usedB,
  ),
  (
    "She has lived in Erzurum for years, so she ___ the cold winters.",
    "is used to",
    ["used to", "uses to", "is use to"],
    _usedB,
  ),
  (
    "Nurses ___ working at night, so they sleep during the day.",
    "are used to",
    ["used to", "use to", "are use to"],
    _usedB,
  ),
  (
    "Ali has been a baker for twenty years, so he ___ waking up at four in the morning.",
    "is used to",
    ["used to", "uses to", "is use to"],
    _usedB,
  ),
  (
    "I can't sleep well here because I ___ sleeping in such a noisy room.",
    "am not used to",
    ["didn't use to", "not used to", "am not use to"],
    _usedB,
  ),
  (
    "Tourists from hot countries ___ the snow, so they find our winters difficult.",
    "aren't used to",
    ["didn't use to", "aren't use to", "don't used to"],
    _usedB,
  ),
  (
    "When we first moved to London, we ___ driving on the left.",
    "weren't used to",
    ["didn't use to", "aren't used to", "weren't use to"],
    _usedB,
  ),
  (
    "At first, the noise of the city kept me awake, but I soon ___ it.",
    "got used to",
    ["used to", "use to", "got use to"],
    _usedC,
  ),
  (
    "It took me months to ___ driving on the left in London.",
    "get used to",
    ["used to", "use to", "got used to"],
    _usedC,
  ),
  (
    "Don't worry about the new school; you will soon ___ it.",
    "get used to",
    ["used to", "use to", "got used to"],
    _usedC,
  ),
  (
    "My cousin moved to Canada last year, and he is slowly ___ the cold weather.",
    "getting used to",
    ["use to", "get used to", "getting use to"],
    _usedC,
  ),
  (
    "Tom found Turkish food very spicy at first, but after a few weeks he ___ eating it.",
    "got used to",
    ["used to", "use to", "was use to"],
    _usedC,
  ),
  (
    "Did you ___ walk to school when you were a child?",
    "use to",
    ["using to", "uses to", "be used to"],
    _usedD,
  ),
  (
    "She didn't ___ like vegetables, but now she loves them.",
    "use to",
    ["uses to", "using to", "be used to"],
    _usedD,
  ),
  (
    "What did people ___ do before television was invented?",
    "use to",
    ["uses to", "using to", "be used to"],
    _usedD,
  ),
  (
    "Did you ___ play with toy cars when you were little?",
    "use to",
    ["using to", "uses to", "be used to"],
    _usedD,
  ),
  (
    "My brother ___ like football, but now he watches every match.",
    "didn't use to",
    ["wasn't used to", "doesn't use to", "isn't used to"],
    _usedD,
  ),
  (
    "We ___ go camping every summer when my grandfather was alive.",
    "used to",
    ["were used to", "are used to", "use to"],
    _usedA,
  ),
  (
    "He ___ eat junk food, but now he only eats healthy meals.",
    "used to",
    ["is used to", "was used to", "use to"],
    _usedA,
  ),
  (
    "After living in Antalya for ten years, Elif ___ the hot summers.",
    "is used to",
    ["used to", "use to", "is use to"],
    _usedB,
  ),
  (
    "Soldiers ___ carrying heavy bags over long distances.",
    "are used to",
    ["used to", "use to", "are use to"],
    _usedB,
  ),
  (
    "I ___ wearing glasses yet; they still feel strange.",
    "haven't got used to",
    ["didn't use to", "haven't used to", "haven't got use to"],
    _usedC,
  ),
  (
    "My parents ___ go out a lot before I was born.",
    "used to",
    ["were used to", "are used to", "use to"],
    _usedA,
  ),
  (
    "Children in the village ___ walk five kilometres to school every day.",
    "used to",
    ["were used to", "are used to", "use to"],
    _usedA,
  ),
  (
    "Pilots ___ flying in bad weather.",
    "are used to",
    ["used to", "use to", "are use to"],
    _usedB,
  ),
  (
    "After a month in the new flat, we finally ___ the sound of the trains.",
    "got used to",
    ["used to", "use to", "got use to"],
    _usedC,
  ),
  (
    "Selin works the night shift, so she ___ sleeping during the day.",
    "is used to",
    ["used to", "uses to", "is use to"],
    _usedB,
  ),
  (
    "I ___ like spinach, but now it is one of my favourite foods.",
    "didn't use to",
    ["wasn't used to", "don't use to", "am not used to"],
    _usedD,
  ),
  (
    "Our neighbours ___ have a dog, but it died last year.",
    "used to",
    ["were used to", "are used to", "use to"],
    _usedA,
  ),
  (
    "This town ___ be very quiet, but now there are new factories everywhere.",
    "used to",
    ["was used to", "is used to", "use to"],
    _usedA,
  ),
  (
    "Many students find online lessons difficult because they ___ studying alone.",
    "aren't used to",
    ["didn't use to", "aren't use to", "not used to"],
    _usedB,
  ),
  (
    "Can you ___ living without a car in a big city?",
    "get used to",
    ["used to", "use to", "got used to"],
    _usedC,
  ),
  (
    "My grandmother ___ tell us stories every night when we were children.",
    "used to",
    ["was used to", "is used to", "use to"],
    _usedA,
  ),
  (
    "Ece moved to the city last month and is still ___ the noise.",
    "getting used to",
    ["use to", "get used to", "getting use to"],
    _usedC,
  ),
];

final _usedToSerpik = _serpistir(_usedTo, 4);
// Seçkiler ([_sirali] dengeli kipi): üç boşluğun yanıtı ayrıdır ve her
// konuma öteki iki yanıttan ayrı birer çeldirici bulunur.
final _usedToSecki = _uygunSecki(
  _usedToSerpik,
  lmAileBoyu,
  (x) => _dengeliKurulur([for (final e in x) e.$2], [for (final e in x) e.$3]),
);

final _usedToAile = lmSirali(
  'en_used_to',
  'used to, be used to ve get used to yapıları',
  Topic.language,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final x = _dizili(_usedToSerpik, i, _usedToSecki);
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde boş '
          'bırakılan yerlere “used to”, “be used to” ve “get used to” yapılarının '
          'uygun biçimleri sırasıyla hangi seçenekte doğru verilmiştir?',
      [for (final e in x) e.$2],
      [for (final e in x) e.$3],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$2}”: ${x[p].$4}'].join('; ')}.',
      i,
      dengeli: true,
    );
  },
  lesson: 'İngilizce',
);

// ───────────────────────────── 13 · Relative clauses ──────────────────────────

const _relKisi = 'kişiyi niteleyen yan cümlede who';
const _relSey = 'nesne ya da hayvanı niteleyen yan cümlede which';
const _relYer = 'yeri niteleyen ve içinde edat bulunmayan yan cümlede where';
const _relZaman = 'zamanı niteleyen yan cümlede when';
const _relIyelik = 'iyelik ilgisi kuran yan cümlede whose';
const _relVirgulKisi =
    'virgülle ayrılan (non-defining) yan cümlede kişi için who; that kullanılmaz';
const _relVirgulSey =
    'virgülle ayrılan (non-defining) yan cümlede nesne ya da yer adı için which; that kullanılmaz';
const _relThat =
    '“all, everything, the only” ve üstünlük sıfatlarından sonra that';

// (cümle, boşluğa gelen sözcük, o boşlukta kesin yanlış sözcükler, gerekçe).
// Tanımlayan yan cümlelerde that de doğru olduğundan oralarda that çeldirici
// yapılmaz; zaman adlarından sonra “that” ve edatlı “which” kullanılabildiği
// için when sorularında bu ikisi seçeneklere girmez. where cümlelerinde
// boşluktan sonra gelen ad “whose” ile de bağlanabiliyorsa (“a country whose
// people …”) cümle alınmamıştır. Öteki ilgi sözcüklerinin hepsi kesin
// yanlıştır: when kişi ve nesne adlarından, that edatsız where boşluklarından
// ve whose boşluklarından sonra, where, whose ve when virgüllü cümlelerde
// kullanılamaz. Böylece üç boşluğun yanıtları ayrı olduğunda her konuma
// yanıtlardan ve birbirinden ayrı çeldirici bulunur.
const _relatives = [
  (
    "The woman ___ lives next door is a doctor.",
    "who",
    ["which", "whose", "where", "when"],
    _relKisi,
  ),
  (
    "This is the book ___ I told you about.",
    "which",
    ["who", "whose", "where", "when"],
    _relSey,
  ),
  (
    "That is the house ___ my grandfather was born.",
    "where",
    ["which", "who", "whose", "when", "that"],
    _relYer,
  ),
  (
    "I will never forget the day ___ I met my best friend.",
    "when",
    ["where", "who", "whose"],
    _relZaman,
  ),
  (
    "This is the girl ___ father is a famous chef.",
    "whose",
    ["who", "which", "where", "when", "that"],
    _relIyelik,
  ),
  (
    "My brother, ___ lives in Ankara, is an engineer.",
    "who",
    ["that", "which", "whose", "where", "when"],
    _relVirgulKisi,
  ),
  (
    "The museum, ___ opened last year, is very popular.",
    "which",
    ["that", "who", "where", "when", "whose"],
    _relVirgulSey,
  ),
  (
    "Do you know the man ___ car was stolen yesterday?",
    "whose",
    ["who", "which", "where", "when", "that"],
    _relIyelik,
  ),
  (
    "The restaurant ___ we had dinner last night was excellent.",
    "where",
    ["which", "who", "whose", "when", "that"],
    _relYer,
  ),
  (
    "Summer is the season ___ most families go on holiday.",
    "when",
    ["where", "who", "whose"],
    _relZaman,
  ),
  (
    "The students ___ passed the exam received a certificate.",
    "who",
    ["which", "whose", "where", "when"],
    _relKisi,
  ),
  (
    "I lost the umbrella ___ my aunt gave me.",
    "which",
    ["who", "whose", "where", "when"],
    _relSey,
  ),
  (
    "Everything ___ he said was true.",
    "that",
    ["who", "whose", "where", "when"],
    _relThat,
  ),
  (
    "This is the best film ___ I have ever seen.",
    "that",
    ["who", "whose", "where", "when"],
    _relThat,
  ),
  (
    "Istanbul, ___ is the largest city in Türkiye, lies on two continents.",
    "which",
    ["that", "who", "where", "when", "whose"],
    _relVirgulSey,
  ),
  (
    "The man ___ I spoke to on the phone was very polite.",
    "who",
    ["which", "whose", "where", "when"],
    _relKisi,
  ),
  (
    "Ankara is the city ___ I spent my childhood.",
    "where",
    ["which", "who", "whose", "when", "that"],
    _relYer,
  ),
  (
    "Do you remember the year ___ we moved to this town?",
    "when",
    ["where", "who", "whose"],
    _relZaman,
  ),
  (
    "The boy ___ bike was stolen went to the police.",
    "whose",
    ["who", "which", "where", "when", "that"],
    _relIyelik,
  ),
  (
    "A dictionary is a book ___ gives the meanings of words.",
    "which",
    ["who", "whose", "where", "when"],
    _relSey,
  ),
  (
    "A vet is a person ___ takes care of sick animals.",
    "who",
    ["which", "whose", "where", "when"],
    _relKisi,
  ),
  (
    "A library is a place ___ you can borrow books.",
    "where",
    ["which", "who", "whose", "when", "that"],
    _relYer,
  ),
  (
    "An orphan is a child ___ parents have died.",
    "whose",
    ["who", "which", "where", "when", "that"],
    _relIyelik,
  ),
  (
    "Monday is the day ___ the shop is closed.",
    "when",
    ["where", "who", "whose"],
    _relZaman,
  ),
  (
    "My grandmother, ___ is eighty years old, still goes swimming every day.",
    "who",
    ["that", "which", "whose", "where", "when"],
    _relVirgulKisi,
  ),
  (
    "The car ___ my father bought last month is red.",
    "which",
    ["who", "whose", "where", "when"],
    _relSey,
  ),
  (
    "The singer ___ songs we all love is coming to our city.",
    "whose",
    ["who", "which", "where", "when", "that"],
    _relIyelik,
  ),
  (
    "The village ___ my parents grew up is very small.",
    "where",
    ["which", "who", "whose", "when", "that"],
    _relYer,
  ),
  (
    "Mr Demir, ___ teaches us history, is very kind.",
    "who",
    ["that", "which", "whose", "where", "when"],
    _relVirgulKisi,
  ),
  (
    "The laptop, ___ I bought only a month ago, has already broken down.",
    "which",
    ["that", "who", "where", "when", "whose"],
    _relVirgulSey,
  ),
  (
    "The children ___ are playing in the garden are my cousins.",
    "who",
    ["which", "whose", "where", "when"],
    _relKisi,
  ),
  (
    "I need a knife ___ can cut bread.",
    "which",
    ["who", "whose", "where", "when"],
    _relSey,
  ),
  (
    "Is this the shop ___ you bought your shoes?",
    "where",
    ["which", "who", "whose", "when", "that"],
    _relYer,
  ),
  (
    "I remember the moment ___ the plane landed safely.",
    "when",
    ["where", "who", "whose"],
    _relZaman,
  ),
  (
    "The writer ___ books are on the table is my uncle.",
    "whose",
    ["who", "which", "where", "when", "that"],
    _relIyelik,
  ),
  (
    "All ___ you need is a good night's sleep.",
    "that",
    ["who", "whose", "where", "when"],
    _relThat,
  ),
  (
    "The only thing ___ matters is your health.",
    "that",
    ["who", "whose", "where", "when"],
    _relThat,
  ),
  (
    "Our neighbours, ___ dog barks all night, are moving next month.",
    "whose",
    ["who", "which", "that", "where", "when"],
    _relIyelik,
  ),
  (
    "The film ___ we watched last night was boring.",
    "which",
    ["who", "whose", "where", "when"],
    _relSey,
  ),
  (
    "Can you name a country ___ it never snows?",
    "where",
    ["which", "who", "whose", "when", "that"],
    _relYer,
  ),
  (
    "1923 is the year ___ the Republic of Türkiye was founded.",
    "when",
    ["where", "who", "whose"],
    _relZaman,
  ),
  (
    "The teacher ___ helped me with my project was Mrs Kaya.",
    "who",
    ["which", "whose", "where", "when"],
    _relKisi,
  ),
  (
    "Paris, ___ is the capital of France, is famous for its museums.",
    "which",
    ["that", "who", "where", "when", "whose"],
    _relVirgulSey,
  ),
];

// Seçkiler ([_sirali] dengeli kipi): üç boşluğun yanıtı ayrıdır ve her
// konuma öteki iki yanıttan ayrı birer çeldirici bulunur.
final _relativeSecki = _uygunSecki(
  _relatives,
  lmAileBoyu,
  (x) => _dengeliKurulur([for (final e in x) e.$2], [for (final e in x) e.$3]),
);

final _relativeAile = lmSirali(
  'en_relative',
  'Relative clauses: who, which, that, where, whose, when',
  Topic.language,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final x = _dizili(_relatives, i, _relativeSecki);
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde boş '
          'bırakılan yerlere gelmesi gereken ilgi sözcükleri (relative pronouns '
          've adverbs) sırasıyla hangi seçenekte doğru verilmiştir?',
      [for (final e in x) e.$2],
      [for (final e in x) e.$3],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$2}”: ${x[p].$4}'].join('; ')}.',
      i,
      dengeli: true,
    );
  },
  lesson: 'İngilizce',
);

// ───────────────────────────── 14 · Reported speech ───────────────────────────

// (doğrudan anlatım, dolaylı anlatım, boşluğa gelen söz, o boşlukta kesin
//  yanlış sözler, gerekçe). Söylenen durumun hâlâ geçerli olabileceği
//  cümlelerde zaman kaydırması isteğe bağlıdır; bu yüzden ya zaman ifadesi
//  aktarımı geçmişe bağlar (“that day”, “the next day”) ya da çeldiriciler
//  kaydırılmamış zaman yerine biçim, sözcük sırası ve zamir yanlışlarıdır.
//  Dolaylı anlatımdaki her zaman ve yer ifadesi, doğrudan anlatımdaki bir
//  ifadenin dönüşmüş biçimidir (now → at that moment gibi); kaynağı olmayan
//  ifade eklenmez.
const _reported = [
  (
    "Elif said, “I am very tired today.”",
    "Elif said that she ___ very tired that day.",
    "was",
    ["is", "were", "has been"],
    "am → was, today → that day",
  ),
  (
    "Mert said, “I will visit my grandmother tomorrow.”",
    "Mert said that he ___ his grandmother the next day.",
    "would visit",
    ["will visit", "would visited", "visits"],
    "will → would, tomorrow → the next day",
  ),
  (
    "The teacher said, “We are going to have a test next week.”",
    "The teacher said that they ___ a test the following week.",
    "were going to have",
    ["are going to have", "was going to have", "were going to had"],
    "are going to → were going to, next week → the following week",
  ),
  (
    "Ayşe said, “I bought this dress yesterday.”",
    "Ayşe said that she ___ that dress the day before.",
    "had bought",
    ["has bought", "had buy", "buys"],
    "bought → had bought, yesterday → the day before",
  ),
  (
    "When he was ten, Can said, “I can swim very well now.”",
    "When he was ten, Can said that he ___ swim very well then.",
    "could",
    ["can", "could to", "cans"],
    "can → could, now → then",
  ),
  (
    "Last month, my friends said, “We have just finished our project.”",
    "Last month, my friends said that they ___ just finished their project.",
    "had",
    ["have", "has", "were"],
    "have finished → had finished",
  ),
  (
    "Dad said, “I am watching the match now.”",
    "Dad said that he ___ the match then.",
    "was watching",
    ["is watching", "were watching", "was watch"],
    "am watching → was watching, now → then",
  ),
  (
    "Zeynep said to me, “I like your new bag.”",
    "Zeynep told me that she liked ___ new bag.",
    "my",
    ["your", "her", "his"],
    "konuşulan kişiye ait “your”, aktaranın ağzından “my” olur",
  ),
  (
    "Emre said, “My brother lives in London.”",
    "Emre said that ___ brother lived in London.",
    "his",
    ["my", "her", "your"],
    "konuşanın kendisine ait “my”, “his” olur",
  ),
  (
    "Last month, Selin said, “I saw him yesterday.”",
    "Last month, Selin said that she had seen him ___.",
    "the day before",
    ["yesterday", "the next day", "tomorrow"],
    "yesterday → the day before",
  ),
  (
    "Last summer, Burak said, “I will start university next year.”",
    "Last summer, Burak said that he would start university ___.",
    "the following year",
    ["the year before", "last year", "yesterday"],
    "next year → the following year",
  ),
  (
    "Kerem phoned from Paris and said, “I love it here.”",
    "Kerem phoned from Paris and said that he loved it ___.",
    "there",
    ["here", "then", "where"],
    "here → there",
  ),
  (
    "She asked me, “Where are you going?”",
    "She asked me where ___.",
    "I was going",
    ["was I going", "am I going", "did I go"],
    "aktarılan soru düz cümle sırasına girer ve zaman kayar",
  ),
  (
    "He asked me, “Are you tired?”",
    "He asked me ___ I was tired.",
    "if",
    ["that", "what", "do"],
    "evet-hayır sorusu if ile aktarılır",
  ),
  (
    "The teacher said to us, “Close your books.”",
    "The teacher told us ___ our books.",
    "to close",
    ["close", "closing", "that close"],
    "emir cümlesi to + yalın fiil ile aktarılır",
  ),
  (
    "Mom said to me, “Don't be late.”",
    "Mom told me ___ late.",
    "not to be",
    ["don't be", "not be", "not being"],
    "olumsuz emir not to + yalın fiil ile aktarılır",
  ),
  (
    "When he was a child, Ali said, “I don't like vegetables.”",
    "When he was a child, Ali said that he ___ like vegetables.",
    "didn't",
    ["doesn't", "don't", "wasn't"],
    "don't → didn't",
  ),
  (
    "Deniz said, “I lost my keys yesterday.”",
    "Deniz said that she ___ her keys the day before.",
    "had lost",
    ["has lost", "have lost", "had lose"],
    "lost → had lost, yesterday → the day before",
  ),
  (
    "Ece asked me, “What time is it?”",
    "Ece asked me what time ___.",
    "it was",
    ["was it", "is it", "did it be"],
    "aktarılan soru düz cümle sırasına girer",
  ),
  (
    "The doctor said to my father, “You must eat less salt.”",
    "The doctor told my father that ___ eat less salt.",
    "he had to",
    ["you must", "I had to", "he had"],
    "you → he, must → had to",
  ),
  (
    "My sister said, “I am going to the cinema tonight.”",
    "My sister said that she ___ to the cinema that night.",
    "was going",
    ["is going", "were going", "goes"],
    "am going → was going, tonight → that night",
  ),
  (
    "Murat said, “I passed my driving test last week.”",
    "Murat said that he ___ his driving test the week before.",
    "had passed",
    ["has passed", "had pass", "passes"],
    "passed → had passed, last week → the week before",
  ),
  (
    "Baran said, “I am writing an email to my boss now.”",
    "Baran said that he ___ an email to his boss at that moment.",
    "was writing",
    ["is writing", "were writing", "was write"],
    "am writing → was writing, now → at that moment",
  ),
  (
    "The children said, “We are hungry.”",
    "The children said that ___ hungry.",
    "they were",
    ["we were", "we are", "them were"],
    "we → they, are → were",
  ),
  (
    "Last year, Ayşe said to Ali, “I will help you tomorrow.”",
    "Last year, Ayşe told Ali that she would help him ___.",
    "the next day",
    ["tomorrow", "yesterday", "the day before"],
    "tomorrow → the next day",
  ),
  (
    "Tom asked me, “Can you help me?”",
    "Tom asked me if I could help ___.",
    "him",
    ["me", "you", "us"],
    "yardım isteyen Tom olduğu için “me”, “him” olur",
  ),
  (
    "The receptionist said to me, “Your room is ready.”",
    "The receptionist told me that ___ room was ready.",
    "my",
    ["your", "her", "their"],
    "aktarana ait “your”, “my” olur",
  ),
  (
    "My parents said to me, “We will buy you a bike.”",
    "My parents told me that they would buy ___ a bike.",
    "me",
    ["you", "them", "us"],
    "aktaran kişiye yöneltilen “you”, “me” olur",
  ),
  (
    "Last night, Ali said, “I am leaving now.”",
    "Last night, Ali said that he was leaving ___.",
    "then",
    ["now", "tomorrow", "ago"],
    "now → then",
  ),
  (
    "Two days ago, Selin said, “I will finish the report today.”",
    "Two days ago, Selin said that she would finish the report ___.",
    "that day",
    ["today", "tomorrow", "yesterday"],
    "today → that day",
  ),
  (
    "A week ago, my uncle said, “I arrived in Ankara this morning.”",
    "A week ago, my uncle said that he had arrived in Ankara ___.",
    "that morning",
    ["this morning", "tomorrow morning", "the next morning"],
    "this morning → that morning",
  ),
  (
    "The waiter asked us, “What would you like to drink?”",
    "The waiter asked us what ___ to drink.",
    "we would like",
    ["would we like", "you would like", "would you like"],
    "soru düz cümle sırasına girer, you → we",
  ),
  (
    "The coach said to the players, “Don't give up.”",
    "The coach told the players ___ up.",
    "not to give",
    ["don't give", "not give", "not giving"],
    "olumsuz emir not to + yalın fiil ile aktarılır",
  ),
  (
    "My friend said to me, “Wait for me at the station.”",
    "My friend told me ___ for him at the station.",
    "to wait",
    ["wait", "waiting", "that wait"],
    "emir cümlesi to + yalın fiil ile aktarılır",
  ),
  (
    "He asked me, “Have you ever been to Rome?”",
    "He asked me ___ I had ever been to Rome.",
    "if",
    ["that", "what", "have"],
    "evet-hayır sorusu if ile aktarılır",
  ),
  (
    "Last night, my brother said, “I can't find my phone.”",
    "Last night, my brother said that he couldn't find ___ phone.",
    "his",
    ["my", "your", "her"],
    "konuşanın kendisine ait “my”, “his” olur",
  ),
  (
    "My grandmother said, “I was born in a small village.”",
    "My grandmother said that she ___ born in a small village.",
    "had been",
    ["has been", "have been", "is"],
    "was → had been",
  ),
  (
    "Last week, Elif said, “I am meeting my friends tomorrow.”",
    "Last week, Elif said that she was meeting her friends ___.",
    "the next day",
    ["tomorrow", "yesterday", "the day before"],
    "tomorrow → the next day",
  ),
  (
    "Ozan said to us, “You should read this book.”",
    "Ozan told us that ___ should read that book.",
    "we",
    ["you", "they", "he"],
    "aktaranlara yöneltilen “you”, “we” olur",
  ),
  (
    "Yesterday, my sister said to me, “I will call you tonight.”",
    "Yesterday, my sister told me that she would call me ___.",
    "that night",
    ["tonight", "the night before", "tomorrow"],
    "tonight → that night",
  ),
];

// Seçkiler ([_sirali] dengeli kipi): üç boşluğun yanıtı ayrıdır ve her
// konuma öteki iki yanıttan ayrı birer çeldirici bulunur.
final _reportedSecki = _uygunSecki(
  _reported,
  lmAileBoyu,
  (x) => _dengeliKurulur([for (final e in x) e.$3], [for (final e in x) e.$4]),
);

final _reportedAile = lmSirali(
  'en_reported',
  'Reported speech: zaman, zamir ve zaman ifadesi',
  Topic.language,
  Difficulty.hard,
  BloomLevel.uygulama,
  (i) {
    final x = _dizili(_reported, i, _reportedSecki);
    return _sirali(
      '${_uc([for (final e in x) '${e.$1} → ${e.$2}'])}\nNumaralanmış '
          'cümlelerde doğrudan anlatım dolaylı anlatıma (reported speech) '
          'çevrilmiştir. Boş bırakılan yerlere sırasıyla hangileri getirilmelidir?',
      [for (final e in x) e.$3],
      [for (final e in x) e.$4],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$3}”: ${x[p].$5}'].join('; ')}.',
      i,
      dengeli: true,
    );
  },
  lesson: 'İngilizce',
);

// ───────────────────────── 15 · Gerund ve infinitive ──────────────────────────

// (cümle, boşluğa gelen biçim, o boşlukta kesin yanlış biçimler, kural).
// Ardından iki yapının da gelebildiği fiiller (like, love, start, stop,
// remember, try, can't stand gibi) alınmamıştır.
const _gerundInf = [
  (
    "My brother enjoys ___ (play) chess with our grandfather.",
    "playing",
    ["to play", "play", "played"],
    "“enjoy” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "She decided ___ (study) medicine at university.",
    "to study",
    ["studying", "study", "studied"],
    "“decide” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "You should avoid ___ (eat) too much sugar.",
    "eating",
    ["to eat", "eat", "ate"],
    "“avoid” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "We hope ___ (see) you again soon.",
    "to see",
    ["seeing", "see", "saw"],
    "“hope” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "Have you finished ___ (write) your essay yet?",
    "writing",
    ["to write", "write", "wrote"],
    "“finish” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "They are planning ___ (visit) Cappadocia next summer.",
    "to visit",
    ["visiting", "visit", "visited"],
    "“plan” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "Would you mind ___ (open) the window, please?",
    "opening",
    ["to open", "open", "opened"],
    "“mind” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "I want ___ (learn) how to play the guitar.",
    "to learn",
    ["learning", "learn", "learned"],
    "“want” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "He kept ___ (talk) during the whole film.",
    "talking",
    ["to talk", "talk", "talked"],
    "“keep” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "My parents agreed ___ (buy) me a new laptop.",
    "to buy",
    ["buying", "buy", "bought"],
    "“agree” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "My doctor suggested ___ (walk) for thirty minutes a day.",
    "walking",
    ["to walk", "walk", "walked"],
    "“suggest” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "She promised ___ (help) me with my homework.",
    "to help",
    ["helping", "help", "helped"],
    "“promise” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "You need to practise ___ (speak) English every day.",
    "speaking",
    ["to speak", "speak", "spoke"],
    "“practise” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "The little boy refused ___ (eat) his vegetables.",
    "to eat",
    ["eating", "eat", "ate"],
    "“refuse” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "My father gave up ___ (smoke) ten years ago.",
    "smoking",
    ["to smoke", "smoke", "smoked"],
    "“give up” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "My sister is learning ___ (drive) this summer.",
    "to drive",
    ["driving", "drive", "drove"],
    "“learn” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "Can you imagine ___ (live) on the Moon?",
    "living",
    ["to live", "live", "lived"],
    "“imagine” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "Despite the heavy traffic, we managed ___ (arrive) on time.",
    "to arrive",
    ["arriving", "arrive", "arrived"],
    "“manage” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "We are considering ___ (move) to a bigger flat.",
    "moving",
    ["to move", "move", "moved"],
    "“consider” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "My neighbour offered ___ (carry) my heavy bags.",
    "to carry",
    ["carrying", "carry", "carried"],
    "“offer” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "We didn't expect ___ (win) the match so easily.",
    "to win",
    ["winning", "win", "won"],
    "“expect” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "I really miss ___ (swim) in the sea in winter.",
    "swimming",
    ["to swim", "swim", "swam"],
    "“miss” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "I would like ___ (order) a cup of tea, please.",
    "to order",
    ["ordering", "order", "ordered"],
    "“would like” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "The thief admitted ___ (steal) the money.",
    "stealing",
    ["to steal", "steal", "stole"],
    "“admit” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "We can't afford ___ (buy) a new car this year.",
    "to buy",
    ["buying", "buy", "bought"],
    "“afford” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "He denied ___ (break) the window.",
    "breaking",
    ["to break", "break", "broke"],
    "“deny” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "She pretended ___ (be) asleep when her mother came in.",
    "to be",
    ["being", "be", "was"],
    "“pretend” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "Don't risk ___ (lose) your job by arriving late every day.",
    "losing",
    ["to lose", "lose", "lost"],
    "“risk” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "The children seem ___ (enjoy) the party.",
    "to enjoy",
    ["enjoying", "enjoy", "enjoyed"],
    "“seem” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "I spent the whole weekend ___ (clean) the house.",
    "cleaning",
    ["to clean", "clean", "cleaned"],
    "“spend (zaman)” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "Many students fail ___ (understand) this rule at first.",
    "to understand",
    ["understanding", "understand", "understood"],
    "“fail” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "I am looking forward to ___ (meet) your family.",
    "meeting",
    ["meet", "met", "have met"],
    "“look forward to” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "Ece chose ___ (stay) at home instead of going out.",
    "to stay",
    ["staying", "stay", "stayed"],
    "“choose” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "Keep ___ (try), and you will succeed one day.",
    "trying",
    ["to try", "try", "tried"],
    "“keep” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "We arranged ___ (meet) at the café at six.",
    "to meet",
    ["meeting", "meet", "met"],
    "“arrange” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "He suggested ___ (go) to the beach on Sunday.",
    "going",
    ["to go", "go", "went"],
    "“suggest” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "I need ___ (buy) some bread on the way home.",
    "to buy",
    ["buying", "buy", "bought"],
    "“need” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "Our team deserved ___ (win) the cup.",
    "to win",
    ["winning", "win", "won"],
    "“deserve” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "She finished ___ (read) the novel in two days.",
    "reading",
    ["to read", "read", "readed"],
    "“finish” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "Please avoid ___ (use) your phone in the library.",
    "using",
    ["to use", "use", "used"],
    "“avoid” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "My cousin hopes ___ (become) a pilot one day.",
    "to become",
    ["becoming", "become", "became"],
    "“hope” sonrasında to ve yalın fiil (infinitive) gelir",
  ),
  (
    "Do you mind ___ (wait) a few minutes?",
    "waiting",
    ["to wait", "wait", "waited"],
    "“mind” sonrasında -ing biçimi (gerund) gelir",
  ),
  (
    "The students practised ___ (pronounce) the new words.",
    "pronouncing",
    ["to pronounce", "pronounce", "pronounced"],
    "“practise” sonrasında -ing biçimi (gerund) gelir",
  ),
];

// Seçkiler ([_sirali] dengeli kipi): üç boşluğun yanıtı ayrıdır ve her
// konuma öteki iki yanıttan ayrı birer çeldirici bulunur.
final _gerundSecki = _uygunSecki(
  _gerundInf,
  lmAileBoyu,
  (x) => _dengeliKurulur([for (final e in x) e.$2], [for (final e in x) e.$3]),
);

final _gerundAile = lmSirali(
  'en_gerund_inf',
  'Gerund ve infinitive: fiilden sonra gelen yapı',
  Topic.language,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final x = _dizili(_gerundInf, i, _gerundSecki);
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde ayraç '
          'içinde verilen fiillerin, önlerindeki fiile ya da yapıya göre alması '
          'gereken biçimler (gerund ya da infinitive) sırasıyla hangi seçenekte '
          'doğru verilmiştir?',
      [for (final e in x) e.$2],
      [for (final e in x) e.$3],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$2}”: ${x[p].$4}'].join('; ')}.',
      i,
      dengeli: true,
    );
  },
  lesson: 'İngilizce',
);

// ────────────────────────────── 16 · Question tags ────────────────────────────

const _tagOlumlu = 'olumlu cümleye olumsuz soru eklentisi gelir';
const _tagOlumsuz = 'olumsuz cümleye olumlu soru eklentisi gelir';

// (cümle, soru eklentisi, o yerde kesin yanlış eklentiler, kural).
// Birden çok eklentinin kabul edildiği emir cümleleri ve “have” asıl fiili
// gibi tartışmalı yapılar alınmamıştır.
const _tags = [
  (
    "You are a student, ___?",
    "aren't you",
    ["aren't they", "don't you", "isn't you"],
    "$_tagOlumlu; yardımcı fiil “are” yinelenir",
  ),
  (
    "She isn't at home, ___?",
    "is she",
    ["isn't she", "does she", "is it"],
    "$_tagOlumsuz; yardımcı fiil “is” yinelenir",
  ),
  (
    "They play football on Sundays, ___?",
    "don't they",
    ["don't you", "aren't they", "doesn't they"],
    "$_tagOlumlu; geniş zamanda “do” kullanılır",
  ),
  (
    "Your brother works in a bank, ___?",
    "doesn't he",
    ["don't he", "doesn't she", "isn't he"],
    "$_tagOlumlu; üçüncü tekil kişide “does” kullanılır",
  ),
  (
    "You didn't call me yesterday, ___?",
    "did you",
    ["didn't you", "do you", "were you"],
    "$_tagOlumsuz; geçmiş zamanda “did” kullanılır",
  ),
  (
    "Ali has finished his homework, ___?",
    "hasn't he",
    ["doesn't he", "didn't he", "isn't he"],
    "$_tagOlumlu; yardımcı fiil “has” yinelenir",
  ),
  (
    "We can swim here, ___?",
    "can't we",
    ["can't you", "don't we", "couldn't we"],
    "$_tagOlumlu; kip “can” yinelenir",
  ),
  (
    "It will rain tomorrow, ___?",
    "won't it",
    ["wouldn't it", "doesn't it", "isn't it"],
    "$_tagOlumlu; “will” olumsuzda “won't” olur",
  ),
  (
    "You should study harder, ___?",
    "shouldn't you",
    ["shouldn't they", "don't you", "wouldn't you"],
    "$_tagOlumlu; kip “should” yinelenir",
  ),
  (
    "I am late again, ___?",
    "aren't I",
    ["isn't I", "aren't you", "don't I"],
    "$_tagOlumlu; “I am” cümlesinde eklenti “aren't I” olur",
  ),
  (
    "Let's go to the cinema, ___?",
    "shall we",
    ["will we", "don't we", "let's we"],
    "“Let's” ile başlayan öneri cümlesinde eklenti “shall we” olur",
  ),
  (
    "There is a bank near here, ___?",
    "isn't there",
    ["isn't it", "aren't there", "doesn't there"],
    "$_tagOlumlu; “there is” yapısında “there” yinelenir",
  ),
  (
    "Your parents were at the meeting, ___?",
    "weren't they",
    ["wasn't they", "weren't you", "didn't they"],
    "$_tagOlumlu; yardımcı fiil “were” yinelenir",
  ),
  (
    "Mert was ill last week, ___?",
    "wasn't he",
    ["weren't he", "wasn't she", "didn't he"],
    "$_tagOlumlu; yardımcı fiil “was” yinelenir",
  ),
  (
    "You haven't seen my keys, ___?",
    "have you",
    ["haven't you", "did you", "do you"],
    "$_tagOlumsuz; yardımcı fiil “have” yinelenir",
  ),
  (
    "She can't speak French, ___?",
    "can she",
    ["can't she", "does she", "could she"],
    "$_tagOlumsuz; kip “can” yinelenir",
  ),
  (
    "He won't be late, ___?",
    "will he",
    ["won't he", "does he", "is he"],
    "$_tagOlumsuz; “won't” eklentide “will” olur",
  ),
  (
    "Ayşe went to Izmir last summer, ___?",
    "didn't she",
    ["didn't he", "wasn't she", "doesn't she"],
    "$_tagOlumlu; geçmiş zamanda “did” kullanılır",
  ),
  (
    "They aren't coming to the party, ___?",
    "are they",
    ["aren't they", "do they", "will they"],
    "$_tagOlumsuz; yardımcı fiil “are” yinelenir",
  ),
  (
    "Nobody called while I was out, ___?",
    "did they",
    ["didn't they", "do they", "was it"],
    "“nobody” cümleyi olumsuz yapar; eklenti olumlu olur ve “they” kullanılır",
  ),
  (
    "Your sister doesn't like coffee, ___?",
    "does she",
    ["doesn't she", "is she", "do she"],
    "$_tagOlumsuz; üçüncü tekil kişide “does” kullanılır",
  ),
  (
    "We have met before, ___?",
    "haven't we",
    ["didn't we", "haven't you", "don't we"],
    "$_tagOlumlu; yardımcı fiil “have” yinelenir",
  ),
  (
    "The film was boring, ___?",
    "wasn't it",
    ["didn't it", "weren't it", "wasn't the film"],
    "$_tagOlumlu; eklentide ad yerine zamir (“it”) kullanılır",
  ),
  (
    "You would like some tea, ___?",
    "wouldn't you",
    ["won't you", "wouldn't they", "don't you"],
    "$_tagOlumlu; kip “would” yinelenir",
  ),
  (
    "It isn't very cold today, ___?",
    "is it",
    ["isn't it", "does it", "was it"],
    "$_tagOlumsuz; yardımcı fiil “is” yinelenir",
  ),
  (
    "Your friends live in Ankara, ___?",
    "don't they",
    ["doesn't they", "don't we", "aren't they"],
    "$_tagOlumlu; geniş zamanda “do” kullanılır",
  ),
  (
    "The children are sleeping, ___?",
    "aren't they",
    ["aren't we", "don't they", "isn't they"],
    "$_tagOlumlu; yardımcı fiil “are” yinelenir",
  ),
  (
    "He never eats meat, ___?",
    "does he",
    ["doesn't he", "is he", "did he"],
    "“never” cümleyi olumsuz yapar; eklenti olumlu olur",
  ),
  (
    "You could help me, ___?",
    "couldn't you",
    ["couldn't I", "can't you", "don't you"],
    "$_tagOlumlu; kip “could” yinelenir",
  ),
  (
    "This is your bag, ___?",
    "isn't it",
    ["isn't this", "aren't it", "doesn't it"],
    "$_tagOlumlu; “this” eklentide “it” olur",
  ),
  (
    "Those are your shoes, ___?",
    "aren't they",
    ["aren't those", "isn't it", "don't they"],
    "$_tagOlumlu; “those” eklentide “they” olur",
  ),
  (
    "We must hurry, ___?",
    "mustn't we",
    ["mustn't you", "don't we", "needn't we"],
    "$_tagOlumlu; kip “must” yinelenir",
  ),
  (
    "Everyone enjoyed the trip, ___?",
    "didn't they",
    ["didn't he", "doesn't they", "wasn't it"],
    "$_tagOlumlu; “everyone” için eklentide “they” kullanılır",
  ),
  (
    "Selin and Can are married, ___?",
    "aren't they",
    ["isn't it", "isn't she", "aren't we"],
    "$_tagOlumlu; iki kişilik özne için “they” kullanılır",
  ),
  (
    "You were born in 2009, ___?",
    "weren't you",
    ["wasn't you", "weren't they", "didn't you"],
    "$_tagOlumlu; yardımcı fiil “were” yinelenir",
  ),
  (
    "The shop opens at nine, ___?",
    "doesn't it",
    ["isn't it", "doesn't they", "don't it"],
    "$_tagOlumlu; üçüncü tekil kişide “does” kullanılır",
  ),
  (
    "Your mother can drive, ___?",
    "can't she",
    ["doesn't she", "couldn't she", "can't he"],
    "$_tagOlumlu; kip “can” yinelenir",
  ),
  (
    "I'm not late, ___?",
    "am I",
    ["aren't I", "do I", "is it"],
    "$_tagOlumsuz; “I'm not” cümlesinde eklenti “am I” olur",
  ),
  (
    "Kerem hasn't got a car, ___?",
    "has he",
    ["hasn't he", "does he", "is he"],
    "$_tagOlumsuz; “has got” yapısında “has” yinelenir",
  ),
  (
    "They will be here soon, ___?",
    "won't they",
    ["won't we", "don't they", "aren't they"],
    "$_tagOlumlu; “will” olumsuzda “won't” olur",
  ),
  (
    "It was a great match, ___?",
    "wasn't it",
    ["wasn't he", "didn't it", "isn't it"],
    "$_tagOlumlu; yardımcı fiil “was” yinelenir",
  ),
  (
    "You don't eat fish, ___?",
    "do you",
    ["don't you", "are you", "did you"],
    "$_tagOlumsuz; geniş zamanda “do” kullanılır",
  ),
  (
    "Emre plays the violin very well, ___?",
    "doesn't he",
    ["don't he", "doesn't she", "isn't he"],
    "$_tagOlumlu; üçüncü tekil kişide “does” kullanılır",
  ),
];

// Seçkiler ([_sirali] dengeli kipi): üç boşluğun yanıtı ayrıdır ve her
// konuma öteki iki yanıttan ayrı birer çeldirici bulunur.
final _tagSecki = _uygunSecki(
  _tags,
  lmAileBoyu,
  (x) => _dengeliKurulur([for (final e in x) e.$2], [for (final e in x) e.$3]),
);

final _questionTag = lmSirali(
  'en_question_tag',
  'Question tags: soru eklentileri',
  Topic.language,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final x = _dizili(_tags, i, _tagSecki);
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerin sonundaki '
          'boşluklara gelmesi gereken soru eklentileri (question tags) sırasıyla '
          'hangi seçenekte doğru verilmiştir?',
      [for (final e in x) e.$2],
      [for (final e in x) e.$3],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$2}”: ${x[p].$4}'].join('; ')}.',
      i,
      dengeli: true,
    );
  },
  lesson: 'İngilizce',
);

// ───────────────────── 17 · Third conditional ve wish cümleleri ───────────────

const _ucKosul =
    'geçmişte gerçekleşmemiş koşul (third conditional): if + had + V3';
const _ucSonuc =
    'geçmişe ait gerçekleşmemiş sonuç (third conditional): would have + V3';
const _dilekSimdi =
    'şimdiki duruma ilişkin gerçekleşmemiş dilek: wish + past simple';
const _dilekGecmis = 'geçmişe ilişkin pişmanlık: wish + had + V3';

// (cümle, boşluğa gelen biçim, o boşlukta kesin yanlış biçimler, kural).
// Sonuç cümlelerindeki “would had + V3” yaygın bir öğrenci yanlışıdır.
// Zaman ifadeleri (yesterday, last week, now, these days) koşulun ya da
// dileğin geçmişe mi şimdiye mi ait olduğunu belirler; karma koşul
// cümlesinin kurulabileceği boşluk bırakılmamıştır.
const _ucuncuKosul = [
  (
    "If you ___ (study) harder last month, you would have passed the exam.",
    "had studied",
    ["studied", "have studied", "would study"],
    _ucKosul,
  ),
  (
    "If I ___ (know) about the party last night, I would have come.",
    "had known",
    ["knew", "have known", "would know"],
    _ucKosul,
  ),
  (
    "If it ___ (not / rain) yesterday, we would have gone to the beach.",
    "hadn't rained",
    ["didn't rain", "hasn't rained", "wouldn't rain"],
    _ucKosul,
  ),
  (
    "If she ___ (leave) home five minutes earlier yesterday, she wouldn't have missed the bus.",
    "had left",
    ["left", "has left", "would leave"],
    _ucKosul,
  ),
  (
    "If we ___ (take) a taxi yesterday, we would have arrived on time.",
    "had taken",
    ["took", "have taken", "would take"],
    _ucKosul,
  ),
  (
    "If they ___ (invite) me to the wedding last month, I would have gone.",
    "had invited",
    ["invited", "have invited", "would invite"],
    _ucKosul,
  ),
  (
    "If you had told me the truth, I ___ (not / be) so angry yesterday.",
    "wouldn't have been",
    ["wouldn't be", "won't be", "hadn't been", "wouldn't had been"],
    _ucSonuc,
  ),
  (
    "If he had driven more carefully, he ___ (not / have) the accident last week.",
    "wouldn't have had",
    ["wouldn't have", "won't have", "hadn't had", "wouldn't had"],
    _ucSonuc,
  ),
  (
    "If I had seen you at the concert last night, I ___ (say) hello to you there.",
    "would have said",
    ["would say", "will say", "had said", "would had said"],
    _ucSonuc,
  ),
  (
    "If we had left home earlier, we ___ (catch) the last train last night.",
    "would have caught",
    ["would catch", "will catch", "had caught", "would had caught"],
    _ucSonuc,
  ),
  (
    "If Ali had set his alarm, he ___ (wake up) on time yesterday.",
    "would have woken up",
    ["would wake up", "will wake up", "had woken up", "would had woken up"],
    _ucSonuc,
  ),
  (
    "If you had asked me, I ___ (help) you last week.",
    "would have helped",
    ["would help", "will help", "had helped", "would had helped"],
    _ucSonuc,
  ),
  (
    "If the team had played better, they ___ (win) the match last Saturday.",
    "would have won",
    ["would win", "will win", "had won", "would had won"],
    _ucSonuc,
  ),
  (
    "If I had had more money last year, I ___ (buy) that car then.",
    "would have bought",
    ["would buy", "will buy", "had bought", "would had bought"],
    _ucSonuc,
  ),
  (
    "If she had listened to the doctor, she ___ (recover) more quickly last winter.",
    "would have recovered",
    ["would recover", "will recover", "had recovered", "would had recovered"],
    _ucSonuc,
  ),
  (
    "If you ___ (remind) me yesterday, I wouldn't have forgotten your birthday.",
    "had reminded",
    ["reminded", "have reminded", "would remind"],
    _ucKosul,
  ),
  (
    "If Elif ___ (not / eat) so much cake at the party, she wouldn't have felt sick.",
    "hadn't eaten",
    ["didn't eat", "hasn't eaten", "wouldn't eat"],
    _ucKosul,
  ),
  (
    "If the weather ___ (be) better last weekend, we would have had a picnic.",
    "had been",
    ["was", "has been", "would be"],
    _ucKosul,
  ),
  (
    "If the bus ___ (come) on time yesterday, we wouldn't have been late for school.",
    "had come",
    ["came", "has come", "would come"],
    _ucKosul,
  ),
  (
    "If you had worn a coat, you ___ (not / catch) a cold last week.",
    "wouldn't have caught",
    ["wouldn't catch", "won't catch", "hadn't caught", "wouldn't had caught"],
    _ucSonuc,
  ),
  (
    "If Can had saved his work, he ___ (not / lose) it when the computer crashed.",
    "wouldn't have lost",
    ["wouldn't lose", "won't lose", "hadn't lost", "wouldn't had lost"],
    _ucSonuc,
  ),
  (
    "If we had booked a table, we ___ (not / wait) so long at the restaurant last night.",
    "wouldn't have waited",
    ["wouldn't wait", "won't wait", "hadn't waited", "wouldn't had waited"],
    _ucSonuc,
  ),
  (
    "If my parents ___ (not / help) me last month, I wouldn't have finished the project.",
    "hadn't helped",
    ["didn't help", "haven't helped", "wouldn't help"],
    _ucKosul,
  ),
  (
    "If she had seen the sign, she ___ (stop) the car yesterday.",
    "would have stopped",
    ["would stop", "will stop", "had stopped", "would had stopped"],
    _ucSonuc,
  ),
  (
    "I wish I ___ (have) more free time these days.",
    "had",
    ["have", "will have", "had had"],
    _dilekSimdi,
  ),
  (
    "She wishes she ___ (can) speak French.",
    "could",
    ["can", "could to", "can to"],
    _dilekSimdi,
  ),
  (
    "I wish I ___ (live) closer to the school; it takes me an hour to get there.",
    "lived",
    ["live", "will live", "had lived"],
    _dilekSimdi,
  ),
  (
    "My brother wishes he ___ (be) taller.",
    "were",
    ["is", "will be", "be"],
    _dilekSimdi,
  ),
  (
    "I wish it ___ (not / be) so cold today.",
    "weren't",
    ["isn't", "won't be", "hadn't been"],
    _dilekSimdi,
  ),
  (
    "We wish we ___ (know) the answer to this question now.",
    "knew",
    ["know", "will know", "had known"],
    _dilekSimdi,
  ),
  (
    "I wish I ___ (not / have to) work this weekend.",
    "didn't have to",
    ["don't have to", "won't have to", "hadn't to"],
    _dilekSimdi,
  ),
  (
    "Ece wishes she ___ (have) a sister.",
    "had",
    ["has", "will have", "having"],
    _dilekSimdi,
  ),
  (
    "I wish I ___ (speak) Japanese; then I could talk to my new neighbour.",
    "spoke",
    ["speak", "will speak", "had spoken"],
    _dilekSimdi,
  ),
  (
    "I wish I ___ (not / eat) so much cake last night.",
    "hadn't eaten",
    ["didn't eat", "don't eat", "wouldn't eat"],
    _dilekGecmis,
  ),
  (
    "She wishes she ___ (study) harder for yesterday's exam.",
    "had studied",
    ["studied", "studies", "would study"],
    _dilekGecmis,
  ),
  (
    "We wish we ___ (go) to the concert last Saturday; everyone says it was great.",
    "had gone",
    ["went", "go", "would go"],
    _dilekGecmis,
  ),
  (
    "I wish I ___ (listen) to my teacher's advice last year.",
    "had listened",
    ["listened", "listen", "would listen"],
    _dilekGecmis,
  ),
  (
    "He wishes he ___ (not / sell) his old car last month.",
    "hadn't sold",
    ["didn't sell", "doesn't sell", "wouldn't sell"],
    _dilekGecmis,
  ),
  (
    "I wish you ___ (tell) me about the problem earlier; now it is too late.",
    "had told",
    ["told", "tell", "will tell"],
    _dilekGecmis,
  ),
  (
    "My father wishes he ___ (learn) English when he was young.",
    "had learned",
    ["learned", "learns", "will learn"],
    _dilekGecmis,
  ),
  (
    "They wish they ___ (take) more photos during their holiday last summer.",
    "had taken",
    ["took", "take", "would take"],
    _dilekGecmis,
  ),
  (
    "Selin wishes she ___ (choose) a different university two years ago.",
    "had chosen",
    ["chose", "chooses", "would choose"],
    _dilekGecmis,
  ),
];

final _ucuncuKosulSerpik = _serpistir(_ucuncuKosul, 4);
// Seçkiler ([_sirali] dengeli kipi): üç boşluğun yanıtı ayrıdır ve her
// konuma öteki iki yanıttan ayrı birer çeldirici bulunur.
final _ucuncuKosulSecki = _uygunSecki(
  _ucuncuKosulSerpik,
  lmAileBoyu,
  (x) => _dengeliKurulur([for (final e in x) e.$2], [for (final e in x) e.$3]),
);

final _thirdConditional = lmSirali(
  'en_third_conditional',
  'Third conditional ve wish cümleleri',
  Topic.language,
  Difficulty.hard,
  BloomLevel.uygulama,
  (i) {
    final x = _dizili(_ucuncuKosulSerpik, i, _ucuncuKosulSecki);
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde ayraç '
          'içinde verilen fiillerin, “third conditional” ya da “wish” kalıbına '
          'göre boşluklara gelmesi gereken biçimleri sırasıyla hangi seçenekte '
          'doğru verilmiştir?',
      [for (final e in x) e.$2],
      [for (final e in x) e.$3],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$2}”: ${x[p].$4}'].join('; ')}.',
      i,
      dengeli: true,
    );
  },
  lesson: 'İngilizce',
);

// ────────────────────── 18 · İngilizce–Türkçe sözcük karşılıkları ─────────────

// (İngilizce sözcük, sözlüklerdeki baskın Türkçe karşılığı). Her Türkçe
// karşılık tabloda tek bir İngilizce sözcüğe aittir; birden çok yaygın
// anlamı olan sözcükler (light, match, miss gibi) alınmamıştır.
const _sozcukler = [
  ('library', 'kütüphane'),
  ('bookshop', 'kitapçı'),
  ('kitchen', 'mutfak'),
  ('bridge', 'köprü'),
  ('honest', 'dürüst'),
  ('brave', 'cesur'),
  ('lazy', 'tembel'),
  ('healthy', 'sağlıklı'),
  ('neighbour', 'komşu'),
  ('borrow', 'ödünç almak'),
  ('lend', 'ödünç vermek'),
  ('expensive', 'pahalı'),
  ('cheap', 'ucuz'),
  ('invite', 'davet etmek'),
  ('forget', 'unutmak'),
  ('remember', 'hatırlamak'),
  ('village', 'köy'),
  ('ceiling', 'tavan'),
  ('pillow', 'yastık'),
  ('blanket', 'battaniye'),
  ('knife', 'bıçak'),
  ('spoon', 'kaşık'),
  ('bottle', 'şişe'),
  ('wallet', 'cüzdan'),
  ('umbrella', 'şemsiye'),
  ('sheep', 'koyun'),
  ('bee', 'arı'),
  ('ant', 'karınca'),
  ('cloud', 'bulut'),
  ('earthquake', 'deprem'),
  ('flood', 'sel'),
  ('harvest', 'hasat'),
  ('wheat', 'buğday'),
  ('island', 'ada'),
  ('desert', 'çöl'),
  ('coast', 'kıyı'),
  ('hospital', 'hastane'),
  ('pharmacy', 'eczane'),
  ('nurse', 'hemşire'),
  ('lawyer', 'avukat'),
  ('farmer', 'çiftçi'),
  ('engineer', 'mühendis'),
  ('journey', 'yolculuk'),
  ('suitcase', 'bavul'),
  ('ticket', 'bilet'),
  ('sensitive', 'hassas'),
  ('sensible', 'mantıklı'),
  ('actually', 'aslında'),
  ('careful', 'dikkatli'),
  ('dangerous', 'tehlikeli'),
  ('polite', 'kibar'),
  ('rude', 'kaba'),
  ('shy', 'utangaç'),
  ('narrow', 'dar'),
  ('deep', 'derin'),
  ('repair', 'onarmak'),
  ('explain', 'açıklamak'),
  ('choose', 'seçmek'),
  ('carry', 'taşımak'),
  ('pull', 'çekmek'),
  ('push', 'itmek'),
];

// Sık karıştırılan sözcük çiftleri: önce bunlar çeldirici yapılır.
const _sozcukKarisan = {
  'library': 'bookshop',
  'bookshop': 'library',
  'borrow': 'lend',
  'lend': 'borrow',
  'expensive': 'cheap',
  'cheap': 'expensive',
  'forget': 'remember',
  'remember': 'forget',
  'pillow': 'blanket',
  'blanket': 'pillow',
  'knife': 'spoon',
  'spoon': 'knife',
  'bee': 'ant',
  'ant': 'bee',
  'earthquake': 'flood',
  'flood': 'earthquake',
  'harvest': 'wheat',
  'wheat': 'harvest',
  'island': 'coast',
  'coast': 'island',
  'hospital': 'pharmacy',
  'pharmacy': 'hospital',
  'sensitive': 'sensible',
  'sensible': 'sensitive',
  'polite': 'rude',
  'rude': 'polite',
  'pull': 'push',
  'push': 'pull',
  'careful': 'dangerous',
  'dangerous': 'careful',
};

final _ingilizceSozcukler = [for (final e in _sozcukler) e.$1];
final _turkceKarsiliklar = [for (final e in _sozcukler) e.$2];
final _karsilikSozlugu = {for (final e in _sozcukler) e.$1: e.$2};

final _vocabulary = lmSirali(
  'en_vocabulary',
  'İngilizce–Türkçe sözcük karşılıkları',
  Topic.language,
  Difficulty.easy,
  BloomLevel.hatirlama,
  (i) {
    final x = _bicimSecki(_sozcukler, i, 2);
    final aciklama = '${[for (final e in x) '${e.$1}: ${e.$2}'].join('; ')}.';
    List<String> once(String en) {
      final k = _sozcukKarisan[en];
      return k == null ? const [] : [k];
    }

    if (i.isEven) {
      final dogru = [for (final e in x) e.$2];
      return _sirali(
        '${_uc([for (final e in x) e.$1])}\nNumaralanmış İngilizce '
        'sözcüklerin Türkçe karşılıkları sırasıyla hangi seçenekte doğru '
        'verilmiştir?',
        dogru,
        [
          for (var p = 0; p < 3; p++)
            [
              for (final k in once(x[p].$1)) _karsilikSozlugu[k]!,
              ..._baskaEtiketler(_turkceKarsiliklar, dogru[p], i + 19 * p),
            ],
        ],
        aciklama,
        i,
        tekrarsiz: true,
      );
    }
    final dogru = [for (final e in x) e.$1];
    return _sirali(
      '${_uc([for (final e in x) e.$2])}\nNumaralanmış Türkçe sözcüklerin '
      'İngilizce karşılıkları sırasıyla hangi seçenekte doğru verilmiştir?',
      dogru,
      [
        for (var p = 0; p < 3; p++)
          [
            ...once(x[p].$1),
            ..._baskaEtiketler(_ingilizceSozcukler, dogru[p], i + 19 * p),
          ],
      ],
      aciklama,
      i,
      tekrarsiz: true,
    );
  },
  lesson: 'İngilizce',
);

// ─────────────── 19 · so / such, too / enough, both / either / neither ─────────

// (cümle, boşluğa gelen sözcük, o boşlukta kesin yanlış sözcükler, kural).
// “so” sonrasında “that” bulunmayan ve “very” ile de kurulabilen boşluklar
// bırakılmamıştır; “too” ile “enough” cümleleri “for … to” ya da “to”
// yapısıyla sınırlanmıştır.
const _soSuch = [
  (
    "It was ___ a beautiful day that we went to the beach.",
    "such",
    ["so", "too", "enough"],
    "such + a + sıfat + ad + that",
  ),
  (
    "The coffee was ___ hot that I couldn't drink it.",
    "so",
    ["such", "too", "such a"],
    "so + sıfat + that",
  ),
  (
    "This box is ___ heavy for me to carry.",
    "too",
    ["so", "such", "enough"],
    "too + sıfat + for … to: aşırılık",
  ),
  (
    "My little brother isn't old ___ to go to school.",
    "enough",
    ["too", "so", "such"],
    "sıfat + enough + to: yeterlilik",
  ),
  (
    "___ my brother and my sister are doctors.",
    "Both",
    ["Either", "Neither", "So"],
    "both … and: ikisi de",
  ),
  (
    "You can have ___ tea or coffee.",
    "either",
    ["both", "neither", "so"],
    "either … or: ya … ya",
  ),
  (
    "___ Ali nor Ayşe came to the party.",
    "Neither",
    ["Either", "Both", "So"],
    "neither … nor: ne … ne",
  ),
  (
    "They were ___ good friends that they shared everything.",
    "such",
    ["so", "too", "enough"],
    "such + sıfat + çoğul ad + that",
  ),
  (
    "The film was ___ boring that I fell asleep.",
    "so",
    ["such", "too", "such a"],
    "so + sıfat + that",
  ),
  (
    "He is ___ young to drive a car.",
    "too",
    ["so", "enough", "such"],
    "too + sıfat + to: aşırılık",
  ),
  (
    "We don't have ___ chairs for all the guests.",
    "enough",
    ["too", "so", "very"],
    "enough + ad: yeterlilik",
  ),
  (
    "I have two cousins, but ___ of them lives in Türkiye.",
    "neither",
    ["either", "both", "all"],
    "iki kişiden hiçbiri: neither of + tekil fiil",
  ),
  (
    "There was ___ much traffic that we were late for the meeting.",
    "so",
    ["such", "too", "enough"],
    "so much + ad + that",
  ),
  (
    "It was ___ an interesting book that I read it in one day.",
    "such",
    ["so", "too", "enough"],
    "such + an + sıfat + ad + that",
  ),
  (
    "The water isn't warm ___ for swimming.",
    "enough",
    ["too", "so", "such"],
    "sıfat + enough + for: yeterlilik",
  ),
  (
    "These shoes are ___ small for me to wear.",
    "too",
    ["so", "enough", "such"],
    "too + sıfat + for … to: aşırılık",
  ),
  (
    "I like ___ cats and dogs.",
    "both",
    ["either", "neither", "so"],
    "both … and: ikisi de",
  ),
  (
    "You can pay ___ by cash or by credit card.",
    "either",
    ["both", "neither", "so"],
    "either … or: ya … ya",
  ),
  (
    "___ the bus nor the train was on time this morning.",
    "Neither",
    ["Either", "Both", "So"],
    "neither … nor: ne … ne",
  ),
  (
    "She spoke ___ quickly that nobody understood her.",
    "so",
    ["such", "too", "enough"],
    "so + zarf + that",
  ),
  (
    "It was ___ cold weather that the schools were closed.",
    "such",
    ["so", "too", "enough"],
    "such + sıfat + sayılamayan ad + that",
  ),
  (
    "Is this bag big ___ for all your books?",
    "enough",
    ["too", "so", "such"],
    "sıfat + enough + for: yeterlilik",
  ),
  (
    "The tea is ___ hot to drink right now.",
    "too",
    ["so", "enough", "such"],
    "too + sıfat + to: aşırılık",
  ),
  (
    "Do you think he is strong ___ to lift that box?",
    "enough",
    ["too", "so", "such"],
    "sıfat + enough + to: yeterlilik",
  ),
  (
    "My grandparents live in a village; ___ of them has a mobile phone.",
    "neither",
    ["either", "both", "all"],
    "iki kişiden hiçbiri: neither of + tekil fiil",
  ),
  (
    "“I don't like horror films.” “I don't like them ___.”",
    "either",
    ["neither", "too", "so"],
    "olumsuz cümleye katılmada cümle sonunda either",
  ),
  (
    "“I can't swim.” “___ can I.”",
    "Neither",
    ["Either", "So", "Too"],
    "olumsuz cümleye katılma: Neither + yardımcı fiil + özne",
  ),
  (
    "“I love pizza.” “___ do I.”",
    "So",
    ["Neither", "Either", "Such"],
    "olumlu cümleye katılma: So + yardımcı fiil + özne",
  ),
  (
    "He had ___ a bad cold that he couldn't go to work.",
    "such",
    ["so", "too", "enough"],
    "such + a + sıfat + ad + that",
  ),
  (
    "The music was ___ loud that the neighbours complained.",
    "so",
    ["such", "too", "such a"],
    "so + sıfat + that",
  ),
  (
    "There are ___ many people here that I can't find my friends.",
    "so",
    ["such", "too", "enough"],
    "so many + ad + that",
  ),
  (
    "This exercise is ___ difficult for beginners to understand.",
    "too",
    ["so", "enough", "such"],
    "too + sıfat + for … to: aşırılık",
  ),
  (
    "I haven't got ___ money to buy a new phone.",
    "enough",
    ["too", "so", "very"],
    "enough + ad + to: yeterlilik",
  ),
  (
    "___ answers are correct, so you can choose either one.",
    "Both",
    ["Either", "Neither", "So"],
    "çoğul adla “ikisi de”: both",
  ),
  (
    "We can meet on ___ Saturday or Sunday; I am free on both days.",
    "either",
    ["both", "neither", "so"],
    "either … or: ya … ya",
  ),
  (
    "She was ___ tired to finish her homework.",
    "too",
    ["so", "enough", "such"],
    "too + sıfat + to: aşırılık",
  ),
  (
    "It was ___ a long journey that the children fell asleep in the car.",
    "such",
    ["so", "too", "enough"],
    "such + a + sıfat + ad + that",
  ),
  (
    "The room was ___ dark that I couldn't see anything.",
    "so",
    ["such", "too", "such a"],
    "so + sıfat + that",
  ),
  (
    "Are you tall ___ to reach the top shelf?",
    "enough",
    ["too", "so", "such"],
    "sıfat + enough + to: yeterlilik",
  ),
  (
    "___ my mother nor my father drinks coffee.",
    "Neither",
    ["Either", "Both", "So"],
    "neither … nor: ne … ne",
  ),
  (
    "The exam was ___ easy that everyone passed.",
    "so",
    ["such", "too", "such an"],
    "so + sıfat + that",
  ),
  (
    "They are ___ kind people that everyone loves them.",
    "such",
    ["so", "too", "enough"],
    "such + sıfat + çoğul ad + that",
  ),
  (
    "“I am not hungry.” “___ am I.”",
    "Neither",
    ["Either", "So", "Too"],
    "olumsuz cümleye katılma: Neither + yardımcı fiil + özne",
  ),
];

// Seçkiler ([_sirali] dengeli kipi): üç boşluğun yanıtı ayrıdır ve her
// konuma öteki iki yanıttan ayrı birer çeldirici bulunur.
final _soSuchSecki = _uygunSecki(
  _soSuch,
  lmAileBoyu,
  (x) => _dengeliKurulur([for (final e in x) e.$2], [for (final e in x) e.$3]),
);

final _soSuchAile = lmSirali(
  'en_so_such',
  'so/such, too/enough ve both/either/neither',
  Topic.language,
  Difficulty.medium,
  BloomLevel.uygulama,
  (i) {
    final x = _dizili(_soSuch, i, _soSuchSecki);
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde boş '
          'bırakılan yerlere anlam ve yapı bakımından uygun düşen sözcükler '
          'sırasıyla hangi seçenekte doğru verilmiştir?',
      [for (final e in x) e.$2],
      [for (final e in x) e.$3],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$2}”: ${x[p].$4}'].join('; ')}.',
      i,
      dengeli: true,
    );
  },
  lesson: 'İngilizce',
);

// ───────────────── 20 · Sıfat ve fiillerden sonra gelen edatlar ───────────────

// (cümle, boşluğa gelen edat, o boşlukta kesin yanlış edatlar, kalıp).
// İki edatla da kullanılabilen kalıplar (angry with/at, different from/to,
// dream of/about gibi) alınmamış; bir kalıbın ikinci, daha az yaygın edatı
// (complain of, protect against gibi) çeldirici yapılmamıştır.
const _edatKaliplari = [
  (
    "My sister is very interested ___ modern art.",
    "in",
    ["on", "at", "for"],
    "interested in",
  ),
  ("Emre is good ___ maths and physics.", "at", ["on", "for", "of"], "good at"),
  (
    "Many people are afraid ___ spiders.",
    "of",
    ["from", "with", "at"],
    "afraid of",
  ),
  (
    "Whether we go to the beach depends ___ the weather.",
    "on",
    ["of", "from", "to"],
    "depend on",
  ),
  (
    "I like listening ___ music while I study.",
    "to",
    ["at", "for", "on"],
    "listen to",
  ),
  (
    "Her parents are very proud ___ her success.",
    "of",
    ["with", "about", "at"],
    "proud of",
  ),
  (
    "Türkiye is famous ___ its delicious food.",
    "for",
    ["of", "with", "about"],
    "famous for",
  ),
  (
    "My aunt is married ___ a doctor.",
    "to",
    ["with", "for", "at"],
    "married to",
  ),
  (
    "Who is responsible ___ this mess?",
    "for",
    ["of", "about", "with"],
    "responsible for",
  ),
  (
    "The students are worried ___ the exam results.",
    "about",
    ["of", "at", "on"],
    "worried about",
  ),
  (
    "I am tired ___ eating the same food every day.",
    "of",
    ["at", "on", "about"],
    "tired of",
  ),
  ("The glass is full ___ water.", "of", ["with", "from", "at"], "full of"),
  (
    "My brother is keen ___ playing computer games.",
    "on",
    ["in", "at", "of"],
    "keen on",
  ),
  (
    "My grandmother is very fond ___ her cat.",
    "of",
    ["on", "with", "at"],
    "fond of",
  ),
  (
    "Your phone is similar ___ mine.",
    "to",
    ["with", "as", "from"],
    "similar to",
  ),
  (
    "I am really bad ___ remembering names.",
    "at",
    ["in", "on", "for"],
    "bad at",
  ),
  (
    "The children are excited ___ the school trip.",
    "about",
    ["on", "at", "of"],
    "excited about",
  ),
  ("Please be kind ___ animals.", "to", ["for", "at", "on"], "kind to"),
  (
    "Does this umbrella belong ___ you?",
    "to",
    ["for", "with", "at"],
    "belong to",
  ),
  ("Do you believe ___ ghosts?", "in", ["on", "at", "to"], "believe in"),
  (
    "We waited ___ the bus for half an hour.",
    "for",
    ["to", "at", "with"],
    "wait for",
  ),
  (
    "I completely agree ___ you.",
    "with",
    ["to", "on", "for"],
    "agree with (birine katılmak)",
  ),
  ("He apologised ___ being late.", "for", ["of", "to", "on"], "apologise for"),
  (
    "She succeeded ___ passing all her exams.",
    "in",
    ["on", "at", "to"],
    "succeed in",
  ),
  (
    "My father insisted ___ paying for dinner.",
    "on",
    ["in", "at", "for"],
    "insist on",
  ),
  (
    "It is hard to concentrate ___ my homework when it is noisy.",
    "on",
    ["in", "at", "to"],
    "concentrate on",
  ),
  (
    "How much did you pay ___ these shoes?",
    "for",
    ["to", "on", "at"],
    "pay for",
  ),
  (
    "The neighbours complained ___ the noise.",
    "about",
    ["on", "for", "at"],
    "complain about",
  ),
  (
    "It is rude to laugh ___ people when they make mistakes.",
    "at",
    ["on", "to", "for"],
    "laugh at",
  ),
  (
    "My grandfather suffers ___ back pain.",
    "from",
    ["of", "at", "on"],
    "suffer from",
  ),
  (
    "A football team consists ___ eleven players.",
    "of",
    ["from", "with", "by"],
    "consist of",
  ),
  (
    "You can always rely ___ your best friend.",
    "on",
    ["to", "at", "in"],
    "rely on",
  ),
  (
    "Are you aware ___ the risks of smoking?",
    "of",
    ["on", "with", "for"],
    "aware of",
  ),
  (
    "He felt ashamed ___ his behaviour at the party.",
    "of",
    ["with", "on", "at"],
    "ashamed of",
  ),
  (
    "My little sister is jealous ___ her new baby brother.",
    "of",
    ["on", "with", "at"],
    "jealous of",
  ),
  (
    "The teacher was pleased ___ our project.",
    "with",
    ["of", "on", "to"],
    "pleased with",
  ),
  (
    "The streets were crowded ___ tourists.",
    "with",
    ["of", "on", "at"],
    "crowded with",
  ),
  (
    "We were late ___ the meeting because of the traffic.",
    "for",
    ["at", "on", "of"],
    "late for",
  ),
  (
    "I was nervous ___ my first job interview.",
    "about",
    ["on", "at", "to"],
    "nervous about",
  ),
  (
    "Can you translate this sentence ___ English?",
    "into",
    ["at", "on", "with"],
    "translate into",
  ),
  (
    "Thank you for taking care ___ my plants while I was away.",
    "of",
    ["for", "on", "with"],
    "take care of",
  ),
  (
    "Many students took part ___ the competition.",
    "in",
    ["on", "at", "to"],
    "take part in",
  ),
  (
    "This cream will protect your skin ___ the sun.",
    "from",
    ["of", "to", "at"],
    "protect from",
  ),
  (
    "She is very polite ___ everyone she meets.",
    "to",
    ["for", "at", "on"],
    "polite to",
  ),
  ("My dog is scared ___ thunder.", "of", ["from", "at", "on"], "scared of"),
];

// Seçkiler ([_sirali] dengeli kipi): üç boşluğun yanıtı ayrıdır ve her
// konuma öteki iki yanıttan ayrı birer çeldirici bulunur.
final _edatSecki = _uygunSecki(
  _edatKaliplari,
  lmAileBoyu,
  (x) => _dengeliKurulur([for (final e in x) e.$2], [for (final e in x) e.$3]),
);

final _dependentPrep = lmSirali(
  'en_dependent_prep',
  'Sıfat ve fiillerden sonra gelen edatlar',
  Topic.language,
  Difficulty.medium,
  BloomLevel.hatirlama,
  (i) {
    final x = _dizili(_edatKaliplari, i, _edatSecki);
    return _sirali(
      '${_uc([for (final e in x) e.$1])}\nNumaralanmış cümlelerde boş '
          'bırakılan yerlere gelmesi gereken edatlar (prepositions) sırasıyla '
          'hangi seçenekte doğru verilmiştir?',
      [for (final e in x) e.$2],
      [for (final e in x) e.$3],
      '${[for (var p = 0; p < 3; p++) '${_rakam[p]}. cümlede “${x[p].$2}”: kalıp “${x[p].$4}”'].join('; ')}.',
      i,
      dengeli: true,
    );
  },
  lesson: 'İngilizce',
);

final lmDilEk = <AdvancedFamily>[
  _deyim,
  _atasozu,
  _esZit,
  _noktalama,
  _fiilimsi,
  _cati,
  _tamlama,
  _kokEk,
  _heceOlcu,
  _nazimAkim,
  _pastContinuous,
  _usedToAile,
  _relativeAile,
  _reportedAile,
  _gerundAile,
  _questionTag,
  _thirdConditional,
  _vocabulary,
  _soSuchAile,
  _dependentPrep,
];
