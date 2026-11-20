import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/services/turkish_speech.dart';
import 'package:jarvis_mobile/services/voice_service.dart';

void main() {
  test('bus timetable keeps clock, route and remaining time distinct', () {
    expect(
      TurkishSpeech.normalize('220 numaralı hat: 19:30. Kalan: 5 dk.'),
      'iki yüz yirmi numaralı hat: saat on dokuz otuz. Kalan: beş dakika.',
    );
    expect(
      TurkishSpeech.normalize('saat 09.05 / 00:00 / 23:59'),
      'saat dokuz sıfır beş / saat sıfır / saat yirmi üç elli dokuz',
    );
  });
  test('explicit durations are not spoken as clock times', () {
    expect(
      TurkishSpeech.normalize('Süre: 05:30'),
      'Süre: beş dakika otuz saniye',
    );
    expect(TurkishSpeech.normalize('05:30 dk'), 'beş dakika otuz saniye');
    expect(
      TurkishSpeech.normalize('125:10 dakika'),
      'yüz yirmi beş dakika on saniye',
    );
  });
  test('valid dates, lira and percentages have Turkish units', () {
    expect(
      TurkishSpeech.normalize('17.11.2026'),
      'on yedi Kasım iki bin yirmi altı',
    );
    expect(
      TurkishSpeech.normalize('1.234,50 TL / 12,05 ₺ / ₺10,5'),
      'bin iki yüz otuz dört lira elli kuruş / on iki lira beş kuruş / on lira elli kuruş',
    );
    expect(
      TurkishSpeech.normalize('%12,5 ve 2,05 kg'),
      'yüzde on iki virgül beş ve iki virgül sıfır beş kilogram',
    );
  });
  test('invalid dates and times are not invented', () {
    expect(
      TurkishSpeech.normalize('31.02.2026 25:99 192.168.1.1 1:2'),
      '31.02.2026 25:99 192.168.1.1 1:2',
    );
  });
  test('markdown cleanup preserves inline values and table cells', () {
    final spoken = VoiceService.cleanForSpeech(
      '**Kalkış** `19:30`\n| Hat | Süre |\n| --- | --- |\n| 220 | 5 dk |',
    );
    expect(spoken, contains('saat on dokuz otuz'));
    expect(spoken, contains('beş dakika'));
    expect(spoken, isNot(contains(r'$1')));
    expect(spoken, isNot(contains('---')));
  });
}
