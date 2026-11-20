import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/ai_client.dart';
import 'package:jarvis_mobile/screens/live_voice_screen.dart';
import 'package:jarvis_mobile/services/voice_service.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';

class _SilentVoice extends VoiceService {
  @override
  Future<void> speak(
    String rawText, {
    double rate = 0.52,
    double pitch = 1,
    JarvisSettings? settings,
    http.Client? httpClient,
    Future<void> Function()? onAudioStarted,
  }) async {}

  @override
  Future<void> stopSpeaking() async {}
}

Uint8List _wav() {
  final b = BytesBuilder();
  b.add(List<int>.filled(44, 0));
  b.add(List<int>.filled(16000, 1));
  return b.toBytes();
}

http.Response _geminiReply(List<Map<String, dynamic>> parts) => http.Response(
  jsonEncode({
    'candidates': [
      {
        'content': {'parts': parts},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gemini bulut konuşma çözümleme', () {
    const settings = JarvisSettings(geminiTtsKey: 'test-key');

    test('anahtar yoksa ağ çağrısı yapılmaz', () async {
      var calls = 0;
      final r = await AiClient.transcribeWithGemini(
        settings: const JarvisSettings(),
        wav: _wav(),
        client: MockClient((_) async {
          calls++;
          return http.Response('', 500);
        }),
      );
      expect(r.ok, isFalse);
      expect(r.error, 'NO_KEY');
      expect(calls, 0);
    });

    test('düşünce parçaları ve tırnaklar metne karışmaz', () async {
      late http.Request seen;
      final r = await AiClient.transcribeWithGemini(
        settings: settings,
        wav: _wav(),
        client: MockClient((req) async {
          seen = req;
          return _geminiReply([
            {'text': 'iç ses', 'thought': true},
            {'text': '"Yarın sabah yedide beni uyandır."'},
          ]);
        }),
      );
      expect(r.ok, isTrue);
      expect(r.text, 'Yarın sabah yedide beni uyandır.');
      expect(seen.headers['x-goog-api-key'], 'test-key');
      expect(seen.url.path, contains(AiClient.geminiSttModels.first));
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      final part = (body['contents'] as List).first['parts'][0]['inlineData'];
      expect(part['mimeType'], 'audio/wav');
    });

    test('BOS yanıtı konuşma yok sayılır', () async {
      final r = await AiClient.transcribeWithGemini(
        settings: settings,
        wav: _wav(),
        client: MockClient(
          (_) async => _geminiReply([
            {'text': 'BOS'},
          ]),
        ),
      );
      expect(r.ok, isTrue);
      expect(r.text, isEmpty);
    });

    test('ilk model hata verirse yedek model denenir', () async {
      final models = <String>[];
      final r = await AiClient.transcribeWithGemini(
        settings: settings,
        wav: _wav(),
        client: MockClient((req) async {
          models.add(req.url.path);
          if (models.length == 1) return http.Response('{}', 404);
          return _geminiReply([
            {'text': 'merhaba'},
          ]);
        }),
      );
      expect(r.text, 'merhaba');
      expect(models, hasLength(2));
      expect(models.last, contains(AiClient.geminiSttModels[1]));
    });
  });

  group('telefon STT hazır değilken canlı mod', () {
    const channel = MethodChannel('com.jarvis.assistant/device');
    late List<String> calls;
    late JarvisController controller;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'startPhoneSpeech') {
              return {'status': 'ERROR', 'text': ''};
            }
            if (call.method == 'startMicCapture') return 'OK';
            return null;
          });
      controller = JarvisController(voice: _SilentVoice());
    });

    tearDown(() {
      controller.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('hata aynı turda kayıt moduna düşer ve yinelenmez', (
      tester,
    ) async {
      unawaited(controller.startLiveSession());
      await tester.pump();
      await tester.pump();
      expect(calls.where((c) => c == 'startPhoneSpeech'), hasLength(1));
      expect(calls.where((c) => c == 'startMicCapture'), hasLength(1));
      expect(controller.liveLoopActive, isTrue);
      expect(controller.livePhase, LiveVoicePhase.listening);
      expect(controller.liveStatusHint, 'Seni dinliyorum...');

      await controller.stopLiveSession();
      await tester.pump(const Duration(seconds: 1));
      unawaited(controller.startLiveSession());
      await tester.pump();
      await tester.pump();
      // İkinci oturum bozuk telefon STT'yi yeniden denemez.
      expect(calls.where((c) => c == 'startPhoneSpeech'), hasLength(1));
      expect(calls.where((c) => c == 'startMicCapture'), hasLength(2));
      await controller.stopLiveSession();
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('Türkçe model yoksa Canlı Ses uyarı ve indirme düğmesi gösterir', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LiveVoiceScreen(controller: controller))),
      );
      expect(find.byKey(const Key('live_stt_notice')), findsNothing);
      unawaited(controller.startLiveSession());
      await tester.pump();
      await tester.pump();
      expect(controller.phoneSttUnavailable, isTrue);
      expect(find.byKey(const Key('live_stt_notice')), findsOneWidget);
      await tester.ensureVisible(find.text('Modeli indir'));
      await tester.pump();
      await tester.tap(find.text('Modeli indir'));
      await tester.pump();
      expect(calls, contains('preparePhoneSpeech'));
      await controller.stopLiveSession();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('dikte de kayıt moduna düşer', (tester) async {
      String? got;
      final err = await controller.toggleDictation(
        onTranscript: (t) => got = t,
      );
      await tester.pump();
      expect(err, isNull);
      expect(got, isNull);
      expect(controller.isDictating, isTrue);
      expect(calls.where((c) => c == 'startMicCapture'), hasLength(1));
      await controller.toggleDictation(onTranscript: (t) => got = t);
      await tester.pump(const Duration(seconds: 31));
    });
  });

  test('ana ekranlarda eski siyan/lacivert HUD renkleri kalmadı', () {
    final legacy = RegExp(
      r'0xFF(22D3EE|67E8F9|1E3A5F|0B1628|0E2944|0E1B2E|0A1424|0A1324|94A3B8|162742|11223B|BAE6FD|E2E8F0)',
      caseSensitive: false,
    );
    for (final f in [
      'lib/screens/home_shell.dart',
      'lib/screens/tools_screen.dart',
      'lib/screens/studio_screen.dart',
      'lib/screens/works_screen.dart',
      'lib/screens/web_tools_screen.dart',
      'lib/screens/pc_hub_screen.dart',
      'lib/screens/chat_screen.dart',
      'lib/screens/live_voice_screen.dart',
      'lib/widgets/jarvis_nav_bar.dart',
    ]) {
      final hits = legacy.allMatches(File(f).readAsStringSync()).length;
      expect(hits, 0, reason: '$f eski renk kullanıyor');
    }
  });
}
