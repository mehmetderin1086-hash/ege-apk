import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'wake_audio.dart';

/// "Asistan"yi kullanıcının kendi söyleyişine göre ayarlar.
///
/// Kullanıcının birkaç "Asistan" kaydı, cihazdaki aynı anahtar sözcük
/// modeliyle (uygulamadaki gibi çift akış: ham + ses yükseltilmiş) bir dizi
/// fonetik yol ve eşik üzerinde denenir. Kaydı yakalayan yollar, yakalandıkları
/// en sıkı eşiğe göre kişisel anahtar sözcük satırına yazılır. Ses telefondan
/// çıkmaz; sonuç `kws/asistan_keywords.txt` dosyasında tutulur ve uyandırma
/// servisi (ayrı Flutter motoru) bu dosyayı okur.
class WakeCalibration {
  WakeCalibration._();

  /// Kişiselleştirmede ek olarak denenen söyleniş yolları. Varsayılan yollar
  /// (`WakeWordEngine.defaultPaths`) her zaman korunur.
  static const extraPaths = <String>[
    '▁AS ▁HIS T ANT',
    '▁AS ▁IS T ANT',
    '▁AS IST AN',
  ];

  /// Denenen eşikler; en sıkıdan en gevşeğe.
  static const ladder = <double>[
    0.30,
    0.25,
    0.20,
    0.15,
    0.12,
    0.10,
    0.08,
    0.06,
    0.04,
    0.03,
    0.02,
    0.01,
  ];

  /// Kişisel yolların alt sınırı: PC ölçümünde yanlış alarm vermeyen en
  /// gevşek eşik.
  static const floor = 0.01;
  static const boost = 3.0;

  static Future<File> customFile() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/kws/asistan_keywords.txt');
  }

  /// Kayıtlı kişisel satır; yoksa null.
  static Future<String?> savedLine() async {
    try {
      final f = await customFile();
      if (!f.existsSync()) return null;
      final s = f.readAsStringSync().trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final f = await customFile();
    if (f.existsSync()) f.deleteSync();
  }

  /// [clips]: 16 kHz mono örnekler (-1..1). [defaultPaths] her zaman satırda
  /// kalır. Döner: her kayıt için yakalandı mı, ve kaydedilecek satır.
  static Future<WakeCalibrationResult> calibrate({
    required String modelDir,
    required List<Float32List> clips,
    required List<String> defaultPaths,
    required double defaultThreshold,
  }) {
    final paths = [
      ...defaultPaths,
      ...extraPaths.where((p) => !defaultPaths.contains(p)),
    ];
    return Isolate.run(
      () => _calibrate(modelDir, clips, paths, defaultPaths, defaultThreshold),
    );
  }

  static WakeCalibrationResult _calibrate(
    String dir,
    List<Float32List> clips,
    List<String> paths,
    List<String> defaults,
    double defaultThreshold,
  ) {
    so.initBindings();
    // Her yol için her kaydın yakalandığı en sıkı eşik (0 = hiç).
    final best = <String, List<double>>{};
    for (final p in paths) {
      best[p] = List.filled(clips.length, 0.0);
    }
    for (final th in ladder) {
      final line = paths
          .map(
            (p) =>
                '$p :${boost.toStringAsFixed(2)} #${th.toStringAsFixed(2)} @P${paths.indexOf(p)}',
          )
          .join('/');
      // Bir eşikte tüm yolları tek algılayıcıda dener; hangi yolun
      // yakaladığını etiketten okur.
      final spotter = so.KeywordSpotter(
        so.KeywordSpotterConfig(
          model: so.OnlineModelConfig(
            transducer: so.OnlineTransducerModelConfig(
              encoder: '$dir/encoder.int8.onnx',
              decoder: '$dir/decoder.int8.onnx',
              joiner: '$dir/joiner.int8.onnx',
            ),
            tokens: '$dir/tokens.txt',
            numThreads: 2,
            debug: false,
          ),
          keywordsFile: '$dir/keywords.txt',
        ),
      );
      try {
        for (var c = 0; c < clips.length; c++) {
          for (final hit in _detectAll(spotter, line, clips[c])) {
            final idx = int.tryParse(hit.replaceFirst('P', ''));
            if (idx == null || idx < 0 || idx >= paths.length) continue;
            final list = best[paths[idx]]!;
            if (list[c] == 0) list[c] = th;
          }
        }
      } finally {
        spotter.free();
      }
    }
    final caught = List.generate(
      clips.length,
      (c) => paths.any((p) => best[p]![c] > 0),
    );
    final lines = <String>[];
    final b = boost.toStringAsFixed(2);
    for (final p in defaults) {
      lines.add('$p :$b #${defaultThreshold.toStringAsFixed(3)} @ASISTAN');
    }
    for (final p in paths.where((p) => !defaults.contains(p))) {
      final hits = best[p]!.where((v) => v > 0).toList();
      if (hits.isEmpty) continue;
      // En zayıf yakalamanın yarısı kadar pay bırak; alt sınırın altına inme.
      final weakest = hits.reduce((a, b) => a < b ? a : b);
      final th = (weakest / 2).clamp(floor, 0.20);
      lines.add('$p :$b #${th.toStringAsFixed(3)} @ASISTAN');
    }
    return WakeCalibrationResult(
      caught: caught,
      line: lines.join('/'),
      personalPaths: lines.length - defaults.length,
    );
  }

  /// Uygulamadaki gibi ham ve ses yükseltilmiş iki akışla dener; yakalanan
  /// tüm etiketleri döner.
  static Set<String> _detectAll(
    so.KeywordSpotter spotter,
    String line,
    Float32List clip,
  ) {
    final found = <String>{};
    final raw = spotter.createStream(keywords: line);
    final loud = spotter.createStream(keywords: line);
    final norm = WakeAudioNormalizer();
    try {
      final pad = Float32List(8000);
      final audio = Float32List(clip.length + pad.length * 3)
        ..setRange(pad.length, pad.length + clip.length, clip);
      const step = 1600;
      for (var i = 0; i < audio.length; i += step) {
        final end = (i + step).clamp(0, audio.length);
        final a = Float32List.fromList(audio.sublist(i, end));
        final b = Float32List.fromList(a);
        norm.process(b);
        raw.acceptWaveform(samples: a, sampleRate: 16000);
        loud.acceptWaveform(samples: b, sampleRate: 16000);
        for (final s in [raw, loud]) {
          while (spotter.isReady(s)) {
            spotter.decode(s);
            final kw = spotter.getResult(s).keyword;
            if (kw.isNotEmpty) {
              found.add(kw);
              spotter.reset(s);
            }
          }
        }
      }
    } finally {
      raw.free();
      loud.free();
    }
    return found;
  }
}

class WakeCalibrationResult {
  const WakeCalibrationResult({
    required this.caught,
    required this.line,
    required this.personalPaths,
  });

  /// Her kayıt için: en az bir yol yakaladı mı.
  final List<bool> caught;

  /// Kaydedilecek anahtar sözcük satırı.
  final String line;

  /// Varsayılanlara eklenen kişisel yol sayısı.
  final int personalPaths;

  int get caughtCount => caught.where((c) => c).length;
}
