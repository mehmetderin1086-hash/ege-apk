import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_proxy_service.dart';
import 'app_theme_settings.dart';
import 'book_lookup.dart';
import 'book_visuals.dart';
import 'catalog_search.dart' show foldTurkish;
import 'cover_fetch.dart';
import 'inventory_session.dart';
import 'isbn.dart';
import 'loan_model.dart';
import 'ocr_extract.dart';
import 'school_automation_hub.dart' show findHighestAccessionNumber;

enum ShelfMatchStatus {
  matchedSameShelf('Doğru Dolapta'),
  matchedWrongShelf('Yanlış Dolapta'),
  newBook('Katalogda Yok (Yeni)');

  const ShelfMatchStatus(this.label);
  final String label;
}

class DetectedShelfBook {
  const DetectedShelfBook({
    required this.index,
    this.photoIndex = 0,
    required this.title,
    this.author = '',
    this.publisher = '',
    this.category = '',
    this.isbn = '',
    this.copiesCount = 1,
    this.box2d,
    this.confidence = 0.85,
    this.selected = true,
    this.matchedBookId,
    this.matchedShelf = '',
    this.matchedAccession = '',
    this.matchStatus = ShelfMatchStatus.newBook,
  });

  final int index;
  final int photoIndex;
  final String title;
  final String author;
  final String publisher;
  final String category;
  final String isbn;
  final int copiesCount;

  /// `[ymin, xmin, ymax, xmax]` 0..1000 normalize kutu koordinatları.
  final List<int>? box2d;
  final double confidence;
  final bool selected;
  final String? matchedBookId;
  final String matchedShelf;
  final String matchedAccession;
  final ShelfMatchStatus matchStatus;

  DetectedShelfBook copyWith({
    int? index,
    int? photoIndex,
    String? title,
    String? author,
    String? publisher,
    String? category,
    String? isbn,
    int? copiesCount,
    List<int>? box2d,
    double? confidence,
    bool? selected,
    String? matchedBookId,
    bool clearMatchedBookId = false,
    String? matchedShelf,
    String? matchedAccession,
    ShelfMatchStatus? matchStatus,
  }) {
    return DetectedShelfBook(
      index: index ?? this.index,
      photoIndex: photoIndex ?? this.photoIndex,
      title: title ?? this.title,
      author: author ?? this.author,
      publisher: publisher ?? this.publisher,
      category: category ?? this.category,
      isbn: isbn ?? this.isbn,
      copiesCount: copiesCount ?? this.copiesCount,
      box2d: box2d ?? this.box2d,
      confidence: confidence ?? this.confidence,
      selected: selected ?? this.selected,
      matchedBookId: clearMatchedBookId
          ? null
          : (matchedBookId ?? this.matchedBookId),
      matchedShelf: matchedShelf ?? this.matchedShelf,
      matchedAccession: matchedAccession ?? this.matchedAccession,
      matchStatus: matchStatus ?? this.matchStatus,
    );
  }
}

class MissingShelfBook {
  const MissingShelfBook({
    required this.book,
    required this.expectedOnShelf,
    required this.activeLoanCount,
  });

  final Map<String, dynamic> book;
  final int expectedOnShelf;
  final int activeLoanCount;
}

class ShelfComparisonReport {
  const ShelfComparisonReport({
    required this.items,
    required this.missingBooks,
    required this.physicalTotal,
    required this.sameShelfCount,
    required this.wrongShelfCount,
    required this.newBookCount,
  });

  final List<DetectedShelfBook> items;
  final List<MissingShelfBook> missingBooks;
  final int physicalTotal;
  final int sameShelfCount;
  final int wrongShelfCount;
  final int newBookCount;
}

String _asciiFoldTr(String value) => foldTurkish(value)
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ş', 's')
    .replaceAll('ı', 'i')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c')
    .replaceAll('â', 'a')
    .replaceAll('î', 'i')
    .replaceAll('û', 'u');

