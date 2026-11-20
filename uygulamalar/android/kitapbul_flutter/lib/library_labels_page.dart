import 'dart:convert';

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';

import 'app_theme_settings.dart';
import 'book_visuals.dart';
import 'catalog_search.dart';

String upperTurkish(String input) {
  return input
      .replaceAll('i', 'İ')
      .replaceAll('ı', 'I')
      .replaceAll('ğ', 'Ğ')
      .replaceAll('ü', 'Ü')
      .replaceAll('ş', 'Ş')
      .replaceAll('ö', 'Ö')
      .replaceAll('ç', 'Ç')
      .toUpperCase();
}

List<String> extractAccessionTokens(Map<String, dynamic> book) {
  final raw = (book['accessionCode'] ?? '').toString().trim();
  if (raw.isEmpty) return const [];
  return raw
      .split(RegExp(r'[;,]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

({String top, String bottom, String colorHex, Color color}) computeCallNumber(
  Map<String, dynamic> book,
) {
  final orig = book['iphoneOriginal'];
  final dewey = orig is Map && orig['location'] is String
      ? (orig['location'] as String).trim()
      : '';
  final category = (book['category'] ?? '').toString().trim();
  final foldedCat = foldTurkish(category);

  String top;
  String hex;
  if (dewey.isNotEmpty && RegExp(r'^\d').hasMatch(dewey)) {
    top = dewey;
    hex = '#1D4ED8';
  } else if (foldedCat.contains('tarih')) {
    top = 'TAR';
    hex = '#B45309';
  } else if (foldedCat.contains('turk edebiyat') ||
      foldedCat.contains('türk edebiyat')) {
    top = 'TÜR';
    hex = '#BE123C';
  } else if (foldedCat.contains('dunya edebiyat') ||
      foldedCat.contains('dünya edebiyat')) {
    top = 'DÜN';
    hex = '#4F46E5';
  } else if (foldedCat.contains('roman') || foldedCat.contains('hikaye') || foldedCat.contains('öykü')) {
    top = 'ROM';
    hex = '#7C3AED';
  } else if (foldedCat.contains('bilim') || foldedCat.contains('doga')) {
    top = 'BİL';
    hex = '#0284C7';
  } else if (foldedCat.contains('din') || foldedCat.contains('inanc')) {
    top = 'DİN';
    hex = '#059669';
  } else if (foldedCat.contains('biyografi') || foldedCat.contains('ani')) {
    top = 'BİY';
    hex = '#D97706';
  } else if (foldedCat.contains('felsefe') || foldedCat.contains('psikoloji')) {
    top = 'FEL';
    hex = '#6D28D9';
  } else if (foldedCat.contains('siir') || foldedCat.contains('şiir')) {
    top = 'Şİİ';
    hex = '#DB2777';
  } else if (category.isNotEmpty) {
    final letters = upperTurkish(
      category.replaceAll(RegExp(r'[^A-Za-zÇĞİÖŞÜçğıöşü]'), ''),
    );
    top = letters.length >= 3
        ? letters.substring(0, 3)
        : (letters.isEmpty ? 'GEN' : letters);
    hex = '#334155';
  } else {
    top = 'GEN';
    hex = '#475569';
  }

  final author = (book['author'] ?? '').toString().trim();
  String bottom = '---';
  if (author.isNotEmpty) {
    final parts = author
        .split(RegExp(r'[\s,;/-]+'))
        .map((p) => p.replaceAll(RegExp(r'[^A-Za-zÇĞİÖŞÜçğıöşü]'), ''))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) {
      final surname = upperTurkish(parts.last);
      bottom = surname.length >= 3 ? surname.substring(0, 3) : surname;
    }
  }

  final colorVal = int.parse('FF${hex.substring(1)}', radix: 16);
  return (top: top, bottom: bottom, colorHex: hex, color: Color(colorVal));
}

String asciiSafeCode128(String input) {
  final clean = input
      .replaceAll('İ', 'I')
      .replaceAll('ı', 'i')
      .replaceAll('Ğ', 'G')
      .replaceAll('ğ', 'g')
      .replaceAll('Ü', 'U')
      .replaceAll('ü', 'u')
      .replaceAll('Ş', 'S')
      .replaceAll('ş', 's')
      .replaceAll('Ö', 'O')
      .replaceAll('ö', 'o')
      .replaceAll('Ç', 'C')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  return clean.trim().isEmpty ? 'CAL-000000' : clean.trim();
}

List<List<double>> buildCode128Bars(String rawCode) {
  final safe = asciiSafeCode128(rawCode);
  return Barcode.code128()
      .make(safe, width: 1.0, height: 1.0)
      .whereType<BarcodeBar>()
      .where((b) => b.black)
      .map((b) => [b.left, b.width])
      .toList();
}

List<String> buildQrMatrixRows(String data) {
  final qrCode = QrCode.fromUint8List(
    data: Uint8List.fromList(utf8.encode(data)),
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final img = QrImage(qrCode);
  final n = img.moduleCount;
  final rows = <String>[];
  for (var r = 0; r < n; r++) {
    final sb = StringBuffer();
    for (var c = 0; c < n; c++) {
      sb.write(img.isDark(r, c) ? '1' : '0');
    }
    rows.add(sb.toString());
  }
  return rows;
}

enum LabelTemplateKind {
  standard('standard', 'Demirbaş Barkod Etiketi', 'A4 · 3×7 (21 adet/sayfa)'),
  spine('spine', 'Renkli Sırt Etiketi', 'A4 · 3×8 (24 adet/sayfa)'),
  qrCard('qrCard', 'QR Kodlu Kitap Kartı', 'A4 · 2×5 (10 adet/sayfa)');

  const LabelTemplateKind(this.id, this.title, this.subtitle);
  final String id;
  final String title;
  final String subtitle;
}

List<Map<String, dynamic>> buildLabelsPayloadItems(
  List<Map<String, dynamic>> books, {
  required LabelTemplateKind template,
  bool expandMultipleCopies = false,
}) {
  final items = <Map<String, dynamic>>[];
  for (final b in books) {
    final call = computeCallNumber(b);
    final rawShelf = (b['shelf'] ?? '').toString().trim();
    final shelfLabel = rawShelf.isEmpty
        ? 'GENEL'
        : (rawShelf.length <= 2 ? 'DOLAP $rawShelf' : rawShelf);
    final isbn = (b['isbn'] ?? '').toString().trim();
    final idShort = (b['id'] ?? 'KITAP').toString().split('-').first.toUpperCase();
    final tokens = extractAccessionTokens(b);
    final copyCodes = expandMultipleCopies && tokens.length > 1
        ? tokens
        : [tokens.isNotEmpty ? tokens.first : (isbn.isNotEmpty ? isbn : 'KTP-$idShort')];

    for (final code in copyCodes) {
      final barcodeValue = code.isNotEmpty
          ? code
          : (isbn.isNotEmpty ? isbn : 'KTP-$idShort');
      final qrValue = 'KITAP:${b['id']}|DEM:$barcodeValue|ISBN:$isbn';
      items.add({
        'callTop': call.top,
        'callBottom': call.bottom,
        'shelf': shelfLabel,
        'title': (b['title'] ?? '').toString(),
        'author': (b['author'] ?? '').toString(),
        'category': (b['category'] ?? '').toString(),
        'accession': code,
        'barcodeText': barcodeValue,
        'color': call.colorHex,
        if (template != LabelTemplateKind.spine)
          'bars': buildCode128Bars(barcodeValue),
        if (template == LabelTemplateKind.qrCard)
          'qr': buildQrMatrixRows(qrValue),
      });
    }
  }
  return items;
}

class LibraryLabelsPage extends StatefulWidget {
  const LibraryLabelsPage({super.key, required this.books});

  final List<Map<String, dynamic>> books;

  @override
  State<LibraryLabelsPage> createState() => _LibraryLabelsPageState();
}

class _LibraryLabelsPageState extends State<LibraryLabelsPage> {
  LabelTemplateKind _template = LabelTemplateKind.standard;
  String _selectedShelf = '';
  String _query = '';
  bool _onlyWithAccession = false;
  bool _expandCopies = true;
  bool _saving = false;
  final Set<String> _deselectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfg = appThemeNotifier.value;
    final activeBooks = widget.books
        .where((b) => b['deletedAt'] == null && b['isWithdrawn'] != true)
        .toList();

    final shelfCounts = <String, int>{};
    for (final b in activeBooks) {
      final s = (b['shelf'] ?? '').toString().trim();
      if (s.isNotEmpty) shelfCounts[s] = (shelfCounts[s] ?? 0) + 1;
    }
    final shelves = shelfCounts.keys.toList()..sort();

    final filtered = activeBooks.where((b) {
      if (_selectedShelf.isNotEmpty &&
          (b['shelf'] ?? '').toString().trim() != _selectedShelf) {
        return false;
      }
      if (_onlyWithAccession &&
          (b['accessionCode'] ?? '').toString().trim().isEmpty) {
        return false;
      }
      if (_query.trim().isNotEmpty && !matchesCatalog(b, _query)) {
        return false;
      }
      return true;
    }).toList();

    final selectedBooks = filtered
        .where((b) => !_deselectedIds.contains(b['id']))
        .toList();

    final previewBook = selectedBooks.isNotEmpty
        ? selectedBooks.first
        : (filtered.isNotEmpty
              ? filtered.first
              : <String, dynamic>{
                  'id': 'DEMO-001',
                  'title': 'Devlet-i Aliyye',
                  'author': 'Halil İnalcık',
                  'category': 'Tarih',
                  'shelf': 'N',
                  'accessionCode': 'CAL-001781',
                  'isbn': '9789944886451',
                });

    return Scaffold(
      appBar: AppBar(title: const Text('Sırt Etiketi, Barkod & QR Baskı')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          IllustratedBannerCard(
            imageAsset: 'assets/images/label_print_banner.jpg',
            title: 'Etiket, Barkod & QR Baskı Merkezi',
            subtitle:
                'A4 vektörel sırt etiketi, demirbaş barkodu ve QR kitap kimlik kartları',
            icon: Icons.qr_code_2_rounded,
            gradientColors: const [Color(0xFF4C1D95), Color(0xFF7C3AED)],
            pills: [
              AnimatedStatPill(
                label: 'Seçili Kitap',
                value: selectedBooks.length,
                icon: Icons.check_box_rounded,
                accentColor: const Color(0xFFFDE68A),
              ),
              AnimatedStatPill(
                label: 'Dolap Sayısı',
                value: shelves.length,
                icon: Icons.shelves,
                accentColor: const Color(0xFF6EE7B7),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '1. Etiket Şablonu Seçin',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final kind in LabelTemplateKind.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BouncyTap(
                onTap: () => setState(() => _template = kind),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: _template == kind
                        ? scheme.primaryContainer.withValues(alpha: 0.65)
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _template == kind
                          ? scheme.primary
                          : scheme.outlineVariant.withValues(alpha: 0.5),
                      width: _template == kind ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        kind == LabelTemplateKind.spine
                            ? Icons.bookmark_rounded
                            : kind == LabelTemplateKind.qrCard
                            ? Icons.qr_code_scanner_rounded
                            : Icons.view_week_rounded,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kind.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              kind.subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_template == kind)
                        Icon(Icons.check_circle_rounded, color: scheme.primary),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Canlı Etiket Önizlemesi',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _LiveLabelPreview(
            book: previewBook,
            template: _template,
            schoolName: cfg.schoolName,
            libraryName: cfg.libraryName,
          ),
          const SizedBox(height: 16),
          Text(
            '2. Basılacak Kitapları Filtreleyin',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedShelf,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Dolap / Raf Seçimi',
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text('Tüm Dolaplar (${activeBooks.length})'),
                    ),
                    for (final s in shelves)
                      DropdownMenuItem(
                        value: s,
                        child: Text(
                          '${s.length <= 2 ? 'Dolap $s' : s} (${shelfCounts[s]})',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedShelf = v ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Kitap, yazar, demirbaş (CAL-...) veya ISBN filtrele...',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Yalnız demirbaş kodu olan kitaplar'),
            value: _onlyWithAccession,
            onChanged: (v) => setState(() => _onlyWithAccession = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Çoklu demirbaş kodları için ayrı etiket bas'),
            subtitle: const Text(
              'Örn. CAL-004057; CAL-004058 olan kitap için 2 ayrı barkod basar',
            ),
            value: _expandCopies,
            onChanged: (v) => setState(() => _expandCopies = v),
          ),
          const SizedBox(height: 8),
          ShimmerActionButton(
            label: _saving
                ? 'Vektörel A4 PDF Üretiliyor...'
                : 'Seçili ${selectedBooks.length} Kitabı A4 PDF Kaydet',
            subtitle: '${_template.title} · Kesim çizgili yüksek çözünürlük',
            icon: Icons.print_rounded,
            colors: const [Color(0xFF4F46E5), Color(0xFF7C3AED)],
            onTap: _saving || selectedBooks.isEmpty
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      final items = buildLabelsPayloadItems(
                        selectedBooks,
                        template: _template,
                        expandMultipleCopies: _expandCopies,
                      );
                      final payload = jsonEncode({
                        'template': _template.id,
                        'schoolName': cfg.schoolName,
                        'libraryName': cfg.libraryName,
                        'items': items,
                      });
                      final ok = await const MethodChannel('kitapbul/files')
                          .invokeMethod<bool>('exportSpineLabelsPdf', {
                            'data': payload,
                            'filename':
                                'Kutuphane_Etiket_${_template.id}.pdf',
                          });
                      if (context.mounted && ok == true) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${items.length} etiket A4 PDF olarak kaydedildi.',
                            ),
                          ),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Etiket PDF dosyası kaydedilemedi.'),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Baskı Listesi (${selectedBooks.length}/${filtered.length})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _deselectedIds.clear()),
                child: const Text('Tümünü Seç'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  for (final b in filtered) {
                    _deselectedIds.add(b['id'] as String);
                  }
                }),
                child: const Text('Temizle'),
              ),
            ],
          ),
          for (final b in filtered.take(60))
            Builder(
              builder: (_) {
                final id = b['id'] as String;
                final checked = !_deselectedIds.contains(id);
                final call = computeCallNumber(b);
                final acc = (b['accessionCode'] ?? '').toString().trim();
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: checked,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _deselectedIds.remove(id);
                    } else {
                      _deselectedIds.add(id);
                    }
                  }),
                  secondary: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: call.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: call.color),
                    ),
                    child: Text(
                      '${call.top}/${call.bottom}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: call.color,
                      ),
                    ),
                  ),
                  title: Text(
                    '${b['title'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      if ((b['shelf'] ?? '').toString().isNotEmpty)
                        'Dolap ${b['shelf']}',
                      if (acc.isNotEmpty) acc else 'ISBN: ${b['isbn'] ?? '-'}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          if (filtered.length > 60)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '… ve ${filtered.length - 60} kitap daha seçime dahildir (PDF çıktısında tamamı yer alır).',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveLabelPreview extends StatelessWidget {
  const _LiveLabelPreview({
    required this.book,
    required this.template,
    required this.schoolName,
    required this.libraryName,
  });

  final Map<String, dynamic> book;
  final LabelTemplateKind template;
  final String schoolName;
  final String libraryName;

  @override
  Widget build(BuildContext context) {
    final call = computeCallNumber(book);
    final tokens = extractAccessionTokens(book);
    final code = tokens.isNotEmpty
        ? tokens.first
        : ((book['isbn'] ?? 'CAL-000001').toString());
    final rawShelf = (book['shelf'] ?? '').toString().trim();
    final shelf = rawShelf.isEmpty
        ? 'DOLAP N'
        : (rawShelf.length <= 2 ? 'DOLAP $rawShelf' : rawShelf);
    final bars = buildCode128Bars(code);

    return Center(
      child: Container(
        width: template == LabelTemplateKind.spine ? 190 : 320,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.blueGrey.shade200, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: call.color.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: template == LabelTemplateKind.spine
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: call.color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      shelf,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    call.top,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  Text(
                    call.bottom,
                    style: TextStyle(
                      color: call.color,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                    ),
                  ),
                  const Divider(height: 16),
                  Text(
                    code,
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: call.color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      upperTurkish('$schoolName · $libraryName'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${call.top} / ${call.bottom}  ·  $shelf',
                              style: TextStyle(
                                color: call.color,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${book['title'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                            Text(
                              '${book['author'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 30,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: _BarcodePreviewPainter(bars),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              code,
                              style: const TextStyle(
                                color: Color(0xFF1E293B),
                                fontWeight: FontWeight.w800,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (template == LabelTemplateKind.qrCard) ...[
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 74,
                          height: 74,
                          child: CustomPaint(
                            painter: _QrPreviewPainter(
                              buildQrMatrixRows(
                                'KITAP:${book['id']}|DEM:$code',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _BarcodePreviewPainter extends CustomPainter {
  const _BarcodePreviewPainter(this.bars);
  final List<List<double>> bars;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (final seg in bars) {
      if (seg.length != 2) continue;
      final left = size.width * seg[0];
      final w = size.width * seg[1];
      canvas.drawRect(Rect.fromLTWH(left, 0, w, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePreviewPainter oldDelegate) =>
      oldDelegate.bars != bars;
}

class _QrPreviewPainter extends CustomPainter {
  const _QrPreviewPainter(this.rows);
  final List<String> rows;

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty) return;
    final n = rows.length;
    final cell = size.width / n;
    final p = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var r = 0; r < n; r++) {
      final row = rows[r];
      for (var c = 0; c < row.length && c < n; c++) {
        if (row.codeUnitAt(c) == 0x31) {
          canvas.drawRect(
            Rect.fromLTWH(c * cell, r * cell, cell + 0.2, cell + 0.2),
            p,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPreviewPainter oldDelegate) =>
      oldDelegate.rows != rows;
}
