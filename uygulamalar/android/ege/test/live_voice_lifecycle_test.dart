import 'dart:async';
import 'dart:convert';
import 'package:jarvis_mobile/services/local_command_engine.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/voice_service.dart';
import 'package:jarvis_mobile/services/device_bridge.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';

class PendingVoice extends VoiceService {
  Completer<void>? pending;
  int spoken = 0;
  JarvisSettings? receivedSettings;
  bool failToSpeak = false;

  @override
  Future<void> speak(
    String rawText, {
    double rate = 0.52,
    double pitch = 1,
    JarvisSettings? settings,
    http.Client? httpClient,
    Future<void> Function()? onAudioStarted,
  }) async {
    spoken++;
    receivedSettings = settings;
    if (failToSpeak) throw StateError('TTS unavailable');
    pending = Completer<void>();
    await onAudioStarted?.call();
    return pending!.future;
  }

  @override
  Future<void> stopSpeaking() async {
    if (pending != null && !pending!.isCompleted) pending!.complete();
  }
}

class LiveController extends JarvisController {
  LiveController(PendingVoice voice) : super(voice: voice);

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
  const channel = MethodChannel('com.jarvis.assistant/device');
  late List<String> calls;
  late PendingVoice voice;
  late LiveController controller;
  Completer<Map<String, Object>>? phonePending;

