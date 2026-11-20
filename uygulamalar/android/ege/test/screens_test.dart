import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/main.dart';
import 'package:jarvis_mobile/screens/memory_screen.dart';
import 'package:jarvis_mobile/screens/settings_screen.dart';
import 'package:jarvis_mobile/screens/works_screen.dart';
import 'package:jarvis_mobile/screens/youtube_screen.dart';
import 'package:jarvis_mobile/services/local_whisper.dart';
import 'package:jarvis_mobile/services/work_hub.dart';
import 'package:jarvis_mobile/services/youtube_service.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<JarvisController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final c = JarvisController();
  await c.init(loadPlatformTelemetry: false);
  return c;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Çalışmalar: empty state, create sheet and job cards fit a phone', (tester) async {
    _phone(tester);
    final c = await _controller();
    c.works.jobs.addAll([
      WorkJob(
        id: 'a',
        kind: WorkKind.word,
        task: 'Haftalık proje raporu ve ekip durum özeti',
        status: 'completed',
        createdAt: DateTime.now(),
        summary: '# Rapor\n\n- Madde',
        outputs: const [WorkFile(name: 'haftalik-rapor.docx', path: '/x', mime: 'application/msword', size: 2048)],
      ),
      WorkJob(
        id: 'b',
        kind: WorkKind.audio,
        task: 'Tarkan Kuzu Kuzu',
        status: 'running',
        createdAt: DateTime.now(),
        progress: 0.4,
        stage: '%40 indirildi',
      ),
      WorkJob(
        id: 'c',
        kind: WorkKind.pdf,
        task: 'Toplantı notları',
        status: 'failed',
        createdAt: DateTime.now(),
        error: 'AI yanıt vermedi.',
      ),
    ]);
    await tester.pumpWidget(MaterialApp(home: WorksScreen(controller: c)));
    await tester.pump();
    expect(find.text('Tamamlandı'), findsWidgets);
    expect(find.text('%40 indirildi'), findsOneWidget);
    expect(find.text('haftalik-rapor.docx'), findsOneWidget);
    await tester.tap(find.text('Yeni İş'));
    await tester.pumpAndSettle();
    expect(find.text('Word belgesi başlat'), findsOneWidget);
    await tester.tap(find.text('Excel tablosu'));
    await tester.pumpAndSettle();
    expect(find.text('Excel tablosu başlat'), findsOneWidget);
    c.dispose();
  });

  testWidgets('Settings: on-device Whisper card shows models, progress and engine switch', (tester) async {
    _phone(tester);
    LocalWhisper.testIsDownloaded = (m) async => m.id == 'base-q5_1';
    addTearDown(() => LocalWhisper.testIsDownloaded = null);
    final c = await _controller();
    await c.refreshWhisperModels();
    c.whisperDownloadingId = 'small-q5_1';
    c.whisperDownloadProgress = 0.42;
    c.whisperDownloadedBytes = 76 * 1048576;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsScreen(controller: c))));
    await tester.pump();
    final scroll = find
        .descendant(
          of: find.byType(SettingsScreen),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    await tester.tap(find.text('Konuşmayı yazıya çevir'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Hızlı mod'), 300, scrollable: scroll);
    await tester.pump();
    expect(find.text('Konuşma Tanıma: Whisper'), findsOneWidget);
    expect(find.text('Base (önerilen) • 57 MB'), findsOneWidget);
    expect(find.text('Small • 181 MB'), findsOneWidget);
    expect(find.textContaining('indiriliyor: %42'), findsWidgets);
    expect(find.byKey(const Key('whisper_cancel_small-q5_1')), findsOneWidget);
    expect(find.byKey(const Key('whisper_delete_base-q5_1')), findsOneWidget);
    expect(find.byKey(const Key('whisper_download_tiny-q5_1')), findsOneWidget);
    c.cancelWhisperDownload();
    expect(c.whisperCancelRequested, isTrue);
    c.whisperDownloadingId = null;
    await tester.ensureVisible(find.text('OpenAI API'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI API'));
    await tester.pumpAndSettle();
    expect(c.settings.whisperEngine, 'api');
    expect(find.text('OpenAI API anahtarı (Whisper)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    c.dispose();
  });

  testWidgets('YouTube screen renders results and the now-playing card', (tester) async {
    _phone(tester);
    final c = await _controller();
    c.ytResults = const [
      YtVideo(id: 'NAHRpEqgcL4', title: 'TARKAN - Kuzu Kuzu (Official Music Video)', author: 'Tarkan', duration: Duration(minutes: 4, seconds: 2)),
      YtVideo(id: '_xgryOIbJj4', title: 'Kuzu Kuzu', author: 'Tarkan'),
    ];
    c.musicNow = c.ytResults.first;
    c.musicStatus = const {'state': 'playing', 'positionMs': 30000, 'durationMs': 242000};
    await tester.pumpWidget(MaterialApp(home: YoutubeScreen(controller: c)));
    await tester.pump();
    expect(find.textContaining('Kuzu Kuzu'), findsWidgets);
    expect(find.textContaining('0:30 / 4:02'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    c.dispose();
  });

  testWidgets('Memory screen lists, adds and switches to raw editing', (tester) async {
    _phone(tester);
    final c = await _controller();
    await c.addMemory('Çayı açık severim');
    await tester.pumpWidget(MaterialApp(home: MemoryScreen(controller: c)));
    await tester.pump();
    expect(find.textContaining('Çayı açık severim'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Kızımın adı Ece');
    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();
    expect(c.memoryItems.length, 2);
    await tester.tap(find.byTooltip('Metin olarak düzenle'));
    await tester.pumpAndSettle();
    expect(find.text('Kaydet'), findsOneWidget);
    c.dispose();
  });

  testWidgets('Studio shows the JARVIS hub and the mini player appears', (tester) async {
    _phone(tester);
    final c = await _controller();
    await tester.pumpWidget(JarvisApp(controller: c, loadPlatformTelemetry: false));
    await tester.pump();
    await tester.tap(find.byTooltip('Menü'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stüdyo')); 
    await tester.pump();
    expect(find.text('Ege Merkezi'), findsOneWidget);
    c.musicNow = const YtVideo(id: 'x', title: 'Deneme Şarkısı');
    c.musicStatus = const {'state': 'playing'};
    c.notifyChanged();
    await tester.pump();
    expect(find.text('Deneme Şarkısı'), findsOneWidget);
    c.musicNow = null;
    c.dispose();
  });
}
