import 'dart:io';

import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:bilgili_flutter/main.dart';
import 'package:bilgili_flutter/models/quiz_models.dart';
import 'package:bilgili_flutter/state/arena_controller.dart';
import 'package:bilgili_flutter/state/question_browser.dart';
import 'package:bilgili_flutter/theme/arena_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('İstanbul Zirve 3D Tema & Görselleri', () {
    test('varsayılan tema İstanbul Boğazı ve 8 İstanbul sahnesi katalogda', () {
      final ctrl = ArenaController.inMemoryForTest();
      expect(ctrl.wallpaperId, 'istanbul_bogaz');
      expect(ctrl.wallpaperClarity, WallpaperClarity.vivid);
      expect(ctrl.currentWallpaper.id, 'istanbul_bogaz');

      const expectedIstanbulIds = [
        'istanbul_bogaz',
        'istanbul_kiz_kulesi',
        'istanbul_galata',
        'istanbul_ayasofya',
        'istanbul_ortakoy',
        'istanbul_skyline',
        'istanbul_dolmabahce',
        'istanbul_suleymaniye',
      ];
      for (final id in expectedIstanbulIds) {
        final preset = ArenaWallpapers.byId(id);
        expect(preset.id, id);
        expect(preset.assetPath, isNotNull);
        expect(File(preset.assetPath!).existsSync(), isTrue,
            reason: '${preset.assetPath} dosyası mevcut olmalı');
      }
    });
  });

  group('Çoklu Kategori Seçimi Motor Testleri', () {
    test('toggleTopicSelection, selectTopicBundle ve clearSelectedTopics doğru çalışır', () {
      final ctrl = ArenaController.inMemoryForTest();
      expect(ctrl.setup.selectedTopics, isEmpty);
      expect(ctrl.setup.isMultiTopic, isFalse);

      ctrl.toggleTopicSelection(Topic.history);
      expect(ctrl.setup.selectedTopics, {Topic.history});
      expect(ctrl.setup.topic, Topic.history);
      expect(ctrl.setup.isMultiTopic, isFalse);

      ctrl.toggleTopicSelection(Topic.geography);
      expect(ctrl.setup.selectedTopics, {Topic.history, Topic.geography});
      expect(ctrl.setup.isMultiTopic, isTrue);
      expect(ctrl.setup.topicsLabel, contains('Tarih'));
      expect(ctrl.setup.topicsLabel, contains('Coğrafya'));

      // Kapatıp tekrar açma
      ctrl.toggleTopicSelection(Topic.history);
      expect(ctrl.setup.selectedTopics, {Topic.geography});
      expect(ctrl.setup.topic, Topic.geography);

      // Hazır paket seçimi
      ctrl.selectTopicBundle({Topic.mathematics, Topic.physics, Topic.chemistry});
      expect(ctrl.setup.selectedTopics, {Topic.mathematics, Topic.physics, Topic.chemistry});
      expect(ctrl.setup.isMultiTopic, isTrue);
      expect(ctrl.countForTopics(ctrl.setup.selectedTopics), greaterThan(100));

      // Temizleme
      ctrl.clearSelectedTopics();
      expect(ctrl.setup.selectedTopics, isEmpty);
      expect(ctrl.setup.topic, Topic.mixed);
    });

    test('sampleQuestions ve startConfiguredRound yalnızca seçili kategorilerden soru çeker', () {
      final ctrl = ArenaController.inMemoryForTest();
      final chosen = {Topic.history, Topic.geography};
      ctrl.selectTopicBundle(chosen);
      ctrl.updateSetup(ctrl.setup.copyWith(questionCount: 12));

      final sampled = ctrl.sampleQuestions(
        RoundSetup(
          topic: Topic.mixed,
          selectedTopics: chosen,
          format: QuestionFormat.mixed,
          questionCount: 12,
        ),
      );
      expect(sampled.length, 12);
      for (final q in sampled) {
        expect(chosen.contains(q.category), isTrue,
            reason: 'Seçilmeyen kategori geldi: ${q.category}');
      }

      ctrl.startConfiguredRound();
      expect(ctrl.activeRound, isNotNull);
      expect(ctrl.activeRound!.questions.length, 12);
      for (final q in ctrl.activeRound!.questions) {
        expect(chosen.contains(q.category), isTrue);
      }
      ctrl.exitRound();
    });

    test('Zirve Merdiveni, Düello ve Rakip Maçı çoklu kategori destekler', () {
      final ctrl = ArenaController.inMemoryForTest();
      final chosen = {Topic.science, Topic.history};

      final zirve = ctrl.zirveSorulari(topics: chosen);
      expect(zirve, isNotNull);
      expect(zirve!.sorular.length, 15);
      for (final q in zirve.sorular) {
        expect(chosen.contains(q.category), isTrue);
        expect(q.options.length, 4);
      }

      ctrl.startDuelTournament(['Ege', 'Deniz'], perPlayer: 2, topics: chosen);
      expect(ctrl.activeRound, isNotNull);
      for (final q in ctrl.activeRound!.questions) {
        expect(chosen.contains(q.category), isTrue);
      }
      ctrl.exitRound();

      ctrl.startRakipMaci(rakipler: const ['Bot'], topics: chosen, soru: 6);
      expect(ctrl.activeRound, isNotNull);
      for (final q in ctrl.activeRound!.questions) {
        expect(chosen.contains(q.category), isTrue);
      }
      ctrl.exitRound();
    });

    test('BrowserPageTask çoklu kategori filtresiyle yalnızca seçili alanları getirir', () async {
      final ctrl = ArenaController.inMemoryForTest();
      final chosen = {Topic.history, Topic.geography};
      final task = BrowserPageTask(
        personal: ctrl.personalQuestions,
        topic: Topic.mixed,
        topics: chosen,
        format: QuestionFormat.mixed,
        collection: PoolCollection.all,
        query: '',
        hidden: const {},
        cursor: firstBrowserPage,
        limit: 20,
      );
      final page = await task.run();
      expect(page.items, isNotEmpty);
      for (final q in page.items) {
        expect(chosen.contains(q.category), isTrue);
      }
    });
  });

  testWidgets('Ana ekranda çoklu kategori paketi seçilip tur başlatılabilir (360x800)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = ArenaController.inMemoryForTest();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: BilgiliApp(controller: ctrl),
      ),
    );
    await tester.pumpAndSettle();

    // Çoklu kategori paketini bul ve seç
    final mainScroll = find.byType(Scrollable).first;
    final sayisal = find.text('Sayısal');
    await tester.scrollUntilVisible(sayisal, 220, scrollable: mainScroll);
    await tester.ensureVisible(sayisal);
    await tester.pumpAndSettle();
    await tester.tap(sayisal);
    await tester.pumpAndSettle();

    expect(ctrl.setup.selectedTopics.length, greaterThanOrEqualTo(3));
    expect(find.text('Temizle'), findsOneWidget);

    // Temizle düğmesi çalışmalı
    final temizle = find.text('Temizle');
    await tester.ensureVisible(temizle);
    await tester.pumpAndSettle();
    await tester.tap(temizle);
    await tester.pumpAndSettle();
    expect(ctrl.setup.selectedTopics, isEmpty);

    // Akademi sekmesinde çoklu kategori filtresi taşmadan çizilmeli
    await tester.tap(find.text('Akademi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kategoriler'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
