import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/jarvis_models.dart';
import 'ai_client.dart';

enum RealtimeEngine {
  geminiLive,
  openAiLive,
}

abstract interface class RealtimeTransport {
  Stream<dynamic> get stream;
  void sendText(String data);
  Future<void> close();
}

class _IoWebSocketTransport implements RealtimeTransport {
  final WebSocket _ws;

  _IoWebSocketTransport(this._ws);

  @override
  Stream<dynamic> get stream => _ws;

  @override
  void sendText(String data) {
    _ws.add(data);
  }

  @override
  Future<void> close() async {
    await _ws.close(WebSocketStatus.normalClosure, 'closed');
  }
}

typedef RealtimeTransportConnector = Future<RealtimeTransport> Function(
  Uri uri,
  Map<String, dynamic> headers,
);

class RealtimeLiveSession {
  final RealtimeEngine engine;
  final RealtimeTransport _transport;
  StreamSubscription<dynamic>? _sub;
  bool _closed = false;
  bool _readyNotified = false;

  /// Gemini Live oturum devam tanıtıcısı: bağlantı koparsa (ya da sunucu
  /// "goAway" derse) aynı konuşmaya bununla yeniden bağlanılır.
  String? resumeHandle;

  void Function()? onReady;
  void Function(Uint8List pcmBytes)? onAudioPcmDelta;
  void Function()? onInterrupted;
  void Function(String text, {bool append})? onUserTranscript;
  void Function(String text, {bool append})? onAssistantTranscript;
  void Function()? onTurnComplete;
  void Function(String message)? onError;
  void Function()? onClosed;

  /// Executes a phone command requested by the live model (Gemini Live
  /// `execute_command` tool, like the Windows JARVIS `execute_work`). Returns
  /// the Turkish result that is sent back to the model.
  Future<String> Function(String command)? onToolCommand;
  final _toolResults = <String, Future<String>>{};

  /// Tool declaration sent in the Gemini Live setup.
  static const Map<String, dynamic> executeCommandTool = {
    'functionDeclarations': [
      {
        'name': 'execute_command',
        'description':
            'Kullanıcının telefonda yapılmasını AÇIKÇA istediği işlemi yürütür: sayaç/hatırlatıcı kur, '
                'el feneri, uygulama aç, YouTube\'da müzik çal, not al, hafızaya kaydet, arama, mesaj, '
                'parlaklık/ses, belge, tablo veya kaynak kod projesi oluştur, web araştırması. Komutu kullanıcının söylediği gibi '
                'Türkçe ve değiştirmeden ilet. Bilgi sorularında kullanma.',
        'parameters': {
          'type': 'OBJECT',
          'properties': {
            'command': {
              'type': 'STRING',
              'description': 'Kullanıcının Türkçe komutu (aynen).',
            },
          },
          'required': ['command'],
        },
      },
    ],
  };

  RealtimeLiveSession._(this.engine, this._transport) {
    _sub = _transport.stream.listen(
      _handleIncomingFrame,
      onError: (Object err) {
        if (!_closed) {
          onError?.call('Canlı ses bağlantı hatası: $err');
        }
      },
      onDone: () {
        if (!_closed) {
          _closed = true;
          onClosed?.call();
        }
      },
    );
  }

  bool get isClosed => _closed;

  static Future<RealtimeTransport> _defaultConnector(
    Uri uri,
    Map<String, dynamic> headers,
  ) async {
    final ws = await WebSocket.connect(uri.toString(), headers: headers)
        .timeout(const Duration(seconds: 15));
    return _IoWebSocketTransport(ws);
  }

  static String _toWsBase(String rawHttpBase) {
    var s = AiClient.normalizedOpenAiBase(rawHttpBase);
    if (s.startsWith('https://')) {
      s = 'wss://${s.substring(8)}';
    } else if (s.startsWith('http://')) {
      s = 'ws://${s.substring(7)}';
    }
    return s;
  }

