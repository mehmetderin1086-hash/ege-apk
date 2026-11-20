import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asistan_flutter/services/asistan_controller.dart';
import 'package:asistan_flutter/services/ai_engine.dart';
import 'package:asistan_flutter/models/asistan_models.dart';
import 'package:asistan_flutter/ui/live_voice_screen.dart';

void main() {
  test(
    'Alarm follow-up resolves without network and cancellation clears it',
    () async {
      final calls = <String>[];
      final engine = AiEngine(
        nativeCaller: (method, [args]) async {
          calls.add(method);
          return {'ok': true, 'message': 'Alarm ekranı açıldı.'};
        },
      );
      Future<AiTurnOutcome> send(String text) => engine.processUserTurn(
        prompt: text,
        mode: WorkMode.voice,
        selectedModel: 'test',
        history: [],
        memories: [],
        mcpServers: [],
        onReminderCreated: (_) {},
        onMemoryAdded: (_) {},
      );
      expect((await send('alarm kur')).replyText, contains('saat'));
      expect(calls, isEmpty);
      await send('08:30');
      expect(calls, ['setAlarmOrTimer']);
      await send('alarm kur');
      expect((await send('iptal')).replyText, contains('iptal'));
      expect(calls.length, 1);
    },
  );
  testWidgets('Voice layout fits a phone and renders preview', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      if (!Platform.isWindows) return;
      final font = FontLoader('Roboto')
        ..addFont(
          File('C:/Windows/Fonts/segoeui.ttf')
              .readAsBytes()
              .then((v) => ByteData.sublistView(v)),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then((v) => ByteData.sublistView(v)),
        );
      await icons.load();
    });
    final c = AsistanController();
    await c.initialize(skipNativeAndNetwork: true);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: c.themePreset.toThemeData(),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(body: LiveVoiceScreen(controller: c)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = Platform.environment['ASISTAN_PREVIEW'];
      if (path != null) { await File(path).writeAsBytes(bytes!.buffer.asUint8List()); }
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
