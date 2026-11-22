import 'dart:convert';

import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:bilgili_flutter/services/native_bridge.dart';
import 'package:bilgili_flutter/state/arena_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clean installation has exactly 3,270,439 academic questions', () async {
    NativeBridge.testMode = true;
    final controller = ArenaController(persistToDisk: false);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.personalQuestions, isEmpty);
    expect(controller.totalPoolCount, 3270439);
    expect(AdvancedCatalog.all.length, 3270439);
    expect(controller.allQuestions.last.sourceModel, contains('Astra'));
  });

  test('v3 backup preserves progress and genuine personal entries during curriculum renewal', () async {
    const channel = MethodChannel('com.mehmetderin.bilgiarena/native');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final controller = ArenaController.inMemoryForTest();
    addTearDown(controller.dispose);
    addTearDown(() {
      NativeBridge.testMode = true;
      messenger.setMockMethodCallHandler(channel, null);
    });
    NativeBridge.testMode = false;
    Map<String, dynamic> question(String id) => {
      'id': id,
      'text': 'Soru $id',
      'options': ['A', 'B', 'C', 'D'],
      'answer': 0,
      'category': 'Bilim',
      'difficulty': 'Kolay',
      'explanation': 'Örnek',
    };
    final official = question('mb100k_astra_d78ae768cad000ebd5b6');
    final mine = question('my-question');
    final backup = {
      'xp': 1250,
      'creationPortfolio': {'my-design': 'İki grubu karşılaştırırım.'},
      'savedBookmarks': [official],
      'offlinePacks': [
        {
          'id': 'astra-applied-01',
          'questions': [official],
        },
        {
          'id': 'astra-quant-01',
          'questions': [official, mine],
        },
      ],
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickFiles') {
        return [
          {
            'name': 'backup.json',
            'bytes': Uint8List.fromList(utf8.encode(jsonEncode(backup))),
          },
        ];
      }
      return null;
    });
    for (var restore = 0; restore < 2; restore++) {
      expect(await controller.restoreFullBackup(), contains('başarıyla'));
      expect(controller.xp, 1250);
      expect(controller.creationPortfolio['my-design'], 'İki grubu karşılaştırırım.');
      expect(controller.savedBookmarks.single.id, official['id']);
      expect(controller.personalQuestions.single.id, mine['id']);
      expect(controller.totalPoolCount, 3270440);
    }
  });
}
