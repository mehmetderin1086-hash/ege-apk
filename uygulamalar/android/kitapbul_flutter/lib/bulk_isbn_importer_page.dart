import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_proxy_service.dart';
import 'app_theme_settings.dart';
import 'book_lookup.dart';
import 'book_visuals.dart';
import 'catalog_xlsx.dart';
import 'cover_fetch.dart';
import 'isbn.dart';
import 'loan_model.dart';
import 'school_automation_hub.dart' show findHighestAccessionNumber;

enum BulkItemStatus { queued, fetching, found, notFound, error, saved }

class BulkIsbnQueueItem {
  BulkIsbnQueueItem({
    required this.isbn,
    this.copies = 1,
    this.targetShelf = '',
    this.status = BulkItemStatus.queued,
    this.metadata,
    this.coverRef,
    this.errorMessage = '',
    this.assignedAccession = '',
  });

  final String isbn;
  int copies;
  String targetShelf;
  BulkItemStatus status;
  Map<String, String>? metadata;
  String? coverRef;
  String errorMessage;
  String assignedAccession;

  Map<String, dynamic> toJson() => {
    'isbn': isbn,
    'copies': copies,
    'targetShelf': targetShelf,
    'status': status.name,
    'metadata': metadata,
    'coverRef': coverRef,
    'errorMessage': errorMessage,
    'assignedAccession': assignedAccession,
  };

  factory BulkIsbnQueueItem.fromJson(Map<String, dynamic> json) {
    final stName = (json['status'] ?? 'queued').toString();
    final st = BulkItemStatus.values.firstWhere(
      (e) => e.name == stName,
      orElse: () => BulkItemStatus.queued,
    );
    final rawMeta = json['metadata'];
    return BulkIsbnQueueItem(
      isbn: (json['isbn'] ?? '').toString(),
      copies: ((json['copies'] as num?)?.toInt() ?? 1).clamp(1, 999),
      targetShelf: (json['targetShelf'] ?? '').toString(),
      status: st == BulkItemStatus.fetching ? BulkItemStatus.queued : st,
      metadata: rawMeta is Map
          ? rawMeta.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()))
          : null,
      coverRef: json['coverRef']?.toString(),
      errorMessage: (json['errorMessage'] ?? '').toString(),
      assignedAccession: (json['assignedAccession'] ?? '').toString(),
    );
  }
}

/// Serbest metinden (100'lerce satır, virgül, noktalı virgül, URL vb.) geçerli ISBN'leri çıkarır,
/// kanonik ISBN-13'e dönüştürür, aynı ISBN'lerin adetlerini toplar ve hatalı adayları ayırır.
({List<BulkIsbnQueueItem> validItems, List<String> invalidTokens})
extractBulkIsbnQueue(String rawText, {String defaultShelf = ''}) {
  final counts = <String, int>{};
  final order = <String>[];
  final invalid = <String>[];

  // Amazon /dp/XXXXXXXXXX veya serbest 10-13 haneli adayları yakala
  final tokenRegex = RegExp(
    r'(?:dp/|gp/product/)?([0-9][0-9\- ]{8,16}[0-9Xx])',
  );
  for (final match in tokenRegex.allMatches(rawText)) {
    final rawCandidate = (match.group(1) ?? '').trim();
    final compact = cleanIsbnInput(rawCandidate);
    if (compact.length != 10 && compact.length != 13) continue;
    final canon = canonicalIsbn(compact);
    if (canon != null) {
      if (!counts.containsKey(canon)) order.add(canon);
      counts[canon] = (counts[canon] ?? 0) + 1;
    } else {
      if (!invalid.contains(compact)) invalid.add(compact);
    }
  }

  return (
    validItems: [
      for (final code in order)
        BulkIsbnQueueItem(
          isbn: code,
          copies: counts[code] ?? 1,
          targetShelf: defaultShelf,
        ),
    ],
    invalidTokens: invalid,
  );
}

class BulkIsbnImporterPage extends StatefulWidget {
  const BulkIsbnImporterPage({
    super.key,
    required this.initialBooks,
    required this.onSaveBooks,
  });

  final List<Map<String, dynamic>> initialBooks;
  final Future<void> Function(List<Map<String, dynamic>> updated) onSaveBooks;

  @override
  State<BulkIsbnImporterPage> createState() => _BulkIsbnImporterPageState();
}

class _BulkIsbnImporterPageState extends State<BulkIsbnImporterPage> {
  late List<Map<String, dynamic>> _books = List.of(widget.initialBooks);
  final List<BulkIsbnQueueItem> _queue = [];
  final TextEditingController _pasteCtrl = TextEditingController();
  final TextEditingController _shelfCtrl = TextEditingController();

