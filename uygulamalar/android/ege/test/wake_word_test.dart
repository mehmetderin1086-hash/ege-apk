import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/screens/wake_tune_screen.dart';
import 'package:jarvis_mobile/services/wake_calibration.dart';
import 'package:jarvis_mobile/services/wake_word.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';

void main() {
  test('duyarlılık eğrisi: varsayılan PC ölçümündeki en iyi nokta (4.6.0)', () {
    final def = WakeWordEngine.tuning(0.5);
    // Ölçüm: eşik 0,01 / puan 3 → %84 yakalama, 520 olumsuzda 0 yanlış alarm.
    expect(def.threshold, closeTo(0.011, 0.0005));
    expect(def.boost, closeTo(3.0, 0.001));
    expect(WakeWordEngine.tuning(0).threshold, closeTo(0.06, 0.001));
    expect(WakeWordEngine.tuning(1).threshold, closeTo(0.004, 0.0005));
    // Duyarlılık arttıkça eşik monoton azalır.
    var last = 1.0;
    for (var s = 0.0; s <= 1.0; s += 0.1) {
      final th = WakeWordEngine.tuning(s).threshold;
      expect(th, lessThanOrEqualTo(last));
      last = th;
    }
  });

  test('Asistan ölçülmüş fonetik yolları kullanır, Jarvis içermez', () {
    final line = WakeWordEngine.keywordLine(0.5);
    final parts = line.split('/');
    expect(parts, hasLength(WakeWordEngine.defaultPaths.length));
    for (final p in WakeWordEngine.defaultPaths) {
      expect(line, contains('$p :3.00 #0.011 @ASISTAN'));
    }
    expect(line, isNot(contains('JARVIS')));
    // Eski Hey Ege kalıpları kullanılmaz.
    for (final p in WakeWordEngine.defaultPaths) {
      expect(p.startsWith('▁A'), isTrue, reason: p);
    }
    expect(WakeWordEngine.defaultPaths.toSet(), hasLength(4));
  });

  test('kişisel yollar Asistan sözcüğüne aittir ve eşik alt sınırı korunur', () {
    for (final p in WakeCalibration.extraPaths) {
      expect(p.startsWith('▁AS'),
          isTrue, reason: p);
    }
    expect(WakeCalibration.floor, greaterThan(0));
    expect(WakeCalibration.ladder.first, greaterThan(WakeCalibration.ladder.last));
    expect(WakeCalibration.ladder.last, WakeCalibration.floor);
  });

  testWidgets('kalibrasyon ekranı beş kayıt ister ve uyandırmayı duraklatır', (
    tester,
  ) async {
    const channel = MethodChannel('com.jarvis.assistant/device');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final c = JarvisController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(home: WakeTuneScreen(controller: c)),
    );
    await tester.pump();
    expect(find.text('1. kaydı başlat'), findsOneWidget);
    expect(find.byKey(const Key('wake_tune_save')), findsNothing);
    expect(c.wakeWordStoppedByUser, isTrue);
    expect(WakeTuneScreen.sampleCount, 5);
    await tester.pumpWidget(const SizedBox());
    expect(c.wakeWordStoppedByUser, isFalse);
  });
}
