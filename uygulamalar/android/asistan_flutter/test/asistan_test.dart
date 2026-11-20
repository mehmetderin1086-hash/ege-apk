import 'package:flutter/widgets.dart';

import 'dart:convert';

import 'package:asistan_flutter/main.dart';
import 'package:asistan_flutter/models/asistan_models.dart';
import 'package:asistan_flutter/services/asistan_controller.dart';
import 'package:asistan_flutter/services/document_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Asistan v3.0 DocumentBuilder & Models Testleri', () {
    test('Gerçek PDF, DOCX, XLSX ve PPTX ikili dosyaları üretir', () {
      final pdf = DocumentBuilder.buildPdfBytes(
        title: 'Kuantum Raporu',
        content: 'Birinci satır.\nİkinci satır Türkçe karakterler: ğüşiöç.',
      );
      expect(pdf.length, greaterThan(150));
      expect(latin1.decode(pdf.sublist(0, 8)), startsWith('%PDF-1.4'));

      final docx = DocumentBuilder.buildDocxBytes(
        title: 'Word Test',
        content: '# Başlık\nTest paragrafı',
      );
      expect(docx.length, greaterThan(200));
      expect(docx[0], equals(0x50)); // 'P'
      expect(docx[1], equals(0x4B)); // 'K' (ZIP header)

      final xlsx = DocumentBuilder.buildXlsxBytes(
        title: 'Tablo',
        content: 'Kalem | Tutar\nYazılım | 1500\nDonanım | 2400',
      );
      expect(xlsx.length, greaterThan(200));
      expect(xlsx[0], equals(0x50));

      final pptx = DocumentBuilder.buildPptxBytes(
        title: 'Sunum',
        content: 'Slayt 1 maddesi\nSlayt 2 maddesi',
      );
      expect(pptx.length, greaterThan(200));
      expect(pptx[0], equals(0x50));
    });

    test('ChatThread ve ChatMessage JSON serileştirme doğru çalışır', () {
      final msg = ChatMessage(
        id: 'm1',
        role: 'assistant',
        text: 'Merhaba Mehmet!',
        reasoningText: 'Muhakeme adımı',
        timestamp: DateTime(2026, 11, 14, 12, 0),
        modelUsed: 'gemini-2.5-pro',
        workMode: WorkMode.council,
        toolTraces: const [
          ToolCallTrace(
            name: 'cihaz.fener',
            title: 'El Feneri',
            inputSummary: 'fener_ac',
            outputSummary: 'Açıldı',
          ),
        ],
        arenaCandidates: const [
          ArenaCandidate(
            modelId: 'gpt-5',
            modelName: 'ChatGPT-5',
            provider: 'OpenAI',
            response: 'Model yanıtı',
            latencyMs: 320,
          ),
        ],
      );

      final roundtrip = ChatMessage.fromJson(msg.toJson());
      expect(roundtrip.id, equals('m1'));
      expect(roundtrip.workMode, equals(WorkMode.council));
      expect(roundtrip.toolTraces.first.title, equals('El Feneri'));
      expect(roundtrip.arenaCandidates.first.modelName, equals('ChatGPT-5'));
    });
  });

  group('Asistan v3.0 3D Arayüz ve Sekme Gezinme Testleri', () {
    testWidgets('Ana ekran, 3D Holografik Küre ve 5 sekme hatasız yüklenir', (
      tester,
    ) async {
      final controller = AsistanController();
      await controller.initialize(skipNativeAndNetwork: true);

      await tester.pumpWidget(AsistanApp(controller: controller));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byTooltip('Menü ve sohbetler'), findsOneWidget);
      await tester.tap(find.byTooltip('Menü ve sohbetler'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Canlı Ses'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Sesli konuşma'), findsOneWidget);
      expect(find.text('Gemini'), findsOneWidget);
      expect(find.text('ChatGPT'), findsOneWidget);
      expect(find.text('Claude / Code'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  });
}
