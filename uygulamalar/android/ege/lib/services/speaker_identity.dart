import 'package:flutter/foundation.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

/// User-enrolled speaker filter. Not authentication or replay protection.
/// Raw recordings are transient; only vectors are kept in Android noBackupFilesDir.
class SpeakerIdentity {
  static final instance = SpeakerIdentity();
  static const _channel = MethodChannel('com.jarvis.assistant/device');
  static const modelName = 'wespeaker_en_voxceleb_resnet34.onnx';

  /// Kayıt tutarlılığı: profil örneklerinin tüm çiftleri en az bu kadar
  /// benzer olmalı (değişmedi).
  static const threshold = 0.65;

  /// Yeni sesin kabul eşiği (profil örneklerinin en az ikisiyle).
  ///
  /// 4.6.1 kalibrasyonu: gerçek cihazda sahibinin canlı/uyandırma
  /// parçaları 0,42–0,60 aldı (4.4.1 ve 4.6.1 kayıtları) ve 0,65 eşiği sahibini
  /// turların çoğunda reddetti. Bu model (wespeaker ResNet34) için farklı
  /// konuşmacılar tipik olarak 0,3'ün altında kalır. Filtre bir kimlik
  /// kilidi değildir; sesi çok benzeyen biri geçebilir.
  static const matchThreshold = 0.45;
  List<List<double>> _references = [];
  List<List<double>> _wakeReferences = [];
  bool get wakeEnrolled => _wakeReferences.length == 3;
  bool enabled = false;
  String lastCheck = 'Henüz ses doğrulanmadı';
  bool get enrolled => _references.length == 3;
  bool _loaded = false;
  Future<void>? _loading;
  Future<void>? _starting;
  Isolate? _worker;
  ReceivePort? _receive;
  SendPort? _send;
  int _id = 0;
  final _pending = <int, Completer<List<double>>>{};

