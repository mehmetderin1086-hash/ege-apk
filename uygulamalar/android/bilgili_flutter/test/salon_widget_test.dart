import 'package:bilgili_flutter/screens/arena_salon.dart';
import 'package:bilgili_flutter/state/arena_controller.dart';
import 'package:bilgili_flutter/state/arena_rooms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> ac(WidgetTester tester, Widget ekran) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: ekran));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  }

  testWidgets('salon ekranları dar ekranda taşmadan çizilir', (tester) async {
    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);
    await ac(tester, OyunModlariScreen(controller: ctrl));
    expect(find.text('Bire Bir'), findsOneWidget);
    expect(find.text('Oda No Gir'), findsOneWidget);

    final oda = OdaAyari(tohum: 42);
    await ac(tester, OzelOdaScreen(controller: ctrl, oda: oda));
    expect(find.text('Oda Numarası'), findsOneWidget);
    await tester.tap(find.text('14'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Oyunu Başlat'), 200);
    expect(find.text('1/10'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await ac(tester, EtkinliklerScreen(controller: ctrl));
    expect(find.text('Etkinlikler'), findsOneWidget);
    expect(find.text('Güncel'), findsOneWidget);
  });
}
