class PhoneCommand {
  const PhoneCommand(this.method, this.args, [this.help = '']);
  final String? method;
  final Map<String, dynamic> args;
  final String help;

  static PhoneCommand? parse(String input) {
    final text = input.trim().replaceFirst(RegExp(r'[.!?]+$'), '').trimRight();
    final lower = text.toLowerCase();
    if (lower == 'iptal' || lower == 'vazgeç') {
      return const PhoneCommand(null, {}, 'İşlem iptal edildi.');
    }
    if (lower == 'ara' || lower == 'arama başlat') {
      return const PhoneCommand(null, {}, 'Aramak için numarayı söyleyin.');
    }
    if (lower == 'mesaj gönder' || lower == 'mesaj at') {
      return const PhoneCommand(
        null,
        {},
        'Numara ve mesajı söyleyin. Örnek: 05551234567 mesaj gönder: Yoldayım.',
      );
    }

    if (lower == 'uygulama kontrolünü ayarla') {
      return const PhoneCommand('openAppControlSettings', {});
    }
    final navigation = switch (lower) {
      'geri dön' || 'geri git' => 'back',
      'aşağı kaydır' => 'down',
      'yukarı kaydır' => 'up',
      'sağa kaydır' => 'right',
      'sola kaydır' => 'left',
      _ => null,
    };
    if (navigation != null) {
      return PhoneCommand('controlApp', {'action': navigation});
    }
    final click = RegExp(r'^(.+?)\s+(?:düğmesine\s+)?(?:dokun|tıkla)$')
        .firstMatch(lower);
    if (click != null) {
      return PhoneCommand('controlApp', {
        'action': 'click',
        'target': click.group(1)!.trim(),
      });
    }
    final write = RegExp(
      r'^ekrana\s+(.+?)\s+yaz$',
      caseSensitive: false,
    ).firstMatch(input.trim());
    if (write != null) {
      return PhoneCommand('controlApp', {
        'action': 'write',
        'target': write.group(1)!,
      });
    }
    final explicitApp = RegExp(
      r"^(?:aç\s+(.+)|(.+?)\s+uygulamas[ıi]n[ıi]\s+aç|((?:you\s*tube|yutub))(?:['’]?[uü])?\s+aç)$",
    ).firstMatch(lower);
    if (explicitApp != null) {
      final target =
          explicitApp.group(1) ?? explicitApp.group(2) ?? explicitApp.group(3)!;
      return PhoneCommand('openAppOrUrl', {'target': target.trim()});
    }
    final appSearch = RegExp(
      r"^(youtube|spotify|chrome)(?:['’]?(?:da|de|ta|te))?\s+(.+?)\s+(ara|bul|çal|aç)$",
      caseSensitive: false,
    ).firstMatch(text);
    if (appSearch != null) {
      return PhoneCommand('openAppSearch', {
        'app': appSearch.group(1)!.toLowerCase(),
        'query': appSearch.group(2)!,
        'play': appSearch.group(3)!.toLowerCase() == 'çal',
      });
    }
    final whatsapp = RegExp(
      r"^whatsapp(?:['’]?(?:tan|ta|dan|da))?\s+([+\d ()-]+)\s+(?:mesaj\s+)?(?:gönder|yaz|at)\s*:?\s*(.+)$",
      caseSensitive: false,
    ).firstMatch(text);
    if (whatsapp != null) {
      final phone = whatsapp.group(1)!.replaceAll(RegExp(r'[\s()-]'), '');
      if (!RegExp(r'^\+?[1-9]\d{8,14}$').hasMatch(phone))
        return const PhoneCommand(
          null,
          {},
          'WhatsApp için ülke koduyla numara gerekli; örneğin +905551234567.',
        );
      return PhoneCommand('openCommunication', {
        'type': 'whatsapp',
        'phone': phone,
        'message': whatsapp.group(2)!,
      });
    }
    if (lower.startsWith('telegram') &&
        (lower.contains('ara') || lower.contains('bul'))) {
      final user = RegExp(r'@([a-zA-Z0-9_]{5,32})').firstMatch(text);
      if (lower.contains('sohbet') || lower.contains('mesaj')) {
        if (user == null)
          return const PhoneCommand(
            null,
            {},
            'Sohbeti açmak için Telegram kullanıcı adını belirtin: Telegram @kullanici sohbetinde mesaj ara. Sohbet içi arama Telegram menüsünde yapılır.',
          );
        return PhoneCommand('openAppSearch', {
          'app': 'telegram',
          'query': user.group(1),
          'mode': 'chat',
          'play': false,
        });
      }
      return PhoneCommand('openAppSearch', {
        'app': 'telegram',
        'query': '',
        'mode': lower.contains('kişi') || lower.contains('rehber')
            ? 'contacts'
            : 'global',
        'play': false,
      });
    }
    final dial = RegExp(r'^(?:ara\s+(.+)|(.+?)\s+(?:numarasını\s+)?ara)$')
        .firstMatch(lower);
    if (dial != null) {
      final target = (dial.group(1) ?? dial.group(2)!).replaceAll(
        RegExp(r'[\s()-]'),
        '',
      );
      if (!RegExp(r'^\+?\d{7,15}$').hasMatch(target)) {
        return const PhoneCommand(
          null,
          {},
          'Aramak için numarayı söyleyin. Örnek: 05551234567 ara. Aramayı telefon ekranında onaylayacaksınız.',
        );
      }
      return PhoneCommand('openCommunication', {
        'type': 'dial',
        'phone': target,
      });
    }
    final sms = RegExp(
      r'^(.+?)\s+(?:numarasına\s+)?(?:mesaj|sms)\s+(?:at|gönder|yaz)\s*[:：]?\s*(.*)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (sms != null) {
      final phone = sms.group(1)!.replaceAll(RegExp(r'[\s()-]'), '');
      final body = sms.group(2)!.trim();
      if (!RegExp(r'^\+?\d{7,15}$').hasMatch(phone) || body.isEmpty) {
        return const PhoneCommand(
          null,
          {},
          'Numara ve mesaj gerekli. Örnek: 05551234567 mesaj gönder: Yoldayım. Göndermeden önce mesaj ekranında kontrol edin.',
        );
      }
      return PhoneCommand('openCommunication', {
        'type': 'sms',
        'phone': phone,
        'message': body,
      });
    }
    if (lower.contains('alarm') &&
        (lower.contains('kur') || lower.contains('ayarla'))) {
      final time = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(lower);
      if (time == null) {
        return const PhoneCommand(
          null,
          {},
          'Alarm saati gerekli. Örnek: 08:30 alarm kur.',
        );
      }
      final hour = int.parse(time.group(1)!);
      final minute = int.parse(time.group(2)!);
      if (hour > 23 || minute > 59) {
        return const PhoneCommand(
          null,
          {},
          'Geçerli bir saat söyleyin; örneğin 08:30.',
        );
      }
      return PhoneCommand('setAlarmOrTimer', {
        'mode': 'alarm',
        'hour': hour,
        'minute': minute,
        'title': 'Asistan Alarmı',
      });
    }
    final settings = RegExp(
      r'^(wifi|wi-fi|bluetooth|konum|ekran|parlaklık|pil|ses)(?:\s+ayarlarını)?\s+(aç|kapat|değiştir)$',
    ).firstMatch(lower);
    if (settings != null) {
      return PhoneCommand('deviceAction', {
        'action': 'ayar_ac',
        'target': settings.group(1),
      });
    }
    final app = RegExp(r'^(.+?)(?:\s+uygulamasını)?\s+aç$').firstMatch(lower);
    if (app != null &&
        !lower.contains('ayar') &&
        !lower.contains('fener') &&
        !lower.contains('ışık')) {
      return PhoneCommand('openAppOrUrl', {'target': app.group(1)!.trim()});
    }
    return null;
  }
}
