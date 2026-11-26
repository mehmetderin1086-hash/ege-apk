import 'package:bilgili_flutter/models/quiz_models.dart';
import 'package:bilgili_flutter/state/arena_controller.dart';
import 'package:bilgili_flutter/state/arena_rooms.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('oda numarası ayarları ve tohumu kayıpsız taşır', () {
    for (final k in OdaAyari.kategoriler) {
      for (final s in OdaAyari.soruSecenekleri) {
        for (final t in OdaAyari.sureSecenekleri) {
          for (final tohum in [0, 1, 777, 5207]) {
            final oda = OdaAyari(kategori: k, soruSayisi: s, sure: t, tohum: tohum);
            expect(oda.kod, hasLength(6));
            final geri = OdaAyari.coz(oda.kod)!;
            expect((geri.kategori, geri.soruSayisi, geri.sure, geri.tohum), (k, s, t, tohum));
          }
        }
      }
    }
    expect(OdaAyari.coz('12a'), isNull);
  });

  test('aynı oda numarası aynı soruları üretir; süre ve çok oyuncu ayarı uygulanır', () {
    final oda = OdaAyari(kategori: Topic.history, soruSayisi: 7, sure: 40, tohum: 1234);
    List<String> sorular() {
      final ctrl = ArenaController.inMemoryForTest();
      expect(ctrl.startOdaRound(OdaAyari.coz(oda.kod)!, ['Ayşe']), isTrue);
      final r = ctrl.activeRound!;
      expect(r.totalTimerSeconds, 40);
      expect(r.questions, hasLength(7));
      final ids = r.questions.map((q) => q.text).toList();
      ctrl.exitRound();
      ctrl.dispose();
      return ids;
    }
    expect(sorular(), sorular());

    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);
    expect(ctrl.startOdaRound(oda, ['A', 'B', 'C']), isTrue);
    expect(ctrl.activeRound!.isDuel, isTrue);
    expect(ctrl.activeRound!.questions, hasLength(21));
    ctrl.exitRound();
  });

  test('rakip maçında rakipler puan toplar ve sıralama oluşur', () {
    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);
    expect(ctrl.startRakipMaci(rakipler: ['Ada', 'Kerem', 'Elif', 'Mert'], soru: 7, sure: 20), isTrue);
    final r = ctrl.activeRound!;
    expect(r.hasRivals, isTrue);
    expect(r.totalTimerSeconds, 20);
    while (!r.finished) {
      ctrl.submitChoice(r.current.answer);
      if (r.currentIndex == r.questions.length - 1) {
        ctrl.finishActiveRound();
      } else {
        ctrl.nextQuestion();
      }
    }
    expect(r.rivalScores.any((s) => s > 0), isTrue);
    final standings = ctrl.history.first.duelStandings;
    expect(standings, hasLength(5));
    expect(standings.map((s) => s['name']), contains('Sen'));
  });

  test('etkinlik takvimi her an en az bir güncel etkinlik verir ve hak sınırı uygulanır', () {
    for (var g = 0; g < 400; g++) {
      final t = DateTime(2026, 1, 3).add(Duration(hours: g * 7));
      expect(EtkinlikTakvimi.guncel(t), isNotEmpty, reason: '$t');
    }
    final ctrl = ArenaController.inMemoryForTest();
    addTearDown(ctrl.dispose);
    final e = EtkinlikTakvimi.guncel(DateTime(2026, 11, 22, 12)).first;
    for (var i = 0; i < e.hak; i++) {
      expect(ctrl.startEtkinlik(e), isTrue);
      expect(ctrl.activeRound!.questions.length, lessThanOrEqualTo(e.soruSayisi));
      ctrl.exitRound();
    }
    expect(ctrl.startEtkinlik(e), isFalse);
    expect(ctrl.etkinlikDenemesi(e), e.hak);
  });
}
