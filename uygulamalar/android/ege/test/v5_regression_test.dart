import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/services/local_whisper.dart';
import 'package:jarvis_mobile/services/realtime_live_service.dart';
import 'package:jarvis_mobile/services/voice_service.dart';

void main() {
  group('5.0 düzeltmeleri', () {
    test('gerçek komutlar prompt yankısı sayılıp silinmez', () {
      for (final c in [
        "YouTube'da şarkı çal.",
        'JARVIS, annemi ara.',
        'Google’da ara.',
        'JARVIS hava durumu.',
      ]) {
        expect(LocalWhisper.cleanTranscript(c), isNotEmpty, reason: c);
      }
      expect(LocalWhisper.cleanTranscript('JARVIS, YouTube, WhatsApp, Google.'), '');
    });

    test('splitForTts saat ve ondalık sayıları bölmez', () {
      expect(VoiceService.splitForTts('Alarm saat 08:00 için kuruldu.'),
          ['Alarm saat 08:00 için kuruldu.']);
      expect(VoiceService.splitForTts('Dolar 34.52 lira oldu.').join(' '), contains('34.52'));
      expect(VoiceService.splitForTts('Bir. İki.').length, 1);
    });

    test('commandMatchesTranscript büyük İ ile eşleşir', () {
      expect(
          RealtimeLiveSession.commandMatchesTranscript(
              "istanbul'a yol tarifi", "İstanbul'a yol tarifi."),
          isTrue);
    });
  });
}
