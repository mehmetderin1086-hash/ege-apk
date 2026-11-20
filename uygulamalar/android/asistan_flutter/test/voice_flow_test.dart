import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:asistan_flutter/services/asistan_controller.dart';
import 'package:asistan_flutter/services/ai_engine.dart';
import 'package:asistan_flutter/models/asistan_models.dart';
import 'package:asistan_flutter/ui/animations_3d.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mehmetderin.asistan/native');
  final calls = <String>[];
  Future<void> emit(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    final done = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) => done.complete(),
        );
    await done.future;
  }

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  testWidgets('Stop cancels queued restart and ignores late speech', (
    tester,
  ) async {
    final c = AsistanController();
    await c.initialize(skipNativeAndNetwork: true);
    await c.startVoiceListening();
    await emit('onSpeechError', {'code': 6, 'message': 'Sessizlik'});
    await c.stopSpeechAndListening();
    final count = c.activeThread.messages.length;
    await emit('onSpeechResult', {'text': 'geç kalan sonuç'});
    await tester.pump(const Duration(seconds: 2));
    expect(calls.where((m) => m == 'startListening').length, 1);
    expect(c.activeThread.messages.length, count);
    expect(c.orbState, OrbActivityState.idle);
    c.dispose();
  });
  testWidgets('Hands free disabled does not restart', (tester) async {
    final c = AsistanController()..handsFreeVoiceLoop = false;
    await c.startVoiceListening();
    await emit('onSpeechError', {'code': 6});
    await tester.pump(const Duration(seconds: 2));
    expect(calls.where((m) => m == 'startListening').length, 1);
    c.dispose();
  });
  testWidgets('Permission denial ends session with visible error', (
    tester,
  ) async {
    final c = AsistanController();
    await c.startVoiceListening();
    await emit('onSpeechError', {
      'code': 9,
      'message': 'Mikrofon izni gerekli',
    });
    expect(c.liveSessionActive, isFalse);
    expect(c.voiceError, contains('Mikrofon'));
    await tester.pump(const Duration(seconds: 2));
    expect(calls.where((m) => m == 'startListening').length, 1);
    c.dispose();
  });
  test('Voice provider uses only discovered matching models', () {
    final c = AsistanController();
    c.engine.liveProxyModelIds = ['gemini-test', 'gpt-test', 'claude-test'];
    expect(c.voiceModelFor(LiveBrainMode.geminiLive), 'gemini-test');
    expect(c.voiceModelFor(LiveBrainMode.chatgptVoice), 'gpt-test');
    expect(c.voiceModelFor(LiveBrainMode.claudeLive), 'claude-test');
    c.engine.liveProxyModelIds = ['gemini-test'];
    expect(c.voiceModelFor(LiveBrainMode.claudeLive), isNull);
    c.dispose();
  });
  test('AI sends recent context and prompt exactly once', () async {
    List<dynamic>? sent;
    final engine = AiEngine(
      nativeCaller: (m, [a]) async => null,
      httpClient: MockClient((request) async {
        sent = (jsonDecode(request.body) as Map)['messages'] as List;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Response'},
              },
            ],
          }),
          200,
        );
      }),
    );
    await engine.processUserTurn(
      prompt: 'Merhaba',
      mode: WorkMode.voice,
      selectedModel: 'gemini-test',
      history: List.generate(
        20,
        (i) => ChatMessage(
          id: '$i',
          role: i.isEven ? 'user' : 'assistant',
          text: 'mesaj $i',
          timestamp: DateTime(2026),
        ),
      ),
      memories: [],
      mcpServers: [],
      onReminderCreated: (_) {},
      onMemoryAdded: (_) {},
    );
    expect(sent!.length, 14);
    expect(sent![1]['content'], 'mesaj 8');
    expect(sent!.where((m) => m['content'] == 'Merhaba').length, 1);
  });
}
