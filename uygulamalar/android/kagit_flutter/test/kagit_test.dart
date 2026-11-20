import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kagit_flutter/kagit_ai_service.dart';
import 'package:kagit_flutter/kagit_export_service.dart';
import 'package:kagit_flutter/kagit_models.dart';
import 'package:kagit_flutter/kagit_store.dart';
import 'package:kagit_flutter/main.dart';
import 'package:kagit_flutter/views/settings_sheet.dart';
import 'package:kagit_flutter/views/teacher_page.dart';

void main() {
  test('PII Redactor validates Turkish T.C. Kimlik, IBAN, phone, email & dates accurately', () {
    expect(PiiRedactor.tcGecerli('10000000146'), isTrue);
    expect(PiiRedactor.tcGecerli('10000000147'), isFalse);
    expect(PiiRedactor.tcGecerli('01234567890'), isFalse);

    expect(PiiRedactor.ibanGecerli('TR33 0006 1005 1978 6457 8413 26'), isTrue);
    expect(PiiRedactor.ibanGecerli('TR33 0006 1005 1978 6457 8413 25'), isFalse);

    const sample =
        'Adı: Ahmet Yılmaz\nT.C.: 10000000146\nYanlış TC: 10000000147\nIBAN: TR33 0006 1005 1978 6457 8413 26\nTel: +90 532 123 45 67\nE-posta: ahmet@okul.edu.tr\nTarih: 13.11.2026';

    final detected = PiiRedactor.detect(sample);
    final kinds = detected.map((d) => d.kind).toSet();
    expect(kinds, containsAll([PiiKind.tcKimlik, PiiKind.iban, PiiKind.telefon, PiiKind.eposta, PiiKind.tarih]));
    expect(detected.where((d) => d.kind == PiiKind.tcKimlik).length, 1);

    final masked = PiiRedactor.maskText(sample);
    expect(masked.contains('10000000146'), isFalse);
    expect(masked.contains('10000000147'), isTrue);
    expect(masked.contains('ahmet@okul.edu.tr'), isFalse);
    expect(masked.contains('532 123 45 67'), isFalse);

    final boxes = PiiRedactor.buildRedactionAnnotations(
      pageIndex: 0,
      blocks: const [
        OcrBlockBox(text: 'T.C. 10000000146', x: 0.1, y: 0.2, w: 0.4, h: 0.05),
        OcrBlockBox(text: 'Normal satır', x: 0.1, y: 0.3, w: 0.4, h: 0.05),
      ],
    );
    expect(boxes.length, 1);
    expect(boxes.first.kind, AnnotationKind.redact);
  });

  test('SplitMix64 Booklet Generator produces deterministic bijection and key table', () {
    final questions = ['Soru Bir', 'Soru İki', 'Soru Üç', 'Soru Dört', 'Soru Beş'];
    final r1 = KitapcikGenerator.generate(
      questions: questions,
      examTitle: 'Fizik Yazılısı',
      seed: 2026,
      aAnswerKeys: ['A', 'B', 'C', 'D', 'A'],
    );
    final r2 = KitapcikGenerator.generate(
      questions: questions,
      examTitle: 'Fizik Yazılısı',
      seed: 2026,
      aAnswerKeys: ['A', 'B', 'C', 'D', 'A'],
    );

    expect(r1.bOrderToA, r2.bOrderToA);
    expect(r1.bOrderToA.toSet(), {0, 1, 2, 3, 4});
    expect(r1.aMetni, contains('1. Soru Bir'));
    expect(r1.bMetni, contains('B KİTAPÇIĞI'));
    expect(r1.cevapAnahtariMetni, contains('B-01'));
  });

  test('PuanParser and XLSX/DOCX/EPUB exporters build valid Office & EPUB ZIP structures', () {
    expect(PuanParser.parseStudentFilename('104 Kerem Arslan - Fizik.pdf'), ('104', 'Kerem Arslan'));

    final puanlar = [
      PdfAnnotation(id: '1', pageIndex: 0, kind: AnnotationKind.puan, colorValue: 0xFF00AA00, text: '+25'),
      PdfAnnotation(id: '2', pageIndex: 1, kind: AnnotationKind.puan, colorValue: 0xFF00AA00, text: '+30'),
      PdfAnnotation(id: '3', pageIndex: 1, kind: AnnotationKind.puan, colorValue: 0xFFFF0000, text: '-5'),
    ];
    expect(PuanParser.sumAnnotations(puanlar), 50);

    final xlsxBytes = KagitDocumentExporters.buildXlsxScores(
      title: '10-A Sınav Sonuçları',
      rows: const [
        OgrenciPuanSatiri(no: '101', adSoyad: 'Zeynep Yılmaz', puan: 95),
        OgrenciPuanSatiri(no: '102', adSoyad: 'Emre Kaya', puan: 85),
      ],
    );
    final xlsxZip = ZipDecoder().decodeBytes(xlsxBytes);
    final sheetXml = utf8.decode(xlsxZip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(sheetXml, contains('Zeynep Yılmaz'));
    expect(sheetXml, contains('<v>90.0</v>')); // Ortalama (95+85)/2

    final docxBytes = KagitDocumentExporters.buildDocx(
      title: 'Türkçe Özeti',
      pages: ['Birinci sayfa metni.', 'İkinci sayfa metni.'],
    );
    final docxZip = ZipDecoder().decodeBytes(docxBytes);
    final docXml = utf8.decode(docxZip.findFile('word/document.xml')!.content as List<int>);
    expect(docXml, contains('Birinci sayfa metni.'));
    expect(docXml, contains('İkinci sayfa metni.'));

    final epubBytes = KagitDocumentExporters.buildEpub(
      title: 'Deneme Kitabı',
      author: 'Öğretmen',
      pages: ['Bölüm içeriği'],
    );
    final epubZip = ZipDecoder().decodeBytes(epubBytes);
    expect(epubZip.first.name, 'mimetype');
    expect(epubZip.findFile('OEBPS/content.opf'), isNotNull);
    expect(epubZip.findFile('OEBPS/page_1.xhtml'), isNotNull);
  });

  test('CLIProxyAPI parses ALL multi-provider models and completes Document AI requests', () async {
    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/v1/models')) {
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'gemini-2.5-pro'},
              {'id': 'claude-opus-4-1'},
              {'id': 'gpt-5-codex'},
              {'id': 'qwen3-coder-plus'},
              {'id': 'deepseek-r1'},
              {'id': 'glm-4.5'},
            ],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/v1/chat/completions')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': 'Model ${body['model']}: Belge özeti hazır [Sayfa 1].',
                  },
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('Not found', 404);
    });

    final ai = KagitAiService(httpClient: mockClient);
    ai.updateConfig((cfg) {
      cfg.mode = KagitAiMode.localCliProxy;
      cfg.endpoint = 'http://127.0.0.1:8317';
      cfg.apiKey = 'sk-test';
    });

    final models = await ai.fetchAllModels();
    expect(models.length, 6);
    expect(models.map((m) => m.id), containsAll(['gemini-2.5-pro', 'claude-opus-4-1', 'gpt-5-codex', 'deepseek-r1', 'glm-4.5']));

    final groups = ai.groupedModels();
    expect(groups.keys, containsAll(['Google Gemini', 'Anthropic Claude', 'OpenAI / Codex', 'DeepSeek', 'GLM / Zhipu']));

    ai.updateConfig((cfg) => cfg.selectedModelId = 'claude-opus-4-1');
    final reply = await ai.ozetle('Bu belge test içindir.', title: 'Test');
    expect(reply, contains('claude-opus-4-1'));
    expect(reply, contains('[Sayfa 1]'));
  });

  testWidgets('KagitController persists state & KagitApp renders all 5 Turkish workspace tabs', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('kagit_test_');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final controller = KagitController(
      enableNativePlatform: false,
      testWorkspaceDir: tempDir,
    );
    await tester.runAsync(() async {
      await controller.init();
      final pdfFile = File('${tempDir.path}/library/ornek.pdf')..writeAsBytesSync([37, 80, 68, 70]);
      final doc = await controller.registerPdfFile(pdfFile.path, customTitle: '101 Zeynep Yılmaz - Sınav');
      controller.toggleStar(doc);
      controller.addAnnotation(
        doc.id,
        PdfAnnotation(id: 'a1', pageIndex: 0, kind: AnnotationKind.puan, colorValue: 0xFF288557, text: '+20'),
      );
      expect(controller.canUndo(doc.id), isTrue);
      controller.undoAnnotation(doc.id);
      expect(controller.annotationsFor(doc.id).isEmpty, isTrue);
      controller.redoAnnotation(doc.id);
      expect(controller.annotationsFor(doc.id).length, 1);
    });

    await tester.pumpWidget(KagitApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Editoryal PDF, Tarama ve Sınav Stüdyosu'), findsOneWidget);

    await tester.tap(find.text('Dosyalar'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('101 Zeynep Yılmaz - Sınav'), findsWidgets);

    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Araçlar')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Tüm PDF ve Stüdyo Araçları'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Araç ara (birleştir, OCR, karart, kitapçık, Excel...)'), 'PII');
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Otomatik PII Karartma'), findsWidgets);

    await tester.tap(find.text('Öğretmen'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Sınav, Kitapçık ve Puanlama Stüdyosu'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('10-A Sınıfı'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(KagitTeacherPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('10-A Sınıfı'), findsOneWidget);

    await tester.tap(find.text('Ayarlar'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.scrollUntilVisible(
      find.text('CLIProxyAPI ve Tüm AI Modelleri'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(KagitSettingsPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('CLIProxyAPI ve Tüm AI Modelleri'), findsOneWidget);
  });
}
