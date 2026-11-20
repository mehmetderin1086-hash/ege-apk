import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/screens/home_shell.dart';
import 'package:jarvis_mobile/screens/whatsapp_screen.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:jarvis_mobile/widgets/jarvis_fx.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jarvis.assistant/device');

  setUpAll(() async {
    if (const bool.fromEnvironment('UI_PREVIEW')) {
      final flutterSdk =
          Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
      for (final font in {
        'Roboto': 'roboto-regular.ttf',
        'Ahem': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final loader = FontLoader(font.key);
        loader.addFont(
          File('$flutterSdk/bin/cache/artifacts/material_fonts/${font.value}')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
        await loader.load();
      }
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    JFx.userEnabled.value = false;
  });

  testWidgets(
    'conversation fits phone and keyboard, drawer keeps tools reachable',
    (tester) async {
      final c = JarvisController();
      final boundary = GlobalKey();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundary,
            child: AnimatedBuilder(
              animation: c,
              builder: (_, _) => HomeShell(controller: c),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.byKey(const Key('empty_chat_canvas')), findsOneWidget);
      expect(find.text('Bugün nasıl yardımcı olabilirim?'), findsNothing);
      expect(find.byTooltip('Canlı Ses'), findsOneWidget);
      expect(tester.takeException(), isNull);

      if (const bool.fromEnvironment('UI_PREVIEW')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('../dist/JARVIS-home-preview.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.enterText(find.byType(TextField), 'Bir soru');
      await tester.pump();
      expect(find.byTooltip('Gönder'), findsOneWidget);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Gönder').hitTestable(), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Menü'));
      await tester.pumpAndSettle();
      expect(find.text('WhatsApp'), findsOneWidget);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      await tester.tap(find.text('Araçlar'));
      await tester.pumpAndSettle();
      expect(c.mainTabIndex, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  testWidgets('live and centralized settings fit a small phone', (tester) async {
    final c = JarvisController();
    final boundary = GlobalKey();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c.openTab(1);
    await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: boundary, child: AnimatedBuilder(animation: c, builder: (_, _) => HomeShell(controller: c)))));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Konuşmayı Başlat').hitTestable(), findsOneWidget);
    expect(find.text('Gemini Live'), findsNothing);
    if (const bool.fromEnvironment('UI_PREVIEW')) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('../dist/JARVIS-4.3-live.png').writeAsBytes(data!.buffer.asUint8List()); image.dispose();
      });
    }
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Oturumu Bitir').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Ayarlar')); await tester.pumpAndSettle();
    expect(find.text('Ayarları Kaydet').hitTestable(), findsOneWidget);
    expect(find.text('Uygulama kontrolü'), findsOneWidget);
    await tester.tap(find.text('Canlı ses')); await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Canlı ses')); await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844); await tester.pumpAndSettle();
    if (const bool.fromEnvironment('UI_PREVIEW')) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('../dist/JARVIS-4.3-settings.png').writeAsBytes(data!.buffer.asUint8List()); image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink()); c.dispose();
  });

  testWidgets(
    'WhatsApp filters notifications, prepares drafts and opens the selected conversation',
    (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'notificationAccess') return true;
            if (call.method == 'recentNotifications') {
              return [
                {
                  'package': 'com.whatsapp',
                  'title': 'Ayşe',
                  'text': 'Toplantı saat üçte.',
                  'key': 'wa-1',
                },
                {
                  'package': 'com.whatsapp.w4b',
                  'title': 'İş',
                  'text': 'Dosya hazır.',
                  'key': 'wa-2',
                },
                {
                  'package': 'org.telegram.messenger',
                  'title': 'Başka uygulama',
                  'text': 'Gizli',
                  'key': 'other',
                },
              ];
            }
            if (call.method == 'openWhatsAppNotification') return true;
            return null;
          });
      final c = JarvisController();
      await tester.pumpWidget(MaterialApp(home: WhatsAppScreen(controller: c)));
      await tester.pumpAndSettle();
      expect(find.text('Başka uygulama'), findsNothing);
      await tester.tap(find.text('Gecikeceğim'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        contains('gecikeceğim'),
      );
      await tester.tap(find.text('WhatsApp’ta aç'));
      await tester.pumpAndSettle();
      expect(
        find.text('Bir kişi adı veya telefon numarası gir.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.byKey(const ValueKey('open-whatsapp-wa-1')), 250,
        scrollable: find.byType(Scrollable).first);
      expect(find.text('Ayşe'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open-whatsapp-wa-1')));
      await tester.pump();
      expect(
        calls
            .where((call) => call.method == 'openWhatsAppNotification')
            .single
            .arguments,
        {'key': 'wa-1'},
      );
      expect(
        calls.where((call) => call.method == 'replyNotification'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
