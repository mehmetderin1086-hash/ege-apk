import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/ai_client.dart';
import 'package:jarvis_mobile/services/edge_tts_client.dart';
import 'package:jarvis_mobile/services/local_command_engine.dart';
import 'package:jarvis_mobile/services/math_evaluator.dart';
import 'package:jarvis_mobile/services/realtime_live_service.dart';
import 'package:jarvis_mobile/services/voice_service.dart';

class _FakeRealtimeTransport implements RealtimeTransport {
  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final List<String> sentFrames = [];
  bool closed = false;

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  void sendText(String data) {
    sentFrames.add(data);
  }

  @override
  Future<void> close() async {
    closed = true;
    await incoming.close();
  }
}

class _FakeDelegate implements MobileStateDelegate {
  final List<JarvisTimer> _timers = [];
  final List<String> notes = [];
  final List<DeviceAppInfo> _installedApps = [
    const DeviceAppInfo(
      name: 'WhatsApp',
      packageName: 'com.whatsapp',
      versionName: '2.26.1',
    ),
    const DeviceAppInfo(
      name: 'Spotify',
      packageName: 'com.spotify.music',
      versionName: '8.9.0',
    ),
  ];
  final List<(String url, String? fileName)> downloadedFiles = [];
  final List<String> downloadedVideos = [];
  final List<String> startedResearches = [];
  int? openedTab;
  int? openedSubTab;

  @override
  List<JarvisTimer> get timers => List.unmodifiable(_timers);

  @override
  List<DeviceAppInfo> get installedApps => List.unmodifiable(_installedApps);

  @override
  Future<JarvisTimer> addTimer(int seconds, String label) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final t = JarvisTimer(
      id: LocalCommandEngine.newId(),
      label: label,
      durationSec: seconds,
      createdAtEpoch: now,
      fireAtEpoch: now + seconds,
    );
    _timers.add(t);
    return t;
  }

  @override
  Future<int> cancelTimers({bool all = false, bool earliest = false}) async {
    if (_timers.isEmpty) return 0;
    if (all) {
      final count = _timers.length;
      _timers.clear();
      return count;
    }
    if (earliest) {
      _timers.sort((a, b) => a.fireAtEpoch.compareTo(b.fireAtEpoch));
    }
    _timers.removeAt(0);
    return 1;
  }

  @override
  Future<void> appendToActiveNote(String text) async {
    notes.add(text);
  }

  @override
  void openTab(int mainTab, {int? toolsSubTab}) {
    openedTab = mainTab;
    openedSubTab = toolsSubTab;
  }

  @override
  Future<String> downloadFile(String url, {String? fileName}) async {
    downloadedFiles.add((url, fileName));
    return 'Dosya indiriliyor: $url';
  }

  @override
  Future<String> downloadVideo(String url) async {
    downloadedVideos.add(url);
    return 'Video indiriliyor: $url';
  }

  @override
  Future<String> startDeepResearch(String question) async {
    startedResearches.add(question);
    return 'Araştırma başlatıldı: $question';
  }
}

class _StreamingMockClient extends http.BaseClient {
  final List<String> chunks;

  _StreamingMockClient({required this.chunks});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final controller = StreamController<List<int>>();
    scheduleMicrotask(() async {
      for (final c in chunks) {
        controller.add(utf8.encode(c));
        await Future<void>.delayed(Duration.zero);
      }
      await controller.close();
    });
    return http.StreamedResponse(
      controller.stream,
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }

  @override
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    return http.Response.bytes(Uint8List(0), 200);
  }
}

class _RoutingMockClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.Request request) handler;

  _RoutingMockClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      return handler(request);
    }
    throw UnsupportedError('Unexpected request type: ${request.runtimeType}');
  }
}

