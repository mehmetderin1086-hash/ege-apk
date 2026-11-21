import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:bilgili_flutter/data/advanced/common.dart';

/// Enumerates the same academic cases the Android game serves via questionAt.
void main() {
  test('generate and screen every published academic case', () async {
    const requested = String.fromEnvironment('BILGILI_REVIEW_DIR');
    final dest = Directory(
      requested.isEmpty ? 'build/academic-review' : requested,
    );
    dest.createSync(recursive: true);
    final bankDir = Directory('${dest.path}/sorular')
      ..createSync(recursive: true);
    final levels = <String, int>{},
        blooms = <String, int>{},
        formats = <String, int>{};
    final topics = <String, int>{}, visuals = <String, int>{};
    final binaryKeys = <String, int>{};
    final signatures = <String>{}, familyKeys = <String>{};
    final reportRows = <Map<String, dynamic>>[];
    int count = 0;
    void add(Map<String, int> map, String key) =>
        map[key] = (map[key] ?? 0) + 1;
    final normalizedSpaces = RegExp(r'\s+');
    String norm(String value) =>
        value.trim().replaceAll(normalizedSpaces, ' ').toLowerCase();
    for (final family in AdvancedCatalog.families) {
      if (!familyKeys.add(family.key) || family.count <= 0)
        fail('Invalid family ${family.key}');
      final file = File('${bankDir.path}/${family.key}.jsonl.gz').openWrite();
      final stream = gzip.encoder.startChunkedConversion(file);
      final sections = <String, int>{};
      final sampleRows = <Map<String, dynamic>>[];
      for (var i = 0; i < family.count; i++) {
        final raw = family.build(i);
        final q = family.questionAt(i);
        void require(bool ok, String reason) {
          if (!ok) fail('${q.id} [${family.title}] $reason');
        }

        require(
          q.id == 'ak38_${family.key}_$i' &&
              q.studyLevel == family.level.label &&
              q.bloom == family.bloom &&
              q.category == family.topic,
          'Kimlik, düzey veya kategori',
        );
        require(
          raw.prompt.trim().isNotEmpty &&
              raw.explanation.trim().length >= 12 &&
              q.explanation.trim().length >= 12,
          'Kök veya açıklama eksik',
        );
        require(
          raw.wrong.length == 3 &&
              {raw.correct, ...raw.wrong}.map(norm).toSet().length == 4 &&
              [raw.correct, ...raw.wrong].every((s) => s.trim().isNotEmpty),
          'Ham anahtar/çeldirici',
        );
        final visual = q.visual, activity = q.activity;
        require(
          visual?.kind == family.visualKind &&
              activity?.kind == family.activityKind,
          'Görsel/etkinlik türü',
        );
        if (visual != null) {
          require(visual.title.trim().isNotEmpty, 'Görsel başlığı eksik');
          switch (visual.kind) {
            case VisualKind.table:
              require(
                visual.columns.isNotEmpty &&
                    visual.rows.isNotEmpty &&
                    visual.rows.every((r) => r.length == visual.columns.length),
                'Tablo boyutları',
              );
            case VisualKind.barChart:
            case VisualKind.lineChart:
              require(
                visual.values.length >= 2 &&
                    visual.values.length == visual.labels.length &&
                    visual.values.every((v) => v.isFinite),
                'Grafik verisi',
              );
            case VisualKind.diagram:
              require(
                visual.elements.isNotEmpty &&
                    visual.elements.every(
                      (e) =>
                          e.x.isFinite &&
                          e.y.isFinite &&
                          const {
                            'circle',
                            'rectangle',
                            'triangle',
                            'point',
                            'line',
                            'arrow',
                            'text',
                          }.contains(e.shape),
                    ),
                'Şema verisi',
              );
            case VisualKind.image:
              require(
                visual.assetPath != null &&
                    File(visual.assetPath!).existsSync(),
                'Resim dosyası',
              );
          }
          add(visuals, visual.kind.name);
        }
        if (activity != null) {
          if (activity.kind == ActivityKind.ordering ||
              activity.kind == ActivityKind.matching) {
            final n = activity.kind == ActivityKind.ordering
                ? activity.items.length
                : activity.left.length;
            require(
              n >= 2 &&
                  activity.solution.length == n &&
                  activity.solution.toSet().length == n &&
                  activity.solution.every((v) => v >= 0 && v < n) &&
                  (activity.kind != ActivityKind.matching ||
                      activity.right.length == n),
              'Etkinlik eşlemesi',
            );
          } else {
            require(
              activity.transcript?.trim().isNotEmpty == true,
              'Ses/metin girdisi',
            );
          }
        }
        require(
          q.responseType == family.responseAt(i) &&
              q.answer >= 0 &&
              q.answer < q.options.length &&
              q.options.map(norm).toSet().length == q.options.length,
          'Cevap biçimi veya seçenekler',
        );
        if (q.responseType == ResponseType.fill) {
          require(
            q.acceptsWritten(raw.correct) &&
                raw.wrong.every((s) => !q.acceptsWritten(s)),
            'Yazılı yanıt denetimi',
          );
        }
        if (q.responseType == ResponseType.trueFalse) {
          require(
            q.options.length == 2 &&
                (q.answer == 0) ==
                    q.text.contains('“${raw.correct}”. Bu yanıt doğru mu?'),
            'Doğru/yanlış önermesi',
          );
          add(binaryKeys, q.options[q.answer]);
        }
        require(
          (q.bloom == BloomLevel.yaratma) == (q.creation != null),
          'Yaratma görevi',
        );
        if (q.creation != null) {
          require(
            q.creation!.brief.trim().length > 16 &&
                q.creation!.criteria.length >= 2 &&
                q.creation!.criteria.every((s) => s.trim().isNotEmpty),
            'Açık uçlu yönerge/ölçüt',
          );
        }
        if (q.multiSelect != null) {
          final task = q.multiSelect!;
          require(
            task.options.length >= 3 &&
                task.correct.length >= 2 &&
                task.correct.length < task.options.length &&
                task.correct.toSet().length == task.correct.length &&
                task.correct.every((v) => v >= 0 && v < task.options.length) &&
                task.matches(task.correct.toSet()),
            'Çoklu seçim anahtarı',
          );
        }
        // Choice order, feedback, answer type and IDs cannot make a case unique.
        final evidence = [
          norm(q.multiSelect?.prompt ?? raw.prompt),
          if (visual != null) visual.toJson(),
          if (activity != null) ({...activity.toJson()}..remove('solution')),
          if (q.multiSelect != null)
            (q.multiSelect!.options.map(norm).toList()..sort()),
          if (q.creation != null) norm(q.creation!.brief),
        ];
        final signature = sha256
            .convert(utf8.encode(jsonEncode(evidence)))
            .toString();
        require(signatures.add(signature), 'Yinelenen soru ve kanıt');
        add(levels, q.studyLevel!);
        add(blooms, q.bloom!.label);
        add(formats, q.responseType.label);
        add(sections, q.responseType.label);
        add(topics, q.category.label);
        stream.add(utf8.encode('${jsonEncode(q.toJson())}\n'));
        if (i == 0 || i == family.count ~/ 2 || i == family.count - 1)
          sampleRows.add(q.toJson());
        count++;
      }
      stream.close();
      await file.done;
      reportRows.add({
        'key': family.key,
        'family': family.title,
        'count': family.count,
        'level': family.level.label,
        'topic': family.topic.label,
        'bloom': family.bloom.label,
        'formats': sections,
        'samples': sampleRows,
      });
    }
    expect(count, 2270439);
    expect(signatures.length, count);
    expect(blooms.keys.toSet(), BloomLevel.values.map((b) => b.label).toSet());
    expect(
      formats.keys.toSet(),
      ResponseType.values.map((s) => s.label).toSet(),
    );
    expect(levels.length, 2);
    final summary = {
      'questions': count,
      'families': familyKeys.length,
      'uniqueCases': signatures.length,
      'levels': levels,
      'bloom': blooms,
      'formats': formats,
      'topics': topics,
      'visuals': visuals,
      'trueFalseKeys': binaryKeys,
    };
    const pretty = JsonEncoder.withIndent('  ');
    File('${dest.path}/ozet.json').writeAsStringSync(pretty.convert(summary));
    File('${dest.path}/aile-ornekleri.json')
        .writeAsStringSync(pretty.convert(reportRows));
    print(jsonEncode(summary));
  }, timeout: const Timeout(Duration(minutes: 45)));
}
