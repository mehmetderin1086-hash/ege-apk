import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/screens/speaker_profile_screen.dart';
import 'package:jarvis_mobile/services/speaker_identity.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jarvis.assistant/device');
  late JarvisController controller;
  final calls = <String>[];
  setUp(() async {
    calls.clear();
    final vector = List<double>.filled(256, 0.1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'speakerProfileRead') {
            return jsonEncode({
              'enabled': true,
              'model': SpeakerIdentity.modelName,
              'references': [vector, vector, vector],
            });
          }
          return true;
        });
    await SpeakerIdentity.instance.enroll([vector, vector, vector]);
    controller = JarvisController();
  });
  tearDown(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  testWidgets('a single misplaced tap cannot delete the voice profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SpeakerProfileScreen(controller: controller)),
    );
    await tester.pump();
    final delete = find.text('Ses profilimi sil');
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('Ses profilin silinsin mi?'), findsOneWidget);
    expect(calls, isNot(contains('speakerProfileDelete')));
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(SpeakerIdentity.instance.enrolled, true);
    expect(calls, isNot(contains('speakerProfileDelete')));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'enrollment blocks delayed wake resume and restores the previous choice',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SpeakerProfileScreen(controller: controller)),
      );
      await tester.pump();
      expect(controller.wakeWordStoppedByUser, true);
      expect(calls, containsAll(['wakeWordPause', 'wakeWordStop']));
      // The same delayed callback scheduled when live mode stops.
      final pendingResume = Future<void>.delayed(
        const Duration(milliseconds: 800),
        controller.resumeWakeWord,
      );
      await tester.pump(const Duration(seconds: 1));
      await pendingResume;
      expect(controller.wakeWordStoppedByUser, true);
      expect(calls, isNot(contains('wakeWordStart')));
      await tester.pumpWidget(const SizedBox());
      expect(controller.wakeWordStoppedByUser, false);
    },
  );
  testWidgets(
    'an existing profile leads to short wake samples, with explicit general renewal',
    (tester) async {
      controller.wakeWordStoppedByUser = true;
      await tester.pumpWidget(
        MaterialApp(home: SpeakerProfileScreen(controller: controller)),
      );
      await tester.pump();
      expect(find.text('1. örneği kaydet'), findsNothing);
      expect(find.text('Asistan · 1. örneği kaydet'), findsOneWidget);
      final renew = find.text('Genel ses profilimi yeniden kaydet');
      await tester.ensureVisible(renew);
      await tester.tap(renew);
      await tester.pump();
      expect(find.text('1. örneği kaydet'), findsOneWidget);
      expect(find.text('Asistan · 1. örneği kaydet'), findsNothing);
      expect(SpeakerIdentity.instance.enrolled, true);
      await tester.pumpWidget(const SizedBox());
      expect(controller.wakeWordStoppedByUser, true);
      expect(calls, isNot(contains('wakeWordStart')));
    },
  );
}
