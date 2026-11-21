import 'package:bilgili_flutter/models/quiz_models.dart';
import 'package:bilgili_flutter/services/native_bridge.dart';
import 'package:bilgili_flutter/services/voice_answer_resolver.dart';
import 'package:bilgili_flutter/state/arena_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Question _activity(QuestionActivity activity) => Question(
  id: 'voice-test',
  text: 'Örneği dinle.',
  options: const ['/t/', '/d/', '/s/', '/z/'],
  answer: 2,
  explanation: '',
  category: Topic.language,
  difficulty: Difficulty.medium,
  activity: activity,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recognition checks all inflected words in order and scores the assigned answer index', () {
    final q = _activity(
      const QuestionActivity(
        kind: ActivityKind.pronunciation,
        title: 'Son ses',
        language: 'en-US',
        transcript: 'books, maps, cups.',
      ),
    );
    expect(VoiceAnswerResolver.resolve('BOOKS maps cups', q)?.choiceIndex, 2);
    expect(VoiceAnswerResolver.resolve('books maps', q), isNull);
    expect(VoiceAnswerResolver.resolve('cups books maps', q), isNull);
    expect(VoiceAnswerResolver.resolve('book map cup', q), isNull);
    expect(
      VoiceAnswerResolver.resolve(
        'book maps caps',
        q,
        alternatives: ['books, maps, cups'],
      )?.choiceIndex,
      2,
    );
    final segments = QuizNarration.questionSegments(q, 1);
    expect(
      segments.where((s) => s.language == 'en-US').single.text,
      'books, maps, cups.',
    );
    expect(
      segments
          .where((s) => s.language == 'tr-TR')
          .any((s) => s.text.contains('books')),
      isFalse,
    );
  });

  test('ordering and matching use the actual number and range of items', () {
    final q = _activity(
      const QuestionActivity(
        kind: ActivityKind.matching,
        title: 'Eşleştir',
        left: ['X', 'Y', 'Z'],
        right: ['A', 'B', 'C', 'D', 'E'],
        solution: [4, 0, 2],
      ),
    );
    expect(VoiceAnswerResolver.resolve('beş bir üç', q)?.sequence, [4, 0, 2]);
    expect(VoiceAnswerResolver.resolve('513', q)?.sequence, [4, 0, 2]);
    expect(VoiceAnswerResolver.resolve('üç', q), isNull);
    expect(VoiceAnswerResolver.resolve('bir iki altı', q), isNull);
    final order = _activity(
      const QuestionActivity(
        kind: ActivityKind.ordering,
        title: 'Sırala',
        items: ['X', 'Y', 'Z'],
        solution: [2, 0, 1],
      ),
    );
    expect(VoiceAnswerResolver.resolve('üç bir iki', order)?.sequence, [
      2,
      0,
      1,
    ]);
    expect(VoiceAnswerResolver.resolve('dört üç bir iki', order), isNull);
    expect(VoiceAnswerResolver.resolve('1 1 3', order), isNull);
    expect(QuizNarration.questionSegments(q, 4).single.text, contains('5. E.'));
  });

  test(
    'live host narrates manual response types without requesting microphone',
    () async {
      const channel = MethodChannel('com.mehmetderin.bilgiarena/native');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final ctrl = ArenaController.inMemoryForTest();
      final calls = <String>[];
      NativeBridge.testMode = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
      addTearDown(() {
        ctrl.exitRound();
        ctrl.dispose();
        NativeBridge.testMode = true;
        messenger.setMockMethodCallHandler(channel, null);
      });
      for (final format in [QuestionFormat.fill, QuestionFormat.multiSelect]) {
        calls.clear();
        expect(
          ctrl.startConfiguredRound(
            overrideSetup: RoundSetup(
              questionCount: 1,
              format: format,
              liveVoiceHost: true,
            ),
            seed: 38,
          ),
          isTrue,
        );
        await Future<void>.delayed(const Duration(milliseconds: 15));
        expect(ctrl.activeRound!.current.matchesFormat(format), isTrue);
        expect(calls, contains('speak'));
        expect(calls, isNot(contains('requestMicPermission')));
        expect(calls, isNot(contains('startListening')));
        expect(ctrl.livePhase, LiveVoicePhase.idle);
        ctrl.exitRound();
      }
    },
  );
}
