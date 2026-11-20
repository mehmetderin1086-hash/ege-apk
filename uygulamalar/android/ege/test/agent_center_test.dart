import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/screens/agent_center_screen.dart';
import 'package:jarvis_mobile/screens/chat_screen.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<JarvisController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final c = JarvisController();
  await c.init(loadPlatformTelemetry: false);
  return c;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(786, 1746);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Widget _app(Widget child) => MaterialApp(
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.15)),
        child: w!,
      ),
      home: child,
    );

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Ajan Merkezi: tüm sekmeler, beceriler ve görev oluşturma', (tester) async {
    _phone(tester);
    final c = await _controller();
    await tester.pumpWidget(_app(AgentCenterScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('Ajan Merkezi'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing, reason: 'initial');
    expect(find.textContaining('MEMORY ['), findsOneWidget);
    expect(find.textContaining('USER ['), findsOneWidget);

    await _tab(tester, 'Beceriler');
    for (final n in ['biyoloji-ders-plani', 'sinav-sorusu-hazirla', 'gunluk-plan']) {
      expect(find.text(n), findsOneWidget);
    }
    await tester.tap(find.text('Yeni beceri'));
    await tester.pumpAndSettle();
    expect(find.text('SKILL.md'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await _tab(tester, 'Görevler');
    await tester.tap(find.text('Yeni görev'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cron_name')), 'Sabah özeti');
    await tester.enterText(find.byKey(const Key('cron_prompt')), 'Bugünün planını özetle');
    await tester.enterText(find.byKey(const Key('cron_when')), 'her gün 08:00');
    await tester.tap(find.text('Oluştur'));
    for (var attempt = 0; attempt < 30 && find.byKey(const Key('cron_name')).evaluate().isNotEmpty; attempt++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('cron_name')), findsNothing);
    expect(c.cronStore.jobs.length, 1);
    expect(find.text('Sabah özeti'), findsOneWidget);

    await _tab(tester, 'Kişilik');
    await tester.drag(find.text('SOUL (temel kişilik metni)'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Öğrenme döngüsü'), findsOneWidget);
    await _tab(tester, 'Arama');
    expect(find.text('Geçmiş sohbetlerde ara'), findsOneWidget);
    await _tab(tester, 'Araçlar');
    expect(find.text('Araç günlüğü'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('Sohbet: PC komutu onay kartı görünür', (tester) async {
    _phone(tester);
    final c = await _controller();
    await tester.pumpWidget(_app(Scaffold(body: ChatScreen(controller: c))));
    await tester.pump();
    expect(find.text('PC komutu onay bekliyor'), findsNothing);
    c.pendingApproval = (cmd: 'Remove-Item x', cwd: null, reason: 'silme');
    c.notifyChanged();
    await tester.pump();
    expect(find.text('PC komutu onay bekliyor'), findsOneWidget);
    expect(find.text('Remove-Item x'), findsOneWidget);
    expect(find.text('Onayla'), findsOneWidget);
    expect(find.text('Her zaman izin ver'), findsOneWidget);
    expect(find.text('Reddet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
