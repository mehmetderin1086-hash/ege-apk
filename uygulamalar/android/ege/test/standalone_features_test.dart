import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/ai_client.dart';
import 'package:jarvis_mobile/services/edge_tts_client.dart';
import 'package:jarvis_mobile/services/embedded_keys.dart';
import 'package:jarvis_mobile/services/office_docs.dart';
import 'package:jarvis_mobile/services/realtime_live_service.dart';
import 'package:jarvis_mobile/services/tts_cache.dart';
import 'package:jarvis_mobile/services/work_hub.dart';
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

/// Accepts any request type (incl. multipart) and exposes the raw body.
class _AnyRouter extends http.BaseClient {
  final http.StreamedResponse Function(http.BaseRequest r, List<int> body) handler;
  int calls = 0;

  _AnyRouter(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final body = await request.finalize().toBytes();
    return handler(request, body);
  }
}

http.StreamedResponse _bytes(List<int> b, [int status = 200, String type = 'audio/mpeg']) =>
    http.StreamedResponse(Stream.value(b), status, headers: {'content-type': type});

Map<String, Uint8List> _unzip(Uint8List zip) {
  final a = ZipDecoder().decodeBytes(zip);
  return {for (final f in a.files) if (f.isFile) f.name: f.readBytes()!};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AiClient.resetTtsHealth();
    AiClient.reachabilityProbe = null;
    EdgeTtsClient.testSynthesizer = null;
  });

  group('EmbeddedKeys (standalone phone)', () {
    test('payload round-trips and is not plain text', () {
      final payload = EmbeddedKeys.encode({'g': 'AIza-test', 'az': 'az-key', 'azr': 'westeurope'});
      expect(payload, isNot(contains('AIza')));
      final k = EmbeddedKeys.decode(payload);
      expect(k.gemini, 'AIza-test');
      expect(k.azureKey, 'az-key');
      expect(k.available, isTrue);
      expect(EmbeddedKeys.decode('bozuk!!').available, isFalse);
    });

    test('applyTo repairs loopback chat, sets HD voice, keeps working choices', () {
      const keys = EmbeddedKeys(gemini: 'AIza-g', azureKey: 'az', azureRegion: 'westeurope');
      final fixed = keys.applyTo(const JarvisSettings());
      expect(fixed.provider, ApiProvider.geminiDirect);
      expect(fixed.apiKey, 'AIza-g');
      expect(fixed.model, 'gemini-2.5-flash');
      expect(fixed.azureSpeechKey, 'az');
      expect(fixed.geminiTtsKey, 'AIza-g');
      expect(fixed.proxyTtsVoice, JarvisVoiceCatalog.defaultHdVoice);
      expect(fixed.embeddedKeysVersion, EmbeddedKeys.version);

      const pcProxy = JarvisSettings(
        baseUrl: 'http://10.0.0.5:8317',
        apiKey: 'real-proxy-key',
        azureSpeechKey: 'user-own',
        proxyTtsVoice: 'Kore',
      );
      final kept = keys.applyTo(pcProxy);
      expect(kept.provider, ApiProvider.cliProxyApi);
      expect(kept.baseUrl, 'http://10.0.0.5:8317');
      expect(kept.azureSpeechKey, 'user-own');
      expect(kept.proxyTtsVoice, 'Kore');
      expect(keys.applyTo(pcProxy, force: true).azureSpeechKey, 'az');
    });
  });

  group('Cloud voices', () {
    test('Azure style is resolved per voice and nudges prosody otherwise', () {
      expect(JarvisVoiceCatalog.resolveAzureStyle('tr-TR-Grant:MAI-Voice-2.1-Flash', JarvisVoiceCatalog.styleFor('jarvis')),
          'educational');
      expect(JarvisVoiceCatalog.resolveAzureStyle('tr-TR-Aydin:MAI-Voice-2.1-Flash', JarvisVoiceCatalog.styleFor('warm')),
          'friendlycheerful');
      expect(JarvisVoiceCatalog.resolveAzureStyle('tr-TR-AhmetNeural', JarvisVoiceCatalog.styleFor('calm')), isNull);
      final ssml = AiClient.buildAzureSsml(
        const JarvisSettings(ttsStyle: 'calm'),
        'tr-TR-AhmetNeural',
        'Merhaba <dünya> & JARVIS',
      );
      expect(ssml, isNot(contains('express-as')));
      expect(ssml, contains('rate="-8%"'));
      expect(ssml, contains('&lt;dünya&gt; &amp; JARVIS'));
      expect(AiClient.azureVoiceFor('Kore'), 'tr-TR-Elif:MAI-Voice-2.1-Flash');
      expect(AiClient.azureVoiceFor('Charon'), JarvisVoiceCatalog.defaultHdVoice);
      expect(AiClient.azureVoiceFor('aydin'), 'tr-TR-Aydın:MAI-Voice-2-Flash');
    });

    test('Azure retries without style when the voice rejects it (HTTP 400)', () async {
      final bodies = <String>[];
      final client = _Router((r) {
        bodies.add(r.body);
        return r.body.contains('express-as')
            ? _bytes(utf8.encode('bad style'), 400, 'text/plain')
            : _bytes(List.filled(800, 0xFF));
      });
      final res = await AiClient.synthesizeSpeechDetailed(
        settings: const JarvisSettings(azureSpeechKey: 'k', ttsEngine: 'azure', ttsStyle: 'warm'),
        voice: 'tr-TR-Aydin:MAI-Voice-2.1-Flash',
        text: 'Merhaba',
        client: client,
        useCache: false,
      );
      expect(res.ok, isTrue);
      expect(bodies.length, 2);
      expect(bodies.first, contains('friendlycheerful'));
      expect(bodies.last, isNot(contains('express-as')));
    });

    test('a rejected key is skipped instantly afterwards (circuit breaker)', () async {
      var azureCalls = 0;
      final client = _Router((r) {
        if (r.url.host.contains('tts.speech.microsoft.com')) {
          azureCalls++;
          return _bytes(utf8.encode('denied'), 401, 'text/plain');
        }
        return _bytes(List.filled(400, 0xFF));
      });
      EdgeTtsClient.testSynthesizer = (t, v, r) async => (bytes: Uint8List.fromList(List.filled(400, 1)), ext: 'mp3', error: '');
      const s = JarvisSettings(azureSpeechKey: 'bad', proxyTtsVoice: 'tr-TR-Aydin:MAI-Voice-2.1-Flash');
      final first = await AiClient.synthesizeSpeechDetailed(settings: s, text: 'Bir', client: client, useCache: false);
      expect(first.provider, contains('Edge'));
      final second = await AiClient.synthesizeSpeechDetailed(settings: s, text: 'İki', client: client, useCache: false);
      expect(second.ok, isTrue);
      expect(azureCalls, 1);
      expect(second.attempts.first.detail, contains('geçici olarak atlandı'));
    });

    test('Edge maps Azure-only HD voices to free Turkish voices', () {
      expect(EdgeTtsClient.resolveEdgeVoice('tr-TR-Seda:DragonLatestNeural', isFemale: true), 'tr-TR-EmelNeural');
      expect(EdgeTtsClient.resolveEdgeVoice('tr-TR-Ahmet:DragonLatestNeural', isFemale: false), 'tr-TR-AhmetNeural');
      expect(EdgeTtsClient.resolveEdgeVoice('tr-TR-Aydin:MAI-Voice-2.1-Flash', isFemale: false), 'tr-TR-AhmetNeural');
      expect(EdgeTtsClient.resolveEdgeVoice('tr-TR-EmelNeural', isFemale: true), 'tr-TR-EmelNeural');
    });

    test('quality order prefers HD cloud voices before the robotic backup', () {
      final order = AiClient.ttsProviderOrder(const JarvisSettings(), 'tr-TR-Aydin:MAI-Voice-2.1-Flash');
      expect(order.first, 'azure');
      expect(order.indexOf('edge_neural'), lessThan(order.indexOf('google_translate')));
      expect(order.last, 'google_translate');
      expect(AiClient.ttsProviderOrder(const JarvisSettings(ttsEngine: 'azure'), 'x'),
          ['azure', 'edge_neural', 'google_translate']);
      expect(TtsDiskCache.hashKey('a|b'), isNot(TtsDiskCache.hashKey('a|c')));
      expect(TtsDiskCache.hashKey('aynı'), TtsDiskCache.hashKey('aynı'));
    });
  });

  group('Standalone chat routing', () {
    test('unreachable PC proxy goes straight to Gemini without touching the proxy', () async {
      AiClient.reachabilityProbe = (host, port) async => false;
      final client = _Router((r) {
        expect(r.url.host, 'generativelanguage.googleapis.com', reason: 'proxy must not be called');
        const sse = 'data: {"candidates":[{"content":{"parts":[{"text":"Merhaba"}]}}]}\n\n';
        return _bytes(utf8.encode(sse), 200, 'text/event-stream');
      });
      final events = await AiClient.streamChat(
        settings: const JarvisSettings(baseUrl: 'http://10.9.9.9:8317', apiKey: 'k', geminiTtsKey: 'AIza'),
        messages: [JarvisMessage(id: '1', role: 'user', content: 'selam', timestamp: DateTime(2026))],
        client: client,
      ).toList();
      expect(events.lastWhere((e) => e.fullText != null).fullText, contains('Merhaba'));
      expect(client.seen.length, 1);
    });

    test('system prompt carries dialogue policy, memory and new actions', () {
      final p = AiClient.buildSystemPrompt(const JarvisSettings(memoryText: '- Kahveyi şekersiz içer'));
      expect(p, contains('Diyalog kuralları'));
      expect(p, contains('Kahveyi şekersiz içer'));
      expect(p, contains('play_youtube'));
      expect(p, contains('start_work'));
      final off = AiClient.buildSystemPrompt(const JarvisSettings(memoryText: '- gizli', memoryEnabled: false));
      expect(off, isNot(contains('gizli')));
    });
  });

  group('Office documents', () {
    const spec = {
      'title': 'Proje & Rapor <2026>',
      'paragraphs': ['Giriş **önemli** metin.'],
      'sections': [
        {
          'heading': 'Durum',
          'paragraphs': ['Her şey yolunda.'],
          'bullets': ['Madde 1', 'Madde 2'],
        },
      ],
      'tables': [
        {
          'headers': ['Ad', 'Tutar'],
          'rows': [
            ['Kira', '12500'],
            ['Formül', '=SUM(A1:A2)'],
          ],
        },
      ],
    };

    test('DOCX is a valid package with escaped text, bold runs and a table', () {
      final files = _unzip(OfficeDocs.buildDocx(Map<String, dynamic>.from(spec)));
      expect(files.keys, containsAll(['[Content_Types].xml', 'word/document.xml', 'word/styles.xml', '_rels/.rels']));
      final doc = utf8.decode(files['word/document.xml']!);
      expect(doc, contains('Proje &amp; Rapor &lt;2026&gt;'));
      expect(doc, contains('<w:b/>'));
      expect(doc, contains('<w:tbl>'));
      expect(doc, contains('Heading1'));
    });

    test('XLSX keeps numbers numeric and never emits formulas', () {
      final files = _unzip(OfficeDocs.buildXlsx({
        'sheet': 'Bütçe/2026',
        'headers': ['Kalem', 'Tutar'],
        'rows': [
          ['Kira', '12500'],
          ['Tehlike', '=HYPERLINK("x")'],
          ['Telefon', '05321234567'],
        ],
      }));
      final sheet = utf8.decode(files['xl/worksheets/sheet1.xml']!);
      expect(sheet, contains('<v>12500</v>'));
      expect(sheet, isNot(contains('<f>')));
      expect(sheet, contains('t="inlineStr"'));
      expect(sheet, contains('05321234567'));
      expect(sheet, contains('state="frozen"'));
      final wb = utf8.decode(files['xl/workbook.xml']!);
      expect(wb, contains('name="Bütçe 2026"'));
      expect(OfficeDocs.colName(0), 'A');
      expect(OfficeDocs.colName(27), 'AB');
    });

    test('ZIP round-trip and traversal-safe extraction', () {
      final zip = OfficeDocs.zipFiles([
        (name: 'a.txt', bytes: Uint8List.fromList(utf8.encode('bir'))),
        (name: 'a.txt', bytes: Uint8List.fromList(utf8.encode('iki'))),
      ]);
      final out = OfficeDocs.unzip(zip);
      expect(out.map((e) => e.name), ['a.txt', 'a-2.txt']);
      final evil = Archive()
        ..addFile(ArchiveFile.bytes('../../evil.sh', utf8.encode('rm')))
        ..addFile(ArchiveFile.bytes('ok/b.txt', utf8.encode('ok')));
      final safe = OfficeDocs.unzip(ZipEncoder().encodeBytes(evil));
      expect(safe.map((e) => e.name), ['ok/b.txt']);
      expect(OfficeDocs.docxText(OfficeDocs.buildDocx({'title': 'Başlık', 'paragraphs': ['Satır']})), contains('Satır'));
    });
  });

  group('Work commands & parsing', () {
    test('Windows-style work commands are recognised', () {
      expect(WorkHub.parseCommand('word oluştur: haftalık rapor')?.kind, WorkKind.word);
      expect(WorkHub.parseCommand('Excel tablosu hazırla: aylık bütçe')?.kind, WorkKind.excel);
      expect(WorkHub.parseCommand('pdf oluştur: toplantı notları')?.task, 'toplantı notları');
      expect(WorkHub.parseCommand('araştır: elektrikli araç teşvikleri')?.kind, WorkKind.research);
      expect(WorkHub.parseCommand('ses indir: Tarkan Kuzu Kuzu')?.kind, WorkKind.audio);
      expect(WorkHub.parseCommand('video indir: https://youtu.be/NAHRpEqgcL4')?.kind, WorkKind.video);
      expect(WorkHub.parseCommand('sayfadan veri çıkar: https://example.com')?.kind, WorkKind.scrape);
      expect(WorkHub.parseCommand('İstanbul hakkında web araştırması yap')?.kind, WorkKind.research);
      expect(WorkHub.parseCommand('word belgesi nasıl oluşturulur?'), isNull);
      expect(WorkHub.parseCommand('pdf oluşturma'), isNull);
      expect(WorkHub.parseCommand('bugün hava nasıl'), isNull);
    });

    test('LLM JSON is extracted from fenced or chatty replies', () {
      expect(WorkHub.parseJsonObject('İşte:\n```json\n{"title":"A","paragraphs":["b"]}\n```')?['title'], 'A');
      expect(WorkHub.parseJsonObject('önce {"sheet":"S","headers":["x"],"rows":[[1]]} sonra')?['sheet'], 'S');
      expect(WorkHub.parseJsonObject('json yok'), isNull);
      expect(WorkHub.slug('Haftalık Proje Raporu: Ekim/2026!'), 'haftalik-proje-raporu-ekim-2026');
    });

    test('live tool commands must come from the user transcript', () {
      expect(RealtimeLiveSession.commandMatchesTranscript('el fenerini aç', 'JARVIS el fenerini aç lütfen'), isTrue);
      expect(RealtimeLiveSession.commandMatchesTranscript('tüm kişileri sil', 'bugün hava nasıl'), isFalse);
      // Gemini may normalise numbers/suffixes; that must still pass the guard.
      expect(RealtimeLiveSession.commandMatchesTranscript('5 dakika sayaç kur', 'beş dakikalık sayaç kur'), isTrue);
      expect(RealtimeLiveSession.commandMatchesTranscript('annemi ara ve parayı gönder', 'hava durumu nedir'), isFalse);
      expect(RealtimeLiveSession.commandMatchesTranscript('Tarkan çal', 'bana tarkan çal'), isTrue);
    });
  });

  group('Extended phone commands (controller)', () {
    late JarvisController c;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      c = JarvisController();
      await c.init(loadPlatformTelemetry: false);
    });

    tearDown(() => c.dispose());

    test('memory: remember, list, forget', () async {
      var out = await c.tryExtendedCommand('Şunu hatırla: kahvemi şekersiz içerim');
      expect(out?.reply, contains('Hafızama kaydettim'));
      expect(c.settings.memoryText, contains('kahvemi şekersiz içerim'));
      out = await c.tryExtendedCommand('hafızana kaydet: kızımın adı Ece');
      expect(c.memoryItems.length, 2);
      out = await c.tryExtendedCommand('neyi hatırlıyorsun');
      expect(out?.reply, contains('2 bilgi'));
      out = await c.tryExtendedCommand('kahve bilgisini unut');
      expect(out?.reply, contains('1 bilgi'));
      expect(c.memoryItems.single, contains('Ece'));
      expect((await c.memoryBackups()), isNotEmpty);
    });

    test('reminders: absolute time and relative delay', () async {
      var out = await c.tryExtendedCommand('saat 21:30 için hatırlatıcı kur: toplantı');
      expect(out?.reply, contains('21:30'));
      expect(c.activeTimers.any((t) => t.label == 'toplantı'), isTrue);
      out = await c.tryExtendedCommand('10 dakika sonra hatırlat: çayı demle');
      expect(out?.reply, contains('çayı demle'));
      final t = c.activeTimers.firstWhere((t) => t.label == 'çayı demle');
      expect(t.durationSec, 600);
    });

    test('negation, system summary, ip and unknown text', () async {
      expect((await c.tryExtendedCommand('wifi açma'))?.reply, contains('işlem yapılmadı'));
      expect((await c.tryExtendedCommand('sistem özeti'))?.reply, contains('Model'));
      expect((await c.tryExtendedCommand('IP adresim ne'))?.handled, isTrue);
      expect(await c.tryExtendedCommand('bugün nasılsın'), isNull);
      expect(await c.tryExtendedCommand('el fenerini aç'), isNull);
    });

    test('work commands start jobs; profiles save and apply', () async {
      AiClient.reachabilityProbe = (h, p) async => false;
      final out = await c.tryExtendedCommand('tüm işleri durdur');
      expect(out?.reply, contains('Çalışan bir iş yok'));
      await c.saveProfile('Gece');
      await c.updateSettings(c.settings.copyWith(ttsStyle: 'energetic'));
      final applied = await c.tryExtendedCommand('gece profiline geç');
      expect(applied?.reply, contains('Gece'));
      expect(c.settings.ttsStyle, 'jarvis');
    });
  });

  group('OpenAI Whisper speech recognition (only STT engine)', () {
    test('sends a multipart Whisper request and returns the text', () async {
      final client = _AnyRouter((req, body) {
        expect(req.url.toString(), 'https://api.openai.com/v1/audio/transcriptions');
        expect(req.headers['Authorization'], 'Bearer sk-wh');
        final text = latin1.decode(body);
        expect(text, contains('name="model"\r\n\r\nwhisper-1'));
        expect(text, contains('name="language"\r\n\r\ntr'));
        expect(text, contains('filename="ses.wav"'));
        return _bytes(utf8.encode(jsonEncode({'text': 'Feneri aç'})), 200, 'application/json');
      });
      final r = await AiClient.transcribeAudioWav(
        settings: const JarvisSettings(whisperKey: 'sk-wh'),
        wavBytes: AiClient.silentWav(),
        client: client,
      );
      expect(r.ok, isTrue);
      expect(r.text, 'Feneri aç');
      expect(r.provider, 'OpenAI Whisper');
      expect(client.calls, 1);
    });

    test('explains missing credit, missing key and Groq endpoints in Turkish', () async {
      final noCredit = _AnyRouter((req, body) => _bytes(
            utf8.encode('{"error":{"type":"insufficient_quota","message":"You have no credits remaining."}}'),
            429,
            'application/json',
          ));
      final r = await AiClient.transcribeAudioWav(
        settings: const JarvisSettings(openAiTtsKey: 'sk-empty'),
        wavBytes: AiClient.silentWav(),
        client: noCredit,
      );
      expect(r.ok, isFalse);
      expect(r.error, contains('kredi yok'));

      final none = await AiClient.transcribeAudioWav(
        settings: const JarvisSettings(),
        wavBytes: AiClient.silentWav(),
        client: noCredit,
      );
      expect(none.error, contains('anahtarı gerekli'));
      expect(noCredit.calls, 1);

      const groq = JarvisSettings(
        whisperKey: 'gsk',
        whisperBaseUrl: 'https://api.groq.com/openai/v1',
        whisperModel: 'whisper-large-v3-turbo',
      );
      expect(AiClient.whisperLabel(groq), 'Whisper (Groq)');
    });

    test('old STT choices migrate to Whisper and the OpenAI key is embedded', () {
      final migrated = JarvisSettings.fromJson({'sttMode': 'azure'});
      expect(migrated.sttMode, 'system');
      expect(migrated.whisperModel, 'whisper-1');
      expect(migrated.whisperBaseUrl, 'https://api.openai.com/v1');
      final k = EmbeddedKeys.decode(EmbeddedKeys.encode({'g': 'AIza', 'oa': 'sk-openai'}));
      expect(k.openai, 'sk-openai');
      final applied = k.applyTo(const JarvisSettings());
      expect(applied.whisperKey, 'sk-openai');
      expect(AiClient.whisperKeyFor(applied), 'sk-openai');
      expect(AiClient.silentWav().length, 44 + 16000 * 600 ~/ 1000 * 2);
    });
  });

  test('speech normalisation fixes common STT spellings', () {
    expect(JarvisFeatures.normalizeSpeech("yutup'ta tarkan çal"), contains('YouTube'));
    expect(JarvisFeatures.normalizeSpeech('vatsap aç'), 'WhatsApp aç');
    expect(JarvisFeatures.normalizeSpeech('gugıl haritalar'), 'Google haritalar');
    expect(File('pubspec.yaml').existsSync(), isTrue);
  });
}