void main() {
  group('MathEvaluator', () {
    test('evaluates operator precedence and parentheses', () {
      expect(MathEvaluator.evaluate('2 + 3 * 4'), 14);
      expect(MathEvaluator.evaluate('(2 + 3) * 4'), 20);
      expect(MathEvaluator.evaluate('-5 + 12'), 7);
      expect(MathEvaluator.evaluate('2 ^ 3'), 8);
    });

    test('supports Turkish comma decimals and scientific functions', () {
      expect(MathEvaluator.evaluate('3,5 * 2'), 7);
      expect(MathEvaluator.evaluate('sqrt(144)'), 12);
      expect(MathEvaluator.evaluate('cos(0)'), 1);
      expect(MathEvaluator.evaluate('ln(e)'), closeTo(1.0, 1e-9));
      expect(MathEvaluator.evaluate('log(100)'), closeTo(2.0, 1e-9));
      expect(MathEvaluator.formatResult(12.0), '12');
    });

    test('throws on division by zero or invalid syntax', () {
      expect(() => MathEvaluator.evaluate('10 / 0'), throwsFormatException);
      expect(() => MathEvaluator.evaluate('2 + * 3'), throwsFormatException);
    });
  });

  group('LocalCommandEngine', () {
    test('normalizes Turkish characters properly', () {
      expect(
        LocalCommandEngine.normalizeTr('İSTANBUL   IĞDIR'),
        'istanbul ığdır',
      );
    });

    test('respects question and negation guardrails', () async {
      final del = _FakeDelegate();
      final q = await LocalCommandEngine.tryHandle(
        'nasıl zamanlayıcı kurulur?',
        del,
      );
      final neg = await LocalCommandEngine.tryHandle('timer kurma', del);
      expect(q.handled, isFalse);
      expect(neg.handled, isFalse);
      expect(del.timers, isEmpty);
    });

    test('parses timers, lists and cancels cleanly', () async {
      final del = _FakeDelegate();
      final addRes = await LocalCommandEngine.tryHandle(
        '5 dk çay sayacı kur',
        del,
      );
      expect(addRes.handled, isTrue);
      expect(del.timers.length, 1);
      expect(del.timers.first.durationSec, 300);

      final clockRes = await LocalCommandEngine.tryHandle(
        "saat 23:59'da ilaç hatırlat",
        del,
      );
      expect(clockRes.handled, isTrue);
      expect(del.timers.length, 2);

      final listRes = await LocalCommandEngine.tryHandle(
        'zamanlayıcıları listele',
        del,
      );
      expect(listRes.handled, isTrue);
      expect(listRes.reply, contains('Etkin zamanlayıcılar'));

      final cancelAll = await LocalCommandEngine.tryHandle(
        'tüm zamanlayıcıları iptal et',
        del,
      );
      expect(cancelAll.handled, isTrue);
      expect(del.timers, isEmpty);
    });

    test('handles note append and offline calculator command', () async {
      final del = _FakeDelegate();
      final noteRes = await LocalCommandEngine.tryHandle(
        'notlarıma ekle: Yarın 09:00 toplantı',
        del,
      );
      expect(noteRes.handled, isTrue);
      expect(del.notes, ['Yarın 09:00 toplantı']);

      final calcRes = await LocalCommandEngine.tryHandle(
        'hesapla sqrt(81) + 9',
        del,
      );
      expect(calcRes.handled, isTrue);
      expect(calcRes.reply, contains('18'));
    });

    test('extracts and strips structured MOBILE_ACTION blocks', () {
      const sample =
          'Elbette!\n<MOBILE_ACTION>{"type":"add_note","content":"Süt al"}</MOBILE_ACTION>';
      final actions = LocalCommandEngine.extractActions(sample);
      expect(actions.length, 1);
      expect(actions.first['type'], 'add_note');
      expect(LocalCommandEngine.stripActionTags(sample), 'Elbette!');
    });
  });

  group('AiClient', () {
    test('returns friendly error when Gemini key is missing', () async {
      final events = await AiClient.streamChat(
        settings: const JarvisSettings(
          provider: ApiProvider.geminiDirect,
          apiKey: '',
        ),
        messages: [
          JarvisMessage(
            id: '1',
            role: 'user',
            content: 'Merhaba',
            timestamp: DateTime(2026),
          ),
        ],
      ).toList();
      expect(events.length, 1);
      expect(events.first.error, contains('API anahtarınızı'));
      expect(events.first.done, isTrue);
    });

    test('buffers split MOBILE_ACTION tags in Gemini SSE without leaking',
        () async {
      final client = _StreamingMockClient(
        chunks: [
          'data: {"candidates":[{"content":{"parts":[{"text":"Tamam, kuruyorum. <MOBI"}]}}]}\n\n',
          'data: {"candidates":[{"content":{"parts":[{"text":"LE_ACTION>{\\"type\\":\\"create_timer\\","}]}}]}\n\n',
          'data: {"candidates":[{"content":{"parts":[{"text":"\\"seconds\\":120,\\"label\\":\\"Test\\"}</MOBILE_ACTION>"}]}}]}\n\n',
        ],
      );

      final deltas = StringBuffer();
      AiStreamEvent? doneEvent;

      await for (final ev in AiClient.streamChat(
        settings: const JarvisSettings(
          provider: ApiProvider.geminiDirect,
          apiKey: 'test-key',
        ),
        messages: [
          JarvisMessage(
            id: '1',
            role: 'user',
            content: '2 dk test',
            timestamp: DateTime(2026),
          ),
        ],
        client: client,
      )) {
        if (ev.delta != null) deltas.write(ev.delta);
        if (ev.done) doneEvent = ev;
      }

      expect(deltas.toString(), isNot(contains('<MOBILE_ACTION>')));
      expect(deltas.toString(), contains('Tamam, kuruyorum.'));
      expect(doneEvent, isNotNull);
      expect(doneEvent!.fullText, 'Tamam, kuruyorum.');
      expect(doneEvent.actions.length, 1);
      expect(doneEvent.actions.first['type'], 'create_timer');
      expect(doneEvent.actions.first['seconds'], 120);
    });

    test('parses OpenAI-compatible SSE chat completions cleanly', () async {
      final client = _StreamingMockClient(
        chunks: [
          'data: {"choices":[{"delta":{"content":"Merhaba "}}]}\n\n',
          'data: {"choices":[{"delta":{"content":"dünya!"}}]}\n\n',
          'data: [DONE]\n\n',
        ],
      );

      final events = await AiClient.streamChat(
        settings: const JarvisSettings(
          provider: ApiProvider.openAiCompatible,
          baseUrl: 'https://api.openai.com',
          apiKey: 'sk-test',
          model: 'gpt-4o-mini',
        ),
        messages: [
          JarvisMessage(
            id: '1',
            role: 'user',
            content: 'Selam',
            timestamp: DateTime(2026),
          ),
        ],
        client: client,
      ).toList();

      final done = events.last;
      expect(done.done, isTrue);
      expect(done.fullText, 'Merhaba dünya!');
    });

    test('JarvisSettings defaults to local cliProxyApi and round-trips JSON',
        () {
      const defaults = JarvisSettings();
      expect(defaults.provider, ApiProvider.cliProxyApi);
      expect(defaults.baseUrl, 'http://127.0.0.1:8317');
      expect(defaults.apiKey, 'sk-local');
      expect(defaults.model, 'gemini-2.5-flash');
      expect(defaults.preferStreaming, isTrue);
      expect(defaults.useProxyTts, isTrue);
      expect(defaults.azureSpeechRegion, 'westeurope');
      expect(defaults.sttMode, 'system');
      expect(defaults.liveEngine, 'turn_based');
      expect(defaults.geminiLiveVoice, 'Kore');
      expect(defaults.openAiLiveModel, 'gpt-realtime');

      final roundTrip = JarvisSettings.fromJson(defaults.toJson());
      expect(roundTrip.provider, ApiProvider.cliProxyApi);
      expect(roundTrip.baseUrl, 'http://127.0.0.1:8317');
      expect(roundTrip.apiKey, 'sk-local');
      expect(roundTrip.useProxyTts, isTrue);
      expect(roundTrip.liveEngine, 'turn_based');
      expect(roundTrip.azureSpeechRegion, 'westeurope');
      expect(roundTrip.sttMode, 'system');
      expect(roundTrip.openAiLiveModel, 'gpt-realtime');
      expect(roundTrip.proxyTtsVoice, 'tr-TR-AhmetNeural');
    });

    test('ProxyModelInfo classifies chat, image, tts and embedding models', () {
      final claude = ProxyModelInfo.classify('claude-opus-5-5', 'anthropic');
      expect(claude.category, 'chat');
      expect(claude.familyLabel, 'Claude');

      final gptImg = ProxyModelInfo.classify('gpt-image-2.5-flare', 'codex');
      expect(gptImg.category, 'image');

      final gemImg =
          ProxyModelInfo.classify('gemini-3.1-flash-image', 'gemini-script');
      expect(gemImg.category, 'image');
      expect(gemImg.familyLabel, 'Gemini');

      final tts = ProxyModelInfo.classify('gpt-4o-mini-tts', 'openai-api');
      expect(tts.category, 'tts');

      final emb = ProxyModelInfo.classify('text-embedding-3-small', 'openai');
      expect(emb.category, 'embedding');

      final ders = ProxyModelInfo.classify('dersdas-qwen3', 'openai-api');
      expect(ders.category, 'chat');
      expect(ders.familyLabel, 'DersDas');
    });

    test('testAndFetchModels parses cli-proxy-api /v1/models catalog', () async {
      String? authHeader;
      final client = _RoutingMockClient((req) async {
        authHeader = req.headers['Authorization'];
        expect(req.url.toString(), 'http://127.0.0.1:8317/v1/models');
        final payload = jsonEncode({
          'object': 'list',
          'data': [
            {'id': 'gemini-3.8-flash', 'owned_by': 'gemini'},
            {'id': 'claude-opus-5-5', 'owned_by': 'anthropic'},
            {'id': 'gpt-image-2.5-flare', 'owned_by': 'codex'},
            {'id': 'gpt-4o-mini-tts', 'owned_by': 'openai-api'},
          ],
        });
        return http.StreamedResponse(
          Stream.value(utf8.encode(payload)),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });

      final res = await AiClient.testAndFetchModels(
        const JarvisSettings(),
        client: client,
      );
      expect(res.ok, isTrue);
      expect(authHeader, 'Bearer sk-local');
      expect(res.models, [
        'gemini-3.8-flash',
        'claude-opus-5-5',
        'gpt-image-2.5-flare',
        'gpt-4o-mini-tts',
      ]);
      expect(res.detailedModels[2].category, 'image');
      expect(res.detailedModels[3].category, 'tts');
    });

    test('streamChat falls back to stream:false when cliProxyApi returns 500',
        () async {
      final streamFlags = <bool>[];
      final client = _RoutingMockClient((req) async {
        final bodyMap = jsonDecode(req.body) as Map<String, dynamic>;
        final isStream = bodyMap['stream'] == true;
        streamFlags.add(isStream);
        if (isStream) {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":{"message":"SSE error"}}')),
            500,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'Fallback yanıtı hazır.'},
                  },
                ],
              }),
            ),
          ),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });

      final events = await AiClient.streamChat(
        settings: const JarvisSettings(model: 'gemini-3.8-flash'),
        messages: [
          JarvisMessage(
            id: '1',
            role: 'user',
            content: 'Merhaba',
            timestamp: DateTime(2026),
          ),
        ],
        client: client,
      ).toList();

      expect(streamFlags, [true, false]);
      expect(events.last.done, isTrue);
      expect(events.last.error, isNull);
      expect(events.last.fullText, 'Fallback yanıtı hazır.');
    });

    test('generateImage supports /v1/images/generations and Gemini images',
        () async {
      final pngBytes = [137, 80, 78, 71];
      final b64 = base64Encode(pngBytes);
      final hitPaths = <String>[];

      final client = _RoutingMockClient((req) async {
        hitPaths.add(req.url.path);
        if (req.url.path == '/v1/images/generations') {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'data': [
                    {'b64_json': b64},
                  ],
                }),
              ),
            ),
            200,
          );
        }
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Galata görseli'},
                        {
                          'inlineData': {
                            'mimeType': 'image/png',
                            'data': b64,
                          },
                        },
                      ],
                    },
                  },
                ],
              }),
            ),
          ),
          200,
        );
      });

      final flareRes = await AiClient.generateImage(
        settings: const JarvisSettings(),
        prompt: 'Cyberpunk city',
        modelOverride: 'gpt-image-2.5-flare',
        client: client,
      );
      expect(flareRes.ok, isTrue);
      expect(flareRes.bytes, pngBytes);

      final gemRes = await AiClient.generateImage(
        settings: const JarvisSettings(),
        prompt: 'Galata tower',
        modelOverride: 'gemini-3.1-flash-image',
        client: client,
      );
      expect(gemRes.ok, isTrue);
      expect(gemRes.bytes, pngBytes);
      expect(gemRes.caption, 'Galata görseli');
      expect(hitPaths, [
        '/v1/images/generations',
        '/v1beta/models/gemini-3.1-flash-image:generateContent',
      ]);
    });
  });

  group('JarvisVoiceCatalog & RealtimeLiveSession', () {
    test('recognizes Chirp 3 HD voices and normalizes case', () {
      expect(JarvisVoiceCatalog.isChirpVoice('Kore'), isTrue);
      expect(JarvisVoiceCatalog.isChirpVoice('sulafat'), isTrue);
      expect(JarvisVoiceCatalog.isChirpVoice('tr-TR-AhmetNeural'), isFalse);
      expect(JarvisVoiceCatalog.normalizeChirpName('kore'), 'Kore');
      expect(JarvisVoiceCatalog.normalizeChirpName('ZEPHYR'), 'Zephyr');
      expect(
        JarvisVoiceCatalog.presets.any((v) => v.id == 'tr-TR-ElifNeural' || v.id == 'tr-TR-AhmetNeural'),
        isTrue,
      );
      expect(
        JarvisVoiceCatalog.openAiLiveVoices.any((v) => v.id == 'alloy'),
        isTrue,
      );
    });

    test('connectGeminiLive recovers when the ticket server is busy', () async {
      AiClient.reachabilityProbe = (_, _) async => true;
      addTearDown(() => AiClient.reachabilityProbe = null);
      var tickets = 0;
      final transport = _FakeRealtimeTransport();
      final session = await RealtimeLiveSession.connectGeminiLive(
        settings: const JarvisSettings(provider: ApiProvider.cliProxyApi,
          baseUrl: 'https://busy-proxy.test', geminiTtsKey: 'test-key'),
        httpClient: _RoutingMockClient((req) async {
          tickets++;
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 503);
        }),
        connector: (uri, headers) async {
          expect(uri.host, 'generativelanguage.googleapis.com');
          expect(headers, isEmpty);
          return transport;
        },
      );
      expect(tickets, 1);
      await session.close();
    });

    test('replayed Live call id joins the pending command and reuses its result', () async {
      final transport = _FakeRealtimeTransport();
      final session = await RealtimeLiveSession.connectGeminiLive(
        settings: const JarvisSettings(provider: ApiProvider.geminiDirect, apiKey: 'test'),
        connector: (_, _) async => transport,
      );
      final pending = Completer<String>();
      var calls = 0;
      session.onToolCommand = (_) { calls++; return pending.future; };
      final frame = jsonEncode({'toolCall': {'functionCalls': [
        {'id':'alarm-1','name':'execute_command','args':{'command':'hatırlatıcı kur'}}
      ]}});
      transport.incoming.add(frame);
      transport.incoming.add(frame);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      pending.complete('Kuruldu');
      await Future<void>.delayed(Duration.zero);
      transport.incoming.add(frame);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(transport.sentFrames.where((f) => f.contains('Kuruldu')), hasLength(3));
      await session.close();
    });

    test('connectGeminiLive provisions CLI Proxy ticket and handles audio/transcripts',
        () async {
      final transport = _FakeRealtimeTransport();
      Uri? wsUri;
      Map<String, dynamic>? wsHeaders;
      String? postedAuthBody;

      final client = _RoutingMockClient((req) async {
        expect(req.url.path, '/v1alpha/auth_tokens');
        postedAuthBody = await req.finalize().bytesToString();
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'name': 'auth_tokens/t123'}))),
          200,
        );
      });

      var ready = false;
      final audioChunks = <Uint8List>[];
      var interrupted = false;
      var userTxt = '';
      var botTxt = '';
      var turnDone = false;

      final session = await RealtimeLiveSession.connectGeminiLive(
        settings: const JarvisSettings(
          provider: ApiProvider.cliProxyApi,
          baseUrl: 'http://127.0.0.1:8317',
          apiKey: 'sk-local',
          geminiLiveVoice: 'kore',
        ),
        httpClient: client,
        connector: (uri, headers) async {
          wsUri = uri;
          wsHeaders = headers;
          return transport;
        },
        onReady: () => ready = true,
        onAudioPcmDelta: audioChunks.add,
        onInterrupted: () => interrupted = true,
        onUserTranscript: (t, {bool append = false}) =>
            userTxt = append ? '$userTxt$t' : t,
        onAssistantTranscript: (t, {bool append = false}) =>
            botTxt = append ? '$botTxt$t' : t,
        onTurnComplete: () => turnDone = true,
      );

      expect(wsUri.toString(), 'ws://127.0.0.1:8317/v1/live');
      expect(wsHeaders?['Authorization'], 'Bearer auth_tokens/t123');
      final decodedTokenReq = jsonDecode(postedAuthBody!) as Map<String, dynamic>;
      expect(decodedTokenReq['uses'], 1);
      final bidiSetup =
          decodedTokenReq['bidiGenerateContentSetup'] as Map<String, dynamic>;
      expect(bidiSetup['model'], 'models/gemini-3.8-live');

      session.sendAudioPcm(Uint8List.fromList([1, 2, 3, 4]));
      session.sendTextPrompt('Merhaba JARVIS');
      expect(transport.sentFrames.length, 2);

      transport.incoming.add(jsonEncode({'setupComplete': {}}));
      transport.incoming.add(
        jsonEncode({
          'serverContent': {
            'inputTranscription': {'text': 'Selam'},
            'outputTranscription': {'text': 'Merhaba!'},
            'modelTurn': {
              'parts': [
                {
                  'inlineData': {
                    'mimeType': 'audio/pcm;rate=24000',
                    'data': base64Encode([10, 20, 30, 40]),
                  },
                },
              ],
            },
            'turnComplete': true,
          },
        }),
      );
      transport.incoming.add(
        jsonEncode({
          'serverContent': {'interrupted': true},
        }),
      );

      await Future<void>.delayed(Duration.zero);
      expect(ready, isTrue);
      expect(userTxt, 'Selam');
      expect(botTxt, 'Merhaba!');
      expect(audioChunks.single, [10, 20, 30, 40]);
      expect(turnDone, isTrue);
      expect(interrupted, isTrue);

      await session.close();
      expect(transport.closed, isTrue);
    });

    test('connectOpenAiLive sends GA session.update and handles output_audio.delta',
        () async {
      final transport = _FakeRealtimeTransport();
      Uri? wsUri;
      Map<String, dynamic>? wsHeaders;

      var ready = false;
      final audioChunks = <Uint8List>[];
      var interrupted = false;
      var botTxt = '';
      var turnDone = false;

      final session = await RealtimeLiveSession.connectOpenAiLive(
        settings: const JarvisSettings(
          openAiLiveKey: 'sk-openai-live',
          openAiLiveModel: 'gpt-realtime',
          openAiLiveVoice: 'marin',
        ),
        connector: (uri, headers) async {
          wsUri = uri;
          wsHeaders = headers;
          return transport;
        },
        onReady: () => ready = true,
        onAudioPcmDelta: audioChunks.add,
        onInterrupted: () => interrupted = true,
        onAssistantTranscript: (t, {bool append = false}) =>
            botTxt = append ? '$botTxt$t' : t,
        onTurnComplete: () => turnDone = true,
      );

      expect(wsUri.toString(), 'wss://api.openai.com/v1/realtime?model=gpt-realtime');
      expect(wsHeaders?['Authorization'], 'Bearer sk-openai-live');
      expect(wsHeaders?.containsKey('OpenAI-Beta'), isFalse);

      final initFrame =
          jsonDecode(transport.sentFrames.first) as Map<String, dynamic>;
      expect(initFrame['type'], 'session.update');
      expect((initFrame['session'] as Map)['type'], 'realtime');

      transport.incoming.add(jsonEncode({'type': 'session.updated'}));
      transport.incoming.add(
        jsonEncode({
          'type': 'response.output_audio.delta',
          'delta': base64Encode([5, 6, 7, 8]),
        }),
      );
      transport.incoming.add(
        jsonEncode({
          'type': 'response.output_audio_transcript.delta',
          'delta': 'Hazırım efendim.',
        }),
      );
      transport.incoming.add(jsonEncode({'type': 'response.done'}));
      transport.incoming.add(
        jsonEncode({'type': 'input_audio_buffer.speech_started'}),
      );

      await Future<void>.delayed(Duration.zero);
      expect(ready, isTrue);
      expect(audioChunks.single, [5, 6, 7, 8]);
      expect(botTxt, 'Hazırım efendim.');
      expect(turnDone, isTrue);
      expect(interrupted, isTrue);

      await session.close();
      expect(transport.closed, isTrue);
    });
  });

  group('Azure & Chirp TTS / STT & Phone Control', () {
    test('synthesizeSpeech handles Google Chirp /v1beta/interactions and Azure SSML',
        () async {
      final fakeWav = Uint8List(256);
      fakeWav.setAll(0, [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]);
      final fakeMp3 = Uint8List.fromList(List.filled(256, 0xAB));
      final seenUris = <String>[];
      String? azureSsmlBody;
      Map<String, String>? azureHeaders;

      final client = _RoutingMockClient((req) async {
        seenUris.add(req.url.toString());
        if (req.url.path == '/v1beta/interactions') {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'steps': [
                    {
                      'content': [
                        {'type': 'audio', 'data': base64Encode(fakeWav)},
                      ],
                    },
                  ],
                }),
              ),
            ),
            200,
          );
        }
        azureHeaders = req.headers;
        azureSsmlBody = utf8.decode(await req.finalize().toBytes());
        return http.StreamedResponse(Stream.value(fakeMp3), 200);
      });

      final chirpOut = await AiClient.synthesizeSpeech(
        settings: const JarvisSettings(
          provider: ApiProvider.cliProxyApi,
          baseUrl: 'http://127.0.0.1:8317',
          proxyTtsVoice: 'Kore',
        ),
        text: 'Merhaba dünya',
        client: client,
      );
      expect(chirpOut, isNotNull);
      expect(chirpOut!.ext, 'wav');
      expect(chirpOut.bytes.length, 256);

      final azureOut = await AiClient.synthesizeSpeech(
        settings: const JarvisSettings(
          provider: ApiProvider.cliProxyApi,
          azureSpeechKey: 'az-secret-key',
          azureSpeechRegion: 'westeurope',
          proxyTtsVoice: 'elif',
        ),
        text: 'Sistem hazır.',
        client: client,
      );
      expect(azureOut, isNotNull);
      expect(azureOut!.ext, 'mp3');
      expect(azureOut.bytes, fakeMp3);
      expect(
        seenUris,
        contains(
          'https://westeurope.tts.speech.microsoft.com/cognitiveservices/v1',
        ),
      );
      expect(azureHeaders?['Ocp-Apim-Subscription-Key'], 'az-secret-key');
      expect(azureSsmlBody, contains('tr-TR-Elif:MAI-Voice-2-Flash'));
    });

    test('LocalCommandEngine.executeStructuredAction invokes Android MethodChannel phone controls',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('com.jarvis.assistant/device');
      final recordedCalls = <(String method, Map<String, dynamic> args)>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        final args = Map<String, dynamic>.from(
          (call.arguments as Map?) ?? const {},
        );
        recordedCalls.add((call.method, args));
        switch (call.method) {
          case 'setFlashlight':
          case 'setVolumeLevel':
          case 'setSystemAlarm':
          case 'openSystemSettings':
          case 'controlMedia':
            return true;
          case 'launchApp':
            return 'WhatsApp';
          default:
            return null;
        }
      });

      try {
        final delegate = _FakeDelegate();
        final flashBanner = await LocalCommandEngine.executeStructuredAction(
          {'type': 'flashlight', 'enabled': true},
          delegate,
        );
        final appBanner = await LocalCommandEngine.executeStructuredAction(
          {'type': 'launch_app', 'app': 'WhatsApp'},
          delegate,
        );
        final volBanner = await LocalCommandEngine.executeStructuredAction(
          {'type': 'set_volume', 'stream': 'media', 'percent': 80},
          delegate,
        );
        final alarmBanner = await LocalCommandEngine.executeStructuredAction(
          {'type': 'set_alarm', 'hour': 7, 'minute': 30, 'message': 'Uyan'},
          delegate,
        );
        final settingsBanner = await LocalCommandEngine.executeStructuredAction(
          {'type': 'open_settings', 'target': 'wifi'},
          delegate,
        );
        final smsBanner = await LocalCommandEngine.executeStructuredAction(
          {'type': 'send_sms', 'number': '+905551112233', 'body': 'Selam'},
          delegate,
        );

        expect(flashBanner, '🔦 El feneri açıldı');
        expect(appBanner, '🚀 WhatsApp açıldı');
        expect(volBanner, '🔊 Ses %80 (media)');
        expect(alarmBanner, '⏰ Sistem alarmı: 07:30 (Uyan)');
        expect(settingsBanner, '⚙️ Ayarlar açıldı (wifi)');
        expect(smsBanner, '💬 SMS hazırlandı: +905551112233');

        expect(
          recordedCalls.map((e) => e.$1).toList(),
          [
            'setFlashlight',
            'launchApp',
            'setVolumeLevel',
            'setSystemAlarm',
            'openSystemSettings',
          ],
        );
        expect(recordedCalls[0].$2['enabled'], isTrue);
        expect(recordedCalls[1].$2['query'], 'WhatsApp');
        expect(recordedCalls[2].$2['percent'], 80);
        expect(recordedCalls[3].$2['hour'], 7);
        expect(recordedCalls[3].$2['minute'], 30);
        expect(recordedCalls[4].$2['target'], 'wifi');
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    });
  });

  group('Cloud TTS Routing, Migration, Diagnostics & Chunking', () {
    test('JarvisSettings migrates legacy pre-v3 useProxyTts=false to cloud auto mode',
        () {
      final legacy = JarvisSettings.fromJson({
        'provider': 'cliProxyApi',
        'useProxyTts': false,
        'baseUrl': 'http://127.0.0.1:8317',
      });
      expect(legacy.useProxyTts, isTrue);
      expect(legacy.ttsEngine, 'auto');

      final migratedFromV3 = JarvisSettings.fromJson({
        'settingsVersion': 3,
        'provider': 'cliProxyApi',
        'useProxyTts': false,
        'ttsEngine': 'device',
      });
      expect(migratedFromV3.useProxyTts, isTrue);
      expect(migratedFromV3.ttsEngine, 'auto');

      final explicitDevice = JarvisSettings.fromJson({
        'settingsVersion': 4,
        'provider': 'cliProxyApi',
        'useProxyTts': false,
        'ttsEngine': 'device',
      });
      expect(explicitDevice.useProxyTts, isFalse);
      expect(explicitDevice.ttsEngine, 'device');

      final roundTrip = const JarvisSettings(
        ttsEngine: 'gemini',
        ttsProxyUrl: 'http://192.168.1.10:8317',
        geminiTtsKey: 'AIzaTest123',
        googleCloudTtsKey: 'AIzaGcp456',
        openAiTtsKey: 'sk-test-tts',
        agentTools: false,
      );
      final restored = JarvisSettings.fromJson(roundTrip.toJson());
      expect(restored.ttsEngine, 'gemini');
      expect(restored.ttsProxyUrl, 'http://192.168.1.10:8317');
      expect(restored.geminiTtsKey, 'AIzaTest123');
      expect(restored.googleCloudTtsKey, 'AIzaGcp456');
      expect(restored.openAiTtsKey, 'sk-test-tts');
      expect(restored.agentTools, isFalse);
    });

    test('AiClient.ttsProviderOrder and synthesizeSpeechDetailed fall back and log attempts',
        () async {
      expect(
        AiClient.ttsProviderOrder(const JarvisSettings(ttsEngine: 'device'), 'Kore'),
        isEmpty,
      );
      final chirpOrder = AiClient.ttsProviderOrder(
        const JarvisSettings(ttsEngine: 'auto'),
        'Kore',
      );
      expect(chirpOrder.first, anyOf('proxy_gemini', 'gemini'));
      expect(chirpOrder, containsAll(['proxy', 'edge_neural', 'azure', 'gemini', 'google_cloud', 'openai', 'google_translate']));

      final fakeMp3 = Uint8List.fromList(
        [0x49, 0x44, 0x33, ...List.filled(320, 0x22)],
      );
      final seenPaths = <String>[];

      final client = _RoutingMockClient((req) async {
        seenPaths.add('${req.url.host}:${req.url.path}');
        if (req.url.host == '127.0.0.1') {
          return http.StreamedResponse(
            Stream.value(utf8.encode('proxy down')),
            502,
          );
        }
        if (req.url.host == 'api.openai.com') {
          return http.StreamedResponse(
            Stream.value(fakeMp3),
            200,
            headers: {'content-type': 'audio/mpeg'},
          );
        }
        return http.StreamedResponse(Stream.value(utf8.encode('skip')), 401);
      });

      final res = await AiClient.synthesizeSpeechDetailed(
        settings: const JarvisSettings(
          provider: ApiProvider.cliProxyApi,
          baseUrl: 'http://127.0.0.1:8317',
          ttsEngine: 'auto',
          proxyTtsVoice: 'alloy',
          openAiTtsKey: 'sk-openai-fallback',
        ),
        text: 'Yedek bulut ses testi.',
        useCache: false,
        client: client,
      );

      expect(res.ok, isTrue);
      expect(res.provider, 'OpenAI TTS');
      expect(res.ext, 'mp3');
      expect(res.bytes, fakeMp3);
      expect(res.attempts, isNotEmpty);
      expect(res.attempts.any((a) => a.ok && a.provider == 'OpenAI TTS'), isTrue);

      final diag = await AiClient.diagnoseTts(
        settings: const JarvisSettings(
          baseUrl: 'http://127.0.0.1:8317',
          openAiTtsKey: 'sk-openai-fallback',
        ),
        client: client,
      );
      expect(diag.length, 7);
      expect(diag.where((a) => a.ok).map((a) => a.provider), ['OpenAI TTS']);
      expect(seenPaths, contains('api.openai.com:/v1/audio/speech'));
    });

    test('VoiceService.cleanForSpeech and splitForTts chunk long markdown responses cleanly',
        () {
      final cleaned = VoiceService.cleanForSpeech(
        '# Başlık\n\nMerhaba **efendim**, [link](https://example.com) ve `kod`. ```dart\nprint(1);\n```',
      );
      expect(cleaned, isNot(contains('#')));
      expect(cleaned, isNot(contains('https://example.com')));
      expect(cleaned, contains('Merhaba efendim'));
      expect(cleaned, contains('kod bloğu'));

      final longText = List.generate(
        8,
        (i) => 'Cümle ${i + 1} oldukça bilgilendirici bir açıklamadır ve yeterli uzunluktadır.',
      ).join(' ');
      final chunks = VoiceService.splitForTts(longText, firstLen: 90, maxLen: 160);
      expect(chunks.length, greaterThan(2));
      expect(chunks.first.length, lessThanOrEqualTo(90));
      for (final c in chunks.skip(1)) {
        expect(c.length, lessThanOrEqualTo(160));
      }
    });

    test('EdgeTtsClient.generateSecMsGecV2 matches exact test vectors and resolves Turkish voices',
        () {
      expect(
        EdgeTtsClient.generateSecMsGecV2(unixTimestamp: 1700000000.0),
        '2CD23A2CA0B2595A-F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2',
      );
      expect(
        EdgeTtsClient.generateSecMsGecV2(unixTimestamp: 1763250000.0),
        '9F0E9F361B0FF2E5-C602F450A120F4DD451D9A2A011DDDFFDB8A26BDF1E711CCF6CE96575FB9CAD2',
      );

      expect(
        EdgeTtsClient.resolveEdgeVoice('tr-TR-AhmetNeural', isFemale: false),
        'tr-TR-AhmetNeural',
      );
      expect(
        EdgeTtsClient.resolveEdgeVoice('elif', isFemale: true),
        'tr-TR-EmelNeural',
      );
      expect(
        EdgeTtsClient.resolveEdgeVoice('aydın', isFemale: false),
        'tr-TR-AhmetNeural',
      );
      expect(
        EdgeTtsClient.resolveEdgeVoice('chirp:Kore', isFemale: true),
        'tr-TR-EmelNeural',
      );
      expect(
        EdgeTtsClient.resolveEdgeVoice('chirp:Charon', isFemale: false),
        'tr-TR-AhmetNeural',
      );
    });

    test('VoiceService.speak plays Edge Neural directly and falls back to device TTS once on cloud failure',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const deviceChannel = MethodChannel('com.jarvis.assistant/device');
      const ttsChannel = MethodChannel('flutter_tts');
      final deviceCalls = <String>[];
      final localTtsCalls = <String>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(deviceChannel, (call) async {
        deviceCalls.add(call.method);
        if (call.method == 'playAudioBytes') return true;
        return true;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ttsChannel, (call) async {
        localTtsCalls.add(call.method);
        if (call.method == 'speak') {
          Future<void>.microtask(() {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .handlePlatformMessage(
              'flutter_tts',
              const StandardMethodCodec()
                  .encodeMethodCall(const MethodCall('speak.onComplete')),
              (_) {},
            );
          });
        }
        return 1;
      });

      final fakeMp3 = Uint8List.fromList([0x49, 0x44, 0x33, ...List.filled(300, 0x55)]);
      EdgeTtsClient.testSynthesizer = (text, voice, rate) async =>
          (bytes: fakeMp3, ext: 'mp3', error: '');

      final failClient = _RoutingMockClient(
        (req) async => http.StreamedResponse(Stream.value(utf8.encode('err')), 503),
      );

      try {
        final voice = VoiceService();
        // 1. Direct Edge Neural succeeds without any API keys
        await voice.speak(
          'Merhaba efendim.',
          settings: const JarvisSettings(ttsEngine: 'edge_neural'),
          httpClient: failClient,
        );
        expect(voice.lastEngineUsed, 'Edge Neural Doğrudan (Ahmet/Emel)');
        expect(deviceCalls, contains('playAudioBytes'));
        expect(localTtsCalls, isEmpty);

        // 2. When all cloud providers fail in auto mode, fall back to device TTS once
        EdgeTtsClient.testSynthesizer = (text, voice, rate) async =>
            (bytes: null, ext: 'mp3', error: 'offline');
        await voice.speak(
          'Bu mesaj çevrimdışı test içindir.',
          settings: const JarvisSettings(ttsEngine: 'auto'),
          httpClient: failClient,
        );
        expect(voice.lastEngineUsed, 'Cihaz TTS (yedek)');
        expect(voice.lastError, isNotNull);
        expect(localTtsCalls.where((c) => c == 'speak'), hasLength(1));
      } finally {
        EdgeTtsClient.testSynthesizer = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(deviceChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ttsChannel, null);
      }
    });
  });

  group('Extended Offline Phone, Download & Research Commands', () {
    test('routes file download, video download, deep research and app management offline',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('com.jarvis.assistant/device');
      final recorded = <(String method, Map<String, dynamic> args)>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        recorded.add(
          (call.method, Map<String, dynamic>.from((call.arguments as Map?) ?? {})),
        );
        if (call.method == 'setBrightness' || call.method == 'setRingerMode') {
          return 'OK';
        }
        return true;
      });

      try {
        final del = _FakeDelegate();

        final fileRes = await LocalCommandEngine.tryHandle(
          'https://example.com/belge.pdf indir',
          del,
        );
        expect(fileRes.handled, isTrue);
        expect(del.downloadedFiles.single.$1, 'https://example.com/belge.pdf');

        final vidRes = await LocalCommandEngine.tryHandle(
          'https://example.com/izle videosunu indir',
          del,
        );
        expect(vidRes.handled, isTrue);
        expect(del.downloadedVideos.single, 'https://example.com/izle');

        final resRes = await LocalCommandEngine.tryHandle(
          'kuantum bilgisayarlar hakkında derin araştırma yap',
          del,
        );
        expect(resRes.handled, isTrue);
        expect(del.startedResearches.single, 'kuantum bilgisayarlar');

        final appsRes = await LocalCommandEngine.tryHandle(
          'uygulamaları listele',
          del,
        );
        expect(appsRes.handled, isTrue);
        expect(appsRes.reply, contains('WhatsApp'));
        expect(del.openedTab, 2);
        expect(del.openedSubTab, 3);

        expect(LocalCommandEngine.waNumber('0555 111 22 33'), '905551112233');
        expect(LocalCommandEngine.waNumber('+90 (532) 000 11 22'), '905320001122');

        final panelBanner = await LocalCommandEngine.executeStructuredAction(
          {'type': 'open_panel', 'panel': 'wifi'},
          del,
        );
        final ringerBanner = await LocalCommandEngine.executeStructuredAction(
          {'type': 'ringer_mode', 'mode': 'silent'},
          del,
        );
        final brightBanner = await LocalCommandEngine.executeStructuredAction(
          {'type': 'set_brightness', 'percent': 45},
          del,
        );
        expect(panelBanner, isNotNull);
        expect(ringerBanner, isNotNull);
        expect(brightBanner, isNotNull);
        expect(
          recorded.map((e) => e.$1),
          containsAll(['openSettingsPanel', 'setRingerMode', 'setBrightness']),
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    });
  });
}
