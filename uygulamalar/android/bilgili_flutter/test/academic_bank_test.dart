import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:bilgili_flutter/data/advanced/common.dart';
import 'package:bilgili_flutter/state/arena_controller.dart';
import 'package:bilgili_flutter/state/question_browser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'catalog families are addressable, and level packs cover the full bank',
    () {
      final ctrl = ArenaController.inMemoryForTest();
      addTearDown(ctrl.dispose);
      final levels = ctrl.offlinePacks.where(
        (p) =>
            p.id == 'builtin_sb_ak38_lise' ||
            p.id == 'builtin_sb_ak38_universite',
      );
      expect(levels.length, 1);
      final blooms = ctrl.offlinePacks.where(
        (p) => p.id.startsWith('builtin_sb_ak38_bloom_'),
      );
      expect(blooms.length, greaterThanOrEqualTo(5));
      expect(
        blooms.fold<int>(0, (size, p) => size + p.questions.length),
        AdvancedCatalog.all.length,
      );
      for (final pack in blooms) {
        final bloom = BloomLevel.values.singleWhere((b) => pack.id.endsWith('_${b.name}'));
        expect(pack.questions.first.bloom, bloom);
      }
      expect(
        levels.fold<int>(0, (count, p) => count + p.questions.length),
        AdvancedCatalog.all.length,
      );
      expect(ctrl.totalPoolCount, ctrl.personalQuestions.length + AdvancedCatalog.all.length);
      expect(
        ctrl.allQuestions[ctrl.personalQuestions.length].id,
        AdvancedCatalog.all.first.id,
      );
      for (final f in AdvancedCatalog.families) {
        expect(AdvancedCatalog.hasId(f.questionAt(0).id), isTrue);
        expect(AdvancedCatalog.hasId(f.questionAt(f.count - 1).id), isTrue);
        if (f.ozgunSira == null) {
          expect(AdvancedCatalog.hasId('ak38_${f.key}_${f.count}'), isFalse);
          continue;
        }
        final secki = f.ozgunSira!.toSet();
        var disarida = 0;
        while (secki.contains(disarida)) {
          disarida++;
        }
        expect(AdvancedCatalog.hasId('ak38_${f.key}_$disarida'), isFalse);
      }
      for (final pack in levels) {
        ctrl.startPackRound(pack, maxQuestions: 6);
        final qs = ctrl.activeRound!.questions;
        expect(qs.map((q) => q.id).toSet(), hasLength(6));
        expect(qs.every((q) => AdvancedCatalog.hasId(q.id)), isTrue);
        ctrl.exitRound();
      }
    },
  );

  test('every academic question is a four-option multiple-choice question', () {
    final all = AdvancedCatalog.all;
    expect(AdvancedCatalog.select(format: QuestionFormat.multipleChoice).length, all.length);
    for (final format in [QuestionFormat.multiSelect, QuestionFormat.trueFalse, QuestionFormat.fill,
        QuestionFormat.creation, QuestionFormat.ordering, QuestionFormat.matching,
        QuestionFormat.listening, QuestionFormat.pronunciation]) {
      expect(AdvancedCatalog.select(format: format), isEmpty, reason: format.label);
    }
    for (var i = 0; i < all.length; i += 7) {
      final q = all[i];
      expect(q.responseType, ResponseType.choice, reason: q.id);
      expect(q.options, hasLength(4), reason: q.id);
      expect(q.studyLevel, 'Lise', reason: q.id);
      expect(AdvancedCatalog.questionById(q.id)?.text, q.text);
    }
  });

  testWidgets(
    'creation waits for a draft and fill records the entered answer',
    (tester) async {
      final ctrl = ArenaController.inMemoryForTest();
      addTearDown(ctrl.dispose);
      const creation = Question(
        id: 'creation-example',
        text: 'Hangi tasarım ölçütü gereklidir?',
        options: ['Tekrarlanabilirlik', 'Hız', 'Renk', 'Sıra'],
        answer: 0,
        explanation: 'Deney başkalarınca tekrar edilebilmelidir.',
        category: Topic.science,
        difficulty: Difficulty.hard,
        bloom: BloomLevel.yaratma,
        creation: CreationTask('Bir deney düzeni tasarlayınız.', [
          'Kontrol değişkenlerini belirtiniz.',
        ]),
      );
      const fill = Question(
        id: 'fill-example',
        text: '2 + 3 = …',
        options: ['5', '4', '3', '2'],
        answer: 0,
        explanation: '2 + 3 = 5.',
        category: Topic.science,
        difficulty: Difficulty.easy,
        responseType: ResponseType.fill,
      );
      void start(Question q) => ctrl.startPackRound(
        QuestionPack(
          id: q.id,
          title: q.id,
          createdAt: DateTime(2026),
          models: const [],
          questions: [q],
        ),
      );
      start(creation);
      final current = ctrl.activeRound!;
      final timer = current.remainingSeconds;
      ctrl.submitChoice(current.current.answer);
      await tester.pump(const Duration(seconds: 20));
      expect(current.revealed, isFalse);
      expect(current.remainingSeconds, timer);
      expect(ctrl.saveCreationResponse('  '), isFalse);
      expect(
        ctrl.saveCreationResponse(
          'Sıcaklığı sabit tutarak iki grup karşılaştırırım.',
        ),
        isTrue,
      );
      expect(current.needsCreation, isFalse);
      ctrl.submitChoice(current.current.answer);
      expect(current.answers.single.writtenResponse, contains('Sıcaklığı'));
      expect(current.answers.single.correct, isTrue);
      start(fill);
      final currentFill = ctrl.activeRound!;
      ctrl.submitChoice(currentFill.current.answer);
      expect(currentFill.revealed, isFalse);
      ctrl.submitWrittenAnswer('5');
      expect(currentFill.answers.single.correct, isTrue);
      expect(currentFill.answers.single.writtenResponse, '5');
      ctrl.exitRound();
    },
  );

  test('round sampling respects visuals, topic, hidden questions and seed', () {
    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);
    const cfg = RoundSetup(
      topic: Topic.physics,
      format: QuestionFormat.visual,
      questionCount: 12,
    );
    final first = ctrl.sampleQuestions(cfg, seed: 38);
    expect(first, hasLength(12));
    expect(
      first.every((q) => q.category == Topic.physics && q.visual != null),
      isTrue,
    );
    expect(first.any((q) => AdvancedCatalog.hasId(q.id)), isTrue);
    expect(
      ctrl.sampleQuestions(cfg, seed: 38).map((q) => q.id),
      first.map((q) => q.id),
    );
    ctrl.reportedQuestionIds.add(first.first.id);
    expect(
      ctrl.sampleQuestions(cfg, seed: 38).map((q) => q.id),
      isNot(contains(first.first.id)),
    );
    ctrl.startVisualAndActivityDiscovery();
    expect(
      ctrl.activeRound!.questions.any((q) => AdvancedCatalog.hasId(q.id)),
      isTrue,
    );
    expect(
      ctrl.activeRound!.questions.every(
        (q) => q.visual != null || q.activity != null,
      ),
      isTrue,
    );
  });

  test('academy pages interleave sources, keep distinct cursors, and filter by level', () async {
    final ctrl = ArenaController.inMemoryForTest(
      seedQuestions: [
        for (var i = 0; i < 5; i++)
          Question(
            id: 'personal_$i',
            text: 'Kişisel soru $i',
            options: const ['A', 'B', 'C', 'D'],
            answer: 0,
            explanation: 'Örnek',
            category: Topic.exam,
            difficulty: Difficulty.easy,
          ),
      ],
    );
    addTearDown(ctrl.dispose);
    BrowserPageTask task(
      PoolCollection group,
      BrowserCursor cursor, {
      String query = '',
    }) => BrowserPageTask(
      personal: ctrl.personalQuestions,
      collection: group,
      topic: Topic.mixed,
      format: QuestionFormat.mixed,
      query: query,
      hidden: {},
      cursor: cursor,
      limit: 4,
    );
    final first = await task(PoolCollection.all, firstBrowserPage).run();
    expect(first.items.first.id, AdvancedCatalog.all.first.id);
    expect(first.items[1].id, ctrl.personalQuestions.first.id);
    final second = await task(PoolCollection.all, first.next).run();
    expect({
      ...first.items.map((q) => q.id),
      ...second.items.map((q) => q.id),
    }, hasLength(8));
    final ordinary = await task(
      PoolCollection.personal,
      firstBrowserPage,
    ).run();
    expect(ordinary.items.every((q) => !AdvancedCatalog.hasId(q.id)), isTrue);
    final highSchool = await task(
      PoolCollection.highSchool,
      firstBrowserPage,
    ).run();
    expect(
      highSchool.items.first.id,
      AdvancedCatalog.select(level: StudyLevel.lise).first.id,
    );
    final university = await task(
      PoolCollection.university,
      firstBrowserPage,
    ).run();
    expect(university.items, isEmpty);
  });
}
