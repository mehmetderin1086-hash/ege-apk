import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asistan_flutter/services/asistan_controller.dart';
import 'package:asistan_flutter/models/asistan_models.dart';
import 'package:asistan_flutter/main.dart';

void main() {
  testWidgets('Chat layout keeps messages visible with keyboard', (tester) async {
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
    final thread = c.activeThread;
    c.threads = [thread.copyWith(messages: [
      ChatMessage(id: 'example-user', role: 'user', text: 'Bugünkü işlerimi düzenlememe yardım et.', timestamp: DateTime(2026, 11, 15, 10, 0)),
      ChatMessage(id: 'example-assistant', role: 'assistant', text: 'Elbette. Yapılacaklarını yaz; birlikte önceliklendirelim.\n\nSaat belirterek alarm kurabilir, dosya bağlantılarını indirme kuyruğuna ekleyebilirsin.', modelUsed: 'Asistan', timestamp: DateTime(2026, 11, 15, 10, 0)),
    ])];
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: AsistanApp(controller: c)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = Platform.environment['ASISTAN_CHAT_PREVIEW'];
      if (path != null) { await File(path).writeAsBytes(bytes!.buffer.asUint8List()); }
      image.dispose();
    });
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
