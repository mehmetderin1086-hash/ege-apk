import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jarvis_mobile/main.dart';
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/models/pc_models.dart';
import 'package:jarvis_mobile/services/ai_client.dart';
import 'package:jarvis_mobile/services/code_tools.dart';
import 'package:jarvis_mobile/screens/pc_hub_screen.dart';
import 'package:jarvis_mobile/screens/voice_studio_screen.dart';
import 'package:jarvis_mobile/services/pc_bridge_client.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Router extends http.BaseClient {
  final FutureOr<http.StreamedResponse> Function(http.Request r) handler;
  final List<http.Request> seen = [];

  _Router(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = request as http.Request;
    seen.add(r);
    return handler(r);
  }
}

http.StreamedResponse _json(Object body, [int status = 200]) => http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: const {'content-type': 'application/json'},
    );

const _bundle = {
  'version': 1,
  'proxy': {
    'baseUrl': 'http://10.0.0.59:8317',
    'apiKey': 'proxy-key-123',
    'reachable': true,
    'modelCount': 3,
  },
  'azure': {'key': 'az-key', 'region': 'westeurope'},
  'gemini': {'key': 'AIza-gem'},
  'googleCloud': {'key': 'AIza-gc'},
  'openai': {'key': 'sk-oai'},
  'sources': ['Windows kullanıcı ortamı', '.env'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PcBridgeClient', () {
    test('normalizeUrl adds scheme and default port', () {
      expect(PcBridgeClient.normalizeUrl('10.0.0.5'), 'http://10.0.0.5:8765');
      expect(PcBridgeClient.normalizeUrl('http://10.0.0.5:9000/'), 'http://10.0.0.5:9000');
      expect(PcBridgeClient.normalizeUrl(' pc.local '), 'http://pc.local:8765');
      expect(PcBridgeClient.normalizeUrl(''), '');
    });

    test('pair, list, read, write and errors map correctly', () async {
      final client = _Router((r) {
        final p = r.url.path;
        if (p == '/pair') {
          final body = jsonDecode(r.body) as Map;
          if (body['pin'] != '123456') return _json({'ok': false, 'error': 'PIN hatalı.'}, 403);
          return _json({'ok': true, 'token': 'jpb_abc', 'host': 'MEHMET-PC'});
        }
        expect(r.headers['Authorization'], 'Bearer jpb_abc');
        if (p == '/api/list') {
          return _json({
            'path': r.url.queryParameters['path'],
            'parent': null,
            'root': {'name': 'Proje', 'path': 'C:\\p'},
            'entries': [
              {'name': 'lib', 'path': 'C:\\p\\lib', 'dir': true, 'size': 0, 'mtime': 0},
              {'name': 'main.dart', 'path': 'C:\\p\\main.dart', 'dir': false, 'size': 42, 'mtime': 0},
            ],
          });
        }
        if (p == '/api/read') {
          return _json({
            'path': 'C:\\p\\main.dart',
            'name': 'main.dart',
            'size': 13,
            'binary': false,
            'content': 'void main(){}\r\n',
            'encoding': 'utf-8',
            'sha256': 'abc',
            'eol': 'crlf',
          });
        }
        if (p == '/api/write') {
          final body = jsonDecode(r.body) as Map;
          if (body['baseSha'] == 'old') return _json({'ok': false, 'error': 'değişmiş'}, 409);
          return _json({'ok': true, 'sha256': 'new', 'size': 20});
        }
        return _json({'error': 'yok'}, 404);
      });

      await expectLater(
        PcBridgeClient.pair('10.0.0.5', '000000', client: client),
        throwsA(isA<PcBridgeException>().having((e) => e.status, 'status', 403)),
      );
      final paired = await PcBridgeClient.pair('10.0.0.5', '123456', client: client);
      expect(paired.token, 'jpb_abc');
      expect(paired.host, 'MEHMET-PC');

      final api = PcBridgeClient(baseUrl: '10.0.0.5', token: paired.token, client: client);
      final listing = await api.list('C:\\p');
      expect(listing.entries.first.isDir, isTrue);
      expect(listing.entries.last.ext, '.dart');
      final file = await api.read('C:\\p\\main.dart');
      expect(file.eol, 'crlf');
      expect(file.editable, isTrue);
      final w = await api.write(path: file.path, content: 'x', baseSha: 'abc');
      expect(w.sha256, 'new');
      await expectLater(
        api.write(path: file.path, content: 'x', baseSha: 'old'),
        throwsA(isA<PcBridgeException>().having((e) => e.conflict, 'conflict', isTrue)),
      );
    });

    test('key bundle summary never contains secrets', () {
      final b = PcKeyBundle.fromJson(Map<String, dynamic>.from(_bundle));
      expect(b.proxyApiKey, 'proxy-key-123');
      final text = b.summary.join(' ');
      expect(text, contains('Azure'));
      expect(text, isNot(contains('proxy-key-123')));
      expect(text, isNot(contains('az-key')));
    });
  });

  group('JarvisController PC import', () {
    test('importKeysFromPc wires proxy, cloud voice keys and refreshes models', () async {
      SharedPreferences.setMockInitialValues({});
      final client = _Router((r) {
        if (r.url.path == '/api/keys') return _json(_bundle);
        if (r.url.path == '/v1/models') {
          expect(r.headers['Authorization'], 'Bearer proxy-key-123');
          return _json({
            'data': [
              {'id': 'gemini-2.5-flash', 'owned_by': 'google'},
              {'id': 'claude-sonnet-5-5', 'owned_by': 'anthropic'},
            ],
          });
        }
        return _json({'error': 'yok'}, 404);
      });
      final c = JarvisController(httpClient: client);
      await c.init(loadPlatformTelemetry: false);
      await c.updateSettings(c.settings.copyWith(
        pcBridgeUrl: 'http://10.0.0.59:8765',
        pcBridgeToken: 'jpb_x',
        pcBridgeName: 'PC',
      ));
      final res = await c.importKeysFromPc();
      expect(res.ok, isTrue, reason: res.message);
      final s = c.settings;
      expect(s.provider, ApiProvider.cliProxyApi);
      expect(s.baseUrl, 'http://10.0.0.59:8317');
      expect(s.apiKey, 'proxy-key-123');
      expect(s.ttsProxyUrl, 'http://10.0.0.59:8317');
      expect(s.ttsProxyKey, 'proxy-key-123');
      expect(s.azureSpeechKey, 'az-key');
      expect(s.geminiTtsKey, 'AIza-gem');
      expect(s.openAiTtsKey, 'sk-oai');
      expect(s.usesLoopbackProxy, isFalse);
      expect(c.proxyModels.map((m) => m.id), contains('claude-sonnet-5-5'));
      c.dispose();
    });
  });

  group('Settings & voice catalog', () {
    test('new settings fields round-trip JSON', () {
      const s = JarvisSettings(
        pcBridgeUrl: 'http://1.2.3.4:8765',
        pcBridgeToken: 't',
        pcBridgeName: 'PC',
        ttsStyle: 'calm',
        ttsProxyKey: 'k',
        autoFallbackGemini: false,
      );
      final back = JarvisSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.pcPaired, isTrue);
      expect(back.ttsStyle, 'calm');
      expect(back.ttsProxyKey, 'k');
      expect(back.autoFallbackGemini, isFalse);
      final legacy = JarvisSettings.fromJson({'ttsStyle': 'bilinmeyen'});
      expect(legacy.ttsStyle, 'jarvis');
      expect(legacy.pcPaired, isFalse);
    });

    test('catalog has every Chirp 3 HD voice and unique preset ids', () {
      expect(JarvisVoiceCatalog.chirpCatalog.length, 30);
      final ids = JarvisVoiceCatalog.presets.map((v) => v.id.toLowerCase()).toList();
      expect(ids.toSet().length, ids.length);
      for (final v in JarvisVoiceCatalog.chirpCatalog) {
        expect(JarvisVoiceCatalog.isChirpVoice(v.id), isTrue, reason: v.id);
      }
      expect(AiClient.isFemaleVoice('en-US-AvaMultilingualNeural'), isTrue);
      expect(AiClient.isFemaleVoice('Achird'), isFalse);
      expect(AiClient.ttsVoiceKind('nova'), 'openai');
      expect(AiClient.ttsVoiceKind('en-US-AndrewMultilingualNeural'), 'azure');
    });

    test('Azure SSML carries style for HD voices and <lang> for multilingual', () async {
      final bodies = <String>[];
      final client = _Router((r) {
        bodies.add(r.body);
        return http.StreamedResponse(
          Stream.value(List<int>.filled(4000, 0xFF)),
          200,
          headers: const {'content-type': 'audio/mpeg'},
        );
      });
      const base = JarvisSettings(azureSpeechKey: 'k', ttsEngine: 'azure', ttsStyle: 'calm');
      final r1 = await AiClient.synthesizeSpeechDetailed(
        settings: base.copyWith(proxyTtsVoice: 'elif'),
        text: 'Merhaba dünya',
        client: client,
        useCache: false,
      );
      expect(r1.ok, isTrue);
      expect(bodies.last, contains('style="reflective"'));
      await AiClient.synthesizeSpeechDetailed(
        settings: base.copyWith(proxyTtsVoice: 'en-US-AvaMultilingualNeural'),
        text: 'Merhaba dünya',
        client: client,
        useCache: false,
      );
      expect(bodies.last, contains('<lang xml:lang="tr-TR">'));
      expect(bodies.last, contains('en-US-AvaMultilingualNeural'));
    });
  });

  group('Gemini fallback', () {
    test('streamChat falls back to Gemini when the proxy is unreachable', () async {
      final client = _Router((r) {
        if (r.url.host == '10.0.0.59') {
          throw const SocketException('No route to host');
        }
        expect(r.url.host, 'generativelanguage.googleapis.com');
        expect(r.headers['x-goog-api-key'], 'AIza-gem');
        const sse = 'data: {"candidates":[{"content":{"parts":[{"text":"Merhaba Mehmet"}]}}]}\n\n';
        return http.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          200,
          headers: const {'content-type': 'text/event-stream'},
        );
      });
      const s = JarvisSettings(
        baseUrl: 'http://10.0.0.59:8317',
        apiKey: 'k',
        model: 'claude-sonnet-5-5',
        geminiTtsKey: 'AIza-gem',
      );
      expect(AiClient.geminiFallbackSettings(s)!.model, 'gemini-2.5-flash');
      final events = await AiClient.streamChat(
        settings: s,
        messages: [
          JarvisMessage(id: '1', role: 'user', content: 'selam', timestamp: DateTime(2026)),
        ],
        client: client,
      ).toList();
      final full = events.lastWhere((e) => e.fullText != null).fullText!;
      expect(full, contains('Merhaba Mehmet'));
      expect(full, contains('Gemini API'));
      expect(AiClient.geminiFallbackSettings(s.copyWith(autoFallbackGemini: false)), isNull);
    });
  });

  group('Code tools', () {
    test('LineDiff reconstructs both sides for random edits', () {
      final rnd = Random(7);
      for (var round = 0; round < 40; round++) {
        final a = List.generate(rnd.nextInt(60), (i) => 'satir ${rnd.nextInt(12)}');
        final b = List<String>.from(a);
        for (var k = 0; k < rnd.nextInt(8); k++) {
          final op = rnd.nextInt(3);
          if (op == 0 || b.isEmpty) {
            b.insert(b.isEmpty ? 0 : rnd.nextInt(b.length), 'yeni ${rnd.nextInt(99)}');
          } else if (op == 1) {
            b.removeAt(rnd.nextInt(b.length));
          } else {
            b[rnd.nextInt(b.length)] = 'degisti ${rnd.nextInt(99)}';
          }
        }
        final oldText = a.join('\n');
        final newText = b.join('\n');
        final diff = LineDiff.compute(oldText, newText);
        final rebuiltOld = diff.where((d) => d.kind != DiffKind.add).map((d) => d.text).join('\n');
        final rebuiltNew = diff.where((d) => d.kind != DiffKind.del).map((d) => d.text).join('\n');
        expect(rebuiltOld, oldText);
        expect(rebuiltNew, newText);
      }
    });

    test('highlighter never drops characters', () {
      const samples = {
        'dart': "import 'x.dart';\n/* blok\n yorum */ final a = 42; // not\nclass A { void f() => print(\"\$a\"); }",
        'python': 'def f(x):\n    """doc\n    string"""\n    return x * 2  # yorum',
        'json': '{"anahtar": [1, 2.5, true, null]}',
        'xml': '<manifest android:name="x"><!-- yorum --></manifest>',
        'powershell': '\$a = Get-Item "C:\\x" # yorum',
        'yaml': 'server:\n  port: 8317 # yorum',
      };
      samples.forEach((lang, code) {
        final lines = code.split('\n');
        final spans = CodeHighlighter.highlightLines(lines, lang);
        for (var i = 0; i < lines.length; i++) {
          expect(spans[i].toPlainText(), lines[i], reason: '$lang satır $i');
        }
      });
      expect(CodeLang.detect('C:\\a\\b\\main.dart'), 'dart');
      expect(CodeLang.detect('/x/build.gradle.kts'), 'kotlin');
    });

    test('CodeAiParser extracts the longest fenced block', () {
      const reply = 'Özet: düzeltildi.\n```dart\nvoid a() {}\n```\nVe:\n```dart\nvoid main() {\n  a();\n}\n```';
      expect(CodeAiParser.extractCode(reply), 'void main() {\n  a();\n}\n');
      expect(CodeAiParser.extractSummary(reply), 'Özet: düzeltildi.');
      expect(CodeAiParser.extractCode('```py\nprint(1)\n'), 'print(1)\n');
    });
  });

  testWidgets('connected PC hub and voice studio lay out on a phone screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final controller = JarvisController();
    await controller.init(loadPlatformTelemetry: false);
    await controller.updateSettings(controller.settings.copyWith(
      pcBridgeUrl: 'http://10.119.125.59:8765',
      pcBridgeToken: 'jpb_x',
      pcBridgeName: 'MEHMET-PC',
      azureSpeechKey: 'k',
    ));
    controller.pcOnline = true;
    controller.pcInfo = PcHostInfo.fromJson({
      'host': 'MEHMET-PC',
      'ram': {'totalGb': 16, 'usedPct': 63},
      'disk': {'totalGb': 512, 'freeGb': 120},
      'battery': {'pct': 80, 'charging': true},
      'uptimeMin': 300,
      'tools': {'flutter': true, 'git': true, 'claude': true, 'codex': false},
      'roots': [
        {'name': 'JARVIS Mobil (Flutter)', 'path': 'C:\\Users\\mehmet\\Desktop\\JARVIS\\jarvis_mobile'},
        {'name': 'CLI Proxy API', 'path': 'C:\\Users\\mehmet\\cli-proxy-api'},
      ],
    });
    await tester.pumpWidget(JarvisApp(controller: controller, loadPlatformTelemetry: false));
    await tester.pump();
    await tester.tap(find.byTooltip('Menü'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PC Kod')); 
    await tester.pump();
    expect(find.text('API\'leri PC\'den Al'), findsOneWidget);
    expect(find.text('Kodlama Ajanı'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('CLI Proxy API'), 300,
        scrollable: find.descendant(of: find.byType(PcHubScreen), matching: find.byType(Scrollable)).first);
    expect(find.text('JARVIS Mobil (Flutter)'), findsOneWidget);

    await tester.tap(find.byTooltip('Bulut Ses Stüdyosu'));
    await tester.pumpAndSettle();
    expect(find.text('Konuşma tonu'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Google Chirp 3 HD / Gemini TTS'), 300,
        scrollable: find.descendant(of: find.byType(VoiceStudioScreen), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('Google Chirp 3 HD / Gemini TTS'));
    await tester.pumpAndSettle();
    expect(find.text('Sulafat'), findsWidgets);
    controller.dispose();
  });

  testWidgets('PC Kod tab shows pairing wizard', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = JarvisController();
    await tester.pumpWidget(JarvisApp(controller: controller, loadPlatformTelemetry: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('empty_chat_canvas')), findsOneWidget);
    await tester.tap(find.byTooltip('Menü'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PC Kod')); 
    await tester.pump();
    expect(find.text('Windows PC\'ye Bağlan'), findsOneWidget);
    expect(find.text('PC\'yi Bul'), findsOneWidget);
    expect(find.text('Adresi elle gir'), findsOneWidget);
    controller.dispose();
  });
}
