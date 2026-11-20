import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/storage_service.dart';
import 'package:jarvis_mobile/services/evidence_memory.dart';
import 'package:jarvis_mobile/services/obsidian_memory.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:jarvis_mobile/screens/live_voice_screen.dart';
import 'package:jarvis_mobile/widgets/speaking_edge_lights.dart';
import 'package:jarvis_mobile/widgets/chat_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jarvis.assistant/device');
  late JarvisController c;
  late List<MethodCall> calls;
  void mock(Future<Object?> Function(MethodCall) fn) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return fn(call);
          });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    c = JarvisController();
    calls = [];
  });
  tearDown(() {
    c.dispose();
    mock((_) async => null);
    ChatPalette.configure('light', 0xFFB85C3D, false);
  });
  test('media downloads never enter the app-store shortcut', () async {
    mock((call) async => call.method == 'listInstalledApps' ? [] : true);
    for (final text in [
      'Resim indir',
      'Megaboz resimlerini indir',
      'Bu fotoğrafı indir',
      'Ekrandaki PDF dosyasını indir',
      'Hey Ege görsel indir',
      'Belge yükle',
    ]) {
      expect(await c.runLocalCommand(text), isNull, reason: text);
    }
    expect(calls.where((x) => x.method == 'openPlayStore'), isEmpty);
    await c.runLocalCommand('Spotify uygulamasını indir');
    expect(calls.where((x) => x.method == 'openPlayStore'), hasLength(1));
  });
  test('user turn is saved before an external application is opened', () async {
    mock((call) async {
      if (call.method == 'openPlayStore') {
        final loaded = await StorageService().loadSessions();
        expect(
          loaded.sessions
              .expand((s) => s.messages)
              .any((m) => m.content == 'Spotify uygulamasını indir'),
          true,
        );
        return true;
      }
      return null;
    });
    await c.sendMessage('Spotify uygulamasını indir');
  });
  test(
    'all messages and all sessions survive reload and queued saves',
    () async {
      final store = StorageService();
      final sessions = List.generate(
        65,
        (s) => ChatSession(
          id: 's$s',
          title: 'Sohbet $s',
          updatedAt: DateTime(2026),
          messages: List.generate(
            s == 0 ? 325 : 1,
            (m) => JarvisMessage(
              id: 's$s-m$m',
              role: 'user',
              content: 'Mesaj $m',
              timestamp: DateTime(2026),
            ),
          ),
        ),
      );
      final old = store.saveSessions(sessions.take(1).toList(), 's0');
      final newer = store.saveSessions(sessions, 's64');
      await Future.wait([old, newer]);
      final loaded = await store.loadSessions();
      expect(loaded.sessions.length, 65);
      expect(loaded.sessions.first.messages.length, 325);
      expect(loaded.sessions.first.messages.first.content, 'Mesaj 0');
      expect(loaded.activeId, 's64');
      final files = ObsidianMemory.files(
        loaded.sessions,
        const JarvisSettings(),
        [],
        [],
      );
      expect(
        files.values.any(
          (s) => s.contains('Mesaj 0') && s.contains('Mesaj 324'),
        ),
        true,
      );
    },
  );
  test('HTML cannot be queued as an image even when named jpg', () async {
    c.dispose();
    c = JarvisController(
      httpClient: MockClient(
        (_) async => http.Response(
          '<html>page</html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
      ),
    );
    mock((_) async => 123);
    final result = await c.runAgentTool({
      'type': 'download_file',
      'url': 'https://example.com/photo',
      'fileName': 'fake.jpg',
      'expectedKind': 'image',
    });
    expect(result, startsWith('Hata'));
    expect(calls.where((x) => x.method.contains('Download')), isEmpty);
  });
  test('page media retains image descriptions and resolved URLs', () async {
    c.dispose();
    c = JarvisController(
      httpClient: MockClient(
        (_) async => http.Response(
          '<html><title>Fotoğraflar</title><img src="/megaboz.jpg" alt="Megaboz sahnede"></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      ),
    );
    final result = await c.runAgentTool({
      'type': 'page_media',
      'url': 'https://example.com/gallery',
    });
    expect(result, contains('https://example.com/megaboz.jpg'));
    expect(result, contains('Megaboz sahnede'));
  });
  test(
    'long press needs a fresh explicit target and preserves package',
    () async {
      mock((_) async => 'new menu');
      expect(
        await c.runAgentTool({
          'type': 'phone_action',
          'app': 'com.android.chrome',
          'action': 'long_click',
        }),
        startsWith('Hata'),
      );
      expect(calls, isEmpty);
      expect(
        await c.runAgentTool({
          'type': 'phone_action',
          'app': 'com.android.chrome',
          'action': 'long_click',
          'target': '@9:3',
        }),
        'new menu',
      );
      expect(calls.single.arguments['target'], '@9:3');
    },
  );
  test('screen failure cannot reuse an old screenshot', () async {
    c.dispose();
    c = JarvisController(
      httpClient: MockClient(
        (_) async => throw StateError('No network expected'),
      ),
    );
    c.lastAssistScreenshot = Uint8List.fromList([1, 2, 3]);
    c.lastAssistScreenshotAt = DateTime.now();
    mock(
      (call) async =>
          call.method == 'resumePhoneScreen' ? 'Hata: izin kapalı' : null,
    );
    expect(await c.screenAnswer('Ekranı oku'), 'Hata: izin kapalı');
    expect(calls.where((x) => x.method == 'phoneScreenImage'), isEmpty);
  });
  test(
    'screen reading uses current accessibility text when capture is blocked',
    () async {
      c.dispose();
      c = JarvisController(
        httpClient: MockClient((req) async {
          expect(req.body, contains('Güncel başlık'));
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Güncel başlık okunuyor.'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      mock(
        (call) async => call.method == 'resumePhoneScreen'
            ? 'Ekran: {"package":"com.android.chrome","controls":[{"label":"Güncel başlık"}]}'
            : {'error': 'Görüntü engelli'},
      );
      expect(await c.screenAnswer('Ekranı oku'), contains('Güncel başlık'));
      expect(
        calls
            .map((c) => c.method)
            .where((m) => m == 'resumePhoneScreen' || m == 'phoneScreenImage'),
        ['resumePhoneScreen', 'phoneScreenImage'],
      );
    },
  );
  test(
    'inferences need two user sources and fabricated quotes are rejected',
    () {
      final store = EvidenceMemory();
      final s = ChatSession(
        id: 's',
        title: 'test',
        updatedAt: DateTime(2026),
        messages: [
          JarvisMessage(
            id: 'a',
            role: 'user',
            content: 'Mavi rengi seviyorum.',
            timestamp: DateTime(2026),
          ),
          JarvisMessage(
            id: 'b',
            role: 'user',
            content: 'Tema yine mavi olsun.',
            timestamp: DateTime(2026),
          ),
        ],
      );
      final first = {'messageId': 'a', 'quote': 'Mavi rengi seviyorum.'};
      expect(
        store.add(
          {
            'text': 'Mavi tercih edebilir',
            'kind': 'inference',
            'sources': [first],
          },
          [s],
        ),
        startsWith('Hata'),
      );
      expect(
        store.add(
          {
            'text': 'Kırmızı sever',
            'kind': 'fact',
            'sources': [
              {'messageId': 'a', 'quote': 'Kırmızı seviyorum'},
            ],
          },
          [s],
        ),
        startsWith('Hata'),
      );
      expect(
        store.add(
          {
            'text': 'Mavi tercih edebilir',
            'kind': 'inference',
            'sources': [
              first,
              {'messageId': 'b', 'quote': 'Tema yine mavi olsun.'},
            ],
          },
          [s],
        ),
        contains('tahmin'),
      );
      expect(store.entries.single['kind'], 'inference');
    },
  );
  test('forgotten memories cannot be reintroduced by extraction', () async {
    final store = EvidenceMemory();
    await store.forget('Megaboz');
    expect(store.excluded('Megaboz resimlerini indir'), true);
    final reloaded = EvidenceMemory();
    await reloaded.load();
    expect(reloaded.excluded('megaboz'), true);
  });
  test('appearance preferences persist and the default orb is smaller', () {
    final s = const JarvisSettings().copyWith(
      themeMode: 'dark',
      themeAccent: 0xFF1976D2,
      liveOrbSize: 110,
    );
    final loaded = JarvisSettings.fromJson(s.toJson());
    expect(loaded.themeMode, 'dark');
    expect(loaded.themeAccent, 0xFF1976D2);
    expect(loaded.liveOrbSize, 110);
    expect(const JarvisSettings().liveOrbSize, lessThan(196));
  });
  testWidgets(
    'live orb measures selected size and updates without remounting',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LiveVoiceScreen(controller: c)),
        ),
      );
      final orb = find.byKey(const Key('live_voice_orb'));
      expect(tester.getSize(orb), const Size(132, 132));
      c.settings = c.settings.copyWith(liveOrbSize: 104);
      c.notifyListeners();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(orb), const Size(104, 104));
    },
  );
  testWidgets('blue edges exist only during assistant speech', (tester) async {
    c.liveLoopActive = true;
    c.livePhase = LiveVoicePhase.speaking;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LiveVoiceScreen(controller: c)),
      ),
    );
    expect(find.byType(SpeakingEdgeLights), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('speaking_edge_canvas'))),
      tester.getSize(find.byType(LiveVoiceScreen)),
    );
    final firstPainter = tester
        .widget<CustomPaint>(find.byKey(const Key('speaking_edge_canvas')))
        .painter;
    await tester.pump(const Duration(milliseconds: 150));
    final nextPainter = tester
        .widget<CustomPaint>(find.byKey(const Key('speaking_edge_canvas')))
        .painter!;
    expect(nextPainter.shouldRepaint(firstPainter!), true);
    c.livePhase = LiveVoicePhase.listening;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LiveVoiceScreen(controller: c)),
      ),
    );
    expect(find.byType(SpeakingEdgeLights), findsNothing);
  });
}
