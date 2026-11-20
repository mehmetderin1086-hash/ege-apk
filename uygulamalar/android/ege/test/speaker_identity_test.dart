import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/services/speaker_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jarvis.assistant/device');
  final a = List<double>.generate(256, (i) => i < 128 ? 1 : 0);
  final b = List<double>.generate(256, (i) => i >= 128 ? 1 : 0);
  test('a speaker must match two independent references, not just one', () {
    expect(SpeakerIdentity.matches(a, [a, a, b]), true);
    expect(SpeakerIdentity.matches(a, [a, b, b]), false);
    expect(SpeakerIdentity.matches(b, [a, a, a]), false);
    expect(SpeakerIdentity.matches(a, [a]), false);
    expect(
      SpeakerIdentity.matches(List.filled(256, double.nan), [a, a, a]),
      false,
    );
    expect(SpeakerIdentity.matches(List.filled(256, 0), [a, a, a]), false);
  });
  test(
    'enabled corrupt profile fails closed and requires enrollment',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => jsonEncode({
              'enabled': true,
              'model': SpeakerIdentity.modelName,
              'references': [],
            }),
          );
      final identity = SpeakerIdentity();
      await identity.load();
      expect(identity.enabled, true);
      expect(identity.enrolled, false);
      expect(await identity.acceptsWav(Uint8List(44)), false);
      await expectLater(identity.setEnabled(true), throwsStateError);
    },
  );
  test('enrollment rejects inconsistent speakers without writing', () async {
    var writes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'speakerProfileWrite') writes++;
          return true;
        });
    final identity = SpeakerIdentity();
    await expectLater(identity.enroll([a, a, b]), throwsStateError);
    expect(writes, 0);
    expect(identity.enrolled, false);
  });
  test('profile write failure cannot report enabled enrollment', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    final identity = SpeakerIdentity();
    await expectLater(identity.enroll([a, a, a]), throwsStateError);
    expect(identity.enabled, false);
    expect(identity.enrolled, false);
  });
  test('WAV parser rejects invalid size and unsupported sample format', () {
    expect(SpeakerIdentity.pcmFromWav(Uint8List(44)), isEmpty);
    final wav = Uint8List(46);
    wav.setRange(0, 4, ascii.encode('RIFF'));
    wav.setRange(12, 16, ascii.encode('fmt '));
    ByteData.sublistView(wav).setUint32(16, 10000, Endian.little);
    expect(SpeakerIdentity.pcmFromWav(wav), isEmpty);
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'wake calibration preserves general identity and filter choice',
    () async {
      Map? saved;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'speakerProfileRead')
              return jsonEncode({
                'enabled': false,
                'model': SpeakerIdentity.modelName,
                'references': [a, a, a],
              });
            if (call.method == 'speakerProfileWrite') {
              saved =
                  jsonDecode((call.arguments as Map)['json'] as String) as Map;
              return true;
            }
            return null;
          });
      final identity = SpeakerIdentity();
      await identity.enrollWake([b, b, b]);
      expect(identity.wakeEnrolled, true);
      expect(identity.enrolled, true);
      expect(identity.enabled, false);
      expect(saved!['references'], [a, a, a]);
      expect(saved!['wakeReferences'], [b, b, b]);
      final loaded = SpeakerIdentity();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => jsonEncode(saved));
      await loaded.load();
      expect(loaded.wakeEnrolled, true);
    },
  );
  test(
    'wake calibration rejects mixed examples and leaves stored profile intact',
    () async {
      var writes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'speakerProfileRead')
              return jsonEncode({
                'enabled': true,
                'model': SpeakerIdentity.modelName,
                'references': [a, a, a],
              });
            writes++;
            return true;
          });
      final identity = SpeakerIdentity();
      await expectLater(identity.enrollWake([a, a, b]), throwsStateError);
      expect(writes, 0);
    },
  );
  test(
    'wake preparation removes only outer silence and preserves internal pauses',
    () {
      final pcm = Float32List(48000);
      for (var i = 16000; i < 32000; i++) {
        pcm[i] = i.isEven ? 0.1 : -0.1;
      }
      for (var i = 23000; i < 24000; i++) {
        pcm[i] = 0;
      }
      final trimmed = SpeakerIdentity.prepareWakeSamples(pcm);
      expect(trimmed.length, lessThan(pcm.length));
      expect(trimmed.length, greaterThan(16000));
      expect(trimmed.where((x) => x != 0).length, 15000);
      expect(SpeakerIdentity.prepareWakeSamples(Float32List(48000)), isEmpty);
    },
  );
  test(
    'short wake speech retains original context for the embedding minimum',
    () {
      for (final start in [0, 16000, 42400]) {
        final pcm = Float32List(48000);
        for (var i = start; i < start + 5600; i++) {
          pcm[i] = i.isEven ? 0.1 : -0.1;
        }
        final prepared = SpeakerIdentity.prepareWakeSamples(pcm);
        expect(prepared.length, 12000);
        expect(prepared.where((v) => v != 0).length, 5600);
        // Context is retained, not fabricated by repeating the user's speech.
        expect(prepared.where((v) => v > 0).length, 2800);
      }
    },
  );
  test(
    'an isolated click and truncated capture cannot become a wake profile',
    () {
      final click = Float32List(48000)..[20000] = 0.8;
      expect(SpeakerIdentity.prepareWakeSamples(click), isEmpty);
      expect(
        SpeakerIdentity.prepareWakeSamples(
          Float32List(6000)..fillRange(0, 6000, 0.1),
        ),
        isEmpty,
      );
    },
  );
}
