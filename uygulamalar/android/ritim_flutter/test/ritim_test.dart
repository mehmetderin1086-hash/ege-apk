import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ritim_flutter/lyrics_service.dart';
import 'package:ritim_flutter/main.dart';
import 'package:ritim_flutter/ritim_ai_service.dart';
import 'package:ritim_flutter/ritim_models.dart';
import 'package:ritim_flutter/ritim_store.dart';
import 'package:ritim_flutter/theme_design.dart';
import 'package:ritim_flutter/youtube_engine.dart';

void main() {
  group('MediaURLPolicy', () {
    test('canonicalizes standard, shorts and youtu.be URLs', () {
      expect(
        MediaURLPolicy.canonicalInput('https://youtu.be/dQw4w9WgXcQ').toString(),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(
        MediaURLPolicy.canonicalInput('https://www.youtube.com/shorts/dQw4w9WgXcQ')
            .toString(),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(
        MediaURLPolicy.canonicalInput(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=RDdQw4w9WgXcQ',
          stripMix: true,
        ).toString(),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    });

    test('rejects insecure HTTP or channel links', () {
      expect(
        () => MediaURLPolicy.canonicalInput('http://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        throwsA(isA<RitimException>()),
      );
      expect(
        () => MediaURLPolicy.canonicalInput('https://www.youtube.com/@artist'),
        throwsA(isA<RitimException>()),
      );
    });

    test('computes format+quality-aware deduplication key', () {
      final k1 = MediaURLPolicy.downloadKey(
        'https://youtu.be/dQw4w9WgXcQ',
        format: DownloadFormat.mp3,
        quality: DownloadQuality.standard,
      );
      final k2 = MediaURLPolicy.downloadKey(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        format: DownloadFormat.mp4,
        quality: DownloadQuality.highest,
      );
      expect(k1, isNotNull);
      expect(k2, isNotNull);
      expect(k1, isNot(equals(k2)));
    });
  });

  group('YouTube Live Guard & Two-Tier Stream Downloader', () {
    test('identifies 24/7 live broadcast renderers and allows normal videos', () {
      expect(
        NativeYouTubeCatalog.isLiveRenderer({
          'videoId': 'abc123def45',
          'badges': [
            {
              'metadataBadgeRenderer': {
                'style': 'BADGE_STYLE_TYPE_LIVE_NOW',
                'label': 'CANLI',
              },
            },
          ],
        }),
        isTrue,
      );

      expect(
        NativeYouTubeCatalog.isLiveRenderer({
          'videoId': 'O-Rh_qnDpWU',
          'lengthText': {'simpleText': '1:02:14'},
        }),
        isFalse,
      );
    });

    test('downloads ranged adaptive M4A and plain muxed MP4 streams reliably',
        () async {
      final prevOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevOverrides);

      final payload = List<int>.generate(32768, (i) => i & 0xFF);
      String? lastRangeHeader;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        lastRangeHeader = req.headers.value('range');
        if (req.uri.path == '/adaptive.m4a') {
          if (lastRangeHeader == null) {
            req.response.statusCode = 403;
            await req.response.close();
            return;
          }
          req.response.statusCode = 206;
          req.response.contentLength = payload.length;
          req.response.add(payload);
          await req.response.close();
        } else if (req.uri.path == '/muxed.mp4') {
          req.response.statusCode = 200;
          req.response.contentLength = payload.length;
          req.response.add(payload);
          await req.response.close();
        }
      });

      final tmpDir = Directory.systemTemp.createTempSync('ritim_dl_test_');
      addTearDown(() {
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      });

      final engine = NativeYouTubeDownloaderEngine();

      // 1) Adaptive stream MUST send Range: bytes=0-(len-1) to avoid 403
      final outM4a = File('${tmpDir.path}/song.m4a');
      await engine.downloadStream(
        stream: ResolvedMediaStream(
          url: Uri.parse('http://127.0.0.1:${server.port}/adaptive.m4a'),
          headers: const {'User-Agent': 'com.google.android.youtube/20.10.38'},
          fileExtension: 'm4a',
          bitrate: 128000,
          contentLength: payload.length,
          itag: 140,
          requiresRange: true,
        ),
        destination: outM4a,
        isCancelled: () => false,
        onProgress: (_, _, _) {},
      );
      expect(lastRangeHeader, 'bytes=0-${payload.length - 1}');
      expect(outM4a.lengthSync(), payload.length);

      // 2) Muxed itag=18 stream sends plain GET without Range
      final outMp4 = File('${tmpDir.path}/video.mp4');
      await engine.downloadStream(
        stream: ResolvedMediaStream(
          url: Uri.parse('http://127.0.0.1:${server.port}/muxed.mp4'),
          headers: const {'User-Agent': 'com.google.android.youtube/20.10.38'},
          fileExtension: 'mp4',
          bitrate: 500000,
          itag: 18,
          resolution: 360,
          requiresRange: false,
        ),
        destination: outMp4,
        isCancelled: () => false,
        onProgress: (_, _, _) {},
      );
      expect(lastRangeHeader, isNull);
      expect(outMp4.lengthSync(), payload.length);
    });
  });

  group('File Export & Share Naming', () {
    test('builds clean human-readable filenames and MIME types for sharing', () {
      final audioTrack = MediaTrack(
        id: 't-audio',
        title: 'Gece: Yolu / Akustik?',
        artist: 'Ritim Studio',
        fileName: 'a8098c1a-f86e.m4a',
        kind: MediaKind.audio,
      );
      expect(
        RitimController.cleanExportFileNameFor(audioTrack),
        'Ritim Studio - Gece Yolu Akustik.m4a',
      );
      expect(RitimController.mimeTypeFor(audioTrack), 'audio/mp4');

      final videoTrack = MediaTrack(
        id: 't-video',
        title: 'Canlı Sahne Klip',
        artist: 'Bilinmeyen sanatçı',
        fileName: 'v123.mp4',
        kind: MediaKind.video,
      );
      expect(
        RitimController.cleanExportFileNameFor(videoTrack),
        'Canlı Sahne Klip.mp4',
      );
      expect(RitimController.mimeTypeFor(videoTrack), 'video/mp4');
    });
  });

  group('LRCParser & Sync', () {
    test('parses timestamps, offset metadata and finds active line', () {
      const sample = '''
[ar:Ritim Studio]
[offset:+500]
[00:05.00]İlk satır
[00:12.50]İkinci satır
[00:20.00]Son satır
''';
      final parsed = LRCParser.parse(sample);
      expect(parsed.lines.length, 3);
      expect(parsed.lines.first.time, closeTo(4.5, 0.01));

      final doc = TrackLyrics(
        trackID: 't1',
        rawText: sample,
        plainText: parsed.plainText,
        lines: parsed.lines,
        sourceName: 'Test',
      );
      expect(doc.activeLine(3.0), isNull);
      expect(doc.activeLine(5.0)?.text, 'İlk satır');
      expect(doc.activeLine(13.0)?.text, 'İkinci satır');
      doc.offset = 2.0;
      expect(doc.activeLine(13.0)?.text, 'İlk satır');
    });
  });

  group('SmartCollections', () {
    test('separates unheard, recent, rediscover, and history accurately', () {
      final now = DateTime(2026, 11, 13);
      final t1 = MediaTrack(
        id: '1',
        title: 'Hiç Çalınmadı',
        fileName: '1.m4a',
        addedAt: now.subtract(const Duration(days: 2)),
        playCount: 0,
      );
      final t2 = MediaTrack(
        id: '2',
        title: 'Eski Favori',
        fileName: '2.m4a',
        addedAt: now.subtract(const Duration(days: 45)),
        isFavorite: true,
        playCount: 6,
        lastPlayedAt: now.subtract(const Duration(days: 20)),
      );
      final t3 = MediaTrack(
        id: '3',
        title: 'Dün Çalındı',
        fileName: '3.m4a',
        addedAt: now.subtract(const Duration(days: 5)),
        playCount: 3,
        lastPlayedAt: now.subtract(const Duration(days: 1)),
      );
      final all = [t1, t2, t3];

      expect(SmartCollection.unheard.tracksIn(all, now: now).map((e) => e.id), ['1']);
      expect(
        SmartCollection.recent.tracksIn(all, now: now).map((e) => e.id),
        containsAll(['1', '3']),
      );
      expect(SmartCollection.rediscover.tracksIn(all, now: now).map((e) => e.id), ['2']);
      expect(SmartCollection.history.tracksIn(all, now: now).first.id, '3');
    });
  });

  group('CLIProxyAPI AI Normalization & Model Providers', () {
    test('categorizes multi-provider models and parses structured reply', () {
      expect(RitimAIClient.providerName('gemini-2.5-pro', null), 'Gemini');
      expect(RitimAIClient.providerName('claude-3-7-sonnet', null), 'Claude');
      expect(RitimAIClient.providerName('gpt-5', null), 'ChatGPT / Codex');
      expect(RitimAIClient.providerName('deepseek-r1', null), 'DeepSeek');
      expect(RitimAIClient.providerName('qwen-max', null), 'Qwen');

      const jsonReply = '''
```json
{"reply":"Gece modu için yumuşak bir liste hazırladım.","playlist":{"name":"Gece Akışı","track_ids":["u1","invalid-id"]},"search_queries":["türkçe akustik lo-fi"],"action":"play"}
```
''';
      final parsed = RitimAIClient.normalizeReply(
        jsonReply,
        model: 'claude-3-7-sonnet',
        allowedIds: {'u1', 'u2'},
      );
      expect(parsed.reply, contains('Gece modu'));
      expect(parsed.playlist?.trackIDs, ['u1']);
      expect(parsed.action, AIAction.play);
      expect(parsed.searchQueries, ['türkçe akustik lo-fi']);
    });
  });

  testWidgets(
      'RitimApp renders all 5 illustrated tabs, studio action buttons, and wallpaper switcher cleanly',
      (WidgetTester tester) async {
    final tmpDir = Directory.systemTemp.createTempSync('ritim_test_');
    addTearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    final controller = RitimController(
      overrideDirectory: tmpDir,
      enableNativePlayer: false,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(() => controller.init());
    controller.tracks.add(MediaTrack(
      id: 'sample-1',
      title: 'Test Ritim',
      artist: 'Deneme Sanatçı',
      fileName: 'sample.m4a',
      duration: 120,
    ));
    controller.recordListeningSeconds('sample-1', 90);
    await tester.runAsync(() => controller.setWallpaper(RitimWallpaper.nightDrive));
    expect(controller.wallpaper, RitimWallpaper.nightDrive);

    await tester.pumpWidget(RitimApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ritim'), findsOneWidget);
    expect(find.text('BUGÜNÜN RİTMİ'), findsOneWidget);
    expect(find.text('MP3 & MP4'), findsOneWidget);
    expect(find.text('YouTube Ara'), findsOneWidget);

    await tester.tap(find.text('Ara'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ara & Keşfet'), findsOneWidget);

    await tester.tap(find.text('Kitaplığım'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Test Ritim'), findsOneWidget);

    await tester.tap(find.text('İndir'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('İndirmeler'), findsOneWidget);
    expect(find.text('MP4 İndir'), findsOneWidget);

    await tester.tap(find.text('Asistan'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ritim Asistan'), findsOneWidget);
    expect(find.text('AI DJ'), findsOneWidget);
  });
}
