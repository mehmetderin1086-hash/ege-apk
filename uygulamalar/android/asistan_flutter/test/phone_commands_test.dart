import 'package:flutter_test/flutter_test.dart';
import 'package:asistan_flutter/services/phone_commands.dart';

void main() {
  test('App commands preserve queries and distinguish playback request', () {
    expect(
      PhoneCommand.parse("YouTube'da Türkçe müzik ara")!.args['query'],
      'Türkçe müzik',
    );
    expect(
      PhoneCommand.parse("Spotify'da Barış Manço çal")!.args['play'],
      true,
    );
    expect(
      PhoneCommand.parse('Chrome https://example.com aç')!.args['app'],
      'chrome',
    );
    expect(
      PhoneCommand.parse('WhatsApp +905551234567 mesaj gönder: Merhaba')!
          .args['type'],
      'whatsapp',
    );
    expect(PhoneCommand.parse("Telegram kanal ara")!.args['app'], 'telegram');
  });

  test('Call opens dialer with explicit number', () {
    final c = PhoneCommand.parse('05551234567 ara')!;
    expect(c.method, 'openCommunication');
    expect(c.args['type'], 'dial');
    expect(c.args['phone'], '05551234567');
  });
  test('SMS preserves content and requires recipient', () {
    final c = PhoneCommand.parse('05551234567 mesaj gönder: Yoldayım')!;
    expect(c.args['message'], 'Yoldayım');
    expect(c.args['type'], 'sms');
    expect(PhoneCommand.parse('Ali mesaj gönder: Merhaba')!.method, isNull);
  });
  test('Alarm requires valid explicit time', () {
    expect(PhoneCommand.parse('alarm kur')!.method, isNull);
    expect(PhoneCommand.parse('25:80 alarm kur')!.method, isNull);
    expect(PhoneCommand.parse('08:30 alarm kur')!.args['minute'], 30);
  });
  test('Settings route to panel and apps route to launcher', () {
    expect(PhoneCommand.parse('bluetooth kapat')!.args['action'], 'ayar_ac');
    expect(PhoneCommand.parse('YouTube aç')!.args['target'], 'youtube');
    expect(PhoneCommand.parse('iptal')!.method, isNull);
    expect(PhoneCommand.parse('Merhaba'), isNull);
  });

  test('Spoken app names and screen actions route to local commands', () {
    for (final command in ['YouTube aç.', 'Aç YouTube', "YouTube’u aç"]) {
      final parsed = PhoneCommand.parse(command)!;
      expect(parsed.method, 'openAppOrUrl');
      expect(parsed.args['target'], 'youtube');
    }
    expect(PhoneCommand.parse('Ritim uygulamasını aç')!.args['target'], 'ritim');
    expect(PhoneCommand.parse('Aşağı kaydır')!.args['action'], 'down');
    expect(PhoneCommand.parse('Geri dön')!.args['action'], 'back');
    expect(PhoneCommand.parse('Abonelikler düğmesine dokun')!.args, {
      'action': 'click',
      'target': 'abonelikler',
    });
    expect(PhoneCommand.parse('Ekrana İzmir! yaz')!.args['target'], 'İzmir!');
  });
}
