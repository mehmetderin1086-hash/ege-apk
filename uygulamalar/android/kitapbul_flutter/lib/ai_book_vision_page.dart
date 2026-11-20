import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_proxy_service.dart';
import 'app_theme_settings.dart';
import 'book_lookup.dart';
import 'book_visuals.dart';
import 'catalog_search.dart' show foldTurkish;
import 'cover_fetch.dart';
import 'isbn.dart';
import 'loan_model.dart';
import 'ocr_extract.dart';
import 'school_automation_hub.dart' show findHighestAccessionNumber;

enum BookPhotoSlot {
  frontCover(
    'frontCover',
    '1. Ön Kapak',
    'Kitap adı, yazar, yayınevi logosu (Ön kapak görseli olarak kaydedilir)',
    Icons.book_rounded,
  ),
  insideFront(
    'insideFront',
    '2. Ön Kapak Sonrası Künye',
    'İç kapak / telif sayfası: ISBN, baskı sayısı, yayın yılı, çevirmen',
    Icons.article_rounded,
  ),
  beforeBack(
    'beforeBack',
    '3. Son Kapak Öncesi Sayfa',
    'Son yaprak / kolofon: toplam sayfa numarası, matbaa, dizin/içindekiler',
    Icons.last_page_rounded,
  ),
  backCover(
    'backCover',
    '4. Arka Kapak',
    'Arka kapak özeti, barkod ISBN ve kategori ipuçları (Arka kapak kaydedilir)',
    Icons.menu_book_rounded,
  );

  const BookPhotoSlot(this.id, this.title, this.subtitle, this.iconData);
  final String id;
  final String title;
  final String subtitle;
  final IconData iconData;
}

class _SlotIcons {
  static IconData of(BookPhotoSlot slot) {
    return switch (slot) {
      BookPhotoSlot.frontCover => Icons.book_rounded,
      BookPhotoSlot.insideFront => Icons.description_rounded,
      BookPhotoSlot.beforeBack => Icons.find_in_page_rounded,
      BookPhotoSlot.backCover => Icons.qr_code_2_rounded,
    };
  }
}

