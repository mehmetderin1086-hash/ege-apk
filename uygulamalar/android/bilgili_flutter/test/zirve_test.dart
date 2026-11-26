import 'package:bilgili_flutter/models/quiz_models.dart';
import 'package:bilgili_flutter/screens/zirve_screen.dart';
import 'package:bilgili_flutter/state/arena_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merdiven: 15 basamak, barajlar ve güvence puanı', () {
    expect(ZirveMerdiveni.odul, hasLength(15));
    expect(ZirveMerdiveni.guvence(0), 0);
    expect(ZirveMerdiveni.guvence(5), 2000);
    expect(ZirveMerdiveni.guvence(9), 2000);
    expect(ZirveMerdiveni.guvence(10), 25000);
    expect(ZirveMerdiveni.guvence(14), 25000);
    expect(puanYaz(1000000), '1.000.000');
    expect(puanYaz(250), '250');
  });

  test('soru seti zorluk sırasıyla gelir, tekrarsızdır, her soru dört seçeneklidir', () {
    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);
    for (final topic in [Topic.mixed, Topic.history, Topic.science]) {
      final paket = ctrl.zirveSorulari(topic: topic, seed: 7)!;
      expect(paket.sorular, hasLength(15));
      expect(paket.sorular.map((q) => q.id).toSet(), hasLength(15));
      for (var i = 0; i < 15; i++) {
        final q = paket.sorular[i];
        expect(q.options, hasLength(4));
        expect(q.difficulty, Difficulty.values[i ~/ 5]);
      }
      expect(paket.yedek.keys.toSet(), Difficulty.values.toSet());
    }
    ctrl.zirveKaydet(kazanc: 2000, basamak: 5);
    ctrl.zirveKaydet(kazanc: 500, basamak: 3);
    expect(ctrl.zirveEnIyi, 2000);
    expect(ctrl.zirveEnUstBasamak, 5);
  });

  testWidgets('zirve ekranı çizilir, joker ve cevap akışı çalışır', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(360, 800), disableAnimations: true),
      child: ZirveScreen(controller: ctrl),
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Zirve Merdiveni'), findsOneWidget);
    await tester.tap(find.text('Başla'));
    await tester.pump();
    expect(find.textContaining('Soru 1'), findsOneWidget);
    await tester.tap(find.text('50:50'));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('elendi')), findsNWidgets(2));
    await tester.tap(find.text('Salon'));
    await tester.pump();
    expect(find.text('Salon oylaması'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Çekil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Çekil').last);
    await tester.pumpAndSettle();
    expect(find.text('Çekildin.'), findsOneWidget);
    expect(find.text('Yeniden Oyna'), findsOneWidget);
  });
}
