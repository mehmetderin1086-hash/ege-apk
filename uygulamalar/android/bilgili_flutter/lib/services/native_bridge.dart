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

  /// res/raw altındaki kısa bir ses dosyasını çalar (ör. 'zirve_dogru').
  static Future<void> playClip(String name, {bool enabled = true, double volume = 0.8}) async {
    if (testMode || !enabled) return;
    try {
      await _channel.invokeMethod('playClip', {'name': name, 'volume': volume});
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
  static String buildQuestionSpeech(Question q, int number) =>
      questionSegments(q, number).map((segment) => segment.text).join(' ');


  static List<({String text, String language})> questionSegments(Question q, int number,
      {bool creationSubmitted = false}) {
    final segments = <({String text, String language})>[];
    final intro = StringBuffer('Soru $number. ${q.category.label}. ');
    if (q.visual != null && q.visual!.summary.isNotEmpty) {
      intro.write('${q.visual!.title}. ${q.visual!.summary} ');
    }
    intro.write(q.text);
    final act = q.activity;
    if (act != null &&
        (act.kind == ActivityKind.listening ||
            act.kind == ActivityKind.dictation ||
            act.kind == ActivityKind.pronunciation)) {
      final transcript = act.transcript ?? '';
      if (transcript.isNotEmpty) {
        segments.add((text: intro.toString(), language: 'tr-TR'));
        segments.add((text: transcript, language: act.language ?? 'tr-TR'));
        intro.clear();
      }
      if (act.kind == ActivityKind.pronunciation) {
        intro.write('Duyduğun ifadeyi tekrar et.');
        segments.add((text: intro.toString(), language: 'tr-TR'));
        return segments;
      }
      if (act.kind == ActivityKind.dictation) {
        intro.write('Duyduğun eksik ifadeyi ekranda yaz.');
        segments.add((text: intro.toString(), language: 'tr-TR'));
        return segments;
      }
    }
    if (act?.kind == ActivityKind.ordering) {
      for (final (i, item) in act!.items.indexed) {
        intro.write(' ${i+1}. $item.');
      }
      intro.write(' ${act.solution.length} öğenin numarasını istediğin sırada söyle.');
    } else if (act?.kind == ActivityKind.matching) {
      intro.write(' Sol sütun. ');
      for (final (i, item) in act!.left.indexed) {
        intro.write('${i+1}. $item. ');
      }
      intro.write('Sağ sütun. ');
      for (final (i, item) in act.right.indexed) {
        intro.write('${i+1}. $item. ');
      }
      intro.write('Her sol öğe için eşleştiği sağ öğenin numarasını sırayla söyle.');
    } else if (q.creation != null && !creationSubmitted) {
      intro.write(' ${q.creation!.brief}');
    } else if (q.responseType == ResponseType.fill) {
      intro.write(' Yanıtını ekranda yaz.');
    } else {
      for (final (i, option) in q.options.indexed) {
        intro.write(' ${String.fromCharCode(65+i)} şıkkı: $option.');
      }
      if (q.multiSelect != null) intro.write(' Uygun seçenekleri ekranda işaretle.');
    }
    segments.add((text: intro.toString(), language: 'tr-TR'));
    return segments;
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