  static Future<RealtimeLiveSession> connectGeminiLive({
    required JarvisSettings settings,
    http.Client? httpClient,
    RealtimeTransportConnector? connector,
    String? resumeHandle,
    void Function()? onReady,
    void Function(Uint8List pcmBytes)? onAudioPcmDelta,
    void Function()? onInterrupted,
    void Function(String text, {bool append})? onUserTranscript,
    void Function(String text, {bool append})? onAssistantTranscript,
    void Function()? onTurnComplete,
    void Function(String message)? onError,
    void Function()? onClosed,
  }) async {
    final voiceName = JarvisVoiceCatalog.normalizeChirpName(
      settings.geminiLiveVoice.trim().isNotEmpty
          ? settings.geminiLiveVoice
          : (JarvisVoiceCatalog.isChirpVoice(settings.proxyTtsVoice)
              ? settings.proxyTtsVoice
              : 'Kore'),
    );

    final bidiSetup = <String, dynamic>{
      'model': 'models/gemini-3.8-live',
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {'voiceName': voiceName},
          },
        },
      },
      'systemInstruction': {
        'parts': [
          {
            'text': '${AiClient.buildSystemPrompt(settings)}\n\n'
                'CANLI SES MODU: Yanıtların 1-3 kısa cümle olsun, Markdown kullanma. Telefonda bir işlem '
                'gerektiğinde MOBILE_ACTION etiketi YAZMA; bunun yerine execute_command aracını kullanıcının '
                'komutuyla çağır ve sonucu kısaca söyle.',
          },
        ],
      },
      'inputAudioTranscription': <String, dynamic>{},
      'outputAudioTranscription': <String, dynamic>{},
      'tools': [RealtimeLiveSession.executeCommandTool],
      // Telefon hoparlörü / ortam gürültüsü konuşma sanılıp yanıtı kesmesin;
      // 0,7 sn sessizlik turun bittiğini gösterir (gerçek API'de denendi).
      'realtimeInputConfig': {
        'automaticActivityDetection': {
          'startOfSpeechSensitivity': 'START_SENSITIVITY_LOW',
          'endOfSpeechSensitivity': 'END_SENSITIVITY_LOW',
          'prefixPaddingMs': 200,
          'silenceDurationMs': 700,
        },
      },
      // Oturum devamı + kayan bağlam penceresi: ~10-15 dk sınırında kopmasın.
      'sessionResumption': {'handle': ?resumeHandle},
      'contextWindowCompression': {'slidingWindow': <String, dynamic>{}},
    };

    final wsConnect = connector ?? _defaultConnector;
    late final RealtimeTransport transport;
    var needsSetupFrame = false;

    var direct = settings.provider == ApiProvider.geminiDirect;
    var directKey = settings.apiKey.trim();
    if (!direct && settings.autoFallbackGemini && settings.geminiTtsKey.trim().isNotEmpty) {
      final reachable = !AiClient.isLoopbackUrl(settings.baseUrl) &&
          await AiClient.proxyReachable(settings.baseUrl);
      if (!reachable) {
        direct = true;
        directKey = settings.geminiTtsKey.trim();
      }
    }

    Future<RealtimeTransport> connectDirect(String apiKey) async {
      if (apiKey.isEmpty) {
        throw StateError(
          'Gemini Live için Ayarlar > API Anahtarı bölümüne Gemini anahtarı girin.',
        );
      }
      final uri = Uri.parse(
        'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${Uri.encodeQueryComponent(apiKey)}',
      );
      needsSetupFrame = true;
      return wsConnect(uri, const {});
    }

    if (direct) {
      transport = await connectDirect(directKey);
    } else {
      final client = httpClient ?? http.Client();
      final ownsClient = httpClient == null;
      try {
        final httpBase = AiClient.normalizedOpenAiBase(settings.baseUrl);
        final bearer = AiClient.effectiveBearerKey(settings);
        final tokenRes = await client
            .post(
              Uri.parse('$httpBase/v1alpha/auth_tokens'),
              headers: {
                'Content-Type': 'application/json',
                if (bearer.isNotEmpty) 'Authorization': 'Bearer $bearer',
              },
              body: jsonEncode({
                'uses': 1,
                'bidiGenerateContentSetup': bidiSetup,
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (AiClient.isTransientStatus(tokenRes.statusCode) &&
            settings.autoFallbackGemini && settings.geminiTtsKey.trim().isNotEmpty) {
          transport = await connectDirect(settings.geminiTtsKey.trim());
        } else {
          final tokenBody = utf8.decode(tokenRes.bodyBytes, allowMalformed: true);
          if (tokenRes.statusCode != 200) {
            throw StateError(
              'CLI Proxy Gemini Live oturumu başlatılamadı (HTTP ${tokenRes.statusCode}): $tokenBody',
            );
          }
          final decoded = jsonDecode(tokenBody);
          final ticket = (decoded is Map ? decoded['name'] : '')?.toString() ?? '';
          if (ticket.isEmpty) {
            throw StateError('CLI Proxy Live bileti alınamadı.');
          }
  
          final wsBase = _toWsBase(settings.baseUrl);
          final uri = Uri.parse('$wsBase/v1/live');
          transport = await wsConnect(uri, {'Authorization': 'Bearer $ticket'});
        }
      } finally {
        if (ownsClient) client.close();
      }
    }

    final session = RealtimeLiveSession._(
      RealtimeEngine.geminiLive,
      transport,
    )
      ..onReady = onReady
      ..onAudioPcmDelta = onAudioPcmDelta
      ..onInterrupted = onInterrupted
      ..onUserTranscript = onUserTranscript
      ..onAssistantTranscript = onAssistantTranscript
      ..onTurnComplete = onTurnComplete
      ..onError = onError
      ..onClosed = onClosed;

    if (needsSetupFrame) {
      transport.sendText(jsonEncode({'setup': bidiSetup}));
    }
    return session;
  }

  static Future<RealtimeLiveSession> connectOpenAiLive({
    required JarvisSettings settings,
    RealtimeTransportConnector? connector,
    void Function()? onReady,
    void Function(Uint8List pcmBytes)? onAudioPcmDelta,
    void Function()? onInterrupted,
    void Function(String text, {bool append})? onUserTranscript,
    void Function(String text, {bool append})? onAssistantTranscript,
    void Function()? onTurnComplete,
    void Function(String message)? onError,
    void Function()? onClosed,
  }) async {
    final openAiKey = settings.openAiLiveKey.trim().isNotEmpty
        ? settings.openAiLiveKey.trim()
        : (settings.provider == ApiProvider.openAiCompatible
            ? settings.apiKey.trim()
            : '');
    if (openAiKey.isEmpty) {
      throw StateError(
        'OpenAI Live için Ayarlar bölümünden OpenAI Realtime API anahtarını (sk-...) girin.',
      );
    }

    final model = settings.openAiLiveModel.trim().isEmpty
        ? 'gpt-realtime'
        : settings.openAiLiveModel.trim();
    final voice = settings.openAiLiveVoice.trim().isEmpty
        ? 'alloy'
        : settings.openAiLiveVoice.trim();
    var rawUrl = settings.openAiLiveUrl.trim().isEmpty
        ? 'wss://api.openai.com/v1/realtime'
        : settings.openAiLiveUrl.trim();
    if (rawUrl.startsWith('https://')) {
      rawUrl = 'wss://${rawUrl.substring(8)}';
    } else if (rawUrl.startsWith('http://')) {
      rawUrl = 'ws://${rawUrl.substring(7)}';
    }
    final parsed = Uri.parse(rawUrl);
    final queryParams = Map<String, String>.from(parsed.queryParameters);
    queryParams.putIfAbsent('model', () => model);
    final uri = parsed.replace(queryParameters: queryParams);

    final isBetaPreview = model.toLowerCase().contains('preview');
    final headers = <String, dynamic>{
      'Authorization': 'Bearer $openAiKey',
      if (isBetaPreview) 'OpenAI-Beta': 'realtime=v1',
    };

    final wsConnect = connector ?? _defaultConnector;
    final transport = await wsConnect(uri, headers);

    final session = RealtimeLiveSession._(
      RealtimeEngine.openAiLive,
      transport,
    )
      ..onReady = onReady
      ..onAudioPcmDelta = onAudioPcmDelta
      ..onInterrupted = onInterrupted
      ..onUserTranscript = onUserTranscript
      ..onAssistantTranscript = onAssistantTranscript
      ..onTurnComplete = onTurnComplete
      ..onError = onError
      ..onClosed = onClosed;

    final instructions = AiClient.buildSystemPrompt(settings);
    final sessionPayload = isBetaPreview
        ? {
            'type': 'session.update',
            'session': {
              'modalities': ['audio', 'text'],
              'instructions': instructions,
              'voice': voice,
              'input_audio_format': 'pcm16',
              'output_audio_format': 'pcm16',
              'input_audio_transcription': {'model': 'gpt-4o-mini-transcribe'},
              'turn_detection': {'type': 'server_vad'},
            },
          }
        : {
            'type': 'session.update',
            'session': {
              'type': 'realtime',
              'instructions': instructions,
              'output_modalities': ['audio'],
              'audio': {
                'input': {
                  'format': {'type': 'audio/pcm', 'rate': 24000},
                  'transcription': {'model': 'gpt-4o-mini-transcribe'},
                  'turn_detection': {'type': 'server_vad'},
                },
                'output': {
                  'format': {'type': 'audio/pcm', 'rate': 24000},
                  'voice': voice,
                },
              },
            },
          };

    transport.sendText(jsonEncode(sessionPayload));
    return session;
  }

  void sendAudioPcm(Uint8List pcmBytes) {
    if (_closed || pcmBytes.isEmpty) return;
    final b64 = base64Encode(pcmBytes);
    if (engine == RealtimeEngine.geminiLive) {
      _transport.sendText(
        jsonEncode({
          'realtimeInput': {
            'audio': {
              'data': b64,
              'mimeType': 'audio/pcm;rate=16000',
            },
          },
        }),
      );
    } else {
      _transport.sendText(
        jsonEncode({
          'type': 'input_audio_buffer.append',
          'audio': b64,
        }),
      );
    }
  }

  void sendTextPrompt(String text) {
    final trimmed = text.trim();
    if (_closed || trimmed.isEmpty) return;
    if (engine == RealtimeEngine.geminiLive) {
      _transport.sendText(
        jsonEncode({
          'realtimeInput': {'text': trimmed},
        }),
      );
    } else {
      _transport.sendText(
        jsonEncode({
          'type': 'conversation.item.create',
          'item': {
            'type': 'message',
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': trimmed},
            ],
          },
        }),
      );
      _transport.sendText(jsonEncode({'type': 'response.create'}));
    }
  }

  void sendImagePrompt({
    required Uint8List jpegBytes,
    required String prompt,
  }) {
    if (_closed || jpegBytes.isEmpty) return;
    final b64 = base64Encode(jpegBytes);
    if (engine == RealtimeEngine.geminiLive) {
      _transport.sendText(
        jsonEncode({
          'realtimeInput': {
            'video': {
              'data': b64,
              'mimeType': 'image/jpeg',
            },
          },
        }),
      );
      if (prompt.trim().isNotEmpty) {
        sendTextPrompt(prompt.trim());
      }
    } else {
      _transport.sendText(
        jsonEncode({
          'type': 'conversation.item.create',
          'item': {
            'type': 'message',
            'role': 'user',
            'content': [
              {
                'type': 'input_text',
                'text': prompt.trim().isEmpty
                    ? 'Kameradaki görüntüyü Türkçe anlat.'
                    : prompt.trim(),
              },
              {
                'type': 'input_image',
                'image_url': 'data:image/jpeg;base64,$b64',
              },
            ],
          },
        }),
      );
      _transport.sendText(jsonEncode({'type': 'response.create'}));
    }
  }

  void _handleIncomingFrame(dynamic rawFrame) {
    if (_closed) return;
    String rawText;
    if (rawFrame is String) {
      rawText = rawFrame;
    } else if (rawFrame is List<int>) {
      rawText = utf8.decode(rawFrame, allowMalformed: true);
    } else {
      return;
    }

    Map<String, dynamic>? msg;
    try {
      final decoded = jsonDecode(rawText);
      if (decoded is Map<String, dynamic>) msg = decoded;
    } catch (_) {}
    if (msg == null) return;

    if (engine == RealtimeEngine.geminiLive) {
      _handleGeminiEvent(msg);
    } else {
      _handleOpenAiEvent(msg);
    }
  }

  void _handleGeminiEvent(Map<String, dynamic> msg) {
    if (msg['error'] is Map) {
      final errMsg =
          msg['error']['message']?.toString() ?? 'Gemini Live sunucu hatası';
      onError?.call(errMsg);
      return;
    }
    if (msg.containsKey('setupComplete')) {
      if (!_readyNotified) {
        _readyNotified = true;
        onReady?.call();
      }
    }
    final resume = msg['sessionResumptionUpdate'];
    if (resume is Map && resume['newHandle'] is String && (resume['newHandle'] as String).isNotEmpty) {
      resumeHandle = resume['newHandle'] as String;
    }
    final toolCall = msg['toolCall'];
    if (toolCall is Map && toolCall['functionCalls'] is List) {
      _handleGeminiToolCalls((toolCall['functionCalls'] as List).whereType<Map>().toList());
    }
    final sc = msg['serverContent'];
    if (sc is Map) {
      if (sc['interrupted'] == true) {
        onInterrupted?.call();
      }
      final interim = sc['interimInputTranscription'];
      if (interim is Map && interim['text'] != null) {
        onUserTranscript?.call(interim['text'].toString(), append: false);
      }
      final inputTr = sc['inputTranscription'];
      if (inputTr is Map && inputTr['text'] != null) {
        onUserTranscript?.call(inputTr['text'].toString(), append: true);
      }
      final outTr = sc['outputTranscription'];
      if (outTr is Map && outTr['text'] != null) {
        onAssistantTranscript?.call(outTr['text'].toString(), append: true);
      }
      final modelTurn = sc['modelTurn'];
      if (modelTurn is Map) {
        final parts = modelTurn['parts'];
        if (parts is List) {
          for (final p in parts.whereType<Map>()) {
            final inl = p['inlineData'];
            if (inl is Map && inl['data'] != null) {
              try {
                final bytes = base64Decode(inl['data'].toString());
                if (bytes.isNotEmpty) {
                  onAudioPcmDelta?.call(bytes);
                }
              } catch (_) {}
            }
            if (p['text'] != null && outTr == null) {
              onAssistantTranscript?.call(p['text'].toString(), append: true);
            }
          }
        }
      }
      if (sc['turnComplete'] == true) {
        onTurnComplete?.call();
      }
    }
  }

  Future<void> _handleGeminiToolCalls(List<Map> calls) async {
    final responses = <Map<String, dynamic>>[];
    for (final call in calls) {
      final name = call['name']?.toString() ?? '';
      final args = call['args'] is Map ? call['args'] as Map : const {};
      var result = 'Bu araç desteklenmiyor.';
      if (name == 'execute_command') {
        final command = args['command']?.toString().trim() ?? '';
        final handler = onToolCommand;
        if (command.isEmpty) {
          result = 'Komut boş.';
        } else if (handler == null) {
          result = 'Telefon komutları bu oturumda kapalı.';
        } else {
          try {
            final id = call['id']?.toString() ?? '';
            result = id.isEmpty ? await handler(command) :
                await _toolResults.putIfAbsent(id, () => Future.sync(() => handler(command)));
          } catch (e) {
            result = 'Komut yürütülemedi: $e';
          }
        }
      }
      responses.add({
        if (call['id'] != null) 'id': call['id'],
        'name': name,
        'response': {'result': result},
      });
    }
    if (_closed) return;
    _transport.sendText(jsonEncode({
      'toolResponse': {'functionResponses': responses},
    }));
  }

  /// True when [command] really comes from what the user said (substring or
  /// >=70% word overlap), blocking commands injected by web/model content.
  static bool commandMatchesTranscript(String command, String transcript) {
    String norm(String v) => v
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll(RegExp(r"[^a-z0-9çğöşü ]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final c = norm(command);
    final t = norm(transcript);
    if (c.isEmpty || t.isEmpty) return false;
    if (t.contains(c) || c.contains(t)) return true;
    final cw = c.split(' ').where((w) => w.length > 1).toSet();
    final tw = t.split(' ').where((w) => w.length > 1).toSet();
    if (cw.isEmpty) return false;
    final hit = cw.where((w) => tw.any((x) => x.startsWith(w) || w.startsWith(x))).length;
    return hit / cw.length >= 0.7;
  }

  void _handleOpenAiEvent(Map<String, dynamic> msg) {
    final type = msg['type']?.toString() ?? '';
    switch (type) {
      case 'session.created':
      case 'session.updated':
        if (!_readyNotified) {
          _readyNotified = true;
          onReady?.call();
        }
      case 'input_audio_buffer.speech_started':
        onInterrupted?.call();
        onUserTranscript?.call('', append: false);
      case 'conversation.item.input_audio_transcription.delta':
        final delta = msg['delta']?.toString() ?? '';
        if (delta.isNotEmpty) {
          onUserTranscript?.call(delta, append: true);
        }
      case 'conversation.item.input_audio_transcription.completed':
        final tr = msg['transcript']?.toString() ?? '';
        if (tr.isNotEmpty) {
          onUserTranscript?.call(tr, append: false);
        }
      case 'response.output_audio.delta':
      case 'response.audio.delta':
        final delta = msg['delta']?.toString() ?? '';
        if (delta.isNotEmpty) {
          try {
            final pcm = base64Decode(delta);
            if (pcm.isNotEmpty) onAudioPcmDelta?.call(pcm);
          } catch (_) {}
        }
      case 'response.output_audio_transcript.delta':
      case 'response.audio_transcript.delta':
      case 'response.output_text.delta':
      case 'response.text.delta':
        final delta = msg['delta']?.toString() ?? '';
        if (delta.isNotEmpty) {
          onAssistantTranscript?.call(delta, append: true);
        }
      case 'response.done':
        onTurnComplete?.call();
      case 'error':
        final err = msg['error'];
        final errMsg = (err is Map ? err['message'] : err)?.toString() ??
            'OpenAI Live hatası';
        onError?.call(errMsg);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _toolResults.clear();
    await _sub?.cancel();
    _sub = null;
    try {
      await _transport.close();
    } catch (_) {}
  }
}
