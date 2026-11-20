// Ekran önizlemeleri: yalnız `--dart-define=UI_PREVIEW=<klasör>` ile PNG yazar.
// Normal test koşusunda yalnız ekranların taşmadan çizildiğini denetler.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/screens/home_shell.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:jarvis_mobile/widgets/chat_palette.dart';

const _out = String.fromEnvironment('UI_PREVIEW');
const _fontDir = 'C:/src/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadFonts() async {
  if (!Directory(_fontDir).existsSync()) return;
  Future<ByteData> f(String n) async =>
      ByteData.sublistView(await File('$_fontDir/$n').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final n in [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-light.ttf',
  ]) {
    roboto.addFont(f(n));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(f('materialicons-regular.otf'));
  await icons.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jarvis.assistant/device');

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    if (_out.isNotEmpty) await _loadFonts();
  });

  final tabs = <String, int>{
    'sohbet': 0,
    'canli': 1,
    'araclar': 2,
    'studyo': 3,
    'ayarlar': 4,
    'pc': 5,
    'canli_konusuyor': 1,
  };

  for (final dark in [true, false]) {
    for (final entry in tabs.entries) {
      testWidgets('önizleme ${entry.key} ${dark ? 'koyu' : 'açık'}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.77;
        addTearDown(tester.view.reset);
        final c = JarvisController();
        ChatPalette.configure(dark ? 'dark' : 'light', 0xFFB85C3D, dark);
        c.settings = c.settings.copyWith(themeMode: dark ? 'dark' : 'light');
        c.openTab(entry.value);
        if (entry.key == 'canli_konusuyor') {
          c.liveLoopActive = true;
          c.livePhase = LiveVoicePhase.speaking;
          c.orbAmplitude = 0.8;
        }
        if (entry.key.startsWith('canli')) {
          c.liveTranscript = 'Yarın sabah yedide beni uyandır.';
          c.liveAssistantReply = 'Tamam, yarın 07.00 için alarm kurdum.';
          c.lastSttInfo = 'Gemini STT • 1,9 sn';
        }
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ChatPalette.theme,
              home: AnimatedBuilder(
                animation: c,
                builder: (_, _) => HomeShell(controller: c),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        if (_out.isNotEmpty) {
          await tester.runAsync(() async {
            final ro =
                boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await ro.toImage(pixelRatio: 1);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            Directory(_out).createSync(recursive: true);
            await File(
              '$_out/${entry.key}_${dark ? 'koyu' : 'acik'}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await tester.pump(const Duration(seconds: 2));
      });
    }
  }
}
