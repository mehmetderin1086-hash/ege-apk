import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../kagit_ai_service.dart';
import '../kagit_export_service.dart';
import '../kagit_models.dart';
import '../kagit_store.dart';
import '../theme_kagit.dart';
import 'settings_sheet.dart';
import 'shared_kagit_widgets.dart';
import 'viewer_sheet.dart';

void openKagitViewer(
  BuildContext context,
  KagitController controller,
  KitaplikOgesi doc, {
  ViewerMode initialMode = ViewerMode.gezin,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (ctx) => BelgeEkrani(
        controller: controller,
        item: doc,
        initialMode: initialMode,
        onRunTool: (tool, activeDoc) => runKagitTool(ctx, controller, tool, preselectedDoc: activeDoc),
      ),
    ),
  );
}

Future<void> runKagitTool(
  BuildContext context,
  KagitController controller,
  KagitTool tool, {
  KitaplikOgesi? preselectedDoc,
}) async {
  controller.recordToolUse(tool.id);

  KitaplikOgesi? doc = preselectedDoc;
  if (tool.requiresDoc && doc == null) {
    doc = await showPickDocumentSheet(
      context,
      controller,
      title: '${tool.title} için Belge Seç',
    );
    if (doc == null || !context.mounted) return;
  }

  switch (tool.id) {
    case KagitToolId.goruntuleVeNot:
      openKagitViewer(context, controller, doc!, initialMode: ViewerMode.kalem);
    case KagitToolId.imzaEkle:
      openKagitViewer(context, controller, doc!, initialMode: ViewerMode.imza);
    case KagitToolId.duzlestir:
      await _runBusy(context, 'Notlar PDF’e yakılıyor...', () async {
        final out = await controller.flattenAnnotationsToPdf(doc!);
        if (context.mounted) openKagitViewer(context, controller, out);
      });
    case KagitToolId.bosPdfOlustur:
      await _showBlankPdfDialog(context, controller);
    case KagitToolId.birlestir:
      await _showMergeDialog(context, controller, initial: doc);
    case KagitToolId.bol:
      await _showSplitDialog(context, controller, doc!);
    case KagitToolId.sayfaDuzenle:
      await _showPageOrganizerDialog(context, controller, doc!);
    case KagitToolId.nUpYerlesim:
      await _showNUpDialog(context, controller, doc!);
    case KagitToolId.kitapcikBasim:
      await _runBusy(context, 'Katlamalı kitapçık düzeni hazırlanıyor...', () async {
        final out = await controller.assembleDocument(
          newTitle: '${doc!.title} (Kitapçık)',
          sourcePath: doc.path,
          booklet: true,
          tags: const ['Kitapçık'],
        );
        if (context.mounted) openKagitViewer(context, controller, out);
      });
    case KagitToolId.sayfaBoyutlandir:
      await _showResizeDialog(context, controller, doc!);
    case KagitToolId.kenarKirp:
      await _runBusy(context, 'Kenar boşlukları kırpılıyor...', () async {
        final out = await controller.assembleDocument(
          newTitle: '${doc!.title} (Kırpılmış)',
          sourcePath: doc.path,
          trimMargins: true,
        );
        if (context.mounted) openKagitViewer(context, controller, out);
      });
    case KagitToolId.filigranEkle:
      await _showWatermarkDialog(context, controller, doc!);
    case KagitToolId.sayfaNumarasi:
      await _showHeaderFooterDialog(context, controller, doc!);
    case KagitToolId.sikistir:
      await _showCompressDialog(context, controller, doc!);
    case KagitToolId.kameraTara:
      await _runCameraOrImageScan(context, controller, fromCamera: true);
    case KagitToolId.gorseldenPdf:
      await _runCameraOrImageScan(context, controller, fromCamera: false);
    case KagitToolId.ocrMetinTanima:
      await _showOcrDialog(context, controller, doc!);
    case KagitToolId.wordOlarakKaydet:
    case KagitToolId.epubOlustur:
    case KagitToolId.markdownVeHtml:
    case KagitToolId.sayfalariGorseleCevir:
      await _runExportTool(context, controller, tool.id, doc!);
    case KagitToolId.piiKarartma:
      await _showPiiRedactDialog(context, controller, doc!);
    case KagitToolId.belgeKarsilastir:
      await _showCompareDialog(context, controller, doc!);
    case KagitToolId.metaTemizle:
      await _runBusy(context, 'Gizli üstveri temizleniyor...', () async {
        final out = await controller.assembleDocument(
          newTitle: '${doc!.title} (Temiz)',
          sourcePath: doc.path,
          dpi: 150,
          tags: const ['Temiz Üstveri'],
        );
        if (context.mounted) openKagitViewer(context, controller, out);
      });
    case KagitToolId.sinavYiginiBol:
      await _showExamStackSplitDialog(context, controller, doc!);
    case KagitToolId.abKitapcik:
      await _showAbBookletDialog(context, controller, sourceDoc: doc);
    case KagitToolId.okulBasligiEkle:
      await _showSchoolHeaderStampDialog(context, controller, doc!);
    case KagitToolId.puanToplaVeExcel:
    case KagitToolId.excelPuanTablosu:
      await _showPointsExcelDialog(context, controller);
    case KagitToolId.aiOzetle:
    case KagitToolId.aiCevir:
    case KagitToolId.aiSohbet:
    case KagitToolId.aiSoruUret:
      await _showAiToolSheet(context, controller, tool.id, doc);
  }
}

