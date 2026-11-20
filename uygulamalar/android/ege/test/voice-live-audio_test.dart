import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/edge_tts_client.dart';
import 'package:jarvis_mobile/services/voice_service.dart';
import 'package:jarvis_mobile/services/work_hub.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';

class _FailClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('err')), 503);
}

class _CountingVoice extends VoiceService {
  final List<String> spoken = [];
  Completer<void>? pending;

  @override
  Future<void> speak(
    String rawText, {
    double rate = 0.52,
    double pitch = 1,
    JarvisSettings? settings,
    http.Client? httpClient,
    Future<void> Function()? onAudioStarted,
  }) async {
    spoken.add(rawText);
    if (spoken.length == 1) pending = Completer<void>();
    await onAudioStarted?.call();
    final p = pending;
    if (p != null) await p.future;
  }

  @override
  Future<void> stopSpeaking() async {
    final p = pending;
    if (p != null && !p.isCompleted) p.complete();
  }
}

class _LiveController extends JarvisController {
  _LiveController(_CountingVoice v) : super(voice: v);

  @override
  Future<void> sendMessage(String rawText, {bool speakReply = false}) async {
    sessions = [
      activeSession.copyWith(
        messages: [
          JarvisMessage(
            id: 'reply',
            role: 'assistant',
            content: 'Merhaba.',
            timestamp: DateTime.now(),
          ),
        ],
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const deviceChannel = MethodChannel('com.jarvis.assistant/device');
  const ttsChannel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockTts(List<String> calls) {
    messenger.setMockMethodCallHandler(ttsChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'speak') {
        Future<void>.microtask(() {
          messenger.handlePlatformMessage(
            'flutter_tts',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('speak.onComplete'),
            ),
            (_) {},
          );
        });
      }
      return 1;
    });
  }

  tearDown(() {
    EdgeTtsClient.testSynthesizer = null;
    messenger.setMockMethodCallHandler(deviceChannel, null);
    messenger.setMockMethodCallHandler(ttsChannel, null);
  });

  test('stopSpeaking during speak halt prevents playback (gen race)', () async {
    final ttsCalls = <String>[];
    final gate = Completer<void>();
    messenger.setMockMethodCallHandler(deviceChannel, (call) async {
      if (call.method == 'stopAudio') await gate.future;
      return true;
    });
    mockTts(ttsCalls);
    final voice = VoiceService();
    final f = voice.speak(
      'Merhaba dünya.',
      settings: const JarvisSettings(ttsEngine: 'device'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final stop = voice.stopSpeaking();
    gate.complete();
    await stop;
    await f;
    expect(ttsCalls.where((c) => c == 'speak'), isEmpty);
  });

  test('cloud TTS failure falls back to device TTS exactly once', () async {
    final ttsCalls = <String>[];
    messenger.setMockMethodCallHandler(deviceChannel, (call) async => true);
    mockTts(ttsCalls);
    EdgeTtsClient.testSynthesizer = (text, voice, rate) async =>
        (bytes: null, ext: 'mp3', error: 'offline');
    final voice = VoiceService();
    await voice.speak(
      'Birinci cümle. İkinci cümle.',
      settings: const JarvisSettings(ttsEngine: 'auto'),
      httpClient: _FailClient(),
    );
    expect(voice.lastEngineUsed, 'Cihaz TTS (yedek)');
    expect(voice.usedDeviceFallback, isTrue);
    expect(voice.lastError, isNotNull);
    expect(ttsCalls.where((c) => c == 'speak'), hasLength(1));
  });

  testWidgets('work finished during live loop is queued, spoken before mic', (
    tester,
  ) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(deviceChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'startMicCapture') return 'OK';
      return null;
    });
    final voice = _CountingVoice();
    final c = _LiveController(voice);
    c.settings = c.settings.copyWith(liveEngine: 'turn_based');
    unawaited(c.sendRealtimeTextPrompt('Merhaba'));
    await tester.pump();
    expect(voice.spoken, ['Merhaba.']);

    c.works.onFinished!(
      WorkJob(
        id: 'j1',
        kind: WorkKind.research,
        task: 'test',
        status: 'completed',
        createdAt: DateTime.now(),
      ),
    );
    // Canlı yanıt kesilmedi, duyuru hemen okunmadı.
    expect(voice.spoken, hasLength(1));

    voice.pending!.complete();
    await tester.pump();
    await tester.pump();
    expect(voice.spoken, hasLength(2));
    expect(voice.spoken.last, contains('tamamlandı'));
    expect(calls.indexOf('startMicCapture'), greaterThan(-1));
    await c.stopLiveSession();
    await tester.pump(const Duration(seconds: 25));
    c.dispose();
  });
}
