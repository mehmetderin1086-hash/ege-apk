// denge.dart yardımcılarının sınaması.
import 'package:bilgili_flutter/data/advanced/lise_metin/denge.dart';
import 'package:bilgili_flutter/data/advanced/lise_metin/ortak.dart';
import 'package:flutter_test/flutter_test.dart';

double _d(String s) =>
    double.parse(s.split(' ').first.replaceAll('−', '-').replaceAll(',', '.'));

void main() {
  test('hedefSira 5.000 vakada dengeli ve tuzlar bağımsız', () {
    for (final tuz in [0, 1, 2, 3]) {
      final say = List.filled(4, 0);
      for (var i = 0; i < lmAileBoyu; i++) {
        say[hedefSira(i, tuz)]++;
      }
      for (final n in say) {
        expect(n, inInclusiveRange(1150, 1350), reason: 'tuz $tuz: $say');
      }
    }
    final ikili = <(int, int), int>{};
    for (var i = 0; i < lmAileBoyu; i++) {
      final k = (hedefSira(i), hedefSira(i, 1));
      ikili[k] = (ikili[k] ?? 0) + 1;
    }
    expect(ikili, hasLength(16));
    expect(
      ikili.values.every((n) => n > 250 && n < 380),
      isTrue,
      reason: '$ikili',
    );
  });

  test('sıralı seçimler hedef sırayı tutturur', () {
    for (var i = 0; i < lmAileBoyu; i++) {
      final sira = hedefSira(i);
      final k = 20 + i % 60;
      final a = sayisalSirali(
        's',
        k,
        [k * 10, k ~/ 2, k * 2, k - 3, k + 7, k ~/ 10],
        'a',
        sira,
        positive: true,
      );
      expect(a.wrong.toSet(), hasLength(3));
      expect(
        a.wrong.where((w) => _d(w) < k).length,
        sira,
        reason: '$k $sira ${a.wrong}',
      );
      final x = 0.4 + (i % 37) / 10;
      final b = ondalikliSirali(
        's',
        x,
        [x * 10, x / 10, x * 2, x / 2],
        'a',
        sira,
        unit: 'km',
        positive: true,
      );
      expect(b.wrong.toSet(), hasLength(3));
      expect(b.wrong.any((w) => ayniSecenek(w, b.correct)), isFalse);
      expect(
        b.wrong.where((w) => _d(w) < _d(b.correct)).length,
        sira,
        reason: '${b.correct} $sira ${b.wrong}',
      );
      final n = 1 + i % 7, d = 9;
      final c = kesirliSirali(
        's',
        n,
        d,
        [(n, d + 2), (n + 2, d), (n * 2, d)],
        'a',
        sira,
      );
      expect(c.wrong.toSet(), hasLength(3));
      double kv(String s) {
        final p = s.split('/');
        return p.length == 1
            ? double.parse(p[0])
            : int.parse(p[0]) / int.parse(p[1]);
      }

      expect(
        c.wrong.where((w) => kv(w) < n / d).length,
        sira,
        reason: '${c.correct} $sira ${c.wrong}',
      );
    }
  });

  test('küme çeldiricileri farklı, boş değil ve anahtar dışı', () {
    for (final n in [3, 4]) {
      for (var anahtar = 1; anahtar < (1 << n); anahtar++) {
        for (var i = 0; i < lmAileBoyu; i += 7) {
          final c = kumeCeldiricileri(anahtar, n, i);
          expect(c.toSet(), hasLength(3));
          expect(c.contains(anahtar), isFalse);
          expect(c.every((m) => m > 0 && m < (1 << n)), isTrue);
        }
      }
    }
    expect(kumeYazimi(1), 'Yalnız I');
    expect(kumeYazimi(5), 'I ve III');
    expect(kumeYazimi(7), 'I, II ve III');
    expect(kumeYazimi(14), 'II, III ve IV');
  });
}
