// Bağımsız çözüm denetimi için ailelerden örnek soru çıkarır. Sorular ve
// anahtarlar ayrı çalıştırmalarda, ayrı dosyalara yazılır; böylece soruları
// çözen denetçi anahtarı göremez.
//
//   flutter test --no-pub --dart-define=LM_ORNEK_DIR=<klasör> \
//     [--dart-define=LM_ORNEK_TOHUM=2] [--dart-define=LM_ORNEK_ADET=5] \
//     [--dart-define=LM_AILELER=lm_a,lm_b] [--dart-define=LM_ANAHTAR=true] \
//     tool/lise_metin/<alan>_ornek_test.dart
//
// LM_DOKUM=true verildiğinde seçili ailelerin bütün vakaları anahtarlarıyla
// birlikte <klasör>/dokum.jsonl dosyasına yazılır (yazar ve editörün bağımsız
// yeniden çözümü için). Tohum 1 ve 2 her ailenin ilk ve son vakasını da içerir.
import 'dart:convert';
import 'dart:io';

import 'package:bilgili_flutter/data/advanced/lise_metin/ortak.dart';
import 'package:flutter_test/flutter_test.dart';

const _harfler = ['A', 'B', 'C', 'D'];

void liseMetinOrnekle(String alan, List<AdvancedFamily> aileler) {
  test('$alan: bağımsız çözüm örnekleri', () async {
    const dir = String.fromEnvironment('LM_ORNEK_DIR');
    const anahtarYaz = bool.fromEnvironment('LM_ANAHTAR');
    const adet = int.fromEnvironment('LM_ORNEK_ADET', defaultValue: 5);
    const tohum = int.fromEnvironment('LM_ORNEK_TOHUM', defaultValue: 1);
    const secili = String.fromEnvironment('LM_AILELER');
    final istenen = secili.isEmpty ? null : secili.split(',').toSet();
    final hedef = Directory(dir.isEmpty ? 'build/lise-metin/$alan' : dir)
      ..createSync(recursive: true);
    if (const bool.fromEnvironment('LM_DOKUM')) {
      final cikti = File('${hedef.path}/dokum.jsonl').openWrite();
      var toplam = 0;
      for (final f in aileler) {
        if (istenen != null && !istenen.contains(f.key)) continue;
        for (var i = 0; i < f.count; i++) {
          final r = f.build(i);
          cikti.writeln(
            jsonEncode({
              'id': '${f.key}_$i',
              'aile': f.key,
              'i': i,
              'soru': r.prompt,
              'dogru': r.correct,
              'yanlis': r.wrong,
              'aciklama': r.explanation,
            }),
          );
          toplam++;
        }
      }
      await cikti.close();
      expect(toplam, greaterThan(0), reason: 'Dökülecek aile bulunamadı');
      // ignore: avoid_print
      print('$toplam vaka yazıldı: ${hedef.path}/dokum.jsonl');
      return;
    }
    final sorular = StringBuffer(), anahtar = StringBuffer();
    var n = 0;
    for (final f in aileler) {
      if (istenen != null && !istenen.contains(f.key)) continue;
      final salt = f.key.codeUnits.fold<int>(
        tohum * 7919,
        (x, y) => (x * 31 + y) & 0x3fffffff,
      );
      final sira = <int>{
        if (tohum <= 2) 0,
        if (tohum <= 2) f.count - 1,
        for (var k = 1; k <= adet + 4; k++)
          (salt * k + 104729 * k * k) % f.count,
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
        anahtar.writeln(
          jsonEncode({
            'n': n,
            'id': '${f.key}_$i',
            'aile': f.key,
            'baslik': f.title,
            'soru': r.prompt,
            'secenekler': secenekler,
            'dogru': _harfler[yer],
            'aciklama': r.explanation,
          }),
        );
      }
    }
    expect(n, greaterThan(0), reason: 'Örneklenecek aile bulunamadı');
    final dosya = anahtarYaz
        ? File('${hedef.path}/anahtar_t$tohum.jsonl')
        : File('${hedef.path}/sorular_t$tohum.txt');
    dosya.writeAsStringSync((anahtarYaz ? anahtar : sorular).toString());
    // ignore: avoid_print
    print('$n örnek yazıldı: ${dosya.path}');
  });
}
