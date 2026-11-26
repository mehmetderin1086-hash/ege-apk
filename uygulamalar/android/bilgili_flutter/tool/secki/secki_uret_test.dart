// lib/data/advanced/secki.g.dart dosyasını üretir: her lise çoktan seçmeli
// aileden birbirine sözcük kümesi bakımından en az %20 uzak en çok 50 vaka,
// ardından başka ailelerdeki seçilmiş sorulara benzeyen (uzaklık < 0,2) vakalar
// da elenir.
//   flutter test --no-pub tool/secki/secki_uret_test.dart
import 'dart:io';

import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'secki.dart';

const esik = 0.2;
const ust = 50;

void main() {
  test('seçki üret', () {
    // İncelemede kusurlu bulunan sorular (tool/secki/elenen.txt, satır başına
    // bir soru kimliği) seçkiye alınmaz.
    final elenenDosya = File('tool/secki/elenen.txt');
    final disari = elenenDosya.existsSync()
        ? elenenDosya.readAsLinesSync().map((l) => l.split('#').first.trim()).where((l) => l.isNotEmpty).toSet()
        : <String>{};
    final sozluk = <String, int>{};
    final secilen = <String, List<int>>{};
    final tum = <(String, int, Set<int>, String)>[]; // aile, vaka, kume, kok
    for (final f in AdvancedCatalog.kaynakAileler) {
      if (!AdvancedCatalog.cokSecmeliLise(f)) continue;
      final sira = enUzakSira(f, ust).where((e) => e.$2 >= esik);
      for (final (i, _) in sira) {
        if (disari.contains('ak38_${f.key}_$i')) continue;
        final kok = f.build(i).prompt;
        tum.add((f.key, i, sozcukKumesi(kok, sozluk), kok));
      }
    }
    final kalan = <(String, int, Set<int>, String)>[];
    final gorulen = <String>{};
    var elenen = 0;
    for (final a in tum) {
      final duz = a.$4.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      var benzer = !gorulen.add(duz);
      if (!benzer) {
        for (final b in kalan) {
          if (b.$1 != a.$1 && uzaklik(a.$3, b.$3) < esik) {
            benzer = true;
            break;
          }
        }
      }
      if (benzer) {
        elenen++;
        continue;
      }
      kalan.add(a);
      (secilen[a.$1] ??= []).add(a.$2);
    }
    final b = StringBuffer()
      ..writeln('// Üretilen dosya: tool/secki/secki_uret_test.dart. Elle düzenlemeyin.')
      ..writeln('// Her lise çoktan seçmeli aileden birbirinden belirgin biçimde ayrışan')
      ..writeln('// vakaların özgün numaraları.')
      ..writeln('const seckiler = <String, List<int>>{');
    for (final e in secilen.entries) {
      b.writeln("  '${e.key}': [${e.value.join(', ')}],");
    }
    b.writeln('};');
    File('lib/data/advanced/secki.g.dart').writeAsStringSync(b.toString());
    // ignore: avoid_print
    print('aile ${secilen.length}, soru ${kalan.length}, aileler arası benzer diye elenen $elenen');
  }, timeout: const Timeout(Duration(minutes: 90)));
}
