import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/local_command_engine.dart';
import 'package:jarvis_mobile/services/voice_commands.dart';

class _Host implements VoiceCommandHost {
  @override
  List<DeviceAppInfo> get installedApps => const [];
  @override
  Future<String> runDailyBriefing({bool speak = false}) async => '';
  @override
  Future<String> askAboutScreen(String question) async => '';
  @override
  Future<String> readNotifications() async => '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jarvis.assistant/device');
  final contacts = <List<String>>[];
  final calls = <String>[];
  final urls = <String>[];
  final volumes = <int>[];

  const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlChannel, (call) async {
      final a = call.arguments;
      if (call.method == 'launch' && a is Map) urls.add(a['url'].toString());
      return true;
    });
    contacts.clear();
    calls.clear();
    urls.clear();
    volumes.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'searchContacts':
          final q = LocalCommandEngine.foldTr(call.arguments['query'] as String);
          return [
            for (final c in contacts)
              if (LocalCommandEngine.foldTr(c[0]).contains(q))
                {'name': c[0], 'phone': c[1]},
          ];
        case 'contactsPermission':
          return 'granted';
        case 'callNumber':
          calls.add(call.arguments['number'] as String);
          return 'CALLING';
        case 'getVolumeState':
          return {'mediaPct': 50};
        case 'setVolumeLevel':
          volumes.add(call.arguments['percent'] as int);
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlChannel, null);
  });

  Future<LocalCommandOutcome?> run(String s) =>
      VoiceCommands.tryHandle(s, _Host());

  test('arama olmayan "ara" cümleleri aranmaz', () async {
    for (final s in [
      "Vikipedi'de mitokondri ara",
      'İnternetten pizza tarifi ara',
      "Spotify'da Tarkan ara",
      "Tarkan'ın son şarkısını ara",
    ]) {
      expect(await run(s), isNull, reason: s);
    }
    expect(calls, isEmpty);
  });

  test("Ali'yi ara -> Ali Veli (Halil Yiğit değil)", () async {
    contacts
      ..add(['Halil Yiğit', '05001112233'])
      ..add(['Ali Veli', '05325550000']);
    final r = await run("Ali'yi ara");
    expect(r?.handled, isTrue);
    expect(calls, ['05325550000']);
  });

  test('acil numara ve telefon numarası aranır', () async {
    await run("112'yi ara");
    expect(calls, ['112']);
    calls.clear();
    await run("0532 123 45 67'yi ara");
    expect(calls, ['05321234567']);
    calls.clear();
    await run('polisi ara');
    expect(calls, ['155']);
  });

  test('grup alıcısı LLM e bırakılır, en yakın zamanda yol tarifi olmaz',
      () async {
    expect(await run('Velilere mesaj yaz: yarın gezi var'), isNull);
    expect(await run('en yakın zamanda görüşelim'), isNull);
    expect(urls, isEmpty);
  });

  test('en yakın eczane nerede haritaya gider', () async {
    final r = await run('en yakın eczane nerede');
    expect(r?.handled, isTrue);
    expect(urls.single, contains('eczane'));
  });

  test('sesi kısar mısın -> ses azalır', () async {
    final r = await run('sesi kısar mısın');
    expect(r?.handled, isTrue);
    expect(volumes, [30]);
  });

  test("144'ün karekökü", () async {
    final r = await run("144'ün karekökü");
    expect(r?.reply, contains('12'));
  });

  test('SMS gövdesi büyük harfi korur', () async {
    contacts.add(['Ali Veli', '05325550000']);
    final r = await run("Ali'ye mesaj yaz: Yarın İstanbul'a geliyorum 2 kişiyiz");
    expect(r?.handled, isTrue);
    expect(
      Uri.decodeComponent(urls.single),
      contains("Yarın İstanbul'a geliyorum 2 kişiyiz"),
    );
  });

  test('Emre ara -> Emrah ile belirsiz kalmaz, tam ad kazanır', () async {
    contacts
      ..add(['Emrah', '05001110000'])
      ..add(['Emre', '05002220000']);
    await run('Emre ara');
    expect(calls, ['05002220000']);
  });

  test('Ayşe ara -> Ayşegül ile belirsiz kalmaz', () async {
    contacts
      ..add(['Ayşegül', '05001110000'])
      ..add(['Ayşe', '05002220000']);
    await run('Ayşe ara');
    expect(calls, ['05002220000']);
  });

  test('-de/-da ile biten gerçek ilk adlar aranır', () async {
    contacts
      ..add(['Hande Yıldız', '05001'])
      ..add(['Seda Kaya', '05002'])
      ..add(['Sevda Nur', '05003'])
      ..add(['Ayten Hanım', '05004']);
    for (final s in [
      'Hande Yıldız ara',
      'Seda Kaya ara',
      'Sevda Nur ara',
      'Ayten Hanım ara',
    ]) {
      final r = await run(s);
      expect(r?.handled, isTrue, reason: s);
    }
    expect(calls, ['05001', '05002', '05003', '05004']);
  });
}