Future<void> _runBusy(BuildContext context, String label, Future<void> Function() task) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 18),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
  try {
    await task();
  } catch (e) {
    if (context.mounted) showKagitSnack(context, 'İşlem başarısız: $e', isError: true);
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

Future<void> _showBlankPdfDialog(BuildContext context, KagitController controller) async {
  final titleCtrl = TextEditingController(text: 'Yeni Defter');
  var pattern = BlankPaperPattern.lined;
  int pageCount = 4;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Boş Not Defteri PDF’i'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Belge Başlığı', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BlankPaperPattern>(
              initialValue: pattern,
              decoration: const InputDecoration(labelText: 'Kağıt Deseni', border: OutlineInputBorder()),
              items: [
                for (final p in BlankPaperPattern.values)
                  DropdownMenuItem(value: p, child: Text(p.title)),
              ],
              onChanged: (v) {
                if (v != null) setS(() => pattern = v);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Sayfa Sayısı: $pageCount', style: const TextStyle(fontWeight: FontWeight.w600)),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 20,
                    divisions: 19,
                    value: pageCount.toDouble(),
                    onChanged: (v) => setS(() => pageCount = v.round()),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              final title = titleCtrl.text.trim().isEmpty ? 'Yeni Defter' : titleCtrl.text.trim();
              Navigator.pop(ctx);
              await _runBusy(context, 'Not defteri hazırlanıyor...', () async {
                final doc = await controller.createTextOrBlankPdf(
                  title: title,
                  pattern: pattern,
                  pageCount: pageCount,
                );
                if (context.mounted) openKagitViewer(context, controller, doc, initialMode: ViewerMode.kalem);
              });
            },
            child: const Text('Oluştur'),
          ),
        ],
      ),
    ),
  );
  titleCtrl.dispose();
}

