import 'dart:async';
import 'package:flutter/services.dart';
import '../models/quiz_models.dart';

class VoiceEvent {
  final String type; // ready, speaking, rms, partial, processing, result, error
  final String text;
  final List<String> alternatives;
  final double level;
  final String? errorMessage;

  const VoiceEvent({
    required this.type,
    this.text = '',
    this.alternatives = const [],
    this.level = 0.0,
    this.errorMessage,
  });
}

class PickedFileData {
  final String name;
  final Uint8List bytes;
  const PickedFileData({required this.name, required this.bytes});
}

class NativeBridge {
  static Future<void> openAtlas() => _channel.invokeMethod<void>('openAtlas');
  static const MethodChannel _channel = MethodChannel('com.mehmetderin.bilgiarena/native');
  static const String defaultTtsVoice = 'tr-TR-AhmetNeural';
  static String activeTtsVoice = defaultTtsVoice;
  static bool testMode = false;
  static bool _initialized = false;
  static final StreamController<VoiceEvent> _voiceStream =
      StreamController<VoiceEvent>.broadcast();

  static Stream<VoiceEvent> get voiceEvents {
    _ensureInitialized();
    return _voiceStream.stream;
  }

  static void _ensureInitialized() {
    if (_initialized || testMode) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVoiceEvent' && call.arguments is Map) {
        final map = Map<String, dynamic>.from(call.arguments as Map);
        final type = map['type']?.toString() ?? '';
        final text = map['text']?.toString() ?? '';
        final alts = (map['alternatives'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [];
        final lvl = (map['level'] as num?)?.toDouble() ?? 0.0;
        final err = map['message']?.toString();
        _voiceStream.add(
          VoiceEvent(
            type: type,
            text: text,
            alternatives: alts,
            level: lvl,
            errorMessage: err,
          ),
        );
      }
    });
  }

  static Future<bool> speak(
    String text, {
    String language = 'tr-TR',
    String? voice,
    double rate = 1.0,
    bool awaitCompletion = true,
  }) async {
    if (testMode || text.trim().isEmpty) return true;
    _ensureInitialized();
    try {
      final res = await _channel.invokeMethod<bool>('speak', {
        'text': text,
        'language': language,
        'voice': voice ?? activeTtsVoice,
        'rate': rate,
        'awaitCompletion': awaitCompletion,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setTtsVoice(String voice) async {
    activeTtsVoice = voice.trim().isEmpty ? defaultTtsVoice : voice.trim();
    if (testMode) return;
    try {
      await _channel.invokeMethod('setTtsVoice', {'voice': activeTtsVoice});
    } catch (_) {}
  }

  static Future<void> stopSpeaking() async {
    if (testMode) return;
    try {
      await _channel.invokeMethod('stopSpeaking');
    } catch (_) {}
  }

  static Future<bool> checkMicPermission() async {
    if (testMode) return true;
    try {
      return await _channel.invokeMethod<bool>('checkMicPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestMicPermission() async {
    if (testMode) return true;
    try {
      return await _channel.invokeMethod<bool>('requestMicPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> startListening({String language = 'tr-TR'}) async {
    if (testMode) return;
    _ensureInitialized();
    await _channel.invokeMethod('startListening', {'language': language});
  }

  static Future<void> stopListening() async {
    if (testMode) return;
    try {
      await _channel.invokeMethod('stopListening');
    } catch (_) {}
  }

  static Future<void> cancelListening() async {
    if (testMode) return;
    try {
      await _channel.invokeMethod('cancelListening');
    } catch (_) {}
  }

  static Future<void> setMusic(String? track, {double volume = 0.35}) async {
    if (testMode) return;
    try {
      await _channel.invokeMethod('setMusic', {
        'track': track ?? 'off',
        'volume': volume,
      });
    } catch (_) {}
  }

  static Future<void> playSfx(
    String kind, {
    bool enabled = true,
    bool haptics = true,
    double volume = 0.55,
  }) async {
    if (testMode) return;
    if (haptics) {
      switch (kind) {
        case 'correct':
        case 'victory':
          HapticFeedback.mediumImpact();
          break;
        case 'wrong':
        case 'timeout':
          HapticFeedback.heavyImpact();
          break;
        default:
          HapticFeedback.selectionClick();
      }
    }
    if (!enabled) return;
    try {
      await _channel.invokeMethod('playSfx', {'kind': kind, 'volume': volume});
    } catch (_) {}
  }

  static Future<List<PickedFileData>> pickFiles({
    String mimeType = '*/*',
    bool allowMultiple = true,
  }) async {
    if (testMode) return const [];
    try {
      final raw = await _channel.invokeMethod<List>('pickFiles', {
        'mimeType': mimeType,
        'allowMultiple': allowMultiple,
      });
      if (raw == null) return const [];
      final out = <PickedFileData>[];
      for (final item in raw) {
        if (item is Map) {
          final name = item['name']?.toString() ?? 'dosya';
          final bytes = item['bytes'];
          if (bytes is Uint8List) {
            out.add(PickedFileData(name: name, bytes: bytes));
          }
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> saveFile({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (testMode) return true;
    try {
      return await _channel.invokeMethod<bool>('saveFile', {
            'fileName': fileName,
            'mimeType': mimeType,
            'bytes': bytes,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> shareText(String text, {String title = 'Bilgili Paylaşım'}) async {
    if (testMode) return;
    try {
      await _channel.invokeMethod('shareText', {'text': text, 'title': title});
    } catch (_) {}
  }
}

class QuizNarration {
  static String buildQuestionSpeech(Question q, int number) {
    final buf = StringBuffer('Soru $number. ${q.category.label}. ');
    if (q.visual != null && q.visual!.summary.isNotEmpty) {
      buf.write('${q.visual!.title}. ${q.visual!.summary} ');
    }
    if (q.activity != null) {
      final act = q.activity!;
      if (act.kind == ActivityKind.listening && act.transcript != null) {
        buf.write('Dinleme metni: ${act.transcript!}. ');
      } else if (act.kind == ActivityKind.ordering) {
        buf.write('${q.text} Öğeler: ');
        for (var i = 0; i < act.items.length; i++) {
          buf.write('${i + 1}: ${act.items[i]}. ');
        }
        buf.write('Sıralamayı dört rakam olarak söyleyebilirsin.');
        return buf.toString();
      } else if (act.kind == ActivityKind.matching) {
        buf.write('${q.text} Eşleştirme için sağ sütun numaralarını sırayla söyleyebilirsin.');
        return buf.toString();
      } else if (act.kind == ActivityKind.pronunciation) {
        buf.write('${q.text} Hedef ifade: ${act.transcript ?? q.options.first}.');
        return buf.toString();
      }
    }
    buf.write('${q.text} ');
    const letters = ['A', 'B', 'C', 'D'];
    for (var i = 0; i < q.options.length && i < 4; i++) {
      buf.write('${letters[i]} şıkkı: ${q.options[i]}. ');
    }
    return buf.toString();
  }

  static String buildFeedbackSpeech(
    Question q, {
    required bool correct,
    required bool includeExplanation,
    required bool isLast,
  }) {
    final buf = StringBuffer();
    if (correct) {
      buf.write('Harika, doğru yanıt! ');
    } else {
      buf.write('Doğru yanıt: ${q.correctAnswerText}. ');
    }
    if (includeExplanation && q.explanation.trim().isNotEmpty) {
      buf.write('${q.explanation} ');
    }
    if (isLast) {
      buf.write('Tur tamamlandı, tebrikler!');
    }
    return buf.toString();
  }
}
