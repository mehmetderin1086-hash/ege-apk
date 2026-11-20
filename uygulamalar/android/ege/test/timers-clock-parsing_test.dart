import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/local_command_engine.dart';
import 'package:jarvis_mobile/services/voice_commands.dart';

class _TimerDelegate implements MobileStateDelegate {
  final List<JarvisTimer> _timers = [];
  int cancelLatestCalls = 0;

  @override
  List<JarvisTimer> get timers => List.unmodifiable(_timers);

  @override
  Future<JarvisTimer> addTimer(int seconds, String label) async {
    final t = JarvisTimer(
      id: 't${_timers.length}',
      label: label,
      durationSec: seconds,
      createdAtEpoch: 1000 + _timers.length,
      fireAtEpoch: 1000 + _timers.length + seconds,
    );
    _timers.add(t);
    return t;
  }

  @override
  Future<int> cancelTimers({bool all = false, bool earliest = false}) async {
    if (_timers.isEmpty) return 0;
    if (all) {
      final n = _timers.length;
      _timers.clear();
      return n;
    }
    if (earliest) {
      _timers.sort((a, b) => a.fireAtEpoch.compareTo(b.fireAtEpoch));
      _timers.removeAt(0);
      return 1;
    }
    cancelLatestCalls++;
    JarvisTimer? latest;
    for (final t in _timers) {
      if (!t.fired &&
          (latest == null || t.createdAtEpoch > latest.createdAtEpoch)) {
        latest = t;
      }
    }
    if (latest == null) return 0;
    _timers.remove(latest);
    return 1;
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.jarvis.assistant/device'),
          (call) async => true,
        );
  });

  group('TrNumbers saat/ondalık', () {
    test('saat yedi otuzda', () {
      expect(TrNumbers.normalize('saat yedi otuzda'), contains('7:30'));
      expect(TrNumbers.normalize('saat yedi otuzda'), "saat 7:30'da");
      expect(TrNumbers.normalize('sekiz kırk beşte alarm kur'),
          "8:45'te alarm kur");
    });
    test('geçersiz birleşim toplanmaz', () {
      expect(TrNumbers.normalize('yedi otuz'), '7 30');
      expect(TrNumbers.normalize('yirmi beş'), '25');
      expect(TrNumbers.normalize('beş beş'), '5 5');
    });
    test('buçuk: süre/işlem ondalık, saat bağlamı H:30', () {
      expect(TrNumbers.normalize('bir buçuk saat sonra'), '1,5 saat sonra');
      expect(TrNumbers.normalize('iki buçuk çarpı dört'), '2,5 çarpı 4');
      expect(TrNumbers.normalize('saat yedi buçukta'), "saat 7:30'ta");
      expect(TrNumbers.normalize('yedi buçukta uyandır'), "7:30'ta uyandır");
    });
  });

  group('TrClock', () {
    test('kala, buçuk, gece 12', () {
      expect(TrClock.parse("8'e çeyrek kala"), (hour: 7, minute: 45));
      expect(TrClock.parse("7'ye 10 kala"), (hour: 6, minute: 50));
      expect(TrClock.parse('7 buçukta'), (hour: 7, minute: 30));
      expect(TrClock.parse('gece 12de'), (hour: 0, minute: 0));
      expect(TrClock.parse("gece 12'de"), (hour: 0, minute: 0));
      expect(TrClock.parse("gece 1'de"), (hour: 1, minute: 0));
      expect(
        TrClock.parse(TrNumbers.normalize('sekize çeyrek kala')),
        (hour: 7, minute: 45),
      );
      expect(
        TrClock.parse(TrNumbers.normalize('yediye on kala')),
        (hour: 6, minute: 50),
      );
    });
    test('tekrar günleri', () {
      expect(TrClock.recurrenceDays('her gün 7de alarm kur'),
          [1, 2, 3, 4, 5, 6, 7]);
      expect(TrClock.recurrenceDays('hafta içi 7de'), [2, 3, 4, 5, 6]);
      expect(TrClock.recurrenceDays('hafta sonu 9da'), [7, 1]);
      expect(TrClock.recurrenceDays('her pazartesi 8de'), [2]);
      expect(TrClock.recurrenceDays('her pazar 8de'), [1]);
      expect(TrClock.recurrenceDays('yarın 8de'), isEmpty);
    });
  });

  group('TrCalc.format', () {
    test('kayan nokta artığı', () {
      final v = TrCalc.evaluate('4,35 çarpı 100');
      expect(TrCalc.format(v!), '435');
      expect(TrCalc.format(0.1 + 0.2), '0,3');
      expect(TrCalc.format(2.5), '2,5');
    });
  });

  group('LCE zamanlayıcı', () {
    test('bir buçuk saat sonra hatırlat → 5400 sn', () async {
      final d = _TimerDelegate();
      final o = await LocalCommandEngine.tryHandle(
          'bir buçuk saat sonra hatırlat', d);
      expect(o.handled, isTrue);
      expect(d.timers.single.durationSec, 5400);
    });
    test('1,5 saat sonra hatırlat → 5400 sn', () async {
      final d = _TimerDelegate();
      await LocalCommandEngine.tryHandle('1,5 saat sonra hatırlat', d);
      expect(d.timers.single.durationSec, 5400);
    });
    test('yarım saat sonra hatırlat → 1800 sn', () async {
      final d = _TimerDelegate();
      await LocalCommandEngine.tryHandle('yarım saat sonra hatırlat', d);
      expect(d.timers.single.durationSec, 1800);
    });
    test('5 dakika sonra kahve hatırlat çalışır', () async {
      final d = _TimerDelegate();
      await LocalCommandEngine.tryHandle('5 dakika sonra kahve hatırlat', d);
      expect(d.timers.single.durationSec, 300);
    });
    test('ders planı cümlesi sayaç kurmaz', () async {
      final d = _TimerDelegate();
      await LocalCommandEngine.tryHandle(
        '40 dakikalık ders planı hazırla ve sonra bana hatırlat',
        d,
      );
      expect(d.timers, isEmpty);
    });
    test('alarmı ertele sayaç kurmaz', () async {
      final d = _TimerDelegate();
      final o =
          await LocalCommandEngine.tryHandle('Alarmı 10 dakika ertele', d);
      expect(d.timers, isEmpty);
      expect(o.handled, isTrue);
      expect(o.reply, contains('erteleme'));
    });
    test('Zamanlayıcıyı iptal et en sonuncuyu siler', () async {
      final d = _TimerDelegate();
      await d.addTimer(60, 'ilk');
      await d.addTimer(120, 'ikinci');
      final o = await LocalCommandEngine.tryHandle('Zamanlayıcıyı iptal et', d);
      expect(o.handled, isTrue);
      expect(d.cancelLatestCalls, 1);
      expect(d.timers.map((t) => t.label), ['ilk']);
    });
  });
}
