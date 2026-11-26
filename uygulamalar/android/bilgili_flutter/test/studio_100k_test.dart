import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:bilgili_flutter/data/advanced/studio100k/studio_100k.dart';
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

  test('studio100k contains exactly 100,000 non-text valid, unique questions (total 334,144)', () {
    expect(
      visualExpand25kFamilies.fold<int>(0, (s, f) => s + f.count),
      25000,
    );
    expect(
      visualNewEngines25kFamilies.fold<int>(0, (s, f) => s + f.count),
      25000,
    );
    expect(AdvancedCatalog.studioVisual50k.length, 50000);
    expect(AdvancedCatalog.studioAudioEnglish25k.length, 25000);
    expect(AdvancedCatalog.studioInteractive25k.length, 25000);
    expect(AdvancedCatalog.studio100k.length, 100000);
    expect(AdvancedCatalog.all.length, 334144);

    final seenIds = <String>{};
    var total = 0;
    for (final fam in studio100kFamilies) {
      // Strictly non-text: every single family must be visual, activity, multiSelect, trueFalse, or fill
      final isPlainTextChoice = fam.visualKind == null &&
          fam.activityKind == null &&
          fam.multiSelect == null &&
          (fam.fixedResponseType == null || fam.fixedResponseType == ResponseType.choice);
      expect(isPlainTextChoice, isFalse, reason: 'Plain text family not allowed in studio100k: ${fam.key}');

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
            expect(
              q.options.map((o) => o.trim()).toSet(),
              hasLength(4),
              reason: 'Duplicate opts in ${q.id}: ${q.options}',
            );
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
            expect(ms.options.toSet(), hasLength(4), reason: 'Duplicate multiSelect opts in ${q.id}: ${ms.options}');
            expect(ms.correct.length, inInclusiveRange(2, 3), reason: q.id);
            break;
          case ResponseType.ordering:
            final act = q.activity!;
            expect(act.items, hasLength(4), reason: q.id);
            expect(act.items.toSet(), hasLength(4), reason: q.id);
            expect(act.solution.toSet(), equals({0, 1, 2, 3}), reason: q.id);
            break;
          case ResponseType.matching:
            final act = q.activity!;
            expect(act.left, hasLength(4), reason: q.id);
            expect(act.right, hasLength(4), reason: q.id);
            expect(act.left.toSet(), hasLength(4), reason: q.id);
            expect(act.right.toSet(), hasLength(4), reason: q.id);
            expect(act.solution.toSet(), equals({0, 1, 2, 3}), reason: q.id);
            break;
          case ResponseType.slider:
            final act = q.activity!;
            expect(act.sliderMax, greaterThan(act.sliderMin), reason: q.id);
            expect(act.sliderStep, greaterThanOrEqualTo(1), reason: q.id);
            expect(act.sliderTarget, inInclusiveRange(act.sliderMin.round(), act.sliderMax.round()), reason: q.id);
            expect(act.matchesSlider(act.sliderTarget), isTrue, reason: q.id);
            break;
          case ResponseType.anagram:
            final act = q.activity!;
            final target = act.anagramTarget;
            expect(target.length, inInclusiveRange(4, 10), reason: q.id);
            expect(act.items, hasLength(target.length), reason: q.id);
            expect(act.matchesAnagram(target), isTrue, reason: q.id);
            final sortedTiles = List<String>.from(act.items)..sort();
            final sortedTarget = target.split('')..sort();
            expect(sortedTiles, equals(sortedTarget), reason: 'Anagram tiles mismatch in ${q.id}');
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

        if (i % 503 == 0) {
          expect(AdvancedCatalog.questionById(q.id)?.id, q.id);
        }
        total++;
      }
    }
    expect(total, 100000);
  });

  testWidgets('all 5 brand-new VisualKind painters render cleanly on 360x800 without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final samples = [
      AdvancedCatalog.questionById('ak38_s100_circuit_logic_0')!,
      AdvancedCatalog.questionById('ak38_s100_circuit_ohm_0')!,
      AdvancedCatalog.questionById('ak38_s100_circuit_ohm_1')!,
      AdvancedCatalog.questionById('ak38_s100_venn_sets_0')!,
      AdvancedCatalog.questionById('ak38_s100_compass_nav_0')!,
      AdvancedCatalog.questionById('ak38_s100_color_optik_0')!,
      AdvancedCatalog.questionById('ak38_s100_color_optik_1')!,
      AdvancedCatalog.questionById('ak38_s100_color_optik_2')!,
      AdvancedCatalog.questionById('ak38_s100_piano_studio_0')!,
      AdvancedCatalog.questionById('ak38_s100_piano_studio_2')!,
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

  testWidgets('3D Slider, 3D Audio English Anagram, live US/UK/AU accent switcher, and 3 speeds work on 360x800', (tester) async {
    NativeBridge.testMode = true;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);

    void loadSingle(Question q) {
      ctrl.startPackRound(
        QuestionPack(
          id: 'test_${q.id}',
          title: '3.21 Stüdyo Testi',
          createdAt: DateTime(2026),
          models: const [],
          questions: [q],
        ),
        maxQuestions: 1,
      );
    }

    // 1. 3D Slider Estimation
    final sliderQ = AdvancedCatalog.questionById('ak38_s100_slider_est_0')!;
    loadSingle(sliderQ);
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
    expect(find.text('Tahminimi Kilitle'), findsOneWidget);
    ctrl.submitSliderAnswer(sliderQ.activity!.sliderTarget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(ctrl.activeRound!.revealed, isTrue);
    expect(ctrl.activeRound!.answers.last.correct, isTrue);
    expect(find.textContaining('Tam Değer:'), findsOneWidget);

    // 2. 3D Audio English Anagram
    final anagramQ = AdvancedCatalog.questionById('ak38_s100_anagram_en_0')!;
    loadSingle(anagramQ);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Kelimeyi Dinle'), findsOneWidget);
    expect(find.textContaining('harf dizildi'), findsOneWidget);
    expect(find.text('İlk Harf'), findsOneWidget);
    await tester.tap(find.text('İlk Harf'));
    await tester.pump();
    ctrl.submitAnagramAnswer(anagramQ.activity!.anagramTarget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(ctrl.activeRound!.revealed, isTrue);
    expect(ctrl.activeRound!.answers.last.correct, isTrue);
    expect(find.textContaining('Kurduğun kelime:'), findsOneWidget);

    // 3. Multi-accent live Audio English switcher (US/UK/AU) + 1.2x fast speed
    final audioQ = AdvancedCatalog.questionById('ak38_s100_en_dialogues_0')!;
    loadSingle(audioQ);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('US'), findsOneWidget);
    expect(find.text('UK'), findsOneWidget);
    expect(find.text('AU'), findsOneWidget);
    expect(find.text('1.2x'), findsOneWidget);
    await tester.tap(find.text('UK'));
    await tester.pump();
    await tester.tap(find.text('1.2x'));
    await tester.pump();
    ctrl.submitChoice(ctrl.activeRound!.current.answer);
    await tester.pump(const Duration(milliseconds: 250));
    expect(ctrl.activeRound!.revealed, isTrue);

    ctrl.exitRound();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('HomePlayTab opens Görsel & Etkileşimli Stüdyo sheet and launches 3D Slider round', (tester) async {
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
    final card = find.text('Görsel & Etkinlik');
    await tester.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(card);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text('3D Tahmin Sürgüsü Stüdyosu (4.500)'), findsOneWidget);
    await tester.tap(find.text('3D Tahmin Sürgüsü Stüdyosu (4.500)'));
    await tester.pumpAndSettle();

    expect(ctrl.activeRound, isNotNull);
    expect(ctrl.activeRound!.questions, hasLength(10));
    expect(ctrl.activeRound!.questions.every((q) => q.isSlider), isTrue);
    ctrl.exitRound();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
