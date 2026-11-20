import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jarvis_mobile/services/microsoft_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jarvis.assistant/device');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {'status': 'OK', 'token': 'test-token'},
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('connection is marked only after actual API verification', () async {
    var allow = false;
    final ms = MicrosoftWorkspace(
      client: MockClient((request) async {
        expect(request.url.host, 'graph.microsoft.com');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.followRedirects, false);
        return http.Response(allow ? '{"value":[]}' : '{}', allow ? 200 : 403);
      }),
    );
    await expectLater(ms.connect('outlook'), throwsStateError);
    expect(await ms.connected('outlook'), false);
    allow = true;
    await ms.connect('outlook');
    expect(await ms.connected('outlook'), true);
    expect(await ms.connected('calendar'), false);
    ms.dispose();
  });
  test('disconnected service cannot access Graph', () async {
    var calls = 0;
    final ms = MicrosoftWorkspace(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(ms.mailSearch('Merhaba'), throwsStateError);
    expect(calls, 0);
    ms.dispose();
  });
  test(
    'mail accepted is not delivered and repeats do not send twice',
    () async {
      SharedPreferences.setMockInitialValues({
        'microsoft_connected_outlook': true,
      });
      var sends = 0;
      final ms = MicrosoftWorkspace(
        client: MockClient((request) async {
          sends++;
          final data = jsonDecode(request.body) as Map;
          expect(data['message']['body']['content'], 'Türkçe içerik');
          expect(request.url.path, '/v1.0/me/sendMail');
          return http.Response('', 202);
        }),
      );
      final first = await ms.mailSend(
        'test@example.com',
        'Konu',
        'Türkçe içerik',
      );
      expect(first['status'], 'accepted');
      expect(first['deliveryConfirmed'], false);
      expect(
        (await ms.mailSend(
          'test@example.com',
          'Konu',
          'Türkçe içerik',
        ))['duplicatePrevented'],
        true,
      );
      expect(sends, 1);
      ms.dispose();
    },
  );
  test('ambiguous send is never retried automatically', () async {
    SharedPreferences.setMockInitialValues({
      'microsoft_connected_outlook': true,
    });
    var sends = 0;
    final ms = MicrosoftWorkspace(
      client: MockClient((_) async {
        sends++;
        throw TimeoutException('test');
      }),
    );
    await expectLater(
      ms.mailSend('test@example.com', 'Konu', 'İçerik'),
      throwsA(isA<TimeoutException>()),
    );
    expect(
      (await ms.mailSend('test@example.com', 'Konu', 'İçerik'))['status'],
      'unknown',
    );
    expect(sends, 1);
    ms.dispose();
  });
  test('OneDrive upload preserves UTF-8 name and fails on conflicts', () async {
    SharedPreferences.setMockInitialValues({
      'microsoft_connected_onedrive': true,
    });
    final ms = MicrosoftWorkspace(
      client: MockClient((r) async {
        expect(r.method, 'PUT');
        expect(
          Uri.decodeComponent(r.url.path),
          '/v1.0/me/drive/root:/Şeker Portakalı.xlsx:/content',
        );
        expect(
          r.url.queryParameters['@microsoft.graph.conflictBehavior'],
          'fail',
        );
        expect(r.bodyBytes, [1, 2, 3]);
        return http.Response('{"id":"file-id"}', 201);
      }),
    );
    expect(
      (await ms.driveUpload(
        'Şeker Portakalı.xlsx',
        'application/octet-stream',
        Uint8List.fromList([1, 2, 3]),
      ))['id'],
      'file-id',
    );
    await expectLater(
      ms.driveUpload('../x', 'text/plain', Uint8List(1)),
      throwsFormatException,
    );
    ms.dispose();
  });
  test(
    'calendar range requires explicit timezone and IDs stay one segment',
    () {
      expect(
        () => MicrosoftWorkspace.validateRange(
          '2026-11-17T14:00:00',
          '2026-11-17T15:00:00',
        ),
        throwsFormatException,
      );
      expect(
        () => MicrosoftWorkspace.validateRange(
          '2026-11-17T16:00:00+03:00',
          '2026-11-17T15:00:00+03:00',
        ),
        throwsFormatException,
      );
      final uri = MicrosoftWorkspace.path(['messages', 'a/b?c']);
      expect(uri.pathSegments.last, 'a/b?c');
      expect(uri.query, isEmpty);
    },
  );
}