Future<void> _showMergeDialog(BuildContext context, KagitController controller, {KitaplikOgesi? initial}) async {
  final selected = <KitaplikOgesi>[?initial];
  final titleCtrl = TextEditingController(text: 'Birleştirilmiş Belge');

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.78,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('PDF Birleştir (${selected.length} seçili)', style: kagitSerif(ctx, size: 18)),
                const SizedBox(height: 10),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Yeni Dosya Adı', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final doc in controller.activeItems)
                        CheckboxListTile(
                          value: selected.contains(doc),
                          title: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${doc.pageCount} sayfa • ${formatFileSizeTr(doc.fileSize)}'),
                          onChanged: (checked) {
                            setS(() {
                              if (checked == true) {
                                selected.add(doc);
                              } else {
                                selected.remove(doc);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: selected.length < 2
                      ? null
                      : () async {
                          final outName = titleCtrl.text.trim().isEmpty ? 'Birleştirilmiş' : titleCtrl.text.trim();
                          Navigator.pop(ctx);
                          await _runBusy(context, 'Belgeler birleştiriliyor...', () async {
                            final out = await controller.mergeDocuments(selected, title: outName);
                            if (context.mounted) openKagitViewer(context, controller, out);
                          });
                        },
                  icon: const Icon(Icons.call_merge_rounded),
                  label: const Text('Seçili Belgeleri Birleştir'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  titleCtrl.dispose();
}

Future<void> _showSplitDialog(BuildContext context, KagitController controller, KitaplikOgesi doc) async {
  final rangeCtrl = TextEditingController(text: '1-${(doc.pageCount / 2).ceil().clamp(1, doc.pageCount)}');
  bool splitEveryPage = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('${doc.title} (${doc.pageCount} s) Böl'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Her sayfayı ayrı PDF yap'),
              value: splitEveryPage,
              onChanged: (v) => setS(() => splitEveryPage = v),
            ),
            if (!splitEveryPage)
              TextField(
                controller: rangeCtrl,
                decoration: InputDecoration(
                  labelText: 'Sayfa Aralığı (örn: 1-3, 5)',
                  helperText: 'Toplam ${doc.pageCount} sayfa var',
                  border: const OutlineInputBorder(),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _runBusy(context, 'Sayfalar ayrılıyor...', () async {
                if (splitEveryPage) {
                  for (int p = 0; p < doc.pageCount; p++) {
                    await controller.assembleDocument(
                      newTitle: '${doc.title} - Sayfa ${p + 1}',
                      pageEntries: [
                        {'path': doc.path, 'pageIndex': p, 'rotateDeg': 0},
                      ],
                    );
                  }
                  if (context.mounted) showKagitSnack(context, '${doc.pageCount} ayrı PDF kitaplığa eklendi.');
                } else {
                  final indices = _parsePageRange(rangeCtrl.text, doc.pageCount);
                  if (indices.isEmpty) {
                    throw Exception('Geçerli sayfa numarası bulunamadı.');
                  }
                  final out = await controller.assembleDocument(
                    newTitle: '${doc.title} (${rangeCtrl.text.trim()})',
                    pageEntries: [
                      for (final p in indices) {'path': doc.path, 'pageIndex': p, 'rotateDeg': 0},
                    ],
                  );
                  if (context.mounted) openKagitViewer(context, controller, out);
                }
              });
            },
            child: const Text('Ayır ve Kaydet'),
          ),
        ],
      ),
    ),
  );
  rangeCtrl.dispose();
}

List<int> _parsePageRange(String input, int maxPages) {
  final out = <int>[];
  for (final part in input.split(',')) {
    final p = part.trim();
    if (p.contains('-')) {
      final bounds = p.split('-');
      final a = int.tryParse(bounds.first.trim()) ?? 1;
      final b = int.tryParse(bounds.last.trim()) ?? maxPages;
      for (int i = a; i <= b; i++) {
        if (i >= 1 && i <= maxPages) out.add(i - 1);
      }
    } else {
      final single = int.tryParse(p);
      if (single != null && single >= 1 && single <= maxPages) out.add(single - 1);
    }
  }
  return out;
}

Future<void> _showPageOrganizerDialog(BuildContext context, KagitController controller, KitaplikOgesi doc) async {
  final entries = List<Map<String, dynamic>>.generate(
    doc.pageCount,
    (i) => {'path': doc.path, 'pageIndex': i, 'rotateDeg': 0, 'isBlank': false},
  );

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.82,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Sayfa Düzenleyici (${entries.length})', style: kagitSerif(ctx, size: 18))),
                    TextButton.icon(
                      onPressed: () {
                        setS(() => entries.add({'isBlank': true, 'width': 595, 'height': 842, 'rotateDeg': 0}));
                      },
                      icon: const Icon(Icons.add_box_outlined, size: 18),
                      label: const Text('Boş Sayfa'),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final isBlank = e['isBlank'] == true;
                      final rot = (e['rotateDeg'] as int?) ?? 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isBlank ? KagitTema.altinMuhur : KagitTema.vurgu,
                            child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                          title: Text(isBlank ? 'Eklenmiş Boş Sayfa' : 'Özgün Sayfa ${(e['pageIndex'] as int) + 1}'),
                          subtitle: Text('Dönme: $rot°'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isBlank)
                                IconButton(
                                  tooltip: '90° Döndür',
                                  icon: const Icon(Icons.rotate_right_rounded, size: 20),
                                  onPressed: () => setS(() => e['rotateDeg'] = (rot + 90) % 360),
                                ),
                              IconButton(
                                tooltip: 'Yukarı Taşı',
                                icon: const Icon(Icons.arrow_upward_rounded, size: 19),
                                onPressed: i == 0
                                    ? null
                                    : () => setS(() {
                                          final item = entries.removeAt(i);
                                          entries.insert(i - 1, item);
                                        }),
                              ),
                              IconButton(
                                tooltip: 'Aşağı Taşı',
                                icon: const Icon(Icons.arrow_downward_rounded, size: 19),
                                onPressed: i == entries.length - 1
                                    ? null
                                    : () => setS(() {
                                          final item = entries.removeAt(i);
                                          entries.insert(i + 1, item);
                                        }),
                              ),
                              IconButton(
                                tooltip: 'Sil',
                                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: KagitTema.vurgu),
                                onPressed: entries.length <= 1 ? null : () => setS(() => entries.removeAt(i)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _runBusy(context, 'Düzenlenen sayfalar birleştiriliyor...', () async {
                      final out = await controller.assembleDocument(
                        newTitle: '${doc.title} (Düzenli)',
                        pageEntries: entries,
                      );
                      if (context.mounted) openKagitViewer(context, controller, out);
                    });
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Yeni PDF Oluştur'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _showNUpDialog(BuildContext context, KagitController controller, KitaplikOgesi doc) async {
  int selected = 2;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Tek Yaprakta Çoklu Sayfa (N-up)'),
        content: Wrap(
          spacing: 8,
          children: [
            for (final n in [2, 4, 6, 9])
              ChoiceChip(
                label: Text('$n Sayfa / Yaprak'),
                selected: selected == n,
                onSelected: (_) => setS(() => selected = n),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _runBusy(context, '$selected-in-1 düzen oluşturuluyor...', () async {
                final out = await controller.assembleDocument(
                  newTitle: '${doc.title} (${selected}li)',
                  sourcePath: doc.path,
                  nUp: selected,
                );
                if (context.mounted) openKagitViewer(context, controller, out);
              });
            },
            child: const Text('Oluştur'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showResizeDialog(BuildContext context, KagitController controller, KitaplikOgesi doc) async {
  String chosen = 'a4';
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Sayfa Boyutunu Değiştir'),
        content: RadioGroup<String>(
          groupValue: chosen,
          onChanged: (v) {
            if (v != null) setS(() => chosen = v);
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(value: 'a4', title: Text('A4 (210 × 297 mm)')),
              RadioListTile<String>(value: 'a5', title: Text('A5 Defter Boyu (148 × 210 mm)')),
              RadioListTile<String>(value: 'letter', title: Text('US Letter')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _runBusy(context, 'Sayfalar ölçekleniyor...', () async {
                final out = await controller.assembleDocument(
                  newTitle: '${doc.title} (${chosen.toUpperCase()})',
                  sourcePath: doc.path,
                  pageSize: chosen,
                );
                if (context.mounted) openKagitViewer(context, controller, out);
              });
            },
            child: const Text('Uygula'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showWatermarkDialog(BuildContext context, KagitController controller, KitaplikOgesi doc) async {
  final textCtrl = TextEditingController(text: 'TASLAK • GİZLİ');
  double opacity = 0.24;
  bool tiled = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('PDF Filigranı Bas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textCtrl,
              decoration: const InputDecoration(labelText: 'Filigran Metni', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Saydamlık: %${(opacity * 100).round()}'),
                Expanded(
                  child: Slider(min: 0.08, max: 0.70, value: opacity, onChanged: (v) => setS(() => opacity = v)),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tüm Sayfaya Döşe (Desenli)'),
              value: tiled,
              onChanged: (v) => setS(() => tiled = v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              final text = textCtrl.text.trim();
              Navigator.pop(ctx);
              if (text.isEmpty) return;
              await _runBusy(context, 'Filigran ekleniyor...', () async {
                final out = await controller.assembleDocument(
                  newTitle: '${doc.title} (Filigranlı)',
                  sourcePath: doc.path,
                  watermark: {
                    'text': text,
                    'opacity': opacity,
                    'angle': -35.0,
                    'fontSize': tiled ? 24.0 : 46.0,
                    'tiled': tiled,
                  },
                );
                if (context.mounted) openKagitViewer(context, controller, out);
              });
            },
            child: const Text('Uygula'),
          ),
        ],
      ),
    ),
  );
  textCtrl.dispose();
}

Future<void> _showHeaderFooterDialog(BuildContext context, KagitController controller, KitaplikOgesi doc) async {
  final hLeft = TextEditingController();
  final hCenter = TextEditingController(text: doc.title);
  final fLeft = TextEditingController(text: controller.ayarlar.yazarAdi);
  bool addNumbers = true;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Sayfa Numarası & Üst/Alt Bilgi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sayfa Numaraları Ekle (1 / N)'),
                value: addNumbers,
                onChanged: (v) => setS(() => addNumbers = v),
              ),
              TextField(
                controller: hCenter,
                decoration: const InputDecoration(labelText: 'Üst Orta Başlık', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: hLeft,
                decoration: const InputDecoration(labelText: 'Üst Sol (opsiyonel)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fLeft,
                decoration: const InputDecoration(labelText: 'Alt Sol Not', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _runBusy(context, 'Numaralar basılıyor...', () async {
                final out = await controller.assembleDocument(
                  newTitle: '${doc.title} (Numaralı)',
                  sourcePath: doc.path,
                  pageNumbers: {'enabled': addNumbers, 'position': 'bottomCenter', 'startAt': 1},
                  headerFooter: {
                    'headerLeft': hLeft.text.trim(),
                    'headerCenter': hCenter.text.trim(),
                    'footerLeft': fLeft.text.trim(),
                  },
                );
                if (context.mounted) openKagitViewer(context, controller, out);
              });
            },
            child: const Text('Uygula'),
          ),
        ],
      ),
    ),
  );
  hLeft.dispose();
  hCenter.dispose();
  fLeft.dispose();
}

Future<void> _showCompressDialog(BuildContext context, KagitController controller, KitaplikOgesi doc) async {
  int dpi = 105;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('${doc.title} Sıkıştır'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mevcut boyut: ${formatFileSizeTr(doc.fileSize)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            RadioGroup<int>(
              groupValue: dpi,
              onChanged: (v) {
                if (v != null) setS(() => dpi = v);
              },
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<int>(value: 150, title: Text('Yüksek Kalite (150 DPI)')),
                  RadioListTile<int>(value: 105, title: Text('Dengeli Tasarruf (105 DPI)')),
                  RadioListTile<int>(value: 72, title: Text('Maksimum Küçültme (72 DPI)')),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _runBusy(context, 'PDF optimize ediliyor...', () async {
                final out = await controller.assembleDocument(
                  newTitle: '${doc.title} (Sıkışık)',
                  sourcePath: doc.path,
                  dpi: dpi,
                );
                if (context.mounted) {
                  showKagitSnack(
                    context,
                    'Boyut: ${formatFileSizeTr(doc.fileSize)} → ${formatFileSizeTr(out.fileSize)}',
                  );
                  openKagitViewer(context, controller, out);
                }
              });
            },
            child: const Text('Sıkıştır'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _runCameraOrImageScan(
  BuildContext context,
  KagitController controller, {
  required bool fromCamera,
}) async {
  final imagePaths = <String>[];
  try {
    if (fromCamera) {
      final p = await controller.captureCameraPhoto();
      if (p != null) imagePaths.add(p);
    } else {
      imagePaths.addAll(await controller.pickImagesFromDevice(allowMultiple: true));
    }
  } catch (e) {
    if (context.mounted) showKagitSnack(context, 'Görsel alınamadı: $e', isError: true);
    return;
  }

  if (imagePaths.isEmpty || !context.mounted) return;

  String filter = 'bw';
  final titleCtrl = TextEditingController(
    text: fromCamera ? 'Kamera Taraması ${DateTime.now().hour}.${DateTime.now().minute}' : 'Fotoğraf PDF’i',
  );

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('${imagePaths.length} Görsel → PDF'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'PDF Adı', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: filter,
              decoration: const InputDecoration(labelText: 'Tarama İyileştirme Filtresi', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'bw', child: Text('Siyah-Beyaz Belge Taraması (En Net)')),
                DropdownMenuItem(value: 'contrast', child: Text('Yüksek Kontrast')),
                DropdownMenuItem(value: 'grayscale', child: Text('Gri Ton')),
                DropdownMenuItem(value: 'normal', child: Text('Özgün Renkli')),
              ],
              onChanged: (v) {
                if (v != null) setS(() => filter = v);
              },
            ),
          ],
        ),
        actions: [
          if (fromCamera)
            TextButton.icon(
              onPressed: () async {
                final more = await controller.captureCameraPhoto();
                if (more != null) setS(() => imagePaths.add(more));
              },
              icon: const Icon(Icons.add_a_photo_rounded, size: 17),
              label: const Text('Sayfa Ekle'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              final title = titleCtrl.text.trim().isEmpty ? 'Tarama' : titleCtrl.text.trim();
              Navigator.pop(ctx);
              await _runBusy(context, 'Görseller A4 PDF’e işleniyor...', () async {
                final out = await controller.createImagesPdf(
                  imagePaths: imagePaths,
                  title: title,
                  filter: filter,
                );
                if (context.mounted) openKagitViewer(context, controller, out);
              });
            },
            child: const Text('PDF Oluştur'),
          ),
        ],
      ),
    ),
  );
  titleCtrl.dispose();
}

Future<void> _showOcrDialog(BuildContext context, KagitController controller, KitaplikOgesi doc) async {
  late String text;
  await _runBusy(context, 'Cihaz içi ML Kit OCR çalıştırılıyor...', () async {
    text = await controller.ensureTextExtracted(doc);
  });
  if (!context.mounted) return;
  if (text.trim().isEmpty) {
    showKagitSnack(context, 'Sayfalarda okunabilir metin tespit edilemedi.');
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('OCR Metni — ${doc.title}', style: kagitSerif(ctx, size: 17))),
                  IconButton(
                    tooltip: 'Panoya Kopyala',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: text));
                      showKagitSnack(ctx, 'Metin panoya kopyalandı.');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: KagitTema.softBg(ctx),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(text, style: const TextStyle(height: 1.45)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final path = await controller.writeExportBytes('${doc.title}.txt', utf8.encode(text));
                        await controller.shareFile(path, title: '${doc.title}.txt', mimeType: 'text/plain');
                      },
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('.TXT Paylaş'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final bytes = KagitDocumentExporters.buildDocx(
                          title: doc.title,
                          pages: text.split(RegExp(r'--- Sayfa \d+ ---')),
                        );
                        final path = await controller.writeExportBytes('${doc.title}.docx', bytes);
                        await controller.saveFileToUserLocation(
                          path,
                          '${doc.title}.docx',
                          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                        );
                      },
                      icon: const Icon(Icons.description_rounded, size: 18),
                      label: const Text('.DOCX Kaydet'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _runExportTool(
  BuildContext context,
  KagitController controller,
  KagitToolId id,
  KitaplikOgesi doc,
) async {
  if (id == KagitToolId.sayfalariGorseleCevir) {
    await _runBusy(context, 'Tüm sayfalar PNG olarak hazırlanıyor...', () async {
      final archive = Archive();
      for (int i = 0; i < doc.pageCount; i++) {
        final pngPath = await controller.renderPdfPage(doc, i, maxWidth: 1400);
        final bytes = await File(pngPath).readAsBytes();
        archive.addFile(ArchiveFile('${doc.title}_sayfa_${i + 1}.png', bytes.length, bytes));
      }
      final zipBytes = ZipEncoder().encode(archive)!;
      final zipPath = await controller.writeExportBytes('${doc.title}_sayfalar.zip', zipBytes);
      if (context.mounted) {
        final saved = await controller.saveFileToUserLocation(zipPath, '${doc.title}_sayfalar.zip', 'application/zip');
        if (!saved && context.mounted) {
          await controller.shareFile(zipPath, title: '${doc.title} Sayfa Görselleri', mimeType: 'application/zip');
        }
      }
    });
    return;
  }

  String fullText = '';
  await _runBusy(context, 'Belge metni çıkarılıp dönüştürülüyor...', () async {
    fullText = await controller.ensureTextExtracted(doc);
    final pages = fullText
        .split(RegExp(r'\n?--- Sayfa \d+ ---\n?'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    final safePages = pages.isEmpty ? [fullText.isEmpty ? doc.title : fullText] : pages;

    late String fileName;
    late String mime;
    late List<int> bytes;

    if (id == KagitToolId.wordOlarakKaydet) {
      fileName = '${doc.title}.docx';
      mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      bytes = KagitDocumentExporters.buildDocx(title: doc.title, pages: safePages);
    } else if (id == KagitToolId.epubOlustur) {
      fileName = '${doc.title}.epub';
      mime = 'application/epub+zip';
      bytes = KagitDocumentExporters.buildEpub(
        title: doc.title,
        author: controller.ayarlar.yazarAdi,
        pages: safePages,
      );
    } else {
      fileName = '${doc.title}.md';
      mime = 'text/markdown';
      final md = StringBuffer('# ${doc.title}\n\n');
      for (int i = 0; i < safePages.length; i++) {
        md.writeln('## Sayfa ${i + 1}\n');
        md.writeln(safePages[i].trim());
        md.writeln('\n');
      }
      bytes = utf8.encode(md.toString());
    }

    final exportPath = await controller.writeExportBytes(fileName, bytes);
    if (context.mounted) {
      final saved = await controller.saveFileToUserLocation(exportPath, fileName, mime);
      if (!saved && context.mounted) {
        await controller.shareFile(exportPath, title: fileName, mimeType: mime);
      }
    }
  });
}

Future<void> _showPiiRedactDialog(BuildContext context, KagitController controller, KitaplikOgesi doc) async {
  final kinds = Set<PiiKind>.from(PiiKind.values);

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Otomatik PII Gizleme & Karartma'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cihaz içi OCR ile tespit edilen hassas verilerin üzerini siyah şeritle yakar:'),
            const SizedBox(height: 8),
            for (final k in PiiKind.values)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(k.title),
                value: kinds.contains(k),
                onChanged: (v) {
                  setS(() {
                    if (v == true) {
                      kinds.add(k);
                    } else {
                      kinds.remove(k);
                    }
                  });
                },
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: kinds.isEmpty
                ? null
                : () async {
                    Navigator.pop(ctx);
                    await _runBusy(context, 'T.C. / IBAN / İletişim verileri taranıyor...', () async {
                      final ocr = await controller.runOcrOnPdf(doc);
                      final pagesRaw = (ocr['pages'] as List?)?.whereType<Map>().toList() ?? [];
                      final grouped = <String, List<Map<String, dynamic>>>{};
                      int hits = 0;

                      for (final p in pagesRaw) {
                        final pageIndex = (p['pageIndex'] as num?)?.toInt() ?? 0;
                        final blocks = (p['blocks'] as List?)
                                ?.whereType<Map>()
                                .map((m) => OcrBlockBox.fromJson(Map<String, dynamic>.from(m)))
                                .toList() ??
                            [];
                        final anns = PiiRedactor.buildRedactionAnnotations(
                          pageIndex: pageIndex,
                          blocks: blocks,
                          enabledKinds: kinds,
                        );
                        hits += anns.length;
                        if (anns.isNotEmpty) {
                          grouped[pageIndex.toString()] = anns.map((a) => a.toJson()).toList();
                        }
                      }

                      if (hits == 0) {
                        if (context.mounted) {
                          showKagitSnack(context, 'Seçili kategorilerde hassas PII verisi bulunmadı.');
                        }
                        return;
                      }

                      final out = await controller.assembleDocument(
                        newTitle: '${doc.title} (Karartılmış)',
                        sourcePath: doc.path,
                        annotationsByPage: grouped,
                        tags: const ['Karartılmış'],
                      );
                      if (context.mounted) {
                        showKagitSnack(context, '$hits hassas alan siyah şeritle yakıldı.');
                        openKagitViewer(context, controller, out);
                      }
                    });
                  },
            child: const Text('Tara ve Karart'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showCompareDialog(BuildContext context, KagitController controller, KitaplikOgesi firstDoc) async {
  final second = await showPickDocumentSheet(
    context,
    controller,
    title: '"${firstDoc.title}" ile Karşılaştırılacak Belgeyi Seçin',
  );
  if (second == null || !context.mounted) return;

  late String report;
  await _runBusy(context, 'İki belge satır bazında karşılaştırılıyor...', () async {
    final t1 = await controller.ensureTextExtracted(firstDoc);
    final t2 = await controller.ensureTextExtracted(second);
    report = KagitDocumentExporters.compareDocuments(
      firstTitle: firstDoc.title,
      firstText: t1,
      secondTitle: second.title,
      secondText: t2,
    );
  });

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Belge Karşılaştırma'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: SingleChildScrollView(child: SelectableText(report)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
      ],
    ),
  );
}

Future<void> _showExamStackSplitDialog(BuildContext context, KagitController controller, KitaplikOgesi doc) async {
  int pagesPerStudent = 2;
  SinifGrubu? selectedClass = controller.siniflar.firstOrNull;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Sınav Yığınını Öğrenciye Göre Böl'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Belge: ${doc.title} (${doc.pageCount} sayfa)'),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Öğrenci Başına Sayfa: $pagesPerStudent', style: const TextStyle(fontWeight: FontWeight.w600)),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 6,
                    divisions: 5,
                    value: pagesPerStudent.toDouble(),
                    onChanged: (v) => setS(() => pagesPerStudent = v.round()),
                  ),
                ),
              ],
            ),
            if (controller.siniflar.isNotEmpty)
              DropdownButtonFormField<SinifGrubu?>(
                initialValue: selectedClass,
                decoration: const InputDecoration(
                  labelText: 'Sınıf Listesi ile Adlandır (Opsiyonel)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Sıra Numarasıyla (Öğrenci 1, 2...)')),
                  for (final s in controller.siniflar)
                    DropdownMenuItem(value: s, child: Text('${s.name} (${s.students.length} öğrenci)')),
                ],
                onChanged: (v) => setS(() => selectedClass = v),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _runBusy(context, 'Öğrenci kağıtları bölünüyor...', () async {
                int created = 0;
                int studentIdx = 0;
                for (int start = 0; start < doc.pageCount; start += pagesPerStudent) {
                  final end = (start + pagesPerStudent).clamp(0, doc.pageCount);
                  final entries = [
                    for (int p = start; p < end; p++) {'path': doc.path, 'pageIndex': p, 'rotateDeg': 0},
                  ];
                  String name;
                  if (selectedClass != null && studentIdx < selectedClass!.students.length) {
                    final st = selectedClass!.students[studentIdx];
                    name = '${st.no} ${st.adSoyad} - Sınav';
                  } else {
                    name = 'Öğrenci ${studentIdx + 1} - ${doc.title}';
                  }
                  await controller.assembleDocument(
                    newTitle: name,
                    pageEntries: entries,
                    tags: const ['Sınav Kâğıdı'],
                  );
                  created++;
                  studentIdx++;
                }
                if (context.mounted) showKagitSnack(context, '$created öğrenci kâğıdı kitaplığa eklendi.');
              });
            },
            child: const Text('Yığını Böl'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showAbBookletDialog(
  BuildContext context,
  KagitController controller, {
  KitaplikOgesi? sourceDoc,
}) async {
  final initialQs = sourceDoc?.cachedOcrText?.trim().isNotEmpty == true
      ? sourceDoc!.cachedOcrText!
      : '''1. Cumhuriyet Dönemi Türk Edebiyatı'nın temel özelliklerinden iki tanesini yazınız.

2. Karadeniz Bölgesi'nde dağların kıyıya paralel uzanmasının iklim üzerindeki etkisi nedir?

3. x² - 5x + 6 = 0 denkleminin kökler toplamı kaçtır?
A) 2   B) 3   C) 5   D) 6

4. Türkiye'nin en uzun nehri aşağıdakilerden hangisidir?
A) Fırat   B) Kızılırmak   C) Sakarya   D) Yeşilırmak''';

  final titleCtrl = TextEditingController(text: controller.ayarlar.okulBasligi.dersAdi);
  final questionsCtrl = TextEditingController(text: initialQs);
  final seedCtrl = TextEditingController(text: '2026');

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('A / B Kitapçığı & Cevap Anahtarı Üret', style: kagitSerif(ctx, size: 18)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Sınav Adı', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: seedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Tohum (Seed)', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: questionsCtrl,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    labelText: 'Sorular (1., 2., 3. biçiminde ayırın)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () async {
                  final qs = KitapcikGenerator.parseQuestions(questionsCtrl.text);
                  if (qs.length < 2) {
                    showKagitSnack(ctx, 'En az 2 soru girin.', isError: true);
                    return;
                  }
                  final exam = titleCtrl.text.trim().isEmpty ? 'Sınav' : titleCtrl.text.trim();
                  final seed = int.tryParse(seedCtrl.text.trim()) ?? 2026;
                  final sonuc = KitapcikGenerator.generate(questions: qs, examTitle: exam, seed: seed);
                  Navigator.pop(ctx);

                  await _runBusy(context, 'A/B kitapçıkları ve cevap anahtarı PDF yapılıyor...', () async {
                    final docA = await controller.createTextOrBlankPdf(
                      title: '$exam — A Kitapçığı',
                      subtitle: 'A Kitapçığı • Öğrenci Nüshası',
                      body: sonuc.aMetni,
                      schoolHeader: controller.ayarlar.okulBasligi,
                    );
                    await controller.createTextOrBlankPdf(
                      title: '$exam — B Kitapçığı',
                      subtitle: 'B Kitapçığı • Tohum $seed',
                      body: sonuc.bMetni,
                      schoolHeader: controller.ayarlar.okulBasligi,
                    );
                    await controller.createTextOrBlankPdf(
                      title: '$exam — Kitapçık Anahtarı',
                      subtitle: 'Eşleştirme Tablosu',
                      body: sonuc.cevapAnahtariMetni,
                    );
                    if (context.mounted) {
                      showKagitSnack(context, 'A Kitapçığı, B Kitapçığı ve Eşleştirme Anahtarı kitaplığa eklendi.');
                      openKagitViewer(context, controller, docA);
                    }
                  });
                },
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('A, B Kitapçığı ve Anahtarı Oluştur'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  titleCtrl.dispose();
  questionsCtrl.dispose();
  seedCtrl.dispose();
}

Future<void> _showSchoolHeaderStampDialog(
  BuildContext context,
  KagitController controller,
  KitaplikOgesi doc,
) async {
  final h = controller.ayarlar.okulBasligi;
  final okul = TextEditingController(text: h.okulAdi);
  final ders = TextEditingController(text: h.dersAdi);
  final tur = TextEditingController(text: h.sinavTuru);
  final sure = TextEditingController(text: h.sure);

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('İlk Sayfaya Okul Sınav Başlığı Ekle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: okul, decoration: const InputDecoration(labelText: 'Okul / Kurum', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: ders, decoration: const InputDecoration(labelText: 'Ders', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: tur, decoration: const InputDecoration(labelText: 'Sınav Türü', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: sure, decoration: const InputDecoration(labelText: 'Süre', border: OutlineInputBorder())),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await _runBusy(context, 'Okul sınav başlığı ilk sayfaya yerleştiriliyor...', () async {
              final out = await controller.assembleDocument(
                newTitle: '${doc.title} (Sınav Başlıklı)',
                sourcePath: doc.path,
                schoolHeader: {
                  'enabled': true,
                  'okulAdi': okul.text.trim(),
                  'dersAdi': ders.text.trim(),
                  'sinavTuru': tur.text.trim(),
                  'tarih': h.tarih,
                  'sure': sure.text.trim(),
                },
              );
              if (context.mounted) openKagitViewer(context, controller, out);
            });
          },
          child: const Text('Başlık Bas'),
        ),
      ],
    ),
  );
  okul.dispose();
  ders.dispose();
  tur.dispose();
  sure.dispose();
}

