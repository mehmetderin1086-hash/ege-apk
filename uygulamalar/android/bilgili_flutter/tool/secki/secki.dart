// Lise ailelerinden birbirinden belirgin biçimde ayrışan vakaları seçer.
// Her vakanın kökü sözcük kümesine çevrilir (sayılar atılır). En uzak nokta
// yöntemiyle, seçilenlere en uzak vaka sırayla eklenir. Seçilenlere uzaklığı
// eşiğin altında kalan vaka (yalnız sayısı ya da birkaç sözcüğü değişen kopya)
// alınmaz.
import 'package:bilgili_flutter/data/advanced/common.dart';

final _sozcuk = RegExp(r'[a-zçğıöşüâîû]+', unicode: true);

Set<int> sozcukKumesi(String metin, Map<String, int> sozluk) {
  final kume = <int>{};
  for (final m in _sozcuk.allMatches(metin.toLowerCase())) {
    final w = m.group(0)!;
    if (w.length < 2) continue;
    kume.add(sozluk.putIfAbsent(w, () => sozluk.length));
  }
  return kume;
}

double uzaklik(Set<int> a, Set<int> b) {
  if (a.isEmpty && b.isEmpty) return 0;
  var ortak = 0;
  final (k, b2) = a.length <= b.length ? (a, b) : (b, a);
  for (final x in k) {
    if (b2.contains(x)) ortak++;
  }
  return 1 - ortak / (a.length + b.length - ortak);
}

/// Seçim sırası ve her seçimin seçilenlere en küçük uzaklığı.
List<(int, double)> enUzakSira(AdvancedFamily f, int ust) {
  final sozluk = <String, int>{};
  final kumeler = <Set<int>>[];
  final iskeletler = <String>[];
  for (var i = 0; i < f.count; i++) {
    final r = f.build(i);
    kumeler.add(sozcukKumesi(r.prompt, sozluk));
    iskeletler.add(r.prompt.replaceAll(RegExp(r'\d+'), '#'));
  }
  final enYakin = List<double>.filled(f.count, double.infinity);
  final alinan = <String>{};
  final sira = <(int, double)>[];
  var aday = 0;
  var adayUzaklik = 1.0;
  while (sira.length < ust) {
    sira.add((aday, adayUzaklik));
    alinan.add(iskeletler[aday]);
    var enIyi = -1;
    var enIyiU = -1.0;
    for (var i = 0; i < f.count; i++) {
      if (enYakin[i] == 0) continue;
      final u = alinan.contains(iskeletler[i]) ? 0.0 : uzaklik(kumeler[i], kumeler[aday]);
      if (u < enYakin[i]) enYakin[i] = u;
      if (enYakin[i] > enIyiU) {
        enIyiU = enYakin[i];
        enIyi = i;
      }
    }
    if (enIyi < 0 || enIyiU <= 0) break;
    aday = enIyi;
    adayUzaklik = enIyiU;
  }
  return sira;
}
