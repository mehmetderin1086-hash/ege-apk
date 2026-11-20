import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/services/device_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jarvis.assistant/device');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('keepAlive false (izin yok) istisna atmadan false doner', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'keepAlive');
          expect(call.arguments['reason'], 'live');
          return false;
        });
    expect(await DeviceBridge.keepAlive('live', true, text: 'x'), isFalse);
  });

  test('keepAlive true ve platform hatasi tolere edilir', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
    expect(await DeviceBridge.keepAlive('wake', false), isTrue);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'SECURITY');
        });
    expect(await DeviceBridge.keepAlive('agent', true), isFalse);
  });
}