Future<void> _showPointsExcelDialog(BuildContext context, KagitController controller) async {
  final rows = <OgrenciPuanSatiri>[];
  for (final doc in controller.activeItems) {
    final anns = controller.annotationsFor(doc.id);
    final sum = PuanParser.sumAnnotations(anns);
    final (no, ad) = PuanParser.parseStudentFilename(doc.title);
    if (anns.any((a) => a.kind == AnnotationKind.puan) || doc.tags.contains('Sınav Kâğıdı')) {
      rows.add(OgrenciPuanSatiri(no: no, adSoyad: ad, puan: sum, notlar: '${doc.pageCount} sayfa'));
    }
  }

  if (rows.isEmpty && controller.siniflar.isNotEmpty) {
    for (final st in controller.siniflar.first.students) {
      rows.add(OgrenciPuanSatiri(no: st.no, adSoyad: st.adSoyad, puan: 0, notlar: controller.siniflar.first.name));
    }
  }

  final editableScores = List<TextEditingController>.generate(
    rows.length,
    (i) => TextEditingController(text: rows[i].puan.toStringAsFixed(rows[i].puan % 1 == 0 ? 0 : 1)),
  );
  final titleCtrl = TextEditingController(text: '${controller.ayarlar.okulBasligi.dersAdi} Puan Listesi');

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.8,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Puan Topla → Excel (.xlsx)', style: kagitSerif(ctx, size: 18)),
              const SizedBox(height: 8),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Rapor Başlığı', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    leading: Text(rows[i].no, style: const TextStyle(fontWeight: FontWeight.w700)),
                    title: Text(rows[i].adSoyad),
                    subtitle: Text(rows[i].notlar),
                    trailing: SizedBox(
                      width: 78,
                      child: TextField(
                        controller: editableScores[i],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(labelText: 'Puan', isDense: true, border: OutlineInputBorder()),
                      ),
                    ),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final finalRows = [
                    for (int i = 0; i < rows.length; i++)
                      OgrenciPuanSatiri(
                        no: rows[i].no,
                        adSoyad: rows[i].adSoyad,
                        puan: double.tryParse(editableScores[i].text.replaceAll(',', '.')) ?? rows[i].puan,
                        notlar: rows[i].notlar,
                      ),
                  ];
                  final bytes = KagitDocumentExporters.buildXlsxScores(
                    title: titleCtrl.text.trim(),
                    rows: finalRows,
                  );
                  final fileName = '${titleCtrl.text.trim()}.xlsx';
                  final path = await controller.writeExportBytes(fileName, bytes);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    final saved = await controller.saveFileToUserLocation(
                      path,
                      fileName,
                      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                    );
                    if (!saved && context.mounted) {
                      await controller.shareFile(
                        path,
                        title: fileName,
                        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                      );
                    }
                  }
                },
                icon: const Icon(Icons.table_chart_rounded),
                label: const Text('Excel (.xlsx) Oluştur & Dışa Aktar'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  for (final c in editableScores) {
    c.dispose();
  }
  titleCtrl.dispose();
}

