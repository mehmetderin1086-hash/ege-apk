import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jarvis_mobile/services/google_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jarvis.assistant/device');
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'google_connected_gmail': true,
      'google_connected_calendar': true,
    });
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
  test('mail is UTF8 MIME and cannot inject recipient headers', () {
    final raw = GoogleWorkspace.encodeMail(
      'me@example.com',
      'Türkçe konu',
      'Şeker Portakalı',
    );
    final mime = utf8.decode(base64Url.decode(base64Url.normalize(raw)));
    expect(mime, contains('To: me@example.com\r\nSubject: =?UTF-8?B?'));
    expect(mime, contains(base64Encode(utf8.encode('Şeker Portakalı'))));
    expect(
      () => GoogleWorkspace.encodeMail(
        'me@example.com\r\nBcc: x@y.com',
        'Konu',
        'Metin',
      ),
      throwsFormatException,
    );
    expect(
      () => GoogleWorkspace.encodeMail(
        'me@example.com',
        'Konu\nBcc:x@y.com',
        'Metin',
      ),
      throwsFormatException,
    );
  });
  test(
    'calendar requires timezone and preserves selected calendar path',
    () async {
      expect(
        () => GoogleWorkspace.eventBody(
          'İş',
          '2026-11-17T10:00:00',
          '2026-11-17T11:00:00',
          '',
        ),
        throwsFormatException,
      );
      expect(
        () => GoogleWorkspace.eventBody(
          'İş',
          '2026-11-17T11:00:00+03:00',
          '2026-11-17T10:00:00+03:00',
          '',
        ),
        throwsFormatException,
      );
      final api = GoogleWorkspace(
        client: MockClient((req) async {
          expect(req.url.pathSegments[3], 'person@example.com');
          expect(req.headers['Authorization'], 'Bearer test-token');
          expect(req.method, 'PATCH');
          return http.Response('{"id":"event1"}', 200);
        }),
      );
      expect(
        (await api.saveEvent(
          calendarId: 'person@example.com',
          eventId: 'event1',
          title: 'İş',
          start: '2026-11-17T10:00:00+03:00',
          end: '2026-11-17T11:00:00+03:00',
        ))['id'],
        'event1',
      );
      api.dispose();
    },
  );
  test('disconnected service does not send an HTTP request', () async {
    final api = GoogleWorkspace(
      client: MockClient((_) async => throw StateError('Network must not run')),
    );
    await expectLater(api.driveList(''), throwsStateError);
    api.dispose();
  });
  test(
    'send only reports server id and does not repeat a successful request',
    () async {
      var requests = 0;
      final api = GoogleWorkspace(
        client: MockClient((req) async {
          requests++;
          expect(req.url.host, 'gmail.googleapis.com');
          return http.Response('{"id":"sent1"}', 200);
        }),
      );
      final first = await api.mailSend('me@example.com', 'Konu', 'Merhaba');
      final second = await api.mailSend('me@example.com', 'Konu', 'Merhaba');
      expect(first['id'], 'sent1');
      expect(second['duplicatePrevented'], true);
      expect(requests, 1);
      api.dispose();
    },
  );
}
