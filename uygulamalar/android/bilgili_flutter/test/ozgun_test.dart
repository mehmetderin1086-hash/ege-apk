import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:bilgili_flutter/data/advanced/common.dart';
import 'package:bilgili_flutter/data/advanced/ozgun/ozgun.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('özgün banka: her soru dört ayrı seçenekli, kökler ve kimlikler tekil', () {
    final kokler = <String>{};
    final kimlikler = <String>{};
    var toplam = 0;
    for (final f in ozgunAileler) {
      expect(f.level, StudyLevel.lise, reason: f.key);
      expect(f.key, startsWith('oz_'));
      for (var i = 0; i < f.count; i++) {
        final item = f.build(i);
        expect(item.wrong, hasLength(3), reason: '${f.key} $i');
        final secenekler = {item.correct, ...item.wrong}.map((s) => s.toLowerCase()).toSet();
        expect(secenekler, hasLength(4), reason: '${f.key} $i');
        expect(item.explanation.trim(), isNotEmpty);
        expect(kokler.add(item.prompt.trim().toLowerCase()), isTrue, reason: item.prompt);
        final q = f.questionAt(i);
        expect(kimlikler.add(q.id), isTrue);
        expect(q.options, hasLength(4));
        if (i % 97 == 0) expect(AdvancedCatalog.questionById(q.id)?.text, q.text);
        toplam++;
      }
    }
    expect(toplam, AdvancedCatalog.ozgun.length);
    expect(toplam, greaterThan(30000));
  });
}