Future<void> _showAiToolSheet(
  BuildContext context,
  KagitController controller,
  KagitToolId toolId,
  KitaplikOgesi? doc,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _AiWorkspaceSheet(
      controller: controller,
      toolId: toolId,
      doc: doc,
    ),
  );
}

class _AiWorkspaceSheet extends StatefulWidget {
  const _AiWorkspaceSheet({
    required this.controller,
    required this.toolId,
    this.doc,
  });

  final KagitController controller;
  final KagitToolId toolId;
  final KitaplikOgesi? doc;

  @override
  State<_AiWorkspaceSheet> createState() => _AiWorkspaceSheetState();
}

class _AiWorkspaceSheetState extends State<_AiWorkspaceSheet> {
  final TextEditingController _inputCtrl = TextEditingController();
  final List<KagitAiMessage> _thread = [];
  String _resultText = '';
  String _targetLang = 'İngilizce';
  int _qCount = 5;
  String _difficulty = 'Orta';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.toolId == KagitToolId.aiOzetle || widget.toolId == KagitToolId.aiCevir) {
      Future.microtask(_runSingleShot);
    } else if (widget.toolId == KagitToolId.aiSoruUret) {
      _inputCtrl.text = widget.doc?.title ?? '${widget.controller.ayarlar.okulBasligi.dersAdi} konusu';
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<String> _getDocTextOrEmpty() async {
    final doc = widget.doc;
    if (doc == null) return '';
    return widget.controller.ensureTextExtracted(doc);
  }

  Future<void> _runSingleShot() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ai = widget.controller.aiService;
      if (widget.toolId == KagitToolId.aiOzetle) {
        final txt = await _getDocTextOrEmpty();
        final out = await ai.ozetle(txt.isEmpty ? (widget.doc?.title ?? '') : txt, title: widget.doc?.title ?? 'Belge');
        setState(() => _resultText = out);
      } else if (widget.toolId == KagitToolId.aiCevir) {
        final txt = await _getDocTextOrEmpty();
        final out = await ai.cevir(txt.isEmpty ? (widget.doc?.title ?? '') : txt, targetLanguage: _targetLang);
        setState(() => _resultText = out);
      } else if (widget.toolId == KagitToolId.aiSoruUret) {
        final docTxt = await _getDocTextOrEmpty();
        final combined = docTxt.isNotEmpty
            ? '${_inputCtrl.text.trim()}\n\nKaynak Metin:\n$docTxt'
            : _inputCtrl.text.trim();
        final out = await ai.soruUret(topicOrText: combined, count: _qCount, difficulty: _difficulty);
        setState(() => _resultText = out);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendChat() async {
    final q = _inputCtrl.text.trim();
    if (q.isEmpty) return;
    _inputCtrl.clear();
    setState(() {
      _thread.add(KagitAiMessage(isUser: true, text: q));
      _busy = true;
      _error = null;
    });
    try {
      final docTxt = await _getDocTextOrEmpty();
      final reply = await widget.controller.aiService.belgeyeSor(docTxt, _thread);
      setState(() => _thread.add(KagitAiMessage(isUser: false, text: reply)));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ai = widget.controller.aiService;
    final title = kagitToolsCatalog.firstWhere((t) => t.id == widget.toolId).title;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.86,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.of(context).viewInsets.bottom + 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: kagitSerif(context, size: 18))),
                  ActionChip(
                    avatar: const Icon(Icons.hub_outlined, size: 16, color: KagitTema.morOkuma),
                    label: Text(ai.config.selectedModelId, style: const TextStyle(fontSize: 11.5)),
                    onPressed: () async {
                      await showAiModelPickerSheet(context, widget.controller);
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
              if (widget.toolId == KagitToolId.aiCevir)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Text('Hedef Dil: '),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'Türkçe', label: Text('Türkçe')),
                          ButtonSegment(value: 'İngilizce', label: Text('İngilizce')),
                        ],
                        selected: {_targetLang},
                        onSelectionChanged: (s) {
                          setState(() => _targetLang = s.first);
                          _runSingleShot();
                        },
                      ),
                    ],
                  ),
                ),
              if (widget.toolId == KagitToolId.aiSoruUret) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _inputCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Konu veya Yönerge',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    DropdownButton<int>(
                      value: _qCount,
                      items: [for (final n in [3, 5, 10, 15]) DropdownMenuItem(value: n, child: Text('$n Soru'))],
                      onChanged: (v) => setState(() => _qCount = v ?? 5),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _difficulty,
                      items: [
                        for (final d in ['Kolay', 'Orta', 'Zor']) DropdownMenuItem(value: d, child: Text(d)),
                      ],
                      onChanged: (v) => setState(() => _difficulty = v ?? 'Orta'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _busy ? null : _runSingleShot,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                      label: const Text('Soru Üret'),
                    ),
                  ],
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                  ),
                ),
              const SizedBox(height: 10),
              Expanded(
                child: widget.toolId == KagitToolId.aiSohbet
                    ? ListView.builder(
                        itemCount: _thread.length,
                        itemBuilder: (_, i) {
                          final m = _thread[i];
                          return Align(
                            alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                              decoration: BoxDecoration(
                                color: m.isUser ? KagitTema.vurgu : KagitTema.softBg(context),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: SelectableText(
                                m.text,
                                style: TextStyle(color: m.isUser ? Colors.white : KagitTema.inkPrimary(context)),
                              ),
                            ),
                          );
                        },
                      )
                    : Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: KagitTema.softBg(context),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _busy
                            ? const Center(child: CircularProgressIndicator())
                            : SingleChildScrollView(
                                child: SelectableText(
                                  _resultText.isEmpty ? 'Yanıt burada görünecek.' : _resultText,
                                  style: const TextStyle(height: 1.48),
                                ),
                              ),
                      ),
              ),
              if (widget.toolId == KagitToolId.aiSohbet) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Belgeye sayfa referanslı soru sorun...',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _sendChat(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _sendChat,
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ] else if (_resultText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _resultText));
                          showKagitSnack(context, 'Panoya kopyalandı.');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 17),
                        label: const Text('Kopyala'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          final pdf = await widget.controller.createTextOrBlankPdf(
                            title: '${widget.doc?.title ?? "Kâğıt"} — $title',
                            subtitle: 'Model: ${ai.config.selectedModelId}',
                            body: _resultText,
                            schoolHeader: widget.toolId == KagitToolId.aiSoruUret
                                ? widget.controller.ayarlar.okulBasligi
                                : null,
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                            openKagitViewer(context, widget.controller, pdf);
                          }
                        },
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 17),
                        label: const Text('PDF Olarak Kaydet'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
