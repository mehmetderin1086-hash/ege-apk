import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/ortak.dart';
import 'package:bilgili_flutter/data/advanced/secki.g.dart';
import 'package:bilgili_flutter/state/arena_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seçki yalnız lise çoktan seçmeli ailelerden ayrışan vakaları sunar', () {
    expect(liseMetinFamilies, hasLength(400));
    final kaynak = {for (final f in AdvancedCatalog.kaynakAileler) f.key: f};
    var toplam = 0;
    for (final f in AdvancedCatalog.families.where((f) => seckiler.containsKey(f.key))) {
      expect(f.level, StudyLevel.lise, reason: f.key);
      expect(f.activityKind, isNull, reason: f.key);
      expect(f.creation, isNull, reason: f.key);
      expect(f.multiSelect, isNull, reason: f.key);
      final secki = seckiler[f.key]!;
      expect(f.count, secki.length);
      expect(secki.length, inInclusiveRange(1, 50), reason: f.key);
      expect(secki.toSet(), hasLength(secki.length), reason: f.key);
      toplam += f.count;
      for (var j = 0; j < f.count; j++) {
        final q = f.questionAt(j);
        expect(q.id, 'ak38_${f.key}_${secki[j]}');
        expect(q.text, kaynak[f.key]!.build(secki[j]).prompt);
        expect(AdvancedCatalog.questionById(q.id)?.text, q.text);
      }
    }
    expect(toplam, 8391);
    expect(
      AdvancedCatalog.all.length,
      8391 + AdvancedCatalog.ozgun.length + AdvancedCatalog.studio10k.length,
    );
    final metin = AdvancedCatalog.families.where((f) => f.sourceLabel == lmKaynak);
    expect(metin.length, greaterThan(350));
  });

  test('lise metin paketi oynanabilir ve yalnız lise metin sorusu içerir', () {
    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);
    final paket = ctrl.offlinePacks.singleWhere(
      (p) => p.id == 'builtin_sb_ak38_lise_metin',
    );
    expect(paket.questions.length, greaterThan(5000));
    ctrl.startPackRound(paket, maxQuestions: 12);
    final sorular = ctrl.activeRound!.questions;
    expect(sorular.map((q) => q.id).toSet(), hasLength(12));
    for (final q in sorular) {
      expect(q.studyLevel, 'Lise', reason: q.id);
      expect(q.visual, isNull, reason: q.id);
      expect(q.activity, isNull, reason: q.id);
      expect(q.options, hasLength(4), reason: q.id);
    }
    ctrl.exitRound();
  });
}
