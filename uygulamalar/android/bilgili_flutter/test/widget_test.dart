import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilgili_flutter/main.dart';
import 'package:bilgili_flutter/models/quiz_models.dart';
import 'package:bilgili_flutter/services/ai_gateway_service.dart';
import 'package:bilgili_flutter/services/voice_answer_resolver.dart';
import 'package:bilgili_flutter/state/arena_controller.dart';

void main() {
  group('VoiceAnswerResolver Tests', () {
    const sampleQ = Question(
      id: 'q1',
      text: 'Türkiye\'nin başkenti neresidir?',
      options: ['İstanbul', ' İzmir', 'Ankara', 'Bursa'],
      answer: 2,
      explanation: 'Ankara 13 Ekim 1923\'ten beri başkenttir.',
      category: Topic.geography,
      difficulty: Difficulty.easy,
    );

    test('strips Turkish fillers and resolves letter, ordinal, and fuzzy option text', () {
      expect(
        VoiceAnswerResolver.resolve('Bence C şıkkı olsun', sampleQ)?.choiceIndex,
        2,
      );
      expect(
        VoiceAnswerResolver.resolve('üçüncü seçenek diyorum', sampleQ)?.choiceIndex,
        2,
      );
      expect(
        VoiceAnswerResolver.resolve('kesinlikle ankara eminim', sampleQ)?.choiceIndex,
        2,
      );
      expect(
        VoiceAnswerResolver.resolve('be', sampleQ)?.choiceIndex,
        1,
      );
    });

    test('detects spoken live quiz commands', () {
      expect(VoiceAnswerResolver.detectCommand('Soruyu tekrar oku'), SpokenVoiceCommand.repeatQuestion);
      expect(VoiceAnswerResolver.detectCommand('Pas geç'), SpokenVoiceCommand.skip);
      expect(VoiceAnswerResolver.detectCommand('Mola ver'), SpokenVoiceCommand.pause);
    });

    test('resolves 4-item ordering sequence and pronunciation phrase', () {
      const orderQ = Question(
        id: 'q_ord',
        text: 'Küçükten büyüğe sırala',
        options: ['A', 'B', 'C', 'D'],
        answer: 0,
        explanation: '',
        category: Topic.science,
        difficulty: Difficulty.easy,
        activity: QuestionActivity(
          kind: ActivityKind.ordering,
          title: 'Sayılar',
          items: ['30', '10', '40', '20'],
          solution: [1, 3, 0, 2],
        ),
      );
      final seqRes = VoiceAnswerResolver.resolve('iki dört bir üç', orderQ);
      expect(seqRes?.sequence, [1, 3, 0, 2]);

      const pronQ = Question(
        id: 'q_pron',
        text: 'Selamlama ifadesini söyle',
        options: ['Good morning', 'Good night', 'Hello', 'Thanks'],
        answer: 0,
        explanation: '',
        category: Topic.language,
        difficulty: Difficulty.easy,
        activity: QuestionActivity(
          kind: ActivityKind.pronunciation,
          title: 'Selam',
          transcript: 'Good morning',
          language: 'en-US',
        ),
      );
      expect(VoiceAnswerResolver.resolve('good morning', pronQ)?.choiceIndex, 0);
    });
  });

  group('AI & CLIProxy Parser Tests', () {
    test('strips think blocks and parses fenced JSON questions', () {
      const raw = '''
<think>Önce soruları tasarlayalım...</think>
```json
[
  {
    "text": "Işığın boşluktaki hızı yaklaşık kaç km/s'dir?",
    "options": ["300.000", "150.000", "30.000", "3.000"],
    "answer": 0,
    "explanation": "Işık hızı saniyede yaklaşık 300.000 kilometredir.",
    "category": "Bilim",
    "difficulty": "Kolay"
  }
]
```
''';
      final parsed = GeneratedQuestionParser.parseQuestions(raw, sourceModel: 'deepseek-r1');
      expect(parsed.length, 1);
      expect(parsed.first.category, Topic.science);
      expect(parsed.first.sourceModel, 'deepseek-r1');
    });

    test('merges live CLIProxy discovered models across all families', () {
      final merged = AiGatewayService.mergeCatalogWithLiveIds([
        'gemini-2.5-pro',
        'claude-sonnet-4-5',
        'custom-qwen-coder-next',
      ]);
      expect(merged.any((m) => m.id == 'custom-qwen-coder-next' && m.family == 'Qwen'), isTrue);
      expect(merged.any((m) => m.id == 'claude-sonnet-4-5' && m.discoveredLive), isTrue);
    });
  });

  group('ArenaController Game & Duel Engine Tests', () {
    test('handles jokers, scoring, Leitner review deck, and duel standings', () {
      final ctrl = ArenaController.inMemoryForTest();
      expect(ctrl.totalPoolCount, greaterThanOrEqualTo(15));

      ctrl.startDuelTournament(['Ali', 'Zeynep'], perPlayer: 2);
      expect(ctrl.activeRound, isNotNull);
      expect(ctrl.activeRound!.questions.length, 4);
      expect(ctrl.activeRound!.activeDuelPlayerName, 'Ali');

      expect(ctrl.useFiftyFiftyJoker(), isTrue);
      expect(ctrl.activeRound!.hiddenOptions.length, 2);

      // Ali answers right
      ctrl.submitChoice(ctrl.activeRound!.current.answer);
      expect(ctrl.activeRound!.duelScores[0], greaterThan(0));
      ctrl.nextQuestion();

      // Zeynep answers wrong -> goes into reviewDeck
      expect(ctrl.activeRound!.activeDuelPlayerName, 'Zeynep');
      final wrongOpt = (ctrl.activeRound!.current.answer + 1) % 4;
      ctrl.submitChoice(wrongOpt);
      expect(ctrl.reviewDeck, isNotEmpty);

      ctrl.finishActiveRound();
      expect(ctrl.history, isNotEmpty);
      expect(ctrl.history.first.duelStandings.first['name'], 'Ali');
    });

    test('parses built-in question bank packs and counts topics accurately', () {
      final ctrl = ArenaController.inMemoryForTest();
      expect(ctrl.countForTopic(Topic.mixed), ctrl.totalPoolCount);
      expect(ctrl.countForTopic(Topic.exam), greaterThan(0));
      expect(ctrl.ttsVoice, 'tr-TR-AhmetNeural');
    });
  });

  testWidgets('Full UI renders all 4 tabs (without AI Stüdyo) and plays a round on 360x800 screen without overflow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = ArenaController.inMemoryForTest();
    await tester.pumpWidget(BilgiliApp(controller: ctrl));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Bilgili'), findsOneWidget);
    expect(find.text('AI Stüdyo'), findsNothing);
    expect(find.text('AI Soru Stüdyosu'), findsNothing);

    // Navigate across all 4 tabs
    await tester.tap(find.text('Akademi'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Bilgi Akademisi & Havuz'), findsOneWidget);

    await tester.tap(find.text('İlerleme'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('İlerleme & Başarımlar'), findsOneWidget);

    await tester.tap(find.text('Ayarlar'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Atmosfer, Ses & Ayarlar'), findsOneWidget);

    // Return to Oyna tab and launch a 2-question round
    await tester.tap(find.text('Oyna'));
    await tester.pump(const Duration(milliseconds: 200));
    ctrl.updateSetup(ctrl.setup.copyWith(questionCount: 2));
    await tester.pump(const Duration(milliseconds: 100));

    ctrl.startConfiguredRound();
    await tester.pump(const Duration(milliseconds: 250));
    expect(ctrl.activeRound, isNotNull);
    expect(find.textContaining('Soru 1 / 2'), findsOneWidget);

    ctrl.exitRound();
    await tester.pump(const Duration(milliseconds: 200));
    expect(ctrl.activeRound, isNull);
  });
}
