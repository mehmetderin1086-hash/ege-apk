import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'ai_book_vision_page.dart';
import 'book_lookup.dart';
import 'book_visuals.dart';
import 'bulk_isbn_importer_page.dart';
import 'continuous_scanner_page.dart';
import 'cover_fetch.dart';
import 'inventory_session.dart' show inventoryLocations;
import 'isbn.dart';
import 'kitapyurdu_search_dialog.dart';
import 'loan_model.dart';
import 'shelf_photo_scanner_page.dart';

class QuickRegisterLogEntry {
  const QuickRegisterLogEntry({
    required this.bookId,
    required this.title,
    required this.subtitle,
    required this.source,
  });

  final String bookId;
  final String title;
  final String subtitle;
  final String source;
}

class QuickRegisterPage extends StatefulWidget {
  const QuickRegisterPage({
    super.key,
    required this.initialBooks,
    required this.saveBooks,
    this.onEditBook,
  });

  final List<Map<String, dynamic>> initialBooks;
  final Future<bool> Function(List<Map<String, dynamic>> updated) saveBooks;
  final Future<List<Map<String, dynamic>>?> Function(
    Map<String, dynamic> book,
  )?
  onEditBook;

  @override
  State<QuickRegisterPage> createState() => _QuickRegisterPageState();
}

class _QuickRegisterPageState extends State<QuickRegisterPage> {
  late List<Map<String, dynamic>> _books = List.of(widget.initialBooks);
  final _shelfController = TextEditingController();
  final _accessionPrefix = TextEditingController();
  final _accessionNextNumber = TextEditingController();
  final _isbnController = TextEditingController();

  BookLookupSource _preferredSource = BookLookupSource.auto;
  bool _mergeDuplicateIsbn = true;
  bool _isTextbook = false;
  bool _busy = false;
  String? _statusMessage;
  bool _statusIsError = false;
  final List<QuickRegisterLogEntry> _sessionLog = [];

  @override
  void dispose() {
    _shelfController.dispose();
    _accessionPrefix.dispose();
    _accessionNextNumber.dispose();
    _isbnController.dispose();
    super.dispose();
  }

  String? _nextAccessionCode() {
    final rawNum = _accessionNextNumber.text.trim();
    if (rawNum.isEmpty) return null;
    final parsed = int.tryParse(rawNum);
    if (parsed == null || parsed < 0) return null;
    final width = rawNum.length < 4 ? 4 : rawNum.length;
    final prefix = _accessionPrefix.text.trim();
    var candidateNum = parsed;
    final existingCodes = <String>{
      for (final b in _books) ...[
        if ((b['accessionCode'] ?? '').toString().trim().isNotEmpty)
          (b['accessionCode'] as String).trim().toUpperCase(),
        for (final c in ((b['copies'] as List?) ?? []).whereType<Map>())
          if ((c['accessionCode'] ?? '').toString().trim().isNotEmpty)
            (c['accessionCode'] as String).trim().toUpperCase(),
      ],
    };
    while (true) {
      final formatted = '$prefix${candidateNum.toString().padLeft(width, '0')}';
      if (!existingCodes.contains(formatted.toUpperCase())) {
        _accessionNextNumber.text = (candidateNum + 1).toString().padLeft(
          rawNum.length,
          '0',
        );
        return formatted;
      }
      candidateNum++;
    }
  }

