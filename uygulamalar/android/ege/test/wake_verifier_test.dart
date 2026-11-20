import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jarvis_mobile/services/wake_verifier.dart';

void main() {
  group('WakeVerifier.matches', () {
    for (final t in ['Asistan', 'ASISTAN!', 'Asistan, saat kaç?', 'assistant']) {
      test('kabul: $t', () => expect(WakeVerifier.matches(t), isTrue));
    }
    // Yerel algılayıcının yanlış alarm verdiği gerçek olumsuz cümleler.
    for (final t in [
      'Asistanlık', 'Hey Ege', 'Sembol', 'Hey Engin, maç kaçta?', 'Hey yavrum, gel buraya.', 'Hediye paketini aç.',
      'Heyecanlı bir maç izledik.', 'Heykel çok güzel olmuş.',
      'Hey, Emre nerede?', 'Hey abi, nasılsın?', 'Hey Elif, kitabı getirdin mi?',
      'Ege denizi bu yaz çok sıcaktı.', 'şurada çok tatlı pembe', 'Burası gelmiyor', 'Hediye', 'Hey Google, müzik çal.', 'H diyalog', '',
    ]) {
      test('ret: $t', () => expect(WakeVerifier.matches(t), isFalse));
    }
  });

  test('bulut hatasında ve anahtar yokken yerel karar korunur', () async {
    final pcm = Uint8List(32000);
    final noKey = await WakeVerifier.verify(pcm, apiKey: '');
    expect(noKey.accepted, isTrue);
    final failing = await WakeVerifier.verify(
      pcm,
      apiKey: 'k',
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    expect(failing.accepted, isTrue);
  }, skip: 'path_provider eklentisi test ortamında yok');

  test('WAV başlığı 16 kHz mono PCM16', () {
    final wav = WakeVerifier.wavFromPcm16(Uint8List(3200));
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
    final bd = ByteData.sublistView(wav);
    expect(bd.getUint32(24, Endian.little), 16000);
    expect(bd.getUint16(22, Endian.little), 1);
    expect(wav.length, 44 + 3200);
  });
}
