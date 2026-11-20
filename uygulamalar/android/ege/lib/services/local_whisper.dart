import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// A ggml Whisper model hosted on Hugging Face (ggerganov/whisper.cpp).
class WhisperModelInfo {
  final String id;
  final String file;
  final String label;
  final String description;
  final int sizeBytes;
  final String sha256;

  const WhisperModelInfo({
    required this.id,
    required this.file,
    required this.label,
    required this.description,
    required this.sizeBytes,
    required this.sha256,
  });

  String get url => '${LocalWhisper.hfBase}/$file';

  String get sizeLabel => '${(sizeBytes / 1048576).toStringAsFixed(0)} MB';
}

/// On-device OpenAI Whisper (whisper.cpp compiled into the app). Models are
/// downloaded once from Hugging Face, verified with SHA-256 and then work
/// fully offline and free.
class LocalWhisper {
  static const hfBase = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';
  static const MethodChannel _channel = MethodChannel('com.jarvis.assistant/device');

  static const models = <WhisperModelInfo>[
    WhisperModelInfo(
      id: 'tiny-q5_1',
      file: 'ggml-tiny-q5_1.bin',
      label: 'Tiny',
      description: 'En hızlı; Türkçede doğruluk düşük',
      sizeBytes: 32152673,
      sha256: '818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7',
    ),
    WhisperModelInfo(
      id: 'base-q5_1',
      file: 'ggml-base-q5_1.bin',
      label: 'Base (önerilen)',
      description: 'Hızlı: telefonda kısa bir komut ~1,5-2,5 sn; Türkçe komutlar için yeterli',
      sizeBytes: 59707625,
      sha256: '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898',
    ),
    WhisperModelInfo(
      id: 'small-q5_1',
      file: 'ggml-small-q5_1.bin',
      label: 'Small',
      description: "Daha doğru ama ~3 kat yavaş (realme 10'da 5-8 sn); uzun dikte için",
      sizeBytes: 190085487,
      sha256: 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
    ),
    WhisperModelInfo(
      id: 'large-v3-turbo-q5_0',
      file: 'ggml-large-v3-turbo-q5_0.bin',
      label: 'Large v3 Turbo',
      description: 'En doğru; büyük ve yavaş (güçlü telefonlar)',
      sizeBytes: 574041195,
      sha256: '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
    ),
  ];

  static const defaultModelId = 'base-q5_1';

  static WhisperModelInfo byId(String id) =>
      models.firstWhere((m) => m.id == id, orElse: () => models[1]);

  /// Komut sözcüklerini doğal bir Türkçe cümle içinde veren ipucu. realme 10
  /// ölçümünde virgüllü kelime listesi "YouTube'de", "iczani" verirken bu
  /// biçim "YouTube'da", "WhatsApp'tan", "eczane"yi doğru yazdırdı.
  static const prompt = "Merhaba Ege. YouTube'da şarkı çal, WhatsApp'tan mesaj yaz, annemi ara, "
      'alarm kur, hatırlatıcı ekle, hava durumu, el feneri, Spotify, Instagram, Google.';

  // ---- test seams
  static Future<({bool ok, String text, int ms, String? error})> Function(
    Uint8List wav,
    WhisperModelInfo model,
  )? testTranscriber;
  static Future<bool> Function(WhisperModelInfo model)? testIsDownloaded;
  static Future<void> Function(
    WhisperModelInfo model,
    void Function(int got, int total)? onProgress,
  )? testDownloader;

  static Future<Directory> Function()? testDirProvider;

  /// Wait between automatic download retries (multiplied by the attempt).
  static Duration retryUnit = const Duration(seconds: 3);

  static Future<Directory> modelDir() async {
    final base = await (testDirProvider ?? getApplicationSupportDirectory)();
    final d = Directory('${base.path}${Platform.pathSeparator}whisper');
    await d.create(recursive: true);
    return d;
  }

  static Future<File> modelFile(WhisperModelInfo m) async =>
      File('${(await modelDir()).path}${Platform.pathSeparator}${m.file}');

  static Future<bool> isDownloaded(WhisperModelInfo m) async {
    final seam = testIsDownloaded;
    if (seam != null) return seam(m);
    try {
      final f = await modelFile(m);
      return await f.exists() && await f.length() == m.sizeBytes;
    } catch (_) {
      return false;
    }
  }

  static Future<String> sha256Of(String path) => Isolate.run(
        () async => (await sha256.bind(File(path).openRead()).first).toString(),
      );