  Future<ScanFeedback> _registerFromFetched({
    required Map<String, String> info,
    Uint8List? preloadedCover,
    String? fallbackIsbn,
  }) async {
    final title = (info['title'] ?? '').trim();
    if (title.isEmpty) {
      return const ScanFeedback(
        title: 'Kitap adı bulunamadı',
        severity: ScanSeverity.error,
      );
    }
    final resolvedIsbn = (info['isbn'] ?? fallbackIsbn ?? '').trim();
    final isbnKey = canonicalIsbn(resolvedIsbn);
    final shelf = _shelfController.text.trim();
    final sourceLabel = (info['source'] ?? 'Çevrimiçi').trim();

    Uint8List? coverBytes = preloadedCover;
    if (coverBytes == null) {
      final coverUrl = (info['coverUrl'] ?? '').trim();
      if (coverUrl.isNotEmpty) {
        try {
          coverBytes = await fetchCoverBytesFromUrl(coverUrl);
        } catch (_) {
          // Non-fatal: continue without cover.
        }
      }
      if (coverBytes == null && isbnKey != null) {
        try {
          final dl = await fetchBestCover(isbnKey);
          coverBytes = dl?.bytes;
        } catch (_) {
          // Non-fatal.
        }
      }
    }
    final encodedCover = coverBytes == null ? null : storeCoverBytes(coverBytes);
    final now = DateTime.now();

    // Check existing book with same canonical ISBN
    final duplicateIndex = !_mergeDuplicateIsbn || isbnKey == null
        ? -1
        : _books.indexWhere(
            (b) =>
                b['deletedAt'] == null &&
                b['isWithdrawn'] != true &&
                canonicalIsbn((b['isbn'] ?? '').toString()) == isbnKey,
          );

    List<Map<String, dynamic>> nextBooks;
    String targetBookId;
    String summarySub;

    if (duplicateIndex >= 0) {
      final existing = Map<String, dynamic>.from(_books[duplicateIndex]);
      targetBookId = existing['id'] as String;
      final nextQty = (existing['quantity'] as int) + 1;
      void fillIfEmpty(String key, String? value) {
        if ((existing[key] ?? '').toString().trim().isEmpty &&
            value != null &&
            value.trim().isNotEmpty) {
          existing[key] = value.trim();
        }
      }

      fillIfEmpty('author', info['author']);
      fillIfEmpty('publisher', info['publisher']);
      fillIfEmpty('category', info['category']);
      fillIfEmpty('publicationYear', info['publicationYear']);
      fillIfEmpty('pageCount', info['pageCount']);
      fillIfEmpty('edition', info['edition']);
      fillIfEmpty('language', info['language']);
      fillIfEmpty('readingLevel', info['readingLevel']);
      if (shelf.isNotEmpty) fillIfEmpty('shelf', shelf);
      if ((existing['coverBase64'] ?? '').toString().trim().isEmpty &&
          encodedCover != null &&
          !coverFieldLocked(existing)) {
        existing['coverBase64'] = encodedCover;
      }
      existing['quantity'] = nextQty;

      final autoCode = _nextAccessionCode();
      if (autoCode != null) {
        final existingCopies = ((existing['copies'] as List?) ?? [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        existingCopies.add({
          'id': 'copy-${now.microsecondsSinceEpoch}',
          'bookID': targetBookId,
          'accessionCode': autoCode,
          'condition': 'Yeni',
          'status': 'Rafta',
          'note': '',
          'addedAt': now.toIso8601String(),
          if (shelf.isNotEmpty) 'shelf': shelf,
        });
        existing['copies'] = existingCopies;
      }

      final normalized = normalizeBook(existing);
      nextBooks = [..._books];
      nextBooks[duplicateIndex] = normalized;
      summarySub =
          'Mevcut kayda +1 nüsha eklendi (Toplam: $nextQty)${autoCode != null ? ' · $autoCode' : ''}';
    } else {
      targetBookId = now.microsecondsSinceEpoch.toString();
      final autoCode = _nextAccessionCode();
      final newBook = normalizeBook({
        'id': targetBookId,
        'title': title,
        'author': (info['author'] ?? '').trim(),
        'isbn': isbnKey ?? resolvedIsbn,
        'shelf': shelf,
        'publisher': (info['publisher'] ?? '').trim(),
        'category': (info['category'] ?? '').trim(),
        'series': '',
        'language': (info['language'] ?? '').trim(),
        'tags': '',
        'readingLevel': (info['readingLevel'] ?? '').trim(),
        'readingStatus': '',
        'contentWarning': '',
        'accessionCode': autoCode ?? '',
        'volume': null,
        'rating': null,
        'publicationYear': (info['publicationYear'] ?? '').trim(),
        'edition': (info['edition'] ?? '').trim(),
        'pageCount': (info['pageCount'] ?? '').trim(),
        'notes': '',
        'coverBase64': encodedCover,
        'backCoverBase64': null,
        'imprintBase64': null,
        'quantity': 1,
        'isTextbook': _isTextbook,
        'loans': <Map<String, dynamic>>[],
        if (autoCode != null)
          'copies': [
            {
              'id': 'copy-${now.microsecondsSinceEpoch}',
              'bookID': targetBookId,
              'accessionCode': autoCode,
              'condition': 'Yeni',
              'status': 'Rafta',
              'note': '',
              'addedAt': now.toIso8601String(),
              if (shelf.isNotEmpty) 'shelf': shelf,
            },
          ],
      });
      nextBooks = [..._books, newBook];
      summarySub = [
        if ((info['author'] ?? '').trim().isNotEmpty) info['author']!.trim(),
        if ((info['publisher'] ?? '').trim().isNotEmpty)
          info['publisher']!.trim(),
        if (shelf.isNotEmpty) 'Raf: $shelf',
        ?autoCode,
      ].join(' · ');
    }

    final saved = await widget.saveBooks(nextBooks);
    if (!saved) {
      return const ScanFeedback(
        title: 'Katalog kaydedilemedi',
        subtitle: 'Tekrar deneyin.',
        severity: ScanSeverity.error,
      );
    }
    if (mounted) {
      setState(() {
        _books = nextBooks;
        _sessionLog.insert(
          0,
          QuickRegisterLogEntry(
            bookId: targetBookId,
            title: title,
            subtitle: summarySub,
            source: sourceLabel,
          ),
        );
      });
    }
    return ScanFeedback(
      title: '$title ($sourceLabel)',
      subtitle: summarySub,
      severity: ScanSeverity.success,
    );
  }

  Future<ScanFeedback> _lookupAndRegisterIsbn(String rawIsbn) async {
    final clean = cleanIsbnInput(rawIsbn);
    if (clean.isEmpty || !isValidIsbn(clean)) {
      return ScanFeedback(
        title: 'Geçersiz ISBN: $rawIsbn',
        subtitle: '10 veya 13 haneli geçerli bir ISBN okutun veya girin.',
        severity: ScanSeverity.error,
      );
    }
    // Check if already in catalog even when offline!
    final isbnKey = canonicalIsbn(clean);
    Map<String, String>? info;
    try {
      info = await lookupIsbn(clean, preferred: _preferredSource);
    } catch (_) {
      // If offline, still allow incrementing an already-known ISBN in the catalog.
    }
    if (info == null) {
      final existing = isbnKey == null
          ? null
          : _books
                .where(
                  (b) =>
                      b['deletedAt'] == null &&
                      canonicalIsbn((b['isbn'] ?? '').toString()) == isbnKey,
                )
                .firstOrNull;
      if (existing != null && _mergeDuplicateIsbn) {
        return await _registerFromFetched(
          info: {
            'source': 'Mevcut katalog',
            'title': '${existing['title']}',
            'isbn': isbnKey!,
          },
          fallbackIsbn: clean,
        );
      }
      return ScanFeedback(
        title: 'ISBN bulunamadı: $clean',
        subtitle:
            "Kitapyurdu arama düğmesiyle başlık, yazar veya yayınevinden ekleyebilirsiniz.",
        severity: ScanSeverity.warning,
      );
    }
    return await _registerFromFetched(info: info, fallbackIsbn: clean);
  }

  Future<void> _submitManualIsbn() async {
    if (_busy) return;
    final input = _isbnController.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final fb = await _lookupAndRegisterIsbn(input);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusMessage = fb.subtitle.isEmpty
            ? fb.title
            : '${fb.title} — ${fb.subtitle}';
        _statusIsError = fb.severity != ScanSeverity.success;
        if (fb.severity == ScanSeverity.success) {
          _isbnController.clear();
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openKitapyurduRegister() async {
    if (_busy) return;
    final picked = await showDialog<FetchedBookData>(
      context: context,
      builder: (_) => const KitapyurduSearchDialog(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final fb = await _registerFromFetched(
        info: picked.metadata,
        preloadedCover: picked.coverBytes,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusMessage = fb.subtitle.isEmpty
            ? fb.title
            : '${fb.title} — ${fb.subtitle}';
        _statusIsError = fb.severity != ScanSeverity.success;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openBatchBarcodeScanner() async {
    if (_busy) return;
    await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ContinuousScannerPage(
          title: 'Seri kitap kayıt',
          isbnOnly: true,
          hintText:
              'Kitapların ISBN barkodunu gösterin; Amazon ve diğer kaynaklardan künye + kapak otomatik kaydedilir.',
          onBarcode: _lookupAndRegisterIsbn,
        ),
      ),
    );
  }

  Widget _miniCover(Map<String, dynamic>? book) {
    if (book == null) return const Icon(Icons.menu_book_outlined);
    return BookCoverWidget(book: book, width: 40, height: 58);
  }

  @override
  Widget build(BuildContext context) {
    final shelves = inventoryLocations(_books);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hızlı kütüphane kitap kaydı'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 126,
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
                          const Color(0xFF0F172A).withValues(alpha: 0.88),
                          const Color(0xFF0F172A).withValues(alpha: 0.25),
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
                          'Seri Barkod ve Çevrimiçi Kayıt',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Amazon ISBN ve Kitapyurdu künyeleriyle kitapları saniyeler içinde rafa ve demirbaşa kaydedin.',
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
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BulkIsbnImporterPage(
                              initialBooks: _books,
                              onSaveBooks: (next) async {
                                final ok = await widget.saveBooks(next);
                                if (ok && mounted) {
                                  setState(() => _books = next);
                                }
                              },
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                label: const Text('100+ ISBN Toplu Amazon'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FourPageBookScannerPage(
                              initialBooks: _books,
                              onSaveBooks: (next) async {
                                final ok = await widget.saveBooks(next);
                                if (ok && mounted) {
                                  setState(() => _books = next);
                                }
                              },
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.document_scanner_rounded, size: 18),
                label: const Text('4-Sayfa Kapak/Künye OCR'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ShelfPhotoScannerPage(
                              initialBooks: _books,
                              onSaveBooks: (next) async {
                                final ok = await widget.saveBooks(next);
                                if (ok && mounted) {
                                  setState(() => _books = next);
                                }
                              },
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.collections_bookmark_rounded, size: 18),
                label: const Text('Raf Fotoğrafından Sayım'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Varsayılan kayıt ve raf ayarları',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _shelfController,
                    decoration: const InputDecoration(
                      labelText: 'Dolap / raf (isteğe bağlı, örn. A-2)',
                      prefixIcon: Icon(Icons.shelves),
                      isDense: true,
                    ),
                  ),
                  if (shelves.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final s in shelves.take(10))
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                label: Text(s),
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    setState(() => _shelfController.text = s),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _accessionPrefix,
                          decoration: const InputDecoration(
                            labelText: 'Demirbaş öneki (örn. DMR-)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _accessionNextNumber,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Başlangıç no (örn. 0001)',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<BookLookupSource>(
                    initialValue: _preferredSource,
                    decoration: const InputDecoration(
                      labelText: 'ISBN veri kaynağı',
                      isDense: true,
                    ),
                    items: [
                      for (final src in [
                        BookLookupSource.auto,
                        BookLookupSource.amazon,
                        BookLookupSource.googleBooks,
                        BookLookupSource.openLibrary,
                      ])
                        DropdownMenuItem(value: src, child: Text(src.label)),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _preferredSource = v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Aynı ISBN kayıtlıysa +1 nüsha ekle'),
                    value: _mergeDuplicateIsbn,
                    onChanged: (v) => setState(() => _mergeDuplicateIsbn = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Yeni eklenenleri ders kitabı işaretle'),
                    value: _isTextbook,
                    onChanged: (v) => setState(() => _isTextbook = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _openBatchBarcodeScanner,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Seri ISBN barkodu okut ve kaydet (Amazon + Kapak)'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _openKitapyurduRegister,
            icon: const Icon(Icons.manage_search),
            label: const Text(
              "Kitapyurdu'ndan başlık / yazar / yayınevi ile ekle",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _isbnController,
            enabled: !_busy,
            onSubmitted: (_) => _submitManualIsbn(),
            decoration: InputDecoration(
              labelText: 'ISBN yazın veya yapıştırın (Amazon / çoklu kaynak)',
              border: const OutlineInputBorder(),
              suffixIcon: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Bilgileri çek ve kaydet',
                      onPressed: _submitManualIsbn,
                      icon: const Icon(Icons.cloud_download_outlined),
                    ),
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _statusMessage!,
              style: TextStyle(
                color: _statusIsError ? scheme.error : scheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const Divider(height: 28),
          Text(
            'Bu oturumda kaydedilenler (${_sessionLog.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_sessionLog.isEmpty)
            const Text(
              'Henüz bu oturumda kitap eklenmedi. Kamera ile seri barkod okutabilir, ISBN yazabilir veya Kitapyurdu üzerinden başlık/yazar/yayınevi aramasıyla ekleyebilirsiniz.',
            ),
          for (final item in _sessionLog) ...[
            Builder(
              builder: (ctx) {
                final matched = _books
                    .where((b) => b['id'] == item.bookId)
                    .firstOrNull;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: _miniCover(matched),
                    title: Text('${item.title} · ${item.source}'),
                    subtitle: Text(item.subtitle),
                    trailing: widget.onEditBook != null && matched != null
                        ? IconButton(
                            tooltip: 'Düzenle',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final updated = await widget.onEditBook!(matched);
                              if (updated != null && mounted) {
                                setState(() => _books = updated);
                              }
                            },
                          )
                        : null,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
