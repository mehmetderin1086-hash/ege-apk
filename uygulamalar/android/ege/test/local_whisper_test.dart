import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/local_whisper.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves [data] like the Hugging Face CDN (optionally honouring Range).
class _ModelServer extends http.BaseClient {
  final Uint8List data;
  final bool honorRange;
  final List<String?> ranges = [];
  final List<Uri> urls = [];

  _ModelServer(this.data, {this.honorRange = true});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final range = request.headers['Range'];
    ranges.add(range);
    urls.add(request.url);
    if (range != null && honorRange) {
      final start = int.parse(
        RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
      );
      final rest = data.sublist(start);
      final half = rest.length ~/ 2;
      return http.StreamedResponse(
        Stream.fromIterable([rest.sublist(0, half), rest.sublist(half)]),
        206,
      );
    }
    return http.StreamedResponse(Stream.value(data), 200);
  }
}

WhisperModelInfo _fakeModel(Uint8List data, {String? sha}) => WhisperModelInfo(
  id: 'test',
  file: 'ggml-test.bin',
  label: 'Test',
  description: '',
  sizeBytes: data.length,
  sha256: sha ?? sha256.convert(data).toString(),
);

Uint8List _randomBytes(int n) {
  final r = Random(7);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('jarvis_whisper_test');
    LocalWhisper.testDirProvider = () async => tmp;
  });

  tearDown(() async {
    LocalWhisper.testDirProvider = null;
    LocalWhisper.testTranscriber = null;
    LocalWhisper.testIsDownloaded = null;
    LocalWhisper.testDownloader = null;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('Model catalog (Hugging Face ggerganov/whisper.cpp)', () {
    test('every model has a Hugging Face URL, exact size and SHA-256', () {
      final ids = LocalWhisper.models.map((m) => m.id).toSet();
      expect(ids.length, LocalWhisper.models.length);
      for (final m in LocalWhisper.models) {
        expect(m.file, startsWith('ggml-'));
        expect(m.file, endsWith('.bin'));
        expect(
          m.url,
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${m.file}',
        );
        expect(
          RegExp(r'^[0-9a-f]{64}$').hasMatch(m.sha256),
          isTrue,
          reason: m.id,
        );
        expect(m.sizeBytes, greaterThan(20 * 1024 * 1024));
      }
      // 3.0: realme 10 ölçümünde Small 5-8 sn sürdüğü için varsayılan Base.
      expect(LocalWhisper.defaultModelId, 'base-q5_1');
      expect(LocalWhisper.byId('olmayan').id, 'base-q5_1');
      expect(LocalWhisper.byId('small-q5_1').sizeLabel, '181 MB');
    });
  });

  group('Settings', () {
    test('older settings migrate to the on-device engine', () {
      final s = JarvisSettings.fromJson({
        'settingsVersion': 6,
        'whisperEngine': 'api',
      });
      expect(s.sttMode, 'system');
      expect(s.whisperEngine, 'local');
      expect(s.localWhisperModel, 'base-q5_1');
      expect(s.whisperFastMode, isTrue);
    });

    test(
      'v7 Small seçimi (eski varsayılan) Base\'e taşınır, v8 seçim korunur',
      () {
        final v7 = JarvisSettings.fromJson({
          'settingsVersion': 7,
          'localWhisperModel': 'small-q5_1',
        });
        expect(v7.localWhisperModel, 'base-q5_1');
        final v8 = JarvisSettings.fromJson({
          'settingsVersion': 8,
          'localWhisperModel': 'small-q5_1',
        });
        expect(v8.localWhisperModel, 'small-q5_1');
      },
    );

    test('v8 keeps the chosen engine, model and fast mode', () {
      final json = const JarvisSettings()
          .copyWith(
            whisperEngine: 'api',
            localWhisperModel: 'base-q5_1',
            whisperFastMode: false,
          )
          .toJson();
      expect(json['settingsVersion'], 10);
      final s = JarvisSettings.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(s.whisperEngine, 'api');
      expect(s.localWhisperModel, 'base-q5_1');
      expect(s.whisperFastMode, isFalse);
      final bad = JarvisSettings.fromJson({
        ...json,
        'localWhisperModel': 'dev-model',
      });
      expect(bad.localWhisperModel, 'base-q5_1');
    });
  });

  group('Model download', () {
    test('resumes a partial file with Range and verifies SHA-256', () async {
      final data = _randomBytes(300 * 1024);
      final model = _fakeModel(data);
      final part = File('${(await LocalWhisper.modelFile(model)).path}.part');
      await part.writeAsBytes(data.sublist(0, 100 * 1024));
      final server = _ModelServer(data);
      final progress = <int>[];
      await LocalWhisper.download(
        model,
        client: server,
        onProgress: (got, _) => progress.add(got),
      );
      expect(server.ranges.single, 'bytes=${100 * 1024}-');
      expect(server.urls.single.toString(), model.url);
      final f = await LocalWhisper.modelFile(model);
      expect(await f.readAsBytes(), data);
      expect(await part.exists(), isFalse);
      expect(progress.last, data.length);
      expect(await LocalWhisper.isDownloaded(model), isTrue);
    });

    test('restarts from zero when the server ignores Range', () async {
      final data = _randomBytes(64 * 1024);
      final model = _fakeModel(data);
      final part = File('${(await LocalWhisper.modelFile(model)).path}.part');
      await part.writeAsBytes(List.filled(10 * 1024, 9));
      await LocalWhisper.download(
        model,
        client: _ModelServer(data, honorRange: false),
      );
      expect(await (await LocalWhisper.modelFile(model)).readAsBytes(), data);
    });

    test('a corrupted download is rejected and removed', () async {
      final data = _randomBytes(32 * 1024);
      final model = _fakeModel(data, sha: '0' * 64);
      await expectLater(
        LocalWhisper.download(model, client: _ModelServer(data)),
        throwsA(isA<StateError>()),
      );
      expect(await LocalWhisper.isDownloaded(model), isFalse);
      expect(
        await File('${(await LocalWhisper.modelFile(model)).path}.part')
            .exists(),
        isFalse,
      );
    });

    test(
      'cancel stops the transfer and keeps nothing half-installed',
      () async {
        final data = _randomBytes(32 * 1024);
        final model = _fakeModel(data);
        await expectLater(
          LocalWhisper.download(
            model,
            client: _ModelServer(data),
            isCancelled: () => true,
          ),
          throwsA(predicate((e) => e.toString().contains('iptal'))),
        );
        expect(await LocalWhisper.isDownloaded(model), isFalse);
      },
    );

    test('delete removes the model and partial files', () async {
      final data = _randomBytes(8 * 1024);
      final model = _fakeModel(data);
      await LocalWhisper.download(model, client: _ModelServer(data));
      await LocalWhisper.delete(model);
      expect(await LocalWhisper.isDownloaded(model), isFalse);
    });
  });

  group('Transcript cleanup', () {
    test(
      'drops subtitle credits and prompt echoes Whisper invents on silence',
      () {
        expect(LocalWhisper.cleanTranscript('Altyazı M.K.'), '');
        expect(
          LocalWhisper.cleanTranscript(' İzlediğiniz için teşekkürler. '),
          '',
        );
        expect(LocalWhisper.cleanTranscript('[Müzik]'), '');
        expect(LocalWhisper.cleanTranscript('♪ ♪'), '');
        expect(
          LocalWhisper.cleanTranscript('JARVIS, YouTube, WhatsApp, Google.'),
          '',
        );
      },
    );

    test('keeps real commands', () {
      expect(
        LocalWhisper.cleanTranscript(' Teşekkürler JARVIS. '),
        'Teşekkürler JARVIS.',
      );
      expect(LocalWhisper.cleanTranscript('Müzik aç'), 'Müzik aç');
      expect(LocalWhisper.cleanTranscript('YouTube aç'), 'YouTube aç');
      expect(
        LocalWhisper.cleanTranscript('Yarın   sabah sekizde beni uyandır.'),
        'Yarın sabah sekizde beni uyandır.',
      );
    });

    test('silent WAV is a valid 16 kHz mono PCM file', () {
      final w = LocalWhisper.silentWav();
      expect(w.length, 44 + 16000 * 600 ~/ 1000 * 2);
      expect(ascii.decode(w.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(w.sublist(8, 12)), 'WAVE');
      expect(ByteData.sublistView(w).getUint32(24, Endian.little), 16000);
    });
  });

  group('Android-only speech recognition routing', () {
    late JarvisController c;
    var whisperCalls = 0;
    var downloads = 0;
    const channel = MethodChannel('com.jarvis.assistant/device');
    setUp(() async {
      whisperCalls = 0;
      downloads = 0;
      SharedPreferences.setMockInitialValues({});
      LocalWhisper.testIsDownloaded = (_) async => true;
      LocalWhisper.testTranscriber = (_, __) async {
        whisperCalls++;
        return (ok: true, text: 'MUST NOT RUN', ms: 1, error: null);
      };
      LocalWhisper.testDownloader = (_, __) async { downloads++; };
      c = JarvisController();
      await c.init(loadPlatformTelemetry: false);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      c.dispose();
    });
    test('legacy Whisper settings cannot bypass Android-only routing', () async {
      c.settings = c.settings.copyWith(sttMode: 'whisper', whisperEngine: 'api', whisperKey: 'sk-test');
      final wav = LocalWhisper.silentWav();
      ByteData.sublistView(wav).setInt16(44, -1234, Endian.little);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'transcribePhoneAudio') return null;
        expect((call.arguments as Map)['pcm'], wav.sublist(44));
        return {'status': 'OK', 'text': ' Saat on dört otuz. '};
      });
      final result = await c.transcribeSpeech(wav);
      expect(result.ok, true);
      expect(result.text, 'Saat on dört otuz.');
      expect(result.provider, 'Android yerel STT');
      expect(whisperCalls, 0);
    });
    for (final status in ['UNAVAILABLE', 'SOURCE_UNSUPPORTED', 'ERROR_13', 'NO_SPEECH', 'CANCELLED']) {
      test('Android $status never falls back to Whisper', () async {
        c.settings = c.settings.copyWith(whisperKey: 'sk-test', whisperEngine: 'api');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => call.method == 'transcribePhoneAudio' ? {'status': status} : null);
        final result = await c.transcribeSpeech(LocalWhisper.silentWav());
        expect(result.ok, false);
        expect(result.provider, 'Android yerel STT');
        expect(result.error, isNotEmpty);
        expect(whisperCalls, 0);
        expect(downloads, 0);
      });
    }
    test('startup preparation cannot download or warm Whisper', () async {
      LocalWhisper.testIsDownloaded = (_) async => false;
      await c.refreshWhisperModels(autoDownload: true);
      c.warmUpWhisper();
      expect(downloads, 0);
      expect(whisperCalls, 0);
    });
    test('legacy Whisper diagnostics are disabled too', () async {
      expect((await c.checkWhisperApi()).ok, false);
      expect((await c.checkLocalWhisper()).ok, false);
      expect(whisperCalls, 0);
    });
  });
}