/// Dolap / raf etiketlerini esnek karşılaştırmak için normalize eder (`Dolap C` == `C`).
String _normalizeShelfToken(String raw) {
  var folded = _asciiFoldTr(raw.trim());
  folded = folded
      .replaceAll(RegExp(r'\bdolap\b'), '')
      .replaceAll(RegExp(r'\braf\b'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  return folded;
}

bool _shelvesCompatible(String bookShelf, String expectedShelf) {
  final exp = _normalizeShelfToken(expectedShelf);
  if (exp.isEmpty) return true;
  final bk = _normalizeShelfToken(bookShelf);
  if (bk.isEmpty) return false;
  if (bk == exp) return true;
  final bkTokens = bk.split(' ').where((e) => e.isNotEmpty).toList();
  final expTokens = exp.split(' ').where((e) => e.isNotEmpty).toList();
  if (bkTokens.isNotEmpty &&
      expTokens.isNotEmpty &&
      bkTokens.first == expTokens.first) {
    return true;
  }
  return false;
}

Set<String> _titleWordTokens(String text) {
  final folded = _asciiFoldTr(text)
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (folded.isEmpty) return const <String>{};
  return folded
      .split(' ')
      .where((w) => w.length >= 2)
      .toSet();
}

double _spineMatchScore(
  DetectedShelfBook detected,
  Map<String, dynamic> catalogBook,
) {
  final detIsbn = canonicalIsbn(detected.isbn);
  final catIsbn = canonicalIsbn((catalogBook['isbn'] ?? '').toString());
  if (detIsbn != null && catIsbn != null && detIsbn == catIsbn) {
    return 1.0;
  }

  final detTitle = _asciiFoldTr(detected.title)
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final catTitle = _asciiFoldTr((catalogBook['title'] ?? '').toString())
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (detTitle.isEmpty || catTitle.isEmpty) return 0;

  double score = 0;
  if (detTitle == catTitle) {
    score = 0.94;
  } else {
    final w1 = _titleWordTokens(detTitle);
    final w2 = _titleWordTokens(catTitle);
    if (w1.isNotEmpty && w2.isNotEmpty) {
      final inter = w1.intersection(w2).length;
      final union = w1.union(w2).length;
      final jaccard = union == 0 ? 0.0 : inter / union;
      final minLen = w1.length < w2.length ? w1.length : w2.length;
      final containment = minLen == 0 ? 0.0 : inter / minLen;
      score = (jaccard * 0.65) + (containment * 0.35);
    }
    if (score < 0.78 &&
        detTitle.length >= 6 &&
        catTitle.length >= 6 &&
        (catTitle.contains(detTitle) || detTitle.contains(catTitle))) {
      final ratio = detTitle.length < catTitle.length
          ? detTitle.length / catTitle.length
          : catTitle.length / detTitle.length;
      if (ratio >= 0.55) {
        score = score < 0.78 ? 0.78 : score;
      }
    }
  }

  if (score < 0.58) return 0;

  final detAuthor = _titleWordTokens(detected.author);
  final catAuthor = _titleWordTokens((catalogBook['author'] ?? '').toString());
  if (detAuthor.isNotEmpty && catAuthor.isNotEmpty) {
    if (detAuthor.intersection(catAuthor).isNotEmpty) {
      score = (score + 0.08).clamp(0.0, 0.99);
    } else if (score < 0.90) {
      score -= 0.14;
    }
  }
  return score;
}

/// Fotoğraftan okunan sırt listesini mevcut 2.892+ kitaplık katalogla karşılaştırır:
/// - Doğru dolapta olanları, başka dolaba kayıtlı olanları ve katalogda hiç olmayan yeni kitapları ayırır.
/// - Seçili dolapta olması gerektiği hâlde fotoğrafta görünmeyen eksik/ödünçteki kitapları listeler.
ShelfComparisonReport matchShelfSpinesAgainstCatalog(
  List<DetectedShelfBook> detected,
  List<Map<String, dynamic>> catalog, {
  required String expectedShelf,
  int unreadableExtraSpines = 0,
}) {
  final activeCatalog = catalog
      .where((b) => b['deletedAt'] == null && b['isWithdrawn'] != true)
      .toList();

  final matchedCatalogIds = <String>{};
  final resolved = <DetectedShelfBook>[];
  var sameShelf = 0;
  var wrongShelf = 0;
  var newCount = 0;
  var physicalCopies = unreadableExtraSpines < 0 ? 0 : unreadableExtraSpines;

  for (var i = 0; i < detected.length; i++) {
    final item = detected[i];
    physicalCopies += item.copiesCount < 1 ? 1 : item.copiesCount;

    Map<String, dynamic>? bestBook;
    var bestScore = 0.0;
    for (final b in activeCatalog) {
      var sc = _spineMatchScore(item, b);
      if (sc <= 0) continue;
      final bShelf = inventoryBookPlace(b);
      if (expectedShelf.trim().isNotEmpty &&
          _shelvesCompatible(bShelf, expectedShelf)) {
        sc += 0.02;
      }
      if (sc > bestScore) {
        bestScore = sc;
        bestBook = b;
      }
    }

    if (bestBook != null && bestScore >= 0.72) {
      final id = (bestBook['id'] ?? '').toString();
      matchedCatalogIds.add(id);
      final bShelf = inventoryBookPlace(bestBook);
      final same = _shelvesCompatible(bShelf, expectedShelf);
      final status = same
          ? ShelfMatchStatus.matchedSameShelf
          : ShelfMatchStatus.matchedWrongShelf;
      if (same) {
        sameShelf++;
      } else {
        wrongShelf++;
      }
      resolved.add(
        item.copyWith(
          index: i + 1,
          matchedBookId: id,
          matchedShelf: bShelf,
          matchedAccession: (bestBook['accessionCode'] ?? '').toString(),
          matchStatus: status,
          author: item.author.trim().isNotEmpty
              ? item.author
              : (bestBook['author'] ?? '').toString(),
          publisher: item.publisher.trim().isNotEmpty
              ? item.publisher
              : (bestBook['publisher'] ?? '').toString(),
          category: item.category.trim().isNotEmpty
              ? item.category
              : (bestBook['category'] ?? '').toString(),
          isbn: item.isbn.trim().isNotEmpty
              ? item.isbn
              : (bestBook['isbn'] ?? '').toString(),
        ),
      );
    } else {
      newCount++;
      resolved.add(
        item.copyWith(
          index: i + 1,
          clearMatchedBookId: true,
          matchedShelf: '',
          matchedAccession: '',
          matchStatus: ShelfMatchStatus.newBook,
        ),
      );
    }
  }

  final missing = <MissingShelfBook>[];
  if (expectedShelf.trim().isNotEmpty) {
    for (final b in activeCatalog) {
      final id = (b['id'] ?? '').toString();
      if (matchedCatalogIds.contains(id)) continue;
      final bShelf = inventoryBookPlace(b);
      if (!_shelvesCompatible(bShelf, expectedShelf)) continue;
      final avail = physicalAvailableCopies(b);
      final loans = activeLoans(b).length;
      if (avail > 0 || loans > 0) {
        missing.add(
          MissingShelfBook(
            book: b,
            expectedOnShelf: avail,
            activeLoanCount: loans,
          ),
        );
      }
    }
    missing.sort((a, b) => b.expectedOnShelf.compareTo(a.expectedOnShelf));
  }

  return ShelfComparisonReport(
    items: resolved,
    missingBooks: missing,
    physicalTotal: physicalCopies,
    sameShelfCount: sameShelf,
    wrongShelfCount: wrongShelf,
    newBookCount: newCount,
  );
}

/// CLIProxyAPI / Gemini 3.8 Flash JSON yanıtını güvenli `DetectedShelfBook` listesine dönüştürür.
({
  List<DetectedShelfBook> books,
  int unreadableSpines,
  int reportedTotalSpines,
})
parseShelfAiJson(dynamic decoded, {int photoIndex = 0, int startIndex = 1}) {
  List<dynamic> rawList = const [];
  var unreadable = 0;
  var totalReported = 0;

  if (decoded is List) {
    rawList = decoded;
  } else if (decoded is Map) {
    if (decoded['books'] is List) {
      rawList = decoded['books'] as List;
    } else if (decoded['spines'] is List) {
      rawList = decoded['spines'] as List;
    } else if (decoded['items'] is List) {
      rawList = decoded['items'] as List;
    }
    unreadable = (decoded['unreadable_spines'] as num?)?.toInt() ??
        (decoded['unreadableCount'] as num?)?.toInt() ??
        0;
    totalReported = (decoded['total_physical_spines'] as num?)?.toInt() ??
        (decoded['totalPhysicalCount'] as num?)?.toInt() ??
        0;
  }

  final parsed = <DetectedShelfBook>[];
  var idx = startIndex;
  for (final entry in rawList) {
    if (entry is! Map) continue;
    final title = (entry['title'] ?? entry['name'] ?? '').toString().trim();
    if (title.isEmpty) continue;

    List<int>? box;
    final rawBox = entry['box_2d'] ?? entry['box2d'] ?? entry['bbox'];
    if (rawBox is List && rawBox.length >= 4) {
      final nums = rawBox
          .take(4)
          .map((e) => ((e as num?)?.round() ?? 0).clamp(0, 1000))
          .toList();
      if (nums[2] > nums[0] && nums[3] > nums[1]) {
        box = nums;
      }
    }

    final copies = ((entry['copies'] ?? entry['quantity'] ?? 1) as num?)
            ?.toInt()
            .clamp(1, 50) ??
        1;
    final conf = ((entry['confidence'] as num?)?.toDouble() ?? 0.88).clamp(
      0.1,
      1.0,
    );

    parsed.add(
      DetectedShelfBook(
        index: idx++,
        photoIndex: photoIndex,
        title: title,
        author: (entry['author'] ?? '').toString().trim(),
        publisher: (entry['publisher'] ?? '').toString().trim(),
        category: (entry['category'] ?? '').toString().trim(),
        isbn: cleanIsbnInput((entry['isbn'] ?? '').toString()),
        copiesCount: copies,
        box2d: box,
        confidence: conf,
      ),
    );
  }

  if (totalReported > 0 && unreadable == 0) {
    final sumParsed = parsed.fold<int>(0, (s, b) => s + b.copiesCount);
    if (totalReported > sumParsed) {
      unreadable = totalReported - sumParsed;
    }
  }

  return (
    books: parsed,
    unreadableSpines: unreadable < 0 ? 0 : unreadable,
    reportedTotalSpines: totalReported,
  );
}

/// Çevrimdışı / yerel ML Kit OCR satırlarından temel sırt adayları çıkarır.
List<DetectedShelfBook> extractSpinesFromLocalOcr(
  OcrDocument doc, {
  int photoIndex = 0,
  int startIndex = 1,
}) {
  final out = <DetectedShelfBook>[];
  final seen = <String>{};
  var idx = startIndex;
  for (final line in doc.lines) {
    final txt = line.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (txt.length < 4 || txt.length > 90) continue;
    // Yalnızca sayı veya yayınevi gürültüsü olan kısa satırları atla
    if (RegExp(r'^[0-9\W]+$').hasMatch(txt)) continue;
    final folded = foldTurkish(txt);
    if (folded == 'yayinlari' ||
        folded == 'yayinevi' ||
        folded == 'roman' ||
        folded == 'hikaye') {
      continue;
    }
    if (!seen.add(folded)) continue;
    out.add(
      DetectedShelfBook(
        index: idx++,
        photoIndex: photoIndex,
        title: txt,
        confidence: 0.55,
      ),
    );
  }
  return out;
}

class _ShelfPhotoEntry {
  _ShelfPhotoEntry({
    required this.bytes,
    required this.label,
    required this.aspectRatio,
  });

  final Uint8List bytes;
  final String label;
  final double aspectRatio;
  int unreadableSpines = 0;
  String sourceNote = '';
}

class ShelfPhotoScannerPage extends StatefulWidget {
  const ShelfPhotoScannerPage({
    super.key,
    required this.initialBooks,
    required this.onSaveBooks,
    this.onSaveInventorySession,
  });

  final List<Map<String, dynamic>> initialBooks;
  final Future<void> Function(List<Map<String, dynamic>> updated) onSaveBooks;
  final Future<bool> Function(InventorySession session)? onSaveInventorySession;

  @override
  State<ShelfPhotoScannerPage> createState() => _ShelfPhotoScannerPageState();
}

class _ShelfPhotoScannerPageState extends State<ShelfPhotoScannerPage> {
  static const _camChannel = MethodChannel('kitapbul/camera');
  static const _fileChannel = MethodChannel('kitapbul/files');
  static const _ocrChannel = MethodChannel('kitapbul/ocr');

  late List<Map<String, dynamic>> _books = List.of(widget.initialBooks);
  final List<_ShelfPhotoEntry> _photos = [];
  List<DetectedShelfBook> _rawDetections = [];
  int _selectedPhotoIdx = 0;
  int? _highlightedSpineIndex;

  final _shelfCtrl = TextEditingController();
  bool _analyzing = false;
  bool _savingBatch = false;
  bool _showBoxes = true;
  bool _enrichOnlineOnAdd = true;
  bool _autoAssignCal = true;
  String _statusText = '';
  String _filter = 'all';

  @override
  void dispose() {
    _shelfCtrl.dispose();
    super.dispose();
  }

  List<String> get _knownShelves {
    final set = <String>{};
    for (final b in _books) {
      if (b['deletedAt'] != null) continue;
      final s = inventoryBookPlace(b).trim();
      if (s.isNotEmpty) set.add(s);
    }
    final sorted = set.toList()..sort();
    return sorted;
  }

  int get _totalUnreadableSpines =>
      _photos.fold<int>(0, (sum, p) => sum + p.unreadableSpines);

  ShelfComparisonReport get _report => matchShelfSpinesAgainstCatalog(
    _rawDetections,
    _books,
    expectedShelf: _shelfCtrl.text,
    unreadableExtraSpines: _totalUnreadableSpines,
  );

  Future<double> _decodeAspectRatio(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width.toDouble();
      final h = frame.image.height.toDouble();
      frame.image.dispose();
      if (w > 0 && h > 0) return w / h;
    } catch (_) {}
    return 4 / 3;
  }

  Future<void> _captureShelfCamera() async {
    if (_analyzing || _savingBatch) return;
    try {
      final bytes = await _camChannel.invokeMethod<Uint8List>('capture');
      if (bytes == null || bytes.isEmpty || !mounted) return;
      final ratio = await _decodeAspectRatio(bytes);
      setState(() {
        _photos.add(
          _ShelfPhotoEntry(
            bytes: bytes,
            label: 'Raf Fotoğrafı ${_photos.length + 1}',
            aspectRatio: ratio,
          ),
        );
        _selectedPhotoIdx = _photos.length - 1;
      });
      await _analyzePhotoIndexes([_photos.length - 1]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kamera açılamadı: $e')),
        );
      }
    }
  }

  Future<void> _pickMultipleShelfPhotos() async {
    if (_analyzing || _savingBatch) return;
    try {
      final rawList = await _fileChannel.invokeMethod<List>(
        'pickMultipleImages',
      );
      if (rawList == null || rawList.isEmpty || !mounted) return;
      final addedIndexes = <int>[];
      for (final item in rawList) {
        if (item is Uint8List && item.isNotEmpty) {
          final ratio = await _decodeAspectRatio(item);
          _photos.add(
            _ShelfPhotoEntry(
              bytes: item,
              label: 'Raf Fotoğrafı ${_photos.length + 1}',
              aspectRatio: ratio,
            ),
          );
          addedIndexes.add(_photos.length - 1);
        }
      }
      if (addedIndexes.isEmpty || !mounted) return;
      setState(() => _selectedPhotoIdx = addedIndexes.first);
      await _analyzePhotoIndexes(addedIndexes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Galeri seçimi başarısız: $e')),
        );
      }
    }
  }

  Future<void> _analyzePhotoIndexes(List<int> indexes) async {
    if (indexes.isEmpty) return;
    setState(() {
      _analyzing = true;
      _statusText = 'Raf fotoğrafları CLIProxy Gemini ile taranıyor...';
    });

    try {
      for (var step = 0; step < indexes.length; step++) {
        final pIdx = indexes[step];
        if (pIdx < 0 || pIdx >= _photos.length) continue;
        final photo = _photos[pIdx];

        // Bu fotoğrafa ait eski tespitleri temizle
        _rawDetections.removeWhere((d) => d.photoIndex == pIdx);

        if (mounted) {
          setState(() {
            _statusText =
                '${step + 1}/${indexes.length} · ${photo.label} üzerinde kitap sırtları okunuyor ve sayılıyor...';
          });
        }

        List<DetectedShelfBook> found = [];
        int unreadable = 0;
        String note = '';

        try {
          const sysPrompt = '''
Sen uzman bir okul kütüphanesi raf sayım ve kitap sırtı (spine) okuma yapay zekâsısın.
Verilen raf fotoğrafındaki TÜM fiziksel kitap sırtlarını soldan sağa (ve varsa üst raftan alt rafa) tek tek tespit et ve say.
Yalnızca geçerli bir JSON nesnesi döndür:
{
  "total_physical_spines": 25,
  "unreadable_spines": 2,
  "books": [
    {
      "title": "Kürk Mantolu Madonna",
      "author": "Sabahattin Ali",
      "publisher": "Yapı Kredi Yayınları",
      "category": "Roman",
      "copies": 1,
      "confidence": 0.95,
      "box_2d": [120, 45, 880, 92]
    }
  ]
}
Kurallar:
1. "box_2d" her kitabın sırtını çevreleyen [ymin, xmin, ymax, xmax] (0 ile 1000 arası tam sayı) koordinatıdır.
2. Yan yana aynı kitaptan birden fazla nüsha varsa ayrı ayrı kutulayabilir veya "copies" sayısını artırabilirsin; ancak "total_physical_spines" raftaki gerçek fiziksel kitap adedini tam vermelidir.
3. Yazısı bulanık/okunamayan sırtları uydurma; onları "unreadable_spines" sayısına ekle.
4. Türkçe karakterleri (ğ, ü, ş, ı, ö, ç, İ) doğru kullan.
''';
          final decoded = await AiProxyClient.generateStructuredJson(
            systemPrompt: sysPrompt,
            userPrompt:
                'Bu kütüphane rafı fotoğrafındaki tüm kitapları say, sırt yazılarından kitap adı, yazar, yayınevi ve [ymin, xmin, ymax, xmax] kutularını çıkar.',
            images: [AiImagePart(bytes: photo.bytes, label: photo.label)],
          );
          final parsed = parseShelfAiJson(
            decoded,
            photoIndex: pIdx,
            startIndex: _rawDetections.length + 1,
          );
          found = parsed.books;
          unreadable = parsed.unreadableSpines;
          note = 'CLIProxy Gemini AI (${found.length} sırt)';
        } catch (aiErr) {
          // Yerel ML Kit OCR yedeği
          try {
            final rawOcr = await _ocrChannel.invokeMethod<Object>(
              'recognize',
              photo.bytes,
            );
            final doc = OcrDocument.fromPlatform(rawOcr);
            found = extractSpinesFromLocalOcr(
              doc,
              photoIndex: pIdx,
              startIndex: _rawDetections.length + 1,
            );
            note = 'Cihaz İçi ML Kit OCR (${found.length} satır)';
          } catch (_) {}
          if (mounted && found.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'CLIProxy yanıt vermedi ($aiErr). Üstteki Hub ikonundan CLIProxy anahtarınızı kontrol edin.',
                ),
              ),
            );
          }
        }

        photo.unreadableSpines = unreadable;
        photo.sourceNote = note;
        _rawDetections.addAll(found);
      }

      // Sıra numaralarını yeniden diz
      _reindexDetections();
    } finally {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _statusText = '';
        });
      }
    }
  }

  void _reindexDetections() {
    _rawDetections = [
      for (var i = 0; i < _rawDetections.length; i++)
        _rawDetections[i].copyWith(index: i + 1),
    ];
  }

  Future<void> _openIphoneShelfSessionsSheet() async {
    List<Map<String, dynamic>> shelfSessions = [];
    try {
      final raw = await rootBundle.loadString(
        'assets/seed/tarama-oturumlari.json',
      );
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            final pending = item['pendingBooks'];
            if (pending is List && pending.isNotEmpty) {
              shelfSessions.add(Map<String, dynamic>.from(item));
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('iPhone tarama oturumları okunamadı: $e')),
        );
      }
      return;
    }

    if (!mounted) return;
    if (shelfSessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aktarılacak bekleyen iPhone raf oturumu bulunamadı.'),
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            const Text(
              'iPhone Raf & Fotoğraf Tarama Oturumları',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'iPhone yedeklerinizdeki raf taramalarını tek dokunuşla yükleyip mevcut katalogla karşılaştırın.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            for (final s in shelfSessions)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text((s['cabinet'] ?? '?').toString()),
                  ),
                  title: Text(
                    'Dolap ${(s['cabinet'] ?? '-')} · ${(s['pendingBooks'] as List).length} Kitap',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Tür: ${s['kind']} · Tarih: ${(s['createdAt'] ?? '').toString().split('T').first}',
                  ),
                  trailing: const Icon(Icons.download_rounded),
                  onTap: () => Navigator.of(ctx).pop(s),
                ),
              ),
          ],
        ),
      ),
    );

    if (picked == null || !mounted) return;
    final cab = (picked['cabinet'] ?? '').toString().trim();
    final pending = (picked['pendingBooks'] as List).whereType<Map>().toList();
    setState(() {
      if (cab.isNotEmpty && _shelfCtrl.text.trim().isEmpty) {
        _shelfCtrl.text = cab.length == 1 ? 'Dolap $cab' : cab;
      }
      var idx = _rawDetections.length + 1;
      for (final p in pending) {
        final title = (p['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        _rawDetections.add(
          DetectedShelfBook(
            index: idx++,
            photoIndex: -1,
            title: title,
            author: (p['author'] ?? '').toString().trim(),
            publisher: (p['publisher'] ?? '').toString().trim(),
            category: (p['category'] ?? '').toString().trim(),
            isbn: cleanIsbnInput((p['isbn'] ?? '').toString()),
            copiesCount: ((p['quantity'] as num?)?.toInt() ?? 1).clamp(1, 50),
            confidence: 0.92,
          ),
        );
      }
      _reindexDetections();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${pending.length} kitaplık iPhone raf taraması karşılaştırma tablosuna yüklendi.',
        ),
      ),
    );
  }

  Future<void> _bulkAddNewBooks(ShelfComparisonReport report) async {
    final candidates = report.items
        .where(
          (b) =>
              b.selected &&
              b.matchStatus == ShelfMatchStatus.newBook &&
              b.title.trim().isNotEmpty,
        )
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Eklenecek seçili yeni kitap bulunmuyor.'),
        ),
      );
      return;
    }

    setState(() {
      _savingBatch = true;
      _statusText = '${candidates.length} yeni kitap kataloğa hazırlanıyor...';
    });

    try {
      final cfg = appThemeNotifier.value;
      var nextAcc =
          findHighestAccessionNumber(_books, prefix: cfg.accessionPrefix) + 1;
      final addedBooks = <Map<String, dynamic>>[];
      final targetShelf = _shelfCtrl.text.trim();

      for (var i = 0; i < candidates.length; i++) {
        final item = candidates[i];
        if (mounted) {
          setState(() {
            _statusText =
                '${i + 1}/${candidates.length} · "${item.title}" zenginleştiriliyor...';
          });
        }

        Map<String, String>? online;
        String? coverRef;
        if (_enrichOnlineOnAdd) {
          try {
            final canon = canonicalIsbn(item.isbn);
            if (canon != null) {
              online = await lookupIsbn(canon);
            } else {
              online = await lookupKitapyurduFirstMatch(
                title: item.title,
                author: item.author,
                publisher: item.publisher,
              );
            }
            final foundIsbn = canonicalIsbn(online?['isbn'] ?? item.isbn);
            final coverUrl = (online?['coverUrl'] ?? '').trim();
            if (coverUrl.isNotEmpty) {
              final dl = await fetchCoverBytesFromUrl(coverUrl);
              if (dl != null) coverRef = storeCoverBytes(dl);
            }
            if (coverRef == null && foundIsbn != null) {
              final dl = await fetchBestCover(foundIsbn);
              if (dl != null) coverRef = storeCoverBytes(dl.bytes);
            }
          } catch (_) {}
        }

        final qty = item.copiesCount.clamp(1, 50);
        final codes = _autoAssignCal
            ? <String>[
                for (var c = 0; c < qty; c++)
                  '${cfg.accessionPrefix}${(nextAcc++).toString().padLeft(cfg.accessionDigits, '0')}',
              ]
            : const <String>[];

        String pick(String val, String key) {
          if (val.trim().isNotEmpty) return val.trim();
          return (online?[key] ?? '').trim();
        }

        final now = DateTime.now();
        addedBooks.add(
          normalizeBook({
            'id': 'shelf-${now.microsecondsSinceEpoch}-$i',
            'title': pick(item.title, 'title'),
            'author': pick(item.author, 'author'),
            'publisher': pick(item.publisher, 'publisher'),
            'isbn': canonicalIsbn(pick(item.isbn, 'isbn')) ??
                pick(item.isbn, 'isbn'),
            'category': pick(item.category, 'category'),
            'publicationYear': (online?['publicationYear'] ?? '').trim(),
            'pageCount': (online?['pageCount'] ?? '').trim(),
            'language': (online?['language'] ?? 'Türkçe').trim(),
            'shelf': targetShelf,
            'accessionCode': codes.join('; '),
            'quantity': qty,
            'coverBase64': coverRef,
            'loans': <Map<String, dynamic>>[],
          }),
        );
      }

      final updated = [..._books, ...addedBooks];
      await widget.onSaveBooks(updated);
      if (!mounted) return;
      setState(() => _books = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${addedBooks.length} yeni kitap demirbaş kodlarıyla kataloğa eklendi!',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingBatch = false;
          _statusText = '';
        });
      }
    }
  }

  Future<void> _moveMisplacedBooksToCurrentShelf(
    ShelfComparisonReport report,
  ) async {
    final targetShelf = _shelfCtrl.text.trim();
    if (targetShelf.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce üstten bu rafın Dolap/Raf adını girin veya seçin.'),
        ),
      );
      return;
    }
    final misplacedIds = report.items
        .where(
          (b) =>
              b.selected &&
              b.matchStatus == ShelfMatchStatus.matchedWrongShelf &&
              b.matchedBookId != null,
        )
        .map((b) => b.matchedBookId!)
        .toSet();

    if (misplacedIds.isEmpty) return;

    setState(() => _savingBatch = true);
    try {
      final updated = [
        for (final b in _books)
          if (misplacedIds.contains(b['id']))
            normalizeBook({...b, 'shelf': targetShelf})
          else
            b,
      ];
      await widget.onSaveBooks(updated);
      if (!mounted) return;
      setState(() => _books = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${misplacedIds.length} kitabın dolap konumu "$targetShelf" olarak güncellendi.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingBatch = false);
    }
  }

  Future<void> _saveAsOfficialInventorySession(
    ShelfComparisonReport report,
  ) async {
    if (widget.onSaveInventorySession == null) return;
    try {
      final rawTarget = _shelfCtrl.text.trim();
      final validLocs = inventoryLocations(_books);
      String? matchedLoc;
      if (rawTarget.isNotEmpty) {
        for (final loc in validLocs) {
          if (_shelvesCompatible(loc, rawTarget)) {
            matchedLoc = loc;
            break;
          }
        }
      }

      var session = startInventory(
        _books,
        name: rawTarget.isEmpty
            ? 'Raf Fotoğraf Sayımı'
            : '$rawTarget Raf Fotoğraf Sayımı',
        operatorName: 'Yapay Zekâ Raf Tarayıcı',
        location: matchedLoc,
      );

      final validEntryIds = {
        for (final e in session.entries) (e['id'] as String).toUpperCase(),
      };

      for (final item in report.items) {
        final id = item.matchedBookId;
        if (id == null || !validEntryIds.contains(id.toUpperCase())) continue;
        final count = item.copiesCount.clamp(1, 20);
        for (var c = 0; c < count; c++) {
          session = recordManualInventory(session, id);
        }
      }

      final ok = await widget.onSaveInventorySession!(session);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Resmî envanter sayım oturumu oluşturuldu (${session.events.length} nüsha işlendi).'
                : 'Envanter oturumu kaydedilemedi.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Envanter oturumu oluşturulamadı: $e')),
        );
      }
    }
  }

  Future<void> _editDetectedSpine(DetectedShelfBook item) async {
    final tCtrl = TextEditingController(text: item.title);
    final aCtrl = TextEditingController(text: item.author);
    final pCtrl = TextEditingController(text: item.publisher);
    final cCtrl = TextEditingController(text: item.copiesCount.toString());

    final edited = await showDialog<DetectedShelfBook>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('#${item.index} Sırt Kaydını Düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tCtrl,
                decoration: const InputDecoration(labelText: 'Kitap Adı'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: aCtrl,
                decoration: const InputDecoration(labelText: 'Yazar'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pCtrl,
                decoration: const InputDecoration(labelText: 'Yayınevi'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: cCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Raftaki Adet'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop(
                item.copyWith(
                  title: tCtrl.text.trim(),
                  author: aCtrl.text.trim(),
                  publisher: pCtrl.text.trim(),
                  copiesCount:
                      (int.tryParse(cCtrl.text.trim()) ?? 1).clamp(1, 50),
                ),
              );
            },
            child: const Text('Güncelle'),
          ),
        ],
      ),
    );

    if (edited == null || !mounted) return;
    setState(() {
      final pos = _rawDetections.indexWhere((x) => x.index == item.index);
      if (pos >= 0) _rawDetections[pos] = edited;
    });
  }

  Color _statusColor(ShelfMatchStatus status) {
    return switch (status) {
      ShelfMatchStatus.matchedSameShelf => Colors.green.shade600,
      ShelfMatchStatus.matchedWrongShelf => Colors.orange.shade800,
      ShelfMatchStatus.newBook => Colors.deepPurple.shade600,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final report = _report;
    final shelves = _knownShelves;

    final visibleItems = report.items.where((item) {
      return switch (_filter) {
        'new' => item.matchStatus == ShelfMatchStatus.newBook,
        'wrong' => item.matchStatus == ShelfMatchStatus.matchedWrongShelf,
        'same' => item.matchStatus == ShelfMatchStatus.matchedSameShelf,
        _ => true,
      };
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Raf Fotoğrafından Toplu Kitap Sayma'),
        actions: [
          IconButton(
            tooltip: 'CLIProxyAPI & Gemini Ayarları',
            onPressed: () => showAiProxySettingsSheet(context),
            icon: const Icon(Icons.hub_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
        children: [
          // Görsel Başlık Kartı
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                SizedBox(
                  height: 126,
                  width: double.infinity,
                  child: Image.asset(
                    'assets/images/ai_vision_banner.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.78),
                          Colors.black.withValues(alpha: 0.35),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 14,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ValueListenableBuilder<AiProxySettings>(
                        valueListenable: aiSettingsNotifier,
                        builder: (_, cfg, _) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.tealAccent.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.tealAccent.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            '${cfg.mode.title} · ${cfg.visionModel}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Rafı Çekin: Yapay Zekâ Kitap Sırtlarını Tek Tek Saysın ve Katalogla Eşleştirsin',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Dolap Seçimi
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _shelfCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Sayılan Dolap / Raf Adı (Karşılaştırma İçin)',
                      hintText: 'Örn: Dolap C veya A-2',
                      prefixIcon: const Icon(Icons.shelves),
                      suffixIcon: _shelfCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () => setState(_shelfCtrl.clear),
                              icon: const Icon(Icons.clear_rounded),
                            ),
                    ),
                  ),
                  if (shelves.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final s in shelves.take(18))
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  s,
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                selected: _shelvesCompatible(_shelfCtrl.text, s) &&
                                    _shelfCtrl.text.trim().isNotEmpty,
                                onSelected: (_) =>
                                    setState(() => _shelfCtrl.text = s),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _analyzing ? null : _captureShelfCamera,
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: const Text('Raf Fotoğrafı Çek'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _analyzing ? null : _pickMultipleShelfPhotos,
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('Çoklu Raf Foto Seç'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _analyzing ? null : _openIphoneShelfSessionsSheet,
                        icon: const Icon(Icons.phone_iphone_rounded),
                        label: const Text('iPhone Raf Oturumu Yükle'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (_analyzing || _savingBatch) ...[
            const SizedBox(height: 10),
            Card(
              color: scheme.primaryContainer.withValues(alpha: 0.55),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.6),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusText,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Etkileşimli Raf Fotoğrafı ve Sırt Kutuları
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (_photos.length > 1)
              SizedBox(
                height: 62,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, idx) {
                    final selected = idx == _selectedPhotoIdx;
                    return InkWell(
                      onTap: () => setState(() => _selectedPhotoIdx = idx),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.memory(
                            _photos[idx].bytes,
                            width: 72,
                            height: 54,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            _buildAnnotatedPhotoCard(report),
          ],

          // KPI Özeti ve Toplu İşlemler
          if (report.items.isNotEmpty || report.missingBooks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _kpiChip(
                  'Fiziksel Kitap',
                  '${report.physicalTotal}',
                  Icons.inventory_2_rounded,
                  scheme.primary,
                ),
                _kpiChip(
                  'Okunan Sırt',
                  '${report.items.length}',
                  Icons.auto_awesome_rounded,
                  Colors.teal,
                ),
                _kpiChip(
                  'Doğru Rafta',
                  '${report.sameShelfCount}',
                  Icons.check_circle_rounded,
                  Colors.green.shade700,
                ),
                _kpiChip(
                  'Yanlış Rafta',
                  '${report.wrongShelfCount}',
                  Icons.warning_amber_rounded,
                  Colors.orange.shade800,
                ),
                _kpiChip(
                  'Yeni Kitap',
                  '${report.newBookCount}',
                  Icons.fiber_new_rounded,
                  Colors.deepPurple,
                ),
                if (_shelfCtrl.text.trim().isNotEmpty)
                  _kpiChip(
                    'Rafta Görünmeyen',
                    '${report.missingBooks.length}',
                    Icons.search_off_rounded,
                    scheme.error,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Toplu Aksiyon Kartı
            Card(
              color: scheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Toplu Kataloglama & Raf Düzenleme İşlemleri',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Yeni kitapları eklerken Amazon & Kitapyurdu kapağı/ISBN indir',
                      ),
                      value: _enrichOnlineOnAdd,
                      onChanged: (v) => setState(() => _enrichOnlineOnAdd = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Otomatik ${appThemeNotifier.value.accessionPrefix} demirbaş kodu üret',
                      ),
                      value: _autoAssignCal,
                      onChanged: (v) => setState(() => _autoAssignCal = v),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (report.newBookCount > 0)
                          FilledButton.icon(
                            onPressed: _savingBatch
                                ? null
                                : () => _bulkAddNewBooks(report),
                            icon: const Icon(Icons.playlist_add_check_rounded),
                            label: Text(
                              'Yeni Kitapları Kataloğa Ekle (${report.newBookCount})',
                            ),
                          ),
                        if (report.wrongShelfCount > 0 &&
                            _shelfCtrl.text.trim().isNotEmpty)
                          FilledButton.tonalIcon(
                            onPressed: _savingBatch
                                ? null
                                : () => _moveMisplacedBooksToCurrentShelf(
                                    report,
                                  ),
                            icon: const Icon(Icons.drive_file_move_rounded),
                            label: Text(
                              'Yanlış Dolaptakileri "${_shelfCtrl.text.trim()}" Yap (${report.wrongShelfCount})',
                            ),
                          ),
                        if (widget.onSaveInventorySession != null &&
                            report.sameShelfCount + report.wrongShelfCount > 0)
                          OutlinedButton.icon(
                            onPressed: _savingBatch
                                ? null
                                : () => _saveAsOfficialInventorySession(report),
                            icon: const Icon(Icons.fact_check_rounded),
                            label: const Text('Resmî Envanter Oturumuna Aktar'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Filtre Sekmeleri
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', 'Tümü (${report.items.length})'),
                  const SizedBox(width: 6),
                  _filterChip('new', 'Yeni (${report.newBookCount})'),
                  const SizedBox(width: 6),
                  _filterChip('wrong', 'Yanlış Dolap (${report.wrongShelfCount})'),
                  const SizedBox(width: 6),
                  _filterChip('same', 'Doğru Dolap (${report.sameShelfCount})'),
                  if (_shelfCtrl.text.trim().isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _filterChip(
                      'missing',
                      'Rafta Eksik / Ödünçte (${report.missingBooks.length})',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            if (_filter == 'missing')
              ..._buildMissingList(report)
            else
              for (final item in visibleItems) _buildDetectedTile(item),
          ],
        ],
      ),
    );
  }

  Widget _buildAnnotatedPhotoCard(ShelfComparisonReport report) {
    final photo = _photos[_selectedPhotoIdx];
    final photoSpines = report.items
        .where((i) => i.photoIndex == _selectedPhotoIdx && i.box2d != null)
        .toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${photo.label}${photo.sourceNote.isEmpty ? '' : ' · ${photo.sourceNote}'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tekrar analiz et',
                  onPressed: _analyzing
                      ? null
                      : () => _analyzePhotoIndexes([_selectedPhotoIdx]),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
                IconButton(
                  tooltip: _showBoxes
                      ? 'Sırt kutularını gizle'
                      : 'Sırt kutularını göster',
                  onPressed: () => setState(() => _showBoxes = !_showBoxes),
                  icon: Icon(
                    _showBoxes
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: photo.aspectRatio.clamp(0.55, 2.2),
            child: InteractiveViewer(
              maxScale: 4.0,
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(photo.bytes, fit: BoxFit.fill),
                      if (_showBoxes)
                        for (final sp in photoSpines)
                          Builder(
                            builder: (_) {
                              final b = sp.box2d!;
                              final top = (b[0] / 1000.0) * h;
                              final left = (b[1] / 1000.0) * w;
                              final bottom = (b[2] / 1000.0) * h;
                              final right = (b[3] / 1000.0) * w;
                              final color = _statusColor(sp.matchStatus);
                              final active = _highlightedSpineIndex == sp.index;
                              return Positioned(
                                top: top,
                                left: left,
                                width: (right - left).clamp(14.0, w),
                                height: (bottom - top).clamp(18.0, h),
                                child: GestureDetector(
                                  onTap: () {
                                    setState(
                                      () => _highlightedSpineIndex = sp.index,
                                    );
                                    _editDetectedSpine(sp);
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: color.withValues(
                                        alpha: active ? 0.34 : 0.16,
                                      ),
                                      border: Border.all(
                                        color: active ? Colors.white : color,
                                        width: active ? 2.4 : 1.5,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    alignment: Alignment.topCenter,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${sp.index}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiChip(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
                  color: color,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    return ChoiceChip(
      selected: _filter == key,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onSelected: (_) => setState(() => _filter = key),
    );
  }

  Widget _buildDetectedTile(DetectedShelfBook item) {
    final badgeColor = _statusColor(item.matchStatus);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: InkWell(
          onTap: () {
            setState(() {
              final pos = _rawDetections.indexWhere(
                (x) => x.index == item.index,
              );
              if (pos >= 0) {
                _rawDetections[pos] = _rawDetections[pos].copyWith(
                  selected: !_rawDetections[pos].selected,
                );
              }
            });
          },
          child: CircleAvatar(
            radius: 17,
            backgroundColor: item.selected
                ? badgeColor
                : Colors.grey.withValues(alpha: 0.35),
            child: Text(
              '${item.index}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        title: Text(
          item.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            if (item.author.isNotEmpty) item.author,
            if (item.publisher.isNotEmpty) item.publisher,
            'Adet: ${item.copiesCount}',
            item.matchStatus.label,
            if (item.matchedShelf.isNotEmpty) 'Kayıtlı: ${item.matchedShelf}',
            if (item.matchedAccession.isNotEmpty) item.matchedAccession,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Düzenle',
              onPressed: () => _editDetectedSpine(item),
              icon: const Icon(Icons.edit_rounded, size: 19),
            ),
            IconButton(
              tooltip: 'Listeden çıkar',
              onPressed: () {
                setState(() {
                  _rawDetections.removeWhere((x) => x.index == item.index);
                  _reindexDetections();
                });
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 19),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMissingList(ShelfComparisonReport report) {
    if (report.missingBooks.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: Text(
              'Bu dolaba kayıtlı tüm kitaplar fotoğrafta doğrulandı!',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ];
    }
    return [
      for (final m in report.missingBooks)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: BookCoverWidget(book: m.book, width: 38, height: 54),
            title: Text(
              (m.book['title'] ?? '').toString(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              [
                if ((m.book['author'] ?? '').toString().isNotEmpty)
                  (m.book['author'] ?? '').toString(),
                if ((m.book['accessionCode'] ?? '').toString().isNotEmpty)
                  (m.book['accessionCode'] ?? '').toString(),
                if (m.expectedOnShelf > 0)
                  'Rafta eksik: ${m.expectedOnShelf} adet',
                if (m.activeLoanCount > 0)
                  'Öğrencide ödünçte: ${m.activeLoanCount} adet',
              ].join(' · '),
            ),
          ),
        ),
    ];
  }
}
