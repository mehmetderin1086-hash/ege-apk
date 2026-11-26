import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:bilgili_flutter/data/advanced/studio10k/studio_10k.dart';
import 'package:bilgili_flutter/models/quiz_models.dart';
import 'package:bilgili_flutter/screens/home_play_tab.dart';
import 'package:bilgili_flutter/screens/quiz_session_screen.dart';
import 'package:bilgili_flutter/services/native_bridge.dart';
import 'package:bilgili_flutter/state/arena_controller.dart';
import 'package:bilgili_flutter/widgets/question_renderers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('studio10k contains exactly 10,000 valid, unique, well-formed questions', () {
    expect(AdvancedCatalog.studioVisual4k.length, 4000);
    expect(AdvancedCatalog.studioAudioEnglish3k.length, 3000);
    expect(AdvancedCatalog.studioInteractive3k.length, 3000);
    expect(AdvancedCatalog.studio10k.length, 10000);

    final seenIds = <String>{};
    var total = 0;
    for (final fam in studio10kFamilies) {
      for (var i = 0; i < fam.count; i++) {
        final q = fam.questionAt(i);
        expect(seenIds.add(q.id), isTrue, reason: 'Duplicate id ${q.id}');
        expect(q.text.trim(), isNotEmpty, reason: q.id);
        expect(q.explanation.trim(), isNotEmpty, reason: q.id);

        switch (q.responseType) {
          case ResponseType.choice:
          case ResponseType.listening:
          case ResponseType.pronunciation:
            expect(q.options, hasLength(4), reason: q.id);
            expect(q.options.map((o) => o.trim()).toSet(), hasLength(4), reason: 'Duplicate opts in ${q.id}: ${q.options}');
            expect(q.answer, inInclusiveRange(0, 3), reason: q.id);
            break;
          case ResponseType.trueFalse:
            expect(q.options, equals(['Doğru', 'Yanlış']), reason: q.id);
            expect(q.answer, inInclusiveRange(0, 1), reason: q.id);
            break;
          case ResponseType.fill:
            expect(q.correctAnswerText.trim(), isNotEmpty, reason: q.id);
            expect(q.acceptsWritten(q.correctAnswerText), isTrue, reason: q.id);
            break;
          case ResponseType.multiSelect:
            final ms = q.multiSelect!;
            expect(ms.options, hasLength(4), reason: q.id);
            expect(ms.options.toSet(), hasLength(4), reason: q.id);
            expect(ms.correct.length, inInclusiveRange(2, 3), reason: q.id);
            break;
          case ResponseType.ordering:
            final act = q.activity!;
            expect(act.items, hasLength(4), reason: q.id);
            expect(act.solution.toSet(), equals({0, 1, 2, 3}), reason: q.id);
            break;
          case ResponseType.matching:
            final act = q.activity!;
            expect(act.left.length, greaterThanOrEqualTo(3), reason: q.id);
            expect(act.left.length, act.right.length, reason: q.id);
            expect(act.solution.toSet(), equals({for (var k = 0; k < act.left.length; k++) k}), reason: q.id);
            break;
          case ResponseType.creation:
            break;
        }

        if (q.activity?.kind == ActivityKind.listening ||
            q.activity?.kind == ActivityKind.dictation ||
            q.activity?.kind == ActivityKind.pronunciation) {
          expect(q.activity!.transcript?.trim(), isNotEmpty, reason: q.id);
          expect(q.activity!.language, startsWith('en-'), reason: q.id);
        }

        if (i % 97 == 0) {
          expect(AdvancedCatalog.questionById(q.id)?.id, q.id);
        }
        total++;
      }
    }
    expect(total, 10000);
  });

  testWidgets('all 7 new VisualKind painters render cleanly on 360x800 without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final samples = [
      AdvancedCatalog.select(visualKind: VisualKind.flag).first,
      AdvancedCatalog.select(visualKind: VisualKind.clock).first,
      AdvancedCatalog.select(visualKind: VisualKind.pieChart).first,
      AdvancedCatalog.select(visualKind: VisualKind.coordPlane).first,
      AdvancedCatalog.select(visualKind: VisualKind.atom).first,
      AdvancedCatalog.select(visualKind: VisualKind.musicStaff).first,
      AdvancedCatalog.select(visualKind: VisualKind.matrix).first,
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final q in samples)
                QuestionVisualViewer(visual: q.visual!, accent: const Color(0xFFF6C453)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Audio English Studio, Dictation, True/False, Multi-Select, Matching, and Ordering play end-to-end on 360x800', (tester) async {
    NativeBridge.testMode = true;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);

    final questions = [
      AdvancedCatalog.select(format: QuestionFormat.listening).first,
      AdvancedCatalog.select(format: QuestionFormat.dictation).first,
      AdvancedCatalog.select(format: QuestionFormat.pronunciation).first,
      AdvancedCatalog.select(format: QuestionFormat.trueFalse).first,
      AdvancedCatalog.select(format: QuestionFormat.multiSelect).first,
      AdvancedCatalog.select(format: QuestionFormat.ordering).first,
      AdvancedCatalog.select(format: QuestionFormat.matching).first,
    ];

    void loadSingle(Question q) {
      ctrl.startPackRound(
        QuestionPack(
          id: 'test_${q.id}',
          title: 'Çok Biçimli Test',
          createdAt: DateTime(2026),
          models: const [],
          questions: [q],
        ),
        maxQuestions: 1,
      );
    }

    loadSingle(questions[0]);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AnimatedBuilder(
          animation: ctrl,
          builder: (_, _) => Scaffold(body: QuizSessionScreen(controller: ctrl)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // 1. Listening screen shows 1.0x and Yavaş buttons
    expect(find.text('Dinle (1.0x)'), findsOneWidget);
    expect(find.text('Yavaş'), findsOneWidget);
    await tester.tap(find.text('Dinle (1.0x)'));
    await tester.pump();
    ctrl.submitChoice(ctrl.activeRound!.current.answer);
    await tester.pump(const Duration(milliseconds: 200));
    expect(ctrl.activeRound!.revealed, isTrue);

    // 2. Dictation screen shows Harf İpucu and accepts typed answer
    loadSingle(questions[1]);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Harf İpucu Göster'), findsOneWidget);
    await tester.tap(find.text('Harf İpucu Göster'));
    await tester.pump();
    expect(find.textContaining('İpucu:'), findsOneWidget);
    final dictationAns = ctrl.activeRound!.current.correctAnswerText;
    await tester.enterText(find.byType(TextField), dictationAns);
    await tester.pump();
    ctrl.submitWrittenAnswer(dictationAns);
    await tester.pump(const Duration(milliseconds: 200));
    expect(ctrl.activeRound!.answers.last.correct, isTrue);

    // 3. Pronunciation renders cleanly
    loadSingle(questions[2]);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Söyle'), findsOneWidget);
    ctrl.submitChoice(ctrl.activeRound!.current.answer);
    await tester.pump(const Duration(milliseconds: 200));
    expect(ctrl.activeRound!.revealed, isTrue);

    // 4. True/False renders 3D Doğru / Yanlış cards
    loadSingle(questions[3]);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Doğru'), findsOneWidget);
    expect(find.text('Yanlış'), findsOneWidget);
    await tester.tap(find.text('Doğru'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(ctrl.activeRound!.revealed, isTrue);

    // 5. Multi-Select renders cleanly
    loadSingle(questions[4]);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Seçimlerimi Kontrol Et'), findsOneWidget);
    ctrl.submitMultiple(ctrl.activeRound!.current.multiSelect!.correct.toSet());
    await tester.pump(const Duration(milliseconds: 200));
    expect(ctrl.activeRound!.answers.last.correct, isTrue);

    // 6. Ordering renders cleanly
    loadSingle(questions[5]);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('öğe seçildi'), findsOneWidget);
    ctrl.submitActivitySequence(ctrl.activeRound!.current.activity!.solution);
    await tester.pump(const Duration(milliseconds: 200));
    expect(ctrl.activeRound!.answers.last.correct, isTrue);

    // 7. Matching renders cleanly
    loadSingle(questions[6]);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('0/4 eşleşti'), findsOneWidget);
    ctrl.submitActivitySequence(ctrl.activeRound!.current.activity!.solution);
    await tester.pump(const Duration(milliseconds: 200));
    expect(ctrl.activeRound!.answers.last.correct, isTrue);
    ctrl.exitRound();
    await tester.pump();
    expect(tester.takeException(), isNull);
    ctrl.exitRound();
  });

  testWidgets('HomePlayTab opens Sesli İngilizce Stüdyosu modal and launches listening round', (tester) async {
    NativeBridge.testMode = true;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: HomePlayTab(
            controller: ctrl,
            onOpenAcademyReview: () {},
            onOpenProgressTab: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final card = find.text('Sesli İngilizce Stüdyosu (3.000 Soru)');
    await tester.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(card);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text('İngilizce Dinleme & Anlama (1.800 Soru)'), findsOneWidget);
    await tester.tap(find.text('İngilizce Dinleme & Anlama (1.800 Soru)'));
    await tester.pumpAndSettle();

    expect(ctrl.activeRound, isNotNull);
    expect(ctrl.activeRound!.questions, hasLength(10));
    expect(ctrl.activeRound!.questions.every((q) => q.activity?.kind == ActivityKind.listening), isTrue);
    ctrl.exitRound();
    await tester.pump();
    expect(tester.takeException(), isNull);
    ctrl.exitRound();
    await tester.pump();
  });
}
