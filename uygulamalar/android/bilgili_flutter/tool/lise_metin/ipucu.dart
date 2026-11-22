// Bilgisiz bir öğrencinin yalnız seçeneklerin biçimine bakarak anahtarı
// bulup bulamayacağını ölçer. Her vaka için şu kestirimler denenir; eşitlikte
// seçim eşit olasılıkla paylaştırılır, rastgele seçimin başarısı %25'tir:
//
//   küme   — öğe kümelerinde çoğunluğa en yakın seçenek ("I ve III" gibi);
//   sıra   — aynı uzunluktaki dizilerde konum konum çoğunluğa en yakın seçenek;
//   sözcük — sözcük kümesi bakımından ötekilere en çok benzeyen seçenek;
//   uzun   — en uzun seçenek;
//   sayı   — sayısal seçeneklerde anahtarın en sık bulunduğu sıra (en küçük,
//            ikinci, üçüncü, en büyük).
//
//   flutter test --no-pub tool/lise_metin/ipucu_test.dart
import 'dart:math';

import 'package:bilgili_flutter/data/advanced/lise_metin/ortak.dart';
import 'package:flutter_test/flutter_test.dart';

final _ayrac = RegExp(r', | ve | – | - | → |; | · ');
final _sozcuk = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _sayi = RegExp(r'^([−-]?\d+(?:,\d+)?)(?:/(\d+))?\s*(.*)$');

List<String> _ogeler(String s) => s
    .replaceFirst(RegExp(r'^Yalnız '), '')
    .split(_ayrac)
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

/// Anahtarın (0. seçenek) en yüksek puanı alma payı.
double _pay(List<double> puan) {
  final enb = puan.reduce(max);
  final kac = puan.where((p) => (p - enb).abs() < 1e-9).length;
  return (puan[0] - enb).abs() < 1e-9 ? 1 / kac : 0;
}

double? _deger(String s) {
  final m = _sayi.firstMatch(s.trim());
  if (m == null) return null;
  final x = double.parse(m.group(1)!.replaceAll('−', '-').replaceAll(',', '.'));
  final d = m.group(2) == null ? 1.0 : double.parse(m.group(2)!);
  return d == 0 ? null : x / d;
}

String? _birim(String s) => _sayi.firstMatch(s.trim())?.group(3);

class IpucuSonuc {
  IpucuSonuc(this.key);
  final String key;
  double kume = 0, sira = 0, sozcuk = 0, uzun = 0;
  final sayiSira = List<int>.filled(4, 0);
  int n = 0, sayisal = 0;

  /// Seçenekler sayısalken anahtarın en sık bulunduğu sırayı, değilse rastgele
  /// seçen öğrencinin başarısı.
  double get sayi => (sayiSira.reduce(max) + 0.25 * (n - sayisal)) / n;
  double get enKotu =>
      [kume / n, sira / n, sozcuk / n, uzun / n, sayi].reduce(max);
  String satir() =>
      '$key  küme ${_y(kume / n)}  sıra ${_y(sira / n)}  '
      'sözcük ${_y(sozcuk / n)}  uzun ${_y(uzun / n)}  sayı ${_y(sayi)}'
      '${sayisal == 0 ? '' : ' (sıralar ${sayiSira.join('/')})'}';
  static String _y(double x) => '${(100 * x).round()}'.padLeft(3);
}

IpucuSonuc ipucuOlc(AdvancedFamily f) {
  final s = IpucuSonuc(f.key);
  for (var i = 0; i < f.count; i++) {
    final r = f.build(i);
    final se = [r.correct, ...r.wrong];
    s.n++;
    // küme
    final kumeler = se.map((x) => _ogeler(x).toSet()).toList();
    final evren = kumeler.expand((k) => k).toSet();
    s.kume += _pay([
      for (var a = 0; a < 4; a++)
        evren.fold<double>(0, (t, e) {
          var u = 0;
          for (var b = 0; b < 4; b++) {
            if (b != a && kumeler[b].contains(e) == kumeler[a].contains(e)) u++;
          }
          return t + u;
        }),
    ]);
    // sıra
    final diziler = se.map(_ogeler).toList();
    final boy = diziler.first.length;
    if (boy > 1 && diziler.every((d) => d.length == boy)) {
      s.sira += _pay([
        for (var a = 0; a < 4; a++)
          [
            for (var b = 0; b < 4; b++)
              if (b != a)
                [for (var p = 0; p < boy; p++) diziler[a][p] == diziler[b][p]]
                    .where((x) => x)
                    .length,
          ].fold<int>(0, (t, x) => t + x).toDouble(),
      ]);
    } else {
      s.sira += 0.25;
    }
    // sözcük
    final sozler = se
        .map(
          (x) =>
              x.toLowerCase().split(_sozcuk).where((w) => w.isNotEmpty).toSet(),
        )
        .toList();
    s.sozcuk += _pay([
      for (var a = 0; a < 4; a++)
        [
          for (var b = 0; b < 4; b++)
            if (b != a)
              sozler[a].union(sozler[b]).isEmpty
                  ? 0.0
                  : sozler[a].intersection(sozler[b]).length /
                        sozler[a].union(sozler[b]).length,
        ].fold<double>(0, (t, x) => t + x),
    ]);
    // uzun
    s.uzun += _pay([for (final x in se) x.length.toDouble()]);
    // sayı
    final degerler = se.map(_deger).toList();
    final birimler = se.map(_birim).toSet();
    if (degerler.every((d) => d != null) && birimler.length == 1) {
      final k = degerler[0]!;
      final sira = degerler.where((d) => d! < k).length;
      s.sayiSira[sira]++;
      s.sayisal++;
    }
  }
  return s;
}

/// Hedef: hiçbir kestirim anahtarı vakaların %40'ından fazlasında bulamaz.
const ipucuHedef = 0.40;

/// [hepsi] verilirse aileler dosyadaki sırayla ve tamamı yazılır; aksi hâlde
/// en kötü durumdan başlayarak sınırı aşanlar (en az 25 satır) yazılır.
/// Sınırı aşan satırlar "!" ile başlar.
void liseMetinIpucu(
  String alan,
  List<AdvancedFamily> aileler, {
  double esik = ipucuHedef,
  bool hepsi = false,
}) {
  test('$alan: seçenek biçiminden ipucu taraması', () {
    final sonuclar = [for (final f in aileler) ipucuOlc(f)];
    final sinir = (100 * esik).round();
    final asan = {
      for (final s in sonuclar)
        if ((100 * s.enKotu).round() > sinir) s.key,
    };
    final yazilacak = hepsi
        ? sonuclar
        : ([...sonuclar]..sort((a, b) => b.enKotu.compareTo(a.enKotu))).take(
            max(asan.length, 25),
          );
    // ignore: avoid_print
    print(
      '$alan: ${aileler.length} aile; en az bir kestirimde %$sinir sınırını '
      'aşan ${asan.length} aile.',
    );
    for (final s in yazilacak) {
      // ignore: avoid_print
      print('${asan.contains(s.key) ? '!' : ' '} ${s.satir()}');
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
