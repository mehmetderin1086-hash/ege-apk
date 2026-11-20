import 'dart:typed_data';

import 'speaker_identity.dart';

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'device_bridge.dart';
import 'wake_audio.dart';
import 'wake_calibration.dart';
import 'wake_verifier.dart';

/// "Asistan" uyandırma sözcüğü; Türkçe söyleyiş için ölçülmüş fonetik yollar.
///
/// sherpa-onnx açık sözcük dağarcıklı anahtar sözcük algılayıcısı (İngilizce
/// GigaSpeech 3.3M zipformer, int8, ~5 MB) cihazda, ayrı bir isolate'te
/// çalışır; ses telefondan çıkmaz. Mikrofon native taraftan 100 ms'lik
/// parçalar hâlinde gelir ("onWakePcm").
class WakeWordEngine {
  WakeWordEngine._();
  static final WakeWordEngine instance = WakeWordEngine._();

  static bool get supported => !kIsWeb && Platform.isAndroid;

  // The bundled English model decodes Turkish "Asistan" as "AS HISTAN".
  static const keywordTokens = '▁AS ▁HIS T AN';
  static const defaultPaths = <String>[
    keywordTokens,
    '▁AS ▁IS T AN',
    '▁AS S IST ANT',
    '▁A S IST AN',
  ];

  static const _assetFiles = {
    'encoder.int8.onnx': 'assets/kws/encoder.int8.onnx',
    'decoder.int8.onnx': 'assets/kws/decoder.int8.onnx',
    'joiner.int8.onnx': 'assets/kws/joiner.int8.onnx',
    'tokens.txt': 'assets/kws/tokens.txt',
  };

  Isolate? _iso;
  ReceivePort? _recv;
  SendPort? _send;
  bool running = false;
  DateTime _lastHit = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int hits = 0;
  final List<Uint8List> _speakerRing = [];
  bool _verifyingSpeaker = false;
  int _speakerGeneration = 0;
  String lastKeyword = '';
  String _activeLine = '';

  /// Son bulut doğrulamasının kısa açıklaması (tanılama için).
  String lastVerification = '';

  /// Model dosyalarını uygulama klasörüne çıkarır (kalibrasyon da kullanır).
  Future<String> modelDir() => _ensureModel();

  /// Duyarlılık 0..1 → algılama eşiği ve sözcük puanı.
  ///
  /// 4.6.0 ölçümü (Türkçe 2 konuşmacı × 45 söyleyiş × temiz/kısık/gürültülü,
  /// 520 zorlayıcı olumsuz kayıt): eşik 0,08 → %72 yakalama; eşik 0,01 ve
  /// puan 3 → %84 yakalama, yanlış alarm 0. Varsayılan (0,5) artık bu nokta.
  static ({double threshold, double boost}) tuning(double sensitivity) {
    final s = sensitivity.clamp(0.0, 1.0);
    // s=0 → 0,06 (sıkı), s=0,5 → 0,011, s=1 → 0,004 (en duyarlı).
    final th = 0.004 + 0.056 * (1 - s) * (1 - s) * (1 - s);
    return (threshold: th, boost: 2.0 + 2.0 * s);
  }

  /// One spoken word starts the assistant.
  static String keywordLine(double sensitivity) {
    final t = tuning(sensitivity);
    final th = t.threshold.toStringAsFixed(3);
    final b = t.boost.toStringAsFixed(2);
    return defaultPaths.map((p) => '$p :$b #$th @ASISTAN').join('/');
  }

  /// Kişisel kalibrasyon varsa onun satırı, yoksa varsayılan satır.
  static Future<String> effectiveKeywordLine(double sensitivity) async {
    return await WakeCalibration.savedLine() ?? keywordLine(sensitivity);
  }

