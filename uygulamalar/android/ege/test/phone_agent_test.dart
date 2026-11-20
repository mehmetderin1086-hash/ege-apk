import 'chat_links_test.dart' show RecordingLauncher;
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jarvis.assistant/device');
  late JarvisController c;
  late List<MethodCall> calls;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    c = JarvisController();
    calls = [];
  });
  tearDown(() {
    c.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  void mock(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  test(
    'YouTube spoken variants open external app, not in-app player',
    () async {
      mock((call) async => call.method == 'openYouTube' ? 'app' : null);
      for (final phrase in [
        'YouTube aç',
        "YouTube'u aç",
        'YouTube uygulamasını başlat',
        'yutubu aç',
        'YouTube başlat',
      ]) {
        final result = await c.runLocalCommand(phrase);
        expect(result?.handled, true, reason: phrase);
        expect(result?.reply, contains('YouTube uygulaması'), reason: phrase);
      }
      expect(calls.where((x) => x.method == 'openYouTube'), hasLength(5));
      expect(c.pendingRoute, isNull);
    },
  );
  test(
    'YouTube search preserves query and reports actual launch failure',
    () async {
      mock((call) async => call.method == 'openYouTube' ? 'unavailable' : null);
      final result = await c.runLocalCommand("YouTube'da Tarkan ara");
      expect(result?.reply, contains('açılamadı'));
      expect(calls.last.arguments['query'], 'Tarkan');
      expect(c.pendingRoute, isNull);
    },
  );
  test('spoken artist request opens YouTube when the video lookup is offline', () async {
    mock((call) async => call.method == 'openYouTube' ? 'app' : null);
    final result = await HttpOverrides.runZoned(
      () => c.runLocalCommand("YouTube'dan Dua Lipa'dan bir şarkı aç"),
      createHttpClient: (_) => throw const SocketException('offline'),
    );
    expect(result?.handled, isTrue);
    expect(calls.singleWhere((call) => call.method == 'openYouTube').arguments['query'], 'Dua Lipa');
  });
  test('negated YouTube launch does not perform an action', () async {
    mock((_) async => null);
    await c.runLocalCommand('YouTube açma');
    expect(calls.where((x) => x.method == 'openYouTube'), isEmpty);
  });

  testWidgets('phone STT returns text without WAV capture', (tester) async {
    mock(
      (call) async => call.method == 'startPhoneSpeech'
          ? {'status': 'OK', 'text': 'Merhaba dünya'}
          : null,
    );
    var text = '';
    expect(await c.toggleDictation(onTranscript: (v) => text = v), isNull);
    expect(text, 'Merhaba dünya');
    expect(c.isDictating, false);
    expect(calls.where((x) => x.method == 'startMicCapture'), isEmpty);
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('unavailable phone STT starts Whisper recording', (tester) async {
    mock(
      (call) async => call.method == 'startPhoneSpeech'
          ? {'status': 'UNAVAILABLE'}
          : call.method == 'startMicCapture'
          ? 'OK'
          : null,
    );
    await c.toggleDictation(onTranscript: (_) {});
    expect(c.isDictating, true);
    expect(calls.where((x) => x.method == 'startMicCapture'), hasLength(1));
    await c.toggleDictation(onTranscript: (_) {});
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('permission denial never bypasses permission with fallback', (
    tester,
  ) async {
    mock(
      (call) async => call.method == 'startPhoneSpeech'
          ? {'status': 'PERMISSION_NEEDED'}
          : null,
    );
    expect(
      await c.toggleDictation(
        onTranscript: (_) => fail('No transcript expected'),
      ),
      contains('izni'),
    );
    expect(calls.where((x) => x.method == 'startMicCapture'), isEmpty);
    expect(c.isDictating, false);
    await tester.pump(const Duration(seconds: 1));
  });
  test(
    'settings migrate old live and preserve explicit v9 Whisper preference',
    () {
      expect(
        JarvisSettings.fromJson({'liveEngine': 'openai_live'}).liveEngine,
        'turn_based',
      );
      expect(
        JarvisSettings.fromJson({'settingsVersion': 8, 'sttMode': 'whisper'})
            .sttMode,
        'system',
      );
      final explicit = const JarvisSettings(sttMode: 'whisper');
      expect(JarvisSettings.fromJson(explicit.toJson()).sttMode, 'whisper');
    },
  );
  test('app tool refuses ambiguous apps and forwards exact target', () async {
    mock((call) async {
      if (call.method == 'listInstalledApps') {
        return [
          {'name': 'Chrome', 'package': 'com.android.chrome'},
        ];
      }
      if (call.method == 'controlApp') return 'İşlem uygulandı.';
      return null;
    });
    expect(
      await c.runAgentTool({
        'type': 'phone_action',
        'app': 'unknown',
        'action': 'click',
        'target': 'Ara',
      }),
      startsWith('Hata'),
    );
    expect(calls.where((x) => x.method == 'controlApp'), isEmpty);
    expect(
      await c.runAgentTool({
        'type': 'phone_action',
        'app': 'com.android.chrome',
        'action': 'click',
        'target': 'Ara',
      }),
      'İşlem uygulandı.',
    );
    expect(calls.last.arguments['target'], 'Ara');
  });
  test('Spotify music requests use verified playback and preserve failure feedback', () async {
    var status = 'Spotify çalıyor: Test';
    mock((call) async => call.method == 'playSpotifyMusic' ? status : null);
    for (final phrase in ["Spotify'dan şarkı aç", 'Asistan, Spotify’dan bir şarkı çal!',
      'Spotify müzik oynat', 'Lütfen Spotifydan bana bir parça aç']) {
      expect((await c.runLocalCommand(phrase))?.reply, status, reason: phrase);
    }
    expect(calls.where((c) => c.method == 'playSpotifyMusic'), hasLength(4));
    status = 'Spotify açıldı ancak çalan bir parça doğrulanamadı.';
    expect((await c.runLocalCommand('Spotify’dan bir şarkı aç'))?.reply, status);
    await c.runLocalCommand('Spotify müzik çalma');
    expect(calls.where((c) => c.method == 'playSpotifyMusic'), hasLength(5));
  });

  test('installed apps are resolved by launcher label for open and in-app search', () async {
    mock((call) async {
      if (call.method == 'listInstalledApps') {
        return [{'name': 'Örnek', 'package': 'example.mobile'}];
      }
      if (call.method == 'launchApp') return 'Örnek';
      if (call.method == 'controlApp') return 'Doğrudan arama isteği iletildi. example.mobile';
      return null;
    });
    expect((await c.runLocalCommand('Örnek uygulamasını aç'))?.reply, contains('açıldı'));
    expect((await c.runLocalCommand("Örnek’te Yaz Okulu ara"))?.reply, contains('Yaz Okulu'));
    final a = calls.singleWhere((x) => x.method == 'controlApp').arguments;
    expect(a['package'], 'example.mobile');
    expect(a['query'], 'Yaz Okulu');
  });

  test('presses the named control only inside the requested app', () async {
    mock((call) async {
      if (call.method == 'listInstalledApps') return [{'name':'Örnek','package':'example.mobile'}];
      if (call.method == 'controlApp' && call.arguments['action'] == 'open') {
        return '{"package":"example.mobile"}';
      }
      return 'Kontrol eylemi uygulandı';
    });
    expect((await c.runLocalCommand('Örnek içinde Geri düğmesine bas'))?.reply, contains('basıldı'));
    expect(calls.last.arguments['target'], 'Geri');
    expect(calls.last.arguments['package'], 'example.mobile');
    expect(calls.last.arguments['action'], 'click');
  });

  test('ten repeated launches share the installed-app lookup', () async {
    mock((call) async => call.method == 'listInstalledApps'
        ? [{'name':'Örnek', 'package':'example.mobile'}] : 'Örnek');
    for (var i = 0; i < 10; i++) {
      expect((await c.runLocalCommand('Örnek uygulamasını aç'))?.handled, isTrue);
    }
    expect(calls.where((call) => call.method == 'launchApp'), hasLength(10));
    expect(calls.where((call) => call.method == 'listInstalledApps'), hasLength(1));
  });

  test('local scrolling, back and field entry stay in the requested app', () async {
    mock((call) async {
      if (call.method == 'listInstalledApps') return [{'name':'Örnek','package':'example.mobile'}];
      if (call.arguments['action'] == 'open') return '{"package":"example.mobile"}';
      return 'Kontrol eylemi uygulandı';
    });
    for (final entry in {'aşağı kaydır':'scroll','yukarı kaydır':'scroll_back','geri dön':'back',
      'Başlık alanına Yaz Tatili yaz':'text'}.entries) {
      expect((await c.runLocalCommand('Örnek içinde ${entry.key}'))?.handled, true);
      expect(calls.last.arguments['action'], entry.value);
      expect(calls.last.arguments['package'], 'example.mobile');
    }
    expect(calls.last.arguments['text'], 'Yaz Tatili');
    expect(calls.last.arguments['target'], 'Başlık');
  });

  test('play falls back to an actual search when the video lookup is offline', () async {
    mock((call) async => call.method == 'openYouTube' ? 'app' : null);
    final result = await HttpOverrides.runZoned(
      () => c.tryExtendedCommand("YouTube'da örnek parça oynat"),
      createHttpClient: (_) => throw const SocketException('offline'),
    );
    expect(result?.reply, contains('aramasıyla'));
    expect(calls.singleWhere((call) => call.method == 'openYouTube').arguments['query'], 'örnek parça');
  });

  test('spoken new conversation keeps the previous conversation', () async {
    final old = c.activeSession.id;
    final result = await c.tryExtendedCommand('Yeni sohbet başlat');
    expect(result?.handled, isTrue);
    expect(c.activeSession.id, isNot(old));
    expect(c.sessions.any((session) => session.id == old), isTrue);
  });

  test('ranked voice projects are available offline and open the chosen source', () async {
    mock((call) async => true);
    final previous = UrlLauncherPlatform.instance;
    final launcher = RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    final list = await c.tryExtendedCommand('İlk beş Jarvis projesini göster');
    expect(list?.reply, contains('5. Jarvis for Windows'));
    await c.tryExtendedCommand('ikinci Jarvis projesinin kodunu aç');
    expect(launcher.urls.single, 'https://github.com/CodeWithHarry/JarvisAI-YouTube');
  });

  test('Spotify commands pass the verified player result through', () async {
    mock((call) async => 'Doğrulanmış yanıt');
    for (final entry in {"Spotify’da ne çalıyor?":'status', 'Spotify müziği duraklat':'pause'}.entries) {
      expect((await c.runLocalCommand(entry.key))?.reply, 'Doğrulanmış yanıt');
      expect(calls.last.method, 'spotifyControl');
      expect(calls.last.arguments['action'], entry.value);
    }
  });

  test('explicit Spotify requests bypass generic YouTube playback', () async {
    mock(
      (call) async => call.method == 'listInstalledApps'
          ? [
              {'name': 'Spotify', 'package': 'com.spotify.music'},
            ]
          : null,
    );
    for (final text in [
      "Spotify'da Hayat Okumaları 191 oynat",
      "Spotify'dan Hayat Okumaları 191 aç",
      'Spotify içinde Hayat Okumaları 191 çal',
    ]) {
      expect(await c.runLocalCommand(text), isNull, reason: text);
    }
    expect(c.pendingRoute, isNull);
  });

  for (final endless in [false, true]) {
    test(endless ? 'phone loop stops truthfully at limit' : 'phone task continues through result and playback after six steps', () async {
      c.dispose();
      final client = _PhoneFlowClient(endless: endless);
      c = JarvisController(httpClient: client);
      c.settings = const JarvisSettings(
        provider: ApiProvider.cliProxyApi,
        baseUrl: 'http://localhost:8317',
        apiKey: 'test',
        model: 'gpt-4o-mini',
        preferStreaming: true,
        agentTools: true,
        autoTts: false,
        learningLoop: false,
      );
      mock((call) async {
        if (call.method == 'listInstalledApps') {
          return [
            {'name': 'Spotify', 'package': 'com.spotify.music'},
          ];
        }
        if (call.method == 'controlApp') {
          return '{"package":"com.spotify.music","controls":[{"target":"@7:2","label":"Duraklat"}]}';
        }
        return null;
      });
      await c.sendMessage(
        'Spotify içinde Hayat Okumaları bölüm 191 içeriğini bul ve oynat',
      );
      final actions = calls.where((x) => x.method == 'controlApp').toList();
      expect(
        actions,
        hasLength(endless ? 16 : 8),
        reason: c.activeSession.messages.map((m) => m.content).join(" | "),
      );
      expect(actions.last.arguments['target'], '@7:2');
      expect(
        c.activeSession.messages.last.content,
        contains(
          endless ? 'tamamlandığını doğrulayamadım' : 'Oynatma doğrulandı',
        ),
      );
      client.close();
    });
  }

  test('file tool rejects path traversal before native write', () async {
    mock((_) async => null);
    expect(
      await c.runAgentTool({
        'type': 'create_text_file',
        'name': '../secret.txt',
        'content': 'x',
      }),
      startsWith('Hata'),
    );
    expect(calls.where((x) => x.method == 'saveBytesToDownloads'), isEmpty);
  });

  test(
    'exact package actions avoid a full app enumeration and preserve form text',
    () async {
      mock((call) async => call.method == 'controlApp' ? 'observed' : null);
      final result = await c.runAgentTool({
        'type': 'phone_action',
        'app': 'com.android.chrome',
        'action': 'text',
        'target': '@4:8',
        'text': 'İstanbul & İzmir + 191',
      });
      expect(result, 'observed');
      expect(calls.where((c) => c.method == 'listInstalledApps'), isEmpty);
      expect(calls.single.arguments['text'], 'İstanbul & İzmir + 191');
      expect(calls.single.arguments['target'], '@4:8');
    },
  );

  test('search and web launch keep the exact app and full query', () async {
    mock((call) async => call.method == 'controlApp' ? 'loaded' : null);
    await c.runAgentTool({
      'type': 'phone_open_app',
      'app': 'com.spotify.music',
      'query': 'Hayat Okumaları 191',
    });
    expect(calls.single.arguments['query'], 'Hayat Okumaları 191');
    expect(calls.single.arguments['package'], 'com.spotify.music');
    await c.runAgentTool({
      'type': 'phone_open_app',
      'app': 'com.android.chrome',
      'url': 'https://example.com/form?a=1&b=2',
    });
    expect(calls.last.arguments['url'], 'https://example.com/form?a=1&b=2');
  });

  test(
    'invalid web schemes and conflicting launch parameters do not act',
    () async {
      mock((_) async => null);
      for (final url in [
        'javascript:alert(1)',
        'file:///private',
        'https://user:pass@example.com',
        'https:///',
      ]) {
        expect(
          await c.runAgentTool({
            'type': 'phone_open_app',
            'app': 'com.android.chrome',
            'url': url,
          }),
          startsWith('Hata'),
        );
      }
      expect(
        await c.runAgentTool({
          'type': 'phone_open_app',
          'app': 'com.android.chrome',
          'query': 'a',
          'url': 'https://example.com',
        }),
        startsWith('Hata'),
      );
      expect(
        await c.runAgentTool({
          'type': 'phone_action',
          'app': 'com.android.chrome',
          'action': 'click',
          'target': '@1:0',
          'query': 'a',
        }),
        startsWith('Hata'),
      );
      expect(calls.where((c) => c.method == 'controlApp'), isEmpty);
    },
  );

  test(
    'form submit needs an observed target and scroll back is forwarded',
    () async {
      mock((_) async => 'observed');
      expect(
        await c.runAgentTool({
          'type': 'phone_action',
          'app': 'com.android.chrome',
          'action': 'submit',
        }),
        startsWith('Hata'),
      );
      expect(calls, isEmpty);
      await c.runAgentTool({
        'type': 'phone_action',
        'app': 'com.android.chrome',
        'action': 'submit',
        'target': '@2:1',
      });
      expect(calls.last.arguments['action'], 'submit');
      await c.runAgentTool({
        'type': 'phone_action',
        'app': 'com.android.chrome',
        'action': 'scroll_back',
        'target': '@3:2',
      });
      expect(calls.last.arguments['action'], 'scroll_back');
    },
  );

  test(
    'send/read/app calling requests reach the agent instead of draft shortcuts',
    () async {
      c.settings = c.settings.copyWith(agentTools: true);
      mock((_) async => null);
      for (final phrase in [
        "WhatsApp'tan Ahmet'e selam gönder",
        "Telegram'dan Ayşe'yi ara",
        "Ahmet'e SMS gönder: Merhaba",
        'WhatsApp mesajlarımı oku',
        'Telegramda Ali ara',
      ]) {
        expect(await c.runLocalCommand(phrase), isNull, reason: phrase);
      }
      expect(calls, isEmpty);
    },
  );

  test(
    'hangup recognizes voice variants, reports actual status, ignores negation',
    () async {
      var status = 'ENDED';
      mock((call) async => call.method == 'endCall' ? status : null);
      for (final phrase in [
        'Aramayı kapat',
        'Görüşmeyi sonlandır',
        'Hey Jarvis, lütfen telefonu kapat.',
        'Hey Ege, lütfen telefonu kapat.',
      ]) {
        expect(
          (await c.runLocalCommand(phrase))?.reply,
          contains('kapandığı doğrulandı'),
        );
      }
      status = 'UNVERIFIED';
      expect(
        (await c.runLocalCommand('Aramayı kapat'))?.reply,
        contains('doğrulanamadı'),
      );
      status = 'PERMISSION_NEEDED';
      expect(
        (await c.runLocalCommand('Aramayı kapat'))?.reply,
        contains('izni gerekiyor'),
      );
      final count = calls.where((c) => c.method == 'endCall').length;
      await c.runLocalCommand('Aramayı kapatma');
      expect(calls.where((c) => c.method == 'endCall'), hasLength(count));
    },
  );

  test('ambiguous contacts cannot accidentally start a call', () async {
    mock(
      (call) async => call.method == 'searchContacts'
          ? [
              {'name': 'Ahmet İş', 'phone': '05001111111'},
              {'name': 'Ahmet Ev', 'phone': '05002222222'},
            ]
          : null,
    );
    expect(
      await c.executeAnyAction({'type': 'call_contact', 'name': 'Ahmet'}),
      contains('Birden fazla'),
    );
    expect(
      calls.where((c) => c.method == 'callNumber' || c.method == 'dialNumber'),
      isEmpty,
    );
  });

  test('failed outgoing call is not reported as dialer success', () async {
    mock((call) async => call.method == 'callNumber' ? 'ERROR' : null);
    expect(
      await c.executeAnyAction({'type': 'call_contact', 'name': '05001234567'}),
      contains('başlatılamadı'),
    );
  });

  test(
    'message reading distinguishes missing permission from empty inbox',
    () async {
      mock((call) async => call.method == 'notificationAccess' ? false : null);
      expect(
        await c.runAgentTool({'type': 'message_notifications'}),
        startsWith('Hata'),
      );
      expect(calls.where((c) => c.method == 'recentNotifications'), isEmpty);
    },
  );

  test(
    'Ege migration keeps settings and updates the saved assistant identity',
    () {
      final settings = JarvisSettings.fromJson({
        'settingsVersion': 9,
        'personaPrompt': 'Sen JARVIS, kısa ve Türkçe cevap ver.',
        'sttMode': 'whisper',
        'wakeWordEnabled': true,
      });
      expect(settings.personaPrompt, 'Sen Ege, kısa ve Türkçe cevap ver.');
      expect(settings.sttMode, 'whisper');
      expect(settings.wakeWordEnabled, true);
      expect(settings.toJson()['settingsVersion'], 10);
    },
  );
}

class _PhoneFlowClient extends http.BaseClient {
  _PhoneFlowClient({required this.endless});
  final bool endless;
  int step = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    final text = endless || step++ < 8
        ? '<MOBILE_ACTION>{"type":"phone_action","app":"com.spotify.music","action":"click","target":"@7:2"}</MOBILE_ACTION>'
        : 'Oynatma doğrulandı.';
    final event = jsonEncode({
      'choices': [
        {
          'delta': {'content': text},
        },
      ],
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode('data: $event\n\ndata: [DONE]\n\n')),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}
