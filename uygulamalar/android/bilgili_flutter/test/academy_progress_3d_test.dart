import 'dart:io';

import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:bilgili_flutter/main.dart';
import 'package:bilgili_flutter/models/quiz_models.dart';
import 'package:bilgili_flutter/state/arena_controller.dart';
import 'package:bilgili_flutter/state/question_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('3D Oyun Logosu & Varlık Doğrulaması', () {
    test('3D logo, uygulama ikonu, açılış görseli ve tüm Android yoğunlukları mevcut', () {
      const files = [
        'assets/images/app_logo_3d.png',
        'assets/images/app_icon.png',
        'android/app/src/main/res/drawable-nodpi/launch_logo.png',
        'android/app/src/main/res/drawable-nodpi/ic_launcher_background.png',
        'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
        'android/app/src/main/res/mipmap-hdpi/ic_launcher.png',
        'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png',
        'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png',
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png',
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png',
      ];
      for (final path in files) {
        final f = File(path);
        expect(f.existsSync(), isTrue, reason: '$path bulunmalı');
        expect(f.lengthSync(), greaterThan(500), reason: '$path boş olmamalı');
      }
    });
  });

  group('Akademi & İlerleme Motor Geliştirmeleri', () {
    test('BrowserPageTask zorluk ve durum filtrelerini uygular', () async {
      final ctrl = ArenaController.inMemoryForTest();
      final task = BrowserPageTask(
        personal: ctrl.personalQuestions,
        topic: Topic.history,
        topics: const {Topic.history},
        format: QuestionFormat.mixed,
        collection: PoolCollection.all,
        difficulty: Difficulty.hard,
        statusFilter: PoolStatusFilter.unsolved,
        playedIds: const {},
        query: '',
        hidden: const {},
        cursor: firstBrowserPage,
        limit: 15,
      );
      final page = await task.run();
      expect(page.items, isNotEmpty);
      expect(page.totalEstimate, greaterThan(0));
      for (final q in page.items) {
        expect(q.category, Topic.history);
        expect(q.difficulty, Difficulty.hard);
      }
    });

    test('startFilteredAcademyRound, startBookmarksRound ve Leitner flashcard akışı çalışır', () {
      final ctrl = ArenaController.inMemoryForTest();

      // Filtrelenmiş Akademi turu
      final started = ctrl.startFilteredAcademyRound(
        topics: const {Topic.science, Topic.history},
        difficulty: Difficulty.medium,
        count: 6,
      );
      expect(started, isTrue);
      expect(ctrl.activeRound, isNotNull);
      expect(ctrl.activeRound!.questions.length, 6);
      final sampleQ = ctrl.activeRound!.questions.first;
      for (final q in ctrl.activeRound!.questions) {
        expect({Topic.science, Topic.history}.contains(q.category), isTrue);
        expect(q.difficulty, Difficulty.medium);
      }
      ctrl.exitRound();

      // Deftere kaydet ve defterden test başlat
      ctrl.toggleBookmark(sampleQ);
      expect(ctrl.isBookmarked(sampleQ), isTrue);
      expect(ctrl.startBookmarksRound(), isTrue);
      expect(ctrl.activeRound!.questions.first.id, sampleQ.id);
      ctrl.exitRound();

      // Leitner tekrar destesine elle ekle ve 3D kart sonucunu işle
      ctrl.addQuestionToReviewDeck(sampleQ);
      expect(ctrl.isInReviewDeck(sampleQ), isTrue);
      final xpBefore = ctrl.xp;
      ctrl.recordFlashcardReview(sampleQ, true);
      expect(ctrl.xp, xpBefore + 5);
      final updatedCard =
          ctrl.reviewDeck.firstWhere((c) => c.question.poolKey == sampleQ.poolKey);
      expect(updatedCard.box, 1);

      // Profil güncelleme
      final p = ctrl.studyProfiles.first;
      ctrl.updateStudyProfile(
        StudyProfile(
          id: p.id,
          title: 'Güncellenen Profil',
          exam: p.exam,
          lesson: p.lesson,
          difficulty: Difficulty.hard,
          questionCount: 20,
        ),
      );
      expect(ctrl.studyProfiles.first.title, 'Güncellenen Profil');
      expect(ctrl.studyProfiles.first.questionCount, 20);
    });

    test('16 rozet canlı ilerleme takibi içerir ve AI Stüdyo rozeti bulunmaz', () {
      final ctrl = ArenaController.inMemoryForTest();
      final badges = ctrl.badges;
      expect(badges.length, 16);
      expect(badges.any((b) => b.id == 'ai_explorer'), isFalse);
      for (final b in badges) {
        expect(b.target, greaterThan(0));
        expect(b.progress, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  testWidgets(
      'AI Stüdyo tamamen kalktı; Akademi ve İlerleme alt bölümleri 360x800 ekranda taşmadan çizilir',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = ArenaController.inMemoryForTest();
    // Gerçekçi ilerleme verisi doldur
    ctrl.xp = 620;
    ctrl.zirveEnIyi = 30000;
    ctrl.zirveEnUstBasamak = 7;
    ctrl.categoryAnswered[Topic.biology.label] = 5;
    ctrl.categoryCorrect[Topic.biology.label] = 3;
    ctrl.categoryAnswered[Topic.statistics.label] = 2;
    ctrl.categoryCorrect[Topic.statistics.label] = 2;
    final sample = ctrl.sampleQuestions(const RoundSetup(questionCount: 3));
    for (final q in sample) {
      ctrl.toggleBookmark(q);
      ctrl.addQuestionToReviewDeck(q);
    }

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: BilgiliApp(controller: ctrl),
      ),
    );
    await tester.pumpAndSettle();

    // AI Stüdyo kesinlikle yok
    expect(find.text('AI Stüdyo'), findsNothing);
    expect(find.text('AI Soru Stüdyosu'), findsNothing);
    expect(find.text('CLIProxy & AI Stüdyosu'), findsNothing);

    // 1. Akademi alt bölümlerini gez: Havuz -> Tekrar -> Defterim -> Paketler -> Profiller
    await tester.tap(find.text('Akademi'));
    await tester.pumpAndSettle();
    expect(find.text('Bilgi Akademisi & Havuz'), findsOneWidget);
    expect(find.text('Filtreyle Tur (10)'), findsOneWidget);
    expect(find.text('3D Kart Modu'), findsOneWidget);

    Future<void> tapPill(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tapPill(find.textContaining('Tekrar ('));
    expect(find.textContaining('Leitner 6 Kutu Dağılımı'), findsOneWidget);

    await tapPill(find.textContaining('Defterim ('));
    expect(find.text('Defterden Test'), findsOneWidget);

    await tapPill(find.textContaining('Paketler ('));
    expect(find.text('Soru Paketi Aktarımı (JSON)'), findsOneWidget);

    await tapPill(find.textContaining('Profiller ('));
    expect(find.text('Hızlı Şablonlar'), findsOneWidget);

    // 2. İlerleme alt bölümlerini gez: Genel Bakış -> Alan Ustalığı -> Rozetler -> Geçmiş
    await tester.tap(find.text('İlerleme'));
    await tester.pumpAndSettle();
    expect(find.text('İlerleme & Başarımlar'), findsOneWidget);
    expect(find.text('Performans Karnesi'), findsOneWidget);

    await tapPill(find.textContaining('Alan Ustalığı'));
    expect(find.text('Uzman'), findsOneWidget);

    await tapPill(find.textContaining('Rozetler'));
    expect(find.textContaining('/ 16 Rozet Kazanıldı'), findsOneWidget);

    await tapPill(find.textContaining('Geçmiş'));
    expect(find.text('Ort. Başarı'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
