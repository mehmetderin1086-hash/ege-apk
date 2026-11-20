import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/local_command_engine.dart';
import 'package:jarvis_mobile/services/work_hub.dart';

class _FakeDelegate implements MobileStateDelegate {
  _FakeDelegate(this.apps);
  final List<DeviceAppInfo> apps;
  @override
  List<DeviceAppInfo> get installedApps => apps;
  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'unexpected ${invocation.memberName}',
  );
}

class _ResearchDelegate extends _FakeDelegate {
  _ResearchDelegate() : super([]);
  final queries = <String>[];
  @override
  Future<String> startDeepResearch(String question) async {
    queries.add(question);
    return 'ok';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.jarvis.assistant/device'),
          (call) async {
            calls.add('${call.method}:${call.arguments}');
            return true;
          },
        );
  });

  group('derin araştırma', () {
    test('yap sözcük sınırı: yapay zeka sorguyu bozmaz', () async {
      final d = _ResearchDelegate();
      await LocalCommandEngine.tryHandle('araştırma yap: yapay zeka hakkında', d);
      expect(d.queries, ['yapay zeka hakkında']);
      for (final t in ['araştır yapay zeka', 'araştırma yapay zeka hakkında']) {
        final d2 = _ResearchDelegate();
        try {
          await LocalCommandEngine.tryHandle(t, d2);
        } catch (_) {}
        expect(d2.queries.any((q) => q.startsWith('ay')), isFalse, reason: t);
      }
    });
  });

  group('haber', () {
    test('Ne haber? ve Anneme haber ver haber araması değildir', () async {
      for (final t in ['Ne haber?', 'Anneme haber ver.']) {
        final o = await LocalCommandEngine.tryHandle(t, _FakeDelegate([]));
        final r = o.reply;
        expect(r.contains('Haberleri'), isFalse, reason: t);
        expect(r.contains('Haberler alınamadı'), isFalse, reason: t);
      }
    });
  });

  group('hava şehri', () {
    test('Niğde / Hollanda korunur', () {
      expect(LocalCommandEngine.weatherCity("niğde'de hava nasıl"), 'niğde');
      expect(LocalCommandEngine.weatherCity('niğde hava nasıl'), 'niğde');
      expect(LocalCommandEngine.weatherCity('hollanda hava'), 'hollanda');
      expect(LocalCommandEngine.weatherCity('kanada hava durumu'), 'kanada');
      expect(LocalCommandEngine.weatherCity('istanbulda hava nasıl'), 'istanbul');
      expect(LocalCommandEngine.weatherCity("ankara'da hava nasıl"), 'ankara');
    });
    test('hafta sonu şehir değildir', () {
      expect(LocalCommandEngine.weatherCity('hafta sonu hava nasıl'), '');
    });
    test('çok sözcük kalırsa LLM', () {
      expect(
        LocalCommandEngine.weatherCity('bahçede çay içmek için hava nasıl'),
        isNull,
      );
    });
  });

  group('uygulama kaldır', () {
    test("Telegram'ı kaldır Telegram'ı bulur", () async {
      final apps = [
        const DeviceAppInfo(
          name: 'Telegram',
          packageName: 'org.telegram.messenger',
          versionName: '1',
          isSystem: false,
          firstInstallMs: 0,
          lastUpdateMs: 0,
        ),
      ];
      final o = await LocalCommandEngine.tryHandle(
        "Telegram'ı kaldır",
        _FakeDelegate(apps),
      );
      expect(o.handled, isTrue);
      expect(o.reply, contains('Telegram'));
      expect(calls.any((c) => c.startsWith('uninstallApp')), isTrue);
    });
  });

  group('structured action', () {
    test('set_alarm saat yoksa null alarm kurulmaz', () async {
      final r = await LocalCommandEngine.executeStructuredAction({
        'type': 'set_alarm',
      }, _FakeDelegate([]));
      expect(r, 'Alarm saatini anlayamadım.');
      expect(calls.any((c) => c.startsWith('setSystemAlarm')), isFalse);
    });
  });

  group('MOBILE_ACTION', () {
    test('tek ters eğik çizgi onarılır', () {
      final a = LocalCommandEngine.extractActions(
        '<MOBILE_ACTION>{"path":"C:\\Users\\x"}</MOBILE_ACTION>',
      );
      expect(a, hasLength(1));
      expect(a.first['path'], r'C:\Users\x');
    });
    test('bozuk JSON hata listesine düşer', () {
      final d = LocalCommandEngine.extractActionsDetailed(
        '<MOBILE_ACTION>{bozuk</MOBILE_ACTION>',
      );
      expect(d.actions, isEmpty);
      expect(LocalCommandEngine.lastActionParseErrors, isNotEmpty);
    });
    test('kapanmamış etiket silinir', () {
      expect(
        LocalCommandEngine.stripActionTags('Tamam.<MOBILE_ACTION>{"type":"x"'),
        'Tamam.',
      );
      expect(
        LocalCommandEngine.stripActionTags(
          'A<MOBILE_ACTION>{}</MOBILE_ACTION>B',
        ),
        'AB',
      );
    });
  });

  group('WorkHub.parseCommand', () {
    test('yapay zeka bölümü iş değildir', () {
      expect(
        WorkHub.parseCommand('PDF dosyasındaki yapay zeka bölümünü anlat'),
        isNull,
      );
      expect(WorkHub.parseCommand('pdf yazdığım yeri düzelt'), isNull);
      expect(WorkHub.parseCommand('word dosyası için ne yapmam lazım'), isNull);
    });
    test('şarkı indir ses işidir', () {
      final r = WorkHub.parseCommand('Tarkan Kuzu Kuzu şarkısını indir');
      expect(r?.kind, WorkKind.audio);
      expect(r?.task, 'Tarkan Kuzu Kuzu');
    });
    test('veri çıkar kazıma işidir', () {
      final r = WorkHub.parseCommand('https://example.com sayfasından veri çıkar');
      expect(r?.kind, WorkKind.scrape);
    });
    test('normal Word isteği çalışır', () {
      expect(
        WorkHub.parseCommand('haftalık rapor için word belgesi oluştur')?.kind,
        WorkKind.word,
      );
    });
  });
}
