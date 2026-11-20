import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/agent_core.dart';
import 'package:jarvis_mobile/services/local_command_engine.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

JarvisMessage _msg(int i, {int len = 700}) => JarvisMessage(
      id: 'm$i',
      role: i.isEven ? 'user' : 'assistant',
      content: 'x' * len,
      timestamp: DateTime(2026, 1, 1).add(Duration(minutes: i)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JarvisController c;
  late int summaryCalls;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    summaryCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.jarvis.assistant/device'),
          (call) async => true,
        );
    final client = MockClient((req) async {
      summaryCalls++;
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': {'content': 'ÖZET $summaryCalls'}},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    c = JarvisController(httpClient: client);
    await c.init(loadPlatformTelemetry: false);
    await c.updateSettings(c.settings.copyWith(autoFallbackGemini: false));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.jarvis.assistant/device'),
          null,
        );
    c.dispose();
  });

  test('uzun sohbette ardışık iki tur bir kez özetler', () async {
    final h1 = [for (var i = 0; i < 60; i++) _msg(i)]; // 42000 karakter
    final r1 = await c.maybeCompress(h1);
    expect(summaryCalls, 1);
    expect(r1.first.id, 'ozet');
    final h2 = [...h1, _msg(60), _msg(61)];
    final r2 = await c.maybeCompress(h2);
    expect(summaryCalls, 1);
    expect(r2.first.content, contains('ÖZET 1'));
    expect(r2.length, lessThan(h2.length));
  });

  test('/sikistir özeti eşik altındaki sonraki turda kullanılır', () async {
    final h = [for (var i = 0; i < 30; i++) _msg(i, len: 100)];
    expect(await c.maybeCompress(h), hasLength(30)); // eşik altı, özet yok
    await c.maybeCompress(h, force: true);
    expect(summaryCalls, 1);
    final next = await c.maybeCompress([...h, _msg(30, len: 100)]);
    expect(summaryCalls, 1);
    expect(next.first.id, 'ozet');
  });

  test('/gunluk-plan tireli beceriyi bulur', () async {
    await c.skillStore.manage(
      action: 'create',
      name: 'gunluk-plan',
      description: 'Günlük plan yap',
      body: 'Ne zaman: sabah\nYöntem: listele\nTuzaklar: yok\nDoğrulama: kontrol',
    );
    expect(c.skillStore.find('gunluk-plan'), isNotNull);
    expect(c.skillStore.find('/gunluk-plan'.substring(1)), isNotNull);
    expect(c.skillStore.find(''), isNull);
    expect(c.skillStore.find('gu'), isNull);
  });

  test('addMemory AgentMemoryLimits.memory sınırını aşmaz', () async {
    final big = 'a' * 390;
    var refused = false;
    for (var i = 0; i < 8; i++) {
      final r = await c.addMemory('${big}b$i');
      if (r.contains('Hafıza dolu')) refused = true;
    }
    expect(refused, isTrue);
    expect(c.settings.memoryText.length, lessThanOrEqualTo(AgentMemoryLimits.memory));
  });

  test('selectModel görsel/embedding modelini sohbet modeli yapmaz', () async {
    final before = c.settings.model;
    final msg = await c.selectModel(
      ProxyModelInfo(id: 'dall-e-3', ownedBy: 'x', category: 'image'),
    );
    expect(msg, 'Bu model sohbet için uygun değil.');
    expect(c.settings.model, before);
    final m2 = await c.selectModel(
      ProxyModelInfo(id: 'text-embedding-3', ownedBy: 'x', category: 'embedding'),
    );
    expect(m2, 'Bu model sohbet için uygun değil.');
    expect(c.settings.model, before);
  });

  test('_appendToSession oturum değişse de özgün oturuma yazar', () async {
    final first = c.activeSessionId;
    await c.createNewSession();
    expect(c.activeSessionId, isNot(first));
    await c.appendToSessionForTest(
      first,
      JarvisMessage(
        id: LocalCommandEngine.newId(),
        role: 'assistant',
        content: 'rapor',
        timestamp: DateTime.now(),
      ),
    );
    final s = c.sessions.firstWhere((x) => x.id == first);
    expect(s.messages.last.content, 'rapor');
    expect(c.activeSession.messages.any((m) => m.content == 'rapor'), isFalse);
  });
}
