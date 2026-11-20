import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/local_command_engine.dart';
import 'package:jarvis_mobile/services/voice_commands.dart';

void main() {
  group('TrNumbers', () {
    test('tek ve bileşik sayılar, ekler', () {
      expect(TrNumbers.normalize('on dakikalık zamanlayıcı kur'), '10 dakikalık zamanlayıcı kur');
      expect(TrNumbers.normalize('beş dakika sonra çayı hatırlat'), '5 dakika sonra çayı hatırlat');
      expect(TrNumbers.normalize('yirmi beşe kadar say'), "25'e kadar say");
      expect(TrNumbers.normalize('iki yüz kırk beş çarpı on sekiz'), '245 çarpı 18');
      expect(TrNumbers.normalize('saat dörde alarm'), "saat 4'e alarm");
    });

    test('buçuk ve yüzde', () {
      expect(TrNumbers.normalize('yedi buçukta uyandır'), "7:30'ta uyandır");
      expect(TrNumbers.normalize('yedi buçuğa alarm kur'), "7:30'a alarm kur");
      expect(TrNumbers.normalize('sesi yüzde elliye ayarla'), "sesi %50'ye ayarla");
      expect(TrNumbers.normalize('parlaklığı yüzde otuz yap'), 'parlaklığı %30 yap');
    });

    test('"bir" tanımlığı ve "altında" gibi sözcükler sayı sayılmaz', () {
      expect(TrNumbers.normalize('bir şarkı çal'), 'bir şarkı çal');
      expect(TrNumbers.normalize('bir dakika bekle'), '1 dakika bekle');
      expect(TrNumbers.normalize('masanın altında'), 'masanın altında');
      expect(TrNumbers.normalize('yüzde'), 'yüzde');
    });
  });

  group('TrClock', () {
    test('saat biçimleri', () {
      expect(TrClock.parse("yarın sabah 7'de beni uyandır"), (hour: 7, minute: 0));
      expect(TrClock.parse("akşam 8'de alarm kur"), (hour: 20, minute: 0));
      expect(TrClock.parse("7:30'a alarm kur"), (hour: 7, minute: 30));
      expect(TrClock.parse("sabah 7.30'da uyandır"), (hour: 7, minute: 30));
      expect(TrClock.parse("7'yi çeyrek geçe uyandır"), (hour: 7, minute: 15));
      expect(TrClock.parse("8'e çeyrek var uyandır"), (hour: 7, minute: 45));
      expect(TrClock.parse('alarm kur saat 6'), (hour: 6, minute: 0));
      expect(TrClock.parse("gece 11'de alarm"), (hour: 23, minute: 0));
      expect(TrClock.parse("öğlen 1'de alarm"), (hour: 13, minute: 0));
      expect(TrClock.parse('beni uyandır'), isNull);
    });
  });

  group('TrCalc', () {
    test('dört işlem, karekök, kare', () {
      expect(TrCalc.evaluate('hesapla 245 çarpı 18'), 4410);
      expect(TrCalc.evaluate('100 bölü 4 artı 3'), 28);
      expect(TrCalc.evaluate("144'ün karekökü"), 12);
      expect(TrCalc.evaluate("12'nin karesi"), 144);
      expect(TrCalc.evaluate('2 üzeri 10'), 1024);
      expect(TrCalc.evaluate('merhaba'), isNull);
      expect(TrCalc.format(4410), '4.410');
      expect(TrCalc.format(2.5), '2,5');
    });
  });

  group('VoiceCommands', () {
    test('Whisper çıktısını komut biçimine getirir', () {
      expect(VoiceCommands.prepare('Jarvis, saat yedi buçuğa alarm kur.'), "saat 7:30'a alarm kur");
      expect(VoiceCommands.prepare('El fenerini aç.'), 'el fenerini aç');
      expect(VoiceCommands.prepare('"Sesi kıs!"'), 'sesi kıs');
    });

    test('kişi adı adayları iyelik ve hal eklerini soyar', () {
      expect(VoiceCommands.nameCandidates('annemi'), containsAll(['annemi', 'annem', 'anne']));
      expect(VoiceCommands.nameCandidates("ahmet'i"), contains('ahmet'));
    });

    test('noktalama komut eşleşmesini bozmaz', () {
      expect(LocalCommandEngine.stripEndPunct('El fenerini aç.'), 'El fenerini aç');
      expect(LocalCommandEngine.stripEndPunct('Not al: süt al.'), 'Not al: süt al');
      expect(LocalCommandEngine.stripEndPunct('Saat kaç?'), 'Saat kaç');
    });

    test('yerel komutlar internetsiz yanıtlar', () async {
      final host = _Host();
      final saat = await VoiceCommands.tryHandle('Saat kaç?', host);
      expect(saat?.handled, isTrue);
      expect(saat!.reply, startsWith('Saat '));
      final hesap = await VoiceCommands.tryHandle('Hesapla iki yüz kırk beş çarpı on sekiz.', host);
      expect(hesap?.reply, 'Sonuç 4.410.');
      final ozet = await VoiceCommands.tryHandle('Günaydın.', host);
      expect(ozet?.reply, 'özet');
      expect(await VoiceCommands.tryHandle('Bana bir fıkra anlat.', host), isNull);
    });
  });
}

class _Host implements VoiceCommandHost {
  @override
  List<DeviceAppInfo> get installedApps => const [];

  @override
  Future<String> askAboutScreen(String question) async => 'ekran';

  @override
  Future<String> readNotifications() async => 'bildirim';

  @override
  Future<String> runDailyBriefing({bool speak = false}) async => 'özet';
}
