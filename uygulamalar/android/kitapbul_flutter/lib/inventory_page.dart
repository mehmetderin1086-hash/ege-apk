import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog_csv.dart';
import 'catalog_search.dart';
import 'continuous_scanner_page.dart';
import 'inventory_session.dart';
import 'isbn.dart';
import 'isbn_scanner.dart';

enum InventoryFilter {
  all('Tümü'),
  missing('Eksikler'),
  uncounted('Hiç sayılmayanlar'),
  surplus('Fazlalar'),
  exact('Tamamlananlar');

  const InventoryFilter(this.label);
  final String label;
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({
    super.key,
    required this.books,
    required this.initialSession,
    required this.save,
    this.currentBooks,
    this.initialHistory = const [],
    this.archive,
    this.registerUnknownBarcode,
    this.readOnly = false,
  });

  final List<Map<String, dynamic>> books;
  final List<Map<String, dynamic>> Function()? currentBooks;
  final InventorySession? initialSession;
  final List<InventoryArchive> initialHistory;
  final bool readOnly;
  final Future<bool> Function(
    InventorySession session,
    List<InventoryArchive> previous,
    List<InventoryArchive> next,
  )?
  archive;
  final Future<bool> Function(
    InventorySession? previous,
    InventorySession? next,
  )
  save;

  /// Registers an unknown barcode into the library catalog and updates both catalog & session.
  final Future<InventorySession?> Function(
    InventorySession currentSession,
    String barcode,
    int scannedCount,
  )?
  registerUnknownBarcode;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final name = TextEditingController(text: 'Envanter sayımı');
  final operatorName = TextEditingController();
  final barcode = TextEditingController();
  final filterSearch = TextEditingController();
  InventorySession? session;
  late List<InventoryArchive> history;
  bool busy = false;
  String selectedLocation = '';
  String searchQuery = '';
  InventoryFilter activeFilter = InventoryFilter.all;

  @override
  void initState() {
    super.initState();
    session = widget.initialSession;
    history = List.of(widget.initialHistory);
  }