/// 4 sayfanın cihaz içi OCR sonuçlarını sayfa rollerine göre birleştirip
/// çevrimdışı/hibrit künye alanları üretir (birim testli saf mantık).
Map<String, String> extractFourPageLocalMetadata(
  Map<BookPhotoSlot, OcrDocument> docs,
) {
  final out = <String, String>{};
  final ocrPages = <OcrPage>[
    if (docs[BookPhotoSlot.frontCover] != null)
      OcrPage('Kapak', docs[BookPhotoSlot.frontCover]!),
    if (docs[BookPhotoSlot.insideFront] != null)
      OcrPage('Künye', docs[BookPhotoSlot.insideFront]!),
    if (docs[BookPhotoSlot.beforeBack] != null)
      OcrPage('Son Sayfa', docs[BookPhotoSlot.beforeBack]!),
    if (docs[BookPhotoSlot.backCover] != null)
      OcrPage('Arka Kapak', docs[BookPhotoSlot.backCover]!),
  ];

  for (final s in combineOcrSuggestions(ocrPages)) {
    out.putIfAbsent(s.suggestion.field, () => s.suggestion.value.trim());
  }

  // Künye ve Arka Kapak ISBN önceliği
  for (final slot in [
    BookPhotoSlot.insideFront,
    BookPhotoSlot.backCover,
    BookPhotoSlot.beforeBack,
    BookPhotoSlot.frontCover,
  ]) {
    final doc = docs[slot];
    if (doc == null) continue;
    final foundIsbns = isbnsInOcrLine(doc.text);
    if (foundIsbns.isNotEmpty) {
      out['isbn'] = foundIsbns.first;
      break;
    }
  }

  // 2. Sayfa (İç Künye): Çevirmen, Dizi/Seri, Dil
  final inside = docs[BookPhotoSlot.insideFront];
  if (inside != null) {
    for (final line in inside.lines) {
      final t = line.text.trim();
      final folded = foldTurkish(t);
      final trMatch = RegExp(
        r'^(?:çeviren|ceviren|çeviri|ceviri|tercüme|tercume)\s*[:：\-]?\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(t);
      if (trMatch != null && (trMatch.group(1) ?? '').trim().length >= 4) {
        out.putIfAbsent('translator', () => trMatch.group(1)!.trim());
      }
      if (folded.contains('dizi') || folded.contains('seri')) {
        final serMatch = RegExp(
          r'^(?:dizi|seri)\s*(?:adı|adi)?\s*[:：\-]\s*(.+)$',
          caseSensitive: false,
        ).firstMatch(t);
        if (serMatch != null && (serMatch.group(1) ?? '').trim().isNotEmpty) {
          out.putIfAbsent('series', () => serMatch.group(1)!.trim());
        }
      }
    }
  }

  // 3. Sayfa (Arka Kapak Öncesi Son Sayfa / Kolofon): Sayfa numarası ve basım yılı
  final beforeBack = docs[BookPhotoSlot.beforeBack];
  if (beforeBack != null) {
    if ((out['pageCount'] ?? '').isEmpty) {
      // Son yaprağın üst/alt köşesindeki tekil sayfa numarasını (ör. 248, 352) yakala
      int? bestPage;
      for (final line in beforeBack.lines) {
        final clean = line.text.trim();
        if (RegExp(r'^\d{2,4}$').hasMatch(clean)) {
          final n = int.tryParse(clean);
          if (n != null && n >= 24 && n <= 3500 && n != 1900 && (n < 1950 || n > 2035)) {
            if (bestPage == null || n > bestPage) bestPage = n;
          }
        }
      }
      if (bestPage != null) {
        out['pageCount'] = '$bestPage';
      }
    }
    if ((out['publicationYear'] ?? '').isEmpty) {
      final yr = RegExp(
        r'\b(19\d{2}|20[0-3]\d)\b',
      ).allMatches(beforeBack.text).lastOrNull?.group(1);
      if (yr != null) out['publicationYear'] = yr;
    }
  }

  // 4. Sayfa (Arka Kapak): Tanıtım / Özet yazısı
  final back = docs[BookPhotoSlot.backCover];
  if (back != null && (out['notes'] ?? '').isEmpty) {
    final proseLines = back.lines
        .map((l) => l.text.trim())
        .where(
          (t) =>
              t.length >= 22 &&
              !foldTurkish(t).contains('isbn') &&
              !t.contains('www.') &&
              !t.contains('http') &&
              !RegExp(r'^97[89][\d \-]+$').hasMatch(t),
        )
        .toList();
    if (proseLines.isNotEmpty) {
      final summary = proseLines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (summary.length >= 30) {
        out['notes'] = summary.length > 900
            ? '${summary.substring(0, 900)}…'
            : summary;
      }
    }
  }

  out.putIfAbsent('language', () => 'Türkçe');
  return out;
}

class FourPageBookScannerPage extends StatefulWidget {
  const FourPageBookScannerPage({
    super.key,
    required this.initialBooks,
    required this.onSaveBooks,
  });

  final List<Map<String, dynamic>> initialBooks;
  final Future<void> Function(List<Map<String, dynamic>> updated) onSaveBooks;

  @override
  State<FourPageBookScannerPage> createState() =>
      _FourPageBookScannerPageState();
}

class _FourPageBookScannerPageState extends State<FourPageBookScannerPage> {
  static const _camChannel = MethodChannel('kitapbul/camera');
  static const _fileChannel = MethodChannel('kitapbul/files');
  static const _ocrChannel = MethodChannel('kitapbul/ocr');

  // placeholder removed cleanly below
  late List<Map<String, dynamic>> _books = List.of(widget.initialBooks);
  final Map<BookPhotoSlot, Uint8List> _photos = {};
  final Map<BookPhotoSlot, OcrDocument> _localOcr = {};

  final _titleCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  final _publisherCtrl = TextEditingController();
  final _isbnCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _editionCtrl = TextEditingController();
  final _pageCountCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _languageCtrl = TextEditingController(text: 'Türkçe');
  final _readingLevelCtrl = TextEditingController();
  final _shelfCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController(text: '1');
  final _notesCtrl = TextEditingController();

  bool _analyzing = false;
  bool _saving = false;
  bool _autoAssignCal = true;
  String _analysisStatus = '';
  String _sourceBadge = '';
  int _savedSessionCount = 0;

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _authorCtrl,
      _publisherCtrl,
      _isbnCtrl,
      _yearCtrl,
      _editionCtrl,
      _pageCountCtrl,
      _categoryCtrl,
      _seriesCtrl,
      _languageCtrl,
      _readingLevelCtrl,
      _shelfCtrl,
      _quantityCtrl,
      _notesCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _captureSingleSlot(BookPhotoSlot slot, {required bool camera}) async {
    try {
      final bytes = camera
          ? await _camChannel.invokeMethod<Uint8List>('capture')
          : await _fileChannel.invokeMethod<Uint8List>('pickCover');
      if (bytes == null || bytes.isEmpty || !mounted) return;
      setState(() {
        _photos[slot] = bytes;
        _localOcr.remove(slot);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf alınamadı: $e')),
        );
      }
    }
  }

  Future<void> _captureFourSequentially() async {
    if (_analyzing || _saving) return;
    const orderedSlots = [
      BookPhotoSlot.frontCover,
      BookPhotoSlot.insideFront,
      BookPhotoSlot.beforeBack,
      BookPhotoSlot.backCover,
    ];
    for (final slot in orderedSlots) {
      if (!mounted) return;
      final go = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(_SlotIcons.of(slot), size: 34),
          title: Text(slot.title),
          content: Text(slot.subtitle),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'stop'),
              child: const Text('Çekimi Bitir & Analiz Et'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'skip'),
              child: const Text('Bu Sayfayı Atla'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'shoot'),
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Fotoğraf Çek'),
            ),
          ],
        ),
      );
      if (go == 'stop' || go == null) break;
      if (go == 'skip') continue;
      await _captureSingleSlot(slot, camera: true);
    }
    if (_photos.isNotEmpty && mounted) {
      await _analyzeCapturedPages();
    }
  }

  Future<void> _pickFourFromGallery() async {
    if (_analyzing || _saving) return;
    try {
      final picked = await _fileChannel.invokeMethod<List>('pickMultipleImages');
      if (picked == null || picked.isEmpty || !mounted) return;
      final byteList = picked.whereType<Uint8List>().toList();
      if (byteList.isEmpty) return;
      const ordered = [
        BookPhotoSlot.frontCover,
        BookPhotoSlot.insideFront,
        BookPhotoSlot.beforeBack,
        BookPhotoSlot.backCover,
      ];
      setState(() {
        for (var i = 0; i < byteList.length && i < ordered.length; i++) {
          _photos[ordered[i]] = byteList[i];
          _localOcr.remove(ordered[i]);
        }
      });
      await _analyzeCapturedPages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Çoklu galeri seçimi yapılamadı: $e')),
        );
      }
    }
  }

  Future<void> _analyzeCapturedPages() async {
    if (_photos.isEmpty || _analyzing) return;
    setState(() {
      _analyzing = true;
      _analysisStatus = '1/3 · Sayfalardaki metinler cihaz içi OCR ile taranıyor...';
    });

    final usedSources = <String>[];
    try {
      // 1. Her fotoğraf için yerel ML Kit OCR çalıştır
      for (final entry in _photos.entries) {
        if (_localOcr.containsKey(entry.key)) continue;
        try {
          final rawOcr = await _ocrChannel.invokeMethod<Object>('recognize', {
            'image': entry.value,
          });
          _localOcr[entry.key] = OcrDocument.fromPlatform(rawOcr);
        } catch (_) {}
      }

      final localFields = extractFourPageLocalMetadata(_localOcr);
      if (localFields.isNotEmpty) {
        usedSources.add('Yerel OCR');
      }

      // 2. Cep Telefonu CLIProxyAPI (127.0.0.1:8317) / Gemini 3.8 Flash Görsel Analizi
      Map<String, String> aiFields = {};
      if (mounted) {
        setState(() {
          _analysisStatus =
              '2/3 · CLIProxyAPI / Gemini 3.8 Flash kapak, künye ve son sayfayı çözümlüyor...';
        });
      }

      try {
        final imageParts = <AiImagePart>[
          for (final slot in [
            BookPhotoSlot.frontCover,
            BookPhotoSlot.insideFront,
            BookPhotoSlot.beforeBack,
            BookPhotoSlot.backCover,
          ])
            if (_photos[slot] != null)
              AiImagePart(
                bytes: _photos[slot]!,
                label: slot.title,
              ),
        ];

        final ocrHints = StringBuffer();
        for (final entry in _localOcr.entries) {
          final snippet = entry.value.text.trim();
          if (snippet.isNotEmpty) {
            ocrHints.writeln(
              '--- ${entry.key.title} Ham OCR ---\n'
              '${snippet.length > 1800 ? snippet.substring(0, 1800) : snippet}',
            );
          }
        }

        final aiJson = await AiProxyClient.generateStructuredJson(
          systemPrompt:
              'Sen uzman bir Türk okul kütüphanesi kataloglama yapay zekâsısın. '
              'Sana bir kitabın çekilmiş fotoğrafları (Ön Kapak, Ön Kapaktan Sonraki Künye Sayfası, '
              'Son Kapaktan Önceki Sayfa/Kolofon ve Arka Kapak) ile ham OCR ipuçları veriliyor. '
              'Çevirmeni veya editörü asla asıl yazar yerine yazma. Türkçe imla kurallarına (İ, ı, ğ, ü, ş, ö, ç) tam uy. '
              'Yalnızca geçerli JSON nesnesi döndür.',
          userPrompt:
              'Fotoğrafları ve aşağıdaki OCR ipuçlarını inceleyerek kitabın tüm künye bilgilerini çıkar:\n'
              '$ocrHints\n\n'
              'Tam olarak şu JSON alanlarıyla yanıt ver (bulunamayan alanlara "" yaz):\n'
              '{\n'
              '  "title": "Kitabın tam adı",\n'
              '  "author": "Asıl yazar(lar)",\n'
              '  "translator": "Çevirmen veya hazırlayan",\n'
              '  "publisher": "Yayınevi adı",\n'
              '  "isbn": "13 veya 10 haneli ISBN (sadece rakam/X)",\n'
              '  "publicationYear": "4 haneli basım yılı",\n'
              '  "edition": "Örn: 12. Baskı",\n'
              '  "pageCount": "Toplam sayfa sayısı (künyeden veya son sayfa numarasından, yalnız sayı)",\n'
              '  "category": "Kütüphane türü (Örn: Türk Edebiyatı, Dünya Edebiyatı, Roman, Tarih, Bilim, Felsefe, Şiir, Biyografi, Din, Ders Kitabı)",\n'
              '  "series": "Varsa dizi/seri adı",\n'
              '  "language": "Türkçe / İngilizce vb.",\n'
              '  "readingLevel": "Lise / Genel / Ortaokul vb.",\n'
              '  "summary": "Arka kapak tanıtım yazısının 2-4 cümlelik temiz özeti"\n'
              '}',
          images: imageParts,
        );

        if (aiJson is Map) {
          String strOf(String k) => (aiJson[k] ?? '').toString().trim();
          aiFields = {
            if (strOf('title').isNotEmpty) 'title': strOf('title'),
            if (strOf('author').isNotEmpty) 'author': strOf('author'),
            if (strOf('translator').isNotEmpty) 'translator': strOf('translator'),
            if (strOf('publisher').isNotEmpty) 'publisher': strOf('publisher'),
            if (strOf('isbn').isNotEmpty) 'isbn': cleanIsbnInput(strOf('isbn')),
            if (strOf('publicationYear').isNotEmpty)
              'publicationYear': strOf('publicationYear'),
            if (strOf('edition').isNotEmpty) 'edition': strOf('edition'),
            if (strOf('pageCount').isNotEmpty)
              'pageCount': strOf('pageCount').replaceAll(RegExp(r'[^0-9]'), ''),
            if (strOf('category').isNotEmpty) 'category': strOf('category'),
            if (strOf('series').isNotEmpty) 'series': strOf('series'),
            if (strOf('language').isNotEmpty) 'language': strOf('language'),
            if (strOf('readingLevel').isNotEmpty)
              'readingLevel': strOf('readingLevel'),
            if (strOf('summary').isNotEmpty) 'notes': strOf('summary'),
          };
          // Geçersiz ISBN üretildiyse yerel OCR'daki geçerli ISBN'i tercih et
          if (aiFields.containsKey('isbn') &&
              canonicalIsbn(aiFields['isbn']!) == null) {
            aiFields.remove('isbn');
          }
          if (aiFields.isNotEmpty) {
            usedSources.add('CLIProxy Gemini AI');
          }
        }
      } catch (aiErr) {
        // Çevrimdışı veya API anahtarı henüz girilmemişse yerel OCR ile devam edilir
        if (mounted && localFields.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Yapay zekâ uyarısı: $aiErr')),
          );
        }
      }

      // 3. İsteğe bağlı Amazon & Kitapyurdu Çapraz Zenginleştirme
      Map<String, String>? onlineFields;
      if (aiSettingsNotifier.value.autoEnrichOnline) {
        final candidateIsbn = canonicalIsbn(
          aiFields['isbn'] ?? localFields['isbn'] ?? _isbnCtrl.text,
        );
        final candidateTitle = aiFields['title'] ?? localFields['title'] ?? '';
        final candidateAuthor = aiFields['author'] ?? localFields['author'] ?? '';
        if (mounted && (candidateIsbn != null || candidateTitle.isNotEmpty)) {
          setState(() {
            _analysisStatus =
                '3/3 · Amazon & Kitapyurdu üzerinden künye çapraz doğrulanıyor...';
          });
        }
        try {
          if (candidateIsbn != null) {
            onlineFields = await lookupIsbn(candidateIsbn);
          } else if (candidateTitle.length >= 3) {
            onlineFields = await lookupKitapyurduFirstMatch(
              title: candidateTitle,
              author: candidateAuthor,
              publisher: aiFields['publisher'] ?? localFields['publisher'] ?? '',
            );
          }
          if (onlineFields != null && onlineFields.isNotEmpty) {
            usedSources.add(onlineFields['source'] ?? 'Çevrimiçi');
          }
        } catch (_) {}
      }

      // Alanları öncelik sırasıyla birleştir: AI -> Online -> Yerel OCR
      String pick(String key) {
        for (final map in [aiFields, onlineFields, localFields]) {
          final v = map?[key]?.trim() ?? '';
          if (v.isNotEmpty) return v;
        }
        return '';
      }

      void setIfFound(TextEditingController ctrl, String val) {
        if (val.isNotEmpty) ctrl.text = val;
      }

      setIfFound(_titleCtrl, pick('title'));
      setIfFound(_authorCtrl, pick('author'));
      setIfFound(_publisherCtrl, pick('publisher'));
      final bestIsbn = canonicalIsbn(pick('isbn')) ?? pick('isbn');
      setIfFound(_isbnCtrl, bestIsbn);
      setIfFound(_yearCtrl, pick('publicationYear'));
      setIfFound(_editionCtrl, pick('edition'));
      setIfFound(_pageCountCtrl, pick('pageCount'));
      setIfFound(_categoryCtrl, pick('category'));
      setIfFound(_seriesCtrl, pick('series'));
      setIfFound(_languageCtrl, pick('language'));
      setIfFound(_readingLevelCtrl, pick('readingLevel'));

      final translator = pick('translator');
      var notes = pick('notes');
      if (translator.isNotEmpty && !notes.contains(translator)) {
        notes = notes.isEmpty
            ? 'Çeviren / Hazırlayan: $translator'
            : 'Çeviren / Hazırlayan: $translator\n$notes';
      }
      setIfFound(_notesCtrl, notes);

      if (mounted) {
        setState(() {
          _sourceBadge = usedSources.isEmpty
              ? 'Metin bulunamadı — alanları elle kontrol edin'
              : 'Otomatik Dolduruldu: ${usedSources.join(' + ')}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _analysisStatus = '';
        });
      }
    }
  }

  Future<void> _saveCurrentBook({required bool clearForNext}) async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en azından Kitap Adı alanını doldurun.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final cfg = appThemeNotifier.value;
      final qty = (int.tryParse(_quantityCtrl.text.trim()) ?? 1).clamp(1, 100);
      var nextAcc =
          findHighestAccessionNumber(_books, prefix: cfg.accessionPrefix) + 1;
      final codes = _autoAssignCal
          ? <String>[
              for (var i = 0; i < qty; i++)
                '${cfg.accessionPrefix}${(nextAcc++).toString().padLeft(cfg.accessionDigits, '0')}',
            ]
          : const <String>[];

      String? frontRef;
      String? insideRef;
      String? backRef;
      if (_photos[BookPhotoSlot.frontCover] != null) {
        frontRef = storeCoverBytes(_photos[BookPhotoSlot.frontCover]!);
      }
      if (_photos[BookPhotoSlot.insideFront] != null) {
        insideRef = storeCoverBytes(_photos[BookPhotoSlot.insideFront]!);
      }
      if (_photos[BookPhotoSlot.backCover] != null) {
        backRef = storeCoverBytes(_photos[BookPhotoSlot.backCover]!);
      }

      // Ön kapak fotoğrafı çekilmemiş ama ISBN varsa kapak indir
      final cleanIsbn = canonicalIsbn(_isbnCtrl.text.trim()) ?? _isbnCtrl.text.trim();
      if (frontRef == null && isValidIsbn(cleanIsbn) && cleanIsbn.isNotEmpty) {
        try {
          final dl = await fetchBestCover(cleanIsbn);
          if (dl != null) frontRef = storeCoverBytes(dl.bytes);
        } catch (_) {}
      }

      final now = DateTime.now();
      final newBook = normalizeBook({
        'id': 'vision-${now.microsecondsSinceEpoch}',
        'title': title,
        'author': _authorCtrl.text.trim(),
        'publisher': _publisherCtrl.text.trim(),
        'isbn': cleanIsbn,
        'publicationYear': _yearCtrl.text.trim(),
        'edition': _editionCtrl.text.trim(),
        'pageCount': _pageCountCtrl.text.trim(),
        'category': _categoryCtrl.text.trim(),
        'series': _seriesCtrl.text.trim(),
        'language': _languageCtrl.text.trim(),
        'readingLevel': _readingLevelCtrl.text.trim(),
        'shelf': _shelfCtrl.text.trim(),
        'accessionCode': codes.join('; '),
        'quantity': qty,
        'notes': _notesCtrl.text.trim(),
        'coverBase64': frontRef,
        'imprintBase64': insideRef,
        'backCoverBase64': backRef,
        'loans': <Map<String, dynamic>>[],
      });

      final updated = [..._books, newBook];
      await widget.onSaveBooks(updated);
      _books = updated;
      _savedSessionCount++;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"$title" kaydedildi${codes.isNotEmpty ? ' (${codes.first})' : ''}.',
          ),
        ),
      );

      if (clearForNext) {
        setState(() {
          _photos.clear();
          _localOcr.clear();
          _titleCtrl.clear();
          _authorCtrl.clear();
          _publisherCtrl.clear();
          _isbnCtrl.clear();
          _yearCtrl.clear();
          _editionCtrl.clear();
          _pageCountCtrl.clear();
          _categoryCtrl.clear();
          _seriesCtrl.clear();
          _readingLevelCtrl.clear();
          _notesCtrl.clear();
          _quantityCtrl.text = '1';
          _sourceBadge = '';
        });
      } else {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _savedSessionCount > 0
              ? '4-Sayfa Akıllı Kitap OCR ($_savedSessionCount)'
              : '4-Sayfa Akıllı Kitap OCR',
        ),
        actions: [
          IconButton(
            tooltip: 'CLIProxyAPI & Gemini Ayarları',
            onPressed: () => showAiProxySettingsSheet(context),
            icon: const Icon(Icons.hub_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
        children: [
          IllustratedBannerCard(
            imageAsset: 'assets/images/ai_vision_banner.jpg',
            title: 'Kapak + Künye + Son Sayfa + Arka Kapak OCR',
            subtitle:
                'Ön kapak, ön kapak arkası künye, son kapak öncesi sayfa ve arka kapağı çekin; CLIProxyAPI Gemini 3.8 Flash + OCR tüm künyeyi otomatik doldursun.',
            icon: Icons.document_scanner_rounded,
            pills: [
              AnimatedStatPill(
                label: 'Hazır Sayfa',
                value: _photos.length,
                icon: Icons.camera_alt_rounded,
                accentColor: const Color(0xFFFDE68A),
              ),
              AnimatedStatPill(
                label: 'Kaydedilen',
                value: _savedSessionCount,
                icon: Icons.check_circle_rounded,
                accentColor: const Color(0xFF6EE7B7),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _analyzing ? null : _captureFourSequentially,
                  icon: const Icon(Icons.photo_camera_front_rounded),
                  label: const Text('4 Sayfayı Sırayla Çek'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _analyzing ? null : _pickFourFromGallery,
                  icon: const Icon(Icons.collections_rounded),
                  label: const Text('Galeriden Çoklu Seç'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 4 Fotoğraf Kartı Izgarası (2×2)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.92,
            children: [
              for (final slot in [
                BookPhotoSlot.frontCover,
                BookPhotoSlot.insideFront,
                BookPhotoSlot.beforeBack,
                BookPhotoSlot.backCover,
              ])
                _buildSlotCard(slot, scheme),
            ],
          ),

          const SizedBox(height: 12),
          if (_analyzing)
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
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
                        _analysisStatus,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_photos.isNotEmpty)
            ShimmerActionButton(
              label: 'Fotoğrafları Oku & Künyeyi Otomatik Doldur',
              subtitle:
                  'CLIProxyAPI (${aiSettingsNotifier.value.visionModel}) + Yerel OCR + Amazon',
              icon: Icons.auto_awesome_rounded,
              colors: const [Color(0xFF4F46E5), Color(0xFF9333EA)],
              onTap: _analyzeCapturedPages,
            ),

          if (_sourceBadge.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade600),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.verified_rounded,
                    size: 18,
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _sourceBadge,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          const Text(
            'Otomatik Doldurulan Kitap Künyesi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Kitap Adı *',
              prefixIcon: Icon(Icons.menu_book_rounded),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _authorCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Yazar',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _publisherCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Yayınevi',
                    prefixIcon: Icon(Icons.business_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _isbnCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'ISBN',
                    prefixIcon: Icon(Icons.qr_code_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _pageCountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Sayfa Sayısı',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _yearCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Basım Yılı',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _editionCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Baskı (Örn: 5. Baskı)',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _categoryCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Kategori / Tür',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _seriesCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Dizi / Seri',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _shelfCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Dolap / Raf (A–N)',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _quantityCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Nüsha Adedi',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _languageCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Dil',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Arka Kapak Özeti / Çevirmen / Notlar',
            ),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Otomatik ${appThemeNotifier.value.accessionPrefix} demirbaş numarası ata',
            ),
            value: _autoAssignCal,
            onChanged: (v) => setState(() => _autoAssignCal = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _saveCurrentBook(clearForNext: false),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Kaydet & Çık'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _saveCurrentBook(clearForNext: true),
                  icon: const Icon(Icons.add_a_photo_rounded),
                  label: const Text('Kaydet & Yeni Kitaba Geç'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard(BookPhotoSlot slot, ColorScheme scheme) {
    final bytes = _photos[slot];
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: bytes != null
              ? scheme.primary.withValues(alpha: 0.7)
              : scheme.outlineVariant,
          width: bytes != null ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: bytes != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 400),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black54,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 15,
                            color: Colors.white,
                            onPressed: () => setState(() {
                              _photos.remove(slot);
                              _localOcr.remove(slot);
                            }),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _SlotIcons.of(slot),
                          size: 28,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          slot.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          slot.subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Container(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: _analyzing
                      ? null
                      : () => _captureSingleSlot(slot, camera: true),
                  icon: const Icon(Icons.camera_alt_rounded, size: 15),
                  label: const Text('Çek', style: TextStyle(fontSize: 11.5)),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: _analyzing
                      ? null
                      : () => _captureSingleSlot(slot, camera: false),
                  icon: const Icon(Icons.photo_library_rounded, size: 15),
                  label: const Text('Galeri', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
