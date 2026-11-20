import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/jarvis_models.dart';
import 'ai_client.dart';
import 'embedded_keys.dart';

/// "Asistan" isabetini bulutta ikinci kez doğrular.
///
/// Yerel İngilizce algılayıcı "Hey Engin", "hediye", "heyecanlı" gibi
/// sözleri de "Asistan" sanabiliyor. Yalnız yerel isabet anında, son ~2,5
/// saniyelik ses Gemini'ye yazdırılır ve metin "Asistan" mi diye bakılır.
/// Sürekli dinleme buluta gitmez. İnternet yok, anahtar yok ya da cevap
/// gecikirse yerel karar geçerli olur (uyandırma kaçmasın).
class WakeVerifier {
  WakeVerifier._();

  static const timeout = Duration(milliseconds: 3500);

  // All Flutter engines share this opt-in flag. A local wake hit is sufficient
  // unless the user explicitly asks for a second cloud transcription.
  static Future<File> _onFile() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/kws/cloud_verify_on');
  }

  static Future<bool> enabled() async {
    try {
      return await (await _onFile()).exists();
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool on) async {
    final f = await _onFile();
    if (on) {
      await f.parent.create(recursive: true);
      await f.writeAsString('1', flush: true);
    } else if (await f.exists()) {
      await f.delete();
    }
  }
  static bool matches(String text) => RegExp(
    r'^(?:asistan|assistant)(?:$|[^a-zçğıöşü])',
    caseSensitive: false,
  ).hasMatch(text.trim());

  /// [pcm16]: 16 kHz mono PCM16 (little endian). Döner: kabul mü ve
  /// kayıtta görülecek kısa açıklama.
  static Future<({bool accepted, String reason})> verify(
    Uint8List pcm16, {
    http.Client? client,
    String? apiKey,
  }) async {
    if (!await enabled()) {
      return (accepted: true, reason: 'bulut doğrulama kapalı');
    }
    final key = apiKey ?? EmbeddedKeys.instance.gemini;
    if (key.isEmpty)
      return (accepted: true, reason: 'anahtar yok; yerel karar');
    if (pcm16.length < 8000)
      return (accepted: true, reason: 'ses kısa; yerel karar');
    try {
      final r = await AiClient.transcribeWithGemini(
        settings: JarvisSettings(geminiTtsKey: key),
        wav: wavFromPcm16(pcm16),
        client: client,
        timeout: timeout,
      ).timeout(timeout + const Duration(milliseconds: 500));
      if (!r.ok)
        return (
          accepted: true,
          reason: 'bulut hatası; yerel karar (${r.error})',
        );
      final ok = matches(r.text);
      return (accepted: ok, reason: '"${r.text}" → ${ok ? 'kabul' : 'ret'}');
    } on TimeoutException {
      return (accepted: true, reason: 'bulut gecikti; yerel karar');
    } catch (e) {
      return (accepted: true, reason: 'bulut hatası; yerel karar ($e)');
    }
  }

  static Uint8List wavFromPcm16(Uint8List pcm) {
    final out = BytesBuilder(copy: false);
    final h = ByteData(44);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        h.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    h.setUint32(4, 36 + pcm.length, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, 1, Endian.little);
    h.setUint32(24, 16000, Endian.little);
    h.setUint32(28, 32000, Endian.little);
    h.setUint16(32, 2, Endian.little);
    h.setUint16(34, 16, Endian.little);
    str(36, 'data');
    h.setUint32(40, pcm.length, Endian.little);
    out.add(h.buffer.asUint8List());
    out.add(pcm);
    return out.takeBytes();
  }
}