  setUp(() {
    calls = [];
    phonePending = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'startMicCapture') return 'OK';
          if (call.method == 'startPhoneSpeech') {
            phonePending = Completer<Map<String, Object>>();
            return phonePending!.future;
          }
          if (call.method == 'cancelPhoneSpeech' && phonePending != null && !phonePending!.isCompleted) {
            phonePending!.complete({'status': 'CANCELLED', 'text': ''});
          }
          return null;
        });
    voice = PendingVoice();
    controller = LiveController(voice);
    controller.settings = controller.settings.copyWith(
      liveEngine: 'turn_based',
    );
  });

  test('explicit YouTube and bare stop use the playing media session once', () async {
    final events = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'mediaSessionCommand');
          events.add("${call.arguments['package']}:${call.arguments['action']}");
          return 'Oynatma durduruldu.';
        });
    for (final command in ["YouTube'dan şarkıyı kapat", "kapat", "durdur", "Spotify müziği devam ettir"]) {
      expect((await controller.runLocalCommand(command))?.handled, isTrue);
    }
    expect(events, ['com.google.android.youtube:pause', ':pause', ':pause', 'com.spotify.music:resume']);
    expect(controller.wakeWordStoppedByUser, isFalse);
  });

  test('a compound request goes back only after verified pause', () async {
    var confirmed = false;
    final actions = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          actions.add(call.method);
          if (call.method == 'currentAppCommand') return 'Geri döndüm.';
          return confirmed ? 'Oynatma durduruldu.' : 'Durum belirsiz.';
        });
    const command = 'şarkıyı durdur ve geri gel';
    await controller.runLocalCommand(command);
    expect(actions, ['mediaSessionCommand']);
    actions.clear();
    confirmed = true;
    expect((await controller.runLocalCommand(command))?.reply, contains('Geri döndüm.'));
    expect(actions, ['mediaSessionCommand', 'currentAppCommand']);
  });

  test('geri and kapat act on the current app and preserve the assistant', () async {
    final actions = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'mediaSessionCommand') return 'NO_MEDIA';
          if (call.method == 'currentAppCommand') {
            actions.add(call.arguments['action'] as String);
            return 'Tamam';
          }
          fail('Unexpected ${call.method}');
        });
    expect((await controller.runLocalCommand('geri gel'))?.handled, isTrue);
    expect((await controller.runLocalCommand('kapat'))?.handled, isTrue);
    expect(actions, ['back', 'leave']);
    expect(controller.wakeWordStoppedByUser, isFalse);
  });

  test('generic screen commands use current targets across apps', () async {
    var controls = <Map<String, dynamic>>[];
    String? action;
    String? target;
    String screen() => jsonEncode({'package': 'example.app', 'controls': controls});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'currentAppCommand') return screen();
          expect(call.method, 'controlApp');
          expect(call.arguments['package'], 'example.app');
          action = call.arguments['action'];
          target = call.arguments['target'];
          return screen();
        });
    controls = [
      {'target':'@2:0', 'enabled':true, 'clickable':true, 'label':''},
      {'target':'@2:1', 'parent':'@2:0', 'enabled':true, 'label':'İleri'},
      {'target':'@2:2', 'enabled':true, 'scrollable':true, 'label':'Liste'},
    ];
    await controller.runLocalCommand('ileri git');
    expect([action,target], ['click','@2:0']);
    await controller.runLocalCommand("İleri’ye dokun");
    expect([action,target], ['click','@2:0']);
    await controller.runLocalCommand('yukarı kaydır');
    expect([action,target], ['scroll_back','@2:2']);
    controls.add({'target':'@2:3', 'enabled':true, 'clickable':true, 'label':'İleri'});
    action = null;
    expect((await controller.runLocalCommand('ileri'))?.reply, contains('birden fazla'));
    expect(action, isNull);
    expect((await controller.runLocalCommand('ekranı oku'))?.reply, contains('Liste'));
  });

  test('in-app search targets the visible field and checks the resulting text', () async {
    const prefix = '{"package":"com.mehmetderin.otobus","controls":[';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'currentAppCommand') {
            return '${prefix}{"target":"@1:2","editable":true,"enabled":true,"label":""}]}';
          }
          expect(call.method, 'controlApp');
          expect(call.arguments['target'], '@1:2');
          expect(call.arguments['text'], '15F');
          return '${prefix}{"target":"@2:3","editable":true,"label":"15F"}]}';
        });
    final result = await controller.runLocalCommand('onun içinde 15F ara');
    expect(result?.reply, contains('15F'));
  });

  test('kapan releases capture and wake listener before dismissing the task', () async {
    controller.liveLoopActive = true;
    await controller.sendRealtimeTextPrompt('Asistan, kapan.');
    expect(controller.liveLoopActive, isFalse);
    expect(controller.wakeWordStoppedByUser, isTrue);
    expect(calls, containsAllInOrder(['wakeWordStop', 'closeAssistantTask']));
    expect(calls, contains('cancelPhoneSpeech'));
    for (final text in ['feneri kapat', 'kapanma', 'kapan deyince ne olur?', 'Spotify kapat']) {
      expect(LocalCommandEngine.isAssistantExit(text), isFalse);
    }
  });

  tearDown(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('live voice respects selected Azure voice and engine', (
    tester,
  ) async {
    controller.settings = controller.settings.copyWith(
      ttsEngine: 'azure',
      proxyTtsVoice: 'tr-TR-EmelNeural',
      ttsStyle: 'warm',
    );
    unawaited(controller.sendRealtimeTextPrompt('Merhaba'));
    await tester.pump();
    expect(voice.receivedSettings!.ttsEngine, 'azure');
    expect(voice.receivedSettings!.proxyTtsVoice, 'tr-TR-EmelNeural');
    expect(voice.receivedSettings!.ttsStyle, 'warm');
    expect(calls, contains('wakeWordPause'));
    await controller.stopLiveSession();
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('voice failure stops live without opening another capture', (
    tester,
  ) async {
    voice.failToSpeak = true;
    await controller.sendRealtimeTextPrompt('Merhaba');
    expect(controller.liveLoopActive, false);
    expect(controller.liveStatusHint, contains('Ses motoruna'));
    expect(calls.where((c) => c == 'startMicCapture'), isEmpty);
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('reported TTS error is visible instead of silently listening', (
    tester,
  ) async {
    unawaited(controller.sendRealtimeTextPrompt('Merhaba'));
    await tester.pump();
    voice.lastError = 'Azure bağlantısı kurulamadı';
    voice.pending!.complete();
    await tester.pump();
    expect(controller.liveLoopActive, false);
    expect(controller.liveStatusHint, contains('Azure bağlantısı kurulamadı'));
    expect(calls.where((c) => c == 'startMicCapture'), isEmpty);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('interrupting speech starts exactly one replacement capture', (
    tester,
  ) async {
    unawaited(controller.sendRealtimeTextPrompt('Merhaba'));
    await tester.pump();
    expect(voice.spoken, 1);
    expect(controller.livePhase, LiveVoicePhase.speaking);
    unawaited(controller.interruptAndListenLive());
    await tester.pump();
    expect(calls.where((c) => c == 'startPhoneSpeech').length, 1);
    expect(controller.livePhase, LiveVoicePhase.listening);
    await controller.stopLiveSession();
    await tester.pump(const Duration(seconds: 25));
    expect(calls.where((c) => c == 'stopMicCapture'), isEmpty);
    expect(controller.liveLoopActive, isFalse);
  });

  testWidgets('stopped capture cannot time out into a restarted session', (
    tester,
  ) async {
    unawaited(controller.startLiveSession());
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await controller.stopLiveSession();
    await tester.pump();
    unawaited(controller.startLiveSession());
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(calls.where((c) => c == 'startPhoneSpeech').length, 2);
    expect(calls.where((c) => c == 'stopMicCapture'), isEmpty);
    expect(controller.liveLoopActive, isTrue);
    expect(controller.livePhase, LiveVoicePhase.listening);
    await controller.stopLiveSession();
    await tester.pump(const Duration(seconds: 25));
  });

  testWidgets('concurrent starts share a single microphone capture', (
    tester,
  ) async {
    unawaited(controller.startLiveSession());
    unawaited(controller.startLiveSession());
    await tester.pump();
    expect(calls.where((c) => c == 'startPhoneSpeech').length, 1);
    await controller.stopLiveSession();
    await tester.pump(const Duration(seconds: 25));
  });
  testWidgets('voice interruption retains the already open microphone', (
    tester,
  ) async {
    controller.whisperDownloaded = {'tiny-q5_1'};
    var token = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'startDuplexCapture') {
            token = call.arguments['token'] as int;
            return {'status': 'OK', 'bargeIn': true};
          }
          return null;
        });
    unawaited(controller.sendRealtimeTextPrompt('Merhaba'));
    await tester.pump();
    expect(calls.where((c) => c == 'startDuplexCapture'), hasLength(1));
    final event = DeviceBridge.onDuplexEvent!;
    event({'token': token, 'event': 'level', 'level': 0.8});
    expect(voice.pending!.isCompleted, false);
    event({'token': token, 'event': 'speech'});
    await tester.pump();
    expect(voice.pending!.isCompleted, true);
    expect(controller.livePhase, LiveVoicePhase.listening);
    expect(calls.where((c) => c == 'startMicCapture'), isEmpty);
    await controller.stopLiveSession();
    event({'token': token, 'event': 'speech'});
    await tester.pump(const Duration(seconds: 36));
    expect(controller.liveLoopActive, false);
    expect(calls.where((c) => c == 'startDuplexCapture'), hasLength(1));
  });

  testWidgets(
    'natural speech completion promotes capture without a new STT start',
    (tester) async {
      controller.settings = controller.settings.copyWith(sttMode: 'whisper');
      controller.whisperDownloaded = {'tiny-q5_1'};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'startDuplexCapture')
              return {'status': 'OK', 'bargeIn': true};
            return null;
          });
      unawaited(controller.sendRealtimeTextPrompt('Merhaba'));
      await tester.pump();
      voice.pending!.complete();
      await tester.pump();
      expect(controller.livePhase, LiveVoicePhase.listening);
      expect(calls.where((c) => c == 'duplexPlaybackEnded'), hasLength(1));
      expect(
        calls.where((c) => c == 'startMicCapture' || c == 'startPhoneSpeech'),
        isEmpty,
      );
      await controller.stopLiveSession();
      await tester.pump(const Duration(seconds: 36));
    },
  );

  testWidgets('phone STT stays first even with a downloaded Whisper model', (
    tester,
  ) async {
    controller.whisperDownloaded = {'tiny-q5_1'};
    final recognition = Completer<Map<String, dynamic>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'startPhoneSpeech') return recognition.future;
          return null;
        });
    unawaited(controller.startLiveSession());
    await tester.pump();
    expect(calls.where((c) => c == 'startPhoneSpeech'), hasLength(1));
    expect(calls.where((c) => c == 'startMicCapture'), isEmpty);
    await controller.stopLiveSession();
    recognition.complete({'status': 'OK', 'text': 'eski konuşma'});
    await tester.pump(const Duration(seconds: 1));
    expect(voice.spoken, 0);
  });

  testWidgets('normal playback releases duplex before next phone STT turn', (
    tester,
  ) async {
    controller.whisperDownloaded = {'tiny-q5_1'};
    final recognition = Completer<Map<String, dynamic>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'startDuplexCapture')
            return {'status': 'OK', 'bargeIn': true};
          if (call.method == 'startPhoneSpeech') return recognition.future;
          return null;
        });
    unawaited(controller.sendRealtimeTextPrompt('Merhaba'));
    await tester.pump();
    voice.pending!.complete();
    await tester.pump();
    expect(
      calls.indexOf('stopDuplexCapture'),
      lessThan(calls.indexOf('startPhoneSpeech')),
    );
    expect(calls.where((c) => c == 'startPhoneSpeech'), hasLength(1));
    expect(calls.where((c) => c == 'duplexPlaybackEnded'), isEmpty);
    await controller.stopLiveSession();
    recognition.complete({'status': 'CANCELLED', 'text': ''});
    await tester.pump(const Duration(seconds: 1));
  });
}
