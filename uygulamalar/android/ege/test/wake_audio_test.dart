import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/services/wake_audio.dart';

void main() {
  test('quiet speech gains level without changing length', () {
    final n = WakeAudioNormalizer();
    final f = Float32List.fromList(
      List.generate(1600, (i) => i.isEven ? 0.002 : -0.002),
    );
    n.process(f);
    expect(f.length, 1600);
    expect(f.first, greaterThan(0.02));
  });
  test('silence stays zero', () {
    final f = Float32List(1600);
    WakeAudioNormalizer().process(f);
    expect(f.every((x) => x == 0), true);
  });
  test('very quiet speech is amplified and brief consonants keep gain', () {
    final n = WakeAudioNormalizer();
    final weak = Float32List.fromList(List.filled(1600, 0.0002));
    n.process(weak);
    expect(weak.first, greaterThan(0.005));
    final consonant = Float32List.fromList(List.filled(1600, 0.00004));
    n.process(consonant);
    expect(consonant.first, greaterThan(0.001));
    for (var i = 0; i < 30; i++) {
      n.process(Float32List(1600));
    }
    final quiet = Float32List.fromList(List.filled(1600, 0.00004));
    n.process(quiet);
    expect(quiet.first, lessThan(0.0001));
  });
  test('loud transition stays bounded after quiet frames', () {
    final n = WakeAudioNormalizer();
    n.process(Float32List.fromList(List.filled(1600, 0.001)));
    final f = Float32List.fromList([0.9, -0.9]);
    n.process(f);
    expect(f.every((x) => x >= -1 && x <= 1), true);
  });
}