  @override
  void dispose() {
    name.dispose();
    operatorName.dispose();
    barcode.dispose();
    filterSearch.dispose();
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<bool> commit(InventorySession? next) async {
    if (busy) return false;
    setState(() => busy = true);
    final ok = await widget.save(session, next);
    if (!mounted) return false;
    setState(() {
      busy = false;
      if (ok) session = next;
    });
    if (!ok) {
      message(
        'Sayım kaydedilemedi veya kayıt başka yerde değişti. Sayfayı kapatıp tekrar açın.',
      );
    }
    return ok;
  }

  Future<void> scan(String input) async {
    if (session == null || busy) return;
    try {
      final next = recordInventoryScan(session!, input);
      final ok = await commit(next);
      if (ok && mounted) {
        barcode.clear();
        final lastEvent = next.events.lastOrNull;
        if (lastEvent != null && lastEvent['kind'] == 'unknown') {
          message('Tanınmayan barkod kaydedildi: ${lastEvent['key']}');
        }
      }
    } on FormatException catch (e) {
      message(e.message);
    } on StateError catch (e) {
      message(e.message);
    }
  }

  Future<void> openContinuousScanner() async {
    if (session == null || busy || widget.readOnly) return;
    await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ContinuousScannerPage(
          title: 'Seri envanter sayımı',
          isbnOnly: false,
          hintText:
              'Kitap ISBN veya nüsha demirbaş barkodlarını sırayla kameraya gösterin.',
          onBarcode: (code) async {
            final current = session;
            if (current == null) {
              return const ScanFeedback(
                title: 'Etkin sayım yok',
                severity: ScanSeverity.error,
              );
            }
            try {
              final next = recordInventoryScan(current, code);
              final ok = await commit(next);
              if (!ok) {
                return const ScanFeedback(
                  title: 'Sayım kaydedilemedi',
                  subtitle: 'Katalog başka yerde değişmiş olabilir.',
                  severity: ScanSeverity.error,
                );
              }
              final lastEvent = next.events.last;
              if (lastEvent['kind'] == 'unknown') {
                return ScanFeedback(
                  title: 'Tanınmayan barkod: ${lastEvent['key']}',
                  subtitle:
                      'Sayım ekranından tek dokunuşla kataloğa ekleyebilirsiniz.',
                  severity: ScanSeverity.warning,
                );
              }
              final rows = inventoryRows(next);
              InventoryRow? matchedRow;
              if (lastEvent['kind'] == 'copy') {
                final copyId = (lastEvent['key'] as String).toUpperCase();
                matchedRow = rows.where((r) {
                  return (r.entry['copies'] as List)
                      .cast<Map<String, dynamic>>()
                      .any(
                        (c) => (c['id'] as String).toUpperCase() == copyId,
                      );
                }).firstOrNull;
              } else if (lastEvent['kind'] == 'isbn') {
                final isbnKey = lastEvent['key'] as String;
                matchedRow = rows
                    .where(
                      (r) => canonicalIsbn(r.entry['isbn'] as String) == isbnKey,
                    )
                    .firstOrNull;
              }
              if (matchedRow != null) {
                final exp = matchedRow.entry['expected'] as int;
                final diff = matchedRow.count - exp;
                final status = diff == 0
                    ? 'Tamamlandı'
                    : (diff < 0 ? '${-diff} eksik kaldı' : '+$diff fazla');
                return ScanFeedback(
                  title: '${matchedRow.entry['title']}',
                  subtitle:
                      'Sayılan: ${matchedRow.count} / Beklenen: $exp · $status',
                  severity: diff > 0
                      ? ScanSeverity.warning
                      : ScanSeverity.success,
                );
              }
              return ScanFeedback(
                title: 'Barkod sayıldı: $code',
                severity: ScanSeverity.success,
              );
            } on StateError catch (e) {
              return ScanFeedback(
                title: e.message,
                subtitle: code,
                severity: ScanSeverity.warning,
              );
            } on FormatException catch (e) {
              return ScanFeedback(
                title: e.message,
                subtitle: code,
                severity: ScanSeverity.error,
              );
            }
          },
          onUndo: () async {
            final current = session;
            if (current == null || current.events.isEmpty) return null;
            final ok = await commit(undoInventory(current));
            return ok ? 'Son okutma geri alındı' : null;
          },
        ),
      ),
    );
  }

  Future<void> reset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sayımı sil?'),
        content: const Text(
          'Bu sayım ve okutma kayıtları silinir. Kitap stokları değişmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (yes == true) await commit(null);
  }

  Future<void> finish() async {
    final current = session;
    if (current == null || busy || widget.archive == null) return;
    final summary = summarizeInventory(current);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sayımı tamamla?'),
        content: Text(
          'Beklenen: ${summary.expectedTotal} · Sayılan: ${summary.countedTotal}\n'
          'Eksik nüsha: ${summary.missingCopies} · Fazla nüsha: ${summary.surplusCopies} · Tanınmayan: ${summary.unknownScans}\n\n'
          'Sayım geçmişe kaydedilir ve yeni bir sayım başlatılabilir. Stoklar değişmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tamamla'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final next = [
      ...history,
      InventoryArchive(
        finishedAt: DateTime.now().toIso8601String(),
        session: current,
      ),
    ];
    setState(() => busy = true);
    final ok = await widget.archive!(current, history, next);
    if (!mounted) return;
    setState(() {
      busy = false;
      if (ok) {
        history = next;
        session = null;
      }
    });
    message(
      ok
          ? 'Sayım geçmişe kaydedildi.'
          : 'Sayım kaydedilemedi veya başka yerde değişti.',
    );
  }

  Future<void> export() async {
    final current = session;
    if (current == null || busy) return;
    final lines = <List<String>>[
      [
        'Sayım',
        'Konum',
        'Görevli',
        'Başlangıç',
        'Kitap',
        'Yazar',
        'ISBN',
        'Beklenen',
        'Sayılan',
        'Kimlikli',
        'ISBN okutma',
        'Elle',
        'Fark',
      ],
      for (final row in inventoryRows(current))
        [
          current.name,
          current.location ?? 'Tümü',
          current.operatorName,
          current.startedAt,
          '${row.entry['title']}',
          '${row.entry['author']}',
          '${row.entry['isbn']}',
          '${row.entry['expected']}',
          '${row.count}',
          '${row.identified}',
          '${row.isbn}',
          '${row.manual}',
          '${row.count - (row.entry['expected'] as int)}',
        ],
      for (final e in current.events.where((e) => e['kind'] == 'unknown'))
        [
          current.name,
          current.location ?? 'Tümü',
          current.operatorName,
          current.startedAt,
          'Tanınmayan barkod',
          '',
          '${e['key']}',
          '',
          '',
          '',
          '',
          '',
          '',
        ],
    ];
    try {
      final saved = await const MethodChannel('kitapbul/files')
          .invokeMethod<bool>('exportCsv', {
            'data':
                '\ufeff${lines.map((line) => line.map(csvCell).join(';')).join('\r\n')}',
            'filename': 'EnvanterSayimi.csv',
          });
      if (saved == true) message('Sayım raporu kaydedildi.');
    } catch (_) {
      message('Sayım raporu kaydedilemedi.');
    }
  }

  Future<void> exportPdf() async {
    final current = session;
    if (current == null || busy) return;
    final data = jsonEncode({
      'name': current.name,
      'location': current.location ?? 'Tümü',
      'operator': current.operatorName,
      'startedAt': current.startedAt,
      'rows': [
        for (final row in inventoryRows(current))
          {
            'title': row.entry['title'],
            'author': row.entry['author'],
            'isbn': row.entry['isbn'],
            'expected': row.entry['expected'],
            'count': row.count,
            'difference': row.count - (row.entry['expected'] as int),
            'identified': row.identified,
            'isbnCount': row.isbn,
            'manual': row.manual,
          },
      ],
      'unknown': [
        for (final event in current.events.where((e) => e['kind'] == 'unknown'))
          event['key'],
      ],
    });
    try {
      final saved = await const MethodChannel('kitapbul/files')
          .invokeMethod<bool>('exportInventoryPdf', {
            'data': data,
            'filename': 'EnvanterSayimTutanagi.pdf',
          });
      if (saved == true) message('Sayım tutanağı kaydedildi.');
    } catch (_) {
      message('Sayım tutanağı kaydedilemedi.');
    }
  }

  bool _matchesRow(InventoryRow row) {
    final exp = row.entry['expected'] as int;
    final matchesFilter = switch (activeFilter) {
      InventoryFilter.all => true,
      InventoryFilter.missing => row.count < exp,
      InventoryFilter.uncounted => row.count == 0 && exp > 0,
      InventoryFilter.surplus => row.count > exp,
      InventoryFilter.exact => row.count == exp && exp > 0,
    };
    if (!matchesFilter) return false;
    final q = foldTurkish(searchQuery.trim());
    if (q.isEmpty) return true;
    final isbnKey = canonicalIsbn(searchQuery);
    if (isbnKey != null &&
        isbnKey == canonicalIsbn((row.entry['isbn'] ?? '').toString())) {
      return true;
    }
    final codes = (row.entry['copies'] as List)
        .cast<Map<String, dynamic>>()
        .map((c) => c['code'] ?? '')
        .join(' ');
    final haystack = foldTurkish(
      '${row.entry['title']} ${row.entry['author']} ${row.entry['isbn']} $codes',
    );
    return haystack.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final current = session;
    final allRows = current == null
        ? <InventoryRow>[]
        : inventoryRows(current);
    final filteredRows = allRows.where(_matchesRow).toList();
    final summary = current == null ? null : summarizeInventory(current);

    final unknownCounts = <String, int>{};
    for (final e in current?.events.where((e) => e['kind'] == 'unknown') ??
        const <Map<String, dynamic>>[]) {
      final k = (e['key'] as String).trim();
      unknownCounts[k] = (unknownCounts[k] ?? 0) + 1;
    }

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.readOnly ? 'Tamamlanan sayım' : 'Envanter sayımı'),
        actions: [
          if (current != null)
            IconButton(
              onPressed: busy ? null : exportPdf,
              tooltip: 'PDF tutanağı kaydet',
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          if (current != null)
            IconButton(
              onPressed: busy ? null : export,
              tooltip: 'CSV raporu kaydet',
              icon: const Icon(Icons.file_download_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!widget.readOnly && history.isNotEmpty) ...[
            ExpansionTile(
              title: Text('Tamamlanan sayımlar (${history.length})'),
              children: [
                for (final item in history.reversed)
                  ListTile(
                    title: Text(item.session.name),
                    subtitle: Text(
                      '${item.session.operatorName} · Tamamlandı: ${item.finishedAt.replaceAll("T", " ")}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => InventoryPage(
                          books: const [],
                          initialSession: item.session,
                          save: (_, _) async => false,
                          readOnly: true,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (current == null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 132,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/scanner_banner.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xFF1E1B4B),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF0F172A).withValues(alpha: 0.90),
                            const Color(0xFF0F172A).withValues(alpha: 0.30),
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Kameralı Akıllı Envanter Sayımı',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Seri kamera okutma, canlı fark analizi ve tanınmayan barkodları doğrudan kataloğa ekleme.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.86),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Sayım adı',
                prefixIcon: Icon(Icons.assignment_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: operatorName,
              decoration: const InputDecoration(
                labelText: 'Görevli adı soyadı *',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedLocation,
              decoration: const InputDecoration(
                labelText: 'Sayım konumu / raf',
                prefixIcon: Icon(Icons.shelves),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('Tüm konumlar')),
                for (final place in inventoryLocations(
                  widget.currentBooks?.call() ?? widget.books,
                ))
                  DropdownMenuItem(value: place, child: Text(place)),
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() => selectedLocation = value ?? ''),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () {
                      try {
                        commit(
                          startInventory(
                            widget.currentBooks?.call() ?? widget.books,
                            name: name.text,
                            operatorName: operatorName.text,
                            location: selectedLocation.isEmpty
                                ? null
                                : selectedLocation,
                          ),
                        );
                      } on FormatException catch (e) {
                        message(e.message);
                      }
                    },
              icon: const Icon(Icons.play_arrow_outlined),
              label: const Text('Sayımı başlat'),
            ),
          ] else ...[
            // Summary Dashboard Card
            Card(
              color: scheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Konum: ${current.location ?? 'Tüm konumlar'} · Görevli: ${current.operatorName}',
                    ),
                    Text(
                      'Başlangıç: ${current.startedAt.split('.').first.replaceAll('T', ' ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (summary != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'İlerleme: ${summary.countedTotal} / ${summary.expectedTotal} nüsha',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            summary.expectedTotal == 0
                                ? '%100'
                                : '%${((summary.countedTotal / summary.expectedTotal) * 100).clamp(0, 999).round()}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: summary.expectedTotal <= 0
                              ? 1
                              : (summary.countedTotal / summary.expectedTotal)
                                    .clamp(0.0, 1.0),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _StatChip(
                            label: 'Tam: ${summary.exactTitles}',
                            color: scheme.secondaryContainer,
                          ),
                          _StatChip(
                            label:
                                'Eksik: ${summary.missingTitles} kitap (${summary.missingCopies} nüsha)',
                            color: summary.missingCopies > 0
                                ? scheme.errorContainer
                                : scheme.surfaceContainerHighest,
                          ),
                          if (summary.surplusCopies > 0)
                            _StatChip(
                              label:
                                  'Fazla: ${summary.surplusTitles} kitap (+${summary.surplusCopies})',
                              color: scheme.tertiaryContainer,
                            ),
                          if (summary.unknownScans > 0)
                            _StatChip(
                              label: 'Tanınmayan: ${summary.unknownScans}',
                              color: scheme.tertiaryContainer,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (!widget.readOnly) ...[
              FilledButton.icon(
                onPressed: busy ? null : openContinuousScanner,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Seri kamerayla say (ardışık barkod tarama)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: barcode,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: 'ISBN veya demirbaş kodu okut / yaz',
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Tek barkod okut',
                        onPressed: busy
                            ? null
                            : () async {
                                final result = await Navigator.of(context)
                                    .push<String>(
                                      MaterialPageRoute(
                                        builder: (_) => const IsbnScannerPage(
                                          isbnOnly: false,
                                        ),
                                      ),
                                    );
                                if (result != null) await scan(result);
                              },
                        icon: const Icon(Icons.camera_alt_outlined),
                      ),
                      IconButton(
                        tooltip: 'Ekle',
                        onPressed: busy ? null : () => scan(barcode.text),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
                onSubmitted: scan,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: busy || current.events.isEmpty
                        ? null
                        : () => commit(undoInventory(current)),
                    icon: const Icon(Icons.undo),
                    label: const Text('Son işlemi geri al'),
                  ),
                  if (widget.archive != null)
                    TextButton.icon(
                      onPressed: busy ? null : finish,
                      icon: const Icon(Icons.task_alt),
                      label: const Text('Sayımı tamamla'),
                    ),
                  TextButton.icon(
                    onPressed: busy ? null : reset,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Sayımı sil'),
                  ),
                ],
              ),
            ],

            // Unknown barcodes section with 1-tap catalog registration!
            if (unknownCounts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                color: scheme.tertiaryContainer.withValues(alpha: 0.55),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tanınmayan barkodlar (${unknownCounts.length} farklı kod)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Bu barkodlar katalogda bulunamadı. Amazon / Kitapyurdu üzerinden künyesini çekerek doğrudan kataloğa ve sayıma ekleyebilirsiniz.',
                      ),
                      const SizedBox(height: 8),
                      for (final entry in unknownCounts.entries)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            entry.value > 1
                                ? '${entry.key} (${entry.value} adet okutuldu)'
                                : entry.key,
                          ),
                          subtitle: Text(
                            isValidIsbn(entry.key)
                                ? 'Geçerli ISBN — çevrimiçi künye çekilebilir'
                                : 'Barkod / demirbaş kodu',
                          ),
                          trailing: widget.readOnly
                              ? null
                              : Wrap(
                                  spacing: 4,
                                  children: [
                                    if (widget.registerUnknownBarcode != null)
                                      FilledButton.tonalIcon(
                                        onPressed: busy
                                            ? null
                                            : () async {
                                                setState(() => busy = true);
                                                try {
                                                  final updatedSession =
                                                      await widget
                                                          .registerUnknownBarcode!(
                                                        current,
                                                        entry.key,
                                                        entry.value,
                                                      );
                                                  if (!mounted) return;
                                                  if (updatedSession != null) {
                                                    setState(
                                                      () => session =
                                                          updatedSession,
                                                    );
                                                    message(
                                                      'Kitap kataloğa ve sayıma eklendi.',
                                                    );
                                                  }
                                                } finally {
                                                  if (mounted) {
                                                    setState(
                                                      () => busy = false,
                                                    );
                                                  }
                                                }
                                              },
                                        icon: const Icon(
                                          Icons.library_add_outlined,
                                          size: 18,
                                        ),
                                        label: const Text('Kataloğa ekle'),
                                      ),
                                    IconButton(
                                      tooltip: 'Tanınmayan kaydı sil',
                                      onPressed: busy
                                          ? null
                                          : () => commit(
                                              removeUnknownBarcodeEvents(
                                                current,
                                                entry.key,
                                              ),
                                            ),
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            const Divider(height: 24),
            // Search and Filter Controls
            TextField(
              controller: filterSearch,
              onChanged: (v) => setState(() => searchQuery = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => setState(() {
                          filterSearch.clear();
                          searchQuery = '';
                        }),
                        icon: const Icon(Icons.clear),
                      ),
                labelText: 'Sayım listesinde kitap, yazar veya ISBN ara',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in InventoryFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(f.label),
                        selected: activeFilter == f,
                        onSelected: (_) => setState(() => activeFilter = f),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Gösterilen: ${filteredRows.length} / ${allRows.length} kitap kaydı',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            if (filteredRows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('Seçilen filtreye uygun kitap kaydı yok.'),
                ),
              ),
            for (final row in filteredRows)
              _buildRowCard(context, current, row),
          ],
        ],
      ),
    );
  }

  Widget _buildRowCard(
    BuildContext context,
    InventorySession current,
    InventoryRow row,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final expected = row.entry['expected'] as int;
    final diff = row.count - expected;
    final (String badgeText, Color badgeBg) = diff == 0
        ? ('Tamam ($expected/$expected)', scheme.secondaryContainer)
        : diff < 0
        ? ('${-diff} eksik (${row.count}/$expected)', scheme.errorContainer)
        : ('+$diff fazla (${row.count}/$expected)', scheme.tertiaryContainer);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row.entry['title']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if ((row.entry['author'] as String).trim().isNotEmpty)
                        Text('${row.entry['author']}'),
                      if ((row.entry['isbn'] as String).trim().isNotEmpty)
                        Text(
                          'ISBN: ${row.entry['isbn']}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatChip(label: badgeText, color: badgeBg),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Kimlikli: ${row.identified} · ISBN okutma: ${row.isbn} · Elle: ${row.manual}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!widget.readOnly) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: busy
                        ? null
                        : () => commit(
                            recordManualInventory(
                              current,
                              row.entry['id'] as String,
                            ),
                          ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('+1 Say'),
                  ),
                  if (row.count > 0)
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => commit(
                              decrementInventoryBook(
                                current,
                                row.entry['id'] as String,
                              ),
                            ),
                      icon: const Icon(Icons.remove, size: 18),
                      label: const Text('-1 Azalt'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
