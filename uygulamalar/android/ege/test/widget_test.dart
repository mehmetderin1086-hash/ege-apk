import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/main.dart';
import 'package:jarvis_mobile/screens/settings_screen.dart';
import 'package:jarvis_mobile/screens/studio_screen.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:jarvis_mobile/widgets/markdown_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('JarvisApp renders standalone mobile tabs and executes offline timer',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = JarvisController();

    await tester.pumpWidget(
      JarvisApp(
        controller: controller,
        loadPlatformTelemetry: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Welcome screen visible
    expect(find.text('Ege'), findsOneWidget);
    expect(find.byKey(const Key('empty_chat_canvas')), findsOneWidget);
      expect(find.text('Bugün nasıl yardımcı olabilirim?'), findsNothing);

    // Execute offline quick timer command directly
    await controller.sendMessage('5 dk çay sayacı kur');
    await tester.pump();
    expect(controller.activeTimers.length, 1);
    expect(find.textContaining('zamanlayıcı başlatıldı'), findsOneWidget);

    // Switch across remaining navigation tabs
    await tester.tap(find.byTooltip('Canlı Ses'));
    await tester.pump();
    expect(find.byTooltip('Konuşmayı Başlat'), findsOneWidget);
    expect(find.text('Gemini Live'), findsNothing);
    expect(find.text('OpenAI Live'), findsNothing);
    expect(controller.settings.liveEngine, 'turn_based');
    await tester.tap(find.byTooltip('Sohbete dön'));
    await tester.pump();
    await tester.tap(find.byTooltip('Menü'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Araçlar'));
    await tester.pump();
    expect(find.text('Sayaçlar'), findsOneWidget);
    expect(find.text('Hesap Makinesi'), findsOneWidget);
    expect(find.text('Web'), findsOneWidget);
    expect(find.text('İndir'), findsOneWidget);

    await tester.tap(find.text('Cihaz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(
      find.text('Telefon Denetim Merkezi'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Telefon Denetim Merkezi'), findsOneWidget);
    expect(find.text('El Feneri'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Hızlı Sistem Kontrolleri'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Hızlı Sistem Kontrolleri'), findsOneWidget);

    await tester.tap(find.text('Web'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Web Kazıma & Arama'), findsOneWidget);

    await tester.tap(find.text('İndir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('İndirme Merkezi'), findsOneWidget);

    await tester.tap(find.text('Stüdyo'));
    await tester.pump();
    expect(find.text('Ege Merkezi'), findsOneWidget);
    expect(find.text('Çalışmalar'), findsOneWidget);
    final studioScroll = find
        .descendant(
          of: find.byType(StudioScreen),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Görsel Üret (Proxy Modelleri)'),
      250,
      scrollable: studioScroll,
    );
    expect(find.text('Görsel Üret (Proxy Modelleri)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Derin Araştırmayı Başlat'),
      250,
      scrollable: studioScroll,
    );
    expect(find.text('Derin Araştırma (Web + Çoklu Kaynak)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Hızlı Üretim Araçları'),
      250,
      scrollable: studioScroll,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Hızlı Üretim Araçları'), findsOneWidget);

    await tester.tap(find.text('Ayarlar'));
    await tester.pump();
    expect(find.text('Ayarları Kaydet'), findsOneWidget);
    final settingsScroll = find
        .descendant(
          of: find.byType(SettingsScreen),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    await tester.scrollUntilVisible(find.text('Bağlantı ve modeller'), 200, scrollable: settingsScroll);
    await tester.tap(find.text('Bağlantı ve modeller'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Telefon CLI Proxy (127.0.0.1:8317)'),
      250,
      scrollable: settingsScroll,
    );
    expect(find.text('AI Sağlayıcı'), findsOneWidget);
    expect(find.text('Telefon CLI Proxy (127.0.0.1:8317)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ajan Web & Telefon Araçları'),
      300,
      scrollable: settingsScroll,
    );
    expect(find.text('Ajan Web & Telefon Araçları'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Bağlantı ve modeller'), -300, scrollable: settingsScroll);
    await tester.tap(find.text('Bağlantı ve modeller'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Seslendirme'), 200, scrollable: settingsScroll);
    await tester.tap(find.text('Seslendirme'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Bulut Ses Motoru (TTS)'),
      300,
      scrollable: settingsScroll,
    );
    expect(find.text('Bulut Ses Motoru (TTS)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Azure / Google Chirp 3 HD TTS Kullan'),
      300,
      scrollable: settingsScroll,
    );
    expect(
      find.text('Azure / Google Chirp 3 HD TTS Kullan'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Bulut Seslerini Tanıla'),
      300,
      scrollable: settingsScroll,
    );
    expect(find.text('Bulut Seslerini Tanıla'), findsOneWidget);
    await tester.tap(find.byTooltip('Sohbete dön'));
    await tester.pumpAndSettle();
    // Open AppBar model picker bottom sheet and select a catalog model
    await tester.tap(find.byKey(const Key('appbar_model_picker_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('Model Seç ('), findsOneWidget);

    await tester.tap(find.text('claude-sonnet-5-5'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(controller.settings.model, 'claude-sonnet-5-5');

    controller.dispose();
  });

  testWidgets('MarkdownMessage renders headings, code blocks and tables',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownMessage(
              text: '''
# Başlık

Burada **kalın** ve `kod` var.

```dart
print('Merhaba');
```

| Anahtar | Değer |
| --- | --- |
| Mod | Bağımsız |
''',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Başlık'), findsOneWidget);
    expect(find.text('dart'), findsOneWidget);
    expect(find.text('Kopyala'), findsOneWidget);
    expect(find.text('Anahtar'), findsOneWidget);
    expect(find.text('Bağımsız'), findsOneWidget);
  });
}