  /// Downloads (resuming a partial file when possible) and verifies a model.
  static Future<void> download(
    WhisperModelInfo m, {
    void Function(int got, int total)? onProgress,
    bool Function()? isCancelled,
    http.Client? client,
  }) async {
    final seam = testDownloader;
    if (seam != null) return seam(m, onProgress);
    final dest = await modelFile(m);
    final part = File('${dest.path}.part');
    var start = await part.exists() ? await part.length() : 0;
    if (start > m.sizeBytes) {
      await part.delete();
      start = 0;
    }
    final c = client ?? http.Client();
    // Closing the client aborts a stalled transfer immediately on cancel.
    final cancelWatch = isCancelled == null || client != null
        ? null
        : Timer.periodic(const Duration(milliseconds: 300), (t) {
            if (isCancelled()) {
              t.cancel();
              c.close();
            }
          });
    try {
      if (start < m.sizeBytes) {
        final req = http.Request('GET', Uri.parse(m.url));
        if (start > 0) req.headers['Range'] = 'bytes=$start-';
        final res = await c.send(req).timeout(const Duration(seconds: 40));
        if (res.statusCode == 200) {
          start = 0; // server ignored the range: restart
        } else if (res.statusCode != 206) {
          throw StateError('Hugging Face indirme hatası (HTTP ${res.statusCode}).');
        }
        final sink = part.openWrite(mode: start > 0 ? FileMode.append : FileMode.write);
        var got = start;
        var lastReport = 0;
        try {
          await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
            if (isCancelled?.call() == true) throw const _DownloadCancelled();
            sink.add(chunk);
            got += chunk.length;
            if (got - lastReport > 512 * 1024 || got >= m.sizeBytes) {
              lastReport = got;
              onProgress?.call(got, m.sizeBytes);
            }
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
      }
      final size = await part.length();
      if (size != m.sizeBytes) {
        throw StateError('İndirme eksik kaldı (${(size / 1048576).toStringAsFixed(0)}/${m.sizeLabel}). Tekrar deneyin.');
      }
      final digest = await sha256Of(part.path);
      if (digest != m.sha256) {
        await part.delete();
        throw StateError('Model doğrulanamadı (SHA-256 uyuşmadı); tekrar indirilecek.');
      }
      if (await dest.exists()) await dest.delete();
      await part.rename(dest.path);
    } catch (e) {
      if (isCancelled?.call() == true) throw const _DownloadCancelled();
      rethrow;
    } finally {
      cancelWatch?.cancel();
      if (client == null) c.close();
    }
  }

  /// Loads the model into memory without running inference (a clip shorter
  /// than 0.2 s returns before decoding) so the first real request is fast.
  static Future<void> warmUp(WhisperModelInfo model) async {
    if (testTranscriber != null) return;
    await transcribe(wav: silentWav(ms: 100), model: model);
  }

  /// Minimal 16 kHz mono PCM16 WAV of silence.
  static Uint8List silentWav({int ms = 600}) {
    final samples = 16000 * ms ~/ 1000;
    final dataLen = samples * 2;
    final b = ByteData(44 + dataLen);
    void ascii(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    b.setUint32(4, 36 + dataLen, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, 16000, Endian.little);
    b.setUint32(28, 32000, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    b.setUint32(40, dataLen, Endian.little);
    return b.buffer.asUint8List();
  }

  /// Whisper sometimes "hears" YouTube subtitle credits or echoes the prompt
  /// when the clip is silent or only noise. Those outputs are dropped.
  static String cleanTranscript(String raw) {
    var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll(RegExp(r'^[\[\(][^\]\)]*[\]\)]\s*'), '').trim(); // [Müzik] (alkış)
    if (t.isEmpty) return '';
    final norm = _normalize(t);
    if (norm.isEmpty) return '';
    // Only phrases nobody says to an assistant (YouTube subtitle credits).
    const junk = <String>{
      'altyazı m k',
      'altyazı mk',
      'izlediğiniz için teşekkürler',
      'izlediğiniz için teşekkür ederim',
      'izlediğiniz için teşekkür ederiz',
      'videoyu beğenmeyi ve abone olmayı unutmayın',
      'abone olmayı ve beğenmeyi unutmayın',
      'abone olmayı unutmayın',
      'kanalıma abone olmayı unutmayın',
      'bir sonraki videoda görüşmek üzere',
      'thanks for watching',
      'türkçe konuşma',
    };
    if (junk.contains(norm)) return '';
    // Echo of the vocabulary prompt (e.g. "JARVIS, YouTube, WhatsApp, ...").
    final promptWords = {..._normalize(prompt).split(' '), 'jarvıs', 'jarvis'};
    final words = norm.split(' ');
    if (words.length >= 4 &&
        ','.allMatches(t).length >= 3 &&
        words.every(promptWords.contains)) {
      return '';
    }
    return t;
  }

  /// Turkish-aware lower case without punctuation ("İ" → "i", "I" → "ı").
  static String _normalize(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-zçğıöşüâîû0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static Future<void> delete(WhisperModelInfo m) async {
    await release();
    final f = await modelFile(m);
    if (await f.exists()) await f.delete();
    final part = File('${f.path}.part');
    if (await part.exists()) await part.delete();
  }

  static Future<({bool ok, String text, int ms, String? error})> transcribe({
    required Uint8List wav,
    required WhisperModelInfo model,
    bool fast = true,
    String language = 'tr',
    int threads = 0,
  }) async {
    final seam = testTranscriber;
    if (seam != null) return seam(wav, model);
    try {
      final f = await modelFile(model);
      final r = await _channel.invokeMethod<Map<dynamic, dynamic>>('whisperTranscribe', {
        'modelPath': f.path,
        'wav': wav,
        'language': language,
        'fast': fast,
        'prompt': prompt,
        'threads': threads,
      });
      if (r == null) return (ok: false, text: '', ms: 0, error: 'Whisper yanıt vermedi.');
      final ok = r['ok'] == true;
      return (
        ok: ok,
        text: (r['text'] ?? '').toString().trim(),
        ms: (r['ms'] as num?)?.toInt() ?? 0,
        error: ok ? null : (r['error']?.toString() ?? 'Whisper hatası'),
      );
    } on MissingPluginException {
      return (ok: false, text: '', ms: 0, error: 'Yerel Whisper bu cihazda kullanılamıyor.');
    } catch (e) {
      return (ok: false, text: '', ms: 0, error: 'Yerel Whisper hatası: $e');
    }
  }

  static Future<Map<String, dynamic>> info() async {
    try {
      final r = await _channel.invokeMethod<Map<dynamic, dynamic>>('whisperInfo');
      return r == null ? const {} : Map<String, dynamic>.from(r);
    } catch (_) {
      return const {};
    }
  }

  static Future<void> release() async {
    try {
      await _channel.invokeMethod('whisperRelease');
    } catch (_) {}
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();

  @override
  String toString() => 'İndirme iptal edildi.';
}
