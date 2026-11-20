import 'turkish_speech.dart';

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import '../models/jarvis_models.dart';
import 'ai_client.dart';
import 'device_bridge.dart';
import 'local_command_engine.dart';

/// Cloud/on-device Turkish TTS with Markdown cleanup for speech. Speech
/// recognition is done by OpenAI Whisper (see AiClient.transcribeAudioWav).
class VoiceService {
  final FlutterTts _tts = FlutterTts();

  bool _ttsReady = false;
  bool _isSpeaking = false;
  Completer<void>? _speakCompleter;

  bool get isSpeaking => _isSpeaking;

  static String cleanForSpeech(String raw) {
    var text = LocalCommandEngine.stripActionTags(raw);
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' kod bloğu. ');
    text = text.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!);
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\((https?://[^\s)]+)\)'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAll(RegExp(r'https?://\S+'), '');
    text = text.replaceAll(
      RegExp(r'^\s*\|?[\s:|-]+\|?\s*$', multiLine: true),
      ' ',
    );
    text = text.replaceAll('|', '; ');
    text = TurkishSpeech.normalize(text);
    text = text.replaceAll(RegExp(r'[#*_~>]+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  Future<void> _ensureTts() async {
    if (_ttsReady) return;
    _ttsReady = true;
    try {
      await _tts.setLanguage('tr-TR');
    } catch (_) {}
    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}

    _tts.setStartHandler(() {
      _isSpeaking = true;
    });
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _completeSpeak();
    });
    _tts.setCancelHandler(() {
      _isSpeaking = false;
      _completeSpeak();
    });
    _tts.setErrorHandler((error) {
      lastError = 'Telefon ses motoru: $error';
      _isSpeaking = false;
      _completeSpeak();
    });
  }

  void _completeSpeak() {
    final c = _speakCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    _speakCompleter = null;
  }

  /// Splits long replies into sentence-aligned chunks so cloud TTS requests
  /// stay short (no timeouts) and playback can start quickly.
  static List<String> splitForTts(
    String text, {
    int maxLen = 260,
    int firstLen = 150,
  }) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return const [];
    final sentences = RegExp(r'(?:[^.!?…;:\n]|(?<=\d)[.:](?=\d))+[.!?…;:]*')
        .allMatches(clean)
        .map((m) => m.group(0)!.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final chunks = <String>[];
    var buf = StringBuffer();
    void flush() {
      final s = buf.toString().trim();
      if (s.isNotEmpty) chunks.add(s);
      buf = StringBuffer();
    }

    for (final sentence in sentences) {
      final limit = chunks.isEmpty ? firstLen : maxLen;
      if (sentence.length > limit) {
        flush();
        var rest = sentence;
        while (rest.length > limit) {
          var cut = rest.lastIndexOf(RegExp(r'[,\s]'), limit);
          if (cut < limit ~/ 2) cut = limit;
          chunks.add(rest.substring(0, cut).trim());
          rest = rest.substring(cut).trim();
        }
        if (rest.isNotEmpty) buf.write(rest);
        continue;
      }
      if (buf.length + sentence.length + 1 > limit) flush();
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(sentence);
    }
    flush();
    return chunks;
  }

  int _speakGen = 0;

  /// Human readable name of the engine that produced the last spoken audio.
  String lastEngineUsed = '';
  String? lastError;

  /// Detailed cloud TTS attempts of the last speak() call.
  List<TtsAttempt> lastAttempts = const [];

  Future<void> speak(
    String rawText, {
    double rate = 0.52,
    double pitch = 1.0,
    JarvisSettings? settings,
    http.Client? httpClient,
    Future<void> Function()? onAudioStarted,
  }) async {
    final clean = cleanForSpeech(rawText);
    if (clean.isEmpty) return;

    final gen = ++_speakGen;
    await _halt();
    if (gen != _speakGen) return;
    lastError = null;

    if (settings?.ttsEngine == 'device') {
      lastEngineUsed = 'Cihaz TTS';
      lastAttempts = const [];
      await _speakDevice(clean, rate, pitch, gen, onAudioStarted);
      return;
    }

    final effSettings = settings ?? const JarvisSettings();
    final chunks = splitForTts(clean);
    Future<TtsResult> synth(int i) => AiClient.synthesizeSpeechDetailed(
      settings: effSettings,
      text: chunks[i],
      client: httpClient,
    );
    // Lower in-app music while JARVIS talks (Windows JARVIS behaviour).
    await DeviceBridge.streamDuck(true);
    try {
      await _speakCloudChunks(
        chunks,
        synth,
        effSettings,
        httpClient,
        gen,
        onAudioStarted,
        rate,
        pitch,
      );
    } finally {
      if (gen == _speakGen) await DeviceBridge.streamDuck(false);
    }
  }

  Future<void> _speakCloudChunks(
    List<String> chunks,
    Future<TtsResult> Function(int i) synth,
    JarvisSettings effSettings,
    http.Client? httpClient,
    int gen,
    Future<void> Function()? onAudioStarted,
    double rate,
    double pitch,
  ) async {
    if (chunks.isEmpty) return;
    var audioStarted = false;
    // Bulut hatasında kalan metni bir kez cihaz TTS ile okur.
    Future<void> deviceFallback(int from) async {
      if (gen != _speakGen) return;
      final rest = chunks.sublist(from).join(' ');
      lastEngineUsed = 'Cihaz TTS (yedek)';
      await _speakDevice(
        rest,
        rate,
        pitch,
        gen,
        audioStarted ? null : onAudioStarted,
      );
    }

    var pending = synth(0);
    for (var i = 0; i < chunks.length; i++) {
      var res = await pending;
      if (gen != _speakGen) return;
      if (i + 1 < chunks.length) pending = synth(i + 1);
      lastAttempts = res.attempts;
      if (!res.ok) {
        lastEngineUsed = 'Bulut ses hatası (${res.failureSummary})';
        lastError = res.failureSummary;
        _isSpeaking = false;
        await deviceFallback(i);
        return;
      }
      lastEngineUsed = res.provider;
      _isSpeaking = true;
      if (i == 0) {
        audioStarted = true;
        await onAudioStarted?.call();
      }
      if (gen != _speakGen) return;
      var played = await DeviceBridge.playAudioBytes(res.bytes!, ext: res.ext);
      if (gen != _speakGen) return;
      if (!played) {
        final mp3Backup = await AiClient.synthesizeSpeechDetailed(
          settings: effSettings,
          text: chunks[i],
          client: httpClient,
          onlyProviders: const ['edge_neural', 'google_translate'],
          useCache: false,
        );
        if (gen != _speakGen) return;
        if (mp3Backup.ok) {
          res = mp3Backup;
          lastAttempts = [...lastAttempts, ...mp3Backup.attempts];
          lastEngineUsed = mp3Backup.provider;
          played = await DeviceBridge.playAudioBytes(
            mp3Backup.bytes!,
            ext: mp3Backup.ext,
          );
          if (gen != _speakGen) return;
        }
      }
      if (!played) {
        lastEngineUsed = '${res.provider} oynatılamadı';
        lastError = lastEngineUsed;
        _isSpeaking = false;
        await deviceFallback(i);
        return;
      }
    }
    _isSpeaking = false;
  }

  Future<void> _speakDevice(
    String clean,
    double rate,
    double pitch,
    int gen,
    Future<void> Function()? onAudioStarted,
  ) async {
    if (gen != _speakGen || clean.trim().isEmpty) return;
    await _ensureTts();

    _isSpeaking = true;
    final completer = Completer<void>();
    _speakCompleter = completer;

    try {
      await _tts.setSpeechRate(rate.clamp(0.3, 1.0));
      await _tts.setPitch(pitch.clamp(0.6, 1.5));
      await onAudioStarted?.call();
      if (gen != _speakGen) return;
      await _tts.speak(clean);
    } catch (e) {
      lastError = 'Telefon ses motoru başlatılamadı: $e';
      _isSpeaking = false;
      _completeSpeak();
    }

    // Wait up to a reasonable safety timeout if awaitSpeakCompletion isn't synchronous.
    await completer.future.timeout(
      Duration(seconds: (clean.length ~/ 6).clamp(8, 180)),
      onTimeout: () {
        lastError = 'Telefon ses motoru zaman aşımına uğradı.';
        _isSpeaking = false;
      },
    );
  }

  /// Son konuşma bulut hatası nedeniyle cihaz TTS'e düştü mü?
  bool get usedDeviceFallback => lastEngineUsed == 'Cihaz TTS (yedek)';

  Future<void> stopSpeaking() async {
    _speakGen++;
    await _halt();
  }

  /// stopSpeaking işi; _speakGen'i ARTIRMAZ (speak içinden güvenle çağrılır).
  Future<void> _halt() async {
    _isSpeaking = false;
    await DeviceBridge.stopAudioPlayback();
    try {
      await DeviceBridge.streamDuck(false);
    } catch (_) {}
    if (_ttsReady) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
    _completeSpeak();
  }

  Future<void> dispose() async {
    await stopSpeaking();
  }
}
