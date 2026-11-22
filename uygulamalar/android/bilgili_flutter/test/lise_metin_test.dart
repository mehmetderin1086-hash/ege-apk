import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/ortak.dart';
import 'package:bilgili_flutter/state/arena_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lise metin bankası 400 aileden 2.000.000 soru sunar', () {
    expect(liseMetinFamilies, hasLength(400));
    expect(liseMetinFamilies.map((f) => f.key).toSet(), hasLength(400));
    var toplam = 0;
    for (final f in liseMetinFamilies) {
      expect(f.key, startsWith('lm_'));
      expect(f.level, StudyLevel.lise, reason: f.key);
      expect(f.visualKind, isNull, reason: f.key);
      expect(f.activityKind, isNull, reason: f.key);
      expect(f.creation, isNull, reason: f.key);
      expect(f.multiSelect, isNull, reason: f.key);
      expect(f.count, lmAileBoyu, reason: f.key);
      toplam += f.count;
      for (final i in [0, f.count ~/ 2, f.count - 1]) {
        final q = f.questionAt(i);
        expect(q.studyLevel, 'Lise');
        expect(q.visual, isNull);
        expect(q.activity, isNull);
        expect(q.sourceModel, lmKaynak);
        expect(q.matchesFormat(QuestionFormat.text), isTrue, reason: q.id);
        expect(AdvancedCatalog.questionById(q.id)?.text, q.text);
      }
    }
    expect(toplam, 2000000);
    final eski = AdvancedCatalog.families
        .where((f) => !f.key.startsWith('lm_'))
        .fold<int>(0, (n, f) => n + f.count);
    expect(eski, 1270439);
    expect(AdvancedCatalog.all.length, 3270439);
    expect(AdvancedCatalog.select(level: StudyLevel.lise).length, 2592093);
  });

  test('lise metin paketi oynanabilir ve yalnız lise metin sorusu içerir', () {
    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);
    final paket = ctrl.offlinePacks.singleWhere(
      (p) => p.id == 'builtin_sb_ak38_lise_metin',
    );
    expect(paket.questions.length, greaterThanOrEqualTo(2000000));
    ctrl.startPackRound(paket, maxQuestions: 12);
    final sorular = ctrl.activeRound!.questions;
    expect(sorular.map((q) => q.id).toSet(), hasLength(12));
    for (final q in sorular) {
      expect(q.studyLevel, 'Lise', reason: q.id);
      expect(q.visual, isNull, reason: q.id);
      expect(q.activity, isNull, reason: q.id);
    }
    ctrl.exitRound();
  });
}
