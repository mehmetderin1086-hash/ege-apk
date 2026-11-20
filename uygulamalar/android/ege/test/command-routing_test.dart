import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/services/local_command_engine.dart';
import 'package:jarvis_mobile/services/wake_strip.dart';
import 'package:jarvis_mobile/services/youtube_service.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stripWake', () {
    test('uyandırma kelimesi ve dolgular atılır, büyük/küçük harf korunur', () {
      expect(stripWake('Jarvis. Feneri aç.'), 'Feneri aç.');
      expect(stripWake('Hey Ege! sesi kıs'), 'sesi kıs');
      expect(stripWake('Ege, hadi şimdi müziği aç'), 'müziği aç');
      expect(stripWake('Feneri aç, Ege'), 'Feneri aç');
      expect(stripWake('Egemen aradı'), 'Egemen aradı');
      expect(stripWake('bir dakika sonra hatırlat'), 'bir dakika sonra hatırlat');
      expect(stripWake('Ege, bir saat sonra alarm kur'), 'bir saat sonra alarm kur');
      expect(stripWake('bir dakikalık sayaç kur'), 'bir dakikalık sayaç kur');
      expect(stripWake('bi saniye sonra uyar'), 'bi saniye sonra uyar');
      expect(stripWake('bir alarm kur'), 'alarm kur');
    });
  });

  group('denetleyici', () {
    late JarvisController c;
    final calls = <String>[];
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.jarvis.assistant/device'),
            (call) async {
              calls.add('${call.method}:${call.arguments}');
              return true;
            },
          );
      c = JarvisController();
      await c.init(loadPlatformTelemetry: false);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.jarvis.assistant/device'),
            null,
          );
      c.dispose();
    });

    test('not, özgün harf büyüklüğüyle saklanır', () async {
      final out = await LocalCommandEngine.tryHandle(
        'not ekle: yarın ahmet bey\'le saat 3\'te toplantı',
        c,
        original: 'Not ekle: Yarın Ahmet Bey\'le saat üçte toplantı',
      );
      expect(out.handled, isTrue);
      expect(out.reply, contains('Yarın Ahmet Bey\'le saat üçte toplantı'));
    });

    test('Feneri yak -> flaş açık', () async {
      final out = await LocalCommandEngine.tryHandle('feneri yak', c);
      expect(out.handled, isTrue);
      expect(calls.any((x) => x.startsWith('setFlashlight') && x.contains('true')),
          isTrue);
      calls.clear();
      await LocalCommandEngine.tryHandle('fener söndür', c);
      expect(calls.any((x) => x.startsWith('setFlashlight') && x.contains('false')),
          isTrue);
    });

    test('"devam et" müzik yokken LLM\'e kalır', () async {
      final out = await LocalCommandEngine.tryHandle('devam et', c);
      expect(out.handled, isFalse);
    });

    test('Onu unut hiçbir şey silmez', () async {
      await c.setMemoryText('Kedim Pamuk\nAraba mavi');
      final out = await c.tryExtendedCommand('Onu unut');
      expect(out!.reply, 'Neyi unutmamı istersin?');
      expect(c.memoryItems.length, 2);
    });

    test('unut: birden çok eşleşmede hiçbir şey silinmez', () async {
      await c.setMemoryText('Kedim Pamuk\nPamuk mavi araba');
      final out = await c.tryExtendedCommand('Pamuk unut');
      expect(out!.reply, contains('hiçbirini silmedim'));
      expect(c.memoryItems.length, 2);
    });

    test('unut: tek tam sözcük eşleşmesi silinir', () async {
      await c.setMemoryText('Kedim Pamuk\nAraba mavi');
      final out = await c.tryExtendedCommand('Pamuk unut');
      expect(out!.reply, contains('silindi'));
      expect(c.memoryItems, ['Araba mavi']);
    });

    test('Müziği oynat YouTube araması yerine sürdürür', () async {
      c.musicNow = const YtVideo(id: 'abc', title: 'Şarkı');
      final out = await c.tryExtendedCommand('Müziği oynat');
      expect(out!.reply, contains('devam'));
      expect(calls.any((x) => x.startsWith('streamResume')), isTrue);
    });

    test('görüntülü arama olumsuz emir sayılmaz, "müziği açma" sayılır', () async {
      final a = await c.tryExtendedCommand('görüntülü arama');
      expect(a?.reply, isNot('Tamam, işlem yapılmadı.'));
      final b = await c.tryExtendedCommand('müzik çalma');
      expect(b?.reply, isNot('Tamam, işlem yapılmadı.'));
      final d = await c.tryExtendedCommand('ekranı açma');
      expect(d!.reply, 'Tamam, işlem yapılmadı.');
    });

    test('panorama çek panoyu eklemez', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': 'gizli metin'};
        return null;
      });
      expect(await c.debugClipboardContext('panorama çek'), '');
      expect(await c.debugClipboardContext('panodaki metni oku'),
          contains('gizli metin'));
    });
  });
}
