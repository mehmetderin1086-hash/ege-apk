import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/widgets/markdown_message.dart';
// Exercise url_launcher's platform boundary without launching a host browser.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class RecordingLauncher extends UrlLauncherPlatform {
  final urls = <String>[];
  final modes = <PreferredLaunchMode>[];
  @override
  Null get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    modes.add(options.mode);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'chat links retain destinations and exclude sentence punctuation',
    (tester) async {
      final previous = UrlLauncherPlatform.instance;
      final launcher = RecordingLauncher();
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownMessage(
              text: '[Belge](https://example.com/file.pdf) www.example.com. mailto:test@example.com',
            ),
          ),
        ),
      );
      await tester.tap(find.text('Belge'));
      await tester.pump();
      await tester.tap(find.text('www.example.com'));
      await tester.pump();
      await tester.tap(find.text('mailto:test@example.com'));
      await tester.pump();
      expect(
        launcher.modes,
        everyElement(PreferredLaunchMode.externalApplication),
      );
      expect(launcher.urls, [
        'https://example.com/file.pdf',
        'https://www.example.com',
        'mailto:test@example.com',
      ]);
    },
  );

  testWidgets('code and executable schemes do not become chat action links', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownMessage(
            text: '`https://example.com` [x](javascript:alert) intent://example file:///private',
          ),
        ),
      ),
    );
    expect(find.byType(InkWell), findsNothing);
  });
}
