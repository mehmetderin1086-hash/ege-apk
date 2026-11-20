import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/ai_client.dart';
import 'package:jarvis_mobile/services/embedded_keys.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.StreamedResponse _sse(String text, {int status = 200}) {
  final body =
      'data: ${jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': text},
              ],
            },
          },
        ],
      })}\n\n';
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    status,
    headers: {'content-type': 'text/event-stream'},
  );
}

JarvisSettings _gemini(JarvisSettings s, {bool agentTools = true}) =>
    s.copyWith(
      provider: ApiProvider.geminiDirect,
      baseUrl: 'https://generativelanguage.googleapis.com',
      apiKey: 'fake-key-1',
      model: 'gemini-2.5-flash',
      agentTools: agentTools,
      autoTts: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AiClient.retryDelayOverride = (_) => Duration.zero;
  });
  tearDown(() => AiClient.retryDelayOverride = null);

  test('stop releases a stalled response and accepts a new turn immediately', () async {
    SharedPreferences.setMockInitialValues({});
    final started = Completer<void>();
    final delayed = Completer<http.StreamedResponse>();
    final c = JarvisController(httpClient: MockClient.streaming((req, body) async {
      if (!started.isCompleted) { started.complete(); return delayed.future; }
      return _sse('İkinci cevap');
    }));
    await c.init(loadPlatformTelemetry: false);
    addTearDown(c.dispose);
    await c.updateSettings(_gemini(c.settings));
    final first = c.sendMessage('Birinci sorum var');
    await started.future;
    try {
      await c.stopStreaming().timeout(const Duration(seconds: 2));
      await first.timeout(const Duration(seconds: 2));
      await c.sendMessage('İkinci sorum var');
      expect(c.activeSession.messages.last.content, 'İkinci cevap');
    } finally {
      delayed.complete(_sse('Eski cevap'));
    }
  });

  test('three simultaneous submissions and three tool calls make one reminder', () async {
    SharedPreferences.setMockInitialValues({});
    const action = '<MOBILE_ACTION>{"type":"create_timer","seconds":180,"label":"Deneme"}</MOBILE_ACTION>';
    var calls = 0;
    final client = MockClient.streaming((req, body) async {
      calls++;
      return _sse(action * 3);
    });
    final c = JarvisController(httpClient: client);
    await c.init(loadPlatformTelemetry: false);
    addTearDown(c.dispose);
    await c.updateSettings(_gemini(c.settings));
    const prompt = 'Başlayabiliriz';
    await Future.wait(List.generate(3, (_) => c.sendMessage(prompt)));
    expect(calls, 1);
    expect(c.activeTimers, hasLength(1));
    await c.sendMessage(prompt);
    expect(c.activeTimers, hasLength(2));
  });

  group('akış done yarışı', () {
    test('karışık telefon eylemi + veri aracı: ajan döngüsü çalışır', () async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      final mock = MockClient.streaming((req, body) async {
        calls++;
        if (calls == 1) {
          return _sse(
            'Bakıyorum <MOBILE_ACTION>{"type":"flashlight","enabled":true}</MOBILE_ACTION>'
            '<MOBILE_ACTION>{"type":"todo","add":"deneme"}</MOBILE_ACTION>',
          );
        }
        return _sse('Tamamlandı, görev eklendi.');
      });
      final c = JarvisController(httpClient: mock);
      await c.init(loadPlatformTelemetry: false);
      await c.updateSettings(_gemini(c.settings));
      await c.sendMessage('el fenerini aç ve görev ekle');
      expect(calls, 2, reason: 'ajan döngüsü ikinci isteği yapmalı');
      final contents = c.activeSession.messages
          .where((m) => m.role == 'assistant')
          .map((m) => m.content)
          .toList();
      expect(contents.any((t) => t.contains('Bakıyorum...') && t.startsWith('🔎')),
          isFalse);
      expect(contents.last, contains('Tamamlandı'));
      c.dispose();
    });

    test('agentTools kapalı: yer tutucu yerine Araçlar kapalı metni', () async {
      SharedPreferences.setMockInitialValues({});
      final mock = MockClient.streaming((req, body) async => _sse(
          '<MOBILE_ACTION>{"type":"web_search","query":"x"}</MOBILE_ACTION>'));
      final c = JarvisController(httpClient: mock);
      await c.init(loadPlatformTelemetry: false);
      await c.updateSettings(_gemini(c.settings, agentTools: false));
      await c.sendMessage('bugün dolar kaç');
      final last = c.activeSession.messages.last;
      expect(last.content, contains('Araçlar kapalı'));
      expect(last.content, isNot(contains('Bakıyorum')));
      c.dispose();
    });

    test('buildSystemPrompt(agentTools:false) veri aracı bölümünü içermez', () {
      final s = JarvisSettings.fromJson(const {});
      final on = AiClient.buildSystemPrompt(s, agentTools: true);
      final off = AiClient.buildSystemPrompt(s, agentTools: false);
      expect(on, contains('Bilgi getiren araçlar'));
      expect(on, contains('web_search: query'));
      expect(off, isNot(contains('web_search: query')));
      expect(off, isNot(contains('AJAN ARAÇLARI')));
      expect(off, contains('flashlight'));
    });
  });

  group('yeniden deneme', () {
    test('503 sonra başarı: yeniden dener', () async {
      var n = 0;
      final r = await AiClient.retrySend<http.Response>(
        () async => ++n < 3 ? http.Response('x', 503) : http.Response('ok', 200),
        (r) => r.statusCode,
      );
      expect(n, 3);
      expect(r.statusCode, 200);
    });

    test('en fazla 2 yeniden deneme', () async {
      var n = 0;
      final r = await AiClient.retrySend<http.Response>(
        () async {
          n++;
          return http.Response('x', 503);
        },
        (r) => r.statusCode,
      );
      expect(n, 3);
      expect(r.statusCode, 503);
    });

    test('SocketException yeniden denenir, 400 denenmez', () async {
      var n = 0;
      await AiClient.retrySend<http.Response>(
        () async {
          if (++n == 1) throw const SocketException('x');
          return http.Response('ok', 200);
        },
        (r) => r.statusCode,
      );
      expect(n, 2);
      n = 0;
      await AiClient.retrySend<http.Response>(() async {
        n++;
        return http.Response('bad', 400);
      }, (r) => r.statusCode);
      expect(n, 1);
    });

    test('tool requests recover from an exhausted proxy without replaying tools', () async {
      final settings = JarvisSettings.fromJson(const {}).copyWith(
        provider: ApiProvider.cliProxyApi, baseUrl: 'http://127.0.0.1:8317',
        model: 'gemini-2.5-flash', geminiTtsKey: 'test', autoFallbackGemini: true,
      );
      var directCalls = 0;
      final client = MockClient((request) async {
        if (request.url.host == '127.0.0.1') return http.Response('{}', 503);
        directCalls++;
        expect(request.body, contains('deneme'));
        return http.Response('{"candidates":[{"content":{"parts":[{"text":"tamam"}]}}]}', 200);
      });
      final reply = await AiClient.completeOnce(settings: settings, system: 's',
        user: 'deneme', client: client);
      expect(reply.text, 'tamam');
      expect(directCalls, 1);
    });

    test('completeOnce Gemini 503 sonra başarı', () async {
      var n = 0;
      final mock = MockClient((req) async {
        if (++n == 1) return http.Response('{}', 503);
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'merhaba'},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final r = await AiClient.completeOnce(
        settings: _gemini(JarvisSettings.fromJson(const {})),
        system: 's',
        user: 'u',
        client: mock,
      );
      expect(r.ok, isTrue);
      expect(n, 2);
    });

    test('ilk token sonrası akışta yeniden deneme yok', () async {
      var n = 0;
      final mock = MockClient.streaming((req, body) async {
        n++;
        final ctrl = StreamController<List<int>>();
        ctrl.add(utf8.encode(
            'data: ${jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'selam'},
                    ],
                  },
                },
              ],
            })}\n\n'));
        ctrl.addError(const SocketException('koptu'));
        ctrl.close();
        return http.StreamedResponse(ctrl.stream, 200);
      });
      final evs = await AiClient.streamChat(
        settings: _gemini(JarvisSettings.fromJson(const {})),
        messages: [
          JarvisMessage(
            id: '1',
            role: 'user',
            content: 'hi',
            timestamp: DateTime.now(),
          ),
        ],
        client: mock,
      ).toList().catchError((_) => <AiStreamEvent>[]);
      expect(evs, isA<List<AiStreamEvent>>());
      expect(n, 1);
    });

    test('busy proxy falls back before any output is delivered', () async {
      final settings = JarvisSettings.fromJson(const {}).copyWith(
        provider: ApiProvider.cliProxyApi, baseUrl: 'http://127.0.0.1:8317',
        model: 'gemini-2.5-flash', geminiTtsKey: 'test', autoFallbackGemini: true,
      );
      var fallbackCalls = 0;
      final mock = MockClient.streaming((req, body) async {
        if (req.url.host == '127.0.0.1') {
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 503);
        }
        fallbackCalls++;
        return _sse('merhaba');
      });
      final events = await AiClient.streamChat(settings: settings, messages: [],
        client: mock).toList();
      expect(fallbackCalls, 1);
      expect(events.last.fullText, contains('merhaba'));
      expect(events.any((e) => e.error != null), isFalse);
    });

    test('akış 503 ardından 200: tekrar dener', () async {
      var n = 0;
      final mock = MockClient.streaming((req, body) async {
        if (++n == 1) {
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 503);
        }
        return _sse('merhaba');
      });
      final evs = await AiClient.streamChat(
        settings: _gemini(JarvisSettings.fromJson(const {})),
        messages: [
          JarvisMessage(
            id: '1',
            role: 'user',
            content: 'hi',
            timestamp: DateTime.now(),
          ),
        ],
        client: mock,
      ).toList();
      expect(n, 2);
      expect(evs.last.fullText, 'merhaba');
    });
  });

  group('gömülü anahtar ve model listesi', () {
    test('force bayat Gemini anahtarının yerine geçer', () {
      const keys = EmbeddedKeys(gemini: 'fake-new-key');
      final s = _gemini(JarvisSettings.fromJson(const {})).copyWith(
        apiKey: 'fake-stale-key',
      );
      final out = keys.applyTo(s, force: true);
      expect(out.apiKey, 'fake-new-key');
      final out2 = keys.applyTo(s);
      expect(out2.apiKey, 'fake-stale-key');
    });

    test('model listesi nextPageToken izler', () async {
      final seen = <Uri>[];
      final mock = MockClient((req) async {
        seen.add(req.url);
        final tok = req.url.queryParameters['pageToken'];
        final body = tok == null
            ? {
                'models': [
                  {
                    'name': 'models/gemini-a',
                    'supportedGenerationMethods': ['generateContent'],
                  },
                ],
                'nextPageToken': 'T2',
              }
            : {
                'models': [
                  {
                    'name': 'models/gemini-b',
                    'supportedGenerationMethods': ['generateContent'],
                  },
                ],
              };
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
      final r = await AiClient.testAndFetchModels(
        _gemini(JarvisSettings.fromJson(const {})),
        client: mock,
      );
      expect(r.ok, isTrue);
      expect(r.models, containsAll(['gemini-a', 'gemini-b']));
      expect(seen.length, 2);
      expect(seen.first.queryParameters['pageSize'], '1000');
      expect(seen.last.queryParameters['pageToken'], 'T2');
    });
  });
}
