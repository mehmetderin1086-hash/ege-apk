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
      expect(levels.length, 2);
      final blooms = ctrl.offlinePacks.where(
        (p) => p.id.startsWith('builtin_sb_ak38_bloom_'),
      );
      expect(blooms.length, 6);
      expect(
        blooms.fold<int>(0, (size, p) => size + p.questions.length),
        1270439,
      );
      for (final bloom in BloomLevel.values) {
        final pack = blooms.singleWhere((p) => p.id.endsWith('_${bloom.name}'));
        expect(pack.questions.first.bloom, bloom);
      }
      expect(
        levels.fold<int>(0, (count, p) => count + p.questions.length),
        1270439,
      );
      expect(ctrl.totalPoolCount, ctrl.personalQuestions.length + 1270439);
      expect(
        ctrl.allQuestions[ctrl.personalQuestions.length].id,
        AdvancedCatalog.all.first.id,
      );
      for (final f in AdvancedCatalog.families) {
        expect(AdvancedCatalog.hasId(f.questionAt(0).id), isTrue);
        expect(AdvancedCatalog.hasId(f.questionAt(f.count - 1).id), isTrue);
        expect(AdvancedCatalog.hasId('ak38_${f.key}_${f.count}'), isFalse);
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

  test('academic response-format views partition the curriculum and preserve exact offsets', () {
    const formats = [QuestionFormat.multipleChoice, QuestionFormat.multiSelect, QuestionFormat.trueFalse, QuestionFormat.fill,
      QuestionFormat.creation, QuestionFormat.ordering, QuestionFormat.matching,
      QuestionFormat.listening, QuestionFormat.pronunciation];
    var count = 0;
    for (final format in formats) {
      final view = AdvancedCatalog.select(format: format);
      expect(view.length, greaterThan(0), reason: format.label);
      count += view.length;
      for (final index in {0, view.length ~/ 2, view.length - 1}) {
        final q = view[index];
        expect(q.matchesFormat(format), isTrue, reason: q.id);
        expect(AdvancedCatalog.questionById(q.id)?.text, q.text);
      }
    }
    expect(count, AdvancedCatalog.all.length);
    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);
    for (final mode in [GameMode.sprint, GameMode.classic]) {
      final cfg = RoundSetup(mode: mode, liveVoiceHost: mode == GameMode.classic,
          format: QuestionFormat.creation, questionCount: 8);
      expect(ctrl.sampleQuestions(cfg, seed: 18).every((q) => q.responseType == ResponseType.choice), isTrue);
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

  test('a multi-select answer requires the exact set and records sorted indices', () {
    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);
    final q = AdvancedCatalog.select(format: QuestionFormat.multiSelect).first;
    ctrl.startQuestionPractice(q);
    final r = ctrl.activeRound!;
    expect(ctrl.useFiftyFiftyJoker(), isFalse);
    ctrl.submitChoice(0);
    expect(r.revealed, isFalse);
    final correct = r.current.multiSelect!.correct.toSet();
    ctrl.submitMultiple({...correct, -1});
    expect(r.revealed, isFalse);
    ctrl.submitMultiple(correct);
    expect(r.answers.single.correct, isTrue);
    expect(r.answers.single.submittedSequence, correct.toList()..sort());
  });

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
    final filtered = await task(
      PoolCollection.university,
      firstBrowserPage,
      query: 'a',
    ).run();
    expect(filtered.items, hasLength(4));
    expect(
      filtered.items.first.id,
      AdvancedCatalog.select(level: StudyLevel.universite).first.id,
    );
  });
}