  Future<String> _ensureModel() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/kws');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    for (final e in _assetFiles.entries) {
      final f = File('${dir.path}/${e.key}');
      if (!f.existsSync() || f.lengthSync() == 0) {
        final data = await rootBundle.load(e.value);
        await f.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
    }
    final kw = File('${dir.path}/keywords.txt');
    await kw.writeAsString('$keywordTokens @ASISTAN\n', flush: true);
    return dir.path;
  }

  Future<String?> start({
    required double sensitivity,
    required void Function() onDetected,
  }) async {
    if (running) return null;
    try {
      final dir = await _ensureModel();
      final recv = ReceivePort();
      _recv = recv;
      final ready = Completer<String?>();
      recv.listen((msg) async {
        if (msg is SendPort) {
          _send = msg;
          if (!ready.isCompleted) ready.complete(null);
        } else if (msg is Map) {
          unawaited(
            const MethodChannel('com.jarvis.assistant/device')
                .invokeMethod<void>('wakeProgress', msg)
                .catchError((_) {}),
          );
        } else if (msg is String && msg.startsWith('ERR')) {
          if (!ready.isCompleted) {
            ready.complete(msg.substring(3).trim());
          } else {
            unawaited(
              const MethodChannel('com.jarvis.assistant/device')
                  .invokeMethod<void>('wakeEngineError')
                  .catchError((_) {}),
            );
          }
        } else if (msg is String && msg.startsWith('HIT')) {
          final now = DateTime.now();
          lastKeyword = msg.length > 4 ? msg.substring(4) : '';
          // Ignore only the initial hardware pop. A full wake phrase spoken
          // immediately after returning from a command must remain detectable.
          if (now.difference(_startedAt) < const Duration(milliseconds: 300)) {
            debugPrint(
              '[JARVIS] uyandırma açılışta yok sayıldı ($lastKeyword)',
            );
            return;
          }
          if (now.difference(_lastHit) > const Duration(seconds: 2)) {
            _lastHit = now;
            if (_verifyingSpeaker) return;
            _verifyingSpeaker = true;
            final speakerGeneration = _speakerGeneration;
            final bytes = BytesBuilder(copy: false);
            for (final chunk in _speakerRing) {
              bytes.add(chunk);
            }
            final raw = bytes.takeBytes();
            final bd = ByteData.sublistView(raw);
            final samples = Float32List.fromList(
              List.generate(
                raw.length ~/ 2,
                (i) => bd.getInt16(i * 2, Endian.little) / 32768.0,
              ),
            );
            final accepted = await SpeakerIdentity.instance.acceptsSamples(
              samples,
              wake: true,
            );
            unawaited(
              const MethodChannel('com.jarvis.assistant/device')
                  .invokeMethod<void>('wakeSpeakerDecision', {
                    'accepted': accepted,
                    'reason': SpeakerIdentity.instance.lastCheck,
                  })
                  .catchError((_) {}),
            );
            if (!running ||
                speakerGeneration != _speakerGeneration ||
                !accepted) {
              _verifyingSpeaker = false;
              return;
            }
            // Son ~2,5 sn: yerel isabeti bulutta ikinci kez doğrula.
            final tail = raw.length > 80000
                ? Uint8List.sublistView(raw, raw.length - 80000)
                : raw;
            final check = await WakeVerifier.verify(tail);
            _verifyingSpeaker = false;
            lastVerification = check.reason;
            debugPrint(
              '[Ege] uyandırma doğrulama ($lastKeyword): ${check.reason}',
            );
            if (!running ||
                speakerGeneration != _speakerGeneration ||
                !check.accepted) {
              return;
            }
            hits++;
            onDetected();
          }
        }
      });
      final line = await effectiveKeywordLine(sensitivity);
      _activeLine = line;
      _iso = await Isolate.spawn(_kwsMain, [recv.sendPort, dir, line]);
      final err = await ready.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => 'zaman aşımı',
      );
      if (err != null) {
        await stop();
        return 'Uyandırma motoru başlatılamadı: $err';
      }
      DeviceBridge.setWakeAudioCallback((chunk) {
        _speakerRing.add(Uint8List.fromList(chunk));
        while (_speakerRing.fold<int>(0, (n, c) => n + c.length) >
            16000 * 2 * 3) {
          _speakerRing.removeAt(0);
        }
        _send?.send(TransferableTypedData.fromList([chunk]));
      });
      final mic = await DeviceBridge.startWakeMic();
      if (mic != 'OK') {
        await stop();
        return mic == 'PERMISSION_NEEDED'
            ? 'Mikrofon izni gerekli.'
            : 'Mikrofon açılamadı ($mic).';
      }
      running = true;
      _startedAt = DateTime.now();
      debugPrint('[JARVIS] uyandırma dinliyor: $_activeLine');
      return null;
    } catch (e) {
      await stop();
      return 'Uyandırma motoru başlatılamadı: $e';
    }
  }

  Future<void> stop() async {
    _speakerGeneration++;
    _speakerRing.clear();
    running = false;
    await DeviceBridge.stopWakeMic();
    DeviceBridge.setWakeAudioCallback(null);
    _send?.send('STOP');
    _send = null;
    final iso = _iso;
    _iso = null;
    if (iso != null) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      iso.kill(priority: Isolate.beforeNextEvent);
    }
    _recv?.close();
    _recv = null;
  }
}

/// Algılayıcı isolate'i: PCM16 parçalarını alır, "HIT" gönderir.
void _kwsMain(List<Object?> args) {
  final out = args[0] as SendPort;
  final dir = args[1] as String;
  final keyword = args[2] as String;
  try {
    so.initBindings();
    final spotter = so.KeywordSpotter(
      so.KeywordSpotterConfig(
        model: so.OnlineModelConfig(
          transducer: so.OnlineTransducerModelConfig(
            encoder: '$dir/encoder.int8.onnx',
            decoder: '$dir/decoder.int8.onnx',
            joiner: '$dir/joiner.int8.onnx',
          ),
          tokens: '$dir/tokens.txt',
          numThreads: 1,
          debug: false,
        ),
        keywordsFile: '$dir/keywords.txt',
      ),
    );
    final stream = spotter.createStream(keywords: keyword);
    final originalStream = spotter.createStream(keywords: keyword);
    final normalizer = WakeAudioNormalizer();
    var processedSamples = 0;
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    inbox.listen((msg) {
      if (msg == 'STOP') {
        stream.free();
        originalStream.free();
        spotter.free();
        inbox.close();
        return;
      }
      if (msg is TransferableTypedData) {
        final bytes = msg.materialize().asUint8List();
        final bd = ByteData.sublistView(bytes);
        final n = bytes.length ~/ 2;
        final f = Float32List(n);
        for (var i = 0; i < n; i++) {
          f[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
        }
        originalStream.acceptWaveform(samples: f, sampleRate: 16000);
        normalizer.process(f);
        stream.acceptWaveform(samples: f, sampleRate: 16000);
        processedSamples += n;
        if (processedSamples % 16000 < n) {
          out.send({'decodedSamples': processedSamples});
        }
        var detected = '';
        // Preserve naturally loud speech as well as the quiet-speech path.
        // A single model owns both streams; report only one hit per chunk.
        for (final candidate in [originalStream, stream]) {
          while (spotter.isReady(candidate)) {
            spotter.decode(candidate);
            final kw = spotter.getResult(candidate).keyword;
            if (kw.isNotEmpty) {
              detected = kw;
              break;
            }
          }
        }
        if (detected.isNotEmpty) {
          out.send('HIT:$detected');
          spotter.reset(originalStream);
          spotter.reset(stream);
        }
      }
    });
  } catch (e) {
    out.send('ERR $e');
  }
}