  BookLookupSource _sourceMode = BookLookupSource.auto;
  int _concurrency = 2;
  bool _downloadCovers = true;
  bool _autoAssignCalCode = true;
  final bool _mergeExistingIsbn = true;
  bool _autoSaveAsFetched = true;
  bool _useAiFallback = true;
  bool _speakFoundTitles = false;

  bool _running = false;
  bool _paused = false;
  bool _cancelRequested = false;
  DateTime? _batchStartedAt;
  int _processedInRun = 0;
  String _filter = 'all';
  List<String> _lastInvalidTokens = const [];

  @override
  void initState() {
    super.initState();
    _restorePersistedQueue();
  }

  @override
  void dispose() {
    _cancelRequested = true;
    _pasteCtrl.dispose();
    _shelfCtrl.dispose();
    super.dispose();
  }

  Future<File> _queueFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/bulk_isbn_queue.json');
  }

  Future<void> _restorePersistedQueue() async {
    try {
      final f = await _queueFile();
      if (!await f.exists()) return;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is List && mounted) {
        final restored = decoded
            .whereType<Map>()
            .map((m) => BulkIsbnQueueItem.fromJson(Map<String, dynamic>.from(m)))
            .where((e) => e.isbn.isNotEmpty)
            .toList();
        if (restored.isNotEmpty) {
          setState(() {
            _queue
              ..clear()
              ..addAll(restored);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _persistQueue() async {
    try {
      final f = await _queueFile();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(_queue.map((e) => e.toJson()).toList()),
        flush: true,
      );
      await tmp.rename(f.path);
    } catch (_) {}
  }

  void _mergeIntoQueue(
    List<BulkIsbnQueueItem> incoming, {
    List<String> invalid = const [],
  }) {
    var addedNew = 0;
    var mergedCopies = 0;
    for (final item in incoming) {
      final idx = _queue.indexWhere((q) => q.isbn == item.isbn);
      if (idx >= 0) {
        _queue[idx].copies += item.copies;
        if (_queue[idx].targetShelf.isEmpty && item.targetShelf.isNotEmpty) {
          _queue[idx].targetShelf = item.targetShelf;
        }
        mergedCopies += item.copies;
      } else {
        _queue.add(item);
        addedNew++;
      }
    }
    setState(() {
      _lastInvalidTokens = invalid;
    });
    _persistQueue();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$addedNew yeni ISBN kuyruğa eklendi'
          '${mergedCopies > 0 ? ', $mergedCopies mükerrer adet birleştirildi' : ''}'
          '${invalid.isNotEmpty ? ' (${invalid.length} geçersiz kod atlandı)' : ''}.',
        ),
      ),
    );
  }

  Future<void> _showPasteDialog() async {
    _pasteCtrl.clear();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '100+ ISBN Toplu Yapıştır / Gir',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'ISBN-10 veya ISBN-13 kodlarını alt alta, virgülle veya Amazon bağlantıları halinde yapıştırın. Geçerli tüm ISBN\'ler otomatik ayıklanır.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pasteCtrl,
                minLines: 6,
                maxLines: 12,
                decoration: InputDecoration(
                  hintText:
                      '9789750719387\n9789753638029\n9789754706048\n9786053601906...',
                  suffixIcon: IconButton(
                    tooltip: 'Panodan yapıştır',
                    onPressed: () async {
                      final clip = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if ((clip?.text ?? '').isNotEmpty) {
                        _pasteCtrl.text =
                            '${_pasteCtrl.text}\n${clip!.text}'.trim();
                      }
                    },
                    icon: const Icon(Icons.content_paste_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final parsed = extractBulkIsbnQueue(
                      _pasteCtrl.text,
                      defaultShelf: _shelfCtrl.text.trim(),
                    );
                    Navigator.of(ctx).pop();
                    _mergeIntoQueue(
                      parsed.validItems,
                      invalid: parsed.invalidTokens,
                    );
                  },
                  icon: const Icon(Icons.playlist_add_check_rounded),
                  label: const Text('ISBN\'leri Doğrula ve Kuyruğa Ekle'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openTurboBarcodeScanner() async {
    final scanned = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const _TurboIsbnQueueScannerPage(),
      ),
    );
    if (scanned == null || scanned.isEmpty) return;
    final parsed = extractBulkIsbnQueue(
      scanned.join('\n'),
      defaultShelf: _shelfCtrl.text.trim(),
    );
    _mergeIntoQueue(parsed.validItems, invalid: parsed.invalidTokens);
  }

  Future<void> _importFromFile() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_view_rounded),
              title: const Text('Excel (.xlsx) Dosyasından ISBN Çek'),
              subtitle: const Text('Tablodaki tüm ISBN-10 / ISBN-13 hücrelerini okur'),
              onTap: () => Navigator.pop(ctx, 'xlsx'),
            ),
            ListTile(
              leading: const Icon(Icons.description_rounded),
              title: const Text('CSV / TXT Metin Dosyasından ISBN Çek'),
              subtitle: const Text('Satır satır veya virgüllü ISBN listesini okur'),
              onTap: () => Navigator.pop(ctx, 'txt'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      const ch = MethodChannel('kitapbul/files');
      if (choice == 'xlsx') {
        final bytes = await ch.invokeMethod<Uint8List>('pickXlsx');
        if (bytes == null) return;
        final rows = parseCatalogXlsx(bytes);
        final buf = StringBuffer();
        for (final r in rows) {
          buf.writeln(r['isbn'] ?? '');
        }
        final parsed = extractBulkIsbnQueue(
          buf.toString(),
          defaultShelf: _shelfCtrl.text.trim(),
        );
        _mergeIntoQueue(parsed.validItems, invalid: parsed.invalidTokens);
      } else {
        final bytes = await ch.invokeMethod<Uint8List>('pickStudentsCsv');
        if (bytes == null) return;
        final text = utf8.decode(bytes, allowMalformed: true);
        final parsed = extractBulkIsbnQueue(
          text,
          defaultShelf: _shelfCtrl.text.trim(),
        );
        _mergeIntoQueue(parsed.validItems, invalid: parsed.invalidTokens);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dosya okunamadı: $e')),
        );
      }
    }
  }

  Future<void> _loadPendingFromIPhoneSessions() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/tarama-oturumlari.json');
      String raw;
      if (await f.exists()) {
        raw = await f.readAsString();
      } else {
        raw = await rootBundle.loadString('assets/seed/tarama-oturumlari.json');
      }
      final list = jsonDecode(raw);
      if (list is! List) return;
      final existingIsbns = <String>{
        for (final b in _books)
          if (b['deletedAt'] == null &&
              canonicalIsbn((b['isbn'] ?? '').toString()) != null)
            canonicalIsbn((b['isbn'] ?? '').toString())!,
      };
      final items = <BulkIsbnQueueItem>[];
      final seen = <String>{};
      for (final s in list.whereType<Map>()) {
        final sessCab = (s['cabinet'] ?? '').toString().trim();
        final pending = (s['pendingBooks'] as List?)?.whereType<Map>() ?? const [];
        for (final p in pending) {
          final rawIsbn = (p['isbn'] ?? '').toString().trim();
          final title = (p['title'] ?? '').toString().trim();
          final canon = canonicalIsbn(rawIsbn);
          if (canon == null || title.isNotEmpty) continue;
          if (existingIsbns.contains(canon) || !seen.add(canon)) continue;
          final cab = (p['cabinet'] ?? sessCab).toString().trim();
          final qty = ((p['quantity'] as num?)?.toInt() ?? 1).clamp(1, 50);
          items.add(
            BulkIsbnQueueItem(
              isbn: canon,
              copies: qty,
              targetShelf: cab.isNotEmpty ? cab : _shelfCtrl.text.trim(),
            ),
          );
        }
      }
      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bekleyen iPhone ISBN kaydı bulunamadı veya tamamı zaten katalogda.'),
            ),
          );
        }
        return;
      }
      _mergeIntoQueue(items);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('iPhone oturumları okunamadı: $e')),
        );
      }
    }
  }

  void _queueCatalogMissingMetadata() {
    final candidates = <BulkIsbnQueueItem>[];
    final seen = <String>{};
    for (final b in _books) {
      if (b['deletedAt'] != null || b['isWithdrawn'] == true) continue;
      final canon = canonicalIsbn((b['isbn'] ?? '').toString());
      if (canon == null || !seen.add(canon)) continue;
      final missingCover = !hasStoredImage(b['coverBase64']);
      final missingPub = (b['publisher'] ?? '').toString().trim().isEmpty;
      final missingCat = (b['category'] ?? '').toString().trim().isEmpty;
      final missingPages = (b['pageCount'] ?? '').toString().trim().isEmpty;
      if (missingCover || missingPub || missingCat || missingPages) {
        candidates.add(
          BulkIsbnQueueItem(
            isbn: canon,
            copies: 0, // 0 = nüsha artırmadan yalnız eksik alanları zenginleştir!
            targetShelf: (b['shelf'] ?? '').toString().trim(),
          ),
        );
      }
    }
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ISBN\'li kitapların kapak ve künye bilgileri tam görünüyor!'),
        ),
      );
      return;
    }
    _mergeIntoQueue(candidates);
  }

  Future<Map<String, String>?> _aiFallbackIsbnLookup(String isbn) async {
    final cfg = aiSettingsNotifier.value;
    if (cfg.mode == AiProviderMode.directGemini && cfg.apiKey.trim().isEmpty) {
      return null;
    }
    try {
      final json = await AiProxyClient.generateStructuredJson(
        systemPrompt:
            'Sen uzman bir Türk kütüphane kataloglama uzmanısın. Verilen ISBN numarasını kesin olarak biliyorsan JSON döndür; emin değilsen {"known": false} döndür. Asla uydurma kitap adı yazma.',
        userPrompt:
            'ISBN: $isbn\n'
            'Şu JSON şemasıyla yanıt ver: '
            '{"known": true/false, "title": "", "author": "", "publisher": "", "publicationYear": "", "pageCount": "", "category": "", "language": "Türkçe"}',
        timeout: const Duration(seconds: 22),
      );
      if (json is Map && json['known'] == true) {
        final title = (json['title'] ?? '').toString().trim();
        if (title.isNotEmpty) {
          return {
            'source': 'CLIProxy / Gemini AI',
            'isbn': isbn,
            'title': title,
            'author': (json['author'] ?? '').toString().trim(),
            'publisher': (json['publisher'] ?? '').toString().trim(),
            'publicationYear': (json['publicationYear'] ?? '').toString().trim(),
            'pageCount': (json['pageCount'] ?? '').toString().trim(),
            'category': (json['category'] ?? '').toString().trim(),
            'language': (json['language'] ?? 'Türkçe').toString().trim(),
          };
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _startOrResumeBatch({bool retryFailedOnly = false}) async {
    if (_running) {
      setState(() => _paused = false);
      return;
    }
    if (retryFailedOnly) {
      setState(() {
        for (final item in _queue) {
          if (item.status == BulkItemStatus.notFound ||
              item.status == BulkItemStatus.error) {
            item.status = BulkItemStatus.queued;
            item.errorMessage = '';
          }
        }
      });
    }
    final targets = _queue
        .where((q) => q.status == BulkItemStatus.queued)
        .toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sırada bekleyen ISBN yok.')),
      );
      return;
    }

    setState(() {
      _running = true;
      _paused = false;
      _cancelRequested = false;
      _batchStartedAt = DateTime.now();
      _processedInRun = 0;
    });

    var cursor = 0;
    var unsavedReadyCount = 0;
    final rng = math.Random();

    Future<void> worker(int workerId) async {
      while (!_cancelRequested && mounted) {
        while (_paused && !_cancelRequested && mounted) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (_cancelRequested || !mounted) break;
        if (cursor >= targets.length) break;
        final item = targets[cursor++];
        if (item.status != BulkItemStatus.queued) continue;

        setState(() => item.status = BulkItemStatus.fetching);

        Map<String, String>? foundInfo;
        String? errText;
        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            foundInfo = await lookupIsbn(item.isbn, preferred: _sourceMode);
            if (foundInfo != null) break;
            // Amazon tekil seçilmiş ve geçici hız sınırına takılmışsa kısa bekleme sonrası tekrar dene
            if (attempt == 0 && _sourceMode == BookLookupSource.amazon) {
              await Future<void>.delayed(
                Duration(milliseconds: 900 + rng.nextInt(600)),
              );
            }
          } catch (e) {
            errText = '$e';
            await Future<void>.delayed(
              Duration(milliseconds: 800 * (attempt + 1)),
            );
          }
        }

        // Amazon tekil modda bulunamadıysa otomatik çoklu kaynak tamamlayıcı dene
        if (foundInfo == null && _sourceMode == BookLookupSource.amazon) {
          try {
            foundInfo = await lookupIsbn(
              item.isbn,
              preferred: BookLookupSource.auto,
            );
          } catch (_) {}
        }

        // Yine bulunamadıysa isteğe bağlı CLIProxyAPI / Gemini AI yedeği
        if (foundInfo == null && _useAiFallback) {
          foundInfo = await _aiFallbackIsbnLookup(item.isbn);
        }

        String? storedCoverRef;
        if (foundInfo != null && _downloadCovers) {
          final coverUrl = (foundInfo['coverUrl'] ?? '').trim();
          Uint8List? coverBytes;
          if (coverUrl.isNotEmpty) {
            try {
              coverBytes = await fetchCoverBytesFromUrl(coverUrl);
            } catch (_) {}
          }
          if (coverBytes == null) {
            try {
              final dl = await fetchBestCover(item.isbn);
              coverBytes = dl?.bytes;
            } catch (_) {}
          }
          if (coverBytes != null) {
            try {
              storedCoverRef = storeCoverBytes(coverBytes);
            } catch (_) {}
          }
        }

        if (!mounted) break;
        setState(() {
          _processedInRun++;
          if (foundInfo != null && (foundInfo['title'] ?? '').trim().isNotEmpty) {
            item.metadata = foundInfo;
            item.coverRef = storedCoverRef ?? item.coverRef;
            item.status = BulkItemStatus.found;
            item.errorMessage = '';
            unsavedReadyCount++;
          } else if (errText != null && errText.isNotEmpty) {
            item.status = BulkItemStatus.error;
            item.errorMessage = errText;
          } else {
            item.status = BulkItemStatus.notFound;
            item.errorMessage = 'Kaynaklarda bulunamadı';
          }
        });

        if (_speakFoundTitles &&
            item.status == BulkItemStatus.found &&
            item.metadata != null) {
          unawaited(
            NativeVoiceController.instance.speak(
              '${item.metadata!['title']} bulundu.',
            ),
          );
        }

        if (_autoSaveAsFetched && unsavedReadyCount >= 8) {
          unsavedReadyCount = 0;
          await _commitFoundItemsToCatalog(silent: true);
        } else if (_processedInRun % 5 == 0) {
          await _persistQueue();
        }

        // Amazon anti-throttle nazik gecikme (320-680ms)
        await Future<void>.delayed(
          Duration(milliseconds: 320 + rng.nextInt(360)),
        );
      }
    }

    final workerCount = _concurrency.clamp(1, 4);
    await Future.wait([
      for (var w = 0; w < workerCount; w++) worker(w),
    ]);

    if (_autoSaveAsFetched) {
      await _commitFoundItemsToCatalog(silent: false);
    } else {
      await _persistQueue();
    }

    if (mounted) {
      setState(() {
        _running = false;
        _paused = false;
      });
    }
  }

  Future<void> _commitFoundItemsToCatalog({bool silent = false}) async {
    final ready = _queue.where((q) => q.status == BulkItemStatus.found).toList();
    if (ready.isEmpty) return;

    final themeCfg = appThemeNotifier.value;
    final prefix = themeCfg.accessionPrefix;
    final digits = themeCfg.accessionDigits;
    var nextAcc = findHighestAccessionNumber(_books, prefix: prefix) + 1;
    String fmtAcc(int n) => '$prefix${n.toString().padLeft(digits, '0')}';

    final updatedBooks = [..._books];
    var addedBooks = 0;
    var enrichedBooks = 0;

    for (final item in ready) {
      final meta = item.metadata;
      if (meta == null) continue;
      final title = (meta['title'] ?? '').trim();
      if (title.isEmpty) continue;

      final shelf = item.targetShelf.trim().isNotEmpty
          ? item.targetShelf.trim()
          : _shelfCtrl.text.trim();
      final dupIdx = !_mergeExistingIsbn && item.copies > 0
          ? -1
          : updatedBooks.indexWhere(
              (b) =>
                  b['deletedAt'] == null &&
                  b['isWithdrawn'] != true &&
                  canonicalIsbn((b['isbn'] ?? '').toString()) == item.isbn,
            );

      if (dupIdx >= 0) {
        final existing = Map<String, dynamic>.from(updatedBooks[dupIdx]);
        void fill(String k, String? val) {
          if ((existing[k] ?? '').toString().trim().isEmpty &&
              val != null &&
              val.trim().isNotEmpty) {
            existing[k] = val.trim();
          }
        }

        fill('author', meta['author']);
        fill('publisher', meta['publisher']);
        fill('category', meta['category']);
        fill('publicationYear', meta['publicationYear']);
        fill('pageCount', meta['pageCount']);
        fill('edition', meta['edition']);
        fill('language', meta['language']);
        fill('readingLevel', meta['readingLevel']);
        if (shelf.isNotEmpty) fill('shelf', shelf);
        if (!hasStoredImage(existing['coverBase64']) && item.coverRef != null) {
          existing['coverBase64'] = item.coverRef;
        }

        if (item.copies > 0) {
          existing['quantity'] = ((existing['quantity'] as int?) ?? 1) + item.copies;
          if (_autoAssignCalCode) {
            final newCodes = <String>[
              for (var i = 0; i < item.copies; i++) fmtAcc(nextAcc++),
            ];
            final prevAcc = (existing['accessionCode'] ?? '').toString().trim();
            existing['accessionCode'] = prevAcc.isEmpty
                ? newCodes.join('; ')
                : '$prevAcc; ${newCodes.join('; ')}';
            item.assignedAccession = newCodes.first;
          }
          addedBooks++;
        } else {
          enrichedBooks++;
        }
        updatedBooks[dupIdx] = normalizeBook(existing);
      } else {
        final qty = item.copies <= 0 ? 1 : item.copies;
        final codes = _autoAssignCalCode
            ? <String>[for (var i = 0; i < qty; i++) fmtAcc(nextAcc++)]
            : const <String>[];
        if (codes.isNotEmpty) item.assignedAccession = codes.first;
        final now = DateTime.now();
        final id = 'bulk-${now.microsecondsSinceEpoch}-${item.isbn}';
        updatedBooks.add(
          normalizeBook({
            'id': id,
            'title': title,
            'author': (meta['author'] ?? '').trim(),
            'publisher': (meta['publisher'] ?? '').trim(),
            'isbn': item.isbn,
            'category': (meta['category'] ?? '').trim(),
            'shelf': shelf,
            'accessionCode': codes.join('; '),
            'publicationYear': (meta['publicationYear'] ?? '').trim(),
            'edition': (meta['edition'] ?? '').trim(),
            'pageCount': (meta['pageCount'] ?? '').trim(),
            'language': (meta['language'] ?? 'Türkçe').trim(),
            'readingLevel': (meta['readingLevel'] ?? '').trim(),
            'coverBase64': item.coverRef,
            'quantity': qty,
            'loans': <Map<String, dynamic>>[],
          }),
        );
        addedBooks++;
      }
      item.status = BulkItemStatus.saved;
    }

    await widget.onSaveBooks(updatedBooks);
    _books = updatedBooks;
    await _persistQueue();
    if (!silent && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kataloğa kaydedildi: $addedBooks kitap eklendi'
            '${enrichedBooks > 0 ? ', $enrichedBooks mevcut kitabın künyesi/kapağı tamamlandı' : ''}.',
          ),
        ),
      );
    }
  }

  String _etaText(int remaining) {
    if (!_running || _processedInRun < 2 || _batchStartedAt == null || remaining <= 0) {
      return '';
    }
    final elapsedSec = DateTime.now()
        .difference(_batchStartedAt!)
        .inMilliseconds /
        1000.0;
    final perItem = elapsedSec / _processedInRun;
    final remSec = (perItem * remaining).round();
    if (remSec < 60) return '~${remSec}s kaldı';
    return '~${remSec ~/ 60} dk ${remSec % 60} sn kaldı';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final queuedCount = _queue
        .where((q) => q.status == BulkItemStatus.queued || q.status == BulkItemStatus.fetching)
        .length;
    final foundCount = _queue
        .where((q) => q.status == BulkItemStatus.found || q.status == BulkItemStatus.saved)
        .length;
    final unsavedFoundCount = _queue
        .where((q) => q.status == BulkItemStatus.found)
        .length;
    final failedCount = _queue
        .where((q) => q.status == BulkItemStatus.notFound || q.status == BulkItemStatus.error)
        .length;
    final progress = _queue.isEmpty
        ? 0.0
        : (_queue.length - queuedCount) / _queue.length;

    final visibleQueue = _queue.where((q) {
      return switch (_filter) {
        'queued' =>
          q.status == BulkItemStatus.queued || q.status == BulkItemStatus.fetching,
        'found' =>
          q.status == BulkItemStatus.found || q.status == BulkItemStatus.saved,
        'failed' =>
          q.status == BulkItemStatus.notFound || q.status == BulkItemStatus.error,
        _ => true,
      };
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('100+ ISBN Toplu Amazon Çekme'),
        actions: [
          IconButton(
            tooltip: 'CLIProxyAPI & Yapay Zekâ Ayarları',
            onPressed: () => showAiProxySettingsSheet(context),
            icon: const Icon(Icons.hub_rounded),
          ),
          if (_queue.isNotEmpty && !_running)
            IconButton(
              tooltip: 'Kuyruğu Temizle',
              onPressed: () async {
                setState(() {
                  _queue.clear();
                  _lastInvalidTokens = const [];
                });
                await _persistQueue();
              },
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          IllustratedBannerCard(
            imageAsset: 'assets/images/scanner_banner.jpg',
            title: 'Toplu ISBN & Amazon Kataloglama Motoru',
            subtitle:
                '100\'lerce ISBN\'i tek seferde yapıştırın, dosyadan alın veya turbo kamerayla okutun; Amazon, Kitapyurdu ve CLIProxy AI kapaklarıyla birlikte çeksin.',
            icon: Icons.rocket_launch_rounded,
            pills: [
              AnimatedStatPill(
                label: 'Kuyrukta',
                value: _queue.length,
                icon: Icons.list_alt_rounded,
                accentColor: const Color(0xFFFDE68A),
              ),
              AnimatedStatPill(
                label: 'Çekilen',
                value: foundCount,
                icon: Icons.check_circle_rounded,
                accentColor: const Color(0xFF6EE7B7),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 5 Hızlı Kuyruk Giriş Butonu
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _running ? null : _showPasteDialog,
                icon: const Icon(Icons.content_paste_go_rounded),
                label: const Text('100+ ISBN Yapıştır'),
              ),
              FilledButton.tonalIcon(
                onPressed: _running ? null : _openTurboBarcodeScanner,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Turbo Seri Barkod Okut'),
              ),
              OutlinedButton.icon(
                onPressed: _running ? null : _importFromFile,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Excel / CSV\'den Al'),
              ),
              OutlinedButton.icon(
                onPressed: _running ? null : _loadPendingFromIPhoneSessions,
                icon: const Icon(Icons.phone_iphone_rounded),
                label: const Text('iPhone Bekleyen ISBN\'ler'),
              ),
              OutlinedButton.icon(
                onPressed: _running ? null : _queueCatalogMissingMetadata,
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: const Text('Katalogdaki Eksik Kapakları Tamamla'),
              ),
            ],
          ),

          if (_lastInvalidTokens.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Kontrol basamağı hatalı ${_lastInvalidTokens.length} kod atlandı: '
                '${_lastInvalidTokens.take(5).join(', ')}',
                style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Ayarlar Kartı
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<BookLookupSource>(
                          initialValue: _sourceMode,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Veri Kaynağı Önceliği',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: BookLookupSource.auto,
                              child: Text('Amazon + Kitapyurdu + Tüm Kaynaklar'),
                            ),
                            DropdownMenuItem(
                              value: BookLookupSource.amazon,
                              child: Text('Önce Doğrudan Amazon (TR + Global)'),
                            ),
                            DropdownMenuItem(
                              value: BookLookupSource.googleBooks,
                              child: Text('Google Books API'),
                            ),
                          ],
                          onChanged: _running
                              ? null
                              : (v) => setState(
                                  () => _sourceMode = v ?? BookLookupSource.auto,
                                ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _shelfCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Hedef Dolap',
                            hintText: 'Örn: N, C, A',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Paralel Bağlantı:',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 1, label: Text('1x')),
                          ButtonSegment(value: 2, label: Text('2x Hızlı')),
                          ButtonSegment(value: 3, label: Text('3x Turbo')),
                        ],
                        selected: {_concurrency},
                        onSelectionChanged: _running
                            ? null
                            : (s) => setState(() => _concurrency = s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      FilterChip(
                        selected: _downloadCovers,
                        label: const Text('HD Kapak İndir'),
                        onSelected: (v) => setState(() => _downloadCovers = v),
                      ),
                      FilterChip(
                        selected: _autoAssignCalCode,
                        label: Text(
                          'Otomatik ${appThemeNotifier.value.accessionPrefix} Kod Ata',
                        ),
                        onSelected: (v) =>
                            setState(() => _autoAssignCalCode = v),
                      ),
                      FilterChip(
                        selected: _autoSaveAsFetched,
                        label: const Text('Çekildikçe Otomatik Kaydet'),
                        onSelected: (v) =>
                            setState(() => _autoSaveAsFetched = v),
                      ),
                      FilterChip(
                        selected: _useAiFallback,
                        label: const Text('CLIProxy AI Yedeği'),
                        onSelected: (v) => setState(() => _useAiFallback = v),
                      ),
                      FilterChip(
                        selected: _speakFoundTitles,
                        label: const Text('Sesli Oku'),
                        onSelected: (v) =>
                            setState(() => _speakFoundTitles = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Ana Çalıştır / Duraklat / Kaydet Aksiyonları
          if (_running)
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _paused
                                ? 'Duraklatıldı ($queuedCount bekliyor)'
                                : 'Amazon & Kaynaklardan Çekiliyor... ${_etaText(queuedCount)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 9,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _paused = !_paused),
                          icon: Icon(
                            _paused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                          ),
                          label: Text(_paused ? 'Devam Et' : 'Duraklat'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _cancelRequested = true),
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Durdur'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else if (_queue.isNotEmpty)
            Column(
              children: [
                if (queuedCount > 0)
                  ShimmerActionButton(
                    label: '$queuedCount ISBN\'i Amazon\'dan Toplu Çek',
                    subtitle:
                        '${_concurrency}x paralel işçi · HD kapak + künye + demirbaş kodu',
                    icon: Icons.cloud_download_rounded,
                    colors: const [Color(0xFF1D4ED8), Color(0xFF0EA5E9)],
                    onTap: () => _startOrResumeBatch(),
                  ),
                if (unsavedFoundCount > 0) ...[
                  const SizedBox(height: 8),
                  ShimmerActionButton(
                    label: '$unsavedFoundCount Bulunan Kitabı Kataloğa Kaydet',
                    subtitle: 'Kapaklar ve künyeler kütüphaneye işlenir',
                    icon: Icons.save_rounded,
                    colors: const [Color(0xFF059669), Color(0xFF10B981)],
                    onTap: () => _commitFoundItemsToCatalog(silent: false),
                  ),
                ],
                if (failedCount > 0) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _startOrResumeBatch(retryFailedOnly: true),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        'Bulunamayan $failedCount ISBN\'i Yeniden Dene',
                      ),
                    ),
                  ),
                ],
              ],
            ),

          if (_queue.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    selected: _filter == 'all',
                    label: Text('Tümü (${_queue.length})'),
                    onSelected: (_) => setState(() => _filter = 'all'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    selected: _filter == 'queued',
                    label: Text('Sırada ($queuedCount)'),
                    onSelected: (_) => setState(() => _filter = 'queued'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    selected: _filter == 'found',
                    label: Text('Bulunan ($foundCount)'),
                    onSelected: (_) => setState(() => _filter = 'found'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    selected: _filter == 'failed',
                    label: Text('Bulunamayan ($failedCount)'),
                    onSelected: (_) => setState(() => _filter = 'failed'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final item in visibleQueue.take(300))
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: item.coverRef != null
                      ? BookCoverWidget(
                          book: {
                            'title': item.metadata?['title'] ?? item.isbn,
                            'coverBase64': item.coverRef,
                          },
                          width: 38,
                          height: 54,
                        )
                      : CircleAvatar(
                          backgroundColor: switch (item.status) {
                            BulkItemStatus.saved ||
                            BulkItemStatus.found =>
                              Colors.green.withValues(alpha: 0.16),
                            BulkItemStatus.fetching =>
                              scheme.primaryContainer,
                            BulkItemStatus.notFound ||
                            BulkItemStatus.error =>
                              scheme.errorContainer,
                            BulkItemStatus.queued =>
                              scheme.surfaceContainerHighest,
                          },
                          child: Icon(
                            switch (item.status) {
                              BulkItemStatus.saved => Icons.check_circle_rounded,
                              BulkItemStatus.found => Icons.download_done_rounded,
                              BulkItemStatus.fetching => Icons.sync_rounded,
                              BulkItemStatus.notFound ||
                              BulkItemStatus.error =>
                                Icons.warning_amber_rounded,
                              BulkItemStatus.queued => Icons.schedule_rounded,
                            },
                            size: 18,
                          ),
                        ),
                  title: Text(
                    item.metadata?['title']?.isNotEmpty == true
                        ? item.metadata!['title']!
                        : 'ISBN: ${item.isbn}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    item.metadata != null
                        ? [
                            if ((item.metadata!['author'] ?? '').isNotEmpty)
                              item.metadata!['author']!,
                            if ((item.metadata!['publisher'] ?? '').isNotEmpty)
                              item.metadata!['publisher']!,
                            if ((item.metadata!['source'] ?? '').isNotEmpty)
                              item.metadata!['source']!,
                            if (item.assignedAccession.isNotEmpty)
                              item.assignedAccession,
                          ].join(' · ')
                        : (item.errorMessage.isNotEmpty
                              ? item.errorMessage
                              : '${item.copies == 0 ? 'Zenginleştirme' : '${item.copies} adet'}'
                                    '${item.targetShelf.isNotEmpty ? ' · Dolap ${item.targetShelf}' : ''}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: !_running
                      ? IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() => _queue.remove(item));
                            _persistQueue();
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        )
                      : null,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Ağ aramasını beklemeden art arda 100'lerce barkodu anında kuyruğa alan Turbo Tarayıcı.
class _TurboIsbnQueueScannerPage extends StatefulWidget {
  const _TurboIsbnQueueScannerPage();

  @override
  State<_TurboIsbnQueueScannerPage> createState() =>
      _TurboIsbnQueueScannerPageState();
}

class _TurboIsbnQueueScannerPageState
    extends State<_TurboIsbnQueueScannerPage> {
  final MobileScannerController _ctrl = MobileScannerController();
  final List<String> _scanned = [];
  String? _lastIsbn;
  DateTime? _lastAt;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    final now = DateTime.now();
    for (final b in cap.barcodes) {
      final raw = b.rawValue?.trim() ?? '';
      final canon = canonicalIsbn(raw);
      if (canon == null) continue;
      if (_lastIsbn == canon &&
          _lastAt != null &&
          now.difference(_lastAt!) < const Duration(milliseconds: 1600)) {
        return;
      }
      _lastIsbn = canon;
      _lastAt = now;
      HapticFeedback.mediumImpact();
      setState(() => _scanned.insert(0, canon));
      break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uniqueCount = _scanned.toSet().length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Turbo Barkod Kuyruğu (${_scanned.length})'),
        actions: [
          IconButton(
            onPressed: () => _ctrl.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(controller: _ctrl, onDetect: _onDetect),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _lastIsbn == null
                          ? 'Barkodları peş peşe gösterin — ağ beklemeden anında kuyruğa eklenir!'
                          : 'Son eklenen: $_lastIsbn · Toplam ${_scanned.length} okutma ($uniqueCount tekil kitap)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              color: scheme.surface,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(
                    child: _scanned.isEmpty
                        ? const Center(
                            child: Text('Henüz barkod okutulmadı.'),
                          )
                        : ListView.builder(
                            itemCount: _scanned.length,
                            itemBuilder: (_, i) => ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 13,
                                child: Text(
                                  '${_scanned.length - i}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              title: Text(
                                _scanned[i],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () =>
                                    setState(() => _scanned.removeAt(i)),
                              ),
                            ),
                          ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(_scanned),
                      icon: const Icon(Icons.check_circle_rounded),
                      label: Text(
                        '${_scanned.length} Barkodu Amazon Kuyruğuna Gönder',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
