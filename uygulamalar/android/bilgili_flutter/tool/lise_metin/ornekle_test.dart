// Bağımsız çözüm denetimi için her aileden örnek sorular çıkarır. Sorular ve
// anahtarlar ayrı dosyalara yazılır; denetçi yalnız soru dosyasını görür.
//
//   flutter test --no-pub --dart-define=LM_ORNEK_DIR=build/lise-metin \
//     [--dart-define=LM_ANAHTAR=1] tool/lise_metin/ornekle_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:bilgili_flutter/data/advanced/lise_metin/biyoloji.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/cografya_tarih.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/dil.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/fizik_elektrik.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/fizik_mekanik.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/geometri.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/kimya.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/mat_ileri.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/mat_temel.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/ortak.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/veri_olasilik.dart';
import 'package:flutter_test/flutter_test.dart';

const _harfler = ['A', 'B', 'C', 'D'];

void main() {
  test('her aileden bağımsız çözüm örnekleri', () {
    const dir = String.fromEnvironment('LM_ORNEK_DIR');
    const anahtarYaz = bool.fromEnvironment('LM_ANAHTAR');
    const adet = int.fromEnvironment('LM_ORNEK_ADET', defaultValue: 5);
    const tohum = int.fromEnvironment('LM_ORNEK_TOHUM', defaultValue: 1);
    final hedef = Directory(dir.isEmpty ? 'build/lise-metin' : dir)
      ..createSync(recursive: true);
    final gruplar = <String, List<AdvancedFamily>>{
      'mat': [...lmMatTemel, ...lmMatIleri],
      'geo_veri': [...lmGeometri, ...lmVeriOlasilik],
      'fizik': [...lmFizikMekanik, ...lmFizikElektrik],
      'kimya_biyoloji': [...lmKimya, ...lmBiyoloji],
      'sozel': [...lmCografyaTarih, ...lmDil],
    };
    var n = 0;
    gruplar.forEach((grup, aileler) {
      final sorular = StringBuffer(), anahtar = StringBuffer();
      for (final f in aileler) {
        final salt = f.key.codeUnits.fold<int>(tohum * 7919, (x, y) => x * 31 + y & 0x3fffffff);
        final sira = <int>{
          if (tohum == 1) 0,
          if (tohum == 1) f.count - 1,
          for (var k = 1; k <= adet + 2; k++) (salt * k + 104729 * k * k) % f.count,
        }.take(adet).toList();
        for (final i in sira) {
          final r = f.build(i);
          final yer = (salt + i) % 4;
          final secenekler = [...r.wrong]..insert(yer, r.correct);
          n++;
          sorular
            ..writeln('#$n [${f.key}_$i] ${f.lesson} · ${f.title}')
            ..writeln(r.prompt);
          for (var j = 0; j < 4; j++) {
            sorular.writeln('${_harfler[j]}) ${secenekler[j]}');
          }
          sorular.writeln();
          anahtar.writeln(jsonEncode({
            'n': n,
            'id': '${f.key}_$i',
            'dogru': _harfler[yer],
            'yanit': r.correct,
            'aciklama': r.explanation,
          }));
        }
      }
      File('${hedef.path}/sorular_$grup.txt').writeAsStringSync(sorular.toString());
      if (anahtarYaz) {
        File('${hedef.path}/anahtar_$grup.jsonl').writeAsStringSync(anahtar.toString());
      }
    });
    // ignore: avoid_print
    print('$n örnek soru yazıldı: ${hedef.path}');
  });
}
