import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:bilgili_flutter/data/advanced/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'secki.dart';

void main() {
  test('eşik ölçümü', () {
    const esikler = [0.1, 0.15, 0.2, 0.25, 0.3, 0.4];
    final toplam = List.filled(esikler.length, 0);
    final dagilim = <String>[];
    for (final f in AdvancedCatalog.families) {
      if (f.level != StudyLevel.lise || f.activityKind != null || f.creation != null || f.multiSelect != null) continue;
      final s = enUzakSira(f, 50);
      for (var k = 0; k < esikler.length; k++) {
        toplam[k] += s.where((e) => e.$2 >= esikler[k]).length;
      }
      dagilim.add('${f.key} ${s.where((e) => e.$2 >= 0.2).length}');
    }
    // ignore: avoid_print
    print('TOPLAM ${[for (var k = 0; k < esikler.length; k++) '${esikler[k]}:${toplam[k]}'].join(' ')}');
    // ignore: avoid_print
    print(dagilim.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 60)));
}