  Future<void> load() async {
    if (_loaded) return;
    await (_loading ??= _load());
  }

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final raw = await _channel.invokeMethod<String>('speakerProfileRead');
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map;
        if (data['model'] == modelName) {
          _references = (data['references'] as List)
              .map(
                (e) => (e as List).map((n) => (n as num).toDouble()).toList(),
              )
              .toList();
          if (_references.length != 3 ||
              _references.any((e) => !validEmbedding(e)) ||
              _references.map((e) => e.length).toSet().length != 1) {
            _references = [];
          }
          final wake = data['wakeReferences'];
          if (wake is List && wake.length == 3) {
            final parsed = wake
                .map(
                  (e) => (e as List).map((n) => (n as num).toDouble()).toList(),
                )
                .toList();
            if (parsed.every(validEmbedding) &&
                parsed.map((e) => e.length).toSet().length == 1) {
              _wakeReferences = parsed;
            }
          }
        }
        // A damaged enabled profile must fail closed, never silently accept others.
        enabled = data['enabled'] == true;
      }
      _loaded = true;
    } on MissingPluginException {
      _loaded = true;
    }
  }

  Future<void> setEnabled(bool value) async {
    await load();
    if (value && !enrolled) {
      throw StateError('Önce üç ses örneğini kaydet.');
    }
    await _save(value, _references);
    enabled = value;
  }

  Future<void> forget() async {
    final deleted = await _channel.invokeMethod<bool>('speakerProfileDelete');
    if (deleted != true) {
      throw StateError('Ses profili silinemedi.');
    }
    _references = [];
    _wakeReferences = [];
    enabled = false;
    _loaded = true;
  }

  Future<void> _save(
    bool value,
    List<List<double>> references, {
    List<List<double>>? wakeReferences,
  }) async {
    final ok = await _channel.invokeMethod<bool>('speakerProfileWrite', {
      'json': jsonEncode({
        'model': modelName,
        'enabled': value,
        'references': references,
        'wakeReferences': wakeReferences ?? _wakeReferences,
      }),
    });
    if (ok != true) {
      throw StateError('Ses profili telefona kaydedilemedi.');
    }
  }

  Future<void> enroll(List<List<double>> samples) async {
    if (samples.length != 3 || samples.any((v) => !validEmbedding(v))) {
      throw StateError('Üç geçerli ses örneği gerekli.');
    }
    for (var i = 0; i < samples.length; i++) {
      for (var j = i + 1; j < samples.length; j++) {
        if (similarity(samples[i], samples[j]) < threshold) {
          throw StateError(
            'Örnekler birbiriyle uyuşmuyor. Sessiz bir yerde aynı sesle yeniden kaydet.',
          );
        }
      }
    }
    await _save(true, samples, wakeReferences: []);
    _references = samples.map((e) => List<double>.from(e)).toList();
    _wakeReferences = [];
    enabled = true;
    _loaded = true;
  }

  Future<void> enrollWake(List<List<double>> samples) async {
    await load();
    if (!enrolled ||
        samples.length != 3 ||
        samples.any((v) => !validEmbedding(v))) {
      throw StateError(
        'Önce genel ses profilini, sonra üç Asistan örneğini kaydet.',
      );
    }
    for (var i = 0; i < samples.length; i++) {
      for (var j = i + 1; j < samples.length; j++) {
        if (similarity(samples[i], samples[j]) < threshold) {
          throw StateError(
            'Asistan örnekleri tutarsız. Normal sesinle, aynı mesafeden yeniden kaydet.',
          );
        }
      }
    }
    await _save(enabled, _references, wakeReferences: samples);
    _wakeReferences = samples.map((e) => List<double>.from(e)).toList();
  }

  Future<bool> acceptsWakeWav(Uint8List wav) async {
    try {
      return await acceptsSamples(pcmFromWav(wav), wake: true);
    } catch (_) {
      lastCheck = 'Uyandırma sesi okunamadı';
      return false;
    }
  }

  Future<bool> acceptsWav(Uint8List wav) async {
    try {
      await load();
      if (!enabled) return true;
      return await acceptsSamples(pcmFromWav(wav));
    } catch (_) {
      return false;
    }
  }

  Future<bool> acceptsSamples(Float32List samples, {bool wake = false}) async {
    try {
      await load();
      if (!enabled) {
        lastCheck = 'Ses filtresi kapalı';
        return true;
      }
      if (!enrolled) {
        lastCheck = 'Ses profili eksik; yeniden kaydet';
        return false;
      }
      if (samples.length < 12000) {
        lastCheck = 'Ses örneği çok kısa';
        return false;
      }
      final refs = wake && wakeEnrolled ? _wakeReferences : _references;
      final vector = await embedding(
        wake && wakeEnrolled ? prepareWakeSamples(samples) : samples,
      );
      final accepted = matches(vector, refs);
      final scores = refs.map((r) => similarity(vector, r)).toList()..sort();
      debugPrint(
        '[Ege] ses kimliği ${wake ? 'uyandırma' : 'konuşma'}: '
        'skor=${scores[1].toStringAsFixed(2)} eşik=$matchThreshold '
        'kabul=$accepted',
      );
      lastCheck = accepted
          ? 'Ses doğrulandı (${scores[1].toStringAsFixed(2)})'
          : 'Ses profili eşleşmedi (${scores[1].toStringAsFixed(2)} / $matchThreshold)${wake && !wakeEnrolled ? '; Asistan kalibrasyonunu yap' : ''}';
      return accepted;
    } catch (e) {
      lastCheck = e is StateError
          ? e.message.toString()
          : 'Ses doğrulama hatası: ${e.runtimeType}';
      return false;
    }
  }

  static bool validEmbedding(List<double> v) =>
      v.length >= 32 &&
      v.every((n) => n.isFinite) &&
      v.any((n) => n.abs() > 0.000001);

  /// Trim only outer silence so enrollment and wake buffers compare the same phrase.
  /// Never concatenate speakers.
  static Float32List prepareWakeSamples(Float32List samples) {
    if (samples.isEmpty) return samples;
    const frame = 320; // 20 ms at 16 kHz
    final levels = <double>[];
    for (var start = 0; start < samples.length; start += frame) {
      final end = math.min(start + frame, samples.length);
      var power = 0.0;
      for (var i = start; i < end; i++) {
        power += samples[i] * samples[i];
      }
      levels.add(math.sqrt(power / (end - start)));
    }
    final peak = levels.reduce(math.max);
    if (!peak.isFinite || peak < 0.003) return Float32List(0);
    final gate = (peak * 0.10).clamp(0.001, 0.015);
    final first = levels.indexWhere((r) => r >= gate);
    final last = levels.lastIndexWhere((r) => r >= gate);
    var start = math.max(0, first * frame - 1600);
    var end = math.min(samples.length, (last + 1) * frame + 1920);
    // A naturally short wake phrase can become shorter than the embedding
    // input minimum after trimming. Keep surrounding ORIGINAL audio instead
    // of rejecting it, repeating speech, or relaxing speaker similarity.
    // An isolated click / empty input must still fail closed.
    if (end - start < 6400 || samples.length < 12000) {
      return Float32List(0);
    }
    if (end - start < 12000) {
      final missing = 12000 - (end - start);
      start = math.max(0, start - missing ~/ 2);
      end = math.min(samples.length, start + 12000);
      start = math.max(0, end - 12000);
    }
    return Float32List.fromList(samples.sublist(start, end));
  }

  static double similarity(List<double> a, List<double> b) {
    if (a.isEmpty || a.length != b.length) return -1;
    var dot = 0.0, aa = 0.0, bb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      aa += a[i] * a[i];
      bb += b[i] * b[i];
    }
    return aa <= 0 || bb <= 0 || !dot.isFinite ? -1 : dot / math.sqrt(aa * bb);
  }

  static bool matches(List<double> v, List<List<double>> refs) =>
      validEmbedding(v) &&
      refs.length == 3 &&
      refs
              .where(
                (r) => validEmbedding(r) && similarity(v, r) >= matchThreshold,
              )
              .length >=
          2;

  static Float32List pcmFromWav(Uint8List wav) {
    if (wav.length < 44 ||
        ascii.decode(wav.sublist(0, 4), allowInvalid: true) != 'RIFF') {
      return Float32List(0);
    }
    final data = ByteData.sublistView(wav);
    var offset = 12;
    var formatOk = false;
    while (offset + 8 <= wav.length) {
      final type = ascii.decode(
        wav.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      final size = data.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      if (size > wav.length - start) {
        return Float32List(0);
      }
      if (type == 'fmt ' && size >= 16) {
        formatOk =
            data.getUint16(start, Endian.little) == 1 &&
            data.getUint16(start + 2, Endian.little) == 1 &&
            data.getUint32(start + 4, Endian.little) == 16000 &&
            data.getUint16(start + 14, Endian.little) == 16;
      }
      if (type == 'data' && formatOk) {
        final count = (size ~/ 2).clamp(0, 16000 * 12);
        return Float32List.fromList(
          List.generate(
            count,
            (i) => data.getInt16(start + i * 2, Endian.little) / 32768.0,
          ),
        );
      }
      offset = start + size + size % 2;
    }
    return Float32List(0);
  }

  Future<List<double>> embedding(Float32List samples) async {
    if (samples.length < 12000 || samples.length > 16000 * 12) {
      throw StateError(
        'Ses örneği çok kısa veya tamamlanmamış. Yeniden söyle.',
      );
    }
    var energy = 0.0;
    for (final x in samples) {
      energy += x * x;
    }
    if (math.sqrt(energy / samples.length) < 0.003) {
      throw StateError('Ses çok düşük; yeniden kaydet.');
    }
    await (_starting ??= _start());
    final id = ++_id;
    final result = Completer<List<double>>();
    _pending[id] = result;
    _send!.send([id, samples]);
    try {
      return await result.future.timeout(const Duration(seconds: 12));
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> _start() async {
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/$modelName';
    final file = File(path);
    if (!await file.exists() || await file.length() != 26534365) {
      final asset = await rootBundle.load('assets/speaker/$modelName');
      await file.writeAsBytes(
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
        flush: true,
      );
    }
    final ready = Completer<void>();
    _receive = ReceivePort();
    _receive!.listen((message) {
      if (message is SendPort) {
        _send = message;
        if (!ready.isCompleted) ready.complete();
      } else if (message is List && message.length == 2 && message[0] is int) {
        final pending = _pending[message[0]];
        if (pending != null && !pending.isCompleted) {
          if (message[1] is List) {
            pending.complete((message[1] as List).cast<double>());
          } else {
            pending.completeError(StateError('Ses kimliği hesaplanamadı.'));
          }
        }
      } else if (!ready.isCompleted) {
        ready.completeError(StateError('Ses kimliği modeli açılamadı.'));
      }
    });
    try {
      _worker = await Isolate.spawn(_speakerWorker, [_receive!.sendPort, path]);
      await ready.future.timeout(const Duration(seconds: 25));
    } catch (_) {
      _worker?.kill();
      _receive?.close();
      _starting = null;
      rethrow;
    }
  }
}

void _speakerWorker(List<Object> args) {
  final reply = args[0] as SendPort;
  try {
    so.initBindings();
    final extractor = so.SpeakerEmbeddingExtractor(
      config: so.SpeakerEmbeddingExtractorConfig(
        model: args[1] as String,
        numThreads: 2,
        debug: false,
      ),
    );
    final input = ReceivePort();
    reply.send(input.sendPort);
    input.listen((message) {
      final id = message[0] as int;
      try {
        final stream = extractor.createStream();
        try {
          stream.acceptWaveform(
            samples: message[1] as Float32List,
            sampleRate: 16000,
          );
          stream.inputFinished();
          reply.send([id, extractor.compute(stream).toList()]);
        } finally {
          stream.free();
        }
      } catch (_) {
        reply.send([id, 'error']);
      }
    });
  } catch (_) {
    reply.send('error');
  }
}
