import 'dart:convert';
import 'package:jarvis_mobile/services/local_command_engine.dart';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jarvis_mobile/models/jarvis_models.dart';
import 'package:jarvis_mobile/services/document_spec.dart';
import 'package:jarvis_mobile/services/spreadsheet_spec.dart';
import 'package:jarvis_mobile/services/office_docs.dart';
import 'package:jarvis_mobile/services/storage_service.dart';
import 'package:jarvis_mobile/services/work_hub.dart';
import 'package:jarvis_mobile/state/jarvis_controller.dart';
import 'package:jarvis_mobile/widgets/chat_file_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('direct project tag from Live provider reaches the same tool', () {
    const reply = '<create_project>{"name":"demo.zip","files":[]}</create_project>';
    expect(LocalCommandEngine.extractActions(reply).single['type'], 'create_project');
    expect(LocalCommandEngine.stripActionTags(reply), isEmpty);
  });
  test('project ZIP preserves source paths and Turkish text', () {
    final zip = ZipDecoder().decodeBytes(OfficeDocs.projectArchive([
      {'path': 'src/main.py', 'content': 'print("merhaba")'},
      {'path': 'README.md', 'content': 'Çalıştırma'},
    ]));
    expect(zip.files.map((f) => f.name), ['src/main.py', 'README.md']);
    expect(utf8.decode(zip.findFile('README.md')!.readBytes()!), 'Çalıştırma');
    for (final bad in ['../main', '/main', 'src', 'SRC/MAIN.PY', r'C:\bad']) {
      expect(() => OfficeDocs.projectArchive([
        {'path': 'src/main.py', 'content': ''},
        {'path': bad, 'content': ''},
      ]), throwsFormatException);
    }
  });
  const url = 'https://example.com/book';
  final at = DateTime(2026, 11, 17);
  test(
    'researched sheets keep literal cells and verified source provenance',
    () {
      final spec = SpreadsheetSpec.validate(
        {
          'sheet': 'Kitap',
          'headers': ['Kitap', 'Fiyat'],
          'rows': [
            ['Şeker Portakalı', 123.45],
          ],
          'sources': [url],
        },
        readUrls: {url},
        checkedAt: at,
      );
      final zip = ZipDecoder().decodeBytes(OfficeDocs.buildXlsx(spec));
      final xml = utf8.decode(
        zip.findFile('xl/worksheets/sheet1.xml')!.readBytes()!,
      );
      expect(xml, contains('Şeker Portakalı'));
      expect(xml, contains('123.45'));
      expect(xml, contains(url));
      expect(spec['rows'], hasLength(1));
      expect(
        () => SpreadsheetSpec.validate(
          {
            'headers': ['A'],
            'rows': [
              ['B'],
            ],
            'sources': ['https://invented.test'],
          },
          readUrls: {url},
          checkedAt: at,
        ),
        throwsFormatException,
      );
      expect(
        () => SpreadsheetSpec.validate(
          {
            'headers': ['A'],
            'rows': [
              ['B', 'C'],
            ],
          },
          readUrls: {},
          checkedAt: at,
        ),
        throwsFormatException,
      );
    },
  );
  test('Word keeps supplied Turkish content and rejects unread sources', () {
    final input = {
      'title': 'Kitap bilgileri',
      'paragraphs': ['Şeker Portakalı, Türkçe baskı.'],
      'sources': [url],
    };
    final spec = DocumentSpec.validate(input, readUrls: {url}, checkedAt: at);
    final zip = ZipDecoder().decodeBytes(OfficeDocs.buildDocx(spec));
    final xml = utf8.decode(zip.findFile('word/document.xml')!.readBytes()!);
    expect(xml, contains('Şeker Portakalı'));
    expect(xml, contains(url));
    expect(
      () => DocumentSpec.validate(input, readUrls: {}, checkedAt: at),
      throwsFormatException,
    );
  });
  test('web-to-office commands remain in the evidence-gathering tool loop', () {
    expect(
      WorkHub.parseCommand(
        'Kitapyurdu Şeker Portakalı bilgilerini çek Excel oluştur',
      ),
      isNull,
    );
    expect(
      WorkHub.parseCommand('Excel oluştur: aylık bütçe')?.kind,
      WorkKind.excel,
    );
  });
  test('delivery persists on originating chat and is not duplicated', () async {
    SharedPreferences.setMockInitialValues({});
    final c = JarvisController();
    c.sessions = [
      ChatSession(
        id: 'original',
        title: 'Araştırma',
        updatedAt: at,
        messages: [],
      ),
      ChatSession(id: 'other', title: 'Diğer', updatedAt: at, messages: []),
    ];
    c.activeSessionId = 'other';
    final job = WorkJob(
      id: 'book',
      kind: WorkKind.excel,
      task: 'Kitap',
      status: 'completed',
      createdAt: at,
      chatSessionId: 'original',
      outputs: [
        WorkFile(
          name: 'kitap.xlsx',
          path: '/files/kitap.xlsx',
          mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          size: 100,
          publicUri: 'content://downloads/1',
        ),
      ],
    );
    await c.deliverWorkFiles(job, 'original');
    await c.deliverWorkFiles(job, 'original');
    expect(c.sessions.first.messages, hasLength(1));
    expect(c.activeSession.messages, isEmpty);
    final loaded = await StorageService().loadSessions();
    expect(
      loaded.sessions.first.messages.single.attachments.single.publicUri,
      'content://downloads/1',
    );
    expect(WorkJob.fromJson(job.toJson()).chatSessionId, 'original');
    c.dispose();
  });
  testWidgets('chat file opens through Android without navigating to Works', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('com.jarvis.assistant/device');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatFileCard(
            file: ChatAttachment(
              id: 'x',
              name: 'Kitap.pdf',
              mimeType: 'application/pdf',
              kind: 'file',
              localPath: '/files/Kitap.pdf',
              publicUri: 'content://downloads/1',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Paylaş'), findsOneWidget);
    await tester.tap(find.text('Aç'));
    await tester.pump();
    expect(calls.single.method, 'openFileUri');
    expect(calls.single.arguments['uri'], 'content://downloads/1');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
