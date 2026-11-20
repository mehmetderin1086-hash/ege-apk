import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/widgets/wake_diagnostic_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jarvis.assistant/device');
  testWidgets(
    'explicit wake diagnostic shows local result and clears it on close',
    (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'wakeWordInfo') {
              return {
                'silenced': false,
                'diagnosticPeak': 0.012,
                'diagnosticHits': 1,
                'diagnosticTexts': ['Hey Ege'],
              };
            }
            return true;
          });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: WakeDiagnosticDialog())),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Hey Ege'), findsOneWidget);
      expect(find.text('Algılama: 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(calls, contains('wakeDiagnosticStart'));
      expect(calls.last, 'wakeDiagnosticEnd');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
