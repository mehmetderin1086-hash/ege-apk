// Seçkideki bütün soruları anahtarlarıyla JSON Lines olarak döker.
//   flutter test --no-pub --dart-define=SECKI_DOKUM=<dosya> tool/secki/dokum_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seçki dökümü', () {
    const yol = String.fromEnvironment('SECKI_DOKUM', defaultValue: 'build/secki.jsonl');
    final c = File(yol).openSync(mode: FileMode.write);
    var n = 0;
    for (final f in AdvancedCatalog.families) {
      for (var j = 0; j < f.count; j++) {
        final q = f.questionAt(j);
        c.writeStringSync('${jsonEncode({
          'id': q.id, 'aile': f.key, 'baslik': f.title, 'ders': f.lesson ?? f.topic.label,
          'gorsel': q.visual != null, 'soru': q.text, 'secenekler': q.options,
          'dogru': q.answer, 'aciklama': q.explanation,
          if (q.visual != null) 'veri': q.visual!.toJson(),
        })}\n');
        n++;
      }
    }
    c.closeSync();
    // ignore: avoid_print
    print('$n soru: $yol');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
